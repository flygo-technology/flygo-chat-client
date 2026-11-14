import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart' show AndroidWebViewWidgetCreationParams;

import '../api/mini_apps.dart';
import '../config.dart' show isDesktop;
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'bang_tin/bang_tin_page.dart' show kBangTinTab, openBangTin;
import 'flows/flows_page.dart' show openFlowsHome;
import 'todo/todo_page.dart' show openTodo;
import 'show_page.dart';
import 'theme.dart';
import 'desk_tabs.dart' show DeskTabScope;
import 'mini_app_windows.dart';
import 'package:flygo_chat/ui/app_route.dart';

/// Mở mini app [app] (tại [path] nếu có): xin URL mở app ngay lúc bấm rồi mở webview toàn màn hình;
/// Windows / Linux, và app có "open_in": "browser" trên điện thoại, mở bằng trình duyệt hệ thống.
Future<void> openMiniApp(BuildContext context, MiniApp app, {String? path}) async {
  final token = context.read<AppState>().token;
  final messenger = ScaffoldMessenger.of(context);
  // Trong một tab máy tính: mở ngay trong tab, tab mang tên app.
  final tab = DeskTabScope.of(context);
  final nav = tab != null ? Navigator.of(context) : Navigator.of(context, rootNavigator: true);
  // App có màn hình native trong Flygo (vd Trình chiếu): mở màn hình đó, tự xin phiên bằng launch token.
  if (app.nativeScreen == 'flows' && tab?.onLaunch != null) {
    tab!.onLaunch!('flows');
    return;
  }
  if (app.nativeScreen == 'flows') {
    await openFlowsHome(context, context.read<AppState>());
    return;
  }
    // Bảng tin trên máy tính: tab riêng (không mở trang có nút quay lại); mở thẳng một bài thì vẫn mở trang.
  if (app.nativeScreen == 'bang_tin' && path == null && tab?.onLaunch != null) {
    tab!.onLaunch!(kBangTinTab);
    return;
  }
  if (app.nativeScreen == 'bang_tin') {
    tab?.onTitle?.call(app.name);
    await openBangTin(context, app, postId: path == null ? null : RegExp(r'^/p/([A-Za-z0-9_-]{6,32})').firstMatch(path)?.group(1));
    return;
  }
  if (app.nativeScreen == 'todo') {
    tab?.onTitle?.call(app.name);
    await openTodo(context, app, noteId: path == null ? null : RegExp(r'^/n/([A-Za-z0-9_-]{6,40})').firstMatch(path)?.group(1));
    return;
  }
  if (app.nativeScreen == 'show') {
    final code = path == null ? null : RegExp(r'^/pair/([A-Za-z0-9]{8})').firstMatch(path)?.group(1)?.toUpperCase();
    tab?.onTitle?.call(app.name);
    await nav.push(AppPageRoute(builder: (_) => ShowHome(app: app, mmToken: token, pairCode: code)));
    return;
  }
  // App "window" trên máy tính (Sếp, 2026-11-14): mở cửa sổ riêng; app "tv_code" thì tab này hiện mã liên kết TV để
  // điều khiển / thêm bài từ điện thoại.
  if (app.feature('window') && MiniAppWindows.supported && await MiniAppWindows.open(app.id)) {
    if (app.feature('tv_code')) {
      tab?.onTitle?.call(app.name);
      await nav.push(AppPageRoute(builder: (_) => TvRemotePage(app: app)));
    }
    return;
  }
  // Máy tính (Sếp): luôn mở trong tab của app, không ra trình duyệt ngoài. "open_in": "browser" chỉ áp cho điện thoại.
  if (!MiniApps.inAppWebView || (app.openInBrowser && !isDesktop)) {
    try {
      await launchUrl(await MiniApps.launch(token, app, path: path), mode: LaunchMode.externalApplication);
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
    return;
  }
  // Mở trang ngay, xin URL mở app (vé, SSO) trong trang: trong lúc chờ hiện biểu tượng + "Đang mở ứng dụng …"
  // thay vì màn trắng (Sếp, 2026-11-10).
  tab?.onTitle?.call(app.name);
  await nav.push(AppPageRoute(builder: (_) => MiniAppPage(app: app, url: MiniApps.launch(token, app, path: path))));
}

/// Nội dung QR [raw] khớp scan_prefixes của một mini app: hỏi xác nhận rồi mở app đó. Trả về true nếu đã xử lý
/// (mở hoặc người dùng huỷ); false nếu không khớp app nào (xử lý như QR thường).
Future<bool> openScannedMiniApp(BuildContext context, String raw) async {
  final hit = await MiniApps.forScan(context.read<AppState>().token, raw);
  if (hit == null || !context.mounted) return false;
  final (app, path) = hit;
  final go = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: MiniAppIcon(app, size: 40),
      title: Text(tr('Mở {0}?', [app.name])),
      content: Text(Uri.parse(app.origin).host),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Mở'))),
      ],
    ),
  );
  if (go == true && context.mounted) await openMiniApp(context, app, path: path);
  return true;
}

