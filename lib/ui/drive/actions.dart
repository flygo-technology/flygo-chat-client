// Drive: thao tác trên tệp — bảng thao tác (điện thoại) / menu (máy tính), đổi tên, di chuyển, sao chép, gắn sao, ghim
// offline, xoá, chi tiết + hoạt động, hộp thoại chia sẻ (người, nhóm, link có hạn và mật khẩu).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/i18n.dart';
import '../forward_page.dart';
import '../app_route.dart';
import '../theme.dart' show toast;
import 'api.dart';
import 'look.dart';
import 'pickers.dart';
import 'session.dart';
import 'transfers.dart';

bool driveWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;

void driveToast(BuildContext context, String msg) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(msg)));

/// Chạy một thao tác, báo lỗi nếu có. Trả true nếu thành công.
Future<bool> driveRun(BuildContext context, Future<void> Function() fn, {String? done}) async {
  final m = ScaffoldMessenger.maybeOf(context);
  try {
    await fn();
    if (done != null) m?.showSnackBar(toast(Text(done)));
    return true;
  } catch (e) {
    m?.showSnackBar(toast(Text(tr('Không thực hiện được: {0}', ['$e']))));
    return false;
  }
}

Future<String?> askName(BuildContext context, {required String title, String initial = '', String ok = 'OK', bool selectStem = true}) {
  final c = TextEditingController(text: initial);
  final dot = initial.lastIndexOf('.');
  c.selection = TextSelection(baseOffset: 0, extentOffset: selectStem && dot > 0 ? dot : initial.length);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(d, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

Future<bool> confirmDrive(BuildContext context, String title, String body, {String ok = 'OK', bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: DriveLook.of(context).danger) : null,
            onPressed: () => Navigator.pop(d, true),
            child: Text(ok),
          ),
        ],
      ),
    ) ==
    true;

enum ItemAction { open, office, share, link, chat, offline, star, rename, move, copy, download, details, trash, restore, purge }

/// Các thao tác cho [items] (một hoặc nhiều mục). [trash]: đang ở thùng rác.
List<(ItemAction, IconData, String)> actionsFor(DriveSession s, List<DriveItem> items, {bool trash = false}) {
  if (trash) {
    return [
      (ItemAction.restore, Icons.restore_rounded, tr('Khôi phục')),
      (ItemAction.purge, Icons.delete_forever_rounded, tr('Xoá vĩnh viễn')),
    ];
  }
  final one = items.length == 1 ? items.first : null;
  final allFav = items.every((i) => i.fav);
  final allPinned = items.every((i) => s.offline.pinned(i.path));
  return [
    if (one != null && isOffice(one)) (ItemAction.office, Icons.edit_document, tr('Mở bằng OnlyOffice')),
    if (one != null && one.canShare) (ItemAction.share, Icons.person_add_alt_1_rounded, tr('Chia sẻ')),
    if (one != null) (ItemAction.link, Icons.link_rounded, tr('Sao chép liên kết')),
    if (items.every((i) => !i.dir)) (ItemAction.chat, Icons.chat_bubble_outline_rounded, tr('Gửi vào cuộc trò chuyện')),
    (ItemAction.offline, allPinned ? Icons.cloud_done_rounded : Icons.download_for_offline_outlined, allPinned ? tr('Bỏ dùng khi không có mạng') : tr('Dùng khi không có mạng')),
    (ItemAction.star, allFav ? Icons.star_rounded : Icons.star_outline_rounded, allFav ? tr('Bỏ gắn sao') : tr('Gắn sao')),
    if (one != null && one.canWrite) (ItemAction.rename, Icons.drive_file_rename_outline_rounded, tr('Đổi tên')),
    if (items.every((i) => i.canDelete)) (ItemAction.move, Icons.drive_file_move_outline, tr('Di chuyển')),
    (ItemAction.copy, Icons.file_copy_outlined, tr('Tạo bản sao')),
    (ItemAction.download, Icons.file_download_outlined, tr('Tải xuống')),
    if (one != null) (ItemAction.details, Icons.info_outline_rounded, tr('Chi tiết và hoạt động')),
    if (items.every((i) => i.canDelete)) (ItemAction.trash, Icons.delete_outline_rounded, tr('Chuyển vào thùng rác')),
  ];
}

