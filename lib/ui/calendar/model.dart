// Lịch: dữ liệu như máy chủ trả (lịch, sự kiện / lần lặp, quyền chia sẻ, cài đặt). Đọc JSON dễ tính: thiếu trường thì lấy
// giá trị mặc định, không ném lỗi.
import 'dart:math';

import 'tz.dart';

final _rnd = Random();
String calId([int n = 14]) {
  const a = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(n, (_) => a[_rnd.nextInt(a.length)]).join();
}

String _s(Object? v, [String d = '']) => v == null ? d : '$v';
int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
bool _b(Object? v, [bool d = false]) => v is bool ? v : d;
List<Map> _maps(Object? v) => [for (final x in (v is List ? v : const [])) if (x is Map) x];

/// Quyền với một lịch, tăng dần.
const kRoles = ['freebusy', 'reader', 'writer', 'manager', 'owner'];
int roleRank(String r) => kRoles.indexOf(r);
const kRoleNames = {
  'freebusy': 'Chỉ xem rảnh/bận',
  'reader': 'Xem tất cả chi tiết',
  'writer': 'Sửa sự kiện',
  'manager': 'Quản lý chia sẻ',
  'owner': 'Chủ sở hữu',
};

class CReminder {
  const CReminder(this.minutes);
  final int minutes;
  factory CReminder.fromJson(Map m) => CReminder(_i(m['minutes'], 30));
  Map<String, dynamic> toJson() => {'minutes': minutes};
}

class CSettings {
  CSettings({
    this.tz = kDefaultTz,
    this.weekStart = 1,
    this.lunar = true,
    this.defaultView = 'week',
    this.defaultDuration = 60,
    List<CReminder>? defaultReminders,
    this.workStart = '08:00',
    this.workEnd = '17:30',
    this.showDeclined = false,
    this.showWeekends = true,
  }) : defaultReminders = defaultReminders ?? const [CReminder(30)];

  String tz;
  int weekStart;
  bool lunar;
  String defaultView;
  int defaultDuration;
  List<CReminder> defaultReminders;
  String workStart, workEnd;
  bool showDeclined, showWeekends;

  factory CSettings.fromJson(Map m) => CSettings(
        tz: _s(m['tz'], kDefaultTz).isEmpty ? kDefaultTz : _s(m['tz'], kDefaultTz),
        weekStart: _i(m['week_start'], 1) == 0 ? 0 : 1,
        lunar: _b(m['lunar'], true),
        defaultView: _s(m['default_view'], 'week'),
        defaultDuration: _i(m['default_duration'], 60).clamp(5, 24 * 60),
        defaultReminders: m['default_reminders'] is List ? [for (final r in _maps(m['default_reminders'])) CReminder.fromJson(r)] : null,
        workStart: _s(m['work_start'], '08:00'),
        workEnd: _s(m['work_end'], '17:30'),
        showDeclined: _b(m['show_declined']),
        showWeekends: _b(m['show_weekends'], true),
      );

  Map<String, dynamic> toJson() => {
        'tz': tz,
        'week_start': weekStart,
        'lunar': lunar,
        'default_view': defaultView,
        'default_duration': defaultDuration,
        'default_reminders': [for (final r in defaultReminders) r.toJson()],
        'work_start': workStart,
        'work_end': workEnd,
        'show_declined': showDeclined,
        'show_weekends': showWeekends,
      };

  /// "08:00" → số phút từ đầu ngày.
  static int minutesOf(String hhmm) {
    final p = hhmm.split(':');
    return (int.tryParse(p.first) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }
}

class CCalendar {
  CCalendar({
    required this.id,
    this.name = '',
    this.description = '',
    this.color = 'blue',
    this.tz = kDefaultTz,
    this.kind = 'personal',
    this.owner = '',
    this.ownerName = '',
    this.role = 'owner',
    this.primary = false,
    this.hidden = false,
    this.colorOverride,
    this.subscribed = false,
    List<CReminder>? defaultReminders,
  }) : defaultReminders = defaultReminders ?? [];

