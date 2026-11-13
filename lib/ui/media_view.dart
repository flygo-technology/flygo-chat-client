import '../i18n/i18n.dart';
import 'dart:io';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';

import '../api/stt.dart';
import 'package:gal/gal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../config.dart' show isDesktop;
import '../data/image_disk_cache.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'chat_page.dart' show saveMedia;
import 'forward_page.dart';
import 'image_edit.dart';
import 'clip.dart';
import 'common.dart';
import 'theme.dart';
import 'zoom_view.dart';

/// Một ảnh hiển thị trong chat: ảnh trên máy (đang gửi / vừa gửi) hoặc ảnh
/// trên máy chủ.
class ChatImage {
  final String? localPath;
  final MmFile? file;
    /// Ảnh ngoài (GIF, sticker).
  final String? url;
  final double aspect;

  /// Ảnh của app khác cần cách tải riêng (vd Bảng tin: kèm vé Flygo ID). Không có nút sửa / chuyển tiếp / tải xuống.
  final ImageProvider? image;
  ChatImage({this.localPath, this.file, this.url, this.aspect = 4 / 3, this.image});

  /// Ảnh trên máy chủ / ảnh ngoài đọc qua bộ nhớ đệm trên đĩa ([DiskCachedImage]): đã xem thì không tải lại, kể cả sau khi mở lại app.
  ImageProvider provider(AppState app, {bool full = false}) {
    if (image != null) return image!;
    if (url != null) return DiskCachedImage.network('url:$url', url!);
    final p = localPath ?? (file == null ? null : app.localPathFor(file!.id));
    if (p != null && File(p).existsSync()) return FileImage(File(p));
    final remote = full ? app.api.fileUrl(file!.id) : app.api.previewUrl(file!.id);
    return DiskCachedImage.network(chatImageKey(file!.id, full ? 'full' : 'preview'), remote, headers: app.api.headers);
  }

  ImageProvider? thumb(AppState app) => image != null || url != null || file == null || app.localPathFor(file!.id) != null
      ? null
      : DiskCachedImage.network(chatImageKey(file!.id, 'thumb'), app.api.thumbUrl(file!.id), headers: app.api.headers);

  /// Tải sẵn ảnh gốc về đĩa (không giải mã); ảnh trên máy thì thôi.
  Future<void> prefetch(AppState app) async {
    final p = provider(app, full: true);
    if (p is DiskCachedImage) await p.prefetch();
  }
}


/// Danh sách ảnh của một tin (ảnh đang gửi lấy từ máy, ảnh đã gửi lấy từ máy chủ).
List<ChatImage> imagesOf(MmPost p) {
  final local = p.localFiles.where((f) => (f['mime'] as String? ?? '').startsWith('image/')).toList();
  if (local.isNotEmpty) {
    return [for (final f in local) ChatImage(localPath: f['path'] as String, aspect: (f['aspect'] as num?)?.toDouble() ?? 4 / 3)];
  }
  return [
    for (final f in p.files.where((f) => f.isImage))
      ChatImage(file: f, aspect: f.width > 0 && f.height > 0 ? f.width / f.height : 4 / 3),
  ];
}

/// Bấm vào ảnh: mở trình xem ảnh phủ kín màn hình hiện tại (máy tính lẫn điện thoại), không mở trang mới.
void openImages(BuildContext context, MmPost post, List<ChatImage> images, int i) => showGallery(context, post, images, i);

/// Trình xem ảnh phủ lên màn hình hiện tại (hiện dần), đóng bằng Esc / nút X / vuốt xuống / chạm ra ngoài ảnh.
Future<void> showGallery(BuildContext context, MmPost post, List<ChatImage> images, int i) =>
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (_, _, _) => GalleryViewer(post: post, images: images, initial: i),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));

/// Ảnh trong tin nhắn: một ảnh thì hiện nguyên, nhiều ảnh thì xếp chồng lệch nhau.
/// [overlay] là giờ gửi + trạng thái, đặt đè ở góc dưới phải.
class ChatMedia extends StatelessWidget {
  final MmPost post;
  final List<ChatImage> images;
  final Widget? overlay;
  final bool sending;
  final double maxWidth;
  final bool sticker;
  const ChatMedia(
      {super.key, required this.post, required this.images, this.overlay, this.sending = false, this.maxWidth = 280, this.sticker = false});

