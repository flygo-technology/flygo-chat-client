// Lịch: trình sửa sự kiện đầy đủ. Máy tính: hai cột (bên trái ngày giờ, lặp lại, tab "Chi tiết sự kiện" / "Tìm thời gian";
// bên phải khách mời, quyền của khách, giờ cả nhóm rảnh). Điện thoại: một cột. Chưa lưu gì cho tới khi bấm Lưu; sửa sự
// kiện lặp thì hỏi phạm vi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../app_route.dart';
import '../common.dart' show pickFilesOrReport;
import '../theme.dart';
import 'event_detail.dart' show askScope;
import 'hop.dart';
import 'look.dart';
import 'model.dart';
import 'people.dart';
import 'recurrence.dart';
import 'store.dart';
import 'tz.dart';

/// Bản nháp đang sửa. [start] / [end] là giờ tường theo [tz]; cả ngày thì [end] là ngày sau ngày cuối (không tính).
class EventDraft {
  EventDraft({
    this.id,
    required this.calendarId,
    this.title = '',
    this.description = '',
    this.location = '',
    this.allDay = false,
    required this.start,
    required this.end,
    this.tz = kDefaultTz,
    this.rrule,
    this.busy = true,
    this.visibility = 'default',
    this.color,
    this.conference,
    List<CAttendee>? guests,
    Map<String, bool>? guestPerms,
    List<CFile>? files,
    List<CReminder>? reminders,
  })  : guests = guests ?? [],
        guestPerms = guestPerms ?? {'modify': false, 'invite': true, 'see_guests': true},
        files = files ?? [],
        reminders = reminders ?? [];

  String? id;
  String calendarId, title, description, location, tz, visibility;
  bool allDay, busy;
  DateTime start, end;
  String? rrule, color;
  CConference? conference;
  List<CAttendee> guests;
  Map<String, bool> guestPerms;
  List<CFile> files;
  List<CReminder> reminders;

  factory EventDraft.fromEvent(CEvent e) => EventDraft(
        id: e.id,
        calendarId: e.calendarId,
        title: e.title,
        description: e.description,
        location: e.location,
        allDay: e.allDay,
        start: parseLocal(e.start),
        end: e.end.isEmpty ? parseLocal(e.start).add(Duration(hours: e.allDay ? 24 : 1)) : parseLocal(e.end),
        tz: e.tz,
        rrule: e.rrule,
        busy: e.busy,
        visibility: e.visibility,
        color: e.color,
        conference: e.conference,
        guests: [for (final a in e.attendees) CAttendee.fromJson(a.toJson())],
        guestPerms: {...e.guestPerms},
        files: [...e.attachments],
        reminders: [...e.reminders],
      );

  /// Sự kiện mới: mặc định nửa giờ tới, dài theo cài đặt, lịch chính, lời nhắc mặc định.
  factory EventDraft.blank(CalStore s, {DateTime? start, DateTime? end, bool allDay = false}) {
    final now = s.nowWall;
    final st = start ?? DateTime.utc(now.year, now.month, now.day, now.hour, now.minute < 30 ? 30 : 0).add(Duration(hours: now.minute < 30 ? 0 : 1));
    final en = end ?? (allDay ? addDays(dayOf(st), 1) : st.add(Duration(minutes: s.settings.defaultDuration)));
    final cal = s.primary ?? (s.writable.isEmpty ? null : s.writable.first);
    return EventDraft(
      calendarId: cal?.id ?? s.primaryId,
      start: allDay ? dayOf(st) : st,
      end: en,
      allDay: allDay,
      tz: s.tz,
      reminders: [...(cal?.defaultReminders.isNotEmpty ?? false ? cal!.defaultReminders : s.settings.defaultReminders)],
    );
  }

  Map<String, dynamic> body() => {
        'calendar_id': calendarId,
        'title': title.trim(),
        'description': description,
        'location': location.trim(),
        'all_day': allDay,
        'start': allDay ? fmtDate(start) : fmtLocal(start),
        'end': allDay ? fmtDate(end) : fmtLocal(end),
        'tz': tz,
        'rrule': rrule,
        'busy': busy,
        'visibility': visibility,
        'color': color,
        'conference': conference?.toJson(),
        'attendees': [for (final g in guests) if (!g.organizer) {'principal': g.principal, 'optional': g.optional}],
        'guest_perms': guestPerms,
        'attachments': [for (final f in files) f.id],
        'reminders': [for (final r in reminders) r.toJson()],
      };
}

