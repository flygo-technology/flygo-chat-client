// TeamWork: màu, biểu tượng và các mẩu giao diện nhỏ dùng chung (vòng trạng thái, mức ưu tiên, avatar người / agent,
// nhãn, ô dự án, logo). Màu chủ đạo tím chàm của app, không dùng màu / logo của sản phẩm khác.
import 'package:flutter/material.dart';

import 'model.dart';

const kTwAccent = Color(0xFF5B5BD6);
const kTwAi = Color(0xFF8E4EC6);

bool twDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

/// Bảng màu của app theo sáng / tối.
class TwLook {
  TwLook(this.dark);
  factory TwLook.of(BuildContext c) => TwLook(twDark(c));
  final bool dark;
  Color get accent => dark ? const Color(0xFF8587F0) : kTwAccent;
  Color get accentSoft => dark ? const Color(0xFF24254A) : const Color(0xFFECECFD);
  Color get bg => dark ? const Color(0xFF0F1013) : Colors.white;
  Color get surface => dark ? const Color(0xFF18191D) : const Color(0xFFF5F6F8);
  Color get surface2 => dark ? const Color(0xFF25272C) : const Color(0xFFE9EBEF);
  Color get card => dark ? const Color(0xFF1C1D22) : Colors.white;
  Color get text => dark ? const Color(0xFFECEEF2) : const Color(0xFF16181D);
  Color get sub => dark ? const Color(0xFFA3A8B5) : const Color(0xFF5F6573);
  Color get divider => dark ? const Color(0xFF2A2C32) : const Color(0xFFE4E6EB);
  Color get ai => dark ? const Color(0xFFB98AE6) : kTwAi;
  Color get aiSoft => dark ? const Color(0xFF2C2238) : const Color(0xFFF4ECFB);
  Color get ok => const Color(0xFF1F9D55);
  Color get warn => const Color(0xFFE8890C);
  Color get red => const Color(0xFFE5484D);
}

/// "#RRGGBB" → Color; sai dạng → xám.
Color hexColor(String? s, [Color fallback = const Color(0xFF8B8D98)]) {
  final h = (s ?? '').replaceFirst('#', '');
  final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
  return v == null ? fallback : Color(0xFF000000 | v);
}

String colorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Bảng màu chọn cho trạng thái / nhãn / dự án.
const kSwatches = ['#8B8D98', '#1E7BFF', '#0E9F8E', '#2B9348', '#1F9D55', '#E8890C', '#E5484D', '#D6409F', '#7C5CFF', '#5B5BD6', '#B0B4BE', '#8E4EC6'];

// ------------------------------------------------------------ ngày
const _wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
String wdShort(DateTime d) => _wd[d.weekday - 1];
String dShort(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
String dLong(DateTime d) => '${dShort(d)}/${d.year}';

/// "Hôm nay", "Mai", "Hôm qua" hoặc dd/MM.
String dRel(DateTime d, DateTime today) {
  final diff = dayOnly(d).difference(dayOnly(today)).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Mai';
  if (diff == -1) return 'Hôm qua';
  return dShort(d);
}

/// Thời điểm (ms) dạng "10:05", "hôm qua 16:20", "3 ngày trước".
String timeAgo(int ms, DateTime now) {
  if (ms <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  final n = now.toLocal();
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) {
    final m = n.difference(t).inMinutes;
    if (m < 1) return 'vừa xong';
    if (m < 60) return '$m phút trước';
    return hm;
  }
  if (days == 1) return 'hôm qua $hm';
  if (days < 7) return '$days ngày trước';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
}

// ------------------------------------------------------------ vòng trạng thái
class StatusRing extends StatelessWidget {
  const StatusRing(this.status, {super.key, this.size = 14});
  final TwStatus? status;
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _RingPainter(hexColor(status?.color), status?.category ?? 'backlog', status?.review ?? false));
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.category, this.review);
  final Color color;
  final String category;
  final bool review;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1;
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = color;
    switch (category) {
      case 'done':
        canvas.drawCircle(c, r + 1, fill);
        final p = Path()
          ..moveTo(c.dx - r * .45, c.dy)
          ..lineTo(c.dx - r * .1, c.dy + r * .35)
          ..lineTo(c.dx + r * .5, c.dy - r * .35);
        canvas.drawPath(
            p,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..strokeCap = StrokeCap.round);
      case 'closed':
        canvas.drawCircle(c, r, stroke);
        canvas.drawLine(c + Offset(-r * .5, -r * .5), c + Offset(r * .5, r * .5), stroke..strokeWidth = 1.6);
      case 'started':
        canvas.drawCircle(c, r, stroke);
        canvas.drawArc(Rect.fromCircle(center: c, radius: r - 1.5), -1.5708, review ? 4.712 : 3.1416, true, fill);
      default:
        canvas.drawCircle(c, r, stroke);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.color != color || o.category != category || o.review != review;
}

