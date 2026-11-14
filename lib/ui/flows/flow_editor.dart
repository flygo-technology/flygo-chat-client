import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, listEquals;
import 'package:flutter/gestures.dart' show GestureBinding, PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../api/flows_api.dart';
import '../../state/drafts.dart';
import '../chat_page.dart' show ChatPage;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen, kFlowOrange, kFlowRed;
import 'flow_calc.dart';
import 'flow_cond.dart';
import 'flow_doc.dart';
import 'flow_editor_errors.dart';
import 'flow_editor_expr.dart';
import 'flow_editor_expr_field.dart';
import 'flow_editor_nodes.dart';
import 'flow_editor_cardx.dart';
import 'flow_editor_compose.dart';
import 'flow_editor_runas.dart';
import 'flow_editor_set.dart';
import 'flow_editor_tables.dart';
import 'flow_editor_vars.dart';
import 'flow_icon_picker.dart';
import 'flow_logic.dart';
import 'flow_nav.dart';
import '../home_page.dart' show PageCloser;
import 'flow_starts.dart';
import '../location.dart' show currentPosition;
import 'package:flygo_chat/ui/app_route.dart';
import 'magic_sign_hooks.dart' show FlowSignEditor;

/// Trình soạn quy trình: sơ đồ dọc tự sắp xếp (không phải bảng vẽ tự do). "+" giữa các bước để chèn,
/// điều kiện / song song tách thành các cột nhánh, kéo thả để đổi chỗ, chạm vào bước để cấu hình.
/// Kiểm lỗi + chạy thử + lưu do máy chủ làm (POST /flows/defs/check, /flows/defs).

/// Mở trình soạn: quy trình có sẵn ([flowId]), từ mẫu ([template], thành quy trình mới), hoặc trống.
Future<bool?> openFlowEditor(BuildContext context, AppState app, FlowsApi api, {String? flowId, Map<String, dynamic>? template}) async {
  Map<String, dynamic>? def;
  // Thêm quy trình: hỏi tên trước, rồi tạo ngay trên máy chủ (mã 6 ký tự ngẫu nhiên, đang tắt) để trợ lý AI cũng sửa được ngay.
  if (flowId == null) {
    final name = await _askFlowName(context, '${template?['name'] ?? ''}');
    if (name == null || !context.mounted) return null;
    if (template != null) template = {...template, 'name': name};
    try {
      final created = await api.newDef(name: name, category: template?['category'] as String?);
      flowId = '${created['id']}';
      def = (created['def'] as Map).cast<String, dynamic>();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không tạo được quy trình: {0}', ['$e']))));
      return null;
    }
    flowsChanged.value++;
    if (template != null) {
      // Từ mẫu: nội dung mẫu, mã của quy trình vừa tạo; chưa lưu (bấm Lưu để thành phiên bản đầu).
      final t = jsonDecode(jsonEncode(template)) as Map<String, dynamic>;
      t['id'] = flowId;
      if (!context.mounted) return null;
      return openFlowPage<bool>(context, 'editor-$flowId', (_) => FlowEditorPage(app: app, api: api, doc: FlowDoc.fromJson(t), isNew: true));
    }
  } else {
    try {
      def = await api.getDef(flowId);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không mở được quy trình: {0}', ['$e']))));
      return null;
    }
  }
  if (!context.mounted) return null;
  return openFlowPage<bool>(context, 'editor-$flowId', (_) => FlowEditorPage(app: app, api: api, doc: FlowDoc.fromJson(def!)));
}

/// Trình soạn đang mở (máy tính: ở vùng giữa của mục Quy trình): hỏi trước khi rời nếu còn thay đổi chưa lưu. Trả về
/// true = được rời (không có gì chưa lưu, hoặc người dùng chọn "Bỏ").
Future<bool> Function()? _editorLeaveGuard;

/// Trước khi mở quy trình khác thay cho trình soạn đang mở: hỏi bỏ thay đổi chưa lưu (nếu có).
Future<bool> canLeaveFlowEditor() async => await _editorLeaveGuard?.call() ?? true;

/// Hộp hỏi tên quy trình mới (điền sẵn tên mẫu). Trả về tên đã nhập, null nếu huỷ.
Future<String?> _askFlowName(BuildContext context, String initial) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) {
      void ok() {
        final v = ctl.text.trim();
        if (v.isNotEmpty) Navigator.pop(d, v);
      }

      return AlertDialog(
        title: Text(tr('Tạo quy trình mới')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Tên quy trình'), hintText: tr('Vd Đề xuất thanh toán'), border: const OutlineInputBorder()),
          onSubmitted: (_) => ok(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Huỷ'))),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: ctl,
            builder: (_, v, _) => FilledButton(onPressed: v.text.trim().isEmpty ? null : ok, child: Text(tr('Tạo'))),
          ),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------------------------- ngữ cảnh trình soạn

/// Dữ liệu dùng chung của trình soạn đang mở (phòng ban, danh sách quy trình, công cụ, thông tin của luồng),
/// để các hộp thoại con (chọn người, danh mục, điều kiện hiện...) không phải truyền qua từng lớp.
class EditorCtx {
  final AppState app;
  final FlowsApi api;
  final Map<String, dynamic> integ;
  final List<Map<String, dynamic>> depts;
  final List<Map<String, dynamic>> flows;
  final List<CondVar> vars;
  final String flowId;
  final List<FStep> steps;
  /// Quy trình đang soạn (để hiện tên dễ đọc thay cho đường dẫn biến).
  final FlowDoc? doc;
  const EditorCtx(
      {required this.app,
      required this.api,
      this.integ = const {},
      this.depts = const [],
      this.flows = const [],
      this.vars = const [],
      this.flowId = '',
      this.steps = const [],
      this.doc});
}

EditorCtx? editorCtx;

// ---------------------------------------------------------------------------------------------- nhãn

/// Màu theo nhóm bước: con người, điều khiển luồng, tin nhắn, AI, ứng dụng (MCP).
const kGroupPeople = Color(0xFF3B82F6), kGroupLogic = Color(0xFFE5508A), kGroupMessage = Color(0xFFE08A1E), kGroupAi = Color(0xFF8B5CF6), kGroupApp = Color(0xFF0D9488);

(IconData, Color, String) stepLook(String type) => switch (type) {
      'approval' => (Icons.how_to_reg_rounded, kGroupPeople, tr('Duyệt')),
      'claim' => (Icons.front_hand_outlined, kGroupPeople, tr('Tiếp nhận')),
      'form_task' => (Icons.edit_note_rounded, kGroupPeople, tr('Điền thông tin')),
      'delegate_set' => (Icons.swap_horiz_rounded, kGroupPeople, tr('Đặt ủy quyền')),
      'user_status' => (Icons.beach_access_outlined, kGroupPeople, tr('Đổi trạng thái')),
      'delegate_request' => (Icons.assignment_ind_outlined, kGroupPeople, tr('Yêu cầu ủy quyền')),
      'delegate_apply' => (Icons.verified_user_outlined, kGroupPeople, tr('Áp dụng ủy quyền')),
      'delegate_approve' => (Icons.verified_user_outlined, kGroupPeople, tr('Duyệt ủy quyền')),
      'delegate_revoke' => (Icons.undo_rounded, kGroupPeople, tr('Thu hồi ủy quyền')),
      'condition' => (Icons.call_split_rounded, kGroupLogic, tr('Rẽ nhánh')),
      'parallel' => (Icons.account_tree_outlined, kGroupLogic, tr('Song song')),
      'foreach' || 'table_loop' => (Icons.repeat_rounded, kGroupTable, tr('Lặp bảng')),
      final t when tableNodeTypes.contains(t) => tableLook(t),
      'wait' => (Icons.hourglass_bottom_rounded, kGroupLogic, tr('Chờ')),
      'calc' => (Icons.calculate_outlined, kGroupLogic, tr('Tính toán')),
      'set' => (Icons.data_object_rounded, kGroupLogic, tr('Đặt biến')),
      'compose' => (Icons.edit_document, kGroupMessage, tr('Soạn nội dung')),
      'progress' => (Icons.linear_scale_rounded, kGroupLogic, tr('Báo tiến độ')),
      'geo_distance' => (Icons.social_distance_rounded, kGroupLogic, tr('Tính khoảng cách GPS')),
      'chat_post' => (Icons.attach_file_rounded, kGroupMessage, tr('Gửi tin kèm tệp')),
      'wait_event' => (Icons.notifications_paused_outlined, kGroupLogic, tr('Chờ sự kiện')),
      'start_flow' => (Icons.alt_route_rounded, kGroupLogic, tr('Bắt đầu quy trình khác')),
      'notify' => (Icons.notifications_active_outlined, kGroupMessage, tr('Thông báo')),
      'note_add' => (Icons.sticky_note_2_outlined, kGroupMessage, tr('Thêm ghi chú')),
      'note_edit' => (Icons.edit_note_rounded, kGroupMessage, tr('Sửa ghi chú')),
      'buttons' => (Icons.smart_button_outlined, kGroupMessage, tr('Nút trên tin')),
      'ai' => (Icons.auto_awesome_rounded, kGroupAi, tr('Bước AI')),
      'mcp' => (Icons.extension_outlined, kGroupApp, tr('Gọi công cụ')),
      'auto' => (Icons.bolt_rounded, kGroupApp, tr('Tự động')),
      // Thẻ dữ liệu, tiến trình, chờ người dùng, tạo phê duyệt.
      final t when editorNodeTypes.contains(t) => nodeLook(t),
      _ => (Icons.circle_outlined, Colors.grey, type),
    };

const _roleNames = {
  'truong_phong': 'Trưởng phòng',
  'pho_phong': 'Phó phòng',
  'giam_doc': 'Giám đốc',
  'pho_giam_doc': 'Phó giám đốc',
  'ke_toan': 'Kế toán',
  'ke_toan_truong': 'Kế toán trưởng',
  'thu_quy': 'Thủ quỹ',
  'nhan_su': 'Nhân sự',
  'kho': 'Thủ kho',
  'mua_hang': 'Mua hàng',
};

String roleLabel(String r) => _roleNames[r] ?? r.replaceAll('_', ' ');

String _userName(AppState app, String id) {
  final u = app.users[id];
  if (u == null) return id;
  return u.displayName.isNotEmpty ? u.displayName : u.username;
}

/// "$requester" / {role} / {user} / {users} → chữ dễ đọc.
String whoLabel(Object? w, AppState app) {
  if (w == null || w == r'$requester') return tr('Người tạo tiến trình');
  if (w is Map) {
    if (w['department'] != null) {
      final d = editorCtx?.depts.where((x) => x['id'] == w['department']).firstOrNull;
      return tr('Cả phòng {0}', ['${d?['name'] ?? w['department']}']);
    }
    if (w['field'] != null) {
      final v = editorCtx?.vars.where((x) => x.path == w['field']).firstOrNull;
      return v?.label ?? '${w['field']}';
    }
    if (w['manager'] != null) {
      final lv = (w['level'] as num?)?.toInt() ?? 1;
      return lv > 1 ? tr('Quản lý cấp {0} của người tạo', [lv]) : tr('Quản lý của người tạo');
    }
    if (w['role'] != null) return roleLabel('${w['role']}');
    if (w['user'] != null) return _userName(app, '${w['user']}');
    if (w['users'] is List) return [for (final u in w['users'] as List) _userName(app, '$u')].join(', ');
  }
  return '$w';
}

/// Nhóm người nhận của "mỗi người một luồng": phòng ban ghi tên phòng (không kèm "Cả phòng").
String peopleLabel(Object? w, AppState app) {
  if (w is Map && w['department'] != null) {
    final d = editorCtx?.depts.where((x) => x['id'] == w['department']).firstOrNull;
    return '${d?['name'] ?? w['department']}';
  }
  return whoLabel(w, app);
}

/// "24h" → "24 giờ", "2d" → "2 ngày", "30m" → "30 phút".
/// Lệch so với mốc ("-3d", "+4h", "-2wd") → "trước 3 ngày" / "sau 4 giờ".
String offsetLabel(String off) {
  final t = off.trim();
  if (t.isEmpty) return '';
  final neg = t.startsWith('-');
  final d = durLabel(t.replaceFirst(RegExp(r'^[+-]'), ''));
  return neg ? tr('(trước {0})', [d]) : tr('(sau {0})', [d]);
}

/// Ô "Lệch so với mốc" (offset): chip có sẵn + ô gõ. Sửa trực tiếp [m]['offset'].
List<Widget> offsetField(BuildContext context, Map<String, dynamic> m, VoidCallback changed, {String? label}) {
  final cur = '${m['offset'] ?? ''}'.trim();
  return [
    Text(label ?? tr('Lệch so với mốc'), style: Theme.of(context).textTheme.labelLarge),
    const SizedBox(height: 6),
    Wrap(spacing: 6, runSpacing: 6, children: [
      ChoiceChip(label: Text(tr('Đúng mốc')), selected: cur.isEmpty, onSelected: (_) {
        m.remove('offset');
        changed();
      }),
      for (final o in {'-1d', '-3d', '-7d', '-2wd', '+4h', '+1d', if (cur.isNotEmpty) cur})
        ChoiceChip(label: Text(offsetLabel(o).replaceAll(RegExp(r'^\(|\)$'), '')), selected: cur == o, onSelected: (_) {
          m['offset'] = o;
          changed();
        }),
    ]),
    Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(tr('"-3d": trước mốc 3 ngày; "-2wd": trước 2 ngày làm việc; "+4h": sau mốc 4 giờ.'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12)),
    ),
  ];
}

/// Nguồn sự kiện của Chờ sự kiện theo khoá.
const eventSources = {'any': 'Mọi nguồn', 'webhook': 'Webhook', 'chat': 'Tin nhắn nhóm', 'email': 'Email'};

String durLabel(String d) {
  final wd = RegExp(r'^(\d+)\s*wd$').firstMatch(d.trim());
  if (wd != null) return tr('{0} ngày làm việc', [wd[1]]);
  final m = RegExp(r'^(\d+)\s*([smhdw])$').firstMatch(d.trim());
  if (m == null) return d;
  final unit = switch (m[2]) { 's' => tr('giây'), 'm' => tr('phút'), 'h' => tr('giờ'), 'd' => tr('ngày'), _ => tr('tuần') };
  return '${m[1]} $unit';
}

String stepSummary(FStep s, AppState app, [List<CondVar> vars = const []]) {
  final doc = editorCtx?.doc;
  return humanTemplate(_stepSummary(s, app, vars), vars, doc, integ: editorCtx?.integ ?? const {});
}

String _stepSummary(FStep s, AppState app, List<CondVar> vars) {
  final n = s.node;
  switch (s.kind) {
    case 'note_add':
      return '“${(n['params'] as Map?)?['text'] ?? ''}”';
    case 'note_edit':
      final src = editorCtx?.steps.where((x) => x.id == (n['params'] as Map?)?['note_step']).firstOrNull;
      return src == null ? tr('Chưa chọn ghi chú') : tr('Sửa ghi chú của "{0}"', [src.name]);
    case 'buttons':
      final bs = [for (final b in (n['buttons'] as List? ?? const [])) if (b is Map) '${b['label']}'];
      return bs.isEmpty ? tr('Xoá nút') : bs.join(' · ');
    case 'claim':
      return [tr('Ai bấm Tiếp nhận trước thì nhận'), whoLabel(n['assignee'], app)].join(' · ');
    case 'start_flow':
      final f = editorCtx?.flows.where((x) => x['id'] == n['flow_id']).firstOrNull;
      final many = n['each'] != null || n['each_person'] != null;
      final table = FlowField.listOf(editorCtx?.doc?.meta['form']).where((t) => 'form.${t.key}' == n['each']).firstOrNull;
      return [
        '${n['flow_id'] ?? ''}'.isEmpty ? tr('Chưa chọn quy trình') : '→ ${f?['name'] ?? n['flow_id']}',
        if (n['each_person'] != null)
          tr('Mỗi người trong «{0}» một luồng', [peopleLabel(n['each_person'], app)])
        else if (n['each'] != null)
          tr('Mỗi dòng của «{0}» một luồng', [table?.label ?? '${n['each']}'.replaceFirst('form.', '')]),
        if (n['confirm'] != null) tr('xác nhận: {0}', [whoLabel(n['confirm'], app)]),
        if (n['wait'] == true) many && '${n['timeout'] ?? ''}'.isNotEmpty ? tr('chờ tối đa {0}', [durLabel('${n['timeout']}')]) : tr('chờ xong'),
      ].join(' · ');
    case 'mcp':
      final p = (n['params'] as Map?) ?? const {};
      final schema = _toolOutput(editorCtx?.integ ?? const {}, mcpKeyOf(p), '${p['tool'] ?? ''}');
      final outs = [for (final k in (n['output_schema'] as Map? ?? const {}).keys) _schemaPath(schema, ['$k']).first].join(', ');
      return [
        '${p['tool'] ?? ''}'.isEmpty ? tr('Chưa chọn công cụ') : '${mcpKeyOf(p)} › ${p['tool']}',
        if (outs.isNotEmpty) tr('trả về: {0}', [outs]),
      ].join(' · ');
    case 'delegate_request':
      return tr('Người tạo tiến trình tự điền: từ ngày, đến ngày, quy trình → người');
    case 'delegate_approve':
      return tr('Quản lý trực tiếp của người tạo duyệt');
    case 'wait_event' when n['match'] is Map:
      final m = n['match'] as Map;
      return [
        '${m['key'] ?? ''}'.trim().isEmpty ? tr('Chưa đặt khoá sự kiện') : tr('Sự kiện khoá {0}', ['${m['key']}']),
        tr(eventSources['${m['source'] ?? 'any'}'] ?? 'Mọi nguồn'),
        if (n['timeout'] != null) tr('tối đa {0}', [durLabel('${n['timeout']}')]),
      ].join(' · ');
    case 'wait_event':
      return [
        '${n['tool'] ?? ''}'.isEmpty ? tr('Chưa chọn công cụ') : '${mcpKeyOf(n)} › ${n['tool']}',
        tr('kiểm tra mỗi {0}', [intervalLabel((n['seconds'] as num?)?.toInt() ?? 300)]),
        if (n['timeout'] != null) tr('tối đa {0}', [durLabel('${n['timeout']}')]),
      ].join(' · ');
    case 'geo_distance':
      final from = '${n['from'] ?? ''}';
      final fromLabel = from.isEmpty ? tr('chưa chọn vị trí') : '«${vars.where((v) => v.path == from).firstOrNull?.label ?? from}»';
      final lat = (n['lat'] as num?) ?? 0, lon = (n['lon'] as num?) ?? 0, r = n['radius'] as num?;
      return [
        tr('Từ {0} tới {1}', [fromLabel, lat == 0 && lon == 0 ? tr('(chưa đặt vị trí công ty)') : '($lat, $lon)']),
        if (r != null) tr('trong {0} m', [r % 1 == 0 ? '${r.toInt()}' : '$r']),
      ].join(' · ');
    case 'progress':
      final pct = '${n['percent'] ?? ''}'.trim();
      return [if (pct.isNotEmpty) pct.contains('{{') ? pct : '${pct.replaceAll('%', '')}%', '${n['label'] ?? ''}'.trim()]
          .where((s) => s.isNotEmpty)
          .join(' · ');
    case 'chat_post':
      final p = (n['params'] as Map?) ?? const {};
      final files = '${p['files'] ?? ''}'.trim();
      return [
        if ((p['to'] as List? ?? const []).contains(r'$requester')) tr('Cho người tạo tiến trình'),
        if ('${p['channel'] ?? ''}'.isNotEmpty) tr('Vào nhóm {0}', [app.channels['${p['channel']}'] == null ? '${p['channel']}' : app.channelTitle(app.channels['${p['channel']}']!)]),
        if (files.isNotEmpty) tr('kèm tệp'),
      ].join(' · ');
    case 'calc':
      final vs = [for (final v in (n['vars'] as List? ?? const [])) if (v is Map) v];
      return vs.isEmpty ? tr('Chưa có biến') : vs.map((v) => '${v['label'] ?? v['name']}').join(', ');
    case 'set':
      return setSummary(n, vars, FlowField.listOf(editorCtx?.doc?.meta['form']));
    case 'delegate_apply':
      return tr('Ủy quyền trong đơn có hiệu lực (tự động)');
    case 'delegate_revoke':
      return tr('Kết thúc các ủy quyền của tiến trình này');
    case 'delegate_set':
      final p = (n['params'] as Map?) ?? const {};
      final rules = (p['rules'] as List? ?? const []).length;
      return [tr('{0} dòng ủy quyền', [rules]), if (p['pending'] == true) tr('chuyển cả tiến trình đang chờ')].join(' · ');
    case 'user_status':
      final p = (n['params'] as Map?) ?? const {};
      return p['clear'] == true ? tr('Xoá trạng thái') : '${_statusEmoji['${p['emoji']}'] ?? ''} ${p['text'] ?? ''}'.trim();
    case 'approval':
      return [
        whoLabel(n['approver'], app),
        if (n['mode'] == 'all') tr('tất cả cùng duyệt'),
        if (n['due'] != null) tr('hạn {0}', [durLabel('${n['due']}')]),
        if (n['escalate'] is Map) tr('quá hạn chuyển {0}', [whoLabel((n['escalate'] as Map)['to'], app)]),
      ].join(' · ');
    case 'form_task':
      return [whoLabel(n['assignee'], app), tr('{0} trường', [(n['fields'] as List? ?? const []).length]), if (n['due'] != null) tr('hạn {0}', [durLabel('${n['due']}')])].join(' · ');
    case 'ai':
      final r = n['runner'] as Map? ?? const {};
      final out = (n['output_schema'] as Map? ?? const {}).keys.join(', ');
      return [r['kind'] == 'api' ? tr('Gọi API AI') : 'Bot ${r['bot'] ?? ''}', if (out.isNotEmpty) tr('trả về: {0}', [out])].join(' · ');
    case 'notify':
      final chans = (n['channels'] as List? ?? const []).length;
      return [
        if ((n['to'] as List? ?? const []).isNotEmpty) tr('Tới: {0}', [[for (final w in (n['to'] as List? ?? const [])) whoLabel(w, app)].join(', ')]),
        if (chans > 0) tr('vào {0} nhóm', [chans]),
      ].join(' · ');
    case 'wait':
      final until = '${n['until'] ?? ''}';
      if (n['for'] != null) return tr('Chờ {0}', [durLabel('${n['for']}')]);
      if (isClockText(until)) return tr('Chờ đến {0} hôm nay', [until.trim()]);
      final off = '${n['offset'] ?? ''}'.trim();
      final base = tr('Chờ tới {0}', [vars.where((v) => v.path == until).firstOrNull?.label ?? until]);
      return off.isEmpty ? base : '$base ${offsetLabel(off)}';
    case 'auto':
      return '${n['action'] ?? ''}';
    case 'compose':
      final subj = '${n['subject'] ?? ''}'.trim();
      return subj.isEmpty ? tr('Chưa có tiêu đề') : tr('Tiêu đề: {0}', [subj]);
    case final t when tableNodeTypes.contains(t):
      return tableSummary(s, (p) => vars.where((v) => v.path == p).firstOrNull?.label ?? p);
    default:
      return editorNodeTypes.contains(s.type) ? nodeSummary(s, app) : '';
  }
}

const _statusEmoji = {'palm_tree': '🌴', 'airplane': '✈️', 'face_with_thermometer': '🤒', 'house': '🏠', 'calendar': '📅', 'books': '📚'};

String _stepTitle(FItem it) => switch (it) {
      FStep s => s.name.isEmpty ? stepLook(s.kind).$3 : s.name,
      FCondition c => c.name.isEmpty ? tr('Rẽ nhánh') : c.name,
      FParallel p => p.name.isEmpty ? tr('Song song') : p.name,
      FLoop l => l.name.isEmpty ? tr('Lặp bảng') : l.name,
    };

const _fieldTypes = {
  'text': 'Chữ ngắn',
  'textarea': 'Đoạn văn',
  'number': 'Số',
  'money': 'Số tiền',
  'date': 'Ngày',
  'select': 'Chọn một',
  'user': 'Người',
  'files': 'Tệp đính kèm',
  'images': 'Ảnh',
  'location': 'Vị trí',
  'wifi': 'Wi-Fi',
  'photo': 'Ảnh chụp tại chỗ',
  'bool': 'Có / Không',
  'table': 'Bảng (nhiều dòng)',
  'delegation': 'Ủy quyền',
};

IconData _fieldIcon(String t) => switch (t) {
      'textarea' => Icons.notes_rounded,
      'number' => Icons.pin_outlined,
      'money' => Icons.payments_outlined,
      'date' => Icons.event_outlined,
      'select' => Icons.arrow_drop_down_circle_outlined,
      'user' => Icons.person_outline_rounded,
      'files' => Icons.attach_file_rounded,
      'images' => Icons.image_outlined,
      'location' => Icons.place_outlined,
      'wifi' => Icons.wifi_rounded,
      'photo' => Icons.photo_camera_outlined,
      'bool' => Icons.toggle_on_outlined,
      'table' => Icons.table_chart_outlined,
      'delegation' => Icons.swap_horiz_rounded,
      _ => Icons.short_text_rounded,
    };

/// Ghi chú dưới ô chọn kiểu: các kiểu app tự lấy, người dùng không gõ.
const _fieldHints = {
  'location': 'App tự lấy GPS khi mở tiến trình',
  'wifi': 'App tự đọc Wi-Fi đang nối',
  'photo': 'Chỉ chụp bằng camera',
};

/// "Số tiền đề xuất" → "so_tien_de_xuat".
String slugKey(String label) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final ch in label.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
}

// ---------------------------------------------------------------------------------------------- tên dễ đọc của biến

/// Tên hiện của một thuộc tính trong khuôn kết quả (JSON Schema) của tool: title, rồi mô tả ngắn, rồi tên trường.
String _schemaTitle(Map? prop, String key) {
  final t = '${prop?['title'] ?? ''}'.trim();
  if (t.isNotEmpty) return t;
  final d = '${prop?['description'] ?? ''}'.trim().split(RegExp(r'[.\n(]')).first.trim();
  return d.isNotEmpty && d.length <= 40 ? d : key;
}

/// Nhóm công cụ của một chỗ gọi công cụ (tham số bước, bước chờ sự kiện, danh mục, bước Bắt đầu): `app` (Flygo
/// Gateway) hoặc `server` (máy chủ MCP cũ).
String mcpKeyOf(Map m) {
  final a = '${m['app'] ?? ''}';
  return a.isNotEmpty ? a : '${m['server'] ?? ''}';
}

/// Ghi nhóm công cụ đã chọn vào [m]: nhóm của gateway (có `app`) ghi `app` và bỏ `server`; máy chủ MCP cũ ghi `server`.
void setMcpKey(Map m, List<Map> groups, String? name) {
  final g = groups.where((x) => x['name'] == name).firstOrNull;
  if (g != null && g['app'] != null) {
    m['app'] = g['app'];
    m.remove('server');
  } else {
    m['server'] = name;
    m.remove('app');
  }
}

/// Tên hiện của tool: `title` (gateway) hoặc tên.
String toolTitle(Map t) => '${t['title'] ?? ''}'.trim().isNotEmpty ? '${t['title']}' : '${t['name']}';

/// Khuôn kết quả của tool [tool] ở máy chủ MCP [server] (lấy từ integrations). Tên có chèn biến (vd
/// "{{...}}-list-accounts") thì tìm tool có cùng phần đuôi ở bất kỳ máy chủ nào.
Map? _toolOutput(Map integ, String server, String tool) {
  final servers = [for (final m in (integ['mcp'] as List? ?? const [])) if (m is Map) m];
  bool match(String name) => tool.contains('{{') ? name.endsWith(tool.split('}}').last) && tool.split('}}').last.isNotEmpty : name == tool;
  for (final m in servers) {
    if (!server.contains('{{') && m['name'] != server && !tool.contains('{{')) continue;
    for (final t in (m['tools'] as List? ?? const [])) {
      if (t is Map && match('${t['name']}')) return t['output_schema'] as Map?;
    }
  }
  return null;
}

/// Đi theo đường dẫn trong khuôn kết quả: ["result", "download_url"] → ["Kết quả", "Đường dẫn tải"].
List<String> _schemaPath(Map? schema, List<String> keys) {
  final out = <String>[];
  Map? cur = schema;
  for (final k in keys) {
    final props = cur?['properties'] as Map?;
    final prop = props?[k] as Map?;
    out.add(_schemaTitle(prop, k));
    cur = prop?['type'] == 'array' ? (prop?['items'] as Map?) : prop;
  }
  return out;
}

/// Tên dễ đọc của một đường dẫn biến (form.x, `steps.<id>.output.x`, requester, today...). Không bao giờ trả về
/// đường dẫn thô khi có tên khai báo: nhãn trường, tên biến của bước Tính toán, tên thuộc tính trong khuôn của tool.
String flowVarLabel(String path, FlowDoc doc, {Map integ = const {}}) {
  final parts = path.split('.');
  switch (parts.first) {
    case 'form':
      final f = FlowField.listOf(doc.meta['form']).where((f) => f.key == parts[1].split('__').first).firstOrNull;
      return [f?.label ?? parts[1], ...parts.skip(2).map((p) => fieldPartLabel(f?.type ?? '', p))].join(' › ');
    case 'steps' when parts.length >= 2:
      final s = doc.allSteps.where((x) => x.id == parts[1]).firstOrNull;
      if (s == null) return parts.skip(1).join(' › ');
      final name = s.name.isEmpty ? stepLook(s.kind).$3 : s.name;
      var rest = parts.skip(2).toList();
      if (rest.isNotEmpty && rest.first == 'output') rest = rest.skip(1).toList();
      if (rest.isEmpty) return name;
      final n = s.node;
      final List<String> field;
      // Nhánh Lỗi: output.error {message, code}.
      if (rest.first == 'error' && FStep.errorTypes.contains(s.type)) {
        final part = rest.length > 1 ? switch (rest[1]) { 'message' => tr('Nội dung'), 'code' => tr('Mã'), final x => x } : null;
        return [name, tr('Lỗi'), ?part].join(' › ');
      }
      switch (s.kind) {
        case 'calc':
          final v = [for (final v in (n['vars'] as List? ?? const [])) if (v is Map && v['name'] == rest.first) v].firstOrNull;
          field = ['${v?['label'] ?? rest.first}', ...rest.skip(1)];
        case 'form_task':
          final f = FlowField.listOf(n['fields']).where((f) => f.key == rest.first).firstOrNull;
          field = [f?.label ?? rest.first, ...rest.skip(1).map((p) => fieldPartLabel(f?.type ?? '', p))];
        case 'start_flow':
          field = [tr(childOutputLabels[rest.first] ?? rest.first), ...rest.skip(1)];
        case 'geo_distance':
          field = [tr(geoOutputLabels[rest.first] ?? rest.first), ...rest.skip(1)];
        case 'mcp':
          final pr = (n['params'] as Map?) ?? const {};
          field = _schemaPath(_toolOutput(integ, mcpKeyOf(pr), '${pr['tool'] ?? ''}'), rest);
        case 'wait_event':
          // Kết quả lần kiểm tra cuối: output.result = kết quả của tool.
          final schema = _toolOutput(integ, mcpKeyOf(n), '${n['tool'] ?? ''}');
          field = rest.first == 'result'
              ? [tr('Kết quả'), ..._schemaPath(schema, rest.skip(1).toList())]
              : rest.first == 'timeout'
                  ? [tr('Hết thời gian chờ')]
                  : rest;
        default:
          field = [nodeOutputLabel(s, rest.first) ?? rest.first, ...rest.skip(1)];
      }
      return [name, ...field].join(' › ');
    case 'result':
      return [tr('Kết quả'), ...parts.skip(1)].join(' › ');
    // Biến của bước Đặt biến.
    case 'vars':
      return [tr('Biến'), ...parts.skip(1)].join(' › ');
    case 'requester':
      return parts.length == 1 ? tr('Người tạo tiến trình') : '${tr('Người tạo tiến trình')} › ${parts.skip(1).join(' › ')}';
    case 'today':
      return tr('Hôm nay');
    case 'now':
      return tr('Bây giờ');
    case 'title':
      return tr('Tiêu đề tiến trình');
    case 'instance':
      return parts.length > 1 && parts[1] == 'id' ? tr('Mã tiến trình') : parts.join(' › ');
    case 'row':
      return [tr('Dòng đang xét'), ...parts.skip(1)].join(' › ');
    // Bước mở nhiều luồng: mỗi người (`item.user`) hoặc mỗi dòng của bảng.
    case 'item':
      return parts.length == 2 && parts[1] == 'user' ? tr('Người nhận') : [tr('Dòng'), ...parts.skip(1)].join(' › ');
    case 'loop':
      return parts.length == 2 && parts[1] == 'index' ? tr('Số thứ tự dòng') : parts.join(' › ');
    case 'index':
      return tr('Số thứ tự');
    // Tiến trình chính của luồng: process.props.<k>, process.stats.<k>, process.state...
    case 'process':
      final known = processVars(doc.allSteps).where((v) => v.path == path).firstOrNull;
      if (known != null) return known.label;
      final rest = parts.skip(1).toList();
      final head = rest.isEmpty
          ? <String>[]
          : switch (rest.first) {
              'props' => [tr('Thuộc tính'), ...rest.skip(1)],
              'stats' => [tr('Thống kê'), ...rest.skip(1)],
              final k => [tr(processVarLabels[k] ?? k)],
            };
      return [tr('Tiến trình'), ...head].join(' › ');
  }
  return path;
}

final _pathRe = RegExp(r'\b(?:form|steps|vars|result|requester|instance|row|item|loop|process)(?:\.[A-Za-z0-9_\-]+)+|\b(?:requester|today|now)\b');

/// [vars] cộng thêm mọi đường dẫn biến có trong quy trình mà [vars] chưa biết (vd kết quả tool chưa khai báo khuôn
/// ở bước, biến chèn trong tên máy chủ / tool), kèm tên dễ đọc: dùng để HIỂN THỊ (điều kiện, tóm tắt bước).
List<CondVar> labelledVars(FlowDoc doc, List<CondVar> vars, Map integ) {
  final known = {for (final v in vars) v.path};
  final extra = <CondVar>[];
  for (final m in _pathRe.allMatches(jsonEncode(doc.toJson()))) {
    final path = m.group(0)!;
    if (path.startsWith('steps.') && path.split('.').length < 3) continue;
    if (known.add(path)) extra.add(CondVar(path, flowVarLabel(path, doc, integ: integ), 'number'));
  }
  return [...vars, ...extra];
}

/// Chuỗi có chèn biến "{{...}}" → chữ đọc được: mỗi biến thành «tên», không để ngoặc nhọn.
String humanTemplate(String raw, List<CondVar> vars, FlowDoc? doc, {Map integ = const {}}) {
  if (!raw.contains('{{')) return raw;
  String label(String path) => vars.where((v) => v.path == path).firstOrNull?.label ?? (doc == null ? path : flowVarLabel(path, doc, integ: integ));
  return raw.replaceAllMapped(RegExp(r'\{\{\s*([^}]*?)\s*\}\}'), (m) {
    final path = m.group(1)!;
    // Trong ngoặc là biểu thức (vd {{form.sl * form.gia}}): mỗi thông tin thành «tên».
    if (!RegExp(r'^[\p{L}_][\p{L}\p{N}_.\-]*$', unicode: true).hasMatch(path)) return '«${exprDisplay(path, label)}»'.replaceAll('««', '«').replaceAll('»»', '»');
    return '«${label(path)}»';
  });
}

/// Ghi chú khi mở quy trình có bước kiểu cũ vừa được đổi sang bước gộp: "Đã nâng cấp bước Duyệt, Gửi sang dạng
/// mới, lưu để áp dụng".
String upgradeNote(FlowDoc doc) {
  final names = [
    for (final k in doc.upgradedKinds)
      switch (k) { 'approval_request' => tr('Duyệt'), 'send' => tr('Gửi'), 'table_loop' => tr('Lặp bảng'), _ => tr('Chờ bấm nút') },
  ];
  return tr('Đã nâng cấp bước {0} sang dạng mới, lưu để áp dụng', [names.isEmpty ? tr('Duyệt') : names.join(', ')]);
}

// ---------------------------------------------------------------------------------------------- trang

class FlowEditorPage extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final FlowDoc doc;
  final bool isNew;
  /// Chỉ cho ảnh xem trước: mở sẵn tab (0 sơ đồ, 1 cài đặt) và lỗi giả.
  final int initialTab;
  final Map<String, List<String>>? debugIssues;
  const FlowEditorPage({super.key, required this.app, required this.api, required this.doc, this.isNew = false, this.initialTab = 0, this.debugIssues});
  @override
  State<FlowEditorPage> createState() => _FlowEditorPageState();
}

