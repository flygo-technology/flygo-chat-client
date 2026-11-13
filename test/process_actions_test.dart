// Tiến trình: nút open / input / select trên thẻ flygo_card, việc "action" (Chờ bấm nút / Lựa chọn), yêu cầu phê duyệt
// (từ chối có lý do, trả lại chọn bước), việc bị trả lại điền sẵn, ghi chú và nút đang mở ở chi tiết tiến trình, đường
// dẫn API theo docs/flows-guide.md.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_form.dart';
import 'package:flygo_chat/ui/flows/flow_task_action.dart';
import 'package:flygo_chat/ui/flows/flows_page.dart';
import 'package:flygo_chat/ui/flows/process_detail.dart';
import 'package:flygo_chat/ui/flygo_card.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json'});

void main() {
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['u2'] = MmUser({'id': 'u2', 'username': 'lan', 'first_name': 'Lan'});
  final now = DateTime.now().millisecondsSinceEpoch;

  // ------------------------------------------------------------------ dữ liệu giả của máy chủ
  final actionTask = {
    'id': 1, 'instance_id': 'i1', 'node': 'chon', 'kind': 'action', 'title': 'Hoá đơn 2154', 'flow_id': 'linkq', 'created_at': now,
    'action': {
      'kind': 'buttons', 'prompt': 'Ký hoá đơn 2154?',
      'buttons': [
        {'id': 'ky', 'label': 'Ký', 'style': 'primary'},
        {'id': 'khong', 'label': 'Không ký', 'confirm': 'Chắc chắn không ký?'},
        {'id': 'pdf', 'label': 'Xem PDF', 'url': 'https://linkq.vn/2154.pdf'},
      ],
    },
  };
  final choiceTask = {
    'id': 4, 'instance_id': 'i2', 'node': 'xu_ly', 'kind': 'action', 'title': 'Hoá đơn 2155', 'flow_id': 'linkq', 'created_at': now,
    'action': {
      'kind': 'choice', 'prompt': 'Xử lý hoá đơn nghi trùng',
      'choices': {
        'id': 'xu_ly:choice', 'min': 1, 'max': 2, 'submit_label': 'Gửi lựa chọn', 'done': false,
        'options': [{'id': 'xuat', 'label': 'Vẫn xuất'}, {'id': 'bao', 'label': 'Báo kế toán trưởng'}, {'id': 'huy', 'label': 'Huỷ'}],
      },
    },
  };
  final approvalTask = {
    'id': 2, 'instance_id': 'i1', 'node': 'duyet', 'kind': 'approval', 'title': 'Hoá đơn 2154', 'flow_id': 'linkq', 'created_at': now,
    'request': {
      'title': 'Xuất hoá đơn nghi trùng 2154', 'reason': 'Trùng số tiền với HĐ 2101', 'mode': 'any', 'fields': [], 'editable': [],
      'return_steps': [{'id': 'start', 'label': 'Bắt đầu'}, {'id': 'bo_sung', 'label': 'Bổ sung thông tin'}], 'level': 1,
    },
  };
  final returnedTask = {
    'id': 3, 'instance_id': 'i1', 'node': 'bo_sung', 'kind': 'form', 'title': 'Hoá đơn 2154', 'flow_id': 'linkq', 'created_at': now,
    'returned': {'reason': 'Sai tên khách', 'by': 'u2', 'at': now, 'from': 'duyet'},
    'prefill': {'khach': 'Cty Hoàng Long'},
  };
  Map<String, dynamic> basic(Map<String, dynamic> t) => {for (final k in ['id', 'instance_id', 'node', 'kind', 'title', 'flow_id', 'created_at']) k: t[k]};
  final inst = {
    'id': 'i1', 'flow_id': 'linkq', 'flow_version': 1, 'title': 'Hoá đơn 2154', 'status': 'running', 'requester': 'me', 'created_at': now, 'updated_at': now,
    'form': {'so': '2154'}, 'steps': {}, 'events': [],
    'def': {
      'id': 'linkq', 'name': 'Đồng bộ hoá đơn', 'form': [{'key': 'so', 'label': 'Số', 'type': 'text'}],
      'nodes': [
        {'id': 'start', 'type': 'start'},
        {'id': 'chon', 'type': 'wait_button', 'name': 'Chờ ký'},
        {'id': 'duyet', 'type': 'approval_request', 'name': 'Duyệt nghi trùng', 'return_steps': ['start', 'bo_sung']},
        {'id': 'bo_sung', 'type': 'form_task', 'name': 'Bổ sung thông tin', 'fields': [{'key': 'khach', 'label': 'Khách', 'type': 'text', 'required': true}]},
        {'id': 'end', 'type': 'end'},
      ],
    },
    // Chi tiết đơn chỉ có phần cơ bản; app lấy phần thêm từ /flows/tasks.
    'my_tasks': [basic(actionTask), basic(approvalTask), basic(returnedTask)],
  };
  final processDetail = {
    'id': 'P-8K2Q4M', 'flow_id': 'linkq', 'flow_name': 'Đồng bộ hoá đơn', 'name': 'Hoá đơn 2154', 'state': 'running', 'status_text': 'Chờ duyệt', 'tone': 'orange',
    'steps': [{'key': 'ky', 'title': 'Ký', 'state': 'active'}], 'stats': [], 'labels': [], 'files': [], 'posts': [], 'events': [], 'created_at': now,
    'note': 'Bị trả lại: thiếu chứng từ',
    'actions': [
      {
        'wait': 'duyet', 'kind': 'approval', 'prompt': 'Xuất hoá đơn nghi trùng 2154: trùng số tiền',
        'actions': [
          {'id': 'duyet:approve', 'label': 'Duyệt', 'style': 'primary'},
          {'id': 'duyet:reject', 'label': 'Từ chối', 'input': {'label': 'Lý do từ chối', 'required': true}},
        ],
      },
      {'wait': 'cu', 'kind': 'buttons', 'prompt': 'Bước chờ đã đóng', 'closed': true, 'actions': []},
    ],
  };

  final requests = <http.Request>[];
  Map<String, dynamic> body(String path) => jsonDecode(requests.lastWhere((r) => r.url.path == path).body) as Map<String, dynamic>;
  setUp(() {
    requests.clear();
    FlowsApi.debugClient = MockClient((r) async {
      requests.add(r);
      return switch (r.url.path) {
        '/__apps/flows/instances/i1' => _json(inst),
        '/__apps/flows/tasks' => _json({'tasks': [actionTask, choiceTask, approvalTask, returnedTask]}),
        '/__apps/flows/processes/P-8K2Q4M' || '/__apps/flows/processes/P-1' => _json(processDetail),
        '/__apps/flows/processes/P-1/files/f1' => http.Response.bytes(utf8.encode('%PDF'), 200),
        '/__apps/flows/instances' => _json({'instances': []}),
        '/__apps/flows/defs' => _json({'flows': []}),
        '/__apps/flows/me' => _json({'id': 'me'}),
        _ => _json({'ok': true}),
      };
    });
  });
  tearDown(() => FlowsApi.debugClient = null);

  Future<void> pump(WidgetTester t, Widget home, {Size size = const Size(430, 1600)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 6));
  }

  // ------------------------------------------------------------------ API
  test('API: việc có action / request / returned / prefill; quyết kèm return_step; đường dẫn tiến trình', () async {
    final api = FlowsApi('tok');
    final tasks = await api.tasks();
    expect(tasks.first.action?['kind'], 'buttons');
    expect(tasks[2].request?['title'], 'Xuất hoá đơn nghi trùng 2154');
    expect([for (final s in tasks[2].returnSteps) s['id']], ['start', 'bo_sung']);
    expect(tasks[3].returned?['reason'], 'Sai tên khách');
    expect(tasks[3].prefill, {'khach': 'Cty Hoàng Long'});

    await api.decide(2, 'return', comment: 'Sai', returnStep: 'bo_sung');
    expect(requests.last.method, 'POST');
    expect(body('/__apps/flows/tasks/2/decide'), {'decision': 'return', 'comment': 'Sai', 'return_step': 'bo_sung'});
    await api.decide(2, 'approve');
    expect(body('/__apps/flows/tasks/2/decide'), {'decision': 'approve'});
    await api.submit(1, {'clicked': 'ky'});
    expect(body('/__apps/flows/tasks/1/submit'), {'data': {'clicked': 'ky'}});

    await api.processes(state: 'done,cancelled,skipped', flow: 'linkq', limit: 200);
    final q = requests.last.url;
    expect(q.path, '/__apps/flows/processes');
    expect(q.queryParameters, {'flow': 'linkq', 'state': 'done,cancelled,skipped', 'limit': '200'});
    await api.processReport('linkq', from: 1000, to: 2000, label: 'KLTM');
    expect(requests.last.url.path, '/__apps/flows/defs/linkq/report');
    expect(requests.last.url.queryParameters, {'from': '1000', 'to': '2000', 'label': 'KLTM'});
    await api.processFile('P-1', 'f1');
    expect(requests.last.url.path, '/__apps/flows/processes/P-1/files/f1');
    final p = await api.process('P-8K2Q4M');
    expect(p.note, 'Bị trả lại: thiếu chứng từ');
    expect(p.actions.length, 1, reason: 'mục đã đóng bị bỏ');
  });

  // ------------------------------------------------------------------ thẻ flygo_card
  test('flygo_card_action mang theo reason / value', () {
    final post = MmPost({'id': 'card-1', 'channel_id': 'c', 'user_id': 'bot', 'create_at': 0, 'message': ''});
    expect(flygoCardActionProps(post, {'id': 'duyet:return', 'label': 'Trả lại', 'reason': ' Sai khách ', 'value': 'bo_sung'}), {
      'flygo_card_action': {'post_id': 'card-1', 'id': 'duyet:return', 'label': 'Trả lại', 'reason': 'Sai khách', 'value': 'bo_sung'},
    });
    expect((flygoCardActionProps(post, {'id': 'chon:ky', 'label': 'Ký'})['flygo_card_action'] as Map).keys, ['post_id', 'id', 'label']);
  });

  testWidgets('thẻ tiến trình: nhiều nút xếp tràn dòng, nút open; process_id không có nút open thì có lối mở ở đầu thẻ', (t) async {
    final got = <Map<String, dynamic>>[];
    final card = {
      'v': 1, 'process_id': 'P-8K2Q4M', 'icon': 'task', 'accent': 'orange', 'title': 'Hoá đơn 2154', 'note': 'Xuất hoá đơn nghi trùng?',
      'actions': [
        {'id': 'duyet:approve', 'label': 'Duyệt', 'style': 'primary'},
        {'id': 'duyet:reject', 'label': 'Từ chối', 'input': {'label': 'Lý do từ chối', 'required': true}},
        {'label': 'Xem hd.pdf', 'open': {'process': 'P-8K2Q4M', 'file': 'f1', 'name': 'hd.pdf'}},
        {'label': 'Mở tiến trình', 'open': {'process': 'P-8K2Q4M'}},
      ],
    };
    await pump(t, Scaffold(body: Center(child: FlygoCard(data: FlygoCardData(card), onAction: got.add))));
    for (final x in ['Duyệt', 'Từ chối', 'Xem hd.pdf', 'Mở tiến trình', 'Xuất hoá đơn nghi trùng?']) {
      expect(find.text(x), findsOneWidget, reason: x);
    }
    expect(find.byTooltip('Mở tiến trình'), findsNothing, reason: 'đã có nút open');
    await t.tap(find.text('Xem hd.pdf'));
    expect(got.last['open'], {'process': 'P-8K2Q4M', 'file': 'f1', 'name': 'hd.pdf'});

    await pump(t, Scaffold(body: Center(child: FlygoCard(data: FlygoCardData({...card, 'actions': const []}), onAction: got.add))));
    await t.tap(find.byTooltip('Mở tiến trình'));
    expect(got.last['open'], {'process': 'P-8K2Q4M'});
  });

  testWidgets('hộp thoại input / select: bắt buộc lý do, chọn bước trả về', (t) async {
    Map<String, String>? result;
    await pump(
      t,
      Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => result = await askFlygoCardInput(ctx, {
              'id': 'duyet:return',
              'label': 'Trả lại',
              'input': {'label': 'Lý do trả lại', 'required': true},
              'select': {'label': 'Trả về bước', 'options': [{'id': 'start', 'label': 'Bắt đầu'}, {'id': 'bo_sung', 'label': 'Bổ sung thông tin'}]},
            }),
            child: const Text('mở'),
          ),
        ),
      ),
    );
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    expect(find.text('Trả về bước'), findsOneWidget);
    expect(find.text('Lý do trả lại'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gửi')).onPressed, isNull, reason: 'chưa nhập lý do');
    await t.tap(find.text('Bổ sung thông tin'));
    await t.enterText(find.byType(TextField), 'Sai tên khách');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await t.pumpAndSettle();
    expect(result, {'reason': 'Sai tên khách', 'value': 'bo_sung'});
  });

  testWidgets('open: mở chi tiết tiến trình hoặc tải tệp của tiến trình', (t) async {
    late BuildContext ctx;
    await pump(t, Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    openProcessTarget(ctx, app, {'process': 'P-1', 'file': 'f1', 'name': 'hd.pdf'});
    await t.pump(const Duration(milliseconds: 300));
    expect(requests.map((r) => r.url.path), contains('/__apps/flows/processes/P-1/files/f1'));
    openProcessTarget(ctx, app, {'process': 'P-1'});
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(ProcessDetailPage), findsOneWidget);
    expect(requests.map((r) => r.url.path), contains('/__apps/flows/processes/P-1'));
    await done(t);
  });

  // ------------------------------------------------------------------ Việc của tôi
  testWidgets('việc action: lựa chọn min / max rồi Gửi nộp {values}', (t) async {
    final sent = <Map<String, dynamic>>[];
    await pump(t, Scaffold(body: FlowTaskActionPanel(task: FlowTask.fromJson(choiceTask), onSubmit: (d) async => sent.add(d))));
    expect(find.text('Xử lý hoá đơn nghi trùng'), findsOneWidget);
    await t.tap(find.text('Vẫn xuất'));
    await t.tap(find.text('Huỷ'));
    await t.pump();
    await t.tap(find.text('Gửi lựa chọn'));
    await t.pumpAndSettle();
    expect(sent, [
      {'values': ['xuat', 'huy']},
    ]);
    expect(find.text('Đã gửi lựa chọn'), findsOneWidget);
  });

  testWidgets('Việc của tôi: việc Chờ bấm nút bấm ngay trong danh sách', (t) async {
    await pump(t, FlowsHome(app: app, initialTab: 1, debugPins: const []), size: const Size(430, 1200));
    expect(find.text('Ký'), findsWidgets);
    expect(find.text('Gửi lựa chọn'), findsOneWidget, reason: 'việc Lựa chọn cũng thao tác được ngay');
    expect(find.textContaining('Xuất hoá đơn nghi trùng 2154'), findsOneWidget, reason: 'tiêu đề yêu cầu phê duyệt');
    expect(find.textContaining('Bị trả lại'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Ký').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(body('/__apps/flows/tasks/1/submit'), {'data': {'clicked': 'ky'}});
    await done(t);
  });

  testWidgets('chi tiết đơn: nút của bước chờ, yêu cầu phê duyệt (trả lại chọn bước), việc bị trả lại điền sẵn', (t) async {
    await pump(t, FlowDetailPage(app: app, instanceId: 'i1'));
    expect(requests.map((r) => r.url.path), containsAll(['/__apps/flows/instances/i1', '/__apps/flows/tasks']));
    // Việc action.
    expect(find.text('Ký hoá đơn 2154?'), findsOneWidget);
    expect(find.text('Xem PDF'), findsOneWidget);
    // Yêu cầu phê duyệt.
    expect(find.text('Xuất hoá đơn nghi trùng 2154'), findsOneWidget);
    expect(find.text('Lý do: Trùng số tiền với HĐ 2101'), findsOneWidget);
    // Bị trả lại.
    expect(find.text('Lan trả lại: Sai tên khách'), findsOneWidget);

    // Bấm nút có xác nhận.
    await t.tap(find.widgetWithText(OutlinedButton, 'Không ký'));
    await t.pumpAndSettle();
    expect(find.text('Chắc chắn không ký?'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Không ký').last);
    await t.pump(const Duration(milliseconds: 300));
    expect(body('/__apps/flows/tasks/1/submit'), {'data': {'clicked': 'khong'}});
    await t.pump(const Duration(seconds: 1));

    // Trả lại: chọn bước + lý do.
    await t.tap(find.widgetWithText(TextButton, 'Trả lại'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bổ sung thông tin').last);
    await t.enterText(find.byType(TextField).last, 'Sai tên khách');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await t.pump(const Duration(milliseconds: 300));
    expect(body('/__apps/flows/tasks/2/decide'), {'decision': 'return', 'comment': 'Sai tên khách', 'return_step': 'bo_sung'});
    await t.pump(const Duration(seconds: 1));

    // Từ chối bắt buộc lý do.
    await t.tap(find.widgetWithText(OutlinedButton, 'Từ chối'));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Gửi')).onPressed, isNull);
    await t.enterText(find.byType(TextField).last, 'Không hợp lệ');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await t.pump(const Duration(milliseconds: 300));
    expect(body('/__apps/flows/tasks/2/decide'), {'decision': 'reject', 'comment': 'Không hợp lệ'});
    await t.pump(const Duration(seconds: 1));

    // Việc bị trả lại: form điền sẵn + dòng lý do.
    await t.tap(find.text('Mở để làm'));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(FlowFormPage), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowFormPage), matching: find.text('Lan trả lại: Sai tên khách')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Cty Hoàng Long'), findsOneWidget);
    await done(t);
  });

  // ------------------------------------------------------------------ chi tiết tiến trình
  testWidgets('chi tiết tiến trình: ghi chú và nút đang mở; không có thẻ trong nhóm của mình thì nhắc', (t) async {
    await pump(t, ProcessDetailPage(app: app, processId: 'P-8K2Q4M'));
    expect(find.text('Bị trả lại: thiếu chứng từ'), findsOneWidget);
    expect(find.text('Bước tiếp theo'), findsOneWidget);
    expect(find.text('Xuất hoá đơn nghi trùng 2154: trùng số tiền'), findsOneWidget);
    expect(find.text('Duyệt'), findsOneWidget);
    expect(find.text('Từ chối'), findsOneWidget);
    expect(find.text('Bước chờ đã đóng'), findsNothing);
    // Không cần thẻ trong nhóm của mình: bấm trên trang tiến trình gọi máy chủ áp dụng ngay.
    await t.tap(find.text('Duyệt'));
    await t.pump(const Duration(milliseconds: 300));
    expect(body('/__apps/flows/processes/P-8K2Q4M/act'), {'action': 'duyet:approve'});
    expect(find.text('Đã gửi: Duyệt'), findsOneWidget);
    // Từ chối: hỏi lý do rồi gửi kèm.
    await t.pump(const Duration(seconds: 4));
    await t.tap(find.text('Từ chối'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Sai MST');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await t.pump(const Duration(milliseconds: 300));
    expect(body('/__apps/flows/processes/P-8K2Q4M/act'), {'action': 'duyet:reject', 'text': 'Sai MST'});
    await done(t);
  });
}
