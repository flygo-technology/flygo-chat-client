// Lịch: xem Lịch biểu — danh sách cuộn vô hạn theo ngày (chỉ ngày có sự kiện), cuộn tới cuối thì tải tiếp tháng sau.
// Cũng dùng để hiện kết quả tìm kiếm ([results]).
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'look.dart';
import 'model.dart';
import 'month_view.dart' show EventTile;
import 'store.dart';
import 'tz.dart';

class AgendaList extends StatefulWidget {
  const AgendaList({super.key, required this.store, required this.from, required this.onEventTap, this.onJoin, this.results, this.wide = true});
  final CalStore store;
  final DateTime from;
  final void Function(CEvent e, Rect anchor) onEventTap;
  final ValueChanged<CEvent>? onJoin;
  /// Kết quả tìm kiếm: hiện đúng danh sách này thay vì tải theo tháng.
  final List<CEvent>? results;
  final bool wide;

  @override
  State<AgendaList> createState() => _AgendaListState();
}

class _AgendaListState extends State<AgendaList> {
  /// Đã tải tới (không gồm) tháng này.
  late DateTime _until = _monthAfter(widget.from, 2);
  bool _more = false;

  CalStore get store => widget.store;

  static DateTime _monthAfter(DateTime d, int n) => DateTime.utc(d.year, d.month + n);

  @override
  void didUpdateWidget(AgendaList old) {
    super.didUpdateWidget(old);
    if (!sameDay(old.from, widget.from)) _until = _monthAfter(widget.from, 2);
  }

  Future<void> _loadMore() async {
    if (_more || widget.results != null || daysBetween(widget.from, _until) > 730) return;
    _more = true;
    final next = _monthAfter(_until, 1);
    await store.ensureRange(_until, next, view: false);
    if (!mounted) return;
    setState(() {
      _until = next;
      _more = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final evs = widget.results ?? store.eventsIn(widget.from, _until);
    final groups = <DateTime, List<CEvent>>{};
    for (final e in evs) {
      // Sự kiện nhiều ngày: hiện ở từng ngày (tính từ ngày bắt đầu xem).
      var d = dayOf(e.wallStart(store.tz));
      final end = e.wallEnd(store.tz);
      if (widget.results == null && d.isBefore(widget.from)) d = widget.from;
      var guard = 0;
      do {
        (groups[d] ??= []).add(e);
        d = addDays(d, 1);
      } while (d.isBefore(end) && widget.results == null && guard++ < 60 && d.isBefore(_until));
    }
    final days = groups.keys.toList()..sort();
    if (days.isEmpty && widget.results != null) {
      return Center(child: Text(tr('Không tìm thấy sự kiện nào'), style: TextStyle(color: pal.sub)));
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(widget.wide ? 24 : 8, 8, widget.wide ? 24 : 8, 96),
      itemCount: days.length + (widget.results == null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == days.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: days.isEmpty && !_more
                  ? Text(tr('Không có sự kiện sắp tới'), style: TextStyle(color: pal.sub))
                  : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final d = days[i];
        return widget.wide ? _dayWide(context, d, groups[d]!) : _dayPhone(context, d, groups[d]!);
      },
    );
  }

  Widget _dateBadge(BuildContext context, DateTime d, double size) {
    final today = sameDay(d, store.today);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: today ? calAccent(context) : null, shape: BoxShape.circle),
      child: Text('${d.day}', style: TextStyle(fontSize: size * .55, fontWeight: FontWeight.w400, color: today ? Colors.white : Pal.of(context).text)),
    );
  }

  Widget _dayWide(BuildContext context, DateTime d, List<CEvent> evs) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 118,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _dateBadge(context, d, 40),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('TH${d.month}, ${dowHeader(d)}${d.year != store.today.year ? '\n${d.year}' : ''}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sameDay(d, store.today) ? calAccent(context) : pal.sub)),
            ),
          ]),
        ),
        Expanded(child: Column(children: [for (final e in evs) _rowWide(context, e, d)])),
      ]),
    );
  }

  Widget _rowWide(BuildContext context, CEvent e, DateTime d) {
    final pal = Pal.of(context);
    final c = eventColor(store.colorOf(e), calDark(context));
    final title = e.busyOnly ? tr('Bận') : (e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title);
    var time = timeRange(e, store.tz), suffix = '';
    if (e.showsAllDay(store.tz)) {
      final s = dayOf(e.wallStart(store.tz)), en = e.wallEnd(store.tz);
      final total = daysBetween(s, en.subtract(const Duration(minutes: 1))) + 1;
      time = tr('Cả ngày');
      if (total > 1) suffix = ' ${tr('(ngày {0}/{1})', [daysBetween(s, d) + 1, total])}';
    }
    final line = [title + suffix, if (e.location.isNotEmpty && !e.busyOnly) e.location, if (e.pendingInvite) tr('chưa trả lời')].join(' · ');
    return Builder(builder: (bc) {
      return InkWell(
        key: ValueKey('ag-${e.instanceId}-${d.day}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          final box = bc.findRenderObject() as RenderBox;
          widget.onEventTap(e, box.localToGlobal(Offset.zero) & box.size);
        },
        child: SizedBox(
          height: 36,
          child: Row(children: [
            Container(width: 11, height: 11, margin: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            SizedBox(width: 148, child: Text(time, style: TextStyle(fontSize: 13.5, color: pal.sub))),
            Expanded(
              child: Text(line,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: pal.text, decoration: e.declined ? TextDecoration.lineThrough : null)),
            ),
            if (e.conference != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: pal.surface,
                    foregroundColor: pal.text,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: widget.onJoin == null ? null : () => widget.onJoin!(e),
                  icon: const Icon(Icons.videocam_outlined, size: 17, color: kCalTeal),
                  label: Text(tr('Họp')),
                ),
              ),
          ]),
        ),
      );
    });
  }

  Widget _dayPhone(BuildContext context, DateTime d, List<CEvent> evs) {
    final pal = Pal.of(context);
    final first = sameDay(d, widget.from) || d.day == 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (first && widget.results == null)
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), child: Text(tr('Tháng {0} {1}', [d.month, d.year]), style: TextStyle(fontSize: 12.5, color: pal.sub))),
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 52,
            child: Column(children: [
              Text(dowHeader(d), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: sameDay(d, store.today) ? calAccent(context) : pal.sub)),
              const SizedBox(height: 2),
              _dateBadge(context, d, 30),
            ]),
          ),
          Expanded(
            child: Column(children: [
              for (final e in evs) Padding(padding: const EdgeInsets.only(bottom: 6, right: 4), child: EventTile(store: store, e: e, onTap: widget.onEventTap)),
            ]),
          ),
        ]),
      ),
    ]);
  }
}
