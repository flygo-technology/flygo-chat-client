// Mục "Ghi chú đã ghim" của Trang chủ: thẻ nhỏ các ghi chú người dùng ghim lên Trang chủ (xem home_pins.dart).
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'home_pins.dart';
import 'look.dart';

/// Số thẻ hiện ở Trang chủ; nhiều hơn thì "Xem tất cả".
const kHomeNotesShown = 6;

class HomePinnedNotes extends StatelessWidget {
  const HomePinnedNotes({super.key, required this.onOpen, this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 4)});

  /// Mở ghi chú trong app Ghi chú (máy tính: tab mới).
  final void Function(String id) onOpen;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: HomeNotePins.instance,
        builder: (context, _) {
          final pins = HomeNotePins.instance.pins;
          if (pins.isEmpty) return const SizedBox.shrink();
          final pal = Pal.of(context);
          final shown = pins.take(kHomeNotesShown).toList();
          return Padding(
            key: const ValueKey('home-pinned-notes'),
            padding: padding,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(tr('Ghi chú đã ghim').toUpperCase(),
                      style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
                ),
                if (pins.length > kHomeNotesShown)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => _all(context),
                    child: Text(tr('Xem tất cả ({0})', [pins.length])),
                  ),
              ]),
              const SizedBox(height: 8),
              _grid(context, shown),
            ]),
          );
        },
      );

  Widget _grid(BuildContext context, List<HomeNotePin> pins) => LayoutBuilder(builder: (context, c) {
        // Thẻ rộng khoảng 170–240: hai cột ở cột trái máy tính / điện thoại, nhiều cột hơn khi rộng.
        final cols = (c.maxWidth / 170).floor().clamp(2, 6);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final p in pins) SizedBox(width: w, child: _PinCard(pin: p, onOpen: () => onOpen(p.id))),
        ]);
      });

  void _all(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (d) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: ListenableBuilder(
            listenable: HomeNotePins.instance,
            builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
                child: Row(children: [
                  Expanded(child: Text(tr('Ghi chú đã ghim'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                  IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(d)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: _grid(context, HomeNotePins.instance.pins),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({required this.pin, required this.onOpen});
  final HomeNotePin pin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = isDark(context);
    final plain = pin.color == 'default';
    final bg = plain ? pal.surface : noteColor(pin.color, dark);
    final fg = dark ? Colors.white : const Color(0xFF202124);
    final sub = fg.withValues(alpha: .7);
    final title = pin.title.isNotEmpty ? pin.title : (pin.lines.isEmpty ? tr('Ghi chú') : pin.lines.first);
    final lines = pin.title.isNotEmpty ? pin.lines : pin.lines.skip(1).toList();
    return Material(
      key: ValueKey('home-note-${pin.id}'),
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: plain ? BorderSide(color: fg.withValues(alpha: .14)) : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
                ),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: PopupMenuButton<String>(
                  tooltip: tr('Tuỳ chọn'),
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: Icon(Icons.more_vert_rounded, color: sub),
                  onSelected: (v) {
                    if (v == 'open') onOpen();
                    if (v == 'unpin') HomeNotePins.instance.unpin(pin.id);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'open', child: Text(tr('Mở ghi chú'))),
                    PopupMenuItem(value: 'unpin', child: Text(tr('Bỏ ghim trang chủ'))),
                  ],
                ),
              ),
            ]),
            if (pin.total > 0) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: pin.done / pin.total,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: fg.withValues(alpha: .12),
                      color: const Color(0xFF2E9D5B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${pin.done}/${pin.total}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sub)),
                ]),
              ),
            ],
            for (final l in lines.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (pin.kind == 'list') Padding(padding: const EdgeInsets.only(top: 1, right: 5), child: Icon(Icons.check_box_outline_blank_rounded, size: 14, color: sub)),
                  Expanded(child: Text(l, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, height: 1.3, color: sub))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
