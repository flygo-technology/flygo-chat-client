import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/chat_page.dart';

/// Trả lời tin bằng luồng bí mật: người gửi tin được thêm vào luồng (trừ chính mình, người ngoài nhóm).
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba'});
  for (final (id, bot) in [('me', false), ('lan', false), ('bot1', true), ('ngoai', false)]) {
    app.users[id] = MmUser({'id': id, 'username': id, 'is_bot': bot, 'delete_at': 0});
  }
  app.debugSetChannelMembers('g', ['me', 'lan', 'bot1']);
  MmPost post(String by, {String type = ''}) => MmPost({'id': 'p$by', 'channel_id': 'g', 'user_id': by, 'message': 'x', 'create_at': 0, 'type': type});

  test('người gửi trong nhóm: thêm', () async {
    expect(await secretThreadAuthor(app, post('lan'), 'g'), 'lan');
  });

  test('trả lời chính bot đó: vẫn thêm bot như trước', () async {
    expect(await secretThreadAuthor(app, post('bot1'), 'g'), 'bot1');
  });

  test('tin của mình, tin hệ thống, người ngoài nhóm: không thêm', () async {
    expect(await secretThreadAuthor(app, post('me'), 'g'), isNull);
    expect(await secretThreadAuthor(app, post('lan', type: 'system_join_channel'), 'g'), isNull);
    expect(await secretThreadAuthor(app, post('ngoai'), 'g'), isNull);
  });
}