/// Bảng thao tác (điện thoại: sheet từ dưới lên; máy tính: menu tại [at]).
Future<void> showItemActions(BuildContext context, DriveSession s, DriveItem it,
    {VoidCallback? onChanged, Offset? at, bool trash = false, bool fromPreview = false}) async {
  final acts = actionsFor(s, [it], trash: trash).where((a) => !(fromPreview && a.$1 == ItemAction.office)).toList();
  final l = DriveLook.of(context);
  ItemAction? a;
  if (at != null || driveWide(context)) {
    final pos = at ?? MediaQuery.sizeOf(context).center(Offset.zero);
    a = await showMenu<ItemAction>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        for (final (id, icon, label) in acts)
          PopupMenuItem(
            value: id,
            height: 42,
            child: Row(children: [
              Icon(icon, size: 20, color: id == ItemAction.trash || id == ItemAction.purge ? l.danger : l.muted),
              const SizedBox(width: 14),
              Text(label, style: TextStyle(color: id == ItemAction.trash || id == ItemAction.purge ? l.danger : null)),
            ]),
          ),
      ],
    );
  } else {
    a = await showModalBottomSheet<ItemAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: l.surface,
      builder: (sh) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sh).height * .85),
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              leading: KindBadge(it),
              title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text([if (!it.dir) fmtSize(it.size), if (it.mtime > 0) tr('Sửa {0}', [fmtDate(it.mtime)])].join(' · ')),
            ),
            Divider(height: 1, color: l.line),
            for (final (id, icon, label) in acts)
              ListTile(
                dense: true,
                leading: Icon(icon, color: id == ItemAction.trash || id == ItemAction.purge ? l.danger : l.muted),
                title: Text(label, style: TextStyle(fontSize: 15, color: id == ItemAction.trash || id == ItemAction.purge ? l.danger : null)),
                trailing: id == ItemAction.offline ? Switch(value: s.offline.pinned(it.path), onChanged: (_) => Navigator.pop(sh, id)) : null,
                onTap: () => Navigator.pop(sh, id),
              ),
          ]),
        ),
      ),
    );
  }
  if (a == null || !context.mounted) return;
  await runItemAction(context, s, a, [it], onChanged: onChanged);
}

