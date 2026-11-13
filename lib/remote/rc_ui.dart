// Điều khiển máy tính từ xa: giao diện (mục trong cài đặt tin riêng, hộp thoại xin phép / lời mời, xin quyền macOS,
// trang điều khiển cho máy tính và điện thoại kèm chọn màn hình của máy kia, cửa sổ điều khiển riêng trên máy tính,
// trang "Máy tính" của chính mình).
import '../update/build_label.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:window_to_front/window_to_front.dart';

import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import '../ui/common.dart' show Avatar;
import '../ui/desktop_tray.dart';
import '../ui/theme.dart';
import 'rc_native.dart';
import 'rc_protocol.dart';
import 'rc_service.dart';

class RemoteControlUi {
  static GlobalKey<NavigatorState>? _nav;

  /// Gắn dịch vụ vào cửa sổ (main.dart). Cửa sổ chính nhận lời xin / lời mời; cửa sổ cuộc họp riêng mời được người
  /// khác điều khiển máy mình; cửa sổ điều khiển (`--rc=`) tự hiện trang điều khiển ([RcWindow]).
  static void bind(ValueNotifier<AppState?> session, GlobalKey<NavigatorState> nav) {
    _nav = nav;
    final s = RemoteControlService.instance;
    s.showIncoming = _showIncoming;
    s.openController = kWindowRc ? null : () => _nav?.currentState?.push(MaterialPageRoute(builder: (_) => const RcControllerPage()));
    // Máy tính: trang điều khiển luôn ở cửa sổ riêng (tiến trình app khác).
    s.openWindow = isDesktop && !kWindowRc
        ? (args) async {
            try {
              await Process.start(Platform.resolvedExecutable, args, mode: ProcessStartMode.detached);
            } catch (e) {
              debugPrint('[rc] window: $e');
              s.toast?.call(tr('Không mở được cửa sổ riêng.'));
            }
          }
        : null;
    s.ensurePermissions = () async {
      final nav = _nav?.currentState;
      if (nav == null) return false;
      return await nav.push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const RcPermissionPage())) ?? false;
    };
    s.toast = (text) {
      final ctx = _nav?.currentContext;
      if (ctx != null) ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(toast(Text(text)));
    };
    s.bind(session);
  }

  static Future<void> _showIncoming(RcConsent c) async {
    if (isDesktop) {
      await DesktopTray.show();
      WindowToFront.activate();
    }
    final ctx = _nav?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showDialog<void>(context: ctx, barrierDismissible: false, builder: (_) => _RcIncomingDialog(consent: c));
  }

  /// Tin riêng 1-1 với người (không bot, không chat với chính mình, không phải chat AI).
  static bool availableFor(AppState app, MmChannel ch) {
    if (kIsWeb || kWindowRc || !ch.isDirect || ch.isSelfDm || ch.isSub || ch.isAi || app.me == null) return false;
    final other = ch.otherUserId(app.me!.id);
    final u = other == null ? null : app.users[other];
    return u != null && !u.isBot && u.deleteAt == 0;
  }
}

/// Phím tắt dừng (thanh đỏ, máy bị điều khiển).
String get _stopHotkeyHint => !kIsWeb && Platform.isMacOS ? 'Cmd+Shift+F12' : 'Ctrl+Shift+F12';

// ------------------------------------------------------------------ hộp thoại xin phép (máy bị điều khiển)

class _RcIncomingDialog extends StatefulWidget {
  final RcConsent consent;
  const _RcIncomingDialog({required this.consent});
  @override
  State<_RcIncomingDialog> createState() => _RcIncomingDialogState();
}

