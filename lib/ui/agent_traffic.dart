import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'agent_link.dart';
import 'chat_info_page.dart' show openDirectWith;
import 'common.dart' show Avatar, hhmm, plainPreview;
import 'markdown_view.dart';
import 'schedules_view.dart' show openChatWith;
import 'shell_highlight.dart' show aiAnswerStyle;
import 'theme.dart';

/// Một tin qua lại giữa các agent, đủ để vẽ thẻ và hộp xem đầy đủ: gửi đi / nhận về, với ai, trạng thái, nội dung,
/// câu trả lời (nếu có).
class AgentTraffic {
  final AgentLinkTone tone;

  /// Tin mình (trợ lý của mình) gửi đi; false = nhận từ agent khác.
  final bool sent;

  /// "Gửi tới @ba-claude", "Nhận từ phiên Build · @jessica", "Trả lời phiên X"…
  final String title;

  /// Bên kia (để hiện ảnh đại diện và mở chat 1-1): tên đăng nhập của bot; null nếu là agent ngoài / không rõ.
  final String? bot;

  /// Agent ngoài (Token MCP): tên hiện ở hộp xem.
  final String? agent;

  /// Phiên bên kia mở được (mình có trong chat đó).
  final String? openChannel;
  final String? status;
  final String message;
  final int at;
  final String? replyText;
  final String? replyWho;
  final int? replyAt;
  final bool replyOk;

  /// Biểu tượng riêng (vd. sub-agent) thay cho biểu tượng theo hướng tin.
  final IconData? customIcon;

  /// Nhãn khối kết quả thay cho "X trả lời" (vd. "Kết quả").
  final String? replyLabel;

  /// Nút "Dừng" trong hộp xem (sub-agent chạy nền); null = không có nút.
  final Future<void> Function()? onStop;
  const AgentTraffic({
    required this.tone,
    required this.sent,
    required this.title,
    required this.message,
    required this.at,
    this.bot,
    this.agent,
    this.openChannel,
    this.status,
    this.replyText,
    this.replyWho,
    this.replyAt,
    this.replyOk = true,
    this.customIcon,
    this.replyLabel,
    this.onStop,
  });

  IconData get icon => customIcon ?? switch (tone) {
        AgentLinkTone.outgoing => Icons.call_made_rounded,
        AgentLinkTone.reply => Icons.reply_rounded,
        AgentLinkTone.external => Icons.hub_rounded,
        AgentLinkTone.incoming => Icons.call_received_rounded,
      };
}

