import 'dart:convert';
import '../i18n/i18n.dart';
import '../agent/agent_config.dart';
import '../config.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'agent_files.dart';
import 'json_view.dart';
import 'markdown_view.dart';
import 'shell_highlight.dart';
import 'theme.dart';

/// Hiển thị tin của bot AI (runner flygo-agent):
/// - props.flygo_agent: thẻ tiến trình (trạng thái + các bước), được sửa liên tục.
/// - props.flygo_agent_message: tin trả lời, nội dung markdown được sửa dần khi đang stream.
/// - props.flygo_agent_approval: yêu cầu duyệt — nút "Xác nhận" / "Từ chối" gửi cảm xúc +1 / -1.

Map<String, dynamic>? agentRunOf(MmPost p) => (p.props['flygo_agent'] as Map?)?.cast<String, dynamic>();
Map<String, dynamic>? agentMessageOf(MmPost p) => (p.props['flygo_agent_message'] as Map?)?.cast<String, dynamic>();
Map<String, dynamic>? agentApprovalOf(MmPost p) => (p.props['flygo_agent_approval'] as Map?)?.cast<String, dynamic>();

/// Câu hỏi trắc nghiệm của trợ lý (props.flygo_agent_question):
/// {id, question, options:[{label, description?}], multi?:bool, allow_other?:bool, status:'pending'|'answered', answer?}.
Map<String, dynamic>? agentQuestionOf(MmPost p) => (p.props['flygo_agent_question'] as Map?)?.cast<String, dynamic>();

/// Claude Code tự hỏi bằng công cụ AskUserQuestion: runner cũ đưa ra như một yêu cầu duyệt có tiêu đề
/// "AskUserQuestion {json}". Đổi thành câu hỏi trắc nghiệm (câu đầu tiên) để hiện thẻ lựa chọn.
Map<String, dynamic>? askUserQuestionOf(MmPost p, Map<String, dynamic> approval) {
  for (final t in [approval['title'], approval['detail']]) {
    if (t is! String) continue;
    final i = t.indexOf('AskUserQuestion');
    if (i < 0) continue;
    final j = t.indexOf('{', i);
    if (j < 0) continue;
    Map<String, dynamic>? q;
    try {
      final m = (jsonDecode(t.substring(j)) as Map).cast<String, dynamic>();
      final qs = m['questions'] as List? ?? const [];
      if (qs.isNotEmpty) q = (qs.first as Map).cast<String, dynamic>();
    } catch (_) {
      // Runner cắt ngắn tiêu đề (JSON dở dang): lấy câu hỏi và các lựa chọn đọc được.
      final raw = t.substring(j);
      String? str(String key) => RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(raw)?.group(1);
      final question = str('question');
      if (question != null) {
        final opts = <Map<String, String>>[];
        for (final m in RegExp(r'"label"\s*:\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*"description"\s*:\s*"((?:[^"\\]|\\.)*)")?')
            .allMatches(raw)) {
          opts.add({'label': m.group(1)!, if (m.group(2) != null) 'description': m.group(2)!});
        }
        final multi = RegExp(r'"multiSelect"\s*:\s*true').hasMatch(raw) ||
            RegExp(r'chọn (được )?nhiều|nhiều lựa chọn|multiple', caseSensitive: false).hasMatch(question);
        if (opts.isNotEmpty) q = {'question': question, 'options': opts, 'multiSelect': multi};
      }
    }
    if (q == null) continue;
    return {
      'id': p.id,
      'question': q['question'],
      'options': q['options'] ?? const [],
      'multi': q['multiSelect'] == true,
      'allow_other': true,
      'status': approval['status'] ?? 'pending',
      'kind': 'ask_user_question',
    };
  }
  return null;
}

bool isAgentPost(MmPost p) => agentRunOf(p) != null || agentMessageOf(p) != null || agentApprovalOf(p) != null;

/// Nội dung hiển thị: bỏ dòng hashtag lọc (#flygo_ai #ai_...) và dòng "Thả 👍/👎" dự phòng cho client khác.
String agentDisplayText(MmPost p) {
  if (!isAgentPost(p)) return p.message;
  final lines = p.message.split('\n').where((l) {
    final t = l.trim();
    if (t.startsWith('#flygo_ai') || RegExp(r'^(#ai_\w+\s*)+$').hasMatch(t)) return false;
    if (t.contains(r'Thả 👍') || t.contains(r'Thả 👎')) return false;
    return true;
  }).toList();
  // Tin cuối mở đầu bằng "@chủ-việc" (để chủ việc nhận thông báo): giữ nguyên, hiện thành tag tô màu như tin của người.
  return lines.join('\n').trim();
}

String _statusLabel(String s) => switch (s) {
  'thinking' => tr('Đang suy nghĩ'),
  'running' => tr('Đang làm'),
  'awaiting_approval' => tr('Chờ duyệt'),
  'queued' => tr('Đang xếp hàng'),
  'done' => tr('Xong'),
  'error' => tr('Lỗi'),
  'cancelled' => tr('Đã dừng'),
  // Đoạn trước tin chèn của người (runner 0.7.28+): phần trả lời tiếp là tin mới bên dưới.
  'continued' => tr('Tiếp ở tin dưới'),
  _ => s,
};

Color _statusColor(String s, Pal pal) => switch (s) {
  'done' => const Color(0xFF2E9D5B),
  'error' => Colors.redAccent,
  'awaiting_approval' => const Color(0xFFF5A623),
  'cancelled' || 'continued' => pal.sub,
  _ => pal.accentText,
};

IconData _kindIcon(String kind) => switch (kind) {
  'command' => Icons.terminal_rounded,
  'file' => Icons.description_outlined,
  'tool' => Icons.build_outlined,
  'search' => Icons.search_rounded,
  'thinking' => Icons.psychology_outlined,
  'approval' => Icons.verified_user_outlined,
  'report' => Icons.campaign_outlined,
  'message' => Icons.forum_outlined,
  _ => Icons.circle_outlined,
};

/// Thẻ tiến trình: một dòng gọn (vòng quay + tên việc + "đang làm · N bước"), bấm để xem các bước.
class AgentRunCard extends StatefulWidget {
  final Map<String, dynamic> run;

  /// Gọn: không hiện tên việc (nằm chung với câu trả lời), chữ nhỏ hơn.
  final bool compact;

  /// Dạng gọn: tên bot đặt ngay sau biểu tượng trạng thái, cùng dòng với mô hình + mức suy nghĩ.
  final Widget? name;

  /// Khoá giữ trạng thái mở/đóng danh sách bước (id tin): tin đang chạy được dựng lại liên tục (chữ viết dần,
  /// đổi bố cục khi dài ra), thẻ có thể bị tạo lại và tự thu gọn nếu chỉ giữ trạng thái trong widget.
  final String? openKey;
  /// Các bước đã hiện ở dòng thời gian ([AgentTimeline]): thẻ không mở danh sách bước nữa.
  final bool stepsElsewhere;
  /// Kế hoạch việc (todos) vẽ ở thẻ này; false khi tin tự vẽ kế hoạch ở cuối tin ([AgentTodoList] dưới câu trả lời).
  final bool showTodos;
  const AgentRunCard(
      {super.key,
      required this.run,
      this.compact = false,
      this.name,
      this.openKey,
      this.stepsElsewhere = false,
      this.quiet = false,
      this.showTodos = true});
  /// Chat 1-1 với trợ lý (kiểu Claude): không có biểu tượng trạng thái / vòng xoay ở đầu tin.
  final bool quiet;
  @override
  State<AgentRunCard> createState() => _AgentRunCardState();
}

class _AgentRunCardState extends State<AgentRunCard> {
  /// Mặc định mở (hiện đủ các bước); đây là các thẻ người dùng đã bấm thu gọn (theo [AgentRunCard.openKey]), sống suốt phiên app.
  static final _closed = <String>{};
  bool _openLocal = true;

