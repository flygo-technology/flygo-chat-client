// Cuộc gọi 1-1 (tin riêng giữa hai người) kiểu WhatsApp: máy trạng thái thuần (không đụng mạng / WebRTC) để
// CallService dùng và kiểm thử được; cách hiện tin cuộc gọi trong chat ("Cuộc gọi thoại · 3:21", "Cuộc gọi nhỡ").
//
// Quy tắc gác máy: một bên gác máy / từ chối / không nghe / mất kết nối quá ~10 giây thì cuộc gọi kết thúc cho CẢ HAI
// bên ngay. Media vẫn đi qua plugin Calls của máy chủ chat (SFU): đổ chuông, CallKit, TURN, lịch sử dùng chung với
// cuộc họp; chỉ khác giao diện và cách kết thúc.
import 'dart:async';

import '../i18n/i18n.dart';

/// Tín hiệu "tôi gác máy" gửi trong cuộc gọi (lệnh `react` của plugin Calls, chỉ người trong cuộc gọi nhận) ngay
/// trước khi rời: bên kia kết thúc luôn, không phải chờ hết thời gian chờ nối lại.
const kHangupSignal = 'flygo_hangup';

/// Tin ghi lại cuộc gọi 1-1 do app đăng (gửi im lặng, không hiện thành tin riêng trong chat): {kind, at, call} với
/// kind 'declined' (người nghe bấm "Từ chối", người gọi nhận tin này là thôi đổ chuông) hoặc 'answered' (người nghe đã
/// vào cuộc gọi — plugin Calls không ghi danh sách người tham gia vào tin cuộc gọi nên lịch sử dựa vào tin này).
const kCallLogProp = 'flygo_call_log';

/// Tiêu đề cuộc gọi (plugin Calls lưu vào tin cuộc gọi) bắt đầu bằng dấu này là gọi video.
const kVideoTitleMark = '📹';

/// Tin cuộc gọi (`custom_calls`) là gọi video (người gọi đặt tiêu đề có dấu 📹).
bool callPropsVideo(Map<String, dynamic> props) => '${props['title'] ?? ''}'.trimLeft().startsWith(kVideoTitleMark);

enum DirectStatus {
  /// Gọi đi: đang tạo cuộc gọi trên máy chủ.
  calling,
  /// Gọi đi: máy chủ đã đổ chuông máy người kia.
  ringing,
  /// Cuộc gọi đến đang đổ chuông.
  incoming,
  /// Đã nghe máy, đang kết nối media.
  connecting,
  /// Đang nói chuyện.
  active,
  ended,
}

/// Lý do kết thúc.
enum DirectEnd {
  /// Mình gác máy khi đang nói chuyện.
  localHangUp,
  /// Mình huỷ khi người kia chưa nghe.
  cancelled,
  /// Người kia gác máy (tín hiệu gác máy, hoặc máy chủ báo cuộc gọi kết thúc).
  remoteHangUp,
  /// Mình bấm "Từ chối".
  declined,
  /// Người kia từ chối.
  remoteDeclined,
  /// Gọi đi: hết giờ mà không ai nghe.
  noAnswer,
  /// Cuộc gọi đến: người gọi huỷ / hết giờ đổ chuông.
  missed,
  /// Người kia rớt mạng / mình rớt mạng quá thời gian chờ nối lại.
  lost,
  /// Mình đã nghe máy / từ chối trên thiết bị khác.
  elsewhere,
}

/// Hẹn giờ (thay được trong kiểm thử): trả về hàm huỷ.
typedef DirectSchedule = void Function() Function(Duration after, void Function() run);

void Function() _realSchedule(Duration after, void Function() run) => Timer(after, run).cancel;

/// Trạng thái một cuộc gọi 1-1. Mọi đường kết thúc đi qua [onEnd] đúng một lần; CallService làm phần việc thật
/// (gửi tín hiệu gác máy, rời / kết thúc cuộc gọi trên máy chủ, báo từ chối, tắt chuông).
class DirectCall {
  final bool outgoing;
  final DirectSchedule _schedule;
  /// Thời gian chờ người kia (hoặc mình) nối lại sau khi rớt mạng.
  final Duration grace;
  /// Gọi đi: chờ người kia nghe máy.
  final Duration answerTimeout;
  /// Cuộc gọi đến: đổ chuông tối đa.
  final Duration ringTimeout;
  final void Function(DirectEnd why) onEnd;

  DirectStatus status;
  DirectEnd? endedBy;
  /// Camera của mình / người kia đang bật: đổi qua lại thoại ↔ video bất cứ lúc nào, không gọi lại.
  bool localVideo;
  bool remoteVideo = false;
  /// Gọi đến là gọi video (người gọi bật camera từ đầu).
  bool incomingVideo;
  /// Lúc bắt đầu nói chuyện (để đếm mm:ss).
  DateTime? talkingSince;
  /// Người kia đang tạm vắng (rời / rớt mạng), đang chờ nối lại.
  bool get waitingPeer => _peerGrace != null;
  bool get waitingSelf => _selfGrace != null;

