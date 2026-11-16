// TeamWork: Gantt — thanh từ ngày bắt đầu tới hạn, tô % xong; việc cha có việc con gập / mở được; mũi tên phụ thuộc
// (việc chặn → việc bị chặn); việc chỉ có hạn là mốc (hình thoi); vạch hôm nay. Kéo thanh để dời, kéo hai đầu để đổi độ
// dài: thả ra thì hỏi có dời theo các việc phụ thuộc không. Zoom Ngày / Tuần / Tháng. Việc chưa có ngày nằm ở mục
// "Chưa xếp lịch", kéo lên trục thời gian để đặt ngày.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'store.dart';
import 'task_widgets.dart';

const _rowH = 38.0, _headH = 52.0;
const kZoomDay = {'day': 36.0, 'week': 14.0, 'month': 4.5};

/// Một dòng của Gantt.
class GanttRow {
  GanttRow(this.task, this.depth, {this.hasKids = false});
  final TwTask task;
  final int depth;
  final bool hasKids;
}

/// Dựng các dòng: việc cấp đầu theo thứ tự, việc con ngay dưới cha (bỏ qua cha đang gập).
List<GanttRow> ganttRows(List<TwTask> tasks, Set<String> folded) {
  final ids = {for (final t in tasks) t.id};
  final out = <GanttRow>[];
  void walk(String? parent, int depth) {
    final kids = tasks.where((t) => parent == null ? (t.parentId == null || !ids.contains(t.parentId)) : t.parentId == parent).toList()
      ..sort((a, b) => (a.start ?? a.due ?? DateTime.utc(9999)).compareTo(b.start ?? b.due ?? DateTime.utc(9999)) != 0
          ? (a.start ?? a.due ?? DateTime.utc(9999)).compareTo(b.start ?? b.due ?? DateTime.utc(9999))
          : byRank(a, b));
    for (final t in kids) {
      final has = tasks.any((x) => x.parentId == t.id);
      if (t.start == null && t.due == null && !has) continue;
      out.add(GanttRow(t, depth, hasKids: has));
      if (has && !folded.contains(t.id) && depth < 3) walk(t.id, depth + 1);
    }
  }

  walk(null, 0);
  return out;
}

/// Khoảng ngày [start, end] của việc trên Gantt (việc cha không có ngày thì lấy theo các việc con).
(DateTime, DateTime)? spanOf(TwTask t, List<TwTask> all) {
  if (t.start != null || t.due != null) return (t.start ?? t.due!, t.due ?? t.start!);
  DateTime? a, b;
  for (final k in all.where((x) => x.parentId == t.id)) {
    final s = spanOf(k, all);
    if (s == null) continue;
    if (a == null || s.$1.isBefore(a)) a = s.$1;
    if (b == null || s.$2.isAfter(b)) b = s.$2;
  }
  return a == null ? null : (a, b!);
}

class TwGanttView extends StatefulWidget {
  const TwGanttView({super.key, required this.store, required this.project, required this.filter, required this.onOpen});
  final TwStore store;
  final TwProjectFull project;
  final TwFilter filter;
  final void Function(TwTask) onOpen;
  @override
  State<TwGanttView> createState() => TwGanttViewState();
}

class TwGanttViewState extends State<TwGanttView> {
  String zoom = 'day';
  final Set<String> _folded = {};
  final _vl = ScrollController(), _vr = ScrollController(), _h = ScrollController();
  bool _syncing = false;
  /// Đang kéo: id việc, chế độ (move | start | end), số ngày lệch.
  String? _dragId, _dragMode;
  double _dragDx = 0;
  bool _showUnscheduled = true;

  TwStore get store => widget.store;
  double get dw => kZoomDay[zoom]!;

