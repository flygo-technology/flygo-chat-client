import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../meet/meet_home.dart' show meetToast;
import 'app_kit.dart';
import 'app_shell.dart';
import 'page_types.dart';
import 'pages_api.dart';
import 'stage_frame.dart';
import 'sys_media_apps.dart';
import 'system_pages.dart';
import 'types/welcome_agenda.dart';

// Trang hệ thống thành app (mockup bảng 01 Chào mừng, 02 Chờ lượt, 03 Nội dung): cùng vỏ PageAppShell như trang thường,
// nhưng dữ liệu là metadata.stage (cấu hình cuộc họp) và hành động là /meet/stage (call.stageAct).

/// Trang hệ thống có phần app (người xem tương tác / chủ trì điều khiển).
const sysAppIds = {'sys:welcome', 'sys:program', 'sys:handover', 'sys:screen', 'sys:auto', 'sys:grid'};

/// Trang hệ thống đang được chủ trì sửa tại chỗ (id), null = không.
final sysAppEditing = ValueNotifier<String?>(null);

String _me(CallService call) => call.myId();

/// Ngữ cảnh của trang hệ thống [id]: content = cấu hình (welcome_cfg / program_cfg / handover_cfg), view = metadata.stage.
/// Chủ trì là manager (điều khiển); người trình chiếu điều khiển được Nội dung (chuyển phần).
PageCtx sysAppCtx(CallService call, String id, {void Function(String error)? onError}) {
  final st = (call.roomStage ?? const {}).cast<String, dynamic>();
  final cfg = switch (id) {
    'sys:welcome' => st['welcome_cfg'],
    'sys:program' => st['program_cfg'],
    'sys:screen' => st['screen_cfg'],
    'sys:auto' || 'sys:grid' => st['video_cfg'],
    _ => st['handover_cfg'],
  } as Map?;
  final label = sysPages.where((p) => p.id == id).firstOrNull?.label ?? '';
  return PageCtx(
    data: PageData.from({
      'page': {'id': id, 'type': id == 'sys:welcome' ? 'welcome' : id.replaceFirst(':', '_'), 'title': label, 'owner': '', 'visibility': 'meeting', 'content': cfg ?? const {}},
      'view': st,
      'role': call.canModerate ? 'manager' : 'viewer',
      'rev': 0,
    }),
    api: PagesApi(call),
    call: call,
    // Người trình chiếu điều khiển được Nội dung (chuyển phần) và Chiếu màn hình (che, cho chỉ laser); người đang chiếu
    // màn hình cũng vậy.
    presenting: (id == 'sys:program' || id == 'sys:screen') && st['presenter'] == _me(call) && '${st['presenter'] ?? ''}'.isNotEmpty ||
        id == 'sys:screen' && call.localScreen != null,
    onStage: false,
    act: (a, [b = const {}]) async {
      final e = await call.stageAct(a, b);
      if (e != null) onError?.call(e);
    },
    reload: () async {},
  );
}

