// TeamWork: các hộp chọn — người làm (người + agent AI), chủ thể thành viên (người / phòng ban / vai trò / mọi người),
// trạng thái, ưu tiên, nhãn, ngày, việc (liên kết / #nhắc việc). Máy tính mở hộp thoại, điện thoại mở bảng trượt từ dưới.
import 'dart:async';

import 'package:flutter/material.dart';

import 'look.dart';
import 'model.dart';
import 'store.dart';

bool twWide(BuildContext c) => MediaQuery.sizeOf(c).width >= 760;

/// Mở [child] dạng hộp thoại (máy tính) hoặc bảng trượt (điện thoại).
Future<T?> twSheet<T>(BuildContext context, {required Widget Function(BuildContext) builder, double width = 420}) {
  if (twWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(c).height * .8), child: builder(c)),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .85), child: builder(c)),
    ),
  );
}

Widget sheetTitle(BuildContext c, String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
      child: Row(children: [Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))), ?trailing]),
    );

Widget groupLabel(BuildContext c, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
      child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5, color: TwLook.of(c).sub)),
    );

// ------------------------------------------------------------ người làm
/// Chọn người làm: người (thành viên / tìm trên máy chủ) và agent AI mình được dùng. Trả về danh sách mới.
Future<List<TwAssignee>?> pickAssignees(BuildContext context, TwStore store, {required List<TwAssignee> current, String? projectId}) =>
    twSheet<List<TwAssignee>>(context, builder: (c) => _AssigneePicker(store: store, current: current, projectId: projectId));

class _AssigneePicker extends StatefulWidget {
  const _AssigneePicker({required this.store, required this.current, this.projectId});
  final TwStore store;
  final List<TwAssignee> current;
  final String? projectId;
  @override
  State<_AssigneePicker> createState() => _AssigneePickerState();
}

class _AssigneePickerState extends State<_AssigneePicker> {
  late final Set<TwAssignee> _sel = {...widget.current};
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

  Future<void> _checkAgents() async {
    final l = widget.store.launcher;
    final out = <String, bool>{};
    for (final a in widget.store.agents) {
      out[a.id] = l == null ? true : await l.canUse(a.id);
    }
    if (mounted) setState(() => _usable = out);
  }