/// Thực hiện thao tác [a] trên [items].
Future<void> runItemAction(BuildContext context, DriveSession s, ItemAction a, List<DriveItem> items, {VoidCallback? onChanged}) async {
  final api = s.api;
  final paths = [for (final i in items) i.path];
  final one = items.first;
  switch (a) {
    case ItemAction.open:
      await openDriveFile(context, s, one);
    case ItemAction.office:
      await openOffice(context, s, one);
    case ItemAction.share:
      await showShareDialog(context, s, one);
      onChanged?.call();
    case ItemAction.link:
      final web = (s.me ?? await s.loadMe()).webUrl;
      await Clipboard.setData(ClipboardData(text: '$web/f/${one.id}'));
      if (context.mounted) driveToast(context, tr('Đã sao chép liên kết (chỉ người có quyền mới mở được)'));
    case ItemAction.chat:
      final files = <String>[];
      final ok = await driveRun(context, () async {
        for (final it in items) {
          files.add((await localCopy(s, it)).path);
        }
      });
      if (ok && context.mounted) await Navigator.of(context).push(AppPageRoute(builder: (_) => ForwardPage.share(localPaths: files)));
    case ItemAction.offline:
      final pin = !items.every((i) => s.offline.pinned(i.path));
      await driveRun(context, () async {
        for (final it in items) {
          pin ? await s.offline.pin(it) : await s.offline.unpin(it);
        }
      }, done: pin ? tr('Đã lưu để dùng khi không có mạng') : tr('Đã bỏ bản lưu trên máy'));
      onChanged?.call();
    case ItemAction.star:
      final on = !items.every((i) => i.fav);
      if (await driveRun(context, () => api.star(paths, on))) {
        for (final i in items) {
          i.fav = on;
        }
      }
      onChanged?.call();
    case ItemAction.rename:
      final name = await askName(context, title: tr('Đổi tên'), initial: one.name, ok: tr('Đổi tên'), selectStem: !one.dir);
      if (name == null || name.isEmpty || name == one.name || !context.mounted) return;
      await driveRun(context, () => api.rename(one.path, name));
      onChanged?.call();
    case ItemAction.move:
    case ItemAction.copy:
      final move = a == ItemAction.move;
      final to = await pickDriveFolder(context, s,
          title: move ? tr('Di chuyển {0} mục', ['${items.length}']) : tr('Sao chép {0} mục', ['${items.length}']),
          ok: move ? tr('Chuyển tới đây') : tr('Sao chép vào đây'),
          start: one.parent,
          exclude: items.where((i) => i.dir).map((i) => i.path).toSet());
      if (to == null || !context.mounted) return;
      await driveRun(context, () => move ? api.move(paths, to) : api.copy(paths, to), done: move ? tr('Đã di chuyển') : tr('Đã tạo bản sao'));
      onChanged?.call();
    case ItemAction.download:
      // Điện thoại, một tệp: tải rồi mở bằng app khác như cũ (tiến độ ở bảng dưới); còn lại tải về máy.
      if (items.length == 1 && !one.dir && !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final d = await startDownload(s, items);
        if (d.state == DownloadState.done) await openWithSystem(d.files.first);
      } else {
        await downloadMany(context, s, items);
      }
    case ItemAction.details:
      await showDetails(context, s, one);
    case ItemAction.trash:
      if (await driveRun(context, () => api.remove(paths), done: tr('Đã chuyển {0} mục vào thùng rác', ['${items.length}']))) {
        for (final it in items) {
          if (s.offline.pinnedRoot(it.path)) await s.offline.unpin(it);
        }
      }
      onChanged?.call();
    case ItemAction.restore:
      await driveRun(context, () => api.restore([for (final i in items) if (i is DriveTrashItem) i.trashId]), done: tr('Đã khôi phục'));
      onChanged?.call();
    case ItemAction.purge:
      if (!await confirmDrive(context, tr('Xoá vĩnh viễn?'), tr('{0} mục sẽ bị xoá hẳn, không khôi phục được.', ['${items.length}']), ok: tr('Xoá vĩnh viễn'), danger: true)) return;
      if (!context.mounted) return;
      await driveRun(context, () => api.purge([for (final i in items) if (i is DriveTrashItem) i.trashId]), done: tr('Đã xoá vĩnh viễn'));
      onChanged?.call();
  }
}

/// Tải xuống [items]: tiến độ và nút "Mở thư mục" / "Mở tệp" ở bảng dưới màn hình ([TransfersPanel]).
/// Máy tính lưu vào thư mục Tải về; điện thoại tải vào thư mục tạm rồi mở / chia sẻ từ bảng.
Future<void> downloadMany(BuildContext context, DriveSession s, List<DriveItem> items) => startDownload(s, items);

// ------------------------------------------------------------------ chi tiết + hoạt động

Future<void> showDetails(BuildContext context, DriveSession s, DriveItem it) => Navigator.of(context).push(AppPageRoute(
      builder: (c) => Scaffold(
        backgroundColor: DriveLook.of(c).surface,
        appBar: AppBar(backgroundColor: DriveLook.of(c).surface, title: Text(it.name, overflow: TextOverflow.ellipsis)),
        body: DetailsPanel(session: s, item: it),
      ),
    ));

class DetailsPanel extends StatefulWidget {
  const DetailsPanel({super.key, required this.session, required this.item, this.onClose});
  final DriveSession session;
  final DriveItem item;
  final VoidCallback? onClose;
  @override
  State<DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<DetailsPanel> {
  int _tab = 0;
  List<DriveShare>? _shares;
  List<DriveActivity>? _activity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DetailsPanel old) {
    super.didUpdateWidget(old);
    if (old.item.path != widget.item.path) {
      _shares = null;
      _activity = null;
      _load();
    }
  }

