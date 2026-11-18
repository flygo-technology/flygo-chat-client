// Thư: trình xem ảnh của một thư — mọi ảnh của thư (ảnh dán trong thư, ảnh từ mạng khi đã cho hiện, ảnh đính kèm)
// xếp dọc như Bảng tin (PhotoZoomScope + PhotoColumn): chụm / bấm đúp / Ctrl + lăn chuột để phóng to, thu nhỏ hết cỡ
// là về danh sách; phím mũi tên sang ảnh trước / sau, Esc đóng. Thao tác: Tải về, Lưu vào Drive, In, Sao chép ảnh.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/image_disk_cache.dart';
import '../bang_tin/photo_list.dart';
import 'attachments.dart';
import 'model.dart';

/// Một ảnh của thư: ảnh trong thân thư ([src]) hoặc ảnh đính kèm ([attachment]).
class MailPhoto {
  const MailPhoto.body(String this.src, {this.name = ''}) : attachment = null;
  MailPhoto.attachment(MailAttachment this.attachment)
      : src = null,
        name = attachment.name;
  final String? src;
  final MailAttachment? attachment;
  final String name;
}

/// Ảnh của một thư cho [PhotoColumn]: mã ảnh = vị trí trong [photos] kèm mã thư (tỉ lệ ảnh được nhớ theo mã).
class MailPhotos extends PhotoSource {
  MailPhotos({required this.messageId, required this.photos, required this.files, this.inlineImage, this.saveToDrive});
  final String messageId;
  final List<MailPhoto> photos;
  final AttachmentFiles files;
  final Future<Uint8List?> Function(String path)? inlineImage;
  final SaveToDrive? saveToDrive;
  final _bytes = <int, Future<Uint8List>>{};

  /// Ảnh trong thân thư [photos] cùng ảnh đính kèm (bỏ tệp đính kèm trùng ảnh đã dán trong thư).
  factory MailPhotos.of(MailMessage m, List<String> body, AttachmentFiles files,
      {Future<Uint8List?> Function(String path)? inlineImage, SaveToDrive? saveToDrive}) {
    String path(String u) => u.split('?').first;
    final inBody = body.map(path).toSet();
    return MailPhotos(
      messageId: m.id,
      files: files,
      inlineImage: inlineImage,
      saveToDrive: saveToDrive,
      photos: [
        for (final s in body) MailPhoto.body(s),
        for (final a in m.attachments)
          if (isImageAttachment(a) && !inBody.contains(path(a.url))) MailPhoto.attachment(a),
      ],
    );
  }

  List<String> get ids => [for (var i = 0; i < photos.length; i++) '$messageId#$i'];

  int indexOfSrc(String src) => photos.indexWhere((p) => p.src == src);
  int indexOfAttachment(MailAttachment a) => photos.indexWhere((p) => p.attachment?.id == a.id);

  MailPhoto _photo(String id) => photos[int.parse(id.substring(id.lastIndexOf('#') + 1))];

  Future<Uint8List> bytes(String id) {
    final i = int.parse(id.substring(id.lastIndexOf('#') + 1));
    return _bytes.putIfAbsent(i, () => _load(i)..catchError((Object _) {
          _bytes.remove(i);
          return Uint8List(0);
        }));
  }

  Future<Uint8List> _load(int i) async {
    final p = photos[i], a = p.attachment;
    if (a != null) return (await files.file(a)).readAsBytes();
    final src = p.src!;
    if (src.startsWith('/mail/api/attachments/')) {
      final b = await inlineImage?.call(src);
      if (b == null) throw StateError('Không tải được ảnh');
      return b;
    }
    return fetchImageBytes(src);
  }

  @override
  ImageProvider image(String id) => _MailImage(this, id);

