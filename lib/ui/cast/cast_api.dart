// "Đưa lên màn hình": gọi cổng màn hình trên trạm của máy chủ chat (push.<tên miền>/cast/…, trang màn hình hello.<tên miền>).
// Một màn hình một người chiếu; người quét sau vào hàng chờ. Trạng thái về qua SSE /cast/c/<ctl>/events.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../config.dart';

const _abc = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Mã màn hình từ nội dung QR (`https://hello.<tên miền>/p/<mã>`) hoặc chữ gõ tay (có / không gạch). Null nếu không phải.
String? parseScreenCode(String raw) {
  final s = raw.trim();
  final m = RegExp(r'/p/([A-Za-z0-9]{8})(?:[/?#]|$)').firstMatch(s);
  final c = (m != null ? m[1]! : s.replaceAll(RegExp(r'[\s-]'), '')).toUpperCase();
  return c.length == 8 && c.split('').every(_abc.contains) ? c : null;
}

/// Mã QR của màn hình thuộc máy chủ khác (hello.dnd-global.com khi đang đăng nhập chat.flygo.vn): tên miền của màn hình.
String? foreignScreenHost(String raw, String server) {
  final u = Uri.tryParse(raw.trim());
  if (u == null || !u.hasScheme || !u.host.startsWith('hello.')) return null;
  final mine = Uri.tryParse(server)?.host ?? '';
  String dom(String h) => (h.split('.')..removeAt(0)).join('.');
  return dom(u.host) == dom(mine) ? null : u.host;
}

class CastError implements Exception {
  final int status;
  final String message;

  /// 423 (màn hình đang khoá): id màn hình + thông tin khoá, để hỏi "Xin dùng".
  final Map? body;
  CastError(this.status, this.message, [this.body]);
  bool get locked => status == 423;
  String? get screenId => body?['screen_id'] as String?;
  @override
  String toString() => message;
}

/// Trạng thái phiên điều khiển: presenter | queued | ended.
class CastState {
  final String role, screen, nowBy, why;
  final int position, queue;
  final List<String> queueNames;
  final Map<String, dynamic>? content;
  final bool blank;

  /// Khoá màn hình {by_name, until, mine, meeting?}; null = không khoá.
  final Map? lock;
  final String screenId;

  /// role == 'request': ai đó xin dùng màn hình (chỉ là thông báo, không đổi trạng thái).
  final String requestFrom;
  CastState(
    this.role, {
    this.lock,
    this.screenId = '',
    this.requestFrom = '',
    this.screen = '',
    this.nowBy = '',
    this.why = '',
    this.position = 0,
    this.queue = 0,
    this.queueNames = const [],
    this.content,
    this.blank = false,
  });
  factory CastState.fromJson(Map j) {
    final now = j['now'] as Map?;
    return CastState(
      '${j['role'] ?? 'ended'}',
      screen: '${j['screen'] ?? ''}',
      nowBy: '${now?['by_name'] ?? j['now_by'] ?? ''}',
      why: '${j['why'] ?? ''}',
      position: (j['position'] as num?)?.toInt() ?? 0,
      queue: (j['queue'] as num?)?.toInt() ?? 0,
      queueNames: [for (final x in (j['queue_names'] as List? ?? const [])) '$x'],
      content: (now?['content'] as Map?)?.cast<String, dynamic>(),
      blank: now?['blank'] == true,
      lock: j['lock'] as Map?,
      screenId: '${j['screen_id'] ?? ''}',
    );
  }
  bool get presenting => role == 'presenter';
  bool get ended => role == 'ended';
  int get page => (content?['page'] as num?)?.toInt() ?? 1;
  Map? get media => content?['media'] as Map?;

  /// Vị trí video hiện tại (giây) theo lệnh gần nhất.
  double videoPos([int? serverSkewMs]) {
    final m = media;
    if (m == null) return 0;
    final t = (m['t'] as num?)?.toDouble() ?? 0;
    if (m['playing'] != true) return t;
    final at = (m['at'] as num?)?.toInt() ?? 0;
    return t + (DateTime.now().millisecondsSinceEpoch + (serverSkewMs ?? 0) - at) / 1000;
  }
}

