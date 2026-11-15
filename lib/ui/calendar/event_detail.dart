// Lịch: chi tiết sự kiện — khung nổi cạnh sự kiện (máy tính) hoặc trang riêng (điện thoại): giờ, lặp lại, nút vào cuộc
// họp, khách kèm trạng thái trả lời, lời nhắc, lịch, tệp; thanh trả lời Có / Không / Có thể khi được mời. Hộp hỏi phạm vi
// cho sự kiện lặp (Sự kiện này / này và tiếp theo / tất cả).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../app_route.dart';
import '../theme.dart';
import 'look.dart';
import 'model.dart';
import 'rrule_text.dart';
import 'store.dart';
import 'tz.dart';

/// Hỏi phạm vi sửa / xoá / trả lời của sự kiện lặp. [guests] > 0 thì có ô "Báo cho N khách". Trả (scope, notify).
Future<(String, bool)?> askScope(BuildContext context, {required String title, int guests = 0, List<String> options = const ['this', 'following', 'all']}) {
  var scope = options.first;
  var notify = true;
  const names = {'this': 'Sự kiện này', 'following': 'Sự kiện này và các sự kiện tiếp theo', 'all': 'Tất cả sự kiện'};
  return showDialog<(String, bool)>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final pal = Pal.of(c);
        return Dialog(
          backgroundColor: calDark(c) ? pal.surface : pal.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: scope,
                  onChanged: (v) => set(() => scope = v ?? scope),
                  child: Column(children: [
                    for (final o in options)
                      InkWell(
                        key: ValueKey('scope-$o'),
                        onTap: () => set(() => scope = o),
                        child: Row(children: [Radio<String>(value: o), Expanded(child: Text(tr(names[o]!), style: const TextStyle(fontSize: 14.5)))]),
                      ),
                  ]),
                ),
                if (guests > 0)
                  InkWell(
                    onTap: () => set(() => notify = !notify),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Row(children: [
                        Icon(notify ? Icons.mail_outline_rounded : Icons.notifications_off_outlined, size: 18, color: pal.sub),
                        const SizedBox(width: 10),
                        Expanded(child: Text(notify ? tr('Báo cho {0} khách qua tin nhắn', [guests]) : tr('Không báo cho khách'), style: TextStyle(fontSize: 13, color: pal.sub))),
                        SizedBox(height: 28, child: Checkbox(value: notify, onChanged: (v) => set(() => notify = v ?? true))),
                      ]),
                    ),
                  ),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Huỷ'), style: TextStyle(color: calAccent(c), fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  FilledButton(key: const ValueKey('scope-ok'), style: calPrimary(c), onPressed: () => Navigator.pop(c, (scope, notify)), child: Text(tr('OK'))),
                ]),
              ]),
            ),
          ),
        );
      },
    ),
  );
}

/// Những việc trang Lịch làm thay khung chi tiết (mở trình sửa, nhân bản, vào họp).
class DetailHooks {
  const DetailHooks({required this.onEdit, required this.onDuplicate, this.onJoin});
  final void Function(CEvent e) onEdit;
  final void Function(CEvent e) onDuplicate;
  final void Function(CEvent e)? onJoin;
}

Future<void> showEventDetail(BuildContext context, {required CalStore store, required CEvent e, Rect? anchor, required DetailHooks hooks}) {
  if (calWide(context) && anchor != null) {
    return showAnchored<void>(context, anchor: anchor, width: 448, builder: (c) => EventDetail(store: store, e: e, hooks: hooks, popover: true));
  }
  return Navigator.of(context).push(AppPageRoute(builder: (_) => EventDetail(store: store, e: e, hooks: hooks, popover: false)));
}

class EventDetail extends StatefulWidget {
  const EventDetail({super.key, required this.store, required this.e, required this.hooks, required this.popover});
  final CalStore store;
  final CEvent e;
  final DetailHooks hooks;
  final bool popover;
  @override
  State<EventDetail> createState() => _EventDetailState();
}

class _EventDetailState extends State<EventDetail> {
  late CEvent e = widget.e;
  bool _busy = false;

  CalStore get store => widget.store;

