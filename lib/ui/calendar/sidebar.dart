// Lịch: cột trái (máy tính) / menu trượt (điện thoại) — nút Tạo, lịch tháng nhỏ (tô tuần đang xem), "Tìm giờ rảnh với…",
// danh sách "Lịch của tôi" / "Lịch khác" có ô màu bật / tắt và menu từng lịch.
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'look.dart';
import 'model.dart';
import 'month_view.dart' show monthDays;
import 'share_dialog.dart';
import 'store.dart';
import 'tz.dart';

class CalSidebar extends StatefulWidget {
  const CalSidebar({
    super.key,
    required this.store,
    required this.anchor,
    required this.highlight,
    required this.onPick,
    required this.onCreate,
    required this.onFindTime,
    this.view,
    this.onView,
    this.onSettings,
    this.onBack,
  });

  final CalStore store;
  final DateTime anchor;
  /// Các ngày đang xem (tô nhạt trong lịch nhỏ).
  final List<DateTime> highlight;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onCreate, onFindTime;
  /// Điện thoại: danh sách chế độ xem ở đầu menu.
  final String? view;
  final ValueChanged<String>? onView;
  final VoidCallback? onSettings, onBack;

  @override
  State<CalSidebar> createState() => _CalSidebarState();
}

class _CalSidebarState extends State<CalSidebar> {
  late DateTime _month = DateTime.utc(widget.anchor.year, widget.anchor.month);
  bool _mineOpen = true, _otherOpen = true;

  CalStore get store => widget.store;
  bool get _phone => widget.onView != null;

  @override
  void didUpdateWidget(CalSidebar old) {
    super.didUpdateWidget(old);
    if (old.anchor.month != widget.anchor.month || old.anchor.year != widget.anchor.year) _month = DateTime.utc(widget.anchor.year, widget.anchor.month);
  }

