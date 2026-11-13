import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_expr.dart';
import 'package:flygo_chat/ui/flows/flow_editor_tables.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Bước bảng (Lọc / Thêm cột / Nhóm / Ghép) và khung Lặp bảng trên trình soạn: đọc / ghi JSON như máy chủ, tự đổi khối
/// lặp kiểu cũ, hàm biểu thức mới, thông tin dòng đang xét, ô cấu hình.
Map<String, dynamic> mcp(String id, String tool) => {
      'id': id,
      'type': 'auto',
      'action': 'mcp',
      'name': 'Đọc',
      'params': {'app': 'vn.example.linkq', 'tool': tool, 'args': <String, dynamic>{}},
      'output_schema': {'rows': 'json'},
    };

/// Như ví dụ trong docs/flows-guide.md: đọc → lọc → thêm cột → nhóm → lặp (tạo tiến trình, chỉ ghi khi đổi).
Map<String, dynamic> syncDef() => {
      'id': 'dong-bo',
      'name': 'Đồng bộ',
      'nodes': [
        {'id': 'start', 'type': 'start'},
        mcp('doc', 'linkq_get_sales_invoice'),
        {'id': 'loc', 'type': 'table_filter', 'table': 'steps.doc.output.rows', 'cond': "not starts_with(item.So_Ct, 'TAM')"},
        {
          'id': 'them',
          'type': 'table_add_field',
          'table': 'steps.loc.output.rows',
          'fields': [
            {'key': 'ma_nhom', 'expr': "prefix(item.So_Ct, '.') + '|' + item.Ngay_Ct"},
            {'key': 'hau_to', 'expr': "suffix(item.So_Ct, '.')"},
          ],
        },
        {'id': 'nhom', 'type': 'table_group', 'table': 'steps.them.output.rows', 'by': ['ma_nhom'], 'aggregates': [{'key': 'tong', 'op': 'sum', 'col': 'tien'}]},
        {'id': 'lap', 'type': 'table_loop', 'name': 'Từng nhóm', 'table': 'steps.nhom.output.groups', 'as': 'nhom', 'key': 'nhom.ma_nhom', 'body': ['tao', 'doi', 'luu']},
        {'id': 'tao', 'type': 'process_create', 'key': '{{nhom.ma_nhom}}', 'title': 'Chứng từ {{nhom.ma_nhom}}', 'props': {'chung_tu': ''}},
        {
          'id': 'doi',
          'type': 'condition',
          'rules': [
            {'if': 'hash(process.props.chung_tu) != hash(nhom.rows)', 'to': 'luu'},
          ],
          'else': '',
        },
        {'id': 'luu', 'type': 'process_props', 'process': {'step': 'tao'}, 'set': {'chung_tu': '{{nhom.rows}}'}},
        {'id': 'end', 'type': 'end'},
      ],
      'edges': [
        ['start', 'doc'],
        ['doc', 'loc'],
        ['loc', 'them'],
        ['them', 'nhom'],
        ['nhom', 'lap'],
        ['tao', 'doi'],
        ['lap', 'end'],
      ],
    };

