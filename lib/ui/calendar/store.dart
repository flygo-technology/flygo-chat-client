// Lịch: kho dữ liệu của màn hình. Giữ lịch, cài đặt và các lần xảy ra đã tải theo từng tháng (giờ tường của người dùng);
// đổi khoảng xem thì tải lại khoảng đó, sửa gì xong cũng tải lại. Tháng đang xem ±1 được lưu xuống máy để mở app khi mất
// mạng vẫn thấy lịch cũ (chỉ xem; sửa cần có mạng).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'model.dart';
import 'tz.dart';

class CalStore extends ChangeNotifier {
  CalStore(this.api, {this.cacheKey, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final CalApi api;
  /// Tên tệp bộ nhớ đệm (máy chủ + người dùng); null = chỉ trong bộ nhớ (kiểm thử).
  final String? cacheKey;
  final DateTime Function() _clock;

  String meId = '', meName = '', meUsername = '', primaryId = '';
  CSettings settings = CSettings();
  List<String> colors = [];
  /// features.hop: có nút "Thêm cuộc họp trên Họp".
  bool hop = false;
  List<CCalendar> calendars = [];
  /// Các lần xảy ra theo tháng "YYYY-MM" (khoảng [đầu tháng, đầu tháng sau)).
  final Map<String, List<CEvent>> _months = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, Future<void>> _loading = {};
  bool loaded = false, offline = false;
  String? error;
  bool _disposed = false;
  Timer? _save;
  /// Khoảng đang xem (để tải lại sau khi sửa).
  DateTime? _viewFrom, _viewTo;

  String get tz => settings.tz;
  DateTime get nowWall => wallOf(_clock().millisecondsSinceEpoch, tz);
  DateTime get today => dayOf(nowWall);

  CCalendar? calendar(String id) => calendars.where((c) => c.id == id).firstOrNull;
  CCalendar? get primary => calendar(primaryId) ?? calendars.where((c) => c.primary).firstOrNull;
  List<CCalendar> get mine => calendars.where((c) => c.isMine).toList();
  List<CCalendar> get others => calendars.where((c) => !c.isMine).toList();
  List<CCalendar> get writable => calendars.where((c) => c.canWrite).toList();

  /// Màu của sự kiện: màu riêng → màu lịch (màu mình đặt) → màu lịch máy chủ gửi.
  String colorOf(CEvent e) => e.color ?? calendar(e.calendarId)?.shownColor ?? e.calendarColor ?? primary?.shownColor ?? 'blue';
  /// Lịch hiện sự kiện: lịch của nó, sự kiện được mời (lịch của người khác) thì là lịch chính.
  CCalendar? calendarOf(CEvent e) => calendar(e.calendarId) ?? primary;

  bool shows(CEvent e) {
    if (e.cancelled) return false;
    if (calendarOf(e)?.hidden ?? false) return false;
    if (e.declined && !settings.showDeclined) return false;
    return true;
  }

  void _changed({bool persist = true}) {
    if (_disposed) return;
    notifyListeners();
    if (persist) _persist();
  }

  void _netError(Object e) {
    if (CalApi.isOffline(e)) {
      offline = true;
    } else {
      error = '$e';
    }
  }

  // ------------------------------------------------------------ bộ nhớ đệm
  Future<File?> _file() async {
    if (cacheKey == null) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}calendar_$cacheKey.json');
  }

  Future<void> _restore() async {
    try {
      final f = await _file();
      if (f == null || !f.existsSync()) return;
      final j = jsonDecode(await f.readAsString()) as Map;
      meId = '${j['me'] ?? ''}';
      meName = '${j['me_name'] ?? ''}';
      primaryId = '${j['primary'] ?? ''}';
      settings = CSettings.fromJson(j['settings'] as Map? ?? const {});
      hop = j['hop'] == true;
      calendars = [for (final c in j['calendars'] as List? ?? const []) CCalendar.fromJson(c as Map)];
      (j['months'] as Map? ?? const {}).forEach((k, v) => _months['$k'] = [for (final e in v as List) CEvent.fromJson(e as Map)]);
      loaded = calendars.isNotEmpty;
    } catch (e) {
      debugPrint('[calendar] bộ nhớ đệm hỏng, bỏ qua: $e');
    }
  }

  void _persist() {
    if (cacheKey == null) return;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 800), () async {
      try {
        final f = await _file();
        if (f == null) return;
        // Chỉ giữ tháng đang xem ±1 cho nhẹ.
        final c = _viewFrom ?? today;
        final keep = {monthKey(DateTime.utc(c.year, c.month - 1)), monthKey(c), monthKey(DateTime.utc(c.year, c.month + 1))};
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode({
          'me': meId,
          'me_name': meName,
          'primary': primaryId,
          'settings': settings.toJson(),
          'hop': hop,
          'calendars': [for (final x in calendars) x.toJson()],
          'months': {for (final k in keep) if (_months[k] != null) k: [for (final e in _months[k]!) e.toJson()]},
        }));
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('[calendar] không lưu được bộ nhớ đệm: $e');
      }
    });
  }

  // ------------------------------------------------------------ tải
  Future<void> start() async {
    await _restore();
    if (loaded) _changed(persist: false);
    await Future.wait([_loadMe(), refreshCalendars()]);
    loaded = true;
    _changed();
  }

  Future<void> _loadMe() async {
    try {
      final j = await api.me();
      final u = j['user'] as Map? ?? const {};
      meId = '${u['id'] ?? meId}';
      meName = '${u['name'] ?? meName}';
      meUsername = '${u['username'] ?? ''}';
      primaryId = '${j['primary_calendar'] ?? primaryId}';
      if (j['settings'] is Map) settings = CSettings.fromJson(j['settings'] as Map);
      colors = [for (final c in j['colors'] as List? ?? const []) '$c'];
      hop = (j['features'] as Map?)?['hop'] == true;
      offline = false;
    } catch (e) {
      _netError(e);
    }
  }

  Future<void> refreshCalendars() async {
    try {
      calendars = await api.calendars();
      offline = false;
      _changed();
    } catch (e) {
      _netError(e);
      _changed(persist: false);
    }
  }

  static String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static Iterable<DateTime> _monthsIn(DateTime from, DateTime to) sync* {
    var m = DateTime.utc(from.year, from.month);
    while (m.isBefore(to)) {
      yield m;
      m = DateTime.utc(m.year, m.month + 1);
    }
  }

  bool hasMonth(DateTime d) => _months.containsKey(monthKey(d));
  bool loading(DateTime from, DateTime to) => _monthsIn(from, to).any((m) => _loading.containsKey(monthKey(m)));

  /// Đảm bảo đã có sự kiện trong [from, to) (giờ tường). Tháng đã có và còn mới (< 60 giây) thì thôi, trừ khi [force].
  Future<void> ensureRange(DateTime from, DateTime to, {bool force = false, bool view = true}) async {
    if (view) {
      _viewFrom = from;
      _viewTo = to;
    }
    final jobs = <Future<void>>[];
    for (final m in _monthsIn(from, to)) {
      final k = monthKey(m);
      final at = _fetchedAt[k];
      if (!force && at != null && DateTime.now().difference(at).inSeconds < 60) continue;
      jobs.add(_loading[k] ??= _fetchMonth(m).whenComplete(() => _loading.remove(k)));
    }
    if (jobs.isEmpty) return;
    _changed(persist: false);
    await Future.wait(jobs);
    _changed();
  }

  Future<void> _fetchMonth(DateTime m) async {
    final k = monthKey(m);
    try {
      _months[k] = await api.events(from: fmtDate(m), to: fmtDate(DateTime.utc(m.year, m.month + 1)));
      _fetchedAt[k] = DateTime.now();
      offline = false;
      error = null;
    } catch (e) {
      _netError(e);
    }
  }

  /// Tải lại khoảng đang xem (sau khi sửa, khi quay lại app).
  Future<void> refresh() async {
    final f = _viewFrom, t = _viewTo;
    // Tháng ngoài khoảng đang xem: coi như cũ, lần xem sau tự tải lại.
    _fetchedAt.clear();
    if (f != null && t != null) await ensureRange(f, t, force: true);
  }

  /// Các lần xảy ra trong [from, to) đang hiện (đã lọc lịch ẩn, từ chối, huỷ), sắp theo giờ bắt đầu.
  List<CEvent> eventsIn(DateTime from, DateTime to, {bool all = false}) {
    final seen = <String>{};
    final out = <CEvent>[];
    for (final m in _monthsIn(DateTime.utc(from.year, from.month - 1), DateTime.utc(to.year, to.month + 1))) {
      for (final e in _months[monthKey(m)] ?? const <CEvent>[]) {
        if (!seen.add(e.instanceId)) continue;
        if (!all && !shows(e)) continue;
        if (e.wallStart(tz).isBefore(to) && e.wallEnd(tz).isAfter(from)) out.add(e);
        // Sự kiện 0 phút (mốc): vẫn hiện trong ngày của nó.
        if (e.wallStart(tz) == e.wallEnd(tz) && !e.wallStart(tz).isBefore(from) && e.wallStart(tz).isBefore(to) && !out.contains(e)) out.add(e);
      }
    }
    out.sort((a, b) {
      final c = a.wallStart(tz).compareTo(b.wallStart(tz));
      return c != 0 ? c : b.wallEnd(tz).compareTo(a.wallEnd(tz));
    });
    return out;
  }

  /// Tìm theo chữ trong khoảng ±1 năm quanh [around].
  Future<List<CEvent>> search(String q, DateTime around) async {
    final r = await api.events(from: fmtDate(DateTime.utc(around.year - 1, around.month)), to: fmtDate(DateTime.utc(around.year + 1, around.month)), q: q);
    r.sort((a, b) => a.wallStart(tz).compareTo(b.wallStart(tz)));
    return r.where((e) => !e.cancelled).toList();
  }

  // ------------------------------------------------------------ sửa sự kiện
  /// Tìm lần xảy ra trong bộ nhớ (mở từ tin nhắn bot).
  CEvent? cached(String id, {String? rid}) {
    for (final l in _months.values) {
      for (final e in l) {
        if (e.id == id && (rid == null || e.rid == rid)) return e;
      }
    }
    return null;
  }

  void _replaceLocal(String instanceId, CEvent? e) {
    for (final l in _months.values) {
      final i = l.indexWhere((x) => x.instanceId == instanceId);
      if (i < 0) continue;
      if (e == null) {
        l.removeAt(i);
      } else {
        l[i] = e;
      }
    }
  }

  Future<T> _mutate<T>(Future<T> Function() f) async {
    try {
      final r = await f();
      offline = false;
      return r;
    } catch (e) {
      if (CalApi.isOffline(e)) offline = true;
      _changed(persist: false);
      rethrow;
    } finally {
      unawaited(refresh());
    }
  }

  Future<CEvent> create(Map<String, dynamic> body) => _mutate(() async {
        final e = await api.create(body);
        final k = monthKey(e.wallStart(tz));
        (_months[k] ??= []).add(e);
        _changed();
        return e;
      });

  /// Sửa [e] theo phạm vi [scope] (this | following | all; sự kiện đơn thì bỏ qua). Sửa "tất cả" mà đổi giờ thì dời
  /// giờ của chuỗi gốc đúng bằng độ lệch của lần này.
  Future<CEvent> update(CEvent e, Map<String, dynamic> body, {String scope = 'all'}) => _mutate(() async {
        final b = e.recurring && scope == 'all' ? await _shiftMaster(e, body) : body;
        final r = await api.update(e.id, b, scope: e.recurring ? scope : null, rid: e.recurring && scope != 'all' ? e.rid : null);
        if (!e.recurring) _replaceLocal(e.instanceId, r);
        _changed();
        return r;
      });

  Future<Map<String, dynamic>> _shiftMaster(CEvent e, Map<String, dynamic> body) async {
    if (!body.containsKey('start') && !body.containsKey('end')) return body;
    final master = await api.event(e.id);
    final allDay = body['all_day'] as bool? ?? e.allDay;
    if (allDay != master.allDay) return body; // đổi kiểu cả ngày: lấy đúng giờ đã chọn
    final out = {...body};
    if (allDay) {
      final ds = daysBetween(parseLocal(e.start), parseLocal('${body['start'] ?? e.start}'));
      final de = daysBetween(parseLocal(e.end), parseLocal('${body['end'] ?? e.end}'));
      out['start'] = fmtDate(addDays(parseLocal(master.start), ds));
      out['end'] = fmtDate(addDays(parseLocal(master.end.isEmpty ? master.start : master.end), de));
      return out;
    }
    final btz = '${body['tz'] ?? e.tz}';
    int ms(String s, String z) => msOfWall(parseLocal(s), z);
    final ds = ms('${body['start'] ?? e.start}', btz) - ms(e.start, e.tz);
    final de = ms('${body['end'] ?? e.end}', btz) - ms(e.end, e.tz);
    out['start'] = fmtLocal(wallOf(ms(master.start, master.tz) + ds, btz));
    out['end'] = fmtLocal(wallOf(ms(master.end, master.tz) + de, btz));
    return out;
  }

  /// Kéo thả: dời [e] tới [startW, endW) (giờ tường của người dùng).
  Future<CEvent> moveTime(CEvent e, DateTime startW, DateTime endW, {String scope = 'all'}) {
    final Map<String, dynamic> body;
    if (e.allDay) {
      body = {'start': fmtDate(startW), 'end': fmtDate(endW)};
    } else {
      final s = msOfWall(startW, tz), en = msOfWall(endW, tz);
      body = {'start': fmtLocal(wallOf(s, e.tz)), 'end': fmtLocal(wallOf(en, e.tz))};
      // Hiện ngay chỗ mới, chờ máy chủ trả bản đúng.
      final local = e.clone()
        ..startMs = s
        ..endMs = en
        ..start = body['start'] as String
        ..end = body['end'] as String;
      _replaceLocal(e.instanceId, local);
      _changed(persist: false);
    }
    return update(e, body, scope: scope);
  }

  Future<void> remove(CEvent e, {String scope = 'all', bool notify = true}) => _mutate(() async {
        _replaceLocal(e.instanceId, null);
        _changed(persist: false);
        await api.remove(e.id, scope: e.recurring ? scope : null, rid: e.recurring && scope != 'all' ? e.rid : null, notify: notify);
      });

  Future<CEvent> rsvp(CEvent e, String value, {String scope = 'all', String? comment}) => _mutate(() async {
        e.myRsvp = value;
        for (final a in e.attendees) {
          if (a.id == meId) a.rsvp = value;
        }
        _changed(persist: false);
        return api.rsvp(e.id, value, scope: e.recurring ? scope : 'all', rid: e.recurring && scope == 'this' ? e.rid : null, comment: comment);
      });

  Future<CEvent> moveToCalendar(CEvent e, String calendarId) => _mutate(() => api.move(e.id, calendarId));

  Future<CEvent> setReminders(CEvent e, List<CReminder> r) => _mutate(() => api.reminders(e.id, r));

  /// Nhân bản: sự kiện mới cùng nội dung (không lặp lại khách đã trả lời).
  Map<String, dynamic> copyBody(CEvent e) => {
        'id': calId(),
        'calendar_id': calendar(e.calendarId)?.canWrite ?? false ? e.calendarId : primaryId,
        'title': e.title,
        'description': e.description,
        'location': e.location,
        'all_day': e.allDay,
        'start': e.start,
        'end': e.end,
        'tz': e.tz,
        'busy': e.busy,
        'visibility': e.visibility,
        'color': e.color,
        'attendees': [for (final a in e.attendees) if (!a.organizer) {'principal': a.principal, 'optional': a.optional}],
        'guest_perms': e.guestPerms,
        'notice': e.notice,
        'reminders': [for (final r in e.reminders) r.toJson()],
        'attachments': [for (final f in e.attachments) f.id],
      };

  // ------------------------------------------------------------ lịch
  Future<void> setPrefs(CCalendar c, {bool? hidden, String? color, bool? subscribed}) async {
    if (hidden != null) c.hidden = hidden;
    if (color != null) c.colorOverride = color;
    if (subscribed != null) c.subscribed = subscribed;
    _changed();
    try {
      final r = await api.prefs(c.id, {'hidden': ?hidden, 'color': ?color, 'subscribed': ?subscribed});
      final i = calendars.indexWhere((x) => x.id == c.id);
      if (i >= 0) calendars[i] = r;
      offline = false;
    } catch (e) {
      _netError(e);
    }
    // Hiện lại một lịch đang ẩn: máy chủ chỉ trả sự kiện của lịch đang hiện, nên tải lại.
    if (hidden == false) await refresh();
    _changed();
  }

  /// "Chỉ hiển thị lịch này": ẩn mọi lịch khác.
  Future<void> onlyThis(CCalendar c) async {
    for (final x in calendars) {
      final h = x.id != c.id;
      if (x.hidden != h) unawaited(setPrefs(x, hidden: h));
    }
  }

  Future<CCalendar> saveCalendar(String id, Map<String, dynamic> body) => _mutate(() async {
        final c = await api.putCalendar(id, body);
        final i = calendars.indexWhere((x) => x.id == id);
        if (i >= 0) {
          calendars[i] = c;
        } else {
          calendars.add(c);
        }
        _changed();
        unawaited(refreshCalendars());
        return c;
      });

  Future<void> deleteCalendar(CCalendar c) => _mutate(() async {
        await api.deleteCalendar(c.id);
        calendars.removeWhere((x) => x.id == c.id);
        _changed();
      });

  Future<void> putSettings(Map<String, dynamic> patch) async {
    settings = CSettings.fromJson({...settings.toJson(), ...patch});
    _changed();
    try {
      settings = await api.putSettings(patch);
      offline = false;
    } catch (e) {
      _netError(e);
    }
    if (patch.containsKey('tz') || patch.containsKey('show_declined')) await refresh();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_save?.isActive ?? false) _persist(); // lần lưu đang chờ vẫn chạy sau khi đóng màn hình
    super.dispose();
  }
}
