// Bảng tin: bấm ảnh mở trình xem ảnh toàn màn hình của chat (showGallery): vuốt / ← → giữa các ảnh của bài,
// phóng to, Esc / X / vuốt xuống / chạm ra ngoài để đóng. Ảnh tải kèm vé Flygo ID như trong bảng tin.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../media_view.dart';
import '../theme.dart';
import 'api.dart';

/// Mở các ảnh [fileIds] của một bài, bắt đầu ở ảnh [index].
Future<void> openBangTinGallery(BuildContext context, BangTinApi api, List<String> fileIds, int index) async {
  if (fileIds.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final images = [for (final id in fileIds) ChatImage(image: api.image(id))];
    // Trình xem cần một tin chat: dùng tin giả chưa gửi, nên không hiện sửa / chuyển tiếp / tải xuống của chat.
    final post = MmPost({'id': 'bang-tin', 'channel_id': '', 'user_id': '', 'message': '', 'create_at': 0});
    await showGallery(context, post, images, index.clamp(0, images.length - 1));
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

/// Đuôi tệp theo nội dung ảnh (máy chủ không gửi tên tệp trong bảng tin).
String _ext(Uint8List b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
  if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'webp';
  return 'jpg';
}

/// "Lưu ảnh" (menu bấm giữ / chuột phải của bài): lưu mọi ảnh của bài vào thư viện ảnh (điện thoại) hoặc Tải về
/// (máy tính), qua saveImageFile dùng chung với trình xem ảnh. Lỗi thì báo rõ lý do (saveErrorText).
Future<void> saveBangTinImages(BuildContext context, BangTinApi api, List<String> fileIds) async {
  final messenger = ScaffoldMessenger.of(context);
  var ok = 0;
  String? where, error;
  for (final id in fileIds) {
    final Uint8List bytes;
    try {
      bytes = await api.bytes(id);
    } catch (e) {
      error ??= tr('Không tải được ảnh từ Bảng tin: {0}', ['$e']);
      continue;
    }
    try {
      final tmp = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}bang-tin');
      await tmp.create(recursive: true);
      final f = File('${tmp.path}${Platform.pathSeparator}bang-tin-$id.${_ext(bytes)}');
      await f.writeAsBytes(bytes);
      where = await saveImageFile(f.path);
      ok++;
    } catch (e) {
      error ??= tr('Không lưu được ảnh: {0}', [saveErrorText(e)]);
    }
  }
  if (fileIds.isEmpty) {
    messenger.showSnackBar(toast(Text(tr('Bài này không có ảnh'))));
    return;
  }
  // Máy tính: saveImageFile trả đường dẫn tệp; báo thư mục chứa nó. Điện thoại: tên album.
  final place = where == null ? '' : (where.contains(Platform.pathSeparator) ? File(where).parent.path : where);
  final saved = ok == 0 ? null : tr('Đã lưu {0} ảnh vào {1}', [ok, place]);
  messenger.showSnackBar(toast(Text([?saved, ?error].join('\n'))));
}
