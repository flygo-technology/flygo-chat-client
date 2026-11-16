// TeamWork: bộ lọc / sắp xếp / nhóm việc dùng chung cho Danh sách, Kanban, Gantt; thẻ việc (Kanban, điện thoại); thanh lọc.
import 'package:flutter/material.dart';

import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'store.dart';

class TwFilter {
  TwFilter();
  String q = '';
  Set<String> assignees = {}; // khoá TwAssignee.key, "none" = chưa giao
  Set<String> labels = {};
  Set<int> priorities = {};
  String? due; // overdue | week | none
  String sort = 'rank'; // rank | priority | due | updated | created
  String group = 'status'; // status | assignee | label | due | priority | none
  bool showSubtasks = true;

  bool get active => q.isNotEmpty || assignees.isNotEmpty || labels.isNotEmpty || priorities.isNotEmpty || due != null;

  Map<String, dynamic> toJson() => {'q': q, 'assignees': assignees.toList(), 'labels': labels.toList(), 'priorities': priorities.toList(), 'due': due, 'sort': sort, 'group': group};
  void load(Map<String, dynamic> j) {
    q = '${j['q'] ?? ''}';
    assignees = {for (final x in j['assignees'] as List? ?? const []) '$x'};
    labels = {for (final x in j['labels'] as List? ?? const []) '$x'};
    priorities = {for (final x in j['priorities'] as List? ?? const []) (x as num).toInt()};
    due = j['due'] as String?;
    sort = '${j['sort'] ?? 'rank'}';
    group = '${j['group'] ?? 'status'}';
  }

  bool matches(TwTask t, DateTime today) {
    if (t.deletedAt != null) return false;
    if (!showSubtasks && t.parentId != null) return false;
    if (q.isNotEmpty) {
      final s = q.toLowerCase();
      if (!t.title.toLowerCase().contains(s) && !t.key.toLowerCase().contains(s)) return false;
    }
    if (assignees.isNotEmpty) {
      final keys = t.assignees.map((a) => a.key).toSet();
      if (!(assignees.contains('none') && keys.isEmpty) && keys.intersection(assignees).isEmpty) return false;
    }
    if (labels.isNotEmpty && t.labels.toSet().intersection(labels).isEmpty) return false;
    if (priorities.isNotEmpty && !priorities.contains(t.priority)) return false;
    switch (due) {
      case 'overdue':
        if (t.due == null || !t.due!.isBefore(today) || t.doneAt != null) return false;
      case 'week':
        if (t.due == null || t.due!.isAfter(today.add(const Duration(days: 7)))) return false;
      case 'none':
        if (t.due != null) return false;
    }
    return true;
  }

  int compare(TwTask a, TwTask b) {
    int prio(TwTask t) => t.priority == 0 ? 9 : t.priority;
    final c = switch (sort) {
      'priority' => prio(a).compareTo(prio(b)),
      'due' => (a.due ?? DateTime.utc(9999)).compareTo(b.due ?? DateTime.utc(9999)),
      'updated' => b.updatedAt.compareTo(a.updatedAt),
      'created' => b.createdAt.compareTo(a.createdAt),
      _ => 0,
    };
    return c != 0 ? c : byRank(a, b);
  }

  List<TwTask> apply(List<TwTask> all, DateTime today) => all.where((t) => matches(t, today)).toList()..sort(compare);
}

const kSortNames = {'rank': 'Thủ công', 'priority': 'Ưu tiên', 'due': 'Hạn', 'updated': 'Mới cập nhật', 'created': 'Mới tạo'};
const kGroupNames = {'status': 'Trạng thái', 'assignee': 'Người làm', 'label': 'Nhãn', 'due': 'Hạn', 'priority': 'Ưu tiên', 'none': 'Không nhóm'};

/// Một nhóm việc trong Danh sách.
class TaskGroup {
  TaskGroup(this.key, this.title, {this.status, this.color, this.leading});
  final String key, title;
  final TwStatus? status;
  final Color? color;
  final Widget? leading;
  final List<TwTask> tasks = [];
}

