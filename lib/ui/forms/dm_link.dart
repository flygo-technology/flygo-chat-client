// Tin của bot Biểu mẫu (props.flygo_app = vn.flygo.forms, props.flygo_form): nút mở thẳng biểu mẫu (tab Câu trả lời).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../theme.dart';
import 'api.dart';
import 'editor_page.dart';

/// Id biểu mẫu mà tin [p] trỏ tới; null nếu không phải tin của Biểu mẫu.
String? formsFormOf(MmPost p) {
  if (p.props['flygo_app'] != kFormsApp) return null;
  final id = '${p.props['flygo_form'] ?? ''}';
  return RegExp(r'^[A-Za-z0-9_-]{6,40}$').hasMatch(id) ? id : null;
}

class FormsOpenButton extends StatelessWidget {
  const FormsOpenButton({super.key, required this.formId});
  final String formId;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final state = context.read<AppState>();
      final apps = await MiniApps.list(state.token);
      final app = apps.where((a) => a.id == kFormsApp).firstOrNull;
      if (app == null) throw StateError(tr('Bạn chưa được dùng Biểu mẫu trên máy chủ này'));
      final id = await FlygoId.current(state.token);
      if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
      await nav.push(AppPageRoute(builder: (_) => FormEditorPage(api: FormsApi(base: app.baseUrl, id: id), formId: formId, tab: 1)));
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
          icon: const Icon(Icons.assignment_outlined, size: 18),
          label: Text(tr('Mở trong Biểu mẫu')),
        ),
      );
}
