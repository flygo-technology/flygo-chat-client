import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/flows_api.dart';
import '../../api/flows_live.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../flygo_card.dart' show FlygoChoices, flygoCardButtons;
import '../flygo_card_action.dart';
import '../open_file.dart';
import '../tasks/task_chat.dart' show openSourceMessage;
import '../theme.dart';
import 'column_resizer.dart';
import 'flow_card.dart' show kFlowGreen, kFlowOrange, kFlowRed;
import 'flow_form.dart';
import 'flow_logic.dart' show flowTaskKindLabel;
import 'flow_nav.dart';
import 'flow_task_action.dart';
import 'flows_page.dart' show FlowProgressBar, openFlowInstance;
import 'process_chat.dart';
import 'process_list.dart';

/// Mở tệp đính kèm / liên kết của tiến trình: liên kết (hoặc thư mục ngoài) mở bằng trình duyệt; tệp tải qua Flows
/// (GET /flows/processes/{id}/files/{file_id}) rồi mở bằng ứng dụng của máy. [f]: {file_id?, url?, name?}.
Future<void> openProcessFile(BuildContext context, FlowsApi api, String processId, Map<String, dynamic> f) async {
  final messenger = ScaffoldMessenger.of(context);
  final url = Uri.tryParse('${f['url'] ?? ''}');
  final fileId = '${f['file_id'] ?? ''}';
  if (fileId.isEmpty) {
    if (url != null && (url.scheme == 'https' || url.scheme == 'http')) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      messenger.showSnackBar(toast(Text(tr('Không có liên kết để mở'))));
    }
    return;
  }
  try {
    final bytes = await api.processFile(processId, fileId);
    final dir = await getTemporaryDirectory();
    final safe = '${f['name'] ?? fileId}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}process-$fileId-$safe');
    await file.writeAsBytes(bytes);
    if (!await openLocalFile(file.path, title: safe)) messenger.showSnackBar(toast(Text(tr('Không mở được tệp'))));
  } catch (e) {
    messenger.showSnackBar(toast(Text(tr('Không tải được tệp: {0}', ['$e']))));
  }
}

/// Nút `open` của thẻ tiến trình: `{process, file?, name?}` — có `file` thì tải và mở tệp đó, không thì mở trang tiến trình.
Future<void> openProcessTarget(BuildContext context, AppState app, Map<String, dynamic> open) async {
  final id = '${open['process'] ?? ''}'.trim();
  if (id.isEmpty) return;
  final file = '${open['file'] ?? ''}'.trim();
  if (file.isEmpty) return openProcess(context, app, id);
  return openProcessFile(context, FlowsApi(app.token), id, {'file_id': file, 'name': open['name'] ?? file});
}

/// Chi tiết một tiến trình: đầu trang (icon, tên, trạng thái), các bước (dòng thời gian), thống kê, nhãn, tệp và liên kết,
/// thẻ đã gửi (bấm để nhảy tới tin), lịch sử thay đổi, việc đã tạo ra tiến trình. Đang chạy thì 5 giây làm mới một lần.
class ProcessDetailPage extends StatefulWidget {
  final AppState app;
  final String processId;
  /// BẢN MẪU thảo luận (chưa có máy chủ): tin nhắn xen trong đường thời gian + khung soạn ghim cuối cột.
  /// Tab mở sẵn khi một cột (0 Tiến trình, 1 Thảo luận; vd mở từ thông báo tin thảo luận).
  final int initialTab;
  const ProcessDetailPage({super.key, required this.app, required this.processId, this.initialTab = 0});
  @override
  State<ProcessDetailPage> createState() => _ProcessDetailPageState();
}

class _ProcessDetailPageState extends State<ProcessDetailPage> {
  late final api = FlowsApi(widget.app.token);
  FlowProcess? _p;
  /// Không được tham gia thảo luận (không liên quan): bố cục cũ, không có cột thảo luận.
  bool _noDiscussion = false;
  /// Độ rộng cột thảo luận do người dùng kéo (null = mặc định).
  double? _chatW;
  static const _chatPref = 'process_chat_w';
  /// Số tin thảo luận (nhãn tab khi một cột); null = chưa tải.
  int? _discCount;
  String? _err;
  Timer? _live, _liveReload;
  /// Kênh realtime của tiến trình: đổi thì tải lại ngay; huỷ khi đóng trang hoặc tiến trình xong.
  FlowsLiveSub? _liveSub;

