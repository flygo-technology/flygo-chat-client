import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'open_file.dart';
import 'theme.dart';

/// Loại tệp để chọn biểu tượng, màu và nhãn trên thẻ tệp đính kèm.
enum FileKind { pdf, doc, sheet, slide, archive, image, audio, video, code, text, generic }

const _code = {
  'dart', 'js', 'ts', 'tsx', 'jsx', 'mjs', 'py', 'rb', 'go', 'rs', 'java', 'kt', 'swift', 'c', 'h', 'cc', 'cpp', 'hpp', 'cs',
  'php', 'sh', 'bash', 'zsh', 'ps1', 'sql', 'json', 'yaml', 'yml', 'toml', 'xml', 'html', 'htm', 'css', 'scss', 'vue', 'lua',
};

/// Đuôi tệp (chữ thường, không dấu chấm); rỗng nếu không có.
String fileExt(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 || i == name.length - 1 ? '' : name.substring(i + 1).toLowerCase();
}

/// Loại tệp theo đuôi, sau đó theo kiểu MIME.
FileKind fileKindOf(String name, String mime) {
  final e = fileExt(name);
  if (e == 'pdf' || mime == 'application/pdf') return FileKind.pdf;
  if (const {'doc', 'docx', 'odt', 'rtf', 'pages'}.contains(e)) return FileKind.doc;
  if (const {'xls', 'xlsx', 'xlsm', 'ods', 'csv', 'numbers'}.contains(e)) return FileKind.sheet;
  if (const {'ppt', 'pptx', 'odp', 'key'}.contains(e)) return FileKind.slide;
  if (const {'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz'}.contains(e) || mime.contains('zip')) return FileKind.archive;
  if (_code.contains(e)) return FileKind.code;
  if (mime.startsWith('image/')) return FileKind.image;
  if (mime.startsWith('audio/')) return FileKind.audio;
  if (mime.startsWith('video/')) return FileKind.video;
  if (const {'txt', 'md', 'log'}.contains(e) || mime.startsWith('text/')) return FileKind.text;
  return FileKind.generic;
}

/// Biểu tượng + màu của từng loại tệp.
(IconData, Color) fileKindLook(FileKind k) => switch (k) {
      FileKind.pdf => (Icons.picture_as_pdf_rounded, const Color(0xFFE53935)),
      FileKind.doc => (Icons.description_rounded, const Color(0xFF2B6CD9)),
      FileKind.sheet => (Icons.table_chart_rounded, const Color(0xFF1E8E4E)),
      FileKind.slide => (Icons.slideshow_rounded, const Color(0xFFE0662B)),
      FileKind.archive => (Icons.folder_zip_rounded, const Color(0xFFB7791F)),
      FileKind.image => (Icons.image_rounded, const Color(0xFF9B51E0)),
      FileKind.audio => (Icons.audiotrack_rounded, const Color(0xFFE91E63)),
      FileKind.video => (Icons.movie_rounded, const Color(0xFF00A3A3)),
      FileKind.code => (Icons.code_rounded, const Color(0xFF607D8B)),
      FileKind.text => (Icons.article_rounded, const Color(0xFF7C83F2)),
      FileKind.generic => (Icons.insert_drive_file_rounded, const Color(0xFF7C83F2)),
    };

/// Nhãn loại tệp (đã dịch).
String fileKindLabel(FileKind k, String name) => switch (k) {
      FileKind.pdf => tr('Tài liệu PDF'),
      FileKind.doc => tr('Tài liệu Word'),
      FileKind.sheet => tr('Bảng tính'),
      FileKind.slide => tr('Bản trình chiếu'),
      FileKind.archive => tr('Tệp nén'),
      FileKind.image => tr('Ảnh'),
      FileKind.audio => tr('Âm thanh'),
      FileKind.video => tr('Video'),
      FileKind.code => tr('Mã nguồn'),
      FileKind.text => tr('Văn bản'),
      FileKind.generic => fileExt(name).isEmpty ? tr('Tệp không rõ loại') : fileExt(name).toUpperCase(),
    };

/// Kích thước dễ đọc: 512 B, 3.4 KB, 12 KB, 1.5 MB, 2.1 GB (dưới 10 thì một chữ số thập phân).
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = v < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s} ${units[i]}';
}

/// Rút gọn tên dài ở GIỮA, giữ đầu tên và đuôi tệp: "bao-cao-thue-qu…-2026.pdf".
String middleEllipsis(String name, {int max = 36}) {
  if (name.length <= max) return name;
  final e = fileExt(name);
  final tail = e.isEmpty ? 6 : (e.length + 7).clamp(8, max ~/ 2);
  final head = max - tail - 1;
  return '${name.substring(0, head)}…${name.substring(name.length - tail)}';
}

