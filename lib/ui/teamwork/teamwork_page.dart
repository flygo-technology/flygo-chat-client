// TeamWork / Làm việc nhóm (vn.flygo.teamwork): màn hình chính. Máy tính: thanh bên (Việc của tôi, Thông báo, Tất cả dự án,
// Tìm kiếm, dự án của tôi) + vùng chính (dự án: Danh sách / Kanban / Gantt / Tổng quan). Điện thoại: thanh dưới Của tôi /
// Dự án / Thông báo / Tìm, mở dự án thành trang riêng, nút + nổi để tạo việc.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart' show serverKey;
import '../../state/app_state.dart';
import '../app_route.dart';
import '../desk_tabs.dart' show DeskTabScope;
import '../theme.dart' show toast;
import '../todo/model.dart';
import 'agent_runs.dart';
import 'api.dart';
import 'board_view.dart';
import 'cover.dart';
import 'gantt_view.dart';
import 'list_view.dart';
import 'look.dart';
import 'model.dart';
import 'my_tasks_view.dart';
import 'pickers.dart';
import 'projects_view.dart';
import 'rich_mentions.dart';
import 'settings_page.dart';
import 'store.dart';
import 'task_page.dart';
import 'task_widgets.dart';

/// Kho TeamWork cho máy chủ + người dùng hiện tại.
Future<TwStore> teamworkStore(BuildContext context, MiniApp app) async {
  final state = context.read<AppState>();
  final id = await FlygoId.current(state.token);
  if (id == null) throw StateError('Máy chủ này chưa có Flygo ID');
  final s = TwStore(TwApi(base: app.baseUrl, id: id), cacheKey: '${serverKey}_${state.me?.id ?? 'me'}'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_'));
  s.launcher = AppAgentLauncher(state);
  // Độ rộng khung việc bên phải: nhớ trên máy này (tuỳ chọn giao diện của app).
  s.panelWidth = await state.uiPref<double>('teamwork_panel_width');
  s.savePanelWidth = (w) => state.setUiPref('teamwork_panel_width', w);
  s.commentsCollapsed = await state.uiPref<bool>('teamwork_comments_collapsed') ?? false;
  s.saveCommentsCollapsed = (v) => state.setUiPref('teamwork_comments_collapsed', v);
  return s;
}

/// Mở TeamWork (từ ô ở mục Chính, hoặc link sâu `/t/<MÃ>` với [taskKey]).
Future<void> openTeamwork(BuildContext context, MiniApp app, {String? taskKey}) async {
  final nav = Navigator.of(context);
  final tab = DeskTabScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final store = await teamworkStore(context, app);
    await nav.push(AppPageRoute(builder: (c) {
      (store.launcher as AppAgentLauncher?)?.context = c;
      return TeamworkHome(store: store, openTaskKey: taskKey);
    }));
    tab?.onTitle?.call(null);
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

class TeamworkHome extends StatefulWidget {
  const TeamworkHome({super.key, required this.store, this.ownsStore = true, this.openTaskKey, this.initialSection, this.initialProject, this.initialView});
  final TwStore store;
  final bool ownsStore;
  final String? openTaskKey;
  /// Kiểm thử / ảnh chụp: mục, dự án và kiểu xem mở đầu.
  final String? initialSection, initialProject, initialView;
  @override
  State<TeamworkHome> createState() => TeamworkHomeState();
}

class TeamworkHomeState extends State<TeamworkHome> {
  late String section = widget.initialSection ?? (widget.initialProject != null ? 'project' : 'all');
  String? projectId;
  late String view = widget.initialView ?? 'kanban';
  final Map<String, TwFilter> _filters = {};
  int _phoneTab = 1;

  TwStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _phoneTab = switch (section) { 'mine' => 0, 'inbox' => 2, 'search' => 3, _ => 1 };
    store.start().then((_) {
      if (!mounted) return;
      if (widget.initialProject != null) {
        final p = store.projects.where((x) => x.id == widget.initialProject || x.key == widget.initialProject).firstOrNull;
        if (p != null) _openProject(p);
      }
      if (widget.openTaskKey != null) openTask(context, store, widget.openTaskKey!);
    });
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    if (widget.ownsStore) store.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  TwFilter filterOf(String pid) => _filters.putIfAbsent(pid, TwFilter.new);

  void _openProject(TwProject p) {
    if (store.fullOf(p.id) == null) unawaited(store.openProject(p.id));
    if (twWide(context)) {
      setState(() {
        section = 'project';
        projectId = p.id;
      });
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TwProjectScreen(store: store, projectId: p.id, filter: filterOf(p.id), initialView: view)));
    }
  }

  Future<void> _newProject() async {
    final f = await createProjectDialog(context, store);
    if (f != null && mounted) _openProject(f.project);
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    return twWide(context) ? _desktop(look) : _phone(look);
  }

  // ------------------------------------------------------------ máy tính
  Widget _navItem(String key, IconData icon, String label, {Widget? trailing, VoidCallback? onTap, bool on = false}) {
    final look = TwLook.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: on ? look.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('nav-$key'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 34,
            child: Row(children: [
              const SizedBox(width: 10),
              icon == Icons.circle ? const SizedBox() : Icon(icon, size: 20, color: on ? look.accent : look.sub),
              const SizedBox(width: 10),
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: on ? look.accent : look.text, fontWeight: on ? FontWeight.w600 : FontWeight.w500))),
              ?trailing,
              const SizedBox(width: 10),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sidebar(TwLook look) {
    final mine = store.projects.where((p) => !p.archived && p.status != 'done' && p.status != 'cancelled').toList()
      ..sort((a, b) => a.starred != b.starred ? (a.starred ? -1 : 1) : a.name.compareTo(b.name));
    return Container(
      width: 248,
      color: look.surface,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
          child: Row(children: [
            const TwLogo(),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Làm việc nhóm', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              Text('TeamWork', style: TextStyle(fontSize: 11.5, color: look.sub)),
            ]),
          ]),
        ),
        _navItem('mine', Icons.how_to_reg_outlined, 'Việc của tôi', on: section == 'mine', onTap: () => setState(() => section = 'mine')),
        _navItem('inbox', Icons.notifications_none, 'Thông báo',
            on: section == 'inbox',
            trailing: store.unread > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: look.accent, borderRadius: BorderRadius.circular(9)),
                    child: Text('${store.unread}', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  )
                : null,
            onTap: () => setState(() => section = 'inbox')),
        _navItem('all', Icons.folder_open_outlined, 'Tất cả dự án', on: section == 'all', onTap: () => setState(() => section = 'all')),
        _navItem('search', Icons.search, 'Tìm kiếm', on: section == 'search', onTap: () => setState(() => section = 'search')),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
          child: Text('DỰ ÁN CỦA TÔI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: look.sub)),
        ),
        Expanded(
          child: ListView(children: [
            for (final p in mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Material(
                  color: section == 'project' && projectId == p.id ? look.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: ValueKey('side-${p.key}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openProject(p),
                    child: SizedBox(
                      height: 34,
                      child: Row(children: [
                        const SizedBox(width: 10),
                        ProjectBadge(p),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(p.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: section == 'project' && projectId == p.id ? look.accent : look.text, fontWeight: section == 'project' && projectId == p.id ? FontWeight.w600 : FontWeight.w500)),
                        ),
                        if (p.starred) const Icon(Icons.star_rounded, size: 14, color: Color(0xFFE8B10C)),
                        const SizedBox(width: 8),
                      ]),
                    ),
                  ),
                ),
              ),
            _navItem('new-project', Icons.add, 'Dự án mới', onTap: _newProject),
          ]),
        ),
        if (store.offline)
          Padding(
            padding: const EdgeInsets.all(6),
            child: Row(children: [Icon(Icons.cloud_off, size: 16, color: look.warn), const SizedBox(width: 6), Expanded(child: Text('Mất mạng · đang hiện dữ liệu đã lưu', style: TextStyle(fontSize: 11.5, color: look.sub)))]),
          ),
        _navItem('prefs', Icons.settings_outlined, 'Cài đặt thông báo', onTap: () => showPrefs(context, store)),
      ]),
    );
  }

  Widget _desktop(TwLook look) {
    Widget main;
    switch (section) {
      case 'mine':
        main = Column(children: [_top('Việc của tôi', sub: 'mọi dự án'), Expanded(child: TwMyTasksView(store: store, onOpen: (t) => openTask(context, store, t.key)))]);
      case 'inbox':
        main = Column(children: [
          _top('Thông báo', actions: [TextButton(onPressed: store.markAllRead, child: const Text('Đánh dấu đã đọc hết'))]),
          Expanded(child: NotificationsView(store: store)),
        ]);
      case 'search':
        main = SearchView(store: store);
      case 'project' when projectId != null:
        main = TwProjectScreen(key: ValueKey('ps-$projectId'), store: store, projectId: projectId!, filter: filterOf(projectId!), embedded: true, initialView: view, onView: (v) => view = v);
      default:
        main = Column(children: [
          _top('Tất cả dự án', actions: [FilledButton.icon(key: const ValueKey('new-project'), onPressed: _newProject, icon: const Icon(Icons.add, size: 18), label: const Text('Dự án mới'))]),
          Expanded(child: TwProjectsView(store: store, onOpen: _openProject)),
        ]);
    }
    return Scaffold(
      backgroundColor: look.bg,
      body: SafeArea(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_sidebar(look), VerticalDivider(width: 1, color: look.divider), Expanded(child: main)])),
    );
  }

  Widget _top(String title, {String? sub, List<Widget> actions = const []}) {
    final look = TwLook.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.divider))),
      child: Row(children: [
        if (Navigator.of(context).canPop()) IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).maybePop()),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        if (sub != null) ...[const SizedBox(width: 10), Text(sub, style: TextStyle(color: look.sub))],
        const Spacer(),
        ...actions,
      ]),
    );
  }

  // ------------------------------------------------------------ điện thoại
  Widget _phone(TwLook look) {
    final titles = ['Việc của tôi', 'Làm việc nhóm', 'Thông báo', 'Tìm kiếm'];
    final body = switch (_phoneTab) {
      0 => TwMyTasksView(store: store, onOpen: (t) => openTask(context, store, t.key)),
      2 => NotificationsView(store: store),
      3 => SearchView(store: store, phone: true),
      _ => TwProjectsView(store: store, onOpen: _openProject),
    };
    return Scaffold(
      backgroundColor: look.bg,
      appBar: AppBar(
        backgroundColor: look.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(children: [if (_phoneTab == 1) ...[const TwLogo(size: 28), const SizedBox(width: 10)], Text(titles[_phoneTab], style: const TextStyle(fontWeight: FontWeight.w700))]),
        actions: [
          if (_phoneTab == 2) TextButton(onPressed: store.markAllRead, child: const Text('Đọc hết')),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'prefs' ? showPrefs(context, store) : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'prefs', child: Text('Cài đặt thông báo'))],
          ),
        ],
      ),
      body: Column(children: [
        if (store.offline)
          Container(
            width: double.infinity,
            color: look.warn.withValues(alpha: .12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text('Mất mạng · đang hiện dữ liệu đã lưu', style: TextStyle(fontSize: 12, color: look.text)),
          ),
        Expanded(child: body),
      ]),
      floatingActionButton: _phoneTab == 1
          ? FloatingActionButton(key: const ValueKey('fab'), backgroundColor: look.accent, foregroundColor: Colors.white, tooltip: 'Dự án mới', onPressed: _newProject, child: const Icon(Icons.add))
          : null,
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: _phoneTab,
        onDestinationSelected: (i) => setState(() => _phoneTab = i),
        destinations: [
          const NavigationDestination(key: ValueKey('ptab-mine'), icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: 'Của tôi'),
          const NavigationDestination(key: ValueKey('ptab-projects'), icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder), label: 'Dự án'),
          NavigationDestination(
            key: const ValueKey('ptab-inbox'),
            icon: Badge(isLabelVisible: store.unread > 0, label: Text('${store.unread}'), child: const Icon(Icons.notifications_none)),
            selectedIcon: const Icon(Icons.notifications),
            label: 'Thông báo',
          ),
          const NavigationDestination(key: ValueKey('ptab-search'), icon: Icon(Icons.search), label: 'Tìm'),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ màn hình một dự án
class TwProjectScreen extends StatefulWidget {
  const TwProjectScreen({super.key, required this.store, required this.projectId, required this.filter, this.embedded = false, this.initialView = 'kanban', this.onView});
  final TwStore store;
  final String projectId;
  final TwFilter filter;
  /// Máy tính: nằm trong vùng chính (không có thanh ứng dụng riêng).
  final bool embedded;
  final String initialView;
  final ValueChanged<String>? onView;
  @override
  State<TwProjectScreen> createState() => _TwProjectScreenState();
}

class _TwProjectScreenState extends State<TwProjectScreen> {
  late String _view = widget.initialView;
  /// Mục mở đầu của tab Cài đặt (nút "Mời" mở thẳng Thành viên).
  String? _settingsTab;
  int _settingsRev = 0;
  TwStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    if (store.fullOf(widget.projectId) == null) store.openProject(widget.projectId);
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _setView(String v) {
    setState(() => _view = v);
    widget.onView?.call(v);
  }

  /// Mở tab Cài đặt của dự án (ngay trong màn hình dự án).
  void _settings([String? tab]) {
    setState(() {
      _settingsTab = tab;
      _settingsRev++;
    });
    _setView('settings');
  }

  Future<void> _create([String? statusId]) async {
    final f = store.fullOf(widget.projectId);
    if (f == null) return;
    final t = await createTaskDialog(context, store, f, statusId: statusId);
    if (t != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã tạo ${t.key}'), action: SnackBarAction(label: 'Mở', onPressed: () => openTask(context, store, t.key))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final f = store.fullOf(widget.projectId);
    if (f == null) {
      final body = Center(child: store.error != null ? Text(store.error!, style: TextStyle(color: look.red)) : const CircularProgressIndicator());
      return widget.embedded ? body : Scaffold(appBar: AppBar(), body: body);
    }
    final pr = f.project;
    // Máy tính: bấm một lần = xem nhanh (hộp thoại), bấm đúp = trang việc đầy đủ. Điện thoại: bấm là mở trang.
    final wideNow = twWide(context);
    void open(TwTask t) => wideNow ? showTaskPreview(context, store, t.key) : openTask(context, store, t.key);
    void openFull(TwTask t) => openTask(context, store, t.key);
    final full = wideNow ? openFull : null;
    final viewWidget = switch (_view) {
      'list' => TwListView(store: store, project: f, filter: widget.filter, onOpen: open, onOpenFull: full, onCreate: _create),
      'gantt' => TwGanttView(store: store, project: f, filter: widget.filter, onOpen: open, onOpenFull: full),
      'overview' => _overview(f, look),
      'settings' => TwSettingsPage(key: ValueKey('settings-$_settingsRev'), store: store, projectId: pr.id, inline: true, initialTab: _settingsTab ?? (twWide(context) ? 'statuses' : null)),
      _ => TwBoardView(store: store, project: f, filter: widget.filter, onOpen: open, onOpenFull: full, onCreate: _create),
    };
    final tabs = [('list', Icons.view_list_outlined, 'Danh sách'), ('kanban', Icons.view_kanban_outlined, 'Kanban'), ('gantt', Icons.timeline, 'Gantt'), ('overview', Icons.description_outlined, 'Tổng quan'), ('settings', Icons.tune, 'Cài đặt')];
    final users = [for (final m in f.members) if (m.subjectType == 'user') TwAssignee(kind: 'user', id: m.subjectId, name: m.name)];
    final groups = f.members.where((m) => m.subjectType == 'dept').map((m) => m.name).toList();
    if (!widget.embedded) {
      return Scaffold(
        backgroundColor: look.bg,
        appBar: AppBar(
          backgroundColor: look.bg,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Text(pr.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              key: const ValueKey('phone-filter'),
              tooltip: 'Lọc',
              icon: Icon(widget.filter.active ? Icons.filter_alt : Icons.filter_list),
              onPressed: () => twSheet(context, builder: (c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: FilterBar(store: store, project: f, filter: widget.filter, compact: true, onChanged: _changed))),
            ),
          ],
        ),
        body: Column(children: [
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 4, 12, 6), children: [
              for (final (k, _, label) in tabs.where((x) => x.$1 != 'overview'))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    key: ValueKey('view-$k'),
                    label: Text(label),
                    selected: _view == k,
                    showCheckmark: false,
                    selectedColor: look.accentSoft,
                    labelStyle: TextStyle(color: _view == k ? look.accent : look.sub, fontWeight: FontWeight.w600),
                    side: BorderSide.none,
                    onSelected: (_) => _setView(k),
                  ),
                ),
            ]),
          ),
          Expanded(child: viewWidget),
        ]),
        floatingActionButton: pr.canEdit && _view != 'settings' ? FloatingActionButton(key: const ValueKey('fab-task'), backgroundColor: look.accent, foregroundColor: Colors.white, onPressed: _create, child: const Icon(Icons.add)) : null,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Dải hình nền mảnh trên đầu màn hình dự án.
      TwCoverView(key: const ValueKey('project-cover-band'), cover: pr.cover, fallback: hexColor(pr.color, kTwAccent), height: 5),
      Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.divider))),
        // Phần tên giãn hết chỗ còn lại (Expanded), nhóm nút luôn sát mép phải.
        child: Row(children: [
          Expanded(
            child: Row(children: [
              ProjectBadge(pr, size: 26),
              const SizedBox(width: 10),
              Flexible(child: Text(pr.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              TwChip(kProjectStatusNames[pr.status]!, color: hexColor(kProjectStatusColors[pr.status]), icon: Icons.radio_button_checked),
              if (groups.isNotEmpty) ...[const SizedBox(width: 8), Flexible(child: Text('· ${groups.join(' + ')}', overflow: TextOverflow.ellipsis, style: TextStyle(color: look.sub, fontSize: 13)))],
            ]),
          ),
          const SizedBox(width: 12),
          TwAvatars(users, size: 28, max: 5),
          const SizedBox(width: 10),
          if (pr.canAdmin) OutlinedButton.icon(key: const ValueKey('invite'), onPressed: () => _settings('members'), icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Mời')),
          const SizedBox(width: 6),
          if (pr.canEdit) FilledButton.icon(key: const ValueKey('new-task'), onPressed: _create, icon: const Icon(Icons.add, size: 18), label: const Text('Việc mới')),
        ]),
      ),
      Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.divider))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (k, icon, label) in tabs)
            InkWell(
              key: ValueKey('view-$k'),
              onTap: () => _setView(k),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _view == k ? look.accent : Colors.transparent, width: 2))),
                child: Row(children: [
                  Icon(icon, size: 18, color: _view == k ? look.accent : look.sub),
                  const SizedBox(width: 6),
                  Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: _view == k ? look.accent : look.sub)),
                ]),
              ),
            ),
        ]),
      ),
      if (_view != 'overview' && _view != 'settings') FilterBar(store: store, project: f, filter: widget.filter, showGroup: _view == 'list', onChanged: _changed),
      Expanded(child: viewWidget),
    ]);
  }

  Widget _overview(TwProjectFull f, TwLook look) {
    final tasks = store.tasksOf(f.project.id).where((t) => t.deletedAt == null).toList();
    final open = tasks.where((t) => !(f.status(t.statusId)?.isClosed ?? false)).toList();
    final late = open.where((t) => t.due != null && t.due!.isBefore(store.today)).toList();
    final byPerson = <String, (TwAssignee, int)>{};
    for (final t in open) {
      for (final a in t.assignees) {
        byPerson[a.key] = (a, (byPerson[a.key]?.$2 ?? 0) + 1);
      }
    }
    final counts = {for (final c in kCategories) c: tasks.where((t) => f.status(t.statusId)?.category == c).length};
    Widget stat(String label, String v, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
              Text(label, style: TextStyle(color: look.sub)),
            ]),
          ),
        );
    return ListView(padding: const EdgeInsets.all(24), children: [
      if (f.project.description.isNotEmpty) ...[TwRichView(f.project.description), const SizedBox(height: 18)],
      Row(children: [
        stat('Tổng số việc', '${tasks.length}'),
        const SizedBox(width: 12),
        stat('Đang mở', '${open.length}'),
        const SizedBox(width: 12),
        stat('Quá hạn', '${late.length}', color: late.isEmpty ? null : look.red),
        const SizedBox(width: 12),
        stat('Đã xong', '${counts['done']}', color: look.ok),
      ]),
      const SizedBox(height: 16),
      CategoryBar(counts, height: 10),
      const SizedBox(height: 20),
      const Text('Việc đang mở theo người', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (final e in (byPerson.values.toList()..sort((a, b) => b.$2.compareTo(a.$2))))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            TwAvatar.of(e.$1, size: 26, border: false),
            const SizedBox(width: 10),
            SizedBox(width: 200, child: Text(e.$1.name, overflow: TextOverflow.ellipsis)),
            Expanded(child: ThinProgress(open.isEmpty ? 0 : e.$2 / open.length, color: look.accent)),
            const SizedBox(width: 10),
            Text('${e.$2}'),
          ]),
        ),
      if (late.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Quá hạn', style: TextStyle(fontWeight: FontWeight.w700, color: look.red)),
        for (final t in late)
          ListTile(dense: true, leading: StatusRing(f.status(t.statusId)), title: Text(t.title), subtitle: Text('${t.key} · hạn ${dShort(t.due!)}'), onTap: () => openTask(context, store, t.key)),
      ],
    ]);
  }
}