  Future<void> _load() async {
    final api = widget.session.api, it = widget.item;
    try {
      final sh = await api.shares(it.path);
      if (mounted) setState(() => _shares = sh);
    } catch (_) {
      if (mounted) setState(() => _shares = const []);
    }
    if (it.id > 0) {
      try {
        final a = await api.activity(it.id);
        if (mounted) setState(() => _activity = a);
      } catch (_) {
        if (mounted) setState(() => _activity = const []);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context), it = widget.item, s = widget.session;
    final off = s.offline.entries[it.path];
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: TextStyle(fontSize: 12.5, color: l.muted)),
            const SizedBox(height: 2),
            Text(v, style: TextStyle(fontSize: 14.5, color: l.text)),
          ]),
        );
    final access = _shares == null
        ? '…'
        : [
            tr('Bạn'),
            for (final sh in _shares!)
              sh.type == 'link' ? tr('Bất kỳ ai có liên kết ({0})', [sh.canEdit ? tr('sửa') : tr('xem')]) : '${sh.withName} (${sh.canEdit ? tr('sửa') : tr('xem')})',
          ].join(', ');
    return ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 24), children: [
      if (widget.onClose != null)
        Row(children: [
          KindBadge(it, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: l.text))),
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: widget.onClose),
        ]),
      Container(
        height: 160,
        margin: const EdgeInsets.symmetric(vertical: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: l.surface2, borderRadius: BorderRadius.circular(12)),
        child: DriveThumb(api: s.api, item: it, size: 512, fit: BoxFit.contain),
      ),
      Row(children: [
        for (final (i, label) in [(0, tr('Chi tiết')), (1, tr('Hoạt động'))])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(label), selected: _tab == i, onSelected: (_) => setState(() => _tab = i), showCheckmark: false),
          ),
      ]),
      const SizedBox(height: 8),
      if (_tab == 0) ...[
        row(tr('Có quyền truy cập'), access),
        if (off != null) row(tr('Ngoại tuyến'), s.offline.busy.contains(it.path) ? tr('Đang lưu về máy…') : tr('Đã lưu trên máy này')),
        row(tr('Loại'), kindName(kindOf(it))),
        if (!it.dir) row(tr('Kích thước'), fmtSize(it.size)),
        row(tr('Vị trí'), it.parent == '/' ? tr('Drive của tôi') : it.parent),
        if (it.ownerName.isNotEmpty) row(tr('Chủ sở hữu'), it.owner == s.me?.uid ? tr('tôi') : it.ownerName),
        if (it.mtime > 0) row(tr('Sửa lần cuối'), fmtDate(it.mtime)),
        if (isOffice(it))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(onPressed: () => openOffice(context, s, it), icon: const Icon(Icons.edit_document, size: 18), label: Text(tr('Mở bằng OnlyOffice'))),
            ),
          ),
      ] else if (_activity == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (_activity!.isEmpty)
        Padding(padding: const EdgeInsets.all(16), child: Text(tr('Chưa có hoạt động'), style: TextStyle(color: l.muted)))
      else
        for (final a in _activity!)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.history_rounded, color: l.muted),
            title: Text(a.subject, style: const TextStyle(fontSize: 14)),
            subtitle: Text(fmtDate(a.time)),
          ),
    ]);
  }
}

// ------------------------------------------------------------------ chia sẻ

Future<void> showShareDialog(BuildContext context, DriveSession s, DriveItem it) => showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720), child: ShareDialog(session: s, item: it)),
      ),
    );

class ShareDialog extends StatefulWidget {
  const ShareDialog({super.key, required this.session, required this.item});
  final DriveSession session;
  final DriveItem item;
  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  final _q = TextEditingController();
  List<DriveShare> _shares = const [];
  List<DrivePerson> _found = const [];
  bool _loading = true, _edit = false;
  String _queryAt = '';

