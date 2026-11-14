// Trang Hình ảnh / Tệp tin / Liên kết của cuộc trò chuyện: chia theo ngày (tiêu đề dính), nút lịch góc dưới phải tua tới ngày.
// Ảnh xem trước (chạy tay): MD_OUT=<thư mục> flutter test test/channel_media_days_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/mm_api.dart';
import 'package:flygo_chat/data/image_disk_cache.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/ui/chat_info_page.dart';
import 'package:flygo_chat/ui/common.dart';
import 'package:flygo_chat/ui/day_sections.dart';
import 'package:flygo_chat/ui/theme.dart';
import 'package:provider/provider.dart';

import 'support/fake_photos.dart';

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

  const roboto = ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf'];
  await load('Roboto', roboto);
  await load('Noto Sans', roboto);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// Máy chủ giả: tin mới nhất trước, phân trang theo before / per_page như Mattermost; có đánh dấu kênh.
class _FakeApi extends MmApi {
  final List<MmPost> all;
  _FakeApi(this.all) : super('t');

  @override
  Future<List<MmPost>> posts(String channelId, {String? before, String? after, int? since, int? page, int perPage = 60}) async {
    final i = before == null ? 0 : all.indexWhere((p) => p.id == before) + 1;
    return all.sublist(i, (i + perPage).clamp(0, all.length));
  }

  @override
  Future<dynamic> get(String p, [Map<String, String>? q]) async {
    if (p.endsWith('/bookmarks')) {
      return [
        {'display_name': 'Bảng giá 2026', 'link_url': 'https://example.com/bang-gia'},
        {'display_name': 'Hướng dẫn lắp đặt', 'link_url': 'https://example.com/huong-dan'},
      ];
    }
    throw Exception('offline');
  }
}

final _today = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();
DateTime _daysAgo(int d, [int hour = 9]) => _today.subtract(Duration(days: d)).add(Duration(hours: hour));

int _seq = 0;
MmPost _post(DateTime at, {String message = '', List<Map<String, dynamic>> files = const [], String user = 'u2'}) => MmPost({
      'id': 'p${_seq++}',
      'channel_id': 'c',
      'user_id': user,
      'message': message,
      'create_at': at.millisecondsSinceEpoch,
      if (files.isNotEmpty) 'metadata': {'files': files},
    });
Map<String, dynamic> _img(String id) => {'id': id, 'name': '$id.jpg', 'mime_type': 'image/jpeg', 'size': 240000};
Map<String, dynamic> _file(String id, String name, int size, [String mime = 'application/pdf']) =>
    {'id': id, 'name': name, 'mime_type': mime, 'size': size};

/// Ngày có ảnh / tệp / liên kết: hôm nay, hôm qua, 3, 4, 8, 12, 20, 40 ngày trước (không có 6 ngày trước).
List<MmPost> _history({int filler = 0}) {
  const days = [0, 1, 3, 4, 8, 12, 20, 40];
  const counts = [2, 5, 3, 7, 4, 6, 3, 8];
  const files = [
    ('Báo giá thang máy tháng 11.pdf', 482000, 'application/pdf'),
    ('Hợp đồng lắp đặt - bản ký.docx', 96000, 'application/msword'),
    ('Bảng kê vật tư.xlsx', 41000, 'application/vnd.ms-excel'),
    ('Video nghiệm thu.mp4', 18200000, 'video/mp4'),
  ];
  final out = <MmPost>[];
  for (final (k, d) in days.indexed) {
    out.add(_post(_daysAgo(d, 17), message: 'Tài liệu tham khảo: https://example.com/tai-lieu-$d', user: k.isEven ? 'u2' : 'me'));
    if (k.isOdd) out.add(_post(_daysAgo(d, 16), message: 'Xem bản vẽ ở https://example.com/ban-ve/$d nhé'));
    for (var j = 0; j <= k % 3; j++) {
      final (name, size, mime) = files[(k + j) % files.length];
      out.add(_post(_daysAgo(d, 14 - j), files: [_file('f$d-$j', name, size, mime)], user: j.isEven ? 'u2' : 'me'));
    }
    out.add(_post(_daysAgo(d, 10), files: [for (var i = 0; i < counts[k]; i++) _img('i$d-$i')], user: k.isEven ? 'me' : 'u2'));
  }
  out.sort((a, b) => b.createAt.compareTo(a.createAt));
  // Tin chữ mới hơn (đẩy các tin có ảnh sang trang cũ hơn phần tải lần đầu).
  return [for (var i = 0; i < filler; i++) _post(_today.add(Duration(minutes: 8 * 60 + i % 600)), message: 'Ok $i'), ...out];
}