  @override
  void initState() {
    super.initState();
    _liveSub = FlowsLive.of(api).subscribe('process:${widget.processId}', (_) {
      if (!mounted) return;
      _liveReload?.cancel();
      _liveReload = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _load();
      });
    });
    _load();
    widget.app.uiPref<num>(_chatPref).then((w) {
      if (w != null && mounted) setState(() => _chatW = w.toDouble());
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    _liveReload?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _live?.cancel();
    try {
      final p = await api.process(widget.processId);
      if (!mounted) return;
      setState(() {
        _p = p;
        _err = null;
      });
    } catch (e) {
      if (mounted && _p == null) setState(() => _err = '$e');
    }
    if (_p?.finished ?? false) {
      _liveSub?.cancel();
      _liveSub = null;
    }
    // Chưa xong: tự làm mới khi trang đang hiện (kênh realtime đang nối thì không cần).
    if (!mounted || (_p?.finished ?? false)) return;
    _scheduleLive();
  }

  void _scheduleLive() {
    _live?.cancel();
    _live = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      final ls = WidgetsBinding.instance.lifecycleState;
      final visible = TickerMode.valuesOf(context).enabled && (ls == null || ls == AppLifecycleState.resumed);
      visible && !(_liveSub != null && FlowsLive.of(api).up) ? _load() : _scheduleLive();
    });
  }

  String _who(String id) {
    if (id.isEmpty) return '';
    if (id == widget.app.me?.id) return tr('Bạn');
    final u = widget.app.users[id];
    if (u == null) {
      // Không phải id người (bot, tên node…): hiện nguyên.
      if (id.length == 26) widget.app.refreshUser(id).then((_) => mounted ? setState(() {}) : null).catchError((_) {});
      return id;
    }
    return u.displayName.isNotEmpty ? u.displayName : u.username;
  }

  String _when(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dayLabel(d)} ${hhmm(d)}';
  }

  static String _size(num? b) {
    if (b == null || b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _openFile(Map<String, dynamic> f) => openProcessFile(context, api, widget.processId, f);

  /// Thẻ tiến trình mình thấy được trong chat (để bấm nút của bước chờ thay cho bấm trên thẻ): trả lời vào luồng thẻ đó.
  MmPost? _cardPost(FlowProcess p) {
    for (final x in p.posts) {
      final ch = '${x['channel_id'] ?? ''}', id = '${x['post_id'] ?? ''}';
      if (ch.isNotEmpty && id.isNotEmpty && widget.app.channels[ch] != null) {
        return MmPost({'id': id, 'channel_id': ch, 'user_id': '', 'create_at': 0, 'message': '', 'props': const {}});
      }
    }
    return null;
  }

  Future<void> _act(FlowProcess p, Map<String, dynamic> a) async {
    await runFlygoCardAction(context, widget.app, _cardPost(p), a, processId: p.id);
    // Máy chủ đọc trả lời trong luồng thẻ vài giây một lần: tải lại sau đó để thấy kết quả.
    if (mounted && a['open'] == null && a['url'] == null) {
      _live?.cancel();
      _live = Timer(const Duration(seconds: 3), _load);
    }
  }

  /// Nút / lựa chọn đang mở, trừ bước chờ mà chính người xem đang có việc (việc đó hiện ô nhập / nút ngay bên dưới).
  List<Map<String, dynamic>> _entries(FlowProcess p) {
    final mine = p.myTasks;
    return [
      for (final e in p.actions)
        if (!mine.any((t) => t.instanceId == '${e['instance_id'] ?? ''}' && t.node == '${e['node'] ?? ''}')) e,
    ];
  }

  /// Việc đang chờ chính người xem: điền thông tin (các ô nhập + Gửi ngay trên trang), chờ bấm nút / lựa chọn, duyệt.
  Widget _myTask(Pal pal, FlowTask t) {
    Future<void> after() async {
      flowsChanged.value++;
      await _load();
    }

    final title = '${t.raw['step_name'] ?? t.node}';
    final type = '${t.raw['node_type'] ?? ''}';
    final fields = FlowField.listOf(t.raw['fields']);
    final Widget body;
    if (t.kind == 'form' && type == 'form_task') {
      body = FlowFormPage(
        key: ValueKey('process-task-form-${t.id}'),
        app: widget.app,
        api: api,
        title: title,
        fields: fields,
        initial: t.prefill ?? const {},
        flowId: t.flowId,
        lookupPath: (f) => '${t.node}:${f.key}',
        notice: t.returned == null ? '' : tr('Bị trả lại: {0}', ['${t.returned!['reason'] ?? ''}']),
        embedded: true,
        onSubmit: (data, _) => api.submit(t.id, data),
        onDone: (_) => after(),
      );
    } else if (t.kind == 'action' && t.action != null) {
      body = FlowTaskActionPanel(key: ValueKey('process-task-action-${t.id}'), task: t, onSubmit: (data) async {
        await api.submit(t.id, data);
        await after();
      });
    } else {
      // Duyệt, tiếp nhận, việc tay...: mở luồng để làm (cùng quyền như "Việc của tôi").
      body = Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () async {
            await openFlowInstance(context, widget.app, t.instanceId);
            if (mounted) _load();
          },
          child: Text(t.kind == 'approval' ? tr('Mở để duyệt') : tr('Mở để làm')),
        ),
      );
    }
    return Padding(
      key: ValueKey('process-task-${t.id}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${flowTaskKindLabel(t.kind)}: $title', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 8),
        if (t.request case final Map<String, dynamic> req) FlowRequestInfo(request: req),
        body,
      ]),
    );
  }

  /// Ghi chú (câu hỏi của bước chờ đang mở hoặc kết quả cuối) và các nút / lựa chọn đang mở của tiến trình.
  List<Widget> _pending(Pal pal, FlowProcess p) {
    final note = p.note;
    final entries = _entries(p);
    final mine = p.myTasks;
    final prompts = {for (final e in entries) '${e['prompt'] ?? ''}'.trim()};
    return [
      if (note.isNotEmpty && !prompts.contains(note))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: pal.text.withValues(alpha: .05), borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.sticky_note_2_outlined, size: 18, color: pal.sub),
              const SizedBox(width: 8),
              Expanded(child: SelectableText(note, style: TextStyle(fontSize: 13.5, height: 1.35, color: pal.text))),
            ]),
          ),
        ),
      if (entries.isNotEmpty || mine.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: FlowNextStep(children: [for (final t in mine) _myTask(pal, t), for (final e in entries) _pendingEntry(pal, p, e)]),
        ),
    ];
  }

  Widget _pendingEntry(Pal pal, FlowProcess p, Map<String, dynamic> e) {
    final prompt = '${e['prompt'] ?? ''}'.trim();
    final buttons = [for (final x in (e['actions'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
    final choices = e['choices'] is Map ? (e['choices'] as Map).cast<String, dynamic>() : null;
    // Phẳng: nằm trong khung "Bước tiếp theo" (một khung duy nhất), không viền riêng.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (prompt.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(prompt, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text))),
        if (choices != null && choices['options'] is List)
          FlygoChoices(choices: choices, accent: pal.accent, pal: pal, onAction: (a) => _act(p, a)),
        if (buttons.isNotEmpty) ...[
          if (choices != null) const SizedBox(height: 8),
          flygoCardButtons(buttons, accent: pal.accent, pal: pal, onAction: (a) => _act(p, a)),
        ],
      ]),
    );
  }

  Widget _section(Pal pal, String title, List<Widget> children, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .3, color: pal.sub))),
            ?trailing,
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  Widget _header(Pal pal, FlowProcess p) {
    final tone = processToneColor(p.tone, processStateColor(p.state));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        processIconBox(pal, p, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(p.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: pal.text, height: 1.25)),
            const SizedBox(height: 4),
            // Không hiện mã / khoá (người dùng không cần); hỗ trợ dùng "Sao chép mã" ở menu.
            Text(p.flowName, style: TextStyle(fontSize: 12.5, color: pal.sub)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ProcessChip(text: processStateLabel(p.state), color: processStateColor(p.state), solid: true),
              if (p.statusText.isNotEmpty) ProcessChip(text: p.statusText, color: tone),
              if (returnCount(p) case final n when n > 0) ProcessChip(text: tr('Bị trả lại {0} lần', [n]), color: kFlowOrange),
            ]),
            // Nhãn trạng thái nhiều dòng / dài (vd lý do lỗi): viên tròn một dòng, đủ nội dung ở đây.
            if (p.statusText.contains('\n') || p.statusText.length > 60)
              Container(
                key: const ValueKey('status-full'),
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(color: tone.withValues(alpha: .08), borderRadius: BorderRadius.circular(10)),
                child: SelectableText(p.statusText, style: TextStyle(fontSize: 13, color: pal.text, height: 1.35)),
              ),
            // Tiến độ (bước Báo tiến độ) của luồng đang chạy.
            if (p.progress != null && !p.finished) FlowProgressBar(progress: p.progress),
            const SizedBox(height: 6),
            Text(
              [
                tr('Tạo {0}', [_when(p.createdAt)]),
                if (p.finishedAt > 0) tr('kết thúc {0}', [_when(p.finishedAt)]) else if (p.updatedAt > p.createdAt) tr('cập nhật {0}', [_when(p.updatedAt)]),
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: pal.sub),
            ),
          ]),
        ),
      ]),
    );
  }

  /// Các bước cố định + lịch sử gộp thành một đường thời gian. Sự kiện xếp vào bước đang diễn ra lúc đó (sự kiện
  /// chuyển bước thuộc bước được chuyển tới; trước bước đầu: nút "Tạo tiến trình"); "Bước tiếp theo" dưới bước hiện tại.
  Widget _rail(Pal pal, FlowProcess p, List<Map<String, dynamic>> events) {
    final keys = [for (final st in p.steps) '${st['key']}'];
    final idx = {for (final (i, k) in keys.indexed) k: i};
    // Chia sự kiện theo lượt: mỗi lần chuyển về một bước đứng trước bước đang làm (bị trả lại) mở một lượt mới.
    final segs = <List<(String?, Map<String, dynamic>)>>[[]];
    final returns = <(int, int, Map<String, dynamic>)>[]; // (bước trả về, bước bị trả lại, sự kiện)
    String? cur;
    for (final e in events) {
      final kind = '${e['kind'] ?? ''}';
      final d = e['data'] is Map ? (e['data'] as Map) : const {};
      if (kind == 'create' || kind == 'created') {
        segs.last.add((null, e));
        if (keys.isNotEmpty) cur = keys.first;
        continue;
      }
      final k = '${d['step'] ?? ''}';
      if (kind == 'step' && idx.containsKey(k)) {
        if (cur != null && idx[k]! < idx[cur]!) {
          returns.add((idx[k]!, idx[cur]!, e));
          segs.add([]);
        }
        cur = k;
        segs.last.add((k, e));
        continue;
      }
      if ((kind == 'fail' || kind == 'failed') && idx.containsKey(k)) {
        segs.last.add((k, e));
        continue;
      }
      segs.last.add((cur, e));
    }
    final next = _nextBox(pal, p);
    final placed = next != null && !p.finished && keys.contains(p.currentStep);
    List<Widget> evs(List<(String?, Map<String, dynamic>)> seg, String? key, {bool start = false}) =>
        [for (final (k, e) in seg) if (k == key) _event(pal, p, e, showTitle: !start)];
    FlowRailNode stepNode(int i, List<(String?, Map<String, dynamic>)> seg, {String? state, bool current = false}) {
      final st = p.steps[i];
      final k = keys[i];
      final overdue = st['overdue'] == true;
      final due = (st['due_at'] as num?)?.toInt() ?? 0;
      final live = '${st['state']}' == 'active' && (state == null || state == 'active');
      return FlowRailNode(
        key: current ? ValueKey('rail-$k') : null,
        state: state ?? '${st['state'] ?? 'pending'}',
        title: '${st['title'] ?? k}',
        badge: overdue ? tr('Quá hạn') : null,
        detail: live && due > 0 ? tr('Hạn: {0}', [_when(due)]) : null,
        children: [
          ...evs(seg, k),
          if (current && placed && k == p.currentStep) ...[const SizedBox(height: 2), next],
        ],
      );
    }

    final startNode = FlowRailNode(state: 'done', title: tr('Tạo tiến trình'), children: evs(segs.first, null, start: true));
    final Widget body;
    if (returns.isEmpty) {
      body = FlowRail(nodes: [startNode, for (var i = 0; i < keys.length; i++) stepNode(i, segs.first, current: true)]);
    } else {
      // Bước thấp nhất có sự kiện trong một lượt (lượt sau có thể quay về sâu hơn lượt trước).
      int low(int r, int target) => [target, for (final (k, _) in segs[r]) if (k != null) idx[k]!].reduce((a, b) => a < b ? a : b);
      final first = low(0, returns.first.$1);
      final lastTarget = low(returns.length, returns.last.$1);
      body = FlowRounds(
        prefix: [startNode, for (var i = 0; i < first; i++) stepNode(i, segs.first, state: 'done')],
        rounds: [
          for (final (r, (target, from, e)) in returns.indexed)
            FlowRound(
              nodes: [for (var i = low(r, target); i <= from; i++) stepNode(i, segs[r], state: 'done')],
              ret: _returnInfo(p, keys, target, e),
            ),
        ],
        current: [for (var i = lastTarget; i < keys.length; i++) stepNode(i, segs.last, current: true)],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        body,
        if (next != null && !placed) ...[const SizedBox(height: 14), next],
      ]),
    );
  }

  FlowReturnInfo _returnInfo(FlowProcess p, List<String> keys, int target, Map<String, dynamic> e) {
    final d = e['data'] is Map ? (e['data'] as Map) : const {};
    final r = d['returned'] is Map ? (d['returned'] as Map) : const {};
    final by = '${r['by'] ?? ''}';
    final at = (r['at'] as num?)?.toInt() ?? (e['at'] as num?)?.toInt() ?? 0;
    final reason = '${r['reason'] ?? ''}'.trim();
    return FlowReturnInfo(
      step: '${p.steps[target]['title'] ?? keys[target]}',
      who: by.isEmpty || by == 'null' ? _actor(e) : _who(by),
      when: _when(at),
      reason: reason == 'null' ? '' : reason,
    );
  }

  /// BẢN MẪU thảo luận: cột 1 là toàn cảnh tiến trình (đầu trang, thống kê, nhãn, đường thời gian, tệp...), cột 2 chỉ
  /// có thảo luận (rộng ~360–400px). Vùng chi tiết hẹp hơn ~760px: một cột với 2 tab "Tiến trình | Thảo luận (n)".
  Widget _withDiscussion(Pal pal, FlowProcess p, BoxConstraints box, List<Widget> overview) {
    final col1 = RefreshIndicator(
      onRefresh: _load,
      child: ListView(key: const ValueKey('process-timeline'), padding: const EdgeInsets.only(bottom: 32), children: overview),
    );
    ProcessDiscussion chat({bool active = true}) => ProcessDiscussion(
          key: ValueKey('discussion-${p.id}'),
          app: widget.app,
          processId: p.id,
          when: _when,
          stepOf: (at) => _stepAt(p, at),
          active: active,
          onFilesChanged: _load,
          onCount: (n) {
            if (mounted && n != _discCount) setState(() => _discCount = n);
          },
          onForbidden: () {
            if (mounted) setState(() => _noDiscussion = true);
          },
        );
    if (box.maxWidth < 760) {
      // Hai tab; cả hai luôn dựng (IndexedStack) để biết ngay người xem có được thảo luận không và đếm số tin.
      return DefaultTabController(
        length: 2,
        initialIndex: widget.initialTab.clamp(0, 1),
        child: Builder(builder: (ctx) {
          final tabs = DefaultTabController.of(ctx);
          return Column(children: [
            TabBar(tabs: [
              Tab(height: 42, text: tr('Tiến trình')),
              Tab(height: 42, text: _discCount == null ? tr('Thảo luận') : tr('Thảo luận ({0})', [_discCount])),
            ]),
            Expanded(
              child: AnimatedBuilder(
                animation: tabs,
                // Vuốt trái / phải để đổi giữa Tiến trình và Thảo luận.
                builder: (_, _) => GestureDetector(
                  key: const ValueKey('process-tabs-swipe'),
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -250 && tabs.index == 0) tabs.animateTo(1);
                    if (v > 250 && tabs.index == 1) tabs.animateTo(0);
                  },
                  child: IndexedStack(index: tabs.index, children: [col1, chat(active: tabs.index == 1)]),
                ),
              ),
            ),
          ]);
        }),
      );
    }
    // Cột thảo luận kéo được (lưu theo tài khoản); bấm đúp vạch ngăn để về mặc định.
    final maxW = (box.maxWidth - 360).clamp(300.0, double.infinity);
    final w = (_chatW ?? (box.maxWidth * .36).clamp(360.0, 400.0)).clamp(300.0, maxW);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: col1),
      ColumnResizer(
        key: const ValueKey('process-chat-resizer'),
        onDrag: (dx) => setState(() => _chatW = (w - dx).clamp(300.0, maxW)),
        onDragEnd: () => widget.app.setUiPref(_chatPref, _chatW),
        onReset: () {
          setState(() => _chatW = null);
          widget.app.setUiPref(_chatPref, null);
        },
      ),
      SizedBox(width: w, child: chat()),
    ]);
  }

  /// Bước đang diễn ra lúc [at] (theo các sự kiện chuyển bước); không xác định được thì rỗng.
  String _stepAt(FlowProcess p, int at) {
    final keys = [for (final st in p.steps) '${st['key']}'];
    if (keys.isEmpty) return '';
    String? cur;
    final evs = [...p.events]..sort((a, b) => ((a['at'] as num?) ?? 0).compareTo((b['at'] as num?) ?? 0));
    for (final e in evs) {
      if (((e['at'] as num?) ?? 0) > at) break;
      if (e['kind'] == 'create' || e['kind'] == 'created') cur ??= keys.first;
      final k = '${(e['data'] is Map ? e['data']['step'] : null) ?? ''}';
      if (e['kind'] == 'step' && keys.contains(k)) cur = k;
    }
    if (cur == null) return '';
    final st = p.steps[keys.indexOf(cur)];
    return '${st['title'] ?? cur}';
  }

  /// Số lần bị trả lại (chuyển về một bước đứng trước bước đang làm).
  static int returnCount(FlowProcess p) {
    final keys = [for (final st in p.steps) '${st['key']}'];
    var cur = keys.isEmpty ? -1 : 0, n = 0;
    final evs = [...p.events]..sort((a, b) => ((a['at'] as num?) ?? 0).compareTo((b['at'] as num?) ?? 0));
    for (final e in evs) {
      if (e['kind'] != 'step') continue;
      final i = keys.indexOf('${(e['data'] as Map?)?['step'] ?? ''}');
      if (i < 0) continue;
      if (i < cur) n++;
      cur = i;
    }
    return n;
  }


  /// Thao tác đang chờ (kèm ghi chú) trong một khung "Bước tiếp theo"; không có thì null.
  Widget? _nextBox(Pal pal, FlowProcess p) {
    final entries = _entries(p);
    final mine = p.myTasks;
    if (entries.isEmpty && mine.isEmpty) return null;
    final note = p.note;
    final prompts = {for (final e in p.actions) '${e['prompt'] ?? ''}'.trim()};
    return FlowNextStep(children: [
      if (note.isNotEmpty && !prompts.contains(note))
        Padding(padding: const EdgeInsets.only(bottom: 8), child: SelectableText(note, style: TextStyle(fontSize: 13.5, height: 1.35, color: pal.text))),
      for (final t in mine) _myTask(pal, t),
      for (final e in entries) _pendingEntry(pal, p, e),
    ]);
  }

  /// Huỷ tiến trình: hỏi lại (lý do, huỷ cả tiến trình con khi có), gọi máy chủ, báo kết quả rồi tải lại.
  Future<void> _cancel(FlowProcess p) async {
    final r = await showDialog<(String, bool)>(context: context, builder: (_) => ProcessCancelDialog(process: p));
    if (r == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await api.cancelProcess(p.id, reason: r.$1, cascade: r.$2);
      final n = (res['cancelled_children'] as num?)?.toInt() ?? 0;
      messenger.showSnackBar(toast(Text(n > 0 ? tr('Đã huỷ tiến trình và {0} tiến trình con', [n]) : tr('Đã huỷ tiến trình'))));
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không huỷ được: {0}', ['$e']))));
    }
    if (mounted) _load();
  }

  /// "Đang chờ 2/3 tiến trình con" (bước Chờ tiến trình của một luồng đang chờ).
  Widget? _waiting(Pal pal, FlowProcess p) {
    final t = p.waitingText;
    if (t.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        key: const ValueKey('process-waiting'),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(color: kProcessBlue.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.hourglass_top_rounded, size: 18, color: kProcessBlue),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text))),
        ]),
      ),
    );
  }

  /// Thuộc tính (tên theo dòng khai báo trên thẻ, không có thì khoá).
  Widget? _props(Pal pal, FlowProcess p) {
    final props = {for (final e in p.props.entries) if (e.value.trim().isNotEmpty) e.key: e.value};
    if (props.isEmpty) return null;
    return _section(pal, tr('Thuộc tính'), [
      for (final e in props.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(p.propLabel(e.key), style: TextStyle(fontSize: 13, color: pal.sub))),
            Expanded(child: SelectableText(e.value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text))),
            if (p.propsLink.contains(e.key)) Icon(Icons.link_rounded, size: 16, color: pal.sub),
          ]),
        ),
    ]);
  }

  /// Một tiến trình liên quan (cha / con / cùng thuộc tính): biểu tượng, tên, trạng thái, bước hiện tại. Bấm để mở.
  Widget _relatedTile(Pal pal, FlowProcess x, {bool showFlow = true}) {
    final step = x.currentStepTitle;
    final tone = processToneColor(x.tone, processStateColor(x.state));
    final sub = [if (showFlow) x.flowName, if (step.isNotEmpty) tr('Bước: {0}', [step]), if (x.waitingText.isNotEmpty) x.waitingText];
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openProcess(context, widget.app, x.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          processIconBox(pal, x, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
              if (sub.isNotEmpty) Text(sub.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub)),
            ]),
          ),
          const SizedBox(width: 6),
          ProcessChip(text: x.statusText.isNotEmpty && !x.finished ? x.statusText : processStateLabel(x.state), color: x.statusText.isNotEmpty && !x.finished ? tone : processStateColor(x.state)),
          Icon(Icons.chevron_right_rounded, size: 18, color: pal.sub),
        ]),
      ),
    );
  }

  /// Mục "Liên quan": tiến trình cha, tiến trình con (theo quy trình), tiến trình của quy trình khác có cùng thuộc
  /// tính liên kết.
  Widget? _related(Pal pal, FlowProcess p) {
    final parent = p.parent;
    final children = p.children;
    final related = [for (final g in p.related) if (g.$4.isNotEmpty) g];
    if (parent == null && children.isEmpty && related.isEmpty) return null;
    Widget sub(String t) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 2), child: Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: pal.sub)));
    final byFlow = <String, List<FlowProcess>>{};
    for (final c in children) {
      (byFlow[c.flowName] ??= []).add(c);
    }
    String count(List<FlowProcess> l) {
      final done = l.where((x) => x.state == 'done').length;
      return done == 0 ? '${l.length}' : tr('{0}/{1} xong', [done, l.length]);
    }

    return KeyedSubtree(
      key: const ValueKey('process-related'),
      child: _section(pal, tr('Liên quan'), [
        if (parent != null) ...[sub(tr('Tiến trình cha')), _relatedTile(pal, parent)],
        for (final e in byFlow.entries) ...[
          sub('${tr('Tiến trình con')} · ${e.key} (${count(e.value)})'),
          for (final c in e.value) _relatedTile(pal, c, showFlow: false),
        ],
        for (final g in related) ...[
          sub(tr('Cùng {0}: {1}', [g.$2, g.$3])),
          for (final x in g.$4) _relatedTile(pal, x),
        ],
      ]),
    );
  }

  Widget _stats(Pal pal, FlowProcess p) => LayoutBuilder(builder: (ctx, c) {
        final cols = c.maxWidth >= 520 ? 3 : 2;
        final w = (c.maxWidth - 8 * (cols - 1)) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in p.stats)
            Container(
              width: w,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(color: pal.text.withValues(alpha: .05), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['label'] ?? s['key']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: pal.sub, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(processStatValue(s['value']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: s['type'] == 'text' ? 14 : 18, fontWeight: FontWeight.w800, color: pal.text)),
              ]),
            ),
        ]);
      });

  Widget _file(Pal pal, Map<String, dynamic> f) {
    final kind = '${f['kind'] ?? 'file'}';
    final icon = switch (kind) { 'link' => Icons.link_rounded, 'folder' => Icons.folder_outlined, _ => Icons.insert_drive_file_outlined };
    final url = '${f['url'] ?? ''}';
    final sub = [
      if (kind == 'link' && url.isNotEmpty) Uri.tryParse(url)?.host ?? url,
      _size(f['size'] as num?),
      _when((f['at'] as num?)?.toInt() ?? 0),
    ].where((x) => x.isNotEmpty).join(' · ');
    final openable = '${f['file_id'] ?? ''}'.isNotEmpty || url.isNotEmpty;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, color: pal.accentText),
      title: Text('${f['name'] ?? (url.isEmpty ? f['file_id'] : url)}', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: openable ? Icon(kind == 'file' ? Icons.download_rounded : Icons.open_in_new_rounded, size: 20, color: pal.sub) : null,
      onTap: openable ? () => _openFile(f) : null,
    );
  }

  Widget _post(Pal pal, Map<String, dynamic> x) {
    final ch = '${x['channel_id'] ?? ''}', user = '${x['user_id'] ?? ''}', postId = '${x['post_id'] ?? ''}';
    final c = ch.isEmpty ? null : widget.app.channels[ch];
    final where = user.isNotEmpty
        ? tr('Tin nhắn riêng: {0}', [_who(user)])
        : c != null
            ? tr('Nhóm: {0}', [c.displayName.isNotEmpty ? c.displayName : c.name])
            : (ch.isEmpty ? tr('Thẻ đã gửi') : tr('Kênh {0}', [ch]));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.style_outlined, color: pal.accentText),
      title: Text(where, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(x['sync'] == false ? tr('Không tự cập nhật') : tr('Tự cập nhật theo tiến trình')),
      trailing: postId.isEmpty ? null : Icon(Icons.chevron_right_rounded, color: pal.sub),
      onTap: postId.isEmpty ? null : () => openSourceMessage(context, widget.app, postId),
    );
  }

  /// Một sự kiện trong lịch sử, viết cho người đọc: (tiêu đề, dòng chi tiết). Không hiện khoá thô / mã bước.
  (String, List<String>) _eventText(FlowProcess p, Map<String, dynamic> e) {
    final kind = '${e['kind'] ?? ''}';
    final raw = e['data'];
    final d = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    String stepTitle(Object? key) {
      final k = '${key ?? ''}';
      for (final st in p.steps) {
        if ('${st['key']}' == k) return '${st['title'] ?? ''}'.trim().isEmpty ? k : '${st['title']}';
      }
      return k;
    }

    String text(Object? v) => v == null || '$v' == 'null' ? '' : '$v'.trim();
    String statLabel(String key) {
      for (final st in p.stats) {
        if ('${st['key']}' == key) return '${st['label'] ?? ''}'.trim().isEmpty ? key : '${st['label']}';
      }
      return key;
    }

    switch (kind) {
      case 'create' || 'created':
        return (tr('Tạo tiến trình'), const []);
      case 'step':
        final title = stepTitle(d['step']);
        return (
          title.isEmpty ? tr('Chuyển bước') : (d['skip'] == true ? tr('Bỏ qua tới bước «{0}»', [title]) : tr('Chuyển sang bước «{0}»', [title])),
          [if (text(d['status_text']).isNotEmpty) text(d['status_text'])],
        );
      case 'stat' || 'stats':
        final lines = <String>[];
        if (raw is List) {
          for (final x in raw) {
            // Thống kê nội bộ (khoá bắt đầu bằng _, vd _loi_lan / _cho_phut): không hiện (Sếp, 2026-11-11).
            if (x is Map && '${x['key'] ?? ''}'.startsWith('_')) continue;
            if (x is Map) lines.add('${'${x['label'] ?? ''}'.trim().isEmpty ? statLabel('${x['key']}') : x['label']}: ${processStatValue(x['value'])}');
          }
        } else if (raw is Map) {
          for (final x in raw.entries) {
            if ('${x.key}'.startsWith('_')) continue;
            lines.add('${statLabel('${x.key}')}: ${processStatValue(x.value is Map ? (x.value as Map)['value'] : x.value)}');
          }
        }
        return (tr('Cập nhật thống kê'), lines);
      case 'fail' || 'failed':
        final at = stepTitle(d['step']);
        return (at.isEmpty ? tr('Báo lỗi') : tr('Báo lỗi ở bước «{0}»', [at]), [if (text(d['reason']).isNotEmpty) text(d['reason'])]);
      case 'finish' || 'finished':
        final r = text(d['result']);
        return (r.isEmpty ? tr('Kết thúc') : tr('Kết thúc: {0}', [processStateLabel(r)]), [if (text(d['summary']).isNotEmpty) text(d['summary'])]);
      case 'label' || 'labels':
        List<String> l(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
        return (tr('Đổi nhãn'), [
          if (l(d['add']).isNotEmpty) tr('Thêm: {0}', [l(d['add']).join(', ')]),
          if (l(d['remove']).isNotEmpty) tr('Bỏ: {0}', [l(d['remove']).join(', ')]),
        ]);
      case 'attach':
        final names = [for (final f in (d['files'] as List? ?? const [])) if (f is Map) text(f['name']) else text(f)].where((x) => x.isNotEmpty).toList();
        return (tr('Đính kèm'), [if (names.isNotEmpty) names.join(', ')]);
      case 'send' || 'sent':
        final n = (d['posts'] as List?)?.length ?? 0;
        return (tr('Gửi thẻ'), [if (n > 1) tr('{0} nơi nhận', [n])]);
      case 'action_open':
        return (tr('Chờ thao tác'), [if (text(d['note']).isNotEmpty) text(d['note'])]);
      case 'action_close':
        return (tr('Đã xử lý thao tác'), [if (text(d['note']).isNotEmpty) text(d['note'])]);
      case 'status':
        return (tr('Đổi trạng thái'), [if (text(d['status_text']).isNotEmpty) text(d['status_text'])]);
      default:
        // Loại lạ: chỉ hiện các giá trị chữ, không hiện tên khoá.
        return (tr('Cập nhật'), [for (final x in d.entries) if (!x.key.startsWith('_') && x.value is String && (x.value as String).trim().isNotEmpty) (x.value as String).trim()]);
    }
  }

  /// Ai làm: tên người, hoặc "Quy trình" khi chính quy trình (bước tự động) ghi.
  String _actor(Map<String, dynamic> e) {
    final a = '${e['actor'] ?? ''}';
    if (a.isEmpty || a == 'null' || a == 'flow' || a == 'flowbot') return tr('Quy trình');
    if (a == widget.app.me?.id) return _who(a);
    final u = widget.app.users[a];
    if (u == null && a.length != 26) return tr('Quy trình');
    return _who(a);
  }

  Widget _event(Pal pal, FlowProcess p, Map<String, dynamic> e, {bool showTitle = true}) {
    final (title, lines) = _eventText(p, e);
    // Sự kiện chỉ đổi thống kê nội bộ (_…): ẩn hẳn, không để lại dòng "Cập nhật thống kê" trống.
    if ((e['kind'] == 'stat' || e['kind'] == 'stats') && lines.isEmpty) return const SizedBox.shrink();
    final step = '${e['node_name'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 5), child: Icon(Icons.circle, size: 7, color: pal.sub)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showTitle) Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: pal.text)),
            for (final l in lines) Text(l, maxLines: 12, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.text)),
            Text(
              [_when((e['at'] as num?)?.toInt() ?? 0), _actor(e), if (step.isNotEmpty && step != 'null') step].where((x) => x.isNotEmpty).join(' · '),
              style: TextStyle(fontSize: 12, color: pal.sub),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = _p;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(leading: flowLeading(context), title: Text(tr('Tiến trình'))),
        body: Center(
          child: _err == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('Không tải được tiến trình: {0}', [_err]), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
                  ]),
                ),
        ),
      );
    }
    // Quá trình chạy theo thứ tự thời gian (cũ trước), bước tiếp theo (thao tác đang chờ) nằm cuối.
    final events = [...p.events]..sort((a, b) => ((a['at'] as num?) ?? 0).compareTo((b['at'] as num?) ?? 0));
    return Scaffold(
      appBar: AppBar(
        leading: flowLeading(context),
        title: Text(tr('Tiến trình')),
        actions: [
          IconButton(
            tooltip: tr('Báo cáo'),
            onPressed: () => openProcessReport(context, widget.app, p.flowId, p.flowName),
            icon: const Icon(Icons.insights_rounded),
          ),
          IconButton(tooltip: tr('Tải lại'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          PopupMenuButton<String>(
            tooltip: tr('Thêm'),
            onSelected: (v) => v == 'cancel' ? _cancel(p) : copyFlowCodes(context, [
              ('process', p.id),
              if (p.key.isNotEmpty) ('key', p.key),
              if (p.instanceId.isNotEmpty) ('instance', p.instanceId),
              ('flow', p.flowId),
              if (p.currentStep.isNotEmpty) ('step', p.currentStep),
            ]),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: const Icon(Icons.copy_rounded), title: Text(tr('Sao chép mã')))),
              if (p.canCancel)
                PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(dense: true, leading: const Icon(Icons.cancel_outlined, color: kFlowRed), title: Text(tr('Huỷ tiến trình'), style: const TextStyle(color: kFlowRed))),
                ),
            ],
          ),
        ],
      ),
      // Vùng rộng (từ 720px, theo bề rộng thật của vùng chi tiết): 2 cột, trái là quá trình chạy (các bước, lịch sử),
      // phải là thông tin kèm theo (nhãn, thống kê, tệp, thẻ đã gửi, tiến trình gốc). Thao tác đang chờ là "Bước tiếp theo" ở
      // cuối quá trình chạy. Hẹp: một cột, cùng thứ tự.
      body: LayoutBuilder(builder: (context, box) {
        final header = _header(pal, p);
        // Có các bước cố định: một đường thời gian gộp bước + lịch sử + bước tiếp theo. Không có: lịch sử theo thời gian,
        // bước tiếp theo ở cuối.
        final rail = p.steps.isEmpty ? null : _rail(pal, p, events);
        final history = p.steps.isNotEmpty || events.isEmpty ? null : _section(pal, tr('Lịch sử'), [for (final e in events) _event(pal, p, e)]);
        final labels = p.labels.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 6, runSpacing: 6, children: [for (final l in p.labels) ProcessLabel(l)]),
              );
        final pending = p.steps.isEmpty ? _pending(pal, p) : const <Widget>[];
        final waiting = _waiting(pal, p);
        final props = _props(pal, p);
        final related = _related(pal, p);
        // Thống kê dạng ô ở đầu trang (báo cáo của tiến trình).
        final stats = p.stats.isEmpty ? null : Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0), child: _stats(pal, p));
        final files = p.files.isEmpty ? null : _section(pal, tr('Tệp và liên kết'), [for (final f in p.files) _file(pal, f)]);
        final posts = p.posts.isEmpty ? null : _section(pal, tr('Thẻ đã gửi'), [for (final x in p.posts) _post(pal, x)]);
        if (box.maxWidth < 720) {
          final list = RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [header, ?waiting, ?stats, ?props, ?labels, ?rail, ?history, ...pending, ?related, ?files, ?posts]),
          );
          if (!_noDiscussion) return _withDiscussion(pal, p, box, [header, ?waiting, ?stats, ?props, ?labels, ?rail, ?history, ...pending, ?related, ?files, ?posts]);
          return list;
        }
        if (!_noDiscussion) return _withDiscussion(pal, p, box, [header, ?waiting, ?stats, ?props, ?labels, ?rail, ?history, ...pending, ?related, ?files, ?posts]);
        // Báo cáo của tiến trình (thống kê, thông tin) ở đầu, các bước bên dưới (Sếp 12/11).
        final timeline = [header, ?waiting, ?stats, ?props, ?rail, ?history, ...pending, ?related];
        final side = [?labels, ?files, ?posts];
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 3,
            child: RefreshIndicator(onRefresh: _load, child: ListView(key: const ValueKey('process-timeline'), padding: const EdgeInsets.only(bottom: 32), children: timeline)),
          ),
          VerticalDivider(width: 1, color: pal.divider),
          Expanded(
            flex: 2,
            child: Material(
              color: Color.alphaBlend(pal.surface2.withValues(alpha: .35), pal.bg),
              child: ListView(key: const ValueKey('process-actions'), padding: const EdgeInsets.only(bottom: 32), children: side),
            ),
          ),
        ]);
      }),
    );
  }
}

