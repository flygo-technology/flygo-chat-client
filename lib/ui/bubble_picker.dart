import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';
import 'bubble_styles.dart';
import 'theme.dart';

/// Bong bóng mẫu có kiểu (dùng ở màn chọn kiểu và ô xem trước).
class StyledBubble extends StatelessWidget {
  final BubbleStyle? style;
  final Color fill;
  final Widget child;
  final bool top, bottom;
  final double scale;
  final BorderRadius radius;
  final EdgeInsets padding;
  /// Nền phía sau bong bóng (để thêm viền mảnh khi màu bong bóng gần trùng nền); mặc định nền chat.
  final Color? against;
  const StyledBubble({
    super.key,
    required this.style,
    required this.fill,
    required this.child,
    this.top = true,
    this.bottom = true,
    this.scale = 1,
    this.radius = const BorderRadius.all(Radius.circular(18)),
    this.padding = const EdgeInsets.fromLTRB(12, 7, 10, 7),
    this.against,
    this.mirror = false,
  });

  /// Tin người khác (căn trái): lật hình trang trí.
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final s = style;
    final pal = Pal.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(color: fill, borderRadius: radius, border: bubbleEdge(fill, against ?? pal.chatBg, pal.divider)),
      child: child,
    );
    if (s == null || !s.decorated) return box;
    return Padding(
      padding: EdgeInsets.only(top: top ? s.roomTop(scale) : 0, bottom: bottom ? s.roomBottom(scale) : 0),
      child: CustomPaint(foregroundPainter: BubbleDecoPainter(style: s, fill: fill, top: top, bottom: bottom, scale: scale, mirror: mirror), child: box),
    );
  }
}

/// Viền mảnh khi màu bong bóng gần trùng nền phía sau (bong bóng trắng trên nền sáng, đen trên nền tối).
Border? bubbleEdge(Color fill, Color bg, Color line) {
  final a = fill.computeLuminance(), b = bg.computeLuminance();
  final ratio = (math.max(a, b) + .05) / (math.min(a, b) + .05);
  return ratio < 1.3 ? Border.all(color: line, width: 1) : null;
}

/// Màn "Kiểu bong bóng" của một chat (trang riêng, có Huỷ / Lưu) — bọc [BubblePickerBody].
/// Trả về lựa chọn mới (`BubbleChoice('')` = về mặc định), null = huỷ.
class BubblePickerPage extends StatefulWidget {
  final BubbleChoice? current;
  /// Màu bong bóng mặc định của mình (khi chưa chọn kiểu).
  final Color defaultFill;
  const BubblePickerPage({super.key, this.current, required this.defaultFill});

  @override
  State<BubblePickerPage> createState() => _BubblePickerPageState();
}

class _BubblePickerPageState extends State<BubblePickerPage> {
  late BubbleChoice _choice = widget.current ?? const BubbleChoice('');

