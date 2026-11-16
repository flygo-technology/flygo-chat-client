// TeamWork: tiến độ trực tiếp của một lượt chạy agent (dưới bình luận @nhắc agent, trong thẻ agent của việc). Đang chạy: danh
// sách bước gọn (6 bước cuối, "xem tất cả N bước") + chữ đang viết (Markdown: bảng, mã…). Xong: thu gọn "✓ <Agent> đã xong ·
// N bước" (bấm để xem lại các bước); câu trả lời cuối là bình luận trả lời của agent ngay bên dưới. Ai đang xem việc cũng thấy.
// Cập nhật theo sự kiện run_progress (WebSocket) → GET /api/runs/:id, gom tối đa ~1,5 lần / giây.
import 'dart:async';

import 'package:flutter/material.dart';

import 'look.dart';
import 'model.dart';
import 'rich_mentions.dart';
import 'store.dart';

class TwRunProgress extends StatefulWidget {
  const TwRunProgress({super.key, required this.store, required this.runId, this.botId = '', this.botName = '', this.state = 'running', this.session, this.compact = false});
  final TwStore store;
  final String runId, botId, botName, state;
  /// Phiên của agent (nút "Mở phiên"; không cần để theo dõi tiến độ).
  final String? session;
  final bool compact;
  @override
  State<TwRunProgress> createState() => _TwRunProgressState();
}

class _TwRunProgressState extends State<TwRunProgress> {
  TwRun? _run;
  bool _all = false, _open = false, _loading = false;
  int _rev = -1;
  Timer? _throttle;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  TwStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
    _fetch();
  }

  @override
  void didUpdateWidget(TwRunProgress old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _fetch();
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    _throttle?.cancel();
    super.dispose();
  }

  void _onStore() {
    final r = store.runRev[widget.runId] ?? 0;
    if (r == _rev) return;
    _rev = r;
    final wait = const Duration(milliseconds: 700) - DateTime.now().difference(_last);
    _throttle?.cancel();
    _throttle = Timer(wait.isNegative ? Duration.zero : wait, _fetch);
  }

  Future<void> _fetch() async {
    if (_loading) return;
    _loading = true;
    _last = DateTime.now();
    _rev = store.runRev[widget.runId] ?? 0;
    try {
      final r = await store.api.run(widget.runId);
      if (mounted) setState(() => _run = r);
    } catch (_) {
    } finally {
      _loading = false;
    }
  }

  Widget _stepIcon(TwRunStep s, TwLook look) => switch (s.status) {
        'done' => Icon(Icons.check_rounded, size: 15, color: look.ok),
        'error' => Icon(Icons.close_rounded, size: 15, color: look.red),
        _ => SizedBox(width: 13, height: 13, child: Padding(padding: const EdgeInsets.all(1), child: CircularProgressIndicator(strokeWidth: 1.6, color: look.ai))),
      };

  Widget _steps(List<TwRunStep> steps, TwLook look, {bool limit = true}) {
    final shown = limit && !_all && steps.length > 6 ? steps.sublist(steps.length - 6) : steps;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (limit && steps.length > 6)
        InkWell(
          key: ValueKey('steps-all-${widget.runId}'),
          onTap: () => setState(() => _all = !_all),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(_all ? 'Thu gọn' : 'xem tất cả ${steps.length} bước', style: TextStyle(fontSize: 12, color: look.accent, fontWeight: FontWeight.w600)),
          ),
        ),
      for (final s in shown)
        Padding(
          key: ValueKey('step-${widget.runId}-${s.id}'),
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: SizedBox(width: 16, child: _stepIcon(s, look))),
            const SizedBox(width: 6),
            Expanded(
              child: Text(s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: s.kind == 'approval' ? look.ai : (s.status == 'error' ? look.red : look.text), fontWeight: s.kind == 'approval' ? FontWeight.w600 : null)),
            ),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final r = _run;
    final name = (r?.botName.isNotEmpty ?? false) ? r!.botName : (widget.botName.isNotEmpty ? widget.botName : store.agent(widget.botId)?.name ?? 'Agent');
    final state = r?.state ?? widget.state;
    final steps = r?.steps ?? const <TwRunStep>[];
    final n = steps.isNotEmpty ? steps.length : (r?.stepCount ?? 0);
    final session = r?.sessionChannel ?? widget.session;
    final finished = const ['review', 'done', 'failed', 'cancelled', 'blocked'].contains(state);
    final failed = const ['failed', 'blocked', 'cancelled'].contains(state);
    final openBtn = session != null && store.launcher != null
        ? TextButton(
            key: ValueKey('runline-open-${widget.botId.isEmpty ? widget.runId : widget.botId}'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 28)),
            onPressed: () => store.launcher!.open(session),
            child: const Text('Mở phiên', style: TextStyle(fontSize: 12)),
          )
        : null;

    if (finished) {
      final color = failed ? look.red : look.ok;
      final label = failed
          ? '$name ${state == 'cancelled' ? 'đã dừng' : 'gặp lỗi'}${n > 0 ? ' · $n bước' : ''}${r?.error != null ? ': ${r!.error}' : ''}'
          : '$name đã xong${n > 0 ? ' · $n bước' : ''}';
      return Padding(
        key: ValueKey('runline-${widget.botId.isEmpty ? widget.runId : widget.botId}'),
        padding: const EdgeInsets.only(top: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            InkWell(
              key: ValueKey('run-toggle-${widget.runId}'),
              onTap: steps.isEmpty ? null : () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(failed ? Icons.cancel_outlined : Icons.check_circle_outline, size: 15, color: color),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
                  ),
                  if (steps.isNotEmpty) Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16, color: look.sub),
                ]),
              ),
            ),
            ?openBtn,
          ]),
          if (_open) Padding(padding: const EdgeInsets.only(left: 4, top: 4), child: _steps(steps, look, limit: false)),
        ]),
      );
    }

    // Đang chạy: bước + chữ đang viết.
    return Container(
      key: ValueKey('runline-${widget.botId.isEmpty ? widget.runId : widget.botId}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      decoration: BoxDecoration(color: look.aiSoft, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: look.ai)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(state == 'queued' ? '$name đang chờ mở phiên…' : '$name đang xử lý…${n > 0 ? ' · $n bước' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: look.ai, fontWeight: FontWeight.w600)),
          ),
          ?openBtn,
        ]),
        if (steps.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: _steps(steps, look)),
        if ((r?.text ?? '').trim().isNotEmpty)
          Container(
            key: ValueKey('run-text-${widget.runId}'),
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: look.divider)),
            child: TwRichView(markdownToBlocks(r!.text!), style: TextStyle(fontSize: 13, height: 1.5, color: look.text)),
          ),
      ]),
    );
  }
}