class CastSession {
  final String server, token, ctl;
  final CastState first;
  CastSession._(this.server, this.token, this.ctl, this.first);

  static String _base(String server) => '${pushUrlFor(server)}/cast';
  Map<String, String> get _h => {'Authorization': 'Bearer $token', 'X-MM-Server': server, 'User-Agent': kUserAgent};

  static Future<Map> _check(http.Response r) async {
    Map j = const {};
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    } catch (_) {}
    if (r.statusCode != 200) throw CastError(r.statusCode, '${j['error'] ?? 'lỗi ${r.statusCode}'}', j);
    return j;
  }

  /// Ghép với màn hình có [code]. Màn hình đang có người chiếu thì vào hàng chờ.
  /// Ghép theo [code] (quét / gõ) hoặc chọn thẳng [screenId] trong danh sách màn hình của công ty.
  static Future<CastSession> pair(String server, String token, {String? code, String? screenId}) async {
    await discoverPush(server);
    if (pushUrlFor(server).isEmpty) throw CastError(0, 'Máy chủ này chưa có cổng màn hình');
    final r = await http
        .post(Uri.parse('${_base(server)}/pair'), headers: _hdr(server, token), body: jsonEncode({'code': ?code, 'screen_id': ?screenId}))
        .timeout(const Duration(seconds: 15));
    final j = await _check(r);
    return CastSession._(server, token, '${j['ctl']}', CastState.fromJson(j));
  }

  static Map<String, String> _hdr(String server, String token) => {
    'Authorization': 'Bearer $token',
    'X-MM-Server': server,
    'User-Agent': kUserAgent,
    'Content-Type': 'application/json',
  };

  /// Màn hình của công ty (đang mở hello) + màn hình mình dùng gần đây.
  static Future<List<CastScreen>> screens(String server, String token) async {
    await discoverPush(server);
    if (pushUrlFor(server).isEmpty) return const [];
    final r = await http.get(Uri.parse('${_base(server)}/screens'), headers: _hdr(server, token)).timeout(const Duration(seconds: 10));
    final j = await _check(r);
    return [for (final x in (j['screens'] as List? ?? const [])) CastScreen.fromJson(x as Map)];
  }

  /// Màn hình: đổi tên (name) / mở khoá (unlock) / xin dùng (request: báo người khoá hoặc người đang chiếu).
  static Future<Map> screenAction(String server, String token, String screenId, String act, [Map body = const {}]) async => _check(
    await http
        .post(Uri.parse('${_base(server)}/screens/$screenId/$act'), headers: _hdr(server, token), body: jsonEncode(body))
        .timeout(const Duration(seconds: 10)),
  );

  /// Thêm màn hình vào cuộc họp ([code] phòng họp có mã, hoặc [channelId] cuộc họp trong nhóm): màn hình vào phòng,
  /// khoá cho thành viên cuộc họp; phiên điều khiển này kết thúc. Trả về tiêu đề cuộc họp.
  Future<String> joinMeeting({String? code, String? channelId}) async =>
      '${(await _post('meeting', {'code': ?code, 'channel_id': ?channelId}))['title'] ?? ''}';

  /// Khoá màn hình từ xa (chỉ mình và admin chiếu được; tự mở sau 2 giờ không dùng hoặc cuối ngày).
  Future<void> lock(bool on) => _post('lock', {'on': on});

  Future<Map> _post(String act, Object body) async => _check(
    await http
        .post(Uri.parse('${_base(server)}/c/$ctl/$act'), headers: {..._h, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15)),
  );

  /// Chiếu tệp (người đang chiếu): [type] pdf | image | video, [mime] đúng loại tệp (vd image/png, video/mp4).
  /// [auto]: PDF tự lật trang mỗi [auto] giây (bảng tin xoay vòng), 0 = không.
  Future<void> showFile(File f, {required String type, required String mime, required String name, int pages = 0, String app = '', int auto = 0}) async {
    final q = Uri(queryParameters: {'type': type, 'name': name, if (type == 'pdf') 'pages': '$pages', if (auto > 0) 'auto': '$auto', 'app': app}).query;
    final req = http.StreamedRequest('POST', Uri.parse('${_base(server)}/c/$ctl/content?$q'))
      ..headers.addAll({..._h, 'Content-Type': mime})
      ..contentLength = await f.length();
    f.openRead().listen(req.sink.add, onDone: req.sink.close, onError: req.sink.addError);
    final r = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 10)));
    await _check(r);
  }

  /// Chiếu màn hình máy tính: trạm trả token LiveKit chỉ được phát màn hình vào phòng của màn hình này.
  Future<({String url, String token})> mirror(String name) async {
    final r = await http
        .post(Uri.parse('${_base(server)}/c/$ctl/mirror?${Uri(queryParameters: {'name': name}).query}'), headers: _h)
        .timeout(const Duration(seconds: 15));
    final j = await _check(r);
    return (url: '${j['url']}', token: '${j['token']}');
  }

  Future<void> showUrl(String type, String url, {String name = '', String app = ''}) => _post('content', {'type': type, 'url': url, 'name': name, 'app': app});
  Future<int> page(int n) async => ((await _post('page', {'page': n}))['page'] as num?)?.toInt() ?? n;
  Future<void> blank(bool on) => _post('blank', {'on': on});

  /// Video: phát / dừng ([playing]), tua tới giây [t].
  Future<void> media({bool? playing, double? t}) => _post('media', {'playing': ?playing, 't': ?t});
  Future<void> stop() => _post('stop', {}).then((_) {}, onError: (_) {});

  DateTime _lastLaser = DateTime(2000);
  bool _laserBusy = false;

  /// Laser (x, y từ 0 đến 1 của trang). Gửi tối đa ~12 lần / giây, bỏ qua khi lần trước chưa xong.
  void laser(double x, double y, {bool on = true}) {
    final now = DateTime.now();
    if (on && (_laserBusy || now.difference(_lastLaser).inMilliseconds < 80)) return;
    _lastLaser = now;
    _laserBusy = true;
    _post('laser', {'x': x, 'y': y, 'on': on}).whenComplete(() => _laserBusy = false).ignore();
  }

  /// Sự kiện trạng thái (tự nối lại khi rớt mạng; dừng khi phiên kết thúc hoặc huỷ đăng ký).
  Stream<CastState> events() {
    late StreamController<CastState> out;
    http.Client? client;
    var stopped = false;
    Future<void> run() async {
      var backoff = 1;
      while (!stopped) {
        try {
          client = http.Client();
          final req = http.Request('GET', Uri.parse('${_base(server)}/c/$ctl/events'))..headers.addAll(_h);
          final res = await client!.send(req);
          if (res.statusCode == 404) {
            out.add(CastState('ended', why: 'gone'));
            break;
          }
          if (res.statusCode != 200) throw CastError(res.statusCode, 'events ${res.statusCode}');
          backoff = 1;
          var ev = '';
          await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
            if (line.startsWith('event: ')) ev = line.substring(7);
            if (line.startsWith('data: ') && ev == 'request') {
              final d = jsonDecode(line.substring(6)) as Map;
              out.add(CastState('request', requestFrom: '${d['from'] ?? ''}'));
            }
            if (line.startsWith('data: ') && ev == 'state') {
              final st = CastState.fromJson(jsonDecode(line.substring(6)) as Map);
              out.add(st);
              if (st.ended) stopped = true;
            }
          }
        } catch (_) {
          // rớt mạng: thử lại
        } finally {
          client?.close();
        }
        if (stopped) break;
        await Future.delayed(Duration(seconds: backoff));
        backoff = (backoff * 2).clamp(1, 10);
      }
      await out.close();
    }

    out = StreamController<CastState>(
      onListen: run,
      onCancel: () {
        stopped = true;
        client?.close();
      },
    );
    return out.stream;
  }
}

/// Một màn hình trong danh sách của công ty.
class CastScreen {
  final String id, name, status, nowBy;
  final bool online, approved, recent;
  final int queue;
  final Map? lock;
  CastScreen.fromJson(Map j)
    : id = '${j['id']}',
      name = '${j['name'] ?? ''}',
      status = '${j['status'] ?? 'idle'}',
      nowBy = '${j['now_by'] ?? ''}',
      online = j['online'] == true,
      approved = j['approved'] == true,
      recent = j['recent'] == true,
      queue = (j['queue'] as num?)?.toInt() ?? 0,
      lock = j['lock'] as Map?;
}
