// Tiến trình nền của lượt chạy (props.flygo_agent.bg, runner 0.7.18): dòng mỗi tiến trình, đầu ra trực tiếp, gọn khi xong.
// Ảnh xem trước (chạy tay): BG_OUT=<thư mục> [EMOJI_FONT=<NotoColorEmoji.ttf>] flutter test test/bg_tasks_ui_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_bg_procs.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f.startsWith('/') || f.startsWith('assets/') ? f : '$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  await load('Flygo Inter', [for (final f in ['Regular', 'Italic', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$f.ttf']);
  await load('JetBrains Mono', [for (final f in ['Regular', 'Medium', 'Bold']) 'assets/fonts/JetBrainsMono-$f.ttf']);
  final emoji = Platform.environment['EMOJI_FONT'];
  if (emoji != null) await load('Noto Color Emoji', [emoji]);
}

final _now = DateTime.now().millisecondsSinceEpoch;
final _tail = [for (var i = 1; i <= 40; i++) 'Running test $i/1192 ... ok'].join('\n');

List<Map<String, dynamic>> _tasks({bool done = false}) => [
      {
        'id': 't1', 'label': 'Chạy toàn bộ test Flutter', 'command': 'flutter test -j 2 2>&1 | tee /tmp/test.log', 'host': 'flygo-03',
        'status': done ? 'done' : 'running', if (done) 'exit_code': 0,
        'started_at': _now - 134000, if (done) 'ended_at': _now - 4000, 'updated_at': _now - 2000,
        'output_file': '/tmp/test.log', 'tail': _tail, 'lines': 1240, 'truncated': true,
      },
      {
        'id': 't4', 'kind': 'detached', 'command': "ssh flygo-02 'nohup /opt/ttv/autodial.sh > /tmp/autodial.log 2>&1 &'",
        'label': "ssh flygo-02 'nohup /opt/ttv/autodial.sh > /tmp/autodial…", 'host': 'flygo-02', 'status': 'done',
        'note': 'tệp output đứng yên, coi như xong (không rõ mã thoát)',
        'started_at': _now - 95000, 'ended_at': _now - 20000, 'updated_at': _now - 20000, 'output_file': '/tmp/autodial.log',
        'tail': 'ppp331 dialing…\nppp331 up 113.22.x.x\nppp332 dialing…', 'lines': 3,
      },
      {
        'id': 't2', 'kind': 'bash_bg', 'command': 'docker compose logs -f relay', 'host': 'local', 'status': done ? 'killed' : 'running',
        if (done) 'note': 'dừng cùng lượt',
        'started_at': _now - 61000, if (done) 'ended_at': _now - 3000, 'updated_at': _now - 1000, 'tail': 'relay  | listening on :8066',
      },
      {
        'id': 't3', 'command': 'flutter build apk --release', 'host': 'flygo-03', 'status': 'failed', 'exit_code': 1,
        'started_at': _now - 600000, 'ended_at': _now - 420000, 'updated_at': _now - 420000,
        'tail': 'FAILURE: Build failed with an exception.\n* What went wrong:\nExecution failed for task \':app:minifyReleaseWithR8\'.',
      },
    ];

AppState _app({bool done = false}) {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica'});
  app.online = true;
  app.debugPutPosts('dm', [
    MmPost({
      'id': 'run', 'channel_id': 'dm', 'user_id': 'bot', 'create_at': _now - 140000, 'update_at': _now - 1000,
      'message': 'Em đã chạy test và theo dõi log relay ở nền; xong em báo ngay.',
      'props': {
        'flygo_agent': {
          'status': 'done', 'engine': 'claude', 'texts': [''], 'bg': _tasks(done: done),
          'steps': [{'id': 'a', 'seg': 0, 'kind': 'command', 'status': 'done', 'title': r'$ flutter test -j 2 &', 'label': 'Chạy test ở nền'}],
        },
        'flygo_agent_message': {'streaming': false},
      },
    }),
    MmPost({'id': 'u1', 'channel_id': 'dm', 'user_id': 'me', 'message': 'Chạy lại toàn bộ test giúp em', 'create_at': _now - 150000}),
  ]);
  app.hasMore['dm'] = false;
  return app;
}

Widget _wrap(AppState app, Brightness b, [Key? key]) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const ChatPage(channelId: 'dm'),
        ),
      ),
    );

