import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../bang_tin/discussion_page.dart' show DiscussionLoader, kStances;
import '../page_types.dart';
import '../stage_frame.dart';
import 'builtin.dart' show pageField;

// Loại trang "Thảo luận" (máy chủ: relay/meet-pt-discuss.mjs, dữ liệu là bài riêng tư của Bảng tin; Sếp, 21/11/2026).
// Điện thoại: màn hình Thảo luận của Bảng tin (thẻ bài, cảm xúc 👍 / 👎, trả lời 2 tầng, cập nhật tức thì).
// Sân khấu / TV: quan điểm đang bàn (người điều hành ghim) + trả lời mới, quan điểm nhiều người đồng tình, tỉ lệ lập trường.

const _sub = Color(0xFF9AA0A6);
const _gold = Color(0xFFF5B544);

void registerDiscussPageType() {
  registerPageType(PageTypeSpec(
    type: 'discuss',
    label: tr('Thảo luận'),
    desc: tr('Mọi người nêu quan điểm, trả lời nhau, 👍 / 👎; có thể ẩn danh'),
    icon: Icons.forum_outlined,
    color: const Color(0xFF1A73E8),
    create: (context, call) => showModalBottomSheet<PageDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const DiscussComposer(),
    ),
    view: (context, ctx) => DiscussView(ctx),
    stageThemed: true,
  ));
}

/// Tạo trang Thảo luận: câu hỏi để mọi người nêu quan điểm, bật / tắt lập trường.
class DiscussComposer extends StatefulWidget {
  const DiscussComposer({super.key});
  @override
  State<DiscussComposer> createState() => _DiscussComposerState();
}

class _DiscussComposerState extends State<DiscussComposer> {
  final _q = TextEditingController();
  bool _stance = true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Thảo luận mới'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tr('Chỉ người trong cuộc họp thấy. Quan điểm, trả lời và 👍 / 👎 hiện ngay trên mọi máy và trên TV.'), style: const TextStyle(color: _sub, fontSize: 12.5)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('discuss-q'),
              controller: _q,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: pageField(tr('Câu hỏi, vd: Có nên chia 2 đội tăng ca?')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Chọn lập trường'), style: const TextStyle(color: Colors.white)),
              subtitle: Text(tr('Đồng ý / Phản đối / Ý kiến khác, có thanh tỉ lệ'), style: const TextStyle(color: _sub)),
              value: _stance,
              onChanged: (v) => setState(() => _stance = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('discuss-create'),
              onPressed: () {
                final q = _q.text.trim();
                Navigator.pop(context, PageDraft(title: q.isEmpty ? tr('Thảo luận') : q, init: {'question': q, 'stance': _stance}));
              },
              child: Text(tr('Tạo thảo luận')),
            ),
          ]),
        ),
      );
}

class DiscussView extends StatelessWidget {
  final PageCtx ctx;
  const DiscussView(this.ctx, {super.key});

  Map<String, dynamic> get v => ctx.view;

  @override
  Widget build(BuildContext context) {
    if (ctx.onStage) return DiscussStage(v);
    final id = v['disc_id'];
    if (id == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('Chưa nối được Bảng tin. Thử lại sau.'), textAlign: TextAlign.center, style: const TextStyle(color: _sub)),
        ),
      );
    }
    return DiscussionLoader(discussionId: '$id');
  }
}

/// Sân khấu / TV (giống mockup đã duyệt): bên trái quan điểm đang bàn + 2 trả lời mới, bên phải quan điểm nhiều 👍, dưới cùng tỉ lệ
/// lập trường. Ngoài khung sân khấu (thử, ảnh thu nhỏ): dựng ở 1168×560 rồi co cho vừa.
class DiscussStage extends StatelessWidget {
  final Map<String, dynamic> v;
  final StageMetrics? fm;
  const DiscussStage(this.v, {super.key, this.fm});

