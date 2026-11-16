// TeamWork: soạn / xem chữ có định dạng cho mô tả và bình luận. Dùng lại bộ soạn theo khối của Công việc (BlockEditor +
// RichController), thêm @nhắc người / agent và #nhắc việc: gõ @ hoặc # (hoặc bấm nút trên thanh công cụ) để chọn; chỗ nhắc
// lưu thành link nội bộ "tw:<loại>:<id>" (máy chủ lưu ở thuộc tính m của đoạn chữ). Phần thêm này nằm riêng ở đây, không
// đổi hành vi của Công việc / Thư.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../todo/block_editor.dart';
import '../todo/model.dart';
import '../todo/rich.dart';
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'store.dart';

/// Chọn một người / agent để @nhắc.
Future<TwAssignee?> pickMention(BuildContext context, TwStore store) => twSheet<TwAssignee>(context, builder: (c) => _MentionPicker(store: store));

class _MentionPicker extends StatefulWidget {
  const _MentionPicker({required this.store});
  final TwStore store;
  @override
  State<_MentionPicker> createState() => _MentionPickerState();
}

class _MentionPickerState extends State<_MentionPicker> {
  final _q = TextEditingController();
  List<TwSubject> _people = [];
  Map<String, bool> _usable = {};
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _search('');
    _checkAgents();
  }

  /// Chỉ gợi ý agent mình được dùng (như ô Người làm).
  Future<void> _checkAgents() async {
    final l = widget.store.launcher;
    final out = <String, bool>{};
    for (final a in widget.store.agents) {
      out[a.id] = l == null ? true : await l.canUse(a.id);
    }
    if (mounted) setState(() => _usable = out);
  }

  void _search(String q) {
    setState(() {});
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 200), () async {
      try {
        final r = await widget.store.api.subjects(q);
        if (mounted) setState(() => _people = r.where((s) => s.type == 'user').toList());
      } catch (_) {}
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
    final q = _q.text.trim().toLowerCase();
    final agents = widget.store.agents.where((a) => _usable[a.id] != false && (q.isEmpty || a.label.toLowerCase().contains(q))).toList();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetTitle(context, 'Nhắc tới'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          key: const ValueKey('mention-q'),
          controller: _q,
          autofocus: true,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.alternate_email, size: 20), hintText: 'Tìm người hoặc agent…', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: _search,
        ),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 10), children: [
          if (_people.isNotEmpty) groupLabel(context, 'Người'),
          for (final p in _people)
            ListTile(
              key: ValueKey('mention-user-${p.id}'),
              dense: true,
              leading: TwAvatar(name: p.name, id: p.id, size: 26, border: false),
              title: Text(p.name),
              onTap: () => Navigator.pop(context, TwAssignee(kind: 'user', id: p.id, name: p.name)),
            ),
          if (agents.isNotEmpty) groupLabel(context, 'Agent AI'),
          for (final a in agents)
            ListTile(
              key: ValueKey('mention-agent-${a.id}'),
              dense: true,
              leading: TwAvatar(name: a.name, id: a.id, agent: true, size: 26, border: false),
              title: Text(a.label),
              subtitle: Text('Đọc việc này và làm theo bình luận', style: TextStyle(fontSize: 11.5, color: TwLook.of(context).ai)),
              onTap: () => Navigator.pop(context, TwAssignee(kind: 'agent', id: a.id, name: a.name)),
            ),
        ]),
      ),
    ]);
  }
}

/// Chèn chỗ nhắc [label] (link [link]) vào ô đang gõ, thay [replace] ký tự đứng trước con trỏ (ký tự @ / # vừa gõ).
void insertMention(RichController c, String label, String link, {int replace = 0}) {
  var sel = c.selection.isValid ? c.selection : TextSelection.collapsed(offset: c.text.length);
  if (replace > 0 && sel.isCollapsed && sel.start - replace >= 1) {
    c.selection = TextSelection(baseOffset: sel.start - replace, extentOffset: sel.start);
    sel = c.selection;
  }
  final st = sel.start;
  c.insert(label);
  c.selection = TextSelection(baseOffset: st, extentOffset: st + label.length);
  c.setLink(link);
  c.selection = TextSelection.collapsed(offset: st + label.length);
  c.insert(' ');
}

