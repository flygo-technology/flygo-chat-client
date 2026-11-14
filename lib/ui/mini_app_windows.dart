// Cửa sổ riêng của mini app (máy tính, app có "features": {"window": true}): mỗi app là một tiến trình app chạy với
// `--miniapp=<id app>` `--miniapp-key=<khoá thư mục>` `--server=<máy chủ chat>`, chỉ có webview của app. Theo cách của
// cửa sổ Ký số (lib/kyso/kyso_windows.dart), trong cùng thư mục `<app support>/popouts/<máy chủ>/`:
// - `app_<id>.lock`: cửa sổ của app khoá suốt lúc chạy (đang mở thì không mở trùng);
// - `app_<id>.focus`: nhờ cửa sổ đang mở hiện lên trước (bấm lại ô app);
// - `app_<id>.coderq` / `app_<id>.code`: cửa sổ chính xin mã liên kết TV, cửa sổ app ghi mã (app "tv_code");
// - `main.lock`: cửa sổ chính; nhả khoá (đã thoát) thì cửa sổ app đóng theo.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:window_to_front/window_to_front.dart';

import '../api/mini_apps.dart';
import '../config.dart';
import '../data/servers.dart' show ServerList;
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'mini_app_view.dart';
import 'theme.dart';

class MiniAppWindows {
  MiniAppWindows._();

  static const _ch = MethodChannel('flygo/window');

  /// Chỉ máy tính có webview trong app (macOS); Windows / Linux mở mini app bằng trình duyệt hệ thống.
  static bool get supported => !kIsWeb && isDesktop && MiniApps.inAppWebView;

  /// Khoá thư mục của cửa sổ chính, do cửa sổ chính truyền sang (`--miniapp-key=`), như cửa sổ Ký số.
  static String? parentKey;

