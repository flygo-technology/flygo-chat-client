import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_form.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'me', 'first_name': 'Tôi'});

  testWidgets('chọn từ danh mục rồi gửi: giá trị đã chọn không bị ô chữ trống ghi đè', (t) async {
    final api = FlowsApi('tok-me', client: MockClient((r) async => http.Response(
        jsonEncode({
          'items': [
            {'value': '52552628', 'label': '52552628', 'sub': 'VND', 'data': {'currency': 'VND'}},
            {'value': '11862628', 'label': '11862628', 'sub': 'USD', 'data': {'currency': 'USD'}},
          ]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'})));
    final fields = FlowField.listOf([
      {
        'key': 'tk',
        'label': 'Tài khoản',
        'type': 'text',
        'required': true,
        'lookup': {'server': 'acb', 'tool': 'acb-list-accounts', 'value': 'full_number', 'label': 'full_number', 'fill': {'tien_te': 'currency'}},
      },
      {'key': 'tien_te', 'label': 'Loại tiền', 'type': 'text'},
    ]);
    Map<String, dynamic>? sent;
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
                    builder: (_) => FlowFormPage(
                        app: app, api: api, title: 'Tải chứng từ', fields: fields, flowId: 'S9MTF4', submitLabel: 'Tạo tiến trình mới', onSubmit: (d, _) async => sent = d))),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextField, 'Tài khoản *'));
    await t.enterText(find.widgetWithText(TextField, 'Tài khoản *'), '1186');
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    await t.tap(find.text('11862628').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Tạo tiến trình mới'));
    await t.pumpAndSettle();
    expect(find.text('Chưa nhập'), findsNothing);
    expect(sent, {'tk': '11862628', 'tien_te': 'USD'});
  });
}