class _RcIncomingDialogState extends State<_RcIncomingDialog> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (!widget.consent.pending) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = widget.consent;
    final win = !kIsWeb && Platform.isWindows;
    return AlertDialog(
      icon: Avatar(userId: c.fromUserId, name: c.fromName, size: 64, status: false),
      title: Text(
          c.invite ? tr('{0} mời bạn điều khiển máy tính của họ', [c.fromName]) : tr('{0} muốn điều khiển máy tính của bạn', [c.fromName]),
          textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            c.invite
                ? tr('Bạn sẽ thấy màn hình và dùng chuột, bàn phím của máy người này. Họ dừng được bất cứ lúc nào.')
                : tr('Người này sẽ thấy màn hình và dùng chuột, bàn phím của bạn. Bấm Dừng trên thanh đỏ hoặc {0} để dừng bất cứ lúc nào.',
                    [_stopHotkeyHint]),
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.sub, height: 1.35),
          ),
          if (win && !c.invite) ...[
            const SizedBox(height: 8),
            Text(tr('Cửa sổ chạy quyền quản trị (UAC) và màn hình khoá không điều khiển được.'),
                textAlign: TextAlign.center, style: TextStyle(color: pal.sub, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          Text(tr('Tự từ chối sau {0} giây', [c.secondsLeft()]), style: TextStyle(color: pal.sub, fontSize: 12.5)),
        ]),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () {
            RemoteControlService.instance.declineIncoming();
            Navigator.of(context).pop();
          },
          child: Text(tr('Từ chối')),
        ),
        FilledButton(
          onPressed: () {
            RemoteControlService.instance.acceptIncoming();
            Navigator.of(context).pop();
          },
          child: Text(c.invite ? tr('Đồng ý') : tr('Cho phép')),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ quyền macOS

/// macOS: giải thích và xin quyền Trợ năng (điều khiển chuột, bàn phím) và Ghi màn hình. Trả về true khi đủ quyền.
class RcPermissionPage extends StatefulWidget {
  const RcPermissionPage({super.key});
  @override
  State<RcPermissionPage> createState() => _RcPermissionPageState();
}

class _RcPermissionPageState extends State<RcPermissionPage> {
  RcPermissions _p = const RcPermissions(accessibility: false, screen: false);
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _check();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final p = await RcNative.permissions();
    if (mounted) setState(() => _p = p);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget item(bool ok, String kind, IconData icon, String title, String body) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Icon(icon, color: ok ? const Color(0xFF34C759) : pal.sub),
            title: Text(title),
            subtitle: Text(body),
            trailing: ok
                ? const Icon(Icons.check_circle, color: Color(0xFF34C759))
                : FilledButton.tonal(
                    onPressed: () async {
                      await RcNative.request(kind);
                      await RcNative.openSettings(kind);
                    },
                    child: Text(tr('Mở Cài đặt')),
                  ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(tr('Cấp quyền điều khiển máy tính'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(
          tr('Để người khác điều khiển máy Mac này, Flygo Chat cần hai quyền trong Cài đặt hệ thống › Quyền riêng tư & Bảo mật. Bật Flygo Chat trong từng mục rồi quay lại đây.'),
          style: TextStyle(height: 1.4, color: pal.text),
        ),
        const SizedBox(height: 16),
        item(_p.accessibility, 'accessibility', Icons.mouse_outlined, tr('Trợ năng'), tr('Để dùng chuột và bàn phím thay bạn.')),
        item(_p.screen, 'screen', Icons.screenshot_monitor_outlined, tr('Ghi màn hình'),
            tr('Để gửi hình màn hình. Sau khi bật, macOS có thể yêu cầu mở lại Flygo Chat.')),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Hủy'))),
          const SizedBox(width: 8),
          FilledButton(onPressed: _p.ok ? () => Navigator.pop(context, true) : null, child: Text(tr('Tiếp tục'))),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ trang điều khiển (máy điều khiển)

class RcControllerPage extends StatefulWidget {
  /// Cửa sổ điều khiển riêng (máy tính): đóng trang = đóng cửa sổ. null: trang trong Navigator (điện thoại).
  final VoidCallback? onClose;
  const RcControllerPage({super.key, this.onClose});
  @override
  State<RcControllerPage> createState() => _RcControllerPageState();
}

class _RcControllerPageState extends State<RcControllerPage> {
  final _svc = RemoteControlService.instance;
  final _focus = FocusNode(debugLabel: 'rc-remote');
  RTCVideoRenderer? _renderer;
  Size _video = Size.zero;
  Size _box = Size.zero;
  String _quality = 'auto';
  bool? _swap;
  bool _full = false;
  bool _wasActive = false;
  // Gộp các lần di chuột (tối đa ~60 lần / giây).
  (int, int)? _pendingMove;
  Timer? _moveTimer;
  final Map<int, int> _pointerButtons = {};
  Offset? _lastPan;
  // Điện thoại: phóng to / kéo khung hình, cuộn bằng hai ngón.
  double _scale = 1;
  Offset _pan = Offset.zero;
  double _startScale = 1;
  Offset _startPan = Offset.zero;
  Offset _startFocal = Offset.zero;
  bool _zooming = false;
  double _scrollAcc = 0;
  final _kbFocus = FocusNode(debugLabel: 'rc-soft-kb');
  final _kb = TextEditingController(text: kRcSentinel);
  String _kbPrev = kRcSentinel;
  bool _kbOpen = false;
  String _screenId = '';

  bool get _mobile => !isDesktop;
  bool get _remoteMac => _svc.remotePlatform == 'macos';
  bool get _swapMeta => _swap ?? (isDesktop && (!kIsWeb && Platform.isMacOS) != _remoteMac);

  @override
  void initState() {
    super.initState();
    _kb.selection = const TextSelection.collapsed(offset: kRcSentinel.length);
    _svc.addListener(_onSvc);
    _onSvc();
    _focus.addListener(() {
      if (!_focus.hasFocus) _svc.sendInput(const RcRelease());
    });
  }

  @override
  void dispose() {
    _svc.removeListener(_onSvc);
    _renderer?.onResize = null;
    _moveTimer?.cancel();
    if (_full) RcNative.setFullscreen(false);
    if (_svc.role == RcRole.controller) _svc.stop();
    _focus.dispose();
    _kbFocus.dispose();
    _kb.dispose();
    super.dispose();
  }

  void _onSvc() {
    final r = _svc.renderer;
    if (r != _renderer) {
      _renderer?.onResize = null;
      _renderer = r;
      r?.onResize = () {
        if (mounted) setState(() => _video = Size(r.videoWidth.toDouble(), r.videoHeight.toDouble()));
      };
    }
    // Máy kia đổi màn hình: khung hình mới, bỏ phóng to cũ.
    if (_svc.screenId != _screenId) {
      _screenId = _svc.screenId;
      _scale = 1;
      _pan = Offset.zero;
    }
    if (_svc.phase == RcPhase.active && !_wasActive) {
      _wasActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
    // Mình bấm Dừng: đóng trang. Máy kia dừng / lỗi: hiện lý do.
    if (_svc.phase == RcPhase.idle && _svc.role == RcRole.none && _wasActive && _svc.endReason == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- gửi thao tác

  (int, int)? _wire(Offset local, {bool clamp = false}) {
    final p = _mobile ? rcUnzoom(local, _scale, _pan) : local;
    return rcToWire(p, _box, _video, clamp: clamp);
  }

  void _queueMove((int, int) w) {
    _pendingMove = w;
    _moveTimer ??= Timer(const Duration(milliseconds: 16), () {
      _moveTimer = null;
      final m = _pendingMove;
      _pendingMove = null;
      if (m != null) _svc.sendInput(RcMove(m.$1, m.$2));
    });
  }

  void _flushMove() {
    _moveTimer?.cancel();
    _moveTimer = null;
    final m = _pendingMove;
    _pendingMove = null;
    if (m != null) _svc.sendInput(RcMove(m.$1, m.$2));
  }

  void _click(Offset local, int button) {
    final w = _wire(local);
    if (w == null) return;
    _svc.sendInput(RcMove(w.$1, w.$2));
    _svc.sendInput(RcButton(button, true, w.$1, w.$2));
    _svc.sendInput(RcButton(button, false, w.$1, w.$2));
  }

  void _key(int hid, bool down) => _svc.sendInput(RcKey(_swapMeta ? rcSwapMeta(hid) : hid, down));

  void _tapKey(int hid) {
    _key(hid, true);
    _key(hid, false);
  }

  void _sendText(String s) {
    for (final part in chunkRcText(s)) {
      _svc.sendInput(RcText(part));
    }
  }

  static int _buttonOf(int buttons) => buttons & kSecondaryMouseButton != 0
      ? 1
      : buttons & kMiddleMouseButton != 0
          ? 2
          : 0;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_svc.phase != RcPhase.active) return KeyEventResult.ignored;
    final hid = rcHidFromUsage(e.physicalKey.usbHidUsage);
    if (hid == null) {
      // Phím không có trong bảng (vd. phím đa phương tiện lạ): gửi chữ nếu có.
      final ch = e.character;
      if (e is KeyDownEvent && ch != null && ch.isNotEmpty) _sendText(ch);
      return KeyEventResult.handled;
    }
    _key(hid, e is! KeyUpEvent);
    return KeyEventResult.handled;
  }

  Future<void> _pasteText() async {
    final t = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (t.isEmpty) return;
    _sendText(t);
    _focus.requestFocus();
  }

  Future<void> _typeText() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Gửi chữ sang máy kia')),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          decoration: InputDecoration(hintText: tr('Gõ chữ (kể cả tiếng Việt có dấu) rồi bấm Gửi')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(tr('Gửi'))),
        ],
      ),
    );
    c.dispose();
    if (text != null && text.isNotEmpty) _sendText(text);
    _focus.requestFocus();
  }

  void _cad() {
    if (_svc.remotePlatform == 'linux') {
      // GNOME / KDE: Ctrl+Alt+Del mở hộp thoại đăng xuất, không có trình quản lý tác vụ chung để mở thay.
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(toast(Text(tr('Máy kia là Linux: không gửi Ctrl+Alt+Del (sẽ mở hộp thoại đăng xuất).'))));
      _focus.requestFocus();
      return;
    }
    for (final k in rcSecureAttention(macTarget: _remoteMac)) {
      _svc.sendInput(k);
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(_remoteMac
        ? tr('Máy kia là Mac: đã mở "Thoát ứng dụng bắt buộc" (Cmd+Option+Esc).')
        : tr('Windows không cho phần mềm gửi Ctrl+Alt+Del: đã mở Trình quản lý tác vụ (Ctrl+Shift+Esc).'))));
    _focus.requestFocus();
  }

  void _setQuality(String q) {
    setState(() => _quality = q);
    _svc.sendInput(RcQuality(q));
    _focus.requestFocus();
  }

  Future<void> _toggleFull() async {
    _full = !_full;
    await RcNative.setFullscreen(_full);
    if (mounted) setState(() {});
    _focus.requestFocus();
  }

  // ---------------------------------------------------------------- bàn phím ảo (điện thoại)

  void _onSoftKb(String _) {
    final v = _kb.value;
    if (v.composing.isValid && !v.composing.isCollapsed) return; // bộ gõ đang ghép chữ: chờ xong
    final (del, ins) = rcTextDiff(_kbPrev, v.text);
    for (var i = 0; i < del; i++) {
      _tapKey(RcHid.backspace);
    }
    final text = ins.replaceAll('\u200B', '');
    if (text.isNotEmpty) _sendText(text);
    _kb.value = const TextEditingValue(text: kRcSentinel, selection: TextSelection.collapsed(offset: kRcSentinel.length));
    _kbPrev = kRcSentinel;
  }

  void _toggleKb() {
    setState(() => _kbOpen = !_kbOpen);
    if (_kbOpen) {
      _kbFocus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    } else {
      _kbFocus.unfocus();
    }
  }

  // ---------------------------------------------------------------- vẽ

  String _statusText() {
    final name = _svc.peerName;
    switch (_svc.phase) {
      case RcPhase.requesting:
        return _svc.own ? tr('Đang kết nối…') : tr('Đang chờ {0} cho phép…', [name]);
      case RcPhase.connecting:
        return tr('Đang kết nối…');
      case RcPhase.ringing:
      case RcPhase.active:
        return '';
      case RcPhase.idle:
    }
    final o = _svc.outcome;
    if (o != null && o != RcRequestOutcome.accepted) {
      return switch (o) {
        RcRequestOutcome.declined => tr('{0} đã từ chối', [name]),
        RcRequestOutcome.permission => tr('Máy của {0} chưa cấp quyền điều khiển. Thử lại sau khi họ cấp quyền.', [name]),
        RcRequestOutcome.timeout => tr('{0} không trả lời', [name]),
        // Máy của chính mình từ chối "không hỗ trợ": thường là chưa cấp quyền Ghi màn hình / Trợ năng hoặc app trên máy đó chưa sẵn sàng.
        RcRequestOutcome.unsupported when _svc.own => tr('Máy {0} chưa sẵn sàng để điều khiển. Mở Flygo Chat trên máy đó và cấp quyền Ghi màn hình + Trợ năng (macOS), rồi thử lại.', [name]),
        RcRequestOutcome.unsupported =>
          '${tr('Máy kia không hỗ trợ bị điều khiển')}\n${tr('Chỉ máy tính Windows, macOS hoặc Linux (phiên X11, chưa hỗ trợ Wayland) đang mở Flygo Chat mới bị điều khiển được.')}',
        RcRequestOutcome.busy => tr('Máy kia đang trong một phiên điều khiển khác'),
        RcRequestOutcome.noStation => tr('Máy chủ chat này chưa hỗ trợ điều khiển máy tính'),
        _ => tr('Không xin được quyền điều khiển. Thử lại sau.'),
      };
    }
    return switch (_svc.endReason) {
      'permission' => tr('Máy của {0} chưa cấp quyền điều khiển. Thử lại sau khi họ cấp quyền.', [name]),
      'capture' => tr('Máy kia không chụp được màn hình'),
      'network' || 'gone' || 'signal' => tr('Mất kết nối với máy kia'),
      'cancelled' => tr('Máy kia đã huỷ phiên điều khiển'),
      'timeout' => tr('{0} không trả lời', [name]),
      _ => tr('{0} đã dừng phiên điều khiển', [name]),
    };
  }

  void _close() {
    final c = widget.onClose;
    if (c != null) return c();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = _svc.phase == RcPhase.active && _svc.role == RcRole.controller;
    final r = _renderer;
    final video = r == null
        ? const SizedBox.shrink()
        : RTCVideoView(r, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain, filterQuality: FilterQuality.medium);
    final status = _statusText();
    final body = LayoutBuilder(builder: (context, c) {
      _box = Size(c.maxWidth, c.maxHeight);
      final view = _mobile ? _mobileView(video) : _desktopView(video);
      return Stack(fit: StackFit.expand, children: [
        ColoredBox(color: Colors.black, child: active || _svc.phase == RcPhase.connecting ? view : const SizedBox.shrink()),
        if (status.isNotEmpty) _overlay(status),
      ]);
    });
    final ended = _svc.phase == RcPhase.idle;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _full
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF16181C),
              foregroundColor: Colors.white,
              titleSpacing: 0,
              title: Text(_svc.peerName.isEmpty ? tr('Điều khiển máy tính') : _svc.peerName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
              actions: [if (active && !_mobile) ..._desktopActions(), if (!ended) _endButton(), const SizedBox(width: 8)],
            ),
      body: SafeArea(child: body),
      bottomNavigationBar: active && _mobile ? _mobileBar() : null,
    );
  }

  Widget _endButton() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D), foregroundColor: Colors.white),
          onPressed: () {
            // Huỷ lời xin đang chờ: đóng luôn trang (cửa sổ điều khiển riêng thì đóng cửa sổ).
            final waiting = _svc.phase == RcPhase.requesting;
            _svc.stop();
            if (waiting) _close();
          },
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: Text(_svc.phase == RcPhase.requesting ? tr('Hủy') : tr('Dừng')),
        ),
      );

  Widget _overlay(String text) => Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(color: const Color(0xE01C1C1E), borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_svc.phase == RcPhase.requesting || _svc.phase == RcPhase.connecting) ...[
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70)),
              const SizedBox(height: 14),
            ] else ...[
              const Icon(Icons.desktop_access_disabled_outlined, color: Colors.white70, size: 34),
              const SizedBox(height: 12),
            ],
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
            if (_svc.phase == RcPhase.idle) ...[
              const SizedBox(height: 14),
              FilledButton(onPressed: _close, child: Text(tr('Đóng'))),
            ],
          ]),
        ),
      );

  /// Tên màn hình của máy kia: tên hệ điều hành đặt, không có thì "Màn hình N".
  String _screenLabel(RcDisplay d, int i) => d.name.isEmpty ? tr('Màn hình {0}', [i + 1]) : d.name;

  void _selectScreen(String id) {
    _svc.selectScreen(id);
    _focus.requestFocus();
  }

  /// Chọn màn hình của máy kia (chỉ hiện khi máy kia có nhiều màn hình).
  Widget? _screenSelector() {
    final list = _svc.screens;
    if (list.length < 2) return null;
    const fg = Colors.white;
    final cur = list.indexWhere((d) => d.id == _svc.screenId);
    return PopupMenuButton<String>(
      key: const ValueKey('rc-screen-selector'),
      tooltip: tr('Chọn màn hình'),
      initialValue: _svc.screenId,
      onSelected: _selectScreen,
      icon: _svc.switchingTo != null
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.monitor_outlined, color: fg),
              if (cur >= 0) ...[
                const SizedBox(width: 2),
                Text('${cur + 1}', style: const TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ]),
      itemBuilder: (_) => [
        for (var i = 0; i < list.length; i++)
          CheckedPopupMenuItem(
            value: list[i].id,
            checked: list[i].id == _svc.screenId,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_screenLabel(list[i], i), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                [
                  if (list[i].width > 0 && list[i].height > 0) '${list[i].width}×${list[i].height}',
                  if (list[i].primary) tr('Màn hình chính'),
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ]),
          ),
      ],
    );
  }

  List<Widget> _desktopActions() {
    const fg = Colors.white;
    final screen = _screenSelector();
    return [
      ?screen,
      PopupMenuButton<String>(
        tooltip: tr('Chất lượng hình'),
        icon: const Icon(Icons.high_quality_outlined, color: fg),
        initialValue: _quality,
        onSelected: _setQuality,
        itemBuilder: (_) => [
          PopupMenuItem(value: 'auto', child: Text(tr('Tự động'))),
          PopupMenuItem(value: 'high', child: Text(tr('Nét nhất'))),
          PopupMenuItem(value: 'low', child: Text(tr('Mượt (mạng yếu)'))),
        ],
      ),
      IconButton(tooltip: tr('Dán chữ sang máy kia'), icon: const Icon(Icons.content_paste_go_outlined, color: fg), onPressed: _pasteText),
      IconButton(tooltip: tr('Gửi chữ (bộ gõ tiếng Việt)'), icon: const Icon(Icons.keyboard_alt_outlined, color: fg), onPressed: _typeText),
      TextButton(
        onPressed: _cad,
        child: Tooltip(
          message: tr('Windows chặn Ctrl+Alt+Del từ phần mềm: nút này mở Trình quản lý tác vụ (Mac: Thoát ứng dụng bắt buộc).'),
          child: const Text('Ctrl+Alt+Del', style: TextStyle(color: fg, fontSize: 13)),
        ),
      ),
      PopupMenuButton<String>(
        tooltip: tr('Thêm'),
        icon: const Icon(Icons.more_vert, color: fg),
        onSelected: (v) {
          if (v == 'swap') setState(() => _swap = !_swapMeta);
          _focus.requestFocus();
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(value: 'swap', checked: _swapMeta, child: Text(tr('Đổi Cmd ↔ Ctrl'))),
        ],
      ),
      IconButton(
        tooltip: _full ? tr('Thoát toàn màn hình') : tr('Toàn màn hình'),
        icon: Icon(_full ? Icons.fullscreen_exit : Icons.fullscreen, color: fg),
        onPressed: _toggleFull,
      ),
    ];
  }

  Widget _desktopView(Widget video) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        // Mũi tên thường như trên máy kia (không dùng dấu "+").
        cursor: SystemMouseCursors.basic,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerHover: (e) {
            final w = _wire(e.localPosition);
            if (w != null) _queueMove(w);
          },
          onPointerMove: (e) {
            final w = _wire(e.localPosition, clamp: true);
            if (w != null) _queueMove(w);
          },
          onPointerDown: (e) {
            _focus.requestFocus();
            final w = _wire(e.localPosition);
            if (w == null) return;
            _flushMove();
            final b = _buttonOf(e.buttons);
            _pointerButtons[e.pointer] = b;
            _svc.sendInput(RcMove(w.$1, w.$2));
            _svc.sendInput(RcButton(b, true, w.$1, w.$2));
          },
          onPointerUp: (e) {
            final b = _pointerButtons.remove(e.pointer);
            if (b == null) return;
            _flushMove();
            final w = _wire(e.localPosition, clamp: true) ?? (0, 0);
            _svc.sendInput(RcButton(b, false, w.$1, w.$2));
          },
          onPointerCancel: (e) {
            final b = _pointerButtons.remove(e.pointer);
            if (b != null) _svc.sendInput(const RcRelease());
          },
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _svc.sendInput(RcWheel(e.scrollDelta.dx.round().clamp(-kRcMaxWheel, kRcMaxWheel), e.scrollDelta.dy.round().clamp(-kRcMaxWheel, kRcMaxWheel)));
            }
          },
          // Bàn di chuột (trackpad) trên Mac: cuộn hai ngón đến dưới dạng pan.
          onPointerPanZoomStart: (_) => _lastPan = Offset.zero,
          onPointerPanZoomUpdate: (e) {
            final d = e.pan - (_lastPan ?? Offset.zero);
            _lastPan = e.pan;
            if (d.distance < .5) return;
            _svc.sendInput(RcWheel((-d.dx).round().clamp(-kRcMaxWheel, kRcMaxWheel), (-d.dy).round().clamp(-kRcMaxWheel, kRcMaxWheel)));
          },
          onPointerPanZoomEnd: (_) => _lastPan = null,
          child: video,
        ),
      ),
    );
  }

  Widget _mobileView(Widget video) {
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _click(d.localPosition, 0),
        onLongPressStart: (d) {
          HapticFeedback.mediumImpact();
          _click(d.localPosition, 1);
        },
        onScaleStart: (d) {
          _startScale = _scale;
          _startPan = _pan;
          _startFocal = d.localFocalPoint;
          _zooming = false;
          _scrollAcc = 0;
        },
        onScaleUpdate: (d) {
          if (d.pointerCount >= 2 && !_zooming && (d.scale - 1).abs() > .08) _zooming = true;
          if (d.pointerCount >= 2 && !_zooming) {
            // Hai ngón kéo: cuộn trang bên máy kia (kéo xuống = cuộn lên, như màn hình cảm ứng).
            _scrollAcc += -d.focalPointDelta.dy * 2;
            if (_scrollAcc.abs() >= 8) {
              _svc.sendInput(RcWheel(0, _scrollAcc.round().clamp(-kRcMaxWheel, kRcMaxWheel)));
              _scrollAcc = 0;
            }
            return;
          }
          setState(() {
            final s = (_zooming ? _startScale * d.scale : _scale).clamp(1.0, 5.0);
            // Giữ điểm giữa hai ngón ở yên chỗ khi phóng to; một ngón thì kéo khung hình.
            final anchor = (_startFocal - _startPan) / _startScale;
            final p = _zooming ? d.localFocalPoint - anchor * s : _startPan + (d.localFocalPoint - _startFocal);
            _scale = s;
            _pan = rcClampPan(p, s, _box);
          });
        },
        child: ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(_pan.dx, _pan.dy, 0, 1)
              ..scaleByDouble(_scale, _scale, 1, 1),
            child: video,
          ),
        ),
      ),
      // Ô nhập ẩn để mở bàn phím ảo; chữ gõ vào được gửi sang máy kia.
      Positioned(
        left: 0,
        bottom: 0,
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0,
          child: TextField(
            focusNode: _kbFocus,
            controller: _kb,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.send,
            onChanged: _onSoftKb,
            onSubmitted: (_) {
              _tapKey(RcHid.enter);
              _kbFocus.requestFocus();
            },
          ),
        ),
      ),
    ]);
  }

  Widget _mobileBar() {
    const fg = Colors.white;
    Widget key(String label, int hid) => TextButton(
          onPressed: () => _tapKey(hid),
          style: TextButton.styleFrom(foregroundColor: fg, minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text(label),
        );
    return Container(
      color: const Color(0xFF16181C),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_kbOpen)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                key('Esc', RcHid.esc),
                key('Tab', RcHid.tab),
                key('←', RcHid.left),
                key('↑', RcHid.up),
                key('↓', RcHid.down),
                key('→', RcHid.right),
                key('Del', RcHid.delete),
                key('⌫', RcHid.backspace),
                key('↵', RcHid.enter),
              ]),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            IconButton(
              tooltip: tr('Bàn phím'),
              icon: Icon(_kbOpen ? Icons.keyboard_hide_outlined : Icons.keyboard_outlined, color: fg),
              onPressed: _toggleKb,
            ),
            IconButton(tooltip: tr('Dán chữ sang máy kia'), icon: const Icon(Icons.content_paste_go_outlined, color: fg), onPressed: _pasteText),
            ?_screenSelector(),
            TextButton(onPressed: _cad, child: const Text('Ctrl+Alt+Del', style: TextStyle(color: fg, fontSize: 12.5))),
            PopupMenuButton<String>(
              tooltip: tr('Chất lượng hình'),
              icon: const Icon(Icons.high_quality_outlined, color: fg),
              initialValue: _quality,
              onSelected: _setQuality,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'auto', child: Text(tr('Tự động'))),
                PopupMenuItem(value: 'high', child: Text(tr('Nét nhất'))),
                PopupMenuItem(value: 'low', child: Text(tr('Mượt (mạng yếu)'))),
              ],
            ),
            IconButton(
              tooltip: tr('Vừa màn hình'),
              icon: const Icon(Icons.fit_screen_outlined, color: fg),
              onPressed: () => setState(() {
                _scale = 1;
                _pan = Offset.zero;
              }),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ cửa sổ điều khiển riêng (máy tính)

/// Cửa sổ điều khiển (máy tính, `--rc=`): một tiến trình app riêng chỉ có trang điều khiển. Mở là làm việc [job]
/// (xin điều khiển / nhận phiên đã đồng ý lời mời / máy tính của chính mình); đóng trang hoặc hết phiên thì thoát.
class RcWindow extends StatefulWidget {
  final RcWindowJob job;
  const RcWindow({super.key, required this.job});
  @override
  State<RcWindow> createState() => _RcWindowState();
}

class _RcWindowState extends State<RcWindow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowToFront.activate();
      RemoteControlService.instance.runWindowJob(widget.job);
    });
  }

  Future<void> _close() async {
    await RemoteControlService.instance.stop();
    // Chờ tin "end" đi tới trạm rồi mới thoát.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  @override
  Widget build(BuildContext context) => RcControllerPage(onClose: _close);
}

