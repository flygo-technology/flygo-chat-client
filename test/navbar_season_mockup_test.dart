// Mockup thanh tab điện thoại mùa Giáng sinh (chạy tay): XMAS_OUT=<thư mục> flutter test test/navbar_season_mockup_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/home_page.dart' show debugMobileTabBar;
import 'package:flygo_chat/ui/season/season_state.dart';
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
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['XMAS_OUT'];
  for (final dark in [false, true]) {
    testWidgets('thanh tab mùa Giáng sinh ${dark ? 'dark' : 'light'}', (t) async {
      if (out == null) return;
      await t.runAsync(_fonts);
      t.view.physicalSize = const Size(390, 420) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      Widget bar(bool on, int idx) => _Frozen(on: on, child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 10), child: debugMobileTabBar(index: idx)));
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(dark ? Brightness.dark : Brightness.light),
          home: Builder(builder: (context) {
            final pal = Pal.of(context);
            Widget label(String s) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Text(s, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: pal.sub)),
                );
            return Scaffold(
              backgroundColor: pal.bg,
              body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 16),
                label('Mùa Giáng sinh: nền riêng cho thanh dưới'),
                bar(true, 0),
                bar(true, 3),
                label('Ngoài mùa / đã tắt (như hiện nay)'),
                bar(false, 0),
              ]),
            );
          }),
        ),
      ));
      await t.pump(const Duration(seconds: 6));
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/14-navbar-bg-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
      debugNavBg = null;
    });
  }
}

/// Bật / tắt nền mùa lễ ngay trước khi dựng thanh tab (mỗi dòng một kiểu).
class _Frozen extends StatelessWidget {
  final bool on;
  final Widget child;
  const _Frozen({required this.on, required this.child});
  @override
  Widget build(BuildContext context) {
    debugNavBg = on;
    return child;
  }
}
