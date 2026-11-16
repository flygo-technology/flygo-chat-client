import 'dart:async';
// Lịch: backend giả (không mạng) + kiểm thử giao diện. Dữ liệu mẫu theo mockup: tuần 16–22/11/2026, hôm nay thứ Ba 17/11
// lúc 10:50 (giờ Việt Nam). Tên người là tên mẫu.
// Ảnh chụp: CAL_OUT=<thư mục> flutter test test/calendar_test.dart (máy tính 1440x900, điện thoại 390x844, sáng + tối).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/ui/calendar/api.dart';
import 'package:flygo_chat/ui/calendar/calendar_entry.dart';
import 'package:flygo_chat/ui/calendar/calendar_page.dart';
import 'package:flygo_chat/ui/calendar/store.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

// ------------------------------------------------------------ dữ liệu mẫu
const _tz = 'Asia/Ho_Chi_Minh';
int _ms(int m, int d, int h, int mi) => DateTime.utc(2026, m, d, h, mi).millisecondsSinceEpoch - 7 * 3600000;
String _p2(int n) => n.toString().padLeft(2, '0');

const _me = {'id': 'u-me', 'name': 'Minh An'};
Map<String, dynamic> _att(String id, String name, String rsvp, {bool org = false, bool opt = false, bool ch = false}) =>
    {'principal': '${ch ? 'ch' : 'mm'}:$id', 'id': id, 'name': name, 'rsvp': rsvp, 'organizer': org, 'optional': opt};

Map<String, dynamic> _ev(String id, String title, String cal, String color, int m, int d, int h, int mi, int dur,
    {String? rid, String? rrule, String loc = '', bool conf = false, List<Map<String, dynamic>> att = const [], String? my, bool rsvp = false, String desc = '', bool edit = true, Map? org}) {
  final s = DateTime.utc(2026, m, d, h, mi), e = s.add(Duration(minutes: dur));
  String f(DateTime x) => '${x.year}-${_p2(x.month)}-${_p2(x.day)}T${_p2(x.hour)}:${_p2(x.minute)}';
  return {
    'id': id,
    'instance_id': rid == null ? id : '$id~$rid',
    'rid': rid,
    'recurring': rrule != null,
    'calendar_id': cal,
    'calendar_color': color,
    'title': title,
    'description': desc,
    'location': loc,
    'all_day': false,
    'start': f(s),
    'end': f(e),
    'tz': _tz,
    'start_ms': _ms(m, d, h, mi),
    'end_ms': _ms(m, d, h, mi) + dur * 60000,
    'rrule': rrule,
    'exdates': [],
    'status': 'confirmed',
    'busy': true,
    'visibility': 'default',
    'color': null,
    'conference': conf ? {'provider': 'hop', 'code': 'kpt-wxq-rmd', 'url': 'https://chat.example.com/hop/kpt-wxq-rmd'} : null,
    'organizer': org ?? _me,
    'attendees': att,
    'guest_perms': {'modify': false, 'invite': true, 'see_guests': true},
    'attachments': [],
    'reminders': [{'minutes': 15}],
    'my_rsvp': my,
    'can_edit': edit,
    'can_rsvp': rsvp,
    'busy_only': false,
  };
}

Map<String, dynamic> _allDay(String id, String title, String cal, String color, int m, int d, {int days = 1}) {
  final s = DateTime.utc(2026, m, d), e = s.add(Duration(days: days));
  String f(DateTime x) => '${x.year}-${_p2(x.month)}-${_p2(x.day)}';
  return {
    ..._ev(id, title, cal, color, m, d, 0, 0, days * 1440),
    'all_day': true,
    'start': f(s),
    'end': f(e),
    'reminders': [],
    'can_edit': cal != 'cal-hol',
  };
}

