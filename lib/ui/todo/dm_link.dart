// Tin của bot Todo (props.flygo_app = vn.flygo.todo, props.flygo_note): nút mở thẳng ghi chú trong màn hình Todo.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'api.dart';
import 'todo_page.dart';

/// Id ghi chú mà tin [p] trỏ tới; null nếu không phải tin của Todo.
String? todoNoteOf(MmPost p) {
  if (p.props['flygo_app'] != kTodoApp) return null;
  final id = '${p.props['flygo_note'] ?? ''}';
  return RegExp(r'^[A-Za-z0-9_-]{6,40}$').hasMatch(id) ? id : null;
}

class TodoOpenButton extends StatelessWidget {
  const TodoOpenButton({super.key, required this.noteId});
  final String noteId;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apps = await MiniApps.list(context.read<AppState>().token);
      final app = apps.where((a) => a.id == kTodoApp).firstOrNull;
      if (!context.mounted) return;
      if (app == null) throw StateError(tr('Bạn chưa được dùng Todo trên máy chủ này'));
      await openTodo(context, app, noteId: noteId);
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
          icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
          label: Text(tr('Mở ghi chú trong Todo')),
        ),
      );
}
