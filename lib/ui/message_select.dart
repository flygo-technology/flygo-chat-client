import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';

/// Chọn chữ trong một tin nhắn.
/// - Máy tính: kéo chuột để chọn (giữ Shift để không bị tính là vuốt), Ctrl/⌘+C sao chép; nháy phải mở menu thao tác
///   của tin ([onMore]) thay cho menu chọn chữ.
/// - Điện thoại: bình thường KHÔNG bọc vùng chọn, vì vùng chọn bắt mọi cú kéo ngang bằng tay (vuốt trả lời / ghi chú
///   sẽ hỏng). Bấm giữ vào chữ mới bật vùng chọn và chọn cả đoạn (có tay kéo để thu hẹp); thanh công cụ có Sao chép,
///   "Thao tác khác" (menu của tin: cảm xúc, trả lời, chuyển tiếp...) và Chọn tất cả. Bỏ chọn là tin vuốt lại được.
///   Bấm giữ phần bong bóng ngoài chữ vẫn mở menu như cũ.
class MessageTextSelection extends StatefulWidget {
  final Widget child;
  final bool desktop;
  final VoidCallback onMore;
  const MessageTextSelection({super.key, required this.child, required this.desktop, required this.onMore});

  @override
  State<MessageTextSelection> createState() => _MessageTextSelectionState();
}

class _MessageTextSelectionState extends State<MessageTextSelection> {
  final _area = GlobalKey<SelectionAreaState>();
  bool _selecting = false;
  bool _hadSelection = false;

  void _start() {
    setState(() {
      _selecting = true;
      _hadSelection = false;
    });
    // Vùng chọn vừa dựng: chữ bên trong đăng ký với vùng chọn sau khung hình đầu, nên chọn ở khung hình kế tiếp.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        HapticFeedback.selectionClick();
        _area.currentState?.selectableRegion.selectAll(SelectionChangedCause.toolbar);
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  void _changed(SelectedContent? c) {
    if (widget.desktop) return;
    if (c != null && c.plainText.isNotEmpty) {
      _hadSelection = true;
    } else if (_hadSelection && _selecting) {
      // Bỏ chọn (chạm ra ngoài, Sao chép, Thao tác khác): tắt vùng chọn để vuốt lại được.
      setState(() => _selecting = false);
    }
  }

  Widget _selectionArea() => SelectionArea(
        key: _area,
        onSelectionChanged: _changed,
        contextMenuBuilder: (ctx, region) {
          if (widget.desktop) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              region.hideToolbar();
              widget.onMore();
            });
            return const SizedBox.shrink();
          }
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: region.contextMenuAnchors,
            // "Thao tác khác" ngay sau Sao chép để không bị dồn vào nút ⋮ trên màn hẹp.
            buttonItems: [
              ...region.contextMenuButtonItems.where((b) => b.type == ContextMenuButtonType.copy),
              ContextMenuButtonItem(
                label: tr('Thao tác khác'),
                onPressed: () {
                  region.clearSelection();
                  widget.onMore();
                },
              ),
              ...region.contextMenuButtonItems.where((b) => b.type != ContextMenuButtonType.copy),
            ],
          );
        },
        child: widget.child,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.desktop) return _selectionArea();
    if (_selecting) {
      // Điện thoại: vùng chọn không tự bỏ chọn khi chạm ra ngoài; chạm ra ngoài (trừ tay kéo / thanh công cụ, cùng
      // nhóm SelectableRegion) thì bỏ chọn và trở về tin thường.
      return TapRegion(
        groupId: SelectableRegion,
        onTapOutside: (_) {
          _area.currentState?.selectableRegion.clearSelection();
          if (mounted) setState(() => _selecting = false);
        },
        child: _selectionArea(),
      );
    }
    return GestureDetector(onLongPress: _start, child: widget.child);
  }
}

/// Kéo ngang trên tin (vuốt để trả lời / ghi chú). Đang giữ Shift thì không nhận, để kéo chuột chọn chữ trong tin.
class SwipeDragRecognizer extends HorizontalDragGestureRecognizer {
  SwipeDragRecognizer({super.debugOwner});

  @override
  bool isPointerAllowed(PointerEvent event) => !HardwareKeyboard.instance.isShiftPressed && super.isPointerAllowed(event);
}