  bool get _open => widget.openKey == null ? _openLocal : !_closed.contains(widget.openKey);
  void _toggle() => setState(() {
        final k = widget.openKey;
        if (k == null) {
          _openLocal = !_openLocal;
        } else if (!_closed.remove(k)) {
          _closed.add(k);
        }
      });

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final r = widget.run;
    final status = r['status'] as String? ?? 'running';
    final steps = widget.stepsElsewhere ? const <Map<String, dynamic>>[] : [for (final s in (r['steps'] as List? ?? const [])) (s as Map).cast<String, dynamic>()];
    final active = status == 'thinking' || status == 'running';
    final todos = [for (final t in (r['todos'] as List? ?? const [])) if (t is Map) t.cast<String, dynamic>()];
    final title = (r['title'] as String? ?? '').trim();
    final engine = r['engine'] as String? ?? '';
    final error = r['error'] as String?;
    // Mô hình + mức suy nghĩ đã dùng cho lượt này (runner 0.3+ ghi vào config).
    final cfg = (r['config'] as Map?)?.cast<String, dynamic>();
    final cfgText = cfg == null
        ? ''
        : [if (cfg['model'] is String) modelLabel(cfg['model'] as String), if (cfg['effort'] != null) effortLabel(cfg['effort'] as String)].join(' · ');
    // Chat kiểu Claude, dạng gọn trong câu trả lời, các bước nằm ở dòng thời gian: bỏ dòng "✳ Opus 5.5 ▂▄" như app
    // Claude (Sếp duyệt mockup 2026-11-18); ghi chú, lỗi, kế hoạch việc vẫn hiện.
    final hideHead = widget.quiet && widget.compact && steps.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hideHead)
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: steps.isEmpty ? null : _toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.quiet) ...[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: active
                      ? CircularProgressIndicator(strokeWidth: 2, color: pal.accentText)
                      : Icon(
                          status == 'done'
                              ? Icons.check_circle_rounded
                              : status == 'error'
                              ? Icons.error_rounded
                              : status == 'awaiting_approval'
                              ? Icons.pause_circle_filled_rounded
                              : Icons.stop_circle_outlined,
                          size: 16,
                          color: _statusColor(status, pal),
                        ),
                ),
                const SizedBox(width: 8),
                ],
                if (!widget.compact)
                  Flexible(
                    child: Text(
                      title.isEmpty ? (engine.isEmpty ? tr('Trợ lý AI') : engine) : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text),
                    ),
                  ),
                if (!widget.compact) const SizedBox(width: 8),
                // Dạng gọn (trong câu trả lời): chỉ biểu tượng trạng thái, tên mô hình và vạch mức suy nghĩ.
                if (!widget.compact)
                  Text(
                    steps.isEmpty ? _statusLabel(status) : tr('{0} · {1} bước', [_statusLabel(status).toLowerCase(), steps.length]),
                    style: TextStyle(fontSize: 13, color: _statusColor(status, pal)),
                  ),
                if (!widget.compact && cfgText.isNotEmpty) Text(' · $cfgText', style: TextStyle(fontSize: 12.5, color: pal.sub)),
                if (widget.compact) ...[
                  EngineIcon(engine, size: 15, color: pal.text),
                  const SizedBox(width: 6),
                ],
                if (widget.compact && widget.name != null) Flexible(child: widget.name!),
                if (widget.compact && cfg?['model'] != null) ...[
                  Text('${widget.name != null ? ' · ' : ''}${modelLabel('${cfg!['model']}')}', style: TextStyle(fontSize: 12.5, color: pal.sub)),
                  const SizedBox(width: 6),
                ],
                if (widget.compact && cfg?['effort'] != null)
                  Tooltip(message: effortLabel(cfg!['effort'] as String), child: EffortBars(effort: cfg['effort'] as String, color: pal.sub)),
                // Mở: mũi tên xuống (đang hiện đủ); thu gọn: mũi tên ngang.
                if (steps.isNotEmpty) Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18, color: pal.sub),
              ],
            ),
          ),
        ),
        if ((cfg?['note'] as String? ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              cfg!['note'] as String,
              style: TextStyle(fontSize: 12.5, color: pal.sub, fontStyle: FontStyle.italic),
            ),
          ),
        // Phiên tách (fork) từ phiên khác: ghi rõ kế thừa ngữ cảnh từ đâu.
        if (r['forked_from'] is Map && ((r['forked_from'] as Map)['name'] as String? ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.call_split, size: 14, color: pal.sub),
              const SizedBox(width: 4),
              Flexible(
                child: Text(tr('Tách từ {0}', [(r['forked_from'] as Map)['name']]),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ),
            ]),
          ),
        if (error != null && error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error, style: const TextStyle(fontSize: 13, color: Colors.redAccent)),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topLeft,
          child: !_open
              ? const SizedBox(width: 0)
              : Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final s in steps) _StepRow(step: s)],
                  ),
                ),
        ),
        // Kế hoạch luôn ở cuối, dưới các bước (Sếp: "Kế hoạch nếu có thì luôn hiện ở cuối của tin nhắn").
        if (todos.isNotEmpty && widget.showTodos) AgentTodoList(todos: todos, active: active),
      ],
    );
  }
}

/// Kế hoạch việc của lượt chạy (props.flygo_agent.todos), rỗng nếu không có.
List<Map<String, dynamic>> agentTodosOf(Map<String, dynamic> run) =>
    [for (final t in (run['todos'] as List? ?? const [])) if (t is Map) t.cast<String, dynamic>()];

/// Danh sách việc agent tự lập trong lượt (props.flygo_agent.todos, runner 0.6.79+), luôn ở cuối tin.
/// Mặc định gọn một dòng: "đã xong/tổng · việc đang làm" + nút mở ở cuối, thanh tiến độ bên dưới; bấm để xem đủ
/// danh sách (Sếp 25/11).
class AgentTodoList extends StatefulWidget {
  final List<Map<String, dynamic>> todos;
  final bool active;
  const AgentTodoList({super.key, required this.todos, required this.active});
  @override
  State<AgentTodoList> createState() => _AgentTodoListState();
}

const _kGreen = Color(0xFF2E9D5B);

class _AgentTodoListState extends State<AgentTodoList> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final todos = widget.todos;
    final done = todos.where((t) => t['status'] == 'completed').length;
    final allDone = done == todos.length;
    // Việc đang làm; chưa có thì việc chưa làm đầu tiên; xong hết thì việc cuối.
    final current = todos.where((t) => t['status'] == 'in_progress').firstOrNull ??
        todos.where((t) => t['status'] != 'completed').firstOrNull ??
        todos.last;
    final doing = current['status'] == 'in_progress';
    final tint = allDone ? _kGreen : pal.accentText;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: pal.text.withValues(alpha: .035),
        border: Border.all(color: pal.text.withValues(alpha: .09)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('todo-head'),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
              child: Row(children: [
                Icon(allDone ? Icons.check_circle_rounded : Icons.checklist_rounded, size: 17, color: tint),
                const SizedBox(width: 7),
                Text('$done/${todos.length}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tint, fontFeatures: const [FontFeature.tabularFigures()])),
                Text('  ·  ', style: TextStyle(fontSize: 13, color: pal.sub)),
                Expanded(
                  child: Text(
                    allDone ? tr('Đã xong kế hoạch') : '${current['text'] ?? ''}',
                    key: const ValueKey('todo-current'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: doing ? FontWeight.w600 : FontWeight.w500, color: allDone ? pal.sub : pal.text),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _open ? .5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded, size: 20, color: pal.sub),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
            child: AgentProgressBar(value: todos.isEmpty ? 0 : done / todos.length, color: tint),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final t in todos) _TodoRow(todo: t, active: widget.active)],
              ),
            ),
        ],
      ),
    );
  }
}

/// Thanh tiến độ mảnh bo tròn (kế hoạch việc, tác vụ nền); đổi giá trị thì trượt nhẹ, không chạy hoạt ảnh liên tục.
class AgentProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  const AgentProgressBar({super.key, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 4,
          backgroundColor: pal.text.withValues(alpha: .08),
          color: color,
        ),
      ),
    );
  }
}

/// Tóm tắt cuối lượt của trợ lý (props.flygo_agent.wrap_up, runner 0.6.80+): vài câu đã làm gì / còn gì.
/// Cần người dùng quyết định thì có câu hỏi + nút; bấm nút = gửi đúng chữ đó cho trợ lý ở cùng chỗ
/// (kênh nhiều người thì gắn @trợ lý để runner chắc chắn nhận).
class AgentWrapUp extends StatefulWidget {
  final MmPost post;
  final Map<String, dynamic> wrap;
  const AgentWrapUp({super.key, required this.post, required this.wrap});
  @override
  State<AgentWrapUp> createState() => _AgentWrapUpState();
}

class _AgentWrapUpState extends State<AgentWrapUp> {
  static final _picked = <String, String>{}; // id tin -> nút đã bấm (giữ khi tin được dựng lại)

  Future<void> _pick(AppState app, String label) async {
    setState(() => _picked[widget.post.id] = label);
    final bot = app.users[widget.post.userId];
    final ch = app.channels[widget.post.channelId];
    final tag = ch != null && !ch.isAi && !ch.isDirect && bot != null ? '@${bot.username} ' : '';
    try {
      await app.send(widget.post.channelId, '$tag$label', rootId: widget.post.rootId);
    } catch (_) {
      if (mounted) setState(() => _picked.remove(widget.post.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.read<AppState>();
    final recap = (widget.wrap['recap'] as String? ?? '').trim();
    final ask = (widget.wrap['ask'] as String? ?? '').trim();
    final actions = [for (final a in (widget.wrap['actions'] as List? ?? const [])) '$a'.trim()].where((a) => a.isNotEmpty).toList();
    final blocked = widget.wrap['blocked'] == true;
    final picked = _picked[widget.post.id];
    if (recap.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: (blocked ? const Color(0xFFF5A623) : pal.text).withValues(alpha: blocked ? .10 : .04),
        border: Border.all(color: (blocked ? const Color(0xFFF5A623) : pal.text).withValues(alpha: .18)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(blocked ? Icons.hourglass_top_rounded : Icons.flag_outlined, size: 16, color: blocked ? const Color(0xFFF5A623) : pal.sub),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(recap, style: TextStyle(fontSize: 13.5, height: 1.35, color: pal.text))),
        ]),
        if (ask.isNotEmpty && actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(ask, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final a in actions)
              picked == a
                  ? FilledButton.icon(onPressed: null, icon: const Icon(Icons.check, size: 16), label: Text(a))
                  : OutlinedButton(onPressed: picked == null ? () => _pick(app, a) : null, child: Text(a)),
          ]),
        ],
      ]),
    );
  }
}

