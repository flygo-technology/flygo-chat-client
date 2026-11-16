// TeamWork: kiểu xem Danh sách — nhóm theo trạng thái / người làm / nhãn / hạn / ưu tiên, sửa nhanh trạng thái ngay trên
// dòng, chọn nhiều việc để đổi hàng loạt. Điện thoại: dòng gọn hai tầng.
import 'package:flutter/material.dart';

import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'store.dart';
import 'task_widgets.dart';

class TwListView extends StatefulWidget {
  const TwListView({super.key, required this.store, required this.project, required this.filter, required this.onOpen, required this.onCreate});
  final TwStore store;
  final TwProjectFull project;
  final TwFilter filter;
  final void Function(TwTask) onOpen;
  /// Thêm việc vào nhóm trạng thái [statusId].
  final void Function(String? statusId) onCreate;
  @override
  State<TwListView> createState() => _TwListViewState();
}

class _TwListViewState extends State<TwListView> {
  final Set<String> _collapsed = {};
  final Set<String> _sel = {};

  TwStore get store => widget.store;

  Future<void> _bulk(Map<String, dynamic> patch) async {
    final ids = _sel.toList();
    try {
      await store.api.bulk(ids, patch);
      setState(_sel.clear);
      await store.openProject(widget.project.project.id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final wide = twWide(context);
    final p = widget.project;
    final tasks = widget.filter.apply(store.tasksOf(p.project.id), store.today);
    final groups = groupTasks(tasks, widget.filter, p, store.today);
    final head = TextStyle(fontSize: 11.5, color: look.sub, fontWeight: FontWeight.w600);
    return Column(children: [
      if (_sel.isNotEmpty)
        Container(
          height: 44,
          color: look.accentSoft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text('Đã chọn ${_sel.length} việc', style: TextStyle(fontWeight: FontWeight.w600, color: look.accent)),
            const SizedBox(width: 16),
            TextButton.icon(
              key: const ValueKey('bulk-status'),
              onPressed: () async {
                final s = await pickStatus(context, p);
                if (s != null) await _bulk({'status_id': s.id});
              },
              icon: const Icon(Icons.radio_button_checked, size: 18),
              label: const Text('Đổi trạng thái'),
            ),
            TextButton.icon(
              onPressed: () async {
                final v = await pickPriority(context);
                if (v != null) await _bulk({'priority': v});
              },
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Ưu tiên'),
            ),
            const Spacer(),
            TextButton(onPressed: () => setState(_sel.clear), child: const Text('Bỏ chọn')),
          ]),
        ),
      if (wide)
        Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.divider))),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            const SizedBox(width: 50),
            SizedBox(width: 74, child: Text('Mã', style: head)),
            Expanded(child: Text('Tên việc', style: head)),
            SizedBox(width: 180, child: Text('Nhãn', style: head)),
            SizedBox(width: 110, child: Text('Người làm', style: head)),
            SizedBox(width: 90, child: Text('Việc con', style: head)),
            SizedBox(width: 80, child: Text('Hạn', style: head)),
          ]),
        ),
      Expanded(
        child: ListView(padding: EdgeInsets.fromLTRB(wide ? 20 : 12, 0, wide ? 20 : 12, 80), children: [
          for (final g in groups) ...[
            Container(
              key: ValueKey('group-${g.key}'),
              height: 38,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(color: look.surface, borderRadius: BorderRadius.circular(8)),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _collapsed.contains(g.key) ? _collapsed.remove(g.key) : _collapsed.add(g.key)),
                child: Row(children: [
                  const SizedBox(width: 6),
                  Icon(_collapsed.contains(g.key) ? Icons.chevron_right : Icons.expand_more, size: 18, color: look.sub),
                  const SizedBox(width: 4),
                  if (g.leading != null) ...[g.leading!, const SizedBox(width: 8)],
                  if (g.color != null) ...[Container(width: 10, height: 10, decoration: BoxDecoration(color: g.color, shape: BoxShape.circle)), const SizedBox(width: 8)],
                  Text(g.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${g.tasks.length}', style: TextStyle(color: look.sub, fontWeight: FontWeight.w600)),
                  if (g.status?.wip != null) ...[const SizedBox(width: 8), Text('WIP ${g.tasks.length}/${g.status!.wip}', style: TextStyle(fontSize: 11, color: look.sub))],
                  const Spacer(),
                  if (p.project.canEdit && widget.filter.group == 'status')
                    IconButton(tooltip: 'Thêm việc', visualDensity: VisualDensity.compact, icon: const Icon(Icons.add, size: 20), onPressed: () => widget.onCreate(g.status?.id)),
                ]),
              ),
            ),
            if (!_collapsed.contains(g.key))
              for (final t in g.tasks) wide ? _row(t, look) : _phoneRow(t, look),
          ],
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Text(widget.filter.active ? 'Không có việc nào khớp bộ lọc' : 'Chưa có việc nào. Bấm "Việc mới" để thêm.', style: TextStyle(color: look.sub))),
            ),
        ]),
      ),
    ]);
  }

  Widget _statusButton(TwTask t) => InkWell(
        key: ValueKey('row-status-${t.key}'),
        borderRadius: BorderRadius.circular(10),
        onTap: !widget.project.project.canEdit
            ? null
            : () async {
                final s = await pickStatus(context, widget.project, current: t.statusId);
                if (s != null && s.id != t.statusId) await store.updateTask(t, {'status_id': s.id});
              },
        child: Padding(padding: const EdgeInsets.all(4), child: StatusRing(store.statusOf(t))),
      );

  Widget _row(TwTask t, TwLook look) {
    final p = widget.project;
    final late = t.due != null && t.due!.isBefore(store.today) && !(store.statusOf(t)?.isClosed ?? false);
    return InkWell(
      key: ValueKey('row-${t.key}'),
      onTap: () => widget.onOpen(t),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.divider))),
        child: Row(children: [
          SizedBox(
            width: 24,
            child: Checkbox(
              visualDensity: VisualDensity.compact,
              value: _sel.contains(t.id),
              onChanged: (v) => setState(() => v == true ? _sel.add(t.id) : _sel.remove(t.id)),
            ),
          ),
          PriorityIcon(t.priority),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: Text(t.key, style: TextStyle(fontSize: 12, color: look.sub, fontWeight: FontWeight.w600))),
          _statusButton(t),
          const SizedBox(width: 6),
          if (t.parentId != null) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.subdirectory_arrow_right, size: 15, color: look.sub)),
          Expanded(child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
          if (t.run?.active ?? false) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.autorenew_rounded, size: 16, color: look.ai)),
          SizedBox(width: 180, child: Wrap(spacing: 4, clipBehavior: Clip.hardEdge, children: [for (final l in t.labels.take(2)) if (p.label(l) != null) LabelChip(p.label(l)!, dense: true)])),
          SizedBox(width: 110, child: Align(alignment: Alignment.centerLeft, child: TwAvatars(t.assignees, size: 24))),
          SizedBox(
            width: 90,
            child: t.subTotal == 0
                ? null
                : Row(children: [Icon(Icons.checklist_rounded, size: 16, color: look.sub), const SizedBox(width: 4), Text('${t.subDone}/${t.subTotal}', style: TextStyle(fontSize: 12.5, color: look.sub))]),
          ),
          SizedBox(
            width: 80,
            child: Text(t.due == null ? '—' : dShort(t.due!), style: TextStyle(fontSize: 12.5, color: late ? look.red : look.sub, fontWeight: late ? FontWeight.w600 : null)),
          ),
        ]),
      ),
    );
  }

  Widget _phoneRow(TwTask t, TwLook look) {
    final late = t.due != null && t.due!.isBefore(store.today) && !(store.statusOf(t)?.isClosed ?? false);
    return InkWell(
      key: ValueKey('row-${t.key}'),
      onTap: () => widget.onOpen(t),
      onLongPress: () => setState(() => _sel.contains(t.id) ? _sel.remove(t.id) : _sel.add(t.id)),
      child: Container(
        color: _sel.contains(t.id) ? look.accentSoft : null,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: null,
        child: Row(children: [
          _statusButton(t),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text([t.key, if (t.due != null) dRel(t.due!, store.today), if (t.subTotal > 0) '${t.subDone}/${t.subTotal} việc con'].join(' · '),
                  style: TextStyle(fontSize: 12, color: late ? look.red : look.sub)),
            ]),
          ),
          TwAvatars(t.assignees, size: 22, max: 2),
          const SizedBox(width: 6),
          PriorityIcon(t.priority),
        ]),
      ),
    );
  }
}
