// Điều khiển máy tính trong cuộc gọi: các nút cho màn hình cuộc gọi (1-1, gọi nhóm, cuộc họp) và bảng chọn người.
// Màn hình cuộc gọi chỉ cần: lấy [rcCallActions] để vẽ nút theo kiểu của mình, bấm thì gọi [runRcCallAction].
//   - 1-1 với người: "Điều khiển màn hình" (xin điều khiển máy người kia, người kia bấm "Cho phép").
//   - Gọi nhóm / cuộc họp: "Yêu cầu điều khiển" (chọn một người → người đó bấm "Cho phép"), và trên máy tính
//     "Cho phép điều khiển máy tôi" (chọn một người → người đó bấm "Đồng ý" là điều khiển máy mình; bấm lại để dừng).
// Chia sẻ màn hình trong cuộc gọi là việc riêng của màn hình cuộc gọi (CallService.startScreenShare), chạy song song
// được với phiên điều khiển (hai luồng chụp màn hình độc lập).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../calls/call_service.dart';
import '../config.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'rc_call.dart';
import 'rc_service.dart';
import 'rc_ui.dart' show RemoteControlUi;

/// Một nút điều khiển máy tính trong cuộc gọi.
class RcCallAction {
  /// rc_request (xin điều khiển) / rc_invite (cho người khác điều khiển máy mình, đang chia sẻ thì là "dừng").
  final String id;
  final IconData icon;
  final String label;
  /// Đang bật (đang cho người khác điều khiển máy mình).
  final bool on;
  const RcCallAction(this.id, this.icon, this.label, {this.on = false});
}

/// Các nút điều khiển máy tính cho cuộc gọi đang diễn ra của [call] (rỗng nếu không dùng được).
List<RcCallAction> rcCallActions(AppState app, CallService call) {
  if (kIsWeb || kWindowRc) return const [];
  final id = call.channelId;
  final ch = id == null ? null : app.channels[id];
  final me = app.me?.id;
  if (ch == null || me == null || call.phase != CallPhase.active) return const [];
  final svc = RemoteControlService.instance;
  if (ch.isDirect) {
    if (!RemoteControlUi.availableFor(app, ch)) return const [];
    return [RcCallAction('rc_request', Icons.desktop_windows_outlined, tr('Điều khiển màn hình'))];
  }
  return [
    RcCallAction('rc_request', Icons.desktop_windows_outlined, tr('Yêu cầu điều khiển')),
    if (RemoteControlService.canInvite)
      svc.sharingControl
          ? RcCallAction('rc_invite', Icons.desktop_access_disabled_outlined, tr('Dừng cho điều khiển'), on: true)
          : RcCallAction('rc_invite', Icons.connected_tv_outlined, tr('Cho phép điều khiển máy tôi')),
  ];
}

/// Người trong cuộc gọi có thể chọn (bỏ mình, bot, tài khoản đã khoá).
List<RcPick> rcCallPeople(AppState app, CallService call) => rcPickList(
      [for (final p in call.participants) p.userId],
      myId: app.me?.id ?? '',
      nameOf: (id) => app.users[id]?.displayName,
      isBot: (id) => app.users[id]?.isBot ?? false,
      isDeleted: (id) => (app.users[id]?.deleteAt ?? 0) != 0,
      fallbackName: tr('Người dùng'),
    );

/// Bấm nút [id] của [rcCallActions].
Future<void> runRcCallAction(BuildContext context, AppState app, CallService call, String id) async {
  final chId = call.channelId;
  final ch = chId == null ? null : app.channels[chId];
  final me = app.me?.id;
  if (ch == null || me == null) return;
  final svc = RemoteControlService.instance;
  if (ch.isDirect) {
    final other = ch.otherUserId(me);
    if (id == 'rc_request' && other != null) await svc.request(ch.id, other);
    return;
  }
  if (id == 'rc_invite' && svc.sharingControl) {
    await svc.stop();
    return;
  }
  final invite = id == 'rc_invite';
  final pick = await showRcPeoplePicker(
    context,
    title: invite ? tr('Cho ai điều khiển máy của bạn?') : tr('Xin điều khiển máy của ai?'),
    people: () => rcCallPeople(app, call),
    listenable: call,
  );
  if (pick == null) return;
  if (invite) {
    await svc.invite(ch.id, pick.userId, via: 'call', name: pick.name);
  } else {
    await svc.request(ch.id, pick.userId, via: 'call', name: pick.name);
  }
}

/// Bảng chọn một người trong cuộc gọi (danh sách cập nhật theo [listenable]). null nếu đóng bảng.
Future<RcPick?> showRcPeoplePicker(
  BuildContext context, {
  required String title,
  required List<RcPick> Function() people,
  Listenable? listenable,
}) =>
    showModalBottomSheet<RcPick>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => RcPeoplePicker(title: title, people: people, listenable: listenable),
    );

/// Nội dung bảng chọn người (tách riêng để kiểm thử).
class RcPeoplePicker extends StatelessWidget {
  final String title;
  final List<RcPick> Function() people;
  final Listenable? listenable;
  const RcPeoplePicker({super.key, required this.title, required this.people, this.listenable});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: listenable ?? const AlwaysStoppedAnimation(0),
        builder: (ctx, _) {
          final list = people();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .7),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Text(tr('Chưa có ai khác trong cuộc gọi'), style: const TextStyle(color: Colors.white70)),
                  )
                else
                  Flexible(
                    child: ListView(shrinkWrap: true, children: [
                      for (final p in list)
                        ListTile(
                          key: ValueKey('rc-pick-${p.userId}'),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF5F6368),
                            child: Text(p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
                                style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                          onTap: () => Navigator.pop(ctx, p),
                        ),
                    ]),
                  ),
                const SizedBox(height: 8),
              ]),
            ),
          );
        },
      );
}
