// TeamWork: backend giả (không mạng) theo đúng dạng JSON của flygo-chat-server teamwork/. Dữ liệu mẫu theo mockup: dự án
// "Ra mắt app bán hàng" (RA), hôm nay thứ Năm 19/11/2026 (giờ Việt Nam). Tên người là tên mẫu.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flygo_chat/browser/flygo_id.dart';
import 'package:flygo_chat/ui/teamwork/api.dart';
import 'package:flygo_chat/ui/teamwork/store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> twFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  // Chữ đơn cách cho ô mã / khối mã (ảnh chụp đọc được); không có thì bỏ qua.
  const mono = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf';
  if (File(mono).existsSync()) await (FontLoader('monospace')..addFont(Future.value(ByteData.sublistView(File(mono).readAsBytesSync())))).load();
}

final twNow = DateTime.utc(2026, 11, 19, 3, 0);

/// Mô tả mẫu có bảng (như agent viết): "Quản lý nhóm", 15 tool, ô có `mã`.
final twTableDesc = [
  {'id': 'h', 't': 'h3', 'r': [{'x': 'Quản lý nhóm'}]},
  {'id': 'p', 't': 'p', 'r': [{'x': 'Các tool MCP cần cho phần quản lý nhóm, quyền tối thiểu của bot:'}]},
  {
    'id': 'tb',
    't': 'table',
    'align': ['l', 'l', 'c'],
    'rows': [
      [[{'x': 'Tool'}], [{'x': 'Input chính'}], [{'x': 'Quyền cần'}]],
      for (final (tool, input, perm) in const [
        ('group_list', 'không có', 'đọc'),
        ('group_get', 'group_id', 'đọc'),
        ('group_create', 'name, members[]', 'quản trị'),
        ('group_rename', 'group_id, name', 'quản trị'),
        ('group_delete', 'group_id', 'chủ nhóm'),
        ('member_add', 'group_id, user_ids[]', 'quản trị'),
        ('member_remove', 'group_id, user_id', 'quản trị'),
        ('member_role', 'group_id, user_id, role (owner | admin | member)', 'chủ nhóm'),
        ('invite_link', 'group_id, ttl', 'quản trị'),
        ('message_send', 'group_id, text, reply_to?', 'thành viên'),
        ('message_pin', 'group_id, message_id', 'quản trị'),
        ('message_delete', 'group_id, message_id', 'quản trị'),
        ('poll_create', 'group_id, question, options[]', 'thành viên'),
        ('mute_member', 'group_id, user_id, minutes', 'quản trị'),
        ('export_history', 'group_id, from, to — trả về tệp CSV gồm toàn bộ tin nhắn trong khoảng thời gian', 'chủ nhóm'),
      ])
        [
          [{'x': tool, 'c': true}],
          [{'x': input}],
          [{'x': perm, if (perm == 'chủ nhóm') 'b': true}],
        ],
    ],
  },
];

Map<String, dynamic> _st(String id, String name, String color, String cat, int pos, {int? wip, bool start = false, bool review = false, bool admin = false, bool closeSubs = false}) => {
      'id': id,
      'project_id': 'p-ra',
      'name': name,
      'color': color,
      'category': cat,
      'pos': pos,
      'wip': wip,
      'is_start': start,
      'admin_only': admin,
      'review': review,
      'close_subtasks_prompt': closeSubs,
    };

const _people = {
  'u-lan': 'Lan',
  'u-minh': 'Minh',
  'u-hung': 'Hùng',
  'u-thu': 'Thu',
  'u-quan': 'Quân',
  'u-ha': 'Hà',
  'u-an': 'An',
};
Map<String, dynamic> _u(String id) => {'kind': 'user', 'id': id, 'name': _people[id]};
Map<String, dynamic> _a(String id) => {'kind': 'agent', 'id': id, 'name': id == 'b-claude' ? 'Claude (của Lan)' : 'Codex (của Minh)'};

Map<String, dynamic> _p(String id, String key, String name, String color, String status, Map<String, int> counts, String role, {String desc = '', String? due, bool star = false}) => {
      'id': id,
      'key': key,
      'name': name,
      'description': desc.isEmpty ? [] : [
        {'id': 'd1', 't': 'p', 'r': [{'x': desc}]},
      ],
      'color': color,
      'status': status,
      'dept_ids': [],
      'start': '2026-11-01',
      'due': due,
      'owner': 'u-lan',
      'archived': false,
      'my_role': role,
      'counts': {...counts, 'total': counts.values.fold(0, (a, b) => a + b), 'overdue': 1},
      'starred': star,
      'updated_at': 1000,
    };

