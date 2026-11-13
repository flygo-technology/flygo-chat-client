// Giao diện app Browser (bản đầu, cho extension Ký số):
// - Trang đầu: đăng nhập máy chủ ký số một lần, rồi mỗi space một ô. Space của Ký số do extension tự khai (mỗi token
//   được cấp một space "Ký số <công ty theo chứng thư>"); whitelist bị cắt về space_origins của extension.
//   Khi có Flygo ID, danh sách space lấy từ Flygo ID (miniapp-sso-design.md §9).
// - Cửa sổ của một space: nhiều tab, thanh địa chỉ, chặn trang ngoài whitelist, trang đầu là bookmark,
//   hộp xác nhận ký đè lên website.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' hide Favicon;
import 'package:path_provider/path_provider.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../config.dart' show isDesktop;
import '../ui/app_route.dart';
import 'browser_dock.dart';
import 'chrome_ui.dart';
import 'flygo_id.dart';
import 'model.dart';
import 'runtime.dart';

/// Tên ô của một token: "Ký số " + tên công ty đầy đủ theo chứng thư (Sếp chọn, 2026-11-08).
String kysoTileName(Map<String, dynamic> token) {
  final company = '${token['companyName'] ?? token['label'] ?? token['tokenId'] ?? ''}'.trim();
  return 'Ký số $company';
}

const _kSelfTest = bool.fromEnvironment('KYSO_SELFTEST');

String kysoTokenId(Map<String, dynamic> token) => '${token['tokenId'] ?? token['id'] ?? ''}';

/// Trình duyệt Ký số mở được mọi trang http/https (không còn giới hạn theo danh sách trang của công ty).
bool kysoCanOpen(String url) {
  final u = Uri.tryParse(url);
  return u != null && (u.isScheme('http') || u.isScheme('https')) && u.host.isNotEmpty;
}

/// Nội dung ô địa chỉ → địa chỉ mở: có scheme thì giữ; giống tên miền (có dấu chấm, không dấu cách) thì thêm https://;
/// còn lại tìm bằng Google (Sếp, 2026-11-09).
String kysoAddressToUrl(String raw) {
  final text = raw.trim();
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) return text;
  final looksLikeHost = !text.contains(' ') && RegExp(r'^[^\s/]+\.[a-zA-Z]{2,}(:\d+)?([/?#].*)?$').hasMatch(text);
  if (looksLikeHost || RegExp(r'^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?([/?#].*)?$').hasMatch(text)) return 'https://$text';
  return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(text)}';
}

/// Space của một token (space do extension Ký số tự khai), đã cắt về space_origins.
Space kysoSpace(KysoHost host, Map<String, dynamic> token) {
  final id = kysoTokenId(token);
  final pins = (token['pins'] as List? ?? const []).whereType<Map>().toList();
  final patterns = <String>{
    for (final p in pins)
      if (Uri.tryParse('${p['url']}') case final u? when u.host.isNotEmpty) '${u.scheme}://${u.host}/*',
    for (final o in (token['origins'] as List? ?? const []))
      if ('$o' != '*' && '$o'.startsWith('http')) '${'$o'.replaceAll(RegExp(r'/+$'), '')}/*',
    '${host.server}/*',
  };
  final raw = Space.fromJson({
    'id': '${host.manifest.id}/$id',
    'name': kysoTileName(token),
    'whitelist': {for (final (i, p) in patterns.indexed) 'p$i': {'pattern': p}},
    'env': {'SERVER': host.server, 'TOKEN': id, if (token['taxCode'] != null) 'MST': '${token['taxCode']}'},
    'extensions': {host.manifest.id: {}},
    'bookmarks': {for (final (i, p) in pins.indexed) 'b$i': {'title': '${p['title'] ?? p['url']}', 'url': '${p['url']}'}},
    'provider': host.manifest.id,
  });
  final (space, dropped) = clampToProvider(raw, host.manifest);
  if (dropped.isNotEmpty) debugPrint('[browser] ${space.id}: bỏ mẫu ngoài space_origins: $dropped');
  return space;
}

/// Trang đầu: đăng nhập máy chủ ký số (một lần), rồi mỗi token một ô.
class KysoHomePage extends StatefulWidget {
  const KysoHomePage({super.key});

  @override
  State<KysoHomePage> createState() => _KysoHomePageState();
}

class _KysoHomePageState extends State<KysoHomePage> {
  final host = KysoHost.instance;
  bool _busy = false;
  String? _error;

  /// Flygo ID của máy chủ chat (null: không có, dùng cách đăng nhập Google cũ) và các space Ký số của người này.
  FlygoId? _id;
  List<BrowserSpace>? _spaces;
  String? _spacesError;

  @override
  void initState() {
    super.initState();
    host.desktopAuth ??= (url) => _desktopLogin(context, url);
    _loadSpaces();
  }

