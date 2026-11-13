// Todo: màu thẻ, màu chữ / màu tô và hình nền (vẽ bằng code, không tải ảnh ngoài). Mỗi thứ có bản sáng và bản tối,
// chữ trên thẻ luôn đủ tương phản: nền sáng chữ đen, nền tối chữ trắng.
import 'dart:math';

import 'package:flutter/material.dart';

/// Màu thẻ (tên gửi máy chủ → (sáng, tối)). "default" = màu bề mặt của theme.
const kNoteColors = <String, (Color, Color)>{
  'default': (Color(0xFFFFFFFF), Color(0xFF202124)),
  'coral': (Color(0xFFFAAFA8), Color(0xFF77172E)),
  'peach': (Color(0xFFF39F76), Color(0xFF692B17)),
  'sand': (Color(0xFFFFF8B8), Color(0xFF7C4A03)),
  'mint': (Color(0xFFE2F6D3), Color(0xFF264D3B)),
  'sage': (Color(0xFFB4DDD3), Color(0xFF0C625D)),
  'fog': (Color(0xFFD4E4ED), Color(0xFF256377)),
  'storm': (Color(0xFFAECCDC), Color(0xFF284255)),
  'dusk': (Color(0xFFD3BFDB), Color(0xFF472E5B)),
  'blossom': (Color(0xFFF6E2DD), Color(0xFF6C394F)),
  'clay': (Color(0xFFE9E3D4), Color(0xFF4B443A)),
  'chalk': (Color(0xFFEFEFF1), Color(0xFF232427)),
};

const kNoteColorNames = <String, String>{
  'default': 'Mặc định',
  'coral': 'San hô',
  'peach': 'Đào',
  'sand': 'Cát',
  'mint': 'Bạc hà',
  'sage': 'Xô thơm',
  'fog': 'Sương',
  'storm': 'Bão',
  'dusk': 'Hoàng hôn',
  'blossom': 'Hoa',
  'clay': 'Đất sét',
  'chalk': 'Phấn',
};

/// Màu chữ / màu tô trong nội dung: (chữ trên nền sáng, chữ trên nền tối, tô sáng, tô tối).
const kTextColors = <String, (Color, Color, Color, Color)>{
  'red': (Color(0xFFC5221F), Color(0xFFFF8A80), Color(0xFFFFCDD2), Color(0xFF7A2323)),
  'orange': (Color(0xFFC25E00), Color(0xFFFFB74D), Color(0xFFFFE0B2), Color(0xFF7A4210)),
  'yellow': (Color(0xFF8D6E00), Color(0xFFFFE57F), Color(0xFFFFF59D), Color(0xFF6B5A0F)),
  'green': (Color(0xFF1E7E34), Color(0xFF81C995), Color(0xFFC8E6C9), Color(0xFF1F5130)),
  'teal': (Color(0xFF00796B), Color(0xFF64FFDA), Color(0xFFB2DFDB), Color(0xFF13504A)),
  'blue': (Color(0xFF1A5FD0), Color(0xFF8AB4F8), Color(0xFFBBDEFB), Color(0xFF1C3F72)),
  'purple': (Color(0xFF7B1FA2), Color(0xFFD7AEFB), Color(0xFFE1BEE7), Color(0xFF4F2463)),
  'pink': (Color(0xFFC2185B), Color(0xFFFF8BCB), Color(0xFFF8BBD0), Color(0xFF6E2241)),
  'brown': (Color(0xFF6D4C41), Color(0xFFD7B19D), Color(0xFFD7CCC8), Color(0xFF4E3B33)),
  'gray': (Color(0xFF5F6368), Color(0xFFBDC1C6), Color(0xFFE0E0E0), Color(0xFF3C4043)),
};

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

Color noteColor(String name, bool dark) {
  final c = kNoteColors[name] ?? kNoteColors['default']!;
  return dark ? c.$2 : c.$1;
}

