import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'season_art.dart' show drawPineRidge;

/// Bộ hình nền Giáng sinh "êm" (ít chi tiết, nhoè nhiều) để đặt sau tin nhắn. Tự vẽ, tĩnh; mỗi mẫu có hai bảng màu
/// sáng / tối và luôn giữ nền đủ đều để chữ hệ thống (ngày, tên) đọc rõ.
abstract class _Calm extends CustomPainter {
  final bool dark;
  const _Calm(this.dark);

  void bg(Canvas c, Size s, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter, List<double>? stops}) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = LinearGradient(begin: begin, end: end, colors: colors, stops: stops).createShader(r));
  }

  /// Vệt sáng nhoè (bokeh / mesh): hình tròn mờ biên.
  void blob(Canvas c, Offset o, double r, Color color, {double blur = .6}) =>
      c.drawCircle(o, r, Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * blur));

  /// Hạt nhiễu rất nhẹ cho bề mặt đỡ "phẳng nhựa".
  void grain(Canvas c, Size s, {double alpha = .035, int seed = 3}) {
    final rnd = math.Random(seed);
    final p = Paint();
    final n = (s.width * s.height / 900).round();
    for (var i = 0; i < n; i++) {
      p.color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(alpha: alpha * rnd.nextDouble());
      c.drawRect(Rect.fromLTWH(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height, 1, 1), p);
    }
  }

  @override
  bool shouldRepaint(_Calm old) => old.dark != dark;
}

/// 1. Tuyết êm: trời đêm xanh thẫm (sáng: kem), vài hạt tuyết to nhoè, thưa.
class SoftSnowPainter extends _Calm {
  const SoftSnowPainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    bg(c, s, dark ? const [Color(0xFF0B1630), Color(0xFF12254A)] : const [Color(0xFFFBF8F2), Color(0xFFEFF3F8)]);
    final rnd = math.Random(41);
    for (var i = 0; i < 34; i++) {
      final r = 1.8 + rnd.nextDouble() * 3.6;
      blob(c, Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height), r,
          (dark ? Colors.white : const Color(0xFF9DB2CC)).withValues(alpha: (dark ? .30 : .38) + rnd.nextDouble() * .2), blur: .8);
    }
    grain(c, s);
  }
}

/// 2. Ánh đèn: vài đốm đèn ấm thật to, thật nhoè, dồn về các góc (giữa màn để trống cho tin nhắn).
class WarmBokehPainter extends _Calm {
  const WarmBokehPainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    bg(c, s, dark ? const [Color(0xFF0E1428), Color(0xFF161A30)] : const [Color(0xFFFFF9F0), Color(0xFFFBF1E4)]);
    const spots = [(.08, .10, 70.0, 0), (.92, .06, 54.0, 1), (.98, .38, 80.0, 2), (.02, .55, 60.0, 1), (.90, .86, 90.0, 0), (.12, .94, 74.0, 2), (.55, .02, 40.0, 2)];
    final cols = dark
        ? const [Color(0xFFFFB547), Color(0xFFE5484D), Color(0xFFFFD98A)]
        : const [Color(0xFFFFC777), Color(0xFFF4A3A3), Color(0xFFFFE2A8)];
    for (final (x, y, r, k) in spots) {
      blob(c, Offset(x * s.width, y * s.height), r, cols[k].withValues(alpha: dark ? .34 : .46), blur: .5);
    }
    grain(c, s, alpha: .03);
  }
}

/// 3. Rừng thông: nền chuyển nhẹ, một hàng thông rất mờ sát đáy, sương phủ lên.
class PineEdgePainter extends _Calm {
  const PineEdgePainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    bg(c, s, dark ? const [Color(0xFF0C1A33), Color(0xFF10233F), Color(0xFF15304F)] : const [Color(0xFFF7F9FB), Color(0xFFEEF3F6), Color(0xFFE4ECF0)],
        stops: const [0, .7, 1]);
    final base = s.height;
    final h = math.min(130.0, s.height * .15);
    // Hai lớp thông: lớp xa nhạt hơn, lớp gần đậm hơn một chút; vẫn rất êm.
    drawPineRidge(c, s, base - h * .25, h * .9, dark ? const Color(0xFF172E4E) : const Color(0xFFD5E0E6), const Color(0x00000000), 3);
    drawPineRidge(c, s, base + 2, h * .7, dark ? const Color(0xFF1E3B60) : const Color(0xFFC3D3DC), const Color(0x00000000), 8);
    // Sương mù phủ lên hàng thông.
    final fog = Rect.fromLTWH(0, base - h * 1.5, s.width, h * 1.5);
    c.drawRect(
        fog,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
            (dark ? const Color(0xFF10233F) : const Color(0xFFEEF3F6)).withValues(alpha: 0),
            (dark ? const Color(0xFF10233F) : const Color(0xFFEEF3F6)).withValues(alpha: .55),
            (dark ? const Color(0xFF10233F) : const Color(0xFFEEF3F6)).withValues(alpha: .15),
          ], stops: const [0, .55, 1]).createShader(fog));
    grain(c, s);
  }
}