  Future<void> _loadSpaces() async {
    String? chatToken;
    try {
      chatToken = context.read<AppState>().token;
    } catch (_) {}
    FlygoId? id;
    try {
      id = chatToken == null || chatToken.isEmpty ? null : await FlygoId.current(chatToken);
    } catch (_) {}
    List<BrowserSpace>? spaces;
    String? error;
    if (id != null) {
      try {
        spaces = (await id.spaces()).where((s) => s.extensionEnv.containsKey(kKysoExtensionId) || s.space.provider == kKysoExtensionId).toList();
      } on FlygoIdException catch (e) {
        error = e.message;
      } catch (e) {
        error = '$e';
      }
    }
    // Không có Flygo ID (hoặc không có space nào): dùng engine chung, đăng nhập Google như trước.
    if (id == null || (spaces ?? const []).isEmpty) await host.ensureStarted();
    if (!mounted) return;
    setState(() {
      _id = id;
      _spaces = spaces;
      _spacesError = error;
    });
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await host.login(host.server);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kysoSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ký số')),
        body: const Center(child: Text('Máy này chưa chạy được trình duyệt ký số trong Flygo.')),
      );
    }
    final spaces = _spaces;
    if (_id != null && spaces != null && spaces.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ký số')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final s in spaces)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: s.space.color != null ? Color(0xFF000000 | s.space.color!) : companyColor(s.space.name),
                    child: const Icon(Icons.draw_rounded, color: Colors.white),
                  ),
                  title: Text(s.space.name),
                  subtitle: Text([
                    if (s.subtitle != null) s.subtitle!,
                    if (s.space.env['MST'] != null) 'MST ${s.space.env['MST']}',
                  ].join(' · ')),
                  onTap: () => openFlygoSpace(context, _id!, s),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Ký số')),
      body: ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: host.status,
        builder: (context, status, _) => ValueListenableBuilder<int>(
          valueListenable: host.storeVersion,
          builder: (context, _, _) {
            final loggedIn = host.stored('token') is String && '${host.stored('token')}'.isNotEmpty;
            final tokens = host.tokens;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_spacesError != null)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Flygo ID: $_spacesError', style: const TextStyle(color: Colors.orange))),
                _StatusLine(status: status),
                const SizedBox(height: 12),
                if (!loggedIn) ...[
                  Text('Máy chủ ký số: ${host.server}'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _login,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(_busy ? 'Đang đăng nhập…' : 'Đăng nhập bằng Google'),
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                ] else ...[
                  if (tokens.isEmpty) const Text('Chưa có token nào được cấp cho tài khoản này.'),
                  for (final token in tokens)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: companyColor(kysoTileName(token)), child: const Icon(Icons.draw_rounded, color: Colors.white)),
                        title: Text(kysoTileName(token)),
                        subtitle: Text([
                          if (token['taxCode'] != null) 'MST ${token['taxCode']}',
                          if (token['certificateValid'] == false) 'Chứng thư hết hạn',
                          '${(token['pins'] as List? ?? const []).length} trang đánh dấu',
                        ].join(' · ')),
                        onTap: () => openKysoBrowser(context, token),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextButton.icon(onPressed: host.logout, icon: const Icon(Icons.logout_rounded), label: const Text('Đăng xuất máy chủ ký số')),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    final state = '${status['state'] ?? 'đang khởi động'}';
    final user = status['user'] is Map ? (status['user'] as Map)['displayName'] ?? (status['user'] as Map)['username'] : null;
    final ok = state == 'connected';
    return Row(children: [
      Icon(ok ? Icons.check_circle_rounded : Icons.hourglass_top_rounded, color: ok ? Colors.green : Colors.orange, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(ok ? 'Đã kết nối${user != null ? ' · $user' : ''}' : 'Trạng thái: $state${status['error'] != null ? ' · ${status['error']}' : ''}')),
    ]);
  }
}

/// Màu riêng mỗi công ty (băm theo tên, như trình duyệt Electron).
Color companyColor(String name) {
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.55, 0.45).toColor();
}

/// Mở cửa sổ space của [token] (tại [url] nếu có; không có thì trang đầu là bookmark công ty).
Future<void> openKysoBrowser(BuildContext context, Map<String, dynamic> token, {String? url, NavigatorState? navigator}) async {
  final host = KysoHost.instance;
  // Script cho website và engine phải sẵn sàng trước khi trang đầu tiên mở.
  await host.ensureStarted();
  final space = kysoSpace(host, token);
  final profile = await host.profileFor(kysoTokenId(token));
  final env = await host.environmentFor(kysoTokenId(token));
  final nav = navigator ?? (context.mounted ? Navigator.of(context) : null);
  await nav?.push(AppPageRoute(
    builder: (_) => SpaceWindow(host: host, space: space, lockTokenId: kysoTokenId(token), profile: profile, environment: env, initialUrl: url),
  ));
}

/// Mở space Ký số lấy từ Flygo ID (đẩy trang lên navigator): xem [buildFlygoSpace].
Future<void> openFlygoSpace(BuildContext context, FlygoId id, BrowserSpace bs, {String? url, NavigatorState? navigator}) async {
  final messenger = ScaffoldMessenger.of(context);
  final nav = navigator ?? Navigator.of(context);
  final dock = BrowserDock.instance;
  final color = bs.space.color != null ? Color(0xFF000000 | bs.space.color!) : companyColor(bs.space.name);
  // Điện thoại: trình duyệt chạy song song (lớp nổi), đang mở thì hiện lại nguyên trạng, kèm tab mới nếu có [url].
  if (!isDesktop && dock.isOpen(bs.space.id)) {
    dock.show(bs.space.id, name: bs.space.name, color: color, build: () => const SizedBox.shrink());
    if (url != null) SpaceWindow.openIn(bs.space.id, url);
    return;
  }
  final (window, error) = await buildFlygoSpace(
    id,
    bs,
    url: url,
    onMinimize: isDesktop ? null : dock.minimize,
    onCloseBrowser: isDesktop ? null : () => dock.close(bs.space.id),
  );
  if (window != null && !isDesktop) {
    dock.show(bs.space.id, name: bs.space.name, color: color, build: () => window);
    return;
  }
  if (window == null) {
    messenger.showSnackBar(SnackBar(content: Text('Không mở được ${bs.space.name}: $error')));
    return;
  }
  await nav.push(AppPageRoute(builder: (_) => window));
}

