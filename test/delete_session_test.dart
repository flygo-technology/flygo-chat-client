// Xoá phiên AI: rời trang ngay, danh sách hiện "Đang xoá…" tới khi máy chủ xác nhận; lỗi / quá giờ thì phiên hiện lại.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/data/local_store.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/ai_panel.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

class _Api extends MmApi {
  _Api() : super('t');
  Future<dynamic> Function(String path)? onDelete;
  final deleted = <String>[];
  @override
  Future<dynamic> delete(String p) {
    deleted.add(p);
    return onDelete!(p);
  }
}

const _g = 'gggggggggggggggggggggggggg';
const _me = 'mmmmmmmmmmmmmmmmmmmmmmmmmm';
const _s = 's1aaaaaaaaaaaaaaaaaaaaaaaa';

var _n = 0;
Future<(AppState, _Api)> _app() async {
  final api = _Api();
  final app = AppState('t', api: api)..me = MmUser({'id': _me, 'username': 'ba', 'first_name': 'Ba'});
  app.channels[_g] = MmChannel({'id': _g, 'name': 'p-$_me-abcdefgh', 'display_name': 'Dự án web', 'type': 'P'});
  app.channels[_s] = MmChannel({'id': _s, 'name': 'a-$_g-$_me-s1aa', 'display_name': 'AI · Dự án web · Sửa build', 'type': 'P', 'create_at': DateTime.now().millisecondsSinceEpoch - 3600000});
  app.online = true;
  app.debugSetStore(await LocalStore.memory('del-${_n++}-${DateTime.now().microsecondsSinceEpoch}'));
  return (app, api);
}

void main() {
  test('success: marked deleting at once, dropped when the server confirms', () async {
    final (app, api) = await _app();
    final done = Completer<void>();
    api.onDelete = (_) => done.future;
    final f = app.deleteChannelOptimistic(_s);
    expect(app.deletingChannels, contains(_s));
    expect(app.channels.containsKey(_s), isTrue);
    done.complete();
    await f;
    expect(api.deleted, ['/channels/$_s']);
    expect(app.deletingChannels, isEmpty);
    expect(app.channels.containsKey(_s), isFalse);
  });

  test('failure and timeout: the session comes back and the error reaches the caller', () async {
    final (app, api) = await _app();
    api.onDelete = (_) async => throw ApiException(500, 'boom');
    await expectLater(app.deleteChannelOptimistic(_s), throwsA(isA<ApiException>()));
    expect(app.deletingChannels, isEmpty);
    expect(app.channels.containsKey(_s), isTrue);

    api.onDelete = (_) => Completer<void>().future; // không bao giờ trả lời
    await expectLater(app.deleteChannelOptimistic(_s, timeout: const Duration(milliseconds: 50)), throwsA(isA<TimeoutException>()));
    expect(app.deletingChannels, isEmpty);
    expect(app.channels.containsKey(_s), isTrue);
  });

  testWidgets('the open session page leaves immediately; the list row shows "Đang xoá…" until confirmed', (t) async {
    final (app, api) = (await t.runAsync(_app))!;
    final done = Completer<void>();
    api.onDelete = (_) => done.future;
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        navigatorKey: nav,
        theme: buildTheme(Brightness.light),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: ListView(children: [AiSessionTile(channel: app.channels[_s]!, selected: false, onTap: () {})])),
      ),
    ));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => const ChatPage(channelId: _s)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(ChatPage), findsOneWidget);

    unawaited(app.deleteChannelOptimistic(_s));
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    // Rời trang ngay, không quay vòng chờ máy chủ.
    expect(find.byType(ChatPage), findsNothing);
    expect(find.byKey(const ValueKey('session-deleting')), findsOneWidget);
    expect(find.text('Đang xoá…'), findsOneWidget);

    done.complete();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(app.channels.containsKey(_s), isFalse);
    expect(find.text('Đang xoá…'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('deleteAiSession: on failure the row comes back and a "Thử lại" action retries', (t) async {
    final (app, api) = (await t.runAsync(_app))!;
    var calls = 0;
    api.onDelete = (_) async {
      calls++;
      if (calls == 1) throw ApiException(503, 'down');
    };
    late BuildContext ctx;
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ),
    ));
    await t.runAsync(() => deleteAiSession(ctx, app.channels[_s]!));
    await t.pump();
    expect(app.channels.containsKey(_s), isTrue);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Không xoá được phiên'), findsOneWidget);
    await t.tap(find.text('Thử lại'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(calls, 2);
    expect(app.channels.containsKey(_s), isFalse);
    await t.pump(const Duration(seconds: 10));
  });

  final out = Platform.environment['DEL_OUT'];
  for (final dark in [false, true]) {
    for (final (name, w) in [('phone', 390.0), ('desktop', 760.0)]) {
      testWidgets('ảnh danh sách phiên đang xoá $name ${dark ? 'dark' : 'light'}', (t) async {
        if (out == null) return;
        final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
        await t.runAsync(() async {
          for (final (fam, files) in [('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']), ('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']), ('MaterialIcons', ['MaterialIcons-Regular.otf'])]) {
            final l = FontLoader(fam);
            for (final f in files) {
              l.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
            }
            await l.load();
          }
        });
        final (app, api) = (await t.runAsync(_app))!;
        api.onDelete = (_) => Completer<void>().future;
        for (final (id, title) in [('s2aaaaaaaaaaaaaaaaaaaaaaaa', 'Thêm trang báo cáo'), ('s3aaaaaaaaaaaaaaaaaaaaaaaa', 'Dọn ổ đĩa máy chủ')]) {
          app.channels[id] = MmChannel({'id': id, 'name': 'a-$_g-$_me-${id.substring(0, 4)}', 'display_name': 'AI · Dự án web · $title', 'type': 'P', 'create_at': DateTime.now().millisecondsSinceEpoch - 3600000});
        }
        // Máy chủ không trả lời: sau 20 giây hết hạn (ném lỗi, phiên hiện lại) — ở đây chỉ chụp lúc đang xoá.
        unawaited(app.deleteChannelOptimistic(_s).catchError((_) {}));
        t.view.physicalSize = Size(w, 300) * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
          value: app,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(dark ? Brightness.dark : Brightness.light),
              home: Scaffold(
                body: ListView(padding: const EdgeInsets.only(top: 16), children: [
                  for (final id in [_s, 's2aaaaaaaaaaaaaaaaaaaaaaaa', 's3aaaaaaaaaaaaaaaaaaaaaaaa'])
                    AiSessionTile(channel: app.channels[id]!, selected: false, onTap: () {}),
                ]),
              ),
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 200));
        await t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/list-$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 25));
      });
    }
  }
}