class _TodoRow extends StatelessWidget {
  final Map<String, dynamic> todo;
  final bool active;
  const _TodoRow({required this.todo, required this.active});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final status = todo['status'] as String? ?? 'pending';
    final completed = status == 'completed', doing = status == 'in_progress';
    final Widget icon = completed
        ? const Icon(Icons.check_circle_rounded, size: 17, color: Color(0xFF2E9D5B))
        : doing
            ? (active
                ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 1.8, color: pal.accentText))
                : Icon(Icons.timelapse_rounded, size: 17, color: pal.accentText))
            : Icon(Icons.radio_button_unchecked, size: 17, color: pal.sub.withValues(alpha: .7));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 18, height: 18, child: Center(child: icon)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            todo['text'] as String? ?? '',
            style: TextStyle(
              fontSize: 14,
              height: 1.3,
              color: completed ? pal.sub : pal.text,
              fontWeight: doing ? FontWeight.w600 : FontWeight.w400,
              decoration: completed ? TextDecoration.lineThrough : null,
              decorationColor: pal.sub,
            ),
          ),
        ),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  final Map<String, dynamic> step;
  const _StepRow({required this.step});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final status = step['status'] as String? ?? 'done';
    final detail = (step['detail'] as String? ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: status == 'running'
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: pal.accentText))
                : Icon(
                    status == 'error'
                        ? Icons.error_outline
                        : status == 'waiting'
                        ? Icons.hourglass_top_rounded
                        : _kindIcon(step['kind'] as String? ?? ''),
                    size: 15,
                    color: status == 'error' ? Colors.redAccent : pal.sub,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AgentTitle(step['title'] as String? ?? '', style: TextStyle(fontSize: 13.5, color: pal.text)),
                if (detail.isNotEmpty)
                  if (tryParseJson(detail) case final json?)
                    JsonView(value: json)
                  else
                    ShellOutput(detail, error: status == 'error', maxLines: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dải "Nghiên cứu sâu" trên thẻ của lượt (runner ghi flygo_agent.mode = "research"): đang chạy / xong, số lượt tìm,
/// số trang đã mở, thời gian, và các tên miền nguồn (từ bước tìm web "Tìm web: …" / "Mở url").
class ResearchSummary extends StatelessWidget {
  final Map<String, dynamic> run;
  const ResearchSummary({super.key, required this.run});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    const accent = Color(0xFFD97757);
    final steps = [for (final s in (run['steps'] as List? ?? const [])) (s as Map).cast<String, dynamic>()];
    final search = steps.where((s) => s['kind'] == 'search').toList();
    final queries = search.where((s) => '${s['title']}'.startsWith('Tìm web')).length;
    final domains = <String, int>{};
    for (final s in search) {
      final m = RegExp(r'https?://([^/\s]+)').firstMatch('${s['title']}');
      if (m != null) domains.update(m.group(1)!.replaceFirst(RegExp(r'^www\.'), ''), (v) => v + 1, ifAbsent: () => 1);
    }
    final top = domains.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final active = agentRunActive(run);
    final start = (run['started_at'] as num?)?.toInt() ?? 0;
    final end = (run['ended_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final mins = start > 0 ? ((end - start) / 60000).round() : 0;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.travel_explore_rounded, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(active ? tr('Nghiên cứu sâu · đang tìm nguồn…') : tr('Nghiên cứu sâu · xong'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: pal.text)),
          ),
          Text(tr('{0} lượt tìm · {1} nguồn · {2} phút', [queries, domains.length, mins]), style: TextStyle(fontSize: 12, color: pal.sub)),
        ]),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in top.take(8))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.public, size: 13, color: pal.sub),
                  const SizedBox(width: 4),
                  Text('${e.key} · ${e.value}', style: TextStyle(fontSize: 12, color: pal.sub)),
                ]),
              ),
            if (top.length > 8)
              Text(tr('+{0} trang khác', [top.length - 8]), style: TextStyle(fontSize: 12, color: pal.sub)),
          ]),
        ],
      ]),
    );
  }
}

/// Tiêu đề bước / yêu cầu duyệt. Runner ghi lệnh shell dạng "\$ lệnh" (có thể sau "Chờ duyệt: "):
/// bỏ "\$ " và hiện lệnh như một khối bash (chữ đơn cách, tên lệnh tô màu).
class AgentTitle extends StatelessWidget {
  final String title;
  final TextStyle style;
  const AgentTitle(this.title, {super.key, required this.style});

  static final _cmd = RegExp(r'^(.*?:\s*)?\$ (.+)$', dotAll: true);

  @override
  Widget build(BuildContext context) {
    final m = _cmd.firstMatch(title);
    if (m == null) return Text(title, style: style);
    final label = (m.group(1) ?? '').trim();
    final cmd = m.group(2)!.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(label, style: style)),
      ShellBlock(cmd, maxLines: 6),
    ]);
  }
}

/// Yêu cầu duyệt của bot: đang chờ thì hiện 2 nút, xong thì hiện kết quả.
class AgentApprovalBar extends StatelessWidget {
  final MmPost post;
  final Map<String, dynamic> approval;
  const AgentApprovalBar({super.key, required this.post, required this.approval});


  /// Thẻ duyệt passkey: còn chờ và chưa hết hạn → nút "🔐 Xác thực passkey" mở trang xác thực; còn lại hiện trạng thái.
  Widget _passkey(BuildContext context, Pal pal) {
    final status = approval['status'] as String? ?? 'pending';
    final exp = DateTime.tryParse(approval['expires_at'] as String? ?? '');
    final expired = status == 'expired' || (status == 'pending' && exp != null && exp.isBefore(DateTime.now()));
    final url = approval['url'] as String?;
    if (status == 'pending' && !expired && url != null) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6C4CE0),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.fingerprint_rounded, size: 20),
        label: Text(tr('Xác thực passkey')),
      );
    }
    final (icon, text, color) = switch (expired ? 'expired' : status) {
      'approved' || 'used' => (Icons.verified_rounded, tr('Đã xác thực passkey'), const Color(0xFF2E9D5B)),
      'denied' => (Icons.cancel_rounded, tr('Đã từ chối'), Colors.redAccent),
      'expired' => (Icons.timer_off_outlined, tr('Hết hạn xác thực'), pal.sub),
      _ => (Icons.info_outline, status, pal.sub),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  /// Kết quả duyệt: Đã phê duyệt / Đã phê duyệt toàn quyền / Đã từ chối.
  Widget _decision(String status, Pal pal) {
    final (icon, text, color) = switch (status) {
      'accepted' => (Icons.check_circle_rounded, tr('Đã phê duyệt'), const Color(0xFF2E9D5B)),
      'always' => (Icons.lock_open_rounded, tr('Đã phê duyệt toàn quyền'), Colors.redAccent),
      'declined' => (Icons.cancel_rounded, tr('Đã từ chối'), Colors.redAccent),
      'expired' => (Icons.timer_off_outlined, tr('Hết hạn duyệt'), pal.sub),
      _ => (Icons.info_outline, status, pal.sub),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bar = _bar(context);
    // Máy tính: hộp xin quyền căn giữa, rộng tối đa 560; điện thoại giữ nguyên chiều rộng tin.
    if (!isDesktop) return bar;
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: bar));
  }

  Widget _bar(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    final status = approval['status'] as String? ?? 'pending';
    final detail = (approval['detail'] as String? ?? '').trim();
    final detailJson = approval['kind'] == 'report' ? null : tryParseJson(detail);
    final mine = post.reactions.entries.where((e) => e.value.contains(app.me?.id)).map((e) => e.key).firstOrNull;
    final owner = post.props['flygo_agent_owner'] as String?;
    // Người được duyệt: chủ trợ lý, hoặc người giao việc cho lượt chạy này (runner ghi flygo_agent_requester).
    final requester = post.props['flygo_agent_requester'] as String?;
    final canApprove =
        app.isMyBot(post.userId) || (owner != null && owner == app.me?.id) || (requester != null && requester == app.me?.id);
    final ownerName = owner == null ? tr('chủ trợ lý') : (app.users[owner]?.displayName ?? tr('chủ trợ lý'));
    final kind = approval['kind'] as String? ?? 'approval';
    final plan = kind == 'plan';
    final name = engineName(engineOf(app.users[post.userId]) ?? 'claude');
    // Kiểu Claude app: "Cho phép Claude chạy?" + lệnh / tệp trong khung code; kế hoạch: "Thực hiện kế hoạch này".
    final rawTitle = (approval['title'] as String? ?? '').trim();
    final command = kind == 'command' && rawTitle.startsWith(r'$ ') ? rawTitle.substring(2) : null;
    Widget header = Row(
      children: [
        Icon(_kindIcon(kind), size: 17, color: const Color(0xFFF5A623)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            plan
                ? tr('Thực hiện kế hoạch này?')
                : (kind == 'command' || kind == 'file')
                    ? tr('Cho phép {0} chạy?', [name])
                    : (rawTitle.isEmpty ? tr('Yêu cầu duyệt') : rawTitle),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text),
          ),
        ),
      ],
    );
    // Lệnh / tên tệp hiện trong khung code ngay dưới tiêu đề.
    final codeLine = command ?? (kind == 'file' && rawTitle.isNotEmpty ? rawTitle : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        if (codeLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: command != null
                ? ShellBlock(command, maxLines: null, selectable: true, fontSize: 13)
                : ShellBlock(codeLine, lang: tr('tệp'), maxLines: null, selectable: true, fontSize: 13),
          ),
        if (plan && detail.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: pal.text.withValues(alpha: .05), borderRadius: BorderRadius.circular(10)),
            child: MarkdownView(text: detail, style: TextStyle(fontSize: 14.5, color: pal.text, height: 1.4)),
          )
        else if (detail.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(8)),
            // Báo cáo ra ngoài: hiện như văn bản thường (nhiều dòng), còn lệnh / tệp thì chữ đơn cách.
            child: approval['kind'] == 'report'
                ? SelectableText(detail, style: TextStyle(fontSize: 14, color: pal.text, height: 1.4))
                : detailJson != null
                ? JsonView(value: detailJson, fontSize: 12.5, background: Colors.transparent)
                : Text(
                    detail,
                    style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontFeatures: kNoLigatures, fontSize: 12.5, color: pal.text, height: 1.3),
                  ),
          ),
        const SizedBox(height: 8),
        // Duyệt bằng passkey (thao tác nhạy cảm qua ContextForge): nút mở trang xác thực; thả cảm xúc không duyệt được.
        if (approval['kind'] == 'passkey')
          _passkey(context, pal)
        // Chỉ chủ trợ lý duyệt được (runner bỏ qua người khác): người khác thấy dòng chờ thay vì nút bấm không tác dụng.
        else if (status == 'pending' && !canApprove)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.hourglass_top_rounded, size: 16, color: pal.sub),
            const SizedBox(width: 6),
            Flexible(
              child: Text(tr('Chờ {0} duyệt', [ownerName]),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.sub)),
            ),
          ])
        // Đã bấm: các lựa chọn biến mất ngay, hiện kết quả luôn (không chờ trợ lý cập nhật tin).
        else if (status == 'pending' && (mine == '+1' || mine == '-1' || mine == 'unlock'))
          _decision(mine == '-1' ? 'declined' : (mine == 'unlock' ? 'always' : 'accepted'), pal)
        // Kiểu Claude app: 3 nút xếp dọc — Cho phép một lần (👍), Luôn cho phép trong phiên này (🔓), Từ chối (👎).
        // Kế hoạch: Duyệt / Từ chối.
        else if (status == 'pending')
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: pal.text,
                foregroundColor: pal.bg,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => app.toggleReaction(post, '+1'),
              child: Text(plan ? tr('Duyệt kế hoạch') : tr('Cho phép một lần'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (!plan && app.isMyBot(post.userId)) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: pal.text,
                  side: BorderSide(color: pal.divider),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => app.toggleReaction(post, 'unlock'),
                child: Text(tr('Luôn cho phép trong phiên này')),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: pal.text,
                side: BorderSide(color: pal.divider),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => app.toggleReaction(post, '-1'),
              child: Text(tr('Từ chối')),
            ),
          ])
        else
          _decision(status, pal),
      ],
    );
  }
}