// ------------------------------------------------------------ ưu tiên
const kPriorityIcons = {
  1: (Icons.priority_high_rounded, Color(0xFFE5484D)),
  2: (Icons.keyboard_double_arrow_up_rounded, Color(0xFFE8890C)),
  3: (Icons.drag_handle_rounded, Color(0xFF1E7BFF)),
  4: (Icons.keyboard_arrow_down_rounded, Color(0xFF8B8D98)),
  0: (Icons.remove_rounded, Color(0xFFB0B4BE)),
};

class PriorityIcon extends StatelessWidget {
  const PriorityIcon(this.priority, {super.key, this.size = 17});
  final int priority;
  final double size;
  @override
  Widget build(BuildContext context) {
    final (i, c) = kPriorityIcons[priority] ?? kPriorityIcons[0]!;
    return Tooltip(message: 'Ưu tiên: ${kPriorityNames[priority] ?? 'Không'}', child: Icon(i, size: size, color: c));
  }
}

// ------------------------------------------------------------ avatar
const _avColors = [Color(0xFFE5484D), Color(0xFF1E7BFF), Color(0xFF0E9F8E), Color(0xFFE8890C), Color(0xFF7C5CFF), Color(0xFFD6409F), Color(0xFF2B9348)];

String initialOf(String name) {
  final n = name.trim();
  if (n.isEmpty) return '?';
  final parts = n.split(RegExp(r'\s+'));
  return parts.last.characters.first.toUpperCase();
}

/// Avatar người (chữ cái đầu trên nền màu) hoặc agent (ô bo góc tím, biểu tượng ✦).
class TwAvatar extends StatelessWidget {
  const TwAvatar({super.key, required this.name, this.id = '', this.agent = false, this.size = 24, this.border = true});
  final String name, id;
  final bool agent, border;
  final double size;
  factory TwAvatar.of(TwAssignee a, {double size = 24, bool border = true}) => TwAvatar(name: a.name, id: a.id, agent: a.isAgent, size: size, border: border);
  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final color = _avColors[(id.isEmpty ? name : id).codeUnits.fold(0, (a, b) => a + b) % _avColors.length];
    return Tooltip(
      message: agent ? 'Agent: $name' : name,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: agent ? null : color,
          gradient: agent ? const LinearGradient(colors: [kTwAi, kTwAccent], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          borderRadius: BorderRadius.circular(agent ? size * .28 : size / 2),
          border: border ? Border.all(color: look.card, width: 2) : null,
        ),
        child: agent
            ? Icon(Icons.auto_awesome, size: size * .5, color: Colors.white)
            : Text(initialOf(name), style: TextStyle(color: Colors.white, fontSize: size * .44, fontWeight: FontWeight.w600, height: 1)),
      ),
    );
  }
}

