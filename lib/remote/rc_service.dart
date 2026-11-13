// Điều khiển máy tính từ xa: xin điều khiển trong tin riêng 1-1 hoặc trong cuộc gọi (người kia bấm "Cho phép" mới bắt
// đầu), mời người khác điều khiển máy mình trong cuộc gọi (người được mời bấm "Đồng ý"), và điều khiển máy tính khác của
// chính mình (cùng tài khoản: máy kia tự đồng ý, vẫn hiện thanh đỏ "Dừng").
//
// Máy tính: trang điều khiển luôn mở ở cửa sổ riêng (tiến trình app khác, `--rc=`, xem rc_call.dart), không nằm trong
// cửa sổ chính hay giao diện cuộc gọi; điện thoại: trang toàn màn hình như cũ. Chia sẻ màn hình trong cuộc gọi và bị
// điều khiển là hai luồng chụp màn hình độc lập (hai kết nối WebRTC khác nhau), dùng cùng lúc được.
//
// Kiến trúc:
//   - Tín hiệu: WebSocket tới trạm của máy chủ chat (wss://<trạm>/rc/ws, flygo-chat-server relay/rc.mjs). Trạm chỉ chuyển
//     offer / answer / ICE giữa đúng hai kết nối của phiên, không lưu gì; tín hiệu không bao giờ thành tin nhắn chat.
//     Máy tính (cửa sổ chính) giữ kết nối này để nhận lời xin; điện thoại chỉ mở khi đang điều khiển.
//   - Hình + thao tác: WebRTC trực tiếp giữa hai máy (ICE / TURN như cuộc gọi: STUN/TURN của plugin Calls và TURN
//     của trạm). Máy bị điều khiển gửi một track video màn hình; thao tác đi qua data channel (rc_protocol.dart).
//   - Màn hình: máy bị điều khiển bắt đầu với màn hình chính (không hỏi), gửi danh sách màn hình qua data channel;
//     máy điều khiển chọn màn hình khác bất cứ lúc nào (["d", id]), máy bị điều khiển kiểm tra id rồi thay track.
//   - Máy bị điều khiển đổi thao tác sang SendInput (Windows) / CGEventPost (macOS) qua kênh flygo/remote_input.
//   - Hết phiên: máy điều khiển đăng một dòng nhật ký trong tin riêng (props.flygo_rc_log).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../calls/ringtones.dart';
import '../config.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import '../ui/common.dart' show hhmm;
import 'rc_call.dart';
import 'rc_consent.dart';
import 'rc_native.dart';
import 'rc_peer.dart';
import 'rc_protocol.dart';
import 'rc_signal.dart';

export 'rc_consent.dart' show RcPhase, RcRequestOutcome, RcConsent, RcConsentState;
export 'rc_call.dart' show RcDevice, RcPick, RcWindowJob;

const kRcLogProp = 'flygo_rc_log';

enum RcRole { none, controller, host }

class RemoteControlService extends ChangeNotifier {
  RemoteControlService._();
  static final instance = RemoteControlService._();

  // ---------------------------------------------------------------- móc giao diện (rc_ui.dart gắn vào)
  /// Hiện hộp thoại "`<Tên>` muốn điều khiển máy tính của bạn".
  void Function(RcConsent c)? showIncoming;
  /// Mở trang điều khiển (máy điều khiển).
  void Function()? openController;
  /// macOS: màn hình giải thích + xin quyền Trợ năng / Ghi màn hình; true khi đủ quyền.
  Future<bool> Function()? ensurePermissions;
  /// Báo ngắn cho người dùng (toast).
  void Function(String text)? toast;
  /// Máy tính: mở cửa sổ điều khiển riêng (tiến trình app khác) với tham số [rcWindowArgs].
  Future<void> Function(List<String> args)? openWindow;

  AppState? _app;
  RcSignal? _sig;
  ValueNotifier<AppState?>? _session;

  RcRole role = RcRole.none;
  RcPhase phase = RcPhase.idle;
  String? sid;
  String peerUserId = '';
  String peerName = '';
  String channelId = '';
  DateTime? startedAt;
  /// Kết quả lời xin (máy điều khiển) để trang điều khiển hiện lý do.
  RcRequestOutcome? outcome;
  /// Lý do kết thúc phiên (máy kia bấm Dừng, mất kết nối...).
  String? endReason;
  RcConsent? incoming;
  String _ref = '';
  Timer? _reqTimer;
  /// Phiên điều khiển máy tính khác của chính mình (không hỏi, không ghi nhật ký vào chat).
  bool own = false;
  /// Đường đi của lời xin / lời mời ("call": trong cuộc gọi nhóm / cuộc họp).
  String? _via;
  /// Tín hiệu đến trước khi kết nối WebRTC phía mình sẵn sàng (giữ lại, chạy sau).
  final List<Map<String, dynamic>> _early = [];
  bool _peerReady = false;
  /// Điện thoại đang trong cuộc gọi / đang mở danh sách máy tính: giữ kết nối tín hiệu (nhận lời mời, hỏi danh sách).
  bool _inCall = false;
  int _deviceViews = 0;
  Listenable? _calls;
  final Map<String, Completer<List<RcDevice>?>> _devAsk = {};

