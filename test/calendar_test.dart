// Lịch: âm lịch, quy luật lặp (đọc / ghi / câu chữ), xếp sự kiện chồng giờ, đọc JSON; giao diện với backend giả
// (tuần, tháng, lịch biểu, chi tiết, trình sửa, chia sẻ, tạo nhanh, mở từ app khác).
// Ảnh chụp (chạy tay): CAL_OUT=<thư mục> flutter test test/calendar_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/calendar/layout.dart';
import 'package:flygo_chat/ui/calendar/lunar.dart';
import 'package:flygo_chat/ui/calendar/model.dart';
import 'package:flygo_chat/ui/calendar/rrule_text.dart';
import 'package:flygo_chat/ui/calendar/tz.dart';

import 'fixtures/calendar_fake.dart';

void main() {
  group('âm lịch', () {
    test('các ngày đã biết', () {
      expect(toLunar(DateTime.utc(2026, 2, 17)).short, '1/1');
      expect(toLunar(DateTime.utc(2026, 11, 9)).short, '1/10');
      expect(toLunar(DateTime.utc(2026, 11, 17)).short, '9/10');
      expect(toLunar(DateTime.utc(2025, 1, 29)).short, '1/1');
      expect(toLunar(DateTime.utc(2025, 1, 29)).year, 2025);
      // Năm 2025 nhuận tháng 6.
      final l = toLunar(DateTime.utc(2025, 7, 25));
      expect(l.month, 6);
      expect(l.leap, isTrue);
    });
  });

  group('quy luật lặp', () {
    final wed = DateTime.utc(2026, 11, 18, 10);
    test('đọc / ghi', () {
      final r = RRule.parse('FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231')!;
      expect(r.freq, 'WEEKLY');
      expect(r.byDay, [const RDay('MO'), const RDay('WE')]);
      expect(r.untilDate, DateTime.utc(2026, 12, 31));
      expect(r.build(), 'FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231');
      expect(RRule.parse('FREQ=MONTHLY;BYDAY=-1FR')!.byDay.single, const RDay('FR', -1));
      expect(RRule.parse('RRULE:FREQ=YEARLY;X-LUNAR=1')!.lunar, isTrue);
      expect(RRule.parse('FREQ=HOURLY'), isNull);
      expect(RRule.parse(null), isNull);
      expect(RRule('DAILY', interval: 2, count: 5).build(), 'FREQ=DAILY;INTERVAL=2;COUNT=5');
    });
    test('câu chữ', () {
      expect(rruleText(null, wed), 'Không lặp lại');
      expect(rruleText('FREQ=DAILY', wed), 'Hằng ngày');
      expect(rruleText('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', wed), 'Ngày làm việc (T2–T6)');
      expect(rruleText('FREQ=WEEKLY', wed), 'Hằng tuần vào thứ Tư');
      expect(rruleText('FREQ=WEEKLY;BYDAY=TU;UNTIL=20261229', wed), 'Hằng tuần vào thứ Ba, đến 29/12');
      expect(rruleText('FREQ=WEEKLY;INTERVAL=2;BYDAY=WE,MO', wed), 'Mỗi 2 tuần vào thứ Hai, thứ Tư');
      expect(rruleText('FREQ=MONTHLY;BYMONTHDAY=18', wed), 'Hằng tháng vào ngày 18');
      expect(rruleText('FREQ=MONTHLY;BYDAY=3WE', wed), 'Hằng tháng vào thứ Tư thứ 3');
      expect(rruleText('FREQ=MONTHLY;BYDAY=-1FR;COUNT=6', wed), 'Hằng tháng vào thứ Sáu cuối cùng, 6 lần');
      expect(rruleText('FREQ=YEARLY', wed), 'Hằng năm vào ngày 18 tháng 11');
      expect(rruleText('FREQ=YEARLY;X-LUNAR=1', wed), 'Hằng năm theo âm lịch (ngày 10/10)');
      expect(rruleText('FREQ=DAILY;UNTIL=20270105', wed), 'Hằng ngày, đến 5/1/2027');
    });
    test('lựa chọn có sẵn theo ngày bắt đầu', () {
      final p = rrulePresets(wed);
      expect(p.map((x) => x.label), contains('Hằng tháng vào thứ Tư thứ 3'));
      expect(p.map((x) => x.rule), contains('FREQ=MONTHLY;BYDAY=3WE'));
      expect(p.map((x) => x.rule), isNot(contains('FREQ=MONTHLY;BYDAY=-1WE')));
      final last = rrulePresets(DateTime.utc(2026, 11, 25));
      expect(last.map((x) => x.rule), contains('FREQ=MONTHLY;BYDAY=-1WE'));
      for (final x in p) {
        if (x.rule != null) expect(rruleText(x.rule, wed), x.label);
      }
    });
  });

  group('xếp chỗ', () {
    test('sự kiện chồng giờ chia cột, cụm riêng không ảnh hưởng nhau', () {
      final r = layoutDay<String>([('a', 900, 960), ('b', 930, 990), ('c', 960, 1020), ('d', 1200, 1260)]);
      Placed<String> p(String id) => r.firstWhere((x) => x.item == id);
      expect(p('a').col, 0);
      expect(p('b').col, 1);
      expect(p('c').col, 0); // a đã xong lúc 16:00
      expect(p('a').cols, 2);
      expect(p('d').cols, 1);
      expect(p('d').span, 1);
    });
    test('giãn sang cột trống bên phải', () {
      final r = layoutDay<String>([('a', 0, 120), ('b', 0, 30), ('c', 0, 30), ('d', 60, 90)]);
      final d = r.firstWhere((x) => x.item == 'd');
      expect(d.cols, 3);
      expect(d.col, 1);
      expect(d.span, 2);
    });
    test('thanh nhiều ngày', () {
      final r = layoutBars<String>([('x', 3, 4), ('y', 4, 4), ('z', 0, 0)]);
      expect(r.firstWhere((b) => b.item == 'x').row, 0);
      expect(r.firstWhere((b) => b.item == 'y').row, 1);
      expect(r.firstWhere((b) => b.item == 'z').row, 0);
    });
  });

  group('dữ liệu', () {
    test('đọc sự kiện thiếu trường', () {
      final e = CEvent.fromJson({'id': 'e1', 'title': 'Họp', 'start': '2026-11-17T09:00', 'end': '2026-11-17T10:00'});
      expect(e.instanceId, 'e1');
      expect(e.tz, kDefaultTz);
      expect(e.attendees, isEmpty);
      expect(e.guestPerms['invite'], isTrue);
      expect(e.wallStart('Asia/Ho_Chi_Minh'), DateTime.utc(2026, 11, 17, 9));
      expect(e.wallStart('Asia/Tokyo'), DateTime.utc(2026, 11, 17, 11));
      final o = CEvent.fromJson({'id': 'e2', 'rid': '2026-11-18T08:30', 'recurring': true, 'all_day': false, 'start_ms': 1795397400000, 'end_ms': 1795399200000,
        'attendees': [{'principal': 'mm:u1', 'name': 'Thu Hà', 'rsvp': 'yes'}, {'principal': 'ch:c1', 'name': 'Nhóm Kỹ thuật'}], 'conference': {'code': 'abc'}});
      expect(o.instanceId, 'e2~2026-11-18T08:30');
      expect(o.attendees[0].id, 'u1');
      expect(o.attendees[1].isChannel, isTrue);
      expect(o.attendees[1].rsvp, 'needs');
      expect(o.conference!.provider, 'hop');
      final a = CEvent.fromJson({'id': 'e3', 'all_day': true, 'start': '2026-11-19', 'end': '2026-11-21'});
      expect(a.wallEnd('UTC'), DateTime.utc(2026, 11, 21));
      expect(a.showsAllDay('UTC'), isTrue);
    });
    test('cài đặt + lịch mặc định', () {
      final s = CSettings.fromJson(const {});
      expect(s.tz, 'Asia/Ho_Chi_Minh');
      expect(s.lunar, isTrue);
      expect(s.weekStart, 1);
      final c = CCalendar.fromJson({'id': 'c', 'role': 'writer', 'color_override': 'pink'});
      expect(c.canWrite, isTrue);
      expect(c.canManage, isFalse);
      expect(c.shownColor, 'pink');
      expect(CCalendar.fromJson({'id': 'h', 'kind': 'holiday', 'role': 'owner'}).canWrite, isFalse);
    });
    test('múi giờ', () {
      expect(tzOffset('Asia/Ho_Chi_Minh', 0), 420);
      expect(tzOffset('Europe/London', DateTime.utc(2026, 7, 1).millisecondsSinceEpoch), 60);
      expect(tzOffset('Europe/London', DateTime.utc(2026, 11, 17).millisecondsSinceEpoch), 0);
      expect(tzOffset('America/New_York', DateTime.utc(2026, 7, 1).millisecondsSinceEpoch), -240);
      expect(tzOffset('Australia/Sydney', DateTime.utc(2026, 12, 1).millisecondsSinceEpoch), 660);
      final w = DateTime.utc(2026, 11, 17, 9);
      expect(wallOf(msOfWall(w, 'America/New_York'), 'America/New_York'), w);
      expect(weekStartOf(DateTime.utc(2026, 11, 22), 1), DateTime.utc(2026, 11, 16));
      expect(weekStartOf(DateTime.utc(2026, 11, 22), 0), DateTime.utc(2026, 11, 22));
    });
  });

  calendarWidgetTests();
}
