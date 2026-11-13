// Flygo ID (registry mini app đã phát triển thêm, cùng địa chỉ): danh sách space của người dùng, vé cho từng app và
// space, kho tài khoản dùng chung (che mật khẩu). Chỉ native gọi, bằng phiên chat; vé và mật khẩu không bao giờ
// vào JS. Đặc tả: /home/admin/handoff/miniapp-sso-design.md v2, flygo-chat-server flygo-id/.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/mini_apps.dart';
import '../config.dart';
import 'model.dart';

class FlygoIdException implements Exception {
  FlygoIdException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Một space người dùng được dùng, kèm extension được bật và quyền quản lý kho.
class BrowserSpace {
  BrowserSpace(this.space, {required this.extensionEnv, required this.canManageVault, this.subtitle, this.home});
  final Space space;

  /// env theo từng extension (app id → env) trong space này.
  final Map<String, Map<String, String>> extensionEnv;
  final bool canManageVault;
  final String? subtitle;
  final String? home;

  /// JSON của Flygo ID: {id, name, subtitle?, icon?, color "#RRGGBB"?, home?, whitelist {id: {pattern}},
  /// extensions {app: {env}}, provider?, vault {can_manage}}.
  static BrowserSpace fromJson(Map j) {
    final ext = <String, Map<String, String>>{
      if (j['extensions'] is Map)
        for (final e in (j['extensions'] as Map).entries)
          '${e.key}': {
            if (e.value is Map && (e.value as Map)['env'] is Map)
              for (final v in ((e.value as Map)['env'] as Map).entries) '${v.key}': '${v.value}',
          },
    };
    final home = j['home'] as String?;
    final space = Space.fromJson({
      'id': j['id'],
      'name': j['name'],
      'color': j['color'],
      'whitelist': j['whitelist'],
      // env chung của space: gộp env của các extension (Ký số chỉ có một).
      'env': {for (final e in ext.values) ...e},
      'extensions': {for (final k in ext.keys) k: {}},
      'bookmarks': {if (home != null) 'home': {'title': '${j['name']}', 'url': home}},
      'provider': j['provider'],
    });
    return BrowserSpace(
      space,
      extensionEnv: ext,
      canManageVault: (j['vault'] as Map?)?['can_manage'] == true,
      subtitle: j['subtitle'] as String?,
      home: home,
    );
  }
}

/// Một tài khoản để tự điền (mật khẩu chỉ nằm trong bộ nhớ native, điền xong là bỏ).
class VaultFill {
  VaultFill(this.id, this.username, this.password);
  final String id;
  final String username;
  final String password;
}

class FlygoId {
  FlygoId({required this.base, required this.chatToken, http.Client? client}) : _http = client ?? http.Client();

  /// Địa chỉ Flygo ID (= registry của máy chủ chat).
  final String base;
  final String chatToken;
  final http.Client _http;

  /// Flygo ID của máy chủ chat đang dùng; null nếu máy chủ không có. Có Flygo ID khi registry của máy chủ trả
  /// `/.well-known/flygo-id.json` {issuer}; registry cũ (chưa nâng cấp) không có tệp này thì giữ cách cũ.
  static Future<FlygoId?> current(String chatToken) async {
    const override = String.fromEnvironment('FLYGO_ID');
    if (override.isNotEmpty) return FlygoId(base: override.replaceAll(RegExp(r'/+$'), ''), chatToken: chatToken);
    final registry = await MiniApps.registry();
    if (registry == null || registry.isEmpty) return null;
    final issuer = _issuers[registry] ??= await _discover(registry);
    return issuer.isEmpty ? null : FlygoId(base: issuer, chatToken: chatToken);
  }

  /// registry → issuer ('' = không có Flygo ID). Lỗi mạng thì không nhớ, lần sau hỏi lại.
  static final _issuers = <String, String>{};

