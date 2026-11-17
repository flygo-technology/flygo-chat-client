// Lịch: biểu tượng + màu nền (màu chuyển) của sự kiện, kiểu banner Giáng sinh (Sếp, 2026-11-17).
// Biểu tượng là id trong [kEventIcons] (tên biểu tượng Material, máy chủ kiểm cùng danh sách); null = tự chọn theo tiêu đề.
// Màu là mã trong kEventColors (look.dart); mỗi mã có một cặp màu chuyển [eventGradient].
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import 'model.dart';

/// id → (biểu tượng, nhãn). Thứ tự = thứ tự trong bảng chọn.
const kEventIcons = <String, (IconData, String)>{
  'groups': (Icons.groups_rounded, 'Họp'),
  'videocam': (Icons.videocam_rounded, 'Họp online'),
  'alarm': (Icons.alarm_rounded, 'Hạn chót'),
  'cake': (Icons.cake_rounded, 'Sinh nhật'),
  'fire_extinguisher': (Icons.fire_extinguisher_rounded, 'PCCC'),
  'health_and_safety': (Icons.health_and_safety_rounded, 'An toàn'),
  'school': (Icons.school_rounded, 'Đào tạo'),
  'handshake': (Icons.handshake_rounded, 'Khách hàng'),
  'flight': (Icons.flight_rounded, 'Công tác'),
  'celebration': (Icons.celebration_rounded, 'Lễ / Tết'),
  'park': (Icons.park_rounded, 'Giáng sinh'),
  'payments': (Icons.payments_rounded, 'Thanh toán'),
  'receipt_long': (Icons.receipt_long_rounded, 'Hoá đơn'),
  'fact_check': (Icons.fact_check_rounded, 'Kiểm tra'),
  'history_edu': (Icons.history_edu_rounded, 'Ký hợp đồng'),
  'request_quote': (Icons.request_quote_rounded, 'Báo giá'),
  'elevator': (Icons.elevator_rounded, 'Thang máy'),
  'engineering': (Icons.engineering_rounded, 'Kỹ thuật'),
  'construction': (Icons.construction_rounded, 'Công trình'),
  'local_shipping': (Icons.local_shipping_rounded, 'Giao hàng'),
  'inventory_2': (Icons.inventory_2_rounded, 'Kho'),
  'description': (Icons.description_rounded, 'Báo cáo'),
  'account_balance': (Icons.account_balance_rounded, 'Ngân hàng'),
  'gavel': (Icons.gavel_rounded, 'Pháp lý'),
  'medical_services': (Icons.medical_services_rounded, 'Sức khoẻ'),
  'restaurant': (Icons.restaurant_rounded, 'Ăn uống'),
  'sports_soccer': (Icons.sports_soccer_rounded, 'Thể thao'),
  'campaign': (Icons.campaign_rounded, 'Thông báo'),
  'call': (Icons.call_rounded, 'Gọi điện'),
  'redeem': (Icons.redeem_rounded, 'Quà tặng'),
  'workspace_premium': (Icons.workspace_premium_rounded, 'Khen thưởng'),
  'event': (Icons.event_rounded, 'Khác'),
};

/// Mã màu → cặp màu chuyển (đầu, cuối) cho nền banner / ô biểu tượng.
const kEventGradients = <String, (Color, Color)>{
  'red': (Color(0xFFD23C3C), Color(0xFF7B1F2B)),
  'orange': (Color(0xFFF08A3C), Color(0xFFB4441C)),
  'amber': (Color(0xFFE9B23A), Color(0xFFB06A12)),
  'leaf': (Color(0xFF35A06A), Color(0xFF1B5E3A)),
  'teal': (Color(0xFF1DB39A), Color(0xFF0B6670)),
  'blue': (Color(0xFF3D7BF0), Color(0xFF1C3FA8)),
  'navy': (Color(0xFF2B4C86), Color(0xFF0E1F3D)),
  'purple': (Color(0xFF8B63FF), Color(0xFF4B2BB3)),
  'pink': (Color(0xFFEC5D96), Color(0xFF9C2763)),
  'slate': (Color(0xFF5B6676), Color(0xFF1F2937)),
  'noel': (Color(0xFFA82424), Color(0xFF1F5A33)),
  'cocoa': (Color(0xFFA47C6B), Color(0xFF5A3D32)),
};

