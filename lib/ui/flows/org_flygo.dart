import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../browser/flygo_id.dart';
import '../../config.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowOrange, kFlowRed;
import 'flow_editor.dart' show roleLabel, slugKey;
import 'flows_org.dart' show pickUsers;

/// Tổ chức khi máy chủ có Flygo ID: sơ đồ phòng ban (cây như thư mục) và quyền dùng tool MCP / app của từng phòng
/// ban hoặc từng người, sửa ngay trên một trang. Trên máy tính chia hai cột: trái là cây phòng ban (nháy phải để
/// thêm / sửa / xoá), phải là quyền của mục đang chọn (tick để cho phép). Ai cũng xem cây; chỉ quản trị Flygo ID
/// (Sếp) sửa được và thấy quyền. Mỗi thao tác lưu ngay vào Flygo ID (kiểm phiên bản để không ghi đè người khác).

class _Api {
  _Api(this.fid);
  final FlygoId fid;

  Future<Map<String, dynamic>> call(String method, String path, [Object? body]) async {
    final test = FlygoOrgView.debugClient;
    final req = http.Request(method, Uri.parse('${fid.base}$path'))
      ..headers.addAll({
        'Authorization': 'Bearer ${fid.chatToken}',
        'X-MM-Server': kServerUrl,
        'X-Flygo-Device': test != null ? 'test' : await FlygoId.deviceId(),
        'Content-Type': 'application/json',
        'User-Agent': kUserAgent,
      });
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await (test ?? http.Client()).send(req).timeout(const Duration(seconds: 20)));
    Map<String, dynamic> j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw FlygoIdException(res.statusCode, '${j['error'] ?? tr('Flygo ID trả lỗi {0}', [res.statusCode])}');
    return j;
  }
}

/// Mục đang chọn ở cột trái: một phòng ban hoặc một người.
class _Sel {
  const _Sel(this.type, this.id);
  final String type; // 'dept' | 'user' | 'everyone'
  final String id;
  @override
  bool operator ==(Object o) => o is _Sel && o.type == type && o.id == id;
  @override
  int get hashCode => Object.hash(type, id);
}

class FlygoOrgView extends StatefulWidget {
  /// Chỉ cho test / ảnh xem trước: thay HTTP thật.
  static http.Client? debugClient;
  final AppState app;
  final FlygoId fid;
  /// Thêm tab sau các tab của trang (vd Lịch làm việc của Quy trình).
  final List<(String, Widget)> extraTabs;
  const FlygoOrgView({super.key, required this.app, required this.fid, this.extraTabs = const []});
  @override
  State<FlygoOrgView> createState() => _FlygoOrgViewState();
}

