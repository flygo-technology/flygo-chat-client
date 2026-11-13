import '../i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'ai_panel.dart' show aiSessionLabel;
import 'common.dart';
import 'theme.dart';

/// Một trợ lý trong tab "Trợ lý" của trang chuyển tiếp: chat chính (1-1, có thể chưa có) và các phiên của mình với
/// trợ lý đó (phiên của "Chung", của dự án hoặc của cuộc trò chuyện thường), phiên mới nhất trước.
class ForwardAgentGroup {
  final MmUser bot;
  final MmChannel? dm;
  final List<MmChannel> sessions;
  const ForwardAgentGroup(this.bot, this.dm, this.sessions);
}

/// Mã đích "chat chính với trợ lý" khi chưa có kênh 1-1 (mở kênh lúc gửi).
const _dmPrefix = 'dm:';

/// Gom các trợ lý mình được dùng và phiên của mình với từng trợ lý ([mine] = id các bot của mình).
List<ForwardAgentGroup> forwardAgentGroups(AppState app, Set<String> mine) {
  final me = app.me?.id;
  final bots = app.users.values.where((u) => u.isBot && u.deleteAt == 0 && app.isAssistant(u.id) && app.canCallBot(u, mine)).toList()
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  final dms = <String, MmChannel>{};
  final sessions = <String, List<MmChannel>>{};
  for (final c in app.channels.values) {
    if (c.deleteAt != 0 || me == null) continue;
    if (c.isDirect) {
      final o = c.otherUserId(me);
      if (o != null) dms[o] = c;
      continue;
    }
    if (!c.isAi || c.aiOwner != me || c.aiArchived) continue;
    // Trợ lý của phiên: bên kia của chat 1-1 gốc, hoặc thành viên bot đã biết.
    final g = app.channels[c.aiGroup];
    String? bot = g != null && g.isDirect ? g.otherUserId(me) : null;
    bot ??= (app.knownMemberIds(c.id) ?? const <String>[]).where((id) => app.users[id]?.isBot == true && app.isAssistant(id)).firstOrNull;
    if (bot != null) (sessions[bot] ??= []).add(c);
  }
  int at(MmChannel c) => app.latest[c.id]?.createAt ?? (c.lastPostAt > 0 ? c.lastPostAt : c.createAt);
  return [
    for (final b in bots) ForwardAgentGroup(b, dms[b.id], (sessions[b.id] ?? [])..sort((x, y) => at(y).compareTo(at(x)))),
  ];
}

/// Chọn các cuộc trò chuyện để chuyển tiếp tin nhắn (tối đa 5, giống WhatsApp). Hai tab: "Chat" (nhóm, kênh, chat với
/// người) và "Trợ lý" (mỗi trợ lý một mục thu gọn được: chat chính + các phiên / dự án; trạng thái mở lưu trên máy).
class ForwardPage extends StatefulWidget {
  /// Chuyển tiếp cả tin ([post], hoặc nhiều tin [posts] theo thứ tự); hoặc chỉ một số ảnh/tệp ([files] trên máy chủ,
  /// [localPaths] trên máy).
  final MmPost? post;
  final List<MmPost> posts;
  final List<MmFile> files;
  final List<String> localPaths;

  /// Nhận chia sẻ từ app khác ("Gửi tới…"): có ô chú thích (điền sẵn [sharedText]), gửi như tin thường, không gắn
  /// nhãn "Chuyển tiếp". Không có tệp thì gửi [sharedText] (chữ / đường link được chia sẻ).
  final bool shared;
  final String sharedText;
  const ForwardPage({super.key, this.post, this.posts = const [], this.files = const [], this.localPaths = const []})
      : shared = false,
        sharedText = '';

  /// Màn "Gửi tới…" cho tệp / chữ nhận từ app khác.
  const ForwardPage.share({super.key, this.localPaths = const [], this.sharedText = ''})
      : post = null,
        posts = const [],
        files = const [],
        shared = true;
  @override
  State<ForwardPage> createState() => _ForwardPageState();
}

