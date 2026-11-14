import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'chat_jump.dart';
import 'common.dart';
import 'theme.dart';

/// Nhóm các mục theo ngày (giờ máy), ngày mới nhất trước; trong một ngày giữ thứ tự đầu vào.
List<(DateTime, List<T>)> groupByDay<T>(Iterable<T> items, int Function(T) atMs) {
  final map = <DateTime, List<T>>{};
  for (final x in items) {
    final d = DateTime.fromMillisecondsSinceEpoch(atMs(x));
    (map[DateTime(d.year, d.month, d.day)] ??= []).add(x);
  }
  final days = map.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in days) (d, map[d]!)];
}

/// Nhóm cần cuộn tới khi chọn ngày [pick] ([days] mới nhất trước): đúng ngày đó, không có thì ngày gần nhất
/// trước đó có mục. null: không có ngày nào từ [pick] trở về trước (trong phần đã tải).
int? sectionAtOrBefore(List<DateTime> days, DateTime pick) {
  final p = DateTime(pick.year, pick.month, pick.day);
  for (var i = 0; i < days.length; i++) {
    if (!days[i].isAfter(p)) return i;
  }
  return null;
}

/// Danh sách chia theo ngày, tiêu đề ngày dính ở trên khi cuộn, nút lịch luôn nằm ở góc dưới bên phải
/// để tua tới ngày bất kỳ. Chiều cao từng nhóm tính được trước ([contentExtent]) nên tua tới nhóm chưa dựng vẫn chính xác.
class DaySectionsView extends StatefulWidget {
  /// Các ngày (mới nhất trước), mỗi ngày một nhóm.
  final List<DateTime> days;
  /// Nội dung (sliver) của nhóm thứ i.
  final Widget Function(BuildContext context, int i) content;
  /// Chiều cao nội dung nhóm thứ i khi khung rộng [width].
  final double Function(int i, double width) contentExtent;
  /// Phần đứng trước các nhóm ngày (vd. đánh dấu của kênh) và chiều cao của nó.
  final List<Widget> leading;
  final double leadingExtent;
  /// Còn mục cũ hơn chưa tải: [loadOlder] tải thêm (khi cuộn tới cuối hoặc khi chọn ngày cũ hơn phần đã có).
  final bool hasOlder;
  final Future<void> Function()? loadOlder;
  /// Tên loại mục trong thông báo ("ảnh", "tệp", "liên kết").
  final String noun;
  /// Ngày tạo cuộc trò chuyện (ms, 0 = không rõ): không chọn được ngày trước đó.
  final int createdAt;
  final Widget? empty;
  const DaySectionsView({
    super.key,
    required this.days,
    required this.content,
    required this.contentExtent,
    required this.noun,
    this.leading = const [],
    this.leadingExtent = 0,
    this.hasOlder = false,
    this.loadOlder,
    this.createdAt = 0,
    this.empty,
  });

  static const headerHeight = 36.0;

  @override
  State<DaySectionsView> createState() => _DaySectionsViewState();
}

class _DaySectionsViewState extends State<DaySectionsView> {
  final _scroll = ScrollController();
  bool _loading = false;
  bool _busy = false;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final pos = _scroll.position;
      if (pos.pixels > pos.maxScrollExtent - 600) _loadOlder();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadOlder() async {
    if (_loading || !widget.hasOlder || widget.loadOlder == null) return;
    _loading = true;
    try {
      await widget.loadOlder!();
    } catch (_) {
    } finally {
      _loading = false;
    }
  }

  /// Vị trí cuộn của tiêu đề nhóm thứ [i].
  double _offsetOf(int i) {
    var y = widget.leadingExtent;
    for (var k = 0; k < i; k++) {
      y += DaySectionsView.headerHeight + widget.contentExtent(k, _width);
    }
    return y;
  }

  Future<void> _pick() async {
    final d = await pickJumpDate(context,
        createdAt: widget.createdAt, initial: widget.days.isEmpty ? null : widget.days.first);
    if (d == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final day = '${two(d.day)}/${two(d.month)}';
    var i = sectionAtOrBefore(widget.days, d);
    // Ngày chọn cũ hơn phần đã tải: tải thêm tới khi có ngày đó (hoặc ngày trước đó) hay hết lịch sử.
    if (i == null && widget.hasOlder && widget.loadOlder != null) {
      setState(() => _busy = true);
      for (var n = 0; n < 50 && i == null && mounted && widget.hasOlder; n++) {
        final before = widget.days.length;
        await _loadOlder();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        i = sectionAtOrBefore(widget.days, d);
        if (widget.days.length == before && !widget.hasOlder) break;
      }
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (i == null) {
      messenger.showSnackBar(toast(Text(tr('Không có {0} nào từ ngày {1} trở về trước', [widget.noun, day]))));
      return;
    }
    final p = DateTime(d.year, d.month, d.day);
    if (widget.days[i] != p) {
      messenger.showSnackBar(toast(Text(tr('Không có {0} ngày {1}, đang hiện ngày gần nhất', [widget.noun, day]))));
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position;
    _scroll.jumpTo(_offsetOf(i).clamp(0.0, pos.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final empty = widget.days.isEmpty && widget.leading.isEmpty;
    return LayoutBuilder(builder: (context, c) {
      _width = c.maxWidth;
      return Stack(children: [
        Positioned.fill(
          child: empty && widget.empty != null
              ? widget.empty!
              : CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    ...widget.leading,
                    for (var i = 0; i < widget.days.length; i++)
                      SliverMainAxisGroup(slivers: [
                        SliverPersistentHeader(pinned: true, delegate: _DayHeader(dayHeaderLabel(widget.days[i]), pal)),
                        widget.content(context, i),
                      ]),
                    if (widget.hasOlder)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                              child: SizedBox(
                                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent))),
                        ),
                      ),
                    // Chừa chỗ cho nút lịch ở góc dưới.
                    const SliverToBoxAdapter(child: SizedBox(height: 72)),
                  ],
                ),
        ),
        Positioned(
          right: 14,
          bottom: 14 + MediaQuery.paddingOf(context).bottom,
          child: ChatRoundButton(
            key: const ValueKey('day-sections-date'),
            tooltip: tr('Tua tới ngày'),
            onTap: _busy ? null : _pick,
            icon: _busy
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: pal.text))
                : Icon(Icons.calendar_month_rounded, color: pal.text),
          ),
        ),
      ]);
    });
  }
}

class _DayHeader extends SliverPersistentHeaderDelegate {
  final String label;
  final Pal pal;
  _DayHeader(this.label, this.pal);

  @override
  double get minExtent => DaySectionsView.headerHeight;
  @override
  double get maxExtent => DaySectionsView.headerHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: pal.bg,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.sub)),
      );

  @override
  bool shouldRebuild(_DayHeader old) => old.label != label || old.pal != pal;
}
