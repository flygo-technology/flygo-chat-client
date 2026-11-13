import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_card.dart';
import 'package:flygo_chat/ui/flows/flow_editor_nodes.dart';

/// Tóm tắt trên sơ đồ, tên nhánh, biến kết quả (kèm tên dễ đọc) của các bước thẻ / tiến trình / chờ người dùng /
/// tạo phê duyệt.
void main() {
  final app = AppState('t');
  final doc = FlowDoc.fromJson({
    'id': 'HD0001',
    'name': 'Đồng bộ hoá đơn',
    'form': [
      {'key': 'so_hd', 'label': 'Số hoá đơn', 'type': 'text'},
      {'key': 'tong', 'label': 'Tổng tiền', 'type': 'money'},
    ],
    'nodes': [
      {'id': 'start', 'type': 'start'},
      {'id': 'tim', 'type': 'process_find', 'name': 'Tìm hoá đơn', 'key': '{{form.so_hd}}'},
      {
        'id': 'tao', 'type': 'process_create', 'name': 'Tạo hoá đơn', 'key': '{{form.so_hd}}', 'title': 'Hoá đơn {{form.so_hd}}', 'icon': '🧾',
        'steps': [{'key': 'nhan', 'title': 'Nhận'}, {'key': 'ky', 'title': 'Ký số'}, {'key': 'gui', 'title': 'Gửi CQT'}],
        'stats': [{'key': 'tien', 'label': 'Tổng tiền', 'type': 'number', 'value': 0}, {'key': 'ncc', 'label': 'Nhà cung cấp', 'type': 'text'}],
        'labels': ['KLTM'],
      },
      {'id': 'gui', 'type': 'card_send', 'name': '', 'channels': ['c1', 'c2'], 'card': {'v': 1, 'title': 'Hoá đơn {{form.so_hd}}'}},
      {'id': 'sua', 'type': 'card_update', 'card': {'step': 'gui'}, 'step': '2', 'patch': {'status': {'label': 'Đã ký', 'tone': 'green'}}},
      {'id': 'b2', 'type': 'process_step', 'process': {'step': 'tao'}, 'step': 'ky', 'status_text': 'Chờ ký'},
      {'id': 'st', 'type': 'process_stat', 'process': {'step': 'tao'}, 'stats': [{'key': 'tien', 'op': 'add', 'value': '{{form.tong}}'}]},
      {'id': 'dk', 'type': 'process_attach', 'process': {'key': '{{form.so_hd}}'}, 'items': [{'kind': 'link', 'name': 'Chứng từ LinkQ', 'url': 'https://linkq'}]},
      {'id': 'nhan', 'type': 'process_label', 'process': {'step': 'tao'}, 'add': ['Nghi trùng'], 'remove': ['KLTM']},
      {'id': 'sd', 'type': 'process_send', 'process': {'step': 'tao'}, 'channels': ['c1'], 'sync': true},
      {
        'id': 'pd', 'type': 'approval_request', 'name': 'Duyệt xuất', 'title': 'Xuất hoá đơn {{form.so_hd}}', 'approver': {'role': 'ke_toan_truong'}, 'mode': 'all', 'due': '24h',
        'escalate': [{'after': '8h', 'to': {'role': 'giam_doc'}, 'mode': 'add'}],
        'fields': [{'key': 'ghi_chu', 'label': 'Ghi chú duyệt', 'type': 'text'}],
        'approve_to': 'cho', 'reject_to': 'end', 'timeout_to': 'end',
      },
      {
        'id': 'cho', 'type': 'wait_button', 'name': 'Kế toán xác nhận', 'prompt': 'Đã ký chưa?', 'who': {'role': 'ke_toan'}, 'where': {'process': {'step': 'tao'}, 'task': true}, 'timeout': '8h',
        'buttons': [{'id': 'ok', 'label': 'Đã ký', 'to': 'xong'}, {'id': 'pdf', 'label': 'Xem PDF', 'url': 'https://pdf'}],
        'always_to': 'dong', 'timeout_to': 'loi',
      },
      {'id': 'dong', 'type': 'wait_close', 'wait': 'cho', 'reason': 'Đã ký trên M-Invoice'},
      {'id': 'loi', 'type': 'process_fail', 'process': {'step': 'tao'}, 'reason': 'Quá hạn ký', 'step': 'ky'},
      {'id': 'xong', 'type': 'process_finish', 'process': {'step': 'tao'}, 'result': 'done'},
      {'id': 'end', 'type': 'end'},
    ],
    'edges': [
      ['start', 'tim'], ['tim', 'tao'], ['tao', 'gui'], ['gui', 'sua'], ['sua', 'b2'], ['b2', 'st'], ['st', 'dk'], ['dk', 'nhan'], ['nhan', 'sd'], ['sd', 'pd'],
      ['dong', 'end'], ['loi', 'end'], ['xong', 'end'],
    ],
  });
  FStep step(String id) => doc.allSteps.firstWhere((s) => s.id == id);
  // Tóm tắt dùng tên các bước của quy trình đang soạn (như khi trình soạn đang mở).
  editorCtx = EditorCtx(app: app, api: FlowsApi('t'), doc: doc, steps: doc.allSteps, vars: flowVars(doc));

  test('loại bước mới: tên, nhóm màu', () {
    expect(stepLook('process_create').$3, 'Tạo tiến trình');
    expect(stepLook('wait_button').$3, 'Chờ bấm nút');
    expect(stepLook('approval_request').$3, 'Duyệt');
    expect(stepLook('card_send').$2, kGroupMessage);
    expect(stepLook('process_step').$2, kGroupProcess);
  });

  test('tóm tắt trên sơ đồ', () {
    final vars = labelledVars(doc, flowVars(doc), const {});
    String sum(String id) => stepSummary(step(id), app, vars);
    expect(sum('tim'), 'Theo khoá «Số hoá đơn»');
    expect(sum('tao'), '🧾 Hoá đơn «Số hoá đơn» · 3 bước · 2 thống kê · khoá «Số hoá đơn»');
    // Gửi thẻ kiểu cũ mở ra thành bước Gửi (Thẻ).
    expect(sum('gui'), 'Thẻ “Hoá đơn «Số hoá đơn»” · vào 2 nhóm');
    expect(sum('sua'), 'Sửa thẻ của "Gửi" · sang bước 2 · Đã ký');
    expect(sum('b2'), '→ Ký số · Chờ ký');
    expect(sum('st'), 'Tổng tiền + «Tổng tiền»');
    expect(sum('dk'), 'Chứng từ LinkQ');
    expect(sum('nhan'), '+Nghi trùng, −KLTM');
    expect(sum('sd'), 'Thẻ tiến trình của "Tạo hoá đơn" · vào 1 nhóm', reason: 'Gửi tiến trình kiểu cũ mở ra thành bước Gửi (Tiến trình)');
    expect(sum('pd'), '“Xuất hoá đơn «Số hoá đơn»” · Kế toán trưởng · tất cả cùng duyệt · hạn 24 giờ · leo thang 1 cấp · nhập 1 thông tin');
    expect(sum('cho'), '“Đã ký chưa?” · 2 nút · Kế toán · Cả hai · hạn 8 giờ');
    expect(sum('dong'), 'Kết thúc chờ của "Kế toán xác nhận" · Đã ký trên M-Invoice');
    expect(sum('loi'), 'Lỗi: Quá hạn ký · ở bước Ký số');
    expect(sum('xong'), 'Hoàn thành');
    expect(processRefLabel({'key': '{{form.so_hd}}'}), 'tiến trình khoá {{form.so_hd}}');
    expect(processRefLabel({'step': 'tao'}), 'tiến trình của "Tạo hoá đơn"');
  });

  test('tên nhánh và nhánh kết thúc', () {
    final pd = step('pd');
    expect([for (final p in pd.ports) portLabel(pd, p)], ['Luôn chạy', 'Phê duyệt', 'Từ chối', 'Leo thang', 'Quá hạn (24 giờ)']);
    expect(pd.ports.firstWhere((p) => p.key == 'reject').end, isTrue);
    final cho = step('cho');
    expect([for (final p in cho.ports) portLabel(cho, p)], ['Luôn chạy', 'Đã ký', 'Quá hạn (8 giờ)'], reason: 'nút Xem PDF chỉ mở link');
    expect(cho.ports.first.steps.single.id, 'dong');
    expect(cho.ports.last.steps.single.id, 'loi');
    expect(cho.ports.last.end, isTrue);
  });

  test('biến kết quả và tên dễ đọc', () {
    final vars = {for (final v in flowVars(doc)) v.path: v};
    expect(vars['steps.tao.output.process_id']?.label, 'Tạo hoá đơn › Mã tiến trình');
    expect(vars['steps.tao.output.existed']?.type, 'bool');
    expect(vars['steps.tim.output.found']?.type, 'bool');
    expect(vars['steps.tim.output.state']?.options, contains('failed'));
    expect(vars['steps.gui.output.post_id']?.label, 'Gửi › Mã tin thẻ');
    expect(vars['steps.pd.output.decision']?.options, ['approve', 'reject', 'return', 'timeout']);
    expect(vars['steps.pd.output.by']?.type, 'user');
    expect(vars['steps.pd.output.ghi_chu']?.label, 'Duyệt xuất › Ghi chú duyệt');
    expect(vars['steps.cho.output.label']?.options, ['Đã ký']);
    expect(vars['steps.dong.output.closed']?.type, 'bool');
    // Bước nằm trong nhánh vẫn có biến.
    expect(vars.containsKey('steps.xong.output.process_id'), isFalse);
    expect(flowVarLabel('steps.tao.output.existed', doc), 'Tạo hoá đơn › Đã có từ trước');
    expect(flowVarLabel('steps.pd.output.by', doc), 'Duyệt xuất › Người phê duyệt');
    expect(flowVarLabel('steps.cho.output.by', doc), 'Kế toán xác nhận › Người bấm');
    expect(flowVarLabel('steps.pd.output.ghi_chu', doc), 'Duyệt xuất › Ghi chú duyệt');
    expect(humanTemplate('{{steps.tim.output.current_step}}', labelledVars(doc, flowVars(doc), const {}), doc), '«Tìm hoá đơn › Bước hiện tại»');
  });

  test('thẻ xem trước: thay biến bằng giá trị mẫu', () {
    final vars = flowVars(doc);
    final card = sampleCard({'title': 'Hoá đơn {{form.so_hd}}', 'hero': {'value': '{{form.tong}}'}, 'x': ['{{không.có}}']}, vars) as Map;
    expect(card['title'], 'Hoá đơn Số hoá đơn');
    expect((card['hero'] as Map)['value'], '12.500.000 ₫');
    expect(card['x'], ['…']);
    expect(mergeCardPatch({'title': 'A', 'status': {'label': 'x', 'tone': 'red'}}, {'status': {'label': 'y'}}), {
      'title': 'A',
      'status': {'label': 'y', 'tone': 'red'},
    });
  });

  test('bảng Thêm bước: có bước mới, ẩn bước cũ đã được thay', () {
    final all = {for (final l in [insertActionItems, insertProcessItems, insertCardItems, insertPeopleItems]) ...l.map((e) => e.$1)};
    expect(all, containsAll(['wait_button', 'wait_choice', 'wait_close', 'approval_request', 'send', 'card_update', 'process_create', 'process_label']));
    expect(all.intersection(supersededTypes), isEmpty);
    expect(supersededTypes, {'approval', 'buttons', 'card_wait', 'notify', 'card_send', 'process_send'});
  });
}
