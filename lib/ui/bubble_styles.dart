import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'theme.dart';

/// Kiểu bong bóng (mỗi người chọn riêng cho từng chat): màu nền + hình trang trí ló ra ở mép bong bóng.
/// Người gửi lưu lựa chọn ở preferences `flygo_bubble/<id kênh>`; lúc gửi, tin mang props `flygo_bubble: {s, c}`
/// nên ai xem cũng thấy đúng kiểu của người gửi (app cũ bỏ qua props này).
///
/// Hình trang trí chỉ nằm ngoài bong bóng hoặc lấn vào mép tối đa ~5 px (phần đệm 7 px trên / dưới, 10–12 px hai bên)
/// nên không bao giờ đè chữ, link hay giờ gửi. Phần trên vẽ ở tin đầu của một lượt, phần dưới ở tin cuối lượt
/// (tin có cảm xúc thì bỏ phần dưới để không đụng chip cảm xúc).
class BubbleStyle {
  final String id;
  final String name;
  final Color color;
  /// Khoảng trống chừa phía trên (tin đầu lượt) và phía dưới (tin cuối lượt) cho hình trang trí.
  final double top, bottom;
  final BubbleDecoFn? _top, _bottom;
  const BubbleStyle(this.id, this.name, this.color, {this.top = 0, this.bottom = 0, BubbleDecoFn? paintTop, BubbleDecoFn? paintBottom})
      : _top = paintTop,
        _bottom = paintBottom;

  bool get decorated => _top != null || _bottom != null;
}

typedef BubbleDecoFn = void Function(Canvas c, Rect b, Color fill, double u);

/// Kiểu "chỉ đổi màu" (không hình trang trí).
const kBubblePlain = 'mau';

List<BubbleStyle> get bubbleStyles => [
      BubbleStyle(kBubblePlain, tr('Chỉ đổi màu'), const Color(0xFF1E88E5)),
      BubbleStyle('quockyvn', tr('Quốc kỳ'), const Color(0xFFC8102E), top: 18, paintTop: _flagVn),
      BubbleStyle('hoasen', tr('Hoa sen'), const Color(0xFFFCE4EC), bottom: 12, top: 10, paintTop: _lotusBud, paintBottom: _lotus),
      BubbleStyle('hoamai', tr('Hoa mai Tết'), const Color(0xFFFFF3C4), top: 12, bottom: 12, paintTop: _maiBranch, paintBottom: _luckyMoney),
      BubbleStyle('hoadao', tr('Hoa đào'), const Color(0xFFFFE4EC), top: 12, paintTop: _daoBranch),
      BubbleStyle('banhchung', tr('Bánh chưng'), const Color(0xFFDCEDC8), bottom: 12, paintBottom: _banhChung),
      BubbleStyle('denlong', tr('Đèn ông sao'), const Color(0xFFFFE0B2), top: 18, paintTop: _starLantern),
      BubbleStyle('caphe', tr('Cà phê phin'), const Color(0xFF6D4C41), bottom: 10, paintBottom: _phin),
      BubbleStyle('sotay', tr('Sổ tay'), const Color(0xFFFFFBE6), top: 6, bottom: 10, paintTop: _spiral, paintBottom: _pen),
      BubbleStyle('kepgiay', tr('Kẹp giấy'), const Color(0xFFE3F2FD), top: 12, paintTop: _clipAndPin),
      BubbleStyle('lich', tr('Hạn chót'), const Color(0xFFE8EAF6), top: 12, bottom: 10, paintTop: _calendar, paintBottom: _alarmClock),
      BubbleStyle('laptop', tr('Laptop'), const Color(0xFFECEFF1), top: 12, bottom: 14, paintTop: _wifi, paintBottom: _laptop),
      BubbleStyle('ytuong', tr('Ý tưởng'), const Color(0xFFFFF9C4), top: 16, bottom: 8, paintTop: _bulb, paintBottom: _sparkles),
      BubbleStyle('tenlua', tr('Khởi động'), const Color(0xFF3949AB), top: 16, bottom: 8, paintTop: _rocket, paintBottom: _nightStars),
      BubbleStyle('tangtruong', tr('Tăng trưởng'), const Color(0xFF2E7D32), bottom: 12, paintBottom: _barChart),
      BubbleStyle('thanhtich', tr('Thành tích'), const Color(0xFFFFE082), top: 16, bottom: 12, paintTop: _trophy, paintBottom: _medal),
      BubbleStyle('daduyet', tr('Đã duyệt'), const Color(0xFFFFFFFF), bottom: 16, paintBottom: _stamp),
      BubbleStyle('hoptac', tr('Hợp tác'), const Color(0xFFE1F5FE), top: 14, paintTop: _puzzle),
      BubbleStyle('baoho', tr('An toàn'), const Color(0xFF455A64), top: 10, bottom: 12, paintTop: _hardHat, paintBottom: _cone),
      BubbleStyle('thangmay', tr('Thang máy'), const Color(0xFFCFD8DC), top: 12, paintTop: _floorDisplay, paintBottom: _callPanel),
      BubbleStyle('vedich', tr('Về đích'), const Color(0xFF37474F), top: 18, paintTop: _finishFlag),
      BubbleStyle('phaohoa', tr('Chúc mừng'), const Color(0xFF311B92), top: 16, bottom: 8, paintTop: _fireworks, paintBottom: _confetti),
      BubbleStyle('sinhnhat', tr('Sinh nhật'), const Color(0xFFF8BBD0), top: 16, bottom: 12, paintTop: _balloons, paintBottom: _cake),
      BubbleStyle('cayxanh', tr('Cây xanh'), const Color(0xFFC8E6C9), bottom: 12, paintBottom: _plant),
      BubbleStyle('meo', tr('Mèo văn phòng'), const Color(0xFFFFCC80), top: 10, bottom: 8, paintTop: _catEars, paintBottom: _catPaws),
    ];

BubbleStyle? bubbleStyleById(String? id) => id == null ? null : bubbleStyles.where((s) => s.id == id).firstOrNull;

/// Màu gợi ý cho bảng chọn màu.
const bubbleSwatches = [
  Color(0xFF1E88E5), Color(0xFF3949AB), Color(0xFF5E35B1), Color(0xFF8E24AA), Color(0xFFD81B60), Color(0xFFC8102E),
  Color(0xFFF4511E), Color(0xFFFB8C00), Color(0xFFFFB300), Color(0xFFFDD835), Color(0xFF7CB342), Color(0xFF2E7D32),
  Color(0xFF00897B), Color(0xFF00ACC1), Color(0xFF6D4C41), Color(0xFF546E7A), Color(0xFF212121), Color(0xFFFFFFFF),
  Color(0xFFFCE4EC), Color(0xFFFFF3C4), Color(0xFFDCEDC8), Color(0xFFE3F2FD), Color(0xFFEDE7F6), Color(0xFFECEFF1),
];

