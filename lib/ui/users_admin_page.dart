// Người dùng (mục Quản trị, chỉ quản trị viên Flygo ID): tài khoản của máy chủ chat quản lý bằng tên đăng nhập + mật khẩu
// (Sếp). Danh sách, tạo tài khoản, đặt lại mật khẩu, khoá / mở khoá (cho nghỉ việc), quyền quản trị, xem phòng ban,
// quyền (kèm nguồn), thiết bị và nhật ký. API: Flygo ID /v1/admin/users (docs/users-admin.md).
import '../update/build_label.dart';
import 'package:flutter/material.dart';

import '../browser/flygo_id.dart';
import '../config.dart';
import '../i18n/i18n.dart';
import 'app_route.dart';
import 'common.dart';
import 'devices_page.dart' show confirmCountdown;
import 'theme.dart';

class UsersAdminPage extends StatefulWidget {
  final FlygoId id;
  const UsersAdminPage({super.key, required this.id});

  /// Người đang dùng có quyền quản trị người dùng không (gọi thử danh sách 1 người).
  static Future<bool> allowed(FlygoId id) async {
    try {
      await id.request('GET', '/v1/admin/users?per_page=1');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  State<UsersAdminPage> createState() => _UsersAdminPageState();
}

class _UsersAdminPageState extends State<UsersAdminPage> {
  final _q = TextEditingController();
  String _status = 'active';
  List<Map<String, dynamic>> _users = const [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  /// Máy tính (đủ rộng): người đang xem chi tiết ở cột phải.
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => (_loading = true, _error = null));
    try {
      final q = Uri.encodeQueryComponent(_q.text.trim());
      final j = await widget.id.request('GET', '/v1/admin/users?q=$q&status=$_status&per_page=200');
      if (!mounted) return;
      setState(() {
        _users = [for (final u in (j['users'] as List? ?? const [])) if (u is Map) Map<String, dynamic>.from(u)];
        _total = (j['total'] as num?)?.toInt() ?? _users.length;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _loading = false));
    }
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(context: context, builder: (_) => _CreateUserDialog(id: widget.id));
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // Máy tính, cửa sổ rộng: danh sách (rộng tối đa 480) bên trái, chi tiết ở cột phải. Hẹp: mở trang chi tiết.
        if (!isDesktop || box.maxWidth < 900) return _list(context, wide: false);
        final pal = Pal.of(context);
        return Row(children: [
          SizedBox(width: 480, child: _list(context, wide: true)),
          VerticalDivider(width: 1, color: pal.divider),
          Expanded(
            child: _selected == null
                ? Center(child: Text(tr('Chọn một người để xem chi tiết'), style: TextStyle(color: pal.sub)))
                : UserDetailPage(key: ValueKey(_selected), id: widget.id, userId: _selected!, embedded: true, onChanged: _load),
          ),
        ]);
      });

