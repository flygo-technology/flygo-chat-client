// Drive: xem tệp trong app — ảnh (vuốt qua lại, chụm phóng to), PDF (pdfrx), video / âm thanh, văn bản.
// Dùng bản ghim offline nếu có (xem được khi mất mạng), không thì tải vào thư mục tạm.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

import '../../i18n/i18n.dart';
import '../mail/attachments.dart' show mailPdfParams;
import '../theme.dart' show toast;
import 'actions.dart';
import 'api.dart';
import 'look.dart';
import 'session.dart';

class DrivePreviewPage extends StatefulWidget {
  const DrivePreviewPage({super.key, required this.session, required this.item, this.gallery = const []});
  final DriveSession session;
  final DriveItem item;
  /// Các ảnh cùng thư mục (vuốt qua lại); rỗng = chỉ tệp này.
  final List<DriveItem> gallery;
  @override
  State<DrivePreviewPage> createState() => _DrivePreviewPageState();
}

class _DrivePreviewPageState extends State<DrivePreviewPage> {
  late List<DriveItem> _items;
  late int _index;
  late final PageController _pages;
  /// Ảnh đang phóng to: khoá vuốt qua ảnh khác (kéo để xem phần còn lại).
  bool _zoomed = false;

  DriveItem get _cur => _items[_index];

