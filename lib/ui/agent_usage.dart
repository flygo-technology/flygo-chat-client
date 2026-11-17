// Mức sử dụng của một trợ lý (trang / hộp chi tiết trợ lý): ngữ cảnh các phiên gần đây, hạn mức gói của tài khoản
// engine (Claude / Codex: phiên 5 giờ, hàng tuần) và chi phí AI công ty (Cổng AI) của trợ lý này cho mình.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../agent/agent_config.dart' show modelLabel;
import '../agent/agent_service.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'agent_view.dart';
import 'ai_gate/ai_gate_api.dart';
import 'ai_gate/ai_quota_page.dart' show AiModelLines;
import 'theme.dart';

/// Một phiên gần đây của trợ lý: cuộc trò chuyện, lúc chạy, ngữ cảnh đang dùng.
typedef AgentSessionUsage = ({String channelId, int at, int used, int max, String model});

/// Các phiên gần đây (đã tải trong app) mà lượt chạy mới nhất là của trợ lý [botId], mới nhất trước.
List<AgentSessionUsage> agentSessionsOf(AppState app, String botId, {int max = 3}) {
  final out = <AgentSessionUsage>[];
  for (final id in app.channels.keys) {
    for (final p in app.postsOf(id)) {
      if (agentRunOf(p) == null) continue;
      if (p.userId == botId) {
        final c = agentContextOf(app, id);
        if (c != null) out.add((channelId: id, at: p.createAt, used: c.used, max: c.max, model: c.model));
      }
      break;
    }
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out.take(max).toList();
}

/// Hạn mức gói của tài khoản engine mà trợ lý [botId] dùng: bản mới hơn giữa props của bot và thẻ tiến trình gần nhất.
AgentLimits? agentLimitsOfBot(AppState app, String botId) {
  AgentLimits? meta;
  final raw = (app.users[botId]?.raw['props'] as Map?)?['flygo_models'];
  try {
    final m = raw is String ? jsonDecode(raw) : raw;
    meta = AgentLimits.parse(m is Map ? m['limits'] : null);
  } catch (_) {}
  final s = agentSessionsOf(app, botId, max: 1);
  final card = s.isEmpty ? null : agentLimitsOf(app, s.first.channelId);
  if (card == null) return meta;
  if (meta == null) return card;
  return meta.at.isAfter(card.at) ? meta : card;
}

/// Dòng của trợ lý [bot] trong bảng mức dùng theo ứng dụng của Cổng AI (khoá là id bot, `bot:<username>` hoặc username).
Map<String, dynamic>? aiUsageRowOf(Map<String, dynamic>? usage, String period, AgentBot bot) {
  final rows = (usage?[period] as Map?)?['rows'] ?? usage?[period];
  if (rows is! List) return null;
  final keys = {bot.id, 'bot:${bot.id}', 'bot:${bot.username}', bot.username, 'agent:${bot.username}'};
  for (final r in rows) {
    if (r is Map && keys.contains('${r['k']}')) return r.cast<String, dynamic>();
  }
  return null;
}

String _tok(num n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)}M' : (n >= 1000 ? '${(n / 1000).round()}k' : '${n.round()}');

/// Mục "Mức sử dụng" của một trợ lý. [quota] / [usage] chỉ để xem trước / kiểm thử (không gọi Cổng AI).
class AgentUsageSection extends StatefulWidget {
  final AgentBot bot;
  final AiQuota? quota;
  final Map<String, dynamic>? usage;
  final DateTime? now;
  const AgentUsageSection({super.key, required this.bot, this.quota, this.usage, this.now});
  @override
  State<AgentUsageSection> createState() => _AgentUsageSectionState();
}

class _AgentUsageSectionState extends State<AgentUsageSection> {
  AiQuota? _quota;
  Map<String, dynamic>? _usage;

  @override
  void initState() {
    super.initState();
    _quota = widget.quota;
    _usage = widget.usage;
    if (widget.quota == null && widget.usage == null) _load();
  }

