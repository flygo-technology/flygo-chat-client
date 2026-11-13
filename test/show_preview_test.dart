// Ảnh các màn Trình chiếu hiện tại (chạy tay, dữ liệu giả): SHOW_OUT=<thư mục> flutter test test/show_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mini_apps.dart';
import 'package:flygo_chat/api/show_api.dart';
import 'package:flygo_chat/ui/show_page.dart';
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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  // Theme Linux dùng 'Noto Sans': máy build không có, thay bằng Roboto (đủ dấu tiếng Việt).
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _titles = [
  'Doanh thu quý 3 tăng 18%',
  'Kênh bán: cửa hàng, online, đại lý',
  'Chi phí vận hành',
  'Khách hàng mới theo tháng',
  'Sản phẩm bán chạy',
  'Rủi ro và việc cần làm',
  'Kế hoạch quý 4',
  'Cảm ơn',
];

class _FakeShow extends ShowClient {
  final bool emptyDecks;
  _FakeShow({this.emptyDecks = false})
      : super(MiniApp.fromJson({'id': 'vn.flygo.show', 'name': 'Trình chiếu', 'base_url': 'https://show.example.com', 'native': {'screen': 'show'}}), 't') {
    perms = {'admin'};
  }

  @override
  Future<String> session({bool renew = false}) async => 's';

  @override
  ShowLive live(String pid) => ShowLive.offline(this, pid);

  Map<String, dynamic> get _deck => {
        'id': 'd1',
        'title': 'Báo cáo kinh doanh quý 3',
        'rev': 1,
        'languages': ['vi', 'en'],
        'slides': [
          for (final (i, t) in _titles.indexed)
            {
              'title': t,
              'summary': 'Tóm tắt ý chính của trang ${i + 1}: số liệu, so sánh cùng kỳ và nhận xét ngắn.',
              'steps': i == 2 ? 2 : 0,
              if (i == 2) 'notes': 'Nhấn mạnh: chi phí kho giảm nhờ gom đơn theo tuyến. Nhắc số liệu tháng 9 là ước tính.',
              if (i == 5) 'hidden': true,
            },
        ],
        'flow': [
          for (final (i, t) in _titles.indexed) {'type': 'slide', 'slide': i + 1, 'title': t, 'hidden': i == 5},
        ],
      };

  /// Các tool đã gọi (để kiểm phím tắt).
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> call(String name, [Map<String, dynamic> params = const {}]) async {
    calls.add(name);
    switch (name) {
      case 'deck_list':
        return {
          'decks': emptyDecks
              ? []
              : [
                  {'id': 'd1', 'title': 'Báo cáo kinh doanh quý 3', 'slides': 8, 'owner_name': 'Nguyễn An', 'updated_at': DateTime.now().toIso8601String()},
                  {'id': 'd2', 'title': 'Giới thiệu sản phẩm IoT cho đối tác', 'slides': 12, 'owner_name': 'Nguyễn An', 'updated_at': '2026-11-08T09:12:00'},
                  {'id': 'd3', 'title': 'Đào tạo nhân viên mới tháng 11', 'slides': 15, 'owner_name': 'Trần Bình', 'updated_at': '2026-11-05T14:30:00'},
                  {'id': 'd4', 'title': 'Hội chợ: chiếu lặp tại gian hàng', 'slides': 6, 'owner_name': 'Trần Bình', 'updated_at': '2026-10-30T08:00:00'},
                ].where((d) => params['mine'] != true || d['owner_name'] == 'Nguyễn An').toList(),
        };
      case 'show_list':
        return {
          'presentations': [
            {'presentation_id': 'p1', 'title': 'Báo cáo kinh doanh quý 3', 'slide': 3, 'total': 8, 'screens': 1, 'presenter_name': 'Nguyễn An'},
          ],
        };
      case 'deck_get':
        return _deck;
      case 'show_status':
        return {
          'presentation_id': 'p1',
          'title': 'Báo cáo kinh doanh quý 3',
          'deck_id': 'd1',
          'deck_rev': 1,
          'slide': 3,
          'scene': 'slide',
          'step': 1,
          'steps': 2,
          'total': 8,
          'slide_title': _titles[2],
          'summary': 'Chi phí giảm 6% nhờ tối ưu kho và vận chuyển.',
          'can_control': true,
          'screen_count': 1,
          'languages': ['vi', 'en'],
          'autopilot': {},
          'music': {'on': true, 'style': 'tech', 'volume': .3},
          'comment_count': 2,
          'presenter_name': 'Nguyễn An',
          'notes': 'Nhấn mạnh: chi phí kho giảm nhờ gom đơn theo tuyến. Nhắc số liệu tháng 9 là ước tính.',
          'docs': 2,
          'open_notes': 1,
          'screens': [
            {'screen_id': 'sc1', 'name': 'TV phòng họp lớn', 'paired_at': DateTime.now().millisecondsSinceEpoch, 'slide': 'vi', 'audio': 'vi', 'sub': 'vi'},
          ],
          'pages': [
            {'scene': 'waiting', 'title': 'Màn chờ'},
            for (final (i, t) in _titles.indexed)
              {'scene': 'slide', 'slide': i + 1, 'title': t, 'summary': 'Tóm tắt ý chính của trang ${i + 1}: số liệu, so sánh cùng kỳ và nhận xét ngắn.'},
            {'scene': 'qa', 'title': 'Hỏi & Đáp'},
            {'scene': 'end', 'title': 'Kết thúc'},
          ],
          'flow': _deck['flow'],
        };
      case 'screen_invite':
        return {'url': 'https://show.example.com/tv?invite=abc', 'expires_in_s': 86400};
      case 'comment_list':
        return {'comments': []};
      case 'screen_list':
        return {'screens': []};
    }
    return {};
  }
}

