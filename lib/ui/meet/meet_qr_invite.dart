import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../config.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../mini_app_view.dart' show ScanOncePage;
import 'meet_home.dart' show meetToast;

// "Mời bằng QR code" trong cuộc họp: TV / máy dùng chung mở trang meet.<tên miền> (chỉ có mã QR). Người đang họp quét
// mã, đặt tên thiết bị; thiết bị vào thẳng cuộc họp này (camera + micro), trong nhóm hiện tin ai đã mời.

/// Mã ghép trong nội dung mã QR / link / mã gõ tay. Null = không phải mã của Họp.
String? parsePairCode(String raw) {
  final s = raw.trim();
  final m = RegExp(r'/hop/pair/([A-Za-z0-9_-]{6,20})(?:[/?#]|$)').firstMatch(s);
  if (m != null) return m[1];
  // Mã gõ tay (hiện dưới mã QR): 12 chữ hoa / số, có hoặc không có gạch nối.
  final bare = s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return RegExp(r'^[A-Z0-9]{12}$').hasMatch(bare) ? bare : null;
}

String _lastName = '';

Future<void> inviteDeviceByQr(BuildContext context, CallService call) async {
  final app = context.read<AppState>();
  final ch = call.channelId;
  if (ch == null) return;
  // 1. Quét mã (điện thoại) hoặc dán link / mã hiện dưới mã QR (máy tính).
  String? raw;
  if (!Platform.isAndroid && !Platform.isIOS) {
    raw = await _askText(context,
        title: tr('Mời bằng QR code'),
        hint: tr('Dán link hoặc mã hiện dưới mã QR trên màn hình thiết bị'),
        label: tr('Link / mã'),
        ok: tr('Tiếp'));
  } else {
    raw = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(builder: (_) => const ScanOncePage()));
  }
  if (raw == null || !context.mounted) return;
  final code = parsePairCode(raw);
  if (code == null) {
    meetToast(context, tr('Mã này không phải mã mời thiết bị của Họp'));
    return;
  }
  // 2. Tên thiết bị (người khác thấy "<tên> · mời bởi <bạn> (QR)").
  final name = await _askText(context,
      title: tr('Tên thiết bị'),
      hint: tr('Mọi người thấy tên này trong cuộc họp, kèm "mời bởi {0}".', [app.me?.displayName ?? tr('bạn')]),
      label: tr('Tên'),
      initial: _lastName.isEmpty ? tr('TV phòng họp') : _lastName,
      ok: tr('Mời vào cuộc họp'));
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  _lastName = name.trim();
  // 3. Mời.
  try {
    await discoverPush(kServerUrl);
    final c = call.meetingInfo?.code;
    final r = await http
        .post(Uri.parse('$kPushUrl/meet/devices/pair/$code/invite'),
            headers: {'Authorization': 'Bearer ${app.token}', 'X-MM-Server': kServerUrl, 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
            body: jsonEncode({if (c != null && c.isNotEmpty) 'code': c else 'channel_id': ch, 'name': name.trim()}))
        .timeout(const Duration(seconds: 15));
    Map j = const {};
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    } catch (_) {}
    if (!context.mounted) return;
    if (r.statusCode != 200) {
      meetToast(context, tr('Không mời được: {0}', ['${j['error'] ?? r.statusCode}']));
      return;
    }
    meetToast(context, tr('Đã mời {0} vào cuộc họp', [name.trim()]));
  } catch (e) {
    if (context.mounted) meetToast(context, tr('Không mời được: {0}', [e]));
  }
}

Future<String?> _askText(BuildContext context, {required String title, required String hint, required String label, String initial = '', required String ok}) {
  final ctl = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(hint),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            autofocus: true,
            maxLength: 60,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(d, v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(ok)),
      ],
    ),
  );
}
