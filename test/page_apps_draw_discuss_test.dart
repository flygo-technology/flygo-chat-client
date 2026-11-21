// Bốc thăm và Thảo luận theo mockup "mỗi trang là một app" (21/11): người xem, chủ trang; ba kiểu màn hình × tối / sáng.
// Ảnh: APP_OUT=<thư mục> flutter test test/page_apps_draw_discuss_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/ui/bang_tin/api.dart';
import 'package:flygo_chat/ui/bang_tin/bang_tin_page.dart' show BangTinMe;
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/types/discuss_app.dart' show debugUseDiscussion;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'app_kit_helpers.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _draw({bool won = false, bool groups = false}) => {
      'source': 'participants', 'options': <String>[], 'count': 1, 'repeats': false, 'mode': groups ? 'groups' : 'pick', 'groups': 3, 'exclude_winners': true, 'effect': 'flip',
      'results': [
        {'id': 'r1', 'picks': ['Mai Kim'], 'by_name': 'Lợi'},
        groups ? {'id': 'r2', 'teams': [['An', 'Bình'], ['Chi', 'Dũng'], ['Hà', 'Lan']], 'by_name': 'Lợi'} : {'id': 'r2', 'picks': ['Trần Quang'], 'by_name': 'Lợi'},
      ],
      'last': groups ? {'id': 'r2', 'teams': [['An', 'Bình'], ['Chi', 'Dũng'], ['Hà', 'Lan']]} : {'id': 'r2', 'picks': ['Trần Quang']},
      'can_control': true, 'round': 2, 'remaining': 10, 'total': 12, 'me_out': false, 'me_won': won,
      'names': [
        for (final n in ['Mai Kim', 'Trần Quang', 'Lê Minh', 'Nguyễn Văn Lợi', 'Dương Văn Ba', 'Hoàng Lan', 'Phạm Tú', 'Vũ Hà'])
          {'name': n, 'off': n == 'Vũ Hà', 'won': n == 'Mai Kim' || n == 'Trần Quang'},
      ],
    };

Map<String, dynamic> _op(String id, String author, String body, String? stance, {int likes = 0, int dislikes = 0, int comments = 0, bool pin = false, List<Map<String, dynamic>> replies = const []}) => {
      'id': id, 'body_preview': body, 'author': {'id': author.toLowerCase(), 'name': author}, 'created_at': _now - 300000, 'stance': stance,
      'reactions': {if (likes > 0) '👍': likes, if (dislikes > 0) '👎': dislikes}, 'my_reactions': <String>[], 'comments': comments, 'discussing': pin,
      'latest_replies': replies, 'can_delete': false, 'hidden': false,
    };