// ------------------------------------------------------------ hình nền
/// Một hình nền: vẽ trên màu nền [base] (sáng / tối), hoạ tiết dùng màu [ink]. Nền gradient tự có màu, không dùng màu thẻ.
class TodoBg {
  const TodoBg(this.id, this.name, this.group, this.kind, {this.light = const [], this.dark = const [], this.ink, this.inkDark});
  final String id, name, group;
  /// Kiểu vẽ: dots, grid, lines, diagonal, waves, zigzag, circles, confetti, stars, leaves, hearts, bubbles, mountains, clouds,
  /// rain, plaid, triangles, hexagons, gradient (chỉ màu chuyển), sunrise, aurora.
  final String kind;
  /// Màu nền (2–3 màu: chuyển màu theo đường chéo). Rỗng = dùng màu thẻ.
  final List<Color> light, dark;
  final Color? ink, inkDark;

  bool get hasOwnColor => light.isNotEmpty;
  /// Nền đủ tối để chữ trắng (theo màu sáng nhất của bản đang dùng).
  bool darkText(bool dark) => !dark;
}

const kBackgrounds = <TodoBg>[
  // Hoạ tiết trên màu thẻ.
  TodoBg('dots', 'Chấm bi', 'Hoạ tiết', 'dots'),
  TodoBg('grid', 'Ô vuông', 'Hoạ tiết', 'grid'),
  TodoBg('lines', 'Giấy kẻ dòng', 'Hoạ tiết', 'lines'),
  TodoBg('diagonal', 'Sọc chéo', 'Hoạ tiết', 'diagonal'),
  TodoBg('waves', 'Sóng', 'Hoạ tiết', 'waves'),
  TodoBg('zigzag', 'Ziczac', 'Hoạ tiết', 'zigzag'),
  TodoBg('circles', 'Vòng tròn', 'Hoạ tiết', 'circles'),
  TodoBg('triangles', 'Tam giác', 'Hoạ tiết', 'triangles'),
  TodoBg('hexagons', 'Tổ ong', 'Hoạ tiết', 'hexagons'),
  TodoBg('plaid', 'Kẻ caro', 'Hoạ tiết', 'plaid'),
  // Minh hoạ.
  TodoBg('confetti', 'Hoa giấy', 'Minh hoạ', 'confetti', light: [Color(0xFFFFF4E6), Color(0xFFFDE7F3)], dark: [Color(0xFF2E2433), Color(0xFF3A2430)]),
  TodoBg('stars', 'Bầu trời sao', 'Minh hoạ', 'stars', light: [Color(0xFFE8EAF6), Color(0xFFD1D9FF)], dark: [Color(0xFF0D1B3E), Color(0xFF1B1446)],
      ink: Color(0xFF5C6BC0), inkDark: Color(0xFFFFF59D)),
  TodoBg('leaves', 'Lá xanh', 'Minh hoạ', 'leaves', light: [Color(0xFFEAF7E4), Color(0xFFD7EFCF)], dark: [Color(0xFF15301F), Color(0xFF1C3A26)],
      ink: Color(0xFF4CAF50), inkDark: Color(0xFF7BC67E)),
  TodoBg('hearts', 'Trái tim', 'Minh hoạ', 'hearts', light: [Color(0xFFFFEEF2), Color(0xFFFFDCE5)], dark: [Color(0xFF3B1A26), Color(0xFF451D2E)],
      ink: Color(0xFFE57399), inkDark: Color(0xFFFF8FB1)),
  TodoBg('bubbles', 'Bong bóng', 'Minh hoạ', 'bubbles', light: [Color(0xFFE3F4FD), Color(0xFFD0ECFA)], dark: [Color(0xFF0E2A3A), Color(0xFF123447)],
      ink: Color(0xFF4FA8D8), inkDark: Color(0xFF6CC3F0)),
  TodoBg('mountains', 'Núi', 'Minh hoạ', 'mountains', light: [Color(0xFFF1F6FB), Color(0xFFDCE8F3)], dark: [Color(0xFF17212D), Color(0xFF1F2C3B)],
      ink: Color(0xFF8FA9C4), inkDark: Color(0xFF4F6A86)),
  TodoBg('clouds', 'Mây', 'Minh hoạ', 'clouds', light: [Color(0xFFE6F2FF), Color(0xFFF7FBFF)], dark: [Color(0xFF1B2533), Color(0xFF222F40)],
      ink: Color(0xFFFFFFFF), inkDark: Color(0xFF3A4A5E)),
  TodoBg('rain', 'Mưa', 'Minh hoạ', 'rain', light: [Color(0xFFE8EEF3), Color(0xFFD9E3EB)], dark: [Color(0xFF151C24), Color(0xFF1C2630)],
      ink: Color(0xFF7D97AE), inkDark: Color(0xFF52708A)),
  TodoBg('sunrise', 'Bình minh', 'Minh hoạ', 'sunrise', light: [Color(0xFFFFF1E0), Color(0xFFFFD9C2)], dark: [Color(0xFF2B1A22), Color(0xFF3D2228)],
      ink: Color(0xFFFFB74D), inkDark: Color(0xFFE08A3C)),
  TodoBg('aurora', 'Cực quang', 'Minh hoạ', 'aurora', light: [Color(0xFFE6FFF7), Color(0xFFEDE7FF)], dark: [Color(0xFF0B1F24), Color(0xFF1A1433)],
      ink: Color(0xFF26C6A0), inkDark: Color(0xFF2EE6B8)),
  // Màu chuyển.
  TodoBg('g-sunset', 'Hoàng hôn', 'Màu chuyển', 'gradient', light: [Color(0xFFFFE0D2), Color(0xFFFFC9D9), Color(0xFFE9D5FF)],
      dark: [Color(0xFF5A2A2A), Color(0xFF5A2446), Color(0xFF3A2A5E)]),
  TodoBg('g-ocean', 'Đại dương', 'Màu chuyển', 'gradient', light: [Color(0xFFD6F5FF), Color(0xFFCFE3FF)], dark: [Color(0xFF0F3B4F), Color(0xFF1A2F5C)]),
  TodoBg('g-forest', 'Rừng', 'Màu chuyển', 'gradient', light: [Color(0xFFE1F7D5), Color(0xFFC8EBD9)], dark: [Color(0xFF1E3F26), Color(0xFF15403A)]),
  TodoBg('g-lavender', 'Oải hương', 'Màu chuyển', 'gradient', light: [Color(0xFFF1E6FF), Color(0xFFE0E7FF)], dark: [Color(0xFF3B2A5A), Color(0xFF2A3466)]),
  TodoBg('g-peach', 'Đào chín', 'Màu chuyển', 'gradient', light: [Color(0xFFFFF0D9), Color(0xFFFFDCC8)], dark: [Color(0xFF5C3A1C), Color(0xFF5A2E24)]),
  TodoBg('g-lemon', 'Chanh', 'Màu chuyển', 'gradient', light: [Color(0xFFFFFBD1), Color(0xFFE9F9C9)], dark: [Color(0xFF4F4A14), Color(0xFF34481C)]),
  TodoBg('g-rose', 'Hoa hồng', 'Màu chuyển', 'gradient', light: [Color(0xFFFFE3EA), Color(0xFFFFF1F0)], dark: [Color(0xFF5A2333), Color(0xFF4A2A30)]),
  TodoBg('g-night', 'Đêm', 'Màu chuyển', 'gradient', light: [Color(0xFFE3E8F0), Color(0xFFD5DCE8)], dark: [Color(0xFF141E30), Color(0xFF243B55)]),
];

