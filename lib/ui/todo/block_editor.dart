// Todo: soạn nội dung theo khối. Mỗi khối là một ô chữ (RichController); Enter tách khối, xoá ở đầu dòng gộp với
// dòng trên, dán nhiều dòng thành nhiều khối. Chế độ danh sách (kind = list): việc chưa xong ở trên, việc đã xong gom
// xuống dưới, kéo để đổi thứ tự.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/i18n.dart';
import 'look.dart';
import 'model.dart';
import 'rich.dart';

/// Cầu nối thanh công cụ ↔ ô đang gõ.
class BlockEditorController extends ChangeNotifier {
  _BlockEditorState? _s;
  RichController? get focused => _s?._focusedCtl;
  TBlock? get focusedBlock => _s?._focusedBlock;
  bool get hasFocus => focused != null;

  void setType(String t) => _s?._setType(t);
  void indent(int d) => _s?._indent(d);
  void insertDivider() => _s?._insertDivider();
  /// Thêm khối mới ở cuối (hoặc sau ô đang gõ) và đặt con trỏ vào.
  void addBlock({String t = 'p'}) => _s?._addAfterFocus(t);
  void focusEnd() => _s?._focusEnd();
  void refresh() => notifyListeners();
}

class BlockEditor extends StatefulWidget {
  const BlockEditor({
    super.key,
    required this.blocks,
    required this.onChanged,
    required this.controller,
    this.listMode = false,
    this.readOnly = false,
    this.revision = 0,
    this.style = const TextStyle(fontSize: 16, height: 1.45),
    this.onPasteMedia,
    this.onInsertBytes,
    this.autofocus = false,
  });

  final List<TBlock> blocks;
  final ValueChanged<List<TBlock>> onChanged;
  final BlockEditorController controller;
  final bool listMode, readOnly, autofocus;
  /// Tăng khi nội dung đổi từ ngoài (người khác sửa): ô nào không đang gõ thì nạp lại.
  final int revision;
  final TextStyle style;
  /// Ctrl+V / "Dán ảnh" khi bộ nhớ tạm có ảnh hoặc tệp: trả true nếu đã xử lý.
  final Future<bool> Function()? onPasteMedia;
  /// Ảnh chèn từ bàn phím ảo (Android: Gboard, Samsung Keyboard): dữ liệu + kiểu.
  final void Function(Uint8List data, String mime)? onInsertBytes;

  @override
  State<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<BlockEditor> {
  late List<TBlock> _blocks;
  final _ctl = <String, RichController>{};
  final _focus = <String, FocusNode>{};
  String? _focusedId;
  bool _doneOpen = true;

  RichController? get _focusedCtl => _focusedId == null ? null : _ctl[_focusedId];
  TBlock? get _focusedBlock => _blocks.where((b) => b.id == _focusedId).firstOrNull;

  @override
  void initState() {
    super.initState();
    widget.controller._s = this;
    _blocks = [for (final b in widget.blocks) b.clone()];
    if (_blocks.isEmpty) _blocks.add(TBlock(t: widget.listMode ? 'check' : 'p'));
    if (widget.autofocus) WidgetsBinding.instance.addPostFrameCallback((_) => _focusEnd());
  }

  @override
  void didUpdateWidget(BlockEditor old) {
    super.didUpdateWidget(old);
    widget.controller._s = this;
    if (old.revision != widget.revision) {
      // Bản mới từ ngoài: giữ nguyên ô đang gõ, nạp lại các ô khác.
      final mine = _focusedBlock;
      _blocks = [for (final b in widget.blocks) b.id == mine?.id ? mine! : b.clone()];
      for (final b in _blocks) {
        final c = _ctl[b.id];
        if (c != null && b.id != mine?.id && c.body != b.text) c.setBody(b.r);
      }
      setState(() {});
    }
    if (old.listMode != widget.listMode) setState(() {});
  }

  @override
  void dispose() {
    if (widget.controller._s == this) widget.controller._s = null;
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  RichController _c(TBlock b) => _ctl.putIfAbsent(b.id, () {
        final c = RichController(b.r, dark: isDark(context));
        c.onEdited = () => _edited(b.id);
        c.onBackspaceAtStart = () => _backspace(b.id);
        c.addListener(() {
          if (_focusedId == b.id) widget.controller.refresh();
        });
        return c;
      });

  FocusNode _f(TBlock b) => _focus.putIfAbsent(b.id, () {
        final f = FocusNode();
        f.addListener(() {
          if (f.hasFocus) {
            _focusedId = b.id;
          } else if (_focusedId == b.id) {
            // Giữ ô cuối cùng được gõ để thanh công cụ (bấm vào làm mất focus) vẫn áp vào ô đó.
          }
          widget.controller.refresh();
        });
        return f;
      });

  void _emit() => widget.onChanged([for (final b in _blocks) b.clone()]);

  int _index(String id) => _blocks.indexWhere((b) => b.id == id);

  void _focusBlock(String id, {int? offset}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final f = _focus[id], c = _ctl[id];
      if (f == null || c == null) return;
      f.requestFocus();
      c.selection = TextSelection.collapsed(offset: (offset ?? c.text.length).clamp(1, c.text.length));
    });
  }

