// Ảnh đại diện có ảnh thật (máy chủ ảnh giả): ảnh cắt tròn khít, viền / chấm hoạt động / nút máy ảnh đúng chỗ.
// Ảnh xem trước (chạy tay): AV_OUT=<thư mục> flutter test test/avatar_round_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/common.dart';
import 'package:flygo_chat/ui/home_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

import 'support/fake_photos.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  testWidgets('ô Hồ sơ: ô tròn không viền, ảnh đại diện vừa khít', (t) async {
    final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'an', 'first_name': 'An'});
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Center(child: AppTileIcon(icon: Avatar(userId: 'me', name: 'An', size: 62, status: false), circle: true)),
      ),
    ));
    final box = t.widget<Container>(find.descendant(of: find.byType(AppTileIcon), matching: find.byType(Container)).first);
    final d = box.decoration! as BoxDecoration;
    expect(d.shape, BoxShape.circle);
    expect(d.border, isNull);
    expect(d.borderRadius, isNull);
    expect(t.getSize(find.byType(AppTileIcon)), t.getSize(find.byType(Avatar)));
  });

  testWidgets('ảnh đại diện trang Bạn / thẻ người dùng', (t) async {
    final out = Platform.environment['AV_OUT'];
    if (out == null) return;
    await t.runAsync(_fonts);
    await useFakePhotos(t);
    final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'an', 'first_name': 'Nguyễn Văn', 'last_name': 'An', 'last_picture_update': 1});
    app.users['me'] = app.me!;
    app.statuses['me'] = 'online';
    debugDisableShadows = false;
    for (final b in [Brightness.light, Brightness.dark]) {
      for (final (name, page) in [
        ('settings', Scaffold(body: ProfileView(onLogout: () {}, onSwitchServer: (_) {}))),
        ('apps-card', Scaffold(body: ListView(children: [AppsUserCard(onProfile: () {}, onSettings: () {}, onLogout: () {})]))),
        // Ô "Hồ sơ" trong nhóm Cá nhân (điện thoại): ảnh đại diện tròn trên ô tròn, không còn góc vuông lòi ra.
        (
          'profile-tile',
          Scaffold(
            body: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppTileIcon(icon: Avatar(userId: 'me', name: 'Nguyễn Văn An', size: 62, status: false), circle: true),
                const SizedBox(width: 24),
                const AppTileIcon(icon: Icon(Icons.settings_rounded, color: Colors.white, size: 30), color: Color(0xFF64748B)),
              ]),
            ),
          )
        ),
      ]) {
        t.view.physicalSize = const Size(1260, 1500);
        t.view.devicePixelRatio = 3;
        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<AppState>.value(
            value: app,
            child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: page),
          ),
        ));
        for (var i = 0; i < 5; i++) {
          await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 3);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/avatar-$name-${b.name}.png').writeAsBytes(data!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox.shrink());
      }
    }
    debugDisableShadows = true;
    t.view.reset();
  });
}
