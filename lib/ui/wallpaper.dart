// Hình nền Trang chủ (máy tính): bộ ảnh phong cảnh Việt Nam nằm trên máy chủ chat (tệp tĩnh flygo-wallpapers:
// wallpapers.json + ảnh gốc + thumbs/, nguồn Wikimedia Commons có ghi tác giả) hoặc ảnh tự chọn, kèm độ mờ. App chỉ
// nhận đường dẫn; ảnh được chọn tải về thư mục app một lần. Lựa chọn chỉ lưu trên máy này (wallpaper.json).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../i18n/i18n.dart';
import 'theme.dart';
import 'common.dart' show pickFilesOrReport;

class WallpaperState {
  /// Tên ảnh trong bộ ảnh của máy chủ (vd vn01.jpg), hoặc null.
  final String? asset;
  /// Tệp ảnh trên máy (ảnh tự chọn đã chép, hoặc ảnh máy chủ đã tải về), hoặc null.
  final String? file;
  /// Độ mờ 0–30.
  final double blur;
  const WallpaperState({this.asset, this.file, this.blur = 0});
  bool get isSet => file != null;

  Map<String, Object?> toJson() => {'asset': asset, 'file': file, 'blur': blur};
  static WallpaperState fromJson(Object? j) => j is Map
      ? WallpaperState(asset: j['asset'] as String?, file: j['file'] as String?, blur: ((j['blur'] as num?) ?? 0).toDouble().clamp(0, 30))
      : const WallpaperState();
}

class Wallpaper {
  Wallpaper._();
  static final state = ValueNotifier<WallpaperState>(const WallpaperState());
  static bool _loaded = false;
  static List<Map<String, dynamic>> _credits = const [];

  static Future<File> _cfg() async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}wallpaper.json');

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _cfg();
      if (f.existsSync()) {
        final s = WallpaperState.fromJson(jsonDecode(f.readAsStringSync()));
        if (s.file != null && File(s.file!).existsSync()) {
          state.value = s;
        } else if (s.asset != null) {
          // Ảnh máy chủ chưa có trên máy (bản cũ để ảnh trong app, hoặc tệp bị xoá): tải lại.
          state.value = WallpaperState(blur: s.blur);
          final path = await download(s.asset!);
          if (path != null) await set(WallpaperState(asset: s.asset, file: path, blur: s.blur));
        } else {
          state.value = WallpaperState(blur: s.blur);
        }
      }
    } catch (_) {}
  }

  static Future<void> set(WallpaperState s) async {
    state.value = s;
    try {
      (await _cfg()).writeAsStringSync(jsonEncode(s.toJson()));
    } catch (_) {}
  }

  static String get _base => staticBase('flygo-wallpapers');
  static String url(String path) => '$_base/$path';

  /// Danh sách ảnh của máy chủ (wallpapers.json: file, thumb, name, author, license, source).
  static Future<List<Map<String, dynamic>>> credits() async {
    if (_credits.isNotEmpty) return _credits;
    try {
      final r = await http.get(Uri.parse(url('wallpapers.json'))).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
        _credits = [for (final c in j['items'] as List) (c as Map).cast<String, dynamic>()];
      }
    } catch (_) {}
    return _credits;
  }

  /// Tải ảnh gốc của máy chủ về thư mục app (dùng lại nếu đã có), trả về đường dẫn tệp.
  static Future<String?> download(String name) async {
    try {
      final dir = (await getApplicationSupportDirectory()).path;
      final dst = File('$dir${Platform.pathSeparator}wallpaper_srv_$name');
      if (dst.existsSync() && dst.lengthSync() > 0) return dst.path;
      final r = await http.get(Uri.parse(url(name))).timeout(const Duration(seconds: 60));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      final tmp = File('${dst.path}.part');
      await tmp.writeAsBytes(r.bodyBytes, flush: true);
      await tmp.rename(dst.path);
      return dst.path;
    } catch (_) {
      return null;
    }
  }

  /// Chọn ảnh của máy chủ: tải về rồi mới đổi nền; xoá ảnh cũ đã tải / ảnh tự chọn cũ.
  static Future<bool> choose(String name) async {
    final path = await download(name);
    if (path == null) return false;
    final old = state.value.file;
    await set(WallpaperState(asset: name, file: path, blur: state.value.blur));
    if (old != null && old != path) {
      try {
        File(old).deleteSync();
      } catch (_) {}
    }
    return true;
  }

  /// Chép ảnh tự chọn vào thư mục app (ảnh gốc có bị xoá / di chuyển thì hình nền vẫn còn).
  static Future<String?> importFile(String path) async {
    try {
      final dir = (await getApplicationSupportDirectory()).path;
      final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '.jpg';
      final dst = '$dir${Platform.pathSeparator}wallpaper_custom_${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(path).copy(dst);
      // Xoá ảnh tự chọn cũ.
      final old = state.value.file;
      if (old != null && old != dst) {
        try {
          File(old).deleteSync();
        } catch (_) {}
      }
      return dst;
    } catch (_) {
      return null;
    }
  }

  static ImageProvider? provider(WallpaperState s) => s.file != null ? FileImage(File(s.file!)) : null;
}