/// Chấm trạng thái một bước (như thẻ flygo_card): xong (tích xanh), đang làm (vòng màu chủ đạo), lỗi (X đỏ),
/// bỏ qua (gạch), chưa tới (vòng xám).
class ProcessStepDot extends StatelessWidget {
  final String state;
  const ProcessStepDot({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final accent = pal.accentText;
    return switch (state) {
      'done' => Container(width: 20, height: 20, decoration: const BoxDecoration(color: kFlowGreen, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 14, color: Colors.white)),
      'failed' => Container(width: 20, height: 20, decoration: const BoxDecoration(color: kFlowRed, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white)),
      'active' => Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent, width: 2), color: accent.withValues(alpha: .15)),
          child: Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle))),
        ),
      'skipped' => Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: pal.text.withValues(alpha: .08)),
          child: Icon(Icons.remove_rounded, size: 14, color: pal.sub)),
      _ => Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.text.withValues(alpha: .25), width: 2))),
    };
  }
}

/// Khối "Bước tiếp theo" ở cuối quá trình chạy: việc đang chờ (nút Đồng ý / Từ chối, lựa chọn...), viền màu chủ đạo
/// để người xem biết đây là bước sắp làm.
class FlowNextStep extends StatelessWidget {
  final List<Widget> children;
  const FlowNextStep({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      key: const ValueKey('next-step'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(color: pal.accent.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.arrow_circle_right_rounded, size: 16, color: pal.accentText),
          const SizedBox(width: 8),
          Text(tr('Bước tiếp theo'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: .2, color: pal.accentText)),
        ]),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }
}