  void _open(BuildContext context, int index) => openImages(context, post, images, index);

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final w = maxWidth.clamp(sticker ? 100.0 : 160.0, 300.0);
    Widget content;
    if (sticker) {
      content = SizedBox(width: w, height: w / images.first.aspect.clamp(.5, 2.0), child: Image(image: images.first.provider(app), fit: BoxFit.contain));
    } else if (images.length == 1) {
      final img = images.first;
      final aspect = img.aspect.clamp(.6, 1.9);
      content = GestureDetector(
        onTap: () => _open(context, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(width: w, height: w / aspect, child: _Img(image: img, app: app)),
        ),
      );
    } else {
      // Nhiều ảnh (điện thoại và máy tính như nhau): một hàng cuộn ngang; bấm một ảnh mở trang toàn màn hình
      // cuộn dọc mọi ảnh liền nhau, bắt đầu ở ảnh đã bấm.
      void open(int i) => openImages(context, post, images, i);
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        // Nhãn số ảnh phía trên hàng ảnh (từ 2 ảnh): biết ngay đây là một bộ ảnh; bấm cũng mở trang xem tất cả.
        GestureDetector(
          onTap: () => open(0),
          child: Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.photo_library_rounded, color: Colors.white, size: 15),
              const SizedBox(width: 5),
              Text(tr('{0} ảnh', [images.length]), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        _ImageRow(
          images: images,
          app: app,
          // Hàng ảnh dùng hết chiều ngang đang có (máy tính rộng thì thấy nhiều ảnh hơn); chỉ khi không đo được mới giới hạn.
          maxWidth: maxWidth.isFinite ? maxWidth : double.infinity,
          onOpen: open,
        ),
      ]);
    }
    // Sticker có chữ ở cả phần dưới: giờ gửi đặt ngay dưới sticker, không đè lên chữ.
    if (sticker && overlay != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        ChatMedia(post: post, images: images, sending: sending, maxWidth: maxWidth, sticker: true),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: IconTheme.merge(data: const IconThemeData(color: Colors.white), child: overlay!),
          ),
        ),
      ]);
    }
    return Stack(children: [
      content,
      if (sending)
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              ),
            ),
          ),
        ),
      if (overlay != null)
        Positioned(
          right: images.length > 1 ? 14 : 8,
          bottom: images.length > 1 ? 10 : 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Colors.white),
              child: IconTheme.merge(data: const IconThemeData(color: Colors.white), child: overlay!),
            ),
          ),
        ),
    ]);
  }
}

/// Hàng ảnh cuộn ngang (máy tính): cao cố định, rộng theo tỉ lệ từng ảnh; lăn chuột dọc cũng cuộn ngang.
class _ImageRow extends StatefulWidget {
  final List<ChatImage> images;
  final AppState app;
  final double maxWidth;
  final void Function(int) onOpen;
  const _ImageRow({required this.images, required this.app, required this.maxWidth, required this.onOpen});
  @override
  State<_ImageRow> createState() => _ImageRowState();
}

class _ImageRowState extends State<_ImageRow> {
  final _ctl = ScrollController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const h = 180.0;
    final widths = [for (final i in widget.images) (h * i.aspect.clamp(.6, 1.9)).toDouble()];
    final total = widths.fold<double>(0, (a, b) => a + b) + 6.0 * (widths.length - 1);
    return LayoutBuilder(builder: (context, c) {
      // Rộng tối đa = chỗ trống thật của tin (full width), không vượt maxWidth của bong bóng.
      final avail = [if (c.maxWidth.isFinite) c.maxWidth, if (widget.maxWidth.isFinite) widget.maxWidth];
      final maxW = avail.isEmpty ? 560.0 : avail.reduce((a, b) => a < b ? a : b);
      return _row(context, total, maxW, widths, h);
    });
  }

  Widget _row(BuildContext context, double total, double maxW, List<double> widths, double h) {
    return SizedBox(
      width: total.clamp(0, maxW).toDouble(),
      height: h + 10,
      child: Listener(
        // Lăn chuột dọc trên hàng ảnh thì cuộn ngang.
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && _ctl.hasClients && e.scrollDelta.dy != 0 && e.scrollDelta.dx == 0) {
            final to = (_ctl.offset + e.scrollDelta.dy).clamp(0.0, _ctl.position.maxScrollExtent);
            _ctl.jumpTo(to);
          }
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.mouse, PointerDeviceKind.touch, PointerDeviceKind.trackpad}),
          child: Scrollbar(
            controller: _ctl,
            thumbVisibility: total > maxW,
            child: ListView.separated(
              controller: _ctl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 10),
              itemCount: widget.images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => widget.onOpen(i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(width: widths[i], height: h, child: _Img(image: widget.images[i], app: widget.app)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nhiều ảnh của một tin: toàn màn hình, cuộn dọc các ảnh liền nhau (mở ở ảnh đã bấm).
/// Bấm một ảnh để phóng to, lưu, chuyển tiếp (trình xem ảnh cũ).
class _Img extends StatelessWidget {
  final ChatImage image;
  final AppState app;
  const _Img({required this.image, required this.app});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final thumb = image.thumb(app);
    return LayoutBuilder(builder: (context, c) => Stack(fit: StackFit.expand, children: [
      Container(color: pal.surface2),
      if (thumb != null) Image(image: thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
      Image(
        // Ảnh trong khung chat: giải mã theo cỡ khung (ảnh dọc cắt theo chiều rộng nên lấy cạnh lớn hơn).
        image: sizedImage(context, image.provider(app), math.max(c.maxWidth, c.maxHeight * image.aspect.clamp(.3, 3.0))),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, sync) =>
            sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 200), child: child),
        errorBuilder: (_, _, _) => Center(child: Icon(Icons.image_not_supported, color: pal.sub)),
      ),
    ]));
  }
}