  // Máy điều khiển.
  RcViewerPeer? _viewer;
  RTCVideoRenderer? renderer;
  String remotePlatform = '';
  /// Màn hình của máy kia (máy kia gửi sau khi kết nối) và màn hình đang xem.
  List<RcDisplay> screens = const [];
  String screenId = '';
  /// Đã xin đổi sang màn hình này, đang chờ máy kia xác nhận.
  String? switchingTo;

  // Máy bị điều khiển.
  RcHostPeer? _host;
  RcInjector? _injector;
  RcRateLimiter _limiter = RcRateLimiter();
  /// Màn hình của máy này (id nguồn chụp → màn hình gốc) và màn hình đang chia sẻ.
  List<({RcDisplay display, RcScreen screen})> _hostScreens = const [];
  String _hostScreenId = '';
  /// Màn hình được chọn trong lúc đang đổi màn hình khác (chỉ giữ lần chọn cuối).
  String? _queuedScreen;
  bool _switching = false;
  /// Phím tắt dừng đã đăng ký được.
  String hotkey = '';

  bool get busy => phase != RcPhase.idle;
  AppState? get app => _app;

  /// Máy này đang mời người khác điều khiển (chờ người kia trả lời) hoặc đang bị điều khiển.
  bool get sharingControl => role == RcRole.host && busy;
  /// Đang chờ người được mời trả lời.
  bool get inviting => role == RcRole.host && phase == RcPhase.requesting;

  /// Máy này đang mở kết nối nhận lời xin (máy tính Windows / macOS / Linux X11, cửa sổ chính).
  static bool get canBeControlled => RcNative.supported && !isChildWindow;

  /// Máy này mời người khác điều khiển được (máy tính, kể cả cửa sổ cuộc họp riêng; không phải cửa sổ điều khiển).
  static bool get canInvite => RcNative.supported && !kWindowRc;

  /// Gắn với phiên đăng nhập của cửa sổ chính (main.dart): đổi máy chủ / đăng xuất thì đóng kết nối cũ.
  void bind(ValueNotifier<AppState?> session) {
    if (_session != null) return;
    _session = session;
    session.addListener(_onSession);
    _onSession();
  }

  void _onSession() {
    final a = _session?.value;
    if (a == _app) return;
    if (_app != null) {
      if (busy) unawaited(stop(reason: 'logout'));
      _sig?.close();
      _sig = null;
    }
    _calls?.removeListener(_onCalls);
    _calls = null;
    _inCall = false;
    _app = a;
    if (a != null && canBeControlled) {
      _sig = _newSignal(a, keepAlive: true);
      unawaited(_sig!.connect());
    }
    // Điện thoại: trong cuộc gọi thì giữ kết nối tín hiệu để nhận lời mời điều khiển (máy tính: cửa sổ chính đã giữ).
    if (a != null && !isDesktop && !kIsWeb) {
      _calls = a.calls..addListener(_onCalls);
      _onCalls();
    }
  }

  void _onCalls() {
    final a = _app;
    final want = a != null && a.calls.busy;
    if (want == _inCall) return;
    _inCall = want;
    if (a == null) return;
    if (want) {
      if (_sig == null) {
        _sig = _newSignal(a, keepAlive: true);
        unawaited(_sig!.connect());
      }
    } else {
      _maybeCloseSignal();
    }
  }

  /// Điện thoại / cửa sổ phụ: không giữ kết nối tín hiệu khi không cần.
  void _maybeCloseSignal() {
    if (canBeControlled || busy || _inCall || _deviceViews > 0) return;
    _sig?.close();
    _sig = null;
  }

  RcSignal _newSignal(AppState a, {required bool keepAlive}) => RcSignal(
        token: a.token,
        server: kServerUrl,
        controllable: canBeControlled,
        keepAlive: keepAlive,
        // Lời mời điều khiển chỉ đến cửa sổ chính (máy tính) / app điện thoại, không đến cửa sổ phụ.
        caps: isChildWindow ? const [] : const ['invite'],
        onMessage: _onSignal,
        onDisconnected: () {
          // Mất kết nối tín hiệu khi đang chờ / đang kết nối: phiên không thể tiếp tục.
          if (phase == RcPhase.requesting || phase == RcPhase.ringing || (phase == RcPhase.connecting && !_peerReady)) {
            incoming?.cancel();
            _finish(remote: false, reason: 'signal');
          }
          for (final c in _devAsk.values) {
            if (!c.isCompleted) c.complete(null);
          }
          _devAsk.clear();
        },
      );

  // ---------------------------------------------------------------- máy điều khiển

  /// Máy tính (không phải cửa sổ điều khiển): trang điều khiển mở ở cửa sổ riêng.
  bool get _useWindow => isDesktop && !kWindowRc && openWindow != null;