// ---------------------------------------------------------------- dung lượng ngữ cảnh
/// Ngữ cảnh của phiên trợ lý trong chat [channelId]: số token đang dùng / tối đa, lấy từ lượt chạy gần nhất
/// (flygo_agent.usage; runner mới ghi thêm contextTokens + contextWindow). null nếu chưa có lượt nào.
({int used, int max, String model})? agentContextOf(AppState app, String channelId) {
  for (final p in app.postsOf(channelId)) {
    final r = agentRunOf(p);
    final all = (r?['usage'] as Map?)?.cast<String, dynamic>();
    if (all == null) continue;
    // Claude (snake_case, nhiều lượt gọi trong một lượt chạy): ngữ cảnh hiện tại = lượt gọi cuối cùng.
    final its = all['iterations'];
    final u = its is List && its.isNotEmpty && its.last is Map ? (its.last as Map).cast<String, dynamic>() : all;
    int n(String k) {
      final snake = k.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
      final alt = {
        'cachedInputTokens': 'cache_read_input_tokens',
        'cacheWriteInputTokens': 'cache_creation_input_tokens',
      }[k];
      return ((u[k] ?? all[k] ?? u[snake] ?? (alt == null ? null : u[alt])) as num?)?.toInt() ?? 0;
    }
    final engine = r?['engine'] as String? ?? '';
    final model = ((r?['config'] as Map?)?['model'] as String?) ?? '';
    // Codex: inputTokens đã gồm phần đọc từ cache; Claude: tách riêng cache đọc / ghi. agy: runner ghi sẵn contextTokens.
    final used = n('contextTokens') > 0
        ? n('contextTokens')
        : (engine == 'codex' ? n('inputTokens') : n('inputTokens') + n('cachedInputTokens') + n('cacheWriteInputTokens')) +
            n('outputTokens');
    final max = n('contextWindow') > 0
        ? n('contextWindow')
        : (engine == 'codex'
            ? 400000
            : engine == 'agy'
                ? 1000000
                : 200000);
    if (used <= 0) continue;
    return (used: used, max: max, model: model);
  }
  return null;
}