class _FlowEditorPageState extends State<FlowEditorPage> {
  late FlowDoc doc = widget.doc;
  final _undo = <String>[];
  /// Mở từ mẫu: nội dung chưa lưu.
  late bool _dirty = widget.isNew;
  /// Bước Duyệt kiểu cũ vừa được đổi sang dạng mới khi mở: chưa tính là sửa, nhưng cho lưu (kèm ghi chú).
  late bool _upgradeNote = widget.doc.upgraded.isNotEmpty;
  bool _dragging = false;
  bool _busy = false;
  late Map<String, List<String>> _issues = widget.debugIssues ?? {};
  Map<String, List<String>> _roles = {};
  /// Bot AI, máy chủ MCP, Kết nối AI (cho các ô chọn trong cấu hình bước).
  Map<String, dynamic> _integ = {};
  /// Trạng thái bật / tắt vừa đổi ở tab Cài đặt (null = theo danh sách quy trình).
  bool? _active;
  List<Map<String, dynamic>> _depts = [];
  List<Map<String, dynamic>> _flows = [];

  void Function(String, WidgetBuilder?)? _side;
  /// Trình soạn mở gần nhất (để trình soạn cũ khi bị thay không đóng cột phải của trình soạn mới).
  static _FlowEditorPageState? _liveEditor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _side = flowSidePanel(context);
  }

  /// Hỏi "Bỏ các thay đổi chưa lưu?" (không có thay đổi: được rời luôn).
  Future<bool> _confirmLeave() async {
    if (!_dirty || !mounted) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Bỏ các thay đổi chưa lưu?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Ở lại'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Bỏ'))),
        ],
      ),
    );
    return leave == true;
  }

  @override
  void dispose() {
    if (_editorLeaveGuard == _confirmLeave) _editorLeaveGuard = null;
    _rev.dispose();
    editorCtx = null;
    // Rời trình soạn: đóng khung cài đặt ở cột phải (sau khung hình, tránh setState khi đang huỷ cây). Trình soạn
    // khác vừa mở thay chỗ thì cột phải đã là của nó: để nguyên.
    final side = _side;
    if (side != null && _liveEditor == this) WidgetsBinding.instance.addPostFrameCallback((_) => side('step', null));
    if (_liveEditor == this) _liveEditor = null;
    super.dispose();
  }

  List<FlowField> get _form => FlowField.listOf(doc.meta['form']);

  @override
  void initState() {
    super.initState();
    _editorLeaveGuard = _confirmLeave;
    _liveEditor = this;
    // Máy tính: Cài đặt quy trình mở sẵn ở cột phải.
    if (widget.initialTab == 0) WidgetsBinding.instance.addPostFrameCallback((_) => _showSettingsSide());
    // Quy trình lưu trước khi có nốt Bắt đầu: đổi who_can_start / trigger sang starts (lưu lần tới sẽ dùng starts).
    if ((doc.meta['starts'] as List? ?? const []).isEmpty) doc.meta['starts'] = legacyStarts(doc.meta);
    // Bấm thủ công theo "Ai được dùng quy trình" trừ khi bật "chỉ một số người" (ghi rõ `only` cho lần lưu tới).
    for (final st in (doc.meta['starts'] as List)) {
      if (st is Map) normalizeManualStart(st, doc.meta['visible_to'] as List? ?? const []);
    }
    doc.meta.remove('who_can_start');
    doc.meta.remove('trigger');
    doc.numberNodes();
    widget.api.roles().then((r) {
      if (mounted) setState(() => _roles = r);
    }).catchError((_) {});
    widget.api.departments().then((r) {
      if (mounted) setState(() => _depts = r);
    }).catchError((_) {});
    widget.api.adminDefs().then((r) {
      if (mounted) setState(() => _flows = r);
    }).catchError((_) {});
    _loadInteg();
  }

  /// Công cụ thấy được theo chế độ chạy (đổi chế độ thì đọc lại: loại đọc / ghi của công cụ theo danh tính mới).
  void _loadInteg() {
    widget.api.integrations(flow: '${doc.meta['id'] ?? ''}', runAs: '${(doc.meta['run_as'] as Map?)?['mode'] ?? ''}').then((r) {
      if (mounted) setState(() => _integ = r);
    }).catchError((_) {});
  }

  /// "#12 · Duyệt": số cố định của bước đứng trước loại bước.
  /// Biến của quy trình kèm tên dễ đọc cho mọi đường dẫn có trong quy trình (chỉ để hiển thị).
  List<CondVar> _shownVars() => labelledVars(doc, flowVars(doc), _integ);

  String _numbered(int? no, String kind) => no == null ? kind : '${doc.meta['id']}-$no · $kind';

  /// Trợ lý AI soạn quy trình: phiên mới với trợ lý (chọn nếu có nhiều), ô nhắn điền sẵn mã quy trình. Máy tính mở ở
  /// cột phải, điện thoại mở trang mới. Trợ lý dùng công cụ Flygo Flows (MCP) để xem / sửa quy trình theo mã.
  Future<void> _askAi() async {
    final app = widget.app;
    final bots = app.users.values.where((u) => u.isBot && u.deleteAt == 0 && app.isAssistant(u.id)).toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    if (bots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Bạn chưa có trợ lý AI. Tạo ở tab Trợ lý.'))));
      return;
    }
    final bot = bots.length == 1
        ? bots.first
        : await showDialog<dynamic>(
            context: context,
            builder: (d) => SimpleDialog(
              title: Text(tr('Chọn trợ lý')),
              children: [for (final b in bots) SimpleDialogOption(onPressed: () => Navigator.pop(d, b), child: Text(b.displayName))],
            ),
          );
    if (bot == null || !mounted) return;
    final id = '${doc.meta['id']}';
    try {
      final group = app.channels[await app.openDirect(bot.id)]!;
      final c = await app.createAiChannel(group, [bot.id], title: tr('Quy trình {0}', [id]));
      Drafts.set(Drafts.key(c.id), tr('Quy trình {0} ("{1}"): dùng công cụ Flygo Flows để xem và sửa quy trình này (mã bước dạng {0}-số). Yêu cầu: ',
          [id, '${doc.meta['name'] ?? ''}']));
      if (!mounted) return;
      final side = flowSidePanel(context);
      if (side != null) {
        side('ai-$id', (_) => ChatPage(channelId: c.id, embedded: true, onClose: _closeSide));
      } else {
        await Navigator.of(context).push(AppPageRoute(builder: (_) => ChatPage(channelId: c.id)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  /// Tìm bước theo số (người dùng gửi ảnh chụp có "#12"): mở cài đặt của bước đó.
  Future<void> _findByNo() async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Tìm bước theo số')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: tr('Vd {0}-12 hoặc 12', ['${doc.meta['id']}']), border: const OutlineInputBorder()),
          onSubmitted: (t) => Navigator.pop(d, t),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Tìm')))],
      ),
    );
    // Nhận cả "K7Q2XA-12", "#12", "12".
    final no = int.tryParse((v ?? '').trim().split(RegExp(r'[-#\s]')).where((p) => p.isNotEmpty).lastOrNull ?? '');
    if (no == null || !mounted) return;
    if (no == 0) return _editForm();
    final st = _starts.where((s) => (s['no'] as num?)?.toInt() == no).firstOrNull;
    if (st != null) return _editStart(st);
    final it = doc.byNo(no);
    if (it == null) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không có bước {0}-{1}', ['${doc.meta['id']}', no]))));
      return;
    }
    if (it is FStep) return _editStep(it);
    return _blockMenu(it);
  }

  /// Mọi thay đổi đi qua đây: lưu bản cũ để hoàn tác, xoá đánh dấu lỗi cũ.
  void _edit(VoidCallback f) {
    _undo.add(jsonEncode(doc.toJson()));
    if (_undo.length > 50) _undo.removeAt(0);
    setState(() {
      f();
      doc.numberNodes();
      _dirty = true;
      _issues = {};
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      doc = FlowDoc.fromJson(jsonDecode(_undo.removeLast()) as Map<String, dynamic>);
      _dirty = true;
    });
  }

  // ------------------------------------------------------------------ kiểm / lưu

  Future<void> _check({bool simulate = false}) async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.checkDef(doc.toJson());
      if (!mounted) return;
      final issues = [for (final i in (r['issues'] as List? ?? const [])) if (i is Map) i.cast<String, dynamic>()];
      _markIssues(issues);
      await _showResult(issues, [for (final t in (r['traces'] as List? ?? const [])) if (t is Map) t.cast<String, dynamic>()], simulate ? 1 : 0);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _markIssues(List<Map<String, dynamic>> issues) {
    setState(() {
      _issues = {};
      for (final i in issues) {
        if (i['node'] != null && i['warn'] != true) (_issues['${i['node']}'] ??= []).add('${i['msg']}');
      }
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final v = await widget.api.saveDef(doc.toJson());
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _upgradeNote = false;
        _issues = {};
      });
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã lưu phiên bản {0}. Tiến trình mới sẽ chạy theo bản này.', [v]))));
    } on FlowsException catch (e) {
      if (!mounted) return;
      if (e.issues.isNotEmpty) {
        _markIssues(e.issues);
        await _showResult(e.issues, const [], 0, title: tr('Chưa lưu: quy trình còn lỗi'));
      } else if (isAdminOnlyError(e.message)) {
        await showAdminOnlyError(context, e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(toast(Text(e.message)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _nodeName(String id) {
    final it = doc.find(id);
    return it == null ? id : _stepTitle(it);
  }

  Future<void> _showResult(List<Map<String, dynamic>> issues, List<Map<String, dynamic>> traces, int tab, {String? title}) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (s) => FractionallySizedBox(
          heightFactor: 0.8,
          child: CheckResultView(
            issues: issues,
            traces: traces,
            initialTab: tab,
            title: title,
            vars: _shownVars(),
            nodeName: _nodeName,
            who: (id) => _userName(widget.app, id),
            // Chạm lỗi của một bước: mở bước đó (vd ô "Cho phép chạy không cần duyệt").
            onOpen: (id) {
              Navigator.pop(s);
              final it = doc.find(id);
              if (it is FStep) _editStep(it);
            },
          ),
        ),
      );

  // ------------------------------------------------------------------ chèn / sửa bước

  /// Lỗi đọc danh sách công cụ từ Flygo Gateway (máy chủ cũ không có trường này).
  Object? get _gatewayError {
    final g = _integ['gateway'];
    return _integ['source'] == 'gateway' && g is Map ? g['error'] : null;
  }

  Future<void> _insert(List<FItem> list, int i) async {
    final apps = [for (final m in (_integ['mcp'] as List? ?? const [])) if (m is Map) m];
    final Object? pick = flowSidePanel(context) != null
        ? await showDialog<Object>(
            context: context,
            builder: (_) => Dialog(child: SizedBox(width: 560, height: 640, child: Padding(padding: const EdgeInsets.only(top: 16), child: _InsertSheet(apps: apps, starts: _starts, gatewayError: _gatewayError)))),
          )
        : await showModalBottomSheet<Object>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (s) => FractionallySizedBox(heightFactor: 0.85, child: _InsertSheet(apps: apps, starts: _starts, gatewayError: _gatewayError)),
          );
    if (pick == null || !mounted) return;
    if (pick is Map && pick['start'] != null) return _addStart('${pick['start']}');
    // Bước ủy quyền: mỗi loại một lần trong quy trình (đủ cả ba khi lưu).
    if (const {'delegate_request', 'delegate_approve', 'delegate_revoke', 'delegate_apply'}.contains(pick) && doc.allSteps.any((s) => s.kind == pick)) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Quy trình đã có bước "{0}"', [stepLook('$pick').$3]))));
      return;
    }
    final item = FlowDoc.make(pick is Map ? 'mcp' : '$pick');
    if (pick is Map && item is FStep) {
      // Tool của một ứng dụng: điền sẵn máy chủ + tool, kết quả theo khuôn của tool (nếu có).
      final app = apps.firstWhere((a) => a['name'] == pick['mcp']);
      final tool = [for (final t in (app['tools'] as List? ?? const [])) if (t is Map && t['name'] == pick['tool']) t].firstOrNull ?? const {};
      item.node['name'] = toolTitle(tool);
      item.node['params'] = {if (app['app'] != null) 'app': app['app'] else 'server': pick['mcp'], 'tool': pick['tool'], 'args': <String, dynamic>{}};
      final os = ((tool['output_schema'] as Map?)?['properties'] as Map?) ?? const {};
      if (os.isNotEmpty) {
        item.node['output_schema'] = {
          for (final e in os.entries)
            '${e.key}': switch ((e.value as Map?)?['type']) { 'boolean' => 'bool', 'number' || 'integer' => 'number', 'string' => 'text', _ => 'json' },
        };
      }
    }
    if (item is FCondition) item.branches.first.cond = '';
    // "Kết thúc chờ" đặt trong nhánh của bước chờ: chọn sẵn bước chờ đó.
    if (item is FStep && item.type == 'wait_close') {
      final owner = doc.allSteps.where((x) => x.ports.any((p) => identical(p.steps, list))).firstOrNull;
      if (owner != null) item.node['wait'] = owner.id;
    }
    if (item is FLoop) {
      // Khung Lặp bảng: đặt vào sơ đồ rồi hỏi bảng / tên dòng (cần vị trí để biết khung ngoài, bảng phía trước).
      list.insert(i, item);
      final ok = await editLoopSettings(context, doc, item, flowVars(doc, at: item));
      list.remove(item);
      if (!ok || !mounted) return;
    }
    _edit(() => list.insert(i, item));
    if (item is FStep) await _editStep(item, fresh: true);
    if (item is FCondition) await _editBranch(item, item.branches.first);
  }

  /// Bước đang sửa ở khung cột phải (máy tính), để đánh dấu trên sơ đồ.
  String? _sideFor;

  void _closeSide() {
    if (_settingsSide && mounted) return _showSettingsSide();
    flowSidePanel(context)?.call('step', null);
    if (mounted) setState(() => _sideFor = null);
  }

  Future<void> _editStep(FStep s, {bool fresh = false}) async {
    final side = flowSidePanel(context);
    if (side != null) {
      setState(() => _sideFor = s.id);
      side(
        'step-${s.id}-${DateTime.now().microsecondsSinceEpoch}',
        (_) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: StepConfigSheet(
                app: widget.app,
                node: s.node,
                form: _form,
                roles: _roles,
                vars: flowVars(doc, at: s),
                integ: _integ,
                onDone: (r) {
                  _closeSide();
                  if (r == 'delete') {
                    _removeStep(s);
                  } else if (r is Map<String, dynamic>) {
                    _edit(() => doc.setNode(s, r));
                  }
                },
              ),
            ),
          ),
        ),
      );
      return;
    }
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.88, child: StepConfigSheet(app: widget.app, node: s.node, form: _form, roles: _roles, vars: flowVars(doc, at: s), integ: _integ)),
    );
    if (!mounted) return;
    if (r == 'delete') {
      _removeStep(s);
    } else if (r is Map<String, dynamic>) {
      _edit(() => doc.setNode(s, r));
    }
  }

  void _removeStep(FStep s) => _edit(() => doc.remove(s.id));

  Future<void> _editBranch(FCondition c, FBranch b) async {
    final r = await showDialog<String>(
      context: context,
      builder: (_) => CondDialog(app: widget.app, expr: b.cond ?? '', vars: flowVars(doc, at: c), canDelete: c.branches.where((x) => x.cond != null).length > 1),
    );
    if (r == null || !mounted) return;
    if (r == '\u0000delete') {
      _edit(() => c.branches.remove(b));
    } else {
      _edit(() => b.cond = r);
    }
  }

  /// Chọn bảng để lặp (bảng của biểu mẫu).
  /// Tên dễ đọc của bảng nguồn khung lặp.
  String _loopTableLabel(String src) {
    final f = _form.where((f) => 'form.${f.key}' == src).firstOrNull;
    if (f != null) return f.label;
    return flowVars(doc).where((v) => v.path == src).firstOrNull?.label ??
        [for (final s in doc.allSteps) ...tableOutputs(s).map((o) => (o.$1, '${s.name.isEmpty ? tableLook(s.type).$3 : s.name} › ${tr(tableOutputLabels[o.$2]!)}'))]
            .where((o) => o.$1 == src)
            .firstOrNull
            ?.$2 ??
        src;
  }

  Future<String?> _pickLoopTable(String current) async {
    final tables = [for (final f in _form) if (f.type == 'table') f];
    // Danh sách trong kết quả bước trước (vd tool ERP trả danh sách hoá đơn).
    final lists = <(String, String)>[
      for (final s in doc.allSteps)
        if (s.type == 'auto' || s.type == 'ai')
          for (final e in ((s.node['output_schema'] as Map?) ?? const {}).entries)
            if (e.value == 'json') ('steps.${s.id}.output.${e.key}', '${s.name.isEmpty ? stepLook(s.kind).$3 : s.name} › ${e.key}'),
    ];
    if (tables.isEmpty && lists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Biểu mẫu chưa có trường kiểu Bảng để lặp. Thêm ở bước "Nhập dữ liệu".'))));
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(tr('Lặp qua từng dòng của bảng')),
        children: [
          for (final t in tables)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, 'form.${t.key}'),
              child: Row(children: [
                Icon(current == 'form.${t.key}' ? Icons.radio_button_checked : Icons.radio_button_off, size: 18),
                const SizedBox(width: 10),
                Text(t.label),
              ]),
            ),
          if (lists.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(24, 10, 24, 4), child: Text(tr('Danh sách từ bước trước'), style: Theme.of(d).textTheme.labelLarge)),
          for (final (path, label) in lists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, path),
              child: Row(children: [
                Icon(current == path ? Icons.radio_button_checked : Icons.radio_button_off, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(label)),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _blockMenu(FItem it) async {
    final pal = Pal.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Đổi tên')), onTap: () => Navigator.pop(s, 'rename')),
          if (it is FLoop && it.legacy)
            ListTile(leading: const Icon(Icons.table_chart_outlined), title: Text(tr('Chọn bảng để lặp')), onTap: () => Navigator.pop(s, 'table'))
          else if (it is FLoop)
            ListTile(leading: const Icon(Icons.tune_rounded), title: Text(tr('Cài đặt lặp')), onTap: () => Navigator.pop(s, 'loop'))
          else
            ListTile(leading: const Icon(Icons.add_road_rounded), title: Text(tr('Thêm nhánh')), onTap: () => Navigator.pop(s, 'branch')),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: kFlowRed),
            title: Text(tr('Xoá cả khối (gồm các bước trong nhánh)'), style: const TextStyle(color: kFlowRed)),
            onTap: () => Navigator.pop(s, 'delete'),
          ),
          SizedBox(height: 4, child: ColoredBox(color: pal.bg)),
        ]),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'rename':
        final ctl = TextEditingController(text: switch (it) { FCondition c => c.name, FParallel p => p.name, FLoop l => l.name, FStep s => s.name });
        final name = await showDialog<String>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(tr('Đổi tên')),
            content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
              FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Lưu'))),
            ],
          ),
        );
        if (name == null) return;
        _edit(() {
          if (it is FCondition) it.name = name.trim();
          if (it is FParallel) it.name = name.trim();
          if (it is FLoop) it.name = name.trim();
        });
      case 'table':
        if (it is FLoop) {
          final t = await _pickLoopTable(it.items);
          if (t != null) _edit(() => it.items = t);
        }
      case 'loop':
        if (it is FLoop && await editLoopSettings(context, doc, it, flowVars(doc, at: it))) _edit(() {});
      case 'branch':
        if (it is FCondition) {
          final b = FBranch('', []);
          _edit(() => it.branches.insert(it.branches.length - 1, b));
          await _editBranch(it, b);
        }
        if (it is FParallel) _edit(() => it.branches.add([]));
      case 'delete':
        _edit(() => doc.remove(it.id));
    }
  }

  // ------------------------------------------------------------------ vẽ sơ đồ

  bool get _desktop => const {TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux}.contains(defaultTargetPlatform);

  Widget _line(Pal pal, [double h = 12]) => Container(width: 2, height: h, color: pal.divider);

  Widget _draggable(String id, Widget child) {
    final feedback = Material(color: Colors.transparent, child: Opacity(opacity: 0.9, child: child));
    void start() => setState(() => _dragging = true);
    void end() => setState(() => _dragging = false);
    return _desktop
        ? Draggable<String>(data: id, feedback: feedback, childWhenDragging: Opacity(opacity: 0.3, child: child), onDragStarted: start, onDragEnd: (_) => end(), child: child)
        : LongPressDraggable<String>(data: id, feedback: feedback, childWhenDragging: Opacity(opacity: 0.3, child: child), onDragStarted: start, onDragEnd: (_) => end(), child: child);
  }

  /// Ô "+" giữa hai bước; khi đang kéo thì thành chỗ thả.
  Widget _slot(Pal pal, List<FItem> list, int i) => DragTarget<String>(
        onAcceptWithDetails: (d) => _edit(() => doc.move(d.data, list, i)),
        builder: (context, cand, _) {
          final hot = cand.isNotEmpty;
          final Widget mid = _dragging
              ? AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 180,
                  height: hot ? 40 : 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hot ? pal.accent.withValues(alpha: 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: hot ? pal.accent : pal.divider, width: hot ? 2 : 1),
                  ),
                  child: Text(tr('Thả vào đây'), style: TextStyle(fontSize: 11.5, color: hot ? pal.accent : pal.sub)),
                )
              : Tooltip(
                  message: tr('Thêm bước'),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _insert(list, i),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: pal.surface, shape: BoxShape.circle, border: Border.all(color: pal.divider, width: 1.5)),
                      child: Icon(Icons.add_rounded, size: 17, color: pal.accent),
                    ),
                  ),
                );
          return Column(mainAxisSize: MainAxisSize.min, children: [_line(pal, 8), mid, _line(pal, 8)]);
        },
      );

  Widget _seq(Pal pal, List<FItem> list) => Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < list.length; i++) ...[_slot(pal, list, i), _item(pal, list[i])],
        _slot(pal, list, list.length),
      ]);

  Widget _item(Pal pal, FItem it) => switch (it) {
        FStep s when s.ports.isNotEmpty => _portBlock(pal, s),
        FStep s => _stepCard(pal, s),
        FCondition c => _block(
            pal,
            it,
            subtitle: tr('Đi theo nhánh đầu tiên đúng'),
            columns: [
              for (final b in c.branches)
                (
                  _branchChip(
                    pal,
                    b.cond == null
                        ? tr('Còn lại')
                        : (b.cond!.trim().isEmpty ? tr('Chưa đặt điều kiện') : tr('Nếu {0}', [condLabel(b.cond!, labelledVars(doc, flowVars(doc, at: c), _integ), userName: (id) => _userName(widget.app, id))])),
                    b.cond == null ? null : () => _editBranch(c, b),
                    warn: b.cond != null && b.cond!.trim().isEmpty,
                  ),
                  b.steps,
                ),
            ],
          ),
        FParallel p => _block(
            pal,
            it,
            subtitle: tr('Các nhánh chạy cùng lúc, đủ hết mới đi tiếp'),
            columns: [for (var i = 0; i < p.branches.length; i++) (_branchChip(pal, tr('Nhánh {0}', [i + 1]), null), p.branches[i])],
            footer: tr('Gộp: chờ đủ {0} nhánh', [p.branches.length]),
          ),
        FLoop l => _block(
            pal,
            it,
            subtitle: [
              l.items.isEmpty ? tr('Chưa chọn bảng') : tr('Mỗi dòng của "{0}"', [_loopTableLabel(l.items)]),
              if (l.alias.isNotEmpty) tr('tên dòng: {0}', [l.alias]),
              if (l.legacy) tr('khối lặp kiểu cũ (có bước chờ người), vẫn chạy như trước'),
              if (FlowDoc.loopBlockedItems(l).isNotEmpty) tr('⚠ không dùng được bước chờ người / song song bên trong'),
            ].join(' · '),
            columns: [(_branchChip(pal, l.alias.isEmpty ? tr('Với từng dòng') : tr('Với từng {0}', [l.alias]), null), l.body)],
            footer: l.legacy ? tr('Hết dòng thì đi tiếp') : (l.stopOnError ? tr('Hết dòng thì đi tiếp; lượt lỗi thì dừng') : tr('Hết dòng thì đi tiếp; lượt lỗi ghi lại, chạy tiếp')),
          ),
      };

  Widget _cardShell(Pal pal, String id, Color color, {required Widget child, VoidCallback? onTap}) {
    final bad = _issues[id];
    final selected = _sideFor == id;
    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bad != null ? kFlowRed : (selected ? pal.accent : pal.divider), width: bad != null || selected ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              child,
              if (bad != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline_rounded, size: 14, color: kFlowRed),
                    const SizedBox(width: 4),
                    Expanded(child: Text(bad.first, style: const TextStyle(color: kFlowRed, fontSize: 11.5))),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _head(Pal pal, IconData icon, Color color, String kind, String title, String sub, {Widget? trailing}) => Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kind.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 0.5, fontWeight: FontWeight.w700, color: color)),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: pal.text)),
            if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub)),
          ]),
        ),
        trailing ?? Icon(Icons.drag_indicator_rounded, size: 18, color: pal.sub.withValues(alpha: 0.6)),
      ]);

  Widget _stepCard(Pal pal, FStep s) {
    final (icon, color, kind) = stepLook(s.kind);
    return _draggable(
      s.id,
      _cardShell(pal, s.id, color, onTap: () => _editStep(s), child: _head(pal, icon, color, _numbered(s.no, kind), humanTemplate(_stepTitle(s), _shownVars(), doc, integ: _integ), stepSummary(s, widget.app, _shownVars()))),
    );
  }

  Widget _branchChip(Pal pal, String text, VoidCallback? onTap, {bool warn = false, Color? color, IconData editIcon = Icons.edit_rounded}) {
    final c = warn ? kFlowRed : (color ?? const Color(0xFFE5508A));
    return Material(
      color: c.withValues(alpha: 0.1),
      shape: StadiumBorder(side: BorderSide(color: c.withValues(alpha: 0.5))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(text, maxLines: 3, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
              if (onTap != null) ...[const SizedBox(width: 4), Icon(editIcon, size: 12, color: c)],
            ]),
          ),
        ),
      ),
    );
  }

  /// Bước nhiều cổng (chờ bấm nút, lựa chọn, tạo phê duyệt): thẻ bước, rồi mỗi nhánh ra một cột có nhãn. Nhánh
  /// chính gặp lại ở bước sau; nhánh phụ (Luôn chạy, Leo thang, Trả lại) và nhánh "kết thúc việc" dừng ở cuối cột.
  Widget _portBlock(Pal pal, FStep s) => Column(mainAxisSize: MainAxisSize.min, children: [
        _stepCard(pal, s),
        _line(pal, 12),
        BranchRow(color: pal.divider, ends: [for (final p in s.ports) p.ends], children: [
          for (final p in s.ports)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _branchChip(pal, portLabel(s, p), () => _portMenu(s, p), color: portColor(p), editIcon: Icons.more_horiz_rounded),
                _seq(pal, p.steps),
                if (p.ends)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.divider)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(p.side ? Icons.more_horiz_rounded : Icons.stop_circle_outlined, size: 14, color: p.key == 'reject' ? kFlowRed : pal.sub),
                      const SizedBox(width: 4),
                      Text(
                        p.side
                            ? tr('Hết nhánh')
                            : p.key == 'reject'
                                ? tr('Kết thúc: bị từ chối')
                                : (p.open && p.key == 'timeout' ? tr('Để trống: chỉ nhắc, vẫn chờ duyệt') : tr('Kết thúc tiến trình')),
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.key == 'reject' ? kFlowRed : pal.sub),
                      ),
                    ]),
                  ),
              ]),
            ),
        ]),
      ]);

  /// Ghi chú khi mở quy trình còn bước kiểu cũ (Duyệt, Thông báo / Gửi thẻ / Gửi tiến trình, Nút trên tin / Chờ bấm
  /// nút trên thẻ): đã đổi sang dạng mới trên sơ đồ, lưu để áp dụng (luồng đang chạy giữ phiên bản cũ).
  Widget _upgradeBanner(Pal pal) => Material(
        color: kGroupPeople.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: kGroupPeople),
            const SizedBox(width: 8),
            Expanded(child: Text(upgradeNote(doc), style: TextStyle(fontSize: 13, color: pal.text))),
            TextButton(onPressed: _busy ? null : _save, child: Text(tr('Lưu'))),
          ]),
        ),
      );

  /// Chạm nhãn nhánh: giải thích nhánh; nhánh chính chọn đi tiếp hay kết thúc việc khi hết nhánh.
  Future<void> _portMenu(FStep s, FPort p) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (d) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(portLabel(s, p), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: portColor(p))),
            const SizedBox(height: 6),
            Text(portHint(s, p), style: TextStyle(color: Pal.of(d).sub)),
            const SizedBox(height: 8),
            if (!p.side) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(p.end ? Icons.radio_button_off : Icons.radio_button_checked),
                title: Text(tr('Hết nhánh thì đi tiếp bước sau')),
                onTap: () => Navigator.pop(d, 'continue'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(p.end && !(p.unwired && p.key == 'timeout') ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(p.key == 'reject' && s.type == 'approval_request' ? tr('Hết nhánh thì kết thúc tiến trình (bị từ chối)') : tr('Hết nhánh thì kết thúc tiến trình')),
                onTap: () => Navigator.pop(d, 'end'),
              ),
              // Quá hạn của bước Duyệt: để trống thì chỉ nhắc người duyệt, yêu cầu vẫn mở (như bước Duyệt cũ).
              if (p.key == 'timeout' && s.type == 'approval_request')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(p.unwired ? Icons.radio_button_checked : Icons.radio_button_off),
                  title: Text(tr('Không nối bước nào thì chỉ nhắc, vẫn chờ duyệt')),
                  onTap: () => Navigator.pop(d, 'remind'),
                ),
            ] else
              Text(tr('Nhánh này tự kết thúc, không gặp lại bước sau.'), style: TextStyle(color: Pal.of(d).sub, fontSize: 12.5)),
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.tune_rounded), title: Text(tr('Cài đặt bước')), onTap: () => Navigator.pop(d, 'edit')),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    switch (r) {
      case 'continue' || 'end' || 'remind':
        // Từ chối của bước Duyệt: kết thúc = để trống (bộ chạy đi tới "khi bị từ chối" hoặc kết thúc "bị từ chối").
        final unwired = r == 'remind' || (r == 'end' && p.key == 'reject' && s.type == 'approval_request');
        if ((r != 'continue') != p.end || unwired != p.unwired) {
          _edit(() {
            p.end = r != 'continue';
            p.unwired = unwired;
          });
        }
      case 'edit':
        await _editStep(s);
    }
  }

  /// Khối điều kiện / song song: thẻ đầu, các cột nhánh nối bằng thanh ngang, gặp lại ở dưới.
  Widget _block(Pal pal, FItem it, {required String subtitle, required List<(Widget, List<FItem>)> columns, String? footer}) {
    final (icon, color, kind) = stepLook(switch (it) { FCondition _ => 'condition', FLoop _ => 'foreach', _ => 'parallel' });
    final head = _draggable(
      it.id,
      _cardShell(
        pal,
        it.id,
        color,
        onTap: () => _blockMenu(it),
        child: _head(pal, icon, color, _numbered(it.no, kind), _stepTitle(it), subtitle, trailing: Icon(Icons.more_vert_rounded, size: 18, color: pal.sub)),
      ),
    );
    final body = Column(mainAxisSize: MainAxisSize.min, children: [
      head,
      _line(pal, 12),
      BranchRow(color: pal.divider, children: [
        for (final (label, steps) in columns)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [label, _seq(pal, steps)]),
          ),
      ]),
      if (footer != null) ...[
        _line(pal, 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: kFlowGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(footer, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kFlowGreen)),
        ),
      ],
    ]);
    if (it is! FLoop) return body;
    // Khung Lặp bảng: hộp bao quanh các bước con (lồng nhau thì hộp trong hộp), tên khung ở góc.
    return Container(
      key: ValueKey('loop-frame-${it.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.6),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.repeat_rounded, size: 14, color: color),
              const SizedBox(width: 4),
              Text(it.name.isEmpty ? tr('Lặp bảng') : it.name, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        ),
        body,
      ]),
    );
  }

  Widget _pill(Pal pal, IconData icon, String text, Color color, {String? sub, VoidCallback? onTap}) => Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 11.5, color: pal.sub)),
              ]),
            ]),
          ),
        ),
      );

  /// Mục "Khi luồng bị huỷ" (on_cancel): chuỗi bước riêng sau "Kết thúc"; bước không tự động bị đánh dấu đỏ.
  List<Widget> _cancelSection(Pal pal) {
    final bad = doc.cancelBlockedItems;
    return [
      const SizedBox(height: 28),
      KeyedSubtree(
        key: const ValueKey('cancel-section'),
        child: _pill(pal, Icons.cancel_outlined, tr('Khi luồng bị huỷ'), kFlowOrange,
            sub: bad.isEmpty
                ? tr('Dừng mọi bước đang chờ, chạy các bước dưới (chỉ bước tự động)')
                : tr('Có {0} bước không dùng được ở đây (chỉ bước tự động)', [bad.length])),
      ),
      if (bad.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            [for (final b in bad) b is FStep ? (b.name.isEmpty ? stepLook(b.kind).$3 : b.name) : tr('Lặp')].join(', '),
            style: const TextStyle(color: kFlowRed, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      _line(pal, 14),
      _seq(pal, doc.cancelSteps),
      _pill(pal, Icons.flag_outlined, tr('Kết thúc'), const Color(0xFF8A8F98), sub: tr('Luồng đã huỷ')),
    ];
  }

  /// Phóng to / thu nhỏ sơ đồ (Ctrl / Cmd + cuộn chuột).
  double _zoom = 1;

  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (!(keys.isControlPressed || keys.isMetaPressed)) return;
    // Nhận sự kiện trước khung cuộn: không cuộn khi đang phóng.
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      setState(() => _zoom = (_zoom * (e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1)).clamp(0.4, 2.0));
    });
  }

  Widget _diagram(Pal pal) => LayoutBuilder(
        builder: (context, box) => Listener(
          onPointerSignal: _onWheel,
          child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 80),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth * (_zoom < 1 ? 1 / _zoom : 1)),
              child: ScaledBox(scale: _zoom, child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                child: Column(children: [
                  _startsRow(pal, box.maxWidth - 24),
                  _line(pal, 14),
                  _startCard(pal),
                  _seq(pal, doc.steps),
                  _pill(pal, Icons.flag_rounded, tr('Kết thúc'), kFlowGreen, sub: tr('Tiến trình hoàn tất')),
                  if (doc.cancelOn || doc.cancelSteps.isNotEmpty) ..._cancelSection(pal),
                ]),
              )),
            ),
          ),
        ),
        ),
      );

  // ------------------------------------------------------------------ biểu mẫu + cài đặt

  Future<void> _editForm() async {
    final side = flowSidePanel(context);
    final fields = [for (final f in (doc.meta['form'] as List? ?? const [])) if (f is Map) Map<String, dynamic>.of(f.cast<String, dynamic>())];
    if (side != null) {
      setState(() => _sideFor = 'start');
      side(
        'form-${DateTime.now().microsecondsSinceEpoch}',
        (_) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FormFieldsSheet(
                fields: fields,
                api: widget.api,
                flowId: '${doc.meta['id'] ?? ''}',
                onDone: (r) {
                  _closeSide();
                  if (r != null) _edit(() => doc.meta['form'] = r);
                },
              ),
            ),
          ),
        ),
      );
      return;
    }
    final r = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: FormFieldsSheet(
          fields: [for (final f in (doc.meta['form'] as List? ?? const [])) if (f is Map) Map<String, dynamic>.of(f.cast<String, dynamic>())],
          api: widget.api,
          flowId: '${doc.meta['id'] ?? ''}',
        ),
      ),
    );
    if (r != null && mounted) _edit(() => doc.meta['form'] = r);
  }

  // ------------------------------------------------------------------ nốt Bắt đầu

  List<Map<String, dynamic>> get _starts => [for (final x in (doc.meta['starts'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];

  /// Các cách bắt đầu (cùng đổ vào bước "Nhập dữ liệu") + nút thêm.
  Widget _startsRow(Pal pal, double width) {
    final starts = _starts;
    // Nằm trong vùng cuộn ngang: giới hạn bề rộng để các nốt xuống dòng theo màn hình.
    final w = width < 240 ? 240.0 : width;
    final card = w < 460 ? w : 220.0;
    return Column(children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w),
        child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
        for (final st in starts)
          SizedBox(
            width: card,
            child: _cardShell(
              pal,
              'start:${st['id']}',
              kGroupStart,
              onTap: () => _editStart(st),
              child: _head(pal, startIcon('${st['type']}'), kGroupStart, _numbered((st['no'] as num?)?.toInt(), tr('Bắt đầu')), '${st['name'] ?? ''}'.isEmpty ? startTypeLabel('${st['type']}') : '${st['name']}',
                  startSummary(st, widget.app, visibleTo: doc.meta['visible_to'] as List? ?? const []), trailing: const SizedBox.shrink()),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _pickStart,
        icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: kGroupStart),
        label: Text(starts.isEmpty ? tr('Thêm cách bắt đầu') : tr('Thêm cách bắt đầu khác'), style: const TextStyle(color: kGroupStart)),
      ),
    ]);
  }

  Future<void> _pickStart() async {
    final type = flowSidePanel(context) != null
        ? await showDialog<String>(context: context, builder: (_) => Dialog(child: SizedBox(width: 520, child: Padding(padding: const EdgeInsets.only(top: 16), child: StartTypeSheet(existing: _starts)))))
        : await showModalBottomSheet<String>(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => StartTypeSheet(existing: _starts));
    if (type != null && mounted) await _addStart(type);
  }

  Future<void> _addStart(String type) async {
    if (singleStartTypes.contains(type) && _starts.any((s) => s['type'] == type)) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Quy trình đã có bước "{0}"', [startTypeLabel(type)]))));
      return;
    }
    final st = newStart(type, _starts);
    _edit(() => doc.meta['starts'] = [..._starts, st]);
    // Bấm thủ công / được quy trình khác gọi: không cần cài thêm gì.
    if (type != 'manual' && type != 'flow') await _editStart(st);
  }

  void _applyStart(Map<String, dynamic> old, Object? r) {
    if (r == 'delete') {
      _edit(() => doc.meta['starts'] = [for (final s in _starts) if (s['id'] != old['id']) s]);
    } else if (r is Map<String, dynamic>) {
      _edit(() => doc.meta['starts'] = [for (final s in _starts) s['id'] == old['id'] ? r : s]);
    }
  }

  Future<void> _editStart(Map<String, dynamic> st) async {
    final side = flowSidePanel(context);
    Widget sheet({void Function(Object?)? onDone}) => StartConfigSheet(
          app: widget.app,
          api: widget.api,
          start: st,
          form: _form,
          roles: _roles,
          integ: _integ,
          flowId: '${doc.meta['id'] ?? ''}',
          flows: _flows,
          onDone: onDone,
        );
    if (side != null) {
      setState(() => _sideFor = 'start:${st['id']}');
      side(
        'start-${st['id']}-${DateTime.now().microsecondsSinceEpoch}',
        (_) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: sheet(onDone: (r) {
                _closeSide();
                _applyStart(st, r);
              }),
            ),
          ),
        ),
      );
      return;
    }
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.88, child: sheet()),
    );
    if (mounted) _applyStart(st, r);
  }

  /// Bước đầu tiên: người tạo luồng nhập dữ liệu theo các trường của quy trình.
  Widget _startCard(Pal pal) {
    final form = _form;
    return _cardShell(
      pal,
      'start',
      pal.accent,
      onTap: _editForm,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _head(
            pal,
            Icons.input_rounded,
            pal.accent,
            _numbered(0, tr('Nhập dữ liệu')),
            tr('Người tạo tiến trình điền'),
            form.isEmpty ? tr('Chưa có trường nào, chạm để thêm') : tr('{0} trường', [form.length]),
            trailing: Icon(Icons.edit_outlined, size: 18, color: pal.sub)),
        if (form.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              for (final f in form)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_fieldIcon(f.type), size: 13, color: pal.accent),
                    const SizedBox(width: 3),
                    Text(f.required ? '${f.label} *' : f.label, style: TextStyle(fontSize: 11.5, color: pal.text)),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }

  Future<void> _editCheck(int? i) async {
    final list = [for (final c in (doc.meta['checks'] as List? ?? const [])) if (c is Map) Map<String, dynamic>.of(c.cast<String, dynamic>())];
    final cur = i == null ? <String, dynamic>{} : list[i];
    final vars = [for (final v in flowVars(doc)) if (v.path.startsWith('form.')) v];
    final cond = await showDialog<String>(context: context, builder: (_) => CondDialog(app: widget.app, expr: '${cur['cond'] ?? ''}', vars: vars));
    if (cond == null || cond == '\u0000delete' || cond.isEmpty || !mounted) return;
    final ctl = TextEditingController(text: '${cur['msg'] ?? ''}');
    final msg = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Báo gì khi không đúng?')),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: tr('Vd Đến ngày phải từ Từ ngày trở đi'), border: const OutlineInputBorder())),
        actions: [FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: Text(tr('Xong')))],
      ),
    );
    if (msg == null) return;
    final c = {'cond': cond, 'msg': msg};
    _edit(() {
      i == null ? list.add(c) : list[i] = c;
      doc.meta['checks'] = list;
    });
  }

  Future<void> _pickIcon() async {
    final e = await pickFlowIcon(context, current: '${doc.meta['icon'] ?? ''}');
    if (e != null && mounted) _edit(() => doc.meta['icon'] = e);
  }

  /// Cài đặt quy trình (tên, biểu tượng, danh mục, bật / tắt, ai thấy...). Máy tính: ở cột phải, mở sẵn khi vào
  /// trình soạn (Sếp, 2026-11-14); điện thoại: trang riêng. Dựng lại mỗi khi trình soạn đổi trạng thái ([_rev]), nên
  /// sửa ở đây là thấy ngay; nút "Lưu" của trình soạn lưu cả quy trình.
  Future<void> _openSettings() async {
    if (_side != null) return _showSettingsSide();
    await Navigator.of(context).push(AppPageRoute(
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: _rev,
        builder: (ctx, _, _) => Scaffold(
          backgroundColor: Pal.of(ctx).bg,
          appBar: AppBar(title: Text(tr('Cài đặt quy trình')), actions: [_saveButton('flow-settings-save'), const SizedBox(width: 8)]),
          body: _settingsTab(Pal.of(ctx)),
        ),
      ),
    ));
  }

  /// Máy tính: khung Cài đặt đang được giữ ở cột phải (mở bước thì tạm thay chỗ, xong bước thì hiện lại).
  bool _settingsSide = false;

  void _showSettingsSide() {
    final side = _side;
    if (side == null || !mounted) return;
    setState(() {
      _settingsSide = true;
      _sideFor = null;
    });
    side(
      'settings',
      (_) => ValueListenableBuilder<int>(
        valueListenable: _rev,
        builder: (ctx, _, _) => Scaffold(
          backgroundColor: Pal.of(ctx).bg,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(tr('Cài đặt quy trình')),
            // Không có nút Lưu riêng: nút Lưu ở thanh tiêu đề trình soạn ngay bên cạnh (một nút cho cả quy trình).
            actions: [
              IconButton(key: const ValueKey('flow-settings-close'), tooltip: tr('Đóng'), onPressed: _hideSettingsSide, icon: const Icon(Icons.close_rounded)),
            ],
          ),
          body: _settingsTab(Pal.of(ctx)),
        ),
      ),
    );
  }

  void _hideSettingsSide() {
    _side?.call('settings', null);
    if (mounted) setState(() => _settingsSide = false);
  }

  /// Nút Lưu luôn thấy (thanh tiêu đề trình soạn; điện thoại cả ở trang Cài đặt vì trang đó che trình soạn): mờ khi
  /// không có gì để lưu, khi đó ghi "Đã lưu".
  Widget _saveButton(String key) {
    final pending = _dirty || _upgradeNote;
    return FilledButton.icon(
      key: ValueKey(key),
      onPressed: pending && !_busy ? _save : null,
      icon: Icon(pending ? Icons.save_outlined : Icons.check_rounded, size: 18),
      label: Text(pending ? tr('Lưu') : tr('Đã lưu')),
    );
  }

  /// Tăng mỗi lần setState: trang Cài đặt (route riêng) nghe để dựng lại.
  final _rev = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

  Widget _settingsTab(Pal pal) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Biểu tượng ở đầu, cạnh tên (Sếp, 2026-11-14): bấm để đổi.
      Row(children: [
        Tooltip(
          message: tr('Đổi biểu tượng'),
          child: InkWell(
            key: const ValueKey('flow-settings-icon'),
            borderRadius: BorderRadius.circular(14),
            onTap: _pickIcon,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.divider)),
                child: Text('${doc.meta['icon'] ?? ''}'.isEmpty ? '📋' : '${doc.meta['icon']}', style: const TextStyle(fontSize: 30)),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            initialValue: '${doc.meta['name'] ?? ''}',
            decoration: InputDecoration(labelText: tr('Tên quy trình'), border: const OutlineInputBorder()),
            onChanged: (v) => _edit(() => doc.meta['name'] = v),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      // Mã cố định do máy chủ cấp: chỉ hiện để chép, không sửa.
      Text.rich(TextSpan(children: [
        TextSpan(text: '${tr('Mã quy trình')}: ', style: TextStyle(color: pal.sub, fontSize: 12.5)),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: SelectableText('${doc.meta['id'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1, color: pal.text)),
        ),
        TextSpan(text: '  ·  ${tr('Cố định, dùng để tra tiến trình / bước')}', style: TextStyle(color: pal.sub, fontSize: 12)),
      ])),
      const SizedBox(height: 16),
      TextFormField(
        initialValue: '${doc.meta['category'] ?? ''}',
        decoration: InputDecoration(labelText: tr('Danh mục'), hintText: tr('Tài chính - Kế toán, Nhân sự, Mua hàng...'), helperText: tr('Nhóm trên trang "Tạo tiến trình mới"'), border: const OutlineInputBorder()),
        onChanged: (v) => _edit(() => v.trim().isEmpty ? doc.meta.remove('category') : doc.meta['category'] = v.trim()),
      ),
      const SizedBox(height: 12),
      TextFormField(
        initialValue: '${doc.meta['description'] ?? ''}',
        minLines: 2,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: tr('Mô tả'),
          hintText: tr('Quy trình dùng để làm gì, khi nào dùng, cần chuẩn bị gì...'),
          helperText: tr('Hiện ở trang giới thiệu quy trình trên máy tính'),
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => _edit(() => v.trim().isEmpty ? doc.meta.remove('description') : doc.meta['description'] = v.trim()),
      ),
      const SizedBox(height: 12),
      Builder(builder: (context) {
        final cur = _flows.where((f) => f['id'] == doc.meta['id']).firstOrNull;
        final on = _active ?? cur?['active'] == true;
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Bật quy trình'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(on ? tr('Đang bật: tạo được tiến trình mới') : tr('Đang tắt: không tạo được tiến trình mới (tiến trình đang chạy vẫn tiếp tục)')),
          value: on,
          onChanged: (v) async {
            final m = ScaffoldMessenger.of(context);
            try {
              await widget.api.setActive('${doc.meta['id']}', v);
              setState(() => _active = v);
              flowsChanged.value++;
            } catch (e) {
              m.showSnackBar(toast(Text('$e')));
            }
          },
        );
      }),
      // "Thử nghiệm": hiện cho mọi người (có nhãn) nhưng chưa ai bắt đầu được; sơ đồ rỗng vẫn lưu được.
      SwitchListTile(
        key: const ValueKey('flow-experimental'),
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Thử nghiệm'), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(tr('Hiện cho mọi người nhưng chưa cho bắt đầu')),
        value: doc.meta['experimental'] == true,
        onChanged: (v) => _edit(() => v ? doc.meta['experimental'] = true : doc.meta.remove('experimental')),
      ),
      const SizedBox(height: 8),
      // Thẻ trạng thái của người tạo: nút / nhãn / tệp thêm (của cả quy trình).
      ExpansionTile(
        key: const ValueKey('flow-card-extra'),
        tilePadding: EdgeInsets.zero,
        title: Text(tr('Nút, nhãn trên thẻ trạng thái'), style: const TextStyle(fontWeight: FontWeight.w700)),
        children: [CardExtraField(owner: doc.meta, vars: flowVars(doc), onChanged: () => _edit(() {}))],
      ),
      const SizedBox(height: 8),
      RunAsField(
        key: const ValueKey('flow-run-as'),
        meta: doc.meta,
        userName: (id) => _userName(widget.app, id),
        onChanged: () {
          _edit(() {});
          _loadInteg();
        },
      ),
      const SizedBox(height: 8),
      Text(tr('Thời gian áp dụng'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      const SizedBox(height: 6),
      Row(children: [
        for (final (k, label) in [('valid_from', tr('Từ ngày')), ('valid_until', tr('Đến hết ngày'))]) ...[
          Expanded(
            child: InkWell(
              onTap: () async {
                final cur = DateTime.tryParse('${doc.meta[k] ?? ''}') ?? DateTime.now();
                final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) _edit(() => doc.meta[k] = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  suffixIcon: doc.meta[k] == null ? const Icon(Icons.event_outlined) : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => _edit(() => doc.meta.remove(k))),
                ),
                child: Text(doc.meta[k] == null ? tr('Không giới hạn') : showFieldValue(const FlowField(key: 'd', label: '', type: 'date'), doc.meta[k])),
              ),
            ),
          ),
          if (k == 'valid_from') const SizedBox(width: 10),
        ],
      ]),
      const SizedBox(height: 16),
      // Một chỗ cài quyền (Sếp, 2026-11-14): ai được dùng thì thấy và bắt đầu được (bước Bấm thủ công).
      Text(tr('Ai được dùng quy trình (xem + chạy)'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      const SizedBox(height: 4),
      Text(tr('Những người này thấy quy trình và bắt đầu được (bấm "Tạo tiến trình mới"). Muốn chỉ một số người được bắt đầu: chạm bước "Bắt đầu" trên sơ đồ, bật "Nâng cao".'),
          style: TextStyle(color: pal.sub, fontSize: 12.5)),
      const SizedBox(height: 6),
      WhoListField(
        app: widget.app,
        roles: _roles,
        value: doc.meta['visible_to'] as List? ?? const [],
        emptyLabel: tr('Cả công ty'),
        onChanged: (v) => _edit(() => v.isEmpty ? doc.meta.remove('visible_to') : doc.meta['visible_to'] = v),
      ),
      const SizedBox(height: 12),
      Text(tr('Cách bắt đầu (bấm tay, lịch, webhook...): chạm các bước "Bắt đầu" ở đầu sơ đồ.'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
      const SizedBox(height: 12),
      // Nhánh khi luồng bị huỷ (`on_cancel`): chỉ bước tự động (báo tin, cập nhật / huỷ tiến trình, gọi công cụ).
      SwitchListTile(
        key: const ValueKey('on-cancel'),
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Khi luồng bị huỷ, chạy thêm các bước')),
        subtitle: Text(tr('Hiện mục "Khi luồng bị huỷ" cuối sơ đồ: chỉ bước tự động (gửi tin, cập nhật / hoàn thành tiến trình, gọi công cụ…). Các bước đang chờ dừng hết, chạy xong thì luồng kết thúc "Đã huỷ".')),
        value: doc.cancelOn || doc.cancelSteps.isNotEmpty,
        onChanged: (v) => _edit(() {
          doc.cancelOn = v;
          if (!v) doc.cancelSteps.clear();
        }),
      ),
      const SizedBox(height: 20),
      // Kiểm tra chéo khi gửi form (vd Đến ngày ≥ Từ ngày): điều kiện dựng bằng giao diện + lời báo.
      Text(tr('Kiểm tra khi gửi'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      const SizedBox(height: 4),
      Text(tr('Điều kiện phải đúng mới gửi được (vd Đến ngày từ Từ ngày trở đi, Tạm ứng không quá hạn mức).'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
      const SizedBox(height: 6),
      for (final (i, c) in [for (final c in (doc.meta['checks'] as List? ?? const [])) if (c is Map) c].indexed)
        Card(
          elevation: 0,
          color: pal.surface2,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.rule_rounded),
            title: Text(condLabel('${c['cond']}', _shownVars())),
            subtitle: Text('${c['msg'] ?? ''}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: kFlowRed),
              onPressed: () => _edit(() => (doc.meta['checks'] as List).removeAt(i)),
            ),
            onTap: () => _editCheck(i),
          ),
        ),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => _editCheck(null), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm kiểm tra')))),
    ]);
  }

  // ------------------------------------------------------------------ khung trang

  /// Nút đóng của trang ở vùng giữa (máy tính): hỏi bỏ thay đổi chưa lưu trước khi đóng.
  Widget? _leading() {
    final closer = PageCloser.of(context);
    if (Navigator.of(context).canPop() || closer == null) return flowLeading(context);
    return IconButton(
      tooltip: tr('Đóng'),
      onPressed: () async {
        if (await _confirmLeave()) closer.onClose();
      },
      icon: const Icon(Icons.close_rounded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    editorCtx = EditorCtx(
        app: widget.app, api: widget.api, integ: _integ, depts: _depts, flows: _flows, vars: flowVars(doc), flowId: '${doc.meta['id'] ?? ''}', steps: doc.allSteps, doc: doc);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (did, _) async {
        if (did) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop(false);
      },
      child: Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(
            leading: _leading(),
            title: Row(children: [
              Text('${doc.meta['icon'] ?? ''}'.isEmpty ? '📋' : '${doc.meta['icon']}', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(child: Text('${doc.meta['name'] ?? ''}'.isEmpty ? tr('Quy trình mới') : '${doc.meta['name']}', overflow: TextOverflow.ellipsis)),
            ]),
            // Các thao tác gộp vào nút ba chấm; có thay đổi chưa lưu thì nút có chấm báo.
            actions: [
              if (_side != null && !_settingsSide)
                IconButton(key: const ValueKey('flow-settings-open'), tooltip: tr('Cài đặt quy trình'), onPressed: _showSettingsSide, icon: const Icon(Icons.tune_rounded)),
              _saveButton('flow-save'),
              PopupMenuButton<String>(
                tooltip: tr('Thao tác'),
                enabled: !_busy,
                icon: Badge(isLabelVisible: _dirty, smallSize: 9, child: const Icon(Icons.more_vert_rounded)),
                onSelected: (v) => switch (v) {
                  'ai' => _askAi(),
                  'find' => _findByNo(),
                  'save' => _save(),
                  'undo' => _undoLast(),
                  'check' => _check(),
                  'settings' => _openSettings(),
                  _ => _check(simulate: true),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'save',
                    enabled: _dirty || _upgradeNote,
                    child: ListTile(dense: true, leading: const Icon(Icons.save_outlined), title: Text(_dirty || _upgradeNote ? tr('Lưu') : tr('Đã lưu'))),
                  ),
                  PopupMenuItem(value: 'undo', enabled: _undo.isNotEmpty, child: ListTile(dense: true, leading: const Icon(Icons.undo_rounded), title: Text(tr('Hoàn tác')))),
                  PopupMenuItem(value: 'check', child: ListTile(dense: true, leading: const Icon(Icons.fact_check_outlined), title: Text(tr('Kiểm lỗi')))),
                  PopupMenuItem(value: 'run', child: ListTile(dense: true, leading: const Icon(Icons.play_circle_outline_rounded), title: Text(tr('Chạy thử')))),
                  PopupMenuItem(value: 'find', child: ListTile(dense: true, leading: const Icon(Icons.tag_rounded), title: Text(tr('Tìm bước theo số')))),
                  PopupMenuItem(value: 'ai', child: ListTile(dense: true, leading: const Icon(Icons.auto_awesome_rounded), title: Text(tr('Hỏi trợ lý AI')))),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: const Icon(Icons.tune_rounded), title: Text(tr('Cài đặt quy trình')))),
                ],
              ),
            ],
          ),
          // Ảnh xem trước dùng initialTab 1 để chụp trang cài đặt; bình thường luôn là sơ đồ.
          body: Stack(children: [
            widget.initialTab == 1
                ? _settingsTab(pal)
                : Column(children: [
                    if (_upgradeNote) _upgradeBanner(pal),
                    Expanded(child: _diagram(pal)),
                  ]),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
          ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------- chèn bước

/// Bảng "Thêm bước": nhóm theo loại (con người, điều khiển luồng, tin nhắn, AI) và mỗi ứng dụng MCP một nhóm
/// (danh sách lấy từ cấu hình máy chủ Flows; bấm nhóm để xem các tool). Có ô tìm; nhóm thu gọn / mở rộng được.
/// Trả về loại bước (String), hoặc {mcp, tool} khi chọn một tool.
class _InsertSheet extends StatefulWidget {
  final List<Map> apps;
  /// Các nốt Bắt đầu đã có (loại chỉ được một thì mờ). Chọn nốt Bắt đầu trả về {start: loại}.
  final List starts;
  /// Máy chủ dùng Flygo Gateway mà không đọc được danh sách công cụ: lý do (hiện trên bảng chọn bước).
  final Object? gatewayError;
  const _InsertSheet({this.apps = const [], this.starts = const [], this.gatewayError});
  @override
  State<_InsertSheet> createState() => _InsertSheetState();
}

class _InsertSheetState extends State<_InsertSheet> {
  /// Nhóm đang thu gọn (nhớ giữa các lần mở trong phiên).
  static final Set<String> _remember = <String>{};
  static bool _seeded = false;
  String _q = '';

  static final _groups = <(String, IconData, Color, String, List<(String, String)>)>[
    ('people', Icons.person_outline_rounded, kGroupPeople, 'Con người', [
      ...insertPeopleItems,
      ('claim', 'Giao cho một nhóm, ai bấm Tiếp nhận trước thì người đó nhận'),
      ('form_task', 'Giao một người điền thêm thông tin'),
      ('delegate_apply', 'Ủy quyền trong đơn (trường Ủy quyền) có hiệu lực; đặt sau bước quản lý duyệt'),
      ('delegate_revoke', 'Kết thúc các ủy quyền của tiến trình này (vd sau khi hết ngày nghỉ)'),
      ('user_status', 'Đặt trạng thái trên chat (vd Nghỉ phép đến ngày...), tự hết hạn'),
    ]),
    ('action', Icons.touch_app_outlined, kGroupPeople, 'Chờ người dùng thao tác', insertActionItems),
    ('process', Icons.view_timeline_outlined, kGroupProcess, 'Tiến trình', insertProcessItems),
    ('table', Icons.table_rows_outlined, kGroupTable, 'Bảng', insertTableItems),
    ('logic', Icons.call_split_rounded, kGroupLogic, 'Điều khiển luồng', [
      ('condition', 'Đi đường khác nhau theo điều kiện'),
      ('parallel', 'Nhiều tiến trình cùng lúc, đủ hết mới đi tiếp'),
      ('wait', 'Chờ một khoảng thời gian rồi đi tiếp'),
      ('wait_event', 'Chờ tới khi dữ liệu ứng dụng thoả điều kiện (vd ngân hàng báo đã chuyển tiền)'),
      ('calc', 'Tạo biến từ phép tính: cộng, tổng / max / min / đếm theo bảng, số ngày, đầu / cuối tháng, nếu-thì, cộng dồn'),
      ('set', 'Đặt biến của luồng từ biểu thức, sửa trường biểu mẫu, hoặc lấy số chứng từ tự tăng (vd PC-2026-0001)'),
      ('progress', 'Cập nhật thanh tiến độ của tiến trình: phần trăm + nhãn (vd 30% Xe đang tới, Lỗi)'),
      ('geo_distance', 'Khoảng cách (m) từ vị trí người bấm tới vị trí công ty cố định; dùng để rẽ nhánh (vd chấm công ngoài 200 m)'),
      ('start_flow', 'Mở tiến trình của quy trình khác, điền sẵn thông tin từ tiến trình này'),
    ]),
    ('message', Icons.chat_bubble_outline_rounded, kGroupMessage, 'Tin nhắn', [
      ('chat_post', 'Gửi tin vào nhóm / cho người tạo tiến trình, đính kèm tệp từ đường dẫn (vd chứng từ ngân hàng)'),
      ('note_add', 'Dán ghi chú lên một tin nhắn (ghi lại để bước sau sửa)'),
      ('note_edit', 'Sửa ghi chú đã thêm ở bước trước'),
      ...insertCardItems,
      ('compose', 'Soạn thư / tin có định dạng (đậm, màu, bảng, link) có chèn dữ liệu, để gửi email hoặc tin nhắn'),
    ]),
    ('ai', Icons.auto_awesome_rounded, kGroupAi, 'AI', [
      ('ai', 'Trợ lý AI kiểm tra, đối chiếu, lập chứng từ'),
    ]),
  ];

  bool _collapsed(String key) => _remember.contains(key);

  void _toggle(String key) => setState(() => _collapsed(key) ? _remember.remove(key) : _remember.add(key));

  Widget _tile(Pal pal, IconData icon, Color color, String title, String sub, Object value, {bool enabled = true}) => ListTile(
        enabled: enabled,
        dense: true,
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: enabled ? 0.14 : 0.06), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: enabled ? color : pal.sub, size: 20),
        ),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? pal.text : pal.sub)),
        subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: enabled ? () => Navigator.pop(context, value) : null,
      );

  Widget _group(Pal pal, String key, IconData icon, Color color, String title, List<Widget> children, {int? count}) {
    final open = _q.isNotEmpty || !_collapsed(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: _q.isEmpty ? () => _toggle(key) : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: color))),
            if (count != null) Text('$count', style: TextStyle(fontSize: 12, color: pal.sub)),
            if (_q.isEmpty) Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: pal.sub),
          ]),
        ),
      ),
      if (open) ...children,
    ]);
  }

  bool _match(String a, [String b = '']) => _q.isEmpty || '$a $b'.toLowerCase().contains(_q.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    // Lần đầu: ứng dụng MCP thu gọn (bấm vào mới hiện tool).
    if (!_seeded) {
      _seeded = true;
      _remember.add('start');
      for (final a in widget.apps) {
        _remember.add('mcp:${a['name']}');
      }
    }
    final have = {for (final x in widget.starts) if (x is Map) '${x['type']}'};
    final startItems = [for (final t in startTypes) if (_match(startTypeLabel(t.$1), tr(t.$3))) t];
    final sections = <Widget>[
      if (startItems.isNotEmpty)
        _group(pal, 'start', Icons.play_circle_outline_rounded, kGroupStart, tr('Bắt đầu'), [
          for (final (type, icon, desc) in startItems)
            _tile(pal, icon, kGroupStart, startTypeLabel(type), singleStartTypes.contains(type) && have.contains(type) ? tr('Quy trình đã có bước này') : tr(desc),
                {'start': type},
                enabled: !(singleStartTypes.contains(type) && have.contains(type))),
        ]),
      for (final (key, icon, color, title, items) in _groups)
        if (items.any((it) => _match(stepLook(it.$1).$3, tr(it.$2))))
          _group(pal, key, icon, color, tr(title), [
            for (final (type, desc) in items)
              if (!supersededTypes.contains(type) && _match(stepLook(type).$3, tr(desc))) _tile(pal, stepLook(type).$1, stepLook(type).$2, stepLook(type).$3, tr(desc), type),
          ]),
      // Mỗi ứng dụng MCP (ERP, ngân hàng, hoá đơn...) một nhóm, danh sách lấy từ cấu hình.
      if (widget.gatewayError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(tr('Không đọc được danh sách công cụ từ Flygo Gateway: {0}', ['${widget.gatewayError}']), style: const TextStyle(color: kFlowRed, fontSize: 12.5)),
        ),
      for (final app in widget.apps)
        if (_match('${app['label']}') || [for (final t in (app['tools'] as List? ?? const [])) if (t is Map) t].any((t) => _match(toolTitle(t), '${t['name']} ${t['description']}')))
          Builder(builder: (context) {
            final tools = [for (final t in (app['tools'] as List? ?? const [])) if (t is Map) t];
            final shown = _match('${app['label']}') ? tools : [for (final t in tools) if (_match(toolTitle(t), '${t['name']} ${t['description']}')) t];
            return _group(pal, 'mcp:${app['name']}', Icons.extension_outlined, kGroupApp, '${app['label']}', [
              if (app['error'] != null)
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(tr('Không kết nối được: {0}', ['${app['error']}']), style: const TextStyle(color: kFlowRed, fontSize: 12.5))),
              if (tools.isEmpty && app['error'] == null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(tr('Ứng dụng chưa có công cụ nào'), style: TextStyle(color: pal.sub))),
              for (final t in shown)
                _tile(
                  pal,
                  t['read_only'] == true ? Icons.search_rounded : Icons.edit_rounded,
                  kGroupApp,
                  toolTitle(t),
                  t['allowed'] == true ? '${t['description'] ?? ''}' : tr('Có ghi dữ liệu, chưa được cho phép trong cấu hình'),
                  {'mcp': app['name'], 'tool': t['name']},
                  enabled: t['allowed'] == true,
                ),
            ], count: tools.length);
          }),
    ];
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Text(tr('Thêm bước'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded, size: 20), hintText: tr('Tìm bước, công cụ…'), isDense: true, border: const OutlineInputBorder()),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
          ]),
        ),
        Expanded(
          child: sections.isEmpty
              ? Center(child: Text(tr('Không thấy bước nào'), style: TextStyle(color: pal.sub)))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: sections),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------- điều kiện

