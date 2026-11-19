// Ảnh trong chat (Sếp, bản 510): ảnh gửi đi đôi khi chỉ còn một vạch đen; sửa ảnh xong có nút "Xong".
// Ảnh xem trước (chạy tay): IMG_OUT=<thư mục> flutter test test/chat_image_fixes_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/data/local_store.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/image_edit.dart';
import 'package:flygo_chat/ui/media_picker.dart';
import 'package:flygo_chat/ui/media_view.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

class _FakeApi extends MmApi {
  _FakeApi() : super('t');
  final asked = <String>[];
  @override
  Future<dynamic> get(String p, [Map<String, String>? q]) async {
    asked.add(p);
    if (p == '/posts/p1/files/info') {
      return [
        {'id': 'f1', 'name': 'a.jpg', 'mime_type': 'image/jpeg', 'extension': 'jpg', 'width': 1200, 'height': 900, 'size': 1000}
      ];
    }
    throw ApiException(404, 'not found');
  }
}

Map<String, dynamic> _file(String id) => {'id': id, 'name': 'a.jpg', 'mime_type': 'image/jpeg', 'extension': 'jpg', 'width': 1200, 'height': 900};

final _out = Platform.environment['IMG_OUT'];
final _key = GlobalKey();

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

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> _save(WidgetTester t, String name) async {
  final out = _out;
  if (out == null) return;
  await t.runAsync(() async {
    await Directory(out).create(recursive: true);
    final img = await (_key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() async {
    if (_out != null) await _fonts();
  });

  test('tin sửa props về thiếu metadata.files: giữ ảnh của bản cũ, không thành bong bóng trống', () async {
    final app = AppState('t', api: _FakeApi());
    app.debugSetStore(await LocalStore.memory('img-${DateTime.now().microsecondsSinceEpoch}'));
    final full = MmPost({'id': 'p1', 'channel_id': 'c', 'user_id': 'u', 'create_at': 1, 'message': '', 'file_ids': ['f1'], 'metadata': {'files': [_file('f1')]}});
    app.debugPutPosts('c', [full]);
    // post_edited (plugin ghi props) không kèm metadata.files.
    app.debugMerge('c', [MmPost({'id': 'p1', 'channel_id': 'c', 'user_id': 'u', 'create_at': 1, 'message': '', 'file_ids': ['f1'], 'metadata': {}, 'props': {'x': 1}})]);
    final p = app.postsOf('c').single;
    expect(p.files.single.id, 'f1');
    expect(p.props['x'], 1);
    expect(imagesOf(p).single.aspect, closeTo(4 / 3, 1e-9));
  });

  test('tin có tệp mà chưa có thông tin tệp: hỏi lại máy chủ rồi gắn vào tin', () async {
    final api = _FakeApi();
    final app = AppState('t', api: api);
    app.debugSetStore(await LocalStore.memory('img2-${DateTime.now().microsecondsSinceEpoch}'));
    app.debugPutPosts('c', []);
    final bare = MmPost({'id': 'p1', 'channel_id': 'c', 'user_id': 'u', 'create_at': 1, 'message': '', 'file_ids': ['f1'], 'metadata': {}});
    expect(bare.filesPending, isTrue);
    app.debugMerge('c', [bare]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(api.asked, ['/posts/p1/files/info']);
    final p = app.postsOf('c').single;
    expect(p.filesPending, isFalse);
    expect(p.files.single.width, 1200);
  });

  test('tỉ lệ ảnh hỏng (0, vô cực, NaN) dùng 4:3', () {
    expect(sanitizeAspect(0), 4 / 3);
    expect(sanitizeAspect(double.nan), 4 / 3);
    expect(sanitizeAspect(double.infinity), 4 / 3);
    expect(sanitizeAspect(null), 4 / 3);
    expect(sanitizeAspect(1.5), 1.5);
    final local = MmPost({'id': 'x', 'file_ids': [], '_local_files': [{'path': '/tmp/a.png', 'name': 'a.png', 'mime': 'image/png', 'aspect': double.nan}]});
    expect(imagesOf(local).single.aspect, 4 / 3);
  });

  testWidgets('khung chờ ảnh: cỡ 4:3, không phải vạch mảnh', (t) async {
    t.view.physicalSize = const Size(780, 600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(RepaintBoundary(
        key: _key,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(Brightness.dark), home: const Scaffold(body: Center(child: ChatMediaPlaceholder(width: 240))))));
    expect(t.getSize(find.byKey(const ValueKey('chat-media-placeholder'))), const Size(240, 180));
    await _save(t, 'chat-image-placeholder-dark');
  });

  group('bộ chọn ảnh: sửa xong có nút Xong', () {
    tearDown(() => editImageOverride = null);

    Future<(bool, String?)?> open(WidgetTester t, {required Future<void> Function() act}) async {
      (bool, String?)? got;
      t.view.physicalSize = const Size(780, 1688);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(RepaintBoundary(
        key: _key,
        child: ChangeNotifierProvider<AppState>.value(
        value: AppState('t'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.dark),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async => got = debugPreviewResult(await Navigator.of(c).push(MaterialPageRoute(builder: (_) => debugAssetPreview(File('assets/icon/background.png').absolute.path)))),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      )));
      await t.tap(find.text('mở'));
      await t.pumpAndSettle();
      await act();
      await t.pumpAndSettle();
      return got;
    }

    testWidgets('sửa → Xong: chọn ảnh đã sửa, về danh sách', (t) async {
      editImageOverride = (_, _) async => File('assets/icon/icon.png').absolute.path;
      final r = await open(t, act: () async {
        expect(find.byKey(const ValueKey('preview-done')), findsNothing);
        await t.tap(find.text('Sửa'));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('preview-done')), findsOneWidget);
        await _save(t, 'media-picker-edited-xong');
        await t.tap(find.byKey(const ValueKey('preview-done')));
      });
      expect(r, (true, File('assets/icon/icon.png').absolute.path));
    });

    testWidgets('sửa → quay lại: hỏi bỏ thay đổi, bỏ thì giữ ảnh gốc', (t) async {
      editImageOverride = (_, _) async => File('assets/icon/icon.png').absolute.path;
      final r = await open(t, act: () async {
        await t.tap(find.text('Sửa'));
        await t.pumpAndSettle();
        await t.tap(find.byIcon(Icons.arrow_back_ios_new));
        await t.pumpAndSettle();
        expect(find.text('Bỏ các thay đổi?'), findsOneWidget);
        await _save(t, 'media-picker-back-confirm');
        await t.tap(find.byKey(const ValueKey('preview-discard')));
      });
      expect(r, (false, null));
    });
  });
}
