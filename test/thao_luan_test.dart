// Thảo luận (bài riêng tư của Bảng tin, 21/11): màn hình điện thoại (nền sáng / tối), soạn quan điểm, trang Thảo luận trên sân khấu.
// Ảnh xem trước (chạy tay): BT_OUT=<thư mục> [BT_EMOJI=<NotoColorEmoji.ttf>] flutter test test/thao_luan_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/bang_tin/api.dart';
import 'package:flygo_chat/ui/bang_tin/bang_tin_page.dart';
import 'package:flygo_chat/ui/bang_tin/discussion_page.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/stage_frame.dart';
import 'package:flygo_chat/ui/pages/types/discuss.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '/mnt/d2/flygo-build/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<File> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      if (f.existsSync()) l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await l.load();
  }

  await load('MaterialIcons', [File('$dir/MaterialIcons-Regular.otf')]);
  await load('Noto Sans', [
    for (final f in ['noto/NotoSans-Regular.ttf', 'noto/NotoSans-Bold.ttf', 'dejavu/DejaVuSans.ttf', 'dejavu/DejaVuSans-Bold.ttf']) File('/usr/share/fonts/truetype/$f'),
  ]);
  await load('Inter', [for (final f in ['Inter-Regular.ttf', 'Inter-Bold.ttf', 'Inter-SemiBold.ttf']) File('assets/fonts/$f')]);
  final emoji = Platform.environment['BT_EMOJI'];
  if (emoji != null) await load('Noto Color Emoji', [File(emoji)]);
}

final _now = DateTime.now().millisecondsSinceEpoch;
Map<String, dynamic> _op(String id, String author, String body, String? stance, {int likes = 0, int dislikes = 0, int comments = 0, bool discussing = false, bool mine = false, List<Map<String, dynamic>> replies = const []}) => {
      'id': id, 'title': '', 'body_preview': body, 'excerpt': body, 'author': {'id': author == 'Ẩn danh' ? '' : author.toLowerCase(), 'name': author}, 'author_admin': false,
      'audience_kind': 'custom', 'created_at': _now - 600000, 'updated_at': _now - 600000, 'pinned': false, 'images': <String>[], 'image_count': 0, 'tags': <Map>[],
      'comments': comments, 'attachments': 0, 'shares': 0, 'read': true, 'acked': false, 'require_ack': false,
      'reactions': {if (likes > 0) '👍': likes, if (dislikes > 0) '👎': dislikes}, 'my_reactions': <String>[],
      'discussion': 'D1', 'stance': stance, 'anon': author == 'Ẩn danh', 'hidden': false, 'discussing': discussing, 'likes': likes, 'dislikes': dislikes, 'mine': mine,
      'latest_replies': replies, 'can_delete': mine, 'can_hide': true,
    };

