import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/i18n.dart';
import '../../../state/app_state.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
import '../page_types.dart';
import '../stage_frame.dart';

// Biên bản thành app (mockup "mỗi trang là một app", bảng 15). Văn bản biên bản vẫn là một chuỗi (các loại trang khác ghi
// thêm vào cuối qua appendMinutes); app đọc theo quy ước:
//   "## 2 · Tiến độ" / "2 · Tiến độ"       -> đề mục
//   "09:14 · Lợi báo còn 2 tầng"            -> dòng có giờ
//   "09:18 · QUYẾT ĐỊNH: Bàn giao 28/11"    -> quyết định
// Việc cần làm ở danh sách riêng (tasks). Người xem đề xuất sửa một dòng; người ghi nhận / bỏ qua.

/// Một dòng của biên bản.
class MinLine {
  final String raw;
  final String time;
  final String text;
  final bool decision;
  const MinLine(this.raw, this.time, this.text, this.decision);
}

/// Một mục của biên bản (đề mục rỗng = phần trước đề mục đầu tiên).
class MinSection {
  final String title;
  final List<MinLine> lines;
  MinSection(this.title, this.lines);
}

final _heading = RegExp(r'^(#{1,3}\s+|\d+\s*[·.)]\s+)');
final _time = RegExp(r'^(\d{1,2}:\d{2})\s*(?:[·\-–]\s*)?');
final _decision = RegExp(r'^\**\s*(QUYẾT ĐỊNH|Quyết định|quyết định|QĐ)\s*\**\s*:\s*\**\s*');

/// Đọc văn bản biên bản thành các mục.
List<MinSection> parseMinutes(String text) {
  final out = <MinSection>[MinSection('', [])];
  for (final l in text.split('\n')) {
    final s = l.trim();
    if (s.isEmpty) continue;
    if (_heading.hasMatch(s) && !_time.hasMatch(s)) {
      out.add(MinSection(s.replaceFirst(RegExp(r'^#{1,3}\s+'), '').replaceAll('*', '').trim(), []));
      continue;
    }
    var body = s.replaceFirst(RegExp(r'^[-*•]\s+'), '');
    final tm = _time.firstMatch(body);
    final time = tm?.group(1) ?? '';
    if (tm != null) body = body.substring(tm.end);
    final dm = _decision.firstMatch(body);
    if (dm != null) body = body.substring(dm.end).replaceAll('**', '');
    out.last.lines.add(MinLine(l, time, body.trim(), dm != null));
  }
  if (out.first.lines.isEmpty && out.length > 1) out.removeAt(0);
  return out;
}

String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

