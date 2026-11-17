// Người dùng (mục Quản trị, chỉ quản trị viên Flygo ID): tài khoản của máy chủ chat quản lý bằng tên đăng nhập + mật khẩu
// (Sếp). Danh sách, tạo tài khoản, đặt lại mật khẩu, khoá / mở khoá (cho nghỉ việc), quyền quản trị, cách đăng nhập
// (Google / mật khẩu), phòng ban, quyền gộp theo app (kèm nguồn), thiết bị và nhật ký. API: Flygo ID /v1/admin/users
// (docs/users-admin.md).
//
// Chặn đăng nhập toàn bộ + passkey bắt buộc (bản xem trước, chờ Sếp duyệt): trang chỉ hiện các phần này khi máy chủ trả
// dữ liệu tương ứng (GET /v1/admin/login-guard, user.login, device.passkey); máy chủ hiện tại chưa có nên không hiện gì.
import '../update/build_label.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../browser/flygo_id.dart';
import '../config.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'app_route.dart';
import 'common.dart';
import 'devices_page.dart' show confirmCountdown;
import 'password_page.dart' show PasswordPolicy;
import 'theme.dart';

/// Chính sách mật khẩu của máy chủ chat đang dùng (null = không đọc được, dùng mặc định).
typedef PolicyLoader = Future<PasswordPolicy?> Function();

PolicyLoader _defaultPolicy(BuildContext context) {
  AppState? app;
  try {
    app = context.read<AppState>();
  } catch (_) {}
  return () async => app?.passwordPolicy();
}

const _red = Color(0xFFFF6B6B), _amber = Color(0xFFF5B544), _green = Color(0xFF3DD68C), _violet = Color(0xFF8B5CF6);

class UsersAdminPage extends StatefulWidget {
  final FlygoId id;

  /// Thử nghiệm / ảnh xem trước: thay cách đọc chính sách mật khẩu.
  final PolicyLoader? policy;
  const UsersAdminPage({super.key, required this.id, this.policy});

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

  /// Chặn đăng nhập toàn bộ (null = máy chủ chưa có tính năng này).
  Map<String, dynamic>? _guard;

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
      final r = await Future.wait([
        widget.id.request('GET', '/v1/admin/users?q=$q&status=$_status&per_page=200'),
        widget.id.request('GET', '/v1/admin/login-guard').then<Map<String, dynamic>?>((j) => j, onError: (_) => null),
      ]);
      final j = r[0]!;
      if (!mounted) return;
      setState(() {
        _users = [
          for (final u in (j['users'] as List? ?? const []))
            if (u is Map) Map<String, dynamic>.from(u),
        ];
        _total = (j['total'] as num?)?.toInt() ?? _users.length;
        _guard = r[1] != null && r[1]!['enabled'] is bool ? r[1] : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _loading = false));
    }
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateUserDialog(id: widget.id, policy: widget.policy ?? _defaultPolicy(context)),
    );
    if (created == true) _load();
  }

  Future<void> _setGuard(Map<String, dynamic> patch, String done) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await widget.id.request('PATCH', '/v1/admin/login-guard', patch);
      m.showSnackBar(toast(Text(done)));
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Máy tính, cửa sổ rộng: danh sách (rộng tối đa 480) bên trái, chi tiết ở cột phải. Hẹp: mở trang chi tiết.
      if (!isDesktop || box.maxWidth < 900) return _list(context, wide: false);
      final pal = Pal.of(context);
      return Row(
        children: [
          SizedBox(width: 480, child: _list(context, wide: true)),
          VerticalDivider(width: 1, color: pal.divider),
          Expanded(
            child: _selected == null
                ? Center(
                    child: Text(tr('Chọn một người để xem chi tiết'), style: TextStyle(color: pal.sub)),
                  )
                : UserDetailPage(key: ValueKey(_selected), id: widget.id, userId: _selected!, embedded: true, onChanged: _load, policy: widget.policy),
          ),
        ],
      );
    },
  );

  Widget _list(BuildContext context, {required bool wide}) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bg, title: Text(tr('Người dùng'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(tr('Thêm người dùng')),
      ),
      body: _loading && _users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: TextStyle(color: pal.sub)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: _users.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) return _head(pal);
                  final u = _users[i - 1];
                  return _UserTile(
                    u: u,
                    guard: _guard?['enabled'] == true,
                    selected: wide && _selected == '${u['id']}',
                    onTap: () async {
                      if (wide) return setState(() => _selected = '${u['id']}');
                      await Navigator.of(context).push(
                        AppPageRoute(
                          builder: (_) => UserDetailPage(id: widget.id, userId: '${u['id']}', policy: widget.policy),
                        ),
                      );
                      _load();
                    },
                  );
                },
              ),
            ),
    );
  }

  Widget _head(Pal pal) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_guard != null) _GuardCard(guard: _guard!, onPatch: _setGuard),
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
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
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
          ],
        ),
      ),
    ],
  );
}

/// Công tắc tổng "Chặn đăng nhập (toàn bộ)" ở đầu danh sách. Bật: không ai đăng nhập được (mật khẩu, Google, mọi
/// thiết bị) trừ người được phép (riêng hoặc theo phòng ban) và quản trị viên (luôn được, để không tự khoá mình).
class _GuardCard extends StatelessWidget {
  final Map<String, dynamic> guard;
  final Future<void> Function(Map<String, dynamic> patch, String done) onPatch;
  const _GuardCard({required this.guard, required this.onPatch});

