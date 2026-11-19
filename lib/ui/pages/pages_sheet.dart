import 'dart:async';

import 'package:flutter/material.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../meet/meet_home.dart' show meetToast;
import 'page_types.dart';
import 'pages_api.dart';
import 'types/builtin.dart' show pageField;

// Họp (mới): bảng kéo lên (thấp: danh sách, vẫn thấy sân khấu · vừa: soạn nhanh · cao hết: soạn kỹ) với
// "Trang của tôi" / "Công khai" / "Lượt trình chiếu", và khung sân khấu hiện trang đang chiếu.

const _bg = Color(0xFF23262C);
const _card = Color(0xFF2D3036);
const _sub = Color(0xFF9AA0A6);
const _acc = Color(0xFF8AB4F8);

/// Sân khấu đang hiện một trang (không phải tài liệu: tài liệu đi qua khung trình chiếu có sẵn).
bool stageShowsPage(CallService call) {
  final st = call.roomStage;
  if (st == null) return false;
  if ('${st['page'] ?? ''}'.isNotEmpty) return st['page_type'] != 'doc' || call.roomPresent?['page_id'] != st['page'];
  return '${st['idle_page'] ?? ''}'.isNotEmpty && call.roomPresent == null;
}

String fmtLeft(int ms) {
  final s = (ms / 1000).ceil().clamp(0, 359999);
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Trang đang lên sân khấu (hoặc trang chờ), kèm nút điều khiển cho người trình chiếu / chủ trì.
class StagePageView extends StatefulWidget {
  final CallService call;
  final bool compact;
  const StagePageView({super.key, required this.call, this.compact = false});
  @override
  State<StagePageView> createState() => _StagePageViewState();
}

class _StagePageViewState extends State<StagePageView> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (widget.call.roomStage?['ends_at'] ?? 0) != 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final st = call.roomStage ?? const {};
    final shown = '${st['page'] ?? ''}';
    final id = shown.isNotEmpty ? shown : '${st['idle_page'] ?? ''}';
    final key = shown.isNotEmpty ? '${st['key'] ?? ''}' : '${st['idle_key'] ?? ''}';
    if (id.isEmpty) return const SizedBox.shrink();
    final mine = st['presenter'] == call.myId();
    final control = shown.isNotEmpty && (mine || call.canModerate);
    final ends = (st['ends_at'] as num?)?.toInt() ?? 0;
    final left = ends == 0 ? 0 : ends - DateTime.now().millisecondsSinceEpoch;
    return Stack(children: [
      Positioned.fill(
        child: PageHost(
          key: ValueKey('stage:$id'),
          call: call,
          id: id,
          stageKey: key.isEmpty ? null : key,
          onStage: true,
          builder: (context, ctx, spec) => spec == null ? unknownPageView(ctx) : spec.view(context, ctx),
        ),
      ),
      if (shown.isNotEmpty && !widget.compact)
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(12)),
            child: Text(
              [tr('Đang chiếu: {0}', ['${st['presenter_name'] ?? ''}']), '${st['page_title'] ?? ''}', if (left > 0) tr('còn {0}', [fmtLeft(left)]), if (st['paused'] == true) tr('tạm dừng')].join(' · '),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      if (control && !widget.compact)
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(Icons.skip_previous_rounded, () => call.stageAct('prev')),
              if (st['mode'] == 'auto')
                _btn(st['paused'] == true ? Icons.play_arrow_rounded : Icons.pause_rounded, () => call.stageAct(st['paused'] == true ? 'resume' : 'pause')),
              _btn(Icons.skip_next_rounded, () => call.stageAct('next')),
              _btn(Icons.stop_rounded, () => call.stageAct('end')),
            ]),
          ),
        ),
    ]);
  }

  Widget _btn(IconData i, Future<String?> Function() f) => IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(i, color: Colors.white, size: 20),
        onPressed: () async {
          final e = await f();
          if (e != null && mounted) meetToast(context, e);
        },
      );
}