/// Phần app của trang hệ thống [id] (null = không phải trang hệ thống có app).
PageTypeSpec? sysAppSpec(String id) {
  final sys = sysPages.where((p) => p.id == id).firstOrNull;
  if (sys == null || !sysAppIds.contains(id)) return null;
  return switch (id) {
    'sys:welcome' => PageTypeSpec(
        type: 'welcome',
        label: sys.label,
        icon: sys.icon,
        color: sys.color,
        view: (context, ctx) => pageTypeOf('welcome')?.view(context, ctx) ?? const SizedBox.shrink(),
        panel: (context, ctx) => WelcomePanel(ctx),
        controls: (context, ctx) => WelcomeControls(ctx, onEdit: () => sysAppEditing.value = id),
        inlineEdit: true,
        stageBleed: true,
      ),
    'sys:program' => PageTypeSpec(
        type: 'sys_program',
        label: sys.label,
        icon: sys.icon,
        color: sys.color,
        stageThemed: true,
        view: (context, ctx) => ValueListenableBuilder(
          valueListenable: pageDraftOf(id),
          builder: (context, d, _) => ProgramView(call: ctx.call, cfg: {...ctx.page.content, ...?d}, controls: false),
        ),
        panel: (context, ctx) => ProgramPanel(ctx),
        controls: (context, ctx) => ProgramControls(ctx),
        inlineEdit: true,
      ),
    'sys:screen' => PageTypeSpec(
        type: 'sys_screen',
        label: sys.label,
        icon: sys.icon,
        color: sys.color,
        stageThemed: true,
        view: (context, ctx) => ScreenStagePreview(ctx),
        panel: (context, ctx) => ScreenPanel(ctx),
        controls: (context, ctx) => ScreenControls(ctx),
      ),
    'sys:auto' || 'sys:grid' => PageTypeSpec(
        type: id.replaceFirst(':', '_'),
        label: sys.label,
        icon: sys.icon,
        color: sys.color,
        stageThemed: true,
        view: (context, ctx) => VideoStagePreview(ctx, grid: id == 'sys:grid'),
        panel: (context, ctx) => VideoViewerPanel(ctx),
        controls: (context, ctx) => VideoRoomControls(ctx),
      ),
    _ => PageTypeSpec(
        type: 'sys_handover',
        label: sys.label,
        icon: sys.icon,
        color: sys.color,
        stageThemed: true,
        stageBleed: true,
        view: (context, ctx) => HandoverView(stage: ctx.view),
        panel: (context, ctx) => HandoverPanel(ctx),
        controls: (context, ctx) => HandoverControls(ctx),
      ),
  };
}

/// Trang hệ thống trong bảng trang (điện thoại: bảng kéo lên; máy tính: cột phải): vỏ app chung.
class SysAppView extends StatelessWidget {
  final CallService call;
  final String id;

  /// Máy tính (cột phải của cuộc họp): trang đang LIVE thì không vẽ lại sân khấu.
  final bool panel;
  const SysAppView({super.key, required this.call, required this.id, this.panel = false});

  @override
  Widget build(BuildContext context) {
    final spec = sysAppSpec(id);
    if (spec == null) return const SizedBox.shrink();
    final ctx = sysAppCtx(call, id, onError: (e) => meetToast(context, e));
    return ValueListenableBuilder<String?>(
      valueListenable: sysAppEditing,
      builder: (context, editing, _) => PageAppShell(
        ctx: ctx,
        spec: spec,
        stage: !(panel && ctx.live),
        editing: editing == id && ctx.control && spec.inlineEdit,
        onEditEnd: () => sysAppEditing.value = null,
      ),
    );
  }
}

/// Nút "Sửa" của chủ trì cho trang hệ thống (vào chế độ sửa tại chỗ của vỏ app).
Widget _editButton(PageCtx ctx, String label) =>
    AppButton(label, key: ValueKey('sys-edit-${ctx.page.id}'), icon: Icons.edit_outlined, onPressed: () async => sysAppEditing.value = ctx.page.id);