// ------------------------------------------------------------------ "Máy tính" của chính mình

/// Biểu tượng theo hệ điều hành.
IconData rcPlatformIcon(String p) => switch (p) {
      'windows' => Icons.desktop_windows_outlined,
      'macos' => Icons.laptop_mac_outlined,
      'linux' => Icons.computer_outlined,
      _ => Icons.devices_other_outlined,
    };

String rcPlatformName(String p) => switch (p) {
      'windows' => 'Windows',
      'macos' => 'macOS',
      'linux' => 'Linux',
      _ => tr('Máy tính'),
    };

/// "lần cuối online": giờ:phút hôm nay, hoặc ngày giờ.
String rcLastSeenText(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
  return sameDay ? hm : '$hm ${two(t.day)}/${two(t.month)}/${t.year}';
}

/// Trang "Máy tính" (tab Bạn › Công việc): các máy tính đang đăng nhập bằng tài khoản của mình. Máy đang online ở
/// trên (bấm để điều khiển ngay, không hỏi ai vì cùng tài khoản; máy kia vẫn hiện thanh đỏ "Dừng"), máy ngoại tuyến
/// mờ ở dưới kèm lần cuối online (nhấn giữ / menu để xoá khỏi danh sách). [load] / [forget] / [onOpen] thay được khi
/// kiểm thử.
class RcDevicesPage extends StatefulWidget {
  final Future<List<RcDevice>?> Function()? load;
  final Future<List<RcDevice>?> Function(String deviceId)? forget;
  final void Function(RcDevice d)? onOpen;
  /// Tự tải lại (thấy máy mới online / vừa tắt).
  final Duration refresh;
  const RcDevicesPage({super.key, this.load, this.forget, this.onOpen, this.refresh = const Duration(seconds: 5)});
  @override
  State<RcDevicesPage> createState() => _RcDevicesPageState();
}

