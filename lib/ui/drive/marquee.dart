// Drive: kéo chuột để quét chọn nhiều mục (khung chữ nhật như Google Drive / trình quản lý tệp).
// Chỉ chuột (cảm ứng vẫn cuộn như thường). Giữ Ctrl / ⌘ khi kéo để thêm vào lựa chọn đang có.
// Kéo sát mép trên / dưới thì tự cuộn; mục đã cuộn khuất giữ nguyên trạng thái lúc còn thấy.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DriveMarquee extends StatefulWidget {
  const DriveMarquee({
    super.key,
    required this.child,
    required this.keys,
    required this.selected,
    required this.onSelect,
    required this.onBlankClick,
    this.controller,
    required this.color,
  });

  final Widget child;
  /// Khoá của từng mục đang hiện (đường dẫn → khoá của ô / dòng).
  final Map<String, GlobalKey> keys;
  final Set<String> Function() selected;
  final void Function(Set<String> sel) onSelect;
  /// Bấm vào chỗ trống (không kéo, không trúng mục nào).
  final VoidCallback onBlankClick;
  final ScrollController? controller;
  final Color color;

  /// Vừa kết thúc một lần kéo quét: bỏ qua cú bấm đi kèm (InkWell vẫn có thể nhận onTap khi chuột nhả).
  static bool get justDragged => _justDragged;
  static bool _justDragged = false;

  @override
  State<DriveMarquee> createState() => _DriveMarqueeState();
}

class _DriveMarqueeState extends State<DriveMarquee> {
  int? _pointer;
  Offset? _start; // toạ độ trong widget, tính cả phần đã cuộn lúc bắt đầu (y + offset)
  Offset? _now; // toạ độ trong widget
  bool _active = false;
  Set<String> _base = {}, _cur = {};
  Timer? _edge;

  double get _off => (widget.controller?.hasClients ?? false) ? widget.controller!.offset : 0;

  @override
  void dispose() {
    _edge?.cancel();
    super.dispose();
  }

  RenderBox? get _box => context.findRenderObject() as RenderBox?;

  Rect? get _rect {
    final s = _start, n = _now;
    if (s == null || n == null) return null;
    return Rect.fromPoints(Offset(s.dx, s.dy - _off), n);
  }

  bool _onItem(Offset global) {
    for (final k in widget.keys.values) {
      final b = k.currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.attached) continue;
      if ((b.localToGlobal(Offset.zero) & b.size).contains(global)) return true;
    }
    return false;
  }

  void _down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryMouseButton) return;
    _pointer = e.pointer;
    _start = Offset(e.localPosition.dx, e.localPosition.dy + _off);
    _now = e.localPosition;
    _active = false;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _start == null) return;
    _now = e.localPosition;
    if (!_active) {
      if ((Offset(_start!.dx, _start!.dy - _off) - _now!).distance < 8) return;
      final k = HardwareKeyboard.instance;
      _active = true;
      _base = k.isControlPressed || k.isMetaPressed ? {...widget.selected()} : {};
      _cur = {..._base};
    }
    _update();
    _autoScroll();
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    final was = _active;
    if (!was && e is PointerUpEvent && !_onItem(e.position)) {
      final k = HardwareKeyboard.instance;
      if (!k.isControlPressed && !k.isMetaPressed && !k.isShiftPressed) widget.onBlankClick();
    }
    _edge?.cancel();
    _edge = null;
    setState(() {
      _pointer = null;
      _start = _now = null;
      _active = false;
    });
    if (was) {
      DriveMarquee._justDragged = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => DriveMarquee._justDragged = false);
    }
  }

  void _update() {
    final box = _box, r = _rect;
    if (box == null || r == null) return;
    final g = Rect.fromPoints(box.localToGlobal(r.topLeft), box.localToGlobal(r.bottomRight));
    final next = {..._cur};
    widget.keys.forEach((path, k) {
      final b = k.currentContext?.findRenderObject() as RenderBox?;
      if (b == null || !b.attached || !b.hasSize) return;
      final hit = (b.localToGlobal(Offset.zero) & b.size).overlaps(g);
      if (hit) {
        next.add(path);
      } else if (!_base.contains(path)) {
        next.remove(path);
      }
    });
    _cur = next;
    widget.onSelect(next);
    setState(() {});
  }

  void _autoScroll() {
    final c = widget.controller, box = _box, n = _now;
    if (c == null || !c.hasClients || box == null || n == null) return;
    const zone = 28.0;
    final dir = n.dy < zone ? -1 : (n.dy > box.size.height - zone ? 1 : 0);
    if (dir == 0) {
      _edge?.cancel();
      _edge = null;
      return;
    }
    _edge ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      final p = c.position, now = _now;
      if (!_active || now == null) return;
      final d = now.dy < zone ? -1 : (now.dy > (_box?.size.height ?? 0) - zone ? 1 : 0);
      if (d == 0) return;
      final to = (c.offset + d * 18).clamp(p.minScrollExtent, p.maxScrollExtent);
      if (to == c.offset) return;
      c.jumpTo(to);
      WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _active ? _rect : null;
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Stack(children: [
        widget.child,
        if (r != null)
          Positioned.fromRect(
            rect: r,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: .12),
                  border: Border.all(color: widget.color.withValues(alpha: .7)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
