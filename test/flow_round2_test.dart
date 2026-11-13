// Flows đợt 2a: thuộc tính tiến trình, tiến trình cha / con, tạo nhiều, Chờ tiến trình (trình soạn) và mục "Liên quan",
// "Đang chờ x/y" (trang tiến trình, danh sách). Ảnh (chạy tay): EDITOR_OUT=<thư mục> flutter test test/flow_round2_test.dart
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
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_editor_nodes.dart';
import 'package:flygo_chat/ui/flows/process_detail.dart';
import 'package:flygo_chat/ui/flows/process_list.dart' show ProcessesView;
import 'package:flygo_chat/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts';
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

void main() {
  final out = Platform.environment['EDITOR_OUT'];
  kServerUrl = 'https://chat.test';
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final api = FlowsApi('t', client: MockClient((_) async => http.Response('{}', 404)));

  Future<void> snap(WidgetTester t, String shot) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byType(RepaintBoundary).first) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$shot.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Widget wrap(Widget child) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: RepaintBoundary(child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: child)),
      );

  // Đơn nhập: tạo tiến trình cha (số PO là thuộc tính liên kết), tạo mỗi container một tiến trình con, chờ mọi container về kho.
  Map<String, dynamic> def() => {
        'id': 'nhap-hang',
        'name': 'Nhập hàng',
        'form': [
          {'key': 'so_po', 'label': 'Số PO', 'type': 'text'},
          {'key': 'eta', 'label': 'ETA', 'type': 'date'},
          {
            'key': 'containers', 'label': 'Container', 'type': 'table',
            'columns': [{'key': 'so_cont', 'label': 'Số container', 'type': 'text'}, {'key': 'tau', 'label': 'Tàu', 'type': 'text'}],
          },
        ],
        'nodes': [
          {'id': 'start', 'type': 'start'},
          {
            'id': 'don', 'type': 'process_create', 'name': 'Tạo đơn nhập', 'key': '{{form.so_po}}', 'title': 'Đơn nhập {{form.so_po}}',
            'steps': [{'key': 'dat', 'title': 'Đặt đơn'}, {'key': 'kho', 'title': 'Nhập kho'}],
            'props': {'po': '{{form.so_po}}', 'eta': '{{form.eta}}'}, 'props_link': ['po'], 'fields': [{'prop': 'eta', 'label': 'ETA'}],
          },
          {
            'id': 'cont', 'type': 'process_create', 'name': 'Tạo container', 'key': '{{form.so_po}}-{{item.so_cont}}', 'title': 'Container {{item.so_cont}}',
            'each': 'form.containers', 'parent': {'step': 'don'},
            'steps': [{'key': 'dong', 'title': 'Đóng hàng'}, {'key': 've_kho', 'title': 'Về kho'}],
            'props': {'po': '{{form.so_po}}'},
          },
          {
            'id': 'cho', 'type': 'process_wait', 'name': 'Chờ container về kho', 'of': {'children_of': {'step': 'don'}}, 'until': 'all', 'step': 've_kho',
            'timeout': '30d', 'timeout_to': 'bao', 'on_error': {'to': 'loi'},
          },
          {'id': 'gan', 'type': 'process_props', 'name': 'Ghi ngày về', 'process': {'step': 'don'}, 'set': {'ve_kho': '{{today()}}'}},
          {'id': 'bao', 'type': 'send', 'name': 'Báo quá hạn', 'to': [r'$requester'], 'text': 'Quá hạn'},
          {'id': 'loi', 'type': 'send', 'name': 'Báo lỗi', 'to': [r'$requester'], 'text': 'Lỗi {{steps.cho.output.error.code}}'},
          {'id': 'end', 'type': 'end'},
        ],
        'edges': [['start', 'don'], ['don', 'cont'], ['cont', 'cho'], ['cho', 'gan'], ['gan', 'end'], ['bao', 'end'], ['loi', 'end']],
      };

  test('Chờ tiến trình: nhánh Thành công (cạnh), Quá hạn (timeout_to), Lỗi (on_error); lưu lại giữ nguyên', () {
    final doc = FlowDoc.fromJson(def());
    final cho = doc.allSteps.firstWhere((s) => s.id == 'cho');
    expect([for (final p in cho.ports) p.key], ['ok', 'timeout', 'error']);
    final j = doc.toJson();
    final nodes = {for (final n in j['nodes'] as List) '${n['id']}': n as Map};
    expect(nodes['cho']!['timeout_to'], 'bao');
    expect(nodes['cho']!['on_error'], {'to': 'loi'});
    expect(nodes['cho']!.containsKey('ok_to'), isFalse);
    expect((j['edges'] as List).any((e) => e[0] == 'cho' && e[1] == 'gan'), isTrue, reason: 'nhánh Thành công là cạnh đi ra');
    // Không có hạn, không nhánh lỗi: bước thường (một cạnh), không có nhánh.
    final plain = FStep({'id': 'x', 'type': 'process_wait', 'of': {'children_of': {'step': 'don'}}});
    expect(plain.ports, isEmpty);
    // Có hạn nhưng chưa nối Quá hạn: không ghi timeout_to.
    final d2 = def();
    final cho2 = (d2['nodes'] as List).firstWhere((n) => n['id'] == 'cho') as Map;
    cho2..remove('timeout_to')..remove('on_error');
    final j2 = FlowDoc.fromJson(d2).toJson();
    final n2 = (j2['nodes'] as List).firstWhere((n) => n['id'] == 'cho') as Map;
    expect(n2.containsKey('timeout_to'), isFalse);
    expect(n2['timeout'], '30d');
    expect((j2['edges'] as List).any((e) => e[0] == 'cho' && e[1] == 'gan'), isTrue);
  });

  test('Tóm tắt trên sơ đồ, biến process.* và phần tử đang tạo', () {
    final doc = FlowDoc.fromJson(def());
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc));
    addTearDown(() => editorCtx = null);
    String sum(String id) => nodeSummary(doc.allSteps.firstWhere((s) => s.id == id), app);
    expect(sum('cho'), 'Tiến trình con của "Tạo đơn nhập" · tất cả tới bước Về kho · hạn 30 ngày');
    expect(sum('gan'), 've_kho = {{today()}}');
    expect(sum('cont'), contains('mỗi phần tử của {{form.containers}} một tiến trình'));
    expect(sum('cont'), contains('con của tiến trình của "Tạo đơn nhập"'));
    expect(sum('don'), contains('2 thuộc tính'));
    final vars = flowVars(doc);
    final eta = vars.firstWhere((v) => v.path == 'process.props.eta');
    expect(eta.label, 'Tiến trình › Thuộc tính › ETA', reason: 'tên lấy từ dòng trên thẻ');
    expect(vars.any((v) => v.path == 'process.props.ve_kho'), isTrue, reason: 'thuộc tính gán ở bước sau');
    expect(vars.any((v) => v.path == 'process.state'), isTrue);
    expect(vars.any((v) => v.path == 'steps.cho.output.matched'), isTrue);
    expect(vars.any((v) => v.path == 'steps.cont.output.count'), isTrue);
    expect(vars.any((v) => v.path == 'steps.cont.output.process_id'), isFalse, reason: 'tạo nhiều không có một mã');
    final inEach = flowVars(doc, at: doc.allSteps.firstWhere((s) => s.id == 'cont'));
    expect(inEach.firstWhere((v) => v.path == 'item.so_cont').label, 'Phần tử đang tạo › Số container');
    expect(inEach.any((v) => v.path == 'index'), isTrue);
    expect(vars.any((v) => v.path == 'item.so_cont'), isFalse);
    expect(flowVarLabel('process.props.po', doc), 'Tiến trình › Thuộc tính › po');
    expect(flowVarLabel('process.current_step', doc), 'Tiến trình › Bước hiện tại');
    expect(processRefLabel({'process_id': '{{form.don}}'}), 'tiến trình mã {{form.don}}');
  });

  Future<Map> config(WidgetTester t, FlowDoc doc, FStep s, Future<void> Function() act, {String? shot, double h = 2600}) async {
    if (out != null) await t.runAsync(_fonts);
    await t.pumpWidget(const SizedBox.shrink());
    t.view.physicalSize = Size(520, h);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    editorCtx = EditorCtx(app: app, api: api, doc: doc, steps: doc.allSteps, vars: flowVars(doc), flows: const [
      {'id': 'container', 'name': 'Container (mẫu)', 'icon': '🚢'},
    ]);
    addTearDown(() => editorCtx = null);
    Object? done;
    await t.pumpWidget(wrap(Scaffold(
      body: StepConfigSheet(app: app, node: s.node, form: FlowField.listOf(doc.meta['form']), roles: const {}, vars: flowVars(doc, at: s), onDone: (r) => done = r),
    )));
    await t.pump();
    await act();
    if (shot != null) await snap(t, shot);
    await t.tap(find.text('Xong'));
    return done as Map;
  }

  testWidgets('Tạo tiến trình: thuộc tính, liên kết, dòng trên thẻ, tiến trình cha, tạo nhiều', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = doc.allSteps.firstWhere((x) => x.id == 'don');
    final r = await config(t, doc, s, () async {
      expect(find.text('Thuộc tính'), findsWidgets);
      expect(find.text('Liên kết'), findsNWidgets(2));
      expect(find.text('Tiến trình cha'), findsOneWidget);
      // Thêm thuộc tính, bật liên kết cho eta.
      await t.tap(find.text('Thêm thuộc tính'));
      await t.pump();
      await t.tap(find.text('Liên kết').at(1));
      await t.pump();
    }, shot: 'r2-editor-process-create-props');
    expect((r['props'] as Map).keys, ['po', 'eta', 'tt_3']);
    expect(r['props_link'], ['po', 'eta']);
    expect(r['fields'], [{'prop': 'eta', 'label': 'ETA'}]);
    expect(r.containsKey('each'), isFalse);
    expect(r.containsKey('parent'), isFalse);

    final c = doc.allSteps.firstWhere((x) => x.id == 'cont');
    final r2 = await config(t, doc, c, () async {
      expect(find.text('Tạo nhiều (mỗi phần tử của danh sách một tiến trình)'), findsOneWidget);
      expect(find.textContaining('Khoá phải chứa'), findsNothing, reason: 'khoá đã có item');
      // Đổi tiến trình cha sang "Theo mã tiến trình…".
      await t.ensureVisible(find.text('Theo mã tiến trình…').first);
      await t.tap(find.text('Theo mã tiến trình…').first);
      await t.pump();
      expect(find.text('Mã tiến trình (vd từ biểu mẫu do quy trình cha truyền sang)'), findsOneWidget);
    });
    expect(r2['each'], 'form.containers', reason: '$r2');
    expect(r2['parent'], {'process_id': ''});
  });

  testWidgets('Chờ tiến trình: con của / cùng thuộc tính, tất cả / bất kỳ / đủ n, trạng thái / bước, hạn, nhánh lỗi', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('process_wait') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      expect(find.text('Tiến trình con'), findsOneWidget);
      expect(find.text('Khi có tiến trình lỗi / bị huỷ'), findsOneWidget);
      await t.tap(find.text('Tới bước'));
      await t.pump();
      expect(find.text('Đóng hàng'), findsOneWidget, reason: 'bước của tiến trình con lấy từ bước Tạo tiến trình có cha');
      await t.tap(find.text('Đủ số lượng'));
      await t.pump();
      await t.tap(find.text('7 ngày'));
      await t.pump();
    }, shot: 'r2-editor-process-wait');
    expect(r['of'], {'children_of': {'step': 'don'}}, reason: 'tự chọn tiến trình (một) tạo ở bước trước');
    expect(r['until'], {'count': 2});
    expect(r['step'], 'dong');
    expect(r.containsKey('state'), isFalse);
    expect(r['timeout'], '7d');

    final s2 = FlowDoc.make('process_wait') as FStep;
    doc.steps.add(s2);
    final r2 = await config(t, doc, s2, () async {
      await t.tap(find.text('Cùng thuộc tính'));
      await t.pump();
      await t.tap(find.text('Thêm thuộc tính'));
      await t.pump();
      await t.tap(find.text('Bất kỳ'));
      await t.pump();
      await t.tap(find.text('Lỗi'));
      await t.pump();
    });
    expect(r2['of'], {'prop': {'tt_1': ''}});
    expect(r2['until'], 'any');
    expect(r2['state'], 'done,failed');
  });

  testWidgets('Gán thuộc tính tiến trình: gán và bỏ', (t) async {
    final doc = FlowDoc.fromJson(def());
    final s = FlowDoc.make('process_props') as FStep;
    doc.steps.add(s);
    final r = await config(t, doc, s, () async {
      expect(find.text('Chưa có thuộc tính cần gán / bỏ.'), findsOneWidget);
      await t.tap(find.text('Thêm thuộc tính'));
      await t.pump();
    });
    expect(r['process'], {'step': 'don'});
    expect(r['set'], {'tt_1': ''});
  });

  // ------------------------------------------------------------------ trang tiến trình

  final now = DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> lite(String id, String flow, String flowName, String icon, String name, String state, String step, {String status = '', Map? waiting}) => {
        'id': id, 'flow_id': flow, 'flow_name': flowName, 'flow_icon': icon, 'name': name, 'icon': icon, 'state': state,
        'current_step': 'x', 'current_step_title': step, 'status_text': status, 'tone': state == 'done' ? 'green' : 'blue', 'waiting': waiting,
      };
  final waiting = {'text': 'Đang chờ 2/3 tiến trình con', 'matched': 2, 'total': 3};
  final detail = {
    'id': 'P-PO0001', 'flow_id': 'don-nhap', 'flow_name': 'Đơn nhập (mẫu)', 'flow_icon': '📦', 'key': 'PO-2026-0001', 'name': 'Đơn nhập PO-2026-0001', 'icon': '📦',
    'state': 'running', 'current_step': 'van_chuyen', 'status_text': 'Hàng đang về', 'tone': 'blue',
    'steps': [
      {'key': 'dat', 'title': 'Đặt đơn', 'state': 'done'},
      {'key': 'gom', 'title': 'Kiểm & gom', 'state': 'done'},
      {'key': 'tt', 'title': 'Thanh toán', 'state': 'done'},
      {'key': 'van_chuyen', 'title': 'Vận chuyển & hải quan', 'state': 'active'},
      {'key': 'kho', 'title': 'Nhập kho', 'state': 'pending'},
    ],
    'stats': [{'key': 'tong', 'label': 'Giá trị', 'type': 'number', 'value': 2450000000}],
    'labels': [], 'created_at': now - 86400000 * 20, 'updated_at': now - 3600000,
    'props': {'po': 'PO-2026-0001', 'ncc': 'Shenzhen Hongda'}, 'props_link': ['po'],
    'prop_fields': [{'prop': 'po', 'label': 'Số PO'}, {'prop': 'ncc', 'label': 'Nhà cung cấp'}],
    'parent': null,
    'children': [
      lite('P-C1', 'container', 'Container (mẫu)', '🚢', 'Container TGHU 123456-7', 'done', 'Về kho'),
      lite('P-C2', 'container', 'Container (mẫu)', '🚢', 'Container MSKU 765432-1', 'running', 'Thông quan', status: 'Chờ tờ khai'),
      lite('P-C3', 'container', 'Container (mẫu)', '🚢', 'Container CSNU 112233-4', 'done', 'Về kho'),
      lite('P-T1', 'thanh-toan', 'Thanh toán (mẫu)', '💳', 'Thanh toán cọc 30%', 'done', 'Đã chi'),
    ],
    'related': [
      {'prop': 'po', 'label': 'Số PO', 'value': 'PO-2026-0001', 'processes': [lite('P-HQ1', 'to-khai', 'Tờ khai hải quan', '🛃', 'Tờ khai 10234567', 'running', 'Phân luồng')]},
    ],
    'waiting': waiting,
    'events': [
      {'at': now - 86400000 * 20, 'kind': 'create', 'data': {'key': 'PO-2026-0001'}},
    ],
  };
  final child = {
    ...lite('P-C2', 'container', 'Container (mẫu)', '🚢', 'Container MSKU 765432-1', 'running', 'Thông quan', status: 'Chờ tờ khai'),
    'steps': [{'key': 'dong', 'title': 'Đóng hàng', 'state': 'done'}, {'key': 'thong_quan', 'title': 'Thông quan', 'state': 'active'}],
    'current_step': 'thong_quan', 'stats': [], 'labels': [], 'created_at': now - 86400000 * 10, 'updated_at': now - 7200000,
    'parent': lite('P-PO0001', 'don-nhap', 'Đơn nhập (mẫu)', '📦', 'Đơn nhập PO-2026-0001', 'running', 'Vận chuyển & hải quan', waiting: waiting),
    'children': [], 'related': [], 'events': [],
  };
  final requests = <Uri>[];
  setUp(() {
    FlowsApi.debugClient = MockClient((r) async {
      requests.add(r.url);
      return switch (r.url.path) {
        '/__apps/flows/processes/P-PO0001' => _json(detail),
        '/__apps/flows/processes/P-C2' => _json(child),
        '/__apps/flows/processes' => _json({'processes': [{...detail}..remove('children')..remove('related')]}),
        _ => _json({}),
      };
    });
  });
  tearDown(() => FlowsApi.debugClient = null);

  Future<void> pumpPage(WidgetTester t, Size size, Widget home) async {
    if (out != null) await t.runAsync(_fonts);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(wrap(home));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Trang tiến trình: Đang chờ 2/3, thuộc tính, Liên quan (con theo quy trình, cùng Số PO); bấm mở tiến trình con', (t) async {
    await pumpPage(t, const Size(430, 1250), ProcessDetailPage(app: app, processId: 'P-PO0001'));
    expect(find.text('Đang chờ 2/3 tiến trình con'), findsOneWidget);
    expect(find.text('Số PO'), findsOneWidget);
    expect(find.text('Nhà cung cấp'), findsOneWidget);
    expect(find.text('Shenzhen Hongda'), findsOneWidget);
    expect(find.text('LIÊN QUAN'), findsOneWidget);
    expect(find.text('Tiến trình con · Container (mẫu) (2/3 xong)'), findsOneWidget);
    expect(find.text('Tiến trình con · Thanh toán (mẫu) (1/1 xong)'), findsOneWidget);
    expect(find.text('Cùng Số PO: PO-2026-0001'), findsOneWidget);
    expect(find.text('Container MSKU 765432-1'), findsOneWidget);
    expect(find.text('Bước: Thông quan'), findsOneWidget);
    expect(find.text('Chờ tờ khai'), findsOneWidget);
    expect(find.text('Tờ khai 10234567'), findsOneWidget);
    expect(find.textContaining('P-C'), findsNothing, reason: 'không hiện mã tiến trình');
    expect(find.textContaining('P-HQ'), findsNothing);
    await t.ensureVisible(find.text('Tờ khai 10234567'));
    await t.pump();
    await snap(t, 'r2-lien-quan');
    await t.tap(find.text('Container MSKU 765432-1'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(requests.any((u) => u.path == '/__apps/flows/processes/P-C2'), isTrue);
    // Tiến trình con: thấy tiến trình cha, cha đang chờ.
    expect(find.text('Tiến trình cha'), findsOneWidget);
    expect(find.text('Đơn nhập PO-2026-0001'), findsWidgets);
    expect(find.textContaining('Đang chờ 2/3 tiến trình con'), findsWidgets);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Danh sách tiến trình: dòng có "Đang chờ x/y"', (t) async {
    await pumpPage(t, const Size(430, 700), Scaffold(body: ProcessesView(app: app, defs: const [])));
    expect(find.text('Đơn nhập PO-2026-0001'), findsOneWidget);
    expect(find.text('Đang chờ 2/3 tiến trình con'), findsOneWidget);
    await snap(t, 'r2-dang-cho');
    await t.pumpWidget(const SizedBox.shrink());
  });

  test('FlowProcess: thuộc tính, nhãn thuộc tính, cha / con / liên quan, đang chờ; bộ lọc prop.* và parent', () async {
    final p = FlowProcess.fromJson(detail);
    expect(p.props['po'], 'PO-2026-0001');
    expect(p.propLabel('ncc'), 'Nhà cung cấp');
    expect(p.propLabel('khac'), 'khac');
    expect(p.parent, isNull);
    expect(p.children.length, 4);
    expect(p.children.first.currentStepTitle, 'Về kho');
    expect(p.related.single.$2, 'Số PO');
    expect(p.waitingText, 'Đang chờ 2/3 tiến trình con');
    expect(FlowProcess.fromJson({'waiting': {'matched': 1, 'total': 4}}).waitingText, '1/4');
    await FlowsApi('t').processes(props: {'po': 'PO-1'}, parent: 'P-PO0001');
    expect(requests.last.queryParameters, {'prop.po': 'PO-1', 'parent': 'P-PO0001'});
  });
}