/// Hộp dựng điều kiện của một nhánh bằng giao diện: các nhóm "tất cả đều đúng" (VÀ), giữa các nhóm là HOẶC.
/// Trả về biểu thức máy chủ, hoặc '\u0000delete' khi xoá nhánh.
class CondDialog extends StatefulWidget {
  final AppState app;
  final String expr;
  final List<CondVar> vars;
  final bool canDelete;
  const CondDialog({super.key, required this.app, required this.expr, required this.vars, this.canDelete = false});
  @override
  State<CondDialog> createState() => _CondDialogState();
}

class _CondDialogState extends State<CondDialog> {
  late CondGroups groups;
  /// Biểu thức do bot AI viết, không dựng lại được bằng giao diện: giữ nguyên cho tới khi người dùng bấm "Làm lại".
  bool advanced = false;
  int _gen = 0;
  /// Biểu thức đang gõ (chế độ "Viết biểu thức").
  late String _text = widget.expr;
  /// Vừa chuyển sang giao diện mà biểu thức không dựng lại được: báo đã làm lại từ đầu.
  bool _reset = false;

  @override
  void initState() {
    super.initState();
    final g = condFromExpr(widget.expr);
    advanced = g == null;
    groups = (g == null || g.isEmpty) ? [[_newTerm()]] : g;
  }

