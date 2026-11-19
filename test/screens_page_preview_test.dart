// Ảnh xem trước app Màn hình (danh sách + chi tiết) với trạm giả: SHOTS=<thư mục> flutter test test/screens_page_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/cast/screens_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f.startsWith('assets/') ? f : '$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _screens = [
  {
    'id': 'a' * 22,
    'name': 'Phòng họp 3F-A',
    'location': 'Văn phòng YLA',
    'online': true,
    'approved': true,
    'status': 'casting',
    'now_by': 'Mai Kim',
    'now_name': 'Bao-cao-Q4.pdf',
    'queue': 1,
  },
  {
    'id': 'b' * 22,
    'name': 'Phòng họp 2F',
    'location': 'Văn phòng YLA',
    'online': true,
    'approved': true,
    'status': 'meeting',
    'lock': {
      'by_name': 'Ba Nguyễn',
      'meeting': {'title': 'Giao ban kinh doanh'},
    },
  },
  {
    'id': 'c' * 22,
    'name': 'TV sảnh lễ tân',
    'location': 'Văn phòng YLA',
    'online': true,
    'approved': true,
    'status': 'schedule',
    'schedule': 'Bảng tin xoay 15 giây',
  },
  {
    'id': 'd' * 22,
    'name': 'TV phòng giám đốc',
    'location': 'Văn phòng YLA',
    'online': true,
    'approved': true,
    'status': 'locked',
    'lock': {'by_name': 'Ba Nguyễn'},
  },
  {'id': 'e' * 22, 'name': 'Màn LED mặt tiền', 'location': 'Showroom Hà Nội', 'online': true, 'approved': true, 'status': 'idle'},
  {'id': 'f' * 22, 'name': 'Kiosk tư vấn', 'location': 'Showroom Hà Nội', 'online': false, 'approved': true, 'status': 'idle'},
  {'id': 'g' * 22, 'name': 'Màn hình 9', 'location': '', 'online': true, 'approved': false, 'status': 'idle'},
];
final _detail = {
  'id': 'a' * 22,
  'name': 'Phòng họp 3F-A',
  'location': 'Văn phòng YLA · tầng 3',
  'device': 'TV · Chrome',
  'online': true,
  'approved': true,
  'trusted': true,
  'status': 'casting',
  'now_by': 'Mai Kim',
  'content': {'type': 'pdf', 'name': 'Bao-cao-Q4.pdf', 'page': 4, 'pages': 12},
  'queue': ['Thu Hà'],
  'manager': true,
  'today': {'casts': 14, 'people': 6},
  'schedules': [
    {
      'id': 's1',
      'days': [1, 2, 3, 4, 5],
      'from': '09:30',
      'to': '10:30',
      'title': 'Giao ban sáng',
      'content': {'type': 'meeting', 'code': 'abc-defg-hij'},
      'by_name': 'Ba Nguyễn',
    },
    {
      'id': 's2',
      'days': [1, 2, 3, 4, 5, 6, 7],
      'from': '19:00',
      'to': '23:59',
      'title': 'Tắt màn hình',
      'content': {'type': 'blank'},
      'by_name': 'Ba Nguyễn',
    },
  ],
};

void main() {
  final out = Platform.environment['SHOTS'];
  final client = MockClient((r) async {
    if (r.url.path == '/health') return http.Response('{"status":"OK"}', 200);
    const json = {'content-type': 'application/json; charset=utf-8'};
    if (r.url.path == '/cast/screens') return http.Response(jsonEncode({'screens': _screens}), 200, headers: json);
    if (r.url.path.startsWith('/cast/screens/')) return http.Response(jsonEncode(_detail), 200, headers: json);
    return http.Response('{}', 404);
  });

  Future<void> shot(WidgetTester t, Widget page, String name) async {
    final key = GlobalKey();
    t.view.physicalSize = const Size(390, 844) * 2;
    t.view.devicePixelRatio = 2;
    await http.runWithClient(() async {
      await t.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: AppState('t'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Noto Sans'),
            home: RepaintBoundary(key: key, child: page),
          ),
        ),
      );
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await t.pump(const Duration(milliseconds: 100));
    }, () => client);
    expect(t.takeException(), isNull);
    if (out != null) {
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ImageByteFormat.png);
        await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await t.pumpWidget(const SizedBox());
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    kServerUrl = 'https://chat.flygo.vn';
    await _fonts();
  });

  testWidgets('danh sách màn hình', (t) => shot(t, const ScreensPage(), 'man-hinh-list'));
  testWidgets('chi tiết màn hình', (t) => shot(t, const ScreenDetailPage(id: 'aaaaaaaaaaaaaaaaaaaaaa', name: 'Phòng họp 3F-A'), 'man-hinh-detail'));
}
