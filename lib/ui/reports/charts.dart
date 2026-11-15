// Biểu đồ của Báo cáo, vẽ bằng CustomPainter (không thêm gói): đường, cột, cột ngang, tỉ trọng (vành khuyên), đường nhỏ.
// Một trục, nét mảnh, đầu cột bo 4px, khe 2px giữa các cột. Màu theo bảng phân loại đã kiểm (thứ tự cố định, không xoay vòng);
// dãy "kỳ trước" vẽ nét đứt xám. Chạm vào biểu đồ để xem giá trị (không chỉ dựa vào màu).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'api.dart';

/// Bảng phân loại 8 màu (sáng / tối), thứ tự cố định.
const _catLight = [
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
  Color(0xFF4A3AA7),
  Color(0xFFE34948),
];
const _catDark = [
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
  Color(0xFF9085E9),
  Color(0xFFE66767),
];
Color seriesColor(BuildContext context, int i) => (Theme.of(context).brightness == Brightness.dark ? _catDark : _catLight)[i % 8];
bool isPrevSeries(String name) => RegExp(r'(kỳ trước|cùng kỳ|tháng trước|tuần trước|năm trước|kế hoạch)', caseSensitive: false).hasMatch(name);

class _Axis {
  _Axis(double lo, double hi) {
    if (lo > 0) lo = 0;
    if (hi < 0) hi = 0;
    if (hi == lo) hi = lo + 1;
    final raw = (hi - lo) / 3;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1, 2, 2.5, 5, 10].map((m) => m * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
    min = (lo / step).floor() * step;
    max = (hi / step).ceil() * step;
    ticks = [for (var v = min; v <= max + step / 2; v += step) v];
  }
  late final double min, max;
  late final List<double> ticks;
}

/// Font chữ trong biểu đồ = font của theme (CustomPainter không tự kế thừa DefaultTextStyle).
String? chartFontFamily;
void syncChartFont(BuildContext context) =>
    chartFontFamily = DefaultTextStyle.of(context).style.fontFamily ?? Theme.of(context).textTheme.bodyMedium?.fontFamily;
