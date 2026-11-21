import 'package:flutter/material.dart';

import '../../../api/mini_apps.dart';
import '../../todo/todo_page.dart' show openTodo, kTodoScreen;

import '../../../i18n/i18n.dart';
import '../page_types.dart';
import '../stage_frame.dart';
import 'notes_app.dart';
import 'builtin.dart' show pageField;

// Loại trang "Ghi chú" (máy chủ: relay/meet-pt-notes.mjs; cũng là app riêng "Ghi chú"): bảng ghi chú dán theo cột, màu,
// kéo thả (nhấn giữ ghi chú rồi kéo sang cột khác), 👍 (có thể giới hạn số phiếu), ẩn danh tuỳ bảng, ghi vào Biên bản.

const _sub = Color(0xFF9AA0A6);
const _col = Color(0xFF23262C);
const noteColors = <String, Color>{
  'yellow': Color(0xFFFFE68A),
  'green': Color(0xFFB9F0C9),
  'blue': Color(0xFFCFE3FF),
  'pink': Color(0xFFFFC9C2),
  'purple': Color(0xFFE2D4FF),
  'orange': Color(0xFFFFD8A8),
};

void registerNotesPageType() {
  registerPageType(PageTypeSpec(
    type: 'notes',
    label: tr('Ghi chú'),
    desc: tr('Bảng ghi chú dán, chia cột, 👍'),
    icon: Icons.sticky_note_2_outlined,
    color: const Color(0xFFF9AB00),
    create: (context, call) => showModalBottomSheet<PageDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => NotesComposer(meeting: call.pagesMeeting),
    ),
    view: (context, ctx) => NotesView(ctx),
    stageThemed: true,
    // Mỗi trang là một app (mockup 21/11): dán ghi chú, +1, chuyển cột ngay trong trang; chủ trang đổi pha, hẹn giờ.
    panel: (context, ctx) => NotesPanel(ctx),
    controls: (context, ctx) => NotesControls(ctx),
  ));
}

/// Tạo bảng ghi chú (dùng cả cho app Ghi chú).
class NotesComposer extends StatefulWidget {
  /// Mã cuộc họp: trang là bảng của cuộc họp trong app Ghi chú (mọi người đang họp cùng ghi).
  final String? meeting;
  const NotesComposer({super.key, this.meeting});
  @override
  State<NotesComposer> createState() => _NotesComposerState();
}

class _NotesComposerState extends State<NotesComposer> {
  final _title = TextEditingController();
  final _cols = TextEditingController(text: 'Ý tưởng\nĐang làm\nĐã xong');
  bool _anon = false;
  int _votes = 0;

  @override
  void dispose() {
    _title.dispose();
    _cols.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.meeting != null ? tr('Bảng ghi chú của cuộc họp') : tr('Bảng ghi chú mới'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              if (widget.meeting != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tr('Mọi người trong cuộc họp cùng ghi trên bảng này trong app Ghi chú; họp xong bảng vẫn còn ở đó.'), style: const TextStyle(color: _sub, fontSize: 12.5)),
                ),
              const SizedBox(height: 12),
              TextField(controller: _title, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Tên bảng'))),
              const SizedBox(height: 10),
              TextField(controller: _cols, minLines: 2, maxLines: 6, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Các cột (mỗi dòng một cột)'))),
              if (widget.meeting == null) SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Ẩn tên người viết'), style: const TextStyle(color: Colors.white)),
                value: _anon,
                onChanged: (v) => setState(() => _anon = v),
              ),
              if (widget.meeting == null) Row(children: [
                Expanded(child: Text(tr('Số 👍 mỗi người'), style: const TextStyle(color: Colors.white))),
                DropdownButton<int>(
                  value: _votes,
                  dropdownColor: const Color(0xFF3A3B3F),
                  style: const TextStyle(color: Colors.white),
                  items: [for (final n in [0, 1, 2, 3, 5]) DropdownMenuItem(value: n, child: Text(n == 0 ? tr('Không giới hạn') : '$n'))],
                  onChanged: (v) => setState(() => _votes = v ?? 0),
                ),
              ]),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  final t = _title.text.trim().isEmpty ? tr('Ghi chú') : _title.text.trim();
                  Navigator.pop(context, PageDraft(title: t, init: {
                    'title': t,
                    'columns': [for (final l in _cols.text.split('\n')) if (l.trim().isNotEmpty) l.trim()],
                    'anon': _anon,
                    'votes_per_person': _votes,
                    if (widget.meeting != null) 'meeting': widget.meeting,
                  }));
                },
                child: Text(tr('Tạo bảng')),
              ),
            ]),
          ),
        ),
      );
}

