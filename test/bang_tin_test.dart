// Bảng tin: bảng tin kiểu mạng xã hội, cột bình luận bên phải (máy tính), xác nhận đã đọc, chọn nền, thanh cảm xúc,
// soạn bài với backend giả. Ảnh xem trước (chạy tay): BT_OUT=<thư mục> [BT_EMOJI=<NotoColorEmoji.ttf>] flutter test test/bang_tin_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/config.dart' show debugIsDesktop;
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/ui/home_page.dart' show debugMobileTabBar;
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/bang_tin/api.dart';
import 'package:flygo_chat/ui/bang_tin/backgrounds.dart';
import 'package:flygo_chat/ui/bang_tin/bang_tin_page.dart';
import 'package:flygo_chat/ui/bang_tin/bang_tin_service.dart';
import 'package:flygo_chat/ui/bang_tin/dm_link.dart';
import 'package:flygo_chat/ui/bang_tin/editor_page.dart';
import 'package:flygo_chat/ui/bang_tin/post_page.dart';
import 'package:flygo_chat/ui/bang_tin/reactions.dart';
import 'package:flygo_chat/ui/bang_tin/share_sheet.dart';
import 'package:flygo_chat/ui/media_view.dart' show GalleryViewer;
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<File> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      if (f.existsSync()) l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await l.load();
  }

  await load('MaterialIcons', [File('$dir/MaterialIcons-Regular.otf')]);
  // Theme trên Linux dùng Noto Sans; máy không có thì nạp DejaVu Sans dưới tên đó (cũng đủ dấu tiếng Việt).
  await load('Noto Sans', [
    for (final f in ['noto/NotoSans-Regular.ttf', 'noto/NotoSans-Bold.ttf', 'dejavu/DejaVuSans.ttf', 'dejavu/DejaVuSans-Bold.ttf'])
      File('/usr/share/fonts/truetype/$f'),
  ]);
  final emoji = Platform.environment['BT_EMOJI'];
  if (emoji != null) await load('Noto Color Emoji', [File(emoji)]);
}

/// Ảnh giả (gradient) cho ảnh trong bài.
Future<Uint8List> _png(Color a, Color b) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const r = Rect.fromLTWH(0, 0, 600, 400);
  c.drawRect(r, Paint()..shader = LinearGradient(colors: [a, b]).createShader(r));
  c.drawCircle(const Offset(450, 120), 70, Paint()..color = Colors.white.withValues(alpha: .5));
  final img = await rec.endRecording().toImage(600, 400);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

final _now = DateTime.now().millisecondsSinceEpoch;
Map<String, dynamic> _post(String id, String body,
        {String title = '',
        String author = 'Lan Hành chính',
        String authorId = 'u2',
        bool admin = false,
        bool pinned = false,
        bool ack = false,
        bool read = true,
        String? cat,
        String? bg,
        List<String> images = const [],
        List<Map<String, String>> tags = const [],
        Map<String, int> reactions = const {},
        int comments = 0,
        int shares = 0,
        int minutesAgo = 60}) =>
    {
      'id': id,
      'title': title,
      'excerpt': body,
      'body_preview': body,
      'body_truncated': false,
      'bg': bg,
      'images': images,
      'image_count': images.length,
      'tags': tags,
      'author_admin': admin,
      'audience_kind': 'everyone',
      'author': {'id': authorId, 'name': author},
      'category': cat,
      'cover': null,
      'created_at': _now - minutesAgo * 60000,
      'updated_at': _now - minutesAgo * 60000,
      'edited': false,
      'pinned': pinned,
      'expires_at': null,
      'expired': false,
      'require_ack': ack,
      'ack_deadline': ack ? _now + 2 * 86400000 : null,
      'read': read,
      'acked': false,
      'comments': comments,
      'shares': shares,
      'views': authorId == 'me' ? 25 : null,
      'attachments': images.length,
      'reactions': reactions,
      'my_reactions': <String>[],
    };

