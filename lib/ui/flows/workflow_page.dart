import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../desk_tabs.dart' show DeskTabScope;
import '../home_page.dart' show PageCloser;
import '../theme.dart';
import 'column_resizer.dart';
import 'flow_editor.dart' show roleLabel, stepLook;
import 'flow_experimental.dart';
import 'flow_card.dart' show kFlowOrange, kFlowRed;
import 'flow_logic.dart' show flowStatusLabel;
import 'flow_nav.dart';
import 'flows_page.dart' show FlowDetailPage, flowDefAdminAction, flowDefAdminItems, flowStatusColor, openFlowInstance, startFlowDef;
import 'process_detail.dart' show ProcessDetailPage;
import 'process_list.dart' show ProcessesView, openProcess, processStatValue;
import 'process_report.dart' show FlowReportCards, FlowStatsPanel, FlowStepTimes, durLabelShort;

/// Trang một quy trình trên máy tính: cột trái là danh sách tiến trình của quy trình (đối tượng theo dõi, hoặc các
/// lần chạy nếu quy trình không tạo đối tượng theo dõi), cột phải là chi tiết dòng đang
/// chọn; chưa chọn thì là giới thiệu quy trình, ai được chạy, các bước và thống kê chạy.
Future<void> openWorkflowPage(BuildContext context, AppState app, FlowDefInfo d, {bool? admin}) =>
    openFlowPage(context, 'workflow-${d.id}', (_) => WorkflowPage(app: app, flowId: d.id, name: d.name, icon: d.icon, def: d, admin: admin));

class WorkflowPage extends StatefulWidget {
  final AppState app;
  final String flowId, name, icon;
  /// Quy trình đã có ở danh sách (biểu mẫu để tạo, cờ bật / ẩn cho menu quản trị); null thì tự tải.
  final FlowDefInfo? def;
  /// Người xem là quản trị (đã biết ở trang Quy trình); null thì tự hỏi.
  final bool? admin;
  const WorkflowPage({super.key, required this.app, required this.flowId, this.name = '', this.icon = '', this.def, this.admin});
  @override
  State<WorkflowPage> createState() => _WorkflowPageState();
}

/// Trang quy trình đang giữ tiêu đề tab (trang mới mở thay trang cũ thì trang cũ không xoá tiêu đề của trang mới).
Object? _titleOwner;

class _WorkflowPageState extends State<WorkflowPage> {
  late final api = FlowsApi(widget.app.token);
  late FlowDefInfo? _def = widget.def;
  late bool _admin = widget.admin ?? false;
  Map<String, dynamic>? _info;
  String? _err;
  /// Quy trình có đối tượng theo dõi (process) không; null = đang hỏi.
  bool? _hasProc;
  List<Map<String, dynamic>>? _runs;
  /// 0 đối tượng theo dõi, 1 lần chạy (theo [_usesProcesses]).
  int _mode = 0;
  String? _selProc, _selRun;
  int _runTab = 0;
  String _q = '';
  final _qCtl = TextEditingController();
  Timer? _live;
  void Function(String? title)? _onTitle;

  String get _name => '${_info?['name'] ?? ''}'.isNotEmpty ? '${_info!['name']}' : (_def?.name ?? widget.name);
  String get _icon => '${_info?['icon'] ?? ''}'.isNotEmpty ? '${_info!['icon']}' : ((_def?.icon ?? '').isNotEmpty ? _def!.icon : widget.icon);
  /// Quy trình dùng đối tượng theo dõi: đã có, hoặc có bước tạo / cập nhật tiến trình (process_*). Khi đó cột trái là
  /// danh sách đối tượng theo dõi, không thì là các lần chạy (một danh sách, không có nút chuyển).
  bool get _usesProcesses =>
      _hasProc == true || [for (final s in (_info?['steps'] as List? ?? const [])) if (s is Map) '${s['type']}'].any((t) => t.startsWith('process_'));
  bool get _canStart => _def != null && !_experimental && (_info?['can_start'] ?? _def!.canStart) == true;
  /// Quy trình "Thử nghiệm": nhãn cạnh tên, nút ＋ mờ (bấm chỉ báo chưa chạy được).
  bool get _experimental => (_info?['experimental'] ?? _def?.experimental) == true;