class TwRichEditor extends StatefulWidget {
  const TwRichEditor({
    super.key,
    required this.blocks,
    required this.onChanged,
    required this.store,
    this.projectId,
    this.controller,
    this.compact = false,
    this.revision = 0,
    this.autofocus = false,
    this.hint,
    this.readOnly = false,
  });
  final List<TBlock> blocks;
  final ValueChanged<List<TBlock>> onChanged;
  final TwStore store;
  final String? projectId;
  final BlockEditorController? controller;
  /// Bình luận: chữ nhỏ hơn, thanh công cụ gọn.
  final bool compact, autofocus, readOnly;
  final int revision;
  final String? hint;
  @override
  State<TwRichEditor> createState() => _TwRichEditorState();
}

class _TwRichEditorState extends State<TwRichEditor> {
  late final BlockEditorController _ed = widget.controller ?? BlockEditorController();
  String _lastText = '';
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _ed.addListener(_watch);
  }

  @override
  void dispose() {
    _ed.removeListener(_watch);
    if (widget.controller == null) _ed.dispose();
    super.dispose();
  }

  /// Vừa gõ @ hoặc # (ở đầu ô hoặc sau dấu cách): mở hộp chọn.
  void _watch() {
    final c = _ed.focused;
    if (c == null) return;
    final t = c.text;
    final grew = t.length == _lastText.length + 1;
    _lastText = t;
    if (!grew || _picking || !c.selection.isCollapsed) return;
    final i = c.selection.start - 1;
    if (i < 1 || i >= t.length) return;
    final ch = t[i];
    final before = i - 1 < 1 ? ' ' : t[i - 1];
    if ((ch == '@' || ch == '#') && (before == ' ' || before == kZw || before == '\n')) {
      scheduleMicrotask(() => ch == '@' ? _mention(replace: 1) : _task(replace: 1));
    }
  }

  /// Ô đang gõ (ô vừa gõ gần nhất); chưa gõ ô nào thì đặt con trỏ vào cuối nội dung.
  Future<RichController?> _target() async {
    if (_ed.focused == null) {
      _ed.focusEnd();
      await WidgetsBinding.instance.endOfFrame;
    }
    return _ed.focused;
  }

  Future<void> _mention({int replace = 0}) async {
    _picking = true;
    try {
      final a = await pickMention(context, widget.store);
      if (a == null || !mounted) return;
      final c = await _target();
      if (c == null) return;
      insertMention(c, '@${a.name}', mentionLink(a.kind, a.id), replace: replace);
      _lastText = c.text;
      widget.onChanged(_current());
    } finally {
      _picking = false;
    }
  }

  Future<void> _task({int replace = 0}) async {
    _picking = true;
    try {
      final t = await pickTask(context, widget.store, projectId: widget.projectId, title: 'Nhắc tới việc');
      if (t == null || !mounted) return;
      final c = await _target();
      if (c == null) return;
      insertMention(c, t.key, mentionLink('task', t.key), replace: replace);
      _lastText = c.text;
      widget.onChanged(_current());
    } finally {
      _picking = false;
    }
  }

  /// Nội dung hiện tại (sau khi chèn chỗ nhắc, BlockEditor báo onChanged qua onEdited; gọi lại cho chắc).
  List<TBlock> _current() {
    final c = _ed.focused, b = _ed.focusedBlock;
    if (c == null || b == null) return widget.blocks;
    return [for (final x in _blocksSnapshot ?? widget.blocks) x.id == b.id ? (x.clone()..r = c.runs) : x];
  }

  List<TBlock>? _blocksSnapshot;
  /// Nội dung sau khi đổi bảng Markdown thành khối bảng (thay cho widget.blocks tới khi cha đổi nội dung).
  List<TBlock>? _folded;
  int _foldRev = 0;

  @override
  void didUpdateWidget(TwRichEditor old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _folded = null;
  }

  /// Khối mã trong trình soạn: giữ nguyên các dòng (không tách thành đoạn văn), sửa trong hộp riêng.
  Widget _codeBlock(TwCodeBlock b, TwLook look) => Container(
        key: ValueKey('ed-code-${b.id}'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: look.surface, border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: Text(b.code, softWrap: false, style: TextStyle(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono'], fontSize: 13, color: look.text)),
          ),
          Row(children: [
            TextButton.icon(
              key: const ValueKey('code-edit'),
              onPressed: () async {
                final r = await editCode(context, b);
                if (r != null) _ed.replaceBlock(b.id, r);
              },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(b.lang == null ? 'Sửa mã' : 'Sửa mã (${b.lang})'),
            ),
            TextButton.icon(onPressed: () => _ed.replaceBlock(b.id, null), icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Xoá')),
          ]),
        ]),
      );

  /// Bảng trong trình soạn: xem như khi đọc, kèm "Sửa bảng" / "Xoá bảng" (không bao giờ bị làm phẳng khi lưu).
  Widget _tableBlock(TwTableBlock b, TwLook look) => Container(
        key: ValueKey('ed-table-${b.id}'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(border: Border.all(color: look.divider, style: BorderStyle.solid), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TwTableView(b, style: TextStyle(fontSize: 13, color: look.text)),
          Row(children: [
            TextButton.icon(
              key: const ValueKey('table-edit'),
              onPressed: () async {
                final r = await editTable(context, b);
                if (r != null) _ed.replaceBlock(b.id, r);
              },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Sửa bảng'),
            ),
            TextButton.icon(
              key: const ValueKey('table-delete'),
              onPressed: () => _ed.replaceBlock(b.id, null),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Xoá bảng'),
            ),
          ]),
        ]),
      );

  Future<void> _link() async {
    final c = _ed.focused;
    if (c == null) return;
    final url = await askText(context, title: 'Chèn link', hint: 'https://…', ok: 'Chèn');
    if (url == null) return;
    c.setLink(url.isEmpty ? null : url);
  }

  Widget _toolbar(TwLook look) {
    final c = _ed.focused, cur = c?.current ?? TFmt.plain, t = _ed.focusedBlock?.t;
    Widget b(IconData i, String tip, bool on, VoidCallback f, {Key? key}) => IconButton(
          key: key,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          iconSize: 19,
          style: IconButton.styleFrom(backgroundColor: on ? look.accentSoft : null, foregroundColor: on ? look.accent : look.sub),
          onPressed: c == null && !(key != null) ? null : f,
          icon: Icon(i),
        );
    Widget sep() => Container(width: 1, height: 18, color: look.divider, margin: const EdgeInsets.symmetric(horizontal: 4));
    return Container(
      decoration: BoxDecoration(color: look.surface, border: Border.all(color: look.divider), borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          b(Icons.format_bold_rounded, 'Đậm', cur.b, () => c!.toggle('b')),
          b(Icons.format_italic_rounded, 'Nghiêng', cur.i, () => c!.toggle('i')),
          b(Icons.format_underlined_rounded, 'Gạch chân', cur.u, () => c!.toggle('u')),
          b(Icons.strikethrough_s_rounded, 'Gạch ngang', cur.s, () => c!.toggle('s')),
          if (widget.compact) ...[
            sep(),
            b(Icons.alternate_email_rounded, 'Nhắc người / agent (@)', false, () => _mention(), key: const ValueKey('rt-mention')),
            b(Icons.tag_rounded, 'Nhắc việc (#)', false, () => _task(), key: const ValueKey('rt-task')),
          ],
          sep(),
          if (!widget.compact) b(Icons.title_rounded, 'Tiêu đề', t == 'h3', () => _ed.setType(t == 'h3' ? 'p' : 'h3')),
          b(Icons.format_list_bulleted_rounded, 'Gạch đầu dòng', t == 'ul', () => _ed.setType(t == 'ul' ? 'p' : 'ul')),
          b(Icons.format_list_numbered_rounded, 'Đánh số', t == 'ol', () => _ed.setType(t == 'ol' ? 'p' : 'ol')),
          b(Icons.checklist_rounded, 'Ô tick', t == 'check', () => _ed.setType(t == 'check' ? 'p' : 'check')),
          b(Icons.format_quote_rounded, 'Trích dẫn', t == 'quote', () => _ed.setType(t == 'quote' ? 'p' : 'quote')),
          b(Icons.code_rounded, 'Mã', cur.c, () => c!.toggle('c')),
          sep(),
          b(Icons.link_rounded, 'Link', cur.a != null, _link),
          if (!widget.compact) ...[
            b(Icons.alternate_email_rounded, 'Nhắc người / agent (@)', false, () => _mention(), key: const ValueKey('rt-mention')),
            b(Icons.tag_rounded, 'Nhắc việc (#)', false, () => _task(), key: const ValueKey('rt-task')),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final editor = BlockEditor(
      blocks: _folded ?? widget.blocks,
      onChanged: (b) {
        // Dán / gõ bảng Markdown: đổi các dòng | … | thành khối bảng (nạp lại trình soạn).
        final f = foldTables(b);
        if (f != null) {
          b = f;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _folded = f;
              _foldRev++;
            });
          });
        }
        _blocksSnapshot = b;
        widget.onChanged(b);
      },
      blockBuilder: (b) => b is TwTableBlock ? _tableBlock(b, look) : (b is TwCodeBlock ? _codeBlock(b, look) : null),
      controller: _ed,
      revision: widget.revision + _foldRev,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      style: TextStyle(fontSize: widget.compact ? 14 : 14.5, height: 1.5, color: look.text),
    );
    if (widget.readOnly) return editor;
    return ListenableBuilder(
      listenable: _ed,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _toolbar(look),
        Container(
          constraints: BoxConstraints(minHeight: widget.compact ? 44 : 90),
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          decoration: BoxDecoration(border: Border.all(color: look.divider), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
          child: editor,
        ),
      ]),
    );
  }
}

