import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';

/// Bước nhiều cổng (Chờ bấm nút, Lựa chọn, Duyệt): mỗi nhánh ghi vào trường `to`, đổi qua lại JSON <-> sơ đồ
/// giữ nguyên đường đi; nhánh phụ tự kết thúc; nhánh "kết thúc việc" đi tới end.
void main() {
  Map<String, dynamic> roundTrip(FlowDoc d) => FlowDoc.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>).toJson();
  Map<String, Map<String, dynamic>> nodesOf(Map<String, dynamic> def) => {for (final n in def['nodes'] as List) '${n['id']}': (n as Map).cast<String, dynamic>()};

  const flow = '''{"id":"HD0001","name":"Hoá đơn","nodes":[
    {"id":"start","type":"start"},
    {"id":"tao","type":"process_create","key":"{{form.so}}","title":"HĐ {{form.so}}","steps":[{"key":"b1","title":"Nhận"},{"key":"b2","title":"Ký"}]},
    {"id":"cho","type":"wait_button","prompt":"Ký hoá đơn?","timeout":"24h",
      "buttons":[{"id":"ky","label":"Đã ký","to":"buoc2"},{"id":"bo","label":"Bỏ qua","to":"bo_qua"},{"id":"xem","label":"Xem","url":"https://x"}],
      "always_to":"cap_nhat","timeout_to":"loi"},
    {"id":"cap_nhat","type":"process_step","process":{"step":"tao"},"step":"b2"},
    {"id":"buoc2","type":"process_step","process":{"step":"tao"},"step":"b2"},
    {"id":"bo_qua","type":"process_label","process":{"step":"tao"},"add":["Bỏ qua"]},
    {"id":"loi","type":"process_fail","process":{"step":"tao"},"reason":"Quá hạn"},
    {"id":"xong","type":"process_finish","process":{"step":"tao"},"result":"done"},
    {"id":"end","type":"end"}],
    "edges":[["start","tao"],["tao","cho"],["cap_nhat","end"],["buoc2","xong"],["bo_qua","xong"],["loi","end"],["xong","end"]]}''';

  test('JSON → sơ đồ: mỗi nút một nhánh, nút mở link không có nhánh, gặp lại ở bước chung', () {
    final doc = FlowDoc.fromJson(jsonDecode(flow) as Map<String, dynamic>);
    expect([for (final x in doc.steps) x.id], ['tao', 'cho', 'xong']);
    final w = doc.steps[1] as FStep;
    expect([for (final p in w.ports) p.key], ['always', 'b:ky', 'b:bo', 'timeout']);
    final byKey = {for (final p in w.ports) p.key: p};
    expect(byKey['always']!.steps.map((x) => x.id), ['cap_nhat']);
    expect(byKey['b:ky']!.steps.map((x) => x.id), ['buoc2']);
    expect(byKey['b:bo']!.steps.map((x) => x.id), ['bo_qua']);
    // Quá hạn đi thẳng tới end: nhánh "kết thúc việc".
    expect(byKey['timeout']!.steps.map((x) => x.id), ['loi']);
    expect(byKey['timeout']!.end, isTrue);
    expect(byKey['b:ky']!.end, isFalse);
    expect(doc.allSteps.map((s) => s.id).toSet(), {'tao', 'cho', 'cap_nhat', 'buoc2', 'bo_qua', 'loi', 'xong'});
  });

  test('sơ đồ → JSON: trường to của từng nhánh, không cạnh đi ra, đổi qua lại không mất gì', () {
    final doc = FlowDoc.fromJson(jsonDecode(flow) as Map<String, dynamic>);
    final out = doc.toJson();
    final nodes = nodesOf(out);
    final cho = nodes['cho']!;
    expect(cho['always_to'], 'cap_nhat');
    expect(cho['timeout_to'], 'loi');
    final bs = {for (final b in cho['buttons'] as List) '${b['id']}': b as Map};
    expect(bs['ky']!['to'], 'buoc2');
    expect(bs['bo']!['to'], 'bo_qua');
    expect(bs['xem']!.containsKey('to'), isFalse, reason: 'nút chỉ mở link không rẽ nhánh');
    final edges = [for (final e in out['edges'] as List) '${e[0]}>${e[1]}'];
    expect(edges.where((e) => e.startsWith('cho>')), isEmpty);
    expect(edges, containsAll(['cap_nhat>end', 'buoc2>xong', 'bo_qua>xong', 'loi>end', 'xong>end', 'tao>cho']));
    expect(roundTrip(doc), out);
    // Sơ đồ không bị sửa khi dựng JSON (trường to chỉ có trong bản JSON).
    expect((doc.steps[1] as FStep).node['buttons'], isNot(anyElement(containsPair('to', anything))));
  });

  test('nhánh trống: nhánh chính đi tiếp bước sau, nhánh phụ bỏ trường to', () {
    final doc = FlowDoc.fromJson({'id': 'x', 'nodes': [], 'edges': []});
    final w = FlowDoc.make('wait_button') as FStep;
    final after = FlowDoc.make('notify');
    doc.steps.addAll([w, after]);
    expect(w.ports.map((p) => p.key).first, 'always');
    expect(w.ports.length, 3, reason: 'Luôn chạy + 2 nút, chưa có hạn chờ');
    final n = nodesOf(doc.toJson())[w.id]!;
    expect(n.containsKey('always_to'), isFalse);
    expect([for (final b in n['buttons'] as List) b['to']], [after.id, after.id]);
    // Đặt hạn chờ: có thêm nhánh Quá hạn.
    w.node['timeout'] = '4h';
    w.syncPorts();
    expect(w.ports.last.key, 'timeout');
    expect(nodesOf(doc.toJson())[w.id]!['timeout_to'], after.id);
  });

  test('syncPorts giữ bước trong nhánh của nút còn lại, bỏ nhánh của nút đã xoá', () {
    final w = FlowDoc.make('wait_button') as FStep;
    final ids = [for (final b in w.node['buttons'] as List) '${b['id']}'];
    final inner = FlowDoc.make('notify');
    w.ports.firstWhere((p) => p.key == 'b:${ids[1]}').steps.add(inner);
    w.node['buttons'] = [(w.node['buttons'] as List)[1], {'id': 'moi', 'label': 'Mới'}, {'id': 'link', 'label': 'Link', 'url': 'https://a'}];
    w.syncPorts();
    expect(w.ports.map((p) => p.key), ['always', 'b:${ids[1]}', 'b:moi']);
    expect(w.ports[1].steps.single, same(inner));
  });

  test('Duyệt: 5 nhánh theo cấu hình; Từ chối, Quá hạn để trống thì không ghi đích (bộ chạy làm như bước Duyệt cũ)', () {
    final a = FlowDoc.make('approval_request') as FStep;
    expect(a.ports.map((p) => p.key), ['always', 'approve', 'reject', 'timeout']);
    a.node['return_steps'] = ['start'];
    a.node['escalate'] = [
      {'after': '8h', 'to': {'role': 'truong_phong'}, 'mode': 'add'},
    ];
    a.syncPorts();
    expect(a.ports.map((p) => p.key), ['always', 'approve', 'reject', 'escalate', 'timeout'], reason: 'trả lại không phải nhánh');
    expect(a.ports.firstWhere((p) => p.key == 'reject').end, isTrue);
    expect(a.ports.firstWhere((p) => p.key == 'reject').unwired, isTrue);
    expect(a.ports.firstWhere((p) => p.key == 'approve').end, isFalse);

    final doc = FlowDoc.fromJson({'id': 'x', 'nodes': [], 'edges': []});
    final notify = FlowDoc.make('send'), bao = FlowDoc.make('send'), leo = FlowDoc.make('send'), sau = FlowDoc.make('calc');
    a.ports.firstWhere((p) => p.key == 'reject').steps.add(bao);
    a.ports.firstWhere((p) => p.key == 'escalate').steps.add(leo);
    a.ports.firstWhere((p) => p.key == 'always').steps.add(notify);
    doc.steps.addAll([a, sau]);
    final def = doc.toJson();
    final n = nodesOf(def)[a.id]!;
    expect(n['approve_to'], sau.id);
    expect(n['reject_to'], bao.id);
    expect(n['always_to'], notify.id);
    expect(n['escalate_to'], leo.id);
    expect(n.containsKey('timeout_to'), isFalse, reason: 'Quá hạn để trống: chỉ nhắc, yêu cầu vẫn mở');
    final edges = [for (final e in def['edges'] as List) '${e[0]}>${e[1]}'];
    expect(edges, containsAll(['${bao.id}>end_rejected', '${leo.id}>end', '${notify.id}>end', '${sau.id}>end']));
    expect(nodesOf(def)['end_rejected']!['status'], 'rejected');

    // Đổi qua lại: giữ đủ nhánh, nhánh kết thúc vẫn kết thúc.
    final back = FlowDoc.fromJson(jsonDecode(jsonEncode(def)) as Map<String, dynamic>);
    expect(back.steps.map((x) => x.id), [a.id, sau.id]);
    final b = back.steps.first as FStep;
    expect({for (final p in b.ports) p.key: p.steps.map((x) => x.id).toList()}, {
      'always': [notify.id],
      'approve': <String>[],
      'reject': [bao.id],
      'escalate': [leo.id],
      'timeout': <String>[],
    });
    expect(b.ports.firstWhere((p) => p.key == 'reject').end, isTrue);
    expect(b.ports.firstWhere((p) => p.key == 'timeout').end, isTrue);
    expect(b.ports.firstWhere((p) => p.key == 'timeout').unwired, isTrue);
    expect(back.toJson(), def);
  });

  test('Lựa chọn lồng trong Rẽ nhánh: điểm gặp lại của Rẽ nhánh không bị nhánh Luôn chạy làm lệch', () {
    final def = {
      'id': 'x',
      'nodes': [
        {'id': 'start', 'type': 'start'},
        {'id': 'dk', 'type': 'condition', 'rules': [{'if': 'form.a > 1', 'to': 'lc'}], 'else': 'chung'},
        {
          'id': 'lc', 'type': 'wait_choice', 'always_to': 'bao',
          'options': [{'id': 'a', 'label': 'A', 'to': 'x1'}, {'id': 'b', 'label': 'B', 'to': 'chung'}],
        },
        {'id': 'bao', 'type': 'notify'},
        {'id': 'x1', 'type': 'notify'},
        {'id': 'chung', 'type': 'calc'},
        {'id': 'end', 'type': 'end'},
      ],
      'edges': [['start', 'dk'], ['bao', 'end'], ['x1', 'chung'], ['chung', 'end']],
    };
    final doc = FlowDoc.fromJson(def);
    expect(doc.steps.map((x) => x.id), ['dk', 'chung']);
    final lc = doc.allSteps.firstWhere((s) => s.id == 'lc');
    expect({for (final p in lc.ports) p.key: p.steps.map((x) => x.id).toList()}, {
      'always': ['bao'],
      'o:a': ['x1'],
      'o:b': <String>[],
    });
    final n = nodesOf(doc.toJson());
    expect(n['lc']!['always_to'], 'bao');
    expect([for (final o in n['lc']!['options'] as List) o['to']], ['x1', 'chung']);
  });

  test('chuyển chỗ / xoá trong nhánh; không thả bước vào nhánh của chính nó', () {
    final doc = FlowDoc.fromJson(jsonDecode(flow) as Map<String, dynamic>);
    final w = doc.steps[1] as FStep;
    final ky = w.ports[1];
    expect(doc.listOf('buoc2'), same(ky.steps));
    doc.move('xong', ky.steps, 1);
    expect(ky.steps.map((x) => x.id), ['buoc2', 'xong']);
    doc.move('cho', ky.steps, 0);
    expect(doc.steps.map((x) => x.id), ['tao', 'cho'], reason: 'thả vào nhánh của chính nó bị bỏ qua');
    doc.remove('bo_qua');
    expect(w.ports[2].steps, isEmpty);
    doc.numberNodes();
    expect(doc.allItems.every((x) => x.no != null), isTrue);
  });

  test('bước đứng trước (để chọn bước trả lại, tiến trình)', () {
    final doc = FlowDoc.fromJson(jsonDecode(flow) as Map<String, dynamic>);
    expect(doc.predecessorsOf('xong'), containsAll(['start', 'tao', 'cho', 'buoc2', 'bo_qua']));
    expect(doc.predecessorsOf('xong').contains('loi'), isFalse);
    expect(doc.predecessorsOf('tao'), {'start'});
  });
}