  /// Cửa sổ app: lấy mã liên kết TV từ trang đang mở (MiniAppPage đặt khi chạy trong cửa sổ riêng).
  static Future<String> Function()? codeProvider;

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final key = parentKey ?? (kServerUrl.isNotEmpty ? serverKey : serverKeyOf(ServerList.pinned ?? ''));
    final d = Directory('${base.path}${Platform.pathSeparator}popouts${Platform.pathSeparator}$key');
    await d.create(recursive: true);
    return d;
  }

  static String slug(String appId) => 'app_${appId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';
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

  /// Mở cửa sổ của app [appId]; đang mở rồi thì đưa cửa sổ đó lên trước. false nếu không mở được.
  static Future<bool> open(String appId) async {
    if (!supported) return false;
    try {
      final d = await _dir();
      final s = slug(appId);
      if (await _locked(d, '$s.lock')) {
        File(_path(d, '$s.focus')).writeAsStringSync('$pid');
        return true;
      }
      await Process.start(
        Platform.resolvedExecutable,
        ['--miniapp=$appId', '--miniapp-key=$serverKey', if (kServerUrl.isNotEmpty) '--server=$kServerUrl'],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e) {
      debugPrint('[miniapp window] $e');
      return false;
    }
  }

  /// Cửa sổ của app [appId] còn mở không.
  static Future<bool> isOpen(String appId) async {
    try {
      return await _locked(await _dir(), '${slug(appId)}.lock');
    } catch (_) {
      return false;
    }
  }

  /// Cửa sổ chính xin mã liên kết TV mới; cửa sổ app ghi vào `.code` (đọc bằng [readCode]).
  static Future<void> requestCode(String appId) async {
    try {
      File(_path(await _dir(), '${slug(appId)}.coderq')).writeAsStringSync('$pid');
    } catch (_) {}
  }

  /// Mã liên kết TV cửa sổ app ghi gần nhất: {code | error, at (ms)}; chưa có thì null.
  static Future<Map<String, dynamic>?> readCode(String appId) async {
    try {
      final f = File(_path(await _dir(), '${slug(appId)}.code'));
      if (!f.existsSync()) return null;
      return (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  static RandomAccessFile? _selfLock;

  /// Cửa sổ app khởi động (trước runApp): giữ khoá (đã có cửa sổ của app này thì nhờ nó hiện lên rồi thoát), đặt cỡ
  /// cửa sổ, nghe yêu cầu đưa lên trước / xin mã TV, và đóng theo cửa sổ chính.
  static Future<void> startChild(String appId) async {
    if (!supported) return;
    final Directory d;
    try {
      d = await _dir();
    } catch (_) {
      return;
    }
    final s = slug(appId);
    _selfLock = await _hold(d, '$s.lock');
    if (_selfLock == null) {
      try {
        File(_path(d, '$s.focus')).writeAsStringSync('$pid');
      } catch (_) {}
      exit(0);
    }
    try {
      await _ch.invokeMethod('center', [1280.0, 760.0]);
    } catch (_) {}
    var ticks = 0;
    var busy = false;
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
      final rq = File(_path(d, '$s.coderq'));
      final get = codeProvider;
      if (busy || get == null || !rq.existsSync()) return;
      busy = true;
      try {
        rq.deleteSync();
      } catch (_) {}
      Map<String, Object?> out;
      try {
        out = {'code': await get()};
      } catch (e) {
        out = {'error': '$e'};
      }
      busy = false;
      try {
        final f = File(_path(d, '$s.code'));
        final tmp = File('${f.path}.$pid.tmp');
        tmp.writeAsStringSync(jsonEncode({...out, 'at': DateTime.now().millisecondsSinceEpoch}), flush: true);
        tmp.renameSync(f.path);
      } catch (_) {}
    });
  }

  static Future<void> setTitle(String title) async {
    try {
      await _ch.invokeMethod('setTitle', title);
    } catch (_) {}
  }
}

/// Nội dung cửa sổ app riêng: tìm app [appId] trong danh sách mini app rồi mở webview của app, không thanh tiêu đề.
class MiniAppWindowPage extends StatefulWidget {
  const MiniAppWindowPage({super.key, required this.appId});
  final String appId;

  @override
  State<MiniAppWindowPage> createState() => _MiniAppWindowPageState();
}

class _MiniAppWindowPageState extends State<MiniAppWindowPage> {
  MiniApp? _app;
  Future<Uri>? _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AppState>().token;
    try {
      final app = (await MiniApps.list(token)).where((a) => a.id == widget.appId).firstOrNull;
      if (!mounted) return;
      if (app == null) return setState(() => _error = tr('Bạn chưa được dùng ứng dụng này.'));
      await MiniAppWindows.setTitle(app.name);
      setState(() {
        _app = app;
        _url = MiniApps.launch(token, app);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app, url = _url;
    if (app != null && url != null) return MiniAppPage(app: app, url: url, inWindow: true);
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

/// "110621207476" → "110 621 207 476" (như YouTube hiện trên TV).
String formatTvCode(String code) => code.replaceAllMapped(RegExp(r'(\d{3})(?=\d)'), (m) => '${m[1]} ');

/// Mã liên kết TV và cách dùng: điện thoại mở app YouTube, Cài đặt → Xem trên TV → Liên kết bằng mã.
class _TvCodeView extends StatelessWidget {
  const _TvCodeView({required this.code});
  final String? code;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(tr('Mã liên kết TV'), style: TextStyle(fontSize: 15, color: pal.sub)),
      const SizedBox(height: 10),
      code == null
          ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6))
          : SelectableText(formatTvCode(code!),
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: 2, color: pal.text)),
      const SizedBox(height: 16),
      Text(
        tr('Trên điện thoại: mở app YouTube → ảnh đại diện → Cài đặt → Xem trên TV → Liên kết bằng mã, rồi nhập mã này. '
            'Sau đó mọi người thêm bài vào hàng chờ, phát / dừng từ điện thoại.'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, height: 1.4, color: pal.sub),
      ),
    ]);
  }
}

class TvCodeDialog extends StatelessWidget {
  const TvCodeDialog({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => AlertDialog(
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: _TvCodeView(code: code)),
        actions: [
          TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)), child: Text(tr('Sao chép'))),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng'))),
        ],
      );
}

/// Tab của app TV ở cửa sổ chính khi app đang chạy trong cửa sổ riêng: hiện mã liên kết TV (tự lấy mã mới mỗi
/// 4 phút), nút hiện cửa sổ TV và lấy mã mới.
class TvRemotePage extends StatefulWidget {
  const TvRemotePage({super.key, required this.app});
  final MiniApp app;

  @override
  State<TvRemotePage> createState() => _TvRemotePageState();
}

class _TvRemotePageState extends State<TvRemotePage> {
  static const _refresh = Duration(minutes: 4);
  Timer? _poll;
  String? _code, _error;
  int _at = 0;
  DateTime _asked = DateTime(2000);
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _ask();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _ask() {
    _asked = DateTime.now();
    MiniAppWindows.requestCode(widget.app.id);
  }

