// Màn hình cuộc gọi 1-1 kiểu WhatsApp (tin riêng giữa hai người; gọi nhóm / cuộc họp vẫn dùng giao diện họp
// trong call_screen.dart).
//   - Gọi thoại: ảnh đại diện lớn, tên, trạng thái (Đang gọi… / Đang đổ chuông… / mm:ss), các nút tròn ở dưới.
//   - Gọi video: hình người kia cả màn hình, hình mình nhỏ ở góc (kéo đi được, bấm để đổi chỗ), chạm để ẩn / hiện nút.
//   - Bật / tắt camera bất cứ lúc nào ở cả hai bên: bố cục tự đổi (không ai bật camera thì về ảnh đại diện).
// Kèm thông báo cuộc gọi đến gọn trên máy tính (IncomingCallToast).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../calls/call_service.dart';
import '../calls/direct_call.dart';
import '../config.dart';
import '../i18n/i18n.dart';
import '../remote/rc_call_buttons.dart';
import '../state/app_state.dart';
import 'call_screen.dart' show CallVideo, ReconnectingChip, ScreenPicker;
import 'common.dart';
import 'self_view.dart';
import 'theme.dart';

const _red = Color(0xFFF15C6D);
const _green = Color(0xFF25D366);

/// Màu chữ / nút theo nền: nền video luôn tối; gọi thoại theo giao diện sáng / tối của app.
class _Look {
  final Color fg, sub, btn, btnOn, iconOn;
  const _Look({required this.fg, required this.sub, required this.btn, required this.btnOn, required this.iconOn});

  static const video = _Look(
    fg: Colors.white,
    sub: Color(0xFFD1D7DB),
    btn: Color(0x66000000),
    btnOn: Colors.white,
    iconOn: Colors.black,
  );

  factory _Look.of(Pal pal) => _Look(
        fg: pal.text,
        sub: pal.sub,
        btn: pal.text.withValues(alpha: .10),
        btnOn: pal.text,
        iconOn: pal.bg,
      );
}

/// Trạng thái hiện dưới tên (Đang gọi… / Đang đổ chuông… / 3:21 / lý do kết thúc).
String directStatusText(CallService call, String peerName) {
  final d = call.direct;
  if (d == null) return '';
  if (call.phase == CallPhase.ended || d.isEnded) return call.endReason ?? tr('Cuộc gọi đã kết thúc');
  if (call.phase == CallPhase.incoming) return d.incomingVideo ? tr('Cuộc gọi video đến') : tr('Cuộc gọi thoại đến');
  if (call.reconnecting) return tr('Đang kết nối lại…');
  return switch (d.status) {
    DirectStatus.calling => tr('Đang gọi…'),
    DirectStatus.ringing => tr('Đang đổ chuông…'),
    DirectStatus.incoming || DirectStatus.connecting => tr('Đang kết nối…'),
    DirectStatus.active => d.waitingPeer
        ? tr('Đang chờ {0} kết nối lại…', [peerName])
        : callClock(DateTime.now().difference(d.talkingSince ?? call.startedAt ?? DateTime.now())),
    DirectStatus.ended => call.endReason ?? '',
  };
}

class DirectCallView extends StatefulWidget {
  const DirectCallView({super.key});
  @override
  State<DirectCallView> createState() => _DirectCallViewState();
}