  void _toast(Object m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$m')));

  Future<void> _pickColor(CCalendar c) async {
    final v = await showCalSheet<String>(
      context,
      width: 320,
      builder: (bc) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Đổi màu'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final k in kEventColors.keys)
              Tooltip(
                message: tr(kColorNames[k]!),
                child: InkWell(
                  key: ValueKey('pick-color-$k'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(bc, k),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: eventColor(k, calDark(bc)), shape: BoxShape.circle),
                    child: c.shownColor == k ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
    if (v != null) await store.setPrefs(c, color: v);
  }

  Future<void> _remove(CCalendar c) async {
    final own = c.isOwner;
    final ok = await showDialog<bool>(
      context: context,
      builder: (bc) => AlertDialog(
        title: Text(own ? tr('Xoá lịch "{0}"?', [c.name]) : tr('Huỷ đăng ký lịch "{0}"?', [c.name])),
        content: Text(own ? tr('Mọi sự kiện trong lịch này sẽ bị xoá, người được chia sẻ cũng không xem được nữa.') : tr('Lịch sẽ không còn hiện trong danh sách của bạn.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(bc, false), child: Text(tr('Huỷ'))),
          FilledButton(
            key: const ValueKey('confirm-remove'),
            style: FilledButton.styleFrom(backgroundColor: own ? kNowRed : calAccent(bc)),
            onPressed: () => Navigator.pop(bc, true),
            child: Text(own ? tr('Xoá') : tr('Huỷ đăng ký')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await store.deleteCalendar(c);
    } catch (e) {
      _toast(e);
    }
  }

  void _menu(CCalendar c, String a) {
    switch (a) {
      case 'only':
        store.onlyThis(c);
      case 'color':
        _pickColor(c);
      case 'settings':
        openCalendarSettings(context, store, c);
      case 'remove':
        _remove(c);
    }
  }

  void _holidays() {
    final h = store.calendars.where((c) => c.isHoliday).firstOrNull;
    if (h == null) return _toast(tr('Máy chủ chưa có lịch Ngày lễ Việt Nam'));
    if (h.hidden) store.setPrefs(h, hidden: false, subscribed: true);
    openCalendarSettings(context, store, h);
  }

  // ------------------------------------------------------------ lịch nhỏ
  Widget _mini() {
    final pal = Pal.of(context);
    final days = monthDays(_month, store.settings.weekStart);
    final today = store.today;
    return Column(children: [
      Row(children: [
        const SizedBox(width: 8),
        Expanded(child: Text(tr('Tháng {0} {1}', [_month.month, _month.year]), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
        _tiny(Icons.chevron_left_rounded, () => setState(() => _month = DateTime.utc(_month.year, _month.month - 1))),
        _tiny(Icons.chevron_right_rounded, () => setState(() => _month = DateTime.utc(_month.year, _month.month + 1))),
      ]),
      const SizedBox(height: 4),
      Row(children: [for (var i = 0; i < 7; i++) Expanded(child: Center(child: Text(dowShort(days[i]), style: TextStyle(fontSize: 11, color: pal.sub))))]),
      for (var w = 0; w < days.length ~/ 7; w++)
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(child: () {
              final d = days[w * 7 + i];
              final isToday = sameDay(d, today);
              final on = widget.highlight.any((x) => sameDay(x, d));
              return InkWell(
                key: ValueKey('mini-${fmtDate(d)}'),
                customBorder: const CircleBorder(),
                onTap: () => widget.onPick(d),
                child: SizedBox(
                  height: 28,
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: isToday ? calAccent(context) : on ? calAccentSoft(context) : null),
                      child: Text('${d.day}',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isToday ? FontWeight.w700 : on ? FontWeight.w600 : FontWeight.w400,
                              color: isToday ? Colors.white : on ? calAccent(context) : d.month == _month.month ? pal.text : pal.sub.withValues(alpha: .55))),
                    ),
                  ),
                ),
              );
            }()),
        ]),
    ]);
  }

  Widget _tiny(IconData i, VoidCallback onTap) => InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(i, size: 20, color: Pal.of(context).text)),
      );

  // ------------------------------------------------------------ danh sách lịch
  Widget _section(String title, bool open, VoidCallback toggle, {Widget? extra}) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 10, 0, 4),
        child: Row(children: [
          Expanded(child: Text(tr(title), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
          ?extra,
          _tiny(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, toggle),
        ]),
      );

  Widget _calRow(CCalendar c) {
    final pal = Pal.of(context);
    return SizedBox(
      key: ValueKey('cal-${c.id}'),
      height: 34,
      child: Row(children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => store.setPrefs(c, hidden: !c.hidden),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                ColorCheck(color: eventColor(c.shownColor, calDark(context)), on: !c.hidden),
                const SizedBox(width: 12),
                Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
              ]),
            ),
          ),
        ),
        PopupMenuButton<String>(
          key: ValueKey('cal-menu-${c.id}'),
          tooltip: tr('Tuỳ chọn cho {0}', [c.name]),
          padding: EdgeInsets.zero,
          icon: Icon(Icons.more_vert_rounded, size: 17, color: pal.sub.withValues(alpha: .7)),
          onSelected: (a) => _menu(c, a),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'only', child: Text(tr('Chỉ hiển thị lịch này'))),
            PopupMenuItem(value: 'color', child: Text(tr('Đổi màu'))),
            PopupMenuItem(value: 'settings', child: Text(c.canManage ? tr('Cài đặt và chia sẻ') : tr('Thông tin lịch'))),
            if (!c.primary) PopupMenuItem(value: 'remove', child: Text(c.isOwner && !c.isHoliday ? tr('Xoá') : tr('Huỷ đăng ký'))),
          ],
        ),
      ]),
    );
  }

  Widget _link(IconData icon, String label, VoidCallback onTap, {Key? key, bool on = false}) {
    final pal = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: on ? calAccentSoft(context) : Colors.transparent,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
        child: InkWell(
          key: key,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Icon(icon, size: 21, color: on ? calAccent(context) : pal.sub),
              const SizedBox(width: 16),
              Expanded(child: Text(tr(label), style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? calAccent(context) : pal.text))),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final mine = store.mine, others = store.others;
    final close = _phone ? () => Navigator.maybePop(context) : () {};
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListView(padding: EdgeInsets.fromLTRB(_phone ? 0 : 12, 8, _phone ? 0 : 12, 24), children: [
        if (_phone) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(children: [CalIcon(day: store.today.day, size: 30), const SizedBox(width: 12), Text(tr('Lịch'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w500))]),
          ),
          for (final (v, icon, label) in const [
            ('day', Icons.view_day_outlined, 'Ngày'),
            ('3day', Icons.view_week_outlined, '3 ngày'),
            ('week', Icons.calendar_view_week_outlined, 'Tuần'),
            ('month', Icons.calendar_month_outlined, 'Tháng'),
            ('agenda', Icons.view_agenda_outlined, 'Lịch biểu'),
          ])
            _link(icon, label, () {
              close();
              widget.onView!(v);
            }, key: ValueKey('drawer-$v'), on: widget.view == v),
          Divider(height: 20, color: pal.divider),
        ] else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: calDark(context) ? pal.surface2 : pal.bg,
              elevation: 2,
              shadowColor: Colors.black38,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const ValueKey('create'),
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onCreate,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 22, 13),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: calAccent(context), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text(tr('Tạo'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _mini(),
          const SizedBox(height: 14),
          Material(
            color: pal.surface,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const ValueKey('find-free'),
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onFindTime,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  Icon(Icons.group_outlined, size: 20, color: pal.sub),
                  const SizedBox(width: 10),
                  Expanded(child: Text(tr('Tìm giờ rảnh với…'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: pal.sub))),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _phone ? 12 : 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _section('Lịch của tôi', _mineOpen, () => setState(() => _mineOpen = !_mineOpen)),
            if (_mineOpen) for (final c in mine) _calRow(c),
            _section('Lịch khác', _otherOpen, () => setState(() => _otherOpen = !_otherOpen),
                extra: PopupMenuButton<String>(
                  key: const ValueKey('other-add'),
                  tooltip: tr('Thêm lịch'),
                  icon: Icon(Icons.add_rounded, size: 20, color: pal.text),
                  padding: EdgeInsets.zero,
                  onSelected: (v) => v == 'new' ? openCalendarSettings(context, store, null) : _holidays(),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'new', child: Text(tr('Tạo lịch mới'))),
                    PopupMenuItem(value: 'holiday', child: Text(tr('Ngày lễ Việt Nam'))),
                  ],
                )),
            if (_otherOpen) for (final c in others) _calRow(c),
          ]),
        ),
        if (_phone) ...[
          Divider(height: 24, color: pal.divider),
          _link(Icons.add_circle_outline_rounded, 'Tạo lịch mới', () => openCalendarSettings(context, store, null), key: const ValueKey('drawer-new-cal')),
          _link(Icons.celebration_outlined, 'Ngày lễ Việt Nam', _holidays),
          _link(Icons.group_outlined, 'Tìm giờ rảnh với…', () {
            close();
            widget.onFindTime();
          }),
          if (widget.onSettings != null)
            _link(Icons.settings_outlined, 'Cài đặt', () {
              close();
              widget.onSettings!();
            }),
          if (widget.onBack != null) _link(Icons.chat_bubble_outline_rounded, 'Quay về app Flygo Chat', widget.onBack!, key: const ValueKey('back-to-chat')),
        ],
      ]),
    );
  }
}
