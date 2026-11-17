// Khung ứng dụng (Sếp, 2026-11-17): trang gốc app không có nút quay lại; máy tính mở mọi app ở tab riêng.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/ui/app_route.dart';
import 'package:flygo_chat/ui/app_shell.dart';
import 'package:flygo_chat/ui/desk_tabs.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';

class _MemCache implements MailCache {
  Map? data;
  @override
  Future<Map?> read() async => data;
  @override
  Future<void> write(Map j) async => data = j;
}

/// Thư mẫu nhưng /me chờ [gate] (máy chủ chậm).
class _SlowMail extends DemoMailApi {
  final gate = Completer<void>();
  @override
  Future<MailMe> me() async {
    await gate.future;
    return super.me();
  }
}

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  tearDown(() {
    appTabHook = null;
    debugIsDesktop = null;
  });

  testWidgets('trang gốc app không có nút quay lại, trang con mở từ đó vẫn có', (t) async {
    debugIsDesktop = false;
    late BuildContext ctx;
    await t.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: Text('home'));
    })));
    unawaited(AppHost.of(ctx).open(
        key: 'vn.flygo.drive',
        title: 'Drive',
        builder: (c) => Scaffold(
              appBar: AppBar(title: const Text('Drive')),
              body: Builder(builder: (c) => TextButton(
                  onPressed: () => Navigator.of(c).push(AppPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Chi tiết'))))),
                  child: Text('back=${showsBack(c)}'))),
            )));
    await t.pumpAndSettle();
    expect(find.text('Drive'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(CloseButton), findsNothing);
    expect(find.text('back=false'), findsOneWidget);
    await t.tap(find.text('back=false'));
    await t.pumpAndSettle();
    expect(find.text('Chi tiết'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('máy tính: mở app từ ngoài tab Trang chủ thì mở tab mới (không đẩy trang)', (t) async {
    debugIsDesktop = true;
    final asked = <AppTabRequest>[];
    appTabHook = (r) {
      asked.add(r);
      return true;
    };
    late BuildContext ctx;
    await t.pumpWidget(_app(Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: Text('chat'));
    })));
    await AppHost.of(ctx).open(key: 'vn.flygo.mail', title: 'Thư', builder: (_) => const Text('mail'));
    await t.pumpAndSettle();
    expect(asked.single.key, 'vn.flygo.mail');
    expect(find.text('mail'), findsNothing);
  });

  testWidgets('máy tính: tab Trang chủ vừa bấm ô thì app mở ngay trong tab đó; đã có tab của app thì chuyển sang', (t) async {
    debugIsDesktop = true;
    appTabHook = (_) => fail('không mở tab mới khi tab Trang chủ chứa được app');
    var existing = false;
    final inTab = <String>[];
    late BuildContext ctx;
    await t.pumpWidget(_app(DeskTabScope(
      onApp: (r) {
        inTab.add(r.key);
        return existing;
      },
      child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (c) {
        ctx = c;
        return const Scaffold(body: Text('launcher'));
      })),
    )));
    unawaited(AppHost.of(ctx).open(key: 'vn.flygo.wiki', title: 'Wiki', builder: (_) => Scaffold(appBar: AppBar(title: const Text('Wiki')))));
    await t.pumpAndSettle();
    expect(inTab, ['vn.flygo.wiki']);
    expect(find.text('Wiki'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    // Từ trong app (Wiki) mở app khác: sang tab mới, không chồng trong tab Wiki.
    final asked = <String>[];
    appTabHook = (r) {
      asked.add(r.key);
      return true;
    };
    final wikiCtx = t.element(find.text('Wiki'));
    await AppHost.of(wikiCtx).open(key: 'vn.flygo.drive', title: 'Drive', builder: (_) => const Text('drive'));
    expect(asked, ['vn.flygo.drive']);

    // Tab Trang chủ khác bấm Wiki mà Wiki đã có tab: không mở chồng.
    existing = true;
    Navigator.of(wikiCtx).pop();
    await t.pumpAndSettle();
    await AppHost.of(ctx).open(key: 'vn.flygo.wiki', title: 'Wiki', builder: (_) => const Text('wiki 2'));
    await t.pumpAndSettle();
    expect(find.text('wiki 2'), findsNothing);
  });

  test('Thư: mở lại hiện ngay danh sách đã lưu, làm mới sau (vạch tải, không khung chờ)', () async {
    final cache = _MemCache();
    final first = MailStore(DemoMailApi(), cache: cache);
    await first.start();
    expect(first.items, isNotEmpty);
    expect(cache.data?['items'], isNotEmpty);
    final subjects = [for (final i in first.items) i.subject];
    first.dispose();

    final api = _SlowMail();
    final store = MailStore(api, cache: cache);
    final done = store.start();
    await Future<void>.delayed(Duration.zero);
    expect(store.me, isNotNull);
    expect([for (final i in store.items) i.subject], subjects);
    expect(store.syncing, isTrue);
    expect(store.loading, isFalse);
    api.gate.complete();
    await done;
    expect(store.syncing, isFalse);
    expect(store.items, isNotEmpty);
    store.dispose();
  });

  test('Thư: bộ nhớ đệm của hộp khác thì không dùng', () async {
    final cache = _MemCache();
    final first = MailStore(DemoMailApi(), cache: cache);
    await first.start();
    first.dispose();
    final api = _SlowMail()..mailbox = 'chung@flygo.vn';
    final store = MailStore(api, cache: cache);
    unawaited(store.start());
    await Future<void>.delayed(Duration.zero);
    expect(store.me, isNull);
    expect(store.syncing, isFalse);
    api.gate.complete();
    store.dispose();
  });
}
