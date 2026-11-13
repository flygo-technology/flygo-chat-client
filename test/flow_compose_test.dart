import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_compose.dart';
import 'package:flygo_chat/ui/flows/flow_editor_expr.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Bước Soạn nội dung (`compose`) trên trình soạn: dựng mẫu như máy chủ, xem trước, thanh nút định dạng.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: child))),
      );

  const body = '<p>Kính gửi <b>{{steps.mail.output.ten}}</b>,</p>{{#if steps.mail.output.ma}}<p>Mã: {{steps.mail.output.ma}}</p>{{else}}<p>Không mã</p>{{/if}}'
      '<table>{{#each steps.mail.output.dong}}<tr><td>{{loop.index}}</td><td>{{item.ten}}</td></tr>{{/each}}</table><p>Tổng {{money(steps.mail.output.tong)}}</p>';

  test('dựng mẫu như máy chủ: mã hoá giá trị, nếu / còn lại, lặp, chỗ chèn trống', () {
    final ctx = {
      'steps': {
        'mail': {
          'output': {
            'ten': 'Cty <A&B>',
            'ma': '',
            'tong': 1080000,
            'dong': [{'ten': 'Bút'}, {'ten': 'Vở'}],
          },
        },
      },
    };
    final (html, missing) = renderCompose(body, ctx);
    expect(html, contains('<b>Cty &lt;A&amp;B&gt;</b>'));
    expect(html, contains('<p>Không mã</p>'));
    expect(html, contains('<tr><td>1</td><td>Bút</td></tr><tr><td>2</td><td>Vở</td></tr>'));
    expect(html, contains('1.080.000 ₫'));
    expect(missing, isEmpty);
    final (subj, m2) = renderCompose('HĐ {{steps.mail.output.ten}} {{vars.khong}}', ctx, html: false);
    expect(subj, 'HĐ Cty <A&B> ');
    expect(m2, ['vars.khong']);
  });

  test('lỗi cấu trúc khối', () {
    expect(composeError(body), isNull);
    expect(composeError('{{#if a}}x'), contains('chưa đóng'));
    expect(composeError('{{/each}}'), contains('không có khối mở'));
    expect(composeError('{{#each a}}{{/if}}'), contains('đóng nhầm'));
    expect(composeError('{{else}}'), isNotNull);
  });

  test('dữ liệu mẫu: mỗi thông tin theo kiểu, bảng trong lặp có hai dòng', () {
    final ctx = sampleCtx(const [CondVar('steps.mail.output.ten', 'Thư › Tên khách', 'text'), CondVar('steps.mail.output.tong', 'Thư › Tổng', 'money')], body);
    expect((ctx['steps'] as Map)['mail']['output']['ten'], '‹Tên khách›');
    expect((ctx['steps'] as Map)['mail']['output']['tong'], 1080000);
    expect(((ctx['steps'] as Map)['mail']['output']['dong'] as List).length, 2);
    final (html, _) = renderCompose(body, ctx);
    expect(html, contains('‹ten 2›'));
  });

  test('hàm money / date_vn', () {
    expect(evalExprText('money(1234567.6)', const {}), '1.234.568 ₫');
    expect(evalExprText("date_vn('2026-01-05')", const {}), '05/01/2026');
    expect(evalExprText("money('x')", const {}), '');
  });

  testWidgets('xem trước: tiêu đề, đậm, danh sách, bảng; không hiện script', (t) async {
    await t.pumpWidget(wrap(const HtmlPreview(html: '<h2>Tiêu đề</h2><p>A <b>đậm</b> <span style="color: #e53935">đỏ</span></p><ul><li>một</li><li>hai</li></ul>'
        '<table><tr><th>STT</th><th>Tên</th></tr><tr><td>1</td><td>Bút</td></tr></table><script>alert(1)</script><p onclick="x">ok</p>')));
    expect(t.takeException(), isNull);
    expect(find.text('Tiêu đề'), findsOneWidget);
    expect(find.textContaining('đậm', findRichText: true), findsWidgets);
    expect(find.text('•'), findsNWidgets(2));
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('Bút'), findsOneWidget);
    expect(find.textContaining('alert', findRichText: true), findsNothing);
  });

  testWidgets('ô soạn: nút Đậm bọc phần chọn, chèn dữ liệu, xem trước', (t) async {
    t.view.physicalSize = const Size(900, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final n = <String, dynamic>{'id': 'soan', 'type': 'compose', 'subject': 'HĐ', 'body': 'Xin chào'};
    await t.pumpWidget(wrap(ComposeConfig(n: n, vars: const [CondVar('vars.ten', 'Biến › ten', 'text')])));
    final field = t.widget<TextField>(find.byKey(const ValueKey('c-body')));
    field.controller!.selection = const TextSelection(baseOffset: 4, extentOffset: 8);
    await t.tap(find.byKey(const ValueKey('c-bold')));
    await t.pump();
    expect(n['body'], 'Xin <b>chào</b>');
    field.controller!.selection = TextSelection.collapsed(offset: field.controller!.text.length);
    await t.tap(find.byKey(const ValueKey('c-data')));
    await t.pumpAndSettle();
    await t.tap(find.text('Biến › ten').last);
    await t.pumpAndSettle();
    expect(n['body'], 'Xin <b>chào</b>{{vars.ten}}');
    await t.tap(find.text('Xem trước'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('c-preview')), findsOneWidget);
    expect(find.textContaining('‹ten›', findRichText: true), findsWidgets);
  });

  testWidgets('bước Soạn nội dung trong bảng cấu hình; mở rồi lưu giữ nguyên', (t) async {
    t.view.physicalSize = const Size(900, 4000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = FlowDoc.make('compose') as FStep;
    final doc = FlowDoc.fromJson({'id': 'F3', 'name': 'F3', 'nodes': [{'id': 'start', 'type': 'start'}, {'id': 'end', 'type': 'end'}], 'edges': [['start', 'end']]});
    doc.steps.add(s);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: StepConfigSheet(app: app, node: s.node, form: const [], roles: const {}, vars: flowVars(doc, at: s), onDone: (_) {}))),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Soạn nội dung'), findsWidgets);
    s.node['subject'] = 'HĐ {{vars.x}}';
    final j = doc.toJson();
    final n = (j['nodes'] as List).firstWhere((x) => x['id'] == s.id) as Map;
    expect((n['type'], n['subject'], n['body']), ('compose', 'HĐ {{vars.x}}', '<p></p>'));
    expect({for (final v in flowVars(doc)) v.path}, containsAll(['steps.${s.id}.output.html', 'steps.${s.id}.output.subject']));
  });
}
