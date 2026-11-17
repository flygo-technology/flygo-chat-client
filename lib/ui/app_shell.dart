import 'package:flutter/material.dart';

import '../config.dart' show isDesktop;
import 'app_route.dart';
import 'desk_tabs.dart';

/// Mở trang gốc một ứng dụng cho đúng chỗ (Sếp, 2026-11-17):
/// - máy tính: luôn ở tab riêng của ứng dụng (đã mở thì chuyển sang tab đó), từ bất cứ đâu (ô Trang chủ, tìm kiếm, link);
///   riêng tab Trang chủ vừa mở từ ô ứng dụng thì ứng dụng mở ngay trong tab đó;
/// - điện thoại / cửa sổ hẹp: một trang [AppHomeRoute] (không có nút quay lại).
///
/// Gọi [AppHost.of] trước mọi `await` (giữ navigator, tab của nơi bấm), rồi [open] khi đã sẵn sàng.
class AppHost {
  final NavigatorState nav;
  final DeskTabScope? tab;
  AppHost._(this.nav, this.tab);

  factory AppHost.of(BuildContext context, {bool rootNavigator = false}) {
    final tab = DeskTabScope.of(context);
    return AppHost._(Navigator.of(context, rootNavigator: rootNavigator && tab == null), tab);
  }

  /// Mở trong chính tab này: tab Trang chủ / tab ứng dụng chưa mở gì chồng lên.
  bool get _inThisTab => tab?.onApp != null && !nav.canPop();

  Future<void> open({required String key, required String title, required WidgetBuilder builder, bool deep = false}) async {
    final r = AppTabRequest(key: key, title: title, builder: builder, deep: deep);
    final hook = appTabHook;
    if (isDesktop && hook != null && !_inThisTab && hook(r)) return;
    final inTab = _inThisTab;
    if (inTab && tab!.onApp!(r)) return;
    tab?.onTitle?.call(title);
    // Máy tính ngoài tab (cửa sổ hẹp, cửa sổ riêng): không có nút quay lại của máy nên giữ nút đóng như trang thường.
    await nav.push(!isDesktop || inTab ? AppHomeRoute(builder: builder) : AppPageRoute(builder: builder));
    tab?.onTitle?.call(null);
  }
}