  static Future<String> _discover(String registry) async {
    try {
      final r = await http
          .get(Uri.parse('${registry.replaceAll(RegExp(r'/+$'), '')}/.well-known/flygo-id.json'), headers: {'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 10));
      // Chỉ nhớ "không có Flygo ID" khi máy chủ trả 404; lỗi tạm (5xx, chặn, chuyển hướng) thì lần sau hỏi lại.
      if (r.statusCode == 404) return '';
      if (r.statusCode != 200) throw StateError('Flygo ID trả ${r.statusCode}');
      final issuer = Uri.tryParse('${(jsonDecode(r.body) as Map)['issuer'] ?? ''}');
      if (issuer == null || !(issuer.isScheme('https') || issuer.host == 'localhost')) return '';
      return issuer.toString().replaceAll(RegExp(r'/+$'), '');
    } catch (_) {
      throw StateError('không hỏi được Flygo ID');
    }
  }

  static const _secure = FlutterSecureStorage();
  static String? _did;

  /// Mã thiết bị của app Browser (X-Flygo-Device): ngẫu nhiên, thu hồi theo mã này. Điện thoại giữ trong secure
  /// storage; máy tính giữ trong tệp của app (như phiên đăng nhập): keychain macOS cần entitlement app không có, đọc
  /// lỗi thì trước đây Flygo ID im lặng thất bại và ô Ký số không hiện.
    static Future<String> deviceId() async => _did ?? (_didLoading ??= _loadDeviceId().whenComplete(() => _didLoading = null));
  static Future<String>? _didLoading;

  /// Điện thoại: secure storage, kèm một bản sao trong tệp của app. Android có lúc treo Keystore (vd ngay sau khi cài
  /// đè bản mới): đọc quá 4 giây thì dùng bản sao, để mọi lời gọi Flygo ID (vé Bảng tin…) không chờ mãi (S24, bản 421).
  static Future<String> _loadDeviceId() async {
    final mobile = Platform.isAndroid || Platform.isIOS;
    String? v;
    File? f;
    try {
      f = File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}browser_did');
    } catch (_) {}
    var secureOk = true;
    if (mobile) {
      try {
        v = await _secure.read(key: 'browser.did').timeout(const Duration(seconds: 4));
      } catch (_) {
        secureOk = false;
      }
    }
    try {
      if ((v == null || v.isEmpty) && f != null && await f.exists()) v = (await f.readAsString()).trim();
    } catch (_) {}
    final fresh = v == null || v.isEmpty;
    if (fresh) {
      final r = Random.secure();
      v = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    }
    try {
      // Không ghi đè secure storage khi vừa đọc lỗi (có thể vẫn còn mã cũ ở đó).
      if (mobile && fresh && secureOk) await _secure.write(key: 'browser.did', value: v).timeout(const Duration(seconds: 4));
      if (f != null && (fresh || mobile)) await f.writeAsString(v);
    } catch (_) {}
    return _did = v;
  }

  Future<Map<String, String>> _headers() async => {
        'Authorization': 'Bearer $chatToken',
        'X-MM-Server': kServerUrl,
        'X-Flygo-Device': await deviceId(),
        'Content-Type': 'application/json',
        'User-Agent': kUserAgent,
      };

  Future<Map<String, dynamic>> _call(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$base$path'))..headers.addAll(await _headers());
    if (body != null) req.body = jsonEncode(body);
        // Hết giờ cho cả lúc chờ phản hồi lẫn lúc đọc nội dung (trước chỉ chờ phản hồi).
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    Map<String, dynamic> j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw FlygoIdException(res.statusCode, '${j['error'] ?? 'Flygo ID trả lỗi ${res.statusCode}'}');
    return j;
  }

  /// Gọi API Flygo ID bằng phiên chat của mình (trang Thiết bị, xác thực…).
  Future<Map<String, dynamic>> request(String method, String path, [Object? body]) => _call(method, path, body);

  /// Các space người này được dùng (chỉ extension được phép trong từng space).
  Future<List<BrowserSpace>> spaces() async {
    final j = await _call('GET', '/v1/browser/spaces');
    return [
      if (j['spaces'] is Map)
        for (final e in (j['spaces'] as Map).entries)
          if (e.value is Map) BrowserSpace.fromJson({'id': e.key, ...(e.value as Map)}),
    ];
  }

  final _tickets = <String, (String, DateTime)>{};

  /// Vé cho [audience] trong space [browser] (JWT, chỉ native giữ). Dùng lại tới khi còn dưới 120 giây.
  Future<String> ticket(String audience, {String? browser, bool refresh = false}) async {
    final key = '$audience|${browser ?? ''}';
    final hit = _tickets[key];
    if (!refresh && hit != null && hit.$2.difference(DateTime.now()) > const Duration(seconds: 120)) return hit.$1;
    final j = await _call('POST', '/v1/token', {'audience': audience, 'browser': ?browser});
    final token = '${j['token']}';
    _tickets[key] = (token, DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 600)));
    return token;
  }

  // ---------------------------------------------------------------- Thiết bị / xác thực từ xa
  // Đặc tả: flygo-chat-server flygo-id/docs/devices-verify.md. Mã thiết bị = [deviceId] (X-Flygo-Device).