String bubbleHex(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

Color? parseBubbleHex(String? s) {
  if (s == null) return null;
  final h = s.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
  return Color(0xFF000000 | int.parse(h, radix: 16));
}

/// Lựa chọn kiểu bong bóng: kiểu + màu nền (null = màu mặc định của kiểu).
class BubbleChoice {
  final String style;
  final Color? color;
  const BubbleChoice(this.style, [this.color]);

  BubbleStyle? get def => bubbleStyleById(style);
  Color get fill => color ?? def?.color ?? bubbleStyles.first.color;

  Map<String, dynamic> toJson() => {'s': style, if (color != null && color != def?.color) 'c': bubbleHex(color!)};

  static BubbleChoice? fromJson(Object? v) {
    if (v is! Map) return null;
    final s = v['s'];
    final c = parseBubbleHex(v['c'] as String?);
    // Kiểu lạ (app mới hơn thêm kiểu): vẫn giữ màu, không hình trang trí.
    if (s is! String || s.isEmpty) return null;
    if (bubbleStyleById(s) == null) return c == null ? null : BubbleChoice(kBubblePlain, c);
    return BubbleChoice(s, c);
  }

  @override
  bool operator ==(Object other) => other is BubbleChoice && other.style == style && other.fill == fill;
  @override
  int get hashCode => Object.hash(style, fill);
}

/// Kiểu bong bóng gắn trên tin (props.flygo_bubble).
BubbleChoice? bubbleOfProps(Map<String, dynamic> props) => BubbleChoice.fromJson(props['flygo_bubble']);

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

/// Màu chữ trên nền [fill]: trắng nếu đủ tương phản 4.5:1, không thì gần đen (luôn đạt ≥ 4.5:1).
Color bubbleTextOn(Color fill) {
  if (_contrast(Colors.white, fill) >= 4.5) return Colors.white;
  const ink = Color(0xFF111111);
  return _contrast(ink, fill) >= 4.5 ? ink : Colors.black;
}

/// Bảng màu cho nội dung trong bong bóng có nền [fill] (chữ, link, trích dẫn, dấu đã xem).
Pal bubblePal(Pal p, Color fill) {
  final fg = bubbleTextOn(fill);
  final light = fg == Colors.white;
  return Pal(
    bg: p.bg,
    surface: p.surface,
    surface2: p.surface2,
    text: fg,
    sub: fg.withValues(alpha: .78),
    divider: fg.withValues(alpha: .22),
    accent: p.accent,
    // Link trong bong bóng: cùng màu chữ (gạch chân) để luôn đủ tương phản trên mọi màu nền.
    accentText: fg,
    chipSelBg: p.chipSelBg,
    chipSelFg: p.chipSelFg,
    outBubble: fill,
    inBubble: fill,
    quoteOut: Color.alphaBlend(fg.withValues(alpha: .1), fill),
    quoteIn: Color.alphaBlend(fg.withValues(alpha: .1), fill),
    quoteBar: fg.withValues(alpha: light ? .85 : .6),
    tick: fg,
    chatBg: p.chatBg,
    doodle: p.doodle,
    avatarBg: p.avatarBg,
    avatarFg: p.avatarFg,
    glass: p.glass,
    threadBg: p.threadBg,
  );
}

/// Vẽ hình trang trí quanh bong bóng (vẽ tràn ra ngoài khung của widget, không chiếm chỗ bố cục).
class BubbleDecoPainter extends CustomPainter {
  final BubbleStyle style;
  final Color fill;
  final bool top, bottom;
  final double scale;
  const BubbleDecoPainter({required this.style, required this.fill, this.top = true, this.bottom = true, this.scale = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final b = Offset.zero & size;
    if (top) style._top?.call(canvas, b, fill, scale);
    if (bottom) style._bottom?.call(canvas, b, fill, scale);
  }

  @override
  bool shouldRepaint(BubbleDecoPainter o) =>
      o.style.id != style.id || o.fill != fill || o.top != top || o.bottom != bottom || o.scale != scale;
}

// ------------------------------------------------------------------------------------------------ nét vẽ chung

const _ink = Color(0xFF3E2C28);

Paint _f(Color c) => Paint()..color = c..isAntiAlias = true;
Paint _s(double u, [Color c = _ink, double w = 1.1]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w * u
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// Tô [path] rồi viền mực.
void _draw(Canvas c, Path p, Color fill, double u, {double w = 1.1}) {
  c.drawPath(p, _f(fill));
  c.drawPath(p, _s(u, _ink, w));
}

Path _rr(Rect r, double rad) => Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(rad)));
Path _oval(Offset o, double rx, double ry) => Path()..addOval(Rect.fromCenter(center: o, width: rx * 2, height: ry * 2));

/// Ngôi sao năm cánh đều, cánh trên hướng thẳng lên (tỉ lệ bán kính trong / ngoài chuẩn 0.382).
Path _star(Offset o, double r, {double inner = .382, double rot = 0}) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * inner;
    final a = -math.pi / 2 + rot + i * math.pi / 5;
    final pt = o + Offset(math.cos(a) * rr, math.sin(a) * rr);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

/// Sao lấp lánh bốn cánh.
Path _sparkle(Offset o, double r) => Path()
  ..moveTo(o.dx, o.dy - r)
  ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
  ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
  ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
  ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
  ..close();

/// Bông hoa [n] cánh tròn.
void _flower(Canvas c, Offset o, double r, Color petal, Color heart, double u, {int n = 5, double rot = 0}) {
  for (var i = 0; i < n; i++) {
    final a = rot + i * 2 * math.pi / n - math.pi / 2;
    _draw(c, _oval(o + Offset(math.cos(a), math.sin(a)) * r * .62, r * .48, r * .48), petal, u, w: .8);
  }
  c.drawCircle(o, r * .32, _f(heart));
}

void _rotated(Canvas c, Offset o, double a, void Function() fn) {
  c.save();
  c.translate(o.dx, o.dy);
  c.rotate(a);
  c.translate(-o.dx, -o.dy);
  fn();
  c.restore();
}

// ------------------------------------------------------------------------------------------------ các kiểu

/// Quốc kỳ: nền đỏ, sao vàng năm cánh ở giữa; rộng = 2/3 dài, bán kính sao = 1/5 chiều dài. Cờ đứng thẳng trên cán,
/// không méo, không bị vật gì đè lên.
void _flagVn(Canvas c, Rect b, Color fill, double u) {
  final poleX = b.right - 26 * u;
  final len = 21 * u, h = len * 2 / 3;
  final flag = Rect.fromLTWH(poleX + .9 * u, b.top - 18 * u, len, h);
  c.drawLine(Offset(poleX, b.top + 3 * u), Offset(poleX, b.top - 19 * u), _s(u, const Color(0xFF8D6E63), 1.8));
  c.drawCircle(Offset(poleX, b.top - 19.5 * u), 1.4 * u, _f(const Color(0xFFFFC107)));
  c.drawRect(flag, _f(const Color(0xFFDA251D)));
  c.drawRect(flag, _s(u, Colors.white.withValues(alpha: .9), .7));
  c.drawPath(_star(flag.center, len / 5), _f(const Color(0xFFFFFF00)));
}

void _lotusBud(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right - 14 * u, b.top - 2 * u);
  c.drawLine(o + Offset(0, 6 * u), o + Offset(2 * u, 2 * u), _s(u, const Color(0xFF558B2F), 1.4));
  final bud = Path()
    ..moveTo(o.dx, o.dy - 7 * u)
    ..quadraticBezierTo(o.dx + 5 * u, o.dy - 1 * u, o.dx + 1 * u, o.dy + 2.5 * u)
    ..quadraticBezierTo(o.dx - 4 * u, o.dy - 1 * u, o.dx, o.dy - 7 * u)
    ..close();
  _draw(c, bud, const Color(0xFFF48FB1), u, w: .9);
}

