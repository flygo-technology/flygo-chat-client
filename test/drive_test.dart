import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/drive/api.dart';
import 'package:flygo_chat/ui/drive/drive_page.dart';
import 'package:flygo_chat/ui/drive/look.dart';
import 'package:flygo_chat/ui/drive/session.dart';
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
}
