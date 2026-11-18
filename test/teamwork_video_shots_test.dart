// Ảnh cho video giới thiệu "Làm việc nhóm": giao diện thật + dữ liệu giả, giao diện sáng, nét gấp đôi (1440x900 điểm →
// 2880x1800 px). Mỗi ảnh kèm toạ độ các phần tử (điểm logic) trong layout.json để trang video đặt lớp động đúng chỗ.
// Chạy tay: TW_VIDEO_OUT=<thư mục> flutter test test/teamwork_video_shots_test.dart (không đặt biến thì chỉ chạy, không ghi).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/teamwork/store.dart';
import 'package:flygo_chat/ui/teamwork/teamwork_page.dart';
import 'package:flygo_chat/ui/theme.dart';

import 'fixtures/teamwork_fake.dart';

const _desk = Size(1440, 900);
const _dpr = 2.0;
final _out = Platform.environment['TW_VIDEO_OUT'];
final _layout = <String, Map<String, List<double>>>{};

/// Dữ liệu giả riêng cho video: bỏ dự án dễ gợi tới khách hàng thật.
void videoData(FakeTw be) {
  final bt = be.projects.firstWhere((p) => p['id'] == 'p-bt');
  bt['name'] = 'Khai trương chi nhánh mới';
  bt['key'] = 'KC';
  bt['description'] = [
    {'id': 'd1', 't': 'p', 'r': [{'x': 'Mặt bằng, nhân sự, hàng hoá và sự kiện khai trương ngày 20/12.'}]},
  ];
}

void main() {
  late FakeTw be;
  setUp(() {
    be = FakeTw();
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

  Future<TwStore> pump(WidgetTester t, {String? section, String? project, String? view}) async {
    t.view.physicalSize = _desk * _dpr;
    t.view.devicePixelRatio = _dpr;
    addTearDown(t.view.reset);
    await t.runAsync(twFonts);
    final s = newTwStore(be, launcher: FakeLauncher(), ai: FakeAiSessions());
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
}
