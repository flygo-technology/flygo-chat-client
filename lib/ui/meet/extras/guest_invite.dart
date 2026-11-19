import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';
import 'fx_api.dart';

// "🔗 Thêm khách mời": bảng nhỏ để chủ trì / phó phòng bật link cho khách ngoài công ty và gửi đi (sao chép / chia sẻ).
// Cài đặt đầy đủ (duyệt khách, mời khách ra) vẫn ở "Quản lý cuộc họp".

/// Mở bảng mời khách (dùng ở menu cuộc họp và nút trong danh sách người).
Future<void> meetGuestInvite(BuildContext context, CallService call) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _GuestInviteSheet(call: call),
    );

class _GuestInviteSheet extends StatefulWidget {
  final CallService call;
  const _GuestInviteSheet({required this.call});
  @override
  State<_GuestInviteSheet> createState() => _GuestInviteSheetState();
}

class _GuestInviteSheetState extends State<_GuestInviteSheet> {
  Map<String, dynamic>? _link;
  bool _loading = true, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await fxRequest(widget.call, 'GET', '/guests');
      if (mounted) {
        setState(() {
          _link = (j['link'] as Map?)?.cast<String, dynamic>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _set(bool on) async {
    setState(() => _busy = true);
    try {
      final j = await fxRequest(widget.call, on ? 'POST' : 'DELETE', '/guests/link');
      if (mounted) setState(() => _link = on ? (j['link'] as Map?)?.cast<String, dynamic>() : null);
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _url => '${_link?['url'] ?? ''}';

  String _until() {
    final ms = (_link?['expires_at'] as num?)?.toInt() ?? 0;
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return tr('Hết hạn lúc {0}:{1} ngày {2}/{3}', [two(d.hour), two(d.minute), two(d.day), two(d.month)]);
  }

  @override
  Widget build(BuildContext context) {
    final on = _link != null;
    final title = widget.call.meetingInfo?.title ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('🔗 ${tr('Thêm khách mời')}', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(tr('Người ngoài công ty mở link trên trình duyệt, nhập tên rồi chờ chủ trì cho vào. Không cần tài khoản.'),
              style: const TextStyle(color: Colors.white70)),
          if (_loading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.white60)))
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Cho khách vào bằng link'), style: const TextStyle(color: Colors.white)),
              subtitle: Text(on ? _until() : tr('Tối đa 5 khách, link hết hạn sau 24 giờ'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
              value: on,
              onChanged: _busy ? null : _set,
            ),
            if (on) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFF3A3B3F), borderRadius: BorderRadius.circular(10)),
                child: SelectableText(_url, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _url));
                      if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Đã sao chép link cho khách'))));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(tr('Sao chép')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(ShareParams(
                      text: tr('Mời bạn vào cuộc họp "{0}": {1}', [title, _url]),
                      subject: title.isEmpty ? null : title,
                    )),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: Text(tr('Chia sẻ')),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(tr('Khi khách xin vào, bạn sẽ thấy thông báo "Cho vào". Duyệt hoặc mời khách ra trong "Quản lý cuộc họp".'),
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ],
        ]),
      ),
    );
  }
}