  Future<void> _allowDepts(BuildContext context) => _allowDeptsDialog(context, guard, onPatch);

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final on = guard['enabled'] == true;
    final allowed = (guard['allowed_count'] as num?)?.toInt() ?? 0, total = (guard['total'] as num?)?.toInt() ?? 0;
    final depts = [
      for (final d in (guard['allowed_depts'] as List? ?? const []))
        if (d is Map) '${d['name']}',
    ];
    final keep = guard['existing_sessions'] != 'logout';
    final color = on ? pal.accent : _amber;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Material(
        color: Color.alphaBlend(color.withValues(alpha: .08), pal.bg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: .35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const ValueKey('guard-switch'),
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 10, 0),
              secondary: Icon(on ? Icons.shield_rounded : Icons.shield_outlined, color: color, size: 30),
              title: Text(tr('Chặn đăng nhập (toàn bộ)'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                on
                    ? tr('Đang bật: chỉ người được phép và quản trị viên đăng nhập được (mật khẩu, Google, mọi thiết bị).')
                    : tr('Đang tắt: ai có tài khoản cũng đăng nhập được.'),
              ),
              value: on,
              onChanged: (v) => onPatch({'enabled': v}, v ? tr('Đã bật chặn đăng nhập') : tr('Đã tắt chặn đăng nhập')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Pill(Icons.how_to_reg_rounded, tr('{0}/{1} người được phép', [allowed, total]), _green),
                  _Pill(Icons.admin_panel_settings_rounded, tr('Quản trị viên luôn được phép'), _violet),
                  for (final d in depts) _Pill(Icons.account_tree_rounded, d, pal.accent),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text(
                tr('Người đang đăng nhập sẵn (không được phép)'),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.sub),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: true, label: Text(tr('Vẫn dùng tiếp')), icon: const Icon(Icons.play_circle_outline_rounded)),
                  ButtonSegment(value: false, label: Text(tr('Đăng xuất ngay')), icon: const Icon(Icons.logout_rounded)),
                ],
                selected: {keep},
                onSelectionChanged: (s) => onPatch({
                  'existing_sessions': s.first ? 'keep' : 'logout',
                }, s.first ? tr('Phiên cũ vẫn dùng được') : tr('Sẽ đăng xuất người không được phép')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                keep
                    ? tr('Chặn từ lần đăng nhập sau; phiên đang mở vẫn dùng tới khi người đó đăng xuất hoặc hết hạn.')
                    : tr('Bật chặn là đăng xuất luôn mọi phiên của người không được phép, trên mọi máy.'),
                style: TextStyle(fontSize: 12.5, color: pal.sub),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(onPressed: () => _allowDepts(context), icon: const Icon(Icons.group_add_rounded), label: Text(tr('Cho phép theo phòng ban'))),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: _red),
                    onPressed: () => onPatch({'logout_blocked': true}, tr('Đã đăng xuất người không được phép')),
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(tr('Đăng xuất tất cả người không được phép')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chọn phòng ban được phép đăng nhập (mọi thành viên, kể cả phòng con).
Future<void> _allowDeptsDialog(BuildContext context, Map<String, dynamic> guard, Future<void> Function(Map<String, dynamic>, String) onPatch) async {
  final depts = [
    for (final d in (guard['depts'] as List? ?? const []))
      if (d is Map) d,
  ];
  final sel = {
    for (final d in depts)
      if (d['allowed'] == true) '${d['id']}',
  };
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Cho phép theo phòng ban')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Mọi thành viên của phòng được chọn (kể cả phòng con) đăng nhập được khi đang chặn.'), style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              for (final d in depts)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: sel.contains('${d['id']}'),
                  onChanged: (v) => set(() => v == true ? sel.add('${d['id']}') : sel.remove('${d['id']}')),
                  title: Text('${d['name']}'),
                  subtitle: Text(tr('{0} người', [d['members'] ?? 0])),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
        ],
      ),
    ),
  );
  if (ok == true) await onPatch({'allowed_depts': sel.toList()}, tr('Đã lưu phòng ban được phép'));
}

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> u;
  final VoidCallback onTap;
  final bool selected;

  /// Đang chặn đăng nhập toàn bộ: hiện người này có được phép không.
  final bool guard;
  const _UserTile({required this.u, required this.onTap, this.selected = false, this.guard = false});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final inactive = u['status'] == 'inactive';
    final depts = [
      for (final d in (u['depts'] as List? ?? const []))
        if (d is Map) '${d['name']}${d['head'] == true ? ' (${tr('trưởng phòng')})' : ''}',
    ];
    return ListTile(
      onTap: onTap,
      selected: selected,
      selectedTileColor: pal.accent.withValues(alpha: .10),
      leading: Opacity(
        opacity: inactive ? .4 : 1,
        child: Avatar(userId: '${u['id']}', name: '${u['name'] ?? u['username']}', size: 42),
      ),
      title: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${(u['name'] ?? '').toString().isEmpty ? u['username'] : u['name']}',
            style: TextStyle(fontWeight: FontWeight.w600, color: inactive ? pal.sub : pal.text),
          ),
          if (u['system_admin'] == true) _Chip(tr('Quản trị'), _violet),
          if (u['is_bot'] == true) _Chip('Bot', pal.sub),
          if (inactive) _Chip(tr('Đã khoá'), _red),
          if (guard && !inactive && u['system_admin'] != true && u['login_allowed'] is bool)
            u['login_allowed'] == true ? _Chip(tr('Được phép'), _green) : _Chip(tr('Bị chặn'), _amber),
        ],
      ),
      subtitle: Text(
        [
          '@${u['username']}',
          if (depts.isNotEmpty) depts.join(', '),
          if ((u['devices'] ?? 0) != 0) tr('{0} thiết bị', ['${u['devices']}']),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
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
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

/// Nhãn trạng thái có biểu tượng (đầu trang chi tiết, công tắc tổng).
class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _Pill(this.icon, this.text, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------- mật khẩu

/// Kiểm tra mật khẩu quản trị đặt cho người khác: chính sách của máy chủ + mức tối thiểu của app (8 ký tự, 2 loại ký
/// tự), không có dấu / ký tự ngoài ASCII (bộ gõ tiếng Việt tự đổi "dd" thành "đ" nên người dùng gõ lại không khớp), không
/// có khoảng trắng đầu / cuối. Khoảng trắng ở giữa chỉ cảnh báo.
class PasswordCheck {
  final PasswordPolicy policy;
  const PasswordCheck(this.policy);

  int get minLength => policy.minLength < 8 ? 8 : policy.minLength;

  static int classes(String p) => [RegExp('[a-z]'), RegExp('[A-Z]'), RegExp('[0-9]'), RegExp(r'[^A-Za-z0-9]')].where(p.contains).length;

  /// Các yêu cầu (nhãn, đạt chưa) để hiện danh sách dưới ô mật khẩu.
  List<(String, bool)> rules(String p) => [
    (tr('Ít nhất {0} ký tự', [minLength]), p.length >= minLength && p.length <= PasswordPolicy.maxLength),
    if (policy.lower) (tr('Có chữ thường (a-z)'), p.contains(RegExp('[a-z]'))),
    if (policy.upper) (tr('Có chữ hoa (A-Z)'), p.contains(RegExp('[A-Z]'))),
    if (policy.number) (tr('Có chữ số (0-9)'), p.contains(RegExp('[0-9]'))),
    if (policy.symbol) (tr('Có ký tự đặc biệt (!@#...)'), p.split('').any(PasswordPolicy.symbols.contains)),
    if (!policy.lower && !policy.upper && !policy.number && !policy.symbol) (tr('Có ít nhất 2 loại: chữ thường, chữ hoa, số, ký tự đặc biệt'), classes(p) >= 2),
    (tr('Không có chữ có dấu hay ký tự lạ'), !p.contains(RegExp(r'[^\x20-\x7E]'))),
    (tr('Không có khoảng trắng ở đầu / cuối'), p.isEmpty || p.trim() == p),
  ];

  /// Lỗi chặn nút đặt mật khẩu (rỗng = hợp lệ).
  List<String> problems(String p) => [
    for (final (label, ok) in rules(p))
      if (!ok) label,
  ];

  bool valid(String p) => p.isNotEmpty && problems(p).isEmpty;

  /// Cảnh báo không chặn.
  List<String> warnings(String p) => [
    if (p.trim().contains(' ')) tr('Mật khẩu có khoảng trắng: nhớ nói rõ cho người dùng.'),
    if (p.contains(RegExp(r'[^\x00-\x7F]')))
      tr('Có chữ có dấu / ký tự ngoài bàn phím tiếng Anh: bộ gõ tiếng Việt (Telex, VNI) có thể đổi ký tự khi gõ lại, nên không cho dùng.'),
  ];

  /// Độ mạnh 0..4 (Rất yếu, Yếu, Trung bình, Khá, Mạnh).
  static int strength(String p) {
    if (p.isEmpty) return 0;
    var s = 0;
    if (p.length >= 8) s++;
    if (p.length >= 12) s++;
    final c = classes(p);
    if (c >= 2) s++;
    if (c >= 3) s++;
    if (p.length < 8) s = s.clamp(0, 1);
    if (RegExp(r'^(.)\1+$').hasMatch(p) || RegExp(r'^(0123|1234|abcd|qwer|pass|matkhau)', caseSensitive: false).hasMatch(p)) s = s.clamp(0, 1);
    return s.clamp(0, 4);
  }
}

/// Ô mật khẩu mới + nhập lại, có hiện / ẩn, thanh độ mạnh, danh sách yêu cầu sống và cảnh báo.
class PasswordFields extends StatefulWidget {
  final PasswordCheck check;
  final TextEditingController password, confirm;
  final VoidCallback onChanged;
  final bool autofocus;
  const PasswordFields({super.key, required this.check, required this.password, required this.confirm, required this.onChanged, this.autofocus = false});
  @override
  State<PasswordFields> createState() => _PasswordFieldsState();
}

class _PasswordFieldsState extends State<PasswordFields> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = widget.password.text, c = widget.confirm.text;
    final s = PasswordCheck.strength(p);
    final sColor = [pal.sub, _red, _amber, pal.accent, _green][s];
    final sLabel = [tr('Chưa nhập'), tr('Yếu'), tr('Trung bình'), tr('Khá'), tr('Mạnh')][s];
    final mismatch = c.isNotEmpty && c != p;
    final eye = IconButton(
      tooltip: _show ? tr('Ẩn mật khẩu') : tr('Hiện mật khẩu'),
      icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
      onPressed: () => setState(() => _show = !_show),
    );
    void changed(String _) {
      setState(() {});
      widget.onChanged();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('pw-new'),
          controller: widget.password,
          autofocus: widget.autofocus,
          obscureText: !_show,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(labelText: tr('Mật khẩu mới'), suffixIcon: eye, border: const OutlineInputBorder()),
          onChanged: changed,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 1; i <= 4; i++)
              Expanded(
                child: Container(
                  height: 5,
                  margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                  decoration: BoxDecoration(color: i <= s ? sColor : pal.surface2, borderRadius: BorderRadius.circular(3)),
                ),
              ),
            const SizedBox(width: 10),
            SizedBox(
              width: 84,
              child: Text(
                sLabel,
                key: const ValueKey('pw-strength'),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: sColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final (label, ok) in widget.check.rules(p))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              children: [
                Icon(
                  ok && p.isNotEmpty ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: ok && p.isNotEmpty ? _green : (p.isEmpty ? pal.sub : _red),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(label, style: TextStyle(fontSize: 12.5, color: ok || p.isEmpty ? pal.sub : pal.text)),
                ),
              ],
            ),
          ),
        for (final w in widget.check.warnings(p))
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _amber.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: _amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(w, style: TextStyle(fontSize: 12.5, color: pal.text)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('pw-confirm'),
          controller: widget.confirm,
          obscureText: !_show,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            labelText: tr('Nhập lại mật khẩu'),
            border: const OutlineInputBorder(),
            errorText: mismatch ? tr('Hai mật khẩu chưa khớp') : null,
            suffixIcon: c.isNotEmpty && !mismatch ? const Icon(Icons.check_rounded, color: _green) : null,
          ),
          onChanged: changed,
        ),
      ],
    );
  }
}

