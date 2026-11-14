// Nháy phải / bấm giữ vào ảnh, tệp, liên kết ở trang Hình ảnh / Tệp tin / Liên kết (cài đặt chat) và cột phải của chat
// với trợ lý: ảnh "Sao chép, Mở thư mục, Copy đường dẫn"; tệp "Mở thư mục, Copy đường dẫn"; liên kết "Sao chép, Mở".
// "Mở thư mục" chỉ có trên máy tính (tải về Tải về nếu chưa có bản trên máy rồi chọn sẵn tệp trong Finder / Explorer).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'file_card.dart';
import 'media_view.dart';
import 'open_file.dart';
import 'theme.dart';

/// Đường dẫn để "Copy đường dẫn": trên máy chạy bot (tệp trợ lý gửi), không có thì bản trên máy này, không nữa thì link tải.
String filePathToCopy(AppState app, MmFile f, MmPost? post) =>
    (post?.props['flygo_file_paths'] as Map?)?[f.id] as String? ?? localCopyOf(f) ?? app.api.fileUrl(f.id);

Future<void> showMediaMenu(BuildContext context, Offset at, {MmFile? file, MmPost? post, String? link}) async {
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final image = file?.isImage == true;
  PopupMenuItem<String> item(String v, IconData icon, String label) => PopupMenuItem(
    value: v,
    height: 44,
    child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]),
  );
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    items: [
      if (link != null) ...[item('copy_link', Icons.copy_rounded, tr('Sao chép')), item('open_link', Icons.open_in_new_rounded, tr('Mở'))],
      if (file != null) ...[
        if (image) item('copy_image', Icons.copy_rounded, tr('Sao chép')),
        if (isDesktop) item('reveal', Icons.folder_open_rounded, tr('Mở thư mục')),
        item('copy_path', Icons.link_rounded, tr('Copy đường dẫn')),
      ],
    ],
  );
  if (v == null || !context.mounted) return;
  void done(String t) => messenger.showSnackBar(toast(Text(t)));
  switch (v) {
    case 'copy_link':
      await Clipboard.setData(ClipboardData(text: link!));
      done(tr('Đã sao chép'));
    case 'open_link':
      await launchUrl(Uri.parse(link!), mode: LaunchMode.externalApplication);
    case 'copy_image':
      await copyChatImage(context, ChatImage(file: file));
    case 'reveal':
      try {
        await revealInFileManager(await saveFileLocally(app, file!));
      } catch (_) {
        done(tr('Không tải được file. Kiểm tra kết nối mạng.'));
      }
    case 'copy_path':
      await Clipboard.setData(ClipboardData(text: filePathToCopy(app, file!, post)));
      done(tr('Đã sao chép'));
  }
}

/// Vùng bấm giữ (điện thoại) / nháy phải (máy tính) mở [showMediaMenu]; chạm thường giữ nguyên hành vi của [child].
class MediaMenuArea extends StatelessWidget {
  final Widget child;
  final MmFile? file;
  final MmPost? post;
  final String? link;
  const MediaMenuArea({super.key, required this.child, this.file, this.post, this.link});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPressStart: (d) => showMediaMenu(context, d.globalPosition, file: file, post: post, link: link),
    onSecondaryTapDown: (d) => showMediaMenu(context, d.globalPosition, file: file, post: post, link: link),
    child: child,
  );
}
