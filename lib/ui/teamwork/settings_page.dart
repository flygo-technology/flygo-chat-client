// TeamWork: cài đặt dự án — Chung (tên, mã, màu, trạng thái dự án, ngày), Trạng thái & quy trình (cột Kanban: màu,
// nhóm, WIP, chỉ Quản trị chuyển vào, nơi agent nộp kết quả, và đúng MỘT trạng thái "bắt đầu"), Thành viên & quyền
// (người / phòng ban / vai trò / mọi người), Nhãn, Lưu trữ / xoá.
import 'package:flutter/material.dart';

import 'cover.dart';
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'project_ai.dart' show linkProjectChat;
import 'projects_view.dart' show ProjectCard;
import 'store.dart';
import 'teamwork_page.dart' show showPrefs;

const kSettingsTabs = {
  'general': 'Chung',
  'statuses': 'Trạng thái & quy trình',
  'members': 'Thành viên & quyền',
  'labels': 'Nhãn',
  'agents': 'Agent AI',
  'notify': 'Thông báo',
  'danger': 'Lưu trữ / xoá',
};
const _tabIcons = {
  'general': Icons.info_outline,
  'statuses': Icons.view_kanban_outlined,
  'members': Icons.group_outlined,
  'labels': Icons.label_outline,
  'agents': Icons.smart_toy_outlined,
  'notify': Icons.notifications_none,
  'danger': Icons.archive_outlined,
};

class TwSettingsPage extends StatefulWidget {
  const TwSettingsPage({super.key, required this.store, required this.projectId, this.initialTab, this.inline = false});
  final TwStore store;
  final String projectId;
  /// Mục mở đầu. Điện thoại: null = danh sách mục (chọn một mục thì mở chi tiết).
  final String? initialTab;
  /// Nằm trong tab "Cài đặt" của dự án (không có thanh ứng dụng riêng).
  final bool inline;
  @override
  State<TwSettingsPage> createState() => _TwSettingsPageState();
}

