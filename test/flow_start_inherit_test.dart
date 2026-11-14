// Một chỗ cài quyền: ai được dùng quy trình thì được bấm "Bắt đầu"; danh sách riêng chỉ khi bật "Nâng cao".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_starts.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'admin', 'first_name': 'Admin'});
  app.users['u2'] = MmUser({'id': 'u2', 'username': 'lan', 'first_name': 'Lan'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));
  const me = {'user': 'me'}, dept = {'department': 'kt_hn'}, u2 = {'user': 'u2'};

  test('manualRestriction: cùng luật với máy chủ', () {
    expect(manualRestriction({'type': 'manual'}, [me, dept]), isNull);
    expect(manualRestriction({'type': 'manual', 'who': [me]}, [me, dept]), isNull, reason: 'nằm gọn trong Ai được dùng');
    expect(manualRestriction({'type': 'manual', 'who': [u2]}, [me, dept]), [u2]);
    expect(manualRestriction({'type': 'manual', 'who': [me]}, const []), [me], reason: 'cả công ty: giữ danh sách cũ');
    expect(manualRestriction({'type': 'manual', 'who': [me], 'only': true}, [me, dept]), [me]);
    expect(manualRestriction({'type': 'manual', 'who': [u2], 'only': false}, [me]), isNull);
  });

  test('normalizeManualStart: bỏ who khi theo Ai được dùng, ghi only khi có danh sách riêng', () {
    final a = {'type': 'manual', 'who': [me]};
    normalizeManualStart(a, [me, dept]);
    expect(a.containsKey('who') || a.containsKey('only'), isFalse);
    final b = {'type': 'manual', 'who': [u2]};
    normalizeManualStart(b, [me, dept]);
    expect(b['only'], isTrue);
    final c = {'type': 'schedule', 'who': [me]};
    normalizeManualStart(c, [me]);
    expect(c['who'], [me]);
  });

  test('startSummary: nốt Bấm thủ công hiện Ai được dùng, hoặc "Chỉ: ..."', () {
    expect(startSummary({'type': 'manual'}, app), 'Mọi người');
    expect(startSummary({'type': 'manual'}, app, visibleTo: [u2]), 'Lan');
    expect(startSummary({'type': 'manual', 'who': [u2], 'only': true}, app, visibleTo: [me, u2]), 'Chỉ: Lan');
  });

  testWidgets('cấu hình nốt Bấm thủ công: mặc định không có danh sách riêng; bật Nâng cao mới hiện "Ai được bắt đầu"', (t) async {
    t.view.physicalSize = const Size(500, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    editorCtx = EditorCtx(app: app, api: api, doc: FlowDoc.fromJson({'id': 'X', 'name': 'X', 'visible_to': [u2], 'nodes': <dynamic>[]}));
    addTearDown(() => editorCtx = null);
    Object? done;
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: StartConfigSheet(
              app: app, api: api, start: const {'id': 'manual', 'type': 'manual'}, form: const [], roles: const {}, integ: const {}, flowId: 'X', onDone: (r) => done = r),
        ),
      ),
    ));
    await t.pump();
    expect(find.textContaining('thì được bắt đầu. Hiện là: Lan.'), findsOneWidget);
    expect(find.text('Ai được bắt đầu'), findsNothing);
    final sw = find.byKey(const ValueKey('manual-only'));
    expect(t.widget<SwitchListTile>(sw).value, isFalse);
    await t.tap(sw);
    await t.pump();
    expect(find.text('Ai được bắt đầu'), findsOneWidget);
    await t.tap(find.text('Xong'));
    await t.pump();
    expect((done as Map)['only'], isTrue);
    // Tắt lại: bỏ cả only lẫn who.
    done = null;
    await t.tap(sw);
    await t.pump();
    await t.tap(find.text('Xong'));
    await t.pump();
    expect((done as Map).containsKey('only') || (done as Map).containsKey('who'), isFalse);
  });
}
