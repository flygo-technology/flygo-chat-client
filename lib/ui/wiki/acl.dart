// Wiki: phân quyền một thư mục. Bật / tắt kế thừa từ thư mục cha, danh sách quyền riêng (người, phòng ban, vai trò,
// mọi người) với mức Xem / Sửa / Quản lý, thêm đối tượng bằng ô tìm. Máy tính: hộp thoại; điện thoại: bảng trượt từ dưới.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'model.dart';
import 'store.dart';

Future<void> showFolderAcl(BuildContext context, WikiStore store, String folder, {required bool wide}) {
  final body = AclEditor(store: store, folder: folder, wide: wide);
  if (wide) {
    return showDialog(
      context: context,
      builder: (d) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760), child: body),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: body),
  );
}

class AclEditor extends StatefulWidget {
  const AclEditor({super.key, required this.store, required this.folder, required this.wide});
  final WikiStore store;
  final String folder;
  final bool wide;
  @override
  State<AclEditor> createState() => _AclEditorState();
}

class _AclEditorState extends State<AclEditor> {
  Map<String, dynamic>? _acl;
  List<Map<String, dynamic>> _entries = [];
  bool _inherit = true, _saving = false;
  String? _error;
  final _q = TextEditingController();
  List<Map<String, dynamic>> _found = [];
  String _newRole = 'view';
  Timer? _debounce;

  WikiStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await store.acl(widget.folder);
      if (!mounted) return;
      setState(() {
        _acl = a;
        _inherit = a['inherit'] == true;
        _entries = [for (final e in a['entries'] as List) Map<String, dynamic>.from(e as Map)];
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (q.trim().isEmpty) {
        if (mounted) setState(() => _found = []);
        return;
      }
      try {
        final r = await store.subjects(q.trim());
        if (mounted && _q.text == q) setState(() => _found = r.where((s) => !_entries.any((e) => e['stype'] == s['stype'] && e['sid'] == s['sid'])).take(8).toList());
      } catch (_) {}
    });
  }

  void _add(Map<String, dynamic> s) => setState(() {
        _entries.add({...s, 'role': _newRole});
        _found = [];
        _q.clear();
      });

  Future<void> _save() async {
    final nav = Navigator.of(context), messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await store.setAcl(widget.folder, _inherit, [for (final e in _entries) {'stype': e['stype'], 'sid': e['sid'], 'role': e['role']}]);
      nav.pop();
      messenger.showSnackBar(toast(Text(tr('Đã lưu quyền'))));
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(toast(Text(tr('Không lưu được quyền: {0}', ['$e']))));
    }
  }

  IconData _icon(String stype) => switch (stype) { 'dept' => Icons.apartment_rounded, 'role' => Icons.badge_outlined, 'everyone' => Icons.groups_outlined, _ => Icons.person_outline_rounded };

  String _detail(Map<String, dynamic> e) => switch ('${e['stype']}') {
        'dept' => tr('Phòng ban · {0} người, gồm cả phòng con', ['${e['members'] ?? 0}']),
        'role' => tr('Vai trò · {0} người', ['${e['members'] ?? 0}']),
        'everyone' => tr('Mọi người trên máy chủ chat'),
        _ => '${e['detail'] ?? tr('Người dùng')}',
      };

  Widget _roleMenu(Pal pal, String role, ValueChanged<String> onPick, {Key? key}) => PopupMenuButton<String>(
        key: key,
        tooltip: tr('Đổi quyền'),
        initialValue: role,
        onSelected: onPick,
        itemBuilder: (_) => [
          for (final r in const ['view', 'edit', 'manage']) PopupMenuItem(value: r, child: Text(roleLabel(r))),
        ],
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(border: Border.all(color: pal.divider), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(roleLabel(role), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: pal.text)),
            Icon(Icons.expand_more_rounded, size: 18, color: pal.sub),
          ]),
        ),
      );

  Widget _row(Pal pal, Map<String, dynamic> e, {bool inherited = false}) {
    final stype = '${e['stype']}';
    final lead = stype == 'user'
        ? CircleAvatar(radius: 18, backgroundColor: pal.avatarBg, child: Text(_initial('${e['name']}'), style: TextStyle(color: pal.avatarFg, fontWeight: FontWeight.w700)))
        : Container(width: 36, height: 36, decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10)), child: Icon(_icon(stype), color: pal.sub, size: 20));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(children: [
        lead,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: pal.text)),
            Text(inherited ? tr('Kế thừa từ “{0}”', ['${e['from_name']}']) : _detail(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub)),
          ]),
        ),
        if (inherited)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: pal.divider), borderRadius: BorderRadius.circular(8)),
            child: Text(roleLabel('${e['role']}'), style: TextStyle(fontSize: 13.5, color: pal.sub)),
          )
        else if (_canManage) ...[
          _roleMenu(pal, '${e['role']}', (r) => setState(() => e['role'] = r)),
          IconButton(tooltip: tr('Bỏ'), icon: const Icon(Icons.close_rounded, size: 20), onPressed: () => setState(() => _entries.remove(e))),
        ] else
          Text(roleLabel('${e['role']}'), style: TextStyle(fontSize: 13.5, color: pal.sub)),
      ]),
    );
  }

  static String _initial(String n) {
    final w = n.trim().split(RegExp(r'\s+'));
    return w.isEmpty || w.last.isEmpty ? '?' : w.last.characters.first.toUpperCase();
  }

  bool get _canManage => _acl?['can_manage'] == true;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final a = _acl;
    if (a == null) {
      return SizedBox(
        height: 240,
        child: Center(child: _error != null ? Padding(padding: const EdgeInsets.all(20), child: Text(_error!)) : const CircularProgressIndicator()),
      );
    }
    final root = a['kind'] == 'root';
    final inherited = [for (final e in a['inherited'] as List) Map<String, dynamic>.from(e as Map)];
    final title = Padding(
      padding: EdgeInsets.fromLTRB(20, widget.wide ? 18 : 0, 8, 4),
      child: Row(children: [
        Icon(Icons.folder_rounded, color: const Color(0xFFE8A100), size: widget.wide ? 26 : 22),
        const SizedBox(width: 10),
        Expanded(child: Text(tr('Quyền của thư mục “{0}”', ['${a['name']}']), style: TextStyle(fontSize: widget.wide ? 18 : 17, fontWeight: FontWeight.w700, color: pal.text))),
        if (widget.wide) IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
      ]),
    );
    final list = ListView(shrinkWrap: true, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
        child: Text(tr('Quyền áp dụng cho mọi trang và thư mục con bên trong, trừ khi thư mục con tự đặt riêng.'), style: TextStyle(color: pal.sub, fontSize: 13.5)),
      ),
      if (!root)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.account_tree_outlined, color: pal.sub),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Kế thừa từ “{0}”', ['${a['parent_name'] ?? ''}']), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                Text(tr('Tắt để chỉ dùng danh sách bên dưới (thư mục kín)'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
            ),
            Switch(
              key: const ValueKey('wiki-acl-inherit'),
              value: _inherit,
              onChanged: !_canManage
                  ? null
                  : (v) => setState(() {
                        _inherit = v;
                        // Tắt kế thừa: giữ cho mình quyền Quản lý để không tự khoá mình (máy chủ cũng chặn).
                        if (!v && !store.admin) {
                          final me = (a['inherited'] as List).cast<Map>().where((e) => e['stype'] == 'user' && e['sid'] == store.meId && e['role'] == 'manage').toList();
                          for (final m in me) {
                            if (!_entries.any((e) => e['stype'] == 'user' && e['sid'] == m['sid'])) _entries.add({...Map<String, dynamic>.from(m), 'from_name': null});
                          }
                        }
                      }),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Text(tr('AI CÓ QUYỀN'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: pal.sub)),
      ),
      for (final e in _entries) _row(pal, e),
      if (_inherit && !root)
        for (final e in inherited.where((i) => !_entries.any((x) => x['stype'] == i['stype'] && x['sid'] == i['sid']))) _row(pal, e, inherited: true),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.shield_outlined, color: pal.sub, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Quản trị wiki'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: pal.text)),
              Text(tr('Luôn có toàn quyền ở mọi thư mục'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ]),
          ),
          Text(roleLabel('manage'), style: TextStyle(fontSize: 13.5, color: pal.sub)),
          const SizedBox(width: 12),
        ]),
      ),
      if (_canManage) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('wiki-acl-add'),
                controller: _q,
                onChanged: _search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.person_add_alt_rounded),
                  hintText: widget.wide ? tr('Thêm người, phòng ban, vai trò hoặc “Mọi người”…') : tr('Thêm người / phòng ban'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _roleMenu(pal, _newRole, (r) => setState(() => _newRole = r)),
          ]),
        ),
        for (final s in _found)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 28),
            leading: Icon(_icon('${s['stype']}'), color: pal.sub),
            title: Text('${s['name']}'),
            subtitle: Text('${s['detail'] ?? ''}'),
            onTap: () => _add(s),
          ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
        child: Text(
          tr('Xem: đọc trang, tải tệp. Sửa: thêm tạo, sửa, chuyển, xoá trang. Quản lý: thêm tạo / đổi tên / chuyển / xoá thư mục con và đặt quyền.'),
          style: TextStyle(fontSize: 12.5, color: pal.sub, height: 1.5),
        ),
      ),
    ]);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title,
      Flexible(child: list),
      Divider(height: 1, color: pal.divider),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
        child: widget.wide
            ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'))),
                const SizedBox(width: 8),
                if (_canManage) FilledButton(key: const ValueKey('wiki-acl-save'), onPressed: _saving ? null : _save, child: Text(tr('Lưu quyền'))),
              ])
            : _canManage
                ? FilledButton(key: const ValueKey('wiki-acl-save'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)), onPressed: _saving ? null : _save, child: Text(tr('Lưu quyền')))
                : OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng'))),
      ),
    ]);
  }
}
