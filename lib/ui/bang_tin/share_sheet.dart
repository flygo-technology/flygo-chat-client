// Bảng tin: chia sẻ bài vào cuộc trò chuyện. App gửi tin bằng phiên chat của người chia sẻ (props.flygo_app /
// flygo_post: tin hiện nút "Mở bài trong Bảng tin"), rồi báo server để đếm lượt chia sẻ.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'api.dart';

/// Mở hộp chia sẻ [post]. Trả về số lượt chia sẻ mới (null nếu không chia sẻ).
Future<int?> shareBangTinPost(BuildContext context, BangTinApi api, Map<String, dynamic> post) => showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.of(context).surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => FractionallySizedBox(heightFactor: .8, child: _ShareSheet(api: api, post: post)),
    );

/// Nội dung tin chia sẻ (chữ cho app cũ / ứng dụng chat khác; app mới hiện thêm nút mở bài).
String bangTinShareText(Map<String, dynamic> post, String note) {
  final title = '${post['title'] ?? ''}'.trim();
  final ex = '${post['excerpt'] ?? ''}'.trim();
  final author = '${(post['author'] as Map?)?['name'] ?? ''}';
  return [
    if (note.trim().isNotEmpty) note.trim(),
    '> **${tr('Bảng tin')}** · $author',
    if (title.isNotEmpty) '> **$title**',
    if (ex.isNotEmpty) '> $ex',
  ].join('\n');
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.api, required this.post});
  final BangTinApi api;
  final Map<String, dynamic> post;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _picked = <String>{};
  final _note = TextEditingController();
  String _q = '';
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final text = bangTinShareText(widget.post, _note.text);
      for (final id in _picked) {
        await app.send(id, text, props: {'flygo_app': kBangTinApp, 'flygo_post': '${widget.post['id']}', 'flygo_kind': 'share'});
      }
      final r = await widget.api.post('/api/posts/${widget.post['id']}/share', {'channels': _picked.toList()});
      nav.pop((r['shares'] as num?)?.toInt());
      messenger.showSnackBar(toast(Text(tr('Đã chia sẻ tới {0} cuộc trò chuyện', [_picked.length]))));
    } catch (e) {
      if (mounted) setState(() => _sending = false);
      messenger.showSnackBar(toast(Text(tr('Không chia sẻ được: {0}', ['$e']))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final q = _q.trim().toLowerCase();
    final chats = app.chats.where((c) => q.isEmpty || c.title.toLowerCase().contains(q)).take(80).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
        child: Row(children: [
          Expanded(child: Text(tr('Chia sẻ bài viết'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text))),
          IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _note,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: tr('Viết vài lời (không bắt buộc)'),
            isDense: true,
            filled: true,
            fillColor: pal.surface2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: tr('Tìm cuộc trò chuyện'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: chats.length,
          itemBuilder: (_, i) {
            final c = chats[i];
            final on = _picked.contains(c.channel.id);
            return CheckboxListTile(
              value: on,
              onChanged: (v) => setState(() {
                if (v == true && _picked.length < 5) {
                  _picked.add(c.channel.id);
                } else {
                  _picked.remove(c.channel.id);
                }
              }),
              secondary: Avatar(userId: c.avatarUserId, name: c.title, size: 36, status: false, channel: c.channel),
              title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _picked.isEmpty || _sending ? null : _send,
              icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
              label: Text(_picked.isEmpty ? tr('Chọn cuộc trò chuyện') : tr('Gửi tới {0} cuộc trò chuyện', ['${_picked.length}'])),
            ),
          ),
        ),
      ),
    ]);
  }
}
