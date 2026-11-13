// Bảng tin: tin tức / thông báo nội bộ (Sếp, 2026-11-10). Danh sách bài (ghim ở đầu), lọc chuyên mục, tìm kiếm,
// lưu trữ, bài của tôi; quản trị Bảng tin có thêm chuyên mục và thống kê. Backend: flygo-chat-server bang-tin/.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../../config.dart' show isDesktop;
import '../../data/image_disk_cache.dart';
import '../app_route.dart';
import '../common.dart';
import '../theme.dart';
import 'admin_pages.dart';
import 'api.dart';
import 'bang_tin_service.dart';
import 'editor_page.dart';
import 'feed_widgets.dart';
import 'post_page.dart';
import 'receipts_page.dart';

/// Mở Bảng tin của [app] (mini app có native.screen = "bang_tin"); [postId] mở thẳng một bài.
Future<void> openBangTin(BuildContext context, MiniApp app, {String? postId}) async {
  final token = context.read<AppState>().token;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id = await FlygoId.current(token);
    if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
    final api = BangTinApi(base: app.baseUrl, id: id);
    await nav.push(
      AppPageRoute(
        builder: (_) => BangTinHome(api: api, title: app.name, openPost: postId),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

/// Thông tin người dùng trong Bảng tin (từ /api/me).
class BangTinMe {
  BangTinMe(this.id, this.name, this.admin, this.categories);
  final String id, name;
  final bool admin;
  final List<Map<String, dynamic>> categories;

  Map<String, dynamic>? category(String? id) => id == null ? null : categories.where((c) => c['id'] == id).firstOrNull;
}

Color? hexColor(Object? v) {
  final s = '${v ?? ''}'.replaceFirst('#', '');
  final n = s.length == 6 ? int.tryParse(s, radix: 16) : null;
  return n == null ? null : Color(0xFF000000 | n);
}

class BangTinHome extends StatefulWidget {
  const BangTinHome({super.key, required this.api, required this.title, this.openPost, this.inTab = false, this.bottomPadding = 0});
  final BangTinApi api;
  final String title;
  final String? openPost;

  /// Mở trong tab riêng (tab máy tính / tab dưới điện thoại): không tiêu đề, không nút quay lại (Sếp).
  final bool inTab;

  /// Khoảng trống dưới cùng (tab dưới của điện thoại: thanh điều hướng nổi đè lên nội dung).
  final double bottomPadding;

  @override
  State<BangTinHome> createState() => _BangTinHomeState();
}

enum _View { all, mine, archived }

/// Máy tính, cửa sổ đủ rộng: bài mở ở cột phải (bài + bình luận), bảng tin vẫn ở giữa.
const _splitMinWidth = 720.0;

class _BangTinHomeState extends State<BangTinHome> {
  BangTinMe? _me;
  List<Map<String, dynamic>> _pinned = const [], _posts = const [];
  int? _next;
  bool _loading = true, _loadingMore = false;
  String? _error, _category;
  _View _view = _View.all;
  final _q = TextEditingController();
  bool _searching = false;
  bool _scrolledPastComposer = false;

  /// Bài đang mở ở cột phải (máy tính); kèm cờ đặt con trỏ vào ô bình luận.
  String? _side;
  bool _sideComment = false;

  /// Cột phải đang hiện danh sách "đã xem" của bài [_side] thay vì bài + bình luận.
    bool _sideViews = false;
  bool _wide = false;

  BangTinApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    // Tab Bảng tin: hiện ngay bản tải sẵn (không vòng chờ), rồi làm mới; đang xem thì xoá số trên tab.
    final svc = BangTinService.instance;
    if (widget.inTab && svc.api == widget.api && svc.me != null) {
      final u = svc.me!['user'] as Map? ?? const {};
      _me = BangTinMe('${u['id']}', '${u['name']}', svc.me!['admin'] == true, _maps(svc.me!['categories']));
      _pinned = svc.pinned;
      _posts = svc.posts;
      _next = svc.next;
      _loading = false;
    }
    if (widget.inTab) WidgetsBinding.instance.addPostFrameCallback((_) => svc.markSeen());
    _load();
    if (widget.openPost != null) WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.openPost!));
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _query({int? before}) {
    final q = <String, String>{
      'limit': '20',

      'category': ?_category,
      if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
      if (_view == _View.mine) 'mine': '1',
      if (_view == _View.archived) 'archived': '1',
      if (before != null) 'before': '$before',
    };
    return Uri(queryParameters: q).query;
  }

  static List<Map<String, dynamic>> _maps(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];

  Future<void> _load() async {
    setState(() => (_loading = true, _error = null));
    try {
      final me = _me == null ? await api.get('/api/me') : null;
      final j = await api.get('/api/posts?${_query()}');
      if (!mounted) return;
      setState(() {
        if (me != null) {
          final u = me['user'] as Map? ?? const {};
          _me = BangTinMe('${u['id']}', '${u['name']}', me['admin'] == true, _maps(me['categories']));
        }
        _pinned = _maps(j['pinned']);
        _posts = _maps(j['posts']);
        _next = (j['next'] as num?)?.toInt();
        _loading = false;
      });
      // Trang đầu không lọc của tab Bảng tin: cập nhật bản tải sẵn và coi như đã xem.
      final svc = BangTinService.instance;
      if (widget.inTab && svc.api == api && _view == _View.all && _category == null && _q.text.trim().isEmpty) {
        svc.me ??= me;
        svc.update(pinned: _pinned, posts: _posts, next: _next);
        svc.markSeen();
      }
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _loading = false));
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _next == null) return;
    _loadingMore = true;
    try {
      final j = await api.get('/api/posts?${_query(before: _next)}');
      if (mounted) setState(() => (_posts = [..._posts, ..._maps(j['posts'])], _next = (j['next'] as num?)?.toInt()));
    } catch (_) {}
    _loadingMore = false;
  }

  Future<void> _reloadCategories() async {
    final me = await api.get('/api/me');
    if (mounted && _me != null) setState(() => _me = BangTinMe(_me!.id, _me!.name, _me!.admin, _maps(me['categories'])));
  }

  /// Cập nhật một bài trong danh sách (thả cảm xúc, đã đọc…) mà không tải lại cả trang.
  void _patch(Map<String, dynamic> p) => setState(() {
    _posts = [
      for (final x in _posts) x['id'] == p['id'] ? {...x, ...p} : x,
    ];
    _pinned = [
      for (final x in _pinned) x['id'] == p['id'] ? {...x, ...p} : x,
    ];
  });

    Future<void> _open(String id, {bool comment = false, bool photos = false}) async {
    final me = _me ?? await _waitMe();
    if (me == null || !mounted) return;
    _patch({'id': id, 'read': true});
    if (_wide) {
            setState(() => (_side = id, _sideComment = comment, _sideViews = false));
      return;
    }
    await Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => BangTinPostPage(api: api, me: me, postId: id, focusComment: comment),
      ),
    );
    _load();
  }

  /// Sửa bài (menu chuột phải / bấm giữ thẻ): lấy bài đầy đủ rồi mở trang soạn (máy tính: hộp thoại).
  Future<void> _edit(String id) async {
    final me = _me;
    if (me == null) return;
    try {
      final j = await api.get('/api/posts/$id');
      if (!mounted) return;
      final saved = await openBangTinEditor(context, api: api, me: me, post: Map<String, dynamic>.from(j['post'] as Map));
      if (saved != null) _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  /// Ai đã xem bài: máy tính mở ở cột phải, điện thoại mở bottom sheet (Sếp).
  void _views(Map<String, dynamic> p) {
    if (_wide) {
      setState(() => (_side = '${p['id']}', _sideViews = true));
    } else {
      showReceiptsSheet(context, api, '${p['id']}', '${p['title'] ?? ''}');
    }
  }

  Future<BangTinMe?> _waitMe() async {
    for (var i = 0; i < 50 && _me == null && mounted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _me;
  }

  Future<void> _compose({bool photos = false, bool background = false}) async {
    if (_me == null) return;
    final created = await openBangTinEditor(context, api: api, me: _me!, pickPhotos: photos, pickBackground: background);
    if (created != null) {
      await _load();
      if (mounted) _open(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final me = _me;
    final title = switch (_view) {
      _View.all => widget.title,
      _View.mine => tr('Bài của tôi'),
      _View.archived => tr('Lưu trữ'),
    };
    return LayoutBuilder(
      builder: (context, box) {
        _wide = isDesktop && box.maxWidth >= _splitMinWidth;
        final side = _wide ? _side : null;
        final sideW = (box.maxWidth * .38).clamp(400.0, 520.0);
        // Điện thoại, tab Bảng tin (Sếp): bỏ thanh trên trống; tìm kiếm và menu nằm ở ô soạn bài.
        final compact = widget.inTab && !isDesktop && _view == _View.all && !_searching;
        final feed = Scaffold(
          backgroundColor: _feedBg(context),
          appBar: compact
              ? null
              : AppBar(
                  backgroundColor: _feedBg(context),
                  automaticallyImplyLeading: !widget.inTab,
                  title: _searching
                      ? TextField(
                          controller: _q,
                          autofocus: true,
                          decoration: InputDecoration(hintText: tr('Tìm bài viết'), border: InputBorder.none),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _load(),
                        )
                      : (widget.inTab && _view == _View.all ? null : Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
                  actions: [
                    IconButton(
                      tooltip: _searching ? tr('Đóng') : tr('Tìm kiếm'),
                      icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                      onPressed: () {
                        setState(() => _searching = !_searching);
                        if (!_searching && _q.text.isNotEmpty) {
                          _q.clear();
                          _load();
                        }
                      },
                    ),
                    _menuButton(me),
                  ],
                ),
          body: Stack(children: [
            Positioned.fill(child: compact ? SafeArea(bottom: false, child: _body(context, pal)) : _body(context, pal)),
            // Nút "+" đăng bài (điện thoại): cỡ nhỏ, cách mép trên thanh điều hướng nổi ~12px; ẩn khi ô soạn bài ở đầu
            // còn trên màn hình (Sếp, ảnh Android 13/11).
            if (me != null && !isDesktop && _view != _View.archived && _scrolledPastComposer)
              Positioned(
                right: 16,
                // Phần nhìn thấy của thanh điều hướng thấp hơn bottomPadding ~23px (lề + bóng): còn cách ~12px.
                bottom: widget.bottomPadding - 11,
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: tr('Tạo bài viết'),
                  shape: const CircleBorder(),
                  onPressed: () => _compose(),
                  child: const Icon(Icons.add_rounded),
                ),
              ),
          ]),
          // Nút "+" đăng bài ở góc dưới phải (Sếp), nằm trên thanh điều hướng dưới, không đè.
        );
        if (side == null) return feed;
        return Row(
          children: [
            Expanded(child: feed),
            VerticalDivider(width: 1, color: pal.divider),
            SizedBox(
              width: sideW,
              child: _sideViews
                  ? BangTinReceiptsPage(key: ValueKey('views-$side'), api: api, postId: side, title: '', onClose: () => setState(() => _side = null))
                  : BangTinPostPage(
                      key: ValueKey('side-$side'),
                      api: api,
                      me: me!,
                      postId: side,
                                          embedded: true,
                      focusComment: _sideComment,
                      onClose: () => setState(() => _side = null),
                      onViews: () => setState(() => _sideViews = true),
                      onChanged: _patch,
                      onDeleted: () {
                        setState(() => _side = null);
                        _load();
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// Menu ⋮ của Bảng tin; [search] thêm mục "Tìm kiếm" (khi không có thanh trên).
  Widget _menuButton(BangTinMe? me, {bool search = false}) => PopupMenuButton<String>(
    onSelected: (v) async {
      switch (v) {
        case 'search':
          setState(() => _searching = true);
        case 'all' || 'mine' || 'archived':
          setState(() => _view = _View.values.byName(v));
          _load();
        case 'categories':
          await Navigator.of(context).push(AppPageRoute(builder: (_) => BangTinCategoriesPage(api: api)));
          _reloadCategories();
        case 'stats':
          await Navigator.of(context).push(
            AppPageRoute(
              builder: (_) => BangTinStatsPage(api: api, me: me!),
            ),
          );
      }
    },
    itemBuilder: (_) => [
      if (search)
        PopupMenuItem(
          value: 'search',
          child: ListTile(leading: const Icon(Icons.search_rounded), title: Text(tr('Tìm kiếm'))),
        ),
      if (_view != _View.all)
        PopupMenuItem(
          value: 'all',
          child: ListTile(leading: const Icon(Icons.dynamic_feed_rounded), title: Text(tr('Tất cả bài'))),
        ),
      if (_view != _View.mine)
        PopupMenuItem(
          value: 'mine',
          child: ListTile(leading: const Icon(Icons.edit_note_rounded), title: Text(tr('Bài của tôi'))),
        ),
      if (_view != _View.archived)
        PopupMenuItem(
          value: 'archived',
          child: ListTile(leading: const Icon(Icons.inventory_2_outlined), title: Text(tr('Lưu trữ'))),
        ),
      if (me?.admin == true) ...[
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'categories',
          child: ListTile(leading: const Icon(Icons.label_outline_rounded), title: Text(tr('Chuyên mục'))),
        ),
        PopupMenuItem(
          value: 'stats',
          child: ListTile(leading: const Icon(Icons.insights_rounded), title: Text(tr('Thống kê'))),
        ),
      ],
    ],
  );

  void _pickCategory(String? id) {
    setState(() => _category = id);
    _load();
  }

  Widget _centered(Widget w) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kFeedMaxWidth),
      child: w,
    ),
  );

  Widget _body(BuildContext context, Pal pal) {
    if (_loading && _posts.isEmpty && _pinned.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.sub),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(tr('Thử lại'))),
            ],
          ),
        ),
      );
    }
    final me = _me!;
    final head = <Widget>[
      if (_view != _View.archived) ComposerCard(me: me, onCompose: _compose, trailing: widget.inTab && !isDesktop ? _menuButton(me, search: true) : null),
      if (me.categories.isNotEmpty)
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(shape: const StadiumBorder(), label: Text(tr('Tất cả')), selected: _category == null, onSelected: (_) => _pickCategory(null)),
              ),
              for (final c in me.categories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    shape: const StadiumBorder(),
                    avatar: hexColor(c['color']) == null ? null : CircleAvatar(backgroundColor: hexColor(c['color']), radius: 5),
                    label: Text('${c['name']}'),
                    selected: _category == c['id'],
                    onSelected: (_) => _pickCategory('${c['id']}'),
                  ),
                ),
            ],
          ),
        ),
    ];
    // Bài ghim luôn ở đầu (ghim mới nhất trước), sau đó bài mới nhất trước (Sếp); bài nào cũng là thẻ như Facebook.
    final posts = [..._pinned, ..._posts];
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) _more();
          // Ô soạn bài ở đầu đã cuộn khuất: hiện nút "+".
          final past = n.metrics.axis == Axis.vertical && n.metrics.pixels > 140;
          if (past != _scrolledPastComposer) setState(() => _scrolledPastComposer = past);
          return false;
        },
        child: ListView.builder(
          padding: EdgeInsets.only(bottom: 40 + widget.bottomPadding + (isDesktop ? 0 : 64)),
          itemCount: head.length + posts.length + 1,
          itemBuilder: (_, i) {
            if (i < head.length) return _centered(head[i]);
            if (i == head.length + posts.length) {
              // Cuối danh sách (Sếp): "Bạn đã xem hết nội dung"; còn trang sau thì hiện vòng chờ.
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: _next != null
                    ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                    : Column(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, size: 34, color: pal.sub),
                          const SizedBox(height: 8),
                          Text(
                            _view == _View.archived && posts.isEmpty ? tr('Chưa có bài nào hết hạn') : tr('Bạn đã xem hết nội dung'),
                            style: TextStyle(color: pal.sub),
                          ),
                        ],
                      ),
              );
            }
            final p = posts[i - head.length];
            return _centered(
              FeedPostCard(
                key: ValueKey(p['id']),
                post: p,
                api: api,
                me: me,
                selected: _wide && _side == p['id'],
                onOpen: ({bool comment = false, bool photos = false}) => _open('${p['id']}', comment: comment, photos: photos),
                onChanged: _patch,
                onViews: () => _views(p),
                onEdit: () => _edit('${p['id']}'),
                onReload: () {
                  if (_side == p['id']) setState(() => _side = null);
                  _load();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Nền bảng tin: hơi khác nền app để thẻ trắng nổi lên (kiểu mạng xã hội).
Color _feedBg(BuildContext context) {
  final pal = Pal.of(context);
  return Theme.of(context).brightness == Brightness.dark ? pal.bg : Color.alphaBlend(const Color(0x0A5B6CFF), const Color(0xFFF2F3F7));
}

String _when(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${hhmm(d)} ${ddmmyyyy(d)}';
}

/// Ngày giờ đầy đủ (hạn xác nhận, ngày hết hạn).
String bangTinTime(int ms) => _when(ms);

/// Ảnh của Bảng tin (tải bằng vé, không dùng URL công khai).
class BangTinImage extends StatefulWidget {
  const BangTinImage({super.key, required this.api, required this.fileId, this.fit = BoxFit.cover});
  final BangTinApi api;
  final String fileId;
  final BoxFit fit;

  @override
  State<BangTinImage> createState() => _BangTinImageState();
}

class _BangTinImageState extends State<BangTinImage> {
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    // Ảnh qua bộ nhớ đệm trên đĩa, giải mã theo cỡ khung (không giữ cả ảnh gốc trong bộ nhớ).
    return LayoutBuilder(
      builder: (context, c) => Image(
        image: sizedImage(context, widget.api.image(widget.fileId), math.max(c.maxWidth, c.maxHeight)),
        fit: widget.fit,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : ColoredBox(color: pal.surface2),
        errorBuilder: (_, _, _) => ColoredBox(color: pal.surface2, child: Icon(Icons.broken_image_outlined, color: pal.sub)),
      ),
    );
  }
}

/// Mã tab Bảng tin trên máy tính (DeskTab 'app', arg này).
const kBangTinTab = 'bangtin';

/// Mini app Bảng tin của máy chủ đang dùng (đã tải trong danh sách app), null nếu máy chủ không có.
MiniApp? bangTinApp() => MiniApps.cached.where((a) => a.id == 'vn.flygo.bangtin').firstOrNull;

/// Tab "Bảng tin" ở thanh điều hướng dưới (điện thoại): trang chủ Bảng tin ngay trong tab, không mở trang mới.
class BangTinTab extends StatefulWidget {
  const BangTinTab({super.key, this.bottomPadding = 0});
  final double bottomPadding;
  @override
  State<BangTinTab> createState() => _BangTinTabState();
}

class _BangTinTabState extends State<BangTinTab> {
  late Future<(BangTinApi, String)?> _load = _open();

  /// Tìm app Bảng tin và Flygo ID của máy chủ; quá 25 giây thì báo lỗi kèm nút thử lại (trước đây quay vòng mãi).
  Future<(BangTinApi, String)?> _open() =>
      _find(context.read<AppState>().token)
          .timeout(const Duration(seconds: 25), onTimeout: () => throw StateError(tr('Không kết nối được Bảng tin. Kiểm tra mạng rồi thử lại.')));

  static Future<(BangTinApi, String)?> _find(String token) async {
    final apps = await MiniApps.list(token).catchError((_) => MiniApps.cached);
    final app = apps.where((a) => a.id == 'vn.flygo.bangtin').firstOrNull;
    if (app == null) return null;
    final id = await FlygoId.current(token);
    if (id == null) return null;
    return (BangTinApi(base: app.baseUrl, id: id), app.name);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    // Bảng tin chạy nền đã sẵn sàng (vé + trang đầu tải sẵn): hiện ngay, không chờ.
    final svc = BangTinService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) => svc.api != null
          ? BangTinHome(api: svc.api!, title: svc.title, inTab: true, bottomPadding: widget.bottomPadding)
          : _fallback(context, pal),
    );
  }

  /// Bảng tin chạy nền chưa sẵn sàng (mất mạng lúc mở app…): tự tìm app như trước.
  Widget _fallback(BuildContext context, Pal pal) {
    return FutureBuilder<(BangTinApi, String)?>(
      future: _load,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final v = s.data;
        if (v == null || s.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.hasError ? '${s.error}' : tr('Máy chủ này chưa có Bảng tin'), style: TextStyle(color: pal.sub)),
                const SizedBox(height: 8),
                TextButton(onPressed: () => setState(() => _load = _open()), child: Text(tr('Thử lại'))),
              ],
            ),
          );
        }
        return BangTinHome(api: v.$1, title: v.$2, inTab: true, bottomPadding: widget.bottomPadding);
      },
    );
  }
}