/// Dựng cửa sổ của một space Ký số: phiên máy chủ ký số đổi từ vé Flygo ID của space (không đăng nhập Google),
/// bookmark lấy từ catalog (trang đánh dấu của token, trong whitelist của space). Lỗi: (null, lý do).
Future<(SpaceWindow?, String?)> buildFlygoSpace(
  FlygoId id,
  BrowserSpace bs, {
  String? url,
  VoidCallback? onEmpty,
  VoidCallback? onMinimize,
  VoidCallback? onCloseBrowser,
}) async {
  final server = bs.space.env['SERVER'] ?? kKysoDefaultServer;
  final host = KysoHost.forServer(server, space: bs.space.id);
  await host.ensureStarted();
  if (!host.loggedIn) {
    final error = await host.loginFlygo(() => id.ticket(host.manifest.id, browser: bs.space.id));
    if (error != null) return (null, error);
    // Catalog (token của phiên, trang đánh dấu) tới sau khi kết nối.
    for (var i = 0; i < 20 && host.tokens.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
  final token = bs.space.env['TOKEN'];
  final pins = [
    for (final t in host.tokens)
      if (token == null || kysoTokenId(t) == token)
        for (final p in (t['pins'] as List? ?? const []))
          if (p is Map && bs.space.allows('${p['url']}')) (title: '${p['title'] ?? p['url']}', url: '${p['url']}'),
  ];
  final space = Space(
    id: bs.space.id,
    name: bs.space.name,
    color: bs.space.color,
    whitelist: bs.space.whitelist,
    env: bs.space.env,
    extensions: bs.space.extensions,
    bookmarks: [...bs.space.bookmarks, ...pins],
    provider: bs.space.provider,
  );
  final profile = await host.profileFor(bs.space.id);
  final env = await host.environmentFor(bs.space.id);
  return (
    SpaceWindow(
      host: host,
      space: space,
      lockTokenId: token ?? (host.tokens.length == 1 ? kysoTokenId(host.tokens.first) : null),
      profile: profile,
      environment: env,
      initialUrl: url,
      flygoId: id,
      onEmpty: onEmpty,
      onMinimize: onMinimize,
      onCloseBrowser: onCloseBrowser,
    ),
    null,
  );
}

/// Settings có thêm `msProfile` cho WebView đã vá (Android: WebViewCompat.setProfile, iOS 17+: data store riêng).
class _ProfileSettings extends InAppWebViewSettings {
  _ProfileSettings(this.profile)
      : super(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: true,
          supportMultipleWindows: true,
          mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          builtInZoomControls: true,
          displayZoomControls: false,
          // Cổng thuế, hoá đơn chạy tốt nhất ở bản máy tính.
          userAgent: Platform.isAndroid
              ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
              : '',
          preferredContentMode: UserPreferredContentMode.DESKTOP,
          allowsBackForwardNavigationGestures: true,
          // iOS: nhấn giữ link mở menu của app (tab mới), không mở bản xem trước của Safari.
          allowsLinkPreview: false,
          isInspectable: true,
          thirdPartyCookiesEnabled: true,
          sharedCookiesEnabled: false,
        );

  final String profile;

  @override
  Map<String, dynamic> toMap() => {...super.toMap(), 'msProfile': profile};
}

/// Một tab trong cửa sổ space.
class _TabModel {
  _TabModel(this.state, {this.initialUrl, this.windowId});
  final KysoTab state;
  final String? initialUrl;
  final int? windowId;
  final key = GlobalKey<_TabViewState>();
  String title = 'Tab mới';
  String url = '';
  bool home = true;
  bool loading = false;
  bool canBack = false;
  bool canForward = false;

  /// Ảnh thu nhỏ của trang (lưới tab trên điện thoại).
  Uint8List? thumb;
}

/// Cửa sổ của một space: nhiều tab (máy tính: dải tab; điện thoại: nút danh sách tab), thanh địa chỉ.
class SpaceWindow extends StatefulWidget {
  const SpaceWindow({
    super.key,
    required this.host,
    required this.space,
    required this.profile,
    this.lockTokenId,
    this.environment,
    this.initialUrl,
    this.flygoId,
    this.onEmpty,
    this.onMinimize,
    this.onCloseBrowser,
  });
  final KysoHost host;

  /// Điện thoại, trình duyệt chạy song song: thu nhỏ (giữ các tab) và đóng hẳn.
  final VoidCallback? onMinimize;
  final VoidCallback? onCloseBrowser;

  /// Trình duyệt đang mở của từng space (để mở thêm tab từ ngoài, vd nút ký của Quy trình).
  static final _open = <String, _SpaceWindowState>{};

  /// Mở [url] ở tab mới của trình duyệt space [spaceId] đang chạy.
  static void openIn(String spaceId, String url) => _open[spaceId]?._newTab(url: url);

  /// Đóng tab cuối cùng: cửa sổ Ký số riêng thì đóng cửa sổ; trang trong app thì quay lại.
  final VoidCallback? onEmpty;

  /// Flygo ID (kho tài khoản dùng chung của space); null với space kiểu cũ.
  final FlygoId? flygoId;
  final Space space;
  final String profile;
  final String? lockTokenId;
  final WebViewEnvironment? environment;
  final String? initialUrl;

  @override
  State<SpaceWindow> createState() => _SpaceWindowState();
}

class _SpaceWindowState extends State<SpaceWindow> {
  final _tabs = <_TabModel>[];
  int _active = 0;
  final _address = TextEditingController();
  final _addressFocus = FocusNode();

  KysoHost get host => widget.host;
  _TabModel get _tab => _tabs[_active];

  @override
  void initState() {
    super.initState();
    SpaceWindow._open[widget.space.id] = this;
    _newTab(url: widget.initialUrl);
    host.openUrl = (url) {
      if (!mounted) return null;
      _newTab(url: url);
      return _tab.state.id;
    };
  }

  @override
  void dispose() {
    for (final t in _tabs) {
      host.tabClosed(t.state);
    }
    host.openUrl = null;
    if (SpaceWindow._open[widget.space.id] == this) SpaceWindow._open.remove(widget.space.id);
    _addressFocus.dispose();
    super.dispose();
  }

  void _newTab({String? url, int? windowId}) {
    if (url != null && !kysoCanOpen(url)) {
      _blocked(url);
      return;
    }
    if (_tabs.isNotEmpty) unawaited(_snap(_tab));
    final t = _TabModel(host.newTab(lockTokenId: widget.lockTokenId), initialUrl: url, windowId: windowId)
      ..home = url == null && windowId == null;
    setState(() {
      _tabs.add(t);
      _active = _tabs.length - 1;
      _address.text = url ?? '';
    });
    host.activeTab = t.state.id;
    _reportTabs();
    // Tab trống: con trỏ vào ô địa chỉ luôn.
    if (url == null && windowId == null) WidgetsBinding.instance.addPostFrameCallback((_) => _addressFocus.requestFocus());
  }

  void _closeTab(int i) {
    final t = _tabs[i];
    host.tabClosed(t.state);
    setState(() {
      _tabs.removeAt(i);
      if (_tabs.isEmpty) {
        // Đóng tab cuối: cửa sổ Ký số riêng thì đóng luôn cửa sổ (Sếp chốt); trang trong app (điện thoại) thì quay lại;
        // không có cách đóng nào thì mở tab trống.
        if (widget.onEmpty != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onEmpty!());
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).maybePop();
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _newTab());
        return;
      }
      _active = _active.clamp(0, _tabs.length - 1);
      _address.text = _tab.url;
    });
    if (_tabs.isNotEmpty) host.activeTab = _tab.state.id;
    _reportTabs();
  }

  /// Số tab cho nút nổi "Ký số · N tab" khi thu nhỏ.
  void _reportTabs() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) BrowserDock.instance.setTabs(widget.space.id, _tabs.length);
      });

  void _select(int i) {
    if (i != _active && _tabs.isNotEmpty) unawaited(_snap(_tab));
    setState(() {
      _active = i;
      _address.text = _tab.url;
    });
    host.activeTab = _tab.state.id;
  }

  void _blocked(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$host không nằm trong danh sách trang được phép của ${widget.space.name}.')));
  }

  void _go(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return;
    url = kysoAddressToUrl(url);
    if (!kysoCanOpen(url)) {
      _blocked(url);
      return;
    }
    setState(() => _tab.home = false);
    _tab.state.web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// Trang đã ghim của công ty: catalog của phiên (cập nhật ngay khi ai đó ghim), không có thì danh sách lúc mở.
  List<({String title, String url})> get _pins {
    final lock = widget.lockTokenId;
    final live = [
      for (final t in host.tokens)
        if (lock == null || kysoTokenId(t) == lock)
          for (final p in (t['pins'] as List? ?? const []))
            if (p is Map && '${p['url']}'.isNotEmpty) (title: '${p['title'] ?? p['url']}', url: '${p['url']}'),
    ];
    return live.isNotEmpty ? live : widget.space.bookmarks;
  }

  bool get _canUnpin => host.tokens.any((t) => (widget.lockTokenId == null || kysoTokenId(t) == widget.lockTokenId) && t['canUnpin'] == true);

  String? get _pinToken => widget.lockTokenId ?? (host.tokens.length == 1 ? kysoTokenId(host.tokens.first) : null);

  /// Ghim trang đang mở (hỏi tên; đã ghim thì đổi tên / bỏ ghim). Ghim lưu trên máy chủ ký số, cả công ty thấy.
  Future<void> _pinCurrent() async {
    final messenger = ScaffoldMessenger.of(context);
    final token = _pinToken;
    final url = _tab.url;
    if (token == null || _tab.home || !(url.startsWith('https://') || url.startsWith('http://'))) return;
    final existing = _pins.where((p) => p.url == url).firstOrNull;
    final name = TextEditingController(text: existing?.title ?? (_tab.title == 'Tab mới' ? Uri.parse(url).host : _tab.title));
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Ghim trang này' : 'Trang đã ghim'),
        content: TextField(controller: name, autofocus: true, maxLength: 80, decoration: const InputDecoration(labelText: 'Tên hiển thị')),
        actions: [
          if (existing != null && _canUnpin) TextButton(onPressed: () => Navigator.of(ctx).pop('remove'), child: const Text('Bỏ ghim')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop('save'), child: Text(existing == null ? 'Ghim' : 'Lưu')),
        ],
      ),
    );
    if (action == null) return;
    final error = await host.setPin(token, url, name.text.trim().isEmpty ? url : name.text.trim(), remove: action == 'remove');
    if (error != null) messenger.showSnackBar(SnackBar(content: Text('Không ghim được: $error')));
  }

  Future<void> _unpin(String url) async {
    final token = _pinToken;
    if (token == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bỏ ghim trang này?'),
        content: Text('Trang sẽ mất khỏi danh sách ghim của cả công ty.\n$url'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Bỏ ghim')),
        ],
      ),
    );
    if (ok != true) return;
    final error = await host.setPin(token, url, '', remove: true);
    if (error != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không bỏ ghim được: $error')));
  }

  void _showCompany() {
    final s = host.status.value;
    final connected = s['state'] == 'connected';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.space.name),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.space.env['MST'] != null) Text('MST ${widget.space.env['MST']}'),
          const SizedBox(height: 8),
          Text(connected ? 'Đã kết nối máy chủ ký số' : 'Chưa kết nối máy chủ ký số${s['error'] != null ? ': ${s['error']}' : ''}'),
          Text(host.server, style: Theme.of(ctx).textTheme.bodySmall),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Đóng'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    final colors = ChromeColors.of(
      context,
      widget.space.name,
      brand: widget.space.color != null ? Color(0xFF000000 | widget.space.color!) : null,
    );
    final mst = widget.space.env['MST'];
    final company = widget.space.name.replaceFirst(RegExp(r'^Ký số\s*'), '');
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): () => _newTab(),
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () => _newTab(),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _closeTab(_active),
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () => _closeTab(_active),
        const SingleActivator(LogicalKeyboardKey.f5): () => _tab.state.web?.reload(),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () => _tab.state.web?.reload(),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => _addressFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () => _addressFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _addressFocus.unfocus();
          _address.text = _tab.url;
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.surface,
          body: SafeArea(
          // Điện thoại: thanh trên không chui dưới tai thỏ / thanh trạng thái, thanh dưới tránh vạch home.
          child: ValueListenableBuilder<int>(
            valueListenable: host.storeVersion,
            builder: (context, _, _) => ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: host.status,
              builder: (context, status, _) {
                final pins = _pins;
                final pinned = !_tab.home && pins.any((p) => p.url == _tab.url);
                final httpPage = !_tab.home && (_tab.url.startsWith('https://') || _tab.url.startsWith('http://'));
                final stack = IndexedStack(
                  index: _active,
                  children: [
                    for (final t in _tabs)
                      _TabView(
                        key: t.key,
                        model: t,
                        window: this,
                        home: ChromeHome(
                          colors: colors,
                          company: company,
                          taxCode: mst,
                          bookmarks: pins,
                          canUnpin: _canUnpin,
                          onOpen: _go,
                          onUnpin: _unpin,
                        ),
                      ),
                  ],
                );
                if (!desktop) return _phoneLayout(colors, status, pinned: pinned, httpPage: httpPage, stack: stack);
                return Column(children: [
                  if (desktop)
                    ChromeTabStrip(
                      colors: colors,
                      tabs: [for (final t in _tabs) ChromeTab(title: t.home ? 'Tab mới' : t.title, url: t.home ? '' : t.url, loading: t.loading)],
                      active: _active,
                      connected: status['state'] == 'connected',
                      companyInitial: company.isEmpty ? 'K' : company.characters.first.toUpperCase(),
                      onSelect: _select,
                      onClose: _closeTab,
                      onNew: () => _newTab(),
                      onCompany: _showCompany,
                    ),
                  Container(
                    height: 44,
                    decoration: BoxDecoration(color: colors.surface, border: Border(bottom: BorderSide(color: colors.line))),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(children: [
                      if (!desktop && Navigator.of(context).canPop())
                        ToolButton(icon: Icons.close_rounded, tooltip: 'Đóng', colors: colors, onPressed: () => Navigator.of(context).maybePop()),
                      ToolButton(icon: Icons.arrow_back_rounded, tooltip: 'Quay lại', colors: colors, onPressed: _tab.canBack ? () => _tab.state.web?.goBack() : null),
                      ToolButton(icon: Icons.arrow_forward_rounded, tooltip: 'Tiến tới', colors: colors, onPressed: _tab.canForward ? () => _tab.state.web?.goForward() : null),
                      ToolButton(icon: Icons.refresh_rounded, tooltip: 'Tải lại (F5)', colors: colors, onPressed: _tab.home ? null : () => _tab.state.web?.reload()),
                      ToolButton(
                        icon: Icons.home_outlined,
                        tooltip: 'Trang đầu',
                        colors: colors,
                        onPressed: () => setState(() {
                          _tab.home = true;
                          _address.text = '';
                        }),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Omnibox(
                          controller: _address,
                          focusNode: _addressFocus,
                          colors: colors,
                          secure: _tab.url.startsWith('https://') && !_tab.home,
                          onSubmit: _go,
                        ),
                      ),
                      const SizedBox(width: 4),
                      ToolButton(
                        icon: pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        tooltip: pinned ? 'Trang đã ghim' : 'Ghim trang này cho cả công ty',
                        colors: colors,
                        active: pinned,
                        onPressed: httpPage && _pinToken != null ? _pinCurrent : null,
                      ),
                      if (widget.flygoId != null)
                        ToolButton(icon: Icons.key_rounded, tooltip: 'Điền tài khoản của công ty', colors: colors, onPressed: httpPage ? _fillAccount : null),
                      if (!desktop)
                        ToolButton(icon: Icons.filter_none_rounded, tooltip: '${_tabs.length} tab', colors: colors, onPressed: _showTabs),
                      if (desktop) ...[
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: colors.brandSoft, borderRadius: BorderRadius.circular(999)),
                            child: Text(
                              mst == null ? company : '$company · $mst',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.brand, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        ToolButton(
                          icon: status['state'] == 'connected' ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                          tooltip: status['state'] == 'connected' ? 'Ký số sẵn sàng' : 'Chưa kết nối máy chủ ký số',
                          colors: colors,
                          onPressed: _showCompany,
                        ),
                      ],
                    ]),
                  ),
                  if (desktop) BookmarksBar(colors: colors, bookmarks: pins, onOpen: _go),
                  Expanded(child: stack),
                ]);
              },
            ),
          ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- điện thoại

  /// Lưới tab (như Safari / Chrome điện thoại) đang hiện.
  bool _switcher = false;

  /// Ảnh thu nhỏ của tab [t] cho lưới tab (chụp lúc rời tab và lúc mở lưới; điện thoại).
  Future<void> _snap(_TabModel t) async {
    final web = t.state.web;
    if (isDesktop || web == null || t.home) return;
    try {
      t.thumb = await web.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.JPEG, quality: 40),
      );
    } catch (_) {}
  }

  Future<void> _openSwitcher() async {
    await _snap(_tab);
    if (mounted) setState(() => _switcher = true);
  }

  Future<void> _pageMenu(String action) async {
    final url = _tab.url;
    switch (action) {
      case 'reload':
        await _tab.state.web?.reload();
      case 'home':
        setState(() {
          _tab.home = true;
          _address.text = '';
        });
      case 'pin':
        await _pinCurrent();
      case 'fill':
        await _fillAccount();
      case 'copy':
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép liên kết')));
      case 'external':
        final u = Uri.tryParse(url);
        if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
      case 'company':
        _showCompany();
      case 'close':
        widget.onCloseBrowser?.call();
    }
  }

  /// Nhấn giữ một link: mở ở tab mới / sao chép.
  Future<void> _linkMenu(String url) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.bodySmall)),
          ListTile(leading: const Icon(Icons.open_in_new_rounded), title: const Text('Mở trong tab mới'), onTap: () => Navigator.of(ctx).pop('tab')),
          ListTile(leading: const Icon(Icons.copy_rounded), title: const Text('Sao chép liên kết'), onTap: () => Navigator.of(ctx).pop('copy')),
        ]),
      ),
    );
    if (action == 'tab') _newTab(url: url);
    if (action == 'copy') await Clipboard.setData(ClipboardData(text: url));
  }

  Widget _phoneLayout(ChromeColors colors, Map<String, dynamic> status, {required bool pinned, required bool httpPage, required Widget stack}) {
    final minimize = widget.onMinimize;
    return Column(children: [
      // Thanh địa chỉ gọn phía trên.
      Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(color: colors.surface, border: Border(bottom: BorderSide(color: colors.line))),
        child: Row(children: [
          if (minimize != null)
            ToolButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Thu nhỏ (trình duyệt vẫn chạy)', colors: colors, onPressed: minimize)
          else if (Navigator.of(context).canPop())
            ToolButton(icon: Icons.close_rounded, tooltip: 'Đóng', colors: colors, onPressed: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 4),
          Expanded(
            child: Omnibox(
              controller: _address,
              focusNode: _addressFocus,
              colors: colors,
              secure: _tab.url.startsWith('https://') && !_tab.home,
              onSubmit: _go,
            ),
          ),
          if (_tab.loading) ...[
            const SizedBox(width: 8),
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.brand)),
          ],
        ]),
      ),
      Expanded(
        child: Stack(children: [
          Positioned.fill(child: stack),
          if (_switcher) Positioned.fill(child: _tabGrid(colors)),
        ]),
      ),
      // Thanh công cụ phía dưới, trong tầm ngón cái.
      Container(
        height: 50,
        decoration: BoxDecoration(color: colors.surface, border: Border(top: BorderSide(color: colors.line))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          ToolButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: 'Quay lại', colors: colors, onPressed: _tab.canBack && !_switcher ? () => _tab.state.web?.goBack() : null),
          ToolButton(icon: Icons.arrow_forward_ios_rounded, tooltip: 'Tiến tới', colors: colors, onPressed: _tab.canForward && !_switcher ? () => _tab.state.web?.goForward() : null),
          ToolButton(icon: Icons.add_rounded, tooltip: 'Tab mới', colors: colors, onPressed: () {
            setState(() => _switcher = false);
            _newTab();
          }),
          // Nút tab: số tab trong ô vuông, bấm mở lưới tab.
          Tooltip(
            message: 'Các tab',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _switcher ? () => setState(() => _switcher = false) : _openSwitcher,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: _switcher ? colors.brand : colors.text, width: 1.8),
                    borderRadius: BorderRadius.circular(5),
                    color: _switcher ? colors.brandSoft : null,
                  ),
                  child: Text('${_tabs.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _switcher ? colors.brand : colors.text)),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: Icon(Icons.more_horiz_rounded, color: colors.text),
            onSelected: _pageMenu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'reload', enabled: !_tab.home, child: const ListTile(leading: Icon(Icons.refresh_rounded), title: Text('Tải lại'))),
              const PopupMenuItem(value: 'home', child: ListTile(leading: Icon(Icons.home_outlined), title: Text('Trang đầu'))),
              PopupMenuItem(
                value: 'pin',
                enabled: httpPage && _pinToken != null,
                child: ListTile(leading: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined), title: Text(pinned ? 'Trang đã ghim' : 'Ghim trang')),
              ),
              if (widget.flygoId != null)
                PopupMenuItem(value: 'fill', enabled: httpPage, child: const ListTile(leading: Icon(Icons.key_rounded), title: Text('Điền tài khoản'))),
              PopupMenuItem(value: 'copy', enabled: httpPage, child: const ListTile(leading: Icon(Icons.copy_rounded), title: Text('Sao chép liên kết'))),
              PopupMenuItem(value: 'external', enabled: httpPage, child: const ListTile(leading: Icon(Icons.open_in_browser_rounded), title: Text('Mở bằng trình duyệt ngoài'))),
              PopupMenuItem(
                value: 'company',
                child: ListTile(
                  leading: Icon(status['state'] == 'connected' ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded),
                  title: Text(status['state'] == 'connected' ? 'Ký số sẵn sàng' : 'Chưa kết nối ký số'),
                ),
              ),
              if (widget.onCloseBrowser != null)
                const PopupMenuItem(value: 'close', child: ListTile(leading: Icon(Icons.power_settings_new_rounded), title: Text('Đóng trình duyệt'))),
            ],
          ),
        ]),
      ),
    ]);
  }

  /// Lưới tab: thẻ có ảnh trang, tiêu đề, ✕; vuốt sang bên để đóng; bấm để mở.
  Widget _tabGrid(ChromeColors colors) => ColoredBox(
        color: colors.tab,
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.72),
          itemCount: _tabs.length,
          itemBuilder: (context, i) {
            final t = _tabs[i];
            final active = i == _active;
            return Dismissible(
              key: ObjectKey(t),
              onDismissed: (_) => _closeTab(i),
              child: GestureDetector(
                onTap: () {
                  _select(i);
                  setState(() => _switcher = false);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: active ? colors.brand : colors.line, width: active ? 2.5 : 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                      child: Row(children: [
                        Favicon(url: t.home ? '' : t.url, color: colors.muted, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(t.home ? 'Tab mới' : t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.text)),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          tooltip: 'Đóng tab',
                          onPressed: () => _closeTab(i),
                          icon: Icon(Icons.close_rounded, color: colors.muted),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: t.thumb != null && !t.home
                          ? Image.memory(t.thumb!, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true)
                          : ColoredBox(
                              color: colors.brandSoft,
                              child: Center(child: Icon(t.home ? Icons.home_outlined : Icons.public_rounded, color: colors.brand, size: 36)),
                            ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      );

  void _showTabs() => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('Tab mới'),
              onTap: () {
                Navigator.of(ctx).pop();
                _newTab();
              },
            ),
            for (final (i, t) in _tabs.indexed)
              ListTile(
                selected: i == _active,
                leading: const Icon(Icons.public_rounded),
                title: Text(t.home ? 'Tab mới' : t.title, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.home ? '' : t.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _closeTab(i);
                  },
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _select(i);
                },
              ),
          ],
        ),
      );

  /// Điền tài khoản dùng chung của space (Flygo ID) vào trang đang mở. Mỗi lần đều hỏi sinh trắc; Flygo ID chỉ trả
  /// tài khoản của đúng origin này (trong whitelist) và ghi nhật ký. Mật khẩu chỉ đi vào ô của trang, không hiện ra.
  Future<void> _fillAccount() async {
    final messenger = ScaffoldMessenger.of(context);
    final web = _tab.state.web;
    final page = Uri.tryParse(_tab.url);
    if (web == null || page == null || page.host.isEmpty || _tab.home) {
      messenger.showSnackBar(const SnackBar(content: Text('Hãy mở trang đăng nhập trước.')));
      return;
    }
    if (!widget.space.allows(_tab.url)) {
      messenger.showSnackBar(SnackBar(content: Text('${page.host} không nằm trong danh sách trang của ${widget.space.name}, không điền tài khoản công ty.')));
      return;
    }
    final denied = await host.confirmOwner('Điền tài khoản vào ${page.host}');
    if (denied != null) {
      messenger.showSnackBar(SnackBar(content: Text(denied)));
      return;
    }
    List<VaultFill> entries;
    try {
      entries = await widget.flygoId!.vaultFill(widget.space.id, page.origin);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Không lấy được tài khoản: $e')));
      return;
    }
    if (entries.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('Chưa có tài khoản nào cho ${page.host} trong ${widget.space.name}.')));
      return;
    }
    if (!mounted) return;
    final pick = entries.length == 1
        ? entries.first
        : await showModalBottomSheet<VaultFill>(
            context: context,
            builder: (ctx) => ListView(shrinkWrap: true, children: [
              for (final e in entries)
                ListTile(leading: const Icon(Icons.person_rounded), title: Text(e.username), onTap: () => Navigator.of(ctx).pop(e)),
            ]),
          );
    if (pick == null) return;
    // Trang có thể đã chuyển đi trong lúc hỏi: chỉ điền nếu vẫn đúng origin.
    final now = Uri.tryParse(_tab.url);
    if (now == null || now.origin != page.origin) return;
    final result = await web.callAsyncJavaScript(functionBody: _fillScript, arguments: {'u': pick.username, 'p': pick.password});
    if (result?.value != true) {
      messenger.showSnackBar(const SnackBar(content: Text('Không thấy ô mật khẩu trên trang này.')));
    }
  }

  /// Một tab báo đổi trang / tiêu đề.
  void _changed(_TabModel t) {
    if (!mounted) return;
    setState(() {
      // Đang gõ địa chỉ thì không ghi đè.
      if (identical(t, _tab) && !_addressFocus.hasFocus) _address.text = t.url;
    });
  }
}

