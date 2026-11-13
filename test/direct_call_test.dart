// Cuộc gọi 1-1 kiểu WhatsApp: máy trạng thái (gác máy từ bất kỳ bên nào là kết thúc cả hai, đổi thoại ↔ video không
// gọi lại) và tin cuộc gọi trong chat (nhỡ / từ chối / đã gọi).
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/calls/direct_call.dart';

/// Hẹn giờ giả: chạy tay bằng [elapse].
class FakeClock {
  final List<(Duration, void Function(), List<bool>)> _jobs = [];
  Duration now = Duration.zero;

  void Function() schedule(Duration after, void Function() run) {
    final cancelled = [false];
    _jobs.add((now + after, run, cancelled));
    return () => cancelled[0] = true;
  }

  void elapse(Duration d) {
    now += d;
    final due = _jobs.where((j) => j.$1 <= now && !j.$3[0]).toList();
    _jobs.removeWhere((j) => j.$1 <= now || j.$3[0]);
    for (final j in due) {
      j.$2();
    }
  }
}

/// Hai máy của một cuộc gọi, nối với nhau như qua máy chủ: kết thúc ở một bên → bên kia nhận tín hiệu tương ứng.
class Pair {
  final clock = FakeClock();
  late final DirectCall caller;
  late final DirectCall callee;
  final ends = <String, DirectEnd>{};

  Pair({bool video = false}) {
    caller = DirectCall(
      outgoing: true,
      video: video,
      schedule: clock.schedule,
      onEnd: (why) {
        ends['caller'] = why;
        // Người gọi gác / huỷ: gửi tín hiệu gác máy + kết thúc cuộc gọi trên máy chủ (call_end tới bên kia).
        callee.remoteHangUp();
      },
    );
    callee = DirectCall(
      outgoing: false,
      video: video,
      schedule: clock.schedule,
      onEnd: (why) {
        ends['callee'] = why;
        switch (why) {
          case DirectEnd.declined:
            caller.remoteDeclined(); // tin "đã từ chối"
          case DirectEnd.missed || DirectEnd.elsewhere:
            break;
          default:
            caller.remoteHangUp(); // tín hiệu gác máy trong cuộc gọi
        }
      },
    );
    caller.serverRinging();
  }

  void answer({bool? video}) {
    callee.accept(video: video);
    callee.connected();
    caller.remoteJoined();
  }
}