/// 4. Đỏ & xanh thông: chuyển chéo đỏ trầm sang xanh thông (sáng: hồng phấn sang bạc hà), vài bông tuyết viền mảnh.
class RedGreenPainter extends _Calm {
  const RedGreenPainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    bg(c, s, dark ? const [Color(0xFF3A1626), Color(0xFF161A2C), Color(0xFF10362C)] : const [Color(0xFFF9E4E6), Color(0xFFF7F7F5), Color(0xFFE2F2E9)],
        begin: Alignment.topLeft, end: Alignment.bottomRight);
    final p = Paint()
      ..color = (dark ? Colors.white : const Color(0xFF8AA3A0)).withValues(alpha: dark ? .10 : .22)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const flakes = [(.14, .12, 16.0), (.82, .20, 11.0), (.70, .52, 18.0), (.20, .70, 12.0), (.88, .84, 14.0), (.42, .92, 9.0)];
    for (final (x, y, r) in flakes) {
      final o = Offset(x * s.width, y * s.height);
      for (var k = 0; k < 6; k++) {
        final a = k * math.pi / 3;
        final d = Offset(math.cos(a), math.sin(a));
        c.drawLine(o, o + d * r, p);
        for (final sg in [-1.0, 1.0]) {
          final b = a + sg * math.pi / 4, m = o + d * r * .58;
          c.drawLine(m, m + Offset(math.cos(b), math.sin(b)) * r * .3, p);
        }
      }
    }
    grain(c, s);
  }
}

/// 5. Kính sương: các mảng màu lạnh nhoè sau lớp kính mờ, hạt sương li ti.
class FrostGlassPainter extends _Calm {
  const FrostGlassPainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    bg(c, s, dark ? const [Color(0xFF0E1A30), Color(0xFF0E1A30)] : const [Color(0xFFF2F6FA), Color(0xFFF2F6FA)]);
    final cols = dark
        ? const [Color(0xFF2E5C8A), Color(0xFF2B6E73), Color(0xFF3B4C8C)]
        : const [Color(0xFFCFE0F2), Color(0xFFD5EEEA), Color(0xFFE3DDF5)];
    blob(c, Offset(s.width * .1, s.height * .18), s.width * .55, cols[0].withValues(alpha: dark ? .8 : 1), blur: .5);
    blob(c, Offset(s.width * .95, s.height * .5), s.width * .6, cols[1].withValues(alpha: dark ? .7 : 1), blur: .5);
    blob(c, Offset(s.width * .3, s.height * .95), s.width * .5, cols[2].withValues(alpha: dark ? .7 : 1), blur: .5);
    // Lớp kính: phủ mờ đều + hạt sương.
    c.drawRect(Offset.zero & s, Paint()..color = (dark ? const Color(0xFF0B1426) : Colors.white).withValues(alpha: dark ? .25 : .2));
    grain(c, s, alpha: .06, seed: 9);
  }
}

/// 6. Ánh cửa sổ: vầng sáng ấm từ góc trên như đèn trong nhà hắt qua cửa kính, hơi sương đọng ở góc dưới.
class WindowGlowPainter extends _Calm {
  const WindowGlowPainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    bg(c, s, dark ? const [Color(0xFF151425), Color(0xFF0E1426)] : const [Color(0xFFFFF7EC), Color(0xFFF6F1EA)]);
    final glowR = math.max(s.width, s.height) * .75;
    final o = Offset(s.width * .85, -s.height * .05);
    c.drawCircle(
        o,
        glowR,
        Paint()
          ..shader = RadialGradient(colors: [
            (dark ? const Color(0xFFFFB45C) : const Color(0xFFFFD39A)).withValues(alpha: dark ? .32 : .55),
            (dark ? const Color(0xFFFFB45C) : const Color(0xFFFFD39A)).withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: o, radius: glowR)));
    // Hơi sương đọng ở hai góc dưới như mặt kính lạnh.
    blob(c, Offset(0, s.height), s.width * .45, (dark ? const Color(0xFF8FA8CC) : Colors.white).withValues(alpha: dark ? .10 : .6), blur: .6);
    blob(c, Offset(s.width, s.height * 1.02), s.width * .35, (dark ? const Color(0xFF8FA8CC) : Colors.white).withValues(alpha: dark ? .08 : .5), blur: .6);
    grain(c, s, alpha: .03);
  }
}

