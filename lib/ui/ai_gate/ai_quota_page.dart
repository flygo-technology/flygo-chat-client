// "Hạn mức AI" của chính mình (Cá nhân): % đã dùng tháng/ngày, lượt "kỹ hơn" còn lại, ngày làm mới.
// Không hiện số tiền cho nhân viên (Sếp: người dùng chỉ thấy phần trăm).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'ai_admin_page.dart' show stateColor, stateLabel, usageBar, usageColor;
import 'ai_gate_api.dart';

class AiQuotaPage extends StatefulWidget {
  const AiQuotaPage({super.key, required this.api, this.initial});
  final AiGateApi api;
  final AiQuota? initial;
  @override
  State<AiQuotaPage> createState() => _AiQuotaPageState();
}

class _AiQuotaPageState extends State<AiQuotaPage> {
  AiQuota? _q;
  String? _error;

  @override
  void initState() {
    super.initState();
    _q = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await widget.api.myQuota();
      if (mounted) setState(() { _q = q; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final q = _q;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bg, foregroundColor: pal.text, title: Text(tr('Hạn mức AI'))),
      body: q == null
          ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: pal.sub))) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
                Center(child: AiQuotaRing(pct: q.usedPct, size: 180)),
                const SizedBox(height: 10),
                Center(child: Text(tr('Đã dùng {0}% hạn mức tháng', ['${q.usedPct}']), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text))),
                const SizedBox(height: 6),
                Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: stateColor(q.state).withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
                  child: Text('${stateLabel(q.state)} · ${tr('Hạng {0}', [q.tierName])}', style: TextStyle(color: stateColor(q.state), fontWeight: FontWeight.w600)),
                )),
                const SizedBox(height: 22),
                _row(pal, Icons.today_rounded, tr('Hôm nay'), '${q.dayPct}%', bar: q.dayPct),
                _row(pal, Icons.calendar_month_rounded, tr('Tháng này'), '${q.usedPct}%', bar: q.usedPct),
                if (q.smartLeft != null) _row(pal, Icons.auto_awesome_rounded, tr('Lượt Nâng cao còn lại'), '${q.smartLeft}'),
                _row(pal, Icons.bolt_rounded, tr('Mức Cơ bản'), q.state == 'blocked' ? tr('Tạm dừng') : tr('Dùng thoải mái')),
                if (q.resetsAt != null) _row(pal, Icons.restart_alt_rounded, tr('Làm mới'), '${q.resetsAt!.day.toString().padLeft(2, '0')}/${q.resetsAt!.month.toString().padLeft(2, '0')} · 00:00'),
                const SizedBox(height: 16),
                Text(
                  switch (q.state) {
                    'warn' => tr('Bạn sắp dùng hết hạn mức tháng. Mức Cơ bản vẫn dùng bình thường.'),
                    'degraded' => tr('Một model đã hết hạn mức: AI tự chuyển sang model rẻ hơn còn hạn mức tới khi làm mới.'),
                    'blocked' => tr('AI của bạn đang tạm dừng. Hãy nhờ quản lý cộng thêm hạn mức.'),
                    _ => tr('Hạn mức tính chung cho Dự án AI, Thư, Office, Báo cáo và Dịch.'),
                  },
                  style: TextStyle(color: pal.sub, height: 1.45),
                ),
              ]),
            ),
    );
  }

  Widget _row(Pal pal, IconData icon, String label, String value, {int? bar}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Row(children: [
            Icon(icon, size: 20, color: pal.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: pal.text))),
            Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
          ]),
          if (bar != null) ...[const SizedBox(height: 8), usageBar(pal, bar)],
        ]),
      );
}

/// Vòng tròn % đã dùng.
class AiQuotaRing extends StatelessWidget {
  const AiQuotaRing({super.key, required this.pct, this.size = 120});
  final int pct;
  final double size;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _Ring(pct: pct, color: usageColor(pal, pct), track: pal.surface2),
        child: Center(child: Text('$pct%', style: TextStyle(fontSize: size * .2, fontWeight: FontWeight.w800, color: pal.text))),
      ),
    );
  }
}

class _Ring extends CustomPainter {
  _Ring({required this.pct, required this.color, required this.track});
  final int pct;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width * .09;
    final r = Rect.fromLTWH(w / 2, w / 2, s.width - w, s.height - w);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = w);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * (pct.clamp(0, 100) / 100), false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_Ring o) => o.pct != pct || o.color != color;
}

