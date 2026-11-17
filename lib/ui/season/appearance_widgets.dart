import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../bubble_picker.dart' show pickBubbleColor;
import '../theme.dart';
import 'season.dart';

/// Các khối của trang Giao diện: máy tính xếp thành lưới nhiều cột (dễ bấm, không một hàng dọc dài), điện thoại xếp dọc.
class SectionGrid extends StatelessWidget {
  final List<Widget> children;
  const SectionGrid({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final w in children) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: w),
        ]);
      }
      final cols = c.maxWidth >= 1350 ? 3 : 2;
      const gap = 16.0;
      final w = (c.maxWidth - 32 - gap * (cols - 1)) / cols;
      // Chia khối vào từng cột lần lượt (cột nào đang thấp hơn thì nhận khối kế tiếp không đo được trước: xếp vòng).
      final columns = List.generate(cols, (_) => <Widget>[]);
      for (final (i, ch) in children.indexed) {
        columns[i % cols].add(Padding(padding: const EdgeInsets.only(bottom: gap), child: ch));
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, col) in columns.indexed) ...[
            if (i > 0) const SizedBox(width: gap),
            SizedBox(width: w, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: col)),
          ],
        ]),
      );
    });
  }
}

/// Một khối có tiêu đề + biểu tượng.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final List<Widget> children;
  const SectionCard({super.key, required this.title, required this.icon, this.subtitle, required this.children});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Material(
      color: pal.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            Icon(icon, size: 20, color: pal.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text))),
          ]),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(subtitle!, style: TextStyle(fontSize: 12.5, color: pal.sub, height: 1.3)),
          ),
        ...children,
        const SizedBox(height: 8),
      ]),
    );
  }
}

/// Tiêu đề nhỏ trong một khối.
Widget subHead(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: .4, fontWeight: FontWeight.w700, color: Pal.of(context).sub)),
    );

String backgroundName(String id) => switch (id) {
      'season' => tr('Theo mùa lễ'),
      'none' => tr('Không'),
      'photo' => tr('Ảnh của mình'),
      _ when id.startsWith('plain:') => tr('Màu trơn'),
      _ => wallpaperById(id)?.name ?? id,
    };

/// Bảng màu gợi ý (mỗi màu tự có bản nhạt / đậm).
const kBackgroundPalette = ['4A78B8', '1E88E5', '0E9F8E', '2E8B6E', '6D8B74', 'B8860B', 'D4A373', 'C0504D', '9E4770', '8E5BB5', '5C6B7A', '37474F'];

/// Chọn nền (Trang chủ / chat): Theo mùa lễ, Không, màu trơn (bảng + tự chọn), các hình nền Giáng sinh.
/// [value]: `season` | `none` | `plain:RRGGBB` | mã hình nền. [arts]: mã hình nền được chọn.
class BackgroundPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String>? onChanged;
  final List<String> arts;
  final bool colors;
  const BackgroundPicker({super.key, required this.value, required this.onChanged, required this.arts, this.colors = true});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final color = value.startsWith('plain:') ? value.substring(6) : null;
    Widget card(String id, Widget art, String name) {
      final on = value == id;
      return SizedBox(
        width: 84,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onChanged == null ? null : () => onChanged!(id),
          child: Column(children: [
            Container(
              width: 76,
              height: 76,
              padding: EdgeInsets.all(on ? 2.5 : 1),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? pal.accent : pal.divider, width: on ? 2.5 : 1)),
              child: ClipRRect(borderRadius: BorderRadius.circular(9), child: art),
            ),
            const SizedBox(height: 4),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: pal.text)),
          ]),
        ),
      );
    }

    Widget swatch(String hex) {
      final on = color == hex;
      return GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!('plain:$hex'),
        child: Container(
          width: 34,
          height: 34,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? pal.accent : pal.divider, width: on ? 2.5 : 1)),
          // Nửa trái: chế độ sáng, nửa phải: chế độ tối.
          child: Row(children: [
            for (final d in [false, true]) Expanded(child: Container(color: plainWallpaperColor(Color(0xFF000000 | int.parse(hex, radix: 16)), d))),
          ]),
        ),
      );
    }

    final xmas = wallpaperById('giangsinh')!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 4, runSpacing: 10, children: [
          card('season', Stack(fit: StackFit.expand, children: [
            WallpaperView(wallpaper: xmas, frozenT: 2),
            const Center(child: Icon(Icons.event_repeat_rounded, color: Colors.white70, size: 26)),
          ]), tr('Theo mùa lễ')),
          card('none', Container(color: pal.bg, child: Icon(Icons.block_rounded, color: pal.sub)), tr('Không')),
          for (final id in arts) card(id, WallpaperView(wallpaper: wallpaperById(id)!, frozenT: 2), backgroundName(id)),
        ]),
      ),
      if (colors) ...[
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 9, runSpacing: 9, children: [
            for (final h in kBackgroundPalette) swatch(h),
            GestureDetector(
              onTap: onChanged == null
                  ? null
                  : () async {
                      final c = await pickBubbleColor(context, color == null ? const Color(0xFF4A78B8) : Color(0xFF000000 | int.parse(color, radix: 16)));
                      if (c == null) return;
                      onChanged!('plain:${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}');
                    },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.divider)),
                child: Icon(Icons.colorize_rounded, color: pal.sub, size: 17),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}
