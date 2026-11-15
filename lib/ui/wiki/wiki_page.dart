// Wiki: màn hình chính. Máy tính: cây thư mục bên trái (cấu trúc chung của công ty, "Nhân viên" chứa thư mục từng người),
// nội dung bên phải (trang, sửa, lịch sử, thư mục, tìm kiếm, thùng rác). Điện thoại: cây thư mục, bấm trang thì mở trang.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart' show isDesktop, serverKey;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../desk_tabs.dart' show DeskTabScope;
import '../open_file.dart' show openLocalFile;
import '../theme.dart';
import 'acl.dart';
import 'api.dart';
import 'editor.dart';
import 'md_view.dart';
import 'model.dart';
import 'store.dart';

const _folderColor = Color(0xFFE8A100);
const _red = Color(0xFFE5484D);

Future<void> openWiki(BuildContext context, MiniApp app, {String? pageId}) async {
  final state = context.read<AppState>();
  final nav = Navigator.of(context);
  final tab = DeskTabScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id = await FlygoId.current(state.token);
    if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
    final store = WikiStore(
      WikiApi(base: app.baseUrl, id: id),
      cacheKey: '${serverKey}_${state.me?.id ?? 'me'}'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_'),
    );
    await nav.push(
      AppPageRoute(
        builder: (_) => WikiHome(store: store, title: app.name, openPageId: pageId),
      ),
    );
    tab?.onTitle?.call(null);
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

/// Nơi đang xem ở khung bên phải (máy tính).
enum _View { page, edit, history, folder, search, trash, recent }

class WikiHome extends StatefulWidget {
  const WikiHome({super.key, required this.store, this.title = 'Wiki', this.openPageId, this.ownsStore = true, this.forceWide});
  final WikiStore store;
  final String title;
  final String? openPageId;
  final bool ownsStore;

  /// Kiểm thử: ép bố cục máy tính / điện thoại.
  final bool? forceWide;
  @override
  State<WikiHome> createState() => WikiHomeState();
}

class WikiHomeState extends State<WikiHome> {
  final Set<String> _open = {WikiStore.staff};
  bool _staffAll = false;
  _View _view = _View.folder;
  String _folder = WikiStore.root;
  String? _page;
  WPage? _editing;
  final _q = TextEditingController();
  final _qFocus = FocusNode();
  int _pageNonce = 0;

  WikiStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    store.load().then((_) {
      if (!mounted) return;
      final p = widget.openPageId;
      if (p != null) {
        _openPage(p);
      } else if (store.home != null && _page == null && _view == _View.folder && _folder == WikiStore.root) {
        setState(() => _open.add(store.home!));
      }
    });
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    if (widget.ownsStore) store.dispose();
    _q.dispose();
    _qFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _wide => widget.forceWide ?? MediaQuery.of(context).size.width >= 900;

  void _reveal(String folder) {
    for (final f in store.pathOf(folder)) {
      _open.add(f.id);
    }
  }

  void _openPage(String id) {
    final ref = store.pages[id];
    if (ref != null) _reveal(ref.folder);
    if (_wide) {
      setState(() {
        _page = id;
        _view = _View.page;
        _pageNonce++;
      });
    } else {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => _PageScreen(home: this, pageId: id),
        ),
      );
    }
  }

  void _openFolder(String id) {
    _reveal(id);
    if (_wide) {
      setState(() {
        _folder = id;
        _view = _View.folder;
        _open.add(id);
      });
    } else {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => _FolderScreen(home: this, folder: id),
        ),
      );
    }
  }

  void _toggle(String id) => setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));

  /// Thư mục để tạo trang mới: thư mục đang xem nếu được sửa, không thì thư mục của mình.
  String get _contextFolder {
    final f = _view == _View.page && _page != null ? store.pages[_page!]?.folder ?? _folder : _folder;
    return store.canIn(f, 'edit') ? f : (store.home ?? WikiStore.root);
  }

  // ------------------------------------------------------------ thao tác
  void _err(Object e) => ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
  void _ok(String s) => ScaffoldMessenger.of(context).showSnackBar(toast(Text(s)));

  Future<String?> _ask(String title, {String initial = '', String action = 'Lưu'}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(key: const ValueKey('wiki-ask'), controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr(action))),
        ],
      ),
    );
  }

  Future<void> newPage([String? folder]) async {
    final f = folder ?? _contextFolder;
    final title = (await _ask(tr('Trang mới trong “{0}”', [store.folderName(f)]), action: 'Tạo'))?.trim();
    if (title == null || title.isEmpty) return;
    try {
      final id = await store.createPage(f, title);
      _reveal(f);
      _open.add(f);
      final p = await store.page(id);
      if (!mounted) return;
      _edit(p);
    } catch (e) {
      _err(e);
    }
  }

  Future<void> newFolder(String parent) async {
    final name = (await _ask(tr('Thư mục con trong “{0}”', [store.folderName(parent)]), action: 'Tạo'))?.trim();
    if (name == null || name.isEmpty) return;
    try {
      final id = await store.createFolder(parent, name);
      setState(() => _open.addAll([parent, id]));
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _renameFolder(WFolder f) async {
    final name = (await _ask(tr('Đổi tên thư mục'), initial: f.name))?.trim();
    if (name == null || name.isEmpty || name == f.name) return;
    try {
      await store.renameFolder(f.id, name);
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _moveFolder(WFolder f) async {
    final to = await _pickFolder(tr('Chuyển “{0}” tới', [f.name]), need: 'manage', exclude: f.id);
    if (to == null) return;
    try {
      await store.moveFolder(f.id, to);
      _ok(tr('Đã chuyển thư mục'));
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _deleteFolder(WFolder f) async {
    if (!await _confirm(tr('Xoá thư mục “{0}”?', [f.name]), tr('Thư mục và mọi trang bên trong vào thùng rác, khôi phục được trong {0} ngày.', ['30']))) return;
    try {
      await store.deleteFolder(f.id);
      if (_folder == f.id || (_page != null && !store.pages.containsKey(_page))) setState(() => _view = _View.folder);
      if (_folder == f.id) _folder = f.parent ?? WikiStore.root;
      _ok(tr('Đã chuyển thư mục vào thùng rác'));
    } catch (e) {
      _err(e);
    }
  }

  Future<void> renamePage(WPage p) async {
    final t = (await _ask(tr('Đổi tên trang'), initial: p.title))?.trim();
    if (t == null || t.isEmpty || t == p.title) return;
    try {
      await store.savePage(p.id, title: t, note: tr('Đổi tên trang'));
      setState(() => _pageNonce++);
    } catch (e) {
      _err(e);
    }
  }

  Future<void> movePage(WPage p) async {
    final to = await _pickFolder(tr('Chuyển “{0}” tới', [p.title]), need: 'edit');
    if (to == null || to == p.folder) return;
    try {
      await store.movePage(p.id, to);
      _reveal(to);
      setState(() => _pageNonce++);
      _ok(tr('Đã chuyển trang'));
    } catch (e) {
      _err(e);
    }
  }

  Future<bool> deletePage(WPage p) async {
    if (!await _confirm(tr('Xoá trang “{0}”?', [p.title]), tr('Trang vào thùng rác, khôi phục được trong {0} ngày.', ['30']))) return false;
    try {
      await store.deletePage(p.id);
      if (_page == p.id) {
        setState(() {
          _page = null;
          _folder = p.folder;
          _view = _View.folder;
        });
      }
      _ok(tr('Đã chuyển trang vào thùng rác'));
      return true;
    } catch (e) {
      _err(e);
      return false;
    }
  }

  void copyLink(String pageId) {
    Clipboard.setData(ClipboardData(text: '${store.api.base.replaceAll(RegExp(r'/+$'), '')}/p/$pageId'));
    _ok(tr('Đã sao chép link'));
  }

  Future<void> _syncStaff() async {
    try {
      final r = await store.syncStaff();
      _ok(tr('Đã đồng bộ {0} nhân viên ({1} thư mục mới, {2} người đã nghỉ)', ['${r['people']}', '${r['created']}', '${r['left']}']));
    } catch (e) {
      _err(e);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Huỷ'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _red),
              onPressed: () => Navigator.pop(d, true),
              child: Text(tr('Xoá')),
            ),
          ],
        ),
      ) ==
      true;

  /// Chọn thư mục đích (chỉ thư mục mình có quyền [need]).
  Future<String?> _pickFolder(String title, {required String need, String? exclude}) {
    final rows = <(WFolder?, int)>[];
    void walk(String id, int depth) {
      for (final f in store.children(id)) {
        if (f.id == exclude) continue;
        rows.add((f, depth));
        walk(f.id, depth + 1);
      }
    }

    rows.add((null, 0));
    walk(WikiStore.root, 1);
    return showDialog<String>(
      context: context,
      builder: (d) {
        final pal = Pal.of(d);
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            height: 460,
            child: ListView(
              children: [
                for (final (f, depth) in rows)
                  Builder(
                    builder: (_) {
                      final id = f?.id ?? WikiStore.root;
                      final ok = store.canIn(id, need) && id != WikiStore.staff;
                      return ListTile(
                        dense: true,
                        enabled: ok,
                        contentPadding: EdgeInsets.only(left: 8.0 + depth * 18, right: 8),
                        leading: Icon(f == null ? Icons.home_outlined : Icons.folder_rounded, color: ok ? (f == null ? pal.sub : _folderColor) : pal.divider),
                        title: Text(f?.name ?? store.rootName),
                        onTap: ok ? () => Navigator.pop(d, id) : null,
                      );
                    },
                  ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Huỷ')))],
        );
      },
    );
  }

  Future<void> openFile(WFile f) async {
    try {
      if (f.isImage) {
        final data = await store.api.bytes(f.id);
        if (!mounted) return;
        await Navigator.of(context).push(
          AppPageRoute(
            builder: (_) => _ImageScreen(name: f.name, data: data),
          ),
        );
        return;
      }
      final p = await store.api.download(f.id, f.name);
      if (isDesktop) {
        await launchUrl(Uri.file(p));
      } else {
        await openLocalFile(p, mime: f.mime, title: f.name);
      }
    } catch (e) {
      _err(e);
    }
  }

  void _edit(WPage p) {
    if (_wide) {
      setState(() {
        _editing = p;
        _page = p.id;
        _view = _View.edit;
      });
    } else {
      Navigator.of(context)
          .push(
            AppPageRoute(
              builder: (_) => WikiEditor(store: store, page: p),
            ),
          )
          .then((saved) {
            if (saved != null && mounted) setState(() => _pageNonce++);
          });
    }
  }

  void openHistory(String pageId) {
    if (_wide) {
      setState(() {
        _page = pageId;
        _view = _View.history;
      });
    } else {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => _HistoryScreen(home: this, pageId: pageId),
        ),
      );
    }
  }

  void _close() => Navigator.of(context).maybePop();

  /// Trang đang xem vừa đổi ở nơi khác (khôi phục phiên bản): tải lại.
  void refreshPage() => setState(() => _pageNonce++);

  // ------------------------------------------------------------ menu thư mục / trang
  List<PopupMenuEntry<String>> _folderItems(WFolder? f) {
    final id = f?.id ?? WikiStore.root;
    final parentManage = f?.parent != null && store.canIn(f!.parent!, 'manage');
    PopupMenuItem<String> it(String v, IconData i, String t, {bool red = false}) => PopupMenuItem(
      value: v,
      child: Row(
        children: [
          Icon(i, size: 20, color: red ? _red : null),
          const SizedBox(width: 12),
          Text(t, style: red ? const TextStyle(color: _red) : null),
        ],
      ),
    );
    return [
      if (store.canIn(id, 'edit')) it('page', Icons.note_add_outlined, tr('Trang mới')),
      if (store.canIn(id, 'manage') && id != WikiStore.staff) it('folder', Icons.create_new_folder_outlined, tr('Thư mục con')),
      if (f != null && !f.fixed && store.canIn(id, 'manage')) it('rename', Icons.drive_file_rename_outline, tr('Đổi tên')),
      if (f != null && !f.fixed && parentManage) it('move', Icons.drive_file_move_outlined, tr('Chuyển tới…')),
      if (f == null || f.role != null) it('acl', Icons.lock_person_outlined, store.canIn(id, 'manage') ? tr('Phân quyền…') : tr('Xem quyền')),
      if (id == WikiStore.staff && store.admin) it('sync', Icons.sync_rounded, tr('Đồng bộ nhân viên')),
      if (f != null && !f.fixed && parentManage) ...[const PopupMenuDivider(), it('delete', Icons.delete_outline_rounded, tr('Xoá thư mục'), red: true)],
    ];
  }

  void _folderAction(WFolder? f, String? v) {
    final id = f?.id ?? WikiStore.root;
    switch (v) {
      case 'page':
        newPage(id);
      case 'folder':
        newFolder(id);
      case 'rename':
        _renameFolder(f!);
      case 'move':
        _moveFolder(f!);
      case 'acl':
        showFolderAcl(context, store, id, wide: _wide);
      case 'sync':
        _syncStaff();
      case 'delete':
        _deleteFolder(f!);
    }
  }

  Future<void> folderMenu(WFolder? f, {Offset? at}) async {
    final items = _folderItems(f);
    if (items.isEmpty) return;
    if (!_wide) {
      final v = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(f?.name ?? store.rootName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              for (final it in items)
                if (it is PopupMenuItem<String>)
                  ListTile(leading: (it.child as Row).children.first, title: (it.child as Row).children.last, onTap: () => Navigator.pop(c, it.value))
                else
                  const Divider(height: 8),
            ],
          ),
        ),
      );
      _folderAction(f, v);
      return;
    }
    final box = context.findRenderObject() as RenderBox;
    final p = at ?? box.size.center(Offset.zero);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(p.dx, p.dy, box.size.width - p.dx, box.size.height - p.dy),
      items: items,
    );
    _folderAction(f, v);
  }

  // ------------------------------------------------------------ cây thư mục
  List<Widget> _treeRows({required bool phone}) {
    final pal = Pal.of(context);
    final rows = <Widget>[];
    final h = phone ? 46.0 : 34.0, fs = phone ? 16.0 : 14.5;

    Widget row({
      required Key key,
      required int depth,
      required Widget icon,
      required String label,
      bool selected = false,
      bool? expanded,
      VoidCallback? onTap,
      VoidCallback? onChevron,
      Widget? trailing,
      void Function(Offset)? onMenu,
      Color? color,
    }) {
      return Padding(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected ? pal.chipSelBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            onLongPress: onMenu == null ? null : () => onMenu(Offset.zero),
            onSecondaryTapDown: onMenu == null ? null : (d) => onMenu(d.globalPosition),
            child: SizedBox(
              height: h,
              child: Row(
                children: [
                  SizedBox(width: depth * (phone ? 22.0 : 20.0)),
                  SizedBox(
                    width: 22,
                    child: expanded == null
                        ? null
                        : InkWell(
                            onTap: onChevron,
                            child: Icon(expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 19, color: pal.sub),
                          ),
                  ),
                  const SizedBox(width: 4),
                  icon,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fs,
                        color: color ?? (selected ? pal.chipSelFg : pal.text),
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  ?trailing,
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      );
    }

    void pageRow(WPageRef p, int depth) {
      final sel = _wide && _page == p.id && (_view == _View.page || _view == _View.edit || _view == _View.history);
      rows.add(
        row(
          key: ValueKey('wiki-page-${p.id}'),
          depth: depth,
          expanded: null,
          icon: Icon(sel ? Icons.description : Icons.description_outlined, size: 19, color: sel ? pal.chipSelFg : pal.sub),
          label: p.title,
          selected: sel,
          onTap: () => _openPage(p.id),
        ),
      );
    }

    void folder(WFolder f, int depth) {
      final open = _open.contains(f.id);
      final mine = f.id == store.home;
      final staffRoot = f.kind == 'staff_root', staffHome = f.kind == 'staff_home';
      final sel = _wide && _view == _View.folder && _folder == f.id;
      final iconData = staffRoot
          ? Icons.groups_rounded
          : staffHome
          ? (mine ? Icons.account_circle : Icons.account_circle_outlined)
          : (open ? Icons.folder_open_rounded : Icons.folder_rounded);
      final iconColor = staffRoot || mine
          ? pal.accent
          : staffHome
          ? pal.sub
          : _folderColor;
      rows.add(
        row(
          key: ValueKey('wiki-folder-${f.id}'),
          depth: depth,
          icon: Icon(iconData, size: 20, color: f.role == null ? pal.divider : (sel ? pal.chipSelFg : iconColor)),
          label: f.name,
          selected: sel,
          expanded: open,
          color: f.role == null ? pal.sub : null,
          onChevron: () => _toggle(f.id),
          onTap: f.role == null ? () => _toggle(f.id) : (phone ? () => _toggle(f.id) : () => _openFolder(f.id)),
          onMenu: f.role == null ? null : (at) => folderMenu(f, at: at == Offset.zero ? null : at),
          trailing: mine
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: pal.chipSelBg, borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    tr('Của tôi'),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: pal.accentText),
                  ),
                )
              : f.left
              ? Text(tr('Đã nghỉ'), style: TextStyle(fontSize: 11.5, color: pal.sub))
              : f.closed
              ? Icon(Icons.lock_outline_rounded, size: 16, color: pal.sub)
              : staffRoot && phone
              ? Text('${store.staffCount}', style: TextStyle(fontSize: 13, color: pal.sub))
              : null,
        ),
      );
      if (!open) return;
      final kids = store.children(f.id);
      final limit = staffRoot && !_staffAll ? 8 : kids.length;
      for (final k in kids.take(limit)) {
        folder(k, depth + 1);
      }
      if (kids.length > limit) {
        rows.add(
          row(
            key: const ValueKey('wiki-staff-more'),
            depth: depth + 1,
            icon: Icon(Icons.more_horiz_rounded, size: 20, color: pal.sub),
            label: tr('{0} người nữa', ['${kids.length - limit}']),
            color: pal.sub,
            onTap: () => setState(() => _staffAll = true),
          ),
        );
      }
      for (final p in store.pagesIn(f.id)) {
        pageRow(p, depth + 1);
      }
    }

    for (final f in store.children(WikiStore.root)) {
      folder(f, 0);
    }
    for (final p in store.pagesIn(WikiStore.root)) {
      pageRow(p, 0);
    }
    return rows;
  }

  Widget _sidebar() {
    final pal = Pal.of(context);
    return Container(
      width: 300,
      color: pal.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 60,
            child: Row(
              children: [
                const SizedBox(width: 18),
                Icon(Icons.menu_book_rounded, color: pal.accent, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.text),
                  ),
                ),
                if (store.canIn(WikiStore.root, 'manage'))
                  IconButton(
                    tooltip: tr('Thư mục mới'),
                    icon: Icon(Icons.create_new_folder_outlined, color: pal.sub),
                    onPressed: () =>
                        newFolder(_view == _View.folder && store.canIn(_folder, 'manage') && _folder != WikiStore.staff ? _folder : WikiStore.root),
                  ),
                IconButton.filled(
                  key: const ValueKey('wiki-new-page'),
                  tooltip: tr('Trang mới'),
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => newPage(),
                ),
                if (Navigator.of(context).canPop())
                  IconButton(
                    tooltip: tr('Đóng'),
                    icon: Icon(Icons.close_rounded, color: pal.sub),
                    onPressed: _close,
                  ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: TextField(
              key: const ValueKey('wiki-search'),
              controller: _q,
              focusNode: _qFocus,
              onSubmitted: (_) => setState(() => _view = _View.search),
              onChanged: (v) => setState(() => _view = v.trim().isEmpty ? (_page != null ? _View.page : _View.folder) : _View.search),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.bg,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: tr('Tìm trong wiki'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: pal.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: pal.divider),
                ),
              ),
            ),
          ),
          if (store.offline) _offline(pal),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                InkWell(
                  onTap: () => _openFolder(WikiStore.root),
                  onSecondaryTapDown: (d) => folderMenu(null, at: d.globalPosition),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                    child: Text(
                      store.rootName.toUpperCase(),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: pal.sub),
                    ),
                  ),
                ),
                ..._treeRows(phone: false),
              ],
            ),
          ),
          Divider(height: 1, color: pal.divider),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _view = _View.trash),
                    icon: Icon(Icons.delete_outline_rounded, color: pal.sub, size: 20),
                    label: Text(
                      tr('Thùng rác'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.sub),
                    ),
                  ),
                ),
              ),
              if (store.admin)
                IconButton(
                  tooltip: tr('Đồng bộ nhân viên'),
                  icon: Icon(Icons.sync_rounded, color: pal.sub, size: 20),
                  onPressed: _syncStaff,
                ),
              const SizedBox(width: 6),
            ],
          ),
        ],
      ),
    );
  }

  Widget _offline(Pal pal) => Container(
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(8)),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 16, color: pal.sub),
        const SizedBox(width: 8),
        Expanded(
          child: Text(tr('Mất mạng: đang xem bản lưu trên máy'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
        ),
      ],
    ),
  );

  Widget _content() {
    switch (_view) {
      case _View.page:
        return WikiPageView(key: ValueKey('page-$_page-$_pageNonce'), home: this, pageId: _page!, wide: true);
      case _View.edit:
        return WikiEditor(
          key: ValueKey('edit-${_editing!.id}'),
          store: store,
          page: _editing!,
          wide: true,
          onDone: (saved) => setState(() {
            _view = _View.page;
            _pageNonce++;
          }),
        );
      case _View.history:
        return WikiHistory(key: ValueKey('hist-$_page'), home: this, pageId: _page!, wide: true, onClose: () => setState(() => _view = _View.page));
      case _View.search:
        return WikiSearch(home: this, query: _q.text, wide: true);
      case _View.trash:
        return WikiTrash(home: this);
      case _View.recent:
        return WikiRecent(home: this);
      case _View.folder:
        return WikiFolderView(key: ValueKey('folder-$_folder'), home: this, folder: _folder, wide: true);
    }
  }

  // ------------------------------------------------------------ điện thoại
  Widget _phone() {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: Navigator.of(context).canPop() ? 0 : 20,
        title: Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: tr('Tìm kiếm'),
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(AppPageRoute(builder: (_) => _SearchScreen(home: this))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'trash') {
                Navigator.of(context).push(AppPageRoute(builder: (_) => _SimpleScreen(title: tr('Thùng rác'), child: WikiTrash(home: this))));
              }
              if (v == 'sync') _syncStaff();
              if (v == 'root') folderMenu(null);
              if (v == 'close') _close();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'trash', child: Text(tr('Thùng rác'))),
              if (store.admin) PopupMenuItem(value: 'sync', child: Text(tr('Đồng bộ nhân viên'))),
              if (store.canIn(WikiStore.root, 'manage')) PopupMenuItem(value: 'root', child: Text(tr('Quản lý “{0}”…', [store.rootName]))),
              if (Navigator.of(context).canPop()) PopupMenuItem(value: 'close', child: Text(tr('Quay về app Flygo Chat'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('wiki-new-page'),
        tooltip: tr('Trang mới'),
        backgroundColor: pal.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: () => newPage(),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (store.offline) _offline(pal),
            if (store.home != null)
              ListTile(
                leading: Icon(Icons.account_circle, color: pal.accent),
                title: Text(tr('Wiki của tôi'), style: const TextStyle(fontSize: 16)),
                trailing: Icon(Icons.chevron_right_rounded, color: pal.sub),
                onTap: () => _openFolder(store.home!),
              ),
            ListTile(
              leading: Icon(Icons.schedule_rounded, color: pal.sub),
              title: Text(tr('Mới sửa gần đây'), style: const TextStyle(fontSize: 16)),
              trailing: Icon(Icons.chevron_right_rounded, color: pal.sub),
              onTap: () => Navigator.of(context).push(
                AppPageRoute(
                  builder: (_) => _SimpleScreen(
                    title: tr('Mới sửa gần đây'),
                    child: WikiRecent(home: this),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                store.rootName.toUpperCase(),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: pal.sub),
              ),
            ),
            if (!store.loaded && store.error == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!store.loaded && store.error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(store.error!, style: TextStyle(color: pal.sub)),
              ),
            ..._treeRows(phone: true),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_wide) return _phone();
    final pal = Pal.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _qFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => _qFocus.requestFocus(),
      },
      child: Scaffold(
        backgroundColor: pal.bg,
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sidebar(),
              VerticalDivider(width: 1, color: pal.divider),
              Expanded(child: _content()),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ thanh trên của khung nội dung (máy tính)
class _Bar extends StatelessWidget {
  const _Bar({required this.crumbs, this.actions = const [], this.onCrumb});
  final List<(String?, String)> crumbs;
  final List<Widget> actions;
  final void Function(String id)? onCrumb;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.fromLTRB(28, 0, 16, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: pal.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.home_outlined, size: 18, color: pal.sub),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < crumbs.length; i++) ...[
                    if (i > 0) Icon(Icons.chevron_right_rounded, size: 18, color: pal.sub),
                    InkWell(
                      onTap: crumbs[i].$1 == null || i == crumbs.length - 1 ? null : () => onCrumb?.call(crumbs[i].$1!),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                        child: Text(
                          crumbs[i].$2,
                          style: TextStyle(
                            fontSize: 14,
                            color: i == crumbs.length - 1 ? pal.text : pal.sub,
                            fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

// ============================================================ xem trang
class WikiPageView extends StatefulWidget {
  const WikiPageView({super.key, required this.home, required this.pageId, required this.wide});
  final WikiHomeState home;
  final String pageId;
  final bool wide;
  @override
  State<WikiPageView> createState() => _WikiPageViewState();
}

class _WikiPageViewState extends State<WikiPageView> {
  WPage? _p;
  Object? _error;

  WikiStore get store => widget.home.store;

  @override
  void initState() {
    super.initState();
    _p = store.cached(widget.pageId);
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await store.page(widget.pageId);
      if (mounted) setState(() => _p = p);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = _p;
    final home = widget.home;
    if (p == null) {
      return Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$_error', style: TextStyle(color: pal.sub)),
              )
            : const CircularProgressIndicator(),
      );
    }
    final meta = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: const Color(0xFF7C5CFF),
          child: Text(
            p.updatedByName.trim().isEmpty ? '?' : p.updatedByName.trim().split(' ').last.characters.first,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          tr('{0} sửa {1} · bản {2}', [
            p.viaAgent ? tr('Agent của {0}', [p.updatedByName]) : p.updatedByName,
            agoLabel(p.updatedAt),
            '${p.version}',
          ]),
          style: TextStyle(fontSize: 13.5, color: pal.sub),
        ),
        if (widget.wide && p.accessSummary.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(6)),
            child: Text(
              p.accessSummary,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: pal.sub),
            ),
          ),
      ],
    );
    final body = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(widget.wide ? 40 : 20, widget.wide ? 34 : 8, widget.wide ? 40 : 20, 60),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.wide) Text(['Công ty', ...p.path.map((x) => x.name)].skip(1).join(' › '), style: TextStyle(fontSize: 12.5, color: pal.sub)),
              if (!widget.wide) const SizedBox(height: 6),
              Text(
                p.title,
                style: TextStyle(fontSize: widget.wide ? 32 : 26, fontWeight: FontWeight.w700, height: 1.25, color: pal.text),
              ),
              const SizedBox(height: 10),
              meta,
              SizedBox(height: widget.wide ? 26 : 16),
              if (p.body.trim().isEmpty)
                Text(p.can('edit') ? tr('Trang chưa có nội dung. Bấm Sửa để viết.') : tr('Trang chưa có nội dung.'), style: TextStyle(color: pal.sub))
              else
                WikiMarkdown(
                  text: p.body,
                  api: store.api,
                  files: p.files,
                  fontSize: widget.wide ? 15.5 : 15.5,
                  onWikiLink: home._openPage,
                  onFile: home.openFile,
                ),
            ],
          ),
        ),
      ),
    );
    if (!widget.wide) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bar(
          crumbs: [for (final x in p.path) (x.id, x.name), (null, p.title)].cast<(String?, String)>(),
          onCrumb: home._openFolder,
          actions: [
            TextButton.icon(onPressed: () => home.openHistory(p.id), icon: const Icon(Icons.history_rounded, size: 20), label: Text(tr('Lịch sử'))),
            TextButton.icon(onPressed: () => home.copyLink(p.id), icon: const Icon(Icons.link_rounded, size: 20), label: Text(tr('Sao chép link'))),
            if (p.can('edit')) ...[
              const SizedBox(width: 6),
              FilledButton.icon(
                key: const ValueKey('wiki-edit'),
                onPressed: () => home._edit(p),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: Text(tr('Sửa')),
              ),
              _pageMenu(p),
            ],
          ],
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _pageMenu(WPage p) => PopupMenuButton<String>(
    tooltip: tr('Thêm'),
    onSelected: (v) {
      if (v == 'rename') widget.home.renamePage(p);
      if (v == 'move') widget.home.movePage(p);
      if (v == 'delete') widget.home.deletePage(p);
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'rename', child: Text(tr('Đổi tên'))),
      PopupMenuItem(value: 'move', child: Text(tr('Chuyển tới…'))),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'delete',
        child: Text(tr('Xoá trang'), style: const TextStyle(color: _red)),
      ),
    ],
  );
}

