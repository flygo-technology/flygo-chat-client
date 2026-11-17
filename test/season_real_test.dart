// Giao diện mùa lễ trên màn hình thật (tin giả, mùa Giáng sinh giả).
// Ảnh xem trước (chạy tay): XMAS_OUT=<thư mục> flutter test test/season_real_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/common.dart' show Avatar;
import 'package:flygo_chat/ui/season/appearance_pages.dart';
import 'package:flygo_chat/ui/season/chat_appearance.dart';
import 'package:flygo_chat/ui/season/chat_wallpaper.dart';
import 'package:flygo_chat/ui/season/season.dart' show Garland;
import 'package:flygo_chat/ui/season/season_art.dart';
import 'package:flygo_chat/ui/season/season_state.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _start = DateTime(2026, 12, 20, 8).millisecondsSinceEpoch;

AppState _app() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'an', 'first_name': 'An'});
  for (final (id, name) in [('me', 'An'), ('u2', 'Bình'), ('u3', 'Chi')]) {
    app.users[id] = MmUser({'id': id, 'username': name, 'first_name': name});
  }
  app.channels['c'] = MmChannel({'id': 'c', 'type': 'O', 'display_name': 'Nhóm dự án', 'create_at': _start - 3600000});
  var i = 0;
  MmPost post(String user, String text, {Map<String, dynamic>? bubble, String root = '', List<String> react = const []}) => MmPost({
        'id': 'p${i++}',
        'channel_id': 'c',
        'user_id': user,
        'message': text,
        'root_id': root,
        'create_at': _start + i * 60000,
        'props': {'flygo_bubble': ?bubble},
        'metadata': {
          'reactions': [for (final r in react) {'emoji_name': r, 'user_id': 'u2'}],
        },
      });
  final posts = [
    post('u2', 'Mọi người ơi, thứ 6 tiệc tất niên nhé 🎄', bubble: {'s': 'tuanloc'}),
    post('u2', 'Ai chưa đăng ký thì báo mình', bubble: {'s': 'tuanloc'}),
    post('me', 'Em đăng ký 2 người ạ', bubble: {'s': 'munoel'}),
    post('me', 'Em mang thêm bánh nữa', bubble: {'s': 'munoel'}, react: ['heart']),
    post('u3', 'Báo cáo quý 4 đã duyệt, cảm ơn cả nhóm! https://example.com/q4', bubble: {'s': 'daduyet'}),
    post('me', 'Tuyệt quá 🎉', bubble: {'s': 'meo', 'c': 'FFE0B2'}, root: 'p4'),
    post('u2', 'Giáng sinh vui vẻ cả nhà!'),
    post('me', 'Sếp duyệt rồi, em gửi ngay bản ký cho đối tác trong chiều nay', bubble: {'s': 'quockyvn'}),
  ];
  app.debugPutPosts('c', posts.reversed.toList());
  app.hasMore['c'] = false;
  return app;
}

Widget _wrap(AppState app, Brightness b, Key key, {Widget home = const ChatPage(channelId: 'c')}) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: home,
        ),
      ),
    );


void _season() {
  final s = SeasonState.instance;
  s.clock = () => DateTime(2026, 12, 20, 9);
  s.app = MiniApp.fromJson({'id': kAppearanceApp, 'origin': 'https://chat.test', 'base_url': 'https://chat.test/__apps/appearance'});
  s.org = {
    'cfg': {
      'seasons': {
        'giangsinh': {'enabled': true, 'from': '12-01', 'to': '12-26', 'features': {'wallpaper': true, 'lights': true, 'hats': true, 'effect': true, 'banner': true}},
        'tet': {'enabled': false, 'before': 11, 'after': 8, 'features': {}},
        'trungthu': {'enabled': false, 'before': 7, 'after': 1, 'features': {}},
      },
      'effect': {'mode': 'keyword', 'keywords': [{'k': 'Giáng sinh vui vẻ', 'fx': 'gifts'}, {'k': 'Merry Christmas', 'fx': 'snow'}, {'k': 'Noel', 'fx': 'mix'}]},
      'defaults': {'bubble': null, 'wallpaper': null},
    },
    'version': 3,
    'can_admin': true,
    'windows': [
      {'id': 'giangsinh', 'start': '2026-12-01', 'end': '2026-12-26', 'enabled': true},
      {'id': 'tet', 'start': '2027-01-26', 'end': '2027-02-14', 'enabled': false},
      {'id': 'trungthu', 'start': '2027-09-08', 'end': '2027-09-16', 'enabled': false},
    ],
  };
  // Ảnh tĩnh: tắt chuyển động (không thì Ticker chạy mãi).
  s.mine = {'motion': false};
  s.wallpapers = {};
}