/// Xem ảnh toàn màn hình: phóng to tự do, vuốt ngang giữa các ảnh, chạm để ẩn/hiện
/// thanh công cụ; có Tải xuống, Chuyển tiếp và (điện thoại) Chia sẻ.
class GalleryViewer extends StatefulWidget {
  final MmPost post;
  final List<ChatImage> images;
  final int initial;
  const GalleryViewer({super.key, required this.post, required this.images, this.initial = 0});
  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late final PageController _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _chrome = true;
  bool _zoomed = false;
  final Map<int, TransformationController> _tc = {};

  TransformationController _ctl(int i) => _tc.putIfAbsent(i, () {
        final c = TransformationController();
        c.addListener(() {
          final z = c.value.getMaxScaleOnAxis() > 1.01;
          if (z != _zoomed && i == _index) setState(() => _zoomed = z);
        });
        return c;
      });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preload());
  }

  /// Mở ảnh i: tải sẵn mọi ảnh khác của tin về đĩa (gần ảnh đang xem trước, mỗi lần vài ảnh) để vuốt sang không phải chờ.
  /// Chỉ giải mã sẵn hai ảnh kề bên, ảnh còn lại nằm trên đĩa (giải mã rất nhanh) để không tốn bộ nhớ.
  Future<void> _preload() async {
    if (!mounted) return;
    final app = context.read<AppState>();
    _decodeNeighbors(_index);
    final order = [for (var i = 0; i < widget.images.length; i++) if (i != widget.initial) i]
      ..sort((a, b) => (a - widget.initial).abs().compareTo((b - widget.initial).abs()));
    var next = 0;
    Future<void> worker() async {
      while (mounted && next < order.length) {
        final i = order[next++];
        try {
          await widget.images[i].prefetch(app);
        } catch (_) {}
      }
    }

    await Future.wait([for (var w = 0; w < 3; w++) worker()]);
  }

  void _decodeNeighbors(int i) {
    if (!mounted) return;
    final app = context.read<AppState>();
    for (final j in [i + 1, i - 1]) {
      if (j < 0 || j >= widget.images.length) continue;
      precacheImage(widget.images[j].provider(app, full: true), context, onError: (_, _) {});
    }
  }

  @override
  void dispose() {
    _page.dispose();
    for (final c in _tc.values) {
      c.dispose();
    }
    for (final (stream, l) in _streams.values) {
      stream.removeListener(l);
    }
    super.dispose();
  }

  /// Sửa ảnh đang xem (vẽ, cắt, xoay), rồi chọn gửi lại vào cuộc trò chuyện, chuyển tiếp hoặc lưu.
  Future<void> _edit(ChatImage img) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    String path;
    try {
      final local = img.localPath ?? app.localPathFor(img.file!.id);
      path = local != null && File(local).existsSync() ? local : (await app.download(img.file!)).path;
    } catch (_) {
      messenger.showSnackBar(toast(Text(tr('Không tải được ảnh để sửa.'))));
      return;
    }
    if (!mounted) return;
    final edited = await editImage(context, path);
    if (edited == null || !mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        final pal = Pal.of(ctx);
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(edited), height: 180)),
            ),
            ListTile(
              leading: Icon(Icons.send_rounded, color: pal.text),
              title: Text(tr('Gửi vào cuộc trò chuyện này'), style: TextStyle(color: pal.text)),
              onTap: () => Navigator.pop(ctx, 'send'),
            ),
            ListTile(
              leading: Icon(Icons.shortcut, color: pal.text),
              title: Text(tr('Chuyển tiếp...'), style: TextStyle(color: pal.text)),
              onTap: () => Navigator.pop(ctx, 'forward'),
            ),
            ListTile(
              leading: Icon(Icons.download, color: pal.text),
              title: Text(tr('Lưu về máy'), style: TextStyle(color: pal.text)),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
    if (!mounted || choice == null) return;
    final name = 'edited_${DateTime.now().millisecondsSinceEpoch}.png';
    switch (choice) {
      case 'send':
        await app.sendMedia(widget.post.channelId, [(edited, name, 'image/png', await imageAspect(edited))]);
        if (mounted) Navigator.pop(context);
      case 'forward':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForwardPage(localPaths: [edited])));
      case 'save':
        await saveLocalImage(context, edited);
    }
  }

  /// Giữ / nháy phải vào ảnh đang xem: Sao chép ảnh, Tải ảnh, (ảnh chat đã gửi) Sửa, Chuyển tiếp.
  Future<void> _imageMenu(int i, Offset at) async {
    final img = widget.images[i];
    final sent = widget.post.sendState == SendState.sent && img.url == null && img.file != null;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
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
        item('copy', Icons.copy, tr('Sao chép ảnh')),
        item('download', Icons.download, tr('Tải ảnh')),
        if (sent) ...[
          item('edit', Icons.edit_outlined, tr('Sửa')),
          item('forward', Icons.shortcut, tr('Chuyển tiếp')),
        ],
      ],
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'copy':
        await copyChatImage(context, img);
      case 'edit':
        await _edit(img);
      case 'forward':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => widget.images.length > 1 ? ForwardPage(files: [img.file!]) : ForwardPage(post: widget.post)));
      case 'download':
        await saveChatImage(context, img);
    }
  }

  /// Điện thoại: ở cỡ gốc, kéo ảnh lên / xuống là để đóng (nền mờ dần theo); thả tay chưa đủ xa thì ảnh về chỗ cũ.
  double _dragY = 0;

  /// Tỉ lệ thật của ảnh (đọc khi ảnh tải xong); trước đó dùng tỉ lệ ghi trong tin.
  final Map<int, double> _aspect = {};
  final Map<int, (ImageStream, ImageStreamListener)> _streams = {};

  void _resolveAspect(int i, ImageProvider image) {
    if (_streams.containsKey(i)) return;
    final stream = image.resolve(createLocalImageConfiguration(context));
    final l = ImageStreamListener((info, _) {
      final w = info.image.width, h = info.image.height;
      // Chỉ dùng khi chạm (chạm ra ngoài ảnh thì đóng), không cần dựng lại; ảnh có sẵn trong bộ nhớ thì báo ngay lúc đang dựng.
      if (w > 0 && h > 0) _aspect[i] = w / h;
    }, onError: (_, _) {});
    stream.addListener(l);
    _streams[i] = (stream, l);
  }

  Widget _zoomable(int i, Widget child) => isDesktop
      ? ZoomPanView(controller: _ctl(i), child: child)
      : InteractiveViewer(
          transformationController: _ctl(i),
          minScale: 1,
          maxScale: 10,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          onInteractionUpdate: (_) => _trackDrag(i),
          onInteractionEnd: (d) => _endDrag(i, d.velocity.pixelsPerSecond.dy),
          child: child,
        );

  void _trackDrag(int i) {
    final m = _ctl(i).value;
    final y = m.getMaxScaleOnAxis() > 1.01 ? 0.0 : m.getTranslation().y;
    if (y != _dragY) setState(() => _dragY = y);
  }

  void _endDrag(int i, double velocity) {
    final c = _ctl(i);
    if (c.value.getMaxScaleOnAxis() > 1.01) return;
    final y = c.value.getTranslation().y;
    if (y.abs() > 120 || (velocity.abs() > 900 && y.abs() > 30)) {
      Navigator.of(context).maybePop();
      return;
    }
    c.value = Matrix4.identity();
    setState(() => _dragY = 0);
  }

  void _doubleTap(int i, TapDownDetails? d) {
    final c = _ctl(i);
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      c.value = Matrix4.identity();
    } else {
      final p = d?.localPosition ?? Offset.zero;
      c.value = Matrix4.identity()
        ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  /// Chạm vào ảnh: ẩn/hiện thanh công cụ. Chạm ra ngoài ảnh (phần nền đen) khi chưa phóng to: đóng.
  void _tap(int i, Offset at, Size box) {
    if (!_zoomed && !imageRectIn(box, _aspect[i] ?? widget.images[i].aspect).contains(at)) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _chrome = !_chrome);
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.images.length) return;
    _page.animateToPage(next, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  /// Điện thoại: chia sẻ ảnh đang xem (Zalo, Ảnh, Tệp...).
  Future<void> _share(ChatImage img) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final local = img.localPath ?? (img.file == null ? null : app.localPathFor(img.file!.id));
      final String path;
      if (local != null && File(local).existsSync()) {
        path = local;
      } else {
        // Ảnh trên máy chủ / Bảng tin: lấy từ bộ nhớ đệm trên đĩa, ghi ra tệp tạm để chia sẻ đúng tệp ảnh (không phải link).
        final bytes = await chatImageBytes(app, img);
        final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}flygo-share');
        await dir.create(recursive: true);
        final name = img.file?.name.contains('.') == true ? img.file!.name : 'anh-${DateTime.now().millisecondsSinceEpoch}.${imageExt(bytes)}';
        path = '${dir.path}${Platform.pathSeparator}${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
        await File(path).writeAsBytes(bytes);
      }
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    } catch (_) {
      messenger.showSnackBar(toast(Text(tr('Không tải được file. Kiểm tra kết nối mạng.'))));
    }
  }

  Widget _arrow(IconData icon, VoidCallback onTap, String tip) => Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: IconButton(tooltip: tip, icon: Icon(icon, color: Colors.white), onPressed: onTap),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final sent = widget.post.sendState == SendState.sent;
    final cur = widget.images[_index];
    final remote = sent && cur.url == null && cur.file != null;
    final phone = Platform.isAndroid || Platform.isIOS;
    final fade = (1 - _dragY.abs() / 500).clamp(0.3, 1.0);
    TapDownDetails? lastDown;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        // Ctrl/⌘+C sao chép ảnh, Ctrl/⌘+S tải ảnh đang xem.
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => copyChatImage(context, cur),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () => copyChatImage(context, cur),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => saveChatImage(context, cur),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => saveChatImage(context, cur),
      },
      child: EscToPop(
        child: Scaffold(
          backgroundColor: Colors.black.withValues(alpha: fade),
          body: Stack(children: [
            PageView.builder(
              controller: _page,
              physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() {
                _decodeNeighbors(i);
                _index = i;
                _zoomed = false;
                _dragY = 0;
              }),
              itemBuilder: (_, i) {
                final full = widget.images[i].provider(app, full: true);
                _resolveAspect(i, full);
                return LayoutBuilder(
                  builder: (_, box) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _tap(i, d.localPosition, box.biggest),
                    onLongPressStart: (d) => _imageMenu(i, d.globalPosition),
                    onSecondaryTapDown: (d) => _imageMenu(i, d.globalPosition),
                    onDoubleTapDown: (d) => lastDown = d,
                    onDoubleTap: () => _doubleTap(i, lastDown),
                    // Máy tính: vuốt / cuộn chuột để phóng to thu nhỏ, kéo chuột để di chuyển ảnh. Điện thoại: chụm hai ngón.
                    // Ảnh luôn hiện trọn (contain) ở cỡ ban đầu, ảnh dài hay ảnh toàn cảnh cũng không bị cắt.
                    child: _zoomable(
                      i,
                      SizedBox.expand(
                        child: Image(
                          key: ValueKey('viewer-image-$i'),
                          image: full,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, p) => p == null
                              ? child
                              : Stack(alignment: Alignment.center, children: [
                                  Positioned.fill(child: Image(image: widget.images[i].provider(app), fit: BoxFit.contain)),
                                  const CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                                ]),
                          errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 48)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (isDesktop && widget.images.length > 1 && _chrome) ...[
              if (_index > 0)
                Positioned(left: 12, top: 0, bottom: 0, child: Center(child: _arrow(Icons.chevron_left_rounded, () => _go(-1), tr('Ảnh trước')))),
              if (_index < widget.images.length - 1)
                Positioned(right: 12, top: 0, bottom: 0, child: Center(child: _arrow(Icons.chevron_right_rounded, () => _go(1), tr('Ảnh sau')))),
            ],
            AnimatedOpacity(
              opacity: _chrome && _dragY == 0 ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !_chrome,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent]),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                      child: Row(children: [
                        IconButton(
                          tooltip: tr('Đóng'),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        if (widget.images.length > 1)
                          Text('${_index + 1}/${widget.images.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (remote) ...[
                          IconButton(
                            tooltip: tr('Sửa'),
                            icon: const Icon(Icons.edit_outlined, color: Colors.white),
                            onPressed: () => _edit(cur),
                          ),
                          IconButton(
                            tooltip: tr('Chuyển tiếp'),
                            icon: const Icon(Icons.shortcut, color: Colors.white),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => widget.images.length > 1 ? ForwardPage(files: [cur.file!]) : ForwardPage(post: widget.post))),
                          ),
                        ],
                        if (phone)
                          IconButton(
                            tooltip: tr('Chia sẻ'),
                            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
                            onPressed: () => _share(cur),
                          ),
                        // Mọi ảnh (chat, Bảng tin, ảnh trên máy): sao chép và tải về, dữ liệu lấy từ bộ nhớ đệm.
                        IconButton(
                          tooltip: tr('Sao chép ảnh'),
                          icon: const Icon(Icons.copy_rounded, color: Colors.white),
                          onPressed: () => copyChatImage(context, cur),
                        ),
                        IconButton(
                          tooltip: tr('Tải ảnh'),
                          icon: const Icon(Icons.download, color: Colors.white),
                          onPressed: () => saveChatImage(context, cur),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Khung ảnh tỉ lệ [aspect] (rộng / cao) khi đặt vừa trọn (contain) giữa khung [box].
Rect imageRectIn(Size box, double aspect) {
  if (aspect <= 0 || box.isEmpty) return Offset.zero & box;
  final w = box.width / box.height > aspect ? box.height * aspect : box.width;
  final h = w / aspect;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}


/// Tin ghi âm: nút phát/dừng, thanh tiến trình, thời lượng.
class AudioMessage extends StatefulWidget {
  final MmFile file;
  const AudioMessage({super.key, required this.file});
  @override
  State<AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<AudioMessage> {
  final _player = AudioPlayer();
  Duration _pos = Duration.zero;
  Duration _len = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  String? _path;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((p) => mounted ? setState(() => _pos = p) : null);
    _player.onDurationChanged.listen((d) => mounted ? setState(() => _len = d) : null);
    _player.onPlayerComplete.listen((_) => mounted ? setState(() {
          _playing = false;
          _pos = Duration.zero;
        }) : null);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Chữ nhận diện từ tin ghi âm (nhớ trong phiên để không chuyển lại).
  static final Map<String, String> _transcripts = {};
  bool _transcribing = false;

  Future<String> _ensurePath() async {
    if (_path != null) return _path!;
    final app = context.read<AppState>();
    final local = app.localPathFor(widget.file.id);
    if (local != null && File(local).existsSync()) return _path = local;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${widget.file.id}_${widget.file.name}');
    if (!f.existsSync()) await f.writeAsBytes(await app.api.fileBytes(widget.file.id));
    return _path = f.path;
  }

  Future<void> _toText() async {
    final api = context.read<AppState>().api;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _transcribing = true);
    try {
      final text = await transcribeAudio(api, await _ensurePath());
      _transcripts[widget.file.id] = text.isEmpty ? tr('(Không nghe rõ nội dung)') : text;
    } catch (_) {
      messenger.showSnackBar(toast(Text(tr('Không chuyển được thành chữ. Kiểm tra kết nối mạng.'))));
    }
    if (mounted) setState(() => _transcribing = false);
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    if (_path == null) {
      setState(() => _loading = true);
      try {
        await _ensurePath();
      } catch (_) {
        if (mounted) setState(() => _loading = false);
        return;
      }
    }
    await _player.play(DeviceFileSource(_path!));
    if (mounted) {
      setState(() {
        _loading = false;
        _playing = true;
      });
    }
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final total = _len.inMilliseconds == 0 ? 1 : _len.inMilliseconds;
    final transcript = _transcripts[widget.file.id];
    return Container(
      width: 250,
      margin: const EdgeInsets.only(bottom: 4, top: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        GestureDetector(
          onTap: _loading ? null : _toggle,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _pos.inMilliseconds / total,
                minHeight: 5,
                backgroundColor: pal.text.withValues(alpha: .15),
                color: pal.accentText,
              ),
            ),
            const SizedBox(height: 5),
            Row(children: [
              Icon(Icons.mic, size: 14, color: pal.sub),
              const SizedBox(width: 3),
              Text(_len == Duration.zero ? tr('Tin ghi âm') : _fmt(_playing || _pos > Duration.zero ? _pos : _len),
                  style: TextStyle(fontSize: 12.5, color: pal.sub)),
              const SizedBox(width: 8),
              Expanded(
                child: transcript != null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: _transcribing ? null : _toText,
                          child: _transcribing
                              ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accentText))
                              : Text(tr('Chuyển thành chữ'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, color: pal.accentText, fontWeight: FontWeight.w600)),
                        ),
                      ),
              ),
            ]),
          ]),
        ),
      ]),
      if (transcript != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: SelectableText(transcript, style: TextStyle(fontSize: 15, color: pal.text, height: 1.3)),
        ),
      ]),
    );
  }
}

