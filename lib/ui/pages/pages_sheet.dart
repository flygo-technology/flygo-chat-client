import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../calls/call_service.dart';
import '../../i18n/i18n.dart';
import '../meet/meet_home.dart' show meetToast;
import 'page_types.dart';
import 'pages_api.dart';
import '../meet/meet_present.dart' show pickPresentPdf;
import 'pages_overview.dart';
import 'stage_frame.dart';
import 'system_pages.dart';
import 'types/builtin.dart' show pageField;

// Họp (mới): bảng kéo lên (thấp: vẫn thấy sân khấu · vừa · cao hết; kéo xuống là đóng) với "▦ Tất cả" (mỗi người một
// hàng trang, pages_overview.dart) và "Lượt trình chiếu"; soạn trang và xem trang người khác ngay trong bảng.
// Cùng file: khung sân khấu hiện trang đang chiếu.

const _bg = Color(0xFF23262C);
const _card = Color(0xFF2D3036);
const _sub = Color(0xFF9AA0A6);

/// Sân khấu đang hiện một trang (không phải tài liệu: tài liệu đi qua khung trình chiếu có sẵn).
bool stageShowsPage(CallService call) {
  final st = call.roomStage;
  if (st == null) return false;
  final page = '${st['page'] ?? ''}';
  // Trang hệ thống: bố cục video là của màn họp; chỉ "Chờ lượt trình chiếu" là một ô trên sân khấu.
  if (page.startsWith('sys:')) return sysStagePages.contains(page);
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
    if (sysStagePages.contains(id)) return _sysFramed(context, id, st);
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
          // Khung sân khấu chung (stage_frame.dart): thanh đầu loại trang / người trình bày / nút điều khiển, thanh cuối giờ.
          builder: (context, ctx, spec) => _framed(context, ctx, spec, st, shown, control, left),
        ),
      ),
    ]);
  }

  /// Trang hệ thống (Chào mừng, Nội dung, Chờ lượt) trong khung chung: thanh đầu chip loại trang + nút soạn (chủ trì),
  /// thanh cuối cách vào họp / chuyển phần / bắt đầu trình bày.
  Widget _sysFramed(BuildContext context, String id, Map st) {
    final call = widget.call;
    final cfg = (st['theme_cfg'] as Map?) ?? const {};
    final t = StageTheme.of(cfg);
    final sys = sysPages.firstWhere((p) => p.id == id);
    final edit = widget.compact || !call.canModerate ? null : sysPageEditor(context, call, id);
    final code = call.meetingInfo?.code ?? '';
    final mine = st['presenter'] == call.myId();
    final Widget child;
    List<Widget> footer = const [];
    var bleed = true;
    switch (id) {
      case 'sys:welcome':
        final spec = pageTypeOf('welcome');
        child = spec == null ? const SizedBox.shrink() : spec.view(context, sysWelcomeCtx(call, (st['welcome_cfg'] as Map?) ?? const {}));
        if (code.isNotEmpty) footer = [StagePill(tr('Vào họp: mở app Flygo hoặc quét mã trên TV · mã {0}', [code]), theme: t, accent: true)];
      case 'sys:program':
        final pc = (st['program_cfg'] as Map?) ?? const {};
        child = ProgramView(call: call, cfg: pc, controls: !widget.compact);
        bleed = false;
        if (!widget.compact) footer = programFooter(context, call, pc, t);
      default:
        child = HandoverView(stage: st);
        footer = [
          if (!widget.compact && mine) ...[
            const Spacer(),
            FilledButton.icon(onPressed: () => call.stageAct('next'), icon: const Icon(Icons.play_arrow_rounded), label: Text(tr('Bắt đầu trình bày'))),
          ],
        ];
    }
    final bg = '${cfg['bg'] ?? ''}', img = '${cfg['bg_image'] ?? ''}';
    return StageFrame(
      theme: t,
      bleed: bleed,
      background: bleed || (bg.isEmpty && img.isEmpty) ? null : stageBackground(bg, img, t),
      headerLeading: [
        StageTypeChip(icon: sys.icon, label: sys.label, theme: t),
        Flexible(child: Text('${st['meeting_title'] ?? call.meetingInfo?.title ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.sub, fontSize: 15))),
      ],
      headerTrailing: [
        if (edit != null)
          IconButton.filledTonal(tooltip: tr('Soạn trang này'), onPressed: edit, icon: const Icon(Icons.tune_rounded)),
      ],
      footer: footer,
      child: child,
    );
  }

  /// Loại trang có người xem trả lời trên app: thanh cuối nhắc cách tham gia.
  static const _interactive = {'poll', 'qa', 'notes', 'draw', 'discuss'};

  Widget _framed(BuildContext context, PageCtx ctx, PageTypeSpec? spec, Map st, String shown, bool control, int left) {
    final call = widget.call;
    final cfg = (st['theme_cfg'] as Map?) ?? const {};
    final t = StageTheme.of(cfg);
    final bg = '${cfg['bg'] ?? ''}', img = '${cfg['bg_image'] ?? ''}';
    var view = spec == null ? unknownPageView(ctx) : spec.view(context, ctx);
    // Trang chưa theo bảng màu sân khấu (chữ trắng): ở chế độ Sáng đặt trong một ô tối cho đọc được.
    if (t.light && !(spec?.stageThemed ?? false) && !(spec?.stageBleed ?? false)) {
      view = Container(
        decoration: BoxDecoration(color: const Color(0xFF171B22), borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: view,
      );
    }
    final code = call.meetingInfo?.code ?? '';
    final presenter = '${st['presenter_name'] ?? ''}';
    return StageFrame(
      theme: t,
      bleed: spec?.stageBleed ?? false,
      background: bg.isEmpty && img.isEmpty ? null : stageBackground(bg, img, t),
      headerLeading: [
        // Nhãn ngắn: "Bình chọn / Trắc nghiệm" -> "Bình chọn".
        StageTypeChip(icon: spec?.icon ?? Icons.article_outlined, label: spec?.stageLabel?.call(ctx) ?? (spec?.label ?? tr('Trang')).split(RegExp(r' [/&] ')).first, theme: t),
        Flexible(child: Text(ctx.page.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.sub, fontSize: 15))),
      ],
      headerTrailing: [
        if (shown.isNotEmpty && presenter.isNotEmpty)
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 380), child: StagePresenterChip(name: presenter, note: st['paused'] == true ? tr('tạm dừng') : tr('đang trình bày'), theme: t)),
        if (control && !widget.compact)
          Container(
            height: 40,
            decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _btn(Icons.skip_previous_rounded, () => call.stageAct('prev'), t.text),
              if (st['mode'] == 'auto')
                _btn(st['paused'] == true ? Icons.play_arrow_rounded : Icons.pause_rounded, () => call.stageAct(st['paused'] == true ? 'resume' : 'pause'), t.text),
              _btn(Icons.skip_next_rounded, () => call.stageAct('next'), t.text),
              _btn(Icons.stop_rounded, () => call.stageAct('end'), t.text),
              // Kết thúc lượt của mình (chủ trì: của người đang trình chiếu); tới lượt người kế tiếp.
              _btn(Icons.logout_rounded, () => call.stageAct('release'), t.text),
            ]),
          ),
      ],
      footer: spec?.stageFooter?.call(context, ctx) ??
          [
            if (_interactive.contains(ctx.page.type) && code.isNotEmpty) StagePill(tr('Trả lời trên app Flygo · mã {0}', [code]), theme: t, accent: true),
            if (left > 0) ...[const Spacer(), StagePill(fmtLeft(left), icon: Icons.timer_outlined, theme: t)],
          ],
      child: view,
    );
  }

  Widget _btn(IconData i, Future<String?> Function() f, [Color? color]) => IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(i, color: color ?? Colors.white, size: 20),
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

  /// Ô "Apps": lưới cân đối theo nhóm (Trình bày / Tương tác / Ghi chép), thẻ cao bằng nhau, tên ngắn một dòng, mô tả hai dòng.
  Future<void> _new() async {
    // Tên ngắn trên thẻ (tên đầy đủ trong mô tả / tooltip).
    const short = {'poll': 'Bình chọn', 'qa': 'Hỏi đáp', 'discuss': 'Thảo luận', 'agenda': 'Chương trình', 'minutes': 'Biên bản', 'welcome': 'Chào mừng', 'video': 'Video', 'show': 'Show'};
    // Loại trang chưa có ở đây (Bấm giờ, Bốc thăm…) vào nhóm Tương tác; tên ghi chú vào nhóm Ghi chép.
    const group = {'video': 0, 'show': 0, 'welcome': 0, 'poll': 1, 'qa': 1, 'discuss': 1, 'agenda': 2, 'minutes': 2, 'note': 2, 'notes': 2};
    final items = <(int, Object, IconData, Color, String, String)>[
      (0, 'present', Icons.present_to_all_rounded, const Color(0xFFF29900), tr('Trình chiếu'), tr('Màn hình của bạn hoặc tài liệu')),
      // Website (cả phòng cùng xem, cùng bấm) và Bảng trắng ở nhóm Tương tác.
      for (final a in widget.apps) (a.id == 'board' || a.id == 'web' ? 1 : 0, a, a.icon, a.color, a.label, a.desc),
      for (final t in pageTypes)
        if (t.type != 'doc' && !t.hidden) (group[t.type] ?? 1, t, t.icon, t.color, tr(short[t.type] ?? t.label), t.desc.isEmpty ? t.label : t.desc),
    ];
    // Ô gọn: biểu tượng trên, tên ngắn một dòng dưới; mô tả ở tooltip (di chuột / nhấn giữ).
    Widget tile(BuildContext ctx, (int, Object, IconData, Color, String, String) it) => Tooltip(
          message: '${it.$5}: ${it.$6}',
          triggerMode: TooltipTriggerMode.longPress,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx, it.$2),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: it.$4.withValues(alpha: .22), borderRadius: BorderRadius.circular(14)),
                    child: Icon(it.$3, color: it.$4, size: 24),
                  ),
                  const SizedBox(height: 6),
                  // Tên dài (Chương trình, Trình chiếu) thu nhỏ cho vừa ô thay vì cắt.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(it.$5, maxLines: 1, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 12.5)),
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
      constraints: const BoxConstraints(maxWidth: 780),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: LayoutBuilder(builder: (ctx, box) {
          // 5 ô mỗi hàng (điện thoại, panel máy tính); rộng hơn thì thêm cột (ô ~120px).
          final cols = (box.maxWidth / 120).floor().clamp(5, 8);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Apps'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              for (final (g, title) in [(0, tr('Trình bày')), (1, tr('Tương tác')), (2, tr('Ghi chép'))])
                if (items.any((x) => x.$1 == g)) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 8), child: Text(title.toUpperCase(), style: const TextStyle(color: _sub, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .5))),
                  GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    mainAxisExtent: 88,
                    children: [for (final it in items.where((x) => x.$1 == g)) tile(ctx, it)],
                  ),
                ],
            ]),
          );
        }),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick is PageApp) return pick.run(context, call);
    if (pick == 'present') return _present();
    final spec = pick as PageTypeSpec;
    try {
      // Bước cấu hình của loại trang (bình chọn, hỏi đáp, bấm giờ…) mở trong khung trang, không phủ cả màn họp.
      final inner = _inner != null && _inner!.mounted ? _inner! : context;
      // ignore: use_build_context_synchronously
      final d = spec.create == null ? PageDraft(title: spec.label) : await spec.create!(inner, call);
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

  /// Context bên trong khung trang: hộp chọn / soạn (Apps, cấu hình bình chọn, hỏi đáp…) mở ngay trong khung (cột phải
  /// máy tính, bảng kéo lên điện thoại), không phủ cả màn họp (Sếp: cấu hình ngay trên trang).
  BuildContext? _inner;

  /// Khung trang có một lớp Navigator riêng (trong suốt, nằm trên nội dung): bảng / hộp mở bằng [_inner] nằm gọn trong
  /// khung. Nội dung khung vẫn dựng bình thường (không nằm trong route, nên luôn cập nhật).
  Widget _inPane(Widget child) => Stack(children: [
        Positioned.fill(child: child),
        Positioned.fill(
          // Không có hộp nào đang mở: lớp này không nhận chạm (route nền có tấm chắn vô hình).
          child: ValueListenableBuilder<int>(
            valueListenable: _paneObs.depth,
            builder: (_, d, nav) => IgnorePointer(ignoring: d <= 1, child: nav),
            child: Navigator(
            observers: [_paneObs],
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              opaque: false,
              pageBuilder: (context, _, _) => Builder(builder: (context) {
                _inner = context;
                return const SizedBox.shrink();
              }),
            ),
          ),
          ),
        ),
      ]);
  final _paneObs = _DepthObserver();

  @override
  Widget build(BuildContext context) {
    if (widget.panel) return _inPane(CustomScrollView(slivers: [const SliverToBoxAdapter(child: SizedBox(height: 10)), ..._slivers()]));
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
        child: _inPane(CustomScrollView(controller: scroll, slivers: [
          SliverToBoxAdapter(
            child: Container(width: 40, height: 5, margin: const EdgeInsets.only(top: 8, bottom: 6), decoration: BoxDecoration(color: const Color(0xFF555555), borderRadius: BorderRadius.circular(3))),
          ),
          ..._slivers(),
        ])),
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

  void _editPage(String id) => setState(() {
        _viewing = null;
        _editing = id;
      });

  Widget _viewer(String id) => PageHost(
        key: ValueKey('view:$id'),
        call: call,
        id: id,
        builder: (context, ctx, spec) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _back('${ctx.page.title} · ${ctx.page.ownerName}', actions: [
            // Trang đang trên sân khấu: nhãn LIVE đỏ nhấp nháy.
            if ((call.roomStage ?? const {})['page'] == id) const Padding(padding: EdgeInsets.only(right: 4), child: LiveBadge(size: 11)),
            if (ctx.page.owner == call.myId() || call.canModerate)
              Builder(
                builder: (btn) => IconButton(
                  tooltip: tr('Sửa, chiếu, công khai, xoá'),
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  onPressed: () => showPageMenu(btn, call, ctx.page, onEdit: () => _editPage(id), reload: _load),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // Khung cao để trả lời / đọc (bình chọn, hỏi đáp), cả bảng kéo lên lẫn panel máy tính. Bấm để tương tác; nhấn giữ /
            // chuột phải là menu của trang (như thẻ trang).
            child: GestureDetector(
              // Menu nổi tại chỗ nhấn.
              onLongPressStart: (d) => showPageMenu(context, call, ctx.page, onEdit: () => _editPage(id), reload: _load, anchor: d.globalPosition & const Size(1, 1)),
              onSecondaryTapDown: (d) => showPageMenu(context, call, ctx.page, onEdit: () => _editPage(id), reload: _load, anchor: d.globalPosition & const Size(1, 1)),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .55,
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: spec == null ? unknownPageView(ctx) : spec.view(context, ctx)),
              ),
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

  /// Hình của trang trên sân khấu, trong khung chung (giống StagePageView, không có nút điều khiển).
  Widget _stagePreview(BuildContext context, PageTypeSpec? spec) {
    final st = ctx.call.roomStage ?? const {};
    final cfg = (st['theme_cfg'] as Map?) ?? const {};
    final t = StageTheme.of(cfg);
    final sctx = PageCtx(data: ctx.data, api: ctx.api, call: ctx.call, presenting: false, onStage: true, act: ctx.act, reload: ctx.reload);
    final bg = '${cfg['bg'] ?? ''}', img = '${cfg['bg_image'] ?? ''}';
    return StageFrame(
      theme: t,
      bleed: spec?.stageBleed ?? false,
      background: bg.isEmpty && img.isEmpty ? null : stageBackground(bg, img, t),
      headerLeading: [StageTypeChip(icon: spec?.icon ?? Icons.article_outlined, label: spec?.stageLabel?.call(sctx) ?? (spec?.label ?? tr('Trang')).split(RegExp(r' [/&] ')).first, theme: t)],
      child: spec == null ? unknownPageView(sctx) : spec.view(context, sctx),
    );
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
      // Xem trước đúng như trên sân khấu / TV (khung chung, bảng màu sân khấu).
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: IgnorePointer(child: _stagePreview(context, spec))),
        ),
      ),
      // Điều khiển của trang ngay trên trang (Sếp: không mở hộp riêng): loại trang không có trình soạn nội dung thì phần
      // tương tác / điều khiển của nó (thêm ghi chú, bấm giờ, bốc thăm, câu hỏi…) nằm đây, đủ cao để dùng.
      if (spec != null && spec.editor == null && const {'poll', 'qa', 'timer', 'draw', 'notes', 'minutes', 'show'}.contains(p.type))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            height: math.min(560, MediaQuery.sizeOf(context).height * .62),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: spec.view(context, ctx),
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


/// Đếm số route trong Navigator của khung trang (1 = chỉ route nền, không có hộp nào mở).
class _DepthObserver extends NavigatorObserver {
  final depth = ValueNotifier<int>(0);
  int _n = 0;
  // Cập nhật sau khung hình: route nền được đẩy ngay lúc Navigator đang dựng.
  void _set(int d) {
    _n += d;
    WidgetsBinding.instance.addPostFrameCallback((_) => depth.value = _n);
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(1);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(-1);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(-1);
}
