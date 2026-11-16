// Ảnh xem trước màn "Kiểu bong bóng" (chạy tay): BUBBLE_OUT=<thư mục> flutter test test/bubble_styles_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/bubble_picker.dart';
import 'package:flygo_chat/ui/bubble_styles.dart';
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

Future<void> _shot(WidgetTester tester, GlobalKey key, String path) => tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: tester.view.devicePixelRatio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    });

/// Bảng soi nét vẽ: mỗi kiểu một ô, cỡ thật, hai tin liền nhau (tin đầu lượt + tin cuối lượt).
Widget _artSheet(bool dark) {
  return Builder(builder: (context) {
    final pal = Pal.of(context);
    Widget cell(BubbleStyle s) => Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Align(alignment: Alignment.centerLeft, child: Text(s.name, style: TextStyle(color: pal.sub, fontSize: 12, fontWeight: FontWeight.w700))),
            StyledBubble(style: s, fill: s.color, bottom: false, child: Text('Báo cáo quý 4 đã xong', style: TextStyle(fontSize: 16, color: bubbleTextOn(s.color)))),
            const SizedBox(height: 3),
            StyledBubble(style: s, fill: s.color, top: false, child: Text('Ok sếp, em gửi ngay', style: TextStyle(fontSize: 16, color: bubbleTextOn(s.color)))),
          ]),
        );
    return Container(
      color: pal.chatBg,
      padding: const EdgeInsets.all(10),
      child: Wrap(children: [for (final s in bubbleStyles) cell(s)]),
    );
  });
}

/// So sánh cỡ: cỡ hiện tại và bản to "ôm bong bóng", mỗi kiểu một đoạn chat (tin người khác + hai tin của mình).
Widget _sizeDemo() {
  return Builder(builder: (context) {
    final pal = Pal.of(context);
    Widget chat(BubbleStyle s) {
      final fg = bubbleTextOn(s.color);
      Widget msg(String t, {bool mine = true, bool top = true, bool bottom = true}) => Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: StyledBubble(
                style: s,
                fill: s.color,
                top: top,
                bottom: bottom,
                mirror: !mine,
                child: Text(t, style: TextStyle(fontSize: 16, color: fg, height: 1.3)),
              ),
            ),
          );
      return Column(children: [
        msg('Anh gửi file hợp đồng rồi nhé', mine: false),
        const SizedBox(height: 6),
        msg('Dạ em nhận rồi ạ', bottom: false),
        msg('Chiều nay em gửi bản ký lại', top: false),
      ]);
    }

    final cur = {for (final s in bubbleStyles) s.id: s};
    final pairs = [
      (cur['meo']!, bubbleHugDemo[0]),
      (cur['cun']!, bubbleHugDemo[1]),
      (cur['munoel']!, bubbleHugDemo[2]),
      (cur['hoamai']!, bubbleHugDemo[3]),
    ];
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(t, style: TextStyle(color: pal.sub, fontSize: 12, fontWeight: FontWeight.w700)),
        );
    return Container(
      color: pal.chatBg,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (a, b) in pairs) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(a.name, style: TextStyle(color: pal.text, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          label('CỠ HIỆN TẠI'),
          chat(a),
          label('CỠ TO (ÔM BONG BÓNG)'),
          chat(b),
          Divider(color: pal.divider, height: 26),
        ],
      ]),
    );
  });
}

void main() {
  final out = Platform.environment['BUBBLE_OUT'];

  for (final dark in [false, true]) {
    testWidgets('size demo ${dark ? 'dark' : 'light'}', (tester) async {
      if (out == null) return;
      await _fonts();
      tester.view.physicalSize = const Size(390, 1900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark ? Brightness.dark : Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: RepaintBoundary(key: key, child: _sizeDemo()))),
      ));
      await tester.pumpAndSettle();
      await _shot(tester, key, '$out/demo-size-${dark ? 'dark' : 'light'}.png');
    });
  }

  for (final dark in [false, true]) {
    for (final (name, size) in [('phone', Size(390, 844)), ('phone-full', Size(390, 2700)), ('desktop', Size(1100, 760))]) {
      testWidgets('picker $name ${dark ? 'dark' : 'light'}', (tester) async {
        if (out == null) return;
        await _fonts();
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(dark ? Brightness.dark : Brightness.light),
            home: BubblePickerPage(current: const BubbleChoice('quockyvn'), defaultFill: (dark ? Pal.dark : Pal.light).outBubble),
          ),
        ));
        await tester.pumpAndSettle();
        await _shot(tester, key, '$out/picker-$name-${dark ? 'dark' : 'light'}.png');
      });
    }
    testWidgets('art sheet ${dark ? 'dark' : 'light'}', (tester) async {
      if (out == null) return;
      await _fonts();
      tester.view.physicalSize = const Size(1240, 2900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark ? Brightness.dark : Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: RepaintBoundary(key: key, child: _artSheet(dark)))),
      ));
      await tester.pumpAndSettle();
      await _shot(tester, key, '$out/art-${dark ? 'dark' : 'light'}.png');
    });
  }
}
