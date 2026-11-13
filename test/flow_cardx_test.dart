import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_cardx.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Nút / nhãn / tệp thêm trên thẻ chat (`card_extra`) trên trình soạn.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: child))),
      );
  const vars = [CondVar('form.tep', 'Tệp', 'files'), CondVar('form.so', 'Số', 'text'), CondVar('process.props.so', 'Tiến trình › Số', 'text')];

  test('lỗi của nút như máy chủ', () {
    expect(buttonError({'label': 'Xem', 'url': 'https://x'}), isNull);
    expect(buttonError({'label': 'Xem', 'url': 'http://x'}), contains('https'));
    expect(buttonError({'label': 'Xem', 'url': '{{form.link}}'}), isNull);
    expect(buttonError({'label': '', 'copy': 'x'}), contains('chữ'));
    expect(buttonError({'label': 'a', 'copy': 'x', 'reply': 'y'}), contains('một hành động'));
    expect(buttonError({'label': 'a', 'open': {'process': ''}}), contains('mã tiến trình'));
  });

  testWidgets('thêm nút, nhãn, tệp; xoá hết thì bỏ card_extra', (t) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final n = <String, dynamic>{'id': 'bao', 'type': 'notify'};
    await t.pumpWidget(wrap(CardExtraField(owner: n, vars: vars)));
    await t.tap(find.byKey(const ValueKey('cx-add-button')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('cx-bl-0')), 'Xem PDF');
    await t.pump();
    expect(n['card_extra']['buttons'][0], {'label': 'Xem PDF', 'url': 'https://'});
    await t.tap(find.byKey(const ValueKey('cx-add-tag')));
    await t.pump();
    await t.enterText(find.byKey(const ValueKey('cx-t-0')), 'Gấp');
    await t.tap(find.byKey(const ValueKey('cx-add-file')));
    await t.pump();
    expect(n['card_extra']['tags'], [{'text': 'Gấp', 'color': 'blue'}]);
    expect(n['card_extra']['files'], [{'from': 'form.tep'}]);
    for (final _ in [1, 2, 3]) {
      await t.tap(find.byIcon(Icons.close_rounded).first);
      await t.pump();
    }
    expect(n.containsKey('card_extra'), isFalse);
  });

  testWidgets('thẻ tiến trình: không có tệp, chỉ chèn thông tin tiến trình', (t) async {
    final n = <String, dynamic>{'id': 'tao', 'type': 'process_create'};
    expect(processCardStep(n), isTrue);
    await t.pumpWidget(wrap(CardExtraField(owner: n, vars: vars, process: true)));
    expect(find.byKey(const ValueKey('cx-add-file')), findsNothing);
    expect(find.textContaining('tự cập nhật'), findsOneWidget);
  });

  testWidgets('bảng cấu hình bước Gửi có mục nút / nhãn; lưu giữ card_extra', (t) async {
    t.view.physicalSize = const Size(900, 5000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = FlowDoc.make('send') as FStep;
    s.node['card_extra'] = {
      'buttons': [{'label': 'Xem', 'url': 'https://x'}],
    };
    final doc = FlowDoc.fromJson({'id': 'F', 'name': 'F', 'nodes': [{'id': 'start', 'type': 'start'}, {'id': 'end', 'type': 'end'}], 'edges': [['start', 'end']]});
    doc.steps.add(s);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: StepConfigSheet(app: app, node: s.node, form: const [], roles: const {}, vars: flowVars(doc, at: s), onDone: (_) {}))),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('Nút, nhãn, tệp trên thẻ chat'), findsOneWidget);
    final j = doc.toJson();
    expect(((j['nodes'] as List).firstWhere((x) => x['id'] == s.id) as Map)['card_extra'], {
      'buttons': [{'label': 'Xem', 'url': 'https://x'}],
    });
  });
}