String _kTokens(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M' : '${(n / 1000).round()}k';

// ---------------------------------------------------------------- hạn mức sử dụng của engine
/// Một cửa sổ hạn mức của tài khoản engine (Codex 5 giờ / tuần, gói Claude phiên 5 giờ / tuần, quota agy).
class AgentLimitWindow {
  final String id;
  final String? label;
  final int usedPercent;
  final int? windowMins;
  final DateTime? resetsAt;
  final String? status;
  const AgentLimitWindow({required this.id, this.label, required this.usedPercent, this.windowMins, this.resetsAt, this.status});

  /// Đã qua thời điểm đặt lại: coi như chưa dùng (runner chưa kịp báo số mới).
  int usedAt(DateTime now) => resetsAt != null && !resetsAt!.isAfter(now) ? 0 : usedPercent;
}

/// Hạn mức của tài khoản engine mà bot đang dùng (runner 0.6.75+: flygo_agent.usage.limits và props.flygo_models.limits).
class AgentLimits {
  final String engine;
  final DateTime at;
  final String? plan;
  final bool reached;
  final List<AgentLimitWindow> windows;
  const AgentLimits({required this.engine, required this.at, this.plan, this.reached = false, required this.windows});

  static AgentLimits? parse(Object? raw) {
    if (raw is! Map) return null;
    final ws = <AgentLimitWindow>[];
    for (final w in (raw['windows'] as List? ?? const [])) {
      if (w is! Map || w['usedPercent'] is! num) continue;
      final r = (w['resetsAt'] as num?)?.toInt();
      ws.add(AgentLimitWindow(
        id: '${w['id'] ?? ''}',
        label: w['label'] as String?,
        usedPercent: (w['usedPercent'] as num).round(),
        windowMins: (w['windowMins'] as num?)?.toInt(),
        resetsAt: r == null || r <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(r * 1000),
        status: w['status'] as String?,
      ));
    }
    if (ws.isEmpty) return null;
    return AgentLimits(
      engine: '${raw['engine'] ?? ''}',
      at: DateTime.fromMillisecondsSinceEpoch((raw['at'] as num?)?.toInt() ?? 0),
      plan: raw['plan'] as String?,
      reached: raw['reached'] == true,
      windows: ws,
    );
  }

  /// Phần trăm của cửa sổ dùng nhiều nhất (vòng ngoài).
  int maxUsed(DateTime now) => windows.fold(0, (m, w) => w.usedAt(now) > m ? w.usedAt(now) : m);
}

/// Hạn mức của bot trả lời trong chat [channelId]: bản mới hơn giữa thẻ tiến trình gần nhất và props của tài khoản bot.
AgentLimits? agentLimitsOf(AppState app, String channelId) {
  AgentLimits? card;
  String? botId;
  for (final p in app.postsOf(channelId)) {
    final r = agentRunOf(p);
    if (r == null) continue;
    botId ??= p.userId;
    if (p.userId != botId) continue;
    card = AgentLimits.parse((r['usage'] as Map?)?['limits']);
    if (card != null) break;
  }
  final ch = app.channels[channelId];
  if (botId == null && ch != null && ch.isDirect) {
    for (final id in ch.name.split('__')) {
      if (app.users[id]?.isBot == true) botId = id;
    }
  }
  AgentLimits? meta;
  final raw = botId == null ? null : (app.users[botId]?.raw['props'] as Map?)?['flygo_models'];
  try {
    final m = raw is String ? jsonDecode(raw) : raw;
    meta = AgentLimits.parse(m is Map ? m['limits'] : null);
  } catch (_) {}
  if (card == null) return meta;
  if (meta == null) return card;
  return meta.at.isAfter(card.at) ? meta : card;
}

String agentLimitLabel(AgentLimitWindow w) {
  final i = w.id.indexOf(':');
  final base = i >= 0 ? w.id.substring(i + 1) : w.id;
  String dur(int m) => m % 1440 == 0 ? tr('{0} ngày', [m ~/ 1440]) : (m % 60 == 0 ? tr('{0} giờ', [m ~/ 60]) : tr('{0} phút', [m]));
  final name = switch (base) {
    'five_hour' => tr('Phiên 5 giờ'),
    'seven_day' => tr('Hàng tuần'),
    'seven_day_opus' => tr('Hàng tuần (Opus)'),
    'seven_day_sonnet' => tr('Hàng tuần (Sonnet)'),
    'seven_day_overage_included' => tr('Hàng tuần (gồm vượt mức)'),
    'daily' => tr('Hàng ngày'),
    _ => w.windowMins != null ? tr('Cửa sổ {0}', [dur(w.windowMins!)]) : (w.label ?? tr('Hạn mức')),
  };
  return w.label != null && w.label!.isNotEmpty && name != w.label ? '${w.label} · $name' : name;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// `tên: đã dùng N% · đặt lại lúc HH:mm (dd/MM)`.
String agentLimitLine(AgentLimitWindow w, DateTime now) {
  final r = w.resetsAt?.toLocal();
  final used = w.usedAt(now);
  if (r == null) return tr('{0}: đã dùng {1}%', [agentLimitLabel(w), used]);
  return tr('{0}: đã dùng {1}% · đặt lại lúc {2}', [agentLimitLabel(w), used, '${_two(r.hour)}:${_two(r.minute)} (${_two(r.day)}/${_two(r.month)})']);
}

/// Màu theo mức dùng: bình thường → cam (>80%) → đỏ (>95%).
Color usageColor(double f, Color normal) => f > .95 ? const Color(0xFFE5484D) : (f > .8 ? const Color(0xFFF5A623) : normal);

String _engineName(String e) => switch (e) { 'codex' => 'Codex', 'claude' => 'Claude Code', 'agy' => 'Antigravity', _ => e };

/// Vòng kép đồng tâm: vòng trong = ngữ cảnh của phiên (% đã dùng), vòng ngoài = hạn mức tài khoản engine đã dùng
/// (cửa sổ 5 giờ / tuần đang dùng nhiều nhất). Giữ chuột xem nhanh, bấm để mở hộp chi tiết có thanh tiến độ.
/// [always]: luôn hiện cả hai vòng (vòng chưa có số liệu để trống) để chat trợ lý không bao giờ mất hai vòng này.
class AgentUsageRing extends StatelessWidget {
  final ({int used, int max, String model})? ctx;
  final AgentLimits? limits;
  final DateTime? now;
  final bool always;
  const AgentUsageRing({super.key, required this.ctx, this.limits, this.now, this.always = false});

  void _details(BuildContext context) {
    final c = ctx;
    final l = limits;
    final pal = Pal.of(context);
    final t = now ?? DateTime.now();
    final track = pal.text.withValues(alpha: .12);
    Widget bar(double v, Color color) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(value: v.clamp(0.0, 1.0), minHeight: 6, borderRadius: BorderRadius.circular(3), backgroundColor: track, color: color),
        );
    Widget head(String text) => Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text));
    final note = TextStyle(fontSize: 12.5, color: pal.sub);
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Dung lượng của trợ lý')),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              head(tr('Ngữ cảnh của phiên')),
              const SizedBox(height: 6),
              if (c != null) ...[
                Text(tr('Đã dùng {0} / {1} token ({2}%)', [_kTokens(c.used), _kTokens(c.max), (c.used * 100 / c.max).round()]), style: const TextStyle(fontSize: 13.5)),
                bar(c.used / c.max, usageColor(c.used / c.max, const Color(0xFF2E9D5B))),
                if (c.model.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Mô hình: {0}', [modelLabel(c.model)]), style: note)),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr('Gần đầy thì trợ lý tự tóm tắt bớt lịch sử; muốn bắt đầu lại sạch hãy tạo phiên mới.'), style: note),
                ),
              ] else
                Text(tr('Chưa có số liệu: trợ lý gửi sau lượt chạy đầu tiên của phiên.'), style: note),
              const SizedBox(height: 18),
              head(l == null
                  ? tr('Hạn mức sử dụng')
                  : (l.plan != null && l.plan!.isNotEmpty ? tr('Hạn mức {0} (gói {1})', [_engineName(l.engine), l.plan]) : tr('Hạn mức {0}', [_engineName(l.engine)]))),
              if (l == null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Chưa có số liệu hạn mức (phiên 5 giờ / hàng tuần) của tài khoản trợ lý.'), style: note))
              else ...[
                for (final w in l.windows) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text(agentLimitLabel(w), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                    Text(tr('đã dùng {0}%', [w.usedAt(t)]), style: TextStyle(fontSize: 13.5, color: usageColor(w.usedAt(t) / 100, pal.text))),
                  ]),
                  bar(w.usedAt(t) / 100, usageColor(w.usedAt(t) / 100, pal.accent)),
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(agentLimitLine(w, t), style: note)),
                ],
                if (l.reached)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(tr('Tài khoản đã chạm hạn mức, chờ đến lúc đặt lại.'), style: const TextStyle(fontSize: 13, color: Color(0xFFE5484D))),
                  ),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Đóng')))],
      ),
    );
  }

  /// Một vòng tiến độ; [size] = đường kính ngoài.
  Widget _ring(BuildContext context, {required Key key, required double size, required double value, required Color color}) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          key: key,
          value: value,
          strokeWidth: 3,
          backgroundColor: Pal.of(context).text.withValues(alpha: .12),
          color: color,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ctx;
    final l = limits;
    if (c == null && l == null && !always) return const SizedBox.shrink();
    final pal = Pal.of(context);
    final t = now ?? DateTime.now();
    final f = c == null ? 0.0 : (c.used / c.max).clamp(0.0, 1.0);
    final used = (l?.maxUsed(t) ?? 0).clamp(0, 100);
    final showCtx = c != null || always;
    final showLimit = l != null || always;
    // Vòng kép đồng tâm (Sếp, 2026-11-18): vòng ngoài = hạn mức tài khoản, vòng trong = ngữ cảnh của phiên;
    // số ở giữa là % ngữ cảnh (hạn mức xem trong chú thích / hộp chi tiết).
    final tip = [
      if (showCtx)
        c == null ? tr('Ngữ cảnh: chưa có số liệu') : tr('Ngữ cảnh: {0} / {1} token ({2}%)', [_kTokens(c.used), _kTokens(c.max), (f * 100).round()]),
      if (showLimit) l == null ? tr('Hạn mức: chưa có số liệu') : [for (final w in l.windows) agentLimitLine(w, t)].join('\n'),
    ].join('\n');
    final label = showCtx ? (c == null ? '-' : '${(f * 100).round()}') : (l == null ? '-' : '$used');
    return Tooltip(
      message: tip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _details(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Stack(alignment: Alignment.center, children: [
              if (showLimit)
                _ring(
                  context,
                  key: const ValueKey('usage-limit-ring'),
                  size: 32,
                  // % đã dùng của cửa sổ dùng nhiều nhất; đỏ khi sắp hết / đã chạm hạn mức.
                  value: l == null ? 0 : used / 100,
                  color: l != null && l.reached ? const Color(0xFFE5484D) : usageColor(used / 100, pal.accent),
                ),
              if (showCtx)
                _ring(
                  context,
                  key: const ValueKey('usage-context-ring'),
                  size: showLimit ? 22 : 32,
                  value: f,
                  color: usageColor(f, const Color(0xFF2E9D5B)),
                ),
              Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: pal.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Vòng kép ở góc trên bên phải chat trợ lý: % ngữ cảnh (trong) và % hạn mức đã dùng (ngoài); bấm xem chi tiết.
class AgentContextRing extends StatelessWidget {
  final String channelId;
  const AgentContextRing({super.key, required this.channelId});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return AgentUsageRing(ctx: agentContextOf(app, channelId), limits: agentLimitsOf(app, channelId), always: true);
  }
}


// ---------------------------------------------------------------- câu hỏi trắc nghiệm của trợ lý
/// Thẻ câu hỏi trắc nghiệm: các lựa chọn (một hoặc nhiều), "Khác…" để tự nhập. Trả lời = gửi một tin vào đúng chỗ
/// (cùng luồng nếu có) kèm props.flygo_agent_answer {post_id, question_id, choices, other}; runner nhận tin đó là câu trả lời.
class AgentQuestionCard extends StatefulWidget {
  final MmPost post;
  final Map<String, dynamic> question;
  const AgentQuestionCard({super.key, required this.post, required this.question});

  /// Khoá cố định theo tin: tin của trợ lý được sửa liên tục làm bố cục bong bóng đổi, GlobalKey giữ nguyên thẻ
  /// (lựa chọn và ô "Khác…" đang gõ không mất focus, không nhảy xuống ô nhắn tin).
  static final _keys = <String, GlobalKey>{};
  static GlobalKey keyFor(String postId) => _keys.putIfAbsent(postId, () => GlobalKey(debugLabel: 'q-$postId'));
  @override
  State<AgentQuestionCard> createState() => _AgentQuestionCardState();
}

class _AgentQuestionCardState extends State<AgentQuestionCard> {
  // Tin của trợ lý đang chạy được sửa liên tục (thẻ có thể bị dựng lại): giữ lựa chọn theo id tin để không mất.
  static final _pickedById = <String, Set<String>>{};
  static final _otherById = <String, bool>{};
  static final _otherTextById = <String, String>{};
  static final _sentById = <String, String>{}; // id tin → 'answered' | 'cancelled'

  String get _id => widget.post.id;
  Set<String> get _picked => _pickedById.putIfAbsent(_id, () => <String>{});
  bool get _other => _otherById[_id] ?? false;
  set _other(bool v) => _otherById[_id] = v;
  bool get _sent => _sentById.containsKey(_id);
  late final TextEditingController _otherCtl = TextEditingController(text: _otherTextById[_id] ?? '')
    ..addListener(() => _otherTextById[_id] = _otherCtl.text);

  @override
  void dispose() {
    _otherCtl.dispose();
    super.dispose();
  }

  /// Huỷ câu hỏi: câu hỏi AskUserQuestion (đang chờ duyệt công cụ) → từ chối công cụ; câu hỏi của runner → gửi trả lời "huỷ".
  Future<void> _cancel(AppState app) async {
    setState(() => _sentById[_id] = 'cancelled');
    try {
      // Huỷ: thả 👎 lên tin câu hỏi (cả câu hỏi của runner lẫn yêu cầu AskUserQuestion cũ), không tạo tin nhắn.
      await app.toggleReaction(widget.post, '-1');
    } catch (_) {
      if (mounted) setState(() => _sentById.remove(_id));
    }
  }

  static const _numbers = ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];

  Future<void> _submit(AppState app, List<String> choices, String other) async {
    if (choices.isEmpty && other.trim().isEmpty) return;
    setState(() => _sentById[_id] = 'answered');
    final q = widget.question;
    // Câu hỏi của runner (props.flygo_agent_question): trả lời bằng cảm xúc số trên chính tin câu hỏi, không tạo tin
    // nhắn (một lựa chọn: 1️⃣…; nhiều lựa chọn: các số rồi ✅). "Khác" thì gửi tin thường cùng chỗ, runner nhận làm câu trả lời.
    if (q['kind'] != 'ask_user_question') {
      final labels = [
        for (final o in (q['options'] as List? ?? const [])) o is Map ? (o['label'] as String? ?? '') : '$o',
      ];
      final idx = [for (final c in choices) labels.indexOf(c)].where((i) => i >= 0 && i < _numbers.length).toList();
      try {
        if (other.trim().isNotEmpty) {
          final text = [...choices, other.trim()].join(', ');
          await app.send(widget.post.channelId, text, rootId: widget.post.rootId);
        } else if (idx.length == choices.length && idx.isNotEmpty) {
          await app.addReactions(widget.post, [
            for (final i in idx) _numbers[i],
            if (q['multi'] == true) 'white_check_mark',
          ]);
        } else {
          // Quá 9 lựa chọn: gửi câu trả lời dạng props (runner vẫn hỗ trợ).
          await app.send(widget.post.channelId, choices.join(', '), rootId: widget.post.rootId, props: {
            'flygo_agent_answer': {'post_id': widget.post.id, 'question_id': q['id'], 'choices': choices},
          });
        }
      } catch (_) {
        if (mounted) setState(() => _sentById.remove(_id));
      }
      return;
    }
    final bot = app.users[widget.post.userId];
    final parts = [...choices, if (other.trim().isNotEmpty) other.trim()];
    // Kênh nhiều người: gắn @trợ lý để runner chắc chắn nhận (chat AI / 1-1 thì không cần).
    final ch = app.channels[widget.post.channelId];
    final tag = ch != null && !ch.isAi && !ch.isDirect && bot != null ? '@${bot.username} ' : '';
    try {
      await app.send(widget.post.channelId, '$tag${parts.join(', ')}',
          rootId: widget.post.rootId,
          props: {
            'flygo_agent_answer': {
              'post_id': widget.post.id,
              'question_id': q['id'],
              'choices': choices,
              if (other.trim().isNotEmpty) 'other': other.trim(),
              // Câu hỏi AskUserQuestion của Claude (đang chờ duyệt công cụ): runner trả lời yêu cầu đó bằng lựa chọn này.
              if (q['kind'] == 'ask_user_question') 'kind': 'ask_user_question',
              if (q['kind'] == 'ask_user_question') 'question': q['question'],
            },
          });
      // Runner cũ chỉ hiểu 👍 cho yêu cầu công cụ AskUserQuestion: duyệt luôn để lượt chạy không đứng chờ;
      // câu trả lời đã nằm trong tin vừa gửi (trợ lý đọc ở lượt kế tiếp).
      if (q['kind'] == 'ask_user_question' && !(widget.post.reactions['+1']?.contains(app.me?.id) ?? false)) {
        await app.toggleReaction(widget.post, '+1');
      }
    } catch (_) {
      if (mounted) setState(() => _sentById.remove(_id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    final q = widget.question;
    final options = [
      for (final o in (q['options'] as List? ?? const []))
        o is Map ? (o['label'] as String? ?? '', o['description'] as String? ?? '') : ('$o', ''),
    ];
    final multi = q['multi'] == true;
    final allowOther = q['allow_other'] != false;
    final answered = (q['status'] as String? ?? 'pending') != 'pending' || _sent;
    final answer = q['answer'];
    final expired = q['status'] == 'expired' && _sentById[_id] == null;
    final cancelled = answered && (_sentById[_id] == 'cancelled' || q['status'] == 'cancelled');
    // Kiểu "chọn đáp án" của Claude: lựa chọn đánh số xếp dọc; một lựa chọn = bấm là gửi, nhiều lựa chọn = tích rồi Gửi;
    // "Khác" là dòng cuối, gõ rồi gửi ngay trong dòng. Hết hạn: giữ nguyên giao diện, chỉ làm mờ (Sếp 25/11).
    final live = !answered && !expired;
    final canSendOther = _otherCtl.text.trim().isNotEmpty;
    void pick(String label) {
      if (!live) return;
      if (!multi) {
        setState(() => _picked
          ..clear()
          ..add(label));
        _submit(app, [label], '');
        return;
      }
      setState(() => _picked.contains(label) ? _picked.remove(label) : _picked.add(label));
    }

    Widget badge(int n, bool sel) => Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? pal.accent : pal.text.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(7),
          ),
          child: multi && sel
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : Text('$n',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : pal.sub,
                      fontFeatures: const [FontFeature.tabularFigures()])),
        );

    Widget row({required int n, required bool sel, required Widget child, VoidCallback? onTap, Key? key}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            key: key,
            color: sel ? pal.accent.withValues(alpha: .10) : pal.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: sel ? pal.accent.withValues(alpha: .8) : pal.divider, width: sel ? 1.3 : 1)),
            child: InkWell(
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              hoverColor: pal.accent.withValues(alpha: .06),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  badge(n, sel),
                  const SizedBox(width: 12),
                  Expanded(child: child),
                ]),
              ),
            ),
          ),
        );

    Widget optionRow(int i, (String, String) o) => row(
          key: ValueKey('q-opt-$i'),
          n: i + 1,
          sel: _picked.contains(o.$1),
          onTap: live ? () => pick(o.$1) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(o.$1, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: pal.text, height: 1.3)),
            if (o.$2.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(o.$2, style: TextStyle(fontSize: 13, color: pal.sub, height: 1.35)),
              ),
          ]),
        );

    // Dòng "Khác": bấm để gõ; Enter (hoặc nút gửi) gửi kèm các lựa chọn đã tích (nhiều lựa chọn).
    Widget otherRow() => row(
          key: const ValueKey('q-other'),
          n: options.length + 1,
          sel: _other,
          onTap: live && !_other
              ? () => setState(() {
                    _other = true;
                    if (!multi) _picked.clear();
                  })
              : null,
          child: _other && live
              ? Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _otherCtl,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 4,
                      style: TextStyle(fontSize: 14.5, color: pal.text),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: tr('Nhập câu trả lời khác…'),
                        hintStyle: TextStyle(color: pal.sub),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => canSendOther ? _submit(app, multi ? _picked.toList() : const [], _otherCtl.text) : null,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('q-other-send'),
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('Gửi'),
                    onPressed: canSendOther ? () => _submit(app, multi ? _picked.toList() : const [], _otherCtl.text) : null,
                    icon: Icon(Icons.arrow_upward_rounded, size: 20, color: canSendOther ? pal.accentText : pal.sub),
                  ),
                ])
              : Text(tr('Khác…'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: pal.sub, height: 1.3)),
        );

    final header = '${q['header'] ?? ''}'.trim();
    final card = Container(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
          color: pal.text.withValues(alpha: .03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (header.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: pal.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
              child: Text(header, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: pal.accentText)),
            ),
          ),
        Text(q['question'] as String? ?? '', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: pal.text, height: 1.35)),
        if (live && multi)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(tr('Chọn một hoặc nhiều, rồi bấm Gửi'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ),
        const SizedBox(height: 10),
        if (cancelled)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(Icons.cancel_rounded, size: 18, color: pal.sub),
              const SizedBox(width: 6),
              Text(tr('Đã huỷ'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.sub)),
            ]),
          )
        else if (answered)
          // Đã trả lời: giữ đủ các lựa chọn đã đưa ra, lựa chọn của mình có ✓ và in đậm, kèm ý khác.
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AgentAnswerOptions(
                q: {...q, if (q['choices'] == null && _picked.isNotEmpty) 'choices': _picked.toList()}, answer: answer is String ? answer : null),
          )
        else ...[
          for (final (i, o) in options.indexed) optionRow(i, o),
          if (allowOther) otherRow(),
          Row(children: [
            TextButton(
              key: const ValueKey('q-skip'),
              style: TextButton.styleFrom(foregroundColor: pal.sub, minimumSize: const Size(56, 40)),
              onPressed: live ? () => _cancel(app) : null,
              child: Text(tr('Bỏ qua')),
            ),
            const Spacer(),
            if (multi)
              FilledButton(
                key: const ValueKey('q-submit'),
                style: FilledButton.styleFrom(shape: const StadiumBorder(), visualDensity: VisualDensity.compact),
                onPressed: live && (_picked.isNotEmpty || (_other && canSendOther))
                    ? () => _submit(app, _picked.toList(), _other ? _otherCtl.text : '')
                    : null,
                child: Text(tr('Gửi')),
              ),
          ]),
        ],
      ]),
    );
    // Hết hạn: cùng giao diện, mờ đi và không bấm được.
    return expired ? IgnorePointer(child: Opacity(key: const ValueKey('q-expired'), opacity: .45, child: card)) : card;
  }
}

