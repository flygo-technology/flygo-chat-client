import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/notes.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Ghi chú gắn vào tin: đọc props, hiện người tạo, hộp thoại chọn màu, gọi trạm, quyền sửa / xoá.
void main() {
  kServerUrl = 'https://chat.flygo.vn';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['me'] = app.me!;
  app.users['u2'] = MmUser({'id': 'u2', 'username': 'lan', 'first_name': 'Lan'});

  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Center(child: child))),
      );

  MmPost post(List<Map<String, dynamic>> notes) =>
      MmPost({'id': 'p' * 26, 'channel_id': 'c1', 'user_id': 'u2', 'message': 'Báo giá cáp thép', 'create_at': 0, 'props': {'flygo_notes': notes}});

  test('đọc props, bỏ phần tử sai khuôn', () {
    final p = post([
      {'id': 'n1', 'by': 'u2', 'color': 'green', 'text': 'Đã gọi NCC', 'at': 1},
      {'text': 'không có id'},
    ]);
    final n = notesOfPost(p);
    expect(n.single.by, 'u2');
    expect(n.single.color, 'green');
  });

  testWidgets('hiện người tạo; ghi chú của người khác không có Sửa / Xoá', (t) async {
    await t.pumpWidget(wrap(MessageNotes(app: app, post: post([
      {'id': 'n1', 'by': 'u2', 'color': 'green', 'text': 'Đã gọi NCC, chờ báo giá', 'at': 1793840400000},
      {'id': 'n2', 'by': 'me', 'color': 'yellow', 'text': 'Nhắc kế toán đối chiếu', 'at': 1793840400000, 'edited_at': 1793844000000},
    ]), width: 320)));
    expect(find.textContaining('Lan'), findsOneWidget);
    expect(find.textContaining('Bạn'), findsOneWidget);
    expect(find.textContaining('đã sửa'), findsOneWidget);
    await t.longPress(find.text('Đã gọi NCC, chờ báo giá'));
    await t.pumpAndSettle();
    expect(find.text('Sao chép'), findsOneWidget);
    expect(find.text('Sửa ghi chú'), findsNothing);
    expect(find.text('Xoá ghi chú'), findsNothing);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.longPress(find.text('Nhắc kế toán đối chiếu'));
    await t.pumpAndSettle();
    expect(find.text('Sửa ghi chú'), findsOneWidget);
    expect(find.text('Xoá ghi chú'), findsOneWidget);
  });

  testWidgets('thêm ghi chú: chọn màu, nhập nội dung, gọi trạm', (t) async {
    final sent = <Map>[];
    notesDebugClient = MockClient((r) async {
      sent.add({'url': r.url.toString(), ...jsonDecode(r.body) as Map});
      return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'notes': [{'id': 'n9', 'by': 'me', 'color': 'blue', 'text': 'Gửi lại hoá đơn đỏ', 'at': 1}]})), 200);
    });
    addTearDown(() => notesDebugClient = null);
    final p = post(const []);
    await t.pumpWidget(wrap(Builder(builder: (c) => FilledButton(onPressed: () => addMessageNote(c, app, p), child: const Text('mở')))));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.text('Thêm ghi chú'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Lưu')).onPressed, isNull, reason: 'chưa có nội dung thì chưa lưu được');
    await t.tap(find.bySemanticsLabel('blue'));
    await t.enterText(find.byType(TextField), '  Gửi lại hoá đơn đỏ ');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await t.pumpAndSettle();
    expect(sent.single['url'], startsWith('https://push.flygo.vn/notes/add'));
    expect(sent.single['color'], 'blue');
    expect(sent.single['text'], 'Gửi lại hoá đơn đỏ');
    expect(sent.single['post_id'], 'p' * 26);
  });

  testWidgets('dòng tin bị dựng lại khi hộp thoại đang mở: bấm Lưu vẫn gửi ghi chú (không bỏ qua im lặng)', (t) async {
    final sent = <Map>[];
    notesDebugClient = MockClient((r) async {
      sent.add(jsonDecode(r.body) as Map);
      return http.Response.bytes(utf8.encode(jsonEncode({'ok': true, 'notes': const []})), 200);
    });
    addTearDown(() => notesDebugClient = null);
    final p = post(const []);
    final show = ValueNotifier(true);
    await t.pumpWidget(wrap(ValueListenableBuilder<bool>(
      valueListenable: show,
      builder: (_, on, _) => on
          ? Builder(key: const ValueKey('row'), builder: (c) => FilledButton(onPressed: () => addMessageNote(c, app, p), child: const Text('mở')))
          : const Text('đã dựng lại'),
    )));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    show.value = false;
    await t.pump();
    await t.enterText(find.byType(TextField), 'Đối chiếu hoá đơn');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await t.pumpAndSettle();
    expect(sent.single['text'], 'Đối chiếu hoá đơn');
  });

  testWidgets('trạm không trả lời: báo rõ "trạm không phản hồi", không hiện TimeoutException', (t) async {
    notesDebugClient = MockClient((r) => Completer<http.Response>().future);
    addTearDown(() => notesDebugClient = null);
    final p = post(const []);
    await t.pumpWidget(wrap(Builder(builder: (c) => FilledButton(onPressed: () => addMessageNote(c, app, p), child: const Text('mở')))));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Đối chiếu sao kê');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await t.pump(const Duration(seconds: 16));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('trạm không phản hồi'), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);
    // Cho thông báo và lần tải lại tin chạy hết giờ chờ.
    await t.pump(const Duration(minutes: 1));
    await t.pumpAndSettle();
  });
}
