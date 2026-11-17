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
                if (q.smartLeft != null) _row(pal, Icons.auto_awesome_rounded, tr('Lượt Kỹ hơn còn lại'), '${q.smartLeft}'),
                _row(pal, Icons.bolt_rounded, tr('Nhanh'), q.state == 'blocked' ? tr('Tạm dừng') : tr('Dùng thoải mái')),
                if (q.resetsAt != null) _row(pal, Icons.restart_alt_rounded, tr('Làm mới'), '${q.resetsAt!.day.toString().padLeft(2, '0')}/${q.resetsAt!.month.toString().padLeft(2, '0')} · 00:00'),
                const SizedBox(height: 16),
                Text(
                  switch (q.state) {
                    'warn' => tr('Bạn sắp dùng hết hạn mức tháng. Chế độ Nhanh vẫn dùng bình thường.'),
                    'degraded' => tr('Đã hết hạn mức: AI chuyển sang chế độ tiết kiệm (Nhanh) tới khi làm mới.'),
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
