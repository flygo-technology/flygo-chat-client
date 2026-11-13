// Điều khiển máy tính từ xa: phần nền tảng (kênh flygo/remote_input) của máy bị điều khiển.
// Windows: SendInput; macOS: CGEventPost (cần quyền Trợ năng + Ghi màn hình); Linux: XTest trên phiên X11
// (Wayland chưa hỗ trợ: không chụp / bơm thao tác được mà không qua cổng xdg-desktop-portal, chỉ điều khiển máy khác).
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'rc_protocol.dart';

/// Linux: GTK chạy trên Wayland (không phải X11) theo biến môi trường của phiên đăng nhập. GDK_BACKEND=x11 thì
/// GTK dùng XWayland, vẫn không chụp / điều khiển được cửa sổ Wayland khác nên vẫn tính là Wayland.
bool rcLinuxIsWayland(Map<String, String> env) {
  if ((env['WAYLAND_DISPLAY'] ?? '').isNotEmpty) return true;
  if ((env['XDG_SESSION_TYPE'] ?? '').toLowerCase() == 'wayland') return true;
  return (env['DISPLAY'] ?? '').isEmpty;
}

/// Quyền của macOS (Windows luôn có; Linux X11: accessibility = máy chủ X có phần mở rộng XTest).
class RcPermissions {
  final bool accessibility;
  final bool screen;
  const RcPermissions({required this.accessibility, required this.screen});
  bool get ok => accessibility && screen;
}

class RcNative {
  static const _ch = MethodChannel('flygo/remote_input');

  /// Máy này bị điều khiển được không (Windows, macOS, Linux phiên X11).
  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isMacOS || (Platform.isLinux && !linuxWayland));
  static bool get isMac => !kIsWeb && Platform.isMacOS;
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// Linux chạy Wayland (GTK dùng Wayland, không có X11): chưa hỗ trợ bị điều khiển.
  static bool get linuxWayland => isLinux && rcLinuxIsWayland(Platform.environment);

  /// Bấm "Dừng" trên thanh đỏ hoặc phím tắt dừng.
  static void Function()? onStop;
  static bool _bound = false;

  static void _bind() {
    if (_bound) return;
    _bound = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'stop') onStop?.call();
      return null;
    });
  }

  static Future<RcPermissions> permissions() async {
    if (!isMac && !isLinux) return const RcPermissions(accessibility: true, screen: true);
    try {
      final m = (await _ch.invokeMethod<Map>('status')) ?? const {};
      return RcPermissions(accessibility: m['accessibility'] == true, screen: m['screen'] == true);
    } catch (e) {
      debugPrint('[rc] status: $e');
      return const RcPermissions(accessibility: false, screen: false);
    }
  }

  /// Xin quyền ('accessibility' | 'screen'): hệ điều hành hiện hộp thoại / thêm app vào danh sách trong Cài đặt.
  static Future<void> request(String kind) async {
    try {
      await _ch.invokeMethod('request', {'kind': kind});
    } catch (_) {}
  }

  /// Mở đúng mục trong Cài đặt hệ thống (Quyền riêng tư & Bảo mật).
  static Future<void> openSettings(String kind) async {
    try {
      await _ch.invokeMethod('openSettings', {'kind': kind});
    } catch (_) {}
  }

  /// Các màn hình (toạ độ gốc của hệ điều hành) và màn hình ảo (Windows; Linux = cửa sổ gốc X).
  static Future<(List<RcScreen>, Rect)> screens() async {
    try {
      final m = (await _ch.invokeMethod<Map>('screens')) ?? const {};
      final list = [for (final s in (m['screens'] as List? ?? const [])) RcScreen.fromMap(s as Map)];
      final v = (m['virtual'] as List?)?.map((e) => (e as num).toDouble()).toList();
      final virt = v != null && v.length == 4
          ? Rect.fromLTWH(v[0], v[1], v[2], v[3])
          : list.isEmpty
              ? Rect.zero
              : list.map((s) => s.rect).reduce((a, b) => a.expandToInclude(b));
      return (list, virt);
    } catch (e) {
      debugPrint('[rc] screens: $e');
      return (const <RcScreen>[], Rect.zero);
    }
  }

  /// Gửi một loạt thao tác đã đổi sang mã của hệ điều hành (xem [RcInjector]).
  static Future<void> inject(List<Map<String, Object>> events) async {
    if (events.isEmpty) return;
    try {
      await _ch.invokeMethod('inject', {'events': events});
    } catch (e) {
      debugPrint('[rc] inject: $e');
    }
  }

  /// Thanh đỏ luôn nổi trên cùng "`<Tên>` đang điều khiển máy của bạn · Dừng" ở mép trên màn hình [screen],
  /// kèm phím tắt dừng. Trả về phím tắt đã đăng ký được (vd. "Ctrl+Shift+F12"), rỗng nếu không đăng ký được.
  static Future<String> showBar({required String text, required String stop, RcScreen? screen}) async {
    _bind();
    try {
      return await _ch.invokeMethod<String>('showBar', {
            'text': text,
            'stop': stop,
            if (screen != null) 'screen': [screen.x, screen.y, screen.width, screen.height],
          }) ??
          '';
    } catch (e) {
      debugPrint('[rc] showBar: $e');
      return '';
    }
  }

  static Future<void> hideBar() async {
    try {
      await _ch.invokeMethod('hideBar');
    } catch (_) {}
  }

  /// Cửa sổ app toàn màn hình (máy điều khiển, macOS / Windows / Linux).
  static Future<void> setFullscreen(bool on) async {
    try {
      await _ch.invokeMethod('fullscreen', {'on': on});
    } catch (_) {}
  }
}

