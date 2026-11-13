// Ảnh xem trước trang mở dạng hộp nổi trên máy tính (chạy tay): ROUTE_OUT=<thư mục> flutter test test/app_route_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/app_route.dart';
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

  for (final fam in ['Roboto', 'Noto Sans']) {
    await load(fam, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['ROUTE_OUT'];
  testWidgets('trang mở dạng hộp nổi', (tester) async {
    if (out == null) return;
    debugDisableShadows = false;
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        navigatorKey: nav,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Row(children: [
            SizedBox(width: 360, child: ListView(children: [for (var i = 0; i < 12; i++) ListTile(leading: const CircleAvatar(), title: Text('Cuộc trò chuyện ${i + 1}'))])),
            const VerticalDivider(width: 1),
            const Expanded(child: Center(child: Text('Chat đang mở'))),
          ]),
        ),
      ),
    ));
    nav.currentState!.push(AppPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Danh bạ')),
        body: ListView(children: [for (var i = 0; i < 10; i++) ListTile(leading: const Icon(Icons.person), title: Text('Người ${i + 1}'))]),
      ),
    ));
    await tester.pumpAndSettle();
    debugDisableShadows = true;
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: .7);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/modal.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
