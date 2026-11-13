// Nhận chia sẻ từ app khác (Android: SEND / SEND_MULTIPLE trong MainActivity / ShareIn.kt; iPhone: Share Extension
// ghi tệp vào App Group rồi mở app): Flygo Chat có trong bảng chia sẻ cho ảnh, video, tệp, chữ, đường link. Chọn Flygo
// Chat thì mở màn "Gửi tới…" (chọn tối đa 5 cuộc trò chuyện, thêm chú thích) của máy chủ đang dùng; chưa đăng nhập
// thì chờ đăng nhập xong mới mở. Kênh "flygo/share": "take" -> {files: [đường dẫn], text} | null; "shared" từ bên
// máy báo có nội dung mới.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import 'forward_page.dart';

/// Nội dung nhận được: tệp trên máy (đường dẫn) và chữ (chữ / link được chia sẻ, chú thích kèm theo).
class SharedPayload {
  final List<String> paths;
  final String text;
  const SharedPayload(this.paths, this.text);
}

/// Đổi dữ liệu kênh "take" thành nội dung gửi: bỏ tệp không còn trên máy, chữ rỗng. Không còn gì thì null.
SharedPayload? parseShared(Object? raw, {bool Function(String path)? exists}) {
  if (raw is! Map) return null;
  final has = exists ?? (p) => File(p).existsSync();
  final paths = [
    for (final f in (raw['files'] as List? ?? const []))
      if (f is String && f.isNotEmpty && has(f)) f,
  ];
  final text = '${raw['text'] ?? ''}'.trim();
  if (paths.isEmpty && text.isEmpty) return null;
  return SharedPayload(paths, text);
}

class ShareIntake with WidgetsBindingObserver {
  ShareIntake._(this._nav, this._session);
  static ShareIntake? _instance;
  static const _channel = MethodChannel('flygo/share');

  final GlobalKey<NavigatorState> _nav;
  final ValueNotifier<AppState?> _session;
  SharedPayload? _pending;

  /// Gọi một lần khi có phiên đăng nhập (cửa sổ chính, điện thoại).
  static void start(GlobalKey<NavigatorState> nav, ValueNotifier<AppState?> session) {
    if (!(Platform.isAndroid || Platform.isIOS) || _instance != null) return;
    final s = _instance = ShareIntake._(nav, session);
    session.addListener(s._flush);
    WidgetsBinding.instance.addObserver(s);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') await s._take();
    });
    s._take();
  }

  /// iPhone: Share Extension mở app bằng flygochat://share; lấy lại mỗi khi app hiện lên cho chắc.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _take();
  }

  Future<void> _take() async {
    try {
      final p = parseShared(await _channel.invokeMethod<Object?>('take'));
      if (p == null) return;
      _pending = p;
      _flush();
    } catch (_) {}
  }

  void _flush() {
    final p = _pending;
    if (p == null || _session.value == null) return;
    final nav = _nav.currentState;
    if (nav == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
      return;
    }
    _pending = null;
    nav.push(MaterialPageRoute(builder: (_) => ForwardPage.share(localPaths: p.paths, sharedText: p.text)));
  }
}
