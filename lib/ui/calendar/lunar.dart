// Lịch: đổi ngày dương sang âm lịch Việt Nam theo thuật toán của Hồ Ngọc Đức (múi giờ +7).
// Tính điểm sóc (trăng mới) và trung khí để xác định tháng 11 âm và tháng nhuận.
import 'dart:math';

class LunarDate {
  const LunarDate(this.day, this.month, this.year, {this.leap = false});
  final int day, month, year;
  final bool leap;

  /// "9/10" (thêm "n" cho tháng nhuận, vd "3/4n").
  String get short => '$day/$month${leap ? 'n' : ''}';
  @override
  String toString() => '$short/$year';
}

int _int(double d) => d.floor();

int _jdFromDate(int dd, int mm, int yy) {
  final a = (14 - mm) ~/ 12;
  final y = yy + 4800 - a;
  final m = mm + 12 * a - 3;
  var jd = dd + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
  if (jd < 2299161) jd = dd + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - 32083;
  return jd;
}

int _newMoonDay(int k, double tz) {
  final t = k / 1236.85, t2 = t * t, t3 = t2 * t;
  const dr = pi / 180;
  var jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3;
  jd1 += 0.00033 * sin((166.56 + 132.87 * t - 0.009173 * t2) * dr);
  final m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3;
  final mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3;
  final f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3;
  var c1 = (0.1734 - 0.000393 * t) * sin(m * dr) + 0.0021 * sin(2 * dr * m);
  c1 -= 0.4068 * sin(mpr * dr) + 0.0161 * sin(dr * 2 * mpr);
  c1 -= 0.0004 * sin(dr * 3 * mpr);
  c1 += 0.0104 * sin(dr * 2 * f) - 0.0051 * sin(dr * (m + mpr));
  c1 -= 0.0074 * sin(dr * (m - mpr)) + 0.0004 * sin(dr * (2 * f + m));
  c1 -= 0.0004 * sin(dr * (2 * f - m)) - 0.0006 * sin(dr * (2 * f + mpr));
  c1 += 0.0010 * sin(dr * (2 * f - mpr)) + 0.0005 * sin(dr * (2 * mpr + m));
  final deltat = t < -11
      ? 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
      : -0.000278 + 0.000265 * t + 0.000262 * t2;
  return _int(jd1 + c1 - deltat + 0.5 + tz / 24);
}

/// Kinh độ mặt trời lúc nửa đêm đầu ngày [jdn], theo 12 cung (0..11).
int _sunLongitude(int jdn, double tz) {
  final t = (jdn - 2451545.5 - tz / 24) / 36525, t2 = t * t;
  const dr = pi / 180;
  final m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2;
  final l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2;
  var dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * sin(dr * m);
  dl += (0.019993 - 0.000101 * t) * sin(dr * 2 * m) + 0.000290 * sin(dr * 3 * m);
  var l = (l0 + dl) * dr;
  l = l - pi * 2 * _int(l / (pi * 2));
  return _int(l / pi * 6);
}

int _lunarMonth11(int yy, double tz) {
  final off = _jdFromDate(31, 12, yy) - 2415021;
  final k = _int(off / 29.530588853);
  var nm = _newMoonDay(k, tz);
  if (_sunLongitude(nm, tz) >= 9) nm = _newMoonDay(k - 1, tz);
  return nm;
}

int _leapMonthOffset(int a11, double tz) {
  final k = _int((a11 - 2415021.076998695) / 29.530588853 + 0.5);
  var last = 0, i = 1;
  var arc = _sunLongitude(_newMoonDay(k + i, tz), tz);
  do {
    last = arc;
    i++;
    arc = _sunLongitude(_newMoonDay(k + i, tz), tz);
  } while (arc != last && i < 14);
  return i - 1;
}

final _cache = <int, LunarDate>{};

/// Ngày âm lịch của ngày dương [d] (chỉ dùng năm / tháng / ngày).
LunarDate toLunar(DateTime d, {double tz = 7}) {
  final key = d.year * 10000 + d.month * 100 + d.day;
  final hit = _cache[key];
  if (hit != null && tz == 7) return hit;
  final dayNumber = _jdFromDate(d.day, d.month, d.year);
  final k = _int((dayNumber - 2415021.076998695) / 29.530588853);
  var monthStart = _newMoonDay(k + 1, tz);
  if (monthStart > dayNumber) monthStart = _newMoonDay(k, tz);
  var a11 = _lunarMonth11(d.year, tz);
  var b11 = a11;
  int lunarYear;
  if (a11 >= monthStart) {
    lunarYear = d.year;
    a11 = _lunarMonth11(d.year - 1, tz);
  } else {
    lunarYear = d.year + 1;
    b11 = _lunarMonth11(d.year + 1, tz);
  }
  final lunarDay = dayNumber - monthStart + 1;
  final diff = _int((monthStart - a11) / 29);
  var leap = false;
  var lunarMonth = diff + 11;
  if (b11 - a11 > 365) {
    final leapDiff = _leapMonthOffset(a11, tz);
    if (diff >= leapDiff) {
      lunarMonth = diff + 10;
      if (diff == leapDiff) leap = true;
    }
  }
  if (lunarMonth > 12) lunarMonth -= 12;
  if (lunarMonth >= 11 && diff < 4) lunarYear -= 1;
  final r = LunarDate(lunarDay, lunarMonth, lunarYear, leap: leap);
  if (tz == 7) _cache[key] = r;
  return r;
}
