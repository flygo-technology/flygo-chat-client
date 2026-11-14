// MCP & tiện ích (Trang chủ › Cá nhân): nối nhanh máy chủ MCP bên ngoài (Streamable HTTP) cho các trợ lý của mình.
// App gọi relay POST /a2a/extensions → runner của từng trợ lý ({t:"ext"}); khoá / token chỉ lưu trên máy chạy trợ lý.
// Xác thực: không cần, API key (header), hoặc OAuth2 (runner tạo URL đăng nhập, trình duyệt quay về relay → runner).
// Trợ lý cũng tự đề xuất được (tool mcp_add): tin props.flygo_mcp_add → thẻ duyệt [McpAddCard] + hộp thoại.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'theme.dart';

const _accent = Color(0xFFD97757);

class ExtApi {
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String botId, Map<String, dynamic> body)? debugCall;

  /// Một thao tác MCP trên runner của [botId]; lỗi trả {ok:false, error}.
  static Future<Map<String, dynamic>> call(AppState app, String botId, Map<String, dynamic> body) async {
    if (debugCall != null) return debugCall!(botId, body);
    try {
      final r = await http
          .post(Uri.parse('${pushUrlFor(kServerUrl)}/a2a/extensions'),
              headers: {'Authorization': 'Bearer ${app.token}', 'X-MM-Server': kServerUrl, 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
              body: jsonEncode({'bot_id': botId, ...body}))
          .timeout(const Duration(seconds: 25));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return {'ok': false, 'error': 'HTTP ${r.statusCode}'};
      return {...j.cast<String, dynamic>(), if (r.statusCode != 200 && j['ok'] == null) 'ok': false};
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }
}

/// Header từ ô nhập: "Authorization" + giá trị; giá trị không có "Bearer " / ":" thì coi là token Bearer.
Map<String, String> _secrets(String header, String value) {
  final v = value.trim();
  if (v.isEmpty) return const {};
  final h = header.trim().isEmpty ? 'Authorization' : header.trim();
  return {h: h.toLowerCase() == 'authorization' && !v.contains(' ') ? 'Bearer $v' : v};
}

class McpPage extends StatefulWidget {
  const McpPage({super.key});
  @override
  State<McpPage> createState() => _McpPageState();
}

class _McpPageState extends State<McpPage> {
  /// id trợ lý → danh sách MCP (null = đang tải / offline).
  final Map<String, List<Map<String, dynamic>>?> _lists = {};
  final Map<String, String> _errors = {};
  List<MmUser> _bots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final ids = await app.myBotIds();
    final bots = [for (final id in ids) if (app.users[id] case final u? when app.isAssistant(id)) u]..sort((a, b) => a.username.compareTo(b.username));
    if (!mounted) return;
    setState(() => _bots = bots);
    await Future.wait([
      for (final b in bots)
        ExtApi.call(app, b.id, {'action': 'list'}).then((r) {
          if (!mounted) return;
          setState(() {
            if (r['ok'] == true) {
              _lists[b.id] = [for (final e in (r['list'] as List? ?? const [])) (e as Map).cast<String, dynamic>()];
              _errors.remove(b.id);
            } else {
              _lists[b.id] = null;
              _errors[b.id] = '${r['error'] ?? tr('offline')}';
            }
          });
        }),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  /// Gộp theo id MCP: (mcp, các trợ lý có nó).
  List<(Map<String, dynamic>, List<MmUser>)> get _merged {
    final byId = <String, (Map<String, dynamic>, List<MmUser>)>{};
    for (final b in _bots) {
      for (final e in _lists[b.id] ?? const <Map<String, dynamic>>[]) {
        final id = e['id'] as String;
        byId.putIfAbsent(id, () => (e, <MmUser>[])).$2.add(b);
      }
    }
    return byId.values.toList();
  }

  Future<void> _each(List<MmUser> bots, Map<String, dynamic> body) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    for (final b in bots) {
      final r = await ExtApi.call(app, b.id, body);
      if (r['ok'] != true) messenger.showSnackBar(toast(Text('@${b.username}: ${r['error'] ?? tr('lỗi')}')));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final merged = _merged;
    final list = ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text(tr('Nối máy chủ MCP bên ngoài (Streamable HTTP) cho các trợ lý của bạn. Khoá / token chỉ lưu trên máy chạy trợ lý, không lưu trên máy chủ chat. Mỗi lần trợ lý dùng công cụ của MCP vẫn hỏi bạn duyệt.'),
          style: TextStyle(fontSize: 13.5, height: 1.4, color: pal.sub)),
      const SizedBox(height: 14),
      Row(children: [
        Text(tr('ĐÃ NỐI ({0})', [merged.length]), style: TextStyle(fontSize: 12, letterSpacing: .6, fontWeight: FontWeight.w700, color: pal.sub)),
        const Spacer(),
        if (_loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 8),
      if (!_loading && merged.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('Chưa nối MCP nào.'), style: TextStyle(color: pal.sub))),
      for (final (e, bots) in merged) Padding(padding: const EdgeInsets.only(bottom: 10), child: _item(pal, e, bots)),
      for (final b in _bots)
        if (_errors[b.id] case final err?)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(tr('@{0} không trả lời ({1}); trợ lý cần chạy runner bản mới và đang mở máy.', [b.username, err]),
                style: TextStyle(fontSize: 12, color: pal.sub)),
          ),
      const SizedBox(height: 6),
      Material(
        color: _accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _bots.isEmpty ? null : () => _add(context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.add_link_rounded, color: _accent),
              const SizedBox(width: 10),
              Text(tr('Nối MCP mới (dán URL)'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _accent)),
            ]),
          ),
        ),
      ),
    ]);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        foregroundColor: pal.text,
        elevation: 0,
        title: Text(tr('MCP & tiện ích')),
        actions: [IconButton(tooltip: tr('Tải lại'), icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: wide ? 760 : double.infinity), child: list)),
    );
  }

  Widget _item(Pal pal, Map<String, dynamic> e, List<MmUser> bots) {
    final on = bots.isNotEmpty && (_lists[bots.first.id]?.firstWhere((x) => x['id'] == e['id'])['enabled'] == true);
    final auth = e['auth'] as String? ?? 'none';
    final connected = e['connected'] != false;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(pal.text.withValues(alpha: .035), pal.bg),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.text.withValues(alpha: .09)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: _accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.extension_outlined, color: _accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e['name'] as String? ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text)),
            Text(e['url'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip(pal, switch (auth) { 'oauth' => connected ? tr('OAuth2 · đã đăng nhập') : tr('OAuth2 · chưa đăng nhập'), 'key' => tr('API key'), _ => tr('Không cần xác thực') },
                  auth == 'oauth' && !connected ? Icons.warning_amber_rounded : Icons.lock_outline_rounded),
              for (final b in bots) _chip(pal, '@${b.username}', Icons.smart_toy_outlined),
              if (e['added_by'] == 'agent') _chip(pal, tr('trợ lý đề xuất'), Icons.auto_awesome_outlined),
            ]),
          ]),
        ),
        Switch(value: on, activeTrackColor: _accent, onChanged: (v) => _each(bots, {'action': v ? 'enable' : 'disable', 'ext': {'id': e['id']}})),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: pal.sub),
          onSelected: (a) => a == 'remove'
              ? _each(bots, {'action': 'remove', 'ext': {'id': e['id']}})
              : _add(context, preset: e),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Text(tr('Sửa / thêm cho trợ lý khác'))),
            PopupMenuItem(value: 'remove', child: Text(tr('Gỡ'), style: const TextStyle(color: Colors.redAccent))),
          ],
        ),
      ]),
    );
  }

  Widget _chip(Pal pal, String t, IconData i) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: pal.sub),
          const SizedBox(width: 4),
          Text(t, style: TextStyle(fontSize: 12, color: pal.sub)),
        ]),
      );

  Future<void> _add(BuildContext context, {Map<String, dynamic>? preset}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => McpConnectDialog(bots: _bots, preset: preset));
    if (ok == true) await _load();
  }
}

