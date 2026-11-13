import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_calc.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';

void main() {
  final app = AppState('t');
  final doc = FlowDoc.fromJson({
    'id': 'CC0001',
    'name': 'Chấm công ca sáng',
    'form': [
      {'key': 'vi_tri', 'label': 'Vị trí vào ca', 'type': 'location'},
      {'key': 'anh', 'label': 'Ảnh', 'type': 'photo'},
    ],
    'nodes': [
      {'id': 'start', 'type': 'start'},
      {
        'id': 'vc', 'type': 'form_task', 'name': 'Vào ca', 'assignee': r'$requester',
        'fields': [
          {'key': 'wifi', 'label': 'Wi-Fi', 'type': 'wifi'},
          {'key': 'vt', 'label': 'Vị trí', 'type': 'location'},
        ],
      },
      {
        'id': 'kt', 'type': 'calc', 'name': 'Kiểm tra',
        'vars': [
          {'name': 'cach_m', 'label': 'Cách xưởng (m)', 'op': 'distance_m', 'args': {'a': {'path': 'steps.vc.output.vt'}, 'lat2': {'value': 21.0285}, 'lon2': {'value': 105.8542}}},
          {'name': 'muon', 'label': 'Muộn (phút)', 'op': 'minutes_between', 'args': {'a': {'value': '08:00'}, 'b': {'path': 'steps.vc.output.vt'}}},
        ],
      },
      {'id': 'chia', 'type': 'start_flow', 'name': 'Chia việc', 'flow_id': 'vao-ca', 'each_person': {'department': 'xuong'}, 'wait': true, 'timeout': '15m', 'title': 'Vào ca {{item.user}}'},
      {'id': 'trua', 'type': 'wait', 'until': '12:00'},
      {'id': 'end', 'type': 'end'},
    ],
    'edges': [['start', 'vc'], ['vc', 'kt'], ['kt', 'chia'], ['chia', 'trua'], ['trua', 'end']],
  });
  FStep step(String id) => doc.allSteps.firstWhere((s) => s.id == id);

  test('vị trí / Wi-Fi: biến có tên từng thành phần, ảnh chụp không thành biến', () {
    final vars = flowVars(doc);
    final byPath = {for (final v in vars) v.path: v};
    expect(byPath['form.vi_tri']?.type, 'location');
    expect(byPath['form.vi_tri.lat']?.label, 'Vị trí vào ca › Vĩ độ');
    expect(byPath['form.vi_tri.accuracy']?.type, 'number');
    expect(byPath['steps.vc.output.wifi.ssid']?.label, 'Vào ca › Wi-Fi › Tên Wi-Fi');
    expect(byPath.containsKey('form.anh'), isFalse);
    expect(byPath['steps.chia.output.pending_count']?.label, 'Chia việc › Số luồng chưa xong');
    expect(byPath['steps.chia.output.timed_out']?.type, 'bool');
  });

  test('đường dẫn biến → tên dễ đọc', () {
    expect(flowVarLabel('form.vi_tri.lon', doc), 'Vị trí vào ca › Kinh độ');
    expect(flowVarLabel('form.vi_tri.at', doc), 'Vị trí vào ca › Lúc lấy');
    expect(flowVarLabel('steps.vc.output.wifi.bssid', doc), 'Vào ca › Wi-Fi › Mã điểm phát');
    expect(flowVarLabel('steps.chia.output.pending', doc), 'Chia việc › Người / dòng chưa xong');
    expect(flowVarLabel('item.user', doc), 'Người nhận');
    expect(humanTemplate('Vào ca {{item.user}}', labelledVars(doc, flowVars(doc), const {}), doc), 'Vào ca «Người nhận»');
  });

  test('tóm tắt bước: mỗi người một luồng, hạn chờ, chờ đến giờ', () {
    expect(stepSummary(step('chia'), app), '→ vao-ca · Mỗi người trong «xuong» một luồng · chờ tối đa 15 phút');
    expect(stepSummary(step('trua'), app), 'Chờ đến 12:00 hôm nay');
    expect(isClockText('12:00'), isTrue);
    expect(isClockText('8:05'), isTrue);
    expect(isClockText('24:00'), isFalse);
    expect(isClockText('form.ngay'), isFalse);
  });

  test('phép tính chấm công: tóm tắt', () {
    final vars = flowVars(doc);
    final ops = {for (final v in (step('kt').node['vars'] as List)) '${(v as Map)['name']}': v};
    expect(calcSummary(ops['cach_m']!, vars, const []), 'Cách xưởng (m) = Khoảng cách từ Vào ca › Vị trí tới (21.0285, 105.8542)');
    expect(calcSummary(ops['muon']!, vars, const []), 'Muộn (phút) = Số phút từ 08:00 tới Vào ca › Vị trí');
    expect(calcSummary({'name': 'luc', 'op': 'now', 'args': {}}, vars, const []), 'luc = Bây giờ');
    expect(calcSummary({'name': 'p', 'op': 'minutes_between', 'args': {'a': {'value': '08:00'}, 'b': {'value': 'now'}}}, vars, const []), 'p = Số phút từ 08:00 tới Bây giờ');
    expect(calcOpType('distance_m'), 'number');
  });
}
