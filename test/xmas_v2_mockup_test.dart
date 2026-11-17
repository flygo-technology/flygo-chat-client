// Mockup v2 (chạy tay): XMAS_OUT=<thư mục> flutter test test/xmas_v2_mockup_test.dart
// - 3 kiểu thanh dưới mùa Giáng sinh (Đêm Noel / Tuyết phủ / Kẹo gậy) trên tông tối xanh, đặt trong màn hình điện thoại đầy đủ;
// - bảng so sánh (tối + sáng);
// - Quản trị: bong bóng + hình nền mùa lễ tự áp cho mọi người; Cài đặt: công tắc "Dùng giao diện mùa lễ".
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/bubble_picker.dart';
import 'package:flygo_chat/ui/bubble_styles.dart';
import 'package:flygo_chat/ui/season/season.dart';
import 'package:flygo_chat/ui/theme.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

// ------------------------------------------------------------------ bảng màu
class _C {
  final bool dark;
  const _C(this.dark);
  Color get bgTop => dark ? const Color(0xFF0B1220) : const Color(0xFFF4F7FC);
  Color get bgBottom => dark ? const Color(0xFF10203A) : const Color(0xFFE9EFF8);
  Color get text => dark ? const Color(0xFFEAF0FA) : const Color(0xFF0F1A2E);
  Color get sub => dark ? const Color(0xFF8C9BB5) : const Color(0xFF5B6B85);
  Color get card => dark ? const Color(0xFF14233F) : Colors.white;
  Color get line => dark ? const Color(0xFF1E3050) : const Color(0xFFDCE4F0);
  static const blue = Color(0xFF2F80FF);
  static const gold = Color(0xFFE9B949);
  static const red = Color(0xFFD9363E);
  static const snow = Color(0xFFF4F8FF);
  // Thanh dưới thường của app trên nền tối xanh.
  Color get bar => dark ? const Color(0xFF13213B) : Colors.white;
  Color get barBorder => dark ? const Color(0x14FFFFFF) : const Color(0x14000000);
}

enum NavStyle { off, noel, snow, cane }

// ------------------------------------------------------------------ thanh dưới
class _Bar extends StatelessWidget {
  final NavStyle style;
  final _C c;
  final int sel;
  const _Bar(this.style, this.c) : sel = 0;

