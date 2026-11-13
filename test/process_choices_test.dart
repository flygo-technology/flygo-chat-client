// Phần `choices` của thẻ flygo_card (bước "Lựa chọn"): ô tích, min / max, nút Gửi, payload trả lời trong luồng.
// Ảnh xem trước (chạy tay): EDITOR_OUT=<thư mục> flutter test test/process_choices_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/ui/flygo_card.dart';
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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['EDITOR_OUT'];
  final card = {
    'v': 1,
    'icon': 'invoice',
    'accent': 'orange',
    'title': 'Hoá đơn 2154 · Cty Hoàng Long',
    'status': {'label': 'Nghi trùng', 'tone': 'orange'},
    'fields': [
      {'label': 'Số tiền', 'value': '128.450.000 ₫', 'kind': 'money'},
    ],
    'choices': {
      'id': 'xu_ly',
      'title': 'Xử lý hoá đơn nghi trùng',
      'options': [
        {'id': 'xuat', 'label': 'Vẫn xuất hoá đơn'},
        {'id': 'bao_kt', 'label': 'Báo kế toán trưởng'},
        {'id': 'huy', 'label': 'Huỷ hoá đơn'},
      ],
      'min': 1,
      'max': 2,
      'submit_label': 'Gửi lựa chọn',
    },
  };
  final post = MmPost({'id': 'card-1', 'channel_id': 'c', 'user_id': 'bot', 'create_at': 0, 'message': 'x', 'props': {'flygo_card': card}});

  Future<void> pump(WidgetTester t, Map<String, dynamic> m, void Function(Map<String, dynamic>)? onAction, {Brightness b = Brightness.light}) async {
    t.view.physicalSize = const Size(420, 560);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: Scaffold(body: Center(child: FlygoCard(data: FlygoCardData(m), width: 360, onAction: onAction == null ? null : (a) async => onAction(a)))),
      ),
    ));
    await t.pump();
  }

  Future<void> snap(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  FilledButton submit(WidgetTester t) => t.widget<FilledButton>(find.ancestor(of: find.text('Gửi lựa chọn'), matching: find.byType(FilledButton)));

  testWidgets('chọn trong khoảng min..max rồi gửi: payload đúng, khoá sau khi gửi', (t) async {
    if (out != null) await t.runAsync(_fonts);
    final sent = <Map<String, dynamic>>[];
    await pump(t, card, sent.add);
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.text('Chọn từ 1 đến 2 mục'), findsOneWidget);
    expect(submit(t).onPressed, isNull, reason: 'chưa chọn gì thì chưa gửi được');

    await t.tap(find.text('Vẫn xuất hoá đơn'));
    await t.tap(find.text('Huỷ hoá đơn'));
    await t.tap(find.text('Báo kế toán trưởng'));
    await t.pump();
    final ticked = [for (final c in t.widgetList<Checkbox>(find.byType(Checkbox))) c.value];
    expect(ticked, [true, false, true], reason: 'tối đa 2 mục');
    expect(submit(t).onPressed, isNotNull);
    await snap(t, 'card-choices');

    await t.tap(find.text('Gửi lựa chọn'));
    await t.pump();
    await t.pump();
    expect(sent, hasLength(1));
    expect(sent.single['id'], 'xu_ly');
    expect(sent.single['values'], ['xuat', 'huy']);
    expect(sent.single['label'], 'Gửi lựa chọn');
    expect(sent.single['reply'], 'Gửi lựa chọn: Vẫn xuất hoá đơn, Huỷ hoá đơn');
    // Khoá sau khi gửi.
    expect(find.text('Đã gửi lựa chọn'), findsOneWidget);
    expect(submit(t).onPressed, isNull);
    expect(t.widgetList<Checkbox>(find.byType(Checkbox)).every((c) => c.onChanged == null), isTrue);
    await snap(t, 'card-choices-sent');

    // Trả lời trong luồng: props.flygo_card_action = {post_id, id, label, values}.
    expect(flygoCardActionProps(post, sent.single), {
      'flygo_card_action': {'post_id': 'card-1', 'id': 'xu_ly', 'label': 'Gửi lựa chọn', 'values': ['xuat', 'huy']},
    });
  });

  testWidgets('chọn một (max 1): tích mục mới thay mục cũ; máy chủ đánh dấu done thì khoá', (t) async {
    final one = {
      ...card,
      'choices': {...card['choices'] as Map, 'max': 1, 'submit_label': null},
    };
    final sent = <Map<String, dynamic>>[];
    await pump(t, one, sent.add);
    expect(find.text('Chọn 1 mục'), findsOneWidget);
    await t.tap(find.text('Vẫn xuất hoá đơn'));
    await t.tap(find.text('Báo kế toán trưởng'));
    await t.pump();
    expect([for (final c in t.widgetList<Checkbox>(find.byType(Checkbox))) c.value], [false, true, false]);
    await t.tap(find.text('Gửi'));
    await t.pump();
    expect(sent.single['values'], ['bao_kt']);
    expect(sent.single['id'], 'xu_ly');

    await pump(t, {...card, 'choices': {...card['choices'] as Map, 'done': true}}, sent.add);
    expect(find.text('Đã gửi lựa chọn'), findsOneWidget);
    expect(t.widgetList<Checkbox>(find.byType(Checkbox)).every((c) => c.onChanged == null), isTrue);
  });

  test('nút id thường: payload như cũ, không có values', () {
    expect(flygoCardActionProps(post, {'id': 'accept', 'label': 'Nhận việc'}), {
      'flygo_card_action': {'post_id': 'card-1', 'id': 'accept', 'label': 'Nhận việc'},
    });
  });

  testWidgets('thẻ không có choices: không có ô tích', (t) async {
    await pump(t, {'v': 1, 'title': 'Hoá đơn', 'actions': [{'label': 'OK', 'id': 'ok'}]}, (_) {});
    expect(find.byType(Checkbox), findsNothing);
  });
}