/// Tỉ lệ khung ảnh, đọc từ đầu file.
Future<double> imageAspect(String path) async {
  try {
    final buf = await ui.ImmutableBuffer.fromFilePath(path);
    final desc = await ui.ImageDescriptor.encoded(buf);
    final r = desc.width / desc.height;
    desc.dispose();
    buf.dispose();
    return r;
  } catch (_) {
    return 4 / 3;
  }
}

/// Lưu ảnh [path] vào thư viện ảnh (điện thoại) hoặc thư mục Tải về (máy tính, không ghi đè tệp trùng tên).
/// Lỗi thì ném, kèm lý do (vd chưa cho quyền ảnh). Trả về nơi đã lưu (đường dẫn trên máy tính, tên album trên điện thoại).
/// [into]: thư mục lưu trên máy tính thay cho Tải về (kiểm thử).
Future<String> saveImageFile(String path, {Directory? into}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
      throw Exception(tr('chưa cho phép Flygo Chat lưu vào thư viện ảnh (Cài đặt → Flygo Chat → Ảnh)'));
    }
    await Gal.putImage(path, album: 'Flygo Chat');
    return 'Flygo Chat';
  }
  final dir = into ?? await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name, ext = dot > 0 ? name.substring(dot) : '';
  var dst = File('${dir.path}${Platform.pathSeparator}$name');
  for (var i = 1; await dst.exists(); i++) {
    dst = File('${dir.path}${Platform.pathSeparator}$base ($i)$ext');
  }
  await File(path).copy(dst.path);
  return dst.path;
}

