// Todo (vn.flygo.todo): trang chủ kiểu Google Keep — thanh "Ghi chú nhanh…", lưới thẻ (masonry trên máy tính, 2 cột trên
// điện thoại), mục Đã ghim ở trên, kéo thả để sắp xếp; menu: Ghi chú, Lời nhắc, nhãn, Lưu trữ, Thùng rác.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart' show serverKey;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../desk_tabs.dart' show DeskTabScope;
import '../theme.dart' show toast;
import 'api.dart';
import 'look.dart';
import 'model.dart';
import 'note_page.dart';
import 'pickers.dart';
import 'store.dart';

const kTodoScreen = 'todo';

/// Mở Todo (từ ô trong mục Chính, hoặc từ tin nhắc của bot với [noteId]).
Future<void> openTodo(BuildContext context, MiniApp app, {String? noteId}) async {
  final state = context.read<AppState>();
  final nav = Navigator.of(context);
  final tab = DeskTabScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id = await FlygoId.current(state.token);
    if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
    final api = TodoApi(base: app.baseUrl, id: id);
    final store = TodoStore(api, cacheKey: '${serverKey}_${state.me?.id ?? 'me'}'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_'));
    await nav.push(AppPageRoute(builder: (_) => TodoHome(store: store, title: app.name, openNoteId: noteId)));
    // Đóng Todo trong một tab máy tính: tab về lại tên ứng dụng.
    tab?.onTitle?.call(null);
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

class TodoHome extends StatefulWidget {
  const TodoHome({super.key, required this.store, this.title = 'Todo', this.openNoteId, this.ownsStore = true});
  final TodoStore store;
  final String title;
  final String? openNoteId;
  final bool ownsStore;
  @override
  State<TodoHome> createState() => _TodoHomeState();
}

class _TodoHomeState extends State<TodoHome> with WidgetsBindingObserver {
  String _section = 'notes';
  final _q = TextEditingController();
  bool _searching = false, _list = false, _railOpen = true;
  final _scaffold = GlobalKey<ScaffoldState>();

  TodoStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_changed);
    store.start().then((_) => _openFromLink());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_changed);
    if (widget.ownsStore) store.dispose();
    _q.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) store.sync();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _openFromLink() {
    final id = widget.openNoteId;
    if (id == null || !mounted) return;
    final n = store.notes[id];
    if (n == null) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không tìm thấy ghi chú này (có thể đã bị xoá hoặc bỏ chia sẻ)'))));
      return;
    }
    if (n.reminder != null) setState(() => _section = 'reminders');
    openNote(context, store, n);
  }

  String get _sectionTitle => switch (_section) {
        'notes' => widget.title,
        'reminders' => tr('Lời nhắc'),
        'archive' => tr('Lưu trữ'),
        'trash' => tr('Thùng rác'),
        _ => store.labelName(_section.substring(6)),
      };

  void _new({String kind = 'note', bool image = false}) {
    final n = store.draft(kind: kind);
    if (_section.startsWith('label:')) n.labels = [_section.substring(6)];
    if (_section == 'reminders') n.reminder = TReminder(DateTime.now().add(const Duration(hours: 1)).copyWith(minute: 0, second: 0).millisecondsSinceEpoch);
    openNote(context, store, n, pickImage: image);
  }

  // ------------------------------------------------------------ menu
  Widget _menu({required bool compact}) {
    final pal = Theme.of(context).colorScheme;
    Widget item(String id, IconData icon, String label) {
      final on = _section == id;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Material(
          color: on ? const Color(0xFFFEEFC3).withValues(alpha: isDark(context) ? .25 : 1) : Colors.transparent,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(30)),
          child: InkWell(
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(30)),
            onTap: () {
              setState(() => _section = id);
              if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22, vertical: 13),
              child: Row(children: [
                Icon(icon, size: 22, color: pal.onSurface.withValues(alpha: .8)),
                if (!compact) ...[const SizedBox(width: 20), Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: on ? FontWeight.w600 : FontWeight.w400)))],
              ]),
            ),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.only(top: 8), children: [
      item('notes', Icons.lightbulb_outline_rounded, tr('Ghi chú')),
      item('reminders', Icons.notifications_none_rounded, tr('Lời nhắc')),
      for (final l in store.labels) item('label:${l.id}', Icons.label_outline_rounded, l.name),
      Padding(
        padding: const EdgeInsets.only(right: 10),
        child: InkWell(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(30)),
          onTap: () => editLabels(context, store).then((_) => setState(() {})),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22, vertical: 13),
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 22, color: pal.onSurface.withValues(alpha: .8)),
              if (!compact) ...[const SizedBox(width: 20), Expanded(child: Text(tr('Chỉnh sửa nhãn'), overflow: TextOverflow.ellipsis))],
            ]),
          ),
        ),
      ),
      item('archive', Icons.archive_outlined, tr('Lưu trữ')),
      item('trash', Icons.delete_outline_rounded, tr('Thùng rác')),
      // Quay về Flygo Chat (Sếp, 2026-11-12): như nút đóng ở góc trên bên phải.
      if (Navigator.of(context).canPop()) ...[
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: InkWell(
            key: const ValueKey('back-to-chat'),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(30)),
            onTap: _close,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22, vertical: 13),
              child: Row(children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 22, color: pal.onSurface.withValues(alpha: .8)),
                if (!compact) ...[const SizedBox(width: 20), Expanded(child: Text(tr('Quay về app Flygo Chat'), overflow: TextOverflow.ellipsis))],
              ]),
            ),
          ),
        ),
      ],
    ]);
  }

  // ------------------------------------------------------------ lưới
  Widget _quickBar() {
    final pal = Theme.of(context).colorScheme;
    final sub = pal.onSurface.withValues(alpha: .65);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Material(
          elevation: 2,
          shadowColor: Colors.black38,
          color: noteColor('default', isDark(context)),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: const ValueKey('quick-note'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => _new(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
              child: Row(children: [
                Expanded(child: Text(tr('Ghi chú nhanh…'), style: TextStyle(fontSize: 16, color: sub, fontWeight: FontWeight.w500))),
                IconButton(tooltip: tr('Danh sách mới'), icon: Icon(Icons.check_box_outlined, color: sub), onPressed: () => _new(kind: 'list')),
                IconButton(tooltip: tr('Ghi chú có ảnh'), icon: Icon(Icons.image_outlined, color: sub), onPressed: () => _new(image: true)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(TNote n, List<TNote> group, double width) {
    final dark = isDark(context);
    final fg = dark ? Colors.white : const Color(0xFF202124);
    final sub = fg.withValues(alpha: .7);
    final imgs = n.files.where((f) => f.isImage).take(3).toList();
    final others = n.files.where((f) => !f.isImage).toList();
    final blocks = n.kind == 'list' ? [...n.blocks.where((b) => !b.done), ...n.blocks.where((b) => b.done)] : n.blocks;
    final shown = blocks.take(n.kind == 'list' ? 8 : 12).toList();
    final hidden = blocks.length - shown.length;
    final doneCount = n.kind == 'list' ? n.blocks.where((b) => b.done).length : 0;
    final style = TextStyle(fontSize: 14.5, height: 1.4, color: fg);
    final card = NoteBackground(
      color: n.color,
      bg: n.bg,
      radius: 10,
      border: n.color == 'default' && n.bg == null ? (dark ? const Color(0xFF5F6368) : const Color(0xFFE0E0E0)) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (imgs.isNotEmpty)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: imgs.length == 1
                ? ConstrainedBox(constraints: const BoxConstraints(maxHeight: 260), child: TodoImage(api: store.api, file: imgs.first, fit: BoxFit.cover))
                : SizedBox(height: 110, child: Row(children: [for (final f in imgs) Expanded(child: Padding(padding: const EdgeInsets.only(right: 1), child: TodoImage(api: store.api, file: f)))])),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: n.title.isEmpty
                    ? const SizedBox()
                    : Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(n.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg))),
              ),
              if (n.pinned) Icon(Icons.push_pin_rounded, size: 16, color: sub),
            ]),
            for (var i = 0; i < shown.length; i++)
              blockPreview(shown, i, style, dark, onTick: n.canEdit && !n.trashed ? (b, v) => _tick(n, b, v) : null),
            if (hidden > 0 || (n.kind == 'list' && doneCount > 0 && shown.every((b) => !b.done)))
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(n.kind == 'list' && doneCount > 0 ? tr('+ {0} mục đã xong', [doneCount]) : '…', style: TextStyle(color: sub, fontSize: 13))),
            if (others.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final f in others.take(3))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: fg.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(fileIcon(f), size: 14, color: sub),
                        const SizedBox(width: 4),
                        ConstrainedBox(constraints: BoxConstraints(maxWidth: width - 80), child: Text(f.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg))),
                      ]),
                    ),
                  if (others.length > 3) Text('+${others.length - 3}', style: TextStyle(fontSize: 12, color: sub)),
                ]),
              ),
            if (n.reminder != null || n.labels.isNotEmpty || n.others.isNotEmpty || (!n.isOwner && n.owner != null))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (n.reminder != null)
                    _pill(n.reminder!.repeat != null ? Icons.repeat_rounded : Icons.alarm_rounded, reminderLabel(n.reminder!), fg, done: n.reminder!.done),
                  for (final l in n.labels)
                    if (store.labelName(l).isNotEmpty) _pill(null, store.labelName(l), fg),
                  if (n.role == 'viewer') _pill(Icons.visibility_outlined, tr('Chỉ xem'), fg),
                  for (final m in [if (!n.isOwner && n.owner != null) n.owner!, ...n.others.where((m) => m.id != store.meId)].take(4)) Tooltip(message: m.name, child: memberAvatar(m.name, 11)),
                ]),
              ),
          ]),
        ),
      ]),
    );
    final touch = _touch;
    final canDrag = !(n.trashed || _searching && _q.text.isNotEmpty);
    // Bấm giữ (điện thoại, khi không kéo được) / chuột phải / bấm giữ chuột (máy tính): menu Ghim, Lưu trữ, Xoá (Sếp, 2026-11-11).
    final tap = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openNote(context, store, n),
      onLongPress: touch && canDrag ? null : () => _actions(n),
      onSecondaryTapUp: (d) => _actions(n, at: d.globalPosition),
      child: card,
    );
    if (!canDrag) return _wrapKey(n, tap);
    // Kéo thả: máy tính kéo bằng chuột ngay; điện thoại bấm giữ rồi kéo. Điện thoại bấm giữ rồi thả tay (không kéo) thì mở menu.
    final feedback = Material(color: Colors.transparent, child: SizedBox(width: width, child: Opacity(opacity: .9, child: card)));
    final drag = !touch
        ? Draggable<String>(data: n.id, feedback: feedback, childWhenDragging: Opacity(opacity: .25, child: tap), child: tap)
        : Listener(
            onPointerDown: (e) => _down = _last = e.position,
            onPointerMove: (e) => _last = e.position,
            child: LongPressDraggable<String>(
              data: n.id,
              feedback: feedback,
              childWhenDragging: Opacity(opacity: .25, child: tap),
              onDragEnd: (_) {
                if (_down != null && _last != null && (_last! - _down!).distance < 12) _actions(n);
              },
              child: tap,
            ),
          );
    return _wrapKey(
      n,
      DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != n.id && group.any((x) => x.id == d.data),
        onAcceptWithDetails: (d) {
          final moving = store.notes[d.data];
          if (moving == null) return;
          // Thả lên thẻ: đứng trước thẻ đó nếu kéo từ dưới lên, sau thẻ đó nếu kéo từ trên xuống.
          final from = group.indexWhere((x) => x.id == moving.id), to = group.indexWhere((x) => x.id == n.id);
          store.moveBefore(moving, from < to ? (to + 1 < group.length ? group[to + 1] : null) : n, group);
        },
        builder: (c, cand, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: cand.isNotEmpty ? const Color(0xFFE8A100) : Colors.transparent, width: 2)),
          child: drag,
        ),
      ),
    );
  }

  /// Đóng Todo, về màn hình Flygo Chat trước đó (điện thoại: tab / trang trước; máy tính: nội dung trước của tab).
  void _close() {
    final nav = Navigator.of(context);
    if (!(_scaffold.currentState?.isDrawerOpen ?? false)) {
      nav.maybePop();
      return;
    }
    // Menu bên trái đang mở: đóng menu trước, khung sau mới đóng trang (pop cùng lúc chỉ đóng menu).
    nav.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => nav.maybePop());
  }

  Offset? _down, _last;
  bool get _touch => const {TargetPlatform.android, TargetPlatform.iOS}.contains(Theme.of(context).platform);

  /// Menu thao tác nhanh trên thẻ: ghim / bỏ ghim, lưu trữ / bỏ lưu trữ, xoá (vào thùng rác, có hoàn tác); trong thùng rác:
  /// khôi phục, xoá vĩnh viễn.
  Future<void> _actions(TNote n, {Offset? at}) async {
    final items = <(String, IconData, String)>[
      if (n.trashed) ...[
        ('restore', Icons.restore_from_trash_outlined, tr('Khôi phục')),
        if (n.isOwner) ('forever', Icons.delete_forever_outlined, tr('Xoá vĩnh viễn')),
      ] else ...[
        ('pin', n.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, n.pinned ? tr('Bỏ ghim') : tr('Ghim')),
        ('archive', n.archived ? Icons.unarchive_outlined : Icons.archive_outlined, n.archived ? tr('Bỏ lưu trữ') : tr('Lưu trữ')),
        ('trash', Icons.delete_outline_rounded, n.isOwner ? tr('Xoá') : tr('Xoá khỏi danh sách của tôi')),
      ],
    ];
    String? v;
    if (at != null) {
      v = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
        items: [for (final (id, icon, label) in items) PopupMenuItem(value: id, child: ListTile(dense: true, leading: Icon(icon), title: Text(label)))],
      );
    } else {
      v = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(n.title.isNotEmpty ? n.title : (n.blocks.map((b) => b.text).firstWhere((x) => x.trim().isNotEmpty, orElse: () => tr('Ghi chú'))),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            for (final (id, icon, label) in items) ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(c, id)),
            const SizedBox(height: 8),
          ]),
        ),
      );
    }
    if (v == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    void undoable(String text, Map<String, dynamic> undo) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: SnackBarAction(label: tr('Hoàn tác'), onPressed: () => store.put(n, undo))));
    switch (v) {
      case 'pin':
        store.put(n, {'pinned': !n.pinned});
      case 'archive':
        final was = n.archived, pinned = n.pinned;
        store.put(n, {'archived': !was});
        undoable(was ? tr('Đã bỏ lưu trữ ghi chú') : tr('Đã lưu trữ ghi chú'), {'archived': was, 'pinned': pinned});
      case 'trash':
        store.put(n, {'trashed': true});
        undoable(tr('Đã chuyển ghi chú vào thùng rác'), {'trashed': false});
      case 'restore':
        store.put(n, {'trashed': false});
      case 'forever':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            content: Text(tr('Xoá vĩnh viễn ghi chú này? Không khôi phục được.')),
            actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Xoá')))],
          ),
        );
        if (ok == true) store.remove(n);
    }
  }

  Widget _wrapKey(TNote n, Widget w) => KeyedSubtree(key: ValueKey('card-${n.id}'), child: w);

  Widget _pill(IconData? icon, String text, Color fg, {bool done = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: fg.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg.withValues(alpha: .7)), const SizedBox(width: 4)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg, decoration: done ? TextDecoration.lineThrough : null))),
        ]),
      );

  void _tick(TNote n, TBlock b, bool v) {
    final blocks = [for (final x in n.blocks) x.id == b.id ? (x.clone()..done = v) : x.clone()];
    store.put(n, {'blocks': [for (final x in blocks) x.toJson()]});
  }

  /// Lưới masonry: chia thẻ vào cột thấp nhất (ước lượng chiều cao theo nội dung), giữ thứ tự đọc trái → phải.
  Widget _grid(List<TNote> notes, double width) {
    if (notes.isEmpty) return const SizedBox.shrink();
    const gap = 12.0;
    final cols = _list ? 1 : (width < 600 ? 2 : (width / 250).floor().clamp(2, 6));
    final cw = _list ? width.clamp(0, 600).toDouble() : (width - gap * (cols - 1)) / cols;
    final cards = <List<TNote>>[for (var i = 0; i < cols; i++) []];
    final heights = List<double>.filled(cols, 0);
    for (final n in notes) {
      var k = 0;
      for (var i = 1; i < cols; i++) {
        if (heights[i] < heights[k] - 1) k = i;
      }
      cards[k].add(n);
      heights[k] += _estimate(n, cw) + gap;
    }
    return Center(
      child: SizedBox(
        width: _list ? cw : width,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < cols; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            SizedBox(width: cw, child: Column(children: [for (final n in cards[i]) Padding(padding: const EdgeInsets.only(bottom: gap), child: _card(n, notes, cw))])),
          ],
        ]),
      ),
    );
  }

  double _estimate(TNote n, double w) {
    final perLine = (w - 28) / 7.6;
    var h = 24.0;
    if (n.files.any((f) => f.isImage)) h += n.files.where((f) => f.isImage).length == 1 ? w * .66 : 110;
    if (n.title.isNotEmpty) h += 26 * (n.title.length / perLine).ceil().clamp(1, 3);
    for (final b in n.blocks.take(12)) {
      h += 20.0 * (b.text.length / perLine).ceil().clamp(1, b.t == 'p' ? 6 : 3);
    }
    if (n.reminder != null || n.labels.isNotEmpty || n.others.isNotEmpty) h += 30;
    return h;
  }

  Widget _empty() {
    final sub = Theme.of(context).colorScheme.onSurface.withValues(alpha: .45);
    final (icon, text) = switch (_section) {
      'reminders' => (Icons.notifications_none_rounded, tr('Ghi chú có lời nhắc sẽ hiện ở đây')),
      'archive' => (Icons.archive_outlined, tr('Ghi chú đã lưu trữ sẽ hiện ở đây')),
      'trash' => (Icons.delete_outline_rounded, tr('Thùng rác trống')),
      _ when _section.startsWith('label:') => (Icons.label_outline_rounded, tr('Chưa có ghi chú nào gắn nhãn này')),
      _ => (Icons.lightbulb_outline_rounded, tr('Ghi chú bạn thêm sẽ hiện ở đây')),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(children: [Icon(icon, size: 110, color: sub.withValues(alpha: .25)), const SizedBox(height: 16), Text(text, style: TextStyle(fontSize: 18, color: sub))]),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 0, 10),
        child: Text(s, style: TextStyle(fontSize: 11.5, letterSpacing: .8, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6))),
      );

  Widget _content(double width) {
    final all = store.view(_section, q: _searching ? _q.text : '');
    final pad = width < 600 ? 10.0 : 24.0;
    final inner = width - 2 * pad;
    final children = <Widget>[];
    final canCreate = (_section == 'notes' || _section == 'reminders' || _section.startsWith('label:')) && !(_searching && _q.text.isNotEmpty);
    if (canCreate) children.addAll([const SizedBox(height: 12), _quickBar()]);
    if (_section == 'trash' && all.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text(tr('Ghi chú trong thùng rác sẽ bị xoá sau 7 ngày.'), style: const TextStyle(fontStyle: FontStyle.italic))),
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  content: Text(tr('Dọn sạch thùng rác? Mọi ghi chú trong thùng rác sẽ bị xoá vĩnh viễn.')),
                  actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Dọn sạch')))],
                ),
              );
              if (ok == true) store.emptyTrash();
            },
            child: Text(tr('Dọn sạch thùng rác')),
          ),
        ]),
      ));
    }
    if (all.isEmpty) {
      children.add(store.loaded || store.offline || store.error != null ? _empty() : const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator())));
    } else if (_section == 'notes' || _section.startsWith('label:')) {
      final pinned = all.where((n) => n.pinned).toList(), rest = all.where((n) => !n.pinned).toList();
      if (pinned.isNotEmpty) children.addAll([_label(tr('ĐÃ GHIM')), _grid(pinned, inner)]);
      if (rest.isNotEmpty) children.addAll([if (pinned.isNotEmpty) _label(tr('KHÁC')) else const SizedBox(height: 20), _grid(rest, inner)]);
    } else {
      children.addAll([const SizedBox(height: 20), _grid(all, inner)]);
    }
    return RefreshIndicator(
      onRefresh: store.sync,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (store.offline)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.cloud_off_rounded, size: 16),
                const SizedBox(width: 6),
                Text(store.pending > 0 ? tr('Đang ngoại tuyến · {0} thay đổi chờ đồng bộ', [store.pending]) : tr('Đang ngoại tuyến')),
              ]),
            ),
          ...children,
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar(bool wide) {
    final pal = Theme.of(context).colorScheme;
    final search = Container(
      height: 44,
      constraints: const BoxConstraints(maxWidth: 720),
      decoration: BoxDecoration(color: pal.onSurface.withValues(alpha: .07), borderRadius: BorderRadius.circular(10)),
      child: TextField(
        controller: _q,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: tr('Tìm kiếm'),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _q.clear())),
          isDense: true,
        ),
        onTap: () => setState(() => _searching = true),
        onChanged: (_) => setState(() => _searching = true),
      ),
    );
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        tooltip: tr('Menu'),
        icon: const Icon(Icons.menu_rounded),
        onPressed: () => wide ? setState(() => _railOpen = !_railOpen) : _scaffold.currentState?.openDrawer(),
      ),
      title: Row(children: [
        if (wide || !_searching) ...[
          if (_section == 'notes') Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(color: const Color(0xFFE8A100), borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.sticky_note_2_rounded, color: Colors.white, size: 22),
          ),
          Text(_sectionTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
          const SizedBox(width: 20),
        ],
        if (wide || _searching) Expanded(child: search) else const Spacer(),
      ]),
      actions: [
        if (!wide && !_searching) IconButton(tooltip: tr('Tìm kiếm'), icon: const Icon(Icons.search_rounded), onPressed: () => setState(() => _searching = true)),
        if (!wide && _searching) IconButton(tooltip: tr('Đóng tìm kiếm'), icon: const Icon(Icons.close_rounded), onPressed: () => setState(() {
              _searching = false;
              _q.clear();
            })),
        IconButton(
          tooltip: store.syncing ? tr('Đang đồng bộ') : tr('Làm mới'),
          icon: store.syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(store.offline ? Icons.cloud_off_rounded : Icons.refresh_rounded),
          onPressed: store.sync,
        ),
        IconButton(tooltip: _list ? tr('Dạng lưới') : tr('Dạng danh sách'), icon: Icon(_list ? Icons.grid_view_rounded : Icons.view_agenda_outlined), onPressed: () => setState(() => _list = !_list)),
        // Nút đóng app ở góc trên bên phải như các mini app khác (Sếp, 2026-11-11).
        if (Navigator.of(context).canPop()) IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: _close),
        const SizedBox(width: 6),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (c, box) {
      final wide = box.maxWidth >= 840;
      final body = wide
          ? Row(children: [
              AnimatedContainer(duration: const Duration(milliseconds: 150), width: _railOpen ? 260 : 68, child: _menu(compact: !_railOpen)),
              Expanded(child: LayoutBuilder(builder: (c, b) => _content(b.maxWidth))),
            ])
          : _content(box.maxWidth);
      return Scaffold(
        key: _scaffold,
        appBar: _appBar(wide),
        drawer: wide ? null : Drawer(child: SafeArea(child: _menu(compact: false))),
        body: body,
        floatingActionButton: !wide && (_section == 'notes' || _section.startsWith('label:') || _section == 'reminders')
            ? FloatingActionButton(
                tooltip: tr('Ghi chú mới'),
                backgroundColor: const Color(0xFFE8A100),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onPressed: () => _new(),
                child: const Icon(Icons.add_rounded, size: 30),
              )
            : null,
      );
    });
  }
}