class _TwSettingsPageState extends State<TwSettingsPage> {
  late String _tab = widget.initialTab ?? 'statuses';
  /// Hình nền đang chọn (chưa lưu); null + _coverPicked = false: chưa chọn gì.
  TwCover? _cover;
  bool _coverPicked = false;
  /// Điện thoại: đang xem chi tiết một mục (false = danh sách mục).
  late bool _detail = widget.initialTab != null;
  TwStore get store => widget.store;
  TwProjectFull? get f => store.fullOf(widget.projectId);

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _toast(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      _toast(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final full = f;
    if (full == null) return widget.inline ? const Center(child: CircularProgressIndicator()) : const Scaffold(body: Center(child: CircularProgressIndicator()));
    final wide = twWide(context);
    final admin = full.project.canAdmin;
    final content = switch (_tab) {
      'general' => _general(full, look, admin),
      'members' => _members(full, look, admin),
      'labels' => _labels(full, look, admin),
      'danger' => _danger(full, look),
      'agents' => _agents(look),
      'notify' => _notify(look),
      _ => _statuses(full, look, admin),
    };
    final body = wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                key: const ValueKey('settings-nav'),
                width: 250,
                child: ListView(padding: const EdgeInsets.all(10), children: [
                  for (final e in kSettingsTabs.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: _tab == e.key ? look.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          key: ValueKey('set-${e.key}'),
                          dense: true,
                          leading: Icon(_tabIcons[e.key], size: 19, color: _tab == e.key ? look.accent : look.sub),
                          minLeadingWidth: 20,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          title: Text(e.value, style: TextStyle(color: _tab == e.key ? look.accent : look.text, fontWeight: _tab == e.key ? FontWeight.w600 : FontWeight.w500)),
                          onTap: () => setState(() => _tab = e.key),
                        ),
                      ),
                    ),
                ]),
              ),
              Expanded(child: content),
            ])
          : !_detail
              ? ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
                  for (final e in kSettingsTabs.entries)
                    ListTile(
                      key: ValueKey('set-${e.key}'),
                      leading: Icon(_tabIcons[e.key], color: look.sub),
                      title: Text(e.value),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() {
                        _tab = e.key;
                        _detail = true;
                      }),
                    ),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (widget.inline || widget.initialTab == null)
                    InkWell(
                      key: const ValueKey('set-back'),
                      onTap: () => setState(() => _detail = false),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: Row(children: [const Icon(Icons.chevron_left), const SizedBox(width: 4), Text(kSettingsTabs[_tab]!, style: const TextStyle(fontWeight: FontWeight.w700))]),
                      ),
                    ),
                  Expanded(child: content),
                ]);
    if (widget.inline) return body;
    return Scaffold(
      backgroundColor: look.bg,
      appBar: AppBar(
        backgroundColor: look.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(children: [ProjectBadge(full.project, size: 26), const SizedBox(width: 10), const Text('Cài đặt dự án', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))]),
      ),
      body: body,
    );
  }

  /// Hình nền: xem trước thẻ dự án + bộ chọn (màu trơn, màu chuyển, hoạ tiết), lưu bằng PATCH {cover}.
  Widget _coverSection(TwProjectFull full, TwLook look, bool admin) {
    final pr = full.project;
    final cur = _coverPicked ? _cover : pr.cover;
    final preview = TwProject.fromJson({...pr.toJson(), 'cover': cur?.toJson()});
    return Padding(
      key: const ValueKey('cover-section'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Hình nền', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.start, children: [
          SizedBox(width: 300, height: ProjectCard.height, child: ProjectCard(key: const ValueKey('cover-preview'), project: preview, store: store, onTap: () {}, preview: true)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: IgnorePointer(
              ignoring: !admin,
              child: TwCoverPicker(cover: cur, projectColor: hexColor(pr.color, kTwAccent), onChanged: (c) => setState(() {
                _cover = c;
                _coverPicked = true;
              })),
            ),
          ),
        ]),
        if (admin)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FilledButton(
              key: const ValueKey('cover-save'),
              onPressed: !_coverPicked || cur == pr.cover
                  ? null
                  : () => _run(() async {
                        await store.updateProject(pr.id, {'cover': cur?.toJson()});
                        if (mounted) setState(() => _coverPicked = false);
                      }),
              child: const Text('Lưu hình nền'),
            ),
          ),
      ]),
    );
  }

  Widget _agents(TwLook look) => ListView(padding: const EdgeInsets.all(20), children: [
        _h('Agent AI',
            'Giao việc cho agent ở ô "Người làm". Agent không cần thêm vào dự án: nó làm bằng quyền của người bấm Bắt đầu (hoặc kéo việc vào trạng thái bắt đầu), báo kết quả bằng bình luận và chuyển việc sang trạng thái "nộp kết quả" để người giao duyệt.',
            look),
        Container(
          decoration: _box(look),
          child: Column(children: [
            for (final a in store.agents) ListTile(leading: TwAvatar(name: a.name, id: a.id, agent: true, size: 28, border: false), title: Text(a.label), subtitle: Text('@${a.username}')),
            if (store.agents.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Chưa có agent nào bạn dùng được', style: TextStyle(color: look.sub))),
          ]),
        ),
      ]);

  Widget _notify(TwLook look) => ListView(padding: const EdgeInsets.all(20), children: [
        _h('Thông báo', 'Bot "Làm việc nhóm" nhắn riêng khi bạn được giao việc, được nhắc, có bình luận mới… Mỗi người tự bật / tắt từng loại.', look),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(key: const ValueKey('notify-prefs'), onPressed: () => showPrefs(context, store), icon: const Icon(Icons.tune, size: 18), label: const Text('Chọn loại tin nhắn')),
        ),
      ]);

  Widget _h(String title, String sub, TwLook look) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 3),
          Text(sub, style: TextStyle(color: look.sub, height: 1.4)),
        ]),
      );

  BoxDecoration _box(TwLook look) => BoxDecoration(border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(12));

  // ------------------------------------------------------------ chung
  Widget _general(TwProjectFull full, TwLook look, bool admin) {
    final pr = full.project;
    return ListView(padding: const EdgeInsets.all(20), children: [
      _h('Chung', 'Tên, mã, màu, trạng thái và thời gian của dự án.', look),
      ListTile(
        title: const Text('Tên dự án'),
        subtitle: Text(pr.name),
        trailing: admin ? const Icon(Icons.edit_outlined, size: 18) : null,
        onTap: !admin
            ? null
            : () async {
                final v = await askText(context, title: 'Tên dự án', initial: pr.name);
                if (v != null && v.isNotEmpty) await _run(() => store.updateProject(pr.id, {'name': v}));
              },
      ),
      ListTile(title: const Text('Mã'), subtitle: Text('${pr.key} (việc đánh số ${pr.key}-1, ${pr.key}-2…)')),
      ListTile(
        title: const Text('Màu'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in kSwatches)
              InkWell(
                onTap: !admin ? null : () => _run(() => store.updateProject(pr.id, {'color': c})),
                child: Container(width: 24, height: 24, decoration: BoxDecoration(color: hexColor(c), borderRadius: BorderRadius.circular(7), border: pr.color.toUpperCase() == c ? Border.all(color: look.text, width: 2) : null)),
              ),
          ]),
        ),
      ),
      _coverSection(full, look, admin),
      if (store.chatOps != null)
        ListTile(
          key: const ValueKey('settings-chat'),
          title: const Text('Nhóm chat của dự án'),
          subtitle: Text(pr.chatChannel == null ? 'Chưa gắn. AI đăng cập nhật vào nhóm này.' : 'Đã gắn; bot Làm việc nhóm đăng cập nhật vào đây.'),
          trailing: pr.chatChannel != null
              ? OutlinedButton.icon(onPressed: () => store.chatOps!.openChannel(pr.chatChannel!), icon: const Icon(Icons.forum_outlined, size: 18), label: const Text('Mở nhóm chat'))
              : (admin ? TextButton.icon(onPressed: () => linkProjectChat(context, store, full), icon: const Icon(Icons.add_link, size: 18), label: const Text('Gắn nhóm chat')) : null),
        ),
      ListTile(
        title: const Text('Trạng thái dự án'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            for (final s in kProjectStatuses)
              ChoiceChip(
                key: ValueKey('pst-$s'),
                label: Text(kProjectStatusNames[s]!),
                selected: pr.status == s,
                selectedColor: hexColor(kProjectStatusColors[s]),
                labelStyle: TextStyle(color: pr.status == s ? Colors.white : null, fontWeight: FontWeight.w600),
                showCheckmark: false,
                onSelected: !admin ? null : (_) => _run(() => store.updateProject(pr.id, {'status': s})),
              ),
          ]),
        ),
      ),
      ListTile(
        title: const Text('Bắt đầu'),
        subtitle: Text(pr.start == null ? '—' : dLong(pr.start!)),
        onTap: !admin
            ? null
            : () async {
                final d = await pickDay(context, initial: pr.start, today: store.today);
                if (d != null) await _run(() => store.updateProject(pr.id, {'start': dayStr(d)}));
              },
      ),
      ListTile(
        title: const Text('Hạn'),
        subtitle: Text(pr.due == null ? '—' : dLong(pr.due!)),
        onTap: !admin
            ? null
            : () async {
                final d = await pickDay(context, initial: pr.due, today: store.today);
                if (d != null) await _run(() => store.updateProject(pr.id, {'due': dayStr(d)}));
              },
      ),
    ]);
  }

  // ------------------------------------------------------------ trạng thái
  Widget _statuses(TwProjectFull full, TwLook look, bool admin) {
    final pr = full.project;
    final wide = twWide(context);
    return ListView(padding: const EdgeInsets.all(20), children: [
      _h('Trạng thái việc',
          'Kéo để đổi thứ tự cột Kanban. Nhóm quyết định "đã xong" khi tính tiến độ. Chọn đúng một trạng thái "bắt đầu": việc có agent được giao vào trạng thái này thì agent bắt đầu làm.', look),
      Container(
        decoration: _box(look),
        child: ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: !admin
              ? (_, _) {}
              : (a, b) {
                  final ids = full.statuses.map((s) => s.id).toList();
                  ids.insert(b, ids.removeAt(a));
                  _run(() => store.reorderStatuses(pr.id, ids));
                },
          children: [
            for (var i = 0; i < full.statuses.length; i++)
              () {
                final s = full.statuses[i];
                final notes = [if (s.id == full.defaultStatus?.id) 'Mặc định cho việc mới', if (s.adminOnly) 'Chỉ Quản trị chuyển vào', if (s.review) 'Agent nộp kết quả vào đây', if (s.closeSubtasksPrompt) 'Hỏi đóng việc con'];
                return Container(
                  key: ValueKey('st-${s.id}'),
                  decoration: BoxDecoration(border: i == full.statuses.length - 1 ? null : Border(bottom: BorderSide(color: look.divider))),
                  child: InkWell(
                    onTap: admin ? () => _editStatus(full, s) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(children: [
                        if (admin) ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator, size: 20, color: look.sub)),
                        const SizedBox(width: 8),
                        Container(width: 16, height: 16, decoration: BoxDecoration(color: hexColor(s.color), borderRadius: BorderRadius.circular(5))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (notes.isNotEmpty) Text(notes.join(' · '), style: TextStyle(fontSize: 11.5, color: look.sub)),
                          ]),
                        ),
                        if (wide) SizedBox(width: 120, child: Text(kCategoryNames[s.category]!, style: TextStyle(fontSize: 12.5, color: look.sub))),
                        SizedBox(width: wide ? 70 : 50, child: Text('WIP: ${s.wip ?? '—'}', style: TextStyle(fontSize: 12.5, color: look.sub))),
                        Tooltip(
                          message: 'Trạng thái bắt đầu',
                          child: InkWell(
                            key: ValueKey('start-${s.id}'),
                            onTap: !admin || s.isStart || s.isClosed ? null : () => _run(() => store.setStartStatus(pr.id, s.id)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(s.isStart ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18, color: s.isStart ? look.ai : look.sub),
                                if (wide) ...[const SizedBox(width: 4), Text('Bắt đầu', style: TextStyle(fontSize: 12, color: s.isStart ? look.ai : look.sub, fontWeight: s.isStart ? FontWeight.w600 : null))],
                              ]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              }(),
          ],
        ),
      ),
      if (admin) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            key: const ValueKey('status-add'),
            onPressed: () => _editStatus(full, TwStatus(id: '', projectId: pr.id, name: '', category: 'started', color: '#1E7BFF', pos: full.statuses.length), create: true),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Thêm trạng thái'),
          ),
        ]),
      ],
    ]);
  }

  Future<void> _editStatus(TwProjectFull full, TwStatus s, {bool create = false}) async {
    final r = await twSheet<(String, TwStatus)>(context, width: 460, builder: (c) => _StatusEditor(status: s.copy(), create: create, canDelete: !create && full.statuses.length > 2));
    if (r == null) return;
    final (action, edited) = r;
    if (action == 'delete') {
      if (!mounted) return;
      final others = full.statuses.where((x) => x.id != s.id).toList();
      final to = await twSheet<TwStatus>(
        context,
        width: 340,
        builder: (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sheetTitle(c, 'Chuyển việc của "${s.name}" sang'),
          for (final o in others) ListTile(key: ValueKey('moveto-${o.id}'), leading: StatusRing(o), title: Text(o.name), onTap: () => Navigator.pop(c, o)),
          const SizedBox(height: 8),
        ]),
      );
      if (to == null) return;
      await _run(() => store.deleteStatus(full.project.id, s.id, to.id));
      return;
    }
    if (edited.name.trim().isEmpty) return _toast('Nhập tên trạng thái');
    await _run(() async {
      await store.saveStatus(full.project.id, edited, create: create);
      if (edited.isStart && !s.isStart && !create) await store.setStartStatus(full.project.id, edited.id);
    });
  }

  // ------------------------------------------------------------ thành viên
  Widget _members(TwProjectFull full, TwLook look, bool admin) {
    const icons = {'dept': Icons.apartment_rounded, 'role': Icons.badge_outlined, 'everyone': Icons.public};
    return ListView(padding: const EdgeInsets.all(20), children: [
      _h('Thành viên & quyền', 'Thêm người, phòng ban (gồm phòng con), vai trò Flygo ID hoặc mọi người. Một người có nhiều vai trò thì lấy vai trò cao nhất. Dự án chỉ thành viên thấy.', look),
      Container(
        decoration: _box(look),
        child: Column(children: [
          for (final m in full.members)
            Container(
              key: ValueKey('member-${m.key}'),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.divider))),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                m.subjectType == 'user'
                    ? TwAvatar(name: m.name, id: m.subjectId, size: 28, border: false)
                    : CircleAvatar(radius: 14, backgroundColor: look.surface2, child: Icon(icons[m.subjectType], size: 16, color: look.sub)),
                const SizedBox(width: 12),
                Expanded(child: Text(m.subjectType == 'everyone' ? 'Mọi người' : (m.subjectType == 'role' ? 'Vai trò: ${m.name}' : m.name), style: const TextStyle(fontWeight: FontWeight.w500))),
                if (m.role == 'owner' || !admin)
                  Text(kRoleNames[m.role] ?? m.role, style: TextStyle(color: look.sub))
                else
                  DropdownButton<String>(
                    key: ValueKey('role-${m.key}'),
                    value: m.role,
                    underline: const SizedBox(),
                    items: [for (final r in ['admin', 'member', 'viewer', 'remove']) DropdownMenuItem(value: r, child: Text(r == 'remove' ? 'Gỡ khỏi dự án' : kRoleNames[r]!))],
                    onChanged: (r) {
                      if (r == null) return;
                      _run(() => r == 'remove' ? store.removeMember(full.project.id, m.subjectType, m.subjectId) : store.setMember(full.project.id, m.subjectType, m.subjectId, r));
                    },
                  ),
              ]),
            ),
          if (admin)
            ListTile(
              key: const ValueKey('member-add'),
              leading: Icon(Icons.person_add_alt, color: look.accent),
              title: Text('Thêm thành viên', style: TextStyle(color: look.accent, fontWeight: FontWeight.w600)),
              onTap: () async {
                final s = await pickSubject(context, store);
                if (s != null) await _run(() => store.setMember(full.project.id, s.type, s.id, s.type == 'everyone' ? 'viewer' : 'member'));
              },
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        decoration: _box(look),
        padding: const EdgeInsets.all(14),
        child: Text.rich(TextSpan(style: TextStyle(fontSize: 12.5, height: 1.7, color: look.sub), children: [
          TextSpan(text: 'Chủ dự án / Quản trị', style: TextStyle(fontWeight: FontWeight.w700, color: look.text)),
          const TextSpan(text: ': sửa cài đặt, quy trình, thành viên\n'),
          TextSpan(text: 'Thành viên', style: TextStyle(fontWeight: FontWeight.w700, color: look.text)),
          const TextSpan(text: ': tạo, sửa, giao việc, bình luận\n'),
          TextSpan(text: 'Người xem', style: TextStyle(fontWeight: FontWeight.w700, color: look.text)),
          const TextSpan(text: ': xem, bình luận, thả cảm xúc\n'),
          TextSpan(text: 'Agent AI', style: TextStyle(fontWeight: FontWeight.w700, color: look.text)),
          const TextSpan(text: ': không cần thêm vào dự án, làm bằng quyền của người bấm Bắt đầu'),
        ])),
      ),
    ]);
  }

  // ------------------------------------------------------------ nhãn
  Widget _labels(TwProjectFull full, TwLook look, bool admin) {
    Future<void> edit([TwLabel? l]) async {
      final r = await twSheet<(String, String)>(context, width: 380, builder: (c) => _LabelEditor(name: l?.name ?? '', color: l?.color ?? '#5B5BD6'));
      if (r == null || r.$1.trim().isEmpty) return;
      await _run(() => store.saveLabel(full.project.id, id: l?.id, name: r.$1.trim(), color: r.$2));
    }

    return ListView(padding: const EdgeInsets.all(20), children: [
      _h('Nhãn', 'Nhãn riêng của dự án, có màu, dùng để lọc và nhóm việc.', look),
      Container(
        decoration: _box(look),
        child: Column(children: [
          for (final l in full.labels)
            ListTile(
              key: ValueKey('label-${l.id}'),
              title: Align(alignment: Alignment.centerLeft, child: LabelChip(l)),
              trailing: !admin
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => edit(l)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _run(() => store.deleteLabel(full.project.id, l.id))),
                    ]),
            ),
          if (full.labels.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Chưa có nhãn', style: TextStyle(color: look.sub))),
          if (admin) ListTile(key: const ValueKey('label-add'), leading: Icon(Icons.add, color: look.accent), title: Text('Thêm nhãn', style: TextStyle(color: look.accent, fontWeight: FontWeight.w600)), onTap: edit),
        ]),
      ),
    ]);
  }

  // ------------------------------------------------------------ lưu trữ / xoá
  Widget _danger(TwProjectFull full, TwLook look) {
    final pr = full.project;
    return ListView(padding: const EdgeInsets.all(20), children: [
      _h('Lưu trữ / xoá', 'Lưu trữ ẩn dự án khỏi danh sách, vẫn tìm được và mở lại được. Xoá là xoá hẳn (chỉ Chủ dự án).', look),
      if (pr.canAdmin)
        OutlinedButton.icon(
          key: const ValueKey('archive'),
          onPressed: () => _run(() => store.updateProject(pr.id, {'archived': !pr.archived})),
          icon: Icon(pr.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
          label: Text(pr.archived ? 'Bỏ lưu trữ' : 'Lưu trữ dự án'),
        ),
      const SizedBox(height: 12),
      if (pr.myRole == 'owner')
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: look.red),
          onPressed: () async {
            if (!await confirm(context, 'Xoá dự án ${pr.name}?', 'Mọi việc, bình luận và tệp của dự án sẽ bị xoá. Không khôi phục được.', ok: 'Xoá hẳn', danger: true)) return;
            await _run(() async {
              await store.deleteProject(pr.id);
              if (mounted) {
                Navigator.of(context)
                  ..pop()
                  ..maybePop();
              }
            });
          },
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Xoá dự án'),
        ),
    ]);
  }
}

