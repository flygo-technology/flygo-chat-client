import 'dart:async';
import 'i18n/i18n.dart';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'auth/auth_service.dart';
import 'calls/call_service.dart';
import 'agent/agent_service.dart';
import 'push/push_service.dart';
import 'update/updater.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_to_front/window_to_front.dart';
import 'config.dart';
import 'data/servers.dart';
import 'data/models.dart';
import 'browser/browser_dock.dart';
import 'browser/flygo_id.dart';
import 'security/device_key.dart';
import 'security/verify_page.dart';
import 'ui/share_intake.dart';
import 'ui/app_route.dart';
import 'kyso/kyso_api.dart';
import 'kyso/kyso_windows.dart';
import 'ui/mini_app_windows.dart';
import 'ui/qr_login.dart';
import 'state/drafts.dart';
import 'state/app_state.dart';
import 'ui/call_screen.dart';
import 'ui/direct_call_screen.dart' show IncomingCallToast;
import 'ui/ai_panel.dart';
import 'ui/ai_consent.dart';
import 'ui/chat_page.dart';
import 'ui/flows/process_detail.dart' show ProcessDetailPage;
import 'ui/desktop_tray.dart';
import 'ui/flags.dart';
import 'ui/home_page.dart';
import 'ui/panes/pane_layout.dart';
import 'ui/popout_windows.dart';
import 'ui/reaction_usage.dart';
import 'ui/login_page.dart';
import 'ui/password_page.dart' show PasswordGate;
import 'ui/server_picker.dart' show kAddServer;
import 'ui/theme.dart';
import 'ui/important_alert.dart';
import 'ui/urgent_alert.dart';
import 'remote/rc_call.dart' show RcWindowJob, rcWindowArgsParse;
import 'remote/rc_service.dart' show RemoteControlService;
import 'remote/rc_ui.dart';

/// Phiên đăng nhập hiện tại; bọc toàn bộ app để mọi trang đều đọc được.
final session = ValueNotifier<AppState?>(null);
final navigatorKey = GlobalKey<NavigatorState>();

