// Lịch: sự kiện sắp tới + đếm ngược ở Trang chủ (dưới thẻ người dùng trên máy tính, dải gọn ở đầu trang trên điện thoại).
// Ảnh chụp (chạy tay): UPCOMING_OUT=<thư mục> flutter test test/calendar_upcoming_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/calendar/event_style.dart';
import 'package:flygo_chat/ui/calendar/model.dart';
import 'package:flygo_chat/ui/calendar/upcoming.dart';
import 'package:flygo_chat/ui/home_page.dart';
import 'package:flygo_chat/ui/theme.dart';
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

const _tz = 'Asia/Ho_Chi_Minh';
// Giờ Việt Nam → UTC ms.
int _ms(int d, int h, int mi) => DateTime.utc(2026, 11, d, h, mi).millisecondsSinceEpoch - 7 * 3600000;
// Bây giờ: thứ Ba 17/11/2026 10:50 giờ Việt Nam.
final _now = DateTime.fromMillisecondsSinceEpoch(_ms(17, 10, 50), isUtc: true);

CEvent _ev(String id, String title, int d, int h, int mi, int dur,
        {String? my = 'yes', bool allDay = false, String status = 'confirmed', bool busyOnly = false, String loc = '', String color = 'blue', String? rid}) =>
    CEvent(
        id: id,
        rid: rid,
        title: title,
        calendarColor: color,
        location: loc,
        allDay: allDay,
        startMs: _ms(d, h, mi),
        endMs: _ms(d, h, mi) + dur * 60000,
        myRsvp: my,
        status: status,
        busyOnly: busyOnly,
        tz: _tz);

final _events = [
  _ev('past', 'Đã xong', 17, 8, 0, 60),
  _ev('live', 'Giao ban đầu tuần', 17, 9, 0, 150, loc: 'Phòng họp tầng 3'),
  _ev('pccc', 'Kiểm tra PCCC – Văn phòng', 17, 14, 30, 90, my: 'needs', loc: 'Văn phòng', color: 'red'),
  _ev('khach', 'Gặp khách hàng', 18, 9, 0, 60, color: 'teal'),
  _ev('xa', 'Đào tạo an toàn', 20, 8, 0, 240, my: 'maybe', color: 'purple'),
  _ev('tuchoi', 'Đã từ chối', 17, 15, 0, 30, my: 'no'),
  _ev('xem', 'Lịch người khác (chỉ xem)', 17, 16, 0, 30, my: null),
  _ev('hol', 'Ngày lễ', 19, 0, 0, 1440, my: null, allDay: true),
  _ev('huy', 'Đã huỷ', 17, 13, 0, 30, status: 'cancelled'),
  _ev('ban', 'Bận', 17, 13, 0, 30, busyOnly: true),
  _ev('xa8', 'Quá 7 ngày', 25, 9, 0, 60),
];

