// Thư: tệp đính kèm — ảnh thu nhỏ / trang đầu PDF trong thẻ, trình xem toàn màn hình (vuốt qua lại giữa các tệp),
// Tải về (máy tính: thư mục Tải về; điện thoại: bảng chia sẻ), In (PDF, ảnh: hộp thoại in của hệ điều hành)
// và Lưu vào Drive (chọn thư mục, tải lên nền).
// Tệp luôn đi qua máy chủ thư với vé của người dùng (kiểm quyền hộp thư mỗi lần), không có link công khai.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'api.dart';
import 'model.dart';
import 'widgets.dart';

bool isImageAttachment(MailAttachment a) =>
    a.kind == 'img' || a.type.startsWith('image/') || RegExp(r'\.(jpe?g|png|gif|webp|bmp)$', caseSensitive: false).hasMatch(a.name);
bool isPdfAttachment(MailAttachment a) => a.type == 'application/pdf' || a.name.toLowerCase().endsWith('.pdf');
bool canPreview(MailAttachment a) => isImageAttachment(a) || isPdfAttachment(a);
/// In được: PDF và ảnh (tệp Office thì không có nút In).
bool canPrint(MailAttachment a) => isPdfAttachment(a) || isImageAttachment(a);

/// Chỉ cho kiểm thử: thay hộp thoại in của hệ điều hành (nhận tên và nội dung PDF).
@visibleForTesting
Future<bool> Function(String name, Uint8List pdf)? printOverride;

/// In PDF [pdf] bằng hộp thoại in của hệ điều hành (máy tính: hộp thoại in có xem trước; điện thoại: bảng in).
Future<bool> printPdfBytes(String name, Uint8List pdf) =>
    (printOverride ?? (n, b) => Printing.layoutPdf(name: n, onLayout: (_) async => b))(name, pdf);

/// Ảnh thành một trang PDF A4 (ảnh nằm giữa, vừa trang) để in.
Future<Uint8List> imageToPdf(Uint8List image) {
  final img = pw.MemoryImage(image);
  final doc = pw.Document()
    ..addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(24), build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain))));
  return doc.save();
}

/// In tệp đính kèm (PDF, ảnh) từ bản đã tải về máy; lỗi thì báo bằng thanh thông báo.
Future<void> printAttachment(BuildContext context, AttachmentFiles files, MailAttachment a) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final bytes = await (await files.file(a)).readAsBytes();
    await printPdfBytes(a.name, isPdfAttachment(a) ? bytes : await imageToPdf(bytes));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Không in được "${a.name}": $e')));
  }
}

/// Nút In của tệp: vòng chờ trong lúc tải tệp / dựng PDF, bấm lại khi đang chờ thì bỏ qua.
class AttachmentPrintButton extends StatefulWidget {
  const AttachmentPrintButton(this.a, {super.key, required this.files, this.color, this.size = 30, this.iconSize = 17});
  final MailAttachment a;
  final AttachmentFiles files;
  final Color? color;
  final double size, iconSize;

  @override
  State<AttachmentPrintButton> createState() => AttachmentPrintButtonState();
}

class AttachmentPrintButtonState extends State<AttachmentPrintButton> {
  bool _busy = false;

  Future<void> run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await printAttachment(context, widget.files, widget.a);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: _busy
            ? Center(child: SizedBox(width: widget.iconSize - 3, height: widget.iconSize - 3, child: CircularProgressIndicator(strokeWidth: 2, color: widget.color)))
            : IconButton(tooltip: 'In', padding: EdgeInsets.zero, iconSize: widget.iconSize, onPressed: run, icon: Icon(Icons.print_outlined, color: widget.color)),
      );
}

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
Future<String?> downloadAttachment(BuildContext context, AttachmentFiles files, MailAttachment a) async =>
    downloadFile(await files.file(a), a.name, a.type);

/// Tải về một tệp đã có trên máy (tệp đính kèm, ảnh trong thư) như [downloadAttachment].
Future<String?> downloadFile(File f, String name, String type) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: type.isEmpty ? null : type)], title: name));
    return null;
  }
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name, ext = dot > 0 ? name.substring(dot) : '';
  var out = File('${dir.path}/$name');
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

/// PDF trong trình xem (Thư, Drive): mở ra thấy trọn trang đầu (trang bìa); lăn chuột cuộn qua các trang như trang thường,
/// Ctrl/Cmd + lăn chuột (hoặc chụm hai ngón) phóng to quanh con trỏ. Phím ← → không thuộc PDF: để trình xem chuyển tệp.
final mailPdfParams = PdfViewerParams(
  backgroundColor: const Color(0xFF0B0D12),
  margin: 12,
  scrollByMouseWheel: 1,
  sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(calculateInitialZoom: (doc, c, fitPage, fitWidth) => fitPage),
  onKey: (params, key, isRealKeyPress) => key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight ? false : null,
);

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

  /// Sang tệp trước / sau (phím ← →, cả khi đang xem PDF).
  void _go(int d) {
    final i = _i + d;
    if (i < 0 || i >= widget.items.length) return;
    _pages.animateToPage(i, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

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

  void _print() {
    if (canPrint(_cur)) _printKey.currentState?.run();
  }

  final _printKey = GlobalKey<AttachmentPrintButtonState>();

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
    // Máy tính: Esc đóng trình xem, ← → sang tệp trước / sau, Ctrl/Cmd + P in tệp đang xem.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _print,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): _print,
      },
      child: Focus(autofocus: true, child: _scaffold(fg)),
    );
  }

  Widget _scaffold(Color fg) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        foregroundColor: fg,
        title: Text(_cur.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(key: const ValueKey('att-download'), tooltip: 'Tải về', icon: const Icon(Icons.download_rounded), onPressed: _download),
          if (canPrint(_cur)) AttachmentPrintButton(_cur, key: _printKey, files: widget.files, color: fg, size: 48, iconSize: 24),
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
        return PdfViewer.file(f.path, params: mailPdfParams);
      },
    );
  }
}