/// Thứ tự màu trong bảng chọn (11 màu như mockup; Nâu vẫn hiển thị được nếu sự kiện cũ đang dùng).
const kPickerColors = ['red', 'orange', 'amber', 'leaf', 'teal', 'blue', 'navy', 'purple', 'pink', 'slate', 'noel'];

// Bỏ dấu tiếng Việt để so từ khoá (tiêu đề gõ có / không dấu đều nhận).
const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
String _fold(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _from.indexOf(ch);
    b.write(i < 0 ? ch : _to[i]);
  }
  return b.toString();
}

/// Từ khoá (không dấu) → biểu tượng. Thứ tự quan trọng: cụm cụ thể trước cụm chung ("họp online" trước "họp").
const _rules = <(List<String>, String)>[
  (['pccc', 'chay', 'cuu hoa'], 'fire_extinguisher'),
  (['hop online', 'hop truc tuyen', 'online', 'zoom', 'meet', 'video call'], 'videocam'),
  (['giang sinh', 'noel', 'christmas'], 'park'),
  (['sinh nhat', 'birthday'], 'cake'),
  (['an toan', 'safety'], 'health_and_safety'),
  (['dao tao', 'training', 'tap huan', 'khoa hoc'], 'school'),
  (['bao gia', 'quotation'], 'request_quote'),
  (['hop dong', 'ky ket', 'contract'], 'history_edu'),
  (['nghiem thu', 'kiem tra', 'kiem dinh', 'audit'], 'fact_check'),
  (['thang may', 'elevator'], 'elevator'),
  (['bao tri', 'bao duong', 'ky thuat', 'sua chua'], 'engineering'),
  (['cong trinh', 'thi cong'], 'construction'),
  (['giao hang', 'van chuyen', 'ship'], 'local_shipping'),
  (['kiem kho', 'nhap kho', 'xuat kho', 'kho'], 'inventory_2'),
  (['hoa don', 'invoice'], 'receipt_long'),
  (['thanh toan', 'luong', 'tra tien', 'payment'], 'payments'),
  (['ngan hang', 'thue', 'bank'], 'account_balance'),
  (['phap ly', 'luat', 'toa an'], 'gavel'),
  (['kham', 'suc khoe', 'y te'], 'medical_services'),
  (['bao cao', 'report'], 'description'),
  (['khach', 'client', 'customer', 'doi tac'], 'handshake'),
  (['cong tac', 'chuyen bay', 'san bay', 'flight', 'bay'], 'flight'),
  (['le', 'tet', 'ky niem', 'holiday'], 'celebration'),
  (['tiec', 'an trua', 'an toi', 'lien hoan', 'an uong'], 'restaurant'),
  (['bong da', 'the thao', 'da bong', 'cau long', 'tennis'], 'sports_soccer'),
  (['khen thuong', 'vinh danh', 'giai thuong'], 'workspace_premium'),
  (['qua tang', 'tang qua', 'gift'], 'redeem'),
  (['thong bao', 'announcement'], 'campaign'),
  (['goi dien', 'call'], 'call'),
  (['han chot', 'deadline', 'han nop', 'het han'], 'alarm'),
  (['hop', 'giao ban', 'meeting', 'thao luan'], 'groups'),
];

/// Biểu tượng tự chọn theo từ khoá trong tiêu đề; không khớp gì = 'event'.
String autoIcon(String title) {
  // Khớp nguyên từ / cụm từ (không dấu), vd "kho" không khớp "không".
  final t = ' ${_fold(title).replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
  for (final (keys, id) in _rules) {
    for (final k in keys) {
      if (t.contains(' $k ')) return id;
    }
  }
  return 'event';
}

/// id biểu tượng đang dùng: đã chọn, hoặc tự chọn theo [title].
String iconIdOf(String? icon, String title) => icon != null && kEventIcons.containsKey(icon) ? icon : autoIcon(title);
IconData iconDataOf(String id) => (kEventIcons[id] ?? kEventIcons['event']!).$1;
String iconLabelOf(String id) => tr((kEventIcons[id] ?? kEventIcons['event']!).$2);

