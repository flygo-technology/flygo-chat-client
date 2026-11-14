// Mục Tiến trình (danh sách, bộ lọc), chi tiết tiến trình, báo cáo tiến trình. Ảnh xem trước (chạy tay):
// EDITOR_OUT=<thư mục> flutter test test/process_ui_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/ui/flows/process_list.dart' show ProcessesView;
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flows_page.dart';
import 'package:flygo_chat/ui/flows/process_detail.dart';
import 'package:flygo_chat/ui/flows/process_report.dart';
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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json'});

void main() {
  final out = Platform.environment['EDITOR_OUT'];
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['u2'] = MmUser({'id': 'u2', 'username': 'lan', 'first_name': 'Lan Kế toán'});
  final now = DateTime.now().millisecondsSinceEpoch;
  final requests = <Uri>[];

  List<Map<String, dynamic>> steps(int at, {bool failed = false}) => [
        for (final (i, (k, t)) in [('nhan', 'Nhận hoá đơn'), ('kiem', 'Kiểm tra trùng'), ('ky', 'Kế toán ký'), ('gui', 'Gửi khách')].indexed)
          {'key': k, 'title': t, 'state': i < at ? 'done' : (i == at ? (failed ? 'failed' : 'active') : 'pending')},
      ];
  Map<String, dynamic> proc(String id, String name, String state, int at, String status, String tone, List<String> labels, {bool failed = false}) => {
        'id': id, 'flow_id': 'linkq', 'flow_name': 'Đồng bộ hoá đơn LinkQ', 'flow_icon': '🧾', 'key': 'dedup-$id', 'name': name, 'icon': '🧾',
        'state': state, 'current_step': steps(at)[at.clamp(0, 3)]['key'], 'status_text': status, 'tone': tone, 'steps': steps(at, failed: failed),
        'stats': [
          {'key': 'amount', 'label': 'Tổng tiền', 'type': 'number', 'value': 128450000},
          {'key': 'buyer', 'label': 'Bên mua', 'type': 'text', 'value': 'Cty Hoàng Long'},
          {'key': 'lines', 'label': 'Số dòng', 'type': 'number', 'value': 12},
        ],
        'labels': labels, 'created_at': now - 3600000, 'updated_at': now - 600000, 'finished_at': state == 'done' ? now - 60000 : null,
      };
  final running = [
    proc('P-8K2Q4M', 'Hoá đơn 2154 · Cty Hoàng Long', 'running', 2, 'Chờ kế toán ký', 'orange', ['KLTM', 'ABC Capital']),
    {...proc('P-7Z1XQ2', 'Hoá đơn 2155 · Cty Minh Phát', 'running', 1, 'Đang kiểm tra trùng', 'blue', ['Nghi trùng']), 'progress': {'percent': 44, 'label': 'Đã kiểm 4/9'}},
  ];
  final failed = [proc('P-3F9DD1', 'Hoá đơn 2101 · Cty An Bình', 'failed', 1, 'Không lấy được XML', 'red', ['KLTM'], failed: true)];
  final done = [proc('P-1A2B3C', 'Hoá đơn 2050 · Cty Sao Mai', 'done', 4, 'Đã gửi khách', 'green', const [])];
  final detail = {
    ...running.first,
    'instance_id': 'i-77',
    'files': [
      {'name': 'hoadon-2154.pdf', 'kind': 'file', 'file_id': 'f1', 'size': 182400, 'at': now - 3000000},
      {'name': 'Chứng từ LinkQ', 'kind': 'link', 'url': 'https://linkq.vn/ct/2154', 'at': now - 2000000},
    ],
    'posts': [
      {'channel_id': 'c-kt', 'post_id': 'post-1', 'sync': true},
      {'user_id': 'u2', 'post_id': 'post-2', 'sync': false},
    ],
    'events': [
      {'at': now - 3600000, 'actor': 'flow', 'node': 'tao', 'kind': 'create', 'data': {'key': 'dedup-P-8K2Q4M'}},
      {'at': now - 1200000, 'actor': 'u2', 'node': 'buoc', 'kind': 'step', 'data': {'step': 'ky', 'status_text': 'Chờ kế toán ký'}},
    ],
  };
  final report = {
    'total': 42,
    'by_state': {'running': 12, 'failed': 3, 'done': 25, 'cancelled': 2},
    'by_step': [
      {'key': 'nhan', 'title': 'Nhận hoá đơn', 'count': 2},
      {'key': 'kiem', 'title': 'Kiểm tra trùng', 'count': 4},
      {'key': 'ky', 'title': 'Kế toán ký', 'count': 9},
    ],
    'stats': [
      {'key': 'amount', 'label': 'Tổng tiền', 'sum': 5394900000, 'avg': 128450000, 'count': 42},
    ],
    'daily': [
      for (var i = 0; i < 14; i++) {'date': '2026-10-${(25 + i > 31 ? 25 + i - 31 : 25 + i).toString().padLeft(2, '0')}', 'created': (i * 7) % 6 + 1, 'done': (i * 5) % 4, 'failed': i % 5 == 0 ? 1 : 0},
    ],
  };
  FlowsApi.debugClient = MockClient((r) async {
    requests.add(r.url);
    final q = r.url.queryParameters;
    List<Map<String, dynamic>> filter(List<Map<String, dynamic>> l) => [
          for (final p in l)
            if ((q['label'] == null || (p['labels'] as List).contains(q['label'])) && (q['q'] == null || '${p['name']}'.toLowerCase().contains(q['q']!.toLowerCase()))) p,
        ];
    return switch (r.url.path) {
      '/__apps/flows/processes' => _json({
          'processes': filter(switch (q['state']) { 'failed' => failed, 'running' => running, null => [...running, ...failed, ...done], _ => done }),
        }),
      '/__apps/flows/processes/P-8K2Q4M' => _json(detail),
      '/__apps/flows/processes/P-8K2Q4M/files/f1' => http.Response.bytes(utf8.encode('%PDF'), 200),
      '/__apps/flows/defs/linkq/report' => _json(report),
      '/__apps/flows/defs' => _json({'flows': [
          {'id': 'linkq', 'name': 'Đồng bộ hoá đơn LinkQ', 'icon': '🧾', 'category': 'Kế toán', 'version': 1, 'form': []},
        ]}),
      '/__apps/flows/instances' => _json({'instances': []}),
      '/__apps/flows/tasks' => _json({'tasks': []}),
      '/__apps/flows/me' => _json({'id': 'me', 'admin': true, 'viewer': true}),
      _ => _json({}),
    };
  });

  Future<void> snap(WidgetTester t, String? shot) async {
    final key = find.byType(RepaintBoundary).first;
    if (out == null || shot == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(key) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$shot.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> pump(WidgetTester t, Size size, Widget home, String? shot, {Brightness b = Brightness.light}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: home)),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    await snap(t, shot);
  }

  Uri last(String path) => requests.lastWhere((u) => u.path == path);

  testWidgets('điện thoại: tiến trình mở làm gốc của khung lồng vẫn có nút quay lại; báo cáo ở đầu, các bước bên dưới', (t) async {
    await pump(t, const Size(430, 900), Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => ProcessDetailPage(app: app, processId: 'P-8K2Q4M')),
              ))),
          child: const Text('mở'),
        )))), null);
    await t.tap(find.text('mở'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProcessDetailPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget, reason: 'Sếp 12/11: mở tiến trình trên điện thoại phải có nút quay lại');
    // Báo cáo (thống kê) trước các bước.
    expect(t.getTopLeft(find.textContaining('128.450.000').first).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('flow-rail'))).dy));
    await t.tap(find.byType(BackButton));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
    expect(find.byType(ProcessDetailPage), findsNothing);
    expect(find.text('mở'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Tiến trình: tab cuối của Quy trình, 3 tab, bộ lọc, ô tìm', (t) async {
    if (out != null) await t.runAsync(_fonts);
    await pump(t, const Size(430, 900), FlowsHome(app: app, initialSection: 1, debugPins: const []), 'process-list');
    expect(find.text('Việc của tôi'), findsNothing, reason: 'bỏ nút chuyển Việc của tôi / Tiến trình, Tiến trình là một tab');
    expect(find.text('Theo dõi'), findsOneWidget);
    final q0 = last('/__apps/flows/processes').queryParameters;
    expect(q0['state'], 'running');
    expect(q0['limit'], '50', reason: 'một trang 50 dòng, cuộn tới cuối thì tải thêm');
    expect(find.text('Hoá đơn 2154 · Cty Hoàng Long'), findsOneWidget);
    // Nhãn trạng thái chỉ để cảnh báo (Sếp 11/11): "Chờ kế toán ký" (cam) trùng ý bước "Kế toán ký" thì bỏ; trạng thái
    // xanh "Đang kiểm tra trùng" không hiện; mỗi dòng có thanh tiến độ theo bước.
    expect(find.text('Chờ kế toán ký'), findsNothing);
    expect(find.text('Đang kiểm tra trùng'), findsNothing);
    expect(find.text('Bước: Kế toán ký'), findsOneWidget);
    expect(find.byKey(const ValueKey('process-steps-bar')), findsNWidgets(2));
    expect(find.text('2/4'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    expect(find.text('KLTM'), findsOneWidget);
    expect(find.text('ABC Capital'), findsOneWidget);
    // Tiến độ của luồng đang chạy ngay trên dòng (như trang chi tiết).
    expect(find.text('44% · Đã kiểm 4/9'), findsOneWidget);
    expect(find.textContaining('128.450.000'), findsNWidgets(2));
    expect(find.textContaining('Số dòng'), findsNothing, reason: 'chỉ 1–2 thống kê chính');

    // Tab Lỗi.
    await t.tap(find.descendant(of: find.byType(ProcessesView), matching: find.text('Lỗi')));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(last('/__apps/flows/processes').queryParameters['state'], 'failed');
    expect(find.text('Hoá đơn 2101 · Cty An Bình'), findsOneWidget);
    expect(find.text('Không lấy được XML'), findsOneWidget);
    await snap(t, 'process-list-failed');

    // Tab Đã xong: done + cancelled + skipped.
    await t.tap(find.descendant(of: find.byType(ProcessesView), matching: find.text('Đã xong')));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(last('/__apps/flows/processes').queryParameters['state'], 'done,cancelled,skipped');
    expect(find.text('Hoá đơn 2050 · Cty Sao Mai'), findsOneWidget);

    await t.tap(find.text('Đang chạy').first);
    await t.pumpAndSettle(const Duration(milliseconds: 100));

    // Bộ lọc: một nút bên phải ô tìm → hộp thoại (quy trình, nhãn, bước), Áp dụng mới tải lại.
    expect(find.text('Nhãn'), findsNothing);
    Future<void> filter(List<String> pick) async {
      await t.tap(find.byKey(const ValueKey('process-filter')));
      await t.pumpAndSettle();
      for (final x in pick) {
        await t.ensureVisible(find.widgetWithText(ChoiceChip, x));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(ChoiceChip, x));
        await t.pumpAndSettle();
      }
      await t.tap(find.widgetWithText(FilledButton, 'Áp dụng'));
      await t.pumpAndSettle(const Duration(milliseconds: 100));
    }

    // Lọc theo nhãn.
    await filter(['Nghi trùng']);
    expect(last('/__apps/flows/processes').queryParameters['label'], 'Nghi trùng');
    expect(find.text('Hoá đơn 2155 · Cty Minh Phát'), findsOneWidget);
    expect(find.text('Hoá đơn 2154 · Cty Hoàng Long'), findsNothing);

    // Lọc theo quy trình rồi theo bước.
    await filter(['🧾 Đồng bộ hoá đơn LinkQ']);
    expect(last('/__apps/flows/processes').queryParameters['flow'], 'linkq');
    await t.tap(find.byKey(const ValueKey('process-filter')));
    await t.pumpAndSettle();
    expect(find.text('Báo cáo'), findsOneWidget, reason: 'lọc theo quy trình thì có lối vào báo cáo');
    await t.tap(find.widgetWithText(ChoiceChip, 'Kiểm tra trùng'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Áp dụng'));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    final qf = last('/__apps/flows/processes').queryParameters;
    expect(qf['step'], 'kiem');
    expect(qf['flow'], 'linkq');
    expect(qf['label'], 'Nghi trùng');
    await snap(t, 'process-list-filtered');

    // Ô tìm (gửi lên máy chủ sau khi ngừng gõ).
    await t.enterText(find.byType(TextField), 'minh');
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 100));
    expect(last('/__apps/flows/processes').queryParameters['q'], 'minh');

    // Tự làm mới sau 5 giây.
    final n = requests.where((u) => u.path == '/__apps/flows/processes').length;
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 100));
    expect(requests.where((u) => u.path == '/__apps/flows/processes').length, greaterThan(n));

    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Chi tiết tiến trình: bước, thống kê, tệp, thẻ đã gửi, lịch sử, việc tạo ra', (t) async {
    if (out != null) await t.runAsync(_fonts);
    await pump(t, const Size(430, 1500), ProcessDetailPage(app: app, processId: 'P-8K2Q4M'), 'process-detail');
    expect(last('/__apps/flows/processes/P-8K2Q4M').path, '/__apps/flows/processes/P-8K2Q4M');
    expect(find.text('Hoá đơn 2154 · Cty Hoàng Long'), findsOneWidget);
    expect(find.text('Đang chạy'), findsOneWidget);
    expect(find.text('Chờ kế toán ký'), findsNWidgets(2), reason: 'nhãn trạng thái + dòng lịch sử');
    for (final x in ['Nhận hoá đơn', 'Kiểm tra trùng', 'Kế toán ký', 'Gửi khách']) {
      expect(find.text(x), findsOneWidget, reason: x);
    }
    expect(find.byType(ProcessStepDot), findsNWidgets(5), reason: '4 bước + nút "Tạo tiến trình" của đường thời gian');
    expect(find.text('128.450.000'), findsOneWidget);
    expect(find.text('Cty Hoàng Long'), findsOneWidget);
    expect(find.text('KLTM'), findsOneWidget);
    expect(find.text('hoadon-2154.pdf'), findsOneWidget);
    expect(find.text('Chứng từ LinkQ'), findsOneWidget);
    expect(find.textContaining('linkq.vn'), findsOneWidget);
    expect(find.text('Kênh c-kt'), findsOneWidget);
    expect(find.text('Tin nhắn riêng: Lan Kế toán'), findsOneWidget);
    // Không hiện mã nội bộ (mã tiến trình, khoá, mã luồng); "Sao chép mã" ở menu.
    expect(find.text('Tạo bởi tiến trình'.toUpperCase()), findsNothing, reason: 'bỏ mục Tạo bởi (Sếp 11/11: ảnh hiển thị sai)');
    expect(find.textContaining('Tạo lúc'), findsNothing);
    expect(find.textContaining('i-77'), findsNothing);
    expect(find.textContaining('P-8K2Q4M'), findsNothing);
    expect(find.textContaining('dedup-'), findsNothing);
    expect(find.byTooltip('Thêm'), findsOneWidget);
    expect(find.text('Tạo tiến trình'), findsOneWidget);
    expect(find.text('Chuyển sang bước «Kế toán ký»'), findsOneWidget);
    expect(find.text('Chờ kế toán ký'), findsWidgets);
    expect(find.textContaining('· Lan Kế toán'), findsOneWidget);
    expect(find.textContaining('· Quy trình'), findsOneWidget, reason: 'quy trình tự ghi: "Quy trình", không hiện mã');
    expect(find.textContaining('buoc'), findsNothing, reason: 'không hiện mã bước');
    expect(find.textContaining('status_text'), findsNothing, reason: 'không hiện khoá thô');
    // Tải tệp qua Flows.
    await t.tap(find.text('hoadon-2154.pdf'));
    await t.pump(const Duration(milliseconds: 300));
    expect(requests.map((u) => u.path), contains('/__apps/flows/processes/P-8K2Q4M/files/f1'));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('Báo cáo tiến trình: khoảng ngày, nhãn, theo trạng thái / bước, thống kê, biểu đồ ngày', (t) async {
    if (out != null) await t.runAsync(_fonts);
    await pump(t, const Size(430, 1300), ProcessReportPage(app: app, flowId: 'linkq', flowName: 'Đồng bộ hoá đơn LinkQ', labels: const ['KLTM', 'Nghi trùng']), 'process-report');
    var q = last('/__apps/flows/defs/linkq/report').queryParameters;
    final from = int.parse(q['from']!), to = int.parse(q['to']!);
    expect(to - from, inInclusiveRange(29 * 86400000, 30 * 86400000 + 3600000));
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Lỗi'), findsNWidgets(2), reason: 'thanh trạng thái + chú thích biểu đồ');
    for (final x in ['Đang chạy', 'Hoàn thành', 'Đã huỷ', 'Nhận hoá đơn', 'Kế toán ký']) {
      expect(find.text(x), findsOneWidget, reason: x);
    }
    expect(find.text('Tổng 5.394.900.000'), findsOneWidget);
    expect(find.text('TB 128.450.000 · 42 tiến trình'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ProcessDailyChart), findsOneWidget);

    await t.tap(find.text('7 ngày'));
    await t.pump(const Duration(milliseconds: 300));
    q = last('/__apps/flows/defs/linkq/report').queryParameters;
    expect(int.parse(q['to']!) - int.parse(q['from']!), lessThan(7 * 86400000));

    await t.tap(find.text('Nhãn'));
    await t.pumpAndSettle();
    await t.tap(find.text('KLTM').last);
    await t.pumpAndSettle();
    expect(last('/__apps/flows/defs/linkq/report').queryParameters['label'], 'KLTM');
    await t.pumpWidget(const SizedBox.shrink());

    await pump(t, const Size(430, 1300), ProcessReportPage(app: app, flowId: 'linkq', flowName: 'Đồng bộ hoá đơn LinkQ', labels: const ['KLTM']), 'process-report-dark',
        b: Brightness.dark);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
