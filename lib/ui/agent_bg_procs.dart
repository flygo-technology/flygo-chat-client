import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';
import 'shell_highlight.dart' show kMonoFallback, kMonoFont, kNoLigatures;
import 'agent_view.dart' show AgentProgressBar;
import 'theme.dart';

/// Tiến trình nền của lượt chạy (props.flygo_agent.bg, runner 0.7.18+): mỗi mục {id, kind, command, label?, host?, status,
/// exit_code? (thường không có), started_at, ended_at?, tail, lines?, truncated?, note?}. Runner vá tin liên tục (kể cả sau khi lượt xong)
/// tới khi mọi tiến trình kết thúc.
List<Map<String, dynamic>> agentBgOf(Map<String, dynamic>? run) =>
    [for (final t in (run?['bg'] as List? ?? const [])) if (t is Map) t.cast<String, dynamic>()];

bool _running(Map<String, dynamic> t) => (t['status'] as String? ?? 'running') == 'running';

/// Thẻ chạy còn tác vụ nền đang chạy (kể cả khi lượt đã xong).
bool agentBgRunning(Map<String, dynamic>? run) => agentBgOf(run).any(_running);

/// "2m14s", "1h03m", "8s".
String bgElapsed(Map<String, dynamic> t, DateTime now) {
  final start = (t['started_at'] as num?)?.toInt();
  if (start == null) return '';
  final end = (t['ended_at'] as num?)?.toInt() ?? (_running(t) ? now.millisecondsSinceEpoch : (t['updated_at'] as num?)?.toInt() ?? start);
  final d = Duration(milliseconds: (end - start).clamp(0, 1 << 40));
  if (d.inHours > 0) return '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  return '${d.inSeconds}s';
}

const _green = Color(0xFF2E9D5B);
const _red = Color(0xFFE5484D);

/// Mục "Tác vụ nền" ở cuối thẻ chạy: mỗi tiến trình một dòng (lệnh, máy, trạng thái, thời gian đã chạy); bấm để xem
/// đầu ra trực tiếp. Xong hết thì gọn thành một dòng tóm tắt (bấm để mở lại).
class AgentBgTasks extends StatefulWidget {
  final List<Map<String, dynamic>> tasks;

  /// Khoá giữ trạng thái mở (id tin + id tiến trình): tin được vá liên tục, widget có thể bị tạo lại.
  final String openKey;

  /// Dừng một tác vụ nền (chủ bot / người giao việc; runner 0.7.27+): trả null khi xong, chuỗi lỗi khi không dừng được.
  /// null = không hiện nút Dừng.
  final Future<String?> Function(String taskId)? onStop;
  const AgentBgTasks({super.key, required this.tasks, required this.openKey, this.onStop});
  @override
  State<AgentBgTasks> createState() => _AgentBgTasksState();
}

class _AgentBgTasksState extends State<AgentBgTasks> {
  static final _open = <String>{}; // '<openKey>:<task id>' đang mở đầu ra; '<openKey>:*' mục đã xong đang mở
  static final _stopping = <String>{}; // '<openKey>:<task id>' đã bấm Dừng, chờ runner vá thẻ
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(AgentBgTasks old) {
    super.didUpdateWidget(old);
    _syncTimer();
  }

