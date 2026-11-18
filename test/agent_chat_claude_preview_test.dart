// Chat với trợ lý kiểu app Claude trong khung chat thật (tin giả).
// Ảnh xem trước (chạy tay): AGENT_OUT=<thư mục> flutter test test/agent_chat_claude_preview_test.dart
// Phông emoji màu (tuỳ chọn): EMOJI_FONT=<NotoColorEmoji.ttf>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
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
  await load('Flygo Roboto', [for (final f in ['Regular', 'Italic', 'Medium', 'Bold']) 'assets/fonts/Roboto-$f.ttf']);
  await load('JetBrains Mono', [for (final f in ['Regular', 'Medium', 'Bold']) 'assets/fonts/JetBrainsMono-$f.ttf']);
  final emoji = Platform.environment['EMOJI_FONT'];
  if (emoji != null) await load('Noto Color Emoji', [emoji]);
}

const _answer = '''✅ Em đã giao session **app shell** sửa **Bảng tin trên máy tính** (làm gấp, vì đang chờ để cài toàn bộ máy):

- 📐 Bấm vào một bài thì **khung chi tiết bên phải rộng hơn**, khoảng một nửa cửa sổ.
- ↔️ **Kéo được vạch ngăn** giữa danh sách và khung chi tiết để chỉnh độ rộng:
  - con trỏ đổi hình khi rê vào vạch;
  - bấm đúp vạch để về độ rộng mặc định;
  - **độ rộng được nhớ lại** sau khi tắt app.
- 📱 Điện thoại giữ nguyên.

ℹ️ **Bản build Windows vừa rồi bị lỗi**, do lần build em huỷ lúc trước vẫn còn chạy trong máy ảo và giữ file log. Em sẽ **khởi động lại máy ảo** rồi build lại một lần sau khi có phần Bảng tin, sau đó cài lên toàn bộ máy nhân viên.

Các bước tiếp theo:

1. Build lại bản Windows
   1. dừng máy ảo cũ;
   2. xoá file log bị khoá.
2. Cài lên **toàn bộ máy** nhân viên.''';

AppState _app(int now) {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica', 'create_at': now - 86400000});
  var i = 0;
  MmPost post(String user, String text, int at, {Map<String, dynamic> props = const {}}) => MmPost({
        'id': 'p${i++}',
        'channel_id': 'dm',
        'user_id': user,
        'message': text,
        'create_at': at,
        'update_at': at,
        'props': props,
      });
  final posts = [
    post('me', 'Sửa giúp em Bảng tin bản máy tính: khung chi tiết hẹp quá, muốn kéo được độ rộng', now - 5 * 60000),
    post('bot', _answer, now - 60000, props: {
      'flygo_agent': {
        'status': 'done',
        'engine': 'claude',
        'config': {'model': 'claude-opus-5-5', 'effort': 'high'},
        'texts': [''],
        'steps': [
          {'id': 'a', 'seg': 0, 'kind': 'command', 'status': 'done', 'title': r'$ git -C bang-tin log --oneline -3', 'label': 'Xem lịch sử nhánh'},
          {'id': 'b', 'seg': 0, 'kind': 'command', 'status': 'done', 'title': r'$ multica issue list --status open', 'label': 'Xem việc đang mở'},
          {'id': 'c', 'seg': 0, 'kind': 'message', 'status': 'done', 'title': 'Gửi việc cho session app shell', 'label': 'app shell'},
        ],
      },
      'flygo_agent_message': {'streaming': false},
    }),
  ];
  app.debugPutPosts('dm', posts.reversed.toList());
  app.hasMore['dm'] = false;
  app.online = true;
  return app;
}

Widget _wrap(AppState app, Brightness b, Key key) => ChangeNotifierProvider<AppState>.value(
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
  final out = Platform.environment['AGENT_OUT'];
  for (final dark in [false, true]) {
    for (final (name, size) in [('phone', Size(390, 1240)), ('desktop', Size(1200, 860))]) {
      testWidgets('ảnh chat trợ lý $name ${dark ? 'dark' : 'light'}', (t) async {
        if (out == null) return;
        await _fonts();
        t.view.physicalSize = size * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(_wrap(_app(DateTime.now().millisecondsSinceEpoch), dark ? Brightness.dark : Brightness.light, key));
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
