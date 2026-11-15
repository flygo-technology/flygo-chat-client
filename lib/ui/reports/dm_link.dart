// Tin của bot Báo cáo (props.flygo_app = vn.flygo.reports, props.flygo_report [+ flygo_edition]): nút mở thẳng bản báo cáo.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../theme.dart';
import 'api.dart';
import 'edition_page.dart';

final _idRe = RegExp(r'^[A-Za-z0-9_-]{6,40}$');

/// (báo cáo, bản) mà tin [p] trỏ tới; null nếu không phải tin của Báo cáo.
(String, String?)? reportsLinkOf(MmPost p) {
  if (p.props['flygo_app'] != kReportsApp) return null;
  final r = '${p.props['flygo_report'] ?? ''}', e = '${p.props['flygo_edition'] ?? ''}';
  if (!_idRe.hasMatch(r)) return null;
  return (r, _idRe.hasMatch(e) ? e : null);
}

class ReportsOpenButton extends StatelessWidget {
  const ReportsOpenButton({super.key, required this.link});
  final (String, String?) link;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final state = context.read<AppState>();
      final apps = await MiniApps.list(state.token);
      final app = apps.where((a) => a.id == kReportsApp).firstOrNull;
      if (app == null) throw StateError('Bạn chưa được dùng Báo cáo trên máy chủ này');
      final id = await FlygoId.current(state.token);
      if (id == null) throw StateError('Máy chủ này chưa có Flygo ID');
      await nav.push(
        AppPageRoute(
          builder: (_) => EditionPage(
            api: ReportsApi(base: app.baseUrl, id: id),
            reportId: link.$1,
            editionId: link.$2,
          ),
        ),
      );
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
      icon: const Icon(Icons.insert_chart_outlined_rounded, size: 18),
      label: const Text('Mở báo cáo'),
    ),
  );
}
