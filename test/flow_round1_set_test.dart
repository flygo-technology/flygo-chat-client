import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_expr.dart';
import 'package:flygo_chat/ui/flows/flow_editor_set.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Bước "Đặt biến" (`set`): `vars.<tên>` dùng ở bước sau (chọn thông tin, tên dễ đọc), sửa trường biểu mẫu, số chứng
/// từ tự tăng có xem trước.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child),
      );

  Map<String, dynamic> def() => {
        'id': 'PC0001',
        'name': 'Phiếu chi',
        'form': [
          {'key': 'so_tien', 'label': 'Số tiền', 'type': 'money'},
          {'key': 'ghi_chu', 'label': 'Ghi chú', 'type': 'text'},
          {'key': 'hang', 'label': 'Hàng', 'type': 'table', 'columns': [{'key': 'sl', 'label': 'SL', 'type': 'number'}]},
        ],
        'nodes': [
          {'id': 'start', 'type': 'start'},
          {
            'id': 'dat', 'type': 'set', 'name': 'Lấy số phiếu',
            'assign': [
              {'to': 'vars.so_phieu', 'number': {'counter': 'phieu-chi', 'format': 'PC-{yyyy}-{0000}'}},
              {'to': 'vars.vat', 'expr': 'round(form.so_tien * 0.08)'},
              {'to': 'form.ghi_chu', 'expr': "'Phiếu ' + vars.so_phieu"},
            ],
          },
          {'id': 'dk', 'type': 'condition', 'rules': [{'if': 'vars.vat > 1000000', 'to': 'bao'}], 'else': 'end'},
          {'id': 'bao', 'type': 'send', 'to': [r'$requester'], 'text': 'Số {{vars.so_phieu}}, VAT {{round(vars.vat / 1000)}} nghìn'},
          {'id': 'end', 'type': 'end'},
        ],
        'edges': [['start', 'dat'], ['dat', 'dk'], ['bao', 'end']],
      };

  test('biến vars.* dùng được ở bước sau, tên dễ đọc, tóm tắt trên sơ đồ', () {
    final doc = FlowDoc.fromJson(def());
    final vars = {for (final v in flowVars(doc)) v.path: v};
    expect(vars['vars.so_phieu']?.label, 'Biến › so_phieu');
    expect(vars['vars.so_phieu']?.type, 'text');
    expect(vars['vars.vat']?.type, 'number');
    expect(vars.containsKey('vars.ghi_chu'), isFalse, reason: 'sửa trường biểu mẫu không tạo biến mới');
    expect(flowVarLabel('vars.vat', doc), 'Biến › vat');
    final dat = doc.allSteps.firstWhere((s) => s.id == 'dat');
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    expect(stepSummary(dat, app, labelledVars(doc, flowVars(doc), const {})),
        "so_phieu = số PC-{yyyy}-{0000} · vat = round(«Số tiền» * 0.08) · Ghi chú = 'Phiếu ' + «Biến › so_phieu»");
    // Điều kiện theo biến; mẫu chữ có biểu thức trong ngoặc.
    final c = doc.steps[1] as FCondition;
    expect(condLabel(c.branches.first.cond!, flowVars(doc)), 'Biến › vat lớn hơn 1.000.000');
    final bao = doc.allSteps.firstWhere((s) => s.id == 'bao');
    expect(stepSummary(bao, app, labelledVars(doc, flowVars(doc), const {})), '“Số «Biến › so_phieu», VAT «round(«Biến › vat» / 1000)» nghìn” · Tới: Người tạo tiến trình');
    // Đổi qua lại giữ nguyên.
    expect(FlowDoc.fromJson(doc.toJson()).toJson(), doc.toJson());
    editorCtx = null;
  });

  test('trường sửa được bằng Đặt biến: không phải bảng / tự tính / tệp', () {
    final f = settableFields(FlowField.listOf(def()['form']));
    expect([for (final x in f) x.key], ['so_tien', 'ghi_chu']);
    expect(assignName('vars.so_phieu'), 'so_phieu');
    expect(assignType({'expr': 'add_days(today(), 3)'}), 'date');
    expect(assignType({'number': {'format': 'PC-{0000}'}}), 'text');
  });

  testWidgets('ô cấu hình Đặt biến: thêm phép gán, đổi sang số chứng từ, xem trước, chèn dạng', (t) async {
    exprNow = () => DateTime.utc(2026, 11, 8, 3);
    addTearDown(() => exprNow = DateTime.now);
    t.view.physicalSize = const Size(700, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('set') as FStep;
    doc.steps.add(s);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    addTearDown(() => editorCtx = null);
    Object? done;
    await t.pumpWidget(wrap(Scaffold(
      body: StepConfigSheet(app: app, node: s.node, form: FlowField.listOf(doc.meta['form']), roles: const {}, vars: flowVars(doc, at: s), onDone: (r) => done = r),
    )));
    expect(find.text('Đặt biến'), findsWidgets);
    // Dòng đầu: biểu thức; gõ sai thì báo lỗi tiếng Việt ngay.
    final value = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Giá trị');
    await t.enterText(value, 'round(form.so_tien');
    await t.pump();
    expect(find.text('Thiếu dấu ")" hoặc "," trong hàm round'), findsOneWidget);
    await t.enterText(value, 'round(form.so_tien * 0.1)');
    await t.pump();
    expect(find.text('round(«Số tiền» * 0.1)'), findsOneWidget);
    // Thêm dòng, đổi sang số chứng từ tự tăng.
    await t.tap(find.text('Thêm phép gán'));
    await t.pump();
    await t.tap(find.text('Số chứng từ tự tăng').last);
    await t.pump();
    expect(find.text('Xem trước: PC-2026-0001, PC-2026-0002, …'), findsOneWidget);
    final fmt = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Dạng số');
    await t.enterText(fmt, 'HD-');
    await t.pump();
    await t.tap(find.text('{mm} · Tháng'));
    await t.pump();
    await t.tap(find.text('{0000} · Số thứ tự 4 chữ số'));
    await t.pump();
    expect(find.text('Xem trước: HD-110001, HD-110002, …'), findsOneWidget);
    await t.tap(find.text('Xong'));
    final r = done as Map;
    final rows = r['assign'] as List;
    expect(rows[0], {'to': 'vars.bien_1', 'expr': 'round(form.so_tien * 0.1)'});
    expect(rows[1]['to'], 'vars.bien_2');
    expect(rows[1]['number'], {'format': 'HD-{mm}{0000}'});
  });
}
