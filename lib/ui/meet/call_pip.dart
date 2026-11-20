import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart' show isChildWindow;
import 'knock_center.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../call_screen.dart' show CallScreen, CallVideo;

// Đang họp mà rời màn hình cuộc gọi (nút 💬 / nút Back để quay lại chat của cuộc họp): cuộc gọi chạy tiếp trong khung nổi
// kéo được trên toàn app. Khung hiện màn hình chia sẻ mới nhất, không thì người đang nói; nút mic, mở lại, rời họp. Bấm khung
// = mở lại màn hình cuộc gọi. Tiếng không ngắt.

class CallPipLayer extends StatefulWidget {
  final Widget child;
  const CallPipLayer({super.key, required this.child});
  @override
  State<CallPipLayer> createState() => _CallPipLayerState();
}

class _CallPipLayerState extends State<CallPipLayer> {
  Offset? _pos;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final call = app.calls;
    // Người xin vào cuộc họp: hộp lớn cho chủ trì ở mọi màn hình của app (chỉ cửa sổ chính).
    final content = isChildWindow ? widget.child : MeetKnockLayer(call: call, child: widget.child);
    return ValueListenableBuilder<int>(
      valueListenable: CallScreen.visible,
      builder: (context, shown, _) {
        // Chỉ cửa sổ chính (nơi có cuộc gọi) hiện khung nổi: cửa sổ phụ của app trên máy tính (mini app, nhóm tách riêng…)
        // không vẽ thêm một khung nổi nữa (bug 2026-11-20: khung thừa nổi trên cửa sổ app Màn hình).
        final pip = !isChildWindow && shown == 0 && call.busy && call.direct == null && (call.phase == CallPhase.active || call.phase == CallPhase.connecting);
        if (!pip) return content;
        return LayoutBuilder(builder: (context, box) {
          const w = 150.0, h = 196.0;
          final pad = MediaQuery.paddingOf(context);
          final maxX = box.maxWidth - w - 8, maxY = box.maxHeight - h - 8 - pad.bottom;
          final p = _pos ?? Offset(maxX, pad.top + 72);
          final at = Offset(p.dx.clamp(8.0, maxX < 8 ? 8.0 : maxX), p.dy.clamp(pad.top + 8, maxY < pad.top + 8 ? pad.top + 8 : maxY));
          return Stack(children: [
            content,
            Positioned(
              left: at.dx,
              top: at.dy,
              width: w,
              height: h,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _pos = at + d.delta),
                onTap: call.showCallScreen,
                child: _PipCard(call: call, app: app),
              ),
            ),
          ]);
        });
      },
    );
  }
}

class _PipCard extends StatelessWidget {
  final CallService call;
  final AppState app;
  const _PipCard({required this.call, required this.app});

  @override
  Widget build(BuildContext context) {
    final people = call.participants;
    // Màn hình chia sẻ (mới nhất trước) > người đang nói có camera > ai đó có camera.
    final screens = [for (final p in people) if (p.hasScreen) p]..sort((a, b) => b.screenAt.compareTo(a.screenAt));
    var screen = screens.firstOrNull;
    final talker = people.where((p) => p.speaking && p.hasVideo).firstOrNull ?? people.where((p) => p.hasVideo).firstOrNull;
    final title = call.channelId == null ? '' : (app.channels[call.channelId] == null ? '' : app.channelTitle(app.channels[call.channelId]!));
    Widget body;
    final pres = call.roomPresent;
    // Ai trình chiếu mới nhất lên khung: tài liệu mới hơn màn hình chia sẻ thì hiện tài liệu.
    if (pres != null && screen != null && ((pres['at'] as num?)?.toInt() ?? 0) >= screen.screenAt) screen = null;
    if (pres != null && screen == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.slideshow_rounded, color: Colors.white70, size: 36),
            const SizedBox(height: 6),
            Text('${pres['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
            Text('${pres['page'] ?? 1}/${pres['pages'] ?? '?'}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ),
      );
    } else if (screen != null) {
      body = CallVideo(stream: screen.screenStream!, trackId: screen.screenTrackId, contain: true);
    } else if (talker != null) {
      body = CallVideo(stream: talker.videoStream!, trackId: talker.videoTrackId);
    } else {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.groups_rounded, color: Colors.white70, size: 40),
          const SizedBox(height: 6),
          Text(tr('{0} người', [people.length + 1]), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ]),
      );
    }
    Widget btn(IconData i, Color c, String tip, VoidCallback onTap) => Expanded(
          child: Tooltip(
            message: tip,
            child: InkWell(onTap: onTap, child: SizedBox(height: 38, child: Icon(i, color: c, size: 20))),
          ),
        );
    return Material(
      color: Colors.black,
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            body,
            Positioned(
              left: 6,
              right: 6,
              top: 6,
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 4)])),
            ),
          ]),
        ),
        Container(
          color: const Color(0xFF1C1D20),
          child: Row(children: [
            btn(call.muted ? Icons.mic_off : Icons.mic, call.muted ? const Color(0xFFFF8A80) : Colors.white, call.muted ? tr('Bật micro') : tr('Tắt micro'),
                call.toggleMute),
            btn(Icons.open_in_full_rounded, Colors.white, tr('Mở cuộc họp'), call.showCallScreen),
            btn(Icons.call_end_rounded, const Color(0xFFFF8A80), tr('Rời cuộc họp'), () => call.hangUp()),
          ]),
        ),
      ]),
    );
  }
}
