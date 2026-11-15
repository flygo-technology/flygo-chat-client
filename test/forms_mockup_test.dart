// Mockup (chỉ để duyệt thiết kế, chưa phải giao diện thật) cho app Biểu mẫu: danh sách, soạn, điền, câu trả lời,
// chia sẻ, trang công khai. Chạy tay: MK_OUT=<thư mục> flutter test test/forms_mockup_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/theme.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f.startsWith('/') ? f : '$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// Màu chủ đề của biểu mẫu mẫu (người soạn chọn).
const _theme = Color(0xFF0F8B8D);

Color _tint(Color c, bool dark) => Color.lerp(c, dark ? Colors.black : Colors.white, dark ? .72 : .88)!;

// ---------------------------------------------------------------- khối dùng chung

class _Card extends StatelessWidget {
  const _Card({required this.child, this.top, this.left, this.pad = const EdgeInsets.all(20)});
  final Widget child;
  final Color? top, left;
  final EdgeInsets pad;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.bg == Colors.white ? Colors.white : p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (top != null) Container(height: 8, color: top),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (left != null) Container(width: 5, color: left),
                Expanded(
                  child: Padding(padding: pad, child: child),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Text _t(BuildContext c, String s, {double size = 14, FontWeight w = FontWeight.w400, Color? color, int? lines}) => Text(
  s,
  maxLines: lines,
  overflow: lines == null ? null : TextOverflow.ellipsis,
  style: TextStyle(fontSize: size, fontWeight: w, color: color ?? Pal.of(c).text, height: 1.35),
);

Widget _sub(BuildContext c, String s, {double size = 12.5}) => _t(c, s, size: size, color: Pal.of(c).sub);

Widget _underline(BuildContext c, String hint, {double width = double.infinity}) {
  final p = Pal.of(c);
  return SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.only(bottom: 6, top: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.divider, width: 1.2)),
      ),
      child: _t(c, hint, color: p.sub),
    ),
  );
}

Widget _pill(BuildContext c, String s, {Color? bg, Color? fg, IconData? icon}) {
  final p = Pal.of(c);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: bg ?? p.surface, borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg ?? p.sub), const SizedBox(width: 4)],
        Text(
          s,
          style: TextStyle(fontSize: 12, color: fg ?? p.sub, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
}

Widget _btn(String s, {Color bg = _theme, IconData? icon, bool outline = false, Color? fg}) => Builder(
  builder: (c) {
    final p = Pal.of(c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(8),
        border: outline ? Border.all(color: p.divider) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 17, color: outline ? (fg ?? p.text) : Colors.white), const SizedBox(width: 6)],
          Text(
            s,
            style: TextStyle(color: outline ? (fg ?? p.text) : Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ],
      ),
    );
  },
);

Widget _radio(BuildContext c, String s, {bool on = false, bool square = false}) {
  final p = Pal.of(c);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(
          square ? (on ? Icons.check_box : Icons.check_box_outline_blank) : (on ? Icons.radio_button_checked : Icons.radio_button_off),
          size: 21,
          color: on ? _theme : p.sub,
        ),
        const SizedBox(width: 12),
        Expanded(child: _t(c, s)),
      ],
    ),
  );
}

Widget _q(BuildContext c, String title, {bool req = false, String? help}) {
  final p = Pal.of(c);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: title),
            if (req)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFD93025)),
              ),
          ],
        ),
        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: p.text, height: 1.35),
      ),
      if (help != null) Padding(padding: const EdgeInsets.only(top: 4), child: _sub(c, help)),
      const SizedBox(height: 10),
    ],
  );
}

Widget _scale(BuildContext c, {int sel = -1, String lo = 'Rất không hài lòng', String hi = 'Rất hài lòng'}) {
  final p = Pal.of(c);
  return Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 1; i <= 5; i++)
            Column(
              children: [
                _t(c, '$i', size: 13),
                const SizedBox(height: 6),
                Icon(i == sel ? Icons.radio_button_checked : Icons.radio_button_off, size: 22, color: i == sel ? _theme : p.sub),
              ],
            ),
        ],
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_sub(c, lo, size: 11.5), _sub(c, hi, size: 11.5)]),
    ],
  );
}

Widget _switch(BuildContext c, String label, bool on, {String? help}) {
  final p = Pal.of(c);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _t(c, label, size: 14),
              if (help != null) Padding(padding: const EdgeInsets.only(top: 2), child: _sub(c, help, size: 12)),
            ],
          ),
        ),
        Container(
          width: 38,
          height: 22,
          padding: const EdgeInsets.all(2),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(color: on ? _theme : p.surface2, borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ],
    ),
  );
}

Widget _bar(BuildContext c, String label, int n, int total, {Color color = _theme, double labelW = 150}) {
  final p = Pal.of(c);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(width: labelW, child: _t(c, label, size: 13, lines: 1)),
        Expanded(
          child: Container(
            height: 22,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(4)),
            child: FractionallySizedBox(
              widthFactor: n / total,
              child: Container(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 74,
          child: Text(
            '$n (${(100 * n / total).round()}%)',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12.5, color: p.sub),
          ),
        ),
      ],
    ),
  );
}