/// Dải thao tác nhanh dưới ô sân khấu (màn họp, không thu nhỏ): người xem dùng app ngay, nút mở app đầy đủ.
/// null = trang này không có thao tác.
Widget? sysQuickStrip(BuildContext context, CallService call, String id, {required VoidCallback onOpen}) {
  if (!sysAppIds.contains(id)) return null;
  final st = call.roomStage ?? const {};
  final t = StageTheme.of(st['theme_cfg'] as Map?);
  final me = _me(call);
  Future<void> act(String a, [Map<String, dynamic> b = const {}]) async {
    final e = await call.stageAct(a, b);
    if (e != null && context.mounted) meetToast(context, e);
  }

  final buttons = <Widget>[];
  switch (id) {
    case 'sys:welcome':
      buttons.add(AppButton(tr('Vẫy chào'), key: const ValueKey('strip-wave'), icon: Icons.waving_hand_outlined, onPressed: () async => call.react('👋')));
    case 'sys:handover':
      final queued = (st['queue'] as List? ?? const []).any((q) => (q as Map)['id'] == me);
      if (st['presenter'] == me) {
        buttons.add(AppButton(tr('Bắt đầu trình bày'), key: const ValueKey('strip-start'), kind: AppButtonKind.primary, icon: Icons.play_arrow_rounded, onPressed: () => act('next')));
      } else {
        buttons.add(queued
            ? AppButton(tr('Rút lượt'), key: const ValueKey('strip-cancel'), onPressed: () => act('cancel'))
            : AppButton(tr('Xin lượt'), key: const ValueKey('strip-request'), icon: Icons.front_hand_outlined, onPressed: () => act('request')));
      }
    case 'sys:program':
      final c = (st['program_cfg'] as Map?) ?? const {};
      final (more, clear) = _fb(c, me);
      buttons.addAll([
        AppButton(tr('Cần thêm thời gian'), key: const ValueKey('strip-more'), kind: more ? AppButtonKind.warn : AppButtonKind.tonal, onPressed: () => act('program_fb', {'fb': more ? '' : 'more'})),
        AppButton(tr('Đã rõ'), key: const ValueKey('strip-clear'), kind: clear ? AppButtonKind.success : AppButtonKind.tonal, onPressed: () => act('program_fb', {'fb': clear ? '' : 'clear'})),
      ]);
  }
  return AppScope(
    form: AppForm.phoneLandscape,
    theme: t,
    hub: AppEditHub(),
    child: Builder(
      builder: (context) => Container(
        color: t.light ? const Color(0xFFF7F8FA) : const Color(0xFF0E1116),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(children: [
          for (final b in buttons) ...[Expanded(child: b), const SizedBox(width: 8)],
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: ValueKey('strip-open-$id'),
              tooltip: tr('Mở app'),
              onPressed: onOpen,
              style: IconButton.styleFrom(backgroundColor: t.light ? const Color(0xFFE3E7EE) : const Color(0xFF262B33), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              icon: Icon(Icons.open_in_full_rounded, size: 18, color: t.text),
            ),
          ),
        ]),
      ),
    ),
  );
}

/// (mình bấm "cần thêm thời gian", mình bấm "đã rõ") cho phần đang diễn ra.
(bool, bool) _fb(Map c, String me) {
  final fb = (c['fb'] as Map?) ?? const {};
  if ((fb['index'] as num?)?.toInt() != ((c['current'] as num?)?.toInt() ?? 0)) return (false, false);
  return ((fb['more'] as List? ?? const []).contains(me), (fb['clear'] as List? ?? const []).contains(me));
}

(int, int) _fbCounts(Map c) {
  final fb = (c['fb'] as Map?) ?? const {};
  if ((fb['index'] as num?)?.toInt() != ((c['current'] as num?)?.toInt() ?? 0)) return (0, 0);
  return ((fb['more'] as List? ?? const []).length, (fb['clear'] as List? ?? const []).length);
}

String _fbText(Map c) {
  final (m, cl) = _fbCounts(c);
  return tr('{0} người cần thêm thời gian · {1} người đã rõ', [m, cl]);
}

// ------------------------------------------------------------------ Nội dung