/// Dung lượng AI công ty của mình, đặt trong trang Trợ lý (Sếp 2026-11-17: cột phải trên máy tính, thẻ gọn trên điện thoại).
/// Không hiện tiền. [compact] = một thẻ ngang: vòng % + hôm nay/tháng.
class AiUsageCard extends StatelessWidget {
  const AiUsageCard({super.key, required this.quota, this.compact = false, this.onRefresh});
  final AiQuota quota;
  final bool compact;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final q = quota;
    final reset = q.resetsAt == null ? '' : '${q.resetsAt!.day.toString().padLeft(2, '0')}/${q.resetsAt!.month.toString().padLeft(2, '0')}';
    Widget line(String label, int pct) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: pal.sub))),
              Text('$pct%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.text)),
            ]),
            const SizedBox(height: 5),
            usageBar(pal, pct, height: 6),
          ]),
        );
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: stateColor(q.state).withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
      child: Text('${stateLabel(q.state)} · ${q.tierName}', style: TextStyle(fontSize: 12, color: stateColor(q.state), fontWeight: FontWeight.w600)),
    );
    final title = Row(children: [
      Icon(Icons.data_usage_rounded, size: 18, color: pal.accent),
      const SizedBox(width: 8),
      Expanded(child: Text(tr('Dung lượng AI công ty'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
      if (onRefresh != null) IconButton(visualDensity: VisualDensity.compact, tooltip: tr('Tải lại'), onPressed: onRefresh, icon: Icon(Icons.refresh_rounded, size: 18, color: pal.sub)),
    ]);
    final note = Text(
      [
        if (q.smartLeft != null) tr('Còn {0} lượt Nâng cao', ['${q.smartLeft}']),
        if (reset.isNotEmpty) tr('Làm mới {0}', [reset]),
      ].join(' · '),
      style: TextStyle(fontSize: 12.5, color: pal.sub),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 14),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18)),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              Row(children: [
                AiQuotaRing(pct: q.usedPct, size: 76),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  chip,
                  const SizedBox(height: 4),
                  if (q.models.isNotEmpty) AiModelLines(quota: q, compact: true) else line(tr('Hôm nay'), q.dayPct),
                  note,
                ])),
                const SizedBox(width: 6),
              ]),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              const SizedBox(height: 8),
              Center(child: AiQuotaRing(pct: q.usedPct, size: 150)),
              const SizedBox(height: 10),
              Center(child: chip),
              const SizedBox(height: 12),
              if (q.models.isNotEmpty) AiModelLines(quota: q) else ...[line(tr('Hôm nay'), q.dayPct), line(tr('Tháng này'), q.usedPct)],
              const SizedBox(height: 6),
              note,
              const SizedBox(height: 10),
              Text(
                switch (q.state) {
                  'warn' => tr('Bạn sắp dùng hết hạn mức tháng. Mức Cơ bản vẫn dùng bình thường.'),
                  'degraded' => tr('Một model đã hết hạn mức: AI tự chuyển sang model rẻ hơn còn hạn mức tới khi làm mới.'),
                  'blocked' => tr('AI của bạn đang tạm dừng. Hãy nhờ quản lý cộng thêm hạn mức.'),
                  _ => tr('Tính chung cho Dự án AI, Thư, Office, Báo cáo và Dịch.'),
                },
                style: TextStyle(fontSize: 12.5, color: pal.sub, height: 1.4),
              ),
            ]),
    );
  }
}

/// % đã dùng của từng mức AI cho nhân viên (Sếp 2026-11-17: "Cơ bản: 20% · Nâng cao: còn 40%"), không bao giờ hiện tiền.
/// Model hạng không có thì ghi "không có"; model không có trần riêng thì ghi "theo hạn mức chung".
class AiModelLines extends StatelessWidget {
  const AiModelLines({super.key, required this.quota, this.compact = false});
  final AiQuota quota;
  final bool compact;

  static Color colorOf(String a) => switch (a) { 'flygo-fast' => const Color(0xFF6E8BFF), 'flygo-smart' => const Color(0xFFB69BFF), _ => const Color(0xFFE07BB0) };

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final ms = [...quota.models]..sort((a, b) => _rank(a.alias).compareTo(_rank(b.alias)));
    final shown = compact ? ms.where((m) => m.allowed).toList() : ms;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final m in shown)
        Padding(
          key: ValueKey('aim-${m.alias}'),
          padding: EdgeInsets.symmetric(vertical: compact ? 3 : 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: colorOf(m.alias), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(tr(aiModelName(m.alias)), style: TextStyle(fontSize: 13, color: pal.text))),
              Text(
                !m.allowed
                    ? tr('không có')
                    : m.usedPct == null
                        ? tr('theo hạn mức chung')
                        : m.exhausted
                            ? tr('hết · {0}%', ['${m.usedPct}'])
                            : tr('{0}% · còn {1}%', ['${m.usedPct}', '${math.max(0, 100 - m.usedPct!)}']),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: m.exhausted && m.allowed ? const Color(0xFFFF6B6B) : pal.sub),
              ),
            ]),
            if (m.allowed && m.usedPct != null) Padding(padding: const EdgeInsets.only(top: 4), child: usageBar(pal, m.usedPct!, height: compact ? 5 : 6)),
          ]),
        ),
    ]);
  }

  static int _rank(String a) => switch (a) { 'flygo-fast' => 0, 'flygo-smart' => 1, 'flygo-agent' => 2, _ => 3 };
}
