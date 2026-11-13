// Ảnh xem trước Quy trình (Flows) (chạy tay): FLOWS_OUT=<thư mục> flutter test test/flows_preview_test.dart
// Cần phông Roboto + MaterialIcons trong bộ nhớ đệm của Flutter (bin/cache/artifacts/material_fonts).
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
import 'package:flygo_chat/ui/flows/flow_card.dart';
import 'package:flygo_chat/ui/flows/flow_form.dart';
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

const _now = 1793840400000; // 05/11/2026 08:00

final _form = [
  {'key': 'loai', 'label': 'Loại chi', 'type': 'select', 'options': ['Mua vật tư', 'Dịch vụ', 'Khác'], 'required': true},
  {'key': 'so_tien', 'label': 'Số tiền', 'type': 'money', 'required': true},
  {'key': 'nha_cung_cap', 'label': 'Nhà cung cấp', 'type': 'text', 'required': true},
  {'key': 'hoa_don', 'label': 'Hoá đơn / chứng từ', 'type': 'files', 'required': true},
  {'key': 'ghi_chu', 'label': 'Ghi chú', 'type': 'textarea'},
];

final _def = {
  'id': 'de-xuat-thanh-toan', 'name': 'Đề xuất thanh toán', 'icon': '💸', 'form': _form,
  'nodes': [
    {'id': 'start', 'type': 'start'},
    {'id': 'ai_kiem', 'type': 'ai', 'name': 'AI kiểm chứng từ'},
    {'id': 'tp', 'type': 'approval', 'name': 'Trưởng phòng duyệt'},
    {'id': 'gd', 'type': 'approval', 'name': 'Giám đốc duyệt'},
    {'id': 'ktt', 'type': 'approval', 'name': 'Kế toán trưởng xác nhận'},
  ],
};

Map<String, dynamic> _ev(String kind, int minutes, {String? node, Map<String, dynamic> data = const {}, String? actor}) =>
    {'kind': kind, 'at': _now + minutes * 60000, 'node': node, 'actor': actor, 'data': data};

final _instance = {
  'id': 'i1', 'flow_id': 'de-xuat-thanh-toan', 'title': 'Mua cáp tải thang máy cho công trình Vinhomes', 'status': 'running', 'requester': 'u2',
  'form': {
    'loai': 'Mua vật tư', 'so_tien': 35000000, 'nha_cung_cap': 'Cty TNHH Cáp Thép Hà Nội',
    'hoa_don': [{'id': 'f1', 'name': 'HD-0001523.pdf'}, {'id': 'f2', 'name': 'bao-gia-cap-thep.xlsx'}],
    'ghi_chu': 'Cần gấp trước 10/11 để kịp lắp đặt.',
  },
  'def': _def,
  'events': [
    _ev('started', 0),
    _ev('enter', 0, node: 'ai_kiem', data: {'type': 'ai'}),
    _ev('job_done', 2, node: 'ai_kiem'),
    _ev('enter', 2, node: 'tp', data: {'type': 'approval'}),
    _ev('decided', 45, node: 'tp', data: {'by': 'u3', 'decision': 'approve'}),
    _ev('enter', 45, node: 'gd', data: {'type': 'approval'}),
  ],
  'my_tasks': [
    {'id': 12, 'instance_id': 'i1', 'node': 'gd', 'kind': 'approval', 'title': 'Mua cáp tải thang máy cho công trình Vinhomes', 'flow_id': 'de-xuat-thanh-toan', 'created_at': _now},
  ],
};

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json'});

