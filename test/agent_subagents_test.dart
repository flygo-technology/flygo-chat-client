// Sub-agent của lượt chạy (props.flygo_agent.subagents, runner 0.7.37): danh sách cạnh tác vụ nền, hộp xem lời giao +
// kết quả, nút Dừng (ext action subagent_stop).
// Ảnh mockup (chạy tay): SUB_OUT=<thư mục> [EMOJI_FONT=<NotoColorEmoji.ttf>] flutter test test/agent_subagents_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_subagents.dart';
import 'package:flygo_chat/ui/agent_traffic.dart';
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

List<Map<String, dynamic>> _agents() => [
      {
        'id': 'toolu_01', 'type': 'Explore', 'title': 'Tìm chỗ vẽ nút + ở tab Agents', 'model': 'claude-sonnet-5',
        'prompt': 'Tìm trong lib/ui mọi chỗ đặt nút **+** nổi (PlusFab) và cách tính khoảng cách đáy. Trả về đường dẫn + số dòng, không sửa gì.',
        'background': false, 'status': 'done', 'started_at': _now - 240000, 'ended_at': _now - 150000, 'updated_at': _now - 150000,
        'tool_uses': 14, 'tokens': {'total': 18400},
        'result': 'Tìm thấy 3 chỗ:\n- `lib/ui/agents_view.dart:405` `_fab`\n- `lib/ui/schedules_view.dart:251`\n- `lib/ui/home_page.dart:2505`\n\nCả ba dùng `PlusFab.bottomOf` (cộng 112 px cho thanh tab điện thoại).',
      },
      {
        'id': 'toolu_02', 'type': 'general-purpose', 'title': 'Chạy toàn bộ test Flutter và tóm tắt lỗi', 'model': 'claude-opus-5-5',
        'prompt': 'Chạy `flutter test -j 2` trong worktree agent-chat-ui, gom các test lỗi theo tệp, với mỗi lỗi ghi Expected/Actual. Không sửa code.',
        'background': true, 'status': 'running', 'started_at': _now - 95000, 'updated_at': _now - 2000,
        'last_action': 'Đã chạy: flutter test -j 2 > /tmp/full.log', 'tool_uses': 6, 'tokens': {'input': 9100, 'output': 1200},
      },
      {
        'id': 'toolu_03', 'type': 'Explore', 'title': 'Đọc hợp đồng props flygo_agent.subagents của runner', 'model': 'claude-sonnet-5',
        'prompt': 'Đọc agent/src/card.ts và runner.ts, liệt kê các trường của props.flygo_agent.subagents.',
        'background': false, 'status': 'running', 'started_at': _now - 31000, 'updated_at': _now - 1000,
        'last_action': 'Đọc agent/src/card.ts', 'tool_uses': 3, 'tokens': {'total': 5200},
      },
    ];

AppState _app() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica'});
  app.online = true;
  app.debugPutPosts('dm', [
    MmPost({
      'id': 'run', 'channel_id': 'dm', 'user_id': 'bot', 'create_at': _now - 250000, 'update_at': _now - 1000,
      'message': 'Em chia việc cho 3 sub-agent: một bạn tìm chỗ đặt nút +, một bạn chạy toàn bộ test ở nền, một bạn đọc hợp đồng props của runner.',
      'props': {
        'flygo_agent_owner': 'me',
        'flygo_agent': {
          'status': 'running', 'engine': 'claude', 'texts': [''], 'subagents': _agents(),
          'steps': [{'id': 'a', 'seg': 0, 'kind': 'tool', 'status': 'done', 'title': 'Task: Tìm chỗ vẽ nút +', 'label': 'Giao 3 sub-agent'}],
        },
        'flygo_agent_message': {'streaming': true},
      },
    }),
    MmPost({'id': 'u1', 'channel_id': 'dm', 'user_id': 'me', 'message': 'Sửa nút + ở tab Agents, chạy lại test giúp em', 'create_at': _now - 260000}),
  ]);
  app.hasMore['dm'] = false;
  return app;
}

Widget _wrap(AppState app, Brightness b) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const ChatPage(channelId: 'dm'),
      )),
    );

void main() {
  testWidgets('running sub-agents are listed; tap opens prompt + result; done-only collapses', (t) async {
    t.view.physicalSize = const Size(420, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_app(), Brightness.light));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AgentSubagents), findsOneWidget);
    expect(find.textContaining('2 đang chạy', findRichText: true), findsWidgets);
    expect(find.text('Chạy toàn bộ test Flutter và tóm tắt lỗi'), findsOneWidget);
    expect(find.text('Đọc agent/src/card.ts'), findsOneWidget);
    expect(find.textContaining('14 công cụ'), findsOneWidget);
    expect(find.textContaining('18k token'), findsOneWidget);

    await t.tap(find.text('Tìm chỗ vẽ nút + ở tab Agents'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(AgentTrafficView), findsOneWidget);
    expect(find.textContaining('Kết quả'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-traffic-stop')), findsNothing, reason: 'sub-agent đã xong: không có nút Dừng');
    await t.tap(find.byTooltip('Đóng'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Chạy toàn bộ test Flutter và tóm tắt lỗi'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('agent-traffic-stop')), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  final out = Platform.environment['SUB_OUT'];
  for (final dark in [false, true]) {
    for (final (name, size) in [('phone', Size(390, 1240)), ('desktop', Size(1200, 900))]) {
      for (final dialog in [false, true]) {
        testWidgets('mockup sub-agent ${dialog ? 'hộp xem' : 'danh sách'} $name ${dark ? 'dark' : 'light'}', (t) async {
          if (out == null) return;
          await _fonts();
          t.view.physicalSize = size * 2;
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.reset);
          await t.pumpWidget(_wrap(_app(), dark ? Brightness.dark : Brightness.light));
          await t.pump(const Duration(milliseconds: 400));
          if (dialog) {
            await t.tap(find.text('Chạy toàn bộ test Flutter và tóm tắt lỗi'));
            await t.pump(const Duration(milliseconds: 600));
            await t.pump(const Duration(milliseconds: 600));
          }
          await t.runAsync(() async {
            final layer = t.binding.renderViews.first.child!.debugLayer! as OffsetLayer;
            final img = await layer.toImage(Offset.zero & size, pixelRatio: 2);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            await File('$out/${dialog ? 'dialog' : 'list'}-$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
          });
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
