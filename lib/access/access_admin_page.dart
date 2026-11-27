// Quản trị Flygo Access viết bằng Flutter (không webview). Điện thoại: thanh điều hướng dưới đáy (App, Thành viên,
// Quyền, Chợ app, Thêm), mỗi dòng chỉ có nút ba chấm ở cuối. Máy tính: thanh bên trái, nội dung rộng. Nền gradient nhẹ.
// Sửa quyền / khoá ký cần chữ ký P-256 của máy (Keychain / Keystore): chưa có thì hiện bản hiện hành, chỉ xem.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n.dart';
import 'access_api.dart';

class AccessAdminPage extends StatefulWidget {
  const AccessAdminPage({super.key, this.session, this.initialTab = 0});
  final FlygoSession? session;
  final int initialTab;
  @override
  State<AccessAdminPage> createState() => _AccessAdminPageState();
}

class _AccessAdminPageState extends State<AccessAdminPage> {
  late final FlygoSession session = widget.session ?? FlygoSession();
  late final AccessApi api = AccessApi(session);
  bool _ready = false;
  List<Map> _orgs = const [];
  String? _org;
  late int _tab = widget.initialTab;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final has = await session.restore();
    if (!mounted) return;
    if (has) await _loadOrgs();
    setState(() => _ready = true);
  }

  Future<void> _loadOrgs() async {
    try {
      final o = await api.myOrgs();
      setState(() {
        _orgs = o;
        _org = o.isEmpty ? null : '${(o.firstWhere((x) => x['admin'] == true, orElse: () => o.first))['org']}';
        _error = null;
      });
    } on AccessException catch (e) {
      if (e.needLogin) {
        setState(() {});
      } else {
        setState(() => _error = e);
      }
    } catch (e) {
      setState(() => _error = e);
    }
  }

  bool get _isAdmin => _orgs.any((o) => '${o['org']}' == _org && o['admin'] == true);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? [const Color(0xFF0F172A), const Color(0xFF111827), const Color(0xFF1E1B4B)]
            : [const Color(0xFFF5F7FF), const Color(0xFFFFFFFF), const Color(0xFFEFF6FF)],
      ),
    );
    Widget body;
    if (!_ready) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!session.signedIn) {
      body = _SignIn(
        session: session,
        onDone: () async {
          await _loadOrgs();
        },
      );
    } else if (_error != null) {
      body = _Problem(text: '$_error', onRetry: _loadOrgs);
    } else if (_org == null) {
      body = _Problem(text: tr('Tài khoản này chưa thuộc tổ chức nào trên Flygo Access.'), onRetry: _loadOrgs);
    } else {
      body = LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 760;
          final dests = _dests(_isAdmin);
          final i = _tab.clamp(0, dests.length - 1);
          final page = KeyedSubtree(key: ValueKey('$_org/$i'), child: dests[i].build(api, _org!));
          if (!wide) return page;
          return Row(
            children: [
              NavigationRail(
                backgroundColor: Colors.transparent,
                extended: c.maxWidth >= 1100,
                selectedIndex: i,
                onDestinationSelected: (v) => setState(() => _tab = v),
                destinations: [for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label))],
              ),
              VerticalDivider(width: 1, color: cs.outlineVariant),
              Expanded(child: page),
            ],
          );
        },
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final dests = _dests(_isAdmin);
    final showBar = !wide && _ready && session.signedIn && _org != null && _error == null;
    return Container(
      decoration: bg,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(tr('Quản trị Flygo')),
          actions: [
            if (_orgs.length > 1)
              PopupMenuButton<String>(
                tooltip: tr('Tổ chức'),
                icon: const Icon(Icons.apartment_rounded),
                onSelected: (v) => setState(() => _org = v),
                itemBuilder: (_) => [
                  for (final o in _orgs) CheckedPopupMenuItem(value: '${o['org']}', checked: '${o['org']}' == _org, child: Text('${o['org']}')),
                ],
              ),
            if (session.signedIn)
              IconButton(
                tooltip: tr('Đăng xuất Flygo ID'),
                icon: const Icon(Icons.logout_rounded),
                onPressed: () async {
                  await session.signOut();
                  setState(() {
                    _orgs = const [];
                    _org = null;
                  });
                },
              ),
          ],
        ),
        body: SafeArea(top: false, child: body),
        bottomNavigationBar: showBar
            ? NavigationBar(
                selectedIndex: _tab < _mobileMore(dests) ? _tab : _mobileMore(dests),
                onDestinationSelected: (v) {
                  if (v == _mobileMore(dests)) {
                    _openMore(context, dests);
                  } else {
                    setState(() => _tab = v);
                  }
                },
                destinations: [
                  for (final d in dests.take(_mobileMore(dests))) NavigationDestination(icon: Icon(d.icon), label: d.short),
                  NavigationDestination(icon: const Icon(Icons.more_horiz_rounded), label: tr('Thêm')),
                ],
              )
            : null,
      ),
    );
  }

  /// Điện thoại: 4 mục đầu ở thanh dưới, phần còn lại vào "Thêm".
  int _mobileMore(List<_Dest> d) => d.length <= 5 ? d.length - 1 : 4;

  void _openMore(BuildContext context, List<_Dest> dests) {
    final start = _mobileMore(dests);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var k = start; k < dests.length; k++)
              ListTile(
                leading: Icon(dests[k].icon),
                title: Text(dests[k].label),
                selected: _tab == k,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _tab = k);
                },
              ),
          ],
        ),
      ),
    );
  }

  List<_Dest> _dests(bool admin) => [
    _Dest(Icons.apps_rounded, tr('App của tôi'), tr('App'), (a, o) => _MyApps(api: a, org: o)),
    if (admin) ...[
      _Dest(Icons.groups_rounded, tr('Thành viên'), tr('Thành viên'), (a, o) => _Members(api: a, org: o)),
      _Dest(Icons.verified_user_rounded, tr('Phân quyền'), tr('Quyền'), (a, o) => _Grants(api: a, org: o)),
      _Dest(Icons.storefront_rounded, tr('Chợ app'), tr('Chợ app'), (a, o) => _Market(api: a, org: o)),
      _Dest(Icons.account_tree_rounded, tr('Phòng ban'), tr('Phòng ban'), (a, o) => _Departments(api: a, org: o)),
      _Dest(Icons.widgets_rounded, tr('App đã cài'), tr('Đã cài'), (a, o) => _Installed(api: a, org: o)),
      _Dest(Icons.key_rounded, tr('Khoá ký quản trị'), tr('Khoá'), (a, o) => _Keys(api: a, org: o)),
      _Dest(Icons.history_rounded, tr('Nhật ký'), tr('Nhật ký'), (a, o) => _Audit(api: a, org: o)),
      _Dest(Icons.receipt_long_rounded, tr('Thanh toán'), tr('Thanh toán'), (a, o) => _Billing(api: a, org: o)),
    ],
    _Dest(Icons.person_rounded, tr('Tài khoản Flygo ID'), tr('Tài khoản'), (a, o) => _Account(session: session)),
  ];
}

