// Ảnh nhóm chat của dự án cho video "Làm việc nhóm": ChatPage thật, tin giả (bot Làm việc nhóm đăng cập nhật tiến độ).
// Chạy tay: TW_VIDEO_OUT=<thư mục> flutter test test/teamwork_video_chat_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

import 'fixtures/teamwork_fake.dart' show twFonts;

final _start = DateTime(2026, 11, 19, 9, 30).millisecondsSinceEpoch;

AppState _app() {
  final app = AppState('t')
    ..me = MmUser({'id': 'me', 'username': 'lan', 'first_name': 'Lan'})
    ..online = true;
  for (final (id, name) in [('me', 'Lan'), ('u2', 'Minh'), ('u3', 'Thu'), ('u4', 'Hùng')]) {
    app.users[id] = MmUser({'id': id, 'username': name.toLowerCase(), 'first_name': name});
  }
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'teamwork-app', 'first_name': 'Làm việc nhóm', 'is_bot': true});
  app.channels['c'] = MmChannel({'id': 'c', 'type': 'P', 'display_name': 'Ra mắt app bán hàng', 'purpose': 'Nhóm chat của dự án RA · Làm việc nhóm', 'create_at': _start - 60000});
  var i = 0;
  MmPost post(String user, String text, {String root = '', List<String> react = const []}) => MmPost({
        'id': 'p${i++}',
        'channel_id': 'c',
        'user_id': user,
        'message': text,
        'root_id': root,
        'create_at': _start + i * 60000,
        'props': {},
        'metadata': {
          'reactions': [for (final r in react) {'emoji_name': r, 'user_id': 'u2'}],
        },
      });
  final posts = [
    post('bot',
        '**Cập nhật tiến độ · Ra mắt app bán hàng**\n\n'
        '- Đã xong **23/54** việc (43%), hạn ra mắt 15/01\n'
        '- Việc mới giai đoạn 3: RA-70 Đào tạo đại lý miền Bắc (Thu, 05/01), RA-71 Đào tạo đại lý miền Nam (Hùng, 09/01), RA-72 Quay video hướng dẫn đặt hàng (Minh, 20/12)\n'
        '- Cần chú ý: RA-35 và RA-38 sắp tới hạn',
        ),
    post('u3', 'Em nhận RA-70 ạ, tuần sau em gửi lịch đào tạo.'),
    post('u4', 'Ok, RA-71 mình lo nhé.'),
    post('u2', 'Video hướng dẫn mình quay xong trước 20/12.'),
  ];
  app.debugPutPosts('c', posts.reversed.toList());
  app.hasMore['c'] = false;
  return app;
}

void main() {
  final out = Platform.environment['TW_VIDEO_OUT'];
  testWidgets('nhóm chat dự án (máy tính, sáng)', (t) async {
    await t.runAsync(twFonts);
    t.view.physicalSize = const Size(1440, 900) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: _app(),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const ChatPage(channelId: 'c'),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Em nhận RA-70'), findsOneWidget);
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/v-chat.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox.shrink());
  });
}
