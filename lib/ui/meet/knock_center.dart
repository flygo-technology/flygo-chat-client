import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import 'extras/fx_api.dart';

// Người xin vào cuộc họp (khách qua link mời, người xin vào lúc cuộc họp khoá): chủ trì / phó phòng thấy một hộp lớn
// (Cho vào / Từ chối / Cho tất cả vào) ở mọi màn hình của app, kể cả khi đang ở khung nổi hay nhóm chat, kèm một tiếng
// báo trên máy này. Nhận tin tức thời (fx_guest_knock / fx_lock_knock) và hỏi lại relay mỗi 4 giây phòng khi lỡ tin.

/// Số người đang chờ (huy hiệu nút ⋯).
final meetKnockCount = ValueNotifier<int>(0);

class _Knock {
  final String req, name, kind; // kind: guest | lock
  _Knock(this.req, this.name, this.kind);
}

class MeetKnockLayer extends StatefulWidget {
  final CallService call;
  final Widget child;
  const MeetKnockLayer({super.key, required this.call, required this.child});
  @override
  State<MeetKnockLayer> createState() => _MeetKnockLayerState();
}

class _MeetKnockLayerState extends State<MeetKnockLayer> {
  final Map<String, _Knock> _knocks = {};
  final Set<String> _seen = {};
  StreamSubscription? _sub;
  Timer? _poll;
  bool _busy = false;

  CallService get call => widget.call;
  bool get _active => call.busy && call.meeting && call.canModerate && (call.meetingInfo?.code ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _sub = call.fxEvents.stream.listen((m) {
      final t = '${m['t']}';
      if ((t == 'fx_guest_knock' || t == 'fx_lock_knock') && call.canModerate) {
        _add(_Knock('${m['req'] ?? ''}', '${m['name'] ?? ''}', t == 'fx_guest_knock' ? 'guest' : 'lock'));
      } else if (t == 'fx_guest_knock_done' || t == 'fx_lock_knock_done') {
        _remove('${m['req'] ?? ''}');
      }
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _add(_Knock k) {
    if (k.req.isEmpty || _knocks.containsKey(k.req)) return;
    setState(() => _knocks[k.req] = k);
    meetKnockCount.value = _knocks.length;
    // Một tiếng báo trên máy chủ trì cho mỗi người mới xin vào.
    if (_seen.add(k.req)) SystemSound.play(SystemSoundType.alert);
  }

  void _remove(String req) {
    if (_knocks.remove(req) == null) return;
    if (mounted) setState(() {});
    meetKnockCount.value = _knocks.length;
  }

  /// Hỏi relay danh sách đang chờ (khách + xin vào lúc khoá); tin tức thời có thể lỡ khi mạng chập chờn.
  Future<void> _refresh() async {
    if (!_active) {
      if (_knocks.isNotEmpty) {
        setState(_knocks.clear);
        meetKnockCount.value = 0;
      }
      return;
    }
    final now = <String, _Knock>{};
    for (final (path, kind) in const [('/guests', 'guest'), ('/controls', 'lock')]) {
      try {
        final j = await fxRequest(call, 'GET', path);
        for (final k in (j['knocks'] as List? ?? const [])) {
          final m = (k as Map).cast<String, dynamic>();
          now['${m['req']}'] = _Knock('${m['req']}', '${m['name'] ?? ''}', kind);
        }
      } catch (_) {
        // Tính năng thêm chưa có / không có quyền: giữ danh sách hiện tại của loại này.
        for (final k in _knocks.values.where((x) => x.kind == kind)) {
          now[k.req] = k;
        }
      }
    }
    if (!mounted) return;
    for (final k in now.values) {
      _add(k);
    }
    for (final r in _knocks.keys.toList()) {
      if (!now.containsKey(r)) _remove(r);
    }
  }

  Future<void> _answer(_Knock k, bool allow) async {
    _remove(k.req);
    try {
      await fxRequest(call, 'POST', k.kind == 'guest' ? '/guests/admit' : '/controls/admit', {'req': k.req, 'allow': allow});
    } catch (_) {}
  }

  Future<void> _all() async {
    setState(() => _busy = true);
    for (final k in _knocks.values.toList()) {
      await _answer(k, true);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Một người chờ: máy rộng một hàng; điện thoại tên trên, nút dưới (không bóp tên).
  Widget _item(_Knock k, bool narrow) {
    final who = Row(
      children: [
        CircleAvatar(
          backgroundColor: k.kind == 'guest' ? const Color(0xFF3E5A75) : const Color(0xFF3D3010),
          child: Text(k.name.trim().isEmpty ? '?' : k.name.trim()[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                k.name.isEmpty ? tr('Không tên') : k.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
              ),
              Text(
                k.kind == 'guest' ? tr('Khách ngoài công ty (qua link mời)') : tr('Xin vào lúc cuộc họp đang khoá'),
                style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => _answer(k, false),
          child: Text(tr('Từ chối'), style: const TextStyle(color: Color(0xFF9AA0A6))),
        ),
        const SizedBox(width: 4),
        FilledButton(onPressed: () => _answer(k, true), child: Text(tr('Cho vào'))),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.end, children: [who, const SizedBox(height: 6), buttons])
          : Row(
              children: [
                Expanded(child: who),
                buttons,
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _active ? _knocks.values.toList() : const <_Knock>[];
    return Stack(
      children: [
        widget.child,
        if (list.isNotEmpty) ...[
          const Positioned.fill(child: ModalBarrier(color: Colors.black54, dismissible: false)),
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Material(
                  color: const Color(0xFF2D2E31),
                  borderRadius: BorderRadius.circular(20),
                  elevation: 6,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.door_front_door_outlined, color: Color(0xFFFFD36B)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  list.length == 1 ? tr('Có người xin vào cuộc họp') : tr('{0} người xin vào cuộc họp', [list.length]),
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Flexible(child: ListView(shrinkWrap: true, children: [for (final k in list) _item(k, MediaQuery.sizeOf(context).width < 480)])),
                          if (list.length > 1) ...[
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(onPressed: _busy ? null : _all, icon: const Icon(Icons.done_all_rounded), label: Text(tr('Cho tất cả vào'))),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
