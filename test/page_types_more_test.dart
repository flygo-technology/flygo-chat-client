// Bấm giờ, Bốc thăm, Ghi chú, Biểu quyết: sân khấu (nhiều cỡ) và điện thoại, không tràn; thao tác gửi đúng hành động.
// PAGES_OUT=<thư mục>: lưu ảnh chụp.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';
import 'package:flygo_chat/ui/pages/pages_api.dart';
import 'package:flygo_chat/ui/pages/types/draw.dart';
import 'package:flygo_chat/ui/pages/types/notes.dart';
import 'package:flygo_chat/ui/pages/types/poll.dart';
import 'package:flygo_chat/ui/pages/types/timer.dart';

final _app = AppState('t');
final _acts = <String>[];
final _shotKey = GlobalKey();

PageCtx _ctx(String type, Map<String, dynamic> view, {String role = 'member', bool stage = false, bool presenting = false, String? meeting = 'abc-defg-hij'}) => PageCtx(
      data: PageData.from({'page': {'id': 'p1', 'type': type, 'title': 'Trang thử', 'owner': 'o', 'visibility': 'meeting', 'meeting': meeting}, 'view': view, 'role': role, 'rev': 3}),
      api: PagesApi(_app.calls),
      call: _app.calls,
      presenting: presenting,
      onStage: stage,
      act: (a, [b = const {}]) async => _acts.add(a),
      reload: () async {},
    );

final _now = DateTime.now().millisecondsSinceEpoch;
final _timer = {'mode': 'countdown', 'duration_ms': 300000, 'running': true, 'started_at': _now - 61000, 'elapsed_ms': 0, 'now': _now, 'sound': true,
  'speakers': ['Nguyễn Văn Lợi', 'Mai Kim', 'Trần Quang'], 'speaker': 1, 'can_control': true};
final _draw = {'source': 'participants', 'options': <String>[], 'count': 2, 'repeats': false, 'mode': 'groups', 'groups': 3, 'can_control': true,
  'last': {'id': 'r1', 'teams': [['An', 'Bình'], ['Chi', 'Dũng'], ['Hà', 'Lan']], 'by_name': 'Ba'},
  'results': [{'id': 'r0', 'picks': ['Phòng A'], 'by_name': 'Ba'}, {'id': 'r1', 'teams': [['An', 'Bình'], ['Chi', 'Dũng'], ['Hà', 'Lan']], 'by_name': 'Ba'}]};
final _notes = {'title': 'Giải pháp bù tiến độ tòa B', 'anon': false, 'votes_per_person': 3, 'votes_left': 2, 'can_manage': true,
  'columns': [{'id': 'c1', 'name': 'Nhân lực'}, {'id': 'c2', 'name': 'Vật tư'}, {'id': 'c3', 'name': 'Tiến độ'}],
  'notes': [
    {'id': 'n1', 'text': 'Tăng ca theo ca 6 giờ, luân phiên 2 đội', 'color': 'yellow', 'col': 'c1', 'by_name': 'Lợi', 'votes': 6, 'voted': true, 'mine': false},
    {'id': 'n2', 'text': 'Đặt ray dẫn hướng dự phòng ở kho Long Biên', 'color': 'green', 'col': 'c2', 'by_name': 'Mai Kim', 'votes': 5, 'voted': false, 'mine': true},
    {'id': 'n3', 'text': 'Lắp song song 2 thang', 'color': 'blue', 'col': 'c3', 'by_name': 'Quang', 'votes': 3, 'voted': false, 'mine': false},
  ]};
final _vote = {'kind': 'vote', 'title': 'Thông qua kế hoạch tăng ca tháng 12', 'anon': true, 'live': false, 'current': 0, 'reveal': false, 'closed': true, 'voters': 9,
  'quorum': 5, 'threshold': 50,
  'questions': [{'id': 'v', 'text': 'Thông qua kế hoạch tăng ca tháng 12 cho đội lắp đặt tòa B?', 'multi': false, 'options': [{'id': 'yes', 'text': 'Đồng ý'}, {'id': 'no', 'text': 'Không đồng ý'}, {'id': 'abstain', 'text': 'Phiếu trắng'}]}],
  'mine': {'v': ['yes']}, 'results': {'v': {'total': 9, 'options': {'yes': 6, 'no': 2, 'abstain': 1}}},
  'outcome': {'yes': 6, 'no': 2, 'abstain': 1, 'voters': 9, 'quorum': 5, 'threshold': 50, 'quorum_met': true, 'passed': true}};

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
  await t.pumpWidget(RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark().copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter')), home: Scaffold(backgroundColor: const Color(0xFF16181C), body: w))));
  await t.pump();
}

