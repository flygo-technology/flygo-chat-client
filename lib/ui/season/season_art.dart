import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hình vẽ mùa lễ (tự vẽ bằng Canvas, không dùng ảnh ngoài): hình nền chat, dây đèn, mũ Noel, hiệu ứng rơi.
/// Mọi painter nhận thời điểm [t] (giây) nên vừa chạy được bằng Ticker vừa vẽ được một khung cố định (ảnh xem trước).

/// Một hạt (tuyết / ánh đèn) sinh từ seed cố định để hình không nhảy khi vẽ lại.
class _Particle {
  final double x, y, r, speed, drift, phase, a;
  const _Particle(this.x, this.y, this.r, this.speed, this.drift, this.phase, this.a);
}

List<_Particle> _particles(int n, int seed, {double rMin = 1, double rMax = 3}) {
  final rnd = math.Random(seed);
  return [
    for (var i = 0; i < n; i++)
      _Particle(rnd.nextDouble(), rnd.nextDouble(), rMin + rnd.nextDouble() * (rMax - rMin), .025 + rnd.nextDouble() * .035,
          6 + rnd.nextDouble() * 14, rnd.nextDouble() * math.pi * 2, .45 + rnd.nextDouble() * .45),
  ];
}

/// Bông tuyết sáu cánh, mỗi cánh có hai nhánh nhỏ.
void drawSnowflake(Canvas c, Offset o, double r, Paint p, {double rot = 0}) {
  for (var k = 0; k < 6; k++) {
    final a = rot + k * math.pi / 3;
    final d = Offset(math.cos(a), math.sin(a));
    final tip = o + d * r;
    c.drawLine(o, tip, p);
    for (final s in [-1.0, 1.0]) {
      final b = a + s * math.pi / 4;
      final base = o + d * r * .55;
      c.drawLine(base, base + Offset(math.cos(b), math.sin(b)) * r * .32, p);
    }
  }
}

/// Rặng thông xa: một dãy cây ba tầng, đỉnh phủ tuyết nhẹ.
void _pines(Canvas c, Size s, double baseY, double h, Color body, Color snow, int seed) {
  final rnd = math.Random(seed);
  var x = -rnd.nextDouble() * 30;
  final p = Paint()..color = body;
  final sp = Paint()..color = snow;
  while (x < s.width + 30) {
    final th = h * (.6 + rnd.nextDouble() * .4), tw = th * (.42 + rnd.nextDouble() * .1);
    final top = baseY - th;
    for (var tier = 0; tier < 3; tier++) {
      final ty = top + th * tier * .26, by = top + th * (.42 + tier * .29), w = tw * (.5 + tier * .25);
      final path = Path()
        ..moveTo(x, ty)
        ..lineTo(x + w / 2, by)
        ..quadraticBezierTo(x, by - th * .04, x - w / 2, by)
        ..close();
      c.drawPath(path, p);
      if (tier == 0) {
        c.drawPath(
            Path()
              ..moveTo(x, ty)
              ..lineTo(x + w * .16, ty + th * .13)
              ..quadraticBezierTo(x, ty + th * .10, x - w * .16, ty + th * .13)
              ..close(),
            sp);
      }
    }
    c.drawRect(Rect.fromLTWH(x - tw * .05, top + th * .98, tw * .1, th * .06), p);
    x += tw * (.55 + rnd.nextDouble() * .6);
  }
}

void _snowfall(Canvas c, Size s, List<_Particle> ps, double t, Color color, {bool flakes = false, double alpha = 1}) {
  final p = Paint()..color = color;
  final lp = Paint()
    ..color = color
    ..strokeWidth = 1
    ..strokeCap = StrokeCap.round;
  for (final f in ps) {
    final y = ((f.y + t * f.speed) % 1.08 - .04) * s.height;
    final x = f.x * s.width + math.sin(t * .6 + f.phase) * f.drift;
    final a = f.a * alpha;
    if (flakes && f.r > 2.4) {
      lp.color = color.withValues(alpha: a);
      drawSnowflake(c, Offset(x, y), f.r * 1.8, lp, rot: f.phase + t * .2);
    } else {
      p.color = color.withValues(alpha: a);
      c.drawCircle(Offset(x, y), f.r, p);
    }
  }
}

