import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/three_finger_swipe.dart';

/// Vuốt 3 ngón từ dưới lên mở bảng chọn máy chủ; 1–2 ngón (cuộn, chụm phóng to) không mở.
void main() {
  Future<int> swipe(WidgetTester t, int fingers, {double dy = -120, double dx = 0}) async {
    var n = 0;
    await t.pumpWidget(MaterialApp(home: ThreeFingerSwipe(onSwipe: () => n++, child: ListView(children: [for (var i = 0; i < 40; i++) Text('dòng $i')]))));
    final gs = <TestGesture>[];
    for (var i = 0; i < fingers; i++) {
      gs.add(await t.startGesture(Offset(100.0 + i * 60, 500), pointer: 10 + i));
    }
    for (var step = 1; step <= 6; step++) {
      for (final g in gs) {
        await g.moveBy(Offset(dx / 6, dy / 6));
      }
      await t.pump(const Duration(milliseconds: 16));
    }
    for (final g in gs) {
      await g.up();
    }
    await t.pumpAndSettle();
    return n;
  }

  testWidgets('3 ngón vuốt lên: mở đúng một lần', (t) async => expect(await swipe(t, 3), 1));
  testWidgets('1 ngón (cuộn) và 2 ngón (chụm phóng to): không mở', (t) async {
    expect(await swipe(t, 1), 0);
    expect(await swipe(t, 2), 0);
  });
  testWidgets('3 ngón nhưng đi xuống, đi ngắn hoặc lệch ngang nhiều: không mở', (t) async {
    expect(await swipe(t, 3, dy: 120), 0);
    expect(await swipe(t, 3, dy: -30), 0);
    expect(await swipe(t, 3, dy: -120, dx: 300), 0);
  });
}
