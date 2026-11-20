// Trang Bình chọn / Trắc nghiệm và Hỏi đáp: dựng trên sân khấu (khung lớn, nhiều cỡ) và để trả lời (điện thoại), không tràn.
// PAGES_OUT=<thư mục>: lưu ảnh chụp để xem.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/pages_api.dart';
import 'package:flygo_chat/ui/pages/types/poll.dart';
import 'package:flygo_chat/ui/pages/types/qa.dart';

final _app = AppState('t');
final _acts = <String>[];

PageCtx _ctx(String type, Map<String, dynamic> view, {String role = 'member', bool stage = false, bool presenting = false}) => PageCtx(
      data: PageData.from({'page': {'id': 'p1', 'type': type, 'title': 'Trang thử', 'owner': 'o', 'visibility': 'meeting'}, 'view': view, 'role': role, 'rev': 3}),
      api: PagesApi(_app.calls),
      call: _app.calls,
      presenting: presenting,
      onStage: stage,
      act: (a, [b = const {}]) async => _acts.add(a),
      reload: () async {},
    );

final _poll = {
  'kind': 'poll', 'title': 'Chọn ngày bàn giao tòa B', 'anon': false, 'live': true, 'current': 0, 'reveal': false, 'closed': false, 'voters': 12,
  'questions': [
    {'id': 'q', 'text': 'Ngày nào bàn giao tòa B cho chủ đầu tư là phù hợp nhất với tiến độ lắp đặt hiện tại?', 'multi': false, 'options': [
      {'id': 'a', 'text': 'Thứ Ba 25/11'}, {'id': 'b', 'text': 'Thứ Sáu 28/11'}, {'id': 'c', 'text': 'Thứ Ba 02/12, sau khi có ray dự phòng từ kho Long Biên'}]},
  ],
  'mine': {'q': ['b']},
  'results': {'q': {'total': 12, 'options': {'a': 7, 'b': 3, 'c': 2}}},
};
final _quiz = {
  'kind': 'quiz', 'title': 'Trắc nghiệm an toàn', 'anon': false, 'live': false, 'current': 0, 'reveal': true, 'closed': false, 'voters': 18, 'my_score': 1,
  'questions': [
    {'id': 'q1', 'text': 'Khi cabin kẹt giữa hai tầng, việc đầu tiên là gì?', 'multi': false, 'seconds': 30, 'correct': ['b'], 'options': [
      {'id': 'a', 'text': 'Mở cửa tầng bằng chìa khoá tam giác'}, {'id': 'b', 'text': 'Ngắt nguồn chính, trấn an người trong cabin'}, {'id': 'c', 'text': 'Gọi kỹ thuật viên rồi chờ'}]},
    {'id': 'q2', 'text': 'Đồ bảo hộ bắt buộc trong hố thang?', 'multi': true, 'correct': ['a', 'b'], 'options': [{'id': 'a', 'text': 'Mũ'}, {'id': 'b', 'text': 'Dây an toàn'}, {'id': 'c', 'text': 'Dép'}]},
  ],
  'mine': {'q1': ['b']},
  'results': {'q1': {'total': 18, 'options': {'a': 2, 'b': 14, 'c': 2}}, 'q2': {'total': 10, 'options': {'a': 9, 'b': 8, 'c': 1}}},
  'leaderboard': [{'name': 'Nguyễn Văn Lợi', 'score': 2, 'of': 2}, {'name': 'Mai Kim', 'score': 1, 'of': 2}],
};
final _qa = {
  'title': 'Hỏi đáp tòa B', 'desc': 'Câu hỏi về tiến độ và an toàn', 'allow_anon': true, 'can_manage': true, 'total': 3, 'open': 2,
  'questions': [
    {'id': 'x1', 'text': 'Thưởng Tết năm nay tính theo KPI quý 4 hay cả năm? Người vào làm sau tháng 6 thì tính thế nào?', 'anon': true, 'by_name': '', 'votes': 24, 'voted': true, 'mine': false, 'answered': true, 'pinned': true, 'hidden': false, 'at': 1,
      'answers': [{'id': 'a1', 'text': 'Theo KPI cả năm, quý 4 nhân hệ số 1,2.', 'by_name': 'Mai Kim', 'at': 2, 'accepted': true, 'mine': false}]},
    {'id': 'x2', 'text': 'Xe đưa đón công trình Long Biên có chạy thứ 7 không?', 'anon': false, 'by_name': 'Hà Ngô', 'votes': 11, 'voted': false, 'mine': true, 'answered': false, 'pinned': false, 'hidden': false, 'at': 3, 'answers': []},
    {'id': 'x3', 'text': 'Tài liệu bảo trì thang đời 2015 để ở đâu?', 'anon': false, 'by_name': 'Trần Quang', 'votes': 0, 'voted': false, 'mine': false, 'answered': false, 'pinned': false, 'hidden': false, 'at': 4, 'answers': []},
  ],
};

