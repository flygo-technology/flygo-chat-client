import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../page_types.dart';
import 'builtin.dart' show pageField;

// Loại trang "Bình chọn & Trắc nghiệm" (máy chủ: relay/meet-pt-poll.mjs). Bình chọn: kết quả hiện ngay (trừ khi chủ trang tắt);
// Trắc nghiệm: có đáp án đúng, giấu kết quả tới khi công bố, mỗi câu trả lời một lần, bảng điểm. Ẩn danh: máy chủ không lưu ai chọn gì.

const _card = Color(0xFF2A2E35);
const _acc = Color(0xFF2BB3A3);
const _gold = Color(0xFFFFD36B);
const _ok = Color(0xFF4CC38A);
const _sub = Color(0xFF9AA0A6);
const _optColors = [Color(0xFFFFD36B), Color(0xFF7FD8CC), Color(0xFF8AB4F8), Color(0xFFF6AEA9), Color(0xFFC6B6FF), Color(0xFFA8DAB5)];

void registerPollPageType() {
  registerPageType(PageTypeSpec(
    type: 'poll',
    label: tr('Bình chọn / Trắc nghiệm'),
    desc: tr('Bình chọn nhanh hoặc trắc nghiệm có chấm điểm'),
    icon: Icons.poll_outlined,
    color: const Color(0xFFE8A33D),
    seconds: 120,
    create: (context, call) => showModalBottomSheet<PageDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const PollComposer(),
    ),
    view: (context, ctx) => PollView(ctx),
  ));
}

// ------------------------------------------------------------------ soạn
class _Q {
  final text = TextEditingController();
  final opts = [TextEditingController(), TextEditingController()];
  final correct = <int>{};
  bool multi = false;
  int seconds = 0;
  void dispose() {
    text.dispose();
    for (final o in opts) {
      o.dispose();
    }
  }
}

/// Bảng soạn bình chọn / trắc nghiệm (dùng cả cho app Bình chọn). Trả về PageDraft (init gửi cho máy chủ).
class PollComposer extends StatefulWidget {
  final bool quiz;
  const PollComposer({super.key, this.quiz = false});
  @override
  State<PollComposer> createState() => _PollComposerState();
}

class _PollComposerState extends State<PollComposer> {
  late String _kind = widget.quiz ? 'quiz' : 'poll'; // poll | quiz | vote
  bool get _quiz => _kind == 'quiz';
  bool get _vote => _kind == 'vote';
  int _quorum = 0, _threshold = 50;
  final _title = TextEditingController();
  final _qs = <_Q>[_Q()];
  bool _anon = false, _live = true;
  String? _err;

  @override
  void dispose() {
    _title.dispose();
    for (final q in _qs) {
      q.dispose();
    }
    super.dispose();
  }

  PageDraft? _draft() {
    if (_vote) {
      final t = _qs.first.text.text.trim();
      if (t.isEmpty) return _fail(tr('Hãy nhập nội dung cần biểu quyết'));
      return PageDraft(title: _title.text.trim().isEmpty ? t : _title.text.trim(), init: {'kind': 'vote', 'text': t, 'anon': _anon, 'quorum': _quorum, 'threshold': _threshold});
    }
    final qs = <Map<String, dynamic>>[];
    for (final (i, q) in _qs.indexed) {
      final opts = [for (final o in q.opts) o.text.trim()];
      final kept = [for (final (j, o) in opts.indexed) if (o.isNotEmpty) (j, o)];
      if (q.text.text.trim().isEmpty) return _fail(tr('Câu {0} chưa có nội dung', [i + 1]));
      if (kept.length < 2) return _fail(tr('Câu {0} cần ít nhất 2 lựa chọn', [i + 1]));
      if (_quiz && !kept.any((x) => q.correct.contains(x.$1))) return _fail(tr('Câu {0} chưa chọn đáp án đúng', [i + 1]));
      qs.add({
        'text': q.text.text.trim(),
        'options': [for (final (j, o) in kept) {'id': 'o$j', 'text': o}],
        'multi': q.multi,
        if (_quiz) 'correct': [for (final (j, _) in kept) if (q.correct.contains(j)) 'o$j'],
        if (_quiz && q.seconds > 0) 'seconds': q.seconds,
      });
    }
    final title = _title.text.trim().isEmpty ? qs.first['text'] as String : _title.text.trim();
    return PageDraft(
      title: title,
      seconds: _quiz ? 0 : 120,
      init: {'kind': _quiz ? 'quiz' : 'poll', 'anon': _anon, 'live': _live, 'questions': qs},
    );
  }