/// Các lựa chọn của một câu hỏi đã trả lời: lựa chọn được chọn có ✓ và in đậm, còn lại mờ; ý khác (gõ tay) ở cuối.
/// [answer]: chuỗi trả lời cũ ("A, B, ý khác") khi runner chưa lưu choices / other.
class AgentAnswerOptions extends StatelessWidget {
  final Map<String, dynamic> q;
  final String? answer;
  const AgentAnswerOptions({super.key, required this.q, this.answer});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    const green = Color(0xFF2E9D5B);
    final options = [
      for (final o in (q['options'] as List? ?? const []))
        o is Map ? ('${o['label'] ?? ''}', '${o['description'] ?? ''}') : ('$o', ''),
    ];
    final ans = answer ?? (q['answer'] is String ? q['answer'] as String : '');
    final choices = <String>{
      for (final c in (q['choices'] as List? ?? const [])) '$c',
      // Runner cũ chỉ lưu chuỗi trả lời: lựa chọn nào có trong chuỗi thì coi là đã chọn.
      if (q['choices'] == null)
        for (final o in options)
          if (o.$1.isNotEmpty && (ans == o.$1 || ans.split(RegExp(r'\s*[,·]\s*')).contains(o.$1))) o.$1,
    };
    var other = '${q['other'] ?? ''}'.trim();
    if (other.isEmpty && choices.isEmpty && ans.isNotEmpty) other = ans;
    final status = q['status'] as String? ?? 'answered';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (final o in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(choices.contains(o.$1) ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  size: 18, color: choices.contains(o.$1) ? green : pal.sub.withValues(alpha: .6)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.$1,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: choices.contains(o.$1) ? FontWeight.w700 : FontWeight.w400,
                        color: choices.contains(o.$1) ? pal.text : pal.sub)),
                if (o.$2.isNotEmpty) Text(o.$2, style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
            ),
          ]),
        ),
      if (other.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.edit_note_rounded, size: 18, color: green)),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: tr('Ý khác: '), style: TextStyle(color: pal.sub)),
                TextSpan(text: other, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              ]), style: const TextStyle(fontSize: 14.5)),
            ),
          ]),
        ),
      if (status == 'cancelled' || status == 'expired')
        Text(status == 'cancelled' ? tr('Đã huỷ') : tr('Câu hỏi đã hết hạn'),
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.sub)),
    ]);
  }
}

/// Câu hỏi đã trả lời, nằm đúng chỗ đã hỏi trong dòng thời gian của lượt chạy (không ghim xuống cuối thẻ).
class AgentAnsweredQuestion extends StatelessWidget {
  final Map<String, dynamic> q;
  const AgentAnsweredQuestion({super.key, required this.q});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: pal.accent.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.accent.withValues(alpha: .2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.help_outline_rounded, size: 17, color: pal.accentText)),
          const SizedBox(width: 6),
          Expanded(child: Text('${q['question'] ?? ''}', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text))),
        ]),
        const SizedBox(height: 8),
        AgentAnswerOptions(q: q),
      ]),
    );
  }
}