  void _mode(bool expr) => setState(() {
        _gen++;
        _reset = false;
        if (expr) {
          if (_valid) _text = condToExpr(groups);
        } else {
          final g = condFromExpr(_text);
          _reset = g == null && _text.trim().isNotEmpty;
          groups = (g == null || g.isEmpty) ? [[_newTerm()]] : g;
        }
        advanced = expr;
      });

  CondVar? _var(String path) => widget.vars.where((v) => v.path == path).firstOrNull;

  Object? _defaultValue(CondVar? v) => switch (v?.type) {
        'bool' => true,
        'select' => v!.options.firstOrNull ?? '',
        'number' || 'money' => 0,
        'date' => DateTime.now().toIso8601String().substring(0, 10),
        _ => '',
      };

  CondTerm _newTerm() {
    final v = widget.vars.where((v) => v.type == 'money' || v.type == 'number').firstOrNull ?? widget.vars.firstOrNull;
    return CondTerm(v?.path ?? '', v == null ? '==' : condOps(v.type).first, _defaultValue(v));
  }

  bool _filled(CondTerm t) => switch (t.value) {
        null => false,
        CondRef r => r.path.isNotEmpty,
        String s => s.trim().isNotEmpty,
        List l => l.isNotEmpty,
        _ => true,
      };

  bool get _valid => groups.isNotEmpty && groups.every((g) => g.isNotEmpty && g.every((t) => t.path.isNotEmpty && _filled(t)));

  /// Vế phải: giá trị, hoặc một thông tin khác cùng kiểu.
  Widget _valueField(CondTerm t, CondVar? v) {
    final other = t.value is CondRef;
    final same = [for (final x in widget.vars) if (x.path != t.path && (v == null || _sameKind(x.type, v.type))) x];
    final toggle = t.op == 'in' || same.isEmpty
        ? null
        : IconButton(
            key: ValueKey('${identityHashCode(t)}-ref-$_gen'),
            tooltip: other ? tr('So với một giá trị') : tr('So với thông tin khác'),
            icon: Icon(other ? Icons.edit_rounded : Icons.compare_arrows_rounded, size: 18),
            onPressed: () => setState(() => t.value = other ? _defaultValue(v) : CondRef(same.first.path)),
          );
    final field = other
        ? DropdownButtonFormField<String>(
            key: ValueKey('${identityHashCode(t)}-refv-$_gen'),
            initialValue: same.any((x) => x.path == (t.value as CondRef).path) ? (t.value as CondRef).path : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Thông tin khác'), border: const OutlineInputBorder(), isDense: true),
            items: [for (final x in same) DropdownMenuItem(value: x.path, child: Text(x.label, overflow: TextOverflow.ellipsis))],
            onChanged: (p) => setState(() => t.value = CondRef(p!)),
          )
        : _plainValue(t, v);
    if (toggle == null) return field;
    return Row(children: [Expanded(child: field), toggle]);
  }

  static bool _sameKind(String a, String b) {
    String k(String t) => switch (t) { 'number' || 'money' => 'num', 'date' => 'date', 'bool' => 'bool', _ => 'text' };
    return k(a) == k(b);
  }

  Widget _plainValue(CondTerm t, CondVar? v) {
    final key = ValueKey('${identityHashCode(t)}-${t.path}-${t.op}-$_gen');
    switch (v?.type) {
      case 'bool':
        return SegmentedButton<bool>(
          key: key,
          segments: [ButtonSegment(value: true, label: Text(tr('Có'))), ButtonSegment(value: false, label: Text(tr('Không')))],
          selected: {t.value == true},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => t.value = s.first),
        );
      case 'select' when t.op == 'in':
        final cur = [for (final x in (t.value is List ? t.value as List : const [])) '$x'];
        return Wrap(key: key, spacing: 4, runSpacing: 4, children: [
          for (final o in v!.options)
            FilterChip(label: Text(o), selected: cur.contains(o), onSelected: (on) => setState(() => t.value = on ? [...cur, o] : ([...cur]..remove(o)))),
        ]);
      case 'select':
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: v!.options.contains('${t.value}') ? '${t.value}' : null,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [for (final o in v.options) DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis))],
          onChanged: (x) => setState(() => t.value = x),
        );
      case 'number' || 'money':
        final money = v!.type == 'money';
        return TextFormField(
          key: key,
          initialValue: t.value is num ? (money ? vnNumber(t.value as num) : '${t.value}') : '',
          keyboardType: TextInputType.number,
          inputFormatters: money ? [MoneyInputFormatterLite()] : null,
          decoration: InputDecoration(suffixText: money ? 'đ' : null, border: const OutlineInputBorder(), isDense: true),
          onChanged: (x) => setState(() => t.value = money ? (parseMoney(x) ?? 0) : (num.tryParse(x.replaceAll(',', '.')) ?? 0)),
        );
      case 'date':
        return OutlinedButton.icon(
          key: key,
          icon: const Icon(Icons.event_rounded, size: 18),
          label: Text(condValueLabel(t.value, v)),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: DateTime.tryParse('${t.value}') ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (d != null) setState(() => t.value = d.toIso8601String().substring(0, 10));
          },
        );
      case 'user':
        final people = widget.app.users.values.where((u) => !u.isBot).toList()..sort((a, b) => a.displayName.compareTo(b.displayName));
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: people.any((u) => u.id == t.value) ? '${t.value}' : null,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [for (final u in people) DropdownMenuItem(value: u.id, child: Text(u.displayName.isEmpty ? u.username : u.displayName, overflow: TextOverflow.ellipsis))],
          onChanged: (x) => setState(() => t.value = x),
        );
      default:
        return TextFormField(
          key: key,
          initialValue: '${t.value ?? ''}',
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          onChanged: (x) => setState(() => t.value = x),
        );
    }
  }

  Widget _term(Pal pal, List<CondTerm> g, CondTerm t) {
    final v = _var(t.path);
    final ops = condOps(v?.type ?? 'text');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('${identityHashCode(t)}-var-$_gen'),
            initialValue: v?.path,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Thông tin'), border: const OutlineInputBorder(), isDense: true),
            items: [for (final x in widget.vars) DropdownMenuItem(value: x.path, child: Text(x.label, overflow: TextOverflow.ellipsis))],
            onChanged: (p) => setState(() {
              final nv = _var(p!);
              t.path = p;
              if (!condOps(nv?.type ?? 'text').contains(t.op)) t.op = condOps(nv?.type ?? 'text').first;
              t.value = _defaultValue(nv);
            }),
          ),
        ),
        IconButton(
          tooltip: tr('Bỏ điều kiện này'),
          onPressed: () => setState(() {
            g.remove(t);
            if (g.isEmpty && groups.length > 1) groups.remove(g);
            if (groups.every((x) => x.isEmpty)) groups = [[_newTerm()]];
          }),
          icon: Icon(Icons.close_rounded, size: 18, color: pal.sub),
        ),
      ]),
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 132,
          child: DropdownButtonFormField<String>(
            key: ValueKey('${identityHashCode(t)}-op-${t.path}-$_gen'),
            initialValue: t.op,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: [for (final o in ops) DropdownMenuItem(value: o, child: Text(condOpLabel(o, v?.type ?? ''), overflow: TextOverflow.ellipsis))],
            onChanged: (o) => setState(() {
              final wasIn = t.op == 'in';
              t.op = o!;
              if (wasIn != (o == 'in')) t.value = o == 'in' ? [if (_filled(t) && t.value is! List) t.value] : _defaultValue(v);
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _valueField(t, v)),
      ]),
    ]);
  }

  Widget _tag(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: c)),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    const andColor = Color(0xFF3B82F6), orColor = Color(0xFFE5508A);
    final expr = condToExpr(groups);
    return AlertDialog(
      title: Text(tr('Điều kiện của nhánh')),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<bool>(
              segments: [ButtonSegment(value: false, label: Text(tr('Chọn bằng giao diện'))), ButtonSegment(value: true, label: Text(tr('Viết biểu thức')))],
              selected: {advanced},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _mode(v.first),
            ),
            const SizedBox(height: 12),
            if (advanced) ...[
              ExprField(key: ValueKey('cond-expr-$_gen'), label: tr('Điều kiện'), value: _text, vars: widget.vars, lines: 3, onChanged: (v) => setState(() => _text = v)),
            ] else ...[
              if (_reset)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr('Biểu thức có phép tính / hàm nên không dựng lại được bằng giao diện: làm lại từ đầu, hoặc chọn "Viết biểu thức" để giữ.'),
                      style: const TextStyle(color: kFlowOrange, fontSize: 12.5)),
                ),
              if (widget.vars.isEmpty)
                Text(tr('Chưa có thông tin nào để so sánh. Thêm trường ở bước "Nhập dữ liệu" trước.'), style: const TextStyle(color: kFlowOrange)),
              for (var gi = 0; gi < groups.length; gi++) ...[
                if (gi > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: _tag(tr('HOẶC'), orColor))),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 4, 4),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (groups[gi].length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(tr('Tất cả điều kiện sau đều đúng'), style: TextStyle(fontSize: 12, color: pal.sub, fontWeight: FontWeight.w600)),
                      ),
                    for (var ti = 0; ti < groups[gi].length; ti++) ...[
                      if (ti > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Align(alignment: Alignment.centerLeft, child: _tag(tr('VÀ'), andColor))),
                      _term(pal, groups[gi], groups[gi][ti]),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.vars.isEmpty ? null : () => setState(() => groups[gi].add(_newTerm())),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(tr('VÀ thêm điều kiện')),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.vars.isEmpty ? null : () => setState(() => groups.add([_newTerm()])),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('HOẶC thêm nhóm điều kiện')),
              ),
              if (_valid)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(tr('Đi nhánh này khi: {0}', [condLabel(expr, widget.vars, userName: (id) => _userName(widget.app, id))]), style: TextStyle(color: pal.sub, fontSize: 12.5)),
                ),
            ],
            const SizedBox(height: 8),
          ]),
        ),
      ),
      actions: [
        if (widget.canDelete) TextButton(onPressed: () => Navigator.pop(context, '\u0000delete'), child: Text(tr('Xoá nhánh'), style: const TextStyle(color: kFlowRed))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: advanced
              ? (checkExpr(_text).ok ? () => Navigator.pop(context, _text.trim()) : null)
              : (_valid ? () => Navigator.pop(context, expr) : null),
          child: Text(tr('Xong')),
        ),
      ],
    );
  }
}

/// Gõ số tiền có dấu chấm ngăn cách.
class MoneyInputFormatterLite extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final t = vnNumber(int.parse(digits));
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

// ---------------------------------------------------------------------------------------------- chọn người

/// Hộp chọn "ai": người tạo luồng / một vai trò / những người cụ thể.
Future<Object?> pickWho(BuildContext context, AppState app, Map<String, List<String>> roles, Object? current) =>
    showDialog<Object>(context: context, builder: (_) => _WhoDialog(app: app, roles: roles, current: current));

class _WhoDialog extends StatefulWidget {
  final AppState app;
  final Map<String, List<String>> roles;
  final Object? current;
  const _WhoDialog({required this.app, required this.roles, required this.current});
  @override
  State<_WhoDialog> createState() => _WhoDialogState();
}

class _WhoDialogState extends State<_WhoDialog> {
  late String kind;
  String? role;
  late Set<String> users;
  int level = 1;
  String? dept;
  String? field;
  String q = '';

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    dept = c is Map ? c['department'] as String? : null;
    field = c is Map ? c['field'] as String? : null;
    kind = c is Map && c['department'] != null
        ? 'department'
        : c is Map && c['field'] != null
        ? 'field'
        : c is Map && c['manager'] != null
        ? 'manager'
        : (c is Map && c['role'] != null ? 'role' : (c is Map ? 'users' : 'requester'));
    level = c is Map ? ((c['level'] as num?)?.toInt() ?? 1) : 1;
    role = c is Map ? c['role'] as String? : null;
    users = c is Map ? {if (c['user'] != null) '${c['user']}', for (final u in (c['users'] as List? ?? const [])) '$u'} : {};
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final roleNames = {...widget.roles.keys, ..._roleNames.keys, ?role}.toList()..sort();
    final people = widget.app.users.values.where((u) => !u.isBot && (q.isEmpty || '${u.displayName} ${u.username}'.toLowerCase().contains(q.toLowerCase()))).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return AlertDialog(
      title: Text(tr('Chọn người')),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, label) in [
              ('requester', tr('Người tạo')),
              ('manager', tr('Quản lý của người tạo')),
              ('department', tr('Cả phòng ban')),
              ('field', tr('Người trong tiến trình')),
              ('role', tr('Vai trò')),
              ('users', tr('Người cụ thể')),
            ])
              ChoiceChip(label: Text(label), selected: kind == k, onSelected: (_) => setState(() => kind = k)),
          ]),
          const SizedBox(height: 12),
          if (kind == 'requester') Text(tr('Người tạo tiến trình (người điền biểu mẫu).'), style: TextStyle(color: pal.sub)),
          if (kind == 'department')
            (editorCtx?.depts ?? const []).isEmpty
                ? Text(tr('Chưa có sơ đồ tổ chức. Vào Quản lý quy trình → Tổ chức để thêm phòng ban.'), style: const TextStyle(color: kFlowOrange))
                : Expanded(
                    child: RadioGroup<String>(
                      groupValue: dept,
                      onChanged: (v) => setState(() => dept = v),
                      child: ListView(children: [
                        for (final d in editorCtx!.depts)
                          RadioListTile<String>(
                            value: '${d['id']}',
                            title: Text('${d['name']}'),
                            subtitle: Text(tr('{0} người', [(d['members'] as List? ?? const []).length + (d['manager'] == null ? 0 : 1)])),
                          ),
                      ]),
                    ),
                  ),
          if (kind == 'field') ...[
            Text(tr('Người được chọn ở biểu mẫu, hoặc người đã tiếp nhận / đã duyệt ở bước trước.'), style: TextStyle(color: pal.sub)),
            const SizedBox(height: 6),
            Expanded(
              child: RadioGroup<String>(
                groupValue: field,
                onChanged: (v) => setState(() => field = v),
                child: ListView(children: [
                  for (final v in (editorCtx?.vars ?? const <CondVar>[]).where((x) => x.type == 'user'))
                    RadioListTile<String>(value: v.path, title: Text(v.label)),
                ]),
              ),
            ),
          ],
          if (kind == 'manager') ...[
            Text(tr('Theo sơ đồ tổ chức: trưởng phòng của người tạo. Người tạo là trưởng phòng thì lên quản lý phòng cấp trên.'), style: TextStyle(color: pal.sub)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final lv in [1, 2, 3])
                ChoiceChip(label: Text(lv == 1 ? tr('Trực tiếp') : tr('Cấp {0}', [lv])), selected: level == lv, onSelected: (_) => setState(() => level = lv)),
            ]),
          ],
          if (kind == 'role')
            Expanded(
              child: RadioGroup<String>(
                groupValue: role,
                onChanged: (v) => setState(() => role = v),
                child: ListView(children: [
                for (final r in roleNames)
                  RadioListTile<String>(
                    value: r,
                    title: Text(roleLabel(r)),
                    subtitle: Text(widget.roles[r]?.isNotEmpty ?? false
                        ? [for (final id in widget.roles[r]!) _userName(widget.app, id)].join(', ')
                        : tr('Chưa có ai giữ vai trò này')),
                  ),
                ]),
              ),
            ),
          if (kind == 'users') ...[
            TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm người'), isDense: true, border: const OutlineInputBorder()), onChanged: (v) => setState(() => q = v)),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(children: [
                for (final u in people)
                  CheckboxListTile(
                    value: users.contains(u.id),
                    onChanged: (v) => setState(() => v == true ? users.add(u.id) : users.remove(u.id)),
                    secondary: Avatar(userId: u.id, name: u.displayName, size: 32, status: false),
                    title: Text(u.displayName.isEmpty ? u.username : u.displayName),
                    dense: true,
                  ),
              ]),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: (kind == 'role' && role == null) || (kind == 'users' && users.isEmpty) || (kind == 'department' && dept == null) || (kind == 'field' && field == null)
              ? null
              : () => Navigator.pop(
                    context,
                    switch (kind) {
                      'role' => {'role': role},
                      'manager' => {'manager': r'$requester', if (level > 1) 'level': level},
                      'department' => {'department': dept},
                      'field' => {'field': field},
                      'users' => users.length == 1 ? {'user': users.first} : {'users': users.toList()},
                      _ => r'$requester',
                    }),
          child: Text(tr('Chọn')),
        ),
      ],
    );
  }
}

/// Một ô "ai" (người duyệt, người làm...): bấm để đổi.
class WhoField extends StatelessWidget {
  final AppState app;
  final Map<String, List<String>> roles;
  final String label;
  final Object? value;
  final ValueChanged<Object> onChanged;
  final VoidCallback? onClear;
  const WhoField({super.key, required this.app, required this.roles, required this.label, required this.value, required this.onChanged, this.onClear});

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4)),
        child: Row(children: [
          Icon(value is Map && (value as Map)['role'] != null ? Icons.badge_outlined : Icons.person_outline_rounded, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(value == null ? tr('Chưa chọn') : whoLabel(value, app))),
          if (onClear != null && value != null) IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18)),
          TextButton(
            onPressed: () async {
              final r = await pickWho(context, app, roles, value);
              if (r != null) onChanged(r);
            },
            child: Text(tr('Đổi')),
          ),
        ]),
      );
}

/// Danh sách "ai" (người nhận thông báo, ai được tạo luồng).
class WhoListField extends StatelessWidget {
  final AppState app;
  final Map<String, List<String>> roles;
  final List value;
  final String emptyLabel;
  final ValueChanged<List> onChanged;
  const WhoListField({super.key, required this.app, required this.roles, required this.value, required this.onChanged, this.emptyLabel = ''});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (value.isEmpty && emptyLabel.isNotEmpty) Chip(label: Text(emptyLabel)),
        for (var i = 0; i < value.length; i++) InputChip(label: Text(whoLabel(value[i], app)), onDeleted: () => onChanged([...value]..removeAt(i))),
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 18),
          label: Text(tr('Thêm')),
          onPressed: () async {
            final r = await pickWho(context, app, roles, null);
            if (r != null) onChanged([...value, r]);
          },
        ),
      ]);
}

// ---------------------------------------------------------------------------------------------- cấu hình bước

class StepConfigSheet extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic> node;
  final List<FlowField> form;
  final Map<String, List<String>> roles;
  /// Thông tin chèn được vào nội dung (trường biểu mẫu, kết quả AI).
  final List<CondVar> vars;
  /// Bot AI / máy chủ MCP / Kết nối AI lấy từ máy chủ Flows (rỗng: hiện ô gõ tay).
  final Map<String, dynamic> integ;
  /// Mở ở khung cột phải (máy tính): Xong / Hủy / Xoá gọi hàm này thay vì đóng bảng trượt.
  final void Function(Object? result)? onDone;
  const StepConfigSheet(
      {super.key, required this.app, required this.node, required this.form, required this.roles, this.vars = const [], this.integ = const {}, this.onDone});
  @override
  State<StepConfigSheet> createState() => _StepConfigSheetState();
}

class _StepConfigSheetState extends State<StepConfigSheet> {
  late final Map<String, dynamic> n = jsonDecode(jsonEncode(widget.node)) as Map<String, dynamic>;

  void _finish(Object? r) => widget.onDone != null ? widget.onDone!(r) : Navigator.pop(context, r);

  String get type => n['type'] == 'auto' && const {'mcp', 'note_add', 'note_edit', 'delegate_set', 'user_status', 'chat_post'}.contains(n['action']) ? '${n['action']}' : '${n['type']}';

  Widget _gap() => const SizedBox(height: 14);

