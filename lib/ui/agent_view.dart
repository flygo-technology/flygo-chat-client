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
  _ => s,
};

Color _statusColor(String s, Pal pal) => switch (s) {
  'done' => const Color(0xFF2E9D5B),
  'error' => Colors.redAccent,
  'awaiting_approval' => const Color(0xFFF5A623),
  'cancelled' => pal.sub,
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
  const AgentRunCard(
      {super.key, required this.run, this.compact = false, this.name, this.openKey, this.stepsElsewhere = false, this.quiet = false});
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        if (todos.isNotEmpty) AgentTodoList(todos: todos, active: active),
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
      ],
    );
  }
}

/// Danh sách việc agent tự lập trong lượt (props.flygo_agent.todos, runner 0.6.79+): checklist
/// chưa làm / đang làm / xong. Lượt đang chạy thì mở sẵn; lượt đã xong thu gọn thành một dòng, bấm để mở.
class AgentTodoList extends StatefulWidget {
  final List<Map<String, dynamic>> todos;
  final bool active;
  const AgentTodoList({super.key, required this.todos, required this.active});
  @override
  State<AgentTodoList> createState() => _AgentTodoListState();
}

class _AgentTodoListState extends State<AgentTodoList> {
  bool? _open; // null: theo trạng thái lượt

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final open = _open ?? true; // mặc định mở, bấm để thu gọn
    final done = widget.todos.where((t) => t['status'] == 'completed').length;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        border: Border.all(color: pal.text.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.checklist_rounded, size: 16, color: pal.sub),
                const SizedBox(width: 6),
                Text(tr('Kế hoạch việc'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.sub)),
                Text(' · $done/${widget.todos.length}', style: TextStyle(fontSize: 13, color: pal.sub)),
                const SizedBox(width: 2),
                Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: pal.sub),
              ]),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final t in widget.todos) _TodoRow(todo: t, active: widget.active)],
              ),
            ),
        ],
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
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: pal.text, height: 1.3),
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

/// Hai vòng tròn cạnh nhau: vòng 1 = ngữ cảnh của phiên (% đã dùng), vòng 2 = hạn mức tài khoản engine còn lại
/// (cửa sổ 5 giờ / tuần đang dùng nhiều nhất). Giữ chuột xem nhanh, bấm vòng nào cũng mở hộp chi tiết có thanh tiến độ.
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

  Widget _ring(BuildContext context, {required Key key, required double? value, required Color color, required String label, required String tip}) {
    final pal = Pal.of(context);
    return Tooltip(
      message: tip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _details(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  key: key,
                  value: value ?? 0,
                  strokeWidth: 3,
                  backgroundColor: pal.text.withValues(alpha: .12),
                  color: color,
                ),
              ),
              Text(label, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: pal.text)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ctx;
    final l = limits;
    if (c == null && l == null && !always) return const SizedBox.shrink();
    final pal = Pal.of(context);
    final t = now ?? DateTime.now();
    final f = c == null ? 0.0 : (c.used / c.max).clamp(0.0, 1.0);
    final used = (l?.maxUsed(t) ?? 0).clamp(0, 100);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (c != null || always)
        _ring(
          context,
          key: const ValueKey('usage-context-ring'),
          value: f,
          color: usageColor(f, const Color(0xFF2E9D5B)),
          label: c == null ? '-' : '${(f * 100).round()}',
          tip: c == null ? tr('Ngữ cảnh: chưa có số liệu') : tr('Ngữ cảnh: {0} / {1} token ({2}%)', [_kTokens(c.used), _kTokens(c.max), (f * 100).round()]),
        ),
      if (l != null || always)
        _ring(
          context,
          key: const ValueKey('usage-limit-ring'),
          // Vòng hạn mức: % đã dùng của cửa sổ dùng nhiều nhất (như vòng ngữ cảnh); đỏ khi sắp hết / đã chạm hạn mức.
          value: l == null ? 0 : used / 100,
          color: l != null && l.reached ? const Color(0xFFE5484D) : usageColor(used / 100, pal.accent),
          label: l == null ? '-' : '$used',
          tip: l == null ? tr('Hạn mức: chưa có số liệu') : [for (final w in l.windows) agentLimitLine(w, t)].join('\n'),
        ),
    ]);
  }
}