  @override
  void initState() {
    super.initState();
    flowsChanged.addListener(_loadRuns);
    _load();
    widget.app.uiPref<num>(_leftPref).then((w) {
      if (w != null && mounted) setState(() => _leftW = w.toDouble());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cb = DeskTabScope.of(context)?.onTitle;
    if (cb != null && _onTitle == null) {
      _onTitle = cb;
      _titleOwner = this;
      WidgetsBinding.instance.addPostFrameCallback((_) => _setTitle());
    }
  }

  /// Tên quy trình làm tiêu đề tab (chỉ khi trang nằm trong một tab máy tính).
  void _setTitle() {
    if (!mounted || _titleOwner != this) return;
    final name = _name;
    if (name.isNotEmpty) _onTitle?.call(name);
  }

  @override
  void dispose() {
    _live?.cancel();
    flowsChanged.removeListener(_loadRuns);
    _qCtl.dispose();
    // Đóng trang: tab về tên ứng dụng (sau khung hình, không đổi cây widget lúc đang gỡ).
    final cb = _onTitle;
    if (cb != null && _titleOwner == this) {
      _titleOwner = null;
      scheduleMicrotask(() {
        if (_titleOwner == null) cb(null);
      });
    }
    super.dispose();
  }

  Future<void> _load() async {
    final meF = widget.admin != null ? Future.value(<String, dynamic>{'admin': widget.admin}) : api.me().then<Map<String, dynamic>?>((v) => v, onError: (_) => null);
    final procF = api.processes(flow: widget.flowId, limit: 1).then<bool?>((l) => l.isNotEmpty, onError: (_) => false);
    _loadRuns();
    try {
      final info = await api.flowInfo(widget.flowId);
      if (!mounted) return;
      setState(() {
        _info = info;
        _err = null;
      });
      _setTitle();
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    final me = await meF;
    if (!mounted) return;
    _admin = me?['admin'] == true;
    try {
      final defs = await api.defs(all: _admin);
      final d = defs.where((x) => x.id == widget.flowId).firstOrNull;
      if (mounted && d != null) setState(() => _def = d);
    } catch (_) {}
    final has = await procF;
    if (!mounted) return;
    setState(() {
      _hasProc = has;
      _mode = _usesProcesses ? 0 : 1;
    });
    _loadReport();
  }

  // ------------------------------------------------------------------ thống kê (phần giới thiệu, màn rộng)

  /// Số ngày gần đây của thống kê (7 / 30 / 90).
  int _days = 30;
  Map<String, dynamic>? _rep, _stepRep;
  String? _repErr;
  int _repSeq = 0;
  /// Bước đang lọc danh sách bên trái (bấm một bước ở cột "Các bước").
  String? _stepFilter;

  Future<void> _loadReport() async {
    if (_hasProc == null) return;
    final seq = ++_repSeq;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - (_days - 1)).millisecondsSinceEpoch;
    final to = now.millisecondsSinceEpoch;
    try {
      final r = _usesProcesses ? await api.processReport(widget.flowId, from: from, to: to) : await api.runsReport(widget.flowId, from: from, to: to);
      if (mounted && seq == _repSeq) {
        setState(() {
          _rep = r;
          _repErr = null;
        });
      }
    } catch (e) {
      if (mounted && seq == _repSeq) setState(() => _repErr = '$e');
    }
    // Thời gian theo bước (bước của tiến trình; quy trình không tạo tiến trình thì không có).
    final st = _usesProcesses ? await api.stepsReport(widget.flowId, from: from, to: to).then<Map<String, dynamic>?>((x) => x).catchError((_) => null) : null;
    if (mounted && seq == _repSeq) setState(() => _stepRep = st);
  }

  void _filterStep(String key) {
    setState(() {
      _stepFilter = _stepFilter == key ? null : key;
      _selProc = _selRun = null;
      _runTab = 0;
    });
  }

  Future<void> _loadRuns() async {
    _live?.cancel();
    try {
      final runs = await api.flowRuns(widget.flowId);
      if (mounted) setState(() => _runs = runs);
    } catch (_) {
      if (mounted && _runs == null) setState(() => _runs = const []);
    }
    _scheduleLive();
  }

  /// Danh sách lần chạy: 5 giây tải lại một lần khi đang hiện (như danh sách tiến trình).
  void _scheduleLive() {
    _live?.cancel();
    if (!mounted) return;
    _live = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      final ls = WidgetsBinding.instance.lifecycleState;
      final visible = TickerMode.valuesOf(context).enabled && (ls == null || ls == AppLifecycleState.resumed);
      visible && _mode == 1 ? _loadRuns() : _scheduleLive();
    });
  }