/// Màu đang dùng: màu của sự kiện → đỏ cho PCCC / an toàn (khi tự chọn) → màu lịch → xanh dương.
String colorIdOf({String? color, String? calendarColor, required String iconId}) {
  if (color != null && kEventGradients.containsKey(color)) return color;
  if (iconId == 'fire_extinguisher' || iconId == 'health_and_safety') return 'red';
  if (calendarColor != null && kEventGradients.containsKey(calendarColor)) return calendarColor;
  return 'blue';
}

LinearGradient eventGradient(String colorId, {Alignment begin = Alignment.centerLeft, Alignment end = Alignment.centerRight}) {
  final g = kEventGradients[colorId] ?? kEventGradients['blue']!;
  return LinearGradient(begin: begin, end: end, colors: [g.$1, g.$2]);
}

/// Kiểu (biểu tượng + màu) của một sự kiện.
({String icon, String color}) styleOf(CEvent e) {
  final icon = iconIdOf(e.icon, e.title);
  return (icon: icon, color: colorIdOf(color: e.color, calendarColor: e.calendarColor, iconId: icon));
}

/// Đếm ngược gọn cho nhãn: "còn 3g 40p", "còn 40p", "còn 2 ngày", "còn 30 giây".
String shortCountdown(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return tr('còn {0} giây', [s < 1 ? 1 : s]);
  final m = (s + 59) ~/ 60;
  if (m < 60) return tr('còn {0}p', [m]);
  final h = m ~/ 60, mm = m % 60;
  if (h < 24) return mm == 0 ? tr('còn {0}g', [h]) : tr('còn {0}g {1}p', [h, mm]);
  return tr('còn {0} ngày', [h ~/ 24]);
}

/// Ô biểu tượng tròn góc trên nền màu chuyển.
class EventIconTile extends StatelessWidget {
  const EventIconTile({super.key, required this.icon, required this.color, this.size = 36, this.dim = false});
  final String icon, color;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dim ? .5 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              gradient: eventGradient(color, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(size * .3)),
          child: Icon(iconDataOf(icon), size: size * .56, color: Colors.white),
        ),
      );
}

/// Banner sự kiện kiểu Giáng sinh: nền màu chuyển, ô biểu tượng mờ bên trái, tên đậm + dòng phụ, nhãn đếm ngược bên phải.
class EventHero extends StatelessWidget {
  const EventHero(
      {super.key, required this.icon, required this.color, required this.title, required this.subtitle, required this.pill, this.live = false, this.trailing, this.onTap, this.pillKey});
  final String icon, color, title, subtitle, pill;
  final bool live;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Key? pillKey;