/// Xem chữ có định dạng: tiêu đề, danh sách, ô tick, trích dẫn, mã, link; @nhắc / #việc hiện nổi màu, bấm được.
/// Số thứ tự của mục "ol" thứ [i], tính cả số bắt đầu (start) của mục đầu danh sách.
int olNumberFrom(List<TBlock> blocks, int i) {
  var first = i;
  while (first > 0 && blocks[first - 1].t == 'ol' && blocks[first - 1].ind >= blocks[i].ind) {
    first--;
  }
  while (first < i && blocks[first].ind != blocks[i].ind) {
    first++;
  }
  final head = blocks[first];
  return olNumber(blocks, i) + (head is TwOlBlock ? head.start - 1 : 0);
}

/// Sửa khối mã: ô chữ nhiều dòng đơn cách + ngôn ngữ.
Future<TwCodeBlock?> editCode(BuildContext context, TwCodeBlock b) {
  final code = TextEditingController(text: b.code), lang = TextEditingController(text: b.lang ?? '');
  return showDialog<TwCodeBlock>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Sửa khối mã'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const ValueKey('code-lang'), controller: lang, decoration: const InputDecoration(labelText: 'Ngôn ngữ (không bắt buộc)', isDense: true)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('code-text'),
            controller: code,
            maxLines: 14,
            minLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Consolas', 'DejaVu Sans Mono'], fontSize: 13),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Huỷ')),
        FilledButton(key: const ValueKey('code-save'), onPressed: () => Navigator.pop(d, TwCodeBlock(id: b.id, code: code.text, lang: lang.text.trim().isEmpty ? null : lang.text.trim())), child: const Text('Xong')),
      ],
    ),
  );
}

