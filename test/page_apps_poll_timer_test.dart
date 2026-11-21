// Bình chọn / Trắc nghiệm / Biểu quyết và Bấm giờ theo mockup "mỗi trang là một app" (21/11): người xem, chủ trang, sửa tại chỗ;
// ba kiểu màn hình × tối / sáng không tràn. Ảnh: APP_OUT=<thư mục> flutter test test/page_apps_poll_timer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';

import 'app_kit_helpers.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _poll({String kind = 'poll', bool results = true, List<String> mine = const ['a'], bool closed = false, bool reveal = false}) => {
      'kind': kind, 'title': 'Chọn ngày bàn giao', 'anon': true, 'live': false, 'current': 0, 'reveal': reveal, 'closed': closed, 'voters': 13, 'results_mode': 'after',
      'questions': [
        kind == 'vote'
            ? {'id': 'v', 'text': 'Thông qua hợp đồng tháng 11', 'multi': false, 'options': [{'id': 'yes', 'text': 'Đồng ý'}, {'id': 'no', 'text': 'Không'}, {'id': 'abstain', 'text': 'Trắng'}]}
            : {
                'id': 'q', 'text': 'Ngày nào bàn giao tòa B?', 'multi': false,
                'options': [{'id': 'a', 'text': 'Thứ Sáu 28/11'}, {'id': 'b', 'text': 'Thứ Hai 01/12'}, {'id': 'c', 'text': 'Thứ Tư 03/12'}],
                if (kind == 'quiz' && reveal) 'correct': ['a'],
              },
      ],
      'mine': {kind == 'vote' ? 'v' : 'q': mine},
      if (results) 'results': {(kind == 'vote' ? 'v' : 'q'): {'total': 13, 'options': kind == 'vote' ? {'yes': 9, 'no': 3, 'abstain': 1} : {'a': 7, 'b': 4, 'c': 2}}},
      if (kind == 'vote') ...{'threshold': 66, 'quorum': 0},
      if (kind == 'quiz' && reveal) ...{'my_score': 1, 'leaderboard': [{'name': 'Mai Kim', 'score': 1, 'of': 1}, {'name': 'Lê Minh', 'score': 0, 'of': 1}]},
    };

Map<String, dynamic> _timer({int? myTurn = 2, bool speaking = false, bool more = false}) => {
      'mode': 'countdown', 'duration_ms': 120000, 'running': true, 'started_at': _now - 86000, 'elapsed_ms': 0, 'now': _now, 'sound': true,
      'speakers': ['Lê Minh', 'Trần Quang', 'Bạn'], 'speaker': speaking ? 2 : 0, 'can_control': false,
      'queue': [
        {'name': 'Lê Minh', 'me': false, 'current': !speaking, 'done': speaking},
        {'name': 'Trần Quang', 'me': false, 'current': false, 'done': speaking},
        {'name': 'Dương Văn Ba', 'me': myTurn == 2, 'current': speaking, 'done': false},
      ],
      'my_turn': myTurn ?? -1,
      'more_req': more ? {'name': 'Lê Minh', 'me': false} : null,
    };

