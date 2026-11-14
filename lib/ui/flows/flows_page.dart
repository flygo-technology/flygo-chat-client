import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/flows_api.dart';
import '../../api/flows_live.dart';
import '../../config.dart' show isDesktop;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../open_file.dart';
import '../theme.dart';
import 'flow_card.dart' show decideFlowTask, kFlowGreen, kFlowOrange, kFlowRed;
import 'flow_form.dart';
import 'flow_logic.dart';
import 'flow_table.dart';
import 'flow_task_action.dart';
import 'flow_trace.dart';
import 'flows_admin.dart';
import 'flows_all.dart';
import 'flow_delegations.dart';
import 'flow_experimental.dart';
import 'flow_editor.dart' show canLeaveFlowEditor, openFlowEditor;
import 'flow_location.dart';
import 'flow_nav.dart';
import 'process_detail.dart' show FlowNextStep, FlowRail, FlowRailNode, FlowReturnInfo, FlowRound, FlowRounds, copyFlowCodes;
import 'process_board.dart';
import 'process_list.dart' show ProcessChip, ProcessesView, openProcessReport;
import '../home_page.dart' show ChatHost, PageCloser;
import '../location.dart' show mapsUrl;
import 'package:flygo_chat/ui/app_route.dart';

/// Quy trình (Flows): mỗi lần chạy một quy trình là một "luồng". Trang chính 2 tab (Đang chạy, Chờ duyệt),
/// trang tạo luồng mới (quy trình nhóm theo danh mục), trang chi tiết luồng; quản trị vào danh sách quy trình bằng nút cài đặt.

/// Mở trang Quy trình: máy tính mở ở vùng bên phải thanh bên (không chiếm toàn màn hình), điện thoại mở trang mới.
Future<void> openFlowsHome(BuildContext context, AppState app) => openFlowPage(context, 'flows-home', (_) => FlowsHome(app: app));

Future<void> openFlowInstance(BuildContext context, AppState app, String id) =>
    openFlowPage(context, 'instance-$id', (_) => FlowDetailPage(app: app, instanceId: id));

// ---------------------------------------------------------------------------------------------- tạo luồng từ tin nhắn

/// Quy trình có mục "Tạo luồng từ tin này" (nốt Bắt đầu "Từ một tin nhắn"), nhớ 5 phút theo máy chủ.
final _msgStarts = <String, (int, List<Map<String, dynamic>>)>{};
final _msgStartsLoading = <String>{};

/// Danh sách đã nhớ (menu tin nhắn đọc đồng bộ); cũ thì tải lại ở nền cho lần mở menu sau.
List<Map<String, dynamic>> messageStartsCached(AppState app) {
  final api = FlowsApi(app.token);
  final c = _msgStarts[api.server];
  final now = DateTime.now().millisecondsSinceEpoch;
  if ((c == null || now - c.$1 > 300000) && _msgStartsLoading.add(api.server)) {
    api.messageStarts().then((v) => _msgStarts[api.server] = (now, v)).catchError((_) => _msgStarts[api.server] = (now, const <Map<String, dynamic>>[])).whenComplete(
          () => _msgStartsLoading.remove(api.server),
        );
  }
  return c?.$2 ?? const [];
}

/// Menu tin nhắn → "Tạo luồng": chọn quy trình (nếu nhiều), biểu mẫu điền sẵn từ tin, người bấm sửa rồi gửi.
Future<void> startFlowFromPost(BuildContext context, AppState app, String postId) async {
  final api = FlowsApi(app.token);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final list = await api.messageStarts();
    _msgStarts[api.server] = (DateTime.now().millisecondsSinceEpoch, list);
    if (!context.mounted) return;
    if (list.isEmpty) {
      messenger.showSnackBar(toast(Text(tr('Chưa có quy trình nào cho tạo tiến trình từ tin nhắn'))));
      return;
    }
    final pick = list.length == 1
        ? list.first
        : await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
                Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(tr('Tạo tiến trình từ tin này'), style: Theme.of(c).textTheme.titleMedium)),
                for (final x in list)
                  ListTile(
                    leading: Text('${x['icon'] ?? ''}'.isEmpty ? '📋' : '${x['icon']}', style: const TextStyle(fontSize: 22)),
                    title: Text('${x['label']}'),
                    subtitle: x['label'] == x['name'] ? null : Text('${x['name']}'),
                    onTap: () => Navigator.pop(c, x),
                  ),
              ]),
            ),
          );
    if (pick == null || !context.mounted) return;
    final flowId = '${pick['flow_id']}', startId = '${pick['start_id']}';
    final pre = await api.prefill(flowId, startId, postId);
    if (!context.mounted) return;
    String? newId;
    final form = FlowFormPage(
        app: app,
        api: api,
        title: '${pre['name'] ?? pick['name']}',
        fields: FlowField.listOf(pre['fields']),
        initial: (pre['form'] as Map?)?.cast<String, dynamic>() ?? const {},
        flowId: flowId,
        askTitle: true,
        initialTitle: '${pre['title'] ?? ''}',
        submitLabel: tr('Tạo tiến trình mới'),
        onSubmit: (data, title) async => newId = await api.start(flowId, data, title: title, startId: startId, postId: postId),
      );
    // Máy tính: hộp thoại giữa màn hình (không che cả cửa sổ); điện thoại: trang mới.
    final wide = ChatHost.of(context)?.openPage != null;
    final ok = wide
        ? await showDialog<bool>(
            context: context,
            builder: (c) => Dialog(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(width: 560, height: (MediaQuery.sizeOf(c).height * 0.9).clamp(360, 760), child: form),
            ),
          )
        : await Navigator.of(context, rootNavigator: true).push<bool>(AppPageRoute(builder: (_) => form));
    if (ok == true && newId != null && context.mounted) {
      flowsChanged.value++;
      messenger.showSnackBar(toast(Text(tr('Đã tạo tiến trình'))));
      await openFlowInstance(context, app, newId!);
    }
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

String _userNameOf(AppState app, String id) {
  final u = app.users[id];
  if (u == null) return id;
  return u.displayName.isNotEmpty ? u.displayName : u.username;
}

Color flowStatusColor(String status, Color accent) => switch (status) {
      'done' => kFlowGreen,
      'rejected' || 'cancelled' || 'failed' => kFlowRed,
      'returned' => kFlowOrange,
      _ => accent,
    };

class FlowsHome extends StatefulWidget {
  final AppState app;
  /// Chỉ cho ảnh xem trước: mở sẵn tab (0 quy trình, 1 cần xử lý, 2 đang chạy, 3 lỗi, 4 đã xong).
  final int initialTab;
  /// Nằm trong tab "Quy trình" của thanh dưới: không có nút quay lại, chừa chỗ cho thanh dưới.
  final bool embedded;
  final double bottomPadding;
  /// Chỉ cho ảnh xem trước / test: quy trình đã ghim (không đọc preferences).
  final List<String>? debugPins;
  /// Mục mở sẵn: 0 "Việc của tôi" (5 tab như cũ), 1 "Tiến trình".
  final int initialSection;
  const FlowsHome({super.key, required this.app, this.initialTab = 0, this.embedded = false, this.bottomPadding = 0, this.debugPins, this.initialSection = 0});
  @override
  State<FlowsHome> createState() => _FlowsHomeState();
}

/// Bắt đầu một quy trình. Máy tính (màn rộng): biểu mẫu trong hộp nổi giữa cửa sổ; gửi xong đóng hộp, rồi [onCreated]
/// (trang quy trình chọn tiến trình mới ở cột phải) hoặc mở trang chi tiết như thường. Điện thoại: trang mới, gửi xong
/// thay bằng trang chi tiết.
Future<void> startFlowDef(BuildContext context, AppState app, FlowsApi api, FlowDefInfo d, {void Function(String id)? onCreated}) async {
  if (d.experimental) return showFlowExperimental(context);
  String? newId;
  FlowFormPage form({void Function(BuildContext ctx)? onDone}) => FlowFormPage(
        app: app,
        api: api,
        title: d.name,
        fields: d.form,
        flowId: d.id,
        askTitle: true,
        submitLabel: tr('Tạo tiến trình mới'),
        onSubmit: (data, title) async => newId = await api.start(d.id, data, title: title),
        onDone: onDone,
      );
  if (isDesktop && flowWide(context)) {
    await Navigator.of(context, rootNavigator: true).push<bool>(AppPageRoute(builder: (_) => form()));
    final id = newId;
    if (id == null || !context.mounted) return;
    flowsChanged.value++;
    if (onCreated != null) return onCreated(id);
    await openFlowInstance(context, app, id);
    return;
  }
  return openFlowPage(
    context,
    'start-${d.id}',
    (_) => form(onDone: (ctx) {
      flowsChanged.value++;
      final id = newId;
      if (id == null) return Navigator.of(ctx).pop(true);
      Navigator.of(ctx).pushReplacement(AppPageRoute(builder: (_) => FlowDetailPage(app: app, instanceId: id)));
    }),
  );
}

