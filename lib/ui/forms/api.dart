// Biểu mẫu (vn.flygo.forms): gọi backend forms (flygo-chat-server forms/) bằng vé Flygo ID, kênh realtime WebSocket,
// và Flows cho tab Tự động hoá (vé Flows + giấy phép biểu mẫu). Đặc tả API: flygo-chat-server forms/README.md.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../browser/flygo_id.dart';
import '../../config.dart';
import 'model.dart';

const kFormsApp = 'vn.flygo.forms';
const kFormsScreen = 'forms';

class FormsException implements Exception {
  FormsException(this.status, this.message, [this.body = const {}]);
  final int status;
  final String message;
  final Json body;
  Map<String, String> get errors => {for (final e in ((body['errors'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
  @override
  String toString() => message;
}

class FormsApi {
  FormsApi({required this.base, required this.id, this.server, http.Client? client}) : _http = client ?? http.Client();

  /// base_url của app (vd https://chat.example.com/__apps/forms).
  final String base;
  final FlygoId id;

  /// Máy chủ chat (gọi Flows ở `<server>/__apps/flows`). Mặc định lấy theo base.
  final String? server;
  final http.Client _http;

  String get chatServer => server ?? Uri.parse(base).origin;

  /// Kiểm thử: tắt kênh realtime (không nối WebSocket thật).
  static bool liveEnabled = true;

  Future<Map<String, String>> _auth({bool refresh = false}) async =>
      {'Authorization': 'Bearer ${await id.ticket(kFormsApp, refresh: refresh).timeout(const Duration(seconds: 25))}', 'User-Agent': kUserAgent};

  Uri uri(String path, [Map<String, String>? q]) => Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path').replace(queryParameters: q);

  Future<http.Response> _send(String method, String path, {Object? body, Map<String, String>? query, bool retried = false}) async {
    final req = http.Request(method, uri(path, query))..headers.addAll(await _auth(refresh: retried));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 40));
    if (res.statusCode == 401 && !retried) return _send(method, path, body: body, query: query, retried: true);
    return res;
  }

  Json _json(http.Response res) {
    Json j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw FormsException(res.statusCode, '${j['error'] ?? 'Biểu mẫu trả lỗi ${res.statusCode}'}', j);
    return j;
  }

  Future<Json> get(String path, [Map<String, String>? q]) async => _json(await _send('GET', path, query: q));
  Future<Json> post(String path, [Object? body]) async => _json(await _send('POST', path, body: body ?? const {}));
  Future<Json> put(String path, Object body) async => _json(await _send('PUT', path, body: body));
  Future<Json> delete(String path) async => _json(await _send('DELETE', path));

  /// Tải tệp lên: [path] = `/api/files` (tệp câu trả lời) hoặc `/api/forms/<id>/images` (ảnh trong biểu mẫu).
  Future<Json> upload(String name, Uint8List bytes, {String path = '/api/files'}) async {
    Future<http.Response> go(bool refresh) async {
      final req = http.MultipartRequest('POST', uri(path))
        ..headers.addAll(await _auth(refresh: refresh))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 5)));
    }

    var res = await go(false);
    if (res.statusCode == 401) res = await go(true);
    return Map<String, dynamic>.from(_json(res)['file'] as Map);
  }

  /// Tải nội dung nhị phân (xuất Excel / CSV, tệp, ảnh).
  Future<Uint8List> bytes(String path, [Map<String, String>? q]) async {
    final res = await _send('GET', path, query: q);
    if (res.statusCode >= 400) _json(res);
    return res.bodyBytes;
  }

  /// Header cho ảnh trong biểu mẫu (Image.network).
  Future<Map<String, String>> imageHeaders() => _auth();

  // ---------------------------------------------------------------- realtime
  /// Kênh realtime: nhận {type: response | form | deleted, form, …} của các biểu mẫu đã đăng ký.
  Future<FormsLive> live(List<String> forms) async {
    if (!liveEnabled) throw StateError('realtime tắt');
    final t = await id.ticket(kFormsApp);
    final u = uri('/ws', {'ticket': t});
    final ws = WebSocketChannel.connect(u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws'));
    await ws.ready;
    final l = FormsLive._(ws);
    l.subscribe(forms);
    return l;
  }

  // ---------------------------------------------------------------- Flows (Tự động hoá)
  Future<Map<String, String>> _flowsHeaders(String formId) async {
    final g = await get('/api/forms/$formId/flows-grant');
    return {
      'Authorization': 'Bearer ${await id.ticket('vn.flygo.flows')}',
      'X-MM-Server': chatServer,
      'X-Flygo-Form-Grant': '${g['grant']}',
      'Content-Type': 'application/json',
      'User-Agent': kUserAgent,
    };
  }

  Uri _flows(String path, [Map<String, String>? q]) => Uri.parse('${chatServer.replaceAll(RegExp(r'/+$'), '')}/__apps/flows/flows/integrations/forms$path').replace(queryParameters: q);

  Future<Json> _flowsCall(String method, String formId, String path, {Object? body, Map<String, String>? q}) async {
    final req = http.Request(method, _flows(path, q))..headers.addAll(await _flowsHeaders(formId));
    if (body != null) req.body = jsonEncode(body);
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 30));
    Json j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw FormsException(res.statusCode, '${j['error'] ?? 'Quy trình trả lỗi ${res.statusCode}'}', j);
    return j;
  }

  /// Quy trình gắn với biểu mẫu.
  Future<List<Json>> flows(String formId) async =>
      [for (final f in ((await _flowsCall('GET', formId, '/defs', q: {'form_id': formId}))['flows'] as List? ?? const [])) Map<String, dynamic>.from(f as Map)];
  Future<Json> saveFlow(String formId, Json def) => _flowsCall('POST', formId, '/defs', body: def);
  Future<Json> checkFlow(String formId, Json def, {Json? answers}) =>
      _flowsCall('POST', formId, '/defs/check', body: {'def': def, if (answers != null) 'form': {'answers': answers, 'files': const {}}});
  Future<Json> setFlowActive(String formId, String flowId, bool active) => _flowsCall('POST', formId, '/defs/$flowId/active', body: {'active': active});
}

class FormsLive {
  FormsLive._(this._ws) {
    _sub = _ws.stream.listen((m) {
      try {
        _out.add(Map<String, dynamic>.from(jsonDecode('$m') as Map));
      } catch (_) {}
    }, onError: (_) => _out.close(), onDone: () => _out.close());
    _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
  }
  final WebSocketChannel _ws;
  late final StreamSubscription<dynamic> _sub;
  late final Timer _ping;
  final _out = StreamController<Json>.broadcast();
  Stream<Json> get events => _out.stream;

  void _send(Object m) {
    try {
      _ws.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  void subscribe(List<String> forms) => _send({'type': 'sub', 'forms': forms});

  Future<void> close() async {
    _ping.cancel();
    await _sub.cancel();
    await _ws.sink.close();
    await _out.close();
  }
}