/// "Đêm Noel": trời xanh đêm, đèn mờ (bokeh), rặng thông xa, tuyết rơi chậm.
class NoelNightPainter extends CustomPainter {
  final double t;
  NoelNightPainter(this.t);
  static final _snow = _particles(42, 11, rMin: .8, rMax: 2.6);
  static final _bokeh = _particles(16, 5, rMin: 14, rMax: 34);
  static const _bokehColors = [Color(0xFFFFC857), Color(0xFFFF6B6B), Color(0xFF7BDCB5), Color(0xFFFFE8A3), Color(0xFF8AB4FF)];

  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF07111F), Color(0xFF0C1E38), Color(0xFF14305A)],
            stops: [0, .55, 1],
          ).createShader(r));
    // Đèn mờ ở xa: vòng tròn nhòe, nhịp sáng rất chậm.
    for (var i = 0; i < _bokeh.length; i++) {
      final b = _bokeh[i];
      final pulse = .65 + .35 * math.sin(t * .5 + b.phase);
      c.drawCircle(
          Offset(b.x * s.width, (.08 + b.y * .62) * s.height),
          b.r,
          Paint()
            ..color = _bokehColors[i % _bokehColors.length].withValues(alpha: .10 * pulse)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.r * .45));
    }
    final ground = s.height * .985;
    _pines(c, s, ground - s.height * .05, math.min(150, s.height * .18), const Color(0xFF10264A), const Color(0x332E4A72), 3);
    _pines(c, s, ground, math.min(110, s.height * .13), const Color(0xFF0A1A33), const Color(0x40C8D8F0), 8);
    // Mặt tuyết dưới chân cây.
    c.drawPath(
        Path()
          ..moveTo(0, ground)
          ..quadraticBezierTo(s.width * .3, ground - 14, s.width * .6, ground - 4)
          ..quadraticBezierTo(s.width * .85, ground + 4, s.width, ground - 8)
          ..lineTo(s.width, s.height)
          ..lineTo(0, s.height)
          ..close(),
        Paint()..color = const Color(0xFF1E3A63));
    _snowfall(c, s, _snow, t, Colors.white, flakes: true, alpha: .8);
  }

  @override
  bool shouldRepaint(NoelNightPainter old) => old.t != t;
}

/// "Tuyết trắng": nền kem, bông tuyết mờ cố định + vài hạt tuyết rơi.
class WhiteSnowPainter extends CustomPainter {
  final double t;
  WhiteSnowPainter(this.t);
  static final _fall = _particles(30, 21, rMin: 1, rMax: 2.2);

  @override
  void paint(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFCF8F0), Color(0xFFF3EADB)],
          ).createShader(r));
    final lp = Paint()
      ..color = const Color(0xFF8FA6BF).withValues(alpha: .22)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    const cell = 92.0;
    final rnd = math.Random(4);
    for (double y = 0; y < s.height + cell; y += cell) {
      for (double x = 0; x < s.width + cell; x += cell) {
        final o = Offset(x + rnd.nextDouble() * cell * .6, y + rnd.nextDouble() * cell * .6);
        drawSnowflake(c, o, 7 + rnd.nextDouble() * 9, lp, rot: rnd.nextDouble());
      }
    }
    _snowfall(c, s, _fall, t, const Color(0xFF9DB4CC), alpha: .55);
  }

  @override
  bool shouldRepaint(WhiteSnowPainter old) => old.t != t;
}

/// Dây đèn Noel vắt ngang mép trên khung chat; từng bóng sáng dịu lên xuống lệch nhịp nhau.
class LightStringPainter extends CustomPainter {
  final double t;
  /// Cỡ bóng / nhịp dây (1 = cỡ ở khung chat).
  final double scale;
  LightStringPainter(this.t, {this.scale = 1});
  static const colors = [Color(0xFFFF4D4D), Color(0xFFFFC23D), Color(0xFF3DDC84), Color(0xFF4DA3FF), Color(0xFFFF7AD9)];

  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(scale);
    _paint(c, size / scale);
    c.restore();
  }

  void _paint(Canvas c, Size s) {
    const span = 96.0, sag = 9.0, top = 3.0;
    final n = math.max(1, (s.width / span).round());
    final w = s.width / n;
    final wire = Paint()
      ..color = const Color(0xFF2C3A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()..moveTo(0, top);
    for (var i = 0; i < n; i++) {
      path.quadraticBezierTo(w * i + w / 2, top + sag * 2, w * (i + 1), top);
    }
    c.drawPath(path, wire);
    // 4 bóng mỗi nhịp dây, treo theo đường cong.
    var k = 0;
    for (var i = 0; i < n; i++) {
      for (final f in [.14, .38, .62, .86]) {
        final x = w * (i + f);
        final y = top + sag * 2 * 2 * f * (1 - f); // điểm trên đường cong bậc hai
        final col = colors[k % colors.length];
        final glow = .55 + .45 * (.5 + .5 * math.sin(t * 1.6 + k * 1.9));
        final tilt = (f - .5) * .5;
        c.save();
        c.translate(x, y);
        c.rotate(-tilt);
        c.drawCircle(const Offset(0, 9), 9,
            Paint()
              ..color = col.withValues(alpha: .35 * glow)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-2.6, 0, 5.2, 4), const Radius.circular(1)), Paint()..color = const Color(0xFF3B4A3E));
        final bulb = Path()
          ..moveTo(-3.6, 4)
          ..cubicTo(-5.4, 9, -3.4, 15, 0, 15.5)
          ..cubicTo(3.4, 15, 5.4, 9, 3.6, 4)
          ..close();
        c.drawPath(bulb, Paint()..color = Color.lerp(col.withValues(alpha: 1), Colors.black, .35 * (1 - glow))!);
        c.drawCircle(const Offset(-1.3, 8), 1.2, Paint()..color = Colors.white.withValues(alpha: .55 * glow));
        c.restore();
        k++;
      }
    }
  }

  @override
  bool shouldRepaint(LightStringPainter old) => old.t != t || old.scale != scale;
}

