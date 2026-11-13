import 'package:flutter/material.dart';

import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'schedules_view.dart' show openChatWith;
import 'theme.dart';

/// Việc chạy ngầm của một phiên AI (trợ lý gọi spawn_task, runner 0.6.82): các phiên con mang mốc
/// `[flygo-ai-task <id phiên cha>]`, chưa có `[flygo-ai-done]`.
List<MmChannel> bgTasksOf(AppState app, String channelId) =>
    app.channels.values.where((c) => c.aiTaskOf == channelId && !c.aiDone && !c.aiArchived).toList()
      ..sort((a, b) => a.createAt.compareTo(b.createAt));

/// Dòng "⚙ N việc chạy ngầm" dưới tên chat; bấm mở danh sách. Không có việc nào thì không hiện gì.
class BgTasksLine extends StatelessWidget {
  final AppState app;
  final String channelId;
  final bool center;
  const BgTasksLine({super.key, required this.app, required this.channelId, this.center = false});

  @override
  Widget build(BuildContext context) {
    final tasks = bgTasksOf(app, channelId);
    if (tasks.isEmpty) return const SizedBox.shrink();
    final pal = Pal.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showBgTasks(context, app, channelId),
      child: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: pal.accentText)),
            const SizedBox(width: 6),
            Text(tr('{0} việc chạy ngầm', [tasks.length]),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.accentText)),
          ],
        ),
      ),
    );
  }
}

/// Danh sách việc chạy ngầm của phiên: tên việc, thời gian đã chạy; bấm để mở phiên con.
Future<void> showBgTasks(BuildContext context, AppState app, String channelId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => ListenableBuilder(
      listenable: app,
      builder: (ctx, _) {
        final pal = Pal.of(ctx);
        final tasks = bgTasksOf(app, channelId);
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('Việc chạy ngầm'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Text(tr('Không còn việc nào đang chạy ngầm.'), style: TextStyle(color: pal.sub)),
              ),
            for (final c in tasks)
              ListTile(
                leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accentText)),
                title: Text(app.channelTitle(c), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(tr('Đã chạy {0}', [_ago(c.createAt)]), style: TextStyle(color: pal.sub)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  openChatWith(context, c.id);
                },
              ),
            const SizedBox(height: 8),
          ]),
        );
      },
    ),
  );
}

String _ago(int ms) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return tr('vài giây');
  if (d.inHours < 1) return tr('{0} phút', [d.inMinutes]);
  return tr('{0} giờ {1} phút', [d.inHours, d.inMinutes % 60]);
}
