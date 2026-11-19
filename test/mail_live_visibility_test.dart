// Kênh realtime của Thư chỉ nối khi Thư đang hiện trước mắt (tab đang chọn, app đang dùng). Máy chủ không nhắn
// "📩 thư mới" cho người đang nối kênh, nên tab Thư để nền / cửa sổ thu nhỏ phải ngắt để vẫn nhận thông báo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/store.dart';

class _Host extends StatefulWidget {
  const _Host(this.store);
  final MailStore store;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int tab = 1; // 0 = tab khác, 1 = tab Thư
  void show(int i) => setState(() => tab = i);
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: IndexedStack(index: tab, children: [const Scaffold(body: Text('chat')), MailHome(store: widget.store, title: 'Mail')]),
      );
}

void main() {
  testWidgets('tab Thư để nền (IndexedStack) hoặc app ra nền: ngắt kênh realtime sau vài giây; quay lại: nối lại', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = MailStore(DemoMailApi());
    await t.pumpWidget(_Host(store));
    await t.pump(const Duration(milliseconds: 500));
    expect(store.liveStarted, isTrue);
    final host = t.state<_HostState>(find.byType(_Host));
    // Sang tab khác: vẫn nối trong 3 giây (chuyển qua lại nhanh), rồi ngắt.
    host.show(0);
    await t.pump(const Duration(seconds: 1));
    expect(store.liveStarted, isTrue);
    await t.pump(const Duration(seconds: 3));
    expect(store.liveStarted, isFalse);
    host.show(1);
    await t.pump();
    expect(store.liveStarted, isTrue);
    // App / cửa sổ ra nền (thu nhỏ, sang ứng dụng khác): ngắt; dùng lại: nối lại.
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump(const Duration(seconds: 4));
    expect(store.liveStarted, isFalse);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(store.liveStarted, isTrue);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 4));
  });
}