  @override
  Widget thumb(BuildContext context, String id, BoxFit fit) => LayoutBuilder(
        builder: (context, c) => Image(
          image: sizedImage(context, image(id), math.max(c.maxWidth, c.maxHeight)),
          fit: fit,
          gaplessPlayback: true,
          frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54)),
        ),
      );

  /// Tệp trên máy của ảnh (tệp đính kèm: bản đã tải; ảnh trong thư: ghi ra thư mục tạm), kèm tên và kiểu.
  Future<(File, String, String)> _file(String id) async {
    final p = _photo(id), a = p.attachment;
    if (a != null) return (await files.file(a), a.name, a.type);
    final b = await bytes(id);
    final ext = _ext(b);
    final seg = Uri.tryParse(p.src!)?.pathSegments.lastOrNull ?? '';
    var name = p.name.isNotEmpty ? p.name : seg;
    if (!RegExp(r'\.(jpe?g|png|gif|webp|bmp)$', caseSensitive: false).hasMatch(name)) {
      name = 'anh-thu-${ids.indexOf(id) + 1}.$ext';
    }
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}mail-anh');
    await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(b);
    return (f, name, 'image/${ext == 'jpg' ? 'jpeg' : ext}');
  }

  static String _ext(Uint8List b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
    if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'webp';
    return 'jpg';
  }

  @override
  List<PhotoAction> actions(BuildContext context, List<String> ids, int index) {
    final id = ids[index];
    void snack(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));
    return [
      PhotoAction(Icons.download_rounded, 'Tải về', key: const ValueKey('photo-download'), bar: true, () async {
        try {
          final (f, name, type) = await _file(id);
          final p = await downloadFile(f, name, type);
          if (p != null) snack('Đã lưu vào Tải về: ${p.split(Platform.pathSeparator).last}');
        } catch (e) {
          snack('Không tải được: $e');
        }
      }),
      if (saveToDrive != null)
        PhotoAction(Icons.add_to_drive_rounded, 'Lưu vào Drive', key: const ValueKey('photo-drive'), bar: true, () async {
          try {
            final (f, name, _) = await _file(id);
            if (context.mounted) await saveToDrive!(context, [(f.path, name)]);
          } catch (e) {
            snack('Không lưu được: $e');
          }
        }),
      PhotoAction(Icons.print_outlined, 'In', key: const ValueKey('photo-print'), () async {
        try {
          final b = await bytes(id);
          await printPdfBytes(_photo(id).name.isEmpty ? 'anh.pdf' : _photo(id).name, await imageToPdf(b));
        } catch (e) {
          snack('Không in được: $e');
        }
      }),
      PhotoAction(Icons.copy_rounded, 'Sao chép ảnh', key: const ValueKey('photo-copy'), bar: true, () => copyPhoto(context, () => bytes(id))),
    ];
  }
}

/// Ảnh của thư đọc qua [MailPhotos.bytes] (giữ trong bộ nhớ, không ghi ra bộ nhớ đệm đĩa dùng chung).
@immutable
class _MailImage extends ImageProvider<_MailImage> {
  const _MailImage(this.source, this.id);
  final MailPhotos source;
  final String id;

  @override
  Future<_MailImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_MailImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: id);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async => decode(await ui.ImmutableBuffer.fromUint8List(await source.bytes(id)));

  @override
  bool operator ==(Object other) => other is _MailImage && identical(other.source, source) && other.id == id;

  @override
  int get hashCode => Object.hash(identityHashCode(source), id);
}

/// Mở trình xem ảnh của thư tại ảnh [index] (trang mới: thư bên dưới giữ nguyên chỗ cuộn).
Future<void> openMailPhotos(BuildContext context, MailPhotos photos, int index) {
  if (photos.photos.isEmpty) return Future.value();
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MailPhotoPage(photos: photos, index: index.clamp(0, photos.photos.length - 1))));
}

class MailPhotoPage extends StatefulWidget {
  const MailPhotoPage({super.key, required this.photos, required this.index});
  final MailPhotos photos;
  final int index;

  @override
  State<MailPhotoPage> createState() => _MailPhotoPageState();
}

class _MailPhotoPageState extends State<MailPhotoPage> {
  static const _bg = Color(0xFF0B0D12);
  final _scope = GlobalKey<PhotoZoomScopeState>();
  late final _keys = [for (final _ in widget.photos.photos) GlobalKey()];
  late int _cur = widget.index;
  bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jump());
  }

  /// Mở ở ảnh vừa bấm (ảnh phía trên tải xong đổi chiều cao thì giữ lại cho tới khi người dùng tự cuộn).
  void _jump() {
    if (!mounted || _userScrolled) return;
    final c = _keys[widget.index].currentContext;
    if (c != null) Scrollable.ensureVisible(c, alignment: widget.index == 0 ? 0 : .5);
  }

  bool _tracking = false;

  /// Ảnh đang xem sau khi danh sách vẽ lại ở chỗ cuộn mới (lúc nhận thông báo cuộn, khung ảnh còn ở chỗ cũ).
  void _track() {
    if (_tracking) return;
    _tracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tracking = false;
      final i = _scope.currentState?.currentIndex;
      if (mounted && i != null && i != _cur) setState(() => _cur = i);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photos;
    final ids = p.ids;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(scaffoldBackgroundColor: _bg),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          leading: IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.maybePop(context)),
          title: Text(
            p.photos.length > 1 ? '${_cur + 1}/${p.photos.length}' : (p.photos.first.name.isEmpty ? 'Ảnh' : p.photos.first.name),
            style: const TextStyle(fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            for (final a in p.actions(context, ids, _cur))
              IconButton(key: a.key, tooltip: a.label, icon: Icon(a.icon), onPressed: a.run),
            const SizedBox(width: 4),
          ],
        ),
        body: PhotoZoomScope(
          key: _scope,
          source: p,
          keyboard: true,
          dark: true,
          builder: (context, locked) => NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is UserScrollNotification) _userScrolled = true;
              if (n is ScrollUpdateNotification || n is ScrollEndNotification) _track();
              return false;
            },
            child: ListView(
              key: const ValueKey('mail-photos'),
              physics: locked ? const NeverScrollableScrollPhysics() : null,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: PhotoColumn(
                      source: p,
                      ids: ids,
                      gap: 8,
                      keys: _keys,
                      onAspect: () => WidgetsBinding.instance.addPostFrameCallback((_) => _jump()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