void main() {
  final out = Platform.environment['SHOW_OUT'];
  // Test không có WebViewPlatform: tắt mọi webview để chạy giống nhau trên Linux, macOS, Windows.
  showWebPreviewOverride = false;

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage(pixelRatio: 1.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> app(WidgetTester t, Widget home, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: home),
    ));
    for (var i = 0; i < 10; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  const desk = Size(1440, 900), phone = Size(390, 844);

  testWidgets('Trình chiếu máy tính', (t) async {
    if (out != null) await t.runAsync(_fonts);
    addTearDown(t.view.reset);
    final c = _FakeShow();

    await app(t, ShowHome(app: c.app, mmToken: 't', client: c, key: UniqueKey()), desk);
    expect(find.text('Đào tạo nhân viên mới tháng 11'), findsWidgets);
    expect(find.text('Trang 1 · Doanh thu quý 3 tăng 18%'), findsOneWidget);
    await shot(t, 'desktop-1-trang-chu');

    // ← → chọn trang ở khung phải.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(find.text('Trang 3 · Chi phí vận hành'), findsOneWidget);
    await shot(t, 'desktop-2-chon-trang');

    await t.tap(find.ancestor(of: find.text('Trình chiếu'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    await t.pumpAndSettle();
    expect(find.text('Bắt đầu trình chiếu'), findsOneWidget);
    await t.enterText(find.byType(TextField).last, 'XKF36G');
    await t.pump();
    await shot(t, 'desktop-3-bat-dau');

    await app(t, ShowControlPage(client: c, pid: 'p1', key: UniqueKey()), desk);
    expect(find.text('GHI CHÚ NGƯỜI NÓI'), findsOneWidget);
    await shot(t, 'desktop-4-dieu-khien');

    // Phím tắt: → Tiếp, ← Trước, 5 Enter nhảy trang; gõ trong ô phụ đề thì Space không chuyển trang.
    c.calls.clear();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await t.sendKeyEvent(LogicalKeyboardKey.digit5);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(c.calls.where((x) => x.startsWith('show_')).toList(), ['show_next', 'show_prev', 'show_goto']);

    await t.tap(find.widgetWithText(Tab, 'Màn hình'));
    await t.pumpAndSettle();
    await shot(t, 'desktop-5-man-hinh');
    // Copy link ghép: lấy link ghép sẵn của buổi.
    c.calls.clear();
    await t.tap(find.text('Copy link ghép'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(c.calls, contains('screen_invite'));
    expect(find.text('Mở trên máy này'), findsOneWidget);
    await t.pumpAndSettle(const Duration(seconds: 5));

    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.pumpAndSettle();
    c.calls.clear();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(c.calls.contains('show_next'), isFalse);
    await t.enterText(find.byType(TextField).last, 'Xin chào mọi người');
    await t.pump();
    await shot(t, 'desktop-6-phu-de');

    await app(t, ShowControlPage(client: c, pid: 'p1', key: UniqueKey()), const Size(1024, 768));
    await shot(t, 'desktop-7-dieu-khien-1024');
  });

  testWidgets('Trình chiếu điện thoại', (t) async {
    if (out != null) await t.runAsync(_fonts);
    addTearDown(t.view.reset);
    final c = _FakeShow();

    await app(t, ShowHome(app: c.app, mmToken: 't', client: c, key: UniqueKey()), phone);
    await shot(t, 'phone-1-danh-sach');

    await app(t, DeckDetailPage(client: c, deckId: 'd1', title: 'Báo cáo kinh doanh quý 3', key: UniqueKey()), phone);
    await shot(t, 'phone-2-chi-tiet');

    await app(t, ShowControlPage(client: c, pid: 'p1', key: UniqueKey()), phone);
    await shot(t, 'phone-3-dieu-khien');
    await t.tap(find.widgetWithText(Tab, 'Màn hình'));
    await t.pumpAndSettle();
    await shot(t, 'phone-4-man-hinh');
    await t.tap(find.widgetWithText(Tab, 'Phụ đề'));
    await t.pumpAndSettle();
    await shot(t, 'phone-5-phu-de');
  });

  testWidgets('Trình chiếu trống', (t) async {
    if (out != null) await t.runAsync(_fonts);
    addTearDown(t.view.reset);
    final c = _FakeShow(emptyDecks: true);
    await app(t, ShowHome(app: c.app, mmToken: 't', client: c), desk);
    expect(find.text('Chưa có bài trình chiếu'), findsOneWidget);
    await shot(t, 'desktop-0-trong');
  });
}
