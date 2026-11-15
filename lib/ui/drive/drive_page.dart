// Drive (Nextcloud) native kiểu Google Drive: Drive của tôi / Được chia sẻ / Gần đây / Gắn sao / Ngoại tuyến / Thùng rác,
// lưới hoặc danh sách, sắp xếp, tìm kiếm có bộ lọc, đường dẫn thư mục, chọn nhiều, chi tiết + hoạt động, chia sẻ.
// Điện thoại: thanh tìm kiếm + chip lọc, nút "Mới", thanh điều hướng dưới. Máy tính: cột trái, danh sách, panel chi tiết,
// kéo-thả tệp từ máy để tải lên. Office mở OnlyOffice (webview); ảnh / PDF / video xem trong app.
import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../common.dart' show pickFilesOrReport;
import '../desk_tabs.dart' show DeskTabScope;
import '../theme.dart' show toast;
import 'actions.dart';
import 'api.dart';
import 'look.dart';
import 'session.dart';
import 'uploads.dart';

/// Mở Drive (ô app Drive, hoặc link tới một thư mục [path]).
Future<void> openDrive(BuildContext context, MiniApp app, {String? path}) async {
  final state = context.read<AppState>();
  final nav = Navigator.of(context);
  final tab = DeskTabScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final s = await DriveSession.current(state, app: app);
    if (s == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
    await nav.push(AppPageRoute(builder: (_) => DriveHome(session: s, title: app.name, startPath: path)));
    tab?.onTitle?.call(null);
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

enum DriveSection { my, shared, recent, starred, offline, trash }

enum DriveSort { name, modified, size }

class DriveHome extends StatefulWidget {
  const DriveHome({super.key, required this.session, this.title = 'Drive', this.startPath});
  final DriveSession session;
  final String title;
  final String? startPath;
  @override
  State<DriveHome> createState() => _DriveHomeState();
}

class _DriveHomeState extends State<DriveHome> with WidgetsBindingObserver {
  DriveSection _section = DriveSection.my;
  String _path = '/';
  List<DriveItem>? _items;
  Object? _error;
  bool _grid = false, _desc = false, _details = false, _dragging = false;
  DriveSort _sort = DriveSort.name;
  final _sel = <String>{};
  String? _focus;
  // Tìm kiếm
  final _q = TextEditingController();
  bool _searching = false;
  String? _type, _owner;
  int? _days;
  final _scaffold = GlobalKey<ScaffoldState>();
  int _loadSeq = 0;

  DriveSession get s => widget.session;
  DriveApi get api => s.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.startPath != null) _path = widget.startPath!;
    s.uploads.addListener(_changed);
    s.offline.addListener(_changed);
    s.uploads.onDone = (j) {
      if (mounted && _section == DriveSection.my && j.dir == _path) _reload(quiet: true);
    };
    s.loadMe().then((_) => _changed()).catchError((_) {});
    _reload();
    s.offline.sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.uploads.removeListener(_changed);
    s.offline.removeListener(_changed);
    s.uploads.onDone = null;
    _q.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed) {
      _reload(quiet: true);
      s.offline.sync();
      s.uploads.scanCamera();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _searchMode => _searching && (_q.text.trim().isNotEmpty || _type != null || _owner != null || _days != null);

  Future<void> _reload({bool quiet = false}) async {
    final seq = ++_loadSeq;
    if (!quiet) {
      setState(() {
        _items = null;
        _error = null;
      });
    }
    try {
      final List<DriveItem> list;
      if (_searchMode) {
        list = await api.search(q: _q.text.trim(), type: _type, owner: _owner, since: _days == null ? null : DateTime.now().millisecondsSinceEpoch ~/ 1000 - _days! * 86400);
      } else {
        list = switch (_section) {
          DriveSection.my => await api.list(_path),
          DriveSection.shared => await api.shared(),
          DriveSection.recent => await api.recent(),
          DriveSection.starred => await api.starred(),
          DriveSection.trash => await api.trash(),
          DriveSection.offline => [for (final e in s.offline.roots) e.item],
        };
      }
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _items = list;
        _error = null;
        _sel.removeWhere((p) => !list.any((i) => i.path == p));
      });
    } catch (e) {
      if (seq != _loadSeq || !mounted) return;
      // Mất mạng: vẫn cho xem các mục đã ghim.
      setState(() {
        _error = e;
        if (!quiet) _items = null;
      });
    }
  }

  void _goSection(DriveSection sec) {
    setState(() {
      _section = sec;
      _path = '/';
      _sel.clear();
      _focus = null;
      _searching = false;
      _q.clear();
      _type = _owner = null;
      _days = null;
    });
    if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
    _reload();
  }

  void _openFolder(String path) {
    setState(() {
      _section = DriveSection.my;
      _path = path;
      _sel.clear();
      _focus = null;
      _searching = false;
      _q.clear();
      _type = _owner = null;
      _days = null;
    });
    _reload();
  }

  List<DriveItem> get _sorted {
    final list = [...?_items];
    if (_section == DriveSection.recent && !_searchMode) return list;
    if (_section == DriveSection.trash) return list;
    int cmp(DriveItem a, DriveItem b) {
      final r = switch (_sort) {
        DriveSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        DriveSort.modified => a.mtime.compareTo(b.mtime),
        DriveSort.size => a.size.compareTo(b.size),
      };
      return _desc ? -r : r;
    }

    list.sort((a, b) => a.dir != b.dir ? (a.dir ? -1 : 1) : cmp(a, b));
    return list;
  }

  String get _sectionTitle => switch (_section) {
        DriveSection.my => tr('Drive của tôi'),
        DriveSection.shared => tr('Được chia sẻ với tôi'),
        DriveSection.recent => tr('Gần đây'),
        DriveSection.starred => tr('Có gắn dấu sao'),
        DriveSection.offline => tr('Ngoại tuyến'),
        DriveSection.trash => tr('Thùng rác'),
      };

  // ------------------------------------------------------------------ thao tác
  Future<void> _tap(DriveItem it, {bool wide = false}) async {
    if (_sel.isNotEmpty && !wide) {
      _toggle(it);
      return;
    }
    if (wide) {
      setState(() {
        _sel
          ..clear()
          ..add(it.path);
        _focus = it.path;
      });
      return;
    }
    await _open(it);
  }

  Future<void> _open(DriveItem it) async {
    if (_section == DriveSection.trash) return;
    if (it.dir) return _openFolder(it.path);
    await openDriveFile(context, s, it, siblings: _sorted);
  }

  void _toggle(DriveItem it) => setState(() {
        _sel.contains(it.path) ? _sel.remove(it.path) : _sel.add(it.path);
        _focus = _sel.isEmpty ? null : it.path;
      });

  List<DriveItem> get _selected => [for (final i in _items ?? <DriveItem>[]) if (_sel.contains(i.path)) i];

  Future<void> _bulk(ItemAction a) async {
    final items = _selected;
    if (items.isEmpty) return;
    await runItemAction(context, s, a, items, onChanged: () {
      if (a != ItemAction.star && a != ItemAction.offline) _sel.clear();
      _reload(quiet: true);
    });
    _changed();
  }

  Future<void> _newMenu(BuildContext ctx, {Offset? at}) async {
    final l = DriveLook.of(ctx);
    final items = <(String, IconData, Color, String)>[
      ('folder', Icons.create_new_folder_rounded, l.folder, tr('Thư mục mới')),
      ('upload', Icons.upload_file_rounded, l.accent, tr('Tải tệp lên')),
      if (!driveWide(ctx)) ('media', Icons.photo_library_rounded, const Color(0xFF8E44AD), tr('Tải ảnh hoặc video lên')),
      ('docx', Icons.description_rounded, const Color(0xFF2B579A), tr('Tài liệu Word')),
      ('xlsx', Icons.table_chart_rounded, const Color(0xFF1E7B45), tr('Bảng tính Excel')),
      ('pptx', Icons.slideshow_rounded, const Color(0xFFC4501F), tr('Bản trình bày PowerPoint')),
    ];
    String? v;
    if (at != null) {
      v = await showMenu<String>(
        context: ctx,
        position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        items: [
          for (final (id, icon, color, label) in items) ...[
            if (id == 'docx') const PopupMenuDivider(),
            PopupMenuItem(value: id, height: 44, child: Row(children: [Icon(icon, color: color, size: 22), const SizedBox(width: 14), Text(label)])),
          ],
        ],
      );
    } else {
      v = await showModalBottomSheet<String>(
        context: ctx,
        showDragHandle: true,
        backgroundColor: l.surface,
        builder: (sh) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(children: [
              for (final (id, icon, color, label) in items)
                SizedBox(
                  width: (MediaQuery.sizeOf(sh).width - 24) / 3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(sh, id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(children: [
                        CircleAvatar(radius: 26, backgroundColor: l.surface2, child: Icon(icon, color: color, size: 26)),
                        const SizedBox(height: 8),
                        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
    }
    if (v == null || !mounted) return;
    final dir = _section == DriveSection.my ? _path : '/';
    switch (v) {
      case 'folder':
        final name = await askName(context, title: tr('Thư mục mới'), initial: tr('Thư mục không có tiêu đề'), ok: tr('Tạo'), selectStem: false);
        if (name == null || name.isEmpty || !mounted) return;
        await driveRun(context, () => api.mkdir(dir, name));
        if (_section != DriveSection.my) _goSection(DriveSection.my);
        _reload(quiet: true);
      case 'upload':
      case 'media':
        final files = await pickFilesOrReport(context, type: v == 'media' ? FileType.media : FileType.any);
        if (files.isEmpty || !mounted) return;
        await s.uploads.add([for (final f in files) if (f.path != null) (f.path!, f.name)], dir);
        if (mounted) driveToast(context, tr('Đang tải {0} tệp lên', ['${files.length}']));
      default:
        final name = await askName(context,
            title: switch (v) { 'docx' => tr('Tài liệu Word mới'), 'xlsx' => tr('Bảng tính Excel mới'), _ => tr('Bản trình bày mới') },
            initial: switch (v) { 'docx' => tr('Tài liệu không có tiêu đề'), 'xlsx' => tr('Bảng tính không có tiêu đề'), _ => tr('Bản trình bày không có tiêu đề') },
            ok: tr('Tạo'),
            selectStem: false);
        if (name == null || name.isEmpty || !mounted) return;
        DriveItem? created;
        await driveRun(context, () async => created = (await api.officeNew(dir, v!, name: name)).$1);
        _reload(quiet: true);
        if (created != null && mounted) await openOffice(context, s, created!);
    }
  }

  // ------------------------------------------------------------------ bố cục
  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context);
    final wide = driveWide(context);
    return Provider<DriveSession?>.value(
      value: s,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => _sel.isNotEmpty ? setState(_sel.clear) : Navigator.maybePop(context),
          const SingleActivator(LogicalKeyboardKey.delete): () => _sel.isNotEmpty && _section != DriveSection.trash ? _bulk(ItemAction.trash) : null,
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => setState(() => _sel.addAll([for (final i in _items ?? <DriveItem>[]) i.path])),
          const SingleActivator(LogicalKeyboardKey.enter): () {
            final it = _items?.where((i) => i.path == _focus).firstOrNull;
            if (it != null) _open(it);
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: _scaffold,
            backgroundColor: l.bg,
            drawer: wide ? null : Drawer(backgroundColor: l.bg, child: SafeArea(child: _side(l, drawer: true))),
            body: SafeArea(child: wide ? _wideBody(l) : _phoneBody(l)),
            floatingActionButton: wide || _section == DriveSection.trash || _sel.isNotEmpty
                ? null
                : Builder(
                    builder: (c) => FloatingActionButton.extended(
                      backgroundColor: l.accentSoft,
                      foregroundColor: l.accentText,
                      onPressed: () => _newMenu(c),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(tr('Mới'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
            bottomNavigationBar: wide ? null : _bottomNav(l),
          ),
        ),
      ),
    );
  }

  Widget _bottomNav(DriveLook l) {
    const tabs = [DriveSection.my, DriveSection.recent, DriveSection.starred, DriveSection.shared];
    final i = tabs.indexOf(_section);
    return NavigationBar(
      backgroundColor: l.surface,
      indicatorColor: l.accentSoft,
      height: 68,
      selectedIndex: i < 0 ? 0 : i,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (k) => _goSection(tabs[k]),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.folder_outlined), selectedIcon: const Icon(Icons.folder_rounded), label: tr('Drive của tôi')),
        NavigationDestination(icon: const Icon(Icons.schedule_outlined), selectedIcon: const Icon(Icons.schedule_rounded), label: tr('Gần đây')),
        NavigationDestination(icon: const Icon(Icons.star_outline_rounded), selectedIcon: const Icon(Icons.star_rounded), label: tr('Gắn sao')),
        NavigationDestination(icon: const Icon(Icons.people_outline_rounded), selectedIcon: const Icon(Icons.people_rounded), label: tr('Được chia sẻ')),
      ],
    );
  }

  Widget _side(DriveLook l, {bool drawer = false}) {
    Widget nav(DriveSection sec, IconData icon, String label, {String? tag}) {
      final on = _section == sec && !_searchMode;
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Material(
          color: on ? l.accentSoft : Colors.transparent,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
          child: InkWell(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
            onTap: () => _goSection(sec),
            child: SizedBox(
              height: 40,
              child: Row(children: [
                const SizedBox(width: 20),
                Icon(icon, size: 21, color: on ? l.accentText : l.text),
                const SizedBox(width: 16),
                Expanded(child: Text(label, style: TextStyle(color: on ? l.accentText : l.text, fontWeight: on ? FontWeight.w600 : FontWeight.w400))),
                if (tag != null) Padding(padding: const EdgeInsets.only(right: 10), child: Text(tag, style: TextStyle(fontSize: 12, color: l.muted))),
              ]),
            ),
          ),
        ),
      );
    }

    final me = s.me;
    final up = s.uploads;
    return ListView(padding: const EdgeInsets.only(top: 4, bottom: 16), children: [
      if (drawer)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(children: [
            Icon(Icons.add_to_drive_rounded, color: l.accent, size: 30),
            const SizedBox(width: 10),
            Text(widget.title, style: TextStyle(fontSize: 20, color: l.text)),
          ]),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 0, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (c) => Material(
                color: l.surface,
                elevation: 2,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTapDown: (d) => _newMenu(c, at: d.globalPosition),
                  onTap: () {},
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 22, 16),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_rounded, color: l.text, size: 24),
                      const SizedBox(width: 12),
                      Text(tr('Mới'), style: TextStyle(fontWeight: FontWeight.w500, color: l.text)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      nav(DriveSection.my, Icons.folder_outlined, tr('Drive của tôi')),
      nav(DriveSection.shared, Icons.people_outline_rounded, tr('Được chia sẻ với tôi')),
      nav(DriveSection.recent, Icons.schedule_outlined, tr('Gần đây')),
      nav(DriveSection.starred, Icons.star_outline_rounded, tr('Có gắn dấu sao')),
      nav(DriveSection.offline, Icons.download_for_offline_outlined, tr('Ngoại tuyến'), tag: s.offline.roots.isEmpty ? null : '${s.offline.roots.length}'),
      nav(DriveSection.trash, Icons.delete_outline_rounded, tr('Thùng rác')),
      Divider(indent: 20, endIndent: 12, color: l.line),
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 20, right: 8),
          dense: true,
          leading: Icon(up.activeCount > 0 ? Icons.cloud_upload_rounded : Icons.cloud_upload_outlined, color: up.activeCount > 0 ? l.accent : l.text),
          title: Text(tr('Tải lên')),
          trailing: up.activeCount > 0 ? Text('${up.activeCount}', style: TextStyle(color: l.accentText, fontWeight: FontWeight.w600)) : null,
          onTap: () {
            if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
            Navigator.of(context).push(AppPageRoute(builder: (_) => UploadsPage(session: s)));
          },
        ),
      ),
      if (me != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (me.total > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: (me.used / me.total).clamp(0, 1), minHeight: 4, color: l.accent, backgroundColor: l.line),
              ),
            const SizedBox(height: 6),
            Text(me.total > 0 ? tr('Đã dùng {0} / {1}', [fmtSize(me.used), fmtSize(me.total)]) : tr('Đã dùng {0}', [fmtSize(me.used)]),
                style: TextStyle(fontSize: 13, color: l.muted)),
          ]),
        ),
    ]);
  }

  Widget _searchBar(DriveLook l, {required bool wide}) => Container(
        height: wide ? 48 : 50,
        decoration: BoxDecoration(color: l.surface2, borderRadius: BorderRadius.circular(25)),
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Row(children: [
          if (!wide)
            IconButton(
              icon: Icon(_searching ? Icons.arrow_back_rounded : Icons.menu_rounded, color: l.muted),
              onPressed: () {
                if (_searching) {
                  setState(() {
                    _searching = false;
                    _q.clear();
                    _type = _owner = null;
                    _days = null;
                  });
                  _reload();
                } else {
                  _scaffold.currentState?.openDrawer();
                }
              },
            )
          else
            Padding(padding: const EdgeInsets.only(left: 10, right: 4), child: Icon(Icons.search_rounded, color: l.muted)),
          Expanded(
            child: TextField(
              controller: _q,
              onTap: () => setState(() => _searching = true),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                setState(() => _searching = true);
                _reload();
              },
              decoration: InputDecoration(border: InputBorder.none, hintText: tr('Tìm trong Drive'), hintStyle: TextStyle(color: l.muted, fontSize: 16)),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          if (_q.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close_rounded, color: l.muted),
              onPressed: () {
                _q.clear();
                _reload();
              },
            ),
          IconButton(
            tooltip: tr('Bộ lọc'),
            icon: Icon(Icons.tune_rounded, color: _searching ? l.accentText : l.muted),
            onPressed: () => setState(() => _searching = !_searching),
          ),
          if (!wide) _uploadsButton(l),
        ]),
      );

  Widget _uploadsButton(DriveLook l) {
    final up = s.uploads;
    final n = up.activeCount;
    return IconButton(
      tooltip: tr('Tải lên'),
      onPressed: () => Navigator.of(context).push(AppPageRoute(builder: (_) => UploadsPage(session: s))),
      icon: n == 0
          ? Icon(Icons.cloud_upload_outlined, color: l.muted)
          : Stack(alignment: Alignment.center, children: [
              SizedBox(width: 26, height: 26, child: CircularProgressIndicator(value: up.overall == 0 ? null : up.overall, strokeWidth: 2.5, color: l.accent)),
              Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: l.accentText)),
            ]),
    );
  }

  Widget _chips(DriveLook l) {
    Future<void> pick<T>(String title, List<(T?, String)> opts, T? cur, void Function(T?) set) async {
      final v = await showModalBottomSheet<(T?,)>(
        context: context,
        backgroundColor: l.surface,
        showDragHandle: true,
        builder: (sh) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
            for (final (val, label) in opts)
              ListTile(title: Text(label), trailing: val == cur ? Icon(Icons.check_rounded, color: l.accent) : null, onTap: () => Navigator.pop(sh, (val,))),
          ]),
        ),
      );
      if (v == null) return;
      setState(() {
        set(v.$1);
        _searching = true;
      });
      _reload();
    }

    Widget chip(String label, bool on, VoidCallback tap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [Text(label), const SizedBox(width: 2), const Icon(Icons.arrow_drop_down_rounded, size: 18)]),
            selected: on,
            showCheckmark: false,
            selectedColor: l.accentSoft,
            labelStyle: TextStyle(color: on ? l.accentText : l.text, fontSize: 13),
            side: BorderSide(color: on ? Colors.transparent : l.line),
            onSelected: (_) => tap(),
          ),
        );
    final types = <(String?, String)>[
      (null, tr('Mọi loại')), ('folder', tr('Thư mục')), ('doc', tr('Tài liệu')), ('sheet', tr('Bảng tính')), ('slide', tr('Bản trình bày')),
      ('pdf', 'PDF'), ('image', tr('Ảnh')), ('video', 'Video'), ('audio', tr('Âm thanh')), ('archive', tr('Tệp nén')),
    ];
    final owners = <(String?, String)>[(null, tr('Mọi người')), ('me', tr('Tôi sở hữu')), ('others', tr('Người khác sở hữu'))];
    final days = <(int?, String)>[(null, tr('Mọi lúc')), (1, tr('Hôm nay')), (7, tr('7 ngày qua')), (30, tr('30 ngày qua')), (365, tr('Năm nay'))];
    return SizedBox(
      height: 44,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
        chip(types.firstWhere((t) => t.$1 == _type).$2.replaceFirst(tr('Mọi loại'), tr('Loại')), _type != null, () => pick(tr('Loại'), types, _type, (v) => _type = v)),
        chip(owners.firstWhere((t) => t.$1 == _owner).$2.replaceFirst(tr('Mọi người'), tr('Người')), _owner != null, () => pick(tr('Người'), owners, _owner, (v) => _owner = v)),
        chip(days.firstWhere((t) => t.$1 == _days).$2.replaceFirst(tr('Mọi lúc'), tr('Sửa đổi')), _days != null, () => pick(tr('Sửa đổi'), days, _days, (v) => _days = v)),
      ]),
    );
  }

  Widget _breadcrumbs(DriveLook l, {double size = 22}) {
    if (_searchMode) return Text(tr('Kết quả tìm kiếm'), style: TextStyle(fontSize: size, color: l.text));
    if (_section != DriveSection.my) return Text(_sectionTitle, style: TextStyle(fontSize: size, color: l.text));
    final parts = _path.split('/').where((x) => x.isNotEmpty).toList();
    final crumbs = <Widget>[
      _crumb(l, tr('Drive của tôi'), '/', parts.isEmpty, size),
      for (var i = 0; i < parts.length; i++) ...[
        Icon(Icons.chevron_right_rounded, color: l.muted, size: size),
        _crumb(l, parts[i], '/${parts.sublist(0, i + 1).join('/')}', i == parts.length - 1, size),
      ],
    ];
    return SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: Row(children: crumbs));
  }

  Widget _crumb(DriveLook l, String label, String path, bool cur, double size) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: cur ? null : () => _openFolder(path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, style: TextStyle(fontSize: size, color: cur ? l.text : l.muted)),
        ),
      );

  Widget _sortRow(DriveLook l, {required bool wide}) {
    final label = switch (_sort) { DriveSort.name => tr('Tên'), DriveSort.modified => tr('Sửa đổi lần cuối'), DriveSort.size => tr('Kích thước') };
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 12 : 6, 0, 6, 0),
      child: Row(children: [
        if (_section != DriveSection.recent && _section != DriveSection.trash)
          PopupMenuButton<DriveSort>(
            tooltip: tr('Sắp xếp'),
            onSelected: (v) {
              setState(() {
                if (v == _sort) {
                  _desc = !_desc;
                } else {
                  _sort = v;
                  _desc = v != DriveSort.name;
                }
              });
            },
            itemBuilder: (_) => [
              for (final (v, t) in [(DriveSort.name, tr('Tên')), (DriveSort.modified, tr('Sửa đổi lần cuối')), (DriveSort.size, tr('Kích thước'))])
                CheckedPopupMenuItem(value: v, checked: v == _sort, child: Text(t)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: TextStyle(color: l.text, fontWeight: FontWeight.w500, fontSize: 13.5)),
                const SizedBox(width: 4),
                Icon(_desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 18, color: l.text),
              ]),
            ),
          )
        else if (_section == DriveSection.trash && (_items?.isNotEmpty ?? false))
          TextButton.icon(
            onPressed: () async {
              if (!await confirmDrive(context, tr('Dọn sạch thùng rác?'), tr('Mọi mục trong thùng rác sẽ bị xoá vĩnh viễn.'), ok: tr('Dọn sạch'), danger: true)) return;
              if (!mounted) return;
              await driveRun(context, api.emptyTrash, done: tr('Đã dọn sạch thùng rác'));
              _reload();
            },
            icon: Icon(Icons.delete_sweep_rounded, color: l.danger),
            label: Text(tr('Dọn sạch thùng rác'), style: TextStyle(color: l.danger)),
          ),
        const Spacer(),
        if (wide) ...[
          _seg(l, Icons.view_list_rounded, !_grid, () => setState(() => _grid = false)),
          _seg(l, Icons.grid_view_rounded, _grid, () => setState(() => _grid = true)),
          const SizedBox(width: 6),
          _seg(l, Icons.info_outline_rounded, _details, () => setState(() => _details = !_details)),
        ] else
          IconButton(icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded, color: l.muted), onPressed: () => setState(() => _grid = !_grid)),
      ]),
    );
  }

  Widget _seg(DriveLook l, IconData icon, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Material(
          color: on ? l.accentSoft : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: on ? Colors.transparent : l.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: tap,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), child: Icon(icon, size: 20, color: on ? l.accentText : l.muted)),
          ),
        ),
      );

  /// Thanh khi đang chọn nhiều mục.
  Widget _selectionBar(DriveLook l) {
    final items = _selected;
    final acts = actionsFor(s, items, trash: _section == DriveSection.trash)
        .where((a) => const {ItemAction.share, ItemAction.offline, ItemAction.star, ItemAction.move, ItemAction.copy, ItemAction.trash, ItemAction.restore, ItemAction.purge, ItemAction.chat, ItemAction.download}.contains(a.$1))
        .toList();
    final main = acts.take(driveWide(context) ? 8 : 3).toList(), more = acts.skip(main.length).toList();
    return Container(
      height: 52,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(color: l.surface2, borderRadius: BorderRadius.circular(26)),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_sel.clear)),
        Expanded(child: Text(tr('Đã chọn {0}', ['${items.length}']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w500, color: l.text))),
        for (final (id, icon, label) in main) IconButton(tooltip: label, icon: Icon(icon, color: id == ItemAction.trash || id == ItemAction.purge ? l.danger : l.text), onPressed: () => _bulk(id)),
        if (more.isNotEmpty)
          PopupMenuButton<ItemAction>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _bulk,
            itemBuilder: (_) => [for (final (id, icon, label) in more) PopupMenuItem(value: id, child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]))],
          ),
      ]),
    );
  }

  Widget _phoneBody(DriveLook l) => Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 6), child: _sel.isNotEmpty ? _selectionBar(l) : _searchBar(l, wide: false)),
        if (_searching && _sel.isEmpty) _chips(l),
        if (_section == DriveSection.my && !_searchMode && _path != '/')
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => _openFolder(parentOf(_path))),
              Expanded(child: _breadcrumbs(l, size: 16)),
            ]),
          ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: l.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            child: Column(children: [
              _sortRow(l, wide: false),
              Expanded(child: _content(l, wide: false)),
            ]),
          ),
        ),
      ]);

  Widget _wideBody(DriveLook l) {
    final focus = _details ? _items?.where((i) => i.path == _focus).firstOrNull : null;
    return Column(children: [
      SizedBox(
        height: 64,
        child: Row(children: [
          SizedBox(
            width: 256,
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.maybePop(context)),
              Icon(Icons.add_to_drive_rounded, color: l.accent, size: 32),
              const SizedBox(width: 10),
              Text(widget.title, style: TextStyle(fontSize: 21, color: l.text)),
            ]),
          ),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _searchBar(l, wide: true)))),
          const SizedBox(width: 12),
          _uploadsButton(l),
          const SizedBox(width: 12),
        ]),
      ),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 256, child: _side(l)),
          Expanded(
            child: DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (d) async {
                setState(() => _dragging = false);
                final dir = _section == DriveSection.my ? _path : '/';
                await s.uploads.add([for (final f in d.files) (f.path, f.name)], dir);
                if (mounted) driveToast(context, tr('Đang tải {0} tệp lên', ['${d.files.length}']));
              },
              child: Stack(children: [
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(color: l.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.fromLTRB(14, 12, 16, 4), child: _breadcrumbs(l)),
                    if (_sel.isNotEmpty) _selectionBar(l) else if (_searching) Padding(padding: const EdgeInsets.only(top: 4), child: _chips(l)),
                    _sortRow(l, wide: true),
                    Expanded(child: _content(l, wide: true)),
                  ]),
                ),
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: l.accentSoft.withValues(alpha: .85),
                          border: Border.all(color: l.accent, width: 2),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Center(
                          child: Text(tr('Thả tệp để tải lên "{0}"', [_section == DriveSection.my && _path != '/' ? _path.split('/').last : tr('Drive của tôi')]),
                              style: TextStyle(color: l.accentText, fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          if (_details)
            Container(
              width: 340,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(color: l.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
              child: focus == null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Chọn một mục để xem chi tiết'), textAlign: TextAlign.center, style: TextStyle(color: l.muted))))
                  : DetailsPanel(session: s, item: focus, onClose: () => setState(() => _details = false)),
            ),
        ]),
      ),
    ]);
  }

  Widget _content(DriveLook l, {required bool wide}) {
    final items = _items;
    if (items == null && _error == null) return const Center(child: CircularProgressIndicator());
    if (items == null) {
      return _empty(l, Icons.cloud_off_rounded, tr('Không tải được'), '$_error', action: (tr('Thử lại'), _reload), extra: s.offline.roots.isEmpty ? null : (tr('Xem tệp ngoại tuyến'), () => _goSection(DriveSection.offline)));
    }
    final list = _sorted;
    if (list.isEmpty) {
      return switch (_section) {
        _ when _searchMode => _empty(l, Icons.search_off_rounded, tr('Không tìm thấy tệp nào'), tr('Thử từ khoá hoặc bộ lọc khác')),
        DriveSection.trash => _empty(l, Icons.delete_outline_rounded, tr('Thùng rác trống'), tr('Mục bị xoá nằm ở đây, có thể khôi phục.')),
        DriveSection.starred => _empty(l, Icons.star_outline_rounded, tr('Chưa có mục gắn sao'), tr('Gắn sao để tìm lại nhanh.')),
        DriveSection.offline => _empty(l, Icons.download_for_offline_outlined, tr('Chưa có tệp ngoại tuyến'), tr('Chọn "Dùng khi không có mạng" trên tệp hoặc thư mục.')),
        DriveSection.shared => _empty(l, Icons.people_outline_rounded, tr('Chưa có gì được chia sẻ'), tr('Tệp người khác chia sẻ cho bạn sẽ hiện ở đây.')),
        _ => _empty(l, Icons.folder_open_rounded, tr('Thư mục trống'), wide ? tr('Kéo tệp vào đây hoặc bấm "Mới".') : tr('Bấm "Mới" để tải tệp lên.')),
      };
    }
    final body = _grid ? _gridView(l, list, wide) : (wide ? _table(l, list) : _listView(l, list));
    return RefreshIndicator(onRefresh: () => _reload(quiet: true), child: body);
  }

  Widget _empty(DriveLook l, IconData icon, String title, String sub, {(String, VoidCallback)? action, (String, VoidCallback)? extra}) => ListView(children: [
        const SizedBox(height: 80),
        Icon(icon, size: 72, color: l.line),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: l.text)),
        const SizedBox(height: 6),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Text(sub, textAlign: TextAlign.center, style: TextStyle(color: l.muted))),
        if (action != null) Center(child: Padding(padding: const EdgeInsets.only(top: 14), child: FilledButton(onPressed: action.$2, child: Text(action.$1)))),
        if (extra != null) Center(child: TextButton(onPressed: extra.$2, child: Text(extra.$1))),
      ]);

  String _subtitle(DriveItem it) {
    final parts = <String>[];
    if (s.offline.pinned(it.path)) parts.add(tr('Ngoại tuyến'));
    if (it is DriveTrashItem) {
      parts.add(tr('Xoá {0}', [fmtDate(it.deleted)]));
      parts.add(it.original);
      return parts.join(' · ');
    }
    if (it.shared && _section != DriveSection.shared) parts.add(tr('Đã chia sẻ'));
    if (_section == DriveSection.shared && it.ownerName.isNotEmpty) parts.add(it.ownerName);
    if (it.mtime > 0) parts.add(tr('Sửa {0}', [fmtDate(it.mtime)]));
    if (!it.dir) parts.add(fmtSize(it.size));
    return parts.join(' · ');
  }

  Widget _offlineMark(DriveLook l, DriveItem it, {double size = 14}) {
    if (s.offline.busy.contains(it.path)) return SizedBox(width: size, height: size, child: CircularProgressIndicator(strokeWidth: 1.6, color: l.ok));
    if (s.offline.pinned(it.path)) return Icon(Icons.check_circle_outline_rounded, size: size, color: l.ok);
    return const SizedBox.shrink();
  }

  Widget _listView(DriveLook l, List<DriveItem> list) => ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final it = list[i];
          final sel = _sel.contains(it.path);
          return Material(
            color: sel ? l.sel : Colors.transparent,
            child: InkWell(
              onTap: () => _tap(it),
              onLongPress: () => _toggle(it),
              child: SizedBox(
                height: 64,
                child: Row(children: [
                  const SizedBox(width: 16),
                  sel
                      ? CircleAvatar(radius: 18, backgroundColor: l.accent, child: const Icon(Icons.check_rounded, color: Colors.white, size: 20))
                      : SizedBox(
                          width: 36,
                          height: 36,
                          child: it.preview && !it.dir
                              ? ClipRRect(borderRadius: BorderRadius.circular(8), child: DriveThumb(api: api, item: it, size: 96, fallbackSize: 36))
                              : KindBadge(it),
                        ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: l.text))),
                        if (it.fav) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.star_rounded, size: 15, color: l.muted)),
                      ]),
                      const SizedBox(height: 2),
                      Row(children: [
                        _offlineMark(l, it),
                        if (s.offline.pinned(it.path) || s.offline.busy.contains(it.path)) const SizedBox(width: 4),
                        Expanded(child: Text(_subtitle(it), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: l.muted))),
                      ]),
                    ]),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert_rounded, color: l.muted),
                    onPressed: () => showItemActions(context, s, it, trash: _section == DriveSection.trash, onChanged: () => _reload(quiet: true)),
                  ),
                  const SizedBox(width: 4),
                ]),
              ),
            ),
          );
        },
      );

  Widget _table(DriveLook l, List<DriveItem> list) {
    final trash = _section == DriveSection.trash;
    Widget head(String t, {int flex = 1}) => Expanded(flex: flex, child: Text(t, style: TextStyle(color: l.muted, fontWeight: FontWeight.w500, fontSize: 13.5)));
    return Column(children: [
      Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.line))),
        child: Row(children: [
          head(tr('Tên'), flex: 5),
          head(trash ? tr('Vị trí ban đầu') : tr('Chủ sở hữu'), flex: 2),
          head(trash ? tr('Ngày xoá') : tr('Sửa đổi lần cuối'), flex: 2),
          head(tr('Kích thước')),
          const SizedBox(width: 40),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final it = list[i];
            final sel = _sel.contains(it.path);
            return GestureDetector(
              onSecondaryTapDown: (d) {
                if (!sel) {
                  setState(() {
                    _sel
                      ..clear()
                      ..add(it.path);
                    _focus = it.path;
                  });
                }
                if (_sel.length > 1) {
                  _bulkMenu(d.globalPosition);
                } else {
                  showItemActions(context, s, it, at: d.globalPosition, trash: trash, onChanged: () => _reload(quiet: true));
                }
              },
              child: Material(
                color: sel ? l.sel : Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final k = HardwareKeyboard.instance;
                    if (k.isControlPressed || k.isMetaPressed) {
                      _toggle(it);
                    } else if (k.isShiftPressed && _focus != null) {
                      final a = list.indexWhere((x) => x.path == _focus), b = i;
                      if (a >= 0) setState(() => _sel.addAll([for (var k = a < b ? a : b; k <= (a < b ? b : a); k++) list[k].path]));
                    } else {
                      _tap(it, wide: true);
                    }
                  },
                  onDoubleTap: () => _open(it),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.line))),
                    child: Row(children: [
                      Expanded(
                        flex: 5,
                        child: Row(children: [
                          KindBadge(it, size: 28),
                          const SizedBox(width: 12),
                          Flexible(child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text))),
                          const SizedBox(width: 6),
                          _offlineMark(l, it, size: 16),
                          if (it.shared) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.people_outline_rounded, size: 16, color: l.muted)),
                          if (it.fav) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.star_rounded, size: 16, color: l.muted)),
                        ]),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          it is DriveTrashItem ? it.original : (it.owner.isEmpty || it.owner == s.me?.uid ? tr('tôi') : it.ownerName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: l.muted),
                        ),
                      ),
                      Expanded(flex: 2, child: Text(fmtDate(it is DriveTrashItem ? it.deleted : it.mtime), style: TextStyle(color: l.muted))),
                      Expanded(child: Text(it.dir ? '—' : fmtSize(it.size), style: TextStyle(color: l.muted))),
                      SizedBox(
                        width: 40,
                        child: Builder(
                          builder: (c) => IconButton(
                            icon: Icon(Icons.more_vert_rounded, color: l.muted, size: 20),
                            onPressed: () {
                              final box = c.findRenderObject() as RenderBox;
                              showItemActions(context, s, it, at: box.localToGlobal(box.size.bottomLeft(Offset.zero)), trash: trash, onChanged: () => _reload(quiet: true));
                            },
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Future<void> _bulkMenu(Offset at) async {
    final acts = actionsFor(s, _selected, trash: _section == DriveSection.trash);
    final a = await showMenu<ItemAction>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [for (final (id, icon, label) in acts) PopupMenuItem(value: id, height: 42, child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]))],
    );
    if (a != null) await _bulk(a);
  }

  Widget _gridView(DriveLook l, List<DriveItem> list, bool wide) {
    final folders = list.where((i) => i.dir).toList(), files = list.where((i) => !i.dir).toList();
    final cross = wide ? 220.0 : 180.0;
    Widget card(DriveItem it) {
      final sel = _sel.contains(it.path);
      return Material(
        color: sel ? l.sel : l.surface2,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _tap(it, wide: wide),
          onDoubleTap: wide ? () => _open(it) : null,
          onLongPress: () => _toggle(it),
          onSecondaryTapDown: (d) => showItemActions(context, s, it, at: d.globalPosition, trash: _section == DriveSection.trash, onChanged: () => _reload(quiet: true)),
          child: it.dir
              ? Row(children: [
                  const SizedBox(width: 12),
                  KindBadge(it, size: 26),
                  const SizedBox(width: 10),
                  Expanded(child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontWeight: FontWeight.w500))),
                  _offlineMark(l, it, size: 16),
                  IconButton(icon: Icon(Icons.more_vert_rounded, size: 20, color: l.muted), onPressed: () => showItemActions(context, s, it, onChanged: () => _reload(quiet: true))),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
                    child: Row(children: [
                      KindBadge(it, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontWeight: FontWeight.w500, fontSize: 13.5))),
                      IconButton(
                        icon: Icon(Icons.more_vert_rounded, size: 20, color: l.muted),
                        onPressed: () => showItemActions(context, s, it, trash: _section == DriveSection.trash, onChanged: () => _reload(quiet: true)),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(color: l.surface, borderRadius: BorderRadius.circular(8)),
                      child: Stack(fit: StackFit.expand, children: [
                        DriveThumb(api: api, item: it, size: 384, fallbackSize: 56),
                        if (s.offline.pinned(it.path)) Positioned(right: 6, bottom: 6, child: CircleAvatar(radius: 11, backgroundColor: l.surface, child: _offlineMark(l, it, size: 18))),
                      ]),
                    ),
                  ),
                ]),
        ),
      );
    }

    return CustomScrollView(slivers: [
      if (folders.isNotEmpty) ...[
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 8, 18, 8), child: Text(tr('Thư mục'), style: TextStyle(color: l.muted, fontWeight: FontWeight.w500)))),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: cross, mainAxisExtent: 52, crossAxisSpacing: 10, mainAxisSpacing: 10),
            delegate: SliverChildBuilderDelegate((_, i) => card(folders[i]), childCount: folders.length),
          ),
        ),
      ],
      if (files.isNotEmpty) ...[
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 8), child: Text(tr('Tệp'), style: TextStyle(color: l.muted, fontWeight: FontWeight.w500)))),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: cross, childAspectRatio: .95, crossAxisSpacing: 10, mainAxisSpacing: 10),
            delegate: SliverChildBuilderDelegate((_, i) => card(files[i]), childCount: files.length),
          ),
        ),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ trang Tải lên