/// Mở trình sửa. [event] = lần xảy ra đang sửa (null = sự kiện mới). Trả true nếu đã lưu.
Future<bool?> openEditor(BuildContext context, CalStore store, {CEvent? event, EventDraft? draft, String? mmToken}) =>
    Navigator.of(context).push<bool>(AppPageRoute(
        fullscreenDialog: true,
        builder: (_) => EventEditor(store: store, event: event, draft: draft ?? (event != null ? EventDraft.fromEvent(event) : EventDraft.blank(store)), mmToken: mmToken)));

class EventEditor extends StatefulWidget {
  const EventEditor({super.key, required this.store, required this.draft, this.event, this.mmToken});
  final CalStore store;
  final EventDraft draft;
  final CEvent? event;
  /// Token chat để tạo phòng Họp (null = không tạo được).
  final String? mmToken;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  late final EventDraft d = widget.draft;
  /// Bản gốc lúc mở (so với lúc lưu để chỉ gửi trường đã đổi).
  late final Map<String, dynamic> _orig;
  late final _title = TextEditingController(text: d.title);
  late final _location = TextEditingController(text: d.location);
  late final _desc = TextEditingController(text: d.description);
  int _tab = 0;
  bool _saving = false, _uploading = false;
  List<CSlot> _hint = [];
  Timer? _hintTimer;
  // Tab "Tìm thời gian".
  DateTime? _fbDay;
  Map<String, List<(int, int)>> _busy = {};
  Map<String, String> _names = {};
  bool _fbLoading = false;
  /// Tăng mỗi lần vẽ lại: bảng "Tìm thời gian" mở riêng trên điện thoại vẽ lại theo.
  final _rev = ValueNotifier(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

  CalStore get store => widget.store;
  bool get _isNew => widget.event == null;
  List<String> get _guestIds => [for (final g in d.guests) if (!g.isChannel && !g.organizer && g.id != store.meId) g.id];

  @override
  void initState() {
    super.initState();
    _orig = jsonDecode(jsonEncode(d.body())) as Map<String, dynamic>;
    if (d.guests.isNotEmpty) _loadHint();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _rev.dispose();
    _title.dispose();
    _location.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _toast(Object m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$m')));

  // ------------------------------------------------------------ giờ
  void _setStart(DateTime s) => setState(() {
        final len = d.end.difference(d.start);
        d.start = s;
        d.end = s.add(len);
        _scheduleHint();
      });

  void _setEnd(DateTime e) => setState(() {
        if (!e.isAfter(d.start)) e = d.start.add(d.allDay ? const Duration(days: 1) : const Duration(minutes: 15));
        d.end = e;
        _scheduleHint();
      });

  void _setAllDay(bool v) => setState(() {
        if (v == d.allDay) return;
        d.allDay = v;
        if (v) {
          d.start = dayOf(d.start);
          d.end = addDays(dayOf(d.end.subtract(const Duration(minutes: 1))), 1);
          if (!d.end.isAfter(d.start)) d.end = addDays(d.start, 1);
        } else {
          final work = CSettings.minutesOf(store.settings.workStart);
          d.start = d.start.add(Duration(minutes: work + 60));
          d.end = d.start.add(Duration(minutes: store.settings.defaultDuration));
        }
      });

  Future<DateTime?> _pickDate(DateTime cur) async {
    final r = await showDatePicker(context: context, initialDate: DateTime(cur.year, cur.month, cur.day), firstDate: DateTime(1970), lastDate: DateTime(2100));
    return r == null ? null : DateTime.utc(r.year, r.month, r.day);
  }

  static String _len(Duration x) {
    final m = x.inMinutes;
    if (m < 60) return '$m phút';
    final h = m / 60;
    return '${h == h.roundToDouble() ? h.toInt() : h.toStringAsFixed(1).replaceAll('.', ',')} giờ';
  }

  /// Menu giờ (mỗi 15 phút) cạnh ô [anchor]. [from] != null: chọn giờ kết thúc, hiện độ dài.
  Future<DateTime?> _pickTime(BuildContext anchor, DateTime cur, {DateTime? from}) {
    final box = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(box.localToGlobal(Offset(0, box.size.height), ancestor: overlay) & box.size, Offset.zero & overlay.size);
    final day = dayOf(cur);
    final items = <DateTime>[];
    if (from != null) {
      for (var t = from.add(const Duration(minutes: 15)); t.difference(from).inMinutes <= 24 * 60; t = t.add(const Duration(minutes: 15))) {
        items.add(t);
      }
    } else {
      for (var m = 0; m < 24 * 60; m += 15) {
        items.add(day.add(Duration(minutes: m)));
      }
    }
    final initial = items.where((t) => !t.isBefore(cur)).firstOrNull;
    return showMenu<DateTime>(
      context: context,
      position: pos,
      initialValue: initial,
      constraints: const BoxConstraints(maxHeight: 320, minWidth: 140),
      items: [
        for (final t in items)
          PopupMenuItem(
            value: t,
            height: 36,
            child: Text(from == null ? hm(t) : '${hm(t)}  (${tr(_len(t.difference(from)))})', style: const TextStyle(fontSize: 13.5)),
          ),
      ],
    );
  }

  Widget _timeRow({bool phone = false}) {
    final startDate = pill(context, dmy(d.start), key: const ValueKey('ed-start-date'), onTap: () async {
      final r = await _pickDate(d.start);
      if (r != null) _setStart(r.add(Duration(hours: d.start.hour, minutes: d.start.minute)));
    });
    final lastDay = d.allDay ? addDays(d.end, -1) : d.end;
    final endDate = pill(context, dmy(lastDay), key: const ValueKey('ed-end-date'), onTap: () async {
      final r = await _pickDate(lastDay);
      if (r != null) _setEnd(d.allDay ? addDays(r, 1) : r.add(Duration(hours: d.end.hour, minutes: d.end.minute)));
    });
    Widget startTime = Builder(
        builder: (bc) => pill(context, hm(d.start), key: const ValueKey('ed-start-time'), onTap: () async {
              final t = await _pickTime(bc, d.start);
              if (t != null) _setStart(t);
            }));
    Widget endTime = Builder(
        builder: (bc) => pill(context, hm(d.end), key: const ValueKey('ed-end-time'), onTap: () async {
              final t = await _pickTime(bc, d.end, from: d.start);
              if (t != null) _setEnd(t);
            }));
    final dash = Text('–', style: TextStyle(color: Pal.of(context).sub));
    if (phone) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: startDate)), if (!d.allDay) startTime]),
        const SizedBox(height: 6),
        Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: endDate)), if (!d.allDay) endTime]),
      ]);
    }
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      startDate,
      if (!d.allDay) startTime,
      dash,
      if (!d.allDay) endTime,
      endDate,
      if (!d.allDay) _tzPicker(),
    ]);
  }

  Widget _tzPicker() => ChipMenu<String>(
        key: const ValueKey('ed-tz'),
        leading: Icon(Icons.public_rounded, size: 17, color: Pal.of(context).sub),
        label: tzLabel(d.tz, msOfWall(d.start, d.tz)),
        items: [for (final z in kTimezones) (z.id, tzLabel(z.id, msOfWall(d.start, z.id)))],
        onSelected: (v) => setState(() => d.tz = v),
      );

  // ------------------------------------------------------------ khách
  void _addGuest(Picked p) => setState(() {
        if (d.guests.any((g) => g.principal == p.principal)) return;
        d.guests.add(CAttendee(principal: p.principal, id: p.id, name: p.name));
        _scheduleHint();
        if (_tab == 1) _loadBusy();
      });

  void _scheduleHint() {
    _hintTimer?.cancel();
    if (d.guests.isEmpty) {
      _hint = [];
      return;
    }
    _hintTimer = Timer(const Duration(milliseconds: 500), _loadHint);
  }

  Future<void> _loadHint() async {
    final ids = _guestIds;
    if (ids.isEmpty) return;
    try {
      final from = dayOf(d.start).isBefore(store.today) ? store.today : dayOf(d.start);
      final r = await store.api.findTime([store.meId, ...ids],
          from: fmtDate(from), to: fmtDate(addDays(from, 7)), duration: d.allDay ? 60 : d.end.difference(d.start).inMinutes.clamp(15, 600), limit: 3);
      if (mounted) setState(() => _hint = r);
    } catch (_) {}
  }

  void _useSlot(CSlot s) {
    final st = wallOf(s.startMs, d.tz), en = wallOf(s.endMs, d.tz);
    setState(() {
      d.allDay = false;
      d.start = st;
      d.end = en;
      _fbDay = dayOf(st);
    });
  }

  String _slotText(CSlot s) {
    final st = wallOf(s.startMs, store.tz), en = wallOf(s.endMs, store.tz);
    final day = sameDay(st, store.today) ? tr('Hôm nay') : sameDay(st, addDays(store.today, 1)) ? tr('Ngày mai') : dowLong(st);
    return '$day ${hm(st)} – ${hm(en)}';
  }

  Widget _guestsPanel() {
    final pal = Pal.of(context);
    final counts = <String, int>{};
    for (final g in d.guests) {
      counts[g.rsvp] = (counts[g.rsvp] ?? 0) + 1;
    }
    final hasOrg = d.guests.any((g) => g.organizer);
    final total = d.guests.length + (hasOrg || d.guests.isEmpty ? 0 : 1);
    final summary = [
      tr('{0} khách', [total]),
      if ((counts['yes'] ?? 0) > 0) tr('{0} có', [counts['yes']]),
      if ((counts['no'] ?? 0) > 0) tr('{0} không', [counts['no']]),
      if ((counts['needs'] ?? 0) > 0) tr('{0} đang chờ', [counts['needs']]),
    ].join(' · ');
    Widget row(CAttendee g, {bool me = false}) => Padding(
          key: ValueKey('guest-${g.principal}'),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            personAvatar(context, g.name, r: 16, rsvp: g.isChannel ? 'needs' : g.rsvp, channel: g.isChannel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                if (g.organizer || g.optional || g.isChannel)
                  Text(g.organizer ? tr('Người tổ chức') : g.isChannel ? tr('Kênh') : tr('Khách tuỳ chọn'), style: TextStyle(fontSize: 11.5, color: pal.sub)),
              ]),
            ),
            if (!g.organizer && !me) ...[
              PopupMenuButton<String>(
                tooltip: tr('Tuỳ chọn'),
                icon: Icon(Icons.more_horiz_rounded, size: 18, color: pal.sub),
                onSelected: (_) => setState(() => g.optional = !g.optional),
                itemBuilder: (_) => [PopupMenuItem(value: 'opt', child: Text(g.optional ? tr('Đánh dấu bắt buộc') : tr('Đánh dấu tuỳ chọn')))],
              ),
              IconButton(
                key: ValueKey('guest-x-${g.principal}'),
                tooltip: tr('Bỏ khách'),
                icon: Icon(Icons.close_rounded, size: 18, color: pal.sub),
                onPressed: () => setState(() {
                  d.guests.remove(g);
                  _scheduleHint();
                }),
              ),
            ],
          ]),
        );
    Widget perm(String k, String label) => InkWell(
          onTap: () => setState(() => d.guestPerms[k] = !(d.guestPerms[k] ?? false)),
          child: Row(children: [
            Checkbox(value: d.guestPerms[k] ?? false, onChanged: (v) => setState(() => d.guestPerms[k] = v ?? false)),
            Text(tr(label), style: const TextStyle(fontSize: 14)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('Khách'), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      PeopleSearch(store: store, onPick: _addGuest, exclude: {for (final g in d.guests) g.principal, 'mm:${store.meId}'}),
      if (d.guests.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(summary, style: TextStyle(fontSize: 12.5, color: pal.sub)),
        const SizedBox(height: 4),
        if (!hasOrg) row(CAttendee(principal: 'mm:${store.meId}', id: store.meId, name: store.meName, rsvp: 'yes', organizer: true), me: true),
        for (final g in [...d.guests]..sort((a, b) => (b.organizer ? 1 : 0) - (a.organizer ? 1 : 0))) row(g),
        const SizedBox(height: 12),
        Text(tr('Khách có quyền'), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        perm('modify', 'Sửa sự kiện'),
        perm('invite', 'Mời người khác'),
        perm('see_guests', 'Xem danh sách khách'),
        if (_hint.isNotEmpty)
          Container(
            key: const ValueKey('free-hint'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: calAccentSoft(context), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: calAccent(context)),
                const SizedBox(width: 6),
                Text(tr('Giờ cả nhóm rảnh'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: calAccent(context))),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 2, children: [
                for (final (i, s) in _hint.indexed)
                  InkWell(
                    onTap: () => _useSlot(s),
                    child: Text('${i > 0 ? '· ' : ''}${_slotText(s)}', style: TextStyle(fontSize: 13, color: pal.text, decoration: TextDecoration.underline, decorationColor: pal.sub)),
                  ),
              ]),
            ]),
          ),
      ],
    ]);
  }

  // ------------------------------------------------------------ tìm thời gian
  Future<void> _loadBusy() async {
    final day = _fbDay ??= dayOf(d.start);
    setState(() => _fbLoading = true);
    try {
      final (b, n) = await store.api.freebusy([store.meId, ..._guestIds], from: fmtLocal(day), to: fmtLocal(addDays(day, 1)), tz: store.tz);
      if (mounted) {
        setState(() {
          _busy = b;
          _names = n;
        });
      }
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _fbLoading = false);
    }
  }

  Widget _findTime() {
    final pal = Pal.of(context);
    final day = _fbDay ?? dayOf(d.start);
    final from = (CSettings.minutesOf(store.settings.workStart) ~/ 60 - 1).clamp(0, 22);
    final to = ((CSettings.minutesOf(store.settings.workEnd) + 59) ~/ 60 + 1).clamp(from + 2, 24);
    final people = [store.meId, ..._guestIds];
    String name(String id) => id == store.meId ? tr('Bạn') : (_names[id] ?? d.guests.where((g) => g.id == id).firstOrNull?.name ?? id);
    final evStart = msOfWall(d.start, d.tz), evEnd = msOfWall(d.end, d.tz);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () {
          _fbDay = addDays(day, -1);
          _loadBusy();
        }),
        Text(dayLong(day, now: store.today), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () {
          _fbDay = addDays(day, 1);
          _loadBusy();
        }),
        if (_fbLoading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      Text(tr('Chạm vào chỗ trống để đặt giờ'), style: TextStyle(fontSize: 12, color: pal.sub)),
      const SizedBox(height: 8),
      Row(children: [
        const SizedBox(width: 120),
        Expanded(
          child: Row(children: [
            for (var h = from; h < to; h++) Expanded(child: Text('$h', style: TextStyle(fontSize: 10.5, color: pal.sub))),
          ]),
        ),
      ]),
      for (final id in people)
        Padding(
          key: ValueKey('fb-$id'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 120, child: Text(name(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                final dayMs = msOfWall(day, store.tz);
                double x(int ms) => ((ms - dayMs) / 60000 / 60 - from) / (to - from) * w;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (t) {
                    final h = from + t.localPosition.dx / w * (to - from);
                    final m = (h * 60 / 30).floor() * 30;
                    _setStart(wallOf(dayMs + m * 60000, d.tz));
                    setState(() => d.allDay = false);
                  },
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(6)),
                    child: Stack(clipBehavior: Clip.hardEdge, children: [
                      for (final (s, e) in _busy[id] ?? const <(int, int)>[])
                        Positioned(
                          left: x(s).clamp(0, w),
                          width: (x(e) - x(s)).clamp(0, w),
                          top: 0,
                          bottom: 0,
                          child: Container(decoration: BoxDecoration(color: pal.sub.withValues(alpha: .45), borderRadius: BorderRadius.circular(4))),
                        ),
                      if (!d.allDay)
                        Positioned(
                          left: x(evStart).clamp(0, w),
                          width: (x(evEnd) - x(evStart)).clamp(2, w),
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(decoration: BoxDecoration(border: Border.all(color: calAccent(context), width: 2), borderRadius: BorderRadius.circular(4))),
                          ),
                        ),
                    ]),
                  ),
                );
              }),
            ),
          ]),
        ),
      if (people.length == 1) Padding(padding: const EdgeInsets.only(top: 10), child: Text(tr('Thêm khách để xem giờ bận của họ'), style: TextStyle(color: pal.sub, fontSize: 13))),
    ]);
  }

  // ------------------------------------------------------------ các dòng chi tiết
  Widget _iconRow(IconData icon, Widget child, {double top = 14}) => Padding(
        padding: EdgeInsets.only(top: top),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 38, child: Padding(padding: const EdgeInsets.only(top: 8), child: Icon(icon, size: 21, color: Pal.of(context).sub))),
          Expanded(child: child),
        ]),
      );

  InputDecoration _fill(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Pal.of(context).surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      );

  Future<void> _addMeeting() async {
    final t = widget.mmToken;
    if (t == null) return _toast(tr('Không tạo được phòng họp ở đây'));
    try {
      final c = await createHopRoom(
          mmToken: t, title: _title.text.trim(), startMs: msOfWall(d.start, d.tz), endMs: msOfWall(d.end, d.tz), invitees: _guestIds, eventId: d.id);
      if (mounted) setState(() => d.conference = c);
    } catch (e) {
      _toast(e);
    }
  }

  Widget _meetingRow() {
    final pal = Pal.of(context);
    final c = d.conference;
    if (c == null && !store.hop) return const SizedBox.shrink();
    return _iconRow(
        Icons.videocam_outlined,
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, children: [
          FilledButton.icon(
            key: const ValueKey('ed-hop'),
            style: FilledButton.styleFrom(backgroundColor: kCalTeal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: c == null ? _addMeeting : null,
            icon: const Icon(Icons.videocam_rounded, size: 20),
            label: Text(c == null ? tr('Thêm cuộc họp trên Họp') : tr('Vào cuộc họp trên Họp'), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (c != null) ...[
            Text('hop/${c.code}', style: TextStyle(fontSize: 13, color: pal.sub)),
            IconButton(tooltip: tr('Bỏ cuộc họp'), icon: Icon(Icons.close_rounded, size: 18, color: pal.sub), onPressed: () => setState(() => d.conference = null)),
          ],
        ]),
        top: 10);
  }

  Widget _remindersRow() {
    final pal = Pal.of(context);
    const units = [(1, 'phút'), (60, 'giờ'), (1440, 'ngày'), (10080, 'tuần')];
    (int, int) split(int m) {
      for (final (u, _) in units.reversed) {
        if (m >= u && m % u == 0) return (m ~/ u, u);
      }
      return (m, 1);
    }

    return _iconRow(
        Icons.notifications_none_rounded,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, r) in d.reminders.indexed)
            Padding(
              key: ValueKey('rem-$i-${r.minutes}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 64,
                  child: TextFormField(
                    initialValue: '${split(r.minutes).$1}',
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: _fill(''),
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null && n >= 0) d.reminders[i] = CReminder(n * split(r.minutes).$2);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ChipMenu<int>(
                  label: tr(units.firstWhere((u) => u.$1 == split(r.minutes).$2).$2),
                  items: [for (final (u, l) in units) (u, tr(l))],
                  onSelected: (u) => setState(() => d.reminders[i] = CReminder(split(d.reminders[i].minutes).$1 * u)),
                ),
                const SizedBox(width: 6),
                Text(tr('trước'), style: TextStyle(fontSize: 13, color: pal.sub)),
                IconButton(tooltip: tr('Bỏ lời nhắc'), icon: Icon(Icons.close_rounded, size: 18, color: pal.sub), onPressed: () => setState(() => d.reminders.removeAt(i))),
              ]),
            ),
          TextButton(
            key: const ValueKey('ed-add-reminder'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: d.reminders.length >= 5 ? null : () => setState(() => d.reminders.add(CReminder(d.allDay ? 1440 : 30))),
            child: Text(tr('Thêm lời nhắc'), style: TextStyle(color: calAccent(context), fontWeight: FontWeight.w600)),
          ),
        ]),
        top: 12);
  }

  Widget _calendarRow() {
    final dark = calDark(context);
    final cals = store.writable;
    final cur = store.calendar(d.calendarId);
    return _iconRow(
        Icons.calendar_today_outlined,
        Wrap(spacing: 10, runSpacing: 8, children: [
          ChipMenu<String>(
            key: const ValueKey('ed-calendar'),
            leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: eventColor(cur?.shownColor, dark), shape: BoxShape.circle)),
            label: cur?.name ?? tr('Lịch'),
            items: [for (final c in cals) (c.id, c.name)],
            onSelected: (v) => setState(() => d.calendarId = v),
          ),
          ChipMenu<String>(
            key: const ValueKey('ed-color'),
            leading: d.color == null ? null : Container(width: 12, height: 12, decoration: BoxDecoration(color: eventColor(d.color, dark), shape: BoxShape.circle)),
            label: d.color == null ? tr('Màu: Theo lịch') : tr('Màu: {0}', [tr(kColorNames[d.color] ?? d.color!)]),
            items: [('', tr('Theo lịch')), for (final e in kColorNames.entries) (e.key, tr(e.value))],
            onSelected: (v) => setState(() => d.color = v.isEmpty ? null : v),
          ),
          ChipMenu<bool>(
            key: const ValueKey('ed-busy'),
            label: d.busy ? tr('Bận') : tr('Rảnh'),
            items: [(true, tr('Bận')), (false, tr('Rảnh'))],
            onSelected: (v) => setState(() => d.busy = v),
          ),
          ChipMenu<String>(
            key: const ValueKey('ed-visibility'),
            label: tr(const {'default': 'Hiển thị mặc định', 'public': 'Công khai', 'private': 'Riêng tư'}[d.visibility] ?? 'Hiển thị mặc định'),
            items: [('default', tr('Hiển thị mặc định')), ('public', tr('Công khai')), ('private', tr('Riêng tư'))],
            onSelected: (v) => setState(() => d.visibility = v),
          ),
        ]),
        top: 10);
  }

  Future<void> _attach() async {
    final r = await pickFilesOrReport(context, type: FileType.any);
    if (r.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      for (final f in r) {
        if (f.path == null) continue;
        final up = await store.api.upload(f.name, await File(f.path!).readAsBytes());
        if (mounted) setState(() => d.files.add(up));
      }
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _filesRow() => _iconRow(
      Icons.attach_file_rounded,
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final f in d.files)
          InputChip(
            avatar: const Icon(Icons.description_outlined, size: 16, color: Color(0xFFE5484D)),
            label: Text('${f.name} · ${fileSize(f.size)}', style: const TextStyle(fontSize: 12.5)),
            onDeleted: () => setState(() => d.files.remove(f)),
          ),
        if (_uploading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        TextButton(onPressed: _uploading ? null : _attach, child: Text(tr('Thêm tệp'), style: TextStyle(color: calAccent(context), fontWeight: FontWeight.w600))),
      ]),
      top: 10);

  Widget _descField() => TextField(
        key: const ValueKey('ed-desc'),
        controller: _desc,
        minLines: 4,
        maxLines: 12,
        style: const TextStyle(fontSize: 14, height: 1.45),
        decoration: InputDecoration(
          hintText: tr('Thêm nội dung'),
          contentPadding: const EdgeInsets.all(14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Pal.of(context).divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Pal.of(context).divider)),
        ),
      );

  List<Widget> _details() => [
        _meetingRow(),
        _iconRow(Icons.place_outlined, TextField(key: const ValueKey('ed-location'), controller: _location, decoration: _fill(tr('Thêm địa điểm'))), top: 12),
        _remindersRow(),
        _calendarRow(),
        _iconRow(Icons.notes_rounded, _descField()),
        _filesRow(),
      ];

  // ------------------------------------------------------------ lưu
  Future<void> _save() async {
    if (_saving) return;
    d.title = _title.text;
    d.location = _location.text;
    d.description = _desc.text;
    final body = d.body();
    setState(() => _saving = true);
    try {
      if (_isNew) {
        await store.create({'id': d.id ?? calId(), ...body});
      } else {
        final e = widget.event!;
        final diff = <String, dynamic>{
          for (final k in body.keys)
            if (k != 'calendar_id' && k != 'reminders' && jsonEncode(body[k]) != jsonEncode(_orig[k])) k: body[k],
        };
        // Đổi giờ thì gửi cả đầu lẫn cuối (máy chủ tính lại).
        if (diff.containsKey('start') || diff.containsKey('end') || diff.containsKey('all_day')) {
          diff['start'] = body['start'];
          diff['end'] = body['end'];
          diff['all_day'] = body['all_day'];
          diff['tz'] = body['tz'];
        }
        if (diff.isNotEmpty) {
          var scope = 'all', notify = true;
          final guests = d.guests.where((g) => !g.organizer).length;
          if (e.recurring) {
            final r = await askScope(context,
                title: tr('Sửa sự kiện định kỳ'), guests: guests, options: diff.containsKey('rrule') ? const ['following', 'all'] : const ['this', 'following', 'all']);
            if (r == null) return;
            (scope, notify) = r;
          }
          await store.update(e, {...diff, 'notify': notify}, scope: scope);
        }
        if (jsonEncode(body['reminders']) != jsonEncode(_orig['reminders'])) await store.setReminders(e, d.reminders);
        if (body['calendar_id'] != _orig['calendar_id']) await store.moveToCalendar(e, d.calendarId);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _toast(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------ khung
  Widget _tabs() {
    final pal = Pal.of(context);
    Widget t(int i, String label) => InkWell(
          key: ValueKey('ed-tab-$i'),
          onTap: () {
            setState(() => _tab = i);
            if (i == 1) _loadBusy();
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            margin: const EdgeInsets.only(right: 22),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _tab == i ? calAccent(context) : Colors.transparent, width: 2.5))),
            child: Text(tr(label), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _tab == i ? calAccent(context) : pal.sub)),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
      child: Row(children: [t(0, 'Chi tiết sự kiện'), t(1, 'Tìm thời gian')]),
    );
  }

  Widget _allDayAndRepeat() => Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        InkWell(
          key: const ValueKey('ed-allday'),
          onTap: () => _setAllDay(!d.allDay),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(value: d.allDay, onChanged: (v) => _setAllDay(v ?? false)),
            Text(tr('Cả ngày'), style: const TextStyle(fontSize: 14.5)),
          ]),
        ),
        RecurrencePicker(value: d.rrule, start: d.start, onChanged: (v) => setState(() => d.rrule = v)),
      ]);

  Widget _titleField({double size = 22}) => TextField(
        key: const ValueKey('ed-title'),
        controller: _title,
        autofocus: _isNew,
        style: TextStyle(fontSize: size),
        decoration: InputDecoration(
          hintText: tr('Thêm tiêu đề'),
          isDense: true,
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Pal.of(context).divider)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: calAccent(context), width: 2)),
        ),
      );

  Widget _saveButton() => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilledButton(
          key: const ValueKey('ed-save'),
          style: calPrimary(context).copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 26, vertical: 12))),
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(tr('Lưu')),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (!calWide(context)) return _phone(context);
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
            child: Row(children: [
              IconButton(key: const ValueKey('ed-close'), tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 12),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: SizedBox(width: 640, child: _titleField())),
              const Spacer(),
              _saveButton(),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(64, 16, 32, 32),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _timeRow(),
                        const SizedBox(height: 8),
                        _allDayAndRepeat(),
                        _tabs(),
                        if (_tab == 0) ..._details() else Padding(padding: const EdgeInsets.only(top: 14), child: _findTime()),
                      ]),
                    ),
                    const SizedBox(width: 32),
                    SizedBox(width: 330, child: _guestsPanel()),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _phone(BuildContext context) {
    final pal = Pal.of(context);
    final div = Divider(height: 24, color: pal.divider);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(key: const ValueKey('ed-close'), tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        actions: [_saveButton()],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Padding(padding: const EdgeInsets.only(left: 38), child: _titleField(size: 21)),
        div,
        _iconRow(
            Icons.schedule_rounded,
            Row(children: [
              Expanded(child: Text(tr('Cả ngày'), style: const TextStyle(fontSize: 14.5))),
              Switch(key: const ValueKey('ed-allday'), value: d.allDay, onChanged: _setAllDay),
            ]),
            top: 0),
        Padding(padding: const EdgeInsets.only(left: 38, top: 6), child: _timeRow(phone: true)),
        if (!d.allDay) _iconRow(Icons.public_rounded, Align(alignment: Alignment.centerLeft, child: _tzPicker()), top: 10),
        _iconRow(Icons.sync_rounded, Align(alignment: Alignment.centerLeft, child: RecurrencePicker(value: d.rrule, start: d.start, onChanged: (v) => setState(() => d.rrule = v))), top: 10),
        div,
        _meetingRow(),
        _iconRow(Icons.people_outline_rounded, _guestsPanel(), top: 12),
        if (d.guests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  _loadBusy();
                  showCalSheet<void>(context, builder: (_) => ValueListenableBuilder(valueListenable: _rev, builder: (_, _, _) => Padding(padding: const EdgeInsets.all(16), child: _findTime())));
                },
                icon: const Icon(Icons.event_available_outlined),
                label: Text(tr('Tìm thời gian')),
              ),
            ),
          ),
        ..._details().skip(1),
      ]),
    );
  }
}
