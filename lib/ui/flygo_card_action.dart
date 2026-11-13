import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/flows_api.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'flows/process_detail.dart' show openProcessTarget;
import 'flygo_card.dart';
import 'flows/magic_sign_hooks.dart' show openFlowSignButton;

/// Nút trên thẻ chung flygo_card: url mở link, copy sao chép, open mở tiến trình / tệp của tiến trình, reply / id gửi
/// trả lời vào luồng của thẻ (kèm props.flygo_card_action để bot / quy trình nhận biết và xử lý tiếp). Nút có `input` /
/// `select` (vd Từ chối, Trả lại của bước Tạo phê duyệt) hỏi lý do / bước trả về trước khi gửi. Xem docs/flygo-card.md.
/// [post]: thẻ để trả lời vào luồng; null (vd trang chi tiết tiến trình không có thẻ trong nhóm của mình) thì chỉ mở
/// link / tiến trình được. Nút có `id` của thẻ tiến trình ([processId], hoặc `flygo_card.process_id` của thẻ): gọi máy
/// chủ áp dụng ngay (POST /flows/processes/{id}/act); máy chủ cũ chưa có thì trả lời vào luồng thẻ như trước.
Future<void> runFlygoCardAction(BuildContext context, AppState app, MmPost? post, Map<String, dynamic> a, {String? processId}) async {
  String s(Object? v) => v == null ? '' : '$v'.trim();
  final confirm = s(a['confirm']);
  if (confirm.isNotEmpty) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(confirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(s(a['label']))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }
  // Nút ký số (Quy trình): mở bằng trình duyệt ký số của app.
  if (await openFlowSignButton(context, a) || !context.mounted) return;
  final url = Uri.tryParse(s(a['url']));
  if (url != null && (url.scheme == 'https' || url.scheme == 'http' || url.scheme == 'tel' || url.scheme == 'mailto')) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
    return;
  }
  if (a['open'] is Map) {
    await openProcessTarget(context, app, (a['open'] as Map).cast<String, dynamic>());
    return;
  }
  if (s(a['copy']).isNotEmpty) {
    await Clipboard.setData(ClipboardData(text: s(a['copy'])));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã sao chép'))));
    return;
  }
  if (a['reply'] == null && a['id'] == null) return;
  final pid = s(processId ?? post?.props['flygo_card']?['process_id']);
  if (pid.isNotEmpty && s(a['id']).isNotEmpty && a['reply'] == null) {
    var act = a;
    if (a['input'] is Map || a['select'] is Map) {
      final r = await askFlygoCardInput(context, a);
      if (r == null || !context.mounted) return;
      act = {...a, ...r};
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FlowsApi(app.token).processAct(pid, s(act['id']),
          text: s(act['reason']).isEmpty ? null : s(act['reason']),
          values: act['values'] is List ? [for (final v in act['values'] as List) '$v'] : null,
          value: s(act['value']).isEmpty ? null : s(act['value']));
      messenger.showSnackBar(toast(Text(tr('Đã gửi: {0}', [s(act['label'])]))));
      return;
    } on FlowsException catch (e) {
      // Máy chủ cũ (chưa có /act): trả lời vào luồng thẻ như trước.
      if (e.status != 404 || post == null) {
        messenger.showSnackBar(toast(Text(e.message)));
        return;
      }
    }
    if (!context.mounted) return;
  }
  if (post == null) {
    ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Mở thẻ tiến trình trong chat hoặc Tiến trình của tôi để thao tác'))));
    return;
  }
  var act = a;
  if (a['input'] is Map || a['select'] is Map) {
    final r = await askFlygoCardInput(context, a);
    if (r == null || !context.mounted) return;
    act = {...a, ...r};
  }
  final base = s(act['reply']).isNotEmpty ? s(act['reply']) : s(act['label']);
  final reply = s(act['reason']).isEmpty ? base : '$base: ${s(act['reason'])}';
  final root = post.rootId.isNotEmpty ? post.rootId : post.id;
  await app.send(post.channelId, reply, rootId: root, replyKind: 'thread', props: flygoCardActionProps(post, act));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã gửi: {0}', [reply]))));
}
