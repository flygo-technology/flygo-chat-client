// Trình xem tệp của Thư (từng tệp một, như PDF / Drive): bấm ảnh trong thư / tệp đính kèm mở một dãy chung (ảnh trong thư,
// ảnh và PDF đính kèm), ảnh vừa màn hình, Ctrl + lăn chuột phóng to, bấm đúp, ← → chuyển tệp; quay lại giữ chỗ cuộn. Ảnh chụp (chạy tay): MAIL_OUT=<thư mục> flutter test test/mail_photos_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/attachments.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/html_view.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/mail/thread_view.dart' show MailHooks;
import 'package:flygo_chat/ui/theme.dart';

Future<Uint8List> _png(Color a, Color b, {int w = 600, int h = 400}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(w.toDouble(), h.toDouble()), [a, b]));
  c.drawCircle(Offset(w * .3, h * .4), h * .18, Paint()..color = Colors.white.withValues(alpha: .7));
  final img = await rec.endRecording().toImage(w, h);
  final d = await img.toByteData(format: ui.ImageByteFormat.png);
  return d!.buffer.asUint8List();
}

const _inlineSrc = '/mail/api/attachments/m-photo/inline1?mailbox=x%40y.vn';

/// Thư "Ảnh nghiệm thu": thêm một ảnh dán trong thư và một biểu tượng chữ ký nhỏ; ảnh đính kèm là ảnh PNG thật.
class _Api extends DemoMailApi {
  final png = <String, Uint8List>{};
  final asked = <String>[];

  @override
  Future<MailThread> thread(String id) async {
    final t = await super.thread(id);
    if (!t.messages.any((m) => m.attachments.any((a) => a.name == 'nghiem-thu-1.jpg'))) return t;
    final m = t.messages.last;
    final html = '${m.html}<p>Sơ đồ điểm phát:</p><img src="$_inlineSrc" alt="so-do.png">'
        '<p>Thảo</p><img src="/mail/api/attachments/m-photo/icon?mailbox=x" width="16" height="16">';
    return MailThread(t.summary, [
      ...t.messages.take(t.messages.length - 1),
      MailMessage(id: m.id, from: m.from, to: m.to, cc: m.cc, date: m.date, html: html, attachments: m.attachments),
    ]);
  }

  @override
  Future<Uint8List?> inlineImage(String path) async {
    asked.add(path);
    return png['inline'];
  }

