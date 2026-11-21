// Máy tính: panel bên phải của cuộc họp (một thanh tab Trang / Chat / AI / Thành viên / Thông tin), dựng CallScreen thật
// với cuộc họp giả và relay giả. Ảnh xem trước (chạy tay): PANEL_OUT=<thư mục> flutter test test/pages_panel_preview_test.dart
// Ảnh trang tài liệu: TATCA_PDF=<thư mục có tiendo.pdf, hopdong.pdf, kehoach.pdf>.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/calls/call_service.dart';
import 'package:flygo_chat/calls/meet_room.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/local_store.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/call_screen.dart';
import 'package:flygo_chat/ui/meet/knock_center.dart';
import 'package:flygo_chat/ui/meet/meet_panel_prefs.dart';
import 'package:flygo_chat/ui/pages/page_thumb.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final mat = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f);
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('MaterialIcons', ['$mat/MaterialIcons-Regular.otf']);
  // Theme của app dùng 'Noto Sans' trên Linux: nạp Inter dưới các tên đó để chữ hiện thật.
  for (final fam in ['Flygo Inter', 'Noto Sans', 'Roboto']) {
    await load(fam, [for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$f.ttf']);
  }
}

const _ch = 'cccccccccccccccccccccccccc';
final _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _p(String id, String type, String title, String owner, String name,
        {String vis = 'meeting', int secs = 0, int order = 0, Map<String, dynamic>? file, Map<String, dynamic> content = const {}}) =>
    {
      'id': id, 'type': type, 'title': title, 'owner': owner, 'owner_name': name, 'meeting': 'abc-defg-hij', 'visibility': vis, 'seconds': secs, 'order': order,
      'rev': 2, 'created_at': order, 'updated_at': order, 'content': {...content, 'file': ?file}, 'file': ?file,
    };
Map<String, dynamic> _f(String id, String name, int pages) => {'id': id, 'url': '/meet/livekit/pagefile/$id.pdf', 'name': name, 'pages': pages};

final _pages = [
  _p('p1', 'agenda', 'Chương trình họp', 'loi', 'Nguyễn Văn Lợi', secs: 300, order: 0, content: {
    'items': [
      {'text': 'Tiến độ tòa B', 'who': 'Lợi', 'minutes': 10},
      {'text': 'Hợp đồng tháng 11', 'who': 'Kim', 'minutes': 8},
      {'text': 'An toàn lao động', 'who': 'Minh', 'minutes': 5},
      {'text': 'Hỏi đáp', 'minutes': 7},
    ],
  }),
  _p('p2', 'doc', 'Tiến độ lắp đặt tòa B', 'loi', 'Nguyễn Văn Lợi', secs: 600, order: 1, file: _f('tiendo', 'TienDo.pptx', 2)),
  _p('p3', 'poll', 'Chọn ngày bàn giao', 'loi', 'Nguyễn Văn Lợi', secs: 120, order: 2),
  _p('p4', 'doc', 'Hợp đồng T11', 'kim', 'Mai Kim', secs: 480, order: 0, file: _f('hopdong', 'HopDong.xlsx', 2)),
  _p('p5', 'qa', 'Hỏi đáp báo giá', 'kim', 'Mai Kim', order: 1),
  _p('p6', 'welcome', 'Chào mừng', 'me', 'Dương Văn Ba', order: 0, content: {'heading': 'Giao ban tháng 12', 'subtitle': 'Chào mừng mọi người, 9:00 bắt đầu'}),
  _p('p7', 'doc', 'Kế hoạch Q4', 'me', 'Dương Văn Ba', vis: 'private', secs: 360, order: 1, file: _f('kehoach', 'KeHoachQ4.pptx', 2)),
  _p('p8', 'minutes', 'Biên bản giao ban', 'me', 'Dương Văn Ba', order: 2),
  _p('p9', 'video', 'Video lắp ray dẫn hướng', 'minh', 'Lê Minh', secs: 165, order: 0),
];

final _counts = {
  'loi': {'name': 'Nguyễn Văn Lợi', 'pages': 3, 'private': 0, 'seconds': 1020},
  'kim': {'name': 'Mai Kim', 'pages': 2, 'private': 0, 'seconds': 480},
  'me': {'name': 'Dương Văn Ba', 'pages': 3, 'private': 1, 'seconds': 360},
  'minh': {'name': 'Lê Minh', 'pages': 1, 'private': 0, 'seconds': 165},
  'quang': {'name': 'Trần Quang', 'pages': 3, 'private': 3, 'seconds': 1080},
};

final _views = <String, Map<String, dynamic>>{
  'p1': {'current': 1, 'started_at': 0},
  'p3': {
    'kind': 'poll', 'title': 'Chọn ngày bàn giao', 'anon': false, 'live': true, 'current': 0, 'reveal': false, 'closed': false, 'voters': 12,
    'questions': [
      {'id': 'q', 'text': 'Ngày nào bàn giao tòa B?', 'multi': false, 'options': [{'id': 'a', 'text': 'Thứ Ba 25/11'}, {'id': 'b', 'text': 'Thứ Sáu 28/11'}, {'id': 'c', 'text': 'Thứ Ba 02/12'}]},
    ],
    'mine': {}, 'results': {'q': {'total': 12, 'options': {'a': 7, 'b': 3, 'c': 2}}},
  },
  'p8': {
    'text': '1. Tiến độ tòa B: đạt 70%, chậm 4 ngày do thiếu ray.\n2. Hợp đồng tháng 11: 12 mới, 3 gia hạn.', 'edited_by': 'Mai Kim', 'edited_at': 1, 'closed': false,
    'tasks': [{'id': 't1', 'text': 'Xác nhận lịch giao ray', 'who': '@quang', 'due': '20/11', 'done': false}],
  },
  'p5': {
    'title': 'Hỏi đáp báo giá', 'desc': 'Câu hỏi về báo giá thang tòa B', 'allow_anon': true, 'can_manage': false, 'total': 3, 'open': 2,
    'questions': [
      {'id': 'x1', 'text': 'Giá ray dẫn hướng nhập tháng 11 đã gồm vận chuyển tới công trình chưa?', 'anon': true, 'by_name': '', 'votes': 9, 'voted': true, 'mine': false, 'answered': true, 'pinned': true, 'hidden': false, 'at': 1,
        'answers': [{'id': 'a1', 'text': 'Đã gồm vận chuyển tới chân công trình, chưa gồm cẩu.', 'by_name': 'Mai Kim', 'at': 2, 'accepted': true, 'mine': false}]},
      {'id': 'x2', 'text': 'Báo giá sửa đổi gửi khách khi nào?', 'anon': false, 'by_name': 'Lê Minh', 'votes': 4, 'voted': false, 'mine': false, 'answered': false, 'pinned': false, 'hidden': false, 'at': 3, 'answers': []},
    ],
  },
  'p7': {'page': 1},
};

http.Client _relay({required bool host}) => MockClient((req) async {
      final p = req.url.path;
      final pdf = RegExp(r'^/meet/livekit/pagefile/(\w+)\.pdf$').firstMatch(p);
      if (pdf != null) {
        final f = File('${Platform.environment['TATCA_PDF'] ?? '/nonexistent'}/${pdf.group(1)}.pdf');
        return f.existsSync() ? http.Response.bytes(f.readAsBytesSync(), 200, headers: {'content-type': 'application/pdf'}) : http.Response('', 404);
      }
      Map<String, dynamic>? body;
      if (p == '/meet/pages' && req.method == 'GET') {
        final scope = req.url.queryParameters['scope'];
        final all = scope == 'all';
        final list = _pages.where((x) => scope == 'mine' ? x['owner'] == 'me' : scope == 'public' ? x['owner'] != 'me' && x['visibility'] != 'private' : true).toList();
        body = {'pages': list, if (all && host) 'counts': _counts};
      } else if (p.startsWith('/meet/pages/')) {
        final id = p.split('/').last;
        final pg = _pages.firstWhere((x) => x['id'] == id);
        body = {'page': pg, 'rev': 2, 'view': _views[id] ?? {}, 'role': pg['owner'] == 'me' ? 'owner' : 'member'};
      }
      return http.Response(jsonEncode(body ?? {'error': 'not found'}), body == null ? 404 : 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });


AppState _app() {
  final app = AppState('t');
  final names = {'me': ('Ba', 'Dương Văn'), 'loi': ('Lợi', 'Nguyễn Văn'), 'kim': ('Kim', 'Mai'), 'minh': ('Minh', 'Lê'), 'quang': ('Quang', 'Trần')};
  for (final e in names.entries) {
    app.users[e.key] = MmUser({'id': e.key, 'username': e.key, 'first_name': e.value.$2, 'last_name': e.value.$1});
  }
  app.me = app.users['me'];
  app.channels[_ch] = MmChannel({'id': _ch, 'name': 'hop-abc-defg-hij', 'display_name': 'Giao ban tháng 12', 'type': 'P', 'team_id': 't'});
  final c = app.calls;
  c.debugMeeting(_ch, [
    CallParticipant('s1', 'loi')..unmuted = true..speaking = true,
    CallParticipant('s2', 'kim'),
    CallParticipant('s3', 'minh')..raisedHand = true,
    CallParticipant('s4', 'quang')..unmuted = true,
  ], info: const MeetingInfo(postId: 'p', creatorId: 'me', title: 'Giao ban tháng 12', code: 'abc-defg-hij'));
  c.liveKit = true;
  c.scribeAvailable = true;
  c.roomHost = 'me';
  c.roomStage = {
    'presenter': 'loi', 'presenter_name': 'Nguyễn Văn Lợi', 'queue': [{'id': 'kim', 'name': 'Mai Kim', 'at': 1}],
    'page': 'p1', 'page_type': 'agenda', 'page_title': 'Chương trình họp', 'key': 'k', 'mode': 'auto', 'ends_at': _now + 252000, 'paused': false, 'at': _now,
  };
  return app;
}

MeetRoom _room() {
  final r = MeetRoom(channelId: _ch, token: 't', server: '', myId: 'me', onMuteMe: () {}, connect: false);
  r.debugApply({
    'type': 'state',
    'you': {'host': true},
    'state': {
      'comments': [
        {'from': {'user_id': 'quang', 'name': 'Trần Quang'}, 'text': 'Ray về ngày 25 chưa anh?', 'at': _now - 60000},
        {'from': {'user_id': 'loi', 'name': 'Nguyễn Văn Lợi'}, 'text': 'Chắc chắn 25/11, nhà cung cấp đã xác nhận.', 'at': _now - 30000},
      ],
    },
  });
  return r;
}

void main() {
  final out = Platform.environment['PANEL_OUT'];
  final shotKey = GlobalKey();
  Future<void> snap(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  setUpAll(() async {
    await _fonts();
    final lib = File('build/native_assets/linux/libpdfium.so');
    if (lib.existsSync()) Pdfrx.pdfiumModulePath = lib.absolute.path;
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global', 'xyz.luan/audioplayers.global/events']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });

  testWidgets('máy tính: panel bên phải có tab, Trang / Chat / Thành viên / xem trang', (t) async {
    debugIsDesktop = true;
    MeetPanelPrefs.debugSet(width: 430, tab: 'pages');
    CallScreen.debugRoom = (_) => _room();
    final dir = Platform.environment['TATCA_PDF'];
    if (dir != null) {
      await t.runAsync(() async {
        for (final id in ['tiendo', 'hopdong', 'kehoach']) {
          final f = File('$dir/$id.pdf');
          if (!f.existsSync()) continue;
          seedPdfBytes(id, f.readAsBytesSync());
          await pdfThumb(id, '/meet/livekit/pagefile/$id.pdf', 1);
        }
      });
    }
    await http.runWithClient(() async {
      final app = _app();
      // Tab Chat nhúng trang chat thật: cần kho tin trên máy (trong bộ nhớ khi test).
      await t.runAsync(() async => app.debugSetStore(await LocalStore.memory('panel-chat')));
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.dark),
          builder: (c, nav) => RepaintBoundary(key: shotKey, child: DefaultTextStyle.merge(style: const TextStyle(fontFamily: 'Flygo Inter'), child: nav!)),
          home: const CallScreen(),
        ),
      ));
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      await settle();
      expect(find.byTooltip('Tương tác, thành viên, màn hình, chat, AI'), findsOneWidget);
      expect(find.text('Dương Văn Ba (bạn)'), findsOneWidget);
      await snap(t, 'd1-tab-trang');

      await t.tap(find.text('Hỏi đáp báo giá').last);
      await settle();
      expect(find.text('Về sân khấu'), findsOneWidget);
      await snap(t, 'd2-xem-trang');
      await t.tap(find.text('Về sân khấu'));
      await settle();

      await t.tap(find.text('Chat').last);
      await settle();
      await snap(t, 'd3-tab-chat');

      await t.tap(find.byTooltip('Thành viên').first);
      await settle();
      expect(find.textContaining('TRONG CUỘC HỌP'), findsOneWidget);
      await snap(t, 'd4-tab-thanh-vien');

      await t.tap(find.text('Màn hình').last);
      await settle();
      await snap(t, 'd5-tab-man-hinh');

      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      app.calls.debugMeeting(_ch, const []);
    }, () => _relay(host: true));
    debugIsDesktop = null;
    CallScreen.debugRoom = null;
  });

  for (final (name, size, desktop) in [('n1-may-tinh-hep', const Size(430, 895), true), ('p1-dien-thoai', const Size(390, 844), false)]) {
    testWidgets('thanh nút mới: $name (hai hàng nút, Cài đặt, Apps)', (t) async {
      debugIsDesktop = desktop;
      MeetPanelPrefs.debugSet(width: 400, tab: '');
      CallScreen.debugRoom = (_) => _room();
      await http.runWithClient(() async {
        final app = _app();
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.dark),
            builder: (c, nav) => RepaintBoundary(key: shotKey, child: nav!),
            home: const CallScreen(),
          ),
        ));
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        await settle();
        expect(find.byTooltip('Tương tác, thành viên, màn hình, chat, AI'), findsOneWidget);
        expect(find.byTooltip('Cài đặt'), findsNothing);
        await snap(t, '$name-1-thanh-nut');
        await t.tap(find.byTooltip('Tương tác, thành viên, màn hình, chat, AI'));
        await settle();
        await snap(t, '$name-2-tuong-tac');
        await t.tap(find.text('Thành viên').last);
        await settle();
        expect(find.text('Mời thành viên'), findsOneWidget);
        expect(find.textContaining('Mời khách'), findsOneWidget);
        await snap(t, '$name-3-thanh-vien');
        await t.tap(find.text('Màn hình').last);
        await settle();
        await snap(t, '$name-4-man-hinh');
        if (!desktop) {
          await t.tap(find.text('Thành viên').last);
          await settle();
          await t.tap(find.text('Tắt mic mọi người…'));
          await settle();
          expect(find.text('Tắt hẳn'), findsOneWidget);
          await snap(t, '$name-5-mute');
          await t.tap(find.text('Giữ nguyên'));
          await settle();
          await t.tap(find.text('Tương tác').last);
          await settle();
          await t.tap(find.byTooltip('Apps: thêm trang, trình chiếu'));
          await settle();
          expect(find.text('Trình chiếu'), findsWidgets);
          await snap(t, '$name-6-apps');
          Navigator.of(t.element(find.byType(CallScreen))).popUntil((r) => r.isFirst);
          await settle();
          // Điện thoại: thanh nút tự ẩn sau vài giây, chạm màn hình để hiện lại.
          if (find.byTooltip('Giơ tay, thả cảm xúc').hitTestable().evaluate().isEmpty) {
            await t.tapAt(const Offset(195, 400));
            await settle();
          }
          await t.tap(find.byTooltip('Giơ tay, thả cảm xúc'));
          await settle();
          expect(find.text('✋'), findsWidgets);
          await snap(t, '$name-7-cam-xuc');
          await t.tapAt(const Offset(195, 300));
          await settle();
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 3));
        app.calls.debugMeeting(_ch, const []);
      }, () => _relay(host: true));
      debugIsDesktop = null;
      CallScreen.debugRoom = null;
    });
  }

  testWidgets('trang hệ thống: hàng Hệ thống, Chờ lượt trình chiếu, Chào mừng nhiều tuỳ chọn', (t) async {
    debugIsDesktop = true;
    MeetPanelPrefs.debugSet(width: 460, tab: 'pages');
    CallScreen.debugRoom = (_) => _room();
    await http.runWithClient(() async {
      final app = _app();
      app.calls.roomStage = {
        ...app.calls.roomStage!,
        'presenter': 'kim', 'presenter_name': 'Mai Kim', 'queue': [{'id': 'minh', 'name': 'Lê Minh'}],
        'page': 'sys:handover', 'page_type': 'system', 'page_title': 'Chờ lượt trình chiếu', 'ends_at': _now + 9000,
        'handover': {'name': 'Mai Kim', 'uid': 'kim', 'pages': 2, 'seconds': 480, 'next': 'Lê Minh'},
        'handover_cfg': {'title': 'Mời {name} trình bày', 'desc': 'Hợp đồng và báo giá tháng 11', 'icon': '🎤', 'bg': 'linear-gradient(135deg,#1A3A6B,#101826)', 'show_avatar': true, 'show_pages': true, 'show_next': true, 'auto_seconds': 10},
      };
      _pages.firstWhere((p) => p['id'] == 'p6')['content'] = {
        'heading': 'Giao ban tháng 12', 'subtitle': 'Chào mừng mọi người, 9:00 bắt đầu', 'icon': '☕', 'bg': 'linear-gradient(135deg,#5B2A86,#1C1230)',
        'show_online': true, 'countdown': true, 'countdown_to': _now + 754000,
      };
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.dark),
          builder: (c, nav) => RepaintBoundary(key: shotKey, child: nav!),
          home: const CallScreen(),
        ),
      ));
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      await settle();
      expect(find.text('Hệ thống'), findsOneWidget);
      expect(find.textContaining('Mời Mai Kim trình bày'), findsOneWidget);
      await snap(t, 's1-he-thong-cho-luot');
      await t.tap(find.byTooltip('Soạn trang này').first);
      await settle();
      await snap(t, 's2-chinh-cho-luot');
      Navigator.of(t.element(find.text('Tự sang trang đầu của người trình bày'))).pop();
      await settle();
      await t.tap(find.text('Chào mừng').last);
      await settle();
      expect(find.text('Đếm ngược'), findsOneWidget);
      await snap(t, 's3-chao-mung');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
      app.calls.debugMeeting(_ch, const []);
    }, () => _relay(host: true));
    debugIsDesktop = null;
    CallScreen.debugRoom = null;
  });

  for (final (name, size, desktop) in [('b1-may-tinh', const Size(1440, 900), true), ('b2-dien-thoai', const Size(390, 844), false)]) {
    testWidgets('đợt mới: $name (xin vào, Apps, AI, Nội dung, Chào mừng, menu trang)', (t) async {
      debugIsDesktop = desktop;
      MeetPanelPrefs.debugSet(width: 460, tab: desktop ? 'pages' : '');
      CallScreen.debugRoom = (_) => _room();
      await http.runWithClient(() async {
        final app = _app();
        await t.runAsync(() async => app.debugSetStore(await LocalStore.memory('batch-$name')));
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.dark),
            builder: (c, nav) => RepaintBoundary(key: shotKey, child: MeetKnockLayer(call: app.calls, child: nav!)),
            home: const CallScreen(),
          ),
        ));
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        await settle();
        // Người xin vào: hộp lớn cho chủ trì.
        app.calls.fxEvents.add({'t': 'fx_guest_knock', 'req': 'r1', 'name': 'Phạm Thu Hà'});
        app.calls.fxEvents.add({'t': 'fx_lock_knock', 'req': 'r2', 'name': 'Đỗ Văn Nam'});
        await settle();
        expect(find.text('2 người xin vào cuộc họp'), findsOneWidget);
        expect(find.text('Cho tất cả vào'), findsOneWidget);
        await snap(t, '$name-1-xin-vao');
        app.calls.fxEvents.add({'t': 'fx_guest_knock_done', 'req': 'r1'});
        app.calls.fxEvents.add({'t': 'fx_lock_knock_done', 'req': 'r2'});
        await settle();
        expect(find.text('Cho tất cả vào'), findsNothing);
        // Trang hệ thống Nội dung trên sân khấu.
        app.calls.roomStage = {
          ...app.calls.roomStage!,
          'presenter': 'me', 'page': 'sys:program', 'page_type': 'system', 'page_title': 'Nội dung', 'ends_at': 0,
          'program_cfg': {
            'title': 'Nội dung giao ban', 'current': 1,
            'items': [
              {'title': 'Khai mạc', 'owner': 'me', 'owner_name': 'Dương Văn Ba', 'minutes': 5},
              {'title': 'Tiến độ tòa B', 'owner': 'loi', 'owner_name': 'Nguyễn Văn Lợi', 'minutes': 10},
              {'title': 'Hợp đồng tháng 11', 'owner': 'kim', 'owner_name': 'Mai Kim', 'minutes': 8},
              {'title': 'Hỏi đáp', 'owner': '', 'owner_name': '', 'minutes': 7},
            ],
          },
        };
        app.calls.notifyListeners();
        await settle();
        expect(find.text('Tiến độ tòa B'), findsWidgets);
        await snap(t, '$name-2-noi-dung');
        await t.tap(find.byTooltip('Soạn trang này').first);
        await settle();
        expect(find.text('Thêm phần'), findsOneWidget);
        await snap(t, '$name-3-soan-noi-dung');
        Navigator.of(t.element(find.text('Thêm phần'))).pop();
        await settle();
        // Trang hệ thống Chào mừng.
        app.calls.roomStage = {
          ...app.calls.roomStage!,
          'page': 'sys:welcome', 'page_title': 'Chào mừng',
          'welcome_cfg': {'heading': 'Giao ban tháng 12', 'subtitle': 'Chào mừng mọi người, 9:00 bắt đầu', 'icon': '☕', 'bg': 'linear-gradient(135deg,#5B2A86,#1C1230)', 'show_online': true, 'countdown': false},
        };
        app.calls.notifyListeners();
        await settle();
        await snap(t, '$name-4-chao-mung');
        await t.tap(find.byTooltip('Soạn trang này').first);
        await settle();
        expect(find.text('Chào mừng (trang hệ thống)'), findsOneWidget);
        await snap(t, '$name-5-soan-chao-mung');
        Navigator.of(t.element(find.text('Chào mừng (trang hệ thống)'))).pop();
        await settle();
        if (find.byTooltip('Tương tác, thành viên, màn hình, chat, AI').hitTestable().evaluate().isEmpty) {
          await t.tapAt(Offset(size.width / 2, 120));
          await settle();
        }
        if (!desktop) {
          await t.tap(find.byTooltip('Tương tác, thành viên, màn hình, chat, AI'));
          await settle();
        }
        // Apps: lưới cân đối theo nhóm.
        await t.tap(find.byTooltip('Apps: thêm trang, trình chiếu'));
        await settle();
        expect(find.text('TƯƠNG TÁC'), findsOneWidget);
        await snap(t, '$name-6-apps');
        Navigator.of(t.element(find.text('TƯƠNG TÁC'))).pop();
        await settle();
        // Nhấn giữ thẻ trang của mình: menu Sửa / Chiếu / Công khai / Xoá.
        await t.longPress(find.text('Kế hoạch Q4').first);
        await settle();
        expect(find.text('Sửa'), findsOneWidget);
        await snap(t, '$name-7-menu-trang');
        Navigator.of(t.element(find.text('Sửa'))).pop();
        await settle();
        // AI: thanh gọn, theme tối.
        await t.ensureVisible(find.text('AI').last);
        await settle();
        await t.tap(find.text('AI').last);
        await settle();
        expect(find.text('Phụ đề'), findsOneWidget);
        await snap(t, '$name-8-ai');
        if (!desktop) {
          Navigator.of(t.element(find.text('Phụ đề'))).pop();
          await settle();
        }
        // Cảm xúc: hàng nổi giữa thanh nút.
        if (find.byTooltip('Giơ tay, thả cảm xúc').hitTestable().evaluate().isEmpty) {
          await t.tapAt(Offset(size.width / 4, 120));
          await settle();
        }
        await t.tap(find.byTooltip('Giơ tay, thả cảm xúc'));
        await settle();
        await snap(t, '$name-9-cam-xuc');
        await t.tapAt(const Offset(40, 300));
        await settle();
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
        app.calls.debugMeeting(_ch, const []);
      }, () => _relay(host: true));
      debugIsDesktop = null;
      CallScreen.debugRoom = null;
    });
  }

  for (final (name, size, desktop, light) in [
    ('f1-may-tinh-toi', const Size(1440, 900), true, false),
    ('f2-may-tinh-sang', const Size(1440, 900), true, true),
    ('f3-dien-thoai', const Size(390, 844), false, false),
  ]) {
    testWidgets('khung sân khấu: $name', (t) async {
      debugIsDesktop = desktop;
      MeetPanelPrefs.debugSet(width: 460, tab: desktop ? 'pages' : '');
      CallScreen.debugRoom = (_) => _room();
      await http.runWithClient(() async {
        final app = _app();
        await t.runAsync(() async => app.debugSetStore(await LocalStore.memory('frame-$name')));
        app.calls.roomStage = {
          ...app.calls.roomStage!,
          'presenter': 'me', 'presenter_name': 'Nguyễn Văn Lợi', 'page': 'p3', 'page_type': 'poll', 'page_title': 'Chọn ngày bàn giao', 'key': 'k3', 'mode': 'manual', 'ends_at': _now + 204000,
          'theme_cfg': light ? {'accent': '#C8102E', 'mode': 'light', 'bg': ''} : {'accent': '#3D7BFF', 'mode': 'dark', 'bg': ''},
        };
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.dark),
            builder: (c, nav) => RepaintBoundary(key: shotKey, child: nav!),
            home: const CallScreen(),
          ),
        ));
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        await settle();
        await snap(t, '$name-1-san-khau');
        expect(find.textContaining('BÌNH CHỌN'), findsWidgets);
        if (desktop && !light) {
          await t.tap(find.text('Giao diện sân khấu'));
          await settle();
          expect(find.text('Màu nhấn'), findsOneWidget);
          await snap(t, '$name-2-giao-dien');
          await t.drag(find.text('Màu nhấn'), const Offset(0, -300));
          await settle();
          await snap(t, '$name-3-nen');
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
        app.calls.debugMeeting(_ch, const []);
      }, () => _relay(host: true));
      debugIsDesktop = null;
      CallScreen.debugRoom = null;
    });
  }

  for (final (name, size, desktop) in [('h1-may-tinh', const Size(1440, 900), true), ('h2-dien-thoai', const Size(390, 844), false)]) {
    testWidgets('trang hệ thống mới: $name', (t) async {
      debugIsDesktop = desktop;
      MeetPanelPrefs.debugSet(width: 460, tab: desktop ? 'pages' : '');
      CallScreen.debugRoom = (_) => _room();
      await http.runWithClient(() async {
        final app = _app();
        await t.runAsync(() async => app.debugSetStore(await LocalStore.memory('sys2-$name')));
        final base = {...app.calls.roomStage!, 'meeting_title': 'Giao ban tháng 12', 'theme_cfg': {'accent': '#3D7BFF', 'mode': 'dark'}, 'ends_at': 0};
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.dark),
            builder: (c, nav) => RepaintBoundary(key: shotKey, child: nav!),
            home: const CallScreen(),
          ),
        ));
        Future<void> settle() async {
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        Future<void> show(Map<String, dynamic> st, String shot) async {
          app.calls.roomStage = {...base, ...st};
          app.calls.notifyListeners();
          await settle();
          await snap(t, '$name-$shot');
        }

        await settle();
        await show({
          'page': 'sys:welcome', 'page_type': 'system', 'page_title': 'Chào mừng',
          'welcome_cfg': {'heading': 'Chào mừng mọi người đến buổi giao ban', 'subtitle': 'Tổng kết tiến độ tòa B, hợp đồng tháng 11 và kế hoạch quý 1.', 'bg': 'brand:dark', 'show_online': true, 'countdown': true, 'countdown_to': _now + 292000},
        }, '1-chao-mung');
        expect(find.text('BẮT ĐẦU SAU'), findsOneWidget);
        await show({
          'page': 'sys:handover', 'page_type': 'system', 'page_title': 'Chờ lượt trình chiếu', 'presenter': 'kim', 'presenter_name': 'Mai Kim',
          'queue': [{'id': 'minh', 'name': 'Lê Minh'}, {'id': 'quang', 'name': 'Trần Quang'}],
          'ends_at': _now + 6000,
          'handover': {'name': 'Mai Kim', 'uid': 'kim', 'pages': 2, 'seconds': 480, 'next': 'Lê Minh'},
          'handover_cfg': {'title': 'Mời chị {name} trình bày', 'show_avatar': true, 'show_pages': true, 'show_next': true, 'auto_seconds': 10},
        }, '2-cho-luot');
        await show({
          'page': 'sys:program', 'page_type': 'system', 'page_title': 'Nội dung', 'presenter': 'me', 'presenter_name': 'Dương Văn Ba',
          'program_cfg': {
            'title': 'Nội dung giao ban', 'current': 1,
            'items': [
              {'title': 'Khai mạc', 'owner': 'me', 'owner_name': 'Dương Văn Ba', 'minutes': 5},
              {'title': 'Tiến độ lắp đặt tòa B', 'owner': 'loi', 'owner_name': 'Nguyễn Văn Lợi', 'minutes': 10},
              {'title': 'Hợp đồng tháng 11', 'owner': 'kim', 'owner_name': 'Mai Kim', 'minutes': 8},
              {'title': 'An toàn lao động', 'owner': 'minh', 'owner_name': 'Lê Minh', 'minutes': 5},
              {'title': 'Hỏi đáp & chốt việc', 'owner': '', 'owner_name': '', 'minutes': 7},
            ],
          },
        }, '3-noi-dung');
        expect(find.text('ĐANG DIỄN RA'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
        app.calls.debugMeeting(_ch, const []);
      }, () => _relay(host: true));
      debugIsDesktop = null;
      CallScreen.debugRoom = null;
    });
  }
}