List<TaskGroup> groupTasks(List<TwTask> tasks, TwFilter f, TwProjectFull? p, DateTime today) {
  final out = <String, TaskGroup>{};
  TaskGroup g(String k, String title, {TwStatus? status, Color? color, Widget? leading}) => out.putIfAbsent(k, () => TaskGroup(k, title, status: status, color: color, leading: leading));
  if (f.group == 'status' && p != null) {
    for (final s in p.statuses) {
      g(s.id, s.name, status: s, leading: StatusRing(s));
    }
  }
  for (final t in tasks) {
    switch (f.group) {
      case 'status':
        final s = p?.status(t.statusId);
        g(t.statusId, s?.name ?? 'Khác', status: s, leading: StatusRing(s)).tasks.add(t);
      case 'assignee':
        if (t.assignees.isEmpty) g('none', 'Chưa giao').tasks.add(t);
        for (final a in t.assignees) {
          g(a.key, a.name, leading: TwAvatar.of(a, size: 20, border: false)).tasks.add(t);
        }
      case 'label':
        if (t.labels.isEmpty) g('none', 'Không nhãn').tasks.add(t);
        for (final l in t.labels) {
          final lb = p?.label(l);
          g(l, lb?.name ?? l, color: hexColor(lb?.color)).tasks.add(t);
        }
      case 'due':
        final d = t.due;
        final (k, title) = d == null
            ? ('z', 'Không hạn')
            : d.isBefore(today) && t.doneAt == null
                ? ('a', 'Quá hạn')
                : d == today
                    ? ('b', 'Hôm nay')
                    : d.isBefore(today.add(const Duration(days: 7)))
                        ? ('c', 'Tuần này')
                        : ('d', 'Sau này');
        g(k, title).tasks.add(t);
      case 'priority':
        g('p${t.priority == 0 ? 9 : t.priority}', kPriorityNames[t.priority]!, leading: PriorityIcon(t.priority)).tasks.add(t);
      default:
        g('all', 'Tất cả việc').tasks.add(t);
    }
  }
  final l = out.values.toList();
  if (f.group != 'status') l.sort((a, b) => a.key.compareTo(b.key));
  return l;
}