  // Đồng hồ "đã chạy" nhảy mỗi giây khi còn tiến trình chạy; xong hết thì dừng.
  void _syncTimer() {
    final need = widget.tasks.any(_running);
    if (need && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!need) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toggle(String k) => setState(() => _open.contains(k) ? _open.remove(k) : _open.add(k));

  /// Bấm Dừng: hỏi lại (dừng tiến trình là việc không hoàn tác) rồi nhờ runner dừng; lỗi thì báo ngay dưới đáy màn hình.
  Future<void> _stop(Map<String, dynamic> t) async {
    final stop = widget.onStop;
    final id = '${t['id'] ?? ''}';
    final k = '${widget.openKey}:$id';
    if (stop == null || id.isEmpty || _stopping.contains(k)) return;
    final cmd = '${t['label'] ?? t['command'] ?? ''}'.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Dừng tác vụ nền?')),
        content: Text(tr('Dừng tiến trình đang chạy "{0}" (và các tiến trình con của nó)?', [cmd])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
          TextButton(
              key: const ValueKey('bg-stop-confirm'),
              style: TextButton.styleFrom(foregroundColor: _red),
              onPressed: () => Navigator.pop(d, true),
              child: Text(tr('Dừng'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _stopping.add(k));
    final err = await stop(id);
    if (!mounted) return;
    setState(() => _stopping.remove(k));
    if (err != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Không dừng được: {0}', [err]))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final tasks = widget.tasks;
    final now = DateTime.now();
    final running = tasks.where(_running).length;
    final failed = tasks.where((t) => !_running(t) && t['status'] != 'done' && t['status'] != 'killed').length;
    final killed = tasks.where((t) => t['status'] == 'killed').length;
    final finished = tasks.length - running;
    final allDone = running == 0;
    final sectionKey = '${widget.openKey}:*';
    // Mặc định gọn một dòng (Sếp 25/11), bấm để xem từng tiến trình.
    final showRows = _open.contains(sectionKey);
    // Tiến trình nói tới ở dòng gọn: cái đang chạy lâu nhất, xong hết thì cái cuối.
    final focus = tasks.where(_running).firstOrNull ?? tasks.last;
    String nameOf(Map<String, dynamic> t) {
      final l = '${t['label'] ?? ''}'.trim();
      return l.isNotEmpty ? l : '${t['command'] ?? ''}'.replaceAll('\n', ' ').trim();
    }

    final summary = allDone
        ? [
            tr('{0} xong', [tasks.length - failed - killed]),
            if (killed > 0) tr('{0} dừng', [killed]),
            if (failed > 0) tr('{0} lỗi', [failed]),
          ].join(' · ')
        : tr('{0} đang chạy', [running]);
    final tint = allDone ? (failed > 0 ? _red : _green) : pal.accentText;
    final elapsed = allDone ? '' : bgElapsed(focus, now);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: pal.text.withValues(alpha: .035),
        border: Border.all(color: pal.text.withValues(alpha: .09)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          key: const ValueKey('bg-head'),
          onTap: () => _toggle(sectionKey),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(children: [
              Icon(Icons.memory_rounded, size: 17, color: tint),
              const SizedBox(width: 7),
              // Một dòng, quá dài thì cắt "…" ở cuối (không tràn trên điện thoại).
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: tr('Tác vụ nền'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                    TextSpan(text: '  ·  ', style: TextStyle(color: pal.sub)),
                    TextSpan(text: summary, style: TextStyle(fontWeight: FontWeight.w600, color: tint)),
                    if (!showRows) ...[
                      TextSpan(text: '  ·  ', style: TextStyle(color: pal.sub)),
                      TextSpan(text: nameOf(focus), style: TextStyle(color: pal.sub)),
                    ],
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (elapsed.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(elapsed,
                      style: TextStyle(fontSize: 12, color: pal.sub, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              const SizedBox(width: 2),
              AnimatedRotation(
                turns: showRows ? .5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more_rounded, size: 20, color: pal.sub),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
          child: AgentProgressBar(value: tasks.isEmpty ? 0 : finished / tasks.length, color: tint),
        ),
        if (showRows)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final t in tasks)
                _BgTaskRow(
                  key: ValueKey('bg-${t['id']}'),
                  task: t,
                  elapsed: bgElapsed(t, now),
                  open: _open.contains('${widget.openKey}:${t['id']}'),
                  onTap: () => _toggle('${widget.openKey}:${t['id']}'),
                  stopping: _stopping.contains('${widget.openKey}:${t['id']}'),
                  onStop: widget.onStop != null && _running(t) ? () => _stop(t) : null,
                ),
            ]),
          ),
      ]),
    );
  }
}

class _BgTaskRow extends StatelessWidget {
  final Map<String, dynamic> task;
  final String elapsed;
  final bool open;
  final VoidCallback onTap;
  final bool stopping;

  /// Nút Dừng (chỉ tác vụ đang chạy, người có quyền dừng).
  final VoidCallback? onStop;
  const _BgTaskRow(
      {super.key, required this.task, required this.elapsed, required this.open, required this.onTap, this.stopping = false, this.onStop});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final t = task;
    final status = t['status'] as String? ?? 'running';
    final exit = t['exit_code'];
    final cmd = '${t['command'] ?? ''}'.replaceAll('\n', ' ').trim();
    // Nhãn runner tự cắt từ lệnh ("ssh flygo-02 'nohup …"): trùng phần đầu lệnh thì không hiện lặp.
    var label = '${t['label'] ?? ''}'.trim();
    final stem = label.replaceAll(RegExp(r'…$'), '');
    if (stem.isNotEmpty && cmd.startsWith(stem)) label = '';
    final host = '${t['host'] ?? ''}'.trim() == 'local' ? '' : '${t['host'] ?? ''}'.trim();
    final note = '${t['note'] ?? ''}'.trim();
    final Widget icon = switch (status) {
      'running' => SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.7, color: pal.accentText)),
      'done' => const Icon(Icons.check_circle_rounded, size: 16, color: _green),
      'killed' => Icon(Icons.stop_circle_outlined, size: 16, color: pal.sub),
      _ => const Icon(Icons.error_rounded, size: 16, color: _red),
    };
    final state = switch (status) {
      'running' => tr('đang chạy'),
      'done' => exit == null ? tr('xong') : tr('xong · exit {0}', [exit]),
      'killed' => tr('đã dừng'),
      _ => exit == null ? tr('lỗi') : tr('lỗi · exit {0}', [exit]),
    };
    final mono = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontFeatures: kNoLigatures, fontSize: 12.5, color: pal.text);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: SizedBox(width: 18, height: 16, child: Center(child: icon))),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (label.isNotEmpty) Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text)),
                Text('\$ $cmd', maxLines: 1, overflow: TextOverflow.ellipsis, style: label.isEmpty ? mono : mono.copyWith(color: pal.sub, fontSize: 12)),
                Text(
                  [if (host.isNotEmpty) host, state, if (elapsed.isNotEmpty) elapsed].join(' · '),
                  style: TextStyle(fontSize: 12, color: status == 'running' || status == 'done' || status == 'killed' ? pal.sub : _red),
                ),
                // Ghi chú của runner ("dừng cùng lượt", "tệp output đứng yên, coi như xong"…).
                if (note.isNotEmpty) Text(note, style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: pal.sub)),
              ]),
            ),
            if (stopping)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 1, 6, 0),
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.7, color: pal.sub)),
              )
            else if (onStop != null)
              Tooltip(
                message: tr('Dừng tác vụ nền'),
                child: InkWell(
                  key: const ValueKey('bg-stop'),
                  customBorder: const CircleBorder(),
                  onTap: onStop,
                  child: const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 0), child: Icon(Icons.stop_circle_outlined, size: 18, color: _red)),
                ),
              ),
            Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: pal.sub),
          ]),
        ),
        if (open) BgOutputView(task: t),
      ]),
    );
  }
}