  /// Xin điều khiển máy của [otherUserId] trong tin riêng [channel] (hoặc kênh của cuộc gọi, [via] = "call"). Máy tính:
  /// mở cửa sổ điều khiển riêng (cửa sổ đó gửi lời xin); điện thoại: mở trang điều khiển ngay (trạng thái chờ).
  Future<void> request(String channel, String otherUserId, {String? via, String? name}) async {
    final a = _app;
    if (a == null) return;
    final shown = (name != null && name.isNotEmpty) ? name : (a.users[otherUserId]?.displayName ?? '');
    if (_useWindow) {
      await openWindow!(rcWindowArgs(RcWindowJob(channelId: channel, userId: otherUserId, via: via, name: shown), server: kServerUrl));
      return;
    }
    if (busy) {
      toast?.call(tr('Đang có một phiên điều khiển khác'));
      return;
    }
    _begin(RcRole.controller, RcPhase.requesting, channel: channel, user: otherUserId, name: shown, via: via);
    openController?.call();
    final sig = _sig ??= _newSignal(a, keepAlive: false);
    if (!await sig.connect()) return _outcome(RcRequestOutcome.noStation);
    if (phase != RcPhase.requesting) return;
    sig.send({'t': 'req', 'to': otherUserId, 'channel_id': channel, 'via': ?via, 'ref': _ref});
    _armTimeout();
  }

  /// Điều khiển máy tính khác của chính mình ([d] trong danh sách "Máy tính"): máy kia tự đồng ý.
  Future<void> requestOwn(RcDevice d) async {
    final a = _app;
    if (a == null || !d.canControl) return;
    if (_useWindow) {
      await openWindow!(rcWindowArgs(RcWindowJob(device: d.cid, name: d.name), server: kServerUrl));
      return;
    }
    await _requestOwn(d.cid, d.name);
  }

  Future<void> _requestOwn(String cid, String name) async {
    final a = _app;
    if (a == null) return;
    if (busy) {
      toast?.call(tr('Đang có một phiên điều khiển khác'));
      return;
    }
    _begin(RcRole.controller, RcPhase.requesting, channel: '', user: a.me?.id ?? '', name: name.isEmpty ? tr('Máy tính của bạn') : name);
    own = true;
    openController?.call();
    final sig = _sig ??= _newSignal(a, keepAlive: false);
    if (!await sig.connect()) return _outcome(RcRequestOutcome.noStation);
    if (phase != RcPhase.requesting) return;
    sig.send({'t': 'req', 'own': true, 'to': a.me?.id ?? '', 'device': cid, 'ref': _ref});
    _armTimeout();
  }

  /// Cửa sổ điều khiển (máy tính) vừa mở: làm việc [j] (xin điều khiển / nhận phiên đã đồng ý / máy của chính mình).
  Future<void> runWindowJob(RcWindowJob j) async {
    if (j.device != null) return _requestOwn(j.device!, j.name);
    if (j.sid != null) return _claim(j);
    return request(j.channelId, j.userId, via: j.via, name: j.name);
  }

  /// Nhận phiên mà cửa sổ chính đã đồng ý lời mời (trạm chờ kết nối mới của cùng người dùng "claim").
  Future<void> _claim(RcWindowJob j) async {
    final a = _app;
    final s = j.sid;
    if (a == null || s == null) return;
    _begin(RcRole.controller, RcPhase.connecting, channel: j.channelId, user: j.userId, name: j.name, via: j.via);
    sid = s;
    outcome = RcRequestOutcome.accepted;
    notifyListeners();
    openController?.call();
    final sig = _sig ??= _newSignal(a, keepAlive: false);
    if (!await sig.connect()) return _finish(remote: true, reason: 'signal', notifyPeer: false);
    if (sid != s) return;
    sig.send({'t': 'claim', 'sid': s});
    _reqTimer?.cancel();
    _reqTimer = Timer(const Duration(seconds: 30), () {
      if (sid == s && !_peerReady) _finish(remote: true, reason: 'network');
    });
  }

  /// Mời [otherUserId] (trong cuộc gọi ở kênh [channel]) điều khiển máy này. Mình đã đồng ý khi mời; người kia bấm
  /// "Đồng ý" là bắt đầu (thanh đỏ "Dừng" hiện như khi bị điều khiển).
  Future<void> invite(String channel, String otherUserId, {String? via, String? name}) async {
    final a = _app;
    if (a == null || !canInvite) return;
    if (busy) {
      toast?.call(tr('Đang có một phiên điều khiển khác'));
      return;
    }
    // macOS: xin quyền trước để người được mời không phải chờ.
    if (!(await RcNative.permissions()).ok) {
      final ok = RcNative.isMac && await (ensurePermissions?.call() ?? Future.value(false));
      if (!ok) {
        toast?.call(tr('Máy này chưa cấp quyền điều khiển máy tính'));
        return;
      }
    }
    if (busy) return;
    final shown = (name != null && name.isNotEmpty) ? name : (a.users[otherUserId]?.displayName ?? '');
    _begin(RcRole.host, RcPhase.requesting, channel: channel, user: otherUserId, name: shown, via: via);
    final sig = _sig ??= _newSignal(a, keepAlive: false);
    if (!await sig.connect()) return _inviteFailed(RcRequestOutcome.noStation);
    if (phase != RcPhase.requesting || role != RcRole.host) return;
    sig.send({'t': 'invite', 'to': otherUserId, 'channel_id': channel, 'via': ?via, 'ref': _ref});
    toast?.call(tr('Đã mời {0} điều khiển máy tính của bạn', [peerName]));
    _armTimeout();
  }

