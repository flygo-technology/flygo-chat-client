// Ảnh xem trước trình soạn quy trình (chạy tay): EDITOR_OUT=<thư mục> flutter test test/flow_editor_preview_test.dart
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
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_buttons.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';
import 'package:flygo_chat/ui/flows/flow_form.dart';
import 'package:flygo_chat/ui/flows/flow_table.dart';
import 'package:flygo_chat/ui/flows/flows_admin.dart';
import 'package:flygo_chat/ui/flows/flows_all.dart';
import 'package:flygo_chat/ui/flows/flows_org.dart';
import 'package:flygo_chat/ui/flows/flows_page.dart';
import 'package:flygo_chat/ui/flows/flow_lookup.dart';
import 'package:flygo_chat/ui/flows/flows_stats.dart';
import 'package:flygo_chat/ui/flows/flow_delegations.dart';
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

const _now = 1793840400000;

http.Response _json(Object o, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(o)), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _fixture(String f) => jsonDecode(File('test/fixtures/flows/$f').readAsStringSync()) as Map<String, dynamic>;

void main() {
  final out = Platform.environment['EDITOR_OUT'];
  kServerUrl = 'https://chat.flygo.vn';
  final app = AppState('test')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  for (final (id, n) in [('me', 'Ba'), ('u2', 'Lan Kế toán'), ('u3', 'Tuấn Trưởng phòng'), ('u4', 'Đang Giám đốc'), ('u5', 'Hoa Kế toán trưởng')]) {
    app.users[id] = MmUser({'id': id, 'username': n.toLowerCase(), 'first_name': n});
  }
  app.channels['c1'] = MmChannel({'id': 'c1', 'name': 'bao-no-bao-co', 'display_name': 'Báo nợ báo có', 'type': 'P'});
  final pay = _fixture('de-xuat-thanh-toan.json');
  final adv = _fixture('tam-ung.json');
  final order = _fixture('don-hang.json');
  final stock = _fixture('canh-bao-ton-kho.json');
  final bank = _fixture('bao-co-khach-hang.json');
  final nk = _fixture('nhap-kho.json');
  final tplNames = ['de-xuat-thanh-toan', 'tam-ung', 'de-xuat-mua-hang', 'don-hang', 'nghi-phep', 'cong-tac', 'canh-bao-ton-kho'];
  Map<String, dynamic> visit(String node, String name, [List<String> who = const [], String outcome = '']) =>
      {'node': node, 'name': name, if (who.isNotEmpty) 'who': who, if (outcome.isNotEmpty) 'outcome': outcome};

  FlowsApi.debugClient = MockClient((r) async => switch (r.url.path) {
        '/__apps/flows/tasks' => _json({'tasks': [
            {'id': 12, 'instance_id': 'i1', 'node': 'gd', 'kind': 'approval', 'title': 'Mua cáp tải thang máy cho công trình Vinhomes', 'flow_id': 'de-xuat-thanh-toan', 'created_at': _now},
          ]}),
        '/__apps/flows/instances' => _json({'instances': [
            {'id': 'i3', 'title': 'Mua 5 bộ biến tần', 'status': 'running', 'updated_at': _now},
            {'id': 'i5', 'title': 'Thanh toán dịch vụ vận chuyển', 'status': 'returned', 'updated_at': _now - 2 * 86400000},
            {'id': 'i4', 'title': 'Tạm ứng đi công trình Hải Phòng', 'status': 'done', 'updated_at': _now - 86400000},
          ]}),
        '/__apps/flows/defs' => _json({'flows': [
            {'id': 'de-xuat-thanh-toan', 'name': 'Đề xuất thanh toán', 'icon': '💸', 'category': 'Tài chính - Kế toán', 'form': pay['form']},
            {'id': 'tam-ung', 'name': 'Tạm ứng', 'icon': '💵', 'category': 'Tài chính - Kế toán', 'form': adv['form']},
            {'id': 'mua-hang', 'name': 'Đề xuất mua hàng', 'icon': '🛒', 'category': 'Mua hàng - Kho', 'form': [{'key': 'hang', 'label': 'Mặt hàng'}, {'key': 'sl', 'label': 'Số lượng'}]},
            {'id': 'xuat-kho', 'name': 'Xuất kho vật tư', 'icon': '📦', 'category': 'Mua hàng - Kho', 'form': [{'key': 'cong_trinh', 'label': 'Công trình'}]},
            {'id': 'nghi-phep', 'name': 'Xin nghỉ phép', 'icon': '🌴', 'category': 'Nhân sự', 'form': [{'key': 'tu', 'label': 'Từ ngày'}, {'key': 'den', 'label': 'Đến ngày'}, {'key': 'ly_do', 'label': 'Lý do'}]},
            {'id': 'cong-tac', 'name': 'Đi công tác', 'icon': '✈️', 'category': 'Nhân sự', 'form': []},
          ]}),
        '/__apps/flows/admin/defs' => _json({'flows': [
            {'id': 'de-xuat-thanh-toan', 'name': 'Đề xuất thanh toán', 'icon': '💸', 'category': 'Tài chính - Kế toán', 'version': 3, 'active': true, 'steps': 9},
            {'id': 'tam-ung', 'name': 'Tạm ứng', 'icon': '💵', 'category': 'Tài chính - Kế toán', 'version': 1, 'active': true, 'steps': 12},
            {'id': 'mua-hang', 'name': 'Đề xuất mua hàng', 'icon': '🛒', 'category': 'Mua hàng - Kho', 'version': 2, 'active': false, 'steps': 6},
            {'id': 'nghi-phep', 'name': 'Xin nghỉ phép', 'icon': '🌴', 'category': 'Nhân sự', 'version': 1, 'active': true, 'steps': 4},
          ]}),
        '/__apps/flows/me' => _json({'id': 'me', 'admin': true, 'viewer': true}),
        '/__apps/flows/org/departments' => _json({'departments': [
            {'id': 'kinh_doanh', 'name': 'Kinh doanh', 'manager': 'u3', 'members': ['me', 'u2']},
            {'id': 'ke_toan', 'name': 'Kế toán', 'manager': 'u5', 'members': ['u2']},
          ]}),
        '/__apps/flows/admin/defs/bao-co-khach-hang/webhook' => _json({
            'path': '/__apps/flows/hooks/5f2c9a81d4e07b3361aa0c94e2f1b7d8c6a5e4f3', 'secret': 'b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4', 'last_at': _now,
            'last_payload': {'amount': 15000000, 'description': 'ACHAU TT DH 1023', 'bank': 'ACB', 'transaction_id': 'FT2611050001', 'date': '05/11/2026'},
          }),
        '/__apps/flows/lookup' => _json({'items': [
            {'value': 'KH-001', 'label': 'Cty Thang máy Á Châu', 'sub': 'Hà Nội · công nợ 125.000.000', 'data': {}},
            {'value': 'KH-014', 'label': 'Cty CP Thang máy Đông Á', 'sub': 'TP.HCM · công nợ 0', 'data': {}},
          ]}),
        '/__apps/flows/my-duties' => _json({'flows': [
            {'id': 'de-xuat-thanh-toan', 'name': 'Đề xuất thanh toán', 'icon': '💸', 'relevant': true},
            {'id': 'tam-ung', 'name': 'Tạm ứng', 'icon': '💵', 'relevant': true},
            {'id': 'de-xuat-mua-hang', 'name': 'Đề xuất mua hàng', 'icon': '🛒', 'relevant': true},
            {'id': 'nghi-phep', 'name': 'Xin nghỉ phép', 'icon': '🌴', 'relevant': true},
            {'id': 'cong-tac', 'name': 'Đi công tác', 'icon': '✈️', 'relevant': false},
          ]}),
        '/__apps/flows/names' => _json({'flows': [
            {'id': 'de-xuat-thanh-toan', 'name': 'Đề xuất thanh toán', 'icon': '💸'},
            {'id': 'tam-ung', 'name': 'Tạm ứng', 'icon': '💵'},
            {'id': 'nghi-phep', 'name': 'Xin nghỉ phép', 'icon': '🌴'},
          ]}),
        '/__apps/flows/me/delegations' => _json({
            'now': _now,
            'flows': {'nghi-phep': 'Xin nghỉ phép', 'de-xuat-thanh-toan': 'Đề xuất thanh toán'},
            'request_flows': [{'id': 'nghi-phep', 'name': 'Xin nghỉ phép', 'icon': '🌴'}],
            'mine': [
              {'id': 1, 'user': 'me', 'delegate': 'u2', 'flows': ['de-xuat-thanh-toan'], 'from': _now - 86400000, 'until': _now + 2 * 86400000 + 5 * 3600000, 'note': 'Nghỉ phép năm', 'instance_id': 'i9'},
              {'id': 2, 'user': 'me', 'delegate': 'u3', 'flows': <String>[], 'from': _now - 86400000, 'until': _now + 2 * 86400000 + 5 * 3600000, 'note': 'Nghỉ phép năm', 'instance_id': 'i9'},
            ],
            'to_me': [
              {'id': 3, 'user': 'u4', 'delegate': 'me', 'flows': <String>[], 'from': _now + 3 * 86400000, 'until': _now + 6 * 86400000, 'note': 'Đi công tác'},
            ],
          }),
        '/__apps/flows/me/delegation' => _json({
            'delegation': {'user': 'me', 'delegate': 'u3', 'from': _now, 'until': _now + 3 * 86400000, 'note': 'Đi công tác Đà Nẵng'},
            'delegated_to_me': [{'user': 'u4', 'delegate': 'me', 'from': _now, 'until': _now + 86400000, 'note': 'Nghỉ phép'}],
          }),
        '/__apps/flows/admin/templates' => _json({'templates': [for (final t in tplNames) _fixture('$t.json')]}),
        '/__apps/flows/admin/integrations' => _json({
            'agents': [
              {'username': 'ketoan-ai', 'name': 'Trợ lý kế toán', 'owner': 'Ba'},
              {'username': 'kho-ai', 'name': 'Trợ lý kho', 'owner': 'Ba'},
            ],
            'mcp': [
              {
                'name': 'erp', 'label': 'ERP (ERPNext)',
                'tools': [
                  {'name': 'ton_kho', 'description': 'Tra số lượng tồn của một mã hàng', 'read_only': true, 'allowed': true,
                    'input_schema': {'type': 'object', 'properties': {'ma_hang': {'type': 'string', 'description': 'Mã hàng'}, 'kho': {'type': 'string', 'enum': ['Kho HN', 'Kho HCM']}}, 'required': ['ma_hang']},
                    'output_schema': {'properties': {'so_luong': {'type': 'number'}}}},
                  {'name': 'lap_phieu_chi', 'description': 'Lập phiếu chi', 'read_only': false, 'allowed': false, 'input_schema': {'type': 'object'}},
                ],
              },
              {'name': 'bank', 'label': 'Ngân hàng', 'tools': []},
            ],
            'ai_credentials': [{'name': 'claude', 'provider': 'anthropic', 'model': 'claude-sonnet-5'}],
          }),
        '/__apps/flows/admin/instances' => _json({
            'total': 4,
            'flows': [{'id': 'de-xuat-thanh-toan', 'name': 'Đề xuất thanh toán', 'icon': '💸'}, {'id': 'nghi-phep', 'name': 'Xin nghỉ phép', 'icon': '🌴'}],
            'instances': [
              {'id': 'i1', 'flow_name': 'Đề xuất thanh toán', 'icon': '💸', 'title': 'Mua cáp tải thang máy cho công trình Vinhomes', 'requester': 'u2', 'status': 'running', 'created_at': _now, 'waiting_for': ['u4']},
              {'id': 'i2', 'flow_name': 'Xin nghỉ phép', 'icon': '🌴', 'title': 'Nghỉ phép 10-11/11', 'requester': 'u3', 'status': 'done', 'created_at': _now - 86400000},
              {'id': 'i3', 'flow_name': 'Đề xuất thanh toán', 'icon': '💸', 'title': 'Thanh toán dịch vụ vận chuyển', 'requester': 'u2', 'status': 'returned', 'created_at': _now - 2 * 86400000},
              {'id': 'i4', 'flow_name': 'Tạm ứng', 'icon': '💵', 'title': 'Tạm ứng công tác Hải Phòng', 'requester': 'u5', 'status': 'rejected', 'created_at': _now - 5 * 86400000},
            ],
          }),
        '/__apps/flows/org/roles' => _json({'roles': {'truong_phong': ['u3'], 'giam_doc': ['u4'], 'ke_toan': ['u2'], 'ke_toan_truong': ['u5']}}),
        '/__apps/flows/defs/check' => _json({'ok': true, 'issues': [], 'traces': [
            {'label': 'so_tien = 20.000.000', 'status': 'done', 'messages': [], 'path': [
              visit('ai_kiem', 'AI kiểm chứng từ'), visit('tp', 'Trưởng phòng duyệt', ['u3'], 'approve'), visit('chk', 'Trên 20 triệu?', [], 'else'),
              visit('ktt', 'Kế toán trưởng xác nhận', ['u5'], 'approve'), visit('ai_chi', 'AI lập phiếu chi'), visit('bao', 'Báo kế toán', ['me', 'u2']),
            ]},
            {'label': 'so_tien = 20.000.001', 'status': 'done', 'messages': [], 'path': [
              visit('ai_kiem', 'AI kiểm chứng từ'), visit('tp', 'Trưởng phòng duyệt', ['u3'], 'approve'), visit('chk', 'Trên 20 triệu?', [], 'rule 1'),
              visit('gd', 'Giám đốc duyệt', ['u4'], 'approve'), visit('ktt', 'Kế toán trưởng xác nhận', ['u5'], 'approve'), visit('ai_chi', 'AI lập phiếu chi'), visit('bao', 'Báo kế toán', ['me', 'u2']),
            ]},
            {'label': 'Trưởng phòng từ chối', 'status': 'rejected', 'messages': [], 'path': [visit('ai_kiem', 'AI kiểm chứng từ'), visit('tp', 'Trưởng phòng duyệt', ['u3'], 'reject')]},
          ]}),
        _ => _json(pay),
      });

  Future<void> shot(WidgetTester tester, String name, Size size, Brightness b, Widget child, {Future<void> Function()? before}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: child)),
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

  Widget editor(Map<String, dynamic> def, {int tab = 0, Map<String, List<String>>? issues}) =>
      FlowEditorPage(app: app, api: FlowsApi('test'), doc: FlowDoc.fromJson(jsonDecode(jsonEncode(def)) as Map<String, dynamic>), initialTab: tab, debugIssues: issues);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('ảnh xem trước trình soạn quy trình', (tester) async {
    if (out == null) return;
    await tester.runAsync(_fonts);
    // Trang Quy trình: 2 tab + nút cài đặt (quản trị) + nút tạo luồng mới.
    await shot(tester, 'home-dang-chay', const Size(400, 720), Brightness.light, FlowsHome(app: app), before: () async {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.textContaining('ĐÃ KẾT THÚC'));
    });
    await shot(tester, 'home-cho-duyet', const Size(400, 720), Brightness.light, FlowsHome(app: app, initialTab: 1), before: () => tester.pump(const Duration(milliseconds: 200)));
    await shot(tester, 'tao-luong-moi', const Size(400, 860), Brightness.light, FlowStartPage(app: app, api: FlowsApi('test')), before: () => tester.pump(const Duration(milliseconds: 200)));
    await shot(tester, 'quan-ly-quy-trinh', const Size(400, 720), Brightness.light, FlowsAdminPage(app: app, api: FlowsApi('test')), before: () => tester.pump(const Duration(milliseconds: 200)));
    // Trường kiểu bảng.
    final orderForm = FlowField.listOf(order['form']);
    final rows = [
      {'ten': 'Cáp tải thang máy 10mm', 'so_luong': 120, 'don_gia': 85000},
      {'ten': 'Biến tần 7.5kW', 'so_luong': 2, 'don_gia': 15500000},
      {'ten': 'Nút gọi tầng', 'so_luong': 12, 'don_gia': 350000},
    ];
    Widget orderPage() => FlowFormPage(
          app: app,
          api: FlowsApi('test'),
          title: 'Đơn đặt hàng',
          askTitle: true,
          submitLabel: 'Bắt đầu luồng',
          fields: orderForm,
          initial: {'khach_hang': 'Cty Thang máy Hà Nội', 'san_pham': rows, 'ngay_giao': '2026-11-20'},
          onSubmit: (_, _) async {},
        );
    await shot(tester, 'bang-form-dien-thoai', const Size(400, 1500), Brightness.light, orderPage());
    await shot(tester, 'bang-form-may-tinh', const Size(1000, 900), Brightness.light, orderPage());
    await shot(tester, 'bang-chi-tiet', const Size(640, 240), Brightness.light,
        Builder(builder: (c) => Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: FlowTableView(field: orderForm[1], value: rows)))));
    final spJson = (order['form'] as List)[1] as Map<String, dynamic>;
    await shot(tester, 'bang-sua-truong', const Size(420, 1000), Brightness.light, Scaffold(body: FieldDialog(field: spJson)));
    final cols = [for (final c in spJson['columns'] as List) (c as Map).cast<String, dynamic>()];
    await shot(tester, 'bang-cot-tu-tinh', const Size(420, 760), Brightness.light, Scaffold(body: FieldDialog(field: cols[3], column: true, siblings: cols.sublist(0, 3))));
    final orderCond = (order['nodes'] as List).firstWhere((n) => n['id'] == 'chk')['rules'][0]['if'] as String;
    await shot(tester, 'bang-dieu-kien', const Size(420, 900), Brightness.light,
        Scaffold(body: CondDialog(app: app, expr: orderCond, vars: flowVars(FlowDoc.fromJson(order)))));
    await shot(tester, 'bang-so-do', const Size(420, 1100), Brightness.light, editor(order));
    await shot(tester, 'them-nhanh', const Size(420, 820), Brightness.light, editor(pay), before: () async {
      await tester.tap(find.text('Người tạo luồng điền'));
      await settle(tester);
      await tester.tap(find.byTooltip('Thêm nhanh'));
      await settle(tester);
    });
    // Tổ chức, ủy quyền, tất cả luồng, công cụ MCP, lịch, mẫu.
    final depts = [
      {'id': 'bgd', 'name': 'Ban giám đốc', 'manager': 'u4', 'members': ['u4']},
      {'id': 'kt', 'name': 'Kế toán', 'parent': 'bgd', 'manager': 'u5', 'members': ['u5', 'u2']},
      {'id': 'kd', 'name': 'Kinh doanh', 'parent': 'bgd', 'manager': 'u3', 'members': ['u3', 'me']},
      {'id': 'kdhn', 'name': 'Nhóm Hà Nội', 'parent': 'kd', 'members': ['me']},
    ];
    final orgRoles = {'giam_doc': ['u4'], 'ke_toan_truong': ['u5'], 'ke_toan': ['u2'], 'flow_admin': ['me'], 'thu_kho': <String>[]};
    await shot(tester, 'org-phong-ban', const Size(420, 720), Brightness.light, FlowsOrgPage(app: app, api: FlowsApi('test'), debugDepts: depts, debugRoles: orgRoles));
    await shot(tester, 'org-vai-tro', const Size(420, 720), Brightness.light, FlowsOrgPage(app: app, api: FlowsApi('test'), debugDepts: depts, debugRoles: orgRoles), before: () async {
      await tester.tap(find.text('Vai trò'));
      await settle(tester);
    });
    final depts2 = [
      {'id': 'bgd', 'name': 'Ban giám đốc', 'manager': 'u4'},
      {'id': 'kd', 'name': 'Kinh doanh', 'parent': 'bgd', 'manager': 'u3', 'deputies': ['u2', 'u5'], 'members': ['me']},
      {'id': 'kt', 'name': 'Kế toán', 'parent': 'bgd', 'manager': 'u5', 'members': ['me']},
    ];
    await shot(tester, 'org-chi-xem', const Size(420, 720), Brightness.light, FlowsOrgPage(app: app, api: FlowsApi('test'), debugDepts: depts2, debugReadOnly: true));
    await shot(tester, 'org-sua-phong', const Size(480, 760), Brightness.light, FlowsOrgPage(app: app, api: FlowsApi('test'), debugDepts: depts2, debugRoles: orgRoles), before: () async {
      await tester.tap(find.text('Kinh doanh'));
      await settle(tester);
    });
    final withStarts = jsonDecode(jsonEncode(stock)) as Map<String, dynamic>;
    withStarts['starts'] = [
      {'id': 'manual', 'type': 'manual'},
      {'id': 'interval', 'type': 'interval', 'seconds': 300},
      {'id': 'watch', 'type': 'watch', 'server': 'erp', 'tool': 'ton_kho', 'seconds': 900, 'cond': 'item.so_luong < 5'},
      {'id': 'web', 'type': 'webhook'},
    ];
    await shot(tester, 'bat-dau-so-do', const Size(760, 900), Brightness.light, editor(withStarts), before: () => tester.pump(const Duration(milliseconds: 300)));
    await shot(tester, 'bat-dau-chon-loai', const Size(420, 900), Brightness.light, editor(withStarts), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Thêm cách bắt đầu khác'));
      await settle(tester);
    });
    await shot(tester, 'bat-dau-theo-doi', const Size(420, 900), Brightness.light, editor(withStarts), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Theo dõi điều kiện'));
      await settle(tester);
    });
    await shot(tester, 'them-buoc-dien-thoai', const Size(420, 860), Brightness.light, editor(stock), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Thêm bước').first);
      await settle(tester);
      // Thu gọn hai nhóm đầu rồi mở ứng dụng ERP.
      await tester.tap(find.text('CON NGƯỜI'));
      await tester.tap(find.text('ĐIỀU KHIỂN LUỒNG'));
      await settle(tester);
      await tester.tap(find.text('ERP (ERPNEXT)'));
      await settle(tester);
    });
    await shot(tester, 'tab-uy-quyen', const Size(420, 860), Brightness.light, FlowsHome(app: app, initialTab: 2), before: () => tester.pump(const Duration(milliseconds: 300)));
    final leave = jsonDecode(jsonEncode(_fixture('nghi-phep.json'))) as Map<String, dynamic>;
    await shot(tester, 'dat-uy-quyen', const Size(420, 1100), Brightness.light, editor(leave), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.text('Áp dụng ủy quyền').last, 300, scrollable: find.byType(Scrollable).at(1));
      await tester.tap(find.text('Áp dụng ủy quyền').last);
      await settle(tester);
    });
    await shot(tester, 'yeu-cau-uy-quyen', const Size(420, 760), Brightness.light,
        DelegationRequestPage(app: app, api: FlowsApi('test'), taskId: 1, from: '2026-11-10', until: '2026-11-12'),
        before: () => tester.pump(const Duration(milliseconds: 300)));
    await shot(tester, 'truong-uy-quyen', const Size(420, 1300), Brightness.light,
        FlowFormPage(app: app, api: FlowsApi('test'), title: 'Xin nghỉ phép', fields: FlowField.listOf(leave['form']), flowId: 'nghi-phep', askTitle: true, submitLabel: 'Gửi', onSubmit: (_, _) async {}),
        before: () => tester.pump(const Duration(milliseconds: 300)));
    await shot(tester, 'truong-uy-quyen-chia', const Size(420, 1300), Brightness.light,
        FlowFormPage(app: app, api: FlowsApi('test'), title: 'Xin nghỉ phép', fields: FlowField.listOf(leave['form']), flowId: 'nghi-phep', onSubmit: (_, _) async {}, initial: {
          'uy_quyen': [
            {'flows': ['de-xuat-thanh-toan', 'tam-ung'], 'delegate': 'u2'},
            {'flows': ['de-xuat-mua-hang', 'nghi-phep'], 'delegate': 'u3'},
          ],
        }),
        before: () => tester.pump(const Duration(milliseconds: 300)));
    final calcOrder = jsonDecode(jsonEncode(_fixture('don-hang.json'))) as Map<String, dynamic>;
    (calcOrder['nodes'] as List).insert(1, {
      'id': 'tinh',
      'type': 'calc',
      'name': 'Tính toán',
      'vars': [
        {'name': 'tong_tien', 'label': 'Tổng tiền', 'op': 'sum', 'args': {'table': 'form.san_pham', 'col': 'thanh_tien'}},
        {'name': 'gia_cao_nhat', 'label': 'Đơn giá cao nhất', 'op': 'max', 'args': {'table': 'form.san_pham', 'col': 'don_gia'}},
        {'name': 'so_dong_lon', 'label': 'Số dòng từ 10 cái', 'op': 'count', 'args': {'table': 'form.san_pham', 'cond': 'item.so_luong >= 10'}},
        {'name': 'vat', 'label': 'Thuế VAT', 'op': 'pct', 'args': {'a': {'path': 'steps.tinh.output.tong_tien'}, 'b': {'value': 8}}},
      ],
    });
    final edges = calcOrder['edges'] as List;
    final first = edges.indexWhere((e) => (e as List)[0] == 'start');
    final next = (edges[first] as List)[1];
    edges[first] = ['start', 'tinh'];
    edges.add(['tinh', next]);
    await shot(tester, 'tinh-toan', const Size(420, 900), Brightness.light, editor(calcOrder), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.text('Tính toán').last, 300, scrollable: find.byType(Scrollable).at(1));
      await tester.tap(find.text('Tính toán').last);
      await settle(tester);
    });
    await shot(tester, 'tinh-toan-bien', const Size(480, 900), Brightness.light, editor(calcOrder), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.text('Tính toán').last, 300, scrollable: find.byType(Scrollable).at(1));
      await tester.tap(find.text('Tính toán').last);
      await settle(tester);
      await tester.tap(find.textContaining('Số dòng từ 10 cái =').last);
      await settle(tester);
    });
    await shot(tester, 'lich-lam-viec', const Size(420, 760), Brightness.light, FlowsOrgPage(app: app, api: FlowsApi('test'), debugDepts: depts2, debugRoles: orgRoles), before: () async {
      await tester.tap(find.text('Lịch làm việc'));
      await settle(tester);
    });
    final day = DateTime.now().millisecondsSinceEpoch;
    await shot(tester, 'bao-cao-van-hanh', const Size(420, 1300), Brightness.light, FlowsStatsPage(app: app, api: FlowsApi('test'), debugData: {
      'flows': [
        {'flow_name': 'Đề xuất thanh toán', 'started': 42, 'done': 35, 'running': 5, 'stopped': 2, 'avg_ms': 2.6 * 86400000},
        {'flow_name': 'Xin nghỉ phép', 'started': 18, 'done': 17, 'running': 1, 'stopped': 0, 'avg_ms': 9 * 3600000},
      ],
      'steps': [
        {'flow_name': 'Đề xuất thanh toán', 'step_name': 'Giám đốc duyệt', 'count': 37, 'avg_ms': 1.9 * 86400000, 'max_ms': 6 * 86400000},
        {'flow_name': 'Đề xuất thanh toán', 'step_name': 'Kế toán kiểm tra', 'count': 40, 'avg_ms': 5 * 3600000, 'max_ms': 30 * 3600000},
      ],
      'busy': [{'user': 'u4', 'open': 7, 'oldest': day - 4 * 86400000}, {'user': 'u2', 'open': 3, 'oldest': day - 3600000}],
      'stuck': [{'instance_id': 'i1', 'title': 'Mua cáp tải thang máy công trình Vinhomes', 'flow_name': 'Đề xuất thanh toán', 'step_name': 'Giám đốc duyệt', 'user': 'u4', 'since': day - 4 * 86400000}],
    }), before: () => tester.pump(const Duration(milliseconds: 200)));
    await shot(tester, 'goi-y-danh-muc', const Size(420, 520), Brightness.light, Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LookupField(api: FlowsApi('test'), flowId: 'x', field: 'kh', label: 'Khách hàng *', value: null, onPicked: (_) {}),
      ),
    ), before: () async {
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'thang');
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    });
    await shot(tester, 'uy-quyen', const Size(420, 760), Brightness.light, DelegationPage(app: app, api: FlowsApi('test')), before: () => tester.pump(const Duration(milliseconds: 200)));
    await shot(tester, 'tat-ca-luong', const Size(420, 760), Brightness.light, FlowsAllPage(app: app, api: FlowsApi('test')), before: () => tester.pump(const Duration(milliseconds: 200)));
    await shot(tester, 'cong-cu-mcp', const Size(420, 1100), Brightness.light, editor(stock), before: () async {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Tra tồn kho'));
      await settle(tester);
    });
    await shot(tester, 'lich-chay', const Size(420, 900), Brightness.light, editor(stock, tab: 1));
    await shot(tester, 'so-do-lich', const Size(420, 760), Brightness.light, editor(stock));
    await shot(tester, 'chon-mau', const Size(420, 820), Brightness.light, FlowsAdminPage(app: app, api: FlowsApi('test')), before: () async {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Tạo quy trình'));
      await settle(tester);
    });
    await shot(tester, 'home-dang-chay-2', const Size(400, 640), Brightness.light, FlowsHome(app: app), before: () => tester.pump(const Duration(milliseconds: 200)));
    await shot(tester, 'ai-chon-bot', const Size(420, 1000), Brightness.light, editor(pay), before: () async {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('AI kiểm chứng từ'));
      await settle(tester);
    });
    // Báo có: webhook → nhóm → tiếp nhận → chọn khách hàng.
    final bankDoc = jsonDecode(jsonEncode(bank)) as Map<String, dynamic>;
    bankDoc['nodes'][1]['channels'] = ['c1'];
    await shot(tester, 'bao-co-so-do', const Size(420, 1250), Brightness.light, editor(bankDoc), before: () => tester.pump(const Duration(milliseconds: 300)));
    await shot(tester, 'bao-co-webhook', const Size(420, 1500), Brightness.light, editor(bankDoc, tab: 1), before: () => tester.pump(const Duration(milliseconds: 300)));
    await shot(tester, 'bao-co-tiep-nhan', const Size(420, 900), Brightness.light, editor(bankDoc), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Kinh doanh tiếp nhận'));
      await settle(tester);
    });
    await shot(tester, 'bao-co-chon-nguoi', const Size(420, 1000), Brightness.light, editor(bankDoc), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Chọn khách hàng'));
      await settle(tester);
      await tester.tap(find.text('Đổi').first);
      await settle(tester);
    });
    // Tool tin nhắn: ghi chú + nút trên thẻ trong nhóm, rẽ nhánh theo nút đã bấm.
    final tools = jsonDecode(jsonEncode(bankDoc)) as Map<String, dynamic>;
    final nodes = (tools['nodes'] as List).cast<Map<String, dynamic>>();
    final at = nodes.indexWhere((n) => n['id'] == 'nhom') + 1;
    nodes.insertAll(at, [
      {'id': 'gc', 'type': 'auto', 'action': 'note_add', 'name': 'Ghi chú chờ nhận', 'params': {'message': {'step': 'nhom'}, 'text': 'Chờ kinh doanh xác nhận', 'color': 'orange'}},
      {'id': 'nut', 'type': 'buttons', 'name': 'Nút xác nhận', 'message': {'step': 'nhom'}, 'who': {'department': 'kinh_doanh'},
        'buttons': [{'label': 'Đã nhận'}, {'label': 'Không phải của tôi'}, {'label': 'Xem trên ERP', 'url': 'https://erp.example.com/tien/{{form.ma_gd}}'}]},
      {'id': 'sua', 'type': 'auto', 'action': 'note_edit', 'name': 'Sửa ghi chú', 'params': {'note_step': 'gc', 'text': 'Đã nhận', 'color': 'green'}},
    ]);
    nodes.removeWhere((n) => n['id'] == 'nhan');
    tools['edges'] = [['start', 'nhom'], ['nhom', 'gc'], ['gc', 'nut'], ['nut', 'sua'], ['sua', 'chon_kh'], ['chon_kh', 'kt'], ['kt', 'end']];
    for (final n in nodes) {
      if (n['id'] == 'chon_kh') n['assignee'] = {'field': 'steps.nut.output.by'};
    }
    await shot(tester, 'tool-so-do', const Size(420, 1350), Brightness.light, editor(tools), before: () => tester.pump(const Duration(milliseconds: 300)));
    await shot(tester, 'tool-nut', const Size(420, 1150), Brightness.light, editor(tools), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Nút xác nhận'));
      await settle(tester);
    });
    await shot(tester, 'tool-sua-ghi-chu', const Size(420, 800), Brightness.light, editor(tools), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Sửa ghi chú'));
      await settle(tester);
    });
    MmPost card(Map<String, dynamic> b) => MmPost({
          'id': 'p1', 'channel_id': 'c1', 'user_id': 'bot', 'message': '💰 Tiền về 15.000.000 đ (ACB): ACHAU TT DH 1023', 'create_at': _now, 'update_at': _now,
          'props': {'flygo_buttons': b},
        });
    final open = {'instance_id': 'i1', 'node': 'nut', 'state': 'open', 'who': ['me'],
      'buttons': [{'label': 'Đã nhận'}, {'label': 'Không phải của tôi'}, {'label': 'Xem trên ERP', 'url': 'https://erp.example.com/tien/FT2611050001'}]};
    await shot(tester, 'tool-nut-tren-tin', const Size(420, 260), Brightness.light, Builder(builder: (c) => Scaffold(body: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('💰 Tiền về 15.000.000 đ (ACB): ACHAU TT DH 1023'),
          FlowButtonsBar(app: app, post: card(open)),
          const SizedBox(height: 24),
          const Text('💰 Tiền về 8.200.000 đ (VPB): DONG A TT HD 77'),
          FlowButtonsBar(app: app, post: card({...open, 'state': 'closed', 'clicked': 'Đã nhận', 'by': 'u2'})),
        ])))));
    // Nhập kho: lặp qua từng dòng, nối quy trình khác; form có ngoại tệ, tự tính, chỉ hiện khi, danh mục.
    await shot(tester, 'lap-va-noi', const Size(420, 1300), Brightness.light, editor(nk), before: () => tester.pump(const Duration(milliseconds: 300)));
    await shot(tester, 'noi-quy-trinh', const Size(420, 1100), Brightness.light, editor(nk), before: () async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Mở khiếu nại NCC'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300));
    });
    final nkForm = FlowField.listOf(nk['form']);
    Widget nkPage(Map<String, dynamic> init) => FlowFormPage(
          app: app,
          api: FlowsApi('test'),
          title: 'Nhập kho & kiểm hàng',
          fields: nkForm,
          flowId: 'nhap-kho',
          initial: init,
          onSubmit: (_, _) async {},
        );
    await shot(tester, 'form-ngoai-te', const Size(400, 1250), Brightness.light,
        nkPage({'ncc': 'OTIS-VN', 'tong_usd': 12500.5, 'hang': [{'ma': 'CAP-10', 'sl': 120, 'loi': 0}, {'ma': 'BT-7', 'sl': 2, 'loi': 1}]}));
    await shot(tester, 'form-hien-ly-do', const Size(400, 1350), Brightness.light,
        nkPage({'ncc': 'OTIS-VN', 'tong_usd': 25000, 'hang': [{'ma': 'CAP-10', 'sl': 120, 'loi': 0}]}));
    final nkFields = (nk['form'] as List).cast<Map<String, dynamic>>();
    await shot(tester, 'truong-chi-hien-khi', const Size(420, 1000), Brightness.light, Scaffold(body: FieldDialog(
      field: nkFields[5],
      condVars: [for (final f in nkForm) if (f.key != 'ly_do' && f.type != 'table') CondVar('form.${f.key}', f.label, f.type)],
    )));
    // Sơ đồ.
    await shot(tester, 'editor-de-xuat-light', const Size(420, 1560), Brightness.light, editor(pay));
    await shot(tester, 'editor-de-xuat-dark', const Size(420, 1560), Brightness.dark, editor(pay));
    await shot(tester, 'editor-tam-ung-desktop', const Size(1100, 1480), Brightness.light, editor(adv));
    // Bước có lỗi (sau khi bấm Kiểm lỗi).
    await shot(tester, 'editor-loi', const Size(420, 760), Brightness.light,
        editor(pay, issues: {'tp': ['Vai trò "truong_phong" chưa có ai giữ'], 'chk': ['Biểu thức sai: form.so_tien >> 1']}));
    // Chèn bước.
    await shot(tester, 'editor-them-buoc', const Size(420, 860), Brightness.light, editor(pay), before: () async {
      await tester.tap(find.byTooltip('Thêm bước').at(1));
      await settle(tester);
    });
    // Cấu hình bước duyệt.
    await shot(tester, 'editor-cau-hinh-duyet', const Size(420, 900), Brightness.light, editor(pay), before: () async {
      await tester.tap(find.text('Trưởng phòng duyệt'));
      await settle(tester);
    });
    await shot(tester, 'editor-cau-hinh-ai', const Size(420, 1000), Brightness.light, editor(pay), before: () async {
      await tester.tap(find.text('AI kiểm chứng từ'));
      await settle(tester);
    });
    // Điều kiện nhánh.
    await shot(tester, 'editor-dieu-kien', const Size(420, 800), Brightness.light, editor(pay), before: () async {
      await tester.tap(find.textContaining('Nếu Số tiền'));
      await settle(tester);
    });
    // Biểu mẫu + cài đặt.
    await shot(tester, 'editor-nhap-du-lieu', const Size(420, 820), Brightness.light, editor(pay), before: () async {
      await tester.tap(find.text('Người tạo luồng điền'));
      await settle(tester);
    });
    await shot(tester, 'editor-sua-truong', const Size(420, 900), Brightness.light, editor(pay), before: () async {
      await tester.tap(find.text('Người tạo luồng điền'));
      await settle(tester);
      await tester.tap(find.text('Loại chi *').last);
      await settle(tester);
    });
    await shot(tester, 'editor-cai-dat', const Size(420, 700), Brightness.light, editor(pay, tab: 1));
    // Điều kiện VÀ / HOẶC.
    final mixed = jsonDecode(jsonEncode(pay)) as Map<String, dynamic>;
    for (final n in mixed['nodes'] as List) {
      if (n['id'] == 'chk') n['rules'][0]['if'] = 'form.so_tien > 20000000 and form.loai == "Mua vật tư" or steps.ai_kiem.output.khop == false';
    }
    await shot(tester, 'editor-dieu-kien-va-hoac', const Size(420, 1100), Brightness.light, editor(mixed), before: () async {
      await tester.tap(find.textContaining('Nếu ('));
      await settle(tester);
    });
    await shot(tester, 'editor-nhanh-va-hoac', const Size(420, 1000), Brightness.light, editor(mixed));
    // Chạy thử.
    await shot(tester, 'editor-chay-thu', const Size(420, 900), Brightness.light, editor(pay), before: () async {
      await tester.tap(find.byTooltip('Thao tác'));
      await settle(tester);
      await tester.tap(find.text('Chạy thử'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
