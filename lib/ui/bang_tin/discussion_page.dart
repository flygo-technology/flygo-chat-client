// Thảo luận (Sếp, 21/11/2026): mọi người nêu quan điểm (Đồng ý / Phản đối / Ý kiến khác), trả lời nhau 2 tầng, 👍 / 👎 / cảm xúc,
// ẩn danh. Quan điểm là bài riêng tư của Bảng tin (chỉ người trong cuộc thảo luận thấy), hiện tức thì qua SSE của Bảng tin.
// Dùng lại thẻ bài, cảm xúc và trang bài + trả lời của Bảng tin. Trong cuộc họp: trang "Thảo luận" mở màn hình này.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../theme.dart';
import 'api.dart';
import 'bang_tin_page.dart';
import 'feed_widgets.dart';
import 'post_page.dart';
import 'reactions.dart';

const kStanceYes = Color(0xFF2BA77A), kStanceNo = Color(0xFFE0525A), kStanceOther = Color(0xFF8A5CF0);

/// Lập trường: (mã, tên, màu).
List<(String, String, Color)> get kStances => [('y', tr('Đồng ý'), kStanceYes), ('n', tr('Phản đối'), kStanceNo), ('o', tr('Ý kiến khác'), kStanceOther)];

(String, String, Color)? stanceOf(Object? code) => kStances.where((s) => s.$1 == code).firstOrNull;