/// Mũ Noel vẽ trong khung [size] (rộng ≈ 0.8 đường kính ảnh đại diện), đỉnh mũ rủ sang phải.
class SantaHatPainter extends CustomPainter {
  const SantaHatPainter();
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final body = Path()
      ..moveTo(w * .10, h * .80)
      ..cubicTo(w * .14, h * .38, w * .38, h * .04, w * .64, h * .04)
      ..quadraticBezierTo(w * .88, h * .05, w * .97, h * .34)
      ..quadraticBezierTo(w * .84, h * .20, w * .72, h * .28)
      ..cubicTo(w * .80, h * .46, w * .88, h * .62, w * .90, h * .80)
      ..close();
    final rect = Offset.zero & s;
    c.drawPath(
        body,
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFB71C1C)], begin: Alignment.topLeft, end: Alignment.bottomRight)
              .createShader(rect));
    // Nếp vải.
    c.drawPath(
        Path()
          ..moveTo(w * .40, h * .70)
          ..quadraticBezierTo(w * .44, h * .34, w * .62, h * .16),
        Paint()
          ..color = const Color(0x33000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .035
          ..strokeCap = StrokeCap.round);
    final fur = Paint()..color = const Color(0xFFFAFAFA);
    final shade = Paint()..color = const Color(0xFFE0E4EA);
    final band = RRect.fromRectAndRadius(Rect.fromLTWH(0, h * .70, w, h * .24), Radius.circular(h * .12));
    c.drawRRect(band.shift(Offset(0, h * .025)), shade);
    c.drawRRect(band, fur);
    for (var i = 0; i < 6; i++) {
      c.drawCircle(Offset(w * (.1 + i * .16), h * (.82 + (i.isEven ? -.03 : .03))), h * .06, shade);
    }
    c.drawCircle(Offset(w * .95, h * .38), h * .13, shade);
    c.drawCircle(Offset(w * .94, h * .36), h * .12, fur);
  }

  @override
  bool shouldRepaint(SantaHatPainter old) => false;
}

/// Ảnh đại diện đội mũ Noel: mũ đặt lệch phải, nghiêng nhẹ, ló ra ngoài vòng tròn.
class SantaHat extends StatelessWidget {
  final double size;
  final Widget child;
  final bool on;
  const SantaHat({super.key, required this.size, required this.child, this.on = true});
  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    return Stack(clipBehavior: Clip.none, children: [
      child,
      Positioned(
        left: size * .18,
        top: -size * .50,
        child: Transform.rotate(
          angle: .30,
          child: IgnorePointer(child: CustomPaint(size: Size(size * .84, size * .72), painter: const SantaHatPainter())),
        ),
      ),
    ]);
  }
}

/// Hiệu ứng toàn màn hình một lần (kiểu iMessage): [p] từ 0 đến 1 trong ~3 giây.
enum BurstKind { snow, gifts, mix }

class BurstPainter extends CustomPainter {
  final double p;
  final BurstKind kind;
  BurstPainter(this.p, this.kind);
  static final _items = _particles(28, 31, rMin: 7, rMax: 13);
  static const _giftColors = [
    (Color(0xFFE53935), Color(0xFFFFD54F)),
    (Color(0xFF2E7D32), Color(0xFFFFFFFF)),
    (Color(0xFF1E88E5), Color(0xFFFF8A80)),
    (Color(0xFFFFB300), Color(0xFFC62828)),
    (Color(0xFF8E24AA), Color(0xFFB9F6CA)),
  ];