  Widget _list(BuildContext context, {required bool wide}) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: Text(tr('Người dùng'))),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _create, icon: const Icon(Icons.person_add_alt_1_rounded), label: Text(tr('Thêm người dùng'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _q,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: tr('Tìm theo tên, tên đăng nhập, email'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onSubmitted: (_) => _load(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final (v, l) in [('active', tr('Đang hoạt động')), ('inactive', tr('Đã khoá')), ('all', tr('Tất cả'))])
              ChoiceChip(
                label: Text(l),
                selected: _status == v,
                onSelected: (_) {
                  setState(() => _status = v);
                  _load();
                },
              ),
            Text(tr('{0} người', ['$_total']), style: TextStyle(color: pal.sub, fontSize: 13)),
          ]),
        ),
        Expanded(
          child: _loading && _users.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: pal.sub)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: _users.length,
                        itemBuilder: (_, i) => _UserTile(
                          u: _users[i],
                          selected: wide && _selected == '${_users[i]['id']}',
                          onTap: () async {
                            if (wide) return setState(() => _selected = '${_users[i]['id']}');
                            await Navigator.of(context).push(AppPageRoute(
                                builder: (_) => UserDetailPage(id: widget.id, userId: '${_users[i]['id']}')));
                            _load();
                          },
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> u;
  final VoidCallback onTap;
  final bool selected;
  const _UserTile({required this.u, required this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final inactive = u['status'] == 'inactive';
    final depts = [for (final d in (u['depts'] as List? ?? const [])) if (d is Map) '${d['name']}${d['head'] == true ? ' (${tr('trưởng phòng')})' : ''}'];
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: pal.accent.withValues(alpha: .10),
      leading: Opacity(opacity: inactive ? .4 : 1, child: Avatar(userId: '${u['id']}', name: '${u['name'] ?? u['username']}', size: 42)),
      title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${(u['name'] ?? '').toString().isEmpty ? u['username'] : u['name']}',
            style: TextStyle(fontWeight: FontWeight.w600, color: inactive ? pal.sub : pal.text)),
        if (u['system_admin'] == true) _Chip(tr('Quản trị'), const Color(0xFF7C3AED)),
        if (u['is_bot'] == true) _Chip('Bot', pal.sub),
        if (inactive) _Chip(tr('Đã khoá'), Colors.redAccent),
      ]),
      subtitle: Text(
          ['@${u['username']}', if (depts.isNotEmpty) depts.join(', '), if ((u['devices'] ?? 0) != 0) tr('{0} thiết bị', ['${u['devices']}'])]
              .join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

class _CreateUserDialog extends StatefulWidget {
  final FlygoId id;
  const _CreateUserDialog({required this.id});
  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _user = TextEditingController(), _pass = TextEditingController(), _name = TextEditingController(), _pos = TextEditingController();
  String? _error;
  bool _busy = false, _show = false;

  Future<void> _save() async {
    setState(() => (_busy = true, _error = null));
    try {
      await widget.id.request('POST', '/v1/admin/users', {
        'username': _user.text.trim().toLowerCase(),
        'password': _pass.text,
        if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
        if (_pos.text.trim().isNotEmpty) 'position': _pos.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _busy = false));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Thêm người dùng')),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _name, decoration: InputDecoration(labelText: tr('Họ tên'))),
            TextField(controller: _user, decoration: InputDecoration(labelText: tr('Tên đăng nhập'), helperText: tr('Chữ thường, số, . _ -; bắt đầu bằng chữ'))),
            TextField(
              controller: _pass,
              obscureText: !_show,
              decoration: InputDecoration(
                labelText: tr('Mật khẩu'),
                suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _show = !_show)),
              ),
            ),
            TextField(controller: _pos, decoration: InputDecoration(labelText: tr('Chức vụ (không bắt buộc)'))),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Tạo tài khoản'))),
        ],
      );
}