class _DirectCallViewState extends State<DirectCallView> {
  Timer? _tick;
  Timer? _hide;
  bool _controls = true;
  /// Hình nhỏ đang là hình người kia (bấm vào hình nhỏ để đổi chỗ).
  bool _swap = false;
  /// Vị trí hình nhỏ (góc trên trái, tính trong khung); null = góc dưới phải mặc định.
  DirectLayout? _lastLayout;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  /// Hiện nút; gọi video trên điện thoại thì tự ẩn sau vài giây.
  void _poke({bool autoHide = true}) {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    if (isDesktop || !autoHide) return;
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    if (_controls) {
      _hide?.cancel();
      setState(() => _controls = false);
    } else {
      _poke();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final call = app.calls;
    final d = call.direct;
    final pal = Pal.of(context);
    if (d == null) return Scaffold(backgroundColor: pal.bg);
    final ch = call.channelId == null ? null : app.channels[call.channelId];
    final otherId = ch?.otherUserId(app.me?.id ?? '');
    final name = ch == null ? '' : app.channelTitle(ch);
    final peer = call.peer;
    final remoteScreen = peer?.hasScreen == true;
    final remoteCam = peer?.hasVideo == true;
    final localCam = call.camera && call.localVideo != null;
    final layout = directLayout(localVideo: localCam, remoteVideo: remoteCam, remoteScreen: remoteScreen);
    final incoming = call.phase == CallPhase.incoming;
    final ended = call.phase == CallPhase.ended || d.isEnded;
    final video = layout != DirectLayout.voice;
    // Vừa đổi sang / khỏi giao diện video: hiện nút (video thì tự ẩn sau vài giây), về gọi thoại thì luôn hiện.
    if (layout != _lastLayout) {
      _lastLayout = layout;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!video) _swap = false;
        _poke(autoHide: video && call.phase == CallPhase.active);
      });
    }
    final look = video ? _Look.video : _Look.of(pal);
    final status = directStatusText(call, name);
    final show = _controls || !video || incoming || ended;

    // Hình lớn và hình nhỏ.
    final remoteStream = remoteScreen ? peer!.screenStream : (remoteCam ? peer!.videoStream : null);
    final remoteTrack = remoteScreen ? peer!.screenTrackId : peer?.videoTrackId;
    Widget remoteView() => CallVideo(
          key: ValueKey('remote:${remoteScreen ? 's' : 'v'}:$remoteTrack'),
          stream: remoteStream!,
          trackId: remoteTrack,
          contain: remoteScreen || isDesktop,
        );
    Widget localView() => CallVideo(key: const ValueKey('local'), stream: call.localVideo!, mirror: true);
    Widget? main;
    Widget? small;
    if (layout == DirectLayout.remote) {
      main = remoteView();
      if (localCam) small = localView();
      if (_swap && small != null) (main, small) = (small, main);
    } else if (layout == DirectLayout.local) {
      // Đang đổ chuông: camera của mình xem trước cả màn hình. Đã nói chuyện (người kia tắt camera): hình của mình thành
      // hình nhỏ kéo đi được, ảnh người kia ở giữa.
      if (call.phase == CallPhase.active) {
        small = localView();
      } else {
        main = localView();
      }
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: video ? Colors.black : pal.bg,
      body: Stack(children: [
        // Nền.
        if (main != null)
          Positioned.fill(child: ColoredBox(color: Colors.black, child: main))
        else
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? const [Color(0xFF1F2C34), Color(0xFF0B141A)]
                      : [Color.alphaBlend(pal.accent.withValues(alpha: .10), pal.bg), pal.bg],
                ),
              ),
            ),
          ),
        // Chạm để ẩn / hiện nút (chỉ khi có video).
        if (video && !incoming && !ended)
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _toggleControls)),
        // Gọi video: viền tối trên / dưới để chữ và nút dễ đọc.
        if (video)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Colors.transparent, Colors.transparent, Color(0xAA000000)],
                      stops: [0, .22, .7, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight;
            final pipW = isDesktop || wide ? 240.0 : 108.0;
            final pipH = isDesktop || wide ? 135.0 : 160.0;
            final bottomGap = show ? 132.0 : 16.0;
            return Stack(children: [
              // Tên + trạng thái: gọi thoại ở giữa (ảnh lớn), gọi video ở trên cùng.
              if (layout == DirectLayout.remote)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: _fade(show, _header(app, look, name, status, peer, small: true)),
                )
              else
                Positioned.fill(
                  bottom: 140,
                  child: IgnorePointer(
                    ignoring: video,
                    child: _fade(show || !video, _center(app, look, otherId, name, status, peer)),
                  ),
                ),
              if (call.reconnecting && !ended)
                Positioned(top: layout == DirectLayout.remote ? 64 : 12, left: 0, right: 0, child: const Center(child: ReconnectingChip())),
              if (call.localScreen != null && !ended)
                Positioned(
                  top: layout == DirectLayout.remote ? 64 : 12,
                  left: 0,
                  right: 0,
                  child: Center(child: _sharingChip(call)),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _fade(show, _bottom(app, call, d, look, incoming: incoming, ended: ended, video: video)),
              ),
              // Hình nhỏ của mình (hoặc người kia khi đã đổi chỗ): kéo đi khắp màn hình, bấm để đổi chỗ; hình của mình kéo
              // xuống nút xoá ở đáy là tắt camera.
              if (small != null)
                DraggablePip(
                  key: const ValueKey('pip'),
                  width: pipW,
                  height: pipH,
                  bottomGap: bottomGap,
                  onTap: layout == DirectLayout.remote ? () => setState(() => _swap = !_swap) : null,
                  onRemove: _swap && layout == DirectLayout.remote ? null : () => call.toggleCamera(),
                  child: ColoredBox(color: const Color(0xFF1F2C34), child: small),
                ),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _fade(bool show, Widget child) => IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(opacity: show ? 1 : 0, duration: const Duration(milliseconds: 200), child: child),
      );

  Widget _header(AppState app, _Look look, String name, String status, CallParticipant? peer, {bool small = false}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: look.fg, fontSize: small ? 18 : 28, fontWeight: FontWeight.w600)),
          SizedBox(height: small ? 2 : 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (peer != null && !peer.unmuted && app.calls.phase == CallPhase.active) ...[
              Icon(Icons.mic_off, size: small ? 14 : 16, color: look.sub),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: look.sub, fontSize: small ? 13.5 : 16.5, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
        ],
      );

  Widget _center(AppState app, _Look look, String? otherId, String name, String status, CallParticipant? peer) =>
      Column(children: [
        const SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline, size: 14, color: look.sub),
          const SizedBox(width: 6),
          Text(tr('Cuộc gọi nội bộ Flygo Chat'), style: TextStyle(color: look.sub, fontSize: 13)),
        ]),
        const Spacer(),
        Avatar(userId: otherId, name: name, size: 128, status: false),
        const SizedBox(height: 22),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: _header(app, look, name, status, peer)),
        const Spacer(flex: 2),
      ]);

  Widget _sharingChip(CallService call) => Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(color: const Color(0xE6302F33), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.present_to_all, color: Color(0xFF8AB4F8), size: 18),
          const SizedBox(width: 8),
          Text(tr('Bạn đang chia sẻ màn hình'), style: const TextStyle(color: Colors.white, fontSize: 13.5)),
          const SizedBox(width: 6),
          TextButton(onPressed: call.stopScreenShare, child: Text(tr('Dừng'))),
        ]),
      );

  // ---------------------------------------------------------------- nút

  Widget _bottom(AppState app, CallService call, DirectCall d, _Look look,
      {required bool incoming, required bool ended, required bool video}) {
    if (ended) return const SizedBox(height: 120);
    if (incoming) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _CallButton(icon: Icons.call_end, color: _red, iconColor: Colors.white, label: tr('Từ chối'), labelColor: look.fg, size: 68, onTap: call.decline),
          // Gọi thoại đến: trả lời bằng video được; gọi video đến: chỉ nghe (không bật camera).
          d.incomingVideo
              ? _CallButton(
                  icon: Icons.call,
                  color: look.btn,
                  iconColor: look.fg,
                  label: tr('Chỉ thoại'),
                  labelColor: look.fg,
                  size: 68,
                  onTap: () => call.accept(video: false))
              : _CallButton(
                  icon: Icons.videocam,
                  color: look.btn,
                  iconColor: look.fg,
                  label: tr('Video'),
                  labelColor: look.fg,
                  size: 68,
                  onTap: () => call.accept(video: true)),
          _CallButton(
              icon: d.incomingVideo ? Icons.videocam : Icons.call,
              color: _green,
              iconColor: Colors.white,
              label: tr('Nghe máy'),
              labelColor: look.fg,
              size: 68,
              onTap: () => call.accept()),
        ]),
      );
    }
    final mobile = !isDesktop;
    void poke() => _poke(autoHide: video);
    final buttons = <Widget>[
      _CallButton(icon: Icons.more_horiz_rounded, color: look.btn, iconColor: look.fg, tooltip: tr('Thêm'), onTap: () => _more(app, call)),
      if (mobile && video && call.camera)
        _CallButton(
          icon: Icons.cameraswitch_outlined,
          color: look.btn,
          iconColor: look.fg,
          tooltip: tr('Đổi camera'),
          onTap: () {
            call.switchCamera();
            poke();
          },
        ),
      if (mobile && !video)
        _CallButton(
          icon: call.speaker ? Icons.volume_up : Icons.volume_down_outlined,
          color: call.speaker ? look.btnOn : look.btn,
          iconColor: call.speaker ? look.iconOn : look.fg,
          tooltip: tr('Loa ngoài'),
          onTap: () {
            call.toggleSpeaker();
            poke();
          },
        ),
      _CallButton(
        icon: call.camera ? Icons.videocam : Icons.videocam_off_outlined,
        color: call.camera ? look.btnOn : look.btn,
        iconColor: call.camera ? look.iconOn : look.fg,
        tooltip: call.camera ? tr('Tắt camera') : tr('Bật camera'),
        onTap: () {
          call.toggleCamera();
          poke();
        },
      ),
      _CallButton(
        icon: call.muted ? Icons.mic_off : Icons.mic_none,
        color: call.muted ? look.btnOn : look.btn,
        iconColor: call.muted ? look.iconOn : look.fg,
        tooltip: call.muted ? tr('Bật micro') : tr('Tắt micro'),
        onTap: () {
          call.toggleMute();
          poke();
        },
      ),
      if (CallService.canShareScreen && call.phase == CallPhase.active)
        _CallButton(
          icon: call.localScreen != null ? Icons.stop_screen_share_outlined : Icons.present_to_all,
          color: call.localScreen != null ? look.btnOn : look.btn,
          iconColor: call.localScreen != null ? look.iconOn : look.fg,
          tooltip: call.localScreen != null ? tr('Dừng chia sẻ màn hình') : tr('Chia sẻ màn hình'),
          onTap: () => _toggleShare(call),
        ),
      _CallButton(icon: Icons.call_end, color: _red, iconColor: Colors.white, tooltip: tr('Kết thúc'), onTap: () => call.hangUp()),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: video ? const Color(0x99151B1F) : look.btn.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(36),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final b in buttons) Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: b),
            ]),
          ),
        ),
      ),
    );
  }

  /// "⋯": chia sẻ màn hình (máy tính), điều khiển máy tính (lib/remote/rc_call_buttons.dart), loa ngoài khi đang video.
  Future<void> _more(AppState app, CallService call) async {
    _hide?.cancel();
    final pal = Pal.of(context);
    final rc = rcCallActions(app, call);
    final video = call.camera || call.peer?.hasVideo == true;
    final a = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: pal.surface,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isDesktop && video)
            ListTile(
              leading: Icon(call.speaker ? Icons.volume_up : Icons.phone_in_talk, color: pal.text),
              title: Text(call.speaker ? tr('Tắt loa ngoài') : tr('Bật loa ngoài'), style: TextStyle(color: pal.text)),
              onTap: () => Navigator.pop(ctx, 'speaker'),
            ),
          if (CallService.canShareScreen && call.phase == CallPhase.active)
            ListTile(
              leading: Icon(call.localScreen != null ? Icons.stop_screen_share_outlined : Icons.present_to_all, color: pal.text),
              title: Text(call.localScreen != null ? tr('Dừng chia sẻ màn hình') : tr('Chia sẻ màn hình'), style: TextStyle(color: pal.text)),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
          for (final r in rc)
            ListTile(
              leading: Icon(r.icon, color: r.on ? pal.accentText : pal.text),
              title: Text(r.label, style: TextStyle(color: pal.text)),
              onTap: () => Navigator.pop(ctx, r.id),
            ),
          if (rc.isEmpty && !(CallService.canShareScreen && call.phase == CallPhase.active) && !(!isDesktop && video))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text(tr('Chưa có thêm tuỳ chọn khi đang đổ chuông'), style: TextStyle(color: pal.sub)),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || a == null) return;
    switch (a) {
      case 'speaker':
        await call.toggleSpeaker();
      case 'share':
        await _toggleShare(call);
      default:
        await runRcCallAction(context, app, call, a);
    }
  }

  Future<void> _toggleShare(CallService call) async {
    if (call.localScreen != null) {
      await call.stopScreenShare();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final id = await showDialog<String>(context: context, builder: (_) => const ScreenPicker());
    if (id == null || !mounted) return;
    final err = await call.startScreenShare(id);
    if (err != null) messenger.showSnackBar(toast(Text(err)));
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String? label;
  final Color? labelColor;
  final String? tooltip;
  final VoidCallback onTap;
  final double size;
  const _CallButton({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onTap,
    this.label,
    this.labelColor,
    this.tooltip,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    Widget b = Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, color: iconColor, size: size * .46)),
      ),
    );
    if (tooltip != null) b = Tooltip(message: tooltip!, child: b);
    if (label == null) return b;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      b,
      const SizedBox(height: 8),
      Text(label!, style: TextStyle(color: labelColor, fontSize: 14)),
    ]);
  }
}

