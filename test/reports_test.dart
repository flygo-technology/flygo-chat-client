// App Báo cáo: dựng màn hình thật với dữ liệu mẫu (không gọi máy chủ). Kiểm danh sách, bản báo cáo, đủ 13 loại biểu đồ,
// bảng nguồn. Ảnh chụp duyệt thiết kế: MK_OUT=<thư mục> flutter test test/reports_test.dart (cần font thật).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/reports/api.dart';
import 'package:flygo_chat/ui/reports/blocks.dart';
import 'package:flygo_chat/ui/reports/edition_page.dart';
import 'package:flygo_chat/ui/reports/reports_page.dart';
import 'package:flygo_chat/ui/theme.dart';

// ---------------------------------------------------------------- dữ liệu mẫu (số tự đặt, tên chung chung)
const _bank = {'tool': 'vn_demo_bank__list_transactions', 'calc': 'sum(amount) where direction=in, date=hôm qua', 'as_of': '2026-11-16T07:20:00+07:00'};
const _sales = {'tool': 'vn_demo_erp__sales_by_day', 'calc': 'sum(revenue) group by day', 'as_of': '2026-11-16T06:00:00+07:00'};
const _debt = {'tool': 'vn_demo_erp__debt_balance', 'calc': 'overdue > 30 ngày', 'as_of': '2026-11-16T06:00:00+07:00'};
final _t0 = DateTime.utc(2026, 11, 16, 0, 30).millisecondsSinceEpoch;

final _morningBlocks = <Json>[
  {'id': 'tien_ve', 'type': 'kpi', 'section': 'Dòng tiền', 'title': 'Tiền về hôm qua', 'value': 1284350000, 'unit': 'VND', 'compare': {'label': 'TB 7 ngày', 'value': 1088440000},
    'trend': [620, 880, 410, 1530, 960, 720, 1090, 830, 1210, 1284], 'source': _bank},
  {'id': 'so_du', 'type': 'kpi', 'section': 'Dòng tiền', 'title': 'Số dư 4 tài khoản', 'value': 8920000000, 'unit': 'VND', 'compare': {'label': 'hôm qua', 'value': 9560000000},
    'source': {..._bank, 'tool': 'vn_demo_bank__get_balance'}},
  {'id': 'dong_tien', 'type': 'waterfall', 'section': 'Dòng tiền', 'title': 'Số dư đầu ngày đến cuối ngày', 'unit': 'VND', 'start': 9560000000,
    'labels': ['Thu khách', 'Thu khác', 'Trả NCC', 'Lương', 'Thuế'], 'values': [1210000000, 74350000, -1380000000, -420000000, -124350000], 'source': _bank},
  {'id': 'chi_lon', 'type': 'alert', 'section': 'Dòng tiền', 'level': 'warn', 'title': 'Chi bất thường', 'text': 'Khoản trả NCC lớn nhất gấp **3,1 lần** trung bình 30 ngày của NCC này.'},
  {'id': 'doanh_so', 'type': 'kpi', 'section': 'Kinh doanh', 'title': 'Doanh số tháng 11', 'value': 6450000000, 'unit': 'VND', 'target': 15000000000, 'source': _sales},
  {'id': 'no_qua_han', 'type': 'kpi', 'section': 'Kinh doanh', 'title': 'Nợ quá hạn > 30 ngày', 'value': 2310000000, 'unit': 'VND', 'good': 'down',
    'compare': {'label': 'tuần trước', 'value': 2210000000}, 'source': _debt},
  {'id': 'luy_ke', 'type': 'area', 'section': 'Kinh doanh', 'title': 'Doanh số luỹ kế tháng', 'unit': 'VND',
    'x': [for (var d = 1; d <= 14; d++) '$d/11'],
    'series': [
      {'name': 'Tháng 11', 'values': [180, 420, 650, 980, 1250, 1610, 1890, 2420, 2980, 3560, 4210, 4870, 5530, 6450].map((v) => v * 1e6).toList()},
      {'name': 'Tháng 10 cùng kỳ', 'values': [150, 380, 700, 1010, 1340, 1500, 1820, 2300, 2760, 3200, 3790, 4300, 4850, 5400].map((v) => v * 1e6).toList()},
    ], 'source': _sales},
  {'id': 'theo_nv', 'type': 'progress', 'section': 'Kinh doanh', 'title': 'Doanh số theo nhân viên so kế hoạch', 'unit': 'VND',
    'progress': [{'label': 'NV An', 'value': 2100000000, 'target': 4000000000}, {'label': 'NV Bình', 'value': 1850000000, 'target': 4000000000},
      {'label': 'NV Chi', 'value': 1620000000, 'target': 3500000000}, {'label': 'NV Dũng', 'value': 880000000, 'target': 3500000000}], 'source': _sales},
  {'id': 'top_no', 'type': 'table', 'section': 'Công nợ', 'title': 'Top khách nợ quá hạn',
    'columns': [{'key': 'khach', 'label': 'Khách', 'type': 'text'}, {'key': 'no', 'label': 'Quá hạn', 'type': 'money'}, {'key': 'ngay', 'label': 'Ngày', 'type': 'number'}],
    'rows': [{'khach': 'Khách hàng A', 'no': 640000000, 'ngay': 74}, {'khach': 'Khách hàng B', 'no': 515000000, 'ngay': 52}, {'khach': 'Khách hàng C', 'no': 298000000, 'ngay': 31}],
    'source': _debt},
  {'id': 'viec', 'type': 'todo', 'section': 'Đề nghị', 'title': 'Việc nên làm hôm nay',
    'items': [{'text': 'Gọi Khách hàng C trước 18/11 (nợ mới quá hạn)', 'assignee': 'P. Kinh doanh'}, {'text': 'Xác nhận khoản trả NCC lớn với kế toán', 'assignee': 'Kế toán'}]},
];

