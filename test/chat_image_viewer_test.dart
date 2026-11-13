import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/chat_page.dart';
import 'package:flygo_chat/ui/image_edit.dart';
import 'package:flygo_chat/ui/media_view.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

/// Xem ảnh phủ màn hình hiện tại, ảnh luôn hiện trọn, sửa ảnh đang chờ gửi rồi "Xong" là thay ảnh.
void main() {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba'});
  final post = MmPost({'id': 'p', 'channel_id': 'c', 'user_id': 'me', 'message': '', 'create_at': 0});
  late Directory tmp;
  late List<ChatImage> imgs;

  /// Ảnh PNG thật trên máy (ảnh trong kiểm thử không tải được từ mạng).
  Future<String> png(String name, int w, int h) async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF3366FF));
    final img = await rec.endRecording().toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('${tmp.path}/$name')..writeAsBytesSync(bytes!.buffer.asUint8List());
    return f.path;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('viewer_test');
  });
  tearDown(() {
    editImageOverride = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> pumpChat(WidgetTester t) => t.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (c) => Column(children: [
                const Text('tin nhắn bên dưới'),
                FilledButton(onPressed: () => openImages(c, post, imgs, 0), child: const Text('mở ảnh')),
              ]),
            ),
          ),
        ),
      ));

  Future<void> open(WidgetTester t) async {
    await t.runAsync(() async {
      imgs = [
        ChatImage(localPath: await png('tall.png', 40, 400), aspect: .1),
        ChatImage(localPath: await png('wide.png', 400, 40), aspect: 10),
        ChatImage(localPath: await png('sq.png', 50, 50), aspect: 1),
      ];
    });
    await pumpChat(t);
    await t.tap(find.text('mở ảnh'));
    await t.pumpAndSettle();
  }

  testWidgets('mở ảnh: phủ lên màn hình hiện tại (không mở trang mới, màn dưới vẫn còn)', (t) async {
    await open(t);
    expect(find.byType(GalleryViewer), findsOneWidget);
    final route = ModalRoute.of(t.element(find.byType(GalleryViewer)))!;
    expect(route.opaque, isFalse, reason: 'phủ lên, không thay trang');
    expect(route, isNot(isA<MaterialPageRoute>()));
    expect(find.text('tin nhắn bên dưới'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('phím mũi tên chuyển ảnh, Esc đóng', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(GalleryViewer), findsNothing);
  });

  testWidgets('nút X đóng', (t) async {
    await open(t);
    await t.tap(find.byTooltip('Đóng'));
    await t.pumpAndSettle();
    expect(find.byType(GalleryViewer), findsNothing);
  });

  testWidgets('chạm ra ngoài ảnh thì đóng, chạm vào ảnh thì ẩn thanh công cụ', (t) async {
    await open(t);
    final size = t.getSize(find.byType(GalleryViewer));
    // Ảnh dài 40x400 nằm giữa: chạm giữa là chạm vào ảnh.
    await t.tapAt(size.center(Offset.zero));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.byType(GalleryViewer), findsOneWidget);
    // Chạm vào nền đen bên trái ảnh: đóng.
    await t.tapAt(Offset(size.width * .1, size.height / 2));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(find.byType(GalleryViewer), findsNothing);
  });

  testWidgets('ảnh trong trình xem luôn hiện trọn (contain), không cắt', (t) async {
    await open(t);
    final img = t.widget<Image>(find.byKey(const ValueKey('viewer-image-0')));
    expect(img.fit, BoxFit.contain);
  });

  test('khung ảnh vừa trọn trong màn hình với mọi tỉ lệ', () {
    const phone = Size(400, 800), desk = Size(1400, 900);
    for (final box in [phone, desk]) {
      for (final a in [0.05, 0.3, 0.75, 1.0, 16 / 9, 8.0]) {
        final r = imageRectIn(box, a);
        expect(r.left >= -0.01 && r.top >= -0.01 && r.right <= box.width + .01 && r.bottom <= box.height + .01, isTrue,
            reason: 'tỉ lệ $a trong $box');
        expect(r.width / r.height, closeTo(a, 1e-6));
        expect(r.width == box.width || r.height == box.height, isTrue, reason: 'chạm một cạnh');
      }
    }
  });

  testWidgets('ảnh chờ gửi: bấm để sửa, sửa xong thì thay ảnh cũ, giữ tên', (t) async {
    late String a, b;
    await t.runAsync(() async {
      a = await png('paste_1.png', 20, 20);
      b = await png('note.txt', 2, 2);
    });
    final staged = [(a, 'paste_1.png'), (b, 'note.txt')];
    final edited = <(String, String)>[];
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: StagedFiles(files: staged, onEdit: edited.add, onRemove: (_) {})),
    ));
    await t.tap(find.byKey(ValueKey('staged-$a')));
    expect(edited, [(a, 'paste_1.png')]);
    expect(find.byKey(ValueKey('staged-$b')), findsNothing, reason: 'tệp không phải ảnh thì không mở trình sửa');
    expect(editedStagedFile((a, 'paste_1.png'), '/tmp/edit_9.jpg'), ('/tmp/edit_9.jpg', 'paste_1.jpg'));
    expect(editedStagedFile((a, 'anh'), '/tmp/edit_9.jpg'), ('/tmp/edit_9.jpg', 'anh.jpg'));
  });

  test('chọn biểu tượng: chèn đúng chỗ con trỏ, con trỏ đứng sau biểu tượng', () {
    const v = TextEditingValue(text: 'Chào bạn', selection: TextSelection.collapsed(offset: 4));
    final r = insertAtCursor(v, '😀');
    expect(r.text, 'Chào😀 bạn');
    expect(r.selection, TextSelection.collapsed(offset: 4 + '😀'.length));
    final sel = insertAtCursor(const TextEditingValue(text: 'abc xyz', selection: TextSelection(baseOffset: 4, extentOffset: 7)), '👍');
    expect(sel.text, 'abc 👍');
    expect(insertAtCursor(const TextEditingValue(text: 'hi'), '🎉').text, 'hi🎉');
  });
}
