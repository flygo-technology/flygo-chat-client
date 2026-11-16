import '../i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../browser/my_browsers.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'devices_page.dart' show confirmCountdown;
import 'theme.dart';

/// Cài đặt › Trình duyệt của tôi: các trình duyệt (extension Flygo Browser Bridge) đã nối với tài khoản, để agent của mình
/// điều khiển (tag @trình-duyệt khi chat với agent). Bật/tắt cho cả tài khoản, đổi tên, mặc định, dừng agent, gỡ;
/// MCP token cho agent ngoài (Claude Code, Codex, Cursor…).
class MyBrowsersPage extends StatefulWidget {
  const MyBrowsersPage({super.key});
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
                for (final b in _list) _card(pal, b),
                if (_list.isEmpty && _error == null) _install(pal),
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
