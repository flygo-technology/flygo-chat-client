import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart' show upgradeNote;
import 'package:flygo_chat/ui/flows/flow_editor_upgrade.dart';

/// Bước gộp: Thông báo / Gửi thẻ / Gửi tiến trình → Gửi; Nút trên tin (có nút chạy tiếp) / Chờ bấm nút trên thẻ →
/// Chờ bấm nút. Cùng cách đổi với `flows_engine::upgrade` (upgrade_sends, upgrade_waits) của máy chủ.
void main() {
  Map<String, Map<String, dynamic>> nodesOf(Map<String, dynamic> def) => {for (final n in def['nodes'] as List) '${n['id']}': (n as Map).cast<String, dynamic>()};
  List<String> edgesOf(Map<String, dynamic> def) => [for (final e in def['edges'] as List) '${e[0]}>${e[1]}'];

  Map<String, dynamic> legacy() => jsonDecode(r'''{"id":"bc","name":"Báo có",
    "form":[{"key":"ghi_chu","label":"Ghi chú","type":"text","show_if":"steps.nut.output.clicked == 'Đã nhận'"}],
    "nodes":[{"id":"start","type":"start"},
      {"id":"bao","no":2,"type":"notify","name":"Báo nhóm","to":["$requester"],"channels":["c1"],"text":"Tiền về {{form.so}}"},
      {"id":"the","no":3,"type":"card_send","channels":["c1"],"card":{"v":1,"title":"HĐ","actions":[{"id":"ky","label":"Ký"},{"id":"bo","label":"Bỏ"},{"label":"Xem","url":"https://x"}]},"message":"HĐ mới"},
      {"id":"tao","type":"process_create","key":"k","title":"t","steps":[{"key":"b1","title":"B1"}]},
      {"id":"gtt","type":"process_send","process":{"step":"tao"},"to":["$requester"],"sync":false},
      {"id":"nut","no":5,"type":"buttons","name":"Nút xác nhận","message":{"step":"bao"},"who":{"department":"kd"},
        "buttons":[{"label":"Đã nhận"},{"label":"Xem ERP","url":"https://erp"},{"label":"Không phải"}]},
      {"id":"link","type":"buttons","message":{"step":"bao"},"buttons":[{"label":"Chỉ link","url":"https://a"}]},
      {"id":"cw","type":"card_wait","card":{"step":"the"},"ids":["ky"],"who":"$requester","timeout":"24h","seconds":10},
      {"id":"cw2","type":"card_wait","card":{"post_id":"{{steps.x.output.post_id}}"}},
      {"id":"sau","type":"progress","label":"{{steps.nut.output.clicked}} / {{steps.nut.output.clicked_by}}"},
      {"id":"end","type":"end"}],
    "edges":[["start","bao"],["bao","the"],["the","tao"],["tao","gtt"],["gtt","nut"],["nut","link"],["link","cw"],["cw","cw2"],["cw2","sau"],["sau","end"]]}''') as Map<String, dynamic>;

  test('hàm đổi: gửi → send (giữ id, số, tên, nơi gửi, nội dung)', () {
    final up = upgradeLegacySteps(legacy());
    final n = nodesOf(up.def);
    expect(n['bao'], {'id': 'bao', 'no': 2, 'name': 'Báo nhóm', 'type': 'send', 'to': [r'$requester'], 'channels': ['c1'], 'text': 'Tiền về {{form.so}}'});
    expect(n['the']!['type'], 'send');
    expect(n['the']!['card']['title'], 'HĐ');
    expect(n['the']!['message'], 'HĐ mới');
    expect(n['the']!.containsKey('text'), isFalse);
    expect(n['gtt'], {'id': 'gtt', 'type': 'send', 'to': [r'$requester'], 'process': {'step': 'tao'}, 'sync': false});
    expect(edgesOf(up.def), containsAll(['bao>the', 'the>tao', 'gtt>nut']), reason: 'cạnh của bước gửi giữ nguyên');
  });

  test('hàm đổi: Nút trên tin → Chờ bấm nút (tin nhắn), clicked → label; chỉ có link thì giữ', () {
    final up = upgradeLegacySteps(legacy());
    final n = nodesOf(up.def);
    expect(n['nut'], {
      'id': 'nut',
      'no': 5,
      'name': 'Nút xác nhận',
      'type': 'wait_button',
      'where': {'message': {'step': 'bao'}},
      'who': {'department': 'kd'},
      'buttons': [
        {'id': 'nut_1', 'label': 'Đã nhận', 'to': 'link'},
        {'id': 'link_2', 'label': 'Xem ERP', 'url': 'https://erp'},
        {'id': 'nut_3', 'label': 'Không phải', 'to': 'link'},
      ],
    });
    expect(edgesOf(up.def), isNot(contains('nut>link')), reason: 'cạnh đi ra thành nhánh của các nút');
    expect(n['link']!['type'], 'buttons', reason: 'bộ nút chỉ có link không phải bước chờ');
    expect(edgesOf(up.def), contains('link>cw'));
    // Bước cũ trả chữ nút ở clicked; bước mới ở label. Tên dài hơn (clicked_by) không đổi.
    expect(n['sau']!['label'], '{{steps.nut.output.label}} / {{steps.nut.output.clicked_by}}');
    expect((up.def['form'] as List).single['show_if'], "steps.nut.output.label == 'Đã nhận'");
  });

  test('hàm đổi: Chờ bấm nút trên thẻ → Chờ bấm nút (thẻ đã gửi): nút theo ids, nhãn từ thẻ; không biết thì "*"', () {
    final up = upgradeLegacySteps(legacy());
    final n = nodesOf(up.def);
    expect(n['cw'], {
      'id': 'cw',
      'type': 'wait_button',
      'where': {'card': {'step': 'the'}},
      'who': r'$requester',
      'seconds': 10,
      'buttons': [
        {'id': 'ky', 'label': 'Ký', 'to': 'cw2'},
      ],
      'timeout': '24h',
      'timeout_to': 'cw2',
    });
    expect(n['cw2']!['buttons'], [
      {'id': '*', 'label': 'Bất kỳ nút nào', 'to': 'sau'},
    ]);
    expect(n['cw2']!.containsKey('timeout_to'), isFalse);
    // Không có ids: mọi nút có id của thẻ.
    final d = legacy();
    (d['nodes'] as List).firstWhere((x) => x['id'] == 'cw').remove('ids');
    expect([for (final b in nodesOf(upgradeLegacySteps(d).def)['cw']!['buttons'] as List) '${b['id']}:${b['label']}'], ['ky:Ký', 'bo:Bỏ']);
    expect(up.ids, ['bao', 'the', 'gtt', 'nut', 'cw', 'cw2']);
    expect(up.kinds, ['send', 'wait_button']);
    expect(legacyKinds(legacy()), ['notify', 'card_send', 'process_send', 'buttons', 'card_wait']);
    expect(legacyKinds(up.def), isEmpty, reason: 'buttons chỉ có link không cần đổi');
  });

  test('mở quy trình: sơ đồ chỉ còn bước gộp, có ghi chú nâng cấp; lưu rồi mở lại thì không đổi gì nữa', () {
    final doc = FlowDoc.fromJson(legacy());
    expect(doc.upgraded, ['bao', 'the', 'gtt', 'nut', 'cw', 'cw2']);
    expect(upgradeNote(doc), 'Đã nâng cấp bước Gửi, Chờ bấm nút sang dạng mới, lưu để áp dụng');
    final types = {for (final s in doc.allSteps) s.id: s.type};
    expect(types['bao'], 'send');
    expect(types['nut'], 'wait_button');
    expect(types['cw'], 'wait_button');
    final nut = doc.allSteps.firstWhere((s) => s.id == 'nut');
    expect([for (final p in nut.ports) p.key], ['always', 'b:nut_1', 'b:nut_3']);
    final cw = doc.allSteps.firstWhere((s) => s.id == 'cw');
    expect([for (final p in cw.ports) p.key], ['always', 'b:ky', 'timeout']);
    final def = doc.toJson();
    final n = nodesOf(def);
    expect([for (final b in n['nut']!['buttons'] as List) b['to']], ['link', null, 'link']);
    expect(n['cw']!['timeout_to'], 'cw2');
    final back = FlowDoc.fromJson(jsonDecode(jsonEncode(def)) as Map<String, dynamic>);
    expect(back.upgraded, isEmpty);
    expect(back.toJson(), def);
  });

  test('ghi chú nâng cấp: chỉ Duyệt cũ thì như trước; cả Duyệt và Gửi thì kể đủ', () {
    final onlyApproval = FlowDoc.fromJson({
      'id': 'x',
      'nodes': [
        {'id': 'start', 'type': 'start'},
        {'id': 'd', 'type': 'approval', 'approver': r'$requester'},
        {'id': 'end', 'type': 'end'},
      ],
      'edges': [['start', 'd'], ['d', 'end']],
    });
    expect(upgradeNote(onlyApproval), 'Đã nâng cấp bước Duyệt sang dạng mới, lưu để áp dụng');
    final both = FlowDoc.fromJson({
      'id': 'x',
      'nodes': [
        {'id': 'start', 'type': 'start'},
        {'id': 'd', 'type': 'approval', 'approver': r'$requester'},
        {'id': 'b', 'type': 'notify', 'to': [r'$requester'], 'text': 'x'},
        {'id': 'end', 'type': 'end'},
      ],
      'edges': [['start', 'd'], ['d', 'b'], ['b', 'end']],
    });
    expect(both.upgraded, ['d', 'b']);
    expect(upgradeNote(both), 'Đã nâng cấp bước Duyệt, Gửi sang dạng mới, lưu để áp dụng');
  });
}
