import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';

/// Vạch ngăn cột kéo được (máy tính): rê chuột hiện con trỏ đổi cỡ, kéo ngang để đổi độ rộng ([onDrag] nhận độ dời),
/// thả thì [onDragEnd] (lưu lại), bấm đúp để về độ rộng mặc định ([onReset]). Vùng bắt chuột rộng 8px, vạch hiện 1px.
class ColumnResizer extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;
  const ColumnResizer({super.key, required this.onDrag, required this.onDragEnd, required this.onReset});
  @override
  State<ColumnResizer> createState() => _ColumnResizerState();
}

class _ColumnResizerState extends State<ColumnResizer> {
  bool _hot = false;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: Tooltip(
        message: tr('Kéo để đổi độ rộng, bấm đúp để về mặc định'),
        waitDuration: const Duration(seconds: 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _hot = true),
          onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) {
            setState(() => _hot = false);
            widget.onDragEnd();
          },
          onDoubleTap: widget.onReset,
          child: SizedBox(
            width: 8,
            child: Center(child: Container(width: _hot ? 3 : 1, color: _hot ? pal.accent : pal.divider)),
          ),
        ),
      ),
    );
  }
}