  static const _items = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chat', 3),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Trợ lý', 1),
    (Icons.newspaper_outlined, Icons.newspaper_rounded, 'Bảng tin', 0),
    (Icons.apps_rounded, Icons.apps_rounded, 'Apps', 0),
  ];

  @override
  Widget build(BuildContext context) {
    final h = style == NavStyle.noel ? 72.0 : 66.0;
    const r = 33.0;
    final noel = style == NavStyle.noel;
    final barFill = noel
        ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF13285A), Color(0xFF0B1838)])
        : LinearGradient(colors: [c.bar, c.bar]);
    final iconOn = switch (style) {
      NavStyle.noel => const Color(0xFF1A1405),
      NavStyle.snow => c.dark ? const Color(0xFFFF6B6B) : const Color(0xFFC62828),
      _ => c.text,
    };
    final iconOff = noel ? const Color(0xFFF3EBD8).withValues(alpha: .78) : c.text.withValues(alpha: .62);

    Widget item(int i) {
      final (o, f, label, badge) = _items[i];
      final on = i == sel;
      Widget icon = Icon(on ? f : o, size: 25, color: on ? iconOn : iconOff);
      icon = Badge(
        isLabelVisible: badge > 0,
        backgroundColor: _C.blue,
        textColor: Colors.white,
        offset: const Offset(7, -5),
        label: Text('$badge', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
        child: icon,
      );
      final labelW = Text(label,
          style: TextStyle(fontSize: 11, height: 1.1, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? iconOn : iconOff));
      Widget body = Column(mainAxisSize: MainAxisSize.min, children: [icon, const SizedBox(height: 3), labelW]);
      // Chỉ báo mục đang chọn.
      Widget pill = Container(
        width: 78,
        height: 52,
        alignment: Alignment.center,
        decoration: on
            ? switch (style) {
                NavStyle.noel => BoxDecoration(
                    color: _C.gold,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [BoxShadow(color: _C.gold.withValues(alpha: .38), blurRadius: 14, spreadRadius: -2)],
                  ),
                NavStyle.snow => BoxDecoration(
                    color: (c.dark ? const Color(0xFFFF6B6B) : const Color(0xFFC62828)).withValues(alpha: c.dark ? .14 : .10),
                    borderRadius: BorderRadius.circular(26)),
                NavStyle.off => BoxDecoration(color: c.text.withValues(alpha: .09), borderRadius: BorderRadius.circular(26)),
                NavStyle.cane => const BoxDecoration(),
              }
            : null,
        child: body,
      );
      if (on && style == NavStyle.snow) {
        pill = Stack(clipBehavior: Clip.none, children: [
          pill,
          const Positioned(right: 0, top: -6, child: CustomPaint(size: Size(24, 18), painter: _HollyPainter())),
        ]);
      }
      if (on && style == NavStyle.cane) {
        pill = Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          pill,
          const Positioned(bottom: -1, child: CustomPaint(size: Size(36, 5), painter: _CanePainter())),
        ]);
      }
      return Expanded(child: Center(child: pill));
    }

    return SizedBox(
      height: h + 14,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          right: 0,
          top: 14,
          height: h,
          child: Container(
            decoration: BoxDecoration(
              gradient: barFill,
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: noel ? const Color(0x1FFFFFFF) : c.barBorder),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: c.dark ? .45 : .14), blurRadius: 22, offset: const Offset(0, 8))],
            ),
            child: Padding(
              padding: EdgeInsets.only(top: noel ? 8 : 0),
              child: Row(children: [for (var i = 0; i < _items.length; i++) item(i)]),
            ),
          ),
        ),
        if (noel) Positioned(left: 0, right: 0, top: 14, height: 14, child: const IgnorePointer(child: CustomPaint(painter: _BulbsPainter(radius: r)))),
        if (style == NavStyle.snow)
          Positioned(left: 0, right: 0, top: 0, height: 30, child: IgnorePointer(child: CustomPaint(painter: _SnowPainter(radius: r, dark: c.dark)))),
      ]),
    );
  }
}

/// 7 bóng đèn ấm, nhỏ, trên dây mảnh vắt sát mép trên (bên trong viền, không chạm biểu tượng).
class _BulbsPainter extends CustomPainter {
  final double radius;
  const _BulbsPainter({required this.radius});
  @override
  void paint(Canvas c, Size s) {
    // Dây mảnh vắt sát mép trên giữa hai đầu bo; 7 bóng nhỏ treo cách đều, chỉ rủ xuống ~9 px (biểu tượng bắt đầu từ ~16 px).
    final x0 = radius * .75, x1 = s.width - radius * .75;
    const n = 7, y0 = 1.5, sag = 2.4;
    final seg = (x1 - x0) / n;
    final wire = Path()..moveTo(x0, y0);
    for (var i = 0; i < n; i++) {
      wire.quadraticBezierTo(x0 + seg * (i + .5), y0 + sag * 2, x0 + seg * (i + 1), y0);
    }
    c.drawPath(wire, Paint()
      ..color = const Color(0xFF3A4C78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    const cols = [Color(0xFFFFC85A), Color(0xFFFF8A5C), Color(0xFFFFE9B0)];
    for (var i = 0; i < n; i++) {
      final x = x0 + seg * (i + .5), y = y0 + sag;
      final col = cols[i % 3];
      c.drawCircle(Offset(x, y + 5), 6, Paint()
        ..color = col.withValues(alpha: .42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y + .9), width: 2.8, height: 2), const Radius.circular(.5)),
          Paint()..color = const Color(0xFF59607A));
      final bulb = Path()
        ..moveTo(x - 2, y + 1.8)
        ..cubicTo(x - 3.2, y + 4.4, x - 2, y + 7.6, x, y + 7.9)
        ..cubicTo(x + 2, y + 7.6, x + 3.2, y + 4.4, x + 2, y + 1.8)
        ..close();
      c.drawPath(bulb, Paint()..color = col);
      c.drawCircle(Offset(x - .7, y + 3.9), .7, Paint()..color = Colors.white.withValues(alpha: .75));
    }
  }

