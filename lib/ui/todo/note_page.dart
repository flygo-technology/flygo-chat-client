// Todo: trang sửa một ghi chú (điện thoại: toàn màn hình; máy tính: hộp thoại giữa màn hình như Keep).
// Lưu tự động khi gõ (gộp 0,6 giây), ghi chú mới chỉ lưu khi đã có nội dung.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart' show isDesktop;
import '../../i18n/i18n.dart';
import '../app_route.dart';
import '../clip.dart' show readClipboardMedia;
import '../theme.dart' show toast;
import 'api.dart';
import 'block_editor.dart';
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'rich.dart';
import 'store.dart';
import '../common.dart' show pickFilesOrReport;

/// Mở ghi chú [n] (ghi chú mới: store.draft()).
Future<void> openNote(BuildContext context, TodoStore store, TNote n, {bool pickImage = false}) {
  final page = NotePage(store: store, note: n, pickImage: pickImage);
  if (isDesktop && MediaQuery.sizeOf(context).width >= 760) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 680, maxHeight: MediaQuery.sizeOf(c).height * .88), child: page),
      ),
    );
  }
  return Navigator.of(context).push(AppPageRoute(builder: (_) => page));
}

class NotePage extends StatefulWidget {
  const NotePage({super.key, required this.store, required this.note, this.pickImage = false});
  final TodoStore store;
  final TNote note;
  final bool pickImage;
  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  late TNote _n = widget.note.clone();
  late final _title = TextEditingController(text: _n.title);
  final _ed = BlockEditorController();
  final _save = Debouncer(const Duration(milliseconds: 600));
  final _dirty = <String>{};
  int _rev = 0, _seenVersion = 0;
  bool _format = false, _uploading = false;

  TodoStore get store => widget.store;
  TodoApi get api => store.api;
  bool get _ro => !_n.canEdit || _n.trashed;

