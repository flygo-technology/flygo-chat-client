// Nút ký số của Quy trình: mở bằng trình duyệt ký số qua MagicSignHooks (hook giả), chưa cài thì mở link như thường
// kèm thông báo; trình sửa có tuỳ chọn "Mở bằng trình duyệt ký số" lấy danh sách token từ hook.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/ui/flows/flow_task_action.dart';
import 'package:flygo_chat/ui/flows/magic_sign_hooks.dart';
import 'package:flygo_chat/ui/theme.dart';

void main() {
  tearDown(() {
    MagicSignHooks.openSignBrowser = null;
    MagicSignHooks.signTokens = null;
  });

  Future<BuildContext> host(WidgetTester t, [Widget? child]) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return child ?? const SizedBox();
      })),
    ));
    return ctx;
  }

  testWidgets('có hook: mở trình duyệt ký số đúng token, link, máy chủ', (t) async {
    final calls = <(String, String, String?)>[];
    MagicSignHooks.openSignBrowser = (c, {required token, required url, server}) async => calls.add((token, url, server));
    final ctx = await host(t);
    final handled = await openFlowSignButton(ctx, {'label': 'Ký', 'url': 'https://minvoice.vn/hd/2154', 'sign': {'token': 'cty-a', 'server': 'https://sign.flygo.vn'}});
    expect(handled, isTrue);
    expect(calls, [('cty-a', 'https://minvoice.vn/hd/2154', 'https://sign.flygo.vn')]);
    // Nút link thường (không sign): để nơi gọi mở như cũ.
    expect(await openFlowSignButton(ctx, {'label': 'Xem', 'url': 'https://x.vn'}), isFalse);
    expect(calls.length, 1);
  });

  testWidgets('chưa cài ký số: báo "Chưa cài ký số trên app này"', (t) async {
    final ctx = await host(t);
    // Không có http/https: không gọi trình duyệt ngoài trong test, chỉ kiểm thông báo.
    final handled = await openFlowSignButton(ctx, {'label': 'Ký', 'url': 'about:blank', 'sign': {'token': 'cty-a'}});
    await t.pump();
    expect(handled, isTrue);
    expect(find.text('Chưa cài ký số trên app này'), findsOneWidget);
  });

  testWidgets('trình sửa: bật ký số, chọn token từ hook', (t) async {
    MagicSignHooks.signTokens = () async => [(id: 'tk1', name: 'Token Cty A', company: 'Cty A'), (id: 'tk2', name: 'Token Flygo', company: 'Flygo')];
    final b = <String, dynamic>{'label': 'Ký', 'url': 'https://x.vn'};
    var changed = 0;
    await host(t, SingleChildScrollView(child: FlowSignEditor(button: b, vars: const [], onChanged: () => changed++)));
    await t.pumpAndSettle();
    expect(b.containsKey('sign'), isFalse);
    await t.tap(find.text('Mở bằng trình duyệt ký số'));
    await t.pumpAndSettle();
    expect(b['sign'], {'token': ''});
    expect(find.textContaining('Đã ký xong'), findsOneWidget, reason: 'gợi ý thêm nút "Đã ký xong"');
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Token Flygo · Flygo').last);
    await t.pumpAndSettle();
    expect(b['sign'], {'token': 'tk2'});
    expect(changed, greaterThan(1));
    // Tắt: bỏ sign.
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(b.containsKey('sign'), isFalse);
  });

  testWidgets('trình sửa: không có danh sách token thì gõ tự do', (t) async {
    final b = <String, dynamic>{'label': 'Ký', 'url': 'https://x.vn', 'sign': {'token': ''}};
    await host(t, SingleChildScrollView(child: FlowSignEditor(button: b, vars: const [], onChanged: () {})));
    await t.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Token công ty (mã, tên hoặc chèn thông tin)'), findsOneWidget);
  });

  testWidgets('việc trong Tiến trình của tôi: bấm nút ký số gọi hook, nút "Đã ký xong" gửi như thường', (t) async {
    final calls = <String>[];
    MagicSignHooks.openSignBrowser = (c, {required token, required url, server}) async => calls.add('$token|$url');
    final sent = <Map<String, dynamic>>[];
    final task = FlowTask.fromJson({
      'id': 5, 'instance_id': 'i1', 'node': 'cho', 'kind': 'action', 'title': 'Ký hoá đơn', 'flow_id': 'ky', 'created_at': 0,
      'action': {
        'kind': 'buttons', 'prompt': 'Ký hoá đơn 2154',
        'buttons': [
          {'id': 'mo', 'label': 'Ký trên M-Invoice', 'url': 'https://minvoice.vn/hd/2154', 'sign': {'token': 'cty-a'}},
          {'id': 'xong', 'label': 'Đã ký xong', 'style': 'primary'},
        ],
      },
    });
    await host(t, FlowTaskActionPanel(task: task, onSubmit: (d) async => sent.add(d)));
    expect(find.byIcon(Icons.draw_outlined), findsOneWidget, reason: 'nút ký số có biểu tượng riêng');
    await t.tap(find.text('Ký trên M-Invoice'));
    await t.pumpAndSettle();
    expect(calls, ['cty-a|https://minvoice.vn/hd/2154']);
    expect(sent, isEmpty, reason: 'nút link không rẽ nhánh');
    await t.tap(find.text('Đã ký xong'));
    await t.pumpAndSettle();
    expect(sent.single['clicked'], 'xong');
  });
}