  void Function()? _ringTimer;
  void Function()? _peerGrace;
  void Function()? _selfGrace;

  DirectCall({
    required this.outgoing,
    required this.onEnd,
    bool video = false,
    DirectSchedule? schedule,
    this.grace = const Duration(seconds: 10),
    this.answerTimeout = const Duration(seconds: 50),
    this.ringTimeout = const Duration(seconds: 45),
  })  : _schedule = schedule ?? _realSchedule,
        status = outgoing ? DirectStatus.calling : DirectStatus.incoming,
        localVideo = outgoing && video,
        incomingVideo = !outgoing && video {
    _ringTimer = outgoing
        ? _schedule(answerTimeout, () => _finish(DirectEnd.noAnswer))
        : _schedule(ringTimeout, () => _finish(DirectEnd.missed));
  }

  bool get isEnded => status == DirectStatus.ended;
  bool get isActive => status == DirectStatus.active;
  /// Chưa ai nghe máy.
  bool get preAnswer => status == DirectStatus.calling || status == DirectStatus.ringing || status == DirectStatus.incoming;

  /// Giao diện video (ảnh đại diện khi không ai bật camera).
  bool get videoLayout => localVideo || remoteVideo;

  // ---------------------------------------------------------------- sự kiện

  /// Gọi đi: máy chủ đã tạo cuộc gọi và đổ chuông bên kia.
  void serverRinging() {
    if (status == DirectStatus.calling) status = DirectStatus.ringing;
  }

  /// Mình bấm nghe máy.
  void accept({bool? video}) {
    if (status != DirectStatus.incoming) return;
    _cancelRing();
    if (video != null) incomingVideo = video;
    status = DirectStatus.connecting;
  }

  /// Phiên của mình đã vào cuộc gọi (media đã nối).
  void connected() {
    if (status == DirectStatus.connecting) _talk();
  }

  /// Người kia có mặt trong cuộc gọi (vừa nghe máy, hoặc vừa nối lại).
  void remoteJoined() {
    if (isEnded) return;
    _cancel(_peerGrace);
    _peerGrace = null;
    if (status == DirectStatus.calling || status == DirectStatus.ringing || status == DirectStatus.connecting) _talk();
  }

  /// Người kia rời cuộc gọi mà không báo gác máy (rớt mạng, app bị tắt): chờ [grace] rồi kết thúc.
  void remoteLeft() {
    if (status != DirectStatus.active || _peerGrace != null) return;
    _peerGrace = _schedule(grace, () {
      _peerGrace = null;
      _finish(DirectEnd.lost);
    });
  }

  /// Người kia gác máy (tín hiệu trong cuộc gọi) hoặc máy chủ báo cuộc gọi đã kết thúc.
  void remoteHangUp() {
    if (isEnded) return;
    _finish(status == DirectStatus.incoming ? DirectEnd.missed : DirectEnd.remoteHangUp);
  }

  /// Người kia bấm "Từ chối".
  void remoteDeclined() {
    if (!outgoing || !preAnswer) return;
    _finish(DirectEnd.remoteDeclined);
  }

  /// Mình bấm gác máy (hoặc "Kết thúc" trên màn hình cuộc gọi của hệ điều hành).
  void hangUp() {
    if (isEnded) return;
    if (status == DirectStatus.incoming) return decline();
    _finish(preAnswer ? DirectEnd.cancelled : DirectEnd.localHangUp);
  }

  void decline() {
    if (status != DirectStatus.incoming) return;
    _finish(DirectEnd.declined);
  }

  /// Đã nghe / từ chối trên thiết bị khác của mình.
  void handledElsewhere() {
    if (status == DirectStatus.incoming) _finish(DirectEnd.elsewhere);
  }

  /// Kết nối của mình đứt: đang tự nối lại; quá [grace] thì kết thúc.
  void connectionLost() {
    if (isEnded || _selfGrace != null) return;
    _selfGrace = _schedule(grace, () {
      _selfGrace = null;
      _finish(DirectEnd.lost);
    });
  }

  void connectionRecovered() {
    _cancel(_selfGrace);
    _selfGrace = null;
  }

  /// Cuộc gọi đã kết thúc vì lý do khác (lỗi, đăng xuất): chỉ dừng hẹn giờ, không gọi [onEnd].
  void dispose() {
    if (isEnded) return;
    status = DirectStatus.ended;
    _stopTimers();
  }

  // ---------------------------------------------------------------- nội bộ

  void _talk() {
    _cancelRing();
    status = DirectStatus.active;
    talkingSince ??= DateTime.now();
  }

  void _cancelRing() {
    _cancel(_ringTimer);
    _ringTimer = null;
  }

