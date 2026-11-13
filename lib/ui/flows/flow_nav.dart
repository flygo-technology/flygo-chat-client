import 'package:flutter/material.dart';

import '../home_page.dart' show ChatHost, PageCloser;
import 'package:flygo_chat/ui/app_route.dart';

/// Mở một trang của Quy trình. Máy tính: ở vùng giữa (không chiếm toàn màn hình); đang ở trong một trang Quy trình
/// thì mở chồng trong vùng đó. Điện thoại: toàn màn hình như trước.
Future<T?> openFlowPage<T>(BuildContext context, String key, WidgetBuilder builder) async {
  if (PageCloser.of(context) != null) return Navigator.of(context).push<T>(AppPageRoute(builder: builder));
  final host = ChatHost.of(context);
  if (host?.openPage != null) {
    host!.openPage!(key, builder);
    return null;
  }
  return Navigator.of(context, rootNavigator: true).push<T>(AppPageRoute(builder: builder));
}

/// Nút ở đầu thanh tiêu đề: trang mở ở vùng giữa (máy tính) thì nút đóng; trang là gốc của một khung điều hướng lồng
/// (điện thoại, Sếp 12/11: mở tiến trình không có nút quay lại) thì nút quay lại của khung ngoài; còn lại để AppBar tự
/// hiện nút quay lại.
Widget? flowLeading(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) return null;
  final closer = PageCloser.of(context);
  if (closer != null) return IconButton(tooltip: 'Đóng', onPressed: closer.onClose, icon: const Icon(Icons.close_rounded));
  final root = Navigator.of(context, rootNavigator: true);
  if (root != nav && root.canPop()) return BackButton(onPressed: () => root.maybePop());
  return null;
}

/// Khung cài đặt ở cột phải (máy tính); null nếu không có (điện thoại: dùng bảng trượt).
void Function(String key, WidgetBuilder? builder)? flowSidePanel(BuildContext context) => ChatHost.of(context)?.openSidePage;

/// Màn rộng (máy tính): cùng ngưỡng với bố cục nhiều cột của màn hình chính.
bool flowWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 860;

/// Đổi khi có thao tác làm thay đổi luồng (tạo, duyệt, nộp...): các danh sách tự tải lại.
final flowsChanged = ValueNotifier<int>(0);
