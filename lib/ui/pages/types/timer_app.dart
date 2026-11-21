import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
import '../page_types.dart';
import 'timer.dart' show fmtClock;

// Bấm giờ theo mockup "mỗi trang là một app" (21/11/2026): lượt phát biểu có giờ.
// - TimerPanel (người xem): vòng giờ (xanh -> vàng dưới 1 phút -> đỏ hết giờ), thứ tự nói, xin / rút lượt; người đang nói xin thêm
//   1 phút hoặc nói xong.
// - TimerControls (chủ trang): chạy / dừng, +1 phút (duyệt yêu cầu), người kế, giờ mỗi lượt, thứ tự nói (đổi chỗ, gọi ngay, bỏ, thêm).

const _green = Color(0xFF38C793), _amber = Color(0xFFF5B544), _red = Color(0xFFF0646A);

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) meetToast(context, '$e');
  }
}

/// Đồng hồ theo mốc của máy chủ (bù lệch giờ chỉ khi có view mới), vẽ lại 4 lần / giây khi đang chạy.
mixin _Clock<T extends StatefulWidget> on State<T> {
  Map<String, dynamic> get v;
  Timer? _tick;
  int _skew = 0;
  int? _syncedNow;

  void _sync() {
    final now = (v['now'] as num?)?.toInt();
    if (now == null || now == _syncedNow) return;
    _syncedNow = now;
    _skew = now - DateTime.now().millisecondsSinceEpoch;
  }

  void startClock() {
    _sync();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && v['running'] == true) setState(() {});
    });
  }

  @override
  void didUpdateWidget(T old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get countdown => v['mode'] != 'stopwatch';
  int get durationMs => (v['duration_ms'] as num?)?.toInt() ?? 0;
  int get elapsed {
    final base = (v['elapsed_ms'] as num?)?.toInt() ?? 0;
    if (v['running'] != true) return base;
    return base + (DateTime.now().millisecondsSinceEpoch + _skew - ((v['started_at'] as num?)?.toInt() ?? 0));
  }

  int get shown => countdown ? (durationMs - elapsed).clamp(0, 1 << 40) : elapsed;
  bool get over => countdown && shown <= 0 && elapsed > 0;
  Color get ringColor => over ? _red : (countdown && shown <= 60000 && elapsed > 0 ? _amber : _green);
  double get frac => countdown && durationMs > 0 ? (shown / durationMs).clamp(0.0, 1.0) : 1.0;
  List<Map<String, dynamic>> get queue => [for (final x in (v['queue'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
  String get current => queue.where((x) => x['current'] == true).map((x) => '${x['name']}').firstOrNull ?? '';
}

class TimerPanel extends StatefulWidget {
  final PageCtx ctx;
  const TimerPanel(this.ctx, {super.key});
  @override
  State<TimerPanel> createState() => _TimerPanelState();
}

class _TimerPanelState extends State<TimerPanel> with _Clock<TimerPanel> {
  @override
  Map<String, dynamic> get v => widget.ctx.view;

  @override
  void initState() {
    super.initState();
    startClock();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), t = s.theme;
    final ctx = widget.ctx;
    final q = queue;
    final myTurn = (v['my_turn'] as num?)?.toInt() ?? -1;
    final speaking = myTurn >= 0 && q.length > myTurn && q[myTurn]['current'] == true;
    final more = (v['more_req'] as Map?)?.cast<String, dynamic>();
    final ring = AppProgressRing(
      value: frac,
      size: s.compact ? 150 : 210,
      stroke: s.compact ? 10 : 13,
      color: ringColor,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(fmtClock(shown), style: TextStyle(color: over ? _red : (ringColor == _amber ? (t.light ? const Color(0xFFB7791F) : const Color(0xFFF8D58F)) : t.text), fontSize: s.compact ? 40 : 56, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
        Text(countdown ? tr('còn lại / {0}', [fmtClock(durationMs)]) : tr('đã chạy'), style: TextStyle(color: t.sub, fontSize: 12.5)),
      ]),
    );
    final status = over
        ? tr('Hết giờ')
        : v['running'] != true
            ? tr('Đang dừng')
            : (countdown && shown <= 60000 ? tr('Còn dưới 1 phút') : '');
    final head = Column(mainAxisSize: MainAxisSize.min, children: [
      if (current.isNotEmpty) AppChip(tr('ĐANG NÓI · {0}', [current.toUpperCase()])),
      SizedBox(height: s.compact ? 8 : 14),
      ring,
      if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status, style: TextStyle(color: over ? _red : (t.light ? const Color(0xFFB7791F) : _amber), fontWeight: FontWeight.w600, fontSize: 13))),
    ]);
    final actions = <Widget>[
      if (speaking) ...[
        Row(children: [
          Expanded(
            child: AppButton(
              more?['me'] == true ? tr('Đã xin thêm 1 phút') : tr('Xin thêm 1 phút'),
              key: const ValueKey('timer-more'),
              kind: AppButtonKind.warn,
              onPressed: more?['me'] == true ? null : () => _run(context, () => ctx.act('more')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: AppButton(tr('Nói xong'), key: const ValueKey('timer-finish'), kind: AppButtonKind.success, onPressed: () => _run(context, () => ctx.act('finish')))),
        ]),
      ] else if (ctx.data.role != 'viewer')
        AppButton(
          myTurn >= 0 ? tr('Rút khỏi thứ tự nói') : tr('Xin lượt nói'),
          key: const ValueKey('timer-join'),
          kind: myTurn >= 0 ? AppButtonKind.tonal : AppButtonKind.primary,
          onPressed: () => _run(context, () => ctx.act(myTurn >= 0 ? 'leave' : 'join')),
        ),
    ];
    final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (q.isNotEmpty) AppSectionLabel(tr('Thứ tự nói')),
      for (final (i, x) in q.indexed.where((e) => e.$2['done'] != true).take(s.compact ? 3 : 6))
        _QueueRow(name: x['me'] == true ? tr('Bạn') : '${x['name']}', current: x['current'] == true, trailing: x['current'] == true ? fmtClock(shown) : (i == q.indexWhere((y) => y['current'] == true) + 1 ? tr('tiếp theo') : '${i + 1}')),
    ]);
    if (s.compact) {
      return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, const SizedBox(height: 10), ...actions]));
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        const SizedBox(height: 14),
        list,
        if (actions.isNotEmpty) ...[const SizedBox(height: 10), ...actions],
      ]),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final String name, trailing;
  final bool current;
  final Widget? lead, tail;
  const _QueueRow({super.key, required this.name, required this.current, required this.trailing, this.lead, this.tail});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(12), border: current ? Border.all(color: _amber, width: 1.5) : null),
      child: Row(children: [
        ?lead,
        AppAvatar(name, size: 28),
        const SizedBox(width: 10),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontWeight: current ? FontWeight.w700 : FontWeight.w500))),
        Text(trailing, style: TextStyle(color: t.sub, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
        ?tail,
      ]),
    );
  }
}

