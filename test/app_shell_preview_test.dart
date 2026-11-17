// Ảnh xem trước khung ứng dụng (chạy tay): SHELL_OUT=<thư mục> flutter test test/app_shell_preview_test.dart
// Trang gốc app không nút quay lại (máy tính: trong tab; điện thoại: trang thường), Thư hiện bộ nhớ đệm + vạch tải.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/app_route.dart';
import 'package:flygo_chat/ui/desk_tabs.dart';
import 'package:flygo_chat/ui/drive/drive_page.dart';
import 'package:flygo_chat/ui/drive/session.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/model.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/theme.dart';

import 'drive_fixtures.dart';

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

class _MemCache implements MailCache {
  Map? data;
  @override
  Future<Map?> read() async => data;
  @override
  Future<void> write(Map j) async => data = j;
}

/// Máy chủ thư chưa trả lời (đang làm mới).
class _SlowMail extends DemoMailApi {
  final gate = Completer<void>();
  @override
  Future<MailMe> me() async {
    await gate.future;
    return super.me();
  }
}

void main() {
  final out = Platform.environment['SHELL_OUT'];

  Future<void> shot(WidgetTester t, String name, Size size, Brightness b, Widget Function() app, {bool desk = false}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    Widget page(Widget home) => desk
        ? Builder(builder: (c) {
            final pal = Pal.of(c);
            Icon ic(IconData i, Color col) => Icon(i, size: 17, color: col);
            final tabs = [DeskTab('chat'), DeskTab('mini', arg: 'drive'), DeskTab('mini', arg: 'mail'), DeskTab('mini', arg: 'wiki'), DeskTab('mini', arg: 'admin:mail')];
            final labels = {
              'chat': DeskTabLabel(ic(Icons.chat_bubble_rounded, const Color(0xFF25A244)), 'Chat', badge: 3),
              'drive': DeskTabLabel(ic(Icons.add_to_drive_rounded, const Color(0xFF4285F4)), 'Drive'),
              'mail': DeskTabLabel(ic(Icons.mail_rounded, const Color(0xFFEA4335)), 'Thư'),
              'wiki': DeskTabLabel(ic(Icons.menu_book_rounded, const Color(0xFF0F766E)), 'Wiki'),
              'admin:mail': DeskTabLabel(ic(Icons.mark_email_read_rounded, const Color(0xFF1E7BFF)), 'Quản trị Thư'),
            };
            final cur = name.contains('drive') ? 1 : 2;
            return Material(
              color: pal.bg,
              child: Column(children: [
                DeskTabBar(
                  tabs: tabs,
                  current: cur,
                  label: (x) => labels[x.arg ?? x.kind]!,
                  onSelect: (_) {},
                  onClose: (_) {},
                  onMove: (_, _) {},
                  onNew: () {},
                  onTogglePin: (_) {},
                  onCloseOthers: (_) {},
                ),
                // Tab ứng dụng: navigator riêng của tab, trang gốc là chính ứng dụng.
                Expanded(child: DeskTabScope(child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => home)))),
              ]),
            );
          })
        : home;
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        // Điện thoại: app mở từ Trang chủ như một trang chồng lên ([AppHomeRoute]).
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const SizedBox()),
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('Trang chủ')))),
          if (desk) MaterialPageRoute(builder: (_) => page(app())) else AppHomeRoute(builder: (_) => app()),
        ],
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: size.width < 500 ? 2 : 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox());
  }

  const phone = Size(390, 844), desk = Size(1440, 900);

  testWidgets('ảnh khung ứng dụng', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    await t.runAsync(() => Directory(out).create(recursive: true));
    debugDisableShadows = false;

    // Bộ nhớ đệm hộp thư đến từ lần mở trước.
    final cache = _MemCache();
    await t.runAsync(() async {
      final s = MailStore(DemoMailApi(), cache: cache);
      await s.start();
      s.dispose();
    });

    for (final b in [Brightness.light, Brightness.dark]) {
      final th = b == Brightness.light ? 'light' : 'dark';
      final drive = DriveSession(api: fakeDriveApi(), key: 'shell-$th', app: null, chatToken: 't')..uploads.hold = true;
      await shot(t, 'desktop-$th-1-drive-tab', desk, b, () => DriveHome(session: drive, title: 'Drive'), desk: true);
      await shot(t, 'desktop-$th-2-mail-cached-refreshing', desk, b, () => MailHome(store: MailStore(_SlowMail(), cache: cache), title: 'Thư'), desk: true);
      await shot(t, 'desktop-$th-3-mail-first-open', desk, b, () => MailHome(store: MailStore(_SlowMail()), title: 'Thư'), desk: true);
      await shot(t, 'phone-$th-1-mail-cached-refreshing', phone, b, () => MailHome(store: MailStore(_SlowMail(), cache: cache), title: 'Thư'));
      await shot(t, 'phone-$th-2-mail-first-open', phone, b, () => MailHome(store: MailStore(_SlowMail()), title: 'Thư'));
      await shot(t, 'phone-$th-3-drive', phone, b, () => DriveHome(session: drive, title: 'Drive'));
    }
    debugDisableShadows = true;
  });
}
