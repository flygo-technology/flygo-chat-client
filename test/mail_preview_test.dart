// Ảnh xem trước Thư (chạy tay): MAIL_OUT=<thư mục> flutter test test/mail_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/rich.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/ui/todo/model.dart';

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
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<MailStore> start(WidgetTester t, Size size, Brightness b, {double ratio = 1}) async {
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: MailHome(store: store, title: 'Mail', ownsStore: false),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    return store;
  }

  for (final b in [Brightness.light, Brightness.dark]) {
    final th = b == Brightness.light ? 'light' : 'dark';
    testWidgets('máy tính $th', (t) async {
      if (out == null) return;
      await t.runAsync(_fonts);
      // Ảnh xem trước cần bóng đổ thật (flutter_test mặc định vẽ bóng thành viền đen); trả lại cuối test.
      debugDisableShadows = false;
      final store = await start(t, const Size(1440, 900), b);
      await save(t, 'desktop-$th-1-inbox');
      store.toggleSelect(store.items[2].id);
      store.toggleSelect(store.items[3].id);
      await save(t, 'desktop-$th-2-multiselect');
      store.clearSelection();
      await t.tap(find.textContaining('Re: Lịch họp review', findRichText: true).first);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await save(t, 'desktop-$th-3-thread');
      await t.tap(find.text('Trả lời').last);
      await t.pump(const Duration(milliseconds: 100));
      await t.enterText(find.byType(TextField).last, 'Cảm ơn chị, em xác nhận lịch 9h thứ Năm.');
      await t.tap(find.text('Soạn thư').first);
      await t.pump(const Duration(milliseconds: 100));
      // Nội dung có định dạng để thấy thanh công cụ soạn thảo.
      final body = t.widget<TextField>(find.byKey(const ValueKey('mail-body')).last).controller! as MailRichController;
      body.setBody([
        TRun('Cảm ơn chị, em '),
        TRun('xác nhận', const TFmt(b: true)),
        TRun(' lịch '),
        TRun('9h thứ Năm', const TFmt(fg: 'red')),
        TRun('. Tài liệu ở '),
        TRun('đây', const TFmt(a: 'https://example.com')),
        TRun(':\n1. Báo cáo quý\n2. Kế hoạch tháng 12\n• Ghi chú: '),
        TRun('mang laptop', const TFmt(i: true)),
        TRun('\n> Họp ở phòng lớn tầng 3'),
      ]);
      await t.pump(const Duration(milliseconds: 100));
      await save(t, 'desktop-$th-4-reply-compose');
      await t.tap(find.byTooltip('Quay lại (u)'));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byTooltip('Tuỳ chọn tìm kiếm'));
      await t.pump(const Duration(milliseconds: 100));
      await save(t, 'desktop-$th-5-search-filters');
      await t.tap(find.byTooltip('Tuỳ chọn tìm kiếm'));
      await store.open(const MailView.search('has:attachment'));
      await t.pump(const Duration(milliseconds: 100));
      await save(t, 'desktop-$th-6-search-results');
      debugDisableShadows = true;
    });

    testWidgets('điện thoại $th', (t) async {
      if (out == null) return;
      await t.runAsync(_fonts);
      // Ảnh xem trước cần bóng đổ thật (flutter_test mặc định vẽ bóng thành viền đen); trả lại cuối test.
      debugDisableShadows = false;
      final store = await start(t, const Size(390, 844), b, ratio: 2);
      await save(t, 'phone-$th-1-inbox');
      store.toggleSelect(store.items[2].id);
      store.toggleSelect(store.items[3].id);
      await save(t, 'phone-$th-3-multiselect');
      store.clearSelection();
      await t.pump();
      await t.tap(find.byTooltip('Menu'));
      await t.pumpAndSettle(const Duration(milliseconds: 50));
      await save(t, 'phone-$th-2-drawer');
      await t.tapAt(const Offset(370, 400));
      await t.pumpAndSettle(const Duration(milliseconds: 50));
      await t.tap(find.textContaining('Re: Lịch họp review', findRichText: true).first);
      await t.pumpAndSettle(const Duration(milliseconds: 50));
      await save(t, 'phone-$th-4-thread');
      await t.tap(find.text('Trả lời').last);
      await t.pumpAndSettle(const Duration(milliseconds: 50));
      await save(t, 'phone-$th-5-compose');
      debugDisableShadows = true;
    });
  }
}
