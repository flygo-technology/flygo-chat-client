// Thêm loại biểu đồ cho Báo cáo (native, CustomPainter): cột nhóm / cột chồng, đồng hồ, phễu, thác nước, phân tán, bản đồ nhiệt,
// treemap, tiến độ theo mục. Cùng quy tắc với charts.dart: một trục, nét mảnh, khe 2px, màu theo thứ tự cố định, có chú thích.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'api.dart';
import 'charts.dart';

TextPainter _tp(String s, TextStyle st, {double max = 200}) => chartText(s, st, max: max);

/// Chú thích màu (luôn có khi ≥ 2 dãy).
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.names, required this.colors});
  final List<String> names;
  final List<Color> colors;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (var i = 0; i < names.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 5),
              Text(names[i], style: TextStyle(fontSize: 12, color: p.sub)),
            ],
          ),
      ],
    );
  }
}

/// Trục từ 0 với bước tròn (1, 2, 2,5, 5 × 10^n), khoảng 3–4 vạch.
({double max, double step}) _niceAxis(double top) {
  final step = _niceMax(top <= 0 ? 1 : top / 3);
  return (max: math.max(step, (top / step).ceil() * step), step: step);
}

double _niceMax(double v) {
  if (v <= 0) return 1;
  final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  return [1, 2, 2.5, 5, 10].map((m) => m * mag).firstWhere((s) => s >= v, orElse: () => 10 * mag);
}

// ---------------------------------------------------------------- cột nhóm / cột chồng
class MultiBarChart extends StatefulWidget {
  const MultiBarChart({super.key, required this.labels, required this.series, this.stacked = false, this.unit, this.height = 180});
  final List<String> labels;
  final List<({String name, List<double> values})> series;
  final bool stacked;
  final String? unit;
  final double height;
  @override
  State<MultiBarChart> createState() => _MultiBarChartState();
}

class _MultiBarChartState extends State<MultiBarChart> {
  int? _sel;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    final colors = [for (var i = 0; i < widget.series.length; i++) seriesColor(context, i)];
    return LayoutBuilder(
      builder: (context, c) {
        final painter = _MultiBarPainter(widget, colors, p, _sel);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTapDown: (d) => setState(() => _sel = painter.indexAt(d.localPosition.dx, c.maxWidth)),
              child: MouseRegion(
                onHover: (e) => setState(() => _sel = painter.indexAt(e.localPosition.dx, c.maxWidth)),
                onExit: (_) => setState(() => _sel = null),
                child: SizedBox(
                  width: c.maxWidth,
                  height: widget.height,
                  child: CustomPaint(painter: painter),
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (_sel != null)
              Text(
                '${widget.labels[_sel!]}: ${[for (final s in widget.series) '${s.name} ${fmtValue(s.values[_sel!], widget.unit)}'].join(' · ')}'
                '${widget.stacked ? ' · Tổng ${fmtValue(widget.series.fold<double>(0, (a, s) => a + s.values[_sel!]), widget.unit)}' : ''}',
                style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w500),
              )
            else
              ChartLegend(names: [for (final s in widget.series) s.name], colors: colors),
          ],
        );
      },
    );
  }
}

class _MultiBarPainter extends CustomPainter {
  _MultiBarPainter(this.w, this.colors, this.p, this.sel);
  final MultiBarChart w;
  final List<Color> colors;
  final Pal p;
  final int? sel;
  static const _l = 44.0, _r = 4.0, _t = 8.0, _b = 20.0;

  int? indexAt(double dx, double width) => w.labels.isEmpty ? null : ((dx - _l) / ((width - _l - _r) / w.labels.length)).floor().clamp(0, w.labels.length - 1);