class _FlygoOrgViewState extends State<FlygoOrgView> {
  late final _api = _Api(widget.fid);
  Map<String, Map<String, dynamic>> _depts = {};
  Map<String, dynamic> _roles = {}, _delegations = {};
  int _version = 0;
  bool _canEdit = false, _busy = false, _loaded = false;
  String? _err;
  _Sel? _sel;
  final _open = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.call('GET', '/v1/org');
      if (!mounted) return;
      setState(() {
        _depts = {for (final e in ((r['departments'] as Map?) ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map)};
        _roles = Map<String, dynamic>.from((r['roles'] as Map?) ?? const {});
        _delegations = Map<String, dynamic>.from((r['delegations'] as Map?) ?? const {});
        _version = (r['version'] as num?)?.toInt() ?? 0;
        _canEdit = r['can_edit'] == true;
        _loaded = true;
        _err = null;
        if (_open.isEmpty) _open.addAll(_depts.keys.where((k) => _depts[k]!['parent'] == null));
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  String _name(String id) {
    final u = widget.app.users[id];
    if (u == null) return id;
    return u.displayName.isNotEmpty ? u.displayName : u.username;
  }

  List<Map<String, dynamic>> _members(Map<String, dynamic> d) => [for (final m in (d['members'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];

  /// Ghi cả sơ đồ (Flygo ID nhận nguyên sơ đồ). [change] sửa bản sao; lỗi phiên bản thì tải lại.
  Future<void> _mutate(void Function(Map<String, Map<String, dynamic>> depts, Map<String, dynamic> roles) change) async {
    final depts = {for (final e in _depts.entries) e.key: jsonDecode(jsonEncode(e.value)) as Map<String, dynamic>};
    final roles = jsonDecode(jsonEncode(_roles)) as Map<String, dynamic>;
    change(depts, roles);
    setState(() => _busy = true);
    final m = ScaffoldMessenger.of(context);
    try {
      final r = await _api.call('PUT', '/v1/admin/directory', {
        'departments': depts,
        'roles': roles,
        'delegations': _delegations,
        'expect_version': _version,
      });
      _version = (r['version'] as num?)?.toInt() ?? _version + 1;
      setState(() {
        _depts = depts;
        _roles = roles;
      });
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
      await _load();
    }
    if (mounted) setState(() => _busy = false);
  }

  // ------------------------------------------------------------------ thao tác trên cây

  Future<String?> _ask(String title, {String initial = '', String hint = ''}) async {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(d, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Xong'))),
        ],
      ),
    );
  }

  String _newId(String name) {
    final base = slugKey(name).isEmpty ? 'phong' : slugKey(name);
    var id = base;
    for (var i = 2; _depts.containsKey(id); i++) {
      id = '${base}_$i';
    }
    return id;
  }

  Future<void> _addDept(String? parent) async {
    final name = (await _ask(parent == null ? tr('Thêm phòng ban') : tr('Thêm phòng ban con'), hint: tr('Ví dụ: Kế toán')))?.trim() ?? '';
    if (name.isEmpty) return;
    final id = _newId(name);
    await _mutate((d, _) => d[id] = {'id': id, 'name': name, 'parent': parent, 'manager': null, 'members': <Object>[]});
    setState(() {
      if (parent != null) _open.add(parent);
      _sel = _Sel('dept', id);
    });
  }

  Future<void> _rename(String id) async {
    final name = (await _ask(tr('Đổi tên phòng ban'), initial: '${_depts[id]?['name'] ?? ''}'))?.trim() ?? '';
    if (name.isNotEmpty) await _mutate((d, _) => d[id]!['name'] = name);
  }

  Future<void> _move(String id) async {
    bool under(String? p) {
      for (var i = 0; p != null && i < 50; i++) {
        if (p == id) return true;
        p = _depts[p]?['parent'] as String?;
      }
      return false;
    }

    final choices = [for (final d in _depts.values) if (!under('${d['id']}')) d];
    final v = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: Text(tr('Chuyển "{0}" vào phòng', ['${_depts[id]?['name']}'])), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(c, ''), child: Text(tr('(Cấp cao nhất)'))),
        for (final d in choices) SimpleDialogOption(onPressed: () => Navigator.pop(c, '${d['id']}'), child: Text('${d['name']}')),
      ]),
    );
    if (v != null) await _mutate((d, _) => d[id]!['parent'] = v.isEmpty ? null : v);
  }

