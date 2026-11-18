// PDF đính kèm trong Thư / Drive: mở ra thấy trọn trang bìa, lăn chuột cuộn, Ctrl + lăn chuột phóng to; phím ← → để
// trình xem chuyển tệp (không bị PDF giữ lại).
// Cần pdfium thật (build/native_assets/linux/libpdfium.so sau một lần flutter build linux); không có thì bỏ qua.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/attachments.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  const lib = 'build/native_assets/linux/libpdfium.so';
  final skip = !File(lib).existsSync();

  testWidgets('PDF: trọn trang bìa; lăn chuột cuộn; Ctrl + lăn chuột phóng to; ← → chuyển tệp, không đổi trang', skip: skip, (t) async {
    Pdfrx.pdfiumModulePath = File(lib).absolute.path;
    final tmp = Directory.systemTemp.createTempSync('pdfrx-test');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = PdfViewerController();
    final moves = <int>[];
    await t.pumpWidget(MaterialApp(
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => moves.add(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => moves.add(1),
        },
        child: Focus(autofocus: true, child: Scaffold(body: PdfViewer.file(File('test/fixtures/two-pages.pdf').absolute.path, controller: c, params: mailPdfParams))),
      ),
    ));
    for (var i = 0; i < 40 && !c.isReady; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(c.isReady, isTrue);
    await t.pump(const Duration(milliseconds: 100));
    // Trọn trang đầu: cao trang (kể cả lề) vừa khung, không phóng theo chiều rộng.
    expect(c.currentZoom, closeTo(c.alternativeFitScale!, .01));
    expect(c.currentZoom, lessThan(c.coverScale));
    final at = t.getCenter(find.byType(PdfViewer));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(mouse.hover(at));
    // Lăn chuột: cuộn xuống, không đổi cỡ.
    final y0 = c.value.getTranslation().y, z0 = c.currentZoom;
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    await t.pumpAndSettle();
    expect(c.value.getTranslation().y, lessThan(y0 - 60));
    expect(c.currentZoom, closeTo(z0, .001));
    // Ctrl + lăn chuột lên: phóng to.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -240)));
    await t.pumpAndSettle();
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.currentZoom, greaterThan(z0 * 1.2));
    // ← → (kể cả khi PDF đang giữ bàn phím): tới trình xem để chuyển tệp; trang không đổi.
    await t.tapAt(at);
    await t.pumpAndSettle();
    final page = c.pageNumber;
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(moves, [1, -1]);
    expect(c.pageNumber, page);
  });
}
