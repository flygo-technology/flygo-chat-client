// TeamWork / Làm việc nhóm: dữ liệu (đọc JSON, @nhắc, Markdown, thứ tự, lọc / nhóm, Gantt, bản giao việc), kho (hàng đợi
// khi mất mạng, nhận lượt chạy agent) và giao diện với backend giả (dự án, Kanban kéo thả, Danh sách, Gantt kéo dời,
// chi tiết việc, bình luận, cảm xúc, @nhắc agent, cài đặt trạng thái, Việc của tôi, tạo việc giao agent, thông báo).
// Ảnh chụp (chạy tay): TW_OUT=<thư mục> flutter test test/teamwork_test.dart (máy tính 1440x900, điện thoại 390x844, sáng + tối).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/teamwork/gantt_view.dart';
import 'package:flygo_chat/ui/teamwork/model.dart';
import 'package:flygo_chat/ui/teamwork/projects_view.dart';
import 'package:flygo_chat/ui/teamwork/store.dart';
import 'package:flygo_chat/ui/teamwork/task_page.dart';
import 'package:flygo_chat/ui/teamwork/task_widgets.dart';
import 'package:flygo_chat/ui/teamwork/teamwork_page.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:flygo_chat/ui/todo/model.dart';

import 'fixtures/teamwork_fake.dart';

const _desk = Size(1440, 900), _phone = Size(390, 844);

/// Đếm số lần mở trang mới.
class _Pushes extends NavigatorObserver {
  int n = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => n++;
}