  @override
  void paint(Canvas canvas, Size size) {
    final n = w.labels.length;
    if (n == 0) return;
    double top = 0, bottom = 0;
    for (var i = 0; i < n; i++) {
      if (w.stacked) {
        top = math.max(top, w.series.fold(0.0, (a, s) => a + s.values[i]));
      } else {
        for (final s in w.series) {
          top = math.max(top, s.values[i]);
          bottom = math.min(bottom, s.values[i]);
        }
      }
    }
    final ax = _niceAxis(math.max(top, -bottom));
    final hi = top <= 0 ? 0.0 : (top / ax.step).ceil() * ax.step, lo = bottom < 0 ? -(-bottom / ax.step).ceil() * ax.step : 0.0;
    double y(double v) => _t + (size.height - _t - _b) * (1 - (v - lo) / (hi - lo));
    final lab = TextStyle(fontSize: 10, color: p.sub);
    for (var t = lo; t <= hi + ax.step / 2; t += ax.step) {
      canvas.drawLine(Offset(_l, y(t)), Offset(size.width - _r, y(t)), Paint()..color = p.divider);
      final tp = _tp(fmtAxis(t, w.unit), lab, max: _l - 4);
      tp.paint(canvas, Offset(_l - 6 - tp.width, y(t) - tp.height / 2));
    }
    final gw = (size.width - _l - _r) / n;
    final every = math.max(1, (n / 7).ceil());
    for (var i = 0; i < n; i++) {
      final g0 = _l + i * gw + 3, g1 = _l + (i + 1) * gw - 3;
      final dim = sel != null && sel != i;
      if (w.stacked) {
        var acc = 0.0;
        for (var s = 0; s < w.series.length; s++) {
          final v = w.series[s].values[i];
          if (v <= 0) continue;
          final last = s == w.series.length - 1 || w.series.skip(s + 1).every((x) => x.values[i] <= 0);
          final r = RRect.fromRectAndCorners(
            Rect.fromLTRB(g0, y(acc + v) + (s == 0 ? 0 : 0), g1, y(acc) - (acc == 0 ? 0 : 2)),
            topLeft: last ? const Radius.circular(4) : Radius.zero,
            topRight: last ? const Radius.circular(4) : Radius.zero,
          );
          canvas.drawRRect(r, Paint()..color = dim ? colors[s].withValues(alpha: .4) : colors[s]);
          acc += v;
        }
      } else {
        final bw = (g1 - g0) / w.series.length;
        for (var s = 0; s < w.series.length; s++) {
          final v = w.series[s].values[i];
          final x0 = g0 + s * bw + 1, x1 = x0 + bw - 2;
          final rect = Rect.fromLTRB(x0, y(math.max(v, 0)), x1, math.max(y(math.min(v, 0)), y(math.max(v, 0)) + 1));
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: v >= 0 ? const Radius.circular(4) : Radius.zero,
              topRight: v >= 0 ? const Radius.circular(4) : Radius.zero,
              bottomLeft: v < 0 ? const Radius.circular(4) : Radius.zero,
              bottomRight: v < 0 ? const Radius.circular(4) : Radius.zero,
            ),
            Paint()..color = dim ? colors[s].withValues(alpha: .4) : colors[s],
          );
        }
      }
      if (i % every == 0 || i == n - 1) {
        final tp = _tp(w.labels[i], lab, max: math.max(gw * every, 30));
        tp.paint(canvas, Offset((g0 + (g1 - g0) / 2 - tp.width / 2).clamp(0.0, size.width - tp.width), size.height - tp.height));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MultiBarPainter o) => o.sel != sel || o.w != w || o.p != p;
}

