import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../i18n/i18n.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
import '../page_types.dart';
import '../stage_frame.dart';

// Phần app của Chào mừng và Chương trình (mockup "mỗi trang là một app", bảng 01 và 16): phần tương tác của người xem,
// điều khiển / sửa tại chỗ của chủ trang. Phần hiện trên sân khấu ở builtin.dart.

/// Đổi khoá trong content: trang thường lưu vào trang; Chào mừng của hệ thống (id sys:welcome) lưu cấu hình cuộc họp.
Future<void> pageContentSave(BuildContext context, PageCtx ctx, Map<String, dynamic> patch) async {
  try {
    if (ctx.page.id == 'sys:welcome') {
      final e = await ctx.call.stageAct('config', {'welcome': {...ctx.page.content, ...patch}});
      if (e != null) throw e;
    } else {
      await ctx.api.patch(ctx.page.id, {'content': {...ctx.page.content, ...patch}});
    }
    await ctx.reload();
  } catch (e) {
    if (context.mounted) meetToast(context, '$e');
    rethrow;
  }
}

/// Bản nháp đang sửa tại chỗ của một trang (khung sân khấu hiện ngay khi gõ).
final _drafts = <String, ValueNotifier<Map<String, dynamic>?>>{};
ValueNotifier<Map<String, dynamic>?> pageDraftOf(String id) => _drafts.putIfAbsent(id, () => ValueNotifier(null));

// ------------------------------------------------------------------ Chào mừng

/// Người đã vào (không tính khách / thiết bị phòng).
List<String> welcomePeople(PageCtx ctx) => [for (final p in ctx.call.participants) if (p.userId.isNotEmpty && !p.userId.contains(':')) p.userId];

/// Người xem: đếm người đã vào, nút "Vẫy chào mọi người" (tên bay lên trên sân khấu, mọi máy và TV).
class WelcomePanel extends StatelessWidget {
  final PageCtx ctx;
  const WelcomePanel(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final n = welcomePeople(ctx).length;
    final wave = AppButton(tr('Vẫy chào mọi người'), key: const ValueKey('welcome-wave'), icon: Icons.waving_hand_outlined, onPressed: () async => ctx.call.react('👋'));
    if (s.compact) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(tr('{0} người đã vào', [n]), style: TextStyle(color: s.theme.sub, fontSize: 12.5)), const SizedBox(height: 8), wave]);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.groups_2_outlined, color: s.theme.sub, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('{0} người đã vào', [n]), style: TextStyle(color: s.theme.text, fontSize: 14.5, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 10),
        wave,
      ]),
    );
  }
}

/// Chủ trang: nền, đếm ngược, người đã vào, nhạc (xem); khi sửa: dòng chữ lớn, mô tả (Xong lưu, khung hiện ngay khi gõ).
class WelcomeControls extends StatefulWidget {
  final PageCtx ctx;

  /// Vào chế độ sửa tại chỗ (trang hệ thống: không có trình soạn riêng); null = vào bằng menu "Sửa" của trang.
  final VoidCallback? onEdit;
  const WelcomeControls(this.ctx, {super.key, this.onEdit});
  @override
  State<WelcomeControls> createState() => _WelcomeControlsState();
}

class _WelcomeControlsState extends State<WelcomeControls> {
  PageCtx get ctx => widget.ctx;
  Map<String, dynamic> get c => ctx.page.content;
  late final _draft = pageDraftOf(ctx.page.id);

  @override
  void dispose() {
    _draft.value = null;
    super.dispose();
  }

  void _set(String k, String v) => _draft.value = {...?_draft.value, k: v};