/// Mở bảng kéo lên Trang họp.
Future<void> showPagesSheet(BuildContext context, CallService call) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (ctx) => _PagesSheet(call: call),
    );

class _PagesSheet extends StatefulWidget {
  final CallService call;
  const _PagesSheet({required this.call});
  @override
  State<_PagesSheet> createState() => _PagesSheetState();
}

class _PagesSheetState extends State<_PagesSheet> {
  late final api = PagesApi(widget.call);
  final _sheet = DraggableScrollableController();
  int _tab = 0;
  List<MeetPage> _mine = const [], _public = const [];
  String? _err;
  String? _editing; // id trang đang soạn
  String? _viewing; // id trang công khai đang xem
  StreamSubscription? _fx;

  CallService get call => widget.call;

  @override
  void initState() {
    super.initState();
    _load();
    call.addListener(_changed);
    _fx = call.fxEvents.stream.listen((m) {
      if (m['t'] == 'fx_page') _load();
    });
  }

  @override
  void dispose() {
    call.removeListener(_changed);
    _fx?.cancel();
    _sheet.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([api.list('mine'), api.list('public')]);
      if (mounted) {
        setState(() {
          _mine = r[0];
          _public = r[1];
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  void _size(double s) {
    if (_sheet.isAttached) _sheet.animateTo(s, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _toast(Future<String?> f) async {
    final e = await f;
    if (e != null && mounted) meetToast(context, e);
  }

  Future<void> _new() async {
    final spec = await showModalBottomSheet<PageTypeSpec>(
      context: context,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in pageTypes)
              SizedBox(
                width: 160,
                child: Material(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, s),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: [
                        _typeIcon(s),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            if (s.desc.isNotEmpty) Text(s.desc, maxLines: 2, style: const TextStyle(color: _sub, fontSize: 11)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
    if (spec == null || !mounted) return;
    try {
      final d = spec.create == null ? PageDraft(title: spec.label) : await spec.create!(context, call);
      if (d == null) return;
      final p = await api.create(type: spec.type, title: d.title, content: d.content, init: d.init, seconds: d.seconds != 0 ? d.seconds : spec.seconds);
      await _load();
      if (!mounted) return;
      setState(() => _editing = p.page.id);
      _size(.72);
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheet,
      initialChildSize: .45,
      minChildSize: .2,
      maxChildSize: 1,
      snap: true,
      snapSizes: const [.45, .72],
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(color: _bg, borderRadius: BorderRadius.vertical(top: Radius.circular(18)), boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 24)]),
        child: CustomScrollView(controller: scroll, slivers: [
          SliverToBoxAdapter(
            child: Column(children: [
              Container(width: 40, height: 5, margin: const EdgeInsets.only(top: 8, bottom: 6), decoration: BoxDecoration(color: const Color(0xFF555555), borderRadius: BorderRadius.circular(3))),
              if (_editing == null && _viewing == null) _tabs(),
            ]),
          ),
          if (_editing != null)
            SliverToBoxAdapter(child: _editor(_editing!))
          else if (_viewing != null)
            SliverToBoxAdapter(child: _viewer(_viewing!))
          else if (_err != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Text(_err!, style: const TextStyle(color: Colors.white70))))
          else
            SliverList.list(children: switch (_tab) { 0 => _mineList(), 1 => _publicList(), _ => _turns() }),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ]),
      ),
    );
  }

  Widget _tabs() {
    final q = (call.roomStage?['queue'] as List? ?? const []).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(children: [
        Expanded(
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(foregroundColor: Colors.white70, selectedForegroundColor: const Color(0xFF041E49), selectedBackgroundColor: _acc, visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(value: 0, label: Text(tr('Của tôi'))),
              ButtonSegment(value: 1, label: Text(tr('Công khai'))),
              ButtonSegment(value: 2, label: Text(q > 0 ? tr('Lượt ({0})', [q]) : tr('Lượt'))),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: _new, icon: const Icon(Icons.add_rounded), tooltip: tr('Trang mới')),
      ]),
    );
  }

  Widget _typeIcon(PageTypeSpec? s, [double size = 34]) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: (s?.color ?? Colors.grey).withValues(alpha: .25), borderRadius: BorderRadius.circular(9)),
        child: Icon(s?.icon ?? Icons.help_outline, color: s?.color ?? Colors.grey, size: size * .55),
      );

  bool get _myTurn => call.roomStage?['presenter'] == call.myId();
  bool get _canShow => _myTurn || call.canModerate || '${call.roomStage?['presenter'] ?? ''}'.isEmpty;

  Widget _pageTile(MeetPage p, {required bool mine}) {
    final s = pageTypeOf(p.type);
    final live = call.roomStage?['page'] == p.id;
    return ListTile(
      leading: _typeIcon(s),
      tileColor: live ? const Color(0xFF173431) : null,
      title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        [
          if (!mine) p.ownerName,
          s?.label ?? p.type,
          if (p.seconds > 0) fmtLeft(p.seconds * 1000),
          if (mine) p.public ? tr('công khai') : tr('riêng'),
          if (live) tr('đang chiếu'),
        ].join(' · '),
        style: const TextStyle(color: _sub, fontSize: 12),
      ),
      trailing: (mine || call.canModerate) && _canShow
          ? IconButton(
              tooltip: tr('Lên sân khấu'),
              icon: Icon(live ? Icons.cast_connected_rounded : Icons.play_circle_outline_rounded, color: _acc),
              onPressed: live ? null : () => _toast(call.stageAct('show', {'page': p.id})),
            )
          : null,
      onTap: () {
        setState(() => mine ? _editing = p.id : _viewing = p.id);
        _size(.72);
      },
    );
  }

  List<Widget> _mineList() => [
        if (_mine.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(tr('Chưa có trang nào. Bấm ＋ để chuẩn bị chào mừng, tài liệu, chương trình, biên bản…'), textAlign: TextAlign.center, style: const TextStyle(color: _sub)),
          ),
        if (_mine.length > 1)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (a, b) async {
              final l = [..._mine];
              l.insert(b, l.removeAt(a));
              setState(() => _mine = l);
              for (final (i, p) in l.indexed) {
                if (p.order != i) await api.patch(p.id, {'order': i}).catchError((_) => p);
              }
            },
            children: [for (final p in _mine) KeyedSubtree(key: ValueKey(p.id), child: _pageTile(p, mine: true))],
          )
        else
          for (final p in _mine) _pageTile(p, mine: true),
      ];

  List<Widget> _publicList() => [
        if (_public.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(tr('Chưa ai công khai trang nào.'), textAlign: TextAlign.center, style: const TextStyle(color: _sub))),
        for (final p in _public) _pageTile(p, mine: false),
      ];

  List<Widget> _turns() {
    final st = call.roomStage ?? const {};
    final pres = '${st['presenter'] ?? ''}';
    final queue = [for (final x in (st['queue'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final inQueue = queue.any((x) => x['id'] == call.myId());
    final host = call.canModerate;
    return [
      ListTile(
        leading: const Icon(Icons.co_present_outlined, color: Colors.white),
        title: Text(pres.isEmpty ? tr('Chưa ai trình chiếu') : tr('Đang trình chiếu: {0}', ['${st['presenter_name'] ?? ''}']), style: const TextStyle(color: Colors.white)),
        trailing: pres.isNotEmpty && (_myTurn || host) ? TextButton(onPressed: () => _toast(call.stageAct('release')), child: Text(_myTurn ? tr('Trả lượt') : tr('Kết thúc lượt'))) : null,
      ),
      if (!_myTurn)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton.tonal(
            onPressed: () => _toast(call.stageAct(inQueue ? 'cancel' : 'request')),
            child: Text(inQueue ? tr('Huỷ xin lượt') : pres.isEmpty ? tr('Trình chiếu') : tr('Xin lượt trình chiếu')),
          ),
        ),
      if (queue.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(tr('Hàng đợi'), style: const TextStyle(color: _sub))),
      for (final (i, q) in queue.indexed)
        ListTile(
          dense: true,
          leading: CircleAvatar(radius: 13, child: Text('${i + 1}')),
          title: Text('${q['name'] ?? ''}', style: const TextStyle(color: Colors.white)),
          trailing: host ? TextButton(onPressed: () => _toast(call.stageAct('grant', {'user': q['id']})), child: Text(tr('Trao lượt'))) : null,
        ),
      if (_myTurn || host) ...[
        const Divider(color: Colors.white12),
        ListTile(
          title: Text(tr('Chạy trang'), style: const TextStyle(color: Colors.white)),
          subtitle: Text(tr('Tự chạy: hết thời lượng của trang thì sang trang kế'), style: const TextStyle(color: _sub, fontSize: 12)),
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(foregroundColor: Colors.white70, selectedForegroundColor: const Color(0xFF041E49), selectedBackgroundColor: _acc, visualDensity: VisualDensity.compact),
            segments: [ButtonSegment(value: 'manual', label: Text(tr('Bấm tay'))), ButtonSegment(value: 'auto', label: Text(tr('Tự chạy')))],
            selected: {'${st['mode'] ?? 'manual'}'},
            onSelectionChanged: (s) => _toast(call.stageAct('mode', {'mode': s.first})),
          ),
        ),
      ],
      if (host) ...[
        SwitchListTile(
          value: st['locked'] == true,
          title: Text(tr('Chỉ chủ trì trao lượt'), style: const TextStyle(color: Colors.white)),
          subtitle: Text(tr('Tắt: ai cũng tự lên trình chiếu khi sân khấu trống'), style: const TextStyle(color: _sub, fontSize: 12)),
          onChanged: (v) => _toast(call.stageAct('lock', {'locked': v})),
        ),
        ListTile(
          title: Text(tr('Màn hình chờ'), style: const TextStyle(color: Colors.white)),
          subtitle: Text(tr('Hiện khi không ai trình chiếu'), style: const TextStyle(color: _sub, fontSize: 12)),
          trailing: DropdownButton<String>(
            dropdownColor: _card,
            value: [..._mine, ..._public].any((p) => p.id == st['idle_page']) ? '${st['idle_page']}' : '',
            items: [
              DropdownMenuItem(value: '', child: Text(tr('Không'), style: const TextStyle(color: Colors.white))),
              for (final p in [..._mine, ..._public].where((p) => p.type == 'welcome' || p.type == 'video'))
                DropdownMenuItem(value: p.id, child: Text(p.title, style: const TextStyle(color: Colors.white))),
            ],
            onChanged: (v) {
              final p = [..._mine, ..._public].where((x) => x.id == v).firstOrNull;
              _toast(call.stageAct('idle', p == null ? {'idle': ''} : {'idle': p.type, 'page': p.id}));
            },
          ),
        ),
      ],
    ];
  }

  Widget _back(String title, {List<Widget> actions = const []}) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () {
              setState(() => _editing = _viewing = null);
              _load();
              _size(.45);
            },
          ),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
          ...actions,
        ]),
      );

  Widget _viewer(String id) => PageHost(
        key: ValueKey('view:$id'),
        call: call,
        id: id,
        builder: (context, ctx, spec) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _back('${ctx.page.title} · ${ctx.page.ownerName}', actions: [
            if (call.canModerate && _canShow) IconButton(tooltip: tr('Lên sân khấu'), icon: const Icon(Icons.play_circle_outline_rounded, color: _acc), onPressed: () => _toast(call.stageAct('show', {'page': id}))),
          ]),
          SizedBox(height: MediaQuery.sizeOf(context).height * .5, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: spec == null ? unknownPageView(ctx) : spec.view(context, ctx))),
        ]),
      );

  Widget _editor(String id) => PageHost(
        key: ValueKey('edit:$id'),
        call: call,
        id: id,
        builder: (context, ctx, spec) => _Editor(ctx: ctx, spec: spec, back: _back, canShow: _canShow, onDeleted: () {
          setState(() => _editing = null);
          _load();
          _size(.45);
        }),
      );
}

