// Chạy một extension của mình (vd Ký số = sign-relay của Magic Sign) trong app Browser, như app Magic Sign mobile
// và trình duyệt Electron đang làm. Đặc tả: /home/admin/handoff/flygo-fetch-spec.md v0.2.
//
// - Background chạy nguyên văn trong một WebView ẩn (trang background của manifest, vd engine.html), lớp chrome.*
//   (shim.js) đứng thay API của Chrome. fetch khác origin đi qua native và bị kiểm theo api_origins / host_origins
//   (bridge_policy.dart); WebSocket chỉ được mở tới các origin đó.
// - Website nhận content script lúc document_start. Tin của website tới app qua web message listener
//   "MagicSignNative" (Android / iOS / macOS), origin lấy từ WebView, không tin trang. Windows (WebView2) chưa có web
//   message listener: lớp _winNative dựng lại MagicSignNative trên JS handler, origin lấy từ URL khung chính.
// - Hộp xác nhận (prompt.js) là trang của extension vẽ đè lên website, website không chạm được; sau đó hỏi sinh trắc.
//
// Mỗi (extension, máy chủ) một runtime: một engine, một storage (phiên đăng nhập trong secure storage, phần còn lại
// trong tệp). Các space (mỗi token một space) của cùng máy chủ dùng chung runtime, khác nhau ở profile WebView và
// token bị khoá trong hộp ký.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart' show kServerUrl;
import 'bridge_policy.dart';
import 'model.dart';

/// Máy chủ ký số đặt lúc build (--dart-define=KYSO_SERVER=...), rỗng = suy ra từ máy chủ chat.
const _kKysoServerOverride = String.fromEnvironment('KYSO_SERVER');

/// Máy chủ ký số của máy chủ chat [chat]: thay nhãn đầu "chat." bằng "kyso." (chat.congty.vn -> kyso.congty.vn).
/// Máy chủ chat không theo quy ước đó: rỗng.
String kysoServerFor(String chat) {
  final u = Uri.tryParse(chat.trim());
  if (u == null || !u.host.startsWith('chat.')) return '';
  return '${u.scheme.isEmpty ? 'https' : u.scheme}://kyso.${u.host.substring(5)}';
}

/// Máy chủ ký số mặc định: KYSO_SERVER nếu đặt lúc build, không thì suy từ máy chủ chat đang dùng. Mỗi space vẫn có
/// thể chỉ máy chủ riêng qua env SERVER.
String get kKysoDefaultServer => _kKysoServerOverride.isNotEmpty ? _kKysoServerOverride : kysoServerFor(kServerUrl);

/// Bật ô "Ký số" (bản thử): --dart-define=KYSO_POC=true.
const kKysoPoc = bool.fromEnvironment('KYSO_POC');

/// Mã extension Ký số (= audience của vé Flygo ID cho máy chủ ký số).
const kKysoExtensionId = 'vn.flygo.kyso';

const _runtimeId = 'vn.flygo.magic-sign';
const _authScheme = 'vn.flygo.magic-sign';
const _customScheme = 'flygoext';

/// Khoá storage chứa bí mật: để trong secure storage, không ghi ra tệp.
const _secretKeys = {'token'};

/// Nền tảng chạy được app Browser (WebView có user script lúc document_start, WebView ẩn). Linux: chưa.
/// Windows: build được nhưng chưa chạy thử thật (máy build Windows tắt), nên chỉ bật với KYSO_POC.
bool get kysoSupported =>
    Platform.isAndroid || (Platform.isIOS && _iosMajor() >= 17) || Platform.isMacOS || (Platform.isWindows && kKysoPoc);

/// iOS 17 trở lên mới có data store riêng cho từng space (Sếp chốt: iOS tối thiểu 17 cho Browser; app vẫn 15).
int _iosMajor() => int.tryParse(RegExp(r'(\d+)').firstMatch(Platform.operatingSystemVersion)?.group(1) ?? '') ?? 0;

/// Trang của app (engine, hộp ký) nằm ở một origin an toàn để WebCrypto và IndexedDB (khoá thiết bị) chạy.
String get kysoAppBase => Platform.isAndroid
    ? 'https://appassets.androidplatform.net/assets/flutter_assets/assets/magicsign/'
    : '$_customScheme://app/assets/magicsign/';
String get _appOrigin {
  final base = Uri.parse(kysoAppBase);
  return '${base.scheme}://${base.host}';
}

bool _isAppUrl(String? url) => url != null && url.startsWith(kysoAppBase);
String _extUrl(String page) => '${kysoAppBase}ext/$page';