  void _focusEnd() {
    final last = widget.listMode ? _blocks.where((b) => !b.done).lastOrNull ?? _blocks.lastOrNull : _blocks.lastOrNull;
    if (last == null || last.t == 'hr') return _addAfterFocus(widget.listMode ? 'check' : 'p');
    _focusBlock(last.id);
  }

  void _edited(String id) {
    final i = _index(id);
    if (i < 0) return;
    final b = _blocks[i], c = _ctl[id]!;
    if (!c.body.contains('\n')) {
      b.r = c.runs;
      _emit();
      return;
    }
    // Enter / dán nhiều dòng: tách thành nhiều khối.
    final sel = c.selection.baseOffset;
    final lastNl = c.text.lastIndexOf('\n');
    final segs = c.splitLines();
    final wasEmptyList = segs.length == 2 && segs[0].isEmpty && segs[1].isEmpty && b.isList && !widget.listMode;
    if (wasEmptyList) {
      // Enter ở dòng danh sách trống: thoát danh sách (hoặc lùi thụt lề).
      c.setBody(const []);
      if (b.ind > 0) {
        b.ind--;
      } else {
        b.t = 'p';
      }
      setState(() {});
      _emit();
      return;
    }
    b.r = segs.first;
    c.setBody(segs.first);
    final nextType = b.isList ? b.t : 'p';
    final added = [for (final s in segs.skip(1)) TBlock(t: nextType, r: s, ind: b.isList ? b.ind : 0)];
    _blocks.insertAll(i + 1, added);
    setState(() {});
    _emit();
    final cursor = sel > lastNl ? sel - lastNl : 1;
    _focusBlock(added.last.id, offset: cursor);
  }

  void _backspace(String id) {
    final i = _index(id);
    if (i < 0) return;
    final b = _blocks[i];
    if (b.ind > 0) {
      setState(() => b.ind--);
      return _emit();
    }
    if (b.t != 'p' && !widget.listMode) {
      setState(() => b.t = 'p');
      return _emit();
    }
    // Gộp vào khối liền trên (bỏ qua đường kẻ: xoá đường kẻ).
    var j = i - 1;
    if (widget.listMode) {
      while (j >= 0 && _blocks[j].done != b.done) {
        j--;
      }
    }
    if (j < 0) return;
    final prev = _blocks[j];
    if (prev.t == 'hr') {
      setState(() => _blocks.removeAt(j));
      return _emit();
    }
    final pc = _c(prev);
    final at = pc.text.length;
    final merged = [...pc.runs, ..._ctl[id]!.runs];
    prev.r = merged;
    pc.setBody(merged, cursor: at);
    setState(() => _blocks.removeAt(i));
    _ctl.remove(id)?.dispose();
    _focus.remove(id)?.dispose();
    _emit();
    _focusBlock(prev.id, offset: at);
  }

  void _setType(String t) {
    final b = _focusedBlock;
    if (b == null) return;
    setState(() => b.t = b.t == t ? 'p' : t);
    _emit();
    _focusBlock(b.id, offset: _ctl[b.id]?.selection.baseOffset);
  }

  void _indent(int d) {
    final b = _focusedBlock;
    if (b == null) return;
    setState(() => b.ind = (b.ind + d).clamp(0, 6));
    _emit();
  }

  void _insertDivider() {
    final i = _focusedId == null ? _blocks.length - 1 : _index(_focusedId!);
    final nb = TBlock(t: 'p');
    setState(() => _blocks.insertAll(i + 1, [TBlock(t: 'hr'), nb]));
    _emit();
    _focusBlock(nb.id);
  }