class _Donut extends CustomPainter {
  _Donut(this.parts, this.colors, this.hole);
  final List<int> parts;
  final List<Color> colors;
  final Color hole;
  @override
  void paint(Canvas canvas, Size s) {
    final total = parts.fold(0, (a, b) => a + b);
    var a = -pi / 2;
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.shortestSide / 2);
    for (var i = 0; i < parts.length; i++) {
      final sw = 2 * pi * parts[i] / total;
      canvas.drawArc(r, a, sw, true, Paint()..color = colors[i]);
      a += sw;
    }
    canvas.drawCircle(r.center, r.width * .3, Paint()..color = hole);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const _pieColors = [Color(0xFF0F8B8D), Color(0xFFE4A11B), Color(0xFF5B6CC4), Color(0xFFD9534F), Color(0xFF8E9AAF)];

Widget _donut(BuildContext c, List<(String, int)> items, {double size = 130}) {
  final p = Pal.of(c);
  final total = items.fold(0, (a, b) => a + b.$2);
  return Row(
    children: [
      SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _Donut([for (final i in items) i.$2], _pieColors, p.bg == Colors.white ? Colors.white : p.surface)),
      ),
      const SizedBox(width: 24),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: _pieColors[i], borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _t(c, items[i].$1, size: 13)),
                    _sub(c, '${items[i].$2} · ${(100 * items[i].$2 / total).round()}%'),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

Widget _histogram(BuildContext c, List<int> v, {double h = 120}) {
  final p = Pal.of(c);
  final m = v.reduce(max);
  return SizedBox(
    height: h + 48,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < v.length; i++)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _sub(c, '${v[i]}'),
                const SizedBox(height: 4),
                Container(
                  height: h * v[i] / m,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _theme.withValues(alpha: .45 + .55 * (i + 1) / v.length),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
                Container(height: 1, color: p.divider),
                const SizedBox(height: 4),
                _t(c, '${i + 1}', size: 12.5),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Thanh tiêu đề trong app (như các app native khác: nút quay lại, tên, thao tác).
Widget _appBar(BuildContext c, String title, {List<Widget> actions = const [], Widget? bottom, bool back = true}) {
  final p = Pal.of(c);
  return Container(
    decoration: BoxDecoration(
      color: p.bg,
      border: Border(bottom: BorderSide(color: p.divider)),
    ),
    child: Column(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 4),
              if (back)
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.arrow_back, color: p.text),
                )
              else
                const SizedBox(width: 12),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: _theme, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.assignment_outlined, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: _t(c, title, size: 17, w: FontWeight.w600, lines: 1)),
              ...actions,
              const SizedBox(width: 8),
            ],
          ),
        ),
        ?bottom,
      ],
    ),
  );
}

Widget _tabs(BuildContext c, List<String> tabs, int sel) {
  final p = Pal.of(c);
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < tabs.length; i++)
        Container(
          padding: EdgeInsets.symmetric(horizontal: tabs.length > 3 ? 12 : 18, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: i == sel ? _theme : Colors.transparent, width: 3)),
          ),
          child: Text(
            tabs[i],
            style: TextStyle(fontSize: 14, fontWeight: i == sel ? FontWeight.w600 : FontWeight.w500, color: i == sel ? _theme : p.sub),
          ),
        ),
    ],
  );
}

Widget _icon(BuildContext c, IconData i, {String? tip}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 2),
  child: IconButton(
    onPressed: () {},
    tooltip: tip,
    icon: Icon(i, color: Pal.of(c).sub, size: 22),
  ),
);

// ---------------------------------------------------------------- nội dung mẫu

const _formTitle = 'Khảo sát hài lòng khách hàng — Quý 4';
const _formDesc = 'Cảm ơn anh/chị đã sử dụng dịch vụ. Khảo sát mất khoảng 2 phút, câu trả lời giúp chúng tôi phục vụ tốt hơn.';

Widget _header(BuildContext c, {bool editing = false}) => _Card(
  top: _theme,
  left: editing ? null : null,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _t(c, _formTitle, size: 24, w: FontWeight.w500),
      const SizedBox(height: 8),
      _t(c, _formDesc, size: 13.5, color: Pal.of(c).sub),
      if (!editing) ...[
        const SizedBox(height: 14),
        Divider(height: 1, color: Pal.of(c).divider),
        const SizedBox(height: 10),
        const Text('* Bắt buộc', style: TextStyle(color: Color(0xFFD93025), fontSize: 12.5)),
      ],
    ],
  ),
);

// ---------------------------------------------------------------- màn hình

