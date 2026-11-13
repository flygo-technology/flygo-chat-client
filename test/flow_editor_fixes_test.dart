import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_tables.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Sửa trình soạn theo Sếp (F1 hoá đơn): thông tin chọn theo khuôn kết quả công cụ, khung Lặp bảng có hộp, điều kiện so
/// hai thông tin bằng giao diện, Ctrl / Cmd + cuộn để phóng.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child),
      );

  final integ = {
    'mcp': [
      {
        'name': 'vn.example.minvoice',
        'app': 'vn.example.minvoice',
        'tools': [
          {
            'name': 'lap_payload_hoa_don',
            'read_only': true,
            'output_schema': {
              'type': 'object',
              'properties': {
                'hop_le': {'type': 'boolean', 'description': 'Hợp lệ'},
                'loi_text': {'type': 'string', 'description': 'Nội dung lỗi. Dùng để báo kế toán'},
                'tong': {'type': 'object', 'properties': {'tien': {'type': 'number', 'description': 'Tổng tiền'}}},
                'rows': {
                  'type': 'array',
                  'description': 'Các dòng',
                  'items': {'type': 'object', 'properties': {'so_ct': {'type': 'string', 'description': 'Số chứng từ'}, 'cho_xuat': {'type': 'boolean', 'description': 'Chờ xuất'}}},
                },
              },
            },
          },
        ],
      },
    ],
  };

  Map<String, dynamic> def() => {
        'id': 'P5F68Z',
        'name': 'HĐ',
        'nodes': [
          {'id': 'start', 'type': 'start'},
          {'id': 'lp', 'type': 'auto', 'action': 'mcp', 'name': 'Lập payload hoá đơn', 'params': {'app': 'vn.example.minvoice', 'tool': 'lap_payload_hoa_don', 'args': <String, dynamic>{}}},
          {'id': 'lap', 'type': 'table_loop', 'name': 'Từng nhóm chứng từ', 'table': 'steps.lp.output.rows', 'as': 'ct', 'body': ['trong']},
          {'id': 'trong', 'type': 'table_loop', 'name': 'Ghi số từng chứng từ', 'table': 'steps.lp.output.rows', 'as': 'dong', 'body': ['gui']},
          {'id': 'gui', 'type': 'send', 'to': [r'$requester'], 'text': 'x'},
          {'id': 'end', 'type': 'end'},
        ],
        'edges': [['start', 'lp'], ['lp', 'lap'], ['lap', 'end']],
      };

  test('thông tin lấy từ khuôn kết quả công cụ (có mô tả), bảng lồng là nguồn bảng, cột theo khuôn', () {
    final doc = FlowDoc.fromJson(def());
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: const [], integ: integ);
    final vars = {for (final v in flowVars(doc)) v.path: v};
    expect(vars['steps.lp.output.hop_le']?.label, 'Lập payload hoá đơn › Hợp lệ');
    expect(vars['steps.lp.output.hop_le']?.type, 'bool');
    expect(vars['steps.lp.output.loi_text']?.label, 'Lập payload hoá đơn › Nội dung lỗi');
    expect(vars['steps.lp.output.tong.tien']?.label, 'Lập payload hoá đơn › tong › Tổng tiền');
    expect(vars.containsKey('steps.lp.output.rows'), isFalse, reason: 'bảng không phải thông tin để so');
    final inner = doc.allSteps.firstWhere((s) => s.id == 'gui');
    expect(tableSources(doc, doc.allItems.firstWhere((x) => x.id == 'lap')).map((s) => s.$1), contains('steps.lp.output.rows'));
    final at = {for (final v in flowVars(doc, at: inner)) v.path: v};
    expect(at['dong.so_ct']?.label, contains('Số chứng từ'));
    expect(at['ct.cho_xuat']?.type, 'bool');
    expect(at['item.cho_xuat']?.label, contains('Chờ xuất'));
    editorCtx = null;
  });

  testWidgets('khung Lặp bảng vẽ thành hộp, lồng nhau thì hộp trong hộp', (t) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(FlowEditorPage(app: app, api: api, doc: FlowDoc.fromJson(def()))));
    await t.pump(const Duration(milliseconds: 300));
    final outer = find.byKey(const ValueKey('loop-frame-lap'));
    final inner = find.byKey(const ValueKey('loop-frame-trong'));
    expect(outer, findsOneWidget);
    expect(inner, findsOneWidget);
    expect(find.descendant(of: outer, matching: inner), findsOneWidget);
    expect(find.descendant(of: outer, matching: find.text('Từng nhóm chứng từ')), findsWidgets);
  });

  testWidgets('Ctrl + cuộn chuột phóng to / thu nhỏ sơ đồ; cuộn thường thì không', (t) async {
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(FlowEditorPage(app: app, api: api, doc: FlowDoc.fromJson(def()))));
    await t.pump(const Duration(milliseconds: 300));
    double scale() => t.widget<ScaledBox>(find.byType(ScaledBox)).scale;
    expect(scale(), 1);
    final at = t.getCenter(find.byKey(const ValueKey('loop-frame-lap')));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(mouse.hover(at));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await t.pump();
    expect(scale(), 1, reason: 'không giữ Ctrl: cuộn như thường');
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await t.pump();
    expect(scale(), closeTo(1.1, 0.001));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await t.pump();
    expect(scale(), closeTo(1 / 1.1, 0.001));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(t.takeException(), isNull);
  });

  testWidgets('hộp điều kiện: dựng được điều kiện so hai thông tin, đổi vế phải sang thông tin khác', (t) async {
    const vars = [
      CondVar('steps.lp.output.hop_le', 'Lập payload hoá đơn › Hợp lệ', 'bool'),
      CondVar('steps.lp.output.loi_hash', 'Lập payload hoá đơn › loi_hash', 'text'),
      CondVar('process.props.loi_hash', 'Tiến trình › Thuộc tính › loi_hash', 'text'),
    ];
    String? result;
    await t.pumpWidget(wrap(Scaffold(
      body: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await showDialog<String>(
            context: c,
            builder: (_) => CondDialog(app: app, expr: 'steps.lp.output.hop_le == false and process.props.loi_hash != steps.lp.output.loi_hash', vars: vars),
          ),
          child: const Text('mở'),
        ),
      ),
    )));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.textContaining('không dựng lại được'), findsNothing);
    expect(find.text('Thông tin khác'), findsOneWidget);
    expect(find.text('Lập payload hoá đơn › loi_hash'), findsWidgets);
    await t.tap(find.text('Xong').last);
    await t.pumpAndSettle();
    expect(result, 'steps.lp.output.hop_le == false and process.props.loi_hash != steps.lp.output.loi_hash');
  });
}
