import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../page_types.dart';
import '../stage_frame.dart';
import 'builtin.dart' show pageField;

// Loại trang "Hỏi đáp & Thảo luận" (máy chủ: relay/meet-pt-qa.mjs). Ai cũng hỏi được (có thể ẩn danh thật), bấm 👍, trả lời;
// chủ trang / chủ trì / người trình chiếu ghim, đánh dấu đã trả lời, chọn câu trả lời. Sân khấu chiếu câu đang được trả lời.

const _card = Color(0xFF2A2E35);
const _sub = Color(0xFF9AA0A6);
const _blue = Color(0xFF8AB4F8);
const _gold = Color(0xFFFFD36B);
const _okBg = Color(0xFF1F4A35);
const _okTx = Color(0xFFA6F0C9);

void registerQaPageType() {
  registerPageType(PageTypeSpec(
    type: 'qa',
    label: tr('Hỏi đáp & Thảo luận'),
    desc: tr('Đặt câu hỏi, bấm 👍, trả lời; có thể ẩn danh'),
    icon: Icons.question_answer_outlined,
    color: const Color(0xFF1A73E8),
    create: (context, call) => showModalBottomSheet<PageDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => QaComposer(defaultTitle: tr('Hỏi đáp: {0}', [call.meetingInfo?.title ?? tr('cuộc họp')])),
    ),
    view: (context, ctx) => QaView(ctx),
    stageThemed: true,
    // 2026-11-21 (Sếp): thay bằng Thảo luận; trang Hỏi đáp cũ chỉ còn xem.
    hidden: true,
  ));
}

/// Bảng tạo chủ đề hỏi đáp (dùng cả cho app Hỏi đáp).
class QaComposer extends StatefulWidget {
  final String defaultTitle;
  const QaComposer({super.key, this.defaultTitle = ''});
  @override
  State<QaComposer> createState() => _QaComposerState();
}

class _QaComposerState extends State<QaComposer> {
  late final _title = TextEditingController(text: widget.defaultTitle);
  final _desc = TextEditingController();
  bool _anon = true;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Chủ đề hỏi đáp mới'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(controller: _title, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Tên chủ đề'))),
            const SizedBox(height: 10),
            TextField(controller: _desc, style: const TextStyle(color: Colors.white), maxLines: 3, minLines: 1, decoration: pageField(tr('Mô tả (không bắt buộc)'))),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Cho hỏi ẩn danh'), style: const TextStyle(color: Colors.white)),
              subtitle: Text(tr('Không ai thấy tên người hỏi, kể cả quản trị'), style: const TextStyle(color: _sub, fontSize: 12)),
              value: _anon,
              onChanged: (v) => setState(() => _anon = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                final t = _title.text.trim();
                if (t.isEmpty) return;
                Navigator.pop(context, PageDraft(title: t, init: {'title': t, 'desc': _desc.text.trim(), 'allow_anon': _anon}));
              },
              child: Text(tr('Tạo chủ đề')),
            ),
          ]),
        ),
      );
}

/// Trang hỏi đáp: sân khấu (câu ghim / nhiều 👍 nhất, chữ to) hoặc danh sách để hỏi, 👍, trả lời.
class QaView extends StatefulWidget {
  final PageCtx ctx;
  const QaView(this.ctx, {super.key});
  @override
  State<QaView> createState() => _QaViewState();
}

class _QaViewState extends State<QaView> {
  final _ask = TextEditingController();
  bool _anon = false, _busy = false;
  String _sort = 'top';
  String? _open; // câu đang mở xem trả lời
  final _reply = TextEditingController();

  PageCtx get ctx => widget.ctx;
  Map<String, dynamic> get v => ctx.view;
  List<Map<String, dynamic>> get qs => [for (final q in (v['questions'] as List? ?? const [])) (q as Map).cast<String, dynamic>()];

