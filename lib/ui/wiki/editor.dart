// Wiki: sửa trang Markdown. Thanh công cụ chèn cú pháp (tiêu đề, đậm, danh sách, ô tick, trích dẫn, bảng, link, link tới
// trang khác, ảnh, tệp); máy tính có Viết / Chia đôi / Xem trước, điện thoại có Viết / Xem trước. Bản nháp lưu trên máy
// liên tục; lưu lên máy chủ thì tạo một phiên bản kèm ghi chú. Có người lưu trước thì hỏi cách xử lý.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/i18n.dart';
import '../common.dart' show pickFilesOrReport;
import '../theme.dart';
import 'api.dart';
import 'md_view.dart';
import 'model.dart';
import 'store.dart';

class WikiEditor extends StatefulWidget {
  const WikiEditor({super.key, required this.store, required this.page, this.wide = false, this.onDone});
  final WikiStore store;
  final WPage page;
  final bool wide;
  /// Đóng trình sửa: trang đã lưu (null = huỷ). Không có thì pop trang.
  final void Function(WPage? saved)? onDone;
  @override
  State<WikiEditor> createState() => _WikiEditorState();
}

class _WikiEditorState extends State<WikiEditor> {
  late final TextEditingController _title, _body, _note;
  final _bodyFocus = FocusNode();
  late String _mode = widget.wide ? 'split' : 'write';
  late int _base = widget.page.version;
  final List<WFile> _files = [];
  bool _saving = false, _draftSaved = false, _restored = false;
  Timer? _draftTimer;

  WikiStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final d = store.drafts[widget.page.id];
    _restored = d != null && (d['body'] != widget.page.body || d['title'] != widget.page.title);
    _title = TextEditingController(text: _restored ? '${d!['title']}' : widget.page.title);
    _body = TextEditingController(text: _restored ? '${d!['body']}' : widget.page.body);
    _note = TextEditingController(text: _restored ? '${d!['note'] ?? ''}' : '');
    if (_restored) _base = (d!['base'] as num?)?.toInt() ?? _base;
    _files.addAll(widget.page.files);
    for (final c in [_title, _body, _note]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _title.dispose();
    _body.dispose();
    _note.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  bool get _dirty => _title.text != widget.page.title || _body.text != widget.page.body;

  void _changed() {
    setState(() => _draftSaved = false);
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      if (_dirty) {
        store.saveDraft(widget.page.id, {'title': _title.text, 'body': _body.text, 'note': _note.text, 'base': _base});
      } else {
        store.dropDraft(widget.page.id);
      }
      setState(() => _draftSaved = _dirty);
    });
  }

  // ------------------------------------------------------------ chèn cú pháp
  TextSelection get _sel {
    final s = _body.selection;
    return s.isValid ? s : TextSelection.collapsed(offset: _body.text.length);
  }

  void _replace(int start, int end, String text, {int? selStart, int? selEnd}) {
    final t = _body.text;
    _body.value = TextEditingValue(
      text: t.replaceRange(start, end, text),
      selection: TextSelection(baseOffset: selStart ?? start + text.length, extentOffset: selEnd ?? selStart ?? start + text.length),
    );
    _bodyFocus.requestFocus();
  }

  /// Bọc phần đang chọn bằng [mark] (đậm **, nghiêng *, gạch ~~, mã `).
  void _wrap(String mark, String placeholder) {
    final s = _sel, t = _body.text;
    final inner = s.isCollapsed ? placeholder : t.substring(s.start, s.end);
    _replace(s.start, s.end, '$mark$inner$mark', selStart: s.start + mark.length, selEnd: s.start + mark.length + inner.length);
  }

  /// Đặt [prefix] ở đầu các dòng đang chọn (tiêu đề, danh sách, trích dẫn). Bấm lại thì bỏ.
  void _prefix(String prefix) {
    final s = _sel, t = _body.text;
    final start = s.start == 0 ? 0 : t.lastIndexOf('\n', s.start - 1) + 1;
    var end = t.indexOf('\n', s.end);
    if (end < 0) end = t.length;
    final lines = t.substring(start, end).split('\n');
    final strip = RegExp(r'^(#{1,6} |> |- \[[ xX]\] |[-*] |\d+\. )');
    bool has(String l) => prefix == '1. ' ? RegExp(r'^\d+\. ').hasMatch(l) : l.startsWith(prefix);
    final off = lines.every(has);
    var n = 0;
    final out = [for (final l in lines) off ? l.replaceFirst(strip, '') : '${prefix == '1. ' ? '${++n}. ' : prefix}${l.replaceFirst(strip, '')}'].join('\n');
    _replace(start, end, out);
  }

  void _insertBlock(String text) {
    final s = _sel, t = _body.text;
    final before = s.start > 0 && t[s.start - 1] != '\n' ? '\n\n' : (s.start > 1 && t[s.start - 2] != '\n' ? '\n' : '');
    _replace(s.start, s.end, '$before$text\n');
  }

  Future<void> _link() async {
    final s = _sel, t = _body.text;
    final text = TextEditingController(text: s.isCollapsed ? '' : t.substring(s.start, s.end)), url = TextEditingController(text: 'https://');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Chèn link')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: text, decoration: InputDecoration(labelText: tr('Chữ hiển thị'))),
          TextField(controller: url, autofocus: true, decoration: InputDecoration(labelText: tr('Địa chỉ')), onSubmitted: (_) => Navigator.pop(d, true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Chèn'))),
        ],
      ),
    );
    if (ok != true || url.text.trim().isEmpty) return;
    final label = text.text.trim().isEmpty ? url.text.trim() : text.text.trim();
    _replace(s.start, s.end, '[$label](${url.text.trim()})');
  }

  Future<void> _pageLink() async {
    final s = _sel;
    final p = await pickWikiPage(context, store);
    if (p == null) return;
    _replace(s.start, s.end, '[${p.title}](wiki:${p.id})');
  }

  Future<void> _attach({required bool images}) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await pickFilesOrReport(context, type: images ? FileType.image : FileType.any);
    for (final f in picked) {
      if (f.path == null) continue;
      try {
        final up = await store.upload(f.name, await File(f.path!).readAsBytes());
        setState(() => _files.add(up));
        _insertBlock('${up.isImage ? '!' : ''}[${up.name.replaceAll(RegExp(r'[\[\]]'), '')}](file:${up.id})');
      } catch (e) {
        messenger.showSnackBar(toast(Text(tr('Không tải lên được {0}: {1}', [f.name, '$e']))));
      }
    }
  }

  // ------------------------------------------------------------ lưu
  Future<void> _save({bool force = false}) async {
    if (_saving) return;
    final title = _title.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (title.isEmpty) {
      messenger.showSnackBar(toast(Text(tr('Trang cần tiêu đề'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final p = await store.savePage(widget.page.id, title: title, body: _body.text, base: _base, note: _note.text.trim(), force: force);
      if (!mounted) return;
      _close(p);
    } on WikiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.status == 409 && e.body['current'] is Map) {
        await _conflict(WPage(Map<String, dynamic>.from(e.body['current'] as Map)));
      } else {
        messenger.showSnackBar(toast(Text(tr('Không lưu được: {0}', ['$e']))));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(toast(Text(tr('Không lưu được (bản nháp vẫn giữ trên máy): {0}', ['$e']))));
    }
  }

  /// Có người lưu bản mới hơn trong lúc mình sửa: xem chỗ khác, ghi đè, hoặc lưu bản của mình thành trang mới.
  Future<void> _conflict(WPage current) async {
    final pal = Pal.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Có người vừa lưu bản {0}', ['${current.version}'])),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('{0} đã lưu trang này {1}. Chỗ khác giữa bản đó và bản của bạn:', [current.updatedByName, agoLabel(current.updatedAt)]), style: TextStyle(color: pal.sub)),
            const SizedBox(height: 10),
            ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: SingleChildScrollView(child: DiffView(a: current.body, b: _body.text))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Tiếp tục sửa'))),
          TextButton(onPressed: () => Navigator.pop(d, 'copy'), child: Text(tr('Lưu thành trang mới'))),
          FilledButton(onPressed: () => Navigator.pop(d, 'force'), child: Text(tr('Ghi đè bằng bản của tôi'))),
        ],
      ),
    );
    if (choice == 'force') {
      await _save(force: true);
    } else if (choice == 'copy') {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        final id = WikiStore.newId();
        final p = await store.savePage(id, folder: widget.page.folder, title: tr('{0} (bản của tôi)', [_title.text.trim()]), body: _body.text, note: _note.text.trim());
        store.dropDraft(widget.page.id);
        if (mounted) _close(p);
      } catch (e) {
        messenger.showSnackBar(toast(Text(tr('Không lưu được: {0}', ['$e']))));
      }
    }
  }

  void _close(WPage? saved) {
    if (widget.onDone != null) {
      widget.onDone!(saved);
    } else {
      Navigator.of(context).pop(saved);
    }
  }

  Future<void> _cancel() async {
    if (_dirty) {
      final drop = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(tr('Bỏ các thay đổi?')),
          content: Text(tr('Nội dung bạn vừa sửa chưa được lưu thành phiên bản mới.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Tiếp tục sửa'))),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)), onPressed: () => Navigator.pop(d, true), child: Text(tr('Bỏ thay đổi'))),
          ],
        ),
      );
      if (drop != true) return;
    }
    store.dropDraft(widget.page.id);
    _close(null);
  }

  // ------------------------------------------------------------ giao diện
  Widget _tool(IconData icon, String tip, VoidCallback onTap) => IconButton(tooltip: tip, icon: Icon(icon, size: 21), visualDensity: VisualDensity.compact, onPressed: onTap);

  List<Widget> _tools({required bool compact}) => [
        if (compact) _tool(Icons.title_rounded, tr('Tiêu đề'), () => _prefix('## ')) else ...[
          _tool(Icons.looks_one_outlined, tr('Tiêu đề 1'), () => _prefix('# ')),
          _tool(Icons.looks_two_outlined, tr('Tiêu đề 2'), () => _prefix('## ')),
          _tool(Icons.looks_3_outlined, tr('Tiêu đề 3'), () => _prefix('### ')),
          const _Sep(),
        ],
        _tool(Icons.format_bold_rounded, tr('Đậm'), () => _wrap('**', tr('chữ đậm'))),
        _tool(Icons.format_italic_rounded, tr('Nghiêng'), () => _wrap('*', tr('chữ nghiêng'))),
        if (!compact) ...[
          _tool(Icons.strikethrough_s_rounded, tr('Gạch ngang'), () => _wrap('~~', tr('chữ gạch'))),
          _tool(Icons.code_rounded, tr('Mã'), () => _wrap('`', 'code')),
          const _Sep(),
        ],
        _tool(Icons.format_list_bulleted_rounded, tr('Danh sách'), () => _prefix('- ')),
        _tool(Icons.format_list_numbered_rounded, tr('Danh sách số'), () => _prefix('1. ')),
        _tool(Icons.checklist_rounded, tr('Ô tick'), () => _prefix('- [ ] ')),
        if (!compact) ...[
          _tool(Icons.format_quote_rounded, tr('Trích dẫn'), () => _prefix('> ')),
          _tool(Icons.table_chart_outlined, tr('Bảng'), () => _insertBlock('| Cột 1 | Cột 2 |\n|---|---|\n|  |  |')),
          _tool(Icons.horizontal_rule_rounded, tr('Đường kẻ'), () => _insertBlock('---')),
          const _Sep(),
        ],
        _tool(Icons.link_rounded, tr('Link'), _link),
        _tool(Icons.article_outlined, tr('Link tới trang wiki'), _pageLink),
        _tool(Icons.image_outlined, tr('Ảnh'), () => _attach(images: true)),
        _tool(Icons.attach_file_rounded, tr('Tệp đính kèm'), () => _attach(images: false)),
      ];

  Widget _source(Pal pal) => TextField(
        key: const ValueKey('wiki-editor-body'),
        controller: _body,
        focusNode: _bodyFocus,
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(fontSize: 15, height: 1.6, color: pal.text),
        decoration: InputDecoration(border: InputBorder.none, contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 18), hintText: tr('Viết nội dung bằng Markdown…')),
      );

  Widget _preview(Pal pal) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_title.text, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: pal.text, height: 1.25)),
          const SizedBox(height: 14),
          WikiMarkdown(text: _body.text, api: store.api, files: _files),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final wide = widget.wide;
    final modes = wide ? {'write': tr('Viết'), 'split': tr('Chia đôi'), 'preview': tr('Xem trước')} : {'write': tr('Viết'), 'preview': tr('Xem trước')};
    final seg = SegmentedButton<String>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [for (final e in modes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
    final titleField = TextField(
      key: const ValueKey('wiki-editor-title'),
      controller: _title,
      style: TextStyle(fontSize: wide ? 22 : 19, fontWeight: FontWeight.w700, color: pal.text),
      decoration: InputDecoration(border: InputBorder.none, hintText: tr('Tiêu đề trang'), contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 4)),
    );
    final body = switch (_mode) {
      'preview' => _preview(pal),
      'split' => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _source(pal)),
          VerticalDivider(width: 1, color: pal.divider),
          Expanded(child: _preview(pal)),
        ]),
      _ => _source(pal),
    };
    final status = _restored && !_draftSaved && !_dirty
        ? ''
        : _draftSaved
            ? tr('Đã lưu nháp trên máy')
            : (_restored ? tr('Đã mở lại bản nháp chưa lưu') : '');
    final save = FilledButton.icon(
      key: const ValueKey('wiki-editor-save'),
      onPressed: _saving ? null : _save,
      icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded, size: 18),
      label: Text(wide ? tr('Lưu bản {0}', ['${widget.page.latest + 1}']) : tr('Lưu')),
    );
    final note = TextField(
      key: const ValueKey('wiki-editor-note'),
      controller: _note,
      style: TextStyle(fontSize: 14, color: pal.text),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.edit_note_rounded, color: pal.sub),
        hintText: tr('Ghi chú phiên bản (không bắt buộc)'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: pal.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: pal.divider)),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _wrap('**', tr('chữ đậm')),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _wrap('*', tr('chữ nghiêng')),
      },
      child: Material(
        color: pal.bg,
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Thanh trên.
            SizedBox(
              height: wide ? 60 : 54,
              child: Row(children: [
                const SizedBox(width: 6),
                IconButton(tooltip: tr('Huỷ'), icon: const Icon(Icons.close_rounded), onPressed: _cancel),
                if (wide)
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: store.pathOf(widget.page.folder).map((f) => f.name).join(' › '), style: TextStyle(color: pal.sub)),
                        TextSpan(text: '   ${tr('Đang sửa · bản {0}', ['${widget.page.latest}'])}', style: TextStyle(color: pal.sub, fontSize: 12.5)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: seg))),
                if (wide) seg,
                if (!wide) ...[save, const SizedBox(width: 10)] else const SizedBox(width: 20),
              ]),
            ),
            Divider(height: 1, color: pal.divider),
            if (wide)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(children: [
                  ..._tools(compact: false),
                  const Spacer(),
                  Text(status, style: TextStyle(color: pal.sub, fontSize: 12.5)),
                  const SizedBox(width: 8),
                ]),
              ),
            if (wide) Divider(height: 1, color: pal.divider),
            if (_mode != 'preview') titleField,
            Expanded(child: body),
            Divider(height: 1, color: pal.divider),
            if (wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Row(children: [
                  Expanded(child: note),
                  const SizedBox(width: 10),
                  OutlinedButton(onPressed: _cancel, child: Text(tr('Huỷ'))),
                  const SizedBox(width: 8),
                  save,
                ]),
              )
            else ...[
              Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 2), child: note),
              if (status.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 0), child: Text(status, style: TextStyle(color: pal.sub, fontSize: 12))),
              // Điện thoại: thanh công cụ ngay trên bàn phím.
              SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4), child: Row(children: _tools(compact: true))),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 6), color: Pal.of(context).divider);
}