void main() {
  final out = Platform.environment['TW_OUT'];
  final today = DateTime.utc(2026, 11, 19);

  group('dữ liệu', () {
    test('đọc dự án / việc / trạng thái từ JSON máy chủ', () {
      final be = FakeTw();
      final p = TwProject.fromJson(be.projects.first);
      expect(p.key, 'RA');
      expect(p.counts.keys.toSet(), {'backlog', 'started', 'closed', 'done'}); // bỏ total / overdue
      expect(p.total, 54);
      expect(p.canAdmin, isTrue);
      final t = TwTask.fromJson(be.task('RA-32'));
      expect(t.assignees.map((a) => a.kind), ['user', 'agent']);
      expect(t.hasAgent, isTrue);
      expect(t.percent, 50);
      expect(t.run!.state, 'running');
      expect(t.blockedBy, ['t-29']);
      expect(t.statusInfo!.category, 'started');
      final f = TwProjectFull.fromJson({'project': be.projects.first, 'statuses': be.statuses, 'labels': be.labels, 'members': be.members});
      expect(f.startStatus!.name, 'Đang làm');
      expect(f.reviewStatus!.name, 'Chờ duyệt');
      expect(f.defaultStatus!.id, 's-todo');
      expect(f.firstDone!.id, 's-done');
    });

    test('@nhắc: thuộc tính m {k, id} ↔ link nội bộ, đọc lại giữ nguyên', () {
      final blocks = blocksFromJson([
        {'id': 'b', 't': 'p', 'r': [{'x': 'Báo '}, {'x': '@Hùng', 'm': {'k': 'user', 'id': 'u-hung'}}, {'x': ' xem RA-38', 'b': true}]},
      ]);
      expect(mentionOf(blocks.first.r[1].f.a), ('user', 'u-hung'));
      final back = blocksToJson(blocks);
      expect(back.first['r'][1], {'x': '@Hùng', 'm': {'k': 'user', 'id': 'u-hung'}});
      expect(back.first['r'][2]['b'], true);
      expect(mentionOf('https://example.com'), isNull);
    });

    test('Markdown ↔ khối', () {
      final b = markdownToBlocks('# Tiêu đề\n- việc **gấp**\n- [x] đã xong\n1. bước một\n> trích\n---\nđoạn `mã`');
      expect(b.map((x) => x.t), ['h1', 'ul', 'check', 'ol', 'quote', 'hr', 'p']);
      expect(b[1].r[1].f.b, isTrue);
      expect(b[2].done, isTrue);
      expect(b[6].r[1].f.c, isTrue);
      final md = blocksToMarkdown(b);
      expect(md, contains('- [x] đã xong'));
      expect(md, contains('**gấp**'));
      expect(blocksText(b), contains('bước một'));
    });

    test('thứ tự Kanban: rank nằm giữa hai thẻ', () {
      for (final (a, b) in [('', ''), ('b', 'c'), ('m', ''), ('', 'm'), ('a', 'b'), ('az', 'b')]) {
        final r = rankBetween(a, b);
        expect(r.compareTo(a) > 0, isTrue, reason: '$a < $r');
        if (b.isNotEmpty) expect(r.compareTo(b) < 0, isTrue, reason: '$r < $b');
      }
    });

    test('lọc, sắp xếp, nhóm việc', () {
      final be = FakeTw();
      final tasks = [for (final t in be.tasks) TwTask.fromJson(t)];
      final f = TwFilter()..assignees = {'agent:b-codex'};
      expect(f.apply(tasks, today).map((t) => t.key), containsAll(['RA-32', 'RA-62', 'RA-63']));
      f
        ..assignees = {}
        ..due = 'overdue';
      expect(f.apply(tasks, today).map((t) => t.key), isEmpty); // 19/11: chưa có việc mở nào quá hạn
      f
        ..due = null
        ..priorities = {1}
        ..sort = 'due';
      expect(f.apply(tasks, today).single.key, 'RA-32');
      final full = TwProjectFull.fromJson({'project': be.projects.first, 'statuses': be.statuses});
      final g = groupTasks(tasks, TwFilter()..group = 'status', full, today);
      expect(g.map((x) => x.title).take(3), ['Cần làm', 'Đang làm', 'Chờ duyệt']);
      final byDue = groupTasks(tasks, TwFilter()..group = 'due', full, today);
      expect(byDue.map((x) => x.title), contains('Không hạn'));
    });

    test('Gantt: dòng cha / con, khoảng ngày việc cha lấy theo việc con', () {
      final be = FakeTw();
      final tasks = [for (final t in be.tasks) TwTask.fromJson(t)];
      final rows = ganttRows(tasks, {});
      final i = rows.indexWhere((r) => r.task.key == 'RA-32');
      expect(rows[i].hasKids, isTrue);
      expect(rows[i + 1].depth, 1);
      expect(rows.any((r) => r.task.key == 'RA-26'), isFalse); // không ngày, không con: nằm ở "Chưa xếp lịch"
      expect(ganttRows(tasks, {'t-32'}).any((r) => r.task.key == 'RA-63'), isFalse); // gập
      final parent = TwTask(id: 'x', projectId: 'p', key: 'X-1', title: 'cha', statusId: 's');
      final kids = [
        parent,
        TwTask(id: 'k1', projectId: 'p', key: 'X-2', title: 'a', statusId: 's', parentId: 'x', start: DateTime.utc(2026, 11, 3), due: DateTime.utc(2026, 11, 5)),
        TwTask(id: 'k2', projectId: 'p', key: 'X-3', title: 'b', statusId: 's', parentId: 'x', start: DateTime.utc(2026, 11, 4), due: DateTime.utc(2026, 11, 9)),
      ];
      expect(spanOf(parent, kids), (DateTime.utc(2026, 11, 3), DateTime.utc(2026, 11, 9)));
    });

    test('mã dự án gợi ý, liên kết hai chiều, bản giao việc', () {
      expect(suggestKey('Ra mắt app bán hàng'), 'RMAB');
      expect(suggestKey('Quyết toán'), 'QT');
      expect(suggestKey('Website'), 'WEB');
      final out = TwLink.fromJson({'id': 'k', 'type': 'blocks', 'direction': 'out', 'task': {'id': 't2', 'key': 'RA-2'}}, 't1');
      expect((out.fromTask, out.toTask, out.otherKey), ('t1', 't2', 'RA-2'));
      final inn = TwLink.fromJson({'id': 'k', 'type': 'blocks', 'direction': 'in', 'task': {'id': 't0', 'key': 'RA-0'}}, 't1');
      expect((inn.fromTask, inn.toTask), ('t0', 't1'));
      final be = FakeTw();
      final d = TwTaskDetail(TwTask.fromJson(be.task('RA-32'))..description = markdownToBlocks('Làm **API**'),
          subtasks: [for (final t in be.tasks.where((t) => t['parent_id'] == 't-32')) TwTask.fromJson(t)]);
      final brief = briefOf(d, 'https://chat.example.com/__apps/teamwork/t/RA-32');
      expect(brief, contains('[teamwork task=RA-32]'));
      expect(brief, contains('Làm **API**'));
      expect(brief, contains('RA-64 Giới hạn số lượng'));
      expect(brief, isNot(contains('RA-60'))); // việc con đã xong
      expect(brief, contains('agent_report'));
    });
  });

  group('bảng + Markdown', () {
    test('GFM: bảng (căn lề, ô có mã / đậm, \\|), khối mã ```, danh sách lồng nhau', () {
      final b = markdownToBlocks('## Quản lý nhóm\n| Tool | Input | Quyền |\n|:---|---|:---:|\n| `group_list` | a \\| b | **đọc** |\n| x | | y |\n\n```\nfinal a = 1;\n  print(a);\n```\n- một\n  - hai\n    - ba');
      expect(b.map((x) => x.t), ['h2', 'table', 'code', 'ul', 'ul', 'ul']);
      final t = b[1] as TwTableBlock;
      expect(t.rows, hasLength(3));
      expect(t.cols, 3);
      expect(t.align, ['l', 'l', 'c']);
      expect(t.rows[1][0].single.f.c, isTrue);
      expect(t.rows[1][1].single.x, 'a | b');
      expect(t.rows[1][2].single.f.b, isTrue);
      expect(t.rows[2][1], isEmpty);
      expect(b[2].text, 'final a = 1;\n  print(a);');
      expect(b.skip(3).map((x) => x.ind), [0, 1, 2]);
      expect(blocksToMarkdown([t]), startsWith('| Tool | Input | Quyền |\n|---|---|:---:|'));
    });

    test('JSON: bảng đi khứ hồi, @nhắc trong ô giữ thuộc tính m', () {
      final json = [
        {'id': 't', 't': 'table', 'align': ['l', 'r'], 'rows': [
          [[{'x': 'Ai'}], [{'x': 'Số'}]],
          [[{'x': '@Hùng', 'm': {'k': 'user', 'id': 'u-hung'}}], [{'x': '12', 'b': true}]],
        ]},
      ];
      final b = blocksFromJson(json);
      final t = b.single as TwTableBlock;
      expect(mentionOf(t.rows[1][0].single.f.a), ('user', 'u-hung'));
      expect(t.clone().rows[1][1].single.f.b, isTrue);
      final back = blocksToJson(b).single;
      expect(back['t'], 'table');
      expect(back['rows'][1][0], [{'x': '@Hùng', 'm': {'k': 'user', 'id': 'u-hung'}}]);
      expect(back['align'], ['l', 'r']);
      expect(blocksText(b), contains('@Hùng | 12'));
    });

    test('dán bảng Markdown (các dòng thành đoạn văn) → khối bảng; dòng | … | sau bảng thành hàng mới', () {
      final paras = [for (final l in ['Trước', '| A | B |', '| --- | --- |', '| 1 | 2 |', 'Sau']) TBlock.text(l)];
      final f = foldTables(paras)!;
      expect(f.map((x) => x.t), ['p', 'table', 'p']);
      expect((f[1] as TwTableBlock).rows, hasLength(2));
      final more = foldTables([...f.take(2), TBlock.text('| 3 | 4 |')])!;
      expect((more[1] as TwTableBlock).rows, hasLength(3));
      expect(foldTables([TBlock.text('a | b'), TBlock.text('không phải bảng')]), isNull);
    });
  });

  group('kho', () {
    test('lượt chạy @nhắc: gửi vào phiên sẵn có (session_hint) nếu còn dùng được, không thì mở phiên mới', () async {
      final be = FakeTw();
      final l = FakeLauncher()..usable = {'ch-1'};
      final s = newTwStore(be, launcher: l);
      await s.refresh();
      be.runs.addAll([
        {'id': 'r-m1', 'kind': 'mention', 'task_id': 't-32', 'comment_id': 'c1', 'bot_id': 'b-codex', 'bot_name': 'Codex', 'started_by': 'u-lan', 'state': 'queued', 'session_hint': 'ch-1'},
        {'id': 'r-m2', 'kind': 'mention', 'task_id': 't-32', 'comment_id': 'c1', 'bot_id': 'b-claude', 'bot_name': 'Claude', 'started_by': 'u-lan', 'state': 'queued', 'session_hint': 'ch-gone'},
      ]);
      await s.checkRuns();
      expect(l.posted, [('ch-1', 'BRIEF RA-32')]);
      expect(l.launched.single.$1, 'b-claude');
      expect(l.launched.single.$2, 'RA-32 · API đặt hàng + đồng bộ tồn kho');
      expect(be.runs[0]['state'], 'running');
      expect(be.runs[0]['session_channel'], 'ch-1');
      expect(be.runs[1]['session_channel'], 'ch-new-b-claude');
      // run_token của máy chủ đi kèm tin giao việc; chỉ xác nhận chủ bot khi đúng là chủ.
      expect(l.props[0]['flygo_teamwork'], {'run_token': 'TOKEN-r-m1', 'run_id': 'r-m1'});
      expect(be.runs[0]['attest_owner'], isFalse);
      expect(be.runs[1]['attest_owner'], isTrue);
      s.dispose();
    });

    test('mất mạng: sửa áp ngay trên máy, xếp hàng, có mạng thì gửi lại', () async {
      final be = FakeTw();
      final s = newTwStore(be);
      await s.refresh();
      await s.openProject('p-ra');
      final t = s.tasksOf('p-ra').firstWhere((x) => x.key == 'RA-44');
      be.down = true;
      await s.updateTask(t, {'priority': 1});
      expect(s.offline, isTrue);
      expect(s.queue, hasLength(1));
      expect(s.tasksOf('p-ra').firstWhere((x) => x.key == 'RA-44').priority, 1);
      be.down = false;
      await s.refresh();
      expect(s.queue, isEmpty);
      expect(be.calls, contains('PATCH /tw/api/tasks/t-44'));
      expect(be.task('RA-44')['priority'], 1);
      s.dispose();
    });

    test('kéo vào trạng thái bắt đầu: nhận lượt chạy, mở phiên, gửi bản giao việc của máy chủ, báo running', () async {
      final be = FakeTw();
      final l = FakeLauncher();
      final s = newTwStore(be, launcher: l);
      await s.refresh();
      await s.openProject('p-ra');
      final t = s.tasksOf('p-ra').firstWhere((x) => x.key == 'RA-30');
      await s.moveTask(t, statusId: 's-doing');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(l.launched, hasLength(1));
      expect(l.launched.single.$1, 'b-claude');
      expect(l.launched.single.$2, 'RA-30 · Tóm tắt phản hồi khảo sát 120 đại lý');
      expect(l.launched.single.$3, 'BRIEF RA-30');
      final run = be.runs.single;
      expect(run['state'], 'running');
      expect(run['session_channel'], 'ch-new-b-claude');
      expect(be.bodies.keys.any((k) => k.startsWith('POST /tw/api/runs/') && k.endsWith('/claim')), isTrue);
      // Không được dùng agent: báo blocked, không mở phiên.
      l.allowed = {};
      await s.startAgents(s.tasksOf('p-ra').firstWhere((x) => x.key == 'RA-63'));
      expect(l.launched, hasLength(1));
      expect(be.runs.last['state'], 'blocked');
      s.dispose();
    });
  });

  // ------------------------------------------------------------ giao diện
  late FakeTw be;
  late FakeLauncher launcher;
  late _Pushes pushes;
  setUp(() {
    pushes = _Pushes();
    be = FakeTw();
    launcher = FakeLauncher();
  });

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  Future<TwStore> pump(WidgetTester t, {Size size = _desk, bool dark = false, Widget Function(TwStore s)? child, String? section, String? project, String? view}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(twFonts);
    final s = newTwStore(be, launcher: launcher);
    await t.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(dark ? Brightness.dark : Brightness.light),
        navigatorObservers: [pushes],
        home: child?.call(s) ?? TeamworkHome(store: s, ownsStore: false, initialSection: section, initialProject: project, initialView: view),
      ),
    ));
    await settle(t, 10);
    return s;
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (out == null) return;
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(() async {
      final img = await (t.renderObject(find.byKey(const ValueKey('shot'))) as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<void> done(WidgetTester t, TwStore s) async {
    await t.pumpWidget(const SizedBox());
    await settle(t, 2);
    s.dispose();
  }

  Future<void> openTaskPage(WidgetTester t, TwStore s, String key, {bool? ai}) async {
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(nav.push(MaterialPageRoute(builder: (_) => TwTaskPage(store: s, idOrKey: key, showAi: ai))));
    await settle(t, 10);
  }

  group('máy tính', () {
    for (final dark in [false, true]) {
      final sfx = dark ? 'dark' : 'light';

      testWidgets('tất cả dự án: thẻ, tiến độ, lọc trạng thái ($sfx)', (t) async {
        final s = await pump(t, dark: dark);
        expect(find.text('Ra mắt app bán hàng'), findsWidgets);
        expect(find.text('23/54 xong'), findsOneWidget);
        expect(find.text('Đang chạy · 4'), findsOneWidget);
        expect(find.text('Làm việc nhóm'), findsOneWidget);
        await shot(t, 'd1-projects-$sfx');
        await t.tap(find.byKey(const ValueKey('pstatus-planning')));
        await settle(t, 2);
        expect(find.byKey(const ValueKey('project-TD')), findsOneWidget);
        expect(find.byKey(const ValueKey('project-RA')), findsNothing);
        await done(t, s);
      });

      testWidgets('Kanban: cột theo trạng thái, WIP, agent đang làm ($sfx)', (t) async {
        final s = await pump(t, dark: dark, project: 'RA', view: 'kanban');
        expect(find.byKey(const ValueKey('column-s-doing')), findsOneWidget);
        expect(find.text('WIP 4/5'), findsOneWidget);
        expect(find.text('WIP 3/3'), findsOneWidget);
        expect(find.byKey(const ValueKey('card-RA-32')), findsOneWidget);
        expect(find.textContaining('Codex đang làm'), findsOneWidget);
        expect(find.byKey(const ValueKey('card-RA-63')), findsNothing); // việc con không lên Kanban
        await shot(t, 'd2-kanban-$sfx');
        await done(t, s);
      });

      testWidgets('Danh sách: nhóm theo trạng thái, đổi trạng thái hàng loạt ($sfx)', (t) async {
        final s = await pump(t, dark: dark, project: 'RA', view: 'list');
        expect(find.byKey(const ValueKey('group-s-doing')), findsOneWidget);
        expect(find.byKey(const ValueKey('row-RA-35')), findsOneWidget);
        await shot(t, 'd3-list-$sfx');
        if (!dark) {
          await t.tap(find.descendant(of: find.byKey(const ValueKey('row-RA-44')), matching: find.byType(Checkbox)));
          await t.tap(find.descendant(of: find.byKey(const ValueKey('row-RA-41')), matching: find.byType(Checkbox)));
          await t.pump();
          expect(find.text('Đã chọn 2 việc'), findsOneWidget);
          await t.tap(find.byKey(const ValueKey('bulk-status')));
          await settle(t, 3);
          await t.tap(find.byKey(const ValueKey('pick-status-s-wait')));
          await settle(t);
          final b = be.bodies['POST /tw/api/tasks/bulk']!;
          expect((b['ids'] as List).toSet(), {'t-44', 't-41'});
          expect(b['patch'], {'status_id': 's-wait'});
        }
        await done(t, s);
      });

      testWidgets('Gantt: thanh, phụ thuộc, việc chưa xếp lịch ($sfx)', (t) async {
        final s = await pump(t, dark: dark, project: 'RA', view: 'gantt');
        expect(find.byKey(const ValueKey('gbar-RA-32')), findsOneWidget);
        expect(find.byKey(const ValueKey('grow-RA-63')), findsOneWidget);
        expect(find.textContaining('Chưa xếp lịch'), findsOneWidget);
        expect(find.byKey(const ValueKey('unsched-RA-26')), findsOneWidget);
        await shot(t, 'd4-gantt-$sfx');
        await done(t, s);
      });

      testWidgets('chi tiết việc: mô tả, việc con, tệp, bình luận của agent, không còn AI hỗ trợ ($sfx)', (t) async {
        final s = await pump(t, dark: dark, project: 'RA');
        await openTaskPage(t, s, 'RA-32');
        expect(find.text('Việc con'), findsOneWidget);
        expect(find.text('3/6'), findsWidgets);
        expect(find.text('Viết test tồn kho'), findsOneWidget);
        expect(find.text('Danh mục hàng.xlsx'), findsOneWidget);
        expect(find.text('Agent · thay Minh'), findsOneWidget);
        expect(find.byKey(const ValueKey('props-left')), findsOneWidget);
        expect(find.byKey(const ValueKey('tab-ai')), findsNothing);
        expect(find.text('AI hỗ trợ'), findsNothing);
        expect(find.byKey(const ValueKey('ai-breakdown')), findsNothing);
        expect(find.byKey(const ValueKey('tab-comments')), findsOneWidget);
        expect(find.byKey(const ValueKey('tab-activity')), findsOneWidget);
        expect(find.byKey(const ValueKey('agent-card')), findsOneWidget);
        expect(find.textContaining('Chặn'), findsOneWidget);
        expect(find.text('Codex đã xong · 7 bước'), findsOneWidget); // bình luận @nhắc agent
        await shot(t, 'd5-task-$sfx');
        await done(t, s);
      });

      testWidgets('cài đặt: trạng thái + đúng một trạng thái bắt đầu, thành viên ($sfx)', (t) async {
        final s = await pump(t, dark: dark, project: 'RA');
        // Tab "Cài đặt" ngay sau "Tổng quan", mở ngay trong màn hình dự án.
        expect(t.getRect(find.byKey(const ValueKey('view-settings'))).left, greaterThanOrEqualTo(t.getRect(find.byKey(const ValueKey('view-overview'))).right));
        expect(find.byKey(const ValueKey('project-settings')), findsNothing); // bỏ nút tune trên thanh đầu
        final before = pushes.n;
        await t.tap(find.byKey(const ValueKey('view-settings')));
        await settle(t, 6);
        expect(pushes.n, before);
        expect(find.byKey(const ValueKey('settings-nav')), findsOneWidget);
        expect(find.text('Agent AI'), findsOneWidget);
        expect(find.text('Trạng thái việc'), findsOneWidget);
        expect(find.textContaining('Agent nộp kết quả vào đây'), findsOneWidget);
        await shot(t, 'd6-settings-$sfx');
        if (!dark) {
          await t.tap(find.byKey(const ValueKey('start-s-review')));
          await settle(t);
          expect(be.bodies['PATCH /tw/api/statuses/s-review'], {'is_start': true});
          expect(s.fullOf('p-ra')!.statuses.where((x) => x.isStart).map((x) => x.id), ['s-review']);
          await t.tap(find.byKey(const ValueKey('set-members')));
          await settle(t, 3);
          expect(find.text('Phòng Kỹ thuật'), findsOneWidget);
          expect(find.text('Vai trò: Ban giám đốc'), findsOneWidget);
          await shot(t, 'd6b-members-$sfx');
        }
        await done(t, s);
      });

      testWidgets('Việc của tôi + tạo việc giao agent ($sfx)', (t) async {
        final s = await pump(t, dark: dark, section: 'mine');
        expect(find.byKey(const ValueKey('mine-row-RA-35')), findsOneWidget);
        expect(find.text('Không hạn · 1'), findsOneWidget);
        expect(find.text('Tuần này · 1'), findsOneWidget);
        await shot(t, 'd7-mine-$sfx');
        await done(t, s);
      });
    }

    testWidgets('mô tả mặc định chỉ xem; Sửa → thanh công cụ + Lưu (base_version) / Huỷ; trống → "Thêm mô tả…"', (t) async {
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-32', ai: false);
      expect(find.byKey(const ValueKey('desc-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('desc-editor')), findsNothing);
      expect(find.text('Yêu cầu'), findsOneWidget);
      // Chỉ ô soạn bình luận có thanh công cụ.
      expect(find.byKey(const ValueKey('rt-mention')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('desc-edit')));
      await settle(t, 3);
      expect(find.byKey(const ValueKey('desc-editor')), findsOneWidget);
      expect(find.byKey(const ValueKey('rt-mention')), findsNWidgets(2));
      await shot(t, 'd5b-desc-edit');
      await t.tap(find.byKey(const ValueKey('desc-cancel')));
      await settle(t, 2);
      expect(find.byKey(const ValueKey('desc-view')), findsOneWidget);
      // Bấm đúp vào chữ cũng vào chế độ sửa; sửa rồi Lưu.
      await t.tap(find.text('Yêu cầu'));
      await t.pump(const Duration(milliseconds: 60));
      await t.tap(find.text('Yêu cầu'));
      await settle(t, 3);
      expect(find.byKey(const ValueKey('desc-editor')), findsOneWidget);
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('desc-editor')), matching: find.byType(TextField)).first, 'Mục tiêu mới');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('desc-save')));
      await settle(t);
      final b = be.bodies['PATCH /tw/api/tasks/t-32']!;
      expect(b['base_version'], 3);
      expect(((b['description'] as List).first as Map)['r'].first['x'], 'Mục tiêu mới');
      expect(find.byKey(const ValueKey('desc-view')), findsOneWidget);
      expect(s.descDrafts, isEmpty);
      // Việc chưa có mô tả.
      await t.pageBack();
      await settle(t, 2);
      await openTaskPage(t, s, 'RA-44', ai: false);
      expect(find.text('Thêm mô tả…'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('desc-placeholder')));
      await settle(t, 3);
      expect(find.byKey(const ValueKey('desc-editor')), findsOneWidget);
      await done(t, s);
    });

    testWidgets('bảng trong mô tả: tiêu đề + 15 hàng, mã trong ô; sửa giữ nguyên bảng, Sửa bảng thêm hàng', (t) async {
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-38', ai: false);
      expect(find.byKey(const ValueKey('tw-table')), findsOneWidget);
      final table = t.widget<Table>(find.descendant(of: find.byKey(const ValueKey('tw-table')), matching: find.byType(Table)));
      expect(table.children, hasLength(16));
      expect(find.text('Quyền cần'), findsOneWidget);
      expect(find.text('group_list'), findsOneWidget);
      await shot(t, 'd5g-table');
      await t.tap(find.byKey(const ValueKey('desc-edit')));
      await settle(t, 3);
      expect(find.byKey(const ValueKey('table-edit')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('table-edit')));
      await settle(t, 3);
      expect(find.byKey(const ValueKey('tcell-0-0')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('tcell-1-2')), 'đọc + ghi');
      await t.tap(find.byKey(const ValueKey('trow-add')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('table-save')));
      await settle(t, 3);
      await t.tap(find.byKey(const ValueKey('desc-save')));
      await settle(t);
      final desc = be.bodies['PATCH /tw/api/tasks/t-38']!['description'] as List;
      final tb = desc.firstWhere((b) => b['t'] == 'table') as Map;
      expect((tb['rows'] as List), hasLength(17));
      expect(tb['rows'][1][0], [{'x': 'group_list', 'c': true}]); // ô không sửa giữ định dạng mã
      expect(tb['rows'][1][2], [{'x': 'đọc + ghi'}]);
      expect(tb['align'], ['l', 'l', 'c']);
      expect(desc.where((b) => b['t'] == 'h3'), hasLength(1));
      await done(t, s);
    });

    testWidgets('dán bảng Markdown vào mô tả → khối bảng, lưu dạng table', (t) async {
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-44', ai: false);
      await t.tap(find.byKey(const ValueKey('desc-placeholder')));
      await settle(t, 3);
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('desc-editor')), matching: find.byType(TextField)).first, '| Tool | Quyền |\n|---|---|\n| `chat_list` | đọc |\n| `chat_send` | ghi |');
      await settle(t, 4);
      expect(find.byKey(const ValueKey('table-edit')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('desc-save')));
      await settle(t);
      final desc = be.bodies['PATCH /tw/api/tasks/t-44']!['description'] as List;
      final tb = desc.firstWhere((b) => b['t'] == 'table') as Map;
      expect(tb['rows'], hasLength(3));
      expect(tb['rows'][1][0], [{'x': 'chat_list', 'c': true}]);
      await done(t, s);
    });

    testWidgets('máy tính: bấm việc con mở khung bên phải (không mở trang), bấm việc khác thay nội dung', (t) async {
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-32');
      final before = pushes.n;
      await t.tap(find.byKey(const ValueKey('sub-RA-63')));
      await settle(t, 8);
      expect(pushes.n, before);
      expect(find.byKey(const ValueKey('task-panel')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('task-panel')), matching: find.text('RA-63')), findsOneWidget);
      expect(find.byKey(const ValueKey('panel-full')), findsOneWidget);
      expect(find.text('Tóm tắt bình luận'), findsNothing); // khung AI nhường chỗ
      await shot(t, 'd5c-subtask-panel');
      // Bấm liên kết RA-41 ở trang chính: khung đổi nội dung.
      await t.tap(find.text('RA-41').first);
      await settle(t, 8);
      expect(pushes.n, before);
      expect(find.descendant(of: find.byKey(const ValueKey('task-panel')), matching: find.text('Viết tài liệu hướng dẫn đại lý')), findsWidgets);
      await t.tap(find.byKey(const ValueKey('panel-close')));
      await settle(t, 2);
      expect(find.byKey(const ValueKey('task-panel')), findsNothing);
      expect(find.byKey(const ValueKey('tab-comments')), findsOneWidget); // về lại các tab của việc cha
      expect(find.text('Agent · thay Minh'), findsOneWidget);
      await done(t, s);
    });

    testWidgets('bố cục theo độ rộng: 3 cột (≥1180), 2 cột + chip (760–1180), một cột (điện thoại)', (t) async {
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-32');
      expect(find.byKey(const ValueKey('props-left')), findsOneWidget);
      expect(find.byKey(const ValueKey('right-col')), findsOneWidget);
      await done(t, s);

      final m = await pump(t, size: const Size(1024, 768), project: 'RA');
      await openTaskPage(t, m, 'RA-32');
      expect(find.byKey(const ValueKey('props-left')), findsNothing);
      expect(find.byKey(const ValueKey('right-col')), findsOneWidget);
      expect(find.byKey(const ValueKey('p-status')), findsOneWidget); // chip dưới tiêu đề
      expect(find.byKey(const ValueKey('tab-activity')), findsOneWidget);
      await shot(t, 'd5d-medium');
      await t.tap(find.byKey(const ValueKey('sub-RA-63')));
      await settle(t, 8);
      expect(find.byKey(const ValueKey('task-panel')), findsOneWidget);
      await done(t, m);

      final ph = await pump(t, size: _phone, project: 'RA');
      await openTaskPage(t, ph, 'RA-32');
      expect(find.byKey(const ValueKey('right-col')), findsNothing);
      await done(t, ph);
    });

    testWidgets('máy tính: bấm thẻ Kanban / dòng Danh sách mở trang việc đầy đủ', (t) async {
      final s = await pump(t, project: 'RA', view: 'kanban');
      final before = pushes.n;
      await t.tap(find.byKey(const ValueKey('card-RA-35')));
      await settle(t, 8);
      expect(pushes.n, before + 1);
      expect(find.byType(TwTaskPage), findsOneWidget);
      expect(find.byKey(const ValueKey('task-panel')), findsNothing);
      expect(find.byKey(const ValueKey('props-left')), findsOneWidget);
      await t.pageBack();
      await settle(t, 3);
      await t.tap(find.byKey(const ValueKey('view-list')));
      await settle(t, 3);
      await t.tap(find.byKey(const ValueKey('row-RA-44')));
      await settle(t, 8);
      expect(pushes.n, before + 2);
      await done(t, s);
    });

    testWidgets('thanh đầu dự án: nhóm nút sát mép phải (1280 / 1600 / 1920); "Mời" mở Cài đặt › Thành viên', (t) async {
      for (final w in [1280.0, 1600.0, 1920.0]) {
        final s = await pump(t, size: Size(w, 900), project: 'RA');
        expect(t.getRect(find.byKey(const ValueKey('new-task'))).right, greaterThan(w - 24), reason: 'rộng $w');
        if (w == 1600) {
          await t.tap(find.byKey(const ValueKey('invite')));
          await settle(t, 4);
          expect(find.text('Thành viên & quyền'), findsWidgets);
          expect(find.text('Vai trò: Ban giám đốc'), findsOneWidget);
        }
        await done(t, s);
      }
    });

    testWidgets('khung việc con: mặc định 40% cửa sổ, kéo mép trái để đổi và nhớ độ rộng', (t) async {
      final s = await pump(t, project: 'RA');
      double? saved;
      s.savePanelWidth = (w) async => saved = w;
      await openTaskPage(t, s, 'RA-32');
      expect(t.getSize(find.byKey(const ValueKey('right-col'))).width, 420);
      await t.tap(find.byKey(const ValueKey('sub-RA-63')));
      await settle(t, 8);
      expect(t.getSize(find.byKey(const ValueKey('right-col'))).width, closeTo(1440 * .4, 1));
      final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('panel-resize'))), kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 5; i++) {
        await g.moveBy(const Offset(-20, 0));
        await t.pump();
      }
      await g.up();
      await settle(t, 2);
      final w = t.getSize(find.byKey(const ValueKey('right-col'))).width;
      expect(w, greaterThan(1440 * .4 + 60));
      expect(saved, closeTo(w, 1));
      expect(s.panelWidth, closeTo(w, 1));
      // Mở việc con khác: giữ độ rộng đã chọn.
      await t.tap(find.byKey(const ValueKey('sub-RA-64')));
      await settle(t, 8);
      expect(t.getSize(find.byKey(const ValueKey('right-col'))).width, closeTo(w, 1));
      await done(t, s);
    });

    testWidgets('mã việc dài (ZLMCP-10…ZLMCP-999): không xuống dòng, không tràn', (t) async {
      final nums = [10, 105, 999, 12, 47, 88, 230, 31, 64, 5, 777, 400, 19, 20, 21, 22, 23, 24, 25];
      for (var i = 0; i < be.tasks.length; i++) {
        be.tasks[i]['key'] = 'ZLMCP-${nums[i % nums.length]}';
      }
      be.projects.first['key'] = 'ZLMCP';
      final s = await pump(t, project: 'ZLMCP', view: 'list');
      void oneLine(String k) {
        for (final e in find.text(k).evaluate()) {
          final h = (e.renderObject as RenderBox).size.height;
          expect(h, lessThan(22), reason: '$k cao $h: bị xuống dòng');
        }
      }

      for (final k in ['ZLMCP-999', 'ZLMCP-105', 'ZLMCP-10']) {
        expect(find.text(k), findsWidgets);
        oneLine(k);
      }
      await openTaskPage(t, s, 't-32');
      expect(find.text('ZLMCP-999'), findsNothing);
      for (final k in ['ZLMCP-400', 'ZLMCP-777', 'ZLMCP-12', 'ZLMCP-20']) {
        oneLine(k);
      }
      final rows = find.byWidgetPredicate((w) => w is InkWell && w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('sub-ZLMCP-'));
      expect(rows, findsNWidgets(6));
      for (final e in rows.evaluate()) {
        expect((e.renderObject as RenderBox).size.height, 30);
      }
      await t.tap(rows.at(3));
      await settle(t, 8);
      expect(find.byKey(const ValueKey('task-panel')), findsOneWidget);
      await shot(t, 'd5f-long-keys');
      await done(t, s);
    });

    testWidgets('kéo thẻ Kanban sang "Chờ duyệt" → move có status_id + before', (t) async {
      final s = await pump(t, project: 'RA', view: 'kanban');
      final card = find.byKey(const ValueKey('card-RA-38'));
      final target = find.byKey(const ValueKey('card-RA-33'));
      final g = await t.startGesture(t.getCenter(card), kind: PointerDeviceKind.mouse);
      await t.pump();
      final to = t.getCenter(target);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(t.getCenter(card), to, i / 10)!);
        await t.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await settle(t);
      // Cột Chờ duyệt đã đủ WIP 3/3: hỏi trước khi thả.
      expect(find.text('Cột "Chờ duyệt" đã đủ WIP'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('confirm-yes')));
      await settle(t);
      final k = be.bodies.keys.firstWhere((k) => k == 'POST /tw/api/tasks/t-38/move');
      expect(be.bodies[k]!['status_id'], 's-review');
      expect(be.bodies[k]!['before_id'], 't-33');
      expect(find.text('WIP 4/3'), findsOneWidget);
      await done(t, s);
    });

    testWidgets('kéo thanh Gantt: hỏi dời theo việc phụ thuộc, gửi schedule shift_dependents', (t) async {
      final s = await pump(t, project: 'RA', view: 'gantt');
      final bar = find.byKey(const ValueKey('gbar-RA-38'));
      await t.ensureVisible(bar);
      final g = await t.startGesture(t.getCenter(bar), kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(12, 0));
        await t.pump();
      }
      await g.up();
      await settle(t);
      expect(find.textContaining('1 việc phụ thuộc'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('RA-33 Chính sách đổi trả')), findsOneWidget);
      await shot(t, 'd4b-gantt-shift');
      await t.tap(find.byKey(const ValueKey('shift-yes')));
      await settle(t);
      final b = be.bodies['POST /tw/api/tasks/t-38/schedule']!;
      expect(b['shift_dependents'], isTrue);
      expect(b['start'], '2026-11-24');
      expect(b['due'], '2026-11-27');
      await done(t, s);
    });

    testWidgets('bình luận có @nhắc, thả cảm xúc trên bình luận và trên việc', (t) async {
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-32', ai: false);
      await t.ensureVisible(find.byKey(const ValueKey('crx-c1-+1')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('crx-c1-+1')));
      await settle(t, 2);
      expect(be.bodies['POST /tw/api/reactions'], {'target': 'comment', 'id': 'c1', 'emoji': '+1'});
      await t.ensureVisible(find.byKey(const ValueKey('comment-send')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('rt-mention')).last);
      await settle(t, 4);
      await t.tap(find.byKey(const ValueKey('mention-user-u-hung')));
      await settle(t, 2);
      await t.tap(find.byKey(const ValueKey('comment-send')));
      await settle(t);
      final post = be.bodies['POST /tw/api/tasks/t-32/comments'];
      expect(post, isNotNull);
      final runs = ((post!['blocks'] as List).first as Map)['r'] as List;
      expect(runs.any((r) => (r as Map)['m'] != null && r['m']['k'] == 'user' && r['m']['id'] == 'u-hung'), isTrue);
      await done(t, s);
    });

    testWidgets('@nhắc: gợi ý người và agent; agent → thuộc tính m + dòng nhắc; trạng thái agent dưới bình luận', (t) async {
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-32');
      // Bình luận đã @nhắc agent: dòng trạng thái + Mở phiên (phiên lấy từ lượt chạy của việc).
      expect(find.text('Codex đã xong · 7 bước'), findsOneWidget);
      expect(find.text('Claude đang xử lý… · 4 bước'), findsOneWidget);
      expect(find.byKey(const ValueKey('runline-open-b-codex')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('comment-send')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('rt-mention')).last);
      await settle(t, 4);
      expect(find.byKey(const ValueKey('mention-user-u-hung')), findsOneWidget);
      expect(find.byKey(const ValueKey('mention-agent-b-claude')), findsOneWidget);
      expect(find.byKey(const ValueKey('mention-agent-b-codex')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('mention-agent-b-claude')));
      await settle(t, 3);
      expect(find.text('Claude sẽ đọc việc này và làm theo bình luận'), findsOneWidget);
      await shot(t, 'd5h-agent-mention');
      await t.tap(find.byKey(const ValueKey('comment-send')));
      await settle(t);
      final runs = ((be.bodies['POST /tw/api/tasks/t-32/comments']!['blocks'] as List).first as Map)['r'] as List;
      expect(runs.any((r) => (r as Map)['m'] != null && r['m']['k'] == 'agent' && r['m']['id'] == 'b-claude'), isTrue);
      expect(find.byKey(const ValueKey('agent-hint')), findsNothing);
      await done(t, s);
    });

    testWidgets('tiến độ trực tiếp: bước + chữ đang viết (bảng) dưới bình luận; xong thì thu gọn; cập nhật theo run_progress', (t) async {
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-32');
      // Lượt @nhắc đang chạy: 4 bước, chữ đang viết có bảng.
      expect(find.text('Claude đang xử lý… · 4 bước'), findsOneWidget);
      expect(find.text('🔓 Chạy không cần duyệt (chủ bot)'), findsOneWidget);
      expect(find.text('Viết docs/api-ton-kho.md'), findsOneWidget);
      expect(find.byKey(const ValueKey('run-text-r-c4')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('run-text-r-c4')), matching: find.byKey(const ValueKey('tw-table'))), findsOneWidget);
      // Lượt Bắt đầu trong thẻ agent: ai xem cũng thấy, ghi rõ chế độ thường.
      expect(find.text('Chạy chế độ thường (người giao không phải chủ bot)'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('run-text-r-c4')), 100, scrollable: find.descendant(of: find.byKey(const ValueKey('right-col')), matching: find.byType(Scrollable)).first);
      await shot(t, 'd5i-agent-streaming');
      // Lượt đã xong: thu gọn, bấm để xem các bước.
      expect(find.text('Codex đã xong · 7 bước'), findsOneWidget);
      expect(find.text('Chạy lại bun test: 14/14 đạt'), findsNothing);
      await t.ensureVisible(find.byKey(const ValueKey('run-toggle-r-old')));
      await t.tap(find.byKey(const ValueKey('run-toggle-r-old')));
      await t.pump();
      expect(find.text('Chạy lại bun test: 14/14 đạt'), findsOneWidget);
      await shot(t, 'd5j-agent-done');
      // run_progress → tải lại tiến độ.
      (be.progress['r-c4']!['progress'] as Map)['steps'].add({'id': 's4', 'kind': 'tool', 'title': 'Thêm phần mã lỗi', 'status': 'running', 'at': 5});
      s.debugEvent({'type': 'run_progress', 'id': 'r-c4', 'task_id': 't-32', 'project_id': 'p-ra', 'seq': 6});
      await settle(t, 8);
      expect(find.text('Claude đang xử lý… · 5 bước'), findsOneWidget);
      expect(find.text('Thêm phần mã lỗi'), findsOneWidget);
      // Xong: chuyển thành dòng thu gọn.
      be.progress['r-c4']!['state'] = 'review';
      s.debugEvent({'type': 'run_progress', 'id': 'r-c4', 'task_id': 't-32', 'project_id': 'p-ra', 'seq': 7});
      await settle(t, 8);
      expect(find.text('Claude đã xong · 5 bước'), findsOneWidget);
      expect(find.byKey(const ValueKey('run-text-r-c4')), findsNothing);
      await done(t, s);
    });

    testWidgets('@nhắc: agent không được dùng thì không gợi ý', (t) async {
      launcher.allowed = {'b-claude'};
      final s = await pump(t, project: 'RA');
      await openTaskPage(t, s, 'RA-32');
      await t.ensureVisible(find.byKey(const ValueKey('comment-send')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('rt-mention')).last);
      await settle(t, 4);
      expect(find.byKey(const ValueKey('mention-agent-b-claude')), findsOneWidget);
      expect(find.byKey(const ValueKey('mention-agent-b-codex')), findsNothing);
      await done(t, s);
    });

    testWidgets('tạo việc: giao agent + trạng thái bắt đầu → agent chạy ngay', (t) async {
      final s = await pump(t, project: 'RA', view: 'list');
      await t.tap(find.byKey(const ValueKey('new-task')));
      await settle(t, 3);
      await t.enterText(find.byKey(const ValueKey('nt-title')), 'Lọc đại lý muốn dùng thử');
      await t.tap(find.byKey(const ValueKey('nt-assignee')));
      await settle(t, 4);
      expect(find.text('Agent AI'.toUpperCase()), findsOneWidget);
      await shot(t, 'd8-assign-agent');
      await t.tap(find.byKey(const ValueKey('pick-agent-b-claude')));
      await t.tap(find.byKey(const ValueKey('assignee-ok')));
      await settle(t, 2);
      expect(find.textContaining('Agent chưa chạy ngay'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('nt-status')));
      await settle(t, 2);
      await t.tap(find.byKey(const ValueKey('pick-status-s-doing')));
      await settle(t, 2);
      expect(find.textContaining('agent sẽ bắt đầu làm ngay'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('nt-save')));
      await settle(t);
      final b = be.bodies['POST /tw/api/projects/p-ra/tasks']!;
      expect(b['status_id'], 's-doing');
      expect((b['assignees'] as List).single['kind'], 'agent');
      await done(t, s);
    });

    testWidgets('thông báo + tìm kiếm', (t) async {
      final s = await pump(t, section: 'inbox');
      expect(find.text('Claude đã nộp kết quả RA-30, chờ bạn duyệt'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // số chưa đọc trên thanh bên
      await t.tap(find.byKey(const ValueKey('nav-search')));
      await settle(t, 2);
      await t.enterText(find.byKey(const ValueKey('search-q')), 'tồn kho');
      await settle(t, 6);
      expect(find.byKey(const ValueKey('result-RA-32')), findsOneWidget);
      await done(t, s);
    });
  });

  group('điện thoại', () {
    for (final dark in [false, true]) {
      final sfx = dark ? 'dark' : 'light';
      testWidgets('dự án, Kanban vuốt cột, chi tiết, AI, Gantt, Việc của tôi ($sfx)', (t) async {
        final s = await pump(t, size: _phone, dark: dark);
        expect(find.byKey(const ValueKey('project-RA')), findsOneWidget);
        expect(find.byKey(const ValueKey('ptab-projects')), findsOneWidget);
        await shot(t, 'p1-projects-$sfx');
        await t.tap(find.byKey(const ValueKey('project-RA')));
        await settle(t, 8);
        expect(find.byKey(const ValueKey('ptab-s-doing')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('ptab-s-doing')));
        await settle(t, 4);
        expect(find.byKey(const ValueKey('card-RA-32')), findsOneWidget);
        await shot(t, 'p2-kanban-$sfx');
        await t.tap(find.byKey(const ValueKey('view-gantt')));
        await settle(t, 4);
        expect(find.byKey(const ValueKey('gbar-RA-32')), findsOneWidget);
        await shot(t, 'p5-gantt-$sfx');
        await t.tap(find.byKey(const ValueKey('view-kanban')));
        await settle(t, 4);
        await t.tap(find.byKey(const ValueKey('ptab-s-doing')));
        await settle(t, 4);
        await t.tap(find.byKey(const ValueKey('card-RA-32')));
        await settle(t, 8);
        expect(find.byKey(const ValueKey('p-status')), findsOneWidget);
        expect(find.text('Viết test tồn kho'), findsOneWidget);
        expect(find.byKey(const ValueKey('ai-open')), findsNothing);
        await shot(t, 'p3-task-$sfx');
        await done(t, s);
      });

      testWidgets('Việc của tôi + thông báo ($sfx)', (t) async {
        final s = await pump(t, size: _phone, dark: dark, section: 'mine');
        expect(find.byKey(const ValueKey('mine-row-RA-35')), findsOneWidget);
        await shot(t, 'p6-mine-$sfx');
        await t.tap(find.byKey(const ValueKey('ptab-inbox')));
        await settle(t, 4);
        expect(find.textContaining('Minh nhắc bạn'), findsOneWidget);
        await shot(t, 'p7-inbox-$sfx');
        await done(t, s);
      });
    }

    testWidgets('điện thoại: bảng rộng cuộn ngang trong khung, không tràn trang', (t) async {
      final s = await pump(t, size: _phone);
      await openTaskPage(t, s, 'RA-38');
      final tw = find.byKey(const ValueKey('tw-table'));
      expect(tw, findsOneWidget);
      final view = t.getRect(tw);
      expect(view.right, lessThanOrEqualTo(390));
      final inner = t.getSize(find.descendant(of: tw, matching: find.byType(Table)));
      expect(inner.width, greaterThan(view.width)); // rộng hơn khung → cuộn ngang
      await t.drag(tw, const Offset(-200, 0));
      await settle(t, 2);
      await shot(t, 'p10-table-scroll');
      await done(t, s);
    });

    testWidgets('điện thoại: bấm việc con vẫn mở trang mới', (t) async {
      final s = await pump(t, size: _phone);
      await openTaskPage(t, s, 'RA-32');
      final before = pushes.n;
      await t.scrollUntilVisible(find.byKey(const ValueKey('sub-RA-63')), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const ValueKey('sub-RA-63')));
      await settle(t, 8);
      expect(pushes.n, before + 1);
      expect(find.byKey(const ValueKey('task-panel')), findsNothing);
      expect(find.text('Viết test tồn kho'), findsWidgets);
      await done(t, s);
    });

    testWidgets('cài đặt trạng thái trên điện thoại (sửa: màu, nhóm, bắt đầu)', (t) async {
      final s = await pump(t, size: _phone, dark: true);
      await t.tap(find.byKey(const ValueKey('project-RA')));
      await settle(t, 8);
      // Tab Cài đặt trên điện thoại: danh sách mục → chi tiết, ngay trong màn hình dự án.
      final before = pushes.n;
      await t.tap(find.byKey(const ValueKey('view-settings')));
      await settle(t, 4);
      expect(pushes.n, before);
      expect(find.byKey(const ValueKey('set-agents')), findsOneWidget);
      await shot(t, 'p9-settings-list-dark');
      await t.tap(find.byKey(const ValueKey('set-statuses')));
      await settle(t, 4);
      expect(find.byKey(const ValueKey('set-back')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('st-s-review')));
      await settle(t, 4);
      expect(find.text('Sửa "Chờ duyệt"'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('st-color-#E5484D')));
      await t.pump();
      await shot(t, 'p8-status-edit-dark');
      await t.tap(find.byKey(const ValueKey('st-save')));
      await settle(t);
      expect(be.bodies['PATCH /tw/api/statuses/s-review']!['color'], '#E5484D');
      await done(t, s);
    });
  });

  test('khối rỗng không làm hỏng mô tả', () {
    expect(blocksToJson([TBlock()]).single['r'], isEmpty);
    expect(blocksFromJson(null), isEmpty);
    expect(blocksFromJson('**a**').single.r.single.f.b, isTrue);
  });
}
