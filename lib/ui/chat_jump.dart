import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'theme.dart';

/// Đã cuộn lên xem tin cũ (hiện nút tua xuống cuối + nút chọn ngày): cách tin mới nhất hơn 600 px,
/// hoặc đang xem cửa sổ tin cũ (tua tới ngày) chưa nối với tin mới nhất.
bool chatScrolledUp({required double pixels, required double minExtent, bool inWindow = false}) =>
    inWindow || pixels - minExtent > 600;

/// Hai nút tròn nổi cạnh nhau ở góc dưới bên phải khung chat khi đã cuộn lên: chọn ngày, rồi tua xuống tin mới nhất.
class ChatJumpButtons extends StatelessWidget {
  final bool visible;
  final bool busy;
  final VoidCallback onPickDate;
  final VoidCallback onDown;
  const ChatJumpButtons({super.key, required this.visible, required this.onPickDate, required this.onDown, this.busy = false});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final pal = Pal.of(context);
    Widget round(Widget icon, String tip, VoidCallback? onTap, Key key) => Tooltip(
          message: tip,
          child: Material(
            key: key,
            color: pal.surface,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 44, height: 44, child: Center(child: icon)),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      round(
        busy
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: pal.text))
            : Icon(Icons.calendar_month_rounded, color: pal.text),
        tr('Tua tới ngày'),
        busy ? null : onPickDate,
        const ValueKey('chat-jump-date'),
      ),
      const SizedBox(width: 10),
      round(Icon(Icons.keyboard_double_arrow_down_rounded, color: pal.text), tr('Tin mới nhất'), onDown,
          const ValueKey('chat-jump-down')),
    ]);
  }
}

/// Hộp chọn ngày để tua tới: không chọn được ngày tương lai, ngày trước khi tạo cuộc trò chuyện ([createdAt] ms, 0 = không rõ).
Future<DateTime?> pickJumpDate(BuildContext context, {required int createdAt, DateTime? initial, DateTime? now}) {
  final n = now ?? DateTime.now();
  final last = DateTime(n.year, n.month, n.day);
  final c = createdAt > 0 ? DateTime.fromMillisecondsSinceEpoch(createdAt) : DateTime(2000);
  var first = DateTime(c.year, c.month, c.day);
  if (first.isAfter(last)) first = last;
  var init = initial == null ? last : DateTime(initial.year, initial.month, initial.day);
  if (init.isBefore(first)) init = first;
  if (init.isAfter(last)) init = last;
  return showDatePicker(
    context: context,
    initialDate: init,
    firstDate: first,
    lastDate: last,
    helpText: tr('Tua tới ngày'),
    confirmText: tr('Tới ngày này'),
    cancelText: tr('Hủy'),
  );
}