  @override
  void paint(Canvas c, Size s) {
    final fade = p < .85 ? 1.0 : (1 - (p - .85) / .15);
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      final start = it.y * .45; // thả lệch nhau
      final q = ((p - start) / .55).clamp(0.0, 1.0);
      if (q <= 0) continue;
      final ease = q * q * (3 - 2 * q) * .55 + q * .45;
      final y = -40 + ease * (s.height + 80);
      final x = it.x * s.width + math.sin(q * 6 + it.phase) * it.drift * 1.6;
      final a = fade * (q < 1 ? 1.0 : 0.0);
      if (a <= 0) continue;
      if (kind == BurstKind.snow || (kind == BurstKind.mix && i.isEven)) {
        final lp = Paint()
          ..color = Colors.white.withValues(alpha: .9 * a)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        c.drawCircle(Offset(x, y), it.r * 1.1, Paint()..color = const Color(0xFF9EC9FF).withValues(alpha: .18 * a)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        drawSnowflake(c, Offset(x, y), it.r, lp, rot: it.phase + q * 3);
      } else {
        _gift(c, Offset(x, y), it.r * 1.5, _giftColors[i % _giftColors.length], it.phase + q * 4 * (i.isEven ? 1 : -1), a);
      }
    }
  }

  static void _gift(Canvas c, Offset o, double r, (Color, Color) col, double rot, double a) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(rot * .4);
    final box = Rect.fromCenter(center: Offset(0, r * .15), width: r * 1.6, height: r * 1.3);
    c.drawRRect(RRect.fromRectAndRadius(box.shift(const Offset(2, 3)), Radius.circular(r * .12)), Paint()..color = Colors.black.withValues(alpha: .18 * a));
    c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(r * .12)), Paint()..color = col.$1.withValues(alpha: a));
    final lid = Rect.fromCenter(center: Offset(0, -r * .5), width: r * 1.8, height: r * .42);
    c.drawRRect(RRect.fromRectAndRadius(lid, Radius.circular(r * .1)), Paint()..color = Color.lerp(col.$1, Colors.white, .12)!.withValues(alpha: a));
    final rb = Paint()..color = col.$2.withValues(alpha: a);
    c.drawRect(Rect.fromCenter(center: Offset(0, r * .05), width: r * .3, height: r * 1.75), rb);
    for (final sgn in [-1.0, 1.0]) {
      c.drawOval(Rect.fromCenter(center: Offset(sgn * r * .32, -r * .86), width: r * .62, height: r * .36), rb);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(BurstPainter old) => old.p != p || old.kind != kind;
}

/// Cây thông nhỏ cho banner Trang chủ.
class MiniTreePainter extends CustomPainter {
  final double t;
  MiniTreePainter([this.t = 0]);
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    c.drawRect(Rect.fromLTWH(w * .44, h * .82, w * .12, h * .16), Paint()..color = const Color(0xFF6D4C41));
    final g = Paint()..color = const Color(0xFF2E7D32);
    for (var i = 0; i < 3; i++) {
      final ty = h * (.08 + i * .2), by = h * (.42 + i * .2), hw = w * (.24 + i * .12);
      c.drawPath(
          Path()
            ..moveTo(w / 2, ty)
            ..lineTo(w / 2 + hw, by)
            ..lineTo(w / 2 - hw, by)
            ..close(),
          g);
    }
    // Ngôi sao trên đỉnh.
    final star = Path();
    for (var k = 0; k < 10; k++) {
      final rr = k.isEven ? w * .11 : w * .045;
      final a = -math.pi / 2 + k * math.pi / 5;
      final pt = Offset(w / 2 + math.cos(a) * rr, h * .08 + math.sin(a) * rr);
      k == 0 ? star.moveTo(pt.dx, pt.dy) : star.lineTo(pt.dx, pt.dy);
    }
    c.drawPath(star..close(), Paint()..color = const Color(0xFFFFD54F));
    const balls = [Offset(.40, .36), Offset(.60, .52), Offset(.36, .66), Offset(.64, .78), Offset(.50, .60)];
    for (var i = 0; i < balls.length; i++) {
      final on = .6 + .4 * math.sin(t * 1.6 + i * 2.1);
      c.drawCircle(Offset(balls[i].dx * w, balls[i].dy * h), w * .05,
          Paint()..color = Color.lerp(LightStringPainter.colors[i % 5], Colors.white, .15)!.withValues(alpha: on));
    }
  }

  @override
  bool shouldRepaint(MiniTreePainter old) => old.t != t;
}
