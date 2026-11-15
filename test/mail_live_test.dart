import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/live.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/mail/switcher.dart';
import 'package:flygo_chat/ui/theme.dart';

/// Ống WebSocket giả: test đẩy tin vào [push], đóng bằng [drop] (kèm mã đóng).
class _Pipe {
  final ctl = StreamController<dynamic>();
  final sent = <String>[];
  int? code;
  MailLiveSocket get socket => MailLiveSocket(ctl.stream, sent.add, () {
        if (!ctl.isClosed) ctl.close();
      }, () => code);
  void push(String s) => ctl.add(s);
  void drop([int? c]) {
    code = c;
    ctl.close();
  }
}

/// Thư mẫu + đếm số lần tải lại, có thể thêm hộp thư (giả lập quản trị vừa tạo hộp).
class _Api extends DemoMailApi {
  int lists = 0, mes = 0;
  final extra = <MailboxInfo>[];
  @override
  Future<MailMe> me() async {
    mes++;
    final m = await super.me();
    return MailMe(m.person, mailboxes: [...m.mailboxes, for (final b in extra) b.id], boxes: [...m.boxes, ...extra], features: m.features, access: m.access, user: m.user, admin: m.admin);
  }

  @override
  Future<MailPage> list({String box = 'inbox', String? label, String? category, String? q, int page = 1, int size = 50}) {
    lists++;
    return super.list(box: box, label: label, category: category, q: q, page: page, size: size);
  }

  @override
  Future<MailLiveTarget?> liveTarget({bool refresh = false}) async => MailLiveTarget(Uri.parse('wss://mail.example.test/mail/api/live'), const {});
}

void main() {
  setUp(() => MailLive.unit = const Duration(milliseconds: 10));
  tearDown(() => MailLive.unit = const Duration(seconds: 1));

  test('kênh realtime: hello, tin thư, đóng 4001 thì nối lại ngay, rớt thì tải lại định kỳ', () async {
    final pipes = <_Pipe>[];
    final events = <MailLiveEvent>[];
    final live = MailLive(
      target: ({refresh = false}) async => MailLiveTarget(Uri.parse('wss://x.test/mail/api/live'), const {'Authorization': 'Bearer t'}),
      onEvent: events.add,
      connector: (t) async => (pipes..add(_Pipe())).last.socket,
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(pipes, hasLength(1));
    pipes[0].push('{"t":"hello"}');
    await Future<void>.delayed(Duration.zero);
    expect(live.up, isTrue);
    pipes[0].push('{"t":"mail","mailbox":"BA@x.test","kinds":["new"],"threads":["t1"]}');
    await Future<void>.delayed(Duration.zero);
    expect(events.single.type, 'mail');
    expect(events.single.mailbox, 'ba@x.test');
    expect(events.single.isNew, isTrue);
    // Danh sách hộp / quyền đổi: máy chủ báo rồi đóng 4001 → nối lại ngay, báo resync sau khi nối lại.
    pipes[0].push('{"t":"boxes"}');
    pipes[0].drop(MailLive.resyncCode);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(events.map((e) => e.type), contains('boxes'));
    expect(pipes, hasLength(2));
    pipes[1].push('{"t":"hello"}');
    await Future<void>.delayed(Duration.zero);
    expect(events.last.type, 'resync');
    // Ping giữ kết nối.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(pipes[1].sent, contains('ping'));
    // Rớt mạng (không nối lại được): chờ lâu dần, trong lúc đó màn hình tự tải lại.
    live.stop();
    final down = MailLive(
      target: ({refresh = false}) async => MailLiveTarget(Uri.parse('wss://x.test/mail/api/live'), const {}),
      onEvent: events.add,
      connector: (t) async => throw Exception('offline'),
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(events.where((e) => e.type == 'poll'), isNotEmpty);
    down.stop();
  });

  test('store: thư mới của hộp đang xem thì tải lại danh sách; hộp khác thì cập nhật số chưa đọc', () async {
    final api = _Api();
    final store = MailStore(api);
    await store.start();
    final cur = store.mailboxId, lists = api.lists, mes = api.mes;
    final opened = <Set<String>>[];
    final sub = store.remoteThreads.listen(opened.add);
    store.onLive(MailLiveEvent('mail', mailbox: cur, kinds: const ['update'], threads: const ['t1']));
    store.onLive(MailLiveEvent('mail', mailbox: cur, kinds: const ['update'], threads: const ['t2']));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(api.lists, lists + 1, reason: 'hai tin liền nhau gộp thành một lần tải');
    expect(opened.expand((s) => s), containsAll(['t1', 't2']));
    expect(api.mes, mes);
    store.onLive(const MailLiveEvent('mail', mailbox: 'hotro@example.com', kinds: ['new'], threads: ['x']));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(api.lists, lists + 1);
    expect(api.mes, mes + 1);
    // Quản trị tạo hộp thư mới ở nơi khác: bộ chọn có ngay.
    api.extra.add(const MailboxInfo('baohanh@example.com', name: 'Bảo hành', kind: 'shared', via: 'admin'));
    store.onLive(const MailLiveEvent('boxes'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(store.me!.boxes.map((b) => b.id), contains('baohanh@example.com'));
    await sub.cancel();
    store.dispose();
  });

  test('store: bị thu quyền hộp đang xem thì về hộp mặc định', () async {
    final api = _OnlyOwn();
    final store = MailStore(api);
    await store.start();
    await store.switchMailbox('hotro@example.com');
    expect(store.mailboxId, 'hotro@example.com');
    api.revoked = true;
    await store.refreshMe();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.mailbox, isNull);
    store.dispose();
  });

  testWidgets('đầu danh sách: địa chỉ hộp đang xem + "Xem hòm thư khác"; không còn nút đóng Thư', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => MailHome(store: store, title: 'Mail', ownsStore: false))),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byTooltip('Đóng Thư'), findsNothing);
    final bar = find.byKey(const ValueKey('mail-current-box'));
    expect(find.descendant(of: bar, matching: find.textContaining('khoa@example.com', findRichText: true)), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('mail-other-boxes')));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MailboxSwitcher), findsOneWidget);
    await t.tap(find.text('Hỗ trợ khách hàng'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // Hộp dùng chung, không phải của mình: ghi rõ + mức quyền.
    expect(find.descendant(of: bar, matching: find.textContaining('Hộp chung hotro@example.com', findRichText: true)), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Đọc và gửi')), findsOneWidget);
  });
}

class _OnlyOwn extends DemoMailApi {
  bool revoked = false;
  @override
  Future<MailMe> me() async {
    final m = await super.me();
    if (!revoked) return m;
    final own = m.boxes.where((b) => b.via == 'owner').toList();
    return MailMe(m.person, mailboxes: [for (final b in own) b.id], boxes: own, features: m.features, access: m.access, user: m.user, admin: m.admin);
  }
}
