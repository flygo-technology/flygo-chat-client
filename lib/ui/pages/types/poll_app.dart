import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
import '../page_types.dart';
import '../stage_frame.dart';

// Bình chọn / Trắc nghiệm / Biểu quyết theo mockup "mỗi trang là một app" (Sếp duyệt 21/11/2026).
// - PollPanel (người xem): chạm phương án là chọn ngay; bình chọn đổi ý được tới khi khoá; trắc nghiệm / biểu quyết một lần.
// - PollControls (chủ trang): ẩn danh, ai thấy kết quả, khoá / mở, công bố, chuyển câu, ghi Biên bản; biểu quyết: ngưỡng, tối thiểu.
// - PollEditor (sửa tại chỗ trên trang): kiểu (khi chưa có phiếu), câu hỏi, phương án, đáp án đúng, chọn nhiều.

const _vYes = Color(0xFF38C793), _vNo = Color(0xFFF0646A), _vAbs = Color(0xFF8E99A8), _ok = Color(0xFF38C793);

List<Map<String, dynamic>> _qs(Map<String, dynamic> v) => [for (final q in (v['questions'] as List? ?? const [])) (q as Map).cast<String, dynamic>()];
List<String> _mine(Map<String, dynamic> v, String q) => [for (final x in ((v['mine'] as Map?)?[q] as List? ?? const [])) '$x'];
Map<String, dynamic>? _res(Map<String, dynamic> v, String q) => ((v['results'] as Map?)?[q] as Map?)?.cast<String, dynamic>();

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) meetToast(context, '$e');
  }
}

/// Phần của người xem.
class PollPanel extends StatefulWidget {
  final PageCtx ctx;
  const PollPanel(this.ctx, {super.key});
  @override
  State<PollPanel> createState() => _PollPanelState();
}

class _PollPanelState extends State<PollPanel> {
  bool _busy = false;
  PageCtx get ctx => widget.ctx;
  Map<String, dynamic> get v => ctx.view;
  String get kind => '${v['kind'] ?? 'poll'}';

  Future<void> _answer(Map<String, dynamic> q, String id) async {
    if (_busy) return;
    final qid = '${q['id']}';
    final cur = _mine(v, qid).toSet();
    final next = q['multi'] == true ? ({...cur}..toggle(id)) : (cur.contains(id) && kind == 'poll' ? <String>{} : {id});
    setState(() => _busy = true);
    await _run(context, () => ctx.act('answer', {'q': qid, 'options': next.toList()}));
    if (mounted) setState(() => _busy = false);
  }

