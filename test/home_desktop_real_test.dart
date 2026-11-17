// Trang chủ máy tính thật (HomePage) với "Màu nền" (chạy tay): DESK_OUT=<thư mục> flutter test test/home_desktop_real_test.dart
// Chỉ để chụp ảnh: sau khi chụp, HomePage còn hẹn giờ nền (kết nối, thăm dò) nên test báo "Timer is still pending" — bỏ qua.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/config.dart' show debugIsDesktop;
import 'package:flygo_chat/data/local_store.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/home_page.dart';
import 'package:flygo_chat/ui/season/season_state.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

class _FakeApi extends MmApi {
  _FakeApi() : super('t');
  @override
  Future<dynamic> get(String p, [Map<String, String>? q]) async => throw ApiException(404, 'offline');
  @override
  Future<dynamic> post(String p, Object? body) async => throw ApiException(404, 'offline');
  @override
  Future<dynamic> put(String p, Object? body) async => throw ApiException(404, 'offline');
}

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

  for (final family in ['Roboto', 'Noto Sans']) {
    await load(family, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['DESK_OUT'];
  for (final (name, bg) in [('chua-chon', null), ('giangsinh', 'giangsinh'), ('mau-tron', 'plain:0E9F8E')]) {
    for (final b in Brightness.values) {
      testWidgets('trang chủ máy tính thật $name ${b.name}', (t) async {
        if (out == null) return;
        await t.runAsync(_fonts);
        debugIsDesktop = true;
        addTearDown(() => debugIsDesktop = null);
        SeasonState.instance.mine = {'home_bg': ?bg};
        final app = AppState('t', api: _FakeApi())
          ..me = MmUser({'id': 'me', 'username': 'nguyenvana', 'first_name': 'Nguyễn Văn', 'last_name': 'An', 'email': 'a@congty.example.vn'});
        await t.runAsync(() async => app.debugSetStore(await LocalStore.memory('home-${DateTime.now().microsecondsSinceEpoch}')));
        app.users['me'] = app.me!;
        t.view.physicalSize = const Size(1600, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<AppState>.value(
            value: app,
            child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: HomePage(onLogout: () async {}, onSwitchServer: (_) {})),
          ),
        ));
        await t.pump(const Duration(milliseconds: 300));
        // Mở tab mới (trang Mở ứng dụng).
        await t.tap(find.byIcon(Icons.add_rounded).first);
        for (var i = 0; i < 6; i++) {
          await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/real-desktop-home-$name-${b.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 2));
      });
    }
  }
}
