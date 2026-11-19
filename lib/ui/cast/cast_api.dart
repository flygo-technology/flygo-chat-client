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
  CastError(this.status, this.message);
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
  CastState(this.role, {this.screen = '', this.nowBy = '', this.why = '', this.position = 0, this.queue = 0, this.queueNames = const [], this.content, this.blank = false});
  factory CastState.fromJson(Map j) {
    final now = j['now'] as Map?;
    return CastState('${j['role'] ?? 'ended'}',
        screen: '${j['screen'] ?? ''}',
        nowBy: '${now?['by_name'] ?? j['now_by'] ?? ''}',
        why: '${j['why'] ?? ''}',
        position: (j['position'] as num?)?.toInt() ?? 0,
        queue: (j['queue'] as num?)?.toInt() ?? 0,
        queueNames: [for (final x in (j['queue_names'] as List? ?? const [])) '$x'],
        content: (now?['content'] as Map?)?.cast<String, dynamic>(),
        blank: now?['blank'] == true);
  }
  bool get presenting => role == 'presenter';
  bool get ended => role == 'ended';
  int get page => (content?['page'] as num?)?.toInt() ?? 1;
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
    if (r.statusCode != 200) throw CastError(r.statusCode, '${j['error'] ?? 'lỗi ${r.statusCode}'}');
    return j;
  }

  /// Ghép với màn hình có [code]. Màn hình đang có người chiếu thì vào hàng chờ.
  static Future<CastSession> pair(String server, String token, String code) async {
    await discoverPush(server);
    if (pushUrlFor(server).isEmpty) throw CastError(0, 'Máy chủ này chưa có cổng màn hình');
    final r = await http
        .post(Uri.parse('${_base(server)}/pair'),
            headers: {'Authorization': 'Bearer $token', 'X-MM-Server': server, 'User-Agent': kUserAgent, 'Content-Type': 'application/json'},
            body: jsonEncode({'code': code}))
        .timeout(const Duration(seconds: 15));
    final j = await _check(r);
    return CastSession._(server, token, '${j['ctl']}', CastState.fromJson(j));
  }

  Future<Map> _post(String act, Object body) async =>
      _check(await http.post(Uri.parse('${_base(server)}/c/$ctl/$act'), headers: {..._h, 'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 15)));

  /// Chiếu tệp PDF (người đang chiếu).
  Future<void> showPdf(File pdf, {required String name, int pages = 0, String app = ''}) async {
    final q = Uri(queryParameters: {'type': 'pdf', 'name': name, 'pages': '$pages', 'app': app}).query;
    final r = await http
        .post(Uri.parse('${_base(server)}/c/$ctl/content?$q'), headers: {..._h, 'Content-Type': 'application/pdf'}, body: await pdf.readAsBytes())
        .timeout(const Duration(minutes: 3));
    await _check(r);
  }

  Future<void> showUrl(String type, String url, {String name = '', String app = ''}) => _post('content', {'type': type, 'url': url, 'name': name, 'app': app});
  Future<int> page(int n) async => ((await _post('page', {'page': n}))['page'] as num?)?.toInt() ?? n;
  Future<void> blank(bool on) => _post('blank', {'on': on});
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

    out = StreamController<CastState>(onListen: run, onCancel: () {
      stopped = true;
      client?.close();
    });
    return out.stream;
  }
}