List<Map<String, dynamic>> _tasks(PageCtx ctx) => [for (final x in (ctx.view['tasks'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
List<Map<String, dynamic>> _sugs(PageCtx ctx) => [for (final x in (ctx.view['suggestions'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];

/// Đang ghi: có người sửa trong 2 phút qua.
bool minutesLive(PageCtx ctx) {
  final at = (ctx.view['edited_at'] as num?)?.toInt() ?? 0;
  return at > 0 && DateTime.now().millisecondsSinceEpoch - at < 120000 && ctx.view['closed'] != true;
}

/// Việc này của mình: giao đúng mình (đã nhận), hoặc tên giao khớp tên mình ("@kim" với "Mai Kim").
bool minutesTaskMine(PageCtx ctx, Map t) {
  if (_isMe(ctx, t['who_id'])) return true;
  String norm(Object? x) => '${x ?? ''}'.replaceFirst('@', '').trim().toLowerCase();
  final me = norm(ctx.call.myName()), as = norm(t['who']);
  return as.isNotEmpty && me.isNotEmpty && (as == me || me.endsWith(' $as'));
}

/// [id] là mình (id rỗng không tính).
bool _isMe(PageCtx ctx, Object? id) {
  final me = ctx.call.myId();
  return me.isNotEmpty && '${id ?? ''}' == me;
}

/// Ngày hạn dạng dd/mm sau [days] ngày.
String _dueIn(int days) {
  final d = DateTime.now().add(Duration(days: days));
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Nhãn QUYẾT ĐỊNH / VIỆC.
class MinTag extends StatelessWidget {
  final bool decision;
  final double size;
  const MinTag({super.key, required this.decision, this.size = 10.5});
  @override
  Widget build(BuildContext context) {
    final t = StageMetrics.themeOf(context);
    final c = decision ? const Color(0xFF38C793) : t.accent;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: EdgeInsets.symmetric(horizontal: size * .6, vertical: size * .15),
      decoration: BoxDecoration(color: c.withValues(alpha: t.light ? .14 : .22), borderRadius: BorderRadius.circular(6)),
      child: Text(decision ? tr('QUYẾT ĐỊNH') : tr('VIỆC'),
          style: TextStyle(color: Color.lerp(c, t.light ? Colors.black : Colors.white, t.light ? .35 : .45), fontSize: size, fontWeight: FontWeight.w800, letterSpacing: .4)),
    );
  }
}

// ------------------------------------------------------------------ Sân khấu

/// Biên bản trên sân khấu / TV: mục đang ghi (giờ, nhãn, con trỏ ở dòng cuối khi đang ghi) và cột "Đã chốt hôm nay".
class MinutesAppStage extends StatelessWidget {
  final PageCtx ctx;
  const MinutesAppStage(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final m = StageMetrics.of(context);
    if (m == null) {
      return FittedBox(child: SizedBox(width: 1168, height: 560, child: StageMetrics(theme: const StageTheme(), portrait: false, size: const Size(1168, 560), child: MinutesAppStage(ctx))));
    }
    final t = m.theme, portrait = m.portrait;
    final secs = parseMinutes('${ctx.view['text'] ?? ''}');
    final cur = secs.isEmpty ? null : secs.last;
    final live = minutesLive(ctx);
    final decisions = [for (final s in secs) ...s.lines.where((l) => l.decision)];
    final tasks = _tasks(ctx);
    final lines = cur == null ? const <MinLine>[] : (cur.lines.length > (portrait ? 6 : 7) ? cur.lines.sublist(cur.lines.length - (portrait ? 6 : 7)) : cur.lines);
    final fs = portrait ? 17.0 : 20.0;
    final left = cur == null || (cur.lines.isEmpty && cur.title.isEmpty)
        ? Text(tr('Biên bản đang trống. Người ghi gõ trên app, mọi người đọc cùng.'), style: TextStyle(color: t.sub, fontSize: fs))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (cur.title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(cur.title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.accent, fontSize: portrait ? 13 : 14, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
              ),
            for (final (i, l) in lines.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: portrait ? 52 : 64,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(l.time, style: TextStyle(color: t.sub, fontSize: fs * .72, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        if (l.decision) WidgetSpan(alignment: PlaceholderAlignment.middle, child: MinTag(decision: true, size: fs * .58)),
                        TextSpan(text: l.text),
                        // Con trỏ ở dòng đang ghi.
                        if (live && i == lines.length - 1)
                          WidgetSpan(alignment: PlaceholderAlignment.middle, child: Container(width: 2.5, height: fs * 1.1, margin: const EdgeInsets.only(left: 3), color: t.accent)),
                      ]),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.text, fontSize: l.decision ? fs * 1.05 : fs, height: 1.4, fontWeight: l.decision ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ),
                ]),
              ),
          ]);
    final items = <Widget>[
      for (final d in decisions.reversed.take(4)) _chot(t, true, d.text, portrait),
      for (final x in tasks.where((x) => x['done'] != true).take(4))
        _chot(t, false, [if ('${x['who'] ?? ''}'.isNotEmpty) '${x['who']}'.replaceFirst('@', ''), '${x['text'] ?? ''}', if ('${x['due'] ?? ''}'.isNotEmpty) '${x['due']}'].join(' · '), portrait),
    ];
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('ĐÃ CHỐT HÔM NAY'), style: TextStyle(color: t.sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
      const SizedBox(height: 10),
      if (items.isEmpty) Text(tr('Chưa có quyết định hay việc nào'), style: TextStyle(color: t.sub, fontSize: 15)),
      ...items.take(portrait ? 3 : 6),
    ]);
    if (portrait) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: ClipRect(child: left)), const SizedBox(height: 12), side]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 3, child: ClipRect(child: left)),
      const SizedBox(width: 28),
      Expanded(flex: 2, child: ClipRect(child: side)),
    ]);
  }

  Widget _chot(StageTheme t, bool decision, String text, bool portrait) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(12)),
        child: Text.rich(
          TextSpan(children: [
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: MinTag(decision: decision, size: 11)),
            TextSpan(text: text),
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: t.text, fontSize: portrait ? 14 : 16, height: 1.35),
        ),
      );
}