/// Nhật ký khởi động trên máy tính: %TEMP%\flygo-init.log (một dòng mỗi bước) để biết app kẹt ở đâu khi màn
/// trắng (vd. máy có nhiều phần mềm diệt virus chặn file). Lỗi ghi thì bỏ qua.
void initMark(String step) {
  if (!isDesktop) return;
  try {
    File('${Directory.systemTemp.path}${Platform.pathSeparator}flygo-init.log')
        .writeAsStringSync('${DateTime.now().toIso8601String()} [$pid] $step\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

/// Chờ một bước khởi động tối đa [limit]; quá hạn thì ghi nhật ký rồi đi tiếp (không để cả app kẹt ở màn trắng).
Future<void> _initStep(String name, Future<void> Function() step, {Duration limit = const Duration(seconds: 8)}) async {
  initMark('$name: bắt đầu');
  try {
    await step().timeout(limit);
    initMark('$name: xong');
  } on TimeoutException {
    initMark('$name: QUÁ HẠN ${limit.inSeconds}s, bỏ qua');
  } catch (e) {
    initMark('$name: LỖI $e');
  }
}

/// Cửa sổ điều khiển máy tính từ xa (`--rc=`): việc cần làm khi mở.
RcWindowJob? _rcJob;

Future<void> main(List<String> args) async {
  initMark('main: bắt đầu ${args.join(' ')}');
  if (await AuthService.relayCallback(args)) exit(0);
  // Xin đồng ý trước khi gửi dữ liệu cho AI (AppState gọi, hiện trên cửa sổ đang mở).
  AppState.aiConsentPrompt = (privacy) async {
    final ctx = navigatorKey.currentContext;
    return ctx != null && ctx.mounted && await showAiConsentDialog(ctx, privacy);
  };
  if (Platform.isWindows) _registerWindowsScheme();
  initMark('đăng ký flygochat:// xong');
  kWindowChannel = args.where((a) => a.startsWith('--chat=')).map((a) => a.substring(7)).firstOrNull;
  final ai = args.where((a) => a.startsWith('--ai=')).map((a) => a.substring(5)).firstOrNull;
  if (ai != null) {
    final parts = ai.split('#');
    kWindowChannel = parts.first;
    kWindowAi = true;
    kWindowAiThread = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
  }
  final thread = args.where((a) => a.startsWith('--thread=')).map((a) => a.substring(9).split('#')).firstOrNull;
  if (thread != null && thread.length == 2 && thread[1].isNotEmpty) {
    kWindowChannel = thread[0];
    kWindowThread = thread[1];
  }
  final call = args.where((a) => a.startsWith('--call=')).map((a) => a.substring(7)).firstOrNull;
  if (call != null) {
    kWindowChannel = call;
    kWindowCall = true;
    kWindowCallVideo = args.contains('--call-video');
    kWindowCallMeeting = args.contains('--call-meeting');
    kWindowCallMeetingPost = args.where((a) => a.startsWith('--call-meeting-post=')).map((a) => a.substring(20)).firstOrNull;
  }
  // Cửa sổ điều khiển máy tính từ xa (máy tính): tiến trình riêng chỉ có trang điều khiển.
  _rcJob = kWindowChannel == null ? rcWindowArgsParse(args) : null;
  kWindowRc = _rcJob != null;
  ServerList.pinned = args.where((a) => a.startsWith('--server=')).map((a) => a.substring(9)).firstOrNull;
  // Cửa sổ Ký số riêng (máy tính): trình duyệt nhiều tab của một công ty (lib/kyso/kyso_windows.dart).
  kWindowKyso = kWindowChannel == null && !kWindowRc
      ? args.where((a) => a.startsWith('--kyso=')).map((a) => a.substring(7)).where((s) => s.isNotEmpty).firstOrNull
      : null;
  // Cửa sổ riêng của một mini app (máy tính): chỉ có webview của app (lib/ui/mini_app_windows.dart).
  kWindowMiniApp = kWindowChannel == null && !kWindowRc && kWindowKyso == null
      ? args.where((a) => a.startsWith('--miniapp=')).map((a) => a.substring(10)).where((s) => s.isNotEmpty).firstOrNull
      : null;
  kWindowAddServer = args.contains('--add-server');
  kStartHidden = args.contains('--hidden');
  final section = args.where((a) => a.startsWith('--section=')).map((a) => a.substring(10)).firstOrNull;
  if (section != null && PaneSections.all.contains(section) && kWindowChannel == null) kWindowSection = section;
  // Cửa sổ tách ra từ màn chia ô (một chat hoặc một mục): cửa sổ chính quản lý (nhớ vị trí, mở lại khi mở app).
  final popout = kWindowSection != null
      ? PaneContent.section(kWindowSection!)
      : kWindowChannel != null && !kWindowAi && kWindowThread == null && !kWindowCall
          ? PaneContent.chat(kWindowChannel!)
          : null;
  kWindowPopout = args.contains('--popout') && popout != null;
  WidgetsFlutterBinding.ensureInitialized();
  initMark('ensureInitialized xong');
  // macOS: bản ký Developer ID không mang entitlement (không sandbox), mà file_picker kiểm entitlement
  // files.user-selected trước khi mở hộp chọn tệp nên báo lỗi và không mở gì (Sếp, bản 452: đăng bài, đính kèm).
  if (Platform.isMacOS) unawaited(FilePicker.skipEntitlementsChecks().catchError((_) {}));
  // Cửa sổ riêng đã mở rồi thì nhờ cửa sổ đó hiện lên và thoát; đặt lại vị trí / kích thước lần trước.
  if (kWindowPopout) await _initStep('cửa sổ riêng', () => PopoutWindows.startChild(popout!));
  KysoWindows.parentKey = args.where((a) => a.startsWith('--kyso-key=')).map((a) => a.substring(11)).where((s) => s.isNotEmpty).firstOrNull;
  if (kWindowKyso != null) await _initStep('cửa sổ Ký số', () => KysoWindows.startChild(kWindowKyso!));
  MiniAppWindows.parentKey = args.where((a) => a.startsWith('--miniapp-key=')).map((a) => a.substring(14)).where((s) => s.isNotEmpty).firstOrNull;
  if (kWindowMiniApp != null) await _initStep('cửa sổ mini app', () => MiniAppWindows.startChild(kWindowMiniApp!));
  // macOS (không sandbox): thư mục tạm ~/Library/Caches/<bundle id> có thể chưa tồn tại, mọi chỗ ghi tệp tạm
  // (dán ảnh, chụp màn hình, ảnh sửa, tải cập nhật…) sẽ lỗi "No such file or directory".
  try {
    await (await getTemporaryDirectory()).create(recursive: true);
  } catch (_) {}
  await _initStep('migrate', _migrateMacSandboxData);
  await _initStep('ngôn ngữ', loadLanguage);
  // Nháp tin nhắn theo chat: đọc nền, ô soạn tin tự chờ nếu mở chat trước khi đọc xong.
  unawaited(Drafts.load());
  await _initStep('reaction', ReactionUsage.load);
  // Khay hệ thống chạy nền, không chặn khung hình đầu: trên máy có nhiều phần mềm diệt virus, gọi khay / ghi
  // khoá khởi động cùng Windows có thể treo rất lâu (có máy >8 giây, bản cũ treo mãi nên màn trắng).
  unawaited(_initStep('khay', DesktopTray.init, limit: const Duration(seconds: 60)));
  // Cập nhật app, thông báo: chỉ cửa sổ chính (cửa sổ riêng khởi động nhẹ, không báo trùng).
  if (!isChildWindow) Updater.start();
  if (!kWindowPopout && kWindowKyso == null && kWindowMiniApp == null) await _initStep('push', PushService.init);
  // Ký số (lib/kyso): nút "Mở bằng trình duyệt ký số" của Quy trình gọi qua MagicSignHooks.
  KysoApi.register();
  initMark('runApp');
  runApp(const FlygoChatApp());
  WidgetsBinding.instance.addPostFrameCallback((_) => initMark('khung hình đầu tiên đã vẽ'));
  // Máy tính: cửa sổ vừa mở riêng (chat, trợ lý AI, luồng, cuộc họp, máy chủ khác, thêm máy chủ) thì đưa lên trước.
  if (isDesktop && (ServerList.pinned != null || kWindowChannel != null || kWindowAddServer || kWindowRc || kWindowKyso != null || kWindowMiniApp != null)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowToFront.activate();
      Future.delayed(const Duration(milliseconds: 600), WindowToFront.activate);
      Future.delayed(const Duration(milliseconds: 1500), WindowToFront.activate);
    });
  }
}

/// macOS: bản cũ chạy trong sandbox, dữ liệu nằm ở ~/Library/Containers/vn.flygo.chat. Bản mới
/// (không sandbox, để chạy được trợ lý AI) chép dữ liệu đó sang thư mục mới ở lần mở đầu tiên.
Future<void> _migrateMacSandboxData() async {
  if (!Platform.isMacOS) return;
  try {
    final dir = await getApplicationSupportDirectory();
    final home = Platform.environment['HOME'] ?? '';
    final old = Directory('$home/Library/Containers/vn.flygo.chat/Data/Library/Application Support/vn.flygo.chat');
    if (dir.path.contains('/Library/Containers/') || !old.existsSync()) return;
    final marker = File('${dir.path}/.migrated_from_sandbox');
    if (marker.existsSync()) return;
    await dir.create(recursive: true);
    for (final e in old.listSync()) {
      if (e is! File) continue;
      final target = File('${dir.path}/${e.uri.pathSegments.last}');
      if (!target.existsSync()) await e.copy(target.path);
    }
    await marker.writeAsString(DateTime.now().toIso8601String());
  } catch (e) {
    debugPrint('[migrate] $e');
  }
}

/// Windows: đăng ký liên kết flygochat:// (đăng nhập Google trả về app) cho người dùng hiện tại.
void _registerWindowsScheme() {
  final exe = Platform.resolvedExecutable;
  const key = r'HKCU\Software\Classes\flygochat';
  for (final a in [
    ['add', key, '/ve', '/d', 'URL:Flygo Chat', '/f'],
    ['add', key, '/v', 'URL Protocol', '/d', '', '/f'],
    ['add', '$key\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"', '/f'],
  ]) {
    Process.run('reg', a).catchError((_) => ProcessResult(0, 1, '', ''));
  }
}

class FlygoChatApp extends StatelessWidget {
  const FlygoChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLanguage,
      builder: (_, lang, _) => _app(lang),
    );
  }

  Widget _app(String lang) {
    return MaterialApp(
      title: 'Flygo Chat',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      supportedLocales: [for (final l in appLanguages.keys) Locale(l)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => CenteredToasts(
        child: ValueListenableBuilder<AppState?>(
          valueListenable: session,
          builder: (_, app, _) => app == null
              ? child!
              // Trình duyệt Ký số (điện thoại) chạy song song: lớp nổi trên toàn app, thu nhỏ vẫn giữ các tab.
              : ChangeNotifierProvider<AppState>.value(value: app, child: BrowserDockLayer(child: child!)),
        ),
      ),
      home: const Root(),
    );
  }
}

