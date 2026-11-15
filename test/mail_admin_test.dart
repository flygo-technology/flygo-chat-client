import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/ui/mail/admin_api.dart';
import 'package:flygo_chat/ui/mail/admin_page.dart';
import 'package:flygo_chat/ui/mail/api.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/mail/switcher.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// FlygoId giả: vé cố định, không gọi mạng.
class _Id extends FlygoId {
  _Id() : super(base: 'https://id.example.invalid', chatToken: 't');
  @override
  Future<String> ticket(String audience, {String? browser, bool refresh = false}) async => 'TICKET';
}

void main() {
  group('MailMe', () {
    test('boxes từ máy chủ mới', () {
      final m = MailMe.fromJson({
        'email': 'hotro@example.com',
        'name': 'Hỗ trợ',
        'access': 'send',
        'admin': true,
        'user': {'email': 'khoa@example.com', 'name': 'Khoa'},
        'mailboxes': ['khoa@example.com', 'hotro@example.com'],
        'boxes': [
          {'id': 'khoa@example.com', 'access': 'admin', 'via': 'owner', 'unread': 2},
          {'id': 'HOTRO@example.com', 'name': 'Hỗ trợ', 'access': 'send', 'via': 'member', 'kind': 'shared', 'unread': 5},
        ],
      });
      expect(m.admin, isTrue);
      expect(m.me.email, 'khoa@example.com');
      expect(m.boxes.map((b) => b.id), ['khoa@example.com', 'hotro@example.com']);
      expect(m.boxes[1].shared, isTrue);
      expect(m.boxes[1].unread, 5);
    });

    test('máy chủ cũ (chỉ mailbox_access) vẫn dựng được danh sách', () {
      final m = MailMe.fromJson({
        'email': 'khoa@example.com',
        'mailboxes': ['khoa@example.com', 'hotro@example.com'],
        'mailbox_access': {'khoa@example.com': 'admin', 'hotro@example.com': 'read'},
        'user': {'email': 'khoa@example.com'},
      });
      expect([for (final b in m.boxes) '${b.id}:${b.access}:${b.via}'], ['khoa@example.com:admin:owner', 'hotro@example.com:read:member']);
      expect(m.admin, isFalse);
    });
  });

  test('đổi hộp thư: dữ liệu và quyền theo hộp mới', () async {
    final store = MailStore(DemoMailApi());
    await store.start();
    expect(store.me!.person.email, DemoMailApi.user.email);
    expect(store.items.length, greaterThan(5));
    await store.switchMailbox('ketoan@example.com');
    expect(store.api.mailbox, 'ketoan@example.com');
    expect(store.me!.person.email, 'ketoan@example.com');
    expect(store.readOnly, isTrue);
    expect(store.items.map((t) => t.subject), contains('Đối chiếu công nợ tháng 10'));
    await store.switchMailbox('hotro@example.com');
    expect(store.readOnly, isFalse);
    expect(store.items.length, 3);
  });

  test('AI demo: tóm tắt + nháp, chỉ xem thì không có nháp ở thanh trên', () async {
    final api = DemoMailApi();
    final store = MailStore(api);
    await store.start();
    final t = store.items.first;
    final r = await api.ai(t.id);
    expect(r.summary, isNotEmpty);
    expect(r.draft, contains('Trân trọng'));
    final r2 = await api.ai(t.id, instruction: 'đồng ý, hẹn thứ Hai gửi bản ký', tone: 'casual');
    expect(r2.draft, contains('đồng ý, hẹn thứ Hai gửi bản ký'));
    expect(r2.draft, contains('Thân,'));
  });

  group('DemoMailAdminApi', () {
    test('tạo / đổi quyền / bí danh / tắt / xoá ghi nhật ký', () async {
      final a = DemoMailAdminApi();
      final n0 = (await a.audit()).length;
      await a.createMailbox('baohanh@example.com', name: 'Bảo hành', kind: 'shared', members: {'long@example.com': 'send'});
      await expectLater(a.createMailbox('baohanh@example.com'), throwsA(isA<MailException>()));
      await a.setMembers('baohanh@example.com', {'long@example.com': 'read'});
      await a.saveAlias(MaAlias('warranty@example.com', 'baohanh@example.com'));
      await a.updateMailbox('baohanh@example.com', {'status': 'disabled'});
      var s = await a.load();
      expect(s.box('baohanh@example.com')!.members['long@example.com'], 'read');
      expect(s.box('baohanh@example.com')!.disabled, isTrue);
      expect(s.aliasesOf('baohanh@example.com').single.address, 'warranty@example.com');
      await a.deleteMailbox('baohanh@example.com');
      s = await a.load();
      expect(s.box('baohanh@example.com'), isNull);
      expect(s.aliases.any((x) => x.target == 'baohanh@example.com'), isFalse);
      final log = await a.audit();
      expect(log.length, n0 + 5);
      expect(log.first.action, 'mailbox.delete');
      expect((await a.audit(q: 'warranty')).single.action, 'alias.create');
    });
  });

  group('HttpMailAdminApi', () {
    test('đường dẫn, vé Bearer, dữ liệu trả về', () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path} ${req.headers['Authorization']}');
        if (req.url.path.endsWith('/state')) {
          return http.Response(
              jsonEncode({
                'domains': [
                  {'name': 'cf.example.com', 'status': 'active', 'dns': {'mx': true, 'spf': true, 'dkim': true, 'dmarc': true}, 'catch_all': 'reject', 'primary': true}
                ],
                'mailboxes': [
                  {'id': 'ba@cf.example.com', 'name': 'Ba', 'kind': 'personal', 'status': 'active', 'members': {}, 'used_mb': 1.5, 'sent_today': 2, 'limit_day': 300}
                ],
                'aliases': [],
                'rules': [],
                'limits': {'per_hour': 20, 'per_day': 100, 'external': true},
                'sent_today': 2,
                'sent_month': null,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (req.url.path.endsWith('/members')) return http.Response.bytes(utf8.encode('{"error":"Email không hợp lệ: x"}'), 400);
        return http.Response('{"ok":true}', 200);
      });
      final api = HttpMailApi(base: 'https://inbox.example.com/', id: _Id(), client: client).adminApi();
      final s = await api.load();
      expect(s.domains.single.status, 'active');
      expect(s.mailboxes.single.limitDay, 300);
      expect(s.monthSent, isNull);
      await api.updateMailbox('ba@cf.example.com', {'status': 'disabled'});
      await expectLater(api.setMembers('ba@cf.example.com', {'x': 'read'}), throwsA(isA<MailException>().having((e) => e.message, 'message', contains('không hợp lệ'))));
      expect(calls, [
        'GET /mail/api/admin/state Bearer TICKET',
        'PATCH /mail/api/admin/mailboxes/ba%40cf.example.com Bearer TICKET',
        'PUT /mail/api/admin/mailboxes/ba%40cf.example.com/members Bearer TICKET',
      ]);
    });

    test('AI gọi /mail/api/ai với X-Mailbox', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'summary': 'S', 'actions': ['A'], 'draft': 'D', 'model': 'm'}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final api = HttpMailApi(base: 'https://inbox.example.com', id: _Id(), mailbox: 'hotro@example.com', client: client);
      final r = await api.ai('t1', instruction: 'ok', tone: 'short');
      expect(seen.url.path, '/mail/api/ai');
      expect(seen.headers['X-Mailbox'], 'hotro@example.com');
      expect(jsonDecode(seen.body), {'threadId': 't1', 'task': 'draft', 'instruction': 'ok', 'tone': 'short'});
      expect((r.summary, r.draft), ('S', 'D'));
      expect(r.actions, ['A']);
    });
  });

  testWidgets('bộ chọn hộp thư: nhóm theo quyền, bấm để đổi hộp', (t) async {
    final store = MailStore(DemoMailApi());
    await t.runAsync(store.start);
    var admin = 0;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: MailboxSwitcher(store: store, onClose: () {}, onAdmin: () => admin++)),
    ));
    expect(find.text('Được chia sẻ với tôi'), findsOneWidget);
    expect(find.text('Hộp khác (quyền quản trị)'), findsOneWidget);
    expect(find.text('Chỉ xem'), findsOneWidget);
    await t.tap(find.text('Quản trị Thư'));
    expect(admin, 1);
    await t.tap(find.text('Phòng Kế toán'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(store.me!.person.email, 'ketoan@example.com');
  });

  testWidgets('Quản trị Thư: tạo hộp dùng chung từ hộp thoại', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final api = DemoMailAdminApi();
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: MailAdminPage(api: api)));
    await t.pumpAndSettle();
    expect(find.text('Hỗ trợ khách hàng'), findsWidgets);
    await t.tap(find.text('Tạo hộp thư').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Dùng chung').last);
    await t.enterText(find.widgetWithText(TextField, 'Địa chỉ'), 'baohanh');
    await t.enterText(find.widgetWithText(TextField, 'Tên hiển thị'), 'Bảo hành');
    await t.tap(find.text('Tạo'));
    await t.pumpAndSettle();
    final s = await api.load();
    expect(s.box('baohanh@example.com')?.kind, 'shared');
    expect(find.text('Bảo hành'), findsOneWidget);
  });
}
