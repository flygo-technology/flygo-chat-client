// Nhãn tin giữa các agent (props.flygo_agent_link, runner 0.7.14+) và props cũ.
// Ảnh xem trước (chạy tay): LINK_OUT=<thư mục> [EMOJI_FONT=<NotoColorEmoji.ttf>] flutter test test/agent_link_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agent_link.dart';
import 'package:flygo_chat/ui/agent_view.dart';
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

MmPost _post(String id, String user, String msg, Map<String, dynamic> props, {int at = 0, String ch = 'dm'}) =>
    MmPost({'id': id, 'channel_id': ch, 'user_id': user, 'message': msg, 'create_at': at, 'update_at': at, 'props': props});

AppState _app() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica'});
  app.channels['s2aaaaaaaaaaaaaaaaaaaaaaaa'] = MmChannel({'id': 's2aaaaaaaaaaaaaaaaaaaaaaaa', 'type': 'P', 'display_name': 'Build Windows'});
  app.online = true;
  return app;
}

const _s2 = 's2aaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('flygo_agent_link: handoff in, reply out, external agent, unknown session', () {
    final app = _app();
    var l = agentLinkOf(app, _post('a', 'bot', 'x', {
      'flygo_agent_link': {'v': 1, 'kind': 'handoff', 'dir': 'in', 'from': {'session': _s2, 'name': 'Build Windows', 'bot': 'jessica'}}
    }))!;
    expect(l.tone, AgentLinkTone.incoming);
    expect(l.label, '📨 Từ phiên Build Windows · @jessica');
    expect(l.sub, 'giao việc');
    expect(l.openChannel, _s2);

    l = agentLinkOf(app, _post('b', 'bot', 'x', {
      'flygo_agent_link': {'v': 1, 'kind': 'reply', 'dir': 'out', 'to': {'session': 'zzzzzzzzzzzzzzzzzzzzzzzzzz', 'name': 'Kế toán', 'bot': 'jenifer'}}
    }))!;
    expect(l.tone, AgentLinkTone.reply);
    expect(l.label, '↩︎ Trả lời phiên Kế toán · @jenifer');
    expect(l.openChannel, isNull, reason: 'không có trong danh sách chat của mình thì không mở');

    l = agentLinkOf(app, _post('c', 'me', 'x', {
      'flygo_bridge': {'token_id': 't'},
      'flygo_agent_link': {'v': 1, 'kind': 'message', 'dir': 'in', 'from': {'agent': 'Claude Code · macbook'}}
    }))!;
    expect(l.tone, AgentLinkTone.external);
    expect(l.label, '🔗 Agent ngoài Claude Code · macbook');
    expect(l.sub, 'gửi qua Token MCP');

    // Không có tên: lấy tên chat đang có.
    l = agentLinkOf(app, _post('d', 'bot', 'x', {
      'flygo_agent_link': {'v': 1, 'kind': 'message', 'dir': 'in', 'from': {'session': _s2}}
    }))!;
    expect(l.label, '📨 Từ phiên Build Windows');
  });

  test('older runners: a2a_from, team_from, bridge, session handoff, bg task result', () {
    final app = _app();
    expect(agentLinkOf(app, _post('a', 'bot', 'x', {'flygo_a2a_from': {'bot_id': 'bot', 'username': 'jessica', 'title': 'Build Windows'}}))!.label,
        '📨 Từ phiên Build Windows');
    expect(agentLinkOf(app, _post('b', 'bot', 'x', {'flygo_a2a_from': {'bot_id': 'x', 'username': 'jenifer'}}))!.label, '📨 Từ @jenifer');
    final t = agentLinkOf(app, _post('c', 'bot', 'x', {'flygo_team_from': {'bot_id': 'x', 'username': 'jenifer', 'session': _s2}}))!;
    expect(t.label, '📨 Từ phiên Build Windows · @jenifer');
    expect(t.openChannel, _s2);
    expect(agentLinkOf(app, _post('d', 'me', 'x', {'flygo_bridge': {'token_id': 't'}}))!.label, '🔗 Agent ngoài');
    final moved = agentLinkOf(app, _post('e', 'bot', 'x', {'flygo_session_handoff': {'kind': 'moved', 'from': 'dm', 'to': _s2, 'title': 'Build Windows'}}))!;
    expect(moved.label, '➡️ Chuyển sang phiên Build Windows');
    expect(moved.openChannel, _s2);
    expect(agentLinkOf(app, _post('f', 'bot', 'x', {'flygo_session_handoff': {'kind': 'task', 'from': _s2, 'to': 'dm', 'title': 'Dọn log'}}))!.sub, 'việc chạy ngầm');
    expect(agentLinkOf(app, _post('g', 'bot', 'x', {'flygo_bg_task_result': {'task': _s2, 'title': 'Build Windows', 'ok': true}}))!.label,
        '↩︎ Kết quả từ phiên Build Windows');
    expect(agentLinkOf(app, _post('h', 'bot', 'Tin thường', {})), isNull);
  });

  test('sender side: agent_send steps give "➡️ Gửi tới …" + reply count, and the summary line names the target', () {
    final app = _app();
    final steps = [
      {'id': 'a', 'seg': 0, 'kind': 'tool', 'status': 'done', 'title': 'agent_send', 'agent_link': {'v': 1, 'kind': 'handoff', 'dir': 'out', 'to': {'session': _s2, 'name': 'Build Windows'}}},
      {'id': 'b', 'seg': 0, 'kind': 'message', 'status': 'done', 'title': 'phiên Build Windows trả lời: xong', 'agent_link': {'v': 1, 'kind': 'reply', 'dir': 'in', 'from': {'session': _s2}}},
      {'id': 'c', 'seg': 0, 'kind': 'command', 'status': 'done', 'title': r'$ ls'},
    ];
    final l = agentLinkOf(app, _post('a', 'bot', 'Xong', {'flygo_agent': {'status': 'done', 'texts': [''], 'steps': steps}}))!;
    expect(l.tone, AgentLinkTone.outgoing);
    expect(l.label, '➡️ Gửi tới phiên Build Windows');
    expect(l.sub, 'đã trả lời');
    expect(l.openChannel, _s2);
    expect(agentStepsSummaryText(steps), 'Đã chạy 1 lệnh, Đã gửi tới phiên Build Windows, nhận 1 câu trả lời');
  });

  final out = Platform.environment['LINK_OUT'];
  for (final dark in [false, true]) {
    for (final (name, size) in [('phone', Size(390, 1240)), ('desktop', Size(1200, 900))]) {
      testWidgets('ảnh nhãn tin giữa agent $name ${dark ? 'dark' : 'light'}', (t) async {
        if (out == null) return;
        await _fonts();
        final app = _app();
        final now = DateTime.now().millisecondsSinceEpoch;
        final posts = [
          _post('p1', 'bot', '🤝 **Phiên "Build Windows" nhờ:**\nKiểm tra giúp log build Windows mới nhất, báo lỗi đầu tiên.', {
            'flygo_agent_link': {'v': 1, 'kind': 'handoff', 'dir': 'in', 'from': {'session': _s2, 'name': 'Build Windows', 'bot': 'jessica'}}
          }, at: now - 9 * 60000),
          _post('p2', 'bot', 'Lỗi đầu tiên: `LNK1104: cannot open file flygo_chat.exe` (file đang bị máy ảo cũ giữ).', {
            'flygo_agent_link': {'v': 1, 'kind': 'reply', 'dir': 'out', 'to': {'session': _s2, 'name': 'Build Windows', 'bot': 'jessica'}},
            'flygo_agent': {'status': 'done', 'engine': 'claude', 'texts': [''], 'steps': [
              {'id': 'x', 'seg': 0, 'kind': 'command', 'status': 'done', 'title': r'$ tail -50 build.log'}
            ]},
            'flygo_agent_message': {'streaming': false},
          }, at: now - 8 * 60000),
          _post('p3', 'me', 'Đã chạy xong test trên macbook: 42/42 qua.', {
            'flygo_bridge': {'token_id': 't'},
            'flygo_agent_link': {'v': 1, 'kind': 'message', 'dir': 'in', 'from': {'agent': 'Claude Code · macbook'}}
          }, at: now - 5 * 60000),
          _post('p4', 'me', 'Nhờ phiên Kiểm thử Android chạy lại test trên máy ảo', {}, at: now - 3 * 60000),
          _post('p5', 'bot', 'Phiên **Kiểm thử Android** đã chạy lại: 118/118 qua ✅', {
            'flygo_agent': {'status': 'done', 'engine': 'claude', 'texts': [''], 'steps': [
              {'id': 'a', 'seg': 0, 'kind': 'tool', 'status': 'done', 'title': 'agent_send', 'agent_link': {'v': 1, 'kind': 'handoff', 'dir': 'out', 'to': {'session': _s2, 'name': 'Kiểm thử Android'}}},
              {'id': 'b', 'seg': 0, 'kind': 'message', 'status': 'done', 'title': 'phiên Kiểm thử Android trả lời: 118/118 qua', 'agent_link': {'v': 1, 'kind': 'reply', 'dir': 'in', 'from': {'session': _s2, 'name': 'Kiểm thử Android'}}},
            ]},
            'flygo_agent_message': {'streaming': false},
          }, at: now - 60000),
        ];
        app.debugPutPosts('dm', posts.reversed.toList());
        app.hasMore['dm'] = false;
        t.view.physicalSize = size * 2;
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
              locale: const Locale('vi'),
              supportedLocales: const [Locale('vi'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: const ChatPage(channelId: 'dm'),
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(AgentLinkChip), findsNWidgets(4));
        await t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