List<Map<String, dynamic>> _programItems(Map c) => [for (final x in (c['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];

/// Người xem: phần đang diễn ra, "Cần thêm thời gian" / "Đã rõ" (bấm lại để bỏ), số người đã bấm.
class ProgramPanel extends StatelessWidget {
  final PageCtx ctx;
  const ProgramPanel(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = ctx.page.content;
    final items = _programItems(c);
    if (items.isEmpty) return AppCard(child: AppEmpty(icon: Icons.format_list_numbered_rounded, title: tr('Chưa có nội dung'), sub: ctx.control ? tr('Bấm "Sửa nội dung" để thêm phần') : null));
    final cur = ((c['current'] as num?)?.toInt() ?? 0).clamp(0, items.length - 1);
    final (more, clear) = _fb(c, _me(ctx.call));
    final buttons = [
      AppButton(tr('Cần thêm thời gian'), key: const ValueKey('program-more'), kind: more ? AppButtonKind.warn : AppButtonKind.tonal, onPressed: () => ctx.act('program_fb', {'fb': more ? '' : 'more'})),
      AppButton(tr('Đã rõ'), key: const ValueKey('program-clear'), kind: clear ? AppButtonKind.success : AppButtonKind.tonal, icon: clear ? Icons.check_rounded : null, onPressed: () => ctx.act('program_fb', {'fb': clear ? '' : 'clear'})),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(tr('Phần {0} / {1} · đang diễn ra', [cur + 1, items.length])),
        Text('${items[cur]['title'] ?? ''}', style: TextStyle(color: s.theme.text, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (s.compact)
          ...[buttons[0], const SizedBox(height: 8), buttons[1]]
        else
          Row(children: [Expanded(child: buttons[0]), const SizedBox(width: 8), Expanded(child: buttons[1])]),
        const SizedBox(height: 8),
        Text(_fbText(c), style: TextStyle(color: s.theme.sub, fontSize: 12.5)),
      ]),
    );
  }
}

/// Chủ trì / người trình chiếu: phần trước / sau, trao lượt cho người phụ trách, tự chạy; khi sửa: tiêu đề và các phần
/// (tên, người phụ trách, số phút, thứ tự).
class ProgramControls extends StatefulWidget {
  final PageCtx ctx;
  const ProgramControls(this.ctx, {super.key});
  @override
  State<ProgramControls> createState() => _ProgramControlsState();
}

class _ProgramControlsState extends State<ProgramControls> {
  PageCtx get ctx => widget.ctx;
  List<Map<String, dynamic>>? _rows;
  String? _title;
  late final _draft = pageDraftOf('sys:program');

  @override
  void dispose() {
    _draft.value = null;
    super.dispose();
  }

  void _push() => _draft.value = {'title': _title, 'items': [for (final r in _rows!) {...r}]};

  /// Người có thể phụ trách: người đang trong cuộc họp (và mình).
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
    final c = ctx.page.content;
    final items = _programItems(c);
    if (!s.editing) {
      _rows = null;
      _title = null;
      final cur = ((c['current'] as num?)?.toInt() ?? 0).clamp(0, items.isEmpty ? 0 : items.length - 1);
      final owner = items.isEmpty ? '' : '${items[cur]['owner'] ?? ''}';
      final ownerName = items.isEmpty ? '' : '${items[cur]['owner_name'] ?? ''}';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(tr('Điều khiển')),
        if (items.isNotEmpty) ...[
          Row(children: [
            SizedBox(width: 52, child: AppButton('‹', key: const ValueKey('program-prev'), onPressed: cur > 0 ? () => ctx.act('program_goto', {'index': cur - 1}) : null)),
            const SizedBox(width: 8),
            Expanded(
              child: ctx.data.manage && owner.isNotEmpty
                  ? AppButton(tr('Trao lượt cho {0}', [ownerName]), key: const ValueKey('program-grant'), kind: AppButtonKind.primary, onPressed: () => ctx.act('program_goto', {'index': cur, 'grant': true}))
                  : AppButton(tr('Phần {0} / {1}', [cur + 1, items.length]), onPressed: null),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 52, child: AppButton('›', key: const ValueKey('program-next'), onPressed: cur < items.length - 1 ? () => ctx.act('program_next') : null)),
          ]),
          const SizedBox(height: 8),
          Text(_fbText(c), style: TextStyle(color: t.sub, fontSize: 12.5)),
        ],
        if (ctx.data.manage) ...[
          AppToggleRow(tr('Tự sang phần sau khi hết giờ'), value: c['auto'] == true, onChanged: (v) => ctx.act('config', {'program': {'auto': v}})),
          const SizedBox(height: 4),
          _editButton(ctx, tr('Sửa nội dung')),
        ],
      ]);
    }
    final rows = _rows ??= [for (final it in items) {...it}];
    _title ??= '${c['title'] ?? tr('Nội dung')}';
    s.registerEdit(() async {
      final clean = [for (final r in rows) if ('${r['title'] ?? ''}'.trim().isNotEmpty) r];
      final e = await ctx.call.stageAct('config', {'program': {'title': _title, 'items': clean}});
      if (e != null) {
        if (context.mounted) meetToast(context, e);
        return false;
      }
      _draft.value = null;
      return true;
    });
    final people = _people(context);
    final box = t.light ? const Color(0xFFF1F3F6) : const Color(0xFF1F232B);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Sửa nội dung')),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: box, borderRadius: BorderRadius.circular(12)),
        child: AppInlineField(key: const ValueKey('program-title'), value: _title!, onChanged: (v) {
          _title = v;
          _push();
        }, style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: 8),
      for (final (i, r) in rows.indexed)
        Container(
          key: ValueKey('program-row-$i-${rows.length}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(10, 8, 2, 4),
          decoration: BoxDecoration(color: box, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(color: t.sub, fontWeight: FontWeight.w700))),
              Expanded(
                child: AppInlineField(key: ValueKey('program-t-$i-${rows.length}'), value: '${r['title'] ?? ''}', hint: tr('Tên phần'), onChanged: (v) {
                  r['title'] = v;
                  _push();
                }, style: TextStyle(color: t.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: AppInlineField(key: ValueKey('program-m-$i-${rows.length}'), value: ((r['minutes'] as num?) ?? 0) == 0 ? '' : '${r['minutes']}', hint: tr('phút'), onChanged: (v) {
                  r['minutes'] = int.tryParse(v.trim()) ?? 0;
                  _push();
                }, style: TextStyle(color: t.text, fontSize: 14)),
              ),
              IconButton(tooltip: tr('Lên trên'), onPressed: i == 0 ? null : () => setState(() { rows.insert(i - 1, rows.removeAt(i)); _push(); }), icon: Icon(Icons.arrow_upward_rounded, size: 20, color: t.sub)),
              IconButton(tooltip: tr('Xoá phần'), onPressed: () => setState(() { rows.removeAt(i); _push(); }), icon: Icon(Icons.close_rounded, size: 20, color: t.sub)),
            ]),
            Builder(
              builder: (b) => AppSelectRow(
                tr('Phụ trách'),
                value: '${r['owner_name'] ?? ''}'.isEmpty ? tr('Chọn người') : '${r['owner_name']}',
                onTap: () => showAppMenu(b, items: [
                  PageMenuItem(label: tr('Không ai'), icon: Icons.person_off_outlined, onTap: () async => setState(() { r['owner'] = ''; r['owner_name'] = ''; _push(); })),
                  for (final e in people.entries)
                    PageMenuItem(label: e.value, icon: Icons.person_outline_rounded, onTap: () async => setState(() { r['owner'] = e.key; r['owner_name'] = e.value; _push(); })),
                ]),
              ),
            ),
          ]),
        ),
      AppButton(tr('Thêm phần'), key: const ValueKey('program-add'), icon: Icons.add_rounded, onPressed: () async => setState(() {
            rows.add({'title': '', 'owner': '', 'owner_name': '', 'minutes': 5});
            _push();
          })),
    ]);
  }
}

