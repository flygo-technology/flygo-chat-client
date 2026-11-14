// Luồng riêng công khai (trang luồng, tin gốc ở chat chính): gõ + gửi phải tạo tin có root_id = tin gốc.
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/data/local_store.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

class _FakeApi extends MmApi {
  final created = <Map<String, dynamic>>[];
  _FakeApi() : super('t');

  @override
  Future<MmPost> createPost(Map<String, dynamic> body) async {
    created.add(body);
    return MmPost({...body, 'id': 'srv${created.length}', 'user_id': 'me', 'create_at': DateTime.now().millisecondsSinceEpoch});
  }

  @override
  Future<List<MmPost>> posts(String channelId, {String? before, String? after, int? since, int? page, int perPage = 60}) async => [];

  @override
  Future<dynamic> get(String p, [Map<String, String>? q]) async => throw ApiException(404, 'offline');

  @override
  Future<dynamic> post(String p, Object? body) async => throw ApiException(404, 'offline');
}

final _now = DateTime(2026, 11, 14, 9).millisecondsSinceEpoch;

Future<(AppState, _FakeApi)> _setup() async {
  final api = _FakeApi();
  final app = AppState('t', api: api)..me = MmUser({'id': 'me', 'username': 'an', 'first_name': 'An'});
  app.debugSetStore(await LocalStore.memory('thread-${DateTime.now().microsecondsSinceEpoch}'));
  app.aiConsent = true;
  for (final (id, name) in [('me', 'An'), ('u2', 'Bình')]) {
    app.users[id] = MmUser({'id': id, 'username': name.toLowerCase(), 'first_name': name});
  }
  app.channels['c'] = MmChannel({'id': 'c', 'type': 'O', 'display_name': 'Nhóm dự án'});
  app.debugPutPosts('c', [
    MmPost({'id': 'r1', 'channel_id': 'c', 'user_id': 'me', 'root_id': 'root', 'message': 'Em đã gửi bản vẽ', 'create_at': _now - 1000, 'props': {'flygo_reply': 'thread'}}),
    MmPost({'id': 'root', 'channel_id': 'c', 'user_id': 'u2', 'message': 'Bàn về báo giá thang máy', 'create_at': _now - 5000, 'props': {'flygo_open_thread': true}}),
  ]);
  return (app, api);
}

Widget _wrap(AppState app) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const ThreadPage(channelId: 'c', rootId: 'root')),
    );

void main() {
  testWidgets('gửi tin trong luồng công khai: root_id = tin gốc', (t) async {
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (app, api) = (await t.runAsync(_setup))!;
    await t.pumpWidget(_wrap(app));
    await t.pumpAndSettle();
    final field = find.descendant(of: find.byType(ThreadPage), matching: find.byType(TextField)).last;
    await t.enterText(field, 'Ok anh, em xem rồi');
    await t.pump();
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(api.created, hasLength(1));
    expect(api.created.single['root_id'], 'root');
    expect(api.created.single['message'], 'Ok anh, em xem rồi');
  });

  testWidgets('trả lời một tin trong luồng: hiện trích dẫn, gửi vào luồng kèm flygo_quote', (t) async {
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (app, api) = (await t.runAsync(_setup))!;
    await t.pumpWidget(_wrap(app));
    await t.pumpAndSettle();
    // Menu của câu trả lời "Em đã gửi bản vẽ" (chuột phải / nhấn giữ) → Trả lời.
    await t.tap(find.textContaining('Em đã gửi bản vẽ', findRichText: true), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    await t.tap(find.text('Trả lời').last);
    await t.pumpAndSettle();
    // Thanh trích dẫn trên ô nhắn tin.
    expect(find.textContaining('Em đã gửi bản vẽ', findRichText: true), findsNWidgets(2));
    final field = find.descendant(of: find.byType(ThreadPage), matching: find.byType(TextField)).last;
    await t.enterText(field, 'Bản vẽ ổn rồi');
    await t.pump();
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(api.created, hasLength(1));
    final body = api.created.single;
    expect(body['root_id'], 'root');
    expect((body['props'] as Map)['flygo_quote'], 'r1');
    expect((body['props'] as Map)['flygo_reply'], 'thread');
    // Gửi xong: bỏ thanh trích dẫn; tin mới trong luồng hiện trích dẫn tin được trả lời.
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.textContaining('Bản vẽ ổn rồi', findRichText: true), findsOneWidget);
    expect(find.textContaining('Em đã gửi bản vẽ', findRichText: true), findsNWidgets(2), reason: 'tin gốc trong luồng + trích dẫn trong tin mới');
  });

  testWidgets('trả lời tin gốc của luồng: không trích dẫn, gửi vào luồng như thường', (t) async {
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final (app, api) = (await t.runAsync(_setup))!;
    await t.pumpWidget(_wrap(app));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Bàn về báo giá thang máy', findRichText: true), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    await t.tap(find.text('Trả lời').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Bàn về báo giá thang máy', findRichText: true), findsOneWidget);
    final field = find.descendant(of: find.byType(ThreadPage), matching: find.byType(TextField)).last;
    await t.enterText(field, 'Chốt giá thứ Hai nhé');
    await t.pump();
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(api.created.single['root_id'], 'root');
    expect((api.created.single['props'] as Map?)?['flygo_quote'], isNull);
  });
}
