import '../i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../browser/flygo_browser_host.dart';
import '../browser/flygo_browser_loading.dart';
import '../browser/flygo_machine_client.dart';
import '../browser/my_browsers.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'devices_page.dart' show confirmCountdown;
import 'theme.dart';

/// Cài đặt › Trình duyệt của tôi: các trình duyệt (extension Flygo Browser Bridge) đã nối với tài khoản, để agent của mình
/// điều khiển (tag @trình-duyệt khi chat với agent). Bật/tắt cho cả tài khoản, đổi tên, mặc định, dừng agent, gỡ;
/// MCP token cho agent ngoài (Claude Code, Codex, Cursor…).
class MyBrowsersPage extends StatefulWidget {
  const MyBrowsersPage({super.key, this.debugBrowsers, this.debugProfiles});

  /// Dữ liệu giả cho ảnh xem trước (test): bỏ qua tải từ Gateway / Flygo ID.
  @visibleForTesting
  final List<MyBrowser>? debugBrowsers;
  @visibleForTesting
  final List<Map<String, dynamic>>? debugProfiles;
  @override
  State<MyBrowsersPage> createState() => _MyBrowsersPageState();
}

class _MyBrowsersPageState extends State<MyBrowsersPage> {
  List<MyBrowser> _list = [];
  List<Map<String, dynamic>> _tokens = [];
  bool _loading = true;
  String? _error;

  String get _token => context.read<AppState>().token;

