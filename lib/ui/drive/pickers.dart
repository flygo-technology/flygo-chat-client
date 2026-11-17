// Drive: chọn thư mục (di chuyển, sao chép, lưu vào Drive), "Lưu vào Drive" từ bảng chia sẻ của máy, và "Đính kèm từ
// Drive" trong chat (gửi bản sao tệp hoặc liên kết xem có hạn).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../forward_page.dart';
import 'actions.dart';
import 'api.dart';
import 'look.dart';
import 'session.dart';

/// Chọn một thư mục trong Drive của tôi. Trả đường dẫn, hoặc null nếu huỷ. [exclude]: thư mục không được chọn (chính
/// các thư mục đang di chuyển).
Future<String?> pickDriveFolder(BuildContext context, DriveSession s,
    {required String title, required String ok, String start = '/', Set<String> exclude = const {}}) {
  // Máy tính / màn hình rộng: hộp thoại giữa màn hình; điện thoại: trang toàn màn hình.
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        key: const ValueKey('drive-folder-dialog'),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Text(title, overflow: TextOverflow.ellipsis),
              actions: [IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(ctx).pop())],
            ),
            body: _FolderBrowser(session: s, start: start, exclude: exclude, ok: ok, onPick: (p) => Navigator.of(ctx).pop(p)),
          ),
        ),
      ),
    );
  }
  return Navigator.of(context).push<String>(AppPageRoute(
    fullscreenDialog: true,
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _FolderBrowser(session: s, start: start, exclude: exclude, ok: ok, onPick: (p) => Navigator.of(context).pop(p)),
    ),
  ));
}

class _FolderBrowser extends StatefulWidget {
  const _FolderBrowser({required this.session, required this.start, required this.ok, required this.onPick, this.exclude = const {}, this.header, this.footerNote});
  final DriveSession session;
  final String start, ok;
  final Set<String> exclude;
  final void Function(String path) onPick;
  final Widget? header;
  final String? footerNote;
  @override
  State<_FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<_FolderBrowser> {
  late String _path = widget.start;
  List<DriveItem>? _dirs;
  Object? _error;
  static final _recent = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _dirs = null;
      _error = null;
    });
    try {
      final list = (await widget.session.api.list(_path)).where((i) => i.dir).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() => _dirs = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _go(String p) {
    _path = p;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context);
    final parts = _path.split('/').where((x) => x.isNotEmpty).toList();
    final blocked = widget.exclude.any((e) => _path == e || _path.startsWith('$e/'));
    return Column(children: [
      ?widget.header,
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          TextButton(onPressed: () => _go('/'), child: Text(tr('Drive của tôi'), style: TextStyle(color: parts.isEmpty ? l.text : l.muted, fontWeight: parts.isEmpty ? FontWeight.w600 : null))),
          for (var i = 0; i < parts.length; i++) ...[
            Icon(Icons.chevron_right_rounded, size: 18, color: l.muted),
            TextButton(
              onPressed: () => _go('/${parts.sublist(0, i + 1).join('/')}'),
              child: Text(parts[i], style: TextStyle(color: i == parts.length - 1 ? l.text : l.muted, fontWeight: i == parts.length - 1 ? FontWeight.w600 : null)),
            ),
          ],
        ]),
      ),
      Divider(height: 1, color: l.line),
      Expanded(
        child: _error != null
            ? Center(child: Text('$_error'))
            : _dirs == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(children: [
                    for (final d in _dirs!)
                      ListTile(
                        enabled: !widget.exclude.contains(d.path),
                        leading: KindBadge(d),
                        title: Text(d.name),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _go(d.path),
                      ),
                    ListTile(
                      leading: Icon(Icons.create_new_folder_outlined, color: l.accentText),
                      title: Text(tr('Thư mục mới'), style: TextStyle(color: l.accentText)),
                      onTap: () async {
                        final name = await askName(context, title: tr('Thư mục mới'), initial: tr('Thư mục không có tiêu đề'), ok: tr('Tạo'), selectStem: false);
                        if (name == null || name.isEmpty || !context.mounted) return;
                        await driveRun(context, () async {
                          final it = await widget.session.api.mkdir(_path, name);
                          _go(it.path);
                        });
                      },
                    ),
                    if (_recent.isNotEmpty && _path == '/') ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                        child: Text(tr('GẦN ĐÂY'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: l.muted)),
                      ),
                      for (final r in _recent.take(4))
                        ListTile(leading: Icon(Icons.folder_outlined, color: l.muted), title: Text(r.substring(1).replaceAll('/', ' / ')), onTap: () => _go(r)),
                    ],
                  ]),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: l.line))),
          child: Row(children: [
            Expanded(child: Text(widget.footerNote ?? (parts.isEmpty ? tr('Drive của tôi') : parts.last), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.muted, fontSize: 13))),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: blocked
                  ? null
                  : () {
                      if (_path != '/') {
                        _recent.remove(_path);
                        _recent.insert(0, _path);
                      }
                      widget.onPick(_path);
                    },
              child: Text(widget.ok),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ Lưu vào Drive (bảng chia sẻ của máy)

/// Màn nhận chia sẻ: chọn "Gửi vào chat" (màn "Gửi tới…" sẵn có) hoặc "Lưu vào Drive". Không có Drive thì chỉ có chat.
class ShareTargetPage extends StatefulWidget {
  const ShareTargetPage({super.key, required this.paths, required this.text, required this.session, this.toDrive = false});
  final List<String> paths;
  final bool toDrive;
  final String text;
  final DriveSession session;
  @override
  State<ShareTargetPage> createState() => _ShareTargetPageState();
}

class _ShareTargetPageState extends State<ShareTargetPage> {
  late bool _drive = widget.toDrive;

  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context);
    final seg = SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, icon: const Icon(Icons.send_rounded), label: Text(tr('Gửi vào chat'))),
            ButtonSegment(value: true, icon: const Icon(Icons.add_to_drive_rounded), label: Text(tr('Lưu vào Drive'))),
          ],
          selected: {_drive},
          onSelectionChanged: (v) => setState(() => _drive = v.first),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: l.bg,
      body: Column(children: [
        seg,
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: _drive
                ? _SaveToDrive(session: widget.session, paths: widget.paths)
                : ForwardPage.share(localPaths: widget.paths, sharedText: widget.text),
          ),
        ),
      ]),
    );
  }
}