/// Đường dẫn lưu không đè tệp sẵn có: "a.pdf" → "a (1).pdf" → "a (2).pdf"...
String uniqueSavePath(String dir, String name, {bool Function(String path)? exists}) {
  final has = exists ?? (p) => File(p).existsSync() || Directory(p).existsSync();
  final sep = Platform.pathSeparator;
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final e = fileExt(safe);
  final base = e.isEmpty ? safe : safe.substring(0, safe.length - e.length - 1);
  var path = '$dir$sep$safe';
  for (var n = 1; has(path); n++) {
    path = '$dir$sep$base ($n)${e.isEmpty ? '' : '.$e'}';
  }
  return path;
}

/// Tải tệp [file] vào [out], báo tiến độ (đã nhận, tổng).
typedef FileDownloader = Future<File> Function(MmFile file, File out, void Function(int got, int total) onProgress);

/// Thẻ tệp đính kèm (không phải ảnh / video xem trước được): biểu tượng theo loại, tên (rút gọn ở giữa), loại + cỡ.
/// Máy tính: "Lưu" (vào Tải về, không đè tệp trùng tên), "Mở file" (bằng ứng dụng mặc định), sau khi lưu thêm
/// "Mở thư mục". Điện thoại: "Lưu" (bảng chia sẻ / lưu vào Tệp) và "Mở". Đang tải thì hiện thanh tiến độ.
/// Thẻ tệp nằm thẳng trên nền chat (tin chỉ có tệp, không bong bóng): nền đặc thay vì nền mờ.
class SolidFileCards extends InheritedWidget {
  final bool solid;
  const SolidFileCards({super.key, required this.solid, required super.child});
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SolidFileCards>()?.solid ?? false;
  @override
  bool updateShouldNotify(SolidFileCards old) => old.solid != solid;
}

class FileCard extends StatefulWidget {
  final MmFile file;
  /// null = theo máy đang chạy.
  final bool? desktop;
  /// Thay cách tải / thư mục lưu (dùng khi kiểm thử).
  final FileDownloader? downloader;
  final Future<Directory> Function()? saveDir;
  /// Đường dẫn tệp trên máy chạy bot (tin trợ lý gửi tệp: props.flygo_file_paths) cho nút "Copy đường dẫn".
  final String? remotePath;
  const FileCard({super.key, required this.file, this.desktop, this.downloader, this.saveDir, this.remotePath});
  @override
  State<FileCard> createState() => _FileCardState();
}

/// Tệp đã tải trong phiên chạy app (id tệp → đường dẫn), để "Mở" lần sau không tải lại.
final Map<String, String> _openCache = {};
final Map<String, String> _savedCache = {};

/// Bản tệp đã có trên máy này (đã lưu / đã mở trong phiên chạy app), null nếu chưa có.
String? localCopyOf(MmFile f) {
  final p = _savedCache[f.id] ?? _openCache[f.id];
  return p != null && File(p).existsSync() ? p : null;
}

/// Tải tệp về thư mục Tải về (máy tính) nếu chưa có bản trên máy; trả về đường dẫn.
Future<String> saveFileLocally(AppState app, MmFile f) async {
  final hit = localCopyOf(f);
  if (hit != null) return hit;
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final out = await app.api.downloadTo(f.id, File(uniqueSavePath(dir.path, f.name)));
  _savedCache[f.id] = out.path;
  return out.path;
}

