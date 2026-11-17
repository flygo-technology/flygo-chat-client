// TeamWork: mở phiên agent khi một việc được "Bắt đầu" (bấm nút, kéo vào trạng thái bắt đầu) hoặc khi agent được @nhắc
// trong bình luận (gửi tiếp vào phiên cũ của việc nếu còn). Máy chủ tạo lượt chạy
// (queued) cho người bấm; app của người đó nhận lượt chạy, mở một phiên AI mới với agent dưới tên người đó (như tab Agents)
// và gửi bản giao việc. Agent dùng tool TeamWork qua Gateway bằng vé của người giao: chỉ có đúng quyền của người đó.
import 'package:flutter/material.dart';

import '../../config.dart' show kServerUrl;

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
  Future<bool> isOwnerOf(String botId) async => (await state.myBotIds()).contains(botId);

  @override
  Future<String> launch(String botId, String title, String brief, {Map<String, dynamic> props = const {}}) async {
    final dm = await state.openDirect(botId);
    final group = state.channels[dm];
    if (group == null) throw StateError('Không mở được chat với agent');
    final c = await state.createAiChannel(group, [botId], title: title);
    await state.send(c.id, brief, props: {'flygo_app': 'vn.flygo.teamwork', ...props});
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
  Future<void> post(String channelId, String text, {Map<String, dynamic> props = const {}}) async {
    await state.send(channelId, text, props: {'flygo_app': 'vn.flygo.teamwork', ...props});
  }

  @override
  void open(String channelId) {
    final c = context;
    if (c != null && c.mounted) openChannelAnywhere(c, channelId);
  }
}

/// Tạo / gắn nhóm chat của dự án bằng token của chính người dùng (lệnh user_op do TeamWork xếp hàng).
class AppChatOps implements TwChatOps {
  AppChatOps(this.state, {this.context});
  final AppState state;
  BuildContext? context;

  @override
  Future<TwChannelInfo> createChannel({String? teamId, required String name, required String displayName, bool private = true, String purpose = '', String header = ''}) async {
    final team = teamId ?? state.teamId;
    if (team == null) throw StateError('Chưa chọn team');
    final c = (await state.api.post('/channels', {
      'team_id': team,
      'name': name,
      'display_name': displayName.length > 64 ? displayName.substring(0, 64) : displayName,
      'type': private ? 'P' : 'O',
      'purpose': purpose,
      'header': header,
    }) as Map);
    return _info(c);
  }

  Future<TwChannelInfo> _info(Map c) async {
    final team = '${c['team_id'] ?? ''}';
    var teamName = '';
    try {
      teamName = '${(await state.api.get('/teams/$team') as Map)['name'] ?? ''}';
    } catch (_) {}
    final base = kServerUrl.replaceAll(RegExp(r'/+$'), '');
    return (id: '${c['id']}', teamId: team, name: '${c['name'] ?? ''}', displayName: '${c['display_name'] ?? c['name'] ?? ''}', url: teamName.isEmpty ? '' : '$base/$teamName/channels/${c['name']}');
  }

  @override
  Future<TwChannelInfo?> resolveChannel(String ref) async {
    try {
      var r = ref.trim();
      // URL dạng …/<team>/channels/<tên> hoặc "~tên": tìm theo tên trong các team của mình.
      final m = RegExp(r'/([^/]+)/channels/([^/?#]+)').firstMatch(r);
      if (m != null) return await _info(await state.api.get('/teams/name/${m[1]}/channels/name/${m[2]}') as Map);
      if (r.startsWith('~')) {
        r = r.substring(1);
        for (final t in (await state.api.get('/users/me/teams') as List)) {
          try {
            return await _info(await state.api.get('/teams/${(t as Map)['id']}/channels/name/$r') as Map);
          } catch (_) {}
        }
        return null;
      }
      return await _info(await state.api.get('/channels/$r') as Map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> addMember(String channelId, String userId) => state.addMember(channelId, userId);

  @override
  Future<bool> isMember(String channelId) async {
    try {
      await state.api.get('/channels/$channelId/members/${state.me!.id}');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> bestTeam(List<String> userIds) async {
    try {
      final teams = [for (final t in (await state.api.get('/users/me/teams') as List)) '${(t as Map)['id']}'];
      if (teams.length <= 1 || userIds.isEmpty) return teams.contains(state.teamId) ? state.teamId : teams.firstOrNull;
      String? best;
      var most = -1;
      for (final t in teams) {
        final ids = await state.api.post('/teams/$t/members/ids', userIds) as List;
        if (ids.length > most || (ids.length == most && t == state.teamId)) {
          most = ids.length;
          best = t;
        }
      }
      return best;
    } catch (_) {
      return state.teamId;
    }
  }

  @override
  Future<List<(String, String)>> myChannels() async => [
        for (final c in state.channels.values)
          if (c.deleteAt == 0 && (c.type == 'O' || c.type == 'P') && !c.isAi && !c.isSub) (c.id, state.channelTitle(c)),
      ]..sort((a, b) => a.$2.compareTo(b.$2));

  @override
  Future<String?> userIdByUsername(String username) async {
    try {
      return '${(await state.api.get('/users/username/$username') as Map)['id']}';
    } catch (_) {
      return null;
    }
  }

  @override
  void openChannel(String channelId) {
    final c = context;
    if (c != null && c.mounted) openChannelAnywhere(c, channelId);
  }
}