final _allBlocks = <Json>[
  {'id': 'a', 'type': 'line', 'title': 'Đường: tiền về 10 ngày', 'unit': 'VND', 'x': [for (var d = 7; d <= 16; d++) '$d/11'],
    'series': [{'name': 'Tiền về', 'values': [620, 880, 410, 1530, 960, 720, 1090, 830, 1210, 1284].map((v) => v * 1e6).toList()}], 'source': _bank},
  {'id': 'b', 'type': 'bar', 'title': 'Cột nhóm: doanh số theo chi nhánh', 'unit': 'VND', 'labels': ['Hà Nội', 'TP.HCM', 'Đà Nẵng'],
    'series': [{'name': 'Tháng 10', 'values': [3.1e9, 2.4e9, 0.8e9]}, {'name': 'Tháng 11', 'values': [3.4e9, 2.2e9, 0.85e9]}], 'source': _sales},
  {'id': 'c', 'type': 'stacked_bar', 'title': 'Cột chồng: doanh số theo tháng và nhóm hàng', 'unit': 'VND', 'labels': ['T8', 'T9', 'T10', 'T11'],
    'series': [{'name': 'Thiết bị', 'values': [3.2e9, 3.6e9, 3.9e9, 3.5e9]}, {'name': 'Linh kiện', 'values': [1.4e9, 1.5e9, 1.8e9, 1.9e9]}, {'name': 'Dịch vụ', 'values': [0.6e9, 0.7e9, 0.6e9, 1.05e9]}],
    'source': _sales},
  {'id': 'd', 'type': 'hbar', 'title': 'Cột ngang: top 5 khách theo doanh số', 'unit': 'VND', 'labels': ['Khách hàng A', 'Khách hàng B', 'Khách hàng C', 'Khách hàng D', 'Khách hàng E'],
    'values': [1.82e9, 1.31e9, 0.96e9, 0.74e9, 0.52e9], 'highlight': 0, 'source': _sales},
  {'id': 'e', 'type': 'pie', 'title': 'Tỉ trọng: doanh thu theo kênh', 'unit': 'VND', 'labels': ['Dự án', 'Đại lý', 'Bán lẻ', 'Khác'], 'values': [3.9e9, 1.6e9, 0.7e9, 0.25e9], 'source': _sales},
  {'id': 'f', 'type': 'gauge', 'title': 'Đồng hồ: doanh số so kế hoạch tháng', 'unit': 'VND', 'value': 6.45e9, 'max': 15e9, 'target': 6.5e9, 'source': _sales},
  {'id': 'g', 'type': 'funnel', 'title': 'Phễu: từ khách tiềm năng đến thu tiền', 'unit': 'khách', 'labels': ['Tiềm năng', 'Báo giá', 'Hợp đồng', 'Đã thu tiền'], 'values': [120, 46, 18, 11],
    'source': {'tool': 'vn_demo_crm__pipeline', 'as_of': '2026-11-16T06:00:00+07:00'}},
  {'id': 'h', 'type': 'waterfall', 'title': 'Thác nước: dòng tiền tuần', 'unit': 'VND', 'start': 9.1e9, 'labels': ['Thu', 'Trả NCC', 'Lương', 'Khác'], 'values': [4.47e9, -3.1e9, -1.2e9, 0.35e9], 'source': _bank},
  {'id': 'i', 'type': 'scatter', 'title': 'Phân tán: tuổi nợ và số nợ theo khách', 'x_label': 'Tuổi nợ (ngày)', 'y_label': 'Số nợ', 'unit': 'ngày', 'y_unit': 'VND',
    'points': [{'x': 74, 'y': 640e6, 'label': 'Khách hàng A'}, {'x': 52, 'y': 515e6, 'label': 'Khách hàng B'}, {'x': 31, 'y': 298e6, 'label': 'Khách hàng C'}, {'x': 45, 'y': 180e6, 'label': 'Khách hàng D'},
      {'x': 90, 'y': 120e6, 'label': 'Khách hàng E'}, {'x': 38, 'y': 410e6, 'label': 'Khách hàng F'}], 'source': _debt},
  {'id': 'j', 'type': 'heatmap', 'title': 'Bản đồ nhiệt: tiền về theo thứ × tuần', 'unit': 'VND', 'x': ['T2', 'T3', 'T4', 'T5', 'T6', 'T7'], 'y': ['Tuần 43', 'Tuần 44', 'Tuần 45', 'Tuần 46'],
    'matrix': [[0.9e9, 1.1e9, 0.7e9, 1.3e9, 1.6e9, 0.4e9], [1.0e9, 0.8e9, 0.9e9, 1.2e9, 1.9e9, 0.3e9], [1.2e9, 1.0e9, 1.1e9, 1.4e9, 1.7e9, 0.5e9], [1.1e9, 1.3e9, 0.9e9, 1.28e9, 0, 0]],
    'source': _bank},
  {'id': 'k', 'type': 'treemap', 'title': 'Treemap: giá trị tồn kho theo nhóm hàng', 'unit': 'VND', 'labels': ['Thiết bị chính', 'Cáp', 'Bo mạch', 'Cửa', 'Ray', 'Phụ kiện', 'Khác'],
    'values': [4.2e9, 2.1e9, 1.6e9, 1.2e9, 0.8e9, 0.5e9, 0.3e9], 'source': {'tool': 'vn_demo_erp__inventory_balance', 'as_of': '2026-11-16T06:00:00+07:00'}},
  {'id': 'l', 'type': 'progress', 'title': 'Tiến độ: doanh số chi nhánh so kế hoạch', 'unit': 'VND',
    'progress': [{'label': 'Hà Nội', 'value': 3.4e9, 'target': 7e9}, {'label': 'TP.HCM', 'value': 2.2e9, 'target': 6e9}, {'label': 'Đà Nẵng', 'value': 0.85e9, 'target': 2e9}], 'source': _sales},
  {'id': 'm', 'type': 'area', 'title': 'Vùng: số dư cuối ngày', 'unit': 'VND', 'x': [for (var d = 7; d <= 16; d++) '$d/11'],
    'series': [{'name': 'Số dư', 'values': [8.1e9, 8.4e9, 8.0e9, 8.9e9, 9.2e9, 9.0e9, 9.4e9, 9.3e9, 9.56e9, 8.92e9]}], 'source': {..._bank, 'tool': 'vn_demo_bank__get_balance'}},
];

