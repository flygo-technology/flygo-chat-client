// Chạy với một Ember thật (PoC trên NAS):
//   EMBER_URL=http://192.168.2.4:8840 EMBER_EMAIL=... EMBER_PASSWORD=... flutter test test/chat_backend/ember_backend_live_test.dart
// Không đặt EMBER_URL thì bỏ qua.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/chat_backend/chat_backend.dart';
import 'package:flygo_chat/chat_backend/ember_backend.dart';

void main() {
  final env = Platform.environment;
  final url = env['EMBER_URL'];

  test('Ember: đăng nhập, danh sách phòng, gửi tin, nhận realtime, tải lịch sử', () async {
    final a = await EmberBackend.signIn(url!, env['EMBER_EMAIL']!, env['EMBER_PASSWORD']!);
    await a.connect();
    expect(a.me.id, isNotEmpty);

    final rooms = await a.channels();
    final general = rooms.firstWhere((r) => r.name == 'general');
    expect(general.kind, ChatChannelKind.open);

    // Phiên thứ hai cùng tài khoản (như máy thứ hai) theo dõi phòng để nhận tin realtime.
    final b = EmberBackend.withSession(url, a.sessionToken);
    await b.connect();
    await b.watch(general.id);
    final text = 'PoC ${DateTime.now().toIso8601String()}\ndòng 2 <b>không phải HTML</b>';
    final got = b.events.whereType<MessageCreated>().firstWhere((e) => e.message.text.startsWith('PoC '));

    final sent = await a.send(general.id, text);
    expect(sent.channelId, general.id);
    final live = (await got.timeout(const Duration(seconds: 10))).message;
    expect(live.id, sent.id);
    expect(live.text, contains('<b>không phải HTML</b>'));

    final reply = await a.send(general.id, 'trả lời trong luồng', rootId: sent.id);
    expect(reply.rootId, sent.id);

    for (var i = 0; i < 3; i++) {
      await a.send(general.id, 'tin số $i');
    }
    await a.unwatch(general.id);
    final page = await a.messages(general.id);
    expect(page.messages.last.text, 'tin số 2');
    final older = await a.messages(general.id, before: page.messages.last.id, limit: 2);
    expect(older.messages.length, 2);
    expect(older.messages.last.text, 'tin số 1');

    await a.markRead(general.id);
    await a.close();
    await b.close();
  }, skip: url == null ? 'đặt EMBER_URL để chạy' : false, timeout: const Timeout(Duration(minutes: 1)));
}

extension<T> on Stream<T> {
  Stream<S> whereType<S>() => where((e) => e is S).cast<S>();
}
