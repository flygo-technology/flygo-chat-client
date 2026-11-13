import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import '../i18n/i18n.dart';

/// Mini app (mục "Ứng dụng"): danh sách tải lúc chạy từ registry của máy chủ chat, không hardcode trong app.
/// Mỗi app là một trang web ở origin riêng, mở trong webview bằng URL mở app dùng một lần (launch token 60 giây).
/// Token máy chủ chat chỉ gửi tới registry, không bao giờ tới app.
class MiniApp {
  final String id, version, minClient, origin;
  /// Gốc API của app (base_url trong registry), vd https://show.example.com.
  final String baseUrl;
  /// Màn hình native Flygo có sẵn cho app (manifest "native": {"screen", "min_client"?}); null = webview.
  final String? _nativeScreen;
  final String _nativeMin;
  final Object? _name, _description;
  /// URL https của ảnh, hoặc một emoji.
  final String icon;
  final List<String> scanPrefixes;
  /// Manifest "open_in": "browser": luôn mở bằng trình duyệt hệ thống (vd trang đăng nhập Google, không chạy trong webview).
  final bool openInBrowser;
  /// Manifest "tile": {"icon": tên biểu tượng (table, tasks, network, code…), "color": "#RRGGBB"}: ô màu như các ô
  /// có sẵn của Flygo thay cho emoji. Không có thì vẽ emoji / ảnh như cũ.
  final Map<String, dynamic>? tile;
  /// Manifest "plain": web bên ngoài có đăng nhập riêng (không phải mini app Flygo): được điều hướng sang trang khác
  /// (trang đăng nhập…) ngay trong webview thay vì đẩy ra trình duyệt hệ thống.
  final bool plain;
  MiniApp._(this.id, this._name, this._description, this.icon, this.version, this.minClient, this.origin, this.scanPrefixes,
      this.baseUrl, this._nativeScreen, this._nativeMin, this.openInBrowser, this.tile, this.plain);

  factory MiniApp.fromJson(Map j) => MiniApp._(
        '${j['id']}',
        j['name'],
        j['description'],
        '${j['icon'] ?? ''}',
        '${j['version'] ?? ''}',
        '${j['min_client'] ?? ''}',
        '${j['origin'] ?? ''}',
        [for (final p in (j['scan_prefixes'] as List? ?? const [])) '$p'],
        '${j['base_url'] ?? j['origin'] ?? ''}'.replaceAll(RegExp(r'/+$'), ''),
        j['native'] is Map && '${j['native']['screen'] ?? ''}'.isNotEmpty ? '${j['native']['screen']}' : null,
        j['native'] is Map ? '${j['native']['min_client'] ?? ''}' : '',
        j['open_in'] == 'browser',
        j['tile'] is Map ? Map<String, dynamic>.from(j['tile'] as Map) : null,
        j['plain'] == true || '${j['id']}'.startsWith('vn.flygo.web.'),
      );



  Map<String, dynamic> toJson() => {
        'id': id,
        'name': _name,
        'description': _description,
        'icon': icon,
        'version': version,
        'min_client': minClient,
        'origin': origin,
        'scan_prefixes': scanPrefixes,
        'base_url': baseUrl,
        'native': _nativeScreen == null ? null : {'screen': _nativeScreen, 'min_client': _nativeMin},
        'open_in': openInBrowser ? 'browser' : null,
        'tile': tile,
        'plain': plain,
      };

  /// Chuỗi hoặc map theo ngôn ngữ ({vi, en}).
  static String _text(Object? v) {
    if (v is Map) return '${v[appLanguage.value] ?? v['vi'] ?? v['en'] ?? (v.values.isEmpty ? '' : v.values.first)}';
    return v == null ? '' : '$v';
  }

  String get name => _text(_name).isEmpty ? id : _text(_name);
  String get description => _text(_description);
  bool get iconIsUrl => icon.startsWith('https://');

