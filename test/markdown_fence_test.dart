// Dấu ``` dính vào chữ (bot gửi "@tên ```text" cùng một dòng): tách ra dòng riêng để hiện đúng khối code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/markdown_view.dart';
import 'package:flygo_chat/ui/theme.dart';

void main() {
  test('mention then opening fence on the same line: fence moves to its own line', () {
    expect(splitGluedFences('@ba.flygo.vn ```text\nTiêu đề: Re: báo giá\n1. một\n```'),
        '@ba.flygo.vn\n```text\nTiêu đề: Re: báo giá\n1. một\n```');
    expect(splitGluedFences('@a @b ```\nx\n```'), '@a @b\n```\nx\n```');
    expect(splitGluedFences('Xem nội dung:```json\n{"a":1}\n```'), 'Xem nội dung:\n```json\n{"a":1}\n```');
  });

  test('closing fence glued to the last line is split when nothing else closes the block', () {
    expect(splitGluedFences('@ba ```text\ndòng 1\ndòng cuối```'), '@ba\n```text\ndòng 1\ndòng cuối\n```');
    expect(splitGluedFences('```\ndòng cuối```\nsau khối'), '```\ndòng cuối\n```\nsau khối');
    // Có dấu đóng đúng chuẩn phía sau: dòng "a```" là nội dung của khối, giữ nguyên.
    expect(splitGluedFences('```\na```\n```'), '```\na```\n```');
  });

  test('valid blocks, inline code and list items are untouched', () {
    const ok = 'Trước\n```dart\nfinal x = "@a ```b";\n```\nSau';
    expect(splitGluedFences(ok), ok);
    expect(splitGluedFences('dùng ```a``` trong dòng'), 'dùng ```a``` trong dòng');
    expect(splitGluedFences('- ```\n  x\n  ```'), '- ```\n  x\n  ```');
    expect(splitGluedFences('1. ```sh\n   ls\n   ```'), '1. ```sh\n   ls\n   ```');
    expect(splitGluedFences('~~~\n@a ```text\n~~~'), '~~~\n@a ```text\n~~~');
    expect(splitGluedFences('không có khối'), 'không có khối');
  });

  testWidgets('rendered as a code block: no literal ```text, list inside stays plain text', (t) async {
    const msg = '@ba.flygo.vn ```text\nTiêu đề: Re: báo giá\n1. một\n2. hai\n```';
    expect(MarkdownView.isSimple(msg), isFalse);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: MarkdownView(text: msg, style: TextStyle(fontSize: 16))),
    ));
    final shown = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? '').join('\n');
    expect(shown, isNot(contains('```')));
    expect(find.text('Tiêu đề: Re: báo giá\n1. một\n2. hai'), findsOneWidget);
    expect(shown, contains('@ba.flygo.vn'));
  });
}