class _Editor extends StatefulWidget {
  final PageCtx ctx;
  final PageTypeSpec? spec;
  final Widget Function(String title, {List<Widget> actions}) back;
  final bool canShow;
  final VoidCallback onDeleted;
  const _Editor({required this.ctx, required this.spec, required this.back, required this.canShow, required this.onDeleted});
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final _title = TextEditingController(text: widget.ctx.page.title);
  late int _seconds = widget.ctx.page.seconds;

  PageCtx get ctx => widget.ctx;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _patch(Map<String, dynamic> b) async {
    try {
      await ctx.api.patch(ctx.page.id, b);
      await ctx.reload();
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ctx.page;
    final owner = ctx.data.role == 'owner';
    final spec = widget.spec;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      widget.back(tr('Sửa: {0}', [p.title]), actions: [
        if (owner || ctx.data.role == 'manager')
          IconButton(
            tooltip: tr('Xoá trang'),
            icon: const Icon(Icons.delete_outline_rounded, color: _sub),
            onPressed: () async {
              try {
                await ctx.api.delete(p.id);
                widget.onDeleted();
              } catch (e) {
                if (context.mounted) meetToast(context, '$e');
              }
            },
          ),
      ]),
      // Xem trước như trên sân khấu.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: IgnorePointer(ignoring: p.type != 'minutes', child: spec == null ? unknownPageView(ctx) : spec.view(context, ctx))),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (owner) ...[
            Focus(
              onFocusChange: (f) {
                if (!f && _title.text.trim().isNotEmpty && _title.text.trim() != p.title) _patch({'title': _title.text.trim()});
              },
              child: TextField(controller: _title, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Tiêu đề'))),
            ),
            const SizedBox(height: 10),
            if (spec?.editor != null) spec!.editor!(context, ctx),
          ],
          Row(children: [
            Text(tr('Thời lượng (tự chạy)'), style: const TextStyle(color: Colors.white)),
            const Spacer(),
            DropdownButton<int>(
              dropdownColor: _card,
              value: const [0, 30, 60, 120, 180, 300, 600, 900, 1800].contains(_seconds) ? _seconds : 0,
              items: [
                for (final s in const [0, 30, 60, 120, 180, 300, 600, 900, 1800])
                  DropdownMenuItem(value: s, child: Text(s == 0 ? tr('Không giới hạn') : fmtLeft(s * 1000), style: const TextStyle(color: Colors.white))),
              ],
              onChanged: owner
                  ? (v) {
                      setState(() => _seconds = v ?? 0);
                      _patch({'seconds': v ?? 0});
                    }
                  : null,
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: p.public,
            title: Text(tr('Công khai trong cuộc họp'), style: const TextStyle(color: Colors.white)),
            subtitle: Text(tr('Mọi người xem được trang này bất cứ lúc nào'), style: const TextStyle(color: _sub, fontSize: 12)),
            onChanged: (v) => _patch({'visibility': v ? 'meeting' : 'private'}),
          ),
          const SizedBox(height: 8),
          if (widget.canShow)
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(tr('Lên sân khấu')),
              onPressed: () async {
                final e = await ctx.call.stageAct('show', {'page': p.id});
                if (e != null && context.mounted) meetToast(context, e);
              },
            ),
        ]),
      ),
    ]);
  }
}