  @override
  Widget build(BuildContext context) {
    final g = kEventGradients[color] ?? kEventGradients['blue']!;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: eventGradient(color),
        boxShadow: [BoxShadow(color: g.$2.withValues(alpha: .22), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            const Positioned.fill(child: CustomPaint(painter: _Sparkles())),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 10, 0),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(13)),
                  child: Icon(iconDataOf(icon), size: 25, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: .86))),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(999)),
                  child: Text(pill,
                      key: pillKey,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: live ? const Color(0xFFB9F6CA) : const Color(0xFFFFE08A),
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                if (trailing != null) ...[const SizedBox(width: 2), trailing!],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Vài bông tuyết mờ cố định trên banner.
class _Sparkles extends CustomPainter {
  const _Sparkles();
  static const _pts = [(.08, .16), (.22, .70), (.37, .30), (.49, .78), (.63, .18), (.78, .64), (.91, .32)];

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .28)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (final (x, y) in _pts) {
      final o = Offset(x * s.width, y * s.height);
      for (var k = 0; k < 3; k++) {
        final d = Offset.fromDirection(k * 1.0472, 3.2);
        c.drawLine(o - d, o + d, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Sparkles old) => false;
}

/// Bảng "Biểu tượng & màu": xem trước, gợi ý tự chọn, lưới biểu tượng, các màu chuyển; "Mặc định" = tự chọn.
/// Trả (icon, color) đã chọn (null = tự động), hoặc null nếu đóng không lưu.
class EventStylePicker extends StatefulWidget {
  const EventStylePicker({super.key, required this.title, required this.subtitle, this.icon, this.color, this.calendarColor});
  final String title, subtitle;
  final String? icon, color, calendarColor;

  @override
  State<EventStylePicker> createState() => _EventStylePickerState();
}

class _EventStylePickerState extends State<EventStylePicker> {
  late String? icon = widget.icon, color = widget.color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final text = dark ? const Color(0xFFE8EEF8) : const Color(0xFF14181F);
    final sub = dark ? const Color(0xFF9AA8BE) : const Color(0xFF5F6B7A);
    final chip = dark ? const Color(0xFF1A2740) : const Color(0xFFEEF1F6);
    final accent = dark ? const Color(0xFF4C97FF) : const Color(0xFF1E7BFF);
    final auto = autoIcon(widget.title);
    final iconId = iconIdOf(icon, widget.title);
    final colorId = colorIdOf(color: color, calendarColor: widget.calendarColor, iconId: iconId);
    final autoColor = colorIdOf(color: null, calendarColor: widget.calendarColor, iconId: auto);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: sub)),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Biểu tượng & màu'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
      const SizedBox(height: 12),
      EventHero(
          key: const ValueKey('style-preview'),
          icon: iconId,
          color: colorId,
          title: widget.title.trim().isEmpty ? tr('(Không có tiêu đề)') : widget.title,
          subtitle: widget.subtitle,
          pill: tr('còn {0}g {1}p', [3, 40])),
      const SizedBox(height: 10),
      Row(children: [
        Icon(Icons.auto_awesome_rounded, size: 16, color: accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(tr('Tự chọn theo tiêu đề: {0} · màu {1}', [iconLabelOf(auto), tr(_colorName(autoColor))]),
              maxLines: 2, style: TextStyle(fontSize: 12.5, color: sub)),
        ),
      ]),
      label(tr('Biểu tượng')),
      LayoutBuilder(builder: (_, c) {
        final cols = c.maxWidth >= 440 ? 8 : 6;
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in kEventIcons.entries)
            Material(
              color: icon == e.key ? accent.withValues(alpha: .16) : chip,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), side: icon == e.key ? BorderSide(color: accent, width: 2) : BorderSide.none),
              child: InkWell(
                key: ValueKey('style-icon-${e.key}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => icon = e.key),
                child: SizedBox(
                  width: w,
                  height: 52,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(e.value.$1, size: 22, color: text),
                    const SizedBox(height: 2),
                    Text(tr(e.value.$2), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: text)),
                  ]),
                ),
              ),
            ),
        ]);
      }),
      label(tr('Màu nền')),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final c in kPickerColors)
          Tooltip(
            message: tr(_colorName(c)),
            child: InkWell(
              key: ValueKey('style-color-$c'),
              customBorder: const CircleBorder(),
              onTap: () => setState(() => color = c),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: eventGradient(c, begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: color == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
              ),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
          key: const ValueKey('style-default'),
          onPressed: () => Navigator.pop(context, (icon: null, color: null)),
          child: Text(tr('Mặc định'), style: TextStyle(color: sub)),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey('style-done'),
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: () => Navigator.pop(context, (icon: icon, color: color)),
          child: Text(tr('Xong')),
        ),
      ]),
    ]);
  }
}

String _colorName(String id) => const {
      'red': 'Đỏ',
      'orange': 'Cam',
      'amber': 'Vàng nghệ',
      'leaf': 'Xanh lá',
      'teal': 'Xanh ngọc',
      'blue': 'Xanh dương',
      'navy': 'Xanh đêm',
      'purple': 'Tím',
      'pink': 'Hồng',
      'slate': 'Xám đá',
      'noel': 'Giáng sinh',
      'cocoa': 'Nâu',
    }[id] ??
    id;

/// Mở bảng chọn: máy tính = hộp thoại, điện thoại = bảng dưới.
Future<({String? icon, String? color})?> showEventStylePicker(BuildContext context,
    {required String title, required String subtitle, String? icon, String? color, String? calendarColor, required bool wide}) {
  final body = EventStylePicker(title: title, subtitle: subtitle, icon: icon, color: color, calendarColor: calendarColor);
  if (wide) {
    return showDialog<({String? icon, String? color})>(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: body),
        ),
      ),
    );
  }
  return showModalBottomSheet<({String? icon, String? color})>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .88),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 12), child: body),
      ),
    ),
  );
}
