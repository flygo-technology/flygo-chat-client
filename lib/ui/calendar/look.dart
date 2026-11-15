// Lịch: màu sự kiện (bản sáng + bản tối dễ đọc), icon riêng của app (ô bo góc, dải xanh dương → ngọc, số ngày), ảnh
// đại diện có dấu trả lời, cách viết ngày giờ tiếng Việt, và khung nổi cạnh chỗ bấm (máy tính) / bảng trượt (điện thoại).
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'model.dart';
import 'tz.dart';

/// Màn hình rộng (máy tính / máy tính bảng ngang): có cột trái, khung nổi.
bool calWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;
bool calDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

const kCalBlue = Color(0xFF1E7BFF);
const kCalTeal = Color(0xFF0E9F8E);
const kNowRed = Color(0xFFE5484D);

/// Mã màu → (sáng, tối). Bản tối đậm hơn một chút để chữ trắng đọc rõ trên nền tối.
const kEventColors = <String, (Color, Color)>{
  'blue': (Color(0xFF1E7BFF), Color(0xFF2F6FD8)),
  'teal': (Color(0xFF0E9F8E), Color(0xFF0B8577)),
  'orange': (Color(0xFFE8811A), Color(0xFFC46C14)),
  'pink': (Color(0xFFD9457B), Color(0xFFB83A68)),
  'purple': (Color(0xFF7C5CE6), Color(0xFF6A4FCC)),
  'red': (Color(0xFFE5484D), Color(0xFFC63D42)),
  'leaf': (Color(0xFF3E9B4F), Color(0xFF348443)),
  'amber': (Color(0xFFC99400), Color(0xFFA67B00)),
  'slate': (Color(0xFF64748B), Color(0xFF56657A)),
  'cocoa': (Color(0xFF8D6E63), Color(0xFF795E54)),
};

const kColorNames = {
  'blue': 'Xanh dương',
  'teal': 'Xanh ngọc',
  'orange': 'Cam',
  'pink': 'Hồng',
  'purple': 'Tím',
  'red': 'Đỏ',
  'leaf': 'Xanh lá',
  'amber': 'Vàng nghệ',
  'slate': 'Xám đá',
  'cocoa': 'Nâu',
};

Color eventColor(String? id, bool dark) {
  final c = kEventColors[id] ?? kEventColors['blue']!;
  return dark ? c.$2 : c.$1;
}

/// Màu xanh chủ đạo theo theme (giống mockup: sáng #1E7BFF, tối #4C97FF).
Color calAccent(BuildContext c) => calDark(c) ? const Color(0xFF4C97FF) : kCalBlue;
/// Nền nhạt của mục đang chọn.
Color calAccentSoft(BuildContext c) => calDark(c) ? const Color(0xFF17305A) : const Color(0xFFE3EEFF);
/// Đường kẻ lưới giờ.
Color calGrid(BuildContext c) => calDark(c) ? const Color(0xFF26282D) : const Color(0xFFECEEF2);

// ------------------------------------------------------------ ngày giờ
const _dowLong = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

/// "TH 2" … "CN" (đầu cột ngày).
String dowHeader(DateTime d) => d.weekday == 7 ? 'CN' : 'TH ${d.weekday + 1}';
/// "T2" … "CN".
String dowShort(DateTime d) => d.weekday == 7 ? 'CN' : 'T${d.weekday + 1}';
String dowLong(DateTime d) => tr(_dowLong[d.weekday - 1]);
/// "Thứ Ba, 17 tháng 11" (thêm năm nếu khác năm [now]).
String dayLong(DateTime d, {DateTime? now}) => '${dowLong(d)}, ${d.day} ${tr('tháng')} ${d.month}${now != null && now.year != d.year ? ', ${d.year}' : ''}';
String monthTitle(DateTime d) => tr('Tháng {0}, {1}', [d.month, d.year]);
String dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// "15:00 – 16:00", "Cả ngày", nhiều ngày: "19/11 – 21/11".
String timeRange(CEvent e, String tz) {
  final s = e.wallStart(tz), en = e.wallEnd(tz);
  if (e.allDay) {
    final last = addDays(en, -1);
    return sameDay(s, last) ? tr('Cả ngày') : '${s.day}/${s.month} – ${last.day}/${last.month}';
  }
  if (!sameDay(s, en) && en.difference(s).inMinutes >= 24 * 60) return '${s.day}/${s.month} ${hm(s)} – ${en.day}/${en.month} ${hm(en)}';
  return '${hm(s)} – ${hm(en)}';
}