class _Dest {
  const _Dest(this.icon, this.label, this.short, this.build);
  final IconData icon;
  final String label, short;
  final Widget Function(AccessApi api, String org) build;
}

// ------------------------------------------------------------------ khung chung

/// Tải dữ liệu một lần, hiện vòng chờ / lỗi / nội dung; kéo xuống để tải lại.
class _Loader<T> extends StatefulWidget {
  const _Loader({super.key, required this.load, required this.build});
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) build;
  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  late Future<T> _f = widget.load();
  void _reload() => setState(() => _f = widget.load());
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _f,
    builder: (context, s) {
      if (s.hasError) return _Problem(text: _errText(s.error!), onRetry: _reload);
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(onRefresh: () async => _reload(), child: widget.build(context, s.data as T, _reload));
    },
  );
}

String _errText(Object e) => e is AccessException
    ? e.notAdmin
          ? tr('Cần quyền quản trị tổ chức (có khoá ký trong danh sách khoá).')
          : e.status == 503
          ? tr('Máy chủ tạm thời không trả lời, thử lại sau.')
          : '${e.message ?? e.code} (${e.status})'
    : '$e';

class _Problem extends StatelessWidget {
  const _Problem({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: Text(tr('Thử lại'))),
        ],
      ),
    ),
  );
}

/// Trang danh sách: tiêu đề + ô tìm + các dòng, rộng tối đa 900.
class _ListPage extends StatelessWidget {
  const _ListPage({required this.title, required this.children, this.action, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? action;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null) Text(subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(tr('Chưa có gì.'))),
            )
          else
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface.withValues(alpha: .85),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1), children[i]],
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Dòng thông tin: chỉ có nút ba chấm ở cuối (quy ước điện thoại).
class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.leading, this.menu = const {}, this.onTap, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? leading, trailing;
  final Map<String, VoidCallback> menu;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: leading,
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: subtitle == null ? null : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
    onTap: onTap,
    trailing: menu.isEmpty
        ? trailing
        : PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (k) => menu[k]!(),
            itemBuilder: (_) => [for (final k in menu.keys) PopupMenuItem(value: k, child: Text(k))],
          ),
  );
}

Widget _appIcon(Map a, {double size = 40}) {
  final icon = a['icon'];
  final name = '${a['name'] ?? a['app_name'] ?? a['app'] ?? a['id'] ?? '?'}';
  final fallback = CircleAvatar(radius: size / 2, child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase()));
  if (icon is String && icon.startsWith('http')) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image.network(icon, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
  return fallback;
}

