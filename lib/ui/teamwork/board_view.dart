// TeamWork: Kanban — mỗi trạng thái một cột (màu, số việc, giới hạn WIP đỏ khi đầy). Kéo thẻ giữa các cột và trong cột
// (thứ tự lưu chung cho cả dự án). Điện thoại: thanh trạng thái phía trên, vuốt ngang qua từng cột, giữ thẻ để kéo sang
// trạng thái khác trên thanh. Kéo vào trạng thái "bắt đầu" thì agent được giao bắt đầu làm (máy chủ tạo lượt chạy).
import 'package:flutter/material.dart';

import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'store.dart';
import 'task_widgets.dart';

class TwBoardView extends StatefulWidget {
  const TwBoardView({super.key, required this.store, required this.project, required this.filter, required this.onOpen, required this.onCreate});
  final TwStore store;
  final TwProjectFull project;
  final TwFilter filter;
  final void Function(TwTask) onOpen;
  final void Function(String? statusId) onCreate;
  @override
  State<TwBoardView> createState() => _TwBoardViewState();
}

class _TwBoardViewState extends State<TwBoardView> {
  /// Chỗ thả đang rê tới: (id cột, id thẻ đứng sau chỗ thả hoặc null = cuối cột).
  (String, String?)? _hover;
  final Set<String> _folded = {};
  int _page = 0;
  late final PageController _pc = PageController(viewportFraction: 1);

  TwStore get store => widget.store;
  TwProjectFull get p => widget.project;

  List<TwTask> _column(String sid, List<TwTask> all) => all.where((t) => t.statusId == sid && t.parentId == null).toList()..sort(byRank);

