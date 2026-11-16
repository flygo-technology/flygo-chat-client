import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/bubble_styles.dart';

/// Vẽ riêng phần trang trí của [s] quanh bong bóng [size] (đặt giữa ảnh, chừa lề [m]) rồi đếm điểm ảnh có màu nằm trong
/// vùng chữ (bong bóng trừ phần đệm 12 / 7 / 10 / 7 như ở chat).
Future<int> _pixelsOverText(BubbleStyle s, Size size, {double scale = 1, bool mirror = false}) async {
  const m = 60.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.translate(m, m);
  BubbleDecoPainter(style: s, fill: s.color, scale: scale, mirror: mirror).paint(canvas, size);
  final w = (size.width + 2 * m).ceil(), h = (size.height + 2 * m).ceil();
  final img = await rec.endRecording().toImage(w, h);
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final text = Rect.fromLTRB(m + 12 * scale, m + 7 * scale, m + size.width - 10 * scale, m + size.height - 7 * scale);
  var n = 0;
  for (var y = text.top.ceil(); y < text.bottom.floor(); y++) {
    for (var x = text.left.ceil(); x < text.right.floor(); x++) {
      if (data.getUint8((y * w + x) * 4 + 3) > 24) n++;
    }
  }
  return n;
}

void main() {
  test('hình trang trí không đè vùng chữ của bong bóng (mọi kiểu, nhiều cỡ)', () async {
    final bad = <String>[];
    for (final s in [...bubbleStyles, ...bubbleHugDemo]) {
      for (final size in const [Size(64, 36), Size(150, 36), Size(260, 58), Size(320, 120)]) {
        for (final mirror in [false, true]) {
          final n = await _pixelsOverText(s, size, mirror: mirror);
          if (n > 0) bad.add('${s.id} ${size.width.toInt()}x${size.height.toInt()}${mirror ? ' lật' : ''}: $n px');
        }
      }
    }
    expect(bad, isEmpty);
  });

  test('kiểu nào cũng có tên, nhóm hợp lệ và id không trùng', () {
    final groups = {for (final (id, _) in bubbleGroups) id};
    final ids = <String>{};
    for (final s in bubbleStyles) {
      expect(ids.add(s.id), isTrue, reason: 'trùng id ${s.id}');
      expect(s.name.isNotEmpty, isTrue);
      expect(s.group.isEmpty || groups.contains(s.group), isTrue, reason: s.id);
    }
  });

  test('chữ trên mọi màu bong bóng đạt tương phản 4.5:1', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (var r = 0; r < 256; r += 15) {
      for (var g = 0; g < 256; g += 15) {
        for (var b = 0; b < 256; b += 15) {
          final c = Color.fromARGB(255, r, g, b);
          expect(contrast(bubbleTextOn(c), c), greaterThanOrEqualTo(4.5), reason: bubbleHex(c));
        }
      }
    }
  });

  test('lưu / đọc lựa chọn', () {
    expect(BubbleChoice.fromJson({'s': 'quockyvn'})?.style, 'quockyvn');
    expect(BubbleChoice.fromJson({'s': 'quockyvn', 'c': '#123ABC'})?.color, const Color(0xFF123ABC));
    // Kiểu lạ từ app mới hơn: giữ màu, bỏ hình.
    expect(BubbleChoice.fromJson({'s': 'kieu-moi', 'c': '00FF00'})?.style, kBubblePlain);
    expect(BubbleChoice.fromJson({'s': 'kieu-moi'}), isNull);
    expect(BubbleChoice.fromJson('rác'), isNull);
    expect(const BubbleChoice('quockyvn').toJson(), {'s': 'quockyvn'});
    expect(BubbleChoice('meo', const Color(0xFF000000)).toJson(), {'s': 'meo', 'c': '000000'});
  });
}