/// Danh sách biểu mẫu (trang chủ app).
Widget formsHome(BuildContext c, {bool desktop = false}) {
  final p = Pal.of(c);
  final tpl = [
    ('Trống', Icons.add, p.accent),
    ('Đăng ký sự kiện', Icons.event_available_outlined, const Color(0xFF5B6CC4)),
    ('Khảo sát hài lòng', Icons.sentiment_satisfied_alt_outlined, _theme),
    ('Đơn xin nghỉ phép', Icons.beach_access_outlined, const Color(0xFFE4A11B)),
    ('Phiếu góp ý', Icons.forum_outlined, const Color(0xFFD9534F)),
  ];
  final forms = [
    (_formTitle, 'Đang nhận · 128 câu trả lời', _theme, true, 'Công khai'),
    ('Đăng ký tiệc tất niên 2026', 'Đang nhận · 46 câu trả lời', const Color(0xFF5B6CC4), true, 'Nội bộ'),
    ('Đánh giá nhà cung cấp', 'Đã đóng 12/11 · 9 câu trả lời', const Color(0xFFE4A11B), false, 'Phòng Mua hàng'),
    ('Phiếu đề xuất cải tiến', 'Nháp · chưa gửi', const Color(0xFF8E9AAF), false, 'Nháp'),
    ('Kiểm tra an toàn công trình', 'Đang nhận · 31 câu trả lời » Quy trình', const Color(0xFFD9534F), true, 'Nội bộ'),
    ('Đăng ký đồng phục', 'Đang nhận · 77 câu trả lời', const Color(0xFF2E7D32), true, 'Nội bộ'),
  ];
  final cols = desktop ? 4 : 2;
  return Column(
    children: [
      _appBar(c, 'Biểu mẫu', back: !desktop, actions: [_icon(c, Icons.search), _icon(c, Icons.more_vert)]),
      Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: desktop ? 48 : 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _t(c, 'Tạo biểu mẫu mới', size: 15, w: FontWeight.w600),
              const SizedBox(height: 10),
              SizedBox(
                height: desktop ? 150 : 128,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in tpl)
                      Container(
                        width: desktop ? 160 : 118,
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _tint(t.$3, p.bg != Colors.white),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: p.divider),
                                ),
                                child: Center(child: Icon(t.$2, size: 38, color: t.$3)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _t(c, t.$1, size: 12.5, lines: 1),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _t(c, 'Biểu mẫu của tôi', size: 15, w: FontWeight.w600),
                  const Spacer(),
                  _pill(c, 'Tất cả', bg: p.chipSelBg, fg: p.chipSelFg),
                  const SizedBox(width: 6),
                  _pill(c, 'Của tôi'),
                  const SizedBox(width: 6),
                  _pill(c, 'Được chia sẻ'),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: desktop ? 1.35 : .95,
                children: [
                  for (final f in forms)
                    Container(
                      decoration: BoxDecoration(
                        color: p.bg == Colors.white ? Colors.white : p.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.divider),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Container(
                              color: _tint(f.$3, p.bg != Colors.white),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 6,
                                    width: 60,
                                    decoration: BoxDecoration(color: f.$3, borderRadius: BorderRadius.circular(3)),
                                  ),
                                  const SizedBox(height: 10),
                                  for (final w in [.9, .6, .75])
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 7),
                                      height: 6,
                                      width: 120 * w,
                                      decoration: BoxDecoration(color: p.sub.withValues(alpha: .25), borderRadius: BorderRadius.circular(3)),
                                    ),
                                  const Spacer(),
                                  _pill(
                                    c,
                                    f.$5,
                                    bg: p.bg.withValues(alpha: .7),
                                    icon: f.$5 == 'Công khai' ? Icons.public : (f.$5 == 'Nháp' ? Icons.edit_note : Icons.lock_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _t(c, f.$1, size: 13.5, w: FontWeight.w600, lines: 1),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(Icons.circle, size: 8, color: f.$4 ? const Color(0xFF2E9D57) : p.sub),
                                          const SizedBox(width: 5),
                                          Expanded(child: _t(c, f.$2, size: 11.5, color: p.sub, lines: 1)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.more_vert, size: 18, color: p.sub),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Câu hỏi đang chọn trong trình soạn (mở rộng đủ công cụ).
Widget _editQuestion(BuildContext c, {bool compact = false}) {
  final p = Pal.of(c);
  Widget opt(String s, {bool other = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(Icons.drag_indicator, size: 18, color: p.sub.withValues(alpha: .5)),
        const SizedBox(width: 4),
        Icon(Icons.radio_button_off, size: 20, color: p.sub),
        const SizedBox(width: 10),
        Expanded(child: _t(c, s, color: other ? p.sub : p.text)),
        if (!compact) ...[
          _pill(c, other ? 'Tiếp tục' : (s.startsWith('Không') ? '» Mục 3: Góp ý' : 'Tiếp tục'), icon: Icons.alt_route),
          const SizedBox(width: 6),
        ],
        Icon(Icons.close, size: 18, color: p.sub),
      ],
    ),
  );
  return _Card(
    left: _theme,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  border: Border(bottom: BorderSide(color: _theme, width: 2)),
                ),
                child: _t(c, 'Anh/chị có giới thiệu dịch vụ cho người quen không?', size: 15),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  border: Border.all(color: p.divider),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.radio_button_checked, size: 18, color: p.sub),
                    const SizedBox(width: 8),
                    _t(c, 'Trắc nghiệm', size: 13.5),
                    const SizedBox(width: 18),
                    Icon(Icons.arrow_drop_down, color: p.sub),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (compact) ...[const SizedBox(height: 10), _pill(c, 'Trắc nghiệm', icon: Icons.radio_button_checked)],
        const SizedBox(height: 14),
        opt('Có, chắc chắn'),
        opt('Có thể'),
        opt('Không'),
        Padding(
          padding: const EdgeInsets.only(left: 22, top: 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Thêm lựa chọn',
                  style: TextStyle(color: p.sub),
                ),
                TextSpan(
                  text: '  hoặc  ',
                  style: TextStyle(color: p.sub),
                ),
                TextSpan(
                  text: 'thêm "Khác"',
                  style: TextStyle(color: p.accentText, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 14),
        Divider(height: 1, color: p.divider),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _icon(c, Icons.content_copy_outlined, tip: 'Nhân bản'),
            _icon(c, Icons.delete_outline, tip: 'Xoá'),
            Container(width: 1, height: 26, color: p.divider, margin: const EdgeInsets.symmetric(horizontal: 8)),
            _t(c, 'Bắt buộc', size: 13.5),
            const SizedBox(width: 8),
            SizedBox(width: 44, child: _switch(c, '', true)),
            _icon(c, Icons.more_vert),
          ],
        ),
      ],
    ),
  );
}

Widget _collapsedQuestion(BuildContext c, String title, Widget body, {bool req = false}) => _Card(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _q(c, title, req: req),
      body,
    ],
  ),
);

