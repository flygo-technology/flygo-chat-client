import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/ref_grants.dart';
import 'package:flygo_chat/ui/ref_picker.dart' show RefItem;
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

/// Tag chat / luồng cho trợ lý: gửi tin không chờ trạm cấp vé, chip vé phía trên tin.
void main() {
  final app = AppState('test')..me = MmUser({'id': 'me', 'username': 'me'});
  final bot = MmUser({'id': 'b' * 26, 'username': 'bot', 'is_bot': true});
  final bot2 = MmUser({'id': 'c' * 26, 'username': 'bot2', 'is_bot': true});
  const chat = RefItem('chat', 'hhhhhhhhhhhhhhhhhhhhhhhhhh', null, 'Kho hàng');
  const thread = RefItem('thread', 'hhhhhhhhhhhhhhhhhhhhhhhhhh', 'rrrrrrrrrrrrrrrrrrrrrrrrrr', 'Đơn 18');

  Widget wrap(Widget child, {Brightness b = Brightness.light}) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(theme: buildTheme(b), home: Scaffold(body: Center(child: child))),
      );
  MmPost postWith(Map<String, dynamic> refs) => MmPost({'id': 'p1', 'channel_id': 'x', 'user_id': 'me', 'message': 'xem giúp', 'props': {'flygo_refs': refs}});

  // Trạm giả: trả lời khi test cho phép (mô phỏng đường đi chậm qua Cloudflare).
  late List<(Map<String, dynamic>, Completer<Map<String, dynamic>>)> calls;
  setUp(() {
    calls = [];
    RefGrants.poster = (token, body) {
      final c = Completer<Map<String, dynamic>>();
      calls.add((body, c));
      return c.future;
    };
  });
  void answer(int i, {int? expiresAt, String? error}) {
    final (body, c) = calls[i];
    error != null
        ? c.completeError(Exception(error))
        : c.complete({'grant_id': body['grant_id'], 'expires_at': expiresAt ?? DateTime.now().millisecondsSinceEpoch + 600000});
  }

  test('start trả vé ngay, không chờ trạm; id trong tin trùng id gửi trạm', () {
    final refs = RefGrants.start('tok', [bot], [chat, thread], 600, false);
    expect(calls, hasLength(1), reason: 'đã gọi trạm, đang chờ');
    final gid = refs['grant_id'] as String;
    expect(gid, matches(RegExp(r'^[A-Za-z0-9_-]{16}$')));
    expect(RefGrants.job(gid)!.status, GrantStatus.pending);
    final (body, _) = calls.first;
    expect(body['grant_id'], gid);
    expect([for (final r in body['refs'] as List) r['ref_id']], [for (final it in refs['items'] as List) it['ref_id']]);
    expect((refs['items'] as List).last['root_id'], thread.rootId);
    expect(refs['bot_id'], bot.id);
    expect(refs['expires_at'], greaterThan(DateTime.now().millisecondsSinceEpoch + 590000));
  });

  test('nhiều trợ lý: mỗi trợ lý một vé, tin mang {grants:[…]}', () {
    final refs = RefGrants.start('tok', [bot, bot2], [chat], 600, true);
    expect((refs['grants'] as List).length, 2);
    expect(calls.length, 2);
    expect(grantChipsOf({'flygo_refs': refs}), hasLength(1), reason: 'cùng một chat gộp một chip');
  });

  testWidgets('bấm gửi: tin + chip hiện ngay khi trạm còn chậm, xong thì đổi sang "đến HH:MM"', (t) async {
    MmPost? sent;
    await t.pumpWidget(wrap(StatefulBuilder(
      builder: (context, set) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextButton(
            onPressed: () => set(() => sent = postWith(RefGrants.start('tok', [bot], [chat], 600, false))),
            child: const Text('Gửi')),
        if (sent != null) ...[RefGrantChips(post: sent!), Text(sent!.message)],
      ]),
    )));
    await t.tap(find.text('Gửi'));
    await t.pump(); // một khung hình, trạm chưa trả lời
    expect(find.text('xem giúp'), findsOneWidget);
    expect(find.text('Kho hàng'), findsOneWidget);
    expect(find.textContaining('Đang cấp quyền…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final end = DateTime.now().add(const Duration(minutes: 10));
    answer(0, expiresAt: end.millisecondsSinceEpoch);
    await t.pump();
    final hm = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    expect(find.textContaining('chỉ đọc · đến $hm'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('cấp lỗi: chip đỏ, bấm để thử lại cùng grant_id', (t) async {
    final refs = RefGrants.start('tok', [bot], [thread], 3600, true);
    await t.pumpWidget(wrap(RefGrantChips(post: postWith(refs))));
    answer(0, error: 'mất mạng');
    await t.pump();
    expect(find.textContaining('Lỗi cấp quyền · Thử lại'), findsOneWidget);
    await t.tap(find.textContaining('Lỗi cấp quyền'));
    await t.pump();
    expect(calls, hasLength(2));
    expect(calls[1].$1['grant_id'], refs['grant_id']);
    expect(find.textContaining('Đang cấp quyền…'), findsOneWidget);
    answer(1);
    await t.pump();
    expect(find.textContaining('đọc + gửi · đến'), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
  });

  for (final b in Brightness.values) {
    testWidgets('vé cũ (đã cấp trước đây) hết hạn: chip xám "hết hạn" ($b)', (t) async {
      final past = DateTime.now().millisecondsSinceEpoch - 1000;
      await t.pumpWidget(wrap(
          RefGrantChips(post: postWith({
            'grant_id': 'oldGrant_000001',
            'expires_at': past,
            'write': false,
            'items': [
              {'ref_id': 'r1', 'kind': 'chat', 'channel_id': 'h' * 26, 'name': 'Kho hàng'},
            ],
          })),
          b: b));
      expect(find.textContaining('chỉ đọc · hết hạn'), findsOneWidget);
      final name = t.widget<Text>(find.text('Kho hàng'));
      expect(name.style?.decoration, TextDecoration.lineThrough);
    });
  }

  testWidgets('chip hết hạn đúng lúc (tự vẽ lại)', (t) async {
    final refs = RefGrants.start('tok', [bot], [chat], 600, false);
    await t.pumpWidget(wrap(RefGrantChips(post: postWith(refs))));
    answer(0, expiresAt: DateTime.now().millisecondsSinceEpoch + 1500);
    await t.pump();
    expect(find.textContaining('đến'), findsOneWidget);
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 1800)));
    await t.pump(const Duration(milliseconds: 1800));
    expect(find.textContaining('hết hạn'), findsOneWidget);
  });

  testWidgets('không có vé thì không vẽ gì', (t) async {
    await t.pumpWidget(wrap(RefGrantChips(post: MmPost({'id': 'p', 'props': {}}))));
    expect(find.byType(Wrap), findsNothing);
  });
}
