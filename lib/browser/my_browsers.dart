// "Trình duyệt của tôi": các trình duyệt (extension Flygo Browser Bridge) đã nối với tài khoản, qua phần server của app
// "Trình duyệt" (vn.flygo.browser) ở <máy chủ chat>/__apps/browser. Dùng cho tag @trình-duyệt khi chat với agent và màn
// Cài đặt › Trình duyệt của tôi.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'flygo_id.dart';

const kBrowserApp = 'vn.flygo.browser';

class MyBrowser {
  MyBrowser(this.raw);
  final Map<String, dynamic> raw;
  String get id => '${raw['id']}';
  String get name => '${raw['name'] ?? ''}';
  String get slug => '${raw['slug'] ?? ''}';
  String get engine => '${raw['engine'] ?? ''}';
  String get os => '${raw['os'] ?? ''}';
  String get machineName => '${raw['machine_name'] ?? ''}';
  String? get machine => raw['machine'] as String?;
  bool get online => raw['online'] == true;
  bool get isDefault => raw['default'] == true;
  String? get via => raw['via'] as String?;
  Map<String, dynamic>? get inUseBy => raw['in_use_by'] as Map<String, dynamic>?;
  int get lastSeen => (raw['last_seen'] as num?)?.toInt() ?? 0;
  bool get sameMachine => machine != null && machine == MyBrowsers.machineIdSync;

  /// props.flygo_browser của tin gửi cho agent.
  Map<String, dynamic> get tag => {'id': id, 'slug': slug, 'name': name};
}

class MyBrowsers {
  MyBrowsers._();
  static List<MyBrowser> _cache = [];
  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static Map<String, dynamic> prefs = {};

  static String get base => '${kServerUrl.replaceAll(RegExp(r'/+$'), '')}/__apps/browser';
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

  // ---------------------------------------------------------------- mã máy (cùng công thức với runner flygo-agent)
  static String? machineIdSync;

  /// sha256("flygo-machine/v1:" + mã máy của hệ điều hành, viết thường), 32 ký tự hex. Chỉ máy tính; điện thoại trả null.
  static Future<String?> machineId() async {
    if (machineIdSync != null) return machineIdSync;
    String? raw;
    try {
      if (Platform.isLinux) {
        raw = (await File('/etc/machine-id').readAsString()).trim();
      } else if (Platform.isMacOS) {
        final r = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
        raw = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch('${r.stdout}')?.group(1);
      } else if (Platform.isWindows) {
        final r = await Process.run('reg', ['query', r'HKLM\SOFTWARE\Microsoft\Cryptography', '/v', 'MachineGuid']);
        raw = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)').firstMatch('${r.stdout}')?.group(1);
      }
    } catch (_) {}
    if (raw == null || raw.isEmpty) return null;
    return machineIdSync = sha256.convert(utf8.encode('flygo-machine/v1:${raw.trim().toLowerCase()}')).toString().substring(0, 32);
  }
}
