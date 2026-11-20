import 'dart:async';

import 'package:flutter/material.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../meet/meet_home.dart' show meetToast;
import 'page_types.dart';
import 'pages_api.dart';
import '../meet/meet_present.dart' show pickPresentPdf;
import 'pages_overview.dart';
import 'system_pages.dart';
import 'types/builtin.dart' show pageField;

// Họp (mới): bảng kéo lên (thấp: vẫn thấy sân khấu · vừa · cao hết; kéo xuống là đóng) với "▦ Tất cả" (mỗi người một
// hàng trang, pages_overview.dart) và "Lượt trình chiếu"; soạn trang và xem trang người khác ngay trong bảng.
// Cùng file: khung sân khấu hiện trang đang chiếu.

const _bg = Color(0xFF23262C);
const _card = Color(0xFF2D3036);
const _sub = Color(0xFF9AA0A6);
const _acc = Color(0xFF8AB4F8);

/// Sân khấu đang hiện một trang (không phải tài liệu: tài liệu đi qua khung trình chiếu có sẵn).
bool stageShowsPage(CallService call) {
  final st = call.roomStage;
  if (st == null) return false;
  final page = '${st['page'] ?? ''}';
  // Trang hệ thống: bố cục video là của màn họp; chỉ "Chờ lượt trình chiếu" là một ô trên sân khấu.
  if (page.startsWith('sys:')) return page == 'sys:handover';
  if (page.isNotEmpty) return st['page_type'] != 'doc' || call.roomPresent?['page_id'] != st['page'];
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
    if (id == 'sys:handover') {
      final mine = st['presenter'] == call.myId();
      return Stack(children: [
        Positioned.fill(child: HandoverView(stage: st)),
        // Người được mời trình bày: bắt đầu ngay (trang đầu của mình); chủ trì chỉnh màn hình chờ.
        if (!widget.compact && (mine || call.canModerate))
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (call.canModerate)
                IconButton.filledTonal(
                  tooltip: tr('Chỉnh màn hình chờ lượt'),
                  onPressed: () => showHandoverEditor(context, call),
                  icon: const Icon(Icons.tune_rounded),
                ),
              const SizedBox(width: 8),
              if (mine) FilledButton.icon(onPressed: () => call.stageAct('next'), icon: const Icon(Icons.play_arrow_rounded), label: Text(tr('Bắt đầu trình bày'))),
            ]),
          ),
      ]);
    }
    final mine = st['presenter'] == call.myId();
    final control = shown.isNotEmpty && (mine || call.canModerate);
    final ends = (st['ends_at'] as num?)?.toInt() ?? 0;
    final left = ends == 0 ? 0 : ends - DateTime.now().millisecondsSinceEpoch;
    return LayoutBuilder(builder: (context, box) => _build(context, box.maxWidth < 560, st, shown, id, key, control, left));
  }

  Widget _build(BuildContext context, bool narrow, Map st, String shown, String id, String key, bool control, int left) {
    final call = widget.call;
    return Stack(children: [
      Positioned.fill(
        child: PageHost(
          key: ValueKey('stage:$id'),
          call: call,
          id: id,
          stageKey: key.isEmpty ? null : key,
          onStage: true,
          // Khung sân khấu quá hẹp (cửa sổ nhỏ, cột bên phải đang mở): dựng ở 360 px rồi thu nhỏ cho vừa, không tràn.
          builder: (context, ctx, spec) => LayoutBuilder(builder: (context, box) {
            final view = spec == null ? unknownPageView(ctx) : spec.view(context, ctx);
            if (box.maxWidth >= 360 || !box.maxHeight.isFinite || box.maxWidth <= 0) return view;
            return FittedBox(fit: BoxFit.contain, child: SizedBox(width: 360, height: 360 * box.maxHeight / box.maxWidth, child: view));
          }),
        ),
      ),
      // Một dải ở góc phải: ai đang chiếu, thời gian còn lại, nút điều khiển (người trình chiếu / chủ trì); không đè lên nội dung trang.
      if (shown.isNotEmpty && !widget.compact)
        Positioned(
          right: 8,
          top: 8,
          // Khung hẹp: chỉ nút điều khiển (chữ "Đang chiếu…" che mất tiêu đề trang).
          child: Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (!narrow || !control) ConstrainedBox(
                constraints: BoxConstraints(maxWidth: narrow ? 160 : 260),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: control ? 0 : 6).copyWith(right: control ? 4 : 12),
                  child: Text(
                    [tr('Đang chiếu: {0}', ['${st['presenter_name'] ?? ''}']), if (left > 0) tr('còn {0}', [fmtLeft(left)]), if (st['paused'] == true) tr('tạm dừng')].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
              if (control) ...[
                _btn(Icons.skip_previous_rounded, () => call.stageAct('prev')),
                if (st['mode'] == 'auto')
                  _btn(st['paused'] == true ? Icons.play_arrow_rounded : Icons.pause_rounded, () => call.stageAct(st['paused'] == true ? 'resume' : 'pause')),
                _btn(Icons.skip_next_rounded, () => call.stageAct('next')),
                _btn(Icons.stop_rounded, () => call.stageAct('end')),
                // Kết thúc lượt của mình (chủ trì: của người đang trình chiếu); tới lượt người kế tiếp.
                _btn(Icons.logout_rounded, () => call.stageAct('release')),
              ],
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

/// Mở bảng kéo lên Trang họp. [edit]: mở thẳng trình soạn trang đó; [create]: mở ngay bảng chọn loại trang mới.
Future<void> showPagesSheet(BuildContext context, CallService call, {String? edit, bool create = false, List<PageApp> apps = const []}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black26,
      builder: (ctx) => PagesPane(call: call, edit: edit, create: create, apps: apps),
    );

/// Một app của màn họp đặt trong ô Apps (vd. Bảng trắng): không phải loại trang, chỉ mở chức năng có sẵn.
class PageApp {
  final String id, label, desc;
  final IconData icon;
  final Color color;
  final Future<void> Function(BuildContext context, CallService call) run;
  const PageApp({required this.id, required this.label, this.desc = '', required this.icon, required this.color, required this.run});
}

/// Nội dung Trang họp: tab Tất cả / Lượt, xem trang, soạn trang. Điện thoại: trong bảng kéo lên ([panel] = false);
/// máy tính: trong panel bên phải của cuộc họp ([panel] = true).
class PagesPane extends StatefulWidget {
  final CallService call;
  final String? edit;
  final bool create;
  final bool panel;
  /// App của màn họp trong ô Apps (bảng trắng…).
  final List<PageApp> apps;
  /// Trình chiếu màn hình của mình (máy tính); null = không có (điện thoại).
  final Future<void> Function()? shareScreen;
  const PagesPane({super.key, required this.call, this.edit, this.create = false, this.panel = false, this.apps = const [], this.shareScreen});
  @override
  State<PagesPane> createState() => _PagesPaneState();
}

class _PagesPaneState extends State<PagesPane> {
  late final api = PagesApi(widget.call);
  final _sheet = DraggableScrollableController();
  List<MeetPage> _mine = const [];
  String? _err;
  String? _editing; // id trang đang soạn
  String? _viewing; // id trang công khai đang xem
  StreamSubscription? _fx;

  CallService get call => widget.call;

  @override
  void initState() {
    super.initState();
    _editing = widget.edit;
    _load();
    if (widget.create) WidgetsBinding.instance.addPostFrameCallback((_) => _new());
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
      final r = await Future.wait([api.list('mine')]);
      if (mounted) {
        setState(() {
          _mine = r[0];
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

  /// Ô "Apps": Trình chiếu (màn hình / tài liệu), app của màn họp (bảng trắng…) và mọi loại trang.
  Future<void> _new() async {
    Widget tile(BuildContext ctx, Object v, IconData icon, Color color, String label, String desc) => SizedBox(
          width: 168,
          child: Material(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx, v),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: color.withValues(alpha: .25), borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, color: color, size: 19),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      if (desc.isNotEmpty) Text(desc, maxLines: 2, style: const TextStyle(color: _sub, fontSize: 11)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
    final pick = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: _bg,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: Text(tr('Apps'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              tile(ctx, 'present', Icons.present_to_all_rounded, const Color(0xFFF29900), tr('Trình chiếu'), tr('Màn hình của bạn, hoặc tài liệu')),
              for (final a in widget.apps) tile(ctx, a, a.icon, a.color, a.label, a.desc),
              for (final s in pageTypes)
                if (s.type != 'doc') tile(ctx, s, s.icon, s.color, s.label, s.desc),
            ]),
          ]),
        ),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick is PageApp) return pick.run(context, call);
    if (pick == 'present') return _present();
    final spec = pick as PageTypeSpec;
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

  /// App "Trình chiếu": màn hình của mình (máy tính) hoặc tài liệu (thành trang Tài liệu rồi lên sân khấu).
  Future<void> _present() async {
    final screen = widget.shareScreen;
    final src = screen == null
        ? 'doc'
        : await showModalBottomSheet<String>(
            context: context,
            backgroundColor: _bg,
            constraints: const BoxConstraints(maxWidth: 520),
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 6), child: Text(tr('Trình chiếu'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700))),
                ListTile(
                  leading: const Icon(Icons.desktop_windows_outlined, color: Colors.white),
                  title: Text(tr('Màn hình của tôi'), style: const TextStyle(color: Colors.white)),
                  subtitle: Text(tr('Chia sẻ cả màn hình hoặc một cửa sổ'), style: const TextStyle(color: _sub)),
                  onTap: () => Navigator.pop(ctx, 'screen'),
                ),
                ListTile(
                  leading: const Icon(Icons.slideshow_rounded, color: Colors.white),
                  title: Text(tr('Tài liệu'), style: const TextStyle(color: Colors.white)),
                  subtitle: Text(tr('PowerPoint, PDF, Word, Excel: mọi người xem cùng trang'), style: const TextStyle(color: _sub)),
                  onTap: () => Navigator.pop(ctx, 'doc'),
                ),
                const SizedBox(height: 8),
              ]),
            ),
          );
    if (src == null || !mounted) return;
    if (src == 'screen') return screen!();
    try {
      final r = await pickPresentPdf(context, call);
      if (r == null || !mounted) return;
      final name = r.$2.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '');
      final d = await api.create(type: 'doc', title: name.isEmpty ? tr('Tài liệu') : name);
      await api.upload(d.page.id, r.$1, r.$2, r.$3);
      await _load();
      if (_canShow) await _toast(call.stageAct('show', {'page': d.page.id}));
      if (mounted) meetToast(context, _canShow ? tr('Đang trình chiếu {0}', [r.$2]) : tr('Đã thêm "{0}" vào trang của bạn', [r.$2]));
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.panel) return CustomScrollView(slivers: [const SliverToBoxAdapter(child: SizedBox(height: 10)), ..._slivers()]);
    return DraggableScrollableSheet(
      controller: _sheet,
      initialChildSize: widget.edit != null ? .72 : .45,
      minChildSize: .2,
      maxChildSize: 1,
      snap: true,
      snapSizes: const [.45, .72],
      builder: (context, scroll) => Material(
        color: _bg,
        elevation: 16,
        shadowColor: Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: CustomScrollView(controller: scroll, slivers: [
          SliverToBoxAdapter(
            child: Container(width: 40, height: 5, margin: const EdgeInsets.only(top: 8, bottom: 6), decoration: BoxDecoration(color: const Color(0xFF555555), borderRadius: BorderRadius.circular(3))),
          ),
          ..._slivers(),
        ]),
      ),
    );
  }

  List<Widget> _slivers() => [
        if (_editing == null && _viewing == null) SliverToBoxAdapter(child: _tabs()),
        if (_editing != null)
          SliverToBoxAdapter(child: _editor(_editing!))
        else if (_viewing != null)
          SliverToBoxAdapter(child: _viewer(_viewing!))
        else if (_err != null)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Text(_err!, style: const TextStyle(color: Colors.white70))))
        else
          SliverToBoxAdapter(
            child: PagesOverview(
              call: call,
              onView: (id) {
                setState(() => _mine.any((p) => p.id == id) ? _editing = id : _viewing = id);
                _size(.72);
              },
              onEdit: (id) {
                setState(() => _editing = id);
                _size(.72);
              },
              onNew: _new,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ];

  /// Đầu danh sách (Sếp: không còn tab / bộ lọc): dải "Lượt" gọn (ai đang chiếu, hàng đợi, xin / trả lượt, ⚙ chỉnh lượt)
  /// và nút ＋ (Apps: thêm trang, trình chiếu).
  Widget _tabs() => Padding(
        // Đầu danh sách: chỉ nút ＋ (Apps). Lượt trình chiếu hiện trên sân khấu (Chờ lượt, "Đang chiếu…"); chủ trì trao lượt
        // ở hàng của từng người, người khác xin lượt bằng menu thẻ trang ("Xin lượt và chiếu").
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
        child: Row(children: [
          const Spacer(),
          IconButton.filled(onPressed: _new, icon: const Icon(Icons.add_rounded), tooltip: tr('Apps: thêm trang, trình chiếu')),
        ]),
      );

  bool get _myTurn => call.roomStage?['presenter'] == call.myId();
  bool get _canShow => _myTurn || call.canModerate || '${call.roomStage?['presenter'] ?? ''}'.isEmpty;

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // Khung cao để trả lời / đọc (bình chọn, hỏi đáp), cả bảng kéo lên lẫn panel máy tính.
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .55,
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: spec == null ? unknownPageView(ctx) : spec.view(context, ctx)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                  call.roomStage?['page'] == id
                      ? tr('Trang này đang trên sân khấu.')
                      : tr('Bạn đang xem riêng trang này. Sân khấu vẫn chạy "{0}".', ['${call.roomStage?['page_title'] ?? ''}'.isEmpty ? tr('màn hình chờ') : call.roomStage!['page_title']]),
                  style: const TextStyle(color: _sub, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                // Panel máy tính: sân khấu vẫn ở bên trái, chỉ quay lại danh sách; điện thoại: đóng bảng.
                onPressed: () => widget.panel ? setState(() => _viewing = null) : Navigator.pop(context),
                child: Text(tr('Về sân khấu')),
              ),
            ]),
          ),
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