List<Map<String, dynamic>> _seed() {
  final out = <Map<String, dynamic>>[];
  // Giao ban sáng: thứ Hai–thứ Sáu 8:30.
  for (var d = DateTime.utc(2026, 10, 26); d.isBefore(DateTime.utc(2026, 12, 7)); d = d.add(const Duration(days: 1))) {
    if (d.weekday > 5) continue;
    out.add(_ev('ev-standup', 'Giao ban sáng', 'cal-me', 'blue', d.month, d.day, 8, 30, 30,
        rid: '${d.year}-${_p2(d.month)}-${_p2(d.day)}T08:30', rrule: 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', conf: true,
        att: [_att('u-me', 'Minh An', 'yes', org: true), _att('c-tech', 'Nhóm Kỹ thuật (8)', 'needs', ch: true)]));
  }
  final team = [
    _att('u-me', 'Minh An', 'yes', org: true),
    _att('u-ha', 'Thu Hà', 'yes'),
    _att('u-bao', 'Quốc Bảo', 'maybe'),
    _att('u-phuong', 'Lan Phương', 'needs'),
  ];
  out.addAll([
    _allDay('ev-tax', 'Hạn nộp tờ khai thuế', 'cal-me', 'blue', 11, 16)..['color'] = 'red',
    _allDay('ev-trip', 'Công tác Đà Nẵng', 'cal-co', 'orange', 11, 19, days: 2),
    _allDay('ev-teacher', 'Ngày Nhà giáo VN', 'cal-hol', 'teal', 11, 20),
    _allDay('ev-law', 'Ngày Pháp luật', 'cal-hol', 'teal', 11, 9),
    _allDay('ev-bid', 'Hạn nộp hồ sơ thầu', 'cal-me', 'blue', 11, 13)..['color'] = 'red',
    _allDay('ev-ha', 'Sinh nhật Thu Hà', 'cal-bday', 'pink', 11, 15),
    _allDay('ev-pay', 'Chốt lương tháng 11', 'cal-me', 'blue', 11, 30)..['color'] = 'red',
    _ev('ev-client', 'Gặp khách hàng Minh Long', 'cal-me', 'blue', 11, 17, 9, 15, 75, loc: 'Văn phòng Q7')..['color'] = 'orange',
    _ev('ev-lunch', 'Ăn trưa cùng nhóm', 'cal-home', 'leaf', 11, 17, 12, 0, 60),
    _ev('ev-interview', 'Phỏng vấn ứng viên', 'cal-tech', 'purple', 11, 17, 15, 0, 60,
        rid: '2026-11-17T15:00', rrule: 'FREQ=WEEKLY;BYDAY=TU;UNTIL=20261229', conf: true, att: team, my: 'yes', rsvp: true)
      ..['rrule_text'] = 'Hằng tuần vào thứ Ba, đến 29/12',
    _ev('ev-review', 'Review sprint 46', 'cal-me', 'blue', 11, 17, 15, 30, 60, conf: true),
    _ev('ev-design', 'Duyệt thiết kế app Lịch', 'cal-me', 'blue', 11, 16, 14, 0, 90, loc: 'Phòng họp 2', conf: true),
    _ev('ev-safety', 'Đào tạo nội bộ: An toàn điện', 'cal-tech', 'purple', 11, 18, 10, 0, 90, loc: 'Hội trường'),
    _ev('ev-lift', 'Nghiệm thu thang máy – công trình Thủ Đức', 'cal-co', 'orange', 11, 19, 13, 30, 210,
        loc: 'Công trình Thủ Đức, Block B',
        my: 'needs',
        rsvp: true,
        edit: false,
        org: {'id': 'u-khoa', 'name': 'Minh Khoa'},
        desc: 'Kiểm tra 4 thang tải khách, mang biên bản mẫu và hồ sơ kiểm định.',
        att: [
          _att('u-khoa', 'Minh Khoa', 'yes', org: true),
          _att('u-me', 'Minh An', 'needs'),
          _att('u-ha', 'Thu Hà', 'yes'),
          _att('u-bao', 'Quốc Bảo', 'yes'),
          _att('u-phuong', 'Lan Phương', 'needs'),
        ]),
    _ev('ev-supplier', 'Gọi nhà cung cấp', 'cal-me', 'blue', 11, 20, 10, 0, 60, my: 'no'),
    _ev('ev-weekly', 'Tổng kết tuần', 'cal-me', 'blue', 11, 20, 16, 0, 60, conf: true),
    _ev('ev-run', 'Chạy bộ', 'cal-home', 'leaf', 11, 21, 7, 0, 60, loc: 'Công viên Gia Định'),
    _ev('ev-run2', 'Chạy bộ', 'cal-home', 'leaf', 11, 15, 7, 0, 60, loc: 'Công viên Gia Định'),
    _ev('ev-swim', 'Học bơi cho con', 'cal-home', 'leaf', 11, 21, 9, 0, 150),
    _ev('ev-mom', 'Sinh nhật mẹ', 'cal-bday', 'pink', 11, 22, 18, 30, 150, loc: 'Nhà hàng Sen'),
    _ev('ev-survey', 'Khảo sát Bình Dương', 'cal-co', 'orange', 11, 11, 9, 0, 120),
    _ev('ev-techmeet', 'Họp phòng Kỹ thuật', 'cal-tech', 'purple', 11, 9, 14, 0, 60),
    _ev('ev-inspect', 'Kiểm định định kỳ', 'cal-tech', 'purple', 11, 24, 9, 0, 60),
    _ev('ev-month', 'Tổng kết tháng', 'cal-me', 'blue', 11, 27, 16, 0, 60),
    _ev('ev-hidden', 'Nhắc gia hạn tên miền', 'cal-remind', 'slate', 11, 18, 9, 0, 30),
  ]);
  return out;
}

