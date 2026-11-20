// Khung nổi PiP của cuộc họp: chỉ cửa sổ chính hiện (khi đã rời màn họp); cửa sổ phụ của app trên máy tính (mini app…)
// không vẽ thêm khung thừa (bug 2026-11-20).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/calls/call_kind.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/meet/call_pip.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pump(WidgetTester t, AppState app) => t.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: CallPipLayer(child: Scaffold(body: Text('nền')))),
      ));

  testWidgets('cửa sổ chính: rời màn họp thì có khung nổi; cửa sổ phụ: không', (t) async {
    final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
    app.calls.debugMeeting('c' * 26, const [], info: const MeetingInfo(postId: 'p', creatorId: 'me', title: 'Cuộc họp của Ba'));
    await pump(t, app);
    expect(find.text('1 người'), findsOneWidget);
    kWindowMiniApp = 'vn.flygo.screens';
    addTearDown(() => kWindowMiniApp = null);
    await pump(t, AppState('t2')..me = app.me);
    final app2 = AppState('t3')..me = app.me;
    app2.calls.debugMeeting('c' * 26, const [], info: const MeetingInfo(postId: 'p', creatorId: 'me', title: 'Cuộc họp của Ba'));
    await pump(t, app2);
    expect(find.text('1 người'), findsNothing);
    expect(find.text('nền'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
