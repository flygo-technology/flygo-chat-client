import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/desk_tabs.dart';
import 'package:flygo_chat/ui/theme.dart';

void main() {
  Future<List<DeskTab>> drag(WidgetTester tester, Offset by, {int count = 2}) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tabs = [DeskTab('chat'), DeskTab('agents'), if (count > 2) DeskTab('flows')].take(count).toList();
    final torn = <DeskTab>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Column(children: [
          DeskTabBar(
            tabs: tabs,
            current: 0,
            label: (t) => DeskTabLabel(const Icon(Icons.tab, size: 17), t.kind),
            onSelect: (_) {},
            onClose: (_) {},
            onMove: (_, _) {},
            onNew: () {},
            onTogglePin: (_) {},
            onCloseOthers: (_) {},
            onDetach: (t, _) => torn.add(t),
          ),
          const Expanded(child: SizedBox()),
        ]),
      ),
    ));
    final g = await tester.startGesture(tester.getCenter(find.text('agents')));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(by / 10);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    return torn;
  }

  testWidgets('kéo tab xuống xa thanh tab: tách ra cửa sổ mới', (tester) async {
    final torn = await drag(tester, const Offset(0, 260));
    expect(torn.map((t) => t.kind), ['agents']);
  });

  testWidgets('kéo tab ngang trong thanh tab: không tách', (tester) async {
    final torn = await drag(tester, const Offset(-150, 10));
    expect(torn, isEmpty);
  });

  test('tornOff', () {
    const bar = Rect.fromLTWH(0, 0, 1000, 42);
    expect(DeskTabBar.tornOff(bar, const Offset(300, 30)), isFalse);
    expect(DeskTabBar.tornOff(bar, const Offset(300, 120)), isTrue);
    expect(DeskTabBar.tornOff(bar, const Offset(-60, 20)), isTrue);
  });
}
