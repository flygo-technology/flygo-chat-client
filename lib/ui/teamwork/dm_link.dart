// Tin của bot Làm việc nhóm (props.flygo_app = vn.flygo.teamwork, props.flygo_task = mã việc): nút mở thẳng việc.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'api.dart';
import 'teamwork_page.dart';

/// Mã việc mà tin [p] trỏ tới; null nếu không phải tin của TeamWork.
String? teamworkTaskOf(MmPost p) {
  if (p.props['flygo_app'] != kTwApp) return null;
  final k = '${p.props['flygo_task'] ?? ''}';
  return RegExp(r'^[A-Z][A-Z0-9]{1,5}-\d{1,7}$').hasMatch(k) ? k : null;
}

class TeamworkOpenButton extends StatelessWidget {
  const TeamworkOpenButton({super.key, required this.taskKey});
  final String taskKey;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apps = await MiniApps.list(context.read<AppState>().token);
      final app = apps.where((a) => a.id == kTwApp).firstOrNull;
      if (!context.mounted) return;
      if (app == null) throw StateError('Bạn chưa được dùng app Làm việc nhóm trên máy chủ này');
      await openTeamwork(context, app, taskKey: taskKey);
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Pal.of(context).accentText),
          onPressed: () => _open(context),
          icon: const Icon(Icons.view_kanban_outlined, size: 18),
          label: Text('Mở $taskKey trong Làm việc nhóm'),
        ),
      );
}