class NotesView extends StatefulWidget {
  final PageCtx ctx;
  const NotesView(this.ctx, {super.key});
  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  bool _busy = false;
  String? _hover; // cột đang được kéo vào

  PageCtx get ctx => widget.ctx;
  Map<String, dynamic> get v => ctx.view;
  List<Map<String, dynamic>> get cols => [for (final c in (v['columns'] as List? ?? const [])) (c as Map).cast<String, dynamic>()];
  List<Map<String, dynamic>> notesOf(String col) => [for (final n in (v['notes'] as List? ?? const [])) if ((n as Map)['col'] == col) n.cast<String, dynamic>()];
  bool get manage => v['can_manage'] == true || ctx.control;
  bool get canWrite => ctx.data.role != 'viewer';

  Future<void> _act(String a, [Map<String, dynamic> b = const {}]) async {
    setState(() => _busy = true);
    try {
      await ctx.act(a, b);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bảng soạn một ghi chú (mới hoặc sửa).
  Future<void> _editNote({String? col, Map<String, dynamic>? note}) async {
    final text = TextEditingController(text: '${note?['text'] ?? ''}');
    var color = '${note?['color'] ?? 'yellow'}';
    final r = await showModalBottomSheet<(String, String, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      builder: (ctx2) => StatefulBuilder(
        builder: (ctx2, set) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx2).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                decoration: BoxDecoration(color: noteColors[color], borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: text,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  style: const TextStyle(color: Color(0xFF222222), fontSize: 16),
                  decoration: InputDecoration(border: InputBorder.none, hintText: tr('Viết ghi chú…'), counterText: ''),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 10, children: [
                for (final e in noteColors.entries)
                  GestureDetector(
                    onTap: () => set(() => color = e.key),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: e.value, shape: BoxShape.circle, border: Border.all(color: color == e.key ? Colors.white : Colors.transparent, width: 3)),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                if (note != null) TextButton.icon(onPressed: () => Navigator.pop(ctx2, ('', '', true)), icon: const Icon(Icons.delete_outline), label: Text(tr('Xoá'))),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(ctx2, (text.text.trim(), color, false)), child: Text(note == null ? tr('Dán') : tr('Lưu'))),
              ]),
            ]),
          ),
        ),
      ),
    );
    text.dispose();
    if (r == null) return;
    if (r.$3) return _act('delete', {'id': note!['id']});
    if (r.$1.isEmpty) return;
    if (note == null) return _act('add', {'text': r.$1, 'color': r.$2, 'col': col});
    return _act('edit', {'id': note['id'], 'text': r.$1, 'color': r.$2});
  }

  Widget _note(Map<String, dynamic> n, {bool big = false, bool readOnly = false}) {
    final mine = n['mine'] == true;
    final card = Container(
      width: big ? null : double.infinity,
      padding: EdgeInsets.fromLTRB(big ? 16 : 10, big ? 14 : 9, big ? 16 : 6, big ? 12 : 6),
      decoration: BoxDecoration(
        color: noteColors['${n['color']}'] ?? noteColors['yellow'],
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${n['text']}', style: TextStyle(color: const Color(0xFF222222), fontSize: big ? 24 : 14)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(
              mine ? tr('của bạn') : '${n['by_name'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: const Color(0xFF555555), fontSize: big ? 16 : 11),
            ),
          ),
          if (big || readOnly)
            Text('👍 ${n['votes']}', style: TextStyle(color: const Color(0xFF222222), fontSize: big ? 20 : 13, fontWeight: FontWeight.w700))
          else
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _busy || !canWrite ? null : () => _act('vote', {'id': n['id']}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: n['voted'] == true ? const Color(0x332BB3A3) : const Color(0x14000000), borderRadius: BorderRadius.circular(12)),
                child: Text('👍 ${n['votes']}', style: TextStyle(color: const Color(0xFF222222), fontWeight: n['voted'] == true ? FontWeight.w800 : FontWeight.w600, fontSize: 12)),
              ),
            ),
        ]),
      ]),
    );
    if (big || readOnly) return card;
    final tappable = GestureDetector(onTap: (mine || manage) && canWrite ? () => _editNote(note: n) : null, child: card);
    if (!canWrite) return tappable;
    return LongPressDraggable<String>(
      data: '${n['id']}',
      feedback: Material(color: Colors.transparent, child: SizedBox(width: 240, child: card)),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: tappable,
    );
  }

  Widget _column(Map<String, dynamic> c, double width) {
    final id = '${c['id']}';
    final ns = notesOf(id);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        setState(() => _hover = id);
        return true;
      },
      onLeave: (_) => setState(() => _hover = null),
      onAcceptWithDetails: (d) {
        setState(() => _hover = null);
        _act('move', {'id': d.data, 'col': id});
      },
      builder: (context, _, _) => Container(
        width: width,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _col,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hover == id ? const Color(0xFF2BB3A3) : Colors.transparent, width: 2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${c['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            Text('${ns.length}', style: const TextStyle(color: _sub, fontSize: 12)),
            if (manage)
              PopupMenuButton<String>(
                iconSize: 18,
                icon: const Icon(Icons.more_horiz, color: _sub, size: 18),
                color: const Color(0xFF3A3B3F),
                onSelected: (a) async {
                  if (a == 'rename') {
                    final name = await _ask(tr('Đổi tên cột'), '${c['name']}');
                    if (name != null && name.isNotEmpty) await _act('col_rename', {'id': id, 'name': name});
                  } else if (a == 'delete') {
                    await _act('col_delete', {'id': id});
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'rename', child: Text(tr('Đổi tên'), style: const TextStyle(color: Colors.white))),
                  if (cols.length > 1) PopupMenuItem(value: 'delete', child: Text(tr('Xoá cột (ghi chú về cột đầu)'), style: const TextStyle(color: Colors.white))),
                ],
              ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: ns.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _note(ns[i]),
            ),
          ),
          if (canWrite)
            TextButton.icon(onPressed: _busy ? null : () => _editNote(col: id), icon: const Icon(Icons.add, size: 18), label: Text(tr('Thêm ghi chú'))),
        ]),
      ),
    );
  }

  Future<String?> _ask(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(tr('Lưu'))),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  /// Sân khấu (mockup Họp): mỗi cột một khung, giấy dán sắp theo bình chọn, ghi chú nhiều ▲ nhất của cả bảng nổi lên
  /// ("đang bàn"). Chỉ xem; thêm / sửa trên app.
  Widget _stage({StageMetrics? fm}) {
    final m = fm ?? StageMetrics.of(context);
    if (m == null) return FittedBox(child: SizedBox(width: 1168, height: 560, child: _stage(fm: const StageMetrics(theme: StageTheme(), portrait: false, size: Size(1168, 560), child: SizedBox()))));
    final t = m.theme;
    final portrait = m.portrait;
    final notes = [for (final n in (v['notes'] as List? ?? const [])) (n as Map).cast<String, dynamic>()];
    final top = (notes.toList()..sort((a, b) => ((b['votes'] as num?) ?? 0).compareTo((a['votes'] as num?) ?? 0))).firstOrNull;
    final groups = cols.isEmpty
        ? [(id: '', name: tr('Ghi chú'))]
        : [
            for (final c in cols) (id: '${c['id']}', name: '${c['name']}'),
            if (notes.any((n) => !cols.any((c) => c['id'] == n['col']))) (id: '', name: tr('Chưa xếp cột')),
          ];
    List<Map<String, dynamic>> inGroup(String id) =>
        notes.where((n) => cols.isEmpty || (id.isEmpty ? !cols.any((c) => c['id'] == n['col']) : n['col'] == id)).toList()
          ..sort((a, b) => ((b['votes'] as num?) ?? 0).compareTo((a['votes'] as num?) ?? 0));
    Widget card(Map<String, dynamic> n) {
      final hot = identical(n, top) && ((n['votes'] as num?) ?? 0) > 0;
      return Transform.rotate(
        angle: hot ? -.02 : 0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.fromLTRB(14, 12, 14, portrait ? 10 : 12),
          decoration: BoxDecoration(
            color: noteColors['${n['color']}'] ?? noteColors['yellow'],
            borderRadius: BorderRadius.circular(10),
            border: hot ? Border.all(color: const Color(0xFFF5B544), width: 3) : null,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: hot ? .4 : .25), blurRadius: hot ? 18 : 2, offset: Offset(0, hot ? 8 : 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${n['text']}', maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: const Color(0xFF1B1F26), fontSize: portrait ? 15 : 17, height: 1.35, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text('${n['by_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xB31B1F26), fontSize: 12, fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0x1F1B1F26), borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.arrow_upward_rounded, size: 12, color: Color(0xFF1B1F26)),
                  const SizedBox(width: 2),
                  Text('${n['votes'] ?? 0}', style: const TextStyle(color: Color(0xFF1B1F26), fontSize: 12, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
          ]),
        ),
      );
    }

    if (notes.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Bảng đang chờ ý tưởng đầu tiên'), style: TextStyle(color: t.text, fontSize: portrait ? 24 : 36, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(tr('Mỗi người dán ghi chú từ điện thoại; ghi chú nhiều ▲ nhất nổi lên trên.'), textAlign: TextAlign.center, style: TextStyle(color: t.sub, fontSize: portrait ? 15 : 19)),
        ]),
      );
    }
    Widget column(({String id, String name}) g, int i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: t.surface.withValues(alpha: t.light ? 1 : .7), borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: t.series[i % t.series.length], borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 8),
              Expanded(child: Text(g.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1))),
              Text('${inGroup(g.id).length}', style: TextStyle(color: t.sub, fontSize: 14)),
            ]),
            const SizedBox(height: 12),
            Expanded(child: ListView(padding: EdgeInsets.zero, physics: const NeverScrollableScrollPhysics(), children: [for (final n in inGroup(g.id).take(6)) card(n)])),
          ]),
        );
    if (portrait) {
      return ListView(padding: EdgeInsets.zero, children: [for (final n in notes.toList()..sort((a, b) => ((b['votes'] as num?) ?? 0).compareTo((a['votes'] as num?) ?? 0))) card(n)]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, g) in groups.take(4).indexed) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: column(g, i))],
    ]);
  }

  /// Mở bảng của cuộc họp trong app Ghi chú (sửa, thêm, 👍 ở đó).
  Future<void> _openInTodo() async {
    final app = MiniApps.cached.where((a) => a.nativeScreen == kTodoScreen).firstOrNull;
    if (app == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Chưa mở được app Ghi chú trên máy này'))));
      return;
    }
    await openTodo(context, app, boardId: '${v['board_id']}');
  }

  /// Trang là bảng của cuộc họp trong app Ghi chú: xem nhanh ở đây, sửa trong app Ghi chú.
  Widget _todoViewer() {
    final open = FilledButton.icon(onPressed: _openInTodo, icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text(tr('Mở bảng trong Ghi chú')));
    final notes = [for (final n in (v['notes'] as List? ?? const [])) (n as Map).cast<String, dynamic>()];
    final groups = cols.isEmpty ? [(id: '', name: '')] : [for (final c in cols) (id: '${c['id']}', name: '${c['name']}'), (id: '', name: tr('Chưa xếp cột'))];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('${v['title'] ?? ctx.page.title}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
        if (v['offline'] == true) const Tooltip(message: 'Đang mất kết nối với Ghi chú', child: Icon(Icons.cloud_off_rounded, color: _sub)),
      ]),
      Text(tr('Bảng của cuộc họp · {0} ghi chú · mọi người trong cuộc họp cùng ghi', [notes.length]), style: const TextStyle(color: _sub, fontSize: 12.5)),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: open),
      const SizedBox(height: 12),
      if (notes.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(tr('Chưa có ghi chú. Bấm "Mở bảng trong Ghi chú" để thêm.'), style: const TextStyle(color: _sub))),
      for (final g in groups) ...[
        if (g.name.isNotEmpty && notes.any((n) => (n['col'] ?? '') == g.id || (g.id.isEmpty && !cols.any((c) => c['id'] == n['col']))))
          Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(g.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        for (final n in notes.where((n) => cols.isEmpty || (g.id.isEmpty ? !cols.any((c) => c['id'] == n['col']) : n['col'] == g.id)))
          Padding(padding: const EdgeInsets.only(bottom: 8), child: _note(n, big: false, readOnly: true)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (ctx.onStage) return _stage();
    if (v['mode'] == 'todo') return _todoViewer();
    final left = v['votes_left'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(children: [
          Expanded(child: Text('${v['title'] ?? ctx.page.title}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
          if (left != null) Chip(visualDensity: VisualDensity.compact, label: Text(tr('Còn {0} 👍', [left]))),
          if (manage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              color: const Color(0xFF3A3B3F),
              onSelected: (a) async {
                if (a == 'col') {
                  final name = await _ask(tr('Cột mới'), '');
                  if (name != null && name.isNotEmpty) await _act('col_add', {'name': name});
                } else if (a == 'minutes') {
                  await _act('to_minutes');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'col', child: Text(tr('Thêm cột'), style: const TextStyle(color: Colors.white))),
                if (ctx.page.meeting != null) PopupMenuItem(value: 'minutes', child: Text(tr('Ghi vào Biên bản'), style: const TextStyle(color: Colors.white))),
              ],
            ),
        ]),
      ),
      if (canWrite)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(tr('Nhấn giữ một ghi chú rồi kéo sang cột khác.'), style: const TextStyle(color: _sub, fontSize: 12)),
        ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth < 600 ? box.maxWidth - 48 : 280.0;
            return ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 16),
              children: [for (final c in cols) _column(c, w)],
            );
          },
        ),
      ),
    ]);
  }
}