/// Thanh cuối của khung sân khấu: ai đang ghi, đã chốt, số quyết định / việc.
List<Widget> minutesFooter(BuildContext context, PageCtx ctx) {
  final t = StageMetrics.themeOf(context);
  final by = '${ctx.view['edited_by'] ?? ''}';
  final dec = parseMinutes('${ctx.view['text'] ?? ''}').fold<int>(0, (a, s) => a + s.lines.where((l) => l.decision).length);
  return [
    if (by.isNotEmpty) StagePill(minutesLive(ctx) ? tr('{0} đang ghi', [by]) : tr('{0} vừa ghi', [by]), icon: Icons.edit_outlined, theme: t, accent: minutesLive(ctx)),
    if (ctx.view['closed'] == true) StagePill(tr('Đã chốt'), icon: Icons.lock_outline_rounded, theme: t),
    const Spacer(),
    StagePill(tr('{0} quyết định · {1} việc', [dec, _tasks(ctx).length]), icon: Icons.checklist_rounded, theme: t),
  ];
}

// ------------------------------------------------------------------ Người xem

/// Phần người xem: đọc cùng, việc của mình (Nhận việc / Đổi hạn ngay tại dòng), đề xuất sửa một dòng.
class MinutesPanel extends StatefulWidget {
  final PageCtx ctx;
  const MinutesPanel(this.ctx, {super.key});
  @override
  State<MinutesPanel> createState() => _MinutesPanelState();
}

class _MinutesPanelState extends State<MinutesPanel> {
  bool _mineOnly = false;
  String? _due; // id việc đang đổi hạn
  String? _suggest; // dòng đang đề xuất sửa (raw)
  final _c = TextEditingController();