/// Quyết định hiện màn hình đăng nhập hay màn hình chính.
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  AppState? _app;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  /// Màn đăng nhập: email đã nhập, máy chủ của email không bật Google (hiện ô mật khẩu).
  String _email = '';
  bool _needPassword = false;
  /// Điện thoại đang "Thêm máy chủ mới": máy chủ đang dùng trước đó (nút Quay lại ở màn đăng nhập).
  String? _prevServer;
  late final AppLifecycleListener _life;
  /// Số lần chưa đọc được phiên đã lưu (máy đang khoá khi cuộc gọi / push mở app...). Khác 0: đang chờ thử lại,
  /// vẫn giữ màn chờ thay vì đưa ra màn đăng nhập.
  int _restoreFails = 0;
  bool _restoring = false;

  Future<void> _askLanguage() async {
    final nav = navigatorKey.currentState;
    final ctx = nav?.overlay?.context ?? context;
    final device = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final lang = await showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (d) => SimpleDialog(
        title: const Text('Chọn ngôn ngữ · Language'),
        children: [
          for (final e in appLanguages.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  LangFlag(e.key),
                  const SizedBox(width: 14),
                  Text(e.value, style: TextStyle(fontSize: 17, fontWeight: e.key == device ? FontWeight.w700 : FontWeight.w400)),
                ]),
              ),
            ),
        ],
      ),
    );
    await setLanguage(lang ?? (appLanguages.containsKey(device) ? device : 'vi'));
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Máy tính: runner trợ lý AI đi kèm app — cập nhật bản đã cài nếu app mang bản mới hơn (chỉ cửa sổ chính).
    if (!isChildWindow) AgentService.instance.syncBundledRunner();
    _life = AppLifecycleListener(
      onResume: () {
        _app?.appResumed();
        TokenStore.migrate();
        if ((_restoreFails > 0 || _restoreGaveUp) && _app == null) {
          _restoreGaveUp = false;
          _restore();
        }
      },
      onStateChange: (s) => PushService.appFocused = s == AppLifecycleState.resumed,
      // Thoát app: dừng các trợ lý AI đang chạy trong app (đưa bot về offline).
      onExitRequested: () async {
        await AgentService.instance.stopAll();
        return AppExitResponse.exit;
      },
    );
    PushService.openChannel.addListener(_onPushOpen);
    // Lần đầu mở app: chọn ngôn ngữ.
    if (!languageChosen) WidgetsBinding.instance.addPostFrameCallback((_) => _askLanguage());
    PushService.acceptCall.addListener(_onPushAccept);
    // Điều khiển máy tính từ xa: cửa sổ chính nhận lời xin / lời mời; mọi cửa sổ xin / mời được (máy tính: trang
    // điều khiển mở ở cửa sổ riêng `--rc=`).
    RemoteControlUi.bind(session, navigatorKey);
    // Thiết bị: yêu cầu xác thực từ xa (thông báo, bấm thông báo, websocket) mở màn hình "Xác thực"; vừa đăng nhập
    // thì xem có yêu cầu nào đang chờ (lỡ thông báo).
    PushService.verifyRequest.addListener(_onVerify);
    session.addListener(_checkPendingVerify);
    // Cửa sổ "Thêm máy chủ mới": không mở phiên đã lưu, vào thẳng màn đăng nhập.
    ServerList.load().then((_) => kWindowAddServer ? setState(() => _loading = false) : _restore(),
        onError: (_) => setState(() => _loading = false));
  }

  final _verifyOpen = <String>{};

  Future<void> _onVerify() async {
    final id = PushService.verifyRequest.value;
    final app = session.value;
    if (id == null || id.isEmpty || app == null || _verifyOpen.contains(id)) return;
    final flygoId = await FlygoId.current(app.token).catchError((_) => null);
    final nav = navigatorKey.currentState;
    if (flygoId == null || nav == null) return;
    _verifyOpen.add(id);
    await nav.push(AppPageRoute(builder: (_) => VerifyPage(id: id, flygoId: flygoId)));
    _verifyOpen.remove(id);
  }

  Future<void> _checkPendingVerify() async {
    final app = session.value;
    if (app == null || !(await DeviceKey.status()).enrolled) return;
    try {
      final id = await FlygoId.current(app.token);
      final pending = await id?.pendingVerifies() ?? const [];
      if (pending.isNotEmpty) PushService.openVerify('${pending.first['id'] ?? ''}');
    } catch (_) {}
  }

  /// Mở phiên đã lưu. Không đọc được kho bảo mật (máy khoá lúc cuộc gọi / push đánh thức app) không có nghĩa là
  /// đã đăng xuất: giữ màn chờ, thử lại sau vài giây và khi app được mở; quá nhiều lần mới hiện màn đăng nhập.
  /// Đã thử đọc phiên đã lưu nhiều lần không được: mở app lại (onResume) thì thử tiếp.
  bool _restoreGaveUp = false;

  Future<void> _restore() async {
    if (_restoring) return;
    _restoring = true;
    try {
      final a = await AppState.restore();
      _restoreFails = 0;
      if (!mounted) return;
      _attach(a);
      setState(() {
        _loading = false;
        if (a != null) _error = null;
      });
    } catch (e) {
      debugPrint('[restore] $e');
      _restoreFails++;
      if (!mounted) return;
      if (_restoreFails >= 20) {
        // Kho bảo mật vẫn chưa đọc được (vd app bị đánh thức ở nền lúc máy khoá): hiện màn đăng nhập kèm lời báo,
        // nhưng KHÔNG coi là đã đăng xuất: lần mở app tiếp theo (onResume) đọc lại phiên đã lưu. Trước đây đặt lại bộ
        // đếm về 0 nên onResume không thử lại và app kẹt ở màn đăng nhập dù phiên trên máy chủ vẫn còn.
        _restoreFails = 0;
        _restoreGaveUp = true;
        setState(() {
          _loading = false;
          _error = tr('Chưa đọc được phiên đăng nhập đã lưu trên máy. Mở khoá máy và mở lại app để thử lại.');
        });
        return;
      }
      Future.delayed(Duration(seconds: _restoreFails < 5 ? 3 : 15), () {
        if (mounted && _app == null && _restoreFails > 0) _restore();
      });
    } finally {
      _restoring = false;
    }
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  void _attach(AppState? a) {
    _app = a;
    session.value = a;
    a?.calls.onShowCallScreen = () {
      // Máy tính: cuộc gọi đến hiện thông báo gọn ở góc (không che cả cửa sổ); nghe máy mới mở màn hình cuộc gọi.
      final app = _app;
      if (isDesktop && app != null && app.calls.phase == CallPhase.incoming) return _showIncomingToast(app);
      _pushCallScreen();
    };
    a?.addListener(_onAppChange);
    a?.urgentAlert.addListener(_onUrgent);
    a?.importantAlert.addListener(_onImportant);
    if (a != null && !isChildWindow) {
      a.registerPush();
      a.calls.addListener(_onCallChange);
      PushService.onSystemDecline = (ch) => _app?.calls.declineFromSystem(ch);
      PushService.onSystemEnd = (ch) => _app?.calls.endFromSystem(ch);
      PushService.onSystemMute = (m) => _app?.calls.setMuted(m);
      _onPushOpen();
      _onPushAccept();
      // Nhận chia sẻ từ app khác (ảnh, tệp, chữ, link): mở "Gửi tới…" khi đã đăng nhập.
      ShareIntake.start(navigatorKey, session);
    }
    if (a != null && a.sessionExpired) _expired();
  }

  /// Tin quan trọng: hộp thông báo giữa màn hình ngay khi nhận (cả khi không ở chat đó), không âm thanh.
  Future<void> _onImportant() async {
    final a = _app, p = a?.importantAlert.value;
    if (a == null || p == null) return;
    a.importantAlert.value = null;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    if (isDesktop) WindowToFront.activate();
    await showImportantAlert(ctx, a, p, onOpen: (id) => PushService.openChannel.value = id);
  }

  /// Tin khẩn cấp: hiện toàn màn hình, đè lên mọi màn hình khác (máy tính: đưa cửa sổ lên trước).
  Future<void> _onUrgent() async {
    final a = _app, p = a?.urgentAlert.value;
    if (a == null || p == null) return;
    a.urgentAlert.value = null;
    if (isDesktop) {
      await DesktopTray.show();
      WindowToFront.activate();
    }
    navigatorKey.currentState?.push(PageRouteBuilder(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (_, _, _) => UrgentAlertPage(app: a, post: p),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Bấm vào thông báo tin nhắn: mở cuộc trò chuyện đó.
  Future<void> _onPushOpen() async {
    final id = PushService.openChannel.value;
    if (id == null || _app == null) return;
    PushService.openChannel.value = null;
    // Thông báo từ máy chủ khác: điện thoại chuyển sang máy chủ đó trước.
    final url = ServerList.urlForServerId(PushService.openServerId ?? '');
    PushService.openServerId = null;
    if (url != null && url != kServerUrl && !isDesktop) {
      await _switchServer(url);
      if (_app == null) return;
    }
    // Tin trong luồng: mở thẳng vào luồng (sau khi mở chat chính).
    final postId = PushService.openPostId;
    PushService.openPostId = null;
    String? root;
    MmPost? urgent;
    // Mở từ thông báo tin khẩn cấp (kể cả màn hình khoá): sau khi mở chat thì hiện toàn màn hình nếu chưa xác nhận.
    void showUrgent() {
      if (urgent case final u?) _app?.showUrgent(u);
    }
    if (postId != null && _app != null) {
      try {
        final p = MmPost((await _app!.api.get('/posts/$postId') as Map).cast());
        if (p.rootId.isNotEmpty && p.inThread) root = p.rootId;
        urgent = p;
      } catch (_) {}
    }
    // Thảo luận của tiến trình (kênh ẩn): mở trang tiến trình ở phần thảo luận.
    final processId = (_app?.channels[id] ?? await _app?.ensureChannel(id))?.processId;
    if (processId != null && _app != null && !isDesktop) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.popUntil((r) => r.isFirst);
      nav.push(MaterialPageRoute(builder: (_) => ProcessDetailPage(app: _app!, processId: processId, initialTab: 1)));
      return;
    }
    if (isDesktop) {
      await DesktopTray.show();
      WindowToFront.activate();
      final hook = PushService.openChatHook;
      if (hook != null) {
        hook(id);
        if (root != null) PushService.openThreadHook?.call(id, root);
        showUrgent();
        return;
      }
    }
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => ChatPage(channelId: id)));
    if (root != null) nav.push(MaterialPageRoute(builder: (_) => ThreadPage(channelId: id, rootId: root!)));
    showUrgent();
  }

  /// Bấm "Trả lời" trên màn hình cuộc gọi của hệ điều hành.
  void _onPushAccept() {
    final id = PushService.acceptCall.value;
    final a = _app;
    if (id == null || a == null) return;
    PushService.acceptCall.value = null;
    a.calls.acceptFromSystem(id, video: PushService.acceptVideo);
    PushService.acceptVideo = false;
  }

  /// Cuộc gọi trong app kết thúc: đóng luôn màn hình cuộc gọi của hệ điều hành.
  CallPhase? _lastCallPhase;
  OverlayEntry? _incomingToast;

  void _pushCallScreen() {
    navigatorKey.currentState?.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CallScreen()));
  }

  void _hideIncomingToast() {
    _incomingToast?.remove();
    _incomingToast = null;
  }

  /// Cuộc gọi đến trên máy tính: thẻ gọn ở góc trên phải, tự ẩn khi người gọi huỷ / đã nghe ở máy khác.
  void _showIncomingToast(AppState a) {
    _hideIncomingToast();
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return _pushCallScreen();
    var accepted = false;
    late final OverlayEntry entry;
    void onCall() {
      if (a.calls.phase == CallPhase.incoming) return;
      a.calls.removeListener(onCall);
      if (_incomingToast == entry) _hideIncomingToast();
      // Nghe máy từ thẻ (hoặc từ nơi khác): mở màn hình cuộc gọi.
      if (!accepted && (a.calls.phase == CallPhase.connecting || a.calls.phase == CallPhase.active)) _pushCallScreen();
    }

    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 16,
        right: 16,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: a.calls,
            builder: (_, _) => IncomingCallToast(
              app: a,
              onAccepted: () {
                accepted = true;
                a.calls.removeListener(onCall);
                if (_incomingToast == entry) _hideIncomingToast();
                _pushCallScreen();
              },
            ),
          ),
        ),
      ),
    );
    _incomingToast = entry;
    overlay.insert(entry);
    a.calls.addListener(onCall);
  }

  void _onCallChange() {
    final p = _app?.calls.phase;
    // Cuộc gọi đến khi cửa sổ đang ẩn dưới khay: hiện cửa sổ lên.
    if (p == CallPhase.incoming && _lastCallPhase != CallPhase.incoming) DesktopTray.show();
    _lastCallPhase = p;
    PushService.inCallChannel =
        p == CallPhase.outgoing || p == CallPhase.connecting || p == CallPhase.active ? _app?.calls.channelId : null;
    if (p == CallPhase.ended || p == CallPhase.idle) PushService.endCalls();
    final a = _app, ch = a?.calls.channelId;
    if (a != null && ch != null && PushService.inCallChannel == ch) {
      final c = a.channels[ch];
      PushService.reportCall(ch,
          name: c == null ? 'Flygo Chat' : a.channelTitle(c), video: a.calls.isVideoCall, connected: p == CallPhase.active, muted: a.calls.muted);
    }
  }

  void _onAppChange() {
    if (_app?.sessionExpired == true) _expired();
  }

  void _expired() {
    final a = _app;
    if (a == null) return;
    // Cửa sổ riêng tách từ cửa sổ chính: phiên hết hạn thì đóng (cửa sổ chính tự xử lý đăng nhập lại).
    if (kWindowPopout) exit(0);
    a.removeListener(_onAppChange);
    a.urgentAlert.removeListener(_onUrgent);
    a.importantAlert.removeListener(_onImportant);
    // Máy chủ đã huỷ phiên: chỉ xoá trên máy (gọi đăng xuất lên máy chủ cũng chỉ nhận 401).
    a.logout(remote: false);
    session.value = null;
    setState(() {
      _app = null;
      _error = tr('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
    });
  }

  /// Chuyển máy chủ: đóng phiên hiện tại (không đăng xuất), mở phiên đã lưu
  /// của máy chủ mới, chưa có thì hiện màn đăng nhập.
  Future<void> _switchServer(String url) async {
    if (url == kAddServer) return _addServer();
    _prevServer = null;
    final old = _app;
    if (old != null) {
      old.removeListener(_onAppChange);
      old.urgentAlert.removeListener(_onUrgent);
      old.importantAlert.removeListener(_onImportant);
      old.disposeSession();
    }
    session.value = null;
    setState(() {
      _app = null;
      _loading = true;
      _error = null;
    });
    await ServerList.use(url);
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    try {
      _attach(await AppState.restore());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// "Thêm máy chủ mới" (điện thoại): đóng phiên hiện tại (không đăng xuất), hiện màn đăng nhập.
  void _addServer() {
    final old = _app;
    if (old != null) {
      old.removeListener(_onAppChange);
      old.urgentAlert.removeListener(_onUrgent);
      old.importantAlert.removeListener(_onImportant);
      old.disposeSession();
    }
    session.value = null;
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    setState(() {
      _prevServer = kServerUrl;
      _app = null;
      _error = null;
      _email = '';
      _needPassword = false;
    });
  }

  /// Tìm máy chủ chat theo tên miền email (hoặc dùng đúng [server] người dùng nhập) rồi chuyển sang máy chủ đó.
  /// Trả về máy chủ tìm được, null nếu không tìm thấy (đã hiện lỗi) hoặc máy chủ đó đã đăng nhập sẵn (đã vào app).
  Future<FoundServer?> _serverForEmail(String email, [String server = '']) async {
    setState(() {
      _busy = true;
      _error = null;
      _email = email;
      _needPassword = false;
    });
    final domain = ServerList.emailDomain(email);
    final manual = ServerList.normalize(server);
    final s = manual.isNotEmpty
        ? await ServerList.probe(manual, name: domain.isEmpty ? null : domain)
        : domain.isEmpty
            ? null
            : await ServerList.discover(email);
    if (!mounted) return null;
    if (s == null) {
      setState(() {
        _busy = false;
        _error = manual.isNotEmpty
            ? tr('Không kết nối được máy chủ {0}. Kiểm tra lại địa chỉ máy chủ.', [Uri.tryParse(manual)?.host ?? manual])
            : domain.isEmpty
            ? tr('Email chưa đúng. Nhập email công ty, ví dụ ten@congty.vn.')
            : tr('Không tìm thấy máy chủ chat của {0}. Kiểm tra lại email hoặc hỏi quản trị viên.', [domain]);
      });
      return null;
    }
    if (kWindowAddServer) {
      // Cửa sổ thêm máy chủ: không mở trùng máy chủ của cửa sổ chính (hai cửa sổ ghi chung một kho trên máy).
      if (s.url == ServerList.current) {
        setState(() {
          _busy = false;
          _error = tr('Máy chủ {0} đang mở ở cửa sổ chính.', [Uri.parse(s.url).host]);
        });
        return null;
      }
      // Cửa sổ này dành riêng cho máy chủ vừa tìm được, không đổi máy chủ của cửa sổ chính.
      ServerList.pinned = s.url;
    }
    if (s.url != kServerUrl || _prevServer != null || kWindowAddServer) {
      if (!ServerList.items.any((e) => e.url == s.url)) await ServerList.add(s.url, s.name, select: false);
      await _switchServer(s.url);
      if (_app != null) return null;
    }
    return s;
  }

  /// "Tiếp tục" ở màn đăng nhập: dò máy chủ theo email, rồi tự mở đăng nhập Google của máy chủ đó
  /// (máy chủ không bật Google thì hiện ô mật khẩu).
  Future<void> _loginEmail(String email, String server) async {
    final s = await _serverForEmail(email, server);
    if (s == null || !mounted) return;
    // Tài khoản demo@… / apple.review@… (để thử app, cho người duyệt App Store): luôn đăng nhập bằng mật khẩu.
    final e = email.trim().toLowerCase();
    final demo = e.startsWith('demo@') || e.startsWith('apple.review@');
    if (s.google && !demo) {
      await _login();
    } else {
      // Máy chủ không bật Google (hoặc tài khoản demo): cần mật khẩu.
      setState(() {
        _busy = false;
        _needPassword = true;
        _error = !s.password && !demo
            ? tr('Máy chủ {0} chưa bật đăng nhập Google. Liên hệ quản trị viên.', [Uri.parse(s.url).host])
            : tr('Nhập mật khẩu để đăng nhập.');
      });
    }
  }

  /// Nút "Đăng nhập bằng Google": có email / máy chủ thì dò máy chủ trước, không thì dùng máy chủ đang chọn.
  Future<void> _loginGoogle(String email, String server) async {
    if (server.isNotEmpty || ServerList.emailDomain(email).isNotEmpty) {
      final s = await _serverForEmail(email, server);
      if (s == null || !mounted) return;
    }
    await _login();
  }

  Future<void> _loginPassword(String login, String password, String server) async {
    // Có địa chỉ máy chủ thì dùng máy chủ đó; đăng nhập bằng email thì tìm máy chủ theo tên miền trước.
    if (server.isNotEmpty || ServerList.emailDomain(login).isNotEmpty) {
      final s = await _serverForEmail(login, server);
      if (s == null || !mounted) return;
    }
    await _login(password: (login, password));
  }

  Future<void> _login({(String, String)? password, String? qrToken}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = qrToken ??
          (password != null
              ? await AuthService.loginWithPassword(password.$1, password.$2)
              : await AuthService.loginWithGoogle());
      await TokenStore.write(token);
      final a = AppState(token);
      await a.start(waitForSync: true);
      if (a.me == null) throw Exception(a.lastError ?? tr('Không kết nối được máy chủ'));
      setState(() => _attach(a));
    } on LoginCancelled {
      _error = tr('Chưa đăng nhập xong. Bấm nút để thử lại.');
    } catch (e) {
      final msg = e.toString();
      _error = password != null
          ? msg.replaceFirst('Exception: ', '')
          : msg.contains('CANCELED') || msg.contains('cancel')
              ? tr('Đã hủy đăng nhập.')
              : tr('Đăng nhập không thành công. Kiểm tra kết nối mạng và thử lại.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final a = _app;
    if (a == null) return;
    a.removeListener(_onAppChange);
    a.urgentAlert.removeListener(_onUrgent);
    a.importantAlert.removeListener(_onImportant);
    await a.logout();
    session.value = null;
    setState(() => _app = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: Icon(Icons.forum, size: 72, color: Pal.of(context).accent)));
    }
    final a = _app;
    if (a == null) {
      return LoginPage(
        busy: _busy,
        error: _error,
        email: _email,
        showPassword: _needPassword,
        onEmail: _loginEmail,
        onPasswordLogin: _loginPassword,
        onGoogle: _loginGoogle,
        // Máy tính: đăng nhập bằng QR quét từ điện thoại cùng mạng LAN.
        onQrLogin: !isDesktop
            ? null
            : () => navigatorKey.currentState?.push(MaterialPageRoute(
                builder: (_) => QrLoginPage(
                    server: kServerUrl,
                    onToken: (t, server, name) async {
                      // Máy tính theo máy chủ của điện thoại: chưa có trong danh sách thì thêm vào.
                      if (server != kServerUrl) {
                        ServerList.items.any((e) => e.url == server)
                            ? await ServerList.use(server)
                            : await ServerList.add(server, name);
                      }
                      _login(qrToken: t);
                    }))),
        onCancel: _prevServer == null ? null : () => _switchServer(_prevServer!),
      );
    }
    if (_rcJob case final job?) return RcWindow(key: ValueKey(a), job: job);
    if (kWindowKyso case final space?) return KysoSpaceWindowPage(key: ValueKey(a), spaceId: space);
    if (kWindowMiniApp case final id?) return MiniAppWindowPage(key: ValueKey(a), appId: id);
    final w = kWindowChannel;
    if (w != null && kWindowCall) return CallWindow(key: ValueKey(a), app: a);
    if (w != null && kWindowThread != null) return ThreadPage(key: ValueKey(Object.hash(a, appLanguage.value)), channelId: w, rootId: kWindowThread!);
    if (w != null && kWindowAi) {
      return Scaffold(key: ValueKey(Object.hash(a, appLanguage.value)), body: AiPanel(groupId: w, thread: kWindowAiThread));
    }
    if (w != null) return ChatPage(key: ValueKey(Object.hash(a, appLanguage.value)), channelId: w, embedded: true);
    // Cửa sổ riêng của một mục thanh tab (Chat, Các trợ lý, Việc, Luồng, Bạn).
    if (kWindowSection != null) {
      return HomePage(
          key: ValueKey(Object.hash(a, appLanguage.value)), onLogout: _logout, onSwitchServer: _switchServer, solo: kWindowSection);
    }
    // Tài khoản được cấp mật khẩu (có dấu phải đổi): đổi mật khẩu lần đầu trước khi vào app.
    return PasswordGate(
      onLogout: _logout,
      child: HomePage(key: ValueKey(Object.hash(a, appLanguage.value)), onLogout: _logout, onSwitchServer: _switchServer),
    );
  }
}

/// Cửa sổ riêng của cuộc họp (máy tính): vào cuộc họp ngay khi mở, rời cuộc họp thì đóng cửa sổ (thoát tiến trình).
class CallWindow extends StatefulWidget {
  final AppState app;
  const CallWindow({super.key, required this.app});
  @override
  State<CallWindow> createState() => _CallWindowState();
}

class _CallWindowState extends State<CallWindow> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    widget.app.calls.addListener(_onCall);
    RemoteControlService.instance.addListener(_onCall);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      WindowToFront.activate();
      await widget.app.calls.startCall(kWindowChannel!, video: kWindowCallVideo, meeting: kWindowCallMeeting, meetingPost: kWindowCallMeetingPost);
      _started = true;
      _onCall();
    });
  }

  void _onCall() {
    // Đang cho người khác điều khiển máy mình (mời từ cuộc họp này): giữ cửa sổ tới khi hết phiên.
    final rc = RemoteControlService.instance;
    if (_started && !widget.app.calls.busy && !rc.busy) exit(0);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.app.calls.removeListener(_onCall);
    RemoteControlService.instance.removeListener(_onCall);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rc = RemoteControlService.instance;
    final sharing = _started && !widget.app.calls.busy && rc.busy;
    return Scaffold(
      backgroundColor: const Color(0xFF202124),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(sharing ? tr('{0} đang điều khiển máy của bạn', [rc.peerName]) : tr('Đang vào cuộc họp…'),
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
          if (sharing) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: () => rc.stop(), child: Text(tr('Dừng'))),
          ],
        ]),
      ),
    );
  }
}
