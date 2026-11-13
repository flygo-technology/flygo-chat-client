import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/agent_view.dart';
import 'package:flygo_chat/ui/theme.dart';

/// Các bước của trợ lý hiện ngay trong tin theo thứ tự, cập nhật trực tiếp, mở chi tiết, thu gọn sau khi xong.
void main() {
  Widget wrap(Map<String, dynamic> run, {Brightness b = Brightness.light, String? key}) => MaterialApp(
        theme: buildTheme(b),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentTimeline(run: run, textStyle: const TextStyle(fontSize: 15), openKey: key),
          ),
        ),
      );

  Map<String, dynamic> step(String title, {String status = 'done', int seg = 0, String kind = 'command', String detail = ''}) =>
      {'kind': kind, 'title': title, 'status': status, 'seg': seg, if (detail.isNotEmpty) 'detail': detail};

  testWidgets('live step is appended inline in order with running/done states', (t) async {
    final run = <String, dynamic>{
      'status': 'running',
      'texts': ['Em xem trước.', ''],
      'steps': [step(r'$ git status')],
    };
    await t.pumpWidget(wrap(run));
    expect(find.text('Em xem trước.', findRichText: true), findsOneWidget);
    expect(find.textContaining('git status', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // Chi tiết bước đang thu gọn: mũi tên ngang (mở thì mũi tên xuống).
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    // Bước mới đến khi đang chạy: hiện ngay ở cuối, có vòng quay.
    final run2 = {
      ...run,
      'steps': [...run['steps'] as List, step(r'$ flutter test', status: 'running', seg: 1)],
    };
    await t.pumpWidget(wrap(run2));
    final a = t.getTopLeft(find.textContaining('git status', findRichText: true));
    final b = t.getTopLeft(find.textContaining('flutter test', findRichText: true));
    final text = t.getTopLeft(find.text('Em xem trước.', findRichText: true));
    expect(a.dy < text.dy && text.dy < b.dy, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Đang chạy', findRichText: true), findsOneWidget);

    // Xong: dấu xong thay vòng quay; lỗi thì biểu tượng lỗi.
    final run3 = {
      ...run2,
      'status': 'done',
      'steps': [step(r'$ git status'), step(r'$ flutter test', status: 'error', seg: 1)],
    };
    await t.pumpWidget(wrap(run3));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('steps run after the last text stay below it (text not repeated as the message body)', (t) async {
    // Trợ lý viết "Em chạy thử." rồi mới chạy lệnh: lệnh (seg 1) phải nằm dưới đoạn chữ đó.
    final run = <String, dynamic>{
      'status': 'running',
      'texts': ['Em chạy thử.'],
      'steps': [step(r'$ git status'), step(r'$ flutter test', status: 'running', seg: 1)],
    };
    expect(agentTextsInTimeline(run), isTrue);
    await t.pumpWidget(wrap(run));
    final a = t.getTopLeft(find.textContaining('git status', findRichText: true));
    final text = t.getTopLeft(find.text('Em chạy thử.', findRichText: true));
    final b = t.getTopLeft(find.textContaining('flutter test', findRichText: true));
    expect(a.dy < text.dy && text.dy < b.dy, isTrue);
    // Chưa có bước sau đoạn cuối: đoạn cuối là nội dung tin (hiện bên dưới), không lặp ở dòng thời gian.
    final plain = {...run, 'steps': [step(r'$ git status')]};
    expect(agentTextsInTimeline(plain), isFalse);
    await t.pumpWidget(wrap(plain));
    expect(find.text('Em chạy thử.', findRichText: true), findsNothing);
  });

  testWidgets('tap a step to expand its detail inline', (t) async {
    final run = <String, dynamic>{
      'status': 'done',
      'texts': [''],
      'steps': [step(r'$ ls -la', detail: 'total 42')],
    };
    await t.pumpWidget(wrap(run, key: 'p-expand'));
    expect(find.text('total 42'), findsNothing);
    await t.tap(find.textContaining('ls -la', findRichText: true));
    await t.pump();
    expect(find.text('total 42'), findsOneWidget);
    expect(find.text('bash'), findsOneWidget);
    // Dựng lại (tin cập nhật) vẫn giữ trạng thái mở theo khoá.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(wrap(run, key: 'p-expand'));
    expect(find.text('total 42'), findsOneWidget);
    await t.tap(find.textContaining('ls -la', findRichText: true).first);
    await t.pump();
    expect(find.text('total 42'), findsNothing);
  });

  testWidgets('long group stays open after completion and folds on demand', (t) async {
    final steps = [for (var i = 0; i < 9; i++) step('\$ cmd$i')];
    await t.pumpWidget(wrap({'status': 'running', 'texts': [''], 'steps': steps}));
    for (var i = 0; i < 9; i++) {
      expect(find.textContaining('cmd$i', findRichText: true), findsOneWidget);
    }
    expect(find.textContaining('Xem thêm'), findsNothing);

    // Xong lượt: mặc định vẫn hiện đủ (Sếp chọn 2026-11-10), có nút Thu gọn.
    await t.pumpWidget(wrap({'status': 'done', 'texts': [''], 'steps': steps}, b: Brightness.dark));
    expect(find.textContaining('cmd8', findRichText: true), findsOneWidget);
    expect(find.text('Thu gọn'), findsOneWidget);

    await t.tap(find.text('Thu gọn'));
    await t.pump();
    expect(find.textContaining('cmd2', findRichText: true), findsOneWidget);
    expect(find.textContaining('cmd3', findRichText: true), findsNothing);
    expect(find.text('Xem thêm 6 bước'), findsOneWidget);
    await t.tap(find.text('Xem thêm 6 bước'));
    await t.pump();
    expect(find.textContaining('cmd8', findRichText: true), findsOneWidget);
  });

  testWidgets('short group is not collapsed after completion', (t) async {
    final steps = [for (var i = 0; i < 5; i++) step('\$ cmd$i')];
    await t.pumpWidget(wrap({'status': 'done', 'texts': [''], 'steps': steps}));
    expect(find.textContaining('cmd4', findRichText: true), findsOneWidget);
    expect(find.textContaining('Xem thêm'), findsNothing);
  });
}