Future<void> _run(BuildContext context, Future<void> Function() f, {VoidCallback? then, String? done}) async {
  final m = ScaffoldMessenger.of(context);
  try {
    await f();
    then?.call();
    if (done != null) m.showSnackBar(SnackBar(content: Text(done)));
  } catch (e) {
    m.showSnackBar(SnackBar(content: Text(_errText(e))));
  }
}

Future<bool> _confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Đồng ý'))),
        ],
      ),
    ) ??
    false;

/// Hộp nhập nhiều ô; trả null khi huỷ.
Future<Map<String, String>?> _form(BuildContext context, String title, Map<String, String> fields) {
  final ctl = {for (final e in fields.entries) e.key: TextEditingController(text: e.value)};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in ctl.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: e.value,
                  decoration: InputDecoration(labelText: e.key),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Huỷ'))),
        FilledButton(onPressed: () => Navigator.pop(c, {for (final e in ctl.entries) e.key: e.value.text.trim()}), child: Text(tr('Lưu'))),
      ],
    ),
  );
}

// ------------------------------------------------------------------ đăng nhập Flygo ID

class _SignIn extends StatefulWidget {
  const _SignIn({required this.session, required this.onDone});
  final FlygoSession session;
  final Future<void> Function() onDone;
  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _login = TextEditingController(), _pass = TextEditingController(), _code = TextEditingController();
  bool _busy = false, _twoFactor = false;
  String? _err;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (_twoFactor) {
        await widget.session.verifyTotp(_code.text.trim());
      } else if (await widget.session.signIn(_login.text.trim(), _pass.text) == 'two_factor') {
        setState(() {
          _twoFactor = true;
          _busy = false;
        });
        return;
      }
      await widget.onDone();
    } catch (e) {
      _err = _errText(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Đăng nhập Flygo ID'), style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (!_twoFactor) ...[
                TextField(
                  controller: _login,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  decoration: InputDecoration(labelText: tr('Email hoặc tên đăng nhập'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _go(),
                  decoration: InputDecoration(labelText: tr('Mật khẩu'), border: const OutlineInputBorder()),
                ),
              ] else
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  onSubmitted: (_) => _go(),
                  decoration: InputDecoration(labelText: tr('Mã xác minh hai bước'), border: const OutlineInputBorder()),
                ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _go, child: Text(_busy ? tr('Đang đăng nhập…') : tr('Tiếp tục'))),
            ],
          ),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------ 1. App của tôi

class _MyApps extends StatelessWidget {
  const _MyApps({required this.api, required this.org});
  final AccessApi api;
  final String org;
  @override
  Widget build(BuildContext context) => _Loader<List<Map>>(
    load: () => api.myApps(org),
    build: (context, apps, _) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: GridView.extent(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final a in apps)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _open(context, a),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _appIcon(a, size: 56),
                    const SizedBox(height: 8),
                    Text('${a['name']}', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  /// Mở app: lấy token riêng của app (5 phút) rồi mở địa chỉ giao diện kèm token trong phần #.
  Future<void> _open(BuildContext context, Map a) => _run(context, () async {
    final url = a['web_url'] as String?;
    if (url == null) throw AccessException(0, 'no_web_url', tr('App này chưa có giao diện.'));
    final t = await api.appToken(org, '${a['app']}');
    final u = Uri.parse(url);
    await launchUrl(u.replace(fragment: 'flygo_token=${Uri.encodeComponent('${t['token'] ?? ''}')}'), mode: LaunchMode.inAppBrowserView);
  });
}

// ------------------------------------------------------------------ 2. Thành viên

class _Members extends StatefulWidget {
  const _Members({required this.api, required this.org});
  final AccessApi api;
  final String org;
  @override
  State<_Members> createState() => _MembersState();
}

class _MembersState extends State<_Members> {
  String _q = '';
  @override
  Widget build(BuildContext context) => _Loader<Map>(
    load: () => widget.api.directory(widget.org),
    build: (context, d, reload) {
      final depts = {for (final x in (d['departments'] as List? ?? const [])) '${x['id']}': '${x['name']}'};
      final dm = (d['dept_members'] as List? ?? const []).cast<Map>();
      final members = (d['members'] as List? ?? const []).cast<Map>().where((m) {
        final q = _q.toLowerCase();
        return q.isEmpty || '${m['display']} ${m['email'] ?? ''}'.toLowerCase().contains(q);
      }).toList();
      return _ListPage(
        title: tr('Thành viên'),
        subtitle: tr('{0} người', ['${members.length}']),
        action: IconButton.filledTonal(
          tooltip: tr('Thêm thành viên'),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          onPressed: () async {
            final f = await _form(context, tr('Thêm thành viên'), {tr('Mã Flygo ID (sub)'): '', tr('Tên hiển thị'): '', tr('Email'): ''});
            if (f == null || !context.mounted) return;
            final v = f.values.toList();
            await _run(context, () => widget.api.putMember(widget.org, v[0], {'display': v[1], 'email': v[2].isEmpty ? null : v[2]}), then: reload);
          },
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm theo tên, email'), border: InputBorder.none),
            ),
          ),
          for (final m in members)
            _Row(
              leading: CircleAvatar(child: Text('${m['display']}'.isEmpty ? '?' : '${m['display']}'.characters.first.toUpperCase())),
              title: '${m['display']}',
              subtitle: [
                if (m['email'] != null) '${m['email']}',
                ...dm
                    .where((x) => x['sub'] == m['sub'])
                    .map(
                      (x) =>
                          '${depts[x['dept_id']] ?? x['dept_id']}${x['role'] == 'lead'
                              ? ' · ${tr('trưởng')}'
                              : x['role'] == 'deputy'
                              ? ' · ${tr('phó')}'
                              : ''}',
                    ),
                if (m['status'] != 'active') tr('đã khoá'),
              ].join(' · '),
              menu: {
                tr('Sửa'): () async {
                  final f = await _form(context, tr('Sửa thành viên'), {tr('Tên hiển thị'): '${m['display']}', tr('Email'): '${m['email'] ?? ''}'});
                  if (f == null || !context.mounted) return;
                  final v = f.values.toList();
                  await _run(
                    context,
                    () => widget.api.putMember(widget.org, '${m['sub']}', {'display': v[0], 'email': v[1].isEmpty ? null : v[1], 'status': m['status']}),
                    then: reload,
                  );
                },
                m['status'] == 'active' ? tr('Khoá') : tr('Mở khoá'): () => _run(
                  context,
                  () => widget.api.putMember(widget.org, '${m['sub']}', {
                    'display': m['display'],
                    'email': m['email'],
                    'status': m['status'] == 'active' ? 'suspended' : 'active',
                  }),
                  then: reload,
                ),
                tr('Xem quyền'): () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text('${m['display']}')),
                      body: _Grants(api: widget.api, org: widget.org, sub: '${m['sub']}'),
                    ),
                  ),
                ),
                tr('Xoá khỏi tổ chức'): () async {
                  if (await _confirm(context, tr('Xoá {0} khỏi tổ chức?', ['${m['display']}'])) && context.mounted) {
                    await _run(context, () => widget.api.removeMember(widget.org, '${m['sub']}'), then: reload);
                  }
                },
              },
            ),
        ],
      );
    },
  );
}