Map<String, dynamic> _m(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
String _s(Object? v) => v is String ? v.trim() : (v == null ? '' : '$v');

/// Tên một đầu liên kết: "phiên X · @bot", "@bot", "agent ngoài X".
String _end(AppState app, Map<String, dynamic> e) {
  final agent = _s(e['agent']);
  if (agent.isNotEmpty) return tr('agent ngoài {0}', [agent]);
  var name = _s(e['name']);
  if (name.isEmpty) {
    final ch = app.channels[_s(e['session'])];
    if (ch != null) name = ch.aiTitle.isNotEmpty ? ch.aiTitle : app.channelTitle(ch);
  }
  final bot = _s(e['bot']);
  return [if (name.isNotEmpty) tr('phiên {0}', [name]), if (bot.isNotEmpty) '@$bot'].join(' · ');
}

/// Tin [p] là tin qua lại giữa các agent ([AgentLinkInfo.traffic]): dữ liệu cho thẻ / hộp xem; null nếu không phải.
AgentTraffic? agentTrafficOf(AppState app, MmPost p) {
  final info = agentLinkOf(app, p);
  if (info == null || !info.traffic) return null;
  final link = _m(p.props['flygo_agent_link']);
  final kind = _s(link['kind']), dir = _s(link['dir']);
  final from = _m(link['from']), to = _m(link['to']);
  final a2a = _m(p.props['flygo_a2a_from']), team = _m(p.props['flygo_team_from']);
  final message = p.message.replaceAll('⁠', '');
  // Gửi đi: bản ghi agent_send (dir out, không phải trả lời) hoặc câu trả lời gửi về bên nhờ (reply / out).
  if (dir == 'out') {
    final who = _end(app, to);
    final reply = info.reply;
    return AgentTraffic(
      tone: info.tone,
      sent: true,
      title: kind == 'reply' ? tr('Trả lời {0}', [who.isEmpty ? tr('bên nhờ') : who]) : tr('Gửi tới {0}', [who.isEmpty ? tr('agent khác') : who]),
      bot: _s(to['bot']).isEmpty ? null : _s(to['bot']),
      agent: _s(to['agent']).isEmpty ? null : _s(to['agent']),
      openChannel: info.openChannel,
      status: kind == 'reply' ? null : info.sub,
      message: message,
      at: p.createAt,
      replyText: reply == null ? null : _s(reply['text']),
      replyWho: info.replier,
      replyAt: (reply?['at'] as num?)?.toInt(),
      replyOk: _s(reply?['state']) == 'completed',
    );
  }
  // Nhận về: từ phiên / đồng đội / bot được tag / agent ngoài (runner mới), hoặc props cũ.
  final agent = _s(from['agent']);
  final bot = _s(from['bot']).isNotEmpty ? _s(from['bot']) : (_s(a2a['username']).isNotEmpty ? _s(a2a['username']) : _s(team['username']));
  var who = link.isNotEmpty
      ? _end(app, from)
      : a2a.isNotEmpty
      ? _end(app, {'name': a2a['title'], 'session': a2a['session'], 'bot': a2a['username']})
      : team.isNotEmpty
      ? _end(app, {'session': team['session'], 'bot': team['username']})
      : tr('agent ngoài');
  if (who.isEmpty) who = tr('agent khác');
  return AgentTraffic(
    tone: info.tone,
    sent: false,
    title: agent.isNotEmpty && kind == 'reply' ? tr('{0} trả lời', [who]) : tr('Nhận từ {0}', [who]),
    bot: bot.isEmpty || agent.isNotEmpty ? null : bot,
    agent: agent.isEmpty ? null : agent,
    openChannel: info.openChannel,
    status: info.sub,
    message: message,
    at: p.createAt,
  );
}

/// Một bước nhắn agent trong thẻ chạy (agent_send / "Hỏi @x", step.agent_link): cùng dữ liệu để mở hộp xem.
/// Câu trả lời lấy ở bước trả lời đi kèm (cùng id, đuôi "-a") nếu có.
AgentTraffic? agentTrafficOfStep(AppState app, Map<String, dynamic> step, List<Map<String, dynamic>> steps, int at) {
  final link = _m(step['agent_link']);
  if (link.isEmpty) return null;
  final dir = _s(link['dir']), kind = _s(link['kind']);
  final detail = _s(step['detail']);
  if (dir == 'out') {
    final to = _m(link['to']);
    final who = _end(app, to);
    final id = _s(step['id']);
    final ans = id.endsWith('-q') ? steps.where((x) => _s(x['id']) == '${id.substring(0, id.length - 2)}-a').firstOrNull : null;
    final st = _s(step['status']);
    return AgentTraffic(
      tone: AgentLinkTone.outgoing,
      sent: true,
      title: tr('Gửi tới {0}', [who.isEmpty ? tr('agent khác') : who]),
      bot: _s(to['bot']).isEmpty ? null : _s(to['bot']),
      agent: _s(to['agent']).isEmpty ? null : _s(to['agent']),
      openChannel: app.channels.containsKey(_s(to['session'])) ? _s(to['session']) : null,
      status: st == 'running' ? tr('đang chờ trả lời') : (ans != null ? tr('đã trả lời') : (st == 'error' ? tr('lỗi') : null)),
      message: detail,
      at: at,
      replyText: ans == null ? null : _s(ans['detail']),
      replyWho: who,
      replyOk: ans?['status'] != 'error',
    );
  }
  final from = _m(link['from']);
  final who = _end(app, from);
  return AgentTraffic(
    tone: kind == 'reply' ? AgentLinkTone.reply : AgentLinkTone.incoming,
    sent: false,
    title: kind == 'reply' ? tr('{0} trả lời', [who.isEmpty ? tr('Bên nhận') : who]) : tr('Nhận từ {0}', [who.isEmpty ? tr('agent khác') : who]),
    bot: _s(from['bot']).isEmpty ? null : _s(from['bot']),
    openChannel: app.channels.containsKey(_s(from['session'])) ? _s(from['session']) : null,
    message: detail,
    at: at,
  );
}

Color _toneColor(AgentLinkTone t, bool dark) {
  final c = AgentLinkChip.colorOf(t);
  return dark ? Color.lerp(c, Colors.white, .3)! : c;
}

/// Biểu tượng tròn theo hướng tin (gửi đi ↗ / nhận về ↙ / trả lời / agent ngoài).
class _ToneIcon extends StatelessWidget {
  final AgentTraffic t;
  final double size;
  const _ToneIcon(this.t, {this.size = 34});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = _toneColor(t.tone, dark);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: dark ? .22 : .14), shape: BoxShape.circle),
      child: Icon(t.icon, size: size * .55, color: c),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusPill(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
      );
}

