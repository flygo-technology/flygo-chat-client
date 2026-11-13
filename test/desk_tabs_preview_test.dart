// Ảnh xem trước thanh tab máy tính (chạy tay): TABS_OUT=<thư mục> flutter test test/desk_tabs_preview_test.dart
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
  testWidgets('ảnh xem trước thanh tab', (tester) async {
    if (out == null) return;
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(1100, 120);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tabs = [DeskTab('chat'), DeskTab('app', arg: 'contacts'), DeskTab('flow', arg: 'x\tĐề nghị thanh toán\t💸')];
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: Builder(builder: (c) {
            final pal = Pal.of(c);
            return Column(children: [
              DeskTabBar(
                tabs: tabs,
                current: 0,
                label: (t) => switch (t.kind) {
                  'chat' => const DeskTabLabel(Icon(Icons.chat_bubble_rounded, size: 17, color: Color(0xFF25A244)), 'Chat', badge: 1),
                  'app' => const DeskTabLabel(Icon(Icons.contacts_rounded, size: 17, color: Color(0xFF2F80ED)), 'Danh bạ'),
                  _ => const DeskTabLabel(Icon(Icons.account_tree_rounded, size: 17), 'Đề nghị thanh toán'),
                },
                onSelect: (_) {},
                onClose: (_) {},
                onMove: (_, _) {},
                onNew: () {},
                onTogglePin: (_) {},
                onCloseOthers: (_) {},
                trailing: const Chip(avatar: Icon(Icons.dns_outlined, size: 16), label: Text('Flygo Technology')),
              ),
              Expanded(child: Container(color: pal.bg)),
            ]);
          }),
        ),
      ),
    ));
    await tester.pump();
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/tabs.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}
