import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/image_disk_cache.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/clip.dart';
import 'package:flygo_chat/ui/media_view.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

/// Trình xem ảnh: Sao chép ảnh / Tải ảnh cho mọi ảnh (chat lẫn Bảng tin), dữ liệu lấy từ bộ nhớ đệm, phím Ctrl/⌘+C, Ctrl/⌘+S.
void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('viewer_copy');
    // Ảnh giải mã của kiểm thử trước (cùng khoá) còn trong bộ nhớ ảnh: xoá để mỗi kiểm thử tải lại từ đầu.
    imageCache.clear();
    imageCache.clearLiveImages();
  });
  tearDown(() {
    copyImageOverride = null;
    tmp.deleteSync(recursive: true);
  });

  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba'});
  // Tin giả như Bảng tin dùng (chưa gửi): trước đây ẩn hết nút.
  final dummy = MmPost({'id': 'bang-tin', 'channel_id': '', 'user_id': '', 'message': '', 'create_at': 0, '_send': 'sending'});

  Future<Uint8List> png() async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.orange);
    final img = await rec.endRecording().toImage(8, 8);
    return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  Future<(ImageDiskCache, Map<String, int>, List<ChatImage>)> setup(WidgetTester t) async {
    late Uint8List bytes;
    await t.runAsync(() async => bytes = await png());
    final cache = ImageDiskCache(dir: () async => tmp);
    final fetched = <String, int>{};
    final images = [
      for (var i = 0; i < 2; i++)
        ChatImage(aspect: 1, image: DiskCachedImage('bt:x:f$i', () async {
          fetched['f$i'] = (fetched['f$i'] ?? 0) + 1;
          return bytes;
        }, cache: cache)),
    ];
    late BuildContext ctx;
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      }))),
    ));
    showGallery(ctx, dummy, images, 0);
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    }
    return (cache, fetched, images);
  }

  testWidgets('ảnh Bảng tin (tin giả): có Sao chép ảnh và Tải ảnh', (t) async {
    await setup(t);
    expect(find.byTooltip('Sao chép ảnh'), findsOneWidget);
    expect(find.byTooltip('Tải ảnh'), findsOneWidget);
    expect(find.byTooltip('Sửa'), findsNothing, reason: 'Sửa / Chuyển tiếp chỉ cho ảnh chat đã gửi');
  });

  testWidgets('Ctrl+C sao chép ảnh đang xem từ bộ nhớ đệm, không tải lại', (t) async {
    final (_, fetched, _) = await setup(t);
    Uint8List? copied;
    var copies = 0;
    copyImageOverride = (b) async {
      copies++;
      copied = b;
      return true;
    };
    // Ảnh đang xem đã tải (vào bộ nhớ đệm) khi hiện lên.
    for (var i = 0; i < 300 && fetched['f0'] == null; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    }
    final before = fetched['f0'];
    expect(before, 1, reason: '$fetched');
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyC);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (var i = 0; i < 20 && copied == null; i++) {
      await t.pump(const Duration(milliseconds: 16));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    }
    expect(copied, isNotNull);
    expect(copies, 1);
    expect(fetched['f0'], before, reason: 'đã có trong bộ nhớ đệm: không tải lại');
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Đã sao chép ảnh'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
  });

  test('lưu vào Tải về: không ghi đè tệp trùng tên', () async {
    if (Platform.isAndroid || Platform.isIOS) return;
    final src = File('${tmp.path}/anh.png')..writeAsBytesSync([1, 2, 3]);
    final dl = Directory('${tmp.path}/dl');
    final a = await saveImageFile(src.path, into: dl);
    final b = await saveImageFile(src.path, into: dl);
    expect(a, endsWith('anh.png'));
    expect(b, endsWith('anh (1).png'));
    expect(File(b).readAsBytesSync(), [1, 2, 3]);
  });
}