  Widget _text(String key, String label, {int lines = 1, String? hint, String? helper}) => TextFormField(
        initialValue: '${n[key] ?? ''}',
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 4,
        decoration: InputDecoration(labelText: label, hintText: hint, helperText: helper, helperMaxLines: 3, border: const OutlineInputBorder(), alignLabelWithHint: lines > 1),
        onChanged: (v) => v.trim().isEmpty ? n.remove(key) : n[key] = v,
      );

  Widget _due(String key, String label, {bool allowNone = true}) {
    final cur = n[key] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final d in ['4h', '8h', '24h', '1wd', '2wd', '3wd', '5wd', '7d'])
          ChoiceChip(label: Text(durLabel(d)), selected: cur == d, onSelected: (_) => setState(() => n[key] = d)),
        if (allowNone) ChoiceChip(label: Text(tr('Không hạn')), selected: cur == null, onSelected: (_) => setState(() => n.remove(key))),
      ]),
    ]);
  }

  /// Nhắc lại tới khi xong (sau hạn; không có hạn thì từ lúc giao việc).
  Widget _remind() {
    final cur = n['remind'] as String?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Nhắc lại tới khi xong'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ChoiceChip(label: Text(tr('Không nhắc lại')), selected: cur == null, onSelected: (_) => setState(() => n.remove('remind'))),
        for (final d in ['2h', '4h', '24h', '1wd'])
          ChoiceChip(label: Text(tr('Mỗi {0}', [durLabel(d)])), selected: cur == d, onSelected: (_) => setState(() => n['remind'] = d)),
      ]),
    ]);
  }

  List<Widget> _approval() {
    final esc = n['escalate'] as Map?;
    final editable = [for (final k in (n['editable'] as List? ?? const [])) '$k'];
    return [
      Text(tr('Trường người duyệt được sửa trước khi duyệt'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in widget.form.where((f) => f.calc == null))
          FilterChip(
            label: Text(f.label),
            selected: editable.contains(f.key),
            onSelected: (v) => setState(() {
              final next = v ? [...editable, f.key] : ([...editable]..remove(f.key));
              next.isEmpty ? n.remove('editable') : n['editable'] = next;
            }),
          ),
      ]),
      _gap(),
      WhoField(app: widget.app, roles: widget.roles, label: tr('Người duyệt'), value: n['approver'], onChanged: (w) => setState(() => n['approver'] = w)),
      _gap(),
      Text(tr('Khi có nhiều người duyệt'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: [ButtonSegment(value: 'any', label: Text(tr('Một người duyệt là đủ'))), ButtonSegment(value: 'all', label: Text(tr('Tất cả phải duyệt')))],
        selected: {'${n['mode'] ?? 'any'}'},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => s.first == 'any' ? n.remove('mode') : n['mode'] = s.first),
      ),
      _gap(),
      _due('due', tr('Hạn duyệt')),
      _gap(),
      _remind(),
      _gap(),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Quá hạn thì chuyển lên người khác')),
        value: esc != null,
        onChanged: (v) => setState(() => v ? n['escalate'] = {'after': '48h', 'to': {'role': 'giam_doc'}} : n.remove('escalate')),
      ),
      if (esc != null) ...[
        WhoField(app: widget.app, roles: widget.roles, label: tr('Chuyển lên'), value: esc['to'], onChanged: (w) => setState(() => esc['to'] = w)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          Text(tr('sau'), style: const TextStyle(height: 2.4)),
          for (final d in ['24h', '48h', '3d', '7d']) ChoiceChip(label: Text(durLabel(d)), selected: esc['after'] == d, onSelected: (_) => setState(() => esc['after'] = d)),
        ]),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Cho phép trả lại để sửa')),
        subtitle: Text(tr('Người duyệt có nút "Trả lại", người tạo sửa rồi nộp lại')),
        value: n['allow_return'] != false,
        onChanged: (v) => setState(() => v ? n.remove('allow_return') : n['allow_return'] = false),
      ),
    ];
  }

  List<Widget> _formTask() {
    final fields = [for (final f in (n['fields'] as List? ?? const [])) if (f is Map) f.cast<String, dynamic>()];
    return [
      WhoField(app: widget.app, roles: widget.roles, label: tr('Người làm'), value: n['assignee'], onChanged: (w) => setState(() => n['assignee'] = w)),
      _gap(),
      _due('due', tr('Hạn làm')),
      _gap(),
      _remind(),
      _gap(),
      Text(tr('Thông tin cần điền'), style: Theme.of(context).textTheme.labelLarge),
      for (var i = 0; i < fields.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(_fieldIcon('${fields[i]['type']}')),
          title: Text('${fields[i]['label'] ?? fields[i]['key']}'),
          subtitle: Text(tr(_fieldTypes['${fields[i]['type']}'] ?? '')),
          onTap: () async {
            final r = await showDialog<Object>(context: context, builder: (_) => FieldDialog(field: fields[i], taken: {for (final f in fields) '${f['key']}'}));
            if (r == null) return;
            setState(() {
              r == 'delete' ? fields.removeAt(i) : fields[i] = r as Map<String, dynamic>;
              n['fields'] = fields;
            });
          },
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('Thêm trường')),
          onPressed: () async {
            final r = await showDialog<Object>(context: context, builder: (_) => FieldDialog(taken: {for (final f in fields) '${f['key']}'}));
            if (r is Map<String, dynamic>) setState(() => n['fields'] = [...fields, r]);
          },
        ),
      ),
    ];
  }

  List<Widget> _ai() {
    final runner = (n['runner'] as Map?)?.cast<String, dynamic>() ?? {'kind': 'bot'};
    n['runner'] = runner;
    final out = (n['output_schema'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['output_schema'] = out;
    final input = [for (final x in (n['input'] as List? ?? const [])) '$x'];
    final agents = [for (final a in (widget.integ['agents'] as List? ?? const [])) if (a is Map) a];
    final creds = [for (final c in (widget.integ['ai_credentials'] as List? ?? const [])) if (c is Map) c];
    return [
      SegmentedButton<String>(
        segments: [ButtonSegment(value: 'bot', label: Text(tr('Giao trợ lý AI (bot)'))), ButtonSegment(value: 'api', label: Text(tr('Gọi API AI')))],
        selected: {'${runner['kind']}'},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => n['runner'] = s.first == 'bot' ? {'kind': 'bot', 'bot': ''} : {'kind': 'api', 'credential': ''}),
      ),
      const SizedBox(height: 10),
      if (runner['kind'] == 'bot' && agents.isNotEmpty)
        DropdownButtonFormField<String>(
          key: const ValueKey('bot-pick'),
          initialValue: agents.any((a) => a['username'] == runner['bot']) ? '${runner['bot']}' : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Bot AI'), helperText: tr('Bot làm việc bằng công cụ của nó (ERP, ngân hàng, hoá đơn...)'), border: const OutlineInputBorder()),
          items: [
            for (final a in agents)
              DropdownMenuItem(value: '${a['username']}', child: Text('${a['name'] ?? a['username']} (@${a['username']})', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => runner['bot'] = v),
        )
      else if (runner['kind'] == 'bot')
        TextFormField(
          key: const ValueKey('bot'),
          initialValue: '${runner['bot'] ?? ''}',
          decoration: InputDecoration(labelText: tr('Tên bot'), hintText: 'ketoan-ai', helperText: tr('Bot làm việc bằng công cụ của nó (ERP, ngân hàng, hoá đơn...)'), border: const OutlineInputBorder()),
          onChanged: (v) => runner['bot'] = v.trim(),
        )
      else ...[
        if (creds.isNotEmpty)
          DropdownButtonFormField<String>(
            key: const ValueKey('cred-pick'),
            initialValue: creds.any((c) => c['name'] == runner['credential']) ? '${runner['credential']}' : null,
            decoration: InputDecoration(labelText: tr('Kết nối AI'), border: const OutlineInputBorder()),
            items: [for (final c in creds) DropdownMenuItem(value: '${c['name']}', child: Text('${c['name']} · ${c['model']}'))],
            onChanged: (v) => setState(() => runner['credential'] = v),
          )
        else
        TextFormField(
          key: const ValueKey('cred'),
          initialValue: '${runner['credential'] ?? ''}',
          decoration: InputDecoration(labelText: tr('Kết nối AI'), helperText: tr('Tên kết nối API đã lưu của công ty'), border: const OutlineInputBorder()),
          onChanged: (v) => runner['credential'] = v.trim(),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: '${runner['model'] ?? ''}',
          decoration: InputDecoration(labelText: tr('Mô hình (để trống = mặc định)'), border: const OutlineInputBorder()),
          onChanged: (v) => v.trim().isEmpty ? runner.remove('model') : runner['model'] = v.trim(),
        ),
      ],
      _gap(),
      TemplateField(label: tr('Giao cho AI xử lý'), raw: '${n['prompt'] ?? ''}', vars: widget.vars, lines: 4, onChanged: (v) => n['prompt'] = v),
      _gap(),
      Text(tr('AI được xem'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final f in widget.form)
          FilterChip(
            label: Text(f.label),
            selected: input.contains('form.${f.key}'),
            onSelected: (v) => setState(() => n['input'] = v ? [...input, 'form.${f.key}'] : (input..remove('form.${f.key}'))),
          ),
      ]),
      _gap(),
      Text(tr('AI trả về'), style: Theme.of(context).textTheme.labelLarge),
      for (final k in out.keys.toList())
        Row(children: [
          Expanded(child: Text(k)),
          DropdownButton<String>(
            value: '${out[k]}',
            items: [for (final t in const ['bool', 'number', 'money', 'text', 'json']) DropdownMenuItem(value: t, child: Text(_outLabel(t)))],
            onChanged: (t) => setState(() => out[k] = t),
          ),
          IconButton(onPressed: () => setState(() => out.remove(k)), icon: const Icon(Icons.close_rounded, size: 18)),
        ]),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('Thêm kết quả')),
          onPressed: () async {
            final ctl = TextEditingController();
            final k = await showDialog<String>(
              context: context,
              builder: (d) => AlertDialog(
                title: Text(tr('Tên kết quả')),
                content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'khop, so_phieu...'), onSubmitted: (v) => Navigator.pop(d, v)),
                actions: [FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Thêm')))],
              ),
            );
            final key = slugKey(k ?? '');
            if (key.isNotEmpty) setState(() => out[key] = 'text');
          },
        ),
      ),
      _gap(),
      WhoField(
        app: widget.app,
        roles: widget.roles,
        label: tr('Người xác nhận trước khi AI ghi dữ liệu'),
        value: n['write_approval'],
        onChanged: (w) => setState(() => n['write_approval'] = w),
        onClear: () => setState(() => n.remove('write_approval')),
      ),
    ];
  }

  String _outLabel(String t) => switch (t) { 'bool' => tr('Đúng / sai'), 'number' => tr('Số'), 'money' => tr('Số tiền'), 'json' => 'JSON', _ => tr('Chữ') };

  static const _noteColors = {'yellow': Color(0xFFE0B400), 'green': Color(0xFF2EAD6B), 'blue': Color(0xFF3B82F6), 'pink': Color(0xFFE5508A), 'purple': Color(0xFF8B5CF6), 'orange': Color(0xFFF07B1E)};

  Widget _colorPick(Map<String, dynamic> p, {bool allowKeep = false}) => Wrap(spacing: 8, children: [
        if (allowKeep)
          ChoiceChip(label: Text(tr('Giữ màu')), selected: '${p['color'] ?? ''}'.isEmpty, onSelected: (_) => setState(() => p['color'] = '')),
        for (final e in _noteColors.entries)
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => setState(() => p['color'] = e.key),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: e.value.withValues(alpha: 0.25), shape: BoxShape.circle, border: Border.all(color: e.value, width: p['color'] == e.key ? 3 : 1)),
              child: p['color'] == e.key ? Icon(Icons.check_rounded, size: 16, color: e.value) : null,
            ),
          ),
      ]);

  /// Chọn tin nhắn: tin do một bước trước gửi vào nhóm, hoặc id tin lấy từ thông tin của luồng.
  Widget _msgPicker(Map<String, dynamic> m) {
    final senders = [
      for (final s in editorCtx?.steps ?? const <FStep>[])
        if (sendsMessage(s)) s,
    ];
    final textVars = [for (final v in widget.vars) if (v.type == 'text') v];
    final cur = m['step'] != null ? 'step:${m['step']}' : (m['post_id'] != null ? 'var:${m['post_id']}' : null);
    final items = [
      for (final s in senders) DropdownMenuItem(value: 'step:${s.id}', child: Text(tr('Tin của bước "{0}"', [s.name]), overflow: TextOverflow.ellipsis)),
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
      onChanged: (v) => setState(() {
        m
          ..remove('step')
          ..remove('post_id');
        if (v == null) return;
        v.startsWith('step:') ? m['step'] = v.substring(5) : m['post_id'] = v.substring(4);
      }),
    );
  }

  List<Widget> _noteAdd() {
    final p = (n['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['params'] = p;
    final m = (p['message'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    p['message'] = m;
    return [
      Text(tr('Tên bước là tên ghi chú: bước "Sửa ghi chú" sau này chọn theo tên này.'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
      _gap(),
      _msgPicker(m),
      _gap(),
      TemplateField(label: tr('Nội dung ghi chú'), raw: '${p['text'] ?? ''}', vars: widget.vars, lines: 3, onChanged: (v) => p['text'] = v),
      _gap(),
      Text(tr('Màu'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      _colorPick(p),
    ];
  }

  List<Widget> _noteEdit() {
    final p = (n['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['params'] = p;
    final notes = [for (final s in editorCtx?.steps ?? const <FStep>[]) if (s.kind == 'note_add') s];
    return [
      DropdownButtonFormField<String>(
        initialValue: notes.any((s) => s.id == p['note_step']) ? '${p['note_step']}' : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: tr('Ghi chú cần sửa (theo tên bước thêm ghi chú)'),
          helperText: notes.isEmpty ? tr('Chưa có bước "Thêm ghi chú" nào phía trước.') : null,
          border: const OutlineInputBorder(),
        ),
        items: [for (final s in notes) DropdownMenuItem(value: s.id, child: Text(s.name.isEmpty ? s.id : s.name))],
        onChanged: (v) => setState(() => p['note_step'] = v),
      ),
      _gap(),
      TemplateField(label: tr('Nội dung mới (để trống = giữ nguyên)'), raw: '${p['text'] ?? ''}', vars: widget.vars, lines: 3, onChanged: (v) => p['text'] = v),
      _gap(),
      Text(tr('Màu'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      _colorPick(p, allowKeep: true),
    ];
  }

  List<Widget> _buttons() {
    final m = (n['message'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['message'] = m;
    final bs = [for (final b in (n['buttons'] as List? ?? const [])) if (b is Map) b.cast<String, dynamic>()];
    n['buttons'] = bs;
    return [
      _msgPicker(m),
      _gap(),
      Text(tr('Các nút (bộ nút này thay cho nút cũ trên tin; để trống = xoá hết nút)'), style: Theme.of(context).textTheme.labelLarge),
      for (var i = 0; i < bs.length; i++)
        Container(
          key: ValueKey('btn-$i-${bs.length}'),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(border: Border.all(color: Pal.of(context).divider), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: '${bs[i]['label'] ?? ''}',
                  decoration: InputDecoration(labelText: tr('Tên nút'), isDense: true, border: const OutlineInputBorder()),
                  onChanged: (v) => bs[i]['label'] = v.trim(),
                ),
              ),
              IconButton(onPressed: () => setState(() => bs.removeAt(i)), icon: const Icon(Icons.close_rounded, size: 18)),
            ]),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: [ButtonSegment(value: false, label: Text(tr('Chạy tiếp quy trình'))), ButtonSegment(value: true, label: Text(tr('Mở link')))],
              selected: {bs[i]['url'] != null},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => v.first ? bs[i]['url'] = '' : (bs[i]..remove('url')).remove('sign')),
            ),
            if (bs[i]['url'] != null) ...[
              const SizedBox(height: 6),
              TemplateField(label: tr('Link'), raw: '${bs[i]['url']}', vars: widget.vars, lines: 1, onChanged: (v) => bs[i]['url'] = v),
              FlowSignEditor(key: ValueKey('bs-${identityHashCode(bs[i])}'), button: bs[i], vars: widget.vars, onChanged: () => setState(() {})),
            ],
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: () => setState(() => bs.add({'label': ''})), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm nút'))),
      ),
      Text(tr('Có nút "Chạy tiếp quy trình" thì tiến trình chờ ở bước này tới khi có người bấm. Bước sau rẽ nhánh theo "Nút đã bấm".'),
          style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
      _gap(),
      WhoField(
        app: widget.app,
        roles: widget.roles,
        label: tr('Ai được bấm (để trống = ai thấy tin cũng bấm được)'),
        value: n['who'],
        onChanged: (w) => setState(() => n['who'] = w),
        onClear: () => setState(() => n.remove('who')),
      ),
    ];
  }

  /// Chờ sự kiện: công cụ + tham số, điều kiện trên kết quả, chu kỳ kiểm tra, thời hạn chờ.
  List<Widget> _waitEvent() {
    final servers = [for (final m in (widget.integ['mcp'] as List? ?? const [])) if (m is Map) m];
    final srv = servers.where((m) => m['name'] == mcpKeyOf(n)).firstOrNull;
    final tools = [for (final t in (srv?['tools'] as List? ?? const [])) if (t is Map) t];
    final tool = tools.where((t) => t['name'] == n['tool']).firstOrNull;
    final props = ((tool?['input_schema'] as Map?)?['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final args = (n['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final out = (((tool?['output_schema'] as Map?)?['properties'] as Map?) ?? const {}).cast<String, dynamic>();
    final rv = [
      for (final e in out.entries)
        CondVar('result.${e.key}', '${tr('Kết quả')} › ${(e.value as Map?)?['title'] ?? e.key}',
            switch ((e.value as Map?)?['type']) { 'number' || 'integer' => 'number', 'boolean' => 'bool', _ => 'text' }),
    ];
    final cond = '${n['cond'] ?? ''}';
    final secs = (n['seconds'] as num?)?.toInt() ?? 300;
    final byKey = n['match'] is Map;
    final mode = SegmentedButton<bool>(
      segments: [
        ButtonSegment(value: false, label: Text(tr('Hỏi công cụ định kỳ'))),
        ButtonSegment(value: true, label: Text(tr('Chờ sự kiện theo khoá'))),
      ],
      selected: {byKey},
      showSelectedIcon: false,
      onSelectionChanged: (v) => setState(() {
        if (v.first) {
          for (final k in const ['server', 'app', 'tool', 'args', 'cond', 'seconds', 'progress', 'call_timeout']) {
            n.remove(k);
          }
          n['match'] = <String, dynamic>{'key': '', 'source': 'any'};
        } else {
          n.remove('match');
          n['server'] = '';
          n['tool'] = '';
          n['cond'] = '';
          n['seconds'] = 300;
        }
      }),
    );
    if (byKey) return [mode, _gap(), ..._eventMatch()];
    if (servers.isEmpty) return [mode, _gap(), Text(tr('Máy chủ Flows chưa khai báo ứng dụng MCP nào.'), style: const TextStyle(color: kFlowOrange))];
    n['args'] = args;
    return [
      mode,
      _gap(),
      DropdownButtonFormField<String>(
        initialValue: srv == null ? null : '${srv['name']}',
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Ứng dụng'), border: const OutlineInputBorder()),
        items: [for (final m in servers) DropdownMenuItem(value: '${m['name']}', child: Text('${m['label']}'))],
        onChanged: (v) => setState(() {
          setMcpKey(n, servers, v);
          n['tool'] = '';
          args.clear();
        }),
      ),
      _gap(),
      DropdownButtonFormField<String>(
        key: ValueKey('we-${mcpKeyOf(n)}'),
        initialValue: tool == null ? null : '${tool['name']}',
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Công cụ (đọc dữ liệu)'), helperText: tool == null ? null : '${tool['description'] ?? ''}', helperMaxLines: 3, border: const OutlineInputBorder()),
        items: [for (final t in tools) DropdownMenuItem(value: '${t['name']}', enabled: t['allowed'] == true, child: Text(toolTitle(t), overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() {
          n['tool'] = v;
          args.clear();
        }),
      ),
      for (final e in props.entries) ...[
        const SizedBox(height: 10),
        TemplateField(
          key: ValueKey('we-arg-${n['tool']}-${e.key}'),
          label: '${(e.value as Map?)?['title'] ?? e.key}',
          raw: '${args[e.key] ?? ''}',
          vars: widget.vars,
          lines: 1,
          onChanged: (v) => v.isEmpty ? args.remove(e.key) : args[e.key] = v,
        ),
      ],
      _gap(),
      Text(tr('Đi tiếp khi'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        icon: const Icon(Icons.rule_rounded, size: 18),
        label: Text(cond.isEmpty ? tr('Đặt điều kiện trên kết quả') : condLabel(cond, rv), maxLines: 3),
        onPressed: rv.isEmpty
            ? null
            : () async {
                final r = await showDialog<String>(context: context, builder: (_) => CondDialog(app: widget.app, expr: cond, vars: rv));
                if (r != null && r != '\u0000delete') setState(() => n['cond'] = r);
              },
      ),
      if (tool != null && rv.isEmpty) Text(tr('Công cụ chưa khai báo khuôn kết quả (outputSchema) nên chưa đặt được điều kiện.'), style: const TextStyle(color: kFlowOrange, fontSize: 12.5)),
      _gap(),
      Text(tr('Kiểm tra mỗi'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in [60, 300, 900, 3600, 21600])
          ChoiceChip(label: Text(intervalLabel(s)), selected: secs == s, onSelected: (_) => setState(() => n['seconds'] = s)),
      ]),
      _gap(),
      _due('timeout', tr('Chờ tối đa (quá hạn thì đi tiếp với "Hết thời gian chờ")')),
    ];
  }

  /// Chờ sự kiện theo khoá: khoá (mẫu), nguồn, nhóm (nguồn tin nhắn), hạn chờ.
  List<Widget> _eventMatch() {
    final m = (n['match'] as Map).cast<String, dynamic>();
    n['match'] = m;
    final src = '${m['source'] ?? 'any'}';
    final chans = [for (final c in (m['channels'] as List? ?? const [])) '$c'];
    final app = widget.app;
    return [
      TemplateField(key: const ValueKey('we-key'), label: tr('Khoá sự kiện (vd TAU-{{số PO}})'), raw: '${m['key'] ?? ''}', vars: widget.vars, lines: 1, onChanged: (v) => m['key'] = v),
      _gap(),
      Text(tr('Nguồn'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in eventSources.entries)
          ChoiceChip(
            label: Text(tr(e.value)),
            selected: src == e.key,
            onSelected: (_) => setState(() {
              m['source'] = e.key;
              if (e.key != 'chat' && e.key != 'any') m.remove('channels');
            }),
          ),
      ]),
      if (src == 'chat' || src == 'any') ...[
        _gap(),
        Text(tr('Đọc thẻ #<khoá> trong các nhóm'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in chans)
            InputChip(
              label: Text(app.channels[id] == null ? tr('Nhóm đã xoá') : app.channelTitle(app.channels[id]!)),
              onDeleted: () => setState(() {
                final next = [for (final c in chans) if (c != id) c];
                next.isEmpty ? m.remove('channels') : m['channels'] = next;
              }),
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr('Thêm nhóm')),
            onPressed: () async {
              final groups = app.channels.values.where((c) => (c.type == 'O' || c.type == 'P') && !c.isProcess && !chans.contains(c.id)).toList()
                ..sort((a, b) => app.channelTitle(a).compareTo(app.channelTitle(b)));
              final id = await showDialog<String>(
                context: context,
                builder: (d) => SimpleDialog(
                  title: Text(tr('Chọn nhóm')),
                  children: [for (final c in groups) SimpleDialogOption(onPressed: () => Navigator.pop(d, c.id), child: Text(app.channelTitle(c)))],
                ),
              );
              if (id != null) setState(() => m['channels'] = [...chans, id]);
            },
          ),
        ]),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          tr('Sự kiện tới qua webhook sự kiện (link ở trang quản trị) hoặc tin nhắn có thẻ #<khoá> trong các nhóm đã chọn (Flow Bot phải ở trong nhóm). Sự kiện tới trước khi có bước chờ được giữ vài ngày.'),
          style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5),
        ),
      ),
      _gap(),
      _due('timeout', tr('Chờ tối đa (quá hạn thì đi tiếp với "Hết thời gian chờ")')),
    ];
  }

  /// Bước Tính toán: danh sách biến, chạm để sửa, thêm biến (biến sau dùng được biến trước).
  List<Widget> _calc() {
    final vars = [for (final v in (n['vars'] as List? ?? const [])) if (v is Map) v.cast<String, dynamic>()];
    n['vars'] = vars;
    List<CondVar> before(int i) => [...widget.vars.where((v) => !v.path.startsWith('steps.${n['id']}.')), ...calcVars('${n['id']}', '${n['name'] ?? ''}', vars.take(i).toList())];
    Future<void> edit(int? i) async {
      final r = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => CalcVarDialog(
          app: widget.app,
          value: i == null ? null : vars[i],
          vars: before(i ?? vars.length),
          form: widget.form,
          taken: {for (final v in vars) '${v['name']}'},
        ),
      );
      if (r == null) return;
      setState(() {
        if (r.containsKey('\u0000delete')) {
          vars.removeAt(i!);
        } else if (i == null) {
          vars.add(r);
        } else {
          vars[i] = r;
        }
      });
    }

    final pal = Pal.of(context);
    return [
      Text(tr('Mỗi biến là một phép tính chọn sẵn. Kết quả dùng ở các bước sau (rẽ nhánh, nội dung, tham số) với tên "{0} › tên biến".', ['${n['name'] ?? tr('Tính toán')}']),
          style: TextStyle(color: pal.sub, fontSize: 12.5)),
      _gap(),
      for (var i = 0; i < vars.length; i++)
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          color: pal.surface2,
          child: ListTile(
            leading: Icon(Icons.functions_rounded, color: kGroupLogic),
            title: Text(calcSummary(vars[i], before(i), widget.form)),
            subtitle: Text(calcOpLabel('${vars[i]['op']}')),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => edit(i),
          ),
        ),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => edit(null), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm biến')))),
    ];
  }

  /// Bộ ba ủy quyền: không có cấu hình, chỉ giải thích.
  List<Widget> _delegationTrio() => [
        Text(
          tr('Ủy quyền gồm trường "Ủy quyền" trong biểu mẫu (người tạo đơn điền: mỗi dòng một người nhận thay và các quy trình) cùng hai bước không cần cài đặt:\n'
              '• Áp dụng ủy quyền: tự động, đặt sau bước quản lý duyệt; ủy quyền có hiệu lực từ ngày bắt đầu tới hết ngày kết thúc, tiến trình đang chờ tự chuyển cho người nhận thay.\n'
              '• Thu hồi ủy quyền: kết thúc ủy quyền của tiến trình này (vd sau bước chờ hết ngày nghỉ).'),
          style: TextStyle(color: Pal.of(context).text, height: 1.4),
        ),
      ];

  /// Ủy quyền ở bước giao việc: cho phép / không cho / chỉ người có vai trò.
  List<Widget> _delegation() {
    final d = (n['delegation'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mode = d['off'] == true ? 'off' : (d['role'] != null ? 'role' : 'on');
    final roles = widget.roles.keys.toList()..sort();
    return [
      _gap(),
      DropdownButtonFormField<String>(
        initialValue: mode,
        decoration: InputDecoration(labelText: tr('Khi người được giao đang vắng (ủy quyền)'), border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem(value: 'on', child: Text(tr('Người được ủy quyền nhận thay'))),
          DropdownMenuItem(value: 'role', child: Text(tr('Chỉ nhận thay nếu có vai trò...'))),
          DropdownMenuItem(value: 'off', child: Text(tr('Không cho ủy quyền (chờ đúng người)'))),
        ],
        onChanged: (v) => setState(() {
          if (v == 'off') {
            n['delegation'] = {'off': true};
          } else if (v == 'role') {
            n['delegation'] = {'role': roles.firstOrNull ?? ''};
          } else {
            n.remove('delegation');
          }
        }),
      ),
      if (mode == 'role') ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: roles.contains(d['role']) ? '${d['role']}' : null,
          decoration: InputDecoration(labelText: tr('Vai trò của người nhận thay'), border: const OutlineInputBorder()),
          items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(roleLabel(r)))],
          onChanged: (v) => setState(() => n['delegation'] = {'role': v}),
        ),
      ],
    ];
  }

  /// Chọn một thông tin của luồng (theo kiểu) làm giá trị mẫu "{{đường dẫn}}".
  Widget _varPick(String label, Map p, String key, Set<String> types, {String? helper}) {
    final vars = [for (final v in widget.vars) if (types.contains(v.type)) v];
    final cur = '${p[key] ?? ''}';
    final path = cur.startsWith('{{') && cur.endsWith('}}') ? cur.substring(2, cur.length - 2).trim() : '';
    return DropdownButtonFormField<String>(
      initialValue: vars.any((v) => v.path == path) ? path : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 2, border: const OutlineInputBorder()),
      items: [for (final v in vars) DropdownMenuItem(value: v.path, child: Text(v.label, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => setState(() => p[key] = v == null ? '' : '{{$v}}'),
    );
  }

  List<Widget> _delegateSet() {
    final p = (n['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['params'] = p;
    final rules = [for (final r in (p['rules'] as List? ?? const [])) if (r is Map) r.cast<String, dynamic>()];
    p['rules'] = rules;
    final flows = editorCtx?.flows ?? const [];
    String flowName(String id) => '${flows.where((f) => f['id'] == id).firstOrNull?['name'] ?? id}';
    Set<String> usedElsewhere(int i) => {for (var j = 0; j < rules.length; j++) if (j != i) ...[for (final f in (rules[j]['flows'] as List? ?? const [])) '$f']};
    return [
      Text(tr('Đặt bước này sau bước cấp trên duyệt. Người nghỉ là người tạo tiến trình; mỗi dòng giao tiến trình của họ ở các quy trình đã chọn cho một người trong khoảng ngày.'),
          style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
      _gap(),
      _varPick(tr('Từ ngày'), p, 'from', {'date'}),
      _gap(),
      _varPick(tr('Đến ngày (hết ngày này)'), p, 'until', {'date'}),
      _gap(),
      Text(tr('Giao bước theo quy trình'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      // Bảng: mỗi dòng nhiều quy trình → một người nhận thay.
      Container(
        decoration: BoxDecoration(border: Border.all(color: Pal.of(context).divider), borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            color: Pal.of(context).surface2,
            padding: const EdgeInsets.fromLTRB(12, 8, 48, 8),
            child: Row(children: [
              Expanded(child: Text(tr('Các quy trình'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('Giao cho'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
            ]),
          ),
          for (var i = 0; i < rules.length; i++) ...[
            if (i > 0) Divider(height: 1, color: Pal.of(context).divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _pickRuleFlows(rules[i], flows, usedElsewhere(i)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            (rules[i]['flows'] as List? ?? const []).isEmpty
                                ? tr('Các quy trình còn lại')
                                : [for (final f in (rules[i]['flows'] as List)) flowName('$f')].join(', '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down_rounded, color: Pal.of(context).sub),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _personCell(rules[i])),
                IconButton(
                  tooltip: tr('Xoá dòng'),
                  onPressed: rules.length <= 1 ? null : () => setState(() => rules.removeAt(i)),
                  icon: const Icon(Icons.delete_outline_rounded, color: kFlowRed, size: 20),
                ),
              ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 4),
      Text(tr('"Giao cho" lấy từ trường kiểu Người trong biểu mẫu. Một quy trình chỉ nằm ở một dòng; chỉ một dòng "Các quy trình còn lại".'),
          style: TextStyle(color: Pal.of(context).sub, fontSize: 12)),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => rules.add({'flows': <String>[], 'delegate': ''})),
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('Thêm dòng ủy quyền')),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Chuyển cả tiến trình đang chờ')),
        subtitle: Text(tr('Tiến trình đã tới người nghỉ trước đó cũng giao thêm cho người nhận thay (khi ủy quyền đã bắt đầu)')),
        value: p['pending'] == true,
        onChanged: (v) => setState(() => p['pending'] = v),
      ),
    ];
  }

  /// Ô "Giao cho" của bảng ủy quyền: một trường kiểu Người của biểu mẫu.
  Widget _personCell(Map<String, dynamic> rule) {
    final vars = [for (final v in widget.vars) if (v.type == 'user') v];
    final cur = '${rule['delegate'] ?? ''}';
    final path = cur.startsWith('{{') && cur.endsWith('}}') ? cur.substring(2, cur.length - 2).trim() : '';
    return DropdownButtonFormField<String>(
      initialValue: vars.any((v) => v.path == path) ? path : null,
      isExpanded: true,
      hint: Text(tr('Chọn')),
      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.fromLTRB(10, 10, 4, 10)),
      items: [for (final v in vars) DropdownMenuItem(value: v.path, child: Text(v.label, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => setState(() => rule['delegate'] = v == null ? '' : '{{$v}}'),
    );
  }

  /// Chọn nhiều quy trình cho một dòng (quy trình đã ở dòng khác thì không chọn được).
  Future<void> _pickRuleFlows(Map<String, dynamic> rule, List<Map<String, dynamic>> flows, Set<String> taken) async {
    final sel = {for (final f in (rule['flows'] as List? ?? const [])) '$f'};
    final r = await showDialog<Set<String>>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr('Các quy trình')),
          content: SizedBox(
            width: 420,
            height: 440,
            child: ListView(children: [
              CheckboxListTile(
                dense: true,
                value: sel.isEmpty,
                title: Text(tr('Các quy trình còn lại')),
                subtitle: Text(tr('Mọi quy trình không nằm ở dòng khác')),
                onChanged: (_) => set(sel.clear),
              ),
              const Divider(height: 1),
              for (final f in flows)
                CheckboxListTile(
                  dense: true,
                  enabled: !taken.contains(f['id']),
                  value: sel.contains(f['id']),
                  title: Text('${f['icon'] ?? ''} ${f['name']}'.trim()),
                  subtitle: taken.contains(f['id']) ? Text(tr('Đã ở dòng khác')) : null,
                  onChanged: (v) => set(() => v == true ? sel.add('${f['id']}') : sel.remove('${f['id']}')),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(d, sel), child: Text(tr('Xong'))),
          ],
        ),
      ),
    );
    if (r != null) setState(() => rule['flows'] = r.toList());
  }

  /// Báo tiến độ: phần trăm (chèn được thông tin), nhãn, kiểu (thường / thành công / cảnh báo / lỗi).
  List<Widget> _progress() => [
        TemplateField(label: tr('Phần trăm (0–100)'), raw: '${n['percent'] ?? ''}', vars: widget.vars, lines: 1, onChanged: (v) => n['percent'] = v),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('Bỏ trống = giữ phần trăm cũ, chỉ đổi nhãn.'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12)),
        ),
        _gap(),
        TemplateField(label: tr('Nhãn tiến độ'), raw: '${n['label'] ?? ''}', vars: widget.vars, lines: 1, onChanged: (v) => n['label'] = v),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('Vd: Đang xử lý, Đã đặt xe, Xe đang tới, Lỗi, Xe hủy.'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12)),
        ),
        _gap(),
        DropdownButtonFormField<String>(
          initialValue: const {'', 'ok', 'warn', 'error'}.contains(n['tone'] ?? '') ? '${n['tone'] ?? ''}' : '',
          decoration: InputDecoration(labelText: tr('Kiểu'), border: const OutlineInputBorder()),
          items: [
            DropdownMenuItem(value: '', child: Text(tr('Thường (xanh)'))),
            DropdownMenuItem(value: 'ok', child: Text(tr('Thành công (xanh lá)'))),
            DropdownMenuItem(value: 'warn', child: Text(tr('Cảnh báo (cam)'))),
            DropdownMenuItem(value: 'error', child: Text(tr('Lỗi (đỏ)'))),
          ],
          onChanged: (v) => setState(() => (v ?? '').isEmpty ? n.remove('tone') : n['tone'] = v),
        ),
      ];

  /// Tính khoảng cách GPS: vị trí người bấm (trường Vị trí) → vị trí công ty cố định (người soạn đặt), bán kính.
  List<Widget> _geoDistance() {
    final pal = Pal.of(context);
    final locs = [for (final v in widget.vars) if (v.type == 'location') v];
    final from = '${n['from'] ?? ''}';
    if (from.isEmpty && locs.isNotEmpty) n['from'] = locs.first.path;
    String numText(Object? v) => v is num && v != 0 ? (v % 1 == 0 ? '${v.toInt()}' : '$v') : '';
    num? parse(String t) => num.tryParse(t.trim().replaceAll(',', '.'));
    return [
      if (locs.isEmpty)
        Text(tr('Chưa có trường kiểu Vị trí. Thêm trường Vị trí ở bước "Nhập dữ liệu" hoặc "Điền thông tin".'), style: const TextStyle(color: kFlowOrange))
      else
        DropdownButtonFormField<String>(
          initialValue: locs.any((v) => v.path == n['from']) ? '${n['from']}' : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Vị trí người bấm'), border: const OutlineInputBorder()),
          items: [for (final v in locs) DropdownMenuItem(value: v.path, child: Text(v.label, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => n['from'] = v),
        ),
      _gap(),
      Text(tr('Vị trí công ty (cố định)'), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextFormField(
            key: ValueKey('geo-lat-${n['lat']}'),
            initialValue: numText(n['lat']),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('Vĩ độ'), hintText: '21.0285', border: const OutlineInputBorder()),
            onChanged: (t) => n['lat'] = parse(t) ?? 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            key: ValueKey('geo-lon-${n['lon']}'),
            initialValue: numText(n['lon']),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('Kinh độ'), hintText: '105.8542', border: const OutlineInputBorder()),
            onChanged: (t) => n['lon'] = parse(t) ?? 0,
          ),
        ),
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.my_location_rounded, size: 18),
          label: Text(tr('Dùng vị trí hiện tại của máy này')),
          onPressed: () async {
            final p = await currentPosition(context);
            if (p == null || !mounted) return;
            setState(() {
              n['lat'] = double.parse(p.latitude.toStringAsFixed(6));
              n['lon'] = double.parse(p.longitude.toStringAsFixed(6));
            });
          },
        ),
      ),
      _gap(),
      TextFormField(
        initialValue: numText(n['radius']),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: tr('Bán kính cho phép (m)'), hintText: '200', helperText: tr('Để trống = không giới hạn'), border: const OutlineInputBorder()),
        onChanged: (t) {
          final r = parse(t);
          r == null || r <= 0 ? n.remove('radius') : n['radius'] = r;
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          tr('Khoảng cách tính trên máy chủ; dùng «… › Trong khu vực» hoặc «… › Khoảng cách (m)» ở bước Rẽ nhánh sau đó.'),
          style: TextStyle(color: pal.sub, fontSize: 12),
        ),
      ),
    ];
  }

  /// Gửi tin kèm tệp (auto chat_post): cho người tạo việc và / hoặc vào một nhóm; tệp tải từ đường dẫn.
  List<Widget> _chatPost() {
    final p = (n['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['params'] = p;
    final toReq = (p['to'] as List? ?? const []).contains(r'$requester');
    final ch = '${p['channel'] ?? ''}';
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Gửi cho người tạo tiến trình')),
        value: toReq,
        onChanged: (v) => setState(() => v ? p['to'] = [r'$requester'] : p.remove('to')),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.groups_outlined),
        title: Text(ch.isEmpty ? tr('Gửi vào nhóm (không bắt buộc)') : (widget.app.channels[ch] == null ? ch : widget.app.channelTitle(widget.app.channels[ch]!))),
        trailing: ch.isEmpty ? const Icon(Icons.add_rounded) : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => p.remove('channel'))),
        onTap: () async {
          final groups = widget.app.channels.values.where((c) => (c.type == 'O' || c.type == 'P') && !c.isProcess).toList()
            ..sort((a, b) => widget.app.channelTitle(a).compareTo(widget.app.channelTitle(b)));
          final id = await showDialog<String>(
            context: context,
            builder: (d) => SimpleDialog(
              title: Text(tr('Chọn nhóm')),
              children: [for (final c in groups) SimpleDialogOption(onPressed: () => Navigator.pop(d, c.id), child: Text(widget.app.channelTitle(c)))],
            ),
          );
          if (id != null) setState(() => p['channel'] = id);
        },
      ),
      Text(tr('Flow Bot phải là thành viên của nhóm.'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12)),
      _gap(),
      TemplateField(label: tr('Nội dung'), raw: '${p['text'] ?? ''}', vars: widget.vars, lines: 3, onChanged: (v) => p['text'] = v),
      _gap(),
      TemplateField(label: tr('Tệp đính kèm (đường dẫn, mỗi dòng một tệp)'), raw: '${p['files'] ?? ''}', vars: widget.vars, lines: 2, onChanged: (v) => v.trim().isEmpty ? p.remove('files') : p['files'] = v),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(tr('Vd đường dẫn tải (download_url) từ bước gọi công cụ ngân hàng. Chỉ tải từ địa chỉ được quản trị cho phép, tối đa 50 MB / tệp.'),
            style: TextStyle(color: Pal.of(context).sub, fontSize: 12)),
      ),
    ];
  }

  List<Widget> _userStatus() {
    final p = (n['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['params'] = p;
    final clear = p['clear'] == true;
    return [
      SegmentedButton<bool>(
        segments: [ButtonSegment(value: false, label: Text(tr('Đặt trạng thái'))), ButtonSegment(value: true, label: Text(tr('Xoá trạng thái')))],
        selected: {clear},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => v.first ? p['clear'] = true : p.remove('clear')),
      ),
      if (!clear) ...[
        _gap(),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in _statusEmoji.entries)
            ChoiceChip(label: Text(e.value, style: const TextStyle(fontSize: 18)), selected: p['emoji'] == e.key, onSelected: (_) => setState(() => p['emoji'] = e.key)),
        ]),
        _gap(),
        TemplateField(label: tr('Nội dung trạng thái'), raw: '${p['text'] ?? ''}', vars: widget.vars, lines: 1, onChanged: (v) => p['text'] = v),
        _gap(),
        _varPick(tr('Hết hạn vào (hết ngày này)'), p, 'until', {'date'}),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Bật Không làm phiền')),
          subtitle: Text(tr('Tắt thông báo của người này tới lúc hết hạn')),
          value: p['dnd'] == true,
          onChanged: (v) => setState(() => p['dnd'] = v),
        ),
      ],
      Text(tr('Trạng thái của người tạo tiến trình. Muốn đặt đúng ngày bắt đầu nghỉ thì thêm bước "Chờ" tới ngày đó ở phía trước.'),
          style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
    ];
  }

  List<Widget> _claim() => [
        WhoField(app: widget.app, roles: widget.roles, label: tr('Giao cho'), value: n['assignee'], onChanged: (w) => setState(() => n['assignee'] = w)),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('Mỗi người được giao thấy nút "Tiếp nhận". Ai bấm trước thì người đó nhận, những người khác không cần làm nữa. Bước sau giao cho "Người tiếp nhận" để làm tiếp.'),
              style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
        ),
        _gap(),
        _due('due', tr('Hạn tiếp nhận')),
        _gap(),
        _remind(),
      ];

  List<Widget> _notify() => [
        Text(tr('Gửi tới'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        WhoListField(app: widget.app, roles: widget.roles, value: [...(n['to'] as List? ?? const [])], onChanged: (v) => setState(() => n['to'] = v)),
        _gap(),
        Text(tr('Gửi thẻ vào nhóm (có nút Mở tiến trình)'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final id in [for (final c in (n['channels'] as List? ?? const [])) '$c'])
            InputChip(
              label: Text(widget.app.channels[id] == null ? id : widget.app.channelTitle(widget.app.channels[id]!)),
              onDeleted: () => setState(() => n['channels'] = [for (final c in (n['channels'] as List)) if (c != id) c]),
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr('Thêm nhóm')),
            onPressed: () async {
              final groups = widget.app.channels.values.where((c) => (c.type == 'O' || c.type == 'P') && !c.isProcess).toList()
                ..sort((a, b) => widget.app.channelTitle(a).compareTo(widget.app.channelTitle(b)));
              final id = await showDialog<String>(
                context: context,
                builder: (d) => SimpleDialog(
                  title: Text(tr('Chọn nhóm')),
                  children: [for (final c in groups) SimpleDialogOption(onPressed: () => Navigator.pop(d, c.id), child: Text(widget.app.channelTitle(c)))],
                ),
              );
              if (id != null) setState(() => n['channels'] = [...(n['channels'] as List? ?? const []), id]);
            },
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('Flow Bot phải là thành viên của nhóm.'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12)),
        ),
        _gap(),
        TemplateField(label: tr('Nội dung'), raw: '${n['text'] ?? ''}', vars: widget.vars, lines: 3, onChanged: (v) => n['text'] = v),
      ];

  /// Khuôn kết quả (khoá + kiểu) để bước sau dùng trong điều kiện / nội dung.
  Widget _outputs(Map<String, dynamic> out, String title) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        for (final k in out.keys.toList())
          Row(children: [
            Expanded(child: Text(k)),
            DropdownButton<String>(
              value: '${out[k]}',
              items: [for (final t in const ['bool', 'number', 'money', 'text', 'json']) DropdownMenuItem(value: t, child: Text(_outLabel(t)))],
              onChanged: (t) => setState(() => out[k] = t),
            ),
            IconButton(onPressed: () => setState(() => out.remove(k)), icon: const Icon(Icons.close_rounded, size: 18)),
          ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Thêm kết quả')),
            onPressed: () async {
              final ctl = TextEditingController();
              final k = await showDialog<String>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text(tr('Tên kết quả')),
                  content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
                  actions: [FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Thêm')))],
                ),
              );
              final key = slugKey(k ?? '');
              if (key.isNotEmpty) setState(() => out[key] = 'text');
            },
          ),
        ),
      ]);

  /// Bước "Gọi công cụ": chọn máy chủ MCP, tool, điền tham số theo khuôn của tool (không gõ JSON).
  /// [pages]: bước Đọc hết trang (chỉ công cụ chỉ đọc, không có khuôn kết quả, thêm cách lật trang).
  List<Widget> _mcp({bool pages = false}) {
    final servers = [for (final m in (widget.integ['mcp'] as List? ?? const [])) if (m is Map) m];
    final p = (n['params'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['params'] = p;
    final args = (p['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    p['args'] = args;
    final out = (n['output_schema'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    if (!pages) n['output_schema'] = out;
    final srv = servers.where((m) => m['name'] == mcpKeyOf(p)).firstOrNull;
    final tools = [for (final t in (srv?['tools'] as List? ?? const [])) if (t is Map) t];
    final tool = tools.where((t) => t['name'] == p['tool']).firstOrNull;
    final props = ((tool?['input_schema'] as Map?)?['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final req = [for (final r in ((tool?['input_schema'] as Map?)?['required'] as List? ?? const [])) '$r'];
    void pickTool(Map t) {
      p['tool'] = t['name'];
      args.removeWhere((k, _) => !(((t['input_schema'] as Map?)?['properties'] as Map?)?.containsKey(k) ?? false));
      if (pages) {
        n['paging'] = guessPaging(((t['input_schema'] as Map?)?['properties'] as Map?)?.keys.map((k) => '$k').toList() ?? const []);
        return;
      }
      // Tool có khai báo khuôn kết quả thì điền sẵn.
      final os = ((t['output_schema'] as Map?)?['properties'] as Map?) ?? const {};
      if (out.isEmpty) {
        for (final e in os.entries) {
          final ty = (e.value as Map?)?['type'];
          out['${e.key}'] = switch (ty) { 'boolean' => 'bool', 'number' || 'integer' => 'number', 'string' => 'text', _ => 'json' };
        }
      }
    }

    return [
      if (servers.isEmpty)
        Text(tr('Máy chủ Flows chưa khai báo máy chủ MCP nào (cấu hình "mcp"). Nhờ quản trị hệ thống thêm.'), style: const TextStyle(color: kFlowOrange))
      else ...[
        DropdownButtonFormField<String>(
          initialValue: srv == null ? null : '${srv['name']}',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Máy chủ công cụ'), border: const OutlineInputBorder()),
          items: [for (final m in servers) DropdownMenuItem(value: '${m['name']}', child: Text('${m['label']}${m['error'] != null ? ' (${tr('lỗi kết nối')})' : ''}'))],
          onChanged: (v) => setState(() {
            setMcpKey(p, servers, v);
            p['tool'] = '';
            args.clear();
          }),
        ),
        _gap(),
        DropdownButtonFormField<String>(
          key: ValueKey('tool-${mcpKeyOf(p)}'),
          initialValue: tool == null ? null : '${tool['name']}',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Công cụ'), helperText: tool == null ? null : '${tool['description']}', helperMaxLines: 3, border: const OutlineInputBorder()),
          items: [
            for (final t in tools)
              DropdownMenuItem(
                value: '${t['name']}',
                enabled: pages ? t['read_only'] == true : t['allowed'] == true,
                child: Text(
                    '${toolTitle(t)}${pages ? (t['read_only'] == true ? '' : ' (${tr('không phải công cụ chỉ đọc')})') : (t['allowed'] == true ? '' : ' (${tr('có ghi dữ liệu, chưa được cho phép')})')}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => pickTool(tools.firstWhere((t) => t['name'] == v))),
        ),
      ],
      if (props.isNotEmpty) ...[
        _gap(),
        Text(tr('Tham số'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final e in props.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(builder: (context) {
              final sch = (e.value as Map?)?.cast<String, dynamic>() ?? const {};
              final label = '${sch['title'] ?? e.key}${req.contains(e.key) ? ' *' : ''}';
              final enums = [for (final x in (sch['enum'] as List? ?? const [])) '$x'];
              if (sch['type'] == 'boolean') {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(label),
                  subtitle: sch['description'] == null ? null : Text('${sch['description']}'),
                  value: args[e.key] == true,
                  onChanged: (v) => setState(() => args[e.key] = v),
                );
              }
              if (enums.isNotEmpty) {
                return DropdownButtonFormField<String>(
                  initialValue: enums.contains(args[e.key]) ? '${args[e.key]}' : null,
                  decoration: InputDecoration(labelText: label, helperText: sch['description'] == null ? null : '${sch['description']}', border: const OutlineInputBorder()),
                  items: [for (final x in enums) DropdownMenuItem(value: x, child: Text(x))],
                  onChanged: (v) => setState(() => args[e.key] = v),
                );
              }
              // Chữ / số: gõ giá trị hoặc chèn thông tin của luồng.
              return TemplateField(
                key: ValueKey('arg-${p['tool']}-${e.key}'),
                label: sch['description'] == null ? label : '$label · ${sch['description']}',
                raw: '${args[e.key] ?? ''}',
                vars: widget.vars,
                lines: 1,
                onChanged: (v) {
                  final isNum = sch['type'] == 'number' || sch['type'] == 'integer';
                  args[e.key] = v.isEmpty ? null : (isNum && num.tryParse(v) != null ? num.parse(v) : v);
                  args.removeWhere((_, x) => x == null);
                },
              );
            }),
          ),
      ],
      _gap(),
      if (pages)
        PagesConfig(n: n, toolArgs: props.keys.toList(), onChanged: () => setState(() {}))
      else
        _outputs(out, tr('Kết quả dùng ở bước sau')),
    ];
  }

  List<Widget> _wait() {
    // Mốc: trường ngày, hoặc thuộc tính của tiến trình (vd ETA).
    final dates = [for (final v in widget.vars) if (v.type == 'date' || v.path.startsWith('process.props.')) v];
    // 0: chờ một khoảng, 1: chờ tới ngày (trường ngày), 2: chờ đến giờ trong ngày ("12:00").
    final mode = n['until'] == null ? 0 : (isClockText('${n['until']}') ? 2 : 1);
    final until = mode == 1;
    return [
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 0, label: Text(tr('Chờ một khoảng'))),
          ButtonSegment(value: 1, label: Text(tr('Chờ tới ngày'))),
          ButtonSegment(value: 2, label: Text(tr('Đến giờ trong ngày'))),
        ],
        selected: {mode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() {
          switch (s.first) {
            case 0:
              n.remove('until');
              n['for'] = '1d';
            case 1:
              n.remove('for');
              n['until'] = dates.firstOrNull?.path ?? '';
            default:
              n.remove('for');
              n['until'] = '12:00';
          }
        }),
      ),
      _gap(),
      if (mode == 2) ...[
        OutlinedButton.icon(
          icon: const Icon(Icons.schedule_rounded, size: 18),
          label: Text(tr('Chờ đến {0} hôm nay', ['${n['until']}'])),
          onPressed: () async {
            final p = '${n['until']}'.split(':');
            final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
            if (t != null) setState(() => n['until'] = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('Giờ Việt Nam. Tới bước này khi đã qua giờ đó thì đi tiếp ngay.'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
        ),
      ] else if (!until)
        _due('for', tr('Chờ trong'), allowNone: false)
      else if (dates.isEmpty)
        Text(tr('Biểu mẫu chưa có trường kiểu Ngày. Thêm trường Ngày ở bước "Nhập dữ liệu".'), style: const TextStyle(color: kFlowOrange))
      else
        DropdownButtonFormField<String>(
          initialValue: dates.any((d) => d.path == n['until']) ? '${n['until']}' : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Ngày lấy từ'), border: const OutlineInputBorder()),
          items: [for (final d in dates) DropdownMenuItem(value: d.path, child: Text(d.label, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => n['until'] = v),
        ),
      if (until) ...[_gap(), ...offsetField(context, n, () => setState(() {}))],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, kind) = stepLook(type);
    final pal = Pal.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(kind, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text))),
          TextButton.icon(
            onPressed: () => _finish('delete'),
            icon: const Icon(Icons.delete_outline_rounded, color: kFlowRed),
            label: Text(tr('Xoá bước'), style: const TextStyle(color: kFlowRed)),
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
          if (editorCtx?.doc case final d? when d.listOf('${n['id']}', d.cancelSteps) != null) ...[
            Container(
              key: const ValueKey('cancel-path-note'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: kFlowOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.cancel_outlined, size: 18, color: kFlowOrange),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('Thuộc nhánh khi luồng bị huỷ: chỉ bước tự động'), style: TextStyle(fontSize: 12.5, color: pal.text))),
              ]),
            ),
            _gap(),
          ],
          _text('name', tr('Tên bước')),
          _gap(),
          ...switch (type) {
            'approval' => [..._approval(), ..._delegation()],
            'form_task' => [..._formTask(), ..._delegation()],
            'delegate_set' => _delegateSet(),
            'calc' => _calc(),
            'progress' => _progress(),
            'geo_distance' => _geoDistance(),
            'chat_post' => _chatPost(),
            'wait_event' => _waitEvent(),
            'delegate_request' || 'delegate_approve' || 'delegate_revoke' || 'delegate_apply' => _delegationTrio(),
            'user_status' => _userStatus(),
            'ai' => _ai(),
            'notify' => _notify(),
            'wait' => _wait(),
            'mcp' => _mcp(),
            'mcp_pages' => _mcp(pages: true),
            'claim' => [..._claim(), ..._delegation()],
            'note_add' => _noteAdd(),
            'note_edit' => _noteEdit(),
            'buttons' => _buttons(),
            'approval_request' => [NodeConfig(app: widget.app, n: n, form: widget.form, roles: widget.roles, vars: widget.vars), ..._delegation()],
            'start_flow' => [StartFlowConfig(app: widget.app, node: n, vars: widget.vars, form: widget.form, onChanged: () => setState(() {}))],
            'set' => [SetConfig(n: n, vars: widget.vars, form: widget.form)],
            'compose' => [ComposeConfig(n: n, vars: widget.vars, onChanged: () => setState(() {}))],
            final t when tableNodeTypes.contains(t) => [TableConfig(n: n, vars: widget.vars, doc: editorCtx?.doc)],
            final t when editorNodeTypes.contains(t) => [NodeConfig(app: widget.app, n: n, form: widget.form, roles: widget.roles, vars: widget.vars)],
            _ => [Text(const JsonEncoder.withIndent('  ').convert(n), style: const TextStyle(fontSize: 12))],
          },
          // Khi lỗi: dừng / bỏ qua / giao người làm tay / rẽ sang nhánh Lỗi, cộng thời hạn mỗi lần gọi.
          // Cho chạy không cần duyệt: máy chủ không còn chặn lưu (duyệt do quy trình tự đặt bước Tạo phê duyệt), chỉ
          // hiện để xem / gỡ ở bước đã đặt từ trước.
          if (n['allow_without_approval'] != null) ...[
            _gap(),
            WaiverField(n: n, userName: (id) => _userName(widget.app, id), onChanged: () => setState(() {})),
          ],
          // Nút / nhãn / tệp thêm trên thẻ chat mà bước gửi (thẻ tiến trình: tự đồng bộ theo tiến trình).
          if (cardSendingTypes.contains(n['type']) || processCardStep(n)) ...[
            _gap(),
            CardExtraField(owner: n, vars: widget.vars, process: processCardStep(n), onChanged: () => setState(() {})),
          ],
          if (FStep.errorTypes.contains(n['type'])) ...[
            _gap(),
            ErrorPolicyField(
              app: widget.app,
              n: n,
              roles: widget.roles,
              label: switch (type) {
                'ai' => tr('Khi AI lỗi'),
                'mcp' => tr('Khi công cụ lỗi'),
                'wait_event' when n['match'] is Map => tr('Khi kho sự kiện lỗi'),
                'wait_event' => tr('Khi gọi công cụ lỗi'),
                'start_flow' => tr('Khi không tạo được / luồng kia lỗi'),
                'process_wait' => tr('Khi có tiến trình lỗi / bị huỷ'),
                'doc_render' => tr('Khi tạo tài liệu lỗi'),
                _ => tr('Khi bước lỗi'),
              },
              onChanged: () => setState(() {}),
            ),
          ],
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _finish(null), child: Text(tr('Hủy')))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: () => _finish(n), child: Text(tr('Xong')))),
          ]),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------- trường biểu mẫu

/// Danh sách trường của bước "Nhập dữ liệu": sắp xếp, thêm, sửa. Trả về danh sách mới khi bấm "Xong".
class FormFieldsSheet extends StatefulWidget {
  final List<Map<String, dynamic>> fields;
  /// Để chép trường từ quy trình khác (null: ẩn).
  final FlowsApi? api;
  final String flowId;
  final void Function(List<Map<String, dynamic>>? result)? onDone;
  const FormFieldsSheet({super.key, required this.fields, this.api, this.flowId = '', this.onDone});
  @override
  State<FormFieldsSheet> createState() => _FormFieldsSheetState();
}

class _FormFieldsSheetState extends State<FormFieldsSheet> {
  late final form = [...widget.fields];

  Future<void> _edit([int? i]) async {
    // Trường đứng trước (số) và tổng của bảng: nguồn cho trường tự tính; các trường khác: cho "Chỉ hiện khi".
    final before = i == null ? form : form.sublist(0, i);
    final sources = <Map<String, dynamic>>[
      for (final f in before)
        if ((f['type'] == 'money' || f['type'] == 'number')) f,
      for (final f in before)
        if (f['type'] == 'table')
          for (final c in (f['columns'] as List? ?? const []))
            if (c is Map && (c['type'] == 'money' || c['type'] == 'number'))
              {'key': '${f['key']}__tong.${c['key']}', 'label': tr('Tổng {0} ({1})', ['${c['label']}'.toLowerCase(), '${f['label']}']), 'type': c['type']},
    ];
    final others = [for (var j = 0; j < form.length; j++) if (j != i) form[j]];
    final condVars = [
      for (final f in FlowField.listOf(others))
        if (f.type != 'files' && f.type != 'table') CondVar('form.${f.key}', f.label, f.type, f.options),
    ];
    final r = await showDialog<Object>(
      context: context,
      builder: (_) => FieldDialog(field: i == null ? null : form[i], taken: {for (final f in form) '${f['key']}'}, siblings: sources, condVars: condVars, fillTargets: others),
    );
    if (r == null) return;
    setState(() {
      if (r == 'delete' && i != null) {
        form.removeAt(i);
      } else if (r is Map<String, dynamic>) {
        i == null ? form.add(r) : form[i] = r;
      }
    });
  }

  /// Thêm nhiều trường (mẫu có sẵn / chép): trùng mã thì thêm hậu tố _2, _3...
  void _append(List<Map<String, dynamic>> add) => setState(() {
        final keys = {for (final f in form) '${f['key']}'};
        for (final f in add) {
          var k = '${f['key']}';
          for (var n = 2; keys.contains(k); n++) {
            k = '${f['key']}_$n';
          }
          keys.add(k);
          form.add({...jsonDecode(jsonEncode(f)) as Map<String, dynamic>, 'key': k});
        }
      });

  Future<void> _quick(String v) async {
    if (v == 'copy') {
      final r = await copyFieldsFromFlow(context, widget.api!, widget.flowId);
      if (r != null) _append(r);
      return;
    }
    _append(fieldPresets()[int.parse(v)].$3);
  }

  String _sub(Map<String, dynamic> f) {
    final ff = FlowField.fromJson(f);
    if (ff.type == 'table') return tr('Bảng · cột: {0}', [ff.columns.map((c) => c.label).join(', ')]);
    return [
      tr(_fieldTypes[ff.type] ?? ff.type),
      if (ff.options.isNotEmpty) ff.options.join(' / '),
      if (ff.defaultValue != null) tr('mặc định: {0}', [showFieldValue(ff, ff.defaultValue)]),
      if (ff.hint.isNotEmpty) tr('gợi ý: {0}', [ff.hint]),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(children: [
          Icon(Icons.input_rounded, color: pal.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Nhập dữ liệu'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(tr('Các trường người tạo tiến trình điền khi bắt đầu. Kéo để đổi thứ tự.'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
      ),
      Expanded(
        child: form.isEmpty
            ? Center(child: Text(tr('Chưa có trường nào.'), style: TextStyle(color: pal.sub)))
            : ReorderableListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                buildDefaultDragHandles: false,
                onReorderItem: (a, b) => setState(() => form.insert(b, form.removeAt(a))),
                children: [
                  for (var i = 0; i < form.length; i++)
                    Card(
                      key: ValueKey('${form[i]['key']}'),
                      elevation: 0,
                      color: pal.surface,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: pal.divider)),
                      child: ListTile(
                        leading: Icon(_fieldIcon('${form[i]['type']}'), color: pal.accent),
                        title: Text('${form[i]['label'] ?? form[i]['key']}${form[i]['required'] == true ? ' *' : ''}', style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
                        subtitle: Text(_sub(form[i]), maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                        onTap: () => _edit(i),
                      ),
                    ),
                ],
              ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            OutlinedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm trường'))),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: tr('Thêm nhanh'),
              icon: const Icon(Icons.library_add_outlined),
              onSelected: _quick,
              itemBuilder: (_) => [
                for (final (i, (name, icon, _)) in fieldPresets().indexed)
                  PopupMenuItem(value: '$i', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(name))),
                if (widget.api != null)
                  PopupMenuItem(
                    value: 'copy',
                    child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.copy_all_rounded), title: Text(tr('Chép từ quy trình khác'))),
                  ),
              ],
            ),
            const Spacer(),
            TextButton(onPressed: () => widget.onDone != null ? widget.onDone!(null) : Navigator.pop(context), child: Text(tr('Hủy'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => widget.onDone != null ? widget.onDone!(form) : Navigator.pop(context, form), child: Text(tr('Xong'))),
          ]),
        ),
      ),
    ]);
  }
}