/// Đầu ra trực tiếp của một tiến trình nền: chữ đơn cách, tự cuộn xuống cuối khi có dòng mới (trừ khi người dùng đang
/// cuộn lên xem), nút sao chép.
class BgOutputView extends StatefulWidget {
  final Map<String, dynamic> task;
  const BgOutputView({super.key, required this.task});
  @override
  State<BgOutputView> createState() => _BgOutputViewState();
}

class _BgOutputViewState extends State<BgOutputView> {
  final _scroll = ScrollController();
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      // Người dùng cuộn lên: thôi tự cuộn; cuộn về cuối: tự cuộn lại.
      _follow = _scroll.position.maxScrollExtent - _scroll.offset < 24;
    });
    _toEnd();
  }

  @override
  void didUpdateWidget(BgOutputView old) {
    super.didUpdateWidget(old);
    if (old.task['tail'] != widget.task['tail'] && _follow) _toEnd();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final tail = '${widget.task['tail'] ?? ''}'.replaceAll(RegExp(r'\n+$'), '');
    final lines = (widget.task['lines'] as num?)?.toInt();
    final shown = tail.isEmpty ? 0 : '\n'.allMatches(tail).length + 1;
    final cut = widget.task['truncated'] == true || (lines != null && lines > shown);
    final file = '${widget.task['output_file'] ?? ''}'.trim();
    return Container(
      key: const ValueKey('bg-output'),
      margin: const EdgeInsets.only(top: 6, left: 24),
      decoration: BoxDecoration(color: pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 2, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                [
                  if (cut) tr('{0} dòng cuối / {1}', [shown, lines ?? '…']),
                  if (file.isNotEmpty) file,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: pal.sub),
              ),
            ),
            IconButton(
              tooltip: tr('Sao chép'),
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(Icons.copy_rounded, color: pal.sub),
              onPressed: tail.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: tail));
                      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã sao chép'))));
                    },
            ),
          ]),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(
              tail.isEmpty ? tr('(chưa có đầu ra)') : tail,
              style: TextStyle(
                  fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontFeatures: kNoLigatures, fontSize: 12, height: 1.4, color: tail.isEmpty ? pal.sub : pal.text),
            ),
          ),
        ),
      ]),
    );
  }
}
