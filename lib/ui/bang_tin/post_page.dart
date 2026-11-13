// Bảng tin: xem một bài (mở là tính "đã xem"), xác nhận đã đọc, cảm xúc, bình luận (trả lời một tầng).
// Tác giả và quản trị Bảng tin: sửa, xoá, ghim, xem ai đã xem / đã xác nhận.
// Máy tính: nhúng ở cột phải của Bảng tin (embedded); điện thoại: trang riêng.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../common.dart';
import '../open_file.dart';
import '../theme.dart';
import 'api.dart';
import 'bang_tin_page.dart';
import 'editor_page.dart';
import 'feed_widgets.dart';
import 'gallery.dart';
import 'poll_widgets.dart';
import 'reactions.dart';
import 'share_sheet.dart';
import 'receipts_page.dart';

class BangTinPostPage extends StatefulWidget {
  const BangTinPostPage({
    super.key,
    required this.api,
    required this.me,
    required this.postId,
        this.embedded = false,
    this.focusComment = false,
    this.onClose,
    this.onChanged,
    this.onDeleted,
    this.onViews,
  });
  final BangTinApi api;
  final BangTinMe me;
  final String postId;

  /// Nằm trong cột phải của Bảng tin (máy tính): nút đóng thay nút quay lại.
    final bool embedded;

  /// Mở xong thì đặt con trỏ vào ô bình luận.
  final bool focusComment;
  final VoidCallback? onClose, onDeleted;

  /// Bài thay đổi (cảm xúc, xác nhận): báo để thẻ trong bảng tin cập nhật theo.
  final ValueChanged<Map<String, dynamic>>? onChanged;

  /// Cột phải (máy tính): chuyển cột sang danh sách "đã xem".
  final VoidCallback? onViews;

  @override
  State<BangTinPostPage> createState() => _BangTinPostPageState();
}

class _BangTinPostPageState extends State<BangTinPostPage> {
  Map<String, dynamic>? _post;
  List<Map<String, dynamic>> _comments = const [];
  String? _error;
  bool _sending = false, _acking = false;
  final _input = TextEditingController();
  final _focus = FocusNode();
  Map<String, dynamic>? _replyTo, _editing;

  /// Ảnh đính kèm bình luận đang soạn (đã tải lên: {id, name, mime, size}); số ảnh đang tải lên.
  List<Map<String, dynamic>> _cfiles = [];
  int _cuploading = 0;

  BangTinApi get api => widget.api;
  String get _pid => widget.postId;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.focusComment && mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  static List<Map<String, dynamic>> _maps(Object? v) => [
    for (final x in (v as List? ?? const []))
      if (x is Map) Map<String, dynamic>.from(x),
  ];

