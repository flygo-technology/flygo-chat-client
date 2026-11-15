// Lịch: cửa vào cho app khác (vd Mail) — mở trình sửa sự kiện mới đã điền sẵn tiêu đề, giờ, khách, nội dung. Không lưu gì
// cho tới khi người dùng bấm Lưu. Email khách được đổi sang người dùng trên máy chủ (POST /api/people/resolve); email
// không có ai thì ghi vào cuối nội dung "Khách ngoài: …".
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'api.dart';
import 'calendar_page.dart' show calendarStore;
import 'editor.dart';
import 'model.dart';
import 'store.dart';
import 'tz.dart';

/// Tìm mini app Lịch trong danh sách app của máy chủ (kiểm thử thay được).
@visibleForTesting
Future<MiniApp?> Function(BuildContext context) findCalendarApp = (context) async {
  final apps = await MiniApps.list(context.read<AppState>().token);
  return apps.where((a) => a.id == kCalApp).firstOrNull;
};

Future<void> openCalendarCreate(BuildContext context,
    {String title = '',
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    List<String> guestEmails = const [],
    List<String> guestUserIds = const [],
    String description = '',
    String? location}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final app = await findCalendarApp(context);
    if (!context.mounted) return;
    if (app == null) {
      messenger.showSnackBar(toast(Text(tr('Chưa cài app Lịch'))));
      return;
    }
    final state = context.read<AppState>();
    final names = {for (final id in guestUserIds) id: state.users[id]?.displayName ?? id};
    final store = await calendarStore(context, app);
    if (!context.mounted) return;
    try {
      await openCalendarCreateWith(context, store,
          title: title,
          start: start,
          end: end,
          allDay: allDay,
          guestEmails: guestEmails,
          guestUserIds: guestUserIds,
          guestNames: names,
          description: description,
          location: location,
          mmToken: state.token);
    } finally {
      store.dispose();
    }
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

/// Phần sau khi đã có kho Lịch (kiểm thử gọi thẳng với backend giả).
Future<bool?> openCalendarCreateWith(BuildContext context, CalStore store,
    {String title = '',
    DateTime? start,
    DateTime? end,
    bool allDay = false,
    List<String> guestEmails = const [],
    List<String> guestUserIds = const [],
    Map<String, String> guestNames = const {},
    String description = '',
    String? location,
    String? mmToken}) async {
  if (!store.loaded) await store.start();
  // Giờ từ app khác là một thời điểm: đổi ra giờ tường của người dùng. Cả ngày thì lấy đúng ngày.
  DateTime? wall(DateTime? d) => d == null ? null : allDay ? DateTime.utc(d.year, d.month, d.day) : wallOf(d.millisecondsSinceEpoch, store.tz);
  var s = wall(start), e = wall(end);
  if (s != null && e == null) e = allDay ? addDays(s, 1) : s.add(Duration(minutes: store.settings.defaultDuration));
  if (s != null && e != null && allDay && !e.isAfter(s)) e = addDays(s, 1);
  final d = EventDraft.blank(store, start: s, end: e, allDay: allDay)
    ..title = title
    ..location = location ?? ''
    ..description = description;
  for (final id in guestUserIds) {
    if (id == store.meId || d.guests.any((g) => g.id == id)) continue;
    d.guests.add(CAttendee(principal: 'mm:$id', id: id, name: guestNames[id] ?? id));
  }
  final emails = [for (final x in guestEmails) if (x.trim().isNotEmpty) x.trim()];
  if (emails.isNotEmpty) {
    var unknown = emails;
    try {
      final (people, rest) = await store.api.resolveEmails(emails);
      unknown = rest;
      for (final p in people) {
        if (p.id == store.meId || d.guests.any((g) => g.id == p.id)) continue;
        d.guests.add(CAttendee(principal: 'mm:${p.id}', id: p.id, name: p.name));
      }
    } catch (_) {
      // Không đổi được (mất mạng / máy chủ cũ): giữ cả danh sách là khách ngoài.
    }
    if (unknown.isNotEmpty) {
      final line = '${tr('Khách ngoài')}: ${unknown.join(', ')}';
      d.description = d.description.trim().isEmpty ? line : '${d.description.trimRight()}\n\n$line';
    }
  }
  if (!context.mounted) return null;
  return openEditor(context, store, draft: d, mmToken: mmToken);
}
