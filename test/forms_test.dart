// Biểu mẫu: logic (rẽ nhánh, kiểm câu trả lời, dựng quy trình Flows), trang chủ, trình soạn (lưu tự động kèm base),
// trang điền (lỗi, rẽ nhánh, gửi), câu trả lời, chia sẻ, cài đặt, tự động hoá — với backend giả.
// Ảnh xem trước (chạy tay): FM_OUT=<thư mục> flutter test test/forms_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/forms/api.dart';
import 'package:flygo_chat/ui/forms/automation_tab.dart';
import 'package:flygo_chat/ui/forms/editor_page.dart';
import 'package:flygo_chat/ui/forms/fill_page.dart';
import 'package:flygo_chat/ui/forms/home_page.dart';
import 'package:flygo_chat/ui/forms/model.dart';
import 'package:flygo_chat/ui/forms/share_sheet.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _schema = {
  'sections': [
    {
      'id': 'sec1',
      'items': [
        {'id': 'q1', 'type': 'short', 'key': 'ho_va_ten', 'title': 'Họ và tên', 'required': true},
        {'id': 'q2', 'type': 'short', 'key': 'so_dien_thoai', 'title': 'Số điện thoại', 'validation': {'kind': 'phone'}},
        {'id': 'q3', 'type': 'scale', 'key': 'diem', 'title': 'Mức độ hài lòng chung', 'required': true, 'scale': {'min': 1, 'max': 5, 'min_label': 'Rất không hài lòng', 'max_label': 'Rất hài lòng'}},
        {
          'id': 'q4', 'type': 'choice', 'key': 'gioi_thieu', 'title': 'Anh/chị có giới thiệu dịch vụ cho người quen không?',
          'options': [{'id': 'o1', 'label': 'Có, chắc chắn'}, {'id': 'o2', 'label': 'Có thể'}, {'id': 'o3', 'label': 'Không', 'goto': 'sec2'}],
        },
        {'id': 'q5', 'type': 'checkbox', 'key': 'dich_vu', 'title': 'Anh/chị đã dùng những dịch vụ nào?', 'options': [{'id': 'c1', 'label': 'Lắp đặt mới'}, {'id': 'c2', 'label': 'Bảo trì định kỳ'}, {'id': 'c3', 'label': 'Sửa chữa khẩn cấp'}], 'other': true},
      ],
    },
    {'id': 'sec2', 'title': 'Góp ý', 'items': [{'id': 'q6', 'type': 'paragraph', 'key': 'gop_y', 'title': 'Góp ý thêm', 'required': true}]},
  ],
};

Map<String, dynamic> _form({String role = 'owner', String access = 'public'}) => {
      'id': 'form0001', 'title': 'Khảo sát hài lòng khách hàng — Quý 4',
      'description': 'Cảm ơn anh/chị đã sử dụng dịch vụ. Khảo sát mất khoảng 2 phút, câu trả lời giúp chúng tôi phục vụ tốt hơn.',
      'theme': '#0F8B8D', 'schema': _schema, 'status': 'open', 'version': 3, 'accepting': true, 'closed_reason': null,
      'settings': {
        'access': access, 'audience': {'everyone': true, 'users': [], 'depts': [], 'roles': []}, 'collect_identity': true, 'one_per_user': true, 'allow_edit': false,
        'close_at': DateTime(2026, 11, 30, 23, 59).millisecondsSinceEpoch, 'max_responses': 500, 'closed_message': 'Đã đóng.', 'confirmation': 'Đã ghi nhận câu trả lời. Cảm ơn anh/chị!',
        'show_summary': false, 'progress': true, 'shuffle': false, 'public_uploads': false, 'per_hour': 300,
        'notify': {'dm': true, 'channel': 'chan0001', 'when': null}, 'flows': [{'id': 'h1', 'mode': 'form', 'enabled': true, 'when': null}],
        'todo': {'enabled': true, 'assignee': 'nam00001', 'title': 'Gọi lại {{ho_va_ten}}', 'when': null},
      },
      'owner': {'id': 'me000001', 'name': 'Bạn'},
      'members': [{'kind': 'dept', 'ref': 'cskh', 'role': 'viewer', 'name': 'Phòng CSKH'}, {'kind': 'user', 'ref': 'lan00001', 'role': 'editor', 'name': 'Lan'}],
      'audience_names': {}, 'todo_assignee_name': 'Nam', 'role': role, 'link': 'https://chat.example.com/__apps/forms/f/k7Qm2xR9', 'token': 'k7Qm2xR9',
      'responses': 128, 'last_response_at': 0, 'created_at': 0, 'updated_at': 0,
    };

