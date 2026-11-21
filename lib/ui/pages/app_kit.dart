import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import 'stage_frame.dart';

// Bộ khung chung cho "mỗi trang là một app" (mockup Sếp duyệt 2026-11-21): kiểu màn hình, phạm vi app (bảng màu, đang
// sửa, nút Xong), menu nổi dùng chung và các ô điều khiển. Mọi màu lấy từ StageTheme nên tự có bản tối / sáng.
// Quy tắc: app không mở hộp thoại / bảng kéo lên / route mới; hỏi lại bằng AppButton(confirm: true).

/// Kiểu màn hình nơi app đang hiện.
enum AppForm {
  /// Điện thoại dọc: sân khấu trên, phần tương tác giữa, điều khiển chủ trang dưới cùng.
  phonePortrait,

  /// Điện thoại ngang: sân khấu kín chiều cao, cột phải hẹp cho thao tác.
  phoneLandscape,

  /// Máy tính / máy tính bảng: sân khấu trái, cột phải rộng (tương tác + điều khiển).
  wide,

  /// TV / màn hình phòng: chỉ xem, chữ to, mã QR.
  tv,
}

/// Chọn kiểu màn hình theo kích thước vùng hiện app.
AppForm appFormFor(Size s, {bool tv = false}) {
  if (tv) return AppForm.tv;
  if (s.width < s.height) return AppForm.phonePortrait;
  return s.shortestSide < 520 ? AppForm.phoneLandscape : AppForm.wide;
}

/// Phạm vi của một app: kiểu màn hình, bảng màu, đang sửa tại chỗ. Đọc bằng `AppScope.of(context)`.
class AppScope extends InheritedWidget {
  final AppForm form;
  final StageTheme theme;

  /// Chủ trang đang sửa tại chỗ (menu "Sửa"): phần xem vẽ các ô sửa (AppInlineField).
  final bool editing;
  final AppEditHub hub;
  const AppScope({super.key, required this.form, required this.theme, this.editing = false, required this.hub, required super.child});

  static final _fallback = AppEditHub();

  /// Ngoài khung app (ảnh thu nhỏ, test cũ): tối, máy tính, không sửa.
  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>() ?? AppScope(form: AppForm.wide, theme: StageMetrics.themeOf(context), hub: _fallback, child: const SizedBox());

  /// Phạm vi app nếu đang ở trong vỏ app (bảng trang), null = ngoài (ô sân khấu của màn họp, TV, ảnh thu nhỏ).
  static AppScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>();

  bool get interactive => form != AppForm.tv;
  bool get compact => form == AppForm.phoneLandscape;

  /// App giữ bản nháp trong State của nó và đăng ký hàm lưu: nút Xong của khung gọi hàm này (false = ở lại chế độ sửa,
  /// vd thiếu dữ liệu). Gọi lại trong mỗi lần build là được (hàm mới thay hàm cũ). Huỷ chỉ thoát chế độ sửa.
  void registerEdit(Future<bool> Function() onDone) => hub.onDone = onDone;

  @override
  bool updateShouldNotify(AppScope old) => old.form != form || old.editing != editing || old.theme.light != theme.light || old.theme.accent != theme.accent;
}

/// Nơi khung app giữ hàm lưu bản nháp của app đang sửa.
class AppEditHub {
  Future<bool> Function()? onDone;
}

/// Một mục menu (menu của trang, menu của từng mục trong app).
class PageMenuItem {
  final String label;
  final IconData icon;
  final bool danger;
  final bool enabled;

  /// Màu riêng (vd Trình chiếu xanh ngọc); null = chữ thường / đỏ nếu [danger].
  final Color? color;
  final Future<void> Function()? onTap;
  const PageMenuItem({required this.label, required this.icon, this.onTap, this.danger = false, this.enabled = true, this.color});
}