  PageCtx get ctx => widget.ctx;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _act(String a, [Map<String, dynamic> b = const {}]) async {
    await ctx.act(a, b);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.theme;
    final closed = ctx.view['closed'] == true;
    final writer = ctx.view['writer'] == true || ctx.data.manage;
    final canSuggest = !writer && !closed && ctx.data.role != 'viewer';
    final mine = [for (final x in _tasks(ctx)) if (minutesTaskMine(ctx, x)) x];
    final sugs = _sugs(ctx);
    final secs = parseMinutes('${ctx.view['text'] ?? ''}');
    // Đọc cùng: dòng cuối các mục (gọn hơn ở điện thoại ngang).
    final limit = s.compact ? 5 : 10;
    final rows = <(String?, MinLine?)>[];
    for (final sec in secs.reversed) {
      for (final l in sec.lines.reversed) {
        if (rows.length >= limit) break;
        rows.insert(0, (null, l));
      }
      if (rows.length >= limit) break;
      if (sec.title.isNotEmpty) rows.insert(0, (sec.title, null));
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(closed ? tr('Biên bản đã chốt') : (minutesLive(ctx) ? tr('{0} đang ghi', [ctx.view['edited_by']]) : tr('Đọc cùng người ghi')),
                style: TextStyle(color: t.sub, fontSize: 12.5)),
          ),
          if (mine.isNotEmpty)
            AppChip(tr('Việc của tôi · {0}', [mine.length]), key: const ValueKey('min-mine'), selected: _mineOnly, icon: Icons.task_alt_rounded, onTap: () => setState(() => _mineOnly = !_mineOnly)),
        ]),
        const SizedBox(height: 10),
        for (final x in mine) _myTask(t, x),
        if (!_mineOnly) ...[
          if (rows.isEmpty) Text(tr('Biên bản đang trống.'), style: TextStyle(color: t.sub, fontSize: 14)),
          for (final (title, l) in rows)
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Text(title.toUpperCase(), style: TextStyle(color: t.light ? t.accent : const Color(0xFF9DBBFF), fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              )
            else
              _line(t, l!, canSuggest),
          for (final x in sugs.where((x) => _isMe(ctx, x['by_id'])))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.schedule_send_rounded, size: 16, color: t.sub),
                const SizedBox(width: 6),
                Expanded(child: Text(tr('Đã gửi đề xuất: {0}', [x['text']]), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.sub, fontSize: 12.5))),
                TextButton(onPressed: () => _act('suggest_reject', {'id': x['id']}), child: Text(tr('Rút lại'))),
              ]),
            ),
          if (canSuggest && _suggest == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppButton(tr('Đề xuất thêm dòng'), icon: Icons.add_comment_outlined, onPressed: () async => setState(() {
                _suggest = '';
                _c.text = '';
              })),
            ),
          if (_suggest == '') _suggestBox(t, ''),
        ],
      ]),
    );
  }

  /// Một dòng đọc cùng; người xem chạm để đề xuất sửa (ô sửa mở ngay dưới dòng).
  Widget _line(StageTheme t, MinLine l, bool canSuggest) {
    final open = _suggest == l.raw;
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 46, child: Text(l.time, style: TextStyle(color: t.sub, fontSize: 12, fontWeight: FontWeight.w600))),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              if (l.decision) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: MinTag(decision: true)),
              TextSpan(text: l.text),
            ]),
            style: TextStyle(color: t.text, fontSize: 14, height: 1.45),
          ),
        ),
        if (canSuggest && !open) Icon(Icons.edit_note_rounded, size: 18, color: t.sub),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      canSuggest
          ? InkWell(
              onTap: () => setState(() {
                _suggest = open ? null : l.raw;
                _c.text = l.raw.trim();
              }),
              child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: body),
            )
          : body,
      if (open) _suggestBox(t, l.raw),
    ]);
  }

  Widget _suggestBox(StageTheme t, String orig) => Container(
        margin: const EdgeInsets.only(top: 4, bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: t.light ? const Color(0xFFF1F4F9) : const Color(0xFF1F232B), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(orig.isEmpty ? tr('Dòng muốn thêm') : tr('Sửa thành (người ghi duyệt rồi mới vào biên bản)'), style: TextStyle(color: t.sub, fontSize: 12)),
          TextField(
            key: const ValueKey('min-suggest-text'),
            controller: _c,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            style: TextStyle(color: t.text, fontSize: 14),
            cursorColor: t.accent,
            decoration: const InputDecoration(isDense: true, border: InputBorder.none),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: AppButton(tr('Huỷ'), onPressed: () async => setState(() => _suggest = null))),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: AppButton(tr('Gửi đề xuất'), kind: AppButtonKind.primary, onPressed: () async {
                final text = _c.text.trim();
                if (text.isEmpty || text == orig.trim()) return;
                await _act('suggest', {'orig': orig.trim(), 'text': text});
                if (mounted) setState(() => _suggest = null);
              }),
            ),
          ]),
        ]),
      );

  /// Việc giao cho mình: nổi bật, Nhận việc / Đổi hạn ngay tại dòng.
  Widget _myTask(StageTheme t, Map<String, dynamic> x) {
    final claimed = x['claimed'] == true || _isMe(ctx, x['who_id']);
    final done = x['done'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        color: t.accent.withValues(alpha: t.light ? .08 : .12),
        outline: t.accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(
            TextSpan(children: [
              const WidgetSpan(alignment: PlaceholderAlignment.middle, child: MinTag(decision: false)),
              TextSpan(text: '${x['text'] ?? ''}'),
              if ('${x['due'] ?? ''}'.isNotEmpty) TextSpan(text: ' · ${tr('hạn {0}', [x['due']])}', style: TextStyle(color: t.sub)),
            ]),
            style: TextStyle(color: t.text, fontSize: 14.5, height: 1.4, decoration: done ? TextDecoration.lineThrough : null),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: claimed
                  ? AppButton(done ? tr('Đã xong') : tr('Đánh dấu xong'), kind: AppButtonKind.success, height: 40, onPressed: () => _act('task', {'id': x['id'], 'done': !done}))
                  : AppButton(tr('Nhận việc'), key: ValueKey('min-claim-${x['id']}'), kind: AppButtonKind.primary, height: 40, onPressed: () => _act('claim', {'id': x['id']})),
            ),
            const SizedBox(width: 8),
            Expanded(child: AppButton(tr('Đổi hạn'), height: 40, onPressed: () async => setState(() => _due = _due == x['id'] ? null : '${x['id']}'))),
          ]),
          if (_due == x['id']) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (label, d) in [(tr('Hôm nay'), 0), (tr('Ngày mai'), 1), (tr('+3 ngày'), 3), (tr('+1 tuần'), 7)])
                AppChip(label, onTap: () async {
                  await _act('task', {'id': x['id'], 'due': _dueIn(d)});
                  if (mounted) setState(() => _due = null);
                }),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Người ghi

/// Điều khiển của người ghi: gõ thẳng vào biên bản, nút gắn nhãn, việc + người, hộp đề xuất sửa, chốt và gửi.
class MinutesControls extends StatefulWidget {
  final PageCtx ctx;
  const MinutesControls(this.ctx, {super.key});
  @override
  State<MinutesControls> createState() => _MinutesControlsState();
}

