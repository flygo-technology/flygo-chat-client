// Trang một quy trình trên máy tính (2 cột: danh sách | chi tiết hoặc giới thiệu + thống kê), chi tiết 2 cột (quá trình
// chạy | thao tác), hộp nổi "Tạo tiến trình mới", tiêu đề tab. Ảnh xem trước (chạy tay):
// EDITOR_OUT=<thư mục> flutter test test/workflow_page_test.dart
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
import 'package:flygo_chat/ui/desk_tabs.dart' show DeskTabScope;
import 'package:flygo_chat/ui/flows/flow_doc.dart' show FlowDoc;
import 'package:flygo_chat/ui/flows/flow_editor.dart' show FlowEditorPage, canLeaveFlowEditor;
import 'package:flygo_chat/ui/flows/flow_form.dart' show FlowFormPage;
import 'package:flygo_chat/ui/home_page.dart' show ChatHost, PageCloser;
import 'package:flygo_chat/ui/flows/flows_page.dart' show FlowDetailPage, FlowsHome;
import 'package:flygo_chat/ui/flows/process_chat.dart';
import 'package:flygo_chat/ui/flows/process_detail.dart' show ProcessDetailPage;
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

void main() {
  final out = Platform.environment['EDITOR_OUT'];
  kServerUrl = 'https://chat.test';
  final app = AppState('tok-me')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  app.users['u2'] = MmUser({'id': 'u2', 'username': 'lan', 'first_name': 'Lan Kế toán'});
  final now = DateTime.now().millisecondsSinceEpoch;
  final requests = <Uri>[];
  // Thời gian theo bước (GET /flows/reports/steps) của quy trình có tiến trình.
  final stepsRep = {
    'flow': 'linkq', 'total': 42,
    'steps': [
      {'key': 'nhan', 'title': 'Nhận hoá đơn', 'sla': '4h', 'count': 40, 'active': 2, 'avg_ms': 25 * 60000, 'p50_ms': 20 * 60000, 'p90_ms': 50 * 60000, 'overdue': 0},
      {'key': 'kiem', 'title': 'Kiểm tra trùng', 'sla': '1d', 'count': 36, 'active': 4, 'avg_ms': 3 * 3600000, 'p50_ms': 2 * 3600000, 'p90_ms': 9 * 3600000, 'overdue': 3},
      {'key': 'ky', 'title': 'Kế toán ký', 'sla': '2wd', 'count': 27, 'active': 9, 'avg_ms': 30 * 3600000, 'p50_ms': 26 * 3600000, 'p90_ms': 70 * 3600000, 'overdue': 5},
      {'key': 'gui', 'title': 'Gửi khách', 'count': 25, 'active': 0, 'avg_ms': 10 * 60000, 'p50_ms': 8 * 60000, 'p90_ms': 15 * 60000, 'overdue': 0},
    ],
  };

  List<Map<String, dynamic>> steps(int at) => [
        for (final (i, (k, t)) in [('nhan', 'Nhận hoá đơn'), ('kiem', 'Kiểm tra trùng'), ('ky', 'Kế toán ký'), ('gui', 'Gửi khách')].indexed)
          {'key': k, 'title': t, 'state': i < at ? 'done' : (i == at ? 'active' : 'pending')},
      ];
  Map<String, dynamic> proc(String id, String name, int at, String status, String tone, List<String> labels) => {
        'id': id, 'flow_id': 'linkq', 'flow_name': 'Đồng bộ hoá đơn LinkQ', 'flow_icon': '🧾', 'key': 'k-$id', 'name': name, 'icon': '🧾',
        'state': 'running', 'current_step': steps(at)[at]['key'], 'status_text': status, 'tone': tone, 'steps': steps(at),
        'stats': [
          {'key': 'amount', 'label': 'Tổng tiền', 'type': 'number', 'value': 128450000},
          {'key': 'buyer', 'label': 'Bên mua', 'type': 'text', 'value': 'Cty Hoàng Long'},
        ],
        'labels': labels, 'created_at': now - 3600000, 'updated_at': now - 600000, 'finished_at': null,
      };
  final procs = [
    {...proc('P-8K2Q4M', 'Hoá đơn 2154 · Cty Hoàng Long', 2, 'Chờ kế toán ký', 'orange', ['KLTM']), 'discussion_channel_id': 'pch-P-8K2Q4M'},
    proc('P-7Z1XQ2', 'Hoá đơn 2155 · Cty Minh Phát', 1, 'Đang kiểm tra trùng', 'blue', ['Nghi trùng']),
    proc('P-5R6T7Y', 'Hoá đơn 2156 · Cty Sao Việt', 0, 'Mới nhận', 'gray', const []),
  ];
  final procDetail = {
    ...procs.first,
    'instance_id': 'i-77',
    'files': [
      {'name': 'hoadon-2154.pdf', 'kind': 'file', 'file_id': 'f1', 'size': 182400, 'at': now - 3000000},
      {'name': 'Chứng từ LinkQ', 'kind': 'link', 'url': 'https://linkq.vn/ct/2154', 'at': now - 2000000},
    ],
    'posts': [
      {'target': 'channel:c-kt', 'channel_id': 'c-kt', 'post_id': 'post-1', 'sync': true},
    ],
    'events': [
      {'at': now - 3600000, 'actor': null, 'node': 'tao', 'node_name': 'Nhận hoá đơn từ LinkQ', 'kind': 'create', 'data': {'key': 'k-P-8K2Q4M'}},
      {'at': now - 2400000, 'actor': null, 'node': 'b_kiem', 'node_name': 'Kiểm tra trùng bằng AI', 'kind': 'step', 'data': {'step': 'kiem', 'status_text': 'Đang kiểm tra trùng'}},
      {'at': now - 1800000, 'actor': null, 'node': 'st', 'node_name': 'Cộng tiền', 'kind': 'stat', 'data': [{'key': 'amount', 'value': 128450000}]},
      {'at': now - 1200000, 'actor': 'u2', 'node': 'b_ky', 'node_name': 'Chuyển sang ký', 'kind': 'step', 'data': {'step': 'ky', 'status_text': 'Chờ kế toán ký'}},
    ],
    'actions': [
      {'wait': 'ky', 'kind': 'buttons', 'prompt': 'Kế toán xác nhận hoá đơn', 'actions': [
        {'id': 'ok', 'label': 'Đồng ý', 'style': 'primary'},
        {'id': 'no', 'label': 'Trả lại', 'style': 'danger'},
      ]},
    ],
  };
  final procReport = {
    'total': 42,
    'by_state': {'running': 12, 'failed': 3, 'done': 25, 'cancelled': 2},
    'by_step': [
      {'key': 'nhan', 'title': 'Nhận hoá đơn', 'count': 2},
      {'key': 'kiem', 'title': 'Kiểm tra trùng', 'count': 4},
      {'key': 'ky', 'title': 'Kế toán ký', 'count': 9},
    ],
    'stats': [
      {'key': 'amount', 'label': 'Tổng tiền', 'sum': 5394900000, 'avg': 128450000, 'count': 42},
    ],
    'daily': [
      for (var i = 0; i < 14; i++) {'date': '2026-10-${(25 + i > 31 ? 25 + i - 31 : 25 + i).toString().padLeft(2, '0')}', 'created': (i * 7) % 6 + 1, 'done': (i * 5) % 4, 'failed': i % 5 == 0 ? 1 : 0},
    ],
  };
  Map<String, dynamic> info(String id, String name, String icon, {String desc = ''}) => {
        'id': id, 'name': name, 'icon': icon, 'category': 'Kế toán', 'description': desc, 'version': 3, 'active': true, 'can_start': true,
        'who_can_start': [
          {'kind': 'department', 'id': 'kt', 'name': 'Kế toán'},
          {'kind': 'role', 'id': 'ke_toan_truong', 'name': 'ke_toan_truong', 'members': 2},
          {'kind': 'role', 'id': 'kiem_soat', 'name': 'Kiểm soát nội bộ', 'members': 1},
          {'kind': 'user', 'id': 'u2', 'name': 'Lan Kế toán'},
        ],
        'valid_from': '2026-01-01', 'valid_until': '2026-12-31',
        'steps': [
          {'id': 'nhan', 'no': 2, 'name': 'Nhận hoá đơn từ LinkQ', 'type': 'auto'},
          {'id': 'kiem', 'no': 3, 'name': 'Kiểm tra trùng', 'type': 'ai'},
          {'id': 'ky', 'no': 4, 'name': 'Kế toán ký', 'type': 'approval_request'},
          {'id': 'gui', 'no': 5, 'name': 'Gửi khách', 'type': 'send'},
        ],
      };
  final runDef = {
    'id': 'nghiphep', 'name': 'Đơn nghỉ phép', 'icon': '🌴',
    'form': [
      {'key': 'tu', 'label': 'Từ ngày', 'type': 'date'},
      {'key': 'so_ngay', 'label': 'Số ngày', 'type': 'number'},
      {'key': 'ly_do', 'label': 'Lý do', 'type': 'textarea'},
    ],
    'nodes': [
      {'id': 'start', 'type': 'start'},
      {'id': 'duyet', 'no': 2, 'type': 'approval_request', 'name': 'Trưởng phòng duyệt', 'approver': {'manager': '\$requester'}},
      {'id': 'bao', 'no': 3, 'type': 'send', 'name': 'Báo nhân sự'},
      {'id': 'sua', 'no': 4, 'type': 'form_task', 'name': 'Bổ sung giấy tờ'},
      {'id': 'end', 'type': 'end'},
    ],
    'edges': [['start', 'duyet'], ['duyet', 'bao'], ['bao', 'end']],
  };
  Map<String, dynamic> run(String id, String title, String status, {String requester = 'u2', int ago = 3600000}) => {
        'id': id, 'flow_id': 'nghiphep', 'flow_version': 2, 'title': title, 'status': status, 'requester': requester,
        'created_at': now - ago, 'updated_at': now - ago ~/ 2, 'flow_name': 'Đơn nghỉ phép', 'flow_icon': '🌴',
        'current': status == 'running' ? ['Trưởng phòng duyệt'] : [], 'waiting': status == 'running' ? ['duyet'] : [],
      };
  final runs = [
    run('i-101', 'Nghỉ phép 12/11 – 14/11 (Lan)', 'running'),
    run('i-102', 'Nghỉ phép 20/11 (Ba)', 'running', requester: 'me', ago: 7200000),
    run('i-090', 'Nghỉ phép 01/11 (Lan)', 'done', ago: 86400000 * 6),
    run('i-091', 'Nghỉ phép 03/11 (Minh)', 'rejected', ago: 86400000 * 4),
  ];
  Map<String, dynamic> runDetail(String id) => {
        ...runs.firstWhere((r) => r['id'] == id, orElse: () => run(id, 'Nghỉ phép mới', 'running', requester: 'me', ago: 1000)),
        'form': {'tu': '2026-11-12', 'so_ngay': 3, 'ly_do': 'Về quê có việc gia đình'},
        'steps': {
          'start': {'status': 'done', 'token': 1, 'started_at': now - 3600000, 'ended_at': now - 3600000},
          'duyet': {'status': 'active', 'token': 1, 'started_at': now - 3600000, 'assignees': ['me']},
        },
        'def': runDef,
        'events': [{'kind': 'started', 'by': 'u2', 'at': now - 3600000}],
        'my_tasks': [{'id': 5, 'instance_id': id, 'node': 'duyet', 'kind': 'approval', 'title': 'Nghỉ phép', 'flow_id': 'nghiphep', 'created_at': now - 3600000}],
      };
  final runsReport = {
    'total': 18,
    'by_status': {'running': 4, 'done': 11, 'rejected': 2, 'cancelled': 1},
    'by_step': [
      {'key': 'duyet', 'title': 'Trưởng phòng duyệt', 'count': 3},
      {'key': 'bao', 'title': 'Báo nhân sự', 'count': 1},
    ],
    'avg_duration_ms': 3 * 3600000 + 25 * 60000,
    'done_count': 11,
    'daily': [
      for (var i = 0; i < 10; i++) {'date': '2026-11-${(i + 1).toString().padLeft(2, '0')}', 'created': (i * 3) % 4 + 1, 'done': (i * 5) % 3, 'failed': 0},
    ],
  };

  // Tiến trình bị trả lại: Kế toán ký → trả về Kiểm tra trùng ("Sai mã số thuế"), đang chạy lại Kiểm tra trùng.
  final t0 = now - 4 * 3600000;
  Map<String, dynamic> ev(int min, String kind, Object data, {String? actor, String? node, String? nodeName}) =>
      {'at': t0 + min * 60000, 'actor': actor, 'node': node, 'node_name': nodeName, 'kind': kind, 'data': data};
  Map<String, dynamic> returned(String id, String name, {bool twice = false}) {
    final st = [
      for (final (k, t, s) in [('nhan', 'Nhận hoá đơn', 'done'), ('kiem', 'Kiểm tra trùng', 'active'), ('ky', 'Kế toán ký', 'pending'), ('gui', 'Gửi khách', 'pending')])
        {'key': k, 'title': t, 'state': s},
    ];
    return {
      ...proc(id, name, 1, 'Kiểm tra lại mã số thuế', 'orange', ['KLTM']),
      'steps': st,
      'current_step': 'kiem',
      'instance_id': 'i-88',
      'files': [{'name': 'hoadon-2160.pdf', 'kind': 'file', 'file_id': 'f9', 'size': 99000, 'at': t0}],
      'posts': [],
      'events': [
        ev(0, 'create', {'key': 'k-$id'}, node: 'tao', nodeName: 'Nhận hoá đơn từ LinkQ'),
        ev(5, 'step', {'step': 'kiem', 'status_text': 'Đang kiểm tra trùng'}, node: 'b_kiem', nodeName: 'Kiểm tra trùng bằng AI'),
        ev(12, 'stat', [{'key': 'amount', 'value': 128450000}], node: 'st', nodeName: 'Cộng tiền'),
        ev(20, 'step', {'step': 'ky', 'status_text': 'Chờ kế toán ký'}, node: 'b_ky', nodeName: 'Chuyển sang ký'),
        if (twice) ...[
          ev(35, 'step', {'step': 'kiem', 'status_text': 'Kiểm tra lại', 'returned': {'by': 'u2', 'reason': 'Thiếu chứng từ gốc', 'at': t0 + 34 * 60000}},
              node: 'b_kiem', nodeName: 'Kiểm tra trùng bằng AI'),
          ev(50, 'step', {'step': 'ky', 'status_text': 'Chờ kế toán ký'}, node: 'b_ky', nodeName: 'Chuyển sang ký'),
        ],
        ev(twice ? 80 : 40, 'step', {'step': 'kiem', 'status_text': 'Kiểm tra lại mã số thuế', 'returned': {'by': 'u2', 'reason': 'Sai mã số thuế', 'at': t0 + (twice ? 79 : 39) * 60000}},
            node: 'b_kiem', nodeName: 'Kiểm tra trùng bằng AI'),
        ev(twice ? 85 : 45, 'attach', {'files': [{'name': 'mst-moi.pdf'}]}, actor: 'me', node: 'dk', nodeName: 'Đính kèm chứng từ'),
      ],
      'actions': [
        {'wait': 'kiem', 'kind': 'buttons', 'prompt': 'Xác nhận đã sửa mã số thuế', 'actions': [
          {'id': 'ok', 'label': 'Đã sửa', 'style': 'primary'},
        ]},
      ],
    };
  }
  final ret1 = returned('P-RET001', 'Hoá đơn 2160 · Cty Nam Việt');
  final ret2 = returned('P-RET002', 'Hoá đơn 2161 · Cty Đông Á', twice: true);

  var meAdmin = true;
  final discussionOn = <String>{};
  final fromPost = <Map>[];
  FlowsApi.debugClient = MockClient((r) async {
    requests.add(r.url);
    final dm = RegExp(r'^/__apps/flows/processes/([^/]+)/discussion$').firstMatch(r.url.path);
    if (dm != null) {
      if (!discussionOn.contains(dm[1])) return http.Response.bytes(utf8.encode('{"error":"không liên quan"}'), 403, headers: {'content-type': 'application/json'});
      return _json({
        'channel_id': 'pch-${dm[1]}', 'team_id': 'team1', 'unread': 2,
        'members': [{'id': 'me', 'name': 'Ba'}, {'id': 'u2', 'name': 'Lan Kế toán'}, {'id': 'u3', 'name': 'Minh Giám đốc'}],
      });
    }
    if (r.url.path.endsWith('/files/from-post')) {
      fromPost.add(jsonDecode(r.body) as Map);
      return _json({'ok': true, 'added': true});
    }
    final q = r.url.queryParameters;
    final path = r.url.path;
    if (path == '/__apps/flows/processes') {
      final list = q['flow'] == 'linkq' ? procs : (q['flow'] == 'trl' ? [ret1, ret2] : <Map<String, dynamic>>[]);
      final want = (q['state'] ?? 'running').split(',');
      return _json({'processes': [for (final p in list) if (q['state'] == null || want.contains(p['state'])) p]});
    }
    if (path == '/__apps/flows/instances') return _json({'instances': q['flow'] == 'nghiphep' ? runs : (q['flow'] == 'linkq' ? [runs.first] : [])});
    if (path == '/__apps/flows/instances/i-103') {
      return _json({
        ...runDetail('i-101'),
        'id': 'i-103',
        'title': 'Nghỉ ốm 05/11 (Lan)',
        'events': [
          {'kind': 'started', 'by': 'u2', 'at': now - 7200000},
          {'kind': 'decided', 'node': 'duyet', 'at': now - 5400000, 'data': {'by': 'me', 'decision': 'return', 'comment': 'Thiếu giấy khám bệnh', 'return_step': 'sua'}},
          {'kind': 'submitted', 'node': 'sua', 'at': now - 3600000, 'data': {'by': 'u2'}},
        ],
      });
    }
    if (path.startsWith('/__apps/flows/instances/')) return _json(runDetail(path.split('/').last));
    if (path == '/__apps/flows/start') return _json({'id': 'i-new'});
    return switch (path) {
      '/__apps/flows/processes/P-8K2Q4M' => _json(procDetail),
      '/__apps/flows/processes/P-RET001' => _json(ret1),
      '/__apps/flows/processes/P-RET002' => _json(ret2),
      '/__apps/flows/defs/trl/info' => _json(info('trl', 'Hoá đơn trả lại', '🧾')),
      '/__apps/flows/defs/trl/report' => _json(procReport),
      '/__apps/flows/defs/linkq/info' => _json(info('linkq', 'Đồng bộ hoá đơn LinkQ', '🧾',
          desc: 'Mỗi hoá đơn đầu vào từ LinkQ thành một tiến trình theo dõi: kiểm tra trùng bằng AI, kế toán ký, gửi lại cho khách. Hoá đơn lỗi hiện ở tab Lỗi để xử lý tay.')),
      '/__apps/flows/defs/nghiphep/info' => _json({
          ...info('nghiphep', 'Đơn nghỉ phép', '🌴', desc: 'Xin nghỉ phép năm, nghỉ ốm, nghỉ việc riêng. Trưởng phòng duyệt, nhân sự được báo.'),
          'steps': [
            {'id': 'duyet', 'no': 2, 'name': 'Trưởng phòng duyệt', 'type': 'approval_request'},
            {'id': 'bao', 'no': 3, 'name': 'Báo nhân sự', 'type': 'send'},
          ],
        }),
      '/__apps/flows/defs/linkq/report' => _json(procReport),
      '/__apps/flows/reports/steps' when q['flow'] == 'linkq' => _json(stepsRep),
      '/__apps/flows/defs/moi/info' => _json({...info('moi', 'Hoá đơn mới', '🧾'), 'steps': [{'id': 'tao', 'no': 2, 'name': 'Tạo hoá đơn', 'type': 'process_create'}]}),
      '/__apps/flows/defs/moi/report' => _json({'total': 0, 'by_state': {}, 'by_step': [], 'stats': [], 'daily': []}),
      '/__apps/flows/defs/nghiphep/runs-report' => _json(runsReport),
      '/__apps/flows/defs' => _json({'flows': [
          {'id': 'linkq', 'name': 'Đồng bộ hoá đơn LinkQ', 'icon': '🧾', 'category': 'Kế toán', 'version': 3, 'form': [], 'active': true, 'can_start': true},
          {'id': 'moi', 'name': 'Hoá đơn mới', 'icon': '🧾', 'category': 'Kế toán', 'version': 1, 'form': [], 'active': true, 'can_start': true},
          {'id': 'nghiphep', 'name': 'Đơn nghỉ phép', 'icon': '🌴', 'category': 'Nhân sự', 'version': 2, 'form': runDef['form'], 'active': true, 'can_start': true},
        ]}),
      '/__apps/flows/tasks' => _json({'tasks': [runDetail('i-101')['my_tasks'][0]]}),
      '/__apps/flows/me' => _json({'id': 'me', 'admin': meAdmin, 'viewer': meAdmin}),
      '/__apps/flows/defs/nghiphep' => _json(runDef),
      _ => _json({}),
    };
  });

  final boundary = GlobalKey();
  Future<void> snap(WidgetTester t, String? shot) async {
    if (out == null || shot == null) return;
    // Ảnh xem trước: vẽ bóng thật (mặc định test vẽ bóng thành viền đen, nhìn như nút ＋ có vòng tối); trả lại sau khi chụp.
    debugDisableShadows = false;
    for (final r in find.byType(RepaintBoundary).evaluate()) {
      r.renderObject?.markNeedsPaint();
    }
    await t.pump();
    await t.runAsync(() async {
      final img = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$shot.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    debugDisableShadows = true;
    await t.pump();
  }

  Finder reportScroll() => find.descendant(of: find.byKey(const ValueKey('intro-report')), matching: find.byType(Scrollable)).first;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> pump(WidgetTester t, Size size, Widget home, {Brightness b = Brightness.light, void Function(String?)? onTitle}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(b), home: DeskTabScope(onTitle: onTitle, child: home)),
      ),
    ));
    await settle(t);
  }

  /// Nút lọc bên phải ô tìm → hộp thoại: chọn một ô rồi Áp dụng.
  Future<void> pickFilter(WidgetTester t, String key, String text) async {
    await t.tap(find.byKey(ValueKey(key)));
    await settle(t);
    await t.tap(find.widgetWithText(ChoiceChip, text).first);
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Áp dụng'));
    await settle(t);
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 50));
  }

  WorkflowPage linkq() => WorkflowPage(app: app, flowId: 'linkq', name: 'Đồng bộ hoá đơn LinkQ', icon: '🧾');
  WorkflowPage leave() => WorkflowPage(app: app, flowId: 'nghiphep', name: 'Đơn nghỉ phép', icon: '🌴');

  for (final (b, tag) in [(Brightness.light, 'light'), (Brightness.dark, 'dark')]) {
    testWidgets('chưa chọn: giới thiệu, ai được chạy, các bước, thống kê tiến trình ($tag)', (t) async {
      if (out != null) await t.runAsync(_fonts);
      requests.clear();
      await pump(t, const Size(1280, 860), linkq(), b: b);
      expect(requests.any((u) => u.path == '/__apps/flows/defs/linkq/info'), isTrue);
      expect(requests.any((u) => u.path == '/__apps/flows/processes' && u.queryParameters['flow'] == 'linkq'), isTrue);
      expect(find.text('Hoá đơn 2154 · Cty Hoàng Long'), findsOneWidget, reason: 'cột trái: tiến trình của quy trình');
      expect(find.text('Quy trình'), findsNothing, reason: 'không có bộ lọc quy trình khi đã cố định quy trình');
      // Nút ＋ nổi góc dưới phải cột danh sách (PlusFab), không còn nút to phía trên.
      expect(find.byTooltip('Tạo tiến trình mới'), findsOneWidget);
      expect(find.byType(PlusFab), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Tạo tiến trình mới'), findsNothing);
      expect(t.getCenter(find.byType(PlusFab)).dx, lessThan(400), reason: 'nằm trong cột trái');
      // Một nút lọc nhỏ bên phải ô tìm (trạng thái, nhãn, bước nằm trong hộp thoại), gọn trong cột 384px, không còn tab.
      expect(t.getRect(find.byKey(const ValueKey('process-filter'))).right, lessThan(384));
      expect(find.text('Nhãn'), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.textContaining('Mỗi hoá đơn đầu vào từ LinkQ'), findsOneWidget);
      expect(find.text('Ai được chạy:'), findsOneWidget);
      expect(find.text('Phòng ban: Kế toán'), findsOneWidget);
      expect(find.text('Vai trò: Kế toán trưởng'), findsOneWidget, reason: 'không hiện mã vai trò');
      expect(find.text('Vai trò: Kiểm soát nội bộ'), findsOneWidget);
      expect(find.textContaining('ke_toan_truong'), findsNothing);
      expect(find.text('Lan Kế toán'), findsOneWidget);
      expect(find.text('Thời gian áp dụng: từ 01/01/2026 đến hết 31/12/2026'), findsOneWidget);
      expect(find.text('Kế toán ký'), findsWidgets);
      expect(find.text('Theo dõi'), findsNothing, reason: 'không còn nút chuyển: có đối tượng theo dõi thì chỉ hiện danh sách đó');
      expect(find.text('Nghỉ phép 12/11 – 14/11 (Lan)'), findsNothing, reason: 'có cả hai: ưu tiên đối tượng theo dõi');
      await snap(t, 'workflow-intro-1280-$tag');
      await t.scrollUntilVisible(find.text('Theo ngày'), 300, scrollable: reportScroll());
      await settle(t);
      expect(find.byKey(const ValueKey('intro-report')), findsOneWidget);
      expect(requests.any((u) => u.path == '/__apps/flows/defs/linkq/report'), isTrue);
      await snap(t, 'workflow-intro-stats-1280-$tag');
      await done(t);
    });

    testWidgets('chọn tiến trình: 3 cột danh sách | quá trình chạy | thao tác ($tag)', (t) async {
      if (out != null) await t.runAsync(_fonts);
      for (final w in [1280.0, 1600.0]) {
        await pump(t, Size(w, w == 1280 ? 860 : 960), linkq(), b: b);
        await t.tap(find.text('Hoá đơn 2154 · Cty Hoàng Long'));
        await settle(t);
        expect(find.byType(ProcessDetailPage), findsOneWidget);
        expect(find.byKey(const ValueKey('process-timeline')), findsOneWidget, reason: 'vùng chi tiết >= 720px: 2 cột');
        expect(find.byKey(const ValueKey('process-actions')), findsOneWidget);
        // Thao tác đang chờ: "Bước tiếp theo" ở cuối quá trình chạy (cột 1), không ở cột phải.
        expect(find.descendant(of: find.byKey(const ValueKey('process-timeline')), matching: find.byKey(const ValueKey('next-step'))), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('next-step')), matching: find.text('Đồng ý')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('process-actions')), matching: find.text('Đồng ý')), findsNothing);
        expect(t.getTopLeft(find.text('Bước tiếp theo')).dy, greaterThan(t.getTopLeft(find.text('Chuyển sang bước «Kế toán ký»')).dy), reason: 'nằm sau lịch sử');
        expect(find.descendant(of: find.byKey(const ValueKey('process-actions')), matching: find.text('hoadon-2154.pdf')), findsOneWidget);
        // Các bước và lịch sử gộp thành một đường thời gian: không còn hai mục riêng.
        expect(find.descendant(of: find.byKey(const ValueKey('process-timeline')), matching: find.byKey(const ValueKey('flow-rail'))), findsOneWidget);
        expect(find.text('LỊCH SỬ'), findsNothing);
        expect(find.text('CÁC BƯỚC'), findsNothing);
        // Sự kiện nằm dưới bước của nó; "Bước tiếp theo" ngay dưới bước hiện tại, bước sắp tới ở dưới nữa.
        expect(find.descendant(of: find.byKey(const ValueKey('rail-kiem')), matching: find.text('Chuyển sang bước «Kiểm tra trùng»')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('rail-ky')), matching: find.byKey(const ValueKey('next-step'))), findsOneWidget);
        expect(t.getTopLeft(find.text('Gửi khách').last).dy, greaterThan(t.getBottomLeft(find.byKey(const ValueKey('next-step'))).dy));
        // Lịch sử viết cho người đọc: tên bước khai báo, tên người / "Quy trình", không khoá thô, không mã bước.
        expect(find.text('Chuyển sang bước «Kế toán ký»'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const ValueKey('process-timeline')), matching: find.text('Tổng tiền: 128.450.000')), findsOneWidget);
        expect(find.textContaining('Lan Kế toán · Chuyển sang ký'), findsOneWidget);
        expect(find.textContaining('Quy trình · Kiểm tra trùng bằng AI'), findsOneWidget);
        for (final raw in ['status_text', 'step:', 'b_ky', 'b_kiem', 'bước tao']) {
          expect(find.textContaining(raw), findsNothing, reason: raw);
        }
        await snap(t, 'workflow-process-${w.toInt()}-$tag');
        // Nút đóng của chi tiết: bỏ chọn, về giới thiệu.
        await t.tap(find.byTooltip('Đóng'));
        await settle(t);
        expect(find.byType(ProcessDetailPage), findsNothing);
        expect(find.text('Ai được chạy:'), findsOneWidget);
        await done(t);
      }
    });

    testWidgets('quy trình không có đối tượng theo dõi: danh sách lần chạy, thống kê theo lần chạy, chi tiết 2 cột ($tag)', (t) async {
      if (out != null) await t.runAsync(_fonts);
      requests.clear();
      await pump(t, const Size(1280, 860), leave(), b: b);
      expect(find.text('Nghỉ phép 12/11 – 14/11 (Lan)'), findsOneWidget);
      expect(find.text('Theo dõi'), findsNothing, reason: 'chỉ có lần chạy: một danh sách');
      expect(requests.any((u) => u.path == '/__apps/flows/instances' && u.queryParameters['flow'] == 'nghiphep'), isTrue);
      await t.scrollUntilVisible(find.text('Theo ngày'), 300, scrollable: reportScroll());
      await settle(t);
      expect(requests.any((u) => u.path == '/__apps/flows/defs/nghiphep/runs-report'), isTrue);
      expect(find.text('3 giờ 25 phút'), findsOneWidget);
      await snap(t, 'workflow-runs-stats-1280-$tag');
      // Tab Đã xong.
      await pickFilter(t, 'state-select', 'Đã xong');
      expect(find.text('Nghỉ phép 01/11 (Lan)'), findsOneWidget);
      expect(find.text('Nghỉ phép 12/11 – 14/11 (Lan)'), findsNothing);
      await pickFilter(t, 'state-select', 'Tất cả');
      expect(find.text('Nghỉ phép 01/11 (Lan)'), findsOneWidget);
      expect(find.text('Nghỉ phép 12/11 – 14/11 (Lan)'), findsOneWidget);
      await pickFilter(t, 'state-select', 'Đang chạy');
      await t.tap(find.text('Nghỉ phép 12/11 – 14/11 (Lan)'));
      await settle(t);
      expect(find.byType(FlowDetailPage), findsOneWidget);
      expect(find.byKey(const ValueKey('run-timeline')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('run-timeline')), matching: find.byKey(const ValueKey('next-step'))), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('flow-rail')), matching: find.byKey(const ValueKey('next-step'))), findsOneWidget, reason: 'dưới bước đang chờ trong đường thời gian');
      expect(find.descendant(of: find.byKey(const ValueKey('next-step')), matching: find.text('Duyệt')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('run-actions')), matching: find.text('Duyệt')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('run-actions')), matching: find.text('Nội dung đơn')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('run-timeline')), matching: find.text('Diễn biến')), findsOneWidget);
      await snap(t, 'workflow-run-1280-$tag');
      await done(t);
    });
  }

  testWidgets('vùng chi tiết hẹp (< 720px): chi tiết 1 cột', (t) async {
    await pump(t, const Size(960, 800), linkq());
    await t.tap(find.text('Hoá đơn 2154 · Cty Hoàng Long'));
    await settle(t);
    expect(find.byType(ProcessDetailPage), findsOneWidget);
    expect(find.byKey(const ValueKey('process-timeline')), findsNothing);
    await t.scrollUntilVisible(find.text('Bước tiếp theo'), 300, scrollable: find.byType(Scrollable).last);
    expect(t.getTopLeft(find.text('Bước tiếp theo')).dy, greaterThan(t.getTopLeft(find.text('Chuyển sang bước «Kế toán ký»')).dy), reason: 'một cột: cùng thứ tự');
    await t.scrollUntilVisible(find.text('hoadon-2154.pdf'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('hoadon-2154.pdf'), findsOneWidget, reason: 'một cột: đường thời gian trước, thông tin kèm theo sau');
    await done(t);
  });

  testWidgets('Tạo tiến trình mới: hộp nổi trên máy tính, gửi xong chọn tiến trình mới ở cột phải', (t) async {
    if (!isDesktop) return;
    requests.clear();
    await pump(t, const Size(1280, 860), leave());
    await t.tap(find.byTooltip('Tạo tiến trình mới'));
    await settle(t);
    expect(find.byType(FlowFormPage), findsOneWidget);
    // Hộp nổi: trang phía sau vẫn còn (route không che kín).
    expect(find.text('Nghỉ phép 12/11 – 14/11 (Lan)', skipOffstage: false), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);
    await t.tap(find.descendant(of: find.byType(FlowFormPage), matching: find.text('Tạo tiến trình mới')).last);
    await settle(t);
    expect(requests.any((u) => u.path == '/__apps/flows/start'), isTrue);
    expect(find.byType(FlowFormPage), findsNothing);
    expect(requests.any((u) => u.path == '/__apps/flows/instances/i-new'), isTrue, reason: 'mở tiến trình mới ở cột phải');
    expect(find.byType(FlowDetailPage), findsOneWidget);
    await done(t);
  });

  testWidgets('tiêu đề tab: tên quy trình khi mở, về tên ứng dụng khi đóng', (t) async {
    final titles = <String?>[];
    await pump(t, const Size(1280, 860), leave(), onTitle: titles.add);
    expect(titles, isNotEmpty);
    expect(titles.last, 'Đơn nghỉ phép');
    await done(t);
    expect(titles.last, isNull);
    // Ngoài tab máy tính (không có DeskTabScope.onTitle): không lỗi.
    await pump(t, const Size(1280, 860), leave());
    await done(t);
  });

  // Mục Quy trình chỉ dành cho quản trị: bấm một quy trình là mở sơ đồ (trình soạn) ở vùng bên phải, giữ danh sách.
  Widget flowsSplit() => const _FlowsSplit();

  testWidgets('quản trị: tab Quy trình, bấm quy trình mở sơ đồ ở vùng bên phải (máy tính)', (t) async {
    if (out != null) await t.runAsync(_fonts);
    meAdmin = true;
    await pump(t, const Size(1280, 860), flowsSplit());
    await settle(t);
    expect(find.widgetWithText(Tab, 'Quy trình'), findsOneWidget);
    await t.tap(find.text('Đơn nghỉ phép'));
    await settle(t);
    await settle(t);
    expect(find.byType(FlowEditorPage), findsOneWidget, reason: 'mở trình soạn, không mở trang quy trình');
    expect(find.byType(WorkflowPage), findsNothing);
    expect(find.byType(FlowFormPage), findsNothing);
    // Danh sách vẫn ở bên trái, sơ đồ ở bên phải.
    expect(t.getRect(find.byType(FlowEditorPage)).left, greaterThanOrEqualTo(460));
    expect(find.text('Đơn nghỉ phép'), findsWidgets);
    await snap(t, 'catalog-admin-diagram-1280');
    await done(t);
  });

  testWidgets('quản trị, điện thoại: bấm quy trình mở trang soạn', (t) async {
    meAdmin = true;
    await pump(t, const Size(430, 900), FlowsHome(app: app, debugPins: const []));
    await settle(t);
    await t.tap(find.text('Đơn nghỉ phép'));
    await settle(t);
    await settle(t);
    expect(find.byType(FlowEditorPage), findsOneWidget);
    expect(find.byType(FlowFormPage), findsNothing);
    await done(t);
  });

  testWidgets('người thường: không có tab Quy trình, mở ở Cần xử lý, bắt đầu quy trình từ tab Đang chạy', (t) async {
    if (out != null) await t.runAsync(_fonts);
    meAdmin = false;
    await pump(t, const Size(1280, 860), flowsSplit());
    await settle(t);
    expect(find.widgetWithText(Tab, 'Quy trình'), findsNothing);
    final tabs = t.widget<TabBar>(find.byType(TabBar).first);
    expect(DefaultTabController.of(t.element(find.byType(TabBar).first)).index, 0);
    expect(tabs.tabs.length, 6);
    expect(find.text('Thêm quy trình'), findsNothing);
    await snap(t, 'catalog-nonadmin-1280');
    await t.tap(find.text('Đang chạy').first);
    await settle(t);
    await t.tap(find.byKey(const ValueKey('start-flow')));
    await settle(t);
    // Danh sách quy trình mình được chạy (GET /flows/defs) để bắt đầu.
    expect(find.text('Đơn nghỉ phép'), findsWidgets);
    await t.tap(find.text('Đơn nghỉ phép').last);
    await settle(t);
    expect(find.byType(FlowFormPage), findsOneWidget);
    meAdmin = true;
    await done(t);
  });

  testWidgets('đổi quy trình khi trình soạn còn thay đổi chưa lưu: hỏi trước', (t) async {
    meAdmin = true;
    await pump(t, const Size(1280, 860), FlowEditorPage(app: app, api: FlowsApi(app.token), doc: FlowDoc.fromJson(runDef), isNew: true));
    await settle(t);
    late Future<bool> leave;
    leave = canLeaveFlowEditor();
    await settle(t);
    expect(find.text('Bỏ các thay đổi chưa lưu?'), findsOneWidget);
    await t.tap(find.text('Ở lại'));
    await settle(t);
    expect(await leave, isFalse);
    await done(t);
    expect(await canLeaveFlowEditor(), isTrue, reason: 'không còn trình soạn nào mở');
  });

  testWidgets('đối tượng theo dõi: ô chọn trạng thái thay cho tab', (t) async {
    requests.clear();
    await pump(t, const Size(1280, 860), linkq());
    expect(find.byType(TabBar), findsNothing);
    await pickFilter(t, 'process-filter', 'Lỗi');
    expect(requests.lastWhere((u) => u.path == '/__apps/flows/processes' && u.queryParameters['label'] == null && u.queryParameters['limit'] == '200' && u.queryParameters.containsKey('q') == false).queryParameters['state'], 'failed');
    expect(find.text('Không có tiến trình nào bị lỗi.'), findsOneWidget);
    expect(find.byKey(const ValueKey('process-filter')), findsOneWidget);
    await done(t);
  });

  testWidgets('có bước tiến trình nhưng chưa có đối tượng nào: vẫn là danh sách đối tượng theo dõi', (t) async {
    requests.clear();
    await pump(t, const Size(1280, 860), WorkflowPage(app: app, flowId: 'moi', name: 'Hoá đơn mới'));
    expect(find.text('Không có tiến trình nào đang chạy.'), findsOneWidget);
    expect(find.byKey(const ValueKey('process-filter')), findsOneWidget, reason: 'bộ lọc của danh sách đối tượng theo dõi');
    expect(requests.any((u) => u.path == '/__apps/flows/defs/moi/report'), isTrue, reason: 'thống kê theo đối tượng theo dõi');
    expect(requests.any((u) => u.path == '/__apps/flows/defs/moi/runs-report'), isFalse);
    await done(t);
  });

  testWidgets('tạo tiến trình mới khi cột trái là đối tượng theo dõi: tiến trình mới mở ở cột phải', (t) async {
    if (!isDesktop) return;
    requests.clear();
    await pump(t, const Size(1280, 860), linkq());
    await t.tap(find.byTooltip('Tạo tiến trình mới'));
    await settle(t);
    await t.tap(find.descendant(of: find.byType(FlowFormPage), matching: find.text('Tạo tiến trình mới')).last);
    await settle(t);
    expect(requests.any((u) => u.path == '/__apps/flows/instances/i-new'), isTrue);
    expect(find.byType(FlowDetailPage), findsOneWidget);
    expect(find.text('Hoá đơn 2154 · Cty Hoàng Long'), findsOneWidget, reason: 'cột trái vẫn là danh sách đối tượng theo dõi');
    await done(t);
  });

  for (final (b, tag) in [(Brightness.light, 'light'), (Brightness.dark, 'dark')]) {
    testWidgets('bị trả lại một lần: lượt cũ mờ, dòng trả lại, lượt hiện tại có bước tiếp theo ($tag)', (t) async {
      if (out != null) await t.runAsync(_fonts);
      await pump(t, const Size(1280, 860), WorkflowPage(app: app, flowId: 'trl', name: 'Hoá đơn trả lại'), b: b);
      await t.tap(find.text('Hoá đơn 2160 · Cty Nam Việt'));
      await settle(t);
      expect(find.text('Bị trả lại 1 lần'), findsOneWidget);
      expect(find.text('LƯỢT 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('round-0')), findsOneWidget);
      expect(t.widget<Opacity>(find.byKey(const ValueKey('round-0'))).opacity, lessThan(.5), reason: 'lượt cũ mờ');
      expect(find.text('Bị trả lại về «Kiểm tra trùng»'), findsOneWidget);
      expect(find.text('“Sai mã số thuế”'), findsOneWidget);
      expect(find.textContaining('Lan Kế toán ·'), findsWidgets);
      // Lượt hiện tại: Kiểm tra trùng đang làm, có "Bước tiếp theo"; sau dòng trả lại.
      expect(find.descendant(of: find.byKey(const ValueKey('rail-kiem')), matching: find.byKey(const ValueKey('next-step'))), findsOneWidget);
      expect(t.getTopLeft(find.byKey(const ValueKey('rail-kiem'))).dy, greaterThan(t.getTopLeft(find.byKey(const ValueKey('return-0'))).dy));
      expect(find.descendant(of: find.byKey(const ValueKey('rail-kiem')), matching: find.text('Đính kèm')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('rail-kiem')), matching: find.textContaining('· Bạn ·')), findsOneWidget, reason: 'người đính kèm là mình');
      await snap(t, 'workflow-returned-1280-$tag');
      await done(t);
    });
  }

  testWidgets('bị trả lại hai lần: các lượt cũ thu gọn một dòng, bấm để mở', (t) async {
    if (out != null) await t.runAsync(_fonts);
    await pump(t, const Size(1280, 860), WorkflowPage(app: app, flowId: 'trl', name: 'Hoá đơn trả lại'));
    await t.tap(find.text('Hoá đơn 2161 · Cty Đông Á'));
    await settle(t);
    expect(find.text('Bị trả lại 2 lần'), findsOneWidget);
    expect(find.text('LƯỢT 1'), findsNothing, reason: 'thu gọn');
    expect(find.textContaining('bị trả lại', findRichText: true), findsNWidgets(2));
    expect(find.text('“Sai mã số thuế”'), findsNothing);
    expect(find.byKey(const ValueKey('next-step')), findsOneWidget);
    await snap(t, 'workflow-returned2-1280-light');
    await t.tap(find.byKey(const ValueKey('round-1')));
    await settle(t);
    expect(find.text('LƯỢT 2'), findsOneWidget);
    expect(find.text('“Sai mã số thuế”'), findsOneWidget);
    await done(t);
  });

  testWidgets('lần chạy bị trả lại: chip, dòng trả lại, bước tiếp theo ở lượt hiện tại', (t) async {
    await pump(t, const Size(1280, 860), FlowDetailPage(app: app, instanceId: 'i-103'));
    await settle(t);
    expect(find.text('Bị trả lại 1 lần'), findsOneWidget);
    expect(find.text('Bị trả lại về «Bổ sung giấy tờ»'), findsOneWidget);
    expect(find.text('“Thiếu giấy khám bệnh”'), findsOneWidget);
    expect(find.byKey(const ValueKey('next-step')), findsOneWidget);
    expect(t.getTopLeft(find.byKey(const ValueKey('next-step'))).dy, greaterThan(t.getTopLeft(find.byKey(const ValueKey('return-0'))).dy));
    await done(t);
  });

  // Thảo luận của tiến trình: kênh Mattermost riêng tư (mã kênh từ POST /discussion), tin đọc từ phiên chat của app.
  app.users['u3'] = MmUser({'id': 'u3', 'username': 'minh', 'first_name': 'Minh Giám đốc'});
  MmPost post(String id, String user, int at, String text, {List<Map<String, dynamic>> files = const [], List<(String, String)> reactions = const []}) => MmPost({
        'id': id, 'channel_id': 'pch-P-8K2Q4M', 'user_id': user, 'create_at': at, 'message': text, 'root_id': '', 'type': '',
        'metadata': {
          'files': files,
          'reactions': [for (final (e, u) in reactions) {'emoji_name': e, 'user_id': u}],
        },
      });
  void seedDiscussion() {
    discussionOn.add('P-8K2Q4M');
    app.channels['pch-P-8K2Q4M'] = MmChannel({'id': 'pch-P-8K2Q4M', 'type': 'P', 'name': 'flow-p-8k2q4m', 'display_name': '💬 Hoá đơn 2154', 'header': 'flygo:process:P-8K2Q4M', 'total_msg_count': 4});
    app.members['pch-P-8K2Q4M'] = MmMember({'channel_id': 'pch-P-8K2Q4M', 'msg_count': 2, 'mention_count': 1, 'last_viewed_at': 0});
    app.debugPutPosts('pch-P-8K2Q4M', [
      post('m4', 'u2', now - 600000, 'Ok, mình ký trong chiều nay.', reactions: [('+1', 'u3'), ('heart', 'me')]),
      post('m3', 'u3', now - 900000, 'Đã đối chiếu với hợp đồng, gửi bản scan đây.',
          files: [{'id': 'fsc1', 'name': 'hop-dong-HL-2026.pdf', 'size': 482000, 'mime_type': 'application/pdf'}]),
      post('m2', 'me', now - 2000000, '@lan mình kiểm rồi, khác mã số thuế bên bán nên **không trùng** nhé.'),
      post('m1', 'u2', now - 2200000, 'Hoá đơn này có vẻ trùng với số 2101 tháng trước, mọi người kiểm tra giúp mình.', reactions: [('eyes', 'me'), ('eyes', 'u3')]),
      MmPost({'id': 'sys', 'channel_id': 'pch-P-8K2Q4M', 'user_id': 'flowbot', 'create_at': now - 3000000, 'message': 'lan joined', 'type': 'system_join_channel', 'root_id': ''}),
    ]);
  }

  for (final (w, b, tag) in [(1280.0, Brightness.light, '1280-light'), (1280.0, Brightness.dark, '1280-dark'), (1600.0, Brightness.light, '1600-light')]) {
    testWidgets('thảo luận: cột 1 toàn cảnh, cột 2 chỉ thảo luận ($tag)', (t) async {
      if (out != null) await t.runAsync(_fonts);
      seedDiscussion();
      requests.clear();
      await pump(t, Size(w, w == 1280 ? 860 : 960), linkq(), b: b);
      // Số tin chưa đọc trên dòng (kênh mình là thành viên): 4 tin, đã xem 2.
      expect(find.byType(ProcessUnreadBadge), findsOneWidget);
      expect(find.descendant(of: find.byType(ProcessUnreadBadge), matching: find.text('2')), findsOneWidget);
      await t.tap(find.text('Hoá đơn 2154 · Cty Hoàng Long'));
      await settle(t);
      expect(requests.any((u) => u.path == '/__apps/flows/processes/P-8K2Q4M/discussion'), isTrue);
      expect(find.descendant(of: find.byKey(const ValueKey('process-timeline')), matching: find.byType(ProcessChatMessage)), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('process-discussion')), matching: find.byType(ProcessChatMessage)), findsNWidgets(4), reason: 'bỏ tin hệ thống');
      final col2 = t.getRect(find.byKey(const ValueKey('process-discussion')));
      expect(col2.width, inInclusiveRange(359, 401));
      expect(t.getRect(find.byKey(const ValueKey('process-timeline'))).right, lessThan(col2.left));
      expect(find.text('Chỉ người liên quan thấy'), findsOneWidget);
      expect(find.text('3 người'), findsOneWidget);
      expect(find.textContaining('tại bước Kiểm tra trùng', findRichText: true), findsNWidgets(2));
      expect(find.textContaining('tại bước Kế toán ký', findRichText: true), findsNWidgets(2));
      expect(t.getRect(find.byKey(const ValueKey('chat-m4'))).top, greaterThan(t.getRect(find.byKey(const ValueKey('chat-m1'))).top));
      expect(t.getRect(find.byKey(const ValueKey('process-composer'))).left, closeTo(col2.left, 1));
      expect(find.byKey(const ValueKey('process-actions')), findsNothing);
      expect(t.getRect(find.text('128.450.000').first).top, lessThan(t.getRect(find.byKey(const ValueKey('flow-rail'))).top));
      await snap(t, 'process-chat-$tag');
      // Đưa tệp của tin vào tệp của tiến trình.
      fromPost.clear();
      await t.tap(find.byKey(const ValueKey('add-to-files-fsc1')));
      await settle(t);
      expect(fromPost.single, {'post_id': 'm3', 'file_id': 'fsc1'});
      await done(t);
    });
  }

  testWidgets('kéo đổi độ rộng 3 cột (danh sách | chi tiết | thảo luận), bấm đúp về mặc định; nút Báo cáo về giao diện ban đầu', (t) async {
    seedDiscussion();
    await pump(t, const Size(1600, 960), linkq());
    await t.tap(find.text('Hoá đơn 2154 · Cty Hoàng Long'));
    await settle(t);
    final chat0 = t.getRect(find.byKey(const ValueKey('process-discussion'))).width;
    double chatW() => t.getRect(find.byKey(const ValueKey('process-discussion'))).width;
    double leftEdge() => t.getRect(find.byKey(const ValueKey('workflow-left-resizer'))).left;
    // Kéo: bước đầu vượt ngưỡng nhận kéo, đo độ dời ở bước sau.
    Future<(double, double)> drag(String key, double dx, double Function() measure) async {
      final g = await t.startGesture(t.getCenter(find.byKey(ValueKey(key))));
      await g.moveBy(Offset(dx.sign * 30, 0));
      await t.pump();
      final a = measure();
      await g.moveBy(Offset(dx, 0));
      await t.pump();
      final b = measure();
      await g.up();
      await settle(t);
      return (a, b);
    }

    final (c1, c2) = await drag('process-chat-resizer', -120, chatW);
    expect(c2 - c1, closeTo(120, 2), reason: 'kéo vạch sang trái: cột thảo luận rộng ra');
    final (l1, l2) = await drag('workflow-left-resizer', 80, leftEdge);
    expect(l2 - l1, closeTo(80, 2), reason: 'cột danh sách rộng ra');
    await drag('workflow-left-resizer', -2000, leftEdge);
    expect(leftEdge(), closeTo(260, 2), reason: 'không hẹp hơn tối thiểu');
    if (out != null) await t.runAsync(_fonts);
    await snap(t, 'workflow-resized-1600');
    // Bấm đúp: về độ rộng mặc định.
    final r = find.byKey(const ValueKey('process-chat-resizer'));
    await t.tap(r);
    await t.pump(const Duration(milliseconds: 60));
    await t.tap(r);
    await settle(t);
    expect(t.getRect(find.byKey(const ValueKey('process-discussion'))).width, closeTo(chat0, 2));
    // Báo cáo: bỏ chọn, cột phải về phần giới thiệu + báo cáo (không mở trang riêng).
    await t.tap(find.byKey(const ValueKey('flow-report')));
    await settle(t);
    expect(find.byType(ProcessDetailPage), findsNothing);
    expect(find.text('Ai được chạy:'), findsOneWidget);
    expect(find.byKey(const ValueKey('workflow-left-resizer')), findsOneWidget, reason: 'vẫn trang quy trình, không phải trang báo cáo riêng');
    await snap(t, 'workflow-report-reset-1600');
    await done(t);
  });

  testWidgets('điện thoại: nút Báo cáo đổi qua lại giữa danh sách và phần giới thiệu / báo cáo', (t) async {
    await pump(t, const Size(430, 900), linkq());
    expect(find.text('Hoá đơn 2154 · Cty Hoàng Long'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('flow-report')));
    await settle(t);
    expect(t.takeException(), isNull, reason: 'không tràn ở màn điện thoại');
    expect(find.textContaining('Phiên bản'), findsOneWidget, reason: 'phần giới thiệu / báo cáo của quy trình');
    if (out != null) await t.runAsync(_fonts);
    await snap(t, 'workflow-report-phone');
    expect(find.text('Hoá đơn 2154 · Cty Hoàng Long'), findsNothing);
    await t.tap(find.byKey(const ValueKey('flow-report')));
    await settle(t);
    expect(find.text('Hoá đơn 2154 · Cty Hoàng Long'), findsOneWidget);
    await done(t);
  });

  testWidgets('thảo luận: vùng hẹp / điện thoại dùng 2 tab', (t) async {
    if (out != null) await t.runAsync(_fonts);
    seedDiscussion();
    await pump(t, const Size(400, 860), ProcessDetailPage(app: app, processId: 'P-8K2Q4M', initialTab: 1));
    await settle(t);
    expect(find.text('Thảo luận (4)'), findsOneWidget);
    expect(find.byType(ProcessChatMessage), findsNWidgets(4));
    expect(t.getRect(find.byKey(const ValueKey('process-composer'))).bottom, closeTo(860, 1));
    await snap(t, 'process-chat-phone-light');
    await t.tap(find.widgetWithText(Tab, 'Tiến trình'));
    await settle(t);
    expect(find.byKey(const ValueKey('flow-rail')), findsOneWidget);
    await done(t);
  });

  testWidgets('điện thoại: vuốt trái / phải đổi giữa Tiến trình và Thảo luận', (t) async {
    seedDiscussion();
    await pump(t, const Size(400, 860), ProcessDetailPage(app: app, processId: 'P-8K2Q4M', initialTab: 1));
    await settle(t);
    expect(find.byKey(const ValueKey('process-composer')), findsOneWidget);
    await t.fling(find.byKey(const ValueKey('process-tabs-swipe')), const Offset(300, 0), 1200);
    await settle(t);
    expect(find.byKey(const ValueKey('flow-rail')), findsOneWidget);
    await t.fling(find.byKey(const ValueKey('process-tabs-swipe')), const Offset(-300, 0), 1200);
    await settle(t);
    expect(DefaultTabController.of(t.element(find.byType(TabBar))).index, 1);
    await done(t);
  });

  testWidgets('thảo luận: chưa có tin; người không liên quan không có cột thảo luận', (t) async {
    seedDiscussion();
    app.debugPutPosts('pch-P-8K2Q4M', const []);
    await pump(t, const Size(1280, 860), ProcessDetailPage(app: app, processId: 'P-8K2Q4M'));
    expect(find.text('Chưa có thảo luận. Nhắn để trao đổi với những người liên quan.'), findsOneWidget);
    expect(find.byKey(const ValueKey('process-composer')), findsOneWidget);
    await done(t);
    discussionOn.clear();
    await pump(t, const Size(1280, 860), ProcessDetailPage(app: app, processId: 'P-8K2Q4M'));
    expect(find.byKey(const ValueKey('process-discussion')), findsNothing);
    expect(find.byKey(const ValueKey('process-actions')), findsOneWidget, reason: 'bố cục cũ');
    await done(t);
  });

  test('kênh thảo luận của tiến trình: nhận ra bằng dấu, ẩn khỏi danh sách chat', () {
    final c = MmChannel({'id': 'x', 'type': 'P', 'name': 'flow-p-1', 'header': 'flygo:process:P-8K2Q4M'});
    expect(c.processId, 'P-8K2Q4M');
    final a = AppState('tok')..me = MmUser({'id': 'me', 'username': 'ba'});
    a.channels['x'] = c;
    a.channels['y'] = MmChannel({'id': 'y', 'type': 'O', 'name': 'chung', 'display_name': 'Chung'});
    expect([for (final s in a.chats) s.channel.id], ['y']);
  });

  for (final w in [1280.0, 1600.0]) {
    testWidgets('chưa chọn: 2 cột, trái báo cáo, phải các bước (bấm bước lọc danh sách) ($w)', (t) async {
      if (out != null) await t.runAsync(_fonts);
      requests.clear();
      await pump(t, Size(w, w == 1280 ? 860 : 960), linkq());
      final rep = t.getRect(find.byKey(const ValueKey('intro-report')));
      final steps = t.getRect(find.byKey(const ValueKey('intro-steps')));
      expect(rep.right, lessThanOrEqualTo(steps.left + 1), reason: 'báo cáo bên trái, các bước bên phải');
      expect(rep.width / (rep.width + steps.width), closeTo(.6, .03));
      expect(requests.any((u) => u.path == '/__apps/flows/reports/steps' && u.queryParameters['flow'] == 'linkq'), isTrue);
      // Cột các bước: tên, số đang ở, thời gian TB, quá hạn.
      for (final x in ['Nhận hoá đơn', 'Kiểm tra trùng', 'Kế toán ký', 'Gửi khách']) {
        expect(find.descendant(of: find.byKey(const ValueKey('intro-steps')), matching: find.text(x)), findsOneWidget, reason: x);
      }
      expect(find.descendant(of: find.byKey(const ValueKey('intro-step-ky')), matching: find.text('9')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('overdue-ky')), matching: find.text('5')), findsOneWidget);
      expect(find.byKey(const ValueKey('overdue-gui')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('intro-step-ky')), matching: find.textContaining('TB 1 ngày 6 giờ')), findsOneWidget);
      await snap(t, 'workflow-intro-2col-${w.toInt()}-light');
      await t.scrollUntilVisible(find.byKey(const ValueKey('step-times')), 300, scrollable: reportScroll());
      expect(find.byKey(const ValueKey('step-times')), findsOneWidget, reason: 'thời gian theo bước trong báo cáo');
      // Bấm bước: danh sách bên trái lọc theo bước đó.
      await t.tap(find.byKey(const ValueKey('intro-step-ky')));
      await settle(t);
      expect(requests.lastWhere((u) => u.path == '/__apps/flows/processes' && u.queryParameters['limit'] == '50').queryParameters['step'], 'ky');
      await done(t);
    });
  }

  testWidgets('chưa chọn, vùng hẹp (< 760px): một cột như cũ', (t) async {
    await pump(t, const Size(960, 800), linkq());
    expect(find.byKey(const ValueKey('intro-steps')), findsNothing);
    expect(find.text('AI ĐƯỢC CHẠY'), findsOneWidget);
    await done(t);
  });

  testWidgets('quy trình không tạo tiến trình: cột các bước theo bước của quy trình, số lần chạy đang ở, bấm để lọc', (t) async {
    await pump(t, const Size(1280, 860), leave());
    await settle(t);
    expect(find.descendant(of: find.byKey(const ValueKey('intro-steps')), matching: find.text('Trưởng phòng duyệt')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('intro-step-duyet')), matching: find.text('3')), findsOneWidget, reason: 'by_step của runs-report');
    expect(find.text('Nghỉ phép 12/11 – 14/11 (Lan)'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('intro-step-bao')));
    await settle(t);
    expect(find.byKey(const ValueKey('step-filter')), findsOneWidget);
    expect(find.text('Nghỉ phép 12/11 – 14/11 (Lan)'), findsNothing, reason: 'lần chạy không chờ ở bước Báo nhân sự');
    await done(t);
  });
}

/// Như tab "Quy trình" của máy tính: danh sách bên trái (460px), trang mở ở vùng bên phải.
class _FlowsSplit extends StatefulWidget {
  const _FlowsSplit();
  @override
  State<_FlowsSplit> createState() => _FlowsSplitState();
}

class _FlowsSplitState extends State<_FlowsSplit> {
  WidgetBuilder? _page;
  int _n = 0;
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return ChatHost(
      openChat: (_) {},
      openInfo: (_) {},
      openThread: (_, _) {},
      openPage: (k, b) => setState(() {
        _page = b;
        _n++;
      }),
      child: Row(children: [
        SizedBox(width: 460, child: Scaffold(body: FlowsHome(app: app, embedded: true, debugPins: const []))),
        Expanded(
          child: _page == null
              ? const SizedBox()
              : PageCloser(
                  onClose: () => setState(() => _page = null),
                  child: Navigator(key: ValueKey('p$_n'), onGenerateRoute: (_) => MaterialPageRoute(builder: _page!)),
                ),
        ),
      ]),
    );
  }
}