  @override
  void initState() {
    super.initState();
    _seenVersion = _n.version;
    store.addListener(_remote);
    _ed.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.pickImage) WidgetsBinding.instance.addPostFrameCallback((_) => _attach(images: true));
  }

  @override
  void dispose() {
    store.removeListener(_remote);
    _save.flush();
    _title.dispose();
    _ed.dispose();
    super.dispose();
  }

  /// Bản trên máy chủ đổi (người khác sửa, hoặc lần lưu của mình vừa xong).
  void _remote() {
    final s = store.notes[_n.id];
    if (s == null) {
      // Bị xoá / bỏ chia sẻ khi đang mở.
      if (_n.version > 0 && mounted) Navigator.of(context).maybePop();
      return;
    }
    if (s.version == _seenVersion) {
      // Chỉ trạng thái riêng đổi (ghim, nhãn…): cập nhật thanh dưới.
      setState(() => _n = _merge(s));
      return;
    }
    _seenVersion = s.version;
    final fromOther = s.editedBy != null && s.editedBy != store.meId;
    if (fromOther && _dirty.isEmpty && !store.hasPending(_n.id)) {
      setState(() {
        _n = s.clone();
        if (_title.text != _n.title) _title.text = _n.title;
        _rev++;
      });
    } else {
      setState(() => _n = _merge(s));
    }
  }

  /// Bản máy chủ cho phần không đang sửa (tệp, người chia sẻ, version…), giữ phần đang sửa của mình.
  TNote _merge(TNote s) {
    final x = s.clone();
    x.title = _n.title;
    x.blocks = _n.blocks;
    x.kind = _n.kind;
    return x;
  }

  void _set(Map<String, dynamic> b, {bool content = false}) {
    if (content) _dirty.addAll(b.keys);
    if (!content) _n.applyPut(b);
    final isNew = !store.notes.containsKey(_n.id);
    if (isNew && _n.isEmpty) return; // chưa có gì: chưa tạo ghi chú
    _save(() {
      final body = <String, dynamic>{
        for (final k in _dirty)
          k: switch (k) {
            'title' => _n.title,
            'blocks' => [for (final x in _n.blocks) x.toJson()],
            'kind' => _n.kind,
            _ => null,
          },
        ...b,
      };
      _dirty.clear();
      store.put(_n, body);
    });
    if (!content) _save.flush();
  }

  void _content() => _set({}, content: true);

  // ------------------------------------------------------------ tệp
  Future<void> _upload(List<(String name, Future<List<int>> Function() read)> files) async {
    if (files.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      for (final (name, read) in files) {
        final bytes = await read();
        final f = await api.upload(name, Uint8List.fromList(bytes));
        _n.files = [..._n.files, TFile.fromJson(f)];
      }
      _flushContent({'files': _n.files});
    } catch (e) {
      messenger.showSnackBar(toast(Text(TodoApi.isOffline(e) ? tr('Không tải tệp lên được: đang mất mạng') : '$e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Gửi ngay (tệp): ghi chú mới có tệp là đủ để tạo.
  void _flushContent(Map<String, dynamic> b) {
    _save.flush();
    store.put(_n, {..._dirty.isEmpty ? {} : {'title': _n.title, 'blocks': [for (final x in _n.blocks) x.toJson()], 'kind': _n.kind}, ...b});
    _dirty.clear();
    setState(() {});
  }

  Future<void> _attach({required bool images}) async {
    final r = await pickFilesOrReport(context, type: images ? FileType.image : FileType.any);
    await _upload([
      for (final f in r)
        if (f.path != null) (f.name, () => File(f.path!).readAsBytes()),
    ]);
  }

  Future<bool> _pasteMedia() async {
    final media = await readClipboardMedia();
    if (media.isEmpty) return false;
    await _upload([for (final (p, name) in media) (name, () => File(p).readAsBytes())]);
    return true;
  }

  void _insertBytes(Uint8List data, String mime) {
    final ext = mime.split('/').last.replaceAll('jpeg', 'jpg');
    _upload([('anh_${DateTime.now().millisecondsSinceEpoch}.$ext', () async => data)]);
  }

  Future<void> _openFile(TFile f) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (f.isImage) {
        await Navigator.of(context).push(AppPageRoute(builder: (_) => _ImageView(api: api, file: f)));
        return;
      }
      final p = await api.download(f.id, f.name);
      await launchUrl(Uri.file(p));
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  void _removeFile(TFile f) {
    _n.files = _n.files.where((x) => x.id != f.id).toList();
    _flushContent({'files': _n.files});
  }

  // ------------------------------------------------------------ thao tác
  void _togglePin() => setState(() => _set({'pinned': !_n.pinned}..addAll(_n.pinned ? {} : {'archived': false})));

  void _archive() {
    _set({'archived': !_n.archived});
    Navigator.of(context).maybePop();
  }

  void _trash() {
    _save.flush();
    if (store.notes.containsKey(_n.id)) store.put(_n, {'trashed': true});
    Navigator.of(context).maybePop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(tr('Đã chuyển ghi chú vào thùng rác'))));
  }

  Future<void> _reminder() async {
    final r = await pickReminder(context, _n.reminder);
    if (r == null) return;
    setState(() => _n.reminder = r.value);
    _flushContent({'reminder': r.value?.toJson()});
  }

  Future<void> _labels() async {
    final l = await pickLabels(context, store, _n.labels);
    if (l == null) return;
    setState(() => _n.labels = l);
    _flushContent({'labels': l});
  }

  Future<void> _share() async {
    _flushContent({});
    if (!store.notes.containsKey(_n.id)) return;
    await shareNote(context, store, store.notes[_n.id]!);
    if (mounted) setState(() => _n = _merge(store.notes[_n.id] ?? _n));
  }

  void _look() => pickLook(context, _n, (c, bg) {
        setState(() {
          _n.color = c;
          _n.bg = bg;
        });
        _flushContent({'color': c, 'bg': bg});
      });

  void _switchMode() {
    setState(() {
      if (_n.kind == 'list') {
        _n.kind = 'note';
        _n.blocks = toNoteMode(_n.blocks);
      } else {
        _n.kind = 'list';
        _n.blocks = toListMode(_n.blocks);
        if (_n.blocks.isEmpty) _n.blocks = [TBlock(t: 'check')];
      }
      _rev++;
    });
    _dirty.addAll(['kind', 'blocks']);
    _content();
  }

  void _copy() {
    _flushContent({});
    if (!store.notes.containsKey(_n.id)) return;
    store.copy(store.notes[_n.id]!);
    Navigator.of(context).maybePop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(tr('Đã tạo bản sao'))));
  }

  Future<void> _link() async {
    final c = _ed.focused;
    if (c == null) return;
    final ctl = TextEditingController(text: c.current.a ?? 'https://');
    final url = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Chèn link')),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'https://…')),
        actions: [
          if (c.current.a != null) TextButton(onPressed: () => Navigator.pop(d, ''), child: Text(tr('Bỏ link'))),
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: Text(tr('Lưu'))),
        ],
      ),
    );
    ctl.dispose();
    if (url == null) return;
    c.setLink(url.isEmpty || !RegExp(r'^(https?://|mailto:|tel:)', caseSensitive: false).hasMatch(url) ? null : url);
  }

  Future<void> _colorMenu(bool highlight) async {
    final c = _ed.focused;
    if (c == null) return;
    final dark = isDark(context);
    final v = await showTodoSheet<String>(context, title: highlight ? tr('Màu tô') : tr('Màu chữ'), builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(label: Text(tr('Mặc định')), onPressed: () => Navigator.pop(context, '')),
            for (final e in kTextColors.entries)
              InkWell(
                onTap: () => Navigator.pop(context, e.key),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: highlight ? (dark ? e.value.$4 : e.value.$3) : (dark ? e.value.$2 : e.value.$1),
                  child: Text('A', style: TextStyle(color: highlight ? null : Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ));
    if (v == null) return;
    highlight ? c.setHighlight(v.isEmpty ? null : v) : c.setColor(v.isEmpty ? null : v);
  }

  // ------------------------------------------------------------ giao diện
  Widget _images(Color fg) {
    final imgs = _n.files.where((f) => f.isImage).toList();
    if (imgs.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (c, box) {
      final cols = imgs.length == 1 ? 1 : imgs.length == 2 || imgs.length == 4 ? 2 : 3;
      final w = (box.maxWidth - (cols - 1) * 3) / cols;
      return Wrap(spacing: 3, runSpacing: 3, children: [
        for (final f in imgs)
          SizedBox(
            width: w,
            height: imgs.length == 1 ? null : w,
            child: Stack(fit: imgs.length == 1 ? StackFit.loose : StackFit.expand, children: [
              GestureDetector(onTap: () => _openFile(f), child: TodoImage(api: api, file: f, fit: imgs.length == 1 ? BoxFit.fitWidth : BoxFit.cover)),
              if (!_ro)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(customBorder: const CircleBorder(), onTap: () => _removeFile(f), child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.white))),
                  ),
                ),
            ]),
          ),
      ]);
    });
  }

  Widget _attachments(Color fg) {
    final files = _n.files.where((f) => !f.isImage).toList();
    if (files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in files)
          InputChip(
            avatar: Icon(fileIcon(f), size: 18),
            label: Text('${f.name} · ${fileSize(f.size)}', overflow: TextOverflow.ellipsis),
            onPressed: () => _openFile(f),
            onDeleted: _ro ? null : () => _removeFile(f),
            backgroundColor: fg.withValues(alpha: .07),
            side: BorderSide.none,
          ),
      ]),
    );
  }

  Widget _chips(Color fg) {
    final sub = fg.withValues(alpha: .7);
    final chip = (fg.withValues(alpha: .08));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (_n.reminder != null)
          InputChip(
            avatar: Icon(_n.reminder!.repeat != null ? Icons.repeat_rounded : Icons.alarm_rounded, size: 16, color: sub),
            label: Text([reminderLabel(_n.reminder!), if (_n.reminder!.repeat != null) repeatName(_n.reminder!.repeat)].join(' · '),
                style: TextStyle(color: fg, decoration: _n.reminder!.done ? TextDecoration.lineThrough : null)),
            onPressed: _reminder,
            onDeleted: () {
              setState(() => _n.reminder = null);
              _flushContent({'reminder': null});
            },
            backgroundColor: chip,
            side: BorderSide.none,
          ),
        for (final l in _n.labels)
          if (store.labelName(l).isNotEmpty)
            InputChip(label: Text(store.labelName(l), style: TextStyle(color: fg)), onPressed: _labels, backgroundColor: chip, side: BorderSide.none, onDeleted: () {
              setState(() => _n.labels = _n.labels.where((x) => x != l).toList());
              _flushContent({'labels': _n.labels});
            }),
        if (_n.others.isNotEmpty)
          InkWell(
            onTap: _share,
            borderRadius: BorderRadius.circular(20),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final m in [if (!_n.isOwner && _n.owner != null) _n.owner!, ..._n.others].take(6))
                Padding(padding: const EdgeInsets.only(right: 2), child: Tooltip(message: '${m.name} · ${m.role == 'owner' ? tr('Chủ sở hữu') : m.role == 'viewer' ? tr('Chỉ xem') : tr('Có thể sửa')}', child: memberAvatar(m.name, 14))),
            ]),
          ),
      ]),
    );
  }

  Widget _formatBar(Color fg) {
    final c = _ed.focused, cur = c?.current ?? TFmt.plain, t = _ed.focusedBlock?.t;
    Widget b(IconData i, String tip, bool on, VoidCallback? f) => IconButton(
          tooltip: tip,
          isSelected: on,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(backgroundColor: on ? fg.withValues(alpha: .14) : null),
          icon: Icon(i, size: 21, color: fg),
          onPressed: c == null ? null : f,
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(children: [
        b(Icons.format_bold_rounded, tr('Đậm'), cur.b, () => c!.toggle('b')),
        b(Icons.format_italic_rounded, tr('Nghiêng'), cur.i, () => c!.toggle('i')),
        b(Icons.format_underline_rounded, tr('Gạch dưới'), cur.u, () => c!.toggle('u')),
        b(Icons.format_strikethrough_rounded, tr('Gạch ngang'), cur.s, () => c!.toggle('s')),
        b(Icons.format_color_text_rounded, tr('Màu chữ'), cur.fg != null, () => _colorMenu(false)),
        b(Icons.format_color_fill_rounded, tr('Màu tô'), cur.hl != null, () => _colorMenu(true)),
        b(Icons.link_rounded, tr('Link'), cur.a != null, _link),
        b(Icons.code_rounded, tr('Mã'), cur.c, () => c!.toggle('c')),
        const SizedBox(height: 24, child: VerticalDivider()),
        b(Icons.title_rounded, tr('Tiêu đề lớn'), t == 'h1', () => _ed.setType('h1')),
        b(Icons.text_fields_rounded, tr('Tiêu đề nhỏ'), t == 'h2', () => _ed.setType('h2')),
        b(Icons.format_list_bulleted_rounded, tr('Gạch đầu dòng'), t == 'ul', () => _ed.setType('ul')),
        b(Icons.format_list_numbered_rounded, tr('Đánh số'), t == 'ol', () => _ed.setType('ol')),
        b(Icons.check_box_outlined, tr('Ô tick'), t == 'check', () => _ed.setType('check')),
        b(Icons.format_quote_rounded, tr('Trích dẫn'), t == 'quote', () => _ed.setType('quote')),
        b(Icons.format_indent_decrease_rounded, tr('Giảm thụt lề'), false, () => _ed.indent(-1)),
        b(Icons.format_indent_increase_rounded, tr('Tăng thụt lề'), false, () => _ed.indent(1)),
        b(Icons.horizontal_rule_rounded, tr('Đường kẻ'), false, _ed.insertDivider),
        b(Icons.format_clear_rounded, tr('Xoá định dạng'), false, () => c!.clearFormat()),
      ]),
    );
  }

  Widget _bottomBar(Color fg) {
    final edited = DateTime.fromMillisecondsSinceEpoch(_n.updatedAt);
    final now = DateTime.now();
    final when = DateUtils.isSameDay(edited, now) ? DateFormat('HH:mm').format(edited) : DateFormat('dd/MM HH:mm').format(edited);
    Widget b(IconData i, String tip, VoidCallback? f, {bool on = false}) => IconButton(
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(backgroundColor: on ? fg.withValues(alpha: .14) : null),
          icon: Icon(i, size: 22, color: fg.withValues(alpha: f == null ? .35 : .85)),
          onPressed: f,
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_format && !_ro) _formatBar(fg),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(children: [
          if (!_ro) ...[
            b(Icons.text_format_rounded, tr('Định dạng'), () => setState(() => _format = !_format), on: _format),
            PopupMenuButton<String>(
              tooltip: tr('Thêm'),
              icon: Icon(Icons.add_box_outlined, color: fg.withValues(alpha: .85)),
              onSelected: (v) => switch (v) {
                'image' => _attach(images: true),
                'file' => _attach(images: false),
                'check' => _ed.addBlock(t: 'check'),
                'hr' => _ed.insertDivider(),
                'paste' => _pasteMedia().then((ok) {
                    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Bộ nhớ tạm không có ảnh hoặc tệp'))));
                  }),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'image', child: ListTile(leading: const Icon(Icons.image_outlined), title: Text(tr('Thêm ảnh')))),
                PopupMenuItem(value: 'file', child: ListTile(leading: const Icon(Icons.attach_file_rounded), title: Text(tr('Đính kèm tệp')))),
                PopupMenuItem(value: 'paste', child: ListTile(leading: const Icon(Icons.content_paste_rounded), title: Text(tr('Dán ảnh / tệp')))),
                if (_n.kind != 'list') PopupMenuItem(value: 'check', child: ListTile(leading: const Icon(Icons.check_box_outlined), title: Text(tr('Ô tick')))),
                PopupMenuItem(value: 'hr', child: ListTile(leading: const Icon(Icons.horizontal_rule_rounded), title: Text(tr('Đường kẻ')))),
              ],
            ),
            b(Icons.palette_outlined, tr('Màu và hình nền'), _look),
          ],
          b(Icons.add_alert_outlined, tr('Nhắc tôi'), _n.trashed ? null : _reminder, on: _n.reminder != null),
          b(Icons.person_add_alt_outlined, tr('Cộng tác viên'), _n.trashed ? null : _share, on: _n.others.isNotEmpty),
          if (_uploading) const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          const Spacer(),
          if (MediaQuery.sizeOf(context).width > 420)
            Text(tr('Đã sửa {0}', [when]), style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .6))),
          PopupMenuButton<String>(
            tooltip: tr('Thêm thao tác'),
            icon: Icon(Icons.more_vert_rounded, color: fg.withValues(alpha: .85)),
            onSelected: (v) => switch (v) {
              'labels' => _labels(),
              'mode' => _switchMode(),
              'copy' => _copy(),
              'trash' => _trash(),
              'restore' => () {
                  store.put(_n, {'trashed': false});
                  Navigator.of(context).maybePop();
                }(),
              'delete' => () {
                  store.remove(_n);
                  Navigator.of(context).maybePop();
                }(),
              _ => null,
            },
            itemBuilder: (_) => [
              if (_n.trashed) ...[
                PopupMenuItem(value: 'restore', child: Text(tr('Khôi phục'))),
                if (_n.isOwner) PopupMenuItem(value: 'delete', child: Text(tr('Xoá vĩnh viễn'))),
              ] else ...[
                PopupMenuItem(value: 'labels', child: Text(tr('Gắn nhãn'))),
                if (!_ro) PopupMenuItem(value: 'mode', child: Text(_n.kind == 'list' ? tr('Chuyển thành văn bản') : tr('Chuyển thành danh sách việc'))),
                PopupMenuItem(value: 'copy', child: Text(tr('Tạo bản sao'))),
                PopupMenuItem(value: 'trash', child: Text(_n.isOwner ? tr('Xoá ghi chú') : tr('Xoá khỏi danh sách của tôi'))),
              ],
            ],
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final fg = dark ? Colors.white : const Color(0xFF202124);
    final inDialog = isDesktop && MediaQuery.sizeOf(context).width >= 760;
    final top = Row(children: [
      if (!inDialog) IconButton(tooltip: tr('Quay lại'), icon: Icon(Icons.arrow_back_rounded, color: fg), onPressed: () => Navigator.of(context).maybePop()),
      const Spacer(),
      if (!_n.trashed) ...[
        IconButton(tooltip: _n.pinned ? tr('Bỏ ghim') : tr('Ghim'), icon: Icon(_n.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, color: fg), onPressed: _togglePin),
        IconButton(tooltip: _n.archived ? tr('Bỏ lưu trữ') : tr('Lưu trữ'), icon: Icon(_n.archived ? Icons.unarchive_outlined : Icons.archive_outlined, color: fg), onPressed: _archive),
      ],
      if (inDialog) IconButton(tooltip: tr('Đóng'), icon: Icon(Icons.close_rounded, color: fg), onPressed: () => Navigator.of(context).maybePop()),
    ]);
    final body = ListView(padding: EdgeInsets.zero, children: [
      _images(fg),
      if (_ro)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: fg.withValues(alpha: .07), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(_n.trashed ? Icons.delete_outline_rounded : Icons.visibility_outlined, size: 18, color: fg.withValues(alpha: .7)),
            const SizedBox(width: 8),
            Expanded(child: Text(_n.trashed ? tr('Ghi chú trong thùng rác không sửa được') : tr('Bạn chỉ được xem ghi chú này'), style: TextStyle(color: fg.withValues(alpha: .8)))),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: TextField(
          controller: _title,
          readOnly: _ro,
          maxLines: null,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: fg),
          decoration: InputDecoration(hintText: tr('Tiêu đề'), border: InputBorder.none, isDense: true, hintStyle: TextStyle(color: fg.withValues(alpha: .45))),
          onChanged: (v) {
            _n.title = v;
            _dirty.add('title');
            _content();
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
        child: BlockEditor(
          key: ValueKey('ed-${_n.kind}'),
          blocks: _n.blocks,
          revision: _rev,
          listMode: _n.kind == 'list',
          readOnly: _ro,
          controller: _ed,
          autofocus: store.notes[_n.id] == null && !widget.pickImage,
          style: TextStyle(fontSize: 16, height: 1.45, color: fg),
          onPasteMedia: _ro ? null : _pasteMedia,
          onInsertBytes: _ro ? null : _insertBytes,
          onChanged: (bl) {
            _n.blocks = bl;
            _dirty.add('blocks');
            _content();
          },
        ),
      ),
      _attachments(fg),
      _chips(fg),
      const SizedBox(height: 12),
    ]);
    final content = NoteBackground(
      color: _n.color,
      bg: _n.bg,
      child: SafeArea(
        child: Column(children: [
          top,
          Expanded(child: body),
          _bottomBar(fg),
        ]),
      ),
    );
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save.flush(),
      child: inDialog ? Material(color: Colors.transparent, child: content) : Scaffold(backgroundColor: noteColor(_n.color, dark), body: content),
    );
  }
}

