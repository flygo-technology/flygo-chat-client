import 'dart:async';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/attachments.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/thread_view.dart' show MailHooks;
import 'package:flygo_chat/ui/mail/html_view.dart';
import 'package:flygo_chat/ui/mail/image_trust.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/mail/when.dart';

/// /me chưa trả lời: màn hình chờ thay vì giao diện trống.
class _Slow extends DemoMailApi {
  final gate = Completer<void>();
  @override
  Future<MailMe> me() async {
    await gate.future;
    return super.me();
  }
}

void main() {
  testWidgets('đang tải hộp thư: hiện vòng chờ, tải xong thì vào hộp thư', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = _Slow();
    final store = MailStore(api);
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    await t.pump();
    expect(find.byKey(const ValueKey('mail-loading')), findsOneWidget);
    expect(find.text('Đang tải hộp thư…'), findsOneWidget);
    api.gate.complete();
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('mail-loading')), findsNothing);
  });

  testWidgets('Tóm tắt bằng AI: nút cạnh "Xem hòm thư khác", liệt kê việc từ thư chưa đọc', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Tóm tắt bằng AI'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('mail-ai-digest')));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Việc cần làm'), findsOneWidget);
    expect(find.textContaining('Đọc và trả lời'), findsWidgets);
  });

  testWidgets('AI soạn trả lời: mở ô trả lời có sẵn nội dung AI', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    store.items.isNotEmpty ? null : fail('no demo threads');
    final first = store.items.first;
    t.state<MailHomeState>(find.byType(MailHome)).openThread(first);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.ensureVisible(find.byKey(const ValueKey('mail-ai-reply')));
    await t.tap(find.byKey(const ValueKey('mail-ai-reply')));
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final draft = (await t.runAsync(() => store.api.ai(first.id)))!;
    final line = draft.draft.split('\n').map((l) => l.trim()).firstWhere((l) => l.length > 8);
    expect(find.textContaining(line.substring(0, 8)), findsWidgets);
  });

  testWidgets('điện thoại: nút tóm tắt AI là biểu tượng, không tràn dòng', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('mail-ai-digest')), findsOneWidget);
    expect(find.byKey(const ValueKey('mail-other-boxes')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('khung trả lời: mặc định Trả lời tất cả, đổi được trước khi gửi; AI sửa theo lệnh, có hoàn tác', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    t.state<MailHomeState>(find.byType(MailHome)).openThread(store.items.first);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.widgetWithText(OutlinedButton, 'Trả lời').first);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('mail-reply-mode')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('mail-reply-mode')), matching: find.text('Trả lời tất cả')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('mail-reply-mode')));
    await t.pumpAndSettle();
    await t.tap(find.text('Trả lời').last);
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('mail-reply-mode')), matching: find.text('Trả lời')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('mail-ai-revise-btn')));
    await t.pump();
    expect(find.byKey(const ValueKey('mail-ai-revise')), findsOneWidget);
    await t.enterText(find.descendant(of: find.byKey(const ValueKey('mail-ai-revise')), matching: find.byType(TextField)), 'ngắn gọn hơn');
    await t.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Đã sửa theo yêu cầu: ngắn gọn hơn'), findsWidgets);
    await t.tap(find.text('Hoàn tác'));
    await t.pump();
    expect(find.textContaining('Đã sửa theo yêu cầu'), findsNothing);
  });

  testWidgets('điện thoại: bấm avatar mở bộ chọn hộp thư và đổi được hộp', (t) async {
    t.view.physicalSize = const Size(412, 915);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final before = store.me!.current.id;
    final other = store.me!.boxes.firstWhere((b) => b.id != before);
    await t.tap(find.byKey(const ValueKey('mail-switcher')));
    await t.pumpAndSettle();
    expect(find.text(other.id), findsWidgets);
    await t.tap(find.text(other.id).last);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(store.me!.current.id, other.id);
    // nút "Xem hòm thư khác" cũng mở được
    await t.tap(find.byKey(const ValueKey('mail-other-boxes')));
    await t.pumpAndSettle();
    expect(find.text(before), findsWidgets);
  });

  test('pickWhen labels: hôm nay / ngày mai', () {
    final n = DateTime.now();
    expect(whenLabel(DateTime(n.year, n.month, n.day, 18)), 'hôm nay 18:00');
    final t = n.add(const Duration(days: 1));
    expect(whenLabel(DateTime(t.year, t.month, t.day, 8)), 'ngày mai 08:00');
  });

  test('MailChange snooze json', () {
    final d = DateTime.utc(2026, 11, 18, 1);
    expect(MailChange(snooze: d).toJson()['snooze'], '2026-11-18T01:00:00.000Z');
    expect(const MailChange(unsnooze: true).toJson().containsKey('snooze'), true);
    expect(const MailChange(unsnooze: true).toJson()['snooze'], null);
    expect(MailChange(snooze: d).leavesBox, true);
  });

  testWidgets('khung soạn có nút Hẹn giờ gửi', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    t.state<MailHomeState>(find.byType(MailHome)).compose();
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('mail-send-later')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('mail-send-later')));
    await t.pumpAndSettle();
    expect(find.text('Hẹn giờ gửi'), findsWidgets);
    expect(find.text('Sáng mai'), findsOneWidget);
  });

  testWidgets('ảnh dán trong thư (cid -> /mail/api/attachments) hiện ngay, có đăng nhập', (t) async {
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
    String? asked;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MailHtml('<p>Xem ảnh</p><img src="/mail/api/attachments/e1/a1?mailbox=x%40y.vn" alt="image.png" width="300">',
            inlineImage: (p) async {
          asked = p;
          return png;
        }),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(asked, '/mail/api/attachments/e1/a1?mailbox=x%40y.vn');
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('tệp đính kèm: nút Tải về / Lưu vào Drive trên thẻ, Lưu tất cả, mở trình xem vuốt được', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    AttachmentThumb.pdfThumbs = false;
    final saved = <List<String>>[];
    MailHooks.saveToDrive = (context, files) async => saved.add([for (final f in files) f.$2]);
    addTearDown(() => MailHooks.saveToDrive = null);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final withAtt = store.items.firstWhere((x) => x.attachments.length > 1);
    t.state<MailHomeState>(find.byType(MailHome)).openThread(withAtt);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final a0 = withAtt.attachments[0], a1 = withAtt.attachments[1];
    await t.ensureVisible(find.byKey(ValueKey('att-dr-${a0.id}')));
    await t.tap(find.byKey(ValueKey('att-dr-${a0.id}')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(saved.last, [a0.name]);
    await t.tap(find.byKey(const ValueKey('att-drive-all')));
    for (var i = 0; i < 5 && saved.length < 2; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    expect(saved.last, [for (final a in withAtt.attachments) a.name]);
    await t.tap(find.text(a0.name).first);
    await t.pumpAndSettle();
    expect(find.byType(AttachmentViewer), findsOneWidget);
    expect(find.byKey(const ValueKey('att-download')), findsOneWidget);
    expect(find.byKey(const ValueKey('att-drive')), findsOneWidget);
    await t.fling(find.byType(PageView), const Offset(-600, 0), 1200);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, a1.name), findsOneWidget);
  });

  testWidgets('chữ ký bảng lồng nhau: không lặp, bỏ ô kẻ 1px, biểu tượng nhỏ bị ẩn không chiếm chỗ', (t) async {
    const html = '<table><tbody><tr><td><table><tbody><tr><td>0986 00 77 00 (Zalo)</td></tr></tbody></table></td>'
        '<td width="1" style="width:1px;border-left:1px solid red"><br>\\<br></td>'
        '<td><img src="https://cdn.example/phone.png" width="13"></td></tr></tbody></table>';
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: MailHtml(html))));
    expect(find.textContaining('0986 00 77 00', findRichText: true), findsOneWidget);
    expect(find.textContaining('\\', findRichText: true), findsNothing);
    expect(find.text('Ảnh'), findsNothing);
  });

  test('ảnh từ mạng: nhận ra thư có ảnh ngoài, không tính ảnh dán trong thư', () {
    expect(MailImageTrust.hasRemoteImages('<img src="https://x/y.png">'), true);
    expect(MailImageTrust.hasRemoteImages('<img src="/mail/api/attachments/a/b">'), false);
  });
}
