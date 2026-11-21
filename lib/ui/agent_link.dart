import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'agent_view.dart' show agentRunOf;
import 'ai_panel.dart' show aiSessionLabel;
import 'schedules_view.dart' show openChatWith;
import 'theme.dart';

/// Loại nhãn tin giữa các agent; mỗi loại một màu.
enum AgentLinkTone { incoming, reply, outgoing, external }

/// Nhãn phía trên tin giữa các agent: tin này từ phiên / agent nào tới, hay gửi về / gửi tới đâu.
class AgentLinkInfo {
  final AgentLinkTone tone;
  final String label;
  final String? sub;

  /// Phiên mở được khi bấm (chỉ khi mình có trong chat đó).
  final String? openChannel;
  const AgentLinkInfo(this.tone, this.label, {this.sub, this.openChannel});
}

Map<String, dynamic> _m(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
String _s(Object? v) => v is String ? v.trim() : (v == null ? '' : '$v');

/// Tên một phiên: tên runner gửi kèm, không có thì tên chat mình đang có, không nữa thì "phiên khác".
String _sessionName(AppState app, Map<String, dynamic> end) {
  final name = _s(end['name']);
  if (name.isNotEmpty) return name;
  final ch = app.channels[_s(end['session'])];
  if (ch != null) return ch.isAi ? aiSessionLabel(ch) : app.channelTitle(ch);
  return '';
}

String? _openable(AppState app, String id) => id.isNotEmpty && app.channels.containsKey(id) ? id : null;

/// Một đầu của liên kết thành chữ: "phiên «X» · @bot", "@bot", "agent ngoài X".
String _who(AppState app, Map<String, dynamic> end, {bool withBot = true}) {
  final agent = _s(end['agent']);
  if (agent.isNotEmpty) return tr('agent ngoài {0}', [agent]);
  final name = _sessionName(app, end);
  final bot = _s(end['bot']);
  final parts = [
    if (name.isNotEmpty) tr('phiên {0}', [name]) else if (_s(end['session']).isNotEmpty) tr('phiên khác'),
    if (withBot && bot.isNotEmpty) '@$bot',
  ];
  return parts.join(' · ');
}

/// Nhãn của một tin giữa các agent, null nếu là tin thường. Đọc props.flygo_agent_link (runner 0.7.14+), không có thì
/// các props cũ: flygo_a2a_from, flygo_team_from, flygo_bridge, flygo_session_handoff, flygo_bg_task_result; phía
/// gửi: các bước agent_send trong thẻ tiến trình (step.agent_link).
AgentLinkInfo? agentLinkOf(AppState app, MmPost p) {
  final props = p.props;
  final link = _m(props['flygo_agent_link']);
  if (link.isNotEmpty) {
    final kind = _s(link['kind']);
    final dir = _s(link['dir']);
    final from = _m(link['from']), to = _m(link['to']);
    final agent = _s(from['agent']);
    if (kind == 'reply' && dir == 'out') {
      final who = _who(app, to);
      return AgentLinkInfo(AgentLinkTone.reply, who.isEmpty ? tr('↩︎ Trả lời bên nhờ') : tr('↩︎ Trả lời {0}', [who]),
          openChannel: _openable(app, _s(to['session'])));
    }
    if (agent.isNotEmpty) {
      return AgentLinkInfo(AgentLinkTone.external, tr('🔗 Agent ngoài {0}', [agent]),
          sub: kind == 'reply' ? tr('trả lời qua Token MCP') : tr('gửi qua Token MCP'));
    }
    if (dir == 'in') {
      final who = _who(app, from);
      return AgentLinkInfo(AgentLinkTone.incoming, who.isEmpty ? tr('📨 Từ agent khác') : tr('📨 Từ {0}', [who]),
          sub: kind == 'handoff' ? tr('giao việc') : null, openChannel: _openable(app, _s(from['session'])));
    }
  }
  // Agent ngoài gửi qua Token MCP (trạm đẩy).
  if (props['flygo_bridge'] is Map) return AgentLinkInfo(AgentLinkTone.external, tr('🔗 Agent ngoài'), sub: tr('gửi qua Token MCP'));
  // Runner cũ: phiên / đồng đội nhờ qua A2A, ghi chú của đồng đội.
  final a2a = _m(props['flygo_a2a_from']);
  if (a2a.isNotEmpty) {
    final own = _s(a2a['bot_id']) == p.userId;
    final who = _who(app, {'name': a2a['title'], 'session': a2a['session'], 'bot': own ? null : a2a['username']});
    return AgentLinkInfo(AgentLinkTone.incoming, who.isEmpty ? tr('📨 Từ agent khác') : tr('📨 Từ {0}', [who]),
        openChannel: _openable(app, _s(a2a['session'])));
  }
  final team = _m(props['flygo_team_from']);
  if (team.isNotEmpty) {
    final who = _who(app, {'session': team['session'], 'bot': team['username']});
    return AgentLinkInfo(AgentLinkTone.incoming, tr('📨 Từ {0}', [who.isEmpty ? '@${_s(team['username'])}' : who]),
        sub: tr('ghi chú'), openChannel: _openable(app, _s(team['session'])));
  }
  // Tách / chuyển / giao việc chạy ngầm giữa các phiên của cùng trợ lý.
  final h = _m(props['flygo_session_handoff']);
  if (h.isNotEmpty) {
    final kind = _s(h['kind']);
    if (kind == 'moved') {
      return AgentLinkInfo(AgentLinkTone.outgoing, tr('➡️ Chuyển sang {0}', [_who(app, {'name': h['title'], 'session': h['to']})]),
          openChannel: _openable(app, _s(h['to'])));
    }
    final who = _who(app, {'session': h['from']});
    return AgentLinkInfo(AgentLinkTone.incoming, tr('📨 Từ {0}', [who.isEmpty ? tr('phiên khác') : who]),
        sub: kind == 'task' ? tr('việc chạy ngầm') : (kind == 'fork' ? tr('tách phiên') : null), openChannel: _openable(app, _s(h['from'])));
  }
  final bg = _m(props['flygo_bg_task_result']);
  if (bg.isNotEmpty) {
    return AgentLinkInfo(AgentLinkTone.reply, tr('↩︎ Kết quả từ {0}', [_who(app, {'name': bg['title'], 'session': bg['task']})]),
        openChannel: _openable(app, _s(bg['task'])));
  }
  // Phía gửi: lượt này đã nhắn agent khác (agent_send) → "➡️ Gửi tới …", kèm "đã trả lời" khi có kết quả về.
  final run = agentRunOf(p);
  if (run != null) {
    final outs = <String>[];
    String? open;
    var replies = 0;
    for (final s in (run['steps'] as List? ?? const [])) {
      final l = _m(_m(s)['agent_link']);
      if (l.isEmpty) continue;
      if (_s(l['dir']) == 'out') {
        final to = _m(l['to']);
        final who = _who(app, to);
        if (who.isNotEmpty && !outs.contains(who)) outs.add(who);
        open ??= _openable(app, _s(to['session']));
      } else if (_s(l['kind']) == 'reply') {
        replies++;
      }
    }
    if (outs.isNotEmpty) {
      return AgentLinkInfo(AgentLinkTone.outgoing, tr('➡️ Gửi tới {0}', [outs.join(', ')]),
          sub: replies > 0 ? (replies == 1 ? tr('đã trả lời') : tr('{0} câu trả lời', [replies])) : null, openChannel: outs.length == 1 ? open : null);
    }
  }
  return null;
}

/// Chip nhãn tin giữa các agent, đặt phía trên bong bóng (cùng phía với bong bóng). Bấm: mở phiên nguồn / đích.
class AgentLinkChip extends StatelessWidget {
  final AgentLinkInfo info;
  final bool mine;
  const AgentLinkChip({super.key, required this.info, this.mine = false});

  static Color colorOf(AgentLinkTone t) => switch (t) {
        AgentLinkTone.incoming => const Color(0xFF2F6FEB),
        AgentLinkTone.reply => const Color(0xFF2E9D5B),
        AgentLinkTone.outgoing => const Color(0xFFD97757),
        AgentLinkTone.external => const Color(0xFF6C4CE0),
      };

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = colorOf(info.tone);
    // Bản tối: chữ sáng hơn cho đủ tương phản trên nền tối.
    final fg = dark ? Color.lerp(base, Colors.white, .35)! : base;
    final open = info.openChannel;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: base.withValues(alpha: dark ? .2 : .12), borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(info.label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ),
        if (open != null) Icon(Icons.chevron_right_rounded, size: 16, color: fg),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
        Flexible(
          child: open == null
              ? chip
              : Tooltip(
                  message: tr('Mở phiên'),
                  child: InkWell(borderRadius: BorderRadius.circular(10), onTap: () => openChatWith(context, open), child: chip),
                ),
        ),
        if (info.sub != null) ...[
          const SizedBox(width: 6),
          Text(info.sub!, style: TextStyle(fontSize: 11.5, color: pal.sub)),
        ],
      ]),
    );
  }
}

/// Nhãn của tin [p] nếu là tin giữa các agent.
class AgentLinkLabel extends StatelessWidget {
  final MmPost post;
  const AgentLinkLabel({super.key, required this.post});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final info = agentLinkOf(app, post);
    if (info == null) return const SizedBox.shrink();
    return AgentLinkChip(info: info, mine: post.userId == app.me?.id);
  }
}