AppState _app(List<MmPost> all) {
  final app = AppState('t', api: _FakeApi(all))..me = MmUser({'id': 'me', 'username': 'an', 'first_name': 'An'});
  for (final (id, name) in [('me', 'An'), ('u2', 'Bình')]) {
    app.users[id] = MmUser({'id': id, 'username': name, 'first_name': name});
  }
  app.channels['c'] = MmChannel({'id': 'c', 'type': 'O', 'display_name': 'Nhóm dự án', 'create_at': _daysAgo(90).millisecondsSinceEpoch});
  return app;
}

Widget _wrap(AppState app, String kind, {Brightness b = Brightness.light, bool vi = false, Key? key}) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(b),
          locale: vi ? const Locale('vi') : null,
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ChannelMediaPage(channelId: 'c', kind: kind),
        ),
      ),
    );

Future<void> _pickDate(WidgetTester t, DateTime d) async {
  await t.tap(find.byKey(const ValueKey('day-sections-date')));
  await t.pumpAndSettle();
  final back = (_today.year * 12 + _today.month) - (d.year * 12 + d.month);
  for (var i = 0; i < back; i++) {
    await t.tap(find.byTooltip('Previous month'));
    await t.pumpAndSettle();
  }
  await t.tap(find.descendant(of: find.byType(CalendarDatePicker), matching: find.text('${d.day}')));
  await t.tap(find.text('Tới ngày này'));
  await t.pumpAndSettle();
}

/// Mép trên vùng danh sách (dưới thanh tiêu đề trang).
double _listTop(WidgetTester t) => t.getTopLeft(find.byType(CustomScrollView)).dy;

/// Tiêu đề [f] nằm ở mép trên danh sách, hoặc danh sách đã cuộn tới cuối (phần còn lại ngắn hơn khung).
void _expectAtTop(WidgetTester t, Finder f) {
  expect(f, findsOneWidget);
  final pos = t.state<ScrollableState>(find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first).position;
  final atEnd = pos.pixels >= pos.maxScrollExtent - .5;
  expect((t.getTopLeft(f).dy - _listTop(t)).abs() < 14 || atEnd, isTrue);
}

