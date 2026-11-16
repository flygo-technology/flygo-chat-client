// Thư: tệp đính kèm — ảnh thu nhỏ / trang đầu PDF trong thẻ, trình xem toàn màn hình (vuốt qua lại giữa các tệp),
// Tải về (máy tính: thư mục Tải về; điện thoại: bảng chia sẻ) và Lưu vào Drive (chọn thư mục, tải lên nền).
// Tệp luôn đi qua máy chủ thư với vé của người dùng (kiểm quyền hộp thư mỗi lần), không có link công khai.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'model.dart';
import 'widgets.dart';

bool isImageAttachment(MailAttachment a) =>
    a.kind == 'img' || a.type.startsWith('image/') || RegExp(r'\.(jpe?g|png|gif|webp|bmp)$', caseSensitive: false).hasMatch(a.name);
bool isPdfAttachment(MailAttachment a) => a.type == 'application/pdf' || a.name.toLowerCase().endsWith('.pdf');
bool canPreview(MailAttachment a) => isImageAttachment(a) || isPdfAttachment(a);

/// Bản tải về máy (thư mục tạm) cho mỗi tệp, dùng chung cho ảnh thu nhỏ, trình xem, tải về và Lưu vào Drive.
class AttachmentFiles {
  AttachmentFiles(this.api);
  final MailApi api;
  final _files = <String, Future<File>>{};

  Future<File> file(MailAttachment a) => _files.putIfAbsent(a.id, () => api.download(a).catchError((Object e) {
        _files.remove(a.id);
        throw e;
      }));
}

/// Móc nối Lưu vào Drive (mail_page gắn: chọn thư mục Drive của người dùng rồi tải lên nền). Null = không có Drive.
typedef SaveToDrive = Future<void> Function(BuildContext context, List<(String path, String name)> files);

/// Tải về: máy tính lưu vào thư mục Tải về (không ghi đè), điện thoại mở bảng chia sẻ (Lưu vào Tệp, gửi app khác).
Future<String?> downloadAttachment(BuildContext context, AttachmentFiles files, MailAttachment a) async {
  final f = await files.file(a);
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: a.type.isEmpty ? null : a.type)], title: a.name));
    return null;
  }
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final dot = a.name.lastIndexOf('.');
  final stem = dot > 0 ? a.name.substring(0, dot) : a.name, ext = dot > 0 ? a.name.substring(dot) : '';
  var out = File('${dir.path}/${a.name}');
  for (var i = 1; out.existsSync(); i++) {
    out = File('${dir.path}/$stem ($i)$ext');
  }
  await f.copy(out.path);
  return out.path;
}

/// Ảnh thu nhỏ trong thẻ tệp: ảnh, trang đầu PDF; tệp khác: biểu tượng.
class AttachmentThumb extends StatelessWidget {
  const AttachmentThumb(this.a, {super.key, required this.files});
  /// Trang đầu PDF (pdfium); tắt trong test widget.
  static bool pdfThumbs = true;
  final MailAttachment a;
  final AttachmentFiles files;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final (icon, color) = attachmentIcon(a);
    final fallback = Center(child: Icon(isImageAttachment(a) ? Icons.image_outlined : icon, size: 40, color: color));
    if (!canPreview(a) || a.size > 20 * 1024 * 1024 || (isPdfAttachment(a) && !pdfThumbs)) return fallback;
    return FutureBuilder<File>(
      future: files.file(a),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) {
          return snap.hasError ? fallback : Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: mc.muted)));
        }
        if (isImageAttachment(a)) return Image.file(f, fit: BoxFit.cover, width: double.infinity, cacheWidth: 400, errorBuilder: (_, _, _) => fallback);
        return ColoredBox(
          color: Colors.white,
          child: PdfDocumentViewBuilder.file(
            f.path,
            builder: (context, doc) => doc == null ? fallback : PdfPageView(document: doc, pageNumber: 1, alignment: Alignment.topCenter),
          ),
        );
      },
    );
  }
}

/// Trình xem toàn màn hình: vuốt qua lại giữa các tệp của thư; ảnh phóng to được, PDF xem trong app,
/// tệp khác thì mở bằng ứng dụng trên máy. Thanh trên: Tải về, Lưu vào Drive, Mở bằng ứng dụng khác.
class AttachmentViewer extends StatefulWidget {
  const AttachmentViewer({super.key, required this.items, required this.index, required this.files, required this.onOpenExternal, this.saveToDrive});
  final List<MailAttachment> items;
  final int index;
  final AttachmentFiles files;
  final Future<void> Function(MailAttachment a) onOpenExternal;
  final SaveToDrive? saveToDrive;

  @override
  State<AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<AttachmentViewer> {
  late int _i = widget.index;
  late final _pages = PageController(initialPage: widget.index);

  MailAttachment get _cur => widget.items[_i];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _snack(String m, {SnackBarAction? action}) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m), action: action));

  Future<void> _download() async {
    try {
      final p = await downloadAttachment(context, widget.files, _cur);
      if (p != null) _snack('Đã lưu vào Tải về: ${p.split(Platform.pathSeparator).last}');
    } catch (e) {
      _snack('Không tải được: $e');
    }
  }

  Future<void> _drive() async {
    final save = widget.saveToDrive;
    if (save == null) return;
    try {
      final f = await widget.files.file(_cur);
      if (mounted) await save(context, [(f.path, _cur.name)]);
    } catch (e) {
      _snack('Không lưu được: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        foregroundColor: fg,
        title: Text(_cur.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(key: const ValueKey('att-download'), tooltip: 'Tải về', icon: const Icon(Icons.download_rounded), onPressed: _download),
          if (widget.saveToDrive != null) IconButton(key: const ValueKey('att-drive'), tooltip: 'Lưu vào Drive', icon: const Icon(Icons.add_to_drive_rounded), onPressed: _drive),
          IconButton(tooltip: 'Mở bằng ứng dụng khác', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => widget.onOpenExternal(_cur)),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (context, i) => _page(widget.items[i]),
      ),
    );
  }

  Widget _page(MailAttachment a) {
    const fg = Colors.white70;
    if (!canPreview(a)) {
      final (icon, color) = attachmentIcon(a);
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 72, color: color),
          const SizedBox(height: 12),
          Text(a.name, style: const TextStyle(color: Colors.white, fontSize: 15)),
          Text(fmtSize(a.size), style: const TextStyle(color: fg)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: () => widget.onOpenExternal(a), icon: const Icon(Icons.open_in_new_rounded), label: const Text('Mở bằng ứng dụng trên máy')),
        ]),
      );
    }
    return FutureBuilder<File>(
      future: widget.files.file(a),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) {
          return Center(child: snap.hasError ? Text('Không tải được tệp: ${snap.error}', style: const TextStyle(color: fg)) : const CircularProgressIndicator());
        }
        if (isImageAttachment(a)) {
          return InteractiveViewer(maxScale: 8, child: Center(child: Image.file(f, errorBuilder: (_, _, _) => const Text('Không hiển thị được ảnh này', style: TextStyle(color: fg)))));
        }
        return PdfViewer.file(f.path, params: const PdfViewerParams(backgroundColor: Color(0xFF0B0D12), margin: 12));
      },
    );
  }
}
