import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_nodes.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Gộp hai bước duyệt: trình soạn chỉ còn một bước "Duyệt" (approval_request). Quy trình còn bước Duyệt kiểu cũ
/// (approval) mở ra thì tự đổi sang dạng mới (như `flows_engine::upgrade` của máy chủ), có đủ các nhánh.
void main() {
  Map<String, Map<String, dynamic>> nodesOf(Map<String, dynamic> def) => {for (final n in def['nodes'] as List) '${n['id']}': (n as Map).cast<String, dynamic>()};

  Map<String, dynamic> legacy() => jsonDecode('''{"id":"tt","name":"Thanh toán","on_reject":"bao_tc",
    "form":[{"key":"so_tien","label":"Số tiền","type":"money"}],
    "nodes":[{"id":"s","type":"start"},
      {"id":"tp","no":3,"type":"approval","name":"Trưởng phòng duyệt","approver":{"role":"truong_phong"},"mode":"all","due":"24h","remind":"4h",
        "escalate":{"after":"48h","to":{"role":"giam_doc"}},"editable":["so_tien"],"fields":[{"key":"kh","label":"Khách","type":"text"}],
        "delegation":{"role":"pho_phong"}},
      {"id":"gd","type":"approval","approver":{"role":"giam_doc"},"allow_return":false},
      {"id":"bao","type":"send","to":["\$requester"],"text":"ok"},
      {"id":"end","type":"end"}],
    "edges":[["s","tp"],["tp","gd"],["gd","bao"],["bao","end"]]}''') as Map<String, dynamic>;

  test('đổi bước Duyệt cũ sang dạng mới khi mở: giữ id, số, tên, ủy quyền; cạnh thành nhánh Phê duyệt', () {
    final doc = FlowDoc.fromJson(legacy());
    expect(doc.upgraded, ['tp', 'gd']);
    expect([for (final x in doc.steps) x.id], ['tp', 'gd', 'bao']);
    final tp = doc.steps[0] as FStep;
    expect(tp.type, 'approval_request');
    expect(tp.no, 3);
    expect(tp.node['name'], 'Trưởng phòng duyệt');
    expect(tp.node['title'], 'Trưởng phòng duyệt', reason: 'tên yêu cầu = tên bước');
    expect(tp.node['delegation'], {'role': 'pho_phong'});
    expect(tp.node['mode'], 'all');
    expect(tp.node['due'], '24h');
    expect(tp.node['remind'], '4h');
    expect(tp.node['editable'], ['so_tien']);
    expect((tp.node['fields'] as List).single['key'], 'kh');
    expect(tp.node['escalate'], [
      {'after': '48h', 'to': {'role': 'giam_doc'}, 'mode': 'add'},
    ]);
    expect(tp.node['return_steps'], ['start'], reason: 'cho trả lại (mặc định) → về đơn ban đầu');
    final gd = doc.steps[1] as FStep;
    expect(gd.node['title'], 'gd', reason: 'không có tên thì dùng id');
    expect(gd.node.containsKey('return_steps'), isFalse, reason: 'allow_return: false');

    // Sơ đồ: đủ nhánh, Từ chối trống (để nối thêm), Quá hạn chỉ có khi có hạn.
    expect([for (final p in tp.ports) p.key], ['always', 'approve', 'reject', 'escalate', 'timeout']);
    expect([for (final p in gd.ports) p.key], ['always', 'approve', 'reject']);
    final reject = tp.ports.firstWhere((p) => p.key == 'reject');
    expect(reject.steps, isEmpty);
    expect(reject.open, isTrue);

    // Lưu: một loại bước Duyệt, không còn cạnh đi ra; Từ chối / Quá hạn trống không ghi đích (bộ chạy: on_reject
    // hoặc kết thúc bị từ chối; quá hạn chỉ nhắc), giữ on_reject của quy trình.
    final def = doc.toJson();
    final n = nodesOf(def);
    expect(n.values.where((x) => x['type'] == 'approval'), isEmpty);
    expect(n['tp']!['approve_to'], 'gd');
    expect(n['gd']!['approve_to'], 'bao');
    for (final id in ['tp', 'gd']) {
      expect(n[id]!.containsKey('reject_to'), isFalse, reason: id);
      expect(n[id]!.containsKey('timeout_to'), isFalse, reason: id);
    }
    expect(def['on_reject'], 'bao_tc');
    final edges = [for (final e in def['edges'] as List) '${e[0]}>${e[1]}'];
    expect(edges.where((e) => e.startsWith('tp>') || e.startsWith('gd>')), isEmpty);
    expect(edges, contains('bao>end'));

    // Mở lại bản đã lưu: không còn gì để đổi, giữ nguyên.
    final back = FlowDoc.fromJson(jsonDecode(jsonEncode(def)) as Map<String, dynamic>);
    expect(back.upgraded, isEmpty);
    expect(back.toJson(), def);
  });

  test('nối bước vào nhánh Từ chối: Từ chối đi tới bước đó rồi kết thúc bị từ chối', () {
    final doc = FlowDoc.fromJson(legacy());
    final tp = doc.steps[0] as FStep;
    final bao = FlowDoc.make('notify');
    tp.ports.firstWhere((p) => p.key == 'reject').steps.add(bao);
    final def = doc.toJson();
    expect(nodesOf(def)['tp']!['reject_to'], bao.id);
    expect([for (final e in def['edges'] as List) '${e[0]}>${e[1]}'], contains('${bao.id}>end_rejected'));
  });

  test('bước Duyệt dạng mới đi tiếp bằng cạnh (do AI viết): cạnh thành nhánh Phê duyệt, không tính là nâng cấp', () {
    final doc = FlowDoc.fromJson({
      'id': 'x',
      'nodes': [
        {'id': 'start', 'type': 'start'},
        {'id': 'd', 'type': 'approval_request', 'title': 'Duyệt', 'approver': r'$requester'},
        {'id': 'b', 'type': 'send', 'to': [r'$requester'], 'text': 'x'},
        {'id': 'end', 'type': 'end'},
      ],
      'edges': [['start', 'd'], ['d', 'b'], ['b', 'end']],
    });
    expect(doc.upgraded, isEmpty);
    expect([for (final x in doc.steps) x.id], ['d', 'b']);
    expect(nodesOf(doc.toJson())['d']!['approve_to'], 'b');
  });

  test('bảng Thêm bước: một mục "Duyệt" (dạng mới), không còn bước Duyệt cũ / "Tạo phê duyệt"', () {
    final all = [for (final l in [insertActionItems, insertProcessItems, insertCardItems, insertPeopleItems]) ...l.map((e) => e.$1)];
    expect(all.where((t) => t == 'approval_request').length, 1);
    expect(all, isNot(contains('approval')));
    expect(supersededTypes, contains('approval'));
    expect(stepLook('approval_request').$3, 'Duyệt');
    expect([for (final t in all) stepLook(t).$3].where((l) => l == 'Duyệt' || l == 'Tạo phê duyệt'), ['Duyệt']);
    // Tạo bước Duyệt (kể cả theo loại cũ) ra bước dạng mới; tên yêu cầu trống thì lấy tên bước.
    for (final t in ['approval_request', 'approval']) {
      final s = FlowDoc.make(t) as FStep;
      expect(s.type, 'approval_request', reason: t);
      expect(s.name, 'Duyệt');
      expect(s.node['return_steps'], ['start']);
      final doc = FlowDoc({'id': 'x'}, [s]);
      expect(nodesOf(doc.toJson())[s.id]!['title'], 'Duyệt');
    }
    final blank = FlowDoc.blank().steps.single as FStep;
    expect(blank.type, 'approval_request');
  });

  testWidgets('mở quy trình có bước Duyệt cũ: ghi chú nâng cấp, chưa tính là sửa, vẫn lưu được', (t) async {
    final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
    final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Widget wrap(FlowDoc doc) => ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: FlowEditorPage(app: app, api: api, doc: doc)),
        );
    await t.pumpWidget(wrap(FlowDoc.fromJson(legacy())));
    await t.pump();
    expect(find.text('Đã nâng cấp bước Duyệt sang dạng mới, lưu để áp dụng'), findsOneWidget);
    expect(find.text('Từ chối'), findsWidgets);
    expect(find.text('Phê duyệt'), findsWidgets);
    // Không có thay đổi của người soạn: rời trang không hỏi bỏ thay đổi.
    final pop = t.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).first);
    expect(pop.canPop, isTrue);
    // Quy trình không có bước cũ: không có ghi chú.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(wrap(FlowDoc.fromJson(jsonDecode(jsonEncode(FlowDoc.fromJson(legacy()).toJson())) as Map<String, dynamic>)));
    await t.pump();
    expect(find.text('Đã nâng cấp bước Duyệt sang dạng mới, lưu để áp dụng'), findsNothing);
  });
}
