// Chat với trợ lý: không gửi tin thoại (Sếp: tránh bấm nhầm); nút mic chỉ chuyển giọng nói thành chữ.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/attach_panel.dart';
import 'package:flygo_chat/ui/theme.dart';

void main() {
  for (final agent in [true, false]) {
    testWidgets('"+" panel ${agent ? 'in an agent chat has no' : 'in a human chat keeps'} "Ghi âm"', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showAttachPanel(c, agent: agent), child: const Text('+')))),
      ));
      await t.tap(find.text('+'));
      await t.pumpAndSettle();
      expect(find.text('Ghi âm'), agent ? findsNothing : findsOneWidget);
      expect(find.text('Chọn file'), findsOneWidget);
    });
  }

  test('voice is one of the actions hidden in agent chats', () {
    expect(agentHiddenActions, contains(AttachAction.voice));
  });
}
