// Dịch thuật native (lib/ui/dich). Ảnh xem trước (chạy tay): DICH_OUT=<thư mục> flutter test test/dich_native_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/config.dart' show debugIsDesktop;
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/dich/dich_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  Future<void> load(String family, List<File> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      if (f.existsSync()) l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await l.load();
  }

  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  await load('MaterialIcons', [File('$dir/MaterialIcons-Regular.otf')]);
  for (final family in ['Roboto', 'Noto Sans']) {
    await load(family, [
      for (final f in ['noto/NotoSans-Regular.ttf', 'noto/NotoSans-Bold.ttf', 'dejavu/DejaVuSans.ttf', 'dejavu/DejaVuSans-Bold.ttf']) File('/usr/share/fonts/truetype/$f'),
    ]);
  }
}

/// Dịch giả: ghi lại các lần gọi; trả lời sau [delay] (để thấy hiệu ứng đang dịch).
class _Fake {
  final calls = <(String, String)>[];
  Object? fail;
  Completer<void>? hold;
  Future<({String text, String from})> call(String text, String to) async {
    calls.add((text, to));
    if (hold != null) await hold!.future;
    if (fail != null) throw fail!;
    const samples = {
      'en': 'Hello, the elevator on floor 5 needs maintenance this week.',
      'vi': 'Xin chào, thang máy tầng 5 cần bảo trì trong tuần này.',
    };
    return (text: samples[to] ?? '[$to] $text', from: to == 'vi' ? 'en' : 'vi');
  }
}