  Future<void> _tick() async {
    final open = await MiniAppWindows.isOpen(widget.app.id);
    final c = await MiniAppWindows.readCode(widget.app.id);
    if (!mounted) return;
    final at = (c?['at'] as num?)?.toInt() ?? 0;
    setState(() {
      _open = open;
      // Chỉ nhận mã ghi sau lần xin gần nhất (mã cũ trong tệp có thể đã hết hạn).
      if (at > _at && at >= _asked.millisecondsSinceEpoch - 1000) {
        _at = at;
        _code = c?['code'] as String?;
        _error = _code == null ? '${c?['error'] ?? ''}' : null;
      }
    });
    // Trang TV mới mở chưa có màn hình ghép đôi: chưa có mã thì hỏi lại mỗi 6 giây; có mã thì làm mới mỗi 4 phút.
    final age = DateTime.now().difference(_asked);
    if (open && ((_code == null && age.inSeconds >= 6) || age >= _refresh)) _ask();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              MiniAppIcon(widget.app, size: 56, radius: 16),
              const SizedBox(height: 12),
              Text(widget.app.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.text)),
              const SizedBox(height: 6),
              Text(_open ? tr('Đang phát ở cửa sổ riêng.') : tr('Cửa sổ TV đã đóng.'), style: TextStyle(color: pal.sub)),
              const SizedBox(height: 28),
              if (_open) _TvCodeView(code: _code),
              if (_open && _error != null && _code == null) ...[
                const SizedBox(height: 8),
                Text(tr('Chưa lấy được mã, đang thử lại…'), style: TextStyle(fontSize: 13, color: pal.sub)),
              ],
              const SizedBox(height: 28),
              Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
                FilledButton.icon(
                  onPressed: () async {
                    await MiniAppWindows.open(widget.app.id);
                    if (!_open) Future.delayed(const Duration(seconds: 4), _ask);
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(_open ? tr('Hiện cửa sổ TV') : tr('Mở lại cửa sổ TV')),
                ),
                if (_open)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _code = null;
                      _ask();
                    }),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(tr('Lấy mã mới')),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Trang luôn coi là đang hiện (app "keep_visible"): document.hidden / visibilityState cố định, chặn các sự kiện ẩn
/// trang trước khi tới trang (bắt ở pha capture của window).
const kKeepVisibleJs = r'''
(() => {
  if (window.__flygoKeepVisible) return;
  window.__flygoKeepVisible = true;
  const d = Document.prototype;
  for (const [k, v] of [['hidden', false], ['webkitHidden', false], ['visibilityState', 'visible'], ['webkitVisibilityState', 'visible']]) {
    try { Object.defineProperty(d, k, { configurable: true, get: () => v }); } catch (_) {}
  }
  try { d.hasFocus = () => true; } catch (_) {}
  const stop = (e) => e.stopImmediatePropagation();
  for (const t of ['visibilitychange', 'webkitvisibilitychange', 'pagehide', 'freeze']) {
    window.addEventListener(t, stop, true);
    document.addEventListener(t, stop, true);
  }
  window.addEventListener('blur', (e) => { if (e.target === window) stop(e); }, true);
})();
''';

/// Xin mã liên kết TV bằng chính màn hình ghép đôi của trang YouTube TV (screenId + loungeToken trang lưu trong
/// localStorage), như khi mở Cài đặt → Liên kết với điện thoại trên TV. Trả về qua kênh FlygoTvCode.
const kTvCodeJs = r'''
(async () => {
  try {
    const raw = localStorage.getItem('yt.leanback.default::yt_mdx_screen');
    const s = raw && JSON.parse(raw).data;
    if (!s || !s.screenId || !s.loungeToken) throw new Error('not ready');
    let dev = localStorage.getItem('flygo.tv.device');
    if (!dev) { dev = crypto.randomUUID(); localStorage.setItem('flygo.tv.device', dev); }
    const body = new URLSearchParams({ access_type: 'permanent', app: 'lb-v4', lounge_token: s.loungeToken,
      screen_id: s.screenId, screen_name: s.name || 'YouTube on TV', device_id: dev });
    const r = await fetch('/api/lounge/pairing/get_pairing_code?ctx=pair', { method: 'POST', body });
    const t = (await r.text()).trim();
    if (!r.ok || !/^\d{6,16}$/.test(t)) throw new Error('HTTP ' + r.status);
    FlygoTvCode.postMessage(JSON.stringify({ code: t }));
  } catch (e) {
    FlygoTvCode.postMessage(JSON.stringify({ error: String((e && e.message) || e) }));
  }
})();
''';
