import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';

/// Phím bổ trợ để chọn nhiều tin bằng chuột: Cmd trên macOS, Ctrl trên Windows / Linux.
bool selectModifierPressed([TargetPlatform? platform]) {
  final kb = HardwareKeyboard.instance;
  return (platform ?? defaultTargetPlatform) == TargetPlatform.macOS ? kb.isMetaPressed : kb.isControlPressed;
}

/// Tin vừa được xử lý bằng Ctrl/Cmd/Shift+bấm (lúc nhấn chuột xuống): lần chạm (onTap) ngay sau đó của bong bóng tin
/// bỏ qua, kẻo vừa chọn đã bỏ chọn.
String? _handled;

/// Bong bóng gọi trước khi xử lý chạm thường: true = lần chạm này đã được Ctrl/Cmd/Shift+bấm xử lý rồi.
bool consumeSelectClick(String postId) {
  if (_handled != postId) return false;
  _handled = null;
  return true;
}

/// Máy tính: Ctrl+bấm (Cmd+bấm trên macOS) vào một tin bật chế độ chọn nhiều và chọn tin đó; bấm tiếp như vậy là
/// chọn / bỏ chọn. Shift+bấm (khi đang chọn ở chat này) chọn cả đoạn từ tin chọn trước tới tin này.
/// Dùng Listener (không tranh chạm với chữ / link bên trong tin).
class MultiSelectClick extends StatelessWidget {
  final MmPost post;
  final Widget child;
  final bool enabled;
  /// Các tin theo thứ tự hiển thị (cho Shift+bấm); null = tin của chat.
  final List<MmPost> Function()? ordered;
  const MultiSelectClick({super.key, required this.post, required this.child, this.enabled = true, this.ordered});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryMouseButton) return;
        if (post.sendState != SendState.sent || post.isSystem) return;
        final app = context.read<AppState>();
        final selecting = app.selectedChannel == post.channelId && app.selectedPosts.isNotEmpty;
        if (selectModifierPressed()) {
          _handled = post.id;
          app.toggleSelect(post);
        } else if (HardwareKeyboard.instance.isShiftPressed && selecting) {
          _handled = post.id;
          app.selectRange(post, ordered: ordered?.call());
        } else {
          _handled = null;
        }
      },
      child: child,
    );
  }
}

/// Đang chọn nhiều tin: Esc thoát chế độ chọn (đặt widget này trong thanh chọn, chỉ có mặt khi đang chọn).
class SelectionEscape extends StatefulWidget {
  final Widget child;
  const SelectionEscape({super.key, required this.child});
  @override
  State<SelectionEscape> createState() => _SelectionEscapeState();
}

class _SelectionEscapeState extends State<SelectionEscape> {
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return false;
    final app = context.read<AppState>();
    if (app.selectedPosts.isEmpty) return false;
    app.clearSelection();
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
