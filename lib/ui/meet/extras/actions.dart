import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';
import '../../../state/app_state.dart';
import 'attendance.dart';
import 'board.dart';
import 'captions.dart';
import 'controls.dart';
import 'hands.dart';
import 'network.dart';
import 'qa.dart';

// Tính năng thêm của Họp (module riêng, vd. giơ tay xếp hàng, hỏi đáp, bảng trắng): mỗi tính năng thêm một mục vào menu
// của màn hình họp ở đây; màn hình họp chỉ đọc danh sách này, không cần sửa call_screen.dart.

class MeetExtraAction {
  final String id;
  final IconData icon;
  final String label;
  final bool on;
  final Future<void> Function(BuildContext context, CallService call) run;
  const MeetExtraAction({required this.id, required this.icon, required this.label, required this.run, this.on = false});
}

/// Tên hiển thị một người trong cuộc họp (thiết bị phòng họp QR: tên thiết bị).
String meetNameOf(BuildContext context, String userId) {
  final app = context.read<AppState>();
  if (userId.startsWith('device:')) return app.calls.deviceNames[userId] ?? tr('Thiết bị phòng họp');
  final n = app.users[userId]?.displayName ?? '';
  return n.isNotEmpty ? n : tr('Người tham gia');
}

/// Các mục thêm cho menu cuộc họp hiện tại.
List<MeetExtraAction> meetExtraActions(BuildContext context, CallService call) {
  if (!call.liveKit) return const [];
  final hands = handQueue(call).length;
  final hasCode = call.meeting && (call.meetingInfo?.code ?? '').isNotEmpty;
  return [
    MeetExtraAction(id: 'captions', icon: Icons.closed_caption_outlined, label: tr('Phụ đề'), on: meetCaptionsOn.value, run: showCaptions),
    if (hasCode) MeetExtraAction(id: 'board', icon: Icons.draw_outlined, label: tr('Bảng trắng'), on: boardOpen(call), run: openBoard),
    MeetExtraAction(id: 'qa', icon: Icons.question_answer_outlined, label: tr('Hỏi đáp'), run: showQa),
    if (hasCode && call.canModerate)
      MeetExtraAction(id: 'controls', icon: Icons.admin_panel_settings_outlined, label: tr('Quản lý cuộc họp'), on: meetLocked(call), run: showControls),
    if (hasCode && call.canModerate)
      MeetExtraAction(id: 'attendance', icon: Icons.fact_check_outlined, label: tr('Báo cáo tham dự'), run: showAttendance),
    if (hands > 0)
      MeetExtraAction(
        id: 'hands',
        icon: Icons.back_hand_outlined,
        label: tr('Hàng chờ giơ tay ({0})', [hands]),
        on: true,
        run: (ctx, call) => showHandQueue(ctx, call, (id) => meetNameOf(ctx, id)),
      ),
  ];
}

final _subs = Expando<List<StreamSubscription>>();

/// Màn hình họp gọi khi mở / đóng: các tính năng thêm nghe sự kiện của cuộc họp (vd. báo "chủ trì đã hạ tay bạn").
void meetExtrasAttach(BuildContext context, CallService call, void Function(String text) toast) {
  meetExtrasDetach(call);
  _subs[call] = [listenHandNotices(call, toast), listenControlNotices(context, call, toast), listenNetworkNotices(call, toast)];
}

void meetExtrasDetach(CallService call) {
  for (final s in _subs[call] ?? const <StreamSubscription>[]) {
    s.cancel();
  }
  _subs[call] = null;
}