  void _toast(Object m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$m')));

  int get _guestCount => e.attendees.where((a) => !a.organizer).length;

  Future<void> _delete() async {
    var scope = 'all', notify = true;
    if (e.recurring) {
      final r = await askScope(context, title: tr('Xoá sự kiện định kỳ'), guests: _guestCount);
      if (r == null) return;
      (scope, notify) = r;
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    nav.pop();
    try {
      await store.remove(e, scope: scope, notify: notify);
      messenger?.showSnackBar(toast(Text(tr('Đã xoá sự kiện'))));
    } catch (err) {
      messenger?.showSnackBar(toast(Text('$err')));
    }
  }

  Future<void> _rsvp(String v) async {
    var scope = 'all';
    if (e.recurring) {
      final r = await askScope(context, title: tr('Trả lời sự kiện định kỳ'), options: const ['this', 'all']);
      if (r == null) return;
      scope = r.$1;
    }
    setState(() => _busy = true);
    try {
      final r = await store.rsvp(e, v, scope: scope);
      if (mounted) setState(() => e = r);
    } catch (err) {
      _toast(err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _moveCalendar() async {
    final cals = store.writable.where((c) => c.id != e.calendarId).toList();
    if (cals.isEmpty) return _toast(tr('Không có lịch nào khác để chuyển'));
    final id = await showCalSheet<String>(
      context,
      width: 360,
      builder: (c) => ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 12), children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text(tr('Chuyển sang lịch'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        for (final cal in cals)
          ListTile(
            leading: ColorCheck(color: eventColor(cal.shownColor, calDark(c)), on: true),
            title: Text(cal.name),
            onTap: () => Navigator.pop(c, cal.id),
          ),
      ]),
    );
    if (id == null || !mounted) return;
    try {
      final r = await store.moveToCalendar(e, id);
      if (mounted) setState(() => e = r);
      _toast(tr('Đã chuyển sang lịch {0}', [store.calendar(id)?.name ?? '']));
    } catch (err) {
      _toast(err);
    }
  }

  void _more(String a) {
    switch (a) {
      case 'dup':
        Navigator.of(context).pop();
        widget.hooks.onDuplicate(e);
      case 'move':
        _moveCalendar();
      case 'copy':
        final s = e.wallStart(store.tz);
        Clipboard.setData(ClipboardData(
            text: [e.title, '${dayLong(s)} · ${timeRange(e, store.tz)}', if (e.location.isNotEmpty) e.location, if (e.conference?.url.isNotEmpty ?? false) e.conference!.url].join('\n')));
        _toast(tr('Đã sao chép thông tin sự kiện'));
    }
  }

  // ------------------------------------------------------------ phần thân
  Widget _row(IconData icon, Widget child, {double top = 0}) {
    final pal = Pal.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 14 + top),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 40, child: Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 21, color: pal.sub))),
        Expanded(child: child),
      ]),
    );
  }

  List<Widget> _body() {
    final pal = Pal.of(context);
    final c = eventColor(store.colorOf(e), calDark(context));
    final s = e.wallStart(store.tz);
    final cal = store.calendarOf(e);
    final when = e.showsAllDay(store.tz) && !sameDay(s, addDays(e.wallEnd(store.tz), -1))
        ? timeRange(e, store.tz)
        : '${dayLong(s, now: store.today)}${e.allDay ? '' : ' · ${timeRange(e, store.tz)}'}';
    final rtext = e.recurring ? (e.rruleText.isNotEmpty ? e.rruleText : rruleText(e.rrule, s)) : null;
    final counts = <String, int>{};
    for (final a in e.attendees) {
      counts[a.rsvp] = (counts[a.rsvp] ?? 0) + 1;
    }
    final summary = [
      if ((counts['yes'] ?? 0) > 0) tr('{0} có', [counts['yes']]),
      if ((counts['no'] ?? 0) > 0) tr('{0} không', [counts['no']]),
      if ((counts['maybe'] ?? 0) > 0) tr('{0} có thể', [counts['maybe']]),
      if ((counts['needs'] ?? 0) > 0) tr('{0} đang chờ', [counts['needs']]),
    ].join(', ');
    final showGuests = e.attendees.isNotEmpty && (e.canEdit || e.guestPerms['see_guests'] != false);
    final orgFirst = [...e.attendees]..sort((a, b) => (b.organizer ? 1 : 0) - (a.organizer ? 1 : 0));
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 40, child: Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.only(top: 6, left: 4), child: Container(width: 16, height: 16, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)))))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.busyOnly ? tr('Bận') : (e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title),
                style: TextStyle(fontSize: 22, height: 1.25, color: pal.text, decoration: e.cancelled ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 4),
            Text(when, style: TextStyle(fontSize: 14, color: pal.sub)),
            if (rtext != null) Text(rtext, style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ]),
        ),
      ]),
      if (e.busyOnly)
        _row(Icons.lock_outline_rounded, Text(tr('Bạn chỉ xem được giờ bận của lịch này'), style: TextStyle(color: pal.sub)))
      else ...[
        if (e.pendingInvite && e.organizerName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14, left: 40),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.mail_outline_rounded, size: 16, color: pal.sub),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: e.organizerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: ' ${tr('mời bạn tham gia sự kiện này')}'),
                  ]), style: TextStyle(fontSize: 13, color: pal.text)),
                ),
              ]),
            ),
          ),
        if (e.conference != null)
          Padding(
            padding: const EdgeInsets.only(top: 16, left: 40),
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
              FilledButton.icon(
                key: const ValueKey('join'),
                style: FilledButton.styleFrom(backgroundColor: kCalTeal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: widget.hooks.onJoin == null ? null : () => widget.hooks.onJoin!(e),
                icon: const Icon(Icons.videocam_rounded, size: 20),
                label: Text(tr('Vào cuộc họp'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (e.conference!.code.isNotEmpty)
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: e.conference!.url.isNotEmpty ? e.conference!.url : e.conference!.code));
                    _toast(tr('Đã sao chép mã họp'));
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('hop/${e.conference!.code}', style: TextStyle(fontSize: 13, color: pal.sub)),
                    const SizedBox(width: 4),
                    Icon(Icons.copy_rounded, size: 14, color: pal.sub),
                  ]),
                ),
            ]),
          ),
        if (e.location.isNotEmpty) _row(Icons.place_outlined, SelectableText(e.location, style: const TextStyle(fontSize: 14))),
        if (showGuests)
          _row(
              Icons.people_outline_rounded,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('{0} khách', [e.attendees.length]), style: const TextStyle(fontSize: 14)),
                if (summary.isNotEmpty) Text(summary, style: TextStyle(fontSize: 12.5, color: pal.sub)),
                const SizedBox(height: 6),
                for (final a in orgFirst.take(widget.popover ? 8 : 100))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      personAvatar(context, a.name, r: 14, rsvp: a.rsvp, channel: a.isChannel),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.name, style: const TextStyle(fontSize: 14)),
                          if (a.organizer || a.optional || a.isChannel)
                            Text(a.organizer ? tr('Người tổ chức') : a.isChannel ? tr('Kênh') : tr('Khách tuỳ chọn'), style: TextStyle(fontSize: 11.5, color: pal.sub)),
                        ]),
                      ),
                    ]),
                  ),
                if (widget.popover && orgFirst.length > 8) Text(tr('và {0} người khác', [orgFirst.length - 8]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
              top: -2),
        if (e.description.trim().isNotEmpty) _row(Icons.notes_rounded, SelectableText(e.description.trim(), style: const TextStyle(fontSize: 14, height: 1.45))),
        if (e.attachments.isNotEmpty)
          _row(
              Icons.attach_file_rounded,
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final f in e.attachments)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 16),
                    label: Text('${f.name} · ${fileSize(f.size)}', style: const TextStyle(fontSize: 12.5)),
                    onPressed: () async {
                      try {
                        await launchUrl(Uri.file(await store.api.download(f)));
                      } catch (err) {
                        _toast(err);
                      }
                    },
                  ),
              ])),
        if (e.reminders.isNotEmpty)
          _row(Icons.notifications_none_rounded,
              Text('${e.reminders.map((r) => reminderText(r.minutes)).join(', ')} · ${tr('tin nhắn từ bot Lịch')}', style: const TextStyle(fontSize: 14))),
      ],
      if (cal != null) _row(Icons.calendar_today_outlined, Text(cal.name, style: const TextStyle(fontSize: 14))),
    ];
  }

  Widget _rsvpBar() {
    final pal = Pal.of(context);
    Widget b(String v, String label) {
      final on = e.myRsvp == v;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: OutlinedButton(
          key: ValueKey('rsvp-$v'),
          style: OutlinedButton.styleFrom(
            backgroundColor: on ? calAccentSoft(context) : null,
            foregroundColor: on ? calAccent(context) : pal.text,
            side: BorderSide(color: on ? Colors.transparent : pal.divider),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _busy ? null : () => _rsvp(v),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (on) ...[const Icon(Icons.check_rounded, size: 16), const SizedBox(width: 4)],
            Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.divider))),
      child: Row(children: [
        Expanded(child: Text(widget.popover ? tr('Tham dự?') : tr('Bạn sẽ tham dự chứ?'), style: TextStyle(fontSize: 13.5, color: pal.sub))),
        b('yes', 'Có'),
        b('no', 'Không'),
        b('maybe', 'Có thể'),
      ]),
    );
  }

  List<Widget> _actions() {
    final pal = Pal.of(context);
    return [
      if (e.canEdit && !e.busyOnly)
        IconButton(
            key: const ValueKey('detail-edit'),
            tooltip: tr('Sửa'),
            icon: Icon(Icons.edit_outlined, color: pal.sub),
            onPressed: () {
              Navigator.of(context).pop();
              widget.hooks.onEdit(e);
            }),
      if (e.canEdit && !e.busyOnly) IconButton(key: const ValueKey('detail-delete'), tooltip: tr('Xoá'), icon: Icon(Icons.delete_outline_rounded, color: pal.sub), onPressed: _delete),
      if (!e.busyOnly)
        PopupMenuButton<String>(
          key: const ValueKey('detail-more'),
          tooltip: tr('Thêm'),
          icon: Icon(Icons.more_vert_rounded, color: pal.sub),
          onSelected: _more,
          itemBuilder: (_) => [
            PopupMenuItem(value: 'dup', child: Text(tr('Nhân bản'))),
            if (e.canEdit && store.writable.length > 1) PopupMenuItem(value: 'move', child: Text(tr('Chuyển sang lịch khác'))),
            PopupMenuItem(value: 'copy', child: Text(tr('Sao chép thông tin'))),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (widget.popover) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ..._actions(),
            IconButton(tooltip: tr('Đóng'), icon: Icon(Icons.close_rounded, color: pal.sub), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 0, 22, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _body()))),
        if (e.canRsvp) _rsvpBar(),
      ]);
    }
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bg, surfaceTintColor: Colors.transparent, actions: _actions()),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 20, 24), children: _body()),
      bottomNavigationBar: e.canRsvp ? SafeArea(child: _rsvpBar()) : null,
    );
  }
}