/// Nhãn lập trường nhỏ ở đầu thẻ quan điểm.
class StancePill extends StatelessWidget {
  const StancePill(this.code, {super.key});
  final Object? code;
  @override
  Widget build(BuildContext context) {
    final s = stanceOf(code);
    if (s == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: s.$3.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
      child: Text(s.$2, style: TextStyle(color: s.$3, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Tạo API + người dùng Bảng tin từ mini app đã cài trên máy chủ (cho trang Thảo luận trong cuộc họp).
Future<(BangTinApi, BangTinMe)> bangTinSession(BuildContext context) async {
  final token = context.read<AppState>().token;
  final app = MiniApps.cached.where((a) => a.nativeScreen == 'bang_tin').firstOrNull;
  if (app == null) throw StateError(tr('Máy chủ này chưa cài Bảng tin'));
  final id = await FlygoId.current(token);
  if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
  final api = BangTinApi(base: app.baseUrl, id: id);
  final j = await api.get('/api/me');
  final u = j['user'] as Map? ?? const {};
  return (api, BangTinMe('${u['id']}', '${u['name']}', j['admin'] == true, const []));
}

/// Màn hình Thảo luận trong cuộc họp: tự lấy phiên Bảng tin rồi hiện [DiscussionPage].
class DiscussionLoader extends StatefulWidget {
  const DiscussionLoader({super.key, required this.discussionId, this.embedded = true});
  final String discussionId;
  final bool embedded;
  @override
  State<DiscussionLoader> createState() => _DiscussionLoaderState();
}

class _DiscussionLoaderState extends State<DiscussionLoader> {
  (BangTinApi, BangTinMe)? _s;
  String? _err;

  @override
  void initState() {
    super.initState();
    bangTinSession(context).then((s) {
      if (mounted) setState(() => _s = s);
    }, onError: (Object e) {
      if (mounted) setState(() => _err = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return Center(
        child: _err != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center))
            : const CircularProgressIndicator(),
      );
    }
    return DiscussionPage(api: s.$1, me: s.$2, discussionId: widget.discussionId, embedded: widget.embedded);
  }
}

class DiscussionPage extends StatefulWidget {
  const DiscussionPage({super.key, required this.api, required this.me, required this.discussionId, this.embedded = false, this.live = true});
  final BangTinApi api;
  final BangTinMe me;
  final String discussionId;

  /// Nằm trong trang của cuộc họp: không có thanh tiêu đề riêng.
  final bool embedded;

  /// Theo dõi SSE (kiểm thử tắt).
  final bool live;

  @override
  State<DiscussionPage> createState() => _DiscussionPageState();
}

class _DiscussionPageState extends State<DiscussionPage> {
  Map<String, dynamic>? _d, _pinned;
  List<Map<String, dynamic>> _posts = const [];
  String _sort = 'top';
  String? _stance, _error;
  StreamSubscription? _live;
  Timer? _debounce;

  BangTinApi get api => widget.api;
  String get _id => widget.discussionId;
  bool get _manage => _d?['can_manage'] == true;
  bool get _closed => _d?['closed'] == true;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.live) {
      _live = api.events(discussion: _id).listen((_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), _load);
      });
    }
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  static List<Map<String, dynamic>> _maps(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];

  Future<void> _load() async {
    try {
      final q = 'sort=$_sort${_stance != null ? '&stance=$_stance' : ''}';
      final j = await api.get('/api/discussions/$_id/posts?$q');
      if (!mounted) return;
      setState(() {
        _d = Map<String, dynamic>.from(j['discussion'] as Map);
        _pinned = j['pinned'] is Map ? Map<String, dynamic>.from(j['pinned'] as Map) : null;
        _posts = _maps(j['posts']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _toast(String s) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(s)));

  Future<void> _patch(Map<String, dynamic> body) async {
    try {
      await api.patch('/api/discussions/$_id', body);
      await _load();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _open(Map<String, dynamic> p, {bool comment = false}) async {
    await Navigator.of(context).push(AppPageRoute(
      builder: (_) => BangTinPostPage(api: api, me: widget.me, postId: '${p['id']}', focusComment: comment),
    ));
    if (mounted) _load();
  }

  Future<void> _react(Map<String, dynamic> p, String? emoji) async {
    final cur = (p['my_reactions'] as List? ?? const []).map((e) => '$e').firstOrNull;
    try {
      emoji == null
          ? await api.delete('/api/posts/${p['id']}/reactions/${Uri.encodeComponent(cur ?? '👍')}')
          : await api.post('/api/posts/${p['id']}/reactions', {'emoji': emoji});
      await _load();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _compose({Map<String, dynamic>? edit}) async {
    final r = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Pal.of(context).surface,
      builder: (_) => OpinionComposer(api: api, discussion: _d!, edit: edit),
    );
    if (r == true) _load();
  }

  /// Menu của một quan điểm: tác giả sửa / xoá; người điều hành ghim "đang bàn", ẩn, xoá.
  Future<void> _menu(Map<String, dynamic> p) async {
    final mine = p['mine'] == true;
    final items = <(String, IconData, String)>[
      if (_manage && p['hidden'] != true)
        p['discussing'] == true ? ('unpin', Icons.push_pin_outlined, tr('Bỏ ghim "Đang bàn"')) : ('pin', Icons.push_pin_rounded, tr('Ghim "Đang bàn" (lên TV)')),
      if (mine && !_closed) ('edit', Icons.edit_outlined, tr('Sửa quan điểm')),
      if (_manage) p['hidden'] == true ? ('unhide', Icons.visibility_outlined, tr('Hiện lại')) : ('hide', Icons.visibility_off_outlined, tr('Ẩn quan điểm này')),
      if (p['can_delete'] == true) ('delete', Icons.delete_outline_rounded, tr('Xoá')),
    ];
    if (items.isEmpty) return;
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Pal.of(context).surface,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (id, icon, label) in items)
            ListTile(
              leading: Icon(icon, color: id == 'delete' ? kStanceNo : null),
              title: Text(label, style: id == 'delete' ? const TextStyle(color: kStanceNo) : null),
              onTap: () => Navigator.pop(s, id),
            ),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    try {
      switch (v) {
        case 'pin':
          await _patch({'pinned_post': p['id']});
        case 'unpin':
          await _patch({'pinned_post': null});
        case 'edit':
          await _compose(edit: p);
        case 'hide' || 'unhide':
          await api.patch('/api/posts/${p['id']}', {'hidden': v == 'hide'});
          await _load();
        case 'delete':
          await api.delete('/api/posts/${p['id']}');
          await _load();
      }
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _manageMenu() async {
    final d = _d!;
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Pal.of(context).surface,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(d['locked'] == true ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
            title: Text(d['locked'] == true ? tr('Mở lại trả lời') : tr('Khoá trả lời')),
            onTap: () => Navigator.pop(s, 'lock'),
          ),
          ListTile(
            leading: Icon(d['stance'] == true ? Icons.toggle_on_rounded : Icons.toggle_off_outlined),
            title: Text(d['stance'] == true ? tr('Tắt chọn lập trường') : tr('Bật chọn lập trường')),
            onTap: () => Navigator.pop(s, 'stance'),
          ),
          ListTile(
            leading: Icon(_closed ? Icons.play_circle_outline_rounded : Icons.stop_circle_outlined, color: _closed ? null : kStanceNo),
            title: Text(_closed ? tr('Mở lại thảo luận') : tr('Đóng thảo luận'), style: _closed ? null : const TextStyle(color: kStanceNo)),
            onTap: () => Navigator.pop(s, 'close'),
          ),
        ]),
      ),
    );
    switch (v) {
      case 'lock':
        await _patch({'locked': d['locked'] != true});
      case 'stance':
        await _patch({'stance': d['stance'] != true});
      case 'close':
        await _patch({'closed': !_closed});
    }
  }

  void _filter(VoidCallback change) {
    setState(change);
    _load();
  }

  Widget _header(Pal pal) {
    final d = _d!;
    final sc = Map<String, dynamic>.from(d['stance_counts'] as Map? ?? const {});
    final counts = Map<String, dynamic>.from(d['counts'] as Map? ?? const {});
    final total = kStances.fold<int>(0, (s, x) => s + ((sc[x.$1] as num?)?.toInt() ?? 0));
    Widget chip(String label, bool on, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(label: Text(label), selected: on, onSelected: (_) => tap(), visualDensity: VisualDensity.compact),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if ('${d['question'] ?? ''}'.isNotEmpty || widget.embedded)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${'${d['question'] ?? ''}'.isNotEmpty ? d['question'] : d['title']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text)),
              const SizedBox(height: 4),
              Text(
                [
                  tr('{0} quan điểm', ['${counts['posts'] ?? 0}']),
                  tr('{0} trả lời', ['${counts['replies'] ?? 0}']),
                  if (_closed) tr('đã đóng') else if (d['locked'] == true) tr('đã khoá trả lời'),
                ].join(' · '),
                style: TextStyle(color: pal.sub, fontSize: 12.5),
              ),
            ]),
          ),
        if (d['stance'] == true) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: total == 0
                  ? ColoredBox(color: pal.divider)
                  : Row(children: [
                      for (final s in kStances)
                        if (((sc[s.$1] as num?)?.toInt() ?? 0) > 0) Expanded(flex: (sc[s.$1] as num).toInt(), child: Container(color: s.$3)),
                    ]),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 12, children: [
            for (final s in kStances)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${sc[s.$1] ?? 0} ${s.$2}', style: TextStyle(color: pal.sub, fontSize: 12.5)),
              ]),
          ]),
        ],
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip(tr('Nổi bật'), _sort == 'top', () => _filter(() => _sort = 'top')),
            chip(tr('Mới nhất'), _sort == 'new', () => _filter(() => _sort = 'new')),
            chip(tr('Của tôi'), _sort == 'mine', () => _filter(() => _sort = 'mine')),
            if (d['stance'] == true)
              for (final s in kStances) chip(s.$2, _stance == s.$1, () => _filter(() => _stance = _stance == s.$1 ? null : s.$1)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final d = _d;
    final body = d == null
        ? Center(child: _error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)) : const CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _header(pal),
                if (_pinned != null) OpinionCard(post: _pinned!, api: api, me: widget.me, onOpen: _open, onReact: _react, onMenu: _menu),
                for (final p in _posts) OpinionCard(post: p, api: api, me: widget.me, onOpen: _open, onReact: _react, onMenu: _menu),
                if (_pinned == null && _posts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _sort == 'mine' ? tr('Bạn chưa nêu quan điểm nào.') : tr('Chưa có quan điểm nào. Hãy là người đầu tiên!'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: pal.sub),
                    ),
                  ),
              ],
            ),
          );
    final composer = d == null || _closed
        ? null
        : Material(
            color: pal.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: InkWell(
                  key: const ValueKey('opinion-new'),
                  borderRadius: BorderRadius.circular(22),
                  onTap: _compose,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(22)),
                    child: Row(children: [
                      Expanded(child: Text(tr('Nêu quan điểm của bạn…'), style: TextStyle(color: pal.sub))),
                      Icon(Icons.send_rounded, color: pal.accent, size: 20),
                    ]),
                  ),
                ),
              ),
            ),
          );
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text('${d?['title'] ?? tr('Thảo luận')}', maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [if (_manage) IconButton(tooltip: tr('Điều hành'), icon: const Icon(Icons.tune_rounded), onPressed: _manageMenu)],
            ),
      floatingActionButton: widget.embedded && _manage
          ? FloatingActionButton.small(heroTag: null, tooltip: tr('Điều hành'), onPressed: _manageMenu, child: const Icon(Icons.tune_rounded))
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      body: body,
      bottomNavigationBar: composer,
    );
  }
}

