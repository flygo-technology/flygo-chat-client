import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
import '../page_types.dart';

// Bốc thăm theo mockup "mỗi trang là một app" (21/11/2026).
// - DrawPanel (người xem): thẻ lật cùng lúc trên mọi máy (kết quả mới), người trúng thấy "Bạn được chọn", danh sách đã trúng,
//   tự rút khỏi / tham gia lại (bốc từ người trong phòng).
// - DrawControls (chủ trang): nguồn tên (người trong phòng / gõ danh sách), chạm tên để bỏ / thêm lại, bỏ người đã trúng, mỗi lần
//   bốc mấy người, chia nhóm, nút Bốc thăm lớn, bốc lại, ghi Biên bản, xoá kết quả (bấm hai lần).

const _purple = Color(0xFF9B6BFF), _purpleDeep = Color(0xFF5B2A86), _gold = Color(0xFFF5B544);
const _teamColors = [Color(0xFF3D7BFF), Color(0xFFF29A3D), Color(0xFF22B8A6), Color(0xFF9B6BFF), Color(0xFFF5B544), Color(0xFFE0609A)];

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) meetToast(context, '$e');
  }
}

List<Map<String, dynamic>> _results(Map<String, dynamic> v) => [for (final r in (v['results'] as List? ?? const [])) (r as Map).cast<String, dynamic>()];

/// Thẻ người trúng: lật (xoay quanh trục dọc) mỗi khi có kết quả mới [id].
class DrawCard extends StatefulWidget {
  final String id;
  final String name;
  final double width;
  final bool glow;
  const DrawCard({super.key, required this.id, required this.name, this.width = 150, this.glow = true});
  @override
  State<DrawCard> createState() => _DrawCardState();
}

class _DrawCardState extends State<DrawCard> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), value: 1);

  @override
  void didUpdateWidget(DrawCard old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id && widget.id.isNotEmpty) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width, h = w * 4 / 3;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final a = Curves.easeInOutBack.transform(_c.value) * math.pi;
        // Thẻ chưa có tên (thẻ phụ hai bên, chưa bốc): luôn úp.
        final front = a > math.pi / 2 && widget.name.isNotEmpty;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0012)
            ..rotateY(front ? a - math.pi : a),
          child: Container(
            width: w,
            height: h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * .1),
              gradient: front ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_purple, _purpleDeep]) : null,
              color: front ? null : (AppScope.of(context).theme.light ? const Color(0xFFD5DBE4) : const Color(0xFF2A2F38)),
              boxShadow: front && widget.glow ? [BoxShadow(color: _purple.withValues(alpha: .5), blurRadius: w * .28)] : null,
            ),
            child: front && widget.name.isNotEmpty
                ? Padding(
                    padding: EdgeInsets.all(w * .08),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(
                        radius: w * .2,
                        backgroundColor: Colors.white.withValues(alpha: .2),
                        child: Text(widget.name.trim().split(RegExp(r'\s+')).last.characters.first.toUpperCase(),
                            style: TextStyle(color: Colors.white, fontSize: w * .18, fontWeight: FontWeight.w800)),
                      ),
                      SizedBox(height: w * .07),
                      Text(widget.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: w * .13, fontWeight: FontWeight.w800, height: 1.15)),
                    ]),
                  )
                : Text('?', style: TextStyle(color: AppScope.of(context).theme.light ? const Color(0xFF5B6676) : Colors.white54, fontSize: w * .3, fontWeight: FontWeight.w800)),
          ),
        );
      },
    );
  }
}