void main() {
  final out = Platform.environment['BT_OUT'];
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final calls = <String>[];
  final posted = <Map<String, dynamic>>[];

  Map<String, dynamic> listBody() => {
        'discussion': {
          'id': 'D1', 'title': 'Giao ban kỹ thuật', 'question': 'Có nên chia 2 đội tăng ca để kịp bàn giao tòa B trước 15/12?', 'stance': true, 'closed': false, 'locked': false,
          'can_manage': true, 'members': 26, 'counts': {'posts': 20, 'replies': 41, 'people': 18}, 'stance_counts': {'y': 12, 'n': 5, 'o': 3},
        },
        'pinned': _op('p1', 'Nguyễn Văn Lợi', 'Chia 2 đội, mỗi ca 6 tiếng. Đội lắp ray làm sáng, đội đấu điện làm chiều, không giẫm chân nhau ở hố thang.', 'y',
            likes: 14, comments: 4, discussing: true, replies: [
              {'id': 'c1', 'author': {'name': 'Mai Kim'}, 'body': 'Kho Long Biên giao ray ngày 25/11, kịp cho đội sáng.'},
              {'id': 'c2', 'author': {'name': 'Ẩn danh'}, 'body': '@Mai Kim còn cáp tải thì sao, đã có lịch chưa?'},
            ]),
        'posts': [
          _op('p2', 'Trần Quang', 'Tăng ca kéo dài 3 tuần thì an toàn lao động khó giữ. Nên thuê thêm 1 tổ lắp ngoài.', 'n', likes: 9, dislikes: 2, comments: 2),
          _op('p3', 'Ẩn danh', 'Lắp song song thang 1 và 2, ưu tiên thang tải trước để chở vật tư.', 'o', likes: 7),
          ...posted,
        ],
      };

  http.Client backend() => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}${req.url.query.isEmpty ? '' : '?${req.url.query}'}');
        final p = req.url.path;
        Object? body;
        if (p == '/v1/token') body = {'token': 'jwt', 'expires_in': 600, 'scope': ['use']};
        if (p == '/bt/api/me') body = {'user': {'id': 'me', 'name': 'Ba'}, 'admin': false, 'categories': []};
        if (p == '/bt/api/discussions/D1/posts') body = listBody();
        if (p == '/bt/api/posts' && req.method == 'POST') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          posted.add(_op('p9', 'Ba', '${b['body']}', b['stance'] as String?, mine: true));
          body = {'post': posted.last};
        }
        if (p == '/bt/api/posts/p2/reactions' && req.method == 'POST') body = {'reactions': {'👍': 10}, 'my_reactions': ['👍']};
        return body == null ? http.Response('{"error":"không có"}', 404) : http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
      });

  BangTinApi api() {
    final c = backend();
    return BangTinApi(base: 'https://chat.test/bt', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: c), client: c);
  }

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester t, Widget child, {Size size = const Size(400, 860), Brightness theme = Brightness.light}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    if (out != null) await t.runAsync(_fonts);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(key: const ValueKey('shot'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(theme), home: child)),
    ));
    await settle(t);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  final me = BangTinMe('me', 'Ba', false, const []);

  for (final (name, theme) in [('sang', Brightness.light), ('toi', Brightness.dark)]) {
    testWidgets('điện thoại ($name): câu hỏi, tỉ lệ lập trường, đang bàn + trả lời mới, lập trường từng quan điểm, 👍 / 👎', (t) async {
      calls.clear();
      await pump(t, DiscussionPage(api: api(), me: me, discussionId: 'D1', live: false), theme: theme, size: const Size(400, 1300));
      expect(find.textContaining('chia 2 đội tăng ca'), findsOneWidget);
      expect(find.text('12 Đồng ý'), findsOneWidget);
      expect(find.text('ĐANG BÀN'), findsOneWidget);
      expect(find.text('Phản đối'), findsWidgets);
      expect(find.textContaining('Kho Long Biên'), findsOneWidget);
      expect(find.text('Xem cả 4 trả lời'), findsOneWidget);
      expect(find.text('Trả lời'), findsWidgets); // nút bình luận gọi là "Trả lời"
      expect(find.text('Chia sẻ'), findsNothing); // riêng tư: không chia sẻ ra ngoài
      await shot(t, 'thao-luan-dien-thoai-$name');
    });
  }

  testWidgets('soạn quan điểm: chọn lập trường, ẩn danh, gửi; lọc / sắp xếp gọi lại máy chủ', (t) async {
    calls.clear();
    posted.clear();
    await pump(t, DiscussionPage(api: api(), me: me, discussionId: 'D1', live: false));
    await t.tap(find.byKey(const ValueKey('opinion-new')));
    await settle(t, 3);
    await t.tap(find.byKey(const ValueKey('stance-n')));
    await t.enterText(find.byKey(const ValueKey('opinion-text')), 'Nên giữ ca sáng dài hơn');
    await t.tap(find.text('Gửi ẩn danh'));
    await t.pump();
    await shot(t, 'thao-luan-soan');
    await t.tap(find.byKey(const ValueKey('opinion-send')));
    await settle(t);
    expect(calls, contains('POST /bt/api/posts'));
    expect(posted.single['stance'], 'n');
    await t.tap(find.text('Mới nhất'));
    await settle(t, 2);
    expect(calls.last, 'GET /bt/api/discussions/D1/posts?sort=new');
    await t.tap(find.widgetWithText(ChoiceChip, 'Đồng ý'));
    await settle(t, 2);
    expect(calls.last, 'GET /bt/api/discussions/D1/posts?sort=new&stance=y');
  });

  final stageView = {
    'mode': 'bangtin', 'disc_id': 'D1', 'title': 'Giao ban kỹ thuật', 'question': 'Có nên chia 2 đội tăng ca để kịp bàn giao tòa B trước 15/12?', 'stance': true,
    'counts': {'posts': 20, 'replies': 41, 'people': 18}, 'stance_counts': {'y': 12, 'n': 5, 'o': 3},
    'pinned': {'id': 'p1', 'text': 'Chia 2 đội, mỗi ca 6 tiếng. Đội lắp ray làm sáng, đội đấu điện làm chiều, không giẫm chân nhau ở hố thang.', 'author': 'Nguyễn Văn Lợi',
      'stance': 'y', 'likes': 14, 'dislikes': 0, 'comments': 4, 'replies': [{'author': 'Mai Kim', 'text': 'Kho Long Biên giao ray ngày 25/11.'}, {'author': 'Phạm Hà', 'text': 'Cáp tải về 28/11.'}]},
    'top': [
      {'id': 'p2', 'text': 'Tăng ca 3 tuần thì an toàn lao động khó giữ. Nên thuê thêm 1 tổ lắp ngoài.', 'author': 'Trần Quang', 'stance': 'n', 'likes': 9, 'dislikes': 2, 'comments': 2},
      {'id': 'p3', 'text': 'Lắp song song thang 1 và 2, ưu tiên thang tải trước.', 'author': 'Ẩn danh', 'stance': 'o', 'likes': 7, 'dislikes': 0, 'comments': 0},
    ],
  };
  for (final (name, light) in [('toi', false), ('sang', true)]) {
    testWidgets('sân khấu ($name): đang bàn + trả lời, nhiều người đồng tình, thanh lập trường', (t) async {
      await pump(
        t,
        Material(
          color: StageTheme(light: light).bg,
          child: Padding(
          padding: const EdgeInsets.all(40),
          child: StageMetrics(theme: StageTheme(light: light), portrait: false, size: const Size(1200, 640), child: DiscussStage(stageView)),
        )),
        size: const Size(1280, 720),
      );
      expect(find.text('ĐANG BÀN'), findsOneWidget);
      expect(find.text('NHIỀU NGƯỜI ĐỒNG TÌNH'), findsOneWidget);
      expect(find.text('12 Đồng ý'), findsOneWidget);
      expect(find.textContaining('Kho Long Biên'), findsOneWidget);
      await shot(t, 'thao-luan-san-khau-$name');
    });
  }

  test('loại trang: có Thảo luận, Hỏi đáp ẩn khỏi danh sách tạo', () {
    expect(pageTypeOf('discuss')?.label, 'Thảo luận');
    expect(pageTypeOf('qa')?.hidden, true);
  });
}