// ------------------------------------------------------------ tạo việc
/// Hộp tạo việc nhanh: tiêu đề, mô tả, trạng thái, người làm (người hoặc agent), ưu tiên, hạn, nhãn.
Future<TwTask?> createTaskDialog(BuildContext context, TwStore store, TwProjectFull f, {String? statusId, String? parentId}) =>
    twSheet<TwTask>(context, width: 640, builder: (c) => _CreateTask(store: store, f: f, statusId: statusId, parentId: parentId));

class _CreateTask extends StatefulWidget {
  const _CreateTask({required this.store, required this.f, this.statusId, this.parentId});
  final TwStore store;
  final TwProjectFull f;
  final String? statusId, parentId;
  @override
  State<_CreateTask> createState() => _CreateTaskState();
}

class _CreateTaskState extends State<_CreateTask> {
  final _title = TextEditingController();
  List<TBlock> _desc = [];
  late TwStatus? _status = widget.f.status(widget.statusId) ?? widget.f.defaultStatus;
  List<TwAssignee> _assignees = [];
  int _priority = 0;
  DateTime? _due;
  List<String> _labels = [];
  bool _busy = false, _more = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);
    try {
      final t = await widget.store.createTask(widget.f.project.id, {
        'title': title,
        if (_desc.any((b) => b.text.trim().isNotEmpty)) 'description': blocksToJson(_desc),
        if (_status != null) 'status_id': _status!.id,
        if (_assignees.isNotEmpty) 'assignees': [for (final a in _assignees) a.toJson()],
        if (_priority != 0) 'priority': _priority,
        if (_due != null) 'due': dayStr(_due!),
        if (_labels.isNotEmpty) 'labels': _labels,
        'parent_id': ?widget.parentId,
      });
      if (_status?.isStart == true && _assignees.any((a) => a.isAgent)) unawaited(widget.store.checkRuns());
      if (mounted) Navigator.pop(context, t);
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final f = widget.f;
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Việc mới · ${f.project.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            TextField(
              key: const ValueKey('nt-title'),
              controller: _title,
              autofocus: true,
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(hintText: 'Tên việc', border: InputBorder.none),
              onSubmitted: (_) => _save(),
            ),
            if (_more)
              TwRichEditor(blocks: _desc, onChanged: (b) => _desc = b, store: widget.store, projectId: f.project.id, compact: true)
            else
              InkWell(onTap: () => setState(() => _more = true), child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('Thêm mô tả…', style: TextStyle(color: look.sub)))),
          ]),
        ),
        Divider(height: 1, color: look.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TwPill(
              key: const ValueKey('nt-status'),
              onTap: () async {
                final s = await pickStatus(context, f, current: _status?.id);
                if (s != null) setState(() => _status = s);
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [StatusRing(_status), const SizedBox(width: 6), Text(_status?.name ?? 'Trạng thái')]),
            ),
            TwPill(
              key: const ValueKey('nt-assignee'),
              color: _assignees.isEmpty ? null : look.accent,
              onTap: () async {
                final r = await pickAssignees(context, widget.store, current: _assignees, projectId: f.project.id);
                if (r != null) setState(() => _assignees = r);
              },
              child: _assignees.isEmpty
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.person_outline), SizedBox(width: 5), Text('Người làm')])
                  : Row(mainAxisSize: MainAxisSize.min, children: [TwAvatars(_assignees, size: 20), const SizedBox(width: 6), Text(_assignees.map((a) => a.name.split(' (').first).join(', '))]),
            ),
            TwPill(
              onTap: () async {
                final v = await pickPriority(context, current: _priority);
                if (v != null) setState(() => _priority = v);
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [PriorityIcon(_priority, size: 16), const SizedBox(width: 5), Text(_priority == 0 ? 'Ưu tiên' : kPriorityNames[_priority]!)]),
            ),
            TwPill(
              key: const ValueKey('nt-due'),
              onTap: () async {
                final d = await pickDay(context, initial: _due, today: widget.store.today, help: 'Hạn');
                if (d != null) setState(() => _due = d);
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.event_outlined), const SizedBox(width: 5), Text(_due == null ? 'Hạn' : dShort(_due!))]),
            ),
            TwPill(
              onTap: () async {
                final r = await pickLabels(context, f, current: _labels);
                if (r != null) setState(() => _labels = r);
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.label_outline), const SizedBox(width: 5), Text(_labels.isEmpty ? 'Nhãn' : '${_labels.length} nhãn')]),
            ),
            const SizedBox(width: 12),
            FilledButton(key: const ValueKey('nt-save'), onPressed: _busy ? null : _save, child: const Text('Tạo việc')),
          ]),
        ),
        if (_assignees.any((a) => a.isAgent))
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Text(
              _status?.isStart == true ? 'Việc tạo thẳng vào "${_status!.name}" (trạng thái bắt đầu): agent sẽ bắt đầu làm ngay.' : 'Agent chưa chạy ngay: bấm Bắt đầu trên việc, hoặc kéo việc vào "${f.startStatus?.name ?? 'trạng thái bắt đầu'}".',
              style: TextStyle(fontSize: 12, color: look.ai),
            ),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ thông báo, tìm kiếm, cài đặt