/// Câu hỏi (đã có trả lời / huỷ / hết hạn) của một bước hỏi trong lượt chạy. Runner 0.7.17+: step.questions; runner cũ:
/// tìm tin câu hỏi (props.flygo_agent_question) cùng chat có nội dung khớp tiêu đề bước ("Chờ trả lời: …" / "Đã trả lời: …").
/// Mỗi câu kèm '_post' = id tin câu hỏi (để ẩn tin đó khỏi danh sách tin).
List<Map<String, dynamic>> stepAnsweredQuestions(Map<String, dynamic> step, List<MmPost> posts) {
  final out = <Map<String, dynamic>>[];
  final qs = step['questions'];
  if (qs is List && qs.isNotEmpty) {
    for (final x in qs) {
      if (x is! Map) continue;
      final q = x.cast<String, dynamic>();
      if ((q['status'] as String? ?? 'pending') == 'pending') continue;
      // Bước chỉ có phần đầu (đang hỏi): lấy nốt trả lời từ tin câu hỏi.
      final post = posts.where((p) => p.id == q['post_id']).firstOrNull;
      out.add({...?agentQuestionOf(post ?? MmPost(const {})), ...q, '_post': q['post_id'] ?? ''});
    }
    return out;
  }
  if (step['kind'] != 'approval') return out;
  final title = '${step['title'] ?? ''}';
  final detail = '${step['detail'] ?? ''}';
  String after(String s, String head) => s.startsWith(head) ? s.substring(head.length).trim() : '';
  final asked = after(title, 'Chờ trả lời:');
  final answered = after(title, 'Đã trả lời:').isNotEmpty ? after(title, 'Đã trả lời:') : after(detail, 'Đã trả lời:');
  if (asked.isEmpty && answered.isEmpty) return out;
  final firstAsk = asked.split(' · ').first.replaceAll(RegExp(r'…$'), '');
  for (final p in posts) {
    final q = agentQuestionOf(p);
    if (q == null || (q['status'] as String? ?? 'pending') == 'pending') continue;
    final text = '${q['question'] ?? ''}';
    final ans = '${q['answer'] ?? ''}';
    final hit = firstAsk.length >= 8 ? text.startsWith(firstAsk) : (answered.length >= 3 && ans.startsWith(answered.split(' · ').first));
    if (hit) out.add({...q, '_post': p.id});
  }
  return out;
}

/// Tin câu hỏi [p] đã trả lời và đã hiện ngay trong dòng thời gian của lượt chạy hỏi nó: không hiện riêng nữa.
bool questionShownInline(MmPost p, List<MmPost> posts) {
  final q = agentQuestionOf(p);
  if (q == null || (q['status'] as String? ?? 'pending') == 'pending') return false;
  for (final r in posts) {
    final run = agentRunOf(r);
    if (run == null || agentMessageOf(r) == null || !hasAgentTimeline(run)) continue;
    for (final s in (run['steps'] as List? ?? const [])) {
      if (s is Map && stepAnsweredQuestions(s.cast<String, dynamic>(), posts).any((x) => x['_post'] == p.id)) return true;
    }
  }
  return false;
}

/// Lượt chạy có dòng thời gian (runner 0.6.19+: props.flygo_agent.texts + step.seg).
bool hasAgentTimeline(Map<String, dynamic> run) =>
    run['texts'] is List && (run['steps'] as List? ?? const []).every((s) => s is Map && s['seg'] is num);

/// Đoạn chữ cuối của lượt đã có bước chạy sau nó (seg của bước = số đoạn chữ đã bắt đầu trước bước): dòng thời gian
/// hiện cả đoạn cuối, xen đúng chỗ, nên tin không hiện lại nội dung ở dưới (nếu không bước mới nằm trên chữ viết trước).
bool agentTextsInTimeline(Map<String, dynamic> run) {
  final texts = run['texts'] as List? ?? const [];
  if (texts.isEmpty || '${texts.last}'.trim().isEmpty) return false;
  return (run['steps'] as List? ?? const []).any((s) => s is Map && s['seg'] is num && (s['seg'] as num).toInt() >= texts.length);
}

/// Lượt còn đang chạy (chưa xong / lỗi / bị dừng): hiện đủ mọi bước, không thu gọn.
bool agentRunActive(Map<String, dynamic> run) {
  final s = run['status'] as String? ?? 'running';
  return s == 'thinking' || s == 'running' || s == 'awaiting_approval';
}

/// Nhóm dài hơn số bước này thì sau khi lượt xong chỉ hiện [kStepPreview] bước đầu + "Xem thêm N bước".
const kStepCollapseOver = 6;
const kStepPreview = 3;

/// Dòng thời gian của một lượt: các bước hiện ngay trong tin theo đúng thứ tự (mỗi bước một dòng gọn,
/// có đường nối dọc), xen giữa các đoạn chữ trung gian. Bước mới đến thì hiện thêm ngay (dữ liệu tin cập nhật liên tục).
/// Bấm một bước để mở chi tiết ngay bên dưới. Đoạn chữ cuối là nội dung tin (hiện ở dưới).
class AgentTimeline extends StatefulWidget {
  final Map<String, dynamic> run;
  final TextStyle textStyle;

  /// Khoá giữ trạng thái mở bước / mở nhóm (id tin): tin đang chạy bị dựng lại liên tục, widget có thể bị tạo lại.
  final String? openKey;
  /// Kênh của tin trả lời: bước "files" tìm tin chứa tệp trong kênh này để vẽ ảnh / tệp tại chỗ.
  final String? channelId;
  /// Chat kiểu Claude: lượt đã xong thì mỗi nhóm bước gọn thành một dòng xám "Đã chạy 2 lệnh, Đã nhắn tin cho tác
  /// nhân ›" (bấm để mở từng bước), như app Claude.
  final bool summary;
  const AgentTimeline({super.key, required this.run, required this.textStyle, this.openKey, this.channelId, this.summary = false});

  @override
  State<AgentTimeline> createState() => _AgentTimelineState();
}

class _AgentTimelineState extends State<AgentTimeline> {
  /// Các bước / nhóm người dùng đã mở, theo [AgentTimeline.openKey], sống suốt phiên app.
  static final _store = <String, Set<String>>{};
  final _local = <String>{};

  Set<String> get _open => widget.openKey == null ? _local : _store.putIfAbsent(widget.openKey!, () => <String>{});
  void _toggle(String k) => setState(() {
        if (!_open.remove(k)) _open.add(k);
      });

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final texts = [for (final t in (run['texts'] as List? ?? const [])) '$t'];
    final steps = [for (final s in (run['steps'] as List? ?? const [])) (s as Map).cast<String, dynamic>()];
    final active = agentRunActive(run);
    // Đoạn cuối = nội dung tin, không hiện ở đây; trừ khi đã có bước chạy sau đoạn đó (bước mới phải nằm dưới chữ
    // viết trước nó): khi đó mọi đoạn hiện ở đây theo đúng thứ tự, nội dung tin bên dưới ẩn đi ([agentTextsInTimeline]).
    final shown = texts.isEmpty ? 0 : (agentTextsInTimeline(run) ? texts.length : texts.length - 1);
    final children = <Widget>[];
    // Tin cùng chat (tìm tin câu hỏi của bước hỏi, runner cũ). Tính một lần cho mỗi lần dựng.
    final chatPosts = widget.channelId == null ? const <MmPost>[] : context.read<AppState>().postsOf(widget.channelId!);
    final qCache = <int, List<Map<String, dynamic>>>{};
    List<Map<String, dynamic>> questionsOf(int i) => qCache[i] ??= stepAnsweredQuestions(steps[i], chatPosts);
    void group(int k, bool Function(int) inGroup) {
      // Giữ chỉ số gốc của bước trong lượt: làm khoá mở chi tiết (bước chỉ được nối thêm vào cuối).
      final idx = [for (var i = 0; i < steps.length; i++) if (inGroup((steps[i]['seg'] as num).toInt())) i];
      if (idx.isEmpty) return;
      // Câu hỏi đã trả lời: hiện đủ ngay tại bước hỏi (đúng thứ tự thời gian), không phải thẻ ghim cuối tin.
      final asked = {for (final i in idx) if (questionsOf(i).isNotEmpty) i};
      // Kiểu Claude, lượt đã xong: một dòng tóm tắt; bấm để mở (khoá g<k> = đã mở). Bước gửi tệp (ảnh) và câu hỏi
      // đã trả lời vẫn hiện, xen đúng chỗ: các bước trước câu hỏi tóm tắt một dòng, câu hỏi, rồi các bước sau.
      if (widget.summary && !active) {
        final opened = _open.contains('g$k');
        final plain = [for (final i in idx) if (steps[i]['kind'] != 'files' && !asked.contains(i)) steps[i]];
        if (plain.isNotEmpty && opened) {
          children.add(AgentStepsSummary(steps: plain, open: true, onTap: () => _toggle('g$k')));
        } else if (plain.isNotEmpty || asked.isNotEmpty) {
          var chunk = <Map<String, dynamic>>[];
          void flush() {
            if (chunk.isNotEmpty) children.add(AgentStepsSummary(steps: chunk, open: false, onTap: () => _toggle('g$k')));
            chunk = [];
          }

          for (final i in idx) {
            if (asked.contains(i)) {
              flush();
              for (final q in questionsOf(i)) {
                children.add(AgentAnsweredQuestion(key: ValueKey('q-$i-${q['_post']}'), q: q));
              }
            } else if (steps[i]['kind'] == 'files' && steps[i]['posts'] is List && widget.channelId != null) {
              flush();
              children.add(AgentInlineFiles(
                  key: ValueKey('files-$i'),
                  channelId: widget.channelId!,
                  postIds: [for (final id in steps[i]['posts'] as List) '$id'],
                  label: stepShortLabel(steps[i])));
            } else if (steps[i]['kind'] != 'files') {
              chunk.add(steps[i]);
            }
          }
          flush();
          return;
        }
      }
      // Mặc định hiện đủ các bước; người dùng bấm "Thu gọn" thì nhóm gọn lại (khoá f<k> = đã thu gọn).
      final collapsed = !active && idx.length > kStepCollapseOver && _open.contains('f$k');
      // Bước gửi tệp (ảnh) luôn hiện, kể cả khi nhóm bước đã thu gọn.
      final visible = collapsed
          ? [...idx.take(kStepPreview), ...idx.skip(kStepPreview).where((i) => steps[i]['kind'] == 'files')]
          : idx;
      final canFold = !active && idx.length > kStepCollapseOver && !collapsed;
      final rows = <Widget>[
        for (var j = 0; j < visible.length; j++)
          if (steps[visible[j]]['kind'] == 'files' && steps[visible[j]]['posts'] is List && widget.channelId != null)
            AgentInlineFiles(
              key: ValueKey('files-${visible[j]}'),
              channelId: widget.channelId!,
              postIds: [for (final id in steps[visible[j]]['posts'] as List) '$id'],
              label: stepShortLabel(steps[visible[j]]),
            )
          else if (asked.contains(visible[j]))
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (final q in questionsOf(visible[j])) AgentAnsweredQuestion(key: ValueKey('q-${visible[j]}-${q['_post']}'), q: q),
            ])
          else
          AgentStepRow(
            key: ValueKey('step-${visible[j]}'),
            step: steps[visible[j]],
            first: j == 0,
            last: j == visible.length - 1 && !collapsed && !canFold,
            open: _open.contains('s${visible[j]}'),
            onTap: () => _toggle('s${visible[j]}'),
          ),
        if (collapsed || canFold)
          _MoreRow(
            label: collapsed ? tr('Xem thêm {0} bước', [idx.length - visible.length]) : tr('Thu gọn'),
            folded: collapsed,
            onTap: () => _toggle('f$k'),
          ),
      ];
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: rows),
      ));
    }

    for (var k = 0; k <= shown; k++) {
      group(k, (seg) => k < shown ? seg == k : seg >= k);
      if (k < shown && texts[k].trim().isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: MarkdownView(text: texts[k], style: widget.textStyle),
        ));
      }
    }
    // Nghiên cứu sâu: dải tóm tắt (số lượt tìm, nguồn đã mở, thời gian) ở đầu dòng thời gian.
    if (run['mode'] == 'research') children.insert(0, ResearchSummary(run: run));
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// "Đã chạy", "Đã sửa"… theo loại bước (giống app Claude); đang chạy thì "Đang …".
String stepVerb(Map<String, dynamic> s) {
  final running = s['status'] == 'running' || s['status'] == 'waiting';
  return switch (s['kind'] as String? ?? '') {
    'command' => running ? tr('Đang chạy') : tr('Đã chạy'),
    'file' => running ? tr('Đang sửa') : tr('Đã sửa'),
    'search' => running ? tr('Đang tìm') : tr('Đã tìm'),
    'approval' => tr('Duyệt'),
    'thinking' => tr('Suy nghĩ'),
    _ => running ? tr('Đang dùng') : tr('Đã dùng'),
  };
}

