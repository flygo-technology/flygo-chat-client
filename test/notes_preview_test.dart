// Ảnh xem trước Ghi chú tin nhắn (chạy tay): NOTES_OUT=<thư mục> flutter test test/notes_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/notes.dart';
import 'package:flygo_chat/ui/reactions.dart';
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

const _t = 1793840400000;

void main() {
  final out = Platform.environment['NOTES_OUT'];
  final app = AppState('test')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  for (final (id, n) in [('me', 'Ba'), ('u2', 'Lan Kế toán'), ('u3', 'Tuấn Kho')]) {
    app.users[id] = MmUser({'id': id, 'username': n.toLowerCase(), 'first_name': n});
  }
  final post = MmPost({
    'id': 'p' * 26, 'channel_id': 'c1', 'user_id': 'u3', 'create_at': _t, 'message': 'Hàng cáp thép lô 12 về kho rồi nhé, thiếu 2 cuộn so với đơn.',
    'props': {
      'flygo_notes': [
        {'id': 'n1', 'by': 'u2', 'color': 'yellow', 'text': 'Đã báo NCC giao bù 2 cuộn trước 10/11.', 'at': _t + 600000},
        {'id': 'n2', 'by': 'me', 'color': 'green', 'text': 'Trừ 2 cuộn khi thanh toán đợt này.', 'at': _t + 900000, 'edited_at': _t + 1200000},
        {'id': 'n3', 'by': 'u3', 'color': 'pink', 'text': 'Cuộn số 7 bị móp, chụp ảnh gửi kèm.', 'at': _t + 1500000},
      ],
    },
  });

  Widget chat(BuildContext c) {
    final pal = Pal.of(c);
    return Scaffold(
      backgroundColor: pal.chatBg,
      appBar: AppBar(title: const Text('Kho & Kế toán')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 330,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: pal.inBubble, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Tuấn Kho', style: TextStyle(fontWeight: FontWeight.w700, color: pal.accentText, fontSize: 13)),
              const SizedBox(height: 2),
              Text(post.message, style: TextStyle(color: pal.text, fontSize: 15)),
              Align(alignment: Alignment.centerRight, child: Text('08:00', style: TextStyle(color: pal.sub, fontSize: 11))),
              MessageNotes(app: app, post: post, width: 310),
            ]),
          ),
        ),
      ]),
    );
  }

  Future<void> shot(WidgetTester tester, String name, Brightness b, {void Function(BuildContext)? open, String? longPress}) async {
    tester.view.physicalSize = const Size(400, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    late BuildContext ctx;
    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        builder: (c, child) => RepaintBoundary(key: key, child: child!),
        home: Builder(builder: (c) {
          ctx = c;
          return chat(c);
        }),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    if (open != null) {
      open(ctx);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    if (longPress != null) {
      await tester.longPress(find.text(longPress));
      await tester.pump(const Duration(milliseconds: 600));
    }
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('ảnh xem trước ghi chú', (tester) async {
    if (out == null) return;
    await tester.runAsync(_fonts);
    for (final b in Brightness.values) {
      await shot(tester, 'notes-chat-${b.name}', b);
    }
    await shot(tester, 'notes-menu', Brightness.light,
        open: (c) => showMessageMenu(context: c, app: app, post: post, mine: false, anchor: const Rect.fromLTWH(12, 70, 330, 80), actions: [
              MenuAction(Icons.reply, 'Trả lời', () {}),
              MenuAction(Icons.forum_outlined, 'Trả lời trong luồng riêng', () {}),
              MenuAction(Icons.sticky_note_2_outlined, 'Thêm ghi chú', () {}),
              MenuAction(Icons.add_task_rounded, 'Tạo việc', () {}),
              MenuAction(Icons.shortcut, 'Chuyển tiếp', () {}),
            ]));
    await shot(tester, 'notes-editor', Brightness.light, open: (c) => showNoteEditor(c, text: 'Trừ 2 cuộn khi thanh toán đợt này.', color: 'green'));
    await shot(tester, 'notes-long-press', Brightness.light, longPress: 'Trừ 2 cuộn khi thanh toán đợt này.');
  });
}