/// Thẻ một quan điểm: đúng thẻ bài của Bảng tin (đầu thẻ, nội dung, ảnh, nút cảm xúc / trả lời) + lập trường, "đang bàn",
/// 2 trả lời mới nhất.
class OpinionCard extends StatelessWidget {
  const OpinionCard({super.key, required this.post, required this.api, required this.me, required this.onOpen, required this.onReact, required this.onMenu});
  final Map<String, dynamic> post;
  final BangTinApi api;
  final BangTinMe me;
  final void Function(Map<String, dynamic> p, {bool comment}) onOpen;
  final void Function(Map<String, dynamic> p, String? emoji) onReact;
  final ValueChanged<Map<String, dynamic>> onMenu;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = post;
    const gold = Color(0xFFE0A21A);
    final images = [for (final i in (p['images'] as List? ?? const [])) '$i'];
    final replies = [for (final r in (p['latest_replies'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    final comments = (p['comments'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: feedCard(context, border: p['discussing'] == true ? gold : null),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onOpen(p),
          onLongPress: () => onMenu(p),
          onSecondaryTap: () => onMenu(p),
          child: Opacity(
            opacity: p['hidden'] == true ? .55 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (p['discussing'] == true || p['hidden'] == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(children: [
                    Icon(p['hidden'] == true ? Icons.visibility_off_outlined : Icons.push_pin_rounded, size: 14, color: p['hidden'] == true ? pal.sub : gold),
                    const SizedBox(width: 4),
                    Text(
                      p['hidden'] == true ? tr('ĐÃ ẨN (chỉ bạn và người điều hành thấy)') : tr('ĐANG BÀN'),
                      style: TextStyle(color: p['hidden'] == true ? pal.sub : gold, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6),
                    ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: PostHeader(
                  post: {...p, 'audience_kind': 'custom', 'category': null, 'pinned': false},
                  me: me,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    StancePill(p['stance']),
                    IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.more_horiz_rounded, color: pal.sub), onPressed: () => onMenu(p)),
                  ]),
                ),
              ),
              PostBody(post: p, onMore: () => onOpen(p)),
              if (images.isNotEmpty) ...[
                const SizedBox(height: 8),
                ImageGallery(api: api, ids: images.take(4).toList(), total: (p['image_count'] as num?)?.toInt() ?? images.length, onTap: (_) => onOpen(p)),
              ],
              if (replies.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: pal.divider, width: 2))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final r in replies)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: '${(r['author'] as Map?)?['name'] ?? ''}  ', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                              TextSpan(text: '${r['body'] ?? ''}', style: TextStyle(color: pal.text)),
                            ]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                      if (comments > replies.length)
                        TextButton(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                          onPressed: () => onOpen(p),
                          child: Text(tr('Xem cả {0} trả lời', ['$comments'])),
                        ),
                    ]),
                  ),
                ),
              PostActions(
                post: p,
                mine: p['mine'] == true,
                kinds: kDiscussReactionKinds,
                commentLabel: tr('Trả lời'),
                onReact: (e) => onReact(p, e),
                onComment: () => onOpen(p, comment: true),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Soạn / sửa quan điểm: lập trường (nếu bật), nội dung, ẩn danh.
class OpinionComposer extends StatefulWidget {
  const OpinionComposer({super.key, required this.api, required this.discussion, this.edit});
  final BangTinApi api;
  final Map<String, dynamic> discussion;
  final Map<String, dynamic>? edit;
  @override
  State<OpinionComposer> createState() => _OpinionComposerState();
}

class _OpinionComposerState extends State<OpinionComposer> {
  late final _text = TextEditingController(text: '${widget.edit?['body_preview'] ?? ''}');
  late String? _stance = widget.edit?['stance'] as String?;
  bool _anon = false, _busy = false;
  String? _err;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return setState(() => _err = tr('Hãy viết quan điểm của bạn'));
    setState(() => _busy = true);
    try {
      if (widget.edit != null) {
        await widget.api.patch('/api/posts/${widget.edit!['id']}', {'body': t, 'stance': _stance});
      } else {
        await widget.api.post('/api/posts', {'discussion': widget.discussion['id'], 'body': t, 'stance': ?_stance, 'anon': _anon});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => (_err = '$e', _busy = false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final d = widget.discussion;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.edit != null ? tr('Sửa quan điểm') : tr('Quan điểm mới'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
        if ('${d['question'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${d['question']}', style: TextStyle(color: pal.sub)),
        ],
        if (d['stance'] == true) ...[
          const SizedBox(height: 12),
          Text(tr('Lập trường của bạn'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final s in kStances)
              ChoiceChip(
                key: ValueKey('stance-${s.$1}'),
                label: Text(s.$2),
                selected: _stance == s.$1,
                selectedColor: s.$3.withValues(alpha: .18),
                labelStyle: TextStyle(color: _stance == s.$1 ? s.$3 : null, fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => _stance = _stance == s.$1 ? null : s.$1),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('opinion-text'),
          controller: _text,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 5000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: tr('Viết quan điểm của bạn…'), counterText: '', border: const OutlineInputBorder()),
        ),
        if (widget.edit == null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Gửi ẩn danh')),
            subtitle: Text(tr('Không ai thấy tên bạn, kể cả người điều hành')),
            value: _anon,
            onChanged: (v) => setState(() => _anon = v),
          ),
        if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_err!, style: const TextStyle(color: kStanceNo))),
        FilledButton(
          key: const ValueKey('opinion-send'),
          onPressed: _busy ? null : _send,
          child: Text(widget.edit != null ? tr('Lưu') : tr('Gửi quan điểm')),
        ),
      ]),
    );
  }
}