class _ForwardPageState extends State<ForwardPage> with SingleTickerProviderStateMixin {
  static const _prefKey = 'forward_agents_expanded';
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final Set<String> _picked = {};
  String _q = '';
  bool _sending = false;
  late final _caption = TextEditingController(text: widget.sharedText);
  Set<String> _mine = const {};
  /// Mục trợ lý đang mở / thu gọn (lưu trên máy). Chưa có thì: một trợ lý → mở; nhiều → chỉ mở trợ lý đầu.
  Map<String, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    app.myBotIds().then((v) {
      if (mounted) setState(() => _mine = v);
    }).catchError((_) {});
    app.uiPref<Map>(_prefKey).then((m) {
      if (!mounted || m == null) return;
      setState(() => _expanded = {for (final e in m.entries) '${e.key}': e.value == true, ..._expanded});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _caption.dispose();
    super.dispose();
  }

  List<MmPost> get _posts => [...widget.posts, ?widget.post];

  Future<void> _send() async {
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      // Chat chính với trợ lý chưa có kênh: mở kênh 1-1 trước.
      final ids = [for (final id in _picked) id.startsWith(_dmPrefix) ? await app.openDirect(id.substring(_dmPrefix.length)) : id];
      if (widget.shared) {
        await app.sendShared(ids, localPaths: widget.localPaths, text: _caption.text.trim());
        nav.pop();
        messenger.showSnackBar(toast(Text(tr('Đã gửi tới {0} cuộc trò chuyện', [_picked.length]))));
        return;
      }
      if (_posts.isNotEmpty && widget.files.isEmpty && widget.localPaths.isEmpty) {
        for (final p in _posts) {
          await app.forward(p, ids);
        }
      } else {
        await app.forwardFiles(ids, files: widget.files, localPaths: widget.localPaths);
      }
      nav.pop();
      messenger.showSnackBar(toast(Text(tr('Đã chuyển tiếp tới {0} cuộc trò chuyện', [_picked.length]))));
    } catch (_) {
      if (mounted) setState(() => _sending = false);
      messenger.showSnackBar(toast(Text(widget.shared
          ? tr('Gửi không thành công. Kiểm tra kết nối mạng.')
          : tr('Chuyển tiếp không thành công. Kiểm tra kết nối mạng.'))));
    }
  }

  void _toggle(String id) => setState(() {
        if (_picked.contains(id)) {
          _picked.remove(id);
        } else if (_picked.length < 5) {
          _picked.add(id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Chỉ chuyển tiếp tối đa 5 cuộc trò chuyện một lần'))));
        }
      });

  String _label(AppState app, String id) {
    if (id.startsWith(_dmPrefix)) return app.users[id.substring(_dmPrefix.length)]?.displayName ?? '';
    final c = app.channels[id];
    if (c == null) return '';
    return c.isAi ? aiSessionLabel(c) : app.channelTitle(c);
  }

  Widget _check(Pal pal, bool on) =>
      Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, color: on ? pal.accent : pal.sub, size: 26);

