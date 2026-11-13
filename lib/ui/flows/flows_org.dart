import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../browser/flygo_id.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowOrange, kFlowRed;
import 'flow_editor.dart' show roleLabel, slugKey;
import 'flow_delegations.dart';
import 'flow_nav.dart';
import 'org_flygo.dart';

/// App Tổ chức (tab Bạn, nhóm Công việc): phòng ban (trưởng phòng, các phó phòng, thành viên; một người thuộc được
/// nhiều phòng), vai trò (Kế toán trưởng, Giám đốc...). Ai cũng xem phòng ban; chỉ quản trị được sửa và xem vai trò.
/// Quy trình dùng sơ đồ này cho người duyệt "quản lý của người tạo" và "cả phòng ban". Ủy quyền khi vắng ở cuối tệp.

String _name(AppState app, String id) {
  final u = app.users[id];
  if (u == null) return id;
  return u.displayName.isNotEmpty ? u.displayName : u.username;
}

/// Chọn người từ danh bạ chat. [single]: chọn một người.
Future<List<String>?> pickUsers(BuildContext context, AppState app, {List<String> selected = const [], bool single = false, String? title}) =>
    showDialog<List<String>>(context: context, builder: (_) => _UserPicker(app: app, selected: selected, single: single, title: title));

class _UserPicker extends StatefulWidget {
  final AppState app;
  final List<String> selected;
  final bool single;
  final String? title;
  const _UserPicker({required this.app, required this.selected, required this.single, this.title});
  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  late final sel = {...widget.selected};
  String q = '';