/// 7. Cực quang: một dải xanh lục / ngọc nhoè ngang trên cao, trời đêm êm.
class AuroraPainter extends _Calm {
  const AuroraPainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    bg(c, s, dark ? const [Color(0xFF07122A), Color(0xFF0D1C36)] : const [Color(0xFFF1F7F6), Color(0xFFF6F8FB)]);
    final band = Path()..moveTo(-40, s.height * .30);
    band.cubicTo(s.width * .3, s.height * .16, s.width * .6, s.height * .40, s.width + 40, s.height * .24);
    final pnt = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.height * .09
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.height * .05);
    pnt.color = (dark ? const Color(0xFF2BB58A) : const Color(0xFFA6E3D0)).withValues(alpha: dark ? .45 : .7);
    c.drawPath(band, pnt);
    pnt
      ..color = (dark ? const Color(0xFF3C7DD9) : const Color(0xFFC3D6F5)).withValues(alpha: dark ? .25 : .5)
      ..strokeWidth = s.height * .06;
    c.drawPath(band.shift(Offset(0, s.height * .07)), pnt);
    final rnd = math.Random(13);
    if (dark) {
      for (var i = 0; i < 30; i++) {
        c.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height * .6), .7 + rnd.nextDouble() * .6,
            Paint()..color = Colors.white.withValues(alpha: .15 + rnd.nextDouble() * .25));
      }
    }
    grain(c, s);
  }
}

/// 8. Đồi tuyết: hai lớp đồi tuyết thoai thoải ở phần dưới, trời trơn (sáng: trắng kem; tối: xanh xám ban đêm).
class SnowDriftPainter extends _Calm {
  const SnowDriftPainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    bg(c, s, dark ? const [Color(0xFF0D1830), Color(0xFF13233F)] : const [Color(0xFFF9FAFC), Color(0xFFF1F4F8)]);
    void hill(double y, double amp, Color col) {
      final p = Path()..moveTo(0, s.height * y);
      p.cubicTo(s.width * .3, s.height * (y - amp), s.width * .65, s.height * (y + amp * .6), s.width, s.height * (y - amp * .4));
      p
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close();
      c.drawPath(p, Paint()..color = col);
    }

    hill(.74, .05, dark ? const Color(0xFF182B4A) : const Color(0xFFE9EEF4));
    hill(.84, .04, dark ? const Color(0xFF1E3456) : const Color(0xFFFFFFFF));
    grain(c, s);
  }
}

/// 9. Giáng sinh (bản giản lược đề xuất thay bản hiện tại): giữ nền và rặng thông, bỏ đèn mờ, tuyết thưa và nhoè.
class XmasSimplePainter extends _Calm {
  const XmasSimplePainter(super.dark);
  @override
  void paint(Canvas c, Size s) {
    PineEdgePainter(dark).paint(c, s);
    final rnd = math.Random(77);
    for (var i = 0; i < 14; i++) {
      blob(c, Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height * .8), 1.6 + rnd.nextDouble() * 2,
          (dark ? Colors.white : const Color(0xFF9DB2CC)).withValues(alpha: dark ? .25 : .35), blur: .9);
    }
  }
}

/// Danh mục: (mã, tên, painter).
final calmXmasWallpapers = <(String, String, CustomPainter Function(bool dark))>[
  ('tuyetem', 'Tuyết êm', SoftSnowPainter.new),
  ('anhden', 'Ánh đèn', WarmBokehPainter.new),
  ('rungthong', 'Rừng thông', PineEdgePainter.new),
  ('dothong', 'Đỏ & xanh thông', RedGreenPainter.new),
  ('kinhsuong', 'Kính sương', FrostGlassPainter.new),
  ('cuaso', 'Ánh cửa sổ', WindowGlowPainter.new),
  ('cucquang', 'Cực quang', AuroraPainter.new),
  ('doituyet', 'Đồi tuyết', SnowDriftPainter.new),
];
