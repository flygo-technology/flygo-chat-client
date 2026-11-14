// Quy trình trên máy tính: Cài đặt quy trình ở cột phải, nút Lưu luôn thấy (chạy cùng bộ test).
// Ảnh xem trước (chạy tay): SHOT_OUT=<thư mục> flutter test test/flows_desktop_preview_test.dart
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
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flows_page.dart';
import 'package:flygo_chat/ui/home_page.dart' show ChatHost, PageCloser;
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

  for (final fam in ['Roboto', 'Noto Sans']) {
    await load(fam, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json'});

final _defs = [
  for (final (id, name, icon, cat) in [
    ('gui-hd', 'Gửi hoá đơn qua email', '📧', 'Tài chính - Kế toán'),
    ('hd-minv', 'Hoá đơn phần mềm → M-Invoice', '🧾', 'Tài chính - Kế toán'),
    ('ct-nh', 'Tải chứng từ ngân hàng theo tháng', '🏦', 'Tài chính - Kế toán'),
    ('hd-bt', 'Hoá đơn phần mềm · Bảo trì 6h', '🧾', 'Tài chính - Kế toán'),
    ('tt', 'Đề xuất thanh toán', '💸', 'Tài chính - Kế toán'),
    ('mua', 'Đề xuất mua hàng', '🛒', 'Mua hàng - Kho'),
    ('xk', 'Xuất kho vật tư', '📦', 'Mua hàng - Kho'),
    ('np', 'Xin nghỉ phép', '🌴', 'Nhân sự'),
    ('ct', 'Đi công tác', '✈️', 'Nhân sự'),
  ])
    {'id': id, 'name': name, 'icon': icon, 'category': cat, 'version': 1, 'active': true, 'steps': 5, 'can_start': true},
];

void main() {
  final out = Platform.environment['SHOT_OUT'];
  kServerUrl = 'https://chat.example.com';
  final app = AppState('test')..me = MmUser({'id': 'me', 'username': 'admin', 'first_name': 'Admin'});
  FlowsApi.debugClient = MockClient((r) async => switch (r.url.path) {
        '/__apps/flows/defs' || '/__apps/flows/admin/defs' => _json({'flows': _defs}),
        '/__apps/flows/me' => _json({'id': 'me', 'admin': true, 'viewer': true}),
        '/__apps/flows/org/departments' => _json({'departments': [
            {'id': 'kt_hn', 'name': 'Kế toán Hà Nội', 'manager': 'me', 'members': ['me']},
            {'id': 'kd', 'name': 'Kinh doanh', 'manager': 'me', 'members': ['me']},
          ]}),
        '/__apps/flows/org/roles' => _json({'roles': <String, dynamic>{}}),
        _ => _json({'flows': [], 'instances': [], 'tasks': [], 'processes': [], 'items': []}),
      });

  Future<void> shot(WidgetTester tester, String name, Widget child, {Future<void> Function()? then}) async {
    await tester.runAsync(_fonts);
    tester.view.physicalSize = const Size(1440, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child)),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (then != null) {
      await then();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('tab Quy trình trên máy tính: hiện trạng (danh sách 460px bên trái, giữa trống)', (t) async {
    if (out == null) return;
    await shot(
        t,
        'flows-tab-before',
        Scaffold(
          body: Builder(builder: (c) {
            final pal = Pal.of(c);
            return Row(children: [
              SizedBox(width: 460, child: FlowsHome(app: app, embedded: true, bottomPadding: 16)),
              VerticalDivider(width: 1, color: pal.divider),
              Expanded(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 96, height: 96, decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle), child: const Icon(Icons.forum, color: Colors.white, size: 52)),
                    const SizedBox(height: 24),
                    Text('Flygo Chat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: pal.text)),
                    const SizedBox(height: 10),
                    Text('Chọn một cuộc trò chuyện bên trái để bắt đầu nhắn tin.', style: TextStyle(fontSize: 15, color: pal.sub)),
                  ]),
                ),
              ),
            ]);
          }),
        ));
  });

  testWidgets('tab Quy trình trên máy tính: danh sách cả trang', (t) async {
    if (out == null) return;
    await shot(t, 'flows-tab-after', Scaffold(body: FlowsHome(app: app, embedded: true, bottomPadding: 16)));
  });

  FlowDoc doc() => FlowDoc.fromJson({
        'id': 'K7Q2XA',
        'name': 'Tải chứng từ ngân hàng theo tháng',
        'icon': '🏦',
        'category': 'Tài chính - Kế toán',
        'visible_to': [
          {'department': 'kt_hn'},
        ],
        'starts': [
          {'type': 'manual', 'who': [{'department': 'kt_hn'}]},
        ],
        'steps': <dynamic>[],
      });

  Widget desk() => _Host(child: FlowEditorPage(app: app, api: FlowsApi('t'), doc: doc()));

  testWidgets('máy tính: Cài đặt quy trình mở sẵn ở cột phải, biểu tượng cạnh tên, nút Lưu luôn thấy', (t) async {
    t.view.physicalSize = const Size(1440, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: desk()),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Cài đặt quy trình'), findsOneWidget);
    expect(find.byKey(const ValueKey('flow-settings-icon')), findsOneWidget);
    // Biểu tượng cùng hàng với ô tên, ở đầu khung.
    final icon = t.getRect(find.byKey(const ValueKey('flow-settings-icon')));
    final name = t.getRect(find.widgetWithText(TextFormField, 'Tên quy trình'));
    expect((icon.center.dy - name.center.dy).abs() < 12, isTrue);
    expect(icon.left < name.left, isTrue);
    // Một nút Lưu duy nhất (thanh tiêu đề trình soạn): chưa sửa thì ghi "Đã lưu" và mờ.
    ButtonStyleButton btn() => t.widget<ButtonStyleButton>(find.byKey(const ValueKey('flow-save')));
    expect(find.byKey(const ValueKey('flow-settings-save')), findsNothing);
    expect(btn().onPressed, isNull);
    expect(find.text('Đã lưu'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextFormField, 'Tên quy trình'), 'Tải chứng từ ngân hàng');
    await t.pump();
    expect(find.text('Lưu'), findsOneWidget);
    expect(btn().onPressed, isNotNull);
    // Đóng khung: hiện nút mở lại trên thanh tiêu đề.
    await t.tap(find.byKey(const ValueKey('flow-settings-close')));
    await t.pump();
    expect(find.text('Cài đặt quy trình'), findsNothing);
    await t.tap(find.byKey(const ValueKey('flow-settings-open')));
    await t.pump();
    expect(find.byKey(const ValueKey('flow-settings-close')), findsOneWidget);
  });

  testWidgets('ảnh: trình soạn máy tính với Cài đặt ở cột phải', (t) async {
    if (out == null) return;
    await shot(t, 'flow-editor-settings-right', desk(), then: () async {
      await t.enterText(find.widgetWithText(TextFormField, 'Tên quy trình'), 'Tải chứng từ ngân hàng theo tháng (HN)');
    });
  });
}

/// Khung giả của màn hình máy tính: vùng giữa (trang có nút đóng) + cột phải 420px.
class _Host extends StatefulWidget {
  final Widget child;
  const _Host({required this.child});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  (String, WidgetBuilder)? _side;
  @override
  Widget build(BuildContext context) => ChatHost(
        openChat: (_) {},
        openInfo: (_) {},
        openThread: (_, _) {},
        openSidePage: (k, b) {
          if (mounted) setState(() => _side = b == null ? null : (k, b));
        },
        child: Scaffold(
          body: Row(children: [
            Expanded(child: PageCloser(onClose: () {}, child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => widget.child)))),
            if (_side != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(width: 420, child: Navigator(key: ValueKey('side-${_side!.$1}'), onGenerateRoute: (_) => MaterialPageRoute(builder: _side!.$2))),
            ],
          ]),
        ),
      );
}
