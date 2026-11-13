// Tin của bot Bảng tin (props.flygo_app = vn.flygo.bangtin, props.flygo_post): nút mở thẳng bài trong màn hình Bảng tin.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'api.dart';
import 'bang_tin_page.dart';

/// Id bài Bảng tin mà tin [p] trỏ tới; null nếu không phải tin của Bảng tin.
String? bangTinPostOf(MmPost p) {
  if (p.props['flygo_app'] != kBangTinApp) return null;
  final id = '${p.props['flygo_post'] ?? ''}';
  return RegExp(r'^[A-Za-z0-9_-]{6,32}$').hasMatch(id) ? id : null;
}

class BangTinOpenButton extends StatelessWidget {
  const BangTinOpenButton({super.key, required this.postId});
  final String postId;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apps = await MiniApps.list(context.read<AppState>().token);
      final app = apps.where((a) => a.id == kBangTinApp).firstOrNull;
      if (!context.mounted) return;
      if (app == null) throw StateError(tr('Bạn chưa được dùng Bảng tin trên máy chủ này'));
      await openBangTin(context, app, postId: postId);
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
          icon: const Icon(Icons.campaign_rounded, size: 18),
          label: Text(tr('Mở bài trong Bảng tin')),
        ),
      );
}
