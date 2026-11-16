import 'package:flutter/material.dart';

import 'model.dart';
import 'store.dart';
import 'widgets.dart';

/// "Tóm tắt bằng AI": AI đọc các thư chưa đọc (kèm vài thư trước trong mỗi hội thoại) và liệt kê việc cần làm.
/// Chạm một việc để mở hội thoại của nó. Màn hình rộng: hộp thoại; điện thoại: bảng trượt từ dưới lên.
Future<void> showMailDigest(BuildContext context, MailStore store, {required bool wide, required void Function(String threadId) onOpen}) {
  final body = _Digest(store: store, onOpen: (id) {
    Navigator.of(context).pop();
    onOpen(id);
  });
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640), child: body),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: body),
  );
}

class _Digest extends StatefulWidget {
  const _Digest({required this.store, required this.onOpen});
  final MailStore store;
  final void Function(String threadId) onOpen;
  @override
  State<_Digest> createState() => _DigestState();
}

class _DigestState extends State<_Digest> {
  MailDigest? _d;
  Object? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await widget.store.api.aiDigest();
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final d = _d;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.auto_awesome, size: 20, color: mc.accentText),
          const SizedBox(width: 8),
          Expanded(child: Text('Tóm tắt bằng AI', style: TextStyle(fontSize: 16, color: mc.text, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Tóm tắt lại', onPressed: _busy ? null : _run, icon: const Icon(Icons.refresh, size: 20)),
        ]),
        if (d != null && d.threads > 0)
          Text('Từ ${d.threads} cuộc hội thoại chưa đọc', style: TextStyle(fontSize: 12, color: mc.muted)),
        const SizedBox(height: 8),
        Expanded(
          child: _busy && d == null
              ? Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(height: 12),
                  Text('AI đang đọc các thư chưa đọc…', style: TextStyle(color: mc.muted)),
                ])
              : _err != null
                  ? Center(child: Text('Không tóm tắt được: $_err', textAlign: TextAlign.center, style: TextStyle(color: mc.danger)))
                  : ListView(padding: const EdgeInsets.only(right: 8), children: [
                      if (d!.summary.isNotEmpty) Text(d.summary, style: TextStyle(fontSize: 14, color: mc.text, height: 1.45)),
                      if (d.tasks.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text('Việc cần làm', style: TextStyle(fontSize: 12.5, color: mc.muted, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        for (final t in d.tasks) _task(t, mc),
                      ],
                    ]),
        ),
        const SizedBox(height: 6),
        Text('AI chỉ đọc thư, không gửi hay đổi gì trong hộp thư.', style: TextStyle(fontSize: 11.5, color: mc.faint)),
      ]),
    );
  }

  Widget _task(MailDigestTask t, MailColors mc) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: t.threadId == null ? null : () => widget.onOpen(t.threadId!),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(t.urgent ? Icons.priority_high : Icons.check_box_outline_blank, size: 16, color: t.urgent ? mc.danger : mc.muted),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.text, style: TextStyle(fontSize: 13.5, color: mc.text, fontWeight: t.urgent ? FontWeight.w600 : FontWeight.w400)),
                if (t.from.isNotEmpty || t.due.isNotEmpty || t.subject.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [if (t.from.isNotEmpty) t.from, if (t.due.isNotEmpty) 'Hạn: ${t.due}', if (t.subject.isNotEmpty) t.subject].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: mc.muted),
                    ),
                  ),
              ]),
            ),
            if (t.threadId != null) Icon(Icons.chevron_right, size: 18, color: mc.faint),
          ]),
        ),
      );
}