class _MinutesControlsState extends State<MinutesControls> {
  late final _c = TextEditingController(text: '${widget.ctx.view['text'] ?? ''}');
  final _focus = FocusNode();
  final _task = TextEditingController();
  Timer? _t;
  bool _taskOpen = false;
  String _who = '', _taskDue = '';

  PageCtx get ctx => widget.ctx;

  @override
  void didUpdateWidget(MinutesControls old) {
    super.didUpdateWidget(old);
    // Người khác vừa ghi (đề xuất được nhận, loại trang khác ghi thêm): cập nhật khi mình không đang gõ.
    final v = '${ctx.view['text'] ?? ''}';
    if (!_focus.hasFocus && !(_t?.isActive ?? false) && v != _c.text) _c.text = v;
  }

  @override
  void dispose() {
    if (_t?.isActive ?? false) ctx.act('text', {'text': _c.text});
    _t?.cancel();
    _c.dispose();
    _focus.dispose();
    _task.dispose();
    super.dispose();
  }

  void _send() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 900), () => ctx.act('text', {'text': _c.text}));
  }

  /// Thêm một dòng mới ở cuối (có giờ / nhãn), đưa con trỏ tới cuối để gõ tiếp.
  void _append(String prefix) {
    final cur = _c.text.replaceFirst(RegExp(r'\s+$'), '');
    _c.text = '$cur${cur.isEmpty ? '' : '\n'}$prefix';
    _c.selection = TextSelection.collapsed(offset: _c.text.length);
    _focus.requestFocus();
    _send();
  }

  Map<String, String> _people(BuildContext context) {
    AppState? app;
    try {
      app = context.read<AppState>();
    } catch (_) {}
    return {
      if (app?.me != null) app!.me!.id: app.me!.displayName,
      for (final p in ctx.call.participants)
        if (p.userId.isNotEmpty && !p.userId.contains(':')) p.userId: app?.users[p.userId]?.displayName ?? p.userId,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.theme;
    final closed = ctx.view['closed'] == true;
    final sugs = _sugs(ctx);
    final tasks = _tasks(ctx);
    final now = _hhmm(DateTime.now());
    final sections = parseMinutes(_c.text).where((x) => x.title.isNotEmpty).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(closed ? tr('Biên bản đã chốt') : tr('Ghi biên bản')),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: t.light ? const Color(0xFFF1F4F9) : const Color(0xFF1F232B), borderRadius: BorderRadius.circular(12)),
        child: TextField(
          key: const ValueKey('min-text'),
          controller: _c,
          focusNode: _focus,
          readOnly: closed,
          maxLines: s.compact ? 6 : 12,
          minLines: s.compact ? 3 : 6,
          style: TextStyle(color: t.text, fontSize: 14.5, height: 1.5),
          cursorColor: t.accent,
          decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: tr('Gõ thẳng vào biên bản…'), hintStyle: TextStyle(color: t.sub)),
          onChanged: (_) => _send(),
        ),
      ),
      if (!closed) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _tagBtn(tr('Quyết định'), Icons.gavel_rounded, AppButtonKind.success, () => _append('$now · QUYẾT ĐỊNH: ')),
          _tagBtn(tr('Việc + người'), Icons.assignment_ind_outlined, AppButtonKind.primary, () => setState(() => _taskOpen = !_taskOpen)),
          _tagBtn(tr('Mục mới'), Icons.title_rounded, AppButtonKind.tonal, () => _append('\n## ${sections + 1} · ')),
          _tagBtn(tr('Dòng mới'), Icons.schedule_rounded, AppButtonKind.tonal, () => _append('$now · ')),
        ]),
        if (_taskOpen) _taskForm(context, t),
      ],
      if (sugs.isNotEmpty) ...[
        const SizedBox(height: 14),
        AppSectionLabel(tr('Đề xuất sửa · {0}', [sugs.length])),
        for (final x in sugs)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: t.light ? const Color(0xFFF1F4F9) : const Color(0xFF1F232B), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('{0} đề xuất', [x['by']]), style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
              if ('${x['orig'] ?? ''}'.isNotEmpty)
                Text('${x['orig']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.sub, fontSize: 13, decoration: TextDecoration.lineThrough)),
              Text('→ ${x['text']}', style: TextStyle(color: t.text, fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: AppButton(tr('Nhận'), key: ValueKey('min-accept-${x['id']}'), kind: AppButtonKind.primary, height: 40, onPressed: () => ctx.act('suggest_accept', {'id': x['id']}))),
                const SizedBox(width: 8),
                Expanded(child: AppButton(tr('Bỏ qua'), height: 40, onPressed: () => ctx.act('suggest_reject', {'id': x['id']}))),
              ]),
            ]),
          ),
      ],
      if (tasks.isNotEmpty) ...[
        const SizedBox(height: 14),
        AppSectionLabel(tr('Việc cần làm · {0}', [tasks.length])),
        for (final x in tasks)
          Row(children: [
            Checkbox(value: x['done'] == true, activeColor: t.accent, onChanged: (v) => ctx.act('task', {'id': x['id'], 'done': v == true})),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${x['text'] ?? ''}', style: TextStyle(color: t.text, fontSize: 14, decoration: x['done'] == true ? TextDecoration.lineThrough : null)),
                if ('${x['who'] ?? ''}${x['due'] ?? ''}'.isNotEmpty)
                  Text(
                    [
                      if ('${x['who'] ?? ''}'.isNotEmpty) '${x['who']}${x['claimed'] == true ? ' ✓' : ''}',
                      if ('${x['due'] ?? ''}'.isNotEmpty) '${x['due']}',
                    ].join(' · '),
                    style: TextStyle(color: t.sub, fontSize: 12),
                  ),
              ]),
            ),
            if (!closed)
              SizedBox(width: 44, height: 44, child: IconButton(tooltip: tr('Xoá việc'), icon: Icon(Icons.close_rounded, size: 18, color: t.sub), onPressed: () => ctx.act('del_task', {'id': x['id']}))),
          ]),
      ],
      const SizedBox(height: 12),
      if (ctx.data.manage)
        closed
            ? AppButton(tr('Mở lại biên bản'), icon: Icons.lock_open_rounded, onPressed: () => ctx.act('reopen'))
            : AppButton(
                tr('Chốt và gửi mọi người'),
                key: const ValueKey('min-close'),
                icon: Icons.send_rounded,
                kind: AppButtonKind.primary,
                confirm: true,
                confirmLabel: tr('Bấm lần nữa để chốt và gửi vào nhóm'),
                onPressed: () async {
                  if (_t?.isActive ?? false) {
                    _t!.cancel();
                    await ctx.act('text', {'text': _c.text});
                  }
                  await ctx.act('close');
                  try {
                    await ctx.api.export(ctx.page.id);
                    if (mounted) meetToast(this.context, tr('Đã chốt và gửi biên bản vào nhóm cuộc họp'));
                  } catch (e) {
                    if (mounted) meetToast(this.context, '$e');
                  }
                },
              ),
    ]);
  }

  Widget _tagBtn(String label, IconData icon, AppButtonKind kind, VoidCallback on) =>
      AppButton(label, icon: icon, kind: kind, height: 40, expand: false, onPressed: () async => on());

  /// Thêm việc ngay tại chỗ: việc gì, ai (người trong phòng), hạn.
  Widget _taskForm(BuildContext context, StageTheme t) {
    final people = _people(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.light ? const Color(0xFFF1F4F9) : const Color(0xFF1F232B), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: const ValueKey('min-task-text'),
          controller: _task,
          style: TextStyle(color: t.text, fontSize: 14),
          cursorColor: t.accent,
          decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: tr('Việc cần làm…'), hintStyle: TextStyle(color: t.sub)),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in people.values.take(8)) AppChip(n, selected: _who == n, onTap: () => setState(() => _who = _who == n ? '' : n)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (label, d) in [(tr('Hôm nay'), 0), (tr('Ngày mai'), 1), (tr('+3 ngày'), 3), (tr('+1 tuần'), 7)])
            AppChip(label, color: const Color(0xFF8E99A8), selected: _taskDue == _dueIn(d), onTap: () => setState(() => _taskDue = _taskDue == _dueIn(d) ? '' : _dueIn(d))),
        ]),
        const SizedBox(height: 8),
        AppButton(tr('Thêm việc'), kind: AppButtonKind.primary, height: 40, onPressed: () async {
          final text = _task.text.trim();
          if (text.isEmpty) return;
          await ctx.act('add_task', {'text': text, 'who': _who, 'due': _taskDue});
          if (mounted) {
            setState(() {
              _task.clear();
              _who = _taskDue = '';
              _taskOpen = false;
            });
          }
        }),
      ]),
    );
  }
}