/// Thẻ việc (Kanban, danh sách điện thoại).
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.store, this.onTap, this.onDoubleTap, this.dragging = false, this.showProject = false});
  final TwTask task;
  final TwStore store;
  final VoidCallback? onTap;
  /// Bấm đúp (máy tính): mở trang việc đầy đủ; bấm một lần thì xem nhanh.
  final VoidCallback? onDoubleTap;
  final bool dragging, showProject;

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final t = task;
    final p = store.fullOf(t.projectId);
    final late = t.due != null && t.due!.isBefore(store.today) && !(store.statusOf(t)?.isClosed ?? false);
    final meta = TextStyle(fontSize: 11.5, color: look.sub);
    final run = t.run;
    return Material(
      color: look.card,
      elevation: dragging ? 8 : 0,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: dragging ? look.accent : look.divider)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PriorityIcon(t.priority, size: 15),
              const SizedBox(width: 6),
              KeyText(t.key, style: meta.copyWith(fontWeight: FontWeight.w600)),
              if (showProject && p != null) ...[const SizedBox(width: 6), Flexible(child: Text(p.project.name, overflow: TextOverflow.ellipsis, style: meta))],
              const Spacer(),
              TwAvatars(t.assignees, size: 22, max: 3),
            ]),
            const SizedBox(height: 6),
            Text(t.title, style: TextStyle(fontWeight: FontWeight.w600, height: 1.35, color: look.text)),
            if (t.labels.isNotEmpty && p != null) ...[
              const SizedBox(height: 7),
              Wrap(spacing: 5, runSpacing: 5, children: [for (final l in t.labels) if (p.label(l) != null) LabelChip(p.label(l)!, dense: true)]),
            ],
            if (t.subTotal > 0 || t.commentCount > 0 || t.attachmentCount > 0 || t.due != null) ...[
              const SizedBox(height: 7),
              Row(children: [
                if (t.subTotal > 0) ...[
                  Icon(Icons.checklist_rounded, size: 15, color: look.sub),
                  const SizedBox(width: 3),
                  Text('${t.subDone}/${t.subTotal}', style: meta),
                  const SizedBox(width: 5),
                  ThinProgress(t.subDone / t.subTotal, width: 46),
                  const SizedBox(width: 8),
                ],
                if (t.commentCount > 0) ...[Icon(Icons.chat_bubble_outline, size: 14, color: look.sub), const SizedBox(width: 3), Text('${t.commentCount}', style: meta), const SizedBox(width: 8)],
                if (t.attachmentCount > 0) ...[Icon(Icons.attach_file, size: 14, color: look.sub), const SizedBox(width: 2), Text('${t.attachmentCount}', style: meta)],
                const Spacer(),
                if (t.due != null) ...[
                  Icon(Icons.event_outlined, size: 14, color: late ? look.red : look.sub),
                  const SizedBox(width: 3),
                  Text(dShort(t.due!), style: meta.copyWith(color: late ? look.red : null, fontWeight: late ? FontWeight.w600 : null)),
                ],
              ]),
            ],
            if (run != null && run.state != 'cancelled' && run.state != 'done') ...[
              const SizedBox(height: 7),
              Row(children: [
                Icon(run.active ? Icons.autorenew_rounded : Icons.auto_awesome, size: 14, color: look.ai),
                const SizedBox(width: 5),
                Flexible(
                  child: Text('${run.botName.isEmpty ? 'Agent' : run.botName} ${kRunStateNames[run.state] ?? run.state}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: look.ai, fontWeight: FontWeight.w600)),
                ),
              ]),
            ] else if (t.hasAgent && run == null) ...[
              const SizedBox(height: 7),
              Row(children: [
                Icon(Icons.smart_toy_outlined, size: 14, color: look.ai),
                const SizedBox(width: 5),
                Text('Agent chờ bắt đầu', style: TextStyle(fontSize: 11.5, color: look.ai, fontWeight: FontWeight.w600)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Thanh lọc trên Danh sách / Kanban / Gantt.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.store, required this.project, required this.filter, required this.onChanged, this.showGroup = true, this.compact = false});
  final TwStore store;
  final TwProjectFull project;
  final TwFilter filter;
  final VoidCallback onChanged;
  final bool showGroup, compact;

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final f = filter;
    final assigneeNames = {
      for (final t in store.tasksOf(project.project.id))
        for (final a in t.assignees) a.key: a,
    };
    Future<void> menu<T>(List<(T, String)> items, void Function(T) pick, {GlobalKey? anchor}) async {
      final box = context.findRenderObject() as RenderBox?;
      final r = await showMenu<T>(
        context: context,
        position: box == null ? const RelativeRect.fromLTRB(100, 100, 100, 100) : RelativeRect.fromRect(box.localToGlobal(Offset.zero) & box.size, Offset.zero & MediaQuery.sizeOf(context)),
        items: [for (final (v, label) in items) PopupMenuItem<T>(value: v, child: Text(label))],
      );
      if (r != null) {
        pick(r);
        onChanged();
      }
    }

    final pills = <Widget>[
      SizedBox(
        width: compact ? 160 : 240,
        height: 32,
        child: TextField(
          key: const ValueKey('filter-q'),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: 'Tìm việc…',
            isDense: true,
            filled: true,
            fillColor: look.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) {
            f.q = v;
            onChanged();
          },
        ),
      ),
      TwPill(
        key: const ValueKey('filter-assignee'),
        set: f.assignees.isNotEmpty,
        onTap: () async {
          final r = await pickAssignees(context, store, current: [for (final k in f.assignees) if (assigneeNames[k] != null) assigneeNames[k]!], projectId: project.project.id);
          if (r != null) {
            f.assignees = r.map((a) => a.key).toSet();
            onChanged();
          }
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.person_outline),
          const SizedBox(width: 5),
          Text(f.assignees.isEmpty ? 'Người làm' : 'Người làm: ${f.assignees.length}'),
        ]),
      ),
      TwPill(
        set: f.labels.isNotEmpty,
        onTap: () async {
          final r = await pickLabels(context, project, current: f.labels.toList());
          if (r != null) {
            f.labels = r.toSet();
            onChanged();
          }
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.label_outline), const SizedBox(width: 5), Text(f.labels.isEmpty ? 'Nhãn' : 'Nhãn: ${f.labels.length}')]),
      ),
      TwPill(
        set: f.priorities.isNotEmpty,
        onTap: () => menu<int>([for (final p in [1, 2, 3, 4, 0]) (p, kPriorityNames[p]!), (-1, 'Bỏ lọc')], (p) => p < 0 ? f.priorities.clear() : (f.priorities.contains(p) ? f.priorities.remove(p) : f.priorities.add(p))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.flag_outlined), const SizedBox(width: 5), Text(f.priorities.isEmpty ? 'Ưu tiên' : 'Ưu tiên: ${f.priorities.map((p) => kPriorityNames[p]).join(', ')}')]),
      ),
      TwPill(
        set: f.due != null,
        onTap: () => menu<String>([('overdue', 'Quá hạn'), ('week', 'Trong 7 ngày'), ('none', 'Không hạn'), ('', 'Bỏ lọc')], (v) => f.due = v.isEmpty ? null : v),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.event_outlined),
          const SizedBox(width: 5),
          Text(switch (f.due) { 'overdue' => 'Quá hạn', 'week' => 'Trong 7 ngày', 'none' => 'Không hạn', _ => 'Hạn' }),
        ]),
      ),
      if (f.active)
        TextButton(
          onPressed: () {
            f
              ..q = ''
              ..assignees = {}
              ..labels = {}
              ..priorities = {}
              ..due = null;
            onChanged();
          },
          child: const Text('Xoá lọc'),
        ),
    ];
    final right = <Widget>[
      TwPill(
        key: const ValueKey('filter-sort'),
        set: true,
        onTap: () => menu<String>([for (final e in kSortNames.entries) (e.key, e.value)], (v) => f.sort = v),
        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.swap_vert), const SizedBox(width: 5), Text('Sắp xếp: ${kSortNames[f.sort]}')]),
      ),
      if (showGroup)
        TwPill(
          key: const ValueKey('filter-group'),
          set: true,
          onTap: () => menu<String>([for (final e in kGroupNames.entries) (e.key, e.value)], (v) => f.group = v),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.layers_outlined), const SizedBox(width: 5), Text('Nhóm: ${kGroupNames[f.group]}')]),
        ),
    ];
    return SizedBox(
      height: 48,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
        for (final w in pills) Padding(padding: const EdgeInsets.only(right: 8), child: w),
        if (!compact) const SizedBox(width: 24),
        for (final w in right) Padding(padding: const EdgeInsets.only(right: 8), child: w),
      ]),
    );
  }
}