class FakeTw {
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};
  bool down = false;
  int _seq = 100;

  final projects = [
    _p('p-ra', 'RA', 'Ra mắt app bán hàng', '#5B5BD6', 'active', {'backlog': 18, 'started': 9, 'closed': 4, 'done': 23}, 'owner',
        desc: 'App đặt hàng cho đại lý: thiết kế, API, kiểm thử, đào tạo đại lý và ra mắt.', due: '2027-01-15', star: true)
      ..['cover'] = {'kind': 'gradient', 'value': 'violet'}
      ..['dept_names'] = ['Kinh doanh', 'Kỹ thuật']
      ..['member_preview'] = [_u('u-lan'), _u('u-minh'), _u('u-hung'), _a('b-claude')],
    _p('p-ht', 'HT', 'Hồ sơ thầu tháng 12', '#E8890C', 'active', {'backlog': 5, 'started': 6, 'closed': 2, 'done': 4}, 'member', desc: 'Hồ sơ năng lực, báo giá, bảo lãnh dự thầu cho 3 gói thầu.', due: '2026-12-05')
      ..['cover'] = {'kind': 'pattern', 'value': '#E8890C', 'pattern': 'dots'}
      ..['dept_names'] = ['Kinh doanh', 'Kế toán']
      ..['member_preview'] = [_u('u-thu'), _u('u-an'), _a('b-codex')],
    _p('p-qt', 'QT', 'Quyết toán năm 2026', '#2B9348', 'active', {'backlog': 22, 'started': 3, 'closed': 1, 'done': 10}, 'admin', desc: 'Khoá sổ, đối chiếu công nợ, kiểm kê kho, báo cáo thuế cuối năm.', due: '2027-01-31')
      ..['cover'] = {'kind': 'gradient', 'value': 'forest'}
      ..['dept_names'] = ['Kế toán']
      ..['member_preview'] = [_u('u-an'), _u('u-ha')],
    _p('p-td', 'TD', 'Tuyển dụng Q1/2027', '#D6409F', 'planning', {'backlog': 14}, 'member', desc: '8 vị trí kỹ thuật, kinh doanh, kế toán, hỗ trợ khách hàng.', due: '2027-03-31'),
    _p('p-bt', 'BT', 'Bảo trì thiết bị', '#0E9F8E', 'active', {'backlog': 6, 'started': 4, 'done': 31}, 'member', desc: 'Lịch bảo trì định kỳ hằng tháng cho khách hàng hợp đồng năm.')
      ..['cover'] = {'kind': 'pattern', 'value': '#0E9F8E', 'pattern': 'waves'}
      ..['dept_names'] = ['Kỹ thuật']
      ..['member_preview'] = [_u('u-hung'), _u('u-quan'), _a('b-codex')],
  ];

  final statuses = [
    _st('s-todo', 'Cần làm', '#8B8D98', 'backlog', 0),
    _st('s-doing', 'Đang làm', '#1E7BFF', 'started', 1, wip: 5, start: true),
    _st('s-review', 'Chờ duyệt', '#E8890C', 'started', 2, wip: 3, review: true),
    _st('s-wait', 'Tạm hoãn', '#D6409F', 'started', 3),
    _st('s-done', 'Xong', '#1F9D55', 'done', 4, closeSubs: true),
    _st('s-cancel', 'Huỷ', '#B0B4BE', 'closed', 5),
  ];

  final labels = [
    {'id': 'l-ui', 'project_id': 'p-ra', 'name': 'Giao diện', 'color': '#1E7BFF'},
    {'id': 'l-hd', 'project_id': 'p-ra', 'name': 'Hợp đồng', 'color': '#E8890C'},
    {'id': 'l-kt', 'project_id': 'p-ra', 'name': 'Kế toán', 'color': '#2B9348'},
    {'id': 'l-gap', 'project_id': 'p-ra', 'name': 'Gấp', 'color': '#E5484D'},
    {'id': 'l-kh', 'project_id': 'p-ra', 'name': 'Khách hàng', 'color': '#7C5CFF'},
  ];

  final members = [
    {'project_id': 'p-ra', 'subject_type': 'user', 'subject_id': 'u-lan', 'role': 'owner', 'name': 'Lan'},
    {'project_id': 'p-ra', 'subject_type': 'user', 'subject_id': 'u-minh', 'role': 'admin', 'name': 'Minh'},
    {'project_id': 'p-ra', 'subject_type': 'user', 'subject_id': 'u-hung', 'role': 'member', 'name': 'Hùng'},
    {'project_id': 'p-ra', 'subject_type': 'user', 'subject_id': 'u-thu', 'role': 'member', 'name': 'Thu'},
    {'project_id': 'p-ra', 'subject_type': 'dept', 'subject_id': 'd-kt', 'role': 'member', 'name': 'Phòng Kỹ thuật', 'members': 9},
    {'project_id': 'p-ra', 'subject_type': 'dept', 'subject_id': 'd-kd', 'role': 'member', 'name': 'Phòng Kinh doanh', 'members': 6},
    {'project_id': 'p-ra', 'subject_type': 'role', 'subject_id': 'r-bgd', 'role': 'viewer', 'name': 'Ban giám đốc', 'members': 3},
  ];

  late final List<Map<String, dynamic>> tasks = _seedTasks();
  final runs = <Map<String, dynamic>>[];
  /// Thao tác của lượt chạy AI dự án (GET /api/runs/:id/actions).
  final actions = <String, List<Map<String, dynamic>>>{
    'r-pdone': [
      {'id': 'a1', 'run_id': 'r-pdone', 'op': 'task_create', 'undoable': true, 'summary': 'Tạo việc "Đào tạo đại lý miền Bắc (40 đại lý)" + 4 việc con', 'target': {'type': 'task', 'id': 't-70', 'key': 'RA-70', 'title': 'Đào tạo đại lý miền Bắc'}, 'at': twNow.millisecondsSinceEpoch - 3500000},
      {'id': 'a2', 'run_id': 'r-pdone', 'op': 'task_assign', 'undoable': true, 'summary': 'Giao RA-41 cho Thu, hạn 12/12', 'target': {'type': 'task', 'id': 't-41', 'key': 'RA-41', 'title': 'Viết tài liệu hướng dẫn đại lý'}, 'at': twNow.millisecondsSinceEpoch - 3400000},
      {'id': 'a3', 'run_id': 'r-pdone', 'op': 'task_update', 'undoable': true, 'summary': 'Dời hạn RA-71 sang 09/01', 'target': {'type': 'task', 'id': 't-71', 'key': 'RA-71', 'title': 'Đào tạo đại lý miền Nam'}, 'at': twNow.millisecondsSinceEpoch - 3300000},
      {'id': 'a4', 'run_id': 'r-pdone', 'op': 'member_remove', 'undoable': true, 'summary': 'Gỡ Quân khỏi dự án', 'severity': 'high', 'target': {'type': 'member', 'id': 'u-quan', 'title': 'Quân'}, 'at': twNow.millisecondsSinceEpoch - 3200000},
    ],
  };
  final userOps = <Map<String, dynamic>>[];
  final deleted = <Map<String, dynamic>>[
    _p('p-old', 'WS', 'Website cũ', '#7C5CFF', 'cancelled', {'done': 3}, 'owner')..['deleted_at'] = twNow.millisecondsSinceEpoch - 2 * 86400000,
  ];
  final userOpReports = <String, Map<String, dynamic>>{};
  /// Tiến độ lượt chạy (GET /api/runs/:id).
  final progress = <String, Map<String, dynamic>>{
    'r-pdone': {
      'id': 'r-pdone', 'kind': 'project', 'project_id': 'p-ra', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'state': 'review', 'seq': 9, 'step_count': 5, 'bypass_eligible': true,
      'progress': {'seq': 9, 'steps': [
        for (final (i, t) in const [(1, '🔓 Chạy không cần duyệt (chủ bot)'), (2, 'Đọc 54 việc'), (3, 'Xem tải việc của 9 thành viên'), (4, 'Tạo 2 việc + 8 việc con'), (5, 'Giao việc, đặt hạn')])
          {'id': 's$i', 'kind': i == 1 ? 'approval' : 'tool', 'title': t, 'status': 'done', 'at': i},
      ]},
      'text': 'Em đã tạo **2 việc** (8 việc con) cho giai đoạn 3 và xếp hạn theo tải hiện tại:\n\n| Việc | Người làm | Hạn |\n|---|---|---|\n| RA-70 Đào tạo miền Bắc | Thu | 05/01 |\n| RA-71 Đào tạo miền Nam | Hà | 09/01 |\n\nQuân không còn việc trong dự án nên em gỡ khỏi danh sách thành viên.',
    },
    'r-c4': {
      'id': 'r-c4', 'kind': 'mention', 'task_id': 't-32', 'comment_id': 'c4', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'state': 'running', 'seq': 5, 'step_count': 4,
      'progress': {'seq': 5, 'steps': [
        {'id': 'tw-mode', 'kind': 'approval', 'title': '🔓 Chạy không cần duyệt (chủ bot)', 'status': 'done', 'at': 1},
        {'id': 's1', 'kind': 'tool', 'title': 'Đọc việc RA-32 và 6 việc con', 'status': 'done', 'at': 2},
        {'id': 's2', 'kind': 'tool', 'title': 'Đọc tệp api/inventory.ts', 'status': 'done', 'at': 3},
        {'id': 's3', 'kind': 'tool', 'title': 'Viết docs/api-ton-kho.md', 'status': 'running', 'at': 4},
      ]},
      'text': '## Tài liệu API tồn kho\n\n| Endpoint | Phương thức | Ghi chú |\n|---|---|---|\n| `/api/stock` | GET | Tồn kho theo mã hàng |\n| `/api/orders` | POST | Tạo đơn, trừ tồn kho |\n\nĐang viết phần lỗi…',
    },
    'r-old': {
      'id': 'r-old', 'kind': 'mention', 'task_id': 't-32', 'comment_id': 'c1', 'bot_id': 'b-codex', 'bot_name': 'Codex', 'state': 'review', 'seq': 12, 'step_count': 7, 'session_channel': 'ch-1',
      'progress': {'seq': 12, 'steps': [
        for (final (i, t) in const [(1, 'Đọc việc RA-32'), (2, 'Đọc api/inventory.ts'), (3, 'Viết test đồng bộ tồn kho'), (4, 'Chạy bun test'), (5, 'Sửa lỗi số âm khi hai đơn cùng lúc'), (6, 'Chạy lại bun test: 14/14 đạt'), (7, 'Bình luận kết quả')])
          {'id': 's$i', 'kind': 'tool', 'title': t, 'status': 'done', 'at': i},
      ]},
    },
    'r-start': {
      'id': 'r-start', 'kind': 'start', 'task_id': 't-32', 'bot_id': 'b-codex', 'bot_name': 'Codex', 'state': 'running', 'seq': 3, 'step_count': 2, 'session_channel': 'ch-1',
      'progress': {'seq': 3, 'steps': [
        {'id': 'a', 'kind': 'approval', 'title': 'Chạy chế độ thường (người giao không phải chủ bot)', 'status': 'done', 'at': 1},
        {'id': 'b', 'kind': 'tool', 'title': 'Chạy bun test tests/inventory.test.ts', 'status': 'running', 'at': 2},
      ]},
    },
  };
  late final List<Map<String, dynamic>> comments = [
    {
      'id': 'c0',
      'task_id': 't-32',
      'parent_id': null,
      'author': 'u-hung',
      'author_name': 'Hùng',
      'via': 'app',
      'blocks': [
        {'id': 'b0', 't': 'p', 'r': [{'x': 'Phần mềm kho mở API đọc tồn kho rồi nhé.'}]},
      ],
      'created_at': twNow.millisecondsSinceEpoch - 40 * 3600000,
      'reactions': [],
      'attachments': [],
    },
    {
      'id': 'c1',
      'task_id': 't-32',
      'parent_id': null,
      'author': 'u-minh',
      'author_name': 'Minh',
      'via': 'app',
      'blocks': [
        {
          'id': 'b1',
          't': 'p',
          'r': [
            {'x': 'Phần đồng bộ chạy ổn. Em giao '},
            {'x': '@Codex (của Minh)', 'm': {'k': 'agent', 'id': 'b-codex'}},
            {'x': ' viết test tồn kho, mai review.'},
          ],
        },
      ],
      'created_at': twNow.millisecondsSinceEpoch - 18 * 3600000,
      'edited_at': null,
      'deleted': false,
      'reactions': [
        {'emoji': '+1', 'users': ['u-lan', 'u-hung', 'u-thu'], 'count': 3},
        {'emoji': 'rocket', 'users': ['u-hung'], 'count': 1},
      ],
      'attachments': [],
      'runs': [
        {'id': 'r-old', 'bot_id': 'b-codex', 'bot_name': 'Codex', 'state': 'review', 'step_count': 7},
      ],
    },
    {
      'id': 'c2',
      'task_id': 't-32',
      'parent_id': null,
      'author': 'u-minh',
      'author_name': 'Minh',
      'via': 'agent:b-codex',
      'agent_id': 'b-codex',
      'agent_name': 'Codex (của Minh)',
      'blocks': [
        {'id': 'b2', 't': 'p', 'r': [{'x': 'Đã viết 14 test cho đồng bộ tồn kho, 13 đạt. Còn 1 lỗi: số âm khi hai đơn đặt cùng lúc. Đề xuất khoá theo mã hàng.'}]},
      ],
      'created_at': twNow.millisecondsSinceEpoch - 3600000,
      'edited_at': null,
      'deleted': false,
      'reactions': [
        {'emoji': 'eyes', 'users': ['u-hung', 'u-thu'], 'count': 2},
      ],
      'attachments': [
        {'id': 'f-log', 'task_id': 't-32', 'comment_id': 'c2', 'name': 'test-ton-kho.log', 'size': 2048, 'mime': 'text/plain', 'source': 'upload'},
      ],
    },
    {
      'id': 'c4',
      'task_id': 't-32',
      'parent_id': null,
      'author': 'u-lan',
      'author_name': 'Lan',
      'via': 'app',
      'blocks': [
        {
          'id': 'b4',
          't': 'p',
          'r': [
            {'x': '@Claude', 'm': {'k': 'agent', 'id': 'b-claude'}},
            {'x': ' viết giúp tài liệu API phần tồn kho cho nhóm app.'},
          ],
        },
      ],
      'created_at': twNow.millisecondsSinceEpoch - 600000,
      'reactions': [],
      'attachments': [],
      'runs': [
        {'id': 'r-c4', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'state': 'running'},
      ],
    },
  ];

  Map<String, dynamic> _t(String id, int n, String title, String status, int prio,
      {List<Map<String, dynamic>> a = const [], List<String> l = const [], String? start, String? due, String? parent, int subT = 0, int subD = 0, int cm = 0, int at = 0, String rank = 'm', Map<String, dynamic>? run}) {
    final cat = statuses.firstWhere((s) => s['id'] == status)['category'];
    return {
      'id': id,
      'project_id': 'p-ra',
      'number': n,
      'key': 'RA-$n',
      'parent_id': parent,
      'title': title,
      'description': [],
      'status_id': status,
      'category': cat,
      'priority': prio,
      'start': start,
      'due': due,
      'estimate': null,
      'progress': subT == 0 ? (cat == 'done' ? 100 : 0) : (subD * 100 / subT).round(),
      'progress_manual': null,
      'rank': rank,
      'labels': l,
      'assignees': a,
      'watchers': ['u-lan'],
      'watching': true,
      'created_by': 'u-lan',
      'created_by_name': 'Lan',
      'created_at': twNow.millisecondsSinceEpoch - (70 - n) * 86400000 ~/ 4,
      'updated_at': twNow.millisecondsSinceEpoch - (70 - n) * 3600000,
      'done_at': cat == 'done' ? 1500 : null,
      'version': 3,
      'deleted_at': null,
      'sub_total': subT,
      'sub_done': subD,
      'comment_count': cm,
      'attachment_count': at,
      'reactions': [],
      'agent_run': run,
    };
  }

  List<Map<String, dynamic>> _seedTasks() => [
        _t('t-41', 41, 'Viết tài liệu hướng dẫn đại lý', 's-todo', 3, a: [_u('u-thu')], l: ['l-kh'], start: '2026-12-04', due: '2026-12-11', rank: 'b')..['blocked_by'] = ['t-39'],
        _t('t-44', 44, 'Chọn ảnh minh hoạ cho trang chủ app', 's-todo', 4, a: [_u('u-lan')], l: ['l-ui'], cm: 2, rank: 'c'),
        _t('t-47', 47, 'Kế hoạch đào tạo 40 đại lý miền Bắc', 's-todo', 2, a: [_u('u-thu'), _u('u-ha')], subT: 5, start: '2026-12-08', due: '2026-12-15', rank: 'd')
          ..['blocked_by'] = ['t-41'],
        _t('t-32', 32, 'API đặt hàng + đồng bộ tồn kho', 's-doing', 1,
            a: [_u('u-minh'), _a('b-codex')], l: ['l-gap'], start: '2026-11-21', due: '2026-11-28', subT: 6, subD: 3, cm: 2, at: 2, rank: 'b',
            run: {'id': 'r-start', 'kind': 'start', 'task_id': 't-32', 'bot_id': 'b-codex', 'bot_name': 'Codex', 'started_by': 'u-minh', 'state': 'running', 'session_channel': 'ch-1'})
          ..['blocked_by'] = ['t-29'],
        _t('t-35', 35, 'Màn hình giỏ hàng & thanh toán', 's-doing', 2, a: [_u('u-lan')], l: ['l-ui'], start: '2026-11-17', due: '2026-12-02', subT: 4, subD: 2, cm: 5, rank: 'c'),
        _t('t-38', 38, 'Bảng giá theo cấp đại lý', 's-doing', 3, a: [_u('u-an')], l: ['l-kt'], start: '2026-11-22', due: '2026-11-25', cm: 1, rank: 'd'),
        _t('t-39', 39, 'Soạn hợp đồng đại lý mẫu', 's-doing', 3, a: [_u('u-ha')], l: ['l-hd'], start: '2026-11-24', due: '2026-12-01', at: 3, rank: 'e'),
        _t('t-29', 29, 'Thiết kế logo & bộ nhận diện app', 's-review', 2, a: [_u('u-lan')], l: ['l-ui'], start: '2026-11-16', due: '2026-11-21', cm: 12, at: 6, rank: 'b'),
        _t('t-30', 30, 'Tóm tắt phản hồi khảo sát 120 đại lý', 's-review', 3, a: [_a('b-claude')], cm: 3, at: 1, rank: 'c',
            run: {'id': 'r-30', 'task_id': 't-30', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'started_by': 'u-lan', 'state': 'review', 'session_channel': 'ch-2'}),
        _t('t-33', 33, 'Chính sách đổi trả', 's-review', 3, a: [_u('u-ha'), _u('u-thu')], l: ['l-hd'], start: '2026-11-28', due: '2026-12-01', rank: 'd'),
        _t('t-26', 26, 'Tích hợp ví điện tử', 's-wait', 4, a: [_u('u-minh')], cm: 4, rank: 'b'),
        _t('t-21', 21, 'Khảo sát nhu cầu đại lý', 's-done', 3, a: [_u('u-thu')], subT: 4, subD: 4, start: '2026-11-02', due: '2026-11-10', rank: 'b'),
        _t('t-22', 22, 'Chốt phạm vi phiên bản 1', 's-done', 2, a: [_u('u-lan'), _u('u-minh')], rank: 'c'),
        // Việc con của RA-32.
        _t('t-60', 60, 'Thiết kế bảng dữ liệu đơn hàng', 's-done', 0, a: [_u('u-minh')], parent: 't-32', rank: 'b'),
        _t('t-61', 61, 'API tạo / huỷ đơn', 's-done', 0, a: [_u('u-minh')], parent: 't-32', rank: 'c'),
        _t('t-62', 62, 'Đồng bộ tồn kho từ phần mềm kho mỗi 5 phút', 's-done', 0, a: [_a('b-codex')], parent: 't-32', rank: 'd'),
        _t('t-63', 63, 'Viết test tồn kho', 's-doing', 0, a: [_a('b-codex')], parent: 't-32', start: '2026-11-23', due: '2026-11-26', rank: 'e'),
        _t('t-64', 64, 'Giới hạn số lượng theo hạn mức đại lý', 's-todo', 0, a: [_u('u-minh')], parent: 't-32', rank: 'f'),
        _t('t-65', 65, 'Tài liệu API cho nhóm app', 's-todo', 0, a: [_a('b-claude')], parent: 't-32', rank: 'g'),
      ];

  Map<String, dynamic> task(String ref) => tasks.firstWhere((t) => t['id'] == ref || t['key'] == ref);

  Map<String, dynamic> _full(String pid) {
    final p = projects.firstWhere((x) => x['id'] == pid || x['key'] == pid);
    return {'project': p, 'statuses': p['id'] == 'p-ra' ? statuses : [statuses[0], statuses[1], statuses[4]], 'labels': p['id'] == 'p-ra' ? labels : [], 'members': p['id'] == 'p-ra' ? members : [], 'my_role': p['my_role']};
  }

  static http.Response _ok(Object body, [int code = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), code, headers: {'content-type': 'application/json'});

  http.Client client() => MockClient((req) async {
        final p = req.url.path;
        if (p == '/v1/token') return _ok({'token': 'tk', 'expires_in': 600});
        if (down) throw const SocketException('mất mạng');
        final key = '${req.method} $p${req.url.hasQuery ? '?${req.url.query}' : ''}';
        calls.add(key);
        Map<String, dynamic> body = {};
        if (req.method != 'GET' && req.body.isNotEmpty) {
          try {
            body = (jsonDecode(req.body) as Map).cast<String, dynamic>();
          } catch (_) {}
        }
        bodies[key] = body;
        final q = req.url.queryParameters;
        RegExpMatch? m(String re) => RegExp('^/tw/api$re\$').firstMatch(p);
        RegExpMatch? x;

        if (p == '/tw/api/me') return _ok({'user': {'id': 'u-lan', 'name': 'Lan', 'username': 'lan'}, 'bot_user_id': 'bot-tw', 'is_admin': false, 'prefs': {'dm': {'assigned': true, 'mention': true, 'comment': true, 'status': true, 'due': true, 'agent': true}}});
        if (p == '/tw/api/me/prefs') return _ok({'prefs': body});
        if (p == '/tw/api/projects' && req.method == 'GET') return _ok({'projects': q['deleted'] == '1' ? deleted : projects});
        if (p == '/tw/api/projects' && req.method == 'POST') {
          final n = _p('p-new', '${body['key']}', '${body['name']}', '${body['color']}', 'active', {}, 'owner');
          projects.add(n);
          return _ok({..._full('p-new'), 'statuses': statuses}, 201);
        }
        if ((x = m(r'/projects/([\w-]+)')) != null) {
          if (req.method == 'PATCH') projects.firstWhere((pr) => pr['id'] == x![1]).addAll(body);
          return _ok(_full(x![1]!));
        }
        if ((x = m(r'/projects/([\w-]+)/tasks')) != null) {
          if (req.method == 'POST') {
            final n = _seq++;
            final t = _t('t-$n', n, '${body['title']}', '${body['status_id'] ?? 's-todo'}', (body['priority'] as num?)?.toInt() ?? 0,
                a: [for (final a in body['assignees'] as List? ?? const []) (a as Map).cast<String, dynamic>()], parent: body['parent_id'] as String?, rank: 'z', due: body['due'] as String?);
            tasks.add(t);
            return _ok({'task': t}, 201);
          }
          return _ok({'tasks': x![1] == 'p-ra' ? tasks : [], 'next_cursor': null});
        }
        if ((x = m(r'/projects/([\w-]+)/members')) != null) return _ok({'members': members});
        if ((x = m(r'/projects/([\w-]+)/statuses')) != null) {
          final s = {...body, 'id': 's-new', 'project_id': x![1]};
          statuses.add(s.cast<String, dynamic>());
          return _ok({'status': s}, 201);
        }
        if ((x = m(r'/projects/([\w-]+)/statuses/order')) != null) return _ok({'statuses': statuses});
        if ((x = m(r'/statuses/([\w-]+)')) != null) {
          final s = statuses.firstWhere((s) => s['id'] == x![1]);
          if (body['is_start'] == true) {
            for (final o in statuses) {
              o['is_start'] = false;
            }
          }
          s.addAll(body);
          return _ok({'status': s});
        }
        if (p == '/tw/api/tasks/mine') {
          return _ok({
            'tasks': [for (final t in tasks) if ((t['assignees'] as List).any((a) => a['id'] == 'u-lan') && t['category'] != 'done') t],
            'projects': {'p-ra': {'key': 'RA', 'name': 'Ra mắt app bán hàng', 'color': '#5B5BD6', 'my_role': 'owner'}},
          });
        }
        if (p == '/tw/api/tasks/bulk') {
          for (final id in body['ids'] as List) {
            task('$id').addAll((body['patch'] as Map).cast<String, dynamic>());
          }
          return _ok({'results': []});
        }
        if ((x = m(r'/tasks/([\w-]+)')) != null) {
          final t = task(x![1]!);
          if (req.method == 'PATCH') {
            t.addAll(Map.of(body)..remove('base_version'));
            if (body.containsKey('status_id')) t['category'] = statuses.firstWhere((s) => s['id'] == body['status_id'])['category'];
            t['version'] = (t['version'] as int) + 1;
            return _ok({'task': t});
          }
          if (req.method == 'DELETE') {
            tasks.remove(t);
            return _ok({'ok': true});
          }
          final subs = <Map<String, dynamic>>[];
          void walk(String id) {
            for (final s in tasks.where((s) => s['parent_id'] == id)) {
              subs.add(s);
              walk(s['id'] as String);
            }
          }

          walk(t['id'] as String);
          return _ok({
            'task': {
              ...t,
              if (t['id'] == 't-32')
                'description': [
                  {'id': 'd1', 't': 'p', 'r': [{'x': 'Mục tiêu: ', 'b': true}, {'x': 'đại lý đặt hàng trên app, hệ thống trừ tồn kho ngay và báo lại nếu hết hàng.'}]},
                  {'id': 'd2', 't': 'h3', 'r': [{'x': 'Yêu cầu'}]},
                  {'id': 'd3', 't': 'ul', 'r': [{'x': 'Đơn tối thiểu theo cấp đại lý (xem '}, {'x': 'RA-38', 'm': {'k': 'task', 'id': 'RA-38'}}, {'x': ')'}]},
                  {'id': 'd4', 't': 'ul', 'r': [{'x': 'Tồn kho lấy từ phần mềm kho, '}, {'x': 'không', 'i': true}, {'x': ' nhập tay'}]},
                  {'id': 'd5', 't': 'ul', 'r': [{'x': 'Lỗi đồng bộ quá 15 phút thì báo '}, {'x': '@Hùng', 'm': {'k': 'user', 'id': 'u-hung'}}]},
                ],
              if (t['id'] == 't-38') 'description': twTableDesc,
            },
            'subtasks': subs,
            'links': t['id'] == 't-32'
                ? [
                    {'id': 'k1', 'type': 'blocks', 'direction': 'out', 'task': {'id': 't-41', 'key': 'RA-41', 'title': 'Viết tài liệu hướng dẫn đại lý', 'status_id': 's-todo'}},
                    {'id': 'k2', 'type': 'blocks', 'direction': 'in', 'task': {'id': 't-29', 'key': 'RA-29', 'title': 'Thiết kế logo', 'status_id': 's-review'}},
                  ]
                : [],
            'attachments': t['id'] == 't-32'
                ? [
                    {'id': 'f1', 'task_id': 't-32', 'name': 'Danh mục hàng.xlsx', 'size': 86016, 'mime': 'application/vnd.ms-excel', 'source': 'drive', 'drive_url': 'https://drive.example.com/f/1'},
                    {'id': 'f2', 'task_id': 't-32', 'name': 'Đặc tả API v2.pdf', 'size': 1258291, 'mime': 'application/pdf', 'source': 'upload'},
                  ]
                : [],
            'runs': [for (final r in runs.reversed) if (r['task_id'] == t['id']) r, if (t['agent_run'] != null) t['agent_run']],
            'parents': t['parent_id'] == null ? [] : [{'id': t['parent_id'], 'key': task(t['parent_id'] as String)['key'], 'title': task(t['parent_id'] as String)['title']}],
            'project': {'id': 'p-ra', 'key': 'RA', 'name': 'Ra mắt app bán hàng', 'color': '#5B5BD6', 'my_role': 'owner'},
          });
        }
        if ((x = m(r'/tasks/([\w-]+)/move')) != null) {
          final t = task(x![1]!);
          if (body['status_id'] != null) {
            t['status_id'] = body['status_id'];
            t['category'] = statuses.firstWhere((s) => s['id'] == body['status_id'])['category'];
            final st = statuses.firstWhere((s) => s['id'] == body['status_id']);
            if (st['is_start'] == true) {
              for (final a in (t['assignees'] as List).where((a) => a['kind'] == 'agent')) {
                runs.add({'id': 'r-${_seq++}', 'task_id': t['id'], 'bot_id': a['id'], 'bot_name': a['name'], 'started_by': 'u-lan', 'state': 'queued'});
              }
            }
          }
          return _ok({'task': t});
        }
        if ((x = m(r'/tasks/([\w-]+)/start')) != null) {
          final t = task(x![1]!);
          final made = [
            for (final a in (t['assignees'] as List).where((a) => a['kind'] == 'agent')) {'id': 'r-${_seq++}', 'task_id': t['id'], 'bot_id': a['id'], 'bot_name': a['name'], 'started_by': 'u-lan', 'state': 'queued'},
          ];
          runs.addAll(made);
          return _ok({'runs': made, 'active': made});
        }
        if (p == '/tw/api/runs') return _ok({'runs': [for (final r in runs) if (q['state'] == null || r['state'] == q['state']) {...r, if (r['task_id'] != null) 'task_key': task(r['task_id'] as String)['key']}]});
        if ((x = m(r'/runs/([\w-]+)/claim')) != null) {
          final r = runs.firstWhere((r) => r['id'] == x![1]);
          if (r['claimed'] == true) return _ok({'error': 'lượt chạy đã được một máy khác nhận', 'code': 'claimed'}, 409);
          r['claimed'] = true;
          r['attest_owner'] = body['attest_owner'] == true;
          return _ok({
            'run': r,
            'brief': r['task_id'] == null ? 'BRIEF PROJECT ${r['project_id']}' : 'BRIEF ${task(r['task_id'] as String)['key']}',
            'run_token': 'TOKEN-${r['id']}',
            'task': r['task_id'] == null ? null : {'id': r['task_id']},
            if (r['task_id'] == null) 'project': {'id': r['project_id'], 'key': 'RA', 'name': 'Ra mắt app bán hàng'},
            if (r['thread_id'] != null) 'thread_id': r['thread_id'],
          });
        }
        if ((x = m(r'/runs/([\w-]+)/cancel')) != null) return _ok({'run': {'id': x![1], 'state': 'cancelled'}});
        if ((x = m(r'/runs/([\w-]+)')) != null && req.method == 'GET') {
          final r = progress[x![1]] ?? runs.where((r) => r['id'] == x![1]).firstOrNull;
          return r == null ? _ok({'error': 'không có', 'code': 'not_found'}, 404) : _ok({'run': r});
        }
        if ((x = m(r'/runs/([\w-]+)')) != null) {
          final r = runs.where((r) => r['id'] == x![1]).firstOrNull;
          r?.addAll(body);
          return _ok({'run': r ?? {}});
        }
        if ((x = m(r'/tasks/([\w-]+)/comments')) != null) {
          if (req.method == 'POST') {
            final c = {
              'id': 'c${_seq++}',
              'task_id': x![1],
              'parent_id': body['parent_id'],
              'author': 'u-lan',
              'author_name': 'Lan',
              'via': 'app',
              'blocks': body['blocks'],
              'created_at': twNow.millisecondsSinceEpoch,
              'reactions': [],
              'attachments': [],
            };
            comments.add(c);
            return _ok({'comment': c}, 201);
          }
          return _ok({'comments': [for (final c in comments) if (c['task_id'] == task(x![1]!)['id']) c]});
        }
        if ((x = m(r'/tasks/([\w-]+)/activity')) != null) {
          return _ok({
            'activity': [
              {'id': 'a1', 'actor': 'u-minh', 'actor_name': 'Minh', 'via': 'app', 'type': 'status', 'data': {'from': 's-todo', 'to': 's-doing'}, 'at': twNow.millisecondsSinceEpoch - 3 * 86400000},
              {'id': 'a2', 'actor': 'u-minh', 'actor_name': 'Minh', 'via': 'app', 'type': 'created', 'data': {}, 'at': twNow.millisecondsSinceEpoch - 5 * 86400000},
            ],
          });
        }
        if ((x = m(r'/tasks/([\w-]+)/schedule-preview')) != null) {
          return _ok({
            'dependents': [
              {'id': 't-33', 'key': 'RA-33', 'title': 'Chính sách đổi trả', 'start': '2026-11-28', 'due': '2026-12-01', 'new_start': '2026-11-29', 'new_due': '2026-12-02'},
            ],
          });
        }
        if ((x = m(r'/tasks/([\w-]+)/schedule')) != null) {
          final t = task(x![1]!);
          t['start'] = body['start'];
          t['due'] = body['due'];
          return _ok({'changed': [t]});
        }
        if ((x = m(r'/tasks/([\w-]+)/assignees')) != null) {
          final t = task(x![1]!);
          t['assignees'] = body['assignees'];
          return _ok({'task': t});
        }
        if ((x = m(r'/tasks/([\w-]+)/ai')) != null) {
          return switch (body['action']) {
            'breakdown' => _ok({
                'subtasks': [
                  {'title': 'Khoá tồn kho theo mã hàng khi đặt đơn', 'assignee': 'u-minh', 'assignee_name': 'Minh', 'due': '2026-11-24'},
                  {'title': 'Test tải: 50 đơn / giây', 'assignee': null, 'due': '2026-11-25'},
                ],
              }),
            'suggest' => _ok({'suggestion': {'assignees': [{'id': 'u-hung', 'name': 'Hùng'}], 'start': '2026-11-21', 'due': '2026-11-27', 'reason': 'Hùng đang ít việc nhất trong phòng Kỹ thuật.'}}),
            _ => _ok({'text': '- Đồng bộ tồn kho đã chạy, 3/6 việc con xong.\n- Lỗi còn lại: tồn kho âm khi 2 đơn cùng lúc.\n- Rủi ro trễ hạn 28/11: **thấp** nếu sửa trước 25/11.'}),
          };
        }
        if (p == '/tw/api/reactions') return _ok({'ok': true});
        if (p == '/tw/api/subjects') {
          return _ok({
            'subjects': [
              {'type': 'everyone', 'id': '*', 'name': 'Mọi người'},
              {'type': 'dept', 'id': 'd-kt', 'name': 'Phòng Kỹ thuật', 'members': 9},
              {'type': 'role', 'id': 'r-bgd', 'name': 'Ban giám đốc', 'members': 3},
              for (final e in _people.entries) {'type': 'user', 'id': e.key, 'name': e.value, 'username': e.key.substring(2)},
            ],
          });
        }
        if (p == '/tw/api/agents') {
          return _ok({
            'agents': [
              {'id': 'b-claude', 'name': 'Claude', 'username': 'lan-claude', 'owner_id': 'u-lan', 'owner_name': 'Lan'},
              {'id': 'b-codex', 'name': 'Codex', 'username': 'minh-codex', 'owner_id': 'u-minh', 'owner_name': 'Minh'},
            ],
          });
        }
        if (p == '/tw/api/notifications') {
          return _ok({
            'items': [
              {'id': 3, 'kind': 'agent', 'task_key': 'RA-30', 'task_id': 't-30', 'text': 'Claude đã nộp kết quả RA-30, chờ bạn duyệt', 'at': twNow.millisecondsSinceEpoch - 600000, 'read': false},
              {'id': 2, 'kind': 'mention', 'task_key': 'RA-32', 'task_id': 't-32', 'text': 'Minh nhắc bạn trong RA-32', 'at': twNow.millisecondsSinceEpoch - 7200000, 'read': false},
              {'id': 1, 'kind': 'assigned', 'task_key': 'RA-44', 'task_id': 't-44', 'text': 'Minh giao cho bạn RA-44', 'at': twNow.millisecondsSinceEpoch - 86400000, 'read': true},
            ],
            'unread': 2,
          });
        }
        if (p == '/tw/api/notifications/read') return _ok({'unread': 0});
        if (p == '/tw/api/search') {
          final s = '${q['q']}'.toLowerCase();
          return _ok({'results': [for (final t in tasks) if ('${t['title']}'.toLowerCase().contains(s)) {'id': t['id'], 'key': t['key'], 'title': t['title'], 'status_id': t['status_id'], 'project_id': 'p-ra'}]});
        }
        // ---- AI của dự án
        if ((x = m(r'/projects/([\w-]+)/ai')) != null && req.method == 'POST') {
          final id = 'r-p${_seq++}';
          final r = {'id': id, 'kind': 'project', 'task_id': null, 'project_id': x![1], 'thread_id': body['thread_id'] ?? 'th-new', 'prompt': body['prompt'], 'action': body['action'], 'bot_id': body['bot_id'], 'bot_name': body['bot_id'] == 'b-claude' ? 'Claude' : 'Codex', 'started_by': 'u-lan', 'state': 'queued', 'created_at': twNow.millisecondsSinceEpoch};
          runs.add(r);
          progress[id] = {...r, 'state': 'running', 'progress': {'seq': 2, 'steps': [
            {'id': 'tw-mode', 'kind': 'approval', 'title': '🔓 Chạy không cần duyệt (chủ bot)', 'status': 'done', 'at': 1},
            {'id': 's1', 'kind': 'tool', 'title': 'Đọc 19 việc của dự án', 'status': 'running', 'at': 2},
          ]}, 'text': '## Tiến độ tuần 47\n- **23/54** việc xong…'};
          return _ok({'run': r, 'thread': {'id': body['thread_id'] ?? 'th-new', 'project_id': x[1]}}, 201);
        }
        if ((x = m(r'/projects/([\w-]+)/ai/threads')) != null) {
          return _ok({'threads': [
            {'id': 'th0', 'project_id': 'p-ra', 'user': 'u-lan', 'title': 'Kế hoạch giai đoạn 3', 'created_at': twNow.millisecondsSinceEpoch - 7200000, 'updated_at': twNow.millisecondsSinceEpoch - 3600000, 'run_count': 1, 'last_run': {'id': 'r-pdone', 'state': 'review', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'action': 'plan'}},
          ]});
        }
        if ((x = m(r'/ai/threads/([\w-]+)')) != null) {
          return _ok({
            'thread': {'id': x![1], 'project_id': 'p-ra', 'user': 'u-lan', 'title': 'Kế hoạch giai đoạn 3', 'run_count': 2},
            'runs': [
              {...progress['r-pdone']!, 'actions': actions['r-pdone']},
              {'id': 'r-pupd', 'kind': 'project', 'project_id': 'p-ra', 'thread_id': x[1], 'prompt': 'Soạn cập nhật cho nhóm', 'action': 'update', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'state': 'review', 'created_at': twNow.millisecondsSinceEpoch - 1800000},
            ],
          });
        }
        if ((x = m(r'/runs/([\w-]+)/actions')) != null) return _ok({'actions': actions[x![1]] ?? []});
        if ((x = m(r'/runs/([\w-]+)/actions/([\w-]+)/undo')) != null) {
          final a = actions[x![1]]!.firstWhere((a) => a['id'] == x![2]);
          if (x[2] == 'a3') return _ok({'code': 'conflict', 'action': a}, 409);
          a['undone_at'] = twNow.millisecondsSinceEpoch;
          return _ok({'result': 'ok', 'action': a});
        }
        if ((x = m(r'/runs/([\w-]+)/undo')) != null) {
          for (final a in actions[x![1]] ?? <Map<String, dynamic>>[]) {
            if (a['id'] != 'a3') a['undone_at'] = twNow.millisecondsSinceEpoch;
          }
          return _ok({'results': [for (final a in actions[x[1]] ?? []) {'id': a['id'], 'ok': a['id'] != 'a3', if (a['id'] == 'a3') 'conflict': true}], 'actions': actions[x[1]]});
        }
        if ((x = m(r'/projects/([\w-]+)/chat-channel')) != null) {
          final pr = projects.firstWhere((pr) => pr['id'] == x![1]);
          pr['chat_channel'] = req.method == 'DELETE' ? null : body;
          return _ok({'ok': true});
        }
        if ((x = m(r'/projects/([\w-]+)/chat-channel/post')) != null) return _ok({'ok': true, 'post_id': 'post1'});
        if ((x = m(r'/projects/([\w-]+)/restore')) != null) {
          final d = deleted.firstWhere((d) => d['id'] == x![1]);
          deleted.remove(d);
          projects.add(d..remove('deleted_at'));
          return _ok({'project': d});
        }
        if (p == '/tw/api/user-ops') return _ok({'ops': userOps});
        if ((x = m(r'/user-ops/([\w-]+)')) != null) {
          userOpReports[x![1]!] = body;
          return _ok({'ok': true});
        }
        return _ok({'error': 'không có', 'code': 'not_found'}, 404);
      });
}

