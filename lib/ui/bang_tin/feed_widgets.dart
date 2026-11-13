// Bảng tin, giao diện kiểu mạng xã hội (Sếp, 2026-11-10): ô soạn bài và thẻ bài như Facebook (avatar viền màu, huy hiệu,
// chữ to có "Xem thêm", nền màu, ảnh tràn viền, hàng cảm xúc / bình luận / chia sẻ). Bài ghim cũng là thẻ, có nhãn "Đã ghim".
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../chat_info_page.dart' show openDirectWith;

import '../../i18n/i18n.dart';
import '../common.dart';
import '../markdown_view.dart';
import '../theme.dart';
import 'api.dart';
import 'backgrounds.dart';
import 'gallery.dart';
import 'bang_tin_page.dart';
import 'poll_widgets.dart';
import 'reactions.dart';
import 'share_sheet.dart';

const kFeedMaxWidth = 680.0;
const _orange = Color(0xFFE8833A);

/// Bóng mềm của thẻ (nền sáng); nền tối dùng viền mảnh.
List<BoxShadow> feedShadow(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const []
    : const [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 4)), BoxShadow(color: Color(0x0A000000), blurRadius: 3)];

BoxDecoration feedCard(BuildContext context, {Color? border}) {
  final pal = Pal.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: pal.surface,
    borderRadius: BorderRadius.circular(18),
    boxShadow: feedShadow(context),
    border: Border.all(color: border ?? (dark ? pal.divider : Colors.transparent), width: border == null ? 1 : 1.5),
  );
}

/// Avatar có viền chuyển sắc (quản trị: vàng cam; người khác: xanh tím).
class AvatarRing extends StatelessWidget {
  const AvatarRing({super.key, required this.userId, required this.name, this.size = 46, this.gold = false});
  final String userId, name;
  final double size;
  final bool gold;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2.2),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: gold ? const [Color(0xFFFFC94D), Color(0xFFFF7A45)] : const [Color(0xFF5B8CFF), Color(0xFFB45BFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: Pal.of(context).surface),
      child: Avatar(userId: userId, name: name, size: size - 8.4, status: false),
    ),
  );
}

