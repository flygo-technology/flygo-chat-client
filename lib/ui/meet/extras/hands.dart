import 'dart:async';

import 'package:flutter/material.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';
import 'fx_api.dart';

// Giơ tay theo thứ tự: số thứ tự trên ô / danh sách người, bảng "Hàng chờ giơ tay" (chủ trì hạ tay từng người / tất cả).
// Thứ tự theo mốc giơ tay (thuộc tính LiveKit `hand` = ms); app cũ không có mốc -> cuối hàng. Hạ tay người khác qua relay.

class HandEntry {
  final String userId;
  final int raisedAt;
  final bool me;
  const HandEntry(this.userId, this.raisedAt, {this.me = false});
}

/// Hàng chờ hiện tại (gồm cả mình), mỗi người một dòng (nhiều máy: lấy mốc sớm nhất).
List<HandEntry> handQueue(CallService call) {
  final by = <String, int>{};
  void add(String uid, int at) {
    final v = at > 0 ? at : 1 << 62; // không có mốc: cuối hàng
    if (!by.containsKey(uid) || v < by[uid]!) by[uid] = v;
  }

  final me = call.myId();
  if (call.handRaised) add(me, call.myHandAt);
  for (final p in call.participants) {
    if (p.raisedHand && !p.userId.startsWith('agent:')) add(p.userId, p.raisedAt);
  }
  final list = by.entries.map((e) => HandEntry(e.key, e.value == 1 << 62 ? 0 : e.value, me: e.key == me)).toList()
    ..sort((a, b) => (a.raisedAt == 0 ? 1 << 62 : a.raisedAt).compareTo(b.raisedAt == 0 ? 1 << 62 : b.raisedAt));
  return list;
}

/// Số thứ tự giơ tay của một người (1, 2…), null nếu không giơ tay.
int? meetHandOrder(CallService call, String userId) {
  final q = handQueue(call);
  final i = q.indexWhere((h) => h.userId == userId);
  return i < 0 ? null : i + 1;
}

/// Huy hiệu ✋ kèm số thứ tự (thay cho biểu tượng bàn tay trơn).
class MeetHandBadge extends StatelessWidget {
  final int? order;
  final double size;
  const MeetHandBadge({super.key, this.order, this.size = 18});
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: size * .4, vertical: size * .1),
        decoration: BoxDecoration(color: const Color(0xFFF2C14E), borderRadius: BorderRadius.circular(size)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.back_hand, color: const Color(0xFF2A2000), size: size * .85),
          if (order != null) ...[
            SizedBox(width: size * .2),
            Text('$order', style: TextStyle(color: const Color(0xFF2A2000), fontWeight: FontWeight.w700, fontSize: size * .75)),
          ],
        ]),
      );
}

Future<void> lowerHandOf(CallService call, String userId) => fxRequest(call, 'POST', '/hands/lower', {'user_id': userId});
Future<void> lowerAllHands(CallService call) => fxRequest(call, 'POST', '/hands/lower', {'all': true});

String _ago(int ms) {
  if (ms <= 0) return '';
  final s = DateTime.now().millisecondsSinceEpoch - ms;
  if (s < 60000) return tr('vừa xong');
  return tr('{0} phút trước', [s ~/ 60000]);
}

/// Bảng "Hàng chờ giơ tay". nameOf: tên hiển thị của một người (màn hình họp có sẵn hàm này).
Future<void> showHandQueue(BuildContext context, CallService call, String Function(String userId) nameOf) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _HandQueueSheet(call: call, nameOf: nameOf),
    );

class _HandQueueSheet extends StatefulWidget {
  final CallService call;
  final String Function(String) nameOf;
  const _HandQueueSheet({required this.call, required this.nameOf});
  @override
  State<_HandQueueSheet> createState() => _HandQueueSheetState();
}

class _HandQueueSheetState extends State<_HandQueueSheet> {
  final _busy = <String>{};
  Timer? _tick; // cập nhật "x phút trước"

  @override
  void initState() {
    super.initState();
    widget.call.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _changed());
  }

  @override
  void dispose() {
    widget.call.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(String key, Future<void> Function() f) async {
    setState(() => _busy.add(key));
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final q = handQueue(call);
    final host = call.canModerate;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(tr('Hàng chờ giơ tay · {0}', [q.length]),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            if (host && q.length > 1)
              TextButton(
                onPressed: _busy.contains('*') ? null : () => _run('*', () => lowerAllHands(call)),
                child: Text(tr('Hạ tất cả')),
              ),
          ]),
          const SizedBox(height: 8),
          if (q.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(tr('Chưa ai giơ tay'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final (i, h) in q.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: MeetHandBadge(order: i + 1, size: 22),
                  title: Text(h.me ? tr('Bạn') : widget.nameOf(h.userId),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  subtitle: h.raisedAt > 0
                      ? Text(tr('giơ tay {0}', [_ago(h.raisedAt)]), style: const TextStyle(color: Colors.white54, fontSize: 12))
                      : null,
                  trailing: h.me
                      ? TextButton(onPressed: call.lowerHand, child: Text(tr('Hạ tay')))
                      : host
                          ? TextButton(
                              onPressed: _busy.contains(h.userId) ? null : () => _run(h.userId, () => lowerHandOf(call, h.userId)),
                              child: Text(tr('Hạ tay')),
                            )
                          : null,
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Báo nhanh khi chủ trì hạ tay mình / mọi người (tin dữ liệu fx_* trên chủ đề `flygo`).
StreamSubscription<Map<String, dynamic>> listenHandNotices(CallService call, void Function(String text) toast) =>
    call.fxEvents.stream.listen((m) {
      final by = (m['by_name'] as String?)?.trim();
      if (m['t'] == 'fx_hand_lowered') toast(tr('{0} đã hạ tay bạn', [by?.isNotEmpty == true ? by : tr('Chủ trì')]));
      if (m['t'] == 'fx_hands_lowered') toast(tr('{0} đã hạ tay mọi người', [by?.isNotEmpty == true ? by : tr('Chủ trì')]));
    });