// ---------------------------------------------------------------- đồng hồ
class GaugeChart extends StatelessWidget {
  const GaugeChart({super.key, required this.value, required this.max, this.min = 0, this.target, this.unit});
  final double value, max, min;
  final double? target;
  final String? unit;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    final frac = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Column(
      children: [
        SizedBox(
          height: 120,
          width: 220,
          child: CustomPaint(
            painter: _GaugePainter(frac, target == null ? null : ((target! - min) / (max - min)).clamp(0.0, 1.0), seriesColor(context, 0), p.surface2, p.text),
            child: Align(
              alignment: const Alignment(0, .75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(frac * 100).round()}%',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text),
                  ),
                  Text(fmtValue(value, unit), style: TextStyle(fontSize: 12.5, color: p.sub)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${fmtValue(min, unit)} – ${fmtValue(max, unit)}${target != null ? ' · mốc ${fmtValue(target!, unit)}' : ''}',
          style: TextStyle(fontSize: 12, color: p.sub),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.frac, this.target, this.color, this.track, this.ink);
  final double frac;
  final double? target;
  final Color color, track, ink;
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2, size.height) - 10;
    final c = Offset(size.width / 2, size.height - 6);
    final rect = Rect.fromCircle(center: c, radius: r);
    final st = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, st..color = track);
    if (frac > 0) canvas.drawArc(rect, math.pi, math.pi * frac, false, st..color = color);
    if (target != null) {
      final a = math.pi + math.pi * target!;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r - 12),
        c + Offset(math.cos(a), math.sin(a)) * (r + 12),
        Paint()
          ..color = ink
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) => o.frac != frac || o.target != target;
}

// ---------------------------------------------------------------- phễu
class FunnelChart extends StatelessWidget {
  const FunnelChart({super.key, required this.labels, required this.values, this.unit});
  final List<String> labels;
  final List<double> values;
  final String? unit;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    final mx = values.fold<double>(0, math.max);
    final color = seriesColor(context, 0);
    return Column(
      children: [
        for (var i = 0; i < values.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = mx == 0 ? 0.0 : math.max(96.0, c.maxWidth * values[i] / mx);
                return Column(
                  children: [
                    Container(
                      width: w,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Color.lerp(color, p.bg, i / (values.length + 1) * .7), borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        fmtValue(values[i], unit),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        '${labels[i]}${i > 0 && values[i - 1] != 0 ? '  ·  ${(values[i] / values[i - 1] * 100).round()}% bước trước' : ''}',
                        style: TextStyle(fontSize: 12, color: p.sub),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- thác nước
class WaterfallChart extends StatelessWidget {
  const WaterfallChart({super.key, required this.start, required this.labels, required this.values, this.unit, this.height = 190});
  final double start;
  final List<String> labels;
  final List<double> values;
  final String? unit;
  final double height;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final up = dark ? const Color(0xFF4CC47F) : const Color(0xFF1A8F4E), down = dark ? const Color(0xFFFF7A7A) : const Color(0xFFC62828);
    final end = values.fold<double>(start, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _WaterfallPainter(this, end, seriesColor(context, 0), up, down, p)),
        ),
        const SizedBox(height: 6),
        ChartLegend(names: const ['Đầu / cuối kỳ', 'Tăng', 'Giảm'], colors: [seriesColor(context, 0), up, down]),
      ],
    );
  }
}

class _WaterfallPainter extends CustomPainter {
  _WaterfallPainter(this.w, this.end, this.total, this.up, this.down, this.p);
  final WaterfallChart w;
  final double end;
  final Color total, up, down;
  final Pal p;
  static const _l = 44.0, _r = 4.0, _t = 16.0, _b = 20.0;
  @override
  void paint(Canvas canvas, Size size) {
    final steps = <({String label, double from, double to, Color c})>[(label: 'Đầu kỳ', from: 0, to: w.start, c: total)];
    var acc = w.start;
    for (var i = 0; i < w.values.length; i++) {
      steps.add((label: w.labels[i], from: acc, to: acc + w.values[i], c: w.values[i] >= 0 ? up : down));
      acc += w.values[i];
    }
    steps.add((label: 'Cuối kỳ', from: 0, to: end, c: total));
    // Cột đầu / cuối kỳ: vẽ từ đáy trục.
    final hiV = steps.fold<double>(0, (a, s) => math.max(a, math.max(s.from, s.to)));
    final loV = steps.fold<double>(0, (a, s) => math.min(a, math.min(s.from, s.to)));
    // Các khoản tăng/giảm nhỏ so với số dư: trục bắt đầu gần mức thấp nhất (cột đầu/cuối kỳ vẽ từ đáy trục) để thấy rõ thay đổi.
    final running = [
      for (final s in steps) ...[if (s.from != 0) s.from, s.to],
    ];
    final minRun = running.isEmpty ? 0.0 : running.reduce(math.min);
    final lo0 = loV < 0 ? loV : (minRun > hiV * .5 ? minRun * .9 : 0.0);
    final step = _niceMax((hiV - lo0) / 3);
    final lo = (lo0 / step).floor() * step, hi = (hiV / step).ceil() * step;
    double y(double v) => _t + (size.height - _t - _b) * (1 - (v - lo) / (hi - lo));
    final lab = TextStyle(fontSize: 10, color: p.sub);
    for (var t = lo; t <= hi + step / 2; t += step) {
      canvas.drawLine(Offset(_l, y(t)), Offset(size.width - _r, y(t)), Paint()..color = p.divider);
      final tp = _tp(fmtAxis(t, w.unit), lab, max: _l - 4);
      tp.paint(canvas, Offset(_l - 6 - tp.width, y(t) - tp.height / 2));
    }
    final bw = (size.width - _l - _r) / steps.length;
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final x0 = _l + i * bw + 2, x1 = x0 + bw - 4;
      final isTotal = i == 0 || i == steps.length - 1;
      final top = y(math.max(s.from, s.to)), bot = isTotal ? y(lo) : y(math.min(s.from, s.to));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x0, top, x1, math.max(bot, top + 1)), const Radius.circular(3)), Paint()..color = s.c);
      if (i < steps.length - 1) {
        final nextFrom = i == steps.length - 2 ? s.to : steps[i + 1].from;
        canvas.drawLine(
          Offset(x1, y(s.to)),
          Offset(x1 + 4, y(nextFrom)),
          Paint()
            ..color = p.sub.withValues(alpha: .6)
            ..strokeWidth = 1,
        );
      }
      if (i == 0 || i == steps.length - 1 || steps.length <= 8) {
        final v = i == 0 || i == steps.length - 1 ? s.to : s.to - s.from;
        final tv = _tp(
          '${(i > 0 && i < steps.length - 1 && v > 0) ? '+' : ''}${fmtAxis(v, w.unit)}',
          TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: p.text),
          max: bw + 20,
        );
        tv.paint(canvas, Offset(x0 + (x1 - x0) / 2 - tv.width / 2, top - tv.height - 1));
      }
      final tl = _tp(
        s.label,
        TextStyle(fontSize: steps.length > 6 ? 9 : 10, color: p.sub),
        max: bw - 1,
      );
      tl.paint(canvas, Offset((x0 + (x1 - x0) / 2 - tl.width / 2).clamp(0.0, size.width - tl.width), size.height - tl.height));
    }
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter o) => o.w != w || o.p != p;
}