/// Đổi thao tác của giao thức thành sự kiện cho [RcNative.inject] trên màn hình đang chia sẻ.
/// Giữ trạng thái phím / nút đang giữ để nhả hết khi kết thúc phiên.
class RcInjector {
  final bool mac;
  /// Linux X11: toạ độ điểm ảnh trên cửa sổ gốc, mã phím X, cuộn theo nấc.
  final bool linux;
  /// Màn hình đang chia sẻ (đổi khi máy điều khiển chọn màn hình khác).
  RcScreen screen;
  final Rect virtualDesk;
  final RcClickCounter _clicks = RcClickCounter();
  final Set<int> _keysDown = {};
  final Set<int> _buttonsDown = {};
  int _wheelX = 0, _wheelY = 0;

  RcInjector({required this.mac, this.linux = false, required this.screen, required this.virtualDesk});

  int? _code(int hid) => mac
      ? rcMacKey(hid)
      : linux
          ? rcLinuxKey(hid)
          : rcWinScan(hid);

  Map<String, Object> _pos(int x, int y) {
    final p = rcWireToScreen(x, y, screen);
    if (linux) return {'x': p.dx.round(), 'y': p.dy.round()};
    if (mac) return {'x': p.dx, 'y': p.dy};
    final (ax, ay) = rcWinAbsolute(p, virtualDesk);
    return {'x': ax, 'y': ay};
  }

  /// Sự kiện nền tảng của [i] (rỗng nếu không làm gì, vd. phím không có trên hệ này).
  List<Map<String, Object>> map(RcInput i) {
    switch (i) {
      case RcMove(:final x, :final y):
        return [
          {'op': 'move', ..._pos(x, y), 'buttons': _buttonsDown.fold<int>(0, (a, b) => a | (1 << b))},
        ];
      case RcButton(:final button, :final down, :final x, :final y):
        final clicks = down ? _clicks.down(button, x, y) : _clicks.current;
        down ? _buttonsDown.add(button) : _buttonsDown.remove(button);
        return [
          {'op': 'button', 'b': button, 'down': down, 'clicks': clicks, ..._pos(x, y)},
        ];
      case RcWheel(:final dx, :final dy) when linux:
        final (nx, rx) = rcLinuxWheel(_wheelX + dx);
        final (ny, ry) = rcLinuxWheel(_wheelY + dy);
        _wheelX = rx;
        _wheelY = ry;
        if (nx == 0 && ny == 0) return const [];
        return [
          {'op': 'wheel', 'dx': nx, 'dy': ny},
        ];
      case RcWheel(:final dx, :final dy):
        return [
          {'op': 'wheel', 'dx': mac ? rcMacWheel(dx) : rcWinWheel(dx), 'dy': mac ? rcMacWheel(dy) : rcWinWheel(dy)},
        ];
      case RcKey(:final hid, :final down):
        final code = _code(hid);
        if (code == null) return const [];
        if (down) {
          _keysDown.add(hid);
        } else if (!_keysDown.remove(hid)) {
          return const []; // nhả phím chưa từng bấm: bỏ qua
        }
        return [
          {'op': 'key', 'code': code, 'down': down, 'hid': hid},
        ];
      case RcText(:final text):
        return [
          {'op': 'text', 's': text},
        ];
      case RcRelease():
        return releaseAll();
      case RcQuality():
      case RcSelectScreen():
        return const [];
    }
  }

  /// Nhả mọi phím / nút đang giữ (kết thúc phiên, máy điều khiển mất tiêu điểm).
  List<Map<String, Object>> releaseAll() {
    final out = <Map<String, Object>>[
      for (final hid in _keysDown.toList().reversed)
        if (_code(hid) case final code?) {'op': 'key', 'code': code, 'down': false, 'hid': hid},
      for (final b in _buttonsDown) {'op': 'button', 'b': b, 'down': false, 'clicks': 1},
    ];
    _keysDown.clear();
    _buttonsDown.clear();
    return out;
  }
}