/// Biểu tượng mini app: ảnh https hoặc emoji.
/// Biểu tượng theo tên trong manifest "tile.icon" (bộ nhỏ, thêm khi cần).
const _tileIcons = <String, IconData>{
  'table': Icons.table_chart_rounded,
  'tasks': Icons.task_alt_rounded,
  'network': Icons.hub_rounded,
  'code': Icons.terminal_rounded,
  'chart': Icons.bar_chart_rounded,
  'doc': Icons.description_rounded,
  'calendar': Icons.calendar_month_rounded,
  'cart': Icons.shopping_cart_rounded,
  'money': Icons.payments_rounded,
  'people': Icons.groups_rounded,
  'settings': Icons.settings_rounded,
  'slideshow': Icons.slideshow_rounded,
  'web': Icons.language_rounded,
  'news': Icons.campaign_rounded,
  'notes': Icons.sticky_note_2_rounded,
};

/// Màu ô của app (manifest "tile.color"), hoặc null nếu app không khai.
Color? miniAppTileColor(MiniApp a) {
  final c = '${a.tile?['color'] ?? ''}'.replaceFirst('#', '');
  final v = c.length == 6 ? int.tryParse(c, radix: 16) : null;
  return v == null ? null : Color(0xFF000000 | v);
}

class MiniAppIcon extends StatelessWidget {
  final MiniApp app;
  final double size;
  /// Bo góc ảnh (ảnh PNG của app phủ kín ô: đặt bằng bo góc của ô).
  final double? radius;
  const MiniAppIcon(this.app, {super.key, this.size = 30, this.radius});
  @override
  Widget build(BuildContext context) {
    final named = _tileIcons['${app.tile?['icon'] ?? ''}'];
    if (named != null && miniAppTileColor(app) != null) return Icon(named, size: size, color: Colors.white);
    final fallback = Icon(Icons.apps_rounded, size: size, color: Pal.of(context).accentText);
    if (app.iconIsUrl) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? size * .22),
        child: Image.network(app.icon, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      );
    }
    if (app.icon.isEmpty) return fallback;
    return SizedBox(width: size, height: size, child: Center(child: Text(app.icon, style: TextStyle(fontSize: size * .8, height: 1))));
  }
}