final _summary = {
  'total': 128,
  'questions': [
    {'key': 'ho_va_ten', 'title': 'Họ và tên', 'type': 'short', 'answered': 128, 'samples': ['Trần Minh Anh', 'Lê Thu Hà', 'Phạm Quốc Bảo']},
    {'key': 'diem', 'title': 'Mức độ hài lòng chung', 'type': 'scale', 'answered': 128, 'avg': 4.16, 'counts': [for (final (i, n) in const [3, 6, 14, 48, 57].indexed) {'label': '${i + 1}', 'n': n}]},
    {'key': 'gioi_thieu', 'title': 'Anh/chị có giới thiệu dịch vụ cho người quen không?', 'type': 'choice', 'answered': 126, 'counts': [{'label': 'Có, chắc chắn', 'n': 71}, {'label': 'Có thể', 'n': 41}, {'label': 'Không', 'n': 14}]},
    {'key': 'dich_vu', 'title': 'Anh/chị đã dùng những dịch vụ nào?', 'type': 'checkbox', 'answered': 121, 'counts': [{'label': 'Lắp đặt mới', 'n': 52}, {'label': 'Bảo trì định kỳ', 'n': 96}, {'label': 'Sửa chữa khẩn cấp', 'n': 23}], 'other': 6},
    {'key': 'gop_y', 'title': 'Góp ý thêm', 'type': 'paragraph', 'answered': 14, 'samples': ['Kỹ thuật viên đến đúng giờ, làm việc cẩn thận.', 'Mong có thêm kênh báo sự cố qua chat.']},
  ],
};

class FakeBackend {
  final calls = <(String, String, dynamic)>[];
  Map<String, dynamic> form = _form();
  List<Map<String, dynamic>> flows = [
    {
      'id': 'bm-1', 'name': 'Xử lý phản hồi khách hàng', 'version': 2, 'active': true, 'runs': 31, 'errors': 0, 'updated_by': 'me000001',
      'def': buildDef(id: 'bm-1', name: 'Xử lý phản hồi khách hàng', schema: _schema, owner: 'me000001', steps: [
        FlowStep('condition', {'key': 'diem', 'op': '<=', 'value': '2'}),
        FlowStep('send', {'to': r'$owner', 'text': 'Khách {{form.ho_va_ten}} chấm {{form.diem}}/5 — cần gọi lại'}),
        FlowStep('task', {'title': 'Gọi lại khách', 'assignee': {'user': 'nam00001'}, 'fields': [{'key': 'ket_qua', 'label': 'Kết quả gọi lại', 'type': 'textarea'}]}),
        FlowStep('approval', {'title': 'Trưởng phòng CSKH duyệt bồi hoàn', 'approver': {'user': 'tp000001'}}),
      ]),
    },
  ];

