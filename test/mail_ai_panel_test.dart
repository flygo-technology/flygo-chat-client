// Khung "AI đọc thư" nằm ở cuối cuộc hội thoại (sau thư cuối, trên nút Trả lời), bấm AI thì cuộn xuống tới nó;
// thư tự động (no-reply, cảnh báo) chỉ có tóm tắt + việc cần làm, kèm ghi chú "Thư tự động, không cần trả lời".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';

void main() {
  Future<MailStore> open(WidgetTester t, bool Function(MailThreadSummary) pick, {Size size = const Size(1440, 900)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail', ownsStore: false)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    t.state<MailHomeState>(find.byType(MailHome)).openThread(store.items.firstWhere(pick));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    return store;
  }

  Future<void> tapAi(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('mail-ai')));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  test('nhận ra địa chỉ của máy gửi', () {
    for (final e in ['no-reply@bank.example', 'google-workspace-alerts-noreply@google.com', 'notifications@github.com', 'alerts@x.vn', 'mailer-daemon@googlemail.com']) {
      expect(isAutomatedSender(e), isTrue, reason: e);
    }
    for (final e in ['jason.jia@hpmont.com', 'ba@flygo.vn', 'receipt@dnd-global.com', 'replyto@x.vn']) {
      expect(isAutomatedSender(e), isFalse, reason: e);
    }
  });

  testWidgets('khung AI ở cuối: sau thư cuối, trên nút Trả lời; bấm AI thì cuộn tới khung', (t) async {
    await open(t, (x) => x.count > 1 && !x.participants.any((p) => isAutomatedSender(p.email)), size: const Size(1440, 700));
    await tapAi(t);
    expect(find.text('AI đọc thư'), findsOneWidget);
    expect(find.text('Dùng bản nháp'), findsOneWidget);
    final panel = t.getRect(find.text('AI đọc thư'));
    // Thứ tự trong cuộc hội thoại: mọi thư (Container của từng thư) trước khung AI, phần trả lời sau khung AI.
    final lv = t.widget<ListView>(find.ancestor(of: find.text('AI đọc thư'), matching: find.byType(ListView)).first);
    final kids = (lv.childrenDelegate as SliverChildListDelegate).children;
    final ai = kids.indexWhere((w) => w.key is GlobalKey);
    final lastMessage = kids.lastIndexWhere((w) => w is Container);
    expect(ai, greaterThan(lastMessage));
    expect(ai, lessThan(kids.length - 1));
    final scroll = find.ancestor(of: find.text('AI đọc thư'), matching: find.byType(Scrollable)).first;
    expect(t.state<ScrollableState>(scroll).position.pixels, greaterThan(0));
    // Khung đang hiện trong màn hình.
    expect(panel.top, greaterThanOrEqualTo(0));
    expect(panel.top, lessThan(700));
  });

  testWidgets('thư tự động (no-reply): chỉ tóm tắt, ghi chú không cần trả lời, không có bản nháp / AI soạn trả lời', (t) async {
    await open(t, (x) => x.participants.any((p) => isAutomatedSender(p.email)));
    expect(find.byKey(const ValueKey('mail-ai-reply')), findsNothing);
    await tapAi(t);
    expect(find.byKey(const ValueKey('mail-ai-automated')), findsOneWidget);
    expect(find.text('Thư tự động, không cần trả lời'), findsOneWidget);
    expect(find.text('Bản nháp trả lời'), findsNothing);
    expect(find.text('Dùng bản nháp'), findsNothing);
  });
}
