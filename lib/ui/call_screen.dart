import '../i18n/i18n.dart';
import 'theme.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'meet_overlay.dart';
import 'ai_panel.dart';
import '../calls/meet_room.dart';
import '../calls/meet_rooms.dart';
import 'meet/meet_home.dart' show MeetLinkBox, meetToast;
import 'meet/meet_qr_invite.dart';
import 'meet/meet_summary.dart';
import 'meet/extras/actions.dart';
import 'meet/extras/controls.dart';
import 'meet/extras/fx_api.dart' show fxRequest;
import 'meet/extras/network.dart' show MeetSignalBadge;
import 'meet/extras/captions.dart';
import 'meet/meet_present.dart';
import 'meet/extras/guest_invite.dart' show meetGuestInvite;
import 'cast/cast_screen.dart' show addScreenToMeeting;
import 'app_route.dart';
import 'chat_page.dart' show ChatPage;
import 'home_page.dart' show ChatHost;
import 'meet/extras/hands.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../calls/call_service.dart';
import '../config.dart';
import '../data/models.dart' show MmChannel, MmUser;
import '../state/app_state.dart';
import 'common.dart';
import 'direct_call_screen.dart';
import 'meet/meet_panel_prefs.dart';
import 'pages/pages_sheet.dart';
import 'poll.dart';
import 'self_view.dart';

// Bảng màu kiểu Google Meet.
const _meetBg = Color(0xFF15171C);
const _tileBg = Color(0xFF3C4043);
const _btnBg = Color(0xFF353A43);
const _red = Color(0xFFE5484D);
const _blue = Color(0xFF4C9BFF);
/// Nút đang bật (phụ đề, trình bày, cột bên phải) và chữ / biểu tượng trên nó.
const _on = Color(0xFFA9CCFF);
const _onText = Color(0xFF0B2A55);
/// Nền cột bên phải, menu, bảng dưới trong cuộc họp.
const _panelBg = Color(0xFF1F2228);

/// Cột bên phải của cuộc họp (máy tính).
enum _MeetPanel { none, pages, people, screens, chat, info, ai }

/// Bố cục ô video của cuộc họp.
enum MeetLayout {
  auto(Icons.auto_awesome_mosaic_outlined, 'Ai trình chiếu lên đầu (mặc định)', 'Có người chia sẻ màn hình / trình chiếu tài liệu thì lên khung lớn (mới nhất trước); không ai trình chiếu thì lưới.'),
  grid(Icons.grid_view_rounded, 'Lưới', 'Mọi người bằng nhau.'),
  sidebar(Icons.view_sidebar_outlined, 'Thanh bên', 'Người đang nói ở ô lớn, người khác ở dải bên cạnh.'),
  spotlight(Icons.crop_square_rounded, 'Tiêu điểm', 'Chỉ người đang nói / đang trình bày.');

  final IconData icon;
  final String _label, _hint;
  const MeetLayout(this.icon, this._label, this._hint);
  String get label => tr(_label);
  String get hint => tr(_hint);
}
const _grey = Color(0xFF9AA0A6);

/// Màn hình cuộc gọi. Lúc đổ chuông / đang gọi / đã kết thúc: kiểu WhatsApp (ảnh lớn, nút tròn).
/// Khi đã vào cuộc gọi: kiểu Google Meet (lưới ô cho mọi người, ghim, thanh nút ở dưới).
class CallScreen extends StatefulWidget {
  /// Số màn hình cuộc gọi đang mở (0 = đã rời màn hình nhưng có thể vẫn đang họp: hiện khung nổi PiP).
  static final visible = ValueNotifier<int>(0);
  const CallScreen({super.key});
  /// Kiểm thử / ảnh xem trước: phòng họp giả thay cho phòng nối trạm thật.
  @visibleForTesting
  static MeetRoom Function(String channelId)? debugRoom;
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _tick;
  Timer? _hide;
  bool _popped = false;
  bool _usersLoaded = false;
  /// Ô đang ghim (null = không ghim). Chia sẻ màn hình tự ghim trừ khi đã bỏ ghim nó.
  String? _pinned;
  String? _dismissedScreen;
  /// Cuộc họp LiveKit: máy này đang theo bố cục của phòng (chủ trì / phó phòng đặt); tự đổi cách xem thì thôi theo.
  bool _followRoom = true;
  String _roomLayoutSeen = '';
  /// Khung lớn đang phóng to (ẩn dải người) — bấm khung lớn để bật / tắt.
  bool _stageFull = false;
  /// Lúc thấy mỗi màn hình chia sẻ lần đầu: màn hình mới nhất lên khung lớn.
  final Map<String, int> _screenSeen = {};
  bool _controls = true;
  CallPhase? _lastPhase;
  /// Phòng họp (bình luận, tắt tiếng, web chia sẻ, sân khấu của trợ lý AI…) của cuộc gọi đang mở.
  MeetRoom? _room;
  /// Máy tính: tab đang mở của panel bên phải cuộc họp (trang, tin nhắn, trợ lý AI, mọi người, thông tin); none = thu gọn.
  _MeetPanel _panel = _MeetPanel.none;
  /// Độ rộng panel bên phải (kéo mép trái để đổi; nhớ qua các lần họp, xem meet_panel_prefs.dart).
  double _panelW = MeetPanelPrefs.width;
  /// Trang hệ thống "Video tự động": người đang nói đang lên lớn và lúc lên (giữ ít nhất 3 giây, không nhảy liên tục).
  String? _sysSpeaker;
  int _sysSpeakerAt = 0;
  /// Lúc từng ô bắt đầu có hình (trang "Chủ phòng": ai mới bật camera đứng đầu dải).
  final Map<String, int> _camOnAt = {};
  /// Bề rộng thật của màn họp (có thể nhỏ hơn cửa sổ khi app có thanh bên).
  double _screenW = 0;
  /// Bề rộng thanh nút (vùng họp bên trái panel), ghi lại khi dựng thanh nút; quyết định một hay hai hàng nút.
  double _stageW = 0;
  bool get _barTwoRows => _twoRowBar(_stageW > 0 ? _stageW : _screenW);
  /// Bố cục của cuộc họp (Tự động / Lưới / Thanh bên / Tiêu điểm).
  MeetLayout _layout = MeetLayout.auto;
  /// Hiện phụ đề (lời trợ lý AI) trên màn hình.
  bool _captions = true;
  /// Người nói gần nhất (bố cục Thanh bên / Tiêu điểm giữ người này ở ô lớn đến khi người khác nói).
  String? _lastSpeaker;
  /// Đã báo "Cuộc họp của bạn đã sẵn sàng" (người tạo vào một mình).
  bool _readyShown = false;
  StreamSubscription<MeetAsk>? _asks;

  void _ensureRoom(AppState app, CallService call) {
    final ch = call.channelId;
    if (ch == null || app.me == null || call.phase != CallPhase.active) return;
    // Chỉ cuộc họp có phòng họp (bình luận, trình chiếu, giơ tay, AI…); gọi 1-1 / gọi nhóm thì không.
    if (!call.meeting) return;
    if (_room?.channelId == ch) return;
    _disposeRoom();
    if (CallScreen.debugRoom != null) {
      _room = CallScreen.debugRoom!(ch)..addListener(_onRoom);
      return;
    }
    final room = MeetRoom(
      channelId: ch,
      token: app.token,
      server: kServerUrl,
      myId: app.me!.id,
      onMuteMe: () {
        if (!call.muted) call.toggleMute();
      },
      onLowerHandMe: call.lowerHand,
      // Luồng bình luận = tin cuộc họp của Calls ("Cuộc họp đang diễn ra / đã kết thúc"); không lấy được thì
      // tạo tin "Cuộc họp mới" (luồng riêng công khai). Người mở cuộc họp chốt luồng ngay khi vào phòng.
      starter: call.callerId == app.me!.id && app.channels[ch]?.isDirect != true,
      // [text] rỗng = chỉ tạo tin gốc.
      persistComment: (text, root) async {
        var r = root ?? await call.threadIdOf();
        if (r == null) {
          final now = DateTime.now();
          final head = await app.send(ch, '📅 ${tr('Cuộc họp mới')} · ${hhmm(now)} ${ddmmyyyy(now)}',
              props: {'flygo_open_thread': true, 'flygo_silent': true, 'flygo_meet_thread': true});
          r = head?.id;
          if (r == null) return (null, null);
        }
        if (text.isEmpty) return (r, null);
        final p = await app.send(ch, text, rootId: r, replyKind: 'thread', props: {'flygo_meet_comment': true, 'flygo_silent': true});
        return (r, p?.id);
      },
    );
    room.addListener(_onRoom);
    _asks = room.asks.stream.listen((a) => _onAsk(call, a));
    _room = room;
    if (call.deafened) room.setSilent(true);
  }

  void _onRoom() {
    if (mounted) setState(() {});
  }

  void _disposeRoom() {
    _asks?.cancel();
    _room?.removeListener(_onRoom);
    _room?.dispose();
    _room = null;
  }