TodoBg? bgById(String? id) => id == null ? null : kBackgrounds.where((b) => b.id == id).firstOrNull;

/// Nền của một thẻ / trang sửa: màu thẻ hoặc màu của hình nền, cộng hoạ tiết.
class NoteBackground extends StatelessWidget {
  const NoteBackground({super.key, required this.color, this.bg, required this.child, this.radius = 0, this.border});
  final String color;
  final String? bg;
  final Widget child;
  final double radius;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final spec = bgById(bg);
    final base = noteColor(color, dark);
    final colors = spec != null && spec.hasOwnColor ? (dark ? spec.dark : spec.light) : null;
    final ink = (dark ? spec?.inkDark : spec?.ink) ?? (dark ? Colors.white : Colors.black);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors == null ? base : null,
        gradient: colors == null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: spec == null || spec.kind == 'gradient'
            ? child
            : CustomPaint(painter: BgPainter(spec.kind, ink, dark: dark, custom: spec.ink != null), child: child),
      ),
    );
  }
}

/// Vẽ hoạ tiết. Hoạ tiết chung (trên màu thẻ) dùng mực đen / trắng rất nhạt để chữ vẫn rõ.
class BgPainter extends CustomPainter {
  BgPainter(this.kind, this.ink, {required this.dark, this.custom = false});
  final String kind;
  final Color ink;
  final bool dark, custom;