  Future<void> _start() async {
    final d = _def;
    if (d == null) return;
    await startFlowDef(context, widget.app, api, d, onCreated: (id) {
      if (!mounted) return;
      // Tiến trình mới mở ngay ở cột phải (cả khi cột trái đang là danh sách đối tượng theo dõi).
      setState(() {
        _selRun = id;
        _selProc = null;
      });
      _loadRuns();
    });
  }

  void _select({String? proc, String? run}) => setState(() {
        _selProc = proc;
        _selRun = run;
      });

  // ------------------------------------------------------------------ cột trái

  Widget _header(Pal pal) {
    final close = flowLeading(context);
    final d = _def;
    final category = '${_info?['category'] ?? d?.category ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ?close,
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(12)),
            child: Text(_icon.isEmpty ? '📋' : _icon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: pal.text)),
              if (category.isNotEmpty) Text(category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub)),
              if (_experimental) const Padding(padding: EdgeInsets.only(top: 3), child: FlowExperimentalBadge(small: true)),
            ]),
          ),
          // Nút Báo cáo (Sếp, 2026-11-11): về giao diện ban đầu của trang quy trình (giới thiệu + báo cáo ở cột phải), không
          // mở trang riêng. Điện thoại: đổi qua lại giữa danh sách và phần giới thiệu / báo cáo.
          IconButton(
            key: const ValueKey('flow-report'),
            tooltip: _narrow && _introNarrow ? tr('Danh sách') : tr('Báo cáo'),
            onPressed: () {
              if (_narrow) {
                setState(() => _introNarrow = !_introNarrow);
              } else {
                _select();
              }
            },
            icon: Icon(_narrow && _introNarrow ? Icons.view_list_rounded : Icons.bar_chart_rounded),
          ),
          if (_admin && d != null)
            PopupMenuButton<String>(
              tooltip: tr('Thêm'),
              icon: const Icon(Icons.more_vert_rounded),
              itemBuilder: (_) => flowDefAdminItems(d),
              onSelected: (v) => flowDefAdminAction(context, widget.app, api, d, v, reload: _load),
            ),
        ]),
      ]),
    );
  }

  /// Lọc trạng thái lần chạy (ô chọn "Trạng thái: …"): Đang chạy, Lỗi, Đã xong, Tất cả (null).
  static const _runTabs = <Set<String>?>[
    {'running', 'returned'},
    {'failed'},
    {'done', 'rejected', 'cancelled'},
    null,
  ];
  static String _stateName(int i) => switch (i) { 0 => tr('Đang chạy'), 1 => tr('Lỗi'), 2 => tr('Đã xong'), _ => tr('Tất cả') };

  /// Hộp thoại lọc lượt chạy (cùng kiểu nút lọc của danh sách tiến trình): chọn trạng thái rồi Áp dụng.
  Future<void> _pickRunState() async {
    final pal = Pal.of(context);
    final failed = (_runs ?? const []).where((r) => r['status'] == 'failed').length;
    var st = _runTab;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('Lọc tiến trình')),
          content: SizedBox(
            width: 420,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(tr('Trạng thái'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final i in [0, 1, 2, 3])
                  ChoiceChip(
                    label: Text(i == 1 && failed > 0 ? '${_stateName(i)} ($failed)' : _stateName(i)),
                    selected: i == st,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => set(() => st = i),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => set(() => st = 0), child: Text(tr('Bỏ lọc'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Áp dụng'))),
          ],
        ),
      ),
    );
    if (ok == true && mounted && st != _runTab) setState(() => _runTab = st);
  }

  String _who(String id) {
    if (id.isEmpty) return '';
    if (id == widget.app.me?.id) return tr('Bạn');
    final u = widget.app.users[id];
    if (u == null) {
      widget.app.refreshUser(id).then((_) => mounted ? setState(() {}) : null).catchError((_) {});
      return id;
    }
    return u.displayName.isNotEmpty ? u.displayName : u.username;
  }

  Widget _runRow(Pal pal, Map<String, dynamic> r) {
    final id = '${r['id']}';
    final status = '${r['status']}';
    final c = flowStatusColor(status, pal.accentText);
    final at = (r['updated_at'] as num?)?.toInt() ?? 0;
    final current = [for (final x in (r['current'] as List? ?? const [])) '$x'];
    final small = TextStyle(color: pal.sub, fontSize: 12.5);
    return InkWell(
      onTap: () => _narrow ? openFlowInstance(context, widget.app, id) : _select(run: id),
      child: Container(
        color: _selRun == id ? pal.accent.withValues(alpha: .12) : null,
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text('${r['title'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(10)),
              child: Text(flowStatusLabel(status), style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 3),
          Text([_who('${r['requester'] ?? ''}'), if (at > 0) dayLabel(DateTime.fromMillisecondsSinceEpoch(at))].where((x) => x.isNotEmpty).join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
          if (current.isNotEmpty && (status == 'running' || status == 'returned'))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 14, color: pal.sub),
                const SizedBox(width: 4),
                Expanded(child: Text(tr('Bước: {0}', [current.join(', ')]), maxLines: 1, overflow: TextOverflow.ellipsis, style: small.copyWith(color: pal.text))),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _runsList(Pal pal) {
    final runs = _runs;
    final q = _q.trim().toLowerCase();
    final failed = (runs ?? const []).where((r) => r['status'] == 'failed').length;
    final want = _runTabs[_runTab];
    final shown = [
      for (final r in runs ?? const <Map<String, dynamic>>[])
        if ((want == null || want.contains('${r['status']}')) &&
            (q.isEmpty || '${r['title'] ?? ''} ${r['id']}'.toLowerCase().contains(q)) &&
            (_stepFilter == null || [for (final w in (r['waiting'] as List? ?? const [])) '$w'].contains(_stepFilter)))
          r,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qCtl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr('Tìm tiến trình (tiêu đề, mã)'),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () => setState(() {
                                _qCtl.clear();
                                _q = '';
                              }),
                          icon: const Icon(Icons.close_rounded)),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(width: 8),
            // Nút lọc bên phải ô tìm: số đỏ = số lượt lỗi (khi không xem "Lỗi"), số xanh = số bộ lọc đang bật.
            IconButton(
              key: const ValueKey('state-select'),
              tooltip: tr('Lọc'),
              onPressed: _pickRunState,
              style: IconButton.styleFrom(
                backgroundColor: _runTab != 0 ? pal.accent.withValues(alpha: .15) : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _runTab != 0 ? pal.accent : pal.divider)),
              ),
              icon: Badge(
                isLabelVisible: _runTab != 0 || failed > 0,
                backgroundColor: _runTab != 0 ? pal.accent : kFlowRed,
                label: Text(_runTab != 0 ? '1' : '$failed'),
                child: Icon(Icons.tune_rounded, color: _runTab != 0 ? pal.accentText : pal.sub),
              ),
            ),
          ]),
          if (_stepFilter != null) const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            // Đang lọc theo một bước (bấm bước ở cột "Các bước" của phần thống kê).
            if (_stepFilter != null)
              InputChip(
                key: const ValueKey('step-filter'),
                label: Text(_stepTitle(_stepFilter!), maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: true,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onDeleted: () => setState(() => _stepFilter = null),
              ),
          ]),
        ]),
      ),
      Expanded(
        child: runs == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadRuns,
                child: shown.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            q.isNotEmpty
                                ? tr('Không có tiến trình nào khớp bộ lọc.')
                                : switch (_runTab) {
                                    0 => tr('Không có tiến trình nào đang chạy.'),
                                    1 => tr('Không có tiến trình nào bị lỗi.'),
                                    2 => tr('Chưa có tiến trình nào xong.'),
                                    _ => tr('Chưa có tiến trình nào.'),
                                  },
                            textAlign: TextAlign.center,
                            style: TextStyle(color: pal.sub),
                          ),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: pal.divider),
                        itemBuilder: (_, i) => _runRow(pal, shown[i]),
                      ),
              ),
      ),
    ]);
  }

  Widget _left(Pal pal) {
    final Widget list;
    if (_hasProc == null && _runs == null) {
      list = const Center(child: CircularProgressIndicator());
    } else if (_mode == 0 && _usesProcesses) {
      list = ProcessesView(
        key: ValueKey('procs-${widget.flowId}-$_stepFilter'),
        initialStep: _stepFilter,
        app: widget.app,
        flowId: widget.flowId,
        stateSelect: true,
        bottomPadding: 72,
        selectedId: _selProc,
        onSelect: (p) => _narrow ? openProcess(context, widget.app, p.id) : _select(proc: p.id),
      );
    } else {
      list = _runsList(pal);
    }
    // Nút ＋ "Tạo tiến trình mới" góc dưới phải của cột danh sách (như nút tạo tin nhắn / dự án mới).
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(pal),
        Divider(height: 1, color: pal.divider),
        Expanded(child: list),
      ]),
      if (_canStart)
        Positioned(
          right: 20,
          bottom: 20,
          child: PlusFab(heroTag: 'workflow-new-${widget.flowId}', tooltip: tr('Tạo tiến trình mới'), onPressed: _start),
        )
      else if (_experimental && _def != null)
        Positioned(
          right: 20,
          bottom: 20,
          child: Opacity(
            opacity: .45,
            child: PlusFab(
              key: const ValueKey('workflow-new-experimental'),
              heroTag: 'workflow-new-${widget.flowId}',
              tooltip: flowExperimentalMsg(),
              onPressed: () => showFlowExperimental(context),
            ),
          ),
        ),
    ]);
  }

  // ------------------------------------------------------------------ cột phải

  Widget _section(Pal pal, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title.toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: .3, color: pal.sub)),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  static String _date(Object? s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${s ?? ''}');
    return m == null ? '' : '${m[3]}/${m[2]}/${m[1]}';
  }

  Widget _who2(Pal pal, Map w) {
    final icon = switch ('${w['kind']}') {
      'user' => Icons.person_outline_rounded,
      'department' => Icons.apartment_rounded,
      'role' => Icons.badge_outlined,
      'manager' => Icons.supervisor_account_outlined,
      'all' => Icons.groups_rounded,
      _ => Icons.person_search_outlined,
    };
    // Vai trò: máy chủ trả tên hiển thị; bản cũ trả mã thì đổi theo bảng tên vai trò của trình soạn.
    final raw = '${w['name'] ?? ''}';
    final name = w['kind'] == 'role' && (raw.isEmpty || raw == '${w['id']}') ? roleLabel('${w['id']}') : raw;
    final kind = switch ('${w['kind']}') {
      'department' => tr('Phòng ban'),
      'role' => tr('Vai trò'),
      _ => '',
    };
    return Chip(
      avatar: Icon(icon, size: 17, color: pal.accentText),
      label: Text(kind.isEmpty ? name : '$kind: $name'),
      visualDensity: VisualDensity.compact,
    );
  }

  /// Tên khai báo của bước (bước của tiến trình hoặc bước của quy trình).
  String _stepTitle(String key) {
    for (final s in (_stepRep?['steps'] as List? ?? const [])) {
      if (s is Map && '${s['key']}' == key) return '${s['title'] ?? key}';
    }
    for (final s in (_rep?['by_step'] as List? ?? const [])) {
      if (s is Map && '${s['key']}' == key) return '${s['title'] ?? key}';
    }
    for (final s in (_info?['steps'] as List? ?? const [])) {
      if (s is Map && '${s['id']}' == key) return '${s['name'] ?? key}';
    }
    return key;
  }

  /// Phần giới thiệu khi chưa chọn tiến trình: màn rộng (từ ~760px) 2 cột, trái là báo cáo (đầu trang gọn, thống kê,
  /// thời gian theo bước), phải là các bước theo thứ tự kèm số đang ở / thời gian TB / quá hạn; hẹp: một cột như cũ.
  Widget _intro(Pal pal) => LayoutBuilder(builder: (ctx, box) => box.maxWidth < 760 || _info == null ? _introOne(pal) : _introTwo(pal));

  /// Đầu trang gọn: biểu tượng, tên, mô tả, ai được chạy, thời gian áp dụng.
  List<Widget> _introHead(Pal pal, Map<String, dynamic> info) {
    final desc = '${info['description'] ?? ''}'.trim();
    final who = [for (final w in (info['who_can_start'] as List? ?? const [])) if (w is Map) w];
    final from = _date(info['valid_from']), until = _date(info['valid_until']);
    final validity = [if (from.isNotEmpty) tr('từ {0}', [from]), if (until.isNotEmpty) tr('đến hết {0}', [until])].join(' ');
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(14)),
          child: Text(_icon.isEmpty ? '📋' : _icon, style: const TextStyle(fontSize: 26)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: pal.text)),
            Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if ('${info['category'] ?? ''}'.isNotEmpty) Text('${info['category']}', style: TextStyle(color: pal.sub, fontSize: 13)),
              if (info['active'] == false) Text(tr('Đang tắt'), style: TextStyle(color: pal.sub, fontWeight: FontWeight.w700, fontSize: 13)),
              if (_experimental) const FlowExperimentalBadge(),
              Text(tr('Phiên bản {0}', ['${info['version'] ?? ''}']), style: TextStyle(color: pal.sub, fontSize: 12.5)),
            ]),
          ]),
        ),
      ]),
      if (desc.isNotEmpty) ...[const SizedBox(height: 10), Text(desc, style: TextStyle(fontSize: 14, height: 1.4, color: pal.text))],
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${tr('Ai được chạy')}:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: pal.sub)),
        if (who.isEmpty)
          Text(tr('Không bắt đầu bằng tay'), style: TextStyle(fontSize: 12.5, color: pal.sub))
        else
          for (final w in who) _who2(pal, w),
      ]),
      if (validity.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(Icons.event_available_outlined, size: 16, color: pal.sub),
            const SizedBox(width: 6),
            Expanded(child: Text(tr('Thời gian áp dụng: {0}', [validity]), style: TextStyle(fontSize: 13, color: pal.text))),
          ]),
        ),
    ];
  }

  Widget _introTwo(Pal pal) {
    final info = _info!;
    final rep = _rep;
    final left = ListView(key: const ValueKey('intro-report'), padding: const EdgeInsets.fromLTRB(24, 20, 20, 32), children: [
      ..._introHead(pal, info),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Text(tr('Báo cáo'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.text))),
        for (final v in [7, 30, 90]) ...[
          const SizedBox(width: 6),
          ChoiceChip(
            label: Text(tr('{0} ngày', [v])),
            selected: _days == v,
            visualDensity: VisualDensity.compact,
            onSelected: (_) {
              setState(() => _days = v);
              _loadReport();
            },
          ),
        ],
      ]),
      const SizedBox(height: 10),
      if (_repErr != null)
        Text(tr('Không tải được báo cáo: {0}', [_repErr]), style: TextStyle(color: pal.sub))
      else if (rep == null)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else ...[
        FlowReportCards(data: rep, runs: !_usesProcesses),
        if ((_stepRep?['steps'] as List? ?? const []).isNotEmpty) FlowStepTimes(data: _stepRep!),
      ],
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(flex: 6, child: left),
      VerticalDivider(width: 1, color: pal.divider),
      Expanded(flex: 4, child: _stepsColumn(pal, info)),
    ]);
  }

  /// Cột "Các bước": các bước theo thứ tự (tiến trình: bước của tiến trình; không: bước của quy trình, có biểu tượng
  /// theo loại), kèm số đang ở bước, thời gian TB ở bước, số lượt quá hạn. Bấm một bước: lọc danh sách bên trái.
  Widget _stepsColumn(Pal pal, Map<String, dynamic> info) {
    final timed = {for (final s in (_stepRep?['steps'] as List? ?? const [])) if (s is Map) '${s['key']}': s};
    final current = {for (final s in (_rep?['by_step'] as List? ?? const [])) if (s is Map) '${s['key']}': s};
    final rows = <({String key, String title, IconData icon, Color color, num? active, num? avg, num? overdue, String sla})>[];
    if (_usesProcesses) {
      final keys = [...timed.keys, for (final k in current.keys) if (!timed.containsKey(k)) k];
      for (final k in keys) {
        final t = timed[k], c = current[k];
        rows.add((
          key: k,
          title: '${t?['title'] ?? c?['title'] ?? k}',
          icon: Icons.flag_outlined,
          color: pal.accentText,
          active: (t?['active'] as num?) ?? (c?['count'] as num?),
          avg: t?['avg_ms'] as num?,
          overdue: t?['overdue'] as num?,
          sla: '${t?['sla'] ?? ''}',
        ));
      }
    }
    if (rows.isEmpty) {
      for (final s in (info['steps'] as List? ?? const [])) {
        if (s is! Map) continue;
        final look = stepLook('${s['type']}');
        final k = '${s['id']}';
        rows.add((
          key: k,
          title: '${s['name'] ?? k}',
          icon: look.$1,
          color: look.$2,
          active: _usesProcesses ? null : (current[k]?['count'] as num?) ?? 0,
          avg: null,
          overdue: null,
          sla: '',
        ));
      }
    }
    String dur(num? v) => v != null && v > 0 ? FlowReportCards.duration(v) : '';
    return ListView(key: const ValueKey('intro-steps'), padding: const EdgeInsets.fromLTRB(16, 20, 16, 32), children: [
      Text(tr('Các bước'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.text)),
      Text(tr('Bấm một bước để lọc danh sách bên trái'), style: TextStyle(fontSize: 12.5, color: pal.sub)),
      const SizedBox(height: 10),
      if (rows.isEmpty) Text(tr('Chưa có dữ liệu'), style: TextStyle(color: pal.sub)),
      for (final (i, r) in rows.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: _stepFilter == r.key ? pal.accent.withValues(alpha: .12) : pal.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('intro-step-${r.key}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => _filterStep(r.key),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: pal.sub))),
                  const SizedBox(width: 6),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: r.color.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
                    child: Icon(r.icon, size: 17, color: r.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                      if (dur(r.avg).isNotEmpty || r.sla.isNotEmpty)
                        Text(
                          [if (dur(r.avg).isNotEmpty) tr('TB {0}', [dur(r.avg)]), if (r.sla.isNotEmpty) tr('Hạn {0}', [durLabelShort(r.sla)])].join(' · '),
                          style: TextStyle(fontSize: 12, color: pal.sub),
                        ),
                    ]),
                  ),
                  if (r.active != null)
                    Tooltip(
                      message: tr('Đang ở bước này'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
                        child: Text(processStatValue(r.active!), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: pal.text)),
                      ),
                    ),
                  if ((r.overdue ?? 0) > 0) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: tr('Quá hạn'),
                      child: Container(
                        key: ValueKey('overdue-${r.key}'),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: kFlowOrange.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.schedule_rounded, size: 12, color: kFlowOrange),
                          const SizedBox(width: 3),
                          Text(processStatValue(r.overdue!), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: kFlowOrange)),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _introOne(Pal pal) {
    final info = _info;
    if (info == null) {
      return Center(
        child: _err == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr('Không tải được quy trình: {0}', [_err]), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
                ]),
              ),
      );
    }
    final desc = '${info['description'] ?? ''}'.trim();
    final who = [for (final w in (info['who_can_start'] as List? ?? const [])) if (w is Map) w];
    final steps = [for (final s in (info['steps'] as List? ?? const [])) if (s is Map) s];
    final from = _date(info['valid_from']), until = _date(info['valid_until']);
    final validity = [
      if (from.isNotEmpty) tr('từ {0}', [from]),
      if (until.isNotEmpty) tr('đến hết {0}', [until]),
    ].join(' ');
    return ListView(padding: const EdgeInsets.fromLTRB(28, 24, 28, 32), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(18)),
                child: Text(_icon.isEmpty ? '📋' : _icon, style: const TextStyle(fontSize: 34)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pal.text)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if ('${info['category'] ?? ''}'.isNotEmpty) Text('${info['category']}', style: TextStyle(color: pal.sub)),
                    if (info['active'] == false) Text(tr('Đang tắt'), style: TextStyle(color: pal.sub, fontWeight: FontWeight.w700)),
                    if (_experimental) const FlowExperimentalBadge(),
                    Text(tr('Phiên bản {0}', ['${info['version'] ?? ''}']), style: TextStyle(color: pal.sub, fontSize: 12.5)),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Text(desc.isEmpty ? tr('Chưa có mô tả.') : desc, style: TextStyle(fontSize: 14.5, height: 1.45, color: desc.isEmpty ? pal.sub : pal.text)),
            _section(pal, tr('Ai được chạy'), [
              if (who.isEmpty)
                Text(tr('Quy trình này không bắt đầu bằng tay (tự chạy theo lịch, webhook, tin nhắn...).'), style: TextStyle(color: pal.sub))
              else
                Wrap(spacing: 6, runSpacing: 6, children: [for (final w in who) _who2(pal, w)]),
              if (validity.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.event_available_outlined, size: 17, color: pal.sub),
                    const SizedBox(width: 6),
                    Expanded(child: Text(tr('Thời gian áp dụng: {0}', [validity]), style: TextStyle(color: pal.text))),
                  ]),
                ),
            ]),
            if (steps.isNotEmpty)
              _section(pal, tr('Các bước'), [
                for (final (i, s) in steps.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: pal.accent.withValues(alpha: .14), shape: BoxShape.circle),
                        child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: pal.accentText)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text('${s['name'] ?? s['id']}', style: TextStyle(color: pal.text))),
                      if (s['no'] != null) Text('#${s['no']}', style: TextStyle(fontSize: 12, color: pal.sub)),
                    ]),
                  ),
              ]),
            const SizedBox(height: 22),
            if (_hasProc != null) FlowStatsPanel(key: ValueKey('stats-$_usesProcesses'), app: widget.app, flowId: widget.flowId, runs: !_usesProcesses),
          ]),
        ),
      ),
    ]);
  }

  Widget _right(Pal pal) {
    final sel = _selProc ?? _selRun;
    if (sel == null) return _intro(pal);
    final Widget page = _selProc != null ? ProcessDetailPage(app: widget.app, processId: _selProc!) : FlowDetailPage(app: widget.app, instanceId: _selRun!);
    // Nút đóng của trang chi tiết = bỏ chọn; trang con (báo cáo, chi tiết khác) mở chồng trong cột này.
    return PageCloser(
      onClose: () => _select(),
      child: Navigator(
        key: ValueKey('detail-$sel'),
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => page),
      ),
    );
  }

  bool _narrow = false;
  /// Điện thoại: đang xem phần giới thiệu / báo cáo thay cho danh sách.
  bool _introNarrow = false;
  /// Độ rộng cột danh sách do người dùng kéo (null = mặc định), lưu theo tài khoản.
  double? _leftW;
  static const _leftPref = 'workflow_left_w';

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          _narrow = box.maxWidth < 600;
          if (_narrow) {
            return _introNarrow ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_header(pal), Expanded(child: _intro(pal))]) : _left(pal);
          }
          final maxLeft = (box.maxWidth - 420).clamp(260.0, double.infinity);
          final leftW = (_leftW ?? (box.maxWidth * .3).clamp(300.0, 400.0)).clamp(260.0, maxLeft);
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: leftW, child: _left(pal)),
            ColumnResizer(
              key: const ValueKey('workflow-left-resizer'),
              onDrag: (dx) => setState(() => _leftW = (leftW + dx).clamp(260.0, maxLeft)),
              onDragEnd: () => widget.app.setUiPref(_leftPref, _leftW),
              onReset: () {
                setState(() => _leftW = null);
                widget.app.setUiPref(_leftPref, null);
              },
            ),
            Expanded(child: _right(pal)),
          ]);
        }),
      ),
    );
  }
}
