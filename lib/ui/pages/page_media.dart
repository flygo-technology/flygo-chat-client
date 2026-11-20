import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../drive/pickers.dart' show pickFromDrive;
import '../meet/meet_home.dart' show meetToast;
import 'pages_api.dart';

// Chọn ảnh / nhạc cho trang (Chào mừng, Chờ lượt, ảnh đại diện video): từ Drive (thư viện media của công ty) hoặc từ máy,
// rồi gửi lên relay; trả về đường dẫn tương đối để lưu vào nội dung trang.

const imageExts = ['png', 'jpg', 'jpeg', 'webp', 'gif'];
const audioExts = ['mp3', 'm4a', 'ogg', 'wav'];

Future<String?> pickPageMedia(BuildContext context, CallService call, {required bool image}) async {
  final exts = image ? imageExts : audioExts;
  final src = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF2D2E31),
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(image ? tr('Chọn ảnh') : tr('Chọn nhạc'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_outlined, color: Colors.white),
          title: Text(tr('Từ Drive (thư viện của công ty)'), style: const TextStyle(color: Colors.white)),
          onTap: () => Navigator.pop(ctx, 'drive'),
        ),
        ListTile(
          leading: const Icon(Icons.folder_open_rounded, color: Colors.white),
          title: Text(tr('Từ máy này'), style: const TextStyle(color: Colors.white)),
          onTap: () => Navigator.pop(ctx, 'device'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (src == null || !context.mounted) return null;
  try {
    File? f;
    String name = '';
    if (src == 'drive') {
      final r = await pickFromDrive(context, remoteOnly: true, extensions: exts, single: true);
      final it = r?.remote.firstOrNull;
      final s = r?.session;
      if (it == null || s == null) return null;
      name = it.name;
      final dir = Directory('${(await getTemporaryDirectory()).path}/meet-media');
      await dir.create(recursive: true);
      f = await s.api.download(it.path, File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_${it.name}'));
    } else {
      final r = (await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: exts)).firstOrNull;
      if (r?.path == null) return null;
      name = r!.name;
      f = File(r.path!);
    }
    if (context.mounted) meetToast(context, tr('Đang tải lên…'));
    return await PagesApi(call).uploadAsset(f, name);
  } catch (e) {
    if (context.mounted) meetToast(context, tr('Không tải lên được: {0}', [e]));
    return null;
  }
}
