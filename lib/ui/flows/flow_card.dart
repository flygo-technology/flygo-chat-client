import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../file_card.dart';
import '../markdown_view.dart';
import '../flygo_card.dart' show askFlygoCardInput, FlygoTags;
import '../flygo_card_action.dart';
import '../theme.dart';
import 'flows_page.dart' show openFlowInstance, FlowProgressBar;

/// Thẻ quy trình trong khung chat (props.flygo_flow, do Flow Bot gửi): thẻ duyệt có nút Duyệt / Từ chối / Trả lại,
/// thẻ trạng thái của người tạo đơn, thông báo kết quả.

Map<String, dynamic>? flowPropsOf(MmPost post) {
  final f = post.props['flygo_flow'];
  return f is Map ? f.cast<String, dynamic>() : null;
}

const kFlowGreen = Color(0xFF2EAD6B);
const kFlowRed = Color(0xFFE5484D);
const kFlowOrange = Color(0xFFE08A1E);

/// Biểu tượng, màu và nhãn đầu thẻ theo loại tin.
(IconData, Color, String) flowCardHead(Map<String, dynamic> p, Color accent) {
  final kind = '${p['kind'] ?? ''}';
  final state = '${p['state'] ?? ''}';
  if (kind == 'decided' || state == 'decided') {
    return switch ('${(p['decided'] as Map?)?['decision'] ?? ''}') {
      'approve' => (Icons.check_circle_rounded, kFlowGreen, tr('Đã duyệt')),
      'reject' => (Icons.cancel_rounded, kFlowRed, tr('Đã từ chối')),
      _ => (Icons.undo_rounded, kFlowOrange, tr('Đã trả lại')),
    };
  }
  return switch (kind) {
    'approval_request' => (Icons.how_to_reg_rounded, accent, tr('Cần bạn duyệt')),
    'form_request' || 'manual_request' => (Icons.edit_note_rounded, accent, tr('Cần bạn làm')),
    'reminder' => (Icons.alarm_rounded, kFlowOrange, tr('Nhắc: đang chờ bạn')),
    'returned' => (Icons.undo_rounded, kFlowOrange, tr('Đơn bị trả lại')),
    'done' => (Icons.verified_rounded, kFlowGreen, tr('Đơn đã hoàn tất')),
    'rejected' => (Icons.cancel_rounded, kFlowRed, tr('Đơn bị từ chối')),
    'cancelled' => (Icons.block_rounded, kFlowRed, tr('Đơn đã hủy')),
    'failed' => (Icons.error_outline_rounded, kFlowRed, tr('Đơn bị lỗi')),
    'notify' => (Icons.notifications_active_outlined, accent, tr('Thông báo quy trình')),
    _ => (Icons.route_rounded, accent, tr('Đơn của bạn')),
  };
}

/// Hỏi lý do (bắt buộc) khi từ chối / trả lại. Hủy: null.
Future<String?> askFlowReason(BuildContext context, String title) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(hintText: tr('Lý do (bắt buộc)'), border: const OutlineInputBorder()),
          onChanged: (_) => set(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          FilledButton(onPressed: ctl.text.trim().isEmpty ? null : () => Navigator.pop(d, ctl.text.trim()), child: Text(tr('Gửi'))),
        ],
      ),
    ),
  );
}

/// Duyệt / từ chối / trả lại một việc (từ chối / trả lại thì hỏi lý do trước). [onSending] gọi khi bắt đầu gửi.
/// [returnSteps] (bước Tạo phê duyệt): trả lại thì chọn thêm bước trả về [{id, label}], gửi kèm `return_step`.
/// Trả về true nếu xong.
Future<bool> decideFlowTask(BuildContext context, FlowsApi api, int taskId, String decision,
    {VoidCallback? onSending, List<Map<String, dynamic>> returnSteps = const []}) async {
  final messenger = ScaffoldMessenger.of(context);
  String? comment, returnStep;
  if (decision == 'return' && returnSteps.isNotEmpty) {
    final r = await askFlygoCardInput(context, {
      'label': tr('Trả lại'),
      'input': {'label': tr('Lý do trả lại'), 'required': true},
      'select': {'label': tr('Trả về bước'), 'options': returnSteps},
    });
    if (r == null || (r['reason'] ?? '').isEmpty) return false;
    comment = r['reason'];
    returnStep = r['value'];
  } else if (decision != 'approve') {
    comment = await askFlowReason(context, decision == 'reject' ? tr('Từ chối đơn') : tr('Trả lại để sửa'));
    if (comment == null) return false;
  }
  onSending?.call();
  try {
    await api.decide(taskId, decision, comment: comment, returnStep: returnStep);
    messenger.showSnackBar(toast(Text(switch (decision) {
      'approve' => tr('Đã duyệt'),
      'reject' => tr('Đã từ chối'),
      _ => tr('Đã trả lại'),
    })));
    return true;
  } catch (e) {
    messenger.showSnackBar(toast(Text(tr('Không gửi được: {0}', ['$e']))));
    return false;
  }
}