class DrawPanel extends StatelessWidget {
  final PageCtx ctx;
  const DrawPanel(this.ctx, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), t = s.theme;
    final v = ctx.view;
    final last = (v['last'] as Map?)?.cast<String, dynamic>();
    final picks = [for (final x in (last?['picks'] as List? ?? const [])) '$x'];
    final teams = [for (final g in (last?['teams'] as List? ?? const [])) [for (final x in g as List) '$x']];
    final round = (v['round'] as num?)?.toInt() ?? _results(v).length;
    final remaining = (v['remaining'] as num?)?.toInt() ?? 0;
    final participants = v['source'] == 'participants';
    final winners = [for (final r in _results(v)) for (final x in (r['picks'] as List? ?? const [])) '$x'];
    final cardW = s.compact ? 110.0 : 150.0;
    final stage = Container(
      padding: EdgeInsets.symmetric(vertical: s.compact ? 12 : 20, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: RadialGradient(center: const Alignment(0, -.2), radius: .9, colors: [t.light ? const Color(0xFFEDE5FF) : const Color(0xFF2C2140), t.surface]),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AppChip(last == null ? tr('CHƯA BỐC') : tr('LẦN {0} · KẾT QUẢ', [round]), color: _purple),
        SizedBox(height: s.compact ? 10 : 16),
        if (teams.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final (i, g) in teams.indexed)
              Container(
                width: s.compact ? 140 : 160,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: _teamColors[i % 6], width: 1.5)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('NHÓM {0}', [i + 1]), style: TextStyle(color: _teamColors[i % 6], fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(g.join(' · '), style: TextStyle(color: t.text, fontSize: 13.5)),
                ]),
              ),
          ])
        else
          FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.rotate(angle: -.14, child: Opacity(opacity: .55, child: DrawCard(id: '', name: '', width: cardW * .43, glow: false))),
            const SizedBox(width: 10),
            DrawCard(id: '${last?['id'] ?? ''}', name: picks.isEmpty ? '' : picks.first, width: cardW),
            const SizedBox(width: 10),
            Transform.rotate(angle: .14, child: Opacity(opacity: .55, child: DrawCard(id: '', name: '', width: cardW * .43, glow: false))),
          ])),
        if (picks.length > 1) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [for (final p in picks.skip(1)) AppChip(p, color: _purple)]),
        ],
        SizedBox(height: s.compact ? 8 : 14),
        Text(
          v['me_won'] == true
              ? tr('Bạn được chọn')
              : v['me_out'] == true
                  ? tr('Bạn đã rút khỏi bốc thăm')
                  : tr('Bạn chưa trúng · còn {0} người', [remaining]),
          style: TextStyle(color: v['me_won'] == true ? _gold : t.sub, fontWeight: v['me_won'] == true ? FontWeight.w800 : FontWeight.w500),
        ),
      ]),
    );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        stage,
        if (winners.isNotEmpty && !s.compact) ...[
          const SizedBox(height: 12),
          AppSectionLabel(tr('Đã trúng')),
          for (final (i, w) in winners.indexed.toList().reversed.take(5))
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(12), border: i == winners.length - 1 ? Border.all(color: _purple, width: 1.5) : null),
              child: Row(children: [
                SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(color: _gold, fontWeight: FontWeight.w800))),
                Expanded(child: Text(w, style: TextStyle(color: t.text))),
              ]),
            ),
        ],
        if (participants && ctx.data.role != 'viewer') ...[
          const SizedBox(height: 10),
          AppButton(
            v['me_out'] == true ? tr('Tham gia lại bốc thăm') : tr('Rút khỏi bốc thăm'),
            key: const ValueKey('draw-optout'),
            onPressed: () => _run(context, () => ctx.act(v['me_out'] == true ? 'optin' : 'optout')),
          ),
        ],
      ]),
    );
  }
}

class DrawControls extends StatefulWidget {
  final PageCtx ctx;
  const DrawControls(this.ctx, {super.key});
  @override
  State<DrawControls> createState() => _DrawControlsState();
}