  /// Báo máy này với Flygo ID (mở app và mỗi 6 giờ). Tên chỉ dùng lần đầu; đổi tên qua [renameDevice].
  Future<void> registerDevice({required String name, required String platform, String os = '', String appVersion = '', bool push = true}) async =>
      _call('POST', '/v1/me/devices/register', {
        'device_id': await deviceId(),
        'name': name,
        'platform': platform,
        'os': os,
        'app_version': appVersion,
        'push': push,
      });

  /// Đăng ký khoá công khai của máy này (một khoá mỗi máy; khoá mới thay khoá cũ).
  Future<void> enrollDeviceKey({required String pub, required bool hwBacked, required bool biometricBound}) async =>
      _call('POST', '/v1/me/devices/${Uri.encodeComponent(await deviceId())}/key', {
        'alg': 'ES256',
        'pub': pub,
        'hw_backed': hwBacked,
        'biometric_bound': biometricBound,
      });

  Future<void> removeDeviceKey([String? id]) async =>
      _call('DELETE', '/v1/me/devices/${Uri.encodeComponent(id ?? await deviceId())}/key');

  Future<List<Map<String, dynamic>>> devices() async {
    final j = await _call('GET', '/v1/me/devices');
    return [for (final d in (j['devices'] as List? ?? const [])) if (d is Map) Map<String, dynamic>.from(d)];
  }

  Future<void> renameDevice(String id, String name) => _call('PATCH', '/v1/me/devices/${Uri.encodeComponent(id)}', {'name': name});

  /// Thu hồi một thiết bị (không cần xác thực; app hỏi lại 10 giây).
  Future<void> revokeDevice(String id) => _call('POST', '/v1/me/devices/${Uri.encodeComponent(id)}/revoke', {});

  /// Một yêu cầu xác thực: {id, title, details_json (chuỗi), codes [3], requester {app, label, device_name},
  /// expires_at, status}.
  Future<Map<String, dynamic>> verifyRequest(String id) => _call('GET', '/v1/me/verify/${Uri.encodeComponent(id)}');

  /// Yêu cầu đang chờ (bù cho thông báo bị lỡ).
  Future<List<Map<String, dynamic>>> pendingVerifies() async {
    final j = await _call('GET', '/v1/me/verify?status=pending');
    final list = j['requests'] ?? j['items'] ?? j['verify'];
    return [for (final r in (list as List? ?? const [])) if (r is Map) Map<String, dynamic>.from(r)];
  }

  /// Trả lời yêu cầu: đồng ý (kèm mã đã chọn và chữ ký) hoặc từ chối.
  Future<Map<String, dynamic>> respondVerify(String id, {required bool approve, String? code, String? sig}) async =>
      _call('POST', '/v1/me/verify/${Uri.encodeComponent(id)}/respond', {
        'device_id': await deviceId(),
        'approve': approve,
        'code': ?code,
        'sig': ?sig,
      });

  /// Các app người này được quản trị (manifest.admin): {app, name, url (tuyệt đối) hoặc native, spaces}.
  Future<List<Map<String, dynamic>>> myAdmin() async {
    final j = await _call('GET', '/v1/me/admin');
    return [for (final a in (j['apps'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
  }

  /// Tài khoản để điền trên [origin] trong [space]. Flygo ID chỉ trả cho trang trong whitelist và ghi nhật ký.
  Future<List<VaultFill>> vaultFill(String space, String origin) async {
    final j = await _call('POST', '/v1/vault/fill', {'space': space, 'origin': origin});
    return [
      for (final e in (j['entries'] as List? ?? const []))
        if (e is Map) VaultFill('${e['id']}', '${e['username']}', '${e['password']}'),
    ];
  }

  /// Quản lý kho (người có quyền vault.manage): danh sách không bao giờ chứa mật khẩu.
  Future<List<Map<String, dynamic>>> vaultEntries(String space) async {
    final j = await _call('GET', '/v1/vault/${Uri.encodeComponent(space)}/entries');
    return [for (final e in (j['entries'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
  }

  Future<void> vaultPut(String space, {String? id, required String origin, required String username, required String password, String? note}) =>
      _call(id == null ? 'POST' : 'PUT', '/v1/vault/${Uri.encodeComponent(space)}/entries${id == null ? '' : '/$id'}', {
        'origin': origin,
        'username': username,
        'password': password,
        'note': ?note,
      });

  Future<void> vaultDelete(String space, String id) => _call('DELETE', '/v1/vault/${Uri.encodeComponent(space)}/entries/$id');
}