  @override
  bool shouldRepaint(_BulbsPainter old) => false;
}

/// Lớp tuyết dày, mềm phủ trên mép trên (bám đường bo hai đầu), bóng xanh xám phía dưới, 3 giọt rủ.
class _SnowPainter extends CustomPainter {
  final double radius;
  final bool dark;
  const _SnowPainter({required this.radius, required this.dark});
  @override
  void paint(Canvas c, Size s) {
    const top = 14.0; // mép trên của thanh trong khung này
    final w = s.width, r = radius;
    double edge(double x) {
      if (x < r) return top + r - math.sqrt(math.max(0, r * r - (r - x) * (r - x)));
      if (x > w - r) return top + r - math.sqrt(math.max(0, r * r - (x - (w - r)) * (x - (w - r))));
      return top;
    }

    double thick(double x) {
      final t = x / w;
      final taper = Curves.easeInOut.transform(math.min(1.0, math.min(t, 1 - t) * 4.2));
      // Gợn mềm: tổng vài sóng dài, không răng cưa.
      return taper * (8.0 + 2.2 * math.sin(x * .034 + .6) + 1.4 * math.sin(x * .081 + 2.1));
    }

    final xs = [for (double x = r * .2; x <= w - r * .2; x += 1.5) x];
    final cap = Path()..moveTo(xs.first, edge(xs.first) + 1);
    for (final x in xs) {
      cap.lineTo(x, edge(x) - thick(x));
    }
    // Đáy lớp tuyết: lấn vào thanh 3 px, có 3 giọt rủ.
    final drips = {w * .30: 6.0, w * .55: 8.0, w * .77: 5.0};
    for (final x in xs.reversed) {
      var y = edge(x) + 3;
      for (final d in drips.entries) {
        final dx = (x - d.key).abs();
        if (dx < 6) y += d.value * math.cos(dx / 6 * math.pi / 2);
      }
      cap.lineTo(x, y);
    }
    cap.close();
    // Bóng đổ nhẹ xuống thanh.
    c.drawPath(cap.shift(const Offset(0, 1.8)), Paint()
      ..color = Colors.black.withValues(alpha: dark ? .35 : .12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2));
    final b = cap.getBounds();
    c.drawPath(
        cap,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, b.top), Offset(0, b.bottom), [
            _C.snow,
            _C.snow,
            dark ? const Color(0xFFC9D6EC) : const Color(0xFFD5E0EF),
          ], [0, .62, 1]));
    // Ánh sáng trên đỉnh tuyết.
    final hi = Path()..moveTo(xs.first, edge(xs.first) - thick(xs.first));
    for (final x in xs) {
      hi.lineTo(x, edge(x) - thick(x) + 1.2);
    }
    c.drawPath(hi, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_SnowPainter old) => false;
}

/// Nhành nhựa ruồi: 2 lá có răng cưa + 3 quả đỏ.
class _HollyPainter extends CustomPainter {
  const _HollyPainter();
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    Path leaf(Offset base, double ang, double len) {
      final p = Path();
      final d = Offset(math.cos(ang), math.sin(ang)), n = Offset(-d.dy, d.dx);
      final tip = base + d * len;
      p.moveTo(base.dx, base.dy);
      for (var k = 1; k <= 3; k++) {
        final m = base + d * (len * k / 3.4);
        final o = m + n * (len * .28) + d * (len * .06);
        p.quadraticBezierTo(o.dx, o.dy, (base + d * (len * (k + .5) / 3.4)).dx + n.dx * len * .16, (base + d * (len * (k + .5) / 3.4)).dy + n.dy * len * .16);
      }
      p.lineTo(tip.dx, tip.dy);
      for (var k = 3; k >= 1; k--) {
        final m = base + d * (len * k / 3.4);
        final o = m - n * (len * .28) + d * (len * .06);
        p.quadraticBezierTo(o.dx, o.dy, (base + d * (len * (k - .5) / 3.4)).dx - n.dx * len * .16, (base + d * (len * (k - .5) / 3.4)).dy - n.dy * len * .16);
      }
      return p..close();
    }