/// Đoạn chữ có định dạng để xem: @nhắc / #việc nổi màu (bấm được), link bấm được, mã chữ đơn cách.
InlineSpan twRunsSpan(TwLook look, List<TRun> r, TextStyle s, void Function(String kind, String id)? onMention) => TextSpan(style: s, children: [
      for (final x in r)
        () {
          final m = mentionOf(x.f.a);
          if (m != null) {
            return TextSpan(
              text: x.x,
              style: s.copyWith(color: look.accent, fontWeight: FontWeight.w600, backgroundColor: look.accentSoft),
              recognizer: onMention == null ? null : (TapGestureRecognizer()..onTap = () => onMention(m.$1, m.$2)),
            );
          }
          var st = runStyle(x.f, s, look.dark);
          if (x.f.a != null) st = st.copyWith(color: look.accent);
          return TextSpan(
            text: x.x,
            style: st,
            recognizer: x.f.a != null ? (TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(x.f.a!), mode: LaunchMode.externalApplication)) : null,
          );
        }(),
    ]);

/// Bảng: hàng tiêu đề đậm trên nền nhạt, viền màu đường kẻ, căn lề theo cột. Cột rộng theo nội dung (tối đa 280px, chữ
/// xuống dòng trong ô); bảng rộng hơn chỗ thì cuộn ngang bên trong, không tràn trang.
class TwTableView extends StatelessWidget {
  const TwTableView(this.table, {super.key, required this.style, this.onMention, this.maxColumn = 280});
  final TwTableBlock table;
  final TextStyle style;
  final void Function(String kind, String id)? onMention;
  final double maxColumn;

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final cols = table.cols;
    if (cols == 0 || table.rows.isEmpty) return const SizedBox();
    final s = style.copyWith(height: 1.4);
    TextAlign al(int c) => switch (table.alignOf(c)) { 'c' => TextAlign.center, 'r' => TextAlign.right, _ => TextAlign.left };
    return Scrollbar(
      child: SingleChildScrollView(
        key: const ValueKey('tw-table'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        child: Table(
          defaultColumnWidth: MinColumnWidth(const IntrinsicColumnWidth(), FixedColumnWidth(maxColumn)),
          border: TableBorder.all(color: look.divider, borderRadius: BorderRadius.circular(6)),
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            for (var r = 0; r < table.rows.length; r++)
              TableRow(
                decoration: r == 0 ? BoxDecoration(color: look.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))) : null,
                children: [
                  for (var c = 0; c < cols; c++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                      child: Text.rich(
                        twRunsSpan(look, c < table.rows[r].length ? table.rows[r][c] : const [], r == 0 ? s.copyWith(fontWeight: FontWeight.w700) : s, onMention),
                        textAlign: al(c),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Sửa bảng: lưới ô chữ (Markdown một dòng: **đậm**, *nghiêng*, `mã`), thêm / bớt hàng, cột. Trả về bảng mới.
Future<TwTableBlock?> editTable(BuildContext context, TwTableBlock table) => showDialog<TwTableBlock>(context: context, builder: (c) => _TableEditor(table: table));

class _TableEditor extends StatefulWidget {
  const _TableEditor({required this.table});
  final TwTableBlock table;
  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  late final List<List<TextEditingController>> _cells = [
    for (final r in widget.table.rows) [for (var c = 0; c < widget.table.cols; c++) TextEditingController(text: c < r.length ? runsToMarkdown(r[c]) : '')],
  ];
  late final List<String> _align = [for (var c = 0; c < widget.table.cols; c++) widget.table.alignOf(c)];

  @override
  void dispose() {
    for (final r in _cells) {
      for (final c in r) {
        c.dispose();
      }
    }
    super.dispose();
  }

  int get _cols => _cells.isEmpty ? 0 : _cells.first.length;

  void _addRow() => setState(() => _cells.add([for (var c = 0; c < _cols; c++) TextEditingController()]));
  void _addCol() => setState(() {
        for (final r in _cells) {
          r.add(TextEditingController());
        }
        _align.add('l');
      });

  TwTableBlock _result() {
    final rows = <List<List<TRun>>>[];
    for (var r = 0; r < _cells.length; r++) {
      rows.add([
        for (var c = 0; c < _cols; c++)
          () {
            final orig = r < widget.table.rows.length && c < widget.table.rows[r].length ? widget.table.rows[r][c] : null;
            final text = _cells[r][c].text;
            // Ô không sửa: giữ nguyên đoạn chữ (kể cả @nhắc, màu).
            return orig != null && runsToMarkdown(orig) == text ? [for (final x in orig) TRun(x.x, x.f)] : inlineMarkdown(text);
          }(),
      ]);
    }
    return TwTableBlock(id: widget.table.id, rows: rows, align: _align);
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    return AlertDialog(
      title: const Text('Sửa bảng'),
      content: SizedBox(
        width: 720,
        height: 420,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (var c = 0; c < _cols; c++)
                  SizedBox(
                    width: 180,
                    child: Row(children: [
                      PopupMenuButton<String>(
                        key: ValueKey('tcol-$c'),
                        tooltip: 'Căn lề / xoá cột',
                        icon: Icon(switch (_align[c]) { 'c' => Icons.format_align_center, 'r' => Icons.format_align_right, _ => Icons.format_align_left }, size: 18),
                        onSelected: (v) => setState(() {
                          if (v == 'del') {
                            if (_cols <= 1) return;
                            for (final r in _cells) {
                              r.removeAt(c).dispose();
                            }
                            _align.removeAt(c);
                          } else {
                            _align[c] = v;
                          }
                        }),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'l', child: Text('Căn trái')),
                          PopupMenuItem(value: 'c', child: Text('Căn giữa')),
                          PopupMenuItem(value: 'r', child: Text('Căn phải')),
                          PopupMenuItem(value: 'del', child: Text('Xoá cột')),
                        ],
                      ),
                    ]),
                  ),
              ]),
              for (var r = 0; r < _cells.length; r++)
                Row(children: [
                  for (var c = 0; c < _cols; c++)
                    Container(
                      width: 180,
                      padding: const EdgeInsets.all(2),
                      color: r == 0 ? look.surface : null,
                      child: TextField(
                        key: ValueKey('tcell-$r-$c'),
                        controller: _cells[r][c],
                        style: TextStyle(fontSize: 13, fontWeight: r == 0 ? FontWeight.w700 : null),
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                  if (r > 0)
                    IconButton(
                      key: ValueKey('trow-del-$r'),
                      tooltip: 'Xoá hàng',
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: () => setState(() {
                        for (final x in _cells.removeAt(r)) {
                          x.dispose();
                        }
                      }),
                    ),
                ]),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton.icon(key: const ValueKey('trow-add'), onPressed: _addRow, icon: const Icon(Icons.add, size: 18), label: const Text('Thêm hàng')),
        TextButton.icon(key: const ValueKey('tcol-add'), onPressed: _addCol, icon: const Icon(Icons.view_column_outlined, size: 18), label: const Text('Thêm cột')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(key: const ValueKey('table-save'), onPressed: () => Navigator.pop(context, _result()), child: const Text('Xong')),
      ],
    );
  }
}

class TwRichView extends StatelessWidget {
  const TwRichView(this.blocks, {super.key, this.onMention, this.style});
  final List<TBlock> blocks;
  final void Function(String kind, String id)? onMention;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final base = style ?? DefaultTextStyle.of(context).style.copyWith(height: 1.55, color: look.text);
    InlineSpan runs(List<TRun> r, TextStyle s) => twRunsSpan(look, r, s, onMention);
    // Nội dung cũ có bảng Markdown dạng đoạn văn: hiện thành bảng.
    final blocks = foldTables(this.blocks) ?? this.blocks;
    final out = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final ind = 18.0 * b.ind;
      if (b is TwTableBlock) {
        out.add(Padding(padding: EdgeInsets.only(left: ind, top: 4, bottom: 4), child: TwTableView(b, style: base, onMention: onMention)));
        continue;
      }
      if (b.t == 'code') {
        // Khối mã: chữ thuần (không định dạng), ghép các dòng mã liền nhau, cuộn ngang khi dài.
        final lines = [b.text];
        while (b is! TwCodeBlock && i + 1 < blocks.length && blocks[i + 1].t == 'code' && blocks[i + 1] is! TwCodeBlock) {
          lines.add(blocks[++i].text);
        }
        out.add(Container(
          key: const ValueKey('tw-code'),
          width: double.infinity,
          margin: EdgeInsets.only(left: ind, top: 4, bottom: 4),
          decoration: BoxDecoration(color: look.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: look.divider)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: Text(lines.join('\n'), softWrap: false, style: base.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Consolas', 'DejaVu Sans Mono'], fontSize: (base.fontSize ?? 14) - 1, height: 1.45)),
          ),
        ));
        continue;
      }
      switch (b.t) {
        case 'hr':
          out.add(Divider(color: look.divider));
        case 'h1' || 'h2' || 'h3':
          out.add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text.rich(runs(b.r, base.copyWith(fontSize: switch (b.t) { 'h1' => 19.0, 'h2' => 16.5, _ => 14.5 }, fontWeight: FontWeight.w700))),
          ));
        case 'quote':
          out.add(Container(
            margin: EdgeInsets.only(left: ind, top: 2, bottom: 2),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: look.divider, width: 3))),
            child: Text.rich(runs(b.r, base.copyWith(color: look.sub))),
          ));
        case 'check':
          out.add(Padding(
            padding: EdgeInsets.only(left: ind),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 3, right: 6), child: Icon(b.done ? Icons.check_box : Icons.check_box_outline_blank, size: 17, color: b.done ? look.ok : look.sub)),
              Expanded(child: Text.rich(runs(b.r, b.done ? base.copyWith(decoration: TextDecoration.lineThrough, color: look.sub) : base))),
            ]),
          ));
        case 'ul' || 'ol':
          out.add(Padding(
            padding: EdgeInsets.only(left: ind),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              (b.t == 'ol' ? SizedBox(width: 26, child: Text('${olNumberFrom(blocks, i)}.', textAlign: TextAlign.right, style: base)) : bulletOf(blocks, i, base)) ?? const SizedBox(width: 22),
              const SizedBox(width: 4),
              Expanded(child: Text.rich(runs(b.r, base))),
            ]),
          ));
        default:
          out.add(Padding(padding: EdgeInsets.only(left: ind), child: Text.rich(runs(b.r, base))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: out);
  }
}