void main() {
  final out = Platform.environment['DICH_OUT'];
  late _Fake fake;
  setUp(() => fake = _Fake());
  tearDown(() => debugIsDesktop = null);

  Future<void> pump(WidgetTester t, {Size size = const Size(1100, 720), Brightness theme = Brightness.light, bool desktop = true}) async {
    debugIsDesktop = desktop;
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    if (out != null) await t.runAsync(_fonts);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: AppState('t'),
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(theme),
          home: DichPage(translate: fake.call, langs: () async => const ['vi', 'en', 'zh', 'ko', 'ja', 'th']),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 50));
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  TextEditingController ctrl(WidgetTester t, String k) => t.widget<TextField>(find.byKey(ValueKey('dich-$k'))).controller!;

  Future<void> ctrlEnter(WidgetTester t) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Enter thường xuống dòng, không dịch; Ctrl + Enter dịch sang ô phải', (t) async {
    await pump(t);
    await t.tap(find.byKey(const ValueKey('dich-L')));
    await t.enterText(find.byKey(const ValueKey('dich-L')), 'Xin chào');
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump(const Duration(milliseconds: 400));
    expect(fake.calls, isEmpty);
    await ctrlEnter(t);
    expect(fake.calls.single, ('Xin chào', 'en'));
    expect(ctrl(t, 'R').text, startsWith('Hello'));
    // Trái "Tự nhận diện": hiện ngôn ngữ vừa nhận diện.
    expect(find.textContaining('Nhận diện: Tiếng Việt'), findsOneWidget);
  });

  testWidgets('Nút Dịch ở ô phải dịch ngược sang ô trái bằng ngôn ngữ đã nhận diện', (t) async {
    await pump(t);
    await t.enterText(find.byKey(const ValueKey('dich-L')), 'Xin chào');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('dich-go-L')));
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(find.byKey(const ValueKey('dich-R')), 'Good morning');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('dich-go-R')));
    await t.pump(const Duration(milliseconds: 400));
    expect(fake.calls.last, ('Good morning', 'vi'));
    expect(ctrl(t, 'L').text, startsWith('Xin chào, thang máy'));
  });

  testWidgets('Dán (Ctrl + V) vào ô phải: ô trái tự dịch', (t) async {
    await pump(t);
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.getData') return {'text': 'Thank you'};
      if (c.method == 'Clipboard.hasStrings') return {'value': true};
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await t.tap(find.byKey(const ValueKey('dich-R')));
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyV);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump(const Duration(milliseconds: 400));
    expect(ctrl(t, 'R').text, 'Thank you');
    expect(fake.calls.single, ('Thank you', 'vi'));
    expect(ctrl(t, 'L').text, isNotEmpty);
  });

  testWidgets('Bàn phím điện thoại chèn một khối dài (dán): tự dịch; gõ vài chữ: không', (t) async {
    await pump(t, size: const Size(400, 860), desktop: false);
    await t.enterText(find.byKey(const ValueKey('dich-L')), 'Chào');
    await t.pump(const Duration(milliseconds: 400));
    expect(fake.calls, isEmpty);
    await t.enterText(find.byKey(const ValueKey('dich-L')), 'Chào bạn, thang máy tầng 5 cần bảo trì trong tuần này.');
    await t.pump(const Duration(milliseconds: 400));
    expect(fake.calls, hasLength(1));
    // Điện thoại: không gợi ý phím tắt.
    expect(find.textContaining('Ctrl'), findsNothing);
    expect(find.textContaining('Dán vào ô nào'), findsOneWidget);
  });

  testWidgets('Đổi chiều: đổi ngôn ngữ và nội dung hai ô', (t) async {
    await pump(t);
    await t.enterText(find.byKey(const ValueKey('dich-L')), 'Xin chào');
    await ctrlEnterFocused(t, 'L');
    await t.tap(find.byKey(const ValueKey('dich-swap')));
    await t.pump(const Duration(milliseconds: 300));
    expect(ctrl(t, 'L').text, startsWith('Hello'));
    expect(ctrl(t, 'R').text, 'Xin chào');
    expect(find.descendant(of: find.byKey(const ValueKey('dich-lang-L')), matching: find.text('English')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('dich-lang-R')), matching: find.text('Tiếng Việt')), findsOneWidget);
  });

  testWidgets('Sao chép đưa nội dung ô vào bảng nhớ tạm', (t) async {
    await pump(t);
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
      if (c.method == 'Clipboard.setData') copied = (c.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await t.enterText(find.byKey(const ValueKey('dich-L')), 'Xin chào');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('dich-copy-L')));
    await t.pump(const Duration(milliseconds: 100));
    expect(copied, 'Xin chào');
    expect(find.text('Đã sao chép'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('Hết lượt (429): báo dễ hiểu', (t) async {
    fake.fail = const HttpException('rate limit (429)');
    await pump(t);
    await t.enterText(find.byKey(const ValueKey('dich-L')), 'Xin chào');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('dich-go-L')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('dịch quá nhiều'), findsOneWidget);
  });

  test('manifest native.screen "dich" chỉ mở native từ min_client trở lên', () {
    expect(compareAppVersion('1.0.4+478', '1.0.5+479'), lessThan(0));
    expect(compareAppVersion('1.0.5+479', '1.0.5+479'), 0);
    final a = MiniApp.fromJson({'id': 'vn.flygo.dich', 'native': {'screen': kDichScreen, 'min_client': '1.0.5+479'}});
    expect(a.nativeScreen, kDichScreen); // chưa biết bản đang chạy: coi như đủ mới
  });

  // ---------------------------------------------------------------- ảnh xem trước
  for (final (name, size, theme, desktop) in [
    ('dich-may-tinh-sang', const Size(1100, 640), Brightness.light, true),
    ('dich-may-tinh-toi', const Size(1100, 640), Brightness.dark, true),
    ('dich-dien-thoai-sang', const Size(400, 860), Brightness.light, false),
    ('dich-dien-thoai-toi', const Size(400, 860), Brightness.dark, false),
  ]) {
    testWidgets('ảnh $name', (t) async {
      await pump(t, size: size, theme: theme, desktop: desktop);
      await t.enterText(find.byKey(const ValueKey('dich-L')), 'Xin chào, thang máy tầng 5 cần bảo trì trong tuần này.');
      await t.pump(const Duration(milliseconds: 400));
      if (desktop) await ctrlEnterFocused(t, 'L');
      await t.pump(const Duration(milliseconds: 500));
      await shot(t, name);
      // Đang dịch: vệt sáng + ba chấm ở ô kia.
      fake.hold = Completer();
      await t.enterText(find.byKey(const ValueKey('dich-R')), '');
      await t.enterText(find.byKey(const ValueKey('dich-R')), 'Please send the maintenance report to the building manager before Friday.');
      await t.pump(const Duration(milliseconds: 100));
      if (desktop) await ctrlEnterFocused(t, 'R');
      await t.pump(const Duration(milliseconds: 420));
      await shot(t, '$name-dang-dich');
      fake.hold!.complete();
      await t.pump(const Duration(milliseconds: 600));
    });
  }
}

/// Ctrl + Enter trong ô [k] (đưa con trỏ vào ô trước).
Future<void> ctrlEnterFocused(WidgetTester t, String k) async {
  t.widget<TextField>(find.byKey(ValueKey('dich-$k'))).focusNode!.requestFocus();
  await t.pump();
  await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump(const Duration(milliseconds: 400));
}