/// Điền tên đăng nhập + mật khẩu vào ô đang hiện (setter gốc + sự kiện input/change để trang React/Angular nhận).
const _fillScript = r'''
const visible = (el) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
const pass = [...document.querySelectorAll('input[type=password]')].find(visible);
if (!pass) return false;
const scope = pass.form || document;
const fields = [...scope.querySelectorAll('input')].filter((el) => visible(el) && /^(text|email|tel|)$/i.test(el.type || 'text'));
const before = fields.filter((el) => el.compareDocumentPosition(pass) & Node.DOCUMENT_POSITION_FOLLOWING);
const user = before.length ? before[before.length - 1] : fields[0];
const set = (el, v) => {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  el.focus();
  setter.call(el, v);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
};
if (user && u) set(user, u);
set(pass, p);
return true;
''';

/// Nội dung một tab: website, trang đầu (bookmark), hộp ký đè lên trên.
class _TabView extends StatefulWidget {
  const _TabView({super.key, required this.model, required this.window, required this.home});
  final _TabModel model;
  final _SpaceWindowState window;

  /// Trang đầu của tab trống.
  final Widget home;

  @override
  State<_TabView> createState() => _TabViewState();
}

class _TabViewState extends State<_TabView> {
  double _progress = 1;
  bool _tested = false;