void _lotus(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.left + 8 * u, b.bottom + 4 * u);
  // Lá sen nằm ngang dưới hoa.
  final leaf = Path()..addOval(Rect.fromCenter(center: o + Offset(4 * u, 5 * u), width: 30 * u, height: 8 * u));
  _draw(c, leaf, const Color(0xFF66BB6A), u, w: .9);
  c.drawLine(o + Offset(4 * u, 5 * u), o + Offset(14 * u, 3.5 * u), _s(u, const Color(0xFF2E7D32), .8));
  Path petal(double dx, double tilt, double hgt) {
    final base = o + Offset(dx * u, 2 * u);
    final tip = base + Offset(tilt * u, -hgt * u);
    return Path()
      ..moveTo(base.dx - 3.5 * u, base.dy)
      ..quadraticBezierTo(base.dx - 4 * u + tilt * u * .3, tip.dy + 3 * u, tip.dx, tip.dy)
      ..quadraticBezierTo(base.dx + 4 * u + tilt * u * .3, tip.dy + 3 * u, base.dx + 3.5 * u, base.dy)
      ..close();
  }

  _draw(c, petal(-5, -5, 8), const Color(0xFFF8BBD0), u, w: .8);
  _draw(c, petal(5, 5, 8), const Color(0xFFF8BBD0), u, w: .8);
  _draw(c, petal(-2.5, -2, 11), const Color(0xFFF48FB1), u, w: .8);
  _draw(c, petal(2.5, 2, 11), const Color(0xFFF48FB1), u, w: .8);
  _draw(c, petal(0, 0, 13), const Color(0xFFEC407A), u, w: .8);
}

void _branch(Canvas c, Rect b, double u, Color petal, Color heart, {required bool round}) {
  final a = Offset(b.left - 8 * u, b.top + 4 * u);
  final p = Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(b.left + 14 * u, b.top - 10 * u, b.left + 44 * u, b.top - 6 * u);
  c.drawPath(p, _s(u, const Color(0xFF5D4037), 2.2));
  c.drawLine(Offset(b.left + 18 * u, b.top - 4.5 * u), Offset(b.left + 24 * u, b.top - 12 * u), _s(u, const Color(0xFF5D4037), 1.4));
  for (final (dx, dy, r) in [(4.0, -3.0, 5.0), (24.0, -12.0, 4.2), (36.0, -6.5, 5.0)]) {
    _flower(c, Offset(b.left + dx * u, b.top + dy * u), r * u, petal, heart, u, rot: round ? 0 : .3);
  }
  for (final (dx, dy) in [(14.0, -7.5), (45.0, -6.0)]) {
    _draw(c, _oval(Offset(b.left + dx * u, b.top + dy * u), 1.8 * u, 1.8 * u), petal, u, w: .7);
  }
}

void _maiBranch(Canvas c, Rect b, Color fill, double u) => _branch(c, b, u, const Color(0xFFFFC107), const Color(0xFFE65100), round: true);
void _daoBranch(Canvas c, Rect b, Color fill, double u) => _branch(c, b, u, const Color(0xFFF8A5C2), const Color(0xFFC2185B), round: false);

void _luckyMoney(Canvas c, Rect b, Color fill, double u) {
  final r = Rect.fromLTWH(b.right - 6 * u, b.bottom - 4 * u, 12 * u, 16 * u);
  _rotated(c, r.center, .18, () {
    _draw(c, _rr(r, 1.5 * u), const Color(0xFFD32F2F), u);
    c.drawCircle(r.center + Offset(0, 1 * u), 3 * u, _f(const Color(0xFFFFD54F)));
    c.drawLine(r.topLeft + Offset(0, 4 * u), r.topRight + Offset(0, 4 * u), _s(u, const Color(0xFFFFD54F), .7));
  });
}

void _banhChung(Canvas c, Rect b, Color fill, double u) {
  final r = Rect.fromLTWH(b.right - 16 * u, b.bottom - 5 * u, 18 * u, 17 * u);
  _draw(c, _rr(r, 2.5 * u), const Color(0xFF558B2F), u);
  c.drawRRect(RRect.fromRectAndRadius(r.deflate(2 * u), Radius.circular(1.5 * u)), _s(u, const Color(0xFF33691E), .7));
  // Lạt buộc: hai lạt mỗi chiều.
  final lat = _s(u, const Color(0xFFF1F8E9), 1.3);
  for (final t in [.36, .64]) {
    c.drawLine(Offset(r.left + r.width * t, r.top), Offset(r.left + r.width * t, r.bottom), lat);
    c.drawLine(Offset(r.left, r.top + r.height * t), Offset(r.right, r.top + r.height * t), lat);
  }
}

void _starLantern(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right - 18 * u, b.top - 7 * u);
  c.drawLine(Offset(o.dx + 10 * u, b.top - 22 * u), o + Offset(0, -9.5 * u), _s(u, const Color(0xFF8D6E63), .9));
  final s = _star(o, 9.5 * u, inner: .45);
  _draw(c, s, const Color(0xFFE53935), u);
  c.drawPath(_star(o, 5.5 * u, inner: .45), _f(const Color(0xFFFFD54F).withValues(alpha: .9)));
  // Nan tre từ tâm ra các cánh.
  for (var i = 0; i < 5; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / 5;
    c.drawLine(o, o + Offset(math.cos(a), math.sin(a)) * 9 * u, _s(u, const Color(0xFFFFB300), .6));
  }
  // Tua giấy hai cánh dưới.
  for (final dx in [-5.0, 5.0]) {
    final from = o + Offset(dx * 1.1 * u, 7.5 * u);
    c.drawLine(from, from + Offset(dx * .2 * u, 5 * u), _s(u, const Color(0xFFFFD54F), 1.2));
  }
}

