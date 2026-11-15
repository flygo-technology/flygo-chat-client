// Lịch: quy luật lặp lại (RRULE theo RFC 5545, không có tiền tố "RRULE:"): đọc / ghi chuỗi, câu tiếng Việt cho ô chọn
// ("Hằng tuần vào thứ Hai, đến 29/12") và các lựa chọn có sẵn theo ngày bắt đầu. Máy chủ mới trải lặp thành từng lần.
import 'lunar.dart';

const kWeekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
const kWeekdayNames = ['thứ Hai', 'thứ Ba', 'thứ Tư', 'thứ Năm', 'thứ Sáu', 'thứ Bảy', 'Chủ nhật'];
/// Tên ngắn theo DateTime.weekday (1 = thứ Hai).
const kWeekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

String weekdayName(int weekday) => kWeekdayNames[weekday - 1];
String weekdayCode(int weekday) => kWeekdayCodes[weekday - 1];

/// Một ngày trong BYDAY: [ord] 0 = mọi tuần, 2 = thứ hai trong tháng, -1 = cuối cùng.
class RDay {
  const RDay(this.code, [this.ord = 0]);
  final String code;
  final int ord;
  int get weekday => kWeekdayCodes.indexOf(code) + 1;
  @override
  String toString() => '${ord == 0 ? '' : ord}$code';
  @override
  bool operator ==(Object other) => other is RDay && other.code == code && other.ord == ord;
  @override
  int get hashCode => Object.hash(code, ord);
}

class RRule {
  RRule(this.freq, {this.interval = 1, this.count, this.until, List<RDay>? byDay, List<int>? byMonthDay, List<int>? byMonth, List<int>? bySetPos, this.wkst, this.lunar = false})
      : byDay = byDay ?? [],
        byMonthDay = byMonthDay ?? [],
        byMonth = byMonth ?? [],
        bySetPos = bySetPos ?? [];

  /// DAILY | WEEKLY | MONTHLY | YEARLY.
  String freq;
  int interval;
  int? count;
  /// "YYYYMMDD" hoặc "YYYYMMDDTHHMMSS" (giờ địa phương), như trong chuỗi.
  String? until;
  List<RDay> byDay;
  List<int> byMonthDay, byMonth, bySetPos;
  String? wkst;
  /// X-LUNAR=1: lặp theo ngày / tháng âm lịch.
  bool lunar;