/// Hộp "Đặt lại mật khẩu": nút Đặt chỉ bật khi mật khẩu đạt yêu cầu và hai ô khớp; lỗi máy chủ hiện ngay trong hộp
/// (trước đây mật khẩu 7 ký tự bị máy chủ từ chối mà không thấy báo gì). Trả về true khi đã đặt.
class SetPasswordDialog extends StatefulWidget {
  final FlygoId id;
  final String userId, name;
  final PolicyLoader policy;
  const SetPasswordDialog({super.key, required this.id, required this.userId, required this.name, required this.policy});
  @override
  State<SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends State<SetPasswordDialog> {
  final _p = TextEditingController(), _c = TextEditingController();
  PasswordCheck _check = const PasswordCheck(PasswordPolicy());
  bool _busy = false, _keep = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.policy().then((p) {
      if (mounted && p != null) setState(() => _check = PasswordCheck(p));
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _p.dispose();
    _c.dispose();
    super.dispose();
  }

  bool get _ok => _check.valid(_p.text) && _c.text == _p.text && !_busy;

  Future<void> _save() async {
    setState(() => (_busy = true, _error = null));
    try {
      await widget.id.request('POST', '/v1/admin/users/${widget.userId}/password', {'password': _p.text, if (_keep) 'keep_sessions': true});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _busy = false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return AlertDialog(
      title: Text(tr('Đặt mật khẩu cho {0}', [widget.name])),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordFields(check: _check, password: _p, confirm: _c, autofocus: true, onChanged: () => setState(() => _error = null)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: !_keep,
                onChanged: (v) => setState(() => _keep = v == false),
                title: Text(tr('Đăng xuất người này khỏi mọi máy'), style: const TextStyle(fontSize: 13.5)),
              ),
              if (_error != null)
                Container(
                  key: const ValueKey('pw-error'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _red.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 18, color: _red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('Máy chủ không nhận mật khẩu: {0}', [_error]), style: TextStyle(fontSize: 13, color: pal.text)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(tr('Huỷ'))),
        FilledButton(
          key: const ValueKey('pw-submit'),
          onPressed: _ok ? _save : null,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('Đặt mật khẩu')),
        ),
      ],
    );
  }
}

class _CreateUserDialog extends StatefulWidget {
  final FlygoId id;
  final PolicyLoader policy;
  const _CreateUserDialog({required this.id, required this.policy});
  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _user = TextEditingController(), _pass = TextEditingController(), _pass2 = TextEditingController();
  final _name = TextEditingController(), _pos = TextEditingController();
  PasswordCheck _check = const PasswordCheck(PasswordPolicy());
  String? _error;
  bool _busy = false;

  static final _userRe = RegExp(r'^[a-z][a-z0-9._-]{2,21}$');

  @override
  void initState() {
    super.initState();
    widget.policy().then((p) {
      if (mounted && p != null) setState(() => _check = PasswordCheck(p));
    }, onError: (_) {});
  }

  bool get _ok => _userRe.hasMatch(_user.text.trim().toLowerCase()) && _check.valid(_pass.text) && _pass.text == _pass2.text && !_busy;

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
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('Họ tên')),
            ),
            TextField(
              controller: _user,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr('Tên đăng nhập'), helperText: tr('Chữ thường, số, . _ -; bắt đầu bằng chữ')),
            ),
            TextField(
              controller: _pos,
              decoration: InputDecoration(labelText: tr('Chức vụ (không bắt buộc)')),
            ),
            const SizedBox(height: 16),
            PasswordFields(check: _check, password: _pass, confirm: _pass2, onChanged: () => setState(() => _error = null)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: _red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(tr('Huỷ'))),
      FilledButton(onPressed: _ok ? _save : null, child: Text(tr('Tạo tài khoản'))),
    ],
  );
}