IconData fileIcon(TFile f) => f.isImage
    ? Icons.image_outlined
    : f.mime == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : f.mime.startsWith('video/')
            ? Icons.movie_outlined
            : f.mime.startsWith('audio/')
                ? Icons.audiotrack_outlined
                : f.mime.contains('sheet') || f.mime.contains('excel') || f.mime == 'text/csv'
                    ? Icons.table_chart_outlined
                    : f.mime.contains('word') || f.mime.startsWith('text/')
                        ? Icons.description_outlined
                        : Icons.insert_drive_file_outlined;

String fileSize(int b) => b < 1024 ? '$b B' : b < 1048576 ? '${(b / 1024).toStringAsFixed(0)} KB' : '${(b / 1048576).toStringAsFixed(1)} MB';

Widget memberAvatar(String name, double r) => CircleAvatar(
      radius: r,
      backgroundColor: Colors.primaries[name.hashCode.abs() % Colors.primaries.length].shade400,
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: r * .95)),
    );

/// Ảnh trong ghi chú (tải qua API có vé, giữ trong bộ nhớ).
class TodoImage extends StatelessWidget {
  const TodoImage({super.key, required this.api, required this.file, this.fit = BoxFit.cover});
  final TodoApi api;
  final TFile file;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: api.bytes(file.id),
        builder: (c, s) => s.hasData
            ? Image.memory(s.data!, fit: fit, width: double.infinity, gaplessPlayback: true, errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)))
            : Container(height: 120, color: Colors.black12, alignment: Alignment.center, child: s.hasError ? const Icon(Icons.broken_image_outlined) : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
}