  @override
  Widget build(BuildContext context) {
    final people = widget.app.users.values
        .where((u) => !u.isBot && u.deleteAt == 0 && (q.isEmpty || '${u.displayName} ${u.username}'.toLowerCase().contains(q.toLowerCase())))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return AlertDialog(
      title: Text(widget.title ?? (widget.single ? tr('Chọn người') : tr('Chọn người ({0})', [sel.length]))),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm người'), isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => setState(() => q = v),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(children: [
              for (final u in people)
                widget.single
                    ? ListTile(
                        leading: Avatar(userId: u.id, name: u.displayName, size: 32, status: false),
                        title: Text(u.displayName.isEmpty ? u.username : u.displayName),
                        trailing: sel.contains(u.id) ? const Icon(Icons.check_rounded) : null,
                        onTap: () => Navigator.pop(context, [u.id]),
                      )
                    : CheckboxListTile(
                        value: sel.contains(u.id),
                        onChanged: (v) => setState(() => v == true ? sel.add(u.id) : sel.remove(u.id)),
                        secondary: Avatar(userId: u.id, name: u.displayName, size: 32, status: false),
                        title: Text(u.displayName.isEmpty ? u.username : u.displayName),
                        dense: true,
                      ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        if (!widget.single) FilledButton(onPressed: () => Navigator.pop(context, sel.toList()), child: Text(tr('Xong'))),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------- trang Tổ chức

class FlowsOrgPage extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  /// Chỉ cho ảnh xem trước: dữ liệu sẵn, không gọi máy chủ.
  final List<Map<String, dynamic>>? debugDepts;
  final Map<String, List<String>>? debugRoles;
  /// Chỉ cho ảnh xem trước: chế độ chỉ xem.
  final bool debugReadOnly;
  const FlowsOrgPage({super.key, required this.app, required this.api, this.debugDepts, this.debugRoles, this.debugReadOnly = false});
  @override
  State<FlowsOrgPage> createState() => _FlowsOrgPageState();
}

class _FlowsOrgPageState extends State<FlowsOrgPage> {
  List<Map<String, dynamic>>? _depts;
  Map<String, List<String>>? _roles;
  String? _err;
  bool _dirtyDepts = false, _dirtyRoles = false, _busy = false, _canEdit = false;

  /// Flygo ID của máy chủ: sơ đồ tổ chức và quyền nằm ở đó. null khi đang dò; [_noFlygoId] khi máy chủ không có.
  FlygoId? _fid;
  bool _noFlygoId = false;

  @override
  void initState() {
    super.initState();
    if (widget.debugDepts != null) {
      _depts = widget.debugDepts;
      _roles = widget.debugRoles ?? {};
      _canEdit = !widget.debugReadOnly;
    } else {
      _discover();
    }
  }

  Future<void> _discover() async {
    try {
      final f = await FlygoId.current(widget.app.token);
      if (!mounted) return;
      setState(() => f == null ? _noFlygoId = true : _fid = f);
    } catch (e) {
      if (mounted) setState(() => _err = tr('Không hỏi được Flygo ID của máy chủ: {0}', ['$e']));
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final m = ScaffoldMessenger.of(context);
    try {
      if (_dirtyDepts) await widget.api.saveDepartments(_depts!);
      if (_dirtyRoles) await widget.api.saveRoles(_roles!);
      setState(() => _dirtyDepts = _dirtyRoles = false);
      m.showSnackBar(toast(Text(tr('Đã lưu sơ đồ tổ chức'))));
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Phòng ban xếp theo cây: (phòng, độ sâu).
  List<(Map<String, dynamic>, int)> _tree() {
    final ds = _depts ?? const [];
    final out = <(Map<String, dynamic>, int)>[];
    final ids = {for (final d in ds) d['id']};
    void walk(String? parent, int depth) {
      for (final d in ds.where((d) => (d['parent'] == null || !ids.contains(d['parent']) ? null : d['parent']) == parent)) {
        if (out.any((x) => x.$1['id'] == d['id']) || depth > 10) continue;
        out.add((d, depth));
        walk('${d['id']}', depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  Future<void> _editDept([Map<String, dynamic>? d]) async {
    final r = await showDialog<Object>(context: context, builder: (_) => _DeptDialog(app: widget.app, dept: d, all: _depts ?? const [], readOnly: !_canEdit));
    if (r == null || !mounted) return;
    if (r == 'delete' && d != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Xoá phòng ban?')),
          content: Text(tr('Xoá "{0}". Phòng con chuyển lên phòng cấp trên. Bấm Lưu để áp dụng.', ['${d['name']}'])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Xoá'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      if (r == 'delete' && d != null) {
        _depts!.remove(d);
        for (final x in _depts!) {
          if (x['parent'] == d['id']) x['parent'] = d['parent'];
        }
      } else if (r is Map<String, dynamic>) {
        d == null ? _depts!.add(r) : _depts![_depts!.indexOf(d)] = r;
      }
      _dirtyDepts = true;
    });
  }

  /// Số người trong phòng: trưởng + phó + thành viên (không đếm trùng).
  int _headcount(Map<String, dynamic> d) => {
        if (d['manager'] != null && '${d['manager']}'.isNotEmpty) '${d['manager']}',
        for (final u in (d['deputies'] as List? ?? const [])) '$u',
        for (final u in (d['members'] as List? ?? const [])) '$u',
      }.length;

  Widget _deptTab(Pal pal) {
    final tree = _tree();
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(
              _canEdit
                  ? tr('Một người thuộc được nhiều phòng. Quy trình dùng cho người duyệt "Quản lý của người tạo" (trưởng phòng; người tạo là trưởng phòng thì lên phòng cấp trên) và "Cả phòng ban".')
                  : tr('Chỉ quản trị viên được sửa phòng ban.'),
              style: TextStyle(color: pal.sub, fontSize: 12.5)),
        ),
        if (tree.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr('Chưa có phòng ban nào.'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub))),
        for (final (d, depth) in tree)
          Padding(
            padding: EdgeInsets.only(left: depth * 18.0, bottom: 8),
            child: Material(
              color: pal.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: pal.divider)),
              child: ListTile(
                leading: Icon(depth == 0 ? Icons.account_balance_outlined : Icons.subdirectory_arrow_right_rounded, color: pal.accent),
                title: Text('${d['name']}', style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                subtitle: Text([
                  d['manager'] == null || '${d['manager']}'.isEmpty ? tr('Chưa có trưởng phòng') : tr('Trưởng: {0}', [_name(widget.app, '${d['manager']}')]),
                  if ((d['deputies'] as List? ?? const []).isNotEmpty) tr('{0} phó phòng', [(d['deputies'] as List).length]),
                  tr('{0} người', [_headcount(d)]),
                ].join(' · '), style: TextStyle(color: d['manager'] == null ? kFlowOrange : pal.sub)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editDept(d),
              ),
            ),
          ),
      ]),
      if (_canEdit) Positioned(right: 16, bottom: 16, child: FloatingActionButton.extended(heroTag: 'dept', onPressed: () => _editDept(), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm phòng ban')))),
    ]);
  }

  Widget _roleTab(Pal pal) {
    final roles = _roles ?? {};
    final names = ({...roles.keys, 'flow_admin'}.toList()..sort());
    String label(String r) => r == 'flow_admin' ? tr('Quản trị quy trình') : roleLabel(r);
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(tr('Vai trò dùng chung cả công ty (Kế toán trưởng, Giám đốc, Thủ quỹ...). "Quản trị quy trình" được soạn và bật/tắt quy trình.'),
              style: TextStyle(color: pal.sub, fontSize: 12.5)),
        ),
        for (final r in names)
          Card(
            elevation: 0,
            color: pal.surface,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: pal.divider)),
            child: ListTile(
              leading: Icon(r == 'flow_admin' ? Icons.admin_panel_settings_outlined : Icons.badge_outlined, color: pal.accent),
              title: Text(label(r), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
              subtitle: Text(
                (roles[r] ?? const []).isEmpty ? tr('Chưa có ai') : [for (final u in roles[r]!) _name(widget.app, u)].join(', '),
                style: TextStyle(color: (roles[r] ?? const []).isEmpty ? kFlowOrange : pal.sub),
              ),
              trailing: const Icon(Icons.edit_outlined, size: 18),
              onTap: () async {
                final v = await pickUsers(context, widget.app, selected: roles[r] ?? const [], title: label(r));
                if (v != null) {
                  setState(() {
                    _roles![r] = v;
                    _dirtyRoles = true;
                  });
                }
              },
            ),
          ),
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'role',
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('Thêm vai trò')),
          onPressed: () async {
            final ctl = TextEditingController();
            final name = await showDialog<String>(
              context: context,
              builder: (d) => AlertDialog(
                title: Text(tr('Vai trò mới')),
                content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: tr('Ví dụ: Thủ kho')), onSubmitted: (v) => Navigator.pop(d, v)),
                actions: [FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Thêm')))],
              ),
            );
            final key = slugKey(name ?? '');
            if (key.isNotEmpty) {
              setState(() {
                _roles!.putIfAbsent(key, () => []);
                _dirtyRoles = true;
              });
            }
          },
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.debugDepts == null) {
      // Sơ đồ tổ chức và quyền ở Flygo ID. Máy chủ chưa có Flygo ID thì báo lỗi (không còn sửa trong Quy trình).
      final body = _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center)))
          : _noFlygoId
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('Máy chủ chat này chưa có Flygo ID nên chưa quản lý được tổ chức và quyền. Hãy báo quản trị viên.'), textAlign: TextAlign.center),
                  ),
                )
              : _fid == null
                  ? const Center(child: CircularProgressIndicator())
                  : FlygoOrgView(app: widget.app, fid: _fid!, extraTabs: [(tr('Lịch làm việc'), WorkCalendarTab(api: widget.api))]);
      return Scaffold(appBar: AppBar(title: Text(tr('Tổ chức'))), body: body);
    }
    final pal = Pal.of(context);
    final dirty = _dirtyDepts || _dirtyRoles;
    final loaded = _err == null && _depts != null;
    return DefaultTabController(
      length: _canEdit ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Tổ chức')),
          actions: [
            if (_canEdit)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(onPressed: !dirty || _busy ? null : _save, child: Text(tr('Lưu'))),
              ),
          ],
          bottom: loaded
              ? TabBar(tabs: [Tab(text: tr('Phòng ban')), if (_canEdit) Tab(text: tr('Vai trò')), Tab(text: tr('Lịch làm việc'))])
              : null,
        ),
        body: _err != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center)))
            : _depts == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _deptTab(pal),
                    if (_canEdit) _roleTab(pal),
                    WorkCalendarTab(api: widget.api, debug: widget.debugDepts != null),
                  ]),
      ),
    );
  }
}

