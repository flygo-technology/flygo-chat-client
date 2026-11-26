// Ảnh xem trước lúc kéo tab ra khỏi thanh tab (chạy tay): TABS_OUT=<thư mục> flutter test test/desk_tab_ghost_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/desk_tabs.dart';
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
  final out = Platform.environment['TABS_OUT'];
  for (final b in Brightness.values) {
    testWidgets('ảnh kéo tab ra (${b.name})', (tester) async {
      if (out == null) return;
      await tester.runAsync(_fonts);
      tester.view.physicalSize = const Size(1000, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tabs = [DeskTab('chat'), DeskTab('agents'), DeskTab('app', arg: 'contacts')];
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: Scaffold(
            body: Column(children: [
              DeskTabBar(
                tabs: tabs,
                current: 0,
                label: (t) => switch (t.kind) {
                  'chat' => const DeskTabLabel(Icon(Icons.chat_bubble_rounded, size: 17, color: Color(0xFF25A244)), 'Chat'),
                  'agents' => const DeskTabLabel(Icon(Icons.smart_toy_rounded, size: 17, color: Color(0xFF7C4DFF)), 'Dự án AI'),
                  _ => const DeskTabLabel(Icon(Icons.contacts_rounded, size: 17, color: Color(0xFF2F80ED)), 'Danh bạ'),
                },
                onSelect: (_) {},
                onClose: (_) {},
                onMove: (_, _) {},
                onNew: () {},
                onTogglePin: (_) {},
                onCloseOthers: (_) {},
                onDetach: (_, _) {},
              ),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ));
      final g = await tester.startGesture(tester.getCenter(find.text('Dự án AI')));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 12; i++) {
        await g.moveBy(const Offset(12, 22));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      final img = await tester.runAsync(() async {
        final ro = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final i = await ro.toImage(pixelRatio: 1);
        return (await i.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      });
      File('$out/keo-tab-${b.name}.png').writeAsBytesSync(img!);
      await g.up();
      await tester.pumpAndSettle();
    });
  }
}
