// Việc gắn tiến trình làm ngay trên trang tiến trình (Sếp, 11/11): bước Điền thông tin hiện ô nhập + Gửi tại bước
// hiện tại, không cần mở "Việc của tôi"; nút trùng của bước chờ (ô nhập trên thẻ) không hiện thêm.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/process_detail.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json'});

void main() {
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final now = DateTime.now().millisecondsSinceEpoch;
  var myTasks = <Map<String, dynamic>>[
    {
      'id': 9, 'instance_id': 'i9', 'node': 'nhap', 'kind': 'form', 'title': 'Gửi hoá đơn', 'flow_id': 'f3', 'created_at': now,
      'step_name': 'Nhập email khách', 'node_type': 'form_task',
      'fields': [{'key': 'email', 'label': 'Email khách', 'type': 'text', 'required': true}],
    },
  ];
  Map<String, dynamic> detail() => {
        'id': 'P-AB12CD', 'flow_id': 'F1HDON', 'flow_name': 'Hoá đơn LinkQ', 'name': 'HĐ 1C26AAA-0001', 'state': 'running', 'status_text': 'Gửi email',
        'current_step': 'gui', 'steps': [{'key': 'gui', 'title': 'Gửi email', 'state': 'active'}],
        'stats': [], 'labels': [], 'files': [], 'posts': [], 'events': [], 'created_at': now,
        'actions': [
          {
            'wait': 'i9:nhap', 'node': 'nhap', 'instance_id': 'i9', 'kind': 'form', 'prompt': 'Nhập email khách', 'who': ['me', 'u2'],
            'actions': [{'id': 'nhap:submit', 'label': 'Gửi', 'style': 'primary', 'input': {'label': 'Email khách', 'required': true}}],
          },
        ],
        'my_tasks': myTasks,
      };
  final requests = <http.Request>[];
  setUp(() {
    requests.clear();
    FlowsApi.debugClient = MockClient((r) async {
      requests.add(r);
      if (r.url.path == '/__apps/flows/tasks/9/submit') myTasks = [];
      return switch (r.url.path) {
        '/__apps/flows/processes/P-AB12CD' => _json(detail()),
        _ => _json({'ok': true}),
      };
    });
  });
  tearDown(() => FlowsApi.debugClient = null);

  testWidgets('bước Điền thông tin của mình: nhập email và Gửi ngay trên trang tiến trình', (t) async {
    t.view.physicalSize = const Size(430, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: ProcessDetailPage(app: app, processId: 'P-AB12CD')),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Nhập email khách'), findsWidgets);
    expect(find.widgetWithText(TextField, 'Email khách *'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Gửi'), findsOneWidget, reason: 'ô nhập trên thẻ trùng việc của mình: không hiện thêm');
    // Thiếu email: không gửi.
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await t.pump(const Duration(milliseconds: 300));
    expect(requests.where((r) => r.url.path == '/__apps/flows/tasks/9/submit'), isEmpty);
    await t.enterText(find.widgetWithText(TextField, 'Email khách *'), 'kh@example.com');
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await t.pump(const Duration(milliseconds: 300));
    final sent = requests.lastWhere((r) => r.url.path == '/__apps/flows/tasks/9/submit');
    expect(jsonDecode(sent.body), {'data': {'email': 'kh@example.com'}});
    await t.pump(const Duration(milliseconds: 300));
    // Đã xong: tải lại, hết ô nhập của mình (bước chờ còn trên thẻ của người khác thì hiện như cũ).
    expect(find.widgetWithText(TextField, 'Email khách *'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  });
}