Widget _bare(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('nút Dừng: chỉ trên tác vụ đang chạy, hỏi lại rồi gọi onStop; không có onStop thì không có nút', (t) async {
    final stopped = <String>[];
    await t.pumpWidget(_bare(AgentBgTasks(tasks: _tasks(), openKey: 'p-stop', onStop: (id) async {
      stopped.add(id);
      return null;
    })));
    expect(find.byKey(const ValueKey('bg-stop')), findsNWidgets(2)); // t1, t2 đang chạy; t4 đã xong
    await t.tap(find.byKey(const ValueKey('bg-stop')).first);
    await t.pump(const Duration(milliseconds: 400)); // vòng xoay "đang chạy" quay mãi: không pumpAndSettle
    expect(find.text('Dừng tác vụ nền?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bg-stop-confirm')));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(stopped, ['t1']);

    await t.pumpWidget(_bare(AgentBgTasks(tasks: _tasks(), openKey: 'p-nostop')));
    expect(find.byKey(const ValueKey('bg-stop')), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  test('elapsed time', () {
    expect(bgElapsed({'started_at': 0, 'ended_at': 134000, 'status': 'done'}, DateTime(2026)), '2m14s');
    expect(bgElapsed({'started_at': 0, 'ended_at': 3780000, 'status': 'done'}, DateTime(2026)), '1h03m');
    expect(bgElapsed({'started_at': 0, 'ended_at': 8000, 'status': 'failed'}, DateTime(2026)), '8s');
  });

  testWidgets('running: section with one row per task, tap opens the live output; done: one summary line', (t) async {
    t.view.physicalSize = const Size(420, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = _app();
    await t.pumpWidget(_wrap(app, Brightness.light));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Tác vụ nền · 2 đang chạy'), findsOneWidget);
    expect(find.text('Chạy toàn bộ test Flutter'), findsOneWidget);
    expect(find.text(r'$ docker compose logs -f relay'), findsOneWidget);
    expect(find.textContaining('flygo-02 · xong · 1m15s'), findsOneWidget);
    expect(find.text('tệp output đứng yên, coi như xong (không rõ mã thoát)'), findsOneWidget);
    // Nhãn chỉ là phần đầu của lệnh: không hiện lặp; host "local" không hiện.
    expect(find.textContaining("autodial…"), findsNothing);
    expect(find.textContaining('local'), findsNothing);
    expect(find.textContaining('flygo-03 · lỗi · exit 1'), findsOneWidget);
    expect(find.byType(BgOutputView), findsNothing);
    await t.tap(find.text('Chạy toàn bộ test Flutter'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byType(BgOutputView), findsOneWidget);
    expect(find.textContaining('Running test 40/1192', findRichText: true), findsOneWidget);
    expect(find.textContaining('40 dòng cuối / 1240'), findsOneWidget);
    // Câu trả lời cũ, tiến trình xong hết: gọn một dòng, bấm mở lại.
    app.debugPutPosts('dm', [
      MmPost({
        'id': 'run', 'channel_id': 'dm', 'user_id': 'bot', 'create_at': _now - 140000, 'update_at': _now,
        'message': 'Xong.', 'props': {'flygo_agent': {'status': 'done', 'texts': [''], 'steps': [], 'bg': _tasks(done: true)}, 'flygo_agent_message': {}},
      }),
    ]);
    app.notifyListeners();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Tác vụ nền · 2 xong · 1 dừng · 1 lỗi'), findsOneWidget);
    expect(find.text('Chạy toàn bộ test Flutter'), findsNothing);
    await t.tap(find.byKey(const ValueKey('bg-head')));
    await t.pump();
    expect(find.text('Chạy toàn bộ test Flutter'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  final out = Platform.environment['BG_OUT'];
  for (final done in [false, true]) {
    for (final dark in [false, true]) {
      for (final (name, size) in [('phone', Size(390, 1240)), ('desktop', Size(1200, 900))]) {
        if (done && name == 'desktop') continue;
        testWidgets('ảnh tác vụ nền ${done ? 'xong' : 'đang chạy'} $name ${dark ? 'dark' : 'light'}', (t) async {
          if (out == null) return;
          await _fonts();
          t.view.physicalSize = size * 2;
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          await t.pumpWidget(_wrap(_app(done: done), dark ? Brightness.dark : Brightness.light, key));
          await t.pump(const Duration(milliseconds: 300));
          // Trạng thái mở giữ theo id tin suốt phiên app (cả giữa các test): chỉ bấm khi đang đóng.
          if (!done && find.byType(BgOutputView).evaluate().isEmpty) {
            await t.tap(find.text('Chạy toàn bộ test Flutter'));
            await t.pump(const Duration(milliseconds: 300));
          } else if (done && find.text('Chạy toàn bộ test Flutter').evaluate().isEmpty) {
            await t.tap(find.byKey(const ValueKey('bg-head')));
            await t.pump(const Duration(milliseconds: 300));
          }
          await t.runAsync(() async {
            final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            await File('$out/${done ? 'done' : 'running'}-$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
          });
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
