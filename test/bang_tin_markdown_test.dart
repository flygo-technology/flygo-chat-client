// Bảng tin hỗ trợ Markdown (Sếp, 2026-11-18): bài và bình luận hiển thị bằng bộ Markdown của chat, link an toàn.
// Ảnh xem trước (chạy tay): BT_OUT=<thư mục> flutter test test/bang_tin_markdown_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/bang_tin/feed_widgets.dart';
import 'package:flygo_chat/ui/markdown_view.dart';
import 'package:flygo_chat/ui/theme.dart';

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

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

const _md = '''## Lịch đi Sa Pa tháng 12

Cả nhà **chuẩn bị** giúp mình nhé, _đọc kỹ_ trước khi đăng ký:

1. Đăng ký trước **thứ Sáu**
   - Ghi rõ số người đi cùng
   - Ăn chay thì báo riêng
2. Đóng phí tại phòng Kế toán
   1. Chuyển khoản: `1903 0000 8868`
   2. Tiền mặt: gặp chị My

- [x] Đặt xe
- [ ] Đặt khách sạn

> Ai có câu hỏi thì bình luận bên dưới.

| Ngày | Hoạt động |
| --- | --- |
| 06/12 | Fansipan |
| 07/12 | Bản Cát Cát |

Xem thêm [lịch trình chi tiết](https://flygo.vn/sapa) · [link lạ](javascript:alert(1)) · [tệp](/etc/passwd)

```
08:00 tập trung tại công ty
```''';

void main() {
  final out = Platform.environment['BT_OUT'];

  test('chữ thô của markdown: bỏ dấu, giữ xuống dòng giữa mục danh sách lồng', () {
    final p = MarkdownView.plain(_md);
    expect(p, startsWith('Lịch đi Sa Pa tháng 12\nCả nhà chuẩn bị giúp mình nhé, đọc kỹ trước khi đăng ký:'));
    expect(p, contains('Ghi rõ số người đi cùng\nĂn chay thì báo riêng'));
    expect(p, contains('☑ Đặt xe'));
    expect(p, contains('lịch trình chi tiết'));
    expect(p, isNot(contains('**')));
    expect(p, isNot(contains('](')));
    // Bài cũ chữ thường: giữ nguyên.
    expect(MarkdownView.plain('Chào cả nhà\nHẹn gặp lại'), 'Chào cả nhà\nHẹn gặp lại');
  });

  testWidgets('bài Markdown: tiêu đề, danh sách lồng, ô chọn, bảng, mã; chỉ link http(s) bấm được', (t) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = const Size(720, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    for (final b in [Brightness.light, Brightness.dark]) {
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: PostBody(post: const {'id': 'p1', 'title': '', 'body': _md}, full: true),
            ),
          ),
        ),
      ));
      await t.pump();
      expect(find.byType(MarkdownView), findsOneWidget);
      // Link trong bài: chỉ "lịch trình chi tiết" là link (gạch chân, bấm được); javascript: và đường dẫn tệp là chữ thường.
      final spans = <TextSpan>[];
      for (final rt in t.widgetList<RichText>(find.byType(RichText))) {
        rt.text.visitChildren((s) {
          if (s is TextSpan) spans.add(s);
          return true;
        });
      }
      final linked = [for (final s in spans) if (s.recognizer is TapGestureRecognizer) s.text];
      expect(linked, ['lịch trình chi tiết']);
      expect(spans.any((s) => s.text == 'link lạ'), isTrue);
      expect(find.textContaining('Fansipan', findRichText: true), findsOneWidget);
      if (out != null) {
        await t.runAsync(() async {
          await Directory(out).create(recursive: true);
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/bang-tin-markdown-${b.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
    }
  });
}
