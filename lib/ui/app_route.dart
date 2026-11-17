import 'package:flutter/material.dart';

import '../config.dart' show isDesktop;
import '../i18n/i18n.dart';

/// Trang mở bằng nút trên máy tính: hiện dạng hộp nổi giữa cửa sổ (nền mờ phía sau), không che kín màn hình.
///
/// Chỉ khi trang được đẩy lên navigator gốc của cửa sổ rộng (máy tính). Trang mở trong một cột / ô / tab (navigator
/// lồng) và điện thoại vẫn mở như [MaterialPageRoute]. Nháy ra ngoài hộp hoặc Esc để đóng.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({required super.builder, super.settings, super.maintainState, super.fullscreenDialog});

  bool? _modalCache;

  bool get _modal {
    final cached = _modalCache;
    if (cached != null) return cached;
    final nav = navigator;
    if (!isDesktop || nav == null) return false;
    // Navigator gốc: không có navigator nào bọc ngoài.
    final root = nav.context.findRootAncestorStateOfType<NavigatorState>() == null;
    final wide = MediaQuery.maybeSizeOf(nav.context)?.width ?? 0;
    return _modalCache = root && wide >= 860;
  }

  @override
  bool get opaque => !_modal;

  /// Trang phía sau đứng yên (không trượt / mờ đi như khi mở trang mới toàn màn hình).
  @override
  bool get fullscreenDialog => _modal || super.fullscreenDialog;

  @override
  Color? get barrierColor => _modal ? Colors.black.withValues(alpha: .45) : null;

  @override
  bool get barrierDismissible => _modal;

  @override
  String? get barrierLabel => _modal ? tr('Đóng') : null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final page = super.buildPage(context, animation, secondaryAnimation);
    if (!_modal) return page;
    final size = MediaQuery.sizeOf(context);
    final w = (size.width * .82).clamp(0.0, 980.0);
    final h = (size.height * .9).clamp(0.0, 1100.0);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: w, maxHeight: h),
        child: Material(
          elevation: 24,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(18),
          // Trang bên trong tính kích thước theo hộp, không theo cả cửa sổ.
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(w, h), padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
            child: page,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (!_modal) return super.buildTransitions(context, animation, secondaryAnimation, child);
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(curved), child: child),
    );
  }
}

/// Trang gốc của một ứng dụng (Drive, Thư, Wiki, Báo cáo…): không có nút quay lại / đóng trên thanh trên cùng (Sếp,
/// 2026-11-17). Điện thoại quay lại bằng nút / cử chỉ của máy, máy tính đóng tab. Trang con mở từ đây (chi tiết →
/// danh sách) vẫn có nút quay lại như thường.
class AppHomeRoute<T> extends AppPageRoute<T> {
  AppHomeRoute({required super.builder, super.settings});

  @override
  bool get impliesAppBarDismissal => false;
}

/// Thanh trên cùng tự vẽ của một trang có nên hiện nút quay lại / đóng không: false ở trang gốc ứng dụng ([AppHomeRoute])
/// và trang đầu của một tab. Dùng thay cho `Navigator.canPop()`.
bool showsBack(BuildContext context) => ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
