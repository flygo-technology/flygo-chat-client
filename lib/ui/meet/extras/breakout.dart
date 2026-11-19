import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';
import 'fx_api.dart';

// Chia phòng nhóm. Chủ trì tạo phòng (relay giữ trạng thái ở metadata phòng chính: breakout), app của người được xếp phòng
// tự chuyển sang phòng nhóm (call.switchLiveKitRoom) sau 10 giây; hết giờ / chủ trì gọi về thì tự về phòng chính.
// Ở phòng nhóm không nhận metadata phòng chính nên mọi thay đổi còn được báo bằng tin dữ liệu fx_breakout_*.

final _dev = 'br${Random().nextInt(1 << 30).toRadixString(36)}';

Map<String, dynamic> _state(CallService call) => (call.roomExtras['breakout'] as Map?)?.cast<String, dynamic>() ?? const {};
bool breakoutOn(CallService call) => _state(call)['on'] == true;

Future<void> _go(CallService call, int? n) async {
  final j = await fxRequest(call, 'POST', '/breakout/token', {'device': _dev, 'n': ?n});
  await call.switchLiveKitRoom(url: j['url'] as String, token: j['token'] as String, label: '${j['name'] ?? ''}');
}

/// Nghe trạng thái phòng nhóm: tự chuyển phòng, đếm ngược khi gọi về, thông báo, nhờ giúp (chủ trì).
StreamSubscription<void> listenBreakout(BuildContext context, CallService call, void Function(String text) toast) {
  ScaffoldMessengerState? messenger() => context.mounted ? ScaffoldMessenger.maybeOf(context) : null;
  Timer? pending;
  var lastKey = '';
  void later(Duration d, Future<void> Function() f) {
    pending?.cancel();
    pending = Timer(d, () => f().catchError((Object e) => toast('$e')));
  }

  // Bắt đầu chia phòng (metadata phòng chính): người được xếp phòng tự sang sau 10 giây.
  void changed() {
    final st = _state(call);
    final key = st['on'] == true ? '${st['started_at']}' : '';
    if (key == lastKey) return;
    lastKey = key;
    if (key.isEmpty || call.canModerate || call.currentBreakout != null) return;
    final n = ((st['assign'] as Map?)?[call.myId()] as num?)?.toInt() ?? 0;
    if (n == 0) return;
    final name = [for (final r in (st['rooms'] as List? ?? const [])) if ((r as Map)['n'] == n) '${r['name']}'].firstOrNull ?? tr('Phòng {0}', [n]);
    messenger()?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 10),
      content: Text(tr('Bạn được chuyển sang {0} sau 10 giây', [name])),
      action: SnackBarAction(label: tr('Sang ngay'), onPressed: () => later(Duration.zero, () => _go(call, null))),
    ));
    later(const Duration(seconds: 10), () => _go(call, null));
  }

  final sub = call.fxEvents.stream.listen((m) {
    final by = (m['by_name'] as String?)?.trim();
    switch (m['t']) {
      case 'fx_breakout_end':
        pending?.cancel();
        if (call.currentBreakout == null) return;
        final secs = (m['seconds'] as num?)?.toInt() ?? 60;
        messenger()?.showSnackBar(SnackBar(
          duration: Duration(seconds: secs),
          content: Text(tr('Chủ trì gọi mọi người về phòng chính sau {0} giây', [secs])),
          action: SnackBarAction(label: tr('Về ngay'), onPressed: () => later(Duration.zero, call.returnToMainRoom)),
        ));
        later(Duration(seconds: secs), call.returnToMainRoom);
      case 'fx_breakout_move':
        final n = (m['n'] as num?)?.toInt() ?? 0;
        if (n == 0) {
          toast(tr('Chủ trì đã đưa bạn về phòng chính'));
          later(Duration.zero, call.returnToMainRoom);
        } else {
          toast(tr('Chủ trì chuyển bạn sang {0}', [m['room_name'] ?? n]));
          later(const Duration(seconds: 2), () => _go(call, null));
        }
      case 'fx_breakout_msg':
        toast('📣 ${by?.isNotEmpty == true ? by : tr('Chủ trì')}: ${m['text'] ?? ''}');
      case 'fx_breakout_help':
        if (!call.canModerate) return;
        final n = (m['n'] as num?)?.toInt() ?? 0;
        messenger()?.showSnackBar(SnackBar(
          duration: const Duration(seconds: 30),
          content: Text(tr('🙋 {0} ở {1} cần chủ trì giúp', [m['name'] ?? '', m['room_name'] ?? n])),
          action: n > 0 ? SnackBarAction(label: tr('Ghé phòng'), onPressed: () => later(Duration.zero, () => _go(call, n))) : null,
        ));
    }
  });
  call.addListener(changed);
  final c = StreamController<void>(onCancel: () {
    call.removeListener(changed);
    sub.cancel();
    pending?.cancel();
  });
  return c.stream.listen(null);
}

Future<void> showBreakout(BuildContext context, CallService call) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _BreakoutSheet(call: call),
    );

class _BreakoutSheet extends StatefulWidget {
  final CallService call;
  const _BreakoutSheet({required this.call});
  @override
  State<_BreakoutSheet> createState() => _BreakoutSheetState();
}

class _BreakoutSheetState extends State<_BreakoutSheet> {
  int _rooms = 3, _minutes = 10;
  Map<String, dynamic> _st = const {};
  Map<String, dynamic> _counts = const {};
  bool _busy = false;
  final _msg = TextEditingController();
  Timer? _tick;