/// "1 giờ trước", "30 phút trước", "1 ngày trước", "2 tuần trước".
String reminderText(int minutes) {
  if (minutes == 0) return tr('Lúc bắt đầu');
  if (minutes % 10080 == 0) return tr('{0} tuần trước', [minutes ~/ 10080]);
  if (minutes % 1440 == 0) return tr('{0} ngày trước', [minutes ~/ 1440]);
  if (minutes % 60 == 0) return tr('{0} giờ trước', [minutes ~/ 60]);
  return tr('{0} phút trước', [minutes]);
}

String fileSize(int b) => b < 1024 ? '$b B' : b < 1048576 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB';

// ------------------------------------------------------------ icon app
/// Icon của Lịch: ô bo góc viền mảnh, dải màu xanh dương → ngọc ở trên, số ngày ở giữa.
class CalIcon extends StatelessWidget {
  const CalIcon({super.key, required this.day, this.size = 34});
  final int day;
  final double size;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: BorderRadius.circular(size * .26),
        border: Border.all(color: calDark(context) ? const Color(0xFF3A3C42) : const Color(0xFFDADDE3), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(height: size * .26, decoration: const BoxDecoration(gradient: LinearGradient(colors: [kCalBlue, kCalTeal]))),
        Expanded(
          child: Center(
            child: Text('$day', style: TextStyle(fontSize: size * .4, height: 1, fontWeight: FontWeight.w700, color: calAccent(context))),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ người
const _avatarColors = [Color(0xFF3B6FD8), Color(0xFFC2457A), Color(0xFF2E8B6E), Color(0xFFCB7A2C), Color(0xFF7C5CE6), Color(0xFF4F5B6E), Color(0xFF3E9B4F)];

Color avatarColor(String name) => _avatarColors[name.codeUnits.fold<int>(0, (a, b) => a + b) % _avatarColors.length];

/// Ảnh đại diện chữ cái đầu, có dấu trả lời lời mời ở góc (yes ✓ xanh, no ✕ đỏ, maybe ? vàng, needs đồng hồ xám).
Widget personAvatar(BuildContext context, String name, {double r = 16, String? rsvp, bool channel = false}) {
  final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
  final av = CircleAvatar(
    radius: r,
    backgroundColor: channel ? const Color(0xFF555B66) : avatarColor(name),
    child: Text(initial, style: TextStyle(color: Colors.white, fontSize: r * .85, fontWeight: FontWeight.w600)),
  );
  if (rsvp == null) return av;
  final (Color c, IconData i) = switch (rsvp) {
    'yes' => (const Color(0xFF2E9E4F), Icons.check_rounded),
    'no' => (const Color(0xFFE5484D), Icons.close_rounded),
    'maybe' => (const Color(0xFFC99400), Icons.question_mark_rounded),
    _ => (const Color(0xFF8A8F99), Icons.schedule_rounded),
  };
  return SizedBox(
    width: r * 2 + 2,
    height: r * 2 + 2,
    child: Stack(clipBehavior: Clip.none, children: [
      av,
      Positioned(
        right: -2,
        bottom: -2,
        child: Container(
          width: r * .85,
          height: r * .85,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Pal.of(context).bg, width: 1.5)),
          child: Icon(i, size: r * .55, color: Colors.white),
        ),
      ),
    ]),
  );
}

// ------------------------------------------------------------ nút, ô chọn
/// Ô dạng viên thuốc có mũi tên ▾, bấm mở menu chọn.
class ChipMenu<T> extends StatelessWidget {
  const ChipMenu({super.key, required this.label, required this.items, required this.onSelected, this.leading, this.enabled = true, this.tooltip});
  final String label;
  final List<(T, String)> items;
  final ValueChanged<T> onSelected;
  final Widget? leading;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return PopupMenuButton<T>(
      enabled: enabled,
      tooltip: tooltip ?? '',
      onSelected: onSelected,
      itemBuilder: (_) => [for (final (v, l) in items) PopupMenuItem(value: v, height: 40, child: Text(l))],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: pal.text))),
          if (enabled) ...[const SizedBox(width: 2), Icon(Icons.arrow_drop_down_rounded, size: 20, color: pal.sub)],
        ]),
      ),
    );
  }
}