/// Sửa một trường: tên, kiểu, lựa chọn, bắt buộc, giá trị mặc định, gợi ý; trường bảng có danh sách cột.
/// [column]: đang sửa một cột của bảng ([siblings] = các cột khác, để chọn cho cột tự tính).
/// Trả về Map trường hoặc 'delete'.
class FieldDialog extends StatefulWidget {
  final Map<String, dynamic>? field;
  final Set<String> taken;
  final bool column;
  final List<Map<String, dynamic>> siblings;
  /// Thông tin dùng cho "Chỉ hiện khi" (rỗng: không có mục này). Trường / cột được điền thêm khi chọn từ danh mục.
  final List<CondVar> condVars;
  final List<Map<String, dynamic>> fillTargets;
  const FieldDialog({super.key, this.field, this.taken = const {}, this.column = false, this.siblings = const [], this.condVars = const [], this.fillTargets = const []});
  @override
  State<FieldDialog> createState() => _FieldDialogState();
}

const _calcOps = {'mul': '×', 'add': '+', 'sub': '−', 'div': '÷'};

class _FieldDialogState extends State<FieldDialog> {
  late final label = TextEditingController(text: '${widget.field?['label'] ?? ''}');
  late final hint = TextEditingController(text: '${widget.field?['hint'] ?? ''}');
  final option = TextEditingController();
  late final options = [for (final o in (widget.field?['options'] as List? ?? const [])) '$o'];
  late final columns = [for (final c in (widget.field?['columns'] as List? ?? const [])) if (c is Map) Map<String, dynamic>.of(c.cast<String, dynamic>())];
  // Cột tự tính hiện như một "kiểu" riêng trong danh sách.
  late String type = widget.field?['calc'] != null ? 'calc' : '${widget.field?['type'] ?? 'text'}';
  late bool required = widget.field?['required'] == true;
  late Object? def = widget.field?['default'];
  late final Map<String, dynamic> calc = {'op': 'mul', ...?(widget.field?['calc'] as Map?)?.cast<String, dynamic>()};
  late String currency = '${widget.field?['currency'] ?? ''}';
  late final List<String> period = [for (final k in (widget.field?['period'] as List? ?? const [])) '$k'];
  late String showIf = '${widget.field?['show_if'] ?? ''}';
  late Map<String, dynamic>? lookup = (widget.field?['lookup'] as Map?)?.cast<String, dynamic>();
  List<String> _lookupKeys = [];
  String? _lookupErr;
  int _gen = 0;