/// Dãy avatar chồng nhau.
class TwAvatars extends StatelessWidget {
  const TwAvatars(this.people, {super.key, this.size = 24, this.max = 4});
  final List<TwAssignee> people;
  final double size;
  final int max;
  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    final extra = people.length - shown.length;
    return SizedBox(
      height: size,
      width: shown.isEmpty ? 0 : size + (shown.length - 1) * size * .7 + (extra > 0 ? size * .9 : 0),
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++) Positioned(left: i * size * .7, child: TwAvatar.of(shown[i], size: size)),
        if (extra > 0)
          Positioned(
            left: shown.length * size * .7 + 2,
            top: 0,
            bottom: 0,
            child: Center(child: Text('+$extra', style: TextStyle(fontSize: size * .45, color: TwLook.of(context).sub))),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ nhãn, chip
class LabelChip extends StatelessWidget {
  const LabelChip(this.label, {super.key, this.dense = false});
  final TwLabel label;
  final bool dense;
  @override
  Widget build(BuildContext context) {
    final c = hexColor(label.color);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(6)),
      child: Text(label.name, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3)),
    );
  }
}

/// Chip màu (trạng thái dự án, nhóm…).
class TwChip extends StatelessWidget {
  const TwChip(this.text, {super.key, required this.color, this.icon, this.solid = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: solid ? color : color.withValues(alpha: .13), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: solid ? Colors.white : color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: solid ? Colors.white : color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Ô vuông màu của dự án với chữ cái đầu của mã.
class ProjectBadge extends StatelessWidget {
  const ProjectBadge(this.project, {super.key, this.size = 18});
  final TwProject project;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: hexColor(project.color, kTwAccent), borderRadius: BorderRadius.circular(size * .28)),
        child: Text(project.key.isEmpty ? '?' : project.key.characters.first, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * .52, height: 1)),
      );
}

/// Logo app: ô bo góc tím → xanh ngọc với ba vạch so le.
class TwLogo extends StatelessWidget {
  const TwLogo({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.symmetric(horizontal: size * .22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kTwAccent, Color(0xFF2BA3A3)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(size * .28),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (w, o) in const [(.7, 1.0), (1.0, .85), (.5, .7)])
            Container(
              margin: EdgeInsets.symmetric(vertical: size * .045),
              width: (size * .56) * w,
              height: size * .12,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: o), borderRadius: BorderRadius.circular(size)),
            ),
        ]),
      );
}

/// Thanh tiến độ mảnh.
class ThinProgress extends StatelessWidget {
  const ThinProgress(this.value, {super.key, this.width, this.color});
  final double value;
  final double? width;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    return Container(
      width: width,
      height: 4,
      decoration: BoxDecoration(color: look.surface2, borderRadius: BorderRadius.circular(2)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0, 1).toDouble(),
        child: Container(decoration: BoxDecoration(color: color ?? look.ok, borderRadius: BorderRadius.circular(2))),
      ),
    );
  }
}

/// Thanh tiến độ dự án chia màu theo nhóm trạng thái.
class CategoryBar extends StatelessWidget {
  const CategoryBar(this.counts, {super.key, this.height = 7});
  final Map<String, int> counts;
  final double height;
  static const colors = {'backlog': Color(0xFF8B8D98), 'started': Color(0xFF1E7BFF), 'closed': Color(0xFFE8890C), 'done': Color(0xFF1F9D55)};
  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        color: TwLook.of(context).surface2,
        child: total == 0
            ? null
            : Row(children: [
                for (final k in ['backlog', 'started', 'closed', 'done'])
                  if ((counts[k] ?? 0) > 0) Expanded(flex: counts[k]!, child: Container(color: colors[k])),
              ]),
      ),
    );
  }
}

/// Nút nhỏ viền mảnh (bộ lọc, thuộc tính).
class TwPill extends StatelessWidget {
  const TwPill({super.key, required this.child, this.onTap, this.set = false, this.dashed = false, this.color});
  final Widget child;
  final VoidCallback? onTap;
  final bool set, dashed;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    return Material(
      color: set ? look.surface : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7), side: BorderSide(color: color ?? look.divider)),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: DefaultTextStyle.merge(style: TextStyle(fontSize: 12.5, color: set ? look.text : look.sub, fontWeight: FontWeight.w500), child: IconTheme.merge(data: IconThemeData(size: 16, color: look.sub), child: child)),
        ),
      ),
    );
  }
}