  Future<void> _deleteDept(String id) async {
    final d0 = _depts[id];
    if (d0 == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Xoá phòng ban?')),
        content: Text(tr('Xoá "{0}". Phòng con chuyển lên phòng cấp trên. Quyền gán cho phòng này không còn tác dụng.', ['${d0['name']}'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Hủy'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: kFlowRed), onPressed: () => Navigator.pop(c, true), child: Text(tr('Xoá'))),
        ],
      ),
    );
    if (ok != true) return;
    await _mutate((d, _) {
      d.remove(id);
      for (final x in d.values) {
        if (x['parent'] == id) x['parent'] = d0['parent'];
      }
    });
    if (_sel == _Sel('dept', id)) setState(() => _sel = null);
  }

  Future<void> _addMembers(String id) async {
    final cur = [for (final m in _members(_depts[id]!)) '${m['user']}'];
    final v = await pickUsers(context, widget.app, selected: cur, title: tr('Thành viên {0}', ['${_depts[id]?['name']}']));
    if (v == null) return;
    await _mutate((d, _) {
      final old = {for (final m in _members(d[id]!)) '${m['user']}': m};
      d[id]!['members'] = [for (final u in v) old[u] ?? {'user': u, 'primary': false, 'deputy': false}];
      if (d[id]!['manager'] != null && !v.contains(d[id]!['manager'])) d[id]!['manager'] = null;
    });
    setState(() => _open.add(id));
  }

  Future<void> _memberOp(String dept, String user, String op) => _mutate((d, _) {
        final x = d[dept]!;
        final ms = _members(x);
        switch (op) {
          case 'manager':
            x['manager'] = x['manager'] == user ? null : user;
          case 'deputy':
            for (final m in ms) {
              if (m['user'] == user) m['deputy'] = !(m['deputy'] == true);
            }
          case 'primary':
            // Mỗi người một phòng chính: bỏ ở các phòng khác.
            for (final y in d.values) {
              y['members'] = [
                for (final m in _members(y)) {...m, 'primary': y['id'] == dept && m['user'] == user ? true : (m['user'] == user ? false : m['primary'] == true)},
              ];
            }
            return;
          case 'remove':
            ms.removeWhere((m) => m['user'] == user);
            if (x['manager'] == user) x['manager'] = null;
        }
        x['members'] = ms;
      });

  Future<void> _deptMenu(String id, Offset at) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(value: 'sub', child: ListTile(dense: true, leading: const Icon(Icons.create_new_folder_outlined), title: Text(tr('Thêm phòng ban con')))),
        PopupMenuItem(value: 'members', child: ListTile(dense: true, leading: const Icon(Icons.group_add_outlined), title: Text(tr('Thêm / bớt thành viên')))),
        PopupMenuItem(value: 'rename', child: ListTile(dense: true, leading: const Icon(Icons.edit_outlined), title: Text(tr('Đổi tên')))),
        PopupMenuItem(value: 'move', child: ListTile(dense: true, leading: const Icon(Icons.drive_file_move_outline), title: Text(tr('Chuyển sang phòng khác')))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: const Icon(Icons.delete_outline, color: kFlowRed), title: Text(tr('Xoá phòng ban'), style: const TextStyle(color: kFlowRed)))),
      ],
    );
    switch (v) {
      case 'sub':
        await _addDept(id);
      case 'members':
        await _addMembers(id);
      case 'rename':
        await _rename(id);
      case 'move':
        await _move(id);
      case 'delete':
        await _deleteDept(id);
    }
  }

  Future<void> _memberMenu(String dept, Map<String, dynamic> m, Offset at) async {
    final u = '${m['user']}';
    final isMgr = _depts[dept]?['manager'] == u;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(value: 'manager', child: Text(isMgr ? tr('Bỏ trưởng phòng') : tr('Đặt làm trưởng phòng'))),
        PopupMenuItem(value: 'deputy', child: Text(m['deputy'] == true ? tr('Bỏ phó phòng') : tr('Đặt làm phó phòng'))),
        if (m['primary'] != true) PopupMenuItem(value: 'primary', child: Text(tr('Đặt làm phòng chính của người này'))),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'remove', child: Text(tr('Xoá khỏi phòng'), style: const TextStyle(color: kFlowRed))),
      ],
    );
    if (v != null) await _memberOp(dept, u, v);
  }

  // ------------------------------------------------------------------ cây phòng ban

  List<Widget> _treeRows(Pal pal, String? parent, int depth, {required bool wide}) {
    final kids = _depts.values.where((d) => (d['parent'] == null || !_depts.containsKey(d['parent']) ? null : d['parent']) == parent).toList()
      ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    final out = <Widget>[];
    for (final d in kids) {
      final id = '${d['id']}';
      if (depth > 12) break;
      final open = _open.contains(id);
      final members = _members(d)
        ..sort((a, b) {
          int rank(Map m) => d['manager'] == m['user'] ? 0 : (m['deputy'] == true ? 1 : 2);
          final r = rank(a).compareTo(rank(b));
          return r != 0 ? r : _name('${a['user']}').compareTo(_name('${b['user']}'));
        });
      final sel = _sel == _Sel('dept', id);
      out.add(_row(
        pal,
        depth: depth,
        selected: sel,
        leading: IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => setState(() => open ? _open.remove(id) : _open.add(id)),
          icon: Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded),
        ),
        icon: Icon(open ? Icons.folder_open_rounded : Icons.folder_rounded, color: pal.accent, size: 20),
        title: '${d['name']}',
        subtitle: d['manager'] == null ? tr('Chưa có trưởng phòng') : null,
        subtitleColor: kFlowOrange,
        trailing: _canEdit
            ? [
                IconButton(tooltip: tr('Thêm phòng ban con'), visualDensity: VisualDensity.compact, iconSize: 18, onPressed: _busy ? null : () => _addDept(id), icon: const Icon(Icons.create_new_folder_outlined)),
                IconButton(tooltip: tr('Thêm thành viên'), visualDensity: VisualDensity.compact, iconSize: 18, onPressed: _busy ? null : () => _addMembers(id), icon: const Icon(Icons.person_add_alt_outlined)),
              ]
            : const [],
        onTap: () => _select(_Sel('dept', id), wide: wide),
        onMenu: _canEdit ? (at) => _deptMenu(id, at) : null,
      ));
      if (!open) continue;
      out.addAll(_treeRows(pal, id, depth + 1, wide: wide));
      for (final m in members) {
        final u = '${m['user']}';
        final badges = [
          if (d['manager'] == u) tr('Trưởng phòng'),
          if (m['deputy'] == true) tr('Phó phòng'),
          if (m['primary'] == true) tr('phòng chính'),
        ];
        out.add(_row(
          pal,
          depth: depth + 1,
          selected: _sel == _Sel('user', u),
          leading: const SizedBox(width: 40),
          icon: Avatar(userId: u, name: _name(u), size: 22, status: false),
          title: _name(u),
          subtitle: badges.isEmpty ? null : badges.join(' · '),
          subtitleColor: pal.sub,
          trailing: const [],
          onTap: () => _select(_Sel('user', u), wide: wide),
          onMenu: _canEdit ? (at) => _memberMenu(id, m, at) : null,
        ));
      }
    }
    return out;
  }

  Widget _row(Pal pal,
      {required int depth,
      required bool selected,
      required Widget leading,
      required Widget icon,
      required String title,
      String? subtitle,
      required Color subtitleColor,
      required List<Widget> trailing,
      required VoidCallback onTap,
      void Function(Offset)? onMenu}) {
    return GestureDetector(
      onSecondaryTapDown: onMenu == null ? null : (e) => onMenu(e.globalPosition),
      onLongPressStart: onMenu == null ? null : (e) => onMenu(e.globalPosition),
      child: Material(
        color: selected ? pal.chipSelBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(left: depth * 20.0, right: 4),
            child: SizedBox(
              height: subtitle == null ? 38 : 46,
              child: Row(children: [
                leading,
                icon,
                const SizedBox(width: 8),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? pal.chipSelFg : pal.text, fontWeight: FontWeight.w600)),
                    if (subtitle != null) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: subtitleColor, fontSize: 11.5)),
                  ]),
                ),
                ...trailing,
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _select(_Sel s, {required bool wide}) {
    setState(() => _sel = s);
    if (!wide && _canEdit) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(_selTitle(s))),
          body: _PermPanel(key: ValueKey(s), api: _api, sel: s, title: null, deptName: (id) => '${_depts[id]?['name'] ?? id}', roleName: _roleName),
        ),
      ));
    }
  }

  String _selTitle(_Sel s) => switch (s.type) {
        'dept' => '${_depts[s.id]?['name'] ?? s.id}',
        'everyone' => tr('Mọi người (cả công ty)'),
        _ => _name(s.id),
      };

  String _roleName(String id) => '${(_roles[id] as Map?)?['name'] ?? roleLabel(id)}';

  Widget _tree(Pal pal, {required bool wide}) {
    final rows = _treeRows(pal, null, 0, wide: wide);
    return ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 80), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _canEdit
                ? tr('Nháy phải (giữ lâu trên điện thoại) vào phòng ban hoặc người để sửa. Quyền gán cho phòng ban áp dụng cho cả phòng con.')
                : tr('Chỉ quản trị viên được sửa phòng ban.'),
            style: TextStyle(color: pal.sub, fontSize: 12.5),
          ),
          if (_canEdit) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(onPressed: _busy ? null : () => _addDept(null), icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Thêm phòng ban'))),
          ],
        ]),
      ),
      if (_canEdit)
        _row(
          pal,
          depth: 0,
          selected: _sel == const _Sel('everyone', '*'),
          leading: const SizedBox(width: 40),
          icon: Icon(Icons.groups_rounded, color: pal.accent, size: 20),
          title: tr('Mọi người (cả công ty)'),
          subtitle: tr('Quyền tick ở đây áp cho mọi nhân viên, không áp cho bot và agent'),
          subtitleColor: pal.sub,
          trailing: const [],
          onTap: () => _select(const _Sel('everyone', '*'), wide: wide),
        ),
      if (rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(tr('Chưa có phòng ban nào.'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub))),
      ...rows,
    ]);
  }

  // ------------------------------------------------------------------ vai trò

  Widget _rolesTab(Pal pal) {
    final ids = ({..._roles.keys, 'flow_admin'}.toList()..sort());
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 80), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(children: [
          Expanded(child: Text(tr('Vai trò dùng chung cả công ty (Kế toán trưởng, Giám đốc, Thủ quỹ...), dùng cho người duyệt trong quy trình.'), style: TextStyle(color: pal.sub, fontSize: 12.5))),
          FilledButton.tonalIcon(
            onPressed: _busy
                ? null
                : () async {
                    final name = (await _ask(tr('Vai trò mới'), hint: tr('Ví dụ: Thủ kho')))?.trim() ?? '';
                    final key = slugKey(name);
                    if (key.isNotEmpty) await _mutate((_, r) => r.putIfAbsent(key, () => {'name': name, 'members': <String>[]}));
                  },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr('Thêm vai trò')),
          ),
        ]),
      ),
      for (final r in ids)
        Card(
          elevation: 0,
          color: pal.surface,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: pal.divider)),
          child: ListTile(
            leading: Icon(Icons.badge_outlined, color: pal.accent),
            title: Text(r == 'flow_admin' && !_roles.containsKey(r) ? tr('Quản trị quy trình') : _roleName(r), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
            subtitle: Builder(builder: (_) {
              final ms = [for (final u in ((_roles[r] as Map?)?['members'] as List? ?? const [])) '$u'];
              return Text(ms.isEmpty ? tr('Chưa có ai') : ms.map(_name).join(', '), style: TextStyle(color: ms.isEmpty ? kFlowOrange : pal.sub));
            }),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: _busy
                ? null
                : () async {
                    final cur = [for (final u in ((_roles[r] as Map?)?['members'] as List? ?? const [])) '$u'];
                    final v = await pickUsers(context, widget.app, selected: cur, title: _roleName(r));
                    if (v != null) {
                      await _mutate((_, roles) => roles[r] = {'name': (roles[r] as Map?)?['name'] ?? (r == 'flow_admin' ? tr('Quản trị quy trình') : roleLabel(r)), 'members': v});
                    }
                  },
          ),
        ),
    ]);
  }

  // ------------------------------------------------------------------ dựng trang

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (_err != null && !_loaded) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center)));
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final body = LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 820;
      if (!wide || !_canEdit) return _tree(pal, wide: false);
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: (c.maxWidth * 0.42).clamp(320, 520), child: _tree(pal, wide: true)),
        VerticalDivider(width: 1, color: pal.divider),
        Expanded(
          child: _sel == null
              ? Center(child: Text(tr('Chọn một phòng ban hoặc một người ở cột trái để xem và gán quyền.'), style: TextStyle(color: pal.sub)))
              : _PermPanel(
                  key: ValueKey(_sel),
                  api: _api,
                  sel: _sel!,
                  title: _selTitle(_sel!),
                  deptName: (id) => '${_depts[id]?['name'] ?? id}',
                  roleName: _roleName,
                ),
        ),
      ]);
    });
    final tabs = <(String, Widget)>[
      (_canEdit ? tr('Phòng ban & quyền') : tr('Phòng ban'), body),
      if (_canEdit) (tr('Vai trò'), _rolesTab(pal)),
      ...widget.extraTabs,
    ];
    if (tabs.length == 1) return body;
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        TabBar(tabs: [for (final t in tabs) Tab(text: t.$1)]),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------- quyền của một mục