/// Chỗ khác giữa hai bản theo dòng: dòng bỏ gạch đỏ, dòng thêm tô xanh, dòng giữ nguyên mờ (rút gọn đoạn dài không đổi).
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.a, required this.b, this.context = 2});
  final String a, b;
  final int context;
  @override
  Widget build(BuildContext ctx) {
    final pal = Pal.of(ctx);
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    final d = lineDiff(a, b);
    final keep = List.filled(d.length, false);
    for (var i = 0; i < d.length; i++) {
      if (d[i].$1 != ' ') {
        for (var j = (i - context).clamp(0, d.length); j <= (i + context).clamp(0, d.length - 1); j++) {
          keep[j] = true;
        }
      }
    }
    if (!d.any((x) => x.$1 != ' ')) return Text(tr('Hai bản giống nhau.'), style: TextStyle(color: pal.sub));
    final rows = <Widget>[];
    var skipped = false;
    for (var i = 0; i < d.length; i++) {
      if (!keep[i]) {
        if (!skipped) rows.add(Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('⋯', style: TextStyle(color: pal.sub))));
        skipped = true;
        continue;
      }
      skipped = false;
      final (k, l) = d[i];
      final add = k == '+', del = k == '-';
      rows.add(Container(
        width: double.infinity,
        color: add ? const Color(0xFF30A46C).withValues(alpha: .16) : del ? const Color(0xFFE5484D).withValues(alpha: .13) : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          '${add ? '+ ' : del ? '− ' : '   '}$l',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: add ? (dark ? const Color(0xFF5BD49A) : const Color(0xFF1F8A55)) : del ? (dark ? const Color(0xFFFF8A8E) : const Color(0xFFC2353A)) : pal.sub,
            decoration: del ? TextDecoration.lineThrough : null,
          ),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// Chọn một trang wiki (để chèn link): tìm theo tiêu đề trong các trang xem được.
Future<WPageRef?> pickWikiPage(BuildContext context, WikiStore store) {
  final q = TextEditingController();
  return showDialog<WPageRef>(
    context: context,
    builder: (d) => StatefulBuilder(builder: (c, set) {
      final pal = Pal.of(c);
      final f = viFold(q.text.trim());
      final list = store.recent.where((p) => f.isEmpty || viFold(p.title).contains(f)).take(50).toList();
      return AlertDialog(
        title: Text(tr('Link tới trang wiki')),
        content: SizedBox(
          width: 480,
          height: 420,
          child: Column(children: [
            TextField(controller: q, autofocus: true, decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm trang')), onChanged: (_) => set(() {})),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                for (final p in list)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.description_outlined, color: pal.sub),
                    title: Text(p.title),
                    subtitle: Text(store.pathOf(p.folder).map((x) => x.name).join(' › '), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(d, p),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Huỷ')))],
      );
    }),
  );
}