  DriveApi get api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sh = await api.shares(widget.item.path);
      if (mounted) setState(() => _shares = sh);
    } catch (e) {
      if (mounted) driveToast(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String q) async {
    _queryAt = q;
    if (q.trim().length < 2) {
      setState(() => _found = const []);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_queryAt != q) return;
    try {
      final r = await api.sharees(q.trim());
      if (mounted && _queryAt == q) setState(() => _found = r);
    } catch (_) {}
  }

  Future<void> _add(DrivePerson p) async {
    final ok = await driveRun(context, () => api.share(path: widget.item.path, type: p.type, withId: p.id, canEdit: _edit));
    if (!ok || !mounted) return;
    _q.clear();
    setState(() => _found = const []);
    await _load();
  }

  DriveShare? get _link => _shares.where((x) => x.type == 'link').firstOrNull;

  Future<void> _linkSettings(DriveShare? cur) async {
    final res = await showDialog<Map<String, Object?>>(context: context, builder: (_) => _LinkDialog(share: cur));
    if (res == null || !mounted) return;
    if (cur == null) {
      final ok = await driveRun(context,
          () => api.share(path: widget.item.path, type: 'link', canEdit: res['can_edit'] == true, expires: res['expires'] as String?, password: res['password'] as String?));
      if (ok) await _load();
      final l = _link?.url;
      if (l != null) {
        await Clipboard.setData(ClipboardData(text: l));
        if (mounted) driveToast(context, tr('Đã tạo và sao chép liên kết'));
      }
    } else {
      await driveRun(context, () => api.updateShare(cur.id, {'type': 'link', ...res}), done: tr('Đã lưu'));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context);
    final link = _link;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Chia sẻ "{0}"', [widget.item.name]), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, color: l.text)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              onChanged: _search,
              decoration: InputDecoration(
                hintText: tr('Thêm người hoặc nhóm'),
                prefixIcon: const Icon(Icons.person_search_rounded),
                filled: true,
                fillColor: l.surface2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<bool>(
            value: _edit,
            underline: const SizedBox(),
            items: [DropdownMenuItem(value: false, child: Text(tr('Người xem'))), DropdownMenuItem(value: true, child: Text(tr('Người chỉnh sửa')))],
            onChanged: (v) => setState(() => _edit = v ?? false),
          ),
        ]),
        if (_found.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(border: Border.all(color: l.line), borderRadius: BorderRadius.circular(10)),
            child: ListView(shrinkWrap: true, children: [
              for (final p in _found)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(child: Icon(p.type == 'group' ? Icons.groups_rounded : Icons.person_rounded, size: 20)),
                  title: Text(p.label),
                  subtitle: p.sub.isEmpty ? null : Text(p.sub),
                  onTap: () => _add(p),
                ),
            ]),
          ),
        const SizedBox(height: 16),
        Text(tr('Những người có quyền truy cập'), style: TextStyle(fontWeight: FontWeight.w600, color: l.text)),
        const SizedBox(height: 4),
        Flexible(
          child: _loading
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              : ListView(shrinkWrap: true, children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                    title: Text(tr('Bạn')),
                    trailing: Text(tr('Chủ sở hữu'), style: TextStyle(color: l.muted)),
                  ),
                  for (final sh in _shares.where((x) => x.type != 'link'))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Icon(sh.type == 'group' ? Icons.groups_rounded : Icons.person_rounded)),
                      title: Text(sh.withName),
                      subtitle: sh.expires == null ? null : Text(tr('Hết hạn {0}', [sh.expires!])),
                      trailing: PopupMenuButton<String>(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(sh.canEdit ? tr('Người chỉnh sửa') : tr('Người xem')), const Icon(Icons.arrow_drop_down)]),
                        onSelected: (v) async {
                          if (v == 'rm') {
                            await driveRun(context, () => api.unshare(sh.id));
                          } else {
                            await driveRun(context, () => api.updateShare(sh.id, {'can_edit': v == 'edit'}));
                          }
                          await _load();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'view', child: Text(tr('Người xem'))),
                          PopupMenuItem(value: 'edit', child: Text(tr('Người chỉnh sửa'))),
                          const PopupMenuDivider(),
                          PopupMenuItem(value: 'rm', child: Text(tr('Xoá quyền truy cập'), style: TextStyle(color: l.danger))),
                        ],
                      ),
                    ),
                ]),
        ),
        const SizedBox(height: 12),
        Text(tr('Quyền truy cập chung'), style: TextStyle(fontWeight: FontWeight.w600, color: l.text)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: link == null ? l.surface2 : const Color(0xFFCEEAD6),
            child: Icon(link == null ? Icons.lock_rounded : Icons.public_rounded, color: link == null ? l.muted : const Color(0xFF137333)),
          ),
          title: Text(link == null ? tr('Bị hạn chế') : tr('Bất kỳ ai có đường liên kết')),
          subtitle: Text(link == null
              ? tr('Chỉ những người có quyền truy cập mới mở được')
              : [
                  link.canEdit ? tr('Có thể chỉnh sửa') : tr('Chỉ xem'),
                  if (link.expires != null) tr('hết hạn {0}', [link.expires!]),
                  if (link.hasPassword) tr('có mật khẩu'),
                ].join(' · ')),
          trailing: link == null
              ? TextButton(onPressed: () => _linkSettings(null), child: Text(tr('Tạo liên kết')))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: tr('Cài đặt liên kết'), icon: const Icon(Icons.tune_rounded), onPressed: () => _linkSettings(link)),
                  IconButton(
                    tooltip: tr('Tắt liên kết'),
                    icon: Icon(Icons.link_off_rounded, color: l.danger),
                    onPressed: () async {
                      await driveRun(context, () => api.unshare(link.id));
                      await _load();
                    },
                  ),
                ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (link?.url != null)
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link!.url!));
                if (context.mounted) driveToast(context, tr('Đã sao chép liên kết'));
              },
              icon: const Icon(Icons.link_rounded),
              label: Text(tr('Sao chép đường liên kết')),
            ),
          const Spacer(),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Xong'))),
        ]),
      ]),
    );
  }
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({this.share});
  final DriveShare? share;
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late bool _edit = widget.share?.canEdit ?? false;
  late String? _expires = widget.share?.expires ?? _plus(7);
  final _pass = TextEditingController();
  late bool _usePass = widget.share?.hasPassword ?? false;

  static String _plus(int days) => DateTime.now().add(Duration(days: days)).toIso8601String().substring(0, 10);

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Liên kết chia sẻ')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Cho phép chỉnh sửa')), value: _edit, onChanged: (v) => setState(() => _edit = v)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hết hạn')),
            subtitle: Text(_expires ?? tr('Không hết hạn')),
            trailing: Wrap(spacing: 4, children: [
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context, firstDate: DateTime.now().add(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 3650)), initialDate: DateTime.tryParse(_expires ?? '') ?? DateTime.now().add(const Duration(days: 7)));
                  if (d != null) setState(() => _expires = d.toIso8601String().substring(0, 10));
                },
                child: Text(tr('Chọn ngày')),
              ),
              if (_expires != null) IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _expires = null)),
            ]),
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Đặt mật khẩu')), value: _usePass, onChanged: (v) => setState(() => _usePass = v)),
          if (_usePass)
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: widget.share?.hasPassword == true ? tr('Để trống: giữ mật khẩu cũ') : tr('Mật khẩu'),
              ),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () {
              final res = <String, Object?>{'can_edit': _edit, 'expires': _expires ?? ''};
              if (_usePass && _pass.text.isNotEmpty) res['password'] = _pass.text;
              if (!_usePass && widget.share?.hasPassword == true) res['password'] = '';
              if (widget.share == null && (_expires == null)) res.remove('expires');
              Navigator.pop(context, res);
            },
            child: Text(tr('Lưu')),
          ),
        ],
      );
}