/// Windows: MagicSignNative dựng trên JS handler "msWeb"; app trả lời qua window.__msNativeIn. Chỉ khung chính.
const _winNative = r'''
(() => {
  if (window.top !== window || window.MagicSignNative) return;
  const listeners = new Set();
  window.__msNativeIn = (data) => listeners.forEach((fn) => { try { fn({ data }); } catch (e) {} });
  const native = {
    postMessage: (data) => window.flutter_inappwebview.callHandler('msWeb', data),
    addEventListener: (type, fn) => { if (type === 'message') listeners.add(fn); },
  };
  (function attach(tries) {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) { window.MagicSignNative = native; return; }
    if (tries < 500) setTimeout(() => attach(tries + 1), 10);
  })(0);
})();
''';

/// Engine: WebSocket chỉ tới các origin đã khai (api_origins / host_origins). Định nghĩa không ghi đè được.
String _wsGuard(List<String> allowed) => '''
(() => {
  const allowed = new Set(${jsonEncode(allowed)});
  const Native = window.WebSocket;
  function Guarded(url, protocols) {
    const u = new URL(url, location.href);
    if (!allowed.has(u.protocol + '//' + u.host)) throw new DOMException('NOT_ALLOWED_ORIGIN ' + u.origin, 'SecurityError');
    return protocols === undefined ? new Native(url) : new Native(url, protocols);
  }
  Guarded.prototype = Native.prototype;
  for (const k of ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED']) Guarded[k] = Native[k];
  Object.defineProperty(window, 'WebSocket', { value: Guarded, writable: false, configurable: false });
})();
''';

InAppWebViewSettings kysoAppPageSettings() => InAppWebViewSettings(
      javaScriptEnabled: true,
      transparentBackground: true,
      isInspectable: kDebugMode,
      resourceCustomSchemes: Platform.isIOS || Platform.isMacOS ? const [_customScheme] : null,
      webViewAssetLoader: Platform.isAndroid
          ? WebViewAssetLoader(pathHandlers: [AssetsPathHandler(path: '/assets/')])
          : null,
    );

/// Phục vụ `flygoext://app/assets/<gói extension>/...` từ asset của Flutter (iOS, macOS, Windows).
Future<CustomSchemeResponse?> kysoServeAsset(WebResourceRequest request) async {
  final url = request.url;
  if (url.scheme != _customScheme || !url.path.startsWith('/assets/magicsign/') || url.path.contains('..')) return null;
  try {
    final data = await rootBundle.load(url.path.substring(1));
    return CustomSchemeResponse(data: data.buffer.asUint8List(), contentType: _mime(url.path));
  } catch (_) {
    return null;
  }
}

String _mime(String path) {
  if (path.endsWith('.html')) return 'text/html';
  if (path.endsWith('.js')) return 'text/javascript';
  if (path.endsWith('.css')) return 'text/css';
  if (path.endsWith('.json')) return 'application/json';
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.svg')) return 'image/svg+xml';
  return 'application/octet-stream';
}

/// Một khung của website đang nói chuyện với app.
class _Frame {
  _Frame(this.fid, this.origin, this.isMain, this.post, this.tab);
  final String fid;
  final String origin;
  final bool isMain;
  final void Function(String data) post;
  final KysoTab tab;
  int? port;

  void send(Map<String, dynamic> message) => post(jsonEncode({'fid': fid, ...message}));
}

/// Những gì host biết về một tab trình duyệt ký số.
class KysoTab {
  KysoTab(this.id, {this.lockTokenId});
  final int id;
  String url = '';
  InAppWebViewController? web;
  InAppWebViewController? prompt;
  final overlay = ValueNotifier<bool>(false);

  /// Tab của một token: hộp ký chỉ cho chọn token đó.
  final String? lockTokenId;
}

class KysoHost {
  KysoHost._(this.server, this.space);

  /// Mỗi (máy chủ ký số, space) một runtime: một engine, một phiên. Đăng nhập bằng Flygo ID cho phiên gắn đúng
  /// một token, nên mỗi space (mỗi token) cần phiên riêng; đăng nhập Google cũ dùng chung một phiên (space null).
  static final _byServer = <String, KysoHost>{};
  static KysoHost forServer(String server, {String? space}) {
    final s = server.trim().replaceAll(RegExp(r'/+$'), '');
    return _byServer['$s|${space ?? ''}'] ??= KysoHost._(s, space);
  }

  /// Space (Flygo ID) của runtime; null = phiên chung kiểu cũ.
  final String? space;

  /// Runtime của máy chủ mặc định.
  static KysoHost get instance => forServer(kKysoDefaultServer);

  /// Máy chủ ký số của runtime này (env SERVER của các space).
  final String server;

  /// Manifest Flygo của extension (assets/magicsign/flygo-manifest.json).
  late final ExtensionManifest manifest;
  Map<String, String> get env => {'SERVER': server};

