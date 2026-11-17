// Hợp đồng: bảng màu (xanh dương đậm khi tối, sáng nhẹ khi sáng) và các mẩu giao diện dùng chung — thẻ, nhãn trạng thái,
// thanh tiến độ ký chia đoạn, avatar bên ký, chấm bước, chip lọc, hộp xác nhận.
import 'package:flutter/material.dart';

import '../theme.dart' show toast;
import 'model.dart';

class HdLook {
  HdLook(this.dark);
  factory HdLook.of(BuildContext c) => HdLook(Theme.of(c).brightness == Brightness.dark);
  final bool dark;
  Color get bg => dark ? const Color(0xFF0A1020) : const Color(0xFFF4F6FA);
  Color get nav => dark ? const Color(0xFF0E1628) : Colors.white;
  Color get card => dark ? const Color(0xFF121B30) : Colors.white;
  Color get card2 => dark ? const Color(0xFF18233D) : const Color(0xFFF0F3F8);
  Color get field => dark ? const Color(0xFF0F182B) : const Color(0xFFF4F6FA);
  Color get border => dark ? const Color(0xFF223050) : const Color(0xFFE1E6EF);
  Color get text => dark ? const Color(0xFFE9EEF8) : const Color(0xFF111827);
  Color get sub => dark ? const Color(0xFF8C98B2) : const Color(0xFF5E6B80);
  Color get faint => dark ? const Color(0xFF5E6B86) : const Color(0xFF98A2B3);
  Color get accent => dark ? const Color(0xFF2F80FF) : const Color(0xFF1E6FFF);
  Color get accentText => dark ? const Color(0xFF7DB2FF) : const Color(0xFF1559D6);
  Color get accentSoft => dark ? const Color(0xFF16305C) : const Color(0xFFE2ECFF);
  Color get ok => dark ? const Color(0xFF2FCB6E) : const Color(0xFF16A34A);
  Color get okSoft => dark ? const Color(0xFF123824) : const Color(0xFFDDF6E6);
  Color get warn => dark ? const Color(0xFFF5A524) : const Color(0xFFD97706);
  Color get warnSoft => dark ? const Color(0xFF3A2A10) : const Color(0xFFFDF0D8);
  Color get red => dark ? const Color(0xFFF26464) : const Color(0xFFDC2626);
  Color get redSoft => dark ? const Color(0xFF3B1820) : const Color(0xFFFDE3E3);
  Color get grey => dark ? const Color(0xFF9AA4B8) : const Color(0xFF64748B);
  Color get greySoft => dark ? const Color(0xFF243048) : const Color(0xFFE9EDF3);

  /// Màu chữ + màu nền của trạng thái hợp đồng.
  (Color, Color) status(String s) => switch (s) {
        'sending' => (accentText, accentSoft),
        'signed' => (ok, okSoft),
        'rejected' => (warn, warnSoft),
        'cancelled' => (red, redSoft),
        _ => (grey, greySoft),
      };
}

/// Khung thẻ bo góc có viền.
class HdCard extends StatelessWidget {
  const HdCard({super.key, required this.child, this.pad = const EdgeInsets.all(18), this.margin, this.color, this.borderColor, this.onTap, this.radius = 12});
  final Widget child;
  final EdgeInsets pad;
  final EdgeInsets? margin;
  final Color? color, borderColor;
  final VoidCallback? onTap;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(color: color ?? l.card, borderRadius: BorderRadius.circular(radius), border: Border.all(color: borderColor ?? l.border)),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: Padding(padding: pad, child: child)),
      ),
    );
  }
}

/// Tiêu đề trong thẻ: icon + chữ + phần phải.
class HdCardTitle extends StatelessWidget {
  const HdCardTitle(this.icon, this.text, {super.key, this.trailing, this.size = 17});
  final IconData icon;
  final String text;
  final Widget? trailing;
  final double size;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    return Row(children: [
      Icon(icon, size: size + 4, color: l.accentText),
      SizedBox(width: size * .6),
      Expanded(child: Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: l.text))),
      ?trailing,
    ]);
  }
}

/// Nhãn nhỏ nền nhạt.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.fg, required this.bg, this.icon, this.size = 12});
  final String text;
  final Color fg, bg;
  final IconData? icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: size * .7, vertical: size * .25),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: size + 3, color: fg), SizedBox(width: size * .35)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: fg))),
        ]),
      );
}

