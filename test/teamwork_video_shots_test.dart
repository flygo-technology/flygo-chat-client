// Ảnh cho video giới thiệu "Làm việc nhóm": giao diện thật + dữ liệu giả, giao diện sáng, nét gấp đôi (1440x900 điểm →
// 2880x1800 px). Mỗi ảnh kèm toạ độ các phần tử (điểm logic) trong layout.json để trang video đặt lớp động đúng chỗ.
// Chạy tay: TW_VIDEO_OUT=<thư mục> flutter test test/teamwork_video_shots_test.dart (không đặt biến thì chỉ chạy, không ghi).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/teamwork/store.dart';
import 'package:flygo_chat/ui/teamwork/task_page.dart';
import 'package:flygo_chat/ui/teamwork/teamwork_page.dart';
import 'package:flygo_chat/ui/theme.dart';

import 'fixtures/teamwork_fake.dart';

const _desk = Size(1440, 900), _phone = Size(390, 844);
const _dpr = 2.0;
final _out = Platform.environment['TW_VIDEO_OUT'];
final _layout = <String, Map<String, List<double>>>{};

/// Dữ liệu giả riêng cho video: bỏ dự án dễ gợi tới khách hàng thật.
void videoData(FakeTw be) {
  final bt = be.projects.firstWhere((p) => p['id'] == 'p-bt');
  bt['name'] = 'Khai trương chi nhánh mới';
  bt['key'] = 'KC';
  for (final r in be.progress.values) {
    for (final st in (r['progress']?['steps'] as List?) ?? []) {
      st['title'] = '${st['title']}'.replaceAll('🔓 ', '');
    }
  }
  bt['description'] = [
    {'id': 'd1', 't': 'p', 'r': [{'x': 'Mặt bằng, nhân sự, hàng hoá và sự kiện khai trương ngày 20/12.'}]},
  ];
}

