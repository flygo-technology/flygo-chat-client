import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../browser/flygo_id.dart' show FlygoId, FlygoIdException;

/// Gọi dịch vụ Flows (quy trình, phê duyệt) ở `https://<máy chủ chat>/__apps/flows/*`.
/// Xác thực: máy chủ có Flygo ID thì dùng vé Flygo ID (JWT, audience vn.flygo.flows, đổi từ phiên chat); không có
/// Flygo ID hoặc Flygo ID lỗi mạng / 5xx thì dùng token máy chủ chat của người dùng + X-MM-Server như trước.

class FlowsException implements Exception {
  final int status;
  final String message;
  /// Lỗi kiểm flow (khi lưu flow), nếu có.
  final List<Map<String, dynamic>> issues;
  FlowsException(this.status, this.message, [this.issues = const []]);
  @override
  String toString() => message;
}

/// Một trường của form (giống `Field` phía máy chủ).
class FlowField {
  final String key, label, type;
  final bool required;
  final List<String> options;
  /// Gợi ý trong ô nhập; giá trị điền sẵn.
  final String hint;
  final Object? defaultValue;
  /// Trường kiểu bảng: các cột. Trường / cột tự tính: `calc = {a, op: mul|add|sub|div, b}`.
  final List<FlowField> columns;
  final Map<String, dynamic>? calc;
  /// Loại tiền của trường money ("USD"...; rỗng = đồng). Điều kiện hiện ("form.x > 5"). Danh mục (tool MCP).
  final String currency;
  final String showIf;
  final Map<String, dynamic>? lookup;
  const FlowField({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.options = const [],
    this.hint = '',
    this.defaultValue,
    this.columns = const [],
    this.calc,
    this.currency = '',
    this.showIf = '',
    this.lookup,
  });

  factory FlowField.fromJson(Map j) => FlowField(
        key: '${j['key']}',
        label: '${j['label'] ?? ''}'.isEmpty ? '${j['key']}' : '${j['label']}',
        type: '${j['type'] ?? 'text'}',
        required: j['required'] == true,
        options: [for (final o in (j['options'] as List? ?? const [])) '$o'],
        hint: '${j['hint'] ?? ''}',
        defaultValue: j['default'],
        columns: listOf(j['columns']),
        calc: (j['calc'] as Map?)?.cast<String, dynamic>(),
        currency: '${j['currency'] ?? ''}'.toUpperCase() == 'VND' ? '' : '${j['currency'] ?? ''}',
        showIf: '${j['show_if'] ?? ''}',
        lookup: (j['lookup'] as Map?)?.cast<String, dynamic>(),
      );

  static List<FlowField> listOf(Object? v) => [for (final f in (v as List? ?? const [])) if (f is Map) FlowField.fromJson(f)];
}

/// Flow người dùng được phép bắt đầu.
class FlowDefInfo {
  final String id, name, icon;
  /// Danh mục để nhóm trên trang "Tạo luồng mới"; rỗng = chưa phân loại.
  final String category;
  final int version;
  final List<FlowField> form;
  /// Chỉ có ý nghĩa khi quản trị tải danh sách đầy đủ (`defs(all: true)`): đang bật, đang ẩn, mình tạo việc được.
  final bool active, hidden, canStart;
  /// Quản trị ghim cho cả công ty (hiện ở mục Ghim của mọi người).
  final bool pinnedAll;
  /// Giới thiệu ngắn (trang quy trình trên máy tính).
  final String description;
  /// "Thử nghiệm": hiện cho mọi người (có nhãn) nhưng chưa bắt đầu được.
  final bool experimental;
  const FlowDefInfo({
    required this.id,
    required this.name,
    required this.icon,
    required this.version,
    required this.form,
    this.category = '',
    this.active = true,
    this.hidden = false,
    this.canStart = true,
    this.pinnedAll = false,
    this.description = '',
    this.experimental = false,
  });

  factory FlowDefInfo.fromJson(Map j) => FlowDefInfo(
        id: '${j['id']}',
        name: '${j['name'] ?? j['id']}',
        icon: '${j['icon'] ?? ''}',
        category: '${j['category'] ?? ''}'.trim(),
        version: (j['version'] as num?)?.toInt() ?? 0,
        form: FlowField.listOf(j['form']),
        active: j['active'] != false,
        hidden: j['hidden'] == true,
        canStart: j['can_start'] != false,
        pinnedAll: j['pinned_all'] == true,
        description: '${j['description'] ?? ''}'.trim(),
        experimental: j['experimental'] == true,
      );
}

/// Việc đang chờ mình.
class FlowTask {
  final int id;
  final String instanceId, node, kind, title, flowId;
  final int? dueAt;
  final int createdAt;
  /// Việc nhận thay (ủy quyền): người được thay.
  final String? onBehalf;
  /// Bản JSON gốc (thông tin thêm theo loại việc, xem [action], [request], [returned], [prefill]).
  final Map<String, dynamic> raw;
  const FlowTask(
      {required this.id,
      required this.instanceId,
      required this.node,
      required this.kind,
      required this.title,
      required this.flowId,
      this.dueAt,
      required this.createdAt,
      this.onBehalf,
      this.raw = const {}});

