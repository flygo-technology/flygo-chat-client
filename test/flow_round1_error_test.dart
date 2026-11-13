import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart' show flowVarLabel;
import 'package:flygo_chat/ui/flows/flow_editor_errors.dart';

/// Nhánh Lỗi (`on_error: {"to"}`) của bước tự động / AI / chờ sự kiện / bắt đầu quy trình khác: sơ đồ có hai nhánh
/// "Thành công" (cạnh đi ra) và "Lỗi"; đổi qua lại JSON giữ nguyên đường đi; kết quả «… › Lỗi › Nội dung / Mã».
void main() {
  Map<String, Map<String, dynamic>> nodesOf(Map<String, dynamic> def) => {for (final n in def['nodes'] as List) '${n['id']}': (n as Map).cast<String, dynamic>()};
  List<String> edgesOf(Map<String, dynamic> def) => [for (final e in def['edges'] as List) '${e[0]}>${e[1]}'];

  Map<String, dynamic> flow() => jsonDecode(r'''{"id":"pc","name":"Phiếu chi","nodes":[
    {"id":"start","type":"start"},
    {"id":"goi_erp","type":"auto","name":"Lập phiếu ERP","action":"mcp","params":{"server":"erp","tool":"lap_phieu","args":{}},
      "timeout":"30s","retry":2,"on_error":{"to":"bao_loi"}},
    {"id":"xong","type":"send","to":["$requester"],"text":"Đã lập phiếu"},
    {"id":"bao_loi","type":"send","to":[{"role":"ke_toan"}],"text":"Lỗi {{steps.goi_erp.output.error.code}}: {{steps.goi_erp.output.error.message}}"},
    {"id":"end","type":"end"}],
    "edges":[["start","goi_erp"],["goi_erp","xong"],["xong","end"],["bao_loi","end"]]}''') as Map<String, dynamic>;

  test('JSON → sơ đồ: nhánh Thành công đi tiếp, nhánh Lỗi riêng rồi kết thúc', () {
    final doc = FlowDoc.fromJson(flow());
    expect([for (final x in doc.steps) x.id], ['goi_erp', 'xong']);
    final s = doc.steps.first as FStep;
    expect([for (final p in s.ports) p.key], ['ok', 'error']);
    final err = s.ports.last;
    expect(err.steps.map((x) => x.id), ['bao_loi']);
    expect(err.end, isTrue);
    expect(s.ports.first.steps, isEmpty);
    expect(s.node['on_error'], {'to': ''}, reason: 'đích nhánh chỉ có trong JSON');
    expect(s.node.containsKey('ok_to'), isFalse);
    expect(s.node['timeout'], '30s');
  });

  test('sơ đồ → JSON: cạnh đi ra + on_error.to, đổi qua lại không mất gì', () {
    final doc = FlowDoc.fromJson(flow());
    final def = doc.toJson();
    final n = nodesOf(def);
    expect(n['goi_erp']!['on_error'], {'to': 'bao_loi'});
    expect(n['goi_erp']!.containsKey('ok_to'), isFalse);
    expect(edgesOf(def), containsAll(['goi_erp>xong', 'xong>end', 'bao_loi>end']));
    final back = FlowDoc.fromJson(jsonDecode(jsonEncode(def)) as Map<String, dynamic>);
    expect(back.toJson(), def);
    // Bước đứng trước bước trong nhánh Lỗi có bước bị lỗi.
    expect(doc.predecessorsOf('bao_loi'), containsAll(['start', 'goi_erp']));
  });

  test('nhánh Lỗi gặp lại nhánh Thành công: các bước của nhánh trước điểm gặp lại', () {
    final d = flow();
    d['edges'] = [['start', 'goi_erp'], ['goi_erp', 'xong'], ['xong', 'end'], ['bao_loi', 'xong']];
    final doc = FlowDoc.fromJson(d);
    final s = doc.steps.first as FStep;
    expect([for (final x in doc.steps) x.id], ['goi_erp', 'xong']);
    expect(s.ports.last.steps.map((x) => x.id), ['bao_loi']);
    expect(s.ports.last.end, isFalse);
    expect(edgesOf(doc.toJson()), containsAll(['goi_erp>xong', 'bao_loi>xong']));
  });

  test('chọn "Đi nhánh lỗi" thì có nhánh; bỏ thì các bước của nhánh Thành công về sau bước, không mất', () {
    final doc = FlowDoc.fromJson({'id': 'x', 'nodes': [], 'edges': []});
    final ai = FlowDoc.make('ai') as FStep;
    final sau = FlowDoc.make('calc');
    doc.steps.addAll([ai, sau]);
    expect(ai.ports, isEmpty);
    doc.setNode(ai, {...ai.node, 'on_error': {'to': ''}});
    expect([for (final p in ai.ports) p.key], ['ok', 'error']);
    expect(ai.ports.last.end, isTrue, reason: 'nhánh Lỗi trống: kết thúc việc');
    final def = doc.toJson();
    expect(nodesOf(def)[ai.id]!['on_error'], {'to': 'end'});
    expect(edgesOf(def), contains('${ai.id}>${sau.id}'));
    // Có bước trong nhánh Thành công rồi bỏ nhánh Lỗi.
    final trong = FlowDoc.make('send');
    ai.ports.first.steps.add(trong);
    doc.setNode(ai, {...ai.node, 'on_error': 'fail'});
    expect(ai.ports, isEmpty);
    expect([for (final x in doc.steps) x.id], [ai.id, trong.id, sau.id]);
  });

  test('kết quả lỗi: «<bước> › Lỗi › Nội dung / Mã», chỉ khi có nhánh Lỗi', () {
    final doc = FlowDoc.fromJson(flow());
    final vars = {for (final v in flowVars(doc)) v.path: v};
    expect(vars['steps.goi_erp.output.error.message']?.label, 'Lập phiếu ERP › Lỗi › Nội dung');
    expect(vars['steps.goi_erp.output.error.code']?.label, 'Lập phiếu ERP › Lỗi › Mã');
    expect(vars['steps.goi_erp.output.error.code']?.options, containsAll(['timeout', 'bad_output', 'child_failed']));
    expect(flowVarLabel('steps.goi_erp.output.error.code', doc), 'Lập phiếu ERP › Lỗi › Mã');
    expect(flowVarLabel('steps.goi_erp.output.error', doc), 'Lập phiếu ERP › Lỗi');
    final plain = FlowDoc.fromJson({...flow(), 'nodes': [for (final n in flow()['nodes'] as List) n['id'] == 'goi_erp' ? {...n, 'on_error': 'fail'} : n]});
    expect(flowVars(plain).where((v) => v.path.contains('.error.')), isEmpty);
  });

  test('cách xử lý lỗi theo loại bước, thời hạn mỗi lần gọi', () {
    expect(errorModes('ai'), ['fail', 'continue', 'assign', 'branch']);
    expect(errorModes('auto'), ['fail', 'continue', 'assign', 'branch']);
    expect(errorModes('wait_event'), ['fail', 'branch']);
    expect(errorModes('start_flow'), ['fail', 'branch']);
    expect(errorMode({'on_error': {'to': 'x'}}), 'branch');
    expect(errorMode({'on_error': {'assign': r'$requester'}}), 'assign');
    expect(errorMode({'on_error': 'continue'}), 'continue');
    expect(errorMode(const {}), 'fail');
    expect(callTimeoutKey({'type': 'ai'}), 'timeout');
    expect(callTimeoutKey({'type': 'wait_event'}), 'call_timeout');
    expect(callTimeoutKey({'type': 'start_flow', 'wait': true}), 'timeout');
    expect(callTimeoutKey({'type': 'start_flow', 'wait': true, 'each': 'form.x'}), isNull, reason: 'nhiều luồng con có ô Hạn chờ riêng');
    expect(callTimeoutKey({'type': 'start_flow'}), isNull);
    // Bước có nhánh Lỗi chỉ ở 4 loại.
    expect(FStep.errorBranch({'type': 'calc', 'on_error': {'to': 'x'}}), isFalse);
    expect(FStep.errorBranch({'type': 'wait_event', 'on_error': {'to': 'x'}}), isTrue);
  });
}
