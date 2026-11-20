import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../page_types.dart';
import 'builtin.dart' show pageField;

// Loại trang "Bốc thăm" (máy chủ: relay/meet-pt-draw.mjs): bốc N mục từ danh sách hoặc từ người trong cuộc họp, có / không
// lặp lại, hoặc chia nhóm. Máy chủ bốc (số ngẫu nhiên mật mã); app quay hiệu ứng ~1,5 giây khi có kết quả mới rồi hiện.

const _sub = Color(0xFF9AA0A6);
const _card = Color(0xFF2A2E35);
const _gold = Color(0xFFFFD36B);
const _teamColors = [Color(0xFF8AB4F8), Color(0xFF7FD8CC), Color(0xFFFFD36B), Color(0xFFF6AEA9), Color(0xFFC6B6FF), Color(0xFFA8DAB5)];

void registerDrawPageType() {
  registerPageType(PageTypeSpec(
    type: 'draw',
    label: tr('Bốc thăm'),
    desc: tr('Bốc ngẫu nhiên, chia nhóm'),
    icon: Icons.casino_outlined,
    color: const Color(0xFF9334E6),
    create: (context, call) => showModalBottomSheet<PageDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DrawSettings(inMeeting: call.pagesMeeting != null),
    ),
    view: (context, ctx) => DrawView(ctx),
  ));
}

/// Cài đặt bốc thăm: tạo mới (trả PageDraft) hoặc sửa ([initial] + onSave).
class DrawSettings extends StatefulWidget {
  final bool inMeeting;
  final Map<String, dynamic>? initial;
  final Future<void> Function(Map<String, dynamic> cfg)? onSave;
  const DrawSettings({super.key, this.inMeeting = true, this.initial, this.onSave});
  @override
  State<DrawSettings> createState() => _DrawSettingsState();
}

class _DrawSettingsState extends State<DrawSettings> {
  late String _source = '${widget.initial?['source'] ?? (widget.inMeeting ? 'participants' : 'list')}';
  late String _mode = '${widget.initial?['mode'] ?? 'pick'}';
  late int _count = (widget.initial?['count'] as num?)?.toInt() ?? 1;
  late int _groups = (widget.initial?['groups'] as num?)?.toInt() ?? 2;
  late bool _repeats = widget.initial?['repeats'] == true;
  late final _options = TextEditingController(text: [for (final o in (widget.initial?['options'] as List? ?? const [])) '$o'].join('\n'));

  @override
  void dispose() {
    _options.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _cfg => {
        'source': _source,
        'mode': _mode,
        'count': _count,
        'groups': _groups,
        'repeats': _repeats,
        'options': [for (final l in _options.text.split('\n')) if (l.trim().isNotEmpty) l.trim()],
      };

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> on) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white))),
        IconButton(onPressed: value > min ? () => on(value - 1) : null, icon: const Icon(Icons.remove_circle_outline, color: Colors.white70)),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
        IconButton(onPressed: value < max ? () => on(value + 1) : null, icon: const Icon(Icons.add_circle_outline, color: Colors.white70)),
      ]);

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'pick', label: Text(tr('Bốc thăm')), icon: const Icon(Icons.casino_outlined)),
                  ButtonSegment(value: 'groups', label: Text(tr('Chia nhóm')), icon: const Icon(Icons.groups_outlined)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 12),
              if (widget.inMeeting)
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'participants', label: Text(tr('Người trong cuộc họp'))),
                    ButtonSegment(value: 'list', label: Text(tr('Danh sách tự nhập'))),
                  ],
                  selected: {_source},
                  onSelectionChanged: (s) => setState(() => _source = s.first),
                ),
              if (_source == 'list' || !widget.inMeeting) ...[
                const SizedBox(height: 12),
                TextField(controller: _options, minLines: 3, maxLines: 8, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Các lựa chọn (mỗi dòng một mục)'))),
              ],
              const SizedBox(height: 8),
              if (_mode == 'pick') ...[
                _stepper(tr('Số lượng bốc'), _count, 1, 20, (v) => setState(() => _count = v)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Cho phép trùng'), style: const TextStyle(color: Colors.white)),
                  subtitle: Text(tr('Một mục có thể được bốc nhiều lần'), style: const TextStyle(color: _sub, fontSize: 12)),
                  value: _repeats,
                  onChanged: (v) => setState(() => _repeats = v),
                ),
              ] else
                _stepper(tr('Số nhóm'), _groups, 2, 20, (v) => setState(() => _groups = v)),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () async {
                  if (widget.onSave != null) {
                    await widget.onSave!(_cfg);
                    if (context.mounted) Navigator.pop(context);
                    return;
                  }
                  Navigator.pop(context, PageDraft(title: _mode == 'groups' ? tr('Chia {0} nhóm', [_groups]) : tr('Bốc thăm'), init: _cfg));
                },
                child: Text(widget.onSave != null ? tr('Lưu') : tr('Tạo')),
              ),
            ]),
          ),
        ),
      );
}

