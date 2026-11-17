// App Hợp đồng (vn.flygo.hopdong): kiểm màn hình native với máy chủ giả (danh sách, soạn / gửi ký, tiến độ ký, chi tiết)
// và chụp ảnh xem trước. Chạy tay để lấy ảnh: HD_OUT=<thư mục> flutter test test/hopdong_preview_test.dart
// (máy tính 1440x900 + điện thoại 390x844, sáng + tối).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/hopdong/api.dart';
import 'package:flygo_chat/ui/hopdong/detail_page.dart';
import 'package:flygo_chat/ui/hopdong/edit_page.dart';
import 'package:flygo_chat/ui/hopdong/hopdong_page.dart';
import 'package:flygo_chat/ui/hopdong/model.dart';
import 'package:flygo_chat/ui/hopdong/progress.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/mnt/d2/flygo-build/flutter'}/bin/cache/artifacts/material_fonts';
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
  // Roboto trong bộ test thiếu "→", "⚠", "✓": nạp DejaVu vào họ chữ dự phòng của theme (máy thật có sẵn).
  final dv = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
  if (dv.existsSync()) {
    final l = FontLoader('Noto Color Emoji')..addFont(Future.value(ByteData.sublistView(dv.readAsBytesSync())));
    await l.load();
  }
}

final _now = DateTime(2026, 11, 17, 10, 0);
int _ms(int m, int d, [int h = 0, int mi = 0, int y = 2026]) => DateTime(y, m, d, h, mi).millisecondsSinceEpoch;

Map<String, dynamic> _p(String id, int idx, String label, String name, String no,
        {String status = 'waiting', bool internal = false, String kind = 'mst', String email = '', int? signedAt, String? via, String? issuer, String? reason, int open = 0, int? exp}) =>
    {
      'id': id, 'idx': idx, 'label': label, 'name': name, 'id_kind': kind, 'id_no': no, 'email': email, 'internal': internal, 'status': status,
      'link_expires': exp, 'opened_at': open > 0 ? _ms(11, 17, 9, 11) : null, 'open_count': open, 'signed_at': signedAt, 'signed_via': via,
      'cert_cn': status == 'signed' ? name : null, 'cert_issuer': issuer, 'cert_serial': status == 'signed' ? '5402AB77C1E9A1' : null, 'reject_reason': reason,
      if (status == 'ready' || status == 'opened') 'link': 'https://chat.test/hd/s/$id.tok',
    };

Map<String, dynamic> _c(String id, String no, String title, String status,
        {num? value, int? from, int? to, int? deadline, String mode = 'seq', List<Map<String, dynamic>> parties = const [], String owner = 'Lan Nguyễn',
        int? done, int remind = 30, String note = '', bool notePublic = false, Map<String, dynamic>? doc, List<Map<String, dynamic>> events = const []}) =>
    {
      'id': id, 'no': no, 'title': title, 'value': value, 'currency': 'VND', 'eff_from': from, 'eff_to': to, 'sign_deadline': deadline, 'remind_days': remind,
      'note': note, 'note_public': notePublic, 'mode': mode, 'status': status, 'owner': {'id': 'u-${owner.hashCode}', 'name': owner}, 'role': 'owner',
      'doc': doc ?? {'name': '${no.replaceAll('/', '-')}.pdf', 'rev': 1 + parties.where((p) => p['status'] == 'signed').length, 'sha256': 'ab', 'pages': 4},
      'sent_at': status == 'draft' ? null : _ms(11, 15, 17, 5), 'done_at': done, 'created_at': _ms(11, 14), 'updated_at': _ms(11, 16, 10, 42),
      'progress': {'signed': parties.where((p) => p['status'] == 'signed').length, 'total': parties.length}, 'parties': parties, 'events': events, 'members': const [],
    };

Map<String, dynamic> _e(int seq, int at, String actor, String action, [Map<String, dynamic>? d]) => {'seq': seq, 'at': at, 'actor': actor, 'action': action, 'detail': d, 'ip': '113.190.1.2'};

class FakeBackend {
  final calls = <(String, String, Object?)>[];

