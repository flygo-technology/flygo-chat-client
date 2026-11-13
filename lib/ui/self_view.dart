import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// Hình nhỏ nổi trong cuộc gọi video (thường là camera của mình): kéo đi khắp màn hình, thả ra thì dạt về mép trái /
/// phải gần nhất. Có [onRemove]: lúc kéo hiện nút xoá ở đáy màn hình, thả hình vào đó là gọi [onRemove] (tắt camera).
/// Đặt trực tiếp trong một Stack (tự chiếm cả vùng, chỗ trống không chặn bấm của lớp dưới).
class DraggablePip extends StatefulWidget {
  final double width;
  final double height;
  /// Khoảng chừa ở đáy khi đứng yên (thanh nút của cuộc gọi).
  final double bottomGap;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  const DraggablePip({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.bottomGap = 12,
    this.onTap,
    this.onRemove,
  });

  @override
  State<DraggablePip> createState() => _DraggablePipState();
}

class _DraggablePipState extends State<DraggablePip> {
  static const _margin = 12.0;
  static const _target = 68.0;
  Offset? _pos;
  bool _dragging = false;
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(builder: (context, box) {
        final w = widget.width, h = widget.height;
        final maxX = (box.maxWidth - w - _margin).clamp(_margin, double.infinity);
        // Đang kéo: xuống được tới đáy (chỗ nút xoá); đứng yên thì nằm trên thanh nút.
        final maxYDrag = (box.maxHeight - h - _margin).clamp(_margin, double.infinity);
        final maxYRest = (box.maxHeight - h - widget.bottomGap).clamp(_margin, double.infinity);
        final p0 = _pos ?? Offset(maxX, maxYRest);
        final pos = Offset(p0.dx.clamp(_margin, maxX), p0.dy.clamp(_margin, _dragging ? maxYDrag : maxYRest));
        final target = Offset(box.maxWidth / 2, box.maxHeight - 28 - _target / 2);
        bool near(Offset p) => (Offset(p.dx + w / 2, p.dy + h / 2) - target).distance < 110 ||
            (p.dy + h > box.maxHeight - 40 && (p.dx + w / 2 - target.dx).abs() < w);
        final removable = widget.onRemove != null;
        return Stack(children: [
          if (_dragging && removable)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: IgnorePointer(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  AnimatedScale(
                    scale: _hot ? 1.2 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: _target,
                      height: _target,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hot ? const Color(0xFFEA4335) : Colors.black54,
                        border: Border.all(color: Colors.white70, width: 2),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 34),
                    ),
                  ),
                ]),
              ),
            ),
          if (_dragging && removable)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28 + _target + 10,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                    child: Text(tr('Thả vào đây để tắt camera'), style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: pos.dx,
            top: pos.dy,
            width: w,
            height: h,
            child: GestureDetector(
              onTap: widget.onTap,
              onPanStart: (_) => setState(() => _dragging = true),
              onPanUpdate: (u) => setState(() {
                _pos = Offset((pos.dx + u.delta.dx).clamp(_margin, maxX), (pos.dy + u.delta.dy).clamp(_margin, maxYDrag));
                _hot = removable && near(_pos!);
              }),
              onPanEnd: (_) {
                final remove = _hot;
                setState(() {
                  _dragging = false;
                  _hot = false;
                  // Thả ra: dạt về mép gần nhất, không nằm đè thanh nút.
                  _pos = remove ? null : Offset(pos.dx + w / 2 < box.maxWidth / 2 ? _margin : maxX, pos.dy.clamp(_margin, maxYRest));
                });
                if (remove) widget.onRemove?.call();
              },
              child: AnimatedOpacity(
                opacity: _hot ? .6 : 1,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}