  void _stopTimers() {
    _cancelRing();
    _cancel(_peerGrace);
    _cancel(_selfGrace);
    _peerGrace = _selfGrace = null;
  }

  static void _cancel(void Function()? c) => c?.call();

  void _finish(DirectEnd why) {
    if (isEnded) return;
    status = DirectStatus.ended;
    endedBy = why;
    _stopTimers();
    onEnd(why);
  }
}

/// Câu báo khi cuộc gọi 1-1 kết thúc (hiện vài giây trên màn hình cuộc gọi).
String directEndText(DirectEnd why) => switch (why) {
      DirectEnd.localHangUp || DirectEnd.remoteHangUp => tr('Cuộc gọi đã kết thúc'),
      DirectEnd.cancelled => tr('Đã huỷ cuộc gọi'),
      DirectEnd.declined => tr('Đã từ chối'),
      DirectEnd.remoteDeclined => tr('Người nhận đã từ chối'),
      DirectEnd.noAnswer => tr('Không có người trả lời'),
      DirectEnd.missed => tr('Cuộc gọi nhỡ'),
      DirectEnd.lost => tr('Mất kết nối'),
      DirectEnd.elsewhere => tr('Đã xử lý trên thiết bị khác'),
    };

/// Bố cục màn hình cuộc gọi 1-1.
enum DirectLayout {
  /// Không ai bật camera: ảnh đại diện lớn, tên, trạng thái (kiểu gọi thoại).
  voice,
  /// Hình người kia (camera hoặc màn hình chia sẻ) chiếm cả màn hình, hình mình nhỏ ở góc nếu có.
  remote,
  /// Chỉ mình bật camera: hình mình cả màn hình (như lúc đang đổ chuông gọi video), ảnh người kia ở giữa.
  local,
}

DirectLayout directLayout({required bool localVideo, required bool remoteVideo, bool remoteScreen = false}) {
  if (remoteVideo || remoteScreen) return DirectLayout.remote;
  if (localVideo) return DirectLayout.local;
  return DirectLayout.voice;
}

/// "3:21", "1:02:03".
String callClock(Duration d) {
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$s';
  return '${d.inMinutes}:$s';
}

enum DirectOutcome { ongoing, answered, missed, noAnswer, declined }

/// Cách hiện một cuộc gọi 1-1 trong chat / lịch sử, kiểu WhatsApp.
class DirectCallSummary {
  final DirectOutcome outcome;
  /// Mình là người gọi.
  final bool outgoing;
  final bool video;
  /// "Cuộc gọi thoại", "Cuộc gọi nhỡ"…
  final String title;
  /// "3:21", "Không trả lời", "Bị từ chối"… (rỗng nếu không có).
  final String detail;
  const DirectCallSummary(this.outcome, {required this.outgoing, required this.video, required this.title, this.detail = ''});

  /// Cuộc gọi nhỡ của mình: tô đỏ.
  bool get alert => outcome == DirectOutcome.missed;

  /// "Cuộc gọi thoại · 3:21" (dòng xem trước trong danh sách chat).
  String get line => detail.isEmpty ? title : '$title · $detail';
}

/// Tóm tắt tin cuộc gọi 1-1 (`custom_calls`): [callerId] là người tạo cuộc gọi, [participants] là những người đã vào
/// (plugin Calls ghi khi kết thúc, null nếu đang diễn ra), [declinedBy] là người đã bấm từ chối (tin [kCallLogProp]).
DirectCallSummary directCallSummary({
  required String me,
  required String callerId,
  required int startAt,
  int? endAt,
  List<String>? participants,
  bool video = false,
  String? declinedBy,
  bool answeredLog = false,
}) {
  final outgoing = callerId == me;
  final kind = video ? tr('Cuộc gọi video') : tr('Cuộc gọi thoại');
  if (endAt == null) {
    return DirectCallSummary(DirectOutcome.ongoing, outgoing: outgoing, video: video, title: tr('Cuộc gọi đang diễn ra'));
  }
  final answered = answeredLog || (participants ?? const []).any((u) => u != callerId);
  if (answered) {
    final d = Duration(milliseconds: (endAt - startAt).clamp(0, 1 << 40));
    return DirectCallSummary(DirectOutcome.answered, outgoing: outgoing, video: video, title: kind, detail: callClock(d));
  }
  if (declinedBy != null && declinedBy.isNotEmpty) {
    return DirectCallSummary(DirectOutcome.declined,
        outgoing: outgoing, video: video, title: kind, detail: declinedBy == me ? tr('Bạn đã từ chối') : tr('Bị từ chối'));
  }
  if (outgoing) {
    return DirectCallSummary(DirectOutcome.noAnswer, outgoing: true, video: video, title: kind, detail: tr('Không trả lời'));
  }
  return DirectCallSummary(DirectOutcome.missed,
      outgoing: false, video: video, title: video ? tr('Cuộc gọi video nhỡ') : tr('Cuộc gọi nhỡ'));
}
