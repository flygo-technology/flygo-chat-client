// Ảnh xem trước thanh tab điện thoại có Bảng tin (chạy tay): TAB_OUT=<thư mục> flutter test test/tabbar_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/home_page.dart';
import 'package:flygo_chat/ui/theme.dart';

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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['TAB_OUT'];

  testWidgets('thanh tab điện thoại: Chat, Trợ lý, Bảng tin, Apps', (t) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = const Size(1179, 420);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    for (final (name, index) in [('tabbar-chat', 0), ('tabbar-bangtin', 5)]) {
      await t.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            backgroundColor: const Color(0xFFEDEFF2),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), child: debugMobileTabBar(index: index)),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(seconds: 6));
      expect(find.text('Bảng tin'), findsOneWidget);
      if (out != null) {
        await t.runAsync(() async {
          final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage(pixelRatio: 3);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
    }
  });
}
