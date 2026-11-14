import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../api/flows_live.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen, kFlowOrange, kFlowRed;
import 'flow_icon_picker.dart' show flowIconView;
import 'flow_logic.dart' show vnNumber, vnDecimal;
import 'flow_nav.dart';
import 'flows_page.dart' show FlowProgressBar;
import 'process_chat.dart' show ProcessUnreadBadge;
import 'process_detail.dart';
import 'process_report.dart';

/// Mục "Tiến trình" của trang Quy trình: các đối tượng nghiệp vụ (vd mỗi hoá đơn) do quy trình tạo và cập nhật.
/// 3 tab Đang chạy / Lỗi / Đã xong, lọc theo quy trình, nhãn, bước, ô tìm; đang hiện thì 5 giây làm mới một lần.

const kProcessBlue = Color(0xFF2F7DE1);
const kProcessGray = Color(0xFF8A8F98);

/// Màu theo `tone` của tiến trình (gray / blue / green / orange / red).
Color processToneColor(String tone, [Color? fallback]) => switch (tone) {
      'green' => kFlowGreen,
      'red' => kFlowRed,
      'orange' => kFlowOrange,
      'blue' => kProcessBlue,
      'gray' => kProcessGray,
      _ => fallback ?? kProcessGray,
    };

/// Màu theo `state` của tiến trình.
Color processStateColor(String state) => switch (state) {
      'done' => kFlowGreen,
      'failed' => kFlowRed,
      'cancelled' || 'skipped' => kProcessGray,
      _ => kProcessBlue,
    };

String processStateLabel(String state) => switch (state) {
      'running' => tr('Đang chạy'),
      'failed' => tr('Lỗi'),
      'done' => tr('Hoàn thành'),
      'cancelled' => tr('Đã huỷ'),
      'skipped' => tr('Bỏ qua'),
      _ => state,
    };

/// Giá trị thống kê: số thì định dạng kiểu Việt Nam ("1.250.000"), chữ giữ nguyên.
String processStatValue(Object? v) {
  if (v is num) return v == v.roundToDouble() ? vnNumber(v) : vnDecimal(v);
  return v == null ? '' : '$v';
}

/// Nhãn màu nhỏ (trạng thái, tone).
class ProcessChip extends StatelessWidget {
  final String text;
  final Color color;
  final bool solid;
  const ProcessChip({super.key, required this.text, required this.color, this.solid = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
        decoration: BoxDecoration(color: solid ? color : color.withValues(alpha: .13), borderRadius: BorderRadius.circular(10)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: solid ? Colors.white : color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

/// Nhãn tự do của tiến trình (KLTM, Nghi trùng…).
class ProcessLabel extends StatelessWidget {
  final String text;
  const ProcessLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: pal.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.sell_outlined, size: 11, color: pal.sub),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11.5, color: pal.text)),
      ]),
    );
  }
}

/// Chữ trùng ý với tên bước (vd "Chờ ký" và "Đã tạo nháp, chờ kế toán ký" thì không; "Chờ ký" và "chờ ký" thì có).
bool sameAsStep(String text, String step) {
  String n(String x) => x.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
  final a = n(text), b = n(step);
  return a.isNotEmpty && b.isNotEmpty && (a == b || a.contains(b) && a.length <= b.length + 6 || b.contains(a));
}

/// Nhãn trạng thái chỉ để cảnh báo (Sếp, 11/11): lỗi, quá hạn, màu cam / đỏ. Trạng thái thường (xanh, xám) không hiện ở
/// danh sách; chữ trùng tên bước hiện tại cũng bỏ. Trả về (chữ, màu) hoặc null.
(String, Color)? processWarning(FlowProcess p) {
  final step = p.currentStepTitle;
  if (p.state == 'failed') {
    final t = p.statusText.isNotEmpty && !sameAsStep(p.statusText, step) ? p.statusText : processStateLabel('failed');
    return (t, kFlowRed);
  }
  // Chữ báo lỗi luôn đỏ (dữ liệu cũ: nhãn "Lỗi ở bước …" còn sót với màu xanh sau khi chạy tiếp).
  if (p.statusText.startsWith('Lỗi')) return (p.statusText, kFlowRed);
  if (p.tone == 'red' || p.tone == 'orange') {
    if (p.statusText.isEmpty || sameAsStep(p.statusText, step)) return null;
    return (p.statusText, processToneColor(p.tone));
  }
  return null;
}

