// Ảnh chụp màn hình Drive (chạy tay): DRIVE_OUT=<thư mục> flutter test test/drive_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/drive/actions.dart';
import 'package:flygo_chat/ui/drive/api.dart';
import 'package:flygo_chat/ui/drive/drive_page.dart';
import 'package:flygo_chat/ui/drive/offline.dart';
import 'package:flygo_chat/ui/drive/pickers.dart';
import 'package:flygo_chat/ui/drive/session.dart';
import 'package:flygo_chat/ui/drive/uploads.dart';
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

DriveSession _session() {
  final s = DriveSession(api: fakeDriveApi(), key: 'shot-${DateTime.now().microsecondsSinceEpoch}', app: null, chatToken: 't');
  for (final j in driveFixture().where((x) => const [12, 21, 24].contains(x['id']))) {
    final it = DriveItem.fromJson(j);
    s.offline.entries[it.path] = OfflineEntry(item: it, local: null);
  }
  return s;
}

void _jobs(DriveSession s) {
  // Ảnh tĩnh: không cho hàng đợi chạy thật (tệp mẫu không có trên máy).
  s.uploads.hold = true;
  UploadJob j(String name, String dir, int size, UploadState st, {int sent = 0, String? err}) => UploadJob(id: name, src: '/x/$name', name: name, dir: dir, size: size)
    ..state = st
    ..sent = sent
    ..error = err
    ..doneAt = DateTime.now().millisecondsSinceEpoch;
  s.uploads.jobs.addAll([
    j('Quay phim công trình 2.mp4', '/', 134217728, UploadState.running, sent: 77594624),
    j('IMG_2052.jpg', '/Ảnh từ điện thoại', 3900000, UploadState.queued),
    j('Báo giá thang máy.pdf', '/Kế toán', 2200000, UploadState.waiting, sent: 680000, err: 'Mất kết nối, sẽ tự thử lại'),
    j('IMG_2051.jpg', '/Ảnh từ điện thoại', 4089446, UploadState.done, sent: 4089446),
    j('Biên bản họp 14-11.docx', '/', 38912, UploadState.done, sent: 38912),
  ]);
}

void main() {
  final out = Platform.environment['DRIVE_OUT'];

  Future<void> shot(WidgetTester tester, String name, Size size, Brightness b, Widget home, {Future<void> Function(BuildContext)? then}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(debugShowCheckedModeBanner: false, navigatorKey: nav, theme: buildTheme(b), home: home),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    if (then != null) {
      then(nav.currentContext!);
      await settle();
    }
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  }

  const phone = Size(390, 844), desk = Size(1440, 900);
  DriveItem item(int id) => DriveItem.fromJson(driveFixture().firstWhere((x) => x['id'] == id));

  testWidgets('ảnh chụp Drive', (tester) async {
    if (out == null) return;
    await tester.runAsync(_fonts);
    await tester.runAsync(() => Directory(out).create(recursive: true));

    var s = _session();
    await shot(tester, '01-phone-home-light', phone, Brightness.light, DriveHome(session: s));
    s = _session();
    _jobs(s);
    await shot(tester, '02-phone-home-dark-uploading', phone, Brightness.dark, DriveHome(session: s));
    s = _session();
    await shot(tester, '03-phone-item-sheet', phone, Brightness.light, DriveHome(session: s), then: (c) => showItemActions(c, s, item(21)));
    s = _session();
    _jobs(s);
    await shot(tester, '04-phone-uploads-dark', phone, Brightness.dark, UploadsPage(session: s));
    s = _session();
    await shot(tester, '05-phone-share-dialog', phone, Brightness.light, DriveHome(session: s), then: (c) => showShareDialog(c, s, item(21)));
    s = _session();
    await shot(tester, '06-phone-save-to-drive', phone, Brightness.light, ShareTargetPage(paths: const [], text: '', session: s, toDrive: true));
    s = _session();
    await shot(tester, '07-phone-chat-attach', phone, Brightness.light, Scaffold(body: DriveAttachSheet(session: s)));
    s = _session();
    await shot(tester, '08-phone-details', phone, Brightness.light, DriveHome(session: s), then: (c) => showDetails(c, s, item(21)));
    s = _session();
    await shot(tester, '09-desktop-light', desk, Brightness.light, DriveHome(session: s));
    s = _session();
    _jobs(s);
    await shot(tester, '10-desktop-dark', desk, Brightness.dark, DriveHome(session: s));
  });
}
