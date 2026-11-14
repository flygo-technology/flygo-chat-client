import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'file_card.dart';
import 'media_view.dart';
import 'theme.dart';

/// Tệp trợ lý gửi giữa câu trả lời (runner 0.6.87: bước kind "files" có danh sách tin chứa tệp): ảnh / tệp hiện ngay
/// tại chỗ trong dòng thời gian thay vì một tin riêng nằm trên câu trả lời (tin đó mang props.flygo_agent_inline, bị ẩn
/// khỏi danh sách chat). Chưa có tin trong máy thì hiện một dòng nhỏ.
class AgentInlineFiles extends StatelessWidget {
  final String channelId;
  final List<String> postIds;
  final String label;
  const AgentInlineFiles({super.key, required this.channelId, required this.postIds, required this.label});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final posts = [for (final id in postIds) app.findPost(channelId, id)].whereType<MmPost>().toList();
    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.attach_file_rounded, size: 15, color: pal.sub),
          const SizedBox(width: 6),
          Flexible(child: Text(label.isEmpty ? tr('Đã gửi tệp') : label, style: TextStyle(fontSize: 13, color: pal.sub))),
        ]),
      );
    }
    final children = <Widget>[];
    for (final p in posts) {
      final caption = p.message.trim();
      if (caption.isNotEmpty) {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(caption, style: TextStyle(fontSize: 14, color: pal.text))));
      }
      final images = imagesOf(p);
      if (images.isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ChatMedia(post: p, images: images, maxWidth: double.infinity),
        ));
      }
      for (final f in p.files.where((f) => !f.isImage)) {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: FileCard(file: f, remotePath: (p.props['flygo_file_paths'] as Map?)?[f.id] as String?)));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
