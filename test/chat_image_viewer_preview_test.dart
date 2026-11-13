// Ảnh xem trước trình xem ảnh / ảnh chờ gửi (chạy tay): IMG_OUT=<thư mục> flutter test test/chat_image_viewer_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/image_edit.dart';
import 'package:flygo_chat/ui/media_view.dart';
import 'package:flygo_chat/ui/message_select.dart';
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

  // Máy Linux: giao diện dùng 'Noto Sans'; chữ không đặt phông (vd thanh chọn chữ) dùng phông mặc định của kiểm thử.
  // Nạp Roboto dưới các tên đó để chữ không thành ô vuông.
  for (final family in ['Roboto', 'Noto Sans', 'FlutterTest']) {
    await load(family, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// Ảnh giả: "ảnh chụp màn hình" dài (các dòng tin) hoặc ảnh toàn cảnh (dải màu), có viền đỏ để thấy ảnh không bị cắt.
Future<String> _picture(String path, int w, int h) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFF4F6FA));
  if (h > w) {
    for (var y = 40.0, i = 0; y < h - 60; y += 70, i++) {
      final left = i.isEven;
      final bw = w * (.45 + (i * 37 % 30) / 100);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left ? 24 : w - 24 - bw, y, bw, 50), const Radius.circular(14)),
          Paint()..color = left ? const Color(0xFFFFFFFF) : const Color(0xFFD9FDD3));
    }
  } else {
    final colors = [0xFF1E3A8A, 0xFF2563EB, 0xFF38BDF8, 0xFF22C55E, 0xFFFACC15, 0xFFF97316];
    for (var i = 0; i < colors.length; i++) {
      c.drawRect(Rect.fromLTWH(w * i / colors.length, 0, w / colors.length, h.toDouble()), Paint()..color = Color(colors[i]));
    }
  }
  c.drawRect(Rect.fromLTWH(6, 6, w - 12.0, h - 12.0), Paint()
    ..color = const Color(0xFFE11D48)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 12);
  final img = await rec.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  return path;
}

void main() {
  final out = Platform.environment['IMG_OUT'];
  final app = AppState('test')..me = MmUser({'id': 'me', 'username': 'ba', 'first_name': 'Ba'});
  final post = MmPost({'id': 'p' * 26, 'channel_id': 'c1', 'user_id': 'me', 'create_at': 0, 'message': ''});

  Widget chat(BuildContext c) {
    final pal = Pal.of(c);
    return Scaffold(
      backgroundColor: pal.chatBg,
      appBar: AppBar(title: const Text('Kho & Kế toán')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (var i = 0; i < 8; i++)
          Align(
            alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: i.isEven ? pal.inBubble : pal.outBubble, borderRadius: BorderRadius.circular(12)),
              child: Text('Tin nhắn số ${i + 1}', style: TextStyle(color: pal.text)),
            ),
          ),
      ]),
    );
  }

  Future<void> shot(WidgetTester t, String name, Size size, {List<ChatImage>? images, int initial = 0, Widget? body, List<String> precache = const [], String? edit, String? longPress}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    late BuildContext ctx;
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        builder: (c, child) => RepaintBoundary(key: key, child: child!),
        home: Builder(builder: (c) {
          ctx = c;
          return body ?? chat(c);
        }),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    // Giải mã ảnh trước (ngoài đồng hồ giả của kiểm thử).
    await t.runAsync(() async {
      for (final p in precache) {
        await precacheImage(FileImage(File(p)), ctx);
      }
    });
    if (images != null) {
      showGallery(ctx, post, images, initial);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
    }
    if (longPress != null) {
      await t.longPress(find.text(longPress));
      await t.pump(const Duration(milliseconds: 600));
    }
    if (edit != null) {
      editImage(ctx, edit);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
    }
    for (var i = 0; i < (edit != null ? 20 : 5); i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
    await t.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('ảnh xem trước trình xem ảnh', (t) async {
    if (out == null) return;
    late String tall, wide, sq;
    await t.runAsync(() async {
      await _fonts();
      tall = await _picture('$out/_tall.png', 720, 3200);
      wide = await _picture('$out/_wide.png', 3000, 700);
      sq = await _picture('$out/_sq.png', 800, 800);
    });
    MmFile f(String id, int w, int h) => MmFile({'id': id, 'name': '$id.png', 'mime_type': 'image/png', 'width': w, 'height': h});
    final album = [
      ChatImage(localPath: tall, file: f('a', 720, 3200), aspect: 720 / 3200),
      ChatImage(localPath: wide, file: f('b', 3000, 700), aspect: 3000 / 700),
      ChatImage(localPath: sq, file: f('c', 800, 800), aspect: 1),
    ];
    const desk = Size(1280, 800), phone = Size(390, 844);
    await shot(t, 'viewer-desktop-tall', desk, images: album, initial: 0, precache: [tall, wide, sq]);
    await shot(t, 'viewer-desktop-wide', desk, images: album, initial: 1, precache: [tall, wide, sq]);
    await shot(t, 'viewer-phone-tall', phone, images: [album[0]], precache: [tall]);
    await shot(t, 'viewer-phone-wide', phone, images: [album[1]], precache: [wide]);
    await shot(t, 'select-text-phone', phone,
        longPress: 'Hàng cáp thép lô 12 về kho rồi nhé, thiếu 2 cuộn so với đơn.',
        body: Builder(
          builder: (c) => Theme(
            data: Theme.of(c).copyWith(platform: TargetPlatform.android),
            child: Scaffold(
              backgroundColor: Pal.of(c).chatBg,
              appBar: AppBar(title: const Text('Kho & Kế toán')),
              body: Padding(
                padding: const EdgeInsets.fromLTRB(12, 120, 60, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Pal.of(c).inBubble, borderRadius: BorderRadius.circular(12)),
                    child: MessageTextSelection(
                        desktop: false, onMore: () {}, child: Text('Hàng cáp thép lô 12 về kho rồi nhé, thiếu 2 cuộn so với đơn.', style: TextStyle(color: Pal.of(c).text, fontSize: 15))),
                  ),
                ),
              ),
            ),
          ),
        ));
    await shot(t, 'editor-phone', phone, precache: [sq], edit: sq);
    await shot(t, 'composer-staged-phone', phone, precache: [sq, tall],
        body: Builder(
          builder: (c) => Scaffold(
            backgroundColor: Pal.of(c).chatBg,
            appBar: AppBar(title: const Text('Kho & Kế toán')),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: StagedFiles(files: [(sq, 'paste_1.png'), (tall, 'paste_2.png'), ('/x/bao-gia.pdf', 'bao-gia.pdf')], onEdit: (_) {}, onRemove: (_) {}),
              ),
            ),
          ),
        ));
  });
}