// ------------------------------------------------------------------ 3. Phòng ban

class _Departments extends StatelessWidget {
  const _Departments({required this.api, required this.org});
  final AccessApi api;
  final String org;
  @override
  Widget build(BuildContext context) => _Loader<Map>(
    load: () => api.directory(org),
    build: (context, d, reload) {
      final depts = (d['departments'] as List? ?? const []).cast<Map>();
      final members = {for (final m in (d['members'] as List? ?? const [])) '${m['sub']}': '${m['display']}'};
      final dm = (d['dept_members'] as List? ?? const []).cast<Map>();
      // Sơ đồ: duyệt cây từ gốc, thụt lề theo cấp.
      final rows = <Widget>[];
      void walk(String? parent, int level) {
        for (final x in depts.where((x) => x['parent_id'] == parent)) {
          final id = '${x['id']}';
          final mine = dm.where((m) => m['dept_id'] == id).toList();
          final lead = mine.where((m) => m['role'] == 'lead').map((m) => members[m['sub']] ?? m['sub']).join(', ');
          final deputy = mine.where((m) => m['role'] == 'deputy').map((m) => members[m['sub']] ?? m['sub']).join(', ');
          rows.add(
            Padding(
              padding: EdgeInsets.only(left: 20.0 * level),
              child: _Row(
                leading: Icon(level == 0 ? Icons.apartment_rounded : Icons.subdirectory_arrow_right_rounded),
                title: '${x['name']}',
                subtitle: [
                  tr('{0} người', ['${mine.length}']),
                  if (lead.isNotEmpty) '${tr('Trưởng')}: $lead',
                  if (deputy.isNotEmpty) '${tr('Phó')}: $deputy',
                ].join(' · '),
                onTap: () => _people(context, x, mine, members, reload),
                menu: {
                  tr('Thêm phòng con'): () => _edit(context, null, id, reload),
                  tr('Đổi tên'): () => _edit(context, x, x['parent_id'] as String?, reload),
                  tr('Thêm người'): () => _addPerson(context, id, members, reload),
                  tr('Xoá'): () async {
                    if (await _confirm(context, tr('Xoá phòng ban {0}?', ['${x['name']}'])) && context.mounted) {
                      await _run(context, () => api.removeDepartment(org, id), then: reload);
                    }
                  },
                },
              ),
            ),
          );
          walk(id, level + 1);
        }
      }

      walk(null, 0);
      return _ListPage(
        title: tr('Phòng ban'),
        subtitle: tr('Sơ đồ tổ chức, trưởng / phó nhóm'),
        action: IconButton.filledTonal(tooltip: tr('Thêm phòng ban'), icon: const Icon(Icons.add_rounded), onPressed: () => _edit(context, null, null, reload)),
        children: rows,
      );
    },
  );