class _ImageView extends StatelessWidget {
  const _ImageView({required this.api, required this.file});
  final TodoApi api;
  final TFile file;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(file.name, style: const TextStyle(fontSize: 15))),
        body: InteractiveViewer(maxScale: 6, child: Center(child: TodoImage(api: api, file: file, fit: BoxFit.contain))),
      );
}

// Dùng ở thẻ trên lưới: chữ của khối (không sửa).
Widget blockPreview(List<TBlock> blocks, int i, TextStyle style, bool dark, {void Function(TBlock, bool)? onTick}) {
  final b = blocks[i];
  if (b.t == 'hr') return Divider(height: 14, color: style.color?.withValues(alpha: .3));
  final st = blockStyle(b.t, style).copyWith(decoration: b.done ? TextDecoration.lineThrough : null, color: b.done ? style.color?.withValues(alpha: .55) : null);
  final lead = b.t == 'check'
      ? SizedBox(
          width: 24,
          height: 22,
          child: Checkbox(
            value: b.done,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: style.color!.withValues(alpha: .55), width: 1.4),
            onChanged: onTick == null ? null : (v) => onTick(b, v ?? false),
          ),
        )
      : bulletOf(blocks, i, st);
  return Padding(
    padding: EdgeInsets.only(left: 16.0 * b.ind, top: 1, bottom: 1),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (lead != null) Padding(padding: const EdgeInsets.only(right: 6), child: lead),
      Expanded(child: Text.rich(runsSpan(b.r, st, dark, links: false), maxLines: b.t == 'p' ? 6 : 3, overflow: TextOverflow.ellipsis)),
    ]),
  );
}