  String get _ns {
    final host = Uri.tryParse(server)?.host ?? 'default';
    final s = space == null ? '' : '-${space!.split('/').last}';
    return '$host$s'.replaceAll(RegExp(r'[^A-Za-z0-9.-]'), '_');
  }

  final _store = <String, dynamic>{};
  File? _storeFile;
  File? _secretFile;
  static bool get _mobile => Platform.isAndroid || Platform.isIOS;
  final _secure = const FlutterSecureStorage();
  HeadlessInAppWebView? _engine;
  InAppWebViewController? _engineView;
  final _engineReady = Completer<void>();
  Future<void>? _starting;
  final _appViews = <InAppWebViewController>{};
  final _frames = <String, _Frame>{};
  final _ports = <int, _Frame>{};
  int _nextPort = 1;
  Future<void> _portQueue = Future.value();
  final tabs = <int, KysoTab>{};
  int _nextTabId = 1;

  /// Windows: môi trường WebView2 có đăng ký scheme của app (an toàn như https) cho engine và hộp ký.
  WebViewEnvironment? appEnvironment;
  final _tokenEnvironments = <String, WebViewEnvironment>{};

  /// Tăng mỗi lần storage đổi (phiên, danh sách token…).
  final storeVersion = ValueNotifier<int>(0);
  dynamic stored(String key) => _store[key];

  /// Trạng thái kết nối (state, user, serverUrl…), làm mới sau mỗi thay đổi.
  final status = ValueNotifier<Map<String, dynamic>>(const {});

  /// Mở một URL trong tab mới (window.open, tabs.create); giao diện đặt.
  int? Function(String url)? openUrl;
  int? activeTab;

  late final List<String> _pageScripts;
  late final String _shimSource;
  late final String promptSource;

  /// Đọc storage, nạp script, chạy engine. Gọi nhiều lần cũng chỉ chạy một lần.
  Future<void> ensureStarted() => _starting ??= _start();