class _RcDevicesPageState extends State<RcDevicesPage> {
  final _svc = RemoteControlService.instance;
  List<RcDevice>? _list;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _svc.holdDevices(true);
    _reload();
    _timer = Timer.periodic(widget.refresh, (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _svc.holdDevices(false);
    super.dispose();
  }

  Future<void> _reload() async {
    final l = await (widget.load ?? _svc.myDevices)();
    if (!mounted) return;
    setState(() {
      if (l != null) _list = l;
      _failed = l == null && _list == null;
    });
  }

  void _open(RcDevice d) {
    if (d.self) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!d.online) {
      messenger?.showSnackBar(toast(Text(tr('Máy đang ngoại tuyến'))));
      return;
    }
    if (d.busy) {
      messenger?.showSnackBar(toast(Text(tr('Máy kia đang trong một phiên điều khiển khác'))));
      return;
    }
    (widget.onOpen ?? _svc.requestOwn)(d);
  }

  Future<void> _forget(RcDevice d) async {
    final l = await (widget.forget ?? _svc.forgetDevice)(d.deviceId);
    if (mounted && l != null) setState(() => _list = l);
  }

  Future<void> _menu(RcDevice d) async {
    if (d.online || d.deviceId.isEmpty) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline, color: Color(0xFFE5484D)),
          title: Text(tr('Xoá khỏi danh sách'), style: const TextStyle(color: Color(0xFFE5484D))),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (ok == true) await _forget(d);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final list = _list;
    Widget body;
    if (list == null) {
      body = Center(
        child: _failed
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Không tải được danh sách máy tính. Máy chủ chat này có thể chưa hỗ trợ điều khiển máy tính.'),
                    textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
              )
            : const CircularProgressIndicator(),
      );
    } else if (list.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('Chưa có máy tính nào của bạn. Mở app trên máy tính Windows, macOS hoặc Linux và đăng nhập bằng tài khoản này.'),
              textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(tr('Bấm vào một máy đang trực tuyến để điều khiển. Máy đó vẫn hiện thanh đỏ để dừng bất cứ lúc nào.'),
                style: TextStyle(color: pal.sub, fontSize: 13)),
          ),
          for (final d in list) _row(d, pal),
        ]),
      );
    }
    return body;
  }

  Widget _row(RcDevice d, Pal pal) {
    final dim = !d.online;
    final name = d.name.isEmpty ? rcPlatformName(d.platform) : d.name;
    final info = [rcPlatformName(d.platform), if (d.version.isNotEmpty) buildLabel(d.version)].join(' · ');
    final status = d.self
        ? tr('Máy này')
        : !d.online
            ? '${tr('Ngoại tuyến')} · ${tr('lần cuối online: {0}', [d.lastSeen == null ? '—' : rcLastSeenText(d.lastSeen!)])}'
            : d.busy
                ? tr('Đang trong một phiên điều khiển')
                : tr('Trực tuyến');
    final dot = d.online ? const Color(0xFF34C759) : pal.sub.withValues(alpha: .5);
    return Opacity(
      opacity: dim ? .55 : 1,
      child: ListTile(
        key: ValueKey('rc-dev-${d.deviceId}-${d.cid}'),
        leading: Stack(clipBehavior: Clip.none, children: [
          Icon(rcPlatformIcon(d.platform), size: 32, color: pal.text),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: pal.bg, width: 2)),
            ),
          ),
        ]),
        title: Row(children: [
          Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (d.self) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: pal.accent.withValues(alpha: .15), borderRadius: BorderRadius.circular(6)),
              child: Text(tr('Máy này'), style: TextStyle(color: pal.accentText, fontSize: 11.5)),
            ),
          ],
        ]),
        subtitle: Text('$info\n$status', style: TextStyle(color: pal.sub, fontSize: 12.5, height: 1.35)),
        isThreeLine: true,
        trailing: !d.online && !d.self && d.deviceId.isNotEmpty
            ? IconButton(tooltip: tr('Thêm'), icon: Icon(Icons.more_vert, color: pal.sub), onPressed: () => _menu(d))
            : d.canControl
                ? Icon(Icons.chevron_right, color: pal.sub)
                : null,
        onTap: d.self ? null : () => _open(d),
        onLongPress: () => _menu(d),
      ),
    );
  }
}
