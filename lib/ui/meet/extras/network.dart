import 'dart:async';

import 'package:flutter/material.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';

// Chất lượng mạng từng người (LiveKit connection quality: excellent / good / poor / lost): vạch sóng trên ô,
// báo nhanh khi mạng của chính mình yếu. LiveKit tự giảm chất lượng video (simulcast + dynacast) cho người mạng yếu.

/// Vạch sóng 3 nấc. quality: 'excellent' | 'good' | 'poor' | 'lost' | '' (chưa biết: không vẽ).
class MeetSignalBadge extends StatelessWidget {
  final String quality;
  final double size;
  const MeetSignalBadge({super.key, required this.quality, this.size = 14});

  static String label(String q) => switch (q) {
        'excellent' => tr('Mạng tốt'),
        'good' => tr('Mạng trung bình'),
        'poor' => tr('Mạng yếu'),
        'lost' => tr('Mất kết nối'),
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    if (quality.isEmpty || quality == 'unknown') return const SizedBox.shrink();
    final bars = switch (quality) { 'excellent' => 3, 'good' => 2, 'poor' => 1, _ => 0 };
    final color = switch (quality) { 'excellent' => const Color(0xFF4CC38A), 'good' => const Color(0xFFF2C14E), _ => const Color(0xFFEA4C4C) };
    return Tooltip(
      message: label(quality),
      child: Container(
        padding: EdgeInsets.all(size * .25),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(size * .35)),
        child: SizedBox(
          width: size,
          height: size * .8,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: size * .22,
                height: size * .8 * (i + 1) / 3,
                decoration: BoxDecoration(color: i < bars ? color : Colors.white24, borderRadius: BorderRadius.circular(1)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Báo khi mạng của mình chuyển sang yếu / mất (một lần mỗi 60 giây), và khi đã ổn lại.
StreamSubscription<void> listenNetworkNotices(CallService call, void Function(String text) toast) {
  var last = call.myQuality;
  DateTime? warned;
  void changed() {
    final q = call.myQuality;
    if (q == last) return;
    final was = last;
    last = q;
    final bad = q == 'poor' || q == 'lost';
    if (bad && (warned == null || DateTime.now().difference(warned!) > const Duration(seconds: 60))) {
      warned = DateTime.now();
      toast(q == 'lost' ? tr('⚠️ Mất kết nối mạng, đang thử nối lại…') : tr('⚠️ Mạng của bạn đang chập chờn. Đã giảm chất lượng video.'));
    } else if (!bad && (was == 'poor' || was == 'lost') && warned != null) {
      toast(tr('Mạng đã ổn định lại'));
    }
  }

  call.addListener(changed);
  final c = StreamController<void>(onCancel: () => call.removeListener(changed));
  return c.stream.listen(null);
}