/// Hộp "Nối MCP": URL, tên, khoá (tuỳ chọn), thử kết nối (liệt kê tool), chọn trợ lý; OAuth2 thì nút Đăng nhập.
/// [request]: đề xuất của trợ lý (tool mcp_add) — chỉ một trợ lý, URL / tên cố định, thêm nút Từ chối.
class McpConnectDialog extends StatefulWidget {
  final List<MmUser> bots;
  final Map<String, dynamic>? preset;
  final Map<String, dynamic>? request;
  const McpConnectDialog({super.key, required this.bots, this.preset, this.request});
  @override
  State<McpConnectDialog> createState() => _McpConnectDialogState();
}

class _McpConnectDialogState extends State<McpConnectDialog> {
  late final _url = TextEditingController(text: widget.request?['url'] as String? ?? widget.preset?['url'] as String? ?? '');
  late final _name = TextEditingController(text: widget.request?['name'] as String? ?? widget.preset?['name'] as String? ?? '');
  final _header = TextEditingController(text: 'Authorization');
  final _key = TextEditingController();
  late final Set<String> _picked = {for (final b in widget.bots) b.id};
  Map<String, dynamic>? _test;
  late String? _auth = widget.request?['auth'] as String?;
  bool _busy = false;
  String? _err;
  bool _waitingOauth = false;

  Map<String, String> get _secretMap => _secrets(_header.text, _key.text);

