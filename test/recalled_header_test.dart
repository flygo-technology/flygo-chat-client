import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/theme.dart';

/// Tin thu hồi là tin đầu của một lượt trong nhóm: vẫn có tên người gửi (trước đây mất tên).
void main() {
  Widget wrap(Widget w) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w));
  final t0 = DateTime(2026, 11, 13, 13, 40);

  testWidgets('tin đầu lượt: tên người gửi phía trên dòng "đã được thu hồi"', (t) async {
    await t.pumpWidget(wrap(RecalledMessage(mine: false, time: t0, name: const Text('~Lan Kế toán'))));
    expect(find.text('~Lan Kế toán'), findsOneWidget);
    expect(find.text('Tin nhắn đã được thu hồi'), findsOneWidget);
    expect(find.text('13:40'), findsOneWidget);
    expect(t.getTopLeft(find.text('~Lan Kế toán')).dy, lessThan(t.getTopLeft(find.text('Tin nhắn đã được thu hồi')).dy));
  });

  testWidgets('tin giữa lượt / của mình: không có tên', (t) async {
    await t.pumpWidget(wrap(RecalledMessage(mine: true, time: t0)));
    expect(find.text('Bạn đã thu hồi một tin nhắn'), findsOneWidget);
    expect(find.textContaining('~'), findsNothing);
  });
}