  Map<String, dynamic>? _m(String k) => raw[k] is Map ? (raw[k] as Map).cast<String, dynamic>() : null;
  /// Việc "action" (Chờ bấm nút / Lựa chọn): `{kind: buttons, prompt, buttons: [{id, label, style, confirm, url}]}` hoặc
  /// `{kind: choice, prompt, choices: {id, options, min, max, submit_label, confirm, done}}`. Nộp bằng [FlowsApi.submit]
  /// `{clicked: id}` / `{values: [...]}`.
  Map<String, dynamic>? get action => _m('action');
  /// Việc duyệt của bước Tạo phê duyệt: `{title, reason, mode, fields, editable, return_steps: [{id, label}], level,
  /// escalated_to, due_at}`.
  Map<String, dynamic>? get request => _m('request');
  /// Bước Điền thông tin bị trả lại: `{reason, by, at, from}`; [prefill]: dữ liệu lần trước.
  Map<String, dynamic>? get returned => _m('returned');
  Map<String, dynamic>? get prefill => _m('prefill');
  /// Các bước được trả về (bước Tạo phê duyệt).
  List<Map<String, dynamic>> get returnSteps =>
      [for (final x in (request?['return_steps'] as List? ?? const [])) if (x is Map && '${x['id'] ?? ''}'.isNotEmpty) x.cast<String, dynamic>()];

  factory FlowTask.fromJson(Map j) => FlowTask(
        id: (j['id'] as num).toInt(),
        instanceId: '${j['instance_id']}',
        node: '${j['node']}',
        kind: '${j['kind']}',
        title: '${j['title'] ?? ''}',
        flowId: '${j['flow_id'] ?? ''}',
        dueAt: (j['due_at'] as num?)?.toInt(),
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
        onBehalf: j['on_behalf'] as String?,
        raw: j.cast<String, dynamic>(),
      );
}

/// Tiến trình (process): đối tượng nghiệp vụ do quy trình tạo ra và cập nhật (vd mỗi hoá đơn). Không chiếm chỗ chạy,
/// chỉ là dữ liệu: bước cố định, trạng thái chữ + màu, thống kê, nhãn, tệp, thẻ đã gửi, lịch sử.
class FlowProcess {
  final Map<String, dynamic> raw;
  const FlowProcess(this.raw);
  factory FlowProcess.fromJson(Map j) => FlowProcess(j.cast<String, dynamic>());

