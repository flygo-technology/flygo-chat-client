import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/cast/cast_slides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bỏ ký hiệu Markdown trong dòng', () {
    expect(plainInline('**Đậm** và *nghiêng*, `mã`, [link](https://x) ![a](b)'), 'Đậm và nghiêng, mã, link');
  });
  test('dựng slide 16:9 tiếng Việt', () async {
    final body = List.generate(14, (i) => '## Mục ${i + 1}\n- Nội dung dòng một của mục ${i + 1}, có dấu tiếng Việt đầy đủ\n- Dòng hai\n').join('\n');
    final pdf = await castSlidesPdf([CastSection(title: 'Quy trình bảo trì thang máy', subtitle: 'Wiki · Phòng kỹ thuật', body: body)]);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final out = Platform.environment['CAST_SLIDES_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
  });
  test('bảng tin: mỗi bài một trang, bài dài bị cắt cho vừa', () async {
    final long = List.filled(40, 'Một câu rất dài trong bài viết để thử cắt bớt nội dung cho vừa một trang.').join(' ');
    final pdf = await castSlidesPdf([
      for (var i = 0; i < 5; i++) CastSection(title: 'Thông báo số ${i + 1} ' * (i == 0 ? 8 : 1), subtitle: 'Phòng HC', body: long),
    ], maxPagesEach: 1);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final out = Platform.environment['CAST_BOARD_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
  });
}