  http.Client client() => MockClient((req) async {
        final p = req.url.path;
        final body = req.body.isEmpty ? null : (req.headers['content-type']?.contains('json') == true ? jsonDecode(req.body) : null);
        calls.add((req.method, p, body));
        Object? out;
        if (p == '/v1/token') out = {'token': 'tk', 'expires_in': 600, 'scope': ['use']};
        if (p == '/fm/api/me') {
          out = {'user': {'id': 'me000001', 'name': 'Bạn'}, 'features': {'flows': true, 'todo': true}, 'templates': [
            {'id': 'blank', 'name': 'Trống', 'icon': 'add', 'color': '#1E7BFF'}, {'id': 'event', 'name': 'Đăng ký sự kiện', 'icon': 'event_available', 'color': '#5B6CC4'},
            {'id': 'satisfaction', 'name': 'Khảo sát hài lòng', 'icon': 'sentiment_satisfied_alt', 'color': '#0F8B8D'}, {'id': 'leave', 'name': 'Đơn xin nghỉ phép', 'icon': 'beach_access', 'color': '#E4A11B'},
            {'id': 'feedback', 'name': 'Phiếu góp ý', 'icon': 'forum', 'color': '#D9534F'},
          ]};
        }
        if (p == '/fm/api/forms' && req.method == 'GET') {
          out = {'forms': [
            for (final f in [
              ('form0001', 'Khảo sát hài lòng khách hàng — Quý 4', '#0F8B8D', 'open', true, 'public', 128, true),
              ('form0002', 'Đăng ký tiệc tất niên 2026', '#5B6CC4', 'open', true, 'internal', 46, false),
              ('form0003', 'Đánh giá nhà cung cấp', '#E4A11B', 'closed', false, 'internal', 9, false),
              ('form0004', 'Phiếu đề xuất cải tiến', '#455A64', 'draft', false, 'internal', 0, false),
              ('form0005', 'Kiểm tra an toàn công trình', '#D9534F', 'open', true, 'internal', 31, true),
              ('form0006', 'Đăng ký đồng phục', '#2E7D32', 'open', true, 'internal', 77, false),
            ])
              {'id': f.$1, 'title': f.$2, 'theme': f.$3, 'status': f.$4, 'accepting': f.$5, 'access': f.$6, 'responses': f.$7, 'has_flows': f.$8, 'role': f.$1 == 'form0002' ? 'editor' : 'owner', 'token': 'tok${f.$1}'},
          ]};
        }
        if (p == '/fm/api/forms/form0001') {
          if (req.method == 'PUT') {
            form = {...form, ...Map<String, dynamic>.from(body as Map)..remove('base'), 'version': (form['version'] as int) + 1};
          }
          out = {'form': form};
        }
        if (p == '/fm/api/forms/form0001/settings') {
          form = {...form, 'settings': {...form['settings'] as Map, ...body as Map}};
          out = {'form': form};
        }
        if (p == '/fm/api/forms/form0001/summary') out = _summary;
        if (p == '/fm/api/forms/form0001/responses') {
          out = {'total': 2, 'responses': [
            {'id': 'r1', 'name': 'Lan Nguyễn', 'email': 'lan@example.com', 'public': false, 'answers': {'ho_va_ten': 'Lan Nguyễn', 'diem': 2, 'gioi_thieu': 'Không', 'gop_y': 'Chậm'}, 'links': [{'kind': 'flow', 'id': 'QT-2041', 'title': 'Xử lý phản hồi khách hàng'}, {'kind': 'todo', 'id': 'n1', 'title': 'Gọi lại Lan Nguyễn'}], 'created_at': DateTime(2026, 11, 14, 9, 42).millisecondsSinceEpoch, 'duration_ms': 108000},
            {'id': 'r2', 'name': null, 'email': null, 'public': true, 'answers': {'ho_va_ten': 'Trần Minh Anh', 'so_dien_thoai': '0912345678', 'diem': 4, 'gioi_thieu': 'Có, chắc chắn', 'dich_vu': ['Lắp đặt mới', 'Bảo trì định kỳ']}, 'links': [], 'created_at': DateTime(2026, 11, 14, 10, 5).millisecondsSinceEpoch, 'duration_ms': 64000},
          ]};
        }
        if (p == '/fm/api/forms/form0001/flows-grant') out = {'grant': 'g', 'expires_in': 300};
        if (p == '/fm/api/org') out = {'departments': [{'id': 'cskh', 'name': 'Phòng CSKH', 'parent': null}], 'roles': [{'id': 'ketoan', 'name': 'Kế toán'}]};
        if (p == '/fm/api/channels') out = {'channels': [{'id': 'chan0001', 'name': 'CSKH', 'team': 'Công ty'}]};
        if (p == '/fm/api/fill/k7Qm2xR9' && req.method == 'GET') out = {'form': {...form, 'settings': {...form['settings'] as Map, 'one_per_user': false}}, 'my_response': null, 'draft': null, 'me': {'name': 'Lan Nguyễn', 'email': 'lan@example.com'}};
        if (p == '/fm/api/fill/k7Qm2xR9' && req.method == 'POST') out = {'ok': true, 'response': {'id': 'r9', 'answers': (body as Map)['answers'], 'links': []}, 'confirmation': 'Đã ghi nhận câu trả lời. Cảm ơn anh/chị!'};
        if (p == '/fm/api/fill/k7Qm2xR9/draft') out = {'ok': true};
        if (p.startsWith('/__apps/flows/flows/integrations/forms/defs')) {
          if (p.endsWith('/check')) {
            out = {'ok': true, 'issues': [], 'traces': [1]};
          } else if (req.method == 'GET') {
            out = {'flows': flows};
          } else {
            out = {'id': 'bm-2', 'version': 1, 'issues': []};
          }
        }
        if (out == null) return http.Response('{"error":"không có $p"}', 404, headers: {'content-type': 'application/json'});
        return http.Response.bytes(utf8.encode(jsonEncode(out)), 200, headers: {'content-type': 'application/json'});
      });
}

