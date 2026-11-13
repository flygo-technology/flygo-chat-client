import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import 'flow_cond.dart';
import 'flow_doc.dart';

/// Kết quả (`steps.<bước>.output.*`) của các bước thẻ dữ liệu, tiến trình, chờ người dùng, Duyệt:
/// dùng được ở Rẽ nhánh và ô chèn thông tin, kèm tên dễ đọc.

/// Loại bước mới (thẻ, tiến trình, chờ người dùng, phê duyệt).
const editorNodeTypes = {
  'send',
  'card_send',
  'card_update',
  'card_wait',
  'process_create',
  'process_step',
  'process_stat',
  'process_attach',
  'process_fail',
  'process_finish',
  'process_send',
  'process_find',
  'process_label',
  'process_props',
  'process_wait',
  'doc_render',
  'process_remind',
  'wait_button',
  'wait_choice',
  'wait_close',
  'approval_request',
};

/// Khoá kết quả → tên hiển thị (dịch bằng tr khi dùng).
const nodeOutputLabels = {
  'post_id': 'Mã tin thẻ',
  'post_ids': 'Các tin đã gửi',
  'clicked': 'Nút đã bấm',
  'label': 'Tên nút đã bấm',
  'by': 'Người thao tác',
  'at': 'Lúc thao tác',
  'timed_out': 'Quá hạn chờ',
  'process_id': 'Mã tiến trình',
  'existed': 'Đã có từ trước',
  'found': 'Tìm thấy',
  'state': 'Trạng thái tiến trình',
  'current_step': 'Bước hiện tại',
  'stats': 'Thống kê',
  'labels': 'Nhãn',
  'files': 'Tệp',
  'links': 'Liên kết',
  'chosen': 'Các lựa chọn đã chọn',
  'closed': 'Đã kết thúc chờ',
  'decision': 'Kết quả phê duyệt',
  'reason': 'Lý do',
  'return_step': 'Bước bị trả về',
  'escalated_to': 'Đã chuyển lên',
  'level': 'Cấp leo thang',
  'via': 'Thao tác ở',
  'process_ids': 'Các mã tiến trình',
  'file_id': 'Mã tệp',
  'name': 'Tên tệp',
  'size': 'Cỡ tệp (byte)',
  'mime_type': 'Loại tệp',
  'count': 'Số tiến trình',
  'created': 'Số tiến trình mới tạo',
  'props': 'Thuộc tính',
  'matched': 'Số tiến trình đã tới',
  'total': 'Tổng số tiến trình',
  'states': 'Trạng thái các tiến trình',
  'due_at': 'Lúc nhắc',
};

/// Giá trị của "Kết quả phê duyệt".
const approvalDecisions = ['approve', 'reject', 'return', 'timeout'];

/// Giá trị của "Trạng thái tiến trình".
const processStates = ['running', 'failed', 'done', 'cancelled', 'skipped'];

/// Tên hiện của một kết quả của bước [s] (null: không phải bước mới / khoá lạ).
String? nodeOutputLabel(FStep s, String key) {
  if (!editorNodeTypes.contains(s.type)) return null;
  if (key == 'by') {
    return switch (s.type) {
      'approval_request' => tr('Người phê duyệt'),
      'wait_choice' => tr('Người chọn'),
      _ => tr('Người bấm'),
    };
  }
  if (s.type == 'approval_request') {
    final f = FlowField.listOf(s.node['fields']).where((f) => f.key == key).firstOrNull;
    if (f != null) return f.label;
  }
  final l = nodeOutputLabels[key];
  return l == null ? null : tr(l);
}

/// Thông tin dùng được ở bước sau, do bước [s] tạo ra.
List<CondVar> nodeVars(FStep s, String name) {
  CondVar v(String key, String type, [List<String> options = const []]) => CondVar('steps.${s.id}.output.$key', '$name › ${nodeOutputLabel(s, key) ?? key}', type, options);
  final n = s.node;
  switch (s.type) {
    case 'card_send' || 'card_update':
      return [v('post_id', 'text')];
    // Gửi: thẻ → mã tin; thẻ tiến trình → mã tiến trình; tin nhắn chữ → không có kết quả.
    case 'send':
      if (n['process'] != null) return [v('process_id', 'text')];
      if (n['card'] != null) return [v('post_id', 'text')];
      return const [];
    case 'card_wait':
      return [
        v('clicked', 'select', [for (final x in (n['ids'] as List? ?? const [])) '$x']),
        v('label', 'text'),
        v('by', 'user'),
        v('timed_out', 'bool'),
      ];
    case 'process_create':
      if ('${n['each'] ?? ''}'.trim().isNotEmpty) return [v('count', 'number'), v('created', 'number')];
      return [v('process_id', 'text'), v('existed', 'bool')];
    case 'process_props':
      return [v('process_id', 'text')];
    case 'doc_render':
      return [v('file_id', 'text'), v('name', 'text'), v('size', 'number')];
    case 'process_wait':
      return [v('matched', 'number'), v('total', 'number'), if ('${n['timeout'] ?? ''}'.isNotEmpty) v('timed_out', 'bool')];
    case 'process_find':
      return [v('found', 'bool'), v('process_id', 'text'), v('state', 'select', processStates), v('current_step', 'text')];
    case 'wait_button':
      final labels = [
        for (final b in (n['buttons'] as List? ?? const []))
          if (b is Map && b['url'] == null && '${b['label'] ?? ''}'.isNotEmpty) '${b['label']}',
      ];
      final where = n['where'] is Map ? n['where'] as Map : const {};
      // Chờ nút có sẵn trên thẻ đã gửi: mã nút (id trên thẻ; nút "*" nhận mọi nút).
      final onCard = where['card'] is Map;
      return [
        if (onCard) v('clicked', 'select', [for (final b in (n['buttons'] as List? ?? const [])) if (b is Map && b['url'] == null && b['id'] != '*') '${b['id']}']),
        v('label', 'select', labels),
        v('by', 'user'),
        if (onCard || where['message'] is Map) v('post_id', 'text'),
      ];
    case 'wait_choice':
      return [v('by', 'user')];
    case 'wait_close':
      return [v('closed', 'bool')];
    case 'approval_request':
      return [
        v('decision', 'select', approvalDecisions),
        v('by', 'user'),
        v('reason', 'text'),
        for (final f in FlowField.listOf(n['fields']))
          if (!const {'files', 'images', 'photo', 'table'}.contains(f.type)) CondVar('steps.${s.id}.output.${f.key}', '$name › ${f.label}', f.type, f.options),
      ];
  }
  return const [];
}