/// Lý do lưu ảnh lỗi, dễ đọc (bỏ tiền tố Exception / GalException).
String saveErrorText(Object e) {
  if (e is GalException) {
    return switch (e.type) {
      GalExceptionType.accessDenied => tr('chưa cho phép Flygo Chat lưu vào thư viện ảnh (Cài đặt → Flygo Chat → Ảnh)'),
      GalExceptionType.notEnoughSpace => tr('máy hết dung lượng'),
      GalExceptionType.notSupportedFormat => tr('định dạng ảnh không được hỗ trợ'),
      GalExceptionType.unexpected => e.platformException.message ?? e.type.message,
    };
  }
  return '$e'.replaceFirst(RegExp(r'^(Exception|FileSystemException): ?'), '');
}

/// Lưu ảnh [path] vào thư viện ảnh (điện thoại) hoặc thư mục Tải về (máy tính). [notify] = false: không tự báo
/// (lưu nhiều ảnh thì người gọi báo một lần). Trả về true nếu lưu được. Cần lý do lỗi thì gọi [saveImageFile].
Future<bool> saveLocalImage(BuildContext context, String path, {bool notify = true}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await saveImageFile(path);
    if (notify) messenger.showSnackBar(toast(Text(Platform.isAndroid || Platform.isIOS ? tr('Đã lưu vào thư viện ảnh') : tr('Đã lưu vào thư mục Tải về'))));
    return true;
  } catch (e) {
    debugPrint('[save] $e');
    if (notify) messenger.showSnackBar(toast(Text(tr('Không lưu được ảnh: {0}', [saveErrorText(e)]))));
    return false;
  }
}

