import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/drive/marquee.dart';

void main() {
  testWidgets('Khung quét chọn khớp con trỏ, kể cả khi danh sách đã cuộn và bố cục dịch xuống giữa lúc kéo', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sc = ScrollController();
    final bar = ValueNotifier(false); // như thanh "Đã chọn N" hiện ra phía trên khi bắt đầu chọn
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(left: 300, top: 120),
          child: ValueListenableBuilder<bool>(
            valueListenable: bar,
            builder: (_, on, _) => Column(children: [
              if (on) const SizedBox(height: 60),
              Expanded(
                child: DriveMarquee(
                  keys: const {},
                  controller: sc,
                  color: Colors.blue,
                  selected: () => {},
                  onSelect: (_) {},
                  onBlankClick: () {},
                  child: ListView.builder(controller: sc, itemCount: 100, itemBuilder: (_, i) => SizedBox(height: 48, child: Text('row $i'))),
                ),
              ),
            ]),
          ),
        ),
      ),
    ));
    sc.jumpTo(200);
    await tester.pump();
    const a = Offset(400, 300), b = Offset(700, 500);
    final g = await tester.startGesture(a, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    bar.value = true; // bố cục dịch xuống 60 px sau khi nhấn
    await tester.pump();
    await g.moveTo(a + const Offset(20, 20));
    await g.moveTo(b);
    await tester.pump();
    final r = tester.getRect(find.descendant(of: find.byType(DriveMarquee), matching: find.byType(DecoratedBox)).last);
    // Góc kéo luôn ở đúng con trỏ; góc bắt đầu đi theo nội dung (dịch xuống cùng danh sách).
    expect(r.bottomRight, b);
    expect(r.topLeft, a + const Offset(0, 60));
    await g.up();
  });
}