  @override
  void dispose() {
    _ask.dispose();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _act(String a, Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      await ctx.act(a, body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _sorted() {
    final l = [...qs];
    if (_sort == 'new') l.sort((a, b) => ((b['at'] as num?) ?? 0).compareTo((a['at'] as num?) ?? 0));
    if (_sort == 'open') l.retainWhere((q) => q['answered'] != true);
    return l; // 'top': máy chủ đã xếp (ghim > chưa trả lời > 👍 > mới)
  }

  // Sân khấu (mockup Họp): câu đang trả lời lớn trong ô nổi bật (số ▲, người hỏi, câu trả lời được chọn), bên phải các câu
  // nhiều người quan tâm. Màu theo bảng màu sân khấu.
  Widget _stage() {
    final m = StageMetrics.of(context);
    if (m == null) return FittedBox(fit: BoxFit.contain, child: SizedBox(width: 1168, height: 560, child: _stageBody(const StageTheme(), false)));
    return _stageBody(m.theme, m.portrait);
  }

  Widget _stageBody(StageTheme t, bool portrait) {
    final list = qs.where((q) => q['hidden'] != true).toList();
    final q = list.where((q) => q['pinned'] == true).firstOrNull ?? list.where((q) => q['answered'] != true).firstOrNull ?? list.firstOrNull;
    const gold = Color(0xFFF5B544);
    if (q == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: gold.withValues(alpha: .16), borderRadius: BorderRadius.circular(22)),
            child: const Icon(Icons.forum_outlined, color: gold, size: 40),
          ),
          const SizedBox(height: 18),
          Text(tr('Có gì muốn hỏi không?'), style: TextStyle(color: t.text, fontSize: portrait ? 26 : 38, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(tr('Đặt câu hỏi trên app, được hỏi ẩn danh. Câu được nhiều người bấm ▲ sẽ lên đầu.'), textAlign: TextAlign.center, style: TextStyle(color: t.sub, fontSize: portrait ? 15 : 20)),
        ]),
      );
    }
    final accepted = [for (final a in (q['answers'] as List? ?? const [])) if ((a as Map)['accepted'] == true) a].firstOrNull;
    final pinned = q['pinned'] == true;
    final main = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(pinned ? tr('ĐANG TRẢ LỜI') : tr('CÂU NHIỀU NGƯỜI QUAN TÂM'), style: TextStyle(color: gold, fontSize: portrait ? 12 : 14, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: EdgeInsets.all(portrait ? 20 : 32),
        decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: gold.withValues(alpha: pinned ? .6 : .25), width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${q['text']}', maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: portrait ? 24 : 36, fontWeight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: gold.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.arrow_upward_rounded, size: 16, color: gold),
                const SizedBox(width: 6),
                Text('${q['votes'] ?? 0}', style: const TextStyle(color: gold, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 14),
            Flexible(child: Text(q['anon'] == true ? tr('Ẩn danh') : '${q['by_name'] ?? ''}', style: TextStyle(color: t.sub, fontSize: portrait ? 14 : 17))),
          ]),
          if (accepted != null) ...[
            Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 16), color: t.line),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE8710A),
                child: Text('${accepted['by_name'] ?? '?'}'.trim().characters.firstOrNull?.toUpperCase() ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${accepted['by_name'] ?? ''} · ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: '${accepted['text'] ?? ''}'),
                  ]),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.text, fontSize: portrait ? 15 : 19, height: 1.45),
                ),
              ),
            ]),
          ],
        ]),
      ),
    ]);
    final others = [for (final x in list) if (x != q) x]..sort((a, b) => ((b['votes'] as num?) ?? 0).compareTo((a['votes'] as num?) ?? 0));
    if (portrait || others.isEmpty) return SingleChildScrollView(child: main);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: main),
      const SizedBox(width: 32),
      SizedBox(
        width: 400,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('NHIỀU NGƯỜI QUAN TÂM'), style: TextStyle(color: t.sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
          const SizedBox(height: 12),
          for (final x in others.take(4))
            Opacity(
              opacity: x['answered'] == true ? .6 : 1,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  SizedBox(
                    width: 52,
                    child: x['answered'] == true
                        ? const Icon(Icons.check_rounded, color: Color(0xFF38C793))
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('${x['votes'] ?? 0}', style: TextStyle(color: t.text, fontSize: 20, fontWeight: FontWeight.w800)),
                            Icon(Icons.arrow_upward_rounded, size: 14, color: t.accent),
                          ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${x['text']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 16, height: 1.35)),
                      const SizedBox(height: 3),
                      Text(x['answered'] == true ? tr('Đã trả lời') : (x['anon'] == true ? tr('Ẩn danh') : '${x['by_name'] ?? ''}'), style: TextStyle(color: t.sub, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _question(Map<String, dynamic> q) {
    final id = '${q['id']}';
    final answers = [for (final a in (q['answers'] as List? ?? const [])) (a as Map).cast<String, dynamic>()];
    final open = _open == id;
    final canReply = ctx.data.role != 'viewer';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: q['pinned'] == true ? Border.all(color: _gold) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = open ? null : id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Material(
                color: q['voted'] == true ? const Color(0xFF1F3448) : const Color(0xFF1F2227),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _busy || !canReply ? null : () => _act('vote', {'q': id}),
                  child: SizedBox(
                    width: 48,
                    height: 50,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(q['voted'] == true ? Icons.thumb_up : Icons.thumb_up_outlined, size: 16, color: q['voted'] == true ? _blue : Colors.white70),
                      Text('${q['votes']}', style: TextStyle(color: q['voted'] == true ? _blue : Colors.white, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${q['pinned'] == true ? '📌 ' : ''}${q['text']}', style: const TextStyle(color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(q['anon'] == true ? tr('Ẩn danh') : '${q['by_name']}', style: const TextStyle(color: _sub, fontSize: 12)),
                    if (q['mine'] == true) Text(tr('của bạn'), style: const TextStyle(color: _blue, fontSize: 12)),
                    if (answers.isNotEmpty) Text(tr('{0} trả lời', [answers.length]), style: const TextStyle(color: _sub, fontSize: 12)),
                    if (q['answered'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(color: _okBg, borderRadius: BorderRadius.circular(10)),
                        child: Text(tr('Đã trả lời'), style: const TextStyle(color: _okTx, fontSize: 11)),
                      ),
                    if (q['hidden'] == true) Text(tr('đã ẩn'), style: const TextStyle(color: Color(0xFFF28B82), fontSize: 12)),
                  ]),
                ]),
              ),
              if (ctx.control || q['mine'] == true)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: _sub, size: 20),
                  color: const Color(0xFF3A3B3F),
                  onSelected: (a) => _act(a, {'q': id}),
                  itemBuilder: (_) => [
                    if (ctx.control) ...[
                      PopupMenuItem(value: 'pin', child: Text(q['pinned'] == true ? tr('Bỏ ghim') : tr('Ghim (chiếu lên sân khấu)'), style: const TextStyle(color: Colors.white))),
                      PopupMenuItem(value: 'answered', child: Text(q['answered'] == true ? tr('Bỏ đánh dấu đã trả lời') : tr('Đánh dấu đã trả lời'), style: const TextStyle(color: Colors.white))),
                    ],
                    if (ctx.data.manage) PopupMenuItem(value: 'hide', child: Text(q['hidden'] == true ? tr('Hiện lại') : tr('Ẩn câu hỏi'), style: const TextStyle(color: Colors.white))),
                    if (q['mine'] == true || ctx.data.manage)
                      PopupMenuItem(value: 'delete', child: Text(tr('Xoá câu hỏi'), style: const TextStyle(color: Color(0xFFF28B82)))),
                  ],
                ),
            ]),
          ),
        ),
        if (open) ...[
          for (final a in answers)
            Padding(
              padding: const EdgeInsets.fromLTRB(66, 0, 8, 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: a['accepted'] == true ? _okBg : const Color(0xFF1F2227), borderRadius: BorderRadius.circular(10)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${a['by_name']}  ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      TextSpan(text: '${a['text']}', style: const TextStyle(color: Colors.white70)),
                    ])),
                  ),
                  if (ctx.control)
                    IconButton(
                      tooltip: a['accepted'] == true ? tr('Bỏ chọn') : tr('Chọn là câu trả lời'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(a['accepted'] == true ? Icons.check_circle : Icons.check_circle_outline, color: _okTx, size: 20),
                      onPressed: _busy ? null : () => _act('accept', {'q': id, 'a': a['id']}),
                    ),
                ]),
              ),
            ),
          if (canReply)
            Padding(
              padding: const EdgeInsets.fromLTRB(66, 0, 8, 10),
              child: Row(children: [
                Expanded(child: TextField(controller: _reply, style: const TextStyle(color: Colors.white), minLines: 1, maxLines: 4, decoration: pageField(tr('Viết trả lời…')))),
                IconButton(
                  icon: const Icon(Icons.send, color: _blue),
                  onPressed: _busy
                      ? null
                      : () async {
                          final t = _reply.text.trim();
                          if (t.isEmpty) return;
                          _reply.clear();
                          await _act('answer', {'q': id, 'text': t});
                        },
                ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _viewer() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${v['title'] ?? ctx.page.title}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            if ('${v['desc'] ?? ''}'.isNotEmpty) Text('${v['desc']}', style: const TextStyle(color: _sub, fontSize: 13)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'top', label: Text(tr('Nhiều 👍'))),
                ButtonSegment(value: 'new', label: Text(tr('Mới nhất'))),
                ButtonSegment(value: 'open', label: Text(tr('Chưa trả lời'))),
              ],
              selected: {_sort},
              onSelectionChanged: (s) => setState(() => _sort = s.first),
            ),
          ]),
        ),
        Expanded(
          child: qs.isEmpty
              ? Center(child: Text(tr('Chưa có câu hỏi nào. Hãy là người đầu tiên.'), style: const TextStyle(color: _sub)))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), children: [for (final q in _sorted()) _question(q)]),
        ),
        if (ctx.data.role != 'viewer')
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(children: [
                Expanded(child: TextField(controller: _ask, style: const TextStyle(color: Colors.white), minLines: 1, maxLines: 4, maxLength: 1000, decoration: pageField(tr('Đặt câu hỏi…')).copyWith(counterText: ''))),
                if (v['allow_anon'] != false)
                  IconButton(
                    tooltip: _anon ? tr('Đang hỏi ẩn danh') : tr('Hỏi ẩn danh'),
                    icon: Text('🕶', style: TextStyle(fontSize: 20, color: _anon ? null : Colors.white38)),
                    isSelected: _anon,
                    onPressed: () => setState(() => _anon = !_anon),
                  ),
                IconButton.filled(
                  onPressed: _busy
                      ? null
                      : () async {
                          final t = _ask.text.trim();
                          if (t.isEmpty) return;
                          _ask.clear();
                          await _act('ask', {'text': t, 'anon': _anon});
                        },
                  icon: const Icon(Icons.send, size: 20),
                ),
              ]),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) => ctx.onStage ? _stage() : _viewer();
}
