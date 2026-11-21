import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'agent_view.dart' show agentRunOf;
import 'ai_panel.dart' show aiSessionLabel;
import 'common.dart' show plainPreview, two;
import 'markdown_view.dart';
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

  /// Tin này chính là tin qua lại giữa các agent (không phải câu trả lời của trợ lý cho mình): mặc định thu gọn.
  final bool traffic;

  /// Bản ghi tin đã gửi (➡️): câu trả lời đã về {state, text, at} (runner vá vào bản ghi), null nếu chưa có.
  final Map<String, dynamic>? reply;

  /// Tên bên trả lời (cho khối trả lời lồng dưới bản ghi tin đã gửi).
  final String? replier;
  const AgentLinkInfo(this.tone, this.label, {this.sub, this.openChannel, this.traffic = false, this.reply, this.replier});
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
  final info = _linkOf(app, p);
  if (info == null || info.traffic || !_postLevel(p)) return info;
  return AgentLinkInfo(info.tone, info.label, sub: info.sub, openChannel: info.openChannel, traffic: true, reply: info.reply, replier: info.replier);
}

/// Đã có bản ghi tin gửi tới [to] trong chat của [p], đăng trong vòng 2 giờ trước [p] (cùng lượt chạy).
bool _hasRecord(AppState app, MmPost p, Map<String, dynamic> to) => app.postsOf(p.channelId).any((x) {
      final l = _m(x.props['flygo_agent_link']);
      if (l.isEmpty || _s(l['dir']) != 'out' || _s(l['kind']) == 'reply') return false;
      if (x.createAt > p.createAt || p.createAt - x.createAt > 2 * 3600000) return false;
      final t = _m(l['to']);
      return _s(t['session']) == _s(to['session']) && _s(t['agent']) == _s(to['agent']) && _s(t['bot']) == _s(to['bot']);
    });

/// Tin mang nhãn ở chính tin (không phải suy ra từ các bước agent_send trong thẻ tiến trình).
bool _postLevel(MmPost p) => const ['flygo_agent_link', 'flygo_bridge', 'flygo_a2a_from', 'flygo_team_from'].any((k) => p.props[k] is Map);

AgentLinkInfo? _linkOf(AppState app, MmPost p) {
  final props = p.props;
  final link = _m(props['flygo_agent_link']);
  if (link.isNotEmpty) {
    final kind = _s(link['kind']);
    final dir = _s(link['dir']);
    final from = _m(link['from']), to = _m(link['to']);
    final agent = _s(from['agent']);
    // Bản ghi tin trợ lý đã gửi cho agent khác (runner đăng ngay khi gửi, vá câu trả lời vào khi có).
    if (kind != 'reply' && dir == 'out') {
      final who = _who(app, to);
      var reply = _m(link['reply']);
      final state = _s(reply['state']);
      // Agent ngoài: bản ghi chỉ có "đã gửi vào hộp thư"; câu trả lời thật về sau thành tin cầu nối
      // (props.flygo_bridge.reply_to = reply.message_id) → lồng câu trả lời đó vào đây.
      if (state == 'delivered') {
        final mid = _s(reply['message_id']);
        final ans = mid.isEmpty
            ? null
            : app.postsOf(p.channelId).where((x) => _s(_m(x.props['flygo_bridge'])['reply_to']) == mid).firstOrNull;
        reply = ans == null ? reply : {'state': 'completed', 'text': ans.message, 'at': ans.createAt};
      }
      final st = _s(reply['state']);
      return AgentLinkInfo(AgentLinkTone.outgoing, tr('➡️ Gửi tới {0}', [who.isEmpty ? tr('agent khác') : who]),
          sub: reply.isEmpty
              ? tr('đang chờ trả lời')
              : st == 'completed'
              ? tr('đã trả lời')
              : st == 'delivered'
              ? tr('đã gửi vào hộp thư')
              : tr('không có trả lời'),
          openChannel: _openable(app, _s(to['session'])),
          reply: reply.isEmpty || st == 'delivered' ? null : reply,
          replier: who.isEmpty ? null : who);
    }
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
        // Runner 0.7.15+ đăng bản ghi riêng cho mỗi lần gửi (tin flygo_agent_link dir out ngay trước câu trả lời):
        // nhãn nằm ở bản ghi đó, không lặp ở đây.
        if (_hasRecord(app, p, to)) continue;
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

/// Tin giữa các agent đang thu gọn: 1–2 dòng xem trước + giờ; bấm để mở đầy đủ.
class AgentTrafficCollapsed extends StatelessWidget {
  final MmPost post;
  final AgentLinkInfo info;
  final VoidCallback onExpand;
  const AgentTrafficCollapsed({super.key, required this.post, required this.info, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.read<AppState>();
    final mine = post.userId == app.me?.id;
    final preview = plainPreview(post.message);
    final at = DateTime.fromMillisecondsSinceEpoch(post.createAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: InkWell(
            key: ValueKey('agent-traffic-${post.id}'),
            borderRadius: BorderRadius.circular(12),
            onTap: onExpand,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: AgentLinkChip.colorOf(info.tone).withValues(alpha: .6), width: 3)),
                color: pal.text.withValues(alpha: .04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(preview.isEmpty ? tr('(không có nội dung)') : preview,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.4, color: pal.sub)),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${two(at.hour)}:${two(at.minute)}', style: TextStyle(fontSize: 11.5, color: pal.sub)),
                  Icon(Icons.expand_more_rounded, size: 18, color: pal.sub),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Câu trả lời lồng dưới bản ghi tin đã gửi (➡️), và nút "Thu gọn" của tin giữa các agent đang mở.
class AgentTrafficFooter extends StatelessWidget {
  final MmPost post;
  final AgentLinkInfo info;
  final VoidCallback onCollapse;
  const AgentTrafficFooter({super.key, required this.post, required this.info, required this.onCollapse});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final mine = post.userId == context.read<AppState>().me?.id;
    final r = info.reply;
    final text = _s(r?['text']);
    final ok = _s(r?['state']) == 'completed';
    final at = (r?['at'] as num?)?.toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (r != null)
          Container(
            key: ValueKey('agent-reply-${post.id}'),
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            constraints: const BoxConstraints(maxWidth: 720),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: AgentLinkChip.colorOf(ok ? AgentLinkTone.reply : AgentLinkTone.outgoing), width: 3)),
              color: pal.text.withValues(alpha: .04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                [
                  ok ? tr('↩︎ {0} trả lời', [info.replier ?? tr('Bên nhận')]) : tr('⚠️ Không có trả lời'),
                  if (at != null) '${two(DateTime.fromMillisecondsSinceEpoch(at).hour)}:${two(DateTime.fromMillisecondsSinceEpoch(at).minute)}',
                ].join(' · '),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pal.sub),
              ),
              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: MarkdownView(text: text, style: TextStyle(fontSize: 14.5, height: 1.45, color: pal.text)),
                ),
            ]),
          ),
        TextButton.icon(
          onPressed: onCollapse,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: pal.sub),
          icon: const Icon(Icons.expand_less_rounded, size: 18),
          label: Text(tr('Thu gọn'), style: const TextStyle(fontSize: 13)),
        ),
      ]),
    );
  }
}
