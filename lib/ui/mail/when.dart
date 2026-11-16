import 'package:flutter/material.dart';

import 'widgets.dart';

/// Chọn thời điểm cho Tạm ẩn / Hẹn giờ gửi: vài mốc nhanh + "Chọn ngày và giờ…". Trả null nếu huỷ.
Future<DateTime?> pickWhen(BuildContext context, {required String title, bool send = false, DateTime? now}) async {
  final n = now ?? DateTime.now();
  DateTime at(DateTime d, int h, [int m = 0]) => DateTime(d.year, d.month, d.day, h, m);
  final tomorrow = n.add(const Duration(days: 1));
  final nextMonday = n.add(Duration(days: (DateTime.monday - n.weekday + 7) % 7 == 0 ? 7 : (DateTime.monday - n.weekday + 7) % 7));
  final saturday = n.add(Duration(days: (DateTime.saturday - n.weekday + 7) % 7 == 0 ? 7 : (DateTime.saturday - n.weekday + 7) % 7));
  final options = <(String, DateTime)>[
    if (send) ...[
      if (n.hour < 13) ('Chiều nay', at(n, 13, 30)),
      ('Sáng mai', at(tomorrow, 8)),
      ('Chiều mai', at(tomorrow, 13, 30)),
      ('Thứ Hai tới', at(nextMonday, 8)),
    ] else ...[
      if (n.hour < 17) ('Cuối ngày hôm nay', at(n, 18)),
      ('Ngày mai', at(tomorrow, 8)),
      if (n.weekday < DateTime.friday) ('Cuối tuần này', at(saturday, 8)),
      ('Tuần sau', at(nextMonday, 8)),
    ],
  ];
  String fmt(DateTime d) => '${_wd[d.weekday - 1]}, ${d.day}/${d.month} lúc ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final picked = await showDialog<Object>(
    context: context,
    builder: (ctx) {
      final mc = MailColors.of(ctx);
      return SimpleDialog(
        title: Text(title),
        children: [
          for (final (label, d) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Row(children: [
                Expanded(child: Text(label, style: TextStyle(color: mc.text))),
                Text(fmt(d), style: TextStyle(color: mc.muted, fontSize: 13)),
              ]),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'custom'),
            child: Row(children: [Icon(Icons.event, size: 18, color: mc.muted), const SizedBox(width: 10), const Text('Chọn ngày và giờ…')]),
          ),
        ],
      );
    },
  );
  if (picked is DateTime) return picked;
  if (picked != 'custom' || !context.mounted) return null;
  final day = await showDatePicker(context: context, initialDate: tomorrow, firstDate: n, lastDate: n.add(const Duration(days: 365)));
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
  if (time == null) return null;
  final d = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  return d.isAfter(DateTime.now().add(const Duration(minutes: 1))) ? d : null;
}

const _wd = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

String whenLabel(DateTime d) {
  final n = DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (d.year == n.year && d.month == n.month && d.day == n.day) return 'hôm nay $hm';
  final t = n.add(const Duration(days: 1));
  if (d.year == t.year && d.month == t.month && d.day == t.day) return 'ngày mai $hm';
  return '${_wd[d.weekday - 1]} ${d.day}/${d.month} $hm';
}
