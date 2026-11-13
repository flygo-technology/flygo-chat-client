// Điều khiển máy tính từ xa: trạng thái xin phép (thuần Dart, kiểm thử được).
import 'dart:async';

/// Lời xin điều khiển máy này đang chờ người dùng trả lời.
enum RcConsentState { ringing, accepted, declined, timedOut, cancelled }

/// Một lời xin điều khiển: chỉ trả lời được một lần; quá [timeout] (mặc định 60 giây) không trả lời thì tự từ chối;
/// bên xin huỷ / máy khác đã nhận thì [cancel]. [onDone] gọi đúng một lần với kết quả cuối.
class RcConsent {
  final String sid;
  final String fromUserId;
  final String fromName;
  final String channelId;
  /// Lời mời "`<Tên>` mời bạn điều khiển máy tính của họ" (đồng ý thì máy này điều khiển máy người mời), thay vì lời
  /// xin điều khiển máy này.
  final bool invite;
  final Duration timeout;
  final void Function(RcConsent c) onDone;
  RcConsentState _state = RcConsentState.ringing;
  Timer? _timer;
  final DateTime startedAt;

  RcConsent({
    required this.sid,
    required this.fromUserId,
    required this.fromName,
    required this.channelId,
    required this.onDone,
    this.invite = false,
    this.timeout = const Duration(seconds: 60),
    Timer Function(Duration, void Function())? timer,
    DateTime? now,
  }) : startedAt = now ?? DateTime.now() {
    _timer = (timer ?? Timer.new)(timeout, () => _finish(RcConsentState.timedOut));
  }

  RcConsentState get state => _state;
  bool get pending => _state == RcConsentState.ringing;

  /// Số giây còn lại trước khi tự từ chối.
  int secondsLeft([DateTime? now]) {
    final left = timeout - (now ?? DateTime.now()).difference(startedAt);
    return left.isNegative ? 0 : (left.inMilliseconds / 1000).ceil();
  }

  /// Người dùng bấm "Cho phép". Trả về false nếu lời xin đã kết thúc (hết giờ, đã huỷ…).
  bool accept() => _finish(RcConsentState.accepted);
  bool decline() => _finish(RcConsentState.declined);
  bool cancel() => _finish(RcConsentState.cancelled);

  bool _finish(RcConsentState s) {
    if (_state != RcConsentState.ringing) return false;
    _state = s;
    _timer?.cancel();
    _timer = null;
    onDone(this);
    return true;
  }
}

/// Giai đoạn của phiên điều khiển trên máy này.
enum RcPhase {
  idle,
  /// Máy điều khiển: đang chờ người kia cho phép.
  requesting,
  /// Máy bị điều khiển: đang hỏi người dùng.
  ringing,
  /// Đã cho phép, đang kết nối WebRTC.
  connecting,
  active,
}

/// Kết quả lời xin gửi đi (máy điều khiển).
enum RcRequestOutcome { accepted, declined, permission, timeout, unsupported, busy, noStation, error }

/// Đổi tin của trạm (`t`) thành kết quả cho người xin; null nếu tin không kết thúc lời xin.
RcRequestOutcome? rcOutcomeOf(Map<String, dynamic> m) => switch (m['t']) {
      'accepted' => RcRequestOutcome.accepted,
      'declined' => switch (m['reason']) {
          'permission' => RcRequestOutcome.permission,
          'unsupported' => RcRequestOutcome.unsupported,
          'timeout' => RcRequestOutcome.timeout,
          'busy' => RcRequestOutcome.busy,
          _ => RcRequestOutcome.declined,
        },
      'timeout' => RcRequestOutcome.timeout,
      'unsupported' => RcRequestOutcome.unsupported,
      'busy' => RcRequestOutcome.busy,
      'error' => m['code'] == 'busy_self' ? RcRequestOutcome.busy : RcRequestOutcome.error,
      _ => null,
    };

/// Dòng nhật ký phiên trong tin riêng: "Phiên điều khiển máy tính HH:mm–HH:mm (N phút)".
int rcSessionMinutes(DateTime start, DateTime end) {
  final ms = end.difference(start).inMilliseconds;
  if (ms <= 0) return 0;
  return (ms / 60000).round().clamp(1, 1 << 20);
}