class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key, required this.store});
  final TwStore store;
  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  @override
  void initState() {
    super.initState();
    widget.store.loadNotifications();
  }

  static const _icons = {
    'assigned': Icons.person_add_alt,
    'mention': Icons.alternate_email,
    'comment': Icons.chat_bubble_outline,
    'status': Icons.swap_horiz,
    'due': Icons.event_outlined,
    'agent': Icons.smart_toy_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final s = widget.store;
    if (s.notifications.isEmpty) return Center(child: Text('Chưa có thông báo', style: TextStyle(color: look.sub)));
    return RefreshIndicator(
      onRefresh: s.loadNotifications,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: s.notifications.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: look.divider, indent: 64),
        itemBuilder: (_, i) {
          final n = s.notifications[i];
          return ListTile(
            key: ValueKey('notif-${n.id}'),
            tileColor: n.read ? null : look.accentSoft.withValues(alpha: .5),
            leading: CircleAvatar(backgroundColor: look.surface2, child: Icon(_icons[n.type] ?? Icons.notifications_none, size: 20, color: n.type == 'agent' ? look.ai : look.sub)),
            title: Text(n.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([if (n.taskKey != null) n.taskKey!, timeAgo(n.at, s.now)].join(' · '), style: TextStyle(color: look.sub, fontSize: 12)),
            onTap: () {
              if (!n.read) {
                setState(() => n.read = true);
                s.unread = (s.unread - 1).clamp(0, 9999);
                s.api.markRead(ids: [n.id]).ignore();
              }
              final k = n.taskKey ?? n.taskId;
              if (k != null) openTask(context, s, k);
            },
          );
        },
      ),
    );
  }
}