  Future<void> _edit(BuildContext context, Map? x, String? parent, VoidCallback reload) async {
    final f = await _form(context, x == null ? tr('Thêm phòng ban') : tr('Đổi tên phòng ban'), {
      if (x == null) tr('Mã phòng ban'): '',
      tr('Tên'): '${x?['name'] ?? ''}',
    });
    if (f == null || !context.mounted) return;
    final v = f.values.toList();
    final id = x == null ? v[0] : '${x['id']}';
    final name = x == null ? v[1] : v[0];
    await _run(context, () => api.putDepartment(org, id, name, parent), then: reload);
  }

  Future<void> _addPerson(BuildContext context, String dept, Map<String, String> members, VoidCallback reload) async {
    final sub = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr('Thêm người vào phòng')),
        children: [for (final e in members.entries) SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Text(e.value))],
      ),
    );
    if (sub == null || !context.mounted) return;
    await _run(context, () => api.putDeptMember(org, dept, sub, 'member'), then: reload);
  }

  void _people(BuildContext context, Map x, List<Map> mine, Map<String, String> members, VoidCallback reload) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('${x['name']}', style: Theme.of(context).textTheme.titleMedium)),
            for (final m in mine)
              _Row(
                title: members[m['sub']] ?? '${m['sub']}',
                subtitle: switch (m['role']) {
                  'lead' => tr('Trưởng nhóm'),
                  'deputy' => tr('Phó nhóm'),
                  _ => tr('Thành viên'),
                },
                menu: {
                  tr('Đặt làm trưởng'): () => _setRole(c, x, m, 'lead', reload),
                  tr('Đặt làm phó'): () => _setRole(c, x, m, 'deputy', reload),
                  tr('Đặt làm thành viên'): () => _setRole(c, x, m, 'member', reload),
                  tr('Bỏ khỏi phòng'): () {
                    Navigator.pop(c);
                    _run(context, () => api.removeDeptMember(org, '${x['id']}', '${m['sub']}'), then: reload);
                  },
                },
              ),
          ],
        ),
      ),
    );
  }

  void _setRole(BuildContext c, Map x, Map m, String role, VoidCallback reload) {
    Navigator.pop(c);
    _run(c, () => api.putDeptMember(org, '${x['id']}', '${m['sub']}', role), then: reload);
  }
}

// ------------------------------------------------------------------ 4. Phân quyền

class _Grants extends StatefulWidget {
  const _Grants({required this.api, required this.org, this.sub});
  final AccessApi api;
  final String org;
  final String? sub;
  @override
  State<_Grants> createState() => _GrantsState();
}

