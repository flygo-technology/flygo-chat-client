// Ảnh cả trang Mở ứng dụng trên điện thoại, từ trên xuống dưới (chạy tay):
//   CARD_OUT=<thư mục> flutter test test/apps_page_full_preview_test.dart
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
import 'package:flygo_chat/ui/server_picker.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/update/build_label.dart';
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

  for (final family in ['Roboto', 'Noto Sans']) {
    await load(family, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

typedef T = (IconData, Color, String, int);

void main() {
  final out = Platform.environment['CARD_OUT'];
  final app = AppState('t')
    ..me = MmUser({
      'id': 'me',
      'username': 'nguyenvana',
      'first_name': 'Nguyễn Văn',
      'last_name': 'An',
      'email': 'nguyenvana@congty.example.vn',
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

  // Đúng kiểu ô của trang (appTile): ô 62px bo 18, màu chuyển + bóng; mini app: ô trắng viền mảnh, biểu tượng emoji.
  Widget tile(Pal pal, Widget icon, Color? color, String label, {int badge = 0}) {
    final box = color == null
        ? BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: pal.divider),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 10, offset: const Offset(0, 4))],
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(color, Colors.white, .28)!, color, Color.lerp(color, Colors.black, .12)!],
              stops: const [0, .55, 1],
            ),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 12, offset: const Offset(0, 5))],
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Badge(
          isLabelVisible: badge > 0,
          label: Text('$badge'),
          backgroundColor: const Color(0xFFE53935),
          textColor: Colors.white,
          child: Container(width: 62, height: 62, decoration: box, child: Center(child: icon)),
        ),
        const SizedBox(height: 9),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, color: pal.text)),
      ]),
    );
  }

  Widget grid(Pal pal, String title, List<Widget> tiles) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
        ),
        LayoutBuilder(builder: (ctx, c) {
          final cols = (c.maxWidth / 108).floor().clamp(4, 12);
          final w = (c.maxWidth - 24) / cols;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(children: [for (final t in tiles) SizedBox(width: w, child: t)]),
          );
        }),
      ]);

  List<Widget> icons(Pal pal, List<T> items) => [for (final (i, c, l, b) in items) tile(pal, Icon(i, color: Colors.white, size: 30), c, l, badge: b)];
  // Mini app: ô trắng; biểu tượng thật là ảnh / emoji của app, ảnh thử dùng biểu tượng màu (máy test không có phông emoji).
  List<Widget> minis(Pal pal, List<(IconData, Color, String)> items) =>
      [for (final (i, c, l) in items) tile(pal, Icon(i, color: c, size: 30), null, l)];

  Widget page(Brightness b) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          home: Builder(builder: (c) {
            final pal = Pal.of(c);
            return Scaffold(
              backgroundColor: pal.bg,
              body: Stack(children: [
                ListView(padding: const EdgeInsets.only(bottom: 110), children: [
                  Padding(
                    // 44: thanh trạng thái giả của điện thoại (MediaQuery padding top).
                    padding: const EdgeInsets.fromLTRB(20, 8 + 44, 20, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(bottom: 14), child: Center(child: AppsServerTitle())),
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(19), border: Border.all(color: pal.divider)),
                        child: Row(children: [
                          Icon(Icons.search_rounded, size: 20, color: pal.sub),
                          const SizedBox(width: 6),
                          Text('Tìm ứng dụng', style: TextStyle(fontSize: 14, color: pal.sub)),
                        ]),
                      ),
                    ]),
                  ),
                  grid(pal, 'Chính', [
                    ...icons(pal, [
                      (Icons.chat_bubble_rounded, const Color(0xFF25A244), 'Chat', 3),
                      (Icons.auto_awesome_rounded, const Color(0xFFD97757), 'Dự án AI', 1),
                    ]),
                    ...minis(pal, [(Icons.campaign_rounded, const Color(0xFFE67E22), 'Bảng tin'), (Icons.sticky_note_2_rounded, const Color(0xFFF2B01E), 'Todo')]),
                    ...icons(pal, [
                      (Icons.contacts_rounded, const Color(0xFF2F80ED), 'Danh bạ', 0),
                      (Icons.assignment_ind_rounded, const Color(0xFFE08A1E), 'Ủy quyền', 0),
                      (Icons.call_rounded, const Color(0xFFE53935), 'Lịch sử cuộc gọi', 0),
                      (Icons.computer_rounded, const Color(0xFF5B6CFF), 'Máy tính', 0),
                      (Icons.chat_rounded, const Color(0xFF0068FF), 'Zalo', 0),
                      (Icons.forum_rounded, const Color(0xFF07C160), 'WeChat', 0),
                    ]),
                    ...minis(pal, [(Icons.slideshow_rounded, const Color(0xFFE8590C), 'Trình chiếu')]),
                  ]),
                  grid(pal, 'Ứng dụng', minis(pal, [(Icons.insights_rounded, const Color(0xFF2F80ED), 'Báo cáo kinh doanh'), (Icons.mail_rounded, const Color(0xFFEA4335), 'Gmail'), (Icons.smart_toy_rounded, const Color(0xFF0EA5E9), 'Assistant'), (Icons.receipt_long_rounded, const Color(0xFF16A34A), 'Hoá đơn'), (Icons.account_balance_rounded, const Color(0xFF7C3AED), 'Ngân hàng')])),
                  grid(pal, 'Ký số', icons(pal, [(Icons.draw_rounded, const Color(0xFF7B61FF), 'Ký số Công ty A', 0), (Icons.draw_rounded, const Color(0xFF0EA5E9), 'Ký số Công ty B', 0)])),
                  grid(pal, 'Quy trình', minis(pal, [(Icons.request_quote_rounded, const Color(0xFF0F766E), 'Đề nghị thanh toán'), (Icons.beach_access_rounded, const Color(0xFFF59E0B), 'Xin nghỉ phép'), (Icons.local_shipping_rounded, const Color(0xFF2563EB), 'Giao hàng')])),
                  grid(pal, 'Quản trị', icons(pal, [
                    (Icons.account_tree_outlined, const Color(0xFF0F766E), 'Tổ chức', 0),
                    (Icons.account_tree_rounded, const Color(0xFF5B6CFF), 'Quy trình', 0),
                    (Icons.manage_accounts_rounded, const Color(0xFF0F766E), 'Người dùng', 0),
                  ])),
                  grid(pal, 'Cá nhân', [
                    tile(pal, ClipOval(child: Avatar(userId: 'me', name: 'Nguyễn Văn An', size: 62, status: false)), null, 'Hồ sơ'),
                    ...icons(pal, [
                    (Icons.settings_rounded, const Color(0xFF14A38B), 'Cài đặt', 0),
                    (Icons.devices_rounded, const Color(0xFF2563EB), 'Thiết bị', 0),
                    (Icons.qr_code_scanner_rounded, const Color(0xFF00A3A3), 'Đăng nhập QR', 0),
                    (Icons.auto_awesome_rounded, const Color(0xFFD97757), 'Trợ lý', 0),
                    (Icons.power_outlined, const Color(0xFF607D8B), 'Bot', 0),
                    (Icons.translate_rounded, const Color(0xFF9B51E0), 'Ngôn ngữ', 0),
                    (Icons.password_rounded, const Color(0xFFF2C94C), 'Mật khẩu', 0),
                    (Icons.block_rounded, const Color(0xFF8E8E93), 'Chặn', 0),
                    (Icons.privacy_tip_outlined, const Color(0xFF5B6CFF), 'Quyền riêng tư', 0),
                    (Icons.gavel_rounded, const Color(0xFF8D6E63), 'Điều khoản', 0),
                    (Icons.auto_awesome_outlined, const Color(0xFFD97757), 'AI', 0),
                  ]),
                  ]),
                  Padding(padding: const EdgeInsets.only(top: 16), child: Center(child: AppsLogoutButton(onLogout: () {}))),
                ]),
                // Thanh điều hướng nổi ở dưới (minh hoạ).
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: pal.surface.withValues(alpha: .96),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Row(children: [
                      for (final (i, l, on) in [
                        (Icons.chat_bubble_outline_rounded, 'Chat', false),
                        (Icons.auto_awesome_outlined, 'Trợ lý', false),
                        (Icons.newspaper_rounded, 'Bảng tin', false),
                        (Icons.apps_rounded, 'Apps', true),
                      ])
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(5),
                            decoration: on ? BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(28)) : null,
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(i, color: pal.text, size: 24),
                              Text(l, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: pal.text)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ),
              ]),
            );
          }),
        ),
      );

  testWidgets('cả trang Mở ứng dụng (điện thoại, sáng + tối)', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    for (final b in Brightness.values) {
      t.view.physicalSize = const Size(390, 2050);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(key: key, child: page(b)));
      await t.pump(const Duration(milliseconds: 200));
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/h-apps-page-full-${b.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });

  Future<void> png(WidgetTester t, String name, Size size, Widget w) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: w));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Widget host(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child),
      );

  testWidgets('trang Hồ sơ (điện thoại, từ ô Hồ sơ của Cá nhân) và máy tính', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    await png(t, 'i-phone-profile-light', const Size(390, 860), host(AppsProfilePage(onProfile: () {}, onSettings: () {})));
    await png(
        t,
        'j-desktop-light',
        const Size(1280, 800),
        host(Builder(builder: (c) {
          final pal = Pal.of(c);
          return Scaffold(
            backgroundColor: pal.bg,
            body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 1280 / 3,
                child: Column(children: [
                  Expanded(child: ListView(padding: const EdgeInsets.only(top: 24, bottom: 16), children: [AppsUserCard(onProfile: () {}, onSettings: () {})])),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
                    child: Row(children: [const Expanded(child: AppsServerRow(align: TextAlign.left)), AppsLogoutButton(onLogout: () {})]),
                  ),
                ]),
              ),
              Expanded(
                child: ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Text('Mở ứng dụng', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
                  ),
                  grid(pal, 'Chính', [
                    ...icons(pal, [(Icons.chat_bubble_rounded, const Color(0xFF25A244), 'Chat', 3), (Icons.auto_awesome_rounded, const Color(0xFFD97757), 'Dự án AI', 1)]),
                    ...minis(pal, [(Icons.campaign_rounded, const Color(0xFFE67E22), 'Bảng tin'), (Icons.sticky_note_2_rounded, const Color(0xFFF2B01E), 'Todo')]),
                    ...icons(pal, [(Icons.contacts_rounded, const Color(0xFF2F80ED), 'Danh bạ', 0), (Icons.call_rounded, const Color(0xFFE53935), 'Lịch sử cuộc gọi', 0), (Icons.computer_rounded, const Color(0xFF5B6CFF), 'Máy tính', 0)]),
                  ]),
                  grid(pal, 'Ứng dụng', minis(pal, [(Icons.insights_rounded, const Color(0xFF2F80ED), 'Báo cáo kinh doanh'), (Icons.mail_rounded, const Color(0xFFEA4335), 'Gmail'), (Icons.receipt_long_rounded, const Color(0xFF16A34A), 'Hoá đơn')])),
                  grid(pal, 'Cá nhân', icons(pal, [(Icons.settings_rounded, const Color(0xFF14A38B), 'Cài đặt', 0), (Icons.devices_rounded, const Color(0xFF2563EB), 'Thiết bị', 0), (Icons.translate_rounded, const Color(0xFF9B51E0), 'Ngôn ngữ', 0), (Icons.password_rounded, const Color(0xFFF2C94C), 'Mật khẩu', 0)])),
                ]),
              ),
            ]),
          );
        })));
  });

  testWidgets('bảng chọn máy chủ (vuốt 3 ngón) và đầu danh sách chat (điện thoại)', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    ServerList.items = [
      ServerEntry('https://chat.congty.example.vn', 'Công ty Thang máy Ví Dụ'),
      ServerEntry('https://chat.chinhanh.example.vn', 'Chi nhánh Miền Nam'),
    ];
    t.view.physicalSize = const Size(390, 760);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    late BuildContext ctx;
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: host(Builder(builder: (c) {
        ctx = c;
        final pal = Pal.of(c);
        return Scaffold(
          backgroundColor: pal.bg,
          body: SafeArea(
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: ServerTitle(onSelected: (_) {}, interactive: false)),
              for (final n in ['Nhóm Kinh doanh', 'Kế toán', 'Kho vận'])
                ListTile(leading: CircleAvatar(backgroundColor: pal.accent, child: const Icon(Icons.groups, color: Colors.white)), title: Text(n), subtitle: const Text('Tin nhắn mới nhất…')),
            ]),
          ),
        );
      })),
    ));
    await t.pump(const Duration(milliseconds: 200));
    Future<void> save(String name) => t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
    await save('k-phone-chat-header');
    showServerPicker(ctx);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await save('l-phone-server-picker');
    ServerList.items = [ServerEntry('https://chat.congty.example.vn', 'Công ty Thang máy Ví Dụ')];
  });
}
