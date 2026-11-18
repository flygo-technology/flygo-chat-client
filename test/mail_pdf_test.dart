// PDF đính kèm trong Thư: mở ra thấy trọn trang bìa, lăn chuột phóng to / thu nhỏ, phím ← → sang trang.
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

  testWidgets('PDF: trọn trang bìa; lăn chuột phóng to / thu nhỏ; ← → sang trang', skip: skip, (t) async {
    Pdfrx.pdfiumModulePath = File(lib).absolute.path;
    final tmp = Directory.systemTemp.createTempSync('pdfrx-test');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = PdfViewerController();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PdfViewer.file(File('test/fixtures/two-pages.pdf').absolute.path, controller: c, params: mailPdfParamsWith(controller: c)))));
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
    // Lăn chuột lên: phóng to quanh con trỏ; lăn xuống: thu nhỏ lại.
    final z0 = c.currentZoom;
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -240)));
    await t.pumpAndSettle();
    expect(c.currentZoom, greaterThan(z0 * 1.2));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, 240)));
    await t.pumpAndSettle();
    expect(c.currentZoom, closeTo(z0, z0 * .05));
    // ← →: sang trang sau / trước.
    await t.tapAt(at);
    await t.pumpAndSettle();
    expect(c.pageNumber, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(c.pageNumber, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(c.pageNumber, 1);
  });
}