  /// Phiên bản Flygo đang chạy thấp hơn min_client: hiện mờ, kèm "Cần cập nhật Flygo".
  /// Màn hình native dùng cho app này ("show"…), nếu bản Flygo này đủ mới; null = mở webview.
  String? get nativeScreen =>
      _nativeScreen == null || (_nativeMin.isNotEmpty && _clientVersion != null && compareAppVersion(_clientVersion!, _nativeMin) < 0) ? null : _nativeScreen;

  bool get needsUpdate => minClient.isNotEmpty && _clientVersion != null && compareAppVersion(_clientVersion!, minClient) < 0;

  /// Trang cùng origin với app (chỉ điều hướng trong origin, cầu nối JS chỉ bật cho origin này).
  bool owns(Uri u) {
    final o = Uri.tryParse(origin);
    return o != null && u.scheme == o.scheme && u.host == o.host && u.port == o.port;
  }

  /// Đường dẫn (kèm query / fragment) mở app khi quét [raw], nếu khớp một scan_prefixes; không khớp: null.
  String? scanPath(String raw) {
    if (!scanPrefixes.any((p) => p.isNotEmpty && raw.startsWith(p))) return null;
    final u = Uri.tryParse(raw);
    if (u == null || !owns(u)) return null;
    final path = u.path.isEmpty ? '/' : u.path;
    return '$path${u.hasQuery ? '?${u.query}' : ''}${u.hasFragment ? '#${u.fragment}' : ''}';
  }
}

String? _clientVersion;

/// "1.0.0+232" so với "1.0.0" / "1.0.0+230": so từng số, phần build (sau +) chỉ so khi cả hai có.
/// So sánh phiên bản app ("1.0.4+417") với mốc trong manifest. Mốc là số trơn ("416") thì hiểu là số build và so với
/// phần "+N" của phiên bản (trước đây "416" bị đọc thành 416.0.0, nên bản nào cũng bị coi là cũ hơn). Không so được thì 0.
@visibleForTesting
int compareAppVersion(String a, String b) {
  final bare = RegExp(r'^\d+$');
  int? build(String s) => bare.hasMatch(s) ? int.parse(s) : (s.contains('+') ? int.tryParse(s.split('+').last) : null);
  if (bare.hasMatch(a) || bare.hasMatch(b)) {
    final x = build(a), y = build(b);
    return x == null || y == null ? 0 : x - y;
  }
  List<int> parts(String s) => [for (final x in s.split('+').first.split('.')) int.tryParse(x) ?? 0];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (d != 0) return d;
  }
  if (a.contains('+') && b.contains('+')) return (int.tryParse(a.split('+').last) ?? 0) - (int.tryParse(b.split('+').last) ?? 0);
  return 0;
}

class MiniAppException implements Exception {
  final int status;
  final String message;
  MiniAppException(this.status, this.message);
  @override
  String toString() => message;
}

/// Registry, danh sách app và mở app của máy chủ chat đang dùng.
class MiniApps {
  /// Đặt khi build (`--dart-define=FLYGO_APPS_REGISTRY=…`) để chạy thử với registry local; khi đó dùng cho mọi máy chủ.
  static const _override = String.fromEnvironment('FLYGO_APPS_REGISTRY');
  static final _registry = <String, String>{}; // máy chủ chat -> registry ('' = không có)
  static final _apps = <String, (DateTime, List<MiniApp>)>{};
  static const _ttl = Duration(minutes: 10);

