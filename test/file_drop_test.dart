import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/file_drop.dart';
import 'package:flygo_chat/ui/theme.dart';

/// Kéo thả tệp vào khung chat (máy tính): hiện "Thả để đính kèm" khi đang kéo, thả là đưa tệp vào ô soạn tin.
void main() {
  testWidgets('đang kéo: hiện khung "Thả để đính kèm"; thả: nhận đủ tệp, bỏ mục rỗng', (t) async {
    final got = <List<(String, String)>>[];
    final key = GlobalKey<FileDropZoneState>();
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: FileDropZone(key: key, enabled: true, onFiles: got.add, child: const Center(child: Text('khung chat')))),
    ));
    expect(find.text('Thả để đính kèm'), findsNothing);
    key.currentState!.hover(true);
    await t.pump();
    expect(find.text('Thả để đính kèm'), findsOneWidget);
    expect(find.text('khung chat'), findsOneWidget, reason: 'khung phủ lên, chat vẫn còn bên dưới');
    key.currentState!.drop([('/tmp/bao-gia.pdf', 'bao-gia.pdf'), ('', 'rong'), ('/tmp/anh.png', 'anh.png')]);
    await t.pump();
    expect(find.text('Thả để đính kèm'), findsNothing);
    expect(got, [
      [('/tmp/bao-gia.pdf', 'bao-gia.pdf'), ('/tmp/anh.png', 'anh.png')],
    ]);
  });

  testWidgets('kéo ra ngoài: tắt khung, không đính kèm', (t) async {
    final got = <List<(String, String)>>[];
    final key = GlobalKey<FileDropZoneState>();
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: FileDropZone(key: key, enabled: true, onFiles: got.add, child: const SizedBox.expand()))));
    key.currentState!.hover(true);
    await t.pump();
    key.currentState!.hover(false);
    await t.pump();
    expect(find.text('Thả để đính kèm'), findsNothing);
    expect(got, isEmpty);
  });

  testWidgets('điện thoại: không bọc gì', (t) async {
    await t.pumpWidget(MaterialApp(home: FileDropZone(enabled: false, onFiles: (_) {}, child: const Text('x'))));
    expect(find.descendant(of: find.byType(FileDropZone), matching: find.byType(Stack)), findsNothing);
  });
}