/// Một nút trên đường thời gian [FlowRail]: một bước (hoặc "Tạo tiến trình") cùng những gì đã xảy ra ở bước đó.
class FlowRailNode {
  /// done | active | failed | skipped | pending (chưa tới: mờ).
  final String state;
  final String title;
  /// Chữ nhỏ cạnh tiêu đề (vd thời gian chạy của bước).
  final String? detail;
  final List<Widget> children;
  final Key? key;
  /// Nhãn màu cạnh tiêu đề (vd "Quá hạn" màu cam).
  final String? badge;
  final Color? badgeColor;
  const FlowRailNode({required this.state, required this.title, this.detail, this.children = const [], this.key, this.badge, this.badgeColor});
}

/// Đường thời gian gộp các bước và lịch sử: mỗi bước là một nút trên trục (xong: tích, đang làm: tô màu, chưa tới:
/// mờ), dưới mỗi nút là các sự kiện ở bước đó; "Bước tiếp theo" (thao tác đang chờ) nằm ngay dưới bước hiện tại.
class FlowRail extends StatelessWidget {
  final List<FlowRailNode> nodes;
  /// Lượt cũ (đã bị trả lại): trục xám.
  final bool muted;
  const FlowRail({super.key, required this.nodes, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Column(key: muted ? null : const ValueKey('flow-rail'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, n) in nodes.indexed)
        Opacity(
          key: n.key,
          opacity: n.state == 'pending' ? .5 : 1,
          child: Stack(children: [
            if (i < nodes.length - 1)
              Positioned(
                left: 12,
                top: 23,
                bottom: 0,
                child: Container(width: 2, color: n.state == 'done' && !muted ? kFlowGreen.withValues(alpha: .6) : pal.text.withValues(alpha: .14)),
              ),
            Padding(
              padding: EdgeInsets.only(bottom: i < nodes.length - 1 ? 14 : 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 26, child: Center(child: ProcessStepDot(state: n.state))),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                          text: n.title,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.25,
                            fontWeight: n.state == 'active' ? FontWeight.w800 : FontWeight.w700,
                            color: switch (n.state) {
                              'active' => pal.accentText,
                              'failed' => kFlowRed,
                              'pending' || 'skipped' => pal.sub,
                              _ => pal.text,
                            },
                            decoration: n.state == 'skipped' ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (n.state == 'skipped') TextSpan(text: '  ${tr('bỏ qua')}', style: TextStyle(fontSize: 12, color: pal.sub)),
                        if (n.detail != null && n.detail!.isNotEmpty) TextSpan(text: '  · ${n.detail}', style: TextStyle(fontSize: 12, color: pal.sub)),
                        if (n.badge != null)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(padding: const EdgeInsets.only(left: 8), child: ProcessChip(text: n.badge!, color: n.badgeColor ?? kFlowOrange)),
                          ),
                      ])),
                    ),
                    if (n.children.isNotEmpty) ...[const SizedBox(height: 8), ...n.children],
                  ]),
                ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// Một lần bị trả lại: về bước nào, ai trả lại, lúc nào, lý do.
