import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';

/// Đổi JSON flow <-> sơ đồ dọc: giữ nguyên đường đi (cạnh giữa các bước thật), sửa / chuyển chỗ đúng.
void main() {
  // Đồ thị rút gọn: bước thật -> các bước thật đi tới ngay sau (bỏ start / end / join; điều kiện giữ rule -> đích).
  Map<String, Set<String>> graph(Map<String, dynamic> def) {
    final nodes = {for (final n in def['nodes'] as List) '${n['id']}': n as Map};
    final edges = [for (final e in def['edges'] as List) ('${e[0]}', '${e[1]}')];
    Set<String> succ(String id) {
      final n = nodes[id]!;
      // Bước Duyệt dạng mới: đi tiếp bằng nhánh Phê duyệt (bước Duyệt cũ bằng cạnh; mở trong sơ đồ thì cạnh thành nhánh).
      final raw = n['type'] == 'condition'
          ? [for (final r in n['rules'] as List) '${r['to']}', '${n['else']}']
          : [for (final (a, b) in edges) if (a == id) b, if (n['type'] == 'approval_request' && n['approve_to'] != null) '${n['approve_to']}'];
      final out = <String>{};
      for (final s in raw) {
        final t = nodes[s]!['type'];
        if (t == 'join' || t == 'foreach_end') {
          out.addAll(succ(s));
        } else if (t == 'end') {
          out.add('END');
        } else {
          out.add(s);
        }
      }
      return out;
    }

    return {for (final id in nodes.keys) if (!{'start', 'end', 'join', 'foreach_end'}.contains(nodes[id]!['type'])) id: succ(id)};
  }

  const pay = '''{"id":"de-xuat","name":"Đề xuất thanh toán","form":[{"key":"so_tien","type":"money"}],
    "nodes":[{"id":"start","type":"start"},{"id":"ai_kiem","type":"ai"},{"id":"tp","type":"approval"},
      {"id":"chk","type":"condition","rules":[{"if":"form.so_tien > 20000000","to":"gd"}],"else":"ktt"},
      {"id":"gd","type":"approval"},{"id":"ktt","type":"approval"},{"id":"ai_chi","type":"ai"},{"id":"bao","type":"notify"},{"id":"end","type":"end"}],
    "edges":[["start","ai_kiem"],["ai_kiem","tp"],["tp","chk"],["gd","ktt"],["ktt","ai_chi"],["ai_chi","bao"],["bao","end"]]}''';
  const adv = '''{"id":"tam-ung","name":"Tạm ứng","nodes":[{"id":"start","type":"start"},{"id":"tp","type":"approval"},
      {"id":"chk","type":"condition","rules":[{"if":"form.so_tien > 10000000","to":"ss"}],"else":"ktt"},
      {"id":"ss","type":"parallel"},{"id":"ktt_lon","type":"approval"},{"id":"gd","type":"approval"},{"id":"gop","type":"join"},
      {"id":"ktt","type":"approval"},{"id":"chi","type":"form_task"},{"id":"cho","type":"wait"},{"id":"nhac","type":"notify"},{"id":"end","type":"end"}],
    "edges":[["start","tp"],["tp","chk"],["ss","ktt_lon"],["ss","gd"],["ktt_lon","gop"],["gd","gop"],["gop","chi"],["ktt","chi"],["chi","cho"],["cho","nhac"],["nhac","end"]]}''';

  test('đề xuất thanh toán: đổi qua lại giữ nguyên đường đi', () {
    final def = jsonDecode(pay) as Map<String, dynamic>;
    final doc = FlowDoc.fromJson(def);
    expect([for (final x in doc.steps) x.id], ['ai_kiem', 'tp', 'chk', 'ktt', 'ai_chi', 'bao']);
    final c = doc.steps[2] as FCondition;
    expect(c.branches.map((b) => b.cond), ['form.so_tien > 20000000', null]);
    expect(c.branches[0].steps.map((x) => x.id), ['gd']);
    expect(c.branches[1].steps, isEmpty);
    expect(graph(doc.toJson()), graph(def));
    expect(doc.toJson()['form'], def['form'], reason: 'giữ biểu mẫu và thông tin khác');
  });

  test('tạm ứng: điều kiện lồng song song, gặp lại ở bước chung', () {
    final def = jsonDecode(adv) as Map<String, dynamic>;
    final doc = FlowDoc.fromJson(def);
    expect([for (final x in doc.steps) x.id], ['tp', 'chk', 'chi', 'cho', 'nhac']);
    final c = doc.steps[1] as FCondition;
    final p = c.branches[0].steps.single as FParallel;
    expect(p.branches.map((b) => b.single.id).toSet(), {'ktt_lon', 'gd'});
    expect(c.branches[1].steps.single.id, 'ktt');
    expect(graph(doc.toJson()), graph(def));
  });

  test('sửa: thêm bước vào nhánh, chuyển chỗ, xoá', () {
    final doc = FlowDoc.fromJson(jsonDecode(pay) as Map<String, dynamic>);
    final c = doc.steps[2] as FCondition;
    final hr = FlowDoc.make('approval');
    c.branches[1].steps.add(hr); // nhánh "còn lại" thêm một bước duyệt
    var g = graph(doc.toJson());
    expect(g['chk'], {'gd', hr.id});
    expect(g[hr.id], {'ktt'});
    // Chuyển "bao" lên đầu
    doc.move('bao', doc.steps, 0);
    expect(doc.steps.first.id, 'bao');
    g = graph(doc.toJson());
    expect(g['bao'], {'ai_kiem'});
    expect(g['ai_chi'], {'END'});
    // Không thả khối điều kiện vào trong chính nó
    doc.move('chk', c.branches[0].steps, 0);
    expect(doc.steps.any((x) => x.id == 'chk'), isTrue);
    doc.remove('gd');
    expect(graph(doc.toJson())['chk'], {'ktt', hr.id});
  });

  test('flow mẫu (bản chép từ flygo-flows/examples) đổi qua lại vẫn giữ đường đi', () {
    for (final f in ['de-xuat-thanh-toan.json', 'tam-ung.json']) {
      final p = File('test/fixtures/flows/$f');
      if (!p.existsSync()) continue;
      final def = jsonDecode(p.readAsStringSync()) as Map<String, dynamic>;
      expect(graph(FlowDoc.fromJson(def).toJson()), graph(def), reason: f);
    }
  });

  test('khối lặp: foreach / foreach_end -> khung Lặp bảng có thân', () {
    const src = '''{"id":"nk","name":"Nhập kho","nodes":[{"id":"start","type":"start"},
      {"id":"lap","type":"foreach","name":"Kiểm từng dòng","items":"form.hang","end":"het"},
      {"id":"co_loi","type":"condition","rules":[{"if":"item.loi > 0","to":"bao"}],"else":"het"},
      {"id":"bao","type":"notify","to":["\$requester"],"text":"x"},{"id":"het","type":"foreach_end"},
      {"id":"kn","type":"start_flow","flow_id":"khieu-nai"},{"id":"end","type":"end"}],
      "edges":[["start","lap"],["lap","co_loi"],["bao","het"],["het","kn"],["kn","end"]]}''';
    final def = jsonDecode(src) as Map<String, dynamic>;
    final doc = FlowDoc.fromJson(def);
    expect([for (final x in doc.steps) x.id], ['lap', 'kn']);
    final l = doc.steps.first as FLoop;
    expect(l.items, 'form.hang');
    expect((l.legacy, l.stopOnError), (false, true), reason: 'đổi sang khung Lặp bảng, lỗi thì dừng như cũ');
    expect(l.body.single, isA<FCondition>());
    expect(doc.upgradedKinds, contains('table_loop'));
    Map<String, Map> nodes(Map<String, dynamic> j) => {for (final n in j['nodes'] as List) '${n['id']}': n as Map};
    Set<String> edges(Map<String, dynamic> j) => {for (final e in j['edges'] as List) '${e[0]}>${e[1]}'};
    var j = doc.toJson();
    expect(nodes(j)['lap']!['type'], 'table_loop');
    expect((nodes(j)['lap']!['body'] as List).toSet(), {'co_loi', 'bao'});
    expect(nodes(j)['lap']!['entry'], 'co_loi');
    expect(nodes(j)['co_loi']!['else'], '', reason: 'nhánh tới foreach_end cũ = kết thúc lượt');
    expect(nodes(j).containsKey('het'), isFalse);
    expect(edges(j), containsAll(['lap>kn', 'kn>end']));
    // Kéo bước ngoài vào đầu thân lặp: thành bước con đầu tiên, sau khung là kết thúc.
    doc.move('kn', l.body, 0);
    expect(l.body.first.id, 'kn');
    j = doc.toJson();
    expect(nodes(j)['lap']!['entry'], 'kn');
    expect(edges(j), containsAll(['lap>end', 'kn>co_loi']));
    expect(edges(j).any((e) => e.startsWith('bao>')), isFalse);
  });
}