  void _addAfterFocus(String t) {
    var i = _focusedId == null ? -1 : _index(_focusedId!);
    if (i < 0) i = widget.listMode ? (_blocks.lastIndexWhere((b) => !b.done)) : _blocks.length - 1;
    final cur = i >= 0 && i < _blocks.length ? _blocks[i] : null;
    // Ô đang gõ còn trống: đổi kiểu ô đó thay vì thêm ô.
    if (cur != null && cur.t != 'hr' && cur.text.isEmpty && !widget.listMode) {
      return _setType(t);
    }
    final nb = TBlock(t: t, ind: cur?.isList == true && t == cur!.t ? cur.ind : 0);
    setState(() => _blocks.insert(i + 1, nb));
    _emit();
    _focusBlock(nb.id);
  }

  void _toggleDone(TBlock b, bool v) {
    setState(() => b.done = v);
    _emit();
  }

  void _remove(TBlock b) {
    final i = _index(b.id);
    setState(() => _blocks.removeWhere((x) => x.id == b.id));
    _ctl.remove(b.id)?.dispose();
    _focus.remove(b.id)?.dispose();
    if (_blocks.isEmpty) _blocks.add(TBlock(t: widget.listMode ? 'check' : 'p'));
    _emit();
    if (i > 0 && i - 1 < _blocks.length) _focusBlock(_blocks[i - 1].id);
  }

