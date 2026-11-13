import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';

void main() {
  final app = AppState('t');
  final doc = FlowDoc.fromJson({
    'id': 'CC0002',
    'name': 'Chấm công một chạm',
    'form': [
      {'key': 'vi_tri', 'label': 'Vị trí', 'type': 'location'},
    ],
    'nodes': [
      {'id': 'start', 'type': 'start'},
      {'id': 'kc', 'type': 'geo_distance', 'name': 'Khoảng cách tới xưởng', 'from': 'form.vi_tri', 'lat': 21.0285, 'lon': 105.8542, 'radius': 200},
      {'id': 'kc2', 'type': 'geo_distance', 'name': '', 'from': '', 'lat': 0, 'lon': 0},
      {'id': 'end', 'type': 'end'},
    ],
    'edges': [['start', 'kc'], ['kc', 'kc2'], ['kc2', 'end']],
  });
  FStep step(String id) => doc.allSteps.firstWhere((s) => s.id == id);

  test('tóm tắt bước Tính khoảng cách GPS', () {
    final vars = flowVars(doc);
    expect(stepSummary(step('kc'), app, vars), 'Từ «Vị trí» tới (21.0285, 105.8542) · trong 200 m');
    expect(stepSummary(step('kc2'), app, vars), 'Từ chưa chọn vị trí tới (chưa đặt vị trí công ty)');
    expect(stepLook('geo_distance').$3, 'Tính khoảng cách GPS');
  });

  test('kết quả dùng được ở Rẽ nhánh, nhãn dễ đọc', () {
    final vars = {for (final v in flowVars(doc)) v.path: v};
    expect(vars['steps.kc.output.distance_m']?.type, 'number');
    expect(vars['steps.kc.output.inside']?.type, 'bool');
    expect(vars['steps.kc.output.inside']?.label, 'Khoảng cách tới xưởng › Trong khu vực');
    expect(vars['steps.kc2.output.distance_m']?.label, 'Tính khoảng cách GPS › Khoảng cách (m)');
    expect(flowVarLabel('steps.kc.output.accuracy', doc), 'Khoảng cách tới xưởng › Độ chính xác GPS (m)');
    expect(flowVarLabel('steps.kc.output.radius', doc), 'Khoảng cách tới xưởng › Bán kính (m)');
  });

  test('mẫu bước mới', () {
    final s = FlowDoc.make('geo_distance') as FStep;
    expect(s.type, 'geo_distance');
    expect(s.node['radius'], 200);
  });
}
