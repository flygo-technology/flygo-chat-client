import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/notes.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

/// Bản 289: Enter lưu ghi chú trên máy tính.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba'});
  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: child)),
      );

  testWidgets('máy tính: Enter lưu ghi chú, Shift+Enter không lưu', (t) async {
    if (!isDesktop) return;
    (String, String, String)? got;
    await t.pumpWidget(wrap(Builder(builder: (c) => FilledButton(onPressed: () async => got = await showNoteEditor(c), child: const Text('mở')))));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Gọi lại cho NCC');
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    expect(got, isNull, reason: 'Shift+Enter không lưu');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(got, ('Gọi lại cho NCC', 'yellow', 'none'));
  });
}