  String get key => widget.field != null ? '${widget.field!['key']}' : slugKey(label.text);

  /// Cột số nhập tay của cùng bảng (dùng được cho cột tự tính).
  List<Map<String, dynamic>> get _numericSiblings =>
      [for (final c in widget.siblings) if ((c['type'] == 'money' || c['type'] == 'number') && c['calc'] == null && c['key'] != key) c];

  Map<String, String> get _types => {
        for (final e in _fieldTypes.entries)
          if (!widget.column || !{'table', 'files', 'delegation', 'location', 'wifi', 'photo'}.contains(e.key)) e.key: e.value,
        if (widget.column) 'calc': 'Tự tính từ 2 cột',
        if (!widget.column && widget.siblings.isNotEmpty) 'calc': 'Tự tính từ 2 trường',
      };

  /// Trường Ủy quyền: thời gian lấy từ hai trường ngày của biểu mẫu.
  List<Widget> _periodEditor(Pal pal) {
    final dates = [for (final c in widget.siblings) if (c['type'] == 'date' && c['key'] != key) c];
    if (period.length != 2) {
      period
        ..clear()
        ..addAll([for (final d in dates.take(2)) '${d['key']}']);
    }
    Widget pick(int i, String label) => DropdownButtonFormField<String>(
          initialValue: period.length > i && dates.any((d) => d['key'] == period[i]) ? period[i] : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: [for (final d in dates) DropdownMenuItem(value: '${d['key']}', child: Text('${d['label'] ?? d['key']}'))],
          onChanged: (v) => setState(() {
            while (period.length < 2) {
              period.add('');
            }
            period[i] = v ?? '';
          }),
        );
    return [
      const SizedBox(height: 12),
      if (dates.length < 2)
        Text(tr('Biểu mẫu cần hai trường Ngày (từ ngày, đến ngày) để làm thời gian ủy quyền.'), style: const TextStyle(color: kFlowOrange))
      else ...[
        pick(0, tr('Ủy quyền từ ngày (trường)')),
        const SizedBox(height: 10),
        pick(1, tr('Đến hết ngày (trường)')),
      ],
      const SizedBox(height: 8),
      Text(tr('Người điền thấy sẵn một dòng gồm mọi quy trình liên quan tới họ; chọn người nhận thay, kéo quy trình sang dòng khác nếu muốn chia. Thêm bước "Áp dụng ủy quyền" sau bước duyệt để có hiệu lực.'),
          style: TextStyle(color: pal.sub, fontSize: 12.5)),
    ];
  }

  void _setType(String t) => setState(() {
        if (t != type) {
          def = null;
          _gen++;
        }
        type = t;
        if (t == 'calc') {
          final n = _numericSiblings;
          calc['a'] ??= n.firstOrNull?['key'];
          calc['b'] ??= (n.length > 1 ? n[1] : n.firstOrNull)?['key'];
        }
      });

  void _addOption() {
    final o = option.text.trim();
    if (o.isEmpty || options.contains(o)) return;
    setState(() {
      options.add(o);
      option.clear();
    });
  }

  Future<void> _editColumn([int? i]) async {
    final r = await showDialog<Object>(
      context: context,
      builder: (_) => FieldDialog(
        field: i == null ? null : columns[i],
        column: true,
        siblings: [for (var j = 0; j < columns.length; j++) if (j != i) columns[j]],
        fillTargets: [for (var j = 0; j < columns.length; j++) if (j != i) columns[j]],
        taken: {for (final c in columns) '${c['key']}'},
      ),
    );
    if (r == null) return;
    setState(() {
      if (r == 'delete' && i != null) {
        final k = columns.removeAt(i)['key'];
        // Bỏ cột tự tính đang dùng cột vừa xoá.
        columns.removeWhere((c) => c['calc'] is Map && ((c['calc'] as Map)['a'] == k || (c['calc'] as Map)['b'] == k));
      } else if (r is Map<String, dynamic>) {
        i == null ? columns.add(r) : columns[i] = r;
      }
    });
  }

  String _colSub(Map<String, dynamic> c) {
    final k = c['calc'];
    if (k is Map) {
      String name(Object? key) => '${columns.firstWhere((x) => x['key'] == key, orElse: () => {'label': key})['label']}';
      return tr('Tự tính = {0} {1} {2}', [name(k['a']), _calcOps[k['op']] ?? '×', name(k['b'])]);
    }
    return [tr(_fieldTypes['${c['type']}'] ?? '${c['type']}'), if (c['required'] == true) tr('bắt buộc')].join(' · ');
  }

  Widget _columnsEditor(Pal pal) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        Text(tr('Các cột'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        if (columns.isEmpty) Text(tr('Chưa có cột nào.'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
        for (var i = 0; i < columns.length; i++)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 4),
            dense: true,
            leading: Icon(columns[i]['calc'] != null ? Icons.functions_rounded : _fieldIcon('${columns[i]['type']}'), size: 20, color: pal.accent),
            title: Text('${columns[i]['label']}'),
            subtitle: Text(_colSub(columns[i])),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (i > 0)
                IconButton(
                  tooltip: tr('Lên'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => columns.insert(i - 1, columns.removeAt(i))),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                ),
            ]),
            onTap: () => _editColumn(i),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => _editColumn(), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm cột'))),
        ),
      ]);

  Widget _calcEditor(Pal pal) {
    final n = _numericSiblings;
    if (n.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(tr('Cần ít nhất một cột kiểu Số hoặc Số tiền (nhập tay) để tự tính.'), style: const TextStyle(color: kFlowOrange)),
      );
    }
    DropdownButtonFormField<String> pick(String slot) => DropdownButtonFormField<String>(
          initialValue: n.any((c) => c['key'] == calc[slot]) ? '${calc[slot]}' : null,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          items: [for (final c in n) DropdownMenuItem(value: '${c['key']}', child: Text('${c['label']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => calc[slot] = v),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Cách tính'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        pick('a'),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: [for (final e in _calcOps.entries) ButtonSegment(value: e.key, label: Text(e.value, style: const TextStyle(fontSize: 18)))],
          selected: {'${calc['op']}'},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => calc['op'] = s.first),
        ),
        const SizedBox(height: 6),
        pick('b'),
      ]),
    );
  }

  /// Chọn từ danh mục: máy chủ MCP, tool, tham số nhận từ khoá, khoá giá trị / nhãn, điền thêm ô khác.
  Widget _lookupEditor(Pal pal) {
    final on = lookup != null;
    final servers = [for (final m in (editorCtx?.integ['mcp'] as List? ?? const [])) if (m is Map) m];
    final lk = lookup ?? {};
    final srv = servers.where((m) => m['name'] == mcpKeyOf(lk)).firstOrNull;
    final tools = [for (final t in (srv?['tools'] as List? ?? const [])) if (t is Map && t['read_only'] == true) t];
    final tool = tools.where((t) => t['name'] == lk['tool']).firstOrNull;
    final props = [for (final k in (((tool?['input_schema'] as Map?)?['properties'] as Map?) ?? const {}).keys) '$k'];
    final args = (lk['args'] as Map?)?.cast<String, dynamic>() ?? {};
    final qArg = args.entries.where((e) => e.value == '{{q}}').map((e) => e.key).firstOrNull;
    final fill = (lk['fill'] as Map?)?.cast<String, dynamic>() ?? {};
    void set(Map<String, dynamic> v) => setState(() => lookup = v);
    Widget keyPick(String label, String? cur, ValueChanged<String?> onChanged, {bool allowNone = false}) => _lookupKeys.isEmpty
        ? TextFormField(
            initialValue: cur ?? '',
            decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => onChanged(v.trim().isEmpty ? null : v.trim()),
          )
        : DropdownButtonFormField<String>(
            initialValue: _lookupKeys.contains(cur) ? cur : (allowNone ? '' : null),
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
            items: [if (allowNone) DropdownMenuItem(value: '', child: Text(tr('(không)'))), for (final k in _lookupKeys) DropdownMenuItem(value: k, child: Text(k))],
            onChanged: (v) => onChanged(v == null || v.isEmpty ? null : v),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Chọn từ danh mục (ERP...)')),
        value: on,
        onChanged: (v) => setState(() {
          final first = servers.firstOrNull;
          lookup = v ? {if (first?['app'] != null) 'app': first!['app'] else 'server': first?['name'] ?? '', 'tool': '', 'value': ''} : null;
        }),
      ),
      if (on) ...[
        DropdownButtonFormField<String>(
          initialValue: srv == null ? null : '${srv['name']}',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Máy chủ công cụ'), isDense: true, border: const OutlineInputBorder()),
          items: [for (final m in servers) DropdownMenuItem(value: '${m['name']}', child: Text('${m['label']}'))],
          onChanged: (v) {
            final m = <String, dynamic>{...lk, 'tool': ''};
            setMcpKey(m, servers, v);
            set(m);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('lk-tool-${mcpKeyOf(lk)}'),
          initialValue: tool == null ? null : '${tool['name']}',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Công cụ tra cứu (chỉ đọc)'), isDense: true, border: const OutlineInputBorder()),
          items: [for (final t in tools) DropdownMenuItem(value: '${t['name']}', child: Text(toolTitle(t), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => set({...lk, 'tool': v, 'args': <String, dynamic>{}}),
        ),
        if (props.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('lk-q-${lk['tool']}'),
            initialValue: props.contains(qArg) ? qArg : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Tham số nhận từ khoá người dùng gõ'), isDense: true, border: const OutlineInputBorder()),
            items: [for (final p in props) DropdownMenuItem(value: p, child: Text(p))],
            onChanged: (v) => set({...lk, 'args': {?v: '{{q}}'}}),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(tr('Thử tra để lấy các khoá')),
            onPressed: () async {
              try {
                final r = await editorCtx!.api.lookupTest({...lk, 'value': '${lk['value'] ?? ''}'.isEmpty ? 'id' : lk['value']}, '');
                setState(() {
                  _lookupKeys = [for (final k in (r['keys'] as List? ?? const [])) '$k'];
                  _lookupErr = _lookupKeys.isEmpty ? tr('Công cụ không trả về mục nào') : null;
                });
              } catch (e) {
                setState(() => _lookupErr = '$e');
              }
            },
          ),
        ),
        if (_lookupErr != null) Text(_lookupErr!, style: const TextStyle(color: kFlowRed, fontSize: 12)),
        Row(children: [
          Expanded(child: keyPick(tr('Khoá giá trị'), lk['value'] as String?, (v) => set({...lk, 'value': v ?? ''}))),
          const SizedBox(width: 8),
          Expanded(child: keyPick(tr('Khoá tên hiện'), lk['label'] as String?, (v) => set({...lk, 'label': v ?? ''}..removeWhere((k, x) => k == 'label' && '$x'.isEmpty)), allowNone: true)),
        ]),
        // Dòng phụ dưới mỗi gợi ý (vd tồn kho, đơn giá) để chọn đúng.
        const SizedBox(height: 8),
        Text(tr('Dòng phụ dưới mỗi gợi ý'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        if (_lookupKeys.isEmpty)
          Text(tr('Bấm "Thử" để lấy các khoá rồi chọn.'), style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in _lookupKeys)
              FilterChip(
                label: Text(k),
                selected: (lk['sub'] as List? ?? const []).contains(k),
                onSelected: (v) {
                  final cur = [for (final x in (lk['sub'] as List? ?? const [])) '$x'];
                  final next = v ? [...cur, k] : (cur..remove(k));
                  set({...lk, 'sub': next}..removeWhere((key, x) => key == 'sub' && (x as List).isEmpty));
                },
              ),
          ]),
        if (widget.fillTargets.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(tr('Điền thêm khi chọn'), style: Theme.of(context).textTheme.labelLarge),
          for (final t in widget.fillTargets.where((t) => t['calc'] == null && t['key'] != key))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: Text('${t['label'] ?? t['key']}', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Expanded(
                  child: keyPick(tr('lấy từ khoá'), fill['${t['key']}'] as String?, (v) {
                    final f2 = {...fill};
                    v == null ? f2.remove('${t['key']}') : f2['${t['key']}'] = v;
                    set({...lk, 'fill': f2});
                  }, allowNone: true),
                ),
              ]),
            ),
        ],
      ],
    ]);
  }

  Widget? _defaultField() {
    final k = ValueKey('def-$type-$_gen');
    final deco = InputDecoration(labelText: tr('Giá trị mặc định (không bắt buộc)'), border: const OutlineInputBorder());
    switch (type) {
      case 'text' || 'textarea':
        return TextFormField(key: k, initialValue: def is String ? def as String : '', decoration: deco, onChanged: (v) => def = v.isEmpty ? null : v);
      case 'number':
        return TextFormField(
          key: k,
          initialValue: def is num ? '$def' : '',
          keyboardType: TextInputType.number,
          decoration: deco,
          onChanged: (v) => def = num.tryParse(v.replaceAll(',', '.')),
        );
      case 'money':
        return TextFormField(
          key: k,
          initialValue: def is num ? vnNumber(def as num) : '',
          keyboardType: TextInputType.number,
          inputFormatters: [MoneyInputFormatterLite()],
          decoration: deco.copyWith(suffixText: 'đ'),
          onChanged: (v) => def = parseMoney(v),
        );
      case 'select':
        return DropdownButtonFormField<String>(
          key: ValueKey('def-select-${options.join('|')}-$_gen'),
          initialValue: options.contains(def) ? def as String : '',
          decoration: deco,
          items: [DropdownMenuItem(value: '', child: Text(tr('Không có'))), for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => setState(() => def = (v == null || v.isEmpty) ? null : v),
        );
      case 'bool':
        return DropdownButtonFormField<String>(
          key: k,
          initialValue: def == null ? '' : '$def',
          decoration: deco,
          items: [DropdownMenuItem(value: '', child: Text(tr('Không có'))), DropdownMenuItem(value: 'true', child: Text(tr('Có'))), DropdownMenuItem(value: 'false', child: Text(tr('Không')))],
          onChanged: (v) => setState(() => def = v == '' ? null : v == 'true'),
        );
      case 'date':
        return InputDecorator(
          key: k,
          decoration: deco,
          child: Row(children: [
            Expanded(child: Text(def == null ? tr('Không có') : condValueLabel(def, const CondVar('', '', 'date')))),
            if (def != null) IconButton(onPressed: () => setState(() => def = null), icon: const Icon(Icons.close_rounded, size: 18)),
            IconButton(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime.tryParse('${def ?? ''}') ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) setState(() => def = d.toIso8601String().substring(0, 10));
              },
              icon: const Icon(Icons.event_rounded, size: 20),
            ),
          ]),
        );
      default:
        return null;
    }
  }

  Map<String, dynamic> _result() {
    if (type == 'calc') {
      final money = _numericSiblings.any((c) => (c['key'] == calc['a'] || c['key'] == calc['b']) && c['type'] == 'money');
      return {'key': key, 'label': label.text.trim(), 'type': money ? 'money' : 'number', 'calc': {'a': calc['a'], 'op': calc['op'], 'b': calc['b']}};
    }
    return {
      'key': key,
      'label': label.text.trim(),
      'type': type,
      if (required) 'required': true,
      if (type == 'select') 'options': options,
      if (type == 'table') 'columns': columns,
      if (type == 'money' && currency.isNotEmpty) 'currency': currency,
      if (type == 'delegation' && period.length == 2) 'period': period,
      if (showIf.isNotEmpty) 'show_if': showIf,
      if (type == 'text' && lookup != null) 'lookup': lookup,
      if (def != null && (type != 'select' || options.contains(def))) 'default': def,
      if (hint.text.trim().isNotEmpty) 'hint': hint.text.trim(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dup = widget.field == null && widget.taken.contains(key);
    final defField = _defaultField();
    final blocked = (type == 'select' && options.isEmpty) ||
        (type == 'table' && columns.isEmpty) ||
        (type == 'calc' && (calc['a'] == null || calc['b'] == null || _numericSiblings.isEmpty));
    final what = widget.column ? tr('cột') : tr('trường');
    return AlertDialog(
      title: Text(widget.field == null ? tr('Thêm {0}', [what]) : tr('Sửa {0}', [what])),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: label,
              autofocus: widget.field == null,
              decoration: InputDecoration(labelText: widget.column ? tr('Tên cột') : tr('Tên trường'), errorText: dup ? tr('Đã có tên này') : null, border: const OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: InputDecoration(labelText: tr('Kiểu giá trị'), border: const OutlineInputBorder()),
              items: [
                for (final e in _types.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Row(children: [Icon(e.key == 'calc' ? Icons.functions_rounded : _fieldIcon(e.key), size: 18), const SizedBox(width: 8), Text(tr(e.value))]),
                  ),
              ],
              onChanged: (v) => _setType(v!),
            ),
            if (_fieldHints[type] case final String hint)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(tr(hint), style: TextStyle(color: Pal.of(context).sub, fontSize: 12.5)),
              ),
            if (type == 'select') ...[
              const SizedBox(height: 12),
              Text(tr('Các lựa chọn'), style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in options) InputChip(label: Text(o), onDeleted: () => setState(() => options.remove(o))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: option,
                    decoration: InputDecoration(hintText: tr('Thêm lựa chọn'), isDense: true, border: const OutlineInputBorder()),
                    onSubmitted: (_) => _addOption(),
                  ),
                ),
                IconButton(onPressed: _addOption, icon: const Icon(Icons.add_circle_outline_rounded)),
              ]),
            ],
            if (type == 'table') _columnsEditor(pal),
            if (type == 'delegation') ..._periodEditor(pal),
            if (type == 'money') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: InputDecoration(labelText: tr('Loại tiền'), border: const OutlineInputBorder()),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('Đồng (VND)'))),
                  for (final c in const ['USD', 'EUR', 'JPY', 'CNY', 'KRW', 'SGD', 'THB']) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => currency = v ?? ''),
              ),
            ],
            if (type == 'text' && (editorCtx?.integ['mcp'] as List? ?? const []).isNotEmpty) _lookupEditor(pal),
            if (widget.condVars.isNotEmpty && type != 'calc')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.visibility_outlined),
                title: Text(tr('Chỉ hiện khi…')),
                subtitle: Text(showIf.isEmpty ? tr('Luôn hiện') : condLabel(showIf, widget.condVars)),
                trailing: showIf.isEmpty ? null : IconButton(onPressed: () => setState(() => showIf = ''), icon: const Icon(Icons.close_rounded, size: 18)),
                onTap: () async {
                  final ctx = editorCtx;
                  if (ctx == null) return;
                  final r = await showDialog<String>(context: context, builder: (_) => CondDialog(app: ctx.app, expr: showIf, vars: widget.condVars));
                  if (r != null && r != '\u0000delete') setState(() => showIf = r);
                },
              ),
            if (type == 'calc') _calcEditor(pal),
            if (defField != null) ...[const SizedBox(height: 12), defField],
            if (type != 'calc') ...[
              const SizedBox(height: 12),
              TextField(
                controller: hint,
                decoration: InputDecoration(labelText: tr('Gợi ý cho người điền (không bắt buộc)'), hintText: tr('Ví dụ: Ghi rõ số hoá đơn'), border: const OutlineInputBorder()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(type == 'table' ? tr('Bắt buộc (ít nhất 1 dòng)') : tr('Bắt buộc')),
                value: required,
                onChanged: (v) => setState(() => required = v),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        if (widget.field != null) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: Text(tr('Xoá'), style: const TextStyle(color: kFlowRed))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(onPressed: key.isEmpty || dup || blocked ? null : () => Navigator.pop(context, _result()), child: Text(tr('Xong'))),
      ],
    );
  }
}

/// Mẫu trường có sẵn để chèn nhanh.
List<(String, IconData, List<Map<String, dynamic>>)> fieldPresets() => [
      (
        tr('Danh sách sản phẩm'),
        Icons.table_chart_outlined,
        [
          {
            'key': 'san_pham',
            'label': tr('Sản phẩm'),
            'type': 'table',
            'required': true,
            'columns': [
              {'key': 'ten', 'label': tr('Tên sản phẩm'), 'type': 'text', 'required': true},
              {'key': 'so_luong', 'label': tr('Số lượng'), 'type': 'number', 'required': true, 'default': 1},
              {'key': 'don_gia', 'label': tr('Đơn giá'), 'type': 'money', 'required': true},
              {'key': 'thanh_tien', 'label': tr('Thành tiền'), 'type': 'money', 'calc': {'a': 'so_luong', 'op': 'mul', 'b': 'don_gia'}},
            ],
          },
        ],
      ),
      (
        tr('Thông tin nhà cung cấp'),
        Icons.storefront_outlined,
        [
          {'key': 'nha_cung_cap', 'label': tr('Nhà cung cấp'), 'type': 'text', 'required': true},
          {'key': 'ma_so_thue', 'label': tr('Mã số thuế'), 'type': 'text'},
          {'key': 'so_tai_khoan', 'label': tr('Số tài khoản'), 'type': 'text', 'hint': tr('Số tài khoản - Ngân hàng')},
        ],
      ),
      (
        tr('Số tiền + chứng từ'),
        Icons.receipt_long_outlined,
        [
          {'key': 'so_tien', 'label': tr('Số tiền'), 'type': 'money', 'required': true},
          {'key': 'chung_tu', 'label': tr('Hoá đơn / chứng từ'), 'type': 'files'},
        ],
      ),
    ];

/// Chép trường từ quy trình khác: chọn quy trình rồi chọn trường. Trả về danh sách trường (Map).
Future<List<Map<String, dynamic>>?> copyFieldsFromFlow(BuildContext context, FlowsApi api, String exceptId) async {
  final List<Map<String, dynamic>> defs;
  try {
    defs = [for (final d in await api.adminDefs()) if (d['id'] != exceptId) d];
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    return null;
  }
  if (!context.mounted) return null;
  final id = await showDialog<String>(
    context: context,
    builder: (d) => SimpleDialog(
      title: Text(tr('Chép trường từ quy trình')),
      children: [
        if (defs.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr('Chưa có quy trình nào khác.'))),
        for (final x in defs)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, '${x['id']}'),
            child: Row(children: [
              Text('${x['icon'] ?? ''}'.isEmpty ? '📋' : '${x['icon']}', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Text('${x['name']}')),
            ]),
          ),
      ],
    ),
  );
  if (id == null || !context.mounted) return null;
  final List<Map<String, dynamic>> fields;
  try {
    fields = [for (final f in ((await api.getDef(id))['form'] as List? ?? const [])) if (f is Map) f.cast<String, dynamic>()];
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    return null;
  }
  if (!context.mounted) return null;
  final picked = {for (final f in fields) '${f['key']}'};
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(tr('Chọn trường cần chép')),
        content: SizedBox(
          width: 400,
          child: ListView(shrinkWrap: true, children: [
            for (final f in fields)
              CheckboxListTile(
                value: picked.contains('${f['key']}'),
                onChanged: (v) => set(() => v == true ? picked.add('${f['key']}') : picked.remove('${f['key']}')),
                secondary: Icon(_fieldIcon('${f['type']}')),
                title: Text('${f['label'] ?? f['key']}'),
                subtitle: Text(tr(_fieldTypes['${f['type']}'] ?? '${f['type']}')),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: picked.isEmpty ? null : () => Navigator.pop(d, [for (final f in fields) if (picked.contains('${f['key']}')) f]),
            child: Text(tr('Chép {0} trường', [picked.length])),
          ),
        ],
      ),
    ),
  );
}

/// Ô nội dung có chèn thông tin của luồng: hiện "[Số tiền]", lưu "{{form.so_tien}}". Không gõ công thức.
class TemplateField extends StatefulWidget {
  final String label, raw;
  final List<CondVar> vars;
  final int lines;
  final ValueChanged<String> onChanged;
  const TemplateField({super.key, required this.label, required this.raw, required this.vars, required this.onChanged, this.lines = 3});
  @override
  State<TemplateField> createState() => _TemplateFieldState();
}

class _TemplateFieldState extends State<TemplateField> {
  late final ctl = TextEditingController(text: templateToDisplay(widget.raw, widget.vars));

  void _insert(CondVar v) => _put('[${v.label}]');

