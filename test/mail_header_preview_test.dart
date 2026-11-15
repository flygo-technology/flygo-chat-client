// Ảnh trước/sau (chạy tay): MAIL_OUT=<thư mục> flutter test test/mail_header_preview_test.dart
// Thư mở như một trang (có thể quay lại), máy tính + điện thoại; bộ chọn hộp thư mở từ đầu danh sách (nếu có).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/store.dart';
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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  // theme dùng 'Noto Sans' trên Linux (máy chạy test): nạp Roboto dưới tên đó.
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['MAIL_OUT'];
  final key = GlobalKey();

  Future<void> save(WidgetTester t, String name) async {
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: t.view.devicePixelRatio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final (name, size, ratio) in [('desktop', const Size(1440, 900), 1.0), ('phone', const Size(390, 844), 2.0)]) {
    testWidgets(name, (t) async {
      if (out == null) return;
      await t.runAsync(_fonts);
      debugDisableShadows = false;
      t.view.physicalSize = size * ratio;
      t.view.devicePixelRatio = ratio;
      addTearDown(t.view.reset);
      final store = MailStore(DemoMailApi());
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => MailHome(store: store, title: 'Mail', ownsStore: false))),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      await save(t, '$name-1-inbox');
      final other = find.byKey(const ValueKey('mail-other-boxes'));
      if (other.evaluate().isNotEmpty) {
        await t.tap(other);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 60));
        }
        await save(t, '$name-2-switcher');
        await t.tap(find.text('Hỗ trợ khách hàng'));
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 60));
        }
        await save(t, '$name-3-shared-box');
      }
      debugDisableShadows = true;
    });
  }
}
