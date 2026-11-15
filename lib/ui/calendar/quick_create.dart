// Lịch: khung tạo nhanh (máy tính) khi bấm / kéo ô giờ trống — tiêu đề, giờ, thêm khách, cuộc họp trên Họp, địa điểm,
// chọn lịch; "Tuỳ chọn khác" mở trình sửa đầy đủ với những gì đã nhập.
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'editor.dart' show EventDraft;
import 'hop.dart';
import 'look.dart';
import 'model.dart' show calId;
import 'rrule_text.dart';
import 'store.dart';
import 'tz.dart';

class QuickCreate extends StatefulWidget {
  const QuickCreate({super.key, required this.store, required this.draft, required this.onMore, this.mmToken});
  final CalStore store;
  final EventDraft draft;
  /// Mở trình sửa đầy đủ (khung đã đóng) với bản nháp đang nhập.
  final void Function(EventDraft d) onMore;
  final String? mmToken;
  @override
  State<QuickCreate> createState() => _QuickCreateState();
}

class _QuickCreateState extends State<QuickCreate> {
  late final EventDraft d = widget.draft;
  final _title = TextEditingController(), _location = TextEditingController();
  bool _saving = false;

  CalStore get store => widget.store;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  void _sync() {
    d.title = _title.text;
    d.location = _location.text;
  }

  void _more() {
    _sync();
    Navigator.pop(context);
    widget.onMore(d);
  }

  Future<void> _save() async {
    _sync();
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await store.create({'id': calId(), ...d.body()});
      nav.pop();
    } catch (e) {
      messenger?.showSnackBar(toast(Text('$e')));
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _meeting() async {
    final t = widget.mmToken;
    if (t == null) return _more();
    try {
      final c = await createHopRoom(mmToken: t, title: _title.text.trim(), startMs: msOfWall(d.start, d.tz), endMs: msOfWall(d.end, d.tz));
      if (mounted) setState(() => d.conference = c);
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$e')));
    }
  }

  Widget _row(IconData icon, Widget child, {VoidCallback? onTap, Key? key}) => InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            SizedBox(width: 38, child: Icon(icon, size: 21, color: Pal.of(context).sub)),
            Expanded(child: child),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cal = store.calendar(d.calendarId);
    final when = d.allDay
        ? (sameDay(d.start, addDays(d.end, -1)) ? dayLong(d.start, now: store.today) : '${dayLong(d.start)} – ${dayLong(addDays(d.end, -1))}')
        : '${dayLong(d.start, now: store.today)} · ${hm(d.start)} – ${hm(d.end)}';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 18, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.drag_handle_rounded, color: pal.sub),
          const Spacer(),
          IconButton(tooltip: tr('Đóng'), icon: Icon(Icons.close_rounded, color: pal.sub), onPressed: () => Navigator.pop(context)),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 38),
          child: TextField(
            key: const ValueKey('qc-title'),
            controller: _title,
            autofocus: true,
            style: const TextStyle(fontSize: 21),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: tr('Thêm tiêu đề'),
              isDense: true,
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: pal.divider)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: calAccent(context), width: 2)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 38, top: 12, bottom: 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: calAccentSoft(context), borderRadius: BorderRadius.circular(8)),
              child: Text(tr('Sự kiện'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: calAccent(context))),
            ),
          ]),
        ),
        _row(
          Icons.schedule_rounded,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(when, style: const TextStyle(fontSize: 14)),
            Text('${tr(rruleText(d.rrule, d.start))} · ${tzById(d.tz)?.name ?? d.tz}', style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ]),
          onTap: _more,
        ),
        _row(Icons.people_outline_rounded, Text(tr('Thêm khách'), style: TextStyle(fontSize: 14, color: pal.sub)), onTap: _more, key: const ValueKey('qc-guests')),
        if (store.hop)
          _row(
            Icons.videocam_outlined,
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kCalTeal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: d.conference == null ? _meeting : null,
                icon: const Icon(Icons.videocam_rounded, size: 20),
                label: Text(d.conference == null ? tr('Thêm cuộc họp trên Họp') : 'hop/${d.conference!.code}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        _row(
          Icons.place_outlined,
          TextField(
            key: const ValueKey('qc-location'),
            controller: _location,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(hintText: tr('Thêm địa điểm'), isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
          ),
        ),
        _row(
          Icons.calendar_today_outlined,
          Row(children: [
            PopupMenuButton<String>(
              key: const ValueKey('qc-calendar'),
              tooltip: tr('Chọn lịch'),
              onSelected: (v) => setState(() => d.calendarId = v),
              itemBuilder: (_) => [for (final c in store.writable) PopupMenuItem(value: c.id, child: Text(c.name))],
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(cal?.name ?? tr('Lịch'), style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 10),
                Container(width: 12, height: 12, decoration: BoxDecoration(color: eventColor(cal?.shownColor, calDark(context)), shape: BoxShape.circle)),
              ]),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text('· ${d.busy ? tr('Bận') : tr('Rảnh')} · ${tr('Mặc định')}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.sub))),
          ]),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            key: const ValueKey('qc-more'),
            onPressed: _more,
            child: Text(tr('Tuỳ chọn khác'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: calAccent(context))),
          ),
          const SizedBox(width: 10),
          FilledButton(key: const ValueKey('qc-save'), style: calPrimary(context), onPressed: _saving ? null : _save, child: Text(tr('Lưu'))),
        ]),
      ]),
    );
  }
}
