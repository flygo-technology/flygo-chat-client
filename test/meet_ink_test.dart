// Nét vẽ chú thích trên tài liệu: vẽ đủ loại nét; bản PDF mới có chú thích (cần pdfium: build/native_assets/linux/libpdfium.so
// và TATCA_PDF=<thư mục có tiendo.pdf>). INK_OUT=<thư mục>: lưu ảnh + PDF để xem.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/meet/meet_ink.dart';
import 'package:pdfrx/pdfrx.dart';

final _strokes = [
  {'t': 'pen', 'c': '#FF3B30', 'w': .006, 'p': [[.1, .2], [.2, .25], [.3, .2], [.4, .3]]},
  {'t': 'rect', 'c': '#34C759', 'w': .004, 'p': [[.5, .1], [.8, .35]]},
  {'t': 'circle', 'c': '#0A84FF', 'w': .004, 'p': [[.1, .5], [.35, .8]]},
  {'t': 'arrow', 'c': '#FFCC00', 'w': .005, 'p': [[.45, .75], [.7, .55]]},
  {'t': 'text', 'c': '#111111', 'w': .004, 's': 'Chậm 4 ngày', 'p': [[.55, .85]]},
];

void main() {
  test('vẽ đủ loại nét (bút, chữ nhật, tròn, mũi tên, chữ)', () async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 800, 450), Paint()..color = Colors.white);
    paintInk(c, const Size(800, 450), _strokes);
    final img = await rec.endRecording().toImage(800, 450);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    expect(bytes.length, greaterThan(1000));
    final out = Platform.environment['INK_OUT'];
    if (out != null) File('$out/ink-strokes.png').writeAsBytesSync(bytes);
  });

  testWidgets('bản PDF mới có chú thích (bản gốc giữ nguyên)', (t) async {
    final dir = Platform.environment['TATCA_PDF'];
    final lib = File('build/native_assets/linux/libpdfium.so');
    if (dir == null || !lib.existsSync() || !File('$dir/tiendo.pdf').existsSync()) return;
    Pdfrx.pdfiumModulePath = lib.absolute.path;
    await t.runAsync(() async {
      final src = File('$dir/tiendo.pdf').readAsBytesSync();
      final doc = await PdfDocument.openData(src, sourceName: 'ink');
      final pdf = await annotatedPdf(doc, {'1': _strokes}, width: 800);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      final again = await PdfDocument.openData(pdf, sourceName: 'ink-out');
      expect(again.pages.length, doc.pages.length);
      final out = Platform.environment['INK_OUT'];
      if (out != null) {
        File('$out/tiendo-chu-thich.pdf').writeAsBytesSync(pdf);
        final img = await again.pages[0].renderForDisplay(fullWidth: 800, fullHeight: 450);
        final png = (await img!.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        File('$out/tiendo-chu-thich-trang1.png').writeAsBytesSync(png);
      }
      await again.dispose();
      await doc.dispose();
    });
  });
}
