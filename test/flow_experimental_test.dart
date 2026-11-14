// Quy trình "Thử nghiệm": nhãn ở trang "Bắt đầu quy trình", lưới Quy trình (quản trị), trang quy trình; không bắt đầu
// được (bấm chỉ báo); công tắc ở Cài đặt quy trình lưu vào JSON. Ảnh (chạy tay):
// EDITOR_OUT=<thư mục> flutter test test/flow_experimental_test.dart
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
import 'package:flygo_chat/ui/common.dart' show PlusFab;
import 'package:flygo_chat/ui/flows/flow_doc.dart' show FlowDoc;
import 'package:flygo_chat/ui/flows/flow_editor.dart' show FlowEditorPage;
import 'package:flygo_chat/ui/flows/flow_experimental.dart';
import 'package:flygo_chat/ui/flows/flows_page.dart' show FlowStartPage, FlowsHome;
import 'package:flygo_chat/ui/flows/workflow_page.dart';
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
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

http.Response _json(Object o) => http.Response.bytes(utf8.encode(jsonEncode(o)), 200, headers: {'content-type': 'application/json'});

const _msg = 'Quy trình đang thử nghiệm, chưa chạy được.';

void main() {
  final out = Platform.environment['EDITOR_OUT'];
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final requests = <String>[];
  final saved = <Map>[];
  var admin = true;

  Map<String, dynamic> def(String id, String name, String icon, String cat, {bool exp = false}) => {
        'id': id, 'name': name, 'icon': icon, 'category': cat, 'version': 1, 'active': true, 'hidden': false, 'pinned_all': false,
        'form': exp ? [] : [{'key': 'so_tien', 'label': 'Số tiền', 'type': 'money'}, {'key': 'ly_do', 'label': 'Lý do', 'type': 'text'}],
        'can_start': !exp, if (exp) 'experimental': true,
      };
  final defs = [
    def('tt', 'Đề xuất thanh toán', '💸', 'Kế toán'),
    def('tu', 'Tạm ứng', '💵', 'Kế toán'),
    def('QTKT01', 'Quyết toán thuế cuối năm', '🧮', 'Kế toán', exp: true),
    def('np', 'Xin nghỉ phép', '🌴', 'Nhân sự'),
    def('QTNS01', 'Đánh giá nhân viên', '⭐', 'Nhân sự', exp: true),
    def('QTNS02', 'Tuyển dụng', '🧑‍💼', 'Nhân sự', exp: true),
  ];
  FlowsApi.debugClient = MockClient((r) async {
    requests.add('${r.method} ${r.url.path}');
    final p = r.url.path;
    if (r.method == 'POST' && p == '/__apps/flows/start') {
      return http.Response.bytes(utf8.encode(jsonEncode({'error': _msg})), 409, headers: {'content-type': 'application/json'});
    }
    if (p == '/__apps/flows/defs/QTKT01/info') {
      return _json({
        'id': 'QTKT01', 'name': 'Quyết toán thuế cuối năm', 'icon': '🧮', 'category': 'Kế toán', 'description': 'Sắp có: quyết toán thuế TNCN và TNDN.',
        'version': 1, 'active': true, 'can_start': false, 'experimental': true, 'who_can_start': [{'kind': 'all', 'id': '', 'name': 'Mọi người'}], 'steps': [],
      });
    }
    return switch (p) {
      '/__apps/flows/defs' => _json({'flows': defs}),
      '/__apps/flows/me' => _json({'id': 'me', 'admin': admin, 'viewer': admin}),
      '/__apps/flows/instances' => _json({'instances': []}),
      '/__apps/flows/tasks' => _json({'tasks': []}),
      '/__apps/flows/processes' => _json({'processes': []}),
      _ => _json({}),
    };
  });

  Future<void> shot(WidgetTester t, GlobalKey key, String? name) async {
    if (out == null || name == null) return;
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<GlobalKey> pump(WidgetTester t, Widget home, {Size size = const Size(1280, 800)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: home)),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    return key;
  }

  test('FlowDefInfo đọc cờ experimental (mặc định tắt)', () {
    expect(FlowDefInfo.fromJson(def('a', 'A', '', '', exp: true)).experimental, isTrue);
    expect(FlowDefInfo.fromJson(def('a', 'A', '', '')).experimental, isFalse);
    expect(FlowDefInfo.fromJson({'id': 'x'}).experimental, isFalse);
  });

  testWidgets('Bắt đầu quy trình: quy trình thử nghiệm có nhãn, bấm chỉ báo, không gọi /flows/start', (t) async {
    if (out != null) await t.runAsync(_fonts);
    final key = await pump(t, FlowStartPage(app: app, api: FlowsApi(app.token)));
    expect(find.byType(FlowExperimentalBadge), findsNWidgets(3));
    expect(find.text('Thử nghiệm'), findsNWidgets(3));
    expect(find.text('Đề xuất thanh toán'), findsOneWidget);
    await shot(t, key, 'experimental-start-picker');
    final before = find.text(_msg).evaluate().length;
    requests.clear();
    await t.tap(find.text('Quyết toán thuế cuối năm'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(_msg).evaluate().length, before + 1, reason: 'snackbar báo chưa chạy được');
    expect(requests.where((r) => r.startsWith('POST')), isEmpty);
    expect(find.text('Tạo tiến trình mới'), findsOneWidget, reason: 'vẫn ở trang chọn, không mở biểu mẫu');
    // Quy trình thường: mở biểu mẫu như trước.
    await t.tap(find.text('Đề xuất thanh toán'));
    await t.pumpAndSettle();
    expect(find.text('Số tiền'), findsWidgets);
  });

  testWidgets('Lưới Quy trình (quản trị): nhãn Thử nghiệm, menu không có "Tạo tiến trình mới"', (t) async {
    if (out != null) await t.runAsync(_fonts);
    admin = true;
    final key = await pump(t, FlowsHome(app: app, initialTab: 0, debugPins: const []));
    expect(find.byType(FlowExperimentalBadge), findsNWidgets(3));
    await shot(t, key, 'experimental-catalog');
    await t.tap(find.text('Đánh giá nhân viên'), buttons: 2);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Sửa'), findsOneWidget, reason: 'quản trị vẫn sửa được');
    expect(find.text('Tạo tiến trình mới'), findsNothing);
  });

  testWidgets('Trang quy trình thử nghiệm: nhãn, nút ＋ mờ chỉ báo chưa chạy được', (t) async {
    if (out != null) await t.runAsync(_fonts);
    final d = FlowDefInfo.fromJson(def('QTKT01', 'Quyết toán thuế cuối năm', '🧮', 'Kế toán', exp: true));
    final key = await pump(t, WorkflowPage(app: app, flowId: d.id, name: d.name, icon: d.icon, def: d, admin: false));
    expect(find.byType(FlowExperimentalBadge), findsWidgets);
    expect(find.byKey(const ValueKey('workflow-new-experimental')), findsOneWidget);
    await shot(t, key, 'experimental-workflow-page');
    requests.clear();
    await t.tap(find.byType(PlusFab));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(_msg), findsOneWidget);
    expect(requests.where((r) => r.startsWith('POST')), isEmpty);
  });

  testWidgets('Cài đặt quy trình: công tắc Thử nghiệm ghi vào JSON khi lưu, tắt thì bỏ khoá', (t) async {
    final api = FlowsApi('t', client: MockClient((r) async {
      if (r.method == 'POST' && r.url.path == '/__apps/flows/defs') {
        saved.add(jsonDecode(r.body) as Map);
        return _json({'id': 'QTNS02', 'version': saved.length + 1, 'issues': []});
      }
      return _json({});
    }));
    final doc = FlowDoc.fromJson({
      'id': 'QTNS02', 'name': 'Tuyển dụng', 'icon': '🧑‍💼',
      'nodes': [{'id': 'start', 'type': 'start'}, {'id': 'end', 'type': 'end'}], 'edges': [['start', 'end']],
    });
    await pump(t, FlowEditorPage(app: app, api: api, doc: doc), size: const Size(900, 1400));
    Future<void> menu(String item) async {
      await t.tap(find.byTooltip('Thao tác'));
      await t.pumpAndSettle();
      await t.tap(find.text(item));
      await t.pumpAndSettle();
    }

    await menu('Cài đặt quy trình');
    final sw = find.byKey(const ValueKey('flow-experimental'));
    expect(sw, findsOneWidget);
    expect(find.text('Hiện cho mọi người nhưng chưa cho bắt đầu'), findsOneWidget);
    expect(t.widget<SwitchListTile>(sw).value, isFalse);
    await t.tap(sw);
    await t.pumpAndSettle();
    expect(t.widget<SwitchListTile>(sw).value, isTrue);
    expect(doc.meta['experimental'], isTrue);
    Navigator.of(t.element(sw)).pop();
    await t.pumpAndSettle();
    // Nút Lưu luôn hiện trên thanh tiêu đề.
    await t.tap(find.byKey(const ValueKey('flow-save')));
    await t.pumpAndSettle();
    expect(saved.last['experimental'], isTrue);
    // Mở lại từ JSON đã lưu: vẫn bật; tắt thì không còn khoá experimental.
    final again = FlowDoc.fromJson(Map<String, dynamic>.from(saved.last));
    expect(again.meta['experimental'], isTrue);
    await t.pumpWidget(const SizedBox.shrink());
    await pump(t, FlowEditorPage(app: app, api: api, doc: again), size: const Size(900, 1400));
    await menu('Cài đặt quy trình');
    expect(t.widget<SwitchListTile>(sw).value, isTrue);
    await t.tap(sw);
    await t.pumpAndSettle();
    Navigator.of(t.element(sw)).pop();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('flow-save')));
    await t.pumpAndSettle();
    expect(saved.last.containsKey('experimental'), isFalse);
  });
}