  /// /doc-from-drive: 'ok' (máy chủ tự lấy từ Drive) | 'old' (máy chủ cũ: 404 "không có").
  String driveMode = 'ok';

  /// Giữ phản hồi /doc-from-drive tới khi kiểm thử cho chạy tiếp (để thấy trạng thái đang lấy tệp).
  Completer<void>? driveGate;
  late final List<Map<String, dynamic>> contracts = [
    _c('hd000118', 'HĐMB-2026/118', 'Mua bán cáp thang máy', 'sending', value: 1240000000, deadline: _ms(11, 20, 17), from: _ms(12, 1), to: _ms(11, 30, 0, 0, 2027), parties: [
      _p('pa118b', 0, 'Bên B', 'CÔNG TY TNHH THANG MÁY HÀ NỘI', '0105123456', status: 'signed', signedAt: _ms(11, 16, 15, 42), via: 'plugin:cthub', issuer: 'Viettel-CA'),
      _p('pa118c', 1, 'Bên C', 'CÔNG TY VẬN TẢI MINH ANH', '0108765432', status: 'signed', signedAt: _ms(11, 17, 9, 10), via: 'offline', issuer: 'FPT-CA'),
      _p('pa118a', 2, 'Bên A', 'CÔNG TY CP FLYGO', '0109876543', status: 'opened', internal: true, open: 1, exp: _ms(11, 20, 17)),
    ], events: [
      _e(9, _ms(11, 17, 9, 11), 'system', 'turn', {'party': 'pa118a', 'name': 'CÔNG TY CP FLYGO', 'label': 'Bên A'}),
      _e(8, _ms(11, 17, 9, 10), 'party:pa118c', 'signed', {'via': 'offline', 'issuer': 'FPT-CA'}),
      _e(7, _ms(11, 17, 8, 52), 'party:pa118c', 'no_plugin', {}),
      _e(6, _ms(11, 16, 15, 42), 'party:pa118b', 'signed', {'via': 'plugin:cthub', 'issuer': 'Viettel-CA'}),
      _e(5, _ms(11, 16, 15, 40), 'party:pa118b', 'wrong_cert', {'cn': 'CTY KHAC', 'ids': {'mst': '0312345678'}, 'want': 'MST 0105123456', 'plugin': 'cthub'}),
      _e(4, _ms(11, 16, 9, 12), 'party:pa118b', 'open', {'n': 1}),
      _e(3, _ms(11, 15, 17, 5), 'u-1', 'send', {'by': 'Lan Nguyễn', 'mode': 'seq'}),
      _e(2, _ms(11, 15, 16, 0), 'u-1', 'doc', {'name': 'HDMB-2026-118.pdf', 'rev': 1}),
      _e(1, _ms(11, 14, 9, 0), 'u-1', 'create', {'by': 'Lan Nguyễn'}),
    ]),
    _c('hd000091', 'HĐDV-2026/091', 'Thuê máy chủ', 'sending', value: 96000000, deadline: _ms(11, 15, 17), owner: 'Hùng Trần', parties: [
      _p('pa091a', 0, 'Bên A', 'Cty TNHH Sao Mai', '0316778899', status: 'ready', exp: _ms(11, 15, 17)),
      _p('pa091b', 1, 'Bên B', 'CÔNG TY CP FLYGO', '0109876543', internal: true),
    ]),
    _c('hd000010', 'HĐĐL-2026/010', 'Đại lý miền Nam', 'rejected', value: 2000000000, owner: 'Hùng Trần', parties: [
      _p('pa010a', 0, 'Bên A', 'CÔNG TY CP FLYGO', '0109876543', internal: true, status: 'signed', signedAt: _ms(11, 15, 10), via: 'plugin:misa', issuer: 'MISA-CA'),
      _p('pa010b', 1, 'Bên B', 'Cty TNHH Phát Đạt', '0312233445', status: 'rejected', reason: 'Đề nghị sửa Điều 5 chiết khấu'),
    ]),
    _c('hd000033', 'HĐLĐ-2026/033', 'Lê Thị Mai', 'sending', deadline: _ms(11, 22, 17), owner: 'Nga Phạm', from: _ms(11, 15), to: _ms(11, 14, 0, 0, 2028), parties: [
      _p('pa033a', 0, 'Người lao động', 'Lê Thị Mai', '001190012345', kind: 'cccd', status: 'ready', exp: _ms(11, 22, 17)),
      _p('pa033b', 1, 'Công ty', 'CÔNG TY CP FLYGO', '0109876543', internal: true),
    ]),
    _c('hd000087', 'HĐDV-2026/087', 'Bảo trì hệ thống 12 tháng', 'draft', value: 360000000, from: _ms(12, 1), to: _ms(11, 30, 0, 0, 2027), deadline: _ms(11, 24, 17),
        note: 'Đối tác yêu cầu ký trước 25/11 để kịp thanh toán đợt 1.', doc: {'name': 'HDDV-2026-087-v3.pdf', 'rev': 3, 'sha256': 'cd', 'pages': 4}, parties: [
      _p('pa087a', 0, 'Bên A', 'CÔNG TY CP ĐÔNG NAM Á', '0101234567', email: 'hung@dongnama.vn'),
      _p('pa087b', 1, 'Bên B', 'CÔNG TY CP FLYGO', '0109876543', internal: true),
    ]),
    _c('hd000012', 'HĐTN-2024/012', 'Thuê văn phòng tầng 5', 'signed', value: 45000000, from: _ms(12, 9, 0, 0, 2024), to: _ms(12, 8), done: _ms(12, 2, 0, 0, 2024), owner: 'Tâm Lê', parties: [
      _p('pa012a', 0, 'Bên A', 'Toà nhà Lotus Office', '0105556677', status: 'signed', signedAt: _ms(12, 1, 0, 0, 2024), via: 'offline', issuer: 'VNPT-CA'),
      _p('pa012b', 1, 'Bên B', 'CÔNG TY CP FLYGO', '0109876543', internal: true, status: 'signed', signedAt: _ms(12, 2, 0, 0, 2024), via: 'plugin:viettel', issuer: 'Viettel-CA'),
    ]),
    _c('hd000031', 'HĐLĐ-2026/031', 'Hợp đồng lao động – Trần Văn Minh', 'signed', from: _ms(11, 15), to: _ms(11, 14, 0, 0, 2028), done: _ms(11, 14, 16), owner: 'Nga Phạm', parties: [
      _p('pa031a', 0, 'Người lao động', 'Trần Văn Minh', '001090054321', kind: 'cccd', status: 'signed', signedAt: _ms(11, 14, 15), via: 'offline', issuer: 'FPT-CA'),
      _p('pa031b', 1, 'Công ty', 'CÔNG TY CP FLYGO', '0109876543', internal: true, status: 'signed', signedAt: _ms(11, 14, 16), via: 'plugin:misa', issuer: 'MISA-CA'),
    ]),
    _c('hd000204', 'HĐMB-2025/204', 'Mua thiết bị camera', 'cancelled', value: 520000000, owner: 'Hùng Trần', parties: [
      _p('pa204a', 0, 'Bên B', 'Cty CP An Ninh Việt', '0107788990'),
      _p('pa204b', 1, 'Bên A', 'CÔNG TY CP FLYGO', '0109876543', internal: true),
    ]),
  ];