  final String id;
  String name, description, color, tz, kind, owner, ownerName, role;
  bool primary, hidden, subscribed;
  String? colorOverride;
  List<CReminder> defaultReminders;

  /// Màu đang dùng (màu riêng của mình nếu có).
  String get shownColor => colorOverride ?? color;
  bool get canWrite => roleRank(role) >= roleRank('writer') && kind != 'holiday';
  bool get canManage => roleRank(role) >= roleRank('manager') && kind != 'holiday';
  bool get isOwner => role == 'owner';
  bool get isHoliday => kind == 'holiday';
  /// Nằm ở "Lịch của tôi" (lịch mình sở hữu) hay "Lịch khác".
  bool get isMine => isOwner && !isHoliday;

  factory CCalendar.fromJson(Map m) => CCalendar(
        id: _s(m['id']),
        name: _s(m['name']),
        description: _s(m['description']),
        color: _s(m['color'], 'blue').isEmpty ? 'blue' : _s(m['color'], 'blue'),
        tz: _s(m['tz'], kDefaultTz),
        kind: _s(m['kind'], 'personal'),
        owner: _s(m['owner']),
        ownerName: _s(m['owner_name']),
        role: _s(m['role'], 'reader'),
        primary: _b(m['primary']),
        hidden: _b(m['hidden']),
        colorOverride: m['color_override'] as String?,
        subscribed: _b(m['subscribed']),
        defaultReminders: [for (final r in _maps(m['default_reminders'])) CReminder.fromJson(r)],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'color': color,
        'tz': tz,
        'kind': kind,
        'owner': owner,
        'owner_name': ownerName,
        'role': role,
        'primary': primary,
        'hidden': hidden,
        'color_override': colorOverride,
        'subscribed': subscribed,
        'default_reminders': [for (final r in defaultReminders) r.toJson()],
      };
}

/// Một dòng chia sẻ: principal = `mm:<id>` (người), `ch:<id>` (kênh) hoặc "*" (mọi người trên máy chủ).
class CAcl {
  CAcl(this.principal, this.name, this.role);
  final String principal, name;
  String role;
  bool get isChannel => principal.startsWith('ch:');
  bool get isEveryone => principal == '*';
  factory CAcl.fromJson(Map m) => CAcl(_s(m['principal']), _s(m['name'], _s(m['principal'])), _s(m['role'], 'reader'));
  Map<String, dynamic> toJson() => {'principal': principal, 'role': role};
}

class CAttendee {
  CAttendee({required this.principal, this.id = '', this.name = '', this.rsvp = 'needs', this.optional = false, this.organizer = false, this.comment});
  final String principal, id, name;
  String rsvp;
  bool optional, organizer;
  String? comment;
  bool get isChannel => principal.startsWith('ch:');

  factory CAttendee.fromJson(Map m) {
    final p = _s(m['principal'], m['id'] == null ? '' : 'mm:${m['id']}');
    return CAttendee(
      principal: p,
      id: _s(m['id'], p.contains(':') ? p.substring(p.indexOf(':') + 1) : p),
      name: _s(m['name'], p),
      rsvp: _s(m['rsvp'], 'needs'),
      optional: _b(m['optional']),
      organizer: _b(m['organizer']),
      comment: m['comment'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'principal': principal, 'id': id, 'name': name, 'rsvp': rsvp, 'optional': optional, 'organizer': organizer, if (comment != null) 'comment': comment};
}

class CFile {
  const CFile({required this.id, required this.name, this.mime = '', this.size = 0});
  final String id, name, mime;
  final int size;
  factory CFile.fromJson(Map m) => CFile(id: _s(m['id']), name: _s(m['name']), mime: _s(m['mime']), size: _i(m['size']));
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'mime': mime, 'size': size};
}

class CConference {
  const CConference({this.provider = 'hop', this.code = '', this.url = ''});
  final String provider, code, url;
  factory CConference.fromJson(Map m) => CConference(provider: _s(m['provider'], 'hop'), code: _s(m['code']), url: _s(m['url']));
  Map<String, dynamic> toJson() => {'provider': provider, 'code': code, 'url': url};
}

/// Một sự kiện hoặc một lần xảy ra của sự kiện lặp (instance).
class CEvent {
  CEvent({
    required this.id,
    String? instanceId,
    this.rid,
    this.recurring = false,
    this.calendarId = '',
    this.calendarColor,
    this.title = '',
    this.description = '',
    this.location = '',
    this.allDay = false,
    this.start = '',
    this.end = '',
    this.tz = kDefaultTz,
    this.startMs,
    this.endMs,
    this.rrule,
    List<String>? exdates,
    this.rruleText = '',
    this.status = 'confirmed',
    this.busy = true,
    this.visibility = 'default',
    this.color,
    this.conference,
    this.organizerId = '',
    this.organizerName = '',
    List<CAttendee>? attendees,
    Map<String, bool>? guestPerms,
    List<CFile>? attachments,
    List<CReminder>? reminders,
    this.myRsvp,
    this.canEdit = true,
    this.canRsvp = false,
    this.busyOnly = false,
    this.notice = false,
    this.updated = 0,
    this.seq = 0,
  })  : instanceId = instanceId ?? (rid == null ? id : '$id~$rid'),
        exdates = exdates ?? [],
        attendees = attendees ?? [],
        guestPerms = guestPerms ?? {'modify': false, 'invite': true, 'see_guests': true},
        attachments = attachments ?? [],
        reminders = reminders ?? [];