  bool get _changed => (widget.current ?? const BubbleChoice('')) != _choice;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.chatBg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 76,
        leading: TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'))),
        centerTitle: true,
        title: Text(tr('Kiểu bong bóng'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
        actions: [
          TextButton(
            onPressed: _changed ? () => Navigator.pop(context, _choice) : null,
            child: Text(tr('Lưu'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: BubblePickerBody(current: widget.current, defaultFill: widget.defaultFill, onChanged: (c) => setState(() => _choice = c)),
    );
  }
}

/// Nội dung màn chọn kiểu bong bóng (không Scaffold, không nút Lưu) để nhúng vào trang khác
/// (vd. tab "Bong bóng" của bảng giao diện chat). Gọi [onChanged] mỗi khi đổi; `BubbleChoice('')` = mặc định.
class BubblePickerBody extends StatefulWidget {
  final BubbleChoice? current;
  final Color defaultFill;
  final ValueChanged<BubbleChoice> onChanged;
  const BubblePickerBody({super.key, this.current, required this.defaultFill, required this.onChanged});

  @override
  State<BubblePickerBody> createState() => _BubblePickerBodyState();
}

class _BubblePickerBodyState extends State<BubblePickerBody> {
  late String _style = widget.current?.style ?? '';
  late Color? _color = widget.current?.color;
  final _scroll = ScrollController();
  final _groupKeys = <String, GlobalKey>{};

  BubbleStyle? get _def => bubbleStyleById(_style);
  Color get _fill => _color ?? _def?.color ?? widget.defaultFill;

  void _update(VoidCallback fn) {
    setState(fn);
    widget.onChanged(_style.isEmpty ? const BubbleChoice('') : BubbleChoice(_style, _color));
  }

  Future<void> _customColor() async {
    final c = await pickBubbleColor(context, _fill);
    if (c == null || !mounted) return;
    _update(() {
      _color = c;
      if (_style.isEmpty) _style = kBubblePlain;
    });
  }

  void _jump(String group) {
    final ctx = _groupKeys[group]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final styles = bubbleStyles;
    final grid = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: wide ? 124 : 100,
      mainAxisExtent: 112,
      crossAxisSpacing: 4,
      mainAxisSpacing: 6,
    );
    Widget tile(BubbleStyle s) => _StyleTile(
          style: s,
          fill: _style == s.id ? _fill : (_color ?? s.color),
          name: s.name,
          selected: _style == s.id,
          onTap: () => _update(() => _style = s.id),
        );
    return Column(children: [
      _Preview(style: _def, fill: _fill),
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: pal.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 12, offset: const Offset(0, -2))],
          ),
          child: Column(children: [
            // Chip nhảy tới từng nhóm chủ đề.
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                children: [
                  for (final (id, name) in bubbleGroups)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(name),
                        onPressed: () => _jump(id),
                        backgroundColor: _def?.group == id ? pal.chipSelBg : pal.surface2,
                        labelStyle: TextStyle(color: _def?.group == id ? pal.chipSelFg : pal.text, fontWeight: FontWeight.w600, fontSize: 13),
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: CustomScrollView(controller: _scroll, slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                    child: Text(tr('Chỉ bạn đổi kiểu tin mình gửi trong chat này. Áp dụng cho các tin gửi sau khi lưu; mọi người đều thấy.'),
                        style: TextStyle(color: pal.sub, fontSize: 13)),
                  ),
                ),
                SliverToBoxAdapter(child: _section(pal, tr('Màu nền'))),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      children: [
                        _Swatch(
                          selected: _color == null,
                          color: _def?.color ?? widget.defaultFill,
                          label: tr('Theo kiểu'),
                          onTap: () => _update(() => _color = null),
                        ),
                        _Swatch(
                          selected: _color != null && !bubbleSwatches.contains(_color),
                          color: _color != null && !bubbleSwatches.contains(_color) ? _color! : null,
                          label: tr('Tuỳ chỉnh'),
                          onTap: _customColor,
                        ),
                        for (final c in bubbleSwatches)
                          _Swatch(
                            selected: _color == c,
                            color: c,
                            onTap: () => _update(() {
                              _color = c;
                              if (_style.isEmpty) _style = kBubblePlain;
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                  sliver: SliverGrid(
                    gridDelegate: grid,
                    delegate: SliverChildListDelegate([
                      _StyleTile(
                        style: null,
                        fill: widget.defaultFill,
                        name: tr('Mặc định'),
                        selected: _style.isEmpty,
                        onTap: () => _update(() {
                          _style = '';
                          _color = null;
                        }),
                      ),
                      for (final s in styles.where((s) => s.group.isEmpty)) tile(s),
                    ]),
                  ),
                ),
                for (final (id, name) in bubbleGroups) ...[
                  SliverToBoxAdapter(child: KeyedSubtree(key: _groupKeys.putIfAbsent(id, GlobalKey.new), child: _section(pal, name))),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    sliver: SliverGrid(gridDelegate: grid, delegate: SliverChildListDelegate([for (final s in styles.where((s) => s.group == id)) tile(s)])),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _section(Pal pal, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
      );
}

class _Preview extends StatelessWidget {
  final BubbleStyle? style;
  final Color fill;
  const _Preview({required this.style, required this.fill});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final fg = bubbleTextOn(fill);
    Widget mine(String text, {required bool top, required bool bottom}) => Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: math.min(MediaQuery.sizeOf(context).width * .78, 460)),
            child: StyledBubble(
              style: style,
              fill: fill,
              top: top,
              bottom: bottom,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: text),
                  TextSpan(text: '  09:41', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .78))),
                ]),
                style: TextStyle(fontSize: 16, color: fg, height: 1.3),
              ),
            ),
          ),
        );
    return Container(
      color: pal.chatBg,
      padding: const EdgeInsets.fromLTRB(16, 12, 22, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
            decoration: BoxDecoration(color: pal.inBubble, borderRadius: BorderRadius.circular(18)),
            child: Text(tr('Chiều nay 3 giờ họp dự án nhé.'), style: TextStyle(fontSize: 16, color: pal.text, height: 1.3)),
          ),
        ),
        const SizedBox(height: 8),
        mine(tr('Dạ, em gửi báo cáo trước 2 giờ.'), top: true, bottom: false),
        const SizedBox(height: 3),
        mine(tr('Kiểu bong bóng mới của em đây!'), top: false, bottom: true),
      ]),
    );
  }
}