void main() {
  setUp(_season);

  testWidgets('chat trong mùa Giáng sinh: hình nền theo mùa, dây đèn, mũ Noel', (t) async {
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_app(), Brightness.dark, GlobalKey()));
    await t.pump(const Duration(milliseconds: 300));
    final wp = t.widget<ChatWallpaperArt>(find.byType(ChatWallpaperArt));
    expect(wp.choice.art?.id, 'giangsinh');
    expect(find.byType(Garland), findsOneWidget);
    await t.pump(const Duration(seconds: 4)); // hết hiệu ứng lời chúc
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mũ Noel trên ảnh đại diện; chủ ảnh tắt mũ / mình tắt xem mũ thì không có', (t) async {
    final app = _app();
    app.users['u3']!.raw['props'] = {'flygo_no_hat': 'true'};
    Widget av(String id) => ChangeNotifierProvider<AppState>.value(
        value: app, child: MaterialApp(theme: buildTheme(Brightness.light), home: Avatar(userId: id, name: id, size: 48)));
    await t.pumpWidget(av('u2'));
    expect(find.byType(SantaHat), findsOneWidget);
    await t.pumpWidget(av('u3'));
    expect(find.byType(SantaHat), findsNothing);
    SeasonState.instance.mine = {'hats': false};
    await t.pumpWidget(av('u2'));
    expect(find.byType(SantaHat), findsNothing);
    SeasonState.instance.clock = () => DateTime(2026, 11, 20); // ngoài tháng 12
    SeasonState.instance.mine = {};
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpWidget(av('u2'));
    expect(find.byType(SantaHat), findsNothing);
  });

  testWidgets('ngoài mùa / không được dùng app: chat như cũ', (t) async {
    SeasonState.instance.org = null;
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(_app(), Brightness.light, GlobalKey()));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatWallpaperArt), findsNothing);
    expect(find.byType(Garland), findsNothing);
    expect(find.byType(SantaHat), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  final out = Platform.environment['XMAS_OUT'];
  Future<void> shot(WidgetTester t, String name, Size size, bool dark, Widget home) async {
    await _fonts();
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(_wrap(_app(), dark ? Brightness.dark : Brightness.light, key, home: home));
    await t.pump(const Duration(milliseconds: 1400));
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/real-$name-${dark ? 'dark' : 'light'}.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox.shrink());
  }

  for (final dark in [false, true]) {
    final m = dark ? 'dark' : 'light';
    testWidgets('ảnh chat phone $m', (t) async {
      if (out != null) await shot(t, 'chat-phone', const Size(390, 844), dark, const ChatPage(channelId: 'c'));
    });
    testWidgets('ảnh chat desktop $m', (t) async {
      if (out != null) await shot(t, 'chat-desktop', const Size(1100, 760), dark, const ChatPage(channelId: 'c'));
    });
    testWidgets('ảnh app Giao diện $m', (t) async {
      if (out != null) await shot(t, 'app-giaodien', const Size(390, 1500), dark, const AppearancePage());
    });
    testWidgets('ảnh quản trị $m', (t) async {
      if (out != null) await shot(t, 'admin', const Size(390, 1700), dark, const AppearanceAdminPage());
    });
    testWidgets('ảnh Màu nền $m', (t) async {
      if (out == null) return;
      SeasonState.instance.mine = {'motion': false, 'home_bg': 'season', 'home_color': '4A78B8'};
      await shot(t, 'home-color-phone', const Size(390, 1000), dark, const HomeBackgroundPage());
      await shot(t, 'home-color-desktop', const Size(1100, 760), dark, const HomeBackgroundPage());
    });
    testWidgets('ảnh Giao diện chat (tab Hình nền) $m', (t) async {
      if (out == null) return;
      await shot(t, 'chat-appearance', const Size(390, 1100), dark, const DefaultTabController(length: 1, child: _WallTab()));
    });
  }
}

class _WallTab extends StatelessWidget {
  const _WallTab();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Giao diện chat')), body: const WallpaperPickerBody(prefKey: 'c'));
}
