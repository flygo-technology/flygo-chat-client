// Danh sách tiến trình phân trang (Sếp 11/11: tránh quá tải): một trang 50 dòng, cuộn tới cuối thì tải trang sau theo
// mốc `next`; nhãn chỉ cho cảnh báo (lỗi đỏ, cam không trùng tên bước).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_card.dart' show kFlowOrange, kFlowRed;
import 'package:flygo_chat/ui/flows/process_list.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json'});

void main() {
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final now = DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> proc(int i, {String status = '', String tone = 'blue', String state = 'running'}) => {
        'id': 'P-$i', 'flow_id': 'f', 'flow_name': 'Hoá đơn', 'name': 'HĐ $i', 'state': state, 'current_step': 'ky', 'status_text': status, 'tone': tone,
        'steps': [{'key': 'tao', 'title': 'Tạo nháp', 'state': 'done'}, {'key': 'ky', 'title': 'Chờ ký', 'state': state == 'failed' ? 'failed' : 'active'}],
        'stats': [], 'labels': [], 'created_at': now, 'updated_at': now - i,
      };
  final requests = <Uri>[];
  setUp(() {
    requests.clear();
    FlowsApi.debugClient = MockClient((r) async {
      requests.add(r.url);
      if (r.url.path != '/__apps/flows/processes') return _json({'ok': true});
      if (r.url.queryParameters['state'] == 'failed') return _json({'processes': [], 'next': null});
      final before = r.url.queryParameters['before'];
      if (before == null) {
        return _json({
          'processes': [
            proc(0, status: 'Thiếu email', tone: 'orange'),
            proc(1, status: 'Đã tạo nháp, chờ kế toán ký'),
            proc(2, status: 'Chờ ký', tone: 'orange'),
            proc(3, status: 'Không lấy được XML', tone: 'red', state: 'failed'),
            // Dữ liệu cũ: nhãn lỗi còn sót màu xanh sau khi chạy tiếp (dữ liệu cũ trước bản sửa).
            proc(4, status: 'Lỗi ở bước Nhận chứng từ'),
            for (var i = 5; i < 12; i++) proc(i),
          ],
          'next': 'm1',
        });
      }
      return _json({'processes': [for (var i = 12; i < 15; i++) proc(i)], 'next': null});
    });
  });
  tearDown(() => FlowsApi.debugClient = null);

  testWidgets('trang một quy trình: không lặp tên quy trình dưới tên tiến trình, ngày ở cuối dòng bước', (t) async {
    t.view.physicalSize = const Size(430, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    Future<void> show(String? flowId) async {
      await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: ProcessesView(key: ValueKey(flowId), app: app, flowId: flowId))),
      ));
      await t.pump(const Duration(milliseconds: 300));
    }

    await show('f');
    expect(find.textContaining('Hoá đơn ·'), findsNothing);
    expect(find.text('Hôm nay'), findsWidgets);
    await show(null);
    expect(find.textContaining('Hoá đơn · Hôm nay'), findsWidgets, reason: 'danh sách nhiều quy trình vẫn ghi tên quy trình');
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  });

  testWidgets('trang đầu 50 dòng, cuộn tới cuối tải trang sau; nhãn chỉ cảnh báo', (t) async {
    t.view.physicalSize = const Size(430, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: ProcessesView(app: app, defs: const [], stateSelect: true))),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final first = requests.firstWhere((u) => u.path == '/__apps/flows/processes' && u.queryParameters['state'] == 'running');
    expect(first.queryParameters['limit'], '50');
    expect(find.text('Thiếu email'), findsOneWidget, reason: 'cảnh báo cam');
    expect(find.text('Đã tạo nháp, chờ kế toán ký'), findsNothing, reason: 'trạng thái thường không hiện');
    expect(find.text('Chờ ký'), findsNothing, reason: 'cam nhưng trùng tên bước');
    expect(find.text('Không lấy được XML'), findsOneWidget, reason: 'lỗi');
    Color chip(String text) => t.widget<ProcessChip>(find.ancestor(of: find.text(text), matching: find.byType(ProcessChip))).color;
    expect(chip('Không lấy được XML'), kFlowRed);
    expect(chip('Lỗi ở bước Nhận chứng từ'), kFlowRed, reason: 'chữ báo lỗi luôn đỏ');
    expect(chip('Thiếu email'), kFlowOrange);
    expect(find.text('1/2'), findsWidgets);
    await t.scrollUntilVisible(find.text('HĐ 11'), 300, scrollable: find.byType(Scrollable).last);
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(requests.where((u) => u.queryParameters['before'] == 'm1'), isNotEmpty, reason: 'tải trang sau theo mốc next');
    await t.scrollUntilVisible(find.text('HĐ 14'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('HĐ 14'), findsOneWidget);
    expect(find.byKey(const ValueKey('process-more')), findsNothing, reason: 'hết trang');
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
  });
}
