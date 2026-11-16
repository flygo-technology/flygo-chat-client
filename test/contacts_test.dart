// Danh bạ khách: đọc file nhập (CSV, Excel, vCard), đoán cột; danh sách, chi tiết, form thêm với backend giả.
// Ảnh xem trước (chạy tay): CT_OUT=<thư mục> flutter test test/contacts_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/ui/contacts/api.dart';
import 'package:flygo_chat/ui/contacts/contact_edit.dart';
import 'package:flygo_chat/ui/contacts/contact_page.dart';
import 'package:flygo_chat/ui/contacts/contacts_view.dart';
import 'package:flygo_chat/ui/contacts/import_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> _fonts() async {
  Future<void> load(String family, List<File> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      if (f.existsSync()) l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await l.load();
  }

  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  await load('MaterialIcons', [File('$dir/MaterialIcons-Regular.otf')]);
  await load('Noto Sans', [
    for (final f in ['noto/NotoSans-Regular.ttf', 'noto/NotoSans-Bold.ttf', 'dejavu/DejaVuSans.ttf', 'dejavu/DejaVuSans-Bold.ttf']) File('/usr/share/fonts/truetype/$f'),
  ]);
}

final _now = DateTime.now().millisecondsSinceEpoch;
const _me = {
  'user': {'id': 'lan', 'name': 'Lan', 'username': 'lan'},
  'admin': true,
  'manager': true,
  'my_depts': [{'id': 'kdhn', 'name': 'KD HN'}],
  'depts': [{'id': 'kdhn', 'name': 'KD HN', 'parent': null}, {'id': 'kt', 'name': 'Kế toán HN', 'parent': null}],
};
Map<String, dynamic> _c(String id, String kind, String name, {String tax = '', List<String> types = const ['customer'], String phone = '', String address = '', int people = 0,
        String owner = 'Lan', String scope = 'dept', List<Map<String, dynamic>> companies = const [], String job = '', int? last, String? lastKind}) =>
    {
      'id': id, 'kind': kind, 'name': name, 'tax_id': tax, 'types': types, 'tags': <String>[], 'phone': phone, 'email': '', 'address': address, 'country': '',
      'job_title': job, 'companies': companies, 'people_count': people, 'status': 'active', 'owner': {'id': owner.toLowerCase(), 'name': owner, 'inactive': false},
      'scope': scope, 'dept': 'kdhn', 'dept_name': 'KD HN', 'last_at': last, 'last_kind': lastKind, 'updated_at': _now, 'can_edit': true,
    };
