// Lịch (vn.flygo.calendar): gọi backend calendar (flygo-chat-server) bằng vé Flygo ID, giống Todo.
// Đặc tả API: flygo-chat-server calendar/README.md.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../browser/flygo_id.dart';
import '../../config.dart';
import 'model.dart';

const kCalApp = 'vn.flygo.calendar';

class CalException implements Exception {
  CalException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class CalApi {
  CalApi({required this.base, required this.id, http.Client? client}) : _http = client ?? http.Client();

  /// base_url của app (có thể kèm đường dẫn, vd https://chat.example.com/__apps/calendar).
  final String base;
  final FlygoId id;
  final http.Client _http;

  Future<Map<String, String>> _auth({bool refresh = false}) async =>
      {'Authorization': 'Bearer ${await id.ticket(kCalApp, refresh: refresh).timeout(const Duration(seconds: 25))}', 'User-Agent': kUserAgent};

  Uri _uri(String path) => Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<http.Response> _send(String method, String path, {Object? body, bool retried = false}) async {
    final req = http.Request(method, _uri(path))..headers.addAll(await _auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 30));
    // Vé vừa hết hạn hoặc quyền vừa đổi: xin vé mới và thử lại một lần.
    if (res.statusCode == 401 && !retried) return _send(method, path, body: body, retried: true);
    return res;
  }

  Map<String, dynamic> _json(http.Response res) {
    Map<String, dynamic> j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw CalException(res.statusCode, '${j['error'] ?? 'Lịch trả lỗi ${res.statusCode}'}');
    return j;
  }

  Future<Map<String, dynamic>> get(String path) async => _json(await _send('GET', path));
  Future<Map<String, dynamic>> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  Future<Map<String, dynamic>> patch(String path, Object body) async => _json(await _send('PATCH', path, body: body));
  Future<Map<String, dynamic>> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  Future<Map<String, dynamic>> delete(String path) async => _json(await _send('DELETE', path));

  /// Lỗi mạng (mất kết nối, hết giờ, máy chủ quá tải) → coi là mất mạng. Lỗi máy chủ trả (4xx) thì không.
  static bool isOffline(Object e) => e is! CalException || e.status >= 500 || e.status == 408 || e.status == 429;

  static String _q(Map<String, Object?> p) {
    final e = p.entries.where((x) => x.value != null && '${x.value}'.isNotEmpty);
    return e.isEmpty ? '' : '?${e.map((x) => '${x.key}=${Uri.encodeQueryComponent('${x.value}')}').join('&')}';
  }

  // ------------------------------------------------------------ người dùng + cài đặt
  Future<Map<String, dynamic>> me() => get('/api/me');
  Future<CSettings> putSettings(Map<String, dynamic> patch) async => CSettings.fromJson((await put('/api/settings', patch))['settings'] as Map? ?? const {});

  // ------------------------------------------------------------ lịch
  Future<List<CCalendar>> calendars() async => [for (final c in (await get('/api/calendars'))['calendars'] as List? ?? const []) if (c is Map) CCalendar.fromJson(c)];
  Future<CCalendar> putCalendar(String id, Map<String, dynamic> body) async => CCalendar.fromJson((await put('/api/calendars/$id', body))['calendar'] as Map);
  Future<void> deleteCalendar(String id) => delete('/api/calendars/$id');
  Future<List<CAcl>> acl(String id) async => [for (final a in (await get('/api/calendars/$id/acl'))['acl'] as List? ?? const []) if (a is Map) CAcl.fromJson(a)];
  Future<List<CAcl>> putAcl(String id, List<CAcl> acl) async =>
      [for (final a in (await put('/api/calendars/$id/acl', {'acl': [for (final x in acl) if (x.role != 'owner') x.toJson()]}))['acl'] as List? ?? const []) if (a is Map) CAcl.fromJson(a)];
  Future<CCalendar> prefs(String id, Map<String, dynamic> body) async => CCalendar.fromJson((await put('/api/calendars/$id/prefs', body))['calendar'] as Map);

  // ------------------------------------------------------------ sự kiện
  Future<List<CEvent>> events({required String from, required String to, List<String>? calendars, String? q, bool pending = false}) async {
    final j = await get('/api/events${_q({'from': from, 'to': to, 'calendars': calendars?.join(','), 'q': q, 'pending': pending ? '1' : null})}');
    return [for (final e in j['events'] as List? ?? const []) if (e is Map) CEvent.fromJson(e)];
  }

