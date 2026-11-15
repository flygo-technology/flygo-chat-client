// Tin của bot Lịch (props.flygo_app = vn.flygo.calendar, props.flygo_event, props.flygo_rid?): nút mở thẳng sự kiện trong
// màn hình Lịch. Nút Có / Không / Có thể của lời mời do Mattermost vẽ (interactive buttons), app không cần làm gì thêm.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'api.dart';
import 'calendar_page.dart';

/// (id sự kiện, rid) mà tin [p] trỏ tới; null nếu không phải tin của Lịch.
(String, String?)? calendarEventOf(MmPost p) {
  if (p.props['flygo_app'] != kCalApp) return null;
  final id = '${p.props['flygo_event'] ?? ''}';
  if (!RegExp(r'^[A-Za-z0-9_-]{6,40}$').hasMatch(id)) return null;
  final rid = p.props['flygo_rid'];
  return (id, rid is String && RegExp(r'^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?$').hasMatch(rid) ? rid : null);
}

class CalendarOpenButton extends StatelessWidget {
  const CalendarOpenButton({super.key, required this.eventId, this.rid, this.kind});
  final String eventId;
  final String? rid;
  /// props.flygo_kind: reminder | invite | update | cancel | rsvp | shared.
  final String? kind;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apps = await MiniApps.list(context.read<AppState>().token);
      final app = apps.where((a) => a.id == kCalApp).firstOrNull;
      if (!context.mounted) return;
      if (app == null) throw StateError(tr('Bạn chưa được dùng Lịch trên máy chủ này'));
      await openCalendar(context, app, eventId: eventId, rid: rid);
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lịch được chia sẻ: không có sự kiện cụ thể nhưng vẫn mở được Lịch.
    final label = kind == 'cancel' ? tr('Xem trong Lịch') : tr('Mở sự kiện trong Lịch');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Pal.of(context).accentText),
        onPressed: () => _open(context),
        icon: const Icon(Icons.event_outlined, size: 18),
        label: Text(label),
      ),
    );
  }
}