/// Nhãn trạng thái hợp đồng; đang ký mà quá hạn thì hiện "Quá hạn".
class StatusChip extends StatelessWidget {
  const StatusChip(this.c, {super.key, required this.now, this.size = 12, this.withProgress = false});
  final Contract c;
  final DateTime now;
  final double size;
  final bool withProgress;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    if (c.overdue(now)) return Pill('Quá hạn', fg: l.red, bg: l.redSoft, size: size);
    final (fg, bg) = l.status(c.status);
    final t = kStatusLabels[c.status] ?? c.status;
    return Pill(withProgress && c.status == 'sending' ? '$t ${c.signedCount}/${c.parties.length}' : t, fg: fg, bg: bg, size: size);
  }
}

/// Thanh tiến độ ký chia đoạn: mỗi bên một đoạn (đã ký xanh lá, đang tới lượt xanh dương, từ chối cam, chưa tới xám).
class SegProgress extends StatelessWidget {
  const SegProgress(this.c, {super.key, required this.now, this.height = 6, this.gap = 6});
  final Contract c;
  final DateTime now;
  final double height, gap;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final ps = c.parties;
    if (ps.isEmpty) return SizedBox(height: height);
    Color col(HdParty p) {
      if (p.signed) return l.ok;
      if (p.status == 'rejected') return l.warn;
      if (c.status == 'cancelled') return l.greySoft;
      if (p.waitingTurn) return c.overdue(now) ? l.red : l.accent;
      return l.greySoft;
    }

    return Row(children: [
      for (var i = 0; i < ps.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        Expanded(child: Container(height: height, decoration: BoxDecoration(color: col(ps[i]), borderRadius: BorderRadius.circular(height)))),
      ],
    ]);
  }
}

const _avatarColors = [
  [Color(0xFFF59E3B), Color(0xFFE2622B)],
  [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
  [Color(0xFF22C55E), Color(0xFF15803D)],
  [Color(0xFFA855F7), Color(0xFF7E22CE)],
  [Color(0xFF14B8A6), Color(0xFF0F766E)],
  [Color(0xFFEC4899), Color(0xFFBE185D)],
];

/// Ô vuông chữ viết tắt của bên ký.
class PartyAvatar extends StatelessWidget {
  const PartyAvatar(this.name, {super.key, this.index = 0, this.size = 48});
  final String name;
  final int index;
  final double size;
  @override
  Widget build(BuildContext context) {
    final g = _avatarColors[index % _avatarColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(size * .26)),
      child: Text(initials(name), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * .38)),
    );
  }
}

/// Avatar tròn chữ cái đầu (người phụ trách).
class OwnerDot extends StatelessWidget {
  const OwnerDot(this.name, {super.key, this.size = 30});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final n = name.trim();
    final ch = n.isEmpty ? '?' : n.split(RegExp(r'\s+')).last[0].toUpperCase();
    final g = _avatarColors[n.codeUnits.fold<int>(0, (a, b) => a + b) % _avatarColors.length];
    return Tooltip(
      message: name,
      child: CircleAvatar(radius: size / 2, backgroundColor: g[1], child: Text(ch, style: TextStyle(color: Colors.white, fontSize: size * .45, fontWeight: FontWeight.w700))),
    );
  }
}

enum HdStep { done, current, rejected, todo }

/// Chấm bước: đã xong (tick xanh), đang tới (số viền xanh), từ chối (x cam), chưa tới (số xám).
class StepDot extends StatelessWidget {
  const StepDot(this.state, {super.key, this.label = '', this.size = 40, this.warn = false});
  final HdStep state;
  final String label;
  final double size;
  final bool warn;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    switch (state) {
      case HdStep.done:
        return Container(
          width: size, height: size,
          decoration: BoxDecoration(color: l.ok, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, color: Colors.white, size: size * .6),
        );
      case HdStep.rejected:
        return Container(
          width: size, height: size,
          decoration: BoxDecoration(color: l.warn, shape: BoxShape.circle),
          child: Icon(Icons.close_rounded, color: Colors.white, size: size * .6),
        );
      case HdStep.current:
        final c = warn ? l.red : l.accent;
        return Container(
          width: size, height: size, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.withValues(alpha: .14), shape: BoxShape.circle, border: Border.all(color: c, width: 2)),
          child: Text(label, style: TextStyle(color: warn ? l.red : l.accentText, fontWeight: FontWeight.w700, fontSize: size < 30 ? 10.5 : size * .4)),
        );
      case HdStep.todo:
        return Container(
          width: size, height: size, alignment: Alignment.center,
          decoration: BoxDecoration(color: l.card2, shape: BoxShape.circle, border: Border.all(color: l.border, width: 1.5)),
          child: Text(label, style: TextStyle(color: l.sub, fontWeight: FontWeight.w600, fontSize: size < 30 ? 10.5 : size * .38)),
        );
    }
  }
}