class SearchView extends StatefulWidget {
  const SearchView({super.key, required this.store, this.phone = false});
  final TwStore store;
  final bool phone;
  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _q = TextEditingController();
  List<TwTask>? _r;
  Timer? _deb;
  bool _busy = false;

  void _search(String q) {
    _deb?.cancel();
    if (q.trim().length < 2) return setState(() => _r = null);
    _deb = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _busy = true);
      try {
        final r = await widget.store.api.search(q.trim());
        if (mounted) setState(() => _r = r);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final s = widget.store;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(widget.phone ? 14 : 20, 12, widget.phone ? 14 : 20, 8),
        child: TextField(
          key: const ValueKey('search-q'),
          controller: _q,
          autofocus: !widget.phone,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            hintText: 'Tìm việc trong mọi dự án (tên, mô tả, bình luận)…',
            filled: true,
            fillColor: look.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
          onChanged: _search,
        ),
      ),
      Expanded(
        child: _r == null
            ? Center(child: Text('Gõ ít nhất 2 ký tự để tìm', style: TextStyle(color: look.sub)))
            : _r!.isEmpty
                ? Center(child: Text('Không thấy việc nào', style: TextStyle(color: look.sub)))
                : ListView(children: [
                    for (final t in _r!)
                      ListTile(
                        key: ValueKey('result-${t.key}'),
                        leading: StatusRing(s.statusOf(t)),
                        title: Text(t.title),
                        subtitle: Text([t.key, s.projectById(t.projectId)?.name ?? ''].where((x) => x.isNotEmpty).join(' · ')),
                        onTap: () => openTask(context, s, t.key),
                      ),
                  ]),
      ),
    ]);
  }
}