/// Các ảnh của một tin xếp dọc từ trên xuống. Chạm một ảnh để xem phóng to;
/// giữ một ảnh để vào chế độ chọn, rồi chuyển tiếp / tải các ảnh đã chọn.
class AlbumPage extends StatefulWidget {
  final MmPost post;
  final List<ChatImage> images;
  const AlbumPage({super.key, required this.post, required this.images});
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  final Set<int> _sel = {};
  bool _selecting = false;

  void _toggle(int i) => setState(() {
        _sel.contains(i) ? _sel.remove(i) : _sel.add(i);
        if (_sel.isEmpty) _selecting = false;
      });

  void _view(int i) => showGallery(context, widget.post, widget.images, i);

  List<MmFile> get _selectedFiles =>
      [for (final i in _sel.toList()..sort()) if (widget.images[i].file != null) widget.images[i].file!];

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    final sent = widget.post.sendState == SendState.sent;
    final sender = app.users[widget.post.userId]?.displayName ?? '';
    final when = DateTime.fromMillisecondsSinceEpoch(widget.post.createAt);
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 720.0);
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _selecting = false;
            _sel.clear();
          });
        }
      },
      child: EscToPop(
        child: Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(
            backgroundColor: pal.bg,
            surfaceTintColor: Colors.transparent,
            leading: _selecting
                ? IconButton(
                    icon: Icon(Icons.close, color: pal.text),
                    onPressed: () => setState(() {
                          _selecting = false;
                          _sel.clear();
                        }))
                : null,
            title: _selecting
                ? Text(tr('Đã chọn {0}', [_sel.length]), style: TextStyle(color: pal.text, fontWeight: FontWeight.w600))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('{0} ảnh', [widget.images.length]), style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, fontSize: 17)),
                    Text('$sender · ${two(when.hour)}:${two(when.minute)} ${two(when.day)}/${two(when.month)}',
                        style: TextStyle(color: pal.sub, fontSize: 13)),
                  ]),
            actions: [
              if (_selecting)
                TextButton(
                  onPressed: () => setState(() => _sel
                    ..clear()
                    ..addAll(List.generate(widget.images.length, (i) => i))),
                  child: Text(tr('Chọn tất cả'), style: TextStyle(color: pal.accentText)),
                ),
            ],
          ),
          body: ListView.builder(
            padding: const EdgeInsets.only(bottom: 90, top: 4),
            itemCount: widget.images.length,
            itemBuilder: (_, i) {
              final img = widget.images[i];
              final picked = _sel.contains(i);
              return Center(
                child: GestureDetector(
                  onTap: () => _selecting ? _toggle(i) : _view(i),
                  onLongPress: sent
                      ? () => setState(() {
                            _selecting = true;
                            _sel.add(i);
                          })
                      : null,
                  onSecondaryTap: sent
                      ? () => setState(() {
                            _selecting = true;
                            _sel.add(i);
                          })
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Stack(children: [
                      AnimatedScale(
                        scale: picked ? .94 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: SizedBox(
                          width: width,
                          height: width / img.aspect.clamp(.4, 3.0),
                          child: _Img(image: img, app: app),
                        ),
                      ),
                      if (_selecting)
                        Positioned(
                          right: 14,
                          top: 12,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: picked ? pal.accent : Colors.black26,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: picked ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                          ),
                        ),
                    ]),
                  ),
                ),
              );
            },
          ),
          bottomNavigationBar: _selecting && _sel.isNotEmpty
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: pal.accentText,
                            side: BorderSide(color: pal.accentText),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => saveMedia(context, _selectedFiles),
                          icon: const Icon(Icons.download),
                          label: Text(tr('Tải xuống')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: pal.accent,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            final files = _selectedFiles;
                            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ForwardPage(files: files)));
                            if (mounted) {
                              setState(() {
                                _selecting = false;
                                _sel.clear();
                              });
                            }
                          },
                          icon: const Icon(Icons.shortcut),
                          label: Text(tr('Chuyển tiếp ({0})', [_sel.length])),
                        ),
                      ),
                    ]),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// Dữ liệu gốc của ảnh: ảnh trên máy đọc thẳng; ảnh trên máy chủ / Bảng tin / ảnh ngoài lấy qua bộ nhớ đệm trên đĩa