  Future<void> _load() async {
    try {
      final gate = await AiGateApi.current(context.read<AppState>().token);
      if (gate == null) return;
      final q = await gate.myQuota();
      final u = await gate.myUsage().catchError((_) => null);
      if (mounted) setState(() { _quota = q; _usage = u; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final now = widget.now ?? DateTime.now();
    final sessions = agentSessionsOf(app, widget.bot.id);
    final limits = agentLimitsOfBot(app, widget.bot.id);
    final day = aiUsageRowOf(_usage, 'day', widget.bot), month = aiUsageRowOf(_usage, 'month', widget.bot);
    final track = pal.text.withValues(alpha: .12);
    final note = TextStyle(fontSize: 12.5, color: pal.sub);
    Widget bar(double v, Color c) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(value: v.clamp(0.0, 1.0), minHeight: 6, borderRadius: BorderRadius.circular(3), backgroundColor: track, color: c),
        );
    Widget head(String t) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text, fontSize: 14.5)),
        );
    Widget line(String a, String b, {Color? color}) => Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontSize: 13.5, color: pal.text), overflow: TextOverflow.ellipsis)),
          Text(b, style: TextStyle(fontSize: 13.5, color: color ?? pal.sub, fontWeight: FontWeight.w600)),
        ]);
    final blocks = <Widget>[];

    // Ngữ cảnh các phiên gần đây.
    blocks.add(head(tr('Ngữ cảnh phiên gần đây')));
    if (sessions.isEmpty) {
      blocks.add(Text(tr('Chưa có số liệu: trợ lý gửi sau lượt chạy đầu tiên của phiên.'), style: note));
    }
    for (final s in sessions) {
      final f = s.used / s.max;
      final ch = app.channels[s.channelId];
      blocks.addAll([
        const SizedBox(height: 10),
        line(ch == null ? tr('Cuộc trò chuyện') : app.channelTitle(ch), tr('{0} / {1} token', [_tok(s.used), _tok(s.max)]),
            color: usageColor(f, pal.sub)),
        bar(f, usageColor(f, const Color(0xFF2E9D5B))),
        if (s.model.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(tr('Mô hình: {0}', [modelLabel(s.model)]), style: note)),
      ]);
    }

    // Hạn mức gói (tài khoản Claude / Codex của trợ lý).
    if (limits != null) {
      blocks.addAll([
        const SizedBox(height: 18),
        head(limits.plan != null && limits.plan!.isNotEmpty ? tr('Hạn mức gói {0}', [limits.plan]) : tr('Hạn mức gói của tài khoản trợ lý')),
        for (final w in limits.windows) ...[
          const SizedBox(height: 10),
          line(agentLimitLabel(w), tr('đã dùng {0}%', [w.usedAt(now)]), color: usageColor(w.usedAt(now) / 100, pal.sub)),
          bar(w.usedAt(now) / 100, usageColor(w.usedAt(now) / 100, pal.accent)),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(agentLimitLine(w, now), style: note)),
        ],
        if (limits.reached)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr('Tài khoản đã chạm hạn mức, chờ đến lúc đặt lại.'), style: const TextStyle(fontSize: 13, color: Color(0xFFE5484D))),
          ),
      ]);
    }

    // AI công ty (Cổng AI): trợ lý này dùng bao nhiêu cho mình, so với hạn mức của mình.
    final q = _quota;
    if (day != null || month != null) {
      final mUsd = (month?['usd'] as num?)?.toDouble() ?? 0, dUsd = (day?['usd'] as num?)?.toDouble() ?? 0;
      final pctMonth = q == null || q.monthUsd <= 0 ? null : mUsd / q.monthUsd;
      final pctDay = q == null || q.dayUsd <= 0 ? null : dUsd / q.dayUsd;
      String toks(Map<String, dynamic>? r) => r == null
          ? tr('chưa dùng')
          : tr('{0} lượt · {1} vào / {2} ra', ['${r['n'] ?? 0}', _tok((r['tok_in'] as num?) ?? 0), _tok((r['tok_out'] as num?) ?? 0)]);
      blocks.addAll([
        const SizedBox(height: 18),
        head(tr('AI công ty')),
        const SizedBox(height: 8),
        // Nhân viên không thấy tiền (như thẻ dung lượng AI): chỉ % hạn mức của mình và số token.
        line(tr('Hôm nay'), pctDay == null ? '' : tr('{0}% hạn mức ngày', [(pctDay * 100).round()])),
        if (pctDay != null) bar(pctDay, usageColor(pctDay, pal.accent)),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(toks(day), style: note)),
        const SizedBox(height: 10),
        line(tr('Tháng này'), pctMonth == null ? '' : tr('{0}% hạn mức tháng', [(pctMonth * 100).round()])),
        if (pctMonth != null) bar(pctMonth, usageColor(pctMonth, pal.accent)),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(toks(month), style: note)),
        if (q != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('Hạn mức của bạn ({0}): đã dùng {1}% tháng này, tính cả các ứng dụng khác.', [q.tierLabel, q.usedPct]), style: note),
          ),
        // Từng model (Sếp 2026-11-17): chỉ %, không tiền.
        if (q != null && q.models.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: AiModelLines(quota: q, compact: true)),
      ]);
    } else if (q != null && _usage != null) {
      blocks.addAll([
        const SizedBox(height: 18),
        head(tr('AI công ty')),
        Text(tr('Tháng này trợ lý chưa dùng AI công ty của bạn.'), style: note),
      ]);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks),
    );
  }
}