class _PageScreen extends StatefulWidget {
  const _PageScreen({required this.home, required this.pageId});
  final WikiHomeState home;
  final String pageId;
  @override
  State<_PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends State<_PageScreen> {
  int _nonce = 0;
  @override
  Widget build(BuildContext context) {
    final home = widget.home, store = home.store;
    final ref = store.pages[widget.pageId];
    final pal = Pal.of(context);
    final canEdit = ref != null && store.canIn(ref.folder, 'edit');
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(ref?.title ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          if (canEdit)
            IconButton(
              key: const ValueKey('wiki-edit'),
              tooltip: tr('Sửa'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final p = await store.page(widget.pageId);
                if (!context.mounted) return;
                final saved = await Navigator.of(context).push(
                  AppPageRoute(
                    builder: (_) => WikiEditor(store: store, page: p),
                  ),
                );
                if (saved != null) setState(() => _nonce++);
              },
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final p = store.cached(widget.pageId);
              if (v == 'history') home.openHistory(widget.pageId);
              if (v == 'link') home.copyLink(widget.pageId);
              if (p == null) return;
              if (v == 'rename') await home.renamePage(p);
              if (v == 'move') await home.movePage(p);
              if (v == 'delete' && await home.deletePage(p) && context.mounted) Navigator.of(context).pop();
              setState(() => _nonce++);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'history', child: Text(tr('Lịch sử'))),
              PopupMenuItem(value: 'link', child: Text(tr('Sao chép link'))),
              if (canEdit) ...[
                PopupMenuItem(value: 'rename', child: Text(tr('Đổi tên'))),
                PopupMenuItem(value: 'move', child: Text(tr('Chuyển tới…'))),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(tr('Xoá trang'), style: const TextStyle(color: _red)),
                ),
              ],
            ],
          ),
        ],
      ),
      body: WikiPageView(key: ValueKey('p-${widget.pageId}-$_nonce'), home: home, pageId: widget.pageId, wide: false),
    );
  }
}