// ------------------------------------------------------------------ Chờ lượt trình chiếu

List<Map> _queue(Map st) => [for (final q in (st['queue'] as List? ?? const [])) q as Map];

Widget _queueRow(StageTheme t, String name, String badge, {bool now = false, bool me = false, List<Widget> actions = const []}) => Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.fromLTRB(10, actions.isEmpty ? 10 : 4, actions.isEmpty ? 12 : 2, actions.isEmpty ? 10 : 4),
      decoration: BoxDecoration(
        color: t.light ? const Color(0xFFF1F3F6) : const Color(0xFF1B1F27),
        borderRadius: BorderRadius.circular(12),
        border: now ? Border.all(color: t.accent, width: 1.5) : (me ? Border.all(color: t.sub.withValues(alpha: .5)) : null),
      ),
      child: Row(children: [
        AppAvatar(name, size: 30),
        const SizedBox(width: 10),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 14.5, fontWeight: me ? FontWeight.w700 : FontWeight.w500))),
        if (badge.isNotEmpty) Text(badge, style: TextStyle(color: now ? (t.light ? t.accent : const Color(0xFF9DBBFF)) : t.sub, fontSize: 12, fontWeight: FontWeight.w700)),
        ...actions,
      ]),
    );

/// Người xem: người đang được mời + hàng chờ (vị trí của mình), xin / rút lượt. Người được mời: chọn trang mở đầu,
/// "Bắt đầu trình bày", "Chưa sẵn sàng, đẩy xuống sau".
class HandoverPanel extends StatefulWidget {
  final PageCtx ctx;
  const HandoverPanel(this.ctx, {super.key});
  @override
  State<HandoverPanel> createState() => _HandoverPanelState();
}