void main() {
  tearDown(() => _acts.clear());
  for (final (name, size) in [('stage-wide', const Size(1280, 720)), ('stage-small', const Size(480, 270)), ('stage-tall', const Size(390, 700))]) {
    testWidgets('sân khấu $name: bấm giờ, bốc thăm, ghi chú, biểu quyết không tràn', (t) async {
      await _pump(t, TimerView(_ctx('timer', _timer, stage: true, presenting: true)), size);
      expect(find.textContaining('Mai Kim'), findsOneWidget);
      await _shot(t, 'timer-$name');
      await _pump(t, DrawView(_ctx('draw', _draw, stage: true)), size);
      expect(find.text('NHÓM 3'), findsOneWidget);
      await _shot(t, 'draw-$name');
      await _pump(t, NotesView(_ctx('notes', _notes, stage: true)), size);
      expect(find.text('VẬT TƯ'), findsOneWidget);
      await _shot(t, 'notes-$name');
      await _pump(t, PollView(_ctx('poll', _vote, stage: true)), size);
      expect(find.textContaining('THÔNG QUA'), findsOneWidget);
      await _shot(t, 'vote-$name');
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('điện thoại: đồng hồ (điều khiển), bốc thăm (bốc lại), ghi chú (👍, thêm), biểu quyết (đã bỏ phiếu)', (t) async {
    await _pump(t, TimerView(_ctx('timer', _timer, role: 'owner')), const Size(390, 760));
    await _shot(t, 'timer-phone');
    await t.tap(find.text('Tạm dừng'));
    await t.pump();
    await _pump(t, DrawView(_ctx('draw', _draw, role: 'owner')), const Size(390, 760));
    await _shot(t, 'draw-phone');
    await t.tap(find.text('Chia lại'));
    await t.pump();
    await _pump(t, NotesView(_ctx('notes', _notes, role: 'owner')), const Size(390, 760));
    await _shot(t, 'notes-phone');
    await t.tap(find.text('👍 6'));
    await t.pump();
    await _pump(t, PollView(_ctx('poll', _vote)), const Size(390, 760));
    await _shot(t, 'vote-phone');
    await t.tap(find.text('Không đồng ý'));
    await t.pump();
    expect(find.text('Bỏ phiếu'), findsNothing); // đã bỏ phiếu, không đổi được
    expect(_acts, ['pause', 'draw', 'vote']);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Ghi chú trong cuộc họp = bảng của cuộc họp: xem nhanh + nút mở trong Ghi chú; sân khấu như cũ', (t) async {
    final todoView = {'mode': 'todo', 'board_id': 'B1', 'meeting': 'abc-defg-hij', 'offline': false, 'title': 'Giao ban tòa B', 'columns': <Map>[],
      'notes': [{'id': 'n1', 'text': 'Ray — giao 25/11', 'color': 'green', 'col': null, 'by_name': 'Lan', 'votes': 2, 'voted': false, 'mine': false}], 'can_manage': false};
    await _pump(t, NotesView(_ctx('notes', todoView)), const Size(390, 760));
    expect(find.text('Mở bảng trong Ghi chú'), findsOneWidget);
    expect(find.text('Ray — giao 25/11'), findsOneWidget);
    expect(find.text('Thêm ghi chú'), findsNothing);
    await _shot(t, 'notes-meeting-phone');
    await _pump(t, NotesView(_ctx('notes', todoView, stage: true)), const Size(1280, 720));
    // Tên bảng nằm ở thanh đầu của khung sân khấu; trang chỉ vẽ các ghi chú.
    expect(find.text('Ray — giao 25/11'), findsOneWidget);
    await _shot(t, 'notes-meeting-stage');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('bấm giờ: đồng hồ vẫn chạy khi cuộc họp dựng lại màn hình (không tính lại lệch giờ theo now cũ); qua 0 = Hết giờ', (t) async {
    final start = DateTime.now().millisecondsSinceEpoch;
    final view = {..._timer, 'speakers': <String>[], 'started_at': start, 'now': start, 'elapsed_ms': 0, 'duration_ms': 300000};
    late StateSetter rebuild;
    var n = 0;
    await _pump(t, StatefulBuilder(builder: (c, set) {
      rebuild = set;
      n++;
      return TimerView(_ctx('timer', view, role: 'owner'));
    }), const Size(390, 760));
    expect(find.text('05:00'), findsOneWidget);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2100)));
    rebuild(() {}); // vd có người bật mic: PageHost dựng lại với cùng view cũ
    await t.pump(const Duration(milliseconds: 300));
    expect(n, greaterThan(1));
    expect(find.text('05:00'), findsNothing);
    expect(find.textContaining(RegExp(r'^04:5[6-8]$')), findsOneWidget);
    // Chạy qua 0 khi chưa từng tạm dừng (elapsed_ms của máy chủ = 0): hiện Hết giờ.
    final over = DateTime.now().millisecondsSinceEpoch;
    await _pump(t, TimerView(_ctx('timer', {...view, 'started_at': over - 301000, 'now': over}, role: 'owner')), const Size(390, 760));
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Hết giờ'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('bấm giờ: các nút gửi đúng hành động (bắt đầu / tạm dừng / đặt lại / +1 phút / mốc / lượt nói / đổi chế độ)', (t) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final paused = {..._timer, 'running': false, 'started_at': 0, 'elapsed_ms': 30000, 'now': now};
    await _pump(t, TimerView(_ctx('timer', paused, role: 'owner')), const Size(390, 900));
    expect(find.text('04:30'), findsOneWidget);
    for (final label in ['Bắt đầu', 'Đặt lại', '+1 phút', '3 phút', 'Chuyển sang bấm giờ']) {
      await t.tap(find.text(label));
      await t.pump();
    }
    await t.tap(find.byIcon(Icons.skip_next));
    await t.pump();
    await t.tap(find.byIcon(Icons.skip_previous));
    await t.pump();
    expect(_acts, ['start', 'reset', 'add', 'set', 'mode', 'next', 'prev']);
    _acts.clear();
    await _pump(t, TimerView(_ctx('timer', {...paused, 'running': true, 'started_at': now, 'elapsed_ms': 0}, role: 'owner')), const Size(390, 900));
    await t.tap(find.text('Tạm dừng'));
    await t.pump();
    expect(_acts, ['pause']);
    // Người xem thường: không có nút.
    await _pump(t, TimerView(_ctx('timer', {...paused, 'can_control': false})), const Size(390, 900));
    expect(find.text('Bắt đầu'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  test('đăng ký đủ loại trang mới', () {
    for (final t in ['timer', 'draw', 'notes', 'poll']) {
      expect(pageTypeOf(t)?.label, isNotEmpty, reason: t);
    }
    expect(fmtClock(61000), '01:01');
    expect(fmtClock(3723000), '1:02:03');
  });
}