  /// Chủ phòng / trợ lý mời mình bật mic hoặc chia sẻ màn hình (hệ điều hành bắt người dùng đồng ý).
  Future<void> _onAsk(CallService call, MeetAsk a) async {
    if (!mounted) return;
    final mic = a.kind == 'unmute_request';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(mic ? tr('{0} mời bạn bật mic', [a.from]) : tr('{0} mời bạn chia sẻ màn hình', [a.from])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Để sau'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(mic ? tr('Bật mic') : tr('Chia sẻ'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (mic) {
      if (call.muted) call.toggleMute();
    } else if (CallService.canShareScreen && call.localScreen == null) {
      await _toggleShare(call);
    }
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _poke();
    CallScreen.visible.value++;
    // Tính năng thêm (meet/extras): nghe sự kiện của cuộc họp để báo nhanh (vd. "X đã hạ tay bạn").
    final call = context.read<AppState>().calls;
    _extrasCall = call;
    // Máy tính: panel bên phải nhớ độ rộng và tab mở gần nhất (cuộc họp có Trang họp mở lại tab đó).
    if (isDesktop) {
      MeetPanelPrefs.load().then((_) {
        if (!mounted) return;
        setState(() {
          _panelW = MeetPanelPrefs.width;
          final last = _MeetPanel.values.where((p) => p.name == MeetPanelPrefs.tab).firstOrNull;
          if (_panel == _MeetPanel.none && last != null && last != _MeetPanel.none && call.meeting && call.scribeAvailable && _screenW >= 1000) {
            _panel = last;
          }
        });
      });
    }
    // Sau khung hình đầu: module thêm đọc ScaffoldMessenger (không được gọi trong initState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      meetExtrasAttach(context, call, (t) {
        if (mounted) meetToast(context, t);
      });
    });
  }

  CallService? _extrasCall;

  @override
  void dispose() {
    _tick?.cancel();
    _hide?.cancel();
    _disposeRoom();
    final xc = _extrasCall;
    if (xc != null) meetExtrasDetach(xc);
    // Sau khung hình này: tránh đổi notifier khi cây đang dựng lại.
    WidgetsBinding.instance.addPostFrameCallback((_) => CallScreen.visible.value = (CallScreen.visible.value - 1).clamp(0, 99));
    super.dispose();
  }

  /// Hai nút mời chính (LiveKit): 📺 Thêm màn hình (TV / máy dùng chung quét QR, theo bố cục màn hình phòng) và
  /// 🔗 Thêm khách mời (link khách, theo bố cục ứng dụng & khách; chủ trì / phó phòng, cuộc họp có mã).
  List<Widget> _inviteButtons(CallService call) {
    if (!call.liveKit) return const [];
    final guest = call.canModerate && (call.meetingInfo?.code ?? '').isNotEmpty;
    final style = OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), minimumSize: const Size(0, 40));
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: style,
              onPressed: () => _addScreen(call),
              icon: const Icon(Icons.cast_rounded, size: 18),
              label: Text(tr('Thêm màn hình')),
            ),
          ),
          if (guest) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: style,
                onPressed: () => meetGuestInvite(context, call),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(tr('Thêm khách mời')),
              ),
            ),
          ],
        ]),
      ),
    ];
  }

  /// 📺 Thêm màn hình: màn hình hello (danh sách màn hình của công ty, quét / gõ mã). TV còn mở trang meet. cũ (mã 12 ký
  /// tự) thì dùng "Mã cũ" ở cuối danh sách.
  Future<void> _addScreen(CallService call) async {
    final ok = await addScreenToMeeting(context, code: call.meetingInfo?.code, channelId: call.channelId);
    if (ok || !mounted) return;
    final old = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('TV đang hiện mã QR kiểu cũ?')),
        content: Text(tr('TV mở trang meet. (mã 12 ký tự) thì dùng cách mời cũ.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Đóng'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Quét mã cũ'))),
        ],
      ),
    );
    if (old == true && mounted) await inviteDeviceByQr(context, call);
  }

  List<String> _banners(AppState app, CallService call) {
    final x = call.roomExtras, perms = x['perms'] is Map ? x['perms'] as Map : const {};
    final st = call.roomStars;
    return [
      if (x['lock'] == true) tr('🔒 Cuộc họp đã khoá'),
      if (perms['unmute'] == false) tr('🔇 Chủ trì đã bật im lặng toàn bộ'),
      if (perms['camera'] == false) tr('📷 Chủ trì đã tắt cam toàn bộ'),
      if (st.isNotEmpty) tr('★ Chỉ {0} được trình chiếu', [st.map((id) => id == app.me?.id ? tr('bạn') : _nameOf(app, id)).join(', ')]),
    ];
  }

  /// Bật / tắt mic: chủ trì tắt quyền tự bật mic thì nhắc giơ tay (chủ trì "mời bật mic" sẽ mở lại).
  void _micTap(CallService call) {
    if (call.muted && !meetPerm(call, 'unmute')) {
      meetToast(context, tr('Chủ trì đang tắt quyền tự bật mic – hãy giơ tay'));
      return;
    }
    call.toggleMute();
  }

  void _camTap(CallService call) {
    if (!call.camera && !meetPerm(call, 'camera')) {
      meetToast(context, tr('Chủ trì đang tắt quyền bật camera'));
      return;
    }
    call.toggleCamera();
  }

  /// Về chat của cuộc họp, cuộc gọi chạy tiếp trong khung nổi (PiP).
  void _backToChat(AppState app, CallService call) {
    final ch = call.channelId;
    final host = ChatHost.of(context);
    final nav = Navigator.of(context);
    nav.maybePop();
    if (ch == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (host != null) {
        host.openChat(ch);
      } else if (app.activeChannelId != ch) {
        nav.push(AppPageRoute(builder: (_) => ChatPage(channelId: ch)));
      }
    });
  }

  /// Hiện thanh nút; trên điện thoại tự ẩn sau vài giây.
  void _poke() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    if (isDesktop) return;
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    if (_controls && !isDesktop) {
      _hide?.cancel();
      setState(() => _controls = false);
    } else {
      _poke();
    }
  }

  /// Nạp tên / ảnh thành viên của cuộc trò chuyện để hiện trên các ô.
  void _loadUsers(AppState app, String? ch) {
    if (_usersLoaded || ch == null) return;
    _usersLoaded = true;
    app.channelUsers(ch).then((_) {
      if (mounted) setState(() {});
    });
  }

  String _duration(DateTime? s) {
    if (s == null) return '';
    final d = DateTime.now().difference(s);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$sec' : '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final call = app.calls;
    final ch = call.channelId == null ? null : app.channels[call.channelId];
    final meeting = call.meeting;
    if (call.phase == CallPhase.idle && !_popped) {
      _popped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    _loadUsers(app, call.channelId);
    // Gọi 1-1 (tin riêng, không phải cuộc họp): màn hình riêng kiểu WhatsApp.
    if (call.direct != null) return PopScope(canPop: !call.busy, child: const DirectCallView());
    _ensureRoom(app, call);
    // Vào cuộc gọi nhóm / cuộc họp: báo mic và camera đã tắt sẵn.
    if (call.autoMutedNotice && call.phase == CallPhase.active) {
      call.autoMutedNotice = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Row(children: [
            const Icon(Icons.mic_off, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            const Icon(Icons.videocam_off, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('Mic và camera đã được tắt tự động. Bấm nút mic / camera để bật khi cần.'))),
          ]),
        ));
      });
    }
    if (call.unmuteAsk != null && call.phase == CallPhase.active) {
      final by = call.unmuteAsk!;
      call.unmuteAsk = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _askUnmute(call, by) : null);
    }
    if (call.phase == CallPhase.active && call.scribePrompt && call.isMeetingCreator) {
      // Chủ phòng vào cuộc họp lần đầu: hỏi một lần có bật phiên âm tự động không (mặc định tắt).
      call.scribePrompt = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _askScribe(call) : null);
    }
    if (call.phase == CallPhase.active && call.presentOnJoin) {
      // Vào bằng nút "Trình bày" của phòng chờ: mở chọn màn hình ngay.
      call.presentOnJoin = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _toggleShare(call) : null);
    }
    if (call.phase == CallPhase.active && !_readyShown && call.isMeetingCreator && call.meetingInfo?.code != null && call.participants.isEmpty) {
      _readyShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _showReady(call) : null);
    }
    if (call.phase != _lastPhase) {
      // Vừa vào cuộc gọi: hiện thanh nút rồi mới tự ẩn.
      if (call.phase == CallPhase.active) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _poke() : null);
      _lastPhase = call.phase;
    }
    final title = ch == null ? '' : app.channelTitle(ch);
    final caller = call.callerId == null ? '' : _nameOf(app, call.callerId!);
    final status = switch (call.phase) {
      CallPhase.incoming => call.groupRing
          ? (call.incomingVideo ? tr('{0} đang gọi video nhóm', [caller]) : tr('{0} đang gọi thoại nhóm', [caller]))
          : (call.incomingVideo ? tr('Cuộc gọi video đến') : tr('Cuộc gọi thoại đến')),
      CallPhase.outgoing => call.reconnecting ? tr('Đang kết nối lại…') : tr('Đang đổ chuông...'),
      CallPhase.connecting => call.lockWaiting ? tr('Cuộc họp đã khoá – đang chờ chủ trì cho vào…') : tr('Đang kết nối...'),
      CallPhase.active =>
        call.remoteUsers.isEmpty && ch?.isDirect == false
            ? tr('Đang chờ mọi người...')
            : _duration(call.startedAt),
      CallPhase.ended => call.endReason ?? (meeting ? tr('Cuộc họp đã kết thúc') : tr('Cuộc gọi đã kết thúc')),
      CallPhase.idle => '',
    };

    // Thông báo (SnackBar) căn theo bề rộng của chính màn họp, không theo cả cửa sổ app.
    return CenteredToasts(
      child: LayoutBuilder(builder: (context, box) {
        _screenW = box.maxWidth;
        return _screen(app, call, ch, meeting, title, status);
      }),
    );
  }

  Widget _screen(AppState app, CallService call, MmChannel? ch, bool meeting, String title, String status) {
    return PopScope(
      // Họp / gọi nhóm: Back về chat, cuộc gọi chạy tiếp trong khung nổi (PiP). Gọi 1-1 giữ như cũ.
      canPop: !call.busy || call.direct == null,
      child: call.phase == CallPhase.active
          ? (isDesktop && _panel != _MeetPanel.none && call.channelId != null
              ? LayoutBuilder(builder: (context, box) {
                  // Luôn là một cột bên phải (không thành cửa sổ nổi): rộng tối đa 60% cửa sổ, sân khấu bên trái co giãn theo.
                  final maxW = (box.maxWidth * .6).clamp(240.0, 720.0);
                  final w = _panelW.clamp(240.0, maxW);
                  // Một panel có tab cho mọi thứ bên phải; mép trái kéo để đổi độ rộng.
                  final panel = SizedBox(
                    width: w + 8,
                    child: Row(children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) => setState(() => _panelW = (w - d.delta.dx).clamp(240.0, maxW)),
                          onHorizontalDragEnd: (_) => MeetPanelPrefs.save(width: _panelW),
                          child: const SizedBox(width: 8, child: Center(child: SizedBox(width: 3, height: 40, child: DecoratedBox(decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.all(Radius.circular(2))))))),
                        ),
                      ),
                      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(0, 12, 12, 12), child: _sidePanel(app, call))),
                    ]),
                  );
                  return ColoredBox(
                    color: _meetBg,
                    child: Row(children: [Expanded(child: _meet(app, call, title, status)), panel]),
                  );
                })
              : _meet(app, call, title, status))
          : meeting
              ? _meetWaiting(call, title, status)
              : _ringing(app, call, ch?.otherUserId(app.me?.id ?? ''), title, status, meeting),
    );
  }

  /// Cuộc họp đang vào / không vào được: cùng giao diện của cuộc họp (không phải màn gọi điện).
  Widget _meetWaiting(CallService call, String title, String status) {
    final failed = call.phase == CallPhase.ended;
    final code = call.meetingInfo?.code;
    return Scaffold(
      backgroundColor: _meetBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(failed ? Icons.error_outline_rounded : Icons.video_call_rounded, size: 56, color: failed ? _red : _blue),
                  const SizedBox(height: 20),
                  Text(
                    title.isEmpty ? tr('Cuộc họp') : title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500),
                  ),
                  if (code != null) ...[
                    const SizedBox(height: 6),
                    Text(code, style: const TextStyle(color: Colors.white54, fontSize: 14)),
                  ],
                  const SizedBox(height: 24),
                  if (!failed) ...[
                    const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: _blue)),
                    const SizedBox(height: 16),
                    Text(tr('Đang vào cuộc họp…'), style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  ] else
                    Text(status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4)),
                  const SizedBox(height: 28),
                  if (!failed)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                      onPressed: () => call.hangUp(),
                      icon: const Icon(Icons.close_rounded),
                      label: Text(tr('Hủy')),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- đổ chuông / đang gọi / kết thúc

  Widget _ringing(AppState app, CallService call, String? otherId, String title, String status, bool meeting) {
    final local = call.localVideo;
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: Stack(
        children: [
          if (local != null) Positioned.fill(child: CallVideo(stream: local, mirror: true)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: local != null
                    ? [Colors.black38, Colors.transparent, Colors.black54]
                    : [const Color(0xFF1F2C34), const Color(0xFF0B141A)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 14, color: Color(0xFF8696A0)),
                      const SizedBox(width: 6),
                      Text(
                        meeting ? tr('Cuộc họp nội bộ Flygo Chat') : tr('Cuộc gọi nội bộ Flygo Chat'),
                        style: const TextStyle(color: Color(0xFF8696A0), fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Avatar(
                    userId: otherId,
                    name: title,
                    size: 128,
                    icon: otherId == null ? Icons.groups : null,
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(status, style: const TextStyle(color: Color(0xFFD1D7DB), fontSize: 17)),
                  const Spacer(),
                  if (call.phase == CallPhase.incoming)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 56),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _RoundButton(
                            icon: Icons.call_end,
                            color: const Color(0xFFF15C6D),
                            label: tr('Từ chối'),
                            onTap: call.decline,
                          ),
                          _RoundButton(
                            icon: call.incomingVideo ? Icons.videocam : Icons.call,
                            color: const Color(0xFF25D366),
                            label: tr('Nghe máy'),
                            onTap: call.accept,
                          ),
                        ],
                      ),
                    )
                  else if (call.busy)
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2C34),
                        borderRadius: BorderRadius.circular(36),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _RoundButton(
                            icon: call.camera ? Icons.videocam : Icons.videocam_off_outlined,
                            color: call.camera ? Colors.white : const Color(0xFF3B4A54),
                            iconColor: call.camera ? Colors.black : Colors.white,
                            onTap: call.toggleCamera,
                            size: 58,
                          ),
                          if (call.camera && !isDesktop)
                            _RoundButton(
                              icon: Icons.cameraswitch_outlined,
                              color: const Color(0xFF3B4A54),
                              onTap: call.switchCamera,
                              size: 58,
                            ),
                          if (!isDesktop)
                            _RoundButton(
                              icon: call.speaker ? Icons.volume_up : Icons.volume_down_outlined,
                              color: call.speaker ? Colors.white : const Color(0xFF3B4A54),
                              iconColor: call.speaker ? Colors.black : Colors.white,
                              onTap: call.toggleSpeaker,
                              size: 58,
                            ),
                          _RoundButton(
                            icon: call.muted ? Icons.mic_off : Icons.mic_none,
                            color: call.muted ? Colors.white : const Color(0xFF3B4A54),
                            iconColor: call.muted ? Colors.black : Colors.white,
                            onTap: call.toggleMute,
                            size: 58,
                          ),
                          _RoundButton(
                            icon: Icons.call_end,
                            color: const Color(0xFFF15C6D),
                            onTap: () => call.hangUp(),
                            size: 58,
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- giao diện kiểu Google Meet

  static final _fetching = <String>{};
  Widget _roleBadge(String text, Color fg, Color bg) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  /// Chủ trì / phó phòng: thao tác với một người (mọi máy của họ). Chỉ chủ trì giao phó phòng / chuyển chủ trì.
  Widget _moderateMenu(AppState app, CallService call, String userId, String name, {bool screen = false}) {
    PopupMenuItem<String> it(String v, IconData i, String t, {Color color = Colors.white}) => PopupMenuItem(
        value: v, child: Row(children: [Icon(i, color: color, size: 19), const SizedBox(width: 12), Text(t, style: TextStyle(color: color))]));
    final co = call.roomCohosts.contains(userId);
    final device = userId.startsWith('device:') || userId.startsWith('guest:');
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
      color: _panelBg,
      onSelected: (a) async {
        final messenger = ScaffoldMessenger.of(context);
        String? err;
        switch (a) {
          case 'cohost':
            err = await call.setRoles(cohosts: co ? [for (final x in call.roomCohosts) if (x != userId) x] : [...call.roomCohosts, userId]);
          case 'host':
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: Text(tr('Chuyển chủ trì cho {0}?', [name])),
                content: Text(tr('Bạn thành phó phòng. Chủ trì mới giao phó phòng và chuyển chủ trì tiếp được.')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
                  FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Chuyển chủ trì'))),
                ],
              ),
            );
            if (ok == true) err = await call.setRoles(host: userId);
          case 'star':
            final st = call.roomStars;
            err = await call.setRoomLayout(stars: st.contains(userId) ? [for (final x in st) if (x != userId) x] : [...st, userId]);
          case 'remove':
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: Text(tr('Mời {0} ra khỏi cuộc họp?', [name])),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: _red), onPressed: () => Navigator.pop(d, true), child: Text(tr('Mời ra'))),
                ],
              ),
            );
            if (ok == true) err = await call.moderate('remove', userId);
          default:
            err = await call.moderate(a, userId);
            if (a == 'ask_unmute' && err == null) messenger.showSnackBar(toast(Text(tr('Đã mời {0} bật mic', [name]))));
        }
        if (err != null) messenger.showSnackBar(toast(Text(err)));
      },
      itemBuilder: (_) => [
        if (call.amHost && !device) it('cohost', co ? Icons.star_outline : Icons.star, co ? tr('Bỏ phó phòng') : tr('Làm phó phòng')),
        if (call.amHost && !device) it('host', Icons.workspace_premium_outlined, tr('Chuyển chủ trì')),
        it('ask_unmute', Icons.mic_none, tr('Mời bật mic')),
        it('mute', Icons.mic_off, tr('Tắt mic')),
        if (screen) it('stop_share', Icons.cancel_presentation, tr('Dừng chia sẻ màn hình')),
        it('star', call.roomStars.contains(userId) ? Icons.star_rounded : Icons.star_border_rounded,
            call.roomStars.contains(userId) ? tr('Bỏ ngôi sao') : tr('Đặt làm ngôi sao')),
        it('remove', Icons.person_remove_alt_1, tr('Mời ra khỏi cuộc họp'), color: const Color(0xFFFF9B9B)),
      ],
    );
  }

  String _nameOf(AppState app, String userId) {
    if (userId.startsWith('device:')) return app.calls.deviceNames[userId] ?? tr('Thiết bị phòng họp');
    // Khách vào bằng link (tên do khách nhập, kèm "(khách)").
    if (userId.startsWith('guest:')) return app.calls.deviceNames[userId] ?? tr('Khách');
    final n = app.users[userId]?.displayName ?? '';
    if (n.isEmpty && userId.isNotEmpty && _fetching.add(userId)) {
      // Người trong cuộc gọi chưa có trong danh bạ của app (vd. ngoài nhóm): tải tên về rồi vẽ lại.
      app.refreshUser(userId).catchError((_) {});
    }
    return n.isEmpty ? tr('Người dùng') : n;
  }

  /// Mọi ô: chia sẻ màn hình trước (của mình trước tiên), rồi người khác, cuối cùng là mình.
  List<_TileData> _tiles(AppState app, CallService call) {
    final screens = <_TileData>[
      if (call.localScreen != null)
        _TileData(
          key: 'screen:me',
          userId: app.me?.id,
          name: tr('Bạn đang chia sẻ màn hình'),
          stream: call.localScreen,
          screen: true,
        ),
    ];
    final people = <_TileData>[];
    for (final p in call.participants) {
      // Phiên chưa rõ là ai (chưa có user id) thì không vẽ ô "Người dùng" trống.
      if (p.userId.isEmpty) continue;
      // Chính mình vào từ thiết bị khác (hoặc phiên cũ chưa thoát hẳn).
      final dl = call.deviceLabel(p);
      final base = p.userId == app.me?.id ? tr('Bạn') : _nameOf(app, p.userId);
      final name = dl.isEmpty ? base : '$base ($dl)';
      if (p.hasScreen) {
        screens.add(_TileData(
          key: 'screen:${p.sessionId}',
          userId: p.userId,
          name: tr('{0} đang trình bày', [name]),
          stream: p.screenStream,
          trackId: p.screenTrackId,
          screen: true,
        ));
      }
      people.add(_TileData(
        key: p.sessionId,
        userId: p.userId,
        name: name,
        stream: p.hasVideo ? p.videoStream : null,
        trackId: p.videoTrackId,
        muted: !p.unmuted,
        speaking: p.speaking && p.unmuted,
        raisedHand: p.raisedHand,
        quality: p.quality,
      ));
    }
    final me = _TileData(
      key: 'me',
      userId: app.me?.id,
      name: tr('Bạn'),
      stream: call.localVideo,
      mirror: true,
      muted: call.muted,
      speaking: call.meSpeaking && !call.muted,
    );
    return [...screens, ...people, me];
  }

  /// Máy này tự đổi cách xem: phòng khoá bố cục thì không được; không khoá thì thôi theo bố cục của phòng.
  bool _localChange(CallService call) {
    if (call.liveKit && call.appLayout['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Chủ trì đã khoá bố cục của cuộc họp'))));
      return false;
    }
    _followRoom = false;
    return true;
  }

  void _tapTile(String key, String? spot) {
    // Bấm khung lớn: phóng to (ẩn dải người) / thu lại — không đổi bố cục của phòng.
    if (key == spot) {
      setState(() => _stageFull = !_stageFull);
      _poke();
      return;
    }
    if (!_localChange(context.read<AppState>().calls)) return;
    setState(() {
      if (key == spot) {
        // Bấm lại ô đang ghim: bỏ ghim (chia sẻ màn hình thì nhớ là đã bỏ ghim).
        if (_pinned == key) {
          _pinned = null;
        } else {
          _dismissedScreen = key;
        }
      } else {
        _pinned = key;
      }
    });
    _poke();
  }

  Widget _meet(AppState app, CallService call, String title, String status) {
    final tiles = _tiles(app, call);
    // Bài trình chiếu tài liệu là một ô như màn hình chia sẻ: lên khung lớn (kèm dải người) hoặc một ô trong lưới.
    final presRaw = call.roomPresent;
    if (presRaw != null) {
      tiles.insert(
          0,
          _TileData(
            key: 'present',
            userId: '${presRaw['by'] ?? ''}',
            name: tr('{0} đang trình chiếu', ['${presRaw['name'] ?? ''}']),
            screen: true,
            custom: (compact) => MeetPresentView(call: call, compact: compact),
          ));
    }
    // Họp (mới): trang đang lên sân khấu (chào mừng, chương trình, biên bản, bình chọn…) cũng là một ô như bài trình chiếu.
    final stageRaw = call.roomStage;
    final stageOn = stageShowsPage(call);
    if (stageOn) {
      tiles.insert(
          0,
          _TileData(
            key: 'stage',
            userId: '${stageRaw?['presenter'] ?? ''}',
            name: '${stageRaw?['page_title'] ?? ''}',
            screen: true,
            custom: (compact) => StagePageView(call: call, compact: compact),
          ));
    }
    final keys = {for (final t in tiles) t.key};
    if (_pinned != null && !keys.contains(_pinned)) _pinned = null;
    // Bố cục của phòng (LiveKit, chủ trì / phó phòng đặt): đổi thì máy này theo lại; khoá thì luôn theo.
    final rl = jsonEncode(call.roomLayout);
    if (rl != _roomLayoutSeen) {
      _roomLayoutSeen = rl;
      _followRoom = true;
    }
    final lay = call.appLayout;
    final following = call.liveKit && (_followRoom || lay['locked'] == true);
    var layout = _layout;
    var pinned = _pinned;
    // "Chỉ cho lên sân khấu người chỉ định": chỉ màn hình / bài trình chiếu / camera của ngôi sao lên khung lớn.
    final starIds = following && (lay['mode'] == 'stars' || lay['mode'] == 'pin') ? call.roomStars : null;
    if (following) {
      final mode = lay['mode'];
      layout = mode == 'grid' ? MeetLayout.grid : MeetLayout.auto;
      pinned = null;
    }
    // Màn hình chia sẻ mới nhất (ai cũng chia sẻ được, nhiều màn hình cùng lúc).
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final t in tiles) {
      if (t.screen) _screenSeen.putIfAbsent(t.key, () => now);
    }
    _screenSeen.removeWhere((k, _) => !keys.contains(k));
    final screens = [
      for (final t in tiles)
        if (t.screen && t.key != 'present' && t.key != 'stage' && t.key != _dismissedScreen && (starIds == null || starIds.contains(t.userId))) t
    ]
      ..sort((a, b) => (_screenSeen[b.key] ?? 0).compareTo(_screenSeen[a.key] ?? 0));
    final star = _room?.star;
    var spot = pinned ??
        (star == null ? null : tiles.where((t) => !t.screen && t.userId == star).firstOrNull?.key) ??
        screens.firstOrNull?.key;
    final talking = tiles.where((t) => t.speaking && t.key != 'me').firstOrNull?.key;
    if (talking != null) _lastSpeaker = talking;
    if (_lastSpeaker != null && !keys.contains(_lastSpeaker)) _lastSpeaker = null;
    switch (layout) {
      case MeetLayout.grid:
        // Lưới: mọi người bằng nhau (chỉ ô mình tự ghim mới lớn).
        spot = pinned;
      case MeetLayout.sidebar || MeetLayout.spotlight:
        spot ??= _lastSpeaker ?? tiles.where((t) => t.key != 'me').firstOrNull?.key;
      case MeetLayout.auto:
        break;
    }
    // Bài trình chiếu tài liệu: lên khung lớn khi phòng chọn "bài trình chiếu", hoặc khi nó mới hơn màn hình chia sẻ mới nhất
    // (không ghim ai, không ở dạng lưới).
    final pres0 = call.roomPresent;
    final pres = pres0 != null && (starIds == null || starIds.contains('${pres0['by']}')) ? pres0 : null;
    final newestScreenAt = screens.isEmpty ? 0 : (_screenSeen[screens.first.key] ?? 0);
    final presOn = pres != null &&
        pinned == null &&
        layout != MeetLayout.grid &&
        (lay['mode'] == 'present' || screens.isEmpty || ((pres['at'] as num?)?.toInt() ?? 0) >= newestScreenAt);
    if (presOn && _dismissedScreen != 'present') spot = 'present';
    // Trang trên sân khấu: lên khung lớn khi mới hơn bài trình chiếu / màn hình chia sẻ (không ghim, không dạng lưới).
    final stageAt = (stageRaw?['at'] as num?)?.toInt() ?? 0;
    if (stageOn && pinned == null && layout != MeetLayout.grid && _dismissedScreen != 'stage' &&
        (!presOn || stageAt >= ((pres['at'] as num?)?.toInt() ?? 0)) && (screens.isEmpty || stageAt >= newestScreenAt)) {
      spot = 'stage';
    }
    // Chế độ ngôi sao, không ngôi sao nào đang trình chiếu: camera của ngôi sao đầu tiên lên khung lớn.
    if (starIds != null && starIds.isNotEmpty && !presOn && screens.isEmpty && pinned == null) {
      spot = tiles.where((t) => !t.screen && starIds.contains(t.userId)).firstOrNull?.key ?? spot;
    }
    // Trang hệ thống trên sân khấu (Họp mới): lưới video / người đang nói / chủ phòng, thay cho "Đổi bố cục".
    final sysp = '${call.roomStage?['page'] ?? ''}';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final t in tiles) {
      if (t.stream != null && !t.screen) {
        _camOnAt.putIfAbsent(t.key, () => nowMs);
      } else {
        _camOnAt.remove(t.key);
      }
    }
    if (call.meeting && sysp.startsWith('sys:') && sysp != 'sys:handover' && _pinned == null) {
      final video = [for (final t in tiles) if (!t.screen && t.custom == null && t.stream != null) t];
      switch (sysp) {
        case 'sys:grid':
          layout = MeetLayout.grid;
          spot = null;
          if (video.isNotEmpty) tiles.removeWhere((t) => !t.screen && t.custom == null && t.stream == null);
        case 'sys:auto':
          final talk = video.where((t) => t.speaking && t.key != 'me').firstOrNull;
          if (talk != null && talk.key != _sysSpeaker && nowMs - _sysSpeakerAt > 3000) {
            _sysSpeaker = talk.key;
            _sysSpeakerAt = nowMs;
          }
          if (!video.any((t) => t.key == _sysSpeaker)) _sysSpeaker = video.where((t) => t.key != 'me').firstOrNull?.key ?? video.firstOrNull?.key;
          layout = MeetLayout.auto;
          spot = _sysSpeaker;
        case 'sys:host':
          spot = (video.where((t) => t.userId == call.roomHost).firstOrNull ?? video.firstOrNull)?.key;
          layout = MeetLayout.auto;
          // Dải bên dưới: ai mới bật camera đứng đầu.
          tiles.sort((a, b) => (_camOnAt[b.key] ?? 0).compareTo(_camOnAt[a.key] ?? 0));
      }
    }
    // Phạm vi app không buộc toàn màn hình: khung lớn kèm dải người; bấm khung lớn để phóng to / thu lại.
    if (spot == null) _stageFull = false;
    // Cuộc họp (Sếp, 2026-11-20): tắt camera thì không vẽ ô (ô xám + ảnh đại diện). Ô của mình ẩn hẳn; người khác tắt
    // camera ẩn khi sân khấu đang chiếu nội dung (họ vẫn ở danh sách Thành viên). Ô đang ghim thì giữ.
    if (call.meeting && !call.groupCall) {
      final content = spot != null && tiles.any((t) => t.key == spot && (t.screen || t.custom != null));
      tiles.removeWhere((t) =>
          t.key != spot && !t.screen && t.custom == null && (t.key == 'me' ? !call.camera : (content && t.stream == null)));
    }
    final room = _room;
    final staged = room != null && (room.stage != null || room.webUrl != null);
    final show = _controls;
    return Scaffold(
      backgroundColor: _meetBg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.fromLTRB(8, show ? 60 : 8, 8, show ? (_barTwoRows ? 152 : 88) : 8),
                  child: staged
                      ? MeetStage(room: room)
                      : LayoutBuilder(
                          builder: (context, box) =>
                              _stage(tiles, spot, box, call, onlyMain: layout == MeetLayout.spotlight || (_stageFull && spot != null))),
                ),
              ),
            ),
            // Phụ đề lời trợ lý cả khi không có màn trình chiếu.
            if (!staged && _captions && room?.caption != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: show ? (_barTwoRows ? 160 : 100) : 24,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(10)),
                    child: Text(room!.caption!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.35, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            // Cảm xúc bay lên + bình luận nổi.
            Positioned.fill(child: ReactionsLayer(reactions: call.reactions.stream)),
            // Bình luận nổi ở góc trái trên (không đè nhãn ô video ở dưới).
            if (room != null) Positioned(left: 12, top: show ? 64 : 12, child: CommentsTicker(room: room)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _fade(show, _topBar(title, status, reserve: call.transcribing)),
            ),
            // Dòng báo của phòng: khoá, im lặng / tắt cam toàn bộ, ngôi sao.
            if (call.liveKit && _banners(app, call).isNotEmpty)
              Positioned(
                top: show ? 64 : 12,
                left: 12,
                right: 12,
                child: IgnorePointer(
                  child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                    for (final t in _banners(app, call))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
                        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                      ),
                  ]),
                ),
              ),
            // Đang phiên âm: luôn hiện (cả khi thanh nút ẩn) để mọi người biết lời nói đang được ghi thành chữ.
            if (call.transcribing) const Positioned(top: 12, right: 16, child: _ScribeChip()),
            // Phụ đề trực tiếp (module thêm): ngay trên thanh nút.
            MeetCaptionsOverlay(call: call, bottom: show ? (_barTwoRows ? 156 : 96) : 24),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _fade(show, _controlBar(app, call)),
            ),
            // Người xin vào phòng (chủ phòng cho vào / từ chối).
            if (room != null && room.knocks.isNotEmpty && _isHost(app, call))
              Positioned(top: show ? 64 : 12, right: 12, child: _knockCard(app, room)),
            if (call.reconnecting)
              Positioned(
                top: show ? 64 : 12,
                left: 0,
                right: 0,
                child: const Center(child: ReconnectingChip()),
              ),
            // Đang tự xem kiểu khác với bố cục của phòng: một chạm để theo lại.
            if (call.liveKit && !following && show)
              Positioned(
                top: 64,
                left: 0,
                right: 0,
                child: Center(
                  child: ActionChip(
                    avatar: const Icon(Icons.sync_rounded, size: 18),
                    label: Text(tr('Theo bố cục của phòng')),
                    onPressed: () => setState(() => _followRoom = true),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fade(bool show, Widget child) => IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
      );

  Widget _topBar(String title, String status, {bool reserve = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 16, 0),
        child: Row(
          children: [
            // Về nhóm chat của cuộc họp (cuộc họp thu nhỏ thành khung nổi).
            Builder(builder: (context) {
              final app = context.read<AppState>();
              return IconButton(
                tooltip: tr('Về nhóm chat'),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                onPressed: () => _backToChat(app, app.calls),
              );
            }),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(status, style: const TextStyle(color: _grey, fontSize: 13)),
                ],
              ),
            ),
            // Số người trong cuộc họp: bấm mở Thành viên (danh sách, mời người, lượt trình chiếu).
            Builder(builder: (context) {
              final app = context.read<AppState>();
              final call = app.calls;
              if (!call.meeting || call.groupCall) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Material(
                  color: Colors.white.withValues(alpha: .1),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => isDesktop ? _openPanel(_MeetPanel.people) : _moreSheet(app, call, tab: _MeetPanel.people),
                    child: Tooltip(
                      message: tr('Thành viên'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.people_outline_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text('${call.participants.length + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (reserve) const SizedBox(width: 150),
          ],
        ),
      );

  Widget _tile(_TileData t, String? spot, {bool small = false}) => _Tile(
        key: ValueKey(t.key),
        data: t,
        pinned: t.key == spot,
        small: small,
        onTap: () => _tapTile(t.key, spot),
      );

  Widget _stage(List<_TileData> tiles, String? spot, BoxConstraints box, CallService call, {bool inner = false, bool onlyMain = false}) {
    final wide = box.maxWidth > box.maxHeight;
    const gap = 8.0;
    // Gọi nhóm / chỉ hai ô: hình của mình nổi ở góc, kéo đi khắp màn hình; kéo xuống nút xoá ở đáy là tắt camera.
    final me = tiles.where((t) => t.key == 'me').firstOrNull;
    if (!inner && me != null && spot != me.key && tiles.length >= 2 && (call.groupCall || tiles.length == 2)) {
      final rest = [for (final t in tiles) if (t.key != me.key) t];
      return Stack(children: [
        Positioned.fill(child: _stage(rest, spot, box, call, inner: true)),
        DraggablePip(
          key: const ValueKey('pip'),
          width: wide ? 240.0 : 108.0,
          height: wide ? 135.0 : 160.0,
          onTap: () => _tapTile(me.key, spot),
          onRemove: call.camera ? () => call.toggleCamera() : null,
          child: _tile(me, spot, small: true),
        ),
      ]);
    }
    // Cuộc họp / gọi nhóm chưa có ai: lời nhắn chờ ở giữa, ô của mình nhỏ bên dưới.
    if (!inner && (tiles.isEmpty || (tiles.length == 1 && tiles.first.key == 'me')) && call.channelId != null && !call.isDm(call.channelId!)) {
      final group = call.groupCall;
      final h = math.min(box.maxHeight * .42, 280.0);
      return Column(children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.groups_rounded, size: 56, color: _grey),
                const SizedBox(height: 12),
                Text(
                  group ? tr('Đang gọi mọi người trong nhóm…') : tr('Đang chờ mọi người tham gia…'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  group
                      ? tr('Cuộc gọi tự kết thúc khi mọi người rời đi.')
                      : tr('Mọi người trong nhóm có thể tham gia bất cứ lúc nào.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _grey, fontSize: 13.5),
                ),
              ]),
            ),
          ),
        ),
        if (tiles.isNotEmpty) SizedBox(height: h, width: math.min(box.maxWidth, wide ? h * 16 / 9 : h * 3 / 4), child: _tile(tiles.first, spot)),
      ]);
    }
    // Có ô ghim: ô đó lớn, các ô còn lại thành dải bên phải (màn ngang) hoặc ở dưới (màn dọc).
    if (spot != null) {
      final main = tiles.firstWhere((t) => t.key == spot);
      final rest = [for (final t in tiles) if (t.key != spot) t];
      if (rest.isEmpty || onlyMain) return _tile(main, spot);
      final strip = ListView.separated(
        scrollDirection: wide ? Axis.vertical : Axis.horizontal,
        itemCount: rest.length,
        separatorBuilder: (_, _) => const SizedBox(width: gap, height: gap),
        itemBuilder: (_, i) => SizedBox(
          width: wide ? null : 150,
          height: wide ? 130 : null,
          child: _tile(rest[i], spot, small: true),
        ),
      );
      return wide
          ? Row(children: [
              Expanded(child: _tile(main, spot)),
              const SizedBox(width: gap),
              SizedBox(width: math.min(240, box.maxWidth * .25), child: strip),
            ])
          : Column(children: [
              Expanded(child: _tile(main, spot)),
              const SizedBox(height: gap),
              SizedBox(height: 120, child: strip),
            ]);
    }
    final n = tiles.length;
    final int cols;
    if (n == 1) {
      cols = 1;
    } else if (n == 2) {
      cols = wide ? 2 : 1;
    } else if (n <= 4) {
      cols = 2;
    } else if (n <= 9) {
      // Màn dọc (điện thoại) tới 6 người: 2 cột cho ô đủ rộng.
      cols = !wide && n <= 6 ? 2 : 3;
    } else {
      cols = box.maxWidth > 1100 ? 4 : (wide ? 3 : 2);
    }
    // Đông người: cuộn dọc.
    if (n > 9) {
      return GridView.builder(
        itemCount: n,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          childAspectRatio: wide ? 16 / 9 : 3 / 4,
        ),
        itemBuilder: (_, i) => _tile(tiles[i], spot, small: true),
      );
    }
    // Lưới vừa khít màn hình (2×2, 3×3...), hàng cuối thiếu thì căn giữa như Meet.
    final rows = (n / cols).ceil();
    var tw = (box.maxWidth - gap * (cols - 1)) / cols;
    final th = (box.maxHeight - gap * (rows - 1)) / rows;
    if (tw > th * 16 / 9) tw = th * 16 / 9;
    return Center(
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        children: [
          for (final t in tiles) SizedBox(width: tw, height: th, child: _tile(t, spot, small: n > 4)),
        ],
      ),
    );
  }

  /// Gọi nhóm (kiểu WhatsApp): chỉ mic, camera, đổi camera, loa ngoài, người tham gia và gác máy — không trình chiếu,
  /// chia sẻ màn hình, giơ tay, bình chọn hay AI (những thứ đó dành cho cuộc họp).
  Widget _groupBar(AppState app, CallService call) {
    final count = call.participants.where((p) => p.userId.isNotEmpty).map((p) => p.userId).toSet().length + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _MeetButton(
              icon: Icons.people_outline,
              color: _btnBg,
              tooltip: tr('Người tham gia'),
              badge: '$count',
              onTap: () => _showPeople(app, call),
            ),
            _MeetButton(
              icon: call.camera ? Icons.videocam : Icons.videocam_off,
              color: call.camera ? _btnBg : _red,
              tooltip: call.camera ? tr('Tắt camera') : tr('Bật camera'),
              onTap: () {
                _camTap(call);
                _poke();
              },
            ),
            if (!isDesktop && call.camera)
              _MeetButton(
                icon: Icons.cameraswitch_outlined,
                color: _btnBg,
                tooltip: tr('Đổi camera'),
                onTap: () {
                  call.switchCamera();
                  _poke();
                },
              ),
            if (!isDesktop)
              _MeetButton(
                icon: call.speaker ? Icons.volume_up : Icons.phone_in_talk,
                color: call.speaker ? const Color(0xFFD2E3FC) : _btnBg,
                iconColor: call.speaker ? const Color(0xFF041E49) : Colors.white,
                tooltip: tr('Loa ngoài'),
                onTap: () {
                  call.toggleSpeaker();
                  _poke();
                },
              ),
            _MeetButton(
              icon: call.muted ? Icons.mic_off : Icons.mic,
              color: call.muted ? _red : _btnBg,
              tooltip: call.muted ? tr('Bật micro') : tr('Tắt micro'),
              onTap: () {
                _micTap(call);
                _poke();
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Tooltip(
                message: tr('Rời cuộc gọi'),
                child: Material(
                  color: _red,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => call.hangUp(),
                    child: const SizedBox(width: 68, height: 52, child: Icon(Icons.call_end, color: Colors.white, size: 26)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Điện thoại: thanh nút gọn — mic, camera, AI, "⋯" (mở bảng các nút còn lại) và gác máy.
  /// Tắt / bật tiếng cuộc họp phía mình: tiếng mọi người và cả sân khấu (giọng đọc, nhạc, hiệu ứng của slide).
  void _toggleDeafen(CallService call) {
    call.toggleDeafen();
    _room?.setSilent(call.deafened);
  }

  Widget _controlBar(AppState app, CallService call) {
    if (call.groupCall) return _groupBar(app, call);
    return _meetBar(app, call);
  }

  /// Hai hàng nút (điện thoại, cửa sổ hẹp) khi một hàng không đủ chỗ.
  bool _twoRowBar(double width) => false;

  /// Thanh nút của cuộc họp (Sếp, 2026-11-20), máy tính và điện thoại như nhau:
  /// mic · camera · âm thanh · phụ đề · giơ tay · cảm xúc | Tin nhắn · AI · Apps · Cài đặt | rời họp.
  /// Thành viên mở từ Cài đặt hoặc số người trên đầu màn hình; trình chiếu (màn hình / tài liệu) là app trong Apps.
  Widget _meetBar(AppState app, CallService call) {
    final room = _room;
    final host = _isHost(app, call);
    Widget btn(IconData icon, String tip, VoidCallback onTap, {bool on = false, bool off = false, String? badge, Color? onColor, Color? onIcon}) => _MeetButton(
          icon: icon,
          color: off ? _red : (on ? (onColor ?? _on) : _btnBg),
          iconColor: on && !off ? (onIcon ?? _onText) : Colors.white,
          tooltip: tip,
          badge: badge,
          onTap: () {
            onTap();
            _poke();
          },
        );
    final chatUnread = call.channelId == null ? 0 : app.unreadOf(call.channelId!);
    final media = <Widget>[
      btn(call.muted ? Icons.mic_off : Icons.mic, call.muted ? tr('Bật micro') : tr('Tắt micro'), () => _micTap(call), off: call.muted),
      btn(call.camera ? Icons.videocam : Icons.videocam_off, call.camera ? tr('Tắt camera') : tr('Bật camera'), () => _camTap(call), off: !call.camera),
      // Âm thanh: máy tính = tắt / bật tiếng cuộc họp phía mình; điện thoại = loa ngoài.
      if (isDesktop)
        btn(call.deafened ? Icons.volume_off_rounded : Icons.volume_up_rounded, call.deafened ? tr('Bật tiếng cuộc họp') : tr('Tắt tiếng cuộc họp'),
            () => _toggleDeafen(call), off: call.deafened)
      else
        btn(call.speaker ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded, call.speaker ? tr('Tắt loa ngoài') : tr('Bật loa ngoài'),
            () => call.toggleSpeaker().then((_) => mounted ? setState(() {}) : null), on: call.speaker),
      // Giơ tay + thả cảm xúc chung một nút.
      Builder(
        builder: (b) => btn(Icons.add_reaction_outlined, tr('Giơ tay, thả cảm xúc'), () => _reactPopover(b, call),
            on: call.handRaised, onColor: const Color(0xFFF5C451), onIcon: const Color(0xFF3C2A00), badge: call.handRaised ? '✋' : null),
      ),
      // ⋯: Tương tác (trang), Thành viên, Màn hình, Chat, AI — cột phải (máy tính) / bảng kéo lên (điện thoại).
      btn(Icons.more_horiz_rounded, tr('Tương tác, thành viên, màn hình, chat, AI'), () => _openMore(app, call),
          on: _panel != _MeetPanel.none,
          badge: room != null && room.knocks.isNotEmpty && host ? '!' : (chatUnread > 0 ? (chatUnread > 99 ? '99+' : '$chatUnread') : null)),
    ];
    final leave = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: tr('Rời cuộc họp'),
        child: Material(
          color: _red,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _leave(call),
            child: const SizedBox(width: 68, height: 52, child: Icon(Icons.call_end, color: Colors.white, size: 26)),
          ),
        ),
      ),
    );
    // Một hàng nút duy nhất; hẹp thì thu nhỏ cả hàng (không xuống dòng).
    return LayoutBuilder(builder: (context, box) {
      _stageW = box.maxWidth;
      final code = call.meetingInfo?.code;
      final clock = box.maxWidth >= 1100
          ? Text.rich(
              TextSpan(children: [
                TextSpan(text: hhmm(DateTime.now())),
                const TextSpan(text: '   |   ', style: TextStyle(color: _grey)),
                TextSpan(text: code ?? call.meetingInfo?.title ?? '', style: const TextStyle(color: _grey)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
            )
          : const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.fromLTRB(box.maxWidth < 600 ? 8 : 20, 0, box.maxWidth < 600 ? 8 : 16, 16),
        child: box.maxWidth >= 1100
            ? Row(children: [
                Expanded(child: clock),
                FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [...media, const SizedBox(width: 10), leave])),
                const Expanded(child: SizedBox.shrink()),
              ])
            // Không có đồng hồ: hàng nút dùng hết bề rộng, chỉ thu nhỏ khi thật sự thiếu chỗ.
            : Center(child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [...media, const SizedBox(width: 10), leave]))),
      );
    });
  }

  /// App của màn họp đặt trong ô Apps (ngoài các loại trang).
  List<PageApp> _pageApps(AppState app, CallService call) {
    final x = {for (final a in meetExtraActions(context, call)) a.id: a};
    final room = _room;
    return [
      if (x['board'] != null)
        PageApp(id: 'board', label: tr('Bảng trắng'), desc: tr('Cùng vẽ, ghi chú'), icon: Icons.draw_outlined, color: const Color(0xFF34A853), run: x['board']!.run),
      if (room != null)
        PageApp(
          id: 'web',
          label: room.webUrl == null ? tr('Website') : tr('Dừng website'),
          desc: tr('Mở một trang web cho cả phòng'),
          icon: room.webUrl == null ? Icons.public : Icons.public_off,
          color: const Color(0xFF4285F4),
          run: (c, call) => _runMore(room.webUrl == null ? 'web' : 'web_close', app, call),
        ),
    ];
  }

  /// Tab AI (máy tính): Thư ký Họp (đang phiên âm, tóm tắt cuộc họp) ở trên, trợ lý AI của nhóm bên dưới.
  Widget _aiBody(AppState app, CallService call) {
    final ai = call.channelId != null && app.channels[call.channelId] != null && app.showsAiFor(app.channels[call.channelId]!);
    final summary = call.meeting && call.scribeAvailable;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Phụ đề (lời trợ lý / phiên âm trên màn hình) bật / tắt ở đây (không còn nút trên thanh).
      SwitchListTile(
        dense: true,
        value: _captions,
        title: Text(tr('Hiện phụ đề trên màn hình'), style: const TextStyle(color: Colors.white)),
        onChanged: (v) => setState(() => _captions = v),
      ),
      if (summary)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            if (call.transcribing) const _ScribeChip() else Text(tr('Chưa phiên âm'), style: const TextStyle(color: _grey, fontSize: 12.5)),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () => _runMore('summary', app, call),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(tr('Tóm tắt cuộc họp')),
            ),
          ]),
        ),
      if (ai)
        Expanded(child: AiPanel(groupId: call.channelId!, thread: _room?.threadRoot ?? call.callThreadId))
      else
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr('Nhóm này chưa bật trợ lý AI. Tóm tắt cuộc họp dùng phiên âm của Thư ký Họp.'), style: const TextStyle(color: _grey)),
        ),
    ]);
  }

  /// Giơ tay + cảm xúc: một hàng nổi phía trên nút, giữ mở để bấm liên tục; bấm ra ngoài thì đóng.
  Future<void> _reactPopover(BuildContext anchor, CallService call) async {
    final box = anchor.findRenderObject() as RenderBox;
    final top = box.localToGlobal(Offset.zero).dy;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: tr('Đóng'),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, _) {
        final h = MediaQuery.sizeOf(ctx).height;
        return Stack(children: [
          Positioned(
            left: 8,
            right: 8,
            bottom: h - top + 10,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Material(
                  color: const Color(0xFF2D2E31),
                  elevation: 10,
                  borderRadius: BorderRadius.circular(32),
                  child: ListenableBuilder(
                    listenable: call,
                    builder: (_, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Tooltip(
                          message: call.handRaised ? tr('Hạ tay') : tr('Giơ tay'),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: call.toggleHand,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: call.handRaised ? const Color(0xFFF5C451) : Colors.transparent),
                              alignment: Alignment.center,
                              child: const Text('✋', style: TextStyle(fontSize: 28)),
                            ),
                          ),
                        ),
                        if (meetPerm(call, 'react')) ...[
                          Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 6), color: Colors.white24),
                          for (final e in CallService.reactionNames.keys)
                            InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => call.react(e),
                              child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 30))),
                            ),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }

  /// Nút Mute (chủ trì / phó phòng): tắt tạm (mọi người tự bật lại được), tắt hẳn (không cho bật lại), cho bật lại.
  Future<void> _muteDialog(AppState app, CallService call) async {
    final forced = meetPerms(call)['unmute'] == false;
    final a = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Tắt mic mọi người')),
        content: Text(forced
            ? tr('Mic mọi người đang bị tắt hẳn (không tự bật lại được). Bạn muốn làm gì?')
            : tr('Nút này sẽ tắt mic mọi người, bạn có muốn không?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Giữ nguyên'))),
          TextButton(onPressed: () => Navigator.pop(d, 'temp'), child: Text(tr('Tắt tạm'))),
          if (forced)
            FilledButton(onPressed: () => Navigator.pop(d, 'lift'), child: Text(tr('Cho bật lại')))
          else
            FilledButton(onPressed: () => Navigator.pop(d, 'force'), child: Text(tr('Tắt hẳn'))),
        ],
      ),
    );
    if (a == null || !mounted) return;
    try {
      switch (a) {
        case 'temp':
          await _runMore('mute_all', app, call);
          if (mounted) meetToast(context, tr('Đã tắt mic mọi người. Ai cần nói có thể tự bật lại.'));
        case 'force':
          await fxRequest(call, 'POST', '/controls', {'perms': {'unmute': false}});
          if (mounted) meetToast(context, tr('Đã tắt hẳn mic mọi người. Bấm lại nút này để cho bật lại.'));
        case 'lift':
          await fxRequest(call, 'POST', '/controls', {'perms': {'unmute': true}});
          if (mounted) meetToast(context, tr('Mọi người đã có thể bật mic lại.'));
      }
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  /// Cài đặt (panel máy tính / bảng dưới điện thoại), Sếp 2026-11-20: hai tab Thành viên / Màn hình.
  /// [close]: đóng bảng dưới trước khi làm (điện thoại).
  Widget _settingsView(AppState app, CallService call, {VoidCallback? close}) {
    final screens = call.participants.where((p) => p.userId.startsWith('device:')).length;
    return DefaultTabController(
      length: 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TabBar(
          labelColor: Colors.white,
          unselectedLabelColor: _grey,
          indicatorColor: const Color(0xFF2BB3A3),
          dividerColor: Colors.white12,
          labelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          tabs: [
            Tab(height: 48, text: tr('Thành viên · {0}', [call.participants.length + 1 - screens])),
            Tab(height: 48, text: screens > 0 ? tr('Màn hình · {0}', [screens]) : tr('Màn hình')),
          ],
        ),
        Expanded(child: TabBarView(children: [_membersTab(app, call, close), _screensTab(app, call, close)])),
      ]),
    );
  }

  Widget _membersTab(AppState app, CallService call, VoidCallback? close) {
    final x = {for (final a in meetExtraActions(context, call)) a.id: a};
    final hasCode = call.meeting && (call.meetingInfo?.code ?? '').isNotEmpty;
    final style = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );
    final compact = FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact);
    void guest() {
      close?.call();
      if (hasCode && call.canModerate && x['guest_invite'] != null) {
        x['guest_invite']!.run(context, call);
      } else {
        _copyLiveLink(app, call);
      }
    }

    return ListenableBuilder(
      listenable: call,
      builder: (_, _) {
        final room = _room;
        return ListView(padding: const EdgeInsets.only(top: 10, bottom: 16), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // Máy tính: hai nút gọn cạnh nhau (cao ~36); điện thoại: hai nút lớn, mỗi nút một dòng (dễ chạm).
            child: isDesktop
                ? Wrap(spacing: 8, runSpacing: 8, children: [
                    Tooltip(
                      message: tr('Người ngoài công ty vào bằng liên kết, không cần cài phần mềm'),
                      child: FilledButton.tonalIcon(style: compact, icon: const Icon(Icons.link_rounded, size: 18), label: Text(tr('Mời khách')), onPressed: guest),
                    ),
                    FilledButton.tonalIcon(style: compact, icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: Text(tr('Mời thành viên')), onPressed: () => _inviteSheet(app, call)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    OutlinedButton.icon(style: style, icon: const Icon(Icons.link_rounded, size: 20), label: Text(tr('Mời khách (không cần cài phần mềm)')), onPressed: guest),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(style: style, icon: const Icon(Icons.person_add_alt_1_outlined, size: 20), label: Text(tr('Mời thành viên')), onPressed: () => _inviteSheet(app, call)),
                  ]),
          ),
          // Chủ trì / phó phòng: tắt mic mọi người (tạm / hẳn / cho bật lại).
          if (call.canModerate && room != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  style: isDesktop ? compact : FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: Icon(meetPerms(call)['unmute'] == false ? Icons.mic_off_rounded : Icons.mic_off_outlined, size: 18),
                  label: Text(meetPerms(call)['unmute'] == false ? tr('Đang tắt hẳn mic mọi người…') : tr('Tắt mic mọi người…')),
                  onPressed: () => _muteDialog(app, call),
                ),
              ),
            ),
          if (room != null && room.knocks.isNotEmpty && _isHost(app, call)) ...[
            _panelHead(tr('Đang xin tham gia')),
            for (final k in room.knocks)
              ListTile(
                leading: _Face(userId: k.userId, name: k.name, size: 36),
                title: Text(k.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: () => _admit(app, room, k, false), child: Text(tr('Từ chối'), style: const TextStyle(color: _grey))),
                  TextButton(onPressed: () => _admit(app, room, k, true), child: Text(tr('Cho vào'), style: const TextStyle(color: _blue))),
                ]),
              ),
          ],
          _panelHead(tr('Trong cuộc họp · {0}', [call.participants.length + 1])),
          ..._peopleRows(app, call),
        ]);
      },
    );
  }

  /// Màn hình: màn hình / TV đang trong cuộc họp và nút thêm màn hình bằng mã QR.
  Widget _screensTab(AppState app, CallService call, VoidCallback? close) => ListenableBuilder(
        listenable: call,
        builder: (_, _) {
          final list = call.participants.where((p) => p.userId.startsWith('device:')).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 16), children: [
            if (call.liveKit)
              Align(
                alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
                child: Tooltip(
                  message: tr('Quét mã QR trên TV / màn hình phòng họp'),
                  child: FilledButton.tonalIcon(
                    style: isDesktop
                        ? FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), visualDensity: VisualDensity.compact)
                        : FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: Text(isDesktop ? tr('Thêm màn hình') : tr('Thêm màn hình (quét mã QR trên TV)')),
                    onPressed: () {
                      close?.call();
                      _addScreen(call);
                    },
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(tr('Chưa có màn hình nào trong cuộc họp. Mở trang hello trên TV / màn hình phòng họp rồi quét mã QR.'),
                    style: const TextStyle(color: _grey)),
              ),
            for (final p in list)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.tv_rounded, color: Colors.white),
                title: Text(call.deviceNames[p.userId] ?? tr('Màn hình phòng họp'), style: const TextStyle(color: Colors.white)),
                subtitle: Text(tr('Đang chiếu cuộc họp'), style: const TextStyle(color: _grey, fontSize: 12.5)),
              ),
          ]);
        },
      );

  /// Mời thành viên: lời mời, liên kết, mã QR, chia sẻ.
  Future<void> _inviteSheet(AppState app, CallService call) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: _panelBg,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 520),
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Mời thành viên'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _infoView(app, call),
            ]),
          ),
        ),
      );

  /// Gác máy. Người tạo cuộc họp: chọn rời (cuộc họp vẫn tiếp tục) hoặc kết thúc cuộc họp cho mọi người.
  Future<void> _leave(CallService call) async {
    if (!call.isMeetingCreator) return call.hangUp();
    _hide?.cancel();
    final a = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.white),
              title: Text(tr('Rời cuộc họp'), style: const TextStyle(color: Colors.white)),
              subtitle: Text(tr('Cuộc họp vẫn tiếp tục, bạn vào lại được.'), style: const TextStyle(color: _grey)),
              onTap: () => Navigator.pop(ctx, 'leave'),
            ),
            ListTile(
              leading: const Icon(Icons.call_end_rounded, color: _red),
              title: Text(tr('Kết thúc cuộc họp'), style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
              subtitle: Text(tr('Mọi người rời họp, cuộc họp đóng lại.'), style: const TextStyle(color: _grey)),
              onTap: () => Navigator.pop(ctx, 'end'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (a == 'leave') return call.hangUp();
    if (a == 'end') return call.endMeeting();
    _poke();
  }

  /// Bình chọn trong cuộc họp: danh sách bình chọn của luồng cuộc họp (bấm chọn ngay tại đây) và nút tạo mới.
  Future<void> _polls(AppState app, CallService call) async {
    final ch = call.channelId;
    if (ch == null) return;
    _hide?.cancel();
    final since = call.startedAt?.millisecondsSinceEpoch ?? 0;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => ListenableBuilder(
        listenable: app,
        builder: (ctx, _) {
          final polls = [
            for (final p in app.postsOf(ch).reversed)
              if (p.props['flygo_poll'] is Map && p.deleteAt == 0 && p.createAt >= since - 60000) p,
          ];
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(children: [
                    Expanded(child: Text(tr('Bình chọn'), style: Theme.of(ctx).textTheme.titleLarge)),
                    FilledButton.icon(
                      onPressed: () => _newPoll(app, call),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr('Tạo bình chọn')),
                    ),
                  ]),
                ),
                if (polls.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(tr('Chưa có bình chọn nào trong cuộc họp này.'), textAlign: TextAlign.center),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: polls.length,
                      separatorBuilder: (_, _) => const Divider(height: 24),
                      itemBuilder: (_, i) => PollCard(app: app, post: polls[i], width: 520),
                    ),
                  ),
              ]),
            ),
          );
        },
      ),
    );
    _poke();
  }

  Future<void> _newPoll(AppState app, CallService call) async {
    final ch = call.channelId;
    if (ch == null) return;
    final poll = await showCreatePoll(context, app.me?.id ?? '');
    if (poll == null || !mounted) return;
    poll.remove('_pin');
    // Gửi vào chat của nhóm (ai không trong cuộc họp cũng thấy); bình chọn ngay trong bảng của cuộc họp.
    await app.send(ch, '📊 ${tr('Bình chọn')}: ${poll['question']}', props: {'flygo_poll': poll});
  }

  /// Chủ phòng vừa vào cuộc họp: hỏi một lần có bật phiên âm tự động không.
  Future<void> _askScribe(CallService call) async {
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.subtitles_rounded),
        title: Text(tr('Bạn có muốn bật phiên âm tự động cho cuộc họp này?')),
        content: Text(tr('Lời nói của người đang bật mic sẽ được ghi thành tin nhắn trong nhóm của cuộc họp. '
            'Bạn bật / tắt lại được trong menu cuộc họp.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Không'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Có'))),
        ],
      ),
    );
    if (yes == null || !mounted) return;
    // "Không" cũng lưu lại (đã hỏi) để lần vào sau không hỏi nữa.
    final ok = await call.setTranscribing(yes);
    if (!ok && mounted) _snack(tr('Không đổi được trạng thái phiên âm, thử lại trong menu cuộc họp.'));
  }

  Future<void> _toggleScribe(CallService call) async {
    if (call.transcribing) {
      final off = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(tr('Tắt phiên âm cuộc họp này?')),
          content: Text(tr('Từ giờ lời nói không còn được ghi thành tin nhắn. Bạn bật lại được bất cứ lúc nào.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Tắt phiên âm'))),
          ],
        ),
      );
      if (off != true || !mounted) return;
    }
    final ok = await call.setTranscribing(!call.transcribing);
    if (!ok && mounted) _snack(tr('Không đổi được trạng thái phiên âm, thử lại sau.'));
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));

  bool _isHost(AppState app, CallService call) =>
      (_room?.host ?? false) || call.callerId == app.me?.id || (call.channelId != null && app.canManage(call.channelId!));



  Future<void> _runMore(String? a, AppState app, CallService call) async {
    if (a == 'scribe') return _toggleScribe(call);
    // Máy tính: Trang họp nằm trong panel bên phải; điện thoại: bảng kéo lên.
    if (a == 'pages') return isDesktop ? _openPanel(_MeetPanel.pages) : showPagesSheet(context, call);
    if (a == 'present') {
      if (!call.mayPresent) return meetToast(context, tr('Chỉ ngôi sao của cuộc họp được trình chiếu'));
      return startPresenting(context, call);
    }
    if (a != null && a.startsWith('x:')) {
      final x = meetExtraActions(context, call).where((x) => 'x:${x.id}' == a).firstOrNull;
      if (x != null) await x.run(context, call);
      return;
    }
    if (a == 'summary') {
      final ch = call.channelId;
      if (ch != null) await summarizeMeeting(context, channelId: ch, code: call.meetingInfo?.code);
      return;
    }
    final room = _room;
    if (room == null) return;
    switch (a) {
      case 'layout':
        await _pickLayout();
      case 'qr_invite':
        if (mounted) await _addScreen(call);
      case 'info':
        await _infoSheet(app, call);
      case 'poll':
        await _polls(app, call);
      case 'web':
        if (!mounted) return;
        final ctl = TextEditingController(text: 'https://');
        final url = await showDialog<String>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(tr('Chia sẻ website')),
            content: TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.url, onSubmitted: (v) => Navigator.pop(d, v)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
              FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Chia sẻ'))),
            ],
          ),
        );
        final u = (url ?? '').trim();
        if (u.isNotEmpty && u != 'https://') room.openWeb(u.startsWith('http') ? u : 'https://$u');
      case 'web_close':
        room.closeWeb();
      case 'mute_all':
        room.muteAll();
        call.hostMuteOthers();
      case 'clear':
        room.clearStage();
      case 'unstar':
        room.setStar(null);
    }
  }

  /// Chia sẻ màn hình (máy tính): chọn màn hình / cửa sổ rồi gửi; bấm lại để dừng.
  Future<void> _toggleShare(CallService call) async {
    _poke();
    if (call.localScreen != null) {
      await call.stopScreenShare();
      return;
    }
    if (!meetPerm(call, 'share')) {
      meetToast(context, tr('Chủ trì đang tắt quyền chia sẻ màn hình'));
      return;
    }
    if (!call.mayPresent) {
      meetToast(context, tr('Chỉ ngôi sao của cuộc họp được trình chiếu'));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final id = await showDialog<String>(context: context, builder: (_) => const ScreenPicker());
    if (id == null || !mounted) return;
    final err = await call.startScreenShare(id);
    if (err != null) messenger.showSnackBar(toast(Text(err)));
    // Màn hình của mình tự ghim (bỏ dấu "đã bỏ ghim" cũ).
    if (mounted) setState(() => _dismissedScreen = null);
  }

  /// Thành viên nhóm chưa vào cuộc gọi nhóm (nhóm đông thì chỉ hiện 50 người đầu).
  List<MmUser> _notJoined(AppState app, CallService call) {
    final ch = call.channelId;
    if (ch == null) return const [];
    final inCall = {app.me?.id, for (final p in call.participants) p.userId};
    return [
      for (final id in app.knownMemberIds(ch) ?? const <String>[])
        if (!inCall.contains(id) && app.users[id] != null && app.users[id]!.deleteAt == 0 && !app.users[id]!.isBot) app.users[id]!,
    ].take(50).toList();
  }

  /// Danh sách người tham gia (cập nhật trực tiếp).
  // ---------------------------------------------------------------- app Họp: cột bên phải, bố cục, xin vào

  /// Cột bên phải (máy tính): Mọi người / Tin nhắn trong cuộc họp / Thông tin cuộc họp.
  /// Mở / thu một tab của panel bên phải (máy tính); nhớ tab đang mở cho lần họp sau.
  void _openPanel(_MeetPanel p) {
    setState(() => _panel = p);
    if (_panel != _MeetPanel.none) MeetPanelPrefs.save(tab: _panel.name);
  }

  /// Các tab của ⋯ (Sếp 2026-11-20): Tương tác (trang của mọi người), Thành viên, Màn hình, Chat (thảo luận nhóm), AI.
  List<(_MeetPanel, IconData, String, String?)> _moreTabs(AppState app, CallService call) {
    final room = _room;
    final ai = call.channelId != null && app.channels[call.channelId] != null && app.showsAiFor(app.channels[call.channelId]!);
    final chatUnread = call.channelId == null ? 0 : app.unreadOf(call.channelId!);
    final humans = {for (final p in call.participants) if (!p.userId.contains(':')) p.userId}..remove(app.me?.id);
    final screens = call.participants.where((p) => p.userId.startsWith('device:')).length;
    return [
      if (call.liveKit && call.scribeAvailable) (_MeetPanel.pages, Icons.dashboard_customize_outlined, tr('Tương tác'), null),
      (_MeetPanel.people, Icons.people_outline_rounded, tr('Thành viên'), room != null && room.knocks.isNotEmpty && _isHost(app, call) ? '!' : '${humans.length + 1}'),
      (_MeetPanel.screens, Icons.tv_rounded, tr('Màn hình'), screens > 0 ? '$screens' : null),
      if (call.channelId != null) (_MeetPanel.chat, Icons.forum_outlined, tr('Chat'), chatUnread > 0 ? (chatUnread > 99 ? '99+' : '$chatUnread') : null),
      if (ai || (call.meeting && call.scribeAvailable)) (_MeetPanel.ai, Icons.auto_awesome_outlined, tr('AI'), null),
    ];
  }

  /// Nội dung một tab của ⋯ (cột phải máy tính / bảng kéo lên điện thoại). [close]: đóng bảng (điện thoại).
  Widget _moreBody(AppState app, CallService call, _MeetPanel p, {VoidCallback? close}) => switch (p) {
        _MeetPanel.pages => PagesPane(
            key: const ValueKey('pages-pane'),
            call: call,
            panel: true,
            apps: _pageApps(app, call),
            shareScreen: CallService.canShareScreen && (call.localScreen != null || meetPerm(call, 'share')) ? () => _toggleShare(call) : null,
          ),
        _MeetPanel.screens => _screensTab(app, call, close),
        _MeetPanel.chat => ChatPage(key: ValueKey('meetchat:${call.channelId}'), channelId: call.channelId!, embedded: true, showHeader: false),
        _MeetPanel.ai => _aiBody(app, call),
        _ => _membersTab(app, call, close),
      };

  /// Bấm ⋯: máy tính mở / thu cột phải (tab gần nhất); điện thoại mở bảng kéo lên.
  void _openMore(AppState app, CallService call) {
    if (!isDesktop) {
      _moreSheet(app, call);
      return;
    }
    if (_panel != _MeetPanel.none) return setState(() => _panel = _MeetPanel.none);
    final tabs = [for (final t in _moreTabs(app, call)) t.$1];
    final last = _MeetPanel.values.where((p) => p.name == MeetPanelPrefs.tab).firstOrNull;
    _openPanel(last != null && tabs.contains(last) ? last : tabs.first);
  }

  /// Điện thoại: ⋯ là bảng kéo lên với các tab như cột phải của máy tính.
  Future<void> _moreSheet(AppState app, CallService call, {_MeetPanel? tab}) {
    final tabs = _moreTabs(app, call);
    final i = tab == null ? 0 : tabs.indexWhere((t) => t.$1 == tab).clamp(0, tabs.length - 1);
    _hide?.cancel();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBg,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .86,
        child: DefaultTabController(
          length: tabs.length,
          initialIndex: i,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: _grey,
              indicatorColor: const Color(0xFF2BB3A3),
              dividerColor: Colors.white12,
              tabs: [
                for (final (_, icon, label, badge) in tabs)
                  Tab(height: 46, child: Badge(isLabelVisible: badge != null, label: Text(badge ?? ''), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)]))),
              ],
            ),
            Expanded(child: TabBarView(children: [for (final t in tabs) _moreBody(app, call, t.$1, close: () => Navigator.pop(ctx))])),
          ]),
        ),
      ),
    );
  }

  Widget _sidePanel(AppState app, CallService call) {
    final tabs = _moreTabs(app, call);
    final cur = _panel == _MeetPanel.info ? _MeetPanel.people : _panel;
    // Hàng tab trên cùng của cột phải (mở bằng ⋯), nút đóng ở cuối.
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 2, 0),
      child: Row(children: [
        for (final (p, icon, label, badge) in tabs)
          Expanded(
            child: InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              onTap: () => _openPanel(p),
              child: Container(
                padding: const EdgeInsets.fromLTRB(2, 7, 2, 6),
                decoration: BoxDecoration(
                  color: cur == p ? Colors.white.withValues(alpha: .07) : null,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                  border: Border(bottom: BorderSide(color: cur == p ? const Color(0xFF2BB3A3) : Colors.transparent, width: 2)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Badge(isLabelVisible: badge != null, label: Text(badge ?? ''), child: Icon(icon, size: 20, color: cur == p ? Colors.white : _grey)),
                  const SizedBox(height: 2),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cur == p ? Colors.white : _grey, fontSize: 11.5, fontWeight: cur == p ? FontWeight.w700 : FontWeight.w500)),
                ]),
              ),
            ),
          ),
        IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded, color: _grey, size: 20), onPressed: () => setState(() => _panel = _MeetPanel.none)),
      ]),
    );
    return Material(
      color: _panelBg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const Divider(height: 1, color: Colors.white12),
        Expanded(child: _moreBody(app, call, cur)),
      ]),
    );
  }

  Widget _panelHead(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
        child: Text(t.toUpperCase(), style: const TextStyle(color: _grey, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .4)),
      );

  /// Thông tin cuộc họp: mã / đường liên kết mời, link xem cho khách, nơi lưu tin nhắn.
  Widget _infoView(AppState app, CallService call) {
    final info = call.meetingInfo;
    final code = info?.code;
    final ch = call.channelId == null ? null : app.channels[call.channelId];
    const head = TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5);
    const sub = TextStyle(color: _grey, fontSize: 13.5, height: 1.4);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (code != null) ...[
        Text(tr('Thông tin tham gia'), style: head),
        const SizedBox(height: 8),
        MeetLinkBox(
          dark: true,
          room: MeetRoomInfo(code: code, url: meetLink(code), channelId: call.channelId ?? '', title: info?.title ?? '', creator: info?.creatorId ?? '', access: ''),
        ),
        const SizedBox(height: 18),
      ] else ...[
        Text(tr('Cuộc họp trong nhóm chat'), style: head),
        const SizedBox(height: 6),
        Text(tr('Thành viên nhóm "{0}" vào được từ thẻ cuộc họp trong chat.', [ch == null ? '' : app.channelTitle(ch)]), style: sub),
        const SizedBox(height: 18),
      ],
      Text(tr('Khách không có tài khoản'), style: head),
      const SizedBox(height: 6),
      Text(tr('Gửi liên kết xem trực tiếp: khách xem trình chiếu, nghe trợ lý và phụ đề ngay trên trình duyệt (chỉ xem, không nói được).'), style: sub),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
        onPressed: () => _copyLiveLink(app, call),
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: Text(tr('Sao chép liên kết xem')),
      ),
      const SizedBox(height: 18),
      Text(tr('Lưu lại'), style: head),
      const SizedBox(height: 6),
      Text(tr('Tin nhắn, bình chọn và ghi chép của trợ lý AI được lưu trong nhóm chat "{0}".', [ch == null ? '' : app.channelTitle(ch)]), style: sub),
    ]);
  }

  Future<void> _copyLiveLink(AppState app, CallService call) async {
    final ch = call.channelId;
    if (ch == null) return;
    try {
      final r = await http.post(Uri.parse('$kPushUrl/meet/$ch/live'),
          headers: {'Authorization': 'Bearer ${app.token}', 'X-MM-Server': kServerUrl, 'User-Agent': kUserAgent}).timeout(const Duration(seconds: 15));
      final url = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['url'] as String?;
      if (r.statusCode != 200 || url == null) throw Exception('HTTP ${r.statusCode}');
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) meetToast(context, tr('Đã sao chép liên kết xem trực tiếp'));
    } catch (e) {
      if (mounted) meetToast(context, tr('Không lấy được liên kết xem: {0}', [e]));
    }
  }

  /// Điện thoại: thông tin cuộc họp trong bảng dưới.
  Future<void> _infoSheet(AppState app, CallService call) async {
    if (isDesktop) {
      setState(() => _panel = _MeetPanel.info);
      return;
    }
    _hide?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panelBg,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Cài đặt'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(height: MediaQuery.sizeOf(ctx).height * .72, child: _settingsView(app, call, close: () => Navigator.pop(ctx))),
          ]),
        ),
      ),
    );
    _poke();
  }

  /// Người tạo vào một mình: báo cuộc họp đã sẵn sàng kèm đường liên kết để mời.
  void _showReady(CallService call) {
    // Máy tính, cửa sổ đủ rộng: mở Cài đặt (liên kết mời) ở cột bên phải; hẹp thì báo bằng thông báo như điện thoại.
    if (isDesktop && _screenW >= 1000) {
      setState(() => _panel = _MeetPanel.info);
      return;
    }
    final code = call.meetingInfo?.code;
    if (code == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 10),
      content: Text(tr('Cuộc họp của bạn đã sẵn sàng. Mã: {0}', [code])),
      action: SnackBarAction(
        label: tr('Sao chép liên kết'),
        onPressed: () => Clipboard.setData(ClipboardData(text: meetLink(code))),
      ),
    ));
  }

  Future<void> _pickLayout() async {
    _hide?.cancel();
    final v = await showDialog<MeetLayout>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: _panelBg,
        title: Text(tr('Đổi bố cục'), style: const TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final l in MeetLayout.values)
            ListTile(
              leading: Icon(l.icon, color: Colors.white),
              title: Text(l.label, style: const TextStyle(color: Colors.white)),
              subtitle: Text(l.hint, style: const TextStyle(color: _grey, fontSize: 12.5)),
              trailing: l == _layout ? const Icon(Icons.check_rounded, color: _blue) : null,
              onTap: () => Navigator.pop(d, l),
            ),
        ]),
      ),
    );
    if (v != null && mounted && _localChange(context.read<AppState>().calls)) setState(() => _layout = v);
    _poke();
  }

  Future<void> _askUnmute(CallService call, String by) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.mic_none_rounded),
        title: Text(tr('{0} mời bạn bật mic', [by])),
        content: Text(tr('Mic của bạn đang tắt. Chủ trì không tự bật được mic của bạn; bấm "Bật mic" nếu bạn muốn nói.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Để sau'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Bật mic'))),
        ],
      ),
    );
    if (yes == true && call.muted) call.toggleMute();
  }

  Widget _knockCard(AppState app, MeetRoom room) {
    final k = room.knocks.first;
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _Face(userId: k.userId, name: k.name, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                room.knocks.length > 1 ? tr('{0} và {1} người khác muốn tham gia', [k.name, room.knocks.length - 1]) : tr('{0} muốn tham gia cuộc họp này', [k.name]),
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (room.knocks.length > 1)
              TextButton(onPressed: () => setState(() => _panel = _MeetPanel.people), child: Text(tr('Xem tất cả'))),
            TextButton(onPressed: () => _admit(app, room, k, false), child: Text(tr('Từ chối'))),
            TextButton(onPressed: () => _admit(app, room, k, true), child: Text(tr('Cho vào'))),
          ]),
        ]),
      ),
    );
  }

  Future<void> _admit(AppState app, MeetRoom room, MeetKnock k, bool allow) async {
    setState(() => room.knocks.remove(k));
    try {
      await MeetRoomsApi(app.token).admit(k.code, k.req, allow);
    } catch (e) {
      if (mounted) meetToast(context, tr('Không gửi được: {0}', [e]));
    }
  }

  /// Danh sách người trong cuộc họp (mình trước), thao tác của chủ phòng với từng người.
  List<Widget> _peopleRows(AppState app, CallService call) {
    final people = call.participants;
    final groups = <String, List<CallParticipant>>{};
    for (final p in people) {
      if (p.userId.isEmpty || p.userId.startsWith('device:') || p.userId.startsWith('agent:')) continue;
      groups.putIfAbsent(p.userId, () => []).add(p);
    }
    // Máy khác của chính mình gộp vào dòng của mình.
    final mine = groups.remove(app.me?.id) ?? const <CallParticipant>[];
    String kindName(String k) => switch (k) {
          'phone' => tr('điện thoại'),
          'tablet' => tr('máy tính bảng'),
          'desktop' => tr('máy tính'),
          'web' => tr('trình duyệt'),
          _ => tr('máy khác'),
        };
    final myName = app.me?.displayName ?? '';
    Widget row({
      required String? userId,
      required String name,
      required bool muted,
      required bool speaking,
      required bool video,
      bool screen = false,
      bool hand = false,
      String quality = '',
    }) =>
        ListTile(
          leading: _Face(userId: userId, name: name, size: 40),
          title: Row(children: [
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
            if (call.liveKit && userId != null && userId == call.roomHost) _roleBadge(tr('CHỦ TRÌ'), const Color(0xFFFFD36B), const Color(0xFF3D3010)),
            if (call.liveKit && userId != null && call.roomCohosts.contains(userId))
              _roleBadge(tr('PHÓ PHÒNG'), const Color(0xFF9CC2FF), const Color(0xFF16294A)),
          ]),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (quality.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 8), child: MeetSignalBadge(quality: quality, size: 14)),
              if (hand) Padding(padding: const EdgeInsets.only(right: 10), child: MeetHandBadge(order: userId == null ? null : meetHandOrder(call, userId), size: 20)),
              if (screen) const Padding(padding: EdgeInsets.only(right: 10), child: Icon(Icons.present_to_all, color: _blue, size: 20)),
              Icon(video ? Icons.videocam : Icons.videocam_off, color: video ? Colors.white : _grey, size: 20),
              const SizedBox(width: 10),
              Icon(
                muted ? Icons.mic_off : (speaking ? Icons.graphic_eq : Icons.mic),
                color: muted ? _red : (speaking ? _blue : Colors.white),
                size: 20,
              ),
              // Cuộc họp LiveKit: chủ trì / phó phòng điều khiển ở SFU (relay kiểm quyền).
              if (call.liveKit && userId != null && userId != app.me?.id && call.canModerate)
                _moderateMenu(app, call, userId, name, screen: screen)
              // Chủ phòng: thao tác với người này (tắt mic, mời bật mic, ngôi sao, mời chia sẻ màn hình).
              else if (_room != null && userId != null && userId != app.me?.id && _isHost(app, call))
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                  color: _panelBg,
                  onSelected: (a) {
                    final r = _room!;
                    switch (a) {
                      case 'mute':
                        r.mute(userId);
                        call.hostMute(userId);
                      case 'unmute':
                        r.askUnmute(userId);
                      case 'star':
                        r.setStar(r.star == userId ? null : userId);
                      case 'screen':
                        r.askScreen(userId);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'mute', child: Text(tr('Tắt mic'), style: const TextStyle(color: Colors.white))),
                    PopupMenuItem(value: 'unmute', child: Text(tr('Mời bật mic'), style: const TextStyle(color: Colors.white))),
                    PopupMenuItem(
                        value: 'star',
                        child: Text(_room!.star == userId ? tr('Bỏ ngôi sao') : tr('Đưa lên ngôi sao'),
                            style: const TextStyle(color: Colors.white))),
                    PopupMenuItem(value: 'screen', child: Text(tr('Mời chia sẻ màn hình'), style: const TextStyle(color: Colors.white))),
                  ],
                ),
            ],
          ),
        );
    return [
      row(
        userId: app.me?.id,
        name: [
          myName.isEmpty ? tr('Bạn') : tr('{0} (Bạn)', [myName]),
          if (mine.isNotEmpty) '· ${tr('{0} thiết bị', [mine.length + 1])}: ${[kindName(isDesktop ? 'desktop' : 'phone'), for (final p in mine) kindName(p.kind)].join(', ')}',
        ].join(' '),
        muted: call.muted,
        speaking: call.meSpeaking && !call.muted,
        video: call.camera,
      ),
      // Mỗi người một dòng; vào bằng nhiều máy thì ghi số thiết bị (vd. "2 thiết bị: máy tính, điện thoại").
      // Màn hình phòng họp (device:) ở tab Màn hình; trợ lý (agent:) không hiện.
      for (final g in groups.values)
        row(
          userId: g.first.userId,
          name: [
            _nameOf(app, g.first.userId),
            if (g.length > 1) '· ${tr('{0} thiết bị', [g.length])}: ${[for (final p in g) kindName(p.kind)].join(', ')}',
          ].join(' '),
          muted: !g.any((p) => p.unmuted),
          speaking: g.any((p) => p.speaking && p.unmuted),
          video: g.any((p) => p.video),
          screen: g.any((p) => p.screen),
          hand: g.any((p) => p.raisedHand),
          quality: g.first.quality,
        ),
      // Gọi nhóm: thành viên chưa vào (kiểu WhatsApp: "Đang gọi…" / "Chưa tham gia").
      if (call.groupCall)
        for (final u in _notJoined(app, call))
          ListTile(
            leading: Opacity(opacity: .55, child: _Face(userId: u.id, name: u.displayName, size: 40)),
            title: Text(u.displayName,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
            trailing: Text(
              call.phase == CallPhase.outgoing ? tr('Đang gọi…') : tr('Chưa tham gia'),
              style: const TextStyle(color: _grey, fontSize: 13),
            ),
          ),
    ];
  }

  void _showPeople(AppState app, CallService call) {
    _hide?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ListenableBuilder(
        listenable: call,
        builder: (ctx, _) {
          final people = call.participants;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Text(
                      tr('Người tham gia ({0})', [people.length + 1]),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ..._inviteButtons(call),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ..._peopleRows(app, call),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(_poke);
  }
}

/// Dữ liệu một ô: một người (camera hoặc ảnh đại diện) hoặc một màn hình đang chia sẻ.
class _TileData {
  final String key;
  final String? userId;
  final String name;
  final MediaStream? stream;
  final String? trackId;
  final bool mirror;
  final bool muted;
  final bool speaking;
  final bool screen;
  final bool raisedHand;
  /// Chất lượng mạng của người này (LiveKit), '' = không hiện.
  final String quality;
  /// Ô không phải video (vd. bài trình chiếu tài liệu): [compact] = ô nhỏ trong dải.
  final Widget Function(bool compact)? custom;
  const _TileData({
    required this.key,
    required this.userId,
    required this.name,
    this.stream,
    this.trackId,
    this.mirror = false,
    this.muted = false,
    this.speaking = false,
    this.screen = false,
    this.raisedHand = false,
    this.quality = '',
    this.custom,
  });
}

class _Tile extends StatelessWidget {
  final _TileData data;
  final bool pinned;
  final bool small;
  final VoidCallback onTap;
  const _Tile({super.key, required this.data, required this.pinned, required this.small, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = data;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: d.screen ? Colors.black : _tileBg,
          borderRadius: BorderRadius.circular(12),
          // Viền xanh khi đang nói.
          border: Border.all(color: d.speaking ? _blue : Colors.transparent, width: 3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              fit: StackFit.expand,
              children: [
                if (d.custom != null)
                  d.custom!(small)
                else if (d.stream != null)
                  CallVideo(stream: d.stream!, trackId: d.trackId, mirror: d.mirror, contain: d.screen)
                else
                  Center(
                    child: _Face(
                      userId: d.userId,
                      name: d.name,
                      size: (math.min(box.maxWidth, box.maxHeight) * .4).clamp(32.0, 128.0),
                    ),
                  ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (d.muted) ...[
                                Icon(Icons.mic_off, color: Colors.white, size: small ? 13 : 16),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  d.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white, fontSize: small ? 12 : 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (d.speaking)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Color(0xFF1A73E8), shape: BoxShape.circle),
                      child: const Icon(Icons.graphic_eq, color: Colors.white, size: 14),
                    ),
                  ),
                if (pinned || d.raisedHand || d.quality.isNotEmpty)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Row(
                      children: [
                        MeetSignalBadge(quality: d.quality, size: 14),
                        if (pinned) const Icon(Icons.push_pin, color: Colors.white, size: 18),
                        if (d.raisedHand) MeetHandBadge(order: d.userId == null ? null : meetHandOrder(context.read<AppState>().calls, d.userId!), size: 18),
                      ],
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

/// Ảnh đại diện trong ô khi tắt camera: ảnh hồ sơ nếu có, không thì hình tròn màu kèm chữ cái đầu.
class _Face extends StatelessWidget {
  final String? userId;
  final String name;
  final double size;
  const _Face({required this.userId, required this.name, required this.size});

  static const _colors = [
    Color(0xFF1A73E8),
    Color(0xFFE8710A),
    Color(0xFF188038),
    Color(0xFF9334E6),
    Color(0xFFD93025),
    Color(0xFF129EAF),
    Color(0xFFE52592),
    Color(0xFF795548),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final uid = userId;
    if (uid != null && uid.isNotEmpty && (app.users[uid]?.lastPictureUpdate ?? 0) > 0) {
      return Avatar(userId: uid, name: name, size: size, status: false);
    }
    final key = (uid ?? name).codeUnits.fold<int>(0, (a, b) => a + b);
    final shown = uid != null && app.users[uid] != null ? app.users[uid]!.displayName : name;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _colors[key % _colors.length]),
      child: Text(
        initials(shown).characters.first,
        style: TextStyle(color: Colors.white, fontSize: size * .45, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Khung video của một track (mỗi ô có renderer riêng).
class CallVideo extends StatefulWidget {
  final MediaStream stream;
  final String? trackId;
  final bool mirror;
  final bool contain;
  const CallVideo({super.key, required this.stream, this.trackId, this.mirror = false, this.contain = false});
  @override
  State<CallVideo> createState() => _CallVideoState();
}

class _CallVideoState extends State<CallVideo> {
  final _r = RTCVideoRenderer();
  bool _ready = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _r.initialize().then((_) {
      if (_disposed) return;
      _ready = true;
      _attach();
      if (mounted) setState(() {});
    });
  }

  Future<void> _attach() async {
    try {
      // Luồng từ SFU gom mọi track của một người: chọn đúng track video (camera / màn hình).
      await _r.setSrcObject(stream: widget.stream, trackId: widget.trackId);
    } catch (e) {
      debugPrint('[calls] renderer: $e');
    }
  }

  @override
  void didUpdateWidget(covariant CallVideo old) {
    super.didUpdateWidget(old);
    if (_ready && (old.stream != widget.stream || old.trackId != widget.trackId)) _attach();
  }

  @override
  void dispose() {
    _disposed = true;
    _r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return RTCVideoView(
      _r,
      mirror: widget.mirror,
      objectFit: widget.contain
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }
}

/// Nút tròn của thanh điều khiển kiểu Meet.
class _MeetButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String tooltip;
  final String? badge;
  final VoidCallback onTap;
  const _MeetButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.iconColor = Colors.white,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: color,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(width: 52, height: 52, child: Icon(icon, color: iconColor, size: 24)),
              ),
            ),
            if (badge != null)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF1A73E8), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    badge!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String? label;
  final VoidCallback onTap;
  final double size;
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.iconColor = Colors.white,
    this.label,
    this.size = 70,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor, size: size * .45),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 10),
          Text(
            label!,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ],
    );
  }
}

/// "Đang kết nối lại…" khi mạng rớt / đổi mạng giữa cuộc gọi.
class ReconnectingChip extends StatelessWidget {
  const ReconnectingChip({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xE6302F33), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFDD663)),
        ),
        const SizedBox(width: 10),
        Text(tr('Đang kết nối lại…'), style: const TextStyle(color: Colors.white, fontSize: 14)),
      ]),
    );
  }
}