  void _search(String q) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 250), () async {
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

  void _toggle(TwAssignee a) => setState(() => _sel.contains(a) ? _sel.remove(a) : _sel.add(a));

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final q = _q.text.trim().toLowerCase();
    final people = <TwSubject>[
      // Người đang được giao luôn hiện trước.
      for (final a in widget.current.where((a) => !a.isAgent)) TwSubject('user', a.id, a.name),
      for (final p in _people)
        if (!widget.current.any((a) => a.id == p.id)) p,
    ];
    final agents = widget.store.agents.where((a) => q.isEmpty || a.label.toLowerCase().contains(q)).toList();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetTitle(context, 'Người làm'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          key: const ValueKey('assignee-q'),
          controller: _q,
          autofocus: twWide(context),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 20), hintText: 'Tìm người hoặc agent…', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (v) {
            setState(() {});
            _search(v);
          },
        ),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          groupLabel(context, 'Người'),
          for (final p in people)
            CheckboxListTile(
              key: ValueKey('pick-user-${p.id}'),
              dense: true,
              value: _sel.contains(TwAssignee(kind: 'user', id: p.id)),
              onChanged: (_) => _toggle(TwAssignee(kind: 'user', id: p.id, name: p.name)),
              secondary: TwAvatar(name: p.name, id: p.id, size: 28, border: false),
              title: Text(p.name),
              subtitle: p.sub.isEmpty ? null : Text(p.sub, style: TextStyle(color: look.sub, fontSize: 12)),
            ),
          if (people.isEmpty) Padding(padding: const EdgeInsets.all(18), child: Text('Không tìm thấy ai', style: TextStyle(color: look.sub))),
          groupLabel(context, 'Agent AI'),
          for (final a in agents)
            CheckboxListTile(
              key: ValueKey('pick-agent-${a.id}'),
              dense: true,
              value: _sel.contains(TwAssignee(kind: 'agent', id: a.id)),
              onChanged: _usable[a.id] == false && !_sel.contains(TwAssignee(kind: 'agent', id: a.id)) ? null : (_) => _toggle(TwAssignee(kind: 'agent', id: a.id, name: a.label)),
              secondary: TwAvatar(name: a.name, id: a.id, agent: true, size: 28, border: false),
              title: Text(a.label),
              subtitle: Text(_usable[a.id] == false ? 'Bạn chưa được dùng agent này' : (a.ownerName.isEmpty ? 'Agent' : '${a.ownerName} cho phép'),
                  style: TextStyle(color: _usable[a.id] == false ? look.sub : look.ai, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          if (agents.isEmpty) Padding(padding: const EdgeInsets.all(18), child: Text('Chưa có agent nào bạn dùng được', style: TextStyle(color: look.sub))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
            child: Text('Agent làm bằng quyền của người bấm "Bắt đầu" và báo kết quả bằng bình luận. Giao xong chưa chạy ngay: bấm Bắt đầu hoặc kéo việc vào trạng thái bắt đầu.',
                style: TextStyle(color: look.sub, fontSize: 12, height: 1.4)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
        child: Row(children: [
          TextButton(onPressed: () => setState(_sel.clear), child: const Text('Bỏ hết')),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          const SizedBox(width: 6),
          FilledButton(key: const ValueKey('assignee-ok'), onPressed: () => Navigator.pop(context, _sel.toList()), child: const Text('Xong')),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------ chủ thể thành viên
Future<TwSubject?> pickSubject(BuildContext context, TwStore store) => twSheet<TwSubject>(context, builder: (c) => _SubjectPicker(store: store));

class _SubjectPicker extends StatefulWidget {
  const _SubjectPicker({required this.store});
  final TwStore store;
  @override
  State<_SubjectPicker> createState() => _SubjectPickerState();
}

class _SubjectPickerState extends State<_SubjectPicker> {
  final _q = TextEditingController();
  List<TwSubject> _r = [];
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  void _search(String q) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 250), () async {
      try {
        final r = await widget.store.api.subjects(q);
        if (mounted) setState(() => _r = r);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    super.dispose();
  }

  static const _icons = {'user': Icons.person_outline, 'dept': Icons.apartment_rounded, 'role': Icons.badge_outlined, 'everyone': Icons.public};
  static const _groups = {'user': 'Người', 'dept': 'Phòng ban', 'role': 'Vai trò Flygo ID', 'everyone': 'Tất cả'};

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetTitle(context, 'Thêm thành viên'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          key: const ValueKey('subject-q'),
          controller: _q,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 20), hintText: 'Tìm người, phòng ban, vai trò…', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: _search,
        ),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
          for (final g in ['everyone', 'dept', 'role', 'user'])
            if (_r.any((s) => s.type == g)) ...[
              groupLabel(context, _groups[g]!),
              for (final s in _r.where((s) => s.type == g))
                ListTile(
                  key: ValueKey('subject-${s.type}-${s.id}'),
                  dense: true,
                  leading: s.type == 'user'
                      ? TwAvatar(name: s.name, id: s.id, size: 28, border: false)
                      : CircleAvatar(radius: 14, backgroundColor: look.surface2, child: Icon(_icons[s.type], size: 16, color: look.sub)),
                  title: Text(s.name),
                  subtitle: s.sub.isEmpty ? null : Text(s.sub, style: TextStyle(color: look.sub, fontSize: 12)),
                  onTap: () => Navigator.pop(context, s),
                ),
            ],
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------ trạng thái, ưu tiên, nhãn
Future<TwStatus?> pickStatus(BuildContext context, TwProjectFull f, {String? current}) => twSheet<TwStatus>(
      context,
      width: 320,
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(c, 'Trạng thái'),
        Flexible(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 10), children: [
            for (final s in f.statuses)
              ListTile(
                key: ValueKey('pick-status-${s.id}'),
                dense: true,
                leading: StatusRing(s, size: 16),
                title: Text(s.name),
                subtitle: s.isStart ? Text('Trạng thái bắt đầu: agent chạy khi việc vào đây', style: TextStyle(fontSize: 11.5, color: TwLook.of(c).ai)) : null,
                trailing: s.id == current ? const Icon(Icons.check, size: 18) : (s.adminOnly && !f.project.canAdmin ? const Icon(Icons.lock_outline, size: 16) : null),
                enabled: !(s.adminOnly && !f.project.canAdmin),
                onTap: () => Navigator.pop(c, s),
              ),
          ]),
        ),
      ]),
    );

Future<int?> pickPriority(BuildContext context, {int? current}) => twSheet<int>(
      context,
      width: 280,
      builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(c, 'Ưu tiên'),
        for (final p in [1, 2, 3, 4, 0])
          ListTile(
            key: ValueKey('pick-priority-$p'),
            dense: true,
            leading: PriorityIcon(p),
            title: Text(kPriorityNames[p]!),
            trailing: p == current ? const Icon(Icons.check, size: 18) : null,
            onTap: () => Navigator.pop(c, p),
          ),
        const SizedBox(height: 10),
      ]),
    );

Future<List<String>?> pickLabels(BuildContext context, TwProjectFull f, {required List<String> current}) =>
    twSheet<List<String>>(context, width: 340, builder: (c) => _LabelPicker(f: f, current: current));

class _LabelPicker extends StatefulWidget {
  const _LabelPicker({required this.f, required this.current});
  final TwProjectFull f;
  final List<String> current;
  @override
  State<_LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<_LabelPicker> {
  late final Set<String> _sel = {...widget.current};
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sheetTitle(context, 'Nhãn'),
        if (widget.f.labels.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('Dự án chưa có nhãn. Thêm nhãn trong Cài đặt dự án.')),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (final l in widget.f.labels)
              CheckboxListTile(
                key: ValueKey('pick-label-${l.id}'),
                dense: true,
                value: _sel.contains(l.id),
                onChanged: (_) => setState(() => _sel.contains(l.id) ? _sel.remove(l.id) : _sel.add(l.id)),
                title: Align(alignment: Alignment.centerLeft, child: LabelChip(l)),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(alignment: Alignment.centerRight, child: FilledButton(key: const ValueKey('labels-ok'), onPressed: () => Navigator.pop(context, _sel.toList()), child: const Text('Xong'))),
        ),
      ]);
}

