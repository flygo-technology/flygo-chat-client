// Drive: màu, biểu tượng loại tệp, định dạng dung lượng / ngày, ảnh thu nhỏ. Cùng bảng màu với bản web Drive.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../i18n/i18n.dart';
import 'api.dart';

/// Bảng màu Drive (sáng / tối), giống token của bản web.
class DriveLook {
  const DriveLook._(this.dark);
  final bool dark;
  static DriveLook of(BuildContext c) => DriveLook._(Theme.of(c).brightness == Brightness.dark);

  Color get bg => dark ? const Color(0xFF12151C) : const Color(0xFFF4F6FB);
  Color get surface => dark ? const Color(0xFF1B1F28) : Colors.white;
  Color get surface2 => dark ? const Color(0xFF232835) : const Color(0xFFEEF2F9);
  Color get line => dark ? const Color(0xFF2E3442) : const Color(0xFFE1E5EE);
  Color get text => dark ? const Color(0xFFE6E9F0) : const Color(0xFF1D2330);
  Color get muted => dark ? const Color(0xFF9AA3B5) : const Color(0xFF5D6577);
  Color get accent => dark ? const Color(0xFF6EA8FF) : const Color(0xFF1F6FEB);
  Color get accentSoft => dark ? const Color(0xFF233A63) : const Color(0xFFDBE8FF);
  Color get accentText => dark ? const Color(0xFFA9C8FF) : const Color(0xFF0B4BBD);
  Color get hover => dark ? const Color(0xFF262C39) : const Color(0xFFE9EDF5);
  Color get sel => dark ? const Color(0xFF2A3F66) : const Color(0xFFD6E4FF);
  Color get danger => dark ? const Color(0xFFFF6B6B) : const Color(0xFFC62828);
  Color get ok => dark ? const Color(0xFF5CC98A) : const Color(0xFF1E7B45);
  Color get warn => const Color(0xFFF0B429);
  Color get folder => dark ? const Color(0xFFAAB4C6) : const Color(0xFF5F6B7F);
}

enum DriveKind { folder, doc, sheet, slide, pdf, image, video, audio, archive, code, text, other }

DriveKind kindOf(DriveItem it) {
  if (it.dir) return DriveKind.folder;
  final m = it.mime, e = it.ext;
  if (m.startsWith('image/') || const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'}.contains(e)) return DriveKind.image;
  if (m.startsWith('video/') || const {'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'}.contains(e)) return DriveKind.video;
  if (m.startsWith('audio/') || const {'mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'}.contains(e)) return DriveKind.audio;
  if (m == 'application/pdf' || e == 'pdf') return DriveKind.pdf;
  if (const {'doc', 'docx', 'odt', 'rtf'}.contains(e) || m.contains('wordprocessing')) return DriveKind.doc;
  if (const {'xls', 'xlsx', 'ods', 'csv'}.contains(e) || m.contains('spreadsheet')) return DriveKind.sheet;
  if (const {'ppt', 'pptx', 'odp'}.contains(e) || m.contains('presentation')) return DriveKind.slide;
  if (const {'zip', 'rar', '7z', 'gz', 'tar'}.contains(e)) return DriveKind.archive;
  if (const {'js', 'ts', 'dart', 'py', 'json', 'html', 'css', 'sh', 'go', 'java', 'kt', 'swift', 'xml', 'yaml', 'yml', 'sql'}.contains(e)) return DriveKind.code;
  if (m.startsWith('text/') || const {'txt', 'md', 'log'}.contains(e)) return DriveKind.text;
  return DriveKind.other;
}

/// Mở bằng OnlyOffice (webview).
bool isOffice(DriveItem it) => const {DriveKind.doc, DriveKind.sheet, DriveKind.slide}.contains(kindOf(it));

/// Xem trực tiếp trong app.
bool canPreview(DriveItem it) => const {DriveKind.image, DriveKind.video, DriveKind.audio, DriveKind.pdf, DriveKind.text, DriveKind.code}.contains(kindOf(it));

(IconData, Color) kindIcon(DriveKind k, DriveLook l) => switch (k) {
      DriveKind.folder => (Icons.folder_rounded, l.folder),
      DriveKind.doc => (Icons.description_rounded, const Color(0xFF2B579A)),
      DriveKind.sheet => (Icons.table_chart_rounded, const Color(0xFF1E7B45)),
      DriveKind.slide => (Icons.slideshow_rounded, const Color(0xFFC4501F)),
      DriveKind.pdf => (Icons.picture_as_pdf_rounded, const Color(0xFFD93025)),
      DriveKind.image => (Icons.image_rounded, const Color(0xFF8E44AD)),
      DriveKind.video => (Icons.movie_rounded, const Color(0xFFD81B60)),
      DriveKind.audio => (Icons.music_note_rounded, const Color(0xFF00897B)),
      DriveKind.archive => (Icons.folder_zip_rounded, const Color(0xFF6D4C41)),
      DriveKind.code => (Icons.code_rounded, const Color(0xFF455A64)),
      DriveKind.text => (Icons.article_rounded, const Color(0xFF455A64)),
      DriveKind.other => (Icons.insert_drive_file_rounded, const Color(0xFF5F6B7F)),
    };

String kindName(DriveKind k) => switch (k) {
      DriveKind.folder => tr('Thư mục'),
      DriveKind.doc => tr('Tài liệu'),
      DriveKind.sheet => tr('Bảng tính'),
      DriveKind.slide => tr('Bản trình bày'),
      DriveKind.pdf => 'PDF',
      DriveKind.image => tr('Ảnh'),
      DriveKind.video => 'Video',
      DriveKind.audio => tr('Âm thanh'),
      DriveKind.archive => tr('Tệp nén'),
      DriveKind.code => tr('Mã nguồn'),
      DriveKind.text => tr('Văn bản'),
      DriveKind.other => tr('Tệp'),
    };

/// Ô biểu tượng loại tệp: thư mục là hình thư mục, tệp là ô màu bo góc.
class KindBadge extends StatelessWidget {
  const KindBadge(this.item, {super.key, this.size = 36});
  final DriveItem item;
  final double size;
  @override
  Widget build(BuildContext context) {
    final l = DriveLook.of(context);
    final (icon, color) = kindIcon(kindOf(item), l);
    if (item.dir) return SizedBox(width: size, height: size, child: Icon(icon, color: color, size: size * .82));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * .22)),
      child: Icon(icon, color: Colors.white, size: size * .58),
    );
  }
}

