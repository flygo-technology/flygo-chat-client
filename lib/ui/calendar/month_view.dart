// Lịch: xem Tháng. Máy tính: lưới 5–6 tuần, mỗi ô có số ngày (ngày âm mùng 1 / rằm), thanh màu cho sự kiện cả ngày,
// chấm màu + giờ cho sự kiện có giờ, "+N sự kiện" khi không đủ chỗ. Điện thoại: lưới số ngày có chấm màu, bên dưới là
// danh sách sự kiện của ngày đang chọn.
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'look.dart';
import 'lunar.dart';
import 'model.dart';
import 'store.dart';
import 'tz.dart';

/// Các ngày của lưới tháng chứa [month] (đủ tuần, bắt đầu theo cài đặt).
List<DateTime> monthDays(DateTime month, int weekStart) {
  final first = DateTime.utc(month.year, month.month);
  final start = weekStartOf(first, weekStart);
  final next = DateTime.utc(month.year, month.month + 1);
  final weeks = (daysBetween(start, next) / 7).ceil();
  return [for (var i = 0; i < weeks * 7; i++) addDays(start, i)];
}

class MonthGrid extends StatelessWidget {
  const MonthGrid({super.key, required this.store, required this.month, required this.onEventTap, required this.onDayTap, required this.onMore, this.onCreate});
  final CalStore store;
  final DateTime month;
  final void Function(CEvent e, Rect anchor) onEventTap;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<DateTime> onMore;
  final void Function(DateTime day, Rect anchor)? onCreate;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final days = monthDays(month, store.settings.weekStart);
    final weeks = days.length ~/ 7;
    final evs = store.eventsIn(days.first, addDays(days.last, 1));
    final today = store.today;
    return Column(children: [
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: i == 0 ? Colors.transparent : pal.divider))),
              child: Text(dowHeader(days[i]), textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, letterSpacing: .3, fontWeight: FontWeight.w600, color: pal.sub)),
            ),
          ),
      ]),
      Expanded(
        child: Column(children: [
          for (var w = 0; w < weeks; w++)
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < 7; i++) Expanded(child: _cell(context, days[w * 7 + i], evs, today, first: i == 0, top: w == 0)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _cell(BuildContext context, DateTime d, List<CEvent> all, DateTime today, {required bool first, required bool top}) {
    final pal = Pal.of(context);
    final dark = calDark(context);
    final inMonth = d.month == month.month;
    final next = addDays(d, 1);
    final evs = all.where((e) => e.wallStart(store.tz).isBefore(next) && (e.wallEnd(store.tz).isAfter(d) || e.wallStart(store.tz) == d)).toList()
      ..sort((a, b) {
        final x = a.showsAllDay(store.tz), y = b.showsAllDay(store.tz);
        if (x != y) return x ? -1 : 1;
        return a.wallStart(store.tz).compareTo(b.wallStart(store.tz));
      });
    final isToday = sameDay(d, today);
    final l = store.settings.lunar ? toLunar(d) : null;
    final label = d.day == 1 ? '1 Th${d.month}' : '${d.day}';
    final numColor = inMonth ? pal.text : pal.sub.withValues(alpha: .7);
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: first ? Colors.transparent : pal.divider), top: BorderSide(color: pal.divider)),
      ),
      child: LayoutBuilder(builder: (context, c) {
        const chipH = 21.0;
        final room = ((c.maxHeight - 32) / chipH).floor().clamp(0, 99);
        final shown = evs.length > room ? (room - 1).clamp(0, 99) : evs.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (t) {
            final box = context.findRenderObject() as RenderBox;
            if (onCreate != null) {
              onCreate!(d, box.localToGlobal(Offset.zero) & box.size);
            } else {
              onDayTap(d);
            }
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 3),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                InkWell(
                  onTap: () => onDayTap(d),
                  customBorder: const StadiumBorder(),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    height: 24,
                    padding: EdgeInsets.symmetric(horizontal: d.day == 1 ? 6 : 0),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: isToday ? calAccent(context) : null, borderRadius: BorderRadius.circular(12)),
                    child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: isToday || d.day == 1 ? FontWeight.w700 : FontWeight.w500, color: isToday ? Colors.white : numColor)),
                  ),
                ),
                if (l != null && (l.day == 1 || l.day == 15)) ...[
                  const SizedBox(width: 6),
                  Text('${l.short} ÂL', style: TextStyle(fontSize: 10, color: pal.sub)),
                ],
              ]),
            ),
            for (final e in evs.take(shown)) _chip(context, e, d, dark),
            if (shown < evs.length)
              InkWell(
                onTap: () => onMore(d),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                  child: Text(tr('+{0} sự kiện', [evs.length - shown]), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: pal.sub)),
                ),
              ),
          ]),
        );
      }),
    );
  }

  Widget _chip(BuildContext context, CEvent e, DateTime d, bool dark) {
    final pal = Pal.of(context);
    final c = eventColor(store.colorOf(e), dark);
    final title = e.busyOnly ? tr('Bận') : (e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title);
    return Builder(builder: (bc) {
      void tap() {
        final box = bc.findRenderObject() as RenderBox;
        onEventTap(e, box.localToGlobal(Offset.zero) & box.size);
      }

      if (e.showsAllDay(store.tz)) {
        return Padding(
          key: ValueKey('mev-${e.instanceId}-${d.day}'),
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
          child: Material(
            color: e.pendingInvite ? Colors.transparent : c,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: e.pendingInvite ? BorderSide(color: c) : BorderSide.none),
            child: InkWell(
              onTap: tap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: e.pendingInvite ? c : Colors.white)),
              ),
            ),
          ),
        );
      }
      return InkWell(
        key: ValueKey('mev-${e.instanceId}-${d.day}'),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
          child: Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${hm(e.wallStart(store.tz))} $title',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: TextStyle(fontSize: 12, color: pal.text, decoration: e.declined ? TextDecoration.lineThrough : null)),
            ),
          ]),
        ),
      );
    });
  }
}