class _DeptDialog extends StatefulWidget {
  final AppState app;
  final Map<String, dynamic>? dept;
  final List<Map<String, dynamic>> all;
  final bool readOnly;
  const _DeptDialog({required this.app, required this.dept, required this.all, this.readOnly = false});
  @override
  State<_DeptDialog> createState() => _DeptDialogState();
}

class _DeptDialogState extends State<_DeptDialog> {
  late final name = TextEditingController(text: '${widget.dept?['name'] ?? ''}');
  late String? parent = widget.dept?['parent'] as String?;
  late String? manager = widget.dept?['manager'] as String?;
  late List<String> deputies = [for (final m in (widget.dept?['deputies'] as List? ?? const [])) '$m'];
  late List<String> members = [for (final m in (widget.dept?['members'] as List? ?? const [])) '$m'];

  /// Danh sách người (phó phòng / thành viên): chip, nút Chọn khi được sửa.
  Widget _people(String label, List<String> list, void Function(List<String>) set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('$label (${list.length})', style: Theme.of(context).textTheme.labelLarge)),
          if (!widget.readOnly)
            TextButton.icon(
              onPressed: () async {
                final v = await pickUsers(context, widget.app, selected: list, title: label);
                if (v != null) setState(() => set(v));
              },
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: Text(tr('Chọn')),
            ),
        ]),
        if (widget.readOnly) const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in list)
            widget.readOnly ? Chip(label: Text(_name(widget.app, m))) : InputChip(label: Text(_name(widget.app, m)), onDeleted: () => setState(() => list.remove(m))),
        ]),
        const SizedBox(height: 12),
      ]);

  /// Phòng không được làm cha của chính nó (hay của phòng cha nó).
  bool _isDescendant(String id) {
    final me = widget.dept?['id'];
    if (me == null) return false;
    String? p = id;
    for (var i = 0; p != null && i < 20; i++) {
      if (p == me) return true;
      p = widget.all.where((d) => d['id'] == p).firstOrNull?['parent'] as String?;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final parents = [for (final d in widget.all) if (!_isDescendant('${d['id']}')) d];
    final ro = widget.readOnly;
    final parentName = widget.all.where((d) => d['id'] == parent).firstOrNull?['name'];
    return AlertDialog(
      title: Text(ro ? '${widget.dept?['name'] ?? ''}' : (widget.dept == null ? tr('Thêm phòng ban') : tr('Sửa phòng ban'))),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!ro) ...[
              TextField(controller: name, autofocus: widget.dept == null, decoration: InputDecoration(labelText: tr('Tên phòng ban'), border: const OutlineInputBorder()), onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: parents.any((d) => d['id'] == parent) ? parent : '',
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Thuộc phòng'), border: const OutlineInputBorder()),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('(Cấp cao nhất)'))),
                  for (final d in parents) DropdownMenuItem(value: '${d['id']}', child: Text('${d['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => parent = (v == null || v.isEmpty) ? null : v),
              ),
              const SizedBox(height: 12),
            ] else if (parentName != null) ...[
              Text(tr('Thuộc phòng: {0}', ['$parentName']), style: TextStyle(color: pal.sub)),
              const SizedBox(height: 12),
            ],
            InputDecorator(
              decoration: InputDecoration(labelText: tr('Trưởng phòng'), border: const OutlineInputBorder(), contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4)),
              child: Row(children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: ro ? 10 : 0),
                    child: Text(manager == null ? tr('Chưa chọn') : _name(widget.app, manager!), style: TextStyle(color: manager == null ? pal.sub : pal.text)),
                  ),
                ),
                if (!ro && manager != null) IconButton(tooltip: tr('Bỏ'), onPressed: () => setState(() => manager = null), icon: const Icon(Icons.close_rounded, size: 18)),
                if (!ro)
                  TextButton(
                    onPressed: () async {
                      final v = await pickUsers(context, widget.app, selected: [?manager], single: true, title: tr('Trưởng phòng'));
                      if (v != null && v.isNotEmpty) {
                        setState(() {
                          manager = v.first;
                          deputies.remove(manager);
                          members.remove(manager);
                        });
                      }
                    },
                    child: Text(tr('Chọn')),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            _people(tr('Phó phòng'), deputies, (v) {
              deputies = [for (final u in v) if (u != manager) u];
              members.removeWhere(deputies.contains);
            }),
            _people(tr('Thành viên'), members, (v) => members = [for (final u in v) if (u != manager && !deputies.contains(u)) u]),
          ]),
        ),
      ),
      actions: ro
          ? [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng')))]
          : [
              if (widget.dept != null) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: Text(tr('Xoá'), style: const TextStyle(color: kFlowRed))),
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
              FilledButton(
                onPressed: name.text.trim().isEmpty
                    ? null
                    : () {
                        final id = widget.dept?['id'] ?? _newId(name.text);
                        Navigator.pop(context, <String, dynamic>{
                          'id': id,
                          'name': name.text.trim(),
                          if (parent != null) 'parent': parent,
                          if (manager != null) 'manager': manager,
                          'deputies': deputies,
                          'members': members,
                        });
                      },
                child: Text(tr('Xong')),
              ),
            ],
    );
  }

  String _newId(String name) {
    final base = slugKey(name).isEmpty ? 'phong' : slugKey(name);
    var id = base;
    for (var i = 2; widget.all.any((d) => d['id'] == id); i++) {
      id = '${base}_$i';
    }
    return id;
  }
}

