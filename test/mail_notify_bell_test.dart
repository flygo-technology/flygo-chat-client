// Chuông "Báo thư mới qua tin nhắn" trên đầu Thư: hiện khi máy chủ có tính năng notify, bấm để tắt / bật.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';

class _Api extends DemoMailApi {
  bool on = true;
  final calls = <bool>[];
  @override
  bool get demo => false;
  @override
  Future<MailMe> me() async {
    final m = await super.me();
    return MailMe(m.person, mailboxes: m.mailboxes, boxes: m.boxes, access: m.access, user: m.user, admin: m.admin, features: const {'notify': true}, notify: on);
  }

  @override
  Future<void> setNotify(bool v) async {
    calls.add(v);
    on = v;
  }
}

void main() {
  testWidgets('chuông báo thư mới: bật sẵn, bấm để tắt rồi bật lại', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = _Api();
    await t.pumpWidget(MaterialApp(home: MailHome(store: MailStore(api), title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final bell = find.byKey(const ValueKey('mail-notify-bell'));
    expect(bell, findsOneWidget);
    expect(find.descendant(of: bell, matching: find.byIcon(Icons.notifications_active_outlined)), findsOneWidget);
    await t.tap(bell);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(api.calls, [false]);
    expect(find.descendant(of: bell, matching: find.byIcon(Icons.notifications_off_outlined)), findsOneWidget);
    expect(find.textContaining('Đã tắt báo thư mới'), findsOneWidget);
    await t.tap(bell);
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(api.calls, [false, true]);
    expect(find.descendant(of: bell, matching: find.byIcon(Icons.notifications_active_outlined)), findsOneWidget);
  });

  testWidgets('điện thoại 360: đầu Thư có chuông vẫn không tràn', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: MailHome(store: MailStore(_Api()), title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('mail-notify-bell')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
