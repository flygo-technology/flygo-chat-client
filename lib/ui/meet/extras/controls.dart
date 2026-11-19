import 'dart:async';

import 'package:flutter/material.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';
import 'fx_api.dart';

// Khoá cuộc họp + quyền của người tham gia. Trạng thái đến từ metadata phòng (call.roomExtras: {lock, perms});
// máy chủ thực thi ở token LiveKit, app chỉ ẩn / khoá nút cho đúng. Chủ trì / phó phòng luôn đủ quyền.

const _permKeys = ['share', 'unmute', 'camera', 'react', 'chat'];

Map<String, bool> meetPerms(CallService call) {
  final p = call.roomExtras['perms'];
  return {for (final k in _permKeys) k: p is Map ? p[k] != false : true};
}

/// Mình có quyền này trong cuộc họp hiện tại không (share / unmute / camera / react / chat).
bool meetPerm(CallService call, String key) => call.canModerate || meetPerms(call)[key] != false;

bool meetLocked(CallService call) => call.roomExtras['lock'] == true;

/// Cuộc họp đang khoá: xin chủ trì cho vào (chờ tối đa 90 giây). Trả về 'admitted' | 'denied' | 'timeout'.
Future<String> knockLockedMeeting(String code, {required String token}) async {
  try {
    final j = await fxSend('POST', '${fxRoomUrl(code)}/controls/knock', token, const {}, const Duration(seconds: 100));
    return (j['status'] as String?) ?? 'timeout';
  } on FxError catch (e) {
    if (e.status == 409) return 'timeout';
    rethrow;
  }
}

Future<void> showControls(BuildContext context, CallService call) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ControlsSheet(call: call),
    );

class _ControlsSheet extends StatefulWidget {
  final CallService call;
  const _ControlsSheet({required this.call});
  @override
  State<_ControlsSheet> createState() => _ControlsSheetState();
}

class _ControlsSheetState extends State<_ControlsSheet> {
  bool _lock = false;
  Map<String, bool> _perms = {for (final k in _permKeys) k: true};
  List<Map<String, dynamic>> _knocks = const [];
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _lock = meetLocked(widget.call);
    _perms = meetPerms(widget.call);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await fxRequest(widget.call, 'GET', '/controls');
      if (!mounted || _busy) return;
      setState(() {
        _lock = j['lock'] == true;
        final p = (j['perms'] as Map?) ?? const {};
        _perms = {for (final k in _permKeys) k: p[k] != false};
        _knocks = [for (final k in (j['knocks'] as List? ?? const [])) (k as Map).cast<String, dynamic>()];
      });
    } catch (_) {}
  }

  Future<void> _save(Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      final j = await fxRequest(widget.call, 'POST', '/controls', body);
      if (!mounted) return;
      setState(() {
        _lock = j['lock'] == true;
        final p = (j['perms'] as Map?) ?? const {};
        _perms = {for (final k in _permKeys) k: p[k] != false};
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _admit(String req, bool allow) async {
    try {
      await fxRequest(widget.call, 'POST', '/controls/admit', {'req': req, 'allow': allow});
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    }
    await _load();
  }

  Widget _switch(String title, String? sub, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        value: value,
        onChanged: _busy ? null : onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final labels = {
      'share': tr('Chia sẻ màn hình'),
      'chat': tr('Gửi tin nhắn'),
      'unmute': tr('Tự bật mic'),
      'camera': tr('Bật camera'),
      'react': tr('Thả cảm xúc'),
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Quản lý cuộc họp'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _switch('🔒 ${tr('Khoá cuộc họp')}', tr('Không ai vào thêm được, kể cả người được mời. Người đến sau phải xin vào.'), _lock,
                (v) => _save({'lock': v})),
            if (_knocks.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(tr('Đang xin vào'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
              for (final k in _knocks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.meeting_room_outlined, color: Colors.white70),
                  title: Text('${k['name'] ?? ''}', style: const TextStyle(color: Colors.white)),
                  trailing: Wrap(spacing: 4, children: [
                    TextButton(onPressed: () => _admit('${k['req']}', false), child: Text(tr('Từ chối'))),
                    FilledButton(onPressed: () => _admit('${k['req']}', true), child: Text(tr('Cho vào'))),
                  ]),
                ),
            ],
            const Divider(height: 24, color: Colors.white12),
            Text(tr('Mọi người được phép'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
            for (final k in _permKeys)
              _switch(labels[k]!, k == 'chat' ? tr('Ẩn ô chat của cuộc họp trên app') : null, _perms[k] != false,
                  (v) => _save({'perms': {k: v}})),
            const SizedBox(height: 4),
            Text(tr('Chủ trì và phó phòng luôn có đủ quyền.'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// Báo cho chủ trì / phó phòng khi có người xin vào lúc cuộc họp khoá, và cho mọi người khi khoá / mở khoá.
StreamSubscription<Map<String, dynamic>> listenControlNotices(BuildContext context, CallService call, void Function(String text) toast) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return call.fxEvents.stream.listen((m) {
      final by = (m['by_name'] as String?)?.trim();
      final who = by?.isNotEmpty == true ? by! : tr('Chủ trì');
      if (m['t'] == 'fx_lock') toast(m['lock'] == true ? tr('{0} đã khoá cuộc họp', [who]) : tr('{0} đã mở khoá cuộc họp', [who]));
      if (m['t'] == 'fx_lock_knock' && call.canModerate) {
        final req = '${m['req'] ?? ''}';
        messenger?.showSnackBar(SnackBar(
          duration: const Duration(seconds: 30),
          content: Text(tr('🚪 {0} xin vào cuộc họp đang khoá', [m['name'] ?? ''])),
          action: SnackBarAction(
            label: tr('Cho vào'),
            onPressed: () => fxRequest(call, 'POST', '/controls/admit', {'req': req, 'allow': true}).catchError((_) => <String, dynamic>{}),
          ),
        ));
      }
    });
}