// ---------------------------------------------------------------- cuộc gọi đến trên máy tính

/// Thông báo cuộc gọi đến gọn ở góc trên phải cửa sổ (máy tính): Từ chối / Nghe máy / Nghe bằng video.
/// Nghe máy thì [onAccepted] mở màn hình cuộc gọi.
class IncomingCallToast extends StatelessWidget {
  final AppState app;
  final VoidCallback onAccepted;
  const IncomingCallToast({super.key, required this.app, required this.onAccepted});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final call = app.calls;
    final ch = call.channelId == null ? null : app.channels[call.channelId];
    final direct = call.direct != null;
    final otherId = direct ? ch?.otherUserId(app.me?.id ?? '') : null;
    final title = ch == null ? '' : app.channelTitle(ch);
    final caller = app.users[call.callerId ?? '']?.displayName ?? '';
    final video = call.direct?.incomingVideo ?? call.incomingVideo;
    final sub = direct
        ? (video ? tr('Cuộc gọi video đến') : tr('Cuộc gọi thoại đến'))
        : (video ? tr('{0} đang gọi video nhóm', [caller]) : tr('{0} đang gọi thoại nhóm', [caller]));
    Future<void> accept({bool? video}) async {
      onAccepted();
      await call.accept(video: video);
    }

    Widget btn(IconData icon, Color bg, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 22)),
            ),
          ),
        );
    return Material(
      elevation: 12,
      color: pal.surface,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.divider)),
        child: Row(children: [
          Avatar(userId: otherId, name: title, size: 46, icon: otherId == null ? Icons.groups : null, channel: ch, status: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.sub, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 8),
          btn(Icons.call_end, _red, tr('Từ chối'), call.decline),
          const SizedBox(width: 8),
          btn(Icons.videocam, const Color(0xFF1A73E8), tr('Nghe bằng video'), () => accept(video: true)),
          const SizedBox(width: 8),
          btn(Icons.call, _green, tr('Nghe máy'), () => accept()),
        ]),
      ),
    );
  }
}