class _DrawControlsState extends State<DrawControls> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _act(String a, [Map<String, dynamic> b = const {}]) => _run(context, () => widget.ctx.act(a, b));

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final v = widget.ctx.view;
    final names = [for (final n in (v['names'] as List? ?? const [])) (n as Map).cast<String, dynamic>()];
    final participants = v['source'] == 'participants';
    final groups = v['mode'] == 'groups';
    final options = [for (final x in (v['options'] as List? ?? const [])) '$x'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('{0} tên · còn {1}', [v['total'] ?? names.length, v['remaining'] ?? 0])),
      AppSegmented<String>(
        items: [('participants', tr('Người trong phòng')), ('list', tr('Gõ danh sách'))],
        value: participants ? 'participants' : 'list',
        onChanged: widget.ctx.page.meeting == null ? null : (x) => _act('config', {'source': x}),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final n in names)
          InkWell(
            key: ValueKey('draw-name-${n['name']}'),
            borderRadius: BorderRadius.circular(99),
            onTap: () => _act('toggle', {'name': n['name']}),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(99)),
              child: Text(
                '${n['name']}',
                style: TextStyle(
                  color: n['off'] == true || (n['won'] == true && v['exclude_winners'] != false && !groups) ? t.sub.withValues(alpha: .6) : t.text,
                  decoration: n['off'] == true || (n['won'] == true && v['exclude_winners'] != false && !groups) ? TextDecoration.lineThrough : null,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
      ]),
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(tr('Chạm tên để bỏ / thêm lại'), style: TextStyle(color: t.sub, fontSize: 12))),
      if (!participants)
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('draw-add'),
              controller: _add,
              style: TextStyle(color: t.text),
              decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: tr('+ Thêm tên (mỗi dòng một tên)'), hintStyle: TextStyle(color: t.accent)),
              onSubmitted: (x) async {
                final add = [for (final l in x.split('\n')) if (l.trim().isNotEmpty) l.trim()];
                if (add.isEmpty) return;
                await _act('config', {'options': [...options, ...add]});
                _add.clear();
              },
            ),
          ),
        ]),
      const SizedBox(height: 6),
      AppToggleRow(tr('Bỏ người đã trúng ra khỏi lần sau'), value: v['exclude_winners'] != false, onChanged: groups ? null : (x) => _act('config', {'exclude_winners': x})),
      AppToggleRow(tr('Chia nhóm'), value: groups, onChanged: (x) => _act('config', {'mode': x ? 'groups' : 'pick'})),
      Row(children: [
        Expanded(child: Text(groups ? tr('Số nhóm') : tr('Mỗi lần bốc'), style: TextStyle(color: t.text))),
        AppNumberStepper(
          value: groups ? (v['groups'] as num?)?.toInt() ?? 2 : (v['count'] as num?)?.toInt() ?? 1,
          min: groups ? 2 : 1,
          max: groups ? 20 : 20,
          format: (x) => groups ? tr('{0} nhóm', [x]) : tr('{0} người', [x]),
          onChanged: (x) => _act('config', {groups ? 'groups' : 'count': x}),
        ),
      ]),
      const SizedBox(height: 12),
      AppButton(_results(v).isEmpty ? tr('Bốc thăm') : tr('Bốc lần {0}', [_results(v).length + 1]), key: const ValueKey('draw-go'), kind: AppButtonKind.primary, height: 56, icon: Icons.casino_outlined, onPressed: () => _act('draw')),
      const SizedBox(height: 8),
      Row(children: [
        if (widget.ctx.page.meeting != null) ...[
          Expanded(child: AppButton(tr('Ghi vào Biên bản'), onPressed: _results(v).isEmpty ? null : () async {
            await _act('to_minutes');
            if (context.mounted) meetToast(context, tr('Đã ghi vào Biên bản'));
          })),
          const SizedBox(width: 8),
        ],
        Expanded(child: AppButton(tr('Xoá kết quả'), kind: AppButtonKind.danger, confirm: true, onPressed: _results(v).isEmpty ? null : () => _act('clear'))),
      ]),
    ]);
  }
}