class FlowReturnInfo {
  final String step, who, when, reason;
  const FlowReturnInfo({required this.step, required this.who, required this.when, required this.reason});
}

/// Một lượt cũ: các bước đã chạy từ bước được trả về tới lúc bị trả lại.
class FlowRound {
  final List<FlowRailNode> nodes;
  final FlowReturnInfo ret;
  const FlowRound({required this.nodes, required this.ret});
}

/// Đường thời gian có các lượt bị trả lại: phần trước bước được trả về (bình thường), các lượt cũ (mờ, trục xám, nhãn
/// "Lượt n"; từ 2 lượt cũ trở lên thì thu gọn mỗi lượt một dòng, bấm để mở), sau mỗi lượt một dòng cam "Bị trả lại về
/// «bước»", rồi lượt hiện tại (bình thường, có "Bước tiếp theo").
class FlowRounds extends StatefulWidget {
  final List<FlowRailNode> prefix;
  final List<FlowRound> rounds;
  final List<FlowRailNode> current;
  const FlowRounds({super.key, required this.prefix, required this.rounds, required this.current});
  @override
  State<FlowRounds> createState() => _FlowRoundsState();
}

class _FlowRoundsState extends State<FlowRounds> {
  final _open = <int>{};

  Widget _returnRow(Pal pal, FlowReturnInfo r, int i) => Container(
        key: ValueKey('return-$i'),
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
        decoration: BoxDecoration(color: kFlowOrange.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 1), child: Icon(Icons.undo_rounded, size: 18, color: kFlowOrange)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Bị trả lại về «{0}»', [r.step]), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: kFlowOrange)),
              Text([r.who, r.when].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(fontSize: 12, color: pal.sub)),
              if (r.reason.isNotEmpty) Text('“${r.reason}”', style: TextStyle(fontSize: 13, color: pal.text, height: 1.35)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final collapse = widget.rounds.length >= 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.prefix.isNotEmpty) ...[FlowRail(nodes: widget.prefix), const SizedBox(height: 10)],
      for (final (i, r) in widget.rounds.indexed) ...[
        if (collapse && !_open.contains(i))
          InkWell(
            key: ValueKey('round-$i'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open.add(i)),
            child: Opacity(
              opacity: .6,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(Icons.history_rounded, size: 18, color: pal.sub),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: tr('Lượt {0}', [i + 1]), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                      TextSpan(text: ' · ${tr('bị trả lại {0} bởi {1}', [r.ret.when, r.ret.who])} · ', style: TextStyle(color: pal.sub)),
                      TextSpan(text: tr('Xem'), style: TextStyle(color: pal.accentText, fontWeight: FontWeight.w600)),
                    ]), style: const TextStyle(fontSize: 12.5)),
                  ),
                ]),
              ),
            ),
          )
        else ...[
          Opacity(
            key: ValueKey('round-$i'),
            opacity: .45,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Text(tr('Lượt {0}', [i + 1]).toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .4, color: pal.sub)),
                  if (collapse) ...[
                    const Spacer(),
                    InkWell(onTap: () => setState(() => _open.remove(i)), child: Text(tr('Thu gọn'), style: TextStyle(fontSize: 12, color: pal.accentText))),
                  ],
                ]),
              ),
              FlowRail(nodes: r.nodes, muted: true),
            ]),
          ),
        ],
        if (!collapse || _open.contains(i)) _returnRow(pal, r.ret, i) else const SizedBox(height: 2),
      ],
      if (widget.current.isNotEmpty) ...[const SizedBox(height: 4), FlowRail(nodes: widget.current)],
    ]);
  }
}

