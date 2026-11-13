import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/checklist.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

/// Tin "Việc cần làm": dựng props, chữ dự phòng, giữ tick khi sửa, luật ai được tick, thẻ hiển thị.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba'});
  Widget wrap(Widget w) => ChangeNotifierProvider<AppState>.value(
      value: app, child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: w))));

  test('dựng danh sách, bỏ dòng trống, chữ dự phòng có mô tả', () {
    final c = buildChecklist(title: 'Việc chiều nay', desc: 'Trước 17h', lines: ['  Gọi NCC ', '', 'Gửi báo giá'], me: 'me', tick: 'some', tickers: ['u2']);
    expect(checklistItems(c).map((e) => e['text']), ['Gọi NCC', 'Gửi báo giá']);
    expect(c['tickers'], ['u2']);
    expect(checklistText(c), '📝 Việc chiều nay\nTrước 17h\n☐ Gọi NCC\n☐ Gửi báo giá');
    expect(buildChecklist(title: '', lines: ['A'], me: 'me', tick: 'all', tickers: ['u2'])['tickers'], isEmpty, reason: 'chỉ "some" mới giữ danh sách');
  });

  test('sửa giữ trạng thái tick; luật ai được tick', () {
    final c = buildChecklist(title: '', lines: ['A', 'B'], me: 'me');
    (c['items'] as List)[0]['done'] = true;
    final c2 = buildChecklist(title: '', lines: ['A', 'C'], me: 'me', old: c);
    expect(checklistItems(c2)[0]['done'], true);
    expect(canTickChecklist({'tick': 'me'}, 'a', 'a'), true);
    expect(canTickChecklist({'tick': 'me'}, 'a', 'b'), false);
    expect(canTickChecklist({'tick': 'all'}, 'a', 'b'), true);
    expect(canTickChecklist({'tick': 'some', 'tickers': ['b']}, 'a', 'b'), true);
    expect(canTickChecklist({'tick': 'some', 'tickers': ['b']}, 'a', 'c'), false);
  });

  testWidgets('người không được phép chỉ xem; người được chọn thì tick được', (t) async {
    MmPost post(Map<String, dynamic> c) => MmPost({'id': 'p', 'channel_id': 'c', 'user_id': 'u2', 'message': 'x', 'create_at': 0, 'props': {'flygo_checklist': c}});
    await t.pumpWidget(wrap(ChecklistCard(app: app, post: post(buildChecklist(title: 'Kho', desc: 'Kiểm hàng', lines: ['A', 'B'], me: 'u2')), width: 320)));
    expect(find.text('Kho'), findsOneWidget);
    expect(find.text('Kiểm hàng'), findsOneWidget);
    expect(find.text('Chỉ người gửi được tick'), findsOneWidget);
    expect(t.widget<Checkbox>(find.byType(Checkbox).first).onChanged, isNull);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await t.pumpWidget(wrap(ChecklistCard(app: app, post: post(buildChecklist(title: 'Kho', lines: ['A'], me: 'u2', tick: 'some', tickers: ['me'])), width: 320)));
    expect(t.widget<Checkbox>(find.byType(Checkbox).first).onChanged, isNotNull);
  });

  testWidgets('trang soạn: đủ các mục, Enter ở một việc thêm dòng mới, Gửi trả về props', (t) async {
    Map<String, dynamic>? got;
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(builder: (c) => Scaffold(body: FilledButton(onPressed: () async => got = await showChecklistEditor(c, app: app, channelId: 'ch'), child: const Text('mở')))),
      ),
    ));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    for (final s in ['Tiêu đề', 'Nội dung mô tả', 'Cho phép sửa sau khi gửi', 'Danh sách việc', 'Ai được tick', 'Chỉ mình tôi', 'Mọi người trong chat', 'Một số người']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    await t.enterText(find.widgetWithText(TextField, 'Tiêu đề'), 'Việc sáng mai');
    await t.enterText(find.widgetWithText(TextField, 'Việc cần làm').first, 'Gọi NCC');
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Việc cần làm').last, 'Gửi báo giá');
    await t.tap(find.text('Mọi người trong chat'));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await t.pumpAndSettle();
    expect(got?['title'], 'Việc sáng mai');
    expect(checklistItems(got!).map((e) => e['text']), ['Gọi NCC', 'Gửi báo giá']);
    expect(got!['tick'], 'all');
    expect(got!['allow_edit'], true);
  });
}
