// In tệp đính kèm trong Thư: nút In cạnh Tải về (PDF, ảnh; không có cho tệp Office), trong trình xem PDF (và Ctrl/Cmd+P),
// trong trình xem ảnh; vòng chờ trong lúc chuẩn bị. Hộp thoại in của hệ điều hành được thay bằng printOverride.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/attachments.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/photos.dart';
import 'package:flygo_chat/ui/mail/store.dart';

Future<Uint8List> _png() async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 40, 30), Paint()..color = Colors.orange);
  final img = await rec.endRecording().toImage(40, 30);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

void main() {
  final printed = <(String, Uint8List)>[];
  setUp(() {
    printed.clear();
    printOverride = (name, pdf) async {
      printed.add((name, pdf));
      return true;
    };
    AttachmentThumb.pdfThumbs = false;
  });
  tearDown(() => printOverride = null);

  Future<MailStore> open(WidgetTester t, bool Function(MailThreadSummary) pick) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    t.state<MailHomeState>(find.byType(MailHome)).openThread(store.items.firstWhere(pick));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    return store;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('thẻ tệp: nút In cạnh Tải về cho PDF, không có cho tệp Office; vòng chờ rồi in đúng tệp', (t) async {
    final store = await open(t, (x) => x.attachments.any(isPdfAttachment) && x.attachments.any((a) => !canPrint(a)));
    final th = store.items.firstWhere((x) => x.attachments.any(isPdfAttachment) && x.attachments.any((a) => !canPrint(a)));
    final pdf = th.attachments.firstWhere(isPdfAttachment), office = th.attachments.firstWhere((a) => !canPrint(a));
    await t.ensureVisible(find.byKey(ValueKey('att-dl-${pdf.id}')));
    expect(find.byKey(ValueKey('att-pr-${pdf.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('att-pr-${office.id}')), findsNothing);
    // Đang chuẩn bị in: vòng chờ thay cho biểu tượng.
    final gate = Completer<bool>();
    printOverride = (name, b) {
      printed.add((name, b));
      return gate.future;
    };
    await t.tap(find.descendant(of: find.byKey(ValueKey('att-pr-${pdf.id}')), matching: find.byType(IconButton)));
    await settle(t);
    expect(printed.single.$1, pdf.name);
    expect(find.descendant(of: find.byKey(ValueKey('att-pr-${pdf.id}')), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    gate.complete(true);
    await settle(t);
    expect(find.descendant(of: find.byKey(ValueKey('att-pr-${pdf.id}')), matching: find.byIcon(Icons.print_outlined)), findsOneWidget);
  });

  testWidgets('trình xem PDF: nút In trên thanh trên và Ctrl+P / Cmd+P in tệp đang xem', (t) async {
    // Trình xem PDF (pdfrx) đọc thư mục tạm khi khởi động.
    final tmp = Directory.systemTemp.createTempSync('mail-print');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    final store = await open(t, (x) => x.attachments.any(isPdfAttachment));
    final pdf = store.items.firstWhere((x) => x.attachments.any(isPdfAttachment)).attachments.firstWhere(isPdfAttachment);
    await t.ensureVisible(find.text(pdf.name).first);
    await t.tap(find.text(pdf.name).first);
    await t.pumpAndSettle();
    expect(find.byType(AttachmentViewer), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('In')));
    await settle(t);
    expect(printed.map((p) => p.$1), [pdf.name]);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t);
    await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await settle(t);
    expect(printed.length, 3);
    // ← →: tệp sau / trước của thư (không phải trang PDF).
    final others = store.items.firstWhere((x) => x.attachments.any(isPdfAttachment)).attachments.where((x) => !isImageAttachment(x)).toList();
    if (others.length > 1) {
      final next = others[others.indexOf(pdf) + 1 < others.length ? others.indexOf(pdf) + 1 : 0];
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, next.name), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pumpAndSettle();
      expect(find.widgetWithText(AppBar, pdf.name), findsOneWidget);
    }
  });

  test('ảnh thành PDF một trang để in', () async {
    final pdf = await imageToPdf(await _png());
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });

  testWidgets('trình xem ảnh của thư: thao tác In gửi ảnh thành PDF', (t) async {
    final png = await t.runAsync(_png);
    final photos = MailPhotos(
      messageId: 'm1',
      photos: [const MailPhoto.body('/mail/api/attachments/m1/a1', name: 'so-do.png')],
      files: AttachmentFiles(DemoMailApi()),
      inlineImage: (_) async => png,
    );
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => (ctx = c, const SizedBox()).$2))));
    final act = photos.actions(ctx, photos.ids, 0).firstWhere((a) => a.key == const ValueKey('photo-print'));
    await t.runAsync(act.run);
    expect(printed.single.$1, 'so-do.png');
    expect(String.fromCharCodes(printed.single.$2.take(5)), '%PDF-');
  });
}