final _shotKey = GlobalKey();
Future<void> _shot(WidgetTester t, String name) async {
  final dir = Platform.environment['PAGES_OUT'];
  if (dir == null) return;
  await t.runAsync(() async {
    final ro = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Khi chụp ảnh (PAGES_OUT): nạp font Inter + biểu tượng Material thật để chữ đọc được (mặc định test dùng font ô vuông).
bool _fontsLoaded = false;
Future<void> loadShotFonts(WidgetTester t) async {
  if (_fontsLoaded || Platform.environment['PAGES_OUT'] == null) return;
  _fontsLoaded = true;
  await t.runAsync(() async {
    final inter = FontLoader('Inter');
    for (final f in ['Inter-Regular.ttf', 'Inter-Bold.ttf', 'Inter-SemiBold.ttf', 'Inter-Medium.ttf']) {
      final file = File('assets/fonts/$f');
      if (file.existsSync()) inter.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await inter.load();
    final icons = FontLoader('MaterialIcons');
    final root = Platform.environment['FLUTTER_ROOT'] ?? '/mnt/d2/flygo-build/flutter';
    icons.addFont(Future.value(ByteData.sublistView(File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
    await icons.load();
  });
}

Future<void> _pump(WidgetTester t, Widget w, Size size) async {
  await loadShotFonts(t);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(RepaintBoundary(key: _shotKey, child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark().copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter')), home: Scaffold(backgroundColor: const Color(0xFF16181C), body: w))));
  await t.pump();
}

void main() {
  tearDown(() => _acts.clear());
  for (final (name, size) in [('stage-wide', const Size(1280, 720)), ('stage-small', const Size(480, 270)), ('stage-tall', const Size(390, 700))]) {
    testWidgets('sân khấu $name: bình chọn, trắc nghiệm, hỏi đáp không tràn', (t) async {
      {
        await _pump(t, PollView(_ctx('poll', _poll, stage: true)), size);
        expect(find.textContaining('Ngày nào bàn giao'), findsOneWidget);
        await _shot(t, 'poll-$name');
        await _pump(t, PollView(_ctx('poll', _quiz, stage: true, presenting: true, role: 'member')), size);
        expect(find.textContaining('câu 1/2'), findsOneWidget);
        await _shot(t, 'quiz-$name');
        await _pump(t, QaView(_ctx('qa', _qa, stage: true)), size);
        expect(find.textContaining('Thưởng Tết'), findsOneWidget);
        await _shot(t, 'qa-$name');
      }
    });
  }

  testWidgets('điện thoại: trả lời bình chọn gửi "answer"; trắc nghiệm đã trả lời không chọn lại', (t) async {
    await _pump(t, PollView(_ctx('poll', _poll)), const Size(390, 760));
    await _shot(t, 'poll-phone');
    await t.tap(find.text('Thứ Ba 25/11'));
    await t.pump();
    await t.tap(find.text('Đổi lựa chọn'));
    await t.pump();
    expect(_acts, ['answer']);
    await _pump(t, PollView(_ctx('poll', _quiz)), const Size(390, 760));
    await _shot(t, 'quiz-phone');
    await t.tap(find.text('Mở cửa tầng bằng chìa khoá tam giác'));
    await t.pump();
    expect(find.text('Gửi'), findsNothing);
    expect(find.textContaining('điểm của bạn: 1/2'), findsOneWidget);
  });

  testWidgets('điện thoại: hỏi đáp: hỏi, 👍, mở trả lời; chủ trang có menu', (t) async {
    await _pump(t, QaView(_ctx('qa', _qa, role: 'owner')), const Size(390, 760));
    await _shot(t, 'qa-phone');
    await t.enterText(find.byType(TextField).last, 'Bao giờ giao ray?');
    await t.tap(find.byIcon(Icons.send).last);
    await t.pump();
    await t.tap(find.byIcon(Icons.thumb_up_outlined).first);
    await t.pump();
    expect(_acts, ['ask', 'vote']);
    await t.tap(find.textContaining('Thưởng Tết'));
    await t.pump();
    expect(find.textContaining('KPI cả năm'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsWidgets);
  });

  test('đăng ký đủ hai loại trang', () {
    expect(pageTypeOf('poll')?.label, isNotEmpty);
    expect(pageTypeOf('qa')?.label, isNotEmpty);
  });
}