/// Chip lọc / chọn nhanh.
class HdChip extends StatelessWidget {
  const HdChip(this.text, {super.key, required this.selected, required this.onTap, this.icon, this.dense = false, this.small = false});
  final String text;
  final bool selected, dense;

  /// Máy tính gọn: cao ~28px, chữ 12.5.
  final bool small;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    return Material(
      color: selected ? (dense ? l.accent : l.accentSoft) : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: selected ? (dense ? l.accent : l.accent.withValues(alpha: .5)) : l.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: small ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5) : EdgeInsets.symmetric(horizontal: dense ? 16 : 14, vertical: dense ? 9 : 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: small ? 14 : 16, color: selected ? (dense ? Colors.white : l.accentText) : l.sub), const SizedBox(width: 6)],
            Text(text,
                style: TextStyle(
                  fontSize: small ? 12.5 : 13.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? (dense ? Colors.white : l.accentText) : l.text.withValues(alpha: .85),
                )),
          ]),
        ),
      ),
    );
  }
}

/// Nút viền nhỏ (hành động trên một bên ký).
class HdAction extends StatelessWidget {
  const HdAction(this.icon, this.text, {super.key, required this.onTap, this.danger = false, this.small = false});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool danger;

  /// Máy tính gọn: cao ~30px, chữ 12.5.
  final bool small;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final c = danger ? l.red : l.text;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: small ? 15 : 17, color: danger ? l.red : l.text),
      label: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: small ? 12.5 : null)),
      style: OutlinedButton.styleFrom(
        backgroundColor: danger ? l.redSoft.withValues(alpha: .5) : l.card2,
        side: BorderSide(color: danger ? l.red.withValues(alpha: .35) : l.border),
        padding: small ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6) : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        minimumSize: small ? const Size(0, 30) : null,
        tapTargetSize: small ? MaterialTapTargetSize.shrinkWrap : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(small ? 8 : 12)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Hộp xác nhận; [danger] = nút đỏ.
Future<bool> hdConfirm(BuildContext context, String title, String body, {String ok = 'Đồng ý', bool danger = false}) async {
  final l = HdLook.of(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
        FilledButton(style: danger ? FilledButton.styleFrom(backgroundColor: l.red) : null, onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

/// Hỏi một dòng chữ (vd lý do huỷ).
Future<String?> hdAsk(BuildContext context, String title, {String hint = '', String ok = 'Xong'}) async {
  final ctl = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, autofocus: true, maxLines: 3, minLines: 1, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Thôi')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(ok)),
      ],
    ),
  );
  ctl.dispose();
  return r;
}

void hdToast(BuildContext context, String msg) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(msg)));

/// Ô tìm kiếm bo tròn.
class HdSearch extends StatelessWidget {
  const HdSearch({super.key, required this.controller, required this.onSubmit, this.hint = 'Tìm số HĐ, đối tác, MST…', this.width, this.height = 42});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final String hint;
  final double? width;
  final double height;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final small = height < 40;
    return SizedBox(
      width: width,
      height: height,
      child: TextField(
        controller: controller,
        onSubmitted: onSubmit,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: l.text, fontSize: small ? 13 : 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: l.card,
          hintText: hint,
          hintStyle: TextStyle(color: l.faint, fontSize: small ? 13 : 14),
          prefixIcon: Icon(Icons.search_rounded, color: l.sub, size: small ? 18 : 20),
          prefixIconConstraints: small ? const BoxConstraints(minWidth: 36) : null,
          contentPadding: EdgeInsets.symmetric(vertical: small ? 8 : 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(small ? 8 : 12), borderSide: BorderSide(color: l.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(small ? 8 : 12), borderSide: BorderSide(color: l.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(small ? 8 : 12), borderSide: BorderSide(color: l.accent)),
        ),
      ),
    );
  }
}

/// Công tắc + chữ; [small] cho máy tính gọn.
class HdSwitchRow extends StatelessWidget {
  const HdSwitchRow({super.key, required this.value, required this.onChanged, required this.text, this.small = false});
  final bool value, small;
  final ValueChanged<bool>? onChanged;
  final String text;
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    final sw = Switch(value: value, onChanged: onChanged);
    return Row(children: [
      if (small) SizedBox(width: 40, height: 26, child: FittedBox(fit: BoxFit.contain, child: sw)) else sw,
      SizedBox(width: small ? 8 : 10),
      Expanded(child: Text(text, style: TextStyle(color: l.text, fontSize: small ? 13 : 15.5))),
    ]);
  }
}
