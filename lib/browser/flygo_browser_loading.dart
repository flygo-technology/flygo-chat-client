// Màn hình chờ khi mở trình duyệt Flygo (Sếp 2026-11-22: "bấm 1 cái là hiện ngay, kể cả đang loading"): hiện ngay khi bấm
// (tên công ty, địa chỉ, bước đang làm, tiến độ tải), tự đóng khi cửa sổ trình duyệt hiện; lỗi thật thì mở WebView như cũ.
import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'flygo_browser_host.dart';

/// Mở công ty [tax] trong trình duyệt Flygo kèm màn hình chờ. Trả false nếu không mở được (nơi gọi dùng WebView).
Future<bool> openInFlygoBrowser(BuildContext context, {String? tax, String? profile, required String title, String? url}) async {
  final host = FlygoBrowserHost.instance;
  var done = false;
  final nav = Navigator.of(context, rootNavigator: true);
  // Hiện ngay (khung đầu tiên), không chờ gì.
  final dialog = showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 80),
    pageBuilder: (ctx, _, _) => FlygoBrowserLoadingCard(title: title, url: url, onCancel: () => Navigator.of(ctx).pop()),
  );
  var cancelled = false;
  unawaited(dialog.then((_) => cancelled = !done));
  final ok = await host.open(tax: tax, profile: profile, url: url);
  done = true;
  if (!cancelled && nav.canPop()) nav.pop();
  return ok;
}


/// Thẻ màn hình chờ (công khai để chụp ảnh xem trước).
class FlygoBrowserLoadingCard extends StatelessWidget {
  const FlygoBrowserLoadingCard({super.key, required this.title, required this.url, required this.onCancel});
  final String title;
  final String? url;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final host = FlygoBrowserHost.instance;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        color: cs.surface,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, minWidth: 320),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.verified_user_outlined, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
              if (url != null && url!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(url!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 16),
              ValueListenableBuilder<double?>(
                valueListenable: host.download,
                builder: (_, p, _) => LinearProgressIndicator(value: p, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: host.stage,
                builder: (_, s, _) => ValueListenableBuilder<double?>(
                  valueListenable: host.download,
                  builder: (_, p, _) => Text(
                    s.isEmpty ? tr('Đang mở trình duyệt Ký số…') : '${tr(s)}${p == null ? '' : ' ${(p * 100).round()}%'}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: onCancel, child: Text(tr('Ẩn')))),
            ]),
          ),
        ),
      ),
    );
  }
}
