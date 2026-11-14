import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/image_disk_cache.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'ai_panel.dart';
import 'app_route.dart';
import 'chat_page.dart' show openFile;
import 'chat_info_page.dart' show ChannelMediaPage;
import 'common.dart';
import 'media_view.dart';
import 'theme.dart';

// Cột phải của chat với trợ lý (máy tính) / trang mở từ ⋮ (điện thoại):
// mọi thao tác của ⋮ (kể cả Kết nối agent từ xa), các phiên, ảnh / tệp / liên kết gần đây.

/// Tin do agent ngoài gửi qua Token MCP (trạm đẩy gắn props.flygo_bridge).
bool isBridgedPost(MmPost p) => p.props['flygo_bridge'] is Map;

// ---------------------------------------------------------------- Token MCP (trạm đẩy /bridge/tokens)

/// Một token MCP của phiên (không có phần bí mật).
class BridgeToken {
  final String id;
  final DateTime created, expires;
  final DateTime? lastUsed;
  final int sends, reads;
  const BridgeToken(this.id, this.created, this.expires, this.lastUsed, this.sends, this.reads);
  static DateTime _t(Object? v) => DateTime.fromMillisecondsSinceEpoch(v is num ? v.toInt() : 0);
  factory BridgeToken.fromJson(Map j) => BridgeToken(
    j['token_id'] as String? ?? '',
    _t(j['created_at']),
    _t(j['expires_at']),
    (j['last_used_at'] as num? ?? 0) > 0 ? _t(j['last_used_at']) : null,
    (j['sends'] as num?)?.toInt() ?? 0,
    (j['reads'] as num?)?.toInt() ?? 0,
  );
}

/// Token vừa tạo: liên kết mời chỉ hiện một lần.
class BridgeInvite {
  final String tokenId, invite, mcpUrl, token;
  final DateTime expires;
  const BridgeInvite(this.tokenId, this.invite, this.mcpUrl, this.token, this.expires);
}

class BridgeApi {
  /// Chỉ cho kiểm thử: client giả.
  @visibleForTesting
  static http.Client? debugClient;

  /// Trả về JSON của trạm (danh sách token là một mảng, các lệnh khác là object).
  static Future<dynamic> _call(AppState app, String method, String path, [Map<String, dynamic>? body]) async {
    final c = debugClient ?? http.Client();
    final req = http.Request(method, Uri.parse('${pushUrlFor(kServerUrl)}/bridge/$path'))
      ..headers.addAll({'Authorization': 'Bearer ${app.token}', 'X-MM-Server': kServerUrl, 'Content-Type': 'application/json', 'User-Agent': kUserAgent});
    if (body != null) req.body = jsonEncode(body);
    final r = await http.Response.fromStream(await c.send(req).timeout(const Duration(seconds: 15)));
    final j = r.body.isEmpty ? const <String, dynamic>{} : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) throw Exception((j is Map ? j['error'] : null) ?? 'bridge ${r.statusCode}');
    return j;
  }

  static Future<List<BridgeToken>> list(AppState app, String channelId) async {
    final j = await _call(app, 'GET', 'tokens?channel_id=$channelId');
    final rows = j is List ? j : (j is Map ? j['tokens'] as List? : null) ?? const [];
    return [
      for (final t in rows)
        if (t is Map && t['revoked'] != true) BridgeToken.fromJson(t),
    ]..removeWhere((t) => t.expires.isBefore(DateTime.now()));
  }

  static Future<BridgeInvite> create(AppState app, String channelId, Duration ttl) async {
    final j = (await _call(app, 'POST', 'tokens', {'channel_id': channelId, 'ttl_sec': ttl.inSeconds}) as Map).cast<String, dynamic>();
    return BridgeInvite(
      j['token_id'] as String,
      j['invite_url'] as String? ?? '',
      j['mcp_url'] as String? ?? '',
      j['token'] as String? ?? '',
      DateTime.fromMillisecondsSinceEpoch((j['expires_at'] as num).toInt()),
    );
  }

  static Future<void> revoke(AppState app, String tokenId) => _call(app, 'DELETE', 'tokens/$tokenId');
}

// ---------------------------------------------------------------- Cột phải

class AgentSidePanel extends StatefulWidget {
  final String channelId;

  /// Các thao tác của ⋮ (giá trị, biểu tượng, nhãn) — chat_page cung cấp, bấm thì gọi [onAction].
  final List<(String, IconData, String)> actions;
  final Future<void> Function(String action) onAction;