  @override
  void initState() {
    super.initState();
    _items = widget.gallery.isEmpty ? [widget.item] : widget.gallery;
    _index = _items.indexWhere((x) => x.path == widget.item.path).clamp(0, _items.length - 1);
    if (_items.isEmpty || _items[_index].path != widget.item.path) {
      _items = [widget.item];
      _index = 0;
    }
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFFE6E9F0);
    void go(int d) {
      final i = _index + d;
      if (_items.length > 1 && i >= 0 && i < _items.length) _pages.animateToPage(i, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }

    // Esc thoát xem trước; ← → chuyển ảnh.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => go(1),
      },
      child: Focus(
        autofocus: true,
        child: Theme(
      data: Theme.of(context).copyWith(iconTheme: const IconThemeData(color: fg)),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0D12),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0D12),
          foregroundColor: fg,
          title: Text(_cur.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, color: fg)),
          actions: [
            // Word / Excel / PowerPoint: xem ở đây; sửa bằng OnlyOffice ở tab riêng, chỉ trên máy tính.
            if (isOffice(_cur) && canEditOffice && _cur.canWrite)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: FilledButton.icon(
                  onPressed: () => openOffice(context, widget.session, _cur),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text(tr('Chỉnh sửa')),
                ),
              ),
            IconButton(tooltip: tr('Chia sẻ'), icon: const Icon(Icons.person_add_alt_1_rounded), onPressed: () => showShareDialog(context, widget.session, _cur)),
            IconButton(
              tooltip: tr('Thêm'),
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () => showItemActions(context, widget.session, _cur, onChanged: () => setState(() {}), fromPreview: true),
            ),
          ],
        ),
        body: _items.length > 1
            ? PageView.builder(
                controller: _pages,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: _items.length,
                onPageChanged: (i) => setState(() {
                  _index = i;
                  _zoomed = false;
                }),
                itemBuilder: (_, i) => _Viewer(key: ValueKey(_items[i].path), session: widget.session, item: _items[i], onZoom: (z) => z != _zoomed ? setState(() => _zoomed = z) : null),
              )
            : _Viewer(session: widget.session, item: _cur),
      ),
        ),
      ),
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({super.key, required this.session, required this.item, this.onZoom});
  final DriveSession session;
  final DriveItem item;
  final ValueChanged<bool>? onZoom;
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  File? _file;
  Object? _error;
  double _progress = 0;
  VideoPlayerController? _video;
  String? _text;
  int _page = 1, _pageCount = 0;

  DriveKind get _kind => kindOf(widget.item);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      void prog(int got, int total) {
        if (mounted && total > 0) setState(() => _progress = got / total);
      }

      // Office: bản PDF máy chủ chuyển (lần đầu mất vài giây, sau đó lấy từ cache).
      final f = isOffice(widget.item) ? await previewPdf(widget.session, widget.item, onProgress: prog) : await localCopy(widget.session, widget.item, onProgress: prog);
      if (_kind == DriveKind.video || _kind == DriveKind.audio) {
        final v = VideoPlayerController.file(f);
        await v.initialize();
        await v.play();
        _video = v..addListener(() => mounted ? setState(() {}) : null);
      } else if (_kind == DriveKind.text || _kind == DriveKind.code) {
        final len = await f.length();
        _text = len > 2 * 1024 * 1024 ? tr('Tệp quá lớn để xem trực tiếp ({0}).', [fmtSize(len)]) : await f.readAsString().catchError((_) => tr('Không đọc được nội dung (không phải UTF-8).'));
      }
      if (mounted) setState(() => _file = f);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFFE6E9F0);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, color: fg, size: 48),
            const SizedBox(height: 12),
            Text(tr('Không tải được tệp'), style: const TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('$_error', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9AA3B5))),
          ]),
        ),
      );
    }
    final f = _file;
    if (f == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 56, height: 56, child: CircularProgressIndicator(value: _progress > 0 ? _progress : null, color: fg)),
          const SizedBox(height: 14),
          Text(_progress > 0 ? '${(_progress * 100).round()}%' : (isOffice(widget.item) ? tr('Đang chuẩn bị bản xem…') : tr('Đang tải…')), style: const TextStyle(color: fg)),
        ]),
      );
    }
    switch (_kind) {
      case DriveKind.image:
        return ZoomImage(
          onZoom: widget.onZoom,
          child: Image.file(f, errorBuilder: (_, _, _) => Text(tr('Không hiển thị được ảnh này'), style: const TextStyle(color: fg))),
        );
      case DriveKind.pdf:
      case DriveKind.doc:
      case DriveKind.sheet:
      case DriveKind.slide:
        return Stack(children: [
          PdfViewer.file(
            f.path,
            // Giống trình xem PDF của Thư: mở ra thấy trọn trang, lăn chuột cuộn như trang thường, Ctrl + lăn / chụm phóng to.
            params: PdfViewerParams(
              backgroundColor: mailPdfParams.backgroundColor,
              margin: mailPdfParams.margin,
              scrollByMouseWheel: mailPdfParams.scrollByMouseWheel,
              sizeDelegateProvider: mailPdfParams.sizeDelegateProvider,
              onKey: mailPdfParams.onKey,
              onViewerReady: (doc, c) => setState(() => _pageCount = doc.pages.length),
              onPageChanged: (n) => setState(() => _page = n ?? _page),
            ),
          ),
          if (_pageCount > 0)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(color: const Color(0xEB282D3C), borderRadius: BorderRadius.circular(18)),
                  child: Text('$_page / $_pageCount', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
            ),
        ]);
      case DriveKind.video:
      case DriveKind.audio:
        final v = _video;
        if (v == null) return const SizedBox();
        return Column(children: [
          Expanded(
            child: Center(
              child: _kind == DriveKind.audio
                  ? const Icon(Icons.music_note_rounded, color: fg, size: 96)
                  : AspectRatio(aspectRatio: v.value.aspectRatio == 0 ? 16 / 9 : v.value.aspectRatio, child: VideoPlayer(v)),
            ),
          ),
          VideoProgressIndicator(v, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              iconSize: 40,
              color: fg,
              icon: Icon(v.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
              onPressed: () => v.value.isPlaying ? v.pause() : v.play(),
            ),
            Text('${_dur(v.value.position)} / ${_dur(v.value.duration)}', style: const TextStyle(color: fg)),
          ]),
          const SizedBox(height: 16),
        ]);
      case DriveKind.text:
      case DriveKind.code:
        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_text ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.45)),
          ),
        );
      default:
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await openWithSystem(f);
          } catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
          }
        });
        return const SizedBox();
    }
  }

  String _dur(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

/// Ảnh phóng to được: chụm (màn cảm ứng, touchpad) hoặc Ctrl / ⌘ + lăn chuột phóng to quanh con trỏ; lăn chuột thường
/// và kéo để xem phần còn lại khi đang phóng to; nhấp đúp phóng to 2,5× / về vừa màn hình.
class ZoomImage extends StatefulWidget {
  const ZoomImage({super.key, required this.child, this.onZoom});
  final Widget child;
  final ValueChanged<bool>? onZoom;
  @override
  State<ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<ZoomImage> {
  final _tc = TransformationController();
  final _view = GlobalKey();
  Offset? _tapAt;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(() {
      final z = _tc.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) {
        _zoomed = z;
        widget.onZoom?.call(z);
      }
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  /// [focal]: điểm trong khung nhìn (toạ độ của InteractiveViewer).
  void _zoomBy(double k, Offset focal) {
    final cur = _tc.value.getMaxScaleOnAxis();
    final to = (cur * k).clamp(1.0, 8.0);
    if (to <= 1.001) {
      _tc.value = Matrix4.identity();
      return;
    }
    final f = to / cur;
    _tc.value = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1)
      ..multiply(_tc.value);
  }

  void _pan(Offset d) {
    if (!_zoomed) return;
    _tc.value = Matrix4.identity()
      ..translateByDouble(-d.dx, -d.dy, 0, 1)
      ..multiply(_tc.value);
  }

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    // Đăng ký trước InteractiveViewer (widget con được hỏi trước): lăn chuột thường không phóng to như mặc định.
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final s = ev as PointerScrollEvent;
      final box = _view.currentContext?.findRenderObject() as RenderBox?;
      final focal = box?.globalToLocal(s.position) ?? Offset.zero;
      final k = HardwareKeyboard.instance;
      if (k.isControlPressed || k.isMetaPressed) {
        _zoomBy(s.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15, focal);
      } else {
        _pan(s.scrollDelta);
      }
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: () => _zoomed ? _tc.value = Matrix4.identity() : _zoomBy(2.5, _tapAt ?? Offset.zero),
        child: InteractiveViewer(
          key: _view,
          transformationController: _tc,
          maxScale: 8,
          child: Listener(onPointerSignal: _signal, child: SizedBox.expand(child: Center(child: widget.child))),
        ),
      );
}