void _phin(Canvas c, Rect b, Color fill, double u) {
  final x = b.right - 6 * u, bot = b.bottom + 8 * u;
  // Ly thuỷ tinh: lớp sữa trắng, cà phê.
  final glass = Path()
    ..moveTo(x - 6.5 * u, bot - 13 * u)
    ..lineTo(x + 6.5 * u, bot - 13 * u)
    ..lineTo(x + 5 * u, bot)
    ..lineTo(x - 5 * u, bot)
    ..close();
  c.drawPath(glass, _f(const Color(0xFFE3F2FD).withValues(alpha: .85)));
  final coffee = Path()
    ..moveTo(x - 6 * u, bot - 9 * u)
    ..lineTo(x + 6 * u, bot - 9 * u)
    ..lineTo(x + 5 * u, bot)
    ..lineTo(x - 5 * u, bot)
    ..close();
  c.drawPath(coffee, _f(const Color(0xFF4E342E)));
  c.drawRect(Rect.fromLTRB(x - 5.2 * u, bot - 3 * u, x + 5.2 * u, bot), _f(const Color(0xFFFFF8E1)));
  c.drawPath(glass, _s(u));
  // Phin nhôm đặt trên miệng ly.
  _draw(c, _rr(Rect.fromLTRB(x - 8 * u, bot - 14.5 * u, x + 8 * u, bot - 12.5 * u), 1 * u), const Color(0xFFB0BEC5), u, w: .8);
  _draw(c, _rr(Rect.fromLTRB(x - 5 * u, bot - 21 * u, x + 5 * u, bot - 14.5 * u), 1 * u), const Color(0xFFCFD8DC), u, w: .8);
  _draw(c, _rr(Rect.fromLTRB(x - 5.8 * u, bot - 22.5 * u, x + 5.8 * u, bot - 21 * u), .8 * u), const Color(0xFF90A4AE), u, w: .8);
  c.drawCircle(Offset(x, bot - 23.5 * u), 1.2 * u, _f(const Color(0xFF90A4AE)));
  // Khói ra phía ngoài.
  for (final dx in [9.0, 12.5]) {
    final p = Path()
      ..moveTo(x + dx * u, bot - 18 * u)
      ..cubicTo(x + (dx + 2.5) * u, bot - 21 * u, x + (dx - 2.5) * u, bot - 23 * u, x + dx * u, bot - 26 * u);
    c.drawPath(p, _s(u, const Color(0xFFBCAAA4), 1));
  }
}

void _spiral(Canvas c, Rect b, Color fill, double u) {
  final n = ((b.width - 24 * u) / (11 * u)).floor().clamp(2, 40);
  final step = (b.width - 24 * u) / math.max(1, n - 1);
  for (var i = 0; i < n; i++) {
    final x = b.left + 12 * u + i * step;
    c.drawCircle(Offset(x, b.top + 1.2 * u), 1.3 * u, _f(_ink.withValues(alpha: .35)));
    c.drawArc(Rect.fromCenter(center: Offset(x, b.top - 1.5 * u), width: 4.4 * u, height: 7 * u), math.pi * .6, math.pi * 1.8, false,
        _s(u, const Color(0xFF78909C), 1.3));
  }
}

void _pen(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right - 14 * u, b.bottom + 4 * u);
  _rotated(c, o, -.42, () {
    final body = Rect.fromCenter(center: o, width: 28 * u, height: 5 * u);
    _draw(c, _rr(body, 2.5 * u), const Color(0xFF1E5AA8), u);
    final tip = Path()
      ..moveTo(body.left, body.top + .6 * u)
      ..lineTo(body.left - 5 * u, o.dy)
      ..lineTo(body.left, body.bottom - .6 * u)
      ..close();
    _draw(c, tip, const Color(0xFFFFE0B2), u, w: .8);
    c.drawCircle(Offset(body.left - 4.4 * u, o.dy), .8 * u, _f(_ink));
    c.drawLine(Offset(body.right - 9 * u, body.top - .8 * u), Offset(body.right - 2 * u, body.top - .8 * u), _s(u, const Color(0xFFFFC107), 1.4));
    c.drawLine(Offset(body.right - 5 * u, body.top), Offset(body.right - 5 * u, body.bottom), _s(u, const Color(0xFFFFC107), 1));
  });
}

void _clipAndPin(Canvas c, Rect b, Color fill, double u) {
  // Kẹp giấy: hai vòng lồng nhau, kẹp qua mép trên.
  final x = b.left + 20 * u, y0 = b.top - 11 * u, y1 = b.top + 4.5 * u;
  final p = Path()
    ..moveTo(x + 2.5 * u, y1 - 3 * u)
    ..lineTo(x + 2.5 * u, y0 + 4 * u)
    ..arcToPoint(Offset(x - 2.5 * u, y0 + 4 * u), radius: Radius.circular(2.5 * u), clockwise: false)
    ..lineTo(x - 2.5 * u, y1 - 1 * u)
    ..arcToPoint(Offset(x + 4.5 * u, y1 - 1 * u), radius: Radius.circular(3.5 * u), clockwise: false)
    ..lineTo(x + 4.5 * u, y0 + 1.5 * u);
  c.drawPath(p, _s(u, const Color(0xFF607D8B), 2.4));
  c.drawPath(p, _s(u, const Color(0xFFCFD8DC), 1.1));
  // Đinh ghim đỏ góc phải.
  final pin = Offset(b.right - 10 * u, b.top - 4 * u);
  c.drawLine(pin, pin + Offset(2 * u, 6 * u), _s(u, const Color(0xFF78909C), 1));
  _draw(c, _oval(pin, 4 * u, 4 * u), const Color(0xFFE53935), u);
  c.drawCircle(pin + Offset(-1.3 * u, -1.3 * u), 1.1 * u, _f(Colors.white.withValues(alpha: .8)));
}

void _calendar(Canvas c, Rect b, Color fill, double u) {
  final r = Rect.fromLTWH(b.left - 7 * u, b.top - 12 * u, 18 * u, 17 * u);
  _rotated(c, r.center, -.12, () {
    _draw(c, _rr(r, 2.5 * u), Colors.white, u);
    c.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(r.left, r.top, r.width, 5.5 * u), topLeft: Radius.circular(2.5 * u), topRight: Radius.circular(2.5 * u)),
        _f(const Color(0xFFE53935)));
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(2.5 * u)), _s(u));
    for (final dx in [5.0, 13.0]) {
      c.drawLine(Offset(r.left + dx * u, r.top - 2 * u), Offset(r.left + dx * u, r.top + 2 * u), _s(u, _ink, 1.4));
    }
    // Ngày được khoanh tròn.
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 2; j++) {
        c.drawCircle(Offset(r.left + (4.5 + i * 4.5) * u, r.top + (9 + j * 4.5) * u), .9 * u, _f(_ink.withValues(alpha: .55)));
      }
    }
    c.drawCircle(Offset(r.left + 13.5 * u, r.top + 13.5 * u), 2.4 * u, _s(u, const Color(0xFFE53935), 1));
  });
}