  Future<void> _save(Map<String, dynamic> patch) => pageContentSave(context, ctx, patch).catchError((_) {});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.theme;
    if (s.editing) {
      s.registerEdit(() async {
        final d = _draft.value;
        if (d == null || d.isEmpty) return true;
        try {
          await pageContentSave(context, ctx, d);
        } catch (_) {
          return false;
        }
        _draft.value = null;
        return true;
      });
    } else if (_draft.value != null) {
      // Huỷ: bỏ bản nháp.
      WidgetsBinding.instance.addPostFrameCallback((_) => _draft.value = null);
    }
    final presets = stagePresets(t.accent);
    final bg = '${c['bg'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.editing) ...[
        AppSectionLabel(tr('Sửa chữ trên trang')),
        _field(tr('Dòng chữ lớn'), AppInlineField(key: const ValueKey('welcome-heading'), value: '${c['heading'] ?? ctx.page.title}', maxLines: 2, onChanged: (v) => _set('heading', v), style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        _field(tr('Mô tả'), AppInlineField(key: const ValueKey('welcome-subtitle'), value: '${c['subtitle'] ?? ''}', maxLines: 3, hint: tr('Vd: Tiến độ, hợp đồng, kế hoạch'), onChanged: (v) => _set('subtitle', v), style: TextStyle(color: t.text, fontSize: 14.5))),
        const SizedBox(height: 14),
      ] else
        AppSectionLabel(tr('Điều khiển')),
      Text(tr('Nền'), style: TextStyle(color: t.sub, fontSize: 12.5)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in presets.take(8))
          Semantics(
            button: true,
            selected: bg == p.key,
            label: p.name,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _save({'bg': p.key, 'bg_image': ''}),
              child: Container(
                width: 48,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: p.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: bg == p.key ? t.accent : t.text.withValues(alpha: .15), width: bg == p.key ? 2.5 : 1),
                ),
                child: bg == p.key ? Icon(Icons.check_rounded, size: 18, color: p.light ? const Color(0xFF141A23) : Colors.white) : null,
              ),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      AppToggleRow(tr('Đếm ngược tới giờ họp'), value: c['countdown'] == true, onChanged: (v) => _save({'countdown': v})),
      AppToggleRow(tr('Hiện người đã vào'), value: c['show_online'] == true, onChanged: (v) => _save({'show_online': v})),
      AppToggleRow(tr('Phát nhạc nền cả trên máy mọi người'), sub: tr('Mặc định chỉ phát trên TV'), value: c['music_devices'] == true, onChanged: (v) => _save({'music_devices': v})),
      if (!s.editing && widget.onEdit != null) ...[
        const SizedBox(height: 6),
        AppButton(tr('Sửa chữ trên trang'), key: const ValueKey('welcome-edit'), icon: Icons.edit_outlined, onPressed: () async => widget.onEdit!()),
      ],
    ]);
  }

  Widget _field(String label, Widget child) {
    final t = AppScope.of(context).theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(color: t.light ? const Color(0xFFF1F3F6) : const Color(0xFF1F232B), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Text(label, style: TextStyle(color: t.sub, fontSize: 11.5)), const SizedBox(height: 4), child]),
    );
  }
}

/// Lời chào đang bay trên sân khấu (người vừa bấm "Vẫy chào").
class WelcomeWaves extends StatelessWidget {
  final List<String> names;
  final double scale;
  const WelcomeWaves(this.names, {super.key, this.scale = 1});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        for (final (i, n) in names.indexed)
          Opacity(
            opacity: 1 - i * .25,
            child: Container(
              margin: EdgeInsets.only(top: 8 * scale),
              padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 6 * scale),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .42), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.waving_hand_rounded, size: 16 * scale, color: const Color(0xFFF5B544)),
                SizedBox(width: 6 * scale),
                Text(tr('{0} vẫy chào', [n]), style: TextStyle(color: Colors.white, fontSize: 15 * scale, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]);
}

// ------------------------------------------------------------------ Chương trình
// content.items [{text, who, minutes, time ('HH:MM', tuỳ chọn), room}]; view.current = phiên đang diễn ra.