class UploadsPage extends StatelessWidget {
  const UploadsPage({super.key, required this.session});
  final DriveSession session;

  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context);
    return ListenableBuilder(
      listenable: session.uploads,
      builder: (context, _) {
        final up = session.uploads;
        final pending = up.pending, done = up.finished;
        final mobile = Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS;
        Widget job(UploadJob j) {
          final it = DriveItem(path: joinPath(j.dir, j.name), name: j.name, dir: false);
          final (sub, color) = switch (j.state) {
            UploadState.running => ('${fmtSize(j.sent)} / ${fmtSize(j.size)}', l.muted),
            UploadState.queued => (tr('Đang chờ'), l.muted),
            UploadState.waiting => (j.error ?? tr('Chờ mạng'), l.warn),
            UploadState.paused => (tr('Tạm dừng'), l.muted),
            UploadState.failed => (j.error ?? tr('Lỗi'), l.danger),
            UploadState.done => (j.dir == '/' ? tr('Drive của tôi') : j.dir.substring(1), l.muted),
            UploadState.cancelled => (tr('Đã huỷ'), l.muted),
          };
          return ListTile(
            leading: KindBadge(it),
            title: Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (j.state == UploadState.done) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check_circle_rounded, size: 14, color: l.ok)),
                if (j.state == UploadState.waiting) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.error_outline_rounded, size: 14, color: l.warn)),
                Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12.5))),
              ]),
              if (j.active)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: j.progress, minHeight: 4, backgroundColor: l.line, color: j.state == UploadState.waiting ? l.warn : l.accent),
                  ),
                ),
            ]),
            trailing: switch (j.state) {
              UploadState.failed => IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => up.retry(j)),
              UploadState.done => const SizedBox.shrink(),
              UploadState.cancelled => const SizedBox.shrink(),
              _ => IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => up.cancel(j)),
            },
          );
        }

        return Scaffold(
          backgroundColor: l.bg,
          appBar: AppBar(
            backgroundColor: l.bg,
            title: Text(tr('Tải lên')),
            actions: [
              IconButton(
                tooltip: up.paused ? tr('Tiếp tục') : tr('Tạm dừng'),
                icon: Icon(up.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                onPressed: () => up.setPaused(!up.paused),
              ),
              if (done.isNotEmpty) IconButton(tooltip: tr('Xoá danh sách đã xong'), icon: const Icon(Icons.clear_all_rounded), onPressed: up.clearFinished),
            ],
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: l.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: l.line)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.wifi_rounded, color: l.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    Theme.of(context).platform == TargetPlatform.android
                        ? tr('Vẫn tải khi tắt màn hình hoặc thoát app. Mất mạng thì dừng, có mạng lại tự tải tiếp từ phần đang dở.')
                        : tr('Mất mạng thì dừng, có mạng lại tự tải tiếp từ phần đang dở. Nếu app bị đóng, lần mở sau sẽ tải nốt.'),
                    style: TextStyle(fontSize: 13.5, color: l.text),
                  ),
                ),
              ]),
            ),
            if (pending.isNotEmpty) ...[
              _sec(l, up.paused ? tr('Tạm dừng · {0} tệp', ['${pending.length}']) : tr('Đang tải · {0} tệp', ['${pending.length}'])),
              for (final j in pending) job(j),
            ],
            if (done.isNotEmpty) ...[
              _sec(l, tr('Đã xong')),
              for (final j in done.take(50)) job(j),
            ],
            if (pending.isEmpty && done.isEmpty)
              Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr('Không có tệp nào đang tải lên'), style: TextStyle(color: l.muted)))),
            if (mobile) ...[
              _sec(l, tr('Tự tải ảnh lên')),
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
                decoration: BoxDecoration(color: l.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: l.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.photo_camera_rounded, color: l.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('Sao lưu ảnh và video'), style: TextStyle(fontWeight: FontWeight.w600, color: l.text)),
                        Text(
                          up.camera.enabled
                              ? tr('Vào thư mục "{0}" · {1} tệp đã lên', [up.camera.folder.substring(1), '${up.camera.count}'])
                              : tr('Ảnh chụp mới sẽ tự tải vào "{0}"', [up.camera.folder.substring(1)]),
                          style: TextStyle(fontSize: 12.5, color: l.muted),
                        ),
                      ]),
                    ),
                    Switch(
                      value: up.camera.enabled,
                      onChanged: (v) async {
                        try {
                          await up.setCamera(enabled: v);
                        } catch (e) {
                          if (context.mounted) driveToast(context, '$e');
                        }
                      },
                    ),
                  ]),
                  if (up.camera.enabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(spacing: 8, children: [
                        FilterChip(label: Text(tr('Chỉ qua Wi-Fi')), selected: up.camera.wifiOnly, onSelected: (v) => up.setCamera(wifiOnly: v)),
                        FilterChip(label: Text(tr('Cả video')), selected: up.camera.video, onSelected: (v) => up.setCamera(video: v)),
                      ]),
                    ),
                ]),
              ),
            ],
            _sec(l, tr('Bộ nhớ ngoại tuyến')),
            ListenableBuilder(
              listenable: session.offline,
              builder: (_, _) => ListTile(
                leading: Icon(Icons.download_for_offline_outlined, color: l.muted),
                title: Text(tr('{0} mục đã ghim · {1}', ['${session.offline.roots.length}', fmtSize(session.offline.bytes)])),
                trailing: session.offline.entries.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () async {
                          if (await confirmDrive(context, tr('Xoá bản lưu trên máy?'), tr('Tệp trên Drive không bị ảnh hưởng.'), ok: tr('Xoá'))) await session.offline.clearAll();
                        },
                        child: Text(tr('Xoá bản lưu')),
                      ),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _sec(DriveLook l, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: .3, color: l.muted)),
      );
}
