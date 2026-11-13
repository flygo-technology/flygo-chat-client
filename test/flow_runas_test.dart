import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_runas.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Chế độ chạy của quy trình (`run_as`) và "Cho phép chạy không cần duyệt" (`allow_without_approval`) trên trình soạn.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['qt1'] = MmUser({'id': 'qt1', 'username': 'sep', 'first_name': 'Sếp'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: child))),
      );
  String name(String id) => app.users[id]?.firstName ?? id;

  final integ = {
    'mcp': [
      {
        'name': 'vn.example.minvoice',
        'app': 'vn.example.minvoice',
        'label': 'M-Invoice',
        'tools': [
          {'name': 'list_invoices', 'read_only': true, 'allowed': true},
          {'name': 'create_draft_invoice', 'read_only': false, 'allowed': true},
        ],
      },
    ],
  };
  Map<String, dynamic> mcp(String tool) => {
        'id': 'goi',
        'type': 'auto',
        'action': 'mcp',
        'name': 'Gọi',
        'params': {'app': 'vn.example.minvoice', 'tool': tool, 'args': <String, dynamic>{}},
      };

  testWidgets('chế độ chạy: chọn chủ thể riêng hiện flow:<id>, chưa lưu; đã bật thì hiện người bật; về mặc định thì bỏ run_as', (t) async {
    final meta = <String, dynamic>{'id': 'F1HD01', 'name': 'Hoá đơn'};
    var changed = 0;
    await t.pumpWidget(wrap(StatefulBuilder(builder: (c, set) => RunAsField(meta: meta, userName: name, onChanged: () => set(() => changed++)))));
    expect(find.text('Theo người tạo tiến trình'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('run-as-custom')));
    await t.pump();
    expect(meta['run_as'], {'mode': 'custom'});
    expect(changed, 1);
    expect(find.text('flow:F1HD01'), findsOneWidget);
    expect(find.textContaining('Chưa lưu'), findsOneWidget);
    meta['run_as'] = {'mode': 'creator', 'user': 'qt1', 'enabled_by': 'qt1'};
    await t.pumpWidget(wrap(RunAsField(key: const ValueKey('b'), meta: meta, userName: name, onChanged: () {})));
    expect(find.textContaining('Đã bật bởi Sếp'), findsOneWidget);
    expect(find.textContaining('chạy bằng quyền của Sếp'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('run-as-requester')));
    await t.pump();
    expect(meta.containsKey('run_as'), isFalse);
  });

  testWidgets('cho phép chạy không cần duyệt: bật thì bắt buộc lý do, giữ người đã đặt khi lý do không đổi', (t) async {
    final n = mcp('create_draft_invoice');
    await t.pumpWidget(wrap(WaiverField(n: n, userName: name, onChanged: () {})));
    await t.tap(find.byKey(const ValueKey('waiver')));
    await t.pump();
    expect(n['allow_without_approval'], {'reason': ''});
    expect(find.text('Ghi lý do để lưu được'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('waiver-reason')), 'Tạo nháp, kế toán ký tay');
    await t.pump();
    expect(n['allow_without_approval'], {'reason': 'Tạo nháp, kế toán ký tay'});
    expect(find.text('Ghi lý do để lưu được'), findsNothing);
    final saved = mcp('create_draft_invoice')..['allow_without_approval'] = {'reason': 'Nháp', 'by': 'qt1'};
    await t.pumpWidget(wrap(WaiverField(key: const ValueKey('s'), n: saved, userName: name, onChanged: () {})));
    expect(find.textContaining('Đã cho phép bởi Sếp'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('waiver')));
    await t.pump();
    expect(saved.containsKey('allow_without_approval'), isFalse);
  });

  test('bước ghi dữ liệu: công cụ ghi / không rõ thì có, công cụ chỉ đọc thì không', () {
    expect(mayWrite(mcp('create_draft_invoice'), integ, mcpKeyOf), isTrue);
    expect(mayWrite(mcp('list_invoices'), integ, mcpKeyOf), isFalse);
    expect(mayWrite(mcp('khong_co'), integ, mcpKeyOf), isTrue, reason: 'không rõ tính là ghi');
    expect(mayWrite({'type': 'wait_event', 'app': 'vn.example.minvoice', 'tool': 'create_draft_invoice'}, integ, mcpKeyOf), isTrue);
    expect(mayWrite({'type': 'wait_event', 'match': {'key': 'x'}}, integ, mcpKeyOf), isFalse);
    expect(mayWrite({'type': 'send', 'text': 'x'}, integ, mcpKeyOf), isFalse);
  });

  testWidgets('ô cho phép chỉ hiện ở bước đã đặt từ trước (máy chủ không còn chặn lưu)', (t) async {
    t.view.physicalSize = const Size(900, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    for (final (tool, has) in [('create_draft_invoice', false), ('list_invoices', false), ('create_draft_invoice', true)]) {
      final n = mcp(tool);
      if (has) n['allow_without_approval'] = {'reason': 'Nháp', 'by': 'qt1'};
      final doc = FlowDoc.fromJson({'id': 'F1', 'name': 'F1', 'nodes': [{'id': 'start', 'type': 'start'}, n, {'id': 'end', 'type': 'end'}], 'edges': [['start', 'goi'], ['goi', 'end']]});
      editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: const []);
      await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: StepConfigSheet(key: ValueKey('$tool-$has'), app: app, node: n, form: const [], roles: const {}, integ: integ, onDone: (_) {}))),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Cho phép chạy không cần duyệt'), has ? findsOneWidget : findsNothing, reason: tool);
    }
  });

  test('mở rồi lưu giữ chế độ chạy và cho phép của bước', () {
    final n = mcp('create_draft_invoice')..['allow_without_approval'] = {'reason': 'Nháp', 'by': 'qt1'};
    final def = {
      'id': 'F1',
      'name': 'F1',
      'run_as': {'mode': 'custom', 'enabled_by': 'qt1'},
      'nodes': [{'id': 'start', 'type': 'start'}, n, {'id': 'end', 'type': 'end'}],
      'edges': [['start', 'goi'], ['goi', 'end']],
    };
    final j = FlowDoc.fromJson(def).toJson();
    expect(j['run_as'], {'mode': 'custom', 'enabled_by': 'qt1'});
    final goi = (j['nodes'] as List).firstWhere((x) => x['id'] == 'goi') as Map;
    expect(goi['allow_without_approval'], {'reason': 'Nháp', 'by': 'qt1'});
  });

  testWidgets('lỗi 403 chỉ quản trị là người thật: nhận ra và giải thích', (t) async {
    const msg = 'tài khoản bot không được bật chế độ chạy "custom": chỉ quản trị là người thật được đặt';
    expect(isAdminOnlyError(msg), isTrue);
    expect(isAdminOnlyError('lỗi khác'), isFalse);
    await t.pumpWidget(wrap(Builder(builder: (c) => TextButton(onPressed: () => showAdminOnlyError(c, msg), child: const Text('mở')))));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.text('Cần quản trị là người thật'), findsOneWidget);
    expect(find.textContaining('bằng tài khoản quản trị của mình'), findsOneWidget);
  });

  testWidgets('chạm lỗi của một bước trong kết quả kiểm: mở bước đó', (t) async {
    String? opened;
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: CheckResultView(
            issues: const [
              {'node': 'goi', 'code': 'write_without_approval', 'msg': 'gọi công cụ ghi mà chưa có bước duyệt'},
              {'node': null, 'code': 'flow_name', 'msg': 'chưa có tên'},
            ],
            traces: const [],
            nodeName: (id) => id,
            who: (id) => id,
            onOpen: (id) => opened = id,
          ),
        ),
      ),
    ));
    await t.tap(find.text('gọi công cụ ghi mà chưa có bước duyệt'));
    expect(opened, 'goi');
    await t.tap(find.text('chưa có tên'));
    expect(opened, 'goi');
  });
}