void _alarmClock(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right + 2 * u, b.bottom + 3 * u);
  for (final a in [-.7, .7]) {
    final bell = o + Offset(math.sin(a) * 7.5 * u, -math.cos(a) * 7.5 * u);
    _draw(c, _oval(bell, 2.8 * u, 2.8 * u), const Color(0xFFE53935), u, w: .8);
  }
  _draw(c, _oval(o, 7 * u, 7 * u), const Color(0xFFE53935), u);
  c.drawCircle(o, 5.3 * u, _f(Colors.white));
  c.drawLine(o, o + Offset(0, -3.8 * u), _s(u, _ink, 1.1));
  c.drawLine(o, o + Offset(2.8 * u, 1 * u), _s(u, _ink, 1.1));
  c.drawCircle(o, .8 * u, _f(_ink));
}

void _wifi(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right - 12 * u, b.top - 1 * u);
  for (final r in [4.0, 7.5, 11.0]) {
    c.drawArc(Rect.fromCircle(center: o, radius: r * u), -math.pi * .78, math.pi * .56, false, _s(u, const Color(0xFF1E88E5), 1.6));
  }
  c.drawCircle(o + Offset(0, -1 * u), 1.4 * u, _f(const Color(0xFF1E88E5)));
}

void _laptop(Canvas c, Rect b, Color fill, double u) {
  final l = b.left - 10 * u, bot = b.bottom + 12 * u;
  final screen = Rect.fromLTWH(l + 3 * u, bot - 18 * u, 22 * u, 14 * u);
  _draw(c, _rr(screen, 1.8 * u), const Color(0xFF37474F), u);
  c.drawRect(screen.deflate(1.8 * u), _f(const Color(0xFF64B5F6)));
  final line = Path()
    ..moveTo(screen.left + 4 * u, screen.bottom - 4 * u)
    ..lineTo(screen.left + 9 * u, screen.bottom - 7 * u)
    ..lineTo(screen.left + 13 * u, screen.bottom - 5.5 * u)
    ..lineTo(screen.right - 4 * u, screen.top + 4 * u);
  c.drawPath(line, _s(u, Colors.white, 1.2));
  final base = Path()
    ..moveTo(l + 1 * u, bot - 4 * u)
    ..lineTo(l + 27 * u, bot - 4 * u)
    ..lineTo(l + 29 * u, bot - 1.2 * u)
    ..quadraticBezierTo(l + 29 * u, bot, l + 27.5 * u, bot)
    ..lineTo(l + .5 * u, bot)
    ..quadraticBezierTo(l - 1 * u, bot, l - 1 * u, bot - 1.2 * u)
    ..close();
  _draw(c, base, const Color(0xFFB0BEC5), u);
}

void _bulb(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right - 14 * u, b.top - 8 * u);
  for (var i = 0; i < 7; i++) {
    final a = -math.pi + i * math.pi / 6;
    c.drawLine(o + Offset(math.cos(a), math.sin(a)) * 9.5 * u, o + Offset(math.cos(a), math.sin(a)) * 12.5 * u, _s(u, const Color(0xFFFFA000), 1.3));
  }
  final glass = Path()
    ..moveTo(o.dx - 3 * u, o.dy + 6.5 * u)
    ..quadraticBezierTo(o.dx - 3.2 * u, o.dy + 4 * u, o.dx - 5 * u, o.dy + 2.5 * u)
    ..arcToPoint(Offset(o.dx + 5 * u, o.dy + 2.5 * u), radius: Radius.circular(7 * u), largeArc: true)
    ..quadraticBezierTo(o.dx + 3.2 * u, o.dy + 4 * u, o.dx + 3 * u, o.dy + 6.5 * u)
    ..close();
  _draw(c, glass, const Color(0xFFFFEB3B), u);
  c.drawPath(_sparkle(o + Offset(-1.5 * u, -1.5 * u), 2.5 * u), _f(Colors.white.withValues(alpha: .9)));
  _draw(c, _rr(Rect.fromLTRB(o.dx - 3 * u, o.dy + 6.5 * u, o.dx + 3 * u, o.dy + 10 * u), 1 * u), const Color(0xFF90A4AE), u, w: .8);
}

void _sparkles(Canvas c, Rect b, Color fill, double u) {
  for (final (dx, dy, r) in [(-6.0, 2.0, 4.0), (2.0, 7.0, 2.6), (-9.0, 8.5, 1.8)]) {
    c.drawPath(_sparkle(Offset(b.left + dx * u, b.bottom + dy * u), r * u), _f(const Color(0xFFFFB300)));
  }
}

void _rocket(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right - 4 * u, b.top - 6 * u);
  // Vệt bay chấm chấm từ góc bong bóng.
  for (var i = 1; i <= 3; i++) {
    c.drawCircle(o + Offset(-6.0 * i * u, 6.0 * i * u * .55), (1.6 - i * .3) * u, _f(const Color(0xFF90CAF9)));
  }
  _rotated(c, o, math.pi / 4, () {
    final flame = Path()
      ..moveTo(o.dx - 2.5 * u, o.dy + 7 * u)
      ..quadraticBezierTo(o.dx, o.dy + 15 * u, o.dx + 2.5 * u, o.dy + 7 * u)
      ..close();
    _draw(c, flame, const Color(0xFFFF9800), u, w: .8);
    for (final s in [-1.0, 1.0]) {
      final fin = Path()
        ..moveTo(o.dx + s * 3 * u, o.dy + 1 * u)
        ..lineTo(o.dx + s * 6.5 * u, o.dy + 7.5 * u)
        ..lineTo(o.dx + s * 2.5 * u, o.dy + 6 * u)
        ..close();
      _draw(c, fin, const Color(0xFFE53935), u, w: .8);
    }
    final body = Path()
      ..moveTo(o.dx, o.dy - 11 * u)
      ..quadraticBezierTo(o.dx + 5.5 * u, o.dy - 5 * u, o.dx + 3.5 * u, o.dy + 7 * u)
      ..lineTo(o.dx - 3.5 * u, o.dy + 7 * u)
      ..quadraticBezierTo(o.dx - 5.5 * u, o.dy - 5 * u, o.dx, o.dy - 11 * u)
      ..close();
    _draw(c, body, Colors.white, u);
    final nose = Path()
      ..moveTo(o.dx, o.dy - 11 * u)
      ..quadraticBezierTo(o.dx + 3.2 * u, o.dy - 8 * u, o.dx + 4 * u, o.dy - 5.5 * u)
      ..lineTo(o.dx - 4 * u, o.dy - 5.5 * u)
      ..quadraticBezierTo(o.dx - 3.2 * u, o.dy - 8 * u, o.dx, o.dy - 11 * u)
      ..close();
    _draw(c, nose, const Color(0xFFE53935), u, w: .8);
    _draw(c, _oval(o + Offset(0, -1 * u), 2 * u, 2 * u), const Color(0xFF4FC3F7), u, w: .8);
  });
}

