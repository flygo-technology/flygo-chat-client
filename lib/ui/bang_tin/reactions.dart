// Bảng tin: cảm xúc kiểu Facebook. Nút "Thích": bấm là 👍 (bấm lại để bỏ). Rê chuột (máy tính) hoặc bấm giữ (điện thoại)
// thì bật thanh 6 cảm xúc để chọn. Mỗi người một cảm xúc trên một bài (server thay cái cũ).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart' show isDesktop;
import '../../i18n/i18n.dart';
import '../theme.dart';

class ReactionKind {
  const ReactionKind(this.emoji, this.label, this.color);
  final String emoji;
  final String label;
  final Color color;
}

List<ReactionKind> get kReactionKinds => [
  ReactionKind('👍', tr('Thích'), const Color(0xFF2D88FF)),
  ReactionKind('❤️', tr('Yêu thích'), const Color(0xFFF33E58)),
  ReactionKind('😆', tr('Haha'), const Color(0xFFF7B125)),
  ReactionKind('😮', tr('Wow'), const Color(0xFFF7B125)),
  ReactionKind('😢', tr('Buồn'), const Color(0xFFF7B125)),
  ReactionKind('😡', tr('Phẫn nộ'), const Color(0xFFE9710F)),
];

ReactionKind? reactionKind(String? emoji) => emoji == null ? null : kReactionKinds.where((k) => k.emoji == emoji).firstOrNull;

/// Nút "Thích" có thanh chọn cảm xúc. [mine] là cảm xúc hiện tại của mình (null = chưa).
class LikeButton extends StatefulWidget {
  const LikeButton({super.key, required this.mine, required this.onReact, this.compact = false});
  final String? mine;

  /// emoji = cảm xúc chọn; null = bỏ cảm xúc.
  final ValueChanged<String?> onReact;
  final bool compact;

  @override
  State<LikeButton> createState() => LikeButtonState();
}

class LikeButtonState extends State<LikeButton> {
  final _link = LayerLink();
  OverlayEntry? _bar;
  Timer? _hoverOpen, _hoverClose;

  @override
  void dispose() {
    _hoverOpen?.cancel();
    _hoverClose?.cancel();
    _bar?.remove();
    super.dispose();
  }

  /// Bật thanh cảm xúc (kiểm thử gọi thẳng để chụp ảnh).
  void openBar() {
    if (_bar != null) return;
    _hoverClose?.cancel();
    final overlay = Overlay.of(context);
    _bar = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Bấm ra ngoài để đóng (điện thoại).
          if (!isDesktop)
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: closeBar),
            ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: const Offset(-4, -6),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: MouseRegion(
                onEnter: (_) => _hoverClose?.cancel(),
                onExit: (_) => _scheduleClose(),
                child: ReactionBar(
                  onPick: (e) {
                    closeBar();
                    widget.onReact(e);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_bar!);
  }

  void closeBar() {
    _hoverOpen?.cancel();
    _bar?.remove();
    _bar = null;
  }

  void _scheduleClose() {
    _hoverClose?.cancel();
    _hoverClose = Timer(const Duration(milliseconds: 350), closeBar);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final k = reactionKind(widget.mine);
    final color = k?.color ?? pal.sub;
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) {
          _hoverClose?.cancel();
          _hoverOpen = Timer(const Duration(milliseconds: 450), openBar);
        },
        onExit: (_) {
          _hoverOpen?.cancel();
          if (_bar != null) _scheduleClose();
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            closeBar();
            widget.onReact(widget.mine == null ? '👍' : null);
          },
          onLongPress: openBar,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 6 : 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (k == null || k.emoji == '👍')
                  Icon(k == null ? Icons.thumb_up_outlined : Icons.thumb_up_rounded, size: 19, color: color)
                else
                  Text(k.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    k?.label ?? tr('Thích'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thanh 6 cảm xúc (nổi lên trên nút Thích).
class ReactionBar extends StatefulWidget {
  const ReactionBar({super.key, required this.onPick});
  final ValueChanged<String> onPick;

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))..forward();
  int? _hover;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final kinds = kReactionKinds;
    return ScaleTransition(
      scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
      alignment: Alignment.bottomLeft,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: pal.divider),
            boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 16, offset: Offset(0, 4))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < kinds.length; i++)
                  Tooltip(
                    message: kinds[i].label,
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hover = i),
                      onExit: (_) => setState(() => _hover = null),
                      child: GestureDetector(
                        onTap: () => widget.onPick(kinds[i].emoji),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.all(4),
                          transform: Matrix4.translationValues(0, _hover == i ? -6 : 0, 0),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 120),
                            // Giữ kiểu chữ của theme (có font emoji dự phòng trên Linux), chỉ đổi cỡ.
                            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(fontSize: _hover == i ? 38 : 30, height: 1.1, decoration: TextDecoration.none),
                            child: Text(kinds[i].emoji),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tóm tắt cảm xúc: tối đa 3 biểu tượng chồng nhau + tổng số.
class ReactionSummary extends StatelessWidget {
  const ReactionSummary({super.key, required this.reactions, this.onTap});
  final Map<String, dynamic> reactions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final sorted = reactions.entries.toList()..sort((a, b) => ((b.value as num?) ?? 0).compareTo((a.value as num?) ?? 0));
    final total = sorted.fold<int>(0, (s, e) => s + ((e.value as num?)?.toInt() ?? 0));
    if (total == 0) return const SizedBox.shrink();
    final top = sorted.take(3).map((e) => e.key).toList();
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18.0 + (top.length - 1) * 13,
            height: 20,
            child: Stack(
              children: [
                for (var i = top.length - 1; i >= 0; i--)
                  Positioned(
                    left: i * 13.0,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: pal.surface,
                        border: Border.all(color: pal.surface, width: 1.5),
                      ),
                      child: Text(top[i], style: const TextStyle(fontSize: 13, height: 1)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text('$total', style: TextStyle(color: pal.sub, fontSize: 13.5)),
        ],
      ),
    );
  }
}
