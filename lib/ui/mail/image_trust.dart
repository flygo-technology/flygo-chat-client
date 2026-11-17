// Thư: ảnh từ mạng mặc định không tải (người gửi không biết bạn đã mở thư). Người dùng cho hiện theo từng thư,
// hoặc "luôn hiện" theo người gửi; danh sách người gửi lưu trên máy (mail/image_senders.json).
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class MailImageTrust {
  MailImageTrust._();
  static final senders = <String>{};
  static bool _loaded = false;

  static final _remote = RegExp(r'''<img[^>]+src\s*=\s*["']?https?://''', caseSensitive: false);

  /// Thư có ảnh lấy từ mạng (ảnh dán trong thư thì luôn hiện, không tính).
  static bool hasRemoteImages(String html) => _remote.hasMatch(html);

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/mail/image_senders.json');

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (f.existsSync()) senders.addAll((jsonDecode(await f.readAsString()) as List).map((e) => '$e'.toLowerCase()));
    } catch (_) {}
  }

  static Future<void> trust(String sender) async {
    senders.add(sender.toLowerCase());
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(senders.toList()));
    } catch (_) {}
  }
}
