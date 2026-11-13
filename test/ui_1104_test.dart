import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/file_card.dart';
import 'package:flygo_chat/ui/forward_page.dart';
import 'package:flygo_chat/ui/home_page.dart' show youAppGroups;
import 'package:flygo_chat/ui/multi_select.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

/// Trang chuyển tiếp 2 tab, Ctrl/Cmd+bấm chọn nhiều tin, thẻ tệp đính kèm, nhóm ô ở tab Bạn (dữ liệu giả, không gọi mạng).
void main() {
  // Id kiểu máy chủ: 26 ký tự [a-z0-9].
  String id(String s) => s.padRight(26, '0');
  final me = id('me'), bot = id('bot'), lan = id('lan'), dm = id('dmbot'), dmLan = id('dmlan'), grp = id('grp');

  AppState makeApp() {
    final app = AppState('test')..me = MmUser({'id': me, 'username': 'me', 'first_name': 'Tôi'});
    app.users[me] = app.me!;
    app.users[lan] = MmUser({'id': lan, 'username': 'lan', 'first_name': 'Lan'});
    app.users[bot] = MmUser({
      'id': bot,
      'username': 'coca',
      'first_name': 'Coca',
      'is_bot': true,
      'bot_description': '[flygo-agent engine=claude allow=$me]',
    });
    app.channels[grp] = MmChannel({'id': grp, 'name': 'nhom', 'display_name': 'Nhóm kế toán', 'type': 'P'});
    app.channels[dmLan] = MmChannel({'id': dmLan, 'name': '${me}__$lan', 'type': 'D'});
    app.channels[dm] = MmChannel({'id': dm, 'name': '${me}__$bot', 'type': 'D'});
    final s = id('sess');
    app.channels[s] = MmChannel({'id': s, 'name': 'a-$dm-$me-ab12', 'display_name': 'AI · Coca · Báo cáo thuế', 'type': 'P'});
    return app;
  }

  Widget wrap(AppState app, Widget child, {Brightness b = Brightness.light}) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(theme: buildTheme(b), home: Scaffold(body: child)),
      );

  MmPost post(String pid, String channel, {String user = ''}) =>
      MmPost({'id': pid, 'channel_id': channel, 'user_id': user, 'message': 'tin $pid', 'create_at': 1});

  group('ForwardPage', () {
    testWidgets('tab Chat: nhóm + chat với người, không có chat với trợ lý', (t) async {
      final app = makeApp();
      await t.pumpWidget(wrap(app, ForwardPage(post: post('p1', grp))));
      await t.pump();
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Trợ lý'), findsOneWidget);
      expect(find.text('Nhóm kế toán'), findsOneWidget);
      expect(find.text('Lan'), findsOneWidget);
      expect(find.text('Coca'), findsNothing);
    });

    testWidgets('tab Trợ lý: mục theo trợ lý, thu gọn / mở, chọn phiên', (t) async {
      final app = makeApp();
      await t.pumpWidget(wrap(app, ForwardPage(post: post('p1', grp)), b: Brightness.dark));
      await t.tap(find.text('Trợ lý'));
      await t.pumpAndSettle();
      expect(find.text('Coca'), findsOneWidget);
      // Một trợ lý: mở sẵn.
      expect(find.text('Chat chính'), findsOneWidget);
      expect(find.text('Báo cáo thuế'), findsOneWidget);
      await t.tap(find.text('Báo cáo thuế'));
      await t.pump();
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      // Thu gọn.
      await t.tap(find.text('Coca'));
      await t.pump();
      expect(find.text('Chat chính'), findsNothing);
      expect(find.text('1 phiên · đã chọn 1'), findsOneWidget);
    });

    test('forwardAgentGroups gom phiên theo trợ lý', () {
      final g = forwardAgentGroups(makeApp(), const {});
      expect(g, hasLength(1));
      expect(g.first.bot.id, bot);
      expect(g.first.dm?.id, dm);
      expect(g.first.sessions.map((c) => c.aiTitle), ['Báo cáo thuế']);
    });
  });

  group('Ctrl/Cmd+bấm chọn nhiều tin', () {
    final posts = [for (var i = 1; i <= 4; i++) post('m$i', grp)];
    Widget list(AppState app) => wrap(
        app,
        Column(children: [
          for (final p in posts)
            MultiSelectClick(post: p, ordered: () => posts, child: SizedBox(height: 40, width: 200, child: Text(p.message))),
          if (app.selectedPosts.isNotEmpty) const SelectionEscape(child: SizedBox()),
        ]));

    Future<void> click(WidgetTester t, String text) async {
      await t.tap(find.text(text), kind: PointerDeviceKind.mouse);
      await t.pump();
    }

    testWidgets('Ctrl+bấm chọn / bỏ chọn, Shift+bấm chọn đoạn, Esc thoát', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final app = makeApp();
      await t.pumpWidget(list(app));
      await click(t, 'tin m1');
      expect(app.selectedPosts, isEmpty);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await click(t, 'tin m1');
      expect(app.selectedPosts, {'m1'});
      await click(t, 'tin m2');
      await click(t, 'tin m2');
      expect(app.selectedPosts, {'m1'});
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      // Bong bóng nhận onTap ngay sau đó: đã xử lý rồi thì bỏ qua.
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await click(t, 'tin m4');
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(app.selectedPosts, {'m1', 'm2', 'm3', 'm4'});
      expect(consumeSelectClick('m4'), isTrue);
      expect(consumeSelectClick('m4'), isFalse);
      await t.pumpWidget(list(app));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(app.selectedPosts, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('macOS dùng Cmd, không dùng Ctrl', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final app = makeApp();
      await t.pumpWidget(list(app));
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await click(t, 'tin m1');
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(app.selectedPosts, isEmpty);
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await click(t, 'tin m3');
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(app.selectedPosts, {'m3'});
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Thẻ tệp đính kèm', () {
    test('cỡ tệp dễ đọc', () {
      expect(humanSize(512), '512 B');
      expect(humanSize(1024), '1 KB');
      expect(humanSize(1536), '1.5 KB');
      expect(humanSize(200 * 1024), '200 KB');
      expect(humanSize(5 * 1024 * 1024 + 300 * 1024), '5.3 MB');
      expect(humanSize(3 * 1024 * 1024 * 1024), '3 GB');
    });

    test('loại tệp, rút gọn tên ở giữa, tên lưu không trùng', () {
      expect(fileKindOf('a.PDF', ''), FileKind.pdf);
      expect(fileKindOf('b.xlsx', ''), FileKind.sheet);
      expect(fileKindOf('c.pptx', ''), FileKind.slide);
      expect(fileKindOf('d.docx', ''), FileKind.doc);
      expect(fileKindOf('e.zip', ''), FileKind.archive);
      expect(fileKindOf('f.ts', ''), FileKind.code);
      expect(fileKindOf('g', 'audio/mpeg'), FileKind.audio);
      expect(fileKindOf('h.bin', 'application/octet-stream'), FileKind.generic);
      final long = 'bao-cao-thue-quy-3-nam-2026-ban-cuoi-cung-da-duyet.pdf';
      final short = middleEllipsis(long);
      expect(short.length, 36);
      expect(short, startsWith('bao-cao'));
      expect(short, endsWith('.pdf'));
      expect(short, contains('…'));
      final taken = {'/d/a.pdf', '/d/a (1).pdf'};
      expect(uniqueSavePath('/d', 'a.pdf', exists: taken.contains), '/d/a (2).pdf'.replaceAll('/', Platform.pathSeparator));
      expect(uniqueSavePath('/d', 'x', exists: (_) => false), '/d/x'.replaceAll('/', Platform.pathSeparator));
    });

    final file = MmFile({'id': 'f1', 'name': 'hop-dong.pdf', 'size': 2 * 1024 * 1024, 'mime_type': 'application/pdf'});

    testWidgets('máy tính: Lưu / Mở file, tiến độ, sau khi lưu có Mở thư mục', (t) async {
      final done = Completer<File>();
      late void Function(int, int) report;
      final dir = Directory.systemTemp.createTempSync('fc');
      await t.pumpWidget(wrap(
          makeApp(),
          FileCard(
            file: file,
            desktop: true,
            saveDir: () async => dir,
            downloader: (f, out, p) {
              report = p;
              return done.future.then((_) => out);
            },
          )));
      expect(find.text('hop-dong.pdf'), findsOneWidget);
      expect(find.text('Tài liệu PDF · 2 MB'), findsOneWidget);
      expect(find.text('Lưu'), findsOneWidget);
      expect(find.text('Mở file'), findsOneWidget);
      expect(find.text('Mở thư mục'), findsNothing);
      await t.tap(find.text('Lưu'));
      await t.pump();
      report(1024 * 1024, 2 * 1024 * 1024);
      await t.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('50% · 1 MB / 2 MB'), findsOneWidget);
      done.complete(File('x'));
      await t.pump();
      await t.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Mở thư mục'), findsOneWidget);
      dir.deleteSync(recursive: true);
    });

    testWidgets('điện thoại: Lưu / Mở, tối', (t) async {
      await t.pumpWidget(wrap(makeApp(), FileCard(file: MmFile({'id': 'f2', 'name': 'a.zip', 'size': 300, 'mime_type': ''}), desktop: false),
          b: Brightness.dark));
      expect(find.text('Lưu'), findsOneWidget);
      expect(find.text('Mở'), findsOneWidget);
      expect(find.text('Mở file'), findsNothing);
      expect(find.text('Tệp nén · 300 B'), findsOneWidget);
      expect(find.byIcon(Icons.folder_zip_rounded), findsOneWidget);
    });
  });

  group('Tab Bạn', () {
    test('Trợ lý và Bot ở nhóm Cá nhân, không còn Hẹn giờ / Tự động hoá', () {
      final g = youAppGroups(desktop: true);
      expect(g.map((e) => e.$1), ['Công việc', 'Cá nhân']);
      final personal = g[1].$2;
      expect(personal, containsAll(['assistants', 'bots']));
      expect(personal.indexOf('assistants'), lessThan(personal.indexOf('language')));
      expect(g.expand((e) => e.$2), isNot(contains('schedules')));
      expect(personal, isNot(contains('qr')));
      expect(youAppGroups(desktop: false)[1].$2, contains('qr'));
      // Máy tính của chính mình (điều khiển từ xa) nằm trong nhóm Công việc.
      expect(g[0].$2, ['contacts', 'org', 'delegations', 'calls', 'computers']);
    });
  });
}