    final base = Offset(w * .5, h * .62);
    c.drawPath(leaf(base, math.pi * 1.05, w * .48), Paint()..color = const Color(0xFF2E8B57));
    c.drawPath(leaf(base, -math.pi * .08, w * .48), Paint()..color = const Color(0xFF3FA66B));
    for (final o in [const Offset(-2.2, -1.6), const Offset(2.2, -1.6), const Offset(0, 1.6)]) {
      c.drawCircle(base + o, 2.2, Paint()..color = const Color(0xFFD9363E));
      c.drawCircle(base + o + const Offset(-.7, -.7), .6, Paint()..color = Colors.white.withValues(alpha: .7));
    }
  }

  @override
  bool shouldRepaint(_HollyPainter old) => false;
}

/// Gạch chân sọc kẹo gậy (đỏ / trắng chéo), bo tròn.
class _CanePainter extends CustomPainter {
  const _CanePainter();
  @override
  void paint(Canvas c, Size s) {
    final rr = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.height / 2));
    c.save();
    c.clipRRect(rr);
    c.drawRect(Offset.zero & s, Paint()..color = Colors.white);
    final red = Paint()..color = _C.red;
    for (double x = -s.height; x < s.width + s.height; x += 6) {
      c.drawPath(
          Path()
            ..moveTo(x, s.height)
            ..lineTo(x + 3, s.height)
            ..lineTo(x + 3 + s.height, 0)
            ..lineTo(x + s.height, 0)
            ..close(),
          red);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_CanePainter old) => false;
}

// ------------------------------------------------------------------ màn hình điện thoại (danh sách chat)
class _Phone extends StatelessWidget {
  final NavStyle style;
  final _C c;
  final String title;
  const _Phone(this.style, this.c, this.title);