class TimerControls extends StatefulWidget {
  final PageCtx ctx;
  const TimerControls(this.ctx, {super.key});
  @override
  State<TimerControls> createState() => _TimerControlsState();
}

class _TimerControlsState extends State<TimerControls> with _Clock<TimerControls> {
  final _name = TextEditingController();

  @override
  Map<String, dynamic> get v => widget.ctx.view;

  @override
  void initState() {
    super.initState();
    startClock();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _act(String a, [Map<String, dynamic> b = const {}]) => _run(context, () => widget.ctx.act(a, b));

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final q = queue;
    final cur = q.indexWhere((x) => x['current'] == true);
    final more = (v['more_req'] as Map?)?.cast<String, dynamic>();
    final running = v['running'] == true;
    final minutes = (durationMs / 60000).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        AppProgressRing(
          value: frac,
          size: 88,
          stroke: 8,
          color: ringColor,
          child: Text(fmtClock(shown), style: TextStyle(color: t.text, fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(current.isEmpty ? tr('Chưa có người nói') : tr('Đang nói'), style: TextStyle(color: t.sub, fontSize: 12.5)),
            if (current.isNotEmpty) Text(current, style: TextStyle(color: t.text, fontSize: 19, fontWeight: FontWeight.w800)),
            if (more != null) Text(tr('{0} xin thêm 1 phút', [more['name']]), style: TextStyle(color: t.light ? const Color(0xFFB7791F) : _amber, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, box) {
        final run = AppButton(running ? tr('Dừng') : tr('Chạy'), key: const ValueKey('timer-run'), kind: running ? AppButtonKind.tonal : AppButtonKind.success, onPressed: () => _act(running ? 'pause' : 'start'));
        final add = AppButton(tr('+1 phút'), key: const ValueKey('timer-add'), kind: AppButtonKind.warn, onPressed: () => _act('add', {'ms': 60000}));
        final next = AppButton(tr('Người kế ›'), key: const ValueKey('timer-next'), kind: AppButtonKind.primary, onPressed: q.isEmpty || cur >= q.length - 1 ? null : () => _act('next', {'start': true}));
        // Cột hẹp (điện thoại ngang): Chạy / +1 phút một hàng, Người kế hàng dưới.
        if (box.maxWidth < 330) {
          return Column(children: [
            Row(children: [Expanded(child: run), if (countdown) ...[const SizedBox(width: 8), Expanded(child: add)]]),
            const SizedBox(height: 8),
            next,
          ]);
        }
        return Row(children: [
          Expanded(flex: 2, child: run),
          const SizedBox(width: 8),
          if (countdown) ...[Expanded(flex: 2, child: add), const SizedBox(width: 8)],
          Expanded(flex: 3, child: next),
        ]);
      }),
      const SizedBox(height: 12),
      AppSectionLabel(tr('Giờ mỗi lượt'), trailing: TextButton(onPressed: () => _act('reset'), child: Text(tr('Đặt lại')))),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final m in [1, 2, 3, 5]) AppChip(tr('{0}′', [m]), selected: countdown && minutes == m, onTap: () => _act('set', {'minutes': m})),
        AppNumberStepper(value: minutes.clamp(1, 120), min: 1, max: 120, format: (x) => tr('{0} phút', [x]), onChanged: (x) => _act('set', {'minutes': x})),
      ]),
      const SizedBox(height: 12),
      AppSectionLabel(tr('Thứ tự nói')),
      for (final (i, x) in q.indexed)
        _QueueRow(
          key: ValueKey('q-$i-${x['name']}'),
          name: '${x['name']}',
          current: x['current'] == true,
          trailing: '',
          lead: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(onTap: i == 0 ? null : () => _act('move', {'from': i, 'to': i - 1}), child: Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: i == 0 ? t.line : t.sub)),
            InkWell(onTap: i == q.length - 1 ? null : () => _act('move', {'from': i, 'to': i + 1}), child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: i == q.length - 1 ? t.line : t.sub)),
          ]),
          tail: Row(mainAxisSize: MainAxisSize.min, children: [
            if (x['current'] != true)
              AppScope.of(context).compact
                  ? IconButton(tooltip: tr('Gọi ngay'), visualDensity: VisualDensity.compact, onPressed: () => _act('call', {'i': i}), icon: Icon(Icons.campaign_outlined, size: 18, color: t.accent))
                  : TextButton(onPressed: () => _act('call', {'i': i}), child: Text(tr('Gọi ngay'))),
            IconButton(tooltip: tr('Bỏ'), visualDensity: VisualDensity.compact, onPressed: () => _act('remove', {'i': i}), icon: const Icon(Icons.close_rounded, size: 18, color: _red)),
          ]),
        ),
      Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('timer-add-name'),
            controller: _name,
            style: TextStyle(color: t.text),
            decoration: InputDecoration(isDense: true, hintText: tr('+ Thêm người'), hintStyle: TextStyle(color: t.accent), border: InputBorder.none),
            onSubmitted: (x) async {
              if (x.trim().isEmpty) return;
              await _act('add_speaker', {'name': x.trim()});
              _name.clear();
            },
          ),
        ),
        IconButton(
          tooltip: tr('Thêm'),
          onPressed: () async {
            if (_name.text.trim().isEmpty) return;
            await _act('add_speaker', {'name': _name.text.trim()});
            _name.clear();
          },
          icon: Icon(Icons.person_add_alt_1_rounded, color: t.accent),
        ),
      ]),
      AppToggleRow(
        countdown ? tr('Đếm ngược') : tr('Bấm giờ (chạy lên)'),
        sub: tr('Bật = đếm ngược theo giờ mỗi lượt'),
        value: countdown,
        onChanged: (x) => _act('mode', {'mode': x ? 'countdown' : 'stopwatch'}),
      ),
    ]);
  }
}
