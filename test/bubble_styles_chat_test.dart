// Kiểu bong bóng trong khung chat thật (tin giả).
// Ảnh xem trước (chạy tay): BUBBLE_OUT=<thư mục> flutter test test/bubble_styles_chat_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/bubble_styles.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _start = DateTime(2026, 12, 20, 8).millisecondsSinceEpoch;

AppState _app() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'an', 'first_name': 'An'});
  for (final (id, name) in [('me', 'An'), ('u2', 'Bình'), ('u3', 'Chi')]) {
    app.users[id] = MmUser({'id': id, 'username': name, 'first_name': name});
  }
  app.channels['c'] = MmChannel({'id': 'c', 'type': 'O', 'display_name': 'Nhóm dự án', 'create_at': _start - 3600000});
  var i = 0;
  MmPost post(String user, String text, {Map<String, dynamic>? bubble, String root = '', List<String> react = const []}) => MmPost({
        'id': 'p${i++}',
        'channel_id': 'c',
        'user_id': user,
        'message': text,
        'root_id': root,
        'create_at': _start + i * 60000,
        'props': {'flygo_bubble': ?bubble},
        'metadata': {
          'reactions': [for (final r in react) {'emoji_name': r, 'user_id': 'u2'}],
        },
      });
  final posts = [
    post('u2', 'Mọi người ơi, thứ 6 tiệc tất niên nhé 🎄', bubble: {'s': 'tuanloc'}),
    post('u2', 'Ai chưa đăng ký thì báo mình', bubble: {'s': 'tuanloc'}),
    post('me', 'Em đăng ký 2 người ạ', bubble: {'s': 'munoel'}),
    post('me', 'Em mang thêm bánh nữa', bubble: {'s': 'munoel'}, react: ['heart']),
    post('u3', 'Báo cáo quý 4 đã duyệt, cảm ơn cả nhóm! https://example.com/q4', bubble: {'s': 'daduyet'}),
    post('me', 'Tuyệt quá 🎉', bubble: {'s': 'meo', 'c': 'FFE0B2'}, root: 'p4'),
    post('u2', 'Tin mặc định không đổi kiểu'),
    post('me', 'Sếp duyệt rồi, em gửi ngay bản ký cho đối tác trong chiều nay', bubble: {'s': 'quockyvn'}),
  ];
  app.debugPutPosts('c', posts.reversed.toList());
  app.hasMore['c'] = false;
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
          home: const ChatPage(channelId: 'c'),
        ),
      ),
    );

void main() {
  testWidgets('tin có props.flygo_bubble vẽ màu + hình trang trí; tin thường giữ nguyên', (t) async {
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_app(), Brightness.light, GlobalKey()));
    await t.pump(const Duration(milliseconds: 300));
    final painters = t.widgetList<CustomPaint>(find.byType(CustomPaint)).map((c) => c.foregroundPainter).whereType<BubbleDecoPainter>().toList();
    expect(painters.map((p) => p.style.id).toSet(), containsAll(['tuanloc', 'munoel', 'daduyet', 'meo', 'quockyvn']));
    // Tin người khác: hình lật ra phía ngoài; tin của mình: không lật.
    expect(painters.where((p) => p.style.id == 'tuanloc').every((p) => p.mirror), isTrue);
    expect(painters.where((p) => p.style.id == 'munoel').every((p) => !p.mirror), isTrue);
    // Lượt hai tin: phần trên chỉ ở tin đầu, phần dưới chỉ ở tin cuối; tin có cảm xúc bỏ phần dưới.
    final noel = painters.where((p) => p.style.id == 'munoel').toList();
    expect(noel.where((p) => p.top).length, 1);
    expect(noel.where((p) => p.bottom).length, 0);
    // Màu tuỳ chỉnh được dùng làm nền.
    expect(painters.firstWhere((p) => p.style.id == 'meo').fill, const Color(0xFFFFE0B2));
    await t.pumpWidget(const SizedBox.shrink());
  });

  final out = Platform.environment['BUBBLE_OUT'];
  for (final dark in [false, true]) {
    for (final (name, size) in [('phone', Size(390, 844)), ('desktop', Size(1100, 760))]) {
      testWidgets('ảnh chat $name ${dark ? 'dark' : 'light'}', (t) async {
        if (out == null) return;
        await _fonts();
        t.view.physicalSize = size * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(_wrap(_app(), dark ? Brightness.dark : Brightness.light, key));
        await t.pump(const Duration(milliseconds: 400));
        await t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/chat-$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