/// (đã xem thì không tải lại).
Future<Uint8List> chatImageBytes(AppState app, ChatImage img) async {
  final local = img.localPath ?? (img.file == null ? null : app.localPathFor(img.file!.id));
  if (local != null && File(local).existsSync()) return File(local).readAsBytes();
  final p = img.provider(app, full: true);
  if (p is DiskCachedImage) return p.bytes();
  if (p is MemoryImage) return p.bytes;
  if (p is FileImage) return p.file.readAsBytes();
  throw StateError('không đọc được ảnh');
}

/// Đuôi tệp theo nội dung ảnh.
String imageExt(Uint8List b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
  if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'webp';
  return 'jpg';
}

/// Sao chép ảnh vào bộ nhớ tạm (dán được như ảnh, không phải đường dẫn).
Future<void> copyChatImage(BuildContext context, ChatImage img) async {
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    final ok = await copyImageToClipboard(await chatImageBytes(app, img));
    messenger.showSnackBar(toast(Text(ok
        ? tr('Đã sao chép ảnh')
        : Platform.isLinux
            ? tr('Máy này chưa sao chép được ảnh (cần cài xclip hoặc wl-clipboard). Hãy dùng Tải ảnh.')
            : tr('Không sao chép được ảnh.'))));
  } catch (_) {
    messenger.showSnackBar(toast(Text(tr('Không sao chép được ảnh.'))));
  }
}

