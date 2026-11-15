// Ảnh xem trước bộ chọn hộp thư, AI đọc thư và Quản trị Thư (chạy tay): MAIL_OUT=<thư mục> flutter test test/mail_admin_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/mail/admin_page.dart';
import 'package:flygo_chat/ui/mail/demo.dart';
import 'package:flygo_chat/ui/mail/mail_page.dart';
import 'package:flygo_chat/ui/mail/store.dart';
import 'package:flygo_chat/ui/theme.dart';

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
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Italic.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['MAIL_OUT'];
  final key = GlobalKey();

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> save(WidgetTester t, String name) async {
    await settle(t);
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: t.view.devicePixelRatio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> app(WidgetTester t, Size size, Brightness b, Widget home, {double ratio = 1}) async {
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: buildTheme(b), home: home),
    ));
    await settle(t);
  }

  for (final b in [Brightness.light, Brightness.dark]) {
    final th = b == Brightness.light ? 'light' : 'dark';

    testWidgets('máy tính $th', (t) async {
      if (out == null) return;
      await t.runAsync(_fonts);
      debugDisableShadows = false;
      final api = DemoMailApi();
      final store = MailStore(api);
      await app(t, const Size(1440, 900), b, MailHome(store: store, title: 'Flygo Mail', ownsStore: false));
      await t.tap(find.byKey(const ValueKey('mail-switcher')).first);
      await save(t, 'desktop-$th-1-switcher');
      await t.tap(find.text('Hỗ trợ khách hàng').first);
      await settle(t);
      await save(t, 'desktop-$th-2-shared-mailbox');
      await t.tap(find.textContaining('WiFi khách', findRichText: true).first);
      await settle(t);
      await t.tap(find.byKey(const ValueKey('mail-ai')));
      await settle(t);
      await save(t, 'desktop-$th-3-ai');

      // Quản trị Thư
      final admin = api.adminApi();
      await app(t, const Size(1440, 900), b, MailAdminPage(api: admin));
      await t.tap(find.text('hotro@example.com').first);
      await save(t, 'desktop-$th-4-admin-mailboxes');
      if (b == Brightness.light) {
        for (final (s, n) in [('Bí danh', 'aliases'), ('Tên miền', 'domains'), ('Chuyển tiếp & catch-all', 'routing'), ('Giới hạn gửi', 'limits'), ('Nhật ký', 'audit')]) {
          await t.tap(find.text(s).first);
          await save(t, 'desktop-$th-5-admin-$n');
        }
        await t.tap(find.text('Hộp thư').first);
        await settle(t);
        await t.tap(find.text('Tạo hộp thư').first);
        await settle(t);
        await t.tap(find.text('Dùng chung').last);
        await save(t, 'desktop-$th-6-admin-create');
      }
      debugDisableShadows = true;
    });

    testWidgets('điện thoại $th', (t) async {
      if (out == null) return;
      await t.runAsync(_fonts);
      debugDisableShadows = false;
      final api = DemoMailApi();
      final store = MailStore(api);
      await app(t, const Size(390, 844), b, MailHome(store: store, title: 'Flygo Mail', ownsStore: false), ratio: 2);
      await t.tap(find.byKey(const ValueKey('mail-switcher')).first);
      await save(t, 'phone-$th-1-switcher');
      await t.tapAt(const Offset(195, 830));
      await settle(t);
      await t.tap(find.textContaining('Báo giá triển khai', findRichText: true).first);
      await settle(t);
      await t.tap(find.byKey(const ValueKey('mail-ai')));
      await settle(t);
      await save(t, 'phone-$th-2-ai');
      await t.tap(find.byTooltip('Quay lại (u)'));
      await t.pumpAndSettle(const Duration(milliseconds: 50));

      final admin = api.adminApi();
      await app(t, const Size(390, 844), b, MailAdminPage(api: admin), ratio: 2);
      await save(t, 'phone-$th-3-admin-home');
      await app(t, const Size(390, 844), b, MailAdminPage(api: admin, section: 'mailboxes'), ratio: 2);
      await save(t, 'phone-$th-4-admin-mailboxes');
      await t.tap(find.text('Hỗ trợ khách hàng').first);
      await t.pumpAndSettle(const Duration(milliseconds: 50));
      await save(t, 'phone-$th-5-admin-mailbox-detail');
      if (b == Brightness.light) {
        for (final n in ['domains', 'routing']) {
          await app(t, const Size(390, 844), b, MailAdminPage(api: admin, section: n), ratio: 2);
          await save(t, 'phone-$th-6-admin-$n');
        }
      }
      debugDisableShadows = true;
    });
  }
}