/// Mở phiên giả: ghi lại các lần mở / dừng.
class FakeLauncher implements TwAgentLauncher {
  final launched = <(String, String, String)>[];
  final stopped = <String>[];
  final posted = <(String, String)>[];
  final props = <Map<String, dynamic>>[];
  Set<String> allowed = {'b-claude', 'b-codex'};
  Set<String> usable = {};
  Set<String> owned = {'b-claude'};
  @override
  Future<bool> isOwnerOf(String botId) async => owned.contains(botId);
  @override
  Future<bool> sessionUsable(String channelId, String botId) async => usable.contains(channelId);
  @override
  Future<void> post(String channelId, String text, {Map<String, dynamic> props = const {}}) async {
    posted.add((channelId, text));
    this.props.add(props);
  }
  @override
  Future<bool> canUse(String botId) async => allowed.contains(botId);
  @override
  Future<String> launch(String botId, String title, String brief, {Map<String, dynamic> props = const {}}) async {
    launched.add((botId, title, brief));
    this.props.add(props);
    return 'ch-new-$botId';
  }

  @override
  Future<void> stop(String channelId) async => stopped.add(channelId);
  @override
  void open(String channelId) {}
}

/// Thao tác chat giả (token của người dùng): ghi lại kênh tạo / thành viên thêm / kênh mở.
class FakeChatOps implements TwChatOps {
  final created = <Map<String, dynamic>>[];
  final added = <(String, String)>[];
  final opened = <String>[];
  Set<String> memberOf = {'ch-old'};
  @override
  Future<TwChannelInfo> createChannel({String? teamId, required String name, required String displayName, bool private = true, String purpose = '', String header = ''}) async {
    created.add({'team': teamId, 'name': name, 'display_name': displayName, 'private': private, 'purpose': purpose, 'header': header});
    final id = 'ch-new${created.length}';
    return (id: id, teamId: teamId ?? 'team-1', name: name, displayName: displayName, url: 'https://chat.example.com/flygo/channels/$name');
  }