/// Mục quản trị của menu một quy trình (lưới Quy trình, trang quy trình): Sửa, Báo cáo, Sao chép, Ghim toàn công ty,
/// Bật / Tắt, Ẩn / Bỏ ẩn. Giá trị đưa vào [flowDefAdminAction].
List<PopupMenuEntry<String>> flowDefAdminItems(FlowDefInfo d) {
  PopupMenuItem<String> item(String v, IconData icon, String label) => PopupMenuItem(value: v, child: ListTile(dense: true, leading: Icon(icon), title: Text(label)));
  return [
    item('edit', Icons.edit_outlined, tr('Sửa')),
    item('report', Icons.insights_rounded, tr('Báo cáo')),
    item('copy', Icons.copy_rounded, tr('Sao chép')),
    d.pinnedAll ? item('unpin_all', Icons.business_outlined, tr('Bỏ ghim toàn công ty')) : item('pin_all', Icons.business_rounded, tr('Ghim toàn công ty')),
    d.active ? item('off', Icons.pause_circle_outline_rounded, tr('Tắt')) : item('on', Icons.play_circle_outline_rounded, tr('Bật')),
    d.hidden ? item('show', Icons.visibility_outlined, tr('Bỏ ẩn')) : item('hide', Icons.visibility_off_outlined, tr('Ẩn')),
  ];
}