/// Quyền của một phòng ban / một người: mỗi app một nhóm, mỗi quyền (dùng app, từng tool MCP, sự kiện…) một ô tick.
/// Tick = gán trực tiếp cho mục này. Quyền có sẵn nhờ phòng cha / phòng ban / vai trò hiện tick xám kèm nguồn.
class _PermPanel extends StatefulWidget {
  final _Api api;
  final _Sel sel;
  final String? title;
  final String Function(String) deptName;
  final String Function(String) roleName;
  const _PermPanel({super.key, required this.api, required this.sel, required this.title, required this.deptName, required this.roleName});
  @override
  State<_PermPanel> createState() => _PermPanelState();
}

class _PermPanelState extends State<_PermPanel> {
  List<Map<String, dynamic>>? _apps;
  /// space id -> {name, provider}: công ty Ký số / trình duyệt.
  Map<String, Map<String, dynamic>> _spaces = {};
  final _direct = <String, String>{}; // "app\nperm\nspace" -> grant id gán trực tiếp ('' = mọi space)
  final _via = <String, List<String>>{}; // "app\nperm\nspace" -> nguồn kế thừa
  String? _err;
  String _q = '';
  final _busy = <String>{};

  /// Nhóm app đang mở / thu gọn, giữ trong phiên chạy app (theo mục đang chọn + app). Chưa có thì: mở nếu nhóm có quyền.
  static final _expanded = <String, bool>{};

