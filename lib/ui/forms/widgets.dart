// Biểu mẫu: khối giao diện dùng chung (thẻ, nhãn, nút, công tắc) theo màu chủ đề của biểu mẫu.
import 'package:flutter/material.dart';

import '../theme.dart';

/// Màu chủ đề của biểu mẫu đang mở (con cháu đọc bằng FormTheme.of).
class FormTheme extends InheritedWidget {
  const FormTheme({super.key, required this.color, required super.child});
  final Color color;
  static Color of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<FormTheme>()?.color ?? const Color(0xFF0F8B8D);
  @override
  bool updateShouldNotify(FormTheme old) => old.color != color;
}

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color cardColor(BuildContext c) => isDark(c) ? Pal.of(c).surface : Colors.white;

/// Thẻ trắng bo góc; [top] = dải màu trên (thẻ tiêu đề), [left] = vạch trái (câu đang sửa).
class FCard extends StatelessWidget {
  const FCard({super.key, required this.child, this.top, this.left, this.pad = const EdgeInsets.all(20), this.error = false, this.onTap});
  final Widget child;
  final Color? top, left;
  final EdgeInsets pad;
  final bool error;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final body = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: error ? const Color(0xFFD93025) : p.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (top != null) Container(height: 8, color: top),
        // Vạch trái theo chiều cao nội dung (Stack + Positioned, không dùng IntrinsicHeight: đo sai với Wrap / Table).
        Material(
          type: MaterialType.transparency,
          child: Stack(children: [
            Padding(padding: left == null ? pad : pad.copyWith(left: pad.left + 5), child: child),
            if (left != null) Positioned(left: 0, top: 0, bottom: 0, width: 5, child: ColoredBox(color: left!)),
          ]),
        ),
      ]),
    );
    return onTap == null ? body : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.bg, this.fg, this.onTap});
  final String text;
  final IconData? icon;
  final Color? bg, fg;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg ?? p.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg ?? p.sub), const SizedBox(width: 4)],
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg ?? p.sub, fontWeight: FontWeight.w500))),
      ]),
    );
    return onTap == null ? w : InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: w);
  }
}

/// Dòng có công tắc + chú thích.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.help});
  final String label;
  final String? help;
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 14, color: p.text)),
              if (help != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(help!, style: TextStyle(fontSize: 12, color: p.sub))),
            ]),
          ),
          Switch(value: value, onChanged: onChanged, activeTrackColor: FormTheme.of(context)),
        ]),
      ),
    );
  }
}

/// Nhãn mục ("Mục 1 / 3") gắn trên thẻ.
class SectionBadge extends StatelessWidget {
  const SectionBadge(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: FormTheme.of(context), borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      );
}

/// Nền trang theo màu chủ đề, nội dung giữa (tối đa [max] px).
class FormBackdrop extends StatelessWidget {
  const FormBackdrop({super.key, required this.child, this.max = 760, this.padding, this.controller});
  final Widget child;
  final double max;
  final EdgeInsets? padding;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Container(
      color: Color.lerp(FormTheme.of(context), isDark(context) ? Colors.black : Colors.white, isDark(context) ? .8 : .9),
      child: SingleChildScrollView(
        controller: controller,
        padding: padding ?? EdgeInsets.fromLTRB(wide ? 16 : 10, 16, wide ? 16 : 10, 90),
        child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child)),
      ),
    );
  }
}

Text reqTitle(BuildContext c, String title, bool req, {double size = 15.5}) => Text.rich(
      TextSpan(children: [TextSpan(text: title.isEmpty ? 'Câu hỏi không có tiêu đề' : title), if (req) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFD93025)))]),
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w500, color: title.isEmpty ? Pal.of(c).sub : Pal.of(c).text, height: 1.35),
    );

Widget errorLine(String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFD93025)),
          const SizedBox(width: 6),
          Expanded(child: Text(e, style: const TextStyle(color: Color(0xFFD93025), fontSize: 12.5))),
        ]),
      );

/// Biểu tượng ô vuông của app (thanh tiêu đề).
class FormsIcon extends StatelessWidget {
  const FormsIcon({super.key, this.color, this.size = 30});
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color ?? FormTheme.of(context), borderRadius: BorderRadius.circular(size * .27)),
        child: Icon(Icons.assignment_outlined, color: Colors.white, size: size * .6),
      );
}