class FakeCal {
  final events = _seed();
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool down = false;
  final calendars = <Map<String, dynamic>>[
    {'id': 'cal-me', 'name': 'Minh An', 'color': 'blue', 'kind': 'personal', 'owner': 'u-me', 'owner_name': 'Minh An', 'role': 'owner', 'primary': true, 'default_reminders': [{'minutes': 30}]},
    {'id': 'cal-home', 'name': 'Việc nhà', 'color': 'leaf', 'kind': 'personal', 'owner': 'u-me', 'role': 'owner'},
    {'id': 'cal-bday', 'name': 'Sinh nhật', 'color': 'pink', 'kind': 'personal', 'owner': 'u-me', 'role': 'owner'},
    {'id': 'cal-remind', 'name': 'Nhắc việc', 'color': 'slate', 'kind': 'personal', 'owner': 'u-me', 'role': 'owner', 'hidden': true},
    {'id': 'cal-tech', 'name': 'Phòng Kỹ thuật', 'color': 'purple', 'kind': 'shared', 'owner': 'u-me', 'owner_name': 'Minh An', 'role': 'manager', 'subscribed': true},
    {'id': 'cal-co', 'name': 'Lịch công ty', 'color': 'orange', 'kind': 'shared', 'owner': 'u-x', 'owner_name': 'Văn phòng', 'role': 'reader', 'subscribed': true},
    {'id': 'cal-hol', 'name': 'Ngày lễ Việt Nam', 'color': 'teal', 'kind': 'holiday', 'role': 'reader', 'subscribed': true},
  ];
  final acl = <Map<String, dynamic>>[
    {'principal': 'mm:u-me', 'name': 'Minh An', 'role': 'owner'},
    {'principal': 'mm:u-ha', 'name': 'Thu Hà', 'role': 'manager'},
    {'principal': 'mm:u-bao', 'name': 'Quốc Bảo', 'role': 'writer'},
    {'principal': 'ch:c-tech', 'name': 'Nhóm Kỹ thuật (8)', 'role': 'reader'},
    {'principal': 'ch:c-acc', 'name': 'Phòng Kế toán (5)', 'role': 'freebusy'},
  ];
  Map<String, dynamic> settings = {
    'tz': _tz, 'week_start': 1, 'lunar': true, 'default_view': 'week', 'default_duration': 60, 'default_reminders': [{'minutes': 30}],
    'work_start': '08:00', 'work_end': '17:30', 'show_declined': false, 'show_weekends': true,
  };

