// Ảnh xem trước Việc cần làm (chạy tay): CL_OUT=<thư mục> flutter test test/checklist_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/checklist.dart';
import 'package:flygo_chat/ui/theme.dart';
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

void main() {
  final out = Platform.environment['CL_OUT'];
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  for (final (id, n) in [('me', 'Ba'), ('u2', 'Lan Kế toán'), ('u3', 'Tuấn Kho')]) {
    app.users[id] = MmUser({'id': id, 'username': n, 'first_name': n});
  }

  Future<void> shot(WidgetTester t, String name, Size size, Widget child) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.light), home: RepaintBoundary(key: key, child: child)),
    ));
    await t.pump(const Duration(milliseconds: 400));
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('ảnh xem trước việc cần làm', (t) async {
    if (out == null) return;
    await t.runAsync(_fonts);
    final initial = buildChecklist(
        title: 'Kiểm kho cuối tuần',
        desc: 'Làm trước 17h thứ Sáu, chụp ảnh gửi kèm nếu thiếu hàng.',
        lines: ['Đếm cáp thép lô 12', 'Kiểm biến tần trong kho HN', 'Cập nhật số liệu lên ERP'],
        me: 'me',
        tick: 'some',
        tickers: ['u2', 'u3']);
    await shot(t, 'todo-editor', const Size(400, 1000), ChecklistEditorPage(app: app, channelId: 'c', initial: null));
    // Trang soạn có sẵn dữ liệu (như khi sửa)
    await shot(t, 'todo-editor-filled', const Size(400, 1100), ChecklistEditorPage(app: app, channelId: 'c', initial: initial));
    final done = Map<String, dynamic>.of(initial);
    done['items'] = [
      {...(initial['items'] as List)[0], 'done': true, 'done_by': 'u3', 'done_at': 1},
      {...(initial['items'] as List)[1], 'done': true, 'done_by': 'me', 'done_at': 1},
      (initial['items'] as List)[2],
    ];
    MmPost p(Map<String, dynamic> c, String by) => MmPost({'id': 'p$by', 'channel_id': 'c', 'user_id': by, 'message': 'x', 'create_at': 0, 'props': {'flygo_checklist': c}});
    final personal = buildChecklist(title: 'Việc của tôi hôm nay', lines: ['Gọi lại cho NCC', 'Gửi báo giá cho anh Tuấn', 'Đối chiếu hoá đơn tháng 10'], me: 'me');
    (personal['items'] as List)[0]['done'] = true;
    await shot(
      t,
      'todo-cards',
      const Size(400, 820),
      Builder(
        builder: (c) => Scaffold(
          backgroundColor: Pal.of(c).chatBg,
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Align(alignment: Alignment.centerLeft, child: ChecklistCard(app: app, post: p(done, 'me'), width: 360)),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: ChecklistCard(app: app, post: p(personal, 'me'), width: 360)),
          ]),
        ),
      ),
    );
  });
}