  PageDraft? _fail(String m) {
    setState(() => _err = m);
    return null;
  }

  Widget _question(int i, _Q q) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(tr('Câu {0}', [i + 1]), style: const TextStyle(color: _sub, fontSize: 12)),
            const Spacer(),
            if (_qs.length > 1)
              IconButton(
                tooltip: tr('Xoá câu này'),
                icon: const Icon(Icons.delete_outline, color: _sub, size: 20),
                onPressed: () => setState(() => _qs.removeAt(i).dispose()),
              ),
          ]),
          TextField(controller: q.text, style: const TextStyle(color: Colors.white), maxLines: 3, minLines: 1, decoration: pageField(tr('Câu hỏi'))),
          const SizedBox(height: 8),
          for (final (j, o) in q.opts.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                if (_quiz)
                  Checkbox(
                    value: q.correct.contains(j),
                    activeColor: _ok,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        if (!q.multi) q.correct.clear();
                        q.correct.add(j);
                      } else {
                        q.correct.remove(j);
                      }
                    }),
                  ),
                Expanded(child: TextField(controller: o, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Lựa chọn {0}', [j + 1])))),
                if (q.opts.length > 2)
                  IconButton(
                    icon: const Icon(Icons.close, color: _sub, size: 18),
                    onPressed: () => setState(() {
                      q.opts.removeAt(j).dispose();
                      q.correct.remove(j);
                    }),
                  ),
              ]),
            ),
          Row(children: [
            if (q.opts.length < 8)
              TextButton.icon(
                onPressed: () => setState(() => q.opts.add(TextEditingController())),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Thêm lựa chọn')),
              ),
            const Spacer(),
            Text(tr('Chọn nhiều'), style: const TextStyle(color: _sub, fontSize: 12)),
            Switch(value: q.multi, onChanged: (v) => setState(() => q.multi = v)),
          ]),
          if (_quiz)
            Row(children: [
              Text(tr('Thời gian trả lời'), style: const TextStyle(color: _sub, fontSize: 12)),
              const Spacer(),
              DropdownButton<int>(
                value: q.seconds,
                dropdownColor: const Color(0xFF3A3B3F),
                style: const TextStyle(color: Colors.white),
                items: [for (final s in [0, 15, 30, 60, 120]) DropdownMenuItem(value: s, child: Text(s == 0 ? tr('Không giới hạn') : tr('{0} giây', [s])))],
                onChanged: (v) => setState(() => q.seconds = v ?? 0),
              ),
            ]),
        ]),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'poll', label: Text(tr('Bình chọn')), icon: const Icon(Icons.how_to_vote_outlined)),
                  ButtonSegment(value: 'quiz', label: Text(tr('Trắc nghiệm')), icon: const Icon(Icons.quiz_outlined)),
                  ButtonSegment(value: 'vote', label: Text(tr('Biểu quyết')), icon: const Icon(Icons.gavel_outlined)),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() {
                  _kind = v.first;
                  _live = _kind == 'poll';
                }),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  TextField(controller: _title, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Tiêu đề (không bắt buộc)'))),
                  const SizedBox(height: 12),
                  if (_vote) ...[
                    TextField(controller: _qs.first.text, style: const TextStyle(color: Colors.white), maxLines: 4, minLines: 2, decoration: pageField(tr('Nội dung biểu quyết'))),
                    const SizedBox(height: 8),
                    Text(tr('Lựa chọn: Đồng ý · Không đồng ý · Phiếu trắng. Mỗi người một phiếu, không đổi.'), style: const TextStyle(color: _sub, fontSize: 12)),
                    Row(children: [
                      Expanded(child: Text(tr('Thông qua khi Đồng ý trên'), style: const TextStyle(color: Colors.white))),
                      DropdownButton<int>(
                        value: _threshold,
                        dropdownColor: const Color(0xFF3A3B3F),
                        style: const TextStyle(color: Colors.white),
                        items: [for (final t in [50, 66, 75]) DropdownMenuItem(value: t, child: Text('$t%'))],
                        onChanged: (v) => setState(() => _threshold = v ?? 50),
                      ),
                    ]),
                    Row(children: [
                      Expanded(child: Text(tr('Số phiếu tối thiểu'), style: const TextStyle(color: Colors.white))),
                      IconButton(onPressed: _quorum > 0 ? () => setState(() => _quorum--) : null, icon: const Icon(Icons.remove_circle_outline, color: Colors.white70)),
                      Text(_quorum == 0 ? tr('không') : '$_quorum', style: const TextStyle(color: Colors.white)),
                      IconButton(onPressed: () => setState(() => _quorum++), icon: const Icon(Icons.add_circle_outline, color: Colors.white70)),
                    ]),
                  ] else
                    for (final (i, q) in _qs.indexed) _question(i, q),
                  if (_quiz)
                    OutlinedButton.icon(onPressed: () => setState(() => _qs.add(_Q())), icon: const Icon(Icons.add), label: Text(tr('Thêm câu hỏi'))),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_vote ? tr('Bỏ phiếu kín') : tr('Ẩn danh'), style: const TextStyle(color: Colors.white)),
                    subtitle: Text(tr('Không ai biết ai chọn gì, kể cả người tạo'), style: const TextStyle(color: _sub, fontSize: 12)),
                    value: _anon,
                    onChanged: (v) => setState(() => _anon = v),
                  ),
                  if (_kind == 'poll')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Mọi người thấy kết quả ngay'), style: const TextStyle(color: Colors.white)),
                      subtitle: Text(tr('Tắt: kết quả hiện khi bạn công bố hoặc đóng'), style: const TextStyle(color: _sub, fontSize: 12)),
                      value: _live,
                      onChanged: (v) => setState(() => _live = v),
                    ),
                ]),
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: const TextStyle(color: Color(0xFFF28B82)))),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  final d = _draft();
                  if (d != null) Navigator.pop(context, d);
                },
                child: Text(_vote ? tr('Tạo biểu quyết') : _quiz ? tr('Tạo trắc nghiệm') : tr('Tạo bình chọn')),
              ),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------------------ hiện
