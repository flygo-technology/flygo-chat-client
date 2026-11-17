// Thư: khung chờ (skeleton) thay cho vòng quay khi đang tải danh sách, hội thoại, hộp thư.
import 'package:flutter/material.dart';

import 'widgets.dart';

/// Ánh sáng lướt qua các khối xám con (một bộ đếm cho cả khung).
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final base = mc.surface2, hi = mc.dark ? const Color(0xFF323949) : const Color(0xFFF7F9FC);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(-1.6 + 3.2 * _c.value, 0),
          end: Alignment(-0.6 + 3.2 * _c.value, 0),
          colors: [base, hi, base],
        ).createShader(r),
        child: child,
      ),
    );
  }
}

/// Một khối xám bo góc.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius = 6, this.circle = false});
  final double? width;
  final double height, radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: circle ? height : width,
        height: height,
        decoration: BoxDecoration(
          color: MailColors.of(context).surface2,
          borderRadius: circle ? null : BorderRadius.circular(radius),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
        ),
      );
}

/// Danh sách thư đang tải.
class MailListSkeleton extends StatelessWidget {
  const MailListSkeleton({super.key, this.rows = 9, this.phone = false});
  final int rows;
  final bool phone;

  @override
  Widget build(BuildContext context) => Shimmer(
        key: const ValueKey('mail-list-skeleton'),
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows,
          itemBuilder: (context, i) {
            final w = [0.55, 0.7, 0.45, 0.62, 0.5][i % 5];
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: phone ? 12 : 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Bone(height: phone ? 40 : 32, circle: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: w * .6, child: const Bone(height: 13))), const SizedBox(width: 12), const Bone(width: 40, height: 11)]),
                    const SizedBox(height: 8),
                    FractionallySizedBox(widthFactor: w + .25, child: const Bone(height: 11)),
                    const SizedBox(height: 6),
                    FractionallySizedBox(widthFactor: w, child: const Bone(height: 11)),
                  ]),
                ),
              ]),
            );
          },
        ),
      );
}

/// Hội thoại đang mở: tiêu đề, người gửi, vài dòng nội dung.
class ThreadSkeleton extends StatelessWidget {
  const ThreadSkeleton({super.key, this.wide = true});
  final bool wide;

  @override
  Widget build(BuildContext context) => Shimmer(
        key: const ValueKey('mail-thread-skeleton'),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(wide ? 72 : 16, 20, 24, 0),
          children: [
            const FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: .6, child: Bone(height: 22, radius: 8)),
            const SizedBox(height: 24),
            Row(children: [
              const Bone(height: 40, circle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  FractionallySizedBox(widthFactor: .35, child: Bone(height: 13)),
                  SizedBox(height: 8),
                  FractionallySizedBox(widthFactor: .5, child: Bone(height: 11)),
                ]),
              ),
              const Bone(width: 64, height: 11),
            ]),
            const SizedBox(height: 24),
            for (final f in const <double>[.95, .9, .97, .6, 0, .92, .85, .4])
              Padding(padding: const EdgeInsets.only(bottom: 10), child: f == 0 ? const SizedBox(height: 8) : FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: f, child: const Bone(height: 12))),
          ],
        ),
      );
}

/// Địa chỉ hộp thư đang đổi (thay chữ của hộp cũ).
class MailboxNameSkeleton extends StatelessWidget {
  const MailboxNameSkeleton({super.key});
  @override
  Widget build(BuildContext context) => const Shimmer(
        key: ValueKey('mail-box-skeleton'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Bone(width: 180, height: 13),
          SizedBox(height: 6),
          Bone(width: 90, height: 10),
        ]),
      );
}