class _GrantsState extends State<_Grants> {
  String? _app, _group;
  @override
  Widget build(BuildContext context) => _Loader<(List<Map>, Map)>(
    key: ValueKey(_group),
    load: () async => (await widget.api.grants(widget.org, sub: widget.sub, group: _group), await widget.api.directory(widget.org)),
    build: (context, data, reload) {
      final (all, dir) = data;
      final names = {for (final m in (dir['members'] as List? ?? const [])) '${m['sub']}': '${m['display']}'};
      final depts = {for (final x in (dir['departments'] as List? ?? const [])) '${x['id']}': '${x['name']}'};
      final apps = {for (final g in all) '${g['app']}': '${g['app_name']}'};
      final list = all.where((g) => _app == null || g['app'] == _app).toList();
      final cs = Theme.of(context).colorScheme;
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (widget.sub == null) Text(tr('Phân quyền'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filter(context, tr('App'), _app == null ? tr('Tất cả app') : apps[_app] ?? _app!, {
                    null: tr('Tất cả app'),
                    ...apps,
                  }, (v) => setState(() => _app = v)),
                  if (widget.sub == null)
                    _filter(context, tr('Phòng ban'), _group == null ? tr('Mọi phòng ban') : depts[_group] ?? _group!, {
                      null: tr('Mọi phòng ban'),
                      ...depts,
                    }, (v) => setState(() => _group = v)),
                ],
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text(tr('Không có dòng quyền nào.'))),
                ),
              for (final g in list)
                Card(
                  elevation: 0,
                  color: cs.surface.withValues(alpha: .85),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _appIcon({'name': g['app_name']}, size: 32),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '${g['perm_label']}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (g['sensitive'] == true) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(6)),
                                          child: Text(tr('nhạy cảm'), style: TextStyle(fontSize: 11, color: cs.onErrorContainer)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '${g['app_name']} · ${g['kind'] == 'admin' ? tr('quản trị ký ({0})', ['${g['signed_by'] ?? ''}']) : tr('bản nền (Access ký)')}',
                                    style: TextStyle(fontSize: 12, color: cs.outline),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              onSelected: (_) => _showPolicy(context, '${g['app']}', '${g['app_name']}'),
                              itemBuilder: (_) => [PopupMenuItem(value: 'p', child: Text(tr('Xem bản quyền của app')))],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _kv(context, tr('Ai được dùng'), switch (g['via']) {
                                  'everyone' => tr('Mọi người'),
                                  'group' => '${depts[g['group']] ?? g['group']} (${g['group_size']})',
                                  _ => names[g['sub']] ?? '${g['sub']}',
                                }),
                              ),
                              Expanded(
                                child: _kv(
                                  context,
                                  tr('Tham số'),
                                  g['params'] is Map && (g['params'] as Map).isNotEmpty
                                      ? (g['params'] as Map).entries.map((e) => '${e.key}: ${e.value}').join('\n')
                                      : '—',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _kv(BuildContext context, String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
      const SizedBox(height: 2),
      Text(v),
    ],
  );

  Widget _filter(BuildContext context, String label, String shown, Map<String?, String> items, ValueChanged<String?> on) => PopupMenuButton<String?>(
    onSelected: on,
    itemBuilder: (_) => [for (final e in items.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
    child: Chip(avatar: const Icon(Icons.filter_list_rounded, size: 16), label: Text(shown)),
  );

  /// Sửa quyền cần ký bằng khoá P-256 của máy: bản này mới xem bản hiện hành.
  void _showPolicy(BuildContext context, String app, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(name)),
          body: _Loader<Map>(
            load: () => widget.api.policy(widget.org, app),
            build: (context, p, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(tr('Sửa quyền cần khoá ký quản trị của máy này')),
                    subtitle: Text(tr('Bản quản trị v{0}, bản nền v{1}.', ['${(p['admin'] as Map?)?['ver'] ?? 0}', '${(p['base'] as Map?)?['ver'] ?? 0}'])),
                  ),
                ),
                SelectableText(const JsonEncoderPretty().convert(p), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class JsonEncoderPretty {
  const JsonEncoderPretty();
  String convert(Object o) => _enc(o, '');
  String _enc(Object? o, String ind) {
    if (o is Map) {
      if (o.isEmpty) return '{}';
      return '{\n${o.entries.map((e) => '$ind  "${e.key}": ${_enc(e.value, '$ind  ')}').join(',\n')}\n$ind}';
    }
    if (o is List) {
      if (o.isEmpty) return '[]';
      return '[\n${o.map((e) => '$ind  ${_enc(e, '$ind  ')}').join(',\n')}\n$ind]';
    }
    return o is String ? '"$o"' : '$o';
  }
}

// ------------------------------------------------------------------ 5. App đã cài

class _Installed extends StatelessWidget {
  const _Installed({required this.api, required this.org});
  final AccessApi api;
  final String org;
  @override
  Widget build(BuildContext context) => _Loader<List<Map>>(
    load: () => api.installed(org),
    build: (context, apps, reload) => _ListPage(
      title: tr('App đã cài'),
      children: [
        for (final a in apps)
          _Row(
            leading: _appIcon(a),
            title: '${a['name']}',
            subtitle: [
              a['mode'] == 'signed' ? tr('quyền đã ký') : tr('quyền qua token'),
              a['in_sync'] == true ? tr('đã đồng bộ') : tr('chưa đồng bộ'),
              if (a['push_error'] != null) '${tr('lỗi gửi')}: ${a['push_error']}',
            ].join(' · '),
            menu: {
              if (a['mode'] == 'signed') tr('Gửi lại quyền'): () => _run(context, () => api.push(org, '${a['app']}'), then: reload, done: tr('Đã gửi lại')),
              if (a['web_url'] != null) tr('Mở giao diện'): () => launchUrl(Uri.parse('${a['web_url']}')),
              if (a['admin_url'] != null) tr('Mở trang quản trị của app'): () => launchUrl(Uri.parse('${a['admin_url']}')),
            },
          ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ 6. Chợ app

class _Market extends StatelessWidget {
  const _Market({required this.api, required this.org});
  final AccessApi api;
  final String org;
  @override
  Widget build(BuildContext context) => _Loader<(List<Map>, Set<String>)>(
    load: () async => (await api.catalog(), {for (final a in await api.installed(org)) '${a['app']}'}),
    build: (context, d, reload) {
      final (apps, have) = d;
      return _ListPage(
        title: tr('Chợ app'),
        children: [
          for (final a in apps)
            _Row(
              leading: _appIcon(a),
              title: '${a['name'] ?? a['id']}',
              subtitle: [
                if (a['publisher'] != null) '${a['publisher'] is Map ? (a['publisher'] as Map)['name'] : a['publisher']}',
                if ((a['rating'] as Map?)?['count'] != 0) '★ ${(a['rating'] as Map?)?['stars']} (${(a['rating'] as Map?)?['count']})',
                if (have.contains('${a['id']}')) tr('đã cài'),
              ].join(' · '),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _AppDetail(api: api, org: org, id: '${a['id']}', installed: have.contains('${a['id']}'), onChanged: reload),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _AppDetail extends StatelessWidget {
  const _AppDetail({required this.api, required this.org, required this.id, required this.installed, required this.onChanged});
  final AccessApi api;
  final String org, id;
  final bool installed;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: _Loader<(Map, Map)>(
      load: () async => (await api.app(id), await api.reviews(id, org)),
      build: (context, d, reload) {
        final (raw, rv) = d;
        final a = (raw['manifest'] as Map?) ?? raw;
        final perms = (a['perms'] as List? ?? const []).cast<Map>();
        final cs = Theme.of(context).colorScheme;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                _appIcon(a, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a['name'] ?? id}', style: Theme.of(context).textTheme.titleLarge),
                      if (a['description'] != null) Text('${a['description']}', style: TextStyle(color: cs.outline)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: Icon(installed ? Icons.settings_rounded : Icons.download_rounded),
              label: Text(installed ? tr('Cài lại / đổi địa chỉ') : tr('Cài cho tổ chức')),
              onPressed: () async {
                final web = (a['web'] as Map?) ?? const {};
                final f = await _form(context, tr('Cài {0}', ['${a['name'] ?? id}']), {
                  tr('Địa chỉ giao diện'): '${web['url'] ?? ''}',
                  tr('Địa chỉ trang quản trị'): '${web['adminUrl'] ?? ''}',
                  tr('Địa chỉ policy (app kiểu ký)'): '',
                });
                if (f == null || !context.mounted) return;
                final v = f.values.toList();
                await _run(
                  context,
                  () => api.install(org, id, {
                    if (v[0].isNotEmpty) 'web_url': v[0],
                    if (v[1].isNotEmpty) 'admin_url': v[1],
                    if (v[2].isNotEmpty) 'policy_url': v[2],
                  }),
                  then: onChanged,
                  done: tr('Đã cài'),
                );
              },
            ),
            if (perms.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(tr('Quyền app khai báo'), style: Theme.of(context).textTheme.titleMedium),
              for (final p in perms)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(p['sensitive'] == true ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded),
                  title: Text('${p['label'] ?? p['id']}'),
                  subtitle: p['params'] is List && (p['params'] as List).isNotEmpty
                      ? Text('${tr('Tham số')}: ${(p['params'] as List).map((x) => x is Map ? x['id'] ?? x['name'] : x).join(', ')}')
                      : null,
                ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text(tr('Đánh giá'), style: Theme.of(context).textTheme.titleMedium)),
                if (installed)
                  TextButton(
                    onPressed: () => _review(context, rv['mine'] as Map?, reload),
                    child: Text(rv['mine'] == null ? tr('Viết đánh giá') : tr('Sửa đánh giá')),
                  ),
              ],
            ),
            for (final r in (rv['reviews'] as List? ?? const []).cast<Map>())
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${'★' * ((r['stars'] as num?)?.toInt() ?? 0)}  ${r['display'] ?? ''}'),
                subtitle: Text('${r['body'] ?? ''}'),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _review(BuildContext context, Map? mine, VoidCallback reload) async {
    var stars = (mine?['stars'] as num?)?.toInt() ?? 5;
    final body = TextEditingController(text: '${mine?['body'] ?? ''}');
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('Đánh giá')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_border_rounded, color: Colors.amber),
                      onPressed: () => set(() => stars = i),
                    ),
                ],
              ),
              TextField(
                controller: body,
                maxLines: 4,
                decoration: InputDecoration(hintText: tr('Nhận xét')),
              ),
            ],
          ),
          actions: [
            if (mine != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: Text(tr('Xoá'))),
            TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Huỷ'))),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );
    if (r == null || !context.mounted) return;
    await _run(context, () => r == 'delete' ? api.removeReview(org, id) : api.putReview(org, id, stars, body.text.trim()), then: reload);
  }
}

// ------------------------------------------------------------------ 7. Khoá ký quản trị

class _Keys extends StatelessWidget {
  const _Keys({required this.api, required this.org});
  final AccessApi api;
  final String org;
  @override
  Widget build(BuildContext context) => _Loader<Map>(
    load: () => api.keys(org),
    build: (context, k, _) {
      final payload = k['payload'] is String ? null : k['payload'] as Map?;
      final keys = ((payload ?? k)['keys'] as List? ?? const []).cast<Map>();
      return _ListPage(
        title: tr('Khoá ký quản trị'),
        subtitle: tr('Danh sách khoá v{0}. Thêm / bỏ khoá cần ký bằng một khoá đang có.', ['${k['ver'] ?? 0}']),
        children: [
          for (final x in keys)
            _Row(
              leading: const Icon(Icons.key_rounded),
              title: '${x['label'] ?? x['name'] ?? x['kid']}',
              subtitle: [if (x['kid'] != null) 'kid ${x['kid']}', if (x['sub'] != null) '${x['sub']}'].join(' · '),
            ),
        ],
      );
    },
  );
}

// ------------------------------------------------------------------ 8. Nhật ký

class _Audit extends StatelessWidget {
  const _Audit({required this.api, required this.org});
  final AccessApi api;
  final String org;
  @override
  Widget build(BuildContext context) => _Loader<List<Map>>(
    load: () => api.audit(org, limit: 200),
    build: (context, items, _) => _ListPage(
      title: tr('Nhật ký'),
      children: [
        for (final x in items)
          _Row(
            leading: const Icon(Icons.bolt_rounded),
            title: '${x['action']}',
            subtitle:
                '${_when(x['at'])}${x['detail'] is Map && (x['detail'] as Map).isNotEmpty ? ' · ${(x['detail'] as Map).entries.map((e) => '${e.key}=${e.value}').join(', ')}' : ''}',
          ),
      ],
    ),
  );
}

String _when(Object? at) {
  final t = DateTime.tryParse('$at')?.toLocal();
  if (t == null) return '$at';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

// ------------------------------------------------------------------ 9. Thanh toán

class _Billing extends StatelessWidget {
  const _Billing({required this.api, required this.org});
  final AccessApi api;
  final String org;
  static String _vnd(num v) => '${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')} đ';
  @override
  Widget build(BuildContext context) => _Loader<Map>(
    load: () => api.billing(org),
    build: (context, b, _) {
      final cur = (b['current'] as Map?) ?? const {};
      return _ListPage(
        title: tr('Thanh toán'),
        subtitle: tr('Tạm tính tháng {0}: {1} (chưa thu tiền)', ['${b['month']}', _vnd((cur['total'] as num?) ?? 0)]),
        children: [
          for (final l in (cur['lines'] as List? ?? const []).cast<Map>())
            _Row(
              leading: _appIcon({'name': l['name']}),
              title: '${l['name']}',
              subtitle: switch (l['model']) {
                'monthly' => tr('Theo tháng'),
                'usage' => tr('{0} lượt gọi', ['${l['calls']}']),
                _ => tr('Miễn phí'),
              },
              trailing: Text(_vnd((l['total'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          for (final h in (b['history'] as List? ?? const []).cast<Map>())
            _Row(leading: const Icon(Icons.calendar_month_rounded), title: '${h['month']}', trailing: Text(_vnd((h['total'] as num?) ?? 0))),
        ],
      );
    },
  );
}

// ------------------------------------------------------------------ 10. Tài khoản Flygo ID

class _Account extends StatelessWidget {
  const _Account({required this.session});
  final FlygoSession session;
  @override
  Widget build(BuildContext context) => _Loader<(Map, List)>(
    load: () async {
      final s = await session.id('GET', '/get-session') as Map? ?? const {};
      final list = await session.id('GET', '/list-sessions') as List? ?? const [];
      return (s, list);
    },
    build: (context, d, reload) {
      final (s, sessions) = d;
      final u = (s['user'] as Map?) ?? const {};
      return _ListPage(
        title: tr('Tài khoản Flygo ID'),
        subtitle: '${u['email'] ?? ''}',
        children: [
          _Row(
            leading: const Icon(Icons.badge_rounded),
            title: '${u['name'] ?? ''}',
            subtitle: tr('Tên hiển thị'),
            menu: {
              tr('Đổi tên'): () async {
                final f = await _form(context, tr('Đổi tên'), {tr('Tên'): '${u['name'] ?? ''}'});
                if (f == null || !context.mounted) return;
                await _run(context, () => session.id('POST', '/update-user', {'name': f.values.first}), then: reload);
              },
            },
          ),
          _Row(leading: const Icon(Icons.password_rounded), title: tr('Mật khẩu'), menu: {tr('Đổi mật khẩu'): () => _changePassword(context)}),
          _Row(
            leading: const Icon(Icons.shield_rounded),
            title: tr('Xác minh hai bước'),
            subtitle: u['twoFactorEnabled'] == true ? tr('Đang bật') : tr('Đang tắt'),
          ),
          for (final x in sessions.cast<Map>())
            _Row(
              leading: const Icon(Icons.devices_rounded),
              title: '${x['userAgent'] ?? tr('Thiết bị')}',
              subtitle: '${x['ipAddress'] ?? ''} · ${_when(x['updatedAt'] ?? x['createdAt'])}',
              menu: {
                tr('Đăng xuất phiên này'): () => _run(context, () => session.id('POST', '/revoke-session', {'token': x['token']}), then: reload),
              },
            ),
        ],
      );
    },
  );

  Future<void> _changePassword(BuildContext context) async {
    final cur = TextEditingController(), next = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Đổi mật khẩu')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cur,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Mật khẩu hiện tại')),
            ),
            TextField(
              controller: next,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Mật khẩu mới')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
      context,
      () => session.id('POST', '/change-password', {'currentPassword': cur.text, 'newPassword': next.text, 'revokeOtherSessions': false}),
      done: tr('Đã đổi mật khẩu'),
    );
  }
}
