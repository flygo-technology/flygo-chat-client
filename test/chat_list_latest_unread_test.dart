// Sếp 25/11: (1) tin mình gửi phải thành dòng xem trước ở danh sách chat ngay, không bị tải lại ghi đè bằng tin cũ;
// (2) "Đánh dấu là chưa đọc" phải hiện số chưa đọc ngay.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/data/local_store.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';

class _FakeApi extends MmApi {
  _FakeApi() : super('t');
  Completer<void>? hold; // giữ createPost lại để kiểm trạng thái trong lúc gửi
  Map<String, dynamic>? unreadReply;
  @override
  Future<dynamic> post(String p, Object? body) async {
    if (p == '/posts') {
      await hold?.future;
      final b = (body as Map).cast<String, dynamic>();
      return {...b, 'id': 'srv1', 'user_id': 'me', 'create_at': DateTime.now().millisecondsSinceEpoch};
    }
    if (p.endsWith('/set_unread')) return unreadReply ?? {};
    return {};
  }

  @override
  Future<dynamic> get(String p, [Map<String, String>? q]) async => <dynamic>[];
}

Future<(AppState, _FakeApi)> _app() async {
  final api = _FakeApi();
  final app = AppState('t', api: api)..me = MmUser({'id': 'me', 'username': 'an'});
  app.debugSetStore(await LocalStore.memory('latest-${DateTime.now().microsecondsSinceEpoch}'));
  app.aiConsent = true;
  final old = DateTime.now().millisecondsSinceEpoch - 60000;
  app.channels['c'] = MmChannel({'id': 'c', 'type': 'O', 'display_name': 'Nhóm', 'total_msg_count': 5, 'total_msg_count_root': 5, 'last_post_at': old});
  app.members['c'] = MmMember({'channel_id': 'c', 'user_id': 'me', 'msg_count': 5, 'msg_count_root': 5, 'last_viewed_at': old + 1});
  app.latest['c'] = MmPost({'id': 'p0', 'channel_id': 'c', 'user_id': 'u2', 'message': 'tin cũ', 'root_id': '', 'create_at': old});
  return (app, api);
}

void main() {
  test('gửi tin: dòng xem trước là tin mình ngay khi bấm gửi, và sau khi máy chủ lưu', () async {
    final (app, api) = await _app();
    api.hold = Completer();
    final f = app.send('c', 'xin chào');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(app.latest['c']?.message, 'xin chào', reason: 'đang gửi đã hiện ở danh sách');
    api.hold!.complete();
    await f;
    expect(app.latest['c']?.id, 'srv1');
  });

  test('trả lời trong luồng không thay dòng xem trước của chat chính', () async {
    final (app, _) = await _app();
    await app.send('c', 'trong luồng', rootId: 'p0', replyKind: 'thread');
    expect(app.latest['c']?.id, 'p0');
  });

  test('đánh dấu chưa đọc: số chưa đọc hiện ngay (kể cả khi tin cuối đã xem)', () async {
    final (app, api) = await _app();
    app.debugPutPosts('c', [app.latest['c']!]);
    expect(app.unreadOf('c'), 0);
    api.unreadReply = {'channel_id': 'c', 'msg_count': 4, 'msg_count_root': 4, 'mention_count': 0, 'last_viewed_at': 1};
    final f = app.markUnread('c');
    await Future<void>.delayed(Duration.zero);
    await f;
    expect(app.unreadOf('c'), 1);
  });
}