/// Tải ảnh: điện thoại lưu vào thư viện ảnh, máy tính lưu vào thư mục Tải về.
Future<void> saveChatImage(BuildContext context, ChatImage img) async {
  final app = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  String path;
  try {
    final local = img.localPath ?? (img.file == null ? null : app.localPathFor(img.file!.id));
    if (local != null && File(local).existsSync()) {
      path = local;
    } else {
      final bytes = await chatImageBytes(app, img);
      final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}flygo-save');
      await dir.create(recursive: true);
      final name = img.file?.name.contains('.') == true ? img.file!.name : 'anh-${DateTime.now().millisecondsSinceEpoch}.${imageExt(bytes)}';
      path = '${dir.path}${Platform.pathSeparator}${name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
      await File(path).writeAsBytes(bytes);
    }
  } catch (_) {
    messenger.showSnackBar(toast(Text(tr('Không tải được file. Kiểm tra kết nối mạng.'))));
    return;
  }
  if (context.mounted) await saveLocalImage(context, path);
}

/// Video trong tin nhắn: hiện khung hình đầu của video (đang gửi thì kèm vòng tải), bấm để xem.
/// Windows / Linux chưa có trình phát video nhúng: hiện thẻ video như cũ.
class ChatVideo extends StatefulWidget {
  final MmFile? file;
  final String? localPath;
  final bool sending;
  const ChatVideo({super.key, this.file, this.localPath, this.sending = false});
  @override
  State<ChatVideo> createState() => _ChatVideoState();
}

class _ChatVideoState extends State<ChatVideo> {
  VideoPlayerController? _v;
  bool _failed = false;

  static bool get supported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (!supported) return;
    final app = context.read<AppState>();
    final local = widget.localPath ?? (widget.file == null ? null : app.localPathFor(widget.file!.id));
    final v = _v = local != null && File(local).existsSync()
        ? VideoPlayerController.file(File(local))
        : VideoPlayerController.networkUrl(Uri.parse(app.api.fileUrl(widget.file!.id)), httpHeaders: app.api.headers);
    v.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _v?.dispose();
    super.dispose();
  }

  void _open() {
    final f = widget.file;
    if (f != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerPage(file: f)));
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final ready = v != null && v.value.isInitialized && !_failed;
    final aspect = ready ? v.value.aspectRatio.clamp(.56, 1.8) : 16 / 10;
    const w = 260.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: GestureDetector(
        onTap: widget.sending ? null : _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: w,
            height: (w / aspect).clamp(140.0, 380.0),
            color: Colors.black87,
            child: Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
              if (ready) FittedBox(fit: BoxFit.cover, child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v))),
              Center(
                child: widget.sending
                    ? Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                      )
                    : const Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
              ),
              Positioned(
                left: 10,
                bottom: 8,
                right: 10,
                child: Row(children: [
                  const Icon(Icons.videocam, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      ready ? _fmt(v.value.duration) : (widget.file?.name ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 4)]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
