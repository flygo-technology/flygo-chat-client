// App "Họp": mã / link, API phòng họp có mã, trang chủ, phòng chờ, màn cuộc họp (bố cục, cột bên phải, xin vào).
// Ảnh xem trước (chạy tay): MEET_OUT=<thư mục> flutter test test/meet_app_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/calls/call_service.dart';
import 'package:flygo_chat/calls/meet_room.dart';
import 'package:flygo_chat/calls/meet_rooms.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/call_screen.dart';
import 'package:flygo_chat/ui/desk_tabs.dart';
import 'package:flygo_chat/ui/meet/meet_home.dart';
import 'package:flygo_chat/ui/meet/meet_lobby.dart';
import 'package:flygo_chat/ui/meet/meet_qr_invite.dart';
import 'package:flygo_chat/ui/meet/meet_schedule.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  for (final fam in ['Roboto', 'Noto Sans', '.SF UI Text', 'Segoe UI']) {
    await load(fam, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

const _me = 'mmmmmmmmmmmmmmmmmmmmmmmmmm';
const _ch = 'cccccccccccccccccccccccccc';
String _u(String c) => c * 26;

void main() {
  final out = Platform.environment['MEET_OUT'];
  final app = AppState('t')..me = MmUser({'id': _me, 'username': 'ba', 'first_name': 'Ba', 'last_name': 'Nguyễn'});
  for (final (c, f, l) in [('a', 'An', 'Trần'), ('b', 'Bình', 'Lê'), ('c', 'Chi', 'Phạm'), ('d', 'Dũng', 'Võ')]) {
    app.users[_u(c)] = MmUser({'id': _u(c), 'username': f.toLowerCase(), 'first_name': f, 'last_name': l});
  }
  app.channels[_ch] = MmChannel({'id': _ch, 'name': 'hop-abc-mnop-xyz', 'display_name': '📅 Giao ban kỹ thuật', 'type': 'P', 'team_id': 't'});
  final now = DateTime.now();
  final rooms = [
    MeetRoomInfo(
      code: 'abc-mnop-xyz',
      url: 'https://chat.example.test/__apps/hop/abc-mnop-xyz',
      channelId: _ch,
      title: 'Giao ban kỹ thuật',
      creator: _me,
      access: 'company',
      start: now.subtract(const Duration(minutes: 20)),
      status: MeetRoomStatus.live,
      participants: 4,
    ),
    MeetRoomInfo(
      code: 'kpq-rstu-vwx',
      url: '',
      channelId: 'x',
      title: 'Họp kế hoạch tháng 12',
      creator: _me,
      access: 'invited',
      start: DateTime(now.year, now.month, now.day, 9).add(const Duration(days: 1)),
      status: MeetRoomStatus.open,
    ),
    MeetRoomInfo(
      code: 'ghi-jkmn-pqr',
      url: '',
      channelId: 'y',
      title: 'Trao đổi với khách hàng',
      creator: _u('a'),
      access: 'invited',
      start: DateTime(now.year, now.month, now.day, 15, 30).add(const Duration(days: 3)),
      status: MeetRoomStatus.scheduled,
    ),
    MeetRoomInfo(
      code: 'stu-vwxy-zab',
      url: '',
      channelId: 'z',
      title: 'Demo app Họp',
      creator: _me,
      access: 'company',
      start: now.subtract(const Duration(days: 1)),
      status: MeetRoomStatus.ended,
    ),
  ];

  setUpAll(() async {
    await _fonts();
    // Phòng họp phát âm thanh qua audioplayers: kiểm thử không có plugin.
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global', 'xyz.luan/audioplayers.global/events']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });
  tearDown(() {
    debugIsDesktop = null;
    CallScreen.debugRoom = null;
  });

  var shotKey = GlobalKey();

  /// Chụp cây widget đang hiện (giữ nguyên trạng thái: menu, cột đang mở…).
  Future<void> snap(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> show(WidgetTester t, String name, Size size, Widget child, {bool dark = false}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    shotKey = GlobalKey();
    final theme = buildTheme(dark ? Brightness.dark : Brightness.light);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          // Bọc cả Navigator: ảnh có luôn menu / bảng dưới đang mở.
          builder: (c, nav) => RepaintBoundary(key: shotKey, child: nav),
          home: child,
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    await snap(t, name);
  }

  group('mã và link', () {
    test('mã mời thiết bị: từ mã QR, link, hoặc gõ tay', () {
      expect(parsePairCode('https://chat.example.test/__apps/hop/pair/KYSRGTWTPW9C'), 'KYSRGTWTPW9C');
      expect(parsePairCode('kysr-gtwt-pw9c'), 'KYSRGTWTPW9C');
      expect(parsePairCode('KYSR GTWT PW9C'), 'KYSRGTWTPW9C');
      expect(parsePairCode('abc-defg-hij'), isNull);
      expect(parsePairCode('xin chào'), isNull);
    });
    test('đọc mã từ mã trần, không gạch, link', () {
      expect(parseMeetCode('ABC-DEFG-HIJ'), 'abc-defg-hij');
      expect(parseMeetCode(' abcdefghij '), 'abc-defg-hij');
      expect(parseMeetCode('https://chat.example.test/__apps/hop/abc-defg-hij'), 'abc-defg-hij');
      expect(parseMeetCode('https://chat.example.test/__apps/hop/abc-defg-hij?x=1'), 'abc-defg-hij');
      expect(parseMeetCode('xin chào'), isNull);
      expect(parseMeetCode('abc-defg'), isNull);
    });

    test('phòng từ JSON của máy chủ', () {
      final r = MeetRoomInfo.fromJson({
        'code': 'abc-defg-hij',
        'url': 'u',
        'channel_id': _ch,
        'title': 'T',
        'creator': _me,
        'access': 'invited',
        'start': 1700000000000,
        'status': 'scheduled',
        'participants': 2,
        'member': false,
        'invitees': [_u('a')],
        'own_channel': true,
      });
      expect(r.locked, isFalse); // luôn vào được trước giờ
      expect(r.live, isFalse);
      expect(r.member, isFalse);
      expect(r.invitees, [_u('a')]);
      expect(MeetRoomInfo.fromJson({'status': 'cancelled'}).finished, isTrue);
    });

    test('API: tạo, vào phòng, máy chủ cũ không có /meet/rooms', () async {
      final seen = <String>[];
      final api = MeetRoomsApi(
        'tok',
        client: MockClient((req) async {
          seen.add('${req.method} ${req.url.path} ${req.headers['Authorization']}');
          if (req.url.path.endsWith('/meet/rooms') && req.method == 'POST') {
            final b = jsonDecode(req.body) as Map;
            expect(b['title'], 'Họp thử');
            expect(b['invitees'], ['an']);
            return http.Response(
              jsonEncode({'code': 'abc-defg-hij', 'channel_id': _ch, 'title': b['title'], 'status': 'open'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (req.url.path.endsWith('/join')) return http.Response('{"status":"admitted","channel_id":"$_ch"}', 200);
          return http.Response('{"error":"not found"}', 404);
        }),
      );
      final r = await api.create(title: 'Họp thử', invitees: ['an']);
      expect(r.code, 'abc-defg-hij');
      expect(await api.join(r.code), (MeetJoinResult.admitted, _ch));
      await expectLater(api.mine(), throwsA(isA<MeetRoomsException>().having((e) => e.unsupported, 'unsupported', isTrue)));
      expect(seen.first, 'POST /meet/rooms Bearer tok');
    });
  });

  testWidgets('trang chủ Họp (máy tính, sáng)', (t) async {
    debugIsDesktop = true;
    await show(t, 'd1-home', const Size(1440, 860), MeetHomePage(demoRooms: rooms));
    expect(find.text('Cuộc họp mới'), findsOneWidget);
    expect(find.text('Nhập mã hoặc đường liên kết'), findsOneWidget);
    expect(find.text('ĐANG DIỄN RA'), findsOneWidget);
    expect(find.text('SẮP TỚI'), findsOneWidget);
    expect(find.text('GẦN ĐÂY'), findsOneWidget);
    // Menu "Cuộc họp mới".
    await t.tap(find.byKey(const ValueKey('meet-new')));
    await t.pumpAndSettle();
    expect(find.text('Tạo cuộc họp để dùng sau'), findsOneWidget);
    expect(find.text('Lên lịch cuộc họp'), findsOneWidget);
    await snap(t, 'd1-home-menu');
  });

  group('lên lịch / sửa / huỷ', () {
    // 08:10 giờ Việt Nam ngày 20/11/2026 (01:10 UTC).
    final clock = DateTime.utc(2026, 11, 20, 1, 10);
    MeetSchedule? got;
    Widget opener({MeetRoomInfo? edit}) => Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open'),
                onPressed: () async => got = await showScheduleMeeting(c, edit: edit, clock: () => clock),
                child: const Text('open'),
              ),
            ),
          ),
        );
    Future<void> pickSlot(WidgetTester t, String key, String label) async {
      await t.tap(find.byKey(ValueKey(key)));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.textContaining(label), 200, scrollable: find.byType(Scrollable).last);
      await t.tap(find.textContaining(label).last);
      await t.pumpAndSettle();
    }

    testWidgets('giờ Việt Nam: chuyển đổi hai chiều', (t) async {
      final w = meetWall(DateTime.utc(2026, 12, 1, 2, 0));
      expect([w.hour, w.minute, w.day], [9, 0, 1]);
      expect(meetInstant(DateTime.utc(2026, 12, 1, 9, 0)).toUtc(), DateTime.utc(2026, 12, 1, 2, 0));
      expect(meetDuration(90), '1 giờ 30 phút');
      expect(meetDuration(45), '45 phút');
    });

    testWidgets('lên lịch: ngày, giờ bắt đầu, giờ kết thúc (máy tính)', (t) async {
      debugIsDesktop = true;
      got = null;
      await show(t, 'd6-schedule-open', const Size(1280, 860), opener());
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      // Mặc định: 09:30–10:30 cùng ngày (mốc 30 phút sau một giờ nữa), giờ Việt Nam.
      expect(find.text('09:30'), findsOneWidget);
      expect(find.text('10:30'), findsOneWidget);
      expect(find.textContaining('Thứ 6, 20/11/2026'), findsOneWidget);
      expect(find.textContaining('Giờ Việt Nam (GMT+7) · 1 giờ'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Giao ban tuần');
      await t.pump();
      await snap(t, 'd6-schedule');
      // Giờ bắt đầu 14:00 (giữ thời lượng 1 giờ) rồi giờ kết thúc 15:30.
      await pickSlot(t, 'meet-from', '14:00');
      expect(find.text('15:00'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('meet-to')));
      await t.pumpAndSettle();
      await snap(t, 'd6-schedule-end-picker');
      await t.scrollUntilVisible(find.textContaining('15:30 (1 giờ 30 phút)'), 200, scrollable: find.byType(Scrollable).last);
      await t.tap(find.textContaining('15:30 (1 giờ 30 phút)'));
      await t.pumpAndSettle();
      expect(find.textContaining('1 giờ 30 phút'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('meet-schedule-save')));
      await t.pumpAndSettle();
      expect(got!.title, 'Giao ban tuần');
      expect(got!.start.toUtc(), DateTime.utc(2026, 11, 20, 7, 0));
      expect(got!.end.toUtc(), DateTime.utc(2026, 11, 20, 8, 30));
      expect(got!.access, 'invited');
    });

    testWidgets('sửa cuộc họp: điền sẵn giờ cũ, giờ đã qua thì báo (điện thoại)', (t) async {
      debugIsDesktop = false;
      got = null;
      final room = MeetRoomInfo(
        code: 'abc-defg-hij', url: '', channelId: _ch, title: 'Họp khách', creator: _me, access: 'company',
        start: DateTime.utc(2026, 11, 21, 2, 0), end: DateTime.utc(2026, 11, 21, 3, 15), invitees: [_u('a')],
      );
      await show(t, 'p6-edit-open', const Size(390, 844), opener(edit: room));
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      expect(find.text('Sửa cuộc họp'), findsOneWidget);
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('10:15'), findsOneWidget);
      expect(find.textContaining('Thứ 7, 21/11/2026'), findsOneWidget);
      await snap(t, 'p6-edit');
      // Kết thúc 08:45 < bắt đầu: hiểu là hôm sau (họp qua đêm), vẫn lưu được nhưng dài quá 24 giờ thì không.
      await pickSlot(t, 'meet-to', '09:30');
      await t.tap(find.byKey(const ValueKey('meet-schedule-save')));
      await t.pumpAndSettle();
      expect(got!.access, 'company');
      expect(got!.invitees, [_u('a')]);
      expect(got!.end.difference(got!.start).inMinutes, 30);
    });

    testWidgets('menu ⋮ trong danh sách: người tạo sửa / huỷ, cuộc họp đã qua thì xoá khỏi lịch sử', (t) async {
      debugIsDesktop = true;
      await show(t, 'd7-menu', const Size(1440, 860), MeetHomePage(demoRooms: rooms));
      final up = rooms.firstWhere((r) => r.creator == _me && !r.live && !r.finished && (r.start?.isAfter(DateTime.now()) ?? false));
      await t.tap(find.byKey(ValueKey('meet-menu-${up.code}')));
      await t.pumpAndSettle();
      expect(find.text('Sửa ngày giờ'), findsOneWidget);
      expect(find.text('Huỷ cuộc họp'), findsOneWidget);
      await snap(t, 'd7-menu-upcoming');
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      final past = rooms.firstWhere((r) => r.finished);
      await t.tap(find.byKey(ValueKey('meet-menu-${past.code}')));
      await t.pumpAndSettle();
      expect(find.text('Xoá khỏi lịch sử'), findsOneWidget);
      expect(find.text('Sửa ngày giờ'), findsNothing);
    });
  });

  testWidgets('trang chủ Họp (điện thoại, tối)', (t) async {
    debugIsDesktop = false;
    await show(t, 'p1-home', const Size(390, 844), MeetHomePage(demoRooms: rooms), dark: true);
    expect(find.text('Nhập mã'), findsOneWidget);
    expect(find.text('Giao ban kỹ thuật'), findsOneWidget);
  });

  testWidgets('phòng chờ (máy tính + điện thoại)', (t) async {
    debugIsDesktop = true;
    await show(t, 'd2-lobby', const Size(1440, 860), MeetLobbyPage(code: rooms[0].code, room: rooms[0], demo: true));
    expect(find.text('Sẵn sàng tham gia?'), findsOneWidget);
    expect(find.text('Tham gia ngay'), findsOneWidget);
    expect(find.text('Trình bày'), findsOneWidget);
    expect(find.text('4 người đang trong cuộc họp'), findsOneWidget);
    debugIsDesktop = false;
    await show(t, 'p2-lobby', const Size(390, 844), MeetLobbyPage(code: rooms[0].code, room: rooms[0], demo: true), dark: true);
    expect(find.text('Trình bày'), findsNothing);
    // Bật mic ở phòng chờ.
    await t.tap(find.byKey(const ValueKey('lobby-mic')));
    await t.pump();
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    // Phòng chưa tới giờ, không cho vào sớm: nút vào bị khoá.
    final locked = MeetRoomInfo(
      code: 'kpq-rstu-vwx',
      url: '',
      channelId: 'x',
      title: 'Họp kế hoạch',
      creator: _u('a'),
      access: 'company',
      start: now.add(const Duration(hours: 2)),
      allowEarly: false,
      status: MeetRoomStatus.scheduled,
      member: true,
    );
    await show(t, 'p2-lobby-locked', const Size(390, 844), MeetLobbyPage(key: const ValueKey('locked'), code: locked.code, room: locked, demo: true));
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('lobby-join'))).onPressed, isNotNull); // luôn vào được trước giờ
    // Phòng chỉ dành cho người được mời: người ngoài danh sách thấy "Xin tham gia".
    final invited = MeetRoomInfo(
      code: 'ghi-jkmn-pqr',
      url: '',
      channelId: 'y',
      title: 'Trao đổi',
      creator: _u('a'),
      access: 'invited',
      status: MeetRoomStatus.open,
      member: false,
    );
    await show(
      t,
      'p2-lobby-knock',
      const Size(390, 844),
      MeetLobbyPage(key: const ValueKey('invited'), code: invited.code, room: invited, demo: true),
    );
    expect(find.text('Xin tham gia'), findsOneWidget);
  });

  testWidgets('phòng chờ co giãn theo chỗ có (tab, ô chia, hộp hẹp): cột tham gia không bị cắt', (t) async {
    debugIsDesktop = true;
    // Tab máy tính ở cửa sổ 1280×800 / 1440×900 (trừ thanh tab), hộp nổi cũ 980×810, ô chia đôi, cửa sổ hẹp.
    for (final (name, size) in [
      ('d2-lobby-1280', const Size(1280, 758)),
      ('d2-lobby-1440', const Size(1440, 858)),
      ('d2-lobby-980', const Size(980, 810)),
      ('d2-lobby-split', const Size(700, 800)),
      ('d2-lobby-narrow', const Size(480, 800)),
    ]) {
      await show(t, name, size, MeetLobbyPage(key: ValueKey(name), code: rooms[0].code, room: rooms[0], demo: true));
      for (final k in [find.byKey(const ValueKey('lobby-join')), find.text('Trình bày'), find.text('Sẵn sàng tham gia?')]) {
        final r = t.getRect(k);
        expect(r.left >= 0 && r.right <= size.width, isTrue, reason: '$name: $k nằm ngoài khung ($r)');
      }
    }
  });

  testWidgets('máy tính có thanh tab: phòng chờ mở thành tab riêng, không đẩy trang hay hộp nổi', (t) async {
    debugIsDesktop = true;
    final opened = <DeskTab>[];
    openTabHook = opened.add;
    addTearDown(() => openTabHook = null);
    await show(t, 'x', const Size(1280, 800), Builder(builder: (c) => TextButton(onPressed: () => openMeetLobby(c, rooms[0].code, room: rooms[0]), child: const Text('mở'))));
    await t.tap(find.text('mở'));
    await t.pump();
    expect(opened.single.kind, 'meet');
    expect(opened.single.arg, rooms[0].code);
    // Không còn trang / hộp nổi nào được đẩy lên.
    expect(find.byType(MeetLobbyPage), findsNothing);
    // Nội dung tab: phòng chờ với thông tin phòng đã có, tiêu đề tab theo tên cuộc họp.
    String? title;
    await show(t, 'd2-lobby-tab', const Size(1280, 758), DeskTabScope(onTitle: (v) => title = v, onClose: () {}, child: MeetLobbyTab.page(rooms[0].code, demo: true)));
    expect(find.text('4 người đang trong cuộc họp'), findsOneWidget);
    expect(title, 'Giao ban kỹ thuật');
  });

  group('màn cuộc họp', () {
    MeetRoom room() {
      final r = MeetRoom(channelId: _ch, token: 't', server: '', myId: _me, onMuteMe: () {}, connect: false);
      r.debugApply({
        'type': 'state',
        'you': {'host': true},
        'state': {
          'comments': [
            {
              'from': {'user_id': _u('a'), 'name': 'An Trần'},
              'text': 'Slide 3 cập nhật số liệu tuần này nhé',
              'at': now.millisecondsSinceEpoch - 600000,
            },
            {
              'from': {'user_id': 'bot', 'name': 'Trợ lý AI', 'bot': true},
              'text': 'Đã ghi: chốt ngân sách Q1 trước 20/11, Chi phụ trách.',
              'at': now.millisecondsSinceEpoch - 300000,
            },
          ],
        },
      });
      return r;
    }

    List<CallParticipant> people() => [
      CallParticipant('s1', _u('a'))
        ..unmuted = true
        ..speaking = true,
      CallParticipant('s2', _u('b'))..raisedHand = true,
      CallParticipant('s3', _u('c'))..unmuted = true,
      CallParticipant('s4', _u('d')),
    ];

    testWidgets('máy tính: lưới, cột Mọi người, xin vào, đổi bố cục, cột Tin nhắn / Thông tin', (t) async {
      debugIsDesktop = true;
      // Màn hình tạo lại thì phòng cũ bị huỷ: mỗi lần một phòng mới, [r] là phòng đang dùng.
      late MeetRoom r;
      CallScreen.debugRoom = (_) => r = room();
      app.calls.debugMeeting(
        _ch,
        people(),
        info: const MeetingInfo(postId: 'p', creatorId: _me, title: 'Giao ban kỹ thuật', code: 'abc-mnop-xyz'),
      );
      await show(t, 'd3-call', const Size(1440, 860), const CallScreen());
      expect(find.text('An Trần'), findsWidgets);
      // Cột Mọi người.
      await t.tap(find.byTooltip('Thành viên'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('TRONG CUỘC HỌP · 5'), findsOneWidget);
      // Có người xin vào: thẻ ở góc + mục trong cột.
      r.debugApply({'type': 'knock', 'req': 'r1', 'user_id': 'k' * 26, 'name': 'Hoa Đỗ', 'code': 'abc-mnop-xyz'});
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Hoa Đỗ muốn tham gia cuộc họp này'), findsOneWidget);
      expect(find.text('ĐANG XIN THAM GIA'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 300));
      await snap(t, 'd3-call-people');
      r.debugApply({'type': 'knock_done', 'req': 'r1'});
      await t.pump();
      expect(find.text('Hoa Đỗ muốn tham gia cuộc họp này'), findsNothing);
      // Tin nhắn trong cuộc họp.
      await t.tap(find.byTooltip('Tin nhắn trong cuộc họp'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Gửi tin nhắn cho mọi người'), findsOneWidget);
      // Bố cục Thanh bên.
      await t.tap(find.byTooltip('Tùy chọn khác'));
      await t.pumpAndSettle();
      await t.tap(find.text('Đổi bố cục'));
      await t.pumpAndSettle();
      await t.tap(find.text('Thanh bên'));
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 300));
      await snap(t, 'd4-call-sidebar-chat');
      // Thông tin cuộc họp: mã, link, liên kết xem.
      await t.tap(find.byTooltip('Thông tin cuộc họp'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Sao chép liên kết xem'), findsOneWidget);
      expect(find.textContaining('abc-mnop-xyz'), findsWidgets);
      await t.pump(const Duration(milliseconds: 300));
      await snap(t, 'd5-call-info');
      await t.pumpWidget(const SizedBox.shrink());
      app.calls.debugMeeting(_ch, const []);
    });

    testWidgets('máy tính: cột bên phải ở các cỡ cửa sổ (1280×800, 1440×900, nửa màn hình)', (t) async {
      debugIsDesktop = true;
      CallScreen.debugRoom = (_) => room();
      for (final (name, size) in [('d6-call-1280', const Size(1280, 800)), ('d6-call-1440', const Size(1440, 900)), ('d6-call-split', const Size(720, 900))]) {
        app.calls.debugMeeting(
          _ch,
          people(),
          info: const MeetingInfo(postId: 'p', creatorId: _me, title: 'Giao ban kỹ thuật', code: 'abc-mnop-xyz'),
        );
        await show(t, name, size, CallScreen(key: ValueKey(name)));
        await t.tap(find.byTooltip('Thành viên'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('TRONG CUỘC HỌP · 5'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 300));
        await snap(t, '$name-people');
        await t.pumpWidget(const SizedBox.shrink());
      }
      app.calls.debugMeeting(_ch, const []);
    });

    testWidgets('đang vào / không vào được cuộc họp: giao diện cuộc họp, không phải màn gọi điện', (t) async {
      debugIsDesktop = true;
      CallScreen.debugRoom = (_) => room();
      app.calls.debugMeeting(_ch, const [], info: const MeetingInfo(postId: 'p', creatorId: _me, title: 'Giao ban kỹ thuật', code: 'abc-mnop-xyz'));
      app.calls.phase = CallPhase.connecting;
      await show(t, 'd7-joining', const Size(1280, 800), const CallScreen());
      expect(find.text('Đang vào cuộc họp…'), findsOneWidget);
      expect(find.text('Cuộc họp nội bộ Flygo Chat'), findsNothing);
      app.calls
        ..endReason = 'Máy chủ chat chưa cho phép gọi nhóm và họp (chỉ gọi riêng 1-1). Hãy báo quản trị máy chủ.'
        ..phase = CallPhase.ended;
      await show(t, 'd7-join-failed', const Size(1280, 800), const CallScreen(key: ValueKey('failed')));
      expect(find.textContaining('chưa cho phép gọi nhóm'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      app.calls.debugMeeting(_ch, const []);
    });

    testWidgets('điện thoại: lưới + bảng ⋯', (t) async {
      debugIsDesktop = false;
      CallScreen.debugRoom = (_) => room();
      app.calls.debugMeeting(
        _ch,
        people(),
        info: const MeetingInfo(postId: 'p', creatorId: _me, title: 'Giao ban kỹ thuật', code: 'abc-mnop-xyz'),
      );
      await show(t, 'p3-call', const Size(390, 844), const CallScreen());
      expect(find.textContaining('Giao ban kỹ thuật'), findsWidgets);
      await t.tap(find.byIcon(Icons.more_horiz_rounded).last);
      await t.pumpAndSettle();
      expect(find.text('Đổi bố cục'), findsOneWidget);
      expect(find.text('Thông tin cuộc họp'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 300));
      await snap(t, 'p4-call-more');
      await t.pumpWidget(const SizedBox.shrink());
      app.calls.debugMeeting(_ch, const []);
    });
  });
}
