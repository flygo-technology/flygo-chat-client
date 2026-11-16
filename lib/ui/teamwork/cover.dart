// TeamWork: hình nền (cover) của dự án — màu trơn, màu chuyển (bộ có sẵn) hoặc hoạ tiết nhẹ trên màu dự án; app tự vẽ, không
// tải ảnh. Không đặt thì lấy màu chuyển nhạt từ màu dự án. Giao diện tối: làm tối bớt cho dịu mắt.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'look.dart';

class TwCover {
  const TwCover(this.kind, this.value, {this.pattern});
  final String kind; // color | gradient | pattern
  final String value; // '#RRGGBB' hoặc tên bộ màu chuyển
  final String? pattern;

  static TwCover? fromJson(Object? m) {
    if (m is! Map) return null;
    final kind = '${m['kind'] ?? ''}';
    if (!const ['color', 'gradient', 'pattern'].contains(kind)) return null;
    return TwCover(kind, '${m['value'] ?? ''}', pattern: m['pattern'] as String?);
  }

  Map<String, dynamic> toJson() => {'kind': kind, 'value': value, if (pattern != null) 'pattern': pattern};

  @override
  bool operator ==(Object other) => other is TwCover && other.kind == kind && other.value == value && other.pattern == pattern;
  @override
  int get hashCode => Object.hash(kind, value, pattern);
}

/// Bộ màu chuyển có sẵn (tên khớp máy chủ).
const kCoverGradients = <String, (Color, Color)>{
  'sunset': (Color(0xFFFF9A62), Color(0xFFE5484D)),
  'ocean': (Color(0xFF3AA0FF), Color(0xFF0E9F8E)),
  'forest': (Color(0xFF2B9348), Color(0xFF7FB800)),
  'violet': (Color(0xFF8E4EC6), Color(0xFF5B5BD6)),
  'dawn': (Color(0xFFFFC1A6), Color(0xFFD6409F)),
  'slate': (Color(0xFF5F6573), Color(0xFF9AA3B5)),
  'mint': (Color(0xFF7DE2C3), Color(0xFF2BA3A3)),
  'peach': (Color(0xFFFFD3A5), Color(0xFFFD6585)),
  'night': (Color(0xFF232A4D), Color(0xFF5B5BD6)),
  'sand': (Color(0xFFF6D365), Color(0xFFE8890C)),
};
const kCoverGradientNames = {'sunset': 'Hoàng hôn', 'ocean': 'Biển', 'forest': 'Rừng', 'violet': 'Tím', 'dawn': 'Bình minh', 'slate': 'Đá', 'mint': 'Bạc hà', 'peach': 'Đào', 'night': 'Đêm', 'sand': 'Cát'};
const kCoverPatterns = ['dots', 'grid', 'waves', 'diagonal', 'circles', 'triangles', 'plus', 'zigzag'];