  static http.Response _ok(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});

  http.Client client() => MockClient((req) async {
        final p = req.url.path;
        if (p == '/v1/token') return _ok({'token': 'tk', 'expires_in': 600});
        if (down) throw const SocketException('mất mạng');
        final q = req.url.queryParameters;
        final key = '${req.method} $p${req.url.hasQuery ? '?${req.url.query}' : ''}';
        calls.add(key);
        final body = req.body.isEmpty || req.method == 'GET' ? <String, dynamic>{} : (jsonDecode(req.body) as Map).cast<String, dynamic>();
        bodies[key] = body;
        if (p == '/cal/api/me') {
          return _ok({'user': {'id': 'u-me', 'name': 'Minh An', 'username': 'minhan'}, 'primary_calendar': 'cal-me', 'settings': settings, 'colors': ['blue', 'teal'], 'features': {'hop': true}});
        }
        if (p == '/cal/api/settings') {
          settings = {...settings, ...body};
          return _ok({'settings': settings});
        }
        if (p == '/cal/api/calendars') return _ok({'calendars': calendars});
        final cm = RegExp(r'^/cal/api/calendars/([\w-]+)(/acl|/prefs)?$').firstMatch(p);
        if (cm != null) {
          final c = calendars.where((x) => x['id'] == cm[1]).firstOrNull;
          if (cm[2] == '/acl') {
            if (req.method == 'PUT') {
              acl
                ..removeWhere((a) => a['role'] != 'owner')
                ..addAll([for (final a in body['acl'] as List) {...(a as Map).cast<String, dynamic>(), 'name': a['principal']}]);
            }
            return _ok({'acl': acl});
          }
          if (cm[2] == '/prefs') {
            if (body.containsKey('hidden')) c!['hidden'] = body['hidden'];
            if (body.containsKey('color')) c!['color_override'] = body['color'];
            return _ok({'calendar': c});
          }
          if (req.method == 'PUT') {
            final n = c ?? {'id': cm[1], 'kind': 'personal', 'owner': 'u-me', 'role': 'owner'};
            n.addAll(body);
            if (c == null) calendars.add(n);
            return _ok({'calendar': n});
          }
          if (req.method == 'DELETE') {
            calendars.remove(c);
            return _ok({'ok': true});
          }
        }
        if (p == '/cal/api/events' && req.method == 'GET') {
          final from = DateTime.parse('${q['from']}T00:00:00Z').millisecondsSinceEpoch - 7 * 3600000;
          final to = DateTime.parse('${q['to']}T00:00:00Z').millisecondsSinceEpoch - 7 * 3600000;
          final hidden = {for (final c in calendars) if (c['hidden'] == true) c['id']};
          final text = q['q']?.toLowerCase();
          return _ok({
            'events': [
              for (final e in events)
                if ((e['start_ms'] as int) < to && (e['end_ms'] as int) > from && (text != null || !hidden.contains(e['calendar_id'])) && (text == null || '${e['title']}'.toLowerCase().contains(text)))
                  e,
            ],
          });
        }
        if (p == '/cal/api/events' && req.method == 'POST') {
          final s = DateTime.parse('${body['start']}:00Z'.replaceFirst(RegExp(r'(\d{4}-\d{2}-\d{2}):00Z$'), r'$1T00:00:00Z'));
          final e = {
            ...body,
            'instance_id': body['id'],
            'start_ms': s.millisecondsSinceEpoch - 7 * 3600000,
            'end_ms': s.millisecondsSinceEpoch - 6 * 3600000,
            'organizer': _me,
            'can_edit': true,
            'attendees': [for (final a in body['attendees'] as List? ?? const []) {...(a as Map), 'name': a['principal'], 'rsvp': 'needs'}],
          };
          events.add(e);
          return _ok({'event': e});
        }
        final em = RegExp(r'^/cal/api/events/([\w-]+)(/rsvp|/move|/reminders)?$').firstMatch(p);
        if (em != null) {
          final list = events.where((e) => e['id'] == em[1]).toList();
          if (list.isEmpty) return http.Response('{"error":"Không tìm thấy sự kiện"}', 404);
          final e = q['rid'] != null ? list.firstWhere((x) => x['rid'] == q['rid'], orElse: () => list.first) : list.first;
          if (em[2] == '/rsvp') return _ok({'event': {...e, 'my_rsvp': body['rsvp']}});
          if (em[2] == '/move') return _ok({'event': {...e, 'calendar_id': body['calendar_id']}});
          if (em[2] == '/reminders') return _ok({'event': {...e, 'reminders': body['reminders']}});
          if (req.method == 'PATCH') {
            for (final x in list) {
              for (final k in ['title', 'location', 'description']) {
                if (body.containsKey(k)) x[k] = body[k];
              }
            }
            return _ok({'event': e});
          }
          if (req.method == 'DELETE') {
            events.removeWhere((x) => x['id'] == em[1] && (q['scope'] != 'this' || x['rid'] == q['rid']));
            return _ok({'ok': true});
          }
          return _ok({'event': e});
        }
        if (p == '/cal/api/people') {
          return _ok({
            'people': [
              {'id': 'u-ha', 'name': 'Thu Hà', 'username': 'thuha'},
              {'id': 'u-bao', 'name': 'Quốc Bảo', 'username': 'quocbao'},
            ].where((x) => '${x['name']}'.toLowerCase().contains('${q['q']}'.toLowerCase()) || '${q['q']}'.length < 2).toList(),
            'channels': [
              {'id': 'c-tech', 'name': 'ky-thuat', 'display_name': 'Nhóm Kỹ thuật', 'members': 8},
            ],
          });
        }
        if (p == '/cal/api/people/resolve') {
          const known = {'bao@example.com': {'id': 'u-bao', 'name': 'Quốc Bảo', 'username': 'quocbao', 'email': 'bao@example.com'}};
          final emails = [for (final x in body['emails'] as List) '$x'];
          return _ok({'people': [for (final x in emails) if (known[x] != null) known[x]], 'unknown': [for (final x in emails) if (known[x] == null) x]});
        }
        if (p == '/cal/api/freebusy') {
          return _ok({
            'busy': {
              'u-me': [[_ms(11, 18, 8, 30), _ms(11, 18, 9, 0)], [_ms(11, 18, 10, 0), _ms(11, 18, 11, 30)]],
              'u-ha': [[_ms(11, 18, 13, 0), _ms(11, 18, 15, 0)]],
              'u-bao': [[_ms(11, 18, 9, 0), _ms(11, 18, 10, 0)]],
            },
            'names': {'u-me': 'Minh An', 'u-ha': 'Thu Hà', 'u-bao': 'Quốc Bảo'},
          });
        }
        if (p == '/cal/api/find-time') {
          return _ok({
            'slots': [
              {'start_ms': _ms(11, 17, 14, 0), 'end_ms': _ms(11, 17, 15, 30), 'start': '2026-11-17T14:00', 'end': '2026-11-17T15:30'},
              {'start_ms': _ms(11, 19, 9, 0), 'end_ms': _ms(11, 19, 10, 30), 'start': '2026-11-19T09:00', 'end': '2026-11-19T10:30'},
            ],
          });
        }
        return http.Response('{"error":"không có"}', 404);
      });
}