  @override
  void initState() {
    super.initState();
    if (widget.debugBrowsers != null) {
      _list = widget.debugBrowsers!;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final l = await MyBrowsers.list(_token, refresh: true);
      final t = await MyBrowsers.mcpTokens(_token).catchError((_) => <Map<String, dynamic>>[]);
      if (!mounted) return;
      setState(() {
        _list = l;
        _tokens = t.where((x) => x['revoked_at'] == null && ((x['expires_at'] as num?) ?? 0) > DateTime.now().millisecondsSinceEpoch).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<Object?> Function() f, String done) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await f();
      m.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  Future<void> _rename(MyBrowser b) async {
    final name = await askText(context, tr('Đổi tên trình duyệt'), b.name);
    if (name == null || name.trim().isEmpty) return;
    await _act(() => MyBrowsers.rename(_token, b.id, name.trim()), tr('Đã đổi tên'));
  }

  Future<void> _remove(MyBrowser b) async {
    final ok = await confirmCountdown(context,
        title: tr('Gỡ "{0}"?', [b.name]), body: tr('Agent sẽ không dùng được trình duyệt này nữa. Muốn dùng lại thì mở Flygo Chat trên máy đó.'), action: tr('Gỡ'));
    if (!ok) return;
    await _act(() => MyBrowsers.remove(_token, b.id), tr('Đã gỡ'));
  }

  Future<void> _newToken() async {
    final name = await askText(context, tr('Tên agent dùng token (vd Claude Code laptop)'), '');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      final r = await MyBrowsers.createMcpToken(_token, name.trim());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('MCP token (chỉ hiện một lần)')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Thêm MCP server dạng HTTP vào agent:'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText('${r['mcp_url']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
            const SizedBox(height: 10),
            Text(tr('Header Authorization: Bearer'), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText('${r['token']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: 'claude mcp add --transport http flygo-browser ${r['mcp_url']} --header "Authorization: Bearer ${r['token']}"')),
                child: Text(tr('Chép lệnh Claude Code'))),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Xong'))),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final aiOn = MyBrowsers.prefs['ai_enabled'] != false;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        title: Text(tr('Trình duyệt của tôi')),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: tr('Tải lại'))],
      ),
      body: _loading && _list.isEmpty && _error == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                      tr('Trình duyệt Chrome / Edge có extension Flygo Browser Bridge. Agent của bạn điều khiển được các trình duyệt này: tag @tên-trình-duyệt khi chat với agent. Chỉ agent của chính bạn dùng được.'),
                      style: TextStyle(fontSize: 13, color: pal.sub)),
                ),
                if (_error != null)
                  Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: pal.sub))),
                SwitchListTile(
                  value: aiOn,
                  title: Text(tr('Cho AI dùng trình duyệt')),
                  subtitle: Text(tr('Tắt thì mọi agent dừng điều khiển mọi trình duyệt của bạn.'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
                  onChanged: (v) => _act(() => MyBrowsers.setPrefs(_token, aiEnabled: v), v ? tr('Đã bật') : tr('Đã tắt')),
                ),
                // Hai nhóm (Sếp 2026-11-22): trình duyệt ngoài (Chrome / Edge có extension) và trình duyệt tích hợp (Flygo / Ký số,
                // theo máy + công ty, khởi động từ xa được).
                _section(pal, tr('TRÌNH DUYỆT NGOÀI'), tr('Chrome / Edge có extension Flygo Browser Bridge.')),
                for (final b in _list.where((b) => !b.integrated)) _card(pal, b),
                if (!_list.any((b) => !b.integrated) && _error == null) _install(pal),
                _section(pal, tr('TRÌNH DUYỆT TÍCH HỢP'), tr('Trình duyệt Flygo (Ký số) do Flygo Chat quản lý, mỗi công ty một profile. Đang tắt thì bấm Khởi động, kể cả máy khác (Flygo Chat trên máy đó đang chạy).')),
                for (final m in _machines()) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(6, 8, 4, 2), child: Text(m, style: TextStyle(fontWeight: FontWeight.w600, color: pal.sub))),
                  for (final b in _list.where((b) => b.integrated && (b.machineName.isEmpty ? '?' : b.machineName) == m)) _card(pal, b),
                ],
                if (!_list.any((b) => b.integrated)) Padding(padding: const EdgeInsets.all(8), child: Text(tr('Chưa có. Bấm ô Ký số của công ty trên máy tính để Flygo Chat mở trình duyệt tích hợp.'), style: TextStyle(color: pal.sub, fontSize: 13))),
                if (FlygoBrowserHost.supported || widget.debugProfiles != null) _profiles(pal),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 22, 4, 6),
                  child: Text(tr('AGENT NGOÀI (MCP TOKEN)'),
                      style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
                ),
                for (final t in _tokens)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.key_rounded),
                      title: Text('${t['name']}'),
                      subtitle: Text(tr('Hết hạn {0}', [ddmmyyyy(DateTime.fromMillisecondsSinceEpoch((t['expires_at'] as num).toInt()))])),
                      trailing: IconButton(
                          tooltip: tr('Thu hồi'),
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _act(() => MyBrowsers.revokeMcpToken(_token, '${t['id']}'), tr('Đã thu hồi'))),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: _newToken, icon: const Icon(Icons.add_rounded), label: Text(tr('Tạo MCP token'))),
                ),
              ]),
            ),
    );
  }

  List<String> _machines() => {for (final b in _list.where((b) => b.integrated)) b.machineName.isEmpty ? '?' : b.machineName}.toList()..sort();

  Widget _section(Pal pal, String title, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 12, color: pal.sub)),
        ]),
      );

  /// Khởi động trình duyệt tích hợp: máy này thì mở thẳng (màn hình chờ), máy khác thì nhờ Flygo Chat bên đó qua Gateway.
  Future<void> _start(MyBrowser b) async {
    if (b.machineName.toLowerCase() == FlygoMachineClient.machine.toLowerCase()) {
      final ok = await openInFlygoBrowser(context, tax: b.tax.isEmpty ? null : b.tax, profile: b.tax.isEmpty && b.profile.isNotEmpty ? b.profile : null, title: b.name);
      if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Không khởi động được trình duyệt tích hợp'))));
      await _load();
      return;
    }
    await _act(() => MyBrowsers.start(_token, b.id), tr('Đã khởi động {0}', [b.name]));
  }

  /// Profile công ty (space Ký số của tài khoản): mở / xem; thêm, đổi tên, xoá công ty làm ở trang quản trị Ký số.
  Widget _profiles(Pal pal) => FutureBuilder<List<Map<String, dynamic>>>(
        future: widget.debugProfiles != null ? Future.value(widget.debugProfiles) : FlygoBrowserHost.instance.kysoSpaces(),
        builder: (_, snap) {
          final ps = snap.data ?? const [];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section(pal, tr('PROFILE CÔNG TY'), tr('Mỗi công ty (token ký số) là một profile của trình duyệt tích hợp.')),
            for (final p in ps) _ProfileTile(space: p, preview: widget.debugProfiles != null),
            if (snap.connectionState == ConnectionState.done && ps.isEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(tr('Tài khoản chưa có công ty Ký số nào.'), style: TextStyle(color: pal.sub, fontSize: 13))),
            // Thêm / bớt công ty = quyền Ký số do quản trị cấp (Flygo ID), không làm trên máy.
            TextButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Thêm công ty')),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(tr('Thêm công ty')),
                  content: Text(tr('Công ty Ký số do quản trị cấp quyền (token ký số của công ty). Nhờ quản trị thêm bạn vào công ty trong trang quản trị Ký số; công ty sẽ tự hiện ở đây.')),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Đã hiểu')))],
                ),
              ),
            ),
          ]);
        },
      );

  Widget _card(Pal pal, MyBrowser b) {
    final use = b.inUseBy;
    final status = use != null
        ? tr('{0} đang điều khiển', ['${use['agent']}'])
        : b.online
            ? tr('Trực tuyến')
            : tr('Ngoại tuyến · lần cuối {0}', [hhmm(DateTime.fromMillisecondsSinceEpoch(b.lastSeen))]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.public, color: use != null ? const Color(0xFFFF2BD6) : b.online ? pal.accent : pal.sub),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                  if (b.isDefault) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.star_rounded, size: 16, color: pal.accent)),
                ]),
                Text(['@${b.slug}', b.engine, b.os, b.machineName].where((x) => x.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 12.5, color: pal.sub)),
                Text(status, style: TextStyle(fontSize: 12.5, color: use != null ? const Color(0xFFFF2BD6) : pal.sub)),
              ]),
            ),
            // Trình duyệt tích hợp đang tắt: khởi động (máy khác cần Flygo Chat bên đó đang chạy).
            if (b.integrated && !b.online)
              Tooltip(
                message: b.startReady || b.machineName.toLowerCase() == FlygoMachineClient.machine.toLowerCase()
                    ? tr('Khởi động trình duyệt tích hợp')
                    : tr('Flygo Chat trên máy {0} đang tắt', [b.machineName]),
                child: FilledButton.tonal(
                  onPressed: b.startReady || b.machineName.toLowerCase() == FlygoMachineClient.machine.toLowerCase() ? () => _start(b) : null,
                  child: Text(tr('Khởi động')),
                ),
              ),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'rename' => _rename(b),
                'default' => _act(() => MyBrowsers.setPrefs(_token, defaultBrowser: b.id, clearDefault: b.isDefault), b.isDefault ? tr('Đã bỏ mặc định') : tr('Đã đặt mặc định')),
                'stop' => _act(() => MyBrowsers.stop(_token, b.id), tr('Đã dừng agent')),
                'remove' => _remove(b),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(tr('Đổi tên'))),
                PopupMenuItem(value: 'default', child: Text(b.isDefault ? tr('Bỏ mặc định') : tr('Đặt làm mặc định'))),
                if (use != null) PopupMenuItem(value: 'stop', child: Text(tr('Dừng agent ngay'))),
                PopupMenuItem(value: 'remove', child: Text(tr('Gỡ khỏi tài khoản'))),
              ],
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _install(Pal pal) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Cài extension (thủ công)'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                tr('1. Tải tệp zip và giải nén vào một thư mục cố định.\n2. Mở chrome://extensions (Edge: edge://extensions), bật Chế độ nhà phát triển.\n3. Bấm "Tải tiện ích đã giải nén" và chọn thư mục đó.\n4. Mở Flygo Chat trên máy này: extension tự kết nối.'),
                style: TextStyle(fontSize: 13, color: pal.sub, height: 1.5)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('${MyBrowsers.base}/extension.zip'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_rounded),
              label: Text(tr('Tải extension')),
            ),
          ]),
        ),
      );
}

