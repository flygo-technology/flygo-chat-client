// Điều khiển máy tính từ xa: kết nối tín hiệu tới trạm của máy chủ chat (wss://<trạm>/rc/ws, flygo-chat-server relay/rc.mjs).
// Trạm chỉ chuyển offer / answer / ICE giữa hai máy, không lưu gì; không dùng tin nhắn chat cho tín hiệu.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// Thông tin máy này gửi cho trạm (danh sách "Máy tính" của chính chủ tài khoản): mã máy cố định (tự sinh, lưu trong
/// thư mục dữ liệu app), tên máy, phiên bản app.
class RcDeviceInfo {
  final String id;
  final String name;
  final String version;
  const RcDeviceInfo(this.id, this.name, this.version);

  Map<String, String> toJson() => {'id': id, 'name': name, 'version': version};

  static Future<RcDeviceInfo>? _cached;
  static Future<RcDeviceInfo> load() => _cached ??= _load();

  /// Mã máy đã biết (null khi chưa đọc xong).
  static String? currentId;

  static Future<RcDeviceInfo> _load() async {
    var id = '';
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}rc_device_id');
      if (await f.exists()) id = (await f.readAsString()).trim();
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
        final r = Random.secure();
        id = [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
        await dir.create(recursive: true);
        await f.writeAsString(id, flush: true);
      }
    } catch (e) {
      debugPrint('[rc] device id: $e');
    }
    var name = '';
    try {
      name = Platform.localHostname.replaceFirst(RegExp(r'\.(local|lan|home)$', caseSensitive: false), '');
    } catch (_) {}
    var version = '';
    try {
      final i = await PackageInfo.fromPlatform();
      version = i.buildNumber.isEmpty ? i.version : '${i.version} (${i.buildNumber})';
    } catch (_) {}
    currentId = id;
    return RcDeviceInfo(id, name, version);
  }
}

class RcSignal {
  final String token;
  final String server;
  /// Máy tính Windows / macOS / Linux X11: nhận lời xin điều khiển.
  final bool controllable;
  final void Function(Map<String, dynamic> m) onMessage;
  /// Kết nối bị mất (đang tự nối lại nếu [keepAlive]).
  final void Function()? onDisconnected;
  /// Giữ kết nối luôn mở và tự nối lại (máy tính chờ lời xin); điện thoại chỉ mở khi đang điều khiển.
  final bool keepAlive;
  /// Khả năng của app gửi cho trạm, vd. "invite" (nhận lời mời điều khiển máy người khác).
  final List<String> caps;

  RcSignal({
    required this.token,
    required this.server,
    required this.controllable,
    required this.onMessage,
    this.onDisconnected,
    this.keepAlive = false,
    this.caps = const [],
  });

  WebSocket? _ws;
  Future<bool>? _connecting;
  bool _closed = false;
  Timer? _retry;
  int _backoff = 2;

  bool get connected => _ws != null;

  static String get platformName => kIsWeb
      ? 'web'
      : Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
              ? 'macos'
              : Platform.isLinux
                  ? 'linux'
                  : Platform.isIOS
                      ? 'ios'
                      : 'android';

  /// Mở kết nối (nếu chưa mở). false nếu máy chủ không có trạm hoặc không nối được.
  Future<bool> connect() {
    if (_ws != null) return Future.value(true);
    return _connecting ??= _open().whenComplete(() => _connecting = null);
  }

  Future<bool> _open() async {
    if (_closed) return false;
    try {
      await discoverPush(server);
      final base = pushUrlFor(server);
      if (base.isEmpty) return false;
      final ws = await WebSocket.connect('${base.replaceFirst('http', 'ws')}/rc/ws', headers: {
        'Authorization': 'Bearer $token',
        'X-MM-Server': server,
        'User-Agent': kUserAgent,
      }).timeout(const Duration(seconds: 12));
      if (_closed) {
        ws.close();
        return false;
      }
      ws.pingInterval = const Duration(seconds: 20);
      _ws = ws;
      _backoff = 2;
      ws.listen(
        (data) {
          if (data is! String) return;
          try {
            final m = jsonDecode(data);
            if (m is Map) onMessage(m.cast<String, dynamic>());
          } catch (_) {}
        },
        onDone: () => _lost(ws),
        onError: (_) => _lost(ws),
        cancelOnError: true,
      );
      final dev = await RcDeviceInfo.load();
      send({'t': 'hello', 'controllable': controllable, 'platform': platformName, 'caps': caps, 'device': dev.toJson()});
      return true;
    } catch (e) {
      debugPrint('[rc] signal connect: $e');
      _scheduleRetry();
      return false;
    }
  }

  void _lost(WebSocket ws) {
    if (_ws != ws) return;
    _ws = null;
    onDisconnected?.call();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!keepAlive || _closed) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), () => connect());
    _backoff = (_backoff * 2).clamp(2, 60);
  }

  void send(Map<String, dynamic> m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (e) {
      debugPrint('[rc] signal send: $e');
    }
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    final ws = _ws;
    _ws = null;
    ws?.close();
  }
}