/// Mục "Ứng dụng" trong tab Apps: lưới mini app từ registry của máy chủ (ẩn khi máy chủ không có registry
/// hoặc không có app nào người dùng được dùng). Tải lại mỗi lần mở tab (dùng bản đã tải trong 10 phút).
class MiniAppsSection extends StatefulWidget {
  /// Vẽ một mục (tiêu đề + lưới) giống các mục khác trong tab Apps.
  final Widget Function(String title, List<Widget> tiles) section;
  /// Ô của một app (biểu tượng, tên, mờ khi cần cập nhật, bấm để mở).
  final Widget Function(Widget icon, Color? color, String label, bool dim, VoidCallback onTap) tile;
  /// Chỉ hiện các app này (vd Trình chiếu đưa lên mục "Chính"); null = mọi app.
  final Set<String>? only;
  /// Bỏ các app này (đã hiện ở mục khác).
  final Set<String> except;
  /// Vẫn gọi [section] khi không có app nào (mục ghép với các ô khác, như "Chính").
  final bool showEmpty;
  /// Các app đặt riêng ở đầu (vd Bảng tin ngay sau "Dự án AI"): có [split] thì gọi split(tiêu đề, ô đầu, ô còn lại) thay [section].
  final List<String> lead;
  final Widget Function(String title, List<Widget> lead, List<Widget> rest)? split;
  const MiniAppsSection(
      {super.key, required this.section, required this.tile, this.only, this.except = const {}, this.showEmpty = false,
      this.lead = const [], this.split});
  @override
  State<MiniAppsSection> createState() => _MiniAppsSectionState();
}

class _MiniAppsSectionState extends State<MiniAppsSection> with WidgetsBindingObserver {
  List<MiniApp> _apps = MiniApps.cached;
  Timer? _poll;

  void _onChanged() {
    if (mounted) setState(() => _apps = MiniApps.cached);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Quay lại app: hỏi lại ngay (quyền có thể vừa được cấp).
    if (s == AppLifecycleState.resumed && mounted) MiniApps.poll(context.read<AppState>().token);
  }