// ---------------------------------------------------------------- quyền gộp theo app

/// Tên hiển thị của các app quen thuộc (quyền chỉ ghi mã app).
const kAppNames = <String, (String, IconData)>{
  'vn.flygo.todo': ('Ghi chú & Việc', Icons.checklist_rounded),
  'vn.flygo.flows': ('Quy trình', Icons.account_tree_rounded),
  'vn.flygo.ai': ('Cổng AI', Icons.auto_awesome_rounded),
  'vn.flygo.mail': ('Thư', Icons.mail_rounded),
  'vn.flygo.calendar': ('Lịch', Icons.calendar_month_rounded),
  'vn.flygo.bangtin': ('Bảng tin', Icons.newspaper_rounded),
  'vn.flygo.dich': ('Dịch thuật', Icons.translate_rounded),
  'vn.flygo.contacts': ('Danh bạ', Icons.contacts_rounded),
  'vn.flygo.forms': ('Biểu mẫu', Icons.dynamic_form_rounded),
  'vn.flygo.wiki': ('Wiki', Icons.menu_book_rounded),
  'vn.flygo.reports': ('Báo cáo', Icons.bar_chart_rounded),
  'vn.flygo.hopdong': ('Hợp đồng', Icons.description_rounded),
  'vn.flygo.kyso': ('Ký số', Icons.draw_rounded),
  'vn.flygo.magic-sign': ('Ký số đa năng', Icons.draw_rounded),
  'vn.flygo.teamwork': ('Làm việc nhóm', Icons.groups_rounded),
  'vn.flygo.show': ('Trình chiếu', Icons.slideshow_rounded),
  'vn.flygo.web.drive': ('Drive', Icons.cloud_rounded),
  'vn.flygo.browser': ('Trình duyệt', Icons.public_rounded),
  'vn.flygo.gateway': ('Cổng kết nối', Icons.hub_rounded),
  'vn.flygo.chat': ('Chat', Icons.chat_rounded),
};

