import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../app_kit.dart';
import '../page_types.dart';
import '../stage_frame.dart';
import 'poll_app.dart';
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
    view: (context, ctx) => AppScope.of(context).editing ? PollEditor(ctx) : PollView(ctx),
    stageThemed: true,
    // Mỗi trang là một app (mockup 21/11): người xem chạm để chọn, chủ trang điều khiển và sửa tại chỗ.
    panel: (context, ctx) => PollPanel(ctx),
    controls: (context, ctx) => PollControls(ctx),
    inlineEdit: true,
    stageLabel: (ctx) => switch (ctx.view['kind']) { 'quiz' => tr('Trắc nghiệm'), 'vote' => tr('Biểu quyết'), _ => tr('Bình chọn') },
    // Thanh cuối: số người đã trả lời / bỏ phiếu + cách tham gia; giờ còn lại của trang ở bên phải.
    stageFooter: (context, ctx) {
      final t = StageMetrics.themeOf(context);
      final v = ctx.view;
      final vote = v['kind'] == 'vote';
      final code = ctx.call.meetingInfo?.code ?? '';
      final st = ctx.call.roomStage ?? const {};
      final ends = (st['ends_at'] as num?)?.toInt() ?? 0;
      final left = ends == 0 ? 0 : ends - DateTime.now().millisecondsSinceEpoch;
      String two(int n) => n.toString().padLeft(2, '0');
      final s = (left / 1000).ceil().clamp(0, 359999);
      return [
        StagePill(vote ? tr('{0} đã bỏ phiếu', [v['voters'] ?? 0]) : tr('{0} đã trả lời', [v['voters'] ?? 0]), icon: Icons.groups_outlined, theme: t),
        if (code.isNotEmpty && v['closed'] != true) StagePill(tr('Trả lời trên app Flygo · mã {0}', [code]), theme: t, accent: true),
        if (left > 0) ...[const Spacer(), StagePill('${two(s ~/ 60)}:${two(s % 60)}', icon: Icons.timer_outlined, theme: t)],
      ];
    },
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

  // Sân khấu (mockup Họp): câu hỏi lớn, thanh kết quả chạy theo phần trăm; trắc nghiệm công bố = ô đáp án đúng sáng lên
  // + bảng điểm; biểu quyết = thanh Đồng ý / Không / Trắng, vạch ngưỡng, dấu THÔNG QUA. Màu theo bảng màu sân khấu.
  Widget _stage() {
    if (qs.isEmpty) return const SizedBox.shrink();
    final m = StageMetrics.of(context);
    final body = m == null
        ? FittedBox(fit: BoxFit.contain, child: SizedBox(width: 1168, height: 560, child: _stageBody(const StageTheme(), false)))
        : _stageBody(m.theme, m.portrait);
    return body;
  }

  Widget _stageBody(StageTheme t, bool portrait) {
    final cur = quiz ? ((v['current'] as num?)?.toInt() ?? 0).clamp(0, qs.length - 1) : 0;
    final q = qs[cur];
    final opts = [for (final o in (q['options'] as List? ?? const [])) o as Map];
    final r = resultOf('${q['id']}');
    final total = (r?['total'] as num?)?.toInt() ?? 0;
    final correct = [for (final x in (q['correct'] as List? ?? const [])) '$x'];
    int count(Map o) => ((r?['options'] as Map?)?['${o['id']}'] as num?)?.toInt() ?? 0;
    final title = Text(
      '${q['text']}',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: t.text, fontSize: portrait ? 28 : 46, fontWeight: FontWeight.w800, height: 1.15),
    );
    final hint = Text(
      [
        if (quiz) tr('Câu {0} / {1}', [cur + 1, qs.length]),
        if (!vote) q['multi'] == true ? tr('Chọn một hoặc nhiều') : tr('Chọn một'),
        if (v['anon'] == true) vote ? tr('phiếu kín') : tr('ẩn danh'),
        if (r == null && !vote) tr('kết quả hiện khi công bố') else if (!vote && v['live'] == true) tr('kết quả hiện trực tiếp'),
        if (v['closed'] == true) tr('đã đóng'),
      ].join(' · '),
      style: TextStyle(color: t.sub, fontSize: portrait ? 14 : 17),
    );

    if (vote) return _voteStage(t, portrait, q, opts, title);

    // Trắc nghiệm đã công bố: lưới ô đáp án (đúng sáng, sai mờ) + bảng điểm.
    if (quiz && v['reveal'] == true && r != null) {
      final board = [for (final x in (v['leaderboard'] as List? ?? const [])) (x as Map)];
      final cells = GridView.count(
        crossAxisCount: portrait ? 1 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: portrait ? 5.2 : 3.6,
        children: [
          for (final (i, o) in opts.indexed)
            Opacity(
              opacity: correct.contains('${o['id']}') ? 1 : .4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: correct.contains('${o['id']}') ? const Color(0xFF38C793).withValues(alpha: .16) : t.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: correct.contains('${o['id']}') ? Border.all(color: const Color(0xFF38C793), width: 2) : null,
                ),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: correct.contains('${o['id']}') ? const Color(0xFF38C793) : t.surface2, borderRadius: BorderRadius.circular(12)),
                    child: Text(String.fromCharCode(65 + i), style: TextStyle(color: correct.contains('${o['id']}') ? const Color(0xFF06281B) : t.text, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Text('${o['text']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: portrait ? 18 : 24, fontWeight: FontWeight.w600))),
                  Text('${count(o)}', style: TextStyle(color: t.text, fontSize: portrait ? 20 : 28, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
        ],
      );
      final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 8), hint, SizedBox(height: portrait ? 16 : 28), cells]);
      if (portrait || board.isEmpty) return SingleChildScrollView(child: left);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: left),
        const SizedBox(width: 40),
        SizedBox(
          width: 340,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('BẢNG ĐIỂM'), style: TextStyle(color: t.sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
            const SizedBox(height: 12),
            for (final (i, x) in board.take(5).indexed)
              Container(
                height: 52,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: i == 0 ? const Color(0xFFF5B544).withValues(alpha: .14) : t.surface, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  SizedBox(width: 26, child: Text('${i + 1}', style: TextStyle(color: i == 0 ? const Color(0xFFF5B544) : t.sub, fontWeight: FontWeight.w700, fontSize: 17))),
                  Expanded(child: Text('${x['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 17))),
                  Text('${x['score']}/${x['of']}', style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
                ]),
              ),
          ]),
        ),
      ]);
    }

    // Bình chọn (và trắc nghiệm chưa công bố): mỗi phương án một dòng: tên, số phiếu, % lớn, thanh màu chạy.
    Widget opt(int i, Map o) {
      final n = count(o);
      final pct = total == 0 ? 0.0 : n / total;
      final color = t.series[i % t.series.length];
      return Padding(
        padding: EdgeInsets.only(bottom: portrait ? 16 : 26),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (r == null) ...[
              Container(
                width: portrait ? 30 : 40,
                height: portrait ? 30 : 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
                child: Text(String.fromCharCode(65 + i), style: TextStyle(color: color, fontSize: portrait ? 15 : 20, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Flexible(child: Text('${o['text']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: portrait ? 18 : 26, fontWeight: FontWeight.w600))),
                if (r != null) ...[const SizedBox(width: 14), Text(tr('{0} phiếu', [n]), maxLines: 1, style: TextStyle(color: t.sub, fontSize: portrait ? 13 : 17))],
              ]),
            ),
            if (r != null) ...[
              Text('${(pct * 100).round()}%', style: TextStyle(color: t.text, fontSize: portrait ? 26 : 40, fontWeight: FontWeight.w800, height: 1)),
            ],
          ]),
          if (r != null) ...[
            SizedBox(height: portrait ? 8 : 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Container(
                height: portrait ? 14 : 22,
                color: t.surface2,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (_, x, _) => FractionallySizedBox(
                    widthFactor: x,
                    child: Container(decoration: BoxDecoration(color: correct.contains('${o['id']}') ? const Color(0xFF38C793) : color, borderRadius: BorderRadius.circular(11))),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title,
      const SizedBox(height: 8),
      hint,
      SizedBox(height: portrait ? 22 : 40),
      Expanded(child: ListView(padding: EdgeInsets.zero, physics: const NeverScrollableScrollPhysics(), children: [for (final (i, o) in opts.indexed) opt(i, o)])),
    ]);
  }

  Widget _voteStage(StageTheme t, bool portrait, Map<String, dynamic> q, List<Map> opts, Widget title) {
    final o = (v['outcome'] as Map?)?.cast<String, dynamic>();
    final closed = v['closed'] == true;
    final thr = ((v['threshold'] as num?) ?? (o?['threshold'] as num?) ?? 50).toDouble();
    final quorum = ((v['quorum'] as num?) ?? 0).toInt();
    const yesC = Color(0xFF38C793), noC = Color(0xFFF0646A), blankC = Color(0xFF6B7686);
    if (o == null || !closed) {
      // Đang bỏ phiếu: chưa lộ kết quả, chỉ số người đã bỏ phiếu.
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title,
        const Spacer(),
        Text(tr('ĐANG BỎ PHIẾU'), style: TextStyle(color: Color.lerp(t.accent, t.light ? Colors.black : Colors.white, .35), fontSize: portrait ? 13 : 16, fontWeight: FontWeight.w700, letterSpacing: 2)),
        const SizedBox(height: 6),
        Text(tr('{0} đã bỏ phiếu', [v['voters'] ?? 0]), style: TextStyle(color: t.text, fontSize: portrait ? 40 : 72, fontWeight: FontWeight.w800)),
        Text(
          [tr('Thông qua khi Đồng ý > {0}%', [thr.round()]), if (quorum > 0) tr('tối thiểu {0} phiếu', [quorum]), if (v['anon'] == true) tr('phiếu kín')].join(' · '),
          style: TextStyle(color: t.sub, fontSize: portrait ? 14 : 18),
        ),
        const Spacer(),
      ]);
    }
    final yes = (o['yes'] as num?)?.toInt() ?? 0, no = (o['no'] as num?)?.toInt() ?? 0, blank = (o['abstain'] as num?)?.toInt() ?? 0;
    final voters = (o['voters'] as num?)?.toInt() ?? 0;
    final ok = o['passed'] == true;
    final pct = voters == 0 ? 0 : (yes * 100 / voters).round();
    final stamp = Transform.rotate(
      angle: -.12,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: portrait ? 16 : 28, vertical: portrait ? 10 : 16),
        decoration: BoxDecoration(border: Border.all(color: ok ? yesC : noC, width: portrait ? 4 : 6), borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(ok ? tr('THÔNG QUA') : tr('KHÔNG THÔNG QUA'), style: TextStyle(color: ok ? yesC : noC, fontSize: portrait ? 26 : 44, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          Text(
            o['quorum_met'] == false ? tr('chưa đủ {0} phiếu tối thiểu', [quorum]) : tr('{0}% đồng ý · cần > {1}%', [pct, thr.round()]),
            style: TextStyle(color: (ok ? yesC : noC).withValues(alpha: .85), fontSize: portrait ? 12 : 16),
          ),
        ]),
      ),
    );
    Widget k(int n, String label, Color c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$n', style: TextStyle(color: c, fontSize: portrait ? 32 : 56, fontWeight: FontWeight.w800, height: 1)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: t.sub, fontSize: portrait ? 13 : 17)),
          ]),
        ]);
    final bar = LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: portrait ? 64 : 88,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: portrait ? 36 : 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Row(children: [
                if (yes > 0) Expanded(flex: yes, child: Container(color: yesC)),
                if (no > 0) Expanded(flex: no, child: Container(color: noC)),
                if (blank > 0) Expanded(flex: blank, child: Container(color: blankC)),
                if (voters == 0) Expanded(child: Container(color: t.surface2)),
              ]),
            ),
          ),
          Positioned(left: box.maxWidth * thr / 100, top: -10, width: 2, height: portrait ? 56 : 80, child: Container(color: t.text)),
          Positioned(
            left: box.maxWidth * thr / 100 + 10,
            top: portrait ? 42 : 62,
            child: Text(tr('Ngưỡng {0}%', [thr.round()]), style: TextStyle(color: t.text, fontSize: portrait ? 12 : 14, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (portrait) ...[title, const SizedBox(height: 18), Align(alignment: Alignment.centerLeft, child: stamp)] else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: title), const SizedBox(width: 24), stamp]),
      const Spacer(),
      bar,
      SizedBox(height: portrait ? 14 : 22),
      Wrap(spacing: portrait ? 24 : 64, runSpacing: 12, children: [
        k(yes, tr('Đồng ý'), yesC),
        k(no, tr('Không đồng ý'), noC),
        k(blank, tr('Phiếu trắng'), t.text),
        if (quorum > 0) k(voters, o['quorum_met'] == false ? tr('Phiếu · chưa đủ túc số ({0})', [quorum]) : tr('Phiếu · đủ túc số ({0})', [quorum]), t.text),
      ]),
      const Spacer(),
    ]);
  }

  Widget _viewer() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('${v['title'] ?? ctx.page.title}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700))),
        if (v['anon'] == true) Chip(label: Text(vote ? tr('🔒 phiếu kín') : tr('🕶 ẩn danh')), visualDensity: VisualDensity.compact),
      ]),
      const SizedBox(height: 4),
      Text(
        [
          vote ? tr('{0} người đã bỏ phiếu', [v['voters'] ?? 0]) : tr('{0} người đã trả lời', [v['voters'] ?? 0]),
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
          if (ctx.presenting)
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(color: StageMetrics.themeOf(context).surface, borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.all(8), child: _controls())),
            ),
        ])
      : _viewer();
}
