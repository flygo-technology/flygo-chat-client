// Mockup nền Trang chủ (danh sách ứng dụng) mùa Giáng sinh (chạy tay): HOME_OUT=<thư mục> flutter test test/home_bg_mockup_test.dart
// Thẻ người dùng và tên máy chủ là widget thật; ô ứng dụng vẽ đúng kiểu ô của trang (home_page.dart appTile / grid)
// với biểu tượng, màu, tên lấy từ trang thật, dữ liệu giả.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/data/servers.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/common.dart' show Avatar;
import 'package:flygo_chat/ui/home_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/update/build_label.dart';
import 'package:provider/provider.dart';

import 'support/fake_photos.dart';

import 'package:flygo_chat/ui/season/season.dart' show WallpaperView, wallpaperById, XmasBanner;
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

typedef T = (IconData, Color, String, int);

void main() {
  final out = Platform.environment['HOME_OUT'];
  final app = AppState('t')
    ..me = MmUser({
      'id': 'me',
      'username': 'nguyenvana',
      'first_name': 'Nguyễn Văn',
      'last_name': 'An',
      'email': 'nguyenvana@congty.example.vn',
      'last_picture_update': 1,
      'position': 'Trưởng phòng Kinh doanh',
      'props': {
        'customStatus': jsonEncode({'emoji': '', 'text': 'Đang họp khách hàng', 'expires_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()}),
        'bio': 'Phụ trách khách hàng khu vực phía Bắc.',
      },
    });
  app.users['me'] = app.me!;
  app.statuses['me'] = 'online';
  ServerList.items = [ServerEntry('https://chat.congty.example.vn', 'Công ty Thang máy Ví Dụ')];
  ServerList.current = ServerList.items.first.url;
  currentBuild.value = '466';

  // Ô của trang (appTile): biểu tượng là widget thật AppTileIcon; ô Hồ sơ là ô tròn chứa ảnh đại diện.
  Widget tile(Pal pal, Widget icon, Color? color, String label, {int badge = 0, bool circle = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Badge(
          isLabelVisible: badge > 0,
          label: Text('$badge'),
          backgroundColor: const Color(0xFFE53935),
          textColor: Colors.white,
          child: AppTileIcon(icon: icon, color: color, circle: circle),
        ),
        const SizedBox(height: 9),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, color: pal.text)),
      ]),
    );
  }

  List<Widget> icons(Pal pal, List<T> items) => [for (final (i, c, l, b) in items) tile(pal, Icon(i, color: Colors.white, size: 30), c, l, badge: b)];
  // Mini app: ô trắng; biểu tượng thật là ảnh / emoji của app, ảnh thử dùng biểu tượng màu (máy test không có phông emoji).
  List<Widget> minis(Pal pal, List<(IconData, Color, String)> items) =>
      [for (final (i, c, l) in items) tile(pal, Icon(i, color: c, size: 30), null, l)];


  // Nhóm ô đặt trên tấm kính mờ (nền mùa lễ phía sau vẫn êm, chữ luôn rõ).
  Widget grid(Pal pal, String title, List<Widget> tiles, {bool glass = false, bool panel = false}) {
    final inner = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(glass ? 16 : 20, glass ? 14 : 18, 20, 4),
        child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
      ),
      LayoutBuilder(builder: (ctx, c) {
        final cols = (c.maxWidth / (panel ? 100 : 96)).floor().clamp(4, 14);
        final w = (c.maxWidth - 16) / cols;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(children: [for (final t in tiles) SizedBox(width: w, child: t)]),
        );
      }),
    ]);
    if (panel) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: pal.surface.withValues(alpha: .6), borderRadius: BorderRadius.circular(22)),
        child: inner,
      );
    }
    if (!glass) return inner;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: pal.surface.withValues(alpha: pal.bg.computeLuminance() < .2 ? .58 : .66),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: pal.bg.computeLuminance() < .2 ? .07 : .5)),
            ),
            child: inner,
          ),
        ),
      ),
    );
  }

  List<Widget> sections(Pal pal, bool glass, {bool panel = false}) => [
        grid(pal, 'Chính', [
          ...icons(pal, [
            (Icons.chat_bubble_rounded, const Color(0xFF25A244), 'Chat', 3),
            (Icons.auto_awesome_rounded, const Color(0xFFD97757), 'Dự án AI', 1),
          ]),
          ...minis(pal, [(Icons.campaign_rounded, const Color(0xFFE67E22), 'Bảng tin'), (Icons.sticky_note_2_rounded, const Color(0xFFF2B01E), 'Ghi chú')]),
          ...icons(pal, [
            (Icons.event_rounded, const Color(0xFF1E7BFF), 'Lịch', 0),
            (Icons.videocam_rounded, const Color(0xFF0EA5E9), 'Họp', 0),
            (Icons.contacts_rounded, const Color(0xFF2F80ED), 'Danh bạ', 0),
            (Icons.call_rounded, const Color(0xFFE53935), 'Cuộc gọi', 0),
          ]),
        ], glass: glass, panel: panel),
        grid(pal, 'Ứng dụng', minis(pal, [(Icons.insights_rounded, const Color(0xFF2F80ED), 'Báo cáo'), (Icons.mail_rounded, const Color(0xFFEA4335), 'Gmail'), (Icons.receipt_long_rounded, const Color(0xFF16A34A), 'Hoá đơn'), (Icons.account_balance_rounded, const Color(0xFF7C3AED), 'Ngân hàng')]), glass: glass, panel: panel),
        grid(pal, 'Quản trị', icons(pal, [
          (Icons.account_tree_outlined, const Color(0xFF0F766E), 'Tổ chức', 0),
          (Icons.manage_accounts_rounded, const Color(0xFF0F766E), 'Người dùng', 0),
          (Icons.palette_rounded, const Color(0xFFC62828), 'Giao diện', 0),
        ]), glass: glass, panel: panel),
        grid(pal, 'Cá nhân', [
          tile(pal, Avatar(userId: 'me', name: 'Nguyễn Văn An', size: 62, status: false), null, 'Hồ sơ', circle: true),
          ...icons(pal, [
            (Icons.settings_rounded, const Color(0xFF14A38B), 'Cài đặt', 0),
            (Icons.devices_rounded, const Color(0xFF2563EB), 'Thiết bị', 0),
            (Icons.auto_awesome_rounded, const Color(0xFFD97757), 'Trợ lý', 0),
            (Icons.translate_rounded, const Color(0xFF9B51E0), 'Ngôn ngữ', 0),
            (Icons.password_rounded, const Color(0xFFF2C94C), 'Mật khẩu', 0),
            (Icons.privacy_tip_outlined, const Color(0xFF5B6CFF), 'Quyền riêng tư', 0),
          ]),
        ], glass: glass, panel: panel),
      ];

  Widget background(String id) => id == 'hiennay' ? const SizedBox.shrink() : WallpaperView(wallpaper: wallpaperById(id)!, frozenT: 2);

  Widget phone(Brightness b, String id) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: Builder(builder: (c) {
            final pal = Pal.of(c);
            final glass = id != 'hiennay';
            return Scaffold(
              backgroundColor: pal.bg,
              body: Stack(children: [
                Positioned.fill(child: background(id)),
                ListView(padding: const EdgeInsets.only(bottom: 110), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 52, 20, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(bottom: 14), child: Center(child: AppsServerTitle())),
                      if (glass) XmasBanner(now: DateTime(2026, 12, 10)),
                    ]),
                  ),
                  ...sections(pal, glass),
                ]),
              ]),
            );
          }),
        ),
      );

  Widget desktop(Brightness b, String id) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: Builder(builder: (c) {
            final pal = Pal.of(c);
            final glass = id != 'hiennay';
            return Scaffold(
              backgroundColor: pal.bg,
              body: Stack(children: [
                Positioned.fill(child: background(id)),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 1280 / 3,
                    child: ListView(padding: const EdgeInsets.only(top: 24, bottom: 16), children: [
                      AppsUserCard(onProfile: () {}, onSettings: () {}),
                      if (glass) XmasBanner(now: DateTime(2026, 12, 10)),
                    ]),
                  ),
                  Expanded(child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 24, right: 12), children: sections(pal, glass))),
                ]),
              ]),
            );
          }),
        ),
      );

  // Trang chủ máy tính sau góp ý của Sếp (17/11): nền thường, tấm nền nhạt cho từng nhóm, cột thẻ <= 400, rộng tới 1680, không thanh cuộn.
  Widget desktopV2(Brightness b) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: Builder(builder: (c) {
            final pal = Pal.of(c);
            return Scaffold(
              backgroundColor: pal.bg,
              body: ScrollConfiguration(
                behavior: ScrollConfiguration.of(c).copyWith(scrollbars: false),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1680),
                    child: LayoutBuilder(builder: (_, k) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: k.maxWidth / 3 > 400 ? 400 : k.maxWidth / 3,
                        child: ListView(padding: const EdgeInsets.only(top: 24, bottom: 16), children: [AppsUserCard(onProfile: () {}, onSettings: () {})]),
                      ),
                      Expanded(
                        child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 24, right: 12), children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                            child: Text('Mở ứng dụng', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
                          ),
                          ...sections(pal, false, panel: true),
                        ]),
                      ),
                    ])),
                  ),
                ),
              ),
            );
          }),
        ),
      );

  const ids = ['hiennay', 'giangsinh2', 'tuyetem', 'anhden', 'rungthong', 'cucquang', 'doituyet', 'cuaso', 'kinhsuong'];
  Future<void> png(WidgetTester t, String name, Size size, Widget w) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: w));
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('desktop v2', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    await useFakePhotos(t);
    for (final b in Brightness.values) {
      await png(t, 'desktop-v2-${b.name}', const Size(1600, 900), desktopV2(b));
    }
  });

  for (final (i, id) in ids.indexed) {
    testWidgets('home $id', (t) async {
      if (out == null) return;
      await t.runAsync(_fonts);
      await useFakePhotos(t);
      final n = '${i.toString().padLeft(2, '0')}-$id';
      for (final b in Brightness.values) {
        await png(t, '$n-phone-${b.name}', const Size(390, 1000), phone(b, id));
        await png(t, '$n-desktop-${b.name}', const Size(1280, 800), desktop(b, id));
      }
    });
  }
}
