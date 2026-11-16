import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';

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
}
