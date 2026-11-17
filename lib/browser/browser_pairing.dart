// Ghép cặp tự động extension Flygo Browser Bridge với tài khoản đang đăng nhập Flygo Chat trên CÙNG máy (bản máy tính).
// App mở 127.0.0.1:47800 chỉ để ghép cặp (không chuyển lệnh): extension dò thấy app thì xin token client, rồi tự nối thẳng
// WebSocket bridge của Gateway (<máy chủ chat>/__apps/gateway/ws). Chỉ trả lời extension của mình (Origin
// chrome-extension://<id>, hoặc không có Origin mà có header X-Flygo-Bridge = id: trang web không gửi được header riêng
// tới 127.0.0.1 mà không qua preflight CORS, và ở đây không trả lời preflight). Mỗi lần ghép cặp hiện thông báo một lần.
//   GET  /flygo/hello  -> {app:"flygo-chat", role:"pairing", server (đang mở), user, servers:[{url, name, current}]}
//   POST /flygo/pair {server?, client:{name, engine, os}, replace?} -> {server, ws_url, token, client, user}
// Đăng nhập nhiều máy chủ: extension tự chọn máy chủ có bridge (servers là mọi máy chủ có phiên đã lưu).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../config.dart';
import '../data/servers.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'my_browsers.dart';

const kBrowserPairPort = 47800;
const kBridgeExtensionIds = {'pknpafgfaedabfloepblchniacfknjig'};

class BrowserPairing {
  BrowserPairing._();
  static HttpServer? _server;
  static AppState? _app;
  static GlobalKey<NavigatorState>? _nav;
  static final List<DateTime> _hits = [];

  static Future<void> start(AppState app, GlobalKey<NavigatorState> nav) async {
    _app = app;
    _nav = nav;
    if (!isDesktop || _server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, kBrowserPairPort);
    } catch (e) {
      debugPrint('[browser-pair] không mở được 127.0.0.1:$kBrowserPairPort: $e');
      return;
    }
    _server!.listen((req) => _handle(req).catchError((Object e) {
          debugPrint('[browser-pair] $e');
          try {
            req.response.statusCode = 500;
            req.response.close();
          } catch (_) {}
        }));
  }

  static Future<void> stop() async {
    _app = null;
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  static bool _allowed(HttpRequest req) {
    final origin = req.headers.value('origin');
    if (origin != null) return kBridgeExtensionIds.any((id) => origin == 'chrome-extension://$id');
    return kBridgeExtensionIds.contains(req.headers.value('x-flygo-bridge'));
  }

  static Future<void> _send(HttpRequest req, int status, Object body) async {
    final o = req.headers.value('origin');
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('Cache-Control', 'no-store');
    if (o != null && status < 400) req.response.headers.set('Access-Control-Allow-Origin', o);
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  static Future<void> _handle(HttpRequest req) async {
    final app = _app;
    // Không trả lời preflight CORS: trang web không gọi được tới đây.
    if (req.method == 'OPTIONS' || !_allowed(req)) return _send(req, 404, {});
    if (app == null) return _send(req, 503, {'error': 'Flygo Chat chưa đăng nhập'});
    final me = app.me;
    if (req.uri.path == '/flygo/hello' && req.method == 'GET') {
      return _send(req, 200, {'app': 'flygo-chat', 'role': 'pairing', 'server': kServerUrl, 'user': me?.displayName ?? me?.username ?? '', 'servers': await _servers()});
    }
    if (req.uri.path == '/flygo/pair' && req.method == 'POST') {
      final now = DateTime.now();
      _hits.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
      if (_hits.length >= 6) return _send(req, 429, {'error': 'thử lại sau'});
      _hits.add(now);
      final body = await utf8.decodeStream(req).timeout(const Duration(seconds: 10));
      final j = body.isEmpty ? <String, dynamic>{} : (jsonDecode(body) as Map).cast<String, dynamic>();
      final client = (j['client'] as Map?)?.cast<String, dynamic>() ?? const {};
      final want = (j['server'] as String?)?.replaceAll(RegExp(r'/+$'), '');
      final Map<String, dynamic> r;
      var server = kServerUrl;
      if (want == null || want.isEmpty || want == kServerUrl.replaceAll(RegExp(r'/+$'), '')) {
        r = await MyBrowsers.pair(app.token, client: client, replace: j['replace'] as String?);
      } else {
        // Máy chủ khác đã đăng nhập trong app.
        final known = ServerList.items.any((e) => e.url.replaceAll(RegExp(r'/+$'), '') == want);
        final tok = known ? await TokenStore.readFor(want) : null;
        if (tok == null) return _send(req, 403, {'error': 'Flygo Chat chưa đăng nhập máy chủ này'});
        r = await MyBrowsers.pairOn(want, tok, client: client, replace: j['replace'] as String?);
        server = want;
      }
      final c = (r['client'] as Map?)?.cast<String, dynamic>() ?? const {};
      await _send(req, 200, {'server': server, 'ws_url': r['ws_url'], 'token': r['token'], 'client': c, 'user': me?.displayName ?? ''});
      _notice(tr('Đã kết nối trình duyệt "{0}" với tài khoản này. Agent của bạn dùng được trình duyệt đó (tag @{1}).', ['${c['name'] ?? ''}', '${c['slug'] ?? ''}']));
      return;
    }
    return _send(req, 404, {});
  }

  /// Máy chủ có phiên đã lưu trong app (máy chủ đang mở luôn có).
  static Future<List<Map<String, dynamic>>> _servers() async {
    final out = <Map<String, dynamic>>[];
    for (final e in ServerList.items) {
      final cur = e.url.replaceAll(RegExp(r'/+$'), '') == kServerUrl.replaceAll(RegExp(r'/+$'), '');
      if (cur || await TokenStore.readFor(e.url) != null) out.add({'url': e.url.replaceAll(RegExp(r'/+$'), ''), 'name': e.name, 'current': cur});
    }
    if (!out.any((x) => x['current'] == true)) out.insert(0, {'url': kServerUrl, 'name': '', 'current': true});
    return out;
  }

  static void _notice(String text) {
    final ctx = _nav?.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6)));
  }
}