// ------------------------------------------------------------ kiểm thử giao diện
const _desk = Size(1440, 900), _phone = Size(390, 844);

void calendarWidgetTests() {
  final out = Platform.environment['CAL_OUT'];
  late FakeCal be;

  CalStore newStore() {
    final c = be.client();
    return CalStore(CalApi(base: 'https://chat.test/cal', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: c), client: c), clock: () => DateTime.utc(2026, 11, 17, 3, 50));
  }

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<CalStore> pump(WidgetTester t, {Size size = _desk, bool dark = false, String? view, Widget Function(CalStore s)? child}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Luôn nạp font thật: chữ đo đúng độ rộng như trên máy (font thử mặc định của Flutter rộng hơn nhiều).
    await t.runAsync(_fonts);
    final s = newStore();
    await t.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark ? Brightness.dark : Brightness.light),
        home: child?.call(s) ?? CalendarHome(store: s, ownsStore: false, initialView: view, initialDate: DateTime.utc(2026, 11, 17)),
      ),
    ));
    await settle(t, 8);
    return s;
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
  }

  setUp(() => be = FakeCal());

  group('máy tính', () {
    for (final dark in [false, true]) {
      final sfx = dark ? 'dark' : 'light';
      testWidgets('tuần: âm lịch, hàng cả ngày, lịch ẩn, bật / tắt lịch ($sfx)', (t) async {
        final s = await pump(t, dark: dark);
        expect(find.text('Gặp khách hàng Minh Long'), findsOneWidget);
        expect(find.text('9/10'), findsOneWidget); // âm lịch dưới ngày 17
        expect(find.text('Công tác Đà Nẵng'), findsOneWidget);
        expect(find.text('Ngày Nhà giáo VN'), findsOneWidget);
        expect(find.text('Nhắc gia hạn tên miền'), findsNothing); // lịch đang ẩn
        expect(find.text('Gọi nhà cung cấp'), findsNothing); // đã từ chối
        expect(find.text('Tháng 11, 2026'), findsOneWidget);
        await shot(t, 'd1-week-$sfx');
        if (!dark) {
          await t.tap(find.text('Việc nhà'));
          await settle(t);
          expect(find.text('Ăn trưa cùng nhóm'), findsNothing);
          expect(be.calls.any((c) => c.startsWith('PUT /cal/api/calendars/cal-home/prefs')), isTrue);
          // Sang tuần sau.
          await t.tap(find.byKey(const ValueKey('next')));
          await settle(t);
          expect(find.text('Kiểm định định kỳ'), findsOneWidget);
        }
        s.dispose();
        await done(t);
      });

      testWidgets('tháng: chip, +N sự kiện, âm lịch mùng 1 ($sfx)', (t) async {
        final s = await pump(t, dark: dark, view: 'month');
        expect(find.text('+2 sự kiện'), findsOneWidget);
        expect(find.text('1/10 ÂL'), findsOneWidget);
        expect(find.text('1 Th12'), findsOneWidget);
        await shot(t, 'd2-month-$sfx');
        s.dispose();
        await done(t);
      });

      testWidgets('lịch biểu: nhóm theo ngày, nút Họp ($sfx)', (t) async {
        final s = await pump(t, dark: dark, view: 'agenda');
        expect(find.text('Phỏng vấn ứng viên'), findsOneWidget);
        expect(find.text('Họp'), findsWidgets);
        expect(find.textContaining('Công tác Đà Nẵng (ngày 1/2)'), findsOneWidget);
        await shot(t, 'd7-agenda-$sfx');
        s.dispose();
        await done(t);
      });

      testWidgets('tạo nhanh: bấm ô trống, nhập tiêu đề, Lưu ($sfx)', (t) async {
        final s = await pump(t, dark: dark);
        // Ô thứ Tư 18/11 lúc 14:00: cột 3 trong 7 cột.
        final grid = t.getRect(find.byType(CustomPaint).last);
        final colW = grid.width / 7;
        final y = grid.top + 14 * 48 + 5;
        await t.tapAt(Offset(grid.left + colW * 2.5, y));
        await settle(t);
        expect(find.byKey(const ValueKey('qc-title')), findsOneWidget);
        expect(find.text('Thêm cuộc họp trên Họp'), findsOneWidget);
        await shot(t, 'd3-quick-create-$sfx');
        await t.enterText(find.byKey(const ValueKey('qc-title')), 'Họp nhanh với kho');
        await t.tap(find.byKey(const ValueKey('qc-save')));
        await settle(t);
        final post = be.bodies.entries.firstWhere((e) => e.key == 'POST /cal/api/events').value;
        expect(post['title'], 'Họp nhanh với kho');
        expect(post['start'], startsWith('2026-11-18T'));
        expect(post['calendar_id'], 'cal-me');
        expect(post['reminders'], [{'minutes': 30}]);
        s.dispose();
        await done(t);
      });

      testWidgets('chi tiết + trả lời lời mời (lặp: hỏi phạm vi) ($sfx)', (t) async {
        final s = await pump(t, dark: dark);
        await t.tap(find.byKey(const ValueKey('ev-ev-interview~2026-11-17T15:00')));
        await settle(t);
        expect(find.text('4 khách'), findsOneWidget);
        expect(find.text('2 có, 1 có thể, 1 đang chờ'), findsOneWidget);
        expect(find.text('Hằng tuần vào thứ Ba, đến 29/12'), findsOneWidget);
        expect(find.text('Vào cuộc họp'), findsOneWidget);
        expect(find.text('Người tổ chức'), findsOneWidget);
        await shot(t, 'd4-detail-$sfx');
        await t.tap(find.byKey(const ValueKey('rsvp-maybe')));
        await settle(t);
        expect(find.text('Trả lời sự kiện định kỳ'), findsOneWidget);
        expect(find.text('Sự kiện này và các sự kiện tiếp theo'), findsNothing);
        await t.tap(find.byKey(const ValueKey('scope-ok')));
        await settle(t);
        final b = be.bodies['POST /cal/api/events/ev-interview/rsvp']!;
        expect(b['rsvp'], 'maybe');
        expect(b['scope'], 'this');
        expect(b['rid'], '2026-11-17T15:00');
        s.dispose();
        await done(t);
      });

      testWidgets('xoá sự kiện lặp: hộp phạm vi, báo khách ($sfx)', (t) async {
        final s = await pump(t, dark: dark);
        await t.tap(find.byKey(const ValueKey('ev-ev-interview~2026-11-17T15:00')));
        await settle(t);
        await t.tap(find.byKey(const ValueKey('detail-delete')));
        await settle(t);
        expect(find.text('Xoá sự kiện định kỳ'), findsOneWidget);
        expect(find.text('Báo cho 3 khách qua tin nhắn'), findsOneWidget);
        await shot(t, 'd5-scope-$sfx');
        await t.tap(find.byKey(const ValueKey('scope-following')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('scope-ok')));
        await settle(t);
        expect(be.calls, contains('DELETE /cal/api/events/ev-interview?scope=following&rid=2026-11-17T15%3A00&notify=1'));
        s.dispose();
        await done(t);
      });

      testWidgets('trình sửa: hai cột, khách, giờ rảnh, lưu theo phạm vi ($sfx)', (t) async {
        final s = await pump(t, dark: dark);
        await t.tap(find.byKey(const ValueKey('ev-ev-interview~2026-11-17T15:00')));
        await settle(t);
        await t.tap(find.byKey(const ValueKey('detail-edit')));
        await settle(t);
        expect(find.text('Khách'), findsOneWidget);
        expect(find.text('Khách có quyền'), findsOneWidget);
        expect(find.text('Giờ cả nhóm rảnh'), findsOneWidget);
        expect(find.text('Hằng tuần vào thứ Ba, đến 29/12'), findsOneWidget);
        expect(find.text('Vào cuộc họp trên Họp'), findsOneWidget);
        await shot(t, 'd6-editor-$sfx');
        if (!dark) {
          // Thêm khách từ ô tìm.
          await t.enterText(find.byKey(const ValueKey('people-q')), 'Nhóm');
          await settle(t, 4);
          await t.tap(find.byKey(const ValueKey('channel-c-tech')));
          await settle(t);
          expect(find.text('Nhóm Kỹ thuật (8)'), findsOneWidget);
          // Chỉ thông báo.
          await t.ensureVisible(find.byKey(const ValueKey('notice-toggle')));
          await t.tap(find.byKey(const ValueKey('notice-toggle')));
          await t.pump();
          // Tab tìm thời gian.
          await t.tap(find.byKey(const ValueKey('ed-tab-1')));
          await settle(t);
          expect(find.byKey(const ValueKey('fb-u-ha')), findsOneWidget);
          await shot(t, 'd6b-find-time-$sfx');
          await t.tap(find.byKey(const ValueKey('ed-tab-0')));
          await settle(t);
          await t.enterText(find.byKey(const ValueKey('ed-title')), 'Phỏng vấn ứng viên vòng 2');
          await t.tap(find.byKey(const ValueKey('ed-save')));
          await settle(t);
          expect(find.text('Sửa sự kiện định kỳ'), findsOneWidget);
          await t.tap(find.byKey(const ValueKey('scope-all')));
          await t.pump();
          await t.tap(find.byKey(const ValueKey('scope-ok')));
          await settle(t);
          final k = be.bodies.keys.firstWhere((k) => k.startsWith('PATCH /cal/api/events/ev-interview'));
          expect(k, 'PATCH /cal/api/events/ev-interview?scope=all');
          expect(be.bodies[k]!['title'], 'Phỏng vấn ứng viên vòng 2');
          expect(be.bodies[k]!.containsKey('start'), isFalse);
          expect((be.bodies[k]!['attendees'] as List).map((a) => a['principal']), contains('ch:c-tech'));
          expect(be.bodies[k]!['notice'], isTrue);
        }
        s.dispose();
        await done(t);
      });

      testWidgets('cài đặt và chia sẻ lịch ($sfx)', (t) async {
        final s = await pump(t, dark: dark, view: 'month');
        await t.tap(find.byKey(const ValueKey('cal-menu-cal-tech')));
        await settle(t, 3);
        await t.tap(find.text('Cài đặt và chia sẻ'));
        await settle(t);
        expect(find.text('Chia sẻ với người cụ thể'), findsOneWidget);
        expect(find.text('Quản lý chia sẻ'), findsOneWidget);
        expect(find.text('Chỉ xem rảnh/bận'), findsOneWidget);
        expect(find.text('Liên kết lịch (để sau)'), findsOneWidget);
        await t.ensureVisible(find.byKey(const ValueKey('acl-everyone')));
        await t.tap(find.byKey(const ValueKey('acl-everyone')));
        await t.pump();
        await shot(t, 'd8-share-$sfx');
        await t.tap(find.byKey(const ValueKey('cal-save')));
        await settle(t);
        final b = be.bodies['PUT /cal/api/calendars/cal-tech/acl']!;
        expect((b['acl'] as List).map((a) => a['principal']), containsAll(['*', 'mm:u-ha', 'ch:c-acc']));
        expect((b['acl'] as List).any((a) => a['role'] == 'owner'), isFalse);
        s.dispose();
        await done(t);
      });
    }

    testWidgets('kéo sự kiện để dời giờ, kéo mép dưới để đổi giờ kết thúc', (t) async {
      final s = await pump(t);
      final lunch = find.byKey(const ValueKey('ev-ev-lunch'));
      final g = await t.startGesture(t.getCenter(lunch), kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, 8));
        await t.pump();
      }
      await g.up();
      await settle(t);
      final k = be.bodies.keys.firstWhere((k) => k.startsWith('PATCH /cal/api/events/ev-lunch'));
      expect(be.bodies[k]!['start'], '2026-11-17T13:00');
      expect(be.bodies[k]!['end'], '2026-11-17T14:00');
      // Đổi giờ kết thúc của "Review sprint 46" thêm 30 phút.
      final edge = t.getRect(find.byKey(const ValueKey('resize-ev-review')));
      final r = await t.startGesture(edge.center, kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 3; i++) {
        await r.moveBy(const Offset(0, 8));
        await t.pump();
      }
      await r.up();
      await settle(t);
      final k2 = be.bodies.keys.firstWhere((k) => k.startsWith('PATCH /cal/api/events/ev-review'));
      expect(be.bodies[k2]!['start'], '2026-11-17T15:30');
      expect(be.bodies[k2]!['end'], '2026-11-17T17:00');
      s.dispose();
      await done(t);
    });

    testWidgets('tìm kiếm → kết quả dạng lịch biểu; mất mạng → biểu ngữ', (t) async {
      final s = await pump(t);
      await t.tap(find.byKey(const ValueKey('search')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('search-q')), 'chạy');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await settle(t);
      expect(find.text('Kết quả tìm kiếm'), findsOneWidget);
      expect(find.textContaining('Chạy bộ'), findsNWidgets(2));
      be.down = true;
      // Chạy trong vùng thời gian giả của test (runAsync sẽ chờ mãi các lần tải đang dở trong vùng giả).
      unawaited(s.refresh());
      await settle(t);
      expect(find.text('Không có mạng · đang hiện lịch đã lưu trên máy'), findsOneWidget);
      s.dispose();
      await done(t);
    });

    testWidgets('mở từ app khác: điền sẵn, đổi email thành khách, email lạ ghi vào nội dung', (t) async {
      late BuildContext ctx;
      final s = await pump(t, child: (s) => Builder(builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox());
          }));
      final f = openCalendarCreateWith(ctx, s,
          title: 'Trao đổi hợp đồng', start: DateTime.utc(2026, 11, 20, 2), guestEmails: ['bao@example.com', 'khach@example.com'], description: 'Theo email ngày 15/11');
      await settle(t, 10);
      expect(find.text('Trao đổi hợp đồng'), findsOneWidget);
      expect(find.text('Quốc Bảo'), findsOneWidget);
      expect(find.textContaining('Khách ngoài: khach@example.com'), findsOneWidget);
      expect(find.text('9:00'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(be.calls.where((c) => c.startsWith('POST /cal/api/events')), isEmpty); // chưa lưu
      await t.tap(find.byKey(const ValueKey('ed-close')));
      await settle(t);
      expect(await f, isNull);
      // Chưa cài app.
      findCalendarApp = (_) async => null;
      openCalendarCreate(ctx, title: 'x');
      await settle(t, 3);
      expect(find.text('Chưa cài app Lịch'), findsOneWidget);
      s.dispose();
      await done(t);
    });
  });

  group('điện thoại', () {
    for (final dark in [false, true]) {
      final sfx = dark ? 'dark' : 'light';
      testWidgets('ngày, tháng, lịch biểu, menu ($sfx)', (t) async {
        final s = await pump(t, size: _phone, dark: dark);
        expect(find.text('9/10 ÂL'), findsOneWidget);
        expect(find.text('Gặp khách hàng Minh Long'), findsOneWidget);
        expect(find.byKey(const ValueKey('fab')), findsOneWidget);
        await shot(t, 'p1-day-$sfx');
        await t.tap(find.byKey(const ValueKey('tab-month')));
        await settle(t);
        await t.tap(find.byKey(const ValueKey('pday-2026-11-19')));
        await settle(t);
        expect(find.text('Thứ Năm, 19 tháng 11'), findsOneWidget);
        expect(find.text('chờ trả lời'), findsOneWidget);
        await shot(t, 'p2-month-$sfx');
        await t.tap(find.byKey(const ValueKey('tab-agenda')));
        await settle(t);
        expect(find.text('Tháng 11 2026'), findsOneWidget);
        await shot(t, 'p3-agenda-$sfx');
        await t.tap(find.byKey(const ValueKey('drawer')));
        await settle(t);
        expect(find.text('Lịch của tôi'), findsOneWidget);
        expect(find.text('Tạo lịch mới'), findsOneWidget);
        await shot(t, 'p6-drawer-$sfx');
        s.dispose();
        await done(t);
      });

      testWidgets('chi tiết lời mời + trình sửa một cột ($sfx)', (t) async {
        final s = await pump(t, size: _phone, dark: dark, view: 'agenda');
        await t.scrollUntilVisible(find.byKey(const ValueKey('tile-ev-lift')), 200, scrollable: find.byType(Scrollable).last);
        await t.tap(find.byKey(const ValueKey('tile-ev-lift')));
        await settle(t);
        expect(find.text('Bạn sẽ tham dự chứ?'), findsOneWidget);
        expect(find.textContaining('mời bạn tham gia sự kiện này'), findsOneWidget);
        await shot(t, 'p4-detail-$sfx');
        await t.tap(find.byKey(const ValueKey('rsvp-yes')));
        await settle(t);
        expect(be.bodies['POST /cal/api/events/ev-lift/rsvp']!['rsvp'], 'yes');
        await t.pageBack();
        await settle(t);
        await t.tap(find.byKey(const ValueKey('fab')));
        await settle(t);
        expect(find.byKey(const ValueKey('ed-title')), findsOneWidget);
        await t.enterText(find.byKey(const ValueKey('ed-title')), 'Họp phòng Kỹ thuật');
        await t.pump();
        await shot(t, 'p5-editor-$sfx');
        s.dispose();
        await done(t);
      });
    }

    testWidgets('sự kiện chỉ thông báo: không hỏi trả lời, "người liên quan"', (t) async {
      final ev = be.events.firstWhere((e) => e['id'] == 'ev-lift');
      ev..['notice'] = true..['my_rsvp'] = 'yes'..['can_rsvp'] = false;
      for (final a in ev['attendees'] as List) {
        (a as Map)['rsvp'] = 'yes';
      }
      final s = await pump(t, size: _phone, view: 'agenda');
      await t.scrollUntilVisible(find.byKey(const ValueKey('tile-ev-lift')), 200, scrollable: find.byType(Scrollable).last);
      await t.tap(find.byKey(const ValueKey('tile-ev-lift')));
      await settle(t);
      expect(find.text('Bạn sẽ tham dự chứ?'), findsNothing);
      expect(find.textContaining('mời bạn tham gia sự kiện này'), findsNothing);
      expect(find.textContaining('người liên quan'), findsOneWidget);
      expect(find.text('Chỉ thông báo, không cần trả lời'), findsOneWidget);
      s.dispose();
      await done(t);
    });
  });
}