void _nightStars(Canvas c, Rect b, Color fill, double u) {
  for (final (dx, dy, r) in [(-5.0, 3.0, 3.6), (6.0, 7.0, 2.2), (-10.0, 9.0, 1.6)]) {
    c.drawPath(_sparkle(Offset(b.left + dx * u, b.bottom + dy * u), r * u), _f(const Color(0xFFFFD54F)));
  }
}

void _barChart(Canvas c, Rect b, Color fill, double u) {
  final base = b.bottom + 10 * u, x = b.right - 18 * u;
  c.drawLine(Offset(x - 3 * u, base), Offset(x + 26 * u, base), _s(u, _ink, 1.2));
  for (final (i, h, col) in [(0, 8.0, Color(0xFFFFCA28)), (1, 13.0, Color(0xFFFFA000)), (2, 19.0, Color(0xFFFF6F00))]) {
    _draw(c, _rr(Rect.fromLTWH(x + i * 7.5 * u, base - h * u, 5.5 * u, h * u), 1 * u), col, u, w: .9);
  }
  final up = Path()
    ..moveTo(x - 4 * u, base - 8 * u)
    ..lineTo(x + 6 * u, base - 15 * u)
    ..lineTo(x + 12 * u, base - 12 * u)
    ..lineTo(x + 23 * u, base - 24 * u);
  c.drawPath(up, _s(u, Colors.white, 3.2));
  c.drawPath(up, _s(u, const Color(0xFFE53935), 1.8));
  final head = Path()
    ..moveTo(x + 25 * u, base - 26.5 * u)
    ..lineTo(x + 18 * u, base - 24.5 * u)
    ..lineTo(x + 23.5 * u, base - 19.5 * u)
    ..close();
  _draw(c, head, const Color(0xFFE53935), u, w: .8);
}

void _trophy(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.left + 14 * u, b.top - 6 * u);
  const gold = Color(0xFFFFC107);
  for (final s in [-1.0, 1.0]) {
    c.drawArc(Rect.fromCenter(center: o + Offset(s * 6 * u, -3 * u), width: 6 * u, height: 7 * u), s < 0 ? math.pi * .5 : -math.pi * .5,
        math.pi, false, _s(u, const Color(0xFFFFA000), 1.6));
  }
  final cup = Path()
    ..moveTo(o.dx - 6.5 * u, o.dy - 8 * u)
    ..lineTo(o.dx + 6.5 * u, o.dy - 8 * u)
    ..quadraticBezierTo(o.dx + 6.5 * u, o.dy + 2 * u, o.dx, o.dy + 2.5 * u)
    ..quadraticBezierTo(o.dx - 6.5 * u, o.dy + 2 * u, o.dx - 6.5 * u, o.dy - 8 * u)
    ..close();
  _draw(c, cup, gold, u);
  c.drawLine(o + Offset(0, 2.5 * u), o + Offset(0, 6 * u), _s(u, const Color(0xFFFFA000), 2));
  _draw(c, _rr(Rect.fromCenter(center: o + Offset(0, 7.5 * u), width: 10 * u, height: 3 * u), .8 * u), const Color(0xFF8D6E63), u, w: .8);
  c.drawPath(_star(o + Offset(0, -3.5 * u), 2.6 * u), _f(Colors.white.withValues(alpha: .9)));
  c.drawPath(_sparkle(o + Offset(12 * u, -7 * u), 2.6 * u), _f(gold));
}

void _medal(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right - 2 * u, b.bottom + 6 * u);
  final rib = Path()
    ..moveTo(o.dx - 4 * u, o.dy - 11 * u)
    ..lineTo(o.dx - 1 * u, o.dy - 3 * u)
    ..lineTo(o.dx + 1 * u, o.dy - 3 * u)
    ..lineTo(o.dx + 4 * u, o.dy - 11 * u)
    ..close();
  _draw(c, rib, const Color(0xFF1E88E5), u, w: .8);
  _draw(c, _oval(o, 5 * u, 5 * u), const Color(0xFFFFC107), u);
  c.drawPath(_star(o, 3 * u), _f(const Color(0xFFFF8F00)));
}

void _stamp(Canvas c, Rect b, Color fill, double u) {
  final o = Offset(b.right + 1 * u, b.bottom + 6 * u);
  const red = Color(0xFFD32F2F);
  _rotated(c, o, -.26, () {
    c.drawCircle(o, 12 * u, _f(Colors.white.withValues(alpha: .55)));
    c.drawCircle(o, 11.5 * u, _s(u, red, 1.8));
    c.drawCircle(o, 8.5 * u, _s(u, red, .8));
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi / 8;
      c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * 10 * u, .45 * u, _f(red));
    }
    final tick = Path()
      ..moveTo(o.dx - 4.5 * u, o.dy + .2 * u)
      ..lineTo(o.dx - 1.2 * u, o.dy + 3.6 * u)
      ..lineTo(o.dx + 4.8 * u, o.dy - 3.6 * u);
    c.drawPath(tick, _s(u, red, 2.2));
  });
}

Path _piece(Rect r, double u, {bool knobRight = false, bool slotLeft = false}) {
  final k = r.height * .2;
  final p = Path()..moveTo(r.left, r.top);
  p.lineTo(r.right, r.top);
  if (knobRight) {
    p.lineTo(r.right, r.center.dy - k);
    p.arcToPoint(Offset(r.right, r.center.dy + k), radius: Radius.circular(k * 1.05), largeArc: true);
  }
  p.lineTo(r.right, r.bottom);
  p.lineTo(r.left, r.bottom);
  if (slotLeft) {
    p.lineTo(r.left, r.center.dy + k);
    p.arcToPoint(Offset(r.left, r.center.dy - k), radius: Radius.circular(k * 1.05), largeArc: true, clockwise: false);
  }
  return p..close();
}

void _puzzle(Canvas c, Rect b, Color fill, double u) {
  final y = b.top - 13 * u, x = b.right - 34 * u;
  final a = Rect.fromLTWH(x, y, 13 * u, 13 * u);
  final bb = Rect.fromLTWH(x + 13 * u, y, 13 * u, 13 * u);
  _rotated(c, Offset(x + 13 * u, y + 6.5 * u), -.08, () {
    _draw(c, _piece(bb, u, slotLeft: true), const Color(0xFFFFA726), u);
    _draw(c, _piece(a, u, knobRight: true), const Color(0xFF29B6F6), u);
  });
}

