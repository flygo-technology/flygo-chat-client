import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/json_view.dart';
import 'package:flygo_chat/ui/markdown_view.dart';
import 'package:flygo_chat/ui/theme.dart';

/// JSON trong chi tiết bước / khối mã: định dạng đẹp, tô màu, thu gọn khi sâu / dài; chuỗi không phải JSON giữ nguyên.
void main() {
  Widget wrap(Widget w, {Brightness b = Brightness.light}) =>
      MaterialApp(theme: buildTheme(b), home: Scaffold(body: SingleChildScrollView(child: w)));

  /// Các mẩu chữ có màu trong khối JSON đang hiện.
  List<TextSpan> spans(WidgetTester t) {
    final st = t.widget<SelectableText>(find.byType(SelectableText).first);
    return st.textSpan!.children!.cast<TextSpan>();
  }

  test('pretty print: 2-space indent, key order kept', () {
    const src = '{"b":1,"a":[true,null,"x"],"c":{"d":2.5}}';
    final v = tryParseJson(src);
    expect(jsonPieces(v).map((p) => p.text).join(), const JsonEncoder.withIndent('  ').convert(jsonDecode(src)));
    expect(jsonPieces(v).map((p) => p.text).join().split('\n')[1], '  "b": 1,');
    expect(tryParseJson('not json'), isNull);
    expect(tryParseJson('{"a": 1'), isNull);
    expect(tryParseJson('"just a string"'), isNull);
    expect(tryParseJson('  [1, 2]  '), [1, 2]);
  });

  test('collapse deeper than level 2 and limit lines', () {
    final v = {
      'a': {
        'b': {'c': 1},
        'l': [1, 2],
      },
    };
    final text = jsonPieces(v, maxDepth: 2).map((p) => p.text).join();
    expect(text, contains('"b": {…1}'));
    expect(text, contains('"l": […2]'));
    final long = List.generate(50, (i) => i);
    final cut = limitLines(jsonPieces(long), 30);
    expect(cut.map((p) => p.text).join().split('\n').length, 31); // 30 dòng + "…"
    expect(cut.last.kind, JsonTok.more);
  });

  testWidgets('distinct colors for keys, strings, numbers, literals, punctuation (light and dark)', (t) async {
    for (final b in Brightness.values) {
      await t.pumpWidget(wrap(JsonView.orPlain('{"name":"Ba","n":3,"ok":true,"x":null}'), b: b));
      final ss = spans(t);
      Color? colorOf(String text) => ss.firstWhere((s) => s.text == text).style!.color;
      final colors = {colorOf('"name"'), colorOf('"Ba"'), colorOf('3'), colorOf('true'), colorOf('{')};
      expect(colors.length, 5, reason: '$b');
      expect(colorOf('null'), colorOf('true'));
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      final st = t.widget<SelectableText>(find.byType(SelectableText).first);
      expect(st.textSpan!.style!.fontFamily, 'monospace');
    }
  });

  testWidgets('long JSON collapses with "Xem thêm" toggle', (t) async {
    final big = jsonEncode({'items': List.generate(40, (i) => {'id': i, 'deep': {'x': i}})});
    await t.pumpWidget(wrap(JsonView.orPlain(big)));
    String shown() => spans(t).map((s) => s.text).join();
    expect(find.text('Xem thêm'), findsOneWidget);
    expect(shown(), contains('{…2}'));
    expect(shown().split('\n').length, lessThanOrEqualTo(31));
    await t.tap(find.text('Xem thêm'));
    await t.pump();
    expect(find.text('Thu gọn'), findsOneWidget);
    expect(shown(), const JsonEncoder.withIndent('  ').convert(jsonDecode(big)));
  });

  testWidgets('small JSON has no toggle; invalid JSON falls back to plain monospace', (t) async {
    await t.pumpWidget(wrap(JsonView.orPlain('{"a":1}')));
    expect(find.text('Xem thêm'), findsNothing);

    await t.pumpWidget(wrap(JsonView.orPlain('{"a": 1, oops')));
    expect(find.byType(JsonView), findsNothing);
    final st = t.widget<SelectableText>(find.byType(SelectableText));
    expect(st.data, '{"a": 1, oops');
    expect(st.style!.fontFamily, 'monospace');
  });

  testWidgets('markdown ```json block and bare JSON block render as JsonView, other code stays plain', (t) async {
    const style = TextStyle(fontSize: 15);
    await t.pumpWidget(wrap(const MarkdownView(text: '```json\n{"a":[1,2]}\n```', style: style)));
    expect(find.byType(JsonView), findsOneWidget);
    await t.pumpWidget(wrap(const MarkdownView(text: '```\n[1, {"b": false}]\n```', style: style)));
    expect(find.byType(JsonView), findsOneWidget);
    await t.pumpWidget(wrap(const MarkdownView(text: '```dart\nvoid main() {}\n```', style: style)));
    expect(find.byType(JsonView), findsNothing);
    await t.pumpWidget(wrap(const MarkdownView(text: '```json\n{broken\n```', style: style)));
    expect(find.byType(JsonView), findsNothing);
  });
}
