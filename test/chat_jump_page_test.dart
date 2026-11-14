// Khung chat thật với tin giả: cuộn lên hiện nút lịch + nút tua xuống; tua tới tin neo không xô lệch khi tin mới hơn đổ vào.
// Ảnh xem trước (chạy tay): CL_OUT=<thư mục> flutter test test/chat_jump_page_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/chat_page.dart';
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
  // Theme trên Linux dùng 'Noto Sans': nạp tạm Roboto dưới tên đó cho ảnh xem trước.
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

const _hour = 3600 * 1000;
final _start = DateTime(2026, 11, 1, 8).millisecondsSinceEpoch;
const _lines = ['Chào cả nhà', 'Ok em', 'Đã gửi báo giá nhé', 'Chiều nay họp lúc 3h', 'Nhận được rồi ạ', 'Cảm ơn'];

AppState _app(int n) {
  final app = AppState('t')..me = MmUser({'id': 'me', 'username': 'an', 'first_name': 'An'});
  for (final (id, name) in [('me', 'An'), ('u2', 'Bình')]) {
    app.users[id] = MmUser({'id': id, 'username': name, 'first_name': name});
  }
  app.channels['c'] = MmChannel({'id': 'c', 'type': 'O', 'display_name': 'Nhóm dự án', 'create_at': _start - 10 * _hour});
  app.debugPutPosts('c', [
    for (var i = n - 1; i >= 0; i--)
      MmPost({'id': 'p$i', 'channel_id': 'c', 'user_id': i.isEven ? 'u2' : 'me', 'message': _lines[i % _lines.length], 'create_at': _start + i * 3 * _hour}),
  ]);
  app.hasMore['c'] = false;
  return app;
}

Widget _wrap(AppState app, Brightness b, Key key) => ChangeNotifierProvider<AppState>.value(
      value: app,
      // Bọc cả MaterialApp để ảnh chụp có cả hộp chọn ngày (route nổi).
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const ChatPage(channelId: 'c'),
        ),
      ),
    );