Widget _sectionBadge(BuildContext c, String s) => Align(
  alignment: Alignment.centerLeft,
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: const BoxDecoration(
      color: _theme,
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    child: Text(
      s,
      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
  ),
);

/// Trình soạn.
Widget builderScreen(BuildContext c, {bool desktop = true}) {
  final p = Pal.of(c);
  final toolbar = Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      color: p.bg == Colors.white ? Colors.white : p.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: p.divider),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _icon(c, Icons.add_circle_outline, tip: 'Thêm câu hỏi'),
        _icon(c, Icons.title, tip: 'Thêm tiêu đề và mô tả'),
        _icon(c, Icons.image_outlined, tip: 'Thêm ảnh'),
        _icon(c, Icons.view_agenda_outlined, tip: 'Thêm mục'),
        _icon(c, Icons.file_download_outlined, tip: 'Nhập câu hỏi từ biểu mẫu khác'),
        _icon(c, Icons.auto_awesome_outlined, tip: 'Soạn bằng AI'),
      ],
    ),
  );
  final body = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionBadge(c, 'Mục 1 / 3'),
      _header(c, editing: true),
      _collapsedQuestion(c, 'Họ và tên', _underline(c, 'Văn bản câu trả lời ngắn', width: 320), req: true),
      _editQuestion(c, compact: !desktop),
      _collapsedQuestion(
        c,
        'Số điện thoại',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _underline(c, 'Văn bản câu trả lời ngắn', width: 320),
            const SizedBox(height: 8),
            _pill(c, 'Kiểm tra: số điện thoại Việt Nam', icon: Icons.rule),
          ],
        ),
        req: true,
      ),
      _collapsedQuestion(c, 'Mức độ hài lòng chung', _scale(c), req: true),
      if (desktop)
        _collapsedQuestion(
          c,
          'Đính kèm ảnh (nếu có)',
          Row(
            children: [
              _btn('Thêm tệp', icon: Icons.upload_file, outline: true),
              const SizedBox(width: 10),
              _sub(c, 'Tối đa 3 tệp · ảnh, PDF · 10 MB / tệp'),
            ],
          ),
        ),
    ],
  );
  final actions = [
    if (desktop) _icon(c, Icons.palette_outlined, tip: 'Màu chủ đề'),
    _icon(c, Icons.visibility_outlined, tip: 'Xem trước'),
    if (desktop) _icon(c, Icons.undo),
    if (desktop) ...[const SizedBox(width: 8), _btn('Gửi', icon: Icons.send), const SizedBox(width: 8)] else _icon(c, Icons.send_outlined),
    _icon(c, Icons.more_vert),
  ];
  return Column(
    children: [
      _appBar(c, _formTitle, back: !desktop, actions: actions, bottom: _tabs(c, ['Câu hỏi', 'Câu trả lời  128', 'Tự động hoá', 'Cài đặt'], 0)),
      Expanded(
        child: Container(
          color: _tint(_theme, p.bg != Colors.white),
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 16, horizontal: desktop ? 0 : 10),
                child: Center(
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
                ),
              ),
              if (desktop)
                Positioned(right: 60, top: 300, child: toolbar)
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: p.bg,
                      border: Border(top: BorderSide(color: p.divider)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _icon(c, Icons.add_circle_outline),
                        _icon(c, Icons.title),
                        _icon(c, Icons.image_outlined),
                        _icon(c, Icons.view_agenda_outlined),
                        _icon(c, Icons.auto_awesome_outlined),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Người điền (trong app hoặc trang công khai).
Widget fillScreen(BuildContext c, {bool public = false, bool desktop = false}) {
  final p = Pal.of(c);
  final content = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(c),
      if (!public)
        _Card(
          pad: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: p.avatarBg,
                child: Text('L', style: TextStyle(color: p.avatarFg, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(child: _sub(c, 'Đang điền với tài khoản Lan Nguyễn · tên và email được ghi kèm câu trả lời', size: 12.5)),
            ],
          ),
        ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _q(c, 'Họ và tên', req: true),
            _t(c, 'Trần Minh Anh'),
            Container(height: 1.6, color: _theme, margin: const EdgeInsets.only(top: 6)),
          ],
        ),
      ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _q(c, 'Số điện thoại', req: true),
            _t(c, '0912 34'),
            Container(height: 1.6, color: const Color(0xFFD93025), margin: const EdgeInsets.only(top: 6)),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Color(0xFFD93025)),
                SizedBox(width: 6),
                Text('Số điện thoại chưa đúng (10 chữ số, bắt đầu bằng 0)', style: TextStyle(color: Color(0xFFD93025), fontSize: 12.5)),
              ],
            ),
          ],
        ),
      ),
      _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_q(c, 'Mức độ hài lòng chung', req: true), _scale(c, sel: 4)]),
      ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _q(c, 'Anh/chị đã dùng những dịch vụ nào?', help: 'Chọn tất cả các mục phù hợp'),
            _radio(c, 'Lắp đặt mới', on: true, square: true),
            _radio(c, 'Bảo trì định kỳ', on: true, square: true),
            _radio(c, 'Sửa chữa khẩn cấp', square: true),
            _radio(c, 'Khác:', square: true),
          ],
        ),
      ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _q(c, 'Ngày sử dụng dịch vụ gần nhất'),
            Row(
              children: [
                _underline(c, '14/11/2026', width: 150),
                const SizedBox(width: 10),
                Icon(Icons.calendar_today_outlined, size: 18, color: p.sub),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          _btn('Tiếp'),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: 1 / 3, minHeight: 8, color: _theme, backgroundColor: p.surface2),
                  ),
                ),
                const SizedBox(width: 10),
                _sub(c, 'Trang 1 / 3'),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Xoá hết',
            style: TextStyle(color: _theme, fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Center(child: _sub(c, public ? 'Không cần đăng nhập · Không gửi mật khẩu qua biểu mẫu này' : 'Bản nháp được lưu tự động trên máy này', size: 11.5)),
      const SizedBox(height: 6),
      Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.assignment_outlined, size: 11, color: Colors.white),
            ),
            const SizedBox(width: 6),
            _t(c, 'Flygo Biểu mẫu', size: 13, w: FontWeight.w600, color: p.sub),
          ],
        ),
      ),
      const SizedBox(height: 4),
      if (public) Center(child: _sub(c, 'Báo cáo lạm dụng', size: 11)),
      const SizedBox(height: 20),
    ],
  );
  final scroll = Container(
    color: _tint(_theme, p.bg != Colors.white),
    child: SingleChildScrollView(
      padding: EdgeInsets.symmetric(vertical: desktop ? 24 : 12, horizontal: 10),
      child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: content),
      ),
    ),
  );
  if (public) {
    // Trang web công khai: không có khung app, chỉ thanh địa chỉ của trình duyệt (vẽ minh hoạ).
    return Column(
      children: [
        Container(
          height: 44,
          color: p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.lock, size: 15, color: p.sub),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(16)),
                  child: _t(c, 'chat.example.com/__apps/forms/f/k7Qm2xR9', size: 13, color: p.sub, lines: 1),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: scroll),
      ],
    );
  }
  return Column(
    children: [
      _appBar(c, 'Biểu mẫu', actions: [_icon(c, Icons.more_vert)]),
      Expanded(child: scroll),
    ],
  );
}