String fmtSize(int b) {
  if (b <= 0) return '0 B';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble(), i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final s = i == 0 || v >= 100 ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
  return '$s ${u[i]}';
}

String fmtDate(int sec, {DateTime? now}) {
  if (sec <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  final n = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day), today = DateTime(n.year, n.month, n.day);
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (day == today) return hm;
  if (today.difference(day).inDays == 1) return tr('Hôm qua');
  if (d.year == n.year) return tr('{0} thg {1}', ['${d.day}', '${d.month}']);
  return tr('{0} thg {1}, {2}', ['${d.day}', '${d.month}', '${d.year}']);
}

/// Ảnh thu nhỏ có bộ nhớ đệm trên đĩa (theo id + etag). Không có ảnh thì hiện biểu tượng loại.
class DriveThumb extends StatefulWidget {
  const DriveThumb({super.key, required this.api, required this.item, this.size = 256, this.fit = BoxFit.cover, this.fallbackSize = 48});
  final DriveApi api;
  final DriveItem item;
  final int size;
  final BoxFit fit;
  final double fallbackSize;
  @override
  State<DriveThumb> createState() => _DriveThumbState();
}

class _DriveThumbState extends State<DriveThumb> {
  static final _mem = <String, File?>{};
  static Directory? _dir;
  File? _file;

  String get _key => md5.convert('${widget.api.base}|${widget.item.id}|${widget.item.etag}|${widget.size}'.codeUnits).toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DriveThumb old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id || old.item.etag != widget.item.etag) _load();
  }

  Future<void> _load() async {
    final it = widget.item;
    if (!it.preview || it.id <= 0) return;
    final key = _key;
    if (_mem.containsKey(key)) {
      if (mounted) setState(() => _file = _mem[key]);
      return;
    }
    try {
      _dir ??= Directory('${(await getTemporaryDirectory()).path}/drive_thumbs');
      final f = File('${_dir!.path}/$key.img');
      if (!await f.exists()) {
        final b = await widget.api.thumb(it.id, widget.size);
        if (b == null) {
          _mem[key] = null;
          return;
        }
        await f.parent.create(recursive: true);
        await f.writeAsBytes(b, flush: true);
      }
      _mem[key] = f;
      if (mounted) setState(() => _file = f);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final f = _file;
    if (f == null) return Center(child: KindBadge(widget.item, size: widget.fallbackSize));
    return Image.file(f, fit: widget.fit, gaplessPlayback: true, errorBuilder: (_, _, _) => Center(child: KindBadge(widget.item, size: widget.fallbackSize)));
  }
}