  bool match(Map<String, dynamic> c, String? st) {
    final now = _now.millisecondsSinceEpoch;
    return switch (st) {
      null => true,
      'overdue' => c['status'] == 'sending' && c['sign_deadline'] != null && (c['sign_deadline'] as int) < now,
      'expiring' => c['status'] == 'signed' && c['eff_to'] != null && (c['eff_to'] as int) >= now && (c['eff_to'] as int) <= now + 30 * 86400000,
      _ => c['status'] == st,
    };
  }

  http.Client client() => MockClient((req) async {
        final p = req.url.path;
        final body = req.body.isEmpty || req.headers['content-type']?.contains('json') != true ? null : jsonDecode(req.body);
        calls.add((req.method, p, body));
        Object? out;
        if (p == '/v1/token') out = {'token': 'tk', 'expires_in': 600, 'scope': ['use']};
        if (p == '/hd/api/me') out = {'user': {'id': 'u-1', 'name': 'Lan Nguyễn', 'username': 'lan'}, 'admin': true, 'company': 'CÔNG TY CP FLYGO', 'plugins': ['misa']};
        if (p == '/hd/api/counts') {
          int n(String? s) => contracts.where((c) => match(c, s)).length;
          out = {'all': n(null), 'draft': n('draft'), 'sending': n('sending'), 'signed': n('signed'), 'rejected': n('rejected'), 'overdue': n('overdue'), 'expiring': n('expiring')};
        }
        if (p == '/hd/api/contracts' && req.method == 'GET') {
          final st = req.url.queryParameters['status'];
          final q = (req.url.queryParameters['q'] ?? '').toLowerCase();
          out = {'contracts': contracts.where((c) => match(c, st) && (q.isEmpty || '${c['no']} ${c['title']}'.toLowerCase().contains(q))).toList()};
        }
        if (p == '/hd/api/contracts' && req.method == 'POST') {
          final c = _c('hdnew001', '', '', 'draft', doc: {'name': '', 'rev': 0});
          (c as Map)['doc'] = null;
          final m = {...c, ...Map<String, dynamic>.from(body as Map)};
          contracts.add(m);
          out = {'contract': m};
        }
        final m = RegExp(r'^/hd/api/contracts/([a-z0-9]+)(?:/(.*))?$').firstMatch(p);
        if (m != null) {
          final c = contracts.where((x) => x['id'] == m.group(1)).firstOrNull;
          final act = m.group(2);
          if (c != null) {
            if (act == null && req.method == 'PUT') {
              final b = Map<String, dynamic>.from(body as Map);
              c.addAll(b..remove('parties'));
            }
            if (act == 'send') c['status'] = 'sending';
            if (act == 'doc-from-drive') {
              if (driveMode == 'old') return http.Response('{"error":"không có"}', 404, headers: {'content-type': 'application/json'});
              await driveGate?.future;
              final b = body as Map;
              c['doc'] = {'name': b['name'], 'rev': ((c['doc'] as Map?)?['rev'] as int? ?? 0) + 1, 'sha256': 'ef', 'pages': 6};
            }
            if (act == 'doc' && req.method == 'PUT') c['doc'] = {'name': 'tai-len.pdf', 'rev': ((c['doc'] as Map?)?['rev'] as int? ?? 0) + 1, 'sha256': 'ef', 'pages': 6};
            out = {'contract': c};
          }
        }
        if (out == null) return http.Response('{"error":"không có $p"}', 404, headers: {'content-type': 'application/json'});
        return http.Response.bytes(utf8.encode(jsonEncode(out)), 200, headers: {'content-type': 'application/json'});
      });
}

