// Ghi chú ghim lên Trang chủ (Sếp, 2026-11-17). Ảnh xem trước (chạy tay): NOTES_OUT=<thư mục> flutter test test/home_pinned_notes_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/ui/todo/home_notes_section.dart';
import 'package:flygo_chat/ui/todo/home_pins.dart';
import 'package:flygo_chat/ui/todo/model.dart';

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

TBlock _b(String text, {String t = 'p', bool done = false}) => TBlock(t: t, r: [TRun(text)], done: done);

void main() {
  final out = Platform.environment['NOTES_OUT'];
  final pins = HomeNotePins.instance;
  tearDown(() => pins.debugSet(const []));

  final list = TNote(id: 'n_list01', title: 'Việc tuần này', color: 'sand', blocks: [
    _b('Gửi báo giá thang máy', t: 'check', done: true),
    _b('Đối soát hoá đơn VAT tháng 11', t: 'check'),
    _b('Gọi lại anh Tuấn', t: 'check'),
    _b('Duyệt hợp đồng vận chuyển', t: 'check', done: true),
    _b('Đặt phòng họp thứ Năm', t: 'check'),
  ]);
  final note = TNote(id: 'n_note01', title: '', blocks: [_b('Mật khẩu wifi khách: hỏi lễ tân'), _b('Giờ làm việc 8:00 – 17:30')]);

  test('tóm tắt ghi chú: danh sách có tiến độ + các mục chưa xong; ghi chú thường có vài dòng đầu', () {
    final a = HomeNotePin.fromNote(list);
    expect((a.kind, a.done, a.total), ('list', 2, 5));
    expect(a.lines, ['Đối soát hoá đơn VAT tháng 11', 'Gọi lại anh Tuấn', 'Đặt phòng họp thứ Năm']);
    final b = HomeNotePin.fromNote(note);
    expect((b.kind, b.title, b.lines.length), ('note', '', 2));
    expect(HomeNotePin.fromJson(a.toJson()).sameAs(a), isTrue);
  });

  test('ghim / bỏ ghim; mới ghim đứng trước; đồng bộ từ thiết bị khác; làm mới theo Ghi chú', () {
    expect(pins.toggle(list), isTrue);
    expect(pins.toggle(note), isTrue);
    expect(pins.pins.first.id, 'n_note01');
    expect(pins.toggle(list), isFalse);
    expect(pins.has('n_list01'), isFalse);
    // preferences_changed từ thiết bị khác.
    pins.onPref({'category': 'flygo_chat', 'name': kHomeNotesPref, 'value': '[{"id":"x1","title":"A","at":2},{"id":"x2","at":5}]'}, deleted: false);
    expect([for (final p in pins.pins) p.id], ['x2', 'x1']);
    pins.onPref({'category': 'other', 'name': kHomeNotesPref, 'value': '[]'}, deleted: false);
    expect(pins.pins.length, 2);
    // Ghi chú đổi tiêu đề → bản tóm tắt đổi; ghi chú không còn (đã tải đủ) → bỏ ghim; chưa tải đủ thì giữ.
    pins.debugSet([HomeNotePin.fromNote(list, at: 1), HomeNotePin.fromNote(note, at: 2)]);
    list.title = 'Việc tuần sau';
    pins.refreshFrom({'n_list01': list}, loaded: false);
    expect(pins.pins.map((p) => p.title), contains('Việc tuần sau'));
    expect(pins.has('n_note01'), isTrue);
    pins.refreshFrom({'n_list01': list}, loaded: true);
    expect(pins.has('n_note01'), isFalse);
    list.title = 'Việc tuần này';
    pins.onPref({'category': 'flygo_chat', 'name': kHomeNotesPref}, deleted: true);
    expect(pins.pins, isEmpty);
  });

  final key = GlobalKey();
  List<HomeNotePin> sample() => [
        HomeNotePin.fromNote(list, at: 9),
        HomeNotePin.fromNote(note, at: 8),
        HomeNotePin.fromNote(TNote(id: 'n_c', title: 'Số tài khoản công ty', color: 'fog', blocks: [_b('Techcombank 1903 …8868'), _b('VPBank …2210')]), at: 7),
        HomeNotePin.fromNote(TNote(id: 'n_d', title: 'Đồ cần mua văn phòng', color: 'mint', blocks: [_b('Giấy A4', t: 'check'), _b('Mực in', t: 'check', done: true), _b('Cà phê', t: 'check')]), at: 6),
        HomeNotePin.fromNote(TNote(id: 'n_e', title: 'Ý tưởng Tết 2027', color: 'blossom', blocks: [_b('Lì xì nhân viên bằng app'), _b('Thiệp điện tử')]), at: 5),
        HomeNotePin.fromNote(TNote(id: 'n_f', title: 'Lịch trực tuần', blocks: [_b('T2 Lan · T3 Nam · T4 My')]), at: 4),
        HomeNotePin.fromNote(TNote(id: 'n_g', title: 'Mã cổng kho', blocks: [_b('2580#')]), at: 3),
      ];

  Future<void> shot(WidgetTester t, String name, Size size, Brightness b, Widget body, {double ratio = 1}) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = size * ratio;
    t.view.devicePixelRatio = ratio;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: body)));
    await t.pump(const Duration(milliseconds: 200));
    if (out == null) return;
    await t.runAsync(() async {
      await Directory(out).create(recursive: true);
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: ratio);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  // Khung giống Trang chủ (ảnh xem trước): cột trái thẻ người dùng + sự kiện + ghi chú ghim; điện thoại: dưới sự kiện.
  Widget placeholder(BuildContext c, String text, double h) => Container(
        height: h,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Pal.of(c).surface, borderRadius: BorderRadius.circular(18)),
        child: Text(text, style: TextStyle(color: Pal.of(c).sub)),
      );
  final opened = <String>[];
  Widget desktop() => Scaffold(
        body: Builder(
          builder: (c) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 400,
              child: ListView(padding: const EdgeInsets.only(top: 24), children: [
                placeholder(c, '(thẻ người dùng)', 220),
                placeholder(c, '(sự kiện sắp tới)', 90),
                HomePinnedNotes(onOpen: opened.add, padding: const EdgeInsets.fromLTRB(16, 18, 16, 4)),
              ]),
            ),
            Expanded(child: Center(child: Text('(lưới ứng dụng)', style: TextStyle(color: Pal.of(c).sub)))),
          ]),
        ),
      );
  Widget phone() => Scaffold(
        body: Builder(
          builder: (c) => ListView(padding: const EdgeInsets.only(top: 12), children: [
            placeholder(c, '(tên công ty + thẻ người dùng)', 150),
            placeholder(c, '(sự kiện sắp tới)', 70),
            HomePinnedNotes(onOpen: opened.add),
            placeholder(c, '(mục Chính)', 200),
          ]),
        ),
      );

  testWidgets('Trang chủ máy tính: 6 thẻ + Xem tất cả; bấm thẻ mở ghi chú; bỏ ghim từ menu thẻ', (t) async {
    pins.debugSet(sample());
    opened.clear();
    await shot(t, 'home-notes-desktop-dark', const Size(1440, 900), Brightness.dark, desktop());
    expect(find.text('GHI CHÚ ĐÃ GHIM'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-note-n_g')), findsNothing);
    expect(find.text('Xem tất cả (7)'), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);
    await t.tap(find.text('Việc tuần này'));
    expect(opened, ['n_list01']);
    await t.tap(find.descendant(of: find.byKey(const ValueKey('home-note-n_c')), matching: find.byType(PopupMenuButton<String>)));
    await t.pumpAndSettle();
    await t.tap(find.text('Bỏ ghim trang chủ'));
    await t.pump(const Duration(milliseconds: 300));
    expect(pins.has('n_c'), isFalse);
    expect(find.byKey(const ValueKey('home-note-n_g')), findsOneWidget);
    expect(find.text('Xem tất cả (6)'), findsNothing);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Trang chủ máy tính sáng + Xem tất cả', (t) async {
    pins.debugSet(sample());
    await shot(t, 'home-notes-desktop-light', const Size(1440, 900), Brightness.light, desktop());
    await t.tap(find.text('Xem tất cả (7)'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-note-n_g')), findsWidgets);
    if (out != null) {
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/home-notes-desktop-light-all.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });

  testWidgets('điện thoại sáng + tối; không ghim gì thì không hiện mục', (t) async {
    pins.debugSet(sample().take(4).toList());
    await shot(t, 'home-notes-phone-light', const Size(390, 844), Brightness.light, phone(), ratio: 2);
    expect(find.text('GHI CHÚ ĐÃ GHIM'), findsOneWidget);
    await shot(t, 'home-notes-phone-dark', const Size(390, 844), Brightness.dark, phone(), ratio: 2);
    pins.debugSet(const []);
    await t.pump();
    expect(find.text('GHI CHÚ ĐÃ GHIM'), findsNothing);
  });
}
