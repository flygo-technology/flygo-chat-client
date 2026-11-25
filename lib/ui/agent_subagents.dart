import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'agent_bg_procs.dart' show bgElapsed;
import 'agent_link.dart' show AgentLinkTone;
import 'agent_traffic.dart';
import '../agent/agent_config.dart' show modelLabel;
import 'agent_view.dart' show AgentProgressBar;
import 'theme.dart';

/// Sub-agent của lượt chạy (props.flygo_agent.subagents, runner 0.7.37+): mỗi mục {id, type, title, prompt, model?,
/// background, status running|done|failed|stopped, started_at, ended_at?, updated_at, last_action?, tool_uses,
/// tokens? {input?, output?, total?}, result?, error?}.
List<Map<String, dynamic>> agentSubagentsOf(Map<String, dynamic>? run) =>
    [for (final t in (run?['subagents'] as List? ?? const [])) if (t is Map) t.cast<String, dynamic>()];

bool _running(Map<String, dynamic> s) => (s['status'] as String? ?? 'running') == 'running';

const _green = Color(0xFF2E9D5B);
const _red = Color(0xFFE5484D);
const _violet = Color(0xFF7C5CE0);

/// "12.4k token".
String _tokens(Map<String, dynamic> s) {
  final t = s['tokens'];
  if (t is! Map) return '';
  final n = ((t['total'] as num?) ?? (((t['input'] as num?) ?? 0) + ((t['output'] as num?) ?? 0))).toInt();
  if (n <= 0) return '';
  return n >= 1000 ? tr('{0}k token', [(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)]) : tr('{0} token', [n]);
}

String _statusText(Map<String, dynamic> s) => switch (s['status'] as String? ?? 'running') {
      'running' => tr('đang chạy'),
      'done' => tr('xong'),
      'stopped' => tr('đã dừng'),
      _ => tr('lỗi'),
    };

/// Mục "Sub-agent" ở cuối thẻ chạy, cạnh "Tác vụ nền": dòng tóm tắt + thanh tiến độ; danh sách từng sub-agent (loại,
/// mô tả, trạng thái, thời gian, việc vừa làm, mô hình, số lần dùng công cụ, token). Còn sub-agent chạy thì danh sách mở
/// sẵn; xong hết thì gọn một dòng (bấm để mở). Bấm một sub-agent: hộp xem lớn với lời giao việc + kết quả.
class AgentSubagents extends StatefulWidget {
  final List<Map<String, dynamic>> agents;
  final String openKey;

  /// Dừng một sub-agent (ext action subagent_stop): null khi xong, chuỗi lỗi khi không dừng được; null = không có nút.
  final Future<String?> Function(String id)? onStop;
  const AgentSubagents({super.key, required this.agents, required this.openKey, this.onStop});
  @override
  State<AgentSubagents> createState() => _AgentSubagentsState();
}

class _AgentSubagentsState extends State<AgentSubagents> {
  static final _toggled = <String>{}; // openKey đã bấm đổi trạng thái mở / gọn so với mặc định
  static final _stopped = <String>{}; // '<openKey>:<id>' đã dừng xong, chờ runner vá thẻ
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AgentSubagents old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final need = widget.agents.any(_running);
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