Color _statusColor(String s, Pal pal) => s == tr('đã trả lời')
    ? const Color(0xFF2E9D5B)
    : s == tr('đang chờ trả lời')
    ? const Color(0xFFD08A1E)
    : s == tr('không có trả lời') || s == tr('lỗi')
    ? const Color(0xFFE5484D)
    : pal.sub;

/// Thẻ tin gửi / nhận giữa các agent trong khung chat: viền + nền theo hướng, biểu tượng, "Gửi tới @x" / "Nhận từ @x",
/// trạng thái, giờ, 3 dòng xem trước, ảnh đại diện bên kia. Bấm: mở hộp xem đầy đủ ([showAgentTraffic]).
class AgentTrafficCard extends StatelessWidget {
  final AgentTraffic t;
  final Key? tapKey;
  const AgentTrafficCard({super.key, required this.t, this.tapKey});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = _toneColor(t.tone, dark);
    final app = context.read<AppState>();
    final user = t.bot == null ? null : app.users.values.where((u) => u.username == t.bot).firstOrNull;
    final preview = plainPreview(t.message);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Material(
            color: c.withValues(alpha: dark ? .08 : .05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.withValues(alpha: dark ? .45 : .35))),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: tapKey,
              onTap: () => showAgentTraffic(context, t),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _ToneIcon(t),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Expanded(
                          child: Text(t.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
                        ),
                        const SizedBox(width: 8),
                        Text(hhmm(DateTime.fromMillisecondsSinceEpoch(t.at)), style: TextStyle(fontSize: 12, color: pal.sub)),
                      ]),
                      if (t.status != null) ...[
                        const SizedBox(height: 3),
                        _StatusPill(t.status!, _statusColor(t.status!, pal)),
                      ],
                      const SizedBox(height: 6),
                      Text(preview.isEmpty ? tr('(không có nội dung)') : preview,
                          maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.4, color: pal.text.withValues(alpha: .85))),
                    ]),
                  ),
                  if (user != null) ...[
                    const SizedBox(width: 10),
                    Avatar(userId: user.id, name: user.displayName, size: 28, status: false),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hộp xem đầy đủ một tin giữa các agent: điện thoại là trang trượt lên gần hết màn hình, máy tính là hộp giữa màn hình
/// rộng ~720 px, cao tối đa 85%. Nội dung đủ (markdown, cuộn được), câu trả lời (nếu có), sao chép, mở chat với bên kia.
Future<void> showAgentTraffic(BuildContext context, AgentTraffic t) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 760) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720, maxHeight: size.height * .85),
          child: AgentTrafficView(t: t),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SizedBox(height: MediaQuery.sizeOf(ctx).height * .9, child: AgentTrafficView(t: t, sheet: true)),
  );
}

