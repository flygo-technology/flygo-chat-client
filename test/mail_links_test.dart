// Link trong thư: bấm vào chữ của link (kể cả chữ đậm / lồng thẻ bên trong) mở link; ảnh nằm trong link mở link
// (không mở trình xem ảnh); "www." không có giao thức thì thêm https; javascript: bỏ qua; mailto thành thư mới.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/compose.dart';
import 'package:flygo_chat/ui/mail/html_view.dart';

void main() {
  Future<List<Uri>> tapIn(WidgetTester t, String html, Finder target, {void Function(String)? onImage, Future<Uint8List?> Function(String)? inline}) async {
    final got = <Uri>[];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: MailHtml(html, onLink: got.add, onImageTap: onImage, inlineImage: inline))));
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.tap(target);
    await t.pump();
    return got;
  }

  testWidgets('chữ của link mở link (link chiếm cả đoạn và link lồng chữ đậm)', (t) async {
    expect(await tapIn(t, '<p><a href="https://example.com/a">Mở trang A</a></p>', find.textContaining('Mở trang A', findRichText: true)),
        [Uri.parse('https://example.com/a')]);
    expect(await tapIn(t, '<p><a href="https://track.example.com/c?u=1&amp;v=2"><b><span>Xem đơn hàng</span></b></a></p>', find.textContaining('Xem đơn hàng', findRichText: true)),
        [Uri.parse('https://track.example.com/c?u=1&v=2')]);
  });

  testWidgets('www. không có giao thức: thêm https; javascript: thì không phải link', (t) async {
    expect(await tapIn(t, '<p><a href=" www.flygo.vn/x ">flygo</a></p>', find.textContaining('flygo', findRichText: true)), [Uri.parse('https://www.flygo.vn/x')]);
    expect(await tapIn(t, '<p><a href="javascript:alert(1)">bấm</a></p>', find.textContaining('bấm', findRichText: true)), isEmpty);
  });

  testWidgets('ảnh nằm trong link: mở link, không mở trình xem ảnh', (t) async {
    final png = (await t.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 300, 80), Paint()..color = Colors.red);
      final img = await rec.endRecording().toImage(300, 80);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    }))!;
    var viewer = 0;
    final got = await tapIn(
      t,
      '<a href="https://shop.example/sale"><img src="/mail/api/attachments/e/banner" width="300"></a>',
      find.byKey(const ValueKey('mail-img-link-/mail/api/attachments/e/banner')),
      onImage: (_) => viewer++,
      inline: (_) async => png,
    );
    expect(got, [Uri.parse('https://shop.example/sale')]);
    expect(viewer, 0);
  });

  test('mailto: người nhận, cc, tiêu đề, nội dung', () {
    final a = mailtoArgs(Uri.parse('mailto:a@x.vn,b@y.vn?cc=c@z.vn&subject=B%C3%A1o%20gi%C3%A1&body=Ch%C3%A0o'));
    expect(a.to.map((p) => p.email), ['a@x.vn', 'b@y.vn']);
    expect(a.cc.map((p) => p.email), ['c@z.vn']);
    expect(a.subject, 'Báo giá');
    expect(a.body, 'Chào');
  });
}
