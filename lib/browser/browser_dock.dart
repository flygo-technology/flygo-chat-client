// Điện thoại: trình duyệt Ký số chạy song song với phần còn lại của Flygo Chat. Mỗi công ty (space) đã mở được giữ
// sống (WebView, các tab, trang đã đăng nhập, phiên ký) ở một lớp nằm trên toàn app; thu nhỏ thì lớp đó ẩn đi và
// hiện một nút nổi "Ký số · N tab" để mở lại ngay. Đóng hẳn (menu "Đóng trình duyệt") mới huỷ WebView.
// Máy tính dùng cửa sổ riêng (lib/kyso/kyso_windows.dart), không dùng lớp này.
import 'package:flutter/material.dart';

/// Một trình duyệt đang mở trong lớp nổi.
class _DockEntry {
  _DockEntry(this.id, this.name, this.color, this.child);
  final String id;
  final String name;
  final Color color;
  final Widget child;
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Số tab đang mở (trình duyệt báo lên).
  int tabs = 1;
}

/// Các trình duyệt đang mở và cái đang hiện. Giao diện: [BrowserDockLayer].
class BrowserDock extends ChangeNotifier {
  BrowserDock._();
  static final instance = BrowserDock._();

  final _entries = <String, _DockEntry>{};
  String? _visible;
  String? _last;

  bool get isEmpty => _entries.isEmpty;
  bool isOpen(String id) => _entries.containsKey(id);

  /// Mở (hoặc hiện lại) trình duyệt [id]. [build] chỉ gọi lần đầu: lần sau trình duyệt đang sống được hiện lại
  /// nguyên trạng.
  void show(String id, {required String name, required Color color, required Widget Function() build}) {
    _entries.putIfAbsent(id, () => _DockEntry(id, name, color, build()));
    _visible = _last = id;
    notifyListeners();
  }

  /// Thu nhỏ: trình duyệt vẫn chạy, quay về Flygo Chat.
  void minimize() {
    if (_visible == null) return;
    _visible = null;
    notifyListeners();
  }

  /// Hiện lại trình duyệt vừa dùng.
  void restore() {
    final id = _last ?? (_entries.isEmpty ? null : _entries.keys.last);
    if (id == null) return;
    _visible = _last = id;
    notifyListeners();
  }

  /// Đóng hẳn trình duyệt [id]: huỷ WebView và các tab.
  void close(String id) {
    _entries.remove(id);
    if (_visible == id) _visible = null;
    if (_last == id) _last = _entries.isEmpty ? null : _entries.keys.last;
    notifyListeners();
  }

  /// Trình duyệt báo số tab (cho nút nổi).
  void setTabs(String id, int n) {
    final e = _entries[id];
    if (e == null || e.tabs == n) return;
    e.tabs = n;
    if (_visible != id) notifyListeners();
  }
}

/// Lớp đặt trên toàn app (MaterialApp.builder): các trình duyệt đang mở (ẩn khi thu nhỏ) và nút nổi.
class BrowserDockLayer extends StatelessWidget {
  const BrowserDockLayer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dock = BrowserDock.instance;
    return ListenableBuilder(
      listenable: dock,
      builder: (context, _) {
        final visible = dock._visible;
        final last = dock._last == null ? null : dock._entries[dock._last];
        final tabs = dock._entries.values.fold<int>(0, (n, e) => n + e.tabs);
        return Stack(children: [
          child,
          for (final e in dock._entries.values)
            Positioned.fill(
              child: Offstage(
                offstage: visible != e.id,
                child: TickerMode(
                  enabled: visible == e.id,
                  child: ScaffoldMessenger(
                    key: e.messengerKey,
                    // Navigator riêng: hộp thoại, menu, hộp ký của trình duyệt nằm trong lớp này.
                    child: Navigator(
                      key: e.navigatorKey,
                      onGenerateRoute: (_) => PageRouteBuilder<void>(
                        pageBuilder: (_, _, _) => PopScope(
                          canPop: false,
                          // Nút Back của Android: thu nhỏ trình duyệt, không đóng.
                          onPopInvokedWithResult: (didPop, _) {
                            if (!didPop) dock.minimize();
                          },
                          child: e.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (visible == null && last != null)
            Positioned(
              right: 12,
              bottom: MediaQuery.paddingOf(context).bottom + 76,
              child: _DockPill(name: last.name, color: last.color, tabs: tabs, onTap: dock.restore),
            ),
        ]);
      },
    );
  }
}

class _DockPill extends StatelessWidget {
  const _DockPill({required this.name, required this.color, required this.tabs, required this.onTap});
  final String name;
  final Color color;
  final int tabs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final company = name.replaceFirst(RegExp(r'^Ký số\s*'), '');
    return Material(
      color: color,
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.draw_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text('Ký số · $tabs tab', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            if (company.isNotEmpty) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 90),
                child: Text(company, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
