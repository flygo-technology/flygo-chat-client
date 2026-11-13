import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_calc.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_nodes.dart';
import 'package:flygo_chat/ui/flows/flow_starts.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Trình soạn, vòng 1: bước Gửi (Tin nhắn / Thẻ / Tiến trình), Chờ bấm nút ở thẻ đã gửi / tin nhắn, nhánh Lỗi và
/// thời hạn mỗi lần gọi, điều kiện viết bằng biểu thức, Tính toán expr / percent / add_workdays, theo dõi điều kiện.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.channels['c1'] = MmChannel({'id': 'c1', 'name': 'ke-toan', 'display_name': 'Kế toán', 'type': 'P'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child),
      );

  Map<String, dynamic> def() => {
        'id': 'HD0001',
        'name': 'Hoá đơn',
        'form': [
          {'key': 'so_hd', 'label': 'Số hoá đơn', 'type': 'text'},
          {'key': 'tong', 'label': 'Tổng tiền', 'type': 'money'},
          {'key': 'ngay', 'label': 'Ngày', 'type': 'date'},
        ],
        'nodes': [
          {'id': 'start', 'type': 'start'},
          {'id': 'tao', 'type': 'process_create', 'name': 'Tạo hoá đơn', 'key': '{{form.so_hd}}', 'title': 'HĐ', 'steps': [{'key': 'b1', 'title': 'Nhận'}]},
          {
            'id': 'the', 'type': 'send', 'name': 'Gửi thẻ HĐ', 'channels': ['c1'],
            'card': {'v': 1, 'title': 'HĐ {{form.so_hd}}', 'actions': [{'id': 'ky', 'label': 'Ký'}, {'id': 'bo', 'label': 'Bỏ qua'}]},
          },
          {'id': 'tin', 'type': 'send', 'name': 'Báo nhóm', 'channels': ['c1'], 'text': 'Có hoá đơn mới'},
          {'id': 'end', 'type': 'end'},
        ],
        'edges': [['start', 'tao'], ['tao', 'the'], ['the', 'tin'], ['tin', 'end']],
      };

  Future<Map> config(WidgetTester t, FlowDoc doc, FStep s, Future<void> Function() act) async {
    t.view.physicalSize = const Size(700, 4200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    addTearDown(() => editorCtx = null);
    Object? done;
    await t.pumpWidget(wrap(Scaffold(
      body: StepConfigSheet(app: app, node: s.node, form: FlowField.listOf(doc.meta['form']), roles: const {}, vars: flowVars(doc, at: s), onDone: (r) => done = r),
    )));
    await act();
    await t.tap(find.text('Xong'));
    return done as Map;
  }

  testWidgets('Gửi: chọn Tin nhắn / Thẻ / Tiến trình, mỗi cách đúng một nội dung', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('send') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      expect(find.text('Nội dung'), findsOneWidget);
      await t.tap(find.text('Thẻ'));
      await t.pump();
      expect(find.text('Nội dung thẻ'), findsOneWidget);
      await t.tap(find.text('Tiến trình').first);
      await t.pump();
      expect(find.text('Tự cập nhật thẻ khi tiến trình đổi'), findsOneWidget);
    });
    expect(r['type'], 'send');
    expect(r['process'], {'step': 'tao'}, reason: 'tự chọn tiến trình tạo ở bước trước');
    expect(r.containsKey('text'), isFalse);
    expect(r.containsKey('card'), isFalse);
    expect(nodeSummary(FStep(r.cast<String, dynamic>()), app), 'Thẻ tiến trình của "Tạo hoá đơn" · Tới: Người tạo tiến trình');
  });

  testWidgets('Chờ bấm nút ở thẻ đã gửi: chọn thẻ, nút lấy từ thẻ; mỗi nút một nhánh', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('wait_button') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      await t.tap(find.text('Thẻ đã gửi'));
      await t.pump();
      expect(find.text('Nút trên thẻ'), findsWidgets);
      // Hai nút mặc định đổi sang nút của thẻ.
      await t.tap(find.text('Thêm nút'));
      await t.pump();
    });
    final where = r['where'] as Map;
    expect(where['card'], {'step': 'the'}, reason: 'thẻ của bước Gửi (Thẻ) đứng trước');
    expect([for (final b in r['buttons'] as List) b['id']].last, 'ky', reason: 'nút thêm mới là nút đầu chưa dùng của thẻ');
    final w = FStep(r.cast<String, dynamic>());
    expect(w.ports.map((p) => p.key), contains('b:ky'));
    expect(nodeSummary(w, app), contains('Thẻ đã gửi'));
  });

  testWidgets('Chờ bấm nút ở tin nhắn: chọn tin của bước gửi vào nhóm, cũng tạo việc ở Việc của tôi', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('wait_button') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      await t.tap(find.text('Tin nhắn'));
      await t.pump();
      await t.tap(find.text('Cũng tạo tiến trình ở "Tiến trình của tôi"'));
      await t.pump();
    });
    expect(r['where'], {'message': {'step': 'tin'}, 'task': true});
  });

  testWidgets('nhánh Lỗi: chọn "Đi nhánh lỗi", đặt thời hạn mỗi lần gọi', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('mcp') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      await t.tap(find.text('Dừng luồng (mặc định)'));
      await t.pumpAndSettle();
      // Giữ các cách cũ.
      expect(find.text('Bỏ qua, đi tiếp'), findsWidgets);
      expect(find.text('Giao người làm tay'), findsWidgets);
      await t.tap(find.text('Đi nhánh lỗi').last);
      await t.pumpAndSettle();
      expect(find.textContaining('«Lỗi»'), findsOneWidget);
      await t.tap(find.text('30 giây'));
      await t.pump();
    });
    expect(r['on_error'], {'to': ''});
    expect(r['timeout'], '30s');
    doc.setNode(s, r.cast<String, dynamic>());
    expect(s.ports.map((p) => p.key), ['ok', 'error']);
    expect(portLabel(s, s.ports.last), 'Lỗi');
    expect(portLabel(s, s.ports.first), 'Thành công');
  });

  testWidgets('chờ sự kiện: chỉ "Hỏi lại lần sau" hoặc nhánh Lỗi, thời hạn là call_timeout', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('wait_event') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      await t.tap(find.text('Hỏi lại lần sau (mặc định)'));
      await t.pumpAndSettle();
      expect(find.text('Bỏ qua, đi tiếp'), findsNothing);
      await t.tap(find.text('Đi nhánh lỗi').last);
      await t.pumpAndSettle();
      await t.tap(find.text('1 phút'));
      await t.pump();
    });
    expect(r['on_error'], {'to': ''});
    expect(r['call_timeout'], '1m');
  });

  testWidgets('điều kiện: viết biểu thức có hàm, kiểm ngay, chèn hàm; dạng đơn giản chuyển lại được giao diện', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = FlowDoc.fromJson(def());
    String? r;
    await t.pumpWidget(wrap(Builder(
      builder: (c) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async => r = await showDialog<String>(context: c, builder: (_) => CondDialog(app: app, expr: 'days_between(form.ngay, today()) > 3', vars: flowVars(doc))),
            child: const Text('mở'),
          ),
        ),
      ),
    )));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    // Biểu thức có hàm: mở ở chế độ "Viết biểu thức", sửa được.
    final field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Điều kiện');
    expect(field, findsOneWidget);
    expect(find.text('days_between(«Ngày», today()) > 3'), findsOneWidget);
    await t.enterText(field, 'days_between(form.ngay) > 3');
    await t.pump();
    expect(find.text('Hàm days_between cần 2 tham số (đang có 1)'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Xong')).onPressed, isNull);
    await t.enterText(field, 'form.tong > 5000000 and ');
    await t.pump();
    await t.tap(find.text('Hàm'));
    await t.pumpAndSettle();
    await t.tap(find.text('empty(x)'));
    await t.pumpAndSettle();
    expect((t.widget<TextField>(field)).controller!.text, 'form.tong > 5000000 and empty(x)');
    await t.enterText(field, 'form.tong > 5000000');
    await t.pump();
    // Dạng đơn giản: về giao diện chọn được.
    await t.tap(find.text('Chọn bằng giao diện'));
    await t.pumpAndSettle();
    expect(find.text('Đi nhánh này khi: Tổng tiền lớn hơn 5.000.000 đ'), findsOneWidget);
    await t.tap(find.text('Viết biểu thức'));
    await t.pumpAndSettle();
    await t.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Điều kiện'), 'form.tong * 1.08 > 5000000');
    await t.pump();
    await t.tap(find.text('Xong'));
    await t.pumpAndSettle();
    expect(r, 'form.tong * 1.08 > 5000000');
  });

  test('Tính toán: phép expr / percent / add_workdays, kiểu và tóm tắt', () {
    expect(calcOpLabel('percent'), 'Tỉ lệ phần trăm (A chiếm bao nhiêu % của B)');
    expect(calcOpType('add_workdays'), 'date');
    final vs = calcVars('t', 'Tính', [
      {'name': 'han', 'op': 'add_workdays', 'args': {'a': {'path': 'form.ngay'}, 'n': {'value': 3}}},
      {'name': 'tong', 'op': 'expr', 'args': {'expr': 'form.tong * 1.08'}},
      {'name': 'den', 'op': 'expr', 'args': {'expr': 'add_days(form.ngay, 2)'}},
    ]);
    expect([for (final v in vs) v.type], ['date', 'number', 'date']);
    const vars = [CondVar('form.tong', 'Tổng tiền', 'money'), CondVar('form.ngay', 'Ngày', 'date')];
    expect(calcSummary({'name': 'tong', 'label': 'Tổng VAT', 'op': 'expr', 'args': {'expr': 'form.tong * 1.08'}}, vars, const []), 'Tổng VAT = «Tổng tiền» * 1.08');
    expect(calcSummary({'name': 'han', 'op': 'add_workdays', 'args': {'a': {'path': 'form.ngay'}, 'n': {'value': 3}}}, vars, const []), 'han = Ngày + 3 ngày làm việc');
    expect(calcSummary({'name': 'tl', 'op': 'percent', 'args': {'a': {'path': 'form.tong'}, 'b': {'value': 10}}}, vars, const []), 'tl = Tổng tiền chiếm bao nhiêu % của 10');
  });

  test('bảng Thêm bước: một mục Gửi, một mục Chờ bấm nút, có Đặt biến; ẩn các bước cũ', () {
    final all = {for (final l in [insertActionItems, insertProcessItems, insertCardItems, insertPeopleItems]) ...l.map((e) => e.$1)};
    expect(all, containsAll(['send', 'wait_button']));
    expect(all, isNot(contains('card_send')));
    expect(all, isNot(contains('process_send')));
    expect(supersededTypes, containsAll(['notify', 'card_send', 'process_send', 'buttons', 'card_wait']));
    expect(stepLook('set').$3, 'Đặt biến');
    expect(stepLook('send').$3, 'Gửi');
  });

  testWidgets('sơ đồ: bước có nhánh Lỗi vẽ hai nhánh Thành công / Lỗi; quy trình có bước gửi cũ có ghi chú nâng cấp', (t) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final d = def();
    final nodes = d['nodes'] as List;
    nodes.insert(4, {'id': 'goi', 'type': 'auto', 'action': 'mcp', 'name': 'Gọi ERP', 'params': {'server': 'erp', 'tool': 'lap'}, 'on_error': {'to': 'bao_loi'}});
    nodes.insert(5, {'id': 'bao_loi', 'type': 'notify', 'name': 'Báo lỗi ERP', 'to': [r'$requester'], 'text': 'Lỗi {{steps.goi.output.error.message}}'});
    d['edges'] = [['start', 'tao'], ['tao', 'the'], ['the', 'tin'], ['tin', 'goi'], ['goi', 'end'], ['bao_loi', 'end']];
    await t.pumpWidget(wrap(FlowEditorPage(app: app, api: api, doc: FlowDoc.fromJson(d))));
    await t.pump();
    expect(find.text('Thành công'), findsOneWidget);
    expect(find.text('Lỗi'), findsOneWidget);
    expect(find.text('Báo lỗi ERP'), findsOneWidget);
    expect(find.textContaining('«Gọi ERP › Lỗi › Nội dung»'), findsOneWidget);
    expect(find.text('Đã nâng cấp bước Gửi sang dạng mới, lưu để áp dụng'), findsOneWidget);
    // Chạm nhãn nhánh Lỗi: giải thích, chọn đi tiếp hay kết thúc.
    await t.tap(find.text('Lỗi'));
    await t.pumpAndSettle();
    expect(find.textContaining('Chạy khi bước lỗi'), findsOneWidget);
  });

  testWidgets('theo dõi điều kiện: "Lấy mốc khi bật", "Mỗi khoá chỉ một lần"', (t) async {
    t.view.physicalSize = const Size(700, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Object? done;
    await t.pumpWidget(wrap(Scaffold(
      body: StartConfigSheet(
        app: app,
        api: api,
        start: {'id': 'w', 'type': 'watch', 'server': '', 'tool': '', 'seconds': 300, 'cond': '', 'key': 'ma'},
        form: const [],
        roles: const {},
        integ: const {},
        flowId: 'HD0001',
        onDone: (r) => done = r,
      ),
    )));
    await t.tap(find.text('Lấy mốc khi bật'));
    await t.pump();
    await t.tap(find.text('Mỗi khoá chỉ một lần'));
    await t.pump();
    expect(find.textContaining('mỗi khoá chỉ tạo một tiến trình'), findsOneWidget);
    await t.tap(find.text('Xong'));
    final r = done as Map;
    expect(r['baseline_on_enable'], true);
    expect(r['mode'], 'once');
    expect(startSummary(r.cast<String, dynamic>(), app), contains('mỗi khoá một lần'));
  });
}