/// Làm một mục quản trị của [flowDefAdminItems]; [reload] chạy sau khi đổi.
Future<void> flowDefAdminAction(BuildContext context, AppState app, FlowsApi api, FlowDefInfo d, String v, {Future<void> Function()? reload}) async {
  final messenger = ScaffoldMessenger.of(context);
  Future<void> again() async => reload == null ? null : await reload();
  try {
    switch (v) {
      case 'edit':
        await openFlowEditor(context, app, api, flowId: d.id);
        await again();
      case 'report':
        await openProcessReport(context, app, d.id, d.name);
      case 'on' || 'off':
        await api.setActive(d.id, v == 'on');
        messenger.showSnackBar(toast(Text(v == 'on' ? tr('Đã bật: mọi người tạo được tiến trình') : tr('Đã tắt: không tạo tiến trình mới, tiến trình đang chạy vẫn chạy tiếp'))));
        await again();
      case 'copy':
        final cp = await api.copyDef(d.id);
        messenger.showSnackBar(toast(Text(tr('Đã sao chép thành "{0}" (đang tắt)', ['${cp['name']}']))));
        await again();
        if (context.mounted) await openFlowEditor(context, app, api, flowId: '${cp['id']}');
        await again();
      case 'pin_all' || 'unpin_all':
        await api.setPinnedAll(d.id, v == 'pin_all');
        messenger.showSnackBar(toast(Text(v == 'pin_all' ? tr('Đã ghim cho cả công ty') : tr('Đã bỏ ghim toàn công ty'))));
        await again();
      case 'hide' || 'show':
        await api.setHidden(d.id, v == 'hide');
        messenger.showSnackBar(toast(Text(v == 'hide' ? tr('Đã ẩn: chỉ quản trị thấy (mờ)') : tr('Đã bỏ ẩn: mọi người có quyền đều thấy'))));
        await again();
    }
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

/// Quy trình được ghim lên đầu tab "Quy trình": lưu ở preferences Mattermost (flygo_flows/pinned) để mọi máy cùng thấy.
class _FlowPins {
  static const _cat = 'flygo_flows', _name = 'pinned';

  static Future<List<String>> load(AppState app) async {
    final me = app.me;
    if (me == null) return const [];
    try {
      final r = (await app.api.get('/users/${me.id}/preferences/$_cat/name/$_name') as Map).cast<String, dynamic>();
      return [for (final x in (jsonDecode('${r['value'] ?? '[]'}') as List? ?? const [])) '$x'];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(AppState app, List<String> ids) async {
    final me = app.me;
    if (me == null) return;
    await app.api.put('/users/${me.id}/preferences', [
      {'user_id': me.id, 'category': _cat, 'name': _name, 'value': jsonEncode(ids)},
    ]);
  }
}

/// Trang chính, 4 tab: Quy trình (lưới để bắt đầu, có ghim), Phê duyệt (việc chờ mình), Đang chạy và Đã xong (việc có
/// liên quan tới mình). Quản trị có nút cài đặt góc trên phải.
class _FlowsHomeState extends State<FlowsHome> {
  late final api = FlowsApi(widget.app.token);
  List<FlowTask>? _tasks;
  List<Map<String, dynamic>>? _runs;
  List<FlowDefInfo>? _defs;
  List<String> _pins = const [];
  bool _admin = false;
  bool _viewer = false;
  bool _meLoaded = false;
  String? _err;
  String _q = '';
  Timer? _live;

  @override
  void initState() {
    super.initState();
    // Hiện ngay bản lần trước (nếu có) trong lúc tải bản mới.
    api.cachedHome().then((c) {
      if (!mounted) return;
      setState(() {
        if (_tasks == null && _runs == null && c.tasks != null && c.instances != null) {
          _tasks = c.tasks;
          _runs = c.instances;
        }
        if (c.me != null && !_meLoaded) {
          _admin = c.me!['admin'] == true;
          _viewer = c.me!['viewer'] == true;
        }
      });
    }).catchError((_) {});
    _load();
    if (widget.debugPins != null) {
      _pins = widget.debugPins!;
    } else {
      _FlowPins.load(widget.app).then((p) {
        if (mounted) setState(() => _pins = p);
      });
    }
    flowsChanged.addListener(_load);
  }

  @override
  void dispose() {
    _live?.cancel();
    for (final s in _liveSubs.values) {
      s.cancel();
    }
    flowsChanged.removeListener(_load);
    super.dispose();
  }

  /// Kênh realtime của các việc đang chạy có thanh tiến độ (tối đa 20): đổi thì thay dòng ngay.
  final _liveSubs = <String, FlowsLiveSub>{};

  void _onLive(FlowsLiveEvent e) {
    if (!mounted) return;
    final runs = _runs;
    final i = runs == null || e.row.isEmpty ? -1 : runs.indexWhere((r) => '${r['id']}' == e.id);
    if (i >= 0) {
      setState(() => _runs = [...runs!]..[i] = e.row);
      _keepLive();
    }
  }

  /// Có việc đang chạy báo tiến độ: theo dõi qua kênh realtime; kênh rớt thì 5 giây làm mới danh sách một lần để thanh
  /// tiến độ chạy theo.
  void _keepLive() {
    _live?.cancel();
    final ids = {
      for (final x in (_runs ?? const <Map<String, dynamic>>[]))
        if (x['status'] == 'running' && x['progress'] != null) '${x['id']}',
    }.take(20).toSet();
    for (final id in [..._liveSubs.keys]) {
      if (!ids.contains(id)) _liveSubs.remove(id)!.cancel();
    }
    if (!mounted) return;
    for (final id in ids) {
      _liveSubs[id] ??= FlowsLive.of(api).subscribe('instance:$id', _onLive);
    }
    if (ids.isEmpty) return;
    _live = Timer(const Duration(seconds: 5), () async {
      if (FlowsLive.of(api).up) return _keepLive();
      try {
        final list = await api.instances(related: true);
        if (mounted) setState(() => _runs = list);
      } catch (_) {}
      _keepLive();
    });
  }

  Future<void> _load() async {
    final meF = api.me().then<Map<String, dynamic>?>((v) => v, onError: (_) => null);
    final defsF = api.defs(all: true).then<List<FlowDefInfo>?>((v) => v, onError: (_) => null);
    try {
      final r = await Future.wait([api.tasks(), api.instances(related: true)]);
      if (!mounted) return;
      setState(() {
        _tasks = r[0] as List<FlowTask>;
        _runs = r[1] as List<Map<String, dynamic>>;
        _err = null;
      });
      _keepLive();
    } catch (e) {
      // Đang có danh sách (bản lưu / lần trước): giữ nguyên, chỉ báo lỗi.
      if (mounted && _tasks != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(tr('Không tải được quy trình: {0}', ['$e']))));
      } else if (mounted) {
        setState(() => _err = '$e');
      }
    }
    final defs = await defsF;
    if (defs != null && mounted) setState(() => _defs = defs);
    try {
      final me = await meF;
      if (me != null && mounted) {
        setState(() {
          _admin = me['admin'] == true;
          _viewer = me['viewer'] == true;
          _meLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _openInstance(String id) async {
    await openFlowInstance(context, widget.app, id);
    _load();
  }

  Future<void> _settings() async {
    await openFlowPage(context, 'admin', (_) => FlowsAdminPage(app: widget.app, api: api));
    _load();
  }

  String _who(String id) {
    if (id.isEmpty) return '';
    if (id == widget.app.me?.id) return tr('Bạn');
    if (widget.app.users[id] == null) widget.app.refreshUser(id).then((_) => mounted ? setState(() {}) : null).catchError((_) {});
    return _userNameOf(widget.app, id);
  }

  Widget _state(Widget child) => _err != null
      ? ListView(children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(tr('Không tải được quy trình: {0}', [_err]), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
            ]),
          ),
        ])
      : child;

  Widget _empty(String text) => ListView(children: [
        Padding(padding: const EdgeInsets.all(32), child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Pal.of(context).sub))),
      ]);

  Widget _header(Pal pal, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: pal.sub)),
      );

  // ------------------------------------------------------------------ tab Quy trình

  Future<void> _togglePin(FlowDefInfo d) async {
    final pinned = _pins.contains(d.id);
    final next = pinned ? [for (final x in _pins) if (x != d.id) x] : [..._pins, d.id];
    setState(() => _pins = next);
    try {
      await _FlowPins.save(widget.app, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pins = [for (final x in next) if (x != d.id) x, if (pinned) d.id]);
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Không lưu được: {0}', ['$e']))));
    }
  }

  Future<void> _defMenu(FlowDefInfo d, Offset at) async {
    final pinned = _pins.contains(d.id);
    final box = Overlay.of(context).context.findRenderObject() as RenderBox;
    PopupMenuItem<String> item(String v, IconData icon, String label) => PopupMenuItem(value: v, child: ListTile(dense: true, leading: Icon(icon), title: Text(label)));
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & box.size),
      items: [
        if (d.canStart) item('start', Icons.play_arrow_rounded, tr('Tạo tiến trình mới')),
        if (!d.pinnedAll) item('pin', pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, pinned ? tr('Bỏ ghim') : tr('Ghim lên đầu')),
        // Quản trị: sửa, bật / tắt (tắt = không tạo tiến trình mới), ẩn (mờ với quản trị, ẩn với người khác).
        if (_admin) ...[const PopupMenuDivider(), ...flowDefAdminItems(d)],
      ],
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'pin':
        await _togglePin(d);
      case 'start':
        await startFlowDef(context, widget.app, api, d);
      default:
        await flowDefAdminAction(context, widget.app, api, d, v, reload: _load);
    }
  }

  Future<void> _addFlow() async {
    await FlowsAdminTab(app: widget.app, api: api, defs: const [], reload: _load).create(context);
    await _load();
  }

  /// Ô "+ Thêm quy trình" ở cuối lưới (quản trị).
  Widget _addTile(Pal pal) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _addFlow,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.divider, width: 1.5)),
              child: Icon(Icons.add_rounded, size: 30, color: pal.accentText),
            ),
            const SizedBox(height: 8),
            Text(tr('Thêm quy trình'), maxLines: 2, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: pal.accentText)),
          ]),
        ),
      );

  Widget _defTile(Pal pal, FlowDefInfo d) {
    final pinned = _pins.contains(d.id) || d.pinnedAll;
    // Quản trị thấy cả quy trình đang tắt / đang ẩn: hiện mờ kèm ghi chú.
    final note = [if (!d.active) tr('Đang tắt'), if (d.hidden) tr('Đã ẩn')].join(' · ');
    Offset at = Offset.zero;
    return Opacity(
      opacity: note.isEmpty ? 1 : .45,
      child: Tooltip(
      message: d.category.isEmpty ? d.name : '${d.name} · ${d.category}',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Mục Quy trình chỉ dành cho quản trị: bấm là mở sơ đồ (trình soạn) — máy tính ở vùng bên phải, giữ danh sách
        // bên trái; điện thoại mở trang soạn. Đang soạn quy trình khác mà chưa lưu thì hỏi trước.
        onTap: () async {
          if (!await canLeaveFlowEditor() || !mounted) return;
          await openFlowEditor(context, widget.app, api, flowId: d.id);
          if (mounted) _load();
        },
        onTapDown: (e) => at = e.globalPosition,
        onLongPress: () => _defMenu(d, at),
        onSecondaryTapDown: (e) => _defMenu(d, e.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(16)),
                child: Text(d.icon.isEmpty ? '📋' : d.icon, style: const TextStyle(fontSize: 28)),
              ),
              if (pinned)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
                    // Ghim toàn công ty: biểu tượng toà nhà; ghim riêng: đinh ghim.
                    child: Icon(d.pinnedAll ? Icons.business_rounded : Icons.push_pin_rounded, size: 11, color: Colors.white),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Text(d.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.text)),
            if (d.experimental) const Padding(padding: EdgeInsets.only(top: 3), child: FlowExperimentalBadge(small: true)),
            if (note.isNotEmpty) Text(note, maxLines: 1, style: TextStyle(fontSize: 11, color: pal.sub)),
          ]),
        ),
      ),
    ),
    );
  }

  Widget _grid(Pal pal, List<FlowDefInfo> defs, {bool add = false}) => LayoutBuilder(builder: (ctx, c) {
        // Như lưới ứng dụng: điện thoại 4 cột, màn rộng thêm cột (tối đa 8).
        final cols = (c.maxWidth / 104).floor().clamp(3, 8);
        final w = (c.maxWidth - 24) / cols;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(children: [
            for (final d in defs) SizedBox(width: w, child: _defTile(pal, d)),
            if (add) SizedBox(width: w, child: _addTile(pal)),
          ]),
        );
      });

  Widget _catalogTab() {
    final defs = _defs;
    if (defs == null) return _err != null ? _state(const SizedBox.shrink()) : const Center(child: CircularProgressIndicator());
    final pal = Pal.of(context);
    final q = _q.trim().toLowerCase();
    final shown = [for (final d in defs) if (q.isEmpty || '${d.name} ${d.category} ${d.id}'.toLowerCase().contains(q)) d];
    final byId = {for (final d in shown) d.id: d};
    final pinned = [
      for (final d in shown) if (d.pinnedAll) d,
      for (final id in _pins) if (byId[id] case final d? when !d.pinnedAll) d,
    ];
    final groups = <String, List<FlowDefInfo>>{};
    for (final d in shown) {
      (groups[d.category.isEmpty ? tr('Khác') : d.category] ??= []).add(d);
    }
    final names = groups.keys.toList()..sort((a, b) => a == tr('Khác') ? 1 : (b == tr('Khác') ? -1 : a.compareTo(b)));
    return ListView(padding: EdgeInsets.only(bottom: 24 + widget.bottomPadding), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: tr('Tìm quy trình'),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: _q.isEmpty ? null : IconButton(onPressed: () => setState(() => _q = ''), icon: const Icon(Icons.close_rounded)),
          ),
          controller: _qCtl,
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      if (defs.isEmpty && !_admin)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('Chưa có quy trình nào. Nhờ quản trị tạo quy trình (có thể nhắn trợ lý AI).'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
        )
      else if (shown.isEmpty)
        Padding(padding: const EdgeInsets.all(32), child: Text(tr('Không thấy quy trình nào.'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub))),
      if (pinned.isNotEmpty) ...[_header(pal, tr('ĐÃ GHIM')), _grid(pal, pinned)],
      for (final g in names) ...[_header(pal, g.toUpperCase()), _grid(pal, groups[g]!, add: _admin && q.isEmpty && g == names.last)],
      // Chưa có quy trình nào (hoặc đang lọc): ô "+ Thêm quy trình" đứng riêng.
      if (_admin && q.isEmpty && names.isEmpty) ...[const SizedBox(height: 12), _grid(pal, const [], add: true)],
      if (defs.isNotEmpty && _pins.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(tr('Bấm giữ (hoặc nháy phải) một quy trình để ghim lên đầu.'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub, fontSize: 12)),
        ),
    ]);
  }

  late final _qCtl = TextEditingController();

  // ------------------------------------------------------------------ tab Phê duyệt

  Widget _approvalsTab() {
    final tasks = _tasks;
    if (tasks == null) return const Center(child: CircularProgressIndicator());
    if (tasks.isEmpty) return _empty(tr('Không có tiến trình nào đang chờ bạn.'));
    final pal = Pal.of(context);
    return ListView.separated(
      padding: EdgeInsets.only(bottom: 24 + widget.bottomPadding),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: pal.divider),
      itemBuilder: (_, i) => _taskTile(pal, tasks[i]),
    );
  }

  Widget _taskTile(Pal pal, FlowTask t) {
    final overdue = t.dueAt != null && t.dueAt! < DateTime.now().millisecondsSinceEpoch;
    final flow = [for (final d in _defs ?? const <FlowDefInfo>[]) if (d.id == t.flowId) d.name].firstOrNull;
    final request = '${t.request?['title'] ?? ''}'.trim();
    final prompt = '${t.action?['prompt'] ?? ''}'.trim();
    final tile = ListTile(
      leading: Icon(
          switch (t.kind) { 'approval' => Icons.how_to_reg_rounded, 'action' => Icons.touch_app_outlined, _ => t.returned != null ? Icons.undo_rounded : Icons.edit_note_rounded },
          color: t.returned != null ? kFlowOrange : pal.accentText),
      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (t.returned != null) tr('Bị trả lại') else flowTaskKindLabel(t.kind),
          if (request.isNotEmpty) request else if (prompt.isNotEmpty) prompt,
          ?flow,
          if (t.onBehalf != null) tr('duyệt thay {0}', [_userNameOf(widget.app, t.onBehalf!)]),
          if (t.dueAt != null) tr('hạn {0}', [_when(t.dueAt!)]),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: overdue ? kFlowRed : pal.sub),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _openInstance(t.instanceId),
    );
    if (t.kind != 'action' || t.action == null) return tile;
    // Chờ bấm nút / Lựa chọn: thao tác ngay trong danh sách.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      tile,
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: FlowTaskActionPanel(
          key: ValueKey('task-action-${t.id}'),
          task: t,
          showPrompt: false,
          onSubmit: (data) async {
            await api.submit(t.id, data);
            flowsChanged.value++;
          },
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------------ tab Đang chạy / Đã xong

  static bool _isRunning(Map m) => m['status'] == 'running' || m['status'] == 'returned';
  static bool _isProblem(Map m) => m['problem'] is Map;

  /// [running]: tab Đang chạy / Đã xong; [problems]: tab Lỗi (việc lỗi chỉ nằm ở tab Lỗi).
  /// Chọn một quy trình mình được chạy rồi điền biểu mẫu (mọi người; quản trị còn có tab "Quy trình").
  Future<void> _pickStart() async {
    await openFlowPage(context, 'start', (_) => FlowStartPage(app: widget.app, api: api));
    if (mounted) _load();
  }

  Widget _startButton() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const ValueKey('start-flow'),
            onPressed: _pickStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(tr('Bắt đầu quy trình')),
          ),
        ),
      );

  Widget _runsTab({bool running = false, bool problems = false}) {
    final runs = _runs;
    if (runs == null) return const Center(child: CircularProgressIndicator());
    final list = [
      for (final m in runs)
        if (problems ? _isProblem(m) : !_isProblem(m) && _isRunning(m) == running) m,
    ];
    if (list.isEmpty) {
      final text = problems
          ? tr('Không có tiến trình nào bị lỗi.')
          : running
              ? tr('Không có tiến trình nào đang chạy. Bấm "Bắt đầu quy trình" để bắt đầu.')
              : tr('Chưa có tiến trình nào xong.');
      return ListView(children: [
        if (running && !problems) _startButton(),
        Padding(padding: const EdgeInsets.all(32), child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Pal.of(context).sub))),
      ]);
    }
    final pal = Pal.of(context);
    return ListView.separated(
      padding: EdgeInsets.only(bottom: 24 + widget.bottomPadding),
      itemCount: list.length + (running && !problems ? 1 : 0),
      separatorBuilder: (_, _) => Divider(height: 1, color: pal.divider),
      itemBuilder: (_, i) {
        // Tab Đang chạy: nút "Bắt đầu quy trình" ở đầu danh sách.
        if (running && !problems) return i == 0 ? _startButton() : _runTile(pal, list[i - 1]);
        return _runTile(pal, list[i]);
      },
    );
  }

  Widget _runTile(Pal pal, Map<String, dynamic> m) {
    final status = '${m['status']}';
    final running = _isRunning(m);
    final created = (m['created_at'] as num?)?.toInt() ?? 0;
    final updated = (m['updated_at'] as num?)?.toInt() ?? created;
    final now = DateTime.now().millisecondsSinceEpoch;
    final flow = '${m['flow_name'] ?? m['flow_id'] ?? ''}';
    final version = m['flow_version'];
    final category = '${m['category'] ?? ''}'.trim();
    final icon = '${m['flow_icon'] ?? ''}';
    final requester = '${m['requester'] ?? ''}';
    final waitFor = [for (final a in (m['assignees'] as List? ?? const [])) _who('$a')];
    final current = [for (final c in (m['current'] as List? ?? const [])) '$c'];
    final small = TextStyle(color: pal.sub, fontSize: 12.5);
    Widget tag(String text, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
          child: Text(text, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
        );
    return InkWell(
      onTap: () => _openInstance('${m['id']}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(12)),
            child: Text(icon.isEmpty ? '📋' : icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text('${m['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
                const SizedBox(width: 8),
                // Kết thúc ở nhánh lỗi: trạng thái là "xong" nhưng hiện như thất bại để khỏi nhầm.
                _StatusChip(status: _isProblem(m) && !running ? 'failed' : status),
              ]),
              const SizedBox(height: 3),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(version == null ? flow : '$flow · v$version', style: small),
                if (category.isNotEmpty) tag(category, pal.accentText),
              ]),
              const SizedBox(height: 3),
              Text(
                running
                    ? tr('Bắt đầu {0} · đã chạy {1}', [_when(created), _span(now - created)])
                    : tr('Xong {0} · chạy {1}', [_when(updated), _span(updated - created)]),
                style: small,
              ),
              Text(
                [
                  tr('Người tạo: {0}', [_who(requester)]),
                  if (running && waitFor.isNotEmpty) tr('Đang chờ: {0}', [waitFor.join(', ')]),
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
              if (running && current.isNotEmpty)
                Text(tr('Bước hiện tại: {0}', [current.join(', ')]), maxLines: 1, overflow: TextOverflow.ellipsis, style: small.copyWith(color: pal.text)),
              if (m['problem'] case final Map p)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: kFlowRed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          switch (p['kind']) { 'failed' => tr('Thất bại'), 'manual' => tr('Cần người xử lý'), _ => tr('Kết thúc do lỗi') },
                          if ('${p['message'] ?? ''}'.isNotEmpty) '${p['message']}',
                        ].join(': '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kFlowRed, fontSize: 12.5),
                      ),
                    ),
                  ]),
                ),
              if (running && !_isProblem(m)) FlowProgressBar(progress: m['progress'], compact: true),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Khoảng thời gian ngắn gọn: "45 giây", "12 phút", "3 giờ", "2 ngày".
  static String _span(int ms) {
    final s = (ms / 1000).floor().clamp(0, 1 << 31);
    if (s < 60) return tr('{0} giây', ['$s']);
    if (s < 3600) return tr('{0} phút', ['${s ~/ 60}']);
    if (s < 86400) return tr('{0} giờ', ['${s ~/ 3600}']);
    return tr('{0} ngày', ['${s ~/ 86400}']);
  }

  @override
  Widget build(BuildContext context) {
    final n = _tasks?.length ?? 0;
    final runningCount = (_runs ?? const []).where((m) => _isRunning(m) && !_isProblem(m)).length;
    final problemCount = (_runs ?? const []).where(_isProblem).length;
    Widget counted(IconData icon, String label, [int count = 0, Color? badge]) => Tab(
          height: 46,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label),
            if (count > 0) ...[const SizedBox(width: 6), Badge(backgroundColor: badge, label: Text('$count'))],
          ]),
        );
    // Theo bề rộng thật của trang (máy tính: trang Quy trình nằm trong một cột): 5 tab có chữ + số đếm cần ~720px,
    // hẹp hơn thì cho cuộn ngang, không cắt chữ.
    // Tab "Quy trình" (danh mục quy trình: ghim, sửa, thêm) chỉ dành cho quản trị quy trình; người khác bắt đầu quy trình
    // ở nút "Bắt đầu quy trình" (tab Đang chạy) hoặc ô quy trình ở Trang chủ, mở đầu ở tab Cần xử lý.
    final cat = _admin ? 1 : 0;
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 720;
      return DefaultTabController(
      key: ValueKey('flows-tabs-$_admin'),
      length: 6 + cat,
      // Mục "Tiến trình" mở sẵn (initialSection 1), "Bảng theo dõi" (initialSection 2) là hai tab cuối.
      initialIndex: switch (widget.initialSection) {
        1 => 4 + cat,
        2 => 5 + cat,
        _ => (_admin ? widget.initialTab.clamp(0, 4) : (widget.initialTab - 1).clamp(0, 3)),
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          leading: widget.embedded ? null : flowLeading(context),
          title: Text(tr('Quy trình')),
          actions: [
            IconButton(tooltip: tr('Tải lại'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
            if (_viewer)
              IconButton(
                tooltip: tr('Tất cả tiến trình'),
                onPressed: () => openFlowPage(context, 'all', (_) => FlowsAllPage(app: widget.app, api: api)),
                icon: const Icon(Icons.filter_alt_outlined),
              ),
            if (_admin) IconButton(tooltip: tr('Quản lý quy trình'), onPressed: _settings, icon: const Icon(Icons.settings_outlined)),
          ],
          // Các tab lọc: danh mục quy trình, việc của tôi (cần xử lý / đang chạy / lỗi / đã xong) và Tiến trình
          // (đối tượng nghiệp vụ quy trình theo dõi). Điện thoại: không vừa một hàng thì cuộn ngang thay vì cắt chữ.
          bottom: TabBar(
            // Tab rộng theo chữ (không chia đều rồi tràn); màn rộng thì căn giữa, hẹp thì cuộn ngang.
            isScrollable: true,
            tabAlignment: narrow ? TabAlignment.start : TabAlignment.center,
            tabs: [
              if (_admin) counted(Icons.apps_rounded, tr('Quy trình')),
              counted(Icons.pending_actions_rounded, tr('Cần xử lý'), n),
              counted(Icons.autorenew_rounded, tr('Đang chạy'), runningCount),
              counted(Icons.error_outline_rounded, tr('Lỗi'), problemCount, kFlowRed),
              counted(Icons.task_alt_rounded, tr('Đã xong')),
              counted(Icons.timeline_rounded, tr('Theo dõi')),
              counted(Icons.view_kanban_outlined, tr('Bảng theo dõi')),
            ],
          ),
        ),
        body: TabBarView(children: [
                if (_admin) RefreshIndicator(onRefresh: _load, child: _catalogTab()),
                RefreshIndicator(onRefresh: _load, child: _state(_approvalsTab())),
                RefreshIndicator(onRefresh: _load, child: _state(_runsTab(running: true))),
                RefreshIndicator(onRefresh: _load, child: _state(_runsTab(problems: true))),
                RefreshIndicator(onRefresh: _load, child: _state(_runsTab(running: false))),
                ProcessesView(app: widget.app, defs: _defs ?? const [], bottomPadding: widget.bottomPadding),
                ProcessBoardView(app: widget.app, bottomPadding: widget.bottomPadding),
              ]),
      ),
    );
    });
  }
}