  // Danh sách lần trước của từng máy chủ lưu trên máy: mạng chậm / lỗi (đường quốc tế) vẫn hiện mục Ứng dụng.
  static Future<File> _diskFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}mini-apps.json');
  }

  static bool _restored = false;

  /// Nạp danh sách đã lưu (một lần); không ghi đè danh sách mới hơn đã tải trong phiên này.
  static Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final f = await _diskFile();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map;
      j.forEach((server, v) {
        if (v is! Map) return;
        _registry.putIfAbsent('$server', () => '${v['registry'] ?? ''}');
        if (!_apps.containsKey(server)) {
          final apps = [for (final a in (v['apps'] as List? ?? const [])) if (a is Map) MiniApp.fromJson(a)];
          _apps['$server'] = (DateTime.fromMillisecondsSinceEpoch(0), apps);
        }
      });
    } catch (_) {}
  }

  static Future<void> _save() async {
    try {
      final out = {
        for (final e in _apps.entries)
          e.key: {'registry': _registry[e.key] ?? '', 'apps': [for (final a in e.value.$2) a.toJson()]},
      };
      await (await _diskFile()).writeAsString(jsonEncode(out));
    } catch (_) {}
  }

  static Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'X-MM-Server': kServerUrl,
        'Content-Type': 'application/json',
        'User-Agent': kUserAgent,
      };

  /// Registry của máy chủ đang dùng: `https://<máy chủ chat>/.well-known/flygo-apps.json` → {"registry": "https://…"}.
  /// Không tìm thấy: null (ẩn mục Ứng dụng). Lỗi mạng thì lần sau dò lại.
  static Future<String?> registry() async {
    if (_override.isNotEmpty) return _override;
    final server = kServerUrl;
    final known = _registry[server];
    if (known != null) return known.isEmpty ? null : known;
    try {
      final r = await http
          .get(Uri.parse('$server/.well-known/flygo-apps.json'), headers: {'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 15));
      var reg = '';
      // Lỗi tạm (không phải 200 / 404): không nhớ, lần sau hỏi lại (trước đây nhớ "không có registry" tới khi mở lại app).
      if (r.statusCode != 200 && r.statusCode != 404) return null;
      if (r.statusCode == 200) {
        final u = Uri.tryParse('${(jsonDecode(r.body) as Map)['registry'] ?? ''}');
        if (u != null && u.scheme == 'https' && u.host.isNotEmpty) reg = u.toString().replaceAll(RegExp(r'/+$'), '');
      }
      _registry[server] = reg;
      return reg.isEmpty ? null : reg;
    } on FormatException {
      _registry[server] = '';
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Danh sách app đã lọc theo quyền (thứ tự của registry). Có sẵn trong 10 phút thì dùng lại, trừ khi [refresh].
  /// Không có registry: rỗng.
  static Future<List<MiniApp>> list(String token, {bool refresh = false}) async {
    _clientVersion ??= await _version();
    await restore();
    final server = kServerUrl;
    final cached = _apps[server];
    if (!refresh && cached != null && DateTime.now().difference(cached.$1) < _ttl) return cached.$2;
    final reg = await registry();
    if (reg == null) return const [];
    try {
      final r = await http.get(Uri.parse('$reg/v1/apps'), headers: _headers(token)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw MiniAppException(r.statusCode, 'apps ${r.statusCode}');
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final apps = [
        for (final a in (j['apps'] as List? ?? const []))
          if (a is Map && '${a['id'] ?? ''}'.isNotEmpty && Uri.tryParse('${a['origin'] ?? ''}')?.host.isNotEmpty == true) MiniApp.fromJson(a),
      ];
      _apps[server] = (DateTime.now(), apps);
      _save();
      return apps;
    } catch (_) {
      if (cached != null) return cached.$2;
      rethrow;
    }
  }

  /// Danh sách đã tải gần nhất của máy chủ đang dùng (không gọi mạng).
  static List<MiniApp> get cached => _apps[kServerUrl]?.$2 ?? const [];

  /// Tăng mỗi khi danh sách app của máy chủ đang dùng đổi (vd vừa được cấp / thu hồi quyền): các mục Ứng dụng vẽ lại.
  static final changed = ValueNotifier<int>(0);

  static String _sig(List<MiniApp> a) => [for (final x in a) '${x.id}:${x.name}:${x.needsUpdate}'].join('|');

  /// Tải lại ngay (bỏ qua hạn 10 phút) và báo [changed] nếu khác. Lỗi mạng: im lặng.
  static Future<void> poll(String token) async {
    final before = _sig(cached);
    try {
      final now = await list(token, refresh: true);
      if (_sig(now) != before) changed.value++;
    } catch (_) {}
  }

  /// App có scan_prefixes khớp nội dung QR [raw], kèm đường dẫn để mở; không khớp: null.
  static Future<(MiniApp, String)?> forScan(String token, String raw) async {
    if (!raw.startsWith('https://') && !raw.startsWith('http://')) return null;
    List<MiniApp> apps;
    try {
      apps = await list(token);
    } catch (_) {
      apps = cached;
    }
    for (final a in apps) {
      final p = a.scanPath(raw);
      if (p != null) return (a, p);
    }
    return null;
  }

  /// URL mở app (dùng một lần, sống 60 giây): gọi ngay trước khi mở webview, không lưu lại.
  /// 401: phiên máy chủ chat hỏng; 404: app bị gỡ hoặc mất quyền (danh sách được tải lại lần sau).
  static Future<Uri> launch(String token, MiniApp app, {String? path}) async {
    final u = Uri.tryParse('${(await _launch(token, app, path: path))['url'] ?? ''}');
    // URL mở app phải thuộc origin của app (registry không đưa webview đi chỗ khác), trừ bước SSO của chính registry
    // (`<registry>/v1/sso/start?next=<trang của app>`: đặt cookie đăng nhập Flygo ID rồi chuyển sang app).
    if (u == null || !(app.owns(u) || await _ssoStart(u, app))) throw MiniAppException(502, tr('Không mở được ứng dụng ({0}).', ['url']));
    return u;
  }

  static Future<bool> _ssoStart(Uri u, MiniApp app) async {
    final reg = Uri.tryParse(await registry() ?? '');
    final next = Uri.tryParse(u.queryParameters['next'] ?? '');
    return reg != null &&
        next != null &&
        u.scheme == 'https' &&
        u.origin == reg.origin &&
        u.path == '${reg.path.replaceAll(RegExp(r'/+$'), '')}/v1/sso/start' &&
        app.owns(next);
  }

  /// Launch token (60 giây, dùng một lần) cho màn hình native: đổi ngay lấy phiên ở `<base_url>/api/session`.
  static Future<String> launchToken(String token, MiniApp app) async {
    final t = '${(await _launch(token, app))['token'] ?? ''}';
    if (t.isEmpty) throw MiniAppException(502, tr('Không mở được ứng dụng ({0}).', ['token']));
    return t;
  }

  static Future<Map> _launch(String token, MiniApp app, {String? path}) async {
    final reg = await registry();
    if (reg == null) throw MiniAppException(404, tr('Máy chủ này chưa có ứng dụng.'));
    final r = await http
        .post(Uri.parse('$reg/v1/apps/${Uri.encodeComponent(app.id)}/launch'),
            headers: _headers(token), body: jsonEncode({if (path != null && path.startsWith('/')) 'path': path}))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode == 401) throw MiniAppException(401, tr('Phiên đăng nhập đã hết hạn, hãy đăng nhập lại.'));
    if (r.statusCode == 404) {
      _apps.remove(kServerUrl);
      throw MiniAppException(404, tr('Ứng dụng không còn hoặc bạn không còn quyền dùng.'));
    }
    if (r.statusCode != 200) throw MiniAppException(r.statusCode, tr('Không mở được ứng dụng ({0}).', ['${r.statusCode}']));
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  }

  static Future<String?> _version() async {
    try {
      final i = await PackageInfo.fromPlatform();
      return i.buildNumber.isEmpty ? i.version : '${i.version}+${i.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  /// Webview trong app: Android, iOS, macOS. Windows / Linux: mở URL mở app bằng trình duyệt hệ thống.
  static bool get inAppWebView => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}