class FlowPostCard extends StatefulWidget {
  final AppState app;
  final MmPost post;
  final double width;
  /// Phần đính liền ở cuối thẻ (ghi chú dán lên tin).
  final Widget? footer;
  const FlowPostCard({super.key, required this.app, required this.post, required this.width, this.footer});
  @override
  State<FlowPostCard> createState() => _FlowPostCardState();
}

class _FlowPostCardState extends State<FlowPostCard> {
  bool _busy = false;
  /// Kết quả vừa bấm trên máy này (trước khi Flow Bot sửa thẻ thật).
  Map<String, dynamic>? _local;

  Map<String, dynamic> get _p => _local ?? flowPropsOf(widget.post) ?? const {};

  @override
  void didUpdateWidget(FlowPostCard old) {
    super.didUpdateWidget(old);
    if (old.post.updateAt != widget.post.updateAt) _local = null;
  }

  String _name(String id) {
    final u = widget.app.users[id];
    if (u == null && id.isNotEmpty) widget.app.refreshUser(id).catchError((_) {});
    return u?.displayName ?? '';
  }

  Future<void> _decide(String decision) async {
    final taskId = (_p['task_id'] as num?)?.toInt();
    if (taskId == null) return;
    final ok = await decideFlowTask(context, FlowsApi(widget.app.token), taskId, decision, onSending: () => setState(() => _busy = true));
    if (ok) {
      // Hiện ngay "đã quyết" trên máy này; Flow Bot sẽ sửa thẻ thật sau vài giây.
      final done = {..._p, 'kind': 'decided', 'state': 'decided', 'actions': const [], 'decided': {'by': widget.app.me?.id, 'decision': decision}};
      _local = done;
      widget.app.mergeLocalProps(widget.post, {'flygo_flow': done});
    }
    if (mounted) setState(() => _busy = false);
  }

  /// "Bạn đã duyệt", "Tuấn đã từ chối"…
  String _decidedLine(Map<String, dynamic> d) {
    final by = '${d['by']}';
    final who = by == widget.app.me?.id ? tr('Bạn') : _name(by);
    if (who.isEmpty) return '';
    return switch ('${d['decision'] ?? ''}') {
      'approve' => tr('{0} đã duyệt', [who]),
      'reject' => tr('{0} đã từ chối', [who]),
      'return' => tr('{0} đã trả lại', [who]),
      _ => who,
    };
  }

  void _open() => openFlowInstance(context, widget.app, '${_p['instance_id']}');