Json _report(String id, String title, String icon, String color, {String? when, bool unread = false, List<Json> kpis = const [], int alerts = 0, int seq = 1, bool sensitive = false}) => {
      'id': id, 'title': title, 'description': '', 'template': null, 'icon': icon, 'color': color, 'sensitive': sensitive, 'notify': true,
      'schedule': when == null ? null : {'prompt': 'Mỗi sáng cho anh: tiền về và chi hôm qua, số dư, doanh số tháng so kế hoạch, khách nợ quá hạn. Có gì bất thường thì báo.', 'when': when},
      'owner': 'u1', 'owner_name': 'Giám đốc', 'role': 'owner', 'editions': seq,
      'last': {'id': '$id-e$seq', 'seq': seq, 'title': title, 'period': '16/11/2026', 'as_of': '2026-11-16T06:00:00+07:00', 'created_at': _t0, 'kpis': kpis, 'alerts': alerts, 'unread': unread, 'by_ai': true},
      'created_at': _t0, 'updated_at': _t0,
    };

final _reports = <Json>[
  _report('rpmorning01', 'Báo cáo sáng · Ban giám đốc', 'wb_sunny', '#4B55C9', when: '07:30 thứ Hai – thứ Bảy', unread: true, seq: 212, alerts: 1,
      kpis: [{'title': 'Tiền về', 'value': '1,28 tỷ', 'delta': .18, 'good': 'up'}, {'title': 'DS tháng', 'value': '6,45 tỷ', 'delta': null, 'good': 'up'}]),
  _report('rpcashflow1', 'Dòng tiền tuần 46 so với tuần 45', 'account_balance', '#1A8F4E', unread: true, sensitive: true,
      kpis: [{'title': 'Tiền về', 'value': '4,47 tỷ', 'delta': .12, 'good': 'up'}, {'title': 'Tiền chi', 'value': '3,1 tỷ', 'delta': .21, 'good': 'down'}]),
  _report('rpcharts001', 'Mẫu đủ 13 loại biểu đồ', 'trending_up', '#6B4FD6', seq: 3),
  _report('rpdebt00001', 'Công nợ quá hạn theo khách', 'schedule', '#C62828', when: 'Thứ Hai 07:30', seq: 46,
      kpis: [{'title': 'Quá hạn', 'value': '2,31 tỷ', 'delta': .045, 'good': 'down'}]),
  _report('rpstock0001', 'Tồn kho cần đặt hàng', 'inventory_2', '#B26A00', when: '07:00 hằng ngày', seq: 88, kpis: [{'title': 'Cần đặt', 'value': '14 mã', 'delta': null, 'good': 'up'}]),
];

