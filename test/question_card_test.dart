// Thẻ câu hỏi trắc nghiệm kiểu "chọn đáp án" của Claude: số thứ tự, một lựa chọn bấm là gửi, nhiều lựa chọn tích rồi Gửi,
// dòng Khác ở cuối; hết hạn giữ nguyên giao diện, chỉ mờ đi.
// Ảnh xem trước (chạy tay): QCARD_OUT=<thư mục> flutter test test/question_card_test.dart
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


AppState _app() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'first_name': 'Jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.channels['dm'] = MmChannel({'id': 'dm', 'type': 'D', 'name': 'bot__me', 'display_name': 'Jessica'});
  return app;
}

Map<String, dynamic> _q({bool multi = false, String status = 'pending'}) => {
      'id': 'q1', 'header': multi ? 'Phạm vi' : 'Cách làm', 'multi': multi, 'allow_other': true, 'status': status,
      'question': multi ? 'Em kiểm tra những phần nào của hệ thống?' : 'Sếp muốn em xử lý bản backup modem thế nào?',
      'options': [
        {'label': 'Chỉ giải mã backup', 'description': 'Đọc cấu hình, không chạm vào modem'},
        {'label': 'Giải mã + truy cập admin modem', 'description': 'Cần SSH vào modem, xin duyệt từng bước'},
        {'label': 'Dừng lại', 'description': ''},
      ],
    };

MmPost _post(String id) => MmPost({'id': id, 'channel_id': 'dm', 'user_id': 'bot', 'create_at': 1, 'message': '', 'props': {}});

Widget _wrap(AppState app, Brightness b, Widget child, [Key? key]) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: SingleChildScrollView(child: child))),
        ),
      ),
    );

void main() {
  testWidgets('một lựa chọn: số thứ tự, có dòng Khác, không có nút Gửi; hết hạn thì mờ và không bấm được', (t) async {
    final app = _app();
    await t.pumpWidget(_wrap(app, Brightness.light, AgentQuestionCard(post: _post('p1'), question: _q())));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // dòng Khác
    expect(find.text('Khác…'), findsOneWidget);
    expect(find.byKey(const ValueKey('q-submit')), findsNothing);
    expect(find.byKey(const ValueKey('q-expired')), findsNothing);

    await t.pumpWidget(_wrap(app, Brightness.light, AgentQuestionCard(post: _post('p2'), question: _q(status: 'expired'))));
    expect(find.byKey(const ValueKey('q-expired')), findsOneWidget);
    expect(find.text('Chỉ giải mã backup'), findsOneWidget); // vẫn giữ các lựa chọn
    expect(t.widget<Opacity>(find.byKey(const ValueKey('q-expired'))).opacity, lessThan(1));
  });

  testWidgets('nhiều lựa chọn: tích nhiều rồi mới bật nút Gửi', (t) async {
    final app = _app();
    await t.pumpWidget(_wrap(app, Brightness.light, AgentQuestionCard(post: _post('p3'), question: _q(multi: true))));
    FilledButton btn() => t.widget<FilledButton>(find.byKey(const ValueKey('q-submit')));
    expect(btn().onPressed, isNull);
    await t.tap(find.byKey(const ValueKey('q-opt-0')));
    await t.tap(find.byKey(const ValueKey('q-opt-2')));
    await t.pump();
    expect(btn().onPressed, isNotNull);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
  });

  final out = Platform.environment['QCARD_OUT'];
  if (out != null) {
    for (final dark in [false, true]) {
      for (final (name, q) in [('single', _q()), ('multi', _q(multi: true)), ('expired', _q(status: 'expired'))]) {
        testWidgets('ảnh thẻ câu hỏi $name ${dark ? 'dark' : 'light'}', (t) async {
          await _fonts();
          t.view.physicalSize = const Size(900, 1000);
          t.view.devicePixelRatio = 2;
          addTearDown(t.view.reset);
          final key = GlobalKey();
          await t.pumpWidget(_wrap(_app(), dark ? Brightness.dark : Brightness.light, AgentQuestionCard(post: _post('s-$name-$dark'), question: q), key));
          if (name == 'multi') {
            await t.tap(find.byKey(const ValueKey('q-opt-1')));
            await t.pump();
          }
          await t.runAsync(() async {
            final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
            final png = await img.toByteData(format: ui.ImageByteFormat.png);
            File('$out/qcard-$name-${dark ? 'dark' : 'light'}.png').writeAsBytesSync(png!.buffer.asUint8List());
          });
        });
      }
    }
  }
}