  @override
  Future<TwChannelInfo?> resolveChannel(String ref) async {
    final id = ref.startsWith('~') ? 'ch-${ref.substring(1)}' : ref;
    return id == 'ch-gone' ? null : (id: id, teamId: 'team-1', name: id.replaceFirst('ch-', ''), displayName: id == 'ch-old' ? 'Kênh Kỹ thuật' : id, url: 'https://chat.example.com/flygo/channels/${id.replaceFirst('ch-', '')}');
  }

  @override
  Future<void> addMember(String channelId, String userId) async => added.add((channelId, userId));
  @override
  Future<bool> isMember(String channelId) async => memberOf.contains(channelId);
  @override
  Future<String?> bestTeam(List<String> userIds) async => 'team-1';
  @override
  Future<List<(String, String)>> myChannels() async => [('ch-old', 'Kênh Kỹ thuật'), ('ch-sales', 'Phòng Kinh doanh')];
  @override
  Future<String?> userIdByUsername(String username) async => 'bot-tw';
  @override
  void openChannel(String channelId) => opened.add(channelId);
}

TwStore newTwStore(FakeTw be, {FakeLauncher? launcher, FakeChatOps? chat}) {
  final c = be.client();
  return TwStore(TwApi(base: 'https://chat.test/tw', id: FlygoId(base: 'https://id.test', chatToken: 'mm', client: c), client: c), clock: () => twNow, live: false)
    ..launcher = launcher ?? FakeLauncher()
    ..chatOps = chat ?? FakeChatOps();
}