  Future<void> _paste(RichController c) async {
    if (widget.onPasteMedia != null && await widget.onPasteMedia!()) return;
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null && d!.text!.isNotEmpty) c.insert(d.text!.replaceAll('\r\n', '\n'));
  }

  Widget _field(TBlock b, int i, TextStyle style) {
    final c = _c(b);
    c.dark = isDark(context);
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    final field = TextField(
      controller: c,
      focusNode: _f(b),
      readOnly: widget.readOnly,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      style: blockStyle(b.t, style).copyWith(
        decoration: b.done ? TextDecoration.lineThrough : null,
        color: b.done ? style.color?.withValues(alpha: .55) : null,
      ),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        hintText: i == 0 && _blocks.length == 1 && c.body.isEmpty ? (widget.listMode ? tr('Mục danh sách') : tr('Ghi chú…')) : null,
      ),
      contextMenuBuilder: (ctx, st) => AdaptiveTextSelectionToolbar.buttonItems(anchors: st.contextMenuAnchors, buttonItems: [
        ...st.contextMenuButtonItems,
        if (widget.onPasteMedia != null && !widget.readOnly)
          ContextMenuButtonItem(label: tr('Dán ảnh / tệp'), onPressed: () {
            ContextMenuController.removeAny();
            widget.onPasteMedia!().then((ok) {
              if (!ok && ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('Bộ nhớ tạm không có ảnh hoặc tệp'))));
            });
          }),
      ]),
      contentInsertionConfiguration: widget.onInsertBytes == null
          ? null
          : ContentInsertionConfiguration(onContentInserted: (c) {
              if (c.data != null && c.data!.isNotEmpty) widget.onInsertBytes!(c.data!, c.mimeType);
            }),
    );
    if (widget.readOnly) return field;
    SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) => SingleActivator(k, control: !mac, meta: mac, shift: shift);
    return CallbackShortcuts(bindings: {
      key(LogicalKeyboardKey.keyB): () => c.toggle('b'),
      key(LogicalKeyboardKey.keyI): () => c.toggle('i'),
      key(LogicalKeyboardKey.keyU): () => c.toggle('u'),
      key(LogicalKeyboardKey.keyX, shift: true): () => c.toggle('s'),
      key(LogicalKeyboardKey.keyV): () => _paste(c),
      key(LogicalKeyboardKey.digit1, shift: false): () => _setType('h1'),
      key(LogicalKeyboardKey.digit2, shift: false): () => _setType('h2'),
      key(LogicalKeyboardKey.digit8, shift: true): () => _setType('ul'),
      key(LogicalKeyboardKey.digit7, shift: true): () => _setType('ol'),
      key(LogicalKeyboardKey.digit9, shift: true): () => _setType('check'),
      const SingleActivator(LogicalKeyboardKey.tab): () => _indent(1),
      const SingleActivator(LogicalKeyboardKey.tab, shift: true): () => _indent(-1),
    }, child: field);
  }

  Widget _row(TBlock b, int i, {Widget? handle}) {
    final style = widget.style.copyWith(color: widget.style.color ?? Theme.of(context).colorScheme.onSurface);
    if (b.t == 'hr') {
      return Row(children: [
        Expanded(child: Divider(height: 24, thickness: 1.2, color: style.color!.withValues(alpha: .3))),
        if (!widget.readOnly) IconButton(visualDensity: VisualDensity.compact, tooltip: tr('Xoá đường kẻ'), icon: const Icon(Icons.close_rounded, size: 16), onPressed: () => _remove(b)),
      ]);
    }
    final lead = b.t == 'check'
        ? SizedBox(
            width: 32,
            height: 30,
            child: Checkbox(
              value: b.done,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: style.color!.withValues(alpha: .6), width: 1.6),
              onChanged: widget.readOnly ? null : (v) => _toggleDone(b, v ?? false),
            ),
          )
        : bulletOf(_blocks, i, blockStyle(b.t, style));
    final focused = _focusedId == b.id && (_focus[b.id]?.hasFocus ?? false);
    Widget row = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ?handle,
      SizedBox(width: 22.0 * b.ind),
      if (lead != null) Padding(padding: EdgeInsets.only(top: b.t == 'check' ? 0 : 4, right: 4), child: lead),
      Expanded(child: _field(b, i, style)),
      if (b.t == 'check' && !widget.readOnly)
        Opacity(
          opacity: focused ? 1 : 0,
          child: IconButton(visualDensity: VisualDensity.compact, tooltip: tr('Xoá mục'), icon: const Icon(Icons.close_rounded, size: 18), onPressed: focused ? () => _remove(b) : null),
        ),
    ]);
    if (b.t == 'quote') {
      row = Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: style.color!.withValues(alpha: .35), width: 3))),
        child: row,
      );
    } else if (b.t == 'code') {
      row = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: style.color!.withValues(alpha: .07), borderRadius: BorderRadius.circular(6)),
        child: row,
      );
    }
    return KeyedSubtree(key: ValueKey(b.id), child: row);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.listMode) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < _blocks.length; i++) _row(_blocks[i], i)]);
    }
    // Danh sách: chưa xong (kéo đổi thứ tự) + "Thêm mục" + đã xong (thu gọn được).
    final open = _blocks.where((b) => !b.done).toList(), done = _blocks.where((b) => b.done).toList();
    final sub = (widget.style.color ?? Theme.of(context).colorScheme.onSurface).withValues(alpha: .65);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorderItem: widget.readOnly
            ? (_, _) {}
            : (from, to) {
                final b = open.removeAt(from);
                open.insert(to, b);
                setState(() => _blocks = [...open, ...done]);
                _emit();
              },
        children: [
          for (var i = 0; i < open.length; i++)
            KeyedSubtree(
              key: ValueKey('o-${open[i].id}'),
              child: _row(open[i], _index(open[i].id),
                  handle: widget.readOnly
                      ? null
                      : ReorderableDragStartListener(
                          index: i,
                          child: MouseRegion(cursor: SystemMouseCursors.grab, child: Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.drag_indicator_rounded, size: 18, color: sub))),
                        )),
            ),
        ],
      ),
      if (!widget.readOnly)
        InkWell(
          onTap: () => _addAfterFocus('check'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [const SizedBox(width: 22), Icon(Icons.add_rounded, size: 20, color: sub), const SizedBox(width: 10), Text(tr('Mục danh sách'), style: TextStyle(color: sub))]),
          ),
        ),
      if (done.isNotEmpty) ...[
        const Divider(height: 12),
        InkWell(
          onTap: () => setState(() => _doneOpen = !_doneOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Icon(_doneOpen ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 20, color: sub),
              const SizedBox(width: 6),
              Text(tr('{0} mục đã hoàn thành', [done.length]), style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        if (_doneOpen) for (final b in done) _row(b, _index(b.id), handle: const SizedBox(width: 18)),
      ],
    ]);
  }
}

/// Đổi chế độ: văn bản → danh sách (mỗi dòng thành một việc) và ngược lại (việc thành dòng chữ, giữ dấu tick bằng ô tick).
List<TBlock> toListMode(List<TBlock> blocks) => [
      for (final b in blocks)
        if (b.t != 'hr' && (b.text.trim().isNotEmpty || b.t == 'check')) TBlock(id: b.id, t: 'check', r: b.r, done: b.t == 'check' && b.done),
    ];

List<TBlock> toNoteMode(List<TBlock> blocks) => [for (final b in blocks) b.clone()];

/// Đợi một chút trước khi lưu (gõ liên tục chỉ gửi một lần).
class Debouncer {
  Debouncer(this.delay);
  final Duration delay;
  Timer? _t;
  VoidCallback? _last;
  void call(VoidCallback f) {
    _last = f;
    _t?.cancel();
    _t = Timer(delay, () {
      _last = null;
      f();
    });
  }

  void flush() {
    _t?.cancel();
    final f = _last;
    _last = null;
    f?.call();
  }
}
