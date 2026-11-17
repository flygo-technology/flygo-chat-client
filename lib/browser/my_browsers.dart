// "Trình duyệt của tôi": các trình duyệt (extension Flygo Browser Bridge) nối với tài khoản qua WebSocket bridge của
// Flygo Gateway (app vn.flygo.clients ở <máy chủ chat>/__apps/gateway). Dùng cho tag @trình-duyệt khi chat với agent và
// màn Cài đặt › Trình duyệt của tôi.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'flygo_id.dart';

const kBrowserApp = 'vn.flygo.clients';

class MyBrowser {
  MyBrowser(this.raw);
  final Map<String, dynamic> raw;
  String get id => '${raw['id']}';
  String get name => '${raw['name'] ?? ''}';
  String get slug => '${raw['slug'] ?? ''}';
  String get engine => '${raw['engine'] ?? ''}';
  String get os => '${raw['os'] ?? ''}';
  String get machineName => '${raw['machine_name'] ?? ''}';
  bool get online => raw['online'] == true;
  bool get isDefault => raw['default'] == true;
  String? get via => raw['via'] as String?;
  Map<String, dynamic>? get inUseBy => raw['in_use_by'] as Map<String, dynamic>?;
  int get lastSeen => (raw['last_seen'] as num?)?.toInt() ?? 0;

  /// props.flygo_browser của tin gửi cho agent.
  Map<String, dynamic> get tag => {'id': id, 'slug': slug, 'name': name};
}

class MyBrowsers {
  MyBrowsers._();
  static List<MyBrowser> _cache = [];
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static Map<String, dynamic> prefs = {};

  static String get base => '${kServerUrl.replaceAll(RegExp(r'/+$'), '')}/__apps/gateway';
  static List<MyBrowser> get cached => _cache;

  static Future<Map<String, String>> _headers(String chatToken, {bool json = false}) async {
    final id = await FlygoId.current(chatToken);
    if (id == null) throw StateError('Máy chủ này chưa có Flygo ID');
    return {
      'Authorization': 'Bearer ${await id.ticket(kBrowserApp).timeout(const Duration(seconds: 20))}',
      'User-Agent': kUserAgent,
      if (json) 'Content-Type': 'application/json',
    };
  }

