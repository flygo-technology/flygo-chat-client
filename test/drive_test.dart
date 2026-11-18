import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/drive/api.dart';
import 'package:flygo_chat/ui/drive/drive_page.dart';
import 'package:flygo_chat/ui/drive/look.dart';
import 'package:flygo_chat/ui/drive/pickers.dart';
import 'package:flygo_chat/ui/drive/preview.dart';
import 'package:flygo_chat/ui/drive/session.dart';
import 'package:flygo_chat/ui/drive/transfers.dart';
import 'package:flygo_chat/ui/drive/uploads.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'drive_fixtures.dart';

void main() {
  group('model', () {
    test('DriveItem.fromJson / toJson', () {
      final it = DriveItem.fromJson({'path': '/A/b.xlsx', 'name': 'b.xlsx', 'dir': false, 'size': 284, 'mime': 'x', 'mtime': 10, 'id': 7, 'fav': true, 'perms': 'RGDNVW'});
      expect(it.parent, '/A');
      expect(it.ext, 'xlsx');
      expect(it.canWrite && it.canDelete, isTrue);
      expect(DriveItem.fromJson(it.toJson()).toJson(), it.toJson());
      expect(parentOf('/x'), '/');
      expect(parentOf('/'), '/');
      expect(joinPath('/', 'a'), '/a');
      expect(joinPath('/a', 'b'), '/a/b');
    });

    test('kindOf theo mime và đuôi', () {
      DriveItem f(String name, [String mime = '']) => DriveItem(path: '/$name', name: name, dir: false, mime: mime);
      expect(kindOf(f('a.docx')), DriveKind.doc);
      expect(kindOf(f('a.XLSX')), DriveKind.sheet);
      expect(kindOf(f('a.pptx')), DriveKind.slide);
      expect(kindOf(f('a.bin', 'application/pdf')), DriveKind.pdf);
      expect(kindOf(f('a.jpg', 'image/jpeg')), DriveKind.image);
      expect(kindOf(f('a.mp4', 'video/mp4')), DriveKind.video);
      expect(kindOf(DriveItem(path: '/d', name: 'd', dir: true)), DriveKind.folder);
      expect(isOffice(f('a.docx')), isTrue);
      expect(canPreview(f('a.md')), isTrue);
      expect(canPreview(f('a.zip')), isFalse);
    });

    test('officeLinkOf: trang soạn nhanh và trang soạn Nextcloud', () {
      expect(officeLinkOf(Uri.parse('https://drive.example/drive/edit.html?id=860&path=%2FA%2Fb.xlsx')), (860, '/A/b.xlsx'));
      expect(officeLinkOf(Uri.parse('https://drive.example/apps/onlyoffice/42?filePath=%2Fc.docx')), (42, '/c.docx'));
      expect(officeLinkOf(Uri.parse('https://drive.example/index.php/apps/onlyoffice/7')), (7, ''));
      expect(officeLinkOf(Uri.parse('https://drive.example/apps/onlyoffice/ajax/new')), isNull);
      expect(officeLinkOf(Uri.parse('https://drive.example/drive/')), isNull);
    });
    test('fmtSize / fmtDate', () {
      expect(fmtSize(0), '0 B');
      expect(fmtSize(284 * 1024), '284 KB');
      expect(fmtSize((4.1 * 1024 * 1024).round()), '4,1 MB');
      final now = DateTime(2026, 11, 15, 12);
      int sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
      expect(fmtDate(sec(DateTime(2026, 11, 15, 10, 12)), now: now), '10:12');
      expect(fmtDate(sec(DateTime(2026, 11, 14, 9)), now: now), 'Hôm qua');
      expect(fmtDate(sec(DateTime(2026, 11, 2)), now: now), '2 thg 11');
      expect(fmtDate(sec(DateTime(2025, 1, 3)), now: now), '3 thg 1, 2025');
    });
  });

  group('tải lên chia khúc', () {
    test('chunkPlan chia đúng và bỏ khúc đã có', () {
      const mb = 1024 * 1024;
      final plan = chunkPlan(25 * mb, 10 * mb);
      expect(plan, [(1, 0, 10 * mb), (2, 10 * mb, 10 * mb), (3, 20 * mb, 5 * mb)]);
      // Khúc 1 đủ, khúc 2 dở (kích thước sai) thì gửi lại khúc 2.
      expect(chunkPlan(25 * mb, 10 * mb, {1: 10 * mb, 2: 3}), [(2, 10 * mb, 10 * mb), (3, 20 * mb, 5 * mb)]);
      expect(chunkPlan(0, 10 * mb), [(1, 0, 0)]);
    });

    test('UploadJob lưu / nạp lại: việc đang chạy thành chờ', () {
      final j = UploadJob(id: '1', src: '/tmp/a', name: 'a.mp4', dir: '/X', size: 100)
        ..state = UploadState.running
        ..sent = 40
        ..session = 'fd-abc'
        ..target = '/X/a.mp4';
      final back = UploadJob.fromJson(jsonDecode(jsonEncode(j.toJson())) as Map);
      expect(back.state, UploadState.queued);
      expect(back.session, 'fd-abc');
      expect(back.sent, 40);
      expect(back.progress, .4);
    });
  });

  group('API', () {
    test('gửi vé, thử lại một lần khi 401, đọc lỗi JSON', () async {
      var calls = 0;
      final refreshes = <bool>[];
      final api = DriveApi(
        base: 'https://chat.example/__apps/drive',
        ticketFn: (r) async {
          refreshes.add(r);
          return r ? 'new' : 'old';
        },
        client: MockClient((req) async {
          calls++;
          expect(req.url.path, '/__apps/drive/api/list');
          expect(req.url.queryParameters['path'], '/Thư mục');
          if (req.headers['Authorization'] == 'Bearer old') return http.Response.bytes(utf8.encode('{"error":"vé hết hạn"}'), 401);
          return http.Response(jsonEncode({'items': driveFixture()}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      final items = await api.list('/Thư mục');
      expect(calls, 2);
      expect(refreshes, [false, true]);
      expect(items.first.name, 'Hợp đồng 2026');
      final bad = DriveApi(base: 'https://x', ticketFn: (_) async => 't', client: MockClient((_) async => http.Response.bytes(utf8.encode('{"error":"không có"}'), 404)));
      expect(() => bad.info(path: '/a'), throwsA(isA<DriveException>().having((e) => e.message, 'message', 'không có')));
    });
  });

  testWidgets('Drive: danh sách, chọn nhiều, mở thư mục', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = DriveSession(api: fakeDriveApi(), key: 'test-${DateTime.now().microsecondsSinceEpoch}', app: null, chatToken: 't');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: DriveHome(session: s)));
    await tester.pumpAndSettle();
    expect(find.text('Báo cáo doanh thu Q3.xlsx'), findsOneWidget);
    expect(find.text('Mới'), findsOneWidget);
    // Chạm giữ: chọn; thanh chọn hiện số mục.
    await tester.longPress(find.text('Pitch deck 2027.pptx'));
    await tester.pump();
    expect(find.text('Đã chọn 1'), findsOneWidget);
    await tester.tap(find.text('Biên bản họp 14-11.docx'));
    await tester.pump();
    expect(find.text('Đã chọn 2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();
    // Mở thư mục: đường dẫn hiện, nút quay lại.
    await tester.tap(find.text('Hợp đồng 2026'));
    await tester.pumpAndSettle();
    expect(find.text('Hợp đồng 2026'), findsWidgets);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
  });

  testWidgets('Drive máy tính: kéo chuột quét chọn, bấm chỗ trống bỏ chọn, Ctrl+C rồi Ctrl+V dán vào thư mục khác', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reqs = <http.Request>[];
    final s = DriveSession(api: fakeDriveApi(onRequest: reqs.add), key: 'test-${DateTime.now().microsecondsSinceEpoch}', app: null, chatToken: 't');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: DriveHome(session: s)));
    await tester.pumpAndSettle();
    final a = tester.getCenter(find.text('Báo cáo doanh thu Q3.xlsx')), b = tester.getCenter(find.text('Biên bản họp 14-11.docx'));
    final top = a.dy < b.dy ? a : b, bottom = a.dy < b.dy ? b : a;
    // Kéo chuột từ dòng trên xuống dòng dưới: chọn mọi dòng ở giữa.
    final g = await tester.startGesture(top.translate(200, 0), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await g.moveTo(top.translate(210, 12));
    await g.moveTo(bottom.translate(220, 0));
    await tester.pump();
    await g.up();
    await tester.pump();
    final n = int.parse(RegExp(r'Đã chọn (\d+)').firstMatch(tester.widgetList<Text>(find.textContaining('Đã chọn')).first.data!)!.group(1)!);
    expect(n, greaterThanOrEqualTo(2));
    // Ctrl+C, mở thư mục, Ctrl+V: gọi copy tới thư mục đó.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(s.clip.length, n);
    expect(s.clipCut, isFalse);
    // Bấm chỗ trống (dưới danh sách): bỏ chọn.
    final empty = Offset(top.dx + 200, 880);
    final c = await tester.startGesture(empty, kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await c.up();
    await tester.pump();
    expect(find.textContaining('Đã chọn'), findsNothing);
    // Chọn thư mục rồi Enter để mở.
    await tester.tap(find.text('Hợp đồng 2026'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('Dán $n mục'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final copy = reqs.where((r) => r.url.path.endsWith('/api/copy')).single;
    final body = jsonDecode(copy.body) as Map;
    expect((body['items'] as List).length, n);
    expect(body['to'], '/Hợp đồng 2026');
  });
  for (final (name, size, dialog) in [('máy tính', const Size(1440, 900), true), ('điện thoại', const Size(390, 844), false)]) {
    testWidgets('Chọn thư mục Drive ($name): ${dialog ? 'hộp thoại giữa màn hình' : 'trang toàn màn hình'}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = DriveSession(api: fakeDriveApi(), key: 'test-${DateTime.now().microsecondsSinceEpoch}', app: null, chatToken: 't');
      String? picked = 'chưa';
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => picked = await pickDriveFolder(c, s, title: 'Lưu "a.pdf" vào Drive', ok: 'Lưu vào đây'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final d = find.byKey(const ValueKey('drive-folder-dialog'));
      expect(d, dialog ? findsOneWidget : findsNothing);
      if (dialog) {
        final r = tester.getRect(find.descendant(of: d, matching: find.byType(Scaffold)));
        expect((r.center - const Offset(720, 450)).distance, lessThan(2));
        expect(r.width, lessThanOrEqualTo(560));
      }
      expect(find.text('Lưu "a.pdf" vào Drive'), findsOneWidget);
      await tester.tap(find.text('Lưu vào đây'));
      await tester.pumpAndSettle();
      expect(picked, '/');
      expect(find.text('Lưu "a.pdf" vào Drive'), findsNothing);
    });
  }

  testWidgets('Drive máy tính: nhấn chuột chọn ngay (không chờ nhấp đúp), nhấn hai lần mở thư mục', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = DriveSession(api: fakeDriveApi(), key: 'test-${DateTime.now().microsecondsSinceEpoch}', app: null, chatToken: 't');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: DriveHome(session: s)));
    await tester.pumpAndSettle();
    final g = await tester.startGesture(tester.getCenter(find.text('Báo cáo doanh thu Q3.xlsx')), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await tester.pump(); // một khung hình, chưa nhả chuột
    expect(find.text('Đã chọn 1'), findsOneWidget);
    await g.up();
    await tester.pump(const Duration(milliseconds: 600));
    final f = tester.getCenter(find.text('Hợp đồng 2026'));
    await tester.tapAt(f, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(f, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing); // máy tính: đường dẫn ở thanh breadcrumb
    expect(find.text('Hợp đồng thang máy 01.pdf'), findsOneWidget);
  });

  testWidgets('Bảng tiến độ: đang tải (%, tốc độ, 2/3 mục, nén thư mục), xong có nút mở', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = DriveSession(api: fakeDriveApi(), key: 'test-${DateTime.now().microsecondsSinceEpoch}', app: null, chatToken: 't');
    final run = DriveDownload(3)
      ..done = 1
      ..name = 'Báo cáo.xlsx'
      ..got = 512 * 1024
      ..total = 1024 * 1024
      ..speed = 2 * 1024 * 1024;
    final zip = DriveDownload(1)
      ..name = 'Hợp đồng 2026.zip'
      ..zipping = true
      ..got = 300 * 1024;
    s.downloads.list.addAll([run, zip]);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Align(alignment: Alignment.bottomRight, child: SizedBox(width: 380, child: TransfersPanel(session: s, wide: true))))));
    await tester.pump();
    expect(find.text('Đang tải xuống'), findsOneWidget);
    expect(find.textContaining('2/3 mục · 50%'), findsOneWidget);
    expect(find.textContaining(RegExp(r'2(,0)? MB/s')), findsOneWidget);
    expect(find.textContaining('Đang nén thư mục'), findsOneWidget);
    s.downloads.list.clear();
    s.downloads.list.add(DriveDownload(1)
      ..state = DownloadState.done
      ..dir = '/tmp/Downloads'
      ..files.add(File('/tmp/Downloads/Báo cáo.xlsx')));
    s.downloads.changed();
    await tester.pump();
    expect(find.text('Đã tải xuống'), findsOneWidget);
    expect(find.text('Mở thư mục'), findsOneWidget);
    expect(find.text('Mở tệp'), findsOneWidget);
  });

  testWidgets('Office mở bản xem trong Drive (không mở trình soạn); máy tính có nút Chỉnh sửa', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final reqs = <http.Request>[];
    final s = DriveSession(api: fakeDriveApi(onRequest: reqs.add), key: 'test-${DateTime.now().microsecondsSinceEpoch}', app: null, chatToken: 't');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: DriveHome(session: s)));
    await tester.pumpAndSettle();
    final f = tester.getCenter(find.text('Báo cáo doanh thu Q3.xlsx'));
    await tester.tapAt(f, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(f, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DrivePreviewPage), findsOneWidget);
    expect(find.text('Chỉnh sửa'), findsOneWidget); // máy chạy test là máy tính (Linux)
    // Không mở trình soạn (không có tab / trang OnlyOffice).
    expect(reqs.any((r) => r.url.path.contains('onlyoffice')), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(DrivePreviewPage), findsNothing);
  });
}