  Future<void> _runTest() async {
    final app = context.read<AppState>();
    setState(() { _busy = true; _err = null; _test = null; });
    final r = await ExtApi.call(app, _picked.firstOrNull ?? widget.bots.first.id, {'action': 'test', 'ext': {'url': _url.text.trim()}, 'secrets': _secretMap});
    if (!mounted) return;
    setState(() {
      _busy = false;
      _test = r;
      _auth = r['auth'] as String? ?? _auth;
      if (r['ok'] == true && _name.text.trim().isEmpty && r['server_name'] is String) _name.text = r['server_name'] as String;
      if (r['ok'] != true) _err = '${r['error'] ?? tr('không kết nối được')}';
    });
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    setState(() { _busy = true; _err = null; });
    final req = widget.request;
    final targets = req != null ? [req['bot_id'] as String] : _picked.toList();
    for (final id in targets) {
      final r = await ExtApi.call(
          app,
          id,
          req != null
              ? {'action': 'request_approve', 'req_id': req['req_id'], 'secrets': _secretMap}
              : {'action': 'install', 'ext': {'id': widget.preset?['id'], 'name': _name.text.trim(), 'url': _url.text.trim()}, 'secrets': _secretMap});
      if (r['ok'] != true) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _err = '${r['error'] ?? tr('lỗi')}';
          if (r['need_oauth'] == true) _auth = 'oauth';
        });
        return;
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  /// OAuth2: runner của từng trợ lý tạo URL đăng nhập; mở trình duyệt, đăng nhập xong trang trả về báo "Đã kết nối".
  Future<void> _oauth() async {
    final app = context.read<AppState>();
    setState(() { _busy = true; _err = null; });
    final req = widget.request;
    final targets = req != null ? [req['bot_id'] as String] : _picked.toList();
    for (final id in targets) {
      final r = await ExtApi.call(app, id, {
        'action': 'oauth_start',
        if (req != null) 'req_id': req['req_id'] else 'ext': {'id': widget.preset?['id'], 'name': _name.text.trim(), 'url': _url.text.trim()},
      });
      if (r['ok'] != true || r['auth_url'] is! String) {
        if (mounted) setState(() { _busy = false; _err = '${r['error'] ?? tr('không bắt đầu đăng nhập được')}'; });
        return;
      }
      await launchUrl(Uri.parse(r['auth_url'] as String), mode: LaunchMode.externalApplication);
    }
    if (mounted) setState(() { _busy = false; _waitingOauth = true; });
  }

  Future<void> _reject() async {
    final req = widget.request!;
    await ExtApi.call(context.read<AppState>(), req['bot_id'] as String, {'action': 'request_reject', 'req_id': req['req_id']});
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final req = widget.request;
    final app = context.read<AppState>();
    final tools = [for (final t in (_test?['tools'] as List? ?? const [])) '${(t as Map)['name']}'];
    final authLabel = switch (_auth) { 'oauth' => tr('OAuth2 (đăng nhập)'), 'key' => tr('API key / token'), 'none' => tr('Không cần xác thực'), _ => tr('Chưa rõ, bấm Thử kết nối') };
    return AlertDialog(
      icon: const Icon(Icons.extension_outlined, color: _accent, size: 30),
      title: Text(req != null ? tr('Trợ lý muốn thêm MCP') : tr('Nối MCP')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (req != null) ...[
              Text(tr('@{0} đề xuất nối "{1}".', [app.users[req['bot_id']]?.username ?? '', req['name'] ?? '']),
                  style: TextStyle(fontSize: 14, color: pal.text, fontWeight: FontWeight.w600)),
              if ((req['reason'] as String? ?? '').isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('${req['reason']}', style: TextStyle(fontSize: 13, color: pal.sub))),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _url,
              readOnly: req != null,
              onChanged: (_) => setState(() => _test = null),
              decoration: const InputDecoration(labelText: 'URL (Streamable HTTP)', hintText: 'https://mcp.example.com/mcp', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(controller: _name, readOnly: req != null, decoration: InputDecoration(labelText: tr('Tên'), isDense: true)),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: pal.sub),
              const SizedBox(width: 6),
              Text(tr('Xác thực: {0}', [authLabel]), style: TextStyle(fontSize: 13, color: pal.text)),
            ]),
            if (_auth != 'oauth' && _auth != 'none') ...[
              const SizedBox(height: 6),
              Row(children: [
                SizedBox(width: 130, child: TextField(controller: _header, decoration: InputDecoration(labelText: tr('Header'), isDense: true))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _key, obscureText: true, decoration: InputDecoration(labelText: tr('Khoá / token (tuỳ chọn)'), isDense: true))),
              ]),
            ],
            if (req == null && widget.bots.length > 1) ...[
              const SizedBox(height: 12),
              Text(tr('Dùng cho trợ lý'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.sub)),
              Wrap(spacing: 6, children: [
                for (final b in widget.bots)
                  FilterChip(
                    label: Text('@${b.username}'),
                    selected: _picked.contains(b.id),
                    onSelected: (v) => setState(() => v ? _picked.add(b.id) : _picked.remove(b.id)),
                  ),
              ]),
            ],
            if (_test?['ok'] == true) ...[
              const SizedBox(height: 10),
              Text(tr('✅ Kết nối được · {0} công cụ', [tools.length]), style: const TextStyle(fontSize: 13, color: Color(0xFF2E9D5B), fontWeight: FontWeight.w600)),
              if (tools.isNotEmpty) Text(tools.take(12).join(', '), style: TextStyle(fontSize: 12, color: pal.sub)),
            ],
            if (_waitingOauth)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(tr('Đăng nhập trong trình duyệt; xong trang sẽ báo "Đã kết nối". Bấm Xong để tải lại danh sách.'),
                    style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(fontSize: 12.5, color: Colors.redAccent))),
          ]),
        ),
      ),
      actions: [
        if (req != null) TextButton(onPressed: _busy ? null : _reject, child: Text(tr('Từ chối'), style: const TextStyle(color: Colors.redAccent)))
        else TextButton(onPressed: () => Navigator.pop(context, _waitingOauth), child: Text(_waitingOauth ? tr('Xong') : tr('Huỷ'))),
        if (req == null) TextButton(onPressed: _busy || _url.text.trim().isEmpty ? null : _runTest, child: Text(tr('Thử kết nối'))),
        if (_auth == 'oauth')
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: _busy ? null : _oauth,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: Text(tr('Đăng nhập')),
          )
        else
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: _busy || (req == null && (_picked.isEmpty || _url.text.trim().isEmpty)) ? null : _save,
            child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(tr('Thêm')),
          ),
      ],
    );
  }
}