/// Ô bấm dạng viên (ngày, giờ).
Widget pill(BuildContext context, String text, {VoidCallback? onTap, Key? key}) {
  final pal = Pal.of(context);
  return Material(
    key: key,
    color: pal.surface,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), child: Text(text, style: TextStyle(fontSize: 13.5, color: pal.text))),
    ),
  );
}

ButtonStyle calPrimary(BuildContext c) => FilledButton.styleFrom(
      backgroundColor: calAccent(c),
      foregroundColor: Colors.white,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );

// ------------------------------------------------------------ khung nổi
/// Khung nổi cạnh vùng [anchor] (toạ độ màn hình): bên phải nếu đủ chỗ, không thì bên trái, không thì giữa.
Future<T?> showAnchored<T>(BuildContext context, {required Rect anchor, required WidgetBuilder builder, double width = 440}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Đóng'),
    barrierColor: Colors.black.withValues(alpha: .04),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (c, _, _) => CustomSingleChildLayout(
      delegate: _AnchorDelegate(anchor, width),
      child: Material(
        color: calDark(c) ? Pal.of(c).surface : Pal.of(c).bg,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: builder(c),
      ),
    ),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

class _AnchorDelegate extends SingleChildLayoutDelegate {
  _AnchorDelegate(this.anchor, this.width);
  final Rect anchor;
  final double width;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints(maxWidth: width.clamp(0, c.maxWidth - 32), maxHeight: c.maxHeight - 32);

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = anchor.right + 12;
    if (x + child.width > size.width - 16) x = anchor.left - child.width - 12;
    if (x < 16) x = (size.width - child.width) / 2;
    final y = (anchor.top - 60).clamp(16.0, (size.height - child.height - 16).clamp(16.0, double.infinity));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_AnchorDelegate o) => o.anchor != anchor || o.width != width;
}

/// Hộp thoại trên màn hình rộng, bảng trượt từ dưới lên trên điện thoại.
Future<T?> showCalSheet<T>(BuildContext context, {required WidgetBuilder builder, double width = 480}) {
  if (calWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (c) => Dialog(
        clipBehavior: Clip.antiAlias,
        backgroundColor: calDark(c) ? Pal.of(c).surface : Pal.of(c).bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(c).height * .88), child: builder(c)),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: calDark(context) ? Pal.of(context).surface : Pal.of(context).bg,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .9), child: builder(c)),
    ),
  );
}

/// Ô vuông màu kiểu checkbox của danh sách lịch.
class ColorCheck extends StatelessWidget {
  const ColorCheck({super.key, required this.color, required this.on, this.size = 18});
  final Color color;
  final bool on;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: on ? color : Colors.transparent, borderRadius: BorderRadius.circular(4), border: on ? null : Border.all(color: color, width: 2)),
        child: on ? Icon(Icons.check_rounded, size: size - 3, color: Colors.white) : null,
      );
}