void _hardHat(Canvas c, Rect b, Color fill, double u) {
  final l = b.left + 8 * u, r = b.left + 36 * u, base = b.top + 2.5 * u;
  final dome = Path()
    ..moveTo(l + 2 * u, base)
    ..cubicTo(l + 2 * u, b.top - 12 * u, r - 2 * u, b.top - 12 * u, r - 2 * u, base)
    ..close();
  _draw(c, dome, const Color(0xFFFFC107), u);
  c.drawLine(Offset((l + r) / 2, b.top - 6.8 * u), Offset((l + r) / 2, base), _s(u, const Color(0xFFFFA000), 2.6));
  _draw(c, _rr(Rect.fromLTRB(l - 2 * u, base - 1 * u, r + 4 * u, base + 2 * u), 1.5 * u), const Color(0xFFFFB300), u);
}

void _cone(Canvas c, Rect b, Color fill, double u) {
  final x = b.right + 1 * u, bot = b.bottom + 10 * u;
  final cone = Path()
    ..moveTo(x - 1.5 * u, bot - 17 * u)
    ..lineTo(x + 1.5 * u, bot - 17 * u)
    ..lineTo(x + 5.5 * u, bot - 2 * u)
    ..lineTo(x - 5.5 * u, bot - 2 * u)
    ..close();
  _draw(c, cone, const Color(0xFFFF6D00), u);
  for (final t in [.35, .65]) {
    final y = bot - 17 * u + 15 * u * t;
    final half = 1.5 * u + 4 * u * t;
    c.drawLine(Offset(x - half + .6 * u, y), Offset(x + half - .6 * u, y), _s(u, Colors.white, 1.8));
  }
  _draw(c, _rr(Rect.fromLTRB(x - 8 * u, bot - 2.5 * u, x + 8 * u, bot), 1 * u), const Color(0xFFE65100), u, w: .8);
}

void _floorDisplay(Canvas c, Rect b, Color fill, double u) {
  final r = Rect.fromLTWH(b.right - 30 * u, b.top - 12 * u, 20 * u, 10 * u);
  _draw(c, _rr(r, 2 * u), const Color(0xFF263238), u);
  final up = Path()
    ..moveTo(r.left + 5 * u, r.top + 2.5 * u)
    ..lineTo(r.left + 8 * u, r.bottom - 2.5 * u)
    ..lineTo(r.left + 2 * u, r.bottom - 2.5 * u)
    ..close();
  c.drawPath(up, _f(const Color(0xFFFFB300)));
  // Số tầng dạng chấm (không dùng chữ để hợp mọi ngôn ngữ).
  for (var i = 0; i < 2; i++) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left + (10.5 + i * 4.2) * u, r.top + 2.4 * u, 3 * u, 5.2 * u), Radius.circular(.8 * u)),
        _s(u, const Color(0xFFFFB300), .9));
  }
}

void _callPanel(Canvas c, Rect b, Color fill, double u) {
  final h = math.min(22 * u, b.height - 4 * u);
  if (h < 14 * u) return;
  final r = Rect.fromLTWH(b.right + 2 * u, b.center.dy - h / 2, 9 * u, h);
  _draw(c, _rr(r, 2.5 * u), const Color(0xFFB0BEC5), u, w: .9);
  final up = r.center + Offset(0, -h * .22), dn = r.center + Offset(0, h * .22);
  c.drawCircle(up, 3 * u, _f(const Color(0xFF66BB6A)));
  c.drawCircle(dn, 3 * u, _f(const Color(0xFFECEFF1)));
  c.drawPath(Path()..moveTo(up.dx, up.dy - 1.6 * u)..lineTo(up.dx + 1.7 * u, up.dy + 1.1 * u)..lineTo(up.dx - 1.7 * u, up.dy + 1.1 * u)..close(),
      _f(Colors.white));
  c.drawPath(Path()..moveTo(dn.dx, dn.dy + 1.6 * u)..lineTo(dn.dx + 1.7 * u, dn.dy - 1.1 * u)..lineTo(dn.dx - 1.7 * u, dn.dy - 1.1 * u)..close(),
      _f(const Color(0xFF78909C)));
}

void _finishFlag(Canvas c, Rect b, Color fill, double u) {
  final poleX = b.right - 28 * u;
  c.drawLine(Offset(poleX, b.top + 3 * u), Offset(poleX, b.top - 20 * u), _s(u, const Color(0xFF8D6E63), 1.8));
  final flag = Rect.fromLTWH(poleX + .9 * u, b.top - 19 * u, 20 * u, 12 * u);
  const n = 5, m = 3;
  final cw = flag.width / n, ch = flag.height / m;
  // Cờ hơi gợn sóng: mỗi cột lệch lên xuống một chút.
  for (var i = 0; i < n; i++) {
    final dy = math.sin(i * 1.3) * 1.2 * u;
    for (var j = 0; j < m; j++) {
      c.drawRect(Rect.fromLTWH(flag.left + i * cw, flag.top + j * ch + dy, cw + .3, ch + .3),
          _f((i + j).isEven ? const Color(0xFF212121) : Colors.white));
    }
  }
  final outline = Path();
  for (var i = 0; i <= n; i++) {
    final dy = math.sin(math.min(i, n - 1) * 1.3) * 1.2 * u;
    final pt = Offset(flag.left + i * cw, flag.top + dy);
    i == 0 ? outline.moveTo(pt.dx, pt.dy) : outline.lineTo(pt.dx, pt.dy);
  }
  for (var i = n; i >= 0; i--) {
    final dy = math.sin(math.min(i, n - 1) * 1.3) * 1.2 * u;
    outline.lineTo(flag.left + i * cw, flag.bottom + dy);
  }
  c.drawPath(outline..close(), _s(u, _ink, .8));
}

void _burst(Canvas c, Offset o, double r, Color col, double u) {
  for (var i = 0; i < 10; i++) {
    final a = i * math.pi / 5;
    final d = Offset(math.cos(a), math.sin(a));
    c.drawLine(o + d * r * .35, o + d * r * .85, _s(u, col, 1.3));
    c.drawCircle(o + d * r, .9 * u, _f(col));
  }
}

void _fireworks(Canvas c, Rect b, Color fill, double u) {
  _burst(c, Offset(b.left + 4 * u, b.top - 7 * u), 8 * u, const Color(0xFFFFD54F), u);
  _burst(c, Offset(b.right - 10 * u, b.top - 8 * u), 7 * u, const Color(0xFFFF4081), u);
  _burst(c, Offset(b.right - 26 * u, b.top - 4 * u), 4.5 * u, const Color(0xFF4DD0E1), u);
}