class DrawView extends StatefulWidget {
  final PageCtx ctx;
  const DrawView(this.ctx, {super.key});
  @override
  State<DrawView> createState() => _DrawViewState();
}

class _DrawViewState extends State<DrawView> {
  String? _shownId; // kết quả đã quay xong
  Timer? _spin;
  String _flash = '';
  bool _busy = false;
  final _rnd = Random();

  Map<String, dynamic> get v => widget.ctx.view;
  Map<String, dynamic>? get last => (v['last'] as Map?)?.cast<String, dynamic>();

  @override
  void initState() {
    super.initState();
    _shownId = '${last?['id'] ?? ''}'; // mở trang: hiện ngay kết quả cũ, không quay
  }

  @override
  void didUpdateWidget(DrawView old) {
    super.didUpdateWidget(old);
    final id = '${last?['id'] ?? ''}';
    if (id.isNotEmpty && id != _shownId && _spin == null) _startSpin(id);
  }

  void _startSpin(String id) {
    final pool = [
      ...[for (final o in (v['options'] as List? ?? const [])) '$o'],
      ...[for (final p in (last?['picks'] as List? ?? const [])) '$p'],
      ...[for (final t in (last?['teams'] as List? ?? const [])) for (final p in (t as List)) '$p'],
    ];
    if (pool.isEmpty || MediaQuery.of(context).disableAnimations) {
      setState(() => _shownId = id);
      return;
    }
    var n = 0;
    _spin = Timer.periodic(const Duration(milliseconds: 70), (t) {
      n++;
      if (!mounted) return t.cancel();
      setState(() => _flash = pool[_rnd.nextInt(pool.length)]);
      if (n >= 22) {
        t.cancel();
        _spin = null;
        setState(() => _shownId = id);
      }
    });
  }

  @override
  void dispose() {
    _spin?.cancel();
    super.dispose();
  }