/// Mô tả ngắn một dòng của bước: nhãn runner đặt (nếu có), không thì tiêu đề; bỏ "\$ " đầu lệnh.
String stepShortLabel(Map<String, dynamic> s) =>
    ((s['label'] as String?)?.trim().isNotEmpty == true ? s['label'] as String : (s['title'] as String? ?? ''))
        .replaceFirst(RegExp(r'^\$\s*'), '')
        .replaceAll('\n', ' ')
        .trim();

/// Cột trái của dòng thời gian: đoạn nối phía trên, biểu tượng, đoạn nối phía dưới (kéo dài theo chiều cao dòng).
class _Rail extends StatelessWidget {
  final Widget icon;
  final bool first, last;
  const _Rail({required this.icon, required this.first, required this.last});

  // Chỉ còn biểu tượng trạng thái, bỏ đường kẻ dọc nối các bước (Sếp, 2026-11-14: gọn hơn).
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        child: Column(children: [
          const SizedBox(height: 4),
          SizedBox(width: 16, height: 16, child: Center(child: icon)),
        ]),
      );
}

/// Một bước trong tin: biểu tượng trạng thái (vòng quay / dấu xong / lỗi), "Đã chạy" + mô tả một dòng;
/// bấm để mở chi tiết (tiêu đề đầy đủ + kết quả) ngay bên dưới.
class AgentStepRow extends StatelessWidget {
  final Map<String, dynamic> step;
  final bool first, last, open;
  final VoidCallback onTap;
  const AgentStepRow(
      {super.key, required this.step, required this.first, required this.last, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final s = step;
    final status = s['status'] as String? ?? 'done';
    final error = status == 'error';
    final running = status == 'running';
    final title = (s['title'] as String? ?? '').trim();
    final detail = (s['detail'] as String? ?? '').trim();
    final label = stepShortLabel(s);
    final Widget icon = running
        ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: pal.accentText))
        : status == 'waiting'
            ? Icon(Icons.hourglass_top_rounded, size: 14, color: pal.sub)
            : error
                ? const Icon(Icons.error_outline, size: 15, color: Colors.redAccent)
                : const Icon(Icons.check_rounded, size: 15, color: Color(0xFF2E9D5B));
    final canOpen = title.isNotEmpty || detail.isNotEmpty;
    // Mỗi bước "Đã chạy …" cách bước trên một khoảng cho dễ tách (Sếp, 2026-11-14).
    return Padding(
      padding: EdgeInsets.only(top: first ? 2 : 10),
      child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: canOpen ? onTap : null,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Rail(icon: icon, first: first, last: last),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '${stepVerb(s)} ',
                            style: TextStyle(fontWeight: FontWeight.w600, color: error ? Colors.redAccent : pal.text)),
                        TextSpan(text: label, style: TextStyle(color: pal.sub)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  if (canOpen) Icon(open ? Icons.expand_more : Icons.chevron_right, size: 16, color: pal.sub),
                ]),
                if (open && canOpen) ...[
                  const SizedBox(height: 4),
                  if (title.isNotEmpty) AgentTitle(title, style: TextStyle(fontSize: 13, color: pal.text)),
                  if (detail.isNotEmpty)
                    if (tryParseJson(detail) case final json?)
                      JsonView(value: json)
                    else
                      ShellOutput(detail, error: error),
                ],
              ]),
            ),
          ),
        ]),
      ),
    ));
  }
}

/// Dòng cuối nhóm đã thu gọn: "Xem thêm N bước" (hoặc "Thu gọn" khi đã mở hết).
/// Tóm tắt các bước của một nhóm theo loại, giữ thứ tự xuất hiện: "Đã chạy 2 lệnh, Đã nhắn tin cho tác nhân".
String agentStepsSummaryText(List<Map<String, dynamic>> steps) {
  final counts = <String, int>{};
  // Nhắn agent khác (step.agent_link, runner 0.7.14+): ghi rõ gửi tới ai, câu trả lời về đếm riêng.
  final sentTo = <String>[];
  var replies = 0;
  for (final s in steps) {
    final link = s['agent_link'];
    if (link is Map) {
      if (link['dir'] == 'out') {
        final to = link['to'] is Map ? link['to'] as Map : const {};
        final name = '${to['name'] ?? ''}'.trim();
        final who = '${to['agent'] ?? ''}'.trim().isNotEmpty
            ? tr('agent ngoài {0}', [to['agent']])
            : name.isNotEmpty
            ? tr('phiên {0}', [name])
            : '${to['bot'] ?? ''}'.trim().isNotEmpty
            ? '@${to['bot']}'
            : tr('tác nhân');
        if (!sentTo.contains(who)) sentTo.add(who);
        continue;
      }
      if (link['kind'] == 'reply') {
        replies++;
        continue;
      }
    }
    final k = switch (s['kind'] as String? ?? '') {
      'command' || 'file' || 'search' || 'message' || 'thinking' || 'approval' || 'report' => s['kind'] as String,
      _ => 'tool',
    };
    counts[k] = (counts[k] ?? 0) + 1;
  }
  final parts = [
    for (final e in counts.entries)
      switch (e.key) {
        'command' => tr('Đã chạy {0} lệnh', [e.value]),
        'file' => tr('Đã sửa {0} tệp', [e.value]),
        'search' => tr('Đã tìm kiếm {0} lần', [e.value]),
        'message' => e.value == 1 ? tr('Đã nhắn tin cho tác nhân') : tr('Đã nhắn {0} tin cho tác nhân', [e.value]),
        'thinking' => tr('Đã suy nghĩ'),
        'approval' => tr('Đã xin duyệt {0} lần', [e.value]),
        'report' => tr('Đã báo cáo'),
        _ => tr('Đã dùng {0} công cụ', [e.value]),
      },
  ];
  if (sentTo.isNotEmpty) parts.add(tr('Đã gửi tới {0}', [sentTo.join(', ')]));
  if (replies > 0) parts.add(replies == 1 ? tr('nhận 1 câu trả lời') : tr('nhận {0} câu trả lời', [replies]));
  final errors = steps.where((s) => s['status'] == 'error').length;
  if (errors > 0) parts.add(tr('{0} lỗi', [errors]));
  return parts.join(', ');
}

/// Dòng tóm tắt các bước (kiểu Claude): chữ xám, mũi tên ›; mở thì mũi tên xuống và các bước hiện bên dưới.
class AgentStepsSummary extends StatelessWidget {
  final List<Map<String, dynamic>> steps;
  final bool open;
  final VoidCallback onTap;
  const AgentStepsSummary({super.key, required this.steps, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final error = steps.any((s) => s['status'] == 'error');
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(agentStepsSummaryText(steps),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, height: 1.35, color: error ? Colors.redAccent : pal.sub)),
            ),
            const SizedBox(width: 4),
            Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: pal.sub),
          ]),
        ),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  final String label;
  final bool folded;
  final VoidCallback onTap;
  const _MoreRow({required this.label, required this.folded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Rail(icon: Icon(folded ? Icons.more_horiz : Icons.expand_less, size: 15, color: pal.sub), first: false, last: true),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.accentText)),
          ),
        ]),
      ),
    );
  }
}