  @override
  Widget build(BuildContext context) {
    const chats = [
      ('Phòng Kinh doanh', 'Hà My: Chiều 24/12 liên hoan nhé cả nhà', '09:18', 3, 0xFF2E7D32),
      ('Lan Phạm', 'Em gửi báo giá thang máy tòa B rồi ạ', '09:02', 0, 0xFFE3A08A),
      ('Kỹ thuật – Bảo trì', 'Tuấn: Đã thay cáp xong, chạy thử ổn', 'Hôm qua', 1, 0xFF3949AB),
      ('Minh Anh', 'Merry Christmas!', 'Hôm qua', 0, 0xFF9CCF8F),
      ('Kế toán', 'Hóa đơn tháng 12 đã xuất', 'T2', 0, 0xFFF0C46A),
      ('Quang Huy', 'Ok anh', 'T2', 0, 0xFFC7A6EE),
      ('Dự án Vinhomes', 'Bản vẽ mới nhất ở Drive', 'CN', 0, 0xFF0E9F8E),
    ];
    Widget row((String, String, String, int, int) x) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Color(x.$5)),
              child: Text(x.$1.split(' ').map((w) => w[0]).take(2).join(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(x.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text))),
                  Text(x.$3, style: TextStyle(fontSize: 12.5, color: x.$4 > 0 ? _C.blue : c.sub)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  Expanded(child: Text(x.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.sub))),
                  if (x.$4 > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: _C.blue, borderRadius: BorderRadius.circular(10)),
                      child: Text('${x.$4}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ]),
            ),
          ]),
        );
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.bgTop, c.bgBottom])),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 54),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(children: [
              Text('Chat', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c.text)),
              const Spacer(),
              Icon(Icons.edit_square, color: _C.blue, size: 24),
            ]),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.search_rounded, color: c.sub, size: 20),
              const SizedBox(width: 8),
              Text('Tìm kiếm', style: TextStyle(color: c.sub, fontSize: 15)),
            ]),
          ),
          for (final x in chats) row(x),
        ]),
        // Nhãn phương án.
        Positioned(
          right: 16,
          top: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _C.blue.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
            child: Text(title, style: const TextStyle(color: _C.blue, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
        Positioned(left: 14, right: 14, bottom: 26, child: _Bar(style, c)),
        // Thanh home của iPhone.
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(child: Container(width: 134, height: 5, decoration: BoxDecoration(color: c.text.withValues(alpha: .85), borderRadius: BorderRadius.circular(3)))),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Quản trị: mùa lễ tự áp cho mọi người
Widget _adminSeason(_C c) {
  Widget card(List<Widget> ch, {String? title}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 16, 8),
            child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: .5, fontWeight: FontWeight.w700, color: c.sub)),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
          child: Column(children: ch),
        ),
      ]);
  Widget seg(List<String> opts, int sel) => Container(
        margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.dark ? const Color(0xFF0E1A31) : const Color(0xFFEFF3F9), borderRadius: BorderRadius.circular(11)),
        child: Row(children: [
          for (final (i, t) in opts.indexed)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: i == sel ? BoxDecoration(color: _C.blue, borderRadius: BorderRadius.circular(9)) : null,
                child: Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: i == sel ? Colors.white : c.sub)),
              ),
            ),
        ]),
      );
  Widget sw(String t, String? s, bool v, {IconData? icon}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: _C.blue, size: 22), const SizedBox(width: 14)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: TextStyle(fontSize: 15, color: c.text, fontWeight: FontWeight.w500)),
              if (s != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(s, style: TextStyle(fontSize: 12.5, color: c.sub, height: 1.3))),
            ]),
          ),
          Switch(value: v, onChanged: (_) {}, activeTrackColor: _C.blue),
        ]),
      );
  Widget div() => Divider(height: 1, color: c.line, indent: 16);
  final group = [for (final s in bubbleStyles) if (s.group == 'giangsinh') s];
  Widget miniBubble(BubbleStyle s, {bool on = false}) => Container(
        width: 66,
        padding: const EdgeInsets.only(top: 4),
        child: Column(children: [
          SizedBox(
            height: 46,
            child: Center(
              child: StyledBubble(
                style: s,
                fill: s.color,
                scale: .62,
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                child: Text('Aa', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: bubbleTextOn(s.color))),
              ),
            ),
          ),
          Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: on ? c.text : c.sub)),
        ]),
      );
  Widget wpTile(Widget art, String name, bool on) => Expanded(
        child: Column(children: [
          Container(
            height: 92,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            padding: EdgeInsets.all(on ? 2.5 : 1),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? _C.blue : c.line, width: on ? 2.5 : 1)),
            child: ClipRRect(borderRadius: BorderRadius.circular(9), child: art),
          ),
          const SizedBox(height: 6),
          Text(name, style: TextStyle(fontSize: 12.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? c.text : c.sub)),
        ]),
      );
  final noel = wallpaperById('demnoel')!, white = wallpaperById('tuyettrang')!;
  return Container(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.bgTop, c.bgBottom])),
    child: ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 48, 16, 4),
        child: Row(children: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _C.blue)),
          Expanded(child: Text('Giao diện', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text))),
          const Text('Lưu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.blue)),
        ]),
      ),
      card([
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1E3A70), Color(0xFF0E1E40)]), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.park_rounded, color: _C.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Giáng sinh', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                Text('01/12 – 26/12 · tự bật, tự tắt', style: TextStyle(fontSize: 13, color: c.sub)),
              ]),
            ),
            Switch(value: true, onChanged: (_) {}, activeTrackColor: _C.blue),
          ]),
        ),
        div(),
        sw('Xem thử trên máy của tôi', 'Chỉ mình thấy, bất kể ngày. Nhân viên không thấy gì.', true, icon: Icons.visibility_outlined),
      ]),
      card(title: 'Bong bóng mùa lễ · tự áp cho mọi người', [
        seg(['Một kiểu', 'Ngẫu nhiên trong nhóm Giáng sinh'], 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Mỗi người một kiểu cố định (theo tài khoản), giống nhau trên mọi máy.', style: TextStyle(fontSize: 12.5, color: c.sub)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          child: Wrap(children: [for (final s in group) miniBubble(s, on: true)]),
        ),
      ]),
      card(title: 'Hình nền mùa lễ · tự áp cho mọi người', [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          child: Row(children: [
            wpTile(Row(children: [Expanded(child: WallpaperView(wallpaper: noel, frozenT: 2)), Expanded(child: WallpaperView(wallpaper: white, frozenT: 2))]),
                'Tự động sáng/tối', true),
            wpTile(WallpaperView(wallpaper: noel, frozenT: 2), 'Đêm Noel', false),
            wpTile(WallpaperView(wallpaper: white, frozenT: 2), 'Tuyết trắng', false),
          ]),
        ),
      ]),
      card(title: 'Trang trí khác', [
        sw('Dây đèn trên khung chat', null, true, icon: Icons.light_rounded),
        div(),
        sw('Thanh điều hướng mùa lễ', null, true, icon: Icons.space_bar_rounded),
        div(),
        sw('Mũ Noel trên ảnh đại diện', null, true, icon: Icons.face_retouching_natural_rounded),
        div(),
        sw('Hiệu ứng khi có lời chúc', null, true, icon: Icons.auto_awesome_rounded),
        div(),
        sw('Banner đếm ngược ở Trang chủ', null, true, icon: Icons.home_outlined),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 30),
        child: Text('Thứ tự áp dụng: 1. chat chọn riêng, 2. mặc định người dùng tự đặt, 3. mùa lễ, 4. mặc định của app. Hết mùa tự trở lại như cũ.',
            style: TextStyle(fontSize: 12.5, color: c.sub, height: 1.35)),
      ),
    ]),
  );
}