void main() {
  final out = Platform.environment['UPCOMING_OUT'];

  group('lọc + câu chữ', () {
    test('chỉ sự kiện của mình, chưa xong, trong 7 ngày, theo giờ bắt đầu', () {
      expect(upcomingFrom(_events, _now).map((e) => e.id), ['live', 'pccc', 'khach', 'xa']);
      expect(upcomingFrom(_events, _now, within: const Duration(hours: 6)).map((e) => e.id), ['live', 'pccc']);
      // Cùng một lần xảy ra lặp lại hai lần (vd vừa lịch chính vừa lời mời) chỉ hiện một.
      expect(upcomingFrom([_ev('r', 'Lặp', 18, 9, 0, 30, rid: '2026-11-18'), _ev('r', 'Lặp', 18, 9, 0, 30, rid: '2026-11-18')], _now).length, 1);
      expect(upcomingFrom(const [], _now), isEmpty);
    });
    test('đếm ngược', () {
      expect(countdownText(const Duration(hours: 2, minutes: 14, seconds: 30)), 'còn 2 giờ 15 phút');
      expect(countdownText(const Duration(hours: 3)), 'còn 3 giờ');
      expect(countdownText(const Duration(minutes: 59, seconds: 30)), 'còn 1 giờ');
      expect(countdownText(const Duration(minutes: 15)), 'còn 15 phút');
      expect(countdownText(const Duration(seconds: 40)), 'còn 40 giây');
      expect(countdownText(Duration.zero), 'còn 1 giây');
      expect(countdownText(const Duration(days: 2, hours: 3)), 'còn 2 ngày 3 giờ');
      expect(countdownText(const Duration(days: 1)), 'còn 1 ngày');
    });
    test('giờ', () {
      final byId = {for (final e in _events) e.id: e};
      expect(whenText(byId['pccc']!, _now, _tz), 'Hôm nay 14:30–16:00');
      expect(whenText(byId['khach']!, _now, _tz), 'Ngày mai 09:00–10:00');
      expect(whenText(byId['xa']!, _now, _tz), 'T6 20/11 08:00–12:00');
      expect(whenText(byId['hol']!, _now, _tz), 'T5 19/11 · Cả ngày');
    });
  });

  group('giao diện', () {
    final app = AppState('t')
      ..me = MmUser({'id': 'me', 'username': 'minhan', 'first_name': 'Minh', 'last_name': 'An', 'position': 'Trưởng phòng Hành chính', 'email': 'minhan@congtymau.vn'});
    app.users['me'] = app.me!;
    late DateTime clock;
    setUp(() {
      clock = _now;
      upcomingDiskCache = false;
      upcomingResetCache();
      upcomingLoader = (_) async => UpcomingData(events: _events, tz: _tz);
    });

    Future<void> pumpHost(WidgetTester t, Size size, Brightness b, Widget Function(BuildContext c) body) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      if (out != null) await t.runAsync(_fonts);
      await t.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: Builder(builder: (c) => Scaffold(backgroundColor: Pal.of(c).bg, body: body(c)))),
        ),
      ));
      await t.pump();
      await t.pump();
    }

    Future<void> shot(WidgetTester t, String name) async {
      if (out == null) return;
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() async {
        final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(out).createSync(recursive: true);
        await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }

    Future<void> done(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump();
    }

    /// Ô ứng dụng giả (minh hoạ bố cục Trang chủ; thẻ người dùng và khối sự kiện là widget thật).
    Widget tiles(Pal pal, List<(IconData, String)> items) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(spacing: 22, runSpacing: 20, children: [
            for (final (i, l) in items)
              SizedBox(
                width: 72,
                child: Column(children: [
                  Container(width: 58, height: 58, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(17)), child: Icon(i, color: Colors.white, size: 28)),
                  const SizedBox(height: 8),
                  Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: pal.text)),
                ]),
              ),
          ]),
        );
    const demoTiles = [(Icons.chat_bubble_rounded, 'Chat'), (Icons.campaign_rounded, 'Bảng tin'), (Icons.event_rounded, 'Lịch'), (Icons.videocam_rounded, 'Họp')];

    for (final b in Brightness.values) {
      final sfx = b == Brightness.dark ? 'dark' : 'light';
      testWidgets('máy tính: thẻ gọn, lịch hôm nay + 7 ngày tới, đếm ngược chạy, bấm mở sự kiện / mở Lịch ($sfx)', (t) async {
        final opened = <String>[];
        var openedCal = 0, profile = 0, settings = 0;
        await pumpHost(
            t,
            const Size(1280, 900),
            b,
            (c) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 1280 / 3,
                    child: Column(children: [
                      Expanded(
                        child: ListView(padding: const EdgeInsets.only(top: 24, bottom: 16), children: [
                          AppsUserCard(compact: true, onProfile: () => profile++, onSettings: () => settings++),
                          UpcomingEvents(clock: () => clock, max: 5, onOpen: (e) => opened.add(e.instanceId), onOpenCalendar: () => openedCal++),
                        ]),
                      ),
                      Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
                          child: Row(children: [
                            const Expanded(child: AppsServerRow(align: TextAlign.left, version: true)),
                            AppsLogoutButton(onLogout: () {}),
                          ])),
                    ]),
                  ),
                  Expanded(child: ListView(padding: const EdgeInsets.only(top: 24), children: [tiles(Pal.of(c), demoTiles)])),
                ]));
        // Thẻ gọn: tên, email (không @tên), chip trạng thái, ⚙️; không còn nút Chỉnh sửa hồ sơ / Đặt trạng thái.
        expect(find.text('Minh An'), findsOneWidget);
        expect(find.text('minhan@congtymau.vn'), findsOneWidget);
        expect(find.textContaining('@minhan'), findsNothing);
        expect(find.byKey(const ValueKey('apps-status-chip')), findsOneWidget);
        expect(find.text('Chỉnh sửa hồ sơ'), findsNothing);
        expect(find.text('Đặt trạng thái'), findsNothing);
        expect(find.byKey(const ValueKey('apps-check-update')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('apps-settings')));
        await t.tap(find.text('Minh An'));
        expect((settings, profile), (1, 1));
        // Lịch hôm nay: cả sự kiện đã xong (mờ), vạch bây giờ, đang diễn ra, sắp tới; rồi 7 ngày tới (tối đa 5).
        expect(find.byKey(const ValueKey('upcoming-events')), findsOneWidget);
        expect(find.text('Sắp diễn ra'), findsOneWidget);
        expect(find.text('HÔM NAY · T3 17/11'), findsOneWidget);
        expect(find.text('7 NGÀY TỚI'), findsOneWidget);
        expect(find.text('Đã xong'), findsOneWidget);
        expect(find.textContaining('đã xong'), findsOneWidget);
        expect(find.byKey(const ValueKey('upcoming-now')), findsOneWidget);
        // Banner = sự kiện gần nhất (đang diễn ra) + cùng sự kiện trong lịch hôm nay.
        expect(find.byKey(const ValueKey('upcoming-hero-countdown')), findsOneWidget);
        expect(find.text('Giao ban đầu tuần'), findsNWidgets(2));
        expect(find.text('Kiểm tra PCCC – Văn phòng'), findsOneWidget);
        expect(find.text('Gặp khách hàng'), findsOneWidget);
        expect(find.text('Đào tạo an toàn'), findsOneWidget);
        expect(find.textContaining('Đang diễn ra · '), findsOneWidget);
        expect(find.text('còn 40p'), findsNWidgets(2));
        expect(find.text('còn 3g 40p'), findsOneWidget);
        expect(find.text('Chưa trả lời'), findsOneWidget);
        expect(t.takeException(), isNull);
        await shot(t, 'd-desktop-$sfx');
        // Đồng hồ chạy: 1 giờ sau, giao ban đã xong (vẫn trong lịch hôm nay, mờ), PCCC còn 2 giờ 40 phút.
        clock = _now.add(const Duration(hours: 1));
        await t.pump(const Duration(seconds: 1));
        expect(find.text('Giao ban đầu tuần'), findsOneWidget);
        expect(find.textContaining('đã xong'), findsNWidgets(2));
        expect(find.text('Kiểm tra PCCC – Văn phòng'), findsNWidgets(2));
        expect(find.text('còn 2g 40p'), findsNWidgets(2));
        await t.tap(find.byKey(const ValueKey('upcoming-pccc')));
        expect(opened, ['pccc']);
        await t.tap(find.byKey(const ValueKey('upcoming-open-calendar')));
        expect(openedCal, 1);
        await done(t);
      });

      testWidgets('điện thoại: dải gọn ở đầu trang ($sfx)', (t) async {
        final opened = <String>[];
        await pumpHost(
            t,
            const Size(390, 844),
            b,
            (c) => ListView(padding: EdgeInsets.zero, children: [
                  // Thẻ người dùng gọn ở đầu trang điện thoại (như app thật), rồi tên công ty, rồi dải Lịch thu gọn.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 52, 20, 12),
                    child: Center(child: Text('Công ty Mẫu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Pal.of(c).text))),
                  ),
                  AppsUserCard(compact: true, dense: true, onProfile: () {}, onSettings: () {}),
                  UpcomingEvents(compact: true, clock: () => clock, onOpen: (e) => opened.add(e.instanceId)),
                  const SizedBox(height: 18),
                  tiles(Pal.of(c), demoTiles),
                ]));
        // Thu gọn: chỉ banner sự kiện gần nhất (biểu tượng, tên, giờ, nhãn đếm ngược).
        expect(find.text('Giao ban đầu tuần'), findsOneWidget);
        expect(find.text('còn 40p'), findsOneWidget);
        expect(find.textContaining('Đang diễn ra · '), findsOneWidget);
        expect(t.takeException(), isNull);
        await shot(t, 'p-phone-live-$sfx');
        clock = _now.add(const Duration(hours: 1));
        await t.pump(const Duration(seconds: 1));
        expect(find.text('Kiểm tra PCCC – Văn phòng'), findsOneWidget);
        expect(find.text('còn 2g 40p'), findsOneWidget);
        await shot(t, 'p-phone-next-$sfx');
        // Bấm dải: mở rộng thành lịch hôm nay + 7 ngày tới; bấm sự kiện mở sự kiện; ˄ thu lại.
        expect(find.text('HÔM NAY · T3 17/11'), findsNothing);
        await t.tap(find.byKey(const ValueKey('upcoming-banner')));
        await t.pump();
        expect(find.text('HÔM NAY · T3 17/11'), findsOneWidget);
        expect(find.text('7 NGÀY TỚI'), findsOneWidget);
        expect(find.text('Gặp khách hàng'), findsOneWidget);
        expect(t.takeException(), isNull);
        await shot(t, 'p-phone-expanded-$sfx');
        await t.tap(find.byKey(const ValueKey('upcoming-pccc')));
        expect(opened, ['pccc']);
        await t.tap(find.byKey(const ValueKey('upcoming-collapse')));
        await t.pump();
        expect(find.text('HÔM NAY · T3 17/11'), findsNothing);
        expect(find.byKey(const ValueKey('upcoming-banner')), findsOneWidget);
        await done(t);
      });
    }

    testWidgets('điện thoại: cuộn ra khỏi màn hình rồi quay lại vẫn hiện ngay, đang tải lại không ẩn, đếm ngược vẫn chạy', (t) async {
      var calls = 0;
      final slow = Completer<UpcomingData?>();
      upcomingLoader = (_) {
        calls++;
        // Lần đầu có dữ liệu; các lần sau treo (mạng chậm) để xem khối có bị ẩn khi đang tải không.
        return calls == 1 ? Future.value(UpcomingData(events: _events, tz: _tz)) : slow.future;
      };
      final ctl = ScrollController();
      await pumpHost(t, const Size(390, 600), Brightness.light, (c) => ListView(controller: ctl, children: [
            UpcomingEvents(compact: true, clock: () => clock),
            for (var i = 0; i < 40; i++) SizedBox(height: 80, child: Text('ô $i')),
          ]));
      final banner = find.byKey(const ValueKey('upcoming-events'));
      expect(banner, findsOneWidget);
      expect(find.text('còn 40p'), findsOneWidget);
      // Cuộn thật xa: ListView bỏ khối khỏi cây (State bị huỷ).
      ctl.jumpTo(2400);
      await t.pump();
      expect(banner, findsNothing);
      // Quay lại: hiện ngay ở khung hình đầu, dù lần tải mới chưa xong.
      ctl.jumpTo(0);
      await t.pump();
      expect(banner, findsOneWidget);
      expect(find.text('còn 40p'), findsOneWidget);
      expect(calls, 2);
      // Đếm ngược tự chạy, không cần tải lại.
      clock = _now.add(const Duration(minutes: 10));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('còn 30p'), findsOneWidget);
      expect(calls, 2);
      // Dữ liệu mới về thì mới thay.
      slow.complete(UpcomingData(events: [_events.firstWhere((e) => e.id == 'khach')], tz: _tz));
      await t.pump();
      await t.pump();
      expect(banner, findsOneWidget);
      expect(find.text('còn 30p'), findsNothing);
      expect(find.text('Gặp khách hàng'), findsOneWidget);
      expect(t.takeException(), isNull);
      await done(t);
    });

    for (final b in Brightness.values) {
      final sfx = b == Brightness.dark ? 'dark' : 'light';
      testWidgets('bảng Biểu tượng & màu: xem trước, chọn, Mặc định ($sfx)', (t) async {
        ({String? icon, String? color})? got;
        await pumpHost(t, const Size(620, 760), b, (c) => Center(
              child: TextButton(
                onPressed: () async => got = await showEventStylePicker(c, title: 'Kiểm tra PCCC – Văn phòng', subtitle: '17/11 14:30–16:00 · Văn phòng', wide: true),
                child: const Text('mở'),
              ),
            ));
        await t.tap(find.text('mở'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('style-preview')), findsOneWidget);
        expect(find.textContaining('Tự chọn theo tiêu đề: PCCC · màu Đỏ'), findsOneWidget);
        expect(t.takeException(), isNull);
        await shot(t, 'picker-$sfx');
        await t.tap(find.byKey(const ValueKey('style-icon-elevator')));
        await t.tap(find.byKey(const ValueKey('style-color-navy')));
        await t.pump();
        await t.tap(find.byKey(const ValueKey('style-done')));
        await t.pumpAndSettle();
        expect(got, (icon: 'elevator', color: 'navy'));
        await t.tap(find.text('mở'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('style-default')));
        await t.pumpAndSettle();
        expect(got, (icon: null, color: null));
        await done(t);
      });
    }

    testWidgets('sự kiện chỉ thông báo: không có nhãn "Chưa trả lời"', (t) async {
      final pccc = _events.firstWhere((e) => e.id == 'pccc').clone()..notice = true;
      upcomingLoader = (_) async => UpcomingData(events: [pccc], tz: _tz);
      await pumpHost(t, const Size(1280, 900), Brightness.light, (c) => ListView(children: [UpcomingEvents(clock: () => clock)]));
      expect(find.text('Kiểm tra PCCC – Văn phòng'), findsNWidgets(2));
      expect(find.text('Chưa trả lời'), findsNothing);
      await done(t);
    });

    testWidgets('ẩn khi không dùng được Lịch, không có sự kiện, hoặc tải lỗi', (t) async {
      for (final loader in <Future<UpcomingData?> Function(String)>[
        (_) async => null,
        (_) async => UpcomingData(events: [_events.first], tz: _tz),
        (_) async => throw Exception('mất mạng'),
      ]) {
        upcomingLoader = loader;
        upcomingResetCache();
        await pumpHost(t, const Size(390, 600), Brightness.light, (c) => ListView(children: [UpcomingEvents(compact: true, clock: () => clock)]));
        expect(find.byKey(const ValueKey('upcoming-events')), findsNothing);
        expect(t.takeException(), isNull);
        await done(t);
      }
    });
  });
}