  Widget _extraButton(Map<String, dynamic> b) {
    void run() => runFlygoCardAction(context, widget.app, widget.post, b);
    final label = Text('${b['label']}');
    return b['style'] == 'primary' ? FilledButton(onPressed: run, child: label) : OutlinedButton(onPressed: run, child: label);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = _p;
    final (icon, color, label) = flowCardHead(p, pal.accentText);
    final summary = [for (final r in (p['summary'] as List? ?? const [])) if (r is List && r.length == 2) ('${r[0]}', '${r[1]}')];
    final note = (p['ai_note'] as Map?)?.cast<String, dynamic>();
    final actions = [for (final a in (p['actions'] as List? ?? const [])) '$a'];
    final open = '${p['state']}' == 'open';
    final step = '${p['step'] ?? ''}';
    final waiting = [for (final x in (p['waiting_for'] as List? ?? const [])) '$x'];
    final decided = (p['decided'] as Map?)?.cast<String, dynamic>();
    final requester = '${p['requester'] ?? ''}';
    final text = '${p['text'] ?? ''}';
    final title = '${p['title'] ?? ''}';
    final flowName = '${p['flow_name'] ?? ''}';
    // Nút riêng của quy trình (props buttons, tối đa 4, cùng dạng action của flygo_card), nhãn và tệp đính kèm.
    final buttons = [for (final b in (p['buttons'] as List? ?? const []).take(4)) if (b is Map && '${b['label'] ?? ''}'.isNotEmpty) b.cast<String, dynamic>()];
    final tags = p['tags'] is List ? p['tags'] as List : const [];
    final files = [for (final f in (p['files'] as List? ?? const [])) if (f is Map) f.cast<String, dynamic>()];
    // Tin đã xong: nút trả lời bỏ đi (url / mở / sao chép vẫn giữ).
    final shownButtons = [for (final b in buttons) if (open || b['reply'] == null) b];
    return Container(
      width: widget.width.clamp(220.0, 380.0),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .35))),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Container(
          color: color.withValues(alpha: .10),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13.5))),
            if ('${p['icon'] ?? ''}'.isNotEmpty && p['icon'] != null) Text('${p['icon']}', style: const TextStyle(fontSize: 16)),
          ]),
        ),
        InkWell(
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.isEmpty || title == flowName ? flowName : title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text)),
              if (title.isNotEmpty && title != flowName) Text(flowName, style: TextStyle(fontSize: 12.5, color: pal.sub)),
              if (tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: FlygoTags(tags)),
              // Người đề xuất là bot (Flow Bot tự chạy theo lịch): không hiện, chỉ hiện khi là người thật.
              if (requester.isNotEmpty && requester != widget.app.me?.id && widget.app.users[requester]?.isBot != true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tr('Người đề xuất: {0}', [_name(requester)]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
                ),
              // Nội dung của quy trình là markdown (**đậm**, link…): vẽ đúng định dạng, không hiện dấu ** (Sếp, 2026-11-11).
              if (text.isNotEmpty && text != 'null')
                Padding(padding: const EdgeInsets.only(top: 6), child: MarkdownView(text: text, style: TextStyle(color: pal.text, fontSize: 14.5))),
              // Tiến độ của việc (bước Báo tiến độ).
              FlowProgressBar(progress: p['progress'], compact: true),
              if (summary.isNotEmpty) const SizedBox(height: 8),
              for (final (k, v) in summary)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 110, child: Text(k, style: TextStyle(color: pal.sub, fontSize: 13))),
                    Expanded(child: Text(v, style: TextStyle(color: pal.text, fontSize: 13.5, fontWeight: FontWeight.w500))),
                  ]),
                ),
              if (note != null && '${note['text'] ?? ''}'.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: (note['level'] == 'warn' ? kFlowOrange : kFlowGreen).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(note['level'] == 'warn' ? Icons.warning_amber_rounded : Icons.auto_awesome_rounded,
                        size: 16, color: note['level'] == 'warn' ? kFlowOrange : kFlowGreen),
                    const SizedBox(width: 6),
                    Expanded(child: Text('AI: ${note['text']}', style: TextStyle(fontSize: 12.5, color: pal.text))),
                  ]),
                ),
              if (step.isNotEmpty || waiting.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    waiting.isEmpty ? step : tr('{0} · chờ {1}', [step, waiting.map(_name).where((n) => n.isNotEmpty).join(', ')]),
                    style: TextStyle(fontSize: 12.5, color: pal.sub),
                  ),
                ),
              if (decided != null && decided['by'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    [
                      _decidedLine(decided),
                      if ('${decided['comment'] ?? ''}'.isNotEmpty && decided['comment'] != null) '“${decided['comment']}”',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12.5, color: pal.sub),
                  ),
                ),
            ]),
          ),
        ),
        // Tệp đính kèm ngay trong thẻ: tệp của tin (file_ids) hoặc tệp của tiến trình (open).
        if (files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final f in files)
                if (f['file_id'] != null)
                  for (final mf in widget.post.files.where((x) => x.id == '${f['file_id']}'))
                    Padding(padding: const EdgeInsets.only(top: 4), child: FileCard(file: mf))
                else if (f['open'] is Map)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Align(alignment: Alignment.centerLeft, child: Text('${f['name'] ?? tr('Tệp')}', overflow: TextOverflow.ellipsis)),
                      onPressed: () => runFlygoCardAction(context, widget.app, widget.post, {'label': '${f['name'] ?? ''}', 'open': f['open']}),
                    ),
                  ),
            ]),
          ),
        if (shownButtons.isNotEmpty && !(open && actions.isNotEmpty)) ...[
          Divider(height: 1, color: pal.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [for (final b in shownButtons) _extraButton(b)]),
          ),
        ],
        if (open && actions.isNotEmpty) ...[
          Divider(height: 1, color: pal.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: _busy
                ? const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                : Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
                    if (actions.contains('return')) TextButton(onPressed: () => _decide('return'), child: Text(tr('Trả lại'))),
                    if (actions.contains('reject'))
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: kFlowRed),
                        onPressed: () => _decide('reject'),
                        child: Text(tr('Từ chối')),
                      ),
                    if (actions.contains('approve'))
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: kFlowGreen),
                        onPressed: () => _decide('approve'),
                        child: Text(tr('Duyệt')),
                      ),
                    if (actions.contains('claim')) FilledButton(onPressed: () => _decide('approve'), child: Text(tr('Tiếp nhận'))),
                    if (actions.contains('open'))
                      FilledButton(onPressed: _open, child: Text(p['kind'] == 'notify' ? tr('Mở tiến trình') : tr('Mở để duyệt'))),
                    if (actions.contains('submit') || actions.contains('resubmit'))
                      FilledButton(onPressed: _open, child: Text(actions.contains('resubmit') ? tr('Sửa và nộp lại') : tr('Mở để làm'))),
                    // Nút riêng của quy trình đứng sau các nút có sẵn.
                    for (final b in shownButtons) _extraButton(b),
                  ]),
          ),
        ],
        if (widget.footer != null) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 10), child: widget.footer),
      ]),
    );
  }
}