class _StatusEditor extends StatefulWidget {
  const _StatusEditor({required this.status, required this.create, required this.canDelete});
  final TwStatus status;
  final bool create, canDelete;
  @override
  State<_StatusEditor> createState() => _StatusEditorState();
}

class _StatusEditorState extends State<_StatusEditor> {
  late final TwStatus s = widget.status;
  late final _name = TextEditingController(text: s.name), _wip = TextEditingController(text: s.wip?.toString() ?? '');

  @override
  void dispose() {
    _name.dispose();
    _wip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.create ? 'Thêm trạng thái' : 'Sửa "${s.name}"', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('st-name'), controller: _name, decoration: const InputDecoration(labelText: 'Tên', border: OutlineInputBorder()), onChanged: (v) => s.name = v),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in kSwatches)
            InkWell(
              key: ValueKey('st-color-$c'),
              onTap: () => setState(() => s.color = c),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle, border: s.color.toUpperCase() == c ? Border.all(color: look.accent, width: 3) : null),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Text('Nhóm', style: TextStyle(fontSize: 12.5, color: look.sub, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final c in kCategories)
            ChoiceChip(
              key: ValueKey('st-cat-$c'),
              label: Text(kCategoryNames[c]!),
              selected: s.category == c,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                s.category = c;
                if (s.isClosed) s.isStart = false;
              }),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('st-wip'),
          controller: _wip,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Giới hạn WIP (để trống = không giới hạn)', border: OutlineInputBorder()),
          onChanged: (v) => s.wip = int.tryParse(v.trim()),
        ),
        SwitchListTile(
          key: const ValueKey('st-start'),
          contentPadding: EdgeInsets.zero,
          value: s.isStart,
          onChanged: s.isClosed ? null : (v) => setState(() => s.isStart = v || s.isStart),
          title: const Text('Trạng thái bắt đầu'),
          subtitle: const Text('Việc có agent được giao vào đây thì agent bắt đầu làm. Mỗi dự án đúng một trạng thái.'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s.review,
          onChanged: (v) => setState(() => s.review = v),
          title: const Text('Agent nộp kết quả vào đây'),
          subtitle: const Text('Agent làm xong chuyển việc sang trạng thái này để người giao duyệt'),
        ),
        SwitchListTile(contentPadding: EdgeInsets.zero, value: s.adminOnly, onChanged: (v) => setState(() => s.adminOnly = v), title: const Text('Chỉ Quản trị được chuyển việc vào')),
        if (s.isDone)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.closeSubtasksPrompt,
            onChanged: (v) => setState(() => s.closeSubtasksPrompt = v),
            title: const Text('Hỏi đóng việc con còn mở'),
          ),
        const SizedBox(height: 10),
        Row(children: [
          if (widget.canDelete) TextButton(key: const ValueKey('st-delete'), style: TextButton.styleFrom(foregroundColor: look.red), onPressed: () => Navigator.pop(context, ('delete', s)), child: const Text('Xoá')),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          const SizedBox(width: 6),
          FilledButton(key: const ValueKey('st-save'), onPressed: () => Navigator.pop(context, ('save', s)), child: const Text('Lưu')),
        ]),
      ]),
    );
  }
}

class _LabelEditor extends StatefulWidget {
  const _LabelEditor({required this.name, required this.color});
  final String name, color;
  @override
  State<_LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends State<_LabelEditor> {
  late final _name = TextEditingController(text: widget.name);
  late String _color = widget.color;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.name.isEmpty ? 'Thêm nhãn' : 'Sửa nhãn', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(key: const ValueKey('label-name'), controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Tên nhãn', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in kSwatches)
              InkWell(
                onTap: () => setState(() => _color = c),
                child: Container(width: 26, height: 26, decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle, border: _color == c ? Border.all(color: TwLook.of(context).text, width: 2.5) : null)),
              ),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
            FilledButton(key: const ValueKey('label-save'), onPressed: () => Navigator.pop(context, (_name.text, _color)), child: const Text('Lưu')),
          ]),
        ]),
      );
}
