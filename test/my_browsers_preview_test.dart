// Ảnh xem trước "Trình duyệt của tôi" + màn hình chờ trình duyệt Flygo (chạy tay):
//   MB_OUT=<thư mục> flutter test test/my_browsers_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_browser_host.dart';
import 'package:flygo_chat/browser/flygo_browser_loading.dart';
import 'package:flygo_chat/browser/my_browsers.dart';
import 'package:flygo_chat/ui/my_browsers_page.dart';
import 'package:flygo_chat/ui/theme.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files, [String? base]) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('${base ?? dir}/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  // Chữ tiếng Việt: Inter của app (đủ dấu), nạp dưới các tên theme có thể dùng.
  const inter = ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf', 'Inter-Bold.ttf'];
  for (final fam in ['Flygo Inter', 'Roboto', 'Noto Sans', '.SF NS', 'Segoe UI']) {
    await load(fam, inter, 'assets/fonts');
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _now = DateTime(2026, 11, 23, 1, 30).millisecondsSinceEpoch;
MyBrowser _b(Map<String, dynamic> m) => MyBrowser({'last_seen': _now - 3600 * 1000, ...m});

final _browsers = [
  _b({'id': 'a1', 'name': 'ba@flygo.vn · macmini', 'slug': 'ba-flygo-vn-macmini', 'engine': 'Chrome 157', 'os': 'macOS', 'machine_name': 'macmini', 'online': true, 'default': true, 'category': 'external'}),
  _b({'id': 'a2', 'name': 'duongvanba.agency - mac mini', 'slug': 'duongvanba-agency-mac-mini', 'engine': 'Chrome 157', 'os': 'macOS', 'machine_name': 'macmini', 'online': true, 'category': 'external',
      'in_use_by': {'agent': 'jessica', 'since': _now}}),
  _b({'id': 'a3', 'name': 'duongvanba6868 · MacBook-Air-cua-Duyen', 'slug': 'duongvanba6868-macbook-air-cua-duyen', 'engine': 'Chrome 157', 'os': 'macOS', 'machine_name': 'MacBook-Air-cua-Duyen', 'online': false, 'category': 'external'}),
  _b({'id': 'k1', 'type': 'integrated', 'name': 'Ký số · CÔNG TY TNHH CÔNG NGHỆ FLYGO · macmini', 'slug': 'ky-so-cong-ty-tnhh-cong-nghe-flygo-macmini', 'engine': 'Electron 44', 'os': 'macOS',
      'machine_name': 'macmini', 'online': true, 'category': 'integrated', 'remote_startable': true, 'start_ready': true, 'tax': '0110804395'}),
  _b({'id': 'k2', 'type': 'integrated', 'name': 'Ký số · CÔNG TY CP THANG MÁY DND VINA · macmini', 'slug': 'ky-so-cong-ty-cp-thang-may-dnd-vina-macmini', 'engine': 'Electron 44', 'os': 'macOS',
      'machine_name': 'macmini', 'online': false, 'category': 'integrated', 'remote_startable': true, 'start_ready': true, 'tax': '0108456789'}),
  _b({'id': 'k3', 'type': 'integrated', 'name': 'Ký số · CÔNG TY TNHH CÔNG NGHỆ FLYGO · MacBook-Air-cua-Duyen', 'slug': 'ky-so-flygo-macbook', 'engine': 'Electron 44', 'os': 'macOS',
      'machine_name': 'MacBook-Air-cua-Duyen', 'online': false, 'category': 'integrated', 'remote_startable': true, 'start_ready': false, 'tax': '0110804395'}),
];

final _profiles = [
  {'id': 'vn.flygo.kyso/misa-bfff', 'name': 'Ký số Flygo', 'company': 'CÔNG TY TNHH CÔNG NGHỆ FLYGO', 'server': 'https://kyso.flygo.vn', 'tokenId': 'misa:bfff', 'taxCode': '0110804395',
   'info': {'label': '', 'open': true, 'hasSiteData': true, 'siteDataBytes': 3460000, 'vaultShared': true}},
  {'id': 'vn.flygo.kyso/fpt-40d4', 'name': 'Ký số DND VINA', 'company': 'CÔNG TY CP THANG MÁY DND VINA', 'server': 'https://kyso.dnd-global.com', 'tokenId': 'fpt:40d4', 'taxCode': '0108456789',
   'info': {'label': 'DND (hải quan)', 'open': false, 'hasSiteData': false, 'siteDataBytes': 0, 'vaultShared': true}},
];

void main() {
  final out = Platform.environment['MB_OUT'];

  Future<void> shot(WidgetTester tester, String name, Brightness b, Size size, Widget Function(BuildContext) child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(b),
      home: RepaintBoundary(key: key, child: Builder(builder: child)),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('ảnh xem trước Trình duyệt của tôi + màn hình chờ', (tester) async {
    if (out == null) return;
    Directory(out).createSync(recursive: true);
    await tester.runAsync(_fonts);
    for (final b in Brightness.values) {
      await shot(tester, 'trinh-duyet-cua-toi-${b.name}', b, const Size(720, 1900),
          (_) => MyBrowsersPage(debugBrowsers: _browsers, debugProfiles: _profiles));
      // Hộp hỏi trước khi xoá dữ liệu công ty trên máy.
      await tester.tap(find.descendant(of: find.byType(Card).at(6), matching: find.byType(PopupMenuButton<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá dữ liệu trên máy này'));
      await tester.pumpAndSettle();
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      await tester.runAsync(() async {
        final img = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/xoa-du-lieu-hoi-${b.name}.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      final host = FlygoBrowserHost.instance;
      final steps = <(String, String, double?)>[
        ('1-cho', '', null),
        ('2-tai', 'Đang tải trình duyệt Ký số (lần đầu)…', .42),
        ('3-khoi-dong', 'Đang khởi động trình duyệt…', null),
        ('4-dang-nhap', 'Đang đăng nhập Ký số…', null),
        ('5-mo-trang', 'Đang mở trang…', null),
      ];
      for (final (id, stage, p) in steps) {
        host.stage.value = stage;
        host.download.value = p;
        await shot(tester, 'man-hinh-cho-$id-${b.name}', b, const Size(560, 300), (c) => Scaffold(
              backgroundColor: Colors.black26,
              body: FlygoBrowserLoadingCard(
                title: 'CÔNG TY TNHH CÔNG NGHỆ FLYGO',
                url: 'https://e-declaration.customs.gov.vn:8443/eclare-ui/',
                onCancel: () {},
              ),
            ));
      }
      host.stage.value = '';
      host.download.value = null;
    }
  });
}