  final String id;
  String instanceId;
  String? rid;
  bool recurring;
  String calendarId;
  String? calendarColor;
  String title, description, location;
  bool allDay;
  /// Giờ địa phương theo [tz]: "YYYY-MM-DDTHH:mm"; cả ngày: "YYYY-MM-DD" (end không tính).
  String start, end, tz;
  int? startMs, endMs;
  String? rrule;
  List<String> exdates;
  String rruleText;
  String status;
  bool busy;
  String visibility;
  String? color;
  CConference? conference;
  String organizerId, organizerName;
  List<CAttendee> attendees;
  Map<String, bool> guestPerms;
  List<CFile> attachments;
  List<CReminder> reminders;
  String? myRsvp;
  bool canEdit, canRsvp, busyOnly;

  /// Chỉ thông báo: khách không cần trả lời (không có nút), được nhắc theo người tổ chức.
  bool notice;
  int updated, seq;

  bool get cancelled => status == 'cancelled';
  bool get pendingInvite => myRsvp == 'needs';
  bool get declined => myRsvp == 'no';

  /// Bắt đầu / kết thúc theo giờ tường của múi giờ [userTz]. Cả ngày: đọc thẳng ngày (không đổi múi giờ).
  DateTime wallStart(String userTz) {
    if (allDay) return parseLocal(start);
    if (startMs != null) return wallOf(startMs!, userTz);
    return wallOf(msOfWall(parseLocal(start), tz), userTz);
  }

  DateTime wallEnd(String userTz) {
    if (allDay) {
      final e = parseLocal(end.isEmpty ? start : end);
      final s = parseLocal(start);
      return e.isAfter(s) ? e : s.add(const Duration(days: 1));
    }
    if (endMs != null) return wallOf(endMs!, userTz);
    if (end.isEmpty) return wallStart(userTz).add(const Duration(hours: 1));
    return wallOf(msOfWall(parseLocal(end), tz), userTz);
  }

  /// Hiện ở hàng "cả ngày" (cả ngày hoặc kéo dài từ 24 giờ).
  bool showsAllDay(String userTz) => allDay || wallEnd(userTz).difference(wallStart(userTz)).inMinutes >= 24 * 60;

