// Tin báo thư mới của bot Thư (props.flygo_app = vn.flygo.mail, props.flygo_thread, props.flygo_mailbox):
// nút mở thẳng cuộc hội thoại trong màn hình Thư.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'api.dart';
import 'mail_page.dart';

/// (thread, mailbox) mà tin [p] trỏ tới; null nếu không phải tin của Thư.
(String, String?)? mailThreadOf(MmPost p) {
  if (p.props['flygo_app'] != kMailApp) return null;
  final id = '${p.props['flygo_thread'] ?? ''}';
  if (!RegExp(r'^[A-Za-z0-9_.@-]{6,200}$').hasMatch(id)) return null;
  final mb = '${p.props['flygo_mailbox'] ?? ''}';
  return (id, RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(mb) ? mb : null);
}

class MailOpenButton extends StatelessWidget {
  const MailOpenButton({super.key, required this.threadId, this.mailbox});
  final String threadId;
  final String? mailbox;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apps = await MiniApps.list(context.read<AppState>().token);
      final app = apps.where((a) => a.id == kMailApp).firstOrNull;
      if (!context.mounted) return;
      if (app == null) throw StateError(tr('Bạn chưa được dùng Thư trên máy chủ này'));
      await openMail(context, app, threadId: threadId, mailbox: mailbox);
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
          icon: const Icon(Icons.mail_outline, size: 18),
          label: Text(tr('Mở thư trong Thư')),
        ),
      );
}