  String _s(String k) => '${raw[k] ?? ''}';
  List<Map<String, dynamic>> _list(String k) => [for (final x in (raw[k] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];

  String get id => _s('id');
  String get flowId => _s('flow_id');
  String get flowName => _s('flow_name').isEmpty ? flowId : _s('flow_name');
  String get flowIcon => _s('flow_icon');
  String get key => _s('key');
  String get name => _s('name').isEmpty ? (key.isEmpty ? id : key) : _s('name');
  String get icon => _s('icon');
  /// running | failed | done | cancelled | skipped
  String get state => _s('state').isEmpty ? 'running' : _s('state');
  String get currentStep => _s('current_step');
  String get statusText => _s('status_text');
  /// gray | blue | green | orange | red
  String get tone => _s('tone');
  /// [{key, title, state: pending|active|done|failed|skipped}]
  List<Map<String, dynamic>> get steps => _list('steps');
  /// [{key, label, type: number|text, value}]. Khoá bắt đầu bằng "_" là dữ liệu nội bộ của quy trình: không hiện.
  List<Map<String, dynamic>> get stats => [for (final s in _list('stats')) if (!'${s['key'] ?? ''}'.startsWith('_')) s];
  List<String> get labels => [for (final x in (raw['labels'] as List? ?? const [])) '$x'];
  /// Chi tiết: [{name, kind: file|folder|link, file_id?, url?, size?, at}]
  List<Map<String, dynamic>> get files => _list('files');
  /// Chi tiết: [{channel_id?, user_id?, post_id, sync}]
  List<Map<String, dynamic>> get posts => _list('posts');
  /// Chi tiết: [{at, actor, node, kind, data}]
  List<Map<String, dynamic>> get events => _list('events');
  /// Chi tiết: câu hỏi của bước chờ đang mở hoặc ghi chú cuối ("Đã chọn: Ký", "Bị trả lại: ...").
  String get note => _s('note').trim();
  /// Chi tiết: nút / lựa chọn đang mở của các bước chờ: [{wait, kind: buttons|choice|approval, prompt, actions: [nút như
  /// thẻ], choices?}].
  List<Map<String, dynamic>> get actions => [for (final a in _list('actions')) if (a['closed'] != true) a];
  /// Chi tiết: việc đang chờ chính người xem ở các luồng gắn với tiến trình (như "Việc của tôi", kèm `fields` của bước
  /// Điền thông tin, `step_name`, `node_type`): điền / bấm / duyệt ngay trên trang tiến trình.
  List<FlowTask> get myTasks => [for (final t in _list('my_tasks')) FlowTask.fromJson(t)];
  /// Việc đã tạo tiến trình.
  String get instanceId => '${raw['instance_id'] ?? raw['created_by_instance'] ?? ''}';
  int _ms(String k) => (raw[k] as num?)?.toInt() ?? 0;
  int get createdAt => _ms('created_at');
  int get updatedAt => _ms('updated_at') == 0 ? createdAt : _ms('updated_at');
  int get finishedAt => _ms('finished_at');
  bool get finished => state == 'done' || state == 'cancelled' || state == 'skipped';

  /// Thuộc tính tự do {khoá: giá trị} (process_create.props / process_props).
  /// Khoá bắt đầu bằng "_" là dữ liệu nội bộ của quy trình (vd _key_api, _chung_tu): không hiện.
  Map<String, String> get props => {
        for (final e in ((raw['props'] as Map?) ?? const {}).entries)
          if (!'${e.key}'.startsWith('_')) '${e.key}': e.value is List ? '${(e.value as List).length} dòng' : '${e.value ?? ''}',
      };
  /// Chi tiết: thuộc tính liên kết (tiến trình của quy trình khác có cùng giá trị hiện ở mục "Liên quan").
  List<String> get propsLink => [for (final x in (raw['props_link'] as List? ?? const [])) '$x'];
  /// Chi tiết: tên hiện của thuộc tính [{prop, label}].
  List<Map<String, dynamic>> get propFields => _list('prop_fields');
  /// Tên hiện của thuộc tính [k] (theo prop_fields), không có thì chính khoá.
  String propLabel(String k) {
    for (final f in propFields) {
      if ('${f['prop']}' == k && '${f['label'] ?? ''}'.trim().isNotEmpty) return '${f['label']}'.trim();
    }
    return k;
  }

  /// Bước hiện tại quá thời hạn (SLA) của bước.
  bool get overdue => raw['overdue'] == true || steps.any((st) => st['overdue'] == true && (st['state'] == 'active' || st['state'] == 'failed'));

  /// Chi tiết: người xem được huỷ tiến trình (quản trị hoặc người tạo luồng đã tạo ra nó, khi đang chạy / lỗi).
  bool get canCancel => raw['can_cancel'] == true;

  /// Tiến trình cha (chi tiết), null nếu không có / không được xem.
  FlowProcess? get parent => raw['parent'] is Map ? FlowProcess.fromJson(raw['parent'] as Map) : null;
  String get parentId => '${raw['parent_id'] ?? ''}';
  /// Chi tiết: tiến trình con (đã lọc quyền xem), theo quy trình rồi lúc tạo.
  List<FlowProcess> get children => [for (final x in _list('children')) FlowProcess(x)];
  /// Chi tiết: tiến trình của quy trình khác có cùng giá trị thuộc tính liên kết: [(khoá, nhãn, giá trị, tiến trình)].
  List<(String, String, String, List<FlowProcess>)> get related => [
        for (final g in _list('related'))
          (
            '${g['prop'] ?? ''}',
            '${g['label'] ?? ''}'.trim().isEmpty ? '${g['prop'] ?? ''}' : '${g['label']}'.trim(),
            '${g['value'] ?? ''}',
            [for (final x in (g['processes'] as List? ?? const [])) if (x is Map) FlowProcess.fromJson(x)],
          ),
      ];
  /// "Đang chờ 2/3 tiến trình con" (bước Chờ tiến trình đang chờ), rỗng nếu không chờ.
  String get waitingText {
    final w = raw['waiting'];
    if (w is! Map) return '';
    final t = '${w['text'] ?? ''}'.trim();
    if (t.isNotEmpty) return t;
    return w['total'] == null ? '' : '${w['matched'] ?? 0}/${w['total']}';
  }

  /// Tiêu đề bước hiện tại (theo key), rỗng nếu không có.
  String get currentStepTitle {
    final t = _s('current_step_title');
    if (t.isNotEmpty && steps.isEmpty) return t;
    for (final st in steps) {
      if ('${st['key']}' == currentStep) return '${st['title'] ?? st['key']}';
    }
    for (final st in steps) {
      if (st['state'] == 'active' || st['state'] == 'failed') return '${st['title'] ?? st['key']}';
    }
    return currentStep;
  }
}

class FlowsApi {
  final String token;
  final String server;
  final http.Client _http;
  FlowsApi(this.token, {String? server, http.Client? client})
      : server = server ?? kServerUrl,
        _http = client ?? debugClient ?? http.Client();

  /// Chỉ cho kiểm thử: client giả cho mọi FlowsApi tạo sau đó.
  @visibleForTesting
  static http.Client? debugClient;

  // ---------------------------------------------------------------- vé Flygo ID
  /// Flygo ID của máy chủ chat đang dùng theo phiên chat (null = máy chủ không có Flygo ID, dùng token chat).
  static final _ids = <String, Future<FlygoId?>>{};

  /// Quyền đổi (sự kiện custom_vn.flygo.sso_permission_changed) hoặc đăng xuất: bỏ vé đã nhớ, lần gọi sau xin vé mới.
  static void resetTickets() => _ids.clear();

  /// Bearer cho Flows: vé Flygo ID nếu có, không thì token chat. 403 từ Flygo ID (không được dùng Quy trình) báo lỗi
  /// thay vì lặng lẽ dùng token chat.
  Future<String> _bearer({bool refresh = false}) async {
    if (server != kServerUrl || debugClient != null) return token;
    FlygoId? id;
    try {
      id = await (_ids['$server|$token'] ??= FlygoId.current(token));
    } catch (_) {
      _ids.remove('$server|$token');
      return token;
    }
    if (id == null) return token;
    try {
      return await id.ticket('vn.flygo.flows', refresh: refresh);
    } on FlygoIdException catch (e) {
      if (e.status == 403) throw FlowsException(403, e.message);
      if (e.status == 401) throw FlowsException(401, e.message);
      return token;
    } catch (_) {
      return token;
    }
  }

  Future<Map<String, String>> _headers({bool refresh = false}) async => {
        'Authorization': 'Bearer ${await _bearer(refresh: refresh)}',
        'X-MM-Server': server,
        'Content-Type': 'application/json',
        'User-Agent': kUserAgent,
      };

  /// Gửi [build] với header xác thực; vé Flygo ID bị Flows từ chối (401) thì xin vé mới và gửi lại một lần.
  Future<http.Response> _authed(Future<http.Response> Function(Map<String, String> h) build) async {
    final r = await build(await _headers());
    if (r.statusCode != 401) return r;
    final h = await _headers(refresh: true);
    if (h['Authorization'] == 'Bearer $token') return r;
    return build(h);
  }

  /// Chuẩn app native (Sếp, 2026-11-11): gọi Flows ở `https://<máy chủ chat>/__apps/flows/*` (sso-shim chuyển vào dịch
  /// vụ Flows). Trạm `push.<tên miền>/flows` giữ cho webhook, form công khai, QR, MCP và app cũ; app mới không gọi API ở đó.
  String get base => _legacy.contains(server) ? publicBase : '${server.replaceAll(RegExp(r'/+$'), '')}/__apps';

  /// Máy chủ chưa có đường `/__apps/flows` (sso-shim / Flows cũ trả 404 không phải JSON): gọi qua trạm đẩy
  /// như trước, nhớ tới khi tắt app.
  static final _legacy = <String>{};

  /// Địa chỉ đã phát ra ngoài (URL webhook hiện cho quản trị): trạm đẩy của máy chủ, không có thì máy chủ chat.
  String get publicBase {
    final p = pushUrlFor(server);
    return p.isEmpty ? server : p;
  }

  Uri _uri(String path, [Map<String, String>? q]) => Uri.parse('$base/flows$path').replace(queryParameters: q);

  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final r = await _authed((h) async {
      final req = http.Request(method, _uri(path, query))..headers.addAll(h);
      if (body != null) req.body = jsonEncode(body);
      return http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    });
    if (r.statusCode == 404 && !_legacy.contains(server) && !_isFlowsError(r)) {
      _legacy.add(server);
      return _send(method, path, body: body, query: query);
    }
    final j = _decode(r);
    if (method == 'GET' && (query == null || (path == '/instances' && query['scope'] == 'related')) && _homePaths.contains(path)) _remember(path, j);
    return j;
  }

  // ---------------------------------------------------------------- bản lưu trang Quy trình
  // Mở trang Quy trình hiện ngay danh sách lần trước (bộ nhớ + tệp trong thư mục app), rồi tải bản mới ở nền:
  // mạng chậm (đường hầm Cloudflare chập chờn) không bắt người dùng nhìn vòng xoay. Lưu theo máy chủ + phiên đăng nhập.
  static const _homePaths = {'/tasks', '/instances', '/me'};
  static Map<String, dynamic>? _cache;

  String get _cacheKey {
    var h = 0x811c9dc5;
    for (final c in token.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return '$server|${h.toRadixString(16)}';
  }

  static Future<File> _cacheFile() async => File('${(await getApplicationSupportDirectory()).path}/flows_home_cache.json');

  static Future<Map<String, dynamic>> _loadCache() async {
    if (_cache != null) return _cache!;
    try {
      final f = await _cacheFile();
      _cache = f.existsSync() ? (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>() : {};
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  void _remember(String path, dynamic j) {
    if (j is! Map) return;
    () async {
      final c = await _loadCache();
      final mine = ((c[_cacheKey] as Map?) ?? {}).cast<String, dynamic>();
      mine[path] = j;
      // Chỉ giữ phiên hiện tại của mỗi máy chủ.
      c.removeWhere((k, _) => k.startsWith('$server|') && k != _cacheKey);
      c[_cacheKey] = mine;
      try {
        await (await _cacheFile()).writeAsString(jsonEncode(c));
      } catch (_) {}
    }();
  }

  /// Bản lưu lần trước của trang Quy trình: (việc chờ tôi, luồng của tôi, quyền), null nếu chưa có.
  Future<({List<FlowTask>? tasks, List<Map<String, dynamic>>? instances, Map<String, dynamic>? me})> cachedHome() async {
    final mine = (await _loadCache())[_cacheKey] as Map?;
    final t = mine?['/tasks'] as Map?, i = mine?['/instances'] as Map?, m = mine?['/me'] as Map?;
    return (
      tasks: t == null ? null : [for (final x in (t['tasks'] as List? ?? const [])) if (x is Map) FlowTask.fromJson(x)],
      instances: i == null ? null : [for (final x in (i['instances'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()],
      me: m?.cast<String, dynamic>(),
    );
  }

  /// Câu trả lời của chính Flows (JSON), khác 404 của đường dẫn chưa có (trang / chữ của shim, hoặc thân rỗng).
  static bool _isFlowsError(http.Response r) {
    try {
      return jsonDecode(utf8.decode(r.bodyBytes)) is Map;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void debugResetLegacy() => _legacy.clear();

  dynamic _decode(http.Response r) {
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      j = null;
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final issues = [for (final i in (j is Map ? j['issues'] as List? ?? const [] : const [])) if (i is Map) i.cast<String, dynamic>()];
      final msg = j is Map && j['error'] != null ? '${j['error']}' : 'Flows ${r.statusCode}';
      throw FlowsException(r.statusCode, msg, issues);
    }
    return j;
  }

  /// Quy trình mình tạo việc được. [all]: quản trị nhận cả quy trình đang tắt / đang ẩn (người thường: như bình thường).
  Future<List<FlowDefInfo>> defs({bool all = false}) async {
    final j = await _send('GET', '/defs', query: all ? const {'all': '1'} : null) as Map;
    return [for (final d in (j['flows'] as List? ?? const [])) if (d is Map) FlowDefInfo.fromJson(d)];
  }

  /// Nộp đơn mới; trả về id đơn.
  /// Bắt đầu luồng. [startId] + [postId]: tạo từ menu tin nhắn (nốt "Từ một tin nhắn").
  Future<String> start(String flowId, Map<String, dynamic> form, {String title = '', String? startId, String? postId}) async {
    final j = await _send('POST', '/start', body: {
      'flow_id': flowId,
      'form': form,
      'title': title,
      'start_id': ?startId,
      'post_id': ?postId,
    }) as Map;
    return '${j['id']}';
  }

  /// Trạng thái các nốt Bắt đầu (`starts`: {id: {ok_at, error}}) + link form công khai (`public_form`: {url, qr}).
  /// [rotate] = "public_form": đổi link mới.
  Future<Map<String, dynamic>> startInfo(String flowId, {String? rotate}) async =>
      (await _send('GET', '/admin/defs/$flowId/starts', query: rotate == null ? null : {'rotate': rotate}) as Map).cast<String, dynamic>();

  /// Quy trình có mục "Tạo luồng từ tin này" mà tôi được dùng: [{flow_id, start_id, name, icon, label}].
  Future<List<Map<String, dynamic>>> messageStarts() async {
    final j = await _send('GET', '/message-starts') as Map;
    return [for (final x in (j['starts'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
  }

  /// Biểu mẫu điền sẵn từ một tin nhắn: {form, title}.
  Future<Map<String, dynamic>> prefill(String flowId, String startId, String postId) async =>
      (await _send('POST', '/prefill', body: {'flow_id': flowId, 'start_id': startId, 'post_id': postId}) as Map).cast<String, dynamic>();

  /// Việc của mình. [related]: cả việc mình được giao duyệt / được nhắn (tab Đang chạy, Đã xong).
  Future<List<Map<String, dynamic>>> instances({bool related = false}) async {
    final j = await _send('GET', '/instances', query: related ? const {'scope': 'related'} : null) as Map;
    return [for (final i in (j['instances'] as List? ?? const [])) if (i is Map) i.cast<String, dynamic>()];
  }

  Future<Map<String, dynamic>> instance(String id) async => (await _send('GET', '/instances/$id') as Map).cast<String, dynamic>();

  Future<List<FlowTask>> tasks() async {
    final j = await _send('GET', '/tasks') as Map;
    return [for (final t in (j['tasks'] as List? ?? const [])) if (t is Map) FlowTask.fromJson(t)];
  }

  /// [decision]: approve | reject | return. Từ chối / trả lại phải có lý do.
  /// [form]: thông tin nhập khi duyệt và trường người duyệt được sửa. [returnStep]: bước Tạo phê duyệt, trả lại về bước
  /// nào (một trong `request.return_steps`; bỏ trống = bước đầu).
  Future<void> decide(int taskId, String decision, {String? comment, Map<String, dynamic>? form, String? returnStep}) =>
      _send('POST', '/tasks/$taskId/decide', body: {'decision': decision, 'comment': ?comment, 'form': ?form, 'return_step': ?returnStep});

  /// Bấm nút "chạy tiếp quy trình" trên tin nhắn.
  Future<void> click(String instanceId, String node, String label) => _send('POST', '/instances/$instanceId/click', body: {'node': node, 'label': label});

  /// Tìm trong danh mục của một trường: [field] = `khoa`, `bang.cot` hoặc `<id bước>:khoa`.
  Future<List<Map<String, dynamic>>> lookup(String flowId, String field, String q) async {
    final j = await _send('POST', '/lookup', body: {'flow_id': flowId, 'field': field, 'q': q}) as Map;
    return [for (final x in (j['items'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
  }

  /// Trình soạn thử danh mục: `{items, keys}`.
  Future<Map<String, dynamic>> lookupTest(Map<String, dynamic> lookup, String q) async =>
      (await _send('POST', '/admin/lookup-test', body: {'lookup': lookup, 'q': q}) as Map).cast<String, dynamic>();

  /// Webhook của quy trình: `{path, secret, last_payload, last_at}`; [rotate] đổi URL và secret.
  Future<Map<String, dynamic>> webhook(String flowId, {bool rotate = false}) async =>
      (await _send('GET', '/admin/defs/$flowId/webhook', query: rotate ? {'rotate': '1'} : null) as Map).cast<String, dynamic>();

  /// Nộp form của việc (form_task, việc tay) hoặc sửa và nộp lại đơn bị trả.
  Future<void> submit(int taskId, Map<String, dynamic> data) => _send('POST', '/tasks/$taskId/submit', body: {'data': data});

  Future<void> cancel(String instanceId, {String reason = ''}) => _send('POST', '/instances/$instanceId/cancel', body: {'reason': reason});

  /// Tải tệp đính kèm lên; trả về `{id, name, size, mime_type}` để đưa vào trường kiểu files.
  Future<Map<String, dynamic>> upload(String name, Uint8List bytes) async {
    final r = await _http
        .post(_uri('/files', {'filename': name}), headers: {...await _headers(), 'Content-Type': 'application/octet-stream'}, body: bytes)
        .timeout(const Duration(minutes: 2));
    return (_decode(r) as Map).cast<String, dynamic>();
  }

  /// Tải tệp đính kèm của một đơn (chỉ người liên quan tới đơn).
  Future<Uint8List> file(String instanceId, String fileId) async {
    final r = await _http.get(_uri('/instances/$instanceId/files/$fileId'), headers: await _headers()).timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) _decode(r);
    return r.bodyBytes;
  }

  // ---------------------------------------------------------------- quản trị (flow_admin / system_admin)

  /// Mọi flow (cả flow đang tắt), bản mới nhất. Không phải quản trị: FlowsException 403.
  Future<List<Map<String, dynamic>>> adminDefs() async {
    final j = await _send('GET', '/admin/defs') as Map;
    return [for (final f in (j['flows'] as List? ?? const [])) if (f is Map) f.cast<String, dynamic>()];
  }

  /// JSON đầy đủ của flow (bản mới nhất hoặc [version]).
  Future<Map<String, dynamic>> getDef(String id, {int? version}) async =>
      (await _send('GET', '/defs/$id', query: version == null ? null : {'version': '$version'}) as Map).cast<String, dynamic>();

  /// Kiểm lỗi + chạy thử, không lưu: `{ok, issues, traces}`.
  Future<Map<String, dynamic>> checkDef(Map<String, dynamic> def) async => (await _send('POST', '/defs/check', body: def) as Map).cast<String, dynamic>();

  /// Lưu phiên bản mới; trả về số phiên bản. Còn lỗi: FlowsException 422 kèm issues.
  Future<int> saveDef(Map<String, dynamic> def) async => ((await _send('POST', '/defs', body: def) as Map)['version'] as num).toInt();

  /// Tạo quy trình mới ngay trên máy chủ (mã 6 ký tự, đang tắt): `{id, def}`.
  Future<Map<String, dynamic>> newDef({String? name, String? category}) async =>
      (await _send('POST', '/admin/defs', body: {'name': ?name, 'category': ?category}) as Map).cast<String, dynamic>();

  Future<void> setActive(String id, bool active) => _send('POST', '/defs/$id/active', body: {'active': active});

  /// Ghim / bỏ ghim quy trình cho cả công ty (quản trị).
  Future<void> setPinnedAll(String id, bool pinned) => _send('POST', '/defs/$id/pin', body: {'pinned': pinned});

  /// Sao chép quy trình thành quy trình mới (mã mới, đang tắt). Trả về `{id, name}`.
  Future<Map<String, dynamic>> copyDef(String id) async => (await _send('POST', '/admin/defs/$id/copy', body: const {}) as Map).cast<String, dynamic>();

  /// Ẩn / hiện quy trình trên tab Quy trình (quản trị vẫn thấy, mờ).
  Future<void> setHidden(String id, bool hidden) => _send('POST', '/defs/$id/hidden', body: {'hidden': hidden});

  /// Cho trình soạn: bot AI gọi được, máy chủ MCP + tool, Kết nối AI. [flow], [runAs]: quy trình đang soạn và chế độ
  /// chạy đang chọn (máy chủ có Flygo Gateway đọc danh sách công cụ bằng vé theo chế độ đó; máy chủ cũ bỏ qua).
  Future<Map<String, dynamic>> integrations({String? flow, String? runAs}) async {
    final q = [
      if (flow != null && flow.isNotEmpty) 'flow=${Uri.encodeQueryComponent(flow)}',
      if (runAs != null && runAs.isNotEmpty) 'run_as=${Uri.encodeQueryComponent(runAs)}',
    ];
    return (await _send('GET', '/admin/integrations${q.isEmpty ? '' : '?${q.join('&')}'}') as Map).cast<String, dynamic>();
  }

  /// Quy trình mẫu có sẵn trên máy chủ.
  Future<List<Map<String, dynamic>>> templates() async {
    final j = await _send('GET', '/admin/templates') as Map;
    return [for (final t in (j['templates'] as List? ?? const [])) if (t is Map) t.cast<String, dynamic>()];
  }

  /// Quyền của tôi: `{admin, viewer}`.
  Future<Map<String, dynamic>> me() async => (await _send('GET', '/me') as Map).cast<String, dynamic>();

  /// Tất cả luồng (quản trị / flow_viewer): `{total, instances, flows}`.
  Future<Map<String, dynamic>> allInstances(Map<String, String> filter) async =>
      (await _send('GET', '/admin/instances', query: filter) as Map).cast<String, dynamic>();

  /// Tệp Excel theo bộ lọc.
  Future<Uint8List> exportXlsx(Map<String, String> filter) async {
    final r = await _http.get(_uri('/admin/export.xlsx', filter), headers: await _headers()).timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) _decode(r);
    return r.bodyBytes;
  }

  /// Liên kết trang in phiếu (10 phút, mở trong trình duyệt).
  Future<String> printUrl(String instanceId) async {
    final j = await _send('POST', '/instances/$instanceId/print-link') as Map;
    return '$base${j['path']}';
  }

  /// Sơ đồ tổ chức: [{id, name, parent, manager, deputies, members}]. Ai cũng xem được.
  Future<List<Map<String, dynamic>>> departments() async => (await orgChart()).depts;

  /// Sơ đồ tổ chức kèm quyền sửa (chỉ quản trị).
  Future<({List<Map<String, dynamic>> depts, bool canEdit})> orgChart() async {
    final j = await _send('GET', '/org/departments') as Map;
    return (depts: [for (final d in (j['departments'] as List? ?? const [])) if (d is Map) d.cast<String, dynamic>()], canEdit: j['can_edit'] == true);
  }

  Future<void> saveDepartments(List<Map<String, dynamic>> depts) => _send('PUT', '/org/departments', body: {'departments': depts});

  Future<void> saveRoles(Map<String, List<String>> roles) => _send('PUT', '/org/roles', body: {'roles': roles});

  /// Ủy quyền khi vắng của tôi: `{delegation, delegated_to_me}`.
  Future<Map<String, dynamic>> myDelegation() async => (await _send('GET', '/me/delegation') as Map).cast<String, dynamic>();

  /// Ủy quyền: `{mine, to_me, flows: {id: tên}, request_flows: [{id, name, icon}]}` (còn hiệu lực hoặc hết hạn trong 30 ngày).
  Future<Map<String, dynamic>> myDelegations() async => (await _send('GET', '/me/delegations') as Map).cast<String, dynamic>();

  /// Các quy trình đang bật (chọn khi tự điền ủy quyền): [{id, name, icon, category}].
  Future<List<Map<String, dynamic>>> flowNames() async {
    final j = await _send('GET', '/names') as Map;
    return [for (final x in (j['flows'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
  }

  /// Mọi quy trình đang bật, `relevant` = có bước có thể giao việc cho tôi (trường Ủy quyền).
  Future<List<Map<String, dynamic>>> myDuties() async {
    final j = await _send('GET', '/my-duties') as Map;
    return [for (final x in (j['flows'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
  }

  /// Lịch làm việc: `{calendar: {weekdays: [1..7], holidays: ["YYYY-MM-DD"]}, can_edit}`.
  Future<Map<String, dynamic>> calendar() async => (await _send('GET', '/org/calendar') as Map).cast<String, dynamic>();

  Future<void> saveCalendar(List<int> weekdays, List<String> holidays) =>
      _send('PUT', '/org/calendar', body: {'calendar': {'weekdays': weekdays, 'holidays': holidays}});

  /// Báo cáo vận hành `days` ngày gần đây: {flows, steps, busy, stuck}.
  Future<Map<String, dynamic>> stats(int days) async => (await _send('GET', '/admin/stats', query: {'days': '$days'}) as Map).cast<String, dynamic>();

  /// Kết thúc sớm một ủy quyền (người ủy quyền hoặc quản trị).
  Future<void> endDelegation(int id) => _send('POST', '/me/delegations/$id/end');



  /// Vai trò tổ chức: tên vai trò -> id người.
  Future<Map<String, List<String>>> roles() async {
    final j = await _send('GET', '/org/roles') as Map;
    return {for (final e in ((j['roles'] as Map?) ?? const {}).entries) '${e.key}': [for (final u in (e.value as List? ?? const [])) '$u']};
  }

  // ---------------------------------------------------------------- tiến trình (process)

  /// Danh sách tiến trình. [state]: running | failed | done (cả cancelled / skipped: "done,cancelled,skipped").
  /// [props]: lọc theo thuộc tính (`prop.<k>=<v>`, mọi điều kiện đều phải đúng); [parent]: tiến trình con của mã này.
  Future<List<FlowProcess>> processes({String? flow, String? state, String? label, String? step, String? q, int? limit, Map<String, String>? props, String? parent}) async =>
      (await processesPage(flow: flow, state: state, label: label, step: step, q: q, limit: limit, props: props, parent: parent)).$1;

  /// Một trang danh sách tiến trình (mới cập nhật trước) và mốc trang sau (null = hết). [before]: mốc từ trang trước.
  Future<(List<FlowProcess>, String?)> processesPage(
      {String? flow, String? state, String? label, String? step, String? q, int? limit, Map<String, String>? props, String? parent, String? before}) async {
    final query = <String, String>{
      for (final e in (props ?? const <String, String>{}).entries) 'prop.${e.key}': e.value,
      if (parent != null && parent.isNotEmpty) 'parent': parent,
      if (flow != null && flow.isNotEmpty) 'flow': flow,
      if (state != null && state.isNotEmpty) 'state': state,
      if (label != null && label.isNotEmpty) 'label': label,
      if (step != null && step.isNotEmpty) 'step': step,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (limit != null) 'limit': '$limit',
      if (before != null && before.isNotEmpty) 'before': before,
    };
    final j = await _send('GET', '/processes', query: query.isEmpty ? null : query) as Map;
    final next = j['next'] is String && '${j['next']}'.isNotEmpty ? '${j['next']}' : null;
    return ([for (final x in (j['processes'] as List? ?? const [])) if (x is Map) FlowProcess.fromJson(x)], next);
  }

  /// Bảng theo dõi: tiến trình đang chạy / lỗi, ở bước lâu nhất trước. [dept]: phòng ban của người đang giao việc,
  /// [flow]: quy trình, [overdue]: chỉ quá hạn.
  Future<Map<String, dynamic>> board({String? dept, String? flow, bool overdue = false}) async {
    final q = <String, String>{
      if (dept != null && dept.isNotEmpty) 'dept': dept,
      if (flow != null && flow.isNotEmpty) 'flow': flow,
      if (overdue) 'overdue': '1',
    };
    return ((await _send('GET', '/board', query: q.isEmpty ? null : q)) as Map).cast<String, dynamic>();
  }

  /// Thời gian theo bước của các tiến trình tạo trong [from, to) (ms) của quy trình [flow].
  Future<Map<String, dynamic>> stepsReport(String flow, {int? from, int? to}) async =>
      ((await _send('GET', '/reports/steps', query: {'flow': flow, if (from != null) 'from': '$from', if (to != null) 'to': '$to'})) as Map).cast<String, dynamic>();

  /// Huỷ tiến trình (quản trị, hoặc người tạo luồng đã tạo ra nó): luồng tạo ra nó dừng và chạy nhánh "Khi luồng bị
  /// huỷ". [cascade]: huỷ cả tiến trình con, cháu chưa xong. Trả về {ok, state, instance_cancelled, cancelled_children}.
  /// Bấm nút / chọn / duyệt / nhập trên tiến trình, áp dụng ngay (POST /flows/processes/{id}/act). [action]: mã nút
  /// hoặc ô chọn của mục đang chờ (`"<bước>:<nút>"`); [text]: lý do / chữ nhập; [values]: lựa chọn; [value]: bước trả về.
  Future<void> processAct(String processId, String action, {String? text, List<String>? values, String? value}) =>
      _send('POST', '/processes/${Uri.encodeComponent(processId)}/act', body: {'action': action, 'text': ?text, 'values': ?values, 'value': ?value});

  Future<Map<String, dynamic>> cancelProcess(String id, {String reason = '', bool cascade = false}) async =>
      ((await _send('POST', '/processes/$id/cancel', body: {if (reason.trim().isNotEmpty) 'reason': reason.trim(), if (cascade) 'cascade': true})) as Map).cast<String, dynamic>();

  /// Chi tiết một tiến trình (kèm files, posts, events, instance_id).
  Future<FlowProcess> process(String id) async => FlowProcess.fromJson(await _send('GET', '/processes/$id') as Map);

  /// Tải tệp đính kèm của tiến trình.
  Future<Uint8List> processFile(String processId, String fileId) async {
    final r = await _http.get(_uri('/processes/$processId/files/$fileId'), headers: await _headers()).timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) _decode(r);
    return r.bodyBytes;
  }

  /// Báo cáo tiến trình của một quy trình: `{total, by_state, by_step, stats, daily}`. [from], [to]: mốc ms.
  Future<Map<String, dynamic>> processReport(String flowId, {int? from, int? to, String? label}) async {
    final query = <String, String>{
      if (from != null) 'from': '$from',
      if (to != null) 'to': '$to',
      if (label != null && label.isNotEmpty) 'label': label,
    };
    return (await _send('GET', '/defs/$flowId/report', query: query.isEmpty ? null : query) as Map).cast<String, dynamic>();
  }

  /// Giới thiệu một quy trình (ai thấy quy trình đều đọc được): `{id, name, icon, category, description, version, active,
  /// can_start, who_can_start: [{kind, id, name}], valid_from, valid_until, steps: [{id, no, name, type}]}`.
  Future<Map<String, dynamic>> flowInfo(String flowId) async => (await _send('GET', '/defs/$flowId/info') as Map).cast<String, dynamic>();

  /// Thống kê các lần chạy của quy trình: `{total, by_status, by_step, avg_duration_ms, done_count, daily}`.
  Future<Map<String, dynamic>> runsReport(String flowId, {int? from, int? to}) async {
    final query = <String, String>{if (from != null) 'from': '$from', if (to != null) 'to': '$to'};
    return (await _send('GET', '/defs/$flowId/runs-report', query: query.isEmpty ? null : query) as Map).cast<String, dynamic>();
  }

  /// Các lần chạy của một quy trình (quản trị: tất cả; người khác: có liên quan tới mình), mới nhất trước.
  Future<List<Map<String, dynamic>>> flowRuns(String flowId, {int limit = 200}) async {
    final j = await _send('GET', '/instances', query: {'flow': flowId, 'limit': '$limit'}) as Map;
    return [for (final i in (j['instances'] as List? ?? const [])) if (i is Map) i.cast<String, dynamic>()];
  }

  /// Mở thảo luận của tiến trình (tạo kênh nếu chưa có, thêm mình vào): `{channel_id, team_id, members: [{id, name}],
  /// unread}`. Người không liên quan: lỗi 403.
  Future<Map<String, dynamic>> processDiscussion(String processId) async =>
      (await _send('POST', '/processes/$processId/discussion') as Map).cast<String, dynamic>();

  /// Đưa tệp của một tin trong thảo luận vào tệp của tiến trình: `{ok, added}`.
  Future<Map<String, dynamic>> processFileFromPost(String processId, String postId, String fileId) async =>
      (await _send('POST', '/processes/$processId/files/from-post', body: {'post_id': postId, 'file_id': fileId}) as Map).cast<String, dynamic>();
}
