import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../page_types.dart';
import 'builtin.dart' show pageField;

// Loại trang "Bấm giờ" (máy chủ: relay/meet-pt-timer.mjs): đếm ngược / bấm giờ, mốc có sẵn 1-3-5-10 phút, lượt người nói.
// Máy chủ chỉ giữ mốc chạy; app tự đếm theo đồng hồ máy chủ (bù lệch giờ bằng view.now). TV kêu chuông khi hết giờ (hop-web).

const _sub = Color(0xFF9AA0A6);
const _red = Color(0xFFF28B82);
const _acc = Color(0xFF2BB3A3);

void registerTimerPageType() {
  registerPageType(PageTypeSpec(
    type: 'timer',
    label: tr('Bấm giờ'),
    desc: tr('Đếm ngược, bấm giờ, lượt người nói'),
    icon: Icons.timer_outlined,
    color: const Color(0xFFE8710A),
    create: (context, call) => showModalBottomSheet<PageDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _TimerComposer(),
    ),
    view: (context, ctx) => TimerView(ctx),
  ));
}

class _TimerComposer extends StatefulWidget {
  const _TimerComposer();
  @override
  State<_TimerComposer> createState() => _TimerComposerState();
}

class _TimerComposerState extends State<_TimerComposer> {
  String _mode = 'countdown';
  int _minutes = 5;
  final _speakers = TextEditingController();

  @override
  void dispose() {
    _speakers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'countdown', label: Text(tr('Đếm ngược')), icon: const Icon(Icons.hourglass_bottom)),
                ButtonSegment(value: 'stopwatch', label: Text(tr('Bấm giờ')), icon: const Icon(Icons.timer_outlined)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            if (_mode == 'countdown') ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in [1, 3, 5, 10, 15, 30])
                  ChoiceChip(label: Text(tr('{0} phút', [m])), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _speakers,
                minLines: 2,
                maxLines: 6,
                style: const TextStyle(color: Colors.white),
                decoration: pageField(tr('Lượt người nói (mỗi dòng một người, không bắt buộc)')),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                PageDraft(
                  title: _mode == 'stopwatch' ? tr('Bấm giờ') : tr('Đếm ngược {0} phút', [_minutes]),
                  init: {
                    'mode': _mode,
                    'minutes': _minutes,
                    'speakers': [for (final l in _speakers.text.split('\n')) if (l.trim().isNotEmpty) l.trim()],
                  },
                ),
              ),
              child: Text(tr('Tạo đồng hồ')),
            ),
          ]),
        ),
      );
}