  @override
  void initState() {
    super.initState();
    void sync(ScrollController from, ScrollController to) {
      if (_syncing || !to.hasClients) return;
      _syncing = true;
      to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
      _syncing = false;
    }

    _vl.addListener(() => sync(_vl, _vr));
    _vr.addListener(() => sync(_vr, _vl));
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToToday());
  }

  @override
  void dispose() {
    _vl.dispose();
    _vr.dispose();
    _h.dispose();
    super.dispose();
  }

  late DateTime _origin;

  /// Đưa vạch hôm nay vào gần mép trái.
  void scrollToToday() {
    if (!_h.hasClients) return;
    final x = store.today.difference(_origin).inDays * dw - 3 * dw;
    _h.jumpTo(x.clamp(0, _h.position.maxScrollExtent));
  }

  (DateTime, int) _range(List<TwTask> all) {
    var a = store.today.subtract(const Duration(days: 7)), b = store.today.add(const Duration(days: 30));
    for (final t in all) {
      for (final d in [t.start, t.due]) {
        if (d == null) continue;
        if (d.isBefore(a)) a = d;
        if (d.isAfter(b)) b = d;
      }
    }
    a = a.subtract(Duration(days: 3 + (a.weekday - 1)));
    b = b.add(Duration(days: zoom == 'month' ? 60 : 14));
    return (a, b.difference(a).inDays + 1);
  }

  Future<void> _commit(TwTask t, DateTime? start, DateTime? due) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final deps = await store.api.schedulePreview(t.id, start, due);
      var shift = false;
      if (deps.isNotEmpty && mounted) {
        final r = await showDialog<String>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Dời ${t.key}: ${start == null ? '' : dShort(start)} – ${due == null ? '' : dShort(due)}'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${deps.length} việc phụ thuộc việc này:'),
              const SizedBox(height: 6),
              for (final x in deps.take(6)) Text('• ${x.key} ${x.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Huỷ')),
              TextButton(key: const ValueKey('shift-no'), onPressed: () => Navigator.pop(d, 'no'), child: const Text('Chỉ việc này')),
              FilledButton(key: const ValueKey('shift-yes'), onPressed: () => Navigator.pop(d, 'yes'), child: const Text('Dời theo')),
            ],
          ),
        );
        if (r == null) return;
        shift = r == 'yes';
      }
      await store.schedule(t, start, due, shift: shift);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _endDrag(TwTask t) {
    final days = (_dragDx / dw).round();
    final mode = _dragMode;
    setState(() {
      _dragId = null;
      _dragDx = 0;
    });
    if (days == 0 || !widget.project.project.canEdit) return;
    final s = t.start ?? t.due!, e = t.due ?? t.start!;
    final d = Duration(days: days.abs());
    DateTime add(DateTime x) => days > 0 ? x.add(d) : x.subtract(d);
    switch (mode) {
      case 'start':
        final ns = add(s);
        if (ns.isAfter(e)) return;
        _commit(t, ns, t.due);
      case 'end':
        final ne = add(e);
        if (ne.isBefore(s)) return;
        _commit(t, t.start, ne);
      default:
        _commit(t, t.start == null ? null : add(t.start!), t.due == null ? null : add(t.due!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final wide = twWide(context);
    final p = widget.project;
    final all = widget.filter.apply(store.tasksOf(p.project.id), store.today);
    final rows = ganttRows(all, _folded);
    final unscheduled = all.where((t) => t.start == null && t.due == null && !all.any((x) => x.parentId == t.id) && t.parentId == null).toList();
    final (origin, days) = _range(all);
    _origin = origin;
    final width = days * dw;
    final leftW = wide ? 330.0 : 0.0;

    final zoomSeg = SegmentedButton<String>(
      key: const ValueKey('gantt-zoom'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [ButtonSegment(value: 'day', label: Text('Ngày')), ButtonSegment(value: 'week', label: Text('Tuần')), ButtonSegment(value: 'month', label: Text('Tháng'))],
      selected: {zoom},
      onSelectionChanged: (s) {
        setState(() => zoom = s.first);
        WidgetsBinding.instance.addPostFrameCallback((_) => scrollToToday());
      },
    );

    final timeline = SingleChildScrollView(
      controller: _h,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Column(children: [
          SizedBox(height: _headH, child: CustomPaint(size: Size(width, _headH), painter: _HeadPainter(origin, days, dw, zoom, store.today, look, DefaultTextStyle.of(context).style))),
          Expanded(
            child: DragTarget<TwTask>(
              onAcceptWithDetails: (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                // Ngày dưới chỗ thả: toạ độ toàn cục → vị trí trên trục thời gian.
                final local = (d.offset.dx - (box.localToGlobal(Offset.zero).dx + leftW)) + _h.offset + 20;
                final day = origin.add(Duration(days: (local / dw).floor().clamp(0, days - 1)));
                _commit(d.data, day, day.add(const Duration(days: 2)));
              },
              builder: (context, _, _) => ListView(
                controller: _vr,
                children: [
                  SizedBox(
                    height: math.max(rows.length * _rowH, 200),
                    child: Stack(children: [
                      Positioned.fill(child: CustomPaint(painter: _GridPainter(origin, days, dw, zoom, store.today, look, rows.length))),
                      for (var i = 0; i < rows.length; i++) ..._bar(rows[i], i, all, origin, look),
                      Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ArrowPainter(rows, all, origin, dw, look, _dragId, _dragMode, _dragDx)))),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );

    return Column(children: [
      if (!wide)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(children: [zoomSeg, const Spacer(), IconButton(tooltip: 'Hôm nay', icon: const Icon(Icons.today), onPressed: scrollToToday)]),
        ),
      Expanded(
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: look.divider))),
          child: Row(children: [
            if (wide)
              Container(
                width: leftW,
                decoration: BoxDecoration(border: Border(right: BorderSide(color: look.divider))),
                child: Column(children: [
                  Container(
                    height: _headH,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.divider))),
                    child: Row(children: [
                      Text('Việc', style: TextStyle(fontSize: 12, color: look.sub, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(tooltip: 'Hôm nay', visualDensity: VisualDensity.compact, icon: const Icon(Icons.today, size: 20), onPressed: scrollToToday),
                      zoomSeg,
                    ]),
                  ),
                  Expanded(
                    child: ListView(controller: _vl, children: [
                      for (final r in rows) _leftRow(r, look),
                      if (rows.length * _rowH < 200) SizedBox(height: 200 - rows.length * _rowH),
                    ]),
                  ),
                ]),
              ),
            Expanded(child: timeline),
          ]),
        ),
      ),
      if (unscheduled.isNotEmpty) _unscheduled(unscheduled, look, wide),
    ]);
  }

  Widget _leftRow(GanttRow r, TwLook look) {
    final t = r.task;
    final milestone = t.start == null && t.due != null && !r.hasKids;
    return InkWell(
      key: ValueKey('grow-${t.key}'),
      onTap: () => widget.onOpen(t),
      child: Container(
        height: _rowH,
        padding: EdgeInsets.only(left: 12.0 + r.depth * 20, right: 12),
        decoration: BoxDecoration(color: r.hasKids && r.depth == 0 ? look.surface : null, border: Border(bottom: BorderSide(color: look.divider))),
        child: Row(children: [
          if (r.hasKids)
            InkWell(
              onTap: () => setState(() => _folded.contains(t.id) ? _folded.remove(t.id) : _folded.add(t.id)),
              child: Icon(_folded.contains(t.id) ? Icons.chevron_right : Icons.expand_more, size: 18, color: look.sub),
            )
          else if (milestone)
            Icon(Icons.flag_outlined, size: 17, color: look.warn)
          else if (r.depth > 0)
            Icon(Icons.subdirectory_arrow_right, size: 15, color: look.sub),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${t.key} ${t.title}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: r.hasKids && r.depth == 0 ? FontWeight.w700 : null, color: r.depth > 0 ? look.sub : null)),
          ),
          if (t.assignees.isNotEmpty) TwAvatar.of(t.assignees.first, size: 22, border: false),
        ]),
      ),
    );
  }

  List<Widget> _bar(GanttRow r, int i, List<TwTask> all, DateTime origin, TwLook look) {
    final t = r.task;
    final span = spanOf(t, all);
    if (span == null) return const [];
    final y = i * _rowH;
    var x0 = span.$1.difference(origin).inDays * dw, x1 = (span.$2.difference(origin).inDays + 1) * dw;
    if (_dragId == t.id) {
      if (_dragMode != 'end') x0 += _dragDx;
      if (_dragMode != 'start') x1 += _dragDx;
      if (x1 - x0 < dw) x1 = x0 + dw;
    }
    final milestone = t.start == null && t.due != null && !r.hasKids;
    if (r.hasKids && t.start == null && t.due == null) {
      return [Positioned(left: x0, top: y + 15, width: x1 - x0, height: 8, child: Container(decoration: BoxDecoration(color: look.text.withValues(alpha: .7), borderRadius: BorderRadius.circular(2))))];
    }
    final status = store.statusOf(t);
    final color = t.priority == 1 && !(status?.isClosed ?? false) ? look.red : hexColor(status?.color, look.accent);
    final canEdit = widget.project.project.canEdit;
    void start(DragStartDetails d, double w) {
      final lx = d.localPosition.dx;
      setState(() {
        _dragId = t.id;
        _dragMode = milestone ? 'move' : (lx < 10 ? 'start' : (lx > w - 10 ? 'end' : 'move'));
        _dragDx = 0;
      });
    }

    Widget gestures(Widget child, double w) => GestureDetector(
          key: ValueKey('gbar-${t.key}'),
          onTap: () => widget.onOpen(t),
              onHorizontalDragStart: canEdit ? (d) => start(d, w) : null,
          onHorizontalDragUpdate: canEdit ? (d) => setState(() => _dragDx += d.delta.dx) : null,
          onHorizontalDragEnd: canEdit ? (_) => _endDrag(t) : null,
          child: MouseRegion(cursor: canEdit ? SystemMouseCursors.grab : MouseCursor.defer, child: child),
        );
    if (milestone) {
      final cx = x1 - dw / 2;
      return [
        Positioned(
          left: cx - 9,
          top: y + 10,
          width: 18,
          height: 18,
          child: gestures(Transform.rotate(angle: math.pi / 4, child: Container(decoration: BoxDecoration(color: look.warn, borderRadius: BorderRadius.circular(3)))), 18),
        ),
        Positioned(left: cx + 14, top: y + 11, child: IgnorePointer(child: Text(t.title, style: TextStyle(fontSize: 12, color: look.sub, fontWeight: FontWeight.w600)))),
      ];
    }
    final w = math.max(x1 - x0 - 4, 6.0);
    final pct = t.percent;
    return [
      Positioned(
        left: x0 + 2,
        top: y + 8,
        width: w,
        height: 22,
        child: gestures(
          Container(
            decoration: BoxDecoration(color: color.withValues(alpha: r.depth > 0 ? .85 : 1), borderRadius: BorderRadius.circular(6)),
            clipBehavior: Clip.hardEdge,
            child: Stack(children: [
              FractionallySizedBox(widthFactor: pct / 100, child: Container(color: Colors.white.withValues(alpha: .25))),
              if (w > 34)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(alignment: Alignment.centerLeft, child: Text('$pct%', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600))),
                ),
              if (_dragId == t.id && _dragMode != 'move')
                Align(alignment: _dragMode == 'start' ? Alignment.centerLeft : Alignment.centerRight, child: Container(width: 4, margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2), color: Colors.white70)),
            ]),
          ),
          w,
        ),
      ),
      if (!twWide(context) || w < 90)
        Positioned(left: x0 + w + 8, top: y + 10, child: IgnorePointer(child: Text(t.title, style: TextStyle(fontSize: 11.5, color: look.sub, fontWeight: FontWeight.w600)))),
      if (_dragId == t.id)
        Positioned(
          left: x0,
          top: y - 16,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: look.text, borderRadius: BorderRadius.circular(4)),
              child: Text(
                () {
                  final n = (_dragDx / dw).round();
                  final s = (t.start ?? t.due!), e = (t.due ?? t.start!);
                  final ns = _dragMode == 'end' ? s : s.add(Duration(days: n));
                  final ne = _dragMode == 'start' ? e : e.add(Duration(days: n));
                  return '${dShort(ns)} – ${dShort(ne)}';
                }(),
                style: TextStyle(color: look.bg, fontSize: 11),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _unscheduled(List<TwTask> list, TwLook look, bool wide) => Container(
        decoration: BoxDecoration(color: look.surface, border: Border(top: BorderSide(color: look.divider))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => setState(() => _showUnscheduled = !_showUnscheduled),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(children: [
                Icon(_showUnscheduled ? Icons.expand_more : Icons.chevron_right, size: 18, color: look.sub),
                const SizedBox(width: 4),
                Text('Chưa xếp lịch · ${list.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Flexible(child: Text('Kéo việc lên trục thời gian để đặt ngày', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: look.sub))),
              ]),
            ),
          ),
          if (_showUnscheduled)
            SizedBox(
              height: 44,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), children: [
                for (final t in list)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: () {
                      final chip = ActionChip(
                        key: ValueKey('unsched-${t.key}'),
                        avatar: StatusRing(store.statusOf(t)),
                        label: Text('${t.key} ${t.title}', overflow: TextOverflow.ellipsis),
                        onPressed: () => widget.onOpen(t),
                      );
                      final fb = Material(color: Colors.transparent, child: Chip(label: Text(t.title)));
                      return wide ? Draggable<TwTask>(data: t, feedback: fb, child: chip) : LongPressDraggable<TwTask>(data: t, feedback: fb, child: chip);
                    }(),
                  ),
              ]),
            ),
        ]),
      );
}