  Future<void> _start() async {
    final dir = await getApplicationSupportDirectory();
    manifest = ExtensionManifest.fromJson(
      jsonDecode(await rootBundle.loadString('assets/magicsign/flygo-manifest.json')) as Map,
      base: 'assets/magicsign/',
    );
    final folder = Directory('${dir.path}/browser/${manifest.id}/$_ns')..createSync(recursive: true);
    _storeFile = File('${folder.path}/storage.json');
    if (await _storeFile!.exists()) {
      try {
        _store.addAll(jsonDecode(await _storeFile!.readAsString()) as Map<String, dynamic>);
      } catch (_) {}
    }
    // Bí mật (token, khoá thiết bị): điện thoại ở secure storage; máy tính ở secrets.json chỉ chủ máy đọc được
    // (keychain macOS cần entitlement app không có, ghi lỗi thì mất phiên Ký số sau mỗi lần mở lại).
    _secretFile = File('${folder.path}/secrets.json');
    if (!_mobile && await _secretFile!.exists()) {
      try {
        final m = jsonDecode(await _secretFile!.readAsString()) as Map<String, dynamic>;
        for (final key in _secretKeys) {
          if (m.containsKey(key)) _store[key] = m[key];
        }
      } catch (_) {}
    }
    for (final key in _mobile ? _secretKeys : const <String>[]) {
      try {
        final value = await _secure.read(key: _secretKey(key));
        if (value != null) _store[key] = jsonDecode(value);
      } catch (_) {}
    }
    // Máy chủ do space cho (env SERVER), không dò trong mạng LAN (magic-sign.local).
    _store['serverUrl'] = server;
    // App không có nút tắt: website luôn ký qua app.
    _store['enabled'] = true;
    _store['deviceName'] ??= 'Flygo Chat trên ${_platformName()}';
    _shimSource = await rootBundle.loadString('assets/magicsign/app/shim.js');
    promptSource = await rootBundle.loadString('assets/magicsign/ext/prompt.js');
    _pageScripts = [
      if (Platform.isWindows) _winNative,
      await rootBundle.loadString('assets/magicsign/app/page-bridge.js'),
      await rootBundle.loadString('assets/magicsign/ext/inject.js'),
    ];
    if (Platform.isWindows) {
      appEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: '${dir.path}\\kyso-webview\\app',
          customSchemeRegistrations: [
            CustomSchemeRegistration(scheme: _customScheme, treatAsSecure: true, hasAuthorityComponent: true),
          ],
        ),
      );
    }
    _engine = HeadlessInAppWebView(
      webViewEnvironment: appEnvironment,
      initialUrlRequest: URLRequest(url: WebUri('${kysoAppBase}app/engine.html')),
      initialSettings: kysoAppPageSettings(),
      initialUserScripts: UnmodifiableListView([
        UserScript(source: _wsGuard(_wsOrigins()), injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
        roleScript('engine'),
      ]),
      onLoadResourceWithCustomScheme: (_, request) => kysoServeAsset(request),
      onWebViewCreated: (controller) {
        _engineView = controller;
        controller.addJavaScriptHandler(handlerName: 'ms', callback: (args) => _fromEngine(args));
      },
      onConsoleMessage: (_, message) => debugPrint('[kyso engine] ${message.message}'),
    );
    await _engine!.run();
    await _engineReady.future.timeout(const Duration(seconds: 20), onTimeout: () {
      debugPrint('[kyso] engine không sẵn sàng sau 20 giây');
    });
    for (final seconds in const [0, 3, 10]) {
      Timer(Duration(seconds: seconds), refreshStatus);
    }
  }

  String _secretKey(String key) => 'browser.${manifest.id}.$_ns.$key';

  /// Origin WebSocket engine được mở: api_origins (đổi https → wss) và host_origins.
  List<String> _wsOrigins() {
    final out = <String>{};
    for (final d in [...manifest.apiOrigins, ...manifest.hostOrigins]) {
      final o = d.resolve(env);
      if (o == null) continue;
      out.add(o.replaceFirst(RegExp('^https:'), 'wss:').replaceFirst(RegExp('^http:'), 'ws:'));
    }
    return out.toList();
  }

  String _platformName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows';
    return 'Linux';
  }

  /// Windows: mỗi token một thư mục dữ liệu WebView2 riêng (cookie cổng thuế của công ty này không lẫn công ty kia).
  Future<WebViewEnvironment?> environmentFor(String tokenId) async {
    if (!Platform.isWindows) return null;
    final hit = _tokenEnvironments[tokenId];
    if (hit != null) return hit;
    final dir = await getApplicationSupportDirectory();
    final safe = tokenId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final env = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: '${dir.path}\\kyso-webview\\$safe',
        customSchemeRegistrations: [
          CustomSchemeRegistration(scheme: _customScheme, treatAsSecure: true, hasAuthorityComponent: true),
        ],
      ),
    );
    return _tokenEnvironments[tokenId] = env;
  }

  /// shim.js cho một trang của app (engine, prompt).
  UserScript roleScript(String role) => UserScript(
        source: 'window.__msRole = ${jsonEncode(role)};\n$_shimSource',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: true,
      );

  /// inject.js + page-bridge.js cho website. iOS / macOS chỉ trả lời web message ở khung chính; Windows dùng JS
  /// handler, cũng chỉ khung chính.
  List<UserScript> websiteScripts() => [
        for (final source in _pageScripts)
          UserScript(
            source: source,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: !Platform.isAndroid,
          ),
      ];

  KysoTab newTab({String? lockTokenId}) {
    final tab = KysoTab(_nextTabId++, lockTokenId: lockTokenId);
    tabs[tab.id] = tab;
    return tab;
  }

  Future<void> refreshStatus() async {
    final state = await sendMessage({'t': 'status'}, _appSender(_extUrl('popup.html')));
    if (state is Map) status.value = Map<String, dynamic>.from(state);
  }

  // ---- các lệnh gọi vào engine ------------------------------------------------

  Future<dynamic> _engineCall(String body, Map<String, dynamic> arguments) async {
    await _engineReady.future;
    final result = await _engineView?.callAsyncJavaScript(functionBody: body, arguments: arguments);
    if (result?.error != null) debugPrint('[kyso engine] ${result!.error}');
    return result?.value;
  }

  Future<dynamic> sendMessage(Map<String, dynamic> message, Map<String, dynamic> sender) =>
      _engineCall('return await window.__ms.message(message, sender);', {'message': message, 'sender': sender});

  Map<String, dynamic> _appSender(String url, [KysoTab? tab]) => {
        'id': _runtimeId,
        'url': url,
        'origin': _appOrigin,
        if (tab != null) 'tab': {'id': tab.id, 'url': tab.url},
      };

  /// Đăng nhập máy chủ ký số [serverUrl] (SSO Google của máy chủ). Trả về lỗi, hoặc null nếu xong.
  Future<String?> login(String serverUrl) async {
    await ensureStarted();
    final reply = await sendMessage(
      {'t': 'login', 'serverUrl': serverUrl, 'deviceName': _store['deviceName'], 'sso': true},
      _appSender(_extUrl('popup.html')),
    );
    await refreshStatus();
    if (reply is Map && reply['ok'] == true) return null;
    return reply is Map ? '${reply['error'] ?? 'Không đăng nhập được'}' : 'Không đăng nhập được';
  }

  /// Đăng nhập máy chủ ký số bằng vé Flygo ID của space (không cần Google): native xin vé (gắn với space, chỉ
  /// native giữ), đổi lấy phiên ở POST /api/session/flygo rồi ghi vào storage như extension tự đăng nhập.
  Future<String?> loginFlygo(Future<String> Function() ticket) async {
    await ensureStarted();
    final String jwt;
    try {
      jwt = await ticket();
    } catch (e) {
      return 'Không lấy được vé Flygo ID: $e';
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse('$server/api/session/flygo'));
      req.followRedirects = false;
      req.headers.set('authorization', 'Bearer $jwt');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'device_id': _store['deviceId'], 'device_name': _store['deviceName']}));
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res.transform(utf8.decoder).join();
      Map<String, dynamic> j = const {};
      try {
        j = Map<String, dynamic>.from(jsonDecode(body) as Map);
      } catch (_) {}
      if (res.statusCode != 200 || j['access_token'] is! String) {
        return '${j['error'] ?? 'Máy chủ ký số trả lỗi ${res.statusCode}'}';
      }
      final user = j['user'] is Map ? j['user'] as Map : const {};
      await _storageWrite({
        'serverUrl': server,
        'token': j['access_token'],
        'username': '${user['username'] ?? ''}',
        'displayName': '${user['displayName'] ?? ''}',
      }, const []);
      return null;
    } catch (e) {
      return 'Không nối được máy chủ ký số: $e';
    } finally {
      client.close();
    }
  }

  /// Ghim / đổi tên / bỏ ghim một trang của công ty (token_pins trên máy chủ ký số, cả công ty thấy). Bỏ ghim chỉ
  /// admin làm được. Trả về lỗi hoặc null.
  Future<String?> setPin(String tokenId, String url, String title, {bool remove = false}) async {
    final reply = await sendMessage(
      {'t': 'pin_set', 'tokenId': tokenId, 'url': url, 'title': title, 'remove': remove},
      _appSender(_extUrl('popup.html')),
    );
    if (reply is Map && reply['error'] != null) return '${reply['error']}';
    return null;
  }

  bool get loggedIn => '${_store['token'] ?? ''}'.isNotEmpty;

  Future<void> logout() async {
    await sendMessage({'t': 'logout'}, _appSender(_extUrl('popup.html')));
    await refreshStatus();
  }

  /// Mã profile WebView (UUID, iOS cần dạng này) của token: cookie và storage của mỗi công ty để riêng.
  Future<String> profileFor(String tokenId) async {
    final map = Map<String, dynamic>.from(_store['kysoProfiles'] as Map? ?? const {});
    final hit = map[tokenId];
    if (hit is String) return hit;
    final id = _uuid4();
    await _storageWrite({'kysoProfiles': {...map, tokenId: id}}, const []);
    return id;
  }

  static String _uuid4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Token người này được dùng trên máy chủ đang đăng nhập (catalog của máy chủ).
  List<Map<String, dynamic>> get tokens {
    final catalog = _store['serverCatalog'];
    if (catalog is! Map) return const [];
    return (catalog['tokens'] as List? ?? const []).whereType<Map>().map((t) => Map<String, dynamic>.from(t)).toList();
  }

  // ---- storage ----------------------------------------------------------------

  Map<String, dynamic> _storageGet(List<dynamic>? keys) => keys == null
      ? Map<String, dynamic>.from(_store)
      : {for (final key in keys) if (_store.containsKey(key)) key as String: _store[key]};

  Future<void> _storageWrite(Map<String, dynamic> next, Iterable<String> removed) async {
    final changes = <String, dynamic>{};
    next.forEach((key, value) {
      final old = _store[key];
      if (jsonEncode(old) == jsonEncode(value)) return;
      changes[key] = {'oldValue': old, 'newValue': value};
      _store[key] = value;
    });
    for (final key in removed) {
      if (!_store.containsKey(key)) continue;
      changes[key] = {'oldValue': _store.remove(key)};
    }
    if (changes.isEmpty) return;
    storeVersion.value++;
    final plain = Map<String, dynamic>.from(_store)..removeWhere((key, _) => _secretKeys.contains(key));
    await _storeFile?.writeAsString(jsonEncode(plain));
    if (!_mobile && changes.keys.any(_secretKeys.contains)) {
      try {
        final secrets = {for (final key in _secretKeys) if (_store.containsKey(key)) key: _store[key]};
        await _secretFile?.writeAsString(jsonEncode(secrets));
        if (!Platform.isWindows && _secretFile != null) await Process.run('chmod', ['600', _secretFile!.path]);
      } catch (e) {
        debugPrint('[kyso] secrets file: $e');
      }
    }
    for (final key in _mobile ? changes.keys.where(_secretKeys.contains) : const <String>[]) {
      try {
        if (_store.containsKey(key)) {
          await _secure.write(key: _secretKey(key), value: jsonEncode(_store[key]));
        } else {
          await _secure.delete(key: _secretKey(key));
        }
      } catch (e) {
        debugPrint('[kyso] secure storage: $e');
      }
    }
    const notify = 'window.__ms && window.__ms.storageChanged(changes);';
    unawaited(_engineView?.callAsyncJavaScript(functionBody: notify, arguments: {'changes': changes}));
    for (final view in _appViews.toList()) {
      unawaited(view.callAsyncJavaScript(functionBody: notify, arguments: {'changes': changes}));
    }
    if (changes.keys.any((key) => const {'enabled', 'ports', 'debug'}.contains(key))) {
      for (final frame in _frames.values) {
        frame.send({'k': 'config', 'config': _pageConfig(), 'changed': changes.containsKey('enabled')});
      }
    }
    if (changes.keys.any((key) => const {'enabled', 'agents', 'token', 'serverUrl'}.contains(key))) {
      for (final seconds in const [0, 3, 10]) {
        Timer(Duration(seconds: seconds), refreshStatus);
      }
    }
  }

  Map<String, dynamic> _pageConfig() => {
        'enabled': _store['enabled'] != false,
        'ports': _store['ports'] ?? const [],
        'debug': _store['debug'],
      };

  // ---- engine hỏi -------------------------------------------------------------

  Future<dynamic> _fromEngine(List<dynamic> args) async {
    final call = Map<String, dynamic>.from(args.first as Map);
    switch (call['op']) {
      case 'engine.ready':
        if (!_engineReady.isCompleted) _engineReady.complete();
        return true;
      case 'port.post':
        _ports[call['port']]?.send({'k': 'port', 'message': call['message']});
        return true;
      case 'port.disconnect':
        final frame = _ports.remove(call['port']);
        frame?.port = null;
        return true;
      case 'tabs.sendMessage':
        final tab = tabs[call['tabId']];
        if (tab?.prompt == null) return false;
        await tab!.prompt!.callAsyncJavaScript(
          functionBody: 'await window.__ms.message(message, sender); return true;',
          arguments: {'message': _lockToken(tab, call['message']), 'sender': _appSender(kysoAppBase)},
        );
        return true;
      case 'fetch':
        return _fetch(call);
    }
    return _common(call, _appSender('${kysoAppBase}app/engine.html'));
  }

  /// Hộp ký trong tab của một token: chỉ chọn được token đó.
  dynamic _lockToken(KysoTab tab, dynamic message) {
    final lock = tab.lockTokenId;
    if (lock == null || message is! Map || message['t'] != 'magic-sign:prompt' || message['prompt'] is! Map) return message;
    final prompt = Map<String, dynamic>.from(message['prompt'] as Map);
    final all = (prompt['certificates'] as List? ?? const []).whereType<Map>().toList();
    final mine = all.where((certificate) => certificate['tokenId'] == lock).toList();
    prompt['certificates'] = mine;
    if (mine.isEmpty) {
      prompt['warnings'] = [
        ...(prompt['warnings'] as List? ?? const []),
        {'level': 'danger', 'text': 'Token của ô Ký số này không ký được yêu cầu này. Hãy mở đúng ô Ký số của công ty cần ký.'},
      ];
    }
    return {...message, 'prompt': prompt};
  }

  /// "Ký và nhớ 60 giây": tới lúc này các lần ký không hỏi lại.
  DateTime _rememberUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool get _remembered => DateTime.now().isBefore(_rememberUntil);

  /// Chủ máy xác nhận chữ ký: vân tay / khuôn mặt / Windows Hello, hoặc khoá màn hình nếu chưa cài sinh trắc.
  Future<Map<String, dynamic>> _biometric({bool remember = false}) async {
    if (_remembered) return {'ok': true};
    final result = await _checkOwner();
    if (result['ok'] == true && remember) _rememberUntil = DateTime.now().add(const Duration(seconds: 60));
    return result;
  }

  /// Hỏi chủ máy (vân tay / khuôn mặt / Windows Hello / mật khẩu máy) trước một việc nhạy cảm, vd điền mật khẩu.
  /// Không dùng "nhớ 60 giây": mỗi lần điền đều hỏi.
  Future<String?> confirmOwner(String reason) async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return 'Máy chưa cài khoá màn hình hay sinh trắc học.';
      return await auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true) ? null : 'Chưa xác thực được.';
    } on LocalAuthException catch (error) {
      return 'Chưa xác thực được (${error.code.name}).';
    } catch (error) {
      return 'Chưa xác thực được: $error';
    }
  }

  Future<Map<String, dynamic>> _checkOwner() async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) {
        return {'ok': false, 'error': 'Máy chưa cài khoá màn hình hay sinh trắc học (vân tay, khuôn mặt, Windows Hello): hãy cài rồi ký lại.'};
      }
      final ok = await auth.authenticate(localizedReason: 'Xác nhận ký số', persistAcrossBackgrounding: true);
      return ok ? {'ok': true} : {'ok': false, 'error': 'Chưa xác thực được, chưa ký.'};
    } on LocalAuthException catch (error) {
      return {'ok': false, 'error': 'Chưa xác thực được (${error.code.name}), chưa ký.'};
    } catch (error) {
      return {'ok': false, 'error': 'Chưa xác thực được: $error'};
    }
  }

  /// Đăng nhập máy tính: đặt bởi giao diện (cửa sổ đăng nhập trong app, bắt redirect vn.flygo.magic-sign://).
  Future<String?> Function(String url)? desktopAuth;

  /// Các lệnh mọi trang của app được gọi.
  Future<dynamic> _common(Map<String, dynamic> call, Map<String, dynamic> sender) async {
    switch (call['op']) {
      case 'storage.get':
        return _storageGet(call['keys'] as List?);
      case 'storage.set':
        await _storageWrite(Map<String, dynamic>.from(call['items'] as Map), const []);
        return null;
      case 'storage.remove':
        await _storageWrite(const {}, List<String>.from(call['keys'] as List));
        return null;
      case 'storage.managed':
        // Như chính sách quản trị của Chrome: máy chủ cố định theo space, extension không tự dò.
        return {'serverUrl': server, 'deviceName': _store['deviceName']};
      case 'runtime.sendMessage':
        return sendMessage(Map<String, dynamic>.from(call['message'] as Map), sender);
      case 'tabs.query':
        final activeOnly = (call['query'] as Map?)?['active'] == true;
        return [
          for (final tab in tabs.values)
            if (!activeOnly || tab.id == activeTab) {'id': tab.id, 'url': tab.url, 'active': tab.id == activeTab},
        ];
      case 'tabs.create':
        return {'id': openUrl?.call(call['url'] as String) ?? activeTab ?? 0};
      case 'open':
        return null;
      case 'biometric':
        return _biometric(remember: call['remember'] == true);
      case 'biometricRemembered':
        return _remembered;
      case 'identity.auth':
        final url = call['url'] as String;
        if (Platform.isAndroid || Platform.isIOS) {
          try {
            return {'url': await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: _authScheme)};
          } catch (error) {
            return {'error': error is PlatformException && error.code == 'CANCELED' ? 'Đã hủy đăng nhập' : '$error'};
          }
        }
        final done = await desktopAuth?.call(url);
        return done == null ? {'error': 'Đã hủy đăng nhập'} : {'url': done};
    }
    return null;
  }

  /// fetch khác origin của background: đi qua app (không vướng CORS), chỉ tới api_origins / host_origins
  /// (bridge_policy.dart). Chưa có Flygo ID nên chưa gắn vé; extension tự gửi phiên của nó như trước.
  Future<Map<String, dynamic>> _fetch(Map<String, dynamic> call) async {
    final headers = {for (final e in (call['headers'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'};
    // Phiên riêng của app (vd Bearer của Magic Sign) chỉ sống ở background (§10.4a): cho đi kèm, không coi là header cấm.
    final auth = headers.remove('authorization') ?? headers.remove('Authorization');
    final body = call['body'] as String?;
    try {
      checkFetch(
        surface: Surface.background,
        manifest: manifest,
        env: env,
        url: call['url'] as String,
        headers: headers,
        bodyBytes: body == null ? 0 : utf8.encode(body).length,
      );
    } on BridgeError catch (e) {
      debugPrint('[browser] chặn fetch ${call['url']}: $e');
      return {'error': '$e'};
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(call['method'] as String, Uri.parse(call['url'] as String));
      request.followRedirects = false;
      headers.forEach((key, value) => request.headers.set(key, value));
      if (auth != null) request.headers.set('authorization', auth);
      if (call['body'] != null) request.write(call['body']);
      final response = await request.close().timeout(const Duration(seconds: 30));
      final bytes = await response.fold<BytesBuilder>(BytesBuilder(), (builder, chunk) => builder..add(chunk));
      final out = <String, String>{};
      response.headers.forEach((name, values) => out[name] = values.join(', '));
      final data = bytes.takeBytes();
      if (data.length > kMaxResponseBytes) return {'error': 'TOO_LARGE: phản hồi quá 20 MB'};
      return {'status': response.statusCode, 'headers': filterResponseHeaders(out), 'body': base64Encode(data)};
    } catch (error) {
      return {'error': '$error'};
    } finally {
      client.close();
    }
  }

  // ---- trang của app (hộp ký) -------------------------------------------------

  void attachAppPage(InAppWebViewController controller, {KysoTab? promptFor}) {
    _appViews.add(controller);
    if (promptFor != null) promptFor.prompt = controller;
    controller.addJavaScriptHandler(
      handlerName: 'ms',
      callback: (args) async {
        final call = Map<String, dynamic>.from(args.first as Map);
        if (call['op'] == 'overlay') {
          promptFor?.overlay.value = call['visible'] == true;
          return null;
        }
        final url = (await controller.getUrl())?.toString() ?? kysoAppBase;
        if (!_isAppUrl(url)) return null;
        return _common(call, _appSender(url, promptFor));
      },
    );
  }

  void detachAppPage(InAppWebViewController controller) => _appViews.remove(controller);

  // ---- website ----------------------------------------------------------------

  /// Gắn kênh website ↔ app vào WebView của [tab] (gọi trong onWebViewCreated).
  Future<void> attachWebsite(InAppWebViewController controller, KysoTab tab) async {
    tab.web = controller;
    if (Platform.isWindows) {
      controller.addJavaScriptHandler(
        handlerName: 'msWeb',
        callback: (args) async {
          if (args.isEmpty) return null;
          // Chỉ khung chính có kênh này; origin là của URL khung chính lúc nhận tin.
          final url = await controller.getUrl();
          void post(String data) =>
              unawaited(controller.evaluateJavascript(source: 'window.__msNativeIn && window.__msNativeIn(${jsonEncode(data)});'));
          await _fromWebsite(tab, args.first?.toString(), url, true, post);
          return null;
        },
      );
      return;
    }
    await controller.addWebMessageListener(WebMessageListener(
      jsObjectName: 'MagicSignNative',
      allowedOriginRules: {'*'},
      onPostMessage: (message, sourceOrigin, isMainFrame, replyProxy) => _fromWebsite(
        tab,
        message?.data?.toString(),
        sourceOrigin,
        isMainFrame,
        (data) => replyProxy.postMessage(WebMessage(data: data)),
      ),
    ));
  }

  Future<void> _fromWebsite(
    KysoTab tab,
    String? data,
    WebUri? sourceOrigin,
    bool isMainFrame,
    void Function(String data) post,
  ) async {
    if (data == null) return;
    final Map<String, dynamic> message;
    try {
      message = Map<String, dynamic>.from(jsonDecode(data) as Map);
    } catch (_) {
      return;
    }
    final fid = message['fid'];
    if (fid is! String || fid.length != 32) return;
    final origin = sourceOrigin == null || sourceOrigin.host.isEmpty || !sourceOrigin.isScheme('http') && !sourceOrigin.isScheme('https')
        ? 'null'
        : sourceOrigin.origin;
    var frame = _frames[fid];
    if (frame != null && (frame.origin != origin || frame.tab != tab)) return;
    frame ??= _frames[fid] = _Frame(fid, origin, isMainFrame, post, tab);

    final sender = {
      'origin': origin,
      'url': isMainFrame && tab.url.startsWith(origin) ? tab.url : '$origin/',
      'tab': {'id': tab.id, 'url': tab.url},
      'frameId': isMainFrame ? 0 : 1,
    };
    switch (message['k']) {
      case 'hello':
        frame.send({'k': 'config', 'config': _pageConfig(), 'changed': false});
      case 'port':
        // Giữ thứ tự của trang: mở port trước tin đầu tiên.
        final current = frame;
        _portQueue = _portQueue.then((_) async {
          if (current.port == null) {
            final id = _nextPort++;
            current.port = id;
            _ports[id] = current;
            await _engineCall("window.__ms.connect(id, 'magic-sign', sender);", {'id': id, 'sender': sender});
          }
          await _engineCall('window.__ms.portMessage(id, message);', {'id': current.port, 'message': message['message']});
        }).catchError((Object error) => debugPrint('[kyso port] $error'));
      case 'web':
        final request = Map<String, dynamic>.from(message['message'] as Map? ?? const {});
        if (!manifest.messages.contains(request['t'])) return;
        final result = await sendMessage(request, sender);
        frame.send({'k': 'web', 'rid': message['rid'], 'result': result});
    }
  }

  /// Tab rời trang: khung và port của trang cũ không còn.
  Future<void> pageGone(KysoTab tab) async {
    final gone = _frames.values.where((frame) => frame.tab == tab).toList();
    for (final frame in gone) {
      _frames.remove(frame.fid);
      final port = frame.port;
      if (port == null) continue;
      _ports.remove(port);
      await _engineCall('window.__ms.portClosed(id);', {'id': port});
    }
  }

  Future<void> tabClosed(KysoTab tab) async {
    tabs.remove(tab.id);
    if (tab.prompt != null) detachAppPage(tab.prompt!);
    await pageGone(tab);
    await _engineCall('window.__ms.tabRemoved(id);', {'id': tab.id});
  }

  Future<void> tabUpdated(KysoTab tab) =>
      _engineCall('window.__ms.tabUpdated(tab);', {'tab': {'id': tab.id, 'url': tab.url}});
}
