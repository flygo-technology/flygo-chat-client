// Drive: xem tệp trong app — ảnh (vuốt qua lại, chụm phóng to), PDF (pdfrx), video / âm thanh, văn bản.
// Dùng bản ghim offline nếu có (xem được khi mất mạng), không thì tải vào thư mục tạm.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:video_player/video_player.dart';

import '../../i18n/i18n.dart';
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
    return Theme(
      data: Theme.of(context).copyWith(iconTheme: const IconThemeData(color: fg)),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0D12),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0D12),
          foregroundColor: fg,
          title: Text(_cur.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, color: fg)),
          actions: [
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
                itemCount: _items.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _Viewer(key: ValueKey(_items[i].path), session: widget.session, item: _items[i]),
              )
            : _Viewer(session: widget.session, item: _cur),
      ),
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer({super.key, required this.session, required this.item});
  final DriveSession session;
  final DriveItem item;
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
      final f = await localCopy(widget.session, widget.item, onProgress: (got, total) {
        if (mounted && total > 0) setState(() => _progress = got / total);
      });
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
          Text(_progress > 0 ? '${(_progress * 100).round()}%' : tr('Đang tải…'), style: const TextStyle(color: fg)),
        ]),
      );
    }
    switch (_kind) {
      case DriveKind.image:
        return InteractiveViewer(
          maxScale: 8,
          child: Center(child: Image.file(f, errorBuilder: (_, _, _) => Text(tr('Không hiển thị được ảnh này'), style: const TextStyle(color: fg)))),
        );
      case DriveKind.pdf:
        return Stack(children: [
          PdfViewer.file(
            f.path,
            params: PdfViewerParams(
              backgroundColor: const Color(0xFF0B0D12),
              margin: 12,
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
