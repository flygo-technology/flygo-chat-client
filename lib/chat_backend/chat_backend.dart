/// Tầng trung gian giữa giao diện chat và máy chủ chat: app nói chuyện với [ChatBackend], không gọi thẳng API của
/// một máy chủ cụ thể. Hiện có hai bản: [MmBackend] (Mattermost, máy chủ đang chạy) và [EmberBackend] (Ember trên
/// Cloudflare, đang thử). Mô hình ở đây là phần chung tối thiểu của hai bên; thứ riêng của từng máy chủ nằm trong
/// [ChatChannel.raw] / [ChatMessage.raw].
library;

import 'dart:async';

enum ChatChannelKind { open, private, direct, group }

class ChatUser {
  final String id;
  final String name;
  final String? email;
  final bool isBot;
  final Object? raw;
  const ChatUser({required this.id, required this.name, this.email, this.isBot = false, this.raw});
  @override
  String toString() => 'ChatUser($id, $name)';
}

class ChatChannel {
  final String id;
  final String name;
  final ChatChannelKind kind;
  final bool unread;
  final int unreadCount;
  final Object? raw;
  const ChatChannel({required this.id, required this.name, required this.kind, this.unread = false, this.unreadCount = 0, this.raw});
  @override
  String toString() => 'ChatChannel($id, $name, ${kind.name})';
}

class ChatMessage {
  final String id;
  final String channelId;
  final ChatUser author;
  /// Chữ thuần để hiển thị/tìm kiếm. Định dạng gốc (markdown của MM, HTML của Ember) nằm trong [raw].
  final String text;
  /// Tin trả lời trong luồng: id tin gốc, null nếu không phải trả lời.
  final String? rootId;
  final DateTime createdAt;
  final DateTime? editedAt;
  /// Id do client sinh khi gửi, dùng để khớp bản tạm (optimistic) với bản máy chủ lưu.
  final String? clientId;
  final Object? raw;
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.author,
    required this.text,
    required this.createdAt,
    this.rootId,
    this.editedAt,
    this.clientId,
    this.raw,
  });
  @override
  String toString() => 'ChatMessage($id in $channelId by ${author.name}: $text)';
}

/// Một trang tin, cũ nhất trước.
class ChatPage {
  final List<ChatMessage> messages;
  final bool hasMore;
  const ChatPage(this.messages, this.hasMore);
}

/// Sự kiện thời gian thực.
sealed class ChatEvent {
  const ChatEvent();
}

class MessageCreated extends ChatEvent {
  final ChatMessage message;
  const MessageCreated(this.message);
}

class MessageUpdated extends ChatEvent {
  final ChatMessage message;
  const MessageUpdated(this.message);
}

class MessageDeleted extends ChatEvent {
  final String channelId;
  final String messageId;
  const MessageDeleted(this.channelId, this.messageId);
}

class Typing extends ChatEvent {
  final String channelId;
  final String userId;
  final bool typing;
  const Typing(this.channelId, this.userId, this.typing);
}

/// Kênh có tin chưa đọc (hoặc vừa được đọc ở thiết bị khác khi [unread] = false).
class ChannelUnread extends ChatEvent {
  final String channelId;
  final bool unread;
  final int? count;
  const ChannelUnread(this.channelId, this.unread, [this.count]);
}

/// Danh sách kênh đổi (thêm, sửa, rời): giao diện tải lại danh sách.
class ChannelsChanged extends ChatEvent {
  const ChannelsChanged();
}

class ConnectionChanged extends ChatEvent {
  final bool connected;
  const ConnectionChanged(this.connected);
}

class ChatBackendException implements Exception {
  final int status;
  final String message;
  const ChatBackendException(this.status, this.message);
  bool get isAuth => status == 401;
  @override
  String toString() => 'ChatBackendException($status): $message';
}

abstract class ChatBackend {
  /// Tên máy chủ (để ghi log, chọn tính năng): 'mattermost' | 'ember'.
  String get kind;

  /// Người đang đăng nhập, sau [connect].
  ChatUser get me;

  /// Kiểm tra phiên, lấy [me] và mở kết nối thời gian thực chung.
  Future<void> connect();
  Future<void> close();

  Future<List<ChatChannel>> channels();

  /// Trang tin mới nhất, hoặc trang trước tin [before].
  Future<ChatPage> messages(String channelId, {String? before, int limit = 50});

  /// Gửi tin; trả về tin máy chủ đã lưu.
  Future<ChatMessage> send(String channelId, String text, {String? rootId});

  /// Đánh dấu đã đọc kênh.
  Future<void> markRead(String channelId);

  /// Mọi sự kiện thời gian thực của tài khoản. Với máy chủ chia kết nối theo kênh (Ember), kênh phải được [watch] thì
  /// mới có sự kiện tin nhắn của kênh đó; MM đẩy mọi kênh trên một kết nối nên [watch] không làm gì.
  Stream<ChatEvent> get events;
  Future<void> watch(String channelId);
  Future<void> unwatch(String channelId);
}