/// "Sao chép mã" (cho hỗ trợ): các mã nội bộ không hiện trên giao diện (mã tiến trình, khoá, mã luồng, mã bước...),
/// mỗi dòng `tên: giá trị`.
Future<void> copyFlowCodes(BuildContext context, List<(String, String)> codes) async {
  await Clipboard.setData(ClipboardData(text: [for (final (k, v) in codes) '$k: $v'].join('\n')));
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã sao chép mã'))));
}

/// Hỏi lại khi huỷ tiến trình: lý do (không bắt buộc), "Huỷ cả tiến trình con" khi tiến trình có con. Trả về (lý do,
/// huỷ cả con) hoặc null khi bấm Không.
class ProcessCancelDialog extends StatefulWidget {
  final FlowProcess process;
  const ProcessCancelDialog({super.key, required this.process});
  @override
  State<ProcessCancelDialog> createState() => _ProcessCancelDialogState();
}

class _ProcessCancelDialogState extends State<ProcessCancelDialog> {
  final _reason = TextEditingController();
  bool _cascade = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.process;
    final open = p.children.where((c) => !c.finished).length;
    return AlertDialog(
      title: Text(tr('Huỷ tiến trình?')),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('"{0}" sẽ thành Đã huỷ. Luồng đã tạo ra nó dừng các bước đang chờ và chạy các bước "Khi luồng bị huỷ" (nếu có).', [p.name])),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: tr('Lý do (không bắt buộc)'), border: const OutlineInputBorder()),
          ),
          if (p.children.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(tr('Huỷ cả tiến trình con')),
              subtitle: Text(open > 0 ? tr('{0} tiến trình con chưa xong (và tiến trình cháu)', [open]) : tr('Mọi tiến trình con đã xong')),
              value: _cascade,
              onChanged: (v) => setState(() => _cascade = v ?? false),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Không'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kFlowRed),
          onPressed: () => Navigator.pop(context, (_reason.text, _cascade)),
          child: Text(tr('Huỷ tiến trình')),
        ),
      ],
    );
  }
}
