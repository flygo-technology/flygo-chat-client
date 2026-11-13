import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/calls/call_kind.dart';

void main() {
  test('call kind from title', () {
    expect(callKindOfTitle({'title': '📅 Họp giao ban'}), CallKind.meeting);
    expect(callKindOfTitle({'title': '📞 Cuộc gọi nhóm'}), CallKind.group);
    expect(callKindOfTitle({'title': '📹 Cuộc gọi video nhóm'}), CallKind.group);
    expect(callKindOfTitle({'title': ''}), isNull);
    expect(callKindOfTitle({}), isNull);
  });

  test('meeting stays open until the creator ends it', () {
    final now = DateTime(2026, 11, 6, 10);
    final m = {'v': kMeetingVersion, 'start': now.millisecondsSinceEpoch, 'allow_early': false};
    expect(meetingOpen(m, now), isTrue);
    expect(meetingOpen({...m, 'start': now.add(const Duration(hours: 1)).millisecondsSinceEpoch}, now), isFalse);
    expect(meetingOpen({...m, 'start': now.add(const Duration(hours: 1)).millisecondsSinceEpoch, 'allow_early': true}, now), isTrue);
    expect(meetingOpen({...m, 'ended_at': now.millisecondsSinceEpoch}, now), isFalse);
    // Thẻ cũ không tự coi là đang mở.
    expect(meetingOpen({'start': now.millisecondsSinceEpoch}, now), isFalse);
  });
}
