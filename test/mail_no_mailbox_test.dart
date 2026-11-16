import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/api.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';

class _NoMailbox extends DemoMailApi {
  @override
  Future<MailMe> me() async => throw MailException(404, 'Bạn chưa có hộp thư nào');
}

class _Down extends DemoMailApi {
  @override
  Future<MailMe> me() async => throw MailException(502, 'Máy chủ thư trả lỗi 502');
}

Future<void> _open(WidgetTester t, MailApi api) async {
  final store = MailStore(api);
  await t.pumpWidget(MaterialApp(home: MailHome(store: store, title: 'Mail')));
  await store.start();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('404 /me: báo chưa có hộp thư, không phải lỗi kết nối', (t) async {
    await _open(t, _NoMailbox());
    expect(find.text('Bạn chưa có hộp thư nào'), findsOneWidget);
    expect(find.text('Nhờ quản trị tạo hộp thư cho bạn.'), findsOneWidget);
    expect(find.textContaining('Không kết nối được máy chủ thư'), findsNothing);
    expect(find.text('Thử lại'), findsOneWidget);
    // không có AppState/Flygo ID: không hiện nút quản trị
    expect(find.text('Quản trị Thư'), findsNothing);
  });

  testWidgets('lỗi khác vẫn là lỗi kết nối', (t) async {
    await _open(t, _Down());
    expect(find.textContaining('Không kết nối được máy chủ thư'), findsOneWidget);
    expect(find.text('Bạn chưa có hộp thư nào'), findsNothing);
  });
}
