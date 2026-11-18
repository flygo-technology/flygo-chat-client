// Khung "AI đọc thư" nằm ở cuối cuộc hội thoại (sau thư cuối, trên nút Trả lời), bấm AI thì cuộn xuống tới nó;
// thư tự động (no-reply, cảnh báo) chỉ có tóm tắt + việc cần làm, kèm ghi chú "Thư tự động, không cần trả lời".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/mail/thread_view.dart';

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

  test('địa chỉ không nhận trả lời (hẹp hơn thư tự động)', () {
    for (final e in ['no-reply@bank.example', 'noreply@x.vn', 'google-workspace-alerts-noreply@google.com', 'mailer-daemon@googlemail.com', 'donotreply@x.vn']) {
      expect(isNoReplySender(e), isTrue, reason: e);
    }
    // Thông báo / bản tin từ địa chỉ thật: vẫn trả lời được (chỉ không có nháp AI).
    for (final e in ['notifications@github.com', 'alerts@x.vn', 'newsletter@shop.vn', 'jason.jia@hpmont.com']) {
      expect(isNoReplySender(e), isFalse, reason: e);
    }
  });

  testWidgets('thư từ no-reply: không có Trả lời / Trả lời tất cả (nút, menu, phím r a), vẫn Chuyển tiếp', (t) async {
    await open(t, (x) => x.participants.any((p) => isNoReplySender(p.email)));
    expect(find.widgetWithText(OutlinedButton, 'Trả lời'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Chuyển tiếp'), findsOneWidget);
    expect(find.byTooltip('Trả lời'), findsNothing);
    expect(find.byKey(const ValueKey('mail-ai-reply-ask')), findsNothing);
    // Phím r / a đi qua ThreadViewState.reply: báo, không mở khung trả lời.
    t.state<ThreadViewState>(find.byType(ThreadView)).reply('reply');
    await t.pump();
    expect(find.text('Thư tự động từ địa chỉ không nhận trả lời, chỉ chuyển tiếp được'), findsOneWidget);
  });

  testWidgets('dặn AI trước khi soạn: ô dưới nút AI soạn trả lời, nội dung dặn vào bản nháp', (t) async {
    await open(t, (x) => x.count > 1 && !x.participants.any((p) => isAutomatedSender(p.email)));
    final ask = find.byKey(const ValueKey('mail-ai-reply-ask'));
    await t.ensureVisible(ask);
    await t.enterText(ask, 'đồng ý, hẹn gửi báo giá thứ Hai');
    await t.tap(find.byKey(const ValueKey('mail-ai-reply')));
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // Bản nháp AI (demo: 'Về nội dung "…": <lời dặn>.') đã vào khung trả lời.
    expect(find.textContaining('Về nội dung', findRichText: true), findsWidgets);
  });
}