/// Một công ty Ký số: Mở, Đổi tên (tên riêng trên máy này), Xoá dữ liệu đăng nhập trang trên máy này (hỏi trước, kho mật khẩu giữ).
class _ProfileTile extends StatefulWidget {
  const _ProfileTile({required this.space, this.preview = false});
  final Map<String, dynamic> space;
  final bool preview;
  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  Map<String, dynamic>? _info;

  String get _tax => '${widget.space['taxCode'] ?? ''}';
  String get _company => '${widget.space['company'] ?? widget.space['name']}';
  String? get _key => widget.preview ? 'preview' : FlygoBrowserHost.instance.profileFor(_tax)?['key'] as String?;

  @override
  void initState() {
    super.initState();
    if (widget.preview) {
      _info = widget.space['info'] as Map<String, dynamic>?;
    } else {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final k = _key;
    if (k == null) return;
    final i = await FlygoBrowserHost.instance.profileInfo(k);
    if (mounted) setState(() => _info = i);
  }

  static String _size(num b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';

  Future<void> _rename() async {
    final k = _key;
    if (k == null) return;
    final ctl = TextEditingController(text: '${_info?['label'] ?? ''}');
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Đổi tên trên máy này')),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: _company, helperText: tr('Để trống = dùng tên công ty.'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (v == null) return;
    await _run(() => FlygoBrowserHost.instance.profileRename(k, v));
  }

  Future<void> _clear() async {
    final k = _key;
    if (k == null) return;
    final bytes = (_info?['siteDataBytes'] as num?) ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Xoá dữ liệu của {0}?', [_company])),
        content: Text([
          tr('Xoá dữ liệu đăng nhập các trang (cookie) của công ty này trên máy này. Mật khẩu đã lưu trong kho công ty vẫn giữ.'),
          if (bytes > 0) tr('Dung lượng: {0}.', [_size(bytes)]),
          if (_info?['open'] == true) tr('Cửa sổ công ty đang mở sẽ đóng.'),
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Huỷ'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error), onPressed: () => Navigator.pop(c, true), child: Text(tr('Xoá dữ liệu'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => FlygoBrowserHost.instance.profileClear(k));
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Không làm được: {0}', ['$e']))));
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final label = '${_info?['label'] ?? ''}';
    final bytes = (_info?['siteDataBytes'] as num?) ?? 0;
    final local = _key != null;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.business_rounded),
        title: Text(label.isNotEmpty ? label : _company),
        subtitle: Text([
          if (label.isNotEmpty) _company,
          if (_tax.isNotEmpty) 'MST $_tax',
          Uri.tryParse('${widget.space['server']}')?.host ?? '',
          if (_info?['hasSiteData'] == true) tr('dữ liệu trên máy {0}', [_size(bytes)]),
        ].where((x) => x.isNotEmpty).join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: () => openInFlygoBrowser(context, tax: _tax.isEmpty ? null : _tax, title: label.isNotEmpty ? label : _company), child: Text(tr('Mở'))),
          PopupMenuButton<String>(
            enabled: local,
            tooltip: local ? null : tr('Chưa mở công ty này trên máy này'),
            onSelected: (v) => v == 'rename' ? _rename() : _clear(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(tr('Đổi tên trên máy này'))),
              PopupMenuItem(enabled: _info?['hasSiteData'] != false, value: 'clear', child: Text(tr('Xoá dữ liệu trên máy này'))),
            ],
          ),
        ]),
      ),
    );
  }
}