Json _edition(String rid, List<Json> blocks, {required String summary, int seq = 212}) {
  final r = _reports.firstWhere((x) => x['id'] == rid);
  return {
    'id': '$rid-e$seq', 'report': rid, 'report_title': r['title'], 'seq': seq, 'title': '${r['title']} — 16/11/2026', 'period': 'Thứ Hai, 16/11/2026',
    'as_of': '2026-11-16T06:00:00+07:00', 'author': 'u1', 'act': 'agent:bot1', 'model': 'claude', 'duration_ms': 14000, 'created_at': _t0, 'updated_at': _t0,
    'role': 'owner', 'sensitive': r['sensitive'], 'summary': summary, 'summary_raw': summary, 'blocks': blocks,
    'checks': {'numeric': blocks.where((b) => b['source'] != null).length, 'with_tool': blocks.where((b) => b['source'] != null).length, 'bare_numbers': []},
    'prev': {'id': '$rid-e${seq - 1}', 'seq': seq - 1, 'period': '14/11/2026', 'created_at': _t0 - 86400000, 'kpi': {'doanh_so': 6050000000}},
    'next': null, 'viewers': 3, 'comments': 1, 'author_name': 'Giám đốc',
  };
}

class FakeSource implements ReportsSource {
  final calls = <String>[];
  @override
  Future<Json> get(String path, [Map<String, String>? q]) async {
    calls.add(path);
    if (path == '/api/reports') return {'reports': _reports};
    final m = RegExp(r'^/api/reports/([A-Za-z0-9_-]+)(/[a-z]+)?$').firstMatch(path);
    final e = RegExp(r'^/api/editions/([A-Za-z0-9_-]+)(/[a-z]+)?$').firstMatch(path);
    final rid = m?.group(1) ?? e?.group(1)?.split('-e').first ?? '';
    final ed = rid == 'rpcharts001'
        ? _edition(rid, _allBlocks, seq: 3, summary: 'Mẫu các loại biểu đồ app vẽ native. AI chọn loại theo dữ liệu.')
        : _edition(rid, _morningBlocks,
            summary: '- Hôm qua **tiền về 1,28 tỷ**, cao hơn trung bình 7 ngày **+18%**.\n- Doanh số tháng 11 đạt **43%** kế hoạch, tiến độ thời gian 53%: đang chậm.\n'
                '- Nợ quá hạn tăng **+4,5%**: thêm Khách hàng C.');
    final sub = m?.group(2) ?? e?.group(2);
    if (sub == '/latest' || (e != null && sub == null)) return {'edition': ed};
    if (sub == '/editions') {
      return {'editions': [for (var i = 0; i < 6; i++) {...ed, 'id': '$rid-e${(ed['seq'] as int) - i}', 'seq': (ed['seq'] as int) - i, 'period': '${16 - i}/11/2026', 'created_at': _t0 - i * 86400000}]};
    }
    if (sub == '/comments') return {'comments': [{'id': 'c1', 'author': 'u2', 'author_name': 'Kế toán trưởng', 'by_ai': false, 'text': 'Khoản trả NCC là đợt 2 theo hợp đồng, đúng hạn.', 'created_at': _t0 + 1200000}]};
    if (m != null) return {'report': _reports.firstWhere((x) => x['id'] == rid), 'members': [{'kind': 'role', 'ref': 'bgd', 'role': 'viewer', 'name': 'Ban giám đốc'}]};
    throw ReportsException(404, 'không có');
  }

