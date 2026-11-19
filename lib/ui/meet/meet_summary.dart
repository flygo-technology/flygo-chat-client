import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart' show hhmm;
import 'meet_home.dart' show meetToast;

// "✨ Tóm tắt cuộc họp": ai trong cuộc họp cũng bấm được. Máy chủ gom phiên âm của Thư ký Họp + tin nhắn của cuộc họp, gọi
// Cổng AI (Mức Cơ bản, tính vào hạn mức của người bấm) và Thư ký Họp gửi một tin tóm tắt vào nhóm của cuộc họp.

/// Cuộc họp có gì để tóm tắt chưa (xem nhanh trên máy, không gọi máy chủ): có câu phiên âm hoặc tin nhắn của người sau thẻ.
bool meetingHasContent(AppState app, MmPost card) => app.postsOf(card.channelId).any((p) =>
    p.createAt > card.createAt &&
    p.deleteAt == 0 &&
    !p.isSystem &&
    p.props['flygo_meeting_summary'] == null &&
    (p.props['flygo_transcript'] is Map ||
        (p.props['from_bot'] == null && p.props['flygo_meeting_notice'] == null && p.message.trim().isNotEmpty)));

/// Bấm "✨ Tóm tắt cuộc họp": hỏi lại (số câu, phí tính vào hạn mức của mình), gửi yêu cầu, báo kết quả / lỗi.
Future<void> summarizeMeeting(BuildContext context, {required String channelId, String? code}) async {
  final app = context.read<AppState>();
  await discoverPush(kServerUrl);
  final path = code != null && code.isNotEmpty ? '/meet/rooms/$code/summary' : '/meet/livekit/channel/$channelId/summary';
  final headers = {'Authorization': 'Bearer ${app.token}', 'X-MM-Server': kServerUrl, 'Content-Type': 'application/json', 'User-Agent': kUserAgent};
  String errOf(http.Response r) {
    try {
      return '${(jsonDecode(utf8.decode(r.bodyBytes)) as Map)['error'] ?? r.statusCode}';
    } catch (_) {
      return 'HTTP ${r.statusCode}';
    }
  }

  Map info;
  try {
    final r = await http.get(Uri.parse('$kPushUrl$path'), headers: headers).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      if (context.mounted) meetToast(context, tr('Không tóm tắt được: {0}', [errOf(r)]));
      return;
    }
    info = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  } catch (e) {
    if (context.mounted) meetToast(context, tr('Không tóm tắt được: {0}', [e]));
    return;
  }
  if (!context.mounted) return;
  if (info['enabled'] != true) return meetToast(context, tr('Máy chủ chưa bật tóm tắt cuộc họp.'));
  final transcripts = (info['transcripts'] as num?)?.toInt() ?? 0, messages = (info['messages'] as num?)?.toInt() ?? 0;
  if (transcripts + messages == 0) {
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Chưa có gì để tóm tắt')),
        content: Text(tr('Cuộc họp chưa có phiên âm hay tin nhắn nào. Chủ phòng bật "Phiên âm" trong menu cuộc họp.')),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: Text(tr('Đóng')))],
      ),
    );
    return;
  }
  final last = info['last'] as Map?;
  final lastAt = last == null ? null : DateTime.fromMillisecondsSinceEpoch((last['at'] as num).toInt());
  final go = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.auto_awesome_rounded),
      title: Text(tr('Tóm tắt cuộc họp?')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Dựa trên {0} câu phiên âm và {1} tin nhắn tới lúc này. Bản tóm tắt gửi vào nhóm, mọi người cùng thấy.',
            [transcripts, messages])),
        const SizedBox(height: 8),
        Text(tr('Tính vào hạn mức AI của bạn (Mức Cơ bản).'), style: Theme.of(d).textTheme.bodySmall),
        if (lastAt != null) ...[
          const SizedBox(height: 8),
          Text(tr('Đã có bản tóm tắt lúc {0}. Bản mới gồm cả phần họp sau đó.', [hhmm(lastAt)]),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(lastAt != null ? tr('Tạo bản mới') : tr('Tóm tắt'))),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(minutes: 2),
    content: Row(children: [
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
      const SizedBox(width: 12),
      Expanded(child: Text(tr('Đang tóm tắt… thường mất 10–30 giây, tin sẽ hiện trong nhóm.'))),
    ]),
  ));
  try {
    final r = await http.post(Uri.parse('$kPushUrl$path'), headers: headers).timeout(const Duration(seconds: 120));
    messenger.hideCurrentSnackBar();
    // Lỗi của Cổng AI (hết hạn mức, chưa được mở AI…) đã là câu tiếng Việt đọc được: hiện nguyên văn.
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: r.statusCode == 200 ? 4 : 8),
      content: Text(r.statusCode == 200 ? tr('Đã gửi bản tóm tắt vào nhóm') : errOf(r)),
    ));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('Không tóm tắt được: {0}', [e]))));
  }
}
