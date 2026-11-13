import '../i18n/i18n.dart';

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../push/push_service.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'effects.dart';

// Tin khẩn cấp (priority "urgent") của người khác: hiện toàn màn hình, đè lên mọi thứ, kêu chuông tới khi bấm "Đã nhận".
// Nền / chữ theo màu nền người gửi chọn (props.flygo_fx.bg; chữ trắng), mặc định nền đen chữ đỏ.

/// Màn hình tin khẩn cấp. Bấm "Đã nhận" = xác nhận đã đọc (ack); "Mở chat" = xác nhận rồi mở cuộc trò chuyện.
class UrgentAlertPage extends StatefulWidget {
  final AppState app;
  final MmPost post;
  const UrgentAlertPage({super.key, required this.app, required this.post});

  @override
  State<UrgentAlertPage> createState() => _UrgentAlertPageState();
}

class _UrgentAlertPageState extends State<UrgentAlertPage> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))
    ..repeat(reverse: true);
  final _player = AudioPlayer();
  static const _lock = MethodChannel('flygo/urgent');

  /// Android: chỉ trong lúc hiện tin khẩn cấp mới cho hiện đè màn hình khoá và bật màn hình.
  static void _overLock(bool on) {
    if (!kIsWeb && Platform.isAndroid) _lock.invokeMethod('overLock', on).catchError((_) {});
  }

  @override
  void initState() {
    super.initState();
    // Đã xác nhận ở máy khác (máy tính / điện thoại khác): tự tắt chuông, đóng màn hình.
    widget.app.urgentDone.addListener(_check);
    widget.app.addListener(_check);
    _overLock(true);
    _player
      ..setReleaseMode(ReleaseMode.loop)
      ..play(AssetSource('ringtones/ring_digital.mp3')).catchError((_) {});
  }

  bool _closed = false;
  void _check() {
    if (_closed || !mounted || !widget.app.urgentAcked(widget.post)) return;
    _closed = true;
    _player.stop();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.app.urgentDone.removeListener(_check);
    widget.app.removeListener(_check);
    _overLock(false);
    _blink.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _ack({bool open = false}) async {
    if (_closed) return;
    _closed = true;
    _player.stop();
    final p = widget.post;
    widget.app.ackUrgent(p).catchError((_) {});
    if (mounted) Navigator.of(context).pop();
    if (open) {
      PushService.openPostId = p.id;
      PushService.openChannel.value = null;
      PushService.openChannel.value = p.channelId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, p = widget.post;
    final bg = fxBackgrounds[(p.props['flygo_fx'] as Map?)?['bg'] as String?]?.$2;
    final fg = bg == null ? const Color(0xFFFF2D2D) : Colors.white;
    final ch = app.channels[p.channelId];
    final sender = app.users[p.userId];
    final senderName = sender?.displayName ?? tr('Người dùng');
    final chatName = ch == null ? '' : (ch.isDirect ? senderName : app.channelTitle(ch));
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            color: bg == null ? Colors.black : null,
            gradient: bg == null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FadeTransition(
                  opacity: Tween(begin: .25, end: 1.0).animate(_blink),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.campaign_rounded, color: fg, size: 34),
                    const SizedBox(width: 10),
                    Text(tr('TIN KHẨN CẤP'),
                        style: TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ]),
                ),
                const SizedBox(height: 28),
                if (chatName.isNotEmpty && !(ch?.isDirect ?? false))
                  Text(chatName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Avatar(userId: p.userId, name: senderName, size: 40),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Text(hhmm(DateTime.fromMillisecondsSinceEpoch(p.createAt)), style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 15)),
                ]),
                const SizedBox(height: 24),
                // Nội dung: cỡ chữ to nhất vừa khung (tin ngắn chữ rất to, tin dài nhỏ dần, tối thiểu 24).
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    final text = plainPreview(p.message);
                    final size = biggestFontSize(text, box.maxWidth, box.maxHeight, weight: FontWeight.w800, height: 1.25);
                    return Center(
                      child: SingleChildScrollView(
                        child: Text(text,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: fg, fontSize: size, height: 1.25, fontWeight: FontWeight.w800)),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: fg,
                        side: BorderSide(color: fg, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _ack(open: true),
                      child: Text(tr('Mở chat'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: fg,
                        foregroundColor: bg == null ? Colors.black : bg.first,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _ack,
                      child: Text(tr('Đã nhận'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cỡ chữ lớn nhất (tối đa [max], tối thiểu [min]) để [text] vừa khung [w] x [h].
double biggestFontSize(String text, double w, double h,
    {double min = 24, double max = 160, FontWeight weight = FontWeight.w700, double height = 1.25}) {
  if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return min;
  bool fits(double s) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: s, height: height, fontWeight: weight)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w);
    final ok = tp.height <= h && !tp.didExceedMaxLines && tp.width <= w + .5;
    // Từ dài hơn cả khung (không xuống dòng được) cũng tính là tràn.
    final words = text.split(RegExp(r'\s+')).where((x) => x.isNotEmpty);
    final wide = words.any((x) {
      final t = TextPainter(text: TextSpan(text: x, style: TextStyle(fontSize: s, fontWeight: weight)), textDirection: TextDirection.ltr)..layout();
      return t.width > w;
    });
    tp.dispose();
    return ok && !wide;
  }
  if (fits(max)) return max;
  var lo = min, hi = max;
  for (var i = 0; i < 12; i++) {
    final mid = (lo + hi) / 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo.floorToDouble();
}

/// Nhãn nhấp nháy trên tin quan trọng / khẩn cấp trong khung chat.
class BlinkLabel extends StatefulWidget {
  final IconData icon;
  final String text;
  final Color color;
  const BlinkLabel({super.key, required this.icon, required this.text, required this.color});

  @override
  State<BlinkLabel> createState() => _BlinkLabelState();
}

class _BlinkLabelState extends State<BlinkLabel> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .35, end: 1.0).animate(_c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(widget.text,
                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .8)),
          ]),
        ),
      );
}

/// Dải "TIN QUAN TRỌNG" / "TIN KHẨN CẤP" trên đầu khung tin: tràn hết chiều rộng, chữ nhấp nháy.
class PriorityStrip extends StatefulWidget {
  final bool urgent;
  const PriorityStrip({super.key, required this.urgent});
  @override
  State<PriorityStrip> createState() => _PriorityStripState();
}

class _PriorityStripState extends State<PriorityStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.urgent ? const Color(0xFFE53935) : const Color(0xFFF08C00);
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: FadeTransition(
        opacity: Tween(begin: .35, end: 1.0).animate(_c),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.urgent ? Icons.campaign_rounded : Icons.priority_high_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(widget.urgent ? tr('TIN KHẨN CẤP') : tr('TIN QUAN TRỌNG'),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .9)),
        ]),
      ),
    );
  }
}