class _HeadPainter extends CustomPainter {
  _HeadPainter(this.origin, this.days, this.dw, this.zoom, this.today, this.look, this.base);
  final DateTime origin, today;
  final int days;
  final double dw;
  final String zoom;
  final TwLook look;
  /// Kiểu chữ của giao diện (phông chữ app).
  final TextStyle base;

  void _text(Canvas c, String s, Offset at, {Color? color, double size = 11, FontWeight w = FontWeight.w500, bool center = false, double width = 60}) {
    final tp = TextPainter(text: TextSpan(text: s, style: base.copyWith(color: color ?? look.sub, fontSize: size, fontWeight: w, height: 1.25)), textDirection: TextDirection.ltr, textAlign: center ? TextAlign.center : TextAlign.left)
      ..layout(minWidth: center ? width : 0, maxWidth: center ? width : 400);
    tp.paint(c, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height - .5), Offset(size.width, size.height - .5), Paint()..color = look.divider);
    for (var i = 0; i < days; i++) {
      final d = origin.add(Duration(days: i));
      final x = i * dw;
      if (zoom == 'month') {
        if (d.day == 1 || i == 0) _text(canvas, 'Tháng ${d.month}/${d.year}', Offset(x + 4, 6), color: look.text, w: FontWeight.w700, size: 11.5);
        if (d.weekday == 1) _text(canvas, '${d.day}', Offset(x + 1, 30));
        continue;
      }
      if (d.weekday == 1) {
        final wk = ((d.difference(DateTime.utc(d.year, 1, 1)).inDays + DateTime.utc(d.year, 1, 1).weekday - 1) ~/ 7) + 1;
        final end = d.add(const Duration(days: 6));
        _text(canvas, zoom == 'week' ? '${dShort(d)}–${dShort(end)}' : 'Tuần $wk · ${d.day}–${end.day}/${end.month}', Offset(x + 6, 5), color: look.text, w: FontWeight.w700, size: 11.5);
      }
      final isToday = d == today;
      if (zoom == 'day') {
        _text(canvas, '${wdShort(d)}\n${d.day}', Offset(x, 22), center: true, width: dw, color: isToday ? look.red : null, w: isToday ? FontWeight.w700 : FontWeight.w500);
      } else if (d.weekday == 1 || isToday) {
        _text(canvas, '${d.day}', Offset(x + 1, 30), color: isToday ? look.red : null, w: isToday ? FontWeight.w700 : FontWeight.w500);
      }
    }
  }

  @override
  bool shouldRepaint(_HeadPainter o) => o.origin != origin || o.days != days || o.dw != dw || o.today != today || o.look.dark != look.dark;
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.origin, this.days, this.dw, this.zoom, this.today, this.look, this.rows);
  final DateTime origin, today;
  final int days, rows;
  final double dw;
  final String zoom;
  final TwLook look;
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()..color = look.divider;
    final we = Paint()..color = look.surface.withValues(alpha: .7);
    for (var i = 0; i < days; i++) {
      final d = origin.add(Duration(days: i));
      final x = i * dw;
      if (zoom != 'month' && d.weekday >= 6) canvas.drawRect(Rect.fromLTWH(x, 0, dw, size.height), we);
      if (zoom == 'day' || d.weekday == 1) canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var r = 1; r <= rows; r++) {
      canvas.drawLine(Offset(0, r * _rowH - .5), Offset(size.width, r * _rowH - .5), line);
    }
    final tx = (today.difference(origin).inDays + .5) * dw;
    canvas.drawRect(Rect.fromLTWH(tx - 1, 0, 2, size.height), Paint()..color = look.red);
  }

  @override
  bool shouldRepaint(_GridPainter o) => true;
}

