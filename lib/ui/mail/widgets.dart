// Thư: phần dùng chung (màu, ảnh đại diện, nhãn, tệp đính kèm, định dạng ngày giờ).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'model.dart';

/// Màu của màn hình Thư (theo theme sáng / tối của app).
class MailColors {
  MailColors._(this.dark);
  final bool dark;
  static MailColors of(BuildContext c) => MailColors._(Theme.of(c).brightness == Brightness.dark);

  Color get bg => dark ? const Color(0xFF12151C) : const Color(0xFFF4F6FB);
  Color get surface => dark ? const Color(0xFF1B1F28) : Colors.white;
  Color get surface2 => dark ? const Color(0xFF252A36) : const Color(0xFFEEF2F9);
  Color get line => dark ? const Color(0xFF2E3442) : const Color(0xFFE3E7EF);
  Color get text => dark ? const Color(0xFFE6E9F0) : const Color(0xFF1D2330);
  Color get muted => dark ? const Color(0xFF9AA3B5) : const Color(0xFF5D6577);
  Color get faint => dark ? const Color(0xFF737C8F) : const Color(0xFF8A92A3);
  Color get accent => dark ? const Color(0xFF6EA8FF) : const Color(0xFF1F6FEB);
  Color get accentSoft => dark ? const Color(0xFF233A63) : const Color(0xFFD6E4FF);
  Color get accentText => dark ? const Color(0xFFA9C8FF) : const Color(0xFF0B4BBD);
  Color get sel => dark ? const Color(0xFF24375A) : const Color(0xFFDFE9FC);
  Color get rowRead => dark ? const Color(0xFF171B23) : const Color(0xFFF5F7FB);
  Color get star => dark ? const Color(0xFFFDD663) : const Color(0xFFF4B400);
  Color get chip => dark ? const Color(0xFF2A303D) : const Color(0xFFEEF1F6);
  Color get button => dark ? const Color(0xFF2F6FE0) : const Color(0xFF1F6FEB);
  Color get danger => dark ? const Color(0xFFFF6B6B) : const Color(0xFFC62828);
}

const _avColors = [0xFF3A7D44, 0xFF1F6FEB, 0xFFC2410C, 0xFF7C3AED, 0xFFBE185D, 0xFF0F766E, 0xFFA16207, 0xFF4338CA, 0xFF0E7490];
Color avatarColor(String key) => Color(_avColors[key.codeUnits.fold<int>(0, (a, c) => a + c) % _avColors.length]);

class MailAvatar extends StatelessWidget {
  const MailAvatar(this.person, {super.key, this.size = 40, this.selected = false});
  final MailPerson person;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return Tooltip(
      message: person.name.isEmpty ? person.email : '${person.name} <${person.email}>',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? mc.accent : avatarColor(person.email)),
        child: selected
            ? Icon(Icons.check, color: Colors.white, size: size * .55)
            : Text(person.initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * .42)),
      ),
    );
  }
}

class LabelChip extends StatelessWidget {
  const LabelChip(this.name, this.color, {super.key, this.onRemove, this.size = 12});
  final String name;
  final Color color;
  final VoidCallback? onRemove;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.only(left: 6, right: onRemove == null ? 6 : 2),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(name, style: TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w500, height: 1.5)),
          if (onRemove != null)
            InkWell(onTap: onRemove, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close, size: size + 1, color: color))),
        ]),
      );
}

(IconData, Color) attachmentIcon(MailAttachment a) => switch (a.kind) {
      'pdf' => (Icons.picture_as_pdf_outlined, const Color(0xFFD93025)),
      'img' => (Icons.image_outlined, const Color(0xFFD93025)),
      'xls' => (Icons.table_chart_outlined, const Color(0xFF1E7B45)),
      'doc' => (Icons.description_outlined, const Color(0xFF2B579A)),
      _ => (Icons.attach_file, const Color(0xFF5F6B7F)),
    };

class AttachmentChip extends StatelessWidget {
  const AttachmentChip(this.a, {super.key, this.onTap, this.maxWidth = 190});
  final MailAttachment a;
  final VoidCallback? onTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final (icon, color) = attachmentIcon(a);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: mc.surface,
        shape: StadiumBorder(side: BorderSide(color: mc.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: mc.text))),
            ]),
          ),
        ),
      ),
    );
  }
}

String fmtSize(int b) => b < 1024 ? '$b B' : b < 1048576 ? '${(b / 1024).round()} KB' : '${(b / 1048576).toStringAsFixed(1)} MB';

/// Ngày trong danh sách: hôm nay → giờ, năm nay → "13 thg 11", năm khác → 13/11/2025.
String fmtListDate(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  if (d.year == n.year && d.month == n.month && d.day == n.day) return DateFormat('HH:mm').format(d);
  if (d.year == n.year) return '${d.day} thg ${d.month}';
  return DateFormat('dd/MM/yyyy').format(d);
}

/// Ngày trong thư: "10:42 13 thg 11 (2 giờ trước)".
String fmtMessageDate(DateTime d, {bool relative = true, DateTime? now}) {
  final n = now ?? DateTime.now();
  final mins = n.difference(d).inMinutes;
  final rel = mins < 1
      ? 'vừa xong'
      : mins < 60
          ? '$mins phút trước'
          : mins < 1440
              ? '${(mins / 60).round()} giờ trước'
              : mins < 43200
                  ? '${(mins / 1440).round()} ngày trước'
                  : '';
  final base = '${DateFormat('HH:mm').format(d)} ${d.day} thg ${d.month}${d.year == n.year ? '' : ' ${d.year}'}';
  return relative && rel.isNotEmpty ? '$base ($rel)' : base;
}

const kLabelSwatches = [0xFF1F6FEB, 0xFF0F9D58, 0xFF7C3AED, 0xFFE8710A, 0xFFD93025, 0xFF0E7490, 0xFFBE185D, 0xFF5F6B7F];

IconData boxIcon(String box) => switch (box) {
      'inbox' => Icons.inbox_outlined,
      'starred' => Icons.star_outline,
      'snoozed' => Icons.schedule,
      'sent' => Icons.send_outlined,
      'scheduled' => Icons.schedule_send_outlined,
      'drafts' => Icons.insert_drive_file_outlined,
      'important' => Icons.label_important_outline,
      'all' => Icons.mail_outline,
      'spam' => Icons.report_outlined,
      'trash' => Icons.delete_outline,
      _ => Icons.folder_outlined,
    };
