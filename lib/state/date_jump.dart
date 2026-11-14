import '../data/models.dart';

/// Kết quả tìm tin đầu tiên từ một mốc thời gian: [targetId] là tin cũ nhất có create_at >= mốc,
/// [posts] là cửa sổ tin quanh nó (mới nhất trước), [hasOlder] / [hasNewer]: còn tin cũ hơn / mới hơn cửa sổ.
class DateJumpResult {
  final String targetId;
  final List<MmPost> posts;
  final bool hasOlder;
  final bool hasNewer;
  const DateJumpResult(this.targetId, this.posts, {required this.hasOlder, required this.hasNewer});
}

/// Tìm tin cũ nhất có create_at >= [since] (ms) theo các trang tin của kênh: trang 0 mới nhất,
/// mỗi trang [perPage] tin, mới nhất trước (GET /channels/{id}/posts?page=&per_page=).
/// Dò trang theo cấp số nhân rồi chia đôi: chỉ cần khoảng 2·log2(số trang) lần gọi, không phải tải hết lịch sử.
/// Không có tin nào từ mốc đó trở đi: trả về null.
Future<DateJumpResult?> findFirstPostSince(int since, Future<List<MmPost>> Function(int page) fetchPage,
    {int perPage = 60}) async {
  final cache = <int, List<MmPost>>{};
  Future<List<MmPost>> page(int p) async => cache[p] ??= await fetchPage(p);
  // Trang đã chạm tới trước mốc (hoặc hết lịch sử).
  bool reaches(List<MmPost> l) => l.isEmpty || l.last.createAt < since;

  final first = await page(0);
  if (first.isEmpty || first.first.createAt < since) return null;
  var lo = -1, hi = 0;
  if (!reaches(first)) {
    lo = 0;
    hi = 1;
    while (!reaches(await page(hi))) {
      lo = hi;
      hi *= 2;
    }
    // Trang lo chưa chạm mốc, trang hi đã chạm: thu hẹp lại còn hai trang liền nhau.
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (reaches(await page(mid))) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
  }
  final h = await page(hi);
  final inHi = h.lastWhere((p) => p.createAt >= since, orElse: () => _none);
  final target = !identical(inHi, _none) ? inHi : (await page(lo)).last;
  final posts = [if (lo >= 0) ...await page(lo), ...h];
  return DateJumpResult(target.id, posts, hasOlder: h.length >= perPage, hasNewer: lo > 0);
}

final _none = MmPost(const {'id': ''});

/// Mốc 00:00 giờ máy của ngày [d].
int startOfDayMs(DateTime d) => DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