class _StyleTile extends StatelessWidget {
  final BubbleStyle? style;
  final Color fill;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  const _StyleTile({required this.style, required this.fill, required this.name, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected ? pal.surface2 : null,
            border: Border.all(color: selected ? pal.text : Colors.transparent, width: 1.6),
          ),
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Column(children: [
            SizedBox(
              height: 66,
              child: Center(
                child: StyledBubble(
                  style: style,
                  fill: fill,
                  scale: .72,
                  radius: BorderRadius.circular(12),
                  padding: EdgeInsets.zero,
                  against: selected ? pal.surface2 : pal.bg,
                  child: const SizedBox(width: 56, height: 22),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.2, color: pal.text, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final bool selected;
  final Color? color;
  final String? label;
  final VoidCallback onTap;
  const _Swatch({required this.selected, required this.color, this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: label ?? '#${bubbleHex(c!)}',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? pal.text : Colors.transparent, width: 2)),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c,
                gradient: c == null
                    ? const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red])
                    : null,
                border: Border.all(color: pal.divider),
              ),
              child: label != null && c != null && label != tr('Tuỳ chỉnh')
                  ? Icon(Icons.auto_awesome, size: 15, color: bubbleTextOn(c))
                  : c == null
                      ? const Icon(Icons.add, size: 18, color: Colors.white)
                      : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Chọn màu tuỳ chỉnh: bảng sắc độ / độ đậm + thanh màu + ô mã hex, có xem trước độ tương phản chữ.
Future<Color?> pickBubbleColor(BuildContext context, Color initial) => showDialog<Color>(
      context: context,
      builder: (ctx) => _ColorDialog(initial: initial),
    );

class _ColorDialog extends StatefulWidget {
  final Color initial;
  const _ColorDialog({required this.initial});

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: bubbleHex(widget.initial));

  void _set(HSVColor v) => setState(() {
        _hsv = v;
        _hex.text = bubbleHex(v.toColor());
      });

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = _hsv.toColor();
    return AlertDialog(
      title: Text(tr('Màu tuỳ chỉnh')),
      content: SizedBox(
        width: 300,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          LayoutBuilder(builder: (ctx, box) {
            final w = box.maxWidth;
            const h = 170.0;
            void at(Offset p) => _set(_hsv.withSaturation((p.dx / w).clamp(0.0, 1.0)).withValue(1 - (p.dy / h).clamp(0.0, 1.0)));
            return GestureDetector(
              onPanDown: (d) => at(d.localPosition),
              onPanUpdate: (d) => at(d.localPosition),
              child: CustomPaint(size: Size(w, h), painter: _SvPainter(_hsv)),
            );
          }),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (ctx, box) {
            final w = box.maxWidth;
            void at(Offset p) => _set(_hsv.withHue((p.dx / w).clamp(0.0, 1.0) * 359.9));
            return GestureDetector(
              onPanDown: (d) => at(d.localPosition),
              onPanUpdate: (d) => at(d.localPosition),
              child: CustomPaint(size: Size(w, 22), painter: _HuePainter(_hsv.hue)),
            );
          }),
          const SizedBox(height: 14),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.divider)),
              child: Text('Aa', style: TextStyle(color: bubbleTextOn(c), fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _hex,
                decoration: const InputDecoration(prefixText: '#', isDense: true, border: OutlineInputBorder()),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')), LengthLimitingTextInputFormatter(6)],
                onChanged: (v) {
                  final p = parseBubbleHex(v);
                  if (p != null) setState(() => _hsv = HSVColor.fromColor(p));
                },
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'))),
        FilledButton(onPressed: () => Navigator.pop(context, c), child: Text(tr('Chọn'))),
      ],
    );
  }
}

class _SvPainter extends CustomPainter {
  final HSVColor hsv;
  const _SvPainter(this.hsv);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
    canvas.save();
    canvas.clipRRect(rr);
    canvas.drawRect(r, Paint()..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()]).createShader(r));
    canvas.drawRect(r, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]).createShader(r));
    canvas.restore();
    final o = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(o, 8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.drawCircle(o, 8, Paint()..color = Colors.black26..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_SvPainter o) => o.hsv != hsv;
}

class _HuePainter extends CustomPainter {
  final double hue;
  const _HuePainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(size.height / 2)),
      Paint()..shader = LinearGradient(colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360, 1, 1).toColor()]).createShader(r),
    );
    final o = Offset(hue / 360 * size.width, size.height / 2);
    canvas.drawCircle(o, size.height / 2 + 1, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_HuePainter o) => o.hue != hue;
}
