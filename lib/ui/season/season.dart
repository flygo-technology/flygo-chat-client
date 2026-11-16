import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'season_art.dart';

/// Hình nền chat (mỗi người chọn riêng cho từng chat, preferences `flygo_wallpaper/<id kênh>`; chỉ người chọn thấy).
/// Hình nền đè lên nền của "Màu chat" (giao diện chung của kênh) nhưng không đổi màu bong bóng / chữ.
class Wallpaper {
  final String id;
  final String name;
  /// Nhóm (mục trong màn chọn): [wallpaperGroups].
  final String group;
  /// Nền tối: chữ hệ thống (ngày, "đang nhập…") trên nền dùng bảng màu tối.
  final bool dark;
  final CustomPainter Function(double t) painter;
  /// Có chuyển động (tuyết rơi, đèn nhấp nháy) — tắt khi "Hiệu ứng động" tắt / giảm chuyển động / tiết kiệm pin.
  final bool animated;
  const Wallpaper(this.id, this.name, this.group, {required this.dark, required this.painter, this.animated = true});
}

List<(String, String)> get wallpaperGroups => [
      ('giangsinh', tr('Giáng sinh')),
      ('tet', tr('Tết')),
      ('trungthu', tr('Trung thu')),
      ('coban', tr('Cơ bản')),
    ];

List<Wallpaper> get wallpapers => [
      Wallpaper('demnoel', tr('Đêm Noel'), 'giangsinh', dark: true, painter: NoelNightPainter.new),
      Wallpaper('tuyettrang', tr('Tuyết trắng'), 'giangsinh', dark: false, painter: WhiteSnowPainter.new),
    ];

Wallpaper? wallpaperById(String? id) => id == null ? null : wallpapers.where((w) => w.id == id).firstOrNull;

/// Hình nền đang chạy. [motion] = lựa chọn "Hiệu ứng động" của người dùng; ngoài ra tự dừng khi máy bật giảm chuyển động
/// (MediaQuery.disableAnimations, gồm cả tiết kiệm pin trên Android) và khi không hiện trên màn hình (TickerMode).
/// [frozenT] chỉ dùng cho ảnh xem trước.
class WallpaperView extends StatefulWidget {
  final Wallpaper wallpaper;
  final bool motion;
  final double? frozenT;
  final Widget? child;
  const WallpaperView({super.key, required this.wallpaper, this.motion = true, this.frozenT, this.child});
  @override
  State<WallpaperView> createState() => _WallpaperViewState();
}

class _WallpaperViewState extends State<WallpaperView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((e) {
    // ~30 khung/giây là đủ cho tuyết rơi chậm.
    final t = e.inMilliseconds / 1000;
    if (t - _t >= 1 / 30) setState(() => _t = t);
  });
  double _t = 0;

  bool get _run => widget.frozenT == null && widget.motion && widget.wallpaper.animated && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(WallpaperView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_run && !_ticker.isActive) _ticker.start();
    if (!_run && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: widget.wallpaper.painter(widget.frozenT ?? _t), child: widget.child ?? const SizedBox.expand()),
      );
}

/// Tin có lời chúc Giáng sinh → hiệu ứng rơi một lần.
final _xmasRe = RegExp(r'gi[aá]ng\s*sinh\s*vui\s*v[eẻ]|merry\s*(x-?mas|christmas)|\bno[eê]l\b', caseSensitive: false);
bool isXmasGreeting(String text) => _xmasRe.hasMatch(text);

/// Chủ đề mùa lễ của công ty (quản trị bật một lần; tự bật / tắt theo khung ngày).
class Season {
  final String id;
  final String name;
  /// Ngày bắt đầu / kết thúc (tháng, ngày), tính cả hai đầu.
  final (int, int) from, to;
  const Season(this.id, this.name, this.from, this.to);

  bool activeOn(DateTime d) {
    final k = d.month * 100 + d.day, a = from.$1 * 100 + from.$2, b = to.$1 * 100 + to.$2;
    return a <= b ? k >= a && k <= b : k >= a || k <= b;
  }
}

List<Season> get seasons => [
      Season('giangsinh', tr('Giáng sinh'), (12, 1), (12, 26)),
      Season('tet', tr('Tết Nguyên đán'), (1, 20), (2, 20)), // ngày thật theo âm lịch từng năm, lấy từ máy chủ
      Season('trungthu', tr('Trung thu'), (9, 10), (9, 30)),
    ];

/// Banner Giáng sinh ở Trang chủ, cùng khuôn với dải "Sắp diễn ra" (upcoming.dart) nhưng nền đỏ - xanh thông.
class XmasBanner extends StatelessWidget {
  final DateTime now;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  const XmasBanner({super.key, required this.now, this.onTap, this.onClose});

  @override
  Widget build(BuildContext context) {
    // Đếm theo ngày lịch (dải hẹp, không cần giờ / phút).
    final days = DateTime.utc(now.year, 12, 24).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    final text = days <= 0 ? tr('Hôm nay!') : days == 1 ? tr('Ngày mai!') : tr('còn {0} ngày', [days]);
    return Padding(
      key: const ValueKey('xmas-banner'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFFB3202A), Color(0xFF7A1420), Color(0xFF0F4D2E)], stops: [0, .55, 1]),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _BannerSnow())),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Row(children: [
                  CustomPaint(size: const Size(30, 36), painter: MiniTreePainter(1)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(tr('Giáng sinh an lành'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(tr('Đêm Noel · Thứ Năm, 24/12'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .85))),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
                    child: Text(text,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFFFE08A), fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                  if (onClose != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('Ẩn'),
                      onPressed: onClose,
                      icon: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: .8)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BannerSnow extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .16)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    const pts = [(.30, .25, 6.0), (.52, .70, 4.0), (.64, .22, 5.0), (.80, .78, 7.0), (.93, .30, 4.0), (.42, .90, 3.0)];
    for (final (x, y, r) in pts) {
      drawSnowflake(c, Offset(x * s.width, y * s.height), r, p);
    }
  }

  @override
  bool shouldRepaint(_BannerSnow old) => false;
}

/// Dải dây đèn đặt ngay dưới thanh tiêu đề chat.
class LightString extends StatefulWidget {
  final bool motion;
  final double? frozenT;
  const LightString({super.key, this.motion = true, this.frozenT});
  @override
  State<LightString> createState() => _LightStringState();
}

class _LightStringState extends State<LightString> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((e) {
    final t = e.inMilliseconds / 1000;
    if (t - _t >= 1 / 20) setState(() => _t = t);
  });
  double _t = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = widget.frozenT == null && widget.motion && !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(child: CustomPaint(size: const Size(double.infinity, 34), painter: LightStringPainter(widget.frozenT ?? _t))),
      );
}

/// Màu chữ hệ thống trên hình nền (chip ngày, "đang nhập…").
Pal wallpaperPal(Wallpaper w) => w.dark ? Pal.dark : Pal.light;

/// Phát hiệu ứng rơi một lần phủ màn hình (~3 giây). Máy bật giảm chuyển động thì bỏ qua.
void playBurst(BuildContext context, BurstKind kind) {
  if (MediaQuery.maybeDisableAnimationsOf(context) == true) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => IgnorePointer(child: _Burst(kind: kind, onDone: () => entry.remove())));
  overlay.insert(entry);
}

class _Burst extends StatefulWidget {
  final BurstKind kind;
  final VoidCallback onDone;
  const _Burst({required this.kind, required this.onDone});
  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
    ..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(animation: _c, builder: (_, _) => CustomPaint(size: Size.infinite, painter: BurstPainter(_c.value, widget.kind))),
      );
}
