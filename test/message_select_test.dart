import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/message_select.dart';

/// Chọn chữ trong tin: điện thoại bấm giữ vào chữ, máy tính kéo chuột; giữ Shift thì kéo ngang không bị tính là vuốt.
void main() {
  const text = 'Hàng cáp thép lô 12 về kho rồi nhé';

  Widget bubble({required TargetPlatform platform, required bool desktop, required VoidCallback onMore, VoidCallback? onBubbleLongPress, VoidCallback? onDoubleTap}) =>
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              onLongPress: onBubbleLongPress,
              onDoubleTap: onDoubleTap,
              child: Container(
                padding: const EdgeInsets.all(24),
                color: Colors.green.shade100,
                child: MessageTextSelection(desktop: desktop, onMore: onMore, child: const Text(text)),
              ),
            ),
          ),
        ),
      );

  testWidgets('điện thoại: bấm giữ vào chữ là chọn chữ, có Sao chép và "Thao tác khác" mở menu của tin', (t) async {
    var more = 0, menu = 0;
    await t.pumpWidget(bubble(platform: TargetPlatform.android, desktop: false, onMore: () => more++, onBubbleLongPress: () => menu++));
    await t.longPress(find.text(text));
    await t.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Thao tác khác'), findsOneWidget);
    expect(menu, 0, reason: 'bấm giữ vào chữ thì chọn chữ, không mở menu tin');
    await t.tap(find.text('Thao tác khác'));
    await t.pumpAndSettle();
    expect(more, 1);
  });

  testWidgets('điện thoại: bấm giữ phần bong bóng ngoài chữ vẫn mở menu tin', (t) async {
    var menu = 0;
    await t.pumpWidget(bubble(platform: TargetPlatform.android, desktop: false, onMore: () {}, onBubbleLongPress: () => menu++));
    final box = t.getRect(find.byType(Container).last);
    await t.longPressAt(box.topLeft + const Offset(6, 6));
    await t.pumpAndSettle();
    expect(menu, 1);
  });

  testWidgets('điện thoại: chạm đúp vào chữ vẫn thả tim (không bị chọn chữ chiếm)', (t) async {
    var hearts = 0;
    await t.pumpWidget(bubble(platform: TargetPlatform.android, desktop: false, onMore: () {}, onDoubleTap: () => hearts++));
    final c = t.getCenter(find.text(text));
    await t.tapAt(c);
    await t.pump(const Duration(milliseconds: 50));
    await t.tapAt(c);
    await t.pumpAndSettle();
    expect(hearts, 1);
  });

  testWidgets('máy tính: nháy phải vào chữ mở menu tin', (t) async {
    var more = 0;
    await t.pumpWidget(bubble(platform: TargetPlatform.linux, desktop: true, onMore: () => more++));
    final g = await t.startGesture(t.getCenter(find.text(text)), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g.up();
    await t.pumpAndSettle();
    expect(more, 1);
  });

  testWidgets('giữ Shift: kéo ngang không bị tính là vuốt', (t) async {
    var swiped = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RawGestureDetector(
            gestures: {
              SwipeDragRecognizer: GestureRecognizerFactoryWithHandlers<SwipeDragRecognizer>(
                SwipeDragRecognizer.new,
                (r) => r.onUpdate = (_) => swiped++,
              ),
            },
            child: const SizedBox(width: 300, height: 80, child: ColoredBox(color: Colors.white)),
          ),
        ),
      ),
    ));
    final c = t.getCenter(find.byType(SizedBox).last);
    await t.dragFrom(c, const Offset(-120, 0), kind: PointerDeviceKind.mouse);
    expect(swiped, greaterThan(0), reason: 'không giữ Shift: vẫn vuốt như cũ');
    swiped = 0;
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.dragFrom(c, const Offset(-120, 0), kind: PointerDeviceKind.mouse);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(swiped, 0);
  });

  // Giống cấu trúc thật: vuốt trả lời (SwipeDragRecognizer) > bong bóng (bấm giữ mở menu) > chữ (MessageTextSelection).
  Widget swipeBubble(TargetPlatform platform, {required VoidCallback onSwipe, VoidCallback? onMenu}) => MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: Center(
            child: RawGestureDetector(
              gestures: {
                SwipeDragRecognizer: GestureRecognizerFactoryWithHandlers<SwipeDragRecognizer>(
                  SwipeDragRecognizer.new,
                  (r) => r.onEnd = (_) => onSwipe(),
                ),
              },
              child: GestureDetector(
                onLongPress: onMenu,
                child: Container(
                  width: 320,
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: MessageTextSelection(desktop: false, onMore: () {}, child: const Text(text)),
                ),
              ),
            ),
          ),
        ),
      );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('điện thoại (${platform.name}): vuốt ngang bằng tay trên CHỮ của tin vẫn là vuốt trả lời', (t) async {
      var swiped = 0;
      await t.pumpWidget(swipeBubble(platform, onSwipe: () => swiped++));
      await t.dragFrom(t.getCenter(find.text(text)), const Offset(-120, 0), kind: PointerDeviceKind.touch);
      await t.pumpAndSettle();
      expect(swiped, 1);
      await t.dragFrom(t.getCenter(find.text(text)), const Offset(120, 0), kind: PointerDeviceKind.touch);
      await t.pumpAndSettle();
      expect(swiped, 2);
    });

    testWidgets('điện thoại (${platform.name}): bấm giữ chọn chữ; bỏ chọn rồi lại vuốt được', (t) async {
      var swiped = 0;
      await t.pumpWidget(swipeBubble(platform, onSwipe: () => swiped++));
      await t.longPress(find.text(text));
      await t.pumpAndSettle();
      expect(find.text('Thao tác khác'), findsOneWidget);
      // Chạm ra ngoài: bỏ chọn, tin trở lại bình thường.
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text('Thao tác khác'), findsNothing);
      await t.dragFrom(t.getCenter(find.text(text)), const Offset(-120, 0), kind: PointerDeviceKind.touch);
      await t.pumpAndSettle();
      expect(swiped, 1);
    });
  }
}