void main() {
  testWidgets('cuộn lên: hiện nút lịch bên trái + nút tua xuống', (t) async {
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = _app(80);
    await t.pumpWidget(_wrap(app, Brightness.light, GlobalKey()));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('chat-jump-date')), findsNothing);
    await t.drag(find.byType(CustomScrollView), const Offset(0, 1500));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('chat-jump-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-jump-down')), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  // Lịch sử dài: 1000 tin cách nhau 3 giờ, tin mới nhất 30/4 21:00; máy chỉ có sẵn 120 tin mới nhất (từ khoảng 16/4).
  final newest = DateTime(2026, 4, 30, 21).millisecondsSinceEpoch;
  final all = [
    for (var i = 999; i >= 0; i--)
      MmPost({'id': 'p$i', 'channel_id': 'c', 'user_id': i.isEven ? 'u2' : 'me', 'message': '${_lines[i % _lines.length]} #$i', 'create_at': newest - (999 - i) * 3 * _hour}),
  ];

  AppState longApp() {
    final api = _FakeApi(all);
    final app = AppState('t', api: api)..me = MmUser({'id': 'me', 'username': 'an', 'first_name': 'An'});
    for (final (id, name) in [('me', 'An'), ('u2', 'Bình')]) {
      app.users[id] = MmUser({'id': id, 'username': name, 'first_name': name});
    }
    app.channels['c'] = MmChannel({'id': 'c', 'type': 'O', 'display_name': 'Nhóm dự án', 'create_at': all.last.createAt - _hour});
    app.debugPutPosts('c', all.sublist(0, 120));
    app.hasMore['c'] = true;
    return app;
  }

  double topOf(WidgetTester t, String text) => t.getTopLeft(find.textContaining(text)).dy;

  Future<void> pickDay(WidgetTester t, String day) async {
    await t.tap(find.byKey(const ValueKey('chat-jump-date')));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text(day)));
    await t.tap(find.text('Tới ngày này'));
    await t.pumpAndSettle();
  }

  testWidgets('chọn ngày chưa tải: tải cửa sổ tin, tin đầu ngày ở đầu khung, tải dần tin mới hơn không xô lệch, nối về tin mới nhất', (t) async {
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = longApp();
    final api = app.api as _FakeApi;
    await t.pumpWidget(_wrap(app, Brightness.light, GlobalKey()));
    await t.pumpAndSettle();
    await t.drag(find.byType(CustomScrollView), const Offset(0, 1500));
    await t.pumpAndSettle();
    api.calls.clear();
    await pickDay(t, '3');

    final since = DateTime(2026, 4, 3).millisecondsSinceEpoch;
    final target = all.lastWhere((p) => p.createAt >= since);
    expect(app.inWindow('c'), isTrue);
    expect(find.textContaining('#${target.id.substring(1)}'), findsOneWidget);
    // Tin đầu ngày nằm ở nửa trên khung (ngay dưới phần đầu nổi); tin ngày trước đó ở trên nữa không hiện quá nhiều.
    final y = topOf(t, '#${target.id.substring(1)}');
    expect(y, lessThan(860 / 2));
    // Tìm theo trang: vài lần gọi chứ không tải hết 1000 tin.
    expect(api.calls.where((c) => c.startsWith('page=')).length, lessThanOrEqualTo(8));
    expect(find.byKey(const ValueKey('chat-jump-down')), findsOneWidget);

    // Cuộn xuống (về phía tin mới hơn) nhiều lần: tin mới hơn đổ vào bên dưới, chỗ đang xem không nhảy.
    // Mốc theo dõi: một tin đang hiện ở giữa khung (số thứ tự tin trong nội dung).
    String? visibleProbe() {
      for (final e in find.textContaining(RegExp(r'#\d+$')).evaluate()) {
        final w = e.widget;
        final s = w is RichText ? w.text.toPlainText() : (w as dynamic).data as String?;
        final box = e.renderObject as RenderBox?;
        if (s == null || box == null || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y > 250 && y < 500) return RegExp(r'#\d+$').stringMatch(s);
      }
      return null;
    }

    var checks = 0, newerLoads = 0;
    for (var n = 0; n < 300 && app.inWindow('c'); n++) {
      final probe = visibleProbe();
      final y0 = probe == null ? null : topOf(t, probe);
      final calls0 = api.calls.length;
      await t.drag(find.byType(CustomScrollView), const Offset(0, -150));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      if (api.calls.length > calls0) newerLoads++;
      if (probe != null && y0 != null && find.textContaining(probe).evaluate().length == 1) {
        // Chỉ dịch đúng quãng kéo, không bị đẩy thêm vì tin mới hơn được chèn vào.
        expect((y0 - topOf(t, probe) - 150).abs(), lessThan(40), reason: probe);
        checks++;
      }
    }
    expect(checks, greaterThan(20));
    expect(newerLoads, greaterThanOrEqualTo(1));
    await t.pumpAndSettle();
    expect(app.inWindow('c'), isFalse, reason: 'đã nối về danh sách tin mới nhất');

    // Bấm nút tua xuống: về tin mới nhất.
    await t.tap(find.byKey(const ValueKey('chat-jump-down')));
    await t.pumpAndSettle();
    expect(find.textContaining('#999'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-jump-date')), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('chọn ngày không có tin: báo và đứng yên', (t) async {
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = _app(80);
    await t.pumpWidget(_wrap(app, Brightness.light, GlobalKey()));
    await t.pumpAndSettle();
    await t.drag(find.byType(CustomScrollView), const Offset(0, 1500));
    await t.pumpAndSettle();
    // Tin cuối cùng của _app(80) là 10/11; hôm nay (theo đồng hồ máy) là sau đó nên chọn được nhưng không có tin.
    final today = DateTime.now();
    final last = DateTime.fromMillisecondsSinceEpoch(_start + 79 * 3 * _hour);
    if (DateTime(today.year, today.month, today.day).isAfter(DateTime(last.year, last.month, last.day)) && today.month == 11) {
      await pickDay(t, '${today.day}');
      expect(find.textContaining('Không có tin nhắn nào từ ngày'), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ảnh xem trước tua tới ngày', (t) async {
    final out = Platform.environment['CL_OUT'];
    if (out == null) return;
    await t.runAsync(_fonts);
    Future<void> save(GlobalKey key, String name) => t.runAsync(() async {
          final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        });
    for (final (b, size, name) in [
      (Brightness.light, const Size(420, 860), 'phone-light'),
      (Brightness.dark, const Size(420, 860), 'phone-dark'),
      (Brightness.light, const Size(1100, 760), 'desktop-light'),
    ]) {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      final key = GlobalKey();
      final app = longApp();
      await t.pumpWidget(_wrap(app, b, key));
      await t.pumpAndSettle();
      await t.drag(find.byType(CustomScrollView), const Offset(0, 1500));
      await t.pumpAndSettle();
      await save(key, '$name-1-scrolled');
      await t.tap(find.byKey(const ValueKey('chat-jump-date')));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('3')));
      await t.pumpAndSettle();
      await save(key, '$name-2-picker');
      await t.tap(find.text('Tới ngày này'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      await save(key, '$name-3-jumped');
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox.shrink());
    }
    t.view.reset();
  });
}

/// Máy chủ giả: lịch sử dài [n] tin (mới nhất trước), trả tin theo page / before / after như Mattermost.
class _FakeApi extends MmApi {
  final List<MmPost> all;
  final calls = <String>[];
  _FakeApi(this.all) : super('t');

  @override
  Future<List<MmPost>> posts(String channelId, {String? before, String? after, int? since, int? page, int perPage = 60}) async {
    calls.add('page=$page before=$before after=$after');
    if (before != null) {
      final i = all.indexWhere((p) => p.id == before) + 1;
      return all.sublist(i, (i + perPage).clamp(0, all.length));
    }
    if (after != null) {
      final i = all.indexWhere((p) => p.id == after);
      return all.sublist((i - perPage).clamp(0, i), i);
    }
    final from = (page ?? 0) * perPage;
    return from >= all.length ? [] : all.sublist(from, (from + perPage).clamp(0, all.length));
  }

  @override
  Future<dynamic> get(String p, [Map<String, String>? q]) async => throw Exception('offline');
}