  @override
  Future<File> download(MailAttachment a) async {
    final b = png[a.name];
    if (b == null) return super.download(a);
    final f = File('${Directory.systemTemp.path}/flygo-mail-photo-${a.name}');
    await f.writeAsBytes(b);
    return f;
  }
}

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
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['MAIL_OUT'];
  final shotKey = GlobalKey();

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await settle(t, 3);
    await t.runAsync(() async {
      final img = await (shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: t.view.devicePixelRatio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await Directory(out).create(recursive: true);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  /// Mở hộp thư rồi mở thư "Ảnh nghiệm thu".
  Future<(_Api, MailThreadSummary)> openThread(WidgetTester t, Size size, {double ratio = 1}) async {
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    addTearDown(t.view.reset);
    imageCache
      ..clear()
      ..clearLiveImages();
    AttachmentThumb.pdfThumbs = false;
    // Ảnh trong thân thư được ghi ra thư mục tạm khi mở trong trình xem.
    final tmp = Directory.systemTemp.createTempSync('mail-photos');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    final api = _Api();
    await t.runAsync(() async {
      if (out != null) await _fonts();
      api.png['inline'] = await _png(const Color(0xFF00C9FF), const Color(0xFF92FE9D), w: 800, h: 450);
      api.png['nghiem-thu-1.jpg'] = await _png(const Color(0xFFFF9A62), const Color(0xFF6A5AE0));
      api.png['nghiem-thu-2.jpg'] = await _png(const Color(0xFF34C77B), const Color(0xFF1D7FE0), w: 400, h: 600);
      api.png['nghiem-thu-3.jpg'] = await _png(const Color(0xFFF7B731), const Color(0xFFE8455A));
    });
    final store = MailStore(api);
    await t.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: MailHome(store: store, title: 'Mail', ownsStore: false)),
    ));
    await settle(t, 8);
    final th = store.items.firstWhere((x) => x.subject.startsWith('Ảnh nghiệm thu'));
    t.state<MailHomeState>(find.byType(MailHome)).openThread(th);
    await settle(t, 10);
    return (api, th);
  }

  ZoomImageState img(WidgetTester t) => t.state<ZoomImageState>(find.byType(ZoomImage).hitTestable());
  String pos(WidgetTester t) => (t.widget<Text>(find.byKey(const ValueKey('att-pos'))).data ?? '');
  Finder threadScroll() => find.ancestor(of: find.byKey(const ValueKey('mail-img-$_inlineSrc')), matching: find.byType(Scrollable)).first;

  test('ảnh xem được trong thân thư: ảnh dán + ảnh mạng khi cho hiện, bỏ biểu tượng ≤ 48px', () {
    const html = '<img src="/mail/api/attachments/a/b"><img src="https://x/y.png"><img src="https://x/i.png" width="40">'
        '<img src="/mail/api/attachments/a/c" height="20">';
    expect(mailBodyImages(html), ['/mail/api/attachments/a/b']);
    expect(mailBodyImages(html, loadImages: true), ['/mail/api/attachments/a/b', 'https://x/y.png']);
  });

  testWidgets('điện thoại: bấm ảnh trong thư mở trình xem từng tệp tại ảnh đó (1/4); bấm đúp phóng to; quay lại giữ chỗ cuộn', (t) async {
    await openThread(t, const Size(390, 844), ratio: 2);
    final inline = find.byKey(const ValueKey('mail-img-$_inlineSrc'));
    await t.ensureVisible(inline);
    await t.pumpAndSettle();
    final before = t.state<ScrollableState>(threadScroll()).position.pixels;
    await shot(t, 'phone-1-thu');
    await t.tap(inline);
    for (var i = 0; i < 20 && find.byType(ZoomImage).evaluate().isEmpty; i++) {
      await settle(t, 2);
    }
    expect(find.byType(AttachmentViewer), findsOneWidget);
    // Một dãy: ảnh trong thư + 3 ảnh đính kèm (biểu tượng 16px không vào); một tệp mỗi lần, không xếp dọc.
    expect(pos(t), '1/4');
    expect(find.byType(ZoomImage).hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('att-download')), findsOneWidget);
    expect(find.byTooltip('In'), findsOneWidget);
    await shot(t, 'phone-2-xem-anh');
    final c = t.getCenter(find.byType(ZoomImage).hitTestable());
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 80));
    await t.tapAt(c);
    await t.pumpAndSettle();
    expect(img(t).scale, greaterThan(2));
    await shot(t, 'phone-3-phong-to');
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 80));
    await t.tapAt(c);
    await t.pumpAndSettle();
    expect(img(t).scale, closeTo(1, .01));
    // Vuốt sang tệp sau.
    await t.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await t.pumpAndSettle();
    expect(pos(t), '2/4');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(AttachmentViewer), findsNothing);
    expect(t.state<ScrollableState>(threadScroll()).position.pixels, before);
  });

  testWidgets('máy tính: bấm ảnh đính kèm mở tại ảnh đó; lăn chuột thường không phóng to; Ctrl + lăn chuột phóng to, rồi lăn để di chuyển; ← →, Esc; In / Drive', (t) async {
    final (api, _) = await openThread(t, const Size(1440, 900));
    final saved = <List<String>>[];
    MailHooks.saveToDrive = (context, files) async => saved.add([for (final f in files) f.$2]);
    addTearDown(() => MailHooks.saveToDrive = null);
    final printed = <String>[];
    printOverride = (name, pdf) async {
      printed.add(name);
      return true;
    };
    addTearDown(() => printOverride = null);
    await t.scrollUntilVisible(find.text('nghiem-thu-2.jpg'), 200, scrollable: threadScroll());
    await t.drag(threadScroll(), const Offset(0, -200));
    await t.pumpAndSettle();
    await t.tap(find.text('nghiem-thu-2.jpg'));
    await settle(t, 8);
    expect(find.byType(AttachmentViewer), findsOneWidget);
    expect(pos(t), '3/4');
    await shot(t, 'desktop-1-xem-anh');
    final at = t.getCenter(find.byType(ZoomImage).hitTestable());
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(mouse.hover(at));
    // Vừa màn hình: lăn chuột thường không làm gì.
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await t.pumpAndSettle();
    expect(img(t).scale, closeTo(1, .01));
    // Ctrl + lăn chuột: phóng to quanh con trỏ.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await t.pumpAndSettle();
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(img(t).scale, greaterThan(2));
    await shot(t, 'desktop-2-phong-to');
    // Đã phóng to: lăn chuột là di chuyển, không đổi cỡ.
    final s0 = img(t).scale;
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await t.pumpAndSettle();
    expect(img(t).scale, closeTo(s0, .001));
    // In, Lưu vào Drive của tệp đang xem.
    await t.tap(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('In')));
    for (var i = 0; i < 30 && printed.isEmpty; i++) {
      await settle(t, 1);
    }
    expect(printed, ['nghiem-thu-2.jpg']);
    await t.tap(find.byKey(const ValueKey('att-drive')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(saved.last, ['nghiem-thu-2.jpg']);
    // ← →: tệp trước / sau (ảnh trong thư là tệp đầu).
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(pos(t), '4/4');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    // (ảnh trong thư đang tải: vòng chờ quay, không chờ "settle")
    await settle(t, 6);
    expect(pos(t), '1/4');
    expect(find.widgetWithText(AppBar, 'so-do.png'), findsNothing);
    // Ảnh trong thư cũng in được (ảnh thành PDF).
    for (var i = 0; i < 30 && find.byType(ZoomImage).hitTestable().evaluate().isEmpty; i++) {
      await settle(t, 1);
    }
    await t.tap(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('In')));
    for (var i = 0; i < 30 && printed.length < 2; i++) {
      await settle(t, 1);
    }
    expect(printed.length, 2);
    expect(api.asked, contains(_inlineSrc));
    // Esc: đóng, về thư.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(AttachmentViewer), findsNothing);
    expect(find.text('nghiem-thu-2.jpg'), findsOneWidget);
  });

  for (final w in [360.0, 390.0]) {
    testWidgets('điện thoại rộng ${w.toInt()}: thanh nút của thư không tràn; Báo cáo thư rác trong Thao tác khác', (t) async {
      await openThread(t, Size(w, 800), ratio: 3);
      expect(t.takeException(), isNull);
      expect(find.byTooltip('Báo cáo thư rác'), findsNothing);
      await t.tap(find.byTooltip('Thao tác khác'));
      await t.pumpAndSettle();
      expect(find.text('Báo cáo thư rác'), findsOneWidget);
    });
  }

  testWidgets('ảnh từ mạng đang ẩn: không bấm được; PDF vẫn mở trình xem tệp', (t) async {
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    String? tapped;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: MailHtml('<img src="https://x/y.png" alt="Logo">', onImageTap: (s) => tapped = s)),
    ));
    expect(find.byKey(const ValueKey('mail-img-https://x/y.png')), findsNothing);
    await t.tap(find.text('Logo'));
    expect(tapped, isNull);
  });
}