/// Menu nổi ngay tại chỗ nhấn (nhấn giữ / chuột phải / nút ⋯), cùng một kiểu cho menu trang và menu từng mục trong app.
/// [at]: điểm nhấn (toạ độ toàn màn hình); null = mép của widget [context]. Trả về mục đã chọn (đã chạy onTap).
Future<PageMenuItem?> showAppMenu(BuildContext context, {Offset? at, required List<PageMenuItem> items}) async {
  if (items.isEmpty) return null;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final box = context.findRenderObject() as RenderBox?;
  final r = at != null ? at & const Size(1, 1) : (box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size);
  final origin = overlay.globalToLocal(r.topLeft);
  final light = StageMetrics.of(context)?.theme.light ?? false;
  final fg = light ? const Color(0xFF151A22) : Colors.white;
  final i = await showMenu<int>(
    context: context,
    color: light ? Colors.white : const Color(0xFF2B2E33),
    elevation: 12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: light ? const BorderSide(color: Color(0xFFDDE2EA)) : BorderSide.none),
    position: RelativeRect.fromRect(origin & r.size, Offset.zero & overlay.size),
    items: [
      for (final (n, it) in items.indexed)
        PopupMenuItem<int>(
          value: n,
          enabled: it.enabled,
          height: 44,
          child: Builder(builder: (_) {
            final c = !it.enabled ? fg.withValues(alpha: .32) : it.color ?? (it.danger ? (light ? const Color(0xFFC2272F) : const Color(0xFFF28B82)) : fg);
            return Row(children: [Icon(it.icon, size: 20, color: c), const SizedBox(width: 12), Flexible(child: Text(it.label, style: TextStyle(color: c, fontSize: 15)))]);
          }),
        ),
    ],
  );
  if (i == null) return null;
  await items[i].onTap?.call();
  return items[i];
}

// ---------------------------------------------------------------------------------------------------------------------
// Ô điều khiển dùng chung. Kích thước chạm tối thiểu 44px.

StageTheme _t(BuildContext c) => AppScope.of(c).theme;

/// Nền của khối điều khiển / bảng tương tác (thẻ tối #171A20 / trắng viền mảnh).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  /// Viền nhấn (mục đang chọn / đang bàn).
  final Color? outline;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.outline});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (t.light ? Colors.white : const Color(0xFF171A20)),
        borderRadius: BorderRadius.circular(16),
        border: outline != null ? Border.all(color: outline!, width: 1.5) : (t.light ? Border.all(color: const Color(0xFFDDE2EA)) : null),
      ),
      child: child,
    );
  }
}

/// Nhãn nhóm chữ hoa nhỏ ("ĐIỀU KHIỂN", "HÀNG CHỜ").
class AppSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const AppSectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: TextStyle(color: t.sub, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.2))),
        ?trailing,
      ]),
    );
  }
}

enum AppButtonKind { primary, tonal, danger, success, warn }

/// Nút của app. [confirm]: bấm lần đầu đổi thành "Bấm lần nữa để …" (3 giây), bấm lần hai mới chạy — thay hộp thoại hỏi lại.
class AppButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final AppButtonKind kind;
  final Future<void> Function()? onPressed;
  final bool confirm;

  /// Chữ khi chờ bấm lần hai; null = "Bấm lần nữa để <label thường>".
  final String? confirmLabel;
  final double height;
  final bool expand;
  const AppButton(this.label, {super.key, this.icon, this.kind = AppButtonKind.tonal, required this.onPressed, this.confirm = false, this.confirmLabel, this.height = 46, this.expand = true});
  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _arm = false, _busy = false;

  Future<void> _tap() async {
    if (widget.confirm && !_arm) {
      setState(() => _arm = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _arm = false);
      });
      return;
    }
    setState(() {
      _arm = false;
      _busy = true;
    });
    try {
      await widget.onPressed?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    final kind = _arm ? AppButtonKind.danger : widget.kind;
    final (bg, fg) = switch (kind) {
      AppButtonKind.primary => (t.accent, Colors.white),
      AppButtonKind.danger => (t.light ? const Color(0xFFFDE4E5) : const Color(0x33E5343D), t.light ? const Color(0xFFC2272F) : const Color(0xFFFFB4B4)),
      AppButtonKind.success => (t.light ? const Color(0xFFDDF5EA) : const Color(0x3338C793), t.light ? const Color(0xFF0E7C55) : const Color(0xFF9FE8C9)),
      AppButtonKind.warn => (t.light ? const Color(0xFFFFF1CC) : const Color(0x33F5B544), t.light ? const Color(0xFF7A5A00) : const Color(0xFFF8D58F)),
      AppButtonKind.tonal => (t.light ? const Color(0xFFE3E7EE) : const Color(0xFF262B33), t.text),
    };
    final text = _arm ? (widget.confirmLabel ?? tr('Bấm lần nữa để {0}', [widget.label.toLowerCase()])) : widget.label;
    final child = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (_busy)
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
      else if (widget.icon != null)
        Icon(widget.icon, size: 18, color: fg),
      if (_busy || widget.icon != null) const SizedBox(width: 8),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14.5))),
    ]);
    final enabled = widget.onPressed != null && !_busy;
    return Opacity(
      opacity: widget.onPressed == null ? .45 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? _tap : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(44, widget.height), minWidth: 44),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: widget.expand ? Center(child: child) : child),
          ),
        ),
      ),
    );
  }
}