/// Ủy quyền (trong lưới Ứng dụng): ủy quyền đang có / đã đặt, nút + để gửi đơn xin ủy quyền.
class FlowDelegationsPage extends StatefulWidget {
  final AppState app;
  const FlowDelegationsPage({super.key, required this.app});
  @override
  State<FlowDelegationsPage> createState() => _FlowDelegationsPageState();
}

class _FlowDelegationsPageState extends State<FlowDelegationsPage> {
  late final api = FlowsApi(widget.app.token);
  final _delKey = GlobalKey<DelegationsTabState>();

  /// Gửi đơn xin ủy quyền: chỉ các quy trình có bước "Đặt ủy quyền" (cấp trên duyệt rồi mới có hiệu lực).
  Future<void> _requestDelegation() async {
    final flows = _delKey.currentState?.requestFlows ?? const [];
    if (flows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Chưa có quy trình xin ủy quyền. Nhờ quản trị thêm (mẫu "Xin nghỉ phép" có sẵn bước Đặt ủy quyền).'))));
      return;
    }
    final id = await openFlowPage<String>(context, 'start-delegation', (_) => FlowStartPage(app: widget.app, api: api, only: {for (final f in flows) '${f['id']}'}));
    if (id != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã gửi đơn, chờ cấp trên duyệt'))));
      await openFlowInstance(context, widget.app, id);
    }
    _delKey.currentState?.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: flowLeading(context), title: Text(tr('Ủy quyền'))),
        body: RefreshIndicator(
          onRefresh: () async => _delKey.currentState?.load(),
          child: DelegationsTab(key: _delKey, app: widget.app, api: api, reload: flowsChanged),
        ),
        floatingActionButton: PlusFab(heroTag: 'flow-delegation', tooltip: tr('Xin ủy quyền'), onPressed: _requestDelegation),
      );
}