/// Đầu thẻ bài: avatar, tên + huy hiệu, giờ · người nhận · chuyên mục.
class PostHeader extends StatelessWidget {
  const PostHeader({super.key, required this.post, required this.me, this.trailing});
  final Map<String, dynamic> post;
  final BangTinMe me;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final a = post['author'] as Map? ?? const {};
    final admin = post['author_admin'] == true;
    final cat = me.category(post['category'] as String?);
    final catColor = hexColor(cat?['color']) ?? pal.accentText;
    final everyone = post['audience_kind'] != 'custom';
    final sub = TextStyle(color: pal.sub, fontSize: 13);
    return Row(
      children: [
        AvatarRing(userId: '${a['id']}', name: '${a['name']}', gold: admin),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      '${a['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text),
                    ),
                  ),
                  if (admin) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: tr('Quản trị Bảng tin'),
                      child: const Icon(Icons.verified_rounded, size: 17, color: Color(0xFF1D9BF0)),
                    ),
                  ],
                  if (post['pinned'] == true) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: _orange.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.push_pin_rounded, size: 12, color: _orange),
                          const SizedBox(width: 2),
                          Text(
                            tr('Đã ghim'),
                            style: const TextStyle(color: _orange, fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Text(listTime((post['created_at'] as num).toInt()), style: sub),
                  Text('·', style: sub),
                  Tooltip(
                    message: everyone ? tr('Toàn công ty') : tr('Phòng ban hoặc người cụ thể'),
                    child: Icon(everyone ? Icons.public_rounded : Icons.groups_rounded, size: 14, color: pal.sub),
                  ),
                  if (cat != null) ...[
                    Text('·', style: sub),
                    Text(
                      '#${cat['name']}',
                      style: TextStyle(color: catColor, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (post['ack_deadline'] != null) ...[
                    Text('·', style: sub),
                    Text(
                      tr('Hạn {0}', [bangTinTime((post['ack_deadline'] as num).toInt())]),
                      style: const TextStyle(color: _orange, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Nội dung bài: tiêu đề, chữ (thu gọn có "Xem thêm") hoặc chữ to trên nền màu, người được gắn thẻ.
class PostBody extends StatefulWidget {
  const PostBody({super.key, required this.post, this.full = false, this.onMore});
  final Map<String, dynamic> post;

  /// Trang chi tiết: hiện hết, không thu gọn.
  final bool full;

  /// Nội dung bị cắt ở server: "Xem thêm" mở trang bài.
  final VoidCallback? onMore;

  @override
  State<PostBody> createState() => _PostBodyState();
}

class _PostBodyState extends State<PostBody> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = widget.post;
    final title = '${p['title'] ?? ''}';
    final body = '${(widget.full ? p['body'] : p['body_preview']) ?? p['excerpt'] ?? ''}';
    final bg = bgById(p['bg'] as String?);
    final hasImages = ((p['image_count'] as num?) ?? 0) > 0 || p['cover'] != null;
    final onBg = bg != null && !hasImages && body.trim().isNotEmpty && body.length <= kBgMaxChars;
    final tags = [
      for (final t in (p['tags'] as List? ?? const []))
        if (t is Map) t,
    ];
    final style = TextStyle(fontSize: 16.5, color: pal.text, height: 1.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text, height: 1.3),
            ),
          ),
        if (onBg)
          BgText(spec: bg, text: body.trim())
        else if (body.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: widget.full || _open
                ? MarkdownView(text: body, style: style)
                : _Collapsed(
                    text: body,
                    style: style,
                    more: p['body_truncated'] == true,
                    onMore: () => p['body_truncated'] == true && widget.onMore != null ? widget.onMore!() : setState(() => _open = true),
                  ),
          ),
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.sell_outlined, size: 15, color: pal.sub),
                Text(tr('cùng với'), style: TextStyle(color: pal.sub, fontSize: 13.5)),
                for (final t in tags)
                  // Bấm người được gắn thẻ: mở tin nhắn riêng với người đó (Sếp).
                  GestureDetector(
                    onTap: () => _openDm(context, '${t['id']}', '${t['name']}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: pal.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        '@${t['name']}',
                        style: TextStyle(color: pal.accentText, fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Mở tin nhắn riêng với người dùng [id] (người được gắn thẻ).
Future<void> _openDm(BuildContext context, String id, String name) async {
  final app = context.read<AppState>();
  final u = app.users[id] ?? MmUser({'id': id, 'username': name, 'first_name': name});
  await openDirectWith(context, app, u);
}

/// Chữ thu gọn 5 dòng; dài hơn thì hiện "Xem thêm".
class _Collapsed extends StatelessWidget {
  const _Collapsed({required this.text, required this.style, required this.more, required this.onMore});
  final String text;
  final TextStyle style;
  final bool more;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final pal = Pal.of(context);
      // Đo bằng chữ thô (bỏ dấu Markdown) với đúng kiểu chữ của theme.
      final plain = text
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^\s*(#{1,6}|>|[-*+])\s+'), '').replaceAll(RegExp(r'\*\*|__|`'), ''))
          .join('\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      final full = DefaultTextStyle.of(context).style.merge(style);
      final tp = TextPainter(
        text: TextSpan(text: plain, style: full),
        maxLines: 5,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: box.maxWidth);
      final overflow = tp.didExceedMaxLines || more;
      if (!overflow) return MarkdownView(text: text, style: style);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plain, maxLines: 5, overflow: TextOverflow.ellipsis, style: style),
          GestureDetector(
            onTap: onMore,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tr('Xem thêm'),
                style: TextStyle(fontWeight: FontWeight.w700, color: pal.text, fontSize: 15),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Ảnh của bài: 1 ảnh tràn viền; 2 ảnh cạnh nhau; 3 ảnh = 1 lớn + 2; từ 4 ảnh lưới 2×2, ô cuối "+N".
class ImageGallery extends StatelessWidget {
  const ImageGallery({super.key, required this.api, required this.ids, required this.total, this.onTap});
  final BangTinApi api;
  final List<String> ids;
  final int total;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return const SizedBox.shrink();
    Widget img(int i, {String? more}) => GestureDetector(
      onTap: onTap == null ? null : () => onTap!(i),
      child: Stack(
        fit: StackFit.expand,
        children: [
          BangTinImage(api: api, fileId: ids[i]),
          if (more != null)
            ColoredBox(
              color: Colors.black45,
              child: Center(
                child: Text(
                  more,
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
    const gap = SizedBox(width: 3, height: 3);
    if (ids.length == 1) return AspectRatio(aspectRatio: 1.5, child: img(0));
    if (ids.length == 2) {
      return AspectRatio(
        aspectRatio: 1.6,
        child: Row(
          children: [
            Expanded(child: img(0)),
            gap,
            Expanded(child: img(1)),
          ],
        ),
      );
    }
    if (ids.length == 3) {
      return AspectRatio(
        aspectRatio: 1.25,
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: SizedBox(width: double.infinity, child: img(0)),
            ),
            gap,
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(child: img(1)),
                  gap,
                  Expanded(child: img(2)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final extra = total - 4;
    return AspectRatio(
      aspectRatio: 1.1,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: img(0)),
                gap,
                Expanded(child: img(1)),
              ],
            ),
          ),
          gap,
          Expanded(
            child: Row(
              children: [
                Expanded(child: img(2)),
                gap,
                Expanded(child: img(3, more: extra > 0 ? '+$extra' : null)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hàng đếm (cảm xúc bên trái, bình luận bên phải) và hàng nút Thích / Bình luận / Xác nhận.
class PostActions extends StatelessWidget {
  const PostActions({
    super.key,
    required this.post,
    required this.mine,
    required this.onReact,
    required this.onComment,
    this.onShare,
    this.onViews,
    this.likeKey,
  });
  final Map<String, dynamic> post;
  final bool mine;
  final ValueChanged<String?> onReact;
  final VoidCallback onComment;
  final VoidCallback? onShare;

  /// Bấm "N lượt xem" (tác giả / quản trị): xem ai đã xem.
  final VoidCallback? onViews;
  final GlobalKey<LikeButtonState>? likeKey;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final reactions = Map<String, dynamic>.from(post['reactions'] as Map? ?? const {});
    final my = (post['my_reactions'] as List? ?? const []).map((e) => '$e').firstOrNull;
    final comments = (post['comments'] as num?)?.toInt() ?? 0;
    final shares = (post['shares'] as num?)?.toInt() ?? 0;
    final views = (post['views'] as num?)?.toInt();
    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color, bool flip = false}) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Mũi tên chia sẻ: lật icon "trả lời" như nút Chia sẻ của Facebook.
              Transform.flip(
                flipX: flip,
                child: Icon(icon, size: 19, color: color ?? pal.sub),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color ?? pal.sub, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Column(
      children: [
        if (reactions.isNotEmpty || comments > 0 || shares > 0 || views != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                ReactionSummary(reactions: reactions),
                if (views != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: onViews,
                    child: Padding(
                      padding: EdgeInsets.only(left: reactions.isEmpty ? 0 : 10, top: 2, bottom: 2, right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility_outlined, size: 16, color: pal.sub),
                          const SizedBox(width: 4),
                          Text(tr('{0} lượt xem', ['$views']), style: TextStyle(color: pal.sub, fontSize: 13.5)),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onComment,
                    child: Text(
                      [
                        if (comments > 0) tr('{0} bình luận', ['$comments']),
                        if (shares > 0) tr('{0} lượt chia sẻ', ['$shares']),
                      ].join('  ·  '),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: pal.sub, fontSize: 13.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Divider(height: 1, color: pal.divider),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: LikeButton(key: likeKey, mine: my, onReact: onReact),
                ),
              ),
              action(Icons.mode_comment_outlined, tr('Bình luận'), onComment),
              if (onShare != null) action(Icons.reply_rounded, tr('Chia sẻ'), onShare!, flip: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thẻ một bài trong bảng tin.
class FeedPostCard extends StatelessWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.api,
    required this.me,
    required this.onOpen,
    required this.onChanged,
    this.onViews,
    this.onEdit,
    this.onReload,
    this.selected = false,
    this.likeKey,
  });
  final Map<String, dynamic> post;
  final BangTinApi api;
  final BangTinMe me;

  /// Mở bài; comment = true để con trỏ vào ô bình luận.
  /// photos = true: ô "+N" của lưới ảnh, mở chi tiết bài kèm đủ ảnh.
  final void Function({bool comment, bool photos}) onOpen;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback? onViews;

  /// Menu chuột phải / bấm giữ (bài của mình, hoặc quản trị): sửa; ghim / xoá xong thì tải lại bảng tin.
  final VoidCallback? onEdit, onReload;
  final bool selected;
  final GlobalKey<LikeButtonState>? likeKey;

  Future<void> _react(BuildContext context, String? emoji) async {
    final messenger = ScaffoldMessenger.of(context);
    final cur = (post['my_reactions'] as List? ?? const []).map((e) => '$e').firstOrNull;
    try {
      final r = emoji == null
          ? await api.delete('/api/posts/${post['id']}/reactions/${Uri.encodeComponent(cur ?? '👍')}')
          : await api.post('/api/posts/${post['id']}/reactions', {'emoji': emoji});
      onChanged({...post, ...r});
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  /// Menu của thẻ: máy tính hiện tại chỗ nháy chuột phải; điện thoại (bấm giữ) hiện bottom sheet.
  bool get _mine => (post['author'] as Map?)?['id'] == me.id;
  List<String> get _imageIds {
    final ids = [for (final i in (post['images'] as List? ?? const [])) '$i'];
    if (ids.isEmpty && post['cover'] != null) ids.add('${post['cover']}');
    return ids;
  }

  /// Mục menu của thẻ (id, icon, nhãn, bấm được). Sửa: chỉ người đăng (Sếp); ghim: người đăng hoặc quản trị;
  /// "Lưu ảnh" khi bài có ảnh; "Xác nhận đã đọc" khi bài cần xác nhận (đã xác nhận thì hiện mờ).
  List<(String, IconData, String, bool)> _menuItems() {
    final pinned = post['pinned'] == true;
    final manage = (_mine || me.admin) && onReload != null;
    final ack = post['require_ack'] == true && !_mine;
    return [
      if (_mine && onEdit != null) ('edit', Icons.edit_outlined, tr('Sửa bài'), true),
      // Ghim: người đăng hoặc quản trị; bỏ ghim và xoá: chỉ quản trị (Sếp).
      if (pinned ? me.admin && onReload != null : manage) ('pin', pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, pinned ? tr('Bỏ ghim') : tr('Ghim lên đầu'), true),
      if (_imageIds.isNotEmpty) ('save', Icons.download_rounded, tr('Lưu ảnh'), true),
      if (ack) post['acked'] == true ? ('ack', Icons.verified_rounded, tr('Đã xác nhận'), false) : ('ack', Icons.task_alt_rounded, tr('Xác nhận đã đọc'), true),
      if (me.admin && onReload != null) ('delete', Icons.delete_outline_rounded, tr('Xoá bài'), true),
    ];
  }

  /// Menu của thẻ: máy tính hiện tại chỗ nháy chuột phải; điện thoại (bấm giữ) hiện bottom sheet.
  Future<void> _menu(BuildContext context, Offset? at) async {
    final pal = Pal.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final pinned = post['pinned'] == true;
    final items = _menuItems();
    if (items.isEmpty) return;
    const red = Color(0xFFE5484D);
    final String? v;
    if (at != null) {
      final box = Overlay.of(context).context.findRenderObject() as RenderBox;
      v = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & box.size),
        items: [
          for (final (id, icon, label, on) in items)
            PopupMenuItem(
              value: id,
              enabled: on,
              child: ListTile(
                dense: true,
                enabled: on,
                leading: Icon(icon, color: id == 'delete' ? red : null),
                title: Text(label, style: id == 'delete' ? const TextStyle(color: red) : null),
              ),
            ),
        ],
      );
    } else {
      v = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: pal.surface,
        builder: (s) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (id, icon, label, on) in items)
                ListTile(
                  enabled: on,
                  leading: Icon(icon, color: id == 'delete' ? red : null),
                  title: Text(label, style: id == 'delete' ? const TextStyle(color: red) : null),
                  onTap: on ? () => Navigator.pop(s, id) : null,
                ),
            ],
          ),
        ),
      );
    }
    if (v == null || !context.mounted) return;
    try {
      switch (v) {
        case 'edit':
          onEdit?.call();
        case 'pin':
          await api.patch('/api/posts/${post['id']}', {'pinned': !pinned});
          onReload?.call();
        case 'save':
          await saveBangTinImages(context, api, _imageIds);
        case 'ack':
          await api.post('/api/posts/${post['id']}/ack');
          onChanged({...post, 'acked': true, 'read': true});
          messenger.showSnackBar(toast(Text(tr('Đã xác nhận đã đọc'))));
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text(tr('Xoá bài viết này?')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Xoá'))),
              ],
            ),
          );
          if (ok != true) return;
          await api.delete('/api/posts/${post['id']}');
          onReload?.call();
      }
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = post;
    final mine = (p['author'] as Map?)?['id'] == me.id;
    final hasMenu = _menuItems().isNotEmpty;
    final needAck = p['require_ack'] == true && p['acked'] != true && !mine;
    final unread = p['read'] != true;
    final images = [for (final i in (p['images'] as List? ?? const [])) '$i'];
    if (images.isEmpty && p['cover'] != null) images.add('${p['cover']}');
    final files = ((p['attachments'] as num?)?.toInt() ?? 0) - ((p['image_count'] as num?)?.toInt() ?? 0);
    final deadline = (p['ack_deadline'] as num?)?.toInt();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: feedCard(context, border: selected ? pal.accent : (needAck ? _orange.withValues(alpha: .7) : null)),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onOpen(),
          onSecondaryTapUp: hasMenu ? (d) => _menu(context, d.globalPosition) : null,
          onLongPress: hasMenu ? () => _menu(context, null) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                child: PostHeader(
                  post: p,
                  me: me,
                  trailing: unread
                      ? Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
                        )
                      : null,
                ),
              ),
              if (needAck)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: _orange.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Icon(Icons.task_alt_rounded, size: 17, color: _orange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          deadline == null ? tr('Cần xác nhận') : tr('Xác nhận trước {0}', [bangTinTime(deadline)]),
                          style: const TextStyle(color: _orange, fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: _orange, visualDensity: VisualDensity.compact),
                        onPressed: () => onOpen(),
                        child: Text(tr('Xem chi tiết')),
                      ),
                    ],
                  ),
                ),
              PostBody(post: p, onMore: () => onOpen()),
            if (p['poll'] is Map)
              PollView(api: api, postId: '${p['id']}', poll: Map<String, dynamic>.from(p['poll'] as Map), onChanged: (pl) => onChanged({...p, 'poll': pl})),
              if (images.isNotEmpty) ...[
                const SizedBox(height: 10),
                ImageGallery(
                  api: api,
                  ids: images.take(4).toList(),
                  total: images.length < 2 ? images.length : (p['image_count'] as num?)?.toInt() ?? images.length,
                  // Ô "+N" (ảnh cuối khi bài nhiều hơn 4 ảnh): mở chi tiết bài với đủ ảnh; ô khác mở trình xem ảnh (Sếp).
                onTap: (i) => i == 3 && ((p['image_count'] as num?)?.toInt() ?? images.length) > 4 ? onOpen(photos: true) : openBangTinGallery(context, api, images, i),
                ),
              ],
              if (files > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Icon(Icons.attach_file_rounded, size: 16, color: pal.sub),
                      const SizedBox(width: 4),
                      Text(tr('{0} tệp đính kèm', ['$files']), style: TextStyle(color: pal.sub, fontSize: 13.5)),
                    ],
                  ),
                ),
              PostActions(
                post: p,
                mine: mine,
                likeKey: likeKey,
                onReact: (e) => _react(context, e),
                onComment: () => onOpen(comment: true),
                onViews: onViews,
                onShare: () async {
                  final n = await shareBangTinPost(context, api, p);
                  if (n != null) onChanged({...p, 'shares': n});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ô "Bạn có gì muốn chia sẻ hôm nay?" ở đầu bảng tin.
class ComposerCard extends StatelessWidget {
  const ComposerCard({super.key, required this.me, required this.onCompose, this.trailing});
  final BangTinMe me;
  final void Function({bool photos, bool background}) onCompose;

  /// Nút thêm ở cuối ô (điện thoại, tab Bảng tin: menu ⋮ thay thanh trên).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 7),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: feedCard(context),
      child: Row(
        children: [
          AvatarRing(userId: me.id, name: me.name, size: 48, gold: me.admin),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () => onCompose(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(26)),
                child: Text(
                  tr('Bạn có gì muốn chia sẻ hôm nay?'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: pal.sub, fontSize: 15.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ComposerIcon(
            tooltip: tr('Ảnh / video'),
            icon: Icons.photo_library_rounded,
            colors: const [Color(0xFF34C77B), Color(0xFF0FA968)],
            onTap: () => onCompose(photos: true),
          ),
          // Có menu ⋮ (điện thoại): bỏ nút nền màu cho rộng chỗ, nền màu vẫn chọn được trong "Tạo bài viết".
          if (trailing == null) ...[
            const SizedBox(width: 6),
            _ComposerIcon(
              tooltip: tr('Nền màu'),
              icon: Icons.palette_rounded,
              colors: const [Color(0xFFFF7EB3), Color(0xFF9B5CFF)],
              onTap: () => onCompose(background: true),
            ),
          ] else
            trailing!,
        ],
      ),
    );
  }
}

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({required this.tooltip, required this.icon, required this.colors, required this.onTap});
  final String tooltip;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(colors: [for (final c in colors) c.withValues(alpha: .16)]),
          border: Border.all(color: colors.last.withValues(alpha: .35)),
        ),
        child: Icon(icon, color: colors.last, size: 24),
      ),
    ),
  );
}