  factory CEvent.fromJson(Map m) {
    final org = m['organizer'] is Map ? m['organizer'] as Map : const {};
    final gp = m['guest_perms'] is Map ? m['guest_perms'] as Map : const {};
    return CEvent(
      id: _s(m['id']),
      instanceId: m['instance_id'] as String?,
      rid: m['rid'] as String?,
      recurring: _b(m['recurring'], m['rrule'] != null),
      calendarId: _s(m['calendar_id']),
      calendarColor: m['calendar_color'] as String?,
      title: _s(m['title']),
      description: _s(m['description']),
      location: _s(m['location']),
      allDay: _b(m['all_day']),
      start: _s(m['start']),
      end: _s(m['end']),
      tz: _s(m['tz'], kDefaultTz).isEmpty ? kDefaultTz : _s(m['tz'], kDefaultTz),
      startMs: m['start_ms'] is num ? (m['start_ms'] as num).toInt() : null,
      endMs: m['end_ms'] is num ? (m['end_ms'] as num).toInt() : null,
      rrule: (m['rrule'] as String?)?.isEmpty ?? true ? null : m['rrule'] as String,
      exdates: [for (final x in (m['exdates'] as List? ?? const [])) '$x'],
      rruleText: _s(m['rrule_text']),
      status: _s(m['status'], 'confirmed'),
      busy: _b(m['busy'], true),
      visibility: _s(m['visibility'], 'default'),
      color: (m['color'] as String?)?.isEmpty ?? true ? null : m['color'] as String,
      conference: m['conference'] is Map ? CConference.fromJson(m['conference'] as Map) : null,
      organizerId: _s(org['id']),
      organizerName: _s(org['name']),
      attendees: [for (final a in _maps(m['attendees'])) CAttendee.fromJson(a)],
      guestPerms: {
        'modify': _b(gp['modify']),
        'invite': _b(gp['invite'], true),
        'see_guests': _b(gp['see_guests'], true),
      },
      attachments: [for (final f in _maps(m['attachments'])) CFile.fromJson(f)],
      reminders: [for (final r in _maps(m['reminders'])) CReminder.fromJson(r)],
      myRsvp: m['my_rsvp'] as String?,
      canEdit: _b(m['can_edit'], true),
      canRsvp: _b(m['can_rsvp']),
      busyOnly: _b(m['busy_only']),
      notice: _b(m['notice']),
      updated: _i(m['updated']),
      seq: _i(m['seq']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'instance_id': instanceId,
        'rid': rid,
        'recurring': recurring,
        'calendar_id': calendarId,
        'calendar_color': calendarColor,
        'title': title,
        'description': description,
        'location': location,
        'all_day': allDay,
        'start': start,
        'end': end,
        'tz': tz,
        'start_ms': startMs,
        'end_ms': endMs,
        'rrule': rrule,
        'exdates': exdates,
        'rrule_text': rruleText,
        'status': status,
        'busy': busy,
        'visibility': visibility,
        'color': color,
        'conference': conference?.toJson(),
        'organizer': {'id': organizerId, 'name': organizerName},
        'attendees': [for (final a in attendees) a.toJson()],
        'guest_perms': guestPerms,
        'attachments': [for (final f in attachments) f.toJson()],
        'reminders': [for (final r in reminders) r.toJson()],
        'my_rsvp': myRsvp,
        'can_edit': canEdit,
        'can_rsvp': canRsvp,
        'busy_only': busyOnly,
        'notice': notice,
        'updated': updated,
        'seq': seq,
      };

  CEvent clone() => CEvent.fromJson(toJson());
}

class CPerson {
  const CPerson(this.id, this.name, [this.username = '', this.email = '']);
  final String id, name, username, email;
  factory CPerson.fromJson(Map m) => CPerson(_s(m['id']), _s(m['name'], _s(m['username'])), _s(m['username']), _s(m['email']));
}

class CChannel {
  const CChannel(this.id, this.name, this.displayName, this.members);
  final String id, name, displayName;
  final int members;
  factory CChannel.fromJson(Map m) => CChannel(_s(m['id']), _s(m['name']), _s(m['display_name'], _s(m['name'])), _i(m['members']));
}

/// Khung giờ rảnh chung (find-time).
class CSlot {
  const CSlot(this.startMs, this.endMs, this.start, this.end);
  final int startMs, endMs;
  final String start, end;
  factory CSlot.fromJson(Map m) => CSlot(_i(m['start_ms']), _i(m['end_ms']), _s(m['start']), _s(m['end']));
}

/// RSVP → tên hiển thị.
const kRsvpNames = {'yes': 'Có', 'no': 'Không', 'maybe': 'Có thể', 'needs': 'Đang chờ'};