class _FileCardState extends State<FileCard> {
  /// Đường dẫn trên máy bot; không có thì tệp đã lưu trên máy này; không nữa thì link tải từ máy chủ chat.
  Future<void> _copyPath() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final path = widget.remotePath ?? _saved ?? _openCache[widget.file.id] ?? context.read<AppState>().api.fileUrl(widget.file.id);
    await Clipboard.setData(ClipboardData(text: path));
    messenger?.showSnackBar(toast(Text(tr('Đã sao chép'))));
  }

  /// Tiến độ tải: null = không tải; 0..1 (hoặc -1 khi không rõ tổng).
  double? _progress;
  String? _saved;

  bool get _desktop => widget.desktop ?? isDesktop;

  @override
  void initState() {
    super.initState();
    _saved = _savedCache[widget.file.id];
  }

  Future<File> _fetch(File out) {
    final dl = widget.downloader ??
        (MmFile f, File o, void Function(int, int) p) => context.read<AppState>().api.downloadTo(f.id, o, onProgress: p);
    setState(() => _progress = -1);
    var last = 0.0;
    return dl(widget.file, out, (got, total) {
      if (!mounted) return;
      final v = total > 0 ? got / total : -1.0;
      // Không dựng lại quá dày: mỗi 1%.
      if (v < 0 ? _progress != -1 : (v - last).abs() >= .01 || v >= 1) {
        last = v;
        setState(() => _progress = v);
      }
    }).whenComplete(() {
      if (mounted) setState(() => _progress = null);
    });
  }

  Future<String> _cached() async {
    final hit = _saved ?? _openCache[widget.file.id];
    if (hit != null && File(hit).existsSync()) return hit;
    final base = widget.saveDir != null ? await widget.saveDir!() : await getTemporaryDirectory();
    final dir = '${base.path}${Platform.pathSeparator}flygo-files${Platform.pathSeparator}${widget.file.id}';
    final f = await _fetch(File(uniqueSavePath(dir, widget.file.name, exists: (_) => false)));
    _openCache[widget.file.id] = f.path;
    return f.path;
  }

  void _fail() {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không tải được file. Kiểm tra kết nối mạng.'))));
  }

  Future<void> _save() async {
    if (_progress != null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_desktop) {
        final dir = widget.saveDir != null
            ? await widget.saveDir!()
            : await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final f = await _fetch(File(uniqueSavePath(dir.path, widget.file.name)));
        _savedCache[widget.file.id] = f.path;
        if (mounted) setState(() => _saved = f.path);
        messenger.showSnackBar(toast(Text(tr('Đã lưu {0}', [f.path.split(Platform.pathSeparator).last]))));
      } else {
        final path = await _cached();
        await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: widget.file.mime.isEmpty ? null : widget.file.mime)], title: widget.file.name));
      }
    } catch (_) {
      _fail();
    }
  }

  Future<void> _open() async {
    if (_progress != null) return;
    try {
      final path = await _cached();
      if (_desktop) {
        await launchUrl(Uri.file(path));
      } else {
        await openLocalFile(path, mime: widget.file.mime.isEmpty ? null : widget.file.mime, title: widget.file.name);
      }
    } catch (_) {
      _fail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final f = widget.file;
    final kind = fileKindOf(f.name, f.mime);
    final (icon, color) = fileKindLook(kind);
    final p = _progress;
    Widget btn(String label, IconData ic, VoidCallback onTap, {bool primary = false}) => Padding(
          padding: const EdgeInsets.only(right: 6, top: 6),
          child: Material(
            color: primary ? pal.accent.withValues(alpha: .14) : pal.text.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: p == null ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(ic, size: 15, color: primary ? pal.accentText : pal.text),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: primary ? pal.accentText : pal.text)),
                ]),
              ),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 4, top: 2),
      // Rộng theo tên tệp (tối thiểu 240), không vượt khung bong bóng chat; tên dài thì xuống dòng.
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 560),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: SolidFileCards.of(context)
          ? BoxDecoration(
              color: pal.inBubble,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .6 : .2), blurRadius: 3, offset: const Offset(0, 1))],
            )
          : BoxDecoration(color: pal.text.withValues(alpha: .06), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Hiện đủ tên tệp; hết chiều ngang khung chat thì xuống dòng.
                Text(f.name, softWrap: true, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: pal.text)),
                const SizedBox(height: 2),
                Text(
                    p == null
                        ? '${fileKindLabel(kind, f.name)} · ${humanSize(f.size)}'
                        : p < 0
                            ? tr('Đang tải...')
                            : '${(p * 100).round()}% · ${humanSize((f.size * p).round())} / ${humanSize(f.size)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
            ),
          ]),
        ),
        if (p != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                  value: p < 0 ? null : p, minHeight: 4, color: pal.accent, backgroundColor: pal.text.withValues(alpha: .08)),
            ),
          ),
        // Máy tính: đã lưu thì "Mở thư mục" thay cho "Lưu" (giữ một hàng nút gọn).
        Wrap(children: [
          if (_desktop && _saved != null)
            btn(tr('Mở thư mục'), Icons.folder_open_rounded, () => revealInFileManager(_saved!), primary: true)
          else
            btn(tr('Lưu'), Icons.download_rounded, _save, primary: true),
          btn(_desktop ? tr('Mở file') : tr('Mở'), Icons.open_in_new_rounded, _open),
          btn(tr('Copy đường dẫn'), Icons.link_rounded, _copyPath),
        ]),
      ]),
    );
  }
}