/// Đã gửi xong.
Widget doneScreen(BuildContext c) {
  final p = Pal.of(c);
  return Container(
    color: _tint(_theme, p.bg != Colors.white),
    padding: const EdgeInsets.all(12),
    child: Column(
      children: [
        const SizedBox(height: 12),
        _Card(
          top: _theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _t(c, _formTitle, size: 22, w: FontWeight.w500),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF2E9D57), size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: _t(c, 'Đã ghi nhận câu trả lời. Cảm ơn anh/chị!')),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Gửi câu trả lời khác',
                style: TextStyle(color: p.accentText, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                'Xem lại câu trả lời của tôi',
                style: TextStyle(color: p.accentText, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Câu trả lời — tóm tắt.
Widget responsesScreen(BuildContext c, {bool desktop = true}) {
  final p = Pal.of(c);
  final summary = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _t(c, '128 câu trả lời', size: 22, w: FontWeight.w500),
                const Spacer(),
                if (desktop) ...[
                  _btn('Xuất Excel', icon: Icons.table_view_outlined, outline: true),
                  const SizedBox(width: 8),
                  _btn('Lưu vào Drive', icon: Icons.drive_folder_upload_outlined, outline: true),
                  const SizedBox(width: 4),
                ],
                _icon(c, Icons.more_vert),
              ],
            ),
            const SizedBox(height: 4),
            _switch(c, 'Đang nhận câu trả lời', true, help: 'Tự đóng lúc 23:59 ngày 30/11/2026 · 128 / 500 câu trả lời'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(c, 'Tóm tắt', bg: p.chipSelBg, fg: p.chipSelFg),
                _pill(c, 'Theo câu hỏi'),
                _pill(c, 'Từng câu trả lời'),
                _pill(c, '7 ngày qua', icon: Icons.filter_list),
                _pill(c, 'Báo trong chat: Bật', icon: Icons.notifications_active_outlined),
              ],
            ),
          ],
        ),
      ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _t(c, 'Mức độ hài lòng chung', size: 15, w: FontWeight.w500),
            _sub(c, '128 câu trả lời · trung bình 4,2 / 5'),
            const SizedBox(height: 12),
            _histogram(c, [3, 6, 14, 48, 57], h: desktop ? 120 : 90),
          ],
        ),
      ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _t(c, 'Anh/chị có giới thiệu dịch vụ cho người quen không?', size: 15, w: FontWeight.w500),
            _sub(c, '126 câu trả lời'),
            const SizedBox(height: 14),
            _donut(c, [('Có, chắc chắn', 71), ('Có thể', 41), ('Không', 14)], size: desktop ? 140 : 110),
          ],
        ),
      ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _t(c, 'Anh/chị đã dùng những dịch vụ nào?', size: 15, w: FontWeight.w500),
            _sub(c, '121 câu trả lời · chọn nhiều'),
            const SizedBox(height: 12),
            _bar(c, 'Lắp đặt mới', 52, 121, labelW: desktop ? 170 : 110),
            _bar(c, 'Bảo trì định kỳ', 96, 121, labelW: desktop ? 170 : 110),
            _bar(c, 'Sửa chữa khẩn cấp', 23, 121, labelW: desktop ? 170 : 110),
            _bar(c, 'Khác', 6, 121, labelW: desktop ? 170 : 110),
          ],
        ),
      ),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _t(c, 'Góp ý thêm', size: 15, w: FontWeight.w500),
            _sub(c, '58 câu trả lời'),
            const SizedBox(height: 10),
            for (final s in [
              'Kỹ thuật viên đến đúng giờ, làm việc cẩn thận.',
              'Mong có thêm kênh báo sự cố qua chat.',
              'Giá bảo trì hơi cao so với năm ngoái.',
            ])
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6)),
                child: _t(c, s, size: 13.5),
              ),
            Text(
              'Xem tất cả 58',
              style: TextStyle(color: p.accentText, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ],
  );
  return Column(
    children: [
      _appBar(
        c,
        _formTitle,
        back: !desktop,
        actions: [
          _icon(c, Icons.palette_outlined),
          _icon(c, Icons.visibility_outlined),
          if (desktop) ...[const SizedBox(width: 8), _btn('Gửi', icon: Icons.send), const SizedBox(width: 8)] else _icon(c, Icons.send_outlined),
        ],
        bottom: _tabs(c, ['Câu hỏi', 'Câu trả lời  128', 'Tự động hoá', 'Cài đặt'], 1),
      ),
      Expanded(
        child: Container(
          color: _tint(_theme, p.bg != Colors.white),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: desktop ? 0 : 10),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: summary),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Từng câu trả lời (điện thoại).
Widget oneResponseScreen(BuildContext c) {
  final p = Pal.of(c);
  Widget a(String q, String v) => _Card(
    pad: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_sub(c, q, size: 12.5), const SizedBox(height: 4), _t(c, v, size: 15)]),
  );
  return Column(
    children: [
      _appBar(c, 'Câu trả lời 37 / 128', actions: [_icon(c, Icons.chevron_left), _icon(c, Icons.chevron_right), _icon(c, Icons.more_vert)]),
      Expanded(
        child: Container(
          color: _tint(_theme, p.bg != Colors.white),
          child: ListView(
            padding: const EdgeInsets.all(10),
            children: [
              _Card(
                pad: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: p.surface2,
                          child: Icon(Icons.public, size: 18, color: p.sub),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _t(c, 'Khách (link công khai)', w: FontWeight.w600),
                              _sub(c, '14/11/2026 09:42 · 1 phút 48 giây'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(c, 'Đã tạo luồng #QT-2041', icon: Icons.account_tree_outlined, bg: _tint(_theme, p.bg != Colors.white), fg: _theme),
                        _pill(c, 'Việc Todo cho Nam', icon: Icons.check_box_outlined),
                      ],
                    ),
                  ],
                ),
              ),
              a('Họ và tên', 'Trần Minh Anh'),
              a('Số điện thoại', '0912 345 678'),
              a('Mức độ hài lòng chung', '4 / 5'),
              a('Anh/chị đã dùng những dịch vụ nào?', 'Lắp đặt mới, Bảo trì định kỳ'),
              a('Anh/chị có giới thiệu dịch vụ cho người quen không?', 'Có, chắc chắn'),
              _Card(
                pad: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sub(c, 'Đính kèm ảnh (nếu có)'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final col in [const Color(0xFF7FB3D5), const Color(0xFFA9CCE3)])
                          Container(
                            width: 84,
                            height: 64,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.image, color: Colors.white),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Hộp thoại Gửi / chia sẻ.
Widget shareDialog(BuildContext c) {
  final p = Pal.of(c);
  Widget seg(String s, IconData i, bool on, String help) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: on ? _tint(_theme, p.bg != Colors.white) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? _theme : p.divider, width: on ? 1.6 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(i, color: on ? _theme : p.sub),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _t(c, s, w: FontWeight.w600),
                const SizedBox(height: 2),
                _sub(c, help, size: 12),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return Container(
    color: Colors.black.withValues(alpha: .45),
    alignment: Alignment.center,
    child: Container(
      width: 620,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: p.bg == Colors.white ? Colors.white : p.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _t(c, 'Gửi biểu mẫu', size: 20, w: FontWeight.w600),
              const Spacer(),
              Icon(Icons.close, color: p.sub),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              seg('Nội bộ', Icons.lock_outline, false, 'Người trong công ty, đăng nhập Flygo'),
              const SizedBox(width: 10),
              seg('Công khai', Icons.public, true, 'Ai có link đều điền được, không cần đăng nhập'),
            ],
          ),
          const SizedBox(height: 16),
          _sub(c, 'Link'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)),
                  child: _t(c, 'https://chat.example.com/__apps/forms/f/k7Qm2xR9', size: 13.5, lines: 1),
                ),
              ),
              const SizedBox(width: 8),
              _btn('Sao chép', icon: Icons.copy),
              const SizedBox(width: 6),
              _btn('QR', icon: Icons.qr_code_2, outline: true),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _pill(c, 'Gửi vào nhóm chat…', icon: Icons.chat_bubble_outline),
              const SizedBox(width: 8),
              _pill(c, 'Nhúng vào web (iframe)', icon: Icons.code),
              const SizedBox(width: 8),
              _pill(c, 'Đổi link', icon: Icons.refresh),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: p.divider),
          const SizedBox(height: 6),
          _switch(c, 'Giới hạn mỗi thiết bị / mỗi người 1 lần', true, help: 'Công khai: theo thiết bị + giới hạn tốc độ theo IP. Nội bộ: theo tài khoản'),
          _switch(c, 'Cho sửa sau khi gửi', false),
          _switch(c, 'Đóng lúc 23:59 · 30/11/2026, hoặc khi đủ 500 câu trả lời', true),
          const SizedBox(height: 6),
          Divider(height: 1, color: p.divider),
          const SizedBox(height: 10),
          _sub(c, 'Người cùng sửa biểu mẫu và xem câu trả lời'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(c, 'Bạn (chủ)', icon: Icons.person),
              _pill(c, 'Phòng CSKH · Xem câu trả lời', icon: Icons.groups_outlined),
              _pill(c, 'Lan · Có thể sửa', icon: Icons.person_outline),
              _pill(c, 'Thêm người…', icon: Icons.person_add_alt, bg: p.chipSelBg, fg: p.chipSelFg),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Cài đặt: hành động khi có câu trả lời (Flows, Todo, chat).
Widget settingsScreen(BuildContext c) {
  final p = Pal.of(c);
  Widget sec(String title, List<Widget> kids) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _t(c, title, size: 16, w: FontWeight.w600),
        const SizedBox(height: 6),
        ...kids,
      ],
    ),
  );
  Widget pick(String label, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: _t(c, label, size: 14)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: p.divider),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _t(c, v, size: 13.5),
              const SizedBox(width: 6),
              Icon(Icons.arrow_drop_down, color: p.sub),
            ],
          ),
        ),
      ],
    ),
  );
  return Column(
    children: [
      _appBar(
        c,
        _formTitle,
        back: false,
        actions: [
          _icon(c, Icons.palette_outlined),
          _icon(c, Icons.visibility_outlined),
          const SizedBox(width: 8),
          _btn('Gửi', icon: Icons.send),
          const SizedBox(width: 8),
        ],
        bottom: _tabs(c, ['Câu hỏi', 'Câu trả lời  128', 'Tự động hoá', 'Cài đặt'], 2),
      ),
      Expanded(
        child: Container(
          color: _tint(_theme, p.bg != Colors.white),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    sec('Khi có câu trả lời mới', [
                      _switch(c, 'Báo trong chat', true, help: 'Bot "Biểu mẫu" nhắn riêng cho chủ và người cùng sửa; gom tối đa 1 tin / 10 phút'),
                      pick('Hoặc đăng vào nhóm', 'Nhóm CSKH'),
                      const SizedBox(height: 6),
                      Divider(height: 1, color: p.divider),
                      _switch(c, 'Bắt đầu quy trình (Flows)', true, help: 'Mỗi câu trả lời tạo một luồng; các câu hỏi thành dữ liệu form.* của luồng'),
                      pick('Quy trình', 'Xử lý phản hồi khách hàng'),
                      pick('Chỉ khi', 'Mức độ hài lòng ≤ 2'),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _sub(c, 'Ghép trường:'),
                            _pill(c, 'Họ và tên » ten_khach'),
                            _pill(c, 'Số điện thoại » sdt'),
                            _pill(c, 'Mức độ hài lòng » diem'),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: p.divider),
                      _switch(c, 'Tạo việc Todo', false, help: 'Giao cho một người, tiêu đề lấy từ câu trả lời'),
                    ]),
                    sec('Câu trả lời', [
                      _switch(c, 'Ghi tên / email người điền (nội bộ)', true),
                      _switch(c, 'Cho người điền xem tóm tắt kết quả', false),
                      _switch(c, 'Xáo thứ tự câu hỏi', false),
                      pick('Lưu tệp đính kèm', 'Kho Biểu mẫu (mặc định)'),
                    ]),
                    sec('Trình bày', [
                      Row(
                        children: [
                          _t(c, 'Màu chủ đề', size: 14),
                          const Spacer(),
                          for (final col in [
                            _theme,
                            const Color(0xFF1E7BFF),
                            const Color(0xFF5B6CC4),
                            const Color(0xFFE4A11B),
                            const Color(0xFFD9534F),
                            const Color(0xFF2E7D32),
                          ])
                            Container(
                              width: 26,
                              height: 26,
                              margin: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                color: col,
                                shape: BoxShape.circle,
                                border: col == _theme ? Border.all(color: p.text, width: 2) : null,
                              ),
                            ),
                        ],
                      ),
                      _switch(c, 'Thanh tiến độ', true),
                      pick('Lời cảm ơn sau khi gửi', 'Đã ghi nhận câu trả lời…'),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Tự động hoá: tạo quy trình Flows mới ngay từ biểu mẫu (bước Bắt đầu = biểu mẫu này).
Widget automationScreen(BuildContext c, {bool desktop = true}) {
  final p = Pal.of(c);
  Widget node(IconData i, Color col, String title, String sub, {Widget? extra}) => Container(
    margin: const EdgeInsets.symmetric(vertical: 2),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: p.bg == Colors.white ? Colors.white : p.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.divider),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: _tint(col, p.bg != Colors.white), borderRadius: BorderRadius.circular(9)),
          child: Icon(i, size: 19, color: col),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _t(c, title, w: FontWeight.w600),
              const SizedBox(height: 2),
              _sub(c, sub),
              if (extra != null) ...[const SizedBox(height: 8), extra],
            ],
          ),
        ),
        Icon(Icons.more_vert, size: 18, color: p.sub),
      ],
    ),
  );
  Widget link({String? label}) => SizedBox(
    height: label == null ? 22 : 34,
    child: Row(
      children: [
        const SizedBox(width: 30),
        Container(width: 2, color: p.divider),
        if (label != null) ...[const SizedBox(width: 10), _pill(c, label, icon: Icons.alt_route)],
      ],
    ),
  );
  Widget add() => Padding(
    padding: const EdgeInsets.only(left: 18, top: 2, bottom: 2),
    child: Row(
      children: [
        Icon(Icons.add_circle, size: 26, color: _theme),
        const SizedBox(width: 8),
        _t(c, 'Thêm bước', size: 13, color: _theme, w: FontWeight.w600),
      ],
    ),
  );
  final flow = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _t(c, 'Xử lý phản hồi khách hàng', size: 18, w: FontWeight.w600)),
                _pill(c, 'Đang bật', icon: Icons.circle, fg: const Color(0xFF2E9D57)),
              ],
            ),
            const SizedBox(height: 4),
            _sub(c, 'Quy trình Flows tạo từ biểu mẫu này · 31 luồng · lỗi 0'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(c, 'Thêm quy trình mới', icon: Icons.add, bg: p.chipSelBg, fg: p.chipSelFg),
                _pill(c, 'Từ mẫu: Duyệt đăng ký / Giao việc / Báo khẩn', icon: Icons.auto_awesome_motion_outlined),
                _pill(c, 'Mở trong Flows (nâng cao)', icon: Icons.open_in_new),
                _pill(c, 'Chạy thử với câu trả lời #37', icon: Icons.play_arrow_outlined),
              ],
            ),
          ],
        ),
      ),
      node(
        Icons.assignment_outlined,
        _theme,
        'Khi có câu trả lời',
        'Biểu mẫu này · mỗi câu trả lời tạo 1 luồng; câu hỏi là form.ten_khach, form.sdt, form.diem…',
      ),
      link(),
      node(
        Icons.call_split,
        const Color(0xFF5B6CC4),
        'Điều kiện',
        'Mức độ hài lòng ≤ 2',
        extra: Wrap(spacing: 6, children: [_pill(c, 'Đúng » nhánh trái'), _pill(c, 'Sai » kết thúc')]),
      ),
      link(label: 'Đúng'),
      node(
        Icons.chat_bubble_outline,
        const Color(0xFFE4A11B),
        'Nhắn vào nhóm CSKH',
        '"Khách {{form.ten_khach}} ({{form.sdt}}) chấm {{form.diem}}/5 — cần gọi lại"',
      ),
      link(),
      node(
        Icons.person_pin_circle_outlined,
        const Color(0xFFD9534F),
        'Giao việc cho trưởng ca CSKH',
        'Form việc: Kết quả gọi lại, Ghi chú · nhắc sau 4 giờ, leo thang sau 1 ngày',
      ),
      link(),
      node(Icons.how_to_reg_outlined, const Color(0xFF2E7D32), 'Duyệt: Trưởng phòng CSKH', 'Chỉ khi đề xuất bồi hoàn > 0 · Duyệt / Từ chối / Trả lại'),
      link(),
      node(Icons.check_box_outlined, const Color(0xFF8E9AAF), 'Tạo việc Todo', 'Cho người đã gọi lại: "Theo dõi khách {{form.ten_khach}} sau 7 ngày"'),
      link(),
      add(),
    ],
  );
  final palette = _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _t(c, 'Bước có thể thêm', size: 15, w: FontWeight.w600),
        const SizedBox(height: 8),
        for (final b in [
          (Icons.call_split, 'Điều kiện / rẽ nhánh'),
          (Icons.how_to_reg_outlined, 'Duyệt (1 người / nhiều người)'),
          (Icons.person_pin_circle_outlined, 'Giao việc kèm form'),
          (Icons.chat_bubble_outline, 'Nhắn chat / nhóm'),
          (Icons.check_box_outlined, 'Tạo việc Todo'),
          (Icons.mail_outline, 'Gửi email'),
          (Icons.description_outlined, 'Tạo tài liệu từ mẫu'),
          (Icons.auto_awesome_outlined, 'AI: phân loại, tóm tắt, trả lời'),
          (Icons.extension_outlined, 'Gọi công cụ MCP'),
          (Icons.schedule, 'Chờ / hẹn giờ'),
          (Icons.webhook_outlined, 'Gọi HTTP (webhook ra)'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(b.$1, size: 18, color: p.sub),
                const SizedBox(width: 10),
                _t(c, b.$2, size: 13.5),
              ],
            ),
          ),
      ],
    ),
  );
  return Column(
    children: [
      _appBar(
        c,
        _formTitle,
        back: !desktop,
        actions: [
          if (desktop) ...[
            _icon(c, Icons.palette_outlined),
            _icon(c, Icons.visibility_outlined),
            const SizedBox(width: 8),
            _btn('Gửi', icon: Icons.send),
            const SizedBox(width: 8),
          ] else
            _icon(c, Icons.send_outlined),
        ],
        bottom: _tabs(c, desktop ? ['Câu hỏi', 'Câu trả lời  128', 'Tự động hoá', 'Cài đặt'] : ['Câu hỏi', 'Trả lời', 'Tự động hoá', 'Cài đặt'], 2),
      ),
      Expanded(
        child: Container(
          color: _tint(_theme, p.bg != Colors.white),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: desktop ? 0 : 10),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: desktop ? 1040 : 760),
                child: desktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: flow),
                          const SizedBox(width: 16),
                          SizedBox(width: 280, child: palette),
                        ],
                      )
                    : flow,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