/// Chọn ngày (null nếu huỷ). [clear]: có nút "Bỏ ngày" — trả về DateTime(0) để báo xoá.
Future<DateTime?> pickDay(BuildContext context, {DateTime? initial, required DateTime today, String? help}) async {
  final d = await showDatePicker(
    context: context,
    initialDate: initial ?? today,
    firstDate: DateTime.utc(today.year - 5),
    lastDate: DateTime.utc(today.year + 10),
    helpText: help,
    cancelText: 'Huỷ',
    confirmText: 'Chọn',
  );
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

// ------------------------------------------------------------ việc
/// Chọn một việc (liên kết, #nhắc việc): tìm trong các dự án mình xem được.
Future<TwTask?> pickTask(BuildContext context, TwStore store, {String? projectId, Set<String> exclude = const {}, String title = 'Chọn việc'}) =>
    twSheet<TwTask>(context, builder: (c) => _TaskPicker(store: store, projectId: projectId, exclude: exclude, title: title));

class _TaskPicker extends StatefulWidget {
  const _TaskPicker({required this.store, this.projectId, required this.exclude, required this.title});
  final TwStore store;
  final String? projectId, title;
  final Set<String> exclude;
  @override
  State<_TaskPicker> createState() => _TaskPickerState();
}

class _TaskPickerState extends State<_TaskPicker> {
  final _q = TextEditingController();
  List<TwTask>? _remote;
  Timer? _deb;

  List<TwTask> get _local {
    final q = _q.text.trim().toLowerCase();
    final l = widget.projectId == null ? <TwTask>[] : widget.store.tasksOf(widget.projectId!);
    return l.where((t) => !widget.exclude.contains(t.id) && (q.isEmpty || t.title.toLowerCase().contains(q) || t.key.toLowerCase().contains(q))).take(40).toList();
  }

  void _search(String q) {
    setState(() {});
    _deb?.cancel();
    if (q.trim().length < 2) return;
    _deb = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await widget.store.api.search(q);
        if (mounted) setState(() => _remote = r.where((t) => !widget.exclude.contains(t.id)).toList());
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
    final local = _local;
    final remote = (_remote ?? const <TwTask>[]).where((t) => !local.any((x) => x.id == t.id)).toList();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetTitle(context, widget.title ?? 'Chọn việc'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          key: const ValueKey('task-q'),
          controller: _q,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 20), hintText: 'Tìm theo tên hoặc mã việc…', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: _search,
        ),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 10), children: [
          for (final t in [...local, ...remote])
            ListTile(
              key: ValueKey('pick-task-${t.key}'),
              dense: true,
              leading: StatusRing(widget.store.statusOf(t)),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.key),
              onTap: () => Navigator.pop(context, t),
            ),
        ]),
      ),
    ]);
  }
}

/// Hỏi một dòng chữ (đặt tên, link…).
Future<String?> askText(BuildContext context, {required String title, String? initial, String? hint, String ok = 'Lưu'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(key: const ValueKey('ask-text'), controller: c, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(d, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Huỷ')),
        FilledButton(key: const ValueKey('ask-ok'), onPressed: () => Navigator.pop(d, c.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Đồng ý', bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(key: const ValueKey('confirm-no'), onPressed: () => Navigator.pop(d, false), child: const Text('Huỷ')),
          FilledButton(
            key: const ValueKey('confirm-yes'),
            style: danger ? FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)) : null,
            onPressed: () => Navigator.pop(d, true),
            child: Text(ok),
          ),
        ],
      ),
    ) ??
    false;