void main() {
  final out = Platform.environment['HD_OUT'];
  late FakeBackend be;
  late HopdongApi api;

  setUpAll(() async {
    HdPdfView.enabled = false;
    hdNow = () => _now;
    if (out != null) {
      await _fonts();
      Directory(out).createSync(recursive: true);
    }
  });
  setUp(() {
    be = FakeBackend();
    final c = be.client();
    api = HopdongApi(base: 'https://chat.test/hd', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: c), client: c);
  });

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  const desk = Size(1440, 900), phone = Size(390, 844);

  Future<void> pump(WidgetTester t, Widget child, {Size size = desk, Brightness theme = Brightness.dark}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>(
      create: (_) => AppState('t'),
      child: RepaintBoundary(key: const ValueKey('shot'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(theme), home: child)),
    ));
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Contract fixture(String id) => Contract.fromJson(be.contracts.firstWhere((c) => c['id'] == id));

  group('định dạng', () {
    test('tiền, ngày, MST, nhật ký', () {
      expect(money(360000000), '360.000.000 ₫');
      expect(moneyShort(1240000000), '1,24 tỷ ₫');
      expect(moneyShort(360000000), '360 tr ₫');
      expect(dmy(_ms(11, 24, 17)), '24/11/2026');
      expect(validId('mst', '0101234567'), isTrue);
      expect(validId('mst', '0101234567-001'), isTrue);
      expect(validId('mst', '010123456'), isFalse);
      expect(validId('cccd', '001190012345'), isTrue);
      expect(initials('CÔNG TY CP ĐÔNG NAM Á'), 'ĐN');
      final c = Contract.fromJson(FakeBackend().contracts.first);
      final wrong = c.events.firstWhere((e) => e.action == 'wrong_cert');
      final (t, warn) = eventText(wrong, c);
      expect(warn, isTrue);
      expect(t, contains('MST 0312345678'));
      expect(t, contains('bị từ chối'));
      expect(eventText(c.events.firstWhere((e) => e.action == 'signed' && e.detail['via'] == 'offline'), c).$1, contains('ký offline'));
    });
  });

  for (final dark in [true, false]) {
    final th = dark ? Brightness.dark : Brightness.light;
    final sfx = dark ? 'toi' : 'sang';

    testWidgets('máy tính: tổng quan ($sfx)', (t) async {
      await pump(t, HopdongHome(api: api), theme: th);
      expect(find.text('Tổng quan'), findsWidgets);
      expect(find.textContaining('Mua bán cáp thang máy'), findsOneWidget);
      expect(find.text('1.240.000.000 ₫'), findsOneWidget);
      await shot(t, 'real-1-danh-sach-desktop-$sfx');
    });

    testWidgets('máy tính: tiến độ ký ($sfx)', (t) async {
      await pump(t, HopdongHome(api: api, initialView: 'progress'), theme: th);
      await settle(t);
      expect(find.text('Sao chép link ký'), findsOneWidget);
      expect(find.textContaining('sai MST 0105123456 → bị từ chối'), findsOneWidget);
      await shot(t, 'real-7-tien-do-ky-desktop-$sfx');
    });

    testWidgets('máy tính: sửa hợp đồng ($sfx)', (t) async {
      await pump(t, ContractEditPage(api: api, initial: fixture('hd000087')), theme: th);
      expect(find.text('Gửi ký cho Bên A'), findsOneWidget);
      expect(find.textContaining('Sẵn sàng gửi · 2 bên · lần lượt · hạn 24/11'), findsOneWidget);
      await shot(t, 'real-6-sua-hop-dong-desktop-$sfx');
      await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -600));
      await settle(t, 2);
      expect(find.text('Tiến độ luồng ký'), findsOneWidget);
      await shot(t, 'real-6b-sua-hop-dong-desktop-cuon-$sfx');
    });

    testWidgets('máy tính: hợp đồng mới ($sfx)', (t) async {
      await pump(t, ContractEditPage(api: api), theme: th);
      expect(find.text('Từ máy'), findsOneWidget);
      await shot(t, 'real-6d-hop-dong-moi-desktop-$sfx');
    });

    testWidgets('máy tính: chi tiết ký ($sfx)', (t) async {
      await pump(t, ContractDetailPage(api: api, contract: fixture('hd000118')), theme: th);
      expect(find.textContaining('Đang ký 2/3'), findsOneWidget);
      await shot(t, 'real-2-chi-tiet-ky-desktop-$sfx');
    });

    testWidgets('điện thoại: danh sách ($sfx)', (t) async {
      await pump(t, HopdongHome(api: api), size: phone, theme: th);
      expect(find.textContaining('Chờ ký'), findsOneWidget);
      await shot(t, 'real-m0-danh-sach-mobile-$sfx');
    });

    testWidgets('điện thoại: sửa hợp đồng ($sfx)', (t) async {
      await pump(t, ContractEditPage(api: api, initial: fixture('hd000087')), size: phone, theme: th);
      await shot(t, 'real-m1-sua-hop-dong-mobile-$sfx');
    });

    testWidgets('điện thoại: tiến độ ký ($sfx)', (t) async {
      await pump(t, ContractProgressPage(api: api, contract: fixture('hd000118')), size: phone, theme: th);
      expect(find.text('Link'), findsOneWidget);
      expect(find.textContaining('Mở trang ký trên máy tính'), findsOneWidget);
      await shot(t, 'real-m2-tien-do-ky-mobile-$sfx');
    });
  }

  testWidgets('gửi ký: hỏi xác nhận rồi gọi /send', (t) async {
    await pump(t, ContractEditPage(api: api, initial: fixture('hd000087')));
    await t.tap(find.text('Gửi ký cho Bên A'));
    await settle(t, 2);
    expect(find.text('Gửi ký cho Bên A?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Gửi ký'));
    await settle(t);
    expect(be.calls.any((c) => c.$1 == 'PUT' && c.$2 == '/hd/api/contracts/hd000087'), isTrue);
    expect(be.calls.any((c) => c.$1 == 'POST' && c.$2 == '/hd/api/contracts/hd000087/send'), isTrue);
  });

  group('chọn PDF từ Drive', () {
    var downloads = 0;
    setUp(() {
      downloads = 0;
      ContractEditPage.debugDrivePicker = (_) async => HdDrivePick(
            path: '/Hợp đồng/HDDV-2026-087-v4.pdf',
            name: 'HDDV-2026-087-v4.pdf',
            ticket: () async => 'drive-ticket',
            download: () async {
              downloads++;
              return Uint8List.fromList(utf8.encode('%PDF-1.7 giả'));
            },
          );
    });
    tearDown(() => ContractEditPage.debugDrivePicker = null);

    Future<void> pickDrive(WidgetTester t) async {
      await t.tap(find.text('Từ Drive'));
      await settle(t, 2);
    }

    testWidgets('máy chủ tự lấy tệp, hiện "Đang lấy tệp từ Drive…"', (t) async {
      be.driveGate = Completer<void>();
      await pump(t, ContractEditPage(api: api, initial: fixture('hd000087')));
      await pickDrive(t);
      expect(find.text('Đang lấy tệp từ Drive…'), findsOneWidget);
      // Đang lấy thì khoá nút gửi / lưu.
      expect(t.widget<FilledButton>(find.ancestor(of: find.text('Gửi ký cho Bên A'), matching: find.byWidgetPredicate((w) => w is FilledButton))).onPressed, isNull);
      await shot(t, 'compact-6c-lay-tu-drive-desktop');
      be.driveGate!.complete();
      await settle(t);
      final call = be.calls.firstWhere((c) => c.$2 == '/hd/api/contracts/hd000087/doc-from-drive');
      expect(call.$1, 'PUT');
      expect(call.$3, {'path': '/Hợp đồng/HDDV-2026-087-v4.pdf', 'name': 'HDDV-2026-087-v4.pdf', 'ticket': 'drive-ticket'});
      expect(downloads, 0);
      expect(find.text('HDDV-2026-087-v4.pdf'), findsOneWidget);
    });

    testWidgets('máy chủ cũ (404) thì tải về rồi tải lên', (t) async {
      be.driveMode = 'old';
      await pump(t, ContractEditPage(api: api, initial: fixture('hd000087')));
      await pickDrive(t);
      await settle(t);
      expect(downloads, 1);
      expect(be.calls.any((c) => c.$1 == 'PUT' && c.$2 == '/hd/api/contracts/hd000087/doc'), isTrue);
    });
  });

  testWidgets('MST sai thì chưa sẵn sàng gửi', (t) async {
    await pump(t, ContractEditPage(api: api, initial: fixture('hd000087')));
    await t.enterText(find.widgetWithText(TextField, '0101234567'), '01012');
    await settle(t, 2);
    expect(find.textContaining('Còn thiếu: MST Bên A'), findsOneWidget);
    expect(find.text('MST phải 10 số hoặc 10 số-3 số'), findsOneWidget);
  });

  testWidgets('gửi nhắc bên đang chờ', (t) async {
    await pump(t, ContractProgressPage(api: api, contract: fixture('hd000118')), size: phone);
    await t.ensureVisible(find.text('Nhắc'));
    await settle(t);
    await t.tap(find.text('Nhắc'));
    await settle(t);
    expect(be.calls.any((c) => c.$1 == 'POST' && c.$2 == '/hd/api/contracts/hd000118/parties/pa118a/remind'), isTrue);
  });
}