/// Chọn màn hình hoặc cửa sổ để chia sẻ (flutter_webrtc desktopCapturer, có ảnh xem trước).
class ScreenPicker extends StatefulWidget {
  const ScreenPicker({super.key});
  @override
  State<ScreenPicker> createState() => _ScreenPickerState();
}

class _ScreenPickerState extends State<ScreenPicker> {
  List<DesktopCapturerSource> _sources = [];
  SourceType _type = SourceType.Screen;
  String? _sel;
  String? _error;
  bool _loading = true;
  final List<StreamSubscription> _subs = [];
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    try {
      _subs.add(desktopCapturer.onThumbnailChanged.stream.listen((_) => mounted ? setState(() {}) : null));
      _subs.add(desktopCapturer.onNameChanged.stream.listen((_) => mounted ? setState(() {}) : null));
    } catch (_) {}
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        await desktopCapturer.updateSources(types: [_type]);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await desktopCapturer.getSources(types: [_type], thumbnailSize: ThumbnailSize(320, 180));
      if (!mounted) return;
      setState(() {
        _sources = list;
        _error = null;
        _loading = false;
        _sel = list.length == 1 ? list.first.id : (list.any((s) => s.id == _sel) ? _sel : null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = tr('Không lấy được danh sách màn hình. Kiểm tra quyền ghi màn hình của ứng dụng.');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tab(SourceType t, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _type == t,
            onSelected: (_) {
              if (_type == t) return;
              setState(() {
                _type = t;
                _sources = [];
                _sel = null;
              });
              _load();
            },
          ),
        );
    return AlertDialog(
      title: Text(tr('Chia sẻ màn hình')),
      content: SizedBox(
        width: 640,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [tab(SourceType.Screen, tr('Toàn màn hình')), tab(SourceType.Window, tr('Cửa sổ'))]),
          const SizedBox(height: 12),
          Expanded(
            child: _loading && _sources.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, textAlign: TextAlign.center))
                    : _sources.isEmpty
                        ? Center(child: Text(tr('Không có gì để chia sẻ')))
                        : GridView.count(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.25,
                            children: [
                              for (final s in _sources)
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => setState(() => _sel = s.id),
                                  onDoubleTap: () => Navigator.pop(context, s.id),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _sel == s.id ? const Color(0xFF1A73E8) : Colors.black12,
                                        width: _sel == s.id ? 2.5 : 1,
                                      ),
                                    ),
                                    child: Column(children: [
                                      Expanded(
                                        child: s.thumbnail == null
                                            ? const Center(child: Icon(Icons.desktop_windows_outlined, size: 40))
                                            : Image.memory(s.thumbnail!, fit: BoxFit.contain, gaplessPlayback: true),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                    ]),
                                  ),
                                ),
                            ],
                          ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: _sel == null ? null : () => Navigator.pop(context, _sel),
          child: Text(tr('Chia sẻ')),
        ),
      ],
    );
  }
}

/// Nút mở cột bên phải (góc phải thanh điều khiển của cuộc họp trên máy tính).
/// Dấu "Đang phiên âm" trên màn hình cuộc gọi (chủ phòng bật Thư ký Họp).
class _ScribeChip extends StatelessWidget {
  const _ScribeChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFE5484D), shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(tr('Đang phiên âm'), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      );
}