void main() {
  final out = Platform.environment['MK_OUT'];

  Future<void> shot(WidgetTester t, String name, Size size, Widget Function(BuildContext c) build, {bool dark = false}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    final theme = buildTheme(dark ? Brightness.dark : Brightness.light);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: RepaintBoundary(
          key: key,
          child: Builder(
            builder: (c) => Material(
              color: Pal.of(c).bg,
              child: Builder(builder: build),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  setUpAll(() async {
    if (out != null) await _fonts();
  });

  const desk = Size(1280, 860), phone = Size(412, 900);
  testWidgets('mockup biểu mẫu', (t) async {
    await shot(t, '01-home-desktop', desk, (c) => formsHome(c, desktop: true));
    await shot(t, '02-home-phone', phone, (c) => formsHome(c));
    await shot(t, '03-builder-desktop', desk, (c) => builderScreen(c));
    await shot(t, '04-builder-phone', phone, (c) => builderScreen(c, desktop: false));
    await shot(t, '05-builder-desktop-dark', desk, (c) => builderScreen(c), dark: true);
    await shot(t, '06-share-desktop', desk, (c) => Stack(children: [builderScreen(c), shareDialog(c)]));
    await shot(t, '07-settings-desktop', desk, (c) => settingsScreen(c));
    await shot(t, '17-automation-desktop', desk, (c) => automationScreen(c));
    await shot(t, '18-automation-phone', const Size(412, 1300), (c) => automationScreen(c, desktop: false));
    await shot(t, '08-fill-phone', phone, (c) => fillScreen(c));
    await shot(t, '09-fill-phone-dark', phone, (c) => fillScreen(c), dark: true);
    await shot(t, '10-done-phone', const Size(412, 420), (c) => doneScreen(c));
    await shot(t, '11-responses-desktop', desk, (c) => responsesScreen(c));
    await shot(t, '12-responses-phone', phone, (c) => responsesScreen(c, desktop: false));
    await shot(t, '13-response-one-phone', phone, (c) => oneResponseScreen(c));
    await shot(t, '14-public-desktop', desk, (c) => fillScreen(c, public: true, desktop: true));
    await shot(t, '15-public-phone', phone, (c) => fillScreen(c, public: true));
    await shot(t, '16-public-phone-dark', phone, (c) => fillScreen(c, public: true), dark: true);
    // Chỉ để chụp ảnh duyệt thiết kế: không có MK_OUT thì không nạp font thật, chữ đo khác nên bỏ qua.
  }, skip: out == null);
}
