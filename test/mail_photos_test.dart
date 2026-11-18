// Trình xem ảnh của Thư: bấm ảnh trong thư / ảnh đính kèm mở mọi ảnh của thư xếp dọc (như Bảng tin), phóng to,
// phím, thao tác; quay lại giữ chỗ cuộn. Ảnh chụp (chạy tay): MAIL_OUT=<thư mục> flutter test test/mail_photos_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/bang_tin/photo_list.dart';
import 'package:flygo_chat/ui/clip.dart';
import 'package:flygo_chat/ui/mail/attachments.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/html_view.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/photos.dart';
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

  Finder photos() => find.descendant(of: find.byType(PhotoColumn), matching: find.byType(Image));
  PhotoZoomScopeState zoom(WidgetTester t) => t.state<PhotoZoomScopeState>(find.byType(PhotoZoomScope));
  Finder threadScroll() => find.ancestor(of: find.byKey(const ValueKey('mail-img-$_inlineSrc')), matching: find.byType(Scrollable)).first;

  test('ảnh xem được trong thân thư: ảnh dán + ảnh mạng khi cho hiện, bỏ biểu tượng ≤ 48px', () {
    const html = '<img src="/mail/api/attachments/a/b"><img src="https://x/y.png"><img src="https://x/i.png" width="40">'
        '<img src="/mail/api/attachments/a/c" height="20">';
    expect(mailBodyImages(html), ['/mail/api/attachments/a/b']);
    expect(mailBodyImages(html, loadImages: true), ['/mail/api/attachments/a/b', 'https://x/y.png']);
  });

  testWidgets('điện thoại: bấm ảnh trong thư mở trình xem mọi ảnh của thư; bấm đúp phóng to; quay lại giữ chỗ cuộn', (t) async {
    await openThread(t, const Size(390, 844), ratio: 2);
    final img = find.byKey(const ValueKey('mail-img-$_inlineSrc'));
    await t.ensureVisible(img);
    await t.pumpAndSettle();
    final before = t.state<ScrollableState>(threadScroll()).position.pixels;
    await shot(t, 'phone-1-thu');
    await t.tap(img);
    await settle(t, 8);
    expect(find.byType(MailPhotoPage), findsOneWidget);
    // 1 ảnh dán trong thư + 3 ảnh đính kèm; biểu tượng 16px không vào trình xem.
    expect(find.byType(PhotoColumn), findsOneWidget);
    expect(t.widget<PhotoColumn>(find.byType(PhotoColumn)).ids.length, 4);
    expect(find.text('1/4'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-download')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-copy')), findsOneWidget);
    await shot(t, 'phone-2-xem-anh');

    // Bấm đúp phóng to, bấm đúp lần nữa về danh sách.
    final c = t.getCenter(photos().at(0));
    Future<void> doubleTap() async {
      await t.tapAt(c);
      await t.pump(const Duration(milliseconds: 80));
      await t.tapAt(c);
      await t.pumpAndSettle();
    }

    await doubleTap();
    expect(zoom(t).zoomed, isTrue);
    expect(find.byTooltip('Thu nhỏ'), findsOneWidget);
    await shot(t, 'phone-3-phong-to');
    await doubleTap();
    expect(zoom(t).zoomed, isFalse);

    // Chụm hai ngón phóng to, thả: vẫn phóng to; nút quay lại thu nhỏ trước, lần nữa mới đóng trình xem.
    final a = await t.startGesture(c - const Offset(20, 0), pointer: 1);
    await t.pump(const Duration(milliseconds: 20));
    final b = await t.startGesture(c + const Offset(20, 0), pointer: 2);
    for (var i = 1; i <= 8; i++) {
      await a.moveTo(c - Offset(20 + 10.0 * i, 0));
      await b.moveTo(c + Offset(20 + 10.0 * i, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isTrue);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isFalse);
    expect(find.byType(MailPhotoPage), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(MailPhotoPage), findsNothing);
    expect(t.state<ScrollableState>(threadScroll()).position.pixels, before);
    expect(find.byKey(const ValueKey('mail-img-$_inlineSrc')), findsOneWidget);
  });

  testWidgets('máy tính: bấm ảnh đính kèm mở tại ảnh đó; Ctrl + lăn chuột phóng to; phím mũi tên, Esc; Sao chép / Drive', (t) async {
    final (api, _) = await openThread(t, const Size(1440, 900));
    final saved = <List<String>>[];
    MailHooks.saveToDrive = (context, files) async => saved.add([for (final f in files) f.$2]);
    addTearDown(() => MailHooks.saveToDrive = null);
    Uint8List? copied;
    copyImageOverride = (b) async {
      copied = b;
      return true;
    };
    addTearDown(() => copyImageOverride = null);
    // Thẻ ảnh đính kèm thứ hai (MailHooks đặt sau khi mở thư: dựng lại cho có nút Drive).
    await t.scrollUntilVisible(find.text('nghiem-thu-2.jpg'), 200, scrollable: threadScroll());
    await t.drag(threadScroll(), const Offset(0, -200));
    await t.pumpAndSettle();
    await t.tap(find.text('nghiem-thu-2.jpg'));
    await settle(t, 8);
    expect(find.byType(MailPhotoPage), findsOneWidget);
    expect(find.byType(AttachmentViewer), findsNothing);
    expect(find.text('3/4'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-drive')), findsOneWidget);
    await shot(t, 'desktop-1-xem-anh');

    // Sao chép ảnh, Lưu vào Drive của ảnh đang xem.
    await t.tap(find.byKey(const ValueKey('photo-copy')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(copied, api.png['nghiem-thu-2.jpg']);
    await t.tap(find.byKey(const ValueKey('photo-drive')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(saved.last, ['nghiem-thu-2.jpg']);

    // Mũi tên xuống / lên: sang ảnh sau / trước.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    expect(find.text('4/4'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pumpAndSettle();
    expect(find.text('2/4'), findsOneWidget);

    // Ctrl + lăn chuột trên ảnh: phóng to (không cuộn danh sách); lăn chuột ngược về cỡ gốc thì về danh sách.
    final list = t.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('mail-photos')), matching: find.byType(Scrollable)));
    final pos = list.position.pixels;
    final i = zoom(t).currentIndex!;
    final at = t.getCenter(photos().at(i));
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(mouse.hover(at));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await t.pumpAndSettle();
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(zoom(t).zoomed, isTrue);
    expect(list.position.pixels, pos);
    await shot(t, 'desktop-2-phong-to');
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 600)));
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isFalse);

    // Lăn chuột không giữ Ctrl: cuộn danh sách, không phóng to.
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isFalse);
    // Esc: đang phóng to thì thu nhỏ; không thì đóng trình xem, về thư.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendEventToBinding(mouse.hover(t.getCenter(photos().at(zoom(t).currentIndex!))));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isFalse);
    expect(find.byType(MailPhotoPage), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(MailPhotoPage), findsNothing);
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

  testWidgets('máy tính: lăn chuột (không cần Ctrl) phóng to ảnh, bấm một lần cũng phóng to, ← → chuyển ảnh', (t) async {
    await openThread(t, const Size(1440, 900));
    await t.scrollUntilVisible(find.text('nghiem-thu-1.jpg'), 200, scrollable: threadScroll());
    await t.drag(threadScroll(), const Offset(0, -200));
    await t.pumpAndSettle();
    await t.tap(find.text('nghiem-thu-1.jpg'));
    await settle(t, 8);
    expect(find.text('2/4'), findsOneWidget);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(mouse.hover(t.getCenter(photos().at(zoom(t).currentIndex!))));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -200)));
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isTrue);
    // Lăn ngược về cỡ gốc: về danh sách.
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 600)));
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isFalse);
    // Bấm một lần vào ảnh: phóng to; bấm lần nữa: thu nhỏ.
    final c = t.getCenter(photos().at(zoom(t).currentIndex!));
    // (một chạm chỉ được nhận sau thời gian chờ chạm đúp)
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isTrue);
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(zoom(t).zoomed, isFalse);
    // ← →: ảnh trước / sau.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(find.text('3/4'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(find.text('2/4'), findsOneWidget);
  });

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
