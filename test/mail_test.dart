import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart' show isMailDemo;
import 'package:flygo_chat/ui/mail/compose.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/html_view.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/rich.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/mail/widgets.dart';
import 'package:flygo_chat/ui/todo/model.dart';

void main() {
  test('chế độ demo theo manifest', () {
    MiniApp app(Map<String, dynamic> j) => MiniApp.fromJson({'id': 'vn.flygo.mail', 'name': 'Mail', ...j});
    expect(isMailDemo(app({'base_url': 'https://mail.example.com', 'features': {'demo': true}})), isTrue);
    expect(isMailDemo(app({'base_url': 'demo:'})), isTrue);
    expect(isMailDemo(app({'base_url': 'https://mail.example.com'})), isFalse);
  });

  group('MailQuery', () {
    test('parse và build giữ nguyên toán tử', () {
      final q = MailQuery.parse('from:"Thu Hà" has:attachment hợp đồng is:unread newer_than:7d label:Kế');
      expect(q.from, 'Thu Hà');
      expect(q.attachment, isTrue);
      expect(q.unread, isTrue);
      expect(q.within, '7d');
      expect(q.inBox, 'label:Kế');
      expect(q.words, 'hợp đồng');
      expect(MailQuery.parse(q.build()).build(), q.build());
    });
  });

  group('HTML', () {
    test('composeHtml: định dạng, danh sách, trích dẫn, thoát ký tự', () {
      final h = composeHtml([
        TRun('Chào '),
        TRun('chị', const TFmt(b: true)),
        TRun(' <Hà> '),
        TRun('đỏ', const TFmt(fg: 'red')),
        TRun(' '),
        TRun('web', const TFmt(a: 'https://example.com/?a=1&b="2"')),
        TRun('\n• một\n• hai\n1. ba\n2. bốn\n> trích\nhết'),
      ]);
      expect(h, contains('<b>chị</b>'));
      expect(h, contains('&lt;Hà&gt;'));
      expect(h, contains('<span style="color:#c5221f">đỏ</span>'));
      expect(h, contains('<a href="https://example.com/?a=1&amp;b=&quot;2&quot;">web</a>'));
      expect(h, contains('<ul><li>một</li><li>hai</li></ul><ol><li>ba</li><li>bốn</li></ol>'));
      expect(h, contains('<blockquote'));
      expect(h, contains('<div>trích</div></blockquote><div>hết</div>'));
    });
    test('composeText: bản chữ thuần kèm theo', () {
      final t = composeText([TRun('Xem '), TRun('đây', const TFmt(a: 'https://example.com')), TRun('\n• một\n2. hai\n> trích')]);
      expect(t, 'Xem đây <https://example.com>\n- một\n2. hai\n> trích');
    });
    test('htmlToRuns: dán giữ định dạng cơ bản', () {
      final r = htmlToRuns('<meta charset="utf-8"><p>A <strong>B</strong> <span style="color: rgb(197, 34, 31)">C</span> <a href="https://x.vn">D</a></p>'
          '<ul><li>một</li><li>hai</li></ul><ol><li>ba</li></ol><blockquote>trích</blockquote><script>x</script>');
      final text = r.map((e) => e.x).join();
      expect(text, 'A B C D\n• một\n• hai\n1. ba\n> trích');
      expect(r.firstWhere((e) => e.x == 'B').f.b, isTrue);
      expect(r.firstWhere((e) => e.x == 'C').f.fg, 'red');
      expect(r.firstWhere((e) => e.x == 'D').f.a, 'https://x.vn');
      // Đọc lại HTML của chính khung soạn ra đúng chữ ban đầu.
      final src = [TRun('Đoạn '), TRun('đậm', const TFmt(b: true)), TRun('\n• một\n1. hai\n> trích')];
      expect(htmlToRuns(composeHtml(src)).map((e) => e.x).join(), 'Đoạn đậm\n• một\n1. hai\n> trích');
    });
    test('MailRichController: Enter nối tiếp danh sách, Enter ở mục trống thì thoát', () {
      final c = MailRichController([TRun('1. một')]);
      String type(String s) {
        final at = c.selection.isValid ? c.selection.start : c.text.length;
        c.value = TextEditingValue(text: c.text.replaceRange(at, at, s), selection: TextSelection.collapsed(offset: at + s.length));
        return c.body;
      }

      c.selection = TextSelection.collapsed(offset: c.text.length);
      expect(type('\n'), '1. một\n2. ');
      expect(type('hai'), '1. một\n2. hai');
      type('\n');
      expect(type('\n'), '1. một\n2. hai\n');
      c.setLineKind('ul');
      expect(c.body, '1. một\n2. hai\n• ');
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 10);
      c.setLineKind('quote');
      expect(c.body, '> một\n> hai\n• ');
      c.setLineKind('quote');
      expect(c.body, 'một\nhai\n• ');
    });
    test('htmlToText bỏ thẻ, giữ xuống dòng', () {
      expect(htmlToText('<p>A <b>B</b></p><p>C<br>D</p><style>x{}</style>'), 'A B\nC\nD');
    });
  });

  test('ngày trong danh sách', () {
    final now = DateTime(2026, 11, 15, 12);
    expect(fmtListDate(DateTime(2026, 11, 15, 9, 5), now), '09:05');
    expect(fmtListDate(DateTime(2026, 3, 2), now), '2 thg 3');
    expect(fmtListDate(DateTime(2025, 3, 2), now), '02/03/2025');
  });

  group('DemoMailApi + MailStore', () {
    test('hộp thư đến, tab, tìm kiếm', () async {
      final api = DemoMailApi();
      final inbox = await api.list(box: 'inbox', category: 'primary');
      expect(inbox.items, isNotEmpty);
      expect(inbox.items.every((t) => t.box == 'inbox' && t.category == 'primary'), isTrue);
      final promo = await api.list(box: 'inbox', category: 'promo');
      expect(promo.items.length, 3);
      final s = await api.list(q: 'has:attachment hợp đồng');
      expect(s.items.map((t) => t.subject), contains('Hợp đồng vận chuyển quý I/2027'));
      expect((await api.list(box: 'drafts')).items.single.draft, isTrue);
    });

    test('chỉ xem: không đổi trạng thái, mở thư không đánh dấu đã đọc', () async {
      final store = MailStore(_ReadOnlyDemo());
      await store.start();
      expect(store.readOnly, isTrue);
      final t = store.items.firstWhere((x) => x.unread);
      await expectLater(store.act(MailAction.archive, [t.id]), throwsA(isA<Exception>()));
      final th = await store.openThread(t.id);
      expect(th.summary.unread, isTrue);
    });

    test('lưu trữ rồi hoàn tác', () async {
      final store = MailStore(DemoMailApi());
      await store.start();
      final first = store.items.first;
      final n = store.items.length;
      final undo = await store.act(MailAction.archive, [first.id]);
      expect(store.items.length, n - 1);
      expect(store.items.any((t) => t.id == first.id), isFalse);
      await undo!();
      expect(store.items.any((t) => t.id == first.id), isTrue);
    });

    test('nhãn: gắn, lọc theo nhãn, gỡ', () async {
      final store = MailStore(DemoMailApi());
      await store.start();
      final l = await store.createLabel('Gấp', 0xFFD93025);
      final id = store.items.first.id;
      await store.apply([id], MailChange(addLabels: [l.id]));
      await store.open(MailView.label(l.id));
      expect(store.items.single.id, id);
      await store.apply([id], MailChange(removeLabels: [l.id]));
      expect(store.items, isEmpty);
    });

    test('gửi trả lời nối vào cuộc hội thoại, đọc thư đánh dấu đã đọc', () async {
      final api = DemoMailApi();
      final store = MailStore(api);
      await store.start();
      final t = store.items.firstWhere((x) => x.unread);
      final th = await store.openThread(t.id);
      expect(th.summary.unread, isFalse);
      final args = replyArgs('all', th, th.messages.last, DemoMailApi.user.email);
      expect(args.subject.startsWith('Re: '), isTrue);
      await api.send(MailDraft(to: args.to, cc: args.cc, subject: args.subject, html: '<p>Ok</p>', threadId: args.threadId));
      expect((await api.thread(t.id)).messages.length, th.messages.length + 1);
    });

    test('bản nháp: lưu, mở lại, gửi thì xoá nháp', () async {
      final api = DemoMailApi();
      final id = await api.saveDraft(MailDraft(to: const [MailPerson('a@b.example')], subject: 'Thử', html: '<div>xin chào</div>'));
      final th = await api.thread(id);
      final args = draftArgs(th);
      expect(args.body, 'xin chào');
      await api.send(MailDraft(to: args.to, subject: args.subject, html: '<div>xin chào</div>'), draftId: id);
      expect((await api.list(box: 'drafts')).items.where((t) => t.id == id), isEmpty);
    });
  });
}

class _ReadOnlyDemo extends DemoMailApi {
  @override
  Future<MailMe> me() async => const MailMe(DemoMailApi.user, access: 'read');
}