  bool _canAnswer(Map<String, dynamic> q) {
    final role = ctx.data.role;
    if (v['closed'] == true || role == 'viewer' || (kind == 'vote' && role == 'guest')) return false;
    if (kind != 'poll' && _mine(v, '${q['id']}').isNotEmpty) return false;
    if (kind == 'quiz' && v['reveal'] == true) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), t = s.theme;
    final qs = _qs(v);
    if (qs.isEmpty) return const SizedBox.shrink();
    final cur = kind == 'quiz' ? ((v['current'] as num?)?.toInt() ?? 0).clamp(0, qs.length - 1) : 0;
    final shown = kind == 'poll' ? qs : [qs[cur]];
    final chip = switch (kind) {
      'quiz' => tr('TRẮC NGHIỆM · CÂU {0} / {1}', [cur + 1, qs.length]),
      'vote' => tr('BIỂU QUYẾT'),
      _ => shown.first['multi'] == true ? tr('BÌNH CHỌN · CHỌN NHIỀU') : tr('BÌNH CHỌN · 1 LỰA CHỌN'),
    };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AppChip(chip),
          const Spacer(),
          if (v['closed'] == true) AppChip(tr('Đã khoá'), color: t.sub) else if (v['anon'] == true) AppChip(kind == 'vote' ? tr('Phiếu kín') : tr('Ẩn danh'), color: t.sub),
        ]),
        for (final q in shown) ...[
          SizedBox(height: s.compact ? 8 : 12),
          Text('${q['text']}', style: TextStyle(color: t.text, fontSize: s.compact ? 17 : 21, fontWeight: FontWeight.w800, height: 1.2)),
          SizedBox(height: s.compact ? 8 : 12),
          if (kind == 'vote') _voteButtons(q, t, s) else ..._options(q, t, s),
        ],
        const SizedBox(height: 8),
        Text(_hint(shown.first), style: TextStyle(color: t.sub, fontSize: 12.5)),
        if (kind == 'quiz' && v['leaderboard'] is List && (v['leaderboard'] as List).isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionLabel(tr('Bảng điểm')),
          for (final (i, x) in (v['leaderboard'] as List).take(5).indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(color: i == 0 ? const Color(0xFFF5B544) : t.sub, fontWeight: FontWeight.w800))),
                Expanded(child: Text('${(x as Map)['name']}', style: TextStyle(color: t.text))),
                Text('${x['score']}/${x['of']}', style: TextStyle(color: t.text, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
        ],
      ]),
    );
  }

  String _hint(Map<String, dynamic> q) {
    final mine = _mine(v, '${q['id']}');
    final voters = v['voters'] ?? 0;
    if (kind == 'vote') {
      final o = (v['outcome'] as Map?)?.cast<String, dynamic>();
      if (v['closed'] == true && o != null) return o['passed'] == true ? tr('Đã THÔNG QUA · {0}/{1} tán thành', [o['yes'], o['voters']]) : tr('KHÔNG thông qua · {0}/{1} tán thành', [o['yes'], o['voters']]);
      final need = tr('Cần trên {0}% tán thành', [v['threshold'] ?? 50]) + (((v['quorum'] as num?) ?? 0) > 0 ? tr(' · tối thiểu {0} phiếu', [v['quorum']]) : '');
      return mine.isEmpty ? '$need · ${tr('{0} người đã bỏ phiếu', [voters])}' : tr('Bạn đã bỏ phiếu. {0}', [need]);
    }
    if (kind == 'quiz') {
      if (v['reveal'] == true && v['my_score'] != null) return tr('Điểm của bạn: {0}/{1}', [v['my_score'], _qs(v).length]);
      return mine.isEmpty ? tr('Chạm để trả lời (một lần, không đổi được).') : tr('Đã trả lời. Đáp án hiện khi chủ trang công bố.');
    }
    if (v['closed'] == true) return tr('Bình chọn đã khoá.');
    if (mine.isEmpty) return v['results'] == null ? tr('Chạm để chọn. Kết quả hiện sau khi bạn chọn.') : tr('Chạm để chọn.');
    final letters = [for (final (i, o) in (q['options'] as List).indexed) if (mine.contains('${(o as Map)['id']}')) String.fromCharCode(65 + i)];
    return tr('Bạn đã chọn {0}. Chạm phương án khác để đổi ý trước khi khoá.', [letters.join(', ')]);
  }

  List<Widget> _options(Map<String, dynamic> q, StageTheme t, AppScope s) {
    final qid = '${q['id']}';
    final r = _res(v, qid);
    final total = (r?['total'] as num?)?.toInt() ?? 0;
    final mine = _mine(v, qid);
    final correct = [for (final x in (q['correct'] as List? ?? const [])) '$x'];
    final can = _canAnswer(q) && !_busy;
    return [
      for (final (i, o) in [for (final o in (q['options'] as List? ?? const [])) (o as Map).cast<String, dynamic>()].indexed)
        Padding(
          padding: EdgeInsets.only(bottom: s.compact ? 6 : 8),
          child: _OptionTile(
            key: ValueKey('opt-${o['id']}'),
            letter: String.fromCharCode(65 + i),
            text: '${o['text']}',
            selected: mine.contains('${o['id']}'),
            correct: correct.contains('${o['id']}'),
            pct: r == null ? null : (total == 0 ? 0 : (((r['options'] as Map?)?['${o['id']}'] as num?) ?? 0) / total),
            count: r == null ? null : (((r['options'] as Map?)?['${o['id']}'] as num?)?.toInt() ?? 0),
            onTap: can ? () => _answer(q, '${o['id']}') : null,
            height: s.compact ? 46 : 52,
          ),
        ),
    ];
  }

  Widget _voteButtons(Map<String, dynamic> q, StageTheme t, AppScope s) {
    final mine = _mine(v, '${q['id']}');
    final can = _canAnswer(q) && !_busy;
    final r = _res(v, '${q['id']}');
    final labels = {'yes': (tr('Tán thành'), _vYes), 'no': (tr('Không'), _vNo), 'abstain': (tr('Bỏ phiếu trắng'), _vAbs)};
    return Row(children: [
      for (final (i, id) in ['yes', 'no', 'abstain'].indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Material(
            color: mine.contains(id) ? labels[id]!.$2.withValues(alpha: .2) : t.surface2,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: ValueKey('vote-$id'),
              borderRadius: BorderRadius.circular(14),
              onTap: can ? () => _answer(q, id) : null,
              child: Container(
                constraints: BoxConstraints(minHeight: s.compact ? 50 : 64),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: mine.contains(id) ? Border.all(color: labels[id]!.$2, width: 2) : null),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(labels[id]!.$1, textAlign: TextAlign.center, style: TextStyle(color: id == 'abstain' ? t.text : labels[id]!.$2, fontSize: 15, fontWeight: FontWeight.w800)),
                  if (r != null) Text('${((r['options'] as Map?)?[id] as num?) ?? 0}', style: TextStyle(color: t.sub, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

extension on Set<String> {
  void toggle(String x) => contains(x) ? remove(x) : add(x);
}

/// Một phương án: chữ cái, nội dung, thanh % (khi được xem kết quả), viền khi đã chọn, dấu đúng (trắc nghiệm đã công bố).
class _OptionTile extends StatelessWidget {
  final String letter, text;
  final bool selected, correct;
  final double? pct;
  final int? count;
  final VoidCallback? onTap;
  final double height;
  const _OptionTile({super.key, required this.letter, required this.text, required this.selected, required this.correct, this.pct, this.count, this.onTap, this.height = 52});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final acc = correct ? _ok : t.accent;
    return Material(
      color: t.surface2,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(children: [
          if (pct != null)
            Positioned.fill(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: pct!.clamp(0, 1).toDouble(), child: ColoredBox(color: acc.withValues(alpha: t.light ? .16 : .24)))),
          Container(
            constraints: BoxConstraints(minHeight: height),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: selected || correct ? Border.all(color: acc, width: 2) : null),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: selected || correct ? acc : t.chip, borderRadius: BorderRadius.circular(8)),
                child: correct
                    ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                    : Text(letter, style: TextStyle(color: selected ? Colors.white : t.text, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(text, style: TextStyle(color: t.text, fontSize: 15.5, fontWeight: FontWeight.w600)))),
              if (pct != null) ...[
                const SizedBox(width: 8),
                Text('${(pct! * 100).round()}%', style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Điều khiển của chủ trang (khung bọc trong AppCard).
class PollControls extends StatelessWidget {
  final PageCtx ctx;
  const PollControls(this.ctx, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final v = ctx.view;
    final kind = '${v['kind'] ?? 'poll'}';
    final qs = _qs(v);
    final cur = ((v['current'] as num?)?.toInt() ?? 0).clamp(0, qs.isEmpty ? 0 : qs.length - 1);
    final voted = ((v['voters'] as num?) ?? 0) > 0;
    final closed = v['closed'] == true, reveal = v['reveal'] == true;
    final mode = '${v['results_mode'] ?? (v['live'] == true ? 'live' : 'reveal')}';
    const modeLabel = {'live': 'Ngay lập tức', 'after': 'Sau khi chọn', 'reveal': 'Khi công bố'};
    Future<void> act(String a, [Map<String, dynamic> b = const {}]) => _run(context, () => ctx.act(a, b));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(closed ? tr('Đã khoá · {0} người đã chọn', [v['voters'] ?? 0]) : tr('Đang mở · {0} người đã chọn', [v['voters'] ?? 0])),
      AppToggleRow(tr('Ẩn danh'), sub: voted ? tr('Không đổi được khi đã có người chọn') : null, value: v['anon'] == true, onChanged: voted ? null : (x) => act('edit', {'anon': x})),
      if (kind == 'poll')
        AppSelectRow(
          tr('Người xem thấy kết quả'),
          value: tr(modeLabel[mode] ?? 'Khi công bố'),
          onTap: () => act('edit', {'results_mode': const {'live': 'after', 'after': 'reveal', 'reveal': 'live'}[mode]}),
        ),
      if (kind == 'vote') ...[
        Row(children: [
          Expanded(child: Text(tr('Ngưỡng tán thành'), style: TextStyle(color: t.text))),
          AppNumberStepper(value: (v['threshold'] as num?)?.toInt() ?? 50, min: 1, max: 99, step: 1, format: (x) => x == 66 ? '2/3' : '$x%', onChanged: (x) => act('edit', {'threshold': x})),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(tr('Số phiếu tối thiểu'), style: TextStyle(color: t.text))),
          AppNumberStepper(value: (v['quorum'] as num?)?.toInt() ?? 0, min: 0, max: 500, onChanged: (x) => act('edit', {'quorum': x})),
        ]),
      ],
      const SizedBox(height: 10),
      if (kind == 'quiz' && qs.length > 1) ...[
        Row(children: [
          Expanded(child: AppButton(tr('Câu trước'), icon: Icons.chevron_left_rounded, onPressed: cur == 0 ? null : () => act('goto', {'index': cur - 1}))),
          const SizedBox(width: 8),
          Expanded(child: AppButton(tr('Câu sau'), icon: Icons.chevron_right_rounded, onPressed: cur >= qs.length - 1 ? null : () => act('goto', {'index': cur + 1}))),
        ]),
        const SizedBox(height: 8),
      ],
      Row(children: [
        Expanded(child: AppButton(closed ? tr('Mở lại') : (kind == 'vote' ? tr('Kết thúc') : tr('Khoá')), key: const ValueKey('poll-close'), onPressed: () => act(closed ? 'reopen' : 'close'))),
        if (kind != 'vote') ...[
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(
              reveal ? tr('Ẩn kết quả') : (kind == 'quiz' ? tr('Công bố đáp án') : tr('Công bố kết quả')),
              key: const ValueKey('poll-reveal'),
              kind: reveal ? AppButtonKind.tonal : AppButtonKind.primary,
              onPressed: () => act(reveal ? 'hide' : 'reveal'),
            ),
          ),
        ],
      ]),
      if (ctx.page.meeting != null) ...[
        const SizedBox(height: 8),
        AppButton(tr('Ghi kết quả vào Biên bản'), icon: Icons.note_add_outlined, onPressed: () async {
          await act('to_minutes');
          if (context.mounted) meetToast(context, tr('Đã ghi vào Biên bản'));
        }),
      ],
    ]);
  }
}

/// Sửa tại chỗ (menu "Sửa" của trang): kiểu, câu hỏi, phương án, đáp án đúng, chọn nhiều. Xong = lưu (act edit).
class PollEditor extends StatefulWidget {
  final PageCtx ctx;
  const PollEditor(this.ctx, {super.key});
  @override
  State<PollEditor> createState() => _PollEditorState();
}

class _PollEditorState extends State<PollEditor> {
  late String _kind = '${widget.ctx.view['kind'] ?? 'poll'}';
  late final List<Map<String, dynamic>> _draft = [
    for (final q in _qs(widget.ctx.view))
      {
        'id': q['id'],
        'text': '${q['text']}',
        'multi': q['multi'] == true,
        'options': [for (final o in (q['options'] as List? ?? const [])) {'id': (o as Map)['id'], 'text': '${o['text']}'}],
        'correct': [for (final x in (q['correct'] as List? ?? const [])) '$x'],
      },
  ];
  int _n = 0;

  Map<String, dynamic> get v => widget.ctx.view;
  bool get _voted => ((v['voters'] as num?) ?? 0) > 0;

  Future<bool> _save() async {
    final questions = [
      for (final q in _draft)
        {
          'id': q['id'],
          'text': '${q['text']}'.trim(),
          'multi': q['multi'] == true,
          'options': [for (final o in q['options'] as List) if ('${(o as Map)['text']}'.trim().isNotEmpty) {'id': o['id'], 'text': '${o['text']}'.trim()}],
          if (_kind == 'quiz') 'correct': q['correct'],
        },
    ];
    if (questions.any((q) => '${q['text']}'.isEmpty)) {
      meetToast(context, tr('Câu hỏi đang trống'));
      return false;
    }
    try {
      await widget.ctx.act('edit', {if (_kind != '${v['kind']}') 'kind': _kind, if (_kind == '${v['kind']}' || _kind != 'vote') 'questions': questions});
      return true;
    } catch (e) {
      if (mounted) meetToast(context, '$e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), t = s.theme;
    s.registerEdit(_save);
    final q = _draft.isEmpty ? null : _draft.first;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSegmented<String>(
          items: [('poll', tr('Bình chọn')), ('quiz', tr('Trắc nghiệm')), ('vote', tr('Biểu quyết'))],
          value: _kind,
          onChanged: _voted ? null : (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: 14),
        if (q != null) ...[
          AppInlineField(
            key: ValueKey('q-text-${q['id']}'),
            value: '${q['text']}',
            hint: tr('Câu hỏi'),
            maxLines: 3,
            onChanged: (x) => q['text'] = x,
            style: TextStyle(color: t.text, fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          if (_kind == 'vote')
            Text(tr('Biểu quyết: Tán thành / Không / Bỏ phiếu trắng (cố định)'), style: TextStyle(color: t.sub, fontSize: 18))
          else ...[
            for (final (i, o) in (q['options'] as List).cast<Map<String, dynamic>>().indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  InkWell(
                    onTap: _kind == 'quiz'
                        ? () => setState(() {
                              final c = (q['correct'] as List).cast<String>();
                              final id = '${o['id']}';
                              q['multi'] == true ? (c.contains(id) ? c.remove(id) : c.add(id)) : (c..clear()..add(id));
                            })
                        : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: (q['correct'] as List).contains('${o['id']}') ? _ok : t.chip, borderRadius: BorderRadius.circular(10)),
                      child: Text(String.fromCharCode(65 + i), style: TextStyle(color: t.text, fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppInlineField(
                      key: ValueKey('opt-edit-${o['id']}'),
                      value: '${o['text']}',
                      hint: tr('Phương án {0}', [String.fromCharCode(65 + i)]),
                      onChanged: (x) => o['text'] = x,
                      style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_count('${q['id']}', '${o['id']}') case final n? when n > 0)
                    Padding(padding: const EdgeInsets.only(left: 8), child: Text('$n', style: TextStyle(color: t.sub, fontSize: 18)))
                  else if ((q['options'] as List).length > 2)
                    IconButton(
                      tooltip: tr('Bỏ phương án'),
                      onPressed: () => setState(() => (q['options'] as List).removeAt(i)),
                      icon: Icon(Icons.close_rounded, color: t.sub),
                    ),
                ]),
              ),
            if ((q['options'] as List).length < 12)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('opt-add'),
                  onPressed: () => setState(() => (q['options'] as List).add({'id': 'n${_n++}${DateTime.now().millisecondsSinceEpoch % 100000}', 'text': ''})),
                  icon: Icon(Icons.add_rounded, color: t.accent),
                  label: Text(tr('Thêm phương án'), style: TextStyle(color: t.accent, fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ),
            Row(children: [
              Switch(value: q['multi'] == true, onChanged: (x) => setState(() => q['multi'] = x)),
              Text(tr('Chọn nhiều'), style: TextStyle(color: t.text, fontSize: 18)),
              if (_kind == 'quiz') ...[
                const SizedBox(width: 16),
                Flexible(child: Text(tr('Chạm chữ cái để chọn đáp án đúng'), style: TextStyle(color: t.sub, fontSize: 16))),
              ],
            ]),
          ],
        ],
      ]),
    );
  }

  int? _count(String q, String o) => ((_res(v, q)?['options'] as Map?)?[o] as num?)?.toInt();
}