  /// Thả [t] vào cột [sid], trước thẻ [beforeId] (null = cuối cột).
  Future<void> _drop(TwTask t, String sid, String? beforeId, List<TwTask> all) async {
    setState(() => _hover = null);
    final s = p.status(sid);
    if (s == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (s.adminOnly && !p.project.canAdmin && t.statusId != sid) {
      messenger.showSnackBar(SnackBar(content: Text('Chỉ Quản trị được chuyển việc sang "${s.name}"')));
      return;
    }
    final col = _column(sid, all).where((x) => x.id != t.id).toList();
    if (t.statusId != sid && s.wip != null && col.length >= s.wip!) {
      final ok = await confirm(context, 'Cột "${s.name}" đã đủ WIP', 'Giới hạn ${s.wip} việc đang làm. Vẫn chuyển việc này vào?', ok: 'Vẫn chuyển');
      if (!ok) return;
    }
    var closeSubs = false;
    if (t.statusId != sid && s.isDone && t.subTotal > t.subDone && s.closeSubtasksPrompt && mounted) {
      closeSubs = await confirm(context, 'Còn ${t.subTotal - t.subDone} việc con chưa xong', 'Đóng luôn các việc con còn mở?', ok: 'Đóng luôn');
    }
    final bi = beforeId == null ? -1 : col.indexWhere((x) => x.id == beforeId);
    final before = bi < 0 ? null : col[bi];
    final after = bi < 0 ? (col.isEmpty ? null : col.last) : (bi == 0 ? null : col[bi - 1]);
    final toStart = t.statusId != sid && s.isStart && t.hasAgent && !(t.run?.active ?? false);
    try {
      await store.moveTask(t, statusId: t.statusId == sid ? null : sid, before: before, after: after);
      if (closeSubs) {
        final kids = all.where((x) => x.parentId == t.id && !(p.status(x.statusId)?.isClosed ?? false)).map((x) => x.id).toList();
        if (kids.isNotEmpty) await store.api.bulk(kids, {'status_id': sid});
      }
      if (toStart) messenger.showSnackBar(const SnackBar(content: Text('Việc vào trạng thái bắt đầu: agent được giao sẽ bắt đầu làm')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _draggable(TwTask t, {required Widget child, required double width}) {
    final feedback = Material(color: Colors.transparent, child: SizedBox(width: width, child: Transform.rotate(angle: .04, child: TaskCard(task: t, store: store, dragging: true))));
    final placeholder = Opacity(opacity: .35, child: child);
    if (!p.project.canEdit) return child;
    return twWide(context)
        ? Draggable<TwTask>(data: t, feedback: feedback, childWhenDragging: placeholder, child: child)
        : LongPressDraggable<TwTask>(data: t, feedback: feedback, childWhenDragging: placeholder, child: child);
  }

  Widget _ghost(TwLook look) => Container(
        height: 64,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: look.accentSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: look.accent, width: 1.5)),
      );

  Widget _columnBody(TwStatus s, List<TwTask> cards, List<TwTask> all, TwLook look, double cardWidth) {
    return DragTarget<TwTask>(
      onWillAcceptWithDetails: (_) {
        if (_hover?.$1 != s.id || _hover?.$2 != null) setState(() => _hover = (s.id, null));
        return true;
      },
      onLeave: (_) {
        if (_hover?.$1 == s.id && _hover?.$2 == null) setState(() => _hover = null);
      },
      onAcceptWithDetails: (d) => _drop(d.data, s.id, null, all),
      builder: (context, cand, _) => ListView(
        key: ValueKey('col-${s.id}'),
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          for (final t in cards)
            DragTarget<TwTask>(
              onWillAcceptWithDetails: (d) {
                if (d.data.id == t.id) return false;
                if (_hover?.$1 != s.id || _hover?.$2 != t.id) setState(() => _hover = (s.id, t.id));
                return true;
              },
              onAcceptWithDetails: (d) => _drop(d.data, s.id, t.id, all),
              builder: (context, _, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                if (_hover == (s.id, t.id)) _ghost(look),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _draggable(t, width: cardWidth, child: TaskCard(key: ValueKey('card-${t.key}'), task: t, store: store, onTap: () => widget.onOpen(t))),
                ),
              ]),
            ),
          if (_hover == (s.id, null) && cand.isNotEmpty) _ghost(look),
          if (p.project.canEdit && s.category != 'done' && s.category != 'closed')
            TextButton.icon(
              key: ValueKey('add-in-${s.id}'),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: look.sub),
              onPressed: () => widget.onCreate(s.id),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Thêm việc'),
            ),
        ],
      ),
    );
  }

  Widget _header(TwStatus s, int n, TwLook look) {
    final over = s.wip != null && n >= s.wip!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Row(children: [
        StatusRing(s),
        const SizedBox(width: 8),
        Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 6),
        Text('$n', style: TextStyle(color: look.sub, fontWeight: FontWeight.w600, fontSize: 12)),
        if (s.isStart) Padding(padding: const EdgeInsets.only(left: 6), child: Tooltip(message: 'Trạng thái bắt đầu: agent chạy khi việc vào đây', child: Icon(Icons.play_circle_outline, size: 16, color: look.ai))),
        const Spacer(),
        if (s.wip != null)
          Container(
            key: ValueKey('wip-${s.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: over ? look.red.withValues(alpha: .14) : look.surface2, borderRadius: BorderRadius.circular(6)),
            child: Text('WIP $n/${s.wip}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: over ? look.red : look.sub)),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: _folded.contains(s.id) ? 'Mở cột' : 'Gập cột',
          icon: Icon(_folded.contains(s.id) ? Icons.unfold_more : Icons.unfold_less, size: 18, color: look.sub),
          onPressed: () => setState(() => _folded.contains(s.id) ? _folded.remove(s.id) : _folded.add(s.id)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final all = widget.filter.apply(store.tasksOf(p.project.id), store.today);
    if (!twWide(context)) return _phone(all, look);
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        for (final s in p.statuses)
          () {
            final cards = _column(s.id, all);
            if (_folded.contains(s.id)) {
              return Container(
                width: 44,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(color: look.surface, borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: () => setState(() => _folded.remove(s.id)),
                  child: Column(children: [
                    const SizedBox(height: 12),
                    StatusRing(s),
                    const SizedBox(height: 8),
                    Text('${cards.length}', style: TextStyle(color: look.sub, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    RotatedBox(quarterTurns: 1, child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                ),
              );
            }
            return Container(
              key: ValueKey('column-${s.id}'),
              width: 282,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(color: look.surface, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [_header(s, cards.length, look), Expanded(child: _columnBody(s, cards, all, look, 264))]),
            );
          }(),
      ],
    );
  }

  Widget _phone(List<TwTask> all, TwLook look) {
    final statuses = p.statuses;
    if (statuses.isEmpty) return const SizedBox();
    final page = _page.clamp(0, statuses.length - 1);
    return Column(children: [
      SizedBox(
        height: 40,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          for (var i = 0; i < statuses.length; i++)
            DragTarget<TwTask>(
              onWillAcceptWithDetails: (d) => d.data.statusId != statuses[i].id,
              onAcceptWithDetails: (d) => _drop(d.data, statuses[i].id, null, all),
              builder: (context, cand, _) => InkWell(
                key: ValueKey('ptab-${statuses[i].id}'),
                onTap: () => _pc.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: cand.isNotEmpty ? look.accentSoft : null,
                    border: Border(bottom: BorderSide(color: i == page ? look.accent : Colors.transparent, width: 2)),
                  ),
                  child: Row(children: [
                    StatusRing(statuses[i]),
                    const SizedBox(width: 5),
                    Text('${statuses[i].name} ${_column(statuses[i].id, all).length}',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: i == page ? look.accent : look.sub)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      Divider(height: 1, color: look.divider),
      Expanded(
        child: Container(
          color: look.surface,
          child: PageView(
            controller: _pc,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (final s in statuses)
                Column(children: [
                  _header(s, _column(s.id, all).length, look),
                  Expanded(child: _columnBody(s, _column(s.id, all), all, look, MediaQuery.sizeOf(context).width - 40)),
                ]),
            ],
          ),
        ),
      ),
    ]);
  }
}
