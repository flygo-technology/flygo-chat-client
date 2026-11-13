import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/config.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
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

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json'});

void main() {
  final out = Platform.environment['EDITOR_OUT'];
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  for (final (id, n) in [('me', 'Ba'), ('u2', 'Lan Kế toán'), ('u3', 'Tuấn Trưởng phòng')]) {
    app.users[id] = MmUser({'id': id, 'username': n.toLowerCase(), 'first_name': n});
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  var admin = true;
  final requests = <String>[];

  Map<String, dynamic> def(String id, String name, String icon, String cat, {bool active = true, bool hidden = false, bool pinnedAll = false}) =>
      {'id': id, 'name': name, 'icon': icon, 'category': cat, 'version': 3, 'form': [], 'active': active, 'hidden': hidden, 'can_start': active, 'pinned_all': pinnedAll};
  final defs = [
    def('S9MTF4', 'Tải chứng từ ngân hàng theo tháng', '🏦', 'Kế toán'),
    def('tt', 'Đề xuất thanh toán', '💸', 'Kế toán'),
    def('tu', 'Tạm ứng', '💵', 'Kế toán', hidden: true),
    def('np', 'Xin nghỉ phép', '🌴', 'Nhân sự', pinnedAll: true),
    def('ct', 'Đi công tác', '✈️', 'Nhân sự', active: false),
    def('mh', 'Đề xuất mua hàng', '🛒', ''),
  ];
  final runs = [
    {
      'id': 'i1', 'flow_id': 'S9MTF4', 'flow_version': 5, 'flow_name': 'Tải chứng từ ngân hàng theo tháng', 'flow_icon': '🏦', 'category': 'Kế toán',
      'title': 'Báo Có ACB tháng 10', 'status': 'running', 'requester': 'me', 'created_at': now - 7 * 60000, 'updated_at': now,
      'current': ['Chờ ngân hàng tải xong'], 'assignees': [], 'progress': {'percent': 42.0, 'label': 'Downloaded 32 of 76 advice(s).'},
    },
    {
      'id': 'i2', 'flow_id': 'tt', 'flow_version': 2, 'flow_name': 'Đề xuất thanh toán', 'flow_icon': '💸', 'category': 'Kế toán',
      'title': 'Thanh toán cáp thang máy Vinhomes', 'status': 'running', 'requester': 'u2', 'created_at': now - 26 * 3600000, 'updated_at': now - 3600000,
      'current': ['Trưởng phòng duyệt'], 'assignees': ['u3', 'me'],
    },
    {
      'id': 'i3', 'flow_id': 'np', 'flow_version': 1, 'flow_name': 'Xin nghỉ phép', 'flow_icon': '🌴', 'category': 'Nhân sự',
      'title': 'Nghỉ phép 2 ngày', 'status': 'done', 'requester': 'me', 'created_at': now - 3 * 86400000, 'updated_at': now - 2 * 86400000,
    },
    {
      'id': 'i4', 'flow_id': 'S9MTF4', 'flow_version': 5, 'flow_name': 'Tải chứng từ ngân hàng theo tháng', 'flow_icon': '🏦', 'category': 'Kế toán',
      'title': 'Báo Nợ VPBank tháng 9', 'status': 'done', 'requester': 'me', 'created_at': now - 5 * 3600000, 'updated_at': now - 4 * 3600000,
      'problem': {'kind': 'error_end', 'message': 'Không lấy được danh sách giao dịch: phiên VPBank hết hạn'},
    },
  ];
  FlowsApi.debugClient = MockClient((r) async {
    requests.add('${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}');
    return switch (r.url.path) {
      '/__apps/flows/defs' => _json({'flows': [for (final d in defs) if (admin || (d['active'] == true && d['hidden'] != true)) d]}),
      '/__apps/flows/instances' => _json({'instances': runs}),
      '/__apps/flows/tasks' => _json({'tasks': [
          {'id': 7, 'instance_id': 'i2', 'node': 'tp', 'kind': 'approval', 'title': 'Thanh toán cáp thang máy Vinhomes', 'flow_id': 'tt', 'created_at': now},
        ]}),
      '/__apps/flows/me' => _json({'id': 'me', 'admin': admin, 'viewer': admin}),
      _ => _json({}),
    };
  });

  Future<void> pump(WidgetTester t, Size size, int tab, String? shot) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.dark), home: FlowsHome(app: app, initialTab: tab, debugPins: const ['S9MTF4'])),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    if (out != null && shot != null) {
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/$shot.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  }

  testWidgets('5 tab: quy trình (ghim, ghim toàn công ty, quản trị), cần xử lý, đang chạy, lỗi, đã xong', (t) async {
    if (out != null) await t.runAsync(_fonts);
    admin = true;
    await pump(t, const Size(820, 900), 0, 'flows-home-quy-trinh-admin');
    expect(find.text('ĐÃ GHIM'), findsOneWidget);
    expect(find.text('Xin nghỉ phép'), findsNWidgets(2), reason: 'ghim toàn công ty + nhóm Nhân sự');
    for (final x in ['Quy trình', 'Cần xử lý', 'Đang chạy', 'Lỗi', 'Đã xong']) {
      expect(find.text(x), findsWidgets, reason: x);
    }
    expect(find.text('Thêm quy trình'), findsOneWidget);
    expect(find.text('Đang tắt'), findsOneWidget);
    expect(find.text('Đã ẩn'), findsOneWidget);
    expect(requests, contains('GET /__apps/flows/defs?all=1'));
    expect(requests, contains('GET /__apps/flows/instances?scope=related'));
    // Lọc nhanh.
    await t.enterText(find.byType(TextField), 'nghỉ');
    await t.pump();
    expect(find.text('Xin nghỉ phép'), findsNWidgets(2));
    expect(find.text('Đề xuất thanh toán'), findsNothing);
    await t.enterText(find.byType(TextField), '');
    await t.pump();
    // Nháy phải: menu quản trị.
    await t.tap(find.text('Đề xuất thanh toán'), buttons: kSecondaryButton);
    await t.pump(const Duration(milliseconds: 300));
    for (final x in ['Tạo tiến trình mới', 'Ghim lên đầu', 'Sửa', 'Sao chép', 'Ghim toàn công ty', 'Tắt', 'Ẩn']) {
      expect(find.text(x), findsOneWidget, reason: x);
    }
    if (out != null) {
      await t.runAsync(() async {});
    }
    await t.pumpWidget(const SizedBox.shrink());

    await pump(t, const Size(420, 860), 2, 'flows-home-dang-chay');
    expect(find.text('Báo Có ACB tháng 10'), findsOneWidget);
    expect(find.textContaining('Đang chờ: Tuấn Trưởng phòng, Bạn'), findsOneWidget);
    expect(find.textContaining('Bước hiện tại: Trưởng phòng duyệt'), findsOneWidget);
    expect(find.text('Nghỉ phép 2 ngày'), findsNothing);
    expect(find.text('Báo Nợ VPBank tháng 9'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());

    await pump(t, const Size(420, 500), 3, 'flows-home-loi');
    expect(find.text('Báo Nợ VPBank tháng 9'), findsOneWidget);
    expect(find.textContaining('Kết thúc do lỗi: Không lấy được danh sách'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());

    await pump(t, const Size(420, 600), 4, 'flows-home-da-xong');
    expect(find.text('Nghỉ phép 2 ngày'), findsOneWidget);
    expect(find.text('Báo Nợ VPBank tháng 9'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());

    await pump(t, const Size(420, 500), 1, 'flows-home-can-xu-ly');
    expect(find.textContaining('Đề xuất thanh toán'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());

    // Người thường: không có tab Quy trình (chỉ dành cho quản trị), mở ở Cần xử lý; bắt đầu quy trình ở tab Đang chạy.
    admin = false;
    await pump(t, const Size(420, 860), 0, 'flows-home-nguoi-thuong');
    expect(find.widgetWithText(Tab, 'Quy trình'), findsNothing);
    expect(find.text('Thêm quy trình'), findsNothing);
    expect(find.textContaining('Đề xuất thanh toán'), findsOneWidget, reason: 'tab Cần xử lý');
    await t.pumpWidget(const SizedBox.shrink());
    await pump(t, const Size(420, 860), 2, null);
    expect(find.byKey(const ValueKey('start-flow')), findsOneWidget);
    expect(find.text('Báo Có ACB tháng 10'), findsOneWidget, reason: 'initialTab 2 vẫn là Đang chạy');
    await t.pumpWidget(const SizedBox.shrink());
  });
}