/// Nguồn của một quyền: user / dept / role / agent / flow / everyone (Flygo ID trả "loại:mã").
String viaKind(String via) {
  final k = via.split(':').first;
  return k == 'everyone' || k == 'dept' || k == 'role' ? k : 'user';
}

/// Quyền của một app, gộp các nguồn.
class AppGrants {
  final String app;

  /// perm (kèm space) → các nguồn.
  final Map<String, Set<String>> perms = {};
  AppGrants(this.app);

  String get name => kAppNames[app]?.$1 ?? app.split('.').last;
  IconData get icon => kAppNames[app]?.$2 ?? Icons.widgets_rounded;
  int get count => perms.length;
  Set<String> get kinds => {
    for (final s in perms.values)
      for (final v in s) viaKind(v),
  };
  List<String> get tools => [
    for (final p in perms.keys)
      if (p.startsWith('tool:')) p.substring(5),
  ]..sort();
  List<String> get events => [
    for (final p in perms.keys)
      if (p.startsWith('webhook:')) p.substring(8),
  ]..sort();
  List<String> get others =>
      [
        for (final p in perms.keys)
          if (!p.startsWith('tool:') && !p.startsWith('webhook:')) p,
      ]..sort(
        (a, b) => a == 'use'
            ? -1
            : b == 'use'
            ? 1
            : a.compareTo(b),
      );

  bool matches(String q) => q.isEmpty || '${name.toLowerCase()} $app ${perms.keys.join(' ')}'.toLowerCase().contains(q);

  /// Gộp danh sách quyền hiệu lực ({app, perm, space?, via}) theo app, sắp theo tên.
  static List<AppGrants> group(List<Map> perms) {
    final m = <String, AppGrants>{};
    for (final p in perms) {
      final g = m.putIfAbsent('${p['app']}', () => AppGrants('${p['app']}'));
      final key = '${p['perm']}${p['space'] != null ? ' · ${p['space']}' : ''}';
      g.perms.putIfAbsent(key, () => {}).add('${p['via']}');
    }
    return m.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

String permLabel(String p) =>
    switch (p.split(' · ').first) {
      'use' => tr('Dùng app'),
      'admin' => tr('Quản trị app'),
      final x => x,
    } +
    (p.contains(' · ') ? ' · ${p.split(' · ').last}' : '');

class _GrantsCard extends StatefulWidget {
  final List<Map> perms;
  final Map<String, String> deptNames;
  const _GrantsCard({required this.perms, required this.deptNames});
  @override
  State<_GrantsCard> createState() => _GrantsCardState();
}

class _GrantsCardState extends State<_GrantsCard> {
  String _q = '';

  String _via(String v) => switch (viaKind(v)) {
    'everyone' => tr('Mọi người'),
    'dept' => widget.deptNames[v.substring(5)] ?? tr('Phòng ban'),
    'role' => tr('Vai trò'),
    _ => tr('Riêng'),
  };

  Widget _kindChip(String k) => switch (k) {
    'everyone' => _Chip(tr('mọi người'), const Color(0xFF64748B)),
    'dept' => _Chip(tr('phòng ban'), const Color(0xFF0EA5E9)),
    'role' => _Chip(tr('vai trò'), _violet),
    _ => _Chip(tr('riêng'), _amber),
  };

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final all = AppGrants.group(widget.perms);
    final shown = [
      for (final g in all)
        if (g.matches(_q.toLowerCase())) g,
    ];
    final total = all.fold<int>(0, (a, g) => a + g.count);
    return _Card(
      title: tr('Quyền'),
      trailing: Text(tr('{0} quyền · {1} app', [total, all.length]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
      children: [
        if (all.length > 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: TextField(
              key: const ValueKey('grants-search'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: tr('Tìm app hoặc quyền'),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
        if (all.isEmpty)
          ListTile(
            dense: true,
            title: Text(tr('Chưa có quyền nào'), style: TextStyle(color: pal.sub)),
          ),
        for (final g in shown)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey('app-${g.app}'),
              initiallyExpanded: _q.isNotEmpty && shown.length == 1,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(58, 0, 14, 10),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              leading: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: pal.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
                child: Icon(g.icon, size: 19, color: pal.accent),
              ),
              title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tr('{0} quyền', [g.count]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
                    for (final k in ['user', 'dept', 'role', 'everyone'])
                      if (g.kinds.contains(k)) _kindChip(k),
                  ],
                ),
              ),
              children: [
                for (final p in g.others) _permRow(pal, permLabel(p), g.perms[p]!),
                if (g.tools.isNotEmpty) _group(pal, '${g.app}/tools', Icons.build_circle_outlined, tr('Công cụ AI: {0}', [g.tools.length]), g.tools),
                if (g.events.isNotEmpty) _group(pal, '${g.app}/events', Icons.bolt_rounded, tr('Sự kiện: {0}', [g.events.length]), g.events),
              ],
            ),
          ),
        if (all.isNotEmpty && shown.isEmpty)
          ListTile(
            dense: true,
            title: Text(tr('Không có quyền nào khớp'), style: TextStyle(color: pal.sub)),
          ),
      ],
    );
  }

  Widget _permRow(Pal pal, String label, Set<String> via) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(Icons.key_rounded, size: 15, color: pal.sub),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
        Text(via.map(_via).toSet().join(', '), style: TextStyle(fontSize: 12, color: pal.sub)),
      ],
    ),
  );

  Widget _group(Pal pal, String id, IconData icon, String title, List<String> items) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: PageStorageKey(id),
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 6),
      expandedAlignment: Alignment.centerLeft,
      leading: Icon(icon, size: 18, color: pal.sub),
      title: Text(title, style: const TextStyle(fontSize: 13.5)),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in items)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  t,
                  style: TextStyle(fontSize: 12, color: pal.text),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// Khung thẻ có tiêu đề của trang chi tiết.
class _Card extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  const _Card({required this.title, this.trailing, required this.children});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            ...children,
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- chi tiết

class UserDetailPage extends StatefulWidget {
  final FlygoId id;
  final String userId;