/// Trang bình chọn / trắc nghiệm: trên sân khấu (lớn, chỉ đọc + nút điều khiển của người trình chiếu) hoặc để trả lời.
class PollView extends StatefulWidget {
  final PageCtx ctx;
  const PollView(this.ctx, {super.key});
  @override
  State<PollView> createState() => _PollViewState();
}

class _PollViewState extends State<PollView> {
  final _pick = <String, Set<String>>{}; // câu -> lựa chọn đang chọn (chưa gửi)
  bool _busy = false;

  PageCtx get ctx => widget.ctx;
  Map<String, dynamic> get v => ctx.view;
  bool get quiz => v['kind'] == 'quiz';
  bool get vote => v['kind'] == 'vote';
  /// Trắc nghiệm / biểu quyết: một lần, không đổi.
  bool get oneShot => quiz || vote;
  List<Map<String, dynamic>> get qs => [for (final q in (v['questions'] as List? ?? const [])) (q as Map).cast<String, dynamic>()];
  Map<String, dynamic>? resultOf(String q) => ((v['results'] as Map?)?[q] as Map?)?.cast<String, dynamic>();
  List<String> mineOf(String q) => [for (final x in ((v['mine'] as Map?)?[q] as List? ?? const [])) '$x'];

  Future<void> _act(String a, [Map<String, dynamic> body = const {}]) async {
    setState(() => _busy = true);
    try {
      await ctx.act(a, body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _option(Map<String, dynamic> q, Map o, int i, {required bool big}) {
    final id = '${o['id']}';
    final r = resultOf('${q['id']}');
    final total = (r?['total'] as num?)?.toInt() ?? 0;
    final n = ((r?['options'] as Map?)?[id] as num?)?.toInt() ?? 0;
    final pct = total == 0 ? 0.0 : n / total;
    final correct = [for (final x in (q['correct'] as List? ?? const [])) '$x'];
    final mine = mineOf('${q['id']}').contains(id);
    final picking = _pick['${q['id']}']?.contains(id) ?? false;
    final answeredQuiz = oneShot && mineOf('${q['id']}').isNotEmpty;
    final canTap = !big && !_busy && v['closed'] != true && ctx.data.role != 'viewer' && !(vote && ctx.data.role == 'guest') && !answeredQuiz && !(quiz && v['reveal'] == true);
    final color = vote ? const [Color(0xFF4CC38A), Color(0xFFF28B82), Color(0xFF9AA0A6)][i % 3] : _optColors[i % _optColors.length];
    return Padding(
      padding: EdgeInsets.only(bottom: big ? 12 : 8),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canTap
              ? () => setState(() {
                    final s = _pick.putIfAbsent('${q['id']}', () => {});
                    if (q['multi'] == true) {
                      s.contains(id) ? s.remove(id) : s.add(id);
                    } else {
                      s
                        ..clear()
                        ..add(id);
                    }
                  })
              : null,
          child: Stack(children: [
            if (r != null)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct,
                  child: Container(color: (correct.contains(id) ? _ok : color).withValues(alpha: .28)),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: picking || mine ? _acc : Colors.transparent, width: 2),
              ),
              padding: EdgeInsets.symmetric(horizontal: big ? 20 : 12, vertical: big ? 16 : 11),
              child: Row(children: [
                Container(width: big ? 14 : 10, height: big ? 14 : 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                SizedBox(width: big ? 14 : 10),
                Expanded(
                  child: Text('${o['text']}', style: TextStyle(color: Colors.white, fontSize: big ? 26 : 15, fontWeight: mine ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (correct.contains(id)) Icon(Icons.check_circle, color: _ok, size: big ? 28 : 18),
                if (mine && !big) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.how_to_vote, color: _acc, size: 18)),
                if (r != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text('$n · ${(pct * 100).round()}%',
                        style: TextStyle(color: Colors.white70, fontSize: big ? 22 : 13, fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _controls() => Wrap(spacing: 8, runSpacing: 8, children: [
        if (quiz && qs.length > 1) ...[
          OutlinedButton(onPressed: _busy || (v['current'] ?? 0) == 0 ? null : () => _act('goto', {'index': (v['current'] as int) - 1}), child: const Icon(Icons.chevron_left)),
          OutlinedButton(
              onPressed: _busy || (v['current'] ?? 0) >= qs.length - 1 ? null : () => _act('goto', {'index': (v['current'] as int) + 1}), child: const Icon(Icons.chevron_right)),
        ],
        if (quiz || (!vote && v['live'] != true))
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: const Color(0xFF2B2000)),
            onPressed: _busy ? null : () => _act(v['reveal'] == true ? 'hide' : 'reveal'),
            icon: Icon(v['reveal'] == true ? Icons.visibility_off_outlined : Icons.campaign_outlined),
            label: Text(v['reveal'] == true ? tr('Ẩn kết quả') : tr('Công bố')),
          ),
        OutlinedButton(
            onPressed: _busy ? null : () => _act(v['closed'] == true ? 'reopen' : 'close'),
            child: Text(v['closed'] == true ? tr('Mở lại') : vote ? tr('Kết thúc biểu quyết') : tr('Đóng'))),
      ]);

  /// Biểu quyết đã kết thúc: THÔNG QUA / KHÔNG THÔNG QUA.
  Widget? _outcome({required bool big}) {
    final o = (v['outcome'] as Map?)?.cast<String, dynamic>();
    if (!vote || o == null || v['closed'] != true) return null;
    final ok = o['passed'] == true;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 28 : 14, vertical: big ? 14 : 8),
      decoration: BoxDecoration(color: ok ? const Color(0xFF1F4A35) : const Color(0xFF4A1F1F), borderRadius: BorderRadius.circular(12)),
      child: Text(
        '${ok ? tr('✅ THÔNG QUA') : tr('❌ KHÔNG THÔNG QUA')} · ${tr('{0}/{1} đồng ý', [o['yes'], o['voters']])}${o['quorum_met'] == false ? ' · ${tr('chưa đủ số phiếu tối thiểu')}' : ''}',
        style: TextStyle(color: ok ? _ok : const Color(0xFFF28B82), fontSize: big ? 30 : 15, fontWeight: FontWeight.w800),
      ),
    );
  }

  // Sân khấu: câu hiện tại (trắc nghiệm) hoặc câu đầu (bình chọn), chữ to, số người đã trả lời.
  Widget _stage() {
    if (qs.isEmpty) return const SizedBox.shrink();
    final cur = quiz ? ((v['current'] as num?)?.toInt() ?? 0).clamp(0, qs.length - 1) : 0;
    final q = qs[cur];
    final opts = [for (final o in (q['options'] as List? ?? const [])) o as Map];
    return LayoutBuilder(
      builder: (context, box) => FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 1280,
          height: 720,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(64, 48, 64, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(quiz ? Icons.quiz_outlined : vote ? Icons.gavel_outlined : Icons.how_to_vote_outlined, color: _gold, size: 30),
                const SizedBox(width: 12),
                Text(quiz ? tr('Trắc nghiệm · câu {0}/{1}', [cur + 1, qs.length]) : vote ? tr('Biểu quyết') : tr('Bình chọn'), style: const TextStyle(color: _gold, fontSize: 24, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(tr('{0} người đã trả lời', [v['voters'] ?? 0]), style: const TextStyle(color: Colors.white70, fontSize: 24)),
              ]),
              const SizedBox(height: 22),
              Text('${q['text']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 28),
              for (final (i, o) in opts.indexed) _option(q, o, i, big: true),
              const Spacer(),
              ?_outcome(big: true),
              if (resultOf('${q['id']}') == null)
                Text(tr('Kết quả sẽ hiện khi công bố'), style: const TextStyle(color: _sub, fontSize: 22)),
              if (quiz && v['reveal'] == true && v['leaderboard'] is List && (v['leaderboard'] as List).isNotEmpty)
                Text('🏆 ${[for (final x in (v['leaderboard'] as List).take(3)) '${(x as Map)['name']} ${x['score']}/${x['of']}'].join('   ·   ')}',
                    style: const TextStyle(color: _gold, fontSize: 24, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _viewer() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('${v['title'] ?? ctx.page.title}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
        if (v['anon'] == true) const Chip(label: Text('🕶 ẩn danh'), visualDensity: VisualDensity.compact),
      ]),
      const SizedBox(height: 4),
      Text(
        [
          tr('{0} người đã trả lời', [v['voters'] ?? 0]),
          if (v['closed'] == true) tr('đã đóng'),
          if (quiz && v['reveal'] != true) tr('kết quả hiện khi công bố'),
          if (vote && v['closed'] != true) tr('kết quả hiện khi kết thúc'),
          if (vote && ((v['quorum'] as num?) ?? 0) > 0) tr('tối thiểu {0} phiếu', [v['quorum']]),
          if (quiz && v['my_score'] != null) tr('điểm của bạn: {0}/{1}', [v['my_score'], qs.length]),
        ].join(' · '),
        style: const TextStyle(color: _sub, fontSize: 13),
      ),
      const SizedBox(height: 14),
      if (_outcome(big: false) case final o?) ...[o, const SizedBox(height: 12)],
      for (final q in qs) ...[
        Text('${q['text']}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        if (q['multi'] == true) Text(tr('Chọn một hoặc nhiều'), style: const TextStyle(color: _sub, fontSize: 12)),
        const SizedBox(height: 8),
        for (final (i, o) in [for (final o in (q['options'] as List? ?? const [])) o as Map].indexed) _option(q, o, i, big: false),
        if ((_pick['${q['id']}'] ?? const {}).isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final sel = _pick.remove('${q['id']}')!.toList();
                      await _act('answer', {'q': q['id'], 'options': sel});
                    },
              child: Text(mineOf('${q['id']}').isEmpty ? (vote ? tr('Bỏ phiếu') : tr('Gửi')) : tr('Đổi lựa chọn')),
            ),
          ),
        const SizedBox(height: 14),
      ],
      if (ctx.control) ...[const Divider(color: Colors.white12), _controls()],
      if (quiz && v['leaderboard'] is List && (v['leaderboard'] as List).isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(tr('Bảng điểm'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        for (final x in (v['leaderboard'] as List).take(10))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${(x as Map)['name']}', style: const TextStyle(color: Colors.white)),
            trailing: Text('${x['score']}/${x['of']}', style: const TextStyle(color: Colors.white70)),
          ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => ctx.onStage
      ? Stack(children: [
          Positioned.fill(child: _stage()),
          if (ctx.presenting) Positioned(right: 12, bottom: 12, child: Material(color: Colors.black54, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.all(8), child: _controls()))),
        ])
      : _viewer();
}