  @override
  void paint(Canvas canvas, Size size) {
    final a = custom ? (dark ? .28 : .35) : (dark ? .10 : .07);
    final p = Paint()..color = ink.withValues(alpha: a)..style = PaintingStyle.stroke..strokeWidth = 1.2..isAntiAlias = true;
    final fill = Paint()..color = ink.withValues(alpha: a);
    final r = Random(kind.hashCode);
    final w = size.width, h = size.height;
    switch (kind) {
      case 'dots':
        for (var y = 8.0; y < h; y += 16) {
          for (var x = (y ~/ 16).isEven ? 8.0 : 16.0; x < w; x += 16) {
            canvas.drawCircle(Offset(x, y), 1.8, fill);
          }
        }
      case 'grid':
        for (var x = 0.0; x < w; x += 18) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), p);
        }
        for (var y = 0.0; y < h; y += 18) {
          canvas.drawLine(Offset(0, y), Offset(w, y), p);
        }
      case 'lines':
        for (var y = 30.0; y < h; y += 26) {
          canvas.drawLine(Offset(0, y), Offset(w, y), p);
        }
        canvas.drawLine(const Offset(28, 0), Offset(28, h), Paint()..color = const Color(0xFFE57373).withValues(alpha: dark ? .3 : .45)..strokeWidth = 1.2);
      case 'diagonal':
        p.strokeWidth = 6;
        for (var x = -h; x < w; x += 22) {
          canvas.drawLine(Offset(x, h), Offset(x + h, 0), p);
        }
      case 'plaid':
        p.strokeWidth = 8;
        for (var x = 10.0; x < w; x += 40) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), p);
        }
        for (var y = 10.0; y < h; y += 40) {
          canvas.drawLine(Offset(0, y), Offset(w, y), p);
        }
        p.strokeWidth = 1;
        for (var x = 26.0; x < w; x += 40) {
          canvas.drawLine(Offset(x, 0), Offset(x, h), p);
        }
      case 'waves':
        p.strokeWidth = 1.6;
        for (var y = 14.0; y < h + 20; y += 22) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x < w; x += 40) {
            path.quadraticBezierTo(x + 10, y - 7, x + 20, y);
            path.quadraticBezierTo(x + 30, y + 7, x + 40, y);
          }
          canvas.drawPath(path, p);
        }
      case 'zigzag':
        p.strokeWidth = 1.6;
        for (var y = 14.0; y < h + 20; y += 20) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x < w; x += 16) {
            path.lineTo(x + 8, y - 6);
            path.lineTo(x + 16, y);
          }
          canvas.drawPath(path, p);
        }
      case 'circles':
        for (var y = 0.0; y < h + 40; y += 44) {
          for (var x = 0.0; x < w + 40; x += 44) {
            canvas.drawCircle(Offset(x + ((y ~/ 44).isEven ? 0 : 22), y), 16, p);
          }
        }
      case 'triangles':
        for (var y = 0.0; y < h + 30; y += 30) {
          for (var x = 0.0; x < w + 30; x += 30) {
            final o = (y ~/ 30).isEven ? 0.0 : 15.0;
            canvas.drawPath(Path()..moveTo(x + o, y + 22)..lineTo(x + o + 12, y + 2)..lineTo(x + o + 24, y + 22)..close(), p);
          }
        }
      case 'hexagons':
        const s = 14.0;
        final hh = s * sqrt(3);
        for (var y = 0.0; y < h + hh; y += hh) {
          for (var x = 0.0, i = 0; x < w + 3 * s; x += 1.5 * s, i++) {
            final cy = y + (i.isOdd ? hh / 2 : 0);
            final path = Path();
            for (var k = 0; k < 6; k++) {
              final ang = pi / 3 * k;
              final pt = Offset(x + s * cos(ang), cy + s * sin(ang));
              k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
            }
            canvas.drawPath(path..close(), p);
          }
        }
      case 'confetti':
        const cs = [Color(0xFFFF7043), Color(0xFF42A5F5), Color(0xFFFFCA28), Color(0xFF66BB6A), Color(0xFFAB47BC), Color(0xFFEC407A)];
        final n = (w * h / 1400).clamp(12, 220).toInt();
        for (var i = 0; i < n; i++) {
          final c = Paint()..color = cs[i % cs.length].withValues(alpha: dark ? .45 : .5);
          final o = Offset(r.nextDouble() * w, r.nextDouble() * h);
          canvas.save();
          canvas.translate(o.dx, o.dy);
          canvas.rotate(r.nextDouble() * pi);
          i.isEven ? canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -1.5, 8, 3), const Radius.circular(1)), c) : canvas.drawCircle(Offset.zero, 2.2, c);
          canvas.restore();
        }
      case 'stars':
        final n = (w * h / 1800).clamp(10, 160).toInt();
        for (var i = 0; i < n; i++) {
          final o = Offset(r.nextDouble() * w, r.nextDouble() * h);
          final s = 1.5 + r.nextDouble() * (i % 7 == 0 ? 4 : 2);
          _star(canvas, o, s, fill);
        }
      case 'leaves':
        for (var i = 0; i < (w * h / 4000).clamp(6, 70).toInt(); i++) {
          final o = Offset(r.nextDouble() * w, r.nextDouble() * h);
          canvas.save();
          canvas.translate(o.dx, o.dy);
          canvas.rotate(r.nextDouble() * 2 * pi);
          final s = 8 + r.nextDouble() * 10;
          final leaf = Path()..moveTo(0, -s)..quadraticBezierTo(s * .8, 0, 0, s)..quadraticBezierTo(-s * .8, 0, 0, -s);
          canvas.drawPath(leaf, fill);
          canvas.drawLine(Offset(0, -s), Offset(0, s), Paint()..color = ink.withValues(alpha: a * 1.6)..strokeWidth = .8);
          canvas.restore();
        }
      case 'hearts':
        for (var i = 0; i < (w * h / 3500).clamp(6, 90).toInt(); i++) {
          final o = Offset(r.nextDouble() * w, r.nextDouble() * h);
          final s = 5 + r.nextDouble() * 7;
          final heart = Path()
            ..moveTo(o.dx, o.dy + s * .9)
            ..cubicTo(o.dx - s * 1.4, o.dy - s * .1, o.dx - s * .6, o.dy - s * 1.1, o.dx, o.dy - s * .35)
            ..cubicTo(o.dx + s * .6, o.dy - s * 1.1, o.dx + s * 1.4, o.dy - s * .1, o.dx, o.dy + s * .9);
          canvas.drawPath(heart, fill);
        }
      case 'bubbles':
        for (var i = 0; i < (w * h / 3000).clamp(6, 90).toInt(); i++) {
          final o = Offset(r.nextDouble() * w, r.nextDouble() * h);
          final s = 3 + r.nextDouble() * 14;
          canvas.drawCircle(o, s, p);
          canvas.drawCircle(o.translate(-s * .35, -s * .35), s * .18, fill);
        }
      case 'mountains':
        final back = Paint()..color = ink.withValues(alpha: a * .7);
        canvas.drawPath(Path()..moveTo(0, h)..lineTo(0, h * .72)..lineTo(w * .22, h * .55)..lineTo(w * .45, h * .74)..lineTo(w * .7, h * .5)..lineTo(w, h * .7)..lineTo(w, h)..close(), back);
        canvas.drawPath(Path()..moveTo(0, h)..lineTo(0, h * .86)..lineTo(w * .3, h * .7)..lineTo(w * .55, h * .88)..lineTo(w * .8, h * .74)..lineTo(w, h * .84)..lineTo(w, h)..close(), fill);
        canvas.drawCircle(Offset(w * .8, h * .2), min(w, h) * .06, back);
      case 'clouds':
        final c = Paint()..color = ink.withValues(alpha: dark ? .5 : .85);
        for (var i = 0; i < (w * h / 16000).clamp(2, 14).toInt(); i++) {
          final o = Offset(r.nextDouble() * w, r.nextDouble() * h);
          final s = 10 + r.nextDouble() * 14;
          canvas.drawCircle(o, s, c);
          canvas.drawCircle(o.translate(s * .9, s * .25), s * .75, c);
          canvas.drawCircle(o.translate(-s * .9, s * .3), s * .65, c);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(o.dx - s * 1.5, o.dy, o.dx + s * 1.6, o.dy + s * .9), Radius.circular(s * .45)), c);
        }
      case 'rain':
        p.strokeWidth = 1.4;
        for (var i = 0; i < (w * h / 900).clamp(20, 400).toInt(); i++) {
          final o = Offset(r.nextDouble() * w, r.nextDouble() * h);
          canvas.drawLine(o, o.translate(-3, 10), p);
        }
      case 'sunrise':
        final sun = Offset(w * .82, h * .85);
        for (var k = 0; k < 12; k++) {
          final ang = pi + pi / 11 * k;
          canvas.drawLine(sun + Offset(cos(ang), sin(ang)) * 46, sun + Offset(cos(ang), sin(ang)) * (min(w, h) * .9), p..strokeWidth = 2);
        }
        canvas.drawCircle(sun, 36, fill..color = ink.withValues(alpha: dark ? .35 : .45));
      case 'aurora':
        for (var k = 0; k < 4; k++) {
          final path = Path()..moveTo(0, h * (.2 + k * .12));
          for (var x = 0.0; x <= w; x += 20) {
            path.lineTo(x, h * (.2 + k * .12) + sin(x / 60 + k) * 18);
          }
          canvas.drawPath(path, Paint()..color = ink.withValues(alpha: a * (1 - k * .18))..style = PaintingStyle.stroke..strokeWidth = 14 - k * 2.5..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        }
    }
  }

  void _star(Canvas c, Offset o, double s, Paint p) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final rr = k.isEven ? s : s * .45;
      final ang = -pi / 2 + pi / 5 * k;
      final pt = o + Offset(cos(ang), sin(ang)) * rr;
      k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    c.drawPath(path..close(), p);
  }

  @override
  bool shouldRepaint(BgPainter old) => old.kind != kind || old.ink != ink || old.dark != dark;
}