  @override
  Future<Json> post(String path, [Object? body]) async => {'comment': {}};
  @override
  Future<Json> put(String path, Object body) async => {};
  @override
  Future<Json> delete(String path) async => {'ok': true};
  @override
  Future<Uint8List> bytes(String path, [Map<String, String>? q]) async => Uint8List(0);
  @override
  Future<ReportsLive?> live({List<String> reports = const [], bool all = false}) async => null;
}

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f.startsWith('/') ? f : '$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  await load('JetBrains Mono', ['${Directory.current.path}/assets/fonts/JetBrainsMono-Regular.ttf']);
}

void main() {
  final out = Platform.environment['MK_OUT'];
  setUpAll(() async {
    if (out != null) await _fonts();
  });

  Future<void> pumpScreen(WidgetTester t, Widget w, {Size size = const Size(412, 900), bool dark = false}) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(dark ? Brightness.dark : Brightness.light), home: RepaintBoundary(key: const Key('shot'), child: w)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const Key('shot'))) as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('danh sách: báo cáo mới lên đầu, KPI chính, điểm cần chú ý', (t) async {
    await pumpScreen(t, ReportsHome(api: FakeSource()));
    expect(find.text('MỚI'), findsNWidgets(3)); // 2 thẻ + tiêu đề mục
    expect(find.text('Báo cáo sáng · Ban giám đốc'), findsOneWidget);
    expect(find.textContaining('1 điểm cần chú ý'), findsOneWidget);
    expect(find.text('Nhờ AI'), findsOneWidget);
    await shot(t, '01-danh-sach-phone');
  });

  testWidgets('bản báo cáo sáng: tóm tắt, KPI, thác nước, tiến độ, bảng, bình luận', (t) async {
    await pumpScreen(t, EditionPage(api: FakeSource(), reportId: 'rpmorning01'), size: const Size(412, 3300));
    expect(find.text('Thứ Hai, 16/11/2026'), findsOneWidget);
    expect(find.text('Tiền về hôm qua'), findsOneWidget);
    expect(find.textContaining('8/8 khối có nguồn'), findsOneWidget);
    expect(find.text('Top khách nợ quá hạn'), findsOneWidget);
    expect(find.textContaining('đợt 2 theo hợp đồng'), findsOneWidget);
    await shot(t, '02-ban-bao-cao-sang-phone');
    await t.tap(find.text('Tiền về hôm qua'));
    await t.pumpAndSettle();
    expect(find.text('vn_demo_bank__list_transactions'), findsWidgets);
    expect(find.text('AI lấy bằng'), findsOneWidget);
  });

  testWidgets('đủ 13 loại biểu đồ vẽ được (sáng + tối)', (t) async {
    for (final dark in [false, true]) {
      await pumpScreen(t, EditionPage(api: FakeSource(), reportId: 'rpcharts001'), size: const Size(412, 5200), dark: dark);
      expect(t.takeException(), isNull);
      for (final b in _allBlocks) {
        expect(find.text('${b['title']}'), findsOneWidget, reason: '${b['type']}');
      }
      expect(find.byType(BlockView), findsNWidgets(13));
      await shot(t, dark ? '05-13-loai-bieu-do-phone-toi' : '04-13-loai-bieu-do-phone');
    }
  });

  testWidgets('nguồn số liệu khi chạm', (t) async {
    await pumpScreen(t, EditionPage(api: FakeSource(), reportId: 'rpmorning01'), size: const Size(412, 900));
    await t.tap(find.text('Tiền về hôm qua'));
    await t.pumpAndSettle();
    await shot(t, '03-nguon-so-lieu-phone');
  });

  testWidgets('máy tính: danh sách trái, bản báo cáo phải (có cột các bản)', (t) async {
    await pumpScreen(t, ReportsHome(api: FakeSource(), initialSelected: 'rpmorning01'), size: const Size(1440, 900));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Nhờ AI lập báo cáo'), findsOneWidget);
    expect(find.byType(EditionPage), findsOneWidget);
    await shot(t, '06-desktop');
    await pumpScreen(t, EditionPage(api: FakeSource(), reportId: 'rpcharts001'), size: const Size(1440, 900));
    expect(find.text('CÁC BẢN'), findsOneWidget);
    await shot(t, '07-desktop-bieu-do');
  });

  testWidgets('bản báo cáo nền tối', (t) async {
    await pumpScreen(t, EditionPage(api: FakeSource(), reportId: 'rpmorning01'), size: const Size(412, 1400), dark: true);
    await shot(t, '08-ban-bao-cao-phone-toi');
  });

  test('định dạng số giống máy chủ', () {
    expect(fmtValue(1284350000, 'VND'), '1,28 tỷ');
    expect(fmtValue(380000000, 'VND'), '380 tr');
    expect(fmtValue(42.35, '%'), '42,4%');
    expect(fmtValue(1234567), '1.234.567');
    expect(fmtAsOf('2026-11-16T07:20:00+07:00'), '07:20 16/11');
  });
}