// ------------------------------------------------------------------ Cài đặt (mọi người): công tắc mùa lễ
Widget _userSettings(_C c) {
  final st = bubbleStyles.firstWhere((s) => s.id == 'munoel');
  Widget sw(String t, String? s, bool v, {IconData? icon, bool sub = false}) => Padding(
        padding: EdgeInsets.fromLTRB(sub ? 52 : 16, 12, 12, 12),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: _C.blue, size: 22), const SizedBox(width: 14)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: TextStyle(fontSize: sub ? 14.5 : 15.5, color: c.text, fontWeight: sub ? FontWeight.w400 : FontWeight.w600)),
              if (s != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(s, style: TextStyle(fontSize: 12.5, color: c.sub, height: 1.3))),
            ]),
          ),
          Switch(value: v, onChanged: (_) {}, activeTrackColor: _C.blue),
        ]),
      );
  Widget div([double i = 16]) => Divider(height: 1, color: c.line, indent: i);
  Widget row(IconData i, String t, String v) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(children: [
          Icon(i, color: c.sub, size: 22),
          const SizedBox(width: 14),
          Expanded(child: Text(t, style: TextStyle(fontSize: 15.5, color: c.text))),
          Text(v, style: TextStyle(fontSize: 14, color: c.sub)),
          Icon(Icons.chevron_right_rounded, color: c.sub),
        ]),
      );
  return Container(
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.bgTop, c.bgBottom])),
    child: ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 48, 16, 8),
        child: Row(children: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _C.blue)),
          Text('Cài đặt', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text)),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
        child: Column(children: [
          row(Icons.notifications_none_rounded, 'Thông báo', ''),
          div(52),
          row(Icons.language_rounded, 'Ngôn ngữ', 'Tiếng Việt'),
          div(52),
          row(Icons.dark_mode_outlined, 'Chế độ tối', 'Theo máy'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 18, 16, 8),
        child: Text('GIAO DIỆN', style: TextStyle(fontSize: 12, letterSpacing: .5, fontWeight: FontWeight.w700, color: c.sub)),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Thẻ mùa đang diễn ra.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF13285A), Color(0xFF0B1838)])),
            child: Row(children: [
              const Icon(Icons.park_rounded, color: _C.gold, size: 26),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Giáng sinh đang diễn ra', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  SizedBox(height: 2),
                  Text('Tới 26/12, sau đó tự trở lại như cũ', style: TextStyle(color: Color(0xFFB9C6E0), fontSize: 12.5)),
                ]),
              ),
              StyledBubble(
                style: st,
                fill: st.color,
                scale: .7,
                padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
                child: Text('Aa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: bubbleTextOn(st.color))),
              ),
            ]),
          ),
          sw('Dùng giao diện mùa lễ', 'Bong bóng Mũ Noel và hình nền Đêm Noel cho mọi chat. Tắt để giữ giao diện thường.', true, icon: Icons.celebration_outlined),
          div(52),
          sw('Dây đèn, thanh điều hướng', null, true, sub: true),
          div(52),
          sw('Hiện mũ Noel của mọi người', null, true, sub: true),
          div(52),
          sw('Đội mũ cho ảnh của mình', null, true, sub: true),
          div(52),
          sw('Hiệu ứng khi có lời chúc', null, true, sub: true),
          div(),
          row(Icons.chat_bubble_outline_rounded, 'Bong bóng mặc định', 'Theo mùa lễ'),
          div(52),
          row(Icons.wallpaper_rounded, 'Hình nền mặc định', 'Theo mùa lễ'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 10, 28, 4),
        child: Text('Chat nào đã chọn riêng bong bóng / hình nền thì giữ lựa chọn đó. "Áp dụng cho mọi chat" bỏ các lựa chọn riêng ấy.', style: TextStyle(fontSize: 12.5, color: c.sub)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        child: OutlinedButton.icon(
          onPressed: () {},
          style: OutlinedButton.styleFrom(foregroundColor: _C.blue, side: const BorderSide(color: _C.blue), padding: const EdgeInsets.symmetric(vertical: 13)),
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Áp dụng cho mọi chat', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    ]),
  );
}