// ---------------------------------------------------------------------------------------------- ủy quyền

/// Trang ủy quyền riêng (ngoài tab Ủy quyền của trang Quy trình).
class DelegationPage extends StatelessWidget {
  final AppState app;
  final FlowsApi api;
  const DelegationPage({super.key, required this.app, required this.api});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: flowLeading(context), title: Text(tr('Ủy quyền'))),
        body: DelegationsTab(app: app, api: api),
      );
}

// ---------------------------------------------------------------------------------------------- lịch làm việc

/// Lịch làm việc của công ty: ngày làm việc trong tuần và ngày nghỉ lễ. Thời hạn "N ngày làm việc" của quy trình
/// (hạn duyệt, nhắc lại, chờ) bỏ qua ngày nghỉ. Ai cũng xem, quản trị sửa.
class WorkCalendarTab extends StatefulWidget {
  final FlowsApi api;
  /// Ảnh xem trước: dữ liệu mẫu, không gọi máy chủ.
  final bool debug;
  const WorkCalendarTab({super.key, required this.api, this.debug = false});
  @override
  State<WorkCalendarTab> createState() => _WorkCalendarTabState();
}

class _WorkCalendarTabState extends State<WorkCalendarTab> {
  List<int>? _days;
  List<String> _holidays = [];
  bool _canEdit = false, _dirty = false, _busy = false;
  String? _err;
  static const _names = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

