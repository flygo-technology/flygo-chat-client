import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Kết nối media của một cuộc gọi: plugin Calls của máy chủ chat ([CallsClient], gọi 1-1) hoặc LiveKit SFU tự host
/// ([LiveKitMedia], cuộc họp). [CallService] chỉ dùng giao diện này; sự kiện người tham gia của cả hai đều theo
/// tên sự kiện của Calls (user_muted, user_voice_on, user_raise_hand…).
abstract class CallMedia {
  /// Phiên của chính mình trong cuộc gọi (bỏ qua track / sự kiện của mình).
  String get sessionId;
  MediaStream? get localVideo;
  Future<void> start({bool video = false, bool muted = false});
  /// Giơ tay (`raise_hand` / `unraise_hand`), thả cảm xúc (`react` {data: EmojiData JSON}).
  void action(String action, [Map<String, dynamic>? data]);
  Future<MediaStream?> startVideo({bool front = true});
  Future<void> stopVideo();
  Future<void> switchCamera();
  /// Luồng do bên gọi giữ (vào lại cuộc gọi thì chia sẻ tiếp), kết nối không tự dừng.
  Future<void> startScreen(MediaStream stream);
  Future<void> stopScreen();
  void setMuted(bool mute);
  Future<void> leave();
  /// Bỏ kết nối này để vào lại bằng kết nối mới (không báo rời đi, không dừng luồng chia sẻ màn hình).
  void abandon();
}
