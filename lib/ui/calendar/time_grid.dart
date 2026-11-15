// Lịch: lưới giờ cho xem Ngày / 3 ngày / Tuần — đầu cột ngày (kèm ngày âm), hàng "cả ngày" có thanh nhiều ngày, sự kiện
// chồng giờ chia cột, vạch đỏ giờ hiện tại. Máy tính: kéo ô trống để chọn khoảng giờ, kéo sự kiện để dời, kéo mép dưới để
// đổi giờ kết thúc. Điện thoại: chạm ô trống để tạo, chạm sự kiện để xem.
import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'layout.dart';
import 'look.dart';
import 'lunar.dart';
import 'model.dart';
import 'store.dart';
import 'tz.dart';

const kHourH = 48.0;
const kGutter = 64.0;

class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.store,
    required this.days,
    required this.onTapEvent,
    required this.onCreate,
    required this.onMove,
    this.onDayTap,
    this.pending,
    this.wide = true,
  });

  final CalStore store;
  /// Các ngày đang xem (giờ tường, đầu ngày); có thể bỏ cuối tuần.
  final List<DateTime> days;
  final void Function(CEvent e, Rect anchor) onTapEvent;
  /// Chạm / kéo ô trống: tạo sự kiện [start, end) (cả ngày nếu [allDay]).
  final void Function(DateTime start, DateTime end, Rect anchor, bool allDay) onCreate;
  final void Function(CEvent e, DateTime start, DateTime end) onMove;
  final ValueChanged<DateTime>? onDayTap;
  /// Khoảng đang tạo (hiện khối "(Không có tiêu đề)").
  final (DateTime, DateTime)? pending;
  final bool wide;

  @override
  State<TimeGrid> createState() => TimeGridState();
}

class _Drag {
  _Drag(this.e, this.resize, this.start, this.end, this.origin);
  final CEvent e;
  final bool resize;
  final DateTime start, end;
  /// Chỗ bấm xuống (toạ độ màn hình); độ dời = vị trí hiện tại - chỗ này.
  final Offset origin;
  double dx = 0, dy = 0;
  void moveTo(Offset g) {
    dx = g.dx - origin.dx;
    dy = g.dy - origin.dy;
  }
}

class TimeGridState extends State<TimeGrid> {
  final _scroll = ScrollController(initialScrollOffset: 7 * kHourH - 8);
  final _body = GlobalKey();
  Timer? _tick;
  _Drag? _drag;
  (int, int, int)? _select; // ngày, phút đầu, phút cuối khi kéo chọn khoảng

  CalStore get store => widget.store;
  String get tz => store.tz;
  int get n => widget.days.length;

  @override
  void initState() {
    super.initState();
    // Vạch giờ hiện tại chạy theo phút.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStart());
  }