  Future<CEvent> event(String id, {String? rid}) async => CEvent.fromJson((await get('/api/events/$id${_q({'rid': rid})}'))['event'] as Map);
  Future<CEvent> create(Map<String, dynamic> body) async => CEvent.fromJson((await post('/api/events', body))['event'] as Map);
  Future<CEvent> update(String id, Map<String, dynamic> body, {String? scope, String? rid}) async =>
      CEvent.fromJson((await patch('/api/events/$id${_q({'scope': scope, 'rid': rid})}', body))['event'] as Map);
  Future<void> remove(String id, {String? scope, String? rid, bool notify = true}) => delete('/api/events/$id${_q({'scope': scope, 'rid': rid, 'notify': notify ? '1' : '0'})}');
  Future<CEvent> rsvp(String id, String value, {String? comment, String scope = 'all', String? rid}) async =>
      CEvent.fromJson((await post('/api/events/$id/rsvp', {'rsvp': value, 'comment': ?comment, 'scope': scope, 'rid': ?rid}))['event'] as Map);
  Future<CEvent> move(String id, String calendarId) async => CEvent.fromJson((await post('/api/events/$id/move', {'calendar_id': calendarId}))['event'] as Map);
  Future<CEvent> reminders(String id, List<CReminder> r) async => CEvent.fromJson((await put('/api/events/$id/reminders', {'reminders': [for (final x in r) x.toJson()]}))['event'] as Map);

  // ------------------------------------------------------------ người, rảnh / bận
  Future<(List<CPerson>, List<CChannel>)> people(String q) async {
    final j = await get('/api/people${_q({'q': q})}');
    return (
      [for (final p in j['people'] as List? ?? const []) if (p is Map) CPerson.fromJson(p)],
      [for (final c in j['channels'] as List? ?? const []) if (c is Map) CChannel.fromJson(c)],
    );
  }

  /// Đổi email thành người dùng trên máy chủ: (người tìm thấy, email không có ai).
  Future<(List<CPerson>, List<String>)> resolveEmails(List<String> emails) async {
    final j = await post('/api/people/resolve', {'emails': emails});
    return ([for (final p in j['people'] as List? ?? const []) if (p is Map) CPerson.fromJson(p)], [for (final e in j['unknown'] as List? ?? const []) '$e']);
  }

  /// Khoảng bận của từng người: id → [[start_ms, end_ms]], kèm tên.
  Future<(Map<String, List<(int, int)>>, Map<String, String>)> freebusy(List<String> users, {required String from, required String to, String? tz}) async {
    final j = await post('/api/freebusy', {'users': users, 'from': from, 'to': to, 'tz': ?tz});
    final busy = <String, List<(int, int)>>{};
    (j['busy'] as Map? ?? const {}).forEach((k, v) {
      busy['$k'] = [for (final x in (v as List? ?? const [])) if (x is List && x.length >= 2) ((x[0] as num).toInt(), (x[1] as num).toInt())];
    });
    return (busy, {for (final e in (j['names'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'});
  }

  Future<List<CSlot>> findTime(List<String> users,
      {required String from, required String to, int duration = 60, String? workStart, String? workEnd, bool includeWeekends = false, int limit = 10}) async {
    final j = await post('/api/find-time', {
      'users': users,
      'from': from,
      'to': to,
      'duration': duration,
      'work_start': ?workStart,
      'work_end': ?workEnd,
      'include_weekends': includeWeekends,
      'limit': limit,
    });
    return [for (final s in j['slots'] as List? ?? const []) if (s is Map) CSlot.fromJson(s)];
  }

  Future<List<Map<String, dynamic>>> holidays(int year) async => [for (final h in (await get('/api/holidays?year=$year'))['holidays'] as List? ?? const []) if (h is Map) h.cast<String, dynamic>()];

  // ------------------------------------------------------------ tệp
  /// Tải một tệp lên (chưa gắn vào sự kiện).
  Future<CFile> upload(String name, Uint8List bytes) async {
    Future<http.Response> go(bool refresh) async {
      final req = http.MultipartRequest('POST', _uri('/api/files'))
        ..headers.addAll(await _auth(refresh: refresh))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 5)));
    }

    var res = await go(false);
    if (res.statusCode == 401) res = await go(true);
    return CFile.fromJson(_json(res)['file'] as Map);
  }

  /// Tải tệp đính kèm về thư mục tạm để mở bằng app khác.
  Future<String> download(CFile f) async {
    final res = await _send('GET', '/api/files/${f.id}');
    if (res.statusCode >= 400) _json(res);
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}calendar');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${f.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }
}
