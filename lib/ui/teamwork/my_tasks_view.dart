// TeamWork: "Việc của tôi" — việc ở mọi dự án, chia tab Tôi làm / Tôi tạo / Tôi theo dõi / Agent của tôi, nhóm theo
// Quá hạn / Hôm nay / Tuần này / Sau này / Không hạn.
import 'package:flutter/material.dart';

import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'store.dart';

const kMineTabs = {'assigned': 'Tôi làm', 'created': 'Tôi tạo', 'watching': 'Tôi theo dõi', 'agents': 'Agent của tôi'};

class TwMyTasksView extends StatefulWidget {
  const TwMyTasksView({super.key, required this.store, required this.onOpen});
  final TwStore store;
  final void Function(TwTask) onOpen;
  @override
  State<TwMyTasksView> createState() => _TwMyTasksViewState();
}

class _TwMyTasksViewState extends State<TwMyTasksView> {
  String _tab = 'assigned';

  @override
  void initState() {
    super.initState();
    widget.store.loadMine(_tab);
  }

  void _pick(String t) {
    setState(() => _tab = t);
    widget.store.loadMine(t);
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final wide = twWide(context);
    final store = widget.store;
    final today = store.today;
    final list = (store.mine[_tab] ?? const <TwTask>[]).where((t) => !(store.statusOf(t)?.isClosed ?? false) && t.doneAt == null).toList();
    final groups = <(String, Color?, List<TwTask>)>[
      ('Quá hạn', look.red, list.where((t) => t.due != null && t.due!.isBefore(today)).toList()),
      ('Hôm nay', null, list.where((t) => t.due == today).toList()),
      ('Tuần này', null, list.where((t) => t.due != null && t.due!.isAfter(today) && t.due!.isBefore(today.add(const Duration(days: 7)))).toList()),
      ('Sau này', null, list.where((t) => t.due != null && !t.due!.isBefore(today.add(const Duration(days: 7)))).toList()),
      ('Không hạn', null, list.where((t) => t.due == null).toList()),
    ];
    for (final g in groups) {
      g.$3.sort((a, b) => (a.due ?? DateTime.utc(9999)).compareTo(b.due ?? DateTime.utc(9999)) != 0
          ? (a.due ?? DateTime.utc(9999)).compareTo(b.due ?? DateTime.utc(9999))
          : (a.priority == 0 ? 9 : a.priority).compareTo(b.priority == 0 ? 9 : b.priority));
    }
    final keyW = keyColumnWidth(context, list.map((t) => t.key), _keyStyle(look));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 14, vertical: 8), children: [
          for (final e in kMineTabs.entries)
            Padding(padding: const EdgeInsets.only(right: 8), child: TwPill(key: ValueKey('mine-${e.key}'), set: _tab == e.key, onTap: () => _pick(e.key), child: Text(e.value))),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => store.loadMine(_tab),
          child: ListView(padding: EdgeInsets.fromLTRB(wide ? 20 : 14, 0, wide ? 20 : 14, 80), children: [
            for (final (title, color, items) in groups)
              if (items.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 4),
                  child: Text('$title · ${items.length}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                ),
                for (final t in items) _row(t, look, wide, color != null, keyW),
              ],
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(40), child: Center(child: Text('Không có việc nào đang mở', style: TextStyle(color: look.sub)))),
          ]),
        ),
      ),
    ]);
  }

  TextStyle _keyStyle(TwLook look) => TextStyle(fontSize: 12, color: look.sub, fontWeight: FontWeight.w600);

  Widget _row(TwTask t, TwLook look, bool wide, bool late, double keyW) {
    final p = widget.store.projectById(t.projectId);
    return InkWell(
      key: ValueKey('mine-row-${t.key}'),
      onTap: () => widget.onOpen(t),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.divider))),
        child: Row(children: [
          if (wide) ...[PriorityIcon(t.priority), const SizedBox(width: 8), SizedBox(width: keyW, child: KeyText(t.key, style: _keyStyle(look)))],
          StatusRing(widget.store.statusOf(t)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: wide ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (!wide) Text('${t.key} · ${t.due == null ? '—' : dRel(t.due!, widget.store.today)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: late ? look.red : look.sub)),
            ]),
          ),
          if (t.run?.active ?? false) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.autorenew_rounded, size: 16, color: look.ai)),
          if (wide && p != null)
            SizedBox(
              width: 230,
              child: Row(children: [ProjectBadge(p), const SizedBox(width: 6), Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: look.sub)))]),
            ),
          if (wide)
            SizedBox(width: 80, child: Text(t.due == null ? '—' : dRel(t.due!, widget.store.today), style: TextStyle(fontSize: 12.5, color: late ? look.red : look.sub, fontWeight: late ? FontWeight.w600 : null)))
          else
            PriorityIcon(t.priority),
        ]),
      ),
    );
  }
}