  _TabModel get t => widget.model;
  KysoHost get host => widget.window.host;
  Space get space => widget.window.widget.space;

  /// KYSO_SELFTEST (bản thử): kiểm tra hook của extension trong trang và engine, ghi kết quả ra kyso-selftest.json.
  Future<void> _selfTest(InAppWebViewController controller) async {
    if (!_kSelfTest || _tested) return;
    _tested = true;
    await Future<void>.delayed(const Duration(seconds: 3));
    const probe = '''(async () => {
      const r = { bridge: !!window.__magicSignBridge, native: typeof MagicSignNative,
        fetchPatched: !/native code/.test(String(window.fetch)), wsPatched: !/native code/.test(String(window.WebSocket)) };
      const t0 = Date.now();
      try { const x = await fetch('http://127.0.0.1:19898/'); r.plugin = 'status ' + x.status; }
      catch (e) { r.plugin = String(e); }
      r.pluginMs = Date.now() - t0;
      return JSON.stringify(r);
    })()''';
    final page = await controller.callAsyncJavaScript(functionBody: 'return await $probe;');
    await host.refreshStatus();
    final report = jsonEncode({'platform': Platform.operatingSystem, 'page': page?.value, 'error': page?.error, 'engine': host.status.value});
    debugPrint('[kyso selftest] $report');
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/kyso-selftest.json').writeAsString(report);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tab = t.state;
    return Column(children: [
      if (_progress < 1) LinearProgressIndicator(value: _progress, minHeight: 2),
      Expanded(
        child: Stack(children: [
          Offstage(
            offstage: t.home,
            child: InAppWebView(
              windowId: t.windowId,
              webViewEnvironment: widget.window.widget.environment,
              initialUrlRequest: t.initialUrl == null ? null : URLRequest(url: WebUri(t.initialUrl!)),
              initialSettings: _ProfileSettings(widget.window.widget.profile),
              initialUserScripts: UnmodifiableListView(host.websiteScripts()),
              onWebViewCreated: (controller) => host.attachWebsite(controller, tab),
              onLoadStart: (controller, url) {
                host.pageGone(tab);
                t.url = tab.url = url?.toString() ?? '';
                t.loading = true;
                widget.window._changed(t);
              },
              onUpdateVisitedHistory: (controller, url, _) async {
                t.url = tab.url = url?.toString() ?? '';
                host.tabUpdated(tab);
                t.canBack = await controller.canGoBack();
                t.canForward = await controller.canGoForward();
                widget.window._changed(t);
              },
              onTitleChanged: (_, title) {
                t.title = (title == null || title.isEmpty) ? t.title : title;
                widget.window._changed(t);
              },
              onProgressChanged: (_, progress) => setState(() => _progress = progress / 100),
              onLoadStop: (controller, url) async {
                t.loading = false;
                t.canBack = await controller.canGoBack();
                t.canForward = await controller.canGoForward();
                widget.window._changed(t);
                await _selfTest(controller);
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame != false) {
                  t.loading = false;
                  widget.window._changed(t);
                }
              },
              onConsoleMessage: (_, message) => debugPrint('[browser web] ${message.message}'),
              // window.open / target=_blank: tab mới cùng space, giữ window.opener.
              onCreateWindow: (controller, action) async {
                final url = action.request.url?.toString();
                if (url != null && url.isNotEmpty && url != 'about:blank' && !kysoCanOpen(url)) {
                  widget.window._blocked(url);
                  return false;
                }
                widget.window._newTab(windowId: action.windowId);
                return true;
              },
              onCloseWindow: (_) {
                final i = widget.window._tabs.indexOf(t);
                if (i >= 0) widget.window._closeTab(i);
              },
              // Nhấn giữ link (điện thoại): mở ở tab mới / sao chép.
              onLongPressHitTestResult: (controller, hit) {
                final url = hit.extra;
                if (url == null || !kysoCanOpen(url)) return;
                if (hit.type == InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE || hit.type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE) {
                  widget.window._linkMenu(url);
                }
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final url = action.request.url;
                if (url == null) return NavigationActionPolicy.ALLOW;
                if (const {'about', 'data', 'blob', 'javascript'}.contains(url.scheme)) return NavigationActionPolicy.ALLOW;
                if (!const {'http', 'https'}.contains(url.scheme)) return NavigationActionPolicy.CANCEL;
                // Mở được mọi trang web (Sếp, 2026-11-09). Danh sách trang của công ty chỉ còn dùng cho điền tài khoản
                // và trang ghim; ký số trên trang nào vẫn do extension (content_scripts) và hộp xác nhận quyết định.
                if (action.isForMainFrame && !kysoCanOpen(url.toString())) {
                  widget.window._blocked(url.toString());
                  return NavigationActionPolicy.CANCEL;
                }
                return NavigationActionPolicy.ALLOW;
              },
            ),
          ),
          if (t.home) widget.home,
          // Hộp xác nhận ký: trang của extension vẽ đè lên website, website không chạm được.
          ValueListenableBuilder<bool>(
            valueListenable: tab.overlay,
            builder: (context, visible, child) => Offstage(offstage: !visible, child: child),
            child: InAppWebView(
              webViewEnvironment: host.appEnvironment,
              initialUrlRequest: URLRequest(url: WebUri('${kysoAppBase}app/prompt.html')),
              initialSettings: kysoAppPageSettings(),
              initialUserScripts: UnmodifiableListView([
                host.roleScript('prompt'),
                UserScript(source: host.promptSource, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END, forMainFrameOnly: true),
              ]),
              onLoadResourceWithCustomScheme: (_, request) => kysoServeAsset(request),
              onWebViewCreated: (controller) => host.attachAppPage(controller, promptFor: tab),
              shouldOverrideUrlLoading: (_, action) async =>
                  '${action.request.url}'.startsWith(kysoAppBase) ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL,
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// Đăng nhập trên máy tính: trang đăng nhập của máy chủ ký số trong một WebView của app; bắt redirect
/// vn.flygo.magic-sign://oauth?... (tạm thời; khi có Flygo ID thì đổi vé, không cần đăng nhập lại).
Future<String?> _desktopLogin(BuildContext context, String url) async {
  if (!context.mounted) return null;
  return Navigator.of(context).push<String>(AppPageRoute(
    builder: (ctx) => Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập máy chủ ký số')),
      body: InAppWebView(
        webViewEnvironment: KysoHost.instance.appEnvironment,
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true, isInspectable: true),
        shouldOverrideUrlLoading: (_, action) async {
          final next = action.request.url;
          if (next != null && next.scheme == 'vn.flygo.magic-sign') {
            Navigator.of(ctx).pop(next.toString());
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
      ),
    ),
  ));
}