  @override
  void dispose() {
    _poll?.cancel();
    MiniApps.changed.removeListener(_onChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final token = context.read<AppState>().token;
    // Được cấp / thu hồi quyền thì ô app hiện / ẩn gần như ngay (Sếp, 2026-11-10): hỏi lại mỗi 20 giây khi đang mở
    // trang Ứng dụng, và mỗi khi quay lại app.
    MiniApps.changed.addListener(_onChanged);
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => MiniApps.poll(token));
    // Hiện ngay danh sách đã lưu, rồi tải mới; lỗi mạng thì thử lại một lần sau 5 giây.
    MiniApps.restore().then((_) {
      if (mounted && _apps.isEmpty) setState(() => _apps = MiniApps.cached);
    });
    MiniApps.list(token).then((a) {
      if (mounted) setState(() => _apps = a);
    }).catchError((_) {
      Future.delayed(const Duration(seconds: 5), () => MiniApps.list(token, refresh: true)).then((a) {
        if (mounted) setState(() => _apps = a);
      }).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final apps = [for (final a in _apps) if ((widget.only == null || widget.only!.contains(a.id)) && !widget.except.contains(a.id)) a];
    if (apps.isEmpty && !widget.showEmpty) return const SizedBox.shrink();
    Widget tileOf(MiniApp a) => widget.tile(
        a.iconIsUrl ? MiniAppIcon(a, size: 62, radius: 18) : miniAppTileColor(a) != null ? MiniAppIcon(a, size: 34) : MiniAppIcon(a),
        a.iconIsUrl ? null : miniAppTileColor(a),
        a.needsUpdate ? '${a.name}\n${tr('Cần cập nhật Flygo')}' : a.name, a.needsUpdate,
        a.needsUpdate ? () => ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Cần cập nhật Flygo')))) : () => openMiniApp(context, a));
    if (widget.split != null) {
      final lead = [for (final id in widget.lead) ...apps.where((a) => a.id == id)];
      return widget.split!(tr('Ứng dụng'), [for (final a in lead) tileOf(a)], [for (final a in apps) if (!lead.contains(a)) tileOf(a)]);
    }
    return widget.section(tr('Ứng dụng'), [for (final a in apps) tileOf(a)]);
  }
}

/// Webview của một mini app: chỉ điều hướng trong origin của app (link khác mở trình duyệt hệ thống), không mang
/// token / cookie của máy chủ chat. Cầu nối JS `FlygoApp` (scanQr, share, close, openExternal) chỉ trả lời trang của app.
class MiniAppPage extends StatefulWidget {
  final MiniApp app;
  /// URL mở app (đang xin vé): trang hiện màn "Đang mở ứng dụng" tới khi trang đầu tiên của app tải xong.
  final Future<Uri> url;
  /// Trang là nội dung của cửa sổ riêng (lib/ui/mini_app_windows.dart): không có thanh tiêu đề, đóng bằng cửa sổ.
  final bool inWindow;
  const MiniAppPage({super.key, required this.app, required this.url, this.inWindow = false});
  @override
  State<MiniAppPage> createState() => _MiniAppPageState();
}

class _MiniAppPageState extends State<MiniAppPage> {
  late final WebViewController _web;
  int _progress = 0;
  /// Trang đầu tiên của app (sau các bước vé / SSO) đã tải xong: bỏ màn chờ.
  bool _ready = false;
  String? _error;
  Timer? _readyFallback;

  MiniApp get _app => widget.app;
  Completer<String>? _tvCode;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlygoApp', onMessageReceived: (m) => _onBridge(m.message))
      ..addJavaScriptChannel('FlygoTvCode', onMessageReceived: (m) => _onTvCode(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageStarted: (_) => _keepVisible(),
        onPageFinished: (u) {
          _keepVisible();
          _maybeReady(u);
        },
        // App một trang (SPA) đổi đường dẫn bằng pushState: không có onPageFinished mới, nên nghe cả onUrlChange.
        onUrlChange: (c) => _maybeReady(c.url ?? ''),
        onNavigationRequest: (req) {
          final u = Uri.tryParse(req.url);
          if (u == null) return NavigationDecision.prevent;
          if (_app.owns(u) || u.scheme == 'about' || u.scheme == 'blob' || u.scheme == 'data') return NavigationDecision.navigate;
          // Web bên ngoài (plain): đăng nhập / chuyển trang ngay trong tab; cầu nối FlygoApp vẫn chỉ trả lời origin của app.
          if (_app.plain && (u.scheme == 'https' || u.scheme == 'http')) return NavigationDecision.navigate;
          // Ra ngoài origin của app: trình duyệt hệ thống, webview đứng yên.
          if (req.isMainFrame && (u.scheme == 'https' || u.scheme == 'http' || u.scheme == 'mailto' || u.scheme == 'tel')) {
            launchUrl(u, mode: LaunchMode.externalApplication);
          }
          return req.isMainFrame ? NavigationDecision.prevent : NavigationDecision.navigate;
        },
      ));
    if (_app.userAgent != null) _web.setUserAgent(_app.userAgent);
    if (widget.inWindow) MiniAppWindows.codeProvider = tvCode;
    _open(widget.url);
  }

  /// App "keep_visible": trang luôn thấy mình đang hiện. youtube.com/tv khi bị ẩn (đổi tab, cửa sổ khác lên trước)
  /// thì dừng và xoá giao diện, quay lại là bị "out" (Sếp, 2026-11-14).
  void _keepVisible() {
    if (_app.feature('keep_visible')) _web.runJavaScript(kKeepVisibleJs).catchError((_) {});
  }

  /// Mã liên kết TV của trang YouTube TV đang mở (app "tv_code"): 12 chữ số, nhập ở app YouTube trên điện thoại
  /// (Cài đặt → Xem trên TV → Liên kết bằng mã) để thêm bài vào hàng chờ.
  Future<String> tvCode() {
    final c = _tvCode ?? Completer<String>();
    if (_tvCode == null) {
      _tvCode = c;
      _web.runJavaScript(kTvCodeJs).catchError((Object e) => _onTvCode(jsonEncode({'error': '$e'})));
      Future.delayed(const Duration(seconds: 20), () => _onTvCode(jsonEncode({'error': 'timeout'})));
    }
    return c.future;
  }

  void _onTvCode(String raw) {
    final c = _tvCode;
    if (c == null || c.isCompleted) return;
    _tvCode = null;
    try {
      final m = jsonDecode(raw) as Map;
      final code = '${m['code'] ?? ''}';
      code.isEmpty ? c.completeError('${m['error'] ?? 'no code'}') : c.complete(code);
    } catch (e) {
      c.completeError('$e');
    }
  }

  Future<void> _showTvCode() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final code = await tvCode();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => TvCodeDialog(code: code));
    } catch (_) {
      messenger.showSnackBar(toast(Text(tr('Chưa lấy được mã TV. Chờ trang tải xong rồi thử lại.'))));
    }
  }

  /// Trang của app đã tải (không phải bước launch / SSO của Flygo ID / trang đăng nhập riêng): bỏ màn chờ.
  /// Trước đây chỉ coi là xong khi đường dẫn không chứa "sso"/"auth", nên app có bước SSO ẩn rồi chuyển trang kiểu
  /// SPA (LarkPanel) kẹt ở màn "Đang mở ứng dụng" (Sếp, 2026-11-11).
  void _maybeReady(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !_app.owns(u)) return;
    final p = u.path.toLowerCase();
    final hop = p.startsWith('/launch') || p.startsWith('/_flygo/enter') || p.contains('/auth/flygo/') || p.endsWith('/flygo-sso') || p.contains('/oidc/');
    if (!hop && mounted && !_ready) setState(() => _ready = true);
  }

  void _open(Future<Uri> url) {
    _readyFallback?.cancel();
    // Trang của app có thể dừng ở bước đăng nhập riêng: tối đa 8 giây thì hiện trang dù chưa "xong".
    _readyFallback = Timer(const Duration(seconds: 8), () {
      if (mounted && !_ready) setState(() => _ready = true);
    });
    url.then((u) => _web.loadRequest(u)).catchError((Object e) {
      _readyFallback?.cancel();
      if (mounted) setState(() => _error = '$e');
    });
  }

  void _retry() {
    setState(() {
      _error = null;
      _ready = false;
    });
    _open(MiniApps.launch(context.read<AppState>().token, _app));
  }

  @override
  void dispose() {
    _readyFallback?.cancel();
    if (MiniAppWindows.codeProvider == tvCode) MiniAppWindows.codeProvider = null;
    super.dispose();
  }

  /// "Tải lại": xin URL mở app mới (cookie phiên của app có thể đã hết hạn), giữ trang đang xem nếu được.
  Future<void> _reload() async {
    final cur = Uri.tryParse(await _web.currentUrl() ?? '');
    if (!mounted) return;
    final token = context.read<AppState>().token;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = cur != null && _app.owns(cur) && !cur.path.startsWith('/launch')
          ? '${cur.path}${cur.hasQuery ? '?${cur.query}' : ''}${cur.hasFragment ? '#${cur.fragment}' : ''}'
          : null;
      await _web.loadRequest(await MiniApps.launch(token, _app, path: path));
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  Future<void> _onBridge(String raw) async {
    Object? id;
    Future<void> reply(Object? result, [String? error]) =>
        _web.runJavaScript('window.__flygoReply && window.__flygoReply(${jsonEncode(id)}, ${jsonEncode(result)}, ${jsonEncode(error)})');
    try {
      final cur = Uri.tryParse(await _web.currentUrl() ?? '');
      if (cur == null || !_app.owns(cur)) return;
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      id = m['id'];
      final params = (m['params'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (!mounted) return;
      switch (m['method']) {
        case 'scanQr':
          // Máy tính không có máy quét: báo lỗi để app chuyển sang nhập mã.
          if (isDesktop) return await reply(null, 'unsupported');
          final code = await Navigator.of(context).push<String>(AppPageRoute(builder: (_) => const ScanOncePage()));
          return await (code == null ? reply(null, 'cancelled') : reply(code));
        case 'share':
          await SharePlus.instance.share(ShareParams(text: '${params['text'] ?? ''}'));
          return await reply(true);
        case 'close':
          await reply(true);
          if (mounted) Navigator.of(context).maybePop();
          return;
        case 'openExternal':
          final u = Uri.tryParse('${params['url'] ?? ''}');
          if (u == null || (u.scheme != 'https' && u.scheme != 'http')) return await reply(null, 'bad url');
          return await reply(await launchUrl(u, mode: LaunchMode.externalApplication));
        default:
          return await reply(null, 'unknown method');
      }
    } catch (e) {
      await reply(null, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Nút quay lại: lùi trong app trước, hết trang mới đóng.
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: pal.bg,
        // Trong tab máy tính (Sếp): không có thanh tiêu đề, đóng bằng tab; chỉ còn vạch tải trang.
        appBar: DeskTabScope.of(context) != null || widget.inWindow
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: _progress < 100 ? LinearProgressIndicator(value: _progress / 100, minHeight: 2) : const SizedBox(height: 2))
            : AppBar(
          leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: tr('Đóng'), onPressed: () => Navigator.of(context).pop()),
          titleSpacing: 0,
          title: Row(children: [
            MiniAppIcon(_app, size: 26),
            const SizedBox(width: 10),
            Flexible(child: Text(_app.name, overflow: TextOverflow.ellipsis)),
          ]),
          actions: [
            if (_app.feature('tv_code'))
              IconButton(icon: const Icon(Icons.connected_tv_rounded), tooltip: tr('Mã liên kết TV'), onPressed: _showTvCode),
            IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: tr('Tải lại'), onPressed: _reload),
          ],
          bottom: _progress < 100
              ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100, minHeight: 2))
              : null,
        ),
        // Android: hybrid composition (như trình duyệt Ký số). Mặc định webview_flutter vẽ qua texture (TLHC), trên
        // một số máy (S24 Ultra, Impeller) trang mini app chỉ hiện màn đen.
        body: Stack(children: [
          Positioned.fill(
            child: Platform.isAndroid
                ? WebViewWidget.fromPlatformCreationParams(
                    params: AndroidWebViewWidgetCreationParams(controller: _web.platform, displayWithHybridComposition: true),
                  )
                : WebViewWidget(controller: _web),
          ),
          if (!_ready || _error != null) Positioned.fill(child: _opening(pal)),
        ]),
      ),
    );
  }
}

