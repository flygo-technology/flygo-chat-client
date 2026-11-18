import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../browser/flygo_id.dart';
import '../../calls/meet_rooms.dart';
import '../../state/app_state.dart';
import '../calendar/api.dart';
import '../../api/mini_apps.dart';
import '../calendar/model.dart';
import '../calendar/tz.dart' show fmtLocal;
import 'meet_schedule.dart';

// Họp ↔ Lịch: cuộc họp có hẹn giờ là một sự kiện trong Lịch.
// - Lên lịch trong Họp: tạo sự kiện trong Lịch kèm "thêm cuộc họp" (Lịch tạo phòng trên máy chủ, gắn mã vào sự kiện).
// - Đổi giờ / huỷ cuộc họp gắn với Lịch: sửa / xoá sự kiện trong Lịch, Lịch tự sửa / huỷ phòng họp.
// Lịch chưa mở cho người này (hoặc máy chủ chưa có Lịch): Họp làm thẳng trên phòng họp như trước.

class MeetSyncException implements Exception {
  final String message;
  const MeetSyncException(this.message);
  @override
  String toString() => message;
}

/// API Lịch của máy chủ hiện tại, null nếu không có Lịch / Flygo ID.
@visibleForTesting
Future<CalApi?> Function(BuildContext context) meetCalendarApi = (context) async {
  try {
    final token = context.read<AppState>().token;
    final app = (await MiniApps.list(token)).where((a) => a.id == kCalApp).firstOrNull;
    if (app == null) return null;
    final id = await FlygoId.current(token);
    return id == null ? null : CalApi(base: app.baseUrl, id: id);
  } catch (_) {
    return null;
  }
};

Map<String, dynamic> _times(MeetSchedule s) => {
      'title': s.title,
      'start': fmtLocal(meetWall(s.start)),
      'end': fmtLocal(meetWall(s.end)),
      'tz': kMeetTz,
      'all_day': false,
    };

/// Lên lịch qua Lịch: sự kiện + phòng họp. Trả về mã phòng, null nếu Lịch không làm được (gọi phía dưới tự tạo phòng).
Future<String?> scheduleInCalendar(BuildContext context, MeetSchedule s) async {
  final api = await meetCalendarApi(context);
  if (api == null) return null;
  try {
    final ev = await api.create({
      ..._times(s),
      'attendees': [for (final id in s.invitees) {'principal': 'mm:$id'}],
      'add_meeting': true,
    });
    final code = ev.conference?.code ?? '';
    if (code.isNotEmpty) return code;
    // Sự kiện tạo được mà không có phòng (Lịch chưa bật Họp): bỏ sự kiện, Họp tự tạo phòng.
    try {
      await api.remove(ev.id, notify: false);
    } catch (_) {}
    return null;
  } on CalException catch (e) {
    debugPrint('[meet] lịch: ${e.message}');
    return null;
  } catch (e) {
    debugPrint('[meet] lịch: $e');
    return null;
  }
}

/// Sự kiện Lịch của phòng [r] (theo id sự kiện, không có thì tìm theo mã quanh giờ họp).
Future<CEvent?> calendarEventOf(CalApi api, MeetRoomInfo r) async {
  if (r.sourceEventId.isNotEmpty) {
    try {
      return await api.event(r.sourceEventId);
    } catch (_) {}
  }
  final s = r.start;
  if (s == null) return null;
  try {
    final from = fmtLocal(meetWall(s.subtract(const Duration(days: 1))));
    final to = fmtLocal(meetWall(s.add(const Duration(days: 1))));
    return (await api.events(from: from, to: to)).where((e) => e.conference?.code == r.code).firstOrNull;
  } catch (_) {
    return null;
  }
}

/// Đổi giờ / tên qua Lịch. true = Lịch đã làm (Lịch tự sửa phòng). false = không gắn Lịch / không tìm thấy sự kiện.
Future<bool> rescheduleInCalendar(BuildContext context, MeetRoomInfo r, MeetSchedule s) async {
  if (!r.fromCalendar) return false;
  final api = await meetCalendarApi(context);
  if (api == null) return false;
  final ev = await calendarEventOf(api, r);
  if (ev == null) return false;
  if (ev.recurring || (ev.rrule ?? '').isNotEmpty) {
    throw const MeetSyncException('Cuộc họp lặp lại theo Lịch: đổi giờ trong Lịch để chọn một buổi hay cả chuỗi.');
  }
  if (!ev.canEdit) throw const MeetSyncException('Bạn không sửa được sự kiện này trong Lịch.');
  await api.update(ev.id, _times(s));
  return true;
}

/// Huỷ qua Lịch: xoá sự kiện (cả chuỗi), Lịch báo khách và huỷ phòng. true = đã xoá trong Lịch.
Future<bool> cancelInCalendar(BuildContext context, MeetRoomInfo r) async {
  if (!r.fromCalendar) return false;
  final api = await meetCalendarApi(context);
  if (api == null) return false;
  final ev = await calendarEventOf(api, r);
  if (ev == null || !ev.canEdit) return false;
  await api.remove(ev.id, scope: ev.recurring ? 'all' : null, notify: true);
  return true;
}
