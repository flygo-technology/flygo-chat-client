// Bảng tin: nền màu cho bài chữ ngắn (như "Chọn nền" của Facebook). Bài chỉ lưu mã nền (posts.bg); bảng nền nằm trong
// app, mã lạ (app cũ chưa biết) thì hiện chữ thường. Hoạ tiết vẽ bằng CustomPainter, không cần ảnh.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';

enum BgPattern { none, bubbles, hearts, bigHeart, confetti, dots, waves }

class BgSpec {
  const BgSpec(this.id, this.colors, {this.pattern = BgPattern.none, this.dark = false, this.begin = Alignment.topLeft, this.end = Alignment.bottomRight});
  final String id;
  final List<Color> colors;
  final BgPattern pattern;

  /// Nền sáng: chữ màu tối.
  final bool dark;
  final Alignment begin, end;

  Color get text => dark ? const Color(0xFF1F2333) : Colors.white;
}

const kBackgrounds = <BgSpec>[
  BgSpec('bubbles', [Color(0xFFA1C4FD), Color(0xFFF3C4F5)], pattern: BgPattern.bubbles, dark: true),
  BgSpec('ocean', [Color(0xFF2193B0), Color(0xFF6DD5ED)], pattern: BgPattern.waves),
  BgSpec('sand', [Color(0xFFE6D3B8), Color(0xFFF5E9DA)], pattern: BgPattern.waves, dark: true),
  BgSpec('wine', [Color(0xFF8E3A59), Color(0xFFD87C93)], pattern: BgPattern.waves),
  BgSpec('night', [Color(0xFF0F2027), Color(0xFF2C5364)], pattern: BgPattern.waves),
  BgSpec('cloud', [Color(0xFFBFC6CC), Color(0xFFE9ECEF)], pattern: BgPattern.bubbles, dark: true),
  BgSpec('sunset', [Color(0xFFFF5F6D), Color(0xFFFFC371)]),
  BgSpec('red', [Color(0xFFC0392B), Color(0xFFE74C3C)]),
  BgSpec('lime', [Color(0xFF9BE15D), Color(0xFFE2F27B)], dark: true),
  BgSpec('cream', [Color(0xFFFDF6EC), Color(0xFFF8EBDA)], pattern: BgPattern.dots, dark: true),
  BgSpec('lavender', [Color(0xFFB8B5F2), Color(0xFFCFCBF7)], pattern: BgPattern.bubbles, dark: true),
  BgSpec('mint', [Color(0xFFC6F1E7), Color(0xFFDDF7F0)], pattern: BgPattern.dots, dark: true),
  BgSpec('gold', [Color(0xFFF7B731), Color(0xFFF9D56E)]),
  BgSpec('bokeh', [Color(0xFF1A1A2E), Color(0xFF6B2D5C)], pattern: BgPattern.bubbles),
  BgSpec('aurora', [Color(0xFF00C9FF), Color(0xFFB06AB3), Color(0xFFFC5C7D)]),
  BgSpec('lilac', [Color(0xFFEDE4FB), Color(0xFFF5EFFD)], dark: true),
  BgSpec('hearts', [Color(0xFFFF6F61), Color(0xFFFF9A8B)], pattern: BgPattern.hearts),
  BgSpec('confetti', [Color(0xFFFFB347), Color(0xFFFFCC33)], pattern: BgPattern.confetti, dark: true),
  BgSpec('blush', [Color(0xFFF1E4E8), Color(0xFFFAF1F3)], pattern: BgPattern.hearts, dark: true),
  BgSpec('love', [Color(0xFF7F00FF), Color(0xFFE100FF), Color(0xFFFF6A00)], pattern: BgPattern.bigHeart, begin: Alignment.bottomLeft, end: Alignment.topRight),
];

BgSpec? bgById(String? id) => id == null ? null : kBackgrounds.where((b) => b.id == id).firstOrNull;

/// Số ký tự tối đa của bài trên nền màu (khớp server).
const kBgMaxChars = 300;

/// Nền [spec] (gradient + hoạ tiết) phủ kín [child].
class BgBox extends StatelessWidget {
  const BgBox({super.key, required this.spec, this.child, this.radius = 0});
  final BgSpec spec;
  final Widget? child;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(colors: spec.colors, begin: spec.begin, end: spec.end)),
          child: CustomPaint(painter: _PatternPainter(spec), child: child ?? const SizedBox.expand()),
        ),
      );
}

/// Chữ to, căn giữa trên nền (trong bảng tin và khi soạn).
class BgText extends StatelessWidget {
  const BgText({super.key, required this.spec, required this.text, this.radius = 0});
  final BgSpec spec;
  final String text;
  final double radius;

  static double fontSize(String t) => t.length <= 60 ? 28 : (t.length <= 130 ? 23 : 19);