void main() {
  late FakeTw be;
  late FakeAiSessions ai;
  setUp(() {
    be = FakeTw();
    ai = FakeAiSessions();
    videoData(be);
  });
  tearDownAll(() {
    if (_out == null) return;
    File('$_out/layout.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(_layout));
  });

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<TwStore> pump(WidgetTester t, {Size size = _desk, String? section, String? project, String? view}) async {
    t.view.physicalSize = size * _dpr;
    t.view.devicePixelRatio = _dpr;
    addTearDown(t.view.reset);
    await t.runAsync(twFonts);
    final s = newTwStore(be, launcher: FakeLauncher(), ai: ai);
    await t.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: TeamworkHome(store: s, ownsStore: false, initialSection: section, initialProject: project, initialView: view),
      ),
    ));
    await settle(t, 10);
    return s;
  }

  /// Chụp ảnh và ghi toạ độ (trái, trên, rộng, cao) của các key cho trước.
  Future<void> shot(WidgetTester t, String name, [List<String> keys = const []]) async {
    await t.pump(const Duration(milliseconds: 300));
    _layout[name] = {
      for (final k in keys)
        if (find.byKey(ValueKey(k)).evaluate().isNotEmpty) k: (() {
          final r = t.getRect(find.byKey(ValueKey(k)).first);
          return [r.left, r.top, r.width, r.height];
        })(),
    };
    if (_out == null) return;
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage(pixelRatio: _dpr);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out!).createSync(recursive: true);
      await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> openTaskPage(WidgetTester t, TwStore s, String key) async {
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(nav.push(MaterialPageRoute(builder: (_) => TwTaskPage(store: s, idOrKey: key, showAi: false))));
    await settle(t, 10);
  }

  Future<void> done(WidgetTester t, TwStore s) async {
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
    s.dispose();
  }

  testWidgets('S3 tất cả dự án', (t) async {
    final s = await pump(t);
    expect(find.text('Khai trương chi nhánh mới'), findsWidgets);
    expect(find.text('Bảo trì thiết bị'), findsNothing);
    await shot(t, 'v-projects', ['project-RA', 'project-HT', 'project-QT']);
    await done(t, s);
  });

  testWidgets('S4 Kanban: kéo RA-41 sang Đang làm, Danh sách, Gantt', (t) async {
    final s = await pump(t, project: 'RA', view: 'kanban');
    const cols = ['column-s-todo', 'column-s-doing', 'column-s-review', 'column-s-wait'];
    await shot(t, 'v-kanban-before', ['card-RA-41', 'view-list', 'view-gantt', 'view-kanban', ...cols]);
    final ra41 = s.tasksOf('p-ra').firstWhere((x) => x.key == 'RA-41');
    // Ảnh "đang kéo": thẻ rời khỏi cột (tạm cho sang cột Huỷ, nằm ngoài khung nhìn).
    await s.moveTask(ra41, statusId: 's-cancel');
    await settle(t, 4);
    expect(find.byKey(const ValueKey('card-RA-41')), findsNothing);
    await shot(t, 'v-kanban-gap', cols);
    final doing = s.tasksOf('p-ra').where((x) => x.statusId == 's-doing' && x.parentId == null).toList()..sort((a, b) => a.rank.compareTo(b.rank));
    await s.moveTask(ra41, statusId: 's-doing', after: doing.last);
    await settle(t, 4);
    await shot(t, 'v-kanban-after', ['card-RA-41', ...cols]);
    await done(t, s);

    final l = await pump(t, project: 'RA', view: 'list');
    await shot(t, 'v-list');
    await done(t, l);

    final g = await pump(t, project: 'RA', view: 'gantt');
    await shot(t, 'v-gantt', ['gbar-RA-32', 'gbar-RA-29']);
    await done(t, g);
  });

  testWidgets('S5 chi tiết việc: @nhắc Claude trong bình luận → đang làm → xong', (t) async {
    final s = await pump(t, project: 'RA');
    await openTaskPage(t, s, 'RA-32');
    await t.ensureVisible(find.byKey(const ValueKey('comment-send')));
    await t.pump();
    await shot(t, 'v-task', ['rt-mention', 'comment-send', 'right-col']);
    await t.tap(find.byKey(const ValueKey('rt-mention')).last);
    await settle(t, 4);
    await shot(t, 'v-task-picker', ['mention-agent-b-claude', 'rt-mention']);
    await t.tap(find.byKey(const ValueKey('mention-agent-b-claude')));
    await settle(t, 3);
    expect(find.text('Claude sẽ đọc việc này và làm theo bình luận'), findsOneWidget);
    await shot(t, 'v-task-mention', ['comment-send', 'agent-hint']);
    final col = find.descendant(of: find.byKey(const ValueKey('right-col')), matching: find.byType(Scrollable)).first;
    await t.scrollUntilVisible(find.byKey(const ValueKey('run-text-r-c4')), 100, scrollable: col);
    await settle(t, 2);
    expect(find.text('Claude đang xử lý… · 4 bước'), findsOneWidget);
    await shot(t, 'v-task-running', ['run-text-r-c4']);
    be.progress['r-c4']!['state'] = 'review';
    s.debugEvent({'type': 'run_progress', 'id': 'r-c4', 'task_id': 't-32', 'project_id': 'p-ra', 'seq': 7});
    await settle(t, 8);
    expect(find.text('Claude đã xong · 4 bước'), findsOneWidget);
    await shot(t, 'v-task-done');
    await done(t, s);
  });

  testWidgets('S6–S7 AI của dự án: lập kế hoạch (tạo việc, giao, đặt hạn, Hoàn tác) rồi tạo nhóm chat', (t) async {
    final pid = FakeAiSessions.chId('aiprojra'), team = FakeAiSessions.chId('team');
    ai.projects[pid] = (channelId: pid, teamId: team, name: 'p-lan-ra', displayName: 'Ra mắt app bán hàng');
    ai.sessionsOf[pid] = [];
    be.projects.first['ai_project'] = {'channel_id': pid, 'team_id': team, 'name': 'p-lan-ra', 'display_name': 'Ra mắt app bán hàng', 'bound_by': 'u-lan', 'bound_at': twNow.millisecondsSinceEpoch - 86400000 * 3};
    const prompt = 'Lập kế hoạch giai đoạn 3: đào tạo đại lý hai miền, xong trước 15/1';
    final sid = FakeAiSessions.chId('sesnew1');
    Map<String, dynamic> step(String id, String title, {String kind = 'tool', String status = 'done'}) => {'id': id, 'kind': kind, 'title': title, 'status': status};
    final now = twNow.millisecondsSinceEpoch;
    Map<String, dynamic> act(String id, String run, String op, String summary, [Map<String, dynamic>? target]) =>
        {'id': id, 'run_id': run, 'op': op, 'undoable': true, 'summary': summary, 'target': ?target, 'at': now + id.hashCode % 1000};
    final plan = [
      act('v1', 'r-vplan', 'task_create', 'Tạo việc RA-70 Đào tạo đại lý miền Bắc + 4 việc con', {'type': 'task', 'id': 't-70', 'key': 'RA-70', 'title': 'Đào tạo đại lý miền Bắc'}),
      act('v2', 'r-vplan', 'task_create', 'Tạo việc RA-71 Đào tạo đại lý miền Nam + 5 việc con', {'type': 'task', 'id': 't-71', 'key': 'RA-71', 'title': 'Đào tạo đại lý miền Nam'}),
      act('v3', 'r-vplan', 'task_create', 'Tạo việc RA-72 Quay video hướng dẫn đặt hàng + 3 việc con', {'type': 'task', 'id': 't-72', 'key': 'RA-72', 'title': 'Quay video hướng dẫn đặt hàng'}),
      act('v4', 'r-vplan', 'task_assign', 'Giao RA-70 cho Thu, RA-71 cho Hùng, RA-72 cho Minh'),
      act('v5', 'r-vplan', 'task_update', 'Đặt hạn RA-72 20/12, RA-70 05/01, RA-71 09/01'),
    ];
    be.actions['r-vplan'] = plan.sublist(0, 2);
    be.progress['r-vplan'] = {'id': 'r-vplan', 'kind': 'project', 'project_id': 'p-ra', 'prompt': prompt, 'action': 'plan', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'state': 'running', 'seq': 4, 'step_count': 4, 'created_at': now};
    final user = (user: true, text: prompt, card: null, runId: null);
    final runningCard = {'status': 'running', 'engine': 'claude', 'title': 'Lập kế hoạch & chia việc', 'config': {'model': 'opus', 'effort': 'high'}, 'steps': [
      step('m', 'Chạy không cần duyệt (chủ bot)', kind: 'approval'), step('a', 'Đọc 54 việc của dự án'), step('b', 'Xem tải việc của 6 thành viên'),
      step('c', 'task_create RA-71 Đào tạo đại lý miền Nam', status: 'running'),
    ]};
    ai.feed[sid] = [user, (user: false, text: '', card: runningCard, runId: 'r-vplan')];

    final s = await pump(t, project: 'RA', view: 'kanban');
    await shot(t, 'v-ai-kanban', ['project-ai']);
    await t.tap(find.byKey(const ValueKey('project-ai')));
    await settle(t, 6);
    expect(find.byKey(const ValueKey('ai-panel')), findsOneWidget);
    await shot(t, 'v-ai-new', ['ai-panel', 'ai-input', 'ai-send', 'ai-agent', 'ai-chips', 'ai-act-plan', 'ai-act-chat_group']);
    await t.enterText(find.byKey(const ValueKey('ai-input')), prompt);
    await settle(t, 2);
    await shot(t, 'v-ai-typed', ['ai-input', 'ai-send']);
    await t.tap(find.byKey(const ValueKey('ai-send')));
    await settle(t, 8);
    expect(find.byKey(ValueKey('ai-session-view-$sid')), findsOneWidget);
    await shot(t, 'v-ai-running', ['ai-panel']);

    // Xong: 3 việc mới ở cột Cần làm, "Đã làm" đủ 5 thao tác.
    for (final (n, title, who, due, sub, rank) in const [
      (70, 'Đào tạo đại lý miền Bắc', 'u-thu', '2027-01-05', 4, 'a1'),
      (71, 'Đào tạo đại lý miền Nam', 'u-hung', '2027-01-09', 5, 'a2'),
      (72, 'Quay video hướng dẫn đặt hàng', 'u-minh', '2026-12-20', 3, 'a3'),
    ]) {
      be.tasks.add({...be.task('RA-47'), 'id': 't-$n', 'number': n, 'key': 'RA-$n', 'title': title, 'status_id': 's-todo', 'category': 'backlog', 'priority': 2,
        'start': '2026-12-01', 'due': due, 'rank': rank, 'labels': ['l-kh'], 'assignees': [{'kind': 'user', 'id': who, 'name': {'u-thu': 'Thu', 'u-hung': 'Hùng', 'u-minh': 'Minh'}[who]}],
        'sub_total': sub, 'sub_done': 0, 'progress': 0, 'comment_count': 0, 'attachment_count': 0, 'agent_run': null});
    }
    be.actions['r-vplan'] = plan;
    be.progress['r-vplan']!['state'] = 'review';
    final doneCard = {...runningCard, 'status': 'done', 'steps': [
      step('m', 'Chạy không cần duyệt (chủ bot)', kind: 'approval'), step('a', 'Đọc 54 việc của dự án'), step('b', 'Xem tải việc của 6 thành viên'),
      step('c', 'Tạo 3 việc + 12 việc con'), step('d', 'Giao việc, đặt hạn'),
    ]};
    const answer = 'Đã tạo 3 việc (12 việc con) cho giai đoạn 3, giao theo tải việc hiện tại:\n'
        '• RA-72 Quay video hướng dẫn đặt hàng · Minh · 20/12\n• RA-70 Đào tạo đại lý miền Bắc · Thu · 05/01\n• RA-71 Đào tạo đại lý miền Nam · Hùng · 09/01';
    ai.feed[sid] = [user, (user: false, text: answer, card: doneCard, runId: 'r-vplan')];
    await s.openProject('p-ra');
    s.debugEvent({'type': 'run_action', 'id': 'r-vplan', 'project_id': 'p-ra'});
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    ai.notifyListeners();
    await settle(t, 8);
    expect(find.byKey(const ValueKey('card-RA-70')), findsOneWidget);
    await shot(t, 'v-ai-done', ['ai-panel', 'card-RA-70', 'card-RA-71', 'card-RA-72', 'column-s-todo', 'run-undo-all-r-vplan', 'action-undo-v1', 'action-undo-v2', 'action-undo-v3', 'action-undo-v4', 'action-undo-v5']);

    // S7: tạo nhóm chat cho dự án.
    be.actions['r-vchat'] = [
      act('c1', 'r-vchat', 'chat_create', 'Tạo nhóm chat "Ra mắt app bán hàng", mời 6 thành viên'),
      act('c2', 'r-vchat', 'chat_post', 'Đăng cập nhật tiến độ vào nhóm'),
    ];
    be.progress['r-vchat'] = {'id': 'r-vchat', 'kind': 'project', 'project_id': 'p-ra', 'prompt': 'Tạo nhóm chat', 'action': 'chat_group', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'state': 'review', 'seq': 3, 'step_count': 3, 'created_at': now + 60000};
    ai.feed[sid] = [
      ...ai.feed[sid]!,
      (user: true, text: 'Tạo nhóm chat cho dự án', card: null, runId: null),
      (
        user: false,
        text: 'Đã tạo nhóm chat "Ra mắt app bán hàng", mời Lan, Minh, Hùng, Thu, Hà, An và đăng bản cập nhật tiến độ đầu tiên.',
        card: {'status': 'done', 'engine': 'claude', 'title': 'Tạo nhóm chat', 'config': {'model': 'opus', 'effort': 'high'}, 'steps': [
          step('a', 'Tạo nhóm "Ra mắt app bán hàng"'), step('b', 'Mời 6 thành viên dự án'), step('c', 'Đăng cập nhật tiến độ'),
        ]},
        runId: 'r-vchat',
      ),
    ];
    be.projects.first['chat_channel'] = {'id': 'ch-proj', 'team_id': 'team-1', 'name': 'ra-mat-app', 'display_name': 'Ra mắt app bán hàng', 'url': 'https://chat.example.com/lua-xanh/channels/ra-mat-app'};
    await s.refresh();
    await s.openProject('p-ra');
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    ai.notifyListeners();
    await settle(t, 8);
    await shot(t, 'v-ai-chat', ['ai-panel', 'open-chat', 'action-undo-c1', 'action-undo-c2']);
    await done(t, s);
  });

  testWidgets('S8 thông báo: máy tính + điện thoại, mở thẳng việc', (t) async {
    final d = await pump(t, section: 'inbox');
    await shot(t, 'v-inbox-desk');
    await done(t, d);
    final p = await pump(t, size: _phone, section: 'mine');
    await t.tap(find.byKey(const ValueKey('ptab-inbox')));
    await settle(t, 4);
    await shot(t, 'v-inbox-phone');
    await openTaskPage(t, p, 'RA-32');
    await shot(t, 'v-task-phone');
    await done(t, p);
  });
}