  /// Đang cấp / bỏ hàng loạt: (đã xong, tổng).
  (int, int)? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = widget.sel;
    try {
      final r = await Future.wait([
        widget.api.call('GET', '/v1/admin/catalog'),
        widget.api.call('GET', '/v1/admin/grants?subject_type=${s.type}&subject_id=${Uri.encodeQueryComponent(s.id)}'),
        widget.api.call('GET', '/v1/admin/subjects/${s.type}/${Uri.encodeComponent(s.id)}/perms'),
      ]);
      if (!mounted) return;
      final me = '${s.type}:${s.id}';
      setState(() {
        _apps = [for (final a in (r[0]['apps'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
        _spaces = {for (final e in ((r[0]['spaces'] as Map?) ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map)};
        _direct.clear();
        _via.clear();
        for (final g in (r[1]['grants'] as List? ?? const [])) {
          final m = g as Map;
          _direct['${m['app']}\n${m['perm']}\n${m['space'] ?? ''}'] = '${m['id']}';
        }
        for (final p in (r[2]['perms'] as List? ?? const [])) {
          final m = p as Map;
          if ('${m['via']}' == me) continue;
          (_via['${m['app']}\n${m['perm']}\n${m['space'] ?? ''}'] ??= []).add('${m['via']}');
        }
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  String _viaLabel(String via) {
    final i = via.indexOf(':');
    final t = via.substring(0, i), id = via.substring(i + 1);
    return switch (t) {
      'dept' => tr('phòng {0}', [widget.deptName(id)]),
      'role' => tr('vai trò {0}', [widget.roleName(id)]),
      'everyone' => tr('Mọi người'),
      _ => via,
    };
  }

  /// Các space (công ty / trình duyệt) mà quyền của app này gán theo được: Browser là mọi space; extension là space nó khai.
  List<String> _appSpaces(String app) => [
        for (final e in _spaces.entries)
          if (app == 'vn.flygo.browser' || e.value['provider'] == app) e.key,
      ]..sort((a, b) => '${_spaces[a]?['name']}'.compareTo('${_spaces[b]?['name']}'));

  Future<void> _toggle(String app, String perm, bool on, [String space = '']) async {
    final k = '$app\n$perm\n$space';
    setState(() => _busy.add(k));
    final m = ScaffoldMessenger.of(context);
    try {
      if (on) {
        final r = await widget.api.call('POST', '/v1/admin/grants',
            {'subject_type': widget.sel.type, 'subject_id': widget.sel.id, 'app': app, 'perm': perm, if (space.isNotEmpty) 'space': space});
        _direct[k] = '${(r['grant'] as Map)['id']}';
      } else if (_direct[k] != null) {
        await widget.api.call('DELETE', '/v1/admin/grants/${_direct[k]}');
        _direct.remove(k);
      }
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
    }
    if (mounted) setState(() => _busy.remove(k));
  }

  bool _isOn(String id) => _direct.containsKey(id) || (_via[id]?.isNotEmpty ?? false);

  /// Có sẵn nhờ phòng cấp trên / vai trò / "Mọi người" (không gán trực tiếp): cấp / bỏ hàng loạt không đụng tới.
  bool _isInherited(String id) => !_direct.containsKey(id) && (_via[id]?.isNotEmpty ?? false);

  String _expandKey(String app) => '${widget.sel.type}:${widget.sel.id}|$app';

  /// Cấp ([on]) hoặc bỏ các quyền [items] (app, quyền; mọi công ty), mỗi lúc 4 yêu cầu, có tiến độ. Đổi nhiều hơn 10 quyền
  /// thì hỏi lại. Quyền kế thừa bỏ qua; quyền đã đúng trạng thái bỏ qua.
  Future<void> _bulk(List<(String, String)> items, bool on) async {
    final todo = [
      for (final (app, perm) in items)
        if (on ? !_isOn('$app\n$perm\n') : _direct.containsKey('$app\n$perm\n')) (app, perm),
    ];
    if (todo.isEmpty || _progress != null) return;
    final who = widget.title ?? '';
    if (todo.length > 10) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(on ? tr('Cấp {0} quyền cho {1}?', [todo.length, who]) : tr('Bỏ {0} quyền của {1}?', [todo.length, who])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(on ? tr('Cấp quyền') : tr('Bỏ quyền'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final m = ScaffoldMessenger.of(context);
    setState(() => _progress = (0, todo.length));
    var next = 0, done = 0, failed = 0;
    Object? lastErr;
    Future<void> worker() async {
      while (next < todo.length) {
        final (app, perm) = todo[next++];
        final k = '$app\n$perm\n';
        try {
          if (on) {
            final r = await widget.api.call('POST', '/v1/admin/grants', {'subject_type': widget.sel.type, 'subject_id': widget.sel.id, 'app': app, 'perm': perm});
            _direct[k] = '${(r['grant'] as Map)['id']}';
          } else if (_direct[k] != null) {
            await widget.api.call('DELETE', '/v1/admin/grants/${_direct[k]}');
            _direct.remove(k);
          }
        } catch (e) {
          failed++;
          lastErr = e;
        }
        done++;
        if (mounted) setState(() => _progress = (done, todo.length));
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    if (!mounted) return;
    setState(() => _progress = null);
    if (failed > 0) m.showSnackBar(toast(Text(tr('{0} quyền chưa đổi được: {1}', [failed, '$lastErr']))));
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (_err != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center)));
    final apps = _apps;
    if (apps == null) return const Center(child: CircularProgressIndicator());
    String appName(Map a) => a['name'] is Map ? '${(a['name'] as Map)['vi'] ?? (a['name'] as Map).values.first}' : '${a['name']}';
    // Ưu tiên app có tool MCP lên đầu.
    final sorted = [...apps]..sort((a, b) {
        final ta = ((a['tools'] as Map?) ?? const {}).isNotEmpty ? 0 : 1, tb = ((b['tools'] as Map?) ?? const {}).isNotEmpty ? 0 : 1;
        return ta != tb ? ta.compareTo(tb) : appName(a).compareTo(appName(b));
      });
    final q = _q.toLowerCase();
    // Các quyền của app hiện theo ô tìm, theo thứ tự: quản trị, dùng app, tool, quyền khác, sự kiện.
    List<String> keysOf(Map a) {
      final perms = Map<String, dynamic>.from((a['perms'] as Map?) ?? const {});
      return perms.keys.where((k) => q.isEmpty || appName(a).toLowerCase().contains(q) || '$k ${(perms[k] as Map)['name']}'.toLowerCase().contains(q)).toList()
        ..sort((x, y) {
          int rank(String k) => k == 'admin' ? -1 : k == 'use' ? 0 : (k.startsWith('tool:') ? 1 : (k.startsWith('webhook:') ? 3 : 2));
          final r = rank(x).compareTo(rank(y));
          return r != 0 ? r : x.compareTo(y);
        });
    }

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      if (widget.title != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Icon(switch (widget.sel.type) { 'dept' => Icons.folder_rounded, 'everyone' => Icons.groups_rounded, _ => Icons.person_outline }, color: pal.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text))),
          ]),
        ),
      Text(
        switch (widget.sel.type) {
          'dept' => tr('Tick để cho phép cả phòng (và các phòng con) dùng. Ô xám là quyền có sẵn nhờ phòng cấp trên hoặc nhờ "Mọi người".'),
          'everyone' => tr('Tick để cho phép mọi nhân viên dùng. Bot và agent không nhận quyền này (agent luôn được gán riêng).'),
          _ => tr('Tick để cho phép riêng người này. Ô xám là quyền có sẵn nhờ phòng ban, vai trò hoặc "Mọi người".'),
        },
        style: TextStyle(color: pal.sub, fontSize: 12.5),
      ),
      const SizedBox(height: 10),
      TextField(
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm app hoặc tool'), isDense: true, border: const OutlineInputBorder()),
        onChanged: (v) => setState(() => _q = v),
      ),
      const SizedBox(height: 8),
      // Chọn tất cả / Bỏ tất cả: mọi quyền đang hiện (theo ô tìm), không đụng quyền kế thừa.
      Row(children: [
        TextButton.icon(
          key: const ValueKey('perm-all-on'),
          onPressed: _progress != null ? null : () => _bulk([for (final a in sorted) for (final k in keysOf(a)) ('${a['id']}', k)], true),
          icon: const Icon(Icons.done_all_rounded, size: 18),
          label: Text(tr('Chọn tất cả')),
        ),
        TextButton.icon(
          key: const ValueKey('perm-all-off'),
          onPressed: _progress != null ? null : () => _bulk([for (final a in sorted) for (final k in keysOf(a)) ('${a['id']}', k)], false),
          icon: const Icon(Icons.remove_done_rounded, size: 18),
          label: Text(tr('Bỏ tất cả')),
        ),
        const Spacer(),
        if (_progress != null)
          Text(tr('Đang cập nhật {0}/{1}', [_progress!.$1, _progress!.$2]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
      ]),
      if (_progress != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LinearProgressIndicator(value: _progress!.$2 == 0 ? null : _progress!.$1 / _progress!.$2),
        ),
      const SizedBox(height: 4),
      for (final a in sorted)
        Builder(builder: (_) {
          final perms = Map<String, dynamic>.from((a['perms'] as Map?) ?? const {});
          final keys = keysOf(a);
          if (keys.isEmpty) return const SizedBox.shrink();
          final ids = [for (final k in keys) '${a['id']}\n$k\n'];
          final granted = ids.where(_isOn).length;
          final groupValue = granted == 0 ? false : (granted == ids.length ? true : null);
          final changeable = ids.any((id) => !_isInherited(id));
          final ek = _expandKey('${a['id']}');
          final open = q.isNotEmpty || (_expanded[ek] ?? granted > 0);
          return Card(
            elevation: 0,
            color: pal.surface,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: pal.divider)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Đầu nhóm: mũi tên thu / mở, tên app, "đã cấp/tổng", ô chọn cả nhóm (tất cả / một phần / không).
                InkWell(
                  key: ValueKey('perm-group-${a['id']}'),
                  onTap: () => setState(() => _expanded[ek] = !open),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 6, 2),
                    child: Row(children: [
                      Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, color: pal.sub),
                      const SizedBox(width: 4),
                      Expanded(child: Text(appName(a), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
                      Text('$granted/${ids.length}', key: ValueKey('perm-count-${a['id']}'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
                      Checkbox(
                        key: ValueKey('perm-group-check-${a['id']}'),
                        tristate: true,
                        value: groupValue,
                        onChanged: _progress != null || !changeable ? null : (_) => _bulk([for (final k in keys) ('${a['id']}', k)], groupValue != true),
                      ),
                    ]),
                  ),
                ),
                if (open)
                for (final k in keys)
                  Builder(builder: (_) {
                    final p = Map<String, dynamic>.from(perms[k] as Map);
                    final id = '${a['id']}\n$k\n';
                    final direct = _direct.containsKey(id);
                    final via = _via[id] ?? const [];
                    final spaces = (p['per_space'] == true || k == 'use') ? _appSpaces('${a['id']}') : const <String>[];
                    final tool = k.startsWith('tool:');
                    final write = tool && '${((a['tools'] as Map?)?[k.substring(5)] as Map?)?['kind']}' == 'write';
                    final sub = [
                      if (k == 'admin') tr('Trang quản trị của app') else if (k == 'use') tr('Dùng app') else if (tool) tr('Tool MCP') else if (k.startsWith('webhook:')) tr('Sự kiện cho quy trình') else tr('Quyền của app'),
                      if (write) tr('ghi dữ liệu'),
                      if (spaces.isNotEmpty || p['per_space'] == true) tr('mọi công ty / trình duyệt'),
                      if (via.isNotEmpty) tr('có sẵn nhờ {0}', [via.map(_viaLabel).join(', ')]),
                    ].join(' · ');
                    final all = CheckboxListTile(
                      dense: true,
                      value: direct || via.isNotEmpty,
                      tristate: false,
                      onChanged: _busy.contains(id) || (!direct && via.isNotEmpty) ? null : (v) => _toggle('${a['id']}', k, v == true),
                      title: Row(children: [
                        if (k == 'admin') ...[Icon(Icons.admin_panel_settings_outlined, size: 18, color: pal.accent), const SizedBox(width: 6)],
                        Flexible(
                          child: Text(
                            k == 'use' ? tr('Dùng {0}', [appName(a)]) : (k == 'admin' ? tr('Quản trị {0}', [appName(a)]) : '${p['name']}'),
                            overflow: TextOverflow.ellipsis,
                            style: k == 'admin' ? const TextStyle(fontWeight: FontWeight.w600) : null,
                          ),
                        ),
                        if (write) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.edit_note_rounded, size: 16, color: kFlowOrange),
                        ],
                      ]),
                      subtitle: Text(sub, style: TextStyle(fontSize: 11.5, color: via.isNotEmpty && !direct ? pal.sub : null)),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                    if (spaces.isEmpty) return all;
                    // Từng công ty / trình duyệt: tick riêng (đã có "mọi" thì các ô con hiện tick xám).
                    final allOn = direct || via.isNotEmpty;
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      all,
                      for (final sp in spaces)
                        Builder(builder: (_) {
                          final sid = '${a['id']}\n$k\n$sp';
                          final d = _direct.containsKey(sid);
                          final v = _via[sid] ?? const [];
                          return Padding(
                            padding: const EdgeInsets.only(left: 36),
                            child: CheckboxListTile(
                              dense: true,
                              value: allOn || d || v.isNotEmpty,
                              onChanged: _busy.contains(sid) || allOn || (!d && v.isNotEmpty) ? null : (on) => _toggle('${a['id']}', k, on == true, sp),
                              title: Text('${_spaces[sp]?['name'] ?? sp}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                              subtitle: v.isNotEmpty && !d ? Text(tr('có sẵn nhờ {0}', [v.map(_viaLabel).join(', ')]), style: TextStyle(fontSize: 11, color: pal.sub)) : null,
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          );
                        }),
                    ]);
                  }),
              ]),
            ),
          );
        }),
    ]);
  }
}