String fmtClock(int ms) {
  final s = (ms / 1000).ceil().clamp(0, 359999);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

class TimerView extends StatefulWidget {
  final PageCtx ctx;
  const TimerView(this.ctx, {super.key});
  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  Timer? _tick;
  int _skew = 0; // đồng hồ máy chủ - đồng hồ máy này
  bool _busy = false;

  Map<String, dynamic> get v => widget.ctx.view;

  @override
  void initState() {
    super.initState();
    _sync();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && v['running'] == true) setState(() {});
    });
  }

  @override
  void didUpdateWidget(TimerView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final now = (v['now'] as num?)?.toInt();
    if (now != null) _skew = now - DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _elapsed {
    final base = (v['elapsed_ms'] as num?)?.toInt() ?? 0;
    if (v['running'] != true) return base;
    final started = (v['started_at'] as num?)?.toInt() ?? 0;
    return base + (DateTime.now().millisecondsSinceEpoch + _skew - started);
  }

  bool get _countdown => v['mode'] != 'stopwatch';
  int get _shown => _countdown ? (((v['duration_ms'] as num?)?.toInt() ?? 0) - _elapsed).clamp(0, 1 << 40) : _elapsed;

  Future<void> _act(String a, [Map<String, dynamic> b = const {}]) async {
    setState(() => _busy = true);
    try {
      await widget.ctx.act(a, b);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _controls({required bool compact}) {
    final running = v['running'] == true;
    final speakers = [for (final s in (v['speakers'] as List? ?? const [])) '$s'];
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(
        onPressed: _busy ? null : () => _act(running ? 'pause' : 'start'),
        icon: Icon(running ? Icons.pause : Icons.play_arrow),
        label: Text(running ? tr('Tạm dừng') : tr('Bắt đầu')),
      ),
      OutlinedButton.icon(onPressed: _busy ? null : () => _act('reset'), icon: const Icon(Icons.replay), label: Text(tr('Đặt lại'))),
      if (_countdown) OutlinedButton(onPressed: _busy ? null : () => _act('add', {'ms': 60000}), child: Text(tr('+1 phút'))),
      if (speakers.isNotEmpty) ...[
        OutlinedButton(onPressed: _busy ? null : () => _act('prev'), child: const Icon(Icons.skip_previous)),
        OutlinedButton(onPressed: _busy ? null : () => _act('next'), child: const Icon(Icons.skip_next)),
      ],
      if (!compact && _countdown)
        for (final m in [1, 3, 5, 10]) ActionChip(label: Text(tr('{0} phút', [m])), onPressed: _busy ? null : () => _act('set', {'minutes': m})),
      if (!compact)
        ActionChip(
          avatar: Icon(_countdown ? Icons.timer_outlined : Icons.hourglass_bottom, size: 18),
          label: Text(_countdown ? tr('Chuyển sang bấm giờ') : tr('Chuyển sang đếm ngược')),
          onPressed: _busy ? null : () => _act('mode', {'mode': _countdown ? 'stopwatch' : 'countdown'}),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ms = _shown;
    final done = _countdown && ms <= 0 && ((v['elapsed_ms'] as num?) ?? 0) > 0;
    final warn = _countdown && ms > 0 && ms <= 10000 && v['running'] == true;
    final speakers = [for (final s in (v['speakers'] as List? ?? const [])) '$s'];
    final who = speakers.isEmpty ? '' : speakers[((v['speaker'] as num?)?.toInt() ?? 0).clamp(0, speakers.length - 1)];
    final control = v['can_control'] == true || widget.ctx.control;
    final clock = Text(
      fmtClock(ms),
      style: TextStyle(
        color: done || warn ? _red : Colors.white,
        fontSize: 220,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1,
      ),
    );
    final face = Column(mainAxisSize: MainAxisSize.min, children: [
      if (who.isNotEmpty)
        Text(tr('Đang nói: {0}', [who]), style: const TextStyle(color: _acc, fontSize: 48, fontWeight: FontWeight.w600)),
      clock,
      Text(
        done ? tr('Hết giờ') : (_countdown ? tr('Đếm ngược') : tr('Bấm giờ')) + (v['running'] == true ? '' : ' · ${tr('đang dừng')}'),
        style: TextStyle(color: done ? _red : _sub, fontSize: 40),
      ),
    ]);
    if (widget.ctx.onStage) {
      return Stack(children: [
        Positioned.fill(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: FittedBox(fit: BoxFit.contain, child: face)))),
        if (widget.ctx.presenting) Positioned(left: 12, right: 12, bottom: 12, child: _controls(compact: true)),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      SizedBox(height: 240, child: FittedBox(fit: BoxFit.contain, child: face)),
      const SizedBox(height: 16),
      if (control) _controls(compact: false) else Text(tr('Chủ trang / người trình chiếu điều khiển đồng hồ.'), textAlign: TextAlign.center, style: const TextStyle(color: _sub)),
      if (speakers.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(tr('Lượt người nói'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        for (final (i, s) in speakers.indexed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(s == who ? Icons.record_voice_over : Icons.person_outline, color: s == who ? _acc : _sub),
            title: Text('${i + 1}. $s', style: TextStyle(color: s == who ? Colors.white : Colors.white70)),
          ),
      ],
    ]);
  }
}
