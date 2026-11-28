import 'package:flutter/foundation.dart';

/// Liên kết mở mini app: `flygochat://app/<mã app>?org=<tổ chức>` (trang "App của tôi" của Flygo ID, 28/11), hoặc tin
/// `open_app` từ console nhúng. Giữ lại tới khi Trang chủ sẵn sàng (chưa đăng nhập thì đăng nhập xong mới mở).
class AppLink {
  static final pending = ValueNotifier<String?>(null);

  /// true nếu [u] là liên kết mở app (đã nhận).
  static bool handle(Uri u) {
    if (u.scheme != 'flygochat' || u.host != 'app') return false;
    final id = u.pathSegments.isEmpty ? '' : u.pathSegments.first;
    if (id.isEmpty) return false;
    open(id);
    return true;
  }

  static void open(String id) {
    // Gán lại cùng mã vẫn phải báo (bấm lại cùng app).
    pending.value = null;
    pending.value = id;
  }
}
