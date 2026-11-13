import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/image_disk_cache.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/media_view.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

/// Ảnh đã xem lưu trên đĩa (không tải lại, kể cả khi mở lại app); mở trình xem thì tải sẵn các ảnh còn lại của tin.
void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('img_cache_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // Đồng hồ giả: mỗi lần ghi / dùng ảnh là một giây sau, thứ tự "lâu chưa dùng" không phụ thuộc độ phân giải giờ tệp
  // hay máy chạy kiểm thử nhanh chậm.
  var clock = DateTime(2026, 1, 1);
  DateTime tick() => clock = clock.add(const Duration(seconds: 1));
  ImageDiskCache cache({int max = 1 << 20}) => ImageDiskCache(dir: () async => tmp, maxBytes: max, now: tick);

  /// Cho trình xem chạy: luân phiên đồng hồ giả (dựng khung hình) và việc thật (đọc / ghi đĩa, giải mã) cho tới khi [done]
  /// hoặc hết [rounds] vòng; cuối cùng chờ mọi việc ghi đĩa xong.
  Future<void> loadAll(WidgetTester t, ImageDiskCache c, bool Function() done, {int rounds = 300}) async {
    Future<void> step() async {
      await t.pump(const Duration(milliseconds: 16));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
    }

    for (var i = 0; i < rounds && !done(); i++) {
      await step();
    }
    // Việc ghi đĩa bắt đầu trong vùng đồng hồ giả nên chỉ chạy tiếp khi pump: pump tới khi xong (có giới hạn).
    for (var i = 0; i < 500 && c.busy; i++) {
      await step();
    }
    expect(c.busy, isFalse, reason: 'ghi đĩa phải xong');
  }
  Uint8List bytes(int n, [int v = 7]) => Uint8List.fromList(List.filled(n, v));


  test('đã tải thì lần sau đọc từ đĩa, kể cả sau khi mở lại app', () async {
    var fetched = 0;
    Future<Uint8List> fetch() async {
      fetched++;
      return bytes(100);
    }

    final a = cache();
    expect(await a.get('mm:x:f1:full', fetch), bytes(100));
    await a.flush();
    expect(await a.get('mm:x:f1:full', fetch), bytes(100));
    expect(fetched, 1);
    // Mở lại app: bộ nhớ đệm mới, cùng thư mục.
    expect(await cache().get('mm:x:f1:full', fetch), bytes(100));
    expect(fetched, 1);
    expect(await cache().has('mm:x:f1:full'), isTrue);
  });

  test('nhiều nơi cùng hỏi một ảnh: chỉ tải một lần', () async {
    var fetched = 0;
    final c = cache();
    Future<Uint8List> fetch() async {
      fetched++;
      await Future.delayed(const Duration(milliseconds: 30));
      return bytes(10);
    }

    await Future.wait([for (var i = 0; i < 5; i++) c.get('k', fetch)]);
    expect(fetched, 1);
  });

  test('tải lỗi thì không lưu, lần sau tải lại', () async {
    final c = cache();
    var n = 0;
    await expectLater(c.get('k', () async {
      n++;
      throw Exception('mạng lỗi');
    }), throwsException);
    expect(await c.get('k', () async {
      n++;
      return bytes(5);
    }), bytes(5));
    expect(n, 2);
  });

  test('quá giới hạn: xoá ảnh lâu chưa dùng nhất', () async {
    final c = cache(max: 1000);
    for (final k in ['a', 'b']) {
      await c.get(k, () async => bytes(400));
      await c.flush();
    }
    // Dùng lại a: giờ b là ảnh lâu chưa dùng nhất.
    await c.get('a', () async => bytes(400));
    await c.flush();
    await c.get('c', () async => bytes(400));
    await c.flush();
    expect(await c.has('b'), isFalse);
    expect(await c.has('a'), isTrue);
    expect(await c.has('c'), isTrue);
    final total = tmp.listSync().whereType<File>().fold<int>(0, (s, f) => s + f.lengthSync());
    expect(total, lessThanOrEqualTo(1000));
  });

  test('khoá ổn định: cùng khoá là cùng một ảnh (không phụ thuộc vé / địa chỉ)', () {
    final a = DiskCachedImage('mm:x:f1:full', () async => bytes(1));
    final b = DiskCachedImage.network('mm:x:f1:full', 'https://x.test/f1?t=abc', headers: {'Authorization': 'Bearer 1'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(chatImageKey('f1', 'thumb'), endsWith(':f1:thumb'));
  });

  testWidgets('mở ảnh: tải sẵn mọi ảnh còn lại của tin, mở lại không tải nữa', (t) async {
    late Uint8List png;
    await t.runAsync(() async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.blue);
      final img = await rec.endRecording().toImage(8, 8);
      png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    });
    final c = cache();
    final fetched = <String, int>{};
    final images = [
      for (var i = 0; i < 6; i++)
        ChatImage(
          aspect: 1,
          image: DiskCachedImage('t:img$i', () async {
            fetched['img$i'] = (fetched['img$i'] ?? 0) + 1;
            return png;
          }, cache: c),
        ),
    ];
    final post = MmPost({'id': 'p', 'channel_id': 'c', 'user_id': 'me', 'message': '', 'create_at': 0});
    final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'ba'});
    late BuildContext ctx;
    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      }))),
    ));
    showGallery(ctx, post, images, 2);
    await loadAll(t, c, () => fetched.length == 6);
    expect(fetched.keys.toSet(), {for (var i = 0; i < 6; i++) 'img$i'}, reason: 'mọi ảnh của tin đã được tải sẵn');
    expect(fetched.values.every((n) => n == 1), isTrue, reason: 'mỗi ảnh chỉ tải một lần');
    // Mở lại (bộ nhớ ảnh trong RAM đã xoá như sau khi mở lại app): đọc từ đĩa, không tải nữa.
    imageCache.clear();
    Navigator.of(ctx, rootNavigator: true).pop();
    await t.pump(const Duration(milliseconds: 500));
    showGallery(ctx, post, images, 0);
    await loadAll(t, c, () => false, rounds: 30);
    expect(fetched.values.every((n) => n == 1), isTrue, reason: '$fetched');
  });
}
