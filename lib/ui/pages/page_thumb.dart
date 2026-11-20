import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';

import '../../calls/call_service.dart';
import '../../config.dart';
import 'page_types.dart';
import 'pages_api.dart';

// Ảnh xem trước của một trang trên thẻ (tab Tất cả). Mặc định: chính phần hiện trên sân khấu của loại trang, dựng ở khung
// 400×225 rồi thu nhỏ (chỉ xem, không bấm được). Loại trang có [PageTypeSpec.thumb] thì dùng ảnh riêng (tài liệu: trang
// PDF vẽ bằng pdfium; video: khung đen + nút phát). Dữ liệu trang tải khi thẻ hiện ra (danh sách cuộn ngang dựng dần),
// giữ trong bộ nhớ theo rev; trang đang thay đổi (bình chọn, hỏi đáp) tải lại thưa (tối đa 3 giây một lần), giữ ảnh cũ
// trong lúc chờ nên không nháy.

const _vw = 400.0, _vh = 225.0;
final _cache = <String, PageData>{};
final _fetchedAt = <String, int>{};
final _inflight = <String, Future<PageData?>>{};

Future<PageData?> _data(PagesApi api, MeetPage p) {
  final c = _cache[p.id];
  if (c != null && c.rev >= p.rev) return Future.value(c);
  final last = _fetchedAt[p.id] ?? 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (c != null && now - last < 3000) return Future.value(c);
  return _inflight.putIfAbsent(p.id, () async {
    try {
      final d = await api.get(p.id);
      _cache[p.id] = d;
      _fetchedAt[p.id] = DateTime.now().millisecondsSinceEpoch;
      return d;
    } catch (_) {
      return c;
    } finally {
      unawaited(Future<void>.delayed(Duration.zero, () => _inflight.remove(p.id)));
    }
  });
}

/// Ảnh trang PDF (tệp của trang tài liệu) rộng 360 px; tải tệp một lần, giữ theo (tệp, trang).
final _docImages = <String, Future<ui.Image?>>{};
final _docReady = <String, ui.Image>{}; // đã vẽ xong: hiện ngay, không chờ (mở lại bảng không nháy)
final _docBytes = <String, Future<Uint8List?>>{};

/// Cho test: nạp sẵn nội dung tệp PDF (không tải qua mạng).
@visibleForTesting
void seedPdfBytes(String fileId, Uint8List bytes) => _docBytes[fileId] = Future.value(bytes);

Future<ui.Image?> pdfThumb(String fileId, String url, int page) {
  final key = '$fileId:$page';
  return _docImages.putIfAbsent(key, () async {
    final bytes = await _docBytes.putIfAbsent(fileId, () async {
      try {
        final r = await http.get(Uri.parse('$kPushUrl$url'), headers: {'User-Agent': kUserAgent}).timeout(const Duration(minutes: 2));
        return r.statusCode == 200 ? r.bodyBytes : null;
      } catch (_) {
        return null;
      }
    });
    if (bytes == null) {
      _docBytes.remove(fileId);
      _docImages.remove(key);
      return null;
    }
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(bytes, sourceName: 'thumb-$fileId');
      final pg = doc.pages[(page - 1).clamp(0, doc.pages.length - 1)];
      final img = await pg.renderForDisplay(fullWidth: 360, fullHeight: 360 * pg.height / pg.width, backgroundColor: 0xFFFFFFFF);
      if (img != null) _docReady[key] = img;
      return img;
    } catch (_) {
      _docImages.remove(key);
      return null;
    } finally {
      await doc?.dispose();
    }
  });
}

/// Ảnh xem trước một trang tài liệu: trang [page] (mặc định 1) của tệp.
class PdfThumb extends StatefulWidget {
  final Map<String, dynamic>? file;
  final int page;
  const PdfThumb({super.key, required this.file, this.page = 1});
  @override
  State<PdfThumb> createState() => _PdfThumbState();
}

class _PdfThumbState extends State<PdfThumb> {
  ui.Image? _img;
  String _key = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PdfThumb old) {
    super.didUpdateWidget(old);
    _load();
  }

  void _load() {
    final f = widget.file;
    final id = '${f?['id'] ?? ''}', url = '${f?['url'] ?? ''}';
    if (id.isEmpty || url.isEmpty) return;
    final k = '$id:${widget.page}';
    if (k == _key) return;
    _key = k;
    final ready = _docReady[k];
    if (ready != null) {
      _img = ready;
      return;
    }
    pdfThumb(id, url, widget.page).then((img) {
      if (mounted && img != null && _key == k) setState(() => _img = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    return Container(
      color: const Color(0xFF111316),
      alignment: Alignment.center,
      child: img == null
          ? const Icon(Icons.slideshow_rounded, color: Color(0xFFF29900), size: 28)
          : RawImage(image: img, fit: BoxFit.contain),
    );
  }
}

/// Ảnh xem trước của [page] cho thẻ trang.
class PageThumb extends StatefulWidget {
  final CallService call;
  final MeetPage page;
  const PageThumb({super.key, required this.call, required this.page});
  @override
  State<PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends State<PageThumb> {
  late final api = PagesApi(widget.call);
  PageData? _d;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    _d = _cache[widget.page.id];
    _load();
  }

  @override
  void didUpdateWidget(PageThumb old) {
    super.didUpdateWidget(old);
    if (widget.page.rev != old.page.rev || widget.page.id != old.page.id) _load();
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final p = widget.page;
    final d = await _data(api, p);
    if (!mounted) return;
    if (d != null && !identical(d, _d)) setState(() => _d = d);
    // Bị bỏ qua vì vừa tải (< 3 giây): thử lại sau, để ảnh theo kịp lần đổi cuối.
    if (d != null && d.rev < p.rev) {
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 3), _load);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    final spec = pageTypeOf(p.type);
    final d = _d;
    Widget child;
    if (spec?.thumb != null) {
      child = spec!.thumb!(context, widget.call, p, d);
    } else if (d == null || spec == null) {
      child = Container(color: (spec?.color ?? Colors.grey).withValues(alpha: .28), alignment: Alignment.center, child: Icon(spec?.icon ?? Icons.help_outline, color: spec?.color ?? Colors.grey));
    } else {
      // Phần hiện trên sân khấu, quyền "chỉ xem" (không hiện nút điều khiển), thu nhỏ vào thẻ.
      final ctx = PageCtx(
        data: PageData(d.page, d.view, 'viewer', d.rev),
        api: api,
        call: widget.call,
        presenting: false,
        onStage: true,
        act: (a, [b = const {}]) async {},
        reload: () async {},
      );
      child = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(width: _vw, height: _vh, child: Material(color: const Color(0xFF17191C), child: Builder(builder: (c) => spec.view(c, ctx)))),
      );
    }
    return IgnorePointer(child: ExcludeSemantics(child: RepaintBoundary(child: child)));
  }
}