  void _open(BuildContext context, Map<String, dynamic> s) {
    final result = '${s['result'] ?? ''}'.trim();
    final error = '${s['error'] ?? ''}'.trim();
    final stop = widget.onStop;
    final k = '${widget.openKey}:${s['id']}';
    showAgentTraffic(
      context,
      AgentTraffic(
        // Màu tím như mục Sub-agent.
        tone: AgentLinkTone.external,
        sent: true,
        customIcon: Icons.smart_toy_outlined,
        title: tr('Sub-agent {0}', ['${s['type'] ?? ''}'.trim()]).trim(),
        status: _statusText(s),
        message: [
          if ('${s['title'] ?? ''}'.trim().isNotEmpty) '**${'${s['title']}'.trim()}**',
          '${s['prompt'] ?? ''}'.trim(),
        ].join('\n\n'),
        at: (s['started_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        // Xong: kết quả / lỗi; còn chạy: việc vừa làm (runner vá liên tục).
        replyText: result.isNotEmpty
            ? result
            : error.isNotEmpty
            ? error
            : (_running(s) && '${s['last_action'] ?? ''}'.trim().isNotEmpty ? '${s['last_action']}'.trim() : null),
        replyLabel: result.isNotEmpty ? tr('Kết quả') : (error.isNotEmpty ? tr('Lỗi') : tr('Đang làm')),
        replyOk: error.isEmpty,
        replyAt: (s['ended_at'] as num?)?.toInt(),
        onStop: stop != null && _running(s) && !_stopped.contains(k)
            ? () async {
                final err = await stop('${s['id']}');
                if (err == null) {
                  if (mounted) setState(() => _stopped.add(k));
                } else if (context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Không dừng được: {0}', [err]))));
                }
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final now = DateTime.now();
    final agents = [
      for (final s in widget.agents)
        if (_running(s) && _stopped.contains('${widget.openKey}:${s['id']}')) {...s, 'status': 'stopped', 'ended_at': now.millisecondsSinceEpoch} else s,
    ];
    final running = agents.where(_running).length;
    final failed = agents.where((s) => s['status'] == 'failed').length;
    final stopped = agents.where((s) => s['status'] == 'stopped').length;
    final allDone = running == 0;
    // Mặc định: còn chạy thì mở danh sách, xong hết thì gọn; bấm tiêu đề để đổi.
    final showRows = allDone == _toggled.contains(widget.openKey);
    final tint = allDone ? (failed > 0 ? _red : _green) : _violet;
    final summary = allDone
        ? [
            tr('{0} xong', [agents.length - failed - stopped]),
            if (stopped > 0) tr('{0} dừng', [stopped]),
            if (failed > 0) tr('{0} lỗi', [failed]),
          ].join(' · ')
        : tr('{0} đang chạy', [running]);
    final focus = agents.where(_running).firstOrNull ?? agents.last;
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
          key: const ValueKey('subagents-head'),
          onTap: () => setState(() => _toggled.contains(widget.openKey) ? _toggled.remove(widget.openKey) : _toggled.add(widget.openKey)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(children: [
              Icon(Icons.smart_toy_outlined, size: 17, color: tint),
              const SizedBox(width: 7),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: tr('Sub-agent'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                    TextSpan(text: '  ·  ', style: TextStyle(color: pal.sub)),
                    TextSpan(text: summary, style: TextStyle(fontWeight: FontWeight.w600, color: tint)),
                    if (!showRows) ...[
                      TextSpan(text: '  ·  ', style: TextStyle(color: pal.sub)),
                      TextSpan(text: '${focus['title'] ?? focus['type'] ?? ''}', style: TextStyle(color: pal.sub)),
                    ],
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
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
          child: AgentProgressBar(value: agents.isEmpty ? 0 : (agents.length - running) / agents.length, color: tint),
        ),
        if (showRows)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              for (final s in agents) _SubagentRow(key: ValueKey('subagent-${s['id']}'), s: s, now: now, onTap: () => _open(context, s)),
            ]),
          ),
      ]),
    );
  }
}

class _SubagentRow extends StatelessWidget {
  final Map<String, dynamic> s;
  final DateTime now;
  final VoidCallback onTap;
  const _SubagentRow({super.key, required this.s, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final status = s['status'] as String? ?? 'running';
    final type = '${s['type'] ?? ''}'.trim();
    final title = '${s['title'] ?? ''}'.trim();
    final last = '${s['last_action'] ?? ''}'.trim();
    final model = '${s['model'] ?? ''}'.trim();
    final uses = (s['tool_uses'] as num?)?.toInt() ?? 0;
    final Widget icon = switch (status) {
      'running' => const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.7, color: _violet)),
      'done' => const Icon(Icons.check_circle_rounded, size: 16, color: _green),
      'stopped' => Icon(Icons.stop_circle_outlined, size: 16, color: pal.sub),
      _ => const Icon(Icons.error_rounded, size: 16, color: _red),
    };
    final meta = [
      _statusText(s),
      bgElapsed(s, now),
      if (model.isNotEmpty) modelLabel(model),
      if (uses > 0) tr('{0} công cụ', [uses]),
      if (_tokens(s).isNotEmpty) _tokens(s),
      if (s['background'] == true) tr('chạy nền'),
    ].where((x) => x.isNotEmpty).join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: SizedBox(width: 18, height: 16, child: Center(child: icon))),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (type.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: _violet.withValues(alpha: .13), borderRadius: BorderRadius.circular(6)),
                    child: Text(type, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _violet)),
                  ),
                Expanded(
                  child: Text(title.isEmpty ? tr('Sub-agent') : title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: status == 'failed' ? _red : pal.sub, fontFeatures: const [FontFeature.tabularFigures()])),
              if (last.isNotEmpty && status == 'running')
                Row(children: [
                  Icon(Icons.subdirectory_arrow_right_rounded, size: 13, color: pal.sub),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(last,
                        key: const ValueKey('subagent-last'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: pal.sub)),
                  ),
                ]),
            ]),
          ),
          Icon(Icons.open_in_full_rounded, size: 15, color: pal.sub),
        ]),
      ),
    );
  }
}