  Widget _chatTab(AppState app, Pal pal, String q) {
    final chats = app.chats.where((c) => !app.isAgentDm(c.channel) && (q.isEmpty || c.title.toLowerCase().contains(q))).toList();
    if (chats.isEmpty) return _empty(pal, tr('Không có cuộc trò chuyện nào'));
    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (_, i) {
        final c = chats[i];
        return ListTile(
          leading: Avatar(userId: c.avatarUserId, name: c.title, size: 44, icon: c.avatarUserId == null ? chatIcon(c.channel) : null, channel: c.channel),
          title: nameText(c.title, bot: app.users[c.avatarUserId]?.isBot == true, engine: engineOf(app.users[c.avatarUserId]), style: TextStyle(color: pal.text, fontWeight: FontWeight.w500)),
          trailing: _check(pal, _picked.contains(c.channel.id)),
          onTap: () => _toggle(c.channel.id),
        );
      },
    );
  }

  Widget _empty(Pal pal, String text) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: pal.sub))),
      );

  bool _isOpen(List<ForwardAgentGroup> all, ForwardAgentGroup g) =>
      _expanded[g.bot.id] ?? (all.length == 1 || all.first.bot.id == g.bot.id);

  Widget _agentTab(AppState app, Pal pal, String q) {
    final all = forwardAgentGroups(app, _mine);
    final rows = <Widget>[];
    for (final g in all) {
      final botHit = q.isEmpty || g.bot.displayName.toLowerCase().contains(q);
      final sessions = g.sessions.where((c) => botHit || aiSessionLabel(c).toLowerCase().contains(q)).toList();
      if (!botHit && sessions.isEmpty) continue;
      // Đang tìm: mở sẵn mục có kết quả.
      final open = q.isNotEmpty || _isOpen(all, g);
      final dmId = g.dm?.id ?? '$_dmPrefix${g.bot.id}';
      final n = [dmId, for (final c in g.sessions) c.id].where(_picked.contains).length;
      rows.add(InkWell(
        onTap: () {
          setState(() => _expanded[g.bot.id] = !open);
          app.setUiPref(_prefKey, Map<String, bool>.from(_expanded));
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(children: [
            Avatar(userId: g.bot.id, name: g.bot.displayName, size: 36, icon: Icons.smart_toy_outlined, status: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                nameText(g.bot.displayName, bot: true, engine: engineOf(g.bot), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text)),
                Text(n > 0 ? tr('{0} phiên · đã chọn {1}', [g.sessions.length, n]) : tr('{0} phiên', [g.sessions.length]),
                    style: TextStyle(fontSize: 12.5, color: n > 0 ? pal.accentText : pal.sub)),
              ]),
            ),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: pal.sub),
          ]),
        ),
      ));
      if (open) {
        if (botHit) {
          rows.add(ListTile(
            contentPadding: const EdgeInsets.only(left: 30, right: 16),
            leading: Icon(Icons.chat_bubble_outline_rounded, color: pal.sub, size: 22),
            title: Text(tr('Chat chính'), style: TextStyle(color: pal.text, fontWeight: FontWeight.w500)),
            trailing: _check(pal, _picked.contains(dmId)),
            onTap: () => _toggle(dmId),
          ));
        }
        for (final c in sessions) {
          final grp = app.channels[c.aiGroup];
          // Dòng phụ: dự án / cuộc trò chuyện của phiên (phiên của "Chung" thì không ghi).
          final where = grp == null || grp.isDirect ? null : app.channelTitle(grp);
          rows.add(ListTile(
            contentPadding: const EdgeInsets.only(left: 30, right: 16),
            leading: Icon(grp?.isAgentProject == true ? Icons.folder_outlined : Icons.forum_outlined, color: pal.sub, size: 22),
            title: Text(aiSessionLabel(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w500)),
            subtitle: where == null ? null : Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.sub, fontSize: 12.5)),
            trailing: _check(pal, _picked.contains(c.id)),
            onTap: () => _toggle(c.id),
          ));
        }
      }
      rows.add(Divider(height: 1, indent: 16, color: pal.divider));
    }
    if (rows.isEmpty) return _empty(pal, q.isEmpty ? tr('Chưa có trợ lý nào') : tr('Không tìm thấy'));
    return ListView(children: rows);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final q = _q.toLowerCase();
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              GlassCircle(icon: Icons.close, onTap: () => Navigator.pop(context)),
              Expanded(
                child: Text(widget.shared ? tr('Gửi tới…') : tr('Chuyển tiếp tới...'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.text)),
              ),
              const SizedBox(width: 44),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: TextStyle(color: pal.text),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: pal.surface,
                hintText: tr('Tìm kiếm'),
                hintStyle: TextStyle(color: pal.sub),
                prefixIcon: Icon(Icons.search, size: 20, color: pal.sub),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: pal.text,
            unselectedLabelColor: pal.sub,
            indicatorColor: pal.accent,
            dividerColor: pal.divider,
            tabs: [Tab(text: tr('Chat')), Tab(text: tr('Trợ lý'))],
          ),
          Expanded(
            child: TabBarView(controller: _tabs, children: [_chatTab(app, pal, q), _agentTab(app, pal, q)]),
          ),
          // Chia sẻ từ app khác: số tệp + ô chú thích (chữ / link được chia sẻ điền sẵn).
          if (widget.shared)
            Container(
              color: pal.surface,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.localPaths.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(tr('{0} tệp', [widget.localPaths.length]), style: TextStyle(color: pal.sub, fontSize: 13)),
                  ),
                TextField(
                  key: const ValueKey('share-caption'),
                  controller: _caption,
                  minLines: 1,
                  maxLines: 4,
                  style: TextStyle(color: pal.text),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: pal.bg,
                    hintText: tr('Thêm chú thích...'),
                    hintStyle: TextStyle(color: pal.sub),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ]),
            ),
          if (_picked.isNotEmpty)
            Container(
              color: pal.surface,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _picked.map((id) => _label(app, id)).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: pal.text),
                  ),
                ),
                const SizedBox(width: 10),
                _sending
                    ? SizedBox(width: 48, height: 48, child: Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(color: pal.accent, strokeWidth: 2)))
                    : Material(
                        color: pal.accent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _send,
                          child: const SizedBox(width: 48, height: 48, child: Icon(Icons.send_rounded, color: Colors.white)),
                        ),
                      ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Phát video đính kèm (tải trực tiếp từ máy chủ, có xác thực).
class VideoPlayerPage extends StatefulWidget {
  final MmFile file;
  const VideoPlayerPage({super.key, required this.file});
  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController _v;
  String? _err;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _v = VideoPlayerController.networkUrl(Uri.parse(app.api.fileUrl(widget.file.id)), httpHeaders: app.api.headers)
      ..initialize().then((_) {
        _v.play();
        setState(() {});
      }).catchError((_) => setState(() => _err = tr('Không phát được video')));
    _v.addListener(() => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EscToPop(child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.file.name, style: const TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: _err != null
            ? Text(_err!, style: const TextStyle(color: Colors.white70))
            : !_v.value.isInitialized
                ? const CircularProgressIndicator(color: Colors.white)
                : GestureDetector(
                    onTap: () => _v.value.isPlaying ? _v.pause() : _v.play(),
                    child: Stack(alignment: Alignment.center, children: [
                      AspectRatio(aspectRatio: _v.value.aspectRatio, child: VideoPlayer(_v)),
                      if (!_v.value.isPlaying) const Icon(Icons.play_circle_fill, color: Colors.white70, size: 72),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoProgressIndicator(_v, allowScrubbing: true, padding: const EdgeInsets.all(12)),
                      ),
                    ]),
                  ),
      ),
    ));
  }
}