/// Vẽ cover. [fallback]: màu dự án (cover null → màu chuyển nhạt từ màu này).
class TwCoverView extends StatelessWidget {
  const TwCoverView({super.key, required this.cover, required this.fallback, this.height, this.radius = BorderRadius.zero});
  final TwCover? cover;
  final Color fallback;
  final double? height;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final dark = twDark(context);
    final c = cover;
    Decoration deco;
    String? pattern;
    if (c == null) {
      final hsl = HSLColor.fromColor(fallback);
      deco = BoxDecoration(gradient: LinearGradient(colors: [hsl.withLightness((hsl.lightness + .22).clamp(0, .92)).toColor(), fallback], begin: Alignment.topLeft, end: Alignment.bottomRight));
    } else if (c.kind == 'gradient') {
      final g = kCoverGradients[c.value] ?? (fallback, fallback);
      deco = BoxDecoration(gradient: LinearGradient(colors: [g.$1, g.$2], begin: Alignment.topLeft, end: Alignment.bottomRight));
    } else {
      final base = c.value.startsWith('#') ? hexColor(c.value, fallback) : (kCoverGradients[c.value]?.$1 ?? fallback);
      deco = BoxDecoration(color: base);
      if (c.kind == 'pattern') pattern = c.pattern ?? 'dots';
    }
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        decoration: deco,
        foregroundDecoration: dark ? BoxDecoration(color: Colors.black.withValues(alpha: .28)) : null,
        child: pattern == null ? null : CustomPaint(painter: _PatternPainter(pattern), size: Size.infinite),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.kind);
  final String kind;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .22)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final f = Paint()..color = Colors.white.withValues(alpha: .22);
    const s = 14.0;
    switch (kind) {
      case 'dots':
        for (var y = s / 2; y < size.height; y += s) {
          for (var x = (y ~/ s).isOdd ? s : s / 2; x < size.width; x += s) {
            canvas.drawCircle(Offset(x, y), 1.8, f);
          }
        }
      case 'grid':
        for (var x = 0.0; x < size.width; x += s) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (var y = 0.0; y < size.height; y += s) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case 'waves':
        for (var y = 6.0; y < size.height + s; y += s) {
          final path = Path()..moveTo(0, y);
          for (var x = 0.0; x <= size.width; x += 4) {
            path.lineTo(x, y + math.sin(x / 10) * 3);
          }
          canvas.drawPath(path, p);
        }
      case 'diagonal':
        for (var x = -size.height; x < size.width; x += s) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
        }
      case 'circles':
        for (var y = 0.0; y < size.height + 20; y += 28) {
          for (var x = (y ~/ 28).isOdd ? 14.0 : 0.0; x < size.width + 20; x += 28) {
            canvas.drawCircle(Offset(x, y), 10, p);
          }
        }
      case 'triangles':
        for (var y = 0.0; y < size.height; y += s) {
          for (var x = (y ~/ s).isOdd ? s / 2 : 0.0; x < size.width; x += s) {
            canvas.drawPath(Path()..moveTo(x, y + s * .8)..lineTo(x + s / 2, y + s * .2)..lineTo(x + s, y + s * .8)..close(), p);
          }
        }
      case 'plus':
        for (var y = s / 2; y < size.height; y += s * 1.4) {
          for (var x = s / 2; x < size.width; x += s * 1.4) {
            canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), p);
            canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), p);
          }
        }
      default: // zigzag
        for (var y = 6.0; y < size.height + s; y += s) {
          final path = Path()..moveTo(0, y);
          var up = true;
          for (var x = 0.0; x <= size.width; x += 7) {
            path.lineTo(x, up ? y - 3 : y + 3);
            up = !up;
          }
          canvas.drawPath(path, p);
        }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.kind != kind;
}

/// Chọn hình nền: mặc định, màu trơn, màu chuyển, hoạ tiết (trên màu dự án).
class TwCoverPicker extends StatelessWidget {
  const TwCoverPicker({super.key, required this.cover, required this.projectColor, required this.onChanged});
  final TwCover? cover;
  final Color projectColor;
  final ValueChanged<TwCover?> onChanged;

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    Widget tile(String key, TwCover? c, {String? tip}) {
      final on = c == cover;
      return Tooltip(
        message: tip ?? '',
        child: InkWell(
          key: ValueKey('cover-$key'),
          onTap: () => onChanged(c),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 56,
            height: 36,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: on ? look.accent : look.divider, width: on ? 2.5 : 1)),
            padding: const EdgeInsets.all(2),
            child: TwCoverView(cover: c, fallback: projectColor, radius: BorderRadius.circular(6)),
          ),
        ),
      );
    }

    Widget group(String title, List<Widget> tiles) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 12, color: look.sub, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: tiles),
          ]),
        );
    final base = colorHex(projectColor);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      group('Mặc định', [tile('none', null, tip: 'Theo màu dự án')]),
      group('Màu trơn', [for (final c in kSwatches.take(10)) tile('color-$c', TwCover('color', c))]),
      group('Màu chuyển', [for (final e in kCoverGradientNames.entries.take(8)) tile('gradient-${e.key}', TwCover('gradient', e.key), tip: e.value)]),
      group('Hoạ tiết', [for (final p in kCoverPatterns.take(6)) tile('pattern-$p', TwCover('pattern', base, pattern: p))]),
    ]);
  }
}
