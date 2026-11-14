import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/clip.dart';

/// BMP 24 bit [w]x[h] (như Windows trả khi dán ảnh: BITMAPFILEHEADER + DIB), điểm ảnh màu [bgr].
Uint8List _bmp(int w, int h, List<int> bgr) {
  final row = (w * 3 + 3) & ~3;
  final size = 54 + row * h;
  final b = ByteData(size);
  b.setUint8(0, 0x42);
  b.setUint8(1, 0x4D);
  b.setUint32(2, size, Endian.little);
  b.setUint32(10, 54, Endian.little);
  b.setUint32(14, 40, Endian.little);
  b.setInt32(18, w, Endian.little);
  b.setInt32(22, h, Endian.little);
  b.setUint16(26, 1, Endian.little);
  b.setUint16(28, 24, Endian.little);
  b.setUint32(34, row * h, Endian.little);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        b.setUint8(54 + y * row + x * 3 + c, bgr[c]);
      }
    }
  }
  return b.buffer.asUint8List();
}

const _pngSig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  test('imageExtOf: nhận đúng loại ảnh theo nội dung', () {
    expect(imageExtOf(_pngSig), 'png');
    expect(imageExtOf(const [0xFF, 0xD8, 0xFF, 0xE0]), 'jpg');
    expect(imageExtOf('GIF89a'.codeUnits), 'gif');
    expect(imageExtOf([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]), 'webp');
    expect(imageExtOf(_bmp(1, 1, const [0, 0, 0])), 'bmp');
    expect(imageExtOf(const [0x49, 0x49, 0x2A, 0x00]), 'tiff');
    expect(imageExtOf(const [1, 2, 3]), isNull);
  });

  testWidgets('dán ảnh BMP (Windows): đổi sang PNG thật, giữ kích thước và màu', (t) async {
    final bmp = _bmp(3, 2, const [0x20, 0x80, 0xF0]); // B, G, R
    final (out, ext) = (await t.runAsync(() => normalizeClipImage(bmp)))!;
    expect(ext, 'png');
    expect(out.sublist(0, 8), _pngSig);
    final img = (await t.runAsync(() async {
      final codec = await ui.instantiateImageCodec(out);
      final f = await codec.getNextFrame();
      final px = await f.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (f.image.width, f.image.height, px!.buffer.asUint8List().sublist(0, 4));
    }))!;
    expect((img.$1, img.$2), (3, 2));
    expect(img.$3, [0xF0, 0x80, 0x20, 0xFF]);
  });

  testWidgets('PNG / JPEG giữ nguyên, không mã hoá lại', (t) async {
    final png = Uint8List.fromList([..._pngSig, 1, 2, 3]);
    final r = (await t.runAsync(() => normalizeClipImage(png)))!;
    expect(identical(r.$1, png), isTrue);
    expect(r.$2, 'png');
    final jpg = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xE0, 9]);
    expect((await t.runAsync(() => normalizeClipImage(jpg)))!.$2, 'jpg');
  });

  testWidgets('không giải mã được: giữ nguyên với đuôi theo nội dung', (t) async {
    final broken = Uint8List.fromList(const [0x42, 0x4D, 1, 2, 3]);
    final r = (await t.runAsync(() => normalizeClipImage(broken)))!;
    expect(r.$2, 'bmp');
  });
}