void _confetti(Canvas c, Rect b, Color fill, double u) {
  final cols = [const Color(0xFFFFD54F), const Color(0xFFFF4081), const Color(0xFF4DD0E1), const Color(0xFF69F0AE)];
  for (var i = 0; i < 6; i++) {
    final o = Offset(b.left - 4 * u + i * 6.5 * u, b.bottom + (3 + (i * 37 % 5)) * u);
    _rotated(c, o, i * .9, () => c.drawRect(Rect.fromCenter(center: o, width: 3.6 * u, height: 1.8 * u), _f(cols[i % 4])));
  }
}

void _balloons(Canvas c, Rect b, Color fill, double u) {
  for (final (dx, dy, col) in [(-20.0, -10.0, Color(0xFF42A5F5)), (-10.0, -13.0, Color(0xFFEF5350))]) {
    final o = Offset(b.right + dx * u, b.top + dy * u);
    final string = Path()
      ..moveTo(o.dx, o.dy + 6.5 * u)
      ..quadraticBezierTo(o.dx + 2 * u, o.dy + 10 * u, o.dx - 1 * u, b.top + 2 * u);
    c.drawPath(string, _s(u, _ink.withValues(alpha: .7), .7));
    _draw(c, _oval(o, 4.6 * u, 5.8 * u), col, u);
    c.drawCircle(o + Offset(-1.6 * u, -2 * u), 1.1 * u, _f(Colors.white.withValues(alpha: .75)));
  }
}

void _cake(Canvas c, Rect b, Color fill, double u) {
  final l = b.left - 12 * u, bot = b.bottom + 10 * u;
  _draw(c, _rr(Rect.fromLTWH(l, bot - 8 * u, 22 * u, 8 * u), 1.5 * u), const Color(0xFFEC407A), u);
  _draw(c, _rr(Rect.fromLTWH(l + 3.5 * u, bot - 14 * u, 15 * u, 6.5 * u), 1.5 * u), const Color(0xFFFFF3E0), u);
  // Kem chảy trên tầng dưới.
  final drip = Path()..moveTo(l + .6 * u, bot - 6.8 * u);
  for (var i = 0; i < 5; i++) {
    drip.quadraticBezierTo(l + (2.2 + i * 4.2) * u, bot - 3.8 * u, l + (4.4 + i * 4.2) * u, bot - 6.8 * u);
  }
  c.drawPath(drip, _s(u, Colors.white, 1.5));
  c.drawLine(Offset(l + 11 * u, bot - 14 * u), Offset(l + 11 * u, bot - 18.5 * u), _s(u, const Color(0xFF42A5F5), 1.6));
  final flame = Path()
    ..moveTo(l + 11 * u, bot - 23 * u)
    ..quadraticBezierTo(l + 13 * u, bot - 20 * u, l + 11 * u, bot - 18.8 * u)
    ..quadraticBezierTo(l + 9 * u, bot - 20 * u, l + 11 * u, bot - 23 * u)
    ..close();
  c.drawPath(flame, _f(const Color(0xFFFFA000)));
}

void _plant(Canvas c, Rect b, Color fill, double u) {
  final x = b.left - 3 * u, bot = b.bottom + 10 * u;
  for (final (a, len) in [(-1.25, 14.0), (-1.75, 18.0), (-2.2, 13.0), (-1.5, 22.0)]) {
    final base = Offset(x, bot - 9 * u);
    final tip = base + Offset(math.cos(a), math.sin(a)) * len * u;
    final mid = Offset.lerp(base, tip, .5)!;
    final n = Offset(-(tip.dy - base.dy), tip.dx - base.dx) / len * 2.6;
    final leaf = Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(mid.dx + n.dx, mid.dy + n.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(mid.dx - n.dx, mid.dy - n.dy, base.dx, base.dy)
      ..close();
    _draw(c, leaf, const Color(0xFF43A047), u, w: .8);
  }
  final pot = Path()
    ..moveTo(x - 7 * u, bot - 10 * u)
    ..lineTo(x + 7 * u, bot - 10 * u)
    ..lineTo(x + 5 * u, bot)
    ..lineTo(x - 5 * u, bot)
    ..close();
  _draw(c, pot, const Color(0xFFD84315), u);
  _draw(c, _rr(Rect.fromLTRB(x - 8 * u, bot - 11.5 * u, x + 8 * u, bot - 8.5 * u), 1 * u), const Color(0xFFBF360C), u, w: .8);
}

void _catEars(Canvas c, Rect b, Color fill, double u) {
  // Tai mèo cùng màu bong bóng: bong bóng thành "đầu mèo".
  final edge = Color.lerp(fill, Colors.black, .35)!;
  for (final x in [b.left + 16 * u, b.left + 40 * u]) {
    final ear = Path()
      ..moveTo(x - 7 * u, b.top + 3 * u)
      ..quadraticBezierTo(x - 3 * u, b.top - 9 * u, x - .5 * u, b.top - 10 * u)
      ..quadraticBezierTo(x + 3 * u, b.top - 7 * u, x + 7 * u, b.top + 3 * u)
      ..close();
    c.drawPath(ear, _f(fill));
    c.drawPath(ear, _s(u, edge, 1));
    final inner = Path()
      ..moveTo(x - 3.5 * u, b.top + 1 * u)
      ..quadraticBezierTo(x - 1.5 * u, b.top - 5 * u, x - .5 * u, b.top - 6 * u)
      ..quadraticBezierTo(x + 1.5 * u, b.top - 4 * u, x + 3.5 * u, b.top + 1 * u)
      ..close();
    c.drawPath(inner, _f(const Color(0xFFF8BBD0)));
  }
}

void _catPaws(Canvas c, Rect b, Color fill, double u) {
  final edge = Color.lerp(fill, Colors.black, .35)!;
  for (final x in [b.left + 18 * u, b.left + 32 * u]) {
    final paw = _oval(Offset(x, b.bottom + 1.5 * u), 5 * u, 4 * u);
    c.drawPath(paw, _f(fill));
    c.drawPath(paw, _s(u, edge, 1));
    for (final dx in [-1.6, 1.6]) {
      c.drawLine(Offset(x + dx * u, b.bottom + 2.5 * u), Offset(x + dx * u, b.bottom + 5 * u), _s(u, edge, .8));
    }
  }
  // Đuôi cong ra phía phải.
  final tail = Path()
    ..moveTo(b.right - 3 * u, b.bottom - 2 * u)
    ..cubicTo(b.right + 9 * u, b.bottom, b.right + 8 * u, b.bottom - 14 * u, b.right + 3 * u, b.bottom - 12 * u);
  c.drawPath(tail, _s(u, edge, 4.6));
  c.drawPath(tail, _s(u, fill, 2.8));
}
