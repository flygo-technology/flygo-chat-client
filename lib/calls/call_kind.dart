// Ba loại cuộc gọi của app, cùng đi qua plugin Calls của máy chủ chat nhưng khác giao diện và cách kết thúc:
// - Gọi 1-1 (tin riêng): kiểu WhatsApp, một bên gác máy là kết thúc cho cả hai (direct_call.dart).
// - Gọi nhóm (thoại / video trong nhóm): đổ chuông cả nhóm, mọi người chung một lưới, không trình chiếu / giơ tay /
//   AI / bình chọn; mọi người rời hết là kết thúc.
// - Cuộc họp: hẹn giờ được, đủ tính năng (trình chiếu, chia sẻ màn hình, giơ tay, bình chọn, AI); người vào ra tự do,
//   chỉ người tạo cuộc họp bấm "Kết thúc" mới kết thúc. Mỗi cuộc họp là một thẻ `flygo_meeting` trong chat.
import 'direct_call.dart';

enum CallKind { direct, group, meeting }

/// Tiêu đề cuộc gọi (plugin Calls lưu vào tin cuộc gọi) bắt đầu bằng dấu này là cuộc họp.
const kMeetingTitleMark = '📅';

/// Tiêu đề cuộc gọi nhóm thoại (gọi video nhóm dùng [kVideoTitleMark]).
const kGroupTitleMark = '📞';

/// Loại cuộc gọi theo tiêu đề tin cuộc gọi (null: tin cũ không có dấu).
CallKind? callKindOfTitle(Map<String, dynamic> props) {
  final t = '${props['title'] ?? ''}'.trimLeft();
  if (t.startsWith(kMeetingTitleMark)) return CallKind.meeting;
  if (t.startsWith(kGroupTitleMark) || t.startsWith(kVideoTitleMark)) return CallKind.group;
  return null;
}

/// Thẻ cuộc họp (props `flygo_meeting`) bản mới: chỉ kết thúc khi người tạo bấm "Kết thúc" (ghi `ended_at`).
const kMeetingVersion = 2;

/// Cuộc họp của một thẻ trong chat.
class MeetingInfo {
  final String postId;
  final String creatorId;
  final String title;
  const MeetingInfo({required this.postId, required this.creatorId, required this.title});
}

/// Thẻ cuộc họp đã được người tạo kết thúc.
bool meetingEnded(Map<String, dynamic> m) => ((m['ended_at'] as num?) ?? 0) > 0;

/// Thẻ cuộc họp bản mới (kết thúc bằng nút "Kết thúc"); thẻ cũ thì coi là kết thúc khi cuộc gọi trống người.
bool meetingV2(Map<String, dynamic> m) => ((m['v'] as num?) ?? 0) >= kMeetingVersion;

/// Thẻ cuộc họp đang mở để vào (chưa kết thúc, đã tới giờ hoặc cho vào sớm).
bool meetingOpen(Map<String, dynamic> m, DateTime now) {
  if (!meetingV2(m) || meetingEnded(m)) return false;
  final start = ((m['start'] as num?) ?? 0).toInt();
  return m['allow_early'] == true || start <= now.millisecondsSinceEpoch;
}
