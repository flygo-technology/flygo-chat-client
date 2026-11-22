// Trình duyệt Flygo (bản máy tính): engine Chromium riêng (Trình duyệt Ký số đa năng ở chế độ --managed) do Flygo Chat tải,
// cài, cập nhật, mở và đăng nhập hộ (Sếp 2026-11-22: "tách tiến trình, chung trải nghiệm"). Kế hoạch:
// ~/handoff/integrated-browser-plan.md (§1 đóng gói, §2 kênh cập nhật, §4 IPC, §5 vé, §6 tự động hoá + kho extension).
//
// IPC: app mở ws://127.0.0.1:<cổng ngẫu nhiên>/kyso-engine; engine chạy với --managed --host-port=<cổng>, khoá trong env
// FLYGO_HOST_KEY; tin đầu {t:"hello", key, version, pid, os} → {t:"welcome"} | {t:"rejected"}. Sau đó RPC hai chiều
// {id, method, params} → {id, result | error}; sự kiện {method, params}.
//   app → engine: open {tax|profile, url?, background?} · list · focus · idle · quit; sự kiện bridge / bridge_revoked /
//                 extensions / spaces / logout.
//   engine → app: yêu cầu spaces · need_credential {space, server}; sự kiện profiles · need_bridge {profileKey, server?} ·
//                 agent · sign_pending · status.
// Vé: vn.flygo.kyso gắn space (engine đổi lấy phiên ở máy chủ ký); vn.flygo.clients → <máy chủ>/__apps/gateway/api/pair
// (token tự động hoá, lưu theo (máy chủ, profile) trong secure storage, engine chỉ giữ trong bộ nhớ).
// Engine chưa có / không chạy được: trả false để nơi gọi mở WebView như cũ.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../auth/auth_service.dart';
import '../config.dart';
import '../data/servers.dart';
import 'flygo_id.dart';
import 'my_browsers.dart';

/// Khoá công khai ed25519 của app vn.flygo.kyso (ghim trong app: gói engine + extension Ký số phải ký bằng khoá này).
const kKysoPinnedKey = 'wXbUm7eOYr8JYzBCc+m5JYFsn9RA0hJAmCPjQ7297YI=';
const kKysoApp = 'vn.flygo.kyso';
const _kEngineName = 'Trinh duyet Ky so da nang';

/// Bản engine đầu tiên có chế độ --managed: bản cài riêng cũ hơn mà chạy với cờ lạ sẽ mở cửa sổ chọn công ty thay vì nối lại.
const _kMinManagedEngine = '1.3.0';

/// Bí mật của trình duyệt Flygo (token Gateway theo máy chủ / profile): tệp JSON trong thư mục app, chỉ chủ máy đọc được.
/// Không dùng Keychain: bản macOS thiếu entitlement keychain nên ghi lỗi (đã gây ghép cặp lặp vô hạn, 2026-11-23).
class FlygoSecrets {
  FlygoSecrets._();
  static Map<String, dynamic>? _cache;
  static Future<void> _lock = Future.value();

  static Future<File> _file() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}flygo-browser')..createSync(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}secrets.json');
  }

  static Future<Map<String, dynamic>> _load() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _file();
      _cache = f.existsSync() ? Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map) : {};
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  static Future<String?> read(String key) async => (await _load())[key] as String?;

  /// Ghi tuần tự, tệp tạm rồi đổi tên (không để tệp dở dang).
  static Future<void> write(String key, String? value) {
    final next = _lock.then((_) async {
      final m = await _load();
      value == null ? m.remove(key) : m[key] = value;
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(m), flush: true);
      if (!Platform.isWindows) await Process.run('chmod', ['600', tmp.path]);
      await tmp.rename(f.path);
    });
    _lock = next.catchError((Object _) {});
    return next;
  }
}

class FlygoBrowserHost {
  FlygoBrowserHost._();
  static final instance = FlygoBrowserHost._();

  static bool get supported => !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  /// Phiên chat hiện tại (đặt khi đăng nhập / đổi máy chủ; null = chưa đăng nhập).
  String? chatToken;

  HttpServer? _server;
  WebSocket? _ws;
  String _key = '';
  int _nextId = 1;
  final _pending = <int, Completer<dynamic>>{};
  Completer<void>? _connected;

  /// Profile đang mở trong engine (từ sự kiện profiles): [{key, company, taxCode, …}].
  final profiles = ValueNotifier<List<Map<String, dynamic>>>(const []);

