// Tin qua lại giữa các agent thu gọn sẵn; bản ghi tin đã gửi (➡️, runner 0.7.15) có câu trả lời lồng bên dưới.
// Ảnh xem trước (chạy tay): TRAFFIC_OUT=<thư mục> [EMOJI_FONT=<NotoColorEmoji.ttf>] flutter test test/agent_traffic_collapse_test.dart
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

const _s2 = 's2aaaaaaaaaaaaaaaaaaaaaaaa';
const _s3 = 's3aaaaaaaaaaaaaaaaaaaaaaaa';

MmPost _post(String id, String user, String msg, Map<String, dynamic> props, int at) =>
    MmPost({'id': id, 'channel_id': 'dm', 'user_id': user, 'message': msg, 'create_at': at, 'update_at': at, 'props': props});

AppState _app({bool withPosts = true}) {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica'});
  app.channels[_s2] = MmChannel({'id': _s2, 'type': 'P', 'display_name': 'Kiểm thử Android'});
  app.channels[_s3] = MmChannel({'id': _s3, 'type': 'P', 'display_name': 'Build Windows'});
  app.online = true;
  if (!withPosts) return app;
  final now = DateTime.now().millisecondsSinceEpoch;
  final posts = [
    _post('p1', 'bot', '🤝 **Phiên "Build Windows" nhờ:**\nKiểm tra giúp log build Windows mới nhất, báo lỗi đầu tiên và đề xuất cách sửa.', {
      'flygo_agent_link': {'v': 1, 'kind': 'handoff', 'dir': 'in', 'from': {'session': _s3, 'name': 'Build Windows', 'bot': 'jessica'}}
    }, now - 20 * 60000),
    _post('p2', 'me', 'Nhờ phiên Kiểm thử Android chạy lại toàn bộ test trên máy ảo rồi báo kết quả', {}, now - 6 * 60000),
    _post('p3', 'bot', 'Chạy lại toàn bộ test Flutter trên máy ảo ct-a (bản 513), gửi số test qua / lỗi và tên test lỗi nếu có.', {
      'flygo_silent': true,
      'flygo_agent_link': {
        'v': 1, 'kind': 'handoff', 'dir': 'out', 'id': 'u1',
        'from': {'session': 'dm', 'name': 'Phiên chính', 'bot': 'jessica'},
        'to': {'session': _s2, 'name': 'Kiểm thử Android', 'bot': 'jessica'},
        'reply': {'state': 'completed', 'text': 'Đã chạy xong trên ct-a:\n- **1192** test qua\n- 1 bỏ qua\n- 0 lỗi', 'at': now - 2 * 60000},
      },
    }, now - 5 * 60000),
    _post('p4', 'me', 'Đã chạy test trên macbook: 42/42 qua, log ở ~/logs/test-513.txt', {
      'flygo_bridge': {'token_id': 't'},
      'flygo_agent_link': {'v': 1, 'kind': 'message', 'dir': 'in', 'from': {'agent': 'Claude Code · macbook'}}
    }, now - 3 * 60000),
    _post('p5', 'bot', 'Phiên **Kiểm thử Android** đã chạy lại: 1192 test qua, không lỗi ✅', {
      'flygo_agent': {'status': 'done', 'engine': 'claude', 'texts': [''], 'steps': [
        {'id': 'a', 'seg': 0, 'kind': 'tool', 'status': 'done', 'title': 'agent_send', 'agent_link': {'v': 1, 'kind': 'handoff', 'dir': 'out', 'to': {'session': _s2, 'name': 'Kiểm thử Android', 'bot': 'jessica'}}},
      ]},
      'flygo_agent_message': {'streaming': false},
    }, now - 60000),
  ];
  app.debugPutPosts('dm', posts.reversed.toList());
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

void main() {
  testWidgets('agent traffic is collapsed by default; the outgoing record expands with its reply nested; Thu gọn folds it', (t) async {
    t.view.physicalSize = const Size(420, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = _app();
    await t.pumpWidget(_wrap(app, Brightness.light));
    await t.pump(const Duration(milliseconds: 300));
    // Thu gọn: tin nhờ từ phiên khác, bản ghi đã gửi, tin agent ngoài. Câu trả lời của trợ lý cho mình không thu gọn.
    expect(find.byType(AgentTrafficCollapsed), findsNWidgets(3));
    expect(find.textContaining('1192 test qua, không lỗi'), findsOneWidget);
    // Có bản ghi riêng: câu trả lời cuối không lặp nhãn "➡️ Gửi tới".
    expect(find.text('➡️ Gửi tới phiên Kiểm thử Android · @jessica'), findsOneWidget);
    expect(find.text('đã trả lời'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('agent-traffic-p3')));
    await t.pump(const Duration(milliseconds: 300));
    expect(app.expanded, contains('p3'));
    expect(find.byType(AgentTrafficCollapsed), findsNWidgets(2));
    expect(find.byKey(const ValueKey('agent-reply-p3')), findsOneWidget);
    expect(find.text('↩︎ phiên Kiểm thử Android · @jessica trả lời · ${_hm(DateTime.now().subtract(const Duration(minutes: 2)))}'), findsOneWidget);

    await t.tap(find.text('Thu gọn'));
    await t.pump(const Duration(milliseconds: 300));
    expect(app.expanded, isNot(contains('p3')));
    expect(find.byType(AgentTrafficCollapsed), findsNWidgets(3));
    await t.pumpWidget(const SizedBox.shrink());
  });

  test('external agent record: "delivered" until the bridge reply arrives, then that reply is nested', () {
    final app = _app(withPosts: false);
    final rec = _post('r', 'bot', 'Chạy test trên macbook giúp em', {
      'flygo_agent_link': {'v': 1, 'kind': 'message', 'dir': 'out', 'to': {'agent': 'Claude Code · macbook', 'session': 'dm'},
        'reply': {'state': 'delivered', 'text': 'Đã gửi vào hộp thư', 'at': 1, 'message_id': 'm9'}},
    }, 1000);
    app.debugPutPosts('dm', [rec]);
    var l = agentLinkOf(app, rec)!;
    expect(l.label, '➡️ Gửi tới agent ngoài Claude Code · macbook');
    expect(l.sub, 'đã gửi vào hộp thư');
    expect(l.reply, isNull);
    expect(l.traffic, isTrue);
    final ans = _post('b', 'me', '42/42 qua', {
      'flygo_bridge': {'token_id': 't', 'reply_to': 'm9'},
      'flygo_agent_link': {'v': 1, 'kind': 'reply', 'dir': 'in', 'from': {'agent': 'Claude Code · macbook'}},
    }, 5000);
    app.debugPutPosts('dm', [ans, rec]);
    l = agentLinkOf(app, rec)!;
    expect(l.sub, 'đã trả lời');
    expect(l.reply?['text'], '42/42 qua');
  });

  final out = Platform.environment['TRAFFIC_OUT'];
  for (final expanded in [false, true]) {
    for (final dark in [false, true]) {
      for (final (name, size) in [('phone', Size(390, 1240)), ('desktop', Size(1200, 900))]) {
        if (expanded && name == 'desktop') continue;
        testWidgets('ảnh ${expanded ? 'mở' : 'thu gọn'} $name ${dark ? 'dark' : 'light'}', (t) async {
          if (out == null) return;
          await _fonts();
          final app = _app();
          if (expanded) app.expanded.add('p3');
          t.view.physicalSize = size * 2;
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          await t.pumpWidget(_wrap(app, dark ? Brightness.dark : Brightness.light, key));
          await t.pump(const Duration(milliseconds: 400));
          await t.pump(const Duration(milliseconds: 400));
          await t.runAsync(() async {
            final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            await File('$out/${expanded ? 'expanded' : 'collapsed'}-$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
          });
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
