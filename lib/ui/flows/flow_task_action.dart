import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../flygo_card.dart' show FlygoChoices;
import '../theme.dart';
import 'magic_sign_hooks.dart' show openFlowSignButton;

/// Phần thao tác của việc "Chờ bấm nút" / "Lựa chọn" (kind "action") trong Việc của tôi: nút (bấm một lần gửi
/// `{clicked: id}`) hoặc ô tích có min / max + Gửi (`{values: [...]}`), nộp qua POST /flows/tasks/{id}/submit.
/// Nút chỉ có `url` mở link, không nộp. [onSubmit] ném lỗi thì cho thao tác lại.
class FlowTaskActionPanel extends StatefulWidget {
  final FlowTask task;
  final Future<void> Function(Map<String, dynamic> data) onSubmit;
  /// Hiện câu hỏi (`prompt`) phía trên nút.
  final bool showPrompt;
  const FlowTaskActionPanel({super.key, required this.task, required this.onSubmit, this.showPrompt = true});
  @override
  State<FlowTaskActionPanel> createState() => _FlowTaskActionPanelState();
}

class _FlowTaskActionPanelState extends State<FlowTaskActionPanel> {
  bool _busy = false, _done = false;

  Future<void> _send(Map<String, dynamic> data, {bool rethrowErr = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.onSubmit(data);
      if (mounted) setState(() => _done = true);
      messenger.showSnackBar(toast(Text(tr('Đã gửi'))));
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không gửi được: {0}', ['$e']))));
      if (rethrowErr) rethrow;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _click(Map<String, dynamic> b) async {
    String s(Object? v) => v == null ? '' : '$v'.trim();
    if (await openFlowSignButton(context, b) || !mounted) return;
    final url = Uri.tryParse(s(b['url']));
    if (url != null && (url.scheme == 'https' || url.scheme == 'http')) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }
    final confirm = s(b['confirm']);
    if (confirm.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          content: Text(confirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
            TextButton(onPressed: () => Navigator.pop(d, true), child: Text(s(b['label']))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _send({'clicked': s(b['id'])});
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final a = widget.task.action ?? const {};
    final prompt = '${a['prompt'] ?? ''}'.trim();
    final choices = a['choices'] is Map ? (a['choices'] as Map).cast<String, dynamic>() : null;
    final buttons = [for (final b in (a['buttons'] as List? ?? const [])) if (b is Map) b.cast<String, dynamic>()];
    final locked = _busy || _done;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (widget.showPrompt && prompt.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(prompt, style: TextStyle(fontSize: 14, height: 1.35, color: pal.text))),
      if (a['kind'] == 'choice' && choices != null)
        FlygoChoices(
          choices: {...choices, if (_done) 'done': true},
          accent: pal.accent,
          pal: pal,
          onAction: (x) => _send({'values': [for (final v in (x['values'] as List? ?? const [])) '$v']}, rethrowErr: true),
        )
      else if (buttons.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          for (final b in buttons)
            if ('${b['url'] ?? ''}'.isNotEmpty)
              TextButton.icon(onPressed: () => _click(b), icon: Icon(b['sign'] is Map ? Icons.draw_outlined : Icons.open_in_new_rounded, size: 16), label: Text('${b['label'] ?? ''}'))
            else if (b['style'] == 'primary')
              FilledButton(onPressed: locked ? null : () => _click(b), child: Text('${b['label'] ?? b['id']}'))
            else
              OutlinedButton(onPressed: locked ? null : () => _click(b), child: Text('${b['label'] ?? b['id']}')),
        ]),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
    ]);
  }
}

/// Thông tin yêu cầu phê duyệt (bước Tạo phê duyệt): tiêu đề, lý do cần duyệt, cấp leo thang.
class FlowRequestInfo extends StatelessWidget {
  final Map<String, dynamic> request;
  const FlowRequestInfo({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final title = '${request['title'] ?? ''}'.trim(), reason = '${request['reason'] ?? ''}'.trim();
    final level = (request['level'] as num?)?.toInt() ?? 0;
    if (title.isEmpty && reason.isEmpty && level <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title.isNotEmpty) Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text)),
        if (reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('Lý do: {0}', [reason]), style: TextStyle(fontSize: 13.5, height: 1.35, color: pal.text)),
          ),
        if (level > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('Đã chuyển lên cấp {0}', [level]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ),
      ]),
    );
  }
}

/// Dòng nhắc màu cam (vd `Bị trả lại: <lý do>`).
class FlowNotice extends StatelessWidget {
  final String text;
  final IconData icon;
  const FlowNotice({super.key, required this.text, this.icon = Icons.undo_rounded});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    const orange = Color(0xFFE08A1E);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: orange.withValues(alpha: .12), borderRadius: BorderRadius.circular(10), border: Border.all(color: orange.withValues(alpha: .4))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: orange),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: pal.text))),
      ]),
    );
  }
}

/// `Bị trả lại: <lý do>` cho việc Điền thông tin bị trả lại (`returned` {reason, by, at, from}).
String flowReturnedText(Map<String, dynamic> returned, String Function(String id) name) {
  final reason = '${returned['reason'] ?? ''}'.trim();
  final by = name('${returned['by'] ?? ''}');
  final head = by.isEmpty ? tr('Bị trả lại') : tr('{0} trả lại', [by]);
  return reason.isEmpty ? head : '$head: $reason';
}