  @override
  // Tỉ lệ 1.45 trên điện thoại; cột rộng (máy tính) thì giới hạn chiều cao để thẻ không quá to.
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: (box.maxWidth / 1.45).clamp(180.0, 340.0),
        child: BgBox(
          spec: spec,
          radius: radius,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: spec.text, fontSize: fontSize(text), fontWeight: FontWeight.w700, height: 1.3, shadows: [
                  if (!spec.dark) const Shadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 1)),
                ]),
              ),
            ),
          ),
        ),
      ));
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.spec);
  final BgSpec spec;

  static Path heart(Offset c, double s) {
    final p = Path()..moveTo(c.dx, c.dy + s * .35);
    p.cubicTo(c.dx - s * 1.1, c.dy - s * .35, c.dx - s * .45, c.dy - s * 1.05, c.dx, c.dy - s * .45);
    p.cubicTo(c.dx + s * .45, c.dy - s * 1.05, c.dx + s * 1.1, c.dy - s * .35, c.dx, c.dy + s * .35);
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final light = Paint()..color = Colors.white.withValues(alpha: spec.dark ? .45 : .16);
    switch (spec.pattern) {
      case BgPattern.none:
        break;
      case BgPattern.bubbles:
        for (final (x, y, r) in [(.18, .22, .30), (.86, .78, .26), (.92, .12, .14), (.08, .9, .12), (.55, 1.02, .2)]) {
          canvas.drawCircle(Offset(w * x, h * y), math.min(w, h) * r, light);
        }
      case BgPattern.waves:
        final p = Paint()
          ..color = Colors.white.withValues(alpha: spec.dark ? .35 : .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, w / 90);
        for (var i = 0; i < 4; i++) {
          final y0 = h * (.55 + i * .12);
          final path = Path()..moveTo(-10, y0);
          path.cubicTo(w * .3, y0 - h * .25, w * .6, y0 + h * .2, w + 10, y0 - h * .1);
          canvas.drawPath(path, p);
        }
      case BgPattern.hearts:
        final p = Paint()..color = Colors.white.withValues(alpha: spec.dark ? .9 : .28);
        final c = Paint()..color = (spec.dark ? const Color(0xFFE88AA0) : Colors.white).withValues(alpha: spec.dark ? .55 : .25);
        final s = math.min(w, h);
        for (final (x, y, r) in [(.1, .15, .07), (.88, .2, .09), (.15, .82, .08), (.82, .85, .06), (.5, .08, .04), (.95, .55, .05), (.04, .5, .045)]) {
          canvas.drawPath(heart(Offset(w * x, h * y), s * r), spec.dark ? c : p);
        }
      case BgPattern.bigHeart:
        final s = math.min(w, h);
        canvas.drawPath(heart(Offset(w / 2, h * .62), s * .55), Paint()..color = Colors.white.withValues(alpha: .18));
      case BgPattern.confetti:
        const colors = [Color(0xFFE74C3C), Color(0xFF8E44AD), Color(0xFF2980B9), Color(0xFF27AE60), Color(0xFFFFFFFF)];
        final rnd = math.Random(7);
        for (var i = 0; i < 46; i++) {
          final edge = i.isEven;
          final x = rnd.nextDouble() * w;
          final y = edge ? rnd.nextDouble() * h * .16 : h - rnd.nextDouble() * h * .16;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(rnd.nextDouble() * math.pi);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w / 70 + 2, height: w / 140 + 1), Paint()..color = colors[i % colors.length].withValues(alpha: .85));
          canvas.restore();
        }
      case BgPattern.dots:
        final p = Paint()..color = const Color(0xFF000000).withValues(alpha: .05);
        final step = math.max(14.0, w / 22);
        for (var y = step / 2; y < h; y += step) {
          for (var x = step / 2; x < w; x += step) {
            canvas.drawCircle(Offset(x, y), step / 9, p);
          }
        }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.spec != spec;
}

/// Hộp chọn nền. Trả về mã nền, '' = bỏ nền, null = đóng không chọn.
Future<String?> pickBackground(BuildContext context, {String? current}) => showDialog<String>(
      context: context,
      builder: (d) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: BackgroundPicker(current: current, onPick: (v) => Navigator.pop(d, v))),
      ),
    );

class BackgroundPicker extends StatelessWidget {
  const BackgroundPicker({super.key, this.current, required this.onPick});
  final String? current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget tile(Widget child, bool selected, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? pal.accent : Colors.transparent, width: 3),
            ),
            padding: const EdgeInsets.all(2),
            child: child,
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 8, 8),
        child: Row(children: [
          Expanded(child: Text(tr('Chọn nền'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text))),
          IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.maybePop(context)),
        ]),
      ),
      Divider(height: 1, color: pal.divider),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Text(tr('Trang trí'), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
      ),
      Flexible(
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            tile(
              Container(
                decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(11), border: Border.all(color: pal.divider)),
                alignment: Alignment.center,
                child: Text('Aa', style: TextStyle(fontWeight: FontWeight.w700, color: pal.sub, fontSize: 18)),
              ),
              current == null || current!.isEmpty,
              () => onPick(''),
            ),
            for (final b in kBackgrounds) tile(BgBox(spec: b, radius: 11), current == b.id, () => onPick(b.id)),
          ],
        ),
      ),
    ]);
  }
}