void main() {
  final out = Platform.environment['FLOWS_OUT'];
  kServerUrl = 'https://chat.flygo.vn';
  final app = AppState('test')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  for (final (id, n) in [('me', 'Ba'), ('u2', 'Lan Kế toán'), ('u3', 'Tuấn Trưởng phòng')]) {
    app.users[id] = MmUser({'id': id, 'username': n.toLowerCase(), 'first_name': n});
  }

  FlowsApi.debugClient = MockClient((r) async => switch (r.url.path) {
        '/__apps/flows/tasks' => _json({'tasks': [
            {'id': 12, 'instance_id': 'i1', 'node': 'gd', 'kind': 'approval', 'title': 'Mua cáp tải thang máy cho công trình Vinhomes', 'flow_id': 'de-xuat-thanh-toan', 'due_at': _now + 86400000 * 400, 'created_at': _now},
            {'id': 13, 'instance_id': 'i2', 'node': 'chi', 'kind': 'form', 'title': 'Tạm ứng công tác Đà Nẵng', 'flow_id': 'tam-ung', 'created_at': _now},
          ]}),
        '/__apps/flows/instances' => _json({'instances': [
            {'id': 'i3', 'title': 'Mua 5 bộ biến tần', 'status': 'running', 'updated_at': _now},
            {'id': 'i4', 'title': 'Tạm ứng đi công trình Hải Phòng', 'status': 'done', 'updated_at': _now - 86400000},
            {'id': 'i5', 'title': 'Thanh toán dịch vụ vận chuyển', 'status': 'returned', 'updated_at': _now - 2 * 86400000},
            {'id': 'i6', 'title': 'Mua văn phòng phẩm', 'status': 'rejected', 'updated_at': _now - 5 * 86400000},
          ]}),
        '/__apps/flows/defs' => _json({'flows': [
            {'id': 'de-xuat-thanh-toan', 'name': 'Đề xuất thanh toán', 'icon': '💸', 'form': _form},
            {'id': 'tam-ung', 'name': 'Tạm ứng', 'icon': '💵', 'form': []},
            {'id': 'mua-hang', 'name': 'Đề xuất mua hàng', 'icon': '🛒', 'form': []},
            {'id': 'nghi-phep', 'name': 'Xin nghỉ phép', 'icon': '🌴', 'form': []},
          ]}),
        _ => _json(_instance),
      });

  Future<void> shot(WidgetTester tester, String name, Size size, Brightness b, Widget child, {Future<void> Function()? before}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: RepaintBoundary(key: key, child: child)),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    if (before != null) await before();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }

  MmPost post(Map<String, dynamic> f) => MmPost({'id': 'p${f.hashCode}', 'channel_id': 'c1', 'user_id': 'bot', 'message': 'x', 'create_at': _now, 'update_at': _now, 'props': {'flygo_flow': f}});
  final request = {
    'v': 1, 'kind': 'approval_request', 'instance_id': 'i1', 'task_id': 12, 'flow_id': 'de-xuat-thanh-toan', 'flow_name': 'Đề xuất thanh toán', 'icon': '💸',
    'title': 'Mua cáp tải thang máy cho công trình Vinhomes', 'requester': 'u2',
    'summary': [['Loại chi', 'Mua vật tư'], ['Số tiền', '35.000.000 đ'], ['Nhà cung cấp', 'Cty TNHH Cáp Thép Hà Nội']],
    'ai_note': {'level': 'ok', 'text': 'Hoá đơn khớp số tiền, MST hợp lệ, không trùng hoá đơn cũ.'},
    'step': 'Giám đốc duyệt', 'actions': ['approve', 'reject', 'return'], 'state': 'open',
  };
  Widget cards(Brightness b) => Builder(
        builder: (c) => Scaffold(
          backgroundColor: Pal.of(c).chatBg,
          appBar: AppBar(title: const Text('Flow Bot')),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            for (final f in [
              request,
              {...request, 'kind': 'approval_request', 'ai_note': {'level': 'warn', 'text': 'Hoá đơn 33.000.000 đ, lệch 2.000.000 đ so với đề xuất.'}, 'title': 'Thanh toán dịch vụ vận chuyển', 'summary': [['Số tiền', '35.000.000 đ']]},
              {...request, 'kind': 'decided', 'state': 'decided', 'actions': [], 'decided': {'by': 'me', 'decision': 'approve'}, 'ai_note': null},
              {...request, 'kind': 'progress', 'state': 'open', 'actions': [], 'requester': 'me', 'step': 'Kế toán trưởng xác nhận', 'waiting_for': ['u2'], 'ai_note': null},
              {...request, 'kind': 'returned', 'state': 'open', 'actions': ['resubmit'], 'requester': 'me', 'step': 'Trưởng phòng duyệt', 'ai_note': null, 'decided': {'by': 'u3', 'decision': 'return', 'comment': 'Thiếu báo giá thứ hai'}},
            ])
              Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 10), child: FlowPostCard(app: app, post: post(f), width: 360))),
          ]),
        ),
      );

  testWidgets('ảnh xem trước Quy trình', (tester) async {
    if (out == null) return;
    await tester.runAsync(_fonts);
    for (final b in Brightness.values) {
      await shot(tester, 'flows-cards-${b.name}', const Size(400, 1580), b, cards(b));
    }
    for (final (i, tab) in ['dang-chay', 'cho-duyet'].indexed) {
      await shot(tester, 'flows-home-$tab', const Size(400, 720), Brightness.light, FlowsHome(app: app), before: () async {
        await tester.pump(const Duration(milliseconds: 200));
        if (i > 0) {
          await tester.tap(find.byType(Tab).at(i));
          await tester.pump(const Duration(milliseconds: 600));
        }
      });
    }
    await shot(tester, 'flows-detail', const Size(400, 1100), Brightness.light, FlowDetailPage(app: app, instanceId: 'i1'),
        before: () => tester.pump(const Duration(milliseconds: 200)));
    await shot(tester, 'flows-form', const Size(400, 900), Brightness.light,
        FlowFormPage(
          app: app,
          api: FlowsApi('test'),
          title: 'Đề xuất thanh toán',
          askTitle: true,
          submitLabel: 'Nộp đơn',
          fields: FlowField.listOf(_form),
          initial: const {'loai': 'Mua vật tư', 'so_tien': 35000000, 'nha_cung_cap': 'Cty TNHH Cáp Thép Hà Nội', 'hoa_don': [{'id': 'f1', 'name': 'HD-0001523.pdf'}]},
          onSubmit: (_, _) async {},
        ));
  });
}