  /// Trang riêng (điện thoại): có nút quay lại. Cột (máy tính): có nút đóng cột.
  final bool asPage;
  final VoidCallback? onClose;

  /// Mở một phiên khác (mặc định onAction('open:' + id)).
  final void Function(String channelId)? onOpenSession;
  const AgentSidePanel({
    super.key,
    required this.channelId,
    required this.actions,
    required this.onAction,
    this.asPage = false,
    this.onClose,
    this.onOpenSession,
  });

  /// Chỉ cho kiểm thử / ảnh xem trước: tin thay cho lần quét kênh.
  @visibleForTesting
  static List<MmPost>? debugScan;

  /// Chỉ cho ảnh xem trước: ô ảnh thay cho ảnh tải từ máy chủ.
  @visibleForTesting
  static Widget Function(MmFile f)? debugThumb;

  @override
  State<AgentSidePanel> createState() => _AgentSidePanelState();
}

class _AgentSidePanelState extends State<AgentSidePanel> {
  List<MmPost>? _scan;
  bool _allSessions = false;
  static final _url = RegExp(r'https?://[^\s<>()\]]+');

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    if (AgentSidePanel.debugScan != null) {
      _scan = AgentSidePanel.debugScan;
    } else {
      app
          .scanChannel(widget.channelId, pages: 1)
          .then((p) {
            if (mounted) setState(() => _scan = p);
          })
          .catchError((_) {
            if (mounted) setState(() => _scan = const []);
          });
    }
  }

  void _openMedia(String kind) => Navigator.of(context).push(
    AppPageRoute(
      builder: (_) => ChannelMediaPage(channelId: widget.channelId, kind: kind),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final ch = app.channels[widget.channelId];
    if (ch == null) return const SizedBox.shrink();
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        _section(pal, Icons.tune_rounded, tr('Thao tác'), null),
        _card(
          pal,
          Column(
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(Icons.hub_outlined, size: 20, color: pal.text.withValues(alpha: .75)),
                title: Text(tr('Kết nối agent từ xa'), style: TextStyle(fontSize: 14.5, color: pal.text)),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => RemoteAgentDialog(channelId: ch.id),
                ),
              ),
              // Phiên / Phiên mới đã có ở mục Phiên bên dưới.
              for (final (v, icon, label) in widget.actions.where((a) => !(ch.isAi && ch.aiGroup != null && (a.$1 == 'switch' || a.$1 == 'new'))))
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(icon, size: 20, color: v == 'delete' ? const Color(0xFFD32F2F) : pal.text.withValues(alpha: .75)),
                  title: Text(label, style: TextStyle(fontSize: 14.5, color: v == 'delete' ? const Color(0xFFD32F2F) : pal.text)),
                  onTap: () => widget.onAction(v),
                ),
            ],
          ),
        ),
        if (ch.isAi && ch.aiGroup != null) ..._sessions(app, ch, pal),
        ..._media(app, pal),
      ],
    );
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Row(
        children: [
          if (widget.asPage)
            IconButton(
              icon: Icon(Icons.arrow_back, color: pal.text),
              onPressed: () => Navigator.maybePop(context),
            ),
          if (!widget.asPage) const SizedBox(width: 8),
          Expanded(
            child: Text(
              ch.isAi ? aiSessionLabel(ch) : app.channelTitle(ch),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: pal.text),
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: tr('Ẩn cột'),
              icon: Icon(Icons.keyboard_double_arrow_right_rounded, color: pal.sub),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
    final body = Column(
      children: [
        head,
        Expanded(child: list),
      ],
    );
    if (widget.asPage) return Scaffold(backgroundColor: pal.bg, body: SafeArea(child: body));
    return Material(color: pal.bg, child: body);
  }

  Widget _section(Pal pal, IconData icon, String title, Widget? trailing) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 16, 4, 6),
    child: Row(
      children: [
        Icon(icon, size: 16, color: pal.sub),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .3, color: pal.sub),
          ),
        ),
        ?trailing,
      ],
    ),
  );

  Widget _card(Pal pal, Widget child) => Material(
    color: Color.alphaBlend(pal.text.withValues(alpha: .035), pal.bg),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: pal.text.withValues(alpha: .07)),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  Widget _more(Pal pal, String label, VoidCallback onTap) => TextButton(
    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
    onPressed: onTap,
    child: Text(
      label,
      style: TextStyle(fontSize: 12.5, color: pal.accentText, fontWeight: FontWeight.w600),
    ),
  );

  List<Widget> _sessions(AppState app, MmChannel ch, Pal pal) {
    final all = app.aiChannelsFor(ch.aiGroup!, thread: ch.aiThread); // mới nhất trước
    final shown = _allSessions ? all : all.take(5).toList();
    return [
      _section(
        pal,
        Icons.view_list_outlined,
        tr('Phiên'),
        all.length > 5 ? _more(pal, _allSessions ? tr('Thu gọn') : tr('Tất cả ({0})', [all.length]), () => setState(() => _allSessions = !_allSessions)) : null,
      ),
      _card(
        pal,
        Column(
          children: [
            for (final c in shown)
              AiSessionTile(
                channel: c,
                selected: c.id == ch.id,
                compact: true,
                onTap: () => c.id == ch.id ? null : (widget.onOpenSession ?? (id) => widget.onAction('open:$id'))(c.id),
              ),
            ListTile(
              dense: true,
              leading: Icon(Icons.add_comment_outlined, size: 20, color: pal.accentText),
              title: Text(
                tr('Phiên mới'),
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: pal.accentText),
              ),
              onTap: () => widget.onAction('new'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _media(AppState app, Pal pal) {
    final posts = _scan;
    final images = <(MmPost, MmFile)>[], files = <(MmPost, MmFile)>[], links = <(MmPost, String)>[];
    final seen = <String>{};
    for (final p in posts ?? const <MmPost>[]) {
      for (final f in p.files) {
        (f.isImage ? images : files).add((p, f));
      }
      for (final m in _url.allMatches(p.message)) {
        if (seen.add(m.group(0)!)) links.add((p, m.group(0)!));
      }
    }
    Widget loading() => Padding(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent)),
      ),
    );
    Widget empty(String t) => Padding(
      padding: const EdgeInsets.all(14),
      child: Text(t, style: TextStyle(fontSize: 13, color: pal.sub)),
    );
    String when(MmPost p) => listTime(p.createAt);
    return [
      _section(pal, Icons.photo_outlined, tr('Ảnh'), images.isEmpty ? null : _more(pal, tr('Xem tất cả'), () => _openMedia('images'))),
      _card(
        pal,
        posts == null
            ? loading()
            : images.isEmpty
            ? empty(tr('Chưa có hình ảnh'))
            : Padding(
                padding: const EdgeInsets.all(6),
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final (p, f) in images.take(8))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GestureDetector(
                          onTap: () => showGallery(context, p, [ChatImage(file: f)], 0),
                          child:
                              AgentSidePanel.debugThumb?.call(f) ??
                              Image(
                                image: DiskCachedImage.network(chatImageKey(f.id, 'thumb'), app.api.thumbUrl(f.id), headers: app.api.headers),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: pal.text.withValues(alpha: .08),
                                  child: Icon(Icons.image_outlined, color: pal.sub),
                                ),
                              ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      _section(pal, Icons.insert_drive_file_outlined, tr('Tệp'), files.isEmpty ? null : _more(pal, tr('Xem tất cả'), () => _openMedia('files'))),
      _card(
        pal,
        posts == null
            ? loading()
            : files.isEmpty
            ? empty(tr('Chưa có tệp tin'))
            : Column(
                children: [
                  for (final (p, f) in files.take(3))
                    ListTile(
                      dense: true,
                      leading: Icon(f.isVideo ? Icons.videocam_outlined : Icons.description_outlined, color: pal.accentText),
                      title: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: pal.text),
                      ),
                      subtitle: Text('${fileSize(f.size)} · ${when(p)}', style: TextStyle(fontSize: 12, color: pal.sub)),
                      onTap: () => openFile(context, f),
                    ),
                ],
              ),
      ),
      _section(pal, Icons.link_rounded, tr('Liên kết'), links.isEmpty ? null : _more(pal, tr('Xem tất cả'), () => _openMedia('links'))),
      _card(
        pal,
        posts == null
            ? loading()
            : links.isEmpty
            ? empty(tr('Chưa có liên kết'))
            : Column(
                children: [
                  for (final (_, u) in links.take(3))
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.link_rounded, color: pal.accentText),
                      title: Text(
                        Uri.tryParse(u)?.host ?? u,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: pal.text),
                      ),
                      subtitle: Text(
                        u,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: pal.sub),
                      ),
                      onTap: () => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
                    ),
                ],
              ),
      ),
    ];
  }
}