class _HandoverPanelState extends State<HandoverPanel> {
  PageCtx get ctx => widget.ctx;
  Future<List<MeetPage>>? _mine;
  String? _pick;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final t = s.theme;
    final st = ctx.view;
    final me = _me(ctx.call);
    final queue = _queue(st);
    final presenter = '${st['presenter'] ?? ''}';
    final presenterName = '${st['presenter_name'] ?? ''}';
    final pos = queue.indexWhere((q) => q['id'] == me);
    if (presenter.isNotEmpty && presenter == me) {
      _mine ??= ctx.api.list('mine').catchError((_) => <MeetPage>[]);
      return AppCard(
        outline: t.accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSectionLabel(tr('Đến lượt bạn trình bày')),
          FutureBuilder<List<MeetPage>>(
            future: _mine,
            builder: (context, snap) {
              final pages = snap.data ?? const <MeetPage>[];
              if (pages.isEmpty) {
                return Text(snap.connectionState == ConnectionState.done ? tr('Bạn chưa có trang nào: bắt đầu sẽ chiếu màn hình chờ, thêm trang ở Apps.') : tr('Đang tải trang của bạn…'),
                    style: TextStyle(color: t.sub, fontSize: 13));
              }
              _pick ??= pages.first.id;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('Mở đầu bằng trang'), style: TextStyle(color: t.sub, fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in pages.take(8)) AppChip(p.title, key: ValueKey('handover-pick-${p.id}'), selected: p.id == _pick, onTap: () => setState(() => _pick = p.id)),
                ]),
              ]);
            },
          ),
          const SizedBox(height: 12),
          AppButton(tr('Bắt đầu trình bày'), key: const ValueKey('handover-start'), kind: AppButtonKind.primary, icon: Icons.play_arrow_rounded, onPressed: () => _pick == null ? ctx.act('next') : ctx.act('show', {'page': _pick})),
          const SizedBox(height: 8),
          AppButton(tr('Chưa sẵn sàng, đẩy xuống sau'), key: const ValueKey('handover-defer'), onPressed: queue.isEmpty ? null : () => ctx.act('defer')),
        ]),
      );
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(tr('Hàng chờ')),
        if (presenter.isNotEmpty) _queueRow(t, presenterName, tr('BÂY GIỜ'), now: true),
        for (final (i, q) in queue.indexed) _queueRow(t, q['id'] == me ? tr('Bạn') : '${q['name'] ?? ''}', '${i + 2}', me: q['id'] == me),
        if (presenter.isEmpty && queue.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('Chưa ai xin lượt'), style: TextStyle(color: t.sub))),
        const SizedBox(height: 6),
        if (pos >= 0)
          AppButton(tr('Rút lại lượt của tôi'), key: const ValueKey('handover-cancel'), onPressed: () => ctx.act('cancel'))
        else
          AppButton(tr('Xin lượt trình bày'), key: const ValueKey('handover-request'), kind: AppButtonKind.primary, icon: Icons.front_hand_outlined, onPressed: () => ctx.act('request')),
        if (pos >= 0) ...[const SizedBox(height: 6), Text(tr('Bạn ở vị trí {0}', [pos + 2]), textAlign: TextAlign.center, style: TextStyle(color: t.sub, fontSize: 12.5))],
      ]),
    );
  }
}

/// Chủ trì: sắp xếp hàng chờ (lên trước), trao lượt ngay, bỏ khỏi hàng.
class HandoverControls extends StatelessWidget {
  final PageCtx ctx;
  const HandoverControls(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final queue = _queue(ctx.view);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Chủ trì · hàng chờ')),
      if (queue.isEmpty) Text(tr('Hàng chờ trống'), style: TextStyle(color: t.sub, fontSize: 13)),
      for (final (i, q) in queue.indexed)
        _queueRow(t, '${q['name'] ?? ''}', '', actions: [
          IconButton(key: ValueKey('handover-up-$i'), tooltip: tr('Lên trước'), onPressed: i == 0 ? null : () => ctx.act('queue_move', {'user': q['id'], 'to': i - 1}), icon: Icon(Icons.arrow_upward_rounded, size: 20, color: t.sub)),
          TextButton(key: ValueKey('handover-grant-$i'), onPressed: () => ctx.act('grant', {'user': q['id'], 'name': q['name']}), child: Text(tr('Trao lượt'))),
          IconButton(key: ValueKey('handover-remove-$i'), tooltip: tr('Bỏ khỏi hàng'), onPressed: () => ctx.act('queue_remove', {'user': q['id']}), icon: Icon(Icons.close_rounded, size: 20, color: t.sub)),
        ]),
    ]);
  }
}