  @override
  void initState() {
    super.initState();
    if (widget.debug) {
      _days = [1, 2, 3, 4, 5, 6];
      _holidays = ['2027-01-01', '2027-02-05', '2027-02-08', '2027-04-30', '2027-05-01', '2027-09-02'];
      _canEdit = true;
      return;
    }
    widget.api.calendar().then((r) {
      if (!mounted) return;
      final c = (r['calendar'] as Map?) ?? const {};
      setState(() {
        _days = [for (final d in (c['weekdays'] as List? ?? const [1, 2, 3, 4, 5])) (d as num).toInt()];
        _holidays = [for (final h in (c['holidays'] as List? ?? const [])) '$h']..sort();
        _canEdit = r['can_edit'] == true;
      });
    }).catchError((e) {
      if (mounted) setState(() => _err = '$e');
    });
  }

  String _dmy(String ymd) {
    final p = ymd.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : ymd;
  }

  Future<void> _addHoliday() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null) return;
    final s = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (_holidays.contains(s)) return;
    setState(() {
      _holidays = [..._holidays, s]..sort();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final m = ScaffoldMessenger.of(context);
    try {
      await widget.api.saveCalendar(_days!, _holidays);
      setState(() => _dirty = false);
      m.showSnackBar(toast(Text(tr('Đã lưu lịch làm việc'))));
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (_err != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!)));
    final days = _days;
    if (days == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(tr('Thời hạn tính theo "ngày làm việc" trong quy trình (hạn duyệt, nhắc lại, chờ) bỏ qua ngày nghỉ dưới đây.'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
      const SizedBox(height: 14),
      Text(tr('Ngày làm việc trong tuần'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var d = 1; d <= 7; d++)
          FilterChip(
            label: Text(tr(_names[d - 1])),
            selected: days.contains(d),
            onSelected: !_canEdit
                ? null
                : (v) => setState(() {
                      _days = v ? ([...days, d]..sort()) : ([...days]..remove(d));
                      _dirty = true;
                    }),
          ),
      ]),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Text(tr('Ngày nghỉ lễ ({0})', [_holidays.length]), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
        if (_canEdit) TextButton.icon(onPressed: _addHoliday, icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm ngày nghỉ'))),
      ]),
      if (_holidays.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('Chưa có ngày nghỉ lễ nào.'), style: TextStyle(color: pal.sub))),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final h in _holidays)
          _canEdit
              ? InputChip(label: Text(_dmy(h)), onDeleted: () => setState(() {
                    _holidays = [..._holidays]..remove(h);
                    _dirty = true;
                  }))
              : Chip(label: Text(_dmy(h))),
      ]),
      if (_canEdit) ...[
        const SizedBox(height: 20),
        FilledButton(onPressed: !_dirty || _busy || days.isEmpty ? null : _save, child: Text(tr('Lưu lịch làm việc'))),
      ],
    ]);
  }
}