// ============================================================ thư mục
class WikiFolderView extends StatelessWidget {
  const WikiFolderView({super.key, required this.home, required this.folder, required this.wide});
  final WikiHomeState home;
  final String folder;
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final store = home.store;
    final f = store.folders[folder];
    final name = store.folderName(folder);
    final kids = store.children(folder), pages = store.pagesIn(folder);
    final role = folder == WikiStore.root ? store.rootRole : f?.role;
    final list = ListView(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 12, wide ? 30 : 4, wide ? 40 : 12, 80),
      children: [
        if (wide) ...[
          Row(
            children: [
              Icon(
                f?.kind == 'staff_home'
                    ? Icons.account_circle
                    : f?.kind == 'staff_root'
                    ? Icons.groups_rounded
                    : Icons.folder_rounded,
                size: 34,
                color: f?.kind == null || f!.kind == 'normal' || f.kind == 'root' ? _folderColor : pal.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: pal.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              tr('Quyền của bạn: {0}', [roleLabel(role)]),
              if (f?.closed ?? false) tr('thư mục kín'),
              if (f?.left ?? false) tr('nhân viên đã nghỉ (chỉ đọc)'),
            ].join(' · '),
            style: TextStyle(color: pal.sub, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (store.canIn(folder, 'edit'))
                FilledButton.icon(onPressed: () => home.newPage(folder), icon: const Icon(Icons.note_add_outlined, size: 18), label: Text(tr('Trang mới'))),
              if (store.canIn(folder, 'manage') && folder != WikiStore.staff)
                OutlinedButton.icon(
                  onPressed: () => home.newFolder(folder),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: Text(tr('Thư mục con')),
                ),
              if (role != null)
                OutlinedButton.icon(
                  onPressed: () => showFolderAcl(context, store, folder, wide: true),
                  icon: const Icon(Icons.lock_person_outlined, size: 18),
                  label: Text(store.canIn(folder, 'manage') ? tr('Phân quyền') : tr('Xem quyền')),
                ),
              if (f != null && home._folderItems(f).length > 3)
                IconButton(tooltip: tr('Thêm'), icon: const Icon(Icons.more_horiz_rounded), onPressed: () => home.folderMenu(f)),
            ],
          ),
          const SizedBox(height: 22),
        ],
        if (kids.isEmpty && pages.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(tr('Thư mục trống.'), style: TextStyle(color: pal.sub)),
          ),
        for (final k in kids)
          ListTile(
            key: ValueKey('wiki-fv-folder-${k.id}'),
            leading: Icon(
              k.kind == 'staff_home' ? (k.id == store.home ? Icons.account_circle : Icons.account_circle_outlined) : Icons.folder_rounded,
              color: k.kind == 'staff_home' ? (k.id == store.home ? pal.accent : pal.sub) : _folderColor,
            ),
            title: Text(k.name),
            trailing: k.closed ? Icon(Icons.lock_outline_rounded, size: 18, color: pal.sub) : null,
            onTap: k.role == null ? null : () => home._openFolder(k.id),
            onLongPress: k.role == null ? null : () => home.folderMenu(k),
          ),
        for (final p in pages)
          ListTile(
            key: ValueKey('wiki-fv-page-${p.id}'),
            leading: Icon(Icons.description_outlined, color: pal.sub),
            title: Text(p.title),
            subtitle: Text(tr('{0} · {1}', [p.updatedByName, agoLabel(p.updatedAt)]), style: TextStyle(color: pal.sub, fontSize: 12.5)),
            onTap: () => home._openPage(p.id),
          ),
      ],
    );
    if (!wide) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bar(
          crumbs: [(WikiStore.root, store.rootName), for (final x in store.pathOf(folder)) (x.id, x.name)].cast<(String?, String)>(),
          onCrumb: home._openFolder,
        ),
        Expanded(child: list),
      ],
    );
  }
}