  void _begin(RcRole r, RcPhase p, {required String channel, required String user, required String name, String? via}) {
    role = r;
    phase = p;
    channelId = channel;
    peerUserId = user;
    peerName = name.isEmpty ? tr('Người dùng') : name;
    own = false;
    _via = via;
    outcome = null;
    endReason = null;
    startedAt = null;
    sid = null;
    remotePlatform = '';
    screens = const [];
    screenId = '';
    switchingTo = null;
    _early.clear();
    _peerReady = false;
    _ref = '${DateTime.now().microsecondsSinceEpoch}';
    notifyListeners();
  }

  void _armTimeout() {
    _reqTimer?.cancel();
    _reqTimer = Timer(const Duration(seconds: 75), () {
      if (phase != RcPhase.requesting) return;
      role == RcRole.host ? _inviteFailed(RcRequestOutcome.timeout) : _outcome(RcRequestOutcome.timeout);
    });
  }

  /// Lời mời không thành: báo lý do, kết thúc.
  void _inviteFailed(RcRequestOutcome o) {
    final name = peerName;
    toast?.call(switch (o) {
      RcRequestOutcome.declined => tr('{0} đã từ chối', [name]),
      RcRequestOutcome.timeout => tr('{0} không trả lời', [name]),
      RcRequestOutcome.unsupported => tr('{0} chưa nhận được lời mời điều khiển (cần cập nhật app)', [name]),
      RcRequestOutcome.busy => tr('Máy kia đang trong một phiên điều khiển khác'),
      RcRequestOutcome.noStation => tr('Máy chủ chat này chưa hỗ trợ điều khiển máy tính'),
      _ => tr('Không gửi được lời mời điều khiển. Thử lại sau.'),
    });
    _finish(remote: false, reason: o.name, notifyPeer: sid != null);
  }

  // ---------------------------------------------------------------- danh sách "Máy tính" của chính mình

  /// Trang "Máy tính" đang mở: giữ kết nối tín hiệu (điện thoại) cho tới khi đóng trang.
  void holdDevices(bool on) {
    _deviceViews = (_deviceViews + (on ? 1 : -1)).clamp(0, 1 << 20);
    if (!on) _maybeCloseSignal();
  }

  /// Máy tính của chính mình (đang online và đã từng online); null nếu trạm không trả lời / chưa có trạm.
  Future<List<RcDevice>?> myDevices() => _askDevices({'t': 'devices'});

  /// Xoá một máy (ngoại tuyến) khỏi danh sách; trả về danh sách mới.
  Future<List<RcDevice>?> forgetDevice(String deviceId) => _askDevices({'t': 'forget', 'device_id': deviceId});

  Future<List<RcDevice>?> _askDevices(Map<String, dynamic> m) async {
    final a = _app;
    if (a == null) return null;
    final sig = _sig ??= _newSignal(a, keepAlive: false);
    if (!await sig.connect()) return null;
    final ref = 'd${DateTime.now().microsecondsSinceEpoch}';
    final c = _devAsk[ref] = Completer<List<RcDevice>?>();
    sig.send({...m, 'ref': ref});
    try {
      return await c.future.timeout(const Duration(seconds: 8), onTimeout: () => null);
    } finally {
      _devAsk.remove(ref);
    }
  }

  void _outcome(RcRequestOutcome o) {
    outcome = o;
    if (o != RcRequestOutcome.accepted) _finish(remote: false, reason: o.name, notifyPeer: sid != null);
  }

  Future<void> _onAccepted(Map<String, dynamic> m) async {
    final a = _app;
    if (a == null) return;
    _reqTimer?.cancel();
    outcome = RcRequestOutcome.accepted;
    phase = RcPhase.connecting;
    remotePlatform = '${m['platform'] ?? ''}';
    notifyListeners();
    final r = RTCVideoRenderer();
    await r.initialize();
    final ice = await a.calls.peerIceServers();
    if (phase != RcPhase.connecting || role != RcRole.controller) {
      await r.dispose();
      return;
    }
    renderer = r;
    final v = _viewer = RcViewerPeer(
      iceServers: ice,
      renderer: r,
      onSignal: _sendSig,
      onState: (ok) => ok ? _connected() : stop(reason: 'network'),
      onHostMessage: _onHostMessage,
    );
    try {
      await v.start();
    } catch (e) {
      debugPrint('[rc] viewer: $e');
      return stop(reason: 'error');
    }
    if (_viewer != v) return;
    _ready();
    notifyListeners();
  }