/// Thẻ trong chat khi trợ lý đề xuất thêm MCP (props.flygo_mcp_add). Chủ trợ lý bấm "Xem / duyệt" để mở hộp thoại.
class McpAddCard extends StatefulWidget {
  final MmPost post;
  const McpAddCard({super.key, required this.post});

  /// Đề xuất đã tự mở hộp thoại (mỗi đề xuất một lần trong phiên chạy app).
  static final _shown = <String>{};

  @override
  State<McpAddCard> createState() => _McpAddCardState();
}

class _McpAddCardState extends State<McpAddCard> {
  Map<String, dynamic> get _req => (widget.post.props['flygo_mcp_add'] as Map).cast<String, dynamic>();

  bool _mine(AppState app) => app.isMyBot(widget.post.userId) || widget.post.props['flygo_agent_owner'] == app.me?.id;

  @override
  void initState() {
    super.initState();
    // Đề xuất mới (≤ 10 phút) đang chờ: tự bật hộp thoại cho chủ trợ lý.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      final fresh = DateTime.now().millisecondsSinceEpoch - widget.post.createAt < 10 * 60 * 1000;
      if (mounted && fresh && _req['status'] == 'pending' && _mine(app) && McpAddCard._shown.add('${_req['req_id']}')) _open();
    });
  }

  Future<void> _open() async {
    final app = context.read<AppState>();
    final bot = app.users[_req['bot_id']];
    await showDialog<bool>(context: context, builder: (_) => McpConnectDialog(bots: [?bot], request: _req));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final st = _req['status'] as String? ?? 'pending';
    final (label, color) = switch (st) {
      'added' => (tr('Đã thêm'), const Color(0xFF2E9D5B)),
      'rejected' => (tr('Đã từ chối'), Colors.redAccent),
      'expired' => (tr('Hết hạn'), pal.sub),
      _ => (tr('Chờ duyệt'), _accent),
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _accent.withValues(alpha: .07), borderRadius: BorderRadius.circular(14), border: Border.all(color: _accent.withValues(alpha: .3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.extension_outlined, color: _accent, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Thêm MCP "{0}"', [_req['name'] ?? '']), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text))),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 4),
        Text('${_req['url'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub)),
        Text(
            switch (_req['auth']) { 'oauth' => tr('Xác thực: OAuth2'), 'key' => tr('Xác thực: API key'), _ => tr('Không cần xác thực') } +
                (_req['tools'] is num ? ' · ${tr('{0} công cụ', [_req['tools']])}' : ''),
            style: TextStyle(fontSize: 12.5, color: pal.sub)),
        if (st == 'pending' && _mine(app)) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _accent, visualDensity: VisualDensity.compact),
            onPressed: _open,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text(tr('Xem và duyệt')),
          ),
        ],
      ]),
    );
  }
}
