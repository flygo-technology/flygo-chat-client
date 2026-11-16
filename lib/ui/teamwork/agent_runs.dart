// TeamWork: mở phiên agent khi một việc được "Bắt đầu" (bấm nút, kéo vào trạng thái bắt đầu) hoặc khi agent được @nhắc
// trong bình luận (gửi tiếp vào phiên cũ của việc nếu còn). Máy chủ tạo lượt chạy
// (queued) cho người bấm; app của người đó nhận lượt chạy, mở một phiên AI mới với agent dưới tên người đó (như tab Agents)
// và gửi bản giao việc. Agent dùng tool TeamWork qua Gateway bằng vé của người giao: chỉ có đúng quyền của người đó.
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../sub_channel.dart' show openChannelAnywhere;
import 'store.dart';

class AppAgentLauncher implements TwAgentLauncher {
  AppAgentLauncher(this.state, {this.context});
  final AppState state;
  /// Ngữ cảnh để mở phiên trong chat (null = không mở được).
  BuildContext? context;

  @override
  Future<bool> canUse(String botId) async {
    if (state.users[botId] == null) {
      try {
        await state.refreshUser(botId);
      } catch (_) {}
    }
    final u = state.users[botId];
    if (u == null) return false;
    return state.canCallBot(u, await state.myBotIds());
  }

  @override
  Future<String> launch(String botId, String title, String brief) async {
    final dm = await state.openDirect(botId);
    final group = state.channels[dm];
    if (group == null) throw StateError('Không mở được chat với agent');
    final c = await state.createAiChannel(group, [botId], title: title);
    await state.send(c.id, brief, props: {'flygo_app': 'vn.flygo.teamwork'});
    return c.id;
  }

  @override
  Future<void> stop(String channelId) async {
    if (!state.channels.containsKey(channelId)) return;
    await state.send(channelId, 'Dừng việc này: người giao đã huỷ hoặc giao cho người khác. Không làm tiếp, không sửa gì thêm.');
  }

  @override
  Future<bool> sessionUsable(String channelId, String botId) async {
    final c = state.channels[channelId];
    if (c == null || c.deleteAt != 0) return false;
    try {
      return (await state.channelUsers(channelId)).any((u) => u.id == botId);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> post(String channelId, String text) async {
    await state.send(channelId, text, props: {'flygo_app': 'vn.flygo.teamwork'});
  }

  @override
  void open(String channelId) {
    final c = context;
    if (c != null && c.mounted) openChannelAnywhere(c, channelId);
  }
}
