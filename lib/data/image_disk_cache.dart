import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// Bộ nhớ đệm ảnh trên đĩa (giữ qua các lần mở app): ảnh đã xem (ảnh gốc, ảnh xem trước, ảnh nhỏ) không tải lại.
/// Khoá là định danh ổn định của ảnh (máy chủ + mã tệp + cỡ), không phải địa chỉ có vé. Giới hạn dung lượng, quá thì
/// xoá ảnh lâu chưa dùng nhất (mỗi lần dùng ảnh thì cập nhật giờ sửa tệp).
class ImageDiskCache {
  /// [now]: đồng hồ dùng làm "lần dùng gần nhất" (kiểm thử truyền đồng hồ giả để thứ tự xoá không phụ thuộc độ phân giải giờ tệp).
  ImageDiskCache({Future<Directory> Function()? dir, this.maxBytes = 400 * 1024 * 1024, DateTime Function()? now})
      : _dirFn = dir ?? _defaultDir,
        _now = now ?? DateTime.now;

  static ImageDiskCache instance = ImageDiskCache();

  final int maxBytes;
  final Future<Directory> Function() _dirFn;
  final DateTime Function() _now;
  final Set<Future<void>> _pending = {};
  Future<Directory>? _dir;
  final Map<String, Future<Uint8List>> _inflight = {};
  int? _total;

  static Future<Directory> _defaultDir() async => Directory('${(await getApplicationCacheDirectory()).path}${Platform.pathSeparator}flygo-images');

  Future<Directory> get _root => _dir ??= () async {
        final d = await _dirFn();
        await d.create(recursive: true);
        return d;
      }();

  Future<File> _file(String key) async => File('${(await _root).path}${Platform.pathSeparator}${sha1.convert(key.codeUnits)}');

  /// Ảnh [key]: có trên đĩa thì đọc, chưa có thì [fetch] rồi lưu. Nhiều nơi cùng hỏi một ảnh thì chỉ tải một lần.
  Future<Uint8List> get(String key, Future<Uint8List> Function() fetch) {
    final running = _inflight[key];
    if (running != null) return running;
    // Khối lệnh (không trả về Future vừa bỏ ra khỏi danh sách: whenComplete sẽ chờ chính nó).
    final f = _get(key, fetch).whenComplete(() {
      _inflight.remove(key);
    });
    return _inflight[key] = f;
  }

  Future<Uint8List> _get(String key, Future<Uint8List> Function() fetch) async {
    final f = await _file(key);
    try {
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        if (bytes.isNotEmpty) {
          _track(f.setLastModified(_now()).catchError((_) {}));
          return bytes;
        }
      }
    } catch (_) {}
    final bytes = await fetch();
    if (bytes.isNotEmpty) _track(_put(f, bytes));
    return bytes;
  }

  /// Ghi đĩa / cập nhật giờ dùng chạy nền (không bắt người xem ảnh chờ); [flush] chờ các việc đó xong.
  void _track(Future<void> f) {
    _pending.add(f);
    f.whenComplete(() {
      _pending.remove(f);
    });
  }

  /// Còn việc ghi đĩa đang chạy.
  bool get busy => _pending.isNotEmpty;

  /// Chờ mọi việc ghi đĩa đang chạy xong.
  Future<void> flush() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  /// Đã có trên đĩa chưa (không tải).
  Future<bool> has(String key) async => (await _file(key)).exists();

  Future<void> _put(File f, Uint8List bytes) async {
    try {
      final before = await _size();
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      await f.setLastModified(_now());
      _total = before + bytes.length;
      if (_total! > maxBytes) await prune();
    } catch (_) {}
  }

  Future<int> _size() async {
    if (_total != null) return _total!;
    var n = 0;
    await for (final e in (await _root).list()) {
      if (e is File) n += await e.length().catchError((_) => 0);
    }
    return _total = n;
  }

  /// Xoá ảnh lâu chưa dùng nhất cho tới khi còn dưới 80% giới hạn.
  Future<void> prune() async {
    final files = <(File, int, DateTime)>[];
    await for (final e in (await _root).list()) {
      if (e is! File) continue;
      try {
        final s = await e.stat();
        files.add((e, s.size, s.modified));
      } catch (_) {}
    }
    var total = files.fold<int>(0, (a, f) => a + f.$2);
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (f, size, _) in files) {
      if (total <= maxBytes * .8) break;
      try {
        await f.delete();
        total -= size;
      } catch (_) {}
    }
    _total = total;
  }
}

/// Tải ảnh qua mạng (kèm [headers]); lỗi thì ném, không lưu vào bộ nhớ đệm.
Future<Uint8List> fetchImageBytes(String url, {Map<String, String>? headers, http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw HttpException('HTTP ${r.statusCode}', uri: Uri.parse(url));
    return r.bodyBytes;
  } finally {
    if (client == null) c.close();
  }
}

/// Khoá đệm ổn định cho tệp [fileId] của máy chủ chat hiện tại ([size]: full / preview / thumb).
String chatImageKey(String fileId, String size) => 'mm:${Uri.tryParse(kServerUrl)?.host ?? ''}:$fileId:$size';

/// Ảnh đọc qua [ImageDiskCache]. Hai ảnh cùng [cacheKey] là một (dùng chung trong bộ nhớ lẫn trên đĩa).
@immutable
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  final String cacheKey;
  final Future<Uint8List> Function() fetch;
  final ImageDiskCache? cache;
  const DiskCachedImage(this.cacheKey, this.fetch, {this.cache});

  /// Ảnh qua mạng tại [url] (kèm [headers]), đệm theo [cacheKey].
  factory DiskCachedImage.network(String cacheKey, String url, {Map<String, String>? headers}) =>
      DiskCachedImage(cacheKey, () => fetchImageBytes(url, headers: headers));

  ImageDiskCache get _cache => cache ?? ImageDiskCache.instance;

  /// Dữ liệu ảnh (từ đĩa nếu đã có, không thì tải rồi lưu).
  Future<Uint8List> bytes() => _cache.get(cacheKey, fetch);

  /// Tải sẵn về đĩa (không giải mã, không tốn bộ nhớ).
  Future<void> prefetch() => _cache.get(cacheKey, fetch).then((_) {});

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(DiskCachedImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: cacheKey);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await _cache.get(cacheKey, fetch);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is DiskCachedImage && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'DiskCachedImage($cacheKey)';
}

/// Giải mã ảnh nhỏ đúng cỡ hiển thị (rộng [width] điểm ảnh logic), không giải mã cả ảnh gốc vào bộ nhớ.
ImageProvider sizedImage(BuildContext context, ImageProvider image, double width) {
  if (!width.isFinite || width <= 0) return image;
  return ResizeImage.resizeIfNeeded((width * MediaQuery.devicePixelRatioOf(context)).round(), null, image);
}
