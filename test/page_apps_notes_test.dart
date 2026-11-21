// Ghi chú theo mockup "mỗi trang là một app" (21/11): bảng của cuộc họp (pha viết / bỏ phiếu / bàn), người xem và chủ trang.
// Ảnh: APP_OUT=<thư mục> flutter test test/page_apps_notes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/pages/page_types.dart';

import 'app_kit_helpers.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _notes({String phase = 'write'}) => {
      'mode': 'todo', 'board_id': 'B1', 'meeting': 'abc-defg-hij', 'offline': false, 'now': _now, 'phase': phase, 'write_until': phase == 'write' ? _now + 200000 : 0,
      'hide_names': false, 'conceal': phase == 'write', 'votes_per_person': 3, 'votes_left': 2, 'pinned_note': 'n4', 'title': 'Rút kinh nghiệm tòa C', 'anon': false,
      'columns': [{'id': 'c1', 'name': 'Làm tốt'}, {'id': 'c2', 'name': 'Cần cải thiện'}, {'id': 'c3', 'name': 'Việc sắp tới'}],
      'notes': [
        {'id': 'n1', 'text': 'Khảo sát hố thang trước 2 tuần, không phát sinh', 'concealed': false, 'color': 'yellow', 'col': 'c1', 'by_name': 'Lợi', 'votes': 6, 'voted': true, 'mine': false, 'pinned': false},
        {'id': 'n2', 'text': 'Bàn giao từng tầng, có biên bản ảnh', 'concealed': false, 'color': 'green', 'col': 'c1', 'by_name': 'Ba', 'votes': 4, 'voted': false, 'mine': true, 'pinned': false},
        {'id': 'n3', 'text': '', 'concealed': phase == 'write', 'color': 'blue', 'col': 'c1', 'by_name': '', 'votes': 3, 'voted': false, 'mine': false, 'pinned': false},
        {'id': 'n4', 'text': 'Thiếu người trực ca tối khi chạy thử', 'concealed': false, 'color': 'pink', 'col': 'c2', 'by_name': 'Kim', 'votes': 5, 'voted': false, 'mine': false, 'pinned': true},
      ],
      'can_manage': false,
    };

void main() {
  setUpAll(loadAppTestFonts);
  setUp(appActs.clear);
  final notes = pageTypeOf('notes')!;

  testWidgets('ghi chú: người xem đang viết (cột, che ghi chú người khác, viết vào cột)', (t) async {
    await pumpAppForms(t, 'ghi-chu-dang-viet', notes, appCtx('notes', _notes(), role: 'member'), check: (t, f, l) async {
      expect(find.textContaining('Đang viết · còn'), findsWidgets);
      expect(find.text('Ghi chú đang viết (che tới khi hết giờ)'), findsOneWidget);
    });
    await t.ensureVisible(find.byKey(const ValueKey('note-text')));
    await t.enterText(find.byKey(const ValueKey('note-text')), 'Đội lắp đặt đúng giờ');
    await t.tap(find.byKey(const ValueKey('note-send')));
    await t.pump();
    expect(appActs.single.$1, 'add');
    expect(appActs.single.$2, {'text': 'Đội lắp đặt đúng giờ', 'col': 'c1'});
  });

  testWidgets('ghi chú: bỏ phiếu (+1 khi chạm), đổi cột, chủ trang (pha, +2 phút, cài đặt)', (t) async {
    await pumpAppForms(t, 'ghi-chu-bo-phieu', notes, appCtx('notes', _notes(phase: 'vote'), role: 'member'), forms: const ['dien-thoai-doc', 'dien-thoai-ngang']);
    await t.tap(find.byKey(const ValueKey('note-n2')));
    await t.pump();
    expect(appActs.last, isA<(String, Map<String, dynamic>)>());
    expect(appActs.last.$1, 'vote');
    await t.tap(find.byKey(const ValueKey('col-c2')));
    await t.pump();
    expect(find.text('Thiếu người trực ca tối khi chạy thử'), findsWidgets);
    appActs.clear();
    await pumpAppForms(t, 'ghi-chu-chu-trang', notes, appCtx('notes', _notes()), check: (t, f, l) async {
      expect(find.text('Che ghi chú người khác khi đang viết'), findsOneWidget);
    });
    for (final f in [find.byKey(const ValueKey('notes-more')), find.byKey(const ValueKey('notes-stop'))]) {
      await t.ensureVisible(f);
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(f);
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(appActs.map((e) => e.$1), ['add_time', 'phase']);
  });
}
