// Kế hoạch việc (props.flygo_agent.todos) luôn ở cuối tin của trợ lý, dưới chữ và các bước;
// kế hoạch dài thì gọn về việc đang làm.
// Ảnh xem trước (chạy tay): PLAN_OUT=<thư mục> [EMOJI_FONT=<NotoColorEmoji.ttf>] flutter test test/plan_at_bottom_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
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

const _long = [
  {'text': 'Đọc log build Windows', 'status': 'completed'},
  {'text': 'Tìm tiến trình giữ file flygo_chat.exe', 'status': 'completed'},
  {'text': 'Khởi động lại máy ảo build', 'status': 'in_progress'},
  {'text': 'Build lại bản Windows', 'status': 'pending'},
  {'text': 'Ký số bản cài', 'status': 'pending'},
  {'text': 'Cài lên toàn bộ máy nhân viên', 'status': 'pending'},
];
const _short = [
  {'text': 'Kiểm tra thư viện AES', 'status': 'completed'},
  {'text': 'Giải mã lớp 1', 'status': 'completed'},
  {'text': 'Báo kết quả cho Sếp', 'status': 'completed'},
];

AppState _app() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica'});
  app.online = true;
  final now = DateTime.now().millisecondsSinceEpoch;
  MmPost run(String id, int at, String msg, Map<String, dynamic> agent, {bool streaming = false}) => MmPost({
        'id': id, 'channel_id': 'dm', 'user_id': 'bot', 'message': msg, 'create_at': at, 'update_at': at,
        'props': {'flygo_agent': agent, 'flygo_agent_message': {'streaming': streaming}},
      });
  final posts = [
    MmPost({'id': 'u1', 'channel_id': 'dm', 'user_id': 'me', 'message': 'Giải mã giúp em backup modem', 'create_at': now - 30 * 60000}),
    run('done', now - 25 * 60000, 'Đã giải mã xong lớp 1, cấu hình nằm ở `config.xml`.', {
      'status': 'done', 'engine': 'claude', 'texts': [''], 'todos': _short,
      'steps': [
        {'id': 'a', 'seg': 0, 'kind': 'command', 'status': 'done', 'title': r'$ python3 decrypt.py', 'label': 'Giải mã lớp 1'},
      ],
    }),
    MmPost({'id': 'u2', 'channel_id': 'dm', 'user_id': 'me', 'message': 'Sửa bản build Windows rồi cài cho mọi người', 'create_at': now - 5 * 60000}),
    run('live', now - 4 * 60000, 'Máy ảo cũ còn giữ file log nên build lỗi. Em đang khởi động lại máy ảo.', {
      'status': 'running', 'engine': 'claude', 'texts': [''], 'todos': _long,
      'steps': [
        {'id': 'a', 'seg': 0, 'kind': 'command', 'status': 'done', 'title': r'$ tail -50 build.log', 'label': 'Đọc log build'},
        {'id': 'b', 'seg': 0, 'kind': 'command', 'status': 'running', 'title': r'$ VBoxManage controlvm build reset', 'label': 'Khởi động lại máy ảo'},
      ],
    }, streaming: true),
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
  testWidgets('plan sits at the end of the message, below text and steps; long plan shows the current item', (t) async {
    t.view.physicalSize = const Size(420, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_app(), Brightness.light));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AgentTodoList), findsNWidgets(2));
    final lists = find.byType(AgentTodoList);
    // Lượt đã xong: gọn một dòng "6/6 · Đã xong kế hoạch", nằm dưới câu trả lời.
    final done = find.ancestor(of: find.text('Đã xong kế hoạch'), matching: lists);
    expect(done, findsOneWidget);
    expect(t.getTopLeft(done).dy, greaterThan(t.getTopLeft(find.textContaining('Đã giải mã xong')).dy));
    // Lượt đang chạy: dưới chữ và dưới các bước; một dòng "đã xong/tổng · việc đang làm" + thanh tiến độ.
    final live = find.ancestor(of: find.text('Khởi động lại máy ảo build'), matching: lists);
    expect(live, findsOneWidget);
    expect(t.getTopLeft(live).dy, greaterThan(t.getTopLeft(find.textContaining('Máy ảo cũ còn giữ')).dy));
    expect(find.descendant(of: live, matching: find.text('2/6')), findsOneWidget);
    expect(find.descendant(of: live, matching: find.byType(AgentProgressBar)), findsOneWidget);
    expect(find.text('Ký số bản cài'), findsNothing);
    expect(find.text('Báo kết quả cho Sếp'), findsNothing);
    // Bấm để xem hết, bấm lần nữa để gọn lại.
    await t.tap(find.descendant(of: live, matching: find.byKey(const ValueKey('todo-head'))));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Ký số bản cài'), findsOneWidget);
    await t.tap(find.descendant(of: live, matching: find.byKey(const ValueKey('todo-head'))));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Ký số bản cài'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a standalone run card also puts the plan below its steps', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: AgentRunCard(run: {
          'status': 'running', 'title': 'Build', 'todos': _short,
          'steps': [{'id': 'a', 'kind': 'command', 'status': 'done', 'title': r'$ ls'}],
        }),
      ),
    ));
    expect(t.getTopLeft(find.byType(AgentTodoList)).dy, greaterThan(t.getTopLeft(find.textContaining('ls')).dy));
  });

  final out = Platform.environment['PLAN_OUT'];
  for (final dark in [false, true]) {
    for (final (name, size) in [('phone', Size(390, 1240)), ('desktop', Size(1200, 900))]) {
      testWidgets('ảnh kế hoạch ở cuối $name ${dark ? 'dark' : 'light'}', (t) async {
        if (out == null) return;
        await _fonts();
        t.view.physicalSize = size * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(_wrap(_app(), dark ? Brightness.dark : Brightness.light, key));
        await t.pump(const Duration(milliseconds: 400));
        await t.pump(const Duration(milliseconds: 400));
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