/// Mũi tên phụ thuộc: từ cuối thanh việc chặn tới đầu thanh việc bị chặn.
class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.rows, this.all, this.origin, this.dw, this.look, this.dragId, this.dragMode, this.dragDx);
  final List<GanttRow> rows;
  final List<TwTask> all;
  final DateTime origin;
  final double dw, dragDx;
  final TwLook look;
  final String? dragId, dragMode;
  @override
  void paint(Canvas canvas, Size size) {
    final idx = {for (var i = 0; i < rows.length; i++) rows[i].task.id: i};
    final paint = Paint()
      ..color = look.sub
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    (double, double)? xs(TwTask t) {
      final s = spanOf(t, all);
      if (s == null) return null;
      var a = s.$1.difference(origin).inDays * dw, b = (s.$2.difference(origin).inDays + 1) * dw;
      if (t.id == dragId) {
        if (dragMode != 'end') a += dragDx;
        if (dragMode != 'start') b += dragDx;
      }
      return (a, b);
    }

    for (final r in rows) {
      final to = r.task;
      for (final fromId in to.blockedBy) {
        final fi = idx[fromId], ti = idx[to.id];
        if (fi == null || ti == null) continue;
        final from = rows[fi].task;
        final a = xs(from), b = xs(to);
        if (a == null || b == null) continue;
        final y1 = fi * _rowH + _rowH / 2, y2 = ti * _rowH + _rowH / 2;
        final x1 = a.$2, x2 = b.$1 + 2;
        final path = Path()
          ..moveTo(x1, y1)
          ..lineTo(x1 + 8, y1)
          ..lineTo(x1 + 8, y2)
          ..lineTo(x2 - 4, y2);
        if (x2 - 4 < x1 + 8) {
          path
            ..reset()
            ..moveTo(x1, y1)
            ..lineTo(x1 + 8, y1)
            ..lineTo(x1 + 8, (y1 + y2) / 2)
            ..lineTo(x2 - 10, (y1 + y2) / 2)
            ..lineTo(x2 - 10, y2)
            ..lineTo(x2 - 4, y2);
        }
        canvas.drawPath(path, paint);
        canvas.drawPath(
            Path()
              ..moveTo(x2 - 6, y2 - 4)
              ..lineTo(x2, y2)
              ..lineTo(x2 - 6, y2 + 4)
              ..close(),
            Paint()..color = look.sub);
      }
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter o) => true;
}