class _FolderScreen extends StatelessWidget {
  const _FolderScreen({required this.home, required this.folder});
  final WikiHomeState home;
  final String folder;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ListenableBuilder(
      listenable: home.store,
      builder: (c, _) => Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bg,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(home.store.folderName(folder), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: tr('Thêm'),
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => home.folderMenu(folder == WikiStore.root ? null : home.store.folders[folder]),
            ),
          ],
        ),
        floatingActionButton: home.store.canIn(folder, 'edit')
            ? FloatingActionButton(
                backgroundColor: pal.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                onPressed: () => home.newPage(folder),
                child: const Icon(Icons.add_rounded, size: 30),
              )
            : null,
        body: WikiFolderView(home: home, folder: folder, wide: false),
      ),
    );
  }
}

// ============================================================ lịch sử
class WikiHistory extends StatefulWidget {
  const WikiHistory({super.key, required this.home, required this.pageId, required this.wide, this.onClose});
  final WikiHomeState home;
  final String pageId;
  final bool wide;
  final VoidCallback? onClose;
  @override
  State<WikiHistory> createState() => _WikiHistoryState();
}

class _WikiHistoryState extends State<WikiHistory> {
  List<WVersion>? _versions;
  WPage? _current, _shown;
  int? _sel;
  bool _diff = true;
  Object? _error;