  static dynamic _decode(http.Response r) {
    final j = r.body.isEmpty ? {} : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) throw HttpException('${j is Map ? j['error'] ?? r.statusCode : r.statusCode}');
    return j;
  }

  /// Danh sách (nhớ 30 giây; [refresh] để tải lại). Lỗi (máy chủ chưa có app) thì trả danh sách rỗng.
  static Future<List<MyBrowser>> list(String chatToken, {bool refresh = false}) async {
    if (!refresh && DateTime.now().difference(_at) < const Duration(seconds: 30)) return _cache;
    try {
      final r = await http.get(Uri.parse('$base/api/browsers'), headers: await _headers(chatToken)).timeout(const Duration(seconds: 15));
      final j = _decode(r) as Map;
      _cache = [for (final b in (j['browsers'] as List? ?? const [])) MyBrowser(Map<String, dynamic>.from(b as Map))];
      prefs = Map<String, dynamic>.from(j['prefs'] as Map? ?? const {});
      _at = DateTime.now();
    } catch (_) {
      if (refresh) rethrow;
    }
    return _cache;
  }

  /// Như [pair] nhưng cho một máy chủ bất kỳ đã đăng nhập trong app (không phải máy chủ đang mở): xin vé Flygo ID của máy
  /// chủ đó bằng phiên đã lưu, rồi ghép ở `<máy chủ>/__apps/gateway`.
  static Future<Map<String, dynamic>> pairOn(String server, String chatToken, {required Map<String, dynamic> client, String? replace}) async {
    final root = server.replaceAll(RegExp(r'/+$'), '');
    final t = await http.post(Uri.parse('$root/flygo-id/v1/token'),
        headers: {'Authorization': 'Bearer $chatToken', 'X-MM-Server': root, 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
        body: jsonEncode({'audience': kBrowserApp})).timeout(const Duration(seconds: 15));
    final ticket = '${(_decode(t) as Map)['token'] ?? ''}';
    if (ticket.isEmpty) throw const HttpException('Flygo ID không cấp vé');
    final r = await http.post(Uri.parse('$root/__apps/gateway/api/pair'),
        headers: {'Authorization': 'Bearer $ticket', 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
        body: jsonEncode({
          'client': {'type': 'extension', 'kind': 'browser', for (final k in ['name', 'engine', 'os', 'profile']) if (client[k] is String) k: client[k]},
          if (replace != null && RegExp(r'^[A-Za-z0-9_-]{12}$').hasMatch(replace)) 'replace': replace,
          'machine_name': Platform.localHostname.replaceAll(RegExp(r'\.(local|lan|home)$'), ''),
        })).timeout(const Duration(seconds: 15));
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  /// Cấp token client cho một trình duyệt trên máy này (ghép cặp tự động, xem browser_pairing.dart). Trả {client, token, ws_url}.
  static Future<Map<String, dynamic>> pair(String chatToken, {required Map<String, dynamic> client, String? replace}) async {
    final r = await http.post(Uri.parse('$base/api/pair'), headers: await _headers(chatToken, json: true), body: jsonEncode({
      'client': {
        'type': 'extension', 'kind': 'browser',
        for (final k in ['name', 'engine', 'os', 'profile']) if (client[k] is String) k: client[k],
      },
      if (replace != null && RegExp(r'^[A-Za-z0-9_-]{12}$').hasMatch(replace)) 'replace': replace,
      'machine_name': Platform.localHostname.replaceAll(RegExp(r'\.(local|lan|home)$'), ''),
    })).timeout(const Duration(seconds: 15));
    _at = DateTime.fromMillisecondsSinceEpoch(0);
    return Map<String, dynamic>.from(_decode(r) as Map);
  }

  static Future<void> rename(String chatToken, String id, String name) async {
    _decode(await http.patch(Uri.parse('$base/api/browsers/$id'), headers: await _headers(chatToken, json: true), body: jsonEncode({'name': name})));
    _at = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Future<void> remove(String chatToken, String id) async {
    _decode(await http.delete(Uri.parse('$base/api/browsers/$id'), headers: await _headers(chatToken)));
    _at = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Dừng agent đang điều khiển trình duyệt này.
  static Future<void> stop(String chatToken, String id) async =>
      _decode(await http.post(Uri.parse('$base/api/browsers/$id?action=stop'), headers: await _headers(chatToken)));

  static Future<void> setPrefs(String chatToken, {String? defaultBrowser, bool clearDefault = false, bool? aiEnabled}) async {
    final j = _decode(await http.put(Uri.parse('$base/api/prefs'), headers: await _headers(chatToken, json: true), body: jsonEncode({
      if (defaultBrowser != null || clearDefault) 'default_browser': clearDefault ? null : defaultBrowser,
      'ai_enabled': ?aiEnabled,
    }))) as Map;
    prefs = Map<String, dynamic>.from(j['prefs'] as Map? ?? const {});
    _at = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Future<List<Map<String, dynamic>>> mcpTokens(String chatToken) async {
    final j = _decode(await http.get(Uri.parse('$base/api/mcp-tokens'), headers: await _headers(chatToken))) as Map;
    return [for (final t in (j['tokens'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
  }

  /// Tạo MCP token cho agent ngoài (Claude Code, Codex…). Trả {token, mcp_url, expires_at}: token chỉ hiện một lần.
  static Future<Map<String, dynamic>> createMcpToken(String chatToken, String name, {int days = 30}) async =>
      Map<String, dynamic>.from(_decode(await http.post(Uri.parse('$base/api/mcp-tokens'),
          headers: await _headers(chatToken, json: true), body: jsonEncode({'name': name, 'ttl_sec': days * 86400}))) as Map);

  static Future<void> revokeMcpToken(String chatToken, String id) async =>
      _decode(await http.delete(Uri.parse('$base/api/mcp-tokens/$id'), headers: await _headers(chatToken)));
}
