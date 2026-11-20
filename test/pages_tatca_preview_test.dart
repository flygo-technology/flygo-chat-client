// Bảng kéo lên Trang họp, tab "Tất cả" (mỗi người một hàng): dựng widget thật với dữ liệu giả (relay giả qua MockClient).
// Ảnh xem trước (chạy tay): TATCA_OUT=<thư mục> flutter test test/pages_tatca_preview_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/pages/pages_sheet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  await load('Flygo Inter', [for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$f.ttf']);
}

const _ch = 'cccccccccccccccccccccccccc';
final _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _p(String id, String type, String title, String owner, String name, {String vis = 'meeting', int secs = 0, int order = 0, Map<String, dynamic>? file}) => {
      'id': id, 'type': type, 'title': title, 'owner': owner, 'owner_name': name, 'meeting': 'abc-defg-hij', 'visibility': vis, 'seconds': secs, 'order': order,
      'rev': 2, 'created_at': order, 'updated_at': order, 'content': {'file': ?file},
    };

final _pages = [
  _p('p1', 'agenda', 'Chương trình họp', 'loi', 'Nguyễn Văn Lợi', secs: 300, order: 0),
  _p('p2', 'doc', 'Tiến độ lắp đặt tòa B', 'loi', 'Nguyễn Văn Lợi', secs: 600, order: 1, file: {'name': 'TienDo.pptx', 'pages': 9}),
  _p('p3', 'poll', 'Chọn ngày bàn giao', 'loi', 'Nguyễn Văn Lợi', secs: 120, order: 2),
  _p('p4', 'doc', 'Hợp đồng T11', 'kim', 'Mai Kim', secs: 480, order: 0, file: {'name': 'HopDong.xlsx', 'pages': 4}),
  _p('p5', 'qa', 'Hỏi đáp báo giá', 'kim', 'Mai Kim', order: 1),
  _p('p6', 'welcome', 'Chào mừng', 'me', 'Dương Văn Ba', order: 0),
  _p('p7', 'doc', 'Kế hoạch Q4', 'me', 'Dương Văn Ba', vis: 'private', secs: 360, order: 1, file: {'name': 'KeHoachQ4.pptx', 'pages': 12}),
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

AppState _app({required bool host}) {
  final app = AppState('t');
  final names = {'me': ('Ba', 'Dương Văn'), 'loi': ('Lợi', 'Nguyễn Văn'), 'kim': ('Kim', 'Mai'), 'minh': ('Minh', 'Lê'), 'quang': ('Quang', 'Trần')};
  for (final e in names.entries) {
    final u = MmUser({'id': e.key, 'username': e.key, 'first_name': e.value.$2, 'last_name': e.value.$1});
    app.users[e.key] = u;
  }
  app.me = app.users['me'];
  final c = app.calls;
  c.channelId = _ch;
  c.roomHost = host ? 'me' : 'loi';
  c.roomStage = {
    'presenter': 'loi', 'presenter_name': 'Nguyễn Văn Lợi', 'queue': [{'id': 'kim', 'name': 'Mai Kim', 'at': 1}],
    'page': 'p2', 'page_type': 'doc', 'page_title': 'Tiến độ lắp đặt tòa B', 'mode': 'auto', 'ends_at': _now + 252000, 'paused': false,
  };
  return app;
}

final _shotKey = GlobalKey();
Future<void> _shot(WidgetTester t, String name) async {
  final dir = Platform.environment['TATCA_OUT'];
  if (dir == null) return;
  await t.runAsync(() async {
    final ro = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Khung cuộc họp giả phía sau bảng (sân khấu đang chiếu slide).
Widget _meeting(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xFF16181C),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(children: [
              Text('Giao ban tháng 12', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              Spacer(),
              Text('● Lợi đang chiếu', style: TextStyle(color: Color(0xFFFFB4AE), fontSize: 12)),
            ]),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: FractionallySizedBox(
                widthFactor: .88,
                heightFactor: .8,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tiến độ lắp đặt tòa B', style: TextStyle(color: Color(0xFF0E5C55), fontSize: 20, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text('• Đạt 70%, chậm 4 ngày\n• Giao ray 25/11', style: TextStyle(color: Color(0xFF1B2430), fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.all(10), child: Text('▤ TienDo.pptx · 3/9 · còn 04:12', style: TextStyle(color: Colors.white70, fontSize: 12))),
        ]),
      ),
    );

Future<BuildContext> _pump(WidgetTester t, AppState app, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  late BuildContext ctx;
  await t.pumpWidget(RepaintBoundary(
    key: _shotKey,
    child: ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Flygo Inter')),
        home: Builder(builder: (c) {
          ctx = c;
          return DefaultTextStyle.merge(style: const TextStyle(fontFamily: 'Flygo Inter'), child: _meeting(c));
        }),
      ),
    ),
  ));
  return ctx;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
  debugIsDesktop = null;
}

void main() {
  setUpAll(_fonts);

  testWidgets('điện thoại: bảng thấp, cao hết, menu thẻ, xem trang người khác, soạn trang', (t) async {
    debugIsDesktop = false;
    await http.runWithClient(() async {
      final app = _app(host: false);
      final ctx = await _pump(t, app, const Size(390, 844));
      showPagesSheet(ctx, app.calls);
      await _settle(t);
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Thêm trang'), findsOneWidget);
      await _shot(t, '1-bang-thap');

      await t.dragFrom(const Offset(195, 470), const Offset(0, -700));
      await _settle(t);
      await _shot(t, '2-tat-ca-cao-het');

      await t.longPress(find.text('Kế hoạch Q4'));
      await _settle(t);
      expect(find.text('Xin lượt và chiếu trang này'), findsOneWidget);
      await _shot(t, '3-menu-the-cua-toi');
      await t.tapAt(const Offset(195, 40));
      await _settle(t);

      await t.tap(find.text('Hỏi đáp báo giá'));
      await _settle(t);
      expect(find.text('Về sân khấu'), findsOneWidget);
      await _shot(t, '4-xem-trang-nguoi-khac');
      await t.tap(find.byIcon(Icons.arrow_back_rounded));
      await _settle(t);
      await t.dragFrom(const Offset(195, 470), const Offset(0, -700));
      await _settle(t);

      await t.tap(find.text('Kế hoạch Q4'));
      await _settle(t);
      expect(find.text('Thời lượng (tự chạy)'), findsOneWidget);
      await _shot(t, '5-soan-trang');
      await _done(t);
    }, () => _relay(host: false));
  });

  testWidgets('điện thoại: chủ trì thấy số trang và trao lượt', (t) async {
    debugIsDesktop = false;
    await http.runWithClient(() async {
      final app = _app(host: true);
      final ctx = await _pump(t, app, const Size(390, 844));
      showPagesSheet(ctx, app.calls);
      await _settle(t);
      await t.dragFrom(const Offset(195, 470), const Offset(0, -700));
      await _settle(t);
      expect(find.text('Trao lượt'), findsWidgets);
      expect(find.text('3 trang chưa công khai'), findsOneWidget);
      await _shot(t, '6-chu-tri');
      await _done(t);
    }, () => _relay(host: true));
  });

  testWidgets('máy tính', (t) async {
    debugIsDesktop = true;
    await http.runWithClient(() async {
      final app = _app(host: false);
      final ctx = await _pump(t, app, const Size(1440, 900));
      showPagesSheet(ctx, app.calls);
      await _settle(t);
      await t.dragFrom(const Offset(720, 520), const Offset(0, -250));
      await _settle(t);
      await _shot(t, '7-may-tinh');
      await _done(t);
    }, () => _relay(host: false));
  });
}
