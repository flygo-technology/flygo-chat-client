import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_card.dart';
import 'package:flygo_chat/ui/flows/flow_form.dart';
import 'package:flygo_chat/ui/flows/flow_logic.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Quy trình (Flows): phần thuần, client API (máy chủ giả), thẻ duyệt trong chat và form sinh từ JSON.
void main() {
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'me', 'first_name': 'Tôi'});
  app.users['me'] = app.me!;
  app.users['nv1'] = MmUser({'id': 'nv1', 'username': 'lan', 'first_name': 'Lan'});

  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: child))),
      );

  group('phần thuần', () {
    test('số tiền', () {
      expect(vnNumber(35000000), '35.000.000');
      expect(vnNumber(-1234), '-1.234');
      expect(vnNumber(999), '999');
      expect(parseMoney('35.000.000'), 35000000);
      expect(parseMoney('35,000,000 đ'), 35000000);
      expect(parseMoney('ba mươi'), isNull);
      expect(parseMoney(''), isNull);
    });

    test('kiểm form giống máy chủ', () {
      const fields = [
        FlowField(key: 'so_tien', label: 'Số tiền', type: 'money', required: true),
        FlowField(key: 'loai', label: 'Loại', type: 'select', options: ['A', 'B']),
        FlowField(key: 'hd', label: 'Hoá đơn', type: 'files', required: true),
        FlowField(key: 'ngay', label: 'Ngày', type: 'date'),
      ];
      expect(validateFlowForm(fields, {'so_tien': 35000000, 'hd': [{'id': 'f1', 'name': 'a.pdf'}], 'loai': 'A', 'ngay': '2026-11-05'}), isEmpty);
      final e = validateFlowForm(fields, {'so_tien': 'abc', 'hd': [], 'loai': 'C', 'ngay': '5/11'});
      expect(e.keys.toSet(), {'so_tien', 'hd', 'loai', 'ngay'});
    });

    test('hiện giá trị', () {
      expect(showFieldValue(const FlowField(key: 'x', label: 'x', type: 'money'), 2500000), '2.500.000 đ');
      expect(showFieldValue(const FlowField(key: 'x', label: 'x', type: 'date'), '2026-11-20'), '20/11/2026');
      expect(showFieldValue(const FlowField(key: 'x', label: 'x', type: 'files'), [1, 2]), '2 tệp');
    });

    test('nhật ký dễ đọc', () {
      String name(String id) => id == 'tp1' ? 'Anh Tuấn' : id;
      String step(String id) => id == 'tp' ? 'Trưởng phòng duyệt' : id;
      expect(flowEventText({'kind': 'decided', 'node': 'tp', 'data': {'by': 'tp1', 'decision': 'approve'}}, name, step), 'Anh Tuấn đã duyệt: Trưởng phòng duyệt');
      expect(flowEventText({'kind': 'decided', 'node': 'tp', 'data': {'by': 'tp1', 'decision': 'reject', 'comment': 'sai NCC'}}, name, step),
          'Anh Tuấn đã từ chối: Trưởng phòng duyệt · “sai NCC”');
      expect(flowEventText({'kind': 'enter', 'node': 'tp', 'data': {'type': 'approval'}}, name, step), 'Chờ duyệt: Trưởng phòng duyệt');
      expect(flowEventText({'kind': 'enter', 'node': 'chk', 'data': {'type': 'condition'}}, name, step), isNull);
      expect(flowEventText({'kind': 'input:decide', 'data': {}}, name, step), isNull);
    });

    test('ô nhập tiền tự thêm dấu chấm', () {
      final f = MoneyInputFormatter();
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '3500000')).text, '3.500.000');
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '3.500.0001')).text, '35.000.001');
      expect(f.formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: 'abc')).text, '');
    });
  });

  group('FlowsApi', () {
    test('máy chủ chưa có /__apps/flows (404 không phải lỗi Flows): gọi qua trạm đẩy như cũ, lỗi của Flows thì không', () async {
      FlowsApi.debugResetLegacy();
      addTearDown(FlowsApi.debugResetLegacy);
      final seen = <String>[];
      final api = FlowsApi('tok-me', client: MockClient((r) async {
        seen.add(r.url.toString());
        if (r.url.path.startsWith('/__apps/')) return http.Response('404 page not found', 404);
        if (r.url.path == '/flows/instances/x') return http.Response.bytes(utf8.encode(jsonEncode({'error': 'không có đơn này'})), 404);
        return http.Response('{"flows":[]}', 200);
      }));
      expect(await api.defs(), isEmpty);
      expect(seen, ['https://chat.test/__apps/flows/defs', 'https://push.chat.test/flows/defs']);
      await api.defs();
      expect(seen.last, 'https://push.chat.test/flows/defs', reason: 'nhớ, không thử lại đường mới mỗi lần');
    });

    test('gửi token, máy chủ, thân lệnh duyệt; đọc lỗi kèm issues', () async {
      late http.Request seen;
      final api = FlowsApi('tok-me', client: MockClient((r) async {
        seen = r;
        if (r.url.path == '/__apps/flows/defs') {
          return http.Response.bytes(utf8.encode(jsonEncode({'error': 'flow còn lỗi', 'issues': [{'code': 'expr', 'msg': 'sai'}]})), 422);
        }
        return http.Response('{"ok":true}', 200);
      }));
      await api.decide(7, 'reject', comment: 'thiếu báo giá');
      expect(seen.url.toString(), 'https://chat.test/__apps/flows/tasks/7/decide', reason: 'chuẩn mới: <máy chủ chat>/__apps/flows');
      expect(seen.headers['Authorization'], 'Bearer tok-me');
      expect(seen.headers['X-MM-Server'], 'https://chat.test');
      expect(jsonDecode(seen.body), {'decision': 'reject', 'comment': 'thiếu báo giá'});
      await api.decide(8, 'approve');
      expect(jsonDecode(seen.body), {'decision': 'approve'});
      try {
        await api.defs();
        fail('phải lỗi');
      } on FlowsException catch (e) {
        expect(e.status, 422);
        expect(e.message, 'flow còn lỗi');
        expect(e.issues.single['code'], 'expr');
      }
    });
  });

  group('thẻ trong chat', () {
    MmPost post(Map<String, dynamic> flow) => MmPost({'id': 'p1', 'channel_id': 'c1', 'user_id': 'bot', 'message': 'x', 'create_at': 0, 'props': {'flygo_flow': flow}});
    final request = {
      'v': 1, 'kind': 'approval_request', 'instance_id': 'i1', 'task_id': 42, 'flow_id': 'de-xuat', 'flow_name': 'Đề xuất thanh toán', 'icon': '💸',
      'title': 'Mua cáp thang máy', 'requester': 'nv1', 'summary': [['Số tiền', '35.000.000 đ'], ['Nhà cung cấp', 'Cty ABC']],
      'ai_note': {'level': 'warn', 'text': 'Lệch 2.000.000 đ so với hoá đơn'}, 'step': 'Trưởng phòng duyệt', 'actions': ['approve', 'reject', 'return'], 'state': 'open',
    };

    testWidgets('thẻ duyệt: nội dung, ghi chú AI, nút; bấm Duyệt gọi API và chuyển sang "đã duyệt"', (t) async {
      final calls = <String>[];
      FlowsApi.debugClient = MockClient((r) async {
        calls.add('${r.method} ${r.url.path} ${r.body}');
        return http.Response('{"ok":true}', 200);
      });
      addTearDown(() => FlowsApi.debugClient = null);
      final p = post(request);
      await t.pumpWidget(wrap(FlowPostCard(app: app, post: p, width: 340)));
      expect(find.text('Cần bạn duyệt'), findsOneWidget);
      expect(find.text('Mua cáp thang máy'), findsOneWidget);
      expect(find.text('Người đề xuất: Lan'), findsOneWidget);
      expect(find.text('35.000.000 đ'), findsOneWidget);
      expect(find.textContaining('Lệch 2.000.000'), findsOneWidget);
      expect(find.text('Duyệt'), findsOneWidget);
      expect(find.text('Từ chối'), findsOneWidget);
      expect(find.text('Trả lại'), findsOneWidget);
      await t.tap(find.text('Duyệt'));
      await t.pumpAndSettle();
      expect(calls, ['POST /__apps/flows/tasks/42/decide {"decision":"approve"}']);
      expect(find.text('Đã duyệt'), findsWidgets);
      expect(find.text('Từ chối'), findsNothing);
    });

    testWidgets('từ chối phải ghi lý do', (t) async {
      final calls = <String>[];
      FlowsApi.debugClient = MockClient((r) async {
        calls.add(r.body);
        return http.Response('{"ok":true}', 200);
      });
      addTearDown(() => FlowsApi.debugClient = null);
      await t.pumpWidget(wrap(FlowPostCard(app: app, post: post(request), width: 340)));
      await t.tap(find.text('Từ chối'));
      await t.pumpAndSettle();
      expect(find.text('Từ chối đơn'), findsOneWidget);
      // Chưa nhập lý do: nút Gửi tắt.
      final send = find.widgetWithText(FilledButton, 'Gửi');
      expect(t.widget<FilledButton>(send).onPressed, isNull);
      await t.enterText(find.byType(TextField), 'Sai nhà cung cấp');
      await t.pump();
      await t.tap(send);
      await t.pumpAndSettle();
      expect(calls.single, '{"decision":"reject","comment":"Sai nhà cung cấp"}');
    });

    testWidgets('thẻ đã quyết và thẻ trạng thái không có nút', (t) async {
      await t.pumpWidget(wrap(FlowPostCard(
          app: app, post: post({...request, 'kind': 'decided', 'state': 'decided', 'actions': [], 'decided': {'by': 'me', 'decision': 'approve'}}), width: 340)));
      expect(find.text('Đã duyệt'), findsOneWidget);
      expect(find.text('Từ chối'), findsNothing);
      await t.pumpWidget(wrap(FlowPostCard(app: app, post: post({...request, 'kind': 'progress', 'state': 'open', 'actions': [], 'requester': 'me', 'waiting_for': ['nv1']}), width: 340)));
      expect(find.text('Đơn của bạn'), findsOneWidget);
      expect(find.text('Trưởng phòng duyệt · chờ Lan'), findsOneWidget);
      expect(find.text('Duyệt'), findsNothing);
    });
  });

  testWidgets('form sinh từ JSON: báo thiếu, định dạng tiền, gửi số', (t) async {
    Map<String, dynamic>? sent;
    final api = FlowsApi('tok-me', client: MockClient((_) async => http.Response('{}', 200)));
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(c).push(MaterialPageRoute(
                  builder: (_) => FlowFormPage(
                    app: app,
                    api: api,
                    title: 'Đề xuất thanh toán',
                    askTitle: true,
                    fields: const [
                      FlowField(key: 'so_tien', label: 'Số tiền', type: 'money', required: true),
                      FlowField(key: 'ncc', label: 'Nhà cung cấp', type: 'text', required: true),
                      FlowField(key: 'loai', label: 'Loại chi', type: 'select', options: ['Mua vật tư', 'Dịch vụ']),
                    ],
                    onSubmit: (data, title) async => sent = {...data, '_title': title},
                  ),
                )),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    await t.tap(find.text('Gửi'));
    await t.pump();
    expect(find.text('Chưa nhập'), findsNWidgets(2));
    expect(sent, isNull);
    await t.enterText(find.widgetWithText(TextField, 'Số tiền *'), '35000000');
    await t.enterText(find.widgetWithText(TextField, 'Nhà cung cấp *'), 'Cty ABC');
    await t.pump();
    expect(find.text('35.000.000'), findsOneWidget);
    await t.tap(find.text('Gửi'));
    await t.pumpAndSettle();
    expect(sent, {'so_tien': 35000000, 'ncc': 'Cty ABC', '_title': ''});
  });
}