void main() {
  final out = Platform.environment['FM_OUT'];
  late FakeBackend be;
  late FormsApi api;

  setUpAll(() async {
    FormsApi.liveEnabled = false;
    if (out != null) await _fonts();
  });
  setUp(() {
    be = FakeBackend();
    final c = be.client();
    api = FormsApi(base: 'https://chat.test/fm', server: 'https://chat.test', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: c), client: c);
  });

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester t, Widget child, {Size size = const Size(412, 900), Brightness theme = Brightness.light}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>(
      create: (_) => AppState('t'),
      child: RepaintBoundary(key: const ValueKey('shot'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(theme), home: child)),
    ));
    await settle(t);
  }

  /// Cuộn tới rồi bấm (nội dung dài hơn khung).
  Future<void> tapV(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(f);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  group('logic', () {
    test('rẽ nhánh và kiểm như máy chủ', () {
      expect(sectionPath(_schema, {'gioi_thieu': 'Có thể'}), [0, 1]);
      expect(sectionPath({'sections': [_schema['sections']![0], {...(_schema['sections']![1] as Map)}]}, {'gioi_thieu': 'Không'}), [0, 1]);
      final s2 = {'sections': [{'id': 'a', 'next': 'submit', 'items': []}, {'id': 'b', 'items': []}]};
      expect(sectionPath(s2, {}), [0]);
      final phone = (_schema['sections']![0] as Map)['items'][1] as Map<String, dynamic>;
      expect(checkAnswer(phone, '0912 34'), contains('Số điện thoại'));
      expect(checkAnswer(phone, '0912 345 678'), isNull);
      expect(checkAnswer({'type': 'number', 'validation': {'kind': 'range', 'min': 1, 'max': 10, 'integer': true}}, 2.5), 'Cần nhập số nguyên');
      expect(checkAnswer({'type': 'short', 'required': true}, null), 'Đây là câu hỏi bắt buộc');
      expect(checkAnswer({'type': 'checkbox', 'validation': {'kind': 'count', 'max': 1}}, ['a', 'b']), 'Chọn nhiều nhất 1');
      expect(checkAnswer({'type': 'grid_choice', 'required': true, 'rows': [{'label': 'A'}, {'label': 'B'}]}, {'A': '1'}), 'Cần trả lời mọi hàng');
      expect(normalize({'type': 'number'}, '1,5'), 1.5);
      expect(slugKey('Kết quả xử lý'), 'ket_qua_xu_ly');
      expect(slugKey('123'), 'q_123');
    });
    test('quy trình: bước → định nghĩa Flows → bước (giữ nguyên)', () {
      final steps = [
        FlowStep('condition', {'key': 'diem', 'op': '<=', 'value': '2'}),
        FlowStep('send', {'to': r'$owner', 'text': 'Gọi lại {{form.ho_va_ten}}'}),
        FlowStep('approval', {'title': 'Duyệt', 'approver': {'user': 'tp1'}}),
        FlowStep('task', {'title': 'Xử lý', 'assignee': r'$requester', 'fields': []}),
        FlowStep('condition', {'key': 'dich_vu', 'op': 'in', 'value': 'Bảo trì định kỳ'}),
      ];
      final def = buildDef(id: '', name: 'Q', steps: steps, schema: _schema, owner: 'own1');
      final nodes = def['nodes'] as List;
      expect(nodes.map((n) => (n as Map)['type']).toList(), ['start', 'condition', 'send', 'approval_request', 'form_task', 'condition', 'end']);
      expect((nodes[1] as Map)['rules'], [{'if': 'form.diem <= 2', 'to': 'b2'}]);
      expect((nodes[2] as Map)['to'], [{'user': 'own1'}]);
      expect((nodes[3] as Map)['approve_to'], 'b4');
      expect((nodes[5] as Map)['rules'], [{'if': "'Bảo trì định kỳ' in form.dich_vu", 'to': 'end'}]);
      expect(def['edges'], [['start', 'b1'], ['b2', 'b3'], ['b4', 'b5']]);
      expect((def['form'] as List).map((f) => (f as Map)['key']).toList(), ['ho_va_ten', 'so_dien_thoai', 'diem', 'gioi_thieu', 'dich_vu', 'gop_y']);
      final back = parseDef(def, 'own1');
      expect(back.map((s) => s.kind).toList(), ['condition', 'send', 'approval', 'task', 'condition']);
      expect(back[0].data, {'key': 'diem', 'op': '<=', 'value': '2'});
      expect(back[1].data['to'], r'$owner');
      expect(back[2].data['approver'], {'user': 'tp1'});
      expect(back[3].data['assignee'], r'$requester');
      expect(back[4].data, {'key': 'dich_vu', 'op': 'in', 'value': 'Bảo trì định kỳ'});
    });
  });

  testWidgets('trang chủ: mẫu có sẵn, danh sách, lọc', (t) async {
    await pump(t, FormsHome(api: api));
    expect(find.text('Tạo biểu mẫu mới'), findsOneWidget);
    expect(find.text('Khảo sát hài lòng'), findsOneWidget);
    expect(find.text('Đăng ký tiệc tất niên 2026'), findsOneWidget);
    expect(find.textContaining('Đang nhận · 128'), findsOneWidget);
    await shot(t, 'f01-home-phone');
    await pump(t, FormsHome(api: api), size: const Size(1280, 860));
    await shot(t, 'f02-home-desktop');
    await t.tap(find.text('Của tôi'));
    await settle(t, 3);
    expect(be.calls.any((c) => c.$2 == '/fm/api/forms' && c.$1 == 'GET'), isTrue);
  });

  testWidgets('trình soạn: chọn câu, sửa tiêu đề → lưu tự động kèm base', (t) async {
    await pump(t, FormEditorPage(api: api, formId: 'form0001'), size: const Size(1280, 1500));
    expect(find.text('Câu hỏi'), findsOneWidget);
    expect(find.text('Mục 1 / 2'), findsOneWidget);
    await t.tap(find.textContaining('Anh/chị có giới thiệu dịch vụ cho người quen không?', findRichText: true).first);
    await settle(t, 2);
    expect(find.text('Trắc nghiệm'), findsWidgets);
    expect(find.text('Đến mục 2'), findsOneWidget); // lựa chọn "Không" rẽ sang mục 2
    await shot(t, 'f03-builder-desktop');
    await t.tap(find.textContaining('Họ và tên', findRichText: true).first);
    await settle(t, 2);
    await t.enterText(find.widgetWithText(TextFormField, 'Họ và tên').first, 'Họ tên đầy đủ');
    await t.pump(const Duration(seconds: 1));
    await settle(t, 3);
    final put = be.calls.lastWhere((c) => c.$1 == 'PUT' && c.$2 == '/fm/api/forms/form0001');
    expect((put.$3 as Map)['base'], 3);
    expect(((put.$3 as Map)['schema'] as Map)['sections'][0]['items'][0]['title'], 'Họ tên đầy đủ');
  });

  testWidgets('trình soạn trên điện thoại + tối', (t) async {
    await pump(t, FormEditorPage(api: api, formId: 'form0001'), size: const Size(412, 900));
    await t.tap(find.textContaining('Mức độ hài lòng chung', findRichText: true).first);
    await settle(t, 2);
    await shot(t, 'f04-builder-phone');
    await pump(t, FormEditorPage(api: api, formId: 'form0001'), size: const Size(1280, 860), theme: Brightness.dark);
    await shot(t, 'f05-builder-desktop-dark');
  });

  testWidgets('điền: báo lỗi, rẽ nhánh sang mục Góp ý, gửi', (t) async {
    await pump(t, FormFillPage(api: api, token: 'k7Qm2xR9'), size: const Size(412, 1500));
    expect(find.textContaining('Đang điền với tài khoản Lan Nguyễn'), findsOneWidget);
    await tapV(t, find.text('Tiếp'));
    await settle(t, 2);
    expect(find.text('Đây là câu hỏi bắt buộc'), findsNWidgets(2));
    await t.enterText(find.byType(TextField).at(0), 'Trần Minh Anh');
    await t.enterText(find.byType(TextField).at(1), '0912 34');
    await tapV(t, find.text('4'));
    await tapV(t, find.text('Bảo trì định kỳ'));
    await settle(t, 2);
    await tapV(t, find.text('Tiếp'));
    await settle(t, 2);
    expect(find.textContaining('Số điện thoại chưa đúng'), findsOneWidget);
    await shot(t, 'f06-fill-phone');
    await t.enterText(find.byType(TextField).at(1), '0912 345 678');
    await tapV(t, find.text('Không'));
    await settle(t, 2);
    await tapV(t, find.text('Tiếp'));
    await settle(t, 2);
    expect(find.textContaining('Góp ý thêm', findRichText: true), findsWidgets);
    await t.enterText(find.byType(TextField).first, 'Cần nhanh hơn');
    await tapV(t, find.text('Gửi'));
    await settle(t, 3);
    final post = be.calls.lastWhere((c) => c.$1 == 'POST' && c.$2 == '/fm/api/fill/k7Qm2xR9');
    expect((post.$3 as Map)['answers'], {'ho_va_ten': 'Trần Minh Anh', 'so_dien_thoai': '0912 345 678', 'diem': 4, 'gioi_thieu': 'Không', 'dich_vu': ['Bảo trì định kỳ'], 'gop_y': 'Cần nhanh hơn'});
    expect(find.textContaining('Đã ghi nhận câu trả lời'), findsOneWidget);
    await shot(t, 'f07-done-phone');
  });

  testWidgets('điền tối', (t) async {
    await pump(t, FormFillPage(api: api, token: 'k7Qm2xR9'), theme: Brightness.dark);
    await shot(t, 'f08-fill-phone-dark');
  });

  testWidgets('câu trả lời: tóm tắt (biểu đồ), từng câu trả lời có luồng + việc Todo', (t) async {
    await pump(t, FormEditorPage(api: api, formId: 'form0001', tab: 1), size: const Size(1280, 1700));
    expect(find.text('2 câu trả lời'), findsOneWidget);
    expect(find.textContaining('trung bình 4,2'), findsOneWidget);
    expect(find.text('Đang nhận câu trả lời'), findsOneWidget);
    await shot(t, 'f09-responses-desktop');
    await t.tap(find.text('Từng câu trả lời'));
    await settle(t, 2);
    expect(find.textContaining('Luồng: Xử lý phản hồi khách hàng'), findsOneWidget);
    expect(find.textContaining('Công việc: Gọi lại Lan Nguyễn'), findsOneWidget);
    await pump(t, FormEditorPage(api: api, formId: 'form0001', tab: 1), size: const Size(412, 1400));
    await shot(t, 'f10-responses-phone');
  });

  testWidgets('tự động hoá: liệt kê quy trình gắn biểu mẫu, mở để sửa, chạy thử', (t) async {
    await pump(t, FormEditorPage(api: api, formId: 'form0001', tab: 2), size: const Size(1280, 1500));
    expect(find.text('Xử lý phản hồi khách hàng'), findsOneWidget);
    expect(find.textContaining('Biểu mẫu đang công khai'), findsOneWidget);
    await t.tap(find.text('Xử lý phản hồi khách hàng'));
    await settle(t, 2);
    expect(find.text('Điều kiện (chỉ chạy tiếp khi…)'), findsOneWidget);
    expect(find.text('Giao việc kèm form'), findsOneWidget);
    await t.tap(find.text('Chạy thử'));
    await settle(t, 3);
    expect(find.textContaining('Chạy thử với câu trả lời mới nhất: ổn'), findsOneWidget);
    expect(be.calls.any((c) => c.$2.endsWith('/defs/check')), isTrue);
    await shot(t, 'f11-automation-desktop');
    await pump(t, FormEditorPage(api: api, formId: 'form0001', tab: 2), size: const Size(412, 1400));
    await t.tap(find.text('Mẫu: Duyệt đơn'));
    await settle(t, 2);
    await shot(t, 'f12-automation-phone');
    await tapV(t, find.text('Tạo quy trình'));
    await settle(t, 3);
    final save = be.calls.lastWhere((c) => c.$1 == 'POST' && c.$2.endsWith('/forms/defs'));
    expect(((save.$3 as Map)['nodes'] as List).map((n) => (n as Map)['type']).toList(), ['start', 'approval_request', 'send', 'end']);
  });

  testWidgets('cài đặt + chia sẻ', (t) async {
    await pump(t, FormEditorPage(api: api, formId: 'form0001', tab: 3), size: const Size(1280, 1300));
    expect(find.text('Báo trong chat'), findsOneWidget);
    expect(find.text('Nam'), findsOneWidget);
    await shot(t, 'f13-settings-desktop');
    await pump(t, Builder(builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () => showShareSheet(c, api, be.form), child: const Text('open'))))), size: const Size(1280, 900));
    await t.tap(find.text('open'));
    await settle(t, 3);
    expect(find.text('Gửi biểu mẫu'), findsOneWidget);
    expect(find.text('Link công khai'), findsOneWidget);
    await shot(t, 'f14-share-desktop');
  });
}
