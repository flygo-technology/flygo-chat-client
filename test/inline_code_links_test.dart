// Link / email trong mã nội dòng của trợ lý (`https://…`): giữ kiểu chữ mã nhưng bấm được.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/links.dart';
import 'package:flygo_chat/ui/markdown_view.dart';
import 'package:flygo_chat/ui/theme.dart';

List<TextSpan> _tappable(WidgetTester t) {
  final out = <TextSpan>[];
  for (final rt in t.widgetList<RichText>(find.byType(RichText))) {
    rt.text.visitChildren((s) {
      if (s is TextSpan && s.recognizer is TapGestureRecognizer) out.add(s);
      return true;
    });
  }
  return out;
}

Future<void> _pump(WidgetTester t, String text) => t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: MarkdownView(text: text, style: const TextStyle(fontSize: 16))),
    ));

void main() {
  testWidgets('URL and email inside inline code: code style kept, both tappable with copy buttons', (t) async {
    await _pump(t, 'Link test: `https://play.google.com/apps/internaltest/4701232710350855718` · mail `ba@flygo.vn`.');
    final links = _tappable(t);
    expect(links.map((s) => s.text), ['https://play.google.com/apps/internaltest/4701232710350855718', 'ba@flygo.vn']);
    // Vẫn là chữ mã (phông đơn cách, nền nhạt).
    expect(links.every((s) => s.style?.fontFamily == 'monospace' && s.style?.backgroundColor != null), isTrue);
    expect(find.byType(InlineLinkButtons), findsNWidgets(2));
    final mail = t.widgetList<InlineLinkButtons>(find.byType(InlineLinkButtons)).last.link;
    expect(mail.isEmail, isTrue);
    expect(mail.uri.toString(), 'mailto:ba@flygo.vn');
    expect(mail.copyText, 'ba@flygo.vn');
  });

  testWidgets('bare URLs and emails are linked; fenced code blocks are not', (t) async {
    await _pump(t, 'Xem https://chat.flygo.vn/x, gửi ba@flygo.vn.\n\n```\nhttps://not-linked.example.com\n```');
    expect(_tappable(t).map((s) => s.text), ['https://chat.flygo.vn/x', 'ba@flygo.vn']);
  });

  test('inline code without links stays a single span; a trailing backtick never joins a URL', () {
    final pal = Pal.light;
    final spans = codeLinkSpans('flutter build apk', const TextStyle(fontFamily: 'monospace'), pal);
    expect(spans, hasLength(1));
    expect(findLinks('`https://a.example.com/p`').single.text, 'https://a.example.com/p');
    expect(MarkdownView.isSimple('dùng `x` nhé'), isFalse);
  });
}