class UserDetailPage extends StatefulWidget {
  final FlygoId id;
  final String userId;
  /// Cột phải của tab Người dùng (máy tính): không có nút quay lại.
  final bool embedded;
  /// Có thay đổi (khoá, đổi tên…): danh sách tải lại.
  final VoidCallback? onChanged;
  const UserDetailPage({super.key, required this.id, required this.userId, this.embedded = false, this.onChanged});
  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.id.request('GET', '/v1/admin/users/${widget.userId}');
      if (mounted) setState(() => (_d = j, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Map<String, dynamic> get _u => Map<String, dynamic>.from(_d?['user'] as Map? ?? const {});

  Future<void> _do(String method, String path, Map<String, dynamic>? body, String done) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await widget.id.request(method, path, body);
      m.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _edit() async {
    final name = TextEditingController(text: '${_u['name'] ?? ''}'), pos = TextEditingController(text: '${_u['position'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sửa thông tin')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Họ tên'))),
          TextField(controller: pos, decoration: InputDecoration(labelText: tr('Chức vụ'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok == true) await _do('PATCH', '/v1/admin/users/${widget.userId}', {'name': name.text.trim(), 'position': pos.text.trim()}, tr('Đã lưu'));
  }

  Future<void> _password() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đặt lại mật khẩu')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: ctl, decoration: InputDecoration(labelText: tr('Mật khẩu mới'))),
          const SizedBox(height: 8),
          Text(tr('Người này sẽ bị đăng xuất khỏi mọi máy và đăng nhập lại bằng mật khẩu mới.'), style: const TextStyle(fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đặt mật khẩu'))),
        ],
      ),
    );
    if (ok == true && ctl.text.isNotEmpty) {
      await _do('POST', '/v1/admin/users/${widget.userId}/password', {'password': ctl.text}, tr('Đã đặt mật khẩu mới'));
    }
  }

  Future<void> _deactivate() async {
    var offboard = false;
    final ok = await confirmCountdown(context,
        title: tr('Khoá tài khoản {0}?', ['${_u['name'] ?? _u['username']}']),
        body: tr('Tài khoản bị khoá, mọi thiết bị bị thu hồi. Có thể mở khoá lại sau.'),
        action: tr('Khoá'));
    if (!ok || !mounted) return;
    offboard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Cho nghỉ việc?')),
            content: Text(tr('Gỡ luôn mọi quyền cấp riêng, rời mọi phòng ban và bỏ quyền quản trị?')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Chỉ khoá'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Cho nghỉ việc'))),
            ],
          ),
        ) ??
        false;
    await _do('POST', '/v1/admin/users/${widget.userId}/deactivate', {'offboard': offboard}, tr('Đã khoá tài khoản'));
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final u = _u;
    final inactive = u['status'] == 'inactive';
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
        );
    final perms = [for (final p in (_d?['perms'] as List? ?? const [])) if (p is Map) p];
    final devices = [for (final d in (_d?['devices'] as List? ?? const [])) if (d is Map) d];
    final audit = [for (final a in (_d?['audit'] as List? ?? const [])) if (a is Map) a];
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: Text('${u['name'] ?? u['username'] ?? ''}'), automaticallyImplyLeading: !widget.embedded),
      body: _d == null
          ? Center(child: _error != null ? Text(_error!, style: TextStyle(color: pal.sub)) : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              ListTile(
                leading: Avatar(userId: widget.userId, name: '${u['name'] ?? u['username']}', size: 52),
                title: Text('${u['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                subtitle: Text(['@${u['username']}', '${u['email'] ?? ''}', '${u['position'] ?? ''}'].where((x) => x.trim().isNotEmpty && x != '@').join('\n')),
                trailing: IconButton(icon: const Icon(Icons.edit_rounded), tooltip: tr('Sửa thông tin'), onPressed: _edit),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: _password, icon: const Icon(Icons.password_rounded), label: Text(tr('Đặt lại mật khẩu'))),
                  inactive
                      ? FilledButton.icon(
                          onPressed: () => _do('POST', '/v1/admin/users/${widget.userId}/activate', null, tr('Đã mở khoá tài khoản')),
                          icon: const Icon(Icons.lock_open_rounded),
                          label: Text(tr('Mở khoá')))
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                          onPressed: _deactivate,
                          icon: const Icon(Icons.lock_rounded),
                          label: Text(tr('Khoá tài khoản'))),
                ]),
              ),
              SwitchListTile(
                title: Text(tr('Quản trị viên máy chủ')),
                value: u['system_admin'] == true,
                onChanged: (v) => _do('PATCH', '/v1/admin/users/${widget.userId}', {'system_admin': v}, v ? tr('Đã cấp quyền quản trị') : tr('Đã bỏ quyền quản trị')),
              ),
              // Đăng nhập bằng mật khẩu theo từng người (vn.flygo.sso 0.4): chỉ với tài khoản có nối Google, mặc định tắt.
              if (_d?['password_login'] is Map && (_d!['password_login'] as Map)['google_linked'] == true)
                SwitchListTile(
                  title: Text(tr('Cho đăng nhập bằng mật khẩu')),
                  subtitle: Text((_d!['password_login'] as Map)['has_password'] == true
                      ? tr('Tắt: chỉ đăng nhập bằng Google. Bật: dùng được cả mật khẩu đã đặt.')
                      : tr('Người này chưa đặt mật khẩu. Bật sẵn thì đặt xong là đăng nhập được ngay.')),
                  value: (_d!['password_login'] as Map)['enabled'] == true,
                  onChanged: (v) => _do('PATCH', '/v1/admin/users/${widget.userId}', {'password_login': v},
                      v ? tr('Đã bật đăng nhập bằng mật khẩu') : tr('Đã tắt đăng nhập bằng mật khẩu')),
                ),
              // Tài khoản chỉ có mật khẩu: cho đăng nhập bằng Google (email Google trùng email tài khoản), mật khẩu vẫn giữ.
              if (_d?['password_login'] is Map && (_d!['password_login'] as Map)['google_linked'] == false)
                SwitchListTile(
                  title: Text(tr('Cho đăng nhập bằng Google')),
                  subtitle: Text(tr('Đăng nhập Google bằng đúng email của tài khoản; mật khẩu hiện có vẫn dùng được.')),
                  value: (_d!['password_login'] as Map)['google_enabled'] == true,
                  onChanged: (v) => _do('PATCH', '/v1/admin/users/${widget.userId}', {'google_login': v},
                      v ? tr('Đã bật đăng nhập bằng Google') : tr('Đã tắt đăng nhập bằng Google')),
                ),
              section(tr('Phòng ban')),
              for (final d in (u['depts'] as List? ?? const []))
                if (d is Map)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.account_tree_rounded),
                    title: Text('${d['name']}'),
                    subtitle: Text([if (d['primary'] == true) tr('Phòng chính'), if (d['head'] == true) tr('Trưởng phòng'), if (d['deputy'] == true) tr('Phó phòng')].join(' · ')),
                  ),
              if ((u['depts'] as List? ?? const []).isEmpty) ListTile(dense: true, title: Text(tr('Chưa thuộc phòng ban nào (sửa ở Tổ chức)'))),
              section(tr('Quyền')),
              for (final p in perms)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.key_rounded),
                  title: Text('${p['app']} · ${p['perm']}${p['space'] != null ? ' · ${p['space']}' : ''}'),
                  subtitle: Text(switch ('${p['via']}') {
                    'user' => tr('Cấp riêng'),
                    'everyone' => tr('Mọi người'),
                    final v when v.startsWith('dept:') => tr('Từ phòng ban {0}', [v.substring(5)]),
                    final v => v,
                  }),
                ),
              if (perms.isEmpty) ListTile(dense: true, title: Text(tr('Chưa có quyền nào'))),
              section(tr('Thiết bị')),
              for (final d in devices)
                ListTile(
                  dense: true,
                  leading: Icon((d['key'] as Map?)?['biometric_bound'] == true ? Icons.verified_user_rounded : Icons.devices_rounded),
                  title: Text('${d['name'] ?? d['device_id']}'),
                  subtitle: Text('${d['platform'] ?? ''} · ${buildLabel('${d['app_version'] ?? ''}')}'),
                  trailing: d['revoked_at'] != null
                      ? Text(tr('Đã thu hồi'))
                      : TextButton(
                          onPressed: () async {
                            final ok = await confirmCountdown(context,
                                title: tr('Thu hồi "{0}"?', ['${d['name'] ?? ''}']), body: tr('Máy đó sẽ bị đăng xuất và mất khoá bảo mật.'), action: tr('Thu hồi'));
                            if (ok) await _do('POST', '/v1/admin/users/${widget.userId}/devices/${d['device_id']}/revoke', null, tr('Đã thu hồi thiết bị'));
                          },
                          child: Text(tr('Thu hồi'))),
                ),
              if (devices.isEmpty) ListTile(dense: true, title: Text(tr('Chưa có thiết bị nào ghi nhận'))),
              section(tr('Nhật ký')),
              for (final a in audit.take(30))
                ListTile(
                  dense: true,
                  title: Text('${a['action']}'),
                  subtitle: Text('${DateTime.fromMillisecondsSinceEpoch((a['at'] as num?)?.toInt() ?? 0)} · ${a['actor'] ?? ''}'),
                ),
              if (audit.isEmpty) ListTile(dense: true, title: Text(tr('Chưa có'))),
            ]),
    );
  }
}
