import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../page_types.dart';
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

  Widget _stage() {
    final list = qs.where((q) => q['hidden'] != true).toList();
    final q = list.where((q) => q['pinned'] == true).firstOrNull ?? list.where((q) => q['answered'] != true).firstOrNull ?? list.firstOrNull;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 1280,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(72, 56, 72, 48),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.question_answer_outlined, color: _blue, size: 30),
              const SizedBox(width: 12),
              Expanded(child: Text('${v['title'] ?? ctx.page.title}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: _blue, fontSize: 26, fontWeight: FontWeight.w600))),
              Text(tr('{0} câu · {1} chờ trả lời', [v['total'] ?? 0, v['open'] ?? 0]), style: const TextStyle(color: Colors.white70, fontSize: 24)),
            ]),
            const Spacer(),
            if (q == null)
              Text(tr('Chưa có câu hỏi. Mở trang này trên điện thoại để đặt câu hỏi.'), style: const TextStyle(color: Colors.white70, fontSize: 34))
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF3D3010), borderRadius: BorderRadius.circular(20)),
                child: Text(q['pinned'] == true ? tr('📌 Đang trả lời · 👍 {0}', [q['votes']]) : tr('👍 {0}', [q['votes']]),
                    style: const TextStyle(color: _gold, fontSize: 24, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 22),
              Text('${q['text']}', maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w700, height: 1.25)),
              const SizedBox(height: 18),
              Text(q['anon'] == true ? tr('Ẩn danh') : '${q['by_name']}', style: const TextStyle(color: Colors.white60, fontSize: 26)),
              if ((q['answers'] as List? ?? const []).any((a) => (a as Map)['accepted'] == true)) ...[
                const SizedBox(height: 22),
                Text(
                  '✅ ${[for (final a in q['answers'] as List) if ((a as Map)['accepted'] == true) '${a['by_name']}: ${a['text']}'].first}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _okTx, fontSize: 30),
                ),
              ],
            ],
            const Spacer(),
          ]),
        ),
      ),
    );
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