void main() {
  setUpAll(loadAppTestFonts);
  setUp(appActs.clear);
  final poll = pageTypeOf('poll')!, timer = pageTypeOf('timer')!;

  testWidgets('bình chọn: người xem chạm là chọn, thấy % sau khi chọn', (t) async {
    await pumpAppForms(t, 'binh-chon-nguoi-xem', poll, appCtx('poll', _poll(), role: 'member'), check: (t, form, light) async {
      expect(find.text('Ngày nào bàn giao tòa B?'), findsWidgets);
      expect(find.text('54%'), findsWidgets);
    });
    appActs.clear();
    await pumpAppForms(t, 'binh-chon-chua-chon', poll, appCtx('poll', _poll(results: false, mine: const []), role: 'member'), forms: const ['dien-thoai-doc']);
    await t.tap(find.byKey(const ValueKey('opt-b')));
    await t.pump();
    expect(appActs.single.$1, 'answer');
    expect(appActs.single.$2, {'q': 'q', 'options': ['b']});
  });

  testWidgets('biểu quyết + trắc nghiệm công bố (người xem)', (t) async {
    await pumpAppForms(t, 'bieu-quyet-nguoi-xem', poll, appCtx('poll', _poll(kind: 'vote', mine: const []), role: 'member'), forms: const ['dien-thoai-doc', 'dien-thoai-ngang']);
    await t.tap(find.byKey(const ValueKey('vote-yes')));
    await t.pump();
    expect(appActs.last.$1, 'answer');
    await pumpAppForms(t, 'trac-nghiem-cong-bo', poll, appCtx('poll', _poll(kind: 'quiz', reveal: true), role: 'member'), forms: const ['dien-thoai-doc'], check: (t, f, l) async {
      expect(find.text('BẢNG ĐIỂM'), findsWidgets);
    });
  });

  testWidgets('bình chọn: chủ trang điều khiển (khoá, công bố, ai thấy kết quả, Biên bản)', (t) async {
    await pumpAppForms(t, 'binh-chon-chu-trang', poll, appCtx('poll', _poll()), check: (t, form, light) async {
      expect(find.text('Công bố kết quả'), findsOneWidget);
      expect(find.text('Sau khi chọn ›'), findsOneWidget);
    });
    appActs.clear();
    await t.tap(find.byKey(const ValueKey('poll-reveal')));
    await t.pump();
    await t.tap(find.text('Sau khi chọn ›'));
    await t.pump();
    expect(appActs.map((e) => e.$1), ['reveal', 'edit']);
    expect(appActs.last.$2, {'results_mode': 'reveal'});
  });

  testWidgets('bình chọn: sửa tại chỗ (kiểu, câu hỏi, phương án), Xong gửi edit', (t) async {
    await pumpAppForms(t, 'binh-chon-sua', poll, appCtx('poll', _poll(results: false, mine: const [])..['voters'] = 0), editing: true, forms: const ['may-tinh', 'dien-thoai-doc']);
    await t.ensureVisible(find.byKey(const ValueKey('opt-add')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('opt-add')));
    await t.pump();
    await t.ensureVisible(find.text('Xong'));
    await t.pump();
    await t.tap(find.text('Xong'));
    await t.pump(const Duration(milliseconds: 100));
    final e = appActs.firstWhere((x) => x.$1 == 'edit').$2;
    expect(((e['questions'] as List).first as Map)['text'], 'Ngày nào bàn giao tòa B?');
  });

  testWidgets('bấm giờ: người xem (trong hàng chờ), người đang nói (xin thêm 1 phút / nói xong)', (t) async {
    await pumpAppForms(t, 'bam-gio-nguoi-xem', timer, appCtx('timer', _timer(), role: 'member'), check: (t, form, light) async {
      expect(find.text('Rút khỏi thứ tự nói'), findsOneWidget);
      expect(find.textContaining('ĐANG NÓI'), findsWidgets);
    });
    await pumpAppForms(t, 'bam-gio-dang-noi', timer, appCtx('timer', _timer(speaking: true), role: 'member'), forms: const ['dien-thoai-doc', 'dien-thoai-ngang']);
    appActs.clear();
    await t.tap(find.byKey(const ValueKey('timer-more')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('timer-finish')));
    await t.pump();
    expect(appActs.map((e) => e.$1), ['more', 'finish']);
    await pumpAppForms(t, 'bam-gio-chua-xin', timer, appCtx('timer', _timer(myTurn: null), role: 'member'), forms: const ['dien-thoai-doc']);
    appActs.clear();
    await t.tap(find.byKey(const ValueKey('timer-join')));
    await t.pump();
    expect(appActs.single.$1, 'join');
  });

  testWidgets('bấm giờ: chủ trang (yêu cầu thêm phút, +1 phút, người kế, đổi thứ tự, gọi ngay)', (t) async {
    await pumpAppForms(t, 'bam-gio-chu-trang', timer, appCtx('timer', _timer(myTurn: null, more: true)), check: (t, form, light) async {
      expect(find.text('Lê Minh xin thêm 1 phút'), findsOneWidget);
    });
    appActs.clear();
    for (final f in [find.byKey(const ValueKey('timer-add')), find.byKey(const ValueKey('timer-next')), find.text('Gọi ngay').first]) {
      await t.ensureVisible(f);
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(appActs.map((e) => e.$1), ['add', 'next', 'call']);
    expect(appActs[1].$2, {'start': true});
  });
}