/// Trang "Tạo luồng mới": các quy trình được phép bắt đầu, nhóm theo danh mục. Chọn một quy trình → điền form →
/// bắt đầu luồng. Trả về id luồng mới qua Navigator.pop.
class FlowStartPage extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  /// Chỉ hiện các quy trình này (vd quy trình xin ủy quyền).
  final Set<String>? only;
  const FlowStartPage({super.key, required this.app, required this.api, this.only});
  @override
  State<FlowStartPage> createState() => _FlowStartPageState();
}

class _FlowStartPageState extends State<FlowStartPage> {
  List<FlowDefInfo>? _defs;
  String? _err;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.defs();
      if (mounted) {
        setState(() {
          _defs = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _start(FlowDefInfo d) async {
    if (d.experimental) return showFlowExperimental(context);
    String? newId;
    final ok = await Navigator.of(context).push<bool>(AppPageRoute(
      builder: (_) => FlowFormPage(
        app: widget.app,
        api: widget.api,
        title: d.name,
        fields: d.form,
        flowId: d.id,
        askTitle: true,
        submitLabel: tr('Tạo tiến trình mới'),
        onSubmit: (data, title) async => newId = await widget.api.start(d.id, data, title: title),
      ),
    ));
    if (ok == true && newId != null && mounted) {
      flowsChanged.value++;
      if (PageCloser.of(context) != null && !Navigator.of(context).canPop()) {
        Navigator.of(context).pushReplacement(AppPageRoute(builder: (_) => FlowDetailPage(app: widget.app, instanceId: newId!)));
      } else {
        Navigator.of(context).pop(newId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final defs = _defs;
    final q = _q.trim().toLowerCase();
    final groups = <String, List<FlowDefInfo>>{};
    for (final d in defs ?? const <FlowDefInfo>[]) {
      if (widget.only != null && !widget.only!.contains(d.id)) continue;
      if (q.isNotEmpty && !'${d.name} ${d.category}'.toLowerCase().contains(q)) continue;
      (groups[d.category.isEmpty ? tr('Khác') : d.category] ??= []).add(d);
    }
    final names = groups.keys.toList()
      ..sort((a, b) => a == tr('Khác') ? 1 : (b == tr('Khác') ? -1 : a.compareTo(b)));
    return Scaffold(
      appBar: AppBar(leading: flowLeading(context), title: Text(tr('Tạo tiến trình mới'))),
      body: _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Không tải được quy trình: {0}', [_err]), textAlign: TextAlign.center)))
          : defs == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                  if (defs.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm quy trình'), isDense: true, border: const OutlineInputBorder()),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ),
                  if (defs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(tr('Chưa có quy trình nào. Nhờ quản trị tạo quy trình (có thể nhắn trợ lý AI).'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
                    ),
                  for (final g in names) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                      child: Text(g.toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: pal.sub)),
                    ),
                    for (final d in groups[g]!)
                      Card(
                        elevation: 0,
                        color: pal.surface,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: pal.divider)),
                        // Quy trình "Thử nghiệm": hiện mờ kèm nhãn, bấm chỉ báo chưa chạy được.
                        child: ListTile(
                          key: ValueKey('start-def-${d.id}'),
                          leading: Opacity(opacity: d.experimental ? .5 : 1, child: Text(d.icon.isEmpty ? '📋' : d.icon, style: const TextStyle(fontSize: 28))),
                          title: Text(d.name, style: TextStyle(fontWeight: FontWeight.w600, color: d.experimental ? pal.sub : pal.text)),
                          subtitle: d.experimental
                              ? Text(flowExperimentalMsg(), maxLines: 1, overflow: TextOverflow.ellipsis)
                              : d.form.isEmpty ? null : Text([for (final f in d.form.take(3)) f.label].join(' · ') + (d.form.length > 3 ? ' …' : ''), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: d.experimental ? const FlowExperimentalBadge() : const Icon(Icons.chevron_right_rounded),
                          onTap: () => _start(d),
                        ),
                      ),
                  ],
                ]),
    );
  }
}

String _whenSec(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${hhmm(d)}:${d.second.toString().padLeft(2, '0')}';
}

String _when(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${dayLabel(d)} ${hhmm(d)}';
}

/// Thanh tiến độ của việc (bước Báo tiến độ): phần trăm + nhãn, màu theo kiểu (thường / ok / warn / error).
class FlowProgressBar extends StatelessWidget {
  final Object? progress;
  final bool compact;
  const FlowProgressBar({super.key, required this.progress, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p is! Map) return const SizedBox.shrink();
    final pal = Pal.of(context);
    final pct = (p['percent'] as num?)?.toDouble();
    final label = '${p['label'] ?? ''}'.trim();
    final color = switch ('${p['tone'] ?? ''}') {
      'ok' => const Color(0xFF15803D),
      'warn' => const Color(0xFFD97706),
      'error' => const Color(0xFFDC2626),
      _ => pal.accent,
    };
    final text = [if (pct != null) '${pct.round()}%', if (label.isNotEmpty) label].join(' · ');
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: compact ? 4 : 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct == null ? null : pct / 100,
            minHeight: compact ? 4 : 8,
            color: color,
            backgroundColor: color.withValues(alpha: .15),
          ),
        ),
        const SizedBox(height: 4),
        Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 12 : 14, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final c = flowStatusColor(status, Pal.of(context).accentText);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
      child: Text(flowStatusLabel(status), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

// ------------------------------------------------------------------ chi tiết đơn

class FlowDetailPage extends StatefulWidget {
  final AppState app;
  final String instanceId;
  const FlowDetailPage({super.key, required this.app, required this.instanceId});
  @override
  State<FlowDetailPage> createState() => _FlowDetailPageState();
}

class _FlowDetailPageState extends State<FlowDetailPage> {
  late final api = FlowsApi(widget.app.token);
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;
  Timer? _live, _liveReload;
  /// Kênh realtime của đơn: đổi thì tải lại ngay; huỷ khi đóng trang hoặc đơn xong.
  FlowsLiveSub? _liveSub;

  @override
  void initState() {
    super.initState();
    _liveSub = FlowsLive.of(api).subscribe('instance:${widget.instanceId}', (_) {
      if (!mounted) return;
      _liveReload?.cancel();
      _liveReload = Timer(const Duration(milliseconds: 300), () {
        if (mounted) _load();
      });
    });
    _load();
  }

  @override
  void dispose() {
    _live?.cancel();
    _liveReload?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  /// Đơn còn chạy: 3 giây tải lại một lần (tiến độ, bước đang chạy, gỡ lỗi) khi kênh realtime không nối được.
  void _poll() {
    _live?.cancel();
    _live = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _liveSub != null && FlowsLive.of(api).up ? _poll() : _load();
    });
  }

  /// Việc của mình trong đơn này kèm thông tin thêm từ GET /flows/tasks (nút / lựa chọn của bước chờ, yêu cầu phê
  /// duyệt, dữ liệu điền sẵn khi bị trả lại); chi tiết đơn chỉ có phần cơ bản.
  Map<int, FlowTask> _rich = {};

  Future<void> _enrich(Map<String, dynamic> d) async {
    final ids = {for (final t in (d['my_tasks'] as List? ?? const [])) if (t is Map && t['id'] is num) (t['id'] as num).toInt()};
    if (ids.isEmpty || ids.every(_rich.containsKey)) return;
    try {
      final all = await api.tasks();
      if (mounted) setState(() => _rich = {for (final t in all) if (ids.contains(t.id)) t.id: t});
    } catch (_) {}
  }

  Future<void> _load() async {
    _live?.cancel();
    try {
      final d = await api.instance(widget.instanceId);
      if (mounted) {
        setState(() {
          _d = d;
          _err = null;
        });
      }
      await _enrich(d);
      final open = d['status'] == 'running' || d['status'] == 'returned';
      if (!open) {
        _liveSub?.cancel();
        _liveSub = null;
      }
      if (mounted && d['status'] == 'running') _poll();
      // Có ủy quyền đề nghị: lấy tên quy trình để hiện.
      if (_flowNames.isEmpty && _delegationRequest != null) {
        final names = await api.flowNames();
        if (mounted) setState(() => _flowNames = {for (final f in names) '${f['id']}': '${f['name']}'});
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Map<String, String> _flowNames = {};

  /// Kết quả bước "Yêu cầu ủy quyền" (nếu đã điền).
  Map? get _delegationRequest {
    for (final n in (_def['nodes'] as List? ?? const [])) {
      if (n is Map && n['type'] == 'delegate_request') {
        final out = ((_d?['steps'] as Map?)?[n['id']] as Map?)?['output'];
        if (out is Map && out['rules'] != null) return out;
      }
    }
    return null;
  }

  Map<String, dynamic> get _def => (_d?['def'] as Map?)?.cast<String, dynamic>() ?? const {};
  List<FlowField> get _form => FlowField.listOf(_def['form']);

  Map<String, dynamic>? _node(String id) {
    for (final n in (_def['nodes'] as List? ?? const [])) {
      if (n is Map && n['id'] == id) return n.cast<String, dynamic>();
    }
    return null;
  }

  /// Tên bước kèm số cố định "(#12)" để người dùng chụp màn hình gửi admin tra.
  String _step(String id) {
    final n = _node(id);
    final name = '${n?['name'] ?? id}';
    // Chỉ tên khai báo của bước; mã bước (quy trình-số) để "Sao chép mã" ở menu.
    return name;
  }

  /// Nhãn khai báo của một trường form (cả trường của bước Điền thông tin / Duyệt); không có thì khoá.
  String _fieldLabel(String key) {
    for (final f in _form) {
      if (f.key == key && f.label.isNotEmpty) return f.label;
    }
    for (final n in (_def['nodes'] as List? ?? const [])) {
      for (final f in (n is Map ? (n['fields'] as List? ?? const []) : const [])) {
        if (f is Map && '${f['key']}' == key && '${f['label'] ?? ''}'.isNotEmpty) return '${f['label']}';
      }
    }
    return key;
  }

  String _name(String id) {
    if (id.isEmpty || id == 'null') return '';
    if (id == widget.app.me?.id) return tr('Bạn');
    final u = widget.app.users[id];
    if (u == null) widget.app.refreshUser(id).then((_) => mounted ? setState(() {}) : null).catchError((_) {});
    return u?.displayName ?? id;
  }

  /// Bước được trả về của việc duyệt (bước Tạo phê duyệt): từ `request.return_steps`, không có thì từ quy trình.
  List<Map<String, dynamic>> _returnSteps(FlowTask t) {
    if (t.returnSteps.isNotEmpty) return t.returnSteps;
    final node = _node(t.node);
    if (node?['type'] != 'approval_request') return const [];
    return [
      for (final id in (node?['return_steps'] as List? ?? const []))
        {'id': '$id', 'label': id == 'start' ? tr('Người tạo sửa đơn') : '${_node('$id')?['name'] ?? id}'},
    ];
  }

  Future<void> _decide(FlowTask t, String decision) async {
    if (await decideFlowTask(context, api, t.id, decision, onSending: () => setState(() => _busy = true), returnSteps: _returnSteps(t))) {
      flowsChanged.value++;
      await _load();
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Form của một việc: form_task → trường của bước; việc tay của bước AI → các khoá output; trả lại → form đơn.
  Future<void> _fill(FlowTask t) async {
    final node = _node(t.node);
    if (node?['type'] == 'delegate_request') {
      // Ngày điền sẵn: hai trường ngày đầu tiên của đơn (vd từ ngày / đến ngày nghỉ).
      final dates = [for (final f in _form) if (f.type == 'date') '${(_d?['form'] as Map?)?[f.key] ?? ''}'].where((v) => v.isNotEmpty).toList();
      final ok = await Navigator.of(context).push<bool>(AppPageRoute(
        builder: (_) => DelegationRequestPage(app: widget.app, api: api, taskId: t.id, from: dates.firstOrNull, until: dates.length > 1 ? dates[1] : null),
      ));
      if (ok == true) await _load();
      return;
    }
    List<FlowField> fields;
    Map<String, dynamic> initial = t.prefill ?? const {};
    var title = _step(t.node);
    if (t.kind == 'resubmit') {
      fields = _form;
      initial = ((_d?['form'] as Map?) ?? const {}).cast<String, dynamic>();
      title = tr('Sửa và nộp lại');
    } else if (node?['type'] == 'form_task') {
      fields = FlowField.listOf(node?['fields']);
    } else {
      final schema = (node?['output_schema'] as Map?)?.cast<String, dynamic>() ?? const {};
      fields = [
        for (final e in schema.entries)
          FlowField(key: e.key, label: e.key, type: switch ('${e.value}') { 'money' => 'money', 'number' => 'number', 'bool' => 'bool', _ => 'text' }, required: true),
      ];
    }
    final ok = await Navigator.of(context).push<bool>(AppPageRoute(
      builder: (_) => FlowFormPage(
        app: widget.app,
        api: api,
        title: title,
        fields: fields,
        initial: initial,
        flowId: '${_d?['flow_id'] ?? ''}',
        lookupPath: (f) => t.kind == 'resubmit' ? f.key : '${t.node}:${f.key}',
        notice: t.returned == null ? '' : flowReturnedText(t.returned!, _name),
        onSubmit: (data, _) => api.submit(t.id, data),
      ),
    ));
    if (ok == true) await _load();
  }

  /// Bước duyệt có thông tin nhập khi duyệt (vd chọn khách hàng) hoặc trường được sửa: mở form, gửi cùng quyết định.
  Future<bool> _approveWithForm(FlowTask t) async {
    final node = _node(t.node) ?? const {};
    final inputs = FlowField.listOf(node['fields']);
    final editable = [for (final k in (node['editable'] as List? ?? const [])) '$k'];
    final form = ((_d?['form'] as Map?) ?? const {}).cast<String, dynamic>();
    final fields = [...inputs, for (final f in _form) if (editable.contains(f.key)) f];
    final ok = await Navigator.of(context).push<bool>(AppPageRoute(
      builder: (_) => FlowFormPage(
        app: widget.app,
        api: api,
        title: _step(t.node),
        fields: fields,
        initial: {for (final k in editable) if (form[k] != null) k: form[k]},
        flowId: '${_d?['flow_id'] ?? ''}',
        lookupPath: (f) => inputs.any((x) => x.key == f.key) ? '${t.node}:${f.key}' : f.key,
        submitLabel: tr('Duyệt'),
        onSubmit: (data, _) => api.decide(t.id, 'approve', form: data),
      ),
    ));
    if (ok == true) await _load();
    return ok == true;
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (d) {
        final ctl = TextEditingController();
        return AlertDialog(
          title: Text(tr('Hủy đơn này?')),
          content: TextField(controller: ctl, decoration: InputDecoration(hintText: tr('Lý do (không bắt buộc)'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Không'))),
            FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: Text(tr('Hủy đơn'))),
          ],
        );
      },
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.cancel(widget.instanceId, reason: reason);
      messenger.showSnackBar(toast(Text(tr('Đã hủy đơn'))));
      await _load();
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không hủy được: {0}', ['$e']))));
    }
  }

  /// In phiếu: mở trang in A4 trong trình duyệt (in / lưu PDF ở đó).
  Future<void> _print() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await api.printUrl(widget.instanceId);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        messenger.showSnackBar(toast(Text(tr('Không mở được trình duyệt'))));
      }
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không in được: {0}', ['$e']))));
    }
  }

  /// Dữ liệu các bước, theo thứ tự trong quy trình: bước "Điền thông tin" (trường đã nhập) và bước "Tính toán" (biến
  /// có đặt tên hiển thị, vd "Cách xưởng (m)", "Muộn (phút)"). (tên bước, trường, giá trị).
  List<(String, List<FlowField>, Map)> _stepInputs(Map<String, dynamic> d) {
    final steps = (d['steps'] as Map?) ?? const {};
    List<FlowField> fieldsOf(Map n) => n['type'] == 'form_task'
        ? FlowField.listOf(n['fields'])
        : n['type'] == 'calc'
            ? FlowField.listOf([
                for (final v in (n['vars'] as List? ?? const []))
                  if (v is Map && '${v['label'] ?? ''}'.trim().isNotEmpty) {'key': v['name'], 'label': v['label'], 'type': 'text'},
              ])
            : const [];
    return [
      for (final n in (_def['nodes'] as List? ?? const []))
        if (n is Map && (n['type'] == 'form_task' || n['type'] == 'calc'))
          if ((steps[n['id']] as Map?)?['output'] case final Map out when out.isNotEmpty)
            if (fieldsOf(n) case final fields when fields.any((f) => out[f.key] != null)) (_step('${n['id']}'), fields, out),
    ];
  }

  /// Một dòng "nhãn: giá trị" của trường (form đơn hoặc thông tin nhập ở một bước). Không có giá trị: null.
  Widget? _fieldRow(Pal pal, FlowField f, Object? v) {
    if (v == null) return null;
    if (v is List && f.type == 'delegation') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(f.label, style: TextStyle(color: pal.sub)),
          const SizedBox(height: 6),
          DelegationValueView(app: widget.app, api: api, value: v),
        ]),
      );
    }
    // Vị trí: bản đồ nhỏ có ghim, toạ độ, độ chính xác, giờ lấy (chỉ xem).
    if (f.type == 'location' && FlowLocationView.point(v) != null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: FlowLocationView(label: f.label, value: v));
    }
    if (f.type == 'table') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.label, style: TextStyle(color: pal.sub)),
          const SizedBox(height: 6),
          FlowTableView(field: f, value: v),
        ]),
      );
    }
    final Widget value = switch (f.type) {
      'images' || 'photo' => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in (v as List? ?? const []))
            if (x is Map)
              InkWell(
                onTap: () => _openFile(x),
                borderRadius: BorderRadius.circular(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: FutureBuilder<Uint8List>(
                      future: _image('${x['id']}'),
                      builder: (_, s) => s.hasData
                          ? Image.memory(s.data!, fit: BoxFit.cover)
                          : ColoredBox(color: pal.surface2, child: Icon(Icons.image_outlined, color: pal.sub)),
                    ),
                  ),
                ),
              ),
        ]),
      'files' => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final x in (v as List? ?? const []))
            if (x is Map)
              InkWell(
                onTap: () => _openFile(x),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.description_outlined, size: 18, color: pal.accentText),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${x['name']}', style: TextStyle(color: pal.accentText, decoration: TextDecoration.underline))),
                  ]),
                ),
              ),
        ]),
      // Vị trí: bấm mở bản đồ.
      'location' when v is Map && v['lat'] is num && v['lon'] is num => InkWell(
          onTap: () => launchUrl(Uri.parse(mapsUrl((v['lat'] as num).toDouble(), (v['lon'] as num).toDouble())), mode: LaunchMode.externalApplication),
          child: Text(showFieldValue(f, v), style: TextStyle(color: pal.accentText, decoration: TextDecoration.underline)),
        ),
      _ => SelectableText(f.type == 'user' ? _name('$v') : showFieldValue(f, v), style: TextStyle(color: pal.text)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(f.label, style: TextStyle(color: pal.sub))),
        Expanded(child: value),
      ]),
    );
  }

  /// Ảnh của trường kiểu images: tải một lần, giữ trong trang (trang tự làm mới không tải lại).
  final _images = <String, Future<Uint8List>>{};
  Future<Uint8List> _image(String id) => _images[id] ??= api.file(widget.instanceId, id);

  Future<void> _openFile(Map f) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await api.file(widget.instanceId, '${f['id']}');
      final dir = await getTemporaryDirectory();
      final safe = '${f['name'] ?? f['id']}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${dir.path}${Platform.pathSeparator}flows-${f['id']}-$safe');
      await file.writeAsBytes(bytes);
      if (!await openLocalFile(file.path, mime: f['mime_type'] as String?, title: safe)) {
        messenger.showSnackBar(toast(Text(tr('Không mở được tệp'))));
      }
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không tải được tệp: {0}', ['$e']))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final d = _d;
    if (d == null) {
      return Scaffold(
        appBar: AppBar(leading: flowLeading(context), title: Text(tr('Đơn'))),
        body: Center(
          child: _err == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_err!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
                  ]),
                ),
        ),
      );
    }
    final status = '${d['status']}';
    final form = ((d['form'] as Map?) ?? const {}).cast<String, dynamic>();
    final tasks = [
      for (final t in (d['my_tasks'] as List? ?? const []))
        if (t is Map) _rich[(t['id'] as num?)?.toInt()] ?? FlowTask.fromJson(t),
    ];
    final events = [for (final e in (d['events'] as List? ?? const [])) if (e is Map) e.cast<String, dynamic>()];
    final lines = [
      for (final e in events)
        if (flowEventText(e, _name, _step, field: _fieldLabel) case final String text) (text, (e['at'] as num?)?.toInt() ?? 0),
    ];
    final mine = d['requester'] == widget.app.me?.id;
    final canCancel = mine && (status == 'running' || status == 'returned');
    final headPart = <Widget>[
      Row(children: [
        _StatusChip(status: status),
        const SizedBox(width: 8),
        if (events.where((e) => e['kind'] == 'decided' && (e['data'] as Map?)?['decision'] == 'return').length case final n when n > 0) ...[
          ProcessChip(text: tr('Bị trả lại {0} lần', [n]), color: kFlowOrange),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(tr('{0} · người đề xuất: {1}', ['${_def['name'] ?? ''}', _name('${d['requester']}')]),
              style: TextStyle(color: pal.sub, fontSize: 13)),
        ),
      ]),
      // Tiến độ (bước Báo tiến độ).
      FlowProgressBar(progress: d['progress']),
    ];
    final delegPart = <Widget>[
      if (_delegationRequest case final Map req) DelegationSummary(app: widget.app, data: req, flowNames: _flowNames),
    ];
    final taskPart = <Widget>[
      // Phẳng (không khung riêng): nằm trong một khung "Bước tiếp theo"; nhiều việc thì vạch ngăn.
      for (final (ti, t) in tasks.indexed)
        Container(
          decoration: ti == 0 ? null : BoxDecoration(border: Border(top: BorderSide(color: pal.divider))),
          child: Padding(
            padding: EdgeInsets.only(top: ti == 0 ? 0 : 12, bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t.kind == 'resubmit' ? tr('Đơn bị trả lại, cần sửa và nộp lại') : '${flowTaskKindLabel(t.kind)}: ${_step(t.node)}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              const SizedBox(height: 10),
              if (t.request case final Map<String, dynamic> req) FlowRequestInfo(request: req),
              if (t.returned case final Map<String, dynamic> ret) FlowNotice(text: flowReturnedText(ret, _name)),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else if (t.kind == 'action' && t.action != null)
                FlowTaskActionPanel(
                  key: ValueKey('task-action-${t.id}'),
                  task: t,
                  onSubmit: (data) async {
                    await api.submit(t.id, data);
                    flowsChanged.value++;
                    await _load();
                  },
                )
              else if (t.kind == 'approval' && _node(t.node)?['type'] == 'claim')
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(onPressed: () => _decide(t, 'approve'), icon: const Icon(Icons.front_hand_outlined, size: 18), label: Text(tr('Tiếp nhận'))),
                )
              else if (t.kind == 'approval' && _node(t.node)?['type'] == 'start_flow')
                Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
                  OutlinedButton(onPressed: () => _decide(t, 'reject'), child: Text(tr('Không đẩy sang'))),
                  FilledButton(onPressed: () => _decide(t, 'approve'), child: Text(tr('Xác nhận đẩy sang'))),
                ])
              else if (t.kind == 'approval')
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
                  if (_node(t.node)?['type'] == 'approval_request'
                      ? _returnSteps(t).isNotEmpty
                      : _node(t.node)?['allow_return'] != false && _node(t.node)?['type'] != 'delegate_approve')
                    TextButton(onPressed: () => _decide(t, 'return'), child: Text(tr('Trả lại'))),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: kFlowRed),
                    onPressed: () => _decide(t, 'reject'),
                    child: Text(tr('Từ chối')),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kFlowGreen),
                    onPressed: () => (_node(t.node)?['fields'] as List? ?? const []).isNotEmpty || (_node(t.node)?['editable'] as List? ?? const []).isNotEmpty
                        ? _approveWithForm(t)
                        : _decide(t, 'approve'),
                    child: Text(tr('Duyệt')),
                  ),
                ])
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(onPressed: () => _fill(t), child: Text(t.kind == 'resubmit' ? tr('Sửa và nộp lại') : tr('Mở để làm'))),
                ),
            ]),
          ),
        ),
    ];
    final contentPart = <Widget>[
      const SizedBox(height: 16),
      Text(tr('Nội dung đơn'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      const SizedBox(height: 6),
      for (final f in _form) ?_fieldRow(pal, f, form[f.key]),
      // Thông tin nhập ở các bước "Điền thông tin" (vd chấm công: vị trí, Wi-Fi, ảnh chụp).
      for (final (name, fields, out) in _stepInputs(d)) ...[
        const SizedBox(height: 14),
        Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 4),
        for (final f in fields) ?_fieldRow(pal, f, out[f.key]),
      ],
    ];
    // Diễn biến: một đường thời gian, mỗi bước một nút, sự kiện nằm dưới bước đang diễn ra lúc đó (trước bước đầu: nút
    // "Tạo tiến trình"); việc đang chờ mình (Duyệt / Từ chối...) là "Bước tiếp theo" ngay dưới bước đang chờ; các bước
    // sắp tới mờ ở dưới.
    final next = taskPart.isEmpty ? null : FlowNextStep(children: taskPart);
    final railNodes = <FlowRailNode>[];
    final startEvents = <Widget>[];
    // Trả lại: quyết định "Trả lại" chia diễn biến thành các lượt; lượt cũ mờ, sau đó là dòng "Bị trả lại về «bước»".
    final returnsAt = <int, Map<String, dynamic>>{
      for (final e in events)
        if (e['kind'] == 'decided' && (e['data'] as Map?)?['decision'] == 'return') (e['at'] as num?)?.toInt() ?? 0: e,
    };
    var open = 0;
    final cuts = <(int, int, FlowReturnInfo)>[]; // (đầu lượt, hết lượt, thông tin trả lại)
    var prefixEnd = -1;
    for (final line in flowTimeline(d, lines, _step)) {
      final row = FlowTimelineRow(line: line, when: _when(line.at));
      final ret = line.kind == 'event' ? returnsAt[line.at] : null;
      if (ret != null) {
        final rd = (ret['data'] as Map?) ?? const {};
        final target = _step('${rd['return_step'] ?? ''}');
        final targetName = '${_node('${rd['return_step'] ?? ''}')?['name'] ?? target}';
        var from = open;
        final hit = railNodes.indexWhere((n) => n.title == target, open);
        if (hit >= 0) from = hit;
        if (cuts.isEmpty) prefixEnd = from;
        cuts.add((cuts.isEmpty ? from : open, railNodes.length, FlowReturnInfo(
          step: targetName,
          who: _name('${rd['by'] ?? ret['by'] ?? ''}'),
          when: _when(line.at),
          reason: '${rd['comment'] ?? ''}'.trim() == 'null' ? '' : '${rd['comment'] ?? ''}'.trim(),
        )));
        open = railNodes.length;
        // Lượt mới bắt đầu lại từ bước được trả về.
        railNodes.add(FlowRailNode(state: 'done', title: target, children: []));
        continue;
      }
      switch (line.kind) {
        case 'event':
          if (railNodes.isEmpty) {
            startEvents.add(row);
          } else {
            railNodes.last.children.add(row);
          }
        default:
          railNodes.add(FlowRailNode(
            state: switch (line.kind) { 'done' => 'done', 'active' => 'active', 'error' => 'failed', _ => 'pending' },
            title: line.text,
            detail: [if (line.at > 0) _when(line.at), ?line.detail].join(' · '),
            children: [],
          ));
      }
    }
    final currentNodes = railNodes.sublist(open);
    // Việc đang chờ: dưới bước đang chạy trùng tên bước của việc, không thì bước đang chạy cuối cùng (của lượt hiện tại).
    final waitName = tasks.isEmpty ? '' : _step(tasks.first.node);
    final byName = currentNodes.indexWhere((n) => n.title == waitName && n.state != 'pending');
    FlowRailNode? hostNode = byName >= 0 ? currentNodes[byName] : currentNodes.where((n) => n.state == 'active').lastOrNull;
    if (byName >= 0 && currentNodes[byName].state == 'done') {
      // Bước được trả về đang chờ làm lại: tô như bước hiện tại.
      final n = currentNodes[byName];
      hostNode = currentNodes[byName] = FlowRailNode(state: 'active', title: n.title, detail: n.detail, children: n.children);
    }
    if (next != null && hostNode == null && waitName.isNotEmpty) {
      // Bước chờ người (duyệt, điền...) không có dòng riêng trong diễn biến: thêm nút bước đang chờ trước các bước sắp tới.
      hostNode = FlowRailNode(state: 'active', title: waitName, children: []);
      final at = currentNodes.indexWhere((n) => n.state == 'pending');
      currentNodes.insert(at < 0 ? currentNodes.length : at, hostNode);
    }
    if (next != null) hostNode?.children.add(next);
    final startNode = FlowRailNode(state: 'done', title: tr('Tạo tiến trình'), children: startEvents);
    final timelinePart = <Widget>[
      const SizedBox(height: 16),
      Row(children: [
        Text(tr('Diễn biến'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
      ]),
      const SizedBox(height: 10),
      if (cuts.isEmpty)
        FlowRail(nodes: [
          if (startEvents.isNotEmpty || currentNodes.isEmpty) startNode,
          ...currentNodes,
        ])
      else
        FlowRounds(
          prefix: [if (startEvents.isNotEmpty) startNode, ...railNodes.sublist(0, prefixEnd < 0 ? 0 : prefixEnd)],
          rounds: [for (final (from, to, info) in cuts) FlowRound(nodes: railNodes.sublist(from, to), ret: info)],
          current: currentNodes,
        ),
    ];
    final nextPart = <Widget>[
      if (next != null && hostNode == null) ...[const SizedBox(height: 16), next],
    ];
    final debugPart = <Widget>[
      if (mine) FlowDebugPanel(data: d, stepName: _step, when: _whenSec),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: flowLeading(context),
        title: Text('${d['title']}', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: tr('In phiếu'), onPressed: _print, icon: const Icon(Icons.print_outlined)),
          IconButton(tooltip: tr('Tải lại'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          if (canCancel) IconButton(tooltip: tr('Hủy đơn'), onPressed: _cancel, icon: const Icon(Icons.block_rounded)),
          PopupMenuButton<String>(
            tooltip: tr('Thêm'),
            onSelected: (_) => copyFlowCodes(context, [
              ('instance', '${d['id'] ?? widget.instanceId}'),
              ('flow', '${d['flow_id'] ?? ''} v${d['flow_version'] ?? ''}'),
              for (final w in (d['waiting'] as List? ?? const []))
                if (w is Map) ('node', '${w['node']} (${d['flow_id'] ?? ''}-${_node('${w['node']}')?['no'] ?? '?'})'),
            ]),
            itemBuilder: (_) => [PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: const Icon(Icons.copy_rounded), title: Text(tr('Sao chép mã'))))],
          ),
        ],
      ),
      // Vùng rộng (từ 720px, theo bề rộng thật của vùng chi tiết): 2 cột, trái là quá trình chạy (trạng thái, tiến độ,
      // diễn biến, rồi "Bước tiếp theo" là việc đang chờ mình), phải là nội dung đơn. Hẹp: một cột, cùng thứ tự.
      body: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 720) {
          return RefreshIndicator(
            onRefresh: _load,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [...headPart, ...delegPart, ...contentPart, ...timelinePart, ...nextPart, ...debugPart]),
              ),
            ),
          );
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 3,
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(key: const ValueKey('run-timeline'), padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [...headPart, ...timelinePart, ...nextPart, ...debugPart]),
            ),
          ),
          VerticalDivider(width: 1, color: pal.divider),
          Expanded(
            flex: 2,
            child: Material(
              color: Color.alphaBlend(pal.surface2.withValues(alpha: .35), pal.bg),
              child: ListView(
                key: const ValueKey('run-actions'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [...delegPart, ...contentPart],
              ),
            ),
          ),
        ]);
      }),
    );
  }
}

/// Nút "Quy trình" ở thanh dưới (thay vị trí "Luồng"): tạm thời báo tính năng đang phát triển.
class FlowsComingSoon extends StatelessWidget {
  final Widget? header;
  final double bottomPadding;
  const FlowsComingSoon({super.key, this.header, this.bottomPadding = 0});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Column(children: [
      ?header,
      Expanded(
        child: Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 24, 32, 24 + bottomPadding),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: pal.accent.withValues(alpha: .12), shape: BoxShape.circle),
                child: Icon(Icons.account_tree_outlined, size: 42, color: pal.accentText),
              ),
              const SizedBox(height: 18),
              Text(tr('Tính năng đang phát triển'), textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.text)),
              const SizedBox(height: 8),
              Text(tr('Quy trình sẽ giúp nộp đề xuất, duyệt nhiều cấp ngay trong chat và để trợ lý AI xử lý chứng từ. Luồng tin nhắn đã chuyển sang tab "Luồng riêng" trong Chat.'),
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, color: pal.sub, height: 1.4)),
            ]),
          ),
        ),
      ),
    ]);
  }
}