void main() {
  final out = Platform.environment['XMAS_OUT'];

  Future<void> render(WidgetTester t, String file, Size size, Widget child, {bool dark = true}) async {
    await t.runAsync(_fonts);
    t.view.physicalSize = size * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(dark ? Brightness.dark : Brightness.light), home: Scaffold(body: child)),
    ));
    await t.pump(const Duration(milliseconds: 50));
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 3);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$file.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  const phone = Size(390, 844);
  const names = {NavStyle.noel: '1 · Đêm Noel', NavStyle.snow: '2 · Tuyết phủ', NavStyle.cane: '3 · Kẹo gậy', NavStyle.off: 'Hiện nay'};
  for (final s in [NavStyle.noel, NavStyle.snow, NavStyle.cane]) {
    testWidgets('phone ${s.name}', (t) async {
      if (out != null) await render(t, '15-navbar-${s.index}-${s.name}-dark', phone, _Phone(s, const _C(true), names[s]!));
    });
  }
  testWidgets('so sánh', (t) async {
    if (out == null) return;
    // Mỗi ô: phần dưới màn hình (danh sách + thanh), 3 cột × 2 hàng (tối / sáng) + cột "hiện nay".
    Widget cell(NavStyle s, bool dark) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 300,
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: 844,
                  maxHeight: 844,
                  child: Theme(data: buildTheme(dark ? Brightness.dark : Brightness.light), child: _Phone(s, _C(dark), names[s]!)),
                ),
              ),
            ),
          ),
        );
    await render(
      t,
      '15-navbar-compare',
      const Size(1640, 700),
      Container(
        color: const Color(0xFF070D18),
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          for (final dark in [true, false]) Row(children: [for (final s in [NavStyle.noel, NavStyle.snow, NavStyle.cane, NavStyle.off]) cell(s, dark)]),
        ]),
      ),
    );
  });
  testWidgets('quản trị mùa lễ', (t) async {
    if (out != null) await render(t, '16-admin-season-dark', const Size(390, 1500), _adminSeason(const _C(true)));
  });
  testWidgets('cài đặt người dùng', (t) async {
    if (out != null) await render(t, '17-user-season-dark', const Size(390, 1100), _userSettings(const _C(true)));
  });
}