/// "Kết nối agent từ xa": tạo liên kết mời (hiện đúng một lần, sao chép bằng một nút), xem và thu hồi các liên kết
/// còn hạn của phiên. Agent ngoài (Claude Code, Claude Desktop, Codex…) mở liên kết là có đủ hướng dẫn để vào phiên.
class RemoteAgentDialog extends StatefulWidget {
  final String channelId;

  /// Chỉ cho ảnh xem trước: liên kết vừa tạo.
  final BridgeInvite? debugInvite;
  const RemoteAgentDialog({super.key, required this.channelId, this.debugInvite});
  @override
  State<RemoteAgentDialog> createState() => _RemoteAgentDialogState();
}

class _RemoteAgentDialogState extends State<RemoteAgentDialog> {
  List<BridgeToken>? _tokens;
  String? _err;
  bool _creating = false;
  Duration _ttl = const Duration(hours: 24);
  late BridgeInvite? _invite = widget.debugInvite;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await BridgeApi.list(context.read<AppState>(), widget.channelId);
      if (mounted) setState(() => _tokens = t);
    } catch (e) {
      if (mounted) {
        setState(() {
          _tokens = const [];
          _err = _msg(e);
        });
      }
    }
  }

  static String _msg(Object e) => '$e'.replaceFirst('Exception: ', '');

  static String _fmt(DateTime t) {
    final now = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) return hm;
    return '$hm ${t.day}/${t.month}';
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _err = null;
    });
    try {
      final inv = await BridgeApi.create(context.read<AppState>(), widget.channelId, _ttl);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _invite = inv;
        _copied = false;
      });
      _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _err = _msg(e);
        });
      }
    }
  }

  Future<void> _revoke(BridgeToken t) async {
    try {
      await BridgeApi.revoke(context.read<AppState>(), t.id);
      if (_invite?.tokenId == t.id) _invite = null;
    } catch (e) {
      if (mounted) setState(() => _err = _msg(e));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final inv = _invite;
    final tokens = _tokens;
    return AlertDialog(
      icon: Icon(Icons.hub_outlined, color: pal.accentText, size: 30),
      title: Text(tr('Kết nối agent từ xa')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'Tạo liên kết mời rồi gửi cho agent khác (Claude Code, Claude Desktop, Codex…). Trong liên kết có đủ hướng dẫn để agent tự kết nối và trao đổi với trợ lý của phiên này. Trợ lý trả lời như bạn hỏi; lệnh ghi vẫn chờ bạn duyệt.',
                ),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: pal.text),
              ),
              const SizedBox(height: 14),
              if (inv == null) ...[
                Text(
                  tr('Liên kết dùng được trong'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.sub),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (d, l) in [
                      (const Duration(hours: 1), tr('1 giờ')),
                      (const Duration(hours: 24), tr('24 giờ')),
                      (const Duration(days: 7), tr('7 ngày')),
                    ])
                      ChoiceChip(label: Text(l), selected: _ttl == d, onSelected: (_) => setState(() => _ttl = d)),
                  ],
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(10)),
                  child: SelectableText(
                    inv.invite,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: pal.text, height: 1.35),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFE8A317)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('Chỉ hiện một lần. Ai có liên kết là nói chuyện được với trợ lý thay bạn, tới {0}. Thu hồi được bất cứ lúc nào.', [
                          '${_fmt(inv.expires)}/${inv.expires.year}',
                        ]),
                        style: TextStyle(fontSize: 12, height: 1.35, color: pal.sub),
                      ),
                    ),
                  ],
                ),
              ],
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_err!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
              if (tokens != null && tokens.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  tr('Liên kết còn hạn'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.sub),
                ),
                for (final t in tokens)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.key_rounded, size: 16, color: Color(0xFF2E9D5B)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Hết hạn {0}', [_fmt(t.expires)]),
                                style: TextStyle(fontSize: 13, color: pal.text, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                t.lastUsed == null ? tr('Chưa dùng') : tr('Dùng lúc {0} · {1} tin gửi', [_fmt(t.lastUsed!), t.sends]),
                                style: TextStyle(fontSize: 12, color: pal.sub),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: Colors.redAccent, visualDensity: VisualDensity.compact),
                          onPressed: () => _revoke(t),
                          child: Text(tr('Thu hồi')),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(inv == null ? tr('Đóng') : tr('Xong'))),
        if (inv == null)
          FilledButton.icon(
            onPressed: _creating ? null : _create,
            icon: _creating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_link_rounded, size: 18),
            label: Text(tr('Tạo liên kết mời')),
          )
        else
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: inv.invite));
              if (mounted) setState(() => _copied = true);
            },
            icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
            label: Text(_copied ? tr('Đã sao chép') : tr('Sao chép liên kết mời')),
          ),
      ],
    );
  }
}