void main() {
  final out = Platform.environment['BT_OUT'];
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final calls = <String>[];
  final files = <String, Uint8List>{};
  // Chỉ có một bài ghim (lỗi Sếp gặp ở bản 419: bài ghim thành băng rôn, bảng tin báo "Chưa có bài viết nào").
  var pinnedOnly = false;
  // Người dùng hiện tại có phải quản trị Bảng tin không.
  var meAdmin = true;

  final feed = [
    _post('p2', 'Chúc mừng team Kinh doanh vượt 120% chỉ tiêu tháng 11! 🎉', bg: 'love', author: 'Ba', authorId: 'me', admin: true, reactions: {'❤️': 12, '👍': 8, '😆': 2}, comments: 5, minutesAgo: 20),
    _post('p3',
        'Buổi team building ở Hồ Tây chiều qua vui quá cả nhà ơi! Cảm ơn mọi người đã tham gia nhiệt tình, hẹn gặp lại ở chuyến đi Sa Pa tháng sau. Ai có ảnh đẹp thì gửi thêm vào bình luận nhé.',
        author: 'Tuấn Kho',
        authorId: 'u3',
        cat: 'su-kien',
        images: ['i1', 'i2', 'i3', 'i4', 'i5'],
        tags: [
          {'id': 'u2', 'name': 'Lan Hành chính'},
          {'id': 'u4', 'name': 'Nam Kinh doanh'},
        ],
        reactions: {'👍': 21, '❤️': 9},
        comments: 7,
        shares: 3,
        minutesAgo: 180),
    _post('p4', '## Quy định chấm công mới\n\nTừ 01/12 mọi người chấm công bằng **Flygo Chat** thay máy vân tay.',
        title: 'Quy định mới về chấm công', cat: 'nhan-su', ack: true, read: false, admin: true, minutesAgo: 300),
    {
      ..._post('p5', 'Cả nhà chọn giúp địa điểm du lịch cuối năm nhé!', author: 'Lan Hành chính', minutesAgo: 400),
      'poll': {
        'question': 'Đi đâu?',
        'multi': false,
        'anonymous': false,
        'closes_at': null,
        'closed': false,
        'voters': 3,
        'options': [
          {'id': 'o1', 'text': 'Sa Pa', 'votes': 2},
          {'id': 'o2', 'text': 'Hạ Long', 'votes': 1},
          {'id': 'o3', 'text': 'Đà Lạt', 'votes': 0},
        ],
        'my_votes': <String>[],
      },
    },
  ];

  http.Client backend() => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path == '/bt/api/posts' && req.method == 'GET') calls.add('query ${req.url.query}');
        final p = req.url.path;
        Object? body;
        if (p == '/v1/token') body = {'token': 'jwt', 'expires_in': 600, 'scope': ['use', 'admin']};
        if (p == '/bt/api/me') {
          body = {
            'user': {'id': 'me', 'name': 'Ba'},
            'admin': meAdmin,
            'categories': [
              {'id': 'nhan-su', 'name': 'Nhân sự', 'color': '#3B82F6', 'sort': 0},
              {'id': 'su-kien', 'name': 'Sự kiện', 'color': '#E8833A', 'sort': 1},
            ],
          };
        }
        if (p == '/bt/api/posts' && req.method == 'GET') {
          body = {
            'pinned': [
              _post('p1', 'Toàn thể anh em chú ý chuẩn bị đi chơi nha. Xe đón lúc 7h sáng thứ Bảy tại công ty.',
                  title: 'Thông báo', pinned: true, admin: true, author: 'Ba', authorId: 'me', reactions: {'👍': 14, '❤️': 6}, comments: 4, shares: 2),
            ],
            'posts': pinnedOnly ? [] : feed,
            'next': null,
          };
        }
        final m = RegExp(r'^/bt/api/posts/(p\d)$').firstMatch(p);
        if (m != null && req.method == 'GET') {
          final base = [...feed, _post('p1', 'Nghỉ từ 04/02 đến hết 14/02.', title: 'Lịch nghỉ Tết Nguyên đán 2027', pinned: true)].firstWhere((x) => x['id'] == m[1]);
          body = {
            'post': {
              ...base,
              'body': base['body_preview'],
              'files': [for (final i in base['images'] as List) {'id': i, 'name': '$i.png', 'mime': 'image/png', 'size': 120000}],
              'can_edit': true,
              'can_delete': true,
              'can_see_receipts': true,
              'stats': {'targets': 42, 'read': 30, 'acked': 21},
              'audience': {'everyone': true, 'depts': [], 'users': []},
            },
          };
        }
        if (m != null && req.method == 'PATCH') body = {'post': feed.first};
        if (RegExp(r'^/bt/api/posts/p\d/comments$').hasMatch(p)) {
          body = {
            'comments': [
              {'id': 'c1', 'parent': null, 'author': {'id': 'u3', 'name': 'Tuấn Kho'}, 'created_at': _now - 600000, 'edited': false, 'hidden': false,
                'deleted': false, 'body': 'Ảnh đẹp quá, cho em xin bản gốc với!', 'can_edit': false, 'can_delete': true, 'can_hide': true, 'reactions': {}, 'my_reactions': []},
              {'id': 'c2', 'parent': 'c1', 'author': {'id': 'u2', 'name': 'Lan Hành chính'}, 'created_at': _now - 300000, 'edited': false, 'hidden': false,
                'deleted': false, 'body': 'Chị gửi vào nhóm chung rồi nhé.', 'can_edit': false, 'can_delete': true, 'can_hide': true, 'reactions': {'👍': 1}, 'my_reactions': [],
                'files': [
                  {'id': 'i1', 'name': 'a.png', 'mime': 'image/png', 'size': 10},
                  {'id': 'i2', 'name': 'b.png', 'mime': 'image/png', 'size': 10},
                  {'id': 'i4', 'name': 'c.png', 'mime': 'image/png', 'size': 10},
                ]},
            ],
          };
        }
        if (RegExp(r'^/bt/api/posts/p\d/ack$').hasMatch(p)) body = {'ok': true, 'acked': true};
        if (p == '/bt/api/posts/p5/vote') {
          final picked = [for (final x in (jsonDecode(req.body)['options'] as List)) '$x'];
          body = {
            'poll': {
              'question': 'Đi đâu?', 'multi': false, 'anonymous': false, 'closes_at': null, 'closed': false, 'voters': 4,
              'options': [
                {'id': 'o1', 'text': 'Sa Pa', 'votes': 2},
                {'id': 'o2', 'text': 'Hạ Long', 'votes': picked.contains('o2') ? 2 : 1},
                {'id': 'o3', 'text': 'Đà Lạt', 'votes': 0},
              ],
              'my_votes': picked,
            },
          };
        }
        if (RegExp(r'^/bt/api/posts/p\d/receipts$').hasMatch(p)) {
          body = {
            'targets': 4,
            'require_ack': false,
            'read': [
              {'id': 'u2', 'name': 'Lan Hành chính', 'at': _now - 600000},
              {'id': 'u3', 'name': 'Tuấn Kho', 'at': _now - 900000},
            ],
            'unread': [
              {'id': 'u4', 'name': 'Nam Kinh doanh'},
              {'id': 'u5', 'name': 'Hoa Kế toán'},
            ],
          };
        }
        if (RegExp(r'^/bt/api/posts/p\d/reactions').hasMatch(p)) {
          body = req.method == 'POST' ? {'reactions': {'❤️': 10, '👍': 21}, 'my_reactions': [jsonDecode(req.body)['emoji']]} : {'reactions': {'👍': 21}, 'my_reactions': []};
        }
        final f = RegExp(r'^/bt/api/files/(\w+)$').firstMatch(p);
        if (f != null && files[f[1]] != null) return http.Response.bytes(files[f[1]]!, 200, headers: {'content-type': 'image/png'});
        return body == null
            ? http.Response('{"error":"không có"}', 404)
            : http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
      });

  BangTinApi api() {
    final client = backend();
    return BangTinApi(base: 'https://chat.test/bt', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: client), client: client);
  }

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pump(WidgetTester t, Widget child, {Size size = const Size(420, 900), Brightness theme = Brightness.light}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      if (out != null) await _fonts();
      if (files.isEmpty) {
        files['i1'] = await _png(const Color(0xFFFF9A62), const Color(0xFF6A5AE0));
        files['i2'] = await _png(const Color(0xFF34C77B), const Color(0xFF1D7FE0));
        files['i3'] = await _png(const Color(0xFFF7B731), const Color(0xFFE8455A));
        files['i4'] = await _png(const Color(0xFF00C9FF), const Color(0xFF92FE9D));
        files['i5'] = await _png(const Color(0xFFFC466B), const Color(0xFF3F5EFB));
      }
    });
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      // Bọc cả MaterialApp để ảnh chụp có cả trang vừa mở và lớp phủ (thanh cảm xúc, hộp chọn nền).
      child: RepaintBoundary(key: const ValueKey('shot'), child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(theme), home: child)),
    ));
    await settle(t);
    // Ảnh giải mã ngoài khung giả lập: chờ thêm rồi vẽ lại.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(t, 3);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('bảng tin (điện thoại, nền sáng): ô soạn bài, bài ghim, nền màu, ảnh, gắn thẻ; mở bài và xác nhận', (t) async {
    calls.clear();
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(420, 2300));
    expect(find.text('Bạn có gì muốn chia sẻ hôm nay?'), findsOneWidget);
    // Bài ghim là thẻ bài bình thường, có nhãn "Đã ghim" (không còn băng rôn).
    expect(find.text('Thông báo'), findsOneWidget);
    expect(find.text('Đã ghim'), findsOneWidget);
    expect(find.text('Xem ngay'), findsNothing);
    expect(find.textContaining('3 lượt chia sẻ'), findsOneWidget);
    expect(find.text('Chia sẻ'), findsWidgets);
    expect(find.textContaining('vượt 120%'), findsOneWidget);
    expect(find.text('@Nam Kinh doanh'), findsOneWidget);
    expect(find.text('Quy định mới về chấm công'), findsOneWidget);
    expect(find.textContaining('7 bình luận'), findsOneWidget);
    // Bài ghim luôn ở đầu (máy chủ trả riêng, ghim mới nhất trước), không dùng pins=inline nữa.
    expect(calls.any((c) => c.startsWith('query ') && c.contains('pins=inline')), isFalse);
    expect(t.getTopLeft(find.text('Thông báo')).dy, lessThan(t.getTopLeft(find.textContaining('vượt 120%')).dy));
    await shot(t, 'bang-tin-1-feed-sang');

    await t.tap(find.text('Quy định mới về chấm công'));
    await settle(t);
    expect(find.text('Đã xem 30/42'), findsOneWidget);
    expect(find.text('Ảnh đẹp quá, cho em xin bản gốc với!'), findsOneWidget);
    await t.ensureVisible(find.text('Tôi đã đọc và xác nhận'));
    await t.tap(find.text('Tôi đã đọc và xác nhận'));
    await settle(t, 4);
    expect(calls, contains('POST /bt/api/posts/p4/ack'));
    expect(find.text('Bạn đã xác nhận đã đọc bài này'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('chỉ có bài ghim: vẫn hiện thẻ bài, không báo "Chưa có bài viết nào"; bấm Chia sẻ mở hộp chia sẻ', (t) async {
    pinnedOnly = true;
    addTearDown(() => pinnedOnly = false);
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 1000), theme: Brightness.dark);
    expect(find.textContaining('chuẩn bị đi chơi nha'), findsOneWidget);
    expect(find.text('Chưa có bài viết nào'), findsNothing);
    expect(find.text('Bạn đã xem hết nội dung'), findsOneWidget);
    await shot(t, 'bang-tin-7-may-tinh-toi-chi-bai-ghim');
    await t.tap(find.text('Chia sẻ').first);
    await settle(t, 3);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Chia sẻ bài viết'), findsOneWidget);
  });

  testWidgets('máy tính nền sáng, trong tab riêng (không tiêu đề, không nút quay lại); bấm lượt xem mở cột phải', (t) async {
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin', inTab: true), size: const Size(1440, 1000));
    expect(find.text('Bảng tin'), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    await shot(t, 'bang-tin-8-may-tinh-sang');
    await t.tap(find.text('25 lượt xem').first);
    await settle(t, 4);
    expect(find.text('Đã xem'), findsWidgets);
    expect(find.byType(TabBar), findsOneWidget);
    await shot(t, 'bang-tin-11-may-tinh-luot-xem');
  });

  testWidgets('điện thoại: bấm lượt xem mở bottom sheet', (t) async {
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin', inTab: true), size: const Size(420, 1000));
    await t.tap(find.text('25 lượt xem').first);
    await settle(t, 4);
    expect(find.byType(BottomSheet), findsOneWidget);
    await shot(t, 'bang-tin-12-dien-thoai-luot-xem');
  });

  testWidgets('nháy chuột phải bài của mình: Sửa, Ghim, Xoá', (t) async {
    calls.clear();
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 1400));
    await t.tap(find.textContaining('vượt 120%'), buttons: kSecondaryButton);
    await settle(t, 2);
    expect(find.text('Sửa bài'), findsOneWidget);
    expect(find.text('Ghim lên đầu'), findsOneWidget);
    expect(find.text('Xoá bài'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 600));
    await shot(t, 'bang-tin-13-menu-chuot-phai');
    await t.tap(find.text('Ghim lên đầu'));
    await settle(t, 2);
    expect(calls, contains('PATCH /bt/api/posts/p2'));
  });

  testWidgets('bấm ảnh trong bài: mở trình xem ảnh toàn màn hình như chat, nút X để đóng', (t) async {
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(420, 1900));
    final img = find.byType(BangTinImage).first;
    await t.ensureVisible(img);
    await t.pump();
    await t.tap(img);
    await settle(t, 4);
    expect(find.byType(GalleryViewer), findsOneWidget);
    await shot(t, 'bang-tin-14-xem-anh');
    await t.tap(find.byTooltip('Đóng').last);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(GalleryViewer), findsNothing);
  });

  testWidgets('menu bài người khác: không có Sửa bài; có Lưu ảnh (bài có ảnh), Xác nhận đã đọc (bài cần xác nhận)', (t) async {
    calls.clear();
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 2400));
    await t.tap(find.textContaining('Buổi team building'), buttons: kSecondaryButton);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Sửa bài'), findsNothing);
    expect(find.text('Lưu ảnh'), findsOneWidget);
    expect(find.text('Ghim lên đầu'), findsOneWidget); // quản trị vẫn ghim được
    expect(find.text('Xoá bài'), findsOneWidget);
    await shot(t, 'bang-tin-15-menu-bai-nguoi-khac');
  });

  testWidgets('menu bài cần xác nhận: Xác nhận đã đọc, xong thì hiện "Đã xác nhận" (mờ)', (t) async {
    calls.clear();
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 1200));
    await t.drag(find.byType(ListView).first, const Offset(0, -1200));
    await settle(t, 2);
    await t.tap(find.text('Quy định mới về chấm công'), buttons: kSecondaryButton);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Sửa bài'), findsNothing);
    await t.pumpAndSettle();
    await t.tap(find.text('Xác nhận đã đọc'));
    await settle(t, 3);
    expect(calls, contains('POST /bt/api/posts/p4/ack'));
    await t.tap(find.text('Quy định mới về chấm công'), buttons: kSecondaryButton);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Đã xác nhận'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('ô "+N" của lưới ảnh: điện thoại mở chi tiết bài với đủ ảnh (không mở trình xem)', (t) async {
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(420, 2400));
    expect(find.text('+1'), findsOneWidget);
    await t.tap(find.text('+1'));
    await settle(t, 4);
    expect(find.byType(GalleryViewer), findsNothing);
    expect(find.text('Bài viết'), findsOneWidget);
    // 5 ảnh của bài + 3 ảnh trong một bình luận.
    expect(find.descendant(of: find.byType(BangTinPostPage), matching: find.byType(BangTinImage)), findsNWidgets(8));
  });

  testWidgets('máy tính: ô "+N" mở chi tiết bài ở cột phải, đủ ảnh', (t) async {
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 2400));
    await t.tap(find.text('+1'));
    await settle(t, 4);
    expect(find.byType(GalleryViewer), findsNothing);
    expect(find.text('Chị gửi vào nhóm chung rồi nhé.'), findsOneWidget);
    // 4 ảnh trên thẻ ở bảng tin + 5 ảnh của bài và 3 ảnh bình luận trong cột phải.
    expect(find.byType(BangTinImage), findsNWidgets(12));
    await shot(t, 'bang-tin-16-may-tinh-du-anh');
  });

  testWidgets('không phải quản trị: bài của mình có Sửa / Ghim, không có Xoá; bài đang ghim không có Bỏ ghim', (t) async {
    meAdmin = false;
    addTearDown(() => meAdmin = true);
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 2400));
    await t.tap(find.textContaining('vượt 120%'), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.text('Sửa bài'), findsOneWidget);
    expect(find.text('Ghim lên đầu'), findsOneWidget);
    expect(find.text('Xoá bài'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.tap(find.text('Thông báo'), buttons: kSecondaryButton);
    await t.pumpAndSettle();
    expect(find.text('Bỏ ghim'), findsNothing);
    expect(find.text('Xoá bài'), findsNothing);
    expect(find.text('Sửa bài'), findsOneWidget);
  });

  testWidgets('bình luận có ảnh: hàng ngang cuộn được, bấm mở trình xem ảnh; khung soạn có nút thêm ảnh bên trái', (t) async {
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 2400));
    await t.tap(find.text('+1'));
    await settle(t, 4);
    expect(find.byTooltip('Thêm ảnh'), findsWidgets);
    final row = find.byType(CommentImagesRow);
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byType(BangTinImage)), findsNWidgets(3));
    await t.ensureVisible(row);
    await t.pump();
    await shot(t, 'bang-tin-17-binh-luan-anh');
    await t.tap(find.descendant(of: row, matching: find.byType(BangTinImage)).at(1));
    await settle(t, 3);
    expect(find.byType(GalleryViewer), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('bình chọn: hiện trên thẻ, chưa chọn thì chưa hiện %, bấm chọn gửi phiếu rồi hiện kết quả', (t) async {
    calls.clear();
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 3000));
    expect(find.text('Đi đâu?'), findsOneWidget);
    expect(find.text('3 người bình chọn'), findsOneWidget);
    expect(find.textContaining('% ·'), findsNothing);
    await t.tap(find.text('Hạ Long'));
    await settle(t, 3);
    expect(calls, contains('POST /bt/api/posts/p5/vote'));
    expect(find.text('4 người bình chọn'), findsOneWidget);
    expect(find.text('50% · 2'), findsNWidgets(2));
    await t.ensureVisible(find.text('Đi đâu?'));
    await t.pump();
    await shot(t, 'bang-tin-18-binh-chon');
  });

  testWidgets('soạn bài: bật bình chọn, thêm lựa chọn, tuỳ chọn chọn nhiều / ẩn danh / hạn', (t) async {
    final me = BangTinMe('me', 'Ba', true, const []);
    await pump(t, BangTinEditor(api: api(), me: me), size: const Size(420, 1400));
    await t.tap(find.byTooltip('Bình chọn'));
    await t.pump();
    expect(find.text('Lựa chọn 1'), findsOneWidget);
    expect(find.text('Lựa chọn 2'), findsOneWidget);
    await t.tap(find.text('Thêm lựa chọn'));
    await t.pump();
    expect(find.text('Lựa chọn 3'), findsOneWidget);
    expect(find.text('Cho chọn nhiều'), findsOneWidget);
    expect(find.text('Ẩn danh'), findsOneWidget);
    expect(find.text('Không có hạn bình chọn'), findsOneWidget);
    await shot(t, 'bang-tin-19-soan-binh-chon');
  });

  test('Bảng tin chạy nền: đếm bài mới từ lần xem gần nhất + bài cần xác nhận; xem rồi thì chỉ còn bài cần xác nhận', () {
    final svc = BangTinService.instance;
    svc.me = {'user': {'id': 'me', 'name': 'Ba'}};
    svc.lastSeen = 0;
    svc.update(pinned: const [], posts: feed);
    // p2 là bài của mình (không đếm); p3, p4 (cần xác nhận), p5 mới.
    expect(svc.badge, 3);
    svc.markSeen();
    expect(svc.badge, 1); // còn p4 chưa xác nhận
  });

  testWidgets('tab Bảng tin: có bản tải sẵn thì hiện ngay, không vòng chờ', (t) async {
    final a = api();
    final svc = BangTinService.instance;
    svc.api = a;
    svc.me = {
      'user': {'id': 'me', 'name': 'Ba'},
      'admin': true,
      'categories': const [],
    };
    svc.update(pinned: const [], posts: [_post('c1', 'Bài lấy từ bộ nhớ đệm', title: 'Tin đã tải sẵn')]);
    addTearDown(() => svc.api = null);
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: BangTinHome(api: a, title: 'Bảng tin', inTab: true)),
    ));
    // Khung đầu tiên (chưa có phản hồi mạng nào): đã thấy bài, không có vòng chờ.
    expect(find.text('Tin đã tải sẵn'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await settle(t, 4);
    // Làm mới xong: thay bằng dữ liệu mới (bài tải sẵn không còn, bài mới nhất hiện ra).
    expect(find.text('Tin đã tải sẵn'), findsNothing);
    expect(find.textContaining('vượt 120%'), findsOneWidget);
  });

  testWidgets('điện thoại: nút "+" nhỏ, ngay trên thanh điều hướng, chỉ hiện khi ô soạn bài đã cuộn khuất', (t) async {
    debugIsDesktop = false;
    addTearDown(() => debugIsDesktop = null);
    t.view.physicalSize = const Size(412, 892);
    t.view.devicePixelRatio = 1;
    t.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      if (out != null) await _fonts();
    });
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (c) => Stack(children: [
              // Như tab Bảng tin của điện thoại: nội dung chạy dưới thanh điều hướng nổi.
              BangTinHome(api: api(), title: 'Bảng tin', inTab: true, bottomPadding: 84 + 14 + MediaQuery.paddingOf(c).bottom),
              Positioned(left: 0, right: 0, bottom: 14 + MediaQuery.paddingOf(c).bottom, child: debugMobileTabBar(index: 5)),
            ]),
          ),
        ),
      ),
    ));
    await settle(t, 6);
    expect(find.byType(FloatingActionButton), findsNothing); // ô soạn bài còn hiện
    await t.drag(find.byType(ListView).first, const Offset(0, -500));
    await settle(t, 3);
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    expect(t.getSize(fab).width, lessThanOrEqualTo(48));
    // Mép dưới nút cách mép trên thanh điều hướng khoảng 8-24px, không đè lên thanh.
    final bar = t.getRect(find.byType(Glass).last);
    final gap = bar.top - t.getRect(fab).bottom;
    expect(gap, inInclusiveRange(4, 28));
    await shot(t, 'bang-tin-20-nut-cong-dien-thoai');
  });

  testWidgets('soạn bài: mở "Tuỳ chọn khác", ô Tiêu đề đang gõ không bị cắt nhãn', (t) async {
    final me = BangTinMe('me', 'Ba', true, const []);
    await pump(t, BangTinEditor(api: api(), me: me), size: const Size(412, 1100));
    await t.tap(find.text('Tuỳ chọn khác'));
    await t.pumpAndSettle();
    final title = find.widgetWithText(TextField, 'Tiêu đề (không bắt buộc)');
    await t.tap(title);
    await t.pumpAndSettle();
    // Nhãn nổi nằm trọn trong vùng của phần mở rộng (không lên trên mép trên của ô).
    final field = t.getRect(title);
    final label = t.getRect(find.text('Tiêu đề (không bắt buộc)'));
    expect(label.top, greaterThanOrEqualTo(t.getRect(find.text('Tuỳ chọn khác')).bottom));
    expect(field.top - label.top, lessThan(14));
    await shot(t, 'bang-tin-21-tuy-chon-khac-tieu-de');
  });

  test('nội dung tin chia sẻ', () {
    final text = bangTinShareText(_post('p9', 'Tối nay liên hoan', title: 'Liên hoan'), 'Mọi người xem nhé');
    expect(text, contains('Mọi người xem nhé'));
    expect(text, contains('> **Liên hoan**'));
  });

  testWidgets('bảng tin nền tối', (t) async {
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(420, 1900), theme: Brightness.dark);
    expect(find.textContaining('vượt 120%'), findsOneWidget);
    await shot(t, 'bang-tin-2-feed-toi');
  });

  testWidgets('máy tính: bấm bài thì bình luận mở ở cột phải, bảng tin vẫn ở giữa', (t) async {
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(1440, 1000));
    await t.scrollUntilVisible(find.textContaining('7 bình luận'), 300, scrollable: find.byType(Scrollable).first);
    await settle(t, 2);
    await t.tap(find.textContaining('7 bình luận'));
    await settle(t);
    expect(find.text('Bình luận'), findsWidgets);
    expect(find.text('Chị gửi vào nhóm chung rồi nhé.'), findsOneWidget);
    // Cột phải hiện chi tiết bài đầy đủ (Sếp, 12/11): nội dung có ở bảng tin và ở cột phải, kèm đủ 5 ảnh.
    expect(find.textContaining('Buổi team building'), findsNWidgets(2));
    // 5 ảnh của bài + 3 ảnh trong một bình luận.
    expect(find.descendant(of: find.byType(BangTinPostPage), matching: find.byType(BangTinImage)), findsNWidgets(8));
    // Bảng tin vẫn còn (không đẩy trang mới).
    expect(find.text('Bạn có gì muốn chia sẻ hôm nay?'), findsOneWidget);
    await shot(t, 'bang-tin-3-may-tinh-cot-binh-luan');
    await t.tap(find.byTooltip('Đóng'));
    await settle(t, 2);
    expect(find.text('Chị gửi vào nhóm chung rồi nhé.'), findsNothing);
  });

  testWidgets('thanh cảm xúc: bấm giữ nút Thích rồi chọn', (t) async {
    calls.clear();
    await pump(t, BangTinHome(api: api(), title: 'Bảng tin'), size: const Size(420, 1100));
    await t.drag(find.byType(ListView).first, const Offset(0, -560));
    await settle(t, 2);
    final like = find.byType(LikeButton).at(1);
    await t.longPress(like);
    await settle(t, 3);
    expect(find.byType(ReactionBar), findsOneWidget);
    await shot(t, 'bang-tin-4-thanh-cam-xuc');
    await t.tap(find.text('❤️').last);
    await settle(t, 3);
    expect(calls, contains('POST /bt/api/posts/p3/reactions'));
    expect(find.byType(ReactionBar), findsNothing);
    expect(find.text('Yêu thích'), findsOneWidget);
  });

  testWidgets('chọn nền màu', (t) async {
    String? picked;
    await pump(
        t,
        Builder(builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () async => picked = await pickBackground(c, current: 'love'), child: const Text('chọn'))))),
        size: const Size(520, 760));
    await t.tap(find.text('chọn'));
    await settle(t, 3);
    expect(find.text('Chọn nền'), findsOneWidget);
    await shot(t, 'bang-tin-5-chon-nen');
    await t.tap(find.byType(BgBox).at(2));
    await settle(t, 2);
    expect(picked, kBackgrounds[2].id);
  });

  testWidgets('soạn bài: nền màu, ảnh, gắn thẻ, người nhận', (t) async {
    final me = BangTinMe('me', 'Ba', true, [
      {'id': 'nhan-su', 'name': 'Nhân sự'},
    ]);
    await pump(t, BangTinEditor(api: api(), me: me), size: const Size(420, 900));
    expect(find.text('Tạo bài viết'), findsOneWidget);
    expect(find.text('Thêm vào bài viết'), findsOneWidget);
    expect(find.text('Toàn công ty'), findsOneWidget);
    expect(find.byTooltip('Thêm ảnh'), findsOneWidget);
    expect(find.byTooltip('Gắn thẻ người'), findsOneWidget);
    await shot(t, 'bang-tin-6-soan-bai');
    // Chọn nền ngay ở dải nền: gõ chữ thẳng lên nền.
    await t.tap(find.byType(BgBox).at(4));
    await settle(t, 2);
    await t.enterText(find.byType(TextField).first, 'Chúc mừng sinh nhật chị Lan! 🎂');
    await settle(t, 2);
    expect(find.text('Chúc mừng sinh nhật chị Lan! 🎂'), findsOneWidget);
    await shot(t, 'bang-tin-9-soan-bai-nen');
  });

  testWidgets('máy tính: Đăng bài mở hộp thoại, không mở trang mới', (t) async {
    final me = BangTinMe('me', 'Ba', true, const []);
    await pump(
        t,
        Builder(builder: (c) => Scaffold(body: Center(child: FilledButton(onPressed: () => openBangTinEditor(c, api: api(), me: me), child: const Text('đăng'))))),
        size: const Size(1440, 1000));
    await t.tap(find.text('đăng'));
    await settle(t, 3);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Tạo bài viết'), findsOneWidget);
    await shot(t, 'bang-tin-10-may-tinh-hop-thoai-dang-bai');
  });

  test('tin của bot Bảng tin trỏ tới bài', () {
    MmPost p(Map<String, dynamic> props) => MmPost({'id': 'x', 'props': props});
    expect(bangTinPostOf(p({'flygo_app': 'vn.flygo.bangtin', 'flygo_post': 'H2s6TZrDKp7m'})), 'H2s6TZrDKp7m');
    expect(bangTinPostOf(p({'flygo_app': 'vn.flygo.bangtin', 'flygo_post': '../x'})), isNull);
    expect(bangTinPostOf(p({'flygo_app': 'vn.flygo.other', 'flygo_post': 'H2s6TZrDKp7m'})), isNull);
    expect(bangTinPostOf(p({})), isNull);
  });

  test('mã nền: biết mã, mã lạ thì null', () {
    expect(bgById('love')?.pattern, BgPattern.bigHeart);
    expect(bgById('khong-co'), isNull);
    expect(kBackgrounds.map((b) => b.id).toSet().length, kBackgrounds.length);
  });
}