  Future<void> _act(String a, [Map<String, dynamic> b = const {}]) async {
    setState(() => _busy = true);
    try {
      await widget.ctx.act(a, b);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _result({required bool big}) {
    final r = last;
    final fs = big ? 48.0 : 18.0;
    if (_spin != null) {
      return Text(_flash, textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: fs * 1.3, fontWeight: FontWeight.w700));
    }
    if (r == null || '${r['id']}' != _shownId) {
      return Text(tr('Chưa bốc'), style: TextStyle(color: _sub, fontSize: fs));
    }
    if (r['teams'] is List) {
      final teams = [for (final t in r['teams'] as List) [for (final p in t as List) '$p']];
      return Wrap(alignment: WrapAlignment.center, spacing: big ? 24 : 10, runSpacing: big ? 24 : 10, children: [
        for (final (i, t) in teams.indexed)
          Container(
            width: big ? 300 : 160,
            padding: EdgeInsets.all(big ? 20 : 10),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _teamColors[i % _teamColors.length], width: 2)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Nhóm {0}', [i + 1]), style: TextStyle(color: _teamColors[i % _teamColors.length], fontSize: fs * .8, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final p in t) Text(p, style: TextStyle(color: Colors.white, fontSize: fs * .7)),
            ]),
          ),
      ]);
    }
    final picks = [for (final p in (r['picks'] as List? ?? const [])) '$p'];
    return Wrap(alignment: WrapAlignment.center, spacing: big ? 20 : 8, runSpacing: big ? 20 : 8, children: [
      for (final p in picks)
        Container(
          padding: EdgeInsets.symmetric(horizontal: big ? 32 : 14, vertical: big ? 18 : 8),
          decoration: BoxDecoration(color: const Color(0xFF3D3010), borderRadius: BorderRadius.circular(40), border: Border.all(color: _gold, width: 2)),
          child: Text(p, style: TextStyle(color: _gold, fontSize: fs, fontWeight: FontWeight.w800)),
        ),
    ]);
  }

  Future<void> _settings() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF2D2E31),
        showDragHandle: true,
        builder: (_) => DrawSettings(inMeeting: widget.ctx.page.meeting != null, initial: v, onSave: (cfg) => _act('config', cfg)),
      );

  @override
  Widget build(BuildContext context) {
    final control = v['can_control'] == true || widget.ctx.control;
    final groups = v['mode'] == 'groups';
    final header = groups ? tr('Chia {0} nhóm', [v['groups'] ?? 2]) : tr('Bốc thăm {0} mục', [v['count'] ?? 1]);
    final drawBtn = FilledButton.icon(
      onPressed: _busy || _spin != null ? null : () => _act('draw'),
      icon: const Icon(Icons.casino),
      label: Text(last == null ? (groups ? tr('Chia nhóm') : tr('Bốc')) : (groups ? tr('Chia lại') : tr('Bốc lại'))),
    );
    if (widget.ctx.onStage) {
      return Stack(children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1280,
              height: 720,
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.casino_outlined, color: _gold, size: 34),
                    const SizedBox(width: 12),
                    Text(header, style: const TextStyle(color: _gold, fontSize: 30, fontWeight: FontWeight.w600)),
                  ]),
                  Expanded(child: Center(child: _result(big: true))),
                ]),
              ),
            ),
          ),
        ),
        if (widget.ctx.presenting) Positioned(right: 16, bottom: 16, child: drawBtn),
      ]);
    }
    final history = [for (final r in (v['results'] as List? ?? const []).reversed.skip(1)) (r as Map).cast<String, dynamic>()];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text(header, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
        if (control) IconButton(tooltip: tr('Cài đặt'), onPressed: _settings, icon: const Icon(Icons.tune, color: Colors.white70)),
      ]),
      Text(
        v['source'] == 'participants' ? tr('Từ người đang trong cuộc họp') : tr('{0} lựa chọn', [(v['options'] as List? ?? const []).length]),
        style: const TextStyle(color: _sub, fontSize: 13),
      ),
      const SizedBox(height: 24),
      Center(child: _result(big: false)),
      const SizedBox(height: 24),
      if (control) Center(child: drawBtn) else Center(child: Text(tr('Chủ trang / người trình chiếu bốc thăm.'), style: const TextStyle(color: _sub))),
      if (history.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text(tr('Lần trước'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        for (final r in history.take(5))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              r['teams'] is List
                  ? [for (final (i, t) in (r['teams'] as List).indexed) '${tr('Nhóm {0}', [i + 1])}: ${(t as List).join(', ')}'].join(' · ')
                  : (r['picks'] as List? ?? const []).join(', '),
              style: const TextStyle(color: Colors.white70),
            ),
            subtitle: Text('${r['by_name'] ?? ''}', style: const TextStyle(color: _sub, fontSize: 12)),
          ),
      ],
    ]);
  }
}
