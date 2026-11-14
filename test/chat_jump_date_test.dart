import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/data/models.dart';
import 'package:flygo_chat/state/app_state.dart';
import 'package:flygo_chat/state/date_jump.dart';
import 'package:flygo_chat/ui/chat_jump.dart';
import 'package:flygo_chat/ui/common.dart';
import 'package:flygo_chat/ui/theme.dart';

const _hour = 3600 * 1000;

/// [n] tin cách nhau 1 giờ, tin cũ nhất ở [start]; trả về mới nhất trước (như máy chủ).
List<MmPost> _history(int n, int start) =>
    [for (var i = n - 1; i >= 0; i--) MmPost({'id': 'p$i', 'channel_id': 'c', 'user_id': 'u', 'create_at': start + i * _hour})];

void main() {
  group('findFirstPostSince', () {
    final start = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    final all = _history(1000, start);
    late List<int> calls;
    Future<List<MmPost>> fetch(int page, {int per = 60}) async {
      calls.add(page);
      final from = page * per;
      return from >= all.length ? [] : all.sublist(from, (from + per).clamp(0, all.length));
    }

    setUp(() => calls = []);

    test('tìm đúng tin cũ nhất từ mốc, ít lần gọi', () async {
      // Tin p300 tạo lúc start + 300h; mốc nằm giữa p299 và p300.
      final since = start + 299 * _hour + 1;
      final r = await findFirstPostSince(since, fetch);
      expect(r!.targetId, 'p300');
      expect(r.posts.map((p) => p.id), contains('p300'));
      expect(r.posts.map((p) => p.id), contains('p299'));
      expect(r.hasOlder, isTrue);
      expect(r.hasNewer, isTrue);
      expect(calls.toSet().length, lessThanOrEqualTo(10));
    });

    test('mốc đúng bằng thời điểm tạo tin', () async {
      final r = await findFirstPostSince(start + 500 * _hour, fetch);
      expect(r!.targetId, 'p500');
    });

    test('tin nằm ở mép trang', () async {
      // Trang 0 = p999..p940, trang 1 = p939..p880: p940 là tin cuối trang 0.
      final r = await findFirstPostSince(start + 940 * _hour, fetch);
      expect(r!.targetId, 'p940');
      final r2 = await findFirstPostSince(start + 939 * _hour, fetch);
      expect(r2!.targetId, 'p939');
    });

    test('mốc trước tin đầu tiên: tin đầu tiên, hết tin cũ hơn', () async {
      final r = await findFirstPostSince(start - 10 * _hour, fetch);
      expect(r!.targetId, 'p0');
      expect(r.hasOlder, isFalse);
      expect(r.hasNewer, isTrue);
    });

    test('mốc trong trang mới nhất: cửa sổ đã là đoạn cuối', () async {
      final r = await findFirstPostSince(start + 990 * _hour, fetch);
      expect(r!.targetId, 'p990');
      expect(r.hasNewer, isFalse);
      expect(calls, [0]);
    });

    test('không có tin từ mốc trở đi', () async {
      expect(await findFirstPostSince(start + 1000 * _hour, fetch), isNull);
      calls = [];
      expect(await findFirstPostSince(start, (p) async => <MmPost>[]), isNull);
    });

    test('startOfDayMs: 00:00 giờ máy', () {
      expect(startOfDayMs(DateTime(2026, 3, 5, 17, 42)), DateTime(2026, 3, 5).millisecondsSinceEpoch);
    });
  });

  group('AppState.jumpToDate (tin đã tải sẵn)', () {
    final start = DateTime(2026, 2, 1).millisecondsSinceEpoch;

    test('ngày nằm trong đoạn đã tải: dùng luôn, không cửa sổ', () async {
      final app = AppState('t');
      app.debugPutPosts('c', _history(100, start));
      app.hasMore['c'] = true;
      expect(await app.jumpToDate('c', DateTime(2026, 2, 3)), isTrue);
      expect(app.inWindow('c'), isFalse);
      final since = startOfDayMs(DateTime(2026, 2, 3));
      expect(app.visiblePostsOf('c').where((p) => p.createAt >= since).last.id, 'p48');
    });

    test('ngày sau tin mới nhất: không có tin', () async {
      final app = AppState('t');
      app.debugPutPosts('c', _history(10, start));
      expect(await app.jumpToDate('c', DateTime(2026, 3, 1)), isFalse);
    });

    test('đã tải hết lịch sử, ngày trước tin đầu tiên: tới tin đầu tiên', () async {
      final app = AppState('t');
      app.debugPutPosts('c', _history(10, start));
      app.hasMore['c'] = false;
      expect(await app.jumpToDate('c', DateTime(2025, 12, 1)), isTrue);
      expect(app.inWindow('c'), isFalse);
    });
  });

  group('nút khi cuộn lên', () {
    test('chatScrolledUp', () {
      expect(chatScrolledUp(pixels: 0, minExtent: 0), isFalse);
      expect(chatScrolledUp(pixels: 601, minExtent: 0), isTrue);
      // Có tin neo (tua tới ngày): đáy ở vị trí âm.
      expect(chatScrolledUp(pixels: 0, minExtent: -2000), isTrue);
      expect(chatScrolledUp(pixels: -1990, minExtent: -2000), isFalse);
      expect(chatScrolledUp(pixels: 0, minExtent: 0, inWindow: true), isTrue);
    });

    Future<void> pump(WidgetTester t, bool visible, {VoidCallback? onDate, VoidCallback? onDown}) => t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Stack(children: [
              Positioned(
                right: 14,
                bottom: 12,
                child: ChatJumpButtons(visible: visible, onPickDate: onDate ?? () {}, onDown: onDown ?? () {}),
              ),
            ]),
          ),
        ));

    testWidgets('ẩn khi ở đáy, hiện cả hai nút cạnh nhau ở góc dưới bên phải khi cuộn lên', (t) async {
      await pump(t, false);
      expect(find.byKey(const ValueKey('chat-jump-date')), findsNothing);
      expect(find.byKey(const ValueKey('chat-jump-down')), findsNothing);
      var date = 0, down = 0;
      await pump(t, true, onDate: () => date++, onDown: () => down++);
      final l = t.getCenter(find.byKey(const ValueKey('chat-jump-date')));
      final r = t.getCenter(find.byKey(const ValueKey('chat-jump-down')));
      expect(l.dx, lessThan(r.dx));
      expect(l.dy, r.dy);
      // Sát nhau (44 px + khoảng 10 px), nút tua xuống sát mép phải.
      expect(r.dx - l.dx, 54);
      expect(t.getTopRight(find.byKey(const ValueKey('chat-jump-down'))).dx, t.view.physicalSize.width / t.view.devicePixelRatio - 14);
      await t.tap(find.byKey(const ValueKey('chat-jump-date')));
      await t.tap(find.byKey(const ValueKey('chat-jump-down')));
      expect((date, down), (1, 1));
    });

    testWidgets('hộp chọn ngày: không chọn được ngày tương lai / trước khi tạo cuộc trò chuyện', (t) async {
      DateTime? picked;
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async => picked = await pickJumpDate(ctx,
                createdAt: DateTime(2026, 11, 10).millisecondsSinceEpoch, now: DateTime(2026, 11, 14, 9)),
            child: const Text('mở'),
          ),
        ),
      ));
      await t.tap(find.text('mở'));
      await t.pumpAndSettle();
      final picker = t.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
      expect(picker.firstDate, DateTime(2026, 11, 10));
      expect(picker.lastDate, DateTime(2026, 11, 14));
      await t.tap(find.text('12'));
      await t.tap(find.text('Tới ngày này'));
      await t.pumpAndSettle();
      expect(picked, DateTime(2026, 11, 12));
    });
  });

  test('nhãn ngày giữa các tin: kèm ngày sau Hôm nay / Hôm qua / thứ', () {
    final now = DateTime(2026, 11, 14, 9); // Thứ Bảy
    expect(daySeparatorLabel(DateTime(2026, 11, 14, 8), now: now), 'Hôm nay, 14/11');
    expect(daySeparatorLabel(DateTime(2026, 11, 13, 23), now: now), 'Hôm qua, 13/11');
    expect(daySeparatorLabel(DateTime(2026, 11, 10, 7), now: now), 'Thứ Ba, 10/11');
    expect(daySeparatorLabel(DateTime(2026, 11, 8), now: now), 'Chủ Nhật, 08/11');
    expect(daySeparatorLabel(DateTime(2026, 11, 7), now: now), '07/11/2026');
    // Gần đây nhưng khác năm: ghi cả năm.
    expect(daySeparatorLabel(DateTime(2026, 12, 30), now: DateTime(2027, 1, 2)), 'Thứ Tư, 30/12/2026');
  });
}