/// Hộp chọn màu thẻ + hình nền (như Keep: hai hàng tròn).
class LookPicker extends StatelessWidget {
  const LookPicker({super.key, required this.color, required this.bg, required this.onColor, required this.onBg});
  final String color;
  final String? bg;
  final ValueChanged<String> onColor;
  final ValueChanged<String?> onBg;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final sub = Theme.of(context).colorScheme.onSurface.withValues(alpha: .6);
    Widget dot({required bool on, required String tip, required Widget child, required VoidCallback tap, Color? fill}) => Tooltip(
          message: tip,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: tap,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill,
                border: Border.all(color: on ? const Color(0xFFA142F4) : sub.withValues(alpha: .35), width: on ? 2.4 : 1),
              ),
              child: ClipOval(child: Stack(fit: StackFit.expand, children: [child, if (on) const Center(child: Icon(Icons.check_rounded, size: 20, color: Color(0xFFA142F4)))])),
            ),
          ),
        );
    final groups = <String, List<TodoBg>>{};
    for (final b in kBackgrounds) {
      (groups[b.group] ??= []).add(b);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 2), child: Text('Màu', style: TextStyle(fontSize: 12, color: sub, fontWeight: FontWeight.w600))),
      Wrap(children: [
        for (final c in kNoteColors.keys)
          dot(
            on: color == c,
            tip: kNoteColorNames[c] ?? c,
            fill: noteColor(c, dark),
            tap: () => onColor(c),
            child: c == 'default' ? Icon(Icons.format_color_reset_outlined, size: 18, color: sub) : const SizedBox(),
          ),
      ]),
      for (final g in groups.entries) ...[
        Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 2), child: Text(g.key, style: TextStyle(fontSize: 12, color: sub, fontWeight: FontWeight.w600))),
        Wrap(children: [
          if (g.key == groups.keys.first) dot(on: bg == null, tip: 'Không có hình nền', tap: () => onBg(null), child: Icon(Icons.hide_image_outlined, size: 18, color: sub)),
          for (final b in g.value)
            dot(on: bg == b.id, tip: b.name, tap: () => onBg(b.id), child: NoteBackground(color: color, bg: b.id, child: const SizedBox.expand())),
        ]),
      ],
    ]);
  }
}
