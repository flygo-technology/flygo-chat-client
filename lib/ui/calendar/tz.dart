// Lịch: múi giờ và "giờ tường" (wall time). Mọi phép tính lưới / ngày dùng DateTime isUtc mang giờ địa phương của múi giờ
// người dùng, để không phụ thuộc múi giờ của máy. Bảng múi giờ thường dùng có luật giờ mùa hè (EU / Mỹ / Úc) viết tay,
// đủ cho việc hiển thị; máy chủ mới là nơi tính lặp lại theo múi giờ.

/// Múi giờ trong ô chọn: id IANA, tên hiển thị, độ lệch chuẩn (phút), luật giờ mùa hè ('' = không có).
class CalTz {
  const CalTz(this.id, this.name, this.std, [this.dst = '']);
  final String id, name;
  final int std;
  final String dst;
}

const kDefaultTz = 'Asia/Ho_Chi_Minh';

const kTimezones = <CalTz>[
  CalTz('Asia/Ho_Chi_Minh', 'Giờ Việt Nam', 420),
  CalTz('Asia/Bangkok', 'Bangkok', 420),
  CalTz('Asia/Jakarta', 'Jakarta', 420),
  CalTz('Asia/Singapore', 'Singapore', 480),
  CalTz('Asia/Kuala_Lumpur', 'Kuala Lumpur', 480),
  CalTz('Asia/Manila', 'Manila', 480),
  CalTz('Asia/Shanghai', 'Trung Quốc', 480),
  CalTz('Asia/Hong_Kong', 'Hồng Kông', 480),
  CalTz('Asia/Taipei', 'Đài Bắc', 480),
  CalTz('Asia/Tokyo', 'Nhật Bản', 540),
  CalTz('Asia/Seoul', 'Hàn Quốc', 540),
  CalTz('Asia/Kolkata', 'Ấn Độ', 330),
  CalTz('Asia/Dubai', 'Dubai', 240),
  CalTz('Australia/Sydney', 'Sydney', 600, 'au'),
  CalTz('Europe/London', 'London', 0, 'eu'),
  CalTz('Europe/Paris', 'Paris', 60, 'eu'),
  CalTz('Europe/Berlin', 'Berlin', 60, 'eu'),
  CalTz('Europe/Moscow', 'Moskva', 180),
  CalTz('America/New_York', 'New York', -300, 'us'),
  CalTz('America/Chicago', 'Chicago', -360, 'us'),
  CalTz('America/Los_Angeles', 'Los Angeles', -480, 'us'),
  CalTz('UTC', 'UTC', 0),
];

CalTz? tzById(String id) => kTimezones.where((z) => z.id == id).firstOrNull;

/// Chủ nhật thứ [n] của tháng (n = -1: Chủ nhật cuối), lúc [hourUtc] giờ UTC.
int _sunday(int y, int m, int n, double hourUtc) {
  DateTime d;
  if (n > 0) {
    d = DateTime.utc(y, m, 1);
    d = d.add(Duration(days: (7 - d.weekday % 7) % 7 + 7 * (n - 1)));
  } else {
    d = DateTime.utc(y, m + 1, 0);
    d = d.subtract(Duration(days: d.weekday % 7));
  }
  return d.millisecondsSinceEpoch + (hourUtc * 3600000).round();
}

/// Độ lệch (phút) của múi giờ [id] tại thời điểm [utcMs]. Múi giờ lạ: lấy độ lệch của máy.
int tzOffset(String id, int utcMs) {
  final z = tzById(id);
  if (z == null) return DateTime.fromMillisecondsSinceEpoch(utcMs).timeZoneOffset.inMinutes;
  final y = DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true).year;
  final h = z.std / 60;
  final on = switch (z.dst) {
    // Châu Âu: Chủ nhật cuối tháng 3 lúc 01:00 UTC đến Chủ nhật cuối tháng 10 lúc 01:00 UTC.
    'eu' => utcMs >= _sunday(y, 3, -1, 1) && utcMs < _sunday(y, 10, -1, 1),
    // Mỹ: Chủ nhật thứ hai tháng 3, 2:00 giờ chuẩn đến Chủ nhật đầu tháng 11, 2:00 giờ mùa hè.
    'us' => utcMs >= _sunday(y, 3, 2, 2 - h) && utcMs < _sunday(y, 11, 1, 1 - h),
    // Úc (nam bán cầu): Chủ nhật đầu tháng 10 đến Chủ nhật đầu tháng 4 năm sau.
    'au' => utcMs >= _sunday(y, 10, 1, 2 - h) || utcMs < _sunday(y, 4, 1, 2 - h),
    _ => false,
  };
  return z.std + (on ? 60 : 0);
}

String gmtLabel(int minutes) {
  final s = minutes < 0 ? '-' : '+';
  final a = minutes.abs();
  return 'GMT$s${a ~/ 60}${a % 60 == 0 ? '' : ':${(a % 60).toString().padLeft(2, '0')}'}';
}

/// "Giờ Việt Nam (GMT+7)".
String tzLabel(String id, [int? atMs]) {
  final z = tzById(id);
  final off = tzOffset(id, atMs ?? DateTime.now().millisecondsSinceEpoch);
  return '${z?.name ?? id} (${gmtLabel(off)})';
}

/// Giờ tường của [utcMs] ở múi giờ [tz].
DateTime wallOf(int utcMs, String tz) => DateTime.fromMillisecondsSinceEpoch(utcMs + tzOffset(tz, utcMs) * 60000, isUtc: true);

/// Thời điểm UTC (ms) của giờ tường [w] ở múi giờ [tz].
int msOfWall(DateTime w, String tz) {
  final base = w.millisecondsSinceEpoch;
  var ms = base - tzOffset(tz, base) * 60000;
  ms = base - tzOffset(tz, ms) * 60000;
  return ms;
}

/// "YYYY-MM-DDTHH:mm" hoặc "YYYY-MM-DD" → giờ tường.
DateTime parseLocal(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?').firstMatch(s.trim());
  if (m == null) return DateTime.utc(1970);
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4] ?? '0'), int.parse(m[5] ?? '0'));
}

String _p2(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime w) => '${w.year}-${_p2(w.month)}-${_p2(w.day)}';
String fmtLocal(DateTime w) => '${fmtDate(w)}T${_p2(w.hour)}:${_p2(w.minute)}';

/// Đầu ngày (giờ tường).
DateTime dayOf(DateTime w) => DateTime.utc(w.year, w.month, w.day);
DateTime addDays(DateTime w, int n) => w.add(Duration(days: n));
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
int daysBetween(DateTime a, DateTime b) => dayOf(b).difference(dayOf(a)).inHours ~/ 24;

/// Đầu tuần chứa [w]; [weekStart] 1 = thứ Hai, 0 = Chủ nhật.
DateTime weekStartOf(DateTime w, int weekStart) {
  final d = dayOf(w);
  final wd = d.weekday % 7; // CN = 0
  return addDays(d, -((wd - weekStart + 7) % 7));
}

String hm(DateTime w) => '${w.hour}:${_p2(w.minute)}';