  /// Cột phải của tab Người dùng (máy tính): không có nút quay lại.
  final bool embedded;

  /// Có thay đổi (khoá, đổi tên…): danh sách tải lại.
  final VoidCallback? onChanged;
  final PolicyLoader? policy;
  const UserDetailPage({super.key, required this.id, required this.userId, this.embedded = false, this.onChanged, this.policy});
  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _logOpen = false;

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
  String get _name => '${(_u['name'] ?? '').toString().trim().isEmpty ? _u['username'] : _u['name']}';

  Future<void> _do(String method, String path, Map<String, dynamic>? body, String done) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await widget.id.request(method, path, body);
      m.showSnackBar(toast(Text(done)));
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: tr('Họ tên')),
            ),
            TextField(
              controller: pos,
              decoration: InputDecoration(labelText: tr('Chức vụ')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok == true) await _do('PATCH', '/v1/admin/users/${widget.userId}', {'name': name.text.trim(), 'position': pos.text.trim()}, tr('Đã lưu'));
  }

  Future<void> _password() async {
    final m = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => SetPasswordDialog(id: widget.id, userId: widget.userId, name: _name, policy: widget.policy ?? _defaultPolicy(context)),
    );
    if (ok == true) {
      m.showSnackBar(toast(Text(tr('Đã đặt mật khẩu mới'))));
      await _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _deactivate() async {
    var offboard = false;
    final ok = await confirmCountdown(
      context,
      title: tr('Khoá tài khoản {0}?', [_name]),
      body: tr('Tài khoản bị khoá, mọi thiết bị bị thu hồi. Có thể mở khoá lại sau.'),
      action: tr('Khoá'),
    );
    if (!ok || !mounted) return;
    offboard =
        await showDialog<bool>(
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

  Map? get _pw => _d?['password_login'] is Map ? _d!['password_login'] as Map : null;
  Map? get _login => _d?['login'] is Map ? _d!['login'] as Map : null;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bg, title: Text(_d == null ? '' : _name), automaticallyImplyLeading: !widget.embedded),
      body: _d == null
          ? Center(
              child: _error != null ? Text(_error!, style: TextStyle(color: pal.sub)) : const CircularProgressIndicator(),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    _header(pal),
                    _signIn(pal),
                    _depts(pal),
                    _GrantsCard(
                      perms: [
                        for (final p in (_d?['perms'] as List? ?? const []))
                          if (p is Map) p,
                      ],
                      deptNames: {
                        for (final d in (_u['depts'] as List? ?? const []))
                          if (d is Map) '${d['id']}': '${d['name']}',
                      },
                    ),
                    _devices(pal),
                    _audit(pal),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _header(Pal pal) {
    final u = _u;
    final inactive = u['status'] == 'inactive';
    final pw = _pw;
    final google = pw != null && (pw['google_linked'] == true || pw['google_enabled'] == true);
    final password = pw == null ? true : pw['has_password'] == true && pw['allowed'] == true;
    final passkey = _login?['passkey_required'] == true;
    final sub = [if (u['position'] != null && '${u['position']}'.trim().isNotEmpty) '${u['position']}', '@${u['username']}'].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [pal.accent.withValues(alpha: .16), pal.surface]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: inactive ? .5 : 1,
                child: Avatar(userId: widget.userId, name: _name, size: 60),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(color: pal.sub, fontSize: 13.5)),
                    if ('${u['email'] ?? ''}'.isNotEmpty) Text('${u['email']}', style: TextStyle(color: pal.sub, fontSize: 13.5)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: const ValueKey('user-menu'),
                tooltip: tr('Thêm'),
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) => switch (v) {
                  'edit' => _edit(),
                  'lock' => _deactivate(),
                  'unlock' => _do('POST', '/v1/admin/users/${widget.userId}/activate', null, tr('Đã mở khoá tài khoản')),
                  _ => null,
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(leading: const Icon(Icons.edit_rounded), title: Text(tr('Sửa thông tin'))),
                  ),
                  inactive
                      ? PopupMenuItem(
                          value: 'unlock',
                          child: ListTile(leading: const Icon(Icons.lock_open_rounded), title: Text(tr('Mở khoá tài khoản'))),
                        )
                      : PopupMenuItem(
                          value: 'lock',
                          child: ListTile(
                            leading: const Icon(Icons.lock_rounded, color: _red),
                            title: Text(tr('Khoá tài khoản…'), style: const TextStyle(color: _red)),
                          ),
                        ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (u['system_admin'] == true) _Pill(Icons.admin_panel_settings_rounded, tr('Quản trị viên'), _violet),
              if (inactive) _Pill(Icons.lock_rounded, tr('Đang khoá'), _red) else _Pill(Icons.check_circle_rounded, tr('Đang hoạt động'), _green),
              if (google) _Pill(Icons.g_mobiledata_rounded, 'Google', pal.accent),
              if (password) _Pill(Icons.password_rounded, tr('Mật khẩu'), pal.accent),
              if (passkey) _Pill(Icons.fingerprint_rounded, 'Passkey', const Color(0xFF14B8A6)),
              if (_login != null && _login!['allowed'] == false && u['system_admin'] != true) _Pill(Icons.block_rounded, tr('Bị chặn đăng nhập'), _amber),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey('btn-password'),
                onPressed: _password,
                icon: const Icon(Icons.password_rounded, size: 18),
                label: Text(tr('Đặt mật khẩu')),
              ),
              if (inactive)
                FilledButton.icon(
                  onPressed: () => _do('POST', '/v1/admin/users/${widget.userId}/activate', null, tr('Đã mở khoá tài khoản')),
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: Text(tr('Mở khoá')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Một dòng công tắc trong thẻ Đăng nhập.
  Widget _switch(
    Pal pal, {
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
    Widget? extra,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Không đổi được (cố định theo tài khoản): nhãn "Luôn bật / Luôn tắt" thay cho công tắc mờ khó đọc.
        if (onChanged == null)
          ListTile(
            key: key,
            leading: Icon(icon, color: pal.sub),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: pal.sub)),
            trailing: value ? _Chip(tr('Luôn bật'), _green) : _Chip(tr('Luôn tắt'), pal.sub),
          )
        else
          SwitchListTile(
            key: key,
            secondary: Icon(icon, color: pal.accent),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: Text(subtitle, style: TextStyle(fontSize: 12.5, color: pal.sub)),
            value: value,
            onChanged: onChanged,
          ),
        ?extra,
      ],
    );
  }

  Widget _signIn(Pal pal) {
    final u = _u;
    final pw = _pw;
    final login = _login;
    final admin = u['system_admin'] == true;
    final id = widget.userId;
    final linked = pw?['google_linked'] == true;
    final hasPw = pw?['has_password'] == true;
    return _Card(
      title: tr('Đăng nhập'),
      children: [
        if (login != null)
          _switch(
            pal,
            key: const ValueKey('sw-allowed'),
            icon: Icons.how_to_reg_rounded,
            title: tr('Được phép đăng nhập'),
            subtitle: admin
                ? tr('Quản trị viên luôn được phép, kể cả khi đang chặn đăng nhập toàn bộ.')
                : '${login['via']}'.startsWith('dept:')
                ? tr('Được phép theo phòng ban {0}.', ['${login['via_name'] ?? ''}'])
                : tr('Khi đang chặn đăng nhập toàn bộ, chỉ người bật mục này mới đăng nhập được.'),
            value: admin || login['allowed'] == true,
            onChanged: admin || '${login['via']}'.startsWith('dept:')
                ? null
                : (v) => _do('PATCH', '/v1/admin/users/$id', {'login_allowed': v}, v ? tr('Đã cho phép đăng nhập') : tr('Đã chặn đăng nhập')),
          ),
        if (pw == null)
          ListTile(
            leading: Icon(Icons.info_outline_rounded, color: pal.sub),
            title: Text(tr('Máy chủ chat chưa hỗ trợ chọn cách đăng nhập (cần vn.flygo.sso 0.4).'), style: TextStyle(fontSize: 13, color: pal.sub)),
          )
        else ...[
          _switch(
            pal,
            key: const ValueKey('sw-google'),
            icon: Icons.g_mobiledata_rounded,
            title: tr('Cho đăng nhập bằng Google'),
            subtitle: linked
                ? tr('Đã nối tài khoản Google: luôn đăng nhập Google được.')
                : tr('Đăng nhập Google bằng đúng email của tài khoản; mật khẩu hiện có vẫn dùng được.'),
            value: linked || pw['google_enabled'] == true,
            onChanged: linked
                ? null
                : (v) => _do('PATCH', '/v1/admin/users/$id', {'google_login': v}, v ? tr('Đã bật đăng nhập bằng Google') : tr('Đã tắt đăng nhập bằng Google')),
          ),
          _switch(
            pal,
            key: const ValueKey('sw-password'),
            icon: Icons.password_rounded,
            title: tr('Cho đăng nhập bằng mật khẩu'),
            subtitle: !linked
                ? tr('Tài khoản chỉ có mật khẩu: luôn đăng nhập bằng mật khẩu (không có cách nào khác).')
                : hasPw
                ? tr('Tắt: chỉ đăng nhập bằng Google. Bật: dùng được cả mật khẩu.')
                : tr('Bật sẵn thì đặt mật khẩu xong là đăng nhập được ngay.'),
            value: !linked || pw['enabled'] == true,
            onChanged: !linked
                ? null
                : (v) => _do('PATCH', '/v1/admin/users/$id', {
                    'password_login': v,
                  }, v ? tr('Đã bật đăng nhập bằng mật khẩu') : tr('Đã tắt đăng nhập bằng mật khẩu')),
            extra: hasPw
                ? null
                : Container(
                    key: const ValueKey('no-password-hint'),
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    decoration: BoxDecoration(color: _amber.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 18, color: _amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(tr('Chưa có mật khẩu: đặt mật khẩu để dùng.'), style: TextStyle(fontSize: 13, color: pal.text)),
                        ),
                        TextButton(onPressed: _password, child: Text(tr('Đặt mật khẩu'))),
                      ],
                    ),
                  ),
          ),
        ],
        if (login != null)
          _switch(
            pal,
            key: const ValueKey('sw-passkey'),
            icon: Icons.fingerprint_rounded,
            title: tr('Bắt buộc passkey trên mỗi thiết bị'),
            subtitle: login['passkey_policy'] == 'all'
                ? tr('Đang bắt buộc cho mọi người (cài đặt chung). Mỗi máy phải đăng ký passkey và xác thực khi mở app.')
                : tr('Mỗi máy phải đăng ký passkey (vân tay / Face ID / mã PIN) và xác thực mới dùng được.'),
            value: login['passkey_required'] == true,
            onChanged: login['passkey_policy'] == 'all'
                ? null
                : (v) => _do('PATCH', '/v1/admin/users/$id', {'passkey_required': v}, v ? tr('Đã bắt buộc passkey') : tr('Đã bỏ bắt buộc passkey')),
          ),
        _switch(
          pal,
          key: const ValueKey('sw-admin'),
          icon: Icons.admin_panel_settings_rounded,
          title: tr('Quản trị viên máy chủ'),
          subtitle: tr('Quản lý người dùng, phòng ban, quyền và cài đặt máy chủ.'),
          value: admin,
          onChanged: (v) => _do('PATCH', '/v1/admin/users/$id', {'system_admin': v}, v ? tr('Đã cấp quyền quản trị') : tr('Đã bỏ quyền quản trị')),
        ),
      ],
    );
  }

  Widget _depts(Pal pal) {
    final depts = [
      for (final d in (_u['depts'] as List? ?? const []))
        if (d is Map) d,
    ];
    return _Card(
      title: tr('Phòng ban'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: depts.isEmpty
              ? Text(tr('Chưa thuộc phòng ban nào (sửa ở Tổ chức)'), style: TextStyle(color: pal.sub, fontSize: 13.5))
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in depts)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: d['primary'] == true ? pal.accent.withValues(alpha: .12) : pal.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_tree_rounded, size: 15, color: d['primary'] == true ? pal.accent : pal.sub),
                            const SizedBox(width: 6),
                            Text('${d['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            for (final r in [
                              if (d['head'] == true) tr('Trưởng phòng'),
                              if (d['deputy'] == true) tr('Phó phòng'),
                              if (d['primary'] == true) tr('chính'),
                            ])
                              Text(' · $r', style: TextStyle(color: pal.sub, fontSize: 12.5)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _ago(Object? ms) {
    final t = (ms as num?)?.toInt();
    if (t == null || t <= 0) return '';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(t));
    if (d.inMinutes < 1) return tr('vừa xong');
    if (d.inHours < 1) return tr('{0} phút trước', [d.inMinutes]);
    if (d.inDays < 1) return tr('{0} giờ trước', [d.inHours]);
    return tr('{0} ngày trước', [d.inDays]);
  }

  Widget _devices(Pal pal) {
    final devices = [
      for (final d in (_d?['devices'] as List? ?? const []))
        if (d is Map) d,
    ];
    final needPasskey = _login?['passkey_required'] == true;
    return _Card(
      title: tr('Thiết bị & passkey'),
      trailing: Text(tr('{0} thiết bị', [devices.length]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
      children: [
        if (devices.isEmpty)
          ListTile(
            dense: true,
            title: Text(tr('Chưa có thiết bị nào ghi nhận'), style: TextStyle(color: pal.sub)),
          ),
        for (final d in devices) _device(pal, d, needPasskey),
      ],
    );
  }

  Widget _device(Pal pal, Map d, bool needPasskey) {
    final pk = d['passkey'] is Map ? d['passkey'] as Map : null;
    final plat = '${d['platform'] ?? ''}'.toLowerCase();
    final icon = plat.contains('ios') || plat.contains('android') ? Icons.smartphone_rounded : Icons.laptop_mac_rounded;
    final lines = [
      [
        '${d['platform'] ?? ''}',
        buildLabel('${d['app_version'] ?? ''}'),
        if (d['last_seen'] != null) _ago(d['last_seen']),
      ].where((x) => x.isNotEmpty).join(' · '),
    ];
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: pal.text),
      ),
      title: Text('${d['name'] ?? d['device_id']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lines.join(), style: TextStyle(fontSize: 12.5, color: pal.sub)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (pk != null)
                _Chip(
                  [
                    'Passkey',
                    if ('${pk['kind'] ?? ''}'.isNotEmpty) '${pk['kind']}',
                    if (pk['last_used'] != null) tr('xác thực {0}', [_ago(pk['last_used'])]),
                  ].join(' · '),
                  const Color(0xFF14B8A6),
                )
              else if (needPasskey)
                _Chip(tr('Chưa có passkey: bị chặn'), _amber)
              else if ((d['key'] as Map?)?['biometric_bound'] == true)
                _Chip(tr('Khoá sinh trắc học'), const Color(0xFF14B8A6)),
            ],
          ),
        ],
      ),
      trailing: TextButton(
        style: TextButton.styleFrom(foregroundColor: _red),
        onPressed: () async {
          final ok = await confirmCountdown(
            context,
            title: tr('Thu hồi "{0}"?', ['${d['name'] ?? ''}']),
            body: pk != null
                ? tr('Máy đó bị đăng xuất, passkey bị xoá; đăng nhập lại phải đăng ký passkey mới.')
                : tr('Máy đó sẽ bị đăng xuất và mất khoá bảo mật.'),
            action: tr('Thu hồi'),
          );
          if (ok) await _do('POST', '/v1/admin/users/${widget.userId}/devices/${d['device_id']}/revoke', null, tr('Đã thu hồi thiết bị'));
        },
        child: Text(tr('Thu hồi')),
      ),
    );
  }

  static const _actions = {
    'user.password': 'Đặt lại mật khẩu',
    'user.patch': 'Sửa thông tin',
    'user.create': 'Tạo tài khoản',
    'user.deactivate': 'Khoá tài khoản',
    'user.activate': 'Mở khoá tài khoản',
    'user.admin.set': 'Cấp quyền quản trị',
    'user.admin.unset': 'Bỏ quyền quản trị',
    'user.password_login.on': 'Bật đăng nhập mật khẩu',
    'user.password_login.off': 'Tắt đăng nhập mật khẩu',
    'user.google_login.on': 'Bật đăng nhập Google',
    'user.google_login.off': 'Tắt đăng nhập Google',
    'user.depts': 'Đổi phòng ban',
    'grant.add': 'Thêm quyền',
    'grant.remove': 'Gỡ quyền',
  };

  Widget _audit(Pal pal) {
    final audit = [
      for (final a in (_d?['audit'] as List? ?? const []))
        if (a is Map) a,
    ];
    return _Card(
      title: tr('Nhật ký'),
      trailing: audit.length > 3
          ? TextButton(onPressed: () => setState(() => _logOpen = !_logOpen), child: Text(_logOpen ? tr('Thu gọn') : tr('Xem tất cả ({0})', [audit.length])))
          : null,
      children: [
        if (audit.isEmpty)
          ListTile(
            dense: true,
            title: Text(tr('Chưa có'), style: TextStyle(color: pal.sub)),
          ),
        for (final a in audit.take(_logOpen ? 30 : 3))
          ListTile(
            dense: true,
            leading: Icon(Icons.history_rounded, size: 18, color: pal.sub),
            title: Text(tr(_actions['${a['action']}'] ?? '${a['action']}')),
            subtitle: Text([_ago(a['at']), '${a['actor'] ?? ''}'].where((x) => x.isNotEmpty).join(' · ')),
          ),
      ],
    );
  }
}