/// Danh sách cuộc thảo luận của mình trong Bảng tin (dùng riêng, ngoài cuộc họp) + tạo mới với người được mời.
class DiscussionListPage extends StatefulWidget {
  const DiscussionListPage({super.key, required this.api, required this.me});
  final BangTinApi api;
  final BangTinMe me;
  @override
  State<DiscussionListPage> createState() => _DiscussionListPageState();
}

class _DiscussionListPageState extends State<DiscussionListPage> {
  List<Map<String, dynamic>>? _list;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.api.get('/api/discussions');
      if (mounted) setState(() => _list = [for (final d in (j['discussions'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)]);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _create() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Pal.of(context).surface,
      builder: (_) => _NewDiscussion(api: widget.api),
    );
    if (id == null || !mounted) return;
    await _load();
    if (mounted) _open(id);
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push(AppPageRoute(builder: (_) => DiscussionPage(api: widget.api, me: widget.me, discussionId: id)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final l = _list;
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: Text(tr('Thảo luận'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_comment_outlined), label: Text(tr('Thảo luận mới'))),
      body: l == null
          ? Center(child: _err != null ? Text(_err!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: l.isEmpty
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(tr('Chưa có cuộc thảo luận nào. Tạo một cuộc thảo luận riêng và mời người cùng bàn.'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
                      ),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                      itemCount: l.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final d = l[i];
                        final c = Map<String, dynamic>.from(d['counts'] as Map? ?? const {});
                        return Container(
                          decoration: feedCard(context),
                          child: ListTile(
                            leading: Icon(d['meeting'] != null ? Icons.groups_outlined : Icons.forum_outlined, color: pal.accentText),
                            title: Text('${d['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [
                                tr('{0} quan điểm', ['${c['posts'] ?? 0}']),
                                tr('{0} người', ['${d['members'] ?? 0}']),
                                if (d['meeting'] != null) tr('cuộc họp'),
                                if (d['closed'] == true) tr('đã đóng'),
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open('${d['id']}'),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _NewDiscussion extends StatefulWidget {
  const _NewDiscussion({required this.api});
  final BangTinApi api;
  @override
  State<_NewDiscussion> createState() => _NewDiscussionState();
}

class _NewDiscussionState extends State<_NewDiscussion> {
  final _title = TextEditingController(), _q = TextEditingController(), _search = TextEditingController();
  bool _stance = true, _busy = false;
  List<Map<String, dynamic>> _people = const [];
  final _picked = <String>{};
  String? _err;

  @override
  void initState() {
    super.initState();
    widget.api.get('/api/directory').then((j) {
      if (mounted) setState(() => _people = [for (final p in (j['people'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)]);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _q.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty) return setState(() => _err = tr('Đặt tên cuộc thảo luận'));
    if (_picked.isEmpty) return setState(() => _err = tr('Mời ít nhất một người'));
    setState(() => _busy = true);
    try {
      final j = await widget.api.post('/api/discussions', {
        'title': _title.text.trim(),
        'question': _q.text.trim(),
        'stance': _stance,
        'audience': {'users': _picked.toList()},
      });
      if (mounted) Navigator.pop(context, '${(j['discussion'] as Map)['id']}');
    } catch (e) {
      if (mounted) setState(() => (_err = '$e', _busy = false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final q = _search.text.trim().toLowerCase();
    final shown = _people.where((p) => q.isEmpty || '${p['name']}'.toLowerCase().contains(q)).take(50).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Thảo luận mới'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
          const SizedBox(height: 10),
          TextField(controller: _title, decoration: InputDecoration(labelText: tr('Tên'), hintText: tr('vd: Kế hoạch tăng ca tháng 12'))),
          TextField(controller: _q, decoration: InputDecoration(labelText: tr('Câu hỏi để mọi người nêu quan điểm (không bắt buộc)'))),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Chọn lập trường (Đồng ý / Phản đối / Ý kiến khác)')), value: _stance, onChanged: (v) => setState(() => _stance = v)),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.person_add_alt_1_rounded), hintText: tr('Mời người tham gia ({0} đã chọn)', ['${_picked.length}'])),
          ),
          Expanded(
            child: ListView(children: [
              for (final p in shown)
                CheckboxListTile(
                  dense: true,
                  value: _picked.contains('${p['id']}'),
                  title: Text('${p['name']}'),
                  onChanged: (v) => setState(() => v == true ? _picked.add('${p['id']}') : _picked.remove('${p['id']}')),
                ),
            ]),
          ),
          if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_err!, style: const TextStyle(color: kStanceNo))),
          FilledButton(onPressed: _busy ? null : _create, child: Text(tr('Tạo thảo luận'))),
        ]),
      ),
    );
  }
}
