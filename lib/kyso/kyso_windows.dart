// Cửa sổ Ký số riêng (máy tính): mỗi công ty (space Flygo ID) là một tiến trình app chạy với `--kyso=<space>`
// `--server=<máy chủ chat>`, hiện trình duyệt nhiều tab của space đó, tiêu đề là tên công ty. Theo cách của
// cửa sổ riêng tách từ màn chia ô (lib/ui/popout_windows.dart), trong cùng thư mục `<app support>/popouts/<máy chủ>/`:
// - `kyso_<space>.lock`: cửa sổ Ký số khoá suốt lúc chạy (đang mở thì không mở trùng);
// - `kyso_<space>.focus`: nhờ cửa sổ đang mở hiện lên trước (bấm lại ô của công ty đó);
// - `main.lock`: cửa sổ chính; nhả khoá (đã thoát) thì cửa sổ Ký số đóng theo.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:window_to_front/window_to_front.dart';

import '../browser/browser_page.dart';
import '../browser/flygo_id.dart';
import '../config.dart';
import '../data/servers.dart' show ServerList;
import '../state/app_state.dart';
import 'kyso_api.dart';

class KysoWindows {
  KysoWindows._();

  static const _ch = MethodChannel('flygo/window');

  static bool get supported => !kIsWeb && isDesktop;

  /// Khoá thư mục của cửa sổ chính, do cửa sổ chính truyền sang (`--kyso-key=`). Cửa sổ Ký số khởi động trước khi
  /// app đọc danh sách máy chủ, nên tự tính sẽ sai (vd máy chủ chính cũ dùng khoá "main"): tìm main.lock ở thư mục
  /// khác, tưởng cửa sổ chính đã thoát và tự đóng sau vài giây.
  static String? parentKey;

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final key = parentKey ?? (kServerUrl.isNotEmpty ? serverKey : serverKeyOf(ServerList.pinned ?? ''));
    final d = Directory('${base.path}${Platform.pathSeparator}popouts${Platform.pathSeparator}$key');
    await d.create(recursive: true);
    return d;
  }

  static String slug(String spaceId) => 'kyso_${spaceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
  static String _path(Directory d, String name) => '${d.path}${Platform.pathSeparator}$name';

  static Future<bool> _locked(Directory d, String name) async {
    final f = File(_path(d, name));
    if (!f.existsSync()) return false;
    RandomAccessFile? r;
    try {
      r = await f.open(mode: FileMode.append);
      await r.lock(FileLock.exclusive, 0, 1);
      await r.unlock(0, 1);
      return false;
    } catch (_) {
      return true;
    } finally {
      try {
        await r?.close();
      } catch (_) {}
    }
  }

  static Future<RandomAccessFile?> _hold(Directory d, String name) async {
    RandomAccessFile? r;
    try {
      r = await File(_path(d, name)).open(mode: FileMode.append);
      await r.lock(FileLock.exclusive, 0, 1);
      return r;
    } catch (_) {
      try {
        await r?.close();
      } catch (_) {}
      return null;
    }
  }

  /// Mở cửa sổ Ký số của [spaceId]; đang mở rồi thì đưa cửa sổ đó lên trước. false nếu không mở được.
  static Future<bool> open(String spaceId) async {
    if (!supported) return false;
    try {
      final d = await _dir();
      final s = slug(spaceId);
      if (await _locked(d, '$s.lock')) {
        File(_path(d, '$s.focus')).writeAsStringSync('$pid');
        return true;
      }
      await Process.start(
        Platform.resolvedExecutable,
        ['--kyso=$spaceId', '--kyso-key=$serverKey', if (kServerUrl.isNotEmpty) '--server=$kServerUrl'],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      debugPrint('[kyso window] $e');
      return false;
    }
  }

  /// Khoá của chính cửa sổ Ký số, giữ tới khi tiến trình thoát.
  static RandomAccessFile? _selfLock;

  /// Cửa sổ Ký số khởi động (trước runApp): giữ khoá (đã có cửa sổ của công ty này thì nhờ nó hiện lên rồi thoát),
  /// đặt cỡ cửa sổ, nghe yêu cầu đưa lên trước và đóng theo cửa sổ chính.
  static Future<void> startChild(String spaceId) async {
    if (!supported) return;
    final Directory d;
    try {
      d = await _dir();
    } catch (_) {
      return;
    }
    final s = slug(spaceId);
    _selfLock = await _hold(d, '$s.lock');
    if (_selfLock == null) {
      try {
        File(_path(d, '$s.focus')).writeAsStringSync('$pid');
      } catch (_) {}
      exit(0);
    }
    try {
      await _ch.invokeMethod('center', [1280.0, 880.0]);
    } catch (_) {}
    var ticks = 0;
    Timer.periodic(const Duration(seconds: 2), (_) async {
      ticks++;
      if (ticks >= 3 && !await _locked(d, 'main.lock')) exit(0);
      final focus = File(_path(d, '$s.focus'));
      if (focus.existsSync()) {
        try {
          focus.deleteSync();
        } catch (_) {}
        WindowToFront.activate();
      }
    });
  }

  /// Tiêu đề cửa sổ (tên công ty).
  static Future<void> setTitle(String title) async {
    try {
      await _ch.invokeMethod('setTitle', title);
    } catch (_) {}
  }
}

/// Nội dung cửa sổ Ký số riêng: tìm space [spaceId] trong Flygo ID, đổi vé lấy phiên, hiện trình duyệt nhiều tab.
class KysoSpaceWindowPage extends StatefulWidget {
  const KysoSpaceWindowPage({super.key, required this.spaceId});
  final String spaceId;

  @override
  State<KysoSpaceWindowPage> createState() => _KysoSpaceWindowPageState();
}

class _KysoSpaceWindowPageState extends State<KysoSpaceWindowPage> {
  Widget? _window;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AppState>().token;
    await KysoApi.refresh(token, force: true);
    final id = KysoApi.flygoId;
    final hit = KysoApi.spaces.where((s) => s.space.id == widget.spaceId).firstOrNull;
    if (id == null || hit == null) {
      if (mounted) setState(() => _error = 'Bạn chưa được dùng trình duyệt ký số này, hoặc máy chủ chưa có Flygo ID.');
      return;
    }
    await KysoWindows.setTitle(hit.space.name);
    final (window, error) = await buildFlygoSpace(id, hit, onEmpty: () => exit(0));
    if (!mounted) return;
    setState(() {
      _window = window;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = _window;
    if (w != null) return w;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null ? const CircularProgressIndicator() : Text(_error!, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Mở space Ký số: máy tính mở cửa sổ riêng (một cửa sổ mỗi công ty, bấm lại thì hiện cửa sổ đó); điện thoại đẩy
/// trang trình duyệt lên.
Future<void> openKysoSpace(BuildContext context, BrowserSpace s, {NavigatorState? navigator}) async {
  if (KysoWindows.supported && await KysoWindows.open(s.space.id)) return;
  if (!context.mounted) return;
  final id = KysoApi.flygoId;
  if (id == null) return;
  await openFlygoSpace(context, id, s, navigator: navigator);
}