  Future<void> _load() async {
    try {
      final r = await Future.wait([api.get('/api/posts/$_pid'), api.get('/api/posts/$_pid/comments')]);
      if (!mounted) return;
      setState(() {
        _post = Map<String, dynamic>.from(r[0]['post'] as Map);
        _post!['comments'] = _maps(r[1]['comments']).where((c) => c['deleted'] != true && c['hidden'] != true).length;
        _comments = _maps(r[1]['comments']);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(toast(Text(s)));

  Future<void> _ack() async {
    setState(() => _acking = true);
    try {
      await api.post('/api/posts/$_pid/ack');
      setState(() => _post = {..._post!, 'acked': true});
      widget.onChanged?.call({'id': _pid, 'acked': true, 'read': true});
      _toast(tr('Đã xác nhận đã đọc'));
    } catch (e) {
      _toast('$e');
    }
    if (mounted) setState(() => _acking = false);
  }

  Future<void> _react(String target, String emoji, bool on) async {
    try {
      final path = '/api/$target/reactions${on ? '' : '/${Uri.encodeComponent(emoji)}'}';
      final r = on ? await api.post(path, {'emoji': emoji}) : await api.delete(path);
      setState(() {
        if (target.startsWith('posts/')) {
          _post = {..._post!, ...r};
          widget.onChanged?.call({'id': _pid, ...r});
        } else {
          final id = target.split('/').last;
          _comments = [
            for (final c in _comments) c['id'] == id ? {...c, ...r} : c,
          ];
        }
      });
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _pickReaction(String target, List<String> mine) async {
    final pal = Pal.of(context);
    final e = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: pal.surface,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            children: [
              for (final q in kReactionKinds.map((k) => k.emoji))
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => Navigator.pop(c, q),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: mine.contains(q) ? pal.chipSelBg : null),
                    child: Text(q, style: const TextStyle(fontSize: 30)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (e != null) _react(target, e, !mine.contains(e));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if ((text.isEmpty && (_cfiles.isEmpty || _editing != null)) || _sending || _cuploading > 0) return;
    setState(() => _sending = true);
    try {
      if (_editing != null) {
        final r = await api.patch('/api/comments/${_editing!['id']}', {'body': text});
        final c = Map<String, dynamic>.from(r['comment'] as Map);
        setState(() => _comments = [for (final x in _comments) x['id'] == c['id'] ? c : x]);
      } else {
        final r = await api.post('/api/posts/$_pid/comments', {
          'body': text,
          if (_replyTo != null) 'parent': _replyTo!['id'],
          if (_cfiles.isNotEmpty) 'files': [for (final f in _cfiles) f['id']],
        });
        setState(() => _comments = [..._comments, Map<String, dynamic>.from(r['comment'] as Map)]);
      }
      _input.clear();
      setState(() => (_replyTo = null, _editing = null, _cfiles = []));
    } catch (e) {
      _toast('$e');
    }
    if (mounted) setState(() => _sending = false);
  }

  /// Nút ảnh bên trái khung bình luận (Sếp): chọn một hoặc nhiều ảnh, tải lên ngay, tối đa 10.
  Future<void> _pickCommentImages() async {
    final picked = await pickFilesOrReport(context, type: FileType.image);
    for (final f in picked) {
      if (_cfiles.length + _cuploading >= 10) {
        _toast(tr('Tối đa 10 ảnh mỗi bình luận'));
        break;
      }
      if (f.path == null) continue;
      final file = File(f.path!);
      if (await file.length() > 20 * 1024 * 1024) {
        _toast(tr('{0} lớn hơn 20 MB', [f.name]));
        continue;
      }
      setState(() => _cuploading++);
      try {
        final up = await api.upload(f.name, await file.readAsBytes());
        if (mounted) setState(() => _cfiles = [..._cfiles, up]);
      } catch (e) {
        _toast(tr('Không tải được {0}: {1}', [f.name, '$e']));
      } finally {
        if (mounted) setState(() => _cuploading--);
      }
    }
  }

  Future<void> _commentMenu(Map<String, dynamic> c) async {
    final pal = Pal.of(context);
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: pal.surface,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c['deleted'] != true)
              ListTile(leading: const Icon(Icons.add_reaction_outlined), title: Text(tr('Thả cảm xúc')), onTap: () => Navigator.pop(s, 'react')),
            if (c['deleted'] != true) ListTile(leading: const Icon(Icons.reply_rounded), title: Text(tr('Trả lời')), onTap: () => Navigator.pop(s, 'reply')),
            if (c['can_edit'] == true) ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Sửa')), onTap: () => Navigator.pop(s, 'edit')),
            if (c['can_hide'] == true)
              ListTile(
                leading: Icon(c['hidden'] == true ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                title: Text(c['hidden'] == true ? tr('Hiện lại bình luận') : tr('Ẩn bình luận')),
                onTap: () => Navigator.pop(s, 'hide'),
              ),
            if (c['can_delete'] == true)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE5484D)),
                title: Text(tr('Xoá'), style: const TextStyle(color: Color(0xFFE5484D))),
                onTap: () => Navigator.pop(s, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || v == null) return;
    try {
      switch (v) {
        case 'react':
          await _pickReaction('comments/${c['id']}', [for (final e in (c['my_reactions'] as List? ?? const [])) '$e']);
        case 'reply':
          setState(() => (_replyTo = c, _editing = null));
          _focus.requestFocus();
        case 'edit':
          setState(() => (_editing = c, _replyTo = null));
          _input.text = '${c['body']}';
          _focus.requestFocus();
        case 'hide':
          final r = await api.post('/api/comments/${c['id']}/hide', {'hidden': c['hidden'] != true});
          final n = Map<String, dynamic>.from(r['comment'] as Map);
          setState(() => _comments = [for (final x in _comments) x['id'] == n['id'] ? n : x]);
        case 'delete':
          if (await _confirm(tr('Xoá bình luận này?'))) {
            await api.delete('/api/comments/${c['id']}');
            _load();
          }
      }
    } catch (e) {
      _toast('$e');
    }
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Xoá'))),
          ],
        ),
      ) ==
      true;

  Future<void> _menu(String v) async {
    final p = _post!;
    try {
      switch (v) {
        case 'edit':
          final saved = await openBangTinEditor(context, api: api, me: widget.me, post: p);
          if (saved != null) _load();
        case 'pin':
          final r = await api.patch('/api/posts/$_pid', {'pinned': p['pinned'] != true});
          setState(() => _post = Map<String, dynamic>.from(r['post'] as Map));
        case 'delete':
          if (await _confirm(tr('Xoá bài viết này?'))) {
            await api.delete('/api/posts/$_pid');
            if (widget.embedded) {
              widget.onDeleted?.call();
            } else if (mounted) {
              Navigator.of(context).pop();
            }
          }
      }
    } catch (e) {
      _toast('$e');
    }
  }

  /// Ai đã xem: trong cột phải thì chuyển cột; trang riêng (điện thoại) thì bottom sheet.
  void _views(String title) => widget.onViews != null ? widget.onViews!() : showReceiptsSheet(context, api, _pid, title);

  Future<void> _openFile(Map<String, dynamic> f) async {
    try {
      final path = await api.download('${f['id']}', '${f['name']}');
      await openLocalFile(path, mime: '${f['mime']}', title: '${f['name']}');
    } catch (e) {
      _toast(tr('Không mở được tệp: {0}', ['$e']));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = _post;
    return Scaffold(
      backgroundColor: pal.surface,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        backgroundColor: pal.surface,
        title: Text(tr('Bài viết')),
        actions: [
          if (p?['can_see_receipts'] == true)
            IconButton(tooltip: tr('Đã xem'), icon: const Icon(Icons.fact_check_outlined), onPressed: () => _views('${p!['title']}')),
          if (p != null && (p['can_edit'] == true || p['can_delete'] == true || p['can_pin'] == true || widget.me.admin))
            PopupMenuButton<String>(
              onSelected: _menu,
              itemBuilder: (_) => [
                if (p['can_edit'] == true)
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Sửa bài'))),
                  ),
                                // Ghim: người đăng hoặc quản trị; bỏ ghim: chỉ quản trị (Sếp).
                if (p['pinned'] == true ? widget.me.admin : (p['can_pin'] == true || widget.me.admin))
                  PopupMenuItem(
                    value: 'pin',
                    child: ListTile(
                      leading: Icon(p['pinned'] == true ? Icons.push_pin_outlined : Icons.push_pin_rounded),
                      title: Text(p['pinned'] == true ? tr('Bỏ ghim') : tr('Ghim lên đầu')),
                    ),
                  ),
                if (p['can_delete'] == true)
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE5484D)),
                      title: Text(tr('Xoá bài')),
                    ),
                  ),
              ],
            ),
          if (widget.embedded) IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: widget.onClose),
        ],
      ),
      body: p == null
          ? Center(
              child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: TextStyle(color: pal.sub)),
            )
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        Center(
                          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: _content(context, pal, p)),
                        ),
                      ],
                    ),
                  ),
                ),
                _composer(context, pal),
              ],
            ),
    );
  }

  Widget _content(BuildContext context, Pal pal, Map<String, dynamic> p) {
    final author = p['author'] as Map? ?? const {};
    final mine = author['id'] == widget.me.id;
    final files = _maps(p['files']);
    final images = [
      for (final f in files)
        if ('${f['mime']}'.startsWith('image/')) '${f['id']}',
    ];
    if (images.isEmpty && p['cover'] != null) images.add('${p['cover']}');
    final others = files.where((f) => !'${f['mime']}'.startsWith('image/')).toList();
    final stats = p['stats'] as Map?;
    final deadline = (p['ack_deadline'] as num?)?.toInt();
    final expires = (p['expires_at'] as num?)?.toInt();
    final topLevel = _comments.where((c) => c['parent'] == null).toList();
    // Máy tính (cột phải) lẫn điện thoại: chi tiết bài đầy đủ, toàn bộ ảnh, rồi bình luận (Sếp, 12/11).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: PostHeader(post: p, me: widget.me),
        ),
        PostBody(post: p, full: true),
        if (p['poll'] is Map)
          PollView(
            api: api,
            postId: _pid,
            poll: Map<String, dynamic>.from(p['poll'] as Map),
            onChanged: (pl) {
              setState(() => _post = {..._post!, 'poll': pl});
              widget.onChanged?.call({'id': _pid, 'poll': pl});
            },
          ),
        if (images.isNotEmpty) ...[
          const SizedBox(height: 10),
          // Trang bài: hiện đủ mọi ảnh (lưới bảng tin chỉ 4 ô đầu).
          for (var i = 0; i < images.length; i += 4)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
              child: ImageGallery(
                api: api,
                ids: images.skip(i).take(4).toList(),
                total: images.skip(i).take(4).length,
                onTap: (k) => openBangTinGallery(context, api, images, i + k),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (expires != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    p['expired'] == true ? tr('Đã hết hạn') : tr('Hết hạn {0}', [bangTinTime(expires)]),
                    style: TextStyle(color: pal.sub, fontSize: 12.5),
                  ),
                ),
              if (stats != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _views('${p['title'] ?? ''}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(Icons.visibility_outlined, size: 16, color: pal.sub),
                        Text(tr('Đã xem {0}/{1}', ['${stats['read']}', '${stats['targets']}']), style: TextStyle(color: pal.sub, fontSize: 13)),
                        if (p['require_ack'] == true) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.task_alt_rounded, size: 16, color: pal.sub),
                          Text(tr('Đã xác nhận {0}/{1}', ['${stats['acked']}', '${stats['targets']}']), style: TextStyle(color: pal.sub, fontSize: 13)),
                        ],
                        Icon(Icons.chevron_right_rounded, size: 18, color: pal.sub),
                      ],
                    ),
                  ),
                ),
              ],
              for (final f in others)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  elevation: 0,
                  color: pal.surface2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Icon(_fileIcon('${f['mime']}'), color: pal.accentText),
                    title: Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(fileSize((f['size'] as num).toInt())),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => _openFile(f),
                  ),
                ),
              if (p['require_ack'] == true && !mine) ...[const SizedBox(height: 14), _ackCard(pal, p['acked'] == true, deadline)],
            ],
          ),
        ),
        PostActions(
          post: p,
          mine: mine,
          onReact: (e) {
            final cur = (p['my_reactions'] as List? ?? const []).map((x) => '$x').firstOrNull;
            _react('posts/$_pid', e ?? cur ?? '👍', e != null);
          },
          onComment: () => _focus.requestFocus(),
          onViews: () => _views('${p['title'] ?? ''}'),
          onShare: () async {
            final n = await shareBangTinPost(context, api, p);
            if (n != null && mounted) {
              setState(() => _post = {..._post!, 'shares': n});
              widget.onChanged?.call({'id': _pid, 'shares': n});
            }
          },
        ),
        Divider(height: 1, color: pal.divider),
        _commentsBlock(pal, topLevel),
      ],
    );
  }

  Widget _commentsBlock(Pal pal, List<Map<String, dynamic>> topLevel) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          topLevel.isEmpty ? tr('Chưa có bình luận') : tr('Bình luận ({0})', ['${_comments.where((c) => c['deleted'] != true).length}']),
          style: TextStyle(fontWeight: FontWeight.w600, color: topLevel.isEmpty ? pal.sub : pal.text),
        ),
        const SizedBox(height: 8),
        for (final c in topLevel) ...[
          _comment(pal, c, reply: false),
          for (final r in _comments.where((x) => x['parent'] == c['id'])) _comment(pal, r, reply: true),
        ],
      ],
    ),
  );

  Widget _ackCard(Pal pal, bool acked, int? deadline) {
    const orange = Color(0xFFE8833A);
    final late = deadline != null && DateTime.now().millisecondsSinceEpoch > deadline;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (acked ? const Color(0xFF2E9E5B) : orange).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (acked ? const Color(0xFF2E9E5B) : orange).withValues(alpha: .5)),
      ),
      child: acked
          ? Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF2E9E5B)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('Bạn đã xác nhận đã đọc bài này'), style: TextStyle(color: pal.text)),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deadline == null
                      ? tr('Bài này cần bạn xác nhận đã đọc.')
                      : late
                      ? tr('Đã quá hạn xác nhận ({0}). Vui lòng xác nhận ngay.', [bangTinTime(deadline)])
                      : tr('Bài này cần bạn xác nhận đã đọc trước {0}.', [bangTinTime(deadline)]),
                  style: TextStyle(color: pal.text),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: orange),
                  onPressed: _acking ? null : _ack,
                  icon: const Icon(Icons.task_alt_rounded),
                  label: Text(tr('Tôi đã đọc và xác nhận')),
                ),
              ],
            ),
    );
  }

  Widget _reactionRow(Pal pal, String target, Map<String, dynamic> x, {bool small = false}) {
    final reactions = Map<String, dynamic>.from(x['reactions'] as Map? ?? const {});
    final mine = [for (final e in (x['my_reactions'] as List? ?? const [])) '$e'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final e in reactions.entries)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _react(target, e.key, !mine.contains(e.key)),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: small ? 6 : 9, vertical: small ? 2 : 4),
              decoration: BoxDecoration(
                color: mine.contains(e.key) ? pal.chipSelBg : pal.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: mine.contains(e.key) ? pal.accent : pal.divider),
              ),
              child: Text(
                '${e.key} ${e.value}',
                style: TextStyle(fontSize: small ? 12 : 13.5, color: pal.text),
              ),
            ),
          ),
        if (!small)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tr('Thả cảm xúc'),
            icon: Icon(Icons.add_reaction_outlined, color: pal.sub),
            onPressed: () => _pickReaction(target, mine),
          ),
      ],
    );
  }

  Widget _comment(Pal pal, Map<String, dynamic> c, {required bool reply}) {
    final a = c['author'] as Map? ?? const {};
    final hidden = c['hidden'] == true, deleted = c['deleted'] == true;
    final body = '${c['body']}';
    return InkWell(
      onLongPress: () => _commentMenu(c),
      onTap: deleted ? null : () => _commentMenu(c),
      child: Padding(
        padding: EdgeInsets.only(left: reply ? 40 : 0, top: 6, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(userId: '${a['id']}', name: '${a['name']}', size: reply ? 26 : 32, status: false),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
                    decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a['name']}',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: pal.text),
                        ),
                        const SizedBox(height: 2),
                        if (deleted)
                          Text(
                            tr('Bình luận đã bị xoá'),
                            style: TextStyle(color: pal.sub, fontStyle: FontStyle.italic),
                          )
                        else if (hidden && body.isEmpty)
                          Text(
                            tr('Bình luận đã bị ẩn'),
                            style: TextStyle(color: pal.sub, fontStyle: FontStyle.italic),
                          )
                        else ...[
                          if (hidden) Text(tr('Đã ẩn với mọi người'), style: const TextStyle(color: Color(0xFFE8833A), fontSize: 12)),
                          if (body.isNotEmpty) Text(body, style: TextStyle(color: pal.text, fontSize: 14.5, height: 1.35)),
                        ],
                      ],
                    ),
                  ),
                  if ((c['files'] as List? ?? const []).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: CommentImagesRow(api: api, ids: [for (final f in (c['files'] as List)) '${(f as Map)['id']}'], size: reply ? 72 : 88),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 3),
                    child: Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${listTime((c['created_at'] as num).toInt())}${c['edited'] == true ? ' · ${tr('đã sửa')}' : ''}',
                          style: TextStyle(color: pal.sub, fontSize: 12),
                        ),
                        if (!deleted)
                          GestureDetector(
                            onTap: () {
                              setState(() => (_replyTo = c, _editing = null));
                              _focus.requestFocus();
                            },
                            child: Text(
                              tr('Trả lời'),
                              style: TextStyle(color: pal.sub, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        if ((c['reactions'] as Map? ?? const {}).isNotEmpty) _reactionRow(pal, 'comments/${c['id']}', c, small: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context, Pal pal) {
    final banner = _editing != null
        ? tr('Đang sửa bình luận')
        : _replyTo != null
        ? tr('Trả lời {0}', ['${(_replyTo!['author'] as Map?)?['name']}'])
        : null;
    return Material(
      color: pal.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (banner != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(banner, style: TextStyle(color: pal.sub, fontSize: 12.5)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        if (_editing != null) _input.clear();
                        setState(() => (_replyTo = null, _editing = null));
                      },
                    ),
                  ],
                ),
              ),
            // Ảnh đã chọn: một hàng ngang cuộn được, bấm × để bỏ (Sếp).
            if (_cfiles.isNotEmpty || _cuploading > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: CommentImagesRow(
                  api: api,
                  ids: [for (final f in _cfiles) '${f['id']}'],
                  size: 64,
                  pending: _cuploading,
                  onRemove: (id) => setState(() => _cfiles = [..._cfiles]..removeWhere((f) => f['id'] == id)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 6, 8),
              child: Row(
                children: [
                  if (_editing == null)
                    IconButton(
                      tooltip: tr('Thêm ảnh'),
                      icon: Icon(Icons.add_photo_alternate_outlined, color: pal.accentText),
                      onPressed: _sending ? null : _pickCommentImages,
                    ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 5000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: tr('Viết bình luận…'),
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: pal.surface2,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Gửi'),
                    icon: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.send_rounded, color: pal.accent),
                    onPressed: _sending ? null : _send,
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

IconData _fileIcon(String mime) {
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart_outlined;
  if (mime.contains('presentation') || mime.contains('powerpoint')) return Icons.slideshow_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.contains('zip')) return Icons.folder_zip_outlined;
  return Icons.description_outlined;
}

/// Ảnh của bình luận: một hàng ngang cuộn được (Sếp). Bấm ảnh mở trình xem ảnh toàn màn hình (sao chép, tải xuống);
/// [onRemove] (khung soạn): nút × để bỏ ảnh; [pending]: số ô đang tải lên.
class CommentImagesRow extends StatelessWidget {
  const CommentImagesRow({super.key, required this.api, required this.ids, this.size = 88, this.onRemove, this.pending = 0});
  final BangTinApi api;
  final List<String> ids;
  final double size;
  final ValueChanged<String>? onRemove;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ids.length + pending,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          if (i >= ids.length) {
            return Container(
              width: size,
              decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          return Stack(children: [
            GestureDetector(
              onTap: () => openBangTinGallery(context, api, ids, i),
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: size, height: size, child: BangTinImage(api: api, fileId: ids[i]))),
            ),
            if (onRemove != null)
              Positioned(
                right: 2,
                top: 2,
                child: InkWell(
                  onTap: () => onRemove!(ids[i]),
                  child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close_rounded, size: 13, color: Colors.white)),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