/// Dòng công tắc ("Ẩn danh", "Đồng bộ cuộn cho cả phòng").
class AppToggleRow extends StatelessWidget {
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AppToggleRow(this.label, {super.key, this.sub, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(color: t.text, fontSize: 14)),
              if (sub != null) Text(sub!, style: TextStyle(color: t.sub, fontSize: 12)),
            ]),
          ),
          Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: t.accent),
        ]),
      ),
    );
  }
}

/// Dòng chọn có giá trị bên phải ("Người xem thấy kết quả · Sau khi chọn ›"); bấm để đổi / mở menu [AppSelectRow.menu].
class AppSelectRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const AppSelectRow(this.label, {super.key, required this.value, this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text, fontSize: 14))),
          Text('$value ›', style: TextStyle(color: t.light ? t.accent : const Color(0xFF9DBBFF), fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Chọn một trong vài kiểu (Bình chọn / Trắc nghiệm / Biểu quyết; Tự động / Lưới).
class AppSegmented<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T>? onChanged;
  const AppSegmented({super.key, required this.items, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: t.light ? const Color(0xFFE9EDF2) : const Color(0xFF1B1F27), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        for (final (v, label) in items)
          Expanded(
            child: Material(
              color: v == value ? (t.light ? Colors.white : const Color(0xFF2A3446)) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: onChanged == null ? null : () => onChanged!(v),
                child: SizedBox(
                  height: 38,
                  child: Center(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: v == value ? t.text : t.sub, fontSize: 13.5, fontWeight: v == value ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Chip nhỏ (lập trường, trạng thái, nhãn QUYẾT ĐỊNH / VIỆC).
class AppChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  const AppChip(this.label, {super.key, this.color, this.selected = false, this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    final c = color ?? t.accent;
    final body = Container(
      constraints: BoxConstraints(minHeight: onTap == null ? 22 : 34),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: t.light ? .14 : .22),
        borderRadius: BorderRadius.circular(999),
        border: selected ? Border.all(color: c, width: 1.5) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: _ink(c, t)), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: _ink(c, t), fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
    return onTap == null ? body : InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: body);
  }
}

/// Màu chữ đọc được trên nền nhạt của màu [c] (tối: sáng hơn, sáng: đậm hơn).
Color _ink(Color c, StageTheme t) => Color.lerp(c, t.light ? Colors.black : Colors.white, t.light ? .35 : .45)!;

/// Ô sửa tại chỗ trên trang (viền gạch xanh khi đang sửa). Ngoài chế độ sửa: chỉ hiện chữ với [style].
class AppInlineField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final TextStyle? style;
  final String? hint;
  final int? maxLines;
  final TextAlign textAlign;
  const AppInlineField({super.key, required this.value, required this.onChanged, this.style, this.hint, this.maxLines = 1, this.textAlign = TextAlign.start});
  @override
  State<AppInlineField> createState() => _AppInlineFieldState();
}

class _AppInlineFieldState extends State<AppInlineField> {
  late final _c = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(AppInlineField old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text && !_focus.hasFocus) _c.text = widget.value;
  }

  final _focus = FocusNode();
  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final style = widget.style ?? TextStyle(color: s.theme.text, fontSize: 15);
    if (!s.editing) return Text(widget.value.isEmpty ? (widget.hint ?? '') : widget.value, style: style, maxLines: widget.maxLines, textAlign: widget.textAlign);
    return CustomPaint(
      foregroundPainter: _DashPainter(s.theme.light ? s.theme.accent : const Color(0xFF9DBBFF)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: TextField(
          controller: _c,
          focusNode: _focus,
          style: style,
          maxLines: widget.maxLines,
          minLines: 1,
          textAlign: widget.textAlign,
          cursorColor: s.theme.accent,
          decoration: InputDecoration.collapsed(hintText: widget.hint, hintStyle: style.copyWith(color: s.theme.sub)),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}

/// Tăng / giảm số (phút bấm giờ, số người mỗi lần bốc, số phiếu mỗi người).
class AppNumberStepper extends StatelessWidget {
  final int value;
  final int min, max, step;
  final String Function(int v)? format;
  final ValueChanged<int>? onChanged;
  const AppNumberStepper({super.key, required this.value, this.min = 0, this.max = 999, this.step = 1, this.format, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    Widget b(IconData i, int to, String tip) => SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: tip,
            onPressed: onChanged == null || to < min || to > max ? null : () => onChanged!(to),
            icon: Icon(i, color: t.text),
            style: IconButton.styleFrom(backgroundColor: t.light ? const Color(0xFFE3E7EE) : const Color(0xFF262B33), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b(Icons.remove_rounded, value - step, tr('Giảm')),
      SizedBox(
        width: 64,
        child: Text(format?.call(value) ?? '$value',
            textAlign: TextAlign.center, style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
      ),
      b(Icons.add_rounded, value + step, tr('Tăng')),
    ]);
  }
}

/// Ảnh đại diện chữ cái (màu cố định theo tên).
class AppAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const AppAvatar(this.name, {super.key, this.size = 32, this.color});
  static const _colors = [Color(0xFF3D7BFF), Color(0xFFE8710A), Color(0xFF22B8A6), Color(0xFF9B6BFF), Color(0xFFC2477E), Color(0xFF2E9D5B)];
  @override
  Widget build(BuildContext context) {
    final n = name.trim();
    final c = color ?? _colors[n.codeUnits.fold<int>(0, (a, b) => a + b) % _colors.length];
    final letter = n.isEmpty ? '?' : n.split(RegExp(r'\s+')).last.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: Text(letter, style: TextStyle(color: Colors.white, fontSize: size * .42, fontWeight: FontWeight.w700)),
    );
  }
}

/// Vòng tiến độ (bấm giờ, số người đã chọn, tự bắt đầu sau…). [value] 0..1.
class AppProgressRing extends StatelessWidget {
  final double value;
  final double size, stroke;
  final Color? color;
  final Widget? child;
  const AppProgressRing({super.key, required this.value, this.size = 120, this.stroke = 10, this.color, this.child});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0, 1).toDouble(), color ?? t.accent, t.light ? const Color(0xFFE3E7EE) : const Color(0xFF1F2530), stroke),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v, w;
  final Color c, bg;
  _RingPainter(this.v, this.c, this.bg, this.w);
  @override
  void paint(Canvas canvas, Size s) {
    final r = (Offset.zero & s).deflate(w / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, p..color = bg);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, p..color = c);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.c != c || o.bg != bg;
}

/// Trạng thái trống của app (chưa có nội dung / chưa có ai trả lời).
class AppEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? action;
  const AppEmpty({super.key, required this.icon, required this.title, this.sub, this.action});
  @override
  Widget build(BuildContext context) {
    final t = _t(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: t.sub),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w700)),
          if (sub != null) ...[const SizedBox(height: 4), Text(sub!, textAlign: TextAlign.center, style: TextStyle(color: t.sub, fontSize: 13.5))],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      ),
    );
  }
}
