import 'dart:async';
import 'dart:convert';

import '../api/mm_api.dart';
import '../api/mm_ws.dart';
import '../data/models.dart';
import 'chat_backend.dart';

/// Mattermost qua [MmApi] / [MmSocket] sẵn có (máy chủ theo [kServerUrl] như phần còn lại của app).
class MmBackend implements ChatBackend {
  final MmApi api;
  final String teamName;
  final _events = StreamController<ChatEvent>.broadcast();
  final Map<String, ChatUser> _users = {};
  MmSocket? _ws;
  ChatUser? _me;
  late String _teamId;

  MmBackend(String token, {this.teamName = 'team'}) : api = MmApi(token);

  @override
  String get kind => 'mattermost';

  @override
  ChatUser get me => _me ?? (throw StateError('chưa connect()'));

  ChatUser _user(MmUser u) => _users[u.id] = ChatUser(id: u.id, name: u.displayName, email: u.email, isBot: u.isBot, raw: u);

  /// Tên người viết: lấy từ bộ nhớ, thiếu thì để id (giao diện thật tải bù qua usersByIds).
  ChatUser _author(String id) => _users[id] ?? ChatUser(id: id, name: id);

  ChatMessage _message(MmPost p) => ChatMessage(
        id: p.id,
        channelId: p.channelId,
        author: _author(p.userId),
        text: p.message,
        rootId: p.rootId.isEmpty ? null : p.rootId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(p.createAt),
        editedAt: p.editAt > 0 ? DateTime.fromMillisecondsSinceEpoch(p.editAt) : null,
        clientId: p.pendingId.isEmpty ? null : p.pendingId,
        raw: p,
      );

  @override
  Future<void> connect() async {
    _me = _user(await api.me());
    _teamId = (await api.teamByName(teamName))['id'] as String;
    _ws = MmSocket(api.token, onEvent: _onEvent, onState: (c) => _events.add(ConnectionChanged(c)))..connect();
  }

  void _onEvent(WsEvent e) {
    final ch = e.channelId;
    switch (e.event) {
      case 'posted' || 'post_edited':
        final p = MmPost((jsonDecode(e.data['post'] as String) as Map).cast());
        _events.add(e.event == 'posted' ? MessageCreated(_message(p)) : MessageUpdated(_message(p)));
      case 'post_deleted':
        final p = MmPost((jsonDecode(e.data['post'] as String) as Map).cast());
        _events.add(MessageDeleted(p.channelId, p.id));
      case 'typing' when ch != null:
        _events.add(Typing(ch, e.data['user_id'] as String? ?? '', true));
      case 'channel_viewed' when ch != null:
        _events.add(ChannelUnread(ch, false));
      case 'channel_created' || 'channel_updated' || 'channel_deleted' || 'user_added' || 'user_removed' || 'direct_added' || 'group_added':
        _events.add(const ChannelsChanged());
    }
  }

  @override
  Future<void> close() async {
    _ws?.close();
    await _events.close();
  }

  @override
  Future<List<ChatChannel>> channels() async {
    final chans = await api.myChannels(_teamId);
    final members = {for (final m in await api.myMembers(_teamId)) m.channelId: m};
    return [
      for (final c in chans)
        ChatChannel(
          id: c.id,
          name: c.displayName.isNotEmpty ? c.displayName : c.name,
          kind: switch (c.type) {
            'O' => ChatChannelKind.open,
            'P' => ChatChannelKind.private,
            'G' => ChatChannelKind.group,
            _ => ChatChannelKind.direct,
          },
          unread: c.totalMsgCount > (members[c.id]?.msgCount ?? c.totalMsgCount),
          unreadCount: members[c.id]?.mentionCount ?? 0,
          raw: c,
        ),
    ];
  }

  @override
  Future<ChatPage> messages(String channelId, {String? before, int limit = 50}) async {
    final posts = await api.posts(channelId, before: before, perPage: limit);
    return ChatPage(posts.reversed.map(_message).toList(), posts.length >= limit);
  }

  @override
  Future<ChatMessage> send(String channelId, String text, {String? rootId}) async =>
      _message(await api.createPost({'channel_id': channelId, 'message': text, 'root_id': ?rootId}));

  @override
  Future<void> markRead(String channelId) => api.viewChannel(channelId);

  @override
  Stream<ChatEvent> get events => _events.stream;

  @override
  Future<void> watch(String channelId) async {}

  @override
  Future<void> unwatch(String channelId) async {}
}
