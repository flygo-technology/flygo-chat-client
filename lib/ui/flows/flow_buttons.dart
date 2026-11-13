import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/flows_api.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'magic_sign_hooks.dart' show openFlowSignButton;

/// Bộ nút do Quy trình đặt lên một tin (props.flygo_buttons): nút mở link, và nút "chạy tiếp quy trình"
/// (bấm thì luồng đi tiếp theo nút đã chọn; bấm xong cả bộ nút khoá lại, ghi ai đã chọn gì).
class FlowButtonsBar extends StatefulWidget {
  final AppState app;
  final MmPost post;
  const FlowButtonsBar({super.key, required this.app, required this.post});

  static bool has(MmPost p) => p.props['flygo_buttons'] is Map && ((p.props['flygo_buttons'] as Map)['buttons'] as List? ?? const []).isNotEmpty;

  @override
  State<FlowButtonsBar> createState() => _FlowButtonsBarState();
}

class _FlowButtonsBarState extends State<FlowButtonsBar> {
  String? _busy;
  /// Vừa bấm trên máy này (trước khi Flow Bot sửa tin).
  String? _picked;

  Map<String, dynamic> get _b => (widget.post.props['flygo_buttons'] as Map).cast<String, dynamic>();

  Future<void> _click(String label) async {
    final m = ScaffoldMessenger.of(context);
    setState(() => _busy = label);
    try {
      await FlowsApi(widget.app.token).click('${_b['instance_id']}', '${_b['node']}', label);
      if (mounted) setState(() => _picked = label);
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text(tr('Không gửi được: {0}', ['$e']))));
    }
    if (mounted) setState(() => _busy = null);
  }

  String _name(String id) {
    if (id == widget.app.me?.id) return tr('bạn');
    final u = widget.app.users[id];
    return u == null ? id : (u.displayName.isEmpty ? u.username : u.displayName);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final b = _b;
    final closed = b['state'] == 'closed' || _picked != null;
    final clicked = '${b['clicked'] ?? _picked ?? ''}';
    final who = [for (final x in (b['who'] as List? ?? const [])) '$x'];
    final allowed = who.isEmpty || who.contains(widget.app.me?.id);
    final buttons = [for (final x in (b['buttons'] as List? ?? const [])) if (x is Map) x];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final x in buttons)
          if ('${x['url'] ?? ''}'.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                if (await openFlowSignButton(context, x)) return;
                await launchUrl(Uri.parse('${x['url']}'), mode: LaunchMode.externalApplication);
              },
              icon: Icon(x['sign'] is Map ? Icons.draw_outlined : Icons.open_in_new_rounded, size: 16),
              label: Text('${x['label']}'),
            )
          else if (!closed)
            FilledButton(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: !allowed || _busy != null ? null : () => _click('${x['label']}'),
              child: _busy == x['label']
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('${x['label']}'),
            ),
        if (closed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: pal.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_rounded, size: 15, color: pal.accentText),
              const SizedBox(width: 5),
              Text(
                b['by'] != null ? tr('{0} · {1} đã chọn', [clicked, _name('${b['by']}')]) : clicked,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.accentText),
              ),
            ]),
          )
        else if (!allowed && buttons.any((x) => '${x['url'] ?? ''}'.isEmpty))
          Text(tr('Chỉ người được giao mới bấm được'), style: TextStyle(fontSize: 12, color: pal.sub)),
      ]),
    );
  }
}