  WikiStore get store => widget.home.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await store.history(widget.pageId);
      final cur = await store.page(widget.pageId);
      if (!mounted) return;
      setState(() {
        _versions = v;
        _current = cur;
      });
      if (v.length > 1) await _pick(v[1].version);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pick(int version) async {
    setState(() => _sel = version);
    try {
      final p = version == _current?.version ? _current! : await store.page(widget.pageId, version: version);
      if (mounted && _sel == version) setState(() => _shown = p);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _restore() async {
    final v = _sel;
    if (v == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.restoreVersion(widget.pageId, v);
      messenger.showSnackBar(toast(Text(tr('Đã khôi phục bản {0}', ['$v']))));
      if (!mounted) return;
      widget.home.refreshPage();
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không khôi phục được: {0}', ['$e']))));
    }
  }

  Widget _list(Pal pal) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Text(
          tr('Các phiên bản'),
          style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
        ),
      ),
      for (final v in _versions!)
        Material(
          color: v.version == _sel ? pal.chipSelBg : Colors.transparent,
          child: InkWell(
            key: ValueKey('wiki-version-${v.version}'),
            onTap: () => _pick(v.version),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: pal.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.version == _current?.version
                        ? tr('Bản {0} · hiện tại', ['${v.version}'])
                        : v.version == 1
                        ? tr('Bản 1 · tạo trang')
                        : tr('Bản {0}', ['${v.version}']),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: pal.text),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (v.viaAgent) ...[Icon(Icons.smart_toy_outlined, size: 15, color: pal.sub), const SizedBox(width: 4)],
                      Expanded(
                        child: Text(
                          '${v.viaAgent ? tr('Agent của {0}', [v.authorName]) : v.authorName} · ${whenLabel(v.at)}',
                          style: TextStyle(fontSize: 12.5, color: pal.sub),
                        ),
                      ),
                    ],
                  ),
                  if (v.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(v.note, style: TextStyle(fontSize: 12.5, color: pal.text)),
                    ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _detail(Pal pal) {
    final s = _shown, cur = _current;
    if (s == null || cur == null) return const Center(child: CircularProgressIndicator());
    final isCur = s.version == cur.version;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(widget.wide ? 40 : 20, 22, widget.wide ? 40 : 20, 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isCur ? tr('Bản {0} (hiện tại)', ['${s.version}']) : tr('Bản {0} so với bản hiện tại ({1})', ['${s.version}', '${cur.version}']),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.sub),
                ),
              ),
              if (!isCur)
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(value: true, label: Text(tr('Chỗ khác'))),
                    ButtonSegment(value: false, label: Text(tr('Toàn bộ bản này'))),
                  ],
                  selected: {_diff},
                  onSelectionChanged: (x) => setState(() => _diff = x.first),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            s.title,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: pal.text),
          ),
          const SizedBox(height: 14),
          // Chỗ khác: những gì bản hiện tại đổi so với bản đang chọn (khôi phục là bỏ các thay đổi đó).
          if (!isCur && _diff) DiffView(a: s.body, b: cur.body) else WikiMarkdown(text: s.body, api: store.api, files: s.files),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (_versions == null) return Center(child: _error != null ? Text('$_error') : const CircularProgressIndicator());
    final canRestore = (_current?.can('edit') ?? false) && _sel != null && _sel != _current?.version;
    if (!widget.wide) {
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(backgroundColor: pal.bg, surfaceTintColor: Colors.transparent, title: Text(tr('Lịch sử'))),
        body: Column(
          children: [
            SizedBox(height: 230, child: _list(pal)),
            Divider(height: 1, color: pal.divider),
            Expanded(child: _detail(pal)),
            if (canRestore)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: _restore,
                    icon: const Icon(Icons.restore_rounded),
                    label: Text(tr('Khôi phục bản {0}', ['$_sel'])),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final p = _current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bar(
          crumbs: [
            if (p != null)
              for (final x in p.path) (x.id, x.name),
            (null, p?.title ?? ''),
            (null, tr('Lịch sử')),
          ].cast<(String?, String)>(),
          onCrumb: widget.home._openFolder,
          actions: [
            TextButton.icon(onPressed: widget.onClose, icon: const Icon(Icons.close_rounded, size: 20), label: Text(tr('Đóng lịch sử'))),
            if (canRestore) ...[
              const SizedBox(width: 6),
              FilledButton.icon(
                key: const ValueKey('wiki-restore'),
                onPressed: _restore,
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: Text(tr('Khôi phục bản {0}', ['$_sel'])),
              ),
            ],
          ],
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _detail(pal)),
              Container(
                width: 340,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: pal.divider)),
                ),
                child: _list(pal),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryScreen extends StatelessWidget {
  const _HistoryScreen({required this.home, required this.pageId});
  final WikiHomeState home;
  final String pageId;
  @override
  Widget build(BuildContext context) => WikiHistory(home: home, pageId: pageId, wide: false);
}

// ============================================================ tìm kiếm
class WikiSearch extends StatefulWidget {
  const WikiSearch({super.key, required this.home, required this.query, required this.wide});
  final WikiHomeState home;
  final String query;
  final bool wide;
  @override
  State<WikiSearch> createState() => _WikiSearchState();
}

class _WikiSearchState extends State<WikiSearch> {
  List<Map<String, dynamic>>? _results;
  String _for = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(WikiSearch old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _run();
  }

  Future<void> _run() async {
    final q = widget.query.trim();
    if (q.isEmpty) return setState(() => _results = []);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted || widget.query.trim() != q) return;
    try {
      final r = await widget.home.store.search(q);
      if (mounted && widget.query.trim() == q) {
        setState(() {
          _results = r;
          _for = q;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final r = _results;
    final list = ListView(
      padding: EdgeInsets.fromLTRB(widget.wide ? 40 : 16, widget.wide ? 26 : 8, widget.wide ? 40 : 16, 60),
      children: [
        if (_error != null) Text('$_error', style: TextStyle(color: pal.sub)),
        if (r == null && _error == null)
          const Center(
            child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()),
          ),
        if (r != null && _for.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              r.isEmpty ? tr('Không tìm thấy trang nào khớp “{0}”', [_for]) : tr('{0} kết quả (chỉ hiện trang bạn được xem)', ['${r.length}']),
              style: TextStyle(color: pal.sub, fontSize: 13.5),
            ),
          ),
        for (final x in r ?? const <Map<String, dynamic>>[])
          InkWell(
            key: ValueKey('wiki-result-${x['id']}'),
            onTap: () => widget.home._openPage('${x['id']}'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: pal.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text([widget.home.store.rootName, ...(x['path'] as List)].join(' › '), style: TextStyle(fontSize: 12.5, color: pal.sub)),
                  const SizedBox(height: 3),
                  Text(
                    '${x['title']}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text),
                  ),
                  const SizedBox(height: 4),
                  _snippet(pal, Map<String, dynamic>.from(x['snippet'] as Map)),
                ],
              ),
            ),
          ),
      ],
    );
    return list;
  }

  Widget _snippet(Pal pal, Map<String, dynamic> s) {
    final text = '${s['text']}';
    final hl = [for (final h in s['hl'] as List) ((h as List)[0] as num).toInt(), for (final h in s['hl'] as List) ((h as List)[1] as num).toInt()];
    final n = (s['hl'] as List).length;
    final spans = <TextSpan>[];
    var at = 0;
    final mark = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF6B5400) : const Color(0xFFFFE58A);
    for (var i = 0; i < n; i++) {
      final a = hl[i].clamp(0, text.length), l = hl[n + i];
      final b = (a + l).clamp(0, text.length);
      if (a < at) continue;
      spans.add(TextSpan(text: text.substring(at, a)));
      spans.add(
        TextSpan(
          text: text.substring(a, b),
          style: TextStyle(backgroundColor: mark, color: pal.text),
        ),
      );
      at = b;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(
        children: spans,
        style: TextStyle(fontSize: 14, color: pal.sub, height: 1.5),
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SearchScreen extends StatefulWidget {
  const _SearchScreen({required this.home});
  final WikiHomeState home;
  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen> {
  final _q = TextEditingController();
  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: TextField(
          controller: _q,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(border: InputBorder.none, hintText: tr('Tìm trong wiki')),
        ),
      ),
      body: WikiSearch(home: widget.home, query: _q.text, wide: false),
    );
  }
}

// ============================================================ thùng rác, gần đây
class WikiTrash extends StatefulWidget {
  const WikiTrash({super.key, required this.home});
  final WikiHomeState home;
  @override
  State<WikiTrash> createState() => _WikiTrashState();
}

class _WikiTrashState extends State<WikiTrash> {
  List<Map<String, dynamic>>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.home.store.trash();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final items = _items;
    final wide = widget.home._wide;
    final list = ListView(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 12, wide ? 26 : 8, wide ? 40 : 12, 60),
      children: [
        if (wide)
          Text(
            tr('Thùng rác'),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: pal.text),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            tr('Trang và thư mục bị xoá nằm đây {0} ngày rồi tự xoá hẳn. Bạn thấy những mục mình có quyền khôi phục.', ['30']),
            style: TextStyle(color: pal.sub, fontSize: 13.5),
          ),
        ),
        if (_error != null) Text('$_error'),
        if (items == null && _error == null) const Center(child: CircularProgressIndicator()),
        if (items != null && items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(tr('Thùng rác trống.'), style: TextStyle(color: pal.sub)),
          ),
        for (final x in items ?? const <Map<String, dynamic>>[])
          ListTile(
            leading: Icon(x['type'] == 'folder' ? Icons.folder_rounded : Icons.description_outlined, color: x['type'] == 'folder' ? _folderColor : pal.sub),
            title: Text('${x['name']}'),
            subtitle: Text(
              tr('{0} · xoá bởi {1} {2}', [
                [widget.home.store.rootName, ...(x['path'] as List)].join(' › '),
                '${x['deleted_by_name']}',
                agoLabel((x['deleted_at'] as num).toInt()),
              ]),
              style: TextStyle(color: pal.sub, fontSize: 12.5),
            ),
            trailing: TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await widget.home.store.restoreTrash('${x['type']}', '${x['id']}');
                  messenger.showSnackBar(toast(Text(tr('Đã khôi phục “{0}”', ['${x['name']}']))));
                  _load();
                } catch (e) {
                  messenger.showSnackBar(toast(Text('$e')));
                }
              },
              child: Text(tr('Khôi phục')),
            ),
          ),
      ],
    );
    return list;
  }
}

class WikiRecent extends StatelessWidget {
  const WikiRecent({super.key, required this.home});
  final WikiHomeState home;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final store = home.store;
    return ListView(
      children: [
        for (final p in store.recent.take(40))
          ListTile(
            leading: Icon(Icons.description_outlined, color: pal.sub),
            title: Text(p.title),
            subtitle: Text(
              '${store.pathOf(p.folder).map((f) => f.name).join(' › ')} · ${p.updatedByName} · ${agoLabel(p.updatedAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pal.sub, fontSize: 12.5),
            ),
            onTap: () => home._openPage(p.id),
          ),
      ],
    );
  }
}

class _SimpleScreen extends StatelessWidget {
  const _SimpleScreen({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bg, surfaceTintColor: Colors.transparent, title: Text(title)),
      body: child,
    );
  }
}

class _ImageScreen extends StatelessWidget {
  const _ImageScreen({required this.name, required this.data});
  final String name;
  final Uint8List data;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(name)),
    body: InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(data))),
  );
}