class _SaveToDrive extends StatelessWidget {
  const _SaveToDrive({required this.session, required this.paths});
  final DriveSession session;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context);
    final files = [for (final p in paths) File(p)];
    final total = files.fold<int>(0, (s, f) => s + (f.existsSync() ? f.lengthSync() : 0));
    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          Expanded(child: Text(tr('Lưu {0} tệp vào Drive', ['${paths.length}']), style: TextStyle(fontSize: 18, color: l.text))),
        ]),
      ),
      SizedBox(
        height: 80,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final f in files.take(12))
            Container(
              width: 72,
              height: 72,
              margin: const EdgeInsets.only(right: 8),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: l.surface2, borderRadius: BorderRadius.circular(10)),
              child: RegExp(r'\.(jpe?g|png|gif|webp|heic)$', caseSensitive: false).hasMatch(f.path)
                  ? Image.file(f, fit: BoxFit.cover, cacheWidth: 200, errorBuilder: (_, _, _) => const Icon(Icons.image_rounded))
                  : Center(child: KindBadge(DriveItem(path: f.path, name: f.uri.pathSegments.last, dir: false), size: 34)),
            ),
        ]),
      ),
    ]);
    return Material(
      color: l.surface,
      child: _FolderBrowser(
        session: session,
        start: '/',
        ok: tr('Lưu vào đây'),
        header: header,
        footerNote: tr('{0} tệp · {1}. Tải lên chạy nền, đóng màn này được.', ['${paths.length}', fmtSize(total)]),
        onPick: (dir) async {
          await session.uploads.add([for (final f in files) (f.path, f.uri.pathSegments.last)], dir, origin: 'share', copy: true);
          if (context.mounted) {
            driveToast(context, tr('Đang tải {0} tệp lên Drive', ['${files.length}']));
            Navigator.pop(context);
          }
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ Đính kèm từ Drive (chat)

/// Kết quả chọn trong chat: tệp tải về máy để gửi như tệp đính kèm, hoặc chữ (liên kết) để gửi.
/// Chế độ [remoteOnly]: [remote] là các mục Drive đã chọn (đường dẫn, tên, cỡ) — không tải về máy; [session] là phiên Drive
/// để app khác xin vé Drive cho máy chủ của nó tự lấy tệp.
class DriveAttachResult {
  DriveAttachResult({this.files = const [], this.text = '', this.remote = const [], this.session});
  final List<(String path, String name)> files;
  final String text;
  final List<DriveItem> remote;
  final DriveSession? session;
}

/// Chọn tệp từ Drive. Mặc định (chat): tải tệp về máy hoặc tạo liên kết xem. [remoteOnly]: chỉ trả các mục đã chọn,
/// không tải; [extensions] (vd ['pdf']) chỉ hiện tệp có đuôi đó; [single]: chọn một tệp.
Future<DriveAttachResult?> pickFromDrive(BuildContext context, {bool remoteOnly = false, List<String>? extensions, bool single = false}) async {
  final s = await DriveSession.current(context.read<AppState>());
  if (s == null || !context.mounted) {
    if (context.mounted) driveToast(context, tr('Bạn chưa được dùng Drive'));
    return null;
  }
  return showModalBottomSheet<DriveAttachResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: DriveLook.of(context).surface,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => FractionallySizedBox(
        heightFactor: .86, child: DriveAttachSheet(session: s, remoteOnly: remoteOnly, extensions: extensions, single: single || remoteOnly && extensions != null)),
  );
}

class DriveAttachSheet extends StatefulWidget {
  const DriveAttachSheet({super.key, required this.session, this.remoteOnly = false, this.extensions, this.single = false});
  final DriveSession session;

  /// Chỉ chọn (không tải về máy, không tạo liên kết).
  final bool remoteOnly;

  /// Chỉ hiện tệp có các đuôi này (chữ thường, không dấu chấm); thư mục luôn hiện.
  final List<String>? extensions;
  final bool single;
  @override
  State<DriveAttachSheet> createState() => _DriveAttachSheetState();
}

class _DriveAttachSheetState extends State<DriveAttachSheet> {
  String _tab = 'recent', _path = '/', _q = '';
  List<DriveItem>? _items;
  final _picked = <String, DriveItem>{};
  bool _asLink = false, _busy = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _items = null);
    final api = widget.session.api;
    try {
      final list = _q.isNotEmpty
          ? await api.search(q: _q)
          : switch (_tab) {
              'my' => await api.list(_path),
              'starred' => await api.starred(),
              'shared' => await api.shared(),
              _ => await api.recent(),
            };
      final ext = widget.extensions;
      if (ext != null) list.removeWhere((it) => !it.dir && !ext.contains(it.name.split('.').last.toLowerCase()));
      if (_tab == 'my' && _q.isEmpty) list.sort((a, b) => a.dir != b.dir ? (a.dir ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        setState(() => _items = const []);
        driveToast(context, '$e');
      }
    }
  }

  Future<void> _send() async {
    final s = widget.session, picked = _picked.values.toList();
    if (widget.remoteOnly) {
      Navigator.pop(context, DriveAttachResult(remote: picked, session: s));
      return;
    }
    setState(() => _busy = true);
    try {
      if (_asLink) {
        // Liên kết chỉ xem, hết hạn sau 30 ngày (ai có liên kết mở được, không cần tài khoản Drive).
        final exp = DateTime.now().add(const Duration(days: 30)).toIso8601String().substring(0, 10);
        final lines = <String>[];
        for (final it in picked) {
          final sh = await s.api.share(path: it.path, type: 'link', expires: exp);
          lines.add('${it.name}: ${sh.url}');
        }
        if (mounted) Navigator.pop(context, DriveAttachResult(text: lines.join('\n')));
      } else {
        final total = picked.fold<int>(0, (a, b) => a + b.size);
        var base = 0;
        final out = <(String, String)>[];
        for (final it in picked) {
          final f = await localCopy(s, it, onProgress: (got, _) {
            if (mounted && total > 0) setState(() => _progress = (base + got) / total);
          });
          base += it.size;
          out.add((f.path, it.name));
        }
        if (mounted) Navigator.pop(context, DriveAttachResult(files: out));
      }
    } catch (e) {
      if (mounted) driveToast(context, tr('Không gửi được: {0}', ['$e']));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context);
    final items = _items;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 12, 6),
        child: Row(children: [
          Expanded(child: Text(widget.remoteOnly ? tr('Chọn từ Drive') : tr('Đính kèm từ Drive'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: l.text))),
          SizedBox(
            width: 180,
            child: TextField(
              decoration: InputDecoration(isDense: true, hintText: tr('Tìm tệp'), prefixIcon: const Icon(Icons.search_rounded, size: 20), border: const OutlineInputBorder()),
              onSubmitted: (v) {
                _q = v.trim();
                _load();
              },
            ),
          ),
        ]),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          for (final (id, label) in [('recent', tr('Gần đây')), ('my', tr('Drive của tôi')), ('starred', tr('Gắn sao')), ('shared', tr('Được chia sẻ'))])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: _tab == id && _q.isEmpty,
                showCheckmark: false,
                onSelected: (_) {
                  _tab = id;
                  _q = '';
                  _path = '/';
                  _load();
                },
              ),
            ),
        ]),
      ),
      if (_tab == 'my' && _path != '/' && _q.isEmpty)
        ListTile(
          dense: true,
          leading: const Icon(Icons.arrow_upward_rounded),
          title: Text(_path.substring(1).replaceAll('/', ' / ')),
          onTap: () {
            _path = parentOf(_path);
            _load();
          },
        ),
      Expanded(
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? Center(child: Text(tr('Không có tệp'), style: TextStyle(color: l.muted)))
                : ListView(children: [
                    for (final it in items)
                      Material(
                        color: _picked.containsKey(it.path) ? l.sel : Colors.transparent,
                        child: ListTile(
                          leading: KindBadge(it),
                          title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text([if (it.mtime > 0) tr('Sửa {0}', [fmtDate(it.mtime)]), if (!it.dir) fmtSize(it.size)].join(' · ')),
                          trailing: it.dir
                              ? const Icon(Icons.chevron_right_rounded)
                              : Icon(_picked.containsKey(it.path) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                  color: _picked.containsKey(it.path) ? l.accent : l.line),
                          onTap: () {
                            if (it.dir) {
                              _tab = 'my';
                              _q = '';
                              _path = it.path;
                              _load();
                              return;
                            }
                            setState(() {
                              if (_picked.containsKey(it.path)) {
                                _picked.remove(it.path);
                              } else {
                                if (widget.single) _picked.clear();
                                _picked[it.path] = it;
                              }
                            });
                          },
                        ),
                      ),
                  ]),
      ),
      SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: l.line))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!widget.remoteOnly) RadioGroup<bool>(
              groupValue: _asLink,
              onChanged: (v) => setState(() => _asLink = v ?? false),
              child: Column(children: [
                RadioListTile<bool>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: false,
                  title: Text(tr('Gửi bản sao tệp')),
                  subtitle: Text(tr('Ai trong cuộc trò chuyện cũng mở được')),
                ),
                RadioListTile<bool>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: true,
                  title: Text(tr('Gửi liên kết xem')),
                  subtitle: Text(tr('Liên kết chỉ xem, hết hạn sau 30 ngày')),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _picked.isEmpty || _busy ? null : _send,
                icon: _busy
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, value: _asLink || _progress == 0 ? null : _progress, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: Text(widget.remoteOnly
                    ? (_picked.isEmpty ? tr('Chọn tệp') : tr('Chọn {0}', [_picked.values.first.name]))
                    : _picked.isEmpty
                        ? tr('Chọn tệp để gửi')
                        : tr('Gửi {0} tệp', ['${_picked.length}'])),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