/// Điện thoại: lưới tháng có chấm màu + danh sách của ngày chọn.
class PhoneMonth extends StatelessWidget {
  const PhoneMonth({super.key, required this.store, required this.month, required this.selected, required this.onSelect, required this.onEventTap});
  final CalStore store;
  final DateTime month, selected;
  final ValueChanged<DateTime> onSelect;
  final void Function(CEvent e, Rect anchor) onEventTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = calDark(context);
    final days = monthDays(month, store.settings.weekStart);
    final evs = store.eventsIn(days.first, addDays(days.last, 1));
    final today = store.today;
    final dayEvs = store.eventsIn(selected, addDays(selected, 1));
    return ListView(padding: EdgeInsets.zero, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(children: [
          for (var i = 0; i < 7; i++) Expanded(child: Text(dowShort(days[i]), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: pal.sub, fontWeight: FontWeight.w500))),
        ]),
      ),
      for (var w = 0; w < days.length ~/ 7; w++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(child: () {
                final d = days[w * 7 + i];
                final next = addDays(d, 1);
                final colors = <Color>[];
                for (final e in evs) {
                  if (e.wallStart(store.tz).isBefore(next) && e.wallEnd(store.tz).isAfter(d)) {
                    final c = eventColor(store.colorOf(e), dark);
                    if (!colors.contains(c)) colors.add(c);
                  }
                }
                final on = sameDay(d, selected), isToday = sameDay(d, today);
                return InkWell(
                  key: ValueKey('pday-${fmtDate(d)}'),
                  onTap: () => onSelect(d),
                  child: SizedBox(
                    height: 46,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? calAccent(context) : on ? calAccentSoft(context) : null),
                        child: Text('${d.day}',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: isToday || on ? FontWeight.w700 : FontWeight.w400,
                                color: isToday ? Colors.white : on ? calAccent(context) : d.month == month.month ? pal.text : pal.sub.withValues(alpha: .6))),
                      ),
                      const SizedBox(height: 3),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (final c in colors.take(3)) Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                      ]),
                    ]),
                  ),
                );
              }()),
          ]),
        ),
      Divider(height: 16, color: pal.divider),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(dayLong(selected, now: today), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text)),
      ),
      if (dayEvs.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), child: Text(tr('Không có sự kiện'), style: TextStyle(color: pal.sub))),
      for (final e in dayEvs) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: EventTile(store: store, e: e, onTap: onEventTap, timeLeft: true)),
      const SizedBox(height: 90),
    ]);
  }
}

/// Ô sự kiện màu (danh sách điện thoại, lịch biểu điện thoại).
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.store, required this.e, required this.onTap, this.timeLeft = false});
  final CalStore store;
  final CEvent e;
  final void Function(CEvent e, Rect anchor) onTap;
  /// Giờ ở đầu dòng ("13:30  Tiêu đề") thay vì dòng dưới.
  final bool timeLeft;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = eventColor(store.colorOf(e), calDark(context));
    final pending = e.pendingInvite;
    final fg = pending ? pal.text : Colors.white;
    final title = e.busyOnly ? tr('Bận') : (e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title);
    final time = e.showsAllDay(store.tz) ? tr('Cả ngày') : (timeLeft ? hm(e.wallStart(store.tz)) : timeRange(e, store.tz));
    return Builder(builder: (bc) {
      return Material(
        key: ValueKey('tile-${e.instanceId}'),
        color: pending ? pal.bg : e.declined ? c.withValues(alpha: .25) : c,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: pending ? BorderSide(color: c, width: 1.2) : BorderSide.none),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            final box = bc.findRenderObject() as RenderBox;
            onTap(e, box.localToGlobal(Offset.zero) & box.size);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: timeLeft
                ? Row(children: [
                    SizedBox(width: 56, child: Text(time, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg))),
                    Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: fg))),
                    if (pending) Text(tr('chờ trả lời'), style: TextStyle(fontSize: 11, color: pal.sub)),
                  ])
                : Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
                        Text([time, if (e.location.isNotEmpty && !e.busyOnly) e.location].join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: .9))),
                      ]),
                    ),
                    if (e.conference != null) Icon(Icons.videocam_outlined, size: 18, color: fg),
                  ]),
          ),
        ),
      );
    });
  }
}
