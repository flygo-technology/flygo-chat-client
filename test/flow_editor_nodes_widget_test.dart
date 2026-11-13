import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_vars.dart';
import 'package:flygo_chat/ui/flygo_card.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Ô cấu hình của các bước mới dựng được (không lỗi bố cục), thẻ xem trước cập nhật khi gõ, sơ đồ vẽ đủ các nhánh.
/// Ảnh (chạy tay): `EDITOR_OUT=<thư mục> flutter test test/flow_editor_nodes_widget_test.dart`
void main() {
  final out = Platform.environment['EDITOR_OUT'];
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.channels['c1'] = MmChannel({'id': 'c1', 'name': 'ke-toan', 'display_name': 'Kế toán', 'type': 'P'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));

  Future<void> fonts() async {
    final dir = '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts';
    Future<void> load(String family, List<String> files) async {
      final l = FontLoader(family);
      for (final f in files) {
        final b = File('$dir/$f');
        if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
      }
      await l.load();
    }

    await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
    await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  }

  Map<String, dynamic> def() => {
        'id': 'HD0001',
        'name': 'Đồng bộ hoá đơn',
        'form': [
          {'key': 'so_hd', 'label': 'Số hoá đơn', 'type': 'text'},
          {'key': 'tong', 'label': 'Tổng tiền', 'type': 'money'},
        ],
        'nodes': [
          {'id': 'start', 'type': 'start'},
          {
            'id': 'tao', 'type': 'process_create', 'name': 'Tạo hoá đơn', 'key': '{{form.so_hd}}', 'title': 'Hoá đơn {{form.so_hd}}', 'icon': '🧾',
            'steps': [{'key': 'nhan', 'title': 'Nhận'}, {'key': 'ky', 'title': 'Ký số'}],
            'stats': [{'key': 'tien', 'label': 'Tổng tiền', 'type': 'number', 'value': 0}],
          },
          {
            'id': 'gui', 'type': 'card_send', 'name': 'Báo kế toán', 'channels': ['c1'],
            'card': {'v': 1, 'icon': 'invoice', 'accent': 'blue', 'title': 'Hoá đơn {{form.so_hd}}', 'hero': {'value': '{{form.tong}}'}, 'actions': [{'label': 'Đã ký', 'id': 'ok', 'style': 'primary'}]},
          },
          {
            'id': 'pd', 'type': 'approval_request', 'name': 'Duyệt xuất', 'title': 'Xuất hoá đơn {{form.so_hd}}', 'approver': {'role': 'ke_toan_truong'}, 'due': '24h',
            'return_steps': ['start'], 'escalate': [{'after': '8h', 'to': {'role': 'giam_doc'}, 'mode': 'add'}],
            'approve_to': 'cho', 'reject_to': 'tu_choi', 'always_to': 'bao', 'timeout_to': 'end',
          },
          {'id': 'bao', 'type': 'process_step', 'process': {'step': 'tao'}, 'step': 'ky', 'status_text': 'Chờ duyệt'},
          {'id': 'tu_choi', 'type': 'process_fail', 'process': {'step': 'tao'}, 'reason': 'Bị từ chối'},
          {
            'id': 'cho', 'type': 'wait_button', 'name': 'Kế toán xác nhận', 'who': {'role': 'ke_toan'}, 'where': {'process': {'step': 'tao'}, 'task': true}, 'timeout': '8h',
            'buttons': [{'id': 'ok', 'label': 'Đã ký', 'style': 'primary', 'to': 'xong'}, {'id': 'pdf', 'label': 'Xem PDF', 'url': 'https://pdf'}],
          },
          {'id': 'xong', 'type': 'process_finish', 'process': {'step': 'tao'}, 'result': 'done'},
          {'id': 'end', 'type': 'end'},
        ],
        'edges': [['start', 'tao'], ['tao', 'gui'], ['gui', 'pd'], ['bao', 'end'], ['tu_choi', 'end_rejected'], ['xong', 'end']],
      };

  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child),
      );

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final ro = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      final img = await ro.toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('ô cấu hình của mọi bước mới dựng được', (t) async {
    t.view.physicalSize = const Size(900, 9000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = FlowDoc.fromJson(def());
    for (final type in editorNodeTypes) {
      final s = FlowDoc.make(type) as FStep;
      doc.steps.add(s);
      editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
      await t.pumpWidget(wrap(Scaffold(
        body: StepConfigSheet(key: ValueKey(type), app: app, node: s.node, form: FlowField.listOf(doc.meta['form']), roles: const {}, vars: flowVars(doc, at: s), onDone: (_) {}),
      )));
      await t.pump();
      expect(t.takeException(), isNull, reason: type);
      expect(find.text(stepLook(type).$3), findsWidgets, reason: type);
      doc.remove(s.id);
    }
  });

  testWidgets('soạn thẻ: xem trước bằng thẻ thật, gõ tiêu đề là thấy ngay', (t) async {
    await fonts();
    t.view.physicalSize = const Size(520, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('card_send') as FStep;
    doc.steps.add(s);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    Object? done;
    await t.pumpWidget(wrap(RepaintBoundary(
      key: const ValueKey('shot'),
      child: Scaffold(body: StepConfigSheet(app: app, node: s.node, form: FlowField.listOf(doc.meta['form']), roles: const {}, vars: flowVars(doc, at: s), onDone: (r) => done = r)),
    )));
    expect(find.byType(FlygoCard), findsOneWidget);
    expect(find.text('(chưa có tiêu đề)'), findsOneWidget);
    final title = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Tiêu đề thẻ *');
    await t.enterText(title, 'Hoá đơn mới');
    await t.pump();
    expect(find.text('Hoá đơn mới'), findsWidgets);
    expect(find.descendant(of: find.byType(FlygoCard), matching: find.text('Hoá đơn mới')), findsOneWidget);
    await t.tap(find.text('Thêm nhóm'));
    await t.pumpAndSettle();
    await t.tap(find.text('Kế toán').last);
    await t.pumpAndSettle();
    await shot(t, 'card_send_config');
    await t.tap(find.text('Xong'));
    final r = done as Map;
    expect((r['card'] as Map)['title'], 'Hoá đơn mới');
    expect((r['card'] as Map)['v'], 1);
    expect(r['channels'], ['c1']);
  });

  testWidgets('chờ bấm nút: thêm nút, nút mở link không thành nhánh', (t) async {
    t.view.physicalSize = const Size(700, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('wait_button') as FStep;
    doc.steps.add(s);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    Object? done;
    await t.pumpWidget(wrap(Scaffold(
      body: StepConfigSheet(app: app, node: s.node, form: const [], roles: const {}, vars: flowVars(doc, at: s), onDone: (r) => done = r),
    )));
    await t.tap(find.text('Thêm nút'));
    await t.pump();
    await t.tap(find.text('Chỉ mở link').last);
    await t.pump();
    await t.tap(find.text('Xong'));
    s.node = (done as Map).cast<String, dynamic>();
    s.syncPorts();
    expect((s.node['buttons'] as List).length, 3);
    expect(s.ports.map((p) => p.key).where((k) => k.startsWith('b:')).length, 2);
  });

  testWidgets('sơ đồ: bước nhiều cổng vẽ mỗi nhánh một cột có nhãn', (t) async {
    await fonts();
    t.view.physicalSize = const Size(1400, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(RepaintBoundary(key: const ValueKey('shot'), child: FlowEditorPage(app: app, api: api, doc: FlowDoc.fromJson(def())))));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
    for (final l in ['Luôn chạy', 'Phê duyệt', 'Từ chối', 'Leo thang', 'Quá hạn (24 giờ)', 'Đã ký', 'Quá hạn (8 giờ)']) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    expect(find.text('Kết thúc: bị từ chối'), findsOneWidget);
    expect(find.text('Xem PDF'), findsNothing, reason: 'nút chỉ mở link không có nhánh');
    expect(find.text('Hết nhánh'), findsWidgets);
    await shot(t, 'diagram_ports');
    // Chạm nhãn nhánh: chọn kết thúc việc khi hết nhánh.
    await t.tap(find.text('Phê duyệt'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hết nhánh thì kết thúc tiến trình'));
    await t.pumpAndSettle();
    expect(find.text('Kết thúc tiến trình'), findsWidgets);
  });
}