/// Tên hiện của thông tin chung của tiến trình chính (`process.<khoá>`).
const processVarLabels = {
  'state': 'Trạng thái',
  'current_step': 'Bước hiện tại',
  'name': 'Tên',
  'key': 'Khoá',
};

/// Biến `process.*` của tiến trình chính của luồng (bước Tạo tiến trình một tiến trình / Tìm tiến trình đầu tiên đã
/// chạy): thuộc tính khai báo trong quy trình, thống kê, trạng thái, bước hiện tại. Không có bước nào như vậy: rỗng.
List<CondVar> processVars(List<FStep> steps) {
  final main = steps.any((s) => (s.type == 'process_create' && '${s.node['each'] ?? ''}'.trim().isEmpty) || s.type == 'process_find');
  if (!main) return const [];
  final root = tr('Tiến trình');
  final props = <String, String>{};
  final stats = <String, Map>{};
  for (final s in steps) {
    if (s.type == 'process_create' && '${s.node['each'] ?? ''}'.trim().isEmpty) {
      for (final k in ((s.node['props'] as Map?) ?? const {}).keys) {
        props.putIfAbsent('$k', () => '$k');
      }
      for (final f in (s.node['fields'] as List? ?? const [])) {
        if (f is Map && '${f['label'] ?? ''}'.trim().isNotEmpty && props.containsKey('${f['prop']}')) props['${f['prop']}'] = '${f['label']}'.trim();
      }
      for (final st in (s.node['stats'] as List? ?? const [])) {
        if (st is Map) stats.putIfAbsent('${st['key']}', () => st);
      }
    }
    if (s.type == 'process_props') {
      for (final k in ((s.node['set'] as Map?) ?? const {}).keys) {
        props.putIfAbsent('$k', () => '$k');
      }
    }
  }
  return [
    CondVar('process.state', '$root › ${tr('Trạng thái')}', 'select', processStates),
    CondVar('process.current_step', '$root › ${tr('Bước hiện tại')}', 'text'),
    // Khoá "_…" là dữ liệu nội bộ (không hiện cho người dùng): vẫn chọn được, xếp cuối dưới nhóm "Ẩn".
    for (final e in props.entries) if (!e.key.startsWith('_')) CondVar('process.props.${e.key}', '$root › ${tr('Thuộc tính')} › ${e.value}', 'text'),
    for (final e in stats.entries)
      if (!e.key.startsWith('_'))
        CondVar('process.stats.${e.key}', '$root › ${tr('Thống kê')} › ${'${e.value['label'] ?? ''}'.trim().isEmpty ? e.key : e.value['label']}', e.value['type'] == 'text' ? 'text' : 'number'),
    for (final e in props.entries) if (e.key.startsWith('_')) CondVar('process.props.${e.key}', '$root › ${tr('Ẩn')} › ${e.value}', 'text'),
    for (final e in stats.entries) if (e.key.startsWith('_')) CondVar('process.stats.${e.key}', '$root › ${tr('Ẩn')} › ${e.key}', e.value['type'] == 'text' ? 'text' : 'number'),
  ];
}

/// Tên mặc định (khi bước chưa đặt tên) của các bước mới.
String nodeDefaultName(String type) => switch (type) {
      'send' => tr('Gửi'),
      'card_send' => tr('Gửi thẻ'),
      'card_update' => tr('Sửa thẻ'),
      'card_wait' => tr('Chờ bấm nút trên thẻ'),
      'process_create' => tr('Tạo tiến trình'),
      'process_step' => tr('Chuyển bước tiến trình'),
      'process_stat' => tr('Cập nhật thống kê'),
      'process_attach' => tr('Đính kèm vào tiến trình'),
      'process_fail' => tr('Báo lỗi tiến trình'),
      'process_finish' => tr('Hoàn thành tiến trình'),
      'process_send' => tr('Gửi tiến trình'),
      'process_find' => tr('Tìm tiến trình'),
      'process_label' => tr('Gắn nhãn tiến trình'),
      'process_props' => tr('Gán thuộc tính tiến trình'),
      'process_wait' => tr('Chờ tiến trình'),
      'doc_render' => tr('Tạo tài liệu'),
      'process_remind' => tr('Nhắc theo mốc'),
      'wait_button' => tr('Chờ bấm nút'),
      'wait_choice' => tr('Lựa chọn'),
      'wait_close' => tr('Kết thúc chờ'),
      'approval_request' => tr('Duyệt'),
      _ => type,
    };