  /// Profile có agent đang điều khiển (huy hiệu AI trên ô Ký số).
  final agentActive = ValueNotifier<Set<String>>(const {});

  bool get connected => _ws != null;

  /// Phiên bản engine đang chạy (theo hello).
  String? engineVersion;
  int? enginePid;

  /// Tiến trình còn sống không (engine chỉ cho một bản mỗi người dùng: chạy bản mới khi bản cũ chưa thoát thì nó chỉ
  /// chuyển lệnh cho bản cũ rồi tự thoát).
  static bool _alive(int pid) => Platform.isWindows
      ? '${Process.runSync('tasklist', ['/FI', 'PID eq $pid', '/NH']).stdout}'.contains('$pid')
      : Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

  /// Bước đang làm khi mở (màn hình chờ hiện ngay khi bấm): tải trình duyệt / khởi động / đăng nhập / mở trang.
  final stage = ValueNotifier<String>('');

  /// Tiến độ tải trình duyệt 0..1 (null = không tải).
  final download = ValueNotifier<double?>(null);

  Stopwatch? _clock;
  bool _warmClick = false;

  // ------------------------------------------------------------------ nhật ký + đo thời gian
  /// Ghi một dòng vào tệp nhật ký trình duyệt Flygo (macOS ~/Library/Logs/Flygo Chat/flygo-browser.log, Windows
  /// %LOCALAPPDATA%\Flygo\logs\flygo-browser.log): IPC, lỗi, và thời gian từ lúc bấm tới từng bước.
  void log(String msg) {
    final t = _clock == null ? '' : ' +${_clock!.elapsedMilliseconds}ms${_warmClick ? ' (ấm)' : ' (lạnh)'}';
    final line = '${DateTime.now().toIso8601String()}$t $msg';
    debugPrint('[flygo-browser] $line');
    try {
      final dir = Platform.isWindows ? '${Platform.environment['LOCALAPPDATA']}\\Flygo\\logs' : '${Platform.environment['HOME']}/Library/Logs/Flygo Chat';
      Directory(dir).createSync(recursive: true);
      final f = File('$dir${Platform.pathSeparator}flygo-browser.log');
      if (f.existsSync() && f.lengthSync() > 2 * 1024 * 1024) f.renameSync('${f.path}.1');
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  void _stage(String s) {
    stage.value = s;
    log('bước: $s');
  }

  // ------------------------------------------------------------------ mở
  /// Mở công ty (MST) / profile trong trình duyệt Flygo, kèm url. false = không mở được (nơi gọi dùng WebView).
  Future<bool> open({String? tax, String? profile, String? url, bool background = false}) async {
    if (!supported) return false;
    _clock = Stopwatch()..start();
    _warmClick = connected;
    log('mở: tax=${tax ?? ''} profile=${profile ?? ''} url=${url ?? ''} engine ${connected ? 'đang chạy' : 'chưa chạy'}');
    try {
      if (!connected && !await _launch()) {
        log('KẾT QUẢ: không khởi động được trình duyệt → WebView');
        return false;
      }
      _stage('Đang mở trang…');
      final r = await request('open', {'tax': ?tax, 'profile': ?profile, 'url': ?url, 'background': background}, const Duration(seconds: 45));
      log('KẾT QUẢ: cửa sổ đã hiện ($r)');
      return true;
    } catch (e) {
      log('KẾT QUẢ: lỗi mở: $e');
      return false;
    } finally {
      _clock = null;
      stage.value = '';
    }
  }

  // ------------------------------------------------------------------ khởi động sẵn
  bool _warming = false;

  /// Sau khi đăng nhập (máy tính): tải sẵn trình duyệt và chạy ẩn ở nền (không cửa sổ) nếu người dùng có space Ký số, để
  /// lần bấm đầu mở ngay. Gọi nhiều lần cũng chỉ chạy một lần.
  Future<void> prewarm() async {
    if (!supported || _warming || chatToken == null) return;
    // Kiểm tra bản mới sau khởi động sẵn (hoặc khi đã nhận nuôi engine cũ), rồi mỗi 6 giờ.
    _updateTimer ??= Timer.periodic(const Duration(hours: 6), (_) => unawaited(checkUpdate()));
    unawaited(Future<void>.delayed(const Duration(minutes: 1), checkUpdate));
    if (connected) return;
    _warming = true;
    try {
      if ((await _spaces()).isEmpty) return; // không dùng Ký số: không tốn RAM
      log('khởi động sẵn');
      await _launch(quiet: true);
    } catch (e) {
      log('khởi động sẵn lỗi: $e');
    } finally {
      _warming = false;
    }
  }

  // ------------------------------------------------------------------ cập nhật engine
  Timer? _updateTimer;
  bool _updating = false;

  /// Tải bản engine mới trên kênh (nếu có) ở nền; thay bản đang chạy chỉ khi rảnh: không cửa sổ công ty nào mở, không
  /// ký chờ, không agent điều khiển. Chưa rảnh thì thử lại sau 10 phút; engine đang tắt thì lần khởi động sau dùng bản mới.
  Future<void> checkUpdate() async {
    if (!supported || _updating) return;
    _updating = true;
    try {
      final root = await _installRoot();
      final have = _newestInstalled(root);
      final haveVer = have == null ? null : _verOfPath(have);
      if (await _install(root, quiet: true, newerThan: haveVer) != null) log('đã tải engine mới (đang có ${haveVer ?? 'không'})');
      final newest = _newestInstalled(root);
      final newestVer = newest == null ? null : _verOfPath(newest);
      if (!connected || newestVer == null || engineVersion == null || _cmp(newestVer, engineVersion!) <= 0) return;
      if (profiles.value.isNotEmpty) {
        log('có engine $newestVer, đợi đóng cửa sổ công ty để thay');
        Timer(const Duration(minutes: 10), () => unawaited(checkUpdate()));
        return;
      }
      final r = Map<String, dynamic>.from(await request('quit', {'ifIdle': true}) as Map);
      if (r['quitting'] != true) {
        log('engine chưa rảnh ($r), thử lại sau');
        Timer(const Duration(minutes: 10), () => unawaited(checkUpdate()));
        return;
      }
      final pid = enginePid, old = engineVersion;
      for (var i = 0; i < 75 && (connected || (pid != null && _alive(pid))); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (pid != null && _alive(pid)) {
        log('engine $old (pid $pid) chưa thoát sau 15 giây, để lần sau');
        return;
      }
      log('thay engine $old → $newestVer');
      await _launch(quiet: true);
    } catch (e) {
      log('kiểm tra cập nhật engine lỗi: $e');
    } finally {
      _updating = false;
    }
  }

  /// `<root>/<ver>/…` → ver.
  static String? _verOfPath(String exe) => RegExp(r'[\\/](\d+\.\d+\.\d+)[\\/]').firstMatch(exe)?.group(1);

  // ------------------------------------------------------------------ liên kết flygochat://kyso?tax=…&url=…
  /// macOS: liên kết mở vào app đang chạy qua kênh "flygo/link" (AppDelegate). Đăng nhập Google cũng dùng kênh này và
  /// đặt handler riêng trong lúc đăng nhập; gọi lại hàm này sau khi đăng nhập xong.
  void attachLinks() {
    // Mở cổng IPC + ghi host.json ngay khi khởi động: engine còn chạy từ Flygo Chat trước (mất host) đọc tệp này mỗi 5 giây
    // và nối lại; nó tự tắt nếu 10 giây không thấy host mới, nên không đợi tới lúc khởi động sẵn (+15 giây).
    if (supported) unawaited(_listen().catchError((Object e) => log('mở cổng IPC lỗi: $e')));
    if (!Platform.isMacOS) return;
    const MethodChannel('flygo/link').setMethodCallHandler((call) async {
      final u = Uri.tryParse('${call.arguments}');
      if (call.method != 'open' || u == null || u.host != 'kyso') return;
      final tax = u.queryParameters['tax'], profile = u.queryParameters['profile'], url = u.queryParameters['url'];
      if ((tax ?? profile ?? '').isEmpty || (url != null && !RegExp(r'^https?://').hasMatch(url))) return;
      onLinkOpen?.call(tax: tax, profile: profile, url: url);
    });
  }

  /// Giao diện đặt: mở có màn hình chờ (xem openKysoWithLoading).
  void Function({String? tax, String? profile, String? url})? onLinkOpen;

  /// Profile engine (đã mở ít nhất một lần trên máy này) của công ty có MST [tax].
  Map<String, dynamic>? profileFor(String? tax) {
    if (tax == null || tax.isEmpty) return null;
    for (final p in profiles.value) {
      if ('${p['taxCode']}' == tax) return p;
    }
    return null;
  }

  /// Dữ liệu cục bộ của profile: {label, open, hasSiteData, siteDataBytes, vaultShared}. null khi engine chưa chạy.
  Future<Map<String, dynamic>?> profileInfo(String profileKey) async {
    if (_ws == null) return null;
    try {
      return Map<String, dynamic>.from(await request('profile_info', {'profileKey': profileKey}) as Map);
    } catch (e) {
      log('profile_info $profileKey: $e');
      return null;
    }
  }

  /// Tên hiển thị riêng trên máy này (rỗng = về tên công ty).
  Future<void> profileRename(String profileKey, String label) async {
    if (!connected && !await _launch(quiet: true)) throw StateError('trình duyệt Flygo chưa chạy');
    await request('profile_rename', {'profileKey': profileKey, 'label': label});
  }

  /// Xoá dữ liệu trang (cookie, storage, cache) của profile trên máy này; kho mật khẩu công ty giữ nguyên.
  Future<void> profileClear(String profileKey) async {
    if (!connected && !await _launch(quiet: true)) throw StateError('trình duyệt Flygo chưa chạy');
    await request('profile_clear', {'profileKey': profileKey, 'confirm': true}, const Duration(seconds: 60));
    log('đã xoá dữ liệu profile $profileKey');
  }

  /// Agent / runner cần mở ở nền (không cướp focus).
  Future<bool> openBackground({String? tax, String? profile, String? url}) => open(tax: tax, profile: profile, url: url, background: true);

  Future<dynamic> request(String method, Map<String, dynamic> params, [Duration timeout = const Duration(seconds: 20)]) {
    final ws = _ws;
    if (ws == null) return Future.error(StateError('trình duyệt Flygo chưa nối'));
    final id = _nextId++;
    final c = Completer<dynamic>();
    _pending[id] = c;
    ws.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('trình duyệt Flygo không trả lời $method');
    });
  }

  void _event(String method, Map<String, dynamic> params) => _ws?.add(jsonEncode({'method': method, 'params': params}));

  /// Đăng xuất Flygo Chat: engine đóng cửa sổ công ty, bỏ phiên.
  Future<void> logout() async {
    _event('logout', const {});
    chatToken = null;
  }

  // ------------------------------------------------------------------ khởi chạy engine
  DateTime? _failedAt;

  Future<bool>? _launching;

  /// Một lần khởi động tại một thời điểm (khởi động sẵn và lần bấm dùng chung).
  Future<bool> _launch({bool quiet = false}) {
    final f = _launching;
    if (f != null) {
      if (!quiet) _stage('Đang khởi động trình duyệt…');
      return f;
    }
    return _launching = _doLaunch(quiet: quiet).whenComplete(() => _launching = null);
  }

  Future<bool> _doLaunch({bool quiet = false}) async {
    // Lần trước không chạy được: không thử lại (mỗi lần chờ tới 40 giây) trong 30 phút, mở WebView ngay.
    if (_failedAt != null && DateTime.now().difference(_failedAt!) < const Duration(minutes: 30)) return false;
    if (!quiet) _stage('Đang chuẩn bị trình duyệt…');
    final exe = await _engineExecutable();
    if (exe == null) return false;
    await _listen();
    if (connected) return true; // vừa nối xong trong lúc tải
    if (!quiet) _stage('Đang khởi động trình duyệt…');
    _connected = Completer<void>();
    final env = Map<String, String>.from(Platform.environment)..['FLYGO_HOST_KEY'] = _key;
    final args = ['--managed', '--host-port=${_server!.port}', '--background', '--host-file=${_hostFile!.path}', '--host-pid=$pid'];
    try {
      log('chạy $exe');
      await Process.start(exe, args, environment: env, mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('[flygo-browser] không chạy được $exe: $e');
      return false;
    }
    // Engine một bản mỗi người dùng: engine cũ mồ côi (Flygo Chat trước đã thoát) nhận lệnh chạy thay cho bản mới. Bản
    // engine biết --host-file thì tự nối lại (nhận nuôi); không nối trong 8 giây thì tắt nó (SIGTERM) rồi chạy lại.
    try {
      await _connected!.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      final orphans = await _orphanEngines();
      if (orphans.isNotEmpty) {
        log('engine mồ côi ${orphans.join(',')} không nối lại: tắt rồi chạy lại');
        for (final o in orphans) {
          Process.killPid(o);
        }
        for (var i = 0; i < 50 && orphans.any(_alive); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!connected) await Process.start(exe, args, environment: env, mode: ProcessStartMode.detached);
      }
    }
    try {
      await _connected!.future.timeout(const Duration(seconds: 32));
      _failedAt = null;
      log('trình duyệt đã nối IPC');
      return true;
    } on TimeoutException {
      debugPrint('[flygo-browser] engine không nối lại trong 40 giây');
      _failedAt = DateTime.now();
      return false;
    }
  }

  File? _hostFile;

  /// Tiến trình chính của engine chế độ managed đang chạy (của người dùng này), trừ engine đang nối.
  Future<List<int>> _orphanEngines() async {
    try {
      final r = Platform.isWindows
          ? await Process.run('powershell', ['-NoProfile', '-Command',
              "Get-CimInstance Win32_Process -Filter \"Name='$_kEngineName.exe'\" | Where-Object { \$_.CommandLine -like '*--managed*' -and \$_.CommandLine -notlike '*--type=*' } | ForEach-Object { \$_.ProcessId }"])
          : await Process.run('pgrep', ['-f', 'MacOS/$_kEngineName --managed']);
      return [
        for (final l in '${r.stdout}'.split(RegExp(r'\s+')))
          if (int.tryParse(l) case final p? when p != enginePid || !connected) p,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _listen() async {
    if (_server != null) return;
    final rnd = Random.secure();
    _key = base64Url.encode(List<int>.generate(32, (_) => rnd.nextInt(256)));
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // Tệp nhận nuôi (chỉ chủ máy đọc): engine mồ côi / engine mất kết nối đọc cổng + khoá mới ở đây để nối lại.
    final dir = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}flygo-browser')..createSync(recursive: true);
    _hostFile = File('${dir.path}${Platform.pathSeparator}host.json');
    final tmp = File('${_hostFile!.path}.tmp');
    await tmp.writeAsString(jsonEncode({'port': _server!.port, 'key': _key, 'pid': pid, 'at': DateTime.now().millisecondsSinceEpoch}), flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', tmp.path]);
    await tmp.rename(_hostFile!.path);
    _server!.listen((req) async {
      if (req.uri.path != '/kyso-engine' || !WebSocketTransformer.isUpgradeRequest(req) || req.headers.value('origin') != null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      var hello = false;
      ws.listen((data) {
        Map<String, dynamic> m;
        try {
          m = Map<String, dynamic>.from(jsonDecode(data as String) as Map);
        } catch (_) {
          return;
        }
        if (!hello) {
          if (m['t'] != 'hello' || m['key'] != _key) {
            ws.add(jsonEncode({'t': 'rejected', 'reason': 'sai khoá'}));
            ws.close();
            return;
          }
          hello = true;
          engineVersion = m['version'] as String?;
          enginePid = (m['pid'] as num?)?.toInt();
          _ws?.close();
          _ws = ws;
          ws.add(jsonEncode({'t': 'welcome'}));
          _connected?.complete();
          unawaited(_onConnected());
          return;
        }
        unawaited(_onMessage(ws, m));
      }, onDone: () {
        if (_ws == ws) {
          _ws = null;
          for (final c in _pending.values) {
            if (!c.isCompleted) c.completeError(StateError('trình duyệt Flygo đã đóng'));
          }
          _pending.clear();
        }
      });
    });
  }

  Future<void> _onConnected() async {
    // Danh sách space + extension ngay khi engine nối (engine cũng hỏi lại spaces khi cần).
    try {
      _event('spaces', {'spaces': await _spaces()});
    } catch (_) {}
    unawaited(pushExtensions());
  }

  Future<void> _onMessage(WebSocket ws, Map<String, dynamic> m) async {
    final id = m['id'];
    final method = m['method'] as String?;
    final params = (m['params'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    if (id != null && method == null) {
      final c = _pending.remove(id);
      if (c == null) return;
      if (m['error'] != null) {
        log('engine trả lỗi: ${(m['error'] as Map?)?['message'] ?? m['error']}');
        c.completeError(Exception('${(m['error'] as Map?)?['message'] ?? m['error']}'));
      } else {
        c.complete(m['result']);
      }
      return;
    }
    if (method == null) return;
    log('engine → $method${id != null ? ' (yêu cầu)' : ''} ${jsonEncode(params).substring(0, min(160, jsonEncode(params).length))}');
    if (id != null) {
      // Yêu cầu của engine.
      try {
        final result = await _handle(method, params);
        ws.add(jsonEncode({'id': id, 'result': result}));
      } catch (e) {
        ws.add(jsonEncode({'id': id, 'error': {'message': '$e'}}));
      }
      return;
    }
    switch (method) {
      case 'profiles':
        profiles.value = [for (final p in (params['profiles'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
      case 'need_bridge':
        unawaited(_bridge('${params['profileKey'] ?? ''}', params['server'] as String?));
      case 'agent':
        final s = {...agentActive.value};
        params['active'] == true ? s.add('${params['profileKey']}') : s.remove('${params['profileKey']}');
        agentActive.value = s;
    }
  }

  Future<dynamic> _handle(String method, Map<String, dynamic> p) async {
    switch (method) {
      case 'spaces':
        return {'spaces': await _spaces()};
      case 'need_credential':
        if (_clock != null) _stage('Đang đăng nhập Ký số…');
        final id = await _flygoId();
        final space = '${p['space'] ?? ''}';
        if (space.isEmpty) throw ArgumentError('thiếu space');
        final ticket = await id.ticket(kKysoApp, browser: space, refresh: true);
        return {'ticket': ticket, 'exp': DateTime.now().add(const Duration(minutes: 9)).millisecondsSinceEpoch};
      case 'need_bridge':
        await _bridge('${p['profileKey'] ?? ''}', p['server'] as String?);
        return {'ok': true};
    }
    throw UnsupportedError('không hỗ trợ $method');
  }

  Future<FlygoId> _flygoId() async {
    final t = chatToken;
    if (t == null) throw StateError('Flygo Chat chưa đăng nhập');
    final id = await FlygoId.current(t);
    if (id == null) throw StateError('máy chủ chưa có Flygo ID');
    return id;
  }

  /// Công ty Ký số của tài khoản (cho màn Trình duyệt của tôi).
  Future<List<Map<String, dynamic>>> kysoSpaces() => _spaces().catchError((Object _) => <Map<String, dynamic>>[]);

  /// Space Ký số của người dùng: {id, name, company, server (env SERVER), tokenId (env TOKEN), taxCode (env MST)}.
  Future<List<Map<String, dynamic>>> _spaces() async {
    final id = await _flygoId();
    final out = <Map<String, dynamic>>[];
    for (final s in await id.spaces()) {
      final env = s.extensionEnv[kKysoApp];
      if (env == null || (env['SERVER'] ?? '').isEmpty) continue;
      out.add({'id': s.space.id, 'name': s.space.name, 'company': s.subtitle ?? s.space.name, 'server': env['SERVER'], 'tokenId': env['TOKEN'] ?? '', 'taxCode': env['MST'] ?? ''});
    }
    return out;
  }

  // ------------------------------------------------------------------ token tự động hoá (Gateway) theo (máy chủ, profile)
  final _pairing = <String>{};
  final _pairedAt = <String, DateTime>{};

  Future<void> _bridge(String profileKey, String? only) async {
    if (profileKey.isEmpty || chatToken == null) return;
    // Engine hỏi lại mỗi 5 giây khi chưa có token: một lượt ghép mỗi (máy chủ, profile), tạo mới tối đa 1 lần / phút.
    if (!_pairing.add(profileKey)) return;
    try {
      await _bridgeOnce(profileKey, only);
    } finally {
      _pairing.remove(profileKey);
    }
  }

  Future<void> _bridgeOnce(String profileKey, String? only) async {
    final prof = profiles.value.firstWhere((p) => p['key'] == profileKey, orElse: () => const {});
    final company = '${prof['company'] ?? prof['taxCode'] ?? profileKey}';
    final machine = Platform.localHostname.replaceAll(RegExp(r'\.(local|lan|home)$'), '');
    for (final server in await bridgeServers()) {
      if (only != null && only.replaceAll(RegExp(r'/+$'), '') != server) continue;
      final storeKey = 'flygo-browser-bridge:$server|$profileKey';
      Map<String, dynamic>? saved;
      try {
        final raw = await FlygoSecrets.read(storeKey);
        if (raw != null) saved = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
      // Engine báo cần token (không có, hoặc Gateway từ chối 4401/4403): ghép lại, thay bản ghi cũ.
      if (saved == null || only != null) {
        final last = _pairedAt[storeKey];
        if (last != null && DateTime.now().difference(last) < const Duration(minutes: 1)) continue;
        _pairedAt[storeKey] = DateTime.now();
        final client = {'type': 'integrated', 'name': 'Ký số · $company · $machine'.substring(0, min(60, 'Ký số · $company · $machine'.length)), 'engine': 'Electron', 'os': Platform.isMacOS ? 'macOS' : 'Windows'};
        try {
          final current = server == kServerUrl.replaceAll(RegExp(r'/+$'), '');
          final tok = current ? chatToken! : await TokenStore.readFor(server);
          if (tok == null) continue;
          final r = current
              ? await MyBrowsers.pair(tok, client: client, replace: saved?['client_id'] as String?)
              : await MyBrowsers.pairOn(server, tok, client: client, replace: saved?['client_id'] as String?);
          saved = {'client_id': (r['client'] as Map?)?['id'], 'token': r['token'], 'ws_url': r['ws_url']};
          await FlygoSecrets.write(storeKey, jsonEncode(saved));
          log('đã ghép $server cho $profileKey (${saved['client_id']})');
        } catch (e) {
          log('LỖI ghép $server cho $profileKey: $e');
          continue;
        }
      }
      _event('bridge', {'profileKey': profileKey, 'server': server, ...saved});
    }
  }

  /// Máy chủ đã đăng nhập trong app có Gateway bridge (`<máy chủ>/__apps/gateway`).
  Future<List<String>> bridgeServers() async {
    final out = <String>[];
    final urls = {kServerUrl.replaceAll(RegExp(r'/+$'), ''), for (final e in ServerList.items) e.url.replaceAll(RegExp(r'/+$'), '')};
    for (final u in urls) {
      try {
        final r = await http.get(Uri.parse('$u/__apps/gateway/healthz')).timeout(const Duration(seconds: 5));
        if (r.statusCode == 200 && (jsonDecode(r.body) as Map)['ok'] == true) out.add(u);
      } catch (_) {}
    }
    return out;
  }

  // ------------------------------------------------------------------ kho extension
  /// Gửi danh sách extension (Flygo ID /v1/browser/extensions?host=kyso_desktop) cho engine tự cài / gỡ.
  Future<void> pushExtensions() async {
    if (!connected) return;
    try {
      final id = await _flygoId();
      final j = await id.request('GET', '/v1/browser/extensions?host=kyso_desktop');
      _event('extensions', {'list': j['extensions'] ?? const [], 'revoked': j['revoked'] ?? const [], 'pinned': {kKysoApp: kKysoPinnedKey}});
    } catch (e) {
      debugPrint('[flygo-browser] extensions: $e');
    }
  }

  // ------------------------------------------------------------------ cài / cập nhật engine
  static String? get _platformKey {
    if (Platform.isMacOS) return 'macos-${_arch()}';
    if (Platform.isWindows) return 'windows-x64';
    return null;
  }

  static String _arch() {
    try {
      final r = Process.runSync('uname', ['-m']);
      return '${r.stdout}'.trim() == 'arm64' ? 'arm64' : 'x64';
    } catch (_) {
      return 'arm64';
    }
  }

  static Future<Directory> _installRoot() async {
    if (Platform.isWindows) return Directory('${Platform.environment['LOCALAPPDATA']}\\Flygo\\kyso-engine');
    return Directory('${(await getApplicationSupportDirectory()).path}/kyso-engine');
  }

  /// File chạy engine: bản app tải về (`kyso-engine/<ver>/`), không có thì thử tải theo kênh cập nhật, rồi tới bản cài riêng
  /// (Trình duyệt Ký số đa năng đã cài sẵn, phải đủ mới để có --managed).
  Future<String?> _engineExecutable() async {
    final root = await _installRoot();
    var exe = _newestInstalled(root);
    exe ??= await _install(root).catchError((Object e) {
      debugPrint('[flygo-browser] cài engine: $e');
      return null;
    });
    exe ??= _systemInstalled();
    return exe;
  }

  String? _newestInstalled(Directory root) {
    if (!root.existsSync()) return null;
    final vers = root.listSync().whereType<Directory>().map((d) => d.path.split(Platform.pathSeparator).last).where((v) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v)).toList()
      ..sort(_cmp);
    for (final v in vers.reversed) {
      final e = _exeIn('${root.path}${Platform.pathSeparator}$v');
      if (e != null) return e;
    }
    return null;
  }

  static int _cmp(String a, String b) {
    final x = a.split('.').map(int.parse).toList(), y = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] - y[i];
    }
    return 0;
  }

  String? _exeIn(String dir) {
    final p = Platform.isMacOS ? '$dir/$_kEngineName.app/Contents/MacOS/$_kEngineName' : '$dir\\$_kEngineName.exe';
    return File(p).existsSync() ? p : null;
  }

  String? _systemInstalled() {
    final cands = Platform.isMacOS
        ? ['/Applications/$_kEngineName.app/Contents/MacOS/$_kEngineName', '${Platform.environment['HOME']}/Applications/$_kEngineName.app/Contents/MacOS/$_kEngineName']
        : [
            for (final b in [Platform.environment['ProgramFiles'], Platform.environment['LOCALAPPDATA'] == null ? null : '${Platform.environment['LOCALAPPDATA']}\\Programs'])
              if (b != null) '$b\\$_kEngineName\\$_kEngineName.exe',
          ];
    for (final c in cands) {
      if (File(c).existsSync() && _cmp(_versionOf(c) ?? '0.0.0', _kMinManagedEngine) >= 0) return c;
    }
    return null;
  }

  /// Phiên bản của bản cài riêng (macOS: Info.plist; Windows: thông tin tệp exe).
  static String? _versionOf(String exe) {
    try {
      final r = Platform.isMacOS
          ? Process.runSync('defaults', ['read', '${exe.substring(0, exe.indexOf('.app/') + 4)}/Contents/Info', 'CFBundleShortVersionString'])
          : Process.runSync('powershell', ['-NoProfile', '-Command', '(Get-Item "$exe").VersionInfo.ProductVersion']);
      final v = RegExp(r'\d+\.\d+\.\d+').firstMatch('${r.stdout}')?.group(0);
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Tải engine theo kyso-engine.json của máy chủ (kiểm sha256 + chữ ký ed25519 bằng khoá ghim), giải nén vào `<ver>/`.
  Future<String?> _install(Directory root, {bool quiet = false, String? newerThan}) async {
    final key = _platformKey;
    if (key == null) return null;
    final base = staticBase('flygo-update');
    final mr = await http.get(Uri.parse('$base/kyso-engine.json')).timeout(const Duration(seconds: 15));
    if (mr.statusCode != 200) return null;
    final m = Map<String, dynamic>.from(jsonDecode(mr.body) as Map);
    final ver = '${m['version'] ?? ''}';
    final file = (m['files'] as Map?)?[key] as String?;
    final want = ((m['sha256'] as Map?)?[key] as String?)?.toLowerCase();
    final sig = (m['sig'] as Map?)?[key] as String?;
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(ver) || file == null || want == null || sig == null) return null;
    if (newerThan != null && _cmp(ver, newerThan) <= 0) return null;
    if (!await _verifySig(want, sig)) throw StateError('chữ ký gói engine không khớp khoá Ký số');
    root.createSync(recursive: true);
    final tmp = File('${root.path}${Platform.pathSeparator}.download-$ver');
    final req = await HttpClient().getUrl(Uri.parse('$base/$file'));
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('tải engine lỗi ${res.statusCode}');
    final total = res.contentLength;
    var got0 = 0;
    if (!quiet) _stage('Đang tải trình duyệt Ký số (lần đầu)…');
    final sink = tmp.openWrite();
    await res.map((chunk) {
      got0 += chunk.length;
      if (total > 0 && !quiet) download.value = got0 / total;
      return chunk;
    }).pipe(sink);
    download.value = null;
    log('đã tải engine ${(got0 / 1048576).toStringAsFixed(1)} MB');
    final got = hash.sha256.convert(await tmp.readAsBytes()).toString();
    if (got != want) {
      tmp.deleteSync();
      throw StateError('sha256 gói engine không khớp');
    }
    final dest = Directory('${root.path}${Platform.pathSeparator}$ver');
    final staging = Directory('${dest.path}.staging');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    // macOS: ditto giữ chữ ký / notarization của .app; Windows: tar có sẵn từ Windows 10.
    final r = Platform.isMacOS
        ? await Process.run('ditto', ['-x', '-k', tmp.path, staging.path])
        : await Process.run('tar', ['-xf', tmp.path, '-C', staging.path]);
    tmp.deleteSync();
    if (r.exitCode != 0) throw StateError('giải nén engine lỗi: ${r.stderr}');
    if (dest.existsSync()) dest.deleteSync(recursive: true);
    staging.renameSync(dest.path);
    return _exeIn(dest.path);
  }

  static Future<bool> _verifySig(String sha256Hex, String sigB64) async {
    try {
      final pub = SimplePublicKey(base64.decode(kKysoPinnedKey), type: KeyPairType.ed25519);
      final sig = Signature(base64.decode(base64.normalize(sigB64.replaceAll('-', '+').replaceAll('_', '/'))), publicKey: pub);
      return await Ed25519().verify(utf8.encode(sha256Hex), signature: sig);
    } catch (_) {
      return false;
    }
  }
}