void main() {
  setUpAll(loadAppTestFonts);
  setUp(appActs.clear);
  final draw = pageTypeOf('draw')!, discuss = pageTypeOf('discuss')!;

  testWidgets('bốc thăm: người xem (thẻ trúng, đã trúng, rút khỏi), chia nhóm', (t) async {
    await pumpAppForms(t, 'boc-tham-nguoi-xem', draw, appCtx('draw', _draw(), role: 'member'), check: (t, f, l) async {
      expect(find.text('Trần Quang'), findsWidgets);
      expect(find.text('Rút khỏi bốc thăm'), findsOneWidget);
    });
    await t.tap(find.byKey(const ValueKey('draw-optout')));
    await t.pump();
    expect(appActs.last.$1, 'optout');
    await pumpAppForms(t, 'boc-tham-chia-nhom', draw, appCtx('draw', _draw(groups: true), role: 'member'), forms: const ['dien-thoai-doc']);
  });

  testWidgets('bốc thăm: chủ trang (chạm tên bỏ, bốc, xoá kết quả bấm hai lần)', (t) async {
    await pumpAppForms(t, 'boc-tham-chu-trang', draw, appCtx('draw', _draw()), check: (t, f, l) async {
      expect(find.text('Bốc lần 3'), findsOneWidget);
    });
    appActs.clear();
    for (final f in [find.byKey(const ValueKey('draw-name-Lê Minh')), find.byKey(const ValueKey('draw-go'))]) {
      await t.ensureVisible(f);
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(appActs.map((e) => e.$1), ['toggle', 'draw']);
    expect(appActs.first.$2, {'name': 'Lê Minh'});
  });

  testWidgets('thảo luận: người xem (lập trường, ý kiến, 👍 / 👎, trả lời), chủ trang (cài đặt)', (t) async {
    final calls = <String>[];
    final posts = [
      _op('p1', 'Nguyễn Văn Lợi', 'Chọn đơn vị A vì đã làm tòa C đúng hạn, giá cao hơn 4% nhưng có bảo hành 24 tháng.', 'y', likes: 14, dislikes: 3, comments: 5, pin: true, replies: [
        {'id': 'c1', 'parent': null, 'author': {'name': 'Mai Kim'}, 'body': 'Tòa C chậm 2 tuần phần cửa tầng, cần xem lại.'},
        {'id': 'c2', 'parent': 'c1', 'author': {'name': 'Lợi'}, 'body': '@Mai Kim Chậm do mình đổi thiết kế cửa.'},
      ]),
      _op('p2', 'Lê Minh', 'Đơn vị B rẻ hơn 9%, nên cho thử 1 hạng mục.', 'n', likes: 7, dislikes: 2, comments: 2),
    ];
    final c = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      Object? body;
      if (req.url.path == '/v1/token') body = {'token': 'jwt', 'expires_in': 600, 'scope': ['use']};
      if (req.url.path == '/bt/api/discussions/D1/posts') {
        body = {
          'discussion': {'id': 'D1', 'title': 'Chọn nhà thầu phụ', 'question': 'Chọn nhà thầu phụ tòa B', 'stance': true, 'require_stance': false, 'allow_anon': true, 'closed': false, 'locked': false,
            'can_manage': true, 'stance_counts': {'y': 13, 'n': 7, 'o': 4}, 'counts': {'posts': 24, 'replies': 31, 'people': 18}},
          'posts': posts,
        };
      }
      if (req.url.path == '/bt/api/posts' && req.method == 'POST') body = {'post': posts.first};
      if (req.url.path.endsWith('/reactions') && req.method == 'POST') body = {'reactions': {}, 'my_reactions': []};
      if (req.url.path == '/bt/api/discussions/D1' && req.method == 'PATCH') body = {'discussion': {}};
      return body == null ? http.Response('{"error":"không có"}', 404) : http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    });
    final api = BangTinApi(base: 'https://chat.test/bt', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: c), client: c);
    debugUseDiscussion('D1', api, BangTinMe('me', 'Ba', false, const []));
    final view = {'mode': 'bangtin', 'disc_id': 'D1', 'title': 'Chọn nhà thầu phụ', 'question': 'Chọn nhà thầu phụ tòa B', 'stance': true, 'counts': {'posts': 24, 'replies': 31, 'people': 18},
      'stance_counts': {'y': 13, 'n': 7, 'o': 4}, 'pinned': null, 'top': [], 'latest': []};
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await pumpAppForms(t, 'thao-luan-app', discuss, appCtx('discuss', view, role: 'owner'), check: (t, f, l) async {
      await settle(t);
      expect(find.text('ĐANG BÀN'), findsWidgets);
      expect(find.textContaining('Tòa C chậm 2 tuần'), findsOneWidget);
      expect(find.text('Bắt buộc chọn lập trường'), findsOneWidget);
    });
    await t.ensureVisible(find.byKey(const ValueKey('react-p2-👍')));
    await t.tap(find.byKey(const ValueKey('react-p2-👍')));
    await settle(t);
    expect(calls, contains('POST /bt/api/posts/p2/reactions'));
    await t.ensureVisible(find.byKey(const ValueKey('st-n')));
    await t.tap(find.byKey(const ValueKey('st-n')));
    await t.enterText(find.byKey(const ValueKey('discuss-text')), 'Nên chia đôi gói thầu');
    await t.tap(find.byKey(const ValueKey('discuss-send')));
    await settle(t);
    expect(calls, contains('POST /bt/api/posts'));
  });
}
