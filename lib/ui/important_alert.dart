// Tin "Quan trọng" (priority important) của người khác: hộp thông báo giữa màn hình ngay khi nhận, kể cả khi đang
// không ở chat đó. Không phát âm thanh (khác tin Khẩn cấp). Bấm "Đã đọc" = xác nhận đã đọc tin.
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'theme.dart';

Future<void> showImportantAlert(BuildContext context, AppState app, MmPost p, {void Function(String channelId)? onOpen}) {
  final pal = Pal.of(context);
  final ch = app.channels[p.channelId];
  final group = ch == null ? '' : app.channelTitle(ch);
  final sender = app.users[p.userId]?.displayName ?? tr('Người dùng');
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (d) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: Color(0xFFF5A623), shape: BoxShape.circle),
                child: const Icon(Icons.priority_high_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Text(tr('Tin quan trọng'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFE08A1E))),
            ]),
            const SizedBox(height: 16),
            if (group.isNotEmpty)
              Text(group, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: pal.text), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(sender, style: TextStyle(fontSize: 14, color: pal.sub)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: SelectableText(p.message.isEmpty ? tr('(Tin có tệp đính kèm)') : p.message,
                    style: TextStyle(fontSize: 22, height: 1.35, fontWeight: FontWeight.w600, color: pal.text)),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              if (onOpen != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(d);
                    app.acknowledge(p).catchError((_) {});
                    onOpen(p.channelId);
                  },
                  child: Text(tr('Mở chat')),
                ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE08A1E), padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
                onPressed: () {
                  Navigator.pop(d);
                  app.acknowledge(p).catchError((_) {});
                },
                child: Text(tr('Đã đọc'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}