/// Hai vòng tròn ở góc trên bên phải chat trợ lý: % ngữ cảnh và % hạn mức đã dùng; bấm xem chi tiết.
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
    Widget optionTile((String, String) o) {
      final sel = _picked.contains(o.$1);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: sel ? pal.accent.withValues(alpha: .16) : pal.text.withValues(alpha: .05),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: BorderSide(color: sel ? pal.accent : Colors.transparent, width: 1.4)),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            // Chọn xong mới gửi bằng nút Xác nhận (cả một lựa chọn lẫn nhiều lựa chọn).
            onTap: answered
                ? null
                : () => setState(() {
                      if (!multi) {
                        _picked
                          ..clear()
                          ..add(o.$1);
                        _other = false;
                      } else {
                        sel ? _picked.remove(o.$1) : _picked.add(o.$1);
                      }
                    }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Icon(
                    multi
                        ? (sel ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                        : (sel ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    size: 20,
                    color: sel ? pal.accentText : pal.sub),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.$1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text)),
                    if (o.$2.isNotEmpty) Text(o.$2, style: TextStyle(fontSize: 13, color: pal.sub)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: pal.accent.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.accent.withValues(alpha: .25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.help_outline_rounded, size: 18, color: pal.accentText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(q['question'] as String? ?? '',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
          ),
        ]),
        if (!answered)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(multi ? tr('Chọn một hoặc nhiều, rồi bấm Xác nhận') : tr('Chọn một, rồi bấm Xác nhận'),
                style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ),
        const SizedBox(height: 10),
        if (q['status'] == 'expired' && _sentById[_id] == null)
          Row(children: [
            Icon(Icons.timer_off_outlined, size: 18, color: pal.sub),
            const SizedBox(width: 6),
            Text(tr('Câu hỏi đã hết hạn'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.sub)),
          ])
        else if (answered && (_sentById[_id] == 'cancelled' || q['status'] == 'cancelled'))
          Row(children: [
            Icon(Icons.cancel_rounded, size: 18, color: pal.sub),
            const SizedBox(width: 6),
            Text(tr('Đã huỷ'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.sub)),
          ])
        else if (answered)
          Row(children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF2E9D5B)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                  answer is String && answer.isNotEmpty ? tr('Đã trả lời: {0}', [answer]) : tr('Đã trả lời'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2E9D5B))),
            ),
          ])
        else ...[
          for (final o in options) optionTile(o),
          if (allowOther)
            _other
                ? Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _otherCtl,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 4,
                        style: TextStyle(color: pal.text),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: tr('Nhập câu trả lời khác…'),
                          filled: true,
                          fillColor: pal.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ])
                : TextButton.icon(
                    onPressed: () => setState(() {
                      _other = true;
                      if (!multi) _picked.clear();
                    }),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(tr('Khác…')),
                  ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent, minimumSize: const Size(64, 44)),
              onPressed: () => _cancel(app),
              child: Text(tr('Huỷ')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(shape: const StadiumBorder()),
              onPressed: _picked.isEmpty && (!_other || _otherCtl.text.trim().isEmpty)
                  ? null
                  : () => _submit(app, _picked.toList(), _other ? _otherCtl.text : ''),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(tr('Xác nhận')),
            ),
          ]),
        ],
      ]),
    );
  }
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
  const AgentTimeline({super.key, required this.run, required this.textStyle, this.openKey, this.channelId});

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
    void group(int k, bool Function(int) inGroup) {
      // Giữ chỉ số gốc của bước trong lượt: làm khoá mở chi tiết (bước chỉ được nối thêm vào cuối).
      final idx = [for (var i = 0; i < steps.length; i++) if (inGroup((steps[i]['seg'] as num).toInt())) i];
      if (idx.isEmpty) return;
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

  @override
  Widget build(BuildContext context) {
    final line = Pal.of(context).text.withValues(alpha: .18);
    return SizedBox(
      width: 22,
      child: Column(children: [
        Container(width: 1.5, height: 4, color: first ? Colors.transparent : line),
        SizedBox(width: 16, height: 16, child: Center(child: icon)),
        Expanded(child: Container(width: 1.5, color: last ? Colors.transparent : line)),
      ]),
    );
  }
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
    return InkWell(
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
    );
  }
}

/// Dòng cuối nhóm đã thu gọn: "Xem thêm N bước" (hoặc "Thu gọn" khi đã mở hết).
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
