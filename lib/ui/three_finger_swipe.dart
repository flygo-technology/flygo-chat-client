import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Vuốt 3 ngón từ dưới lên (điện thoại): gọi [onSwipe] một lần mỗi lần vuốt. Dùng để mở bảng chọn / thêm máy chủ.
/// Chỉ nghe con trỏ (Listener, không tranh cử chỉ), nên cuộn, chụm 2 ngón phóng to ảnh, chọn chữ vẫn chạy bình thường.
class ThreeFingerSwipe extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipe;

  /// Quãng đi lên tối thiểu của cả 3 ngón (điểm ảnh logic).
  final double distance;
  const ThreeFingerSwipe({super.key, required this.child, required this.onSwipe, this.distance = 70});

  @override
  State<ThreeFingerSwipe> createState() => _ThreeFingerSwipeState();
}

class _ThreeFingerSwipeState extends State<ThreeFingerSwipe> {
  final Map<int, Offset> _start = {};
  final Map<int, Offset> _now = {};
  bool _fired = false;

  void _end(PointerEvent e) {
    _start.remove(e.pointer);
    _now.remove(e.pointer);
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _start[e.pointer] = e.position;
          _now[e.pointer] = e.position;
          if (_start.length == 1) _fired = false;
        },
        onPointerMove: (e) {
          if (!_start.containsKey(e.pointer)) return;
          _now[e.pointer] = e.position;
          if (_fired || _start.length != 3) return;
          final dys = [for (final k in _start.keys) _now[k]!.dy - _start[k]!.dy];
          final dxs = [for (final k in _start.keys) (_now[k]!.dx - _start[k]!.dx).abs()];
          // Cả 3 ngón cùng đi lên đủ xa, lệch ngang ít.
          if (dys.every((d) => d < -widget.distance) && dxs.every((d) => d < 120)) {
            _fired = true;
            HapticFeedback.mediumImpact();
            widget.onSwipe();
          }
        },
        onPointerUp: _end,
        onPointerCancel: _end,
        child: widget.child,
      );
}