void main() {
  group('DirectCall hang-up', () {
    test('caller hangs up during the call: both end', () {
      final p = Pair()..answer();
      expect(p.caller.status, DirectStatus.active);
      expect(p.callee.status, DirectStatus.active);
      p.caller.hangUp();
      expect(p.ends['caller'], DirectEnd.localHangUp);
      expect(p.ends['callee'], DirectEnd.remoteHangUp);
      expect(p.callee.isEnded, isTrue);
    });

    test('callee hangs up during the call: both end', () {
      final p = Pair()..answer();
      p.callee.hangUp();
      expect(p.ends['callee'], DirectEnd.localHangUp);
      expect(p.ends['caller'], DirectEnd.remoteHangUp);
      expect(p.caller.isEnded, isTrue);
    });

    test('onEnd fires once even with duplicate signals', () {
      var n = 0;
      final c = DirectCall(outgoing: true, schedule: FakeClock().schedule, onEnd: (_) => n++);
      c.remoteJoined();
      c.remoteHangUp();
      c.remoteHangUp();
      c.hangUp();
      expect(n, 1);
    });

    test('caller cancels before answer: callee sees a missed call', () {
      final p = Pair();
      expect(p.callee.status, DirectStatus.incoming);
      p.caller.hangUp();
      expect(p.ends['caller'], DirectEnd.cancelled);
      expect(p.ends['callee'], DirectEnd.missed);
    });

    test('callee declines: caller stops ringing at once', () {
      final p = Pair();
      p.callee.decline();
      expect(p.ends['callee'], DirectEnd.declined);
      expect(p.ends['caller'], DirectEnd.remoteDeclined);
    });

    test('no answer: caller times out, callee rings out as missed', () {
      final p = Pair();
      p.clock.elapse(const Duration(seconds: 46));
      expect(p.ends['callee'], DirectEnd.missed);
      expect(p.caller.isEnded, isFalse);
      p.clock.elapse(const Duration(seconds: 5));
      expect(p.ends['caller'], DirectEnd.noAnswer);
    });

    test('peer drops: waits ~10 s for a reconnect, then ends', () {
      final p = Pair()..answer();
      p.caller.remoteLeft();
      expect(p.caller.waitingPeer, isTrue);
      p.clock.elapse(const Duration(seconds: 6));
      // Nối lại kịp: cuộc gọi tiếp tục.
      p.caller.remoteJoined();
      expect(p.caller.waitingPeer, isFalse);
      p.clock.elapse(const Duration(seconds: 20));
      expect(p.caller.isActive, isTrue);
      // Lần này không quay lại.
      p.caller.remoteLeft();
      p.clock.elapse(const Duration(seconds: 9));
      expect(p.caller.isActive, isTrue);
      p.clock.elapse(const Duration(seconds: 2));
      expect(p.ends['caller'], DirectEnd.lost);
      expect(p.callee.isEnded, isTrue);
    });

    test('own connection lost beyond the grace period ends the call', () {
      final p = Pair()..answer();
      p.callee.connectionLost();
      p.clock.elapse(const Duration(seconds: 5));
      p.callee.connectionRecovered();
      p.clock.elapse(const Duration(seconds: 30));
      expect(p.callee.isActive, isTrue);
      p.callee.connectionLost();
      p.clock.elapse(const Duration(seconds: 11));
      expect(p.ends['callee'], DirectEnd.lost);
      expect(p.ends['caller'], DirectEnd.remoteHangUp);
    });

    test('answered on another device stops ringing here only', () {
      final p = Pair();
      p.callee.handledElsewhere();
      expect(p.ends['callee'], DirectEnd.elsewhere);
      expect(p.caller.isEnded, isFalse);
    });
  });

  group('voice and video', () {
    test('voice call switches to video and back without ending', () {
      final p = Pair()..answer();
      expect(p.caller.videoLayout, isFalse);
      expect(directLayout(localVideo: false, remoteVideo: false), DirectLayout.voice);
      // Người gọi bật camera: bên kia tự chuyển sang hình người gọi.
      p.caller.localVideo = true;
      p.callee.remoteVideo = true;
      expect(p.caller.videoLayout, isTrue);
      expect(directLayout(localVideo: p.caller.localVideo, remoteVideo: p.caller.remoteVideo), DirectLayout.local);
      expect(directLayout(localVideo: p.callee.localVideo, remoteVideo: p.callee.remoteVideo), DirectLayout.remote);
      // Người nghe cũng bật, rồi người gọi tắt.
      p.callee.localVideo = true;
      p.caller.remoteVideo = true;
      p.caller.localVideo = false;
      p.callee.remoteVideo = false;
      expect(directLayout(localVideo: p.callee.localVideo, remoteVideo: p.callee.remoteVideo), DirectLayout.local);
      // Cả hai tắt: về ảnh đại diện.
      p.callee.localVideo = false;
      p.caller.remoteVideo = false;
      expect(directLayout(localVideo: false, remoteVideo: false), DirectLayout.voice);
      expect(p.caller.isActive && p.callee.isActive, isTrue);
      expect(p.ends, isEmpty);
    });

    test('incoming video call can be answered as voice only', () {
      final p = Pair(video: true);
      expect(p.caller.localVideo, isTrue);
      expect(p.callee.incomingVideo, isTrue);
      p.answer(video: false);
      expect(p.callee.incomingVideo, isFalse);
      expect(p.callee.isActive, isTrue);
    });

    test('screen share takes the big view', () {
      expect(directLayout(localVideo: true, remoteVideo: false, remoteScreen: true), DirectLayout.remote);
    });

    test('video title mark', () {
      expect(callPropsVideo({'title': '$kVideoTitleMark Video call'}), isTrue);
      expect(callPropsVideo({'title': null}), isFalse);
      expect(callPropsVideo(const {}), isFalse);
    });
  });

  group('call messages', () {
    const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaa', b = 'bbbbbbbbbbbbbbbbbbbbbbbbbb';
    const start = 1700000000000;

    test('answered voice call shows the duration', () {
      final s = directCallSummary(me: a, callerId: a, startAt: start, endAt: start + 201000, participants: [a, b]);
      expect(s.outcome, DirectOutcome.answered);
      expect(s.line, 'Cuộc gọi thoại · 3:21');
      expect(s.outgoing, isTrue);
      expect(s.alert, isFalse);
    });

    test('answered video call, long', () {
      final s = directCallSummary(me: b, callerId: a, startAt: start, endAt: start + 3723000, participants: [a, b], video: true);
      expect(s.line, 'Cuộc gọi video · 1:02:03');
      expect(s.outgoing, isFalse);
    });

    test('missed for the callee, no answer for the caller', () {
      final callee = directCallSummary(me: b, callerId: a, startAt: start, endAt: start + 30000, participants: [a]);
      expect(callee.outcome, DirectOutcome.missed);
      expect(callee.line, 'Cuộc gọi nhỡ');
      expect(callee.alert, isTrue);
      final caller = directCallSummary(me: a, callerId: a, startAt: start, endAt: start + 30000, participants: [a]);
      expect(caller.outcome, DirectOutcome.noAnswer);
      expect(caller.line, 'Cuộc gọi thoại · Không trả lời');
      expect(directCallSummary(me: b, callerId: a, startAt: start, endAt: start + 1, participants: [a], video: true).line,
          'Cuộc gọi video nhỡ');
    });

    test('declined', () {
      final caller = directCallSummary(me: a, callerId: a, startAt: start, endAt: start + 5000, participants: [a], declinedBy: b);
      expect(caller.outcome, DirectOutcome.declined);
      expect(caller.line, 'Cuộc gọi thoại · Bị từ chối');
      final callee = directCallSummary(me: b, callerId: a, startAt: start, endAt: start + 5000, participants: [a], declinedBy: b);
      expect(callee.line, 'Cuộc gọi thoại · Bạn đã từ chối');
      expect(callee.alert, isFalse);
    });

    test('ongoing', () {
      final s = directCallSummary(me: b, callerId: a, startAt: start);
      expect(s.outcome, DirectOutcome.ongoing);
    });

    test('clock format', () {
      expect(callClock(const Duration(seconds: 5)), '0:05');
      expect(callClock(const Duration(minutes: 12, seconds: 30)), '12:30');
    });
  });
}
