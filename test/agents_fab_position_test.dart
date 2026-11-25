// Nút ＋ của tab Agents nằm góc dưới phải: máy tính / ô chia cách đáy 16 px, điện thoại ngay trên thanh tab nổi;
// ô thấp thì nút vẫn bám đáy, không lên sát đầu vùng (lỗi build 529).
// Ảnh xem trước (chạy tay): FAB_OUT=<thư mục> flutter test test/agents_fab_position_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/agents_view.dart';
import 'package:flygo_chat/ui/common.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

AppState _app() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba'});
  app.users['bot'] = MmUser({'id': 'bot', 'username': 'jessica', 'is_bot': true, 'bot_description': '[flygo-agent engine=claude]'});
  app.noteMyBot('bot');
  app.setMyAgents({'bot'});
  return app;
}

/// Danh sách Agents trong một ô rộng [w], cao [h] (máy tính: cột trái / ô chia; điện thoại: cả màn hình).
Widget _pane(AppState app, double w, double h, double bottomPadding, {Brightness b = Brightness.light, Key? key}) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: w,
                height: h,
                child: AgentsView(onOpen: (_) {}, bottomPadding: bottomPadding, header: const SizedBox(height: 8)),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  Future<void> size(WidgetTester t, Size s) async {
    t.view.physicalSize = s;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('desktop split view: 16 px from the bottom-right corner (empty list)', (t) async {
    await size(t, const Size(1200, 800));
    await t.pumpWidget(_pane(_app(), 380, 800, 16));
    await t.pump();
    final r = t.getRect(find.byType(PlusFab));
    expect(r.bottom, 800 - 16);
    expect(r.right, 380 - 16);
  });

  testWidgets('short desktop pane: the button stays at the bottom, below the tab bar, never on the header line', (t) async {
    await size(t, const Size(1200, 800));
    await t.pumpWidget(_pane(_app(), 380, 220, 16));
    await t.pump();
    final r = t.getRect(find.byType(PlusFab));
    final tabs = t.getRect(find.byType(TabBar));
    expect(r.bottom, 220 - 16);
    expect(r.top, greaterThan(tabs.bottom));
  });

  testWidgets('phone: just above the floating tab bar, as before', (t) async {
    await size(t, const Size(390, 844));
    final app = _app();
    await t.pumpWidget(_pane(app, 390, 844, 84 + kTabBarLift));
    await t.pump();
    final r = t.getRect(find.byType(PlusFab));
    expect(r.bottom, 844 - (10 + kTabBarLift + 88));
    expect(r.right, 390 - 20);
  });

  final out = Platform.environment['FAB_OUT'];
  for (final dark in [false, true]) {
    for (final (name, w, h, pad) in [('desktop', 380.0, 800.0, 16.0), ('desktop-short', 380.0, 260.0, 16.0), ('phone', 390.0, 844.0, 98.0)]) {
      testWidgets('ảnh nút + $name ${dark ? 'dark' : 'light'}', (t) async {
        if (out == null) return;
        final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
        await t.runAsync(() async {
          for (final (fam, files) in [
            ('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']),
            ('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']),
            ('MaterialIcons', ['MaterialIcons-Regular.otf'])
          ]) {
            final l = FontLoader(fam);
            for (final f in files) {
              l.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
            }
            await l.load();
          }
        });
        t.view.physicalSize = Size(w, h) * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(_pane(_app(), w, h, pad, b: dark ? Brightness.dark : Brightness.light, key: key));
        await t.pump(const Duration(milliseconds: 300));
        await t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
