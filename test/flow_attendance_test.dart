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
import 'package:flygo_chat/ui/flows/flow_form.dart';
import 'package:flygo_chat/ui/flows/flow_location.dart';
import 'package:flygo_chat/ui/flows/flow_logic.dart';
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
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'cn1', 'first_name': 'Công nhân A'});
  final at = DateTime(2026, 11, 7, 8, 7).millisecondsSinceEpoch;

  test('giá trị vị trí / Wi-Fi / ảnh hiện dễ đọc', () {
    final loc = FlowField.listOf([{'key': 'vt', 'label': 'Vị trí', 'type': 'location'}]).first;
    final wifi = FlowField.listOf([{'key': 'w', 'label': 'Wi-Fi', 'type': 'wifi'}]).first;
    final photo = FlowField.listOf([{'key': 'a', 'label': 'Ảnh', 'type': 'photo'}]).first;
    expect(showFieldValue(loc, {'lat': 21.029, 'lon': 105.8542, 'accuracy': 8.4, 'at': at}), '21.029000, 105.854200 (±8 m) · 08:07');
    expect(showFieldValue(wifi, {'ssid': 'XUONG-01', 'bssid': 'aa:bb:cc:dd:ee:01', 'at': at}), 'XUONG-01 (aa:bb:cc:dd:ee:01) · 08:07');
    expect(showFieldValue(wifi, {'ssid': null, 'bssid': 'aa:bb'}), '(aa:bb)');
    expect(showFieldValue(photo, [{'id': 'f1'}, {'id': 'f2'}]), '2 ảnh');
    expect(showFieldValue(loc, {'lat': 'x'}), '');
  });

  testWidgets('trang chi tiết hiện thông tin nhập ở bước Vào ca', (tester) async {
    if (out != null) await tester.runAsync(_fonts);
    final def = {
      'id': 'vao-ca', 'name': 'Vào ca', 'icon': '⏰', 'form': [{'key': 'ca', 'label': 'Ca', 'type': 'text'}],
      'nodes': [
        {'id': 'start', 'type': 'start'},
        {'id': 'vc', 'type': 'form_task', 'name': 'Vào ca', 'assignee': '\$requester', 'fields': [
          {'key': 'vi_tri', 'label': 'Vị trí', 'type': 'location'},
          {'key': 'wifi', 'label': 'Wi-Fi', 'type': 'wifi'},
          {'key': 'anh', 'label': 'Ảnh chụp', 'type': 'photo'}]},
        {'id': 'kt', 'type': 'calc', 'name': 'Kiểm tra', 'vars': [{'name': 'cach_m', 'label': 'Cách xưởng (m)', 'op': 'distance_m'}, {'name': 'muon', 'label': 'Muộn (phút)', 'op': 'minutes_between'}, {'name': 'tam', 'op': 'now'}]},
        {'id': 'end', 'type': 'end'},
      ],
      'edges': [['start', 'vc'], ['vc', 'kt'], ['kt', 'end']],
    };
    final inst = {
      'id': 'i1', 'flow_id': 'vao-ca', 'flow_version': 1, 'title': 'Vào ca sáng', 'status': 'done', 'requester': 'me', 'created_at': at, 'updated_at': at,
      'form': {'ca': 'sáng'},
      'steps': {
        'vc': {'status': 'done', 'token': 1, 'started_at': at - 60000, 'ended_at': at, 'output': {
          'vi_tri': {'lat': 21.029, 'lon': 105.8542, 'accuracy': 8, 'at': at},
          'wifi': {'ssid': 'XUONG-01', 'bssid': 'aa:bb:cc:dd:ee:01', 'at': at},
          'anh': [{'id': 'f1', 'name': 'anh.jpg'}], 'by': 'me'}},
        'kt': {'status': 'done', 'token': 1, 'started_at': at, 'ended_at': at, 'output': {'cach_m': 56, 'muon': 7, 'tam': 1}},
      },
      'waiting': [], 'def': def, 'events': [{'kind': 'started', 'by': 'me', 'at': at - 60000}], 'my_tasks': [],
    };
    FlowsApi.debugClient = MockClient((r) async => r.url.path.contains('/files/')
        ? http.Response.bytes(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='), 200)
        : http.Response.bytes(utf8.encode(jsonEncode(inst)), 200, headers: {'content-type': 'application/json'}));
    tester.view.physicalSize = const Size(560, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.dark), home: FlowDetailPage(app: app, instanceId: 'i1'))),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FlowLocationView), findsOneWidget, reason: 'vị trí hiện bằng ô bản đồ');
    expect(find.text('21.029000, 105.854200'), findsOneWidget);
    expect(find.textContaining('XUONG-01 (aa:bb:cc:dd:ee:01)'), findsOneWidget);
    expect(find.text('Ảnh chụp'), findsOneWidget);
    expect(find.text('Muộn (phút)'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('tam'), findsNothing, reason: 'biến không đặt tên hiển thị thì không hiện');
    if (out != null) {
      await tester.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/cham-cong-chi-tiet.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    FlowsApi.debugClient = null;
  });

  testWidgets('chấm công một chạm: không có ô nhập, lỗi thì nêu lý do và Thử lại', (tester) async {
    final fields = FlowField.listOf([
      {'key': 'vi_tri', 'label': 'Vị trí', 'type': 'location', 'required': true},
      {'key': 'wifi', 'label': 'Wi-Fi', 'type': 'wifi'},
    ]);
    var sent = 0;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: FlowFormPage(app: app, api: FlowsApi('tok-me'), title: 'Chấm công ngày', fields: fields, flowId: 'PMBVF5', askTitle: true, onSubmit: (_, _) async => sent++),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    // Không có ô nhập nào (kể cả tiêu đề); test không có GPS nên báo chưa gửi được và cho thử lại.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(FlowLocationView), findsOneWidget);
    for (var i = 0; i < 10 && find.text('Chưa gửi được').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Chưa gửi được'), findsOneWidget);
    expect(find.text('Thử lại'), findsWidgets);
    expect(sent, 0, reason: 'thiếu vị trí bắt buộc thì không gửi');
  });

  testWidgets('ô vị trí: bản đồ + toạ độ + độ chính xác + giờ lấy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: FlowLocationView(label: 'Vị trí', value: {'lat': 21.029, 'lon': 105.8542, 'accuracy': 8, 'at': at})),
    ));
    await tester.pump();
    expect(find.text('Đã lấy vị trí'), findsOneWidget);
    expect(find.text('21.029000, 105.854200'), findsOneWidget);
    expect(find.textContaining('±8 m'), findsOneWidget);
  });
}