/// Nội dung hộp xem (dùng chung trang trượt và hộp giữa màn hình).
class AgentTrafficView extends StatelessWidget {
  final AgentTraffic t;
  final bool sheet;
  const AgentTrafficView({super.key, required this.t, this.sheet = false});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = _toneColor(t.tone, dark);
    final app = context.read<AppState>();
    final user = t.bot == null ? null : app.users.values.where((u) => u.username == t.bot).firstOrNull;
    // Cùng kiểu chữ đọc với câu trả lời của trợ lý (Inter, code JetBrains Mono).
    final body = aiAnswerStyle(pal.text).copyWith(fontSize: 15);
    final at = DateTime.fromMillisecondsSinceEpoch(t.at);
    // Trang trượt (điện thoại) cao cố định: nội dung chiếm phần giữa, hàng nút luôn ở đáy. Hộp giữa màn hình (máy tính)
    // co theo nội dung, tối đa 85% chiều cao.
    Widget middle(Widget child) => sheet ? Expanded(child: child) : Flexible(child: child);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: sheet ? MainAxisSize.max : MainAxisSize.min, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(20, sheet ? 0 : 18, 8, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ToneIcon(t, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c)),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${hhmm(at)}, ${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 12.5, color: pal.sub)),
                if (t.status != null) _StatusPill(t.status!, _statusColor(t.status!, pal)),
              ]),
            ]),
          ),
          IconButton(tooltip: tr('Đóng'), icon: Icon(Icons.close_rounded, color: pal.sub), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Divider(height: 1, color: pal.divider),
      middle(
        SingleChildScrollView(
          key: const ValueKey('agent-traffic-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectionArea(child: MarkdownView(text: t.message.isEmpty ? tr('(không có nội dung)') : t.message, style: body)),
            if (t.replyText != null && t.replyText!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                key: const ValueKey('agent-traffic-reply'),
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: pal.text.withValues(alpha: .04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(left: BorderSide(color: t.replyOk ? const Color(0xFF2E9D5B) : const Color(0xFFE5484D), width: 3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.reply_rounded, size: 16, color: t.replyOk ? const Color(0xFF2E9D5B) : const Color(0xFFE5484D)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          t.replyLabel ?? (t.replyOk ? tr('{0} trả lời', [t.replyWho ?? tr('Bên nhận')]) : tr('Không có trả lời')),
                          if (t.replyAt != null) hhmm(DateTime.fromMillisecondsSinceEpoch(t.replyAt!)),
                        ].join(' · '),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.sub),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  SelectionArea(child: MarkdownView(text: t.replyText!, style: body)),
                ]),
              ),
            ],
          ]),
        ),
      ),
      Divider(height: 1, color: pal.divider),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
        child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          TextButton(key: const ValueKey('agent-traffic-close'), onPressed: () => Navigator.pop(context), child: Text(tr('Đóng'))),
          TextButton.icon(
            onPressed: () {
              final all = [t.message, if (t.replyText != null && t.replyText!.isNotEmpty) '---\n${t.replyText}'].join('\n\n');
              Clipboard.setData(ClipboardData(text: all));
              ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã sao chép'))));
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(tr('Sao chép')),
          ),
          if (t.onStop != null)
            OutlinedButton.icon(
              key: const ValueKey('agent-traffic-stop'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE5484D), side: const BorderSide(color: Color(0xFFE5484D))),
              onPressed: () async {
                final nav = Navigator.of(context);
                await t.onStop!();
                nav.pop();
              },
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text(tr('Dừng')),
            ),
          if (user != null || t.openChannel != null)
            FilledButton.icon(
              key: const ValueKey('agent-traffic-open'),
              style: FilledButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white),
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                if (t.openChannel != null) {
                  openChatWith(nav.context, t.openChannel!);
                } else if (user != null) {
                  openDirectWith(nav.context, app, user);
                }
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(t.openChannel != null ? tr('Mở phiên') : tr('Mở cuộc chat với @{0}', [t.bot])),
            ),
        ]),
      ),
    ]);
  }
}
