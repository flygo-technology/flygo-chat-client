// Flows đợt 2c: nhánh "Khi luồng bị huỷ" (on_cancel), Hoàn thành tiến trình huỷ cả tiến trình con (cascade), Tạo tài liệu
// (doc_render), Huỷ tiến trình từ trang tiến trình, cách xử lý lỗi của Chờ sự kiện theo khoá. Ảnh (chạy tay):
// EDITOR_OUT=<thư mục> flutter test test/flow_round2c_test.dart
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
import 'package:flygo_chat/ui/flows/process_detail.dart';
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


  /// Chờ nhãn ô nhập nổi lên viền: hiệu ứng (~167ms) bắt đầu ở khung hình sau khi gõ, nên cần hai lần vẽ.
  Future<void> settleLabel(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  /// Ô có chữ: nhãn đã nổi lên viền, không còn nằm đè lên chữ đã gõ.
  void expectLabelClear(WidgetTester t, String label) {
    final field = find.ancestor(of: find.text(label), matching: find.byType(TextField));
    expect(field, findsOneWidget);
    final labelBox = t.getRect(find.text(label));
    final textBox = t.getRect(find.descendant(of: field, matching: find.byType(EditableText)));
    expect(labelBox.overlaps(textBox), isFalse, reason: 'nhãn "$label" đè lên chữ đã gõ: $labelBox / $textBox');
    expect(labelBox.bottom, lessThanOrEqualTo(textBox.top));
  }

  Map<String, dynamic> def() => {
        'id': 'hop-dong',
        'name': 'Hợp đồng',
        'form': [
          {'key': 'so_hd', 'label': 'Số hợp đồng', 'type': 'text'},
          {'key': 'mau', 'label': 'Mẫu hợp đồng', 'type': 'files'},
        ],
        'nodes': [
          {'id': 'start', 'type': 'start'},
          {'id': 'tao', 'type': 'process_create', 'name': 'Tạo hợp đồng', 'key': '{{form.so_hd}}', 'title': 'Hợp đồng {{form.so_hd}}', 'steps': [{'key': 'soan', 'title': 'Soạn'}]},
          {
            'id': 'duyet', 'type': 'approval_request', 'name': 'Giám đốc duyệt', 'title': 'Duyệt HĐ', 'approver': {'role': 'giam_doc'},
          },
          {'id': 'end', 'type': 'end'},
          {'id': 'huy_tt', 'type': 'process_finish', 'name': 'Huỷ hợp đồng', 'process': {'step': 'tao'}, 'result': 'cancelled', 'cascade': true},
          {'id': 'bao_huy', 'type': 'send', 'name': 'Báo đã huỷ', 'to': [r'$requester'], 'text': 'Hợp đồng {{form.so_hd}} đã huỷ'},
        ],
        'edges': [['start', 'tao'], ['tao', 'duyet'], ['duyet', 'end'], ['huy_tt', 'bao_huy'], ['bao_huy', 'end']],
        'on_cancel': {'to': 'huy_tt'},
      };

  test('Khi luồng bị huỷ: đọc nhánh on_cancel thành chuỗi riêng, lưu lại giữ nguyên; đánh dấu bước không tự động', () {
    final doc = FlowDoc.fromJson(def());
    expect([for (final x in doc.steps) x.id], ['tao', 'duyet']);
    expect([for (final x in doc.cancelSteps) x.id], ['huy_tt', 'bao_huy']);
    expect(doc.cancelOn, isTrue);
    expect(doc.meta.containsKey('on_cancel'), isFalse);
    final j = doc.toJson();
    expect(j['on_cancel'], {'to': 'huy_tt'});
    final ids = {for (final n in j['nodes'] as List) '${n['id']}'};
    expect(ids.containsAll(['huy_tt', 'bao_huy', 'tao', 'duyet']), isTrue);
    expect((j['edges'] as List).any((e) => e[0] == 'bao_huy' && e[1] == 'end'), isTrue);
    expect(doc.allSteps.map((s) => s.id), containsAll(['huy_tt', 'bao_huy']));
    expect(doc.find('bao_huy'), isNotNull);
    expect(doc.cancelBlockedItems, isEmpty);
    doc.cancelSteps.add(FlowDoc.make('approval_request'));
    doc.cancelSteps.add(FlowDoc.make('wait'));
    doc.cancelSteps.add(FStep({'id': 'sf', 'type': 'start_flow', 'flow_id': 'x', 'wait': true}));
    doc.cancelSteps.add(FStep({'id': 'sf2', 'type': 'start_flow', 'flow_id': 'x'}));
    expect(doc.cancelBlockedItems.length, 3);
    // Không có nhánh: không ghi on_cancel.
    final plain = FlowDoc.fromJson({...def()..remove('on_cancel')});
    expect(plain.cancelSteps, isEmpty);
    expect(plain.toJson().containsKey('on_cancel'), isFalse);
  });

  testWidgets('Sơ đồ: mục "Khi luồng bị huỷ" sau Kết thúc; bật / tắt ở Cài đặt', (t) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = const Size(900, 1500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = FlowDoc.fromJson(def());
    await t.pumpWidget(wrap(FlowEditorPage(app: app, api: api, doc: doc)));
    await t.pump();
    expect(find.text('Khi luồng bị huỷ'), findsOneWidget);
    expect(find.text('Huỷ hợp đồng'), findsOneWidget);
    expect(find.text('Báo đã huỷ'), findsOneWidget);
    expect(find.textContaining('huỷ cả tiến trình con'), findsOneWidget, reason: 'tóm tắt Hoàn thành tiến trình (cascade)');
    expect(find.text('Dừng mọi bước đang chờ, chạy các bước dưới (chỉ bước tự động)'), findsOneWidget);
    await snap(t, 'r2-editor-on-cancel');
    // Bước không tự động trong nhánh: báo đỏ.
    final bad = FlowDoc.fromJson(def())..cancelSteps.add(FStep({'id': 'cho', 'type': 'wait', 'name': 'Chờ 1 ngày', 'for': '1d'}));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpWidget(wrap(FlowEditorPage(app: app, api: api, doc: bad)));
    await t.pump();
    expect(find.text('Có 1 bước không dùng được ở đây (chỉ bước tự động)'), findsOneWidget);
    // Quy trình chưa có nhánh: không có mục; bật ở Cài đặt thì hiện.
    final plain = FlowDoc.fromJson({...def()..remove('on_cancel')});
    expect(plain.cancelOn, isFalse);
    plain.cancelOn = true;
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpWidget(wrap(FlowEditorPage(app: app, api: api, doc: plain)));
    await t.pump();
    expect(find.text('Khi luồng bị huỷ'), findsOneWidget);
  });

  Future<Map> config(WidgetTester t, FlowDoc doc, FStep s, Future<void> Function() act, {String? shot, double h = 1500}) async {
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

  testWidgets('Tạo tài liệu: mẫu từ trường tệp, PDF, tên tệp, nhánh lỗi', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('doc_render') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      expect(find.text('Mẫu hợp đồng'), findsOneWidget, reason: 'tự chọn trường tệp đầu tiên');
      expect(find.textContaining('{{#each form.hang}}'), findsOneWidget);
      await t.tap(find.text('PDF'));
      await t.pump();
      await t.enterText(find.widgetWithText(TextField, 'Tên tệp (vd Hợp đồng {{form.so_hd}})'), 'HĐ {{form.so_hd}}');
      await settleLabel(t);
      expectLabelClear(t, 'Tên tệp (vd Hợp đồng {{form.so_hd}})');
      expect(find.text('Khi tạo tài liệu lỗi'), findsOneWidget);
      expect(find.text('Dừng luồng (mặc định)'), findsOneWidget);
      expect(find.text('Dừng tiến trình, báo lỗi'), findsNothing);
    }, shot: 'r2-editor-doc-render');
    expect(r['type'], 'doc_render');
    expect(r['template'], '{{form.mau}}');
    expect(r['output'], 'pdf');
    expect(r['file_name'], 'HĐ {{form.so_hd}}');
    expect(r['name'], 'Tạo tài liệu', reason: 'tên bước giữ riêng, không lẫn tên tệp');
    // Tóm tắt và kết quả dùng ở bước sau.
    final step = FStep(Map<String, dynamic>.from(r));
    doc.steps.add(step);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps);
    expect(stepSummary(step, app), 'Mẫu: tệp ở "Mẫu hợp đồng" · PDF · “HĐ «Số hợp đồng»”');
    expect(flowVars(doc).any((v) => v.path == 'steps.${step.id}.output.file_id'), isTrue);
    expect(FStep({...r, 'on_error': {'to': 'x'}}).ports.map((p) => p.key), ['ok', 'error']);
    editorCtx = null;
  });

  testWidgets('Bảng thuộc tính: bước ở nhánh khi luồng bị huỷ có ghi chú, bước luồng chính thì không', (t) async {
    final doc = FlowDoc.fromJson(def());
    await config(t, doc, doc.find('bao_huy') as FStep, () async {
      expect(find.text('Thuộc nhánh khi luồng bị huỷ: chỉ bước tự động'), findsOneWidget);
    });
    await config(t, doc, doc.find('tao') as FStep, () async {
      expect(find.text('Thuộc nhánh khi luồng bị huỷ: chỉ bước tự động'), findsNothing);
    });
  });

  testWidgets('Hoàn thành tiến trình: "Huỷ cả tiến trình con" chỉ khi kết quả là Huỷ', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('process_finish') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      expect(find.text('Huỷ cả tiến trình con'), findsNothing);
      await t.tap(find.text('Huỷ'));
      await t.pump();
      await t.tap(find.text('Huỷ cả tiến trình con'));
      await t.pump();
    });
    expect(r['result'], 'cancelled');
    expect(r['cascade'], true);
  });

  testWidgets('Chờ sự kiện theo khoá: lỗi chỉ "Dừng luồng (mặc định)" hoặc "Đi nhánh lỗi"', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FStep({'id': 'ev', 'type': 'wait_event', 'name': 'Chờ tàu', 'match': {'key': 'TAU-1', 'source': 'any'}, 'timeout': '3d'});
    doc.steps.add(s);
    await config(t, doc, s, () async {
      expect(find.text('Khi kho sự kiện lỗi'), findsOneWidget);
      expect(find.text('Dừng luồng (mặc định)'), findsOneWidget);
      await t.tap(find.text('Dừng luồng (mặc định)'));
      await t.pumpAndSettle();
      expect(find.text('Đi nhánh lỗi'), findsWidgets);
      expect(find.text('Hỏi lại lần sau (mặc định)'), findsNothing);
      await t.tap(find.text('Dừng luồng (mặc định)').last);
      await t.pumpAndSettle();
    });
    expect(errorModeLabel('wait_event', 'fail'), 'Hỏi lại lần sau (mặc định)');
  });

  // ------------------------------------------------------------------ huỷ tiến trình

  final now = DateTime.now().millisecondsSinceEpoch;
  final detail = {
    'id': 'P-PO0001', 'flow_id': 'don-nhap', 'flow_name': 'Đơn nhập (mẫu)', 'flow_icon': '📦', 'key': 'PO-2026-0001', 'name': 'Đơn nhập PO-2026-0001', 'icon': '📦',
    'state': 'running', 'current_step': 'tt', 'status_text': 'Chờ thanh toán', 'tone': 'blue',
    'steps': [{'key': 'dat', 'title': 'Đặt đơn', 'state': 'done'}, {'key': 'tt', 'title': 'Thanh toán', 'state': 'active'}],
    'stats': [], 'labels': [], 'created_at': now - 86400000, 'updated_at': now - 3600000, 'events': [], 'can_cancel': true,
    'children': [
      {'id': 'P-C1', 'flow_id': 'container', 'flow_name': 'Container (mẫu)', 'name': 'Container TGHU 123456-7', 'state': 'running', 'current_step_title': 'Trên biển'},
      {'id': 'P-C2', 'flow_id': 'container', 'flow_name': 'Container (mẫu)', 'name': 'Container MSKU 765432-1', 'state': 'done', 'current_step_title': 'Về kho'},
    ],
  };
  final posts = <(String, Object?)>[];
  setUp(() {
    posts.clear();
    FlowsApi.debugClient = MockClient((r) async {
      if (r.method == 'POST' && r.url.path == '/__apps/flows/processes/P-PO0001/cancel') {
        posts.add((r.url.path, jsonDecode(r.body)));
        return _json({'ok': true, 'state': 'cancelled', 'instance_cancelled': true, 'cancelled_children': 1});
      }
      return switch (r.url.path) {
        '/__apps/flows/processes/P-PO0001' => _json(detail),
        _ => _json({}),
      };
    });
  });
  tearDown(() => FlowsApi.debugClient = null);

  testWidgets('Huỷ tiến trình: menu (khi được huỷ), hỏi lại có lý do và "Huỷ cả tiến trình con", gửi lên máy chủ', (t) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = const Size(520, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(ProcessDetailPage(app: app, processId: 'P-PO0001')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byTooltip('Thêm'));
    await t.pumpAndSettle();
    expect(find.text('Huỷ tiến trình'), findsOneWidget);
    await t.tap(find.text('Huỷ tiến trình'));
    await t.pumpAndSettle();
    expect(find.text('Huỷ tiến trình?'), findsOneWidget);
    expect(find.text('1 tiến trình con chưa xong (và tiến trình cháu)'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Khách huỷ đơn');
    await t.tap(find.text('Huỷ cả tiến trình con'));
    await settleLabel(t);
    expectLabelClear(t, 'Lý do (không bắt buộc)');
    await snap(t, 'r2-huy-tien-trinh');
    await t.tap(find.widgetWithText(FilledButton, 'Huỷ tiến trình'));
    await t.pump(const Duration(milliseconds: 300));
    expect(posts.single.$2, {'reason': 'Khách huỷ đơn', 'cascade': true});
    expect(find.text('Đã huỷ tiến trình và 1 tiến trình con'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Huỷ tiến trình: không có quyền thì không có mục trong menu', (t) async {
    detail['can_cancel'] = false;
    addTearDown(() => detail['can_cancel'] = true);
    t.view.physicalSize = const Size(520, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(ProcessDetailPage(app: app, processId: 'P-PO0001')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byTooltip('Thêm'));
    await t.pumpAndSettle();
    expect(find.text('Huỷ tiến trình'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