  /// Gửi một thao tác sang máy kia.
  void sendInput(RcInput i) => _viewer?.send(i.encode());

  /// Có thể gửi thao tác chưa (data channel đã mở).
  bool get canSend => _viewer?.canSend ?? false;

  /// Xin máy kia chia sẻ màn hình [id] (một màn hình trong [screens]).
  void selectScreen(String id) {
    if (role != RcRole.controller || id == screenId || !screens.any((d) => d.id == id)) return;
    switchingTo = id;
    sendInput(RcSelectScreen(id));
    notifyListeners();
  }

  void _onHostMessage(String raw) {
    if (role != RcRole.controller) return;
    final m = RcHostMessage.decode(raw);
    if (m == null) return;
    screens = List.unmodifiable(m.screens);
    screenId = m.current;
    if (switchingTo == m.current || !screens.any((d) => d.id == switchingTo)) switchingTo = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- máy bị điều khiển

  void _onRing(Map<String, dynamic> m) {
    final s = '${m['sid'] ?? ''}';
    if (s.isEmpty) return;
    if (busy || !canBeControlled) {
      _sig?.send({'t': 'decline', 'sid': s, 'reason': busy ? 'busy' : 'unsupported'});
      return;
    }
    final from = '${m['from'] ?? ''}';
    final known = _app?.users[from]?.displayName;
    _begin(RcRole.host, RcPhase.ringing,
        channel: '${m['channel_id'] ?? ''}', user: from, name: (known != null && known.isNotEmpty) ? known : '${m['from_name'] ?? ''}');
    sid = s;
    // Máy tính khác của chính mình (trạm chỉ ghép hai kết nối cùng tài khoản): tự đồng ý, không hỏi, không đổ chuông;
    // vẫn hiện thanh đỏ "Dừng" và phím tắt dừng.
    final me = _app?.me?.id;
    if (m['own'] == true && me != null && from == me) {
      own = true;
      unawaited(_hostAccepted(prompt: false));
      return;
    }
    final c = incoming = RcConsent(sid: s, fromUserId: peerUserId, fromName: peerName, channelId: channelId, onDone: _onConsent);
    // Đổ chuông như cuộc gọi đến, trừ khi tin riêng này đang tắt thông báo.
    if (!(_app?.notificationsOff(channelId) ?? false)) Ringtones.ring(channelId);
    notifyListeners();
    showIncoming?.call(c);
  }

  /// Lời mời điều khiển máy người khác (người kia đã đồng ý khi mời): hỏi "Đồng ý" / "Từ chối".
  void _onInvite(Map<String, dynamic> m) {
    final s = '${m['sid'] ?? ''}';
    if (s.isEmpty) return;
    if (busy) {
      _sig?.send({'t': 'decline', 'sid': s, 'reason': 'busy'});
      return;
    }
    final from = '${m['from'] ?? ''}';
    final known = _app?.users[from]?.displayName;
    _begin(RcRole.controller, RcPhase.ringing,
        channel: '${m['channel_id'] ?? ''}',
        user: from,
        name: (known != null && known.isNotEmpty) ? known : '${m['from_name'] ?? ''}',
        via: m['via'] == 'call' ? 'call' : null);
    sid = s;
    remotePlatform = '${m['platform'] ?? ''}';
    final c = incoming =
        RcConsent(sid: s, fromUserId: peerUserId, fromName: peerName, channelId: channelId, invite: true, onDone: _onConsent);
    if (!(_app?.notificationsOff(channelId) ?? false)) Ringtones.ring(channelId);
    notifyListeners();
    showIncoming?.call(c);
  }

  /// Đồng ý lời mời: máy tính (cửa sổ chính) giao phiên cho cửa sổ điều khiển riêng; điện thoại điều khiển ngay.
  Future<void> _inviteAccepted() async {
    final s = sid;
    if (s == null) return;
    if (rcInviteAcceptPlan(desktop: isDesktop && openWindow != null, controllerWindow: kWindowRc) == RcInviteAccept.handoff) {
      _sig?.send({'t': 'accept', 'sid': s, 'handoff': true, 'platform': RcSignal.platformName});
      final args = rcWindowArgs(RcWindowJob(channelId: channelId, userId: peerUserId, sid: s, via: _via, name: peerName), server: kServerUrl);
      // Cửa sổ này không còn giữ phiên (trạm chờ cửa sổ điều khiển nhận).
      sid = null;
      _finish(remote: false, reason: 'stopped', notifyPeer: false);
      await openWindow?.call(args);
      return;
    }
    phase = RcPhase.connecting;
    outcome = RcRequestOutcome.accepted;
    notifyListeners();
    _sig?.send({'t': 'accept', 'sid': s, 'platform': RcSignal.platformName});
    openController?.call();
    _reqTimer?.cancel();
    _reqTimer = Timer(const Duration(seconds: 30), () {
      if (sid == s && !_peerReady) _finish(remote: true, reason: 'network');
    });
  }

  /// Người dùng bấm Cho phép / Từ chối trên hộp thoại.
  void acceptIncoming() => incoming?.accept();
  void declineIncoming() => incoming?.decline();

  void _onConsent(RcConsent c) {
    Ringtones.stop();
    if (_finishing || c.sid != sid) return;
    switch (c.state) {
      case RcConsentState.accepted:
        unawaited(c.invite ? _inviteAccepted() : _hostAccepted());
      case RcConsentState.declined:
        _sig?.send({'t': 'decline', 'sid': c.sid});
        _finish(remote: false, reason: 'declined', notifyPeer: false);
      case RcConsentState.timedOut:
        _sig?.send({'t': 'decline', 'sid': c.sid, 'reason': 'timeout'});
        _finish(remote: false, reason: 'timeout', notifyPeer: false);
      case RcConsentState.cancelled:
        _finish(remote: true, reason: 'cancelled', notifyPeer: false);
      case RcConsentState.ringing:
    }
    incoming = null;
  }

  /// Bắt đầu bị điều khiển. [invited]: mình đã mời, người kia vừa đồng ý (trạm đã báo, không gửi accept).
  /// [prompt]: false với máy của chính mình (không ai ngồi trước máy để bấm cấp quyền: thiếu quyền thì dừng).
  Future<void> _hostAccepted({bool invited = false, bool prompt = true}) async {
    final a = _app, s = sid;
    if (a == null || s == null) return;
    phase = RcPhase.connecting;
    notifyListeners();
    if (!invited) _sig?.send({'t': 'accept', 'sid': s, 'platform': RcSignal.platformName});
    // macOS: cần quyền Trợ năng (điều khiển chuột / phím) và Ghi màn hình. Linux: máy chủ X thiếu XTest thì không
    // có gì để người dùng bật trong app, dừng luôn.
    if (!(await RcNative.permissions()).ok) {
      final ok = prompt && RcNative.isMac && await (ensurePermissions?.call() ?? Future.value(false));
      if (sid != s) return;
      if (!ok) return stop(reason: 'permission');
    }
    List<DesktopCapturerSource> sources;
    try {
      sources = await desktopCapturer.getSources(types: [SourceType.Screen], thumbnailSize: ThumbnailSize(320, 180));
    } catch (e) {
      debugPrint('[rc] sources: $e');
      return stop(reason: 'capture');
    }
    if (sid != s) return;
    if (sources.isEmpty) return stop(reason: 'capture');
    final (native, virt) = await RcNative.screens();
    // Bắt đầu với màn hình chính, không hỏi người dùng; máy điều khiển tự đổi màn hình khác.
    final list = rcDisplaysOf([for (final x in sources) x.id], native);
    final first = rcDefaultDisplay([for (final e in list) e.display]);
    if (first == null) return stop(reason: 'capture');
    final screen = list.firstWhere((e) => e.display.id == first.id).screen;
    _hostScreens = list;
    _hostScreenId = first.id;
    _queuedScreen = null;
    _switching = false;
    _injector = RcInjector(mac: RcNative.isMac, linux: RcNative.isLinux, screen: screen, virtualDesk: virt);
    _limiter = RcRateLimiter();
    final ice = await a.calls.peerIceServers();
    if (sid != s) return;
    final h = _host = RcHostPeer(
      iceServers: ice,
      sourceId: first.id,
      onSignal: _sendSig,
      onInput: _onInput,
      onOpen: _sendScreens,
      onState: (ok) => ok ? _connected() : stop(reason: 'network'),
    );
    try {
      await h.start();
    } catch (e) {
      debugPrint('[rc] host: $e');
      return stop(reason: 'capture');
    }
    if (sid != s) return;
    _ready();
    RcNative.onStop = () => stop(reason: 'stopped');
    hotkey = await RcNative.showBar(
      text: _barText,
      stop: tr('Dừng'),
      screen: screen,
    );
    notifyListeners();
  }

  /// Chữ trên thanh đỏ của máy bị điều khiển.
  String get _barText => own ? tr('Máy này đang được điều khiển từ thiết bị khác của bạn') : tr('{0} đang điều khiển máy của bạn', [peerName]);

  /// Kết nối WebRTC phía mình đã sẵn sàng: chạy các tín hiệu đến sớm.
  void _ready() {
    _peerReady = true;
    final peer = role == RcRole.host ? _host : _viewer;
    final list = [..._early];
    _early.clear();
    for (final d in list) {
      unawaited(peer?.onRemoteSignal(d));
    }
  }

  void _onInput(String raw) {
    final inj = _injector;
    if (inj == null || phase != RcPhase.active) return;
    final i = RcInput.decode(raw);
    if (i == null || !_limiter.allow()) return;
    if (i is RcQuality) {
      unawaited(_host?.setQuality(i.level));
      return;
    }
    if (i is RcSelectScreen) {
      unawaited(_switchScreen(i.id));
      return;
    }
    unawaited(RcNative.inject(inj.map(i)));
  }

  /// Gửi danh sách màn hình và màn hình đang chia sẻ cho máy điều khiển.
  void _sendScreens() {
    if (role != RcRole.host || _hostScreens.isEmpty) return;
    _host?.send(RcHostMessage(_hostScreenId, [for (final e in _hostScreens) e.display]).encode());
  }

  /// Máy điều khiển chọn màn hình [id]: chỉ nhận id trong danh sách đã gửi; đổi track, đổi toạ độ, dời thanh đỏ.
  Future<void> _switchScreen(String id) async {
    final idx = _hostScreens.indexWhere((e) => e.display.id == id);
    if (idx < 0) return _sendScreens(); // id lạ: báo lại danh sách đúng
    if (_switching) {
      _queuedScreen = id;
      return;
    }
    final h = _host, s = sid;
    if (h == null || id == _hostScreenId) return _sendScreens();
    _switching = true;
    try {
      await h.switchSource(id);
      if (sid != s || _host != h) return;
      final target = _hostScreens[idx].screen;
      final inj = _injector;
      if (inj != null) {
        // Nhả phím / nút đang giữ trước khi đổi toạ độ sang màn hình mới.
        await RcNative.inject(inj.releaseAll());
        inj.screen = target;
      }
      _hostScreenId = id;
      hotkey = await RcNative.showBar(
        text: _barText,
        stop: tr('Dừng'),
        screen: target,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[rc] switch screen: $e');
    } finally {
      _switching = false;
    }
    if (sid != s) return;
    _sendScreens();
    final q = _queuedScreen;
    _queuedScreen = null;
    if (q != null && q != _hostScreenId) await _switchScreen(q);
  }

  // ---------------------------------------------------------------- chung

  void _connected() {
    if (phase != RcPhase.connecting) return;
    phase = RcPhase.active;
    startedAt = DateTime.now();
    notifyListeners();
  }

  void _sendSig(Map<String, dynamic> data) {
    final s = sid;
    if (s != null) _sig?.send({'t': 'sig', 'sid': s, 'data': data});
  }

  void _onSignal(Map<String, dynamic> m) {
    final t = m['t'];
    final s = '${m['sid'] ?? ''}';
    switch (t) {
      case 'ring':
        return _onRing(m);
      case 'invite':
        return _onInvite(m);
      case 'devices':
        final c = _devAsk.remove('${m['ref'] ?? ''}');
        if (c != null && !c.isCompleted) c.complete(rcDeviceRows(m['list'], myDeviceId: RcDeviceInfo.currentId ?? ''));
        return;
      case 'cancel':
        if (s == sid && phase == RcPhase.ringing) incoming?.cancel();
        return;
      case 'ringing':
        if (phase == RcPhase.requesting && m['ref'] == _ref) {
          sid = s;
          notifyListeners();
        }
        return;
      case 'claimed':
        // Người được mời: trạm đã ghép phiên, máy người mời sắp gửi hình.
        if (s == sid && role == RcRole.controller && phase == RcPhase.connecting && _viewer == null) unawaited(_onAccepted(m));
        return;
      case 'sig':
        if (s != sid) return;
        final d = m['data'];
        if (d is! Map) return;
        final data = d.cast<String, dynamic>();
        if (!_peerReady) {
          if (_early.length < 256) _early.add(data);
          return;
        }
        unawaited((role == RcRole.host ? _host : _viewer)?.onRemoteSignal(data));
        return;
      case 'end':
        if (s == sid) _finish(remote: true, reason: '${m['reason'] ?? 'ended'}', notifyPeer: false);
        return;
    }
    // Cửa sổ điều khiển nhận phiên không được (người mời đã huỷ, quá giờ).
    if (t == 'error' && role == RcRole.controller && phase == RcPhase.connecting && !_peerReady && s.isNotEmpty && s == sid) {
      return _finish(remote: true, reason: 'cancelled', notifyPeer: false);
    }
    // Trả lời cho lời mời của mình.
    if (role == RcRole.host && phase == RcPhase.requesting) {
      if (s.isNotEmpty && sid != null && s != sid) return;
      if (t == 'error' && m['ref'] != null && m['ref'] != _ref) return;
      if (t == 'accepted') {
        if (s.isEmpty) return;
        sid = s;
        _reqTimer?.cancel();
        unawaited(_hostAccepted(invited: true));
        return;
      }
      final o = rcOutcomeOf(m);
      if (o == null) return;
      sid = null; // trạm đã bỏ phiên
      return _inviteFailed(o);
    }
    // Trả lời cho lời xin của mình.
    if (role != RcRole.controller || phase != RcPhase.requesting) return;
    if (s.isNotEmpty && sid != null && s != sid) return;
    if (t == 'error' && m['ref'] != null && m['ref'] != _ref) return;
    final o = rcOutcomeOf(m);
    if (o == null) return;
    if (s.isNotEmpty) sid = s;
    if (o == RcRequestOutcome.accepted) {
      unawaited(_onAccepted(m));
    } else {
      sid = null; // trạm đã bỏ phiên
      _outcome(o);
    }
  }

  /// Dừng phiên (cả hai bên): bấm Dừng, phím tắt, đóng trang điều khiển.
  Future<void> stop({String reason = 'stopped'}) async {
    if (!busy) return;
    if (phase == RcPhase.ringing) {
      incoming?.decline();
      return;
    }
    _finish(remote: false, reason: reason, notifyPeer: true);
  }

  bool _finishing = false;

  void _finish({required bool remote, required String reason, bool notifyPeer = true}) {
    if (_finishing || (role == RcRole.none && phase == RcPhase.idle)) return;
    _finishing = true;
    try {
      _doFinish(remote: remote, reason: reason, notifyPeer: notifyPeer);
    } finally {
      _finishing = false;
    }
  }

  void _doFinish({required bool remote, required String reason, required bool notifyPeer}) {
    _reqTimer?.cancel();
    final s = sid;
    if (notifyPeer && s != null) _sig?.send({'t': 'end', 'sid': s, 'reason': reason});
    final wasRole = role, started = startedAt, ch = channelId;
    if (wasRole == RcRole.host) {
      final inj = _injector;
      if (inj != null) unawaited(RcNative.inject(inj.releaseAll()));
      unawaited(RcNative.hideBar());
      RcNative.onStop = null;
    }
    final h = _host, v = _viewer, r = renderer;
    _host = null;
    _viewer = null;
    _injector = null;
    renderer = null;
    _hostScreens = const [];
    _hostScreenId = '';
    _queuedScreen = null;
    screens = const [];
    screenId = '';
    switchingTo = null;
    _early.clear();
    _peerReady = false;
    // [own] giữ tới lời xin sau (trang điều khiển còn hiện lý do kết thúc).
    final wasOwn = own;
    unawaited(h?.close());
    unawaited(v?.close());
    // Trang điều khiển còn vẽ renderer thêm một khung hình: giải phóng sau.
    if (r != null) {
      Future.delayed(const Duration(seconds: 1), () async {
        r.srcObject = null;
        await r.dispose();
      });
    }
    incoming?.cancel();
    incoming = null;
    Ringtones.stop();
    endReason = remote ? reason : (wasRole == RcRole.controller && reason != 'stopped' ? reason : null);
    sid = null;
    phase = RcPhase.idle;
    role = RcRole.none;
    startedAt = null;
    hotkey = '';
    // Điện thoại / cửa sổ phụ: không giữ kết nối tín hiệu khi không điều khiển (trừ khi đang trong cuộc gọi...).
    _maybeCloseSignal();
    // Nhật ký chỉ trong tin riêng 1-1 (không ghi vào kênh của cuộc gọi nhóm, không có kênh với máy của chính mình).
    if (wasRole == RcRole.controller && started != null && !wasOwn && (_app?.channels[ch]?.isDirect ?? false)) {
      unawaited(_postLog(ch, started, DateTime.now()));
    }
    if (wasRole == RcRole.host && started != null) toast?.call(tr('Đã kết thúc phiên điều khiển máy tính'));
    notifyListeners();
  }

  /// Một dòng nhật ký trong tin riêng (người xin đăng).
  Future<void> _postLog(String channel, DateTime start, DateTime end) async {
    final a = _app;
    if (a == null || channel.isEmpty) return;
    final text = rcLogLine(start, end);
    try {
      await a.send(channel, text, props: {
        kRcLogProp: {'start': start.millisecondsSinceEpoch, 'end': end.millisecondsSinceEpoch},
        'flygo_silent': true,
      });
    } catch (e) {
      debugPrint('[rc] log: $e');
    }
  }
}

/// "Phiên điều khiển máy tính HH:mm–HH:mm (N phút)".
String rcLogLine(DateTime start, DateTime end) =>
    tr('Phiên điều khiển máy tính {0}–{1} ({2} phút)', [hhmm(start), hhmm(end), rcSessionMinutes(start, end)]);

/// Tin nhật ký phiên điều khiển (props.flygo_rc_log): chữ theo ngôn ngữ / giờ của máy đang xem; null nếu không phải.
String? rcLogText(Map<String, dynamic> props, String fallback) {
  final v = props[kRcLogProp];
  if (v is! Map) return null;
  final s = (v['start'] as num?)?.toInt(), e = (v['end'] as num?)?.toInt();
  if (s == null || e == null || e < s) return fallback;
  return rcLogLine(DateTime.fromMillisecondsSinceEpoch(s), DateTime.fromMillisecondsSinceEpoch(e));
}
