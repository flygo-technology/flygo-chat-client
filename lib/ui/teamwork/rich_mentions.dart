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
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _search('');
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
    final agents = widget.store.agents.where((a) => q.isEmpty || a.label.toLowerCase().contains(q)).toList();
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
          for (final p in _people)
            ListTile(
              key: ValueKey('mention-user-${p.id}'),
              dense: true,
              leading: TwAvatar(name: p.name, id: p.id, size: 26, border: false),
              title: Text(p.name),
              onTap: () => Navigator.pop(context, TwAssignee(kind: 'user', id: p.id, name: p.name)),
            ),
          for (final a in agents)
            ListTile(
              key: ValueKey('mention-agent-${a.id}'),
              dense: true,
              leading: TwAvatar(name: a.name, id: a.id, agent: true, size: 26, border: false),
              title: Text(a.label),
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
          sep(),
          if (!widget.compact) b(Icons.title_rounded, 'Tiêu đề', t == 'h3', () => _ed.setType(t == 'h3' ? 'p' : 'h3')),
          b(Icons.format_list_bulleted_rounded, 'Gạch đầu dòng', t == 'ul', () => _ed.setType(t == 'ul' ? 'p' : 'ul')),
          b(Icons.format_list_numbered_rounded, 'Đánh số', t == 'ol', () => _ed.setType(t == 'ol' ? 'p' : 'ol')),
          b(Icons.checklist_rounded, 'Ô tick', t == 'check', () => _ed.setType(t == 'check' ? 'p' : 'check')),
          b(Icons.format_quote_rounded, 'Trích dẫn', t == 'quote', () => _ed.setType(t == 'quote' ? 'p' : 'quote')),
          b(Icons.code_rounded, 'Mã', cur.c, () => c!.toggle('c')),
          sep(),
          b(Icons.link_rounded, 'Link', cur.a != null, _link),
          b(Icons.alternate_email_rounded, 'Nhắc người / agent (@)', false, () => _mention(), key: const ValueKey('rt-mention')),
          b(Icons.tag_rounded, 'Nhắc việc (#)', false, () => _task(), key: const ValueKey('rt-task')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final editor = BlockEditor(
      blocks: widget.blocks,
      onChanged: (b) {
        _blocksSnapshot = b;
        widget.onChanged(b);
      },
      controller: _ed,
      revision: widget.revision,
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
class TwRichView extends StatelessWidget {
  const TwRichView(this.blocks, {super.key, this.onMention, this.style});
  final List<TBlock> blocks;
  final void Function(String kind, String id)? onMention;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final base = style ?? TextStyle(fontSize: 14, height: 1.55, color: look.text);
    InlineSpan runs(List<TRun> r, TextStyle s) => TextSpan(style: s, children: [
          for (final x in r)
            () {
              final m = mentionOf(x.f.a);
              if (m != null) {
                return TextSpan(
                  text: x.x,
                  style: s.copyWith(color: look.accent, fontWeight: FontWeight.w600, backgroundColor: look.accentSoft),
                  recognizer: onMention == null ? null : (TapGestureRecognizer()..onTap = () => onMention!(m.$1, m.$2)),
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
    final out = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final ind = 18.0 * b.ind;
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
        case 'code':
          out.add(Container(
            margin: EdgeInsets.only(left: ind, top: 2, bottom: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: look.surface, borderRadius: BorderRadius.circular(6)),
            child: Text.rich(runs(b.r, base.copyWith(fontFamily: 'monospace', fontSize: 13))),
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
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [bulletOf(blocks, i, base) ?? const SizedBox(width: 22), const SizedBox(width: 4), Expanded(child: Text.rich(runs(b.r, base)))]),
          ));
        default:
          out.add(Padding(padding: EdgeInsets.only(left: ind), child: Text.rich(runs(b.r, base))));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: out);
  }
}
