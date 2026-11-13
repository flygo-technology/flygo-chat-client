// Ảnh xem trước thẻ người dùng trang Mở ứng dụng + nút Đăng xuất trang cài đặt (chạy tay):
//   CARD_OUT=<thư mục> flutter test test/apps_user_card_preview_test.dart
// Không có IMG: kiểm tra thẻ dựng được, chữ dài không tràn, có Đăng xuất.
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
import 'package:flygo_chat/ui/edit_profile_page.dart';
import 'package:flygo_chat/ui/home_page.dart';
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

void main() {
  final out = Platform.environment['CARD_OUT'];
  final app = AppState('t')
    ..me = MmUser({
      'id': 'me',
      'username': 'nguyenvana',
      'first_name': 'Nguyễn Văn',
      'last_name': 'An',
      'email': 'nguyenvana@congty-thang-may-rat-dai.example.vn',
      'position': 'Trưởng phòng Kinh doanh',
      'props': {
        'customStatus': jsonEncode({'emoji': 'computer', 'text': 'Đang họp khách hàng', 'expires_at': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String()}),
        'bio': 'Phụ trách khách hàng khu vực phía Bắc. Liên hệ giờ hành chính, ngoài giờ nhắn tin để lại lời nhắn nhé.',
        'phone': '0900 000 000',
      },
    });
  app.users['me'] = app.me!;
  app.statuses['me'] = 'online';
  ServerList.items = [ServerEntry('https://chat.cong-ty-rat-dai-ten-mien.example.vn', 'Công ty Thang máy Rất Dài Tên Miền Việt Nam')];
  ServerList.current = ServerList.items.first.url;
  currentBuild.value = '466';

  Widget host(Brightness b, Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: child),
      );

  Widget card({VoidCallback? logout}) => AppsUserCard(onProfile: () {}, onSettings: () {}, onLogout: logout ?? () {});
  Widget server() => const AppsServerRow();

  /// Ô ứng dụng giả (minh hoạ bố cục; thẻ và dòng máy chủ là widget thật).
  Widget tiles(Pal pal, List<(IconData, String)> items) => Wrap(spacing: 22, runSpacing: 20, children: [
        for (final (i, l) in items)
          SizedBox(
            width: 72,
            child: Column(children: [
              Container(width: 58, height: 58, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(17)), child: Icon(i, color: Colors.white, size: 28)),
              const SizedBox(height: 8),
              Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: pal.text)),
            ]),
          ),
      ]);
  Widget sectionTitle(Pal pal, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 13, letterSpacing: .8, fontWeight: FontWeight.w600, color: pal.sub)),
      );

  Future<void> shot(WidgetTester t, String name, Size size, Widget page, {Future<void> Function()? before}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: page));
    await t.pump(const Duration(milliseconds: 200));
    if (before != null) await before();
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Widget phone(Brightness b) => host(
        b,
        Builder(
          builder: (c) => Scaffold(
            backgroundColor: Pal.of(c).bg,
            body: ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Text('Mở ứng dụng', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Pal.of(c).text)),
              ),
              card(),
            ]),
          ),
        ),
      );

  testWidgets('thẻ người dùng: chữ dài không tràn, có Đăng xuất, phiên bản chỉ số bản', (t) async {
    if (out != null) await t.runAsync(_fonts);
    var loggedOut = 0;
    await shot(t, 'card-phone-light', const Size(390, 700), host(Brightness.light, Scaffold(body: ListView(children: [card(logout: () => loggedOut++), server()]))));
    expect(t.takeException(), isNull, reason: 'không tràn (RenderFlex overflow)');
    expect(find.text('Phiên bản 466'), findsOneWidget);
    expect(find.byKey(const ValueKey('apps-current-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('apps-bio')), findsOneWidget);
    expect(find.byKey(const ValueKey('apps-presence-dot')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('apps-logout')));
    expect(loggedOut, 1);
    await shot(t, 'a-card-phone-light', const Size(390, 720), phone(Brightness.light));
    await shot(t, 'b-card-phone-dark', const Size(390, 720), phone(Brightness.dark));
    expect(t.takeException(), isNull);
    // Máy tính: cột trái 1/3 (thẻ, máy chủ ghim dưới cùng), ứng dụng bên phải 2/3 (ô giả để thấy bố cục).
    await shot(
        t,
        'c-desktop-light',
        const Size(1280, 760),
        host(
          Brightness.light,
          Builder(builder: (c) {
            final pal = Pal.of(c);
            return Scaffold(
              backgroundColor: pal.bg,
              body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 1280 / 3,
                  child: Column(children: [
                    Expanded(child: ListView(padding: const EdgeInsets.only(top: 24, bottom: 16), children: [card()])),
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: server()),
                  ]),
                ),
                Expanded(
                  child: ListView(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Text('Mở ứng dụng', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
                    ),
                    sectionTitle(pal, 'Chính'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: tiles(pal, [(Icons.chat_bubble_rounded, 'Chat'), (Icons.auto_awesome_rounded, 'Dự án AI'), (Icons.campaign_rounded, 'Bảng tin'), (Icons.contacts_rounded, 'Danh bạ'), (Icons.call_rounded, 'Cuộc gọi'), (Icons.computer_rounded, 'Máy tính')]),
                    ),
                  ]),
                ),
              ]),
            );
          }),
        ));
    expect(t.takeException(), isNull);
    // Điện thoại cuộn xuống cuối: mục Cá nhân rồi dòng máy chủ.
    await shot(
        t,
        'd-phone-bottom-light',
        const Size(390, 520),
        host(
          Brightness.light,
          Builder(builder: (c) {
            final pal = Pal.of(c);
            return Scaffold(
              backgroundColor: pal.bg,
              body: ListView(reverse: true, children: [
                const SizedBox(height: 16),
                server(),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: tiles(pal, [(Icons.settings_rounded, 'Cài đặt'), (Icons.devices_rounded, 'Thiết bị'), (Icons.qr_code_scanner_rounded, 'Đăng nhập QR'), (Icons.auto_awesome_rounded, 'Trợ lý'), (Icons.power_outlined, 'Bot'), (Icons.translate_rounded, 'Ngôn ngữ'), (Icons.password_rounded, 'Mật khẩu'), (Icons.block_rounded, 'Chặn')]),
                ),
                sectionTitle(pal, 'Cá nhân'),
              ]),
            );
          }),
        ));
    expect(t.takeException(), isNull);
  });

  testWidgets('màn Chỉnh sửa hồ sơ: điện thoại sáng / tối, máy tính (hộp thoại)', (t) async {
    if (out != null) await t.runAsync(_fonts);
    for (final b in Brightness.values) {
      await shot(t, 'f-edit-phone-${b.name}', const Size(390, 900), host(b, const EditProfilePage()));
      expect(t.takeException(), isNull);
    }
    expect(find.byKey(const ValueKey('edit-username')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('edit-save'))).onPressed, isNull, reason: 'chưa đổi gì thì chưa lưu');
    await t.enterText(find.byKey(const ValueKey('edit-username')), 'A b');
    await t.pump();
    expect(find.textContaining('3–22 ký tự'), findsOneWidget);
    await shot(
        t,
        'g-edit-desktop-light',
        const Size(1100, 760),
        host(
          Brightness.light,
          Builder(
            builder: (c) => Scaffold(
              backgroundColor: Colors.black26,
              body: Center(
                child: Dialog(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: const SizedBox(width: 520, height: 680, child: EditProfilePage(dialog: true)),
                ),
              ),
            ),
          ),
        ));
    expect(t.takeException(), isNull);
  });

  testWidgets('trang cài đặt: nút Đăng xuất ở cuối', (t) async {
    if (out != null) await t.runAsync(_fonts);
    var loggedOut = 0;
    await shot(t, 'e-settings-bottom', const Size(390, 844), host(Brightness.light, Scaffold(body: ProfileView(onLogout: () => loggedOut++, onSwitchServer: (_) {}))),
        before: () async {
      await t.scrollUntilVisible(find.byKey(const ValueKey('profile-logout')), 400, scrollable: find.byType(Scrollable).first);
      await t.pump(const Duration(milliseconds: 200));
    });
    await t.tap(find.byKey(const ValueKey('profile-logout')));
    expect(loggedOut, 1);
  });
}