  void _put(String t) {
    final sel = ctl.selection;
    final at = sel.isValid ? sel.start : ctl.text.length;
    final end = sel.isValid ? sel.end : ctl.text.length;
    ctl.value = TextEditingValue(text: ctl.text.replaceRange(at, end, t), selection: TextSelection.collapsed(offset: at + t.length));
    widget.onChanged(templateFromDisplay(ctl.text, widget.vars));
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: ctl,
          minLines: widget.lines,
          maxLines: widget.lines + 6,
          decoration: InputDecoration(labelText: widget.label, alignLabelWithHint: true, border: const OutlineInputBorder()),
          onChanged: (v) => widget.onChanged(templateFromDisplay(v, widget.vars)),
        ),
        Wrap(spacing: 14, children: [
          if (widget.vars.isNotEmpty)
            PopupMenuButton<CondVar>(
              tooltip: tr('Chèn thông tin của tiến trình'),
              onSelected: _insert,
              itemBuilder: (_) => [for (final v in widget.vars) PopupMenuItem(value: v, child: Text(v.label))],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_box_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(tr('Chèn thông tin'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          // Biểu thức trong ngoặc: {{round(form.so_tien * 0.08)}}, {{add_days(form.tu_ngay, 3)}}...
          PopupMenuButton<ExprFunc>(
            tooltip: tr('Chèn hàm (tính trong ngoặc {{…}})'),
            onSelected: (f) => _put('{{${f.template}}}'),
            itemBuilder: (_) => [
              for (final f in exprFuncs)
                PopupMenuItem(value: f, child: ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(f.template, style: const TextStyle(fontFamily: 'monospace')), subtitle: Text(tr(f.hint)))),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.functions_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(tr('Hàm'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ]);
}

// ---------------------------------------------------------------------------------------------- kết quả kiểm / chạy thử

class CheckResultView extends StatelessWidget {
  final List<Map<String, dynamic>> issues, traces;
  final int initialTab;
  final String? title;
  /// Thông tin của luồng, để đổi tên trường trong tên tình huống thành chữ dễ đọc.
  final List<CondVar> vars;
  final String Function(String) nodeName, who;
  /// Chạm lỗi có bước: mở bước đó.
  final void Function(String node)? onOpen;
  const CheckResultView({super.key, required this.issues, required this.traces, required this.nodeName, required this.who, this.vars = const [], this.initialTab = 0, this.title, this.onOpen});

  /// "so_tien = 20.000.001" → "Số tiền = 20.000.001"; "san_pham__tong.thanh_tien = ..." → "Sản phẩm › Tổng thành tiền = ...".
  String _label(String l) {
    var s = l;
    final named = [for (final v in vars) if (v.path.startsWith('form.')) (v.path.substring(5), v.label)]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
    for (final (k, label) in named) {
      s = s.replaceAll(RegExp('(?<![\\w.])${RegExp.escape(k)}(?![\\w.])'), label);
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final errors = issues.where((i) => i['warn'] != true).length;
    final ok = errors == 0;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            Icon(ok ? Icons.verified_rounded : Icons.error_rounded, color: ok ? kFlowGreen : kFlowRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title ?? (ok ? tr('Quy trình hợp lệ') : tr('Còn {0} lỗi cần sửa', [errors])), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
            ),
          ]),
        ),
        TabBar(tabs: [Tab(text: tr('Lỗi ({0})', [issues.length])), Tab(text: tr('Chạy thử ({0})', [traces.length]))]),
        Expanded(
          child: TabBarView(children: [
            issues.isEmpty
                ? Center(child: Text(tr('Không có lỗi nào'), style: TextStyle(color: pal.sub)))
                : ListView(padding: const EdgeInsets.all(12), children: [
                    for (final i in issues)
                      ListTile(
                        leading: Icon(i['warn'] == true ? Icons.warning_amber_rounded : Icons.error_outline_rounded, color: i['warn'] == true ? kFlowOrange : kFlowRed),
                        title: Text('${i['msg']}'),
                        subtitle: i['node'] == null ? null : Text(tr('Bước: {0}', [nodeName('${i['node']}')])),
                        trailing: i['node'] == null || onOpen == null || '${i['node']}'.startsWith('start:') ? null : const Icon(Icons.chevron_right_rounded),
                        onTap: i['node'] == null || onOpen == null || '${i['node']}'.startsWith('start:') ? null : () => onOpen!('${i['node']}'),
                      ),
                  ]),
            traces.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(ok ? tr('Không có tình huống chạy thử') : tr('Sửa hết lỗi để chạy thử'), style: TextStyle(color: pal.sub))))
                : ListView(padding: const EdgeInsets.all(12), children: [for (final t in traces) _trace(context, pal, t)]),
          ]),
        ),
      ]),
    );
  }

  Widget _trace(BuildContext context, Pal pal, Map<String, dynamic> t) {
    final status = '${t['status']}';
    final color = switch (status) { 'done' => kFlowGreen, 'rejected' || 'failed' || 'cancelled' => kFlowRed, _ => kFlowOrange };
    final path = [for (final v in (t['path'] as List? ?? const [])) if (v is Map) v];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${t['label']}'.isEmpty ? tr('Tình huống') : _label('${t['label']}'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(flowStatusLabel(status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 4, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var i = 0; i < path.length; i++) ...[
            if (i > 0) Icon(Icons.arrow_forward_rounded, size: 14, color: pal.sub),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(8)),
              child: Text(
                [
                  '${path[i]['name']}'.isEmpty ? nodeName('${path[i]['node']}') : '${path[i]['name']}',
                  if ((path[i]['who'] as List?)?.isNotEmpty ?? false) '(${[for (final w in path[i]['who'] as List) who('$w')].join(', ')})',
                ].join(' '),
                style: TextStyle(fontSize: 12, color: pal.text),
              ),
            ),
          ],
        ]),
        if (t['error'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${t['error']}', style: const TextStyle(color: kFlowRed, fontSize: 12))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------- hàng nhánh

/// Các cột nhánh đặt cạnh nhau, tự vẽ đường nối: thanh ngang trên (tách nhánh), đường dọc từ đáy mỗi cột
/// xuống thanh ngang dưới (gặp lại). Không dùng IntrinsicHeight nên lồng nhiều cấp vẫn đúng.
class BranchRow extends MultiChildRenderObjectWidget {
  final Color color;
  /// Cột nào tự kết thúc (không nối xuống thanh gặp lại), theo thứ tự cột.
  final List<bool> ends;
  const BranchRow({super.key, required this.color, this.ends = const [], required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderBranchRow(color)..ends = ends;

  @override
  void updateRenderObject(BuildContext context, RenderBranchRow renderObject) => renderObject
    ..color = color
    ..ends = ends;
}

class _BranchParentData extends ContainerBoxParentData<RenderBox> {}

class RenderBranchRow extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _BranchParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _BranchParentData> {
  RenderBranchRow(this._color);

  static const _pad = 12.0, _stroke = 2.0;

  Color _color;
  set color(Color c) {
    if (c == _color) return;
    _color = c;
    markNeedsPaint();
  }

  List<bool> _ends = const [];
  set ends(List<bool> e) {
    if (listEquals(e, _ends)) return;
    _ends = e;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BranchParentData) child.parentData = _BranchParentData();
  }

  @override
  void performLayout() {
    var x = 0.0, h = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
      final pd = child.parentData! as _BranchParentData;
      pd.offset = Offset(x, _pad);
      x += child.size.width;
      if (child.size.height > h) h = child.size.height;
      child = pd.nextSibling;
    }
    size = constraints.constrain(Size(x, h + 2 * _pad));
  }

  double _sum(double Function(RenderBox) f) {
    var t = 0.0;
    for (var c = firstChild; c != null; c = (c.parentData! as _BranchParentData).nextSibling) {
      t += f(c);
    }
    return t;
  }

  double _max(double Function(RenderBox) f) {
    var t = 0.0;
    for (var c = firstChild; c != null; c = (c.parentData! as _BranchParentData).nextSibling) {
      final v = f(c);
      if (v > t) t = v;
    }
    return t;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _sum((c) => c.getMinIntrinsicWidth(double.infinity));
  @override
  double computeMaxIntrinsicWidth(double height) => _sum((c) => c.getMaxIntrinsicWidth(double.infinity));
  @override
  double computeMinIntrinsicHeight(double width) => _max((c) => c.getMinIntrinsicHeight(double.infinity)) + 2 * _pad;
  @override
  double computeMaxIntrinsicHeight(double width) => _max((c) => c.getMaxIntrinsicHeight(double.infinity)) + 2 * _pad;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()
      ..color = _color
      ..strokeWidth = _stroke;
    final canvas = context.canvas;
    final bottom = size.height - _stroke / 2;
    final top = _stroke / 2;
    final centers = <double>[], open = <double>[];
    var i = 0;
    for (var c = firstChild; c != null; c = (c.parentData! as _BranchParentData).nextSibling, i++) {
      final pd = c.parentData! as _BranchParentData;
      final cx = offset.dx + pd.offset.dx + c.size.width / 2;
      centers.add(cx);
      canvas.drawLine(Offset(cx, offset.dy + top), Offset(cx, offset.dy + _pad), paint);
      // Cột tự kết thúc: không nối xuống thanh gặp lại.
      if (i < _ends.length && _ends[i]) continue;
      open.add(cx);
      canvas.drawLine(Offset(cx, offset.dy + _pad + c.size.height), Offset(cx, offset.dy + bottom), paint);
    }
    if (centers.length > 1) {
      canvas.drawLine(Offset(centers.first - _stroke / 2, offset.dy + top), Offset(centers.last + _stroke / 2, offset.dy + top), paint);
    }
    if (open.isNotEmpty) {
      // Thanh gặp lại luôn chạm giữa hàng (nơi đường đi tiếp xuống bước sau).
      final mid = offset.dx + size.width / 2;
      final a = open.first < mid ? open.first : mid, b = open.last > mid ? open.last : mid;
      if (b - a > 0.5) canvas.drawLine(Offset(a - _stroke / 2, offset.dy + bottom), Offset(b + _stroke / 2, offset.dy + bottom), paint);
    }
    defaultPaint(context, offset);
  }
}

// ---------------------------------------------------------------------------------------------- lịch chạy

const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// "Tự chạy hằng ngày lúc 08:00" ... hoặc null nếu không chạy theo lịch.
String? scheduleLabel(Object? trigger) {
  final s = trigger is Map ? trigger['schedule'] : null;
  if (s is! Map) return null;
  final at = '${s['at'] ?? '08:00'}';
  return switch ('${s['every']}') {
    'hour' => tr('Tự chạy mỗi giờ, phút {0}', [at.split(':').last]),
    'week' => tr('Tự chạy {0} lúc {1}', [
        [for (final d in (s['weekdays'] as List? ?? const [])) _weekdays[((d as num).toInt() - 1).clamp(0, 6)]].join(', ').ifEmpty(tr('mọi ngày')),
        at,
      ]),
    'month' => tr('Tự chạy ngày {0} hằng tháng lúc {1}', [s['day'] ?? 1, at]),
    _ => tr('Tự chạy hằng ngày lúc {0}', [at]),
  };
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Cách bắt đầu: người bấm "Tạo luồng" hoặc tự chạy theo lịch (giờ Việt Nam), đứng tên một người.
class ScheduleEditor extends StatelessWidget {
  final AppState app;
  final Map<String, dynamic>? trigger;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  /// Nằm trong TriggerEditor: chỉ hiện phần lịch (không có tiêu đề / nút bật tắt).
  final bool embedded;
  const ScheduleEditor({super.key, required this.app, required this.trigger, required this.onChanged, this.embedded = false});

  Map<String, dynamic> get _s => (trigger?['schedule'] as Map?)?.cast<String, dynamic>() ?? {'every': 'day', 'at': '08:00'};

  void _set(Map<String, dynamic> s, {String? runAs}) => onChanged({
        'schedule': s,
        if ((runAs ?? trigger?['run_as']) != null) 'run_as': runAs ?? trigger?['run_as'],
      });

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final on = trigger?['schedule'] != null;
    final s = _s;
    final every = '${s['every']}';
    final at = '${s['at'] ?? '08:00'}';
    final days = [for (final d in (s['weekdays'] as List? ?? const [])) (d as num).toInt()];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!embedded) ...[
        Text(tr('Cách bắt đầu'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: [ButtonSegment(value: false, label: Text(tr('Người bấm Tạo tiến trình'))), ButtonSegment(value: true, label: Text(tr('Tự chạy theo lịch')))],
          selected: {on},
          showSelectedIcon: false,
          onSelectionChanged: (v) => v.first ? _set({'every': 'day', 'at': '08:00'}) : onChanged(null),
        ),
      ],
      if (on || embedded) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final (k, label) in [('hour', tr('Mỗi giờ')), ('day', tr('Hằng ngày')), ('week', tr('Hằng tuần')), ('month', tr('Hằng tháng'))])
            ChoiceChip(label: Text(label), selected: every == k, onSelected: (_) => _set({...s, 'every': k})),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.access_time_rounded, size: 18),
            label: Text(every == 'hour' ? tr('Phút {0}', [at.split(':').last]) : tr('Lúc {0}', [at])),
            onPressed: () async {
              final p = at.split(':');
              final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 8, minute: int.tryParse(p.last) ?? 0));
              if (t != null) _set({...s, 'at': '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'});
            },
          ),
          if (every == 'week')
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(_weekdays[d - 1]),
                selected: days.contains(d),
                onSelected: (v) => _set({...s, 'weekdays': v ? ([...days, d]..sort()) : ([...days]..remove(d))}),
              ),
          if (every == 'month')
            DropdownButton<int>(
              value: ((s['day'] as num?)?.toInt() ?? 1).clamp(1, 28),
              items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text(tr('Ngày {0}', [d])))],
              onChanged: (v) => _set({...s, 'day': v}),
            ),
        ]),
        const SizedBox(height: 10),
        WhoField(
          app: app,
          roles: const {},
          label: tr('Tiến trình đứng tên'),
          value: trigger?['run_as'] == null ? null : {'user': trigger!['run_as']},
          onChanged: (w) {
            final u = w is Map ? (w['user'] ?? (w['users'] as List?)?.firstOrNull) : null;
            if (u != null) _set(s, runAs: '$u');
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('Bỏ trống "Tiến trình đứng tên" thì tiến trình đứng tên người lưu quy trình. Tiến trình tự chạy không có ai điền biểu mẫu: trường bắt buộc cần có giá trị mặc định.'),
              style: TextStyle(color: pal.sub, fontSize: 12.5)),
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------------------------- cách bắt đầu

/// Đường dẫn các giá trị lá trong JSON mẫu: {"a": {"b": 1}} → ["a.b"].
List<String> jsonPaths(Object? v, [String prefix = '']) {
  if (v is Map) {
    return [for (final e in v.entries) ...jsonPaths(e.value, prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}')];
  }
  return prefix.isEmpty ? [] : [prefix];
}

/// Cách bắt đầu: người bấm "Tạo luồng" / tự chạy theo lịch / webhook (hệ thống ngoài gửi dữ liệu vào, có secret).
class TriggerEditor extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final String flowId;
  final List<FlowField> form;
  final Map<String, dynamic>? trigger;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  const TriggerEditor({super.key, required this.app, required this.api, required this.flowId, required this.form, required this.trigger, required this.onChanged});
  @override
  State<TriggerEditor> createState() => _TriggerEditorState();
}

class _TriggerEditorState extends State<TriggerEditor> {
  Map<String, dynamic>? _hook;
  String? _hookErr;
  bool _showSecret = false;

  String get _mode => widget.trigger?['webhook'] != null ? 'webhook' : (widget.trigger?['schedule'] != null ? 'schedule' : 'manual');
  Map<String, dynamic> get _wh => (widget.trigger?['webhook'] as Map?)?.cast<String, dynamic>() ?? {'mapping': <String, dynamic>{}};

  @override
  void initState() {
    super.initState();
    if (_mode == 'webhook') _loadHook();
  }

  Future<void> _loadHook({bool rotate = false}) async {
    try {
      final h = await widget.api.webhook(widget.flowId, rotate: rotate);
      if (mounted) {
        setState(() {
          _hook = h;
          _hookErr = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hookErr = '$e');
    }
  }

  void _setWh(Map<String, dynamic> wh) => widget.onChanged({'webhook': wh, if (widget.trigger?['run_as'] != null) 'run_as': widget.trigger!['run_as']});

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã chép {0}', [what]))));
  }

  Widget _webhook(Pal pal) {
    final h = _hook;
    final url = h == null ? '' : '${widget.api.base}${h['path']}';
    final secret = '${h?['secret'] ?? ''}';
    final paths = jsonPaths(h?['last_payload']);
    final mapping = (_wh['mapping'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final at = (h?['last_at'] as num?)?.toInt();
    Widget box(String label, String value, {bool secretBox = false}) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 11.5, color: pal.sub, fontWeight: FontWeight.w600)),
                SelectableText(secretBox && !_showSecret ? '•' * 24 : value, style: const TextStyle(fontSize: 13)),
              ]),
            ),
            if (secretBox)
              IconButton(onPressed: () => setState(() => _showSecret = !_showSecret), icon: Icon(_showSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18)),
            IconButton(tooltip: tr('Chép'), onPressed: () => _copy(value, label), icon: const Icon(Icons.copy_rounded, size: 18)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      if (_hookErr != null) Text(_hookErr!, style: const TextStyle(color: kFlowRed)),
      if (h == null && _hookErr == null) const LinearProgressIndicator(minHeight: 2),
      if (h != null) ...[
        box(tr('URL nhận dữ liệu (POST JSON)'), url),
        box(tr('Secret'), secret, secretBox: true),
        Text(
          tr('Hệ thống gửi kèm header X-Flygo-Secret: <secret>, hoặc X-Flygo-Signature: sha256=<HMAC-SHA256 của nội dung, khoá là secret>. Sai hoặc thiếu secret thì bị từ chối.'),
          style: TextStyle(color: pal.sub, fontSize: 12.5),
        ),
        Row(children: [
          TextButton.icon(onPressed: () => _loadHook(), icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Tải dữ liệu mới nhận'))),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text(tr('Đổi URL và secret?')),
                  content: Text(tr('URL và secret cũ hết hiệu lực ngay. Hệ thống bên ngoài phải cập nhật cái mới.')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Đổi'))),
                  ],
                ),
              );
              if (ok == true) _loadHook(rotate: true);
            },
            icon: const Icon(Icons.autorenew_rounded, size: 18, color: kFlowOrange),
            label: Text(tr('Đổi URL / secret'), style: const TextStyle(color: kFlowOrange)),
          ),
        ]),
        if (h['last_payload'] != null) ...[
          Text(tr('Dữ liệu nhận gần nhất{0}', [at == null ? '' : ' (${DateTime.fromMillisecondsSinceEpoch(at).toString().substring(0, 16)})']),
              style: Theme.of(context).textTheme.labelLarge),
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 10),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
            child: SingleChildScrollView(child: Text(const JsonEncoder.withIndent('  ').convert(h['last_payload']), style: const TextStyle(fontSize: 12))),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tr('Chưa nhận dữ liệu nào. Cho hệ thống bên ngoài gửi thử một lần (kể cả khi chưa lưu xong) để chọn khoá cho từng trường.'),
                style: const TextStyle(color: kFlowOrange, fontSize: 12.5)),
          ),
      ],
      Text(tr('Lấy giá trị cho từng trường'), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      for (final f in widget.form.where((f) => f.calc == null))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(flex: 4, child: Text(f.required ? '${f.label} *' : f.label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: paths.isEmpty
                  ? TextFormField(
                      initialValue: '${mapping[f.key] ?? ''}',
                      decoration: InputDecoration(hintText: tr('khoá, vd amount'), isDense: true, border: const OutlineInputBorder()),
                      onChanged: (v) => _setWh({..._wh, 'mapping': {...mapping, f.key: v.trim()}..removeWhere((_, x) => '$x'.isEmpty)}),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: paths.contains(mapping[f.key]) ? '${mapping[f.key]}' : '',
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: '', child: Text(tr('(không lấy)'))),
                        for (final p in paths) DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => _setWh({..._wh, 'mapping': {...mapping, f.key: v ?? ''}..removeWhere((_, x) => '$x'.isEmpty)}),
                    ),
            ),
          ]),
        ),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: paths.contains(_wh['dedupe']) ? '${_wh['dedupe']}' : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Mã giao dịch (gửi lại cùng mã thì không tạo trùng)'), border: const OutlineInputBorder()),
        items: [DropdownMenuItem(value: '', child: Text(tr('(không chống trùng)'))), for (final p in paths) DropdownMenuItem(value: p, child: Text(p))],
        onChanged: (v) => _setWh({..._wh, 'dedupe': v}..removeWhere((k, x) => k == 'dedupe' && (x == null || '$x'.isEmpty))),
      ),
      const SizedBox(height: 10),
      TemplateField(
        label: tr('Tiêu đề tiến trình'),
        raw: '${_wh['title'] ?? ''}',
        vars: [for (final f in widget.form) if (f.type != 'table' && f.type != 'files') CondVar('form.${f.key}', f.label, f.type)],
        lines: 1,
        onChanged: (v) => _setWh({..._wh, 'title': v}..removeWhere((k, x) => k == 'title' && '$x'.isEmpty)),
      ),
      const SizedBox(height: 10),
      WhoField(
        app: widget.app,
        roles: const {},
        label: tr('Tiến trình đứng tên'),
        value: widget.trigger?['run_as'] == null ? null : {'user': widget.trigger!['run_as']},
        onChanged: (w) {
          final u = w is Map ? (w['user'] ?? (w['users'] as List?)?.firstOrNull) : null;
          if (u != null) widget.onChanged({...?widget.trigger, 'run_as': '$u'});
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final mode = _mode;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Cách bắt đầu'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'manual', label: Text(tr('Người bấm'))),
          ButtonSegment(value: 'schedule', label: Text(tr('Theo lịch'))),
          ButtonSegment(value: 'webhook', label: Text(tr('Webhook'))),
        ],
        selected: {mode},
        showSelectedIcon: false,
        onSelectionChanged: (v) {
          switch (v.first) {
            case 'manual':
              widget.onChanged(null);
            case 'schedule':
              widget.onChanged({'schedule': {'every': 'day', 'at': '08:00'}});
            default:
              widget.onChanged({'webhook': {'mapping': <String, dynamic>{}}});
              _loadHook();
          }
        },
      ),
      if (mode == 'schedule') ScheduleEditor(app: widget.app, trigger: widget.trigger, onChanged: widget.onChanged, embedded: true),
      if (mode == 'webhook') _webhook(pal),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------- bắt đầu quy trình khác

/// Bước "Bắt đầu quy trình khác": chọn quy trình đích, lấy giá trị cho từng trường của nó từ luồng này.
/// Trường bắt buộc chưa có nguồn thì báo đỏ: thêm bước "Điền thông tin" phía trước để có người nhập.
class StartFlowConfig extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic> node;
  final List<CondVar> vars;
  final List<FlowField> form;
  final VoidCallback onChanged;
  const StartFlowConfig({super.key, required this.app, required this.node, required this.vars, required this.onChanged, this.form = const []});
  @override
  State<StartFlowConfig> createState() => _StartFlowConfigState();
}

class _StartFlowConfigState extends State<StartFlowConfig> {
  List<FlowField>? _target;
  String? _err;

  Map<String, dynamic> get n => widget.node;
  Map<String, dynamic> get _mapping {
    final m = (n['mapping'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    n['mapping'] = m;
    return m;
  }

  @override
  void initState() {
    super.initState();
    if ('${n['flow_id'] ?? ''}'.isNotEmpty) _load();
  }

  Future<void> _load() async {
    final ctx = editorCtx;
    if (ctx == null) return;
    setState(() {
      _target = null;
      _err = null;
    });
    try {
      final d = await ctx.api.getDef('${n['flow_id']}');
      if (mounted) setState(() => _target = FlowField.listOf(d['form']));
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  bool _compat(String src, String dst) =>
      src == dst ||
      ({'number', 'money'}.contains(src) && {'number', 'money'}.contains(dst)) ||
      ({'text', 'textarea'}.contains(dst) && !{'table', 'files'}.contains(src)) ||
      (dst == 'select' && {'text', 'select'}.contains(src));

  void _changed() {
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final ctx = editorCtx;
    final flows = [for (final f in ctx?.flows ?? const <Map<String, dynamic>>[]) if (f['id'] != ctx?.flowId) f];
    // Thêm bảng của biểu mẫu (để chép cả bảng sang).
    final tables = [for (final f in widget.form) if (f.type == 'table') CondVar('form.${f.key}', f.label, 'table')];
    // Lặp song song: mỗi dòng của bảng một luồng; mapping dùng được các cột của dòng.
    final eachTable = widget.form.where((f) => f.type == 'table' && 'form.${f.key}' == n['each']).firstOrNull;
    final perPerson = n['each_person'] != null;
    final rowVars = [
      for (final c in eachTable?.columns ?? const <FlowField>[]) CondVar('item.${c.key}', '${tr('Dòng')} › ${c.label}', c.type, c.options),
      if (n['each'] != null) CondVar('loop.index', tr('Số thứ tự dòng'), 'number'),
      // Mỗi người một luồng: người nhận luồng này (cũng là người tạo luồng con).
      if (perPerson) CondVar('item.user', tr('Người nhận'), 'user'),
    ];
    final vars = [...rowVars, ...widget.vars, ...tables];
    final confirm = n['confirm'] != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        initialValue: perPerson ? '\u0001person' : (eachTable == null ? '' : 'form.${eachTable.key}'),
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Số tiến trình mở'), border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem(value: '', child: Text(tr('Một tiến trình'))),
          for (final t in widget.form.where((f) => f.type == 'table'))
            DropdownMenuItem(value: 'form.${t.key}', child: Text(tr('Mỗi dòng của "{0}" một tiến trình (chạy song song)', [t.label]), overflow: TextOverflow.ellipsis)),
          DropdownMenuItem(value: '\u0001person', child: Text(tr('Mỗi người một tiến trình (vd chấm công)'), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          if (v == '\u0001person') {
            n.remove('each');
            final dept = editorCtx?.depts.firstOrNull;
            n['each_person'] ??= dept == null ? r'$requester' : {'department': dept['id']};
          } else {
            n.remove('each_person');
            v == null || v.isEmpty ? n.remove('each') : n['each'] = v;
          }
          if (n['each'] == null && n['each_person'] == null) n.remove('timeout');
          _changed();
          setState(() {});
        },
      ),
      if (perPerson) ...[
        const SizedBox(height: 12),
        WhoField(
          app: widget.app,
          roles: const {},
          label: tr('Gửi cho từng người trong'),
          value: n['each_person'],
          onChanged: (w) {
            n['each_person'] = w;
            _changed();
          },
        ),
      ],
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: flows.any((f) => f['id'] == n['flow_id']) ? '${n['flow_id']}' : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Quy trình cần bắt đầu'), border: const OutlineInputBorder()),
        items: [for (final f in flows) DropdownMenuItem(value: '${f['id']}', child: Text('${f['icon'] ?? ''} ${f['name']}'.trim(), overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          n['flow_id'] = v;
          n['mapping'] = <String, dynamic>{};
          _changed();
          _load();
        },
      ),
      const SizedBox(height: 12),
      if (_err != null) Text(_err!, style: const TextStyle(color: kFlowRed)),
      if (_target == null && '${n['flow_id'] ?? ''}'.isNotEmpty && _err == null) const LinearProgressIndicator(minHeight: 2),
      if (_target != null) ...[
        Text(tr('Lấy giá trị cho biểu mẫu của quy trình đó'), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final f in _target!.where((f) => f.calc == null))
          Builder(builder: (context) {
            final src = _mapping[f.key] as Map?;
            final need = f.required && f.defaultValue == null && f.showIf.isEmpty;
            final choices = [for (final v in vars) if (_compat(v.type, f.type)) v];
            final cur = src == null ? '' : (src['from'] != null ? 'from:${src['from']}' : '__value');
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(flex: 4, child: Text(need ? '${f.label} *' : f.label, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 6,
                    child: DropdownButtonFormField<String>(
                      initialValue: cur == '' || cur == '__value' || choices.any((v) => 'from:${v.path}' == cur) ? cur : '',
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: '', child: Text(tr('(không lấy)'))),
                        for (final v in choices) DropdownMenuItem(value: 'from:${v.path}', child: Text(v.label, overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: '__value', child: Text(tr('Giá trị cố định…'))),
                      ],
                      onChanged: (v) {
                        if (v == null || v.isEmpty) {
                          _mapping.remove(f.key);
                        } else if (v == '__value') {
                          _mapping[f.key] = {'value': f.options.isNotEmpty ? f.options.first : ''};
                        } else {
                          _mapping[f.key] = {'from': v.substring(5)};
                        }
                        _changed();
                      },
                    ),
                  ),
                ]),
                if (cur == '__value')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: f.options.isNotEmpty
                        ? DropdownButtonFormField<String>(
                            initialValue: f.options.contains(src?['value']) ? '${src?['value']}' : f.options.first,
                            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                            items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
                            onChanged: (v) {
                              _mapping[f.key] = {'value': v};
                              _changed();
                            },
                          )
                        : TextFormField(
                            initialValue: '${src?['value'] ?? ''}',
                            decoration: InputDecoration(hintText: tr('Giá trị'), isDense: true, border: const OutlineInputBorder()),
                            onChanged: (v) => _mapping[f.key] = {'value': v},
                          ),
                  ),
                if (need && src == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(tr('Bắt buộc nhưng chưa có nguồn. Thêm bước "Điền thông tin" phía trước để có người nhập, rồi chọn thông tin đó ở đây.'),
                        style: const TextStyle(color: kFlowRed, fontSize: 12)),
                  ),
              ]),
            );
          }),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Cần xác nhận trước khi đẩy sang')),
        value: confirm,
        onChanged: (v) {
          v ? n['confirm'] = r'$requester' : n.remove('confirm');
          _changed();
        },
      ),
      if (confirm)
        WhoField(
          app: widget.app,
          roles: const {},
          label: tr('Người xác nhận'),
          value: n['confirm'],
          onChanged: (w) {
            n['confirm'] = w;
            _changed();
          },
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(n['each'] != null || perPerson ? tr('Chờ các tiến trình kia xong mới đi tiếp') : tr('Chờ tiến trình kia xong mới đi tiếp')),
        value: n['wait'] == true,
        onChanged: (v) {
          v ? n['wait'] = true : (n..remove('wait')..remove('timeout'));
          _changed();
        },
      ),
      // Nhiều việc: chờ tối đa bao lâu (vd 15 phút sau giờ vào ca), quá hạn thì đi tiếp với các việc đã xong.
      if (n['wait'] == true && (n['each'] != null || perPerson)) ...[
        TextFormField(
          initialValue: '${n['timeout'] ?? ''}',
          decoration: InputDecoration(
            labelText: tr('Hạn chờ'),
            hintText: tr('Vd 15m, 2h; để trống = chờ tất cả'),
            helperText: '${n['timeout'] ?? ''}'.isEmpty ? null : tr('Quá {0} thì đi tiếp với các tiến trình đã xong', [durLabel('${n['timeout']}')]),
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) {
            v.trim().isEmpty ? n.remove('timeout') : n['timeout'] = v.trim();
            _changed();
          },
        ),
        const SizedBox(height: 12),
      ],
      TemplateField(
        label: tr('Tiêu đề tiến trình mới (không bắt buộc)'),
        raw: '${n['title'] ?? ''}',
        vars: [...rowVars, ...widget.vars],
        lines: 1,
        onChanged: (v) => v.isEmpty ? n.remove('title') : n['title'] = v,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(perPerson ? tr('Mỗi tiến trình mới đứng tên chính người nhận (họ là người tạo tiến trình đó).') : tr('Tiến trình mới đứng tên người tạo tiến trình này.'),
            style: TextStyle(color: pal.sub, fontSize: 12)),
      ),
    ]);
  }
}

/// Hộp phóng to / thu nhỏ nội dung: kích thước chiếm chỗ cũng nhân theo [scale] (khung cuộn tính đúng), chạm / kéo thả
/// vẫn đúng chỗ.
class ScaledBox extends SingleChildRenderObjectWidget {
  final double scale;
  const ScaledBox({super.key, required this.scale, super.child});
  @override
  RenderObject createRenderObject(BuildContext context) => RenderScaledBox(scale);
  @override
  void updateRenderObject(BuildContext context, RenderScaledBox renderObject) => renderObject.scale = scale;
}

class RenderScaledBox extends RenderProxyBox {
  RenderScaledBox(this._scale);
  double _scale;
  set scale(double v) {
    if (v == _scale) return;
    _scale = v;
    markNeedsLayout();
  }

  Matrix4 get _m => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void performLayout() {
    final c = constraints;
    double div(double x) => x.isFinite ? x / _scale : x;
    child!.layout(BoxConstraints(minWidth: div(c.minWidth), maxWidth: div(c.maxWidth), minHeight: div(c.minHeight), maxHeight: div(c.maxHeight)), parentUsesSize: true);
    size = c.constrain(child!.size * _scale);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_scale == 1) return context.paintChild(child!, offset);
    context.pushTransform(needsCompositing, offset, _m, (c, o) => c.paintChild(child!, o));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(transform: _m, position: position, hitTest: (r, p) => child!.hitTest(r, position: p));

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_m);
}
