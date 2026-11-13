import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/flows/flow_trace.dart';
import 'package:flygo_chat/ui/flows/flows_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  final out = Platform.environment['EDITOR_OUT'];
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final def = jsonDecode(File('test/fixtures/flows/tai-chung-tu-ngan-hang.json').readAsStringSync()) as Map<String, dynamic>;
  final t0 = DateTime(2026, 11, 6, 22, 8, 6).millisecondsSinceEpoch;
  Map<String, dynamic> step(String status, int startS, [int? endS, Object? output]) =>
      {'status': status, 'token': 1, 'started_at': t0 + startS * 1000, if (endS != null) 'ended_at': t0 + endS * 1000, 'output': output};
  final steps = {
    's': step('done', 0, 0),
    'chuan_bi': step('done', 0, 0, {'server': 'acb', 'so_tk': '52552628'}),
    'td_1': step('done', 0, 0),
    'dem': step('done', 0, 5, {'total': 137, 'credit_count': 76}),
    'kt_dem': step('done', 5, 5),
    'td_2': step('done', 5, 5),
    'tai': step('done', 5, 7, {'job_id': '231c', 'status': 'queued'}),
    'kt_tai': step('done', 7, 7),
    'cho': step('active', 7),
  };
  final inst = {
    'id': 'i1', 'flow_id': 'S9MTF4', 'flow_version': 5, 'title': 'Thử thôi', 'status': 'running', 'requester': 'me', 'created_at': t0, 'updated_at': t0,
    'form': {'ngan_hang': 'ACB', 'tk_acb': '52552628', 'tien_te': 'VND', 'loai': 'Báo Có', 'thang': '10', 'nam': 'Năm nay'},
    'steps': steps,
    'waiting': [{'id': 9, 'node': 'cho'}],
    'progress': {'percent': 28.0, 'label': 'Đã tải 22/76 giấy báo', 'step': 'cho'},
    'def': def, 'events': [{'kind': 'started', 'by': 'me', 'at': t0}], 'my_tasks': [],
  };

  test('bước sắp tới đi theo đường chính, không đi nhánh lỗi', () {
    expect(flowUpcoming(def, steps, [{'node': 'cho'}]), ['kt_xong', 'gui', 'td_xong', 'e_ok']);
    expect(flowUpcoming(def, const {}, [{'node': 's'}]).take(4), ['chuan_bi', 'td_1', 'dem', 'kt_dem']);
  });

  test('diễn biến: bước tự động đã chạy, bước đang chạy, rồi bước sắp tới (mờ)', () {
    final lines = flowTimeline(inst, [('Đã nộp đơn', t0)], (id) => '${(def['nodes'] as List).firstWhere((n) => n['id'] == id)['name']}');
    expect([for (final l in lines) '${l.kind}:${l.text}'], [
      'event:Đã nộp đơn',
      'done:Chuẩn bị tham số',
      'done:Đếm giao dịch trong tháng',
      'done:Yêu cầu tải giấy báo cả tháng',
      'active:Chờ ngân hàng tải xong',
      'next:Gửi tệp cho người chạy quy trình',
      'next:Hoàn tất',
    ]);
  });

  testWidgets('trang chi tiết: diễn biến, bước sắp tới, gỡ lỗi', (tester) async {
    if (out != null) await tester.runAsync(_fonts);
    FlowsApi.debugClient = MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode(inst)), 200, headers: {'content-type': 'application/json'}));
    tester.view.physicalSize = const Size(760, 1180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.dark), home: FlowDetailPage(app: app, instanceId: 'i1')),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Gỡ lỗi'), findsOneWidget);
    await tester.tap(find.text('Gỡ lỗi'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Chờ ngân hàng tải xong'), findsWidgets);
    expect(find.textContaining('(S9MTF4-'), findsNothing, reason: 'không hiện mã bước sau tên bước');
    if (out != null) {
      await tester.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/flow-dien-bien.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    // Đơn đang chạy thì trang tự tải lại: dừng hẳn trước khi kết thúc test.
    await tester.pumpWidget(const SizedBox.shrink());
    FlowsApi.debugClient = null;
  });
}