  @override
  Widget build(BuildContext context) {
    final m = fm ?? StageMetrics.of(context);
    if (m == null) {
      return FittedBox(
        child: SizedBox(width: 1168, height: 560, child: DiscussStage(v, fm: const StageMetrics(theme: StageTheme(), portrait: false, size: Size(1168, 560), child: SizedBox()))),
      );
    }
    final t = m.theme;
    final sc = Map<String, dynamic>.from(v['stance_counts'] as Map? ?? const {});
    final counts = Map<String, dynamic>.from(v['counts'] as Map? ?? const {});
    final top = [for (final x in (v['top'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final pinned = v['pinned'] is Map ? Map<String, dynamic>.from(v['pinned'] as Map) : (top.isNotEmpty ? top.first : null);
    final others = top.where((x) => x['id'] != pinned?['id']).take(3).toList();
    final stance = v['stance'] != false;
    final total = kStances.fold<int>(0, (s, x) => s + ((sc[x.$1] as num?)?.toInt() ?? 0));
    Widget pill(Object? code, double size) {
      final s = kStances.where((x) => x.$1 == code).firstOrNull;
      if (!stance || s == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(left: 10),
        padding: EdgeInsets.symmetric(horizontal: size * .6, vertical: size * .2),
        decoration: BoxDecoration(color: s.$3.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
        child: Text(s.$2.toUpperCase(), style: TextStyle(color: s.$3, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: .5)),
      );
    }

    final bar = Row(children: [
      if (stance) ...[
        for (final s in kStances) ...[
          Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('${sc[s.$1] ?? 0} ${s.$2}', style: TextStyle(color: t.sub, fontSize: 15)),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: total == 0
                  ? ColoredBox(color: t.surface2)
                  : Row(children: [
                      for (final s in kStances)
                        if (((sc[s.$1] as num?)?.toInt() ?? 0) > 0) Expanded(flex: (sc[s.$1] as num).toInt(), child: Container(color: s.$3)),
                    ]),
            ),
          ),
        ),
        const SizedBox(width: 16),
      ] else
        const Spacer(),
      Text(tr('{0} quan điểm · {1} trả lời', ['${counts['posts'] ?? 0}', '${counts['replies'] ?? 0}']), style: TextStyle(color: t.sub, fontSize: 15)),
    ]);

    if (pinned == null) {
      return Column(children: [
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if ('${v['question'] ?? ''}'.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('${v['question']}', textAlign: TextAlign.center, style: TextStyle(color: t.text, fontSize: 30, fontWeight: FontWeight.w700))),
              Text(tr('Nêu quan điểm của bạn trên app Flygo'), style: TextStyle(color: t.sub, fontSize: 20)),
              const SizedBox(height: 6),
              Text(tr('Chọn Đồng ý / Phản đối / Ý kiến khác, có thể ẩn danh'), style: TextStyle(color: t.sub, fontSize: 16)),
            ]),
          ),
        ),
        bar,
      ]);
    }
    final ini = '${pinned['author'] ?? '?'}'.trim().characters.firstOrNull?.toUpperCase() ?? '?';
    final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(v['pinned'] is Map ? tr('ĐANG BÀN') : tr('NỔI BẬT'), style: const TextStyle(color: _gold, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
      const SizedBox(height: 10),
      Flexible(
        child: Container(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
          decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: _gold.withValues(alpha: .7), width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              CircleAvatar(radius: 16, backgroundColor: t.series[ini.codeUnitAt(0) % t.series.length], child: Text(ini, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Flexible(child: Text('${pinned['author'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w700))),
              pill(pinned['stance'], 12),
            ]),
            const SizedBox(height: 14),
            Flexible(child: Text('${pinned['text'] ?? ''}', maxLines: 5, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 30, height: 1.3, fontWeight: FontWeight.w600))),
            const SizedBox(height: 14),
            Row(children: [
              Text('👍 ${pinned['likes'] ?? 0}', style: TextStyle(color: t.sub, fontSize: 17)),
              if (((pinned['dislikes'] as num?) ?? 0) > 0) ...[const SizedBox(width: 18), Text('👎 ${pinned['dislikes']}', style: TextStyle(color: t.sub, fontSize: 17))],
              const SizedBox(width: 18),
              Text(tr('{0} trả lời', ['${pinned['comments'] ?? 0}']), style: TextStyle(color: t.sub, fontSize: 17)),
            ]),
            for (final r in (pinned['replies'] as List? ?? const []).take(2))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: t.line, width: 3))),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${(r as Map)['author']}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: '${r['text']}'),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.text, fontSize: 17, height: 1.35),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ]);
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('NHIỀU NGƯỜI ĐỒNG TÌNH'), style: TextStyle(color: t.sub, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
      const SizedBox(height: 10),
      for (final x in others)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 46,
              child: Column(children: [
                Text('${x['likes'] ?? 0}', style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w800)),
                Text('👍', style: TextStyle(color: t.sub, fontSize: 11)),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${x['text'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 16, height: 1.35)),
                const SizedBox(height: 4),
                Text(
                  [
                    '${x['author'] ?? ''}',
                    if (stance && kStances.any((s) => s.$1 == x['stance'])) kStances.firstWhere((s) => s.$1 == x['stance']).$2.toLowerCase(),
                    if (((x['comments'] as num?) ?? 0) > 0) tr('{0} trả lời', ['${x['comments']}']),
                  ].join(' · '),
                  style: TextStyle(color: t.sub, fontSize: 13),
                ),
              ]),
            ),
          ]),
        ),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if ('${v['question'] ?? ''}'.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('${v['question']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.sub, fontSize: 18))),
      Expanded(
        child: m.portrait || others.isEmpty
            ? main
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: main),
                const SizedBox(width: 28),
                Expanded(flex: 2, child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: side)),
              ]),
      ),
      const SizedBox(height: 14),
      bar,
    ]);
  }
}
