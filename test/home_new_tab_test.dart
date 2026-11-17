// Trang chủ máy tính: bấm ô ứng dụng luôn mở tab mới; đã có tab mở từ ô đó thì chuyển sang (Sếp, 2026-11-17).
// Biểu tượng app Lịch: trang lịch vẽ bằng widget, số ngày hôm nay.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/desk_tabs.dart';
import 'package:flygo_chat/ui/home_page.dart' show AppTileIcon;
import 'package:flygo_chat/ui/mini_app_view.dart';
import 'package:flygo_chat/ui/theme.dart';

void main() {
  test('bấm ô: chuyển sang tab đã mở từ ô đó, chưa có thì mở tab mới', () {
    final home = DeskTab('launcher'), chat = DeskTab('chat'), lich = DeskTab('launcher');
    final tabs = [chat, home, lich];
    final origin = {lich.id: 'Lịch'};
    expect(homeTapExisting(tabs, home, 'Lịch', origin), 2);
    expect(homeTapExisting(tabs, home, 'Drive', origin), -1);
    // Chính tab đó bấm lại ô của nó: không tự chuyển sang mình (mở tab mới).
    expect(homeTapExisting(tabs, lich, 'Lịch', origin), -1);
  });

  test('tab mới thành tab ứng dụng; ứng dụng đã có tab thì dùng tab đó', () {
    final contacts = DeskTab('app', arg: 'contacts'), fresh = DeskTab('launcher');
    final tabs = [DeskTab('chat'), contacts, fresh];
    expect(homeLaunchExisting(tabs, fresh, 'app', 'contacts'), 1);
    expect(homeLaunchExisting(tabs, fresh, 'app', 'calls'), -1);
    expect(homeLaunchExisting(tabs, fresh, 'chat', null), 0);
    expect(homeLaunchExisting(tabs, fresh, 'launcher', null), -1);
  });

  testWidgets('biểu tượng Lịch: thứ + số ngày hôm nay, không dùng emoji', (t) async {
    await t.pumpWidget(const MaterialApp(home: Center(child: CalendarAppGlyph(size: 34))));
    final now = DateTime.now();
    expect(find.byKey(const ValueKey('calendar-app-glyph')), findsOneWidget);
    expect(find.text('${now.day}'), findsOneWidget);
    expect(find.text(['THỨ HAI', 'THỨ BA', 'THỨ TƯ', 'THỨ NĂM', 'THỨ SÁU', 'THỨ BẢY', 'CN'][now.weekday - 1]), findsOneWidget);
    expect(find.text('📅'), findsNothing);
  });

  // Ảnh (chạy tay): ICON_OUT=<thư mục> flutter test test/home_new_tab_test.dart
  final out = Platform.environment['ICON_OUT'];
  for (final b in Brightness.values) {
    testWidgets('ảnh ô Lịch cạnh các ô khác (${b.name})', (t) async {
      if (out == null) return;
      await t.runAsync(() async {
        final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
        for (final fam in ['Roboto', 'Noto Sans']) {
          final l = FontLoader(fam);
          for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
            if (File('$dir/$f').existsSync()) l.addFont(Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())));
          }
          await l.load();
        }
        final m = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
        await m.load();
      });
      t.view.physicalSize = const Size(1040, 360);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      Widget cell(Widget icon, Color c, String label) => SizedBox(
          width: 104,
          child: Column(mainAxisSize: MainAxisSize.min, children: [AppTileIcon(icon: icon, color: c), const SizedBox(height: 8), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))]));
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: Builder(
          builder: (c) => Scaffold(
            backgroundColor: Pal.of(c).bg,
            body: Center(
              child: RepaintBoundary(
                key: const ValueKey('shot'),
                child: Container(
                  color: Pal.of(c).bg,
                  padding: const EdgeInsets.all(12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    cell(const Icon(Icons.mail_rounded, color: Colors.white, size: 30), const Color(0xFF3D7BF0), 'Mail'),
                    cell(const Icon(Icons.folder_rounded, color: Colors.white, size: 30), const Color(0xFF2563EB), 'Drive'),
                    cell(const CalendarAppGlyph(size: 34), kCalTileColor, 'Lịch'),
                    cell(const Icon(Icons.view_kanban_rounded, color: Colors.white, size: 30), const Color(0xFF5B4BD8), 'Làm việc nhóm'),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pump();
      await t.runAsync(() async {
        final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(out).createSync(recursive: true);
        await File('$out/lich-icon-app-${b.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    });
  }
}
