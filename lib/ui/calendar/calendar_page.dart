// Lịch (vn.flygo.calendar): màn hình chính. Máy tính: thanh trên (Hôm nay, ‹ ›, tên tháng, tìm kiếm, cài đặt, chọn Ngày /
// Tuần / Tháng / Lịch biểu) + cột trái. Điện thoại: thanh dưới Ngày / 3 ngày / Tháng / Lịch biểu, nút + nổi, menu trái;
// vuốt trái / phải để đổi ngày / tuần / tháng.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart' show serverKey;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../desk_tabs.dart' show DeskTabScope;
import '../theme.dart';
import 'agenda_view.dart';
import 'api.dart';
import 'editor.dart';
import 'event_detail.dart';
import 'look.dart';
import 'model.dart';
import 'month_view.dart';
import 'quick_create.dart';
import 'settings_page.dart';
import 'sidebar.dart';
import 'store.dart';
import 'time_grid.dart';
import 'tz.dart';

const kCalScreen = 'calendar';

/// Kho Lịch cho máy chủ + người dùng hiện tại (vé Flygo ID, bộ nhớ đệm riêng).
Future<CalStore> calendarStore(BuildContext context, MiniApp app) async {
  final state = context.read<AppState>();
  final id = await FlygoId.current(state.token);
  if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
  return CalStore(CalApi(base: app.baseUrl, id: id), cacheKey: '${serverKey}_${state.me?.id ?? 'me'}'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_'));
}

/// Mở Lịch (từ ô trong mục Chính, hoặc từ tin của bot với [eventId] / [rid]).
Future<void> openCalendar(BuildContext context, MiniApp app, {String? eventId, String? rid}) async {
  final state = context.read<AppState>();
  final nav = Navigator.of(context);
  final tab = DeskTabScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final store = await calendarStore(context, app);
    await nav.push(AppPageRoute(builder: (_) => CalendarHome(store: store, title: app.name, openEventId: eventId, openRid: rid, mmToken: state.token)));
    tab?.onTitle?.call(null);
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

class CalendarHome extends StatefulWidget {
  const CalendarHome({super.key, required this.store, this.title = 'Lịch', this.openEventId, this.openRid, this.mmToken, this.ownsStore = true, this.initialView, this.initialDate});
  final CalStore store;
  final String title;
  final String? openEventId, openRid;
  final String? mmToken;
  final bool ownsStore;
  /// Kiểm thử / ảnh chụp: chế độ xem và ngày mở đầu.
  final String? initialView;
  final DateTime? initialDate;
  @override
  State<CalendarHome> createState() => CalendarHomeState();
}

class CalendarHomeState extends State<CalendarHome> with WidgetsBindingObserver {
  String? _view;
  late DateTime _anchor = widget.initialDate ?? widget.store.today;
  bool _sidebar = true, _searching = false;
  final _q = TextEditingController();
  List<CEvent>? _results;
  (DateTime, DateTime)? _pending;
  final _scaffold = GlobalKey<ScaffoldState>();

  CalStore get store => widget.store;
  String get view => _view ?? 'week';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_changed);
    store.start().then((_) {
      if (!mounted) return;
      _load();
      _openFromLink();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_changed);
    if (widget.ownsStore) store.dispose();
    _q.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.refresh();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toast(Object m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$m')));

  Future<void> _openFromLink() async {
    final id = widget.openEventId;
    if (id == null) return;
    try {
      final e = store.cached(id, rid: widget.openRid) ?? await store.api.event(id, rid: widget.openRid);
      if (!mounted) return;
      setState(() => _anchor = dayOf(e.wallStart(store.tz)));
      _load();
      _detail(e, Rect.zero);
    } catch (err) {
      _toast(tr('Không mở được sự kiện này (có thể đã bị xoá hoặc bạn không còn quyền xem)'));
    }
  }

  // ------------------------------------------------------------ khoảng xem
  List<DateTime> get _days {
    switch (view) {
      case 'day':
        return [_anchor];
      case '3day':
        return [for (var i = 0; i < 3; i++) addDays(_anchor, i)];
      default:
        final s = weekStartOf(_anchor, store.settings.weekStart);
        final all = [for (var i = 0; i < 7; i++) addDays(s, i)];
        return store.settings.showWeekends ? all : all.where((d) => d.weekday <= 5).toList();
    }
  }

  (DateTime, DateTime) get _range {
    switch (view) {
      case 'month':
        final d = monthDays(_anchor, store.settings.weekStart);
        return (d.first, addDays(d.last, 1));
      case 'agenda':
        return (_anchor, DateTime.utc(_anchor.year, _anchor.month + 2));
      default:
        final d = _days;
        return (d.first, addDays(d.last, 1));
    }
  }

  void _load() {
    final (f, t) = _range;
    store.ensureRange(f, t);
  }

  void _go(DateTime d) {
    setState(() => _anchor = dayOf(d));
    _load();
  }

  void _shift(int dir) {
    switch (view) {
      case 'day':
        _go(addDays(_anchor, dir));
      case '3day':
        _go(addDays(_anchor, 3 * dir));
      case 'week':
        _go(addDays(_anchor, 7 * dir));
      default:
        final m = DateTime.utc(_anchor.year, _anchor.month + dir);
        final last = DateTime.utc(m.year, m.month + 1, 0).day;
        _go(DateTime.utc(m.year, m.month, _anchor.day.clamp(1, last)));
    }
  }

  void _setView(String v) {
    setState(() {
      _view = v;
      _results = null;
      _searching = false;
    });
    _load();
  }

  String _title(bool wide) {
    if (view == 'week' || view == '3day') {
      final d = _days;
      final a = d.first, b = d.last;
      if (a.month != b.month) {
        return a.year != b.year ? 'Th${a.month} ${a.year} – Th${b.month} ${b.year}' : 'Th${a.month} – Th${b.month}${wide ? ', ${a.year}' : ''}';
      }
    }
    if (!wide) return '${tr('Tháng {0}', [_anchor.month])}${_anchor.year != store.today.year ? ' ${_anchor.year}' : ''}';
    return monthTitle(_anchor);
  }

  // ------------------------------------------------------------ hành động
  DetailHooks get _hooks => DetailHooks(onEdit: _edit, onDuplicate: _duplicate, onJoin: _join);

  void _detail(CEvent e, Rect anchor) => showEventDetail(context, store: store, e: e, anchor: calWide(context) ? anchor : null, hooks: _hooks);

  Future<void> _edit(CEvent e) async {
    var ev = e;
    // Sửa từ bản đầy đủ (lần xảy ra có thể thiếu trường khi lấy từ bộ nhớ đệm cũ).
    try {
      ev = await store.api.event(e.id, rid: e.rid);
      ev.rid ??= e.rid;
      ev.recurring = ev.recurring || e.recurring;
      ev.instanceId = e.instanceId;
    } catch (_) {}
    if (!mounted) return;
    await openEditor(context, store, event: ev, mmToken: widget.mmToken);
  }

  void _duplicate(CEvent e) {
    final d = EventDraft.fromEvent(e)
      ..id = null
      ..calendarId = (store.calendar(e.calendarId)?.canWrite ?? false) ? e.calendarId : store.primaryId
      ..conference = null
      ..guests = [for (final g in e.attendees) if (!g.organizer) CAttendee(principal: g.principal, id: g.id, name: g.name, optional: g.optional)];
    openEditor(context, store, draft: d, mmToken: widget.mmToken);
  }

  Future<void> _join(CEvent e) async {
    final c = e.conference;
    if (c == null) return;
    if (c.url.isEmpty) return _toast(tr('Mã họp: {0}', [c.code]));
    try {
      await launchUrl(Uri.parse(c.url), mode: LaunchMode.externalApplication);
    } catch (err) {
      _toast(err);
    }
  }

  void _newEvent({DateTime? start, DateTime? end, bool allDay = false}) =>
      openEditor(context, store, draft: EventDraft.blank(store, start: start, end: end, allDay: allDay), mmToken: widget.mmToken);

  Future<void> _create(DateTime s, DateTime e, Rect anchor, bool allDay) async {
    if (store.writable.isEmpty) return _toast(tr('Bạn chưa có lịch nào để thêm sự kiện'));
    if (!calWide(context)) return _newEvent(start: s, end: e, allDay: allDay);
    final draft = EventDraft.blank(store, start: s, end: e, allDay: allDay);
    setState(() => _pending = allDay ? null : (s, e));
    EventDraft? more;
    await showAnchored<void>(
      context,
      anchor: anchor,
      width: 440,
      builder: (_) => QuickCreate(store: store, draft: draft, mmToken: widget.mmToken, onMore: (d) => more = d),
    );
    if (mounted) setState(() => _pending = null);
    if (more != null && mounted) await openEditor(context, store, draft: more, mmToken: widget.mmToken);
  }

  Future<void> _move(CEvent e, DateTime s, DateTime en) async {
    var scope = 'all';
    if (e.recurring) {
      final r = await askScope(context, title: tr('Sửa sự kiện định kỳ'), guests: e.attendees.where((a) => !a.organizer).length);
      if (r == null) return setState(() {});
      scope = r.$1;
    }
    try {
      await store.moveTime(e, s, en, scope: scope);
    } catch (err) {
      _toast(err);
    }
  }

  Future<void> _findFree() async {
    final r = await findFreeTime(context, store);
    if (r == null || !mounted) return;
    final d = EventDraft.blank(store, start: wallOf(r.slot.startMs, store.tz), end: wallOf(r.slot.endMs, store.tz))
      ..guests = [for (final p in r.people) CAttendee(principal: p.principal, id: p.id, name: p.name)];
    await openEditor(context, store, draft: d, mmToken: widget.mmToken);
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return setState(() => _results = null);
    try {
      final r = await store.search(q.trim(), _anchor);
      if (mounted) setState(() => _results = r);
    } catch (e) {
      _toast(e);
    }
  }

  void _close() {
    final nav = Navigator.of(context);
    if (!(_scaffold.currentState?.isDrawerOpen ?? false)) {
      nav.maybePop();
      return;
    }
    nav.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => nav.maybePop());
  }

  // ------------------------------------------------------------ nội dung
  Widget _content(bool wide) {
    if (_results != null) return AgendaList(store: store, from: _anchor, onEventTap: _detail, onJoin: _join, results: _results, wide: wide);
    switch (view) {
      case 'month':
        if (!wide) {
          return PhoneMonth(store: store, month: _anchor, selected: _anchor, onSelect: _go, onEventTap: _detail);
        }
        return MonthGrid(
          store: store,
          month: _anchor,
          onEventTap: _detail,
          onDayTap: (d) {
            _go(d);
            _setView('day');
          },
          onMore: (d) {
            _go(d);
            _setView('day');
          },
          onCreate: (d, r) => _create(d, addDays(d, 1), r, true),
        );
      case 'agenda':
        return AgendaList(key: ValueKey('agenda-${fmtDate(_anchor)}'), store: store, from: _anchor, onEventTap: _detail, onJoin: _join, wide: wide);
      default:
        return TimeGrid(
          key: ValueKey('grid-$view'),
          store: store,
          days: _days,
          wide: wide,
          pending: _pending,
          onTapEvent: _detail,
          onCreate: _create,
          onMove: _move,
          onDayTap: view == 'day'
              ? null
              : (d) {
                  _go(d);
                  _setView('day');
                },
        );
    }
  }

  Widget _offlineBanner() {
    if (!store.offline) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('offline'),
      width: double.infinity,
      color: const Color(0xFFFFF4D6).withValues(alpha: calDark(context) ? .18 : 1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, size: 17, color: Color(0xFFB7791F)),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('Không có mạng · đang hiện lịch đã lưu trên máy'), style: TextStyle(fontSize: 13, color: Pal.of(context).text))),
        TextButton(onPressed: store.refresh, child: Text(tr('Thử lại'))),
      ]),
    );
  }

  Widget _avatar() => CircleAvatar(
        radius: 17,
        backgroundColor: calAccent(context),
        child: Text(store.meName.trim().isEmpty ? '?' : store.meName.trim().characters.first.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
      );

  Widget _searchField({double width = 320}) => SizedBox(
        width: width,
        child: TextField(
          key: const ValueKey('search-q'),
          controller: _q,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: tr('Tìm sự kiện'),
            isDense: true,
            filled: true,
            fillColor: Pal.of(context).surface,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
          ),
        ),
      );

  void _toggleSearch() => setState(() {
        _searching = !_searching;
        if (!_searching) {
          _results = null;
          _q.clear();
        }
      });

  Widget _segmented() {
    final pal = Pal.of(context);
    const views = [('day', 'Ngày'), ('week', 'Tuần'), ('month', 'Tháng'), ('agenda', 'Lịch biểu')];
    return Container(
      height: 36,
      decoration: BoxDecoration(border: Border.all(color: pal.divider), borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (v, l) in views)
          InkWell(
            key: ValueKey('view-$v'),
            onTap: () => _setView(v),
            child: Container(
              color: view == v && _results == null ? calAccentSoft(context) : null,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              child: Text(tr(l),
                  style: TextStyle(fontSize: 13.5, fontWeight: view == v ? FontWeight.w600 : FontWeight.w500, color: view == v && _results == null ? calAccent(context) : pal.sub)),
            ),
          ),
      ]),
    );
  }

  Widget _topWide() {
    final pal = Pal.of(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
      child: Row(children: [
        IconButton(tooltip: tr('Menu'), icon: Icon(Icons.menu_rounded, color: pal.sub), onPressed: () => setState(() => _sidebar = !_sidebar)),
        const SizedBox(width: 4),
        CalIcon(day: store.today.day),
        const SizedBox(width: 10),
        Text(widget.title, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w500, color: pal.text)),
        const SizedBox(width: 28),
        OutlinedButton(
          key: const ValueKey('today'),
          style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: pal.divider), foregroundColor: pal.text, padding: const EdgeInsets.symmetric(horizontal: 18)),
          onPressed: () => _go(store.today),
          child: Text(tr('Hôm nay'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        IconButton(key: const ValueKey('prev'), tooltip: tr('Trước'), icon: Icon(Icons.chevron_left_rounded, color: pal.sub), onPressed: () => _shift(-1)),
        IconButton(key: const ValueKey('next'), tooltip: tr('Sau'), icon: Icon(Icons.chevron_right_rounded, color: pal.sub), onPressed: () => _shift(1)),
        const SizedBox(width: 12),
        Flexible(child: Text(_results != null ? tr('Kết quả tìm kiếm') : _title(true), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, color: pal.text))),
        const Spacer(),
        if (_searching) _searchField(),
        IconButton(key: const ValueKey('search'), tooltip: tr('Tìm kiếm'), icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, color: pal.sub), onPressed: _toggleSearch),
        IconButton(key: const ValueKey('settings'), tooltip: tr('Cài đặt'), icon: Icon(Icons.settings_outlined, color: pal.sub), onPressed: () => openCalSettings(context, store)),
        const SizedBox(width: 10),
        _segmented(),
        const SizedBox(width: 14),
        _avatar(),
        if (Navigator.of(context).canPop()) ...[
          const SizedBox(width: 4),
          IconButton(tooltip: tr('Đóng'), icon: Icon(Icons.close_rounded, color: pal.sub), onPressed: _close),
        ],
      ]),
    );
  }

  Widget _wide() {
    final pal = Pal.of(context);
    final (f, t) = _range;
    return Scaffold(
      key: _scaffold,
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(children: [
          _topWide(),
          if (store.loading(f, t)) LinearProgressIndicator(minHeight: 2, color: calAccent(context), backgroundColor: Colors.transparent) else const SizedBox(height: 2),
          _offlineBanner(),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_sidebar)
                SizedBox(
                  width: 256,
                  child: CalSidebar(
                    store: store,
                    anchor: _anchor,
                    highlight: view == 'month' ? const [] : _days,
                    onPick: _go,
                    onCreate: () => _newEvent(),
                    onFindTime: _findFree,
                  ),
                ),
              Expanded(child: _content(true)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _phone() {
    final pal = Pal.of(context);
    const tabs = ['day', '3day', 'month', 'agenda'];
    final idx = tabs.indexOf(view);
    return Scaffold(
      key: _scaffold,
      backgroundColor: pal.bg,
      drawer: Drawer(
        backgroundColor: calDark(context) ? pal.surface : pal.bg,
        child: SafeArea(
          child: CalSidebar(
            store: store,
            anchor: _anchor,
            highlight: _days,
            onPick: _go,
            onCreate: () => _newEvent(),
            onFindTime: _findFree,
            view: view,
            onView: _setView,
            onSettings: () => openCalSettings(context, store),
            onBack: Navigator.of(context).canPop() ? _close : null,
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(key: const ValueKey('drawer'), tooltip: tr('Menu'), icon: const Icon(Icons.menu_rounded), onPressed: () => _scaffold.currentState?.openDrawer()),
        title: _searching
            ? _searchField(width: double.infinity)
            : InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: DateTime(_anchor.year, _anchor.month, _anchor.day), firstDate: DateTime(1970), lastDate: DateTime(2100));
                  if (d != null) _go(DateTime.utc(d.year, d.month, d.day));
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_results != null ? tr('Kết quả tìm kiếm') : _title(false), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                  const Icon(Icons.arrow_drop_down_rounded),
                ]),
              ),
        actions: [
          IconButton(key: const ValueKey('search'), tooltip: tr('Tìm kiếm'), icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded), onPressed: _toggleSearch),
          if (!_searching)
            IconButton(key: const ValueKey('today'), tooltip: tr('Hôm nay'), icon: CalIcon(day: store.today.day, size: 24), onPressed: () => _go(store.today)),
          Padding(padding: const EdgeInsets.only(right: 12, left: 4), child: _avatar()),
        ],
      ),
      body: Column(children: [
        _offlineBanner(),
        Expanded(
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 250 || _results != null || view == 'agenda') return;
              _shift(v < 0 ? 1 : -1);
            },
            child: _content(false),
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('fab'),
        backgroundColor: calAccent(context),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tooltip: tr('Tạo sự kiện'),
        onPressed: () => _newEvent(start: view == 'month' ? _anchor.add(Duration(minutes: CSettings.minutesOf(store.settings.workStart) + 60)) : null),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        backgroundColor: pal.bg,
        indicatorColor: Colors.transparent,
        selectedIndex: idx < 0 ? 0 : idx,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => _setView(tabs[i]),
        destinations: [
          for (final (i, (icon, l)) in const [
            (Icons.view_day_outlined, 'Ngày'),
            (Icons.view_week_outlined, '3 ngày'),
            (Icons.calendar_month_outlined, 'Tháng'),
            (Icons.view_agenda_outlined, 'Lịch biểu'),
          ].indexed)
            NavigationDestination(
              key: ValueKey('tab-${tabs[i]}'),
              icon: Icon(icon, color: pal.sub),
              selectedIcon: Icon(icon, color: calAccent(context)),
              label: tr(l),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = calWide(context);
    if (_view == null) {
      final d = widget.initialView ?? store.settings.defaultView;
      _view = wide ? (d == '3day' ? 'week' : d) : (d == 'week' ? 'day' : d);
    }
    // Đổi cỡ cửa sổ: chế độ chỉ có trên điện thoại / máy tính thì đổi sang chế độ gần nhất.
    if (wide && view == '3day') _view = 'week';
    return wide ? _wide() : _phone();
  }
}