  static RRule? parse(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final parts = <String, String>{};
    for (final p in s.trim().replaceFirst(RegExp(r'^RRULE:', caseSensitive: false), '').split(';')) {
      final i = p.indexOf('=');
      if (i > 0) parts[p.substring(0, i).toUpperCase()] = p.substring(i + 1);
    }
    final freq = parts['FREQ']?.toUpperCase();
    if (freq == null || !const ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'].contains(freq)) return null;
    List<int> ints(String? v) => [for (final x in (v ?? '').split(',')) if (int.tryParse(x.trim()) != null) int.parse(x.trim())];
    final days = <RDay>[];
    for (final x in (parts['BYDAY'] ?? '').split(',')) {
      final m = RegExp(r'^([+-]?\d+)?(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(x.trim().toUpperCase());
      if (m != null) days.add(RDay(m[2]!, int.tryParse((m[1] ?? '0').replaceFirst('+', '')) ?? 0));
    }
    return RRule(freq,
        interval: (int.tryParse(parts['INTERVAL'] ?? '') ?? 1).clamp(1, 999),
        count: int.tryParse(parts['COUNT'] ?? ''),
        until: parts['UNTIL'],
        byDay: days,
        byMonthDay: ints(parts['BYMONTHDAY']),
        byMonth: ints(parts['BYMONTH']),
        bySetPos: ints(parts['BYSETPOS']),
        wkst: parts['WKST'],
        lunar: parts['X-LUNAR'] == '1');
  }

  String build() => [
        'FREQ=$freq',
        if (interval > 1) 'INTERVAL=$interval',
        if (byDay.isNotEmpty) 'BYDAY=${byDay.join(',')}',
        if (byMonthDay.isNotEmpty) 'BYMONTHDAY=${byMonthDay.join(',')}',
        if (byMonth.isNotEmpty) 'BYMONTH=${byMonth.join(',')}',
        if (bySetPos.isNotEmpty) 'BYSETPOS=${bySetPos.join(',')}',
        if (wkst != null) 'WKST=$wkst',
        if (lunar) 'X-LUNAR=1',
        if (count != null) 'COUNT=$count' else if (until != null) 'UNTIL=$until',
      ].join(';');

  @override
  String toString() => build();

  /// Ngày UNTIL dưới dạng ngày (giờ tường).
  DateTime? get untilDate {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(until ?? '');
    return m == null ? null : DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  static String untilOf(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  bool get isWeekdays =>
      freq == 'WEEKLY' && interval == 1 && byDay.length == 5 && byDay.every((d) => d.ord == 0) && {for (final d in byDay) d.code}.containsAll(const ['MO', 'TU', 'WE', 'TH', 'FR']);
}

String _ordText(int ord) => ord == -1 ? 'cuối cùng' : 'thứ $ord';

/// Câu mô tả quy luật [rule] cho sự kiện bắt đầu [start] (giờ tường). Chuỗi rỗng / sai → "Không lặp lại".
String rruleText(String? rule, DateTime start) {
  final r = RRule.parse(rule);
  if (r == null) return 'Không lặp lại';
  String unit(String one) => r.interval == 1 ? 'Hằng $one' : 'Mỗi ${r.interval} $one';
  String head;
  if (r.lunar) {
    final l = toLunar(start);
    head = 'Hằng năm theo âm lịch (ngày ${l.day}/${l.month})';
  } else {
    switch (r.freq) {
      case 'DAILY':
        head = unit('ngày');
      case 'WEEKLY':
        if (r.isWeekdays) {
          head = 'Ngày làm việc (T2–T6)';
        } else {
          final days = r.byDay.isEmpty ? [RDay(weekdayCode(start.weekday))] : ([...r.byDay]..sort((a, b) => a.weekday.compareTo(b.weekday)));
          head = '${unit('tuần')} vào ${days.map((d) => weekdayName(d.weekday)).join(', ')}';
        }
      case 'MONTHLY':
        if (r.byDay.isNotEmpty) {
          final d = r.byDay.first;
          final ord = d.ord != 0 ? d.ord : (r.bySetPos.isNotEmpty ? r.bySetPos.first : 0);
          head = '${unit('tháng')} vào ${weekdayName(d.weekday)}${ord == 0 ? '' : ' ${_ordText(ord)}'}';
        } else {
          final n = r.byMonthDay.isNotEmpty ? r.byMonthDay.first : start.day;
          head = '${unit('tháng')} vào ${n == -1 ? 'ngày cuối tháng' : 'ngày $n'}';
        }
      default:
        final m = r.byMonth.isNotEmpty ? r.byMonth.first : start.month;
        final d = r.byMonthDay.isNotEmpty ? r.byMonthDay.first : start.day;
        head = '${unit('năm')} vào ngày $d tháng $m';
    }
  }
  if (r.count != null) return '$head, ${r.count} lần';
  final u = r.untilDate;
  if (u != null) return '$head, đến ${u.day}/${u.month}${u.year != start.year ? '/${u.year}' : ''}';
  return head;
}

/// Một lựa chọn trong ô "Lặp lại".
class RPreset {
  const RPreset(this.label, this.rule);
  final String label;
  final String? rule;
}

/// Thứ tự của tuần chứa [d] trong tháng (1..5) và có phải tuần cuối không.
(int, bool) weekOfMonth(DateTime d) {
  final k = (d.day - 1) ~/ 7 + 1;
  final last = d.add(const Duration(days: 7)).month != d.month;
  return (k, last);
}

/// Các lựa chọn có sẵn theo ngày bắt đầu [start].
List<RPreset> rrulePresets(DateTime start) {
  final code = weekdayCode(start.weekday);
  final (k, last) = weekOfMonth(start);
  final l = toLunar(start);
  return [
    const RPreset('Không lặp lại', null),
    const RPreset('Hằng ngày', 'FREQ=DAILY'),
    const RPreset('Ngày làm việc (T2–T6)', 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'),
    RPreset('Hằng tuần vào ${weekdayName(start.weekday)}', 'FREQ=WEEKLY;BYDAY=$code'),
    RPreset('Hằng tháng vào ngày ${start.day}', 'FREQ=MONTHLY;BYMONTHDAY=${start.day}'),
    if (k <= 4) RPreset('Hằng tháng vào ${weekdayName(start.weekday)} thứ $k', 'FREQ=MONTHLY;BYDAY=$k$code'),
    if (last) RPreset('Hằng tháng vào ${weekdayName(start.weekday)} cuối cùng', 'FREQ=MONTHLY;BYDAY=-1$code'),
    RPreset('Hằng năm vào ngày ${start.day} tháng ${start.month}', 'FREQ=YEARLY'),
    RPreset('Hằng năm theo âm lịch (ngày ${l.day}/${l.month})', 'FREQ=YEARLY;X-LUNAR=1'),
  ];
}