final _list = [
  _c('c-thanhdat', 'company', 'Công ty TNHH Xây dựng Thành Đạt', tax: '0101234567', address: '12 Láng Hạ, Đống Đa, Hà Nội', people: 3, last: _now - 86400000, lastKind: 'payment'),
  _c('p-tuan', 'person', 'Nguyễn Văn Tuấn', phone: '0912 345 678', job: 'PM công trình', companies: [{'id': 'c-thanhdat', 'name': 'Thành Đạt', 'role': 'PM', 'left': false}]),
  _c('c-ningbo', 'company', 'Ningbo Lift Parts Co., Ltd.', types: ['supplier'], owner: 'Kho', scope: 'company')..['country'] = 'Trung Quốc',
  _c('c-ankhang', 'company', 'Công ty CP Đầu tư An Khang', tax: '0312345678', types: ['lead'], address: 'Quận 1, TP.HCM', owner: 'Hùng'),
  _c('p-bich', 'person', 'Chị Bích – chủ nhà Ecopark', phone: '0987 654 321', scope: 'private'),
  _c('c-binhminh', 'company', 'Bảo trì Thang máy Bình Minh', types: ['partner'], address: 'Bắc Ninh', scope: 'company'),
];
Map<String, dynamic> _full() => {
      ..._list.first,
      'full_name': 'CÔNG TY TNHH XÂY DỰNG THÀNH ĐẠT',
      'phones': [{'v': '024 3826 1234', 'label': '', 'pretty': '024 3826 1234'}],
      'emails': [{'v': 'ketoan@thanhdat.vn', 'label': ''}],
      'addresses': [{'v': '12 Láng Hạ, Đống Đa, Hà Nội', 'label': 'Xuất HĐ'}],
      'tags': ['Công trình HN', 'VIP'],
      'website': '', 'salutation': '', 'zalo': '', 'wechat': '', 'currency': '', 'invoice_email': 'ketoan@thanhdat.vn', 'birthday': '', 'source': 'Giới thiệu', 'notes': '',
      'external_ids': {'3tsoft': 'KH-00218'}, 'helpers': [{'id': 'ha', 'name': 'Hà'}], 'created_by': {'id': 'lan', 'name': 'Lan'}, 'created_at': _now, 'version': 3,
      'shares': [{'type': 'dept', 'id': 'kt', 'level': 'view', 'name': 'Kế toán HN'}],
      'people': [
        {..._list[1], 'role': 'PM công trình', 'left': false},
        {..._c('p-ha', 'person', 'Trần Thu Hà', phone: '0903 111 222'), 'role': 'Kế toán', 'left': false},
      ],
      'timeline': [
        {'id': 't1', 'kind': 'payment', 'at': _now - 86400000, 'summary': 'Báo có 120.000.000 đ', 'link': '', 'via': 'system', 'actor': {'id': 'ha', 'name': 'Hà'}},
        {'id': 't2', 'kind': 'invoice', 'at': _now - 3 * 86400000, 'summary': 'Hoá đơn 0001234 – 120 tr', 'link': '', 'via': null, 'actor': {'id': 'ha', 'name': 'Hà'}},
        {'id': 't3', 'kind': 'meeting', 'at': _now - 7 * 86400000, 'summary': 'Họp khảo sát công trình với anh Tuấn', 'link': '', 'via': null, 'actor': {'id': 'lan', 'name': 'Lan'}},
        {'id': 't4', 'kind': 'mail', 'at': _now - 8 * 86400000, 'summary': 'Mail: “Báo giá cáp tải 8 thang”', 'link': '', 'via': 'agent ketoan', 'actor': {'id': 'lan', 'name': 'Lan'}},
      ],
    };

class FakeBackend {
  final calls = <String>[];
  Map<String, dynamic>? lastBody;
  http.Client client() => MockClient((req) async {
        final p = req.url.path;
        if (p == '/v1/token') return http.Response(jsonEncode({'token': 'tk', 'expires_in': 600, 'scope': ['use']}), 200, headers: {'content-type': 'application/json'});
        calls.add('${req.method} $p');
        if (req.body.isNotEmpty) lastBody = jsonDecode(req.body) as Map<String, dynamic>;
        Object? body;
        if (p == '/ct/api/me') body = _me;
        if (p == '/ct/api/counts') {
          body = {'all': 6, 'mine': 4, 'private': 1, 'company': 2, 'orphans': 0, 'duplicates': 2, 'types': {'customer': 3, 'lead': 1, 'supplier': 1, 'partner': 1}, 'tags': {},
            'depts': [{'id': 'kdhn', 'name': 'KD HN', 'count': 3}]};
        }
        if (p == '/ct/api/contacts' && req.method == 'GET') {
          final q = req.url.queryParameters['q'] ?? '';
          final rows = _list.where((c) => q.isEmpty || '${c['name']}'.toLowerCase().contains(q.toLowerCase())).toList();
          body = {'total': rows.length, 'contacts': rows};
        }
        if (p == '/ct/api/contacts' && req.method == 'POST') body = {'contact': {..._full(), 'id': 'c-new', 'name': lastBody!['name']}};
        if (p == '/ct/api/contacts/c-thanhdat') body = {'contact': _full()};
        if (p == '/ct/api/check') {
          final phones = (lastBody!['phones'] as List).map((e) => '$e'.replaceAll(' ', ''));
          body = {'matches': phones.contains('0912345678') ? [{'id': 'p-tuan', 'visible': false, 'owner': 'hung', 'owner_name': 'Hùng', 'by': 'phone'}] : []};
        }
        if (p == '/ct/api/tax/0109876543') {
          body = {'info': {'tax_id': '0109876543', 'name': 'CÔNG TY CP THANG MÁY PHƯƠNG NAM', 'address': '45 Nguyễn Trãi, Thanh Xuân, Hà Nội', 'status': 'NNT đang hoạt động', 'active': true}, 'matches': []};
        }
        return body == null ? http.Response('{"error":"không có"}', 404) : http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
      });
}