/// Nền Trang chủ: ảnh phủ kín, làm mờ theo cài đặt, phủ một lớp màu nhạt để chữ dễ đọc.
class WallpaperBackground extends StatelessWidget {
  final Widget child;
  const WallpaperBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ValueListenableBuilder<WallpaperState>(
      valueListenable: Wallpaper.state,
      builder: (context, s, _) {
        final img = Wallpaper.provider(s);
        if (img == null) return child;
        Widget pic = Image(image: img, fit: BoxFit.cover, width: double.infinity, height: double.infinity, gaplessPlayback: true);
        if (s.blur > 0) pic = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: s.blur, sigmaY: s.blur, tileMode: TileMode.clamp), child: pic);
        return Stack(fit: StackFit.expand, children: [
          ClipRect(child: pic),
          ColoredBox(color: pal.bg.withValues(alpha: .35)),
          child,
        ]);
      },
    );
  }
}

/// Chọn hình nền (mở thành tab toàn màn hình): thanh "Blur" ở đầu, ảnh tự chọn, lưới 30 ảnh có sẵn.
class WallpaperPage extends StatefulWidget {
  const WallpaperPage({super.key});
  @override
  State<WallpaperPage> createState() => _WallpaperPageState();
}

class _WallpaperPageState extends State<WallpaperPage> {
  List<Map<String, dynamic>> _credits = const [];
  bool _loading = true;
  String? _busy;

  @override
  void initState() {
    super.initState();
    Wallpaper.load();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final c = await Wallpaper.credits();
    if (mounted) setState(() => (_credits = c, _loading = false));
  }

  Future<void> _pick(String name) async {
    if (_busy != null) return;
    setState(() => _busy = name);
    final ok = await Wallpaper.choose(name);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Không tải được ảnh từ máy chủ'))));
  }

  Future<void> _custom() async {
    final files = await pickFilesOrReport(context, type: FileType.image);
    final f = files.firstOrNull;
    if (f?.path == null) return;
    final dst = await Wallpaper.importFile(f!.path!);
    if (dst == null) return;
    await Wallpaper.set(WallpaperState(file: dst, blur: Wallpaper.state.value.blur));
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ValueListenableBuilder<WallpaperState>(
      valueListenable: Wallpaper.state,
      builder: (context, s, _) {
        final cur = s.file != null ? _credits.where((c) => c['file'] == s.asset).firstOrNull : null;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: WallpaperBackground(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Thanh trên: độ mờ, ảnh tự chọn, bỏ hình nền.
              Container(
                color: pal.surface.withValues(alpha: .92),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(tr('Hình nền'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.text)),
                  SizedBox(
                    width: 360,
                    child: Row(children: [
                      Icon(Icons.blur_on_rounded, color: pal.sub),
                      const SizedBox(width: 6),
                      Text('Blur', style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
                      Expanded(
                        child: Slider(
                          value: s.blur,
                          min: 0,
                          max: 30,
                          onChanged: s.isSet ? (v) => Wallpaper.state.value = WallpaperState(asset: s.asset, file: s.file, blur: v) : null,
                          onChangeEnd: (v) => Wallpaper.set(WallpaperState(asset: s.asset, file: s.file, blur: v)),
                        ),
                      ),
                      SizedBox(width: 28, child: Text('${s.blur.round()}', style: TextStyle(color: pal.sub))),
                    ]),
                  ),
                  FilledButton.icon(onPressed: _custom, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(tr('Chọn ảnh tùy chỉnh'))),
                  if (s.isSet)
                    OutlinedButton.icon(
                      onPressed: () => Wallpaper.set(WallpaperState(blur: s.blur)),
                      icon: const Icon(Icons.hide_image_outlined),
                      label: Text(tr('Bỏ hình nền')),
                    ),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final cols = (box.maxWidth / 280).floor().clamp(2, 6);
                  if (_credits.isEmpty) {
                    return Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(tr('Không tải được danh sách ảnh từ máy chủ'), style: TextStyle(color: pal.text)),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(onPressed: _fetch, icon: const Icon(Icons.refresh_rounded), label: Text(tr('Thử lại'))),
                            ]),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 16 / 11),
                    itemCount: _credits.length,
                    itemBuilder: (context, i) {
                      final c = _credits[i];
                      final file = c['file'] as String;
                      final name = c['name'] as String? ?? '';
                      final sel = s.asset == file && s.file != null;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _pick(file),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: sel ? pal.accent : Colors.transparent, width: 3),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 8, offset: const Offset(0, 3))],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Stack(fit: StackFit.expand, children: [
                                  Image.network(Wallpaper.url(c['thumb'] as String? ?? file),
                                      fit: BoxFit.cover,
                                      cacheWidth: 480,
                                      errorBuilder: (_, _, _) => ColoredBox(color: pal.surface, child: Icon(Icons.image_not_supported_outlined, color: pal.sub))),
                                  if (_busy == file) const Center(child: CircularProgressIndicator()),
                                  if (sel)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Icon(Icons.check_circle_rounded, color: pal.accent, size: 26, shadows: const [Shadow(blurRadius: 6)]),
                                    ),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text)),
                        ]),
                      );
                    },
                  );
                }),
              ),
              // Ghi nguồn ảnh đang dùng (giấy phép Creative Commons yêu cầu).
              if (cur != null)
                Container(
                  color: pal.surface.withValues(alpha: .92),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Text(tr('Ảnh: {0} — {1}, {2}, Wikimedia Commons', [cur['name'], cur['author'], cur['license']]),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.sub)),
                ),
            ]),
          ),
        );
      },
    );
  }
}