  void _scrollToStart() {
    if (!_scroll.hasClients) return;
    final work = CSettings.minutesOf(store.settings.workStart);
    final y = ((work - 60) / 60 * kHourH).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(y);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  int _dayIndex(DateTime d) => widget.days.indexWhere((x) => sameDay(x, d));

  // ------------------------------------------------------------ đầu cột
  Widget _header(BuildContext context) {
    final pal = Pal.of(context);
    final acc = calAccent(context);
    final lunar = store.settings.lunar;
    final today = store.today;
    if (n == 1 && !widget.wide) {
      // Điện thoại xem Ngày: đầu cột lệch trái như mockup.
      final d = widget.days.first;
      final on = sameDay(d, today);
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(children: [
          SizedBox(
            width: kGutter - 12,
            child: Column(children: [
              Text(dowHeader(d), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: on ? acc : pal.sub)),
              const SizedBox(height: 2),
              _dayCircle(context, d, on, 36, 18),
            ]),
          ),
          if (lunar) Text('${toLunar(d).short} ÂL', style: TextStyle(fontSize: 12, color: pal.sub)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: kGutter),
      child: Row(children: [
        for (final d in widget.days)
          Expanded(
            child: InkWell(
              onTap: widget.onDayTap == null ? null : () => widget.onDayTap!(d),
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Column(children: [
                  Text(dowHeader(d), style: TextStyle(fontSize: 11.5, letterSpacing: .3, fontWeight: FontWeight.w600, color: sameDay(d, today) ? acc : pal.sub)),
                  const SizedBox(height: 2),
                  _dayCircle(context, d, sameDay(d, today), widget.wide ? 44 : 34, widget.wide ? 24 : 18),
                  if (lunar) Text(toLunar(d).short, style: TextStyle(fontSize: 10.5, color: pal.sub)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _dayCircle(BuildContext context, DateTime d, bool today, double size, double font) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: today ? calAccent(context) : null, shape: BoxShape.circle),
        child: Text('${d.day}', style: TextStyle(fontSize: font, fontWeight: FontWeight.w500, color: today ? Colors.white : Pal.of(context).text)),
      );

  // ------------------------------------------------------------ hàng cả ngày
  Widget _allDayRow(BuildContext context, List<CEvent> evs) {
    final pal = Pal.of(context);
    final first = widget.days.first, last = addDays(widget.days.last, 1);
    final items = <(CEvent, int, int)>[];
    for (final e in evs.where((e) => e.showsAllDay(tz))) {
      final s = e.wallStart(tz), en = e.wallEnd(tz);
      if (!s.isBefore(last) || !en.isAfter(first)) continue;
      var f = widget.days.indexWhere((d) => addDays(d, 1).isAfter(s));
      var t = widget.days.lastIndexWhere((d) => d.isBefore(en));
      if (f < 0 || t < 0 || t < f) continue;
      f = f.clamp(0, n - 1);
      t = t.clamp(0, n - 1);
      items.add((e, f, t));
    }
    final bars = layoutBars(items);
    final rows = bars.isEmpty ? 0 : bars.map((b) => b.row).reduce((a, b) => a > b ? a : b) + 1;
    final h = rows == 0 ? 26.0 : rows * 24.0 + 6;
    return SizedBox(
      height: h,
      child: Row(children: [
        SizedBox(
          width: kGutter,
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(padding: const EdgeInsets.only(right: 8, top: 6), child: Text(gmtLabel(tzOffset(tz, msOfWall(first, tz))), style: TextStyle(fontSize: 10.5, color: pal.sub))),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth / n;
            return Stack(children: [
              Positioned.fill(
                child: Row(children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final box = context.findRenderObject() as RenderBox;
                          final o = box.localToGlobal(Offset(i * w, 0));
                          widget.onCreate(widget.days[i], addDays(widget.days[i], 1), o & Size(w, h), true);
                        },
                        child: Container(decoration: BoxDecoration(border: Border(left: BorderSide(color: calGrid(context))))),
                      ),
                    ),
                ]),
              ),
              for (final b in bars)
                Positioned(
                  left: b.from * w + 2,
                  width: (b.to - b.from + 1) * w - 5,
                  top: 3 + b.row * 24.0,
                  height: 21,
                  child: _bar(context, b.item),
                ),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _bar(BuildContext context, CEvent e) {
    final c = eventColor(store.colorOf(e), calDark(context));
    final pending = e.pendingInvite;
    return Builder(
      builder: (bc) => Material(
        color: pending ? Pal.of(context).bg : c,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: pending ? BorderSide(color: c, width: 1.2) : BorderSide.none),
        child: InkWell(
          key: ValueKey('ev-${e.instanceId}'),
          borderRadius: BorderRadius.circular(5),
          onTap: () => widget.onTapEvent(e, _rectOf(bc)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(e.busyOnly ? tr('Bận') : (e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pending ? c : Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  static Rect _rectOf(BuildContext c) {
    final box = c.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // ------------------------------------------------------------ lưới giờ
  int _snap(double y, int step, {bool up = false}) {
    final m = y / kHourH * 60;
    final v = up ? (m / step).ceil() * step : (m / step).floor() * step;
    return v.clamp(0, 24 * 60);
  }

  void _tapEmpty(TapUpDetails d, double colW) {
    final i = (d.localPosition.dx / colW).floor().clamp(0, n - 1);
    final m = _snap(d.localPosition.dy, 30);
    final start = widget.days[i].add(Duration(minutes: m));
    final end = start.add(Duration(minutes: store.settings.defaultDuration));
    widget.onCreate(start, end, _slotRect(i, m, end.difference(start).inMinutes, colW), false);
  }

  Rect _slotRect(int i, int m, int len, double colW) {
    final box = _body.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Rect.zero;
    return box.localToGlobal(Offset(i * colW, m / 60 * kHourH)) & Size(colW, len / 60 * kHourH);
  }

  void _selStart(DragStartDetails d, double colW) {
    final i = (d.localPosition.dx / colW).floor().clamp(0, n - 1);
    final m = _snap(d.localPosition.dy, 15);
    setState(() => _select = (i, m, m + 15));
  }

  void _selUpdate(DragUpdateDetails d) {
    final s = _select;
    if (s == null) return;
    final m = _snap(d.localPosition.dy, 15, up: true);
    setState(() => _select = (s.$1, s.$2, m <= s.$2 ? s.$2 + 15 : m));
  }

  void _selEnd(double colW) {
    final s = _select;
    if (s == null) return;
    final start = widget.days[s.$1].add(Duration(minutes: s.$2));
    final end = widget.days[s.$1].add(Duration(minutes: s.$3));
    widget.onCreate(start, end, _slotRect(s.$1, s.$2, s.$3 - s.$2, colW), false);
    setState(() => _select = null);
  }

  (DateTime, DateTime) _dragged(_Drag d, double colW) {
    final dm = (d.dy / kHourH * 60 / 15).round() * 15;
    if (d.resize) {
      var end = d.end.add(Duration(minutes: dm));
      if (end.difference(d.start).inMinutes < 15) end = d.start.add(const Duration(minutes: 15));
      return (d.start, end);
    }
    final dd = (d.dx / colW).round();
    final shift = Duration(days: dd, minutes: dm);
    return (d.start.add(shift), d.end.add(shift));
  }

  void _dragEnd(double colW) {
    final d = _drag;
    if (d == null) return;
    final (s, e) = _dragged(d, colW);
    setState(() => _drag = null);
    if (s != d.start || e != d.end) widget.onMove(d.e, s, e);
  }

  Widget _block(BuildContext context, CEvent e, DateTime s, DateTime en, {bool ghost = false, double colW = 100}) {
    final pal = Pal.of(context);
    final dark = calDark(context);
    final c = eventColor(store.colorOf(e), dark);
    final pending = e.pendingInvite;
    final declined = e.declined;
    final mins = en.difference(s).inMinutes;
    final fg = pending ? pal.text : declined ? c : Colors.white;
    final title = e.busyOnly ? tr('Bận') : (e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title);
    final sub = [
      '${hm(s)} – ${hm(en)}',
      if (e.location.isNotEmpty && !e.busyOnly) e.location,
      if (pending) tr('Lời mời · chưa trả lời'),
    ].join(' · ');
    final deco = TextDecoration.combine([if (declined) TextDecoration.lineThrough]);
    final short = mins < 40;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(6, short ? 1 : 3, 4, 1),
      child: short
          ? Text.rich(
              TextSpan(children: [
                if (e.conference != null) WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.videocam_outlined, size: 13, color: fg)),
                TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (e.recurring) WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.only(left: 3), child: Icon(Icons.sync_rounded, size: 12, color: fg))),
                TextSpan(text: mins >= 45 ? '\n${hm(s)} – ${hm(en)}' : ', ${hm(s)}', style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 11)),
              ]),
              maxLines: mins >= 25 ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.2, color: fg, decoration: deco),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  if (e.conference != null) WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.videocam_outlined, size: 13, color: fg)),
                  TextSpan(text: title),
                  if (e.recurring) WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: const EdgeInsets.only(left: 3), child: Icon(Icons.sync_rounded, size: 12, color: fg))),
                ]),
                maxLines: mins >= 90 ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.25, fontWeight: FontWeight.w600, color: fg, decoration: deco),
              ),
              Flexible(child: Text(sub, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, height: 1.25, color: fg.withValues(alpha: .92), decoration: deco))),
            ]),
    );
    return Builder(builder: (bc) {
      final box = Container(
        decoration: BoxDecoration(
          color: pending ? pal.bg : declined ? c.withValues(alpha: dark ? .22 : .16) : c.withValues(alpha: ghost ? .85 : 1),
          borderRadius: BorderRadius.circular(5),
          border: pending ? Border.all(color: c, width: 1.2) : Border.all(color: pal.bg.withValues(alpha: .9), width: .8),
          boxShadow: ghost ? [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 10, offset: const Offset(0, 3))] : null,
        ),
        clipBehavior: Clip.hardEdge,
        child: content,
      );
      if (ghost) return box;
      final canDrag = widget.wide && e.canEdit && !e.busyOnly;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('ev-${e.instanceId}'),
          dragStartBehavior: DragStartBehavior.down,
          onTap: () => widget.onTapEvent(e, _rectOf(bc)),
          onPanStart: canDrag ? (d) => setState(() => _drag = _Drag(e, false, s, en, d.globalPosition)) : null,
          onPanUpdate: canDrag ? (d) => setState(() => _drag?.moveTo(d.globalPosition)) : null,
          onPanEnd: canDrag ? (_) => _dragEnd(colW) : null,
          child: Stack(children: [
            Positioned.fill(child: box),
            if (canDrag)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 6,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    key: ValueKey('resize-${e.instanceId}'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: (d) => setState(() => _drag = _Drag(e, true, s, en, d.globalPosition)),
                    onPanUpdate: (d) => setState(() => _drag?.moveTo(d.globalPosition)),
                    onPanEnd: (_) => _dragEnd(colW),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }

  Widget _body0(BuildContext context, List<CEvent> evs) {
    final pal = Pal.of(context);
    final now = store.nowWall;
    return LayoutBuilder(builder: (context, c) {
      final colW = c.maxWidth / n;
      final children = <Widget>[];
      for (var i = 0; i < n; i++) {
        final d = widget.days[i];
        final next = addDays(d, 1);
        final items = <(CEvent, int, int)>[];
        for (final e in evs) {
          if (e.showsAllDay(tz)) continue;
          final s = e.wallStart(tz), en = e.wallEnd(tz);
          if (!s.isBefore(next) || (!en.isAfter(d) && s != en)) continue;
          final sm = s.isBefore(d) ? 0 : s.difference(d).inMinutes;
          final em = en.isAfter(next) ? 24 * 60 : en.difference(d).inMinutes;
          items.add((e, sm, em));
        }
        for (final p in layoutDay(items)) {
          final dragging = _drag != null && _drag!.e.instanceId == p.item.instanceId;
          final top = p.start / 60 * kHourH;
          final h = ((p.end - p.start).clamp(20, 24 * 60) / 60 * kHourH) - 1;
          final w = colW - 6;
          // Cột cuối của cụm rộng hơn một chút để chữ dễ đọc (chồng lên cột trước như mockup).
          final left = i * colW + w * p.col / p.cols;
          final width = w * p.span / p.cols + (p.cols > 1 && p.col + p.span < p.cols ? w * .12 : 0);
          children.add(Positioned(
            left: left + 2,
            top: top,
            width: width.clamp(12.0, colW),
            height: h,
            child: Opacity(opacity: dragging ? .45 : 1, child: _block(context, p.item, p.item.wallStart(tz), p.item.wallEnd(tz), colW: colW)),
          ));
        }
      }
      // Khối đang kéo.
      final dr = _drag;
      if (dr != null) {
        final (s, e) = _dragged(dr, colW);
        final i = _dayIndex(s);
        if (i >= 0) {
          children.add(Positioned(
            left: i * colW + 2,
            top: (s.hour * 60 + s.minute) / 60 * kHourH,
            width: colW - 6,
            height: (e.difference(s).inMinutes / 60 * kHourH - 1).clamp(16.0, 24 * kHourH),
            child: IgnorePointer(child: _block(context, dr.e, s, e, ghost: true)),
          ));
        }
      }
      // Khoảng đang chọn / đang tạo.
      (int, int, int)? sel = _select;
      final p = widget.pending;
      if (sel == null && p != null && !p.$2.difference(p.$1).isNegative && sameDay(p.$1, p.$2.subtract(const Duration(minutes: 1)))) {
        final i = _dayIndex(p.$1);
        if (i >= 0) sel = (i, p.$1.hour * 60 + p.$1.minute, p.$1.hour * 60 + p.$1.minute + p.$2.difference(p.$1).inMinutes);
      }
      if (sel != null) {
        final d = widget.days[sel.$1];
        final s = d.add(Duration(minutes: sel.$2)), e = d.add(Duration(minutes: sel.$3));
        children.add(Positioned(
          left: sel.$1 * colW + 2,
          top: sel.$2 / 60 * kHourH,
          width: colW - 6,
          height: (sel.$3 - sel.$2) / 60 * kHourH - 1,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 2),
              decoration: BoxDecoration(color: calAccent(context), borderRadius: BorderRadius.circular(5), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))]),
              child: Text('${tr('(Không có tiêu đề)')}\n${hm(s)} – ${hm(e)}',
                  maxLines: 2, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 12, height: 1.3, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ));
      }
      // Vạch giờ hiện tại.
      final ti = _dayIndex(now);
      if (ti >= 0) {
        final y = (now.hour * 60 + now.minute) / 60 * kHourH;
        children.add(Positioned(left: ti * colW, width: colW, top: y - 1, height: 2, child: const IgnorePointer(child: ColoredBox(color: kNowRed))));
        children.add(Positioned(
            left: ti * colW - 6, top: y - 6, width: 12, height: 12, child: const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(color: kNowRed, shape: BoxShape.circle)))));
      }
      return Stack(key: _body, clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (d) => _tapEmpty(d, colW),
            onPanStart: widget.wide ? (d) => _selStart(d, colW) : null,
            onPanUpdate: widget.wide ? _selUpdate : null,
            onPanEnd: widget.wide ? (_) => _selEnd(colW) : null,
            child: CustomPaint(painter: _GridPainter(n, calGrid(context), pal.divider)),
          ),
        ),
        ...children,
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final from = widget.days.first, to = addDays(widget.days.last, 1);
    final evs = store.eventsIn(from, to);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(context),
      _allDayRow(context, evs),
      Divider(height: 1, thickness: 1, color: pal.divider),
      Expanded(
        child: SingleChildScrollView(
          controller: _scroll,
          child: SizedBox(
            height: 24 * kHourH + 12,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: kGutter,
                  height: 24 * kHourH,
                  child: Stack(clipBehavior: Clip.none, children: [
                    for (var h = 1; h < 24; h++)
                      Positioned(
                        top: h * kHourH - 7,
                        right: 10,
                        child: Text('$h:00', style: TextStyle(fontSize: 10.5, color: pal.sub)),
                      ),
                  ]),
                ),
                Expanded(child: SizedBox(height: 24 * kHourH, child: _body0(context, evs))),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.n, this.grid, this.strong);
  final int n;
  final Color grid, strong;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var h = 1; h < 24; h++) {
      canvas.drawLine(Offset(0, h * kHourH), Offset(size.width, h * kHourH), p);
    }
    final w = size.width / n;
    for (var i = 0; i < n; i++) {
      canvas.drawLine(Offset(i * w, 0), Offset(i * w, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => o.n != n || o.grid != grid;
}