void main() {
  test('groupByDay / sectionAtOrBefore / dayHeaderLabel', () {
    final g = groupByDay([DateTime(2026, 11, 10, 9), DateTime(2026, 11, 12, 8), DateTime(2026, 11, 10, 7)], (d) => d.millisecondsSinceEpoch);
    expect(g.map((e) => e.$1), [DateTime(2026, 11, 12), DateTime(2026, 11, 10)]);
    expect(g.last.$2, [DateTime(2026, 11, 10, 9), DateTime(2026, 11, 10, 7)]);
    final days = [DateTime(2026, 11, 12), DateTime(2026, 11, 10), DateTime(2026, 11, 3)];
    expect(sectionAtOrBefore(days, DateTime(2026, 11, 10, 15)), 1);
    expect(sectionAtOrBefore(days, DateTime(2026, 11, 11)), 1, reason: 'không có ngày 11: ngày gần nhất trước đó');
    expect(sectionAtOrBefore(days, DateTime(2026, 11, 14)), 0);
    expect(sectionAtOrBefore(days, DateTime(2026, 11, 1)), isNull);
    final now = DateTime(2026, 11, 14, 9);
    expect(dayHeaderLabel(DateTime(2026, 11, 14), now: now), 'Hôm nay, 14/11/2026');
    expect(dayHeaderLabel(DateTime(2026, 11, 13), now: now), 'Hôm qua, 13/11/2026');
    expect(dayHeaderLabel(DateTime(2026, 11, 10), now: now), 'Thứ Ba, 10/11/2026');
    expect(dayHeaderLabel(DateTime(2025, 3, 2), now: now), 'Chủ Nhật, 02/03/2025');
  });

  for (final kind in ['images', 'files', 'links']) {
    testWidgets('$kind: tiêu đề theo ngày, nút lịch tua tới ngày / ngày gần nhất trước đó', (t) async {
      t.view.physicalSize = const Size(420, 860);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_wrap(_app(_history()), kind));
      await t.pumpAndSettle();
      expect(find.text(dayHeaderLabel(_today)), findsOneWidget);
      expect(find.byKey(const ValueKey('day-sections-date')), findsOneWidget);
      if (kind == 'links') expect(find.text('Bảng giá 2026'), findsOneWidget);

      // Đúng ngày có mục: tiêu đề ngày đó ở mép trên danh sách, không báo gì.
      final d12 = _daysAgo(12);
      await _pickDate(t, d12);
      final h12 = find.text(dayHeaderLabel(DateTime(d12.year, d12.month, d12.day)));
      _expectAtTop(t, h12);
      expect(find.textContaining('đang hiện ngày gần nhất'), findsNothing);

      // Ngày không có mục (6 ngày trước): tới ngày gần nhất trước đó (8 ngày trước) và báo.
      final d8 = _daysAgo(8);
      await _pickDate(t, _daysAgo(6));
      final h8 = find.text(dayHeaderLabel(DateTime(d8.year, d8.month, d8.day)));
      _expectAtTop(t, h8);
      expect(find.textContaining('đang hiện ngày gần nhất'), findsOneWidget);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });
  }

  testWidgets('ngày cũ hơn phần đã tải: tải thêm trang cũ hơn rồi tua tới', (t) async {
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // 1200 tin chữ hôm nay: lần đầu chỉ quét 1000 tin, chưa tới các tin có ảnh.
    await t.pumpWidget(_wrap(_app(_history(filler: 1200)), 'images'));
    await t.pumpAndSettle();
    final d20 = _daysAgo(20);
    await _pickDate(t, d20);
    expect(find.text(dayHeaderLabel(DateTime(d20.year, d20.month, d20.day))), findsOneWidget);
  });

  testWidgets('ảnh xem trước', (t) async {
    final out = Platform.environment['MD_OUT'];
    if (out == null) return;
    await t.runAsync(_fonts);
    await useFakePhotos(t);
    // Bộ đệm ảnh ra thư mục tạm (test không có thư mục cache của app).
    final tmp = (await t.runAsync(() => Directory.systemTemp.createTemp('md')))!;
    ImageDiskCache.instance = ImageDiskCache(dir: () async => tmp);
    debugDisableShadows = false;
    for (final (kind, b) in [('images', Brightness.light), ('images', Brightness.dark), ('files', Brightness.light), ('links', Brightness.light)]) {
      t.view.physicalSize = const Size(420, 860);
      t.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await t.pumpWidget(_wrap(_app(_history()), kind, b: b, vi: true, key: key));
      for (var i = 0; i < 12; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
        await t.pump(const Duration(milliseconds: 100));
      }
      // Cuộn một chút để thấy tiêu đề ngày dính ở trên.
      await t.drag(find.byType(CustomScrollView), const Offset(0, -120));
      await t.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await t.runAsync(() => Future.delayed(const Duration(milliseconds: 80)));
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        await File('$out/media-$kind-${b.name}.png').writeAsBytes(data!.buffer.asUint8List());
      });
      await t.pumpWidget(const SizedBox.shrink());
    }
    debugDisableShadows = true;
    t.view.reset();
  });
}
