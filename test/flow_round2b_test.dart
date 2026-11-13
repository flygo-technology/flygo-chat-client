// Flows đợt 2b: chờ tới mốc có lệch (offset), Nhắc theo mốc, Chờ sự kiện theo khoá, hạn bước (SLA), bước quá hạn trên
// trang tiến trình / danh sách, Bảng theo dõi, Thời gian theo bước. Ảnh (chạy tay):
// EDITOR_OUT=<thư mục> flutter test test/flow_round2b_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_errors.dart';
import 'package:flygo_chat/ui/flows/process_board.dart';
import 'package:flygo_chat/ui/flows/process_detail.dart';
import 'package:flygo_chat/ui/flows/process_report.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts';
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
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.channels['c-kho'] = MmChannel({'id': 'c-kho', 'name': 'kho', 'display_name': 'Kho vận', 'type': 'P'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));

  Future<void> snap(WidgetTester t, String shot) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$shot.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: RepaintBoundary(child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child)),
      );

  Map<String, dynamic> def() => {
        'id': 'container',
        'name': 'Container',
        'form': [
          {'key': 'so_cont', 'label': 'Số container', 'type': 'text'},
          {'key': 'ngay_tau', 'label': 'Ngày tàu chạy', 'type': 'date'},
        ],
        'nodes': [
          {'id': 'start', 'type': 'start'},
          {
            'id': 'tao', 'type': 'process_create', 'name': 'Tạo container', 'key': '{{form.so_cont}}', 'title': 'Container {{form.so_cont}}',
            'steps': [
              {'key': 'dong', 'title': 'Đóng hàng', 'sla': '2d', 'escalate_to': {'role': 'kho'}},
              {'key': 'to_khai', 'title': 'Tờ khai', 'sla': '3wd'},
            ],
            'props': {'eta': '{{form.ngay_tau}}'}, 'fields': [{'prop': 'eta', 'label': 'ETA'}],
          },
          {'id': 'nhac', 'type': 'process_remind', 'name': 'Nhắc hải quan', 'process': {'step': 'tao'}, 'at': 'process.props.eta', 'offset': '-3d', 'to': [{'role': 'hai_quan'}], 'message': 'Sắp tới ETA', 'repeat': '1d'},
          {'id': 'cho', 'type': 'wait', 'name': 'Chờ gần ETA', 'until': 'process.props.eta', 'offset': '-2wd'},
          {'id': 'tau', 'type': 'wait_event', 'name': 'Chờ tàu cập', 'match': {'key': 'TAU-{{form.so_cont}}', 'source': 'chat', 'channels': ['c-kho']}, 'timeout': '7d'},
          {'id': 'end', 'type': 'end'},
        ],
        'edges': [['start', 'tao'], ['tao', 'nhac'], ['nhac', 'cho'], ['cho', 'tau'], ['tau', 'end']],
      };

  test('Tóm tắt: chờ tới mốc có lệch, nhắc theo mốc, chờ sự kiện theo khoá; wait_event theo khoá không có thời hạn mỗi lần gọi', () {
    final doc = FlowDoc.fromJson(def());
    final vars = flowVars(doc);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: vars);
    addTearDown(() => editorCtx = null);
    String sum(String id) => stepSummary(doc.allSteps.firstWhere((s) => s.id == id), app, vars);
    expect(sum('cho'), 'Chờ tới Tiến trình › Thuộc tính › ETA (trước 2 ngày làm việc)');
    expect(sum('tau'), 'Sự kiện khoá TAU-«Số container» · Tin nhắn nhóm · tối đa 7 ngày');
    expect(sum('nhac'), contains('Lúc «Tiến trình › Thuộc tính › ETA»'));
    expect(sum('nhac'), contains('(trước 3 ngày)'));
    expect(sum('nhac'), contains('nhắc lại mỗi 1 ngày'));
    expect(callTimeoutKey({'type': 'wait_event', 'match': {'key': 'x'}}), isNull);
    expect(callTimeoutKey({'type': 'wait_event'}), 'call_timeout');
    // Lưu lại giữ nguyên các trường mới.
    final j = doc.toJson();
    final nodes = {for (final n in j['nodes'] as List) '${n['id']}': n as Map};
    expect(nodes['cho']!['offset'], '-2wd');
    expect((nodes['tao']!['steps'] as List).first['sla'], '2d');
    expect(nodes['tau']!['match'], {'key': 'TAU-{{form.so_cont}}', 'source': 'chat', 'channels': ['c-kho']});
  });

  Future<Map> config(WidgetTester t, FlowDoc doc, FStep s, Future<void> Function() act, {String? shot, double h = 1300}) async {
    if (out != null) await t.runAsync(_fonts);
    await t.pumpWidget(const SizedBox.shrink());
    t.view.physicalSize = Size(520, h);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    addTearDown(() => editorCtx = null);
    Object? done;
    await t.pumpWidget(wrap(Scaffold(
      body: StepConfigSheet(app: app, node: s.node, form: FlowField.listOf(doc.meta['form']), roles: const {}, vars: flowVars(doc, at: s), onDone: (r) => done = r),
    )));
    await t.pump();
    await act();
    if (shot != null) await snap(t, shot);
    await t.tap(find.text('Xong'));
    return done as Map;
  }

  testWidgets('Chờ: mốc lấy cả thuộc tính tiến trình, chọn lệch so với mốc', (t) async {
    final doc = FlowDoc.fromJson(def());
    final r = await config(t, doc, doc.allSteps.firstWhere((s) => s.id == 'cho'), () async {
      expect(find.text('Tiến trình › Thuộc tính › ETA'), findsOneWidget);
      expect(find.text('Lệch so với mốc'), findsOneWidget);
      await t.tap(find.text('trước 3 ngày'));
      await t.pump();
    });
    expect(r['until'], 'process.props.eta');
    expect(r['offset'], '-3d');
  });

  testWidgets('Nhắc theo mốc: tiến trình, mốc, lệch, người nhận, nội dung, nhắc lại', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('process_remind') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      expect(find.text('Tiến trình › Thuộc tính › ETA'), findsOneWidget, reason: 'mốc mặc định ETA');
      expect(find.text('trước 3 ngày'), findsOneWidget);
      await t.tap(find.text('1 ngày'));
      await t.pump();
    }, shot: 'r2-editor-remind');
    expect(r['process'], {'step': 'tao'});
    expect(r['at'], 'process.props.eta');
    expect(r['offset'], '-3d');
    expect(r['repeat'], '1d');
  });

  testWidgets('Chờ sự kiện: chuyển sang "Chờ sự kiện theo khoá", nguồn tin nhắn nhóm, chọn nhóm', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('wait_event') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      await t.tap(find.text('Chờ sự kiện theo khoá'));
      await t.pump();
      expect(find.text('Khoá sự kiện (vd TAU-{{số PO}})'), findsOneWidget);
      expect(find.text('Mỗi lần gọi tối đa'), findsNothing);
      await t.tap(find.text('Tin nhắn nhóm'));
      await t.pump();
      await t.tap(find.text('Thêm nhóm'));
      await t.pumpAndSettle();
      await t.tap(find.text('Kho vận'));
      await t.pumpAndSettle();
      expect(find.text('Kho vận'), findsOneWidget);
    }, shot: 'r2-editor-wait-event-match');
    expect(r['match'], {'key': '', 'source': 'chat', 'channels': ['c-kho']});
    for (final k in ['server', 'tool', 'cond', 'seconds']) {
      expect(r.containsKey(k), isFalse, reason: k);
    }
  });

  testWidgets('Tạo tiến trình: hạn bước và người nhận báo quá hạn cho từng bước', (t) async {
    final doc = FlowDoc.fromJson(def());
    final r = await config(t, doc, doc.allSteps.firstWhere((s) => s.id == 'tao'), () async {
      expect(find.text('Hạn bước'), findsNWidgets(2));
      expect(find.text('Báo quá hạn cho'), findsNWidgets(2));
      await t.enterText(find.widgetWithText(TextFormField, 'Hạn bước').last, '8h');
      await t.pump();
    }, h: 2400);
    expect((r['steps'] as List)[1]['sla'], '8h');
    expect((r['steps'] as List)[0]['escalate_to'], {'role': 'kho'});
  });

  // ------------------------------------------------------------------ trang tiến trình, bảng theo dõi, báo cáo

  final now = DateTime.now().millisecondsSinceEpoch;
  const hour = 3600000;
  final detail = {
    'id': 'P-C2', 'flow_id': 'container', 'flow_name': 'Container (mẫu)', 'flow_icon': '🚢', 'key': 'MSKU7654321', 'name': 'Container MSKU 765432-1', 'icon': '🚢',
    'state': 'running', 'current_step': 'to_khai', 'status_text': 'Chờ tờ khai', 'tone': 'orange', 'overdue': true,
    'steps': [
      {'key': 'dong', 'title': 'Đóng hàng', 'state': 'done', 'started_at': now - 120 * hour, 'ended_at': now - 80 * hour, 'sla': '2d', 'due_at': now - 72 * hour, 'overdue': false},
      {'key': 'to_khai', 'title': 'Tờ khai', 'state': 'active', 'started_at': now - 80 * hour, 'sla': '2d', 'due_at': now - 32 * hour, 'overdue': true},
      {'key': 've_kho', 'title': 'Về kho', 'state': 'pending'},
    ],
    'stats': [], 'labels': [], 'created_at': now - 120 * hour, 'updated_at': now - hour, 'events': [],
  };
  Map<String, dynamic> row(String id, String name, String flow, String flowName, String step, int ageH, String sla, List<(String, String)> who) => {
        'id': id, 'name': name, 'icon': '📦', 'flow_id': flow, 'flow_name': flowName, 'flow_icon': '📦', 'state': 'running', 'status_text': '', 'tone': 'blue',
        'current_step': 'x', 'current_step_title': step, 'since': now - ageH * hour, 'age_ms': ageH * hour,
        'sla': {'state': sla, 'due_at': now, 'sla': '2d'},
        'assignees': [for (final (n, d) in who) {'id': 'u-$n', 'name': n, 'since': now - ageH * hour, 'departments': d.isEmpty ? [] : [{'id': d, 'name': d == 'kho' ? 'Kho vận' : 'Kế toán'}]}],
        'departments': [for (final d in {for (final (_, d) in who) if (d.isNotEmpty) d}) {'id': d, 'name': d == 'kho' ? 'Kho vận' : 'Kế toán'}],
      };
  final board = {
    'processes': [
      row('P-C2', 'Container MSKU 765432-1', 'container', 'Container (mẫu)', 'Tờ khai', 80, 'overdue', [('Hải Quan Minh', 'kho')]),
      row('P-T2', 'Thanh toán còn lại 70%', 'thanh-toan', 'Thanh toán (mẫu)', 'Sếp duyệt', 28, 'warn', [('Lan Kế toán', 'ke_toan')]),
      row('P-C3', 'Container CSNU 112233-4', 'container', 'Container (mẫu)', 'Trên biển', 5, 'ok', [('Tuấn Kho', 'kho')]),
      row('P-X1', 'Đơn nhập PO-2026-0002', 'don-nhap', 'Đơn nhập (mẫu)', 'Kiểm & gom', 3, 'none', []),
    ],
    'departments': [{'id': 'kho', 'name': 'Kho vận'}, {'id': 'ke_toan', 'name': 'Kế toán'}],
    'flows': [{'id': 'container', 'name': 'Container (mẫu)'}, {'id': 'thanh-toan', 'name': 'Thanh toán (mẫu)'}, {'id': 'don-nhap', 'name': 'Đơn nhập (mẫu)'}],
    'now': now,
  };
  final steps = {
    'flow': 'container', 'flow_name': 'Container (mẫu)', 'total': 18,
    'steps': [
      {'key': 'dong', 'title': 'Đóng hàng', 'sla': '2d', 'count': 18, 'active': 0, 'avg_ms': 30 * hour, 'p50_ms': 26 * hour, 'p90_ms': 50 * hour, 'overdue': 2},
      {'key': 'to_khai', 'title': 'Tờ khai', 'sla': '2d', 'count': 12, 'active': 4, 'avg_ms': 41 * hour, 'p50_ms': 36 * hour, 'p90_ms': 80 * hour, 'overdue': 5},
      {'key': 've_kho', 'title': 'Về kho', 'sla': '', 'count': 9, 'active': 3, 'avg_ms': 5 * hour, 'p50_ms': 4 * hour, 'p90_ms': 9 * hour, 'overdue': 0},
    ],
  };
  final requests = <Uri>[];
  setUp(() {
    FlowsApi.debugClient = MockClient((r) async {
      requests.add(r.url);
      final q = r.url.queryParameters;
      return switch (r.url.path) {
        '/__apps/flows/processes/P-C2' => _json(detail),
        '/__apps/flows/board' => _json({
            ...board,
            'processes': [
              for (final p in board['processes'] as List)
                if ((q['overdue'] != '1' || (p as Map)['sla']['state'] == 'overdue') && (q['flow'] == null || (p as Map)['flow_id'] == q['flow'])) p,
            ],
          }),
        '/__apps/flows/reports/steps' => _json(steps),
        '/__apps/flows/defs/container/report' => _json({'total': 18, 'by_state': {'running': 7, 'done': 11}, 'by_step': [], 'stats': [], 'daily': []}),
        '/__apps/flows/processes' => _json({'processes': []}),
        _ => _json({}),
      };
    });
  });
  tearDown(() => FlowsApi.debugClient = null);

  Future<void> pumpPage(WidgetTester t, Size size, Widget home) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(home));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Trang tiến trình: bước quá hạn hiện "Quá hạn" màu cam, bước đang làm có "Hạn: …"', (t) async {
    await pumpPage(t, const Size(430, 800), ProcessDetailPage(app: app, processId: 'P-C2'));
    expect(find.text('Quá hạn'), findsOneWidget);
    expect(find.textContaining('Hạn: '), findsOneWidget);
    expect(FlowProcess.fromJson(detail).overdue, isTrue);
    await snap(t, 'r2-qua-han');
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Bảng theo dõi: nhóm theo phòng ban / quy trình, chip Quá hạn / Sắp hạn, lọc chỉ quá hạn, bấm mở tiến trình', (t) async {
    await pumpPage(t, const Size(430, 900), Scaffold(body: ProcessBoardView(app: app)));
    expect(requests.last.path, '/__apps/flows/board');
    for (final g in ['Kho vận', 'Kế toán', 'Chưa có phòng ban']) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
    expect(find.text('Quá hạn'), findsOneWidget);
    expect(find.text('Sắp hạn'), findsOneWidget);
    expect(find.text('ở bước 3 ngày 8 giờ'), findsOneWidget);
    expect(find.text('Hải Quan Minh'), findsOneWidget);
    expect(find.text('Chưa giao ai'), findsOneWidget);
    expect(find.textContaining('P-C'), findsNothing, reason: 'không hiện mã tiến trình');
    await snap(t, 'r2-bang-theo-doi');
    await t.tap(find.text('Theo quy trình'));
    await t.pump();
    expect(find.text('Container (mẫu)'), findsOneWidget, reason: 'tiêu đề nhóm');
    await t.tap(find.text('Chỉ quá hạn (1)'));
    await t.pump(const Duration(milliseconds: 300));
    expect(requests.last.queryParameters['overdue'], '1');
    expect(find.text('Thanh toán còn lại 70%'), findsNothing);
    await t.tap(find.text('Container MSKU 765432-1'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(requests.any((u) => u.path == '/__apps/flows/processes/P-C2'), isTrue);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Báo cáo tiến trình: bảng Thời gian theo bước', (t) async {
    await pumpPage(t, const Size(520, 1300), ProcessReportPage(app: app, flowId: 'container', flowName: 'Container (mẫu)', labels: const []));
    expect(requests.any((u) => u.path == '/__apps/flows/reports/steps' && u.queryParameters['flow'] == 'container'), isTrue);
    await t.ensureVisible(find.byKey(const ValueKey('step-times')));
    await t.pump();
    expect(find.text('Thời gian theo bước'), findsOneWidget);
    expect(find.text('Tờ khai'), findsOneWidget);
    expect(find.text('1 ngày 17 giờ'), findsOneWidget, reason: 'TB của Tờ khai');
    expect(find.text('Hạn 2 ngày'), findsNWidgets(2));
    await snap(t, 'r2-thoi-gian-buoc');
    await t.pumpWidget(const SizedBox.shrink());
  });
}
