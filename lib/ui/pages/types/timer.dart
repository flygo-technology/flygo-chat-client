import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../page_types.dart';
import '../stage_frame.dart';
import 'builtin.dart' show pageField;
import 'timer_app.dart';

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
    // Mỗi trang là một app (mockup 21/11): người xem xin lượt nói, chủ trang điều khiển tại chỗ.
    panel: (context, ctx) => TimerPanel(ctx),
    controls: (context, ctx) => TimerControls(ctx),
    stageThemed: true,
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

  int? _syncedNow;

  /// Bù lệch giờ máy chủ, chỉ khi có view mới (now đổi). Trước đây tính lại ở mỗi lần dựng lại (cuộc họp dựng lại liên tục khi
  /// có người nói, vào / ra...) với now cũ: lệch giờ trôi theo, đồng hồ đứng yên ở số lúc tải view.
  void _sync() {
    final now = (v['now'] as num?)?.toInt();
    if (now == null || now == _syncedNow) return;
    _syncedNow = now;
    _skew = now - DateTime.now().millisecondsSinceEpoch;
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

  /// Sân khấu (mockup Họp): vòng tiến độ đổi màu xanh → vàng (50%) → đỏ (dưới 10 giây), số lớn ở giữa; lượt người nói bên phải.
  Widget _stage(int ms, bool done, String who, List<String> speakers, {StageMetrics? fm}) {
    final m = fm ?? StageMetrics.of(context);
    // Ngoài khung sân khấu (thử, ảnh thu nhỏ): dựng ở kích thước vùng nội dung của khung rồi co cho vừa.
    if (m == null) return FittedBox(child: SizedBox(width: 1168, height: 560, child: _stage(ms, done, who, speakers, fm: const StageMetrics(theme: StageTheme(), portrait: false, size: Size(1168, 560), child: SizedBox()))));
    final t = m.theme;
    final portrait = m.portrait;
    final dur = (v['duration_ms'] as num?)?.toInt() ?? 0;
    final frac = _countdown && dur > 0 ? (ms / dur).clamp(0.0, 1.0) : 1.0;
    final color = done || (_countdown && ms <= 10000 && v['running'] == true)
        ? _red
        : (_countdown && frac <= .5 ? const Color(0xFFF5B544) : const Color(0xFF38C793));
    final ring = AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) => Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: frac,
              strokeWidth: box.maxWidth * .045,
              strokeCap: StrokeCap.round,
              backgroundColor: t.surface2,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(box.maxWidth * .14),
            child: FittedBox(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(done ? tr('HẾT GIỜ') : (_countdown ? tr('CÒN LẠI') : tr('ĐÃ CHẠY')), style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 2)),
                Text(fmtClock(ms), style: TextStyle(color: done ? _red : t.text, fontSize: 140, fontWeight: FontWeight.w800, height: 1, fontFeatures: const [FontFeature.tabularFigures()])),
                Text(
                  v['running'] == true ? (dur > 0 && _countdown ? tr('trên {0}', [fmtClock(dur)]) : '') : tr('đang dừng'),
                  style: TextStyle(color: t.sub, fontSize: 22),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
    if (portrait || speakers.isEmpty) return Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: ring));
    final cur = ((v['speaker'] as num?)?.toInt() ?? 0).clamp(0, speakers.length - 1);
    return Row(children: [
      Expanded(child: Center(child: ring)),
      const SizedBox(width: 40),
      SizedBox(
        width: 420,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('LƯỢT NÓI'), style: TextStyle(color: t.sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
          const SizedBox(height: 12),
          for (final (i, sp) in speakers.take(6).indexed)
            Opacity(
              opacity: i < cur ? .5 : 1,
              child: Container(
                height: 56,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: i == cur ? const Color(0xFFF5B544).withValues(alpha: .12) : t.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: i == cur ? Border.all(color: const Color(0xFFF5B544), width: 1.5) : null,
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: t.series[i % t.series.length],
                    child: Text(sp.trim().characters.firstOrNull?.toUpperCase() ?? '?', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(sp, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 17, fontWeight: i == cur ? FontWeight.w700 : FontWeight.w400))),
                  if (i == cur) Text(tr('đang nói'), style: const TextStyle(color: Color(0xFFF5B544), fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ms = _shown;
    // Hết giờ: đã chạy đủ thời lượng (kể cả khi đang chạy qua 0, lúc elapsed_ms của máy chủ vẫn là 0).
    final done = _countdown && ms <= 0 && _elapsed > 0;
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
        Positioned.fill(child: _stage(ms, done, who, speakers)),
        if (widget.ctx.presenting) Positioned(left: 0, right: 0, bottom: 0, child: _controls(compact: true)),
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