extension on _MiniAppPageState {
  /// Màn chờ khi mở app (xin vé, SSO, trang đầu): biểu tượng app, vòng quay, "Đang mở ứng dụng …"; lỗi thì có Thử lại.
  Widget _opening(Pal pal) {
    final color = miniAppTileColor(_app);
    return ColoredBox(
      key: const ValueKey('mini-app-opening'),
      color: pal.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color ?? pal.surface,
                borderRadius: BorderRadius.circular(20),
                border: color == null ? Border.all(color: pal.divider) : null,
              ),
              child: Center(child: MiniAppIcon(_app, size: 40, radius: 20)),
            ),
            const SizedBox(height: 20),
            if (_error == null) ...[
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
              const SizedBox(height: 16),
              Text(tr('Đang mở ứng dụng {0}', [_app.name]), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: pal.text)),
            ] else ...[
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: pal.sub)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _retry, child: Text(tr('Thử lại'))),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Quét một mã QR cho mini app (cầu nối scanQr): trả về nội dung mã, hoặc null nếu đóng.
class ScanOncePage extends StatefulWidget {
  const ScanOncePage({super.key});
  @override
  State<ScanOncePage> createState() => _ScanOncePageState();
}

class _ScanOncePageState extends State<ScanOncePage> {
  final _ctl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(tr('Quét mã QR'))),
        body: MobileScanner(
          controller: _ctl,
          onDetect: (cap) {
            final raw = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (raw == null || _done) return;
            _done = true;
            Navigator.of(context).pop(raw);
          },
        ),
      );
}