void main() {
  final out = Platform.environment['CT_OUT'];

  group('đọc file nhập', () {
    test('CSV: dấu chấm phẩy, ngoặc kép, BOM, dòng trống', () {
      final rows = parseCsv('﻿Tên KH;MST;ĐT\n"Cty ""A""; B";0101234567;0912.345.678\n\nCty C;;"0243 / 0912"\r\n');
      expect(rows, [
        ['Tên KH', 'MST', 'ĐT'],
        ['Cty "A"; B', '0101234567', '0912.345.678'],
        ['Cty C', '', '0243 / 0912'],
      ]);
    });

    test('đoán cột theo tiêu đề tiếng Việt', () {
      expect(guessField('Tên khách hàng'), 'name');
      expect(guessField('Mã số thuế'), 'tax_id');
      expect(guessField('SĐT'), 'phone');
      expect(guessField('Người LH'), 'contact_name');
      expect(guessField('ĐT người liên hệ'), 'contact_phone');
      expect(guessField('Đ/c'), 'address');
      expect(guessField('Sales'), 'owner');
      expect(guessField('Mã KH'), 'external_id');
      expect(guessField('Cột trống'), 'skip');
    });

    test('Excel: chuỗi dùng chung, ô số, ô trống giữa dòng', () {
      final a = Archive()
        ..add(ArchiveFile.string('xl/workbook.xml', '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="KH" sheetId="1" r:id="rId1"/></sheets></workbook>'))
        ..add(ArchiveFile.string('xl/_rels/workbook.xml.rels', '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'))
        ..add(ArchiveFile.string('xl/sharedStrings.xml', '<sst><si><t>Tên</t></si><si><t>MST</t></si><si><r><t>Cty </t></r><r><t>Thành Đạt</t></r></si></sst>'))
        ..add(ArchiveFile.string('xl/worksheets/sheet1.xml',
            '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><v>101234567.0</v></c></row></sheetData></worksheet>'));
      final rows = parseXlsx(Uint8List.fromList(ZipEncoder().encode(a)));
      expect(rows, [
        ['Tên', '', 'MST'],
        ['Cty Thành Đạt', '', '101234567'],
      ]);
    });

    test('vCard: có ORG thành công ty + người liên hệ, không thì khách lẻ; dòng gập', () {
      final rows = parseVcf('BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Nguyễn Văn Tuấn\r\nORG:Thành Đạt;Kỹ thuật\r\nTITLE:PM\r\nTEL;TYPE=CELL:0912 345 678\r\nEMAIL:tuan@thanhdat.vn\r\nEND:VCARD\r\n'
          'BEGIN:VCARD\nVERSION:3.0\nN:Bích;Chị;;;\nTEL:0987\n 654321\nADR;TYPE=HOME:;;Ecopark;Văn Giang;Hưng Yên;;\nEND:VCARD\n');
      expect(rows[0], {'kind': 'company', 'name': 'Thành Đạt', 'contact_name': 'Nguyễn Văn Tuấn', 'contact_phone': ['0912 345 678'], 'contact_email': ['tuan@thanhdat.vn'], 'contact_title': 'PM', 'address': []});
      expect(rows[1]['kind'], 'person');
      expect(rows[1]['name'], 'Chị Bích');
      expect(rows[1]['phones'], ['0987654321']);
      expect(rows[1]['address'], ['Ecopark, Văn Giang, Hưng Yên']);
    });
  });

  late FakeBackend be;
  ContactsApi api() {
    final c = be.client();
    return ContactsApi(base: 'https://chat.test/ct', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: c), client: c);
  }

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester t, Widget child, {Size size = const Size(400, 860), Brightness theme = Brightness.light}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    if (out != null) await t.runAsync(_fonts);
    await t.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(theme), home: child)));
    await settle(t);
    await settle(t, 3);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  setUp(() => be = FakeBackend());

  testWidgets('điện thoại: danh sách khách, lọc, tìm', (t) async {
    await pump(t, Scaffold(appBar: AppBar(title: const Text('Danh bạ')), body: ContactsView(api: api())));
    expect(find.text('Công ty TNHH Xây dựng Thành Đạt'), findsOneWidget);
    expect(find.text('Nguyễn Văn Tuấn'), findsOneWidget);
    expect(find.text('MST 0101234567 · Hà Nội · 3 người liên hệ'), findsOneWidget);
    expect(find.text('PM công trình – Thành Đạt · 0912 345 678'), findsOneWidget);
    expect(find.text('Có thể trùng · 2'), findsOneWidget); // quản lý danh bạ thấy hàng chờ
    await shot(t, 'ct-1-danh-sach');
    await t.tap(find.widgetWithText(ChoiceChip, 'Nhà cung cấp'));
    await settle(t);
    expect(be.calls.last, 'GET /ct/api/counts');
    expect(be.calls.any((c) => c == 'GET /ct/api/contacts'), isTrue);
    await t.enterText(find.byType(TextField), 'ningbo');
    await settle(t, 6);
    expect(find.text('Công ty TNHH Xây dựng Thành Đạt'), findsNothing);
    expect(find.text('Ningbo Lift Parts Co., Ltd.'), findsOneWidget);
  });

  testWidgets('chi tiết công ty: nút nhanh, thông tin, người liên hệ, dòng thời gian', (t) async {
    await pump(t, ContactPage(api: api(), id: 'c-thanhdat', me: _me), size: const Size(400, 1500));
    expect(find.text('Gọi'), findsOneWidget);
    expect(find.text('Zalo'), findsOneWidget);
    expect(find.text('Lan · hỗ trợ: Hà'), findsOneWidget);
    expect(find.text('Phòng KD HN · +Kế toán HN'), findsOneWidget);
    expect(find.text('KH-00218'), findsOneWidget);
    expect(find.text('Người liên hệ (2)'), findsOneWidget);
    expect(find.text('Báo có 120.000.000 đ'), findsOneWidget);
    await shot(t, 'ct-2-chi-tiet');
  });

  testWidgets('máy tính: ba cột, bấm liên hệ hiện chi tiết bên phải', (t) async {
    await pump(t, Scaffold(body: ContactsView(api: api())), size: const Size(1360, 820));
    expect(find.text('Chọn một liên hệ để xem'), findsOneWidget);
    expect(find.text('Của người đã nghỉ'), findsOneWidget);
    await t.tap(find.text('Công ty TNHH Xây dựng Thành Đạt').first);
    await settle(t);
    await shot(t, 'ct-3-may-tinh');
    expect(find.text('Người liên hệ (2)'), findsOneWidget);
  });

  testWidgets('thêm công ty: tra MST tự điền, báo trùng số điện thoại khi gõ', (t) async {
    await pump(t, ContactEditPage(api: api(), me: _me, kind: 'company'), size: const Size(400, 1200));
    await t.enterText(find.byType(TextField).first, '0109876543');
    await t.tap(find.text('Tra MST'));
    await settle(t);
    expect(find.text('Đã tự điền tên và địa chỉ theo MST · đang hoạt động'), findsOneWidget);
    expect(find.text('CÔNG TY CP THANG MÁY PHƯƠNG NAM'), findsOneWidget);
    expect(find.text('Công Ty CP Thang Máy Phương Nam'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, '').at(0), '0912 345 678');
    await t.pump(const Duration(milliseconds: 700));
    await settle(t);
    expect(find.textContaining('do Hùng phụ trách'), findsOneWidget);
    expect(find.text('Xin chia sẻ'), findsOneWidget);
    await shot(t, 'ct-4-them-cong-ty');
    await t.tap(find.text('Lưu'));
    await settle(t);
    expect(be.lastBody!['tax_id'], '0109876543');
    expect(be.lastBody!['scope'], 'dept');
    expect(be.lastBody!['dept'], 'kdhn');
  });
}
