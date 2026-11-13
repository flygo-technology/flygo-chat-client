import 'dart:io';

import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowOrange, kFlowGreen, kFlowRed;
import 'flow_cond.dart';
import 'flow_doc.dart';
import 'flow_editor.dart';
import 'flow_editor_card.dart';
import 'flow_editor_expr_field.dart' show ExprField;
import 'flow_editor_upgrade.dart' show anyButtonId;
import 'flow_editor_vars.dart';
import 'flow_icon_picker.dart';
import 'magic_sign_hooks.dart' show FlowSignEditor;
import '../common.dart' show pickFilesOrReport;

/// Trình soạn cho các bước thẻ dữ liệu (card_*), tiến trình (process_*), chờ người dùng (wait_button / wait_choice /
/// wait_close) và Duyệt (approval_request): hình, tóm tắt trên sơ đồ, tên nhánh, ô cấu hình.

/// Màu nhóm "Tiến trình".
const kGroupProcess = Color(0xFF0EA5E9);

(IconData, Color, String) nodeLook(String type) => switch (type) {
      'send' => (Icons.send_rounded, kGroupMessage, nodeDefaultName(type)),
      'card_send' => (Icons.style_outlined, kGroupMessage, nodeDefaultName(type)),
      'card_update' => (Icons.published_with_changes_rounded, kGroupMessage, nodeDefaultName(type)),
      'card_wait' => (Icons.touch_app_outlined, kGroupMessage, nodeDefaultName(type)),
      'process_create' => (Icons.add_task_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_step' => (Icons.timeline_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_stat' => (Icons.bar_chart_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_attach' => (Icons.link_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_fail' => (Icons.error_outline_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_finish' => (Icons.task_alt_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_send' => (Icons.send_outlined, kGroupProcess, nodeDefaultName(type)),
      'process_find' => (Icons.manage_search_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_label' => (Icons.label_outline_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_props' => (Icons.data_object_rounded, kGroupProcess, nodeDefaultName(type)),
      'process_wait' => (Icons.hourglass_top_rounded, kGroupProcess, nodeDefaultName(type)),
      'doc_render' => (Icons.description_outlined, kGroupProcess, nodeDefaultName(type)),
      'process_remind' => (Icons.notifications_active_outlined, kGroupProcess, nodeDefaultName(type)),
      'wait_button' => (Icons.smart_button_outlined, kGroupPeople, nodeDefaultName(type)),
      'wait_choice' => (Icons.checklist_rounded, kGroupPeople, nodeDefaultName(type)),
      'wait_close' => (Icons.cancel_schedule_send_outlined, kGroupPeople, nodeDefaultName(type)),
      'approval_request' => (Icons.how_to_reg_rounded, kGroupPeople, nodeDefaultName(type)),
      _ => (Icons.approval_outlined, kGroupPeople, nodeDefaultName(type)),
    };

/// Mục trong bảng "Thêm bước" (nhóm, loại, mô tả). Bước cũ đã có bước mới thay (Duyệt, Nút trên tin, Chờ bấm nút
/// trên thẻ) không còn trong bảng; quy trình đang dùng vẫn sửa / vẽ được.
const insertActionItems = [
  ('wait_button', 'Chờ người bấm một nút (Đồng ý / Từ chối...) ở Tiến trình của tôi, thẻ tiến trình, thẻ đã gửi hoặc tin nhắn: mỗi nút một nhánh, có nhánh Luôn chạy và Quá hạn'),
  ('wait_choice', 'Người dùng tích một hay nhiều lựa chọn rồi Gửi: mỗi lựa chọn một nhánh, chạy song song'),
  ('wait_close', 'Kết thúc lượt chờ của bước Chờ bấm nút / Lựa chọn / Duyệt (vd đã xử lý tự động)'),
];

const insertProcessItems = [
  ('process_create', 'Tạo đối tượng theo dõi (vd mỗi hoá đơn): các bước cố định, thống kê, nhãn; khoá trùng thì dùng lại'),
  ('process_step', 'Chuyển tiến trình sang bước khác, đổi dòng trạng thái'),
  ('process_stat', 'Đặt / cộng / trừ thống kê của tiến trình'),
  ('process_attach', 'Đính kèm tệp, thư mục, liên kết (vd link chứng từ) vào tiến trình'),
  ('process_fail', 'Đánh dấu bước lỗi, tiến trình hiện ở tab Lỗi'),
  ('process_finish', 'Kết thúc tiến trình: hoàn thành / huỷ / bỏ qua'),
  ('process_find', 'Tìm tiến trình theo khoá (vd mã hoá đơn) để cập nhật tiếp'),
  ('process_label', 'Gắn / bỏ nhãn của tiến trình'),
  ('process_props', 'Gán / bỏ thuộc tính của tiến trình (vd số PO, ETA): tìm được, liên kết các tiến trình cùng giá trị'),
  ('process_remind', 'Nhắc người phụ trách theo một mốc của tiến trình (vd 3 ngày trước ETA); mốc đổi thì tự dời, tiến trình xong thì thôi'),
  ('doc_render', 'Tạo tài liệu Word / PDF từ mẫu Word (hợp đồng, phiếu, biên bản…) và gắn vào tiến trình'),
  ('process_wait', 'Chờ các tiến trình con (hoặc cùng thuộc tính) tới trạng thái / bước: tất cả, bất kỳ hoặc đủ n tiến trình'),
];

const insertCardItems = [
  ('send', 'Gửi tin nhắn, thẻ dữ liệu (hoá đơn, sự cố...) hoặc thẻ tiến trình vào nhóm / nhắn riêng'),
  ('card_update', 'Sửa thẻ đã gửi: đổi trạng thái, chuyển bước, báo lỗi'),
];

const insertPeopleItems = [
  ('approval_request', 'Người duyệt bấm Duyệt / Từ chối / Trả lại; mỗi kết quả một nhánh (để trống Từ chối = kết thúc, bị từ chối), nhắc, leo thang nhiều cấp, quá hạn'),
];

/// Loại bước không còn thêm mới (vẫn sửa được khi quy trình đã có). Khi mở quy trình, bước Duyệt kiểu cũ đổi sang
/// Duyệt dạng mới; Thông báo / Gửi thẻ / Gửi tiến trình đổi sang Gửi; Nút trên tin / Chờ bấm nút trên thẻ đổi sang
/// Chờ bấm nút ([FlowDoc.fromJson]).
const supersededTypes = {'approval', 'buttons', 'card_wait', 'notify', 'card_send', 'process_send'};

// ---------------------------------------------------------------------------------------------- tóm tắt

FStep? _stepById(Object? id) => id == null ? null : (editorCtx?.steps ?? const <FStep>[]).where((s) => s.id == '$id').firstOrNull;

String _stepName(FStep s) => s.name.isEmpty ? nodeLook(s.type).$3 : s.name;

/// "tiến trình của «Tạo tiến trình»" / "tiến trình khoá «...»".
String processRefLabel(Object? ref) {
  if (ref is Map && '${ref['process_id'] ?? ''}'.isNotEmpty) return tr('tiến trình mã {0}', ['${ref['process_id']}']);
  if (ref is Map && '${ref['key'] ?? ''}'.isNotEmpty) return tr('tiến trình khoá {0}', ['${ref['key']}']);
  if (ref is Map && '${ref['step'] ?? ''}'.isNotEmpty) {
    final s = _stepById(ref['step']);
    return tr('tiến trình của "{0}"', [s == null ? '${ref['step']}' : _stepName(s)]);
  }
  return tr('chưa chọn tiến trình');
}

/// Các bước cố định của tiến trình mà [ref] trỏ tới (bước Tạo tiến trình được chọn, hoặc bước Tạo tiến trình đầu
/// tiên của quy trình khi tìm theo khoá).
List<Map<String, dynamic>> processStepsFor(Object? ref) {
  final steps = editorCtx?.steps ?? const <FStep>[];
  var src = ref is Map ? _stepById(ref['step']) : null;
  if (src?.type != 'process_create') src = steps.where((s) => s.type == 'process_create').firstOrNull;
  return [for (final x in (src?.node['steps'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
}

/// Thống kê khai báo ở bước Tạo tiến trình (như [processStepsFor]).
List<Map<String, dynamic>> processStatsFor(Object? ref) {
  final steps = editorCtx?.steps ?? const <FStep>[];
  var src = ref is Map ? _stepById(ref['step']) : null;
  if (src?.type != 'process_create') src = steps.where((s) => s.type == 'process_create').firstOrNull;
  return [for (final x in (src?.node['stats'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
}

String _processStepTitle(Object? ref, Object? key) {
  final k = '${key ?? ''}';
  final st = processStepsFor(ref).where((x) => '${x['key']}' == k).firstOrNull;
  if (st != null) return '${st['title']}';
  final i = int.tryParse(k);
  final all = processStepsFor(ref);
  if (i != null && i >= 1 && i <= all.length) return '${all[i - 1]['title']}';
  return k;
}

const processTones = {'gray': 'Xám', 'blue': 'Xanh dương', 'green': 'Xanh lá', 'orange': 'Cam', 'red': 'Đỏ'};
const processResults = {'done': 'Hoàn thành', 'cancelled': 'Huỷ', 'skipped': 'Bỏ qua'};
const _statOps = {'set': 'Đặt', 'add': 'Cộng', 'sub': 'Trừ'};
const _attachKinds = {'file': 'Tệp', 'folder': 'Thư mục', 'link': 'Liên kết'};
const waitWhere = {'card': 'Thẻ tiến trình', 'tasks': 'Tiến trình của tôi', 'both': 'Cả hai'};

/// Nơi thao tác của Chờ bấm nút: thêm nút có sẵn trên thẻ đã gửi và bộ nút gắn lên tin nhắn.
const waitButtonWhere = {'tasks': 'Tiến trình của tôi', 'card': 'Thẻ tiến trình', 'both': 'Cả hai', 'sent': 'Thẻ đã gửi', 'message': 'Tin nhắn'};

/// Nơi thao tác của bước chờ, theo `where: {process? | card? | message?, task?: bool}` (bỏ trống = Việc của tôi):
/// "card" (thẻ tiến trình), "tasks", "both", "sent" (nút trên thẻ đã gửi) hoặc "message" (bộ nút trên tin nhắn).
String waitWhereMode(Map n) {
  final w = n['where'];
  if (w is! Map) return 'tasks';
  if (w['card'] is Map) return 'sent';
  if (w['message'] is Map) return 'message';
  if (w['process'] is! Map) return 'tasks';
  return w['task'] == true ? 'both' : 'card';
}

/// Bước gửi thẻ dữ liệu (Gửi có thẻ, hoặc Gửi thẻ kiểu cũ).
bool sendsCard(FStep s) => s.type == 'card_send' || (s.type == 'send' && s.node['card'] is Map);

/// Bước gửi tin vào nhóm (Gửi tin nhắn có nhóm, Thông báo kiểu cũ có nhóm, Gửi tin kèm tệp).
bool sendsMessage(FStep s) =>
    ((s.type == 'notify' || (s.type == 'send' && s.node['card'] == null && s.node['process'] == null)) && (s.node['channels'] as List? ?? const []).isNotEmpty) ||
    (s.type == 'auto' && s.node['action'] == 'chat_post');

String _cardOf(Object? ref) {
  if (ref is Map && '${ref['post_id'] ?? ''}'.isNotEmpty) return tr('tin {0}', ['${ref['post_id']}']);
  final s = ref is Map ? _stepById(ref['step']) : null;
  return s == null ? tr('chưa chọn thẻ') : tr('thẻ của "{0}"', [_stepName(s)]);
}

String _chanCount(Map n) {
  final ch = (n['channels'] as List? ?? const []).length;
  return ch > 0 ? tr('vào {0} nhóm', [ch]) : '';
}

String _toWho(Map n, AppState app) {
  final to = n['to'] as List? ?? const [];
  return to.isEmpty ? '' : tr('Tới: {0}', [[for (final w in to) whoLabel(w, app)].join(', ')]);
}

/// Tóm tắt trên sơ đồ của bước mới (chuỗi có thể còn "{{...}}": trình soạn đổi thành «tên»).
String nodeSummary(FStep s, AppState app) {
  final n = s.node;
  String join(List<String> parts) => parts.where((x) => x.trim().isNotEmpty).join(' · ');
  switch (s.type) {
    case 'send':
      final card = n['card'] is Map ? n['card'] as Map : null;
      final none = (n['channels'] as List? ?? const []).isEmpty && (n['to'] as List? ?? const []).isEmpty;
      return join([
        if (n['process'] != null)
          tr('Thẻ {0}', [processRefLabel(n['process'])])
        else if (card != null)
          '${card['title'] ?? ''}'.isEmpty ? tr('Thẻ chưa có tiêu đề') : tr('Thẻ “{0}”', ['${card['title']}'])
        else
          '${n['text'] ?? ''}'.trim().isEmpty ? tr('Tin nhắn chưa có nội dung') : '“${n['text']}”',
        _chanCount(n),
        _toWho(n, app),
        if (none) tr('Chưa chọn nơi gửi'),
        if (n['process'] != null && n['sync'] == false) tr('không đồng bộ'),
      ]);
    case 'card_send':
      final card = n['card'] as Map? ?? const {};
      return join([
        '${card['title'] ?? ''}'.isEmpty ? tr('Thẻ chưa có tiêu đề') : '“${card['title']}”',
        _chanCount(n),
        _toWho(n, app),
      ]);
    case 'card_update':
      final patch = n['patch'] as Map? ?? const {};
      return join([
        tr('Sửa {0}', [_cardOf(n['card'])]),
        if ('${n['step'] ?? ''}'.isNotEmpty) tr('sang bước {0}', ['${n['step']}']),
        if ('${n['fail_step'] ?? ''}'.isNotEmpty) tr('báo lỗi bước {0}', ['${n['fail_step']}']),
        if (n['done_all'] == true) tr('xong mọi bước'),
        if (patch['status'] is Map) '${(patch['status'] as Map)['label'] ?? ''}',
      ]);
    case 'card_wait':
      return join([
        tr('Chờ bấm nút trên {0}', [_cardOf(n['card'])]),
        if (n['who'] != null) whoLabel(n['who'], app),
        if ('${n['timeout'] ?? ''}'.isNotEmpty) tr('tối đa {0}', [durLabel('${n['timeout']}')]),
      ]);
    case 'process_create':
      final props = (n['props'] as Map? ?? const {}).length;
      return join([
        '${n['icon'] ?? ''} ${'${n['title'] ?? ''}'.isEmpty ? tr('Chưa đặt tên tiến trình') : n['title']}'.trim(),
        if ('${n['each'] ?? ''}'.trim().isNotEmpty) tr('mỗi phần tử của {0} một tiến trình', ['{{${'${n['each']}'.trim()}}}']),
        tr('{0} bước', [(n['steps'] as List? ?? const []).length]),
        if ((n['stats'] as List? ?? const []).isNotEmpty) tr('{0} thống kê', [(n['stats'] as List).length]),
        if (props > 0) tr('{0} thuộc tính', [props]),
        if (n['parent'] is Map) tr('con của {0}', [processRefLabel(n['parent'])]),
        if ('${n['key'] ?? ''}'.isEmpty) tr('chưa có khoá') else tr('khoá {0}', ['${n['key']}']),
      ]);
    case 'process_props':
      final set = (n['set'] as Map? ?? const {});
      final rm = [for (final x in (n['remove'] as List? ?? const [])) '$x'];
      if (set.isEmpty && rm.isEmpty) return tr('Chưa có thuộc tính nào');
      return [for (final e in set.entries) '${e.key} = ${e.value}', for (final k in rm) '−$k'].join(', ');
    case 'process_remind':
      final at = '${n['at'] ?? ''}'.trim();
      final to = n['to'] is List ? n['to'] as List : [?n['to']];
      return join([
        at.isEmpty ? tr('Chưa đặt mốc') : tr('Lúc {0}', ['{{$at}}']),
        if ('${n['offset'] ?? ''}'.trim().isNotEmpty) offsetLabel('${n['offset']}'),
        if (to.isNotEmpty) tr('Tới: {0}', [[for (final w in to) whoLabel(w, app)].join(', ')]),
        if ('${n['repeat'] ?? ''}'.isNotEmpty) tr('nhắc lại mỗi {0}', [durLabel('${n['repeat']}')]),
      ]);
    case 'process_wait':
      return join([
        processWaitOfLabel(n),
        processWaitUntilLabel(n),
        if ('${n['timeout'] ?? ''}'.isNotEmpty) tr('hạn {0}', [durLabel('${n['timeout']}')]),
      ]);
    case 'process_step':
      return join([
        '${n['step'] ?? ''}'.isEmpty ? tr('Chưa chọn bước') : '→ ${_processStepTitle(n['process'], n['step'])}',
        '${n['status_text'] ?? ''}',
        if ((n['skip'] as List? ?? const []).isNotEmpty) tr('bỏ qua {0} bước', [(n['skip'] as List).length]),
      ]);
    case 'process_stat':
      final items = [for (final x in (n['stats'] as List? ?? const [])) if (x is Map) x];
      if (items.isEmpty) return tr('Chưa có thống kê nào');
      final names = {for (final st in processStatsFor(n['process'])) '${st['key']}': '${st['label'] ?? st['key']}'};
      return [
        for (final x in items)
          '${names['${x['key']}'] ?? x['key']} ${switch ('${x['op'] ?? 'set'}') { 'add' => '+', 'sub' => '−', _ => '=' }} ${x['value'] ?? ''}',
      ].join(', ');
    case 'process_attach':
      final items = [for (final x in (n['items'] as List? ?? const [])) if (x is Map) x];
      return items.isEmpty ? tr('Chưa có mục nào') : [for (final x in items) '${x['name'] ?? ''}'.isEmpty ? tr(_attachKinds['${x['kind']}'] ?? 'Tệp') : '${x['name']}'].join(', ');
    case 'process_fail':
      return join([
        '${n['reason'] ?? ''}'.isEmpty ? tr('Báo lỗi') : tr('Lỗi: {0}', ['${n['reason']}']),
        if ('${n['step'] ?? ''}'.isNotEmpty) tr('ở bước {0}', [_processStepTitle(n['process'], n['step'])]),
      ]);
    case 'process_finish':
      return join([
        tr(processResults['${n['result'] ?? 'done'}'] ?? 'Hoàn thành'),
        if (n['result'] == 'cancelled' && n['cascade'] == true) tr('huỷ cả tiến trình con'),
        '${n['summary'] ?? ''}',
      ]);
    case 'doc_render':
      return join([
        docTemplateLabel(n),
        n['output'] == 'pdf' ? 'PDF' : 'Word',
        if ('${n['file_name'] ?? ''}'.trim().isNotEmpty) '“${n['file_name']}”',
      ]);
    case 'process_send':
      return join([
        _chanCount(n),
        _toWho(n, app),
        if ((n['channels'] as List? ?? const []).isEmpty && (n['to'] as List? ?? const []).isEmpty) tr('Chưa chọn nơi gửi'),
        n['sync'] == false ? tr('không đồng bộ') : tr('tự cập nhật thẻ'),
      ]);
    case 'process_find':
      return '${n['key'] ?? ''}'.isEmpty ? tr('Chưa đặt khoá') : tr('Theo khoá {0}', ['${n['key']}']);
    case 'process_label':
      return join([
        for (final l in (n['add'] as List? ?? const [])) '+$l',
        for (final l in (n['remove'] as List? ?? const [])) '−$l',
      ]).replaceAll(' · ', ', ');
    case 'wait_button' || 'wait_choice':
      final list = (n[s.type == 'wait_button' ? 'buttons' : 'options'] as List? ?? const []).whereType<Map>().toList();
      final mn = (n['min'] as num?)?.toInt(), mx = (n['max'] as num?)?.toInt();
      return join([
        if ('${n['prompt'] ?? ''}'.isNotEmpty) '“${n['prompt']}”',
        s.type == 'wait_button' ? tr('{0} nút', [list.length]) : tr('{0} lựa chọn', [list.length]),
        if (s.type == 'wait_choice' && (mn != null || mx != null)) tr('chọn {0}–{1}', [mn ?? 1, mx ?? list.length]),
        if (n['who'] != null) whoLabel(n['who'], app),
        s.type == 'wait_button' ? tr(waitButtonWhere[waitWhereMode(n)]!) : tr(waitWhere[waitWhereMode(n)] ?? 'Tiến trình của tôi'),
        if (waitWhereMode(n) == 'sent') _cardOf((n['where'] as Map)['card']),
        if ('${n['timeout'] ?? ''}'.isNotEmpty) tr('hạn {0}', [durLabel('${n['timeout']}')]),
      ]);
    case 'wait_close':
      final w = _stepById(n['wait']);
      return join([w == null ? tr('Chưa chọn bước chờ') : tr('Kết thúc chờ của "{0}"', [_stepName(w)]), '${n['reason'] ?? ''}']);
    case 'approval_request':
      final esc = (n['escalate'] as List? ?? const []).length;
      return join([
        if ('${n['title'] ?? ''}'.isNotEmpty) '“${n['title']}”',
        whoLabel(n['approver'], app),
        if (n['mode'] == 'all') tr('tất cả cùng duyệt'),
        if ('${n['due'] ?? ''}'.isNotEmpty) tr('hạn {0}', [durLabel('${n['due']}')]),
        if ('${n['remind'] ?? ''}'.isNotEmpty) tr('nhắc mỗi {0}', [durLabel('${n['remind']}')]),
        if (esc > 0) tr('leo thang {0} cấp', [esc]),
        if ((n['fields'] as List? ?? const []).isNotEmpty) tr('nhập {0} thông tin', [(n['fields'] as List).length]),
        if ((n['return_steps'] as List? ?? const []).isNotEmpty) tr('cho trả lại'),
      ]);
  }
  return '';
}

/// Tạo tài liệu: mẫu là tệp của trường biểu mẫu, tệp đã tải lên (tên đã lưu) hoặc chưa chọn.
String docTemplateLabel(Map n) {
  final t = '${n['template'] ?? ''}'.trim();
  if (t.isEmpty) return tr('Chưa chọn mẫu');
  final m = RegExp(r'^\{\{\s*form\.([A-Za-z0-9_]+)\s*\}\}$').firstMatch(t);
  if (m != null) {
    final f = FlowField.listOf(editorCtx?.doc?.meta['form']).where((f) => f.key == m[1]).firstOrNull;
    return tr('Mẫu: tệp ở "{0}"', [f?.label ?? m[1]!]);
  }
  final name = '${n['template_name'] ?? ''}'.trim();
  return name.isEmpty ? tr('Mẫu: tệp đã tải lên') : tr('Mẫu: {0}', [name]);
}

/// Chờ tiến trình: nhóm tiến trình được chờ.
String processWaitOfLabel(Map n) {
  final of = n['of'] is Map ? n['of'] as Map : const {};
  final parent = of['children_of'];
  if (parent is Map) {
    final s = _stepById(parent['step']);
    return s != null ? tr('Tiến trình con của "{0}"', [_stepName(s)]) : tr('Tiến trình con của {0}', [processRefLabel(parent)]);
  }
  final prop = of['prop'] is Map ? of['prop'] as Map : const {};
  if (prop.isNotEmpty) return tr('Tiến trình có {0}', [[for (final e in prop.entries) '${e.key} = ${e.value}'].join(', ')]);
  return tr('Chưa chọn tiến trình cần chờ');
}

/// Chờ tiến trình: điều kiện ("tất cả hoàn thành", "2 tiến trình tới bước Về kho"...).
String processWaitUntilLabel(Map n) {
  final u = n['until'];
  final who = u is Map && u['count'] != null ? tr('{0} tiến trình', [u['count']]) : (u == 'any' ? tr('bất kỳ tiến trình nào') : tr('tất cả'));
  final step = '${n['step'] ?? ''}'.trim();
  if (step.isNotEmpty) {
    final of = n['of'] is Map ? n['of'] as Map : const {};
    final t = _childStepTitle(of['children_of'], step);
    return tr('{0} tới bước {1}', [who, t]);
  }
  final states = [for (final x in '${n['state'] ?? 'done'}'.split(',')) if (x.trim().isNotEmpty) processStateNames[x.trim()] ?? x.trim()];
  return tr('{0} {1}', [who, [for (final x in states) tr(x).toLowerCase()].join(' / ')]);
}

/// Trạng thái tiến trình → tên.
const processStateNames = {'running': 'Đang chạy', 'failed': 'Lỗi', 'done': 'Hoàn thành', 'cancelled': 'Đã huỷ', 'skipped': 'Bỏ qua'};

/// Tên bước [key] của tiến trình con: bước Tạo tiến trình (con) nào trong quy trình khai báo bước này.
String _childStepTitle(Object? parentRef, String key) {
  for (final s in editorCtx?.steps ?? const <FStep>[]) {
    if (s.type != 'process_create') continue;
    for (final x in (s.node['steps'] as List? ?? const [])) {
      if (x is Map && '${x['key']}' == key && '${x['title'] ?? ''}'.trim().isNotEmpty) return '${x['title']}';
    }
  }
  return key;
}

// ---------------------------------------------------------------------------------------------- nhánh

/// Tên nhánh trên sơ đồ.
String portLabel(FStep s, FPort p) {
  final n = s.node;
  String item(String list, String id) {
    final m = [for (final x in (n[list] as List? ?? const [])) if (x is Map && '${x['id']}' == id) x].firstOrNull;
    final l = '${m?['label'] ?? ''}'.trim();
    return l.isEmpty ? tr('(chưa đặt tên)') : l;
  }

  if (p.key.startsWith('b:')) return item('buttons', p.key.substring(2));
  if (p.key.startsWith('o:')) return item('options', p.key.substring(2));
  return switch (p.key) {
    'always' => tr('Luôn chạy'),
    'approve' => tr('Phê duyệt'),
    'reject' => tr('Từ chối'),
    'escalate' => tr('Leo thang'),
    'ok' => tr('Thành công'),
    'error' => tr('Lỗi'),
    'timeout' => s.type == 'approval_request' ? tr('Quá hạn ({0})', [durLabel('${n['due']}')]) : tr('Quá hạn ({0})', [durLabel('${n['timeout']}')]),
    _ => p.key,
  };
}

/// Màu của nhãn nhánh.
Color portColor(FPort p) => switch (p.key) {
      'always' => const Color(0xFF64748B),
      'approve' => kFlowGreen,
      'reject' => kFlowRed,
      'timeout' => kFlowOrange,
      'escalate' => const Color(0xFF8B5CF6),
      'ok' => kFlowGreen,
      'error' => kFlowRed,
      _ => kGroupPeople,
    };

/// Giải thích ngắn của nhánh (hiện khi chạm nhãn).
String portHint(FStep s, FPort p) => switch (p.key) {
      'always' => tr('Chạy ngay khi bước bắt đầu, song song với lúc chờ. Dùng để cập nhật thẻ / tiến trình hoặc chờ sự kiện khác; đặt bước "Kết thúc chờ" trong nhánh để đóng lượt chờ.'),
      'timeout' => switch (s.type) {
          'approval_request' => tr('Chạy khi hết hạn duyệt mà chưa có quyết định: yêu cầu tự đóng. Không nối bước nào thì chỉ nhắc người duyệt, yêu cầu vẫn mở.'),
          'process_wait' => tr('Chạy khi hết hạn mà các tiến trình chưa tới. Không nối bước nào thì đi nhánh Lỗi (mã timeout) nếu có, không thì đi tiếp.'),
          _ => tr('Chạy khi hết hạn mà chưa có ai thao tác.'),
        },
      'escalate' => tr('Chạy mỗi lần leo thang một cấp (báo người mới, cập nhật thẻ). Yêu cầu vẫn chờ quyết định.'),
      'approve' => tr('Chạy khi yêu cầu được phê duyệt.'),
      'reject' => tr('Chạy khi người duyệt từ chối (bắt buộc ghi lý do). Để trống: luồng kết thúc với trạng thái bị từ chối.'),
      'ok' => tr('Chạy khi bước xong, không lỗi.'),
      'error' => tr('Chạy khi bước lỗi (đã thử lại mà vẫn lỗi, quá thời gian, kết quả sai khuôn...). Trong nhánh dùng «… › Lỗi › Nội dung / Mã» để báo lỗi.'),
      _ => s.type == 'wait_choice' ? tr('Chạy khi lựa chọn này được tích (các lựa chọn đã tích chạy song song).') : tr('Chạy khi người dùng bấm nút này.'),
    };

// ---------------------------------------------------------------------------------------------- cấu hình

/// Ô cấu hình của các bước mới. Sửa trực tiếp [n] (bản sao của node trong bảng cấu hình).
class NodeConfig extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic> n;
  final List<FlowField> form;
  final Map<String, List<String>> roles;
  final List<CondVar> vars;
  const NodeConfig({super.key, required this.app, required this.n, required this.form, required this.roles, required this.vars});
  @override
  State<NodeConfig> createState() => _NodeConfigState();
}

class _NodeConfigState extends State<NodeConfig> {
  Map<String, dynamic> get n => widget.n;
  String get type => '${n['type']}';
  List<FStep> get _steps => editorCtx?.steps ?? const <FStep>[];

  /// Bước đứng trước bước đang soạn (trên mọi đường đi tới nó).
  late final Set<String> _before = () {
    final doc = editorCtx?.doc;
    if (doc == null) return const <String>{};
    final id = '${n['id']}';
    final pre = doc.predecessorsOf(id);
    // Nhánh "Khi luồng bị huỷ": dùng được tiến trình tạo / tìm ở các bước của luồng chính.
    if (doc.listOf(id, doc.cancelSteps) != null) {
      return {...pre, for (final x in FlowDoc(doc.meta, doc.steps).allItems) x.id};
    }
    return pre;
  }();

  @override
  void initState() {
    super.initState();
    // Bước tiến trình mới: tự chọn tiến trình tạo / tìm ở bước gần nhất phía trước.
    final ref = n['process'];
    if (ref is Map && ref.isEmpty && type != 'approval_request' && !type.startsWith('wait_')) {
      final src = _steps.reversed.where((s) => ((s.type == 'process_create' && s.node['each'] == null) || s.type == 'process_find') && _before.contains(s.id)).firstOrNull;
      if (src != null) n['process'] = {'step': src.id};
    }
    // Tạo tài liệu mới: mẫu là trường tệp đầu tiên của biểu mẫu (nếu có).
    final files = [for (final f in widget.form) if (f.type == 'files') f];
    if (type == 'doc_render' && '${n['template'] ?? ''}'.isEmpty && n['template_name'] == null && files.isNotEmpty) n['template'] = '{{form.${files.first.key}}}';
    final of = n['of'];
    if (type == 'process_wait' && of is Map && of['children_of'] is Map && (of['children_of'] as Map).isEmpty) {
      final src = _steps.reversed.where((s) => (s.type == 'process_create' && s.node['each'] == null || s.type == 'process_find') && _before.contains(s.id)).firstOrNull;
      if (src != null) of['children_of'] = {'step': src.id};
    }
    final card = n['card'];
    if ((type == 'card_update' || type == 'card_wait') && card is Map && card.isEmpty) {
      final src = _steps.reversed.where((s) => sendsCard(s) && _before.contains(s.id)).firstOrNull;
      if (src != null) n['card'] = {'step': src.id};
    }
  }

  void _set(VoidCallback f) => setState(f);

  Widget _gap([double h = 14]) => SizedBox(height: h);
  Widget _title(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: Theme.of(context).textTheme.labelLarge));
  Widget _hint(String t, {Color? color}) =>
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(t, style: TextStyle(color: color ?? Pal.of(context).sub, fontSize: 12.5)));

  Widget _tpl(String label, Map<String, dynamic> m, String k, {int lines = 1, Key? key}) => TemplateField(
        key: key,
        label: label,
        raw: '${m[k] ?? ''}',
        vars: widget.vars,
        lines: lines,
        onChanged: (v) => v.trim().isEmpty ? m.remove(k) : m[k] = v,
      );

  Widget _plain(String label, Map<String, dynamic> m, String k, {String? hint, Key? key}) => TextFormField(
        key: key,
        initialValue: '${m[k] ?? ''}',
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
        onChanged: (v) => _set(() => v.trim().isEmpty ? m.remove(k) : m[k] = v.trim()),
      );

  Widget _seg<T>(Map<T, String> options, T value, ValueChanged<T> pick) => SegmentedButton<T>(
        segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(tr(e.value)))],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _set(() => pick(s.first)),
      );

  Widget _due(String key, String label, {List<String> options = const ['1h', '4h', '8h', '24h', '2wd', '3d', '7d']}) {
    final cur = '${n[key] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(label),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(label: Text(tr('Không hạn')), selected: cur.isEmpty, onSelected: (_) => _set(() => n.remove(key))),
        for (final d in {...options, if (cur.isNotEmpty) cur}) ChoiceChip(label: Text(durLabel(d)), selected: cur == d, onSelected: (_) => _set(() => n[key] = d)),
      ]),
    ]);
  }

  Widget _tones(Map<String, dynamic> m, String key) => Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(label: Text(tr('Giữ màu')), selected: m[key] == null, onSelected: (_) => _set(() => m.remove(key))),
        for (final e in processTones.entries)
          ChoiceChip(
            avatar: CircleAvatar(radius: 6, backgroundColor: cardTones[e.key]?.$2 ?? Colors.grey),
            label: Text(tr(e.value)),
            selected: m[key] == e.key,
            onSelected: (_) => _set(() => m[key] = e.key),
          ),
      ]);

  Widget _row(List<Widget> children, VoidCallback onDelete, {Key? key, Widget? lead}) => Container(
        key: key,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 8),
        decoration: BoxDecoration(border: Border.all(color: Pal.of(context).divider), borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ?lead,
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.close_rounded, size: 18), tooltip: tr('Xoá')),
        ]),
      );

  Widget _add(String label, VoidCallback onTap) =>
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _set(onTap), icon: const Icon(Icons.add_rounded), label: Text(label)));

  List<Map<String, dynamic>> _list(Map<String, dynamic> m, String k) {
    final l = [for (final x in (m[k] as List? ?? const [])) if (x is Map) (x is Map<String, dynamic> ? x : Map<String, dynamic>.from(x))];
    m[k] = l;
    return l;
  }

  Map<String, dynamic> _map(Map<String, dynamic> m, String k) {
    final v = m[k];
    final out = v is Map<String, dynamic> ? v : (v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{});
    m[k] = out;
    return out;
  }

  Future<void> _pickChannel(String key) async {
    final app = widget.app;
    final groups = app.channels.values.where((c) => (c.type == 'O' || c.type == 'P') && !c.isProcess).toList()..sort((a, b) => app.channelTitle(a).compareTo(app.channelTitle(b)));
    final id = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(tr('Chọn nhóm')),
        children: [for (final c in groups) SimpleDialogOption(onPressed: () => Navigator.pop(d, c.id), child: Text(app.channelTitle(c)))],
      ),
    );
    if (id != null) _set(() => n[key] = [...(n[key] as List? ?? const []), id]);
  }

  /// Nơi gửi: nhóm (Flow Bot phải ở trong nhóm) và / hoặc nhắn riêng.
  List<Widget> _destinations() {
    final app = widget.app;
    return [
      _title(tr('Gửi vào nhóm')),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final id in [for (final c in (n['channels'] as List? ?? const [])) '$c'])
          InputChip(
            label: Text(app.channels[id] == null ? id : app.channelTitle(app.channels[id]!)),
            onDeleted: () => _set(() => n['channels'] = [for (final c in (n['channels'] as List)) if (c != id) c]),
          ),
        ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Thêm nhóm')), onPressed: () => _pickChannel('channels')),
      ]),
      _hint(tr('Flow Bot phải là thành viên của nhóm.')),
      _gap(),
      _title(tr('Nhắn riêng cho')),
      WhoListField(app: app, roles: widget.roles, value: [...(n['to'] as List? ?? const [])], onChanged: (v) => _set(() => n['to'] = v)),
    ];
  }

  /// Chọn tiến trình: "tạo / tìm ở bước…" hoặc "theo khoá…". [optional]: thêm lựa chọn "Không gắn".
  List<Widget> _process({bool optional = false, String? label, Map<String, dynamic>? holder, String field = 'process', String none = 'Không gắn'}) {
    final h = holder ?? n;
    final ref = h[field];
    final sources = [
      for (final s in _steps)
        if (((s.type == 'process_create' && '${s.node['each'] ?? ''}'.isEmpty) || s.type == 'process_find') && s.id != n['id']) s,
    ];
    final mode = ref is Map && ref.containsKey('process_id') ? 'id' : (ref is Map && ref.containsKey('key') ? 'key' : (ref is Map ? 'step' : 'none'));
    return [
      _title(label ?? tr('Tiến trình')),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in {if (optional) 'none': none, 'step': 'Tạo / tìm ở bước…', 'key': 'Theo khoá…', 'id': 'Theo mã tiến trình…'}.entries)
          ChoiceChip(
            label: Text(tr(e.value)),
            selected: (optional || mode != 'none' ? mode : 'step') == e.key,
            onSelected: (_) => _set(() => switch (e.key) {
                  'none' => h.remove(field),
                  'key' => h[field] = {'key': ''},
                  'id' => h[field] = {'process_id': ''},
                  _ => h[field] = {if (sources.isNotEmpty) 'step': sources.last.id},
                }),
          ),
      ]),
      const SizedBox(height: 8),
      if (mode == 'step' || (!optional && mode == 'none'))
        DropdownButtonFormField<String>(
          key: ValueKey('proc-step-$field-${ref is Map ? ref['step'] : ''}'),
          initialValue: sources.any((s) => ref is Map && s.id == ref['step']) ? '${(ref as Map)['step']}' : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: tr('Tiến trình tạo / tìm ở bước'),
            helperText: sources.isEmpty ? tr('Chưa có bước "Tạo tiến trình" hoặc "Tìm tiến trình". Thêm phía trước, hoặc chọn theo khoá.') : null,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final s in sources)
              DropdownMenuItem(
                value: s.id,
                child: Text('${_stepName(s)}${_before.contains(s.id) || _before.isEmpty ? '' : ' ${tr('(không đứng trước bước này)')}'}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => _set(() => h[field] = {'step': v}),
        ),
      if (mode == 'key')
        TemplateField(
          key: ValueKey('proc-key-$field'),
          label: tr('Khoá tiến trình (vd mã hoá đơn)'),
          raw: '${(ref as Map)['key'] ?? ''}',
          vars: widget.vars,
          lines: 1,
          onChanged: (v) => h[field] = {'key': v},
        ),
      if (mode == 'id') ...[
        TemplateField(
          key: ValueKey('proc-id-$field'),
          label: tr('Mã tiến trình (vd từ biểu mẫu do quy trình cha truyền sang)'),
          raw: '${(ref as Map)['process_id'] ?? ''}',
          vars: widget.vars,
          lines: 1,
          onChanged: (v) => h[field] = {'process_id': v},
        ),
        _hint(tr('Theo mã thì tìm được tiến trình của mọi quy trình.')),
      ],
    ];
  }

  /// Chọn thẻ: thẻ do bước Gửi thẻ trước đó gửi, hoặc id tin trong thông tin của việc. [holder]: nơi ghi (mặc định
  /// `card` của bước).
  Widget _cardRef([Map<String, dynamic>? holder]) {
    final m = holder ?? _map(n, 'card');
    final senders = [for (final s in _steps) if (sendsCard(s) && s.id != n['id']) s];
    final textVars = [for (final v in widget.vars) if (v.type == 'text') v];
    final cur = m['step'] != null ? 'step:${m['step']}' : (m['post_id'] != null ? 'var:${m['post_id']}' : null);
    final items = [
      for (final s in senders) DropdownMenuItem(value: 'step:${s.id}', child: Text(tr('Thẻ của bước "{0}"', [_stepName(s)]), overflow: TextOverflow.ellipsis)),
      for (final v in textVars) DropdownMenuItem(value: 'var:{{${v.path}}}', child: Text(tr('Id tin trong "{0}"', [v.label]), overflow: TextOverflow.ellipsis)),
    ];
    return DropdownButtonFormField<String>(
      initialValue: items.any((i) => i.value == cur) ? cur : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr('Thẻ'),
        helperText: senders.isEmpty ? tr('Chưa có bước "Gửi" thẻ nào. Thêm bước Gửi (Thẻ) phía trước.') : null,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: (v) => _set(() {
        m
          ..remove('step')
          ..remove('post_id');
        if (v == null) return;
        v.startsWith('step:') ? m['step'] = v.substring(5) : m['post_id'] = v.substring(4);
      }),
    );
  }

  /// Chọn tin nhắn: tin do bước gửi vào nhóm trước đó gửi, hoặc id tin trong thông tin của việc.
  Widget _msgRef(Map<String, dynamic> m) {
    final senders = [for (final s in _steps) if (sendsMessage(s) && s.id != n['id']) s];
    final textVars = [for (final v in widget.vars) if (v.type == 'text') v];
    final cur = m['step'] != null ? 'step:${m['step']}' : (m['post_id'] != null ? 'var:${m['post_id']}' : null);
    final items = [
      for (final s in senders) DropdownMenuItem(value: 'step:${s.id}', child: Text(tr('Tin của bước "{0}"', [_stepName(s)]), overflow: TextOverflow.ellipsis)),
      for (final v in textVars) DropdownMenuItem(value: 'var:{{${v.path}}}', child: Text(tr('Id tin trong "{0}"', [v.label]), overflow: TextOverflow.ellipsis)),
    ];
    return DropdownButtonFormField<String>(
      initialValue: items.any((i) => i.value == cur) ? cur : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr('Tin nhắn'),
        helperText: senders.isEmpty ? tr('Chưa có bước nào gửi tin vào nhóm. Thêm bước Gửi (Tin nhắn) có nhóm phía trước.') : null,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: (v) => _set(() {
        m
          ..remove('step')
          ..remove('post_id');
        if (v == null) return;
        v.startsWith('step:') ? m['step'] = v.substring(5) : m['post_id'] = v.substring(4);
      }),
    );
  }

  /// Thẻ gốc của bước Sửa thẻ / Chờ bấm nút (theo bước Gửi thẻ được chọn).
  Map<String, dynamic>? _baseCard([Object? cardRef]) {
    final ref = cardRef ?? n['card'];
    final s = ref is Map ? _stepById(ref['step']) : null;
    final c = s?.node['card'];
    return c is Map ? Map<String, dynamic>.from(c) : null;
  }

  /// Danh sách chữ (nhãn): chip + ô thêm.
  Widget _strings(String key, String label, {String hint = ''}) {
    final list = [for (final x in (n[key] as List? ?? const [])) '$x'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title(label),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in list) InputChip(label: Text(s), onDeleted: () => _set(() => n[key] = [for (final x in list) if (x != s) x])),
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('Thêm')),
          onPressed: () async {
            final ctl = TextEditingController();
            final v = await showDialog<String>(
              context: context,
              builder: (d) => AlertDialog(
                title: Text(label),
                content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (t) => Navigator.pop(d, t)),
                actions: [FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Thêm')))],
              ),
            );
            final t = (v ?? '').trim();
            if (t.isNotEmpty && !list.contains(t)) _set(() => n[key] = [...list, t]);
          },
        ),
      ]),
    ]);
  }

  // ------------------------------------------------------------------ gửi

  /// Nội dung của bước Gửi: "text" (tin nhắn), "card" (thẻ dữ liệu) hoặc "process" (thẻ tiến trình).
  String get _sendMode => n['process'] != null ? 'process' : (n['card'] != null ? 'card' : 'text');

  List<Widget> _send() {
    final mode = _sendMode;
    return [
      _title(tr('Gửi gì')),
      _seg<String>(const {'text': 'Tin nhắn', 'card': 'Thẻ', 'process': 'Tiến trình'}, mode, (v) {
        if (v == mode) return;
        for (final k in const ['text', 'card', 'message', 'process', 'sync']) {
          n.remove(k);
        }
        switch (v) {
          case 'card':
            n['card'] = <String, dynamic>{'v': 1, 'icon': 'task', 'accent': 'blue', 'title': ''};
          case 'process':
            final src = _steps.reversed.where((s) => (s.type == 'process_create' || s.type == 'process_find') && _before.contains(s.id)).firstOrNull;
            n['process'] = <String, dynamic>{if (src != null) 'step': src.id};
          default:
            n['text'] = '';
        }
      }),
      _hint(switch (mode) {
        'card' => tr('Thẻ dữ liệu (hoá đơn, sự cố, công việc nhiều bước...); nút trên thẻ chờ được bằng bước "Chờ bấm nút" (Thẻ đã gửi).'),
        'process' => tr('Thẻ của tiến trình, tự cập nhật khi tiến trình đổi bước, thống kê, nhãn...'),
        _ => tr('Tin nhắn chữ, có nút Mở luồng.'),
      }),
      _gap(),
      if (mode == 'process') ...[..._process(), _gap()],
      ..._destinations(),
      _gap(),
      if (mode == 'text') _tpl(tr('Nội dung'), n, 'text', lines: 3, key: const ValueKey('send-text')),
      if (mode == 'card') ...[
        _title(tr('Nội dung thẻ')),
        CardTemplateEditor(card: _map(n, 'card'), vars: widget.vars),
        _gap(),
        _tpl(tr('Chữ cho app cũ (trống = tự dựng từ thẻ)'), n, 'message', lines: 2),
      ],
      if (mode == 'process') ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Tự cập nhật thẻ khi tiến trình đổi')),
          subtitle: Text(tr('Đổi bước, thống kê, nhãn, tệp... thì thẻ đã gửi tự sửa (giữ ghi chú). Lỗi / hoàn thành có thêm trả lời trong luồng.')),
          value: n['sync'] != false,
          onChanged: (v) => _set(() => v ? n.remove('sync') : n['sync'] = false),
        ),
        _hint(tr('Đã gửi tới cùng nơi thì không gửi lại.')),
      ],
    ];
  }

  // ------------------------------------------------------------------ thẻ

  List<Widget> _cardSend() => [
        ..._destinations(),
        _gap(),
        _title(tr('Nội dung thẻ')),
        CardTemplateEditor(card: _map(n, 'card'), vars: widget.vars),
        _gap(),
        _tpl(tr('Chữ cho app cũ (trống = tự dựng từ thẻ)'), n, 'message', lines: 2),
      ];

  List<Widget> _cardUpdate() {
    final base = _baseCard();
    final rows = [for (final r in (((base?['steps'] as Map?)?['rows']) as List? ?? const [])) if (r is Map) '${r['title'] ?? ''}'];
    Widget stepPick(String key, String label) => rows.isEmpty
        ? _plain(label, n, key, hint: tr('Số thứ tự (vd 2) hoặc tên bước'), key: ValueKey('cu-$key'))
        : DropdownButtonFormField<String>(
            initialValue: rows.contains(n[key]) ? '${n[key]}' : (int.tryParse('${n[key] ?? ''}') != null && int.parse('${n[key]}') <= rows.length ? rows[int.parse('${n[key]}') - 1] : null),
            isExpanded: true,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: '', child: Text(tr('Không đổi'))),
              for (final r in rows) DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => _set(() => (v ?? '').isEmpty ? n.remove(key) : n[key] = v),
          );
    return [
      _cardRef(),
      _gap(),
      stepPick('step', tr('Chuyển sang bước (các bước trước thành xong)')),
      _gap(10),
      stepPick('fail_step', tr('Báo lỗi ở bước')),
      if ('${n['fail_step'] ?? ''}'.isNotEmpty) ...[_gap(8), _tpl(tr('Ghi chú lỗi'), n, 'note')],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Đánh dấu xong mọi bước')),
        value: n['done_all'] == true,
        onChanged: (v) => _set(() => v ? n['done_all'] = true : n.remove('done_all')),
      ),
      _title(tr('Sửa nội dung thẻ (ô trống = giữ nguyên)')),
      CardTemplateEditor(card: _map(n, 'patch'), vars: widget.vars, partial: true, base: base, onChanged: () => setState(() {})),
      _gap(),
      _tpl(tr('Trả lời ngắn trong luồng thẻ (để mọi người nhận thông báo)'), n, 'notify', lines: 2),
    ];
  }

  List<Widget> _cardWait() {
    final base = _baseCard();
    final ids = [for (final a in (base?['actions'] as List? ?? const [])) if (a is Map && a['id'] != null) a];
    final sel = [for (final x in (n['ids'] as List? ?? const [])) '$x'];
    return [
      _hint(tr('Bước cũ: quy trình mới nên dùng "Chờ bấm nút" (mỗi nút một nhánh).'), color: kFlowOrange),
      _gap(8),
      _cardRef(),
      _gap(),
      if (ids.isNotEmpty) ...[
        _title(tr('Chỉ nhận các nút (không chọn = mọi nút)')),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final a in ids)
            FilterChip(
              label: Text('${a['label'] ?? a['id']}'),
              selected: sel.contains('${a['id']}'),
              onSelected: (v) => _set(() {
                final next = v ? [...sel, '${a['id']}'] : [for (final x in sel) if (x != '${a['id']}') x];
                next.isEmpty ? n.remove('ids') : n['ids'] = next;
              }),
            ),
        ]),
        _gap(),
      ],
      WhoField(app: widget.app, roles: widget.roles, label: tr('Ai được bấm'), value: n['who'], onChanged: (w) => _set(() => n['who'] = w), onClear: () => _set(() => n.remove('who'))),
      _gap(),
      _due('timeout', tr('Chờ tối đa')),
    ];
  }

  // ------------------------------------------------------------------ tiến trình

  List<Widget> _processCreate() {
    final steps = _list(n, 'steps');
    final stats = _list(n, 'stats');
    return [
      _tpl(tr('Khoá (duy nhất trong quy trình, vd mã hoá đơn)'), n, 'key'),
      _hint(tr('Khoá đã có thì dùng lại tiến trình cũ, không tạo mới. Muốn rẽ nhánh thì dùng «… › Đã có từ trước».')),
      _gap(),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final e = await pickFlowIcon(context, current: '${n['icon'] ?? ''}', keywords: true);
            if (e != null) _set(() => n['icon'] = e);
          },
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: Pal.of(context).divider), borderRadius: BorderRadius.circular(10)),
            child: flowIconView('${n['icon'] ?? ''}'.isEmpty ? '📋' : '${n['icon']}', color: Pal.of(context).accentText),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _tpl(tr('Tên tiến trình (vd Hoá đơn 2154 · Cty Hoàng Long)'), n, 'title')),
      ]),
      _gap(),
      _title(tr('Các bước (cố định lúc tạo; kéo để đổi thứ tự)')),
      _hint(tr('Hạn bước: quá hạn thì thẻ chuyển cam, báo người được chọn một lần; "3wd" = 3 ngày làm việc.')),
      const SizedBox(height: 4),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: (a, b) => _set(() => steps.insert(b, steps.removeAt(a))),
        children: [
          for (final (i, st) in steps.indexed)
            _row([
              Row(children: [
                SizedBox(width: 92, child: _plain(tr('Mã'), st, 'key', key: ValueKey('k-${identityHashCode(st)}'))),
                const SizedBox(width: 8),
                Expanded(child: _plain(tr('Tên bước'), st, 'title', key: ValueKey('t-${identityHashCode(st)}'))),
              ]),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 92, child: _plain(tr('Hạn bước'), st, 'sla', hint: '8h, 2d, 3wd', key: ValueKey('sla-${identityHashCode(st)}'))),
                const SizedBox(width: 8),
                Expanded(
                  child: WhoField(
                    app: widget.app,
                    roles: widget.roles,
                    label: tr('Báo quá hạn cho'),
                    value: st['escalate_to'] is List ? (st['escalate_to'] as List).firstOrNull : st['escalate_to'],
                    onChanged: (w) => _set(() => st['escalate_to'] = w),
                    onClear: () => _set(() => st.remove('escalate_to')),
                  ),
                ),
              ]),
            ], () => _set(() => steps.remove(st)),
                key: ObjectKey(st),
                lead: ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.only(top: 8, right: 6), child: Icon(Icons.drag_indicator_rounded, size: 20)))),
        ],
      ),
      _add(tr('Thêm bước'), () => steps.add({'key': 'b${steps.length + 1}', 'title': ''})),
      _gap(),
      _title(tr('Thống kê')),
      for (final st in stats)
        _row([
          Row(children: [
            Expanded(child: _plain(tr('Tên hiện'), st, 'label', key: ValueKey('l-${identityHashCode(st)}'))),
            const SizedBox(width: 8),
            SizedBox(width: 110, child: _plain(tr('Mã'), st, 'key', key: ValueKey('k-${identityHashCode(st)}'))),
          ]),
          const SizedBox(height: 6),
          _seg<String>({'number': 'Số', 'text': 'Chữ'}, '${st['type'] ?? 'number'}', (v) => st['type'] = v),
          const SizedBox(height: 6),
          TemplateField(
            key: ValueKey('v-${identityHashCode(st)}'),
            label: tr('Giá trị đầu'),
            raw: '${st['value'] ?? ''}',
            vars: widget.vars,
            lines: 1,
            onChanged: (v) {
              final t = v.trim();
              t.isEmpty ? st.remove('value') : st['value'] = st['type'] != 'text' && num.tryParse(t) != null ? num.parse(t) : v;
            },
          ),
        ], () => _set(() => stats.remove(st)), key: ObjectKey(st)),
      _add(tr('Thêm thống kê'), () => stats.add({'key': 's${stats.length + 1}', 'label': '', 'type': 'number', 'value': 0})),
      _hint(tr('Thống kê số cộng / trừ được và tính tổng trong báo cáo; thống kê chữ hiện thành dòng thông tin trên thẻ.')),
      _gap(),
      _strings('labels', tr('Nhãn ban đầu'), hint: tr('Vd KLTM')),
      _gap(),
      _tpl(tr('Dòng trạng thái (vd Chờ kế toán ký)'), n, 'status_text'),
      _gap(8),
      _tones(n, 'tone'),
      _gap(),
      _title(tr('Thuộc tính')),
      ..._propsEditor(n, 'props', link: true),
      _hint(tr('Thuộc tính tìm được theo giá trị (vd số PO), dùng trong biểu thức «Tiến trình › Thuộc tính». Bật "Liên kết": tiến trình của quy trình khác có cùng giá trị hiện ở mục "Liên quan".')),
      if ((n['props'] as Map? ?? const {}).isNotEmpty) ...[_gap(), ..._propFields()],
      _gap(),
      ..._process(optional: true, label: tr('Tiến trình cha'), field: 'parent', none: 'Không có'),
      _hint(tr('Tiến trình cha thấy tiến trình này trong mục "Liên quan" và chờ được bằng bước "Chờ tiến trình".')),
      _gap(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Tạo nhiều (mỗi phần tử của danh sách một tiến trình)')),
        subtitle: Text(tr('Vd mỗi dòng của bảng container một tiến trình. Trong khoá, tên, thuộc tính dùng «Phần tử đang tạo › …» và «Số thứ tự».')),
        value: n.containsKey('each'),
        onChanged: (v) => _set(() {
          if (!v) {
            n.remove('each');
            return;
          }
          final table = widget.form.where((f) => f.type == 'table').firstOrNull;
          n['each'] = table == null ? '' : 'form.${table.key}';
        }),
      ),
      if (n.containsKey('each')) ...[
        ExprField(
          key: const ValueKey('pc-each'),
          label: tr('Danh sách (vd bảng trong biểu mẫu)'),
          value: '${n['each'] ?? ''}',
          vars: widget.vars,
          lines: 1,
          onChanged: (v) => n['each'] = v.trim(),
        ),
        if (!RegExp(r'\{\{\s*(item\.|index\b)').hasMatch('${n['key'] ?? ''}'))
          _hint(tr('Khoá phải chứa «Phần tử đang tạo › …» hoặc «Số thứ tự» để mỗi phần tử một khoá.'), color: kFlowRed),
      ],
    ];
  }

  /// Sửa bảng khoá → mẫu `holder[key]` (thuộc tính). [link]: thêm nút "Liên kết" (ghi `props_link` của [holder]).
  int _propGen = 0;
  List<Widget> _propsEditor(Map<String, dynamic> holder, String key, {bool link = false, String? addLabel}) {
    final cur = holder[key];
    final m = cur is Map<String, dynamic> ? cur : (cur is Map ? Map<String, dynamic>.from(cur) : <String, dynamic>{});
    if (cur is Map && cur is! Map<String, dynamic>) holder[key] = m;
    final links = [for (final x in (holder['props_link'] as List? ?? const [])) '$x'];
    final entries = m.entries.toList();
    void rename(int i, String to) {
      final old = entries[i].key;
      final t = to.trim();
      if (t == old || t.isEmpty || m.containsKey(t)) return;
      final next = <String, dynamic>{for (final e in m.entries) e.key == old ? t : e.key: e.value};
      m
        ..clear()
        ..addAll(next);
      if (link && links.contains(old)) holder['props_link'] = [for (final x in links) x == old ? t : x];
      for (final f in (holder['fields'] as List? ?? const [])) {
        if (f is Map && f['prop'] == old) f['prop'] = t;
      }
    }

    return [
      for (final (i, e) in entries.indexed)
        _row([
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 120,
              child: TextFormField(
                key: ValueKey('pk-$key-$_propGen-$i'),
                initialValue: e.key,
                decoration: InputDecoration(labelText: tr('Khoá'), isDense: true, border: const OutlineInputBorder()),
                onChanged: (v) => rename(i, v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_')),
                onFieldSubmitted: (_) => _set(() => _propGen++),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TemplateField(
                key: ValueKey('pv-$key-$_propGen-$i'),
                label: tr('Giá trị'),
                raw: '${e.value ?? ''}',
                vars: widget.vars,
                lines: 1,
                onChanged: (v) => m[entries[i].key] = v,
              ),
            ),
          ]),
          if (link)
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                avatar: const Icon(Icons.link_rounded, size: 16),
                label: Text(tr('Liên kết')),
                selected: links.contains(e.key),
                onSelected: (v) => _set(() {
                  final next = v ? [...links, e.key] : [for (final x in links) if (x != e.key) x];
                  next.isEmpty ? holder.remove('props_link') : holder['props_link'] = next;
                }),
              ),
            ),
        ], () => _set(() {
          m.remove(e.key);
          _propGen++;
          if (link) {
            final next = [for (final x in links) if (x != e.key) x];
            next.isEmpty ? holder.remove('props_link') : holder['props_link'] = next;
            final f = [for (final x in (holder['fields'] as List? ?? const [])) if (x is Map && x['prop'] != e.key) x];
            f.isEmpty ? holder.remove('fields') : holder['fields'] = f;
          }
          if (m.isEmpty) holder.remove(key);
        }), key: ValueKey('pr-$key-$_propGen-$i')),
      _add(addLabel ?? tr('Thêm thuộc tính'), () {
        var i = m.length + 1;
        while (m.containsKey('tt_$i')) {
          i++;
        }
        m['tt_$i'] = '';
        holder[key] = m;
        _propGen++;
      }),
    ];
  }

  /// Dòng trên thẻ tiến trình lấy từ thuộc tính: [{prop, label}].
  List<Widget> _propFields() {
    final keys = [for (final k in (n['props'] as Map? ?? const {}).keys) '$k'];
    final fields = _list(n, 'fields');
    if (fields.isEmpty) n.remove('fields');
    return [
      _title(tr('Dòng trên thẻ (lấy từ thuộc tính)')),
      for (final f in fields)
        _row([
          DropdownButtonFormField<String>(
            initialValue: keys.contains(f['prop']) ? '${f['prop']}' : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Thuộc tính'), isDense: true, border: const OutlineInputBorder()),
            items: [for (final k in keys) DropdownMenuItem(value: k, child: Text(k))],
            onChanged: (v) => _set(() => f['prop'] = v),
          ),
          const SizedBox(height: 6),
          _plain(tr('Nhãn hiện (vd Số PO)'), f, 'label', key: ValueKey('pf-${identityHashCode(f)}')),
        ], () => _set(() {
          fields.remove(f);
          if (fields.isEmpty) n.remove('fields');
        }), key: ObjectKey(f)),
      _add(tr('Thêm dòng'), () {
        n['fields'] = fields;
        fields.add({'prop': keys.firstOrNull ?? '', 'label': ''});
      }),
    ];
  }

  List<Widget> _processProps() {
    final rm = [for (final x in (n['remove'] as List? ?? const [])) '$x'];
    return [
      ..._process(),
      _gap(),
      _title(tr('Gán thuộc tính')),
      ..._propsEditor(n, 'set'),
      _gap(),
      _strings('remove', tr('Bỏ thuộc tính'), hint: tr('Khoá thuộc tính, vd eta')),
      if (rm.isEmpty && (n['set'] as Map? ?? const {}).isEmpty) _hint(tr('Chưa có thuộc tính cần gán / bỏ.'), color: kFlowRed),
      _hint(tr('Thuộc tính đổi thì các bước "Chờ tiến trình" đang chờ theo thuộc tính này tự xét lại.')),
    ];
  }

  /// Nhắc theo mốc: biến chỉ của biểu mẫu, biến luồng, người tạo, tiến trình (mốc tính lại khi tiến trình đổi).
  List<CondVar> get _remindVars => [
        for (final v in widget.vars)
          if (v.path.startsWith('form.') || v.path.startsWith('vars.') || v.path.startsWith('requester') || v.path.startsWith('process.')) v,
      ];

  List<Widget> _processRemind() {
    final vars = _remindVars;
    final marks = [for (final v in vars) if (v.type == 'date' || v.path.startsWith('process.props.')) v];
    final to = n['to'] is List ? [...n['to'] as List] : [?n['to']];
    final at = '${n['at'] ?? ''}';
    return [
      ..._process(),
      _gap(),
      DropdownButtonFormField<String>(
        initialValue: marks.any((v) => v.path == at) ? at : (at.isEmpty ? null : '\u0000'),
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Mốc'), border: const OutlineInputBorder()),
        items: [
          for (final v in marks) DropdownMenuItem(value: v.path, child: Text(v.label, overflow: TextOverflow.ellipsis)),
          if (at.isNotEmpty && !marks.any((v) => v.path == at)) DropdownMenuItem(value: '\u0000', child: Text(tr('Biểu thức riêng'))),
        ],
        onChanged: (v) => _set(() => v == null || v == '\u0000' ? null : n['at'] = v),
      ),
      const SizedBox(height: 8),
      ExprField(key: ValueKey('rm-at-$at'), label: tr('Hoặc biểu thức mốc (ngày / giờ)'), value: at, vars: vars, lines: 1, onChanged: (v) => n['at'] = v.trim()),
      _gap(),
      ...offsetField(context, n, () => _set(() {})),
      _gap(),
      _title(tr('Nhắc ai')),
      WhoListField(app: widget.app, roles: widget.roles, value: to, onChanged: (v) => _set(() => n['to'] = v)),
      _gap(),
      TemplateField(key: const ValueKey('rm-msg'), label: tr('Nội dung nhắc'), raw: '${n['message'] ?? ''}', vars: vars, lines: 2, onChanged: (v) => n['message'] = v),
      _gap(),
      _due('repeat', tr('Nhắc lại mỗi (tới khi tiến trình xong)'), options: const ['4h', '1d', '2d', '7d']),
      _hint(tr('Bước đi tiếp ngay. Mốc đổi (vd ETA mới) thì lịch nhắc tự dời; tiến trình xong / huỷ thì thôi nhắc. Mốc trống thì chờ tới khi có.')),
    ];
  }

  List<Widget> _processWait() {
    final of = _map(n, 'of');
    final byProp = of['prop'] is Map;
    final u = n['until'];
    final until = u is Map ? 'count' : (u == 'any' ? 'any' : 'all');
    final byStep = n.containsKey('step');
    final states = [for (final x in '${n['state'] ?? 'done'}'.split(',')) if (x.trim().isNotEmpty) x.trim()];
    // Bước của tiến trình con: các bước khai báo ở bước Tạo tiến trình (có tiến trình cha hoặc tạo nhiều).
    final childSteps = <String, String>{
      for (final s in _steps)
        if (s.type == 'process_create' && (s.node['parent'] != null || s.node['each'] != null))
          for (final x in (s.node['steps'] as List? ?? const []))
            if (x is Map) '${x['key']}': '${x['title'] ?? x['key']}',
    };
    final flows = editorCtx?.flows ?? const <Map<String, dynamic>>[];
    return [
      _title(tr('Chờ những tiến trình nào')),
      _seg<String>({'children': 'Tiến trình con', 'prop': 'Cùng thuộc tính'}, byProp ? 'prop' : 'children', (v) {
        of.clear();
        v == 'prop' ? of['prop'] = <String, dynamic>{} : of['children_of'] = <String, dynamic>{};
      }),
      _gap(8),
      if (!byProp) ...[
        ..._process(label: tr('Tiến trình con của'), holder: of, field: 'children_of'),
      ] else ...[
        ..._propsEditor(of, 'prop'),
        _gap(8),
        DropdownButtonFormField<String>(
          initialValue: flows.any((f) => f['id'] == of['flow']) ? '${of['flow']}' : '',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Chỉ tiến trình của quy trình'), border: const OutlineInputBorder()),
          items: [
            DropdownMenuItem(value: '', child: Text(tr('Mọi quy trình'))),
            for (final f in flows) DropdownMenuItem(value: '${f['id']}', child: Text('${f['icon'] ?? ''} ${f['name'] ?? ''}'.trim(), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => _set(() => (v ?? '').isEmpty ? of.remove('flow') : of['flow'] = v),
        ),
      ],
      _gap(),
      _title(tr('Đi tiếp khi')),
      _seg<String>({'all': 'Tất cả', 'any': 'Bất kỳ', 'count': 'Đủ số lượng'}, until, (v) => switch (v) {
            'any' => n['until'] = 'any',
            'count' => n['until'] = {'count': 2},
            _ => n['until'] = 'all',
          }),
      if (until == 'count') ...[
        _gap(8),
        SizedBox(
          width: 160,
          child: TextFormField(
            initialValue: '${(u as Map)['count'] ?? ''}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Số tiến trình'), isDense: true, border: const OutlineInputBorder()),
            onChanged: (t) => n['until'] = {'count': int.tryParse(t.trim()) ?? 1},
          ),
        ),
      ],
      if (until == 'all') _hint(tr('Chưa có tiến trình nào thì vẫn chờ (tiến trình tạo sau cũng được tính).')),
      _gap(),
      _seg<String>({'state': 'Tới trạng thái', 'step': 'Tới bước'}, byStep ? 'step' : 'state', (v) {
        if (v == 'step') {
          n.remove('state');
          n['step'] = childSteps.keys.firstOrNull ?? '';
        } else {
          n.remove('step');
          n['state'] = 'done';
        }
      }),
      _gap(8),
      if (!byStep)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in processStateNames.entries)
            FilterChip(
              label: Text(tr(e.value)),
              selected: states.contains(e.key),
              onSelected: (v) => _set(() {
                final next = v ? [...states, e.key] : [for (final x in states) if (x != e.key) x];
                n['state'] = (next.isEmpty ? ['done'] : next).join(',');
              }),
            ),
        ])
      else if (childSteps.isEmpty)
        _plain(tr('Mã bước của tiến trình'), n, 'step', key: const ValueKey('pw-step'))
      else
        DropdownButtonFormField<String>(
          initialValue: childSteps.containsKey(n['step']) ? '${n['step']}' : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Bước của tiến trình'), border: const OutlineInputBorder()),
          items: [for (final e in childSteps.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _set(() => n['step'] = v),
        ),
      if (byStep) _hint(tr('Tính là tới khi bước đang làm, đã xong, hoặc tiến trình đã hoàn thành.')),
      _gap(),
      _due('timeout', tr('Hạn chờ (có hạn thì thêm nhánh "Quá hạn")'), options: const ['1d', '3d', '7d', '14d', '30d']),
      _gap(),
      ..._process(optional: true, label: tr('Hiện "Đang chờ x/y" trên tiến trình'), field: 'process', none: 'Mặc định'),
      _hint(tr('Mặc định: tiến trình cha (khi chờ tiến trình con).')),
    ];
  }

  bool _uploading = false;

  Future<void> _uploadTemplate() async {
    final api = editorCtx?.api;
    if (api == null) return;
    final picked = await pickFilesOrReport(context);
    final p = picked.where((x) => x.path != null).firstOrNull;
    if (p == null) return;
    setState(() => _uploading = true);
    try {
      final info = await api.upload(p.name, await File(p.path!).readAsBytes());
      _set(() {
        n['template'] = '${info['id'] ?? ''}';
        n['template_name'] = '${info['name'] ?? p.name}';
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không tải được {0}: {1}', [p.name, '$e']))));
    }
    if (mounted) setState(() => _uploading = false);
  }

  List<Widget> _docRender() {
    final fileFields = [for (final f in widget.form) if (f.type == 'files') f];
    final t = '${n['template'] ?? ''}'.trim();
    final fieldKey = RegExp(r'^\{\{\s*form\.([A-Za-z0-9_]+)\s*\}\}$').firstMatch(t)?[1];
    final mode = fieldKey != null || (t.isEmpty && n['template_name'] == null && fileFields.isNotEmpty) ? 'field' : 'file';
    final data = n['data'] is Map ? n['data'] as Map : null;
    return [
      _title(tr('Mẫu Word (.docx)')),
      _seg<String>({'field': 'Tệp trong biểu mẫu', 'file': 'Tải mẫu lên'}, mode, (v) {
        n.remove('template_name');
        n['template'] = v == 'field' && fileFields.isNotEmpty ? '{{form.${fileFields.first.key}}}' : '';
      }),
      _gap(8),
      if (mode == 'field')
        DropdownButtonFormField<String>(
          initialValue: fileFields.any((f) => f.key == fieldKey) ? fieldKey : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: tr('Trường tệp của biểu mẫu'),
            helperText: fileFields.isEmpty ? tr('Biểu mẫu chưa có trường kiểu Tệp. Thêm trường, hoặc tải mẫu lên.') : null,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
          items: [for (final f in fileFields) DropdownMenuItem(value: f.key, child: Text(f.label, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => _set(() => n['template'] = '{{form.$v}}'),
        )
      else ...[
        Row(children: [
          Expanded(
            child: Text(
              t.isEmpty ? tr('Chưa có mẫu') : '${n['template_name'] ?? ''}'.trim().isEmpty ? tr('Đã có mẫu') : '${n['template_name']}',
              style: TextStyle(fontWeight: FontWeight.w600, color: t.isEmpty ? Pal.of(context).sub : Pal.of(context).text),
            ),
          ),
          if (_uploading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          TextButton.icon(onPressed: _uploading ? null : _uploadTemplate, icon: const Icon(Icons.upload_file_rounded), label: Text(t.isEmpty ? tr('Tải mẫu lên') : tr('Đổi mẫu'))),
        ]),
      ],
      _hint(tr('Mẫu Word có {{form.x}}; lặp dòng bảng: đặt {{#each form.hang}} … {{/each}} trong cùng một dòng, dùng {{item.cot}}, {{loop.index}}. PDF cần máy chuyển PDF trên máy chủ.')),
      _gap(),
      _title(tr('Định dạng')),
      _seg<String>({'docx': 'Word (.docx)', 'pdf': 'PDF'}, n['output'] == 'pdf' ? 'pdf' : 'docx', (v) => n['output'] = v),
      _gap(),
      _tpl(tr('Tên tệp (vd Hợp đồng {{form.so_hd}})'), n, 'file_name'),
      _gap(),
      ..._process(optional: true, label: tr('Gắn vào tiến trình'), none: 'Tiến trình chính'),
      _hint(tr('Mặc định gắn vào tiến trình chính của luồng (bước Tạo / Tìm tiến trình đầu tiên).')),
      _gap(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Thêm dữ liệu riêng cho mẫu')),
        subtitle: Text(tr('Mẫu dùng được mọi thông tin của luồng; thêm khoá riêng nếu cần giá trị tính sẵn cho mẫu.')),
        value: data != null,
        onChanged: (v) => _set(() => v ? n['data'] = <String, dynamic>{} : n.remove('data')),
      ),
      if (data != null) ..._propsEditor(n, 'data', addLabel: tr('Thêm khoá')),
    ];
  }

  Widget _processStepPick(String key, String label, {bool allowCurrent = false}) {
    final steps = processStepsFor(n['process']);
    if (steps.isEmpty) return _plain(label, n, key, hint: tr('Mã bước hoặc số thứ tự (vd 2)'), key: ValueKey('ps-$key'));
    final cur = '${n[key] ?? ''}';
    return DropdownButtonFormField<String>(
      initialValue: steps.any((s) => '${s['key']}' == cur) ? cur : (allowCurrent ? '' : null),
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        if (allowCurrent) DropdownMenuItem(value: '', child: Text(tr('Bước hiện tại'))),
        for (final (i, s) in steps.indexed) DropdownMenuItem(value: '${s['key']}', child: Text('${i + 1}. ${s['title'] ?? s['key']}', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => _set(() => (v ?? '').isEmpty ? n.remove(key) : n[key] = v),
    );
  }

  List<Widget> _processStep() {
    final steps = processStepsFor(n['process']);
    final skip = [for (final x in (n['skip'] as List? ?? const [])) '$x'];
    return [
      ..._process(),
      _gap(),
      _processStepPick('step', tr('Bước hiện tại mới')),
      _hint(tr('Các bước trước thành xong (trừ bước bỏ qua). Tiến trình đang lỗi thì hết lỗi.')),
      if (steps.isNotEmpty) ...[
        _gap(),
        _title(tr('Bỏ qua các bước')),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in steps)
            FilterChip(
              label: Text('${s['title'] ?? s['key']}'),
              selected: skip.contains('${s['key']}'),
              onSelected: (v) => _set(() {
                final next = v ? [...skip, '${s['key']}'] : [for (final x in skip) if (x != '${s['key']}') x];
                next.isEmpty ? n.remove('skip') : n['skip'] = next;
              }),
            ),
        ]),
      ],
      _gap(),
      _tpl(tr('Dòng trạng thái (vd Chờ kế toán ký)'), n, 'status_text'),
      _gap(8),
      _tones(n, 'tone'),
    ];
  }

  List<Widget> _processStat() {
    final items = _list(n, 'stats');
    final known = processStatsFor(n['process']);
    return [
      ..._process(),
      _gap(),
      _title(tr('Thay đổi thống kê')),
      for (final it in items)
        _row([
          if (known.isEmpty)
            _plain(tr('Mã thống kê'), it, 'key', key: ValueKey('sk-${identityHashCode(it)}'))
          else
            DropdownButtonFormField<String>(
              initialValue: known.any((k) => '${k['key']}' == it['key']) ? '${it['key']}' : null,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(labelText: tr('Thống kê'), isDense: true, border: const OutlineInputBorder()),
              items: [for (final k in known) DropdownMenuItem(value: '${k['key']}', child: Text('${k['label'] ?? k['key']}'))],
              onChanged: (v) => _set(() {
                it['key'] = v;
                if (known.firstWhere((k) => k['key'] == v)['type'] == 'text') it['op'] = 'set';
              }),
            ),
          const SizedBox(height: 6),
          if (known.where((k) => k['key'] == it['key']).firstOrNull?['type'] != 'text') _seg<String>(_statOps, '${it['op'] ?? 'set'}', (v) => it['op'] = v),
          const SizedBox(height: 6),
          _tpl(tr('Giá trị'), it, 'value', key: ValueKey('sv-${identityHashCode(it)}')),
        ], () => _set(() => items.remove(it)), key: ObjectKey(it)),
      _add(tr('Thêm thay đổi'), () => items.add({'key': known.firstOrNull?['key'] ?? '', 'op': 'add', 'value': '1'})),
      _hint(tr('Cộng / trừ chỉ dùng cho thống kê kiểu số.')),
    ];
  }

  List<Widget> _processAttach() {
    final items = _list(n, 'items');
    return [
      ..._process(),
      _gap(),
      _title(tr('Đính kèm')),
      for (final it in items)
        _row([
          _seg<String>(_attachKinds, '${it['kind'] ?? 'file'}', (v) => it['kind'] = v),
          const SizedBox(height: 6),
          _tpl(tr('Tên hiện (vd Chứng từ LinkQ)'), it, 'name', key: ValueKey('an-${identityHashCode(it)}')),
          const SizedBox(height: 6),
          _tpl(
            switch ('${it['kind'] ?? 'file'}') { 'link' => tr('Liên kết (https://…)'), 'folder' => tr('Đường dẫn thư mục'), _ => tr('Đường dẫn tải tệp') },
            it,
            'url',
            key: ValueKey('au-${identityHashCode(it)}'),
          ),
        ], () => _set(() => items.remove(it)), key: ObjectKey(it)),
      _add(tr('Thêm tệp'), () => items.add({'kind': 'file', 'name': '', 'url': ''})),
      _add(tr('Thêm liên kết'), () => items.add({'kind': 'link', 'name': '', 'url': ''})),
      _hint(tr('Liên kết hiện thành nút trên thẻ tiến trình. Tệp chỉ tải từ địa chỉ được quản trị cho phép.')),
    ];
  }

  List<Widget> _processFail() => [
        ..._process(),
        _gap(),
        _tpl(tr('Lý do lỗi'), n, 'reason', lines: 2),
        _gap(),
        _processStepPick('step', tr('Bước bị lỗi'), allowCurrent: true),
      ];

  List<Widget> _processFinish() => [
        ..._process(),
        _gap(),
        _title(tr('Kết quả')),
        _seg<String>(processResults, '${n['result'] ?? 'done'}', (v) {
          n['result'] = v;
          if (v != 'cancelled') n.remove('cascade');
        }),
        _hint(tr('Các bước chưa làm thành "bỏ qua".')),
        if (n['result'] == 'cancelled')
          SwitchListTile(
            key: const ValueKey('pf-cascade'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Huỷ cả tiến trình con')),
            subtitle: Text(tr('Huỷ mọi tiến trình con, cháu chưa xong và dừng các luồng đã tạo ra chúng (các luồng đó chạy nhánh "Khi luồng bị huỷ").')),
            value: n['cascade'] == true,
            onChanged: (v) => _set(() => v ? n['cascade'] = true : n.remove('cascade')),
          ),
        _gap(),
        _tpl(tr('Tóm tắt'), n, 'summary', lines: 2),
      ];

  List<Widget> _processSend() => [
        ..._process(),
        _gap(),
        ..._destinations(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Tự cập nhật thẻ khi tiến trình đổi')),
          subtitle: Text(tr('Đổi bước, thống kê, nhãn, tệp... thì thẻ đã gửi tự sửa (giữ ghi chú). Lỗi / hoàn thành có thêm trả lời trong luồng.')),
          value: n['sync'] != false,
          onChanged: (v) => _set(() => n['sync'] = v),
        ),
        _hint(tr('Đã gửi tới cùng nơi thì không gửi lại.')),
      ];

  List<Widget> _processFind() => [
        _tpl(tr('Khoá tiến trình (vd mã hoá đơn)'), n, 'key'),
        _hint(tr('Kết quả: «… › Tìm thấy», «… › Mã tiến trình», «… › Trạng thái tiến trình», «… › Bước hiện tại». Bước sau chọn tiến trình "tạo / tìm ở bước" này.')),
      ];

  List<Widget> _processLabel() => [
        ..._process(),
        _gap(),
        _strings('add', tr('Gắn nhãn'), hint: tr('Vd Nghi trùng')),
        _gap(),
        _strings('remove', tr('Bỏ nhãn')),
      ];

  // ------------------------------------------------------------------ chờ người dùng

  /// Đổi nơi thao tác. where: {process: tiến trình (thẻ), task: true (Việc của tôi)} / {card: thẻ đã gửi} /
  /// {message: tin nhắn}; chỉ Việc của tôi thì bỏ trống.
  void _setWhere(String v) {
    final old = n['where'] is Map ? n['where'] as Map : const {};
    switch (v) {
      case 'tasks':
        n.remove('where');
      case 'sent':
        final src = _steps.reversed.where((s) => sendsCard(s) && _before.contains(s.id)).firstOrNull;
        n['where'] = <String, dynamic>{'card': old['card'] is Map ? old['card'] : <String, dynamic>{if (src != null) 'step': src.id}, if (old['task'] == true) 'task': true};
      case 'message':
        final src = _steps.reversed.where((s) => sendsMessage(s) && _before.contains(s.id)).firstOrNull;
        n['where'] = <String, dynamic>{'message': old['message'] is Map ? old['message'] : <String, dynamic>{if (src != null) 'step': src.id}, if (old['task'] == true) 'task': true};
      default:
        final src = _steps.reversed.where((s) => (s.type == 'process_create' || s.type == 'process_find') && _before.contains(s.id)).firstOrNull;
        final ref = old['process'] is Map ? old['process'] : <String, dynamic>{if (src != null) 'step': src.id};
        n['where'] = <String, dynamic>{'process': ref, if (v == 'both') 'task': true};
    }
  }

  /// Ai thao tác, ở đâu, hạn chờ, nhánh Luôn chạy. [button]: Chờ bấm nút (thêm thẻ đã gửi, tin nhắn).
  List<Widget> _waitCommon({bool button = false}) {
    final where = waitWhereMode(n);
    return [
      WhoField(app: widget.app, roles: widget.roles, label: tr('Ai được thao tác'), value: n['who'], onChanged: (w) => _set(() => n['who'] = w)),
      _hint(tr('Người khác bấm sẽ nhận "không có quyền" trên thẻ, và không thấy tiến trình ở "Tiến trình của tôi".')),
      _gap(),
      _title(tr('Thao tác ở đâu')),
      if (button)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in waitButtonWhere.entries)
            ChoiceChip(
              label: Text(e.key == 'both' ? tr('Thẻ tiến trình + Tiến trình của tôi') : tr(e.value)),
              selected: where == e.key,
              onSelected: (_) => _set(() => _setWhere(e.key)),
            ),
        ])
      else
        _seg<String>(waitWhere, where, _setWhere),
      _hint(switch (where) {
        'sent' => tr('Nút có sẵn trên thẻ đã gửi (bước Gửi thẻ): mỗi nút của bước này là một nút của thẻ; "Bất kỳ nút nào" nhận mọi nút.'),
        'message' => tr('Bộ nút gắn lên tin nhắn đã gửi vào nhóm; xong / quá hạn thì bộ nút khoá lại, ghi ai đã chọn gì.'),
        _ => tr('Chọn cả hai: bấm ở đâu trước thì tính ở đó, chỗ còn lại tự khoá.'),
      }),
      if (where == 'card' || where == 'both') ...[_gap(), ..._process(label: tr('Thẻ của tiến trình'), holder: _map(n, 'where'))],
      if (where == 'sent') ...[_gap(), _cardRef(_map(_map(n, 'where'), 'card'))],
      if (where == 'message') ...[_gap(), _msgRef(_map(_map(n, 'where'), 'message'))],
      if (where == 'sent' || where == 'message')
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Cũng tạo tiến trình ở "Tiến trình của tôi"')),
          value: (n['where'] as Map)['task'] == true,
          onChanged: (v) => _set(() => v ? (n['where'] as Map)['task'] = true : (n['where'] as Map).remove('task')),
        ),
      _gap(),
      _due('timeout', tr('Hạn chờ (có hạn thì thêm nhánh "Quá hạn")')),
      _gap(8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Dừng nhánh "Luôn chạy" khi người dùng đã thao tác')),
        subtitle: Text(tr('Nhánh "Luôn chạy" chạy ngay khi bước bắt đầu, song song với lúc chờ.')),
        value: n['stop_always_on_action'] != false,
        onChanged: (v) => _set(() => n['stop_always_on_action'] = v),
      ),
    ];
  }

  List<Widget> _waitButton() {
    final bs = _list(n, 'buttons');
    final branching = bs.where((b) => b['url'] == null).length;
    final sent = waitWhereMode(n) == 'sent';
    // Thẻ đã gửi: nút lấy từ thẻ (mã nút = id trên thẻ), cộng "Bất kỳ nút nào".
    final card = sent ? _baseCard((n['where'] as Map)['card']) : null;
    final acts = <String, String>{
      for (final a in (card?['actions'] as List? ?? const []))
        if (a is Map && a['id'] != null) '${a['id']}': '${a['label'] ?? a['id']}',
      anyButtonId: tr('Bất kỳ nút nào'),
    };
    return [
      _tpl(tr('Câu hỏi / lời nhắn'), n, 'prompt', lines: 2),
      _gap(),
      _title(tr('Các nút')),
      if (sent) ...[
        for (final b in bs)
          _row([
            if (card == null)
              _plain(tr('Mã nút trên thẻ (* = bất kỳ nút nào)'), b, 'id', key: ValueKey('bi-${identityHashCode(b)}'))
            else
              DropdownButtonFormField<String>(
                initialValue: acts.containsKey(b['id']) ? '${b['id']}' : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Nút trên thẻ'), isDense: true, border: const OutlineInputBorder()),
                items: [for (final e in acts.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => _set(() {
                  b['id'] = v;
                  b['label'] = acts[v];
                  b.remove('url');
                }),
              ),
          ], () => _set(() => bs.remove(b)), key: ObjectKey(b)),
        _add(tr('Thêm nút'), () {
          final used = {for (final b in bs) '${b['id']}'};
          final next = acts.keys.where((k) => !used.contains(k)).firstOrNull ?? anyButtonId;
          bs.add({'id': next, 'label': acts[next] ?? next});
        }),
        _hint(tr('Mỗi nút là một nhánh trên sơ đồ.')),
      ] else
      for (final b in bs)
        _row([
          _plain(tr('Chữ trên nút'), b, 'label', key: ValueKey('bl-${identityHashCode(b)}')),
          const SizedBox(height: 6),
          _seg<bool>({false: 'Rẽ nhánh', true: 'Chỉ mở link'}, b.containsKey('url'), (v) => v ? b['url'] = '' : (b..remove('url')).remove('sign')),
          if (b.containsKey('url')) ...[
            const SizedBox(height: 6),
            _tpl(tr('Link'), b, 'url', key: ValueKey('bu-${identityHashCode(b)}')),
            FlowSignEditor(key: ValueKey('bs-${identityHashCode(b)}'), button: b, vars: widget.vars, onChanged: () => _set(() {})),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tr('Nút chính (nền màu)')),
            value: b['style'] == 'primary',
            onChanged: (v) => _set(() => v == true ? b['style'] = 'primary' : b.remove('style')),
          ),
        ], () => _set(() => bs.remove(b)), key: ObjectKey(b)),
      if (!sent) ...[
        _add(tr('Thêm nút'), () => bs.add({'id': FlowDoc.newId('nut'), 'label': ''})),
        _hint(tr('Mỗi nút rẽ nhánh là một nhánh trên sơ đồ. Nút chỉ mở link không có nhánh: bấm chỉ mở link, tiến trình vẫn chờ các nút khác.')),
      ],
      if (branching == 0 && '${n['timeout'] ?? ''}'.isEmpty) _hint(tr('Cần ít nhất một nút rẽ nhánh (hoặc đặt hạn chờ).'), color: kFlowRed),
      _gap(),
      ..._waitCommon(button: true),
    ];
  }

  List<Widget> _waitChoice() {
    final os = _list(n, 'options');
    Widget num_(String key, String label) => SizedBox(
          width: 120,
          child: TextFormField(
            initialValue: n[key] == null ? '' : '${n[key]}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
            onChanged: (t) => _set(() => int.tryParse(t.trim()) == null ? n.remove(key) : n[key] = int.parse(t.trim())),
          ),
        );
    return [
      _tpl(tr('Câu hỏi / lời nhắn'), n, 'prompt', lines: 2),
      _gap(),
      _title(tr('Các lựa chọn')),
      for (final o in os) _row([_plain(tr('Lựa chọn'), o, 'label', key: ValueKey('ol-${identityHashCode(o)}'))], () => _set(() => os.remove(o)), key: ObjectKey(o)),
      _add(tr('Thêm lựa chọn'), () => os.add({'id': FlowDoc.newId('lc'), 'label': ''})),
      _hint(tr('Mỗi lựa chọn là một nhánh. Các lựa chọn đã tích chạy song song; bước Gộp sau đó chỉ chờ các nhánh được chọn.')),
      _gap(),
      Row(children: [num_('min', tr('Chọn ít nhất')), const SizedBox(width: 10), num_('max', tr('Chọn nhiều nhất'))]),
      _gap(),
      ..._waitCommon(),
    ];
  }

  List<Widget> _waitClose() {
    final waits = [for (final s in _steps) if (const {'wait_button', 'wait_choice', 'approval_request'}.contains(s.type) && s.id != n['id']) s];
    return [
      DropdownButtonFormField<String>(
        initialValue: waits.any((s) => s.id == n['wait']) ? '${n['wait']}' : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: tr('Bước chờ cần kết thúc'),
          helperText: waits.isEmpty ? tr('Chưa có bước Chờ bấm nút / Lựa chọn / Duyệt nào.') : null,
          border: const OutlineInputBorder(),
        ),
        items: [for (final s in waits) DropdownMenuItem(value: s.id, child: Text(_stepName(s), overflow: TextOverflow.ellipsis))],
        onChanged: (v) => _set(() => n['wait'] = v),
      ),
      _gap(),
      _tpl(tr('Lý do (vd Đã ký trên M-Invoice)'), n, 'reason'),
      _hint(tr('Thường đặt trong nhánh "Luôn chạy" của bước chờ. Nút trên thẻ bị khoá ("Đã xử lý tự động"), tiến trình ở "Tiến trình của tôi" tự đóng, các nhánh nút không chạy nữa.')),
    ];
  }

  // ------------------------------------------------------------------ tạo phê duyệt

  List<Widget> _approvalRequest() {
    final fields = _list(n, 'fields');
    final editable = [for (final k in (n['editable'] as List? ?? const [])) '$k'];
    final returns = [for (final k in (n['return_steps'] as List? ?? const [])) '$k'];
    final esc = _list(n, 'escalate');
    // Bước nhập liệu trước đó: đơn ban đầu và các bước Điền thông tin đứng trước.
    final inputs = <(String, String)>[
      ('start', tr('Nhập dữ liệu (đơn ban đầu)')),
      for (final s in _steps)
        if (s.type == 'form_task' && (_before.isEmpty || _before.contains(s.id))) (s.id, _stepName(s)),
    ];
    return [
      _tpl(tr('Tên yêu cầu (để trống = tên bước; vd Xuất hoá đơn nghi trùng …)'), n, 'title'),
      _gap(),
      _tpl(tr('Lý do cần phê duyệt'), n, 'reason', lines: 2),
      _gap(),
      WhoField(app: widget.app, roles: widget.roles, label: tr('Người phê duyệt'), value: n['approver'], onChanged: (w) => _set(() => n['approver'] = w)),
      _gap(),
      _title(tr('Khi có nhiều người duyệt')),
      _seg<String>({'any': 'Một người duyệt là đủ', 'all': 'Tất cả phải duyệt'}, '${n['mode'] ?? 'any'}', (v) => n['mode'] = v),
      _gap(),
      ..._process(optional: true, label: tr('Gắn với tiến trình (nút Duyệt / Từ chối / Trả lại hiện trên thẻ)')),
      _gap(),
      _title(tr('Thông tin người duyệt nhập thêm')),
      for (var i = 0; i < fields.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.edit_note_rounded),
          title: Text('${fields[i]['label'] ?? fields[i]['key']}'),
          onTap: () async {
            final r = await showDialog<Object>(context: context, builder: (_) => FieldDialog(field: fields[i], taken: {for (final f in fields) '${f['key']}'}));
            if (r == null) return;
            _set(() => r == 'delete' ? fields.removeAt(i) : fields[i] = r as Map<String, dynamic>);
          },
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('Thêm trường')),
          onPressed: () async {
            final r = await showDialog<Object>(context: context, builder: (_) => FieldDialog(taken: {for (final f in fields) '${f['key']}'}));
            if (r is Map<String, dynamic>) _set(() => fields.add(r));
          },
        ),
      ),
      if (widget.form.isNotEmpty) ...[
        _title(tr('Trường người duyệt được sửa')),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in widget.form.where((f) => f.calc == null))
            FilterChip(
              label: Text(f.label),
              selected: editable.contains(f.key),
              onSelected: (v) => _set(() {
                final next = v ? [...editable, f.key] : [for (final x in editable) if (x != f.key) x];
                next.isEmpty ? n.remove('editable') : n['editable'] = next;
              }),
            ),
        ]),
        _gap(),
      ],
      _title(tr('Cho người duyệt trả lại về bước')),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (id, label) in inputs)
          FilterChip(
            label: Text(label),
            selected: returns.contains(id),
            onSelected: (v) => _set(() {
              final next = v ? [...returns, id] : [for (final x in returns) if (x != id) x];
              next.isEmpty ? n.remove('return_steps') : n['return_steps'] = next;
            }),
          ),
      ]),
      _hint(tr('Người duyệt chọn một bước và ghi lý do; người làm bước đó nhận lại tiến trình với dữ liệu cũ, nộp lại thì quay lại phê duyệt.')),
      _gap(),
      _due('due', tr('Hạn duyệt (có hạn thì thêm nhánh "Quá hạn"; để trống nhánh thì chỉ nhắc)')),
      _gap(),
      _due('remind', tr('Nhắc lại mỗi'), options: const ['2h', '4h', '8h', '24h', '1wd']),
      _gap(),
      _title(tr('Leo thang (thêm nhánh "Leo thang")')),
      for (final (i, e) in esc.indexed)
        _row([
          Text(tr('Cấp {0}', [i + 1]), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _plain(tr('Sau (vd 8h, 24h, 2d)'), e, 'after', key: ValueKey('ea-${identityHashCode(e)}')),
          const SizedBox(height: 6),
          WhoField(app: widget.app, roles: widget.roles, label: tr('Chuyển tới'), value: e['to'], onChanged: (w) => _set(() => e['to'] = w)),
          const SizedBox(height: 6),
          _seg<String>({'add': 'Thêm người duyệt', 'replace': 'Thay người duyệt'}, '${e['mode'] ?? 'add'}', (v) => e['mode'] = v),
          const SizedBox(height: 6),
          _tpl(tr('Ghi chú (vd Đã chuyển lên Giám đốc)'), e, 'note', key: ValueKey('en-${identityHashCode(e)}')),
        ], () => _set(() => esc.remove(e)), key: ObjectKey(e)),
      _add(tr('Thêm cấp leo thang'), () => esc.add({'after': esc.isEmpty ? '8h' : '24h', 'to': {'manager': r'$requester', 'level': esc.length + 2}, 'mode': 'add'})),
      if (esc.isNotEmpty) _hint(tr('Các mốc phải tăng dần (và nhỏ hơn hạn duyệt khi có nối nhánh "Quá hạn").')),
      _gap(8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Dừng nhánh "Luôn chạy" khi đã có quyết định')),
        value: n['stop_always_on_action'] != false,
        onChanged: (v) => _set(() => n['stop_always_on_action'] = v),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final children = switch (type) {
      'send' => _send(),
      'card_send' => _cardSend(),
      'card_update' => _cardUpdate(),
      'card_wait' => _cardWait(),
      'process_create' => _processCreate(),
      'process_step' => _processStep(),
      'process_stat' => _processStat(),
      'process_attach' => _processAttach(),
      'process_fail' => _processFail(),
      'process_finish' => _processFinish(),
      'process_send' => _processSend(),
      'process_find' => _processFind(),
      'process_label' => _processLabel(),
      'process_props' => _processProps(),
      'process_wait' => _processWait(),
      'doc_render' => _docRender(),
      'process_remind' => _processRemind(),
      'wait_button' => _waitButton(),
      'wait_choice' => _waitChoice(),
      'wait_close' => _waitClose(),
      'approval_request' => _approvalRequest(),
      _ => <Widget>[],
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