// ---------------------------------------------------------------- phân tán
class ScatterChart extends StatefulWidget {
  const ScatterChart({super.key, required this.points, this.xLabel, this.yLabel, this.xUnit, this.yUnit, this.height = 200});
  final List<({double x, double y, String? label})> points;
  final String? xLabel, yLabel, xUnit, yUnit;
  final double height;
  @override
  State<ScatterChart> createState() => _ScatterChartState();
}

class _ScatterChartState extends State<ScatterChart> {
  int? _sel;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    return LayoutBuilder(
      builder: (context, c) {
        final painter = _ScatterPainter(widget, seriesColor(context, 0), p, _sel);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTapDown: (d) => setState(() => _sel = painter.nearest(d.localPosition, Size(c.maxWidth, widget.height))),
              child: SizedBox(
                width: c.maxWidth,
                height: widget.height,
                child: CustomPaint(painter: painter),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _sel == null
                  ? 'Ngang: ${widget.xLabel ?? 'x'} · Dọc: ${widget.yLabel ?? 'y'} · chạm vào điểm để xem'
                  : '${widget.points[_sel!].label ?? 'Điểm'}: ${widget.xLabel ?? 'x'} ${fmtValue(widget.points[_sel!].x, widget.xUnit)}, ${widget.yLabel ?? 'y'} ${fmtValue(widget.points[_sel!].y, widget.yUnit)}',
              style: TextStyle(fontSize: 12, color: _sel == null ? p.sub : p.text),
            ),
          ],
        );
      },
    );
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter(this.w, this.color, this.p, this.sel);
  final ScatterChart w;
  final Color color;
  final Pal p;
  final int? sel;
  static const _l = 44.0, _r = 8.0, _t = 8.0, _b = 20.0;
  ({double max, double step}) get _xa => _niceAxis(w.points.fold<double>(0, (a, b) => math.max(a, b.x)));
  ({double max, double step}) get _ya => _niceAxis(w.points.fold<double>(0, (a, b) => math.max(a, b.y)));
  double get _xMax => _xa.max;
  double get _yMax => _ya.max;
  Offset _pt(int i, Size s) => Offset(_l + (s.width - _l - _r) * w.points[i].x / _xMax, _t + (s.height - _t - _b) * (1 - w.points[i].y / _yMax));
  int? nearest(Offset o, Size s) {
    int? best;
    var bd = 24.0 * 24;
    for (var i = 0; i < w.points.length; i++) {
      final d = (_pt(i, s) - o).distanceSquared;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lab = TextStyle(fontSize: 10, color: p.sub);
    final ya = _ya, xa = _xa;
    for (var yv = 0.0; yv <= ya.max + ya.step / 2; yv += ya.step) {
      final yy = _t + (size.height - _t - _b) * (1 - yv / ya.max);
      canvas.drawLine(Offset(_l, yy), Offset(size.width - _r, yy), Paint()..color = p.divider);
      final tp = _tp(fmtAxis(yv, w.yUnit), lab, max: _l - 4);
      tp.paint(canvas, Offset(_l - 6 - tp.width, yy - tp.height / 2));
    }
    for (var xv = 0.0; xv <= xa.max + xa.step / 2; xv += xa.step) {
      final xx = _l + (size.width - _l - _r) * xv / xa.max;
      final tx = _tp(fmtAxis(xv, w.xUnit), lab, max: 60);
      tx.paint(canvas, Offset((xx - tx.width / 2).clamp(0.0, size.width - tx.width), size.height - tx.height));
    }
    for (var i = 0; i < w.points.length; i++) {
      final o = _pt(i, size);
      canvas.drawCircle(o, sel == i ? 7 : 5.5, Paint()..color = p.bg);
      canvas.drawCircle(o, sel == i ? 5.5 : 4, Paint()..color = sel == null || sel == i ? color : color.withValues(alpha: .4));
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter o) => o.sel != sel || o.w != w || o.p != p;
}

// ---------------------------------------------------------------- bản đồ nhiệt (một màu, nhạt → đậm)
class HeatmapChart extends StatefulWidget {
  const HeatmapChart({super.key, required this.x, required this.y, required this.matrix, this.unit});
  final List<String> x, y;
  final List<List<double>> matrix;
  final String? unit;
  @override
  State<HeatmapChart> createState() => _HeatmapChartState();
}

class _HeatmapChartState extends State<HeatmapChart> {
  (int, int)? _sel;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    final color = seriesColor(context, 0);
    final all = [for (final r in widget.matrix) ...r];
    final lo = all.isEmpty ? 0.0 : all.reduce(math.min), hi = all.isEmpty ? 1.0 : all.reduce(math.max);
    Color cell(double v) => Color.lerp(p.surface, color, hi == lo ? .6 : .12 + .88 * (v - lo) / (hi - lo))!;
    final lab = TextStyle(fontSize: 10.5, color: p.sub);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 64),
            for (final x in widget.x)
              Expanded(
                child: Text(x, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.clip, style: lab),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < widget.y.length; r++)
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(widget.y[r], maxLines: 1, overflow: TextOverflow.ellipsis, style: lab),
              ),
              for (var c = 0; c < widget.x.length; c++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _sel = (r, c)),
                    child: Container(
                      height: 26,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: cell(widget.matrix[r][c]),
                        borderRadius: BorderRadius.circular(3),
                        border: _sel == (r, c) ? Border.all(color: p.text, width: 1.5) : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              _sel == null
                  ? fmtValue(lo, widget.unit)
                  : '${widget.y[_sel!.$1]} · ${widget.x[_sel!.$2]}: ${fmtValue(widget.matrix[_sel!.$1][_sel!.$2], widget.unit)}',
              style: TextStyle(fontSize: 12, color: _sel == null ? p.sub : p.text, fontWeight: _sel == null ? null : FontWeight.w500),
            ),
            if (_sel == null) ...[
              const SizedBox(width: 6),
              Container(
                width: 80,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(colors: [cell(lo), cell(hi)]),
                ),
              ),
              const SizedBox(width: 6),
              Text(fmtValue(hi, widget.unit), style: TextStyle(fontSize: 12, color: p.sub)),
            ],
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- treemap (chia ô theo diện tích, kiểu squarified đơn giản)
class TreemapChart extends StatelessWidget {
  const TreemapChart({super.key, required this.labels, required this.values, this.unit, this.height = 200});
  final List<String> labels;
  final List<double> values;
  final String? unit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    final idx = [for (var i = 0; i < values.length; i++) i]..sort((a, b) => values[b].compareTo(values[a]));
    final total = values.fold<double>(0, (a, b) => a + b);
    return LayoutBuilder(
      builder: (context, c) {
        final rects = <(int, Rect)>[];
        _layout(idx, Rect.fromLTWH(0, 0, c.maxWidth, height), rects);
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              for (final (i, r) in rects)
                Positioned.fromRect(
                  rect: r.deflate(1),
                  child: Tooltip(
                    message: '${labels[i]}: ${fmtValue(values[i], unit)} (${total == 0 ? 0 : (values[i] / total * 100).round()}%)',
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: seriesColor(context, idx.indexOf(i) < 7 ? idx.indexOf(i) : 7).withValues(alpha: idx.indexOf(i) < 7 ? 1 : .5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: r.width > 54 && r.height > 30
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                                if (r.height > 44) Text(fmtValue(values[i], unit), maxLines: 1, style: const TextStyle(fontSize: 11, color: Colors.white)),
                              ],
                            )
                          : null,
                    ),
                  ),
                ),
              if (rects.isEmpty)
                Center(
                  child: Text('Không có dữ liệu', style: TextStyle(color: p.sub)),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Chia đôi theo tổng (slice-and-dice cân bằng): đủ đọc, không cần thuật toán squarified đầy đủ.
  void _layout(List<int> ids, Rect r, List<(int, Rect)> out) {
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      out.add((ids.first, r));
      return;
    }
    final total = ids.fold<double>(0, (a, i) => a + values[i]);
    if (total <= 0) return;
    var acc = 0.0, k = 0;
    while (k < ids.length - 1 && acc + values[ids[k]] <= total / 2) {
      acc += values[ids[k]];
      k++;
    }
    if (k == 0) {
      acc = values[ids[0]];
      k = 1;
    }
    final f = acc / total;
    final (a, b) = r.width >= r.height
        ? (Rect.fromLTWH(r.left, r.top, r.width * f, r.height), Rect.fromLTWH(r.left + r.width * f, r.top, r.width * (1 - f), r.height))
        : (Rect.fromLTWH(r.left, r.top, r.width, r.height * f), Rect.fromLTWH(r.left, r.top + r.height * f, r.width, r.height * (1 - f)));
    _layout(ids.sublist(0, k), a, out);
    _layout(ids.sublist(k), b, out);
  }
}

// ---------------------------------------------------------------- tiến độ theo mục (so kế hoạch)
class ProgressList extends StatelessWidget {
  const ProgressList({super.key, required this.items, this.unit});
  final List<({String label, double value, double target})> items;
  final String? unit;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    final color = seriesColor(context, 0);
    return Column(
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        it.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.text),
                      ),
                    ),
                    Text('${fmtValue(it.value, unit)} / ${fmtValue(it.target, unit)}', style: TextStyle(fontSize: 12, color: p.sub)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(it.value / it.target * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 8,
                  decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(4)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (it.value / it.target).clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