List<Map<String, dynamic>> agendaItems(PageCtx ctx) => [for (final x in (ctx.page.content['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];

/// Giờ bắt đầu của từng phiên: theo `time` đã ghi, không có thì cộng dồn số phút từ phiên trước (null = chưa biết giờ).
List<int?> agendaStarts(List<Map<String, dynamic>> items) {
  final out = <int?>[];
  int? prev;
  for (final it in items) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('${it['time'] ?? ''}'.trim());
    final v = m != null ? int.parse(m[1]!) * 60 + int.parse(m[2]!) : prev;
    out.add(v);
    prev = v == null ? null : v + ((it['minutes'] as num?)?.toInt() ?? 0);
  }
  return out;
}

String agendaHm(int? m) => m == null ? '' : '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// Phiên đã bấm "Nhắc tôi" (chỉ trên máy này, nhớ qua các lần mở).
class AgendaReminders {
  static final Set<String> _set = {};
  static bool _loaded = false;
  static final changes = ValueNotifier(0);

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/meet-agenda-remind.json');

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final j = jsonDecode(await (await _file()).readAsString());
      if (j is List) _set.addAll(j.map((e) => '$e'));
      changes.value++;
    } catch (_) {}
  }

  @visibleForTesting
  static void debugReset() {
    _set.clear();
    _loaded = true;
  }

  static String key(String page, Map it, int i) => '$page:${it['id'] ?? '$i:${it['text']}'}';
  static bool has(String k) => _set.contains(k);
  static Future<void> toggle(String k) async {
    if (!_set.remove(k)) _set.add(k);
    changes.value++;
    try {
      await (await _file()).writeAsString(jsonEncode(_set.toList()));
    } catch (_) {}
  }
}

/// Người xem: dòng thời gian các phiên (đang diễn ra đỏ), "Nhắc tôi" từng phiên, tab "Của tôi" (phiên đã nhắc).
class AgendaPanel extends StatefulWidget {
  final PageCtx ctx;
  const AgendaPanel(this.ctx, {super.key});
  @override
  State<AgendaPanel> createState() => _AgendaPanelState();
}

class _AgendaPanelState extends State<AgendaPanel> {
  bool _mine = false;

  @override
  void initState() {
    super.initState();
    AgendaReminders.load();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(valueListenable: AgendaReminders.changes, builder: (context, _, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.theme;
    final ctx = widget.ctx;
    final items = agendaItems(ctx);
    if (items.isEmpty) return AppCard(child: AppEmpty(icon: Icons.event_note_outlined, title: tr('Chưa có phiên nào'), sub: ctx.control ? tr('Bấm "Sửa" để thêm phiên') : null));
    final cur = ((ctx.view['current'] as num?)?.toInt() ?? 0).clamp(0, items.length - 1);
    final starts = agendaStarts(items);
    final keys = [for (final (i, it) in items.indexed) AgendaReminders.key(ctx.page.id, it, i)];
    final shown = [for (var i = 0; i < items.length; i++) if (!_mine || AgendaReminders.has(keys[i])) i];
    final mineN = keys.where(AgendaReminders.has).length;
    final next = cur + 1 < items.length ? cur + 1 : -1;
    Widget row(int i) {
      final it = items[i];
      final done = i < cur, now = i == cur;
      final dot = now ? const Color(0xFFE5343D) : (done ? t.sub.withValues(alpha: .5) : (t.light ? const Color(0xFFC9D0DA) : const Color(0xFF2A3446)));
      final sub = [if ('${it['who'] ?? ''}'.isNotEmpty) '${it['who']}', if ('${it['room'] ?? ''}'.isNotEmpty) '${it['room']}', if (((it['minutes'] as num?) ?? 0) > 0) '${it['minutes']}′'].join(' · ');
      final on = AgendaReminders.has(keys[i]);
      return Opacity(
        opacity: done ? .55 : 1,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 46,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(agendaHm(starts[i]).isEmpty ? '${i + 1}' : agendaHm(starts[i]),
                    textAlign: TextAlign.right, style: TextStyle(color: now ? t.text : t.sub, fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
            SizedBox(
              width: 22,
              child: Stack(alignment: Alignment.topCenter, children: [
                Positioned.fill(child: Center(child: Container(width: 2, color: t.light ? const Color(0xFFE3E7EE) : const Color(0xFF232A35)))),
                Container(
                  margin: const EdgeInsets.only(top: 15),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle, boxShadow: now ? const [BoxShadow(color: Color(0xAAE5343D), blurRadius: 8)] : null),
                ),
              ]),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
                decoration: BoxDecoration(
                  color: now ? const Color(0xFFE5343D).withValues(alpha: .12) : (t.light ? const Color(0xFFF1F3F6) : const Color(0xFF1B1F27)),
                  borderRadius: BorderRadius.circular(12),
                  border: now ? Border.all(color: const Color(0xFFE5343D), width: 1.5) : (on ? Border.all(color: t.accent, width: 1.5) : null),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      if (now) Text(tr('ĐANG DIỄN RA'), style: TextStyle(color: t.light ? const Color(0xFFC2272F) : const Color(0xFFFF9A9F), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                      if (i == next) Text(tr('TIẾP THEO'), style: TextStyle(color: t.sub, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                      Text('${it['text'] ?? ''}', style: TextStyle(color: t.text, fontSize: 14.5, fontWeight: FontWeight.w700)),
                      if (sub.isNotEmpty) Text(sub, style: TextStyle(color: t.sub, fontSize: 12)),
                    ]),
                  ),
                  if (!done && !now)
                    IconButton(
                      key: ValueKey('agenda-remind-$i'),
                      tooltip: on ? tr('Đã nhắc tôi · bấm để bỏ') : tr('Nhắc tôi'),
                      onPressed: () => AgendaReminders.toggle(keys[i]),
                      icon: Icon(on ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: on ? t.accent : t.sub),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSegmented<bool>(items: [(false, tr('Tất cả')), (true, tr('Của tôi · {0}', [mineN]))], value: _mine, onChanged: (v) => setState(() => _mine = v)),
        const SizedBox(height: 8),
        if (shown.isEmpty) Padding(padding: const EdgeInsets.all(14), child: Text(tr('Bấm chuông ở phiên muốn nghe để được nhắc'), textAlign: TextAlign.center, style: TextStyle(color: t.sub))),
        for (final i in shown) row(i),
      ]),
    );
  }
}

/// Chủ trang / người trình chiếu: phiên trước / sau, dời lịch các phiên còn lại; khi sửa: giờ, tên phiên, diễn giả, phòng.
class AgendaControls extends StatefulWidget {
  final PageCtx ctx;
  const AgendaControls(this.ctx, {super.key});
  @override
  State<AgendaControls> createState() => _AgendaControlsState();
}

class _AgendaControlsState extends State<AgendaControls> {
  PageCtx get ctx => widget.ctx;
  List<Map<String, dynamic>>? _rows;
  late final _draft = pageDraftOf(ctx.page.id);

  @override
  void dispose() {
    _draft.value = null;
    super.dispose();
  }

  void _push() => _draft.value = {'items': [for (final r in _rows!) {...r}]};

  /// Dời giờ các phiên từ phiên đang diễn ra trở đi thêm [m] phút (ghi giờ cụ thể cho từng phiên).
  Future<void> _shift(int m) async {
    final items = agendaItems(ctx);
    final cur = ((ctx.view['current'] as num?)?.toInt() ?? 0).clamp(0, items.isEmpty ? 0 : items.length - 1);
    final starts = agendaStarts(items);
    final out = [
      for (final (i, it) in items.indexed) {...it, if (i > cur && starts[i] != null) 'time': agendaHm(starts[i]! + m) else if (starts[i] != null) 'time': agendaHm(starts[i])},
    ];
    await pageContentSave(context, ctx, {'items': out}).catchError((_) {});
    if (mounted) meetToast(context, tr('Đã dời các phiên sau thêm {0} phút', [m]));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.theme;
    final items = agendaItems(ctx);
    if (!s.editing) {
      _rows = null;
      final cur = ((ctx.view['current'] as num?)?.toInt() ?? 0).clamp(0, items.isEmpty ? 0 : items.length - 1);
      final owner = ctx.data.role == 'owner';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(tr('Điều khiển')),
        Row(children: [
          SizedBox(width: 56, child: AppButton('‹', key: const ValueKey('agenda-prev'), onPressed: cur > 0 ? () => ctx.act('prev') : null)),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(items.isEmpty ? tr('Chưa có phiên') : (cur + 1 < items.length ? tr('Sang phiên {0}', [cur + 2]) : tr('Phiên cuối')),
                key: const ValueKey('agenda-next'), kind: AppButtonKind.primary, onPressed: cur + 1 < items.length ? () => ctx.act('next') : null),
          ),
        ]),
        if (owner && items.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(tr('Chương trình đang trễ? Dời các phiên sau'), style: TextStyle(color: t.sub, fontSize: 12.5)),
          const SizedBox(height: 8),
          Row(children: [
            for (final (i, m) in const [5, 10, 15].indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: AppButton('+$m′', key: ValueKey('agenda-shift-$m'), kind: m == 10 ? AppButtonKind.warn : AppButtonKind.tonal, onPressed: () => _shift(m))),
            ],
          ]),
        ],
      ]);
    }
    final rows = _rows ??= [for (final it in items) {...it}];
    s.registerEdit(() async {
      final clean = [for (final r in rows) if ('${r['text'] ?? ''}'.trim().isNotEmpty) r];
      try {
        await pageContentSave(context, ctx, {'items': clean});
      } catch (_) {
        return false;
      }
      _draft.value = null;
      return true;
    });
    final starts = agendaStarts(rows);
    Widget cell(Map<String, dynamic> r, String k, String hint, {double? width, bool bold = false, int i = 0}) {
      final f = AppInlineField(
        key: ValueKey('agenda-$k-$i-${rows.length}'),
        value: '${r[k] ?? ''}',
        hint: hint,
        onChanged: (v) {
          r[k] = k == 'minutes' ? (int.tryParse(v) ?? 0) : v;
          _push();
        },
        style: TextStyle(color: t.text, fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
      );
      return width == null ? Expanded(child: f) : SizedBox(width: width, child: f);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Sửa chương trình')),
      for (final (i, r) in rows.indexed)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
          decoration: BoxDecoration(color: t.light ? const Color(0xFFF1F3F6) : const Color(0xFF1F232B), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Row(children: [
              cell(r, 'time', agendaHm(starts[i]).isEmpty ? '09:00' : agendaHm(starts[i]), width: 64, i: i),
              const SizedBox(width: 8),
              cell(r, 'text', tr('Tên phiên'), bold: true, i: i),
              IconButton(tooltip: tr('Lên trên'), onPressed: i == 0 ? null : () => setState(() { rows.insert(i - 1, rows.removeAt(i)); _push(); }), icon: Icon(Icons.arrow_upward_rounded, color: t.sub, size: 20)),
              IconButton(tooltip: tr('Xoá phiên'), onPressed: () => setState(() { rows.removeAt(i); _push(); }), icon: Icon(Icons.close_rounded, color: t.sub, size: 20)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const SizedBox(width: 72),
              cell(r, 'who', tr('Diễn giả'), i: i),
              const SizedBox(width: 8),
              cell(r, 'room', tr('Phòng'), i: i),
              const SizedBox(width: 8),
              cell(r, 'minutes', tr('Phút'), width: 48, i: i),
              const SizedBox(width: 44),
            ]),
          ]),
        ),
      AppButton(tr('Thêm phiên'), key: const ValueKey('agenda-add'), icon: Icons.add_rounded, onPressed: () async => setState(() {
            rows.add({'text': '', 'who': '', 'minutes': 15});
            _push();
          })),
    ]);
  }
}

/// Chương trình trên sân khấu (bảng 16): dòng thời gian trái (giờ, chấm, thẻ; phiên đang diễn ra đỏ), phải: đếm ngược của
/// phiên đang diễn ra và phiên tiếp theo. Dọc: chỉ dòng thời gian quanh phiên hiện tại.
class AgendaTimeline extends StatelessWidget {
  final PageCtx ctx;
  const AgendaTimeline(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final m = StageMetrics.of(context);
    if (m == null) return FittedBox(child: SizedBox(width: 1168, height: 560, child: StageMetrics(theme: const StageTheme(), portrait: false, size: const Size(1168, 560), child: AgendaTimeline(ctx))));
    final t = m.theme;
    final portrait = m.portrait;
    final draft = pageDraftOf(ctx.page.id).value;
    final items = draft?['items'] is List ? [for (final x in draft!['items'] as List) (x as Map).cast<String, dynamic>()] : agendaItems(ctx);
    if (items.isEmpty) return Center(child: Text(tr('Chưa có phiên nào'), style: TextStyle(color: t.sub, fontSize: 24)));
    final cur = ((ctx.view['current'] as num?)?.toInt() ?? 0).clamp(0, items.length - 1);
    final starts = agendaStarts(items);
    final red = t.light ? const Color(0xFFC2272F) : const Color(0xFFFF9A9F);
    final started = (ctx.view['started_at'] as num?)?.toInt() ?? 0;
    final mins = (items[cur]['minutes'] as num?)?.toInt() ?? 0;
    final el = started > 0 ? ((DateTime.now().millisecondsSinceEpoch - started) / 1000).floor() : 0;
    final left = mins > 0 ? (mins * 60 - el).clamp(0, 359999) : 0;
    String two(int n) => n.toString().padLeft(2, '0');
    final from = portrait ? (cur - 1).clamp(0, items.length) : (cur - 1).clamp(0, (items.length - 5).clamp(0, items.length));
    final view = items.indexed.skip(from).take(portrait ? 5 : 5).toList();

    Widget row((int, Map<String, dynamic>) e) {
      final (i, it) = e;
      final done = i < cur, now = i == cur;
      final sub = [if ('${it['who'] ?? ''}'.isNotEmpty) '${it['who']}', if ('${it['room'] ?? ''}'.isNotEmpty) '${it['room']}'].join(' · ');
      return Opacity(
        opacity: done ? .5 : 1,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: portrait ? 64 : 84,
              child: Padding(
                padding: EdgeInsets.only(top: now ? 22 : 14),
                child: Text(agendaHm(starts[i]).isEmpty ? '${i + 1}' : agendaHm(starts[i]),
                    textAlign: TextAlign.right, style: TextStyle(color: now ? t.text : t.sub, fontSize: portrait ? 17 : 20, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
            SizedBox(
              width: 32,
              child: Stack(alignment: Alignment.topCenter, children: [
                Positioned.fill(child: Center(child: Container(width: 3, color: t.light ? const Color(0xFFE3E7EE) : const Color(0xFF232A35)))),
                Container(
                  margin: EdgeInsets.only(top: now ? 24 : 17),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: now ? const Color(0xFFE5343D) : (t.light ? const Color(0xFFC9D0DA) : const Color(0xFF2A3446)),
                    shape: BoxShape.circle,
                    border: Border.all(color: t.bg, width: 3),
                    boxShadow: now ? const [BoxShadow(color: Color(0xAAE5343D), blurRadius: 12)] : null,
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: now ? 14 : 10),
                decoration: BoxDecoration(
                  color: now ? const Color(0xFFE5343D).withValues(alpha: .12) : t.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: now ? Border.all(color: const Color(0xFFE5343D), width: 2) : null,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (now) Text(mins > 0 ? tr('ĐANG DIỄN RA · CÒN {0} PHÚT', [(left / 60).ceil()]) : tr('ĐANG DIỄN RA'), style: TextStyle(color: red, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  Text('${it['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: now ? (portrait ? 24 : 28) : (portrait ? 18 : 20), fontWeight: FontWeight.w700, height: 1.15)),
                  if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.sub, fontSize: portrait ? 14 : 16)),
                ]),
              ),
            ),
          ]),
        ),
      );
    }

    final line = Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final e in view) row(e)]);
    if (portrait) return Padding(padding: const EdgeInsets.fromLTRB(4, 8, 12, 8), child: line);
    final nx = cur + 1 < items.length ? items[cur + 1] : null;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(child: line),
      const SizedBox(width: 32),
      SizedBox(
        width: 320,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (mins > 0)
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('CÒN LẠI CỦA PHIÊN'), style: TextStyle(color: t.sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                const SizedBox(height: 6),
                Text('${two(left ~/ 60)}:${two(left % 60)}', style: TextStyle(color: t.text, fontSize: 72, fontWeight: FontWeight.w800, height: 1, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: started > 0 ? (el / (mins * 60)).clamp(0.0, 1.0) : 0, minHeight: 8, backgroundColor: t.surface2, valueColor: const AlwaysStoppedAnimation(Color(0xFFE5343D))),
                ),
              ]),
            ),
          if (nx != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(agendaHm(starts[cur + 1]).isEmpty ? tr('TIẾP THEO') : tr('TIẾP THEO · {0}', [agendaHm(starts[cur + 1])]), style: TextStyle(color: t.sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                const SizedBox(height: 6),
                Text('${nx['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 19, height: 1.3)),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }
}