  CallService get call => widget.call;

  @override
  void initState() {
    super.initState();
    _st = _state(call);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _msg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await fxRequest(call, 'GET', '/breakout');
      if (!mounted) return;
      setState(() {
        _st = (j['breakout'] as Map?)?.cast<String, dynamic>() ?? const {};
        _counts = (j['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
      });
    } catch (_) {}
  }

  Future<void> _do(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _left() {
    final end = (_st['ends_at'] as num?)?.toInt() ?? 0;
    if (end <= 0) return '';
    final s = ((end - DateTime.now().millisecondsSinceEpoch) / 1000).round();
    if (s <= 0) return tr('hết giờ');
    return tr('còn {0}:{1}', [s ~/ 60, (s % 60).toString().padLeft(2, '0')]);
  }

  Widget _host() {
    final on = _st['on'] == true;
    if (!on) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Chia người đang họp vào các phòng nhỏ để thảo luận. Chủ trì và phó phòng ghé được mọi phòng.'),
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(tr('Số phòng'), style: const TextStyle(color: Colors.white))),
          IconButton(onPressed: _rooms > 2 ? () => setState(() => _rooms--) : null, icon: const Icon(Icons.remove_circle_outline, color: Colors.white70)),
          Text('$_rooms', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          IconButton(onPressed: _rooms < 10 ? () => setState(() => _rooms++) : null, icon: const Icon(Icons.add_circle_outline, color: Colors.white70)),
        ]),
        Row(children: [
          Expanded(child: Text(tr('Thời gian'), style: const TextStyle(color: Colors.white))),
          DropdownButton<int>(
            value: _minutes,
            dropdownColor: const Color(0xFF3A3B3F),
            style: const TextStyle(color: Colors.white),
            items: [for (final m in [0, 5, 10, 15, 20, 30, 45]) DropdownMenuItem(value: m, child: Text(m == 0 ? tr('Không giới hạn') : tr('{0} phút', [m])))],
            onChanged: (v) => setState(() => _minutes = v ?? 10),
          ),
        ]),
        const SizedBox(height: 4),
        Text(tr('Người đang họp được chia đều ngẫu nhiên; chủ trì có thể chuyển từng người sau.'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _do(() => fxRequest(call, 'POST', '/breakout', {'rooms': _rooms, 'minutes': _minutes})),
          child: Text(tr('Mở phòng nhóm')),
        ),
      ]);
    }
    final rooms = [for (final r in (_st['rooms'] as List? ?? const [])) (r as Map).cast<String, dynamic>()];
    final assign = (_st['assign'] as Map?) ?? const {};
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_left().isNotEmpty) Text('⏱ ${_left()}', style: const TextStyle(color: Colors.white70)),
      for (final r in rooms)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.meeting_room_outlined, color: Colors.white70),
          title: Text('${r['name']}', style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            tr('{0} người được xếp · {1} đang trong phòng', [assign.values.where((v) => v == r['n']).length, _counts['${r['n']}'] ?? 0]),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: call.currentBreakout == r['name']
              ? Text(tr('Bạn đang ở đây'), style: const TextStyle(color: Color(0xFF8AB4F8), fontSize: 12))
              : TextButton(onPressed: _busy ? null : () => _do(() => _go(call, (r['n'] as num).toInt())), child: Text(tr('Ghé'))),
        ),
      if (call.currentBreakout != null)
        TextButton.icon(onPressed: () => _do(call.returnToMainRoom), icon: const Icon(Icons.home_outlined), label: Text(tr('Về phòng chính'))),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _msg,
            maxLength: 300,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: tr('Gửi thông báo tới mọi phòng…'),
              hintStyle: const TextStyle(color: Colors.white38),
              counterText: '',
              filled: true,
              fillColor: const Color(0xFF3A3B3F),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        IconButton(
          onPressed: _busy
              ? null
              : () {
                  final t = _msg.text.trim();
                  if (t.isEmpty) return;
                  _msg.clear();
                  _do(() => fxRequest(call, 'POST', '/breakout/broadcast', {'text': t}));
                },
          icon: const Icon(Icons.campaign_outlined, color: Colors.white),
        ),
      ]),
      const SizedBox(height: 12),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEA4C4C)),
        onPressed: _busy ? null : () => _do(() => fxRequest(call, 'POST', '/breakout/end')),
        child: Text(tr('Gọi mọi người về')),
      ),
    ]);
  }

  Widget _participant() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Bạn đang ở {0}', [call.currentBreakout?.isNotEmpty == true ? call.currentBreakout! : tr('phòng nhóm')]),
            style: const TextStyle(color: Colors.white)),
        if (_left().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('⏱ ${_left()}', style: const TextStyle(color: Colors.white70))),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _do(() async {
                    await fxRequest(call, 'POST', '/breakout/help');
                    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('Đã nhờ chủ trì vào giúp'))));
                  }),
          icon: const Text('🙋'),
          label: Text(tr('Nhờ chủ trì giúp')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _busy ? null : () => _do(call.returnToMainRoom), icon: const Icon(Icons.home_outlined), label: Text(tr('Về phòng chính'))),
      ]);

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Phòng nhóm'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (call.canModerate) _host() else _participant(),
            ]),
          ),
        ),
      );
}