/// Thanh tiến độ theo bước: bước xong / bỏ qua tô xanh, bước đang làm tô xanh dương, bước lỗi tô đỏ, còn lại xám.
/// Tiến trình đã xong thì cả thanh xanh.
class ProcessStepsBar extends StatelessWidget {
  final FlowProcess process;
  const ProcessStepsBar(this.process, {super.key});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final steps = process.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final failed = process.state == 'failed';
    Color color(Map<String, dynamic> st) {
      final s = '${st['state'] ?? ''}';
      if (process.state == 'done' || s == 'done' || s == 'skipped') return kFlowGreen;
      if (s == 'failed' || failed && '${st['key']}' == process.currentStep) return kFlowRed;
      if (s == 'active') return kProcessBlue;
      return pal.divider;
    }

    final done = process.state == 'done' ? steps.length : steps.where((st) => const {'done', 'skipped'}.contains('${st['state']}')).length;
    return Tooltip(
      message: tr('{0}/{1} bước', [done, steps.length]),
      child: Row(key: const ValueKey('process-steps-bar'), children: [
        for (final (i, st) in steps.indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(child: Container(height: 4, decoration: BoxDecoration(color: color(st), borderRadius: BorderRadius.circular(2)))),
        ],
        const SizedBox(width: 8),
        Text('$done/${steps.length}', style: TextStyle(fontSize: 11, color: pal.sub, fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

/// Ô icon của tiến trình (emoji của tiến trình, không có thì của quy trình).
Widget processIconBox(Pal pal, FlowProcess p, {double size = 40}) {
  final icon = p.icon.isNotEmpty ? p.icon : (p.flowIcon.isNotEmpty ? p.flowIcon : '📦');
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(size * .3)),
    child: flowIconView(icon, size: size * .5, color: pal.accentText),
  );
}

/// Mở chi tiết tiến trình: máy tính ở vùng bên phải như chi tiết việc, điện thoại trang mới.
Future<void> openProcess(BuildContext context, AppState app, String id, {int initialTab = 0}) =>
    openFlowPage(context, 'process-$id', (_) => ProcessDetailPage(app: app, processId: id, initialTab: initialTab));

/// Mở báo cáo tiến trình của một quy trình.
Future<void> openProcessReport(BuildContext context, AppState app, String flowId, String flowName, {List<String>? labels}) =>
    openFlowPage(context, 'process-report-$flowId', (_) => ProcessReportPage(app: app, flowId: flowId, flowName: flowName, labels: labels));

class ProcessesView extends StatefulWidget {
  final AppState app;
  /// Quy trình để chọn ở bộ lọc (đã tải ở trang Quy trình); thêm các quy trình gặp trong danh sách.
  final List<FlowDefInfo> defs;
  final double bottomPadding;
  /// Chỉ cho test / ảnh xem trước: tab mở sẵn (0 đang chạy, 1 lỗi, 2 đã xong).
  final int initialTab;
  /// Chỉ tiến trình của một quy trình (trang quy trình trên máy tính): ẩn bộ lọc quy trình và nút Báo cáo.
  final String? flowId;
  /// Dòng đang chọn (tô đậm) và bấm dòng: thay cho mở trang chi tiết (trang quy trình hiện chi tiết ở cột phải).
  final String? selectedId;
  final void Function(FlowProcess p)? onSelect;
  /// Lọc sẵn theo một bước (mã bước của tiến trình), vd bấm bước ở phần thống kê của trang quy trình.
  final String? initialStep;
  /// Lọc trạng thái bằng ô chọn "Trạng thái: …" cùng hàng bộ lọc (thêm "Tất cả") thay cho 3 tab.
  final bool stateSelect;
  const ProcessesView(
      {super.key,
      required this.app,
      this.defs = const [],
      this.bottomPadding = 0,
      this.initialTab = 0,
      this.flowId,
      this.selectedId,
      this.onSelect,
      this.stateSelect = false,
      this.initialStep});
  @override
  State<ProcessesView> createState() => _ProcessesViewState();
}

class _ProcessesViewState extends State<ProcessesView> with SingleTickerProviderStateMixin {
  late final api = FlowsApi(widget.app.token);
  late final _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2))..addListener(_tabChanged);
  final _qCtl = TextEditingController();
  /// Danh sách theo tab (null = đang tải lần đầu).
  final _lists = <int, List<FlowProcess>>{};
  /// Mốc trang sau theo tab (null = đã hết); đang tải thêm.
  final _next = <int, String?>{};
  bool _moreBusy = false;
  static const _page = 50;
  String? _err;
  late String? _flow = widget.flowId;
  String? _label;
  late String? _step = widget.initialStep;
  String _q = '';
  Timer? _live, _debounce, _liveReload;
  int _seq = 0;
  /// Kênh realtime: `flow:<mã>` khi lọc một quy trình, không thì `processes` (mọi tiến trình mình xem được).
  FlowsLiveSub? _liveSub;
  DateTime _liveReloadAt = DateTime.fromMillisecondsSinceEpoch(0);
  /// Nhãn và bước đã gặp (để chọn ở bộ lọc): bước theo quy trình.
  final _seenLabels = <String>{};
  final _seenSteps = <String, Map<String, String>>{};
  final _seenFlows = <String, (String, String)>{};

  static const _states = ['running', 'failed', 'done,cancelled,skipped', ''];
  /// Trạng thái đang lọc: chỉ số trong [_states] (tab, hoặc ô chọn khi [ProcessesView.stateSelect]).
  late int _stateIdx = widget.initialTab.clamp(0, 2);
  /// Số tiến trình lỗi (ô chọn trạng thái: hiện số cạnh "Lỗi").
  int? _failedCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    _debounce?.cancel();
    _liveReload?.cancel();
    _liveSub?.cancel();
    _tabs.dispose();
    _qCtl.dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (_tabs.indexIsChanging) return;
    _stateIdx = _tabs.index;
    _load();
  }

  Future<void> _load() async {
    final tab = _stateIdx;
    final seq = ++_seq;
    _live?.cancel();
    _liveSubscribe();
    if (widget.stateSelect) {
      api.processes(flow: _flow, state: 'failed', limit: 200).then((l) {
        if (mounted && l.length != _failedCount) setState(() => _failedCount = l.length);
      }).catchError((_) {});
    }
    // Tự làm mới: tải lại đúng số dòng đang hiện (tối đa 200); đã cuộn xem hơn 200 dòng thì thôi tự làm mới.
    final shown = _lists[tab]?.length ?? 0;
    if (shown > 200) return _scheduleLive();
    try {
      final (list, next) = await api.processesPage(flow: _flow, state: _states[tab], label: _label, step: _step, q: _q, limit: shown.clamp(_page, 200));
      if (!mounted || seq != _seq) return;
      _remember(list);
      setState(() {
        _lists[tab] = list;
        _next[tab] = next;
        _err = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (_lists[tab] == null) setState(() => _err = '$e');
    }
    _scheduleLive();
  }

  /// Trang sau (cuộn tới cuối hoặc bấm "Tải thêm").
  Future<void> _loadMore() async {
    final tab = _stateIdx;
    final before = _next[tab];
    if (before == null || _moreBusy) return;
    final seq = _seq;
    setState(() => _moreBusy = true);
    try {
      final (list, next) = await api.processesPage(flow: _flow, state: _states[tab], label: _label, step: _step, q: _q, limit: _page, before: before);
      if (!mounted || seq != _seq) return;
      _remember(list);
      final have = {for (final p in _lists[tab] ?? const <FlowProcess>[]) p.id};
      setState(() {
        _lists[tab] = [...?_lists[tab], for (final p in list) if (!have.contains(p.id)) p];
        _next[tab] = next;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không tải thêm được: {0}', ['$e']))));
    } finally {
      if (mounted) setState(() => _moreBusy = false);
    }
  }

  void _remember(List<FlowProcess> list) {
    for (final p in list) {
      _seenLabels.addAll(p.labels);
      _seenFlows[p.flowId] = (p.flowName, p.flowIcon);
      final m = _seenSteps[p.flowId] ??= {};
      for (final st in p.steps) {
        final k = '${st['key'] ?? ''}';
        if (k.isNotEmpty) m[k] = '${st['title'] ?? k}';
      }
    }
  }

  /// Đang hiện (trang không bị che, app không chạy nền): 5 giây tải lại tab hiện tại một lần.
  void _scheduleLive() {
    _live?.cancel();
    if (!mounted) return;
    _live = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      final ls = WidgetsBinding.instance.lifecycleState;
      final visible = TickerMode.valuesOf(context).enabled && (ls == null || ls == AppLifecycleState.resumed);
      visible && !FlowsLive.of(api).up ? _load() : _scheduleLive();
    });
  }

  void _liveSubscribe() {
    final topic = _flow == null || _flow!.isEmpty ? 'processes' : 'flow:$_flow';
    if (_liveSub?.topic == topic) return;
    _liveSub?.cancel();
    _liveSub = FlowsLive.of(api).subscribe(topic, _onLive);
  }

  /// Tin realtime: tiến trình đang hiện (và vẫn đúng tab) thì thay dòng; tiến trình khác / đổi tab / `resync` thì tải
  /// lại tab hiện tại, tối đa 5 giây một lần (máy chủ đông việc không làm app tải liên tục).
  void _onLive(FlowsLiveEvent e) {
    if (!mounted || e.type == 'instance') return;
    final tab = _stateIdx;
    final list = _lists[tab];
    if (!e.resync && list != null && e.row.isNotEmpty) {
      final p = FlowProcess.fromJson(e.row);
      final want = _states[tab];
      final fits = want.isEmpty || want.split(',').contains(p.state);
      final i = list.indexWhere((x) => x.id == p.id);
      if (i >= 0 && fits) {
        _remember([p]);
        setState(() => _lists[tab] = [...list]..[i] = p);
        return;
      }
      if (i < 0 && !fits) return;
    }
    if (_liveReload?.isActive == true) return;
    final wait = const Duration(seconds: 5) - DateTime.now().difference(_liveReloadAt);
    _liveReload = Timer(wait.isNegative ? const Duration(milliseconds: 300) : wait, () {
      _liveReloadAt = DateTime.now();
      if (mounted) _load();
    });
  }

  void _setFilter(VoidCallback f) {
    setState(() {
      f();
      _lists.clear();
      _next.clear();
      _err = null;
    });
    _load();
  }

  void _search(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _setFilter(() => _q = v));
  }

  Map<String, (String, String)> get _flows {
    final m = <String, (String, String)>{for (final d in widget.defs) d.id: (d.name, d.icon)};
    for (final e in _seenFlows.entries) {
      m.putIfAbsent(e.key, () => e.value);
    }
    return m;
  }

  static String stateName(int i) => switch (i) { 0 => tr('Đang chạy'), 1 => tr('Lỗi'), 2 => tr('Đã xong'), _ => tr('Tất cả') };

  /// Số bộ lọc đang khác mặc định (trạng thái khác "Đang chạy", quy trình, nhãn, bước).
  int get _activeFilters =>
      (widget.stateSelect && _stateIdx != 0 ? 1 : 0) + (_flow != null && widget.flowId == null ? 1 : 0) + (_label != null ? 1 : 0) + (_step != null ? 1 : 0);

  /// Một hộp thoại gom mọi bộ lọc (trạng thái, quy trình, nhãn, bước): chọn xong bấm Áp dụng.
  Future<void> _openFilters(Pal pal) async {
    final flows = _flows;
    final labels = _seenLabels.toList()..sort();
    final failed = _failedCount ?? 0;
    var st = _stateIdx;
    var flow = _flow;
    var label = _label;
    var step = _step;
    final flowItems = flows.entries.toList()..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final steps = flow == null ? const <String, String>{} : (_seenSteps[flow] ?? const {});
        Widget head(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)));
        Widget choices<T>(List<(T?, String)> items, T? cur, void Function(T?) pick) => Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (v, l) in items)
                ChoiceChip(label: Text(l), selected: v == cur, showCheckmark: false, visualDensity: VisualDensity.compact, onSelected: (_) => set(() => pick(v))),
            ]);
        return AlertDialog(
          title: Text(tr('Lọc tiến trình')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (widget.stateSelect) ...[
                  head(tr('Trạng thái')),
                  choices<int>([for (final i in [0, 1, 2, 3]) (i, i == 1 && failed > 0 ? '${stateName(i)} ($failed)' : stateName(i))], st, (v) => st = v ?? 0),
                ],
                if (widget.flowId == null) ...[
                  head(tr('Quy trình')),
                  choices<String>([
                    (null, tr('Tất cả quy trình')),
                    for (final e in flowItems) (e.key, '${e.value.$2.isEmpty ? '' : '${e.value.$2} '}${e.value.$1}'),
                  ], flow, (v) {
                    if (v != flow) step = null;
                    flow = v;
                  }),
                ],
                head(tr('Nhãn')),
                labels.isEmpty
                    ? Text(tr('Chưa có nhãn nào'), style: TextStyle(color: pal.sub))
                    : choices<String>([(null, tr('Tất cả nhãn')), for (final l in labels) (l, l)], label, (v) => label = v),
                head(tr('Bước')),
                flow == null
                    ? Text(tr('Chọn quy trình trước để lọc theo bước'), style: TextStyle(color: pal.sub))
                    : choices<String>([(null, tr('Mọi bước')), for (final e in steps.entries) (e.key, e.value)], step, (v) => step = v),
                if (_flow != null && widget.flowId == null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.insights_rounded, size: 18),
                    label: Text(tr('Báo cáo')),
                    onPressed: () {
                      Navigator.pop(c);
                      openProcessReport(context, widget.app, _flow!, flows[_flow]?.$1 ?? _flow!, labels: labels);
                    },
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => set(() {
                st = 0;
                if (widget.flowId == null) flow = null;
                label = null;
                step = null;
              }),
              child: Text(tr('Bỏ lọc')),
            ),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Áp dụng'))),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    if (st == _stateIdx && flow == _flow && label == _label && step == _step) return;
    _setFilter(() {
      _stateIdx = st;
      _flow = flow;
      _label = label;
      _step = step;
    });
  }

  Widget _filters(Pal pal) {
    final n = _activeFilters;
    final failed = _failedCount ?? 0;
    // Nút lọc bên phải ô tìm: số đỏ = số tiến trình lỗi (khi đang không xem "Lỗi"), số xanh = số bộ lọc đang bật.
    final btn = IconButton(
      key: const ValueKey('process-filter'),
      tooltip: tr('Lọc'),
      onPressed: () => _openFilters(pal),
      style: IconButton.styleFrom(
        backgroundColor: n > 0 ? pal.accent.withValues(alpha: .15) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: n > 0 ? pal.accent : pal.divider)),
      ),
      icon: Badge(
        isLabelVisible: n > 0 || (widget.stateSelect && failed > 0 && _stateIdx != 1),
        backgroundColor: n > 0 ? pal.accent : kFlowRed,
        label: Text(n > 0 ? '$n' : '$failed'),
        child: Icon(Icons.tune_rounded, color: n > 0 ? pal.accentText : pal.sub),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _qCtl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: tr('Tìm tiến trình (tên, mã, khoá)'),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: _qCtl.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _qCtl.clear();
                        _debounce?.cancel();
                        _setFilter(() => _q = '');
                      },
                      icon: const Icon(Icons.close_rounded)),
            ),
            onChanged: (v) {
              setState(() {});
              _search(v);
            },
          ),
        ),
        const SizedBox(width: 8),
        btn,
      ]),
    );
  }

  int _discussionUnread(FlowProcess p) {
    final ch = '${p.raw['discussion_channel_id'] ?? ''}';
    if (ch.isEmpty || widget.app.channels[ch] == null || widget.app.members[ch] == null) return 0;
    return widget.app.unreadOf(ch);
  }

  Widget _row(Pal pal, FlowProcess p) {
    final small = TextStyle(color: pal.sub, fontSize: 12.5);
    final step = p.currentStepTitle;
    final warn = processWarning(p);
    final oneFlow = widget.flowId != null || _flow != null;
    final labels = [for (final l in p.labels) if (!sameAsStep(l, step)) l];
    // 1–2 thống kê chính: hai thống kê đầu theo thứ tự khai báo lúc tạo tiến trình.
    final stats = p.stats.take(2).toList();
    final at = p.finished && p.finishedAt > 0 ? p.finishedAt : p.updatedAt;
    final selected = widget.selectedId == p.id;
    return InkWell(
      onTap: () async {
        if (widget.onSelect != null) return widget.onSelect!(p);
        await openProcess(context, widget.app, p.id);
        if (mounted) _load();
      },
      child: Container(
        color: selected ? pal.accent.withValues(alpha: .12) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          processIconBox(pal, p),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
                // Tin thảo luận chưa đọc (kênh thảo luận mình là thành viên; không có số thì không hiện).
                if (_discussionUnread(p) case final n when n > 0) ...[const SizedBox(width: 6), ProcessUnreadBadge(count: n)],
              ]),
              // Chỉ cảnh báo (quá hạn, lỗi, trạng thái cam / đỏ) và nhãn không trùng tên bước; xuống dòng khi dài.
              if (p.overdue || warn != null || labels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 5, runSpacing: 4, children: [
                    if (p.overdue) ProcessChip(text: tr('Quá hạn'), color: kFlowOrange, solid: true),
                    if (warn != null) ProcessChip(text: warn.$1, color: warn.$2),
                    for (final l in labels) ProcessLabel(l),
                  ]),
                ),
              // Tên quy trình chỉ khi danh sách gồm nhiều quy trình (trang một quy trình: bỏ cho gọn, Sếp 11/11); ngày đứng
              // cuối dòng bước.
              if (!oneFlow || step.isEmpty) ...[
                const SizedBox(height: 3),
                Text([if (!oneFlow) p.flowName, if (at > 0 && (step.isEmpty || !oneFlow)) dayLabel(DateTime.fromMillisecondsSinceEpoch(at))].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
              ],
              if (step.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: oneFlow ? 4 : 2),
                  child: Row(children: [
                    Icon(p.state == 'failed' ? Icons.error_outline_rounded : Icons.flag_outlined, size: 14, color: p.state == 'failed' ? kFlowRed : pal.sub),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(tr('Bước: {0}', [step]), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: small.copyWith(color: p.state == 'failed' ? kFlowRed : pal.text)),
                    ),
                    if (oneFlow && at > 0) ...[const SizedBox(width: 8), Text(dayLabel(DateTime.fromMillisecondsSinceEpoch(at)), style: small)],
                  ]),
                ),
              if (p.waitingText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    const Icon(Icons.hourglass_top_rounded, size: 14, color: kProcessBlue),
                    const SizedBox(width: 4),
                    Expanded(child: Text(p.waitingText, maxLines: 1, overflow: TextOverflow.ellipsis, style: small.copyWith(color: kProcessBlue, fontWeight: FontWeight.w600))),
                  ]),
                ),
              if (p.steps.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: ProcessStepsBar(p)),
              // Tiến độ (bước Báo tiến độ) của luồng đang chạy, như trang chi tiết: thanh + "44% · nhãn".
              if (p.progress != null) FlowProgressBar(progress: p.progress, compact: true),
              if (stats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(spacing: 14, runSpacing: 2, children: [
                    for (final s in stats)
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '${s['label'] ?? s['key']}: ', style: small),
                        TextSpan(text: processStatValue(s['value']), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: pal.text)),
                      ])),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      ),
    );
  }

  Widget _tab(Pal pal, int i) {
    final list = _lists[i];
    Widget msg(String t) => ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: pal.sub)))]);
    if (list == null) {
      if (_err != null && _stateIdx == i) {
        return ListView(children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(tr('Không tải được tiến trình: {0}', [_err]), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
            ]),
          ),
        ]);
      }
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = (_flow != null && widget.flowId == null) || _label != null || _step != null || _q.isNotEmpty;
    if (list.isEmpty) {
      return msg(filtered
          ? tr('Không có tiến trình nào khớp bộ lọc.')
          : switch (i) {
              0 => tr('Không có tiến trình nào đang chạy.'),
              1 => tr('Không có tiến trình nào bị lỗi.'),
              2 => tr('Chưa có tiến trình nào xong.'),
              _ => tr('Chưa có tiến trình nào.'),
            });
    }
    final more = _next[i] != null;
    return ListView.separated(
      padding: EdgeInsets.only(bottom: 24 + widget.bottomPadding),
      itemCount: list.length + (more ? 1 : 0),
      separatorBuilder: (_, _) => Divider(height: 1, color: pal.divider),
      itemBuilder: (_, k) {
        if (k < list.length) return _row(pal, list[k]);
        // Cuối danh sách: tự tải trang sau (cuộn tới đây), lỗi thì bấm lại.
        if (!_moreBusy) WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
        return Padding(
          key: const ValueKey('process-more'),
          padding: const EdgeInsets.all(12),
          child: Center(
            child: _moreBusy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: _loadMore, child: Text(tr('Tải thêm'))),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final failed = _lists[1]?.length ?? 0;
    if (widget.stateSelect) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _filters(pal),
        Expanded(child: RefreshIndicator(onRefresh: _load, child: _tab(pal, _stateIdx))),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TabBar(
        controller: _tabs,
        tabs: [
          Tab(height: 42, text: tr('Đang chạy')),
          Tab(
            height: 42,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Lỗi')),
              if (failed > 0) ...[const SizedBox(width: 6), Badge(backgroundColor: kFlowRed, label: Text('$failed'))],
            ]),
          ),
          Tab(height: 42, text: tr('Đã xong')),
        ],
      ),
      _filters(pal),
      Expanded(
        child: TabBarView(controller: _tabs, children: [
          for (var i = 0; i < 3; i++) RefreshIndicator(onRefresh: _load, child: _tab(pal, i)),
        ]),
      ),
    ]);
  }
}
