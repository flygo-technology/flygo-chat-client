import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import 'model.dart';
import 'note_page.dart' show memberAvatar;
import 'pickers.dart' show showTodoSheet;
import 'store.dart';

// Hộp thoại của bảng ghi chú: tạo bảng, đổi tên, sửa cột, chia sẻ bảng (Sếp 2026-11-21: ghi chú và bảng ghi chú là một).

/// Hỏi một dòng chữ (đổi tên…); null = huỷ.
Future<String?> askText(BuildContext context, String title, String initial) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Huỷ'))),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(tr('Lưu'))),
      ],
    ),
  );
  c.dispose();
  return r;
}

/// Tạo bảng mới (tên + cột tuỳ chọn). Trả về bảng vừa tạo.
Future<TBoard?> newBoardDialog(BuildContext context, TodoStore store) => showTodoSheet<TBoard>(
      context,
      title: tr('Bảng mới'),
      builder: (_) => _NewBoard(store: store),
    );

class _NewBoard extends StatefulWidget {
  const _NewBoard({required this.store});
  final TodoStore store;
  @override
  State<_NewBoard> createState() => _NewBoardState();
}

class _NewBoardState extends State<_NewBoard> {
  final _name = TextEditingController();
  bool _cols = false, _busy = false;
  final _colText = TextEditingController(text: 'Việc cần làm\nĐang làm\nĐã xong');
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _colText.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _err = tr('Hãy đặt tên bảng'));
    setState(() => _busy = true);
    try {
      final b = await widget.store.createBoard(name, columns: _cols ? [for (final l in _colText.text.split('\n')) if (l.trim().isNotEmpty) l.trim()] : const []);
      if (mounted) Navigator.pop(context, b);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: tr('Tên bảng'), hintText: tr('vd: Dự án tòa B, Ý tưởng hội chợ'))),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Chia cột')),
            subtitle: Text(tr('Xếp ghi chú theo cột, vd Việc cần làm / Đang làm / Đã xong')),
            value: _cols,
            onChanged: (v) => setState(() => _cols = v),
          ),
          if (_cols) TextField(controller: _colText, minLines: 2, maxLines: 6, decoration: InputDecoration(labelText: tr('Các cột (mỗi dòng một cột)'))),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(tr('Tạo xong có thể chia sẻ bảng cho mọi người cùng ghi.'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6)))),
            FilledButton(onPressed: _busy ? null : _create, child: Text(tr('Tạo bảng'))),
          ]),
        ]),
      );
}

/// Sửa các cột của bảng (thêm, đổi tên, xoá, đổi thứ tự). null = huỷ.
Future<List<({String id, String name})>?> editColumnsDialog(BuildContext context, TBoard b) => showTodoSheet<List<({String id, String name})>>(
      context,
      title: tr('Các cột của bảng'),
      builder: (_) => _Columns(board: b),
    );

class _Columns extends StatefulWidget {
  const _Columns({required this.board});
  final TBoard board;
  @override
  State<_Columns> createState() => _ColumnsState();
}

class _ColumnsState extends State<_Columns> {
  late final List<(String, TextEditingController)> _cols = [for (final c in widget.board.columns) (c.id, TextEditingController(text: c.name))];

  @override
  void dispose() {
    for (final c in _cols) {
      c.$2.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Flexible(
            child: ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              onReorderItem: (a, b) => setState(() => _cols.insert(b, _cols.removeAt(a))),
              children: [
                for (final (i, c) in _cols.indexed)
                  Row(key: ValueKey(c.$1), children: [
                    ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded))),
                    Expanded(child: TextField(controller: c.$2, decoration: InputDecoration(isDense: true, hintText: tr('Tên cột')))),
                    IconButton(onPressed: () => setState(() => _cols.removeAt(i).$2.dispose()), icon: const Icon(Icons.close_rounded)),
                  ]),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _cols.length >= 12 ? null : () => setState(() => _cols.add(('c${DateTime.now().microsecondsSinceEpoch}', TextEditingController()))),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Thêm cột')),
          ),
          Row(children: [
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'))),
            FilledButton(
              onPressed: () => Navigator.pop(context, [
                for (final c in _cols)
                  if (c.$2.text.trim().isNotEmpty) (id: c.$1.startsWith('c1') && c.$1.length > 12 ? '' : c.$1, name: c.$2.text.trim()),
              ]),
              child: Text(tr('Lưu')),
            ),
          ]),
        ]),
      );
}

/// Chia sẻ bảng: người tham gia thấy và cùng ghi mọi ghi chú trong bảng. Trả về danh sách người (trừ chủ bảng); null = huỷ.
Future<List<TMember>?> shareBoardDialog(BuildContext context, TodoStore store, TBoard b) => showTodoSheet<List<TMember>>(
      context,
      title: tr('Người tham gia bảng'),
      width: 480,
      builder: (_) => _ShareBoard(store: store, board: b),
    );

class _ShareBoard extends StatefulWidget {
  const _ShareBoard({required this.store, required this.board});
  final TodoStore store;
  final TBoard board;
  @override
  State<_ShareBoard> createState() => _ShareBoardState();
}

class _ShareBoardState extends State<_ShareBoard> {
  late List<TMember> _others = widget.board.members.where((m) => m.role != 'owner').toList();
  final _q = TextEditingController();
  List<TMember> _found = [];
  Timer? _deb;

  @override
  void dispose() {
    _q.dispose();
    _deb?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _deb?.cancel();
    if (q.trim().isEmpty) return setState(() => _found = []);
    _deb = Timer(const Duration(milliseconds: 300), () async {
      try {
        final j = await widget.store.api.get('/api/people?q=${Uri.encodeQueryComponent(q.trim())}');
        if (!mounted) return;
        setState(() => _found = [for (final p in j['people'] as List? ?? const []) TMember('${p['id']}', '${p['name']}', 'editor')]);
      } catch (_) {
        if (mounted) setState(() => _found = []);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.board.members.where((m) => m.role == 'owner').firstOrNull;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          if (owner != null) ListTile(leading: memberAvatar(owner.name, 16), title: Text(owner.name), subtitle: Text(tr('Chủ bảng'))),
          for (final m in _others)
            ListTile(
              leading: memberAvatar(m.name, 16),
              title: Text(m.name),
              trailing: DropdownButton<String>(
                value: m.role,
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: 'editor', child: Text(tr('Cùng ghi'))),
                  DropdownMenuItem(value: 'viewer', child: Text(tr('Chỉ xem'))),
                  DropdownMenuItem(value: 'remove', child: Text(tr('Bỏ khỏi bảng'), style: const TextStyle(color: Colors.red))),
                ],
                onChanged: (v) => setState(() => _others =
                    v == 'remove' ? _others.where((x) => x.id != m.id).toList() : [for (final x in _others) x.id == m.id ? TMember(x.id, x.name, v!) : x]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(hintText: tr('Tên hoặc username'), prefixIcon: const Icon(Icons.person_add_alt_1_rounded), isDense: true),
              onChanged: _search,
            ),
          ),
          for (final p in _found.where((p) => !_others.any((o) => o.id == p.id) && p.id != owner?.id))
            ListTile(
              dense: true,
              leading: memberAvatar(p.name, 14),
              title: Text(p.name),
              trailing: const Icon(Icons.add_rounded),
              onTap: () => setState(() {
                _others = [..._others, p];
                _q.clear();
                _found = [];
              }),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: Row(children: [
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(context, _others), child: Text(tr('Lưu'))),
        ]),
      ),
    ]);
  }
}