void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child),
      );

  Map<String, Map<String, dynamic>> byId(Map<String, dynamic> j) => {for (final n in (j['nodes'] as List)) '${(n as Map)['id']}': n.cast<String, dynamic>()};
  Set<String> edges(Map<String, dynamic> j) => {for (final e in (j['edges'] as List)) '${e[0]}>${e[1]}'};

  test('khung Lặp bảng: mở rồi lưu giữ nguyên bước con, bước đầu, nhánh rỗng kết thúc lượt', () {
    final doc = FlowDoc.fromJson(syncDef());
    expect(doc.upgraded, isEmpty);
    final loop = doc.steps.whereType<FLoop>().single;
    expect((loop.items, loop.alias, loop.key, loop.legacy, loop.stopOnError), ('steps.nhom.output.groups', 'nhom', 'nhom.ma_nhom', false, false));
    expect([for (final x in loop.body) x.id], ['tao', 'doi']);
    final j = doc.toJson();
    final n = byId(j);
    expect(n['lap']!['type'], 'table_loop');
    expect((n['lap']!['body'] as List).toSet(), {'tao', 'doi', 'luu'});
    expect(n['lap']!['entry'], 'tao');
    expect(n['lap']!['as'], 'nhom');
    expect(n['doi']!['else'], '');
    expect(n['doi']!['rules'][0]['to'], 'luu');
    final e = edges(j);
    expect(e.contains('tao>doi'), isTrue);
    expect(e.any((x) => x.startsWith('luu>') || x.startsWith('doi>') || x.endsWith('>tao')), isFalse, reason: '$e');
    expect(e.contains('lap>end'), isTrue);
    // Mở lại bản vừa lưu: như cũ.
    expect(jsonEncode(FlowDoc.fromJson(j).toJson()), jsonEncode(j));
  });

  test('khung lồng nhau: bước con của khung trong không thuộc khung ngoài', () {
    final doc = FlowDoc.fromJson(syncDef());
    final outer = doc.steps.whereType<FLoop>().single;
    final inner = FlowDoc.make('table_loop') as FLoop
      ..items = 'nhom.rows'
      ..alias = 'ct';
    final ghi = FlowDoc.make('send') as FStep;
    inner.body.add(ghi);
    outer.body.add(inner);
    final n = byId(doc.toJson());
    expect((n[outer.id]!['body'] as List).toSet(), {'tao', 'doi', 'luu', inner.id});
    expect(n[inner.id]!['body'], [ghi.id]);
    expect(n[inner.id]!['entry'], ghi.id);
    // Thông tin trong khung trong: tên dòng của cả hai khung, item / loop của khung trong.
    final vars = {for (final v in flowVars(doc, at: ghi)) v.path};
    expect(vars, containsAll(['nhom.ma_nhom', 'nhom.count', 'nhom.tong', 'ct', 'item', 'loop.index']));
    expect(tableSources(doc, inner).map((s) => s.$1), contains('nhom.rows'));
  });

  test('khối lặp kiểu cũ: đổi sang khung Lặp bảng (dừng khi lỗi); có bước chờ người thì giữ nguyên', () {
    final old = {
      'id': 'kiem',
      'name': 'Kiểm',
      'form': [
        {'key': 'hang', 'label': 'Hàng', 'type': 'table', 'columns': [{'key': 'ma', 'label': 'Mã', 'type': 'text'}, {'key': 'loi', 'label': 'Lỗi', 'type': 'number'}]},
      ],
      'nodes': [
        {'id': 'start', 'type': 'start'},
        {'id': 'lap', 'type': 'foreach', 'items': 'form.hang', 'end': 'het'},
        {'id': 'co', 'type': 'condition', 'rules': [{'if': 'item.loi > 0', 'to': 'bao'}], 'else': 'het'},
        {'id': 'bao', 'type': 'send', 'to': [r'$requester'], 'text': '{{item.ma}}'},
        {'id': 'het', 'type': 'foreach_end'},
        {'id': 'end', 'type': 'end'},
      ],
      'edges': [['start', 'lap'], ['lap', 'co'], ['bao', 'het'], ['het', 'end']],
    };
    final doc = FlowDoc.fromJson(old);
    expect(doc.upgraded, ['lap']);
    expect(doc.upgradedKinds, ['table_loop']);
    expect(upgradeNote(doc), contains('Lặp bảng'));
    final n = byId(doc.toJson());
    expect(n['lap']!['type'], 'table_loop');
    expect(n['lap']!['table'], 'form.hang');
    expect(n['lap']!['stop_on_error'], true);
    expect(n.containsKey('het'), isFalse);
    expect(n['co']!['else'], '');
    // Dòng đang xét có tên cột của bảng biểu mẫu.
    final bao = doc.allSteps.firstWhere((s) => s.id == 'bao');
    expect(flowVars(doc, at: bao).where((v) => v.path == 'item.loi').single.type, 'number');

    final keep = jsonDecode(jsonEncode(old)) as Map<String, dynamic>;
    (keep['nodes'] as List)[3] = {'id': 'bao', 'type': 'approval_request', 'title': 'Duyệt {{item.ma}}', 'approver': r'$requester'};
    final d2 = FlowDoc.fromJson(keep);
    expect(d2.upgradedKinds, isNot(contains('table_loop')));
    final l2 = d2.steps.whereType<FLoop>().single;
    expect(l2.legacy, isTrue);
    expect(byId(d2.toJson())['lap']!['type'], 'foreach');
  });

  test('bước không dùng được trong khung lặp được đánh dấu', () {
    final doc = FlowDoc.fromJson(syncDef());
    final loop = doc.steps.whereType<FLoop>().single;
    expect(FlowDoc.loopBlockedItems(loop), isEmpty);
    loop.body.add(FlowDoc.make('approval_request'));
    loop.body.add(FlowDoc.make('parallel'));
    expect(FlowDoc.loopBlockedItems(loop).length, 2);
  });

  test('hàm prefix / suffix / before / after / starts_with / hash như máy chủ', () {
    Object? ev(String src, [Map<String, dynamic> ctx = const {}]) => evalExpr(parseExpr(src), ctx);
    expect(ev("prefix('ABC.2', '.')"), 'ABC');
    expect(ev("suffix('ABC.2', '.')"), '2');
    expect(ev("before('a.b.c', '.')"), 'a');
    expect(ev("after('a.b.c', '.')"), 'b.c');
    expect(ev("prefix('ABC', '.')"), 'ABC');
    expect(ev("suffix('ABC', '.')"), '');
    expect(ev("starts_with('LQF:x', 'LQF:')"), true);
    expect(ev("hash('abc')"), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    final ctx = {
      'item': {
        'a': {'x': 1, 'y': [1, 2]},
        'b': {'y': [1, 2], 'x': 1},
      },
    };
    expect(ev('hash(item.a)', ctx), ev('hash(item.b)', ctx));
    expect(checkExpr("hash(item)").error, isNull);
    expect(exprType(parseExpr("starts_with(a, 'x')")), 'bool');
    expect(exprType(parseExpr("prefix(a, '.')")), 'text');
  });

  test('cột biết trước theo chuỗi bước bảng; tóm tắt trên sơ đồ', () {
    final doc = FlowDoc.fromJson(syncDef());
    expect(tableColumns(doc, 'steps.them.output.rows'), isNull, reason: 'kết quả công cụ không biết cột');
    expect(tableColumns(doc, 'steps.nhom.output.groups'), ['ma_nhom', 'count', 'rows', 'tong']);
    final loc = doc.allSteps.firstWhere((s) => s.id == 'loc');
    expect(tableSummary(loc, (p) => p == 'steps.doc.output.rows' ? 'Đọc › rows' : p), contains('«Đọc › rows»'));
    final nhom = doc.allSteps.firstWhere((s) => s.id == 'nhom');
    expect(tableSummary(nhom, (p) => p), contains('nhóm theo ma_nhom'));
    expect({for (final v in flowVars(doc)) v.path}, containsAll(['steps.loc.output.count', 'steps.nhom.output.count', 'steps.lap.output.ok']));
    final them = doc.allSteps.firstWhere((s) => s.id == 'them');
    expect({for (final v in flowVars(doc, at: them)) v.path}, contains('item'));
  });

  test('Đọc hết trang: mặc định, đoán cách lật trang, tóm tắt, kết quả là bảng, nhánh lỗi', () {
    expect(guessPaging(['from_date', 'cursor']), {'mode': 'cursor', 'cursor_arg': 'cursor', 'next': 'next_cursor', 'more': 'has_more'});
    expect(guessPaging(['series', 'start', 'count']), {'mode': 'offset', 'start_arg': 'start', 'size_arg': 'count', 'size': 100});
    final doc = FlowDoc.fromJson(syncDef());
    final s = FlowDoc.make('mcp_pages') as FStep;
    expect(s.node['paging']['mode'], 'cursor');
    s.node['params'] = {'app': 'vn.example.linkq', 'tool': 'linkq_get_sales_invoice', 'args': <String, dynamic>{}};
    s.node['on_error'] = {'to': ''};
    s.syncPorts();
    expect(s.ports.map((p) => p.key), containsAll(['ok', 'error']));
    doc.steps.insert(1, s);
    expect(tableSummary(s, (p) => p), contains('linkq_get_sales_invoice'));
    expect({for (final v in flowVars(doc)) v.path}, containsAll(['steps.${s.id}.output.count', 'steps.${s.id}.output.pages', 'steps.${s.id}.output.truncated']));
    final loc = doc.allSteps.firstWhere((x) => x.id == 'loc');
    expect(tableSources(doc, loc).map((x) => x.$1), contains('steps.${s.id}.output.rows'));
    final j = doc.toJson();
    final n = byId(j)[s.id]!;
    expect(n['type'], 'mcp_pages');
    expect(n.containsKey('output_schema'), isFalse);
    expect(FlowDoc.fromJson(j).allSteps.any((x) => x.id == s.id && x.type == 'mcp_pages'), isTrue);
  });

  testWidgets('ô cấu hình của các bước bảng dựng được', (t) async {
    t.view.physicalSize = const Size(900, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = FlowDoc.fromJson(syncDef());
    for (final type in tableNodeTypes) {
      final s = FlowDoc.make(type) as FStep;
      doc.steps.insert(5, s);
      editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
      await t.pumpWidget(wrap(Scaffold(
        body: StepConfigSheet(key: ValueKey(type), app: app, node: s.node, form: FlowField.listOf(doc.meta['form']), roles: const {}, vars: flowVars(doc, at: s), onDone: (_) {}),
      )));
      await t.pump();
      expect(t.takeException(), isNull, reason: type);
      expect(find.text(tableLook(type).$3), findsWidgets, reason: type);
      doc.remove(s.id);
    }
  });

  testWidgets('hộp cài đặt Lặp bảng: chọn nhóm, đặt tên dòng, tên trùng khung ngoài bị chặn', (t) async {
    t.view.physicalSize = const Size(900, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = FlowDoc.fromJson(syncDef());
    final outer = doc.steps.whereType<FLoop>().single;
    final inner = FlowDoc.make('table_loop') as FLoop;
    outer.body.add(inner);
    bool? saved;
    await t.pumpWidget(wrap(Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () async => saved = await editLoopSettings(c, doc, inner, flowVars(doc, at: inner)), child: const Text('mở'))))));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.text('Lặp bảng'), findsWidgets);
    await t.enterText(find.widgetWithText(TextFormField, 'Tên dòng (as)'), 'nhom');
    await t.pump();
    expect(find.textContaining('không trùng khung ngoài'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Tên dòng (as)'), 'ct');
    await t.pump();
    await t.tap(find.byType(DropdownButtonFormField<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Các dòng của nhóm').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Lưu'));
    await t.pumpAndSettle();
    expect(saved, isTrue);
    expect((inner.items, inner.alias), ('nhom.rows', 'ct'));
  });
}