/// Bật / tắt từng loại tin bot nhắn riêng.
Future<void> showPrefs(BuildContext context, TwStore store) => twSheet(context, width: 420, builder: (c) => _Prefs(store: store));

class _Prefs extends StatefulWidget {
  const _Prefs({required this.store});
  final TwStore store;
  @override
  State<_Prefs> createState() => _PrefsState();
}

class _PrefsState extends State<_Prefs> {
  static const kinds = {
    'assigned': 'Được giao / bỏ giao việc',
    'mention': 'Được @nhắc',
    'comment': 'Bình luận mới trên việc mình làm / theo dõi',
    'status': 'Đổi trạng thái, đổi hạn',
    'due': 'Sắp tới hạn, quá hạn (8:00 sáng)',
    'agent': 'Agent làm xong / báo vướng',
  };
  late final Map<String, bool> _dm = {for (final k in kinds.keys) k: (widget.store.prefs['dm'] as Map?)?[k] != false};

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(context, 'Tin nhắn của bot Làm việc nhóm'),
        for (final e in kinds.entries)
          SwitchListTile(
            key: ValueKey('pref-${e.key}'),
            value: _dm[e.key]!,
            title: Text(e.value),
            onChanged: (v) async {
              setState(() => _dm[e.key] = v);
              try {
                final r = await widget.store.api.putPrefs({'dm': _dm});
                widget.store.prefs = r['prefs'] is Map ? (r['prefs'] as Map).cast<String, dynamic>() : {'dm': _dm};
              } catch (_) {}
            },
          ),
        const SizedBox(height: 12),
      ]);
}