TextPainter chartText(String s, TextStyle st, {double max = 200}) => TextPainter(
  text: TextSpan(
    text: s,
    style: st.copyWith(fontFamily: chartFontFamily),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
  ellipsis: '…',
)..layout(maxWidth: max);
TextPainter _tp(String s, TextStyle st, {double max = 200}) => chartText(s, st, max: max);

// ---------------------------------------------------------------- đường
class LineChart extends StatefulWidget {
  const LineChart({super.key, required this.x, required this.series, this.unit, this.height = 180, this.fill = false});
  final List<String> x;

  /// Biểu đồ vùng: tô dưới đường.
  final bool fill;
  final List<({String name, List<double> values})> series;
  final String? unit;
  final double height;
  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _hover;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    var ci = 0;
    final colors = [for (final s in widget.series) isPrevSeries(s.name) ? p.sub.withValues(alpha: .7) : seriesColor(context, ci++)];
    return LayoutBuilder(
      builder: (context, c) {
        final painter = _LinePainter(widget, colors, p, _hover);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTapDown: (d) => setState(() => _hover = painter.indexAt(d.localPosition.dx, c.maxWidth)),
              onHorizontalDragUpdate: (d) => setState(() => _hover = painter.indexAt(d.localPosition.dx, c.maxWidth)),
              child: MouseRegion(
                onHover: (e) => setState(() => _hover = painter.indexAt(e.localPosition.dx, c.maxWidth)),
                onExit: (_) => setState(() => _hover = null),
                child: SizedBox(
                  width: c.maxWidth,
                  height: widget.height,
                  child: CustomPaint(painter: painter),
                ),
              ),
            ),
            if (widget.series.length > 1 || _hover != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    if (_hover != null)
                      Text(
                        widget.x[_hover!],
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text),
                      ),
                    for (var i = 0; i < widget.series.length; i++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 14, height: 3, color: colors[i]),
                          const SizedBox(width: 5),
                          Text(
                            _hover == null ? widget.series[i].name : '${widget.series[i].name}: ${fmtValue(widget.series[i].values[_hover!], widget.unit)}',
                            style: TextStyle(fontSize: 12, color: p.sub),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.w, this.colors, this.p, this.hover);
  final LineChart w;
  final List<Color> colors;
  final Pal p;
  final int? hover;
  static const _l = 44.0, _r = 8.0, _t = 8.0, _b = 20.0;

  int? indexAt(double dx, double width) {
    final n = w.x.length;
    if (n < 2) return n == 1 ? 0 : null;
    return (((dx - _l) / (width - _l - _r)) * (n - 1)).round().clamp(0, n - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in w.series) ...s.values];
    if (all.isEmpty) return;
    final ax = _Axis(all.reduce(math.min), all.reduce(math.max));
    final n = w.x.length;
    double x(int i) => _l + (n < 2 ? 0 : i * (size.width - _l - _r) / (n - 1));
    double y(double v) => _t + (size.height - _t - _b) * (1 - (v - ax.min) / (ax.max - ax.min));
    final grid = Paint()
      ..color = p.divider
      ..strokeWidth = 1;
    final lab = TextStyle(fontSize: 10, color: p.sub);
    for (final t in ax.ticks) {
      canvas.drawLine(Offset(_l, y(t)), Offset(size.width - _r, y(t)), grid);
      final tp = _tp(fmtAxis(t, w.unit), lab, max: _l - 4);
      tp.paint(canvas, Offset(_l - 6 - tp.width, y(t) - tp.height / 2));
    }
    // Nhãn trục x: đầu, giữa, cuối (tránh chồng chữ).
    for (final i in {0, n ~/ 2, n - 1}) {
      if (i < 0 || i >= n) continue;
      final tp = _tp(w.x[i], lab, max: 80);
      final dx = (x(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, size.height - tp.height));
    }
    for (var s = w.series.length - 1; s >= 0; s--) {
      final v = w.series[s].values;
      final path = Path();
      for (var i = 0; i < v.length; i++) {
        i == 0 ? path.moveTo(x(i), y(v[i])) : path.lineTo(x(i), y(v[i]));
      }
      final paint = Paint()
        ..color = colors[s]
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      if (w.fill && !isPrevSeries(w.series[s].name) && v.isNotEmpty) {
        final area = Path.from(path)
          ..lineTo(x(v.length - 1), y(math.max(ax.min, 0)))
          ..lineTo(x(0), y(math.max(ax.min, 0)))
          ..close();
        canvas.drawPath(area, Paint()..color = colors[s].withValues(alpha: w.series.length > 1 ? .18 : .22));
      }
      if (isPrevSeries(w.series[s].name)) {
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 7) {
            canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
          }
        }
      } else {
        canvas.drawPath(path, paint);
        final last = v.length - 1;
        canvas.drawCircle(Offset(x(last), y(v[last])), 5, Paint()..color = p.bg);
        canvas.drawCircle(Offset(x(last), y(v[last])), 3.5, Paint()..color = colors[s]);
      }
    }
    if (hover != null) {
      canvas.drawLine(
        Offset(x(hover!), _t),
        Offset(x(hover!), size.height - _b),
        Paint()
          ..color = p.sub.withValues(alpha: .5)
          ..strokeWidth = 1,
      );
      for (var s = 0; s < w.series.length; s++) {
        canvas.drawCircle(Offset(x(hover!), y(w.series[s].values[hover!])), 4.5, Paint()..color = p.bg);
        canvas.drawCircle(Offset(x(hover!), y(w.series[s].values[hover!])), 3, Paint()..color = colors[s]);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter o) => o.hover != hover || o.w != w || o.p != p;
}

// ---------------------------------------------------------------- cột (dọc / ngang)
class BarChart extends StatefulWidget {
  const BarChart({super.key, required this.labels, required this.values, this.unit, this.highlight, this.horizontal = false, this.height = 170});
  final List<String> labels;
  final List<double> values;
  final String? unit;
  final int? highlight;
  final bool horizontal;
  final double height;
  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart> {
  int? _sel;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    syncChartFont(context);
    final color = seriesColor(context, 0);
    if (widget.horizontal) return _horizontal(context, p, color);
    return LayoutBuilder(
      builder: (context, c) {
        final painter = _BarPainter(widget, color, p, _sel);
        return GestureDetector(
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
        );
      },
    );
  }

  /// Cột ngang (xếp hạng): mỗi dòng một nhãn, thanh và số ghi thẳng (đọc được không cần màu).
  Widget _horizontal(BuildContext context, Pal p, Color color) {
    final max = widget.values.fold<double>(0, (a, b) => math.max(a, b.abs()));
    return Column(
      children: [
        for (var i = 0; i < widget.values.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    widget.labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.text),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 14,
                        width: max == 0 ? 0 : math.max(2, c.maxWidth * widget.values[i].abs() / max),
                        decoration: BoxDecoration(
                          color: widget.highlight == null || widget.highlight == i ? color : color.withValues(alpha: .45),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Text(
                    fmtValue(widget.values[i], widget.unit),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, color: p.text, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.w, this.color, this.p, this.sel);
  final BarChart w;
  final Color color;
  final Pal p;
  final int? sel;
  static const _l = 44.0, _r = 4.0, _t = 16.0, _b = 20.0;

  int? indexAt(double dx, double width) {
    final n = w.values.length;
    if (n == 0) return null;
    return ((dx - _l) / ((width - _l - _r) / n)).floor().clamp(0, n - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (w.values.isEmpty) return;
    final ax = _Axis(w.values.reduce(math.min), w.values.reduce(math.max));
    final n = w.values.length;
    final bw = (size.width - _l - _r) / n;
    double y(double v) => _t + (size.height - _t - _b) * (1 - (v - ax.min) / (ax.max - ax.min));
    final lab = TextStyle(fontSize: 10, color: p.sub);
    for (final t in ax.ticks) {
      canvas.drawLine(Offset(_l, y(t)), Offset(size.width - _r, y(t)), Paint()..color = p.divider);
      final tp = _tp(fmtAxis(t, w.unit), lab, max: _l - 4);
      tp.paint(canvas, Offset(_l - 6 - tp.width, y(t) - tp.height / 2));
    }
    final every = math.max(1, (n / 7).ceil()); // nhãn x thưa khi nhiều cột
    final shown = sel ?? w.highlight;
    for (var i = 0; i < n; i++) {
      final x0 = _l + i * bw + 1, x1 = x0 + bw - 2; // khe 2px
      final top = y(math.max(w.values[i], 0)), bottom = y(math.min(w.values[i], 0));
      final on = w.highlight == null || w.highlight == i || sel == i;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTRB(x0, top, x1, math.max(bottom, top + 1)),
        topLeft: w.values[i] >= 0 ? const Radius.circular(4) : Radius.zero,
        topRight: w.values[i] >= 0 ? const Radius.circular(4) : Radius.zero,
        bottomLeft: w.values[i] < 0 ? const Radius.circular(4) : Radius.zero,
        bottomRight: w.values[i] < 0 ? const Radius.circular(4) : Radius.zero,
      );
      canvas.drawRRect(r, Paint()..color = on ? color : color.withValues(alpha: .45));
      if (i % every == 0 || i == n - 1 || i == shown) {
        final tp = _tp(w.labels[i], lab, max: math.max(bw * every, 30));
        tp.paint(canvas, Offset((x0 + (x1 - x0) / 2 - tp.width / 2).clamp(0.0, size.width - tp.width), size.height - tp.height));
      }
    }
    if (shown != null && shown < n) {
      final x0 = _l + shown * bw;
      final tp = _tp(fmtValue(w.values[shown], w.unit), TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.text));
      tp.paint(canvas, Offset((x0 + bw / 2 - tp.width / 2).clamp(0.0, size.width - tp.width), y(math.max(w.values[shown], 0)) - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter o) => o.sel != sel || o.w != w || o.p != p;
}

// ---------------------------------------------------------------- tỉ trọng
class PieChart extends StatelessWidget {
  const PieChart({super.key, required this.labels, required this.values, this.unit});
  final List<String> labels;
  final List<double> values;
  final String? unit;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final total = values.fold<double>(0, (a, b) => a + b);
    final colors = [for (var i = 0; i < values.length; i++) seriesColor(context, i)];
    return Row(
      children: [
        SizedBox(width: 120, height: 120, child: CustomPaint(painter: _PiePainter(values, colors, p.bg))),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < values.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: p.text),
                        ),
                      ),
                      Text(
                        '${fmtValue(values[i], unit)} · ${total == 0 ? 0 : (values[i] / total * 100).round()}%',
                        style: TextStyle(fontSize: 12.5, color: p.sub),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.values, this.colors, this.gap);
  final List<double> values;
  final List<Color> colors;
  final Color gap;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    var a = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(
        rect,
        a,
        sweep,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20,
      );
      // Khe 2px giữa các phần.
      final e = Offset(rect.center.dx + math.cos(a) * rect.width / 2, rect.center.dy + math.sin(a) * rect.height / 2);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        e - dir * 11,
        e + dir * 11,
        Paint()
          ..color = gap
          ..strokeWidth = 2,
      );
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter o) => o.values != values;
}

// ---------------------------------------------------------------- đường nhỏ trong thẻ KPI
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.height = 30});
  final List<double> values;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _SparkPainter(values, seriesColor(context, 0), Pal.of(context).bg)),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.v, this.color, this.bg);
  final List<double> v;
  final Color color, bg;
  @override
  void paint(Canvas canvas, Size size) {
    if (v.length < 2) return;
    final lo = v.reduce(math.min), hi = v.reduce(math.max), span = hi == lo ? 1 : hi - lo;
    Offset pt(int i) => Offset(2 + i * (size.width - 8) / (v.length - 1), 3 + (size.height - 6) * (1 - (v[i] - lo) / span));
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < v.length; i++) {
      path.lineTo(pt(i).dx, pt(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(pt(v.length - 1), 4, Paint()..color = bg);
    canvas.drawCircle(pt(v.length - 1), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter o) => o.v != v;
}
