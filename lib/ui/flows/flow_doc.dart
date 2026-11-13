import 'dart:math';

import 'flow_editor_tables.dart' show newTableNode;
import 'flow_editor_upgrade.dart';

/// Mô hình soạn flow dạng sơ đồ dọc: chuỗi bước, bước "điều kiện" tách nhánh, bước "song song" chạy nhiều nhánh,
/// các nhánh gặp lại nhau ở bước kế tiếp. Đổi qua lại với JSON flow của máy chủ (nodes + edges): bộ chạy, lint,
/// bot AI dựng flow không phải đổi gì.

/// Một mục trong chuỗi bước.
sealed class FItem {
  String id;
  /// Số thứ tự cố định ("#12"), để tra nhanh khi người dùng chụp màn hình.
  int? no;
  FItem(this.id, [this.no]);
}

/// Bước thường: approval, form_task, ai, auto, notify, wait. [node] là JSON của node (không có cạnh).
class FStep extends FItem {
  Map<String, dynamic> node;
  /// Nhánh ra của bước nhiều cổng (chờ bấm nút, lựa chọn, tạo phê duyệt): mỗi nút / lựa chọn / kết quả một nhánh.
  /// Bước thường: rỗng.
  List<FPort> ports = [];
  FStep(this.node) : super('${node['id']}', (node['no'] as num?)?.toInt()) {
    syncPorts();
  }
  String get type => '${node['type']}';
  /// Loại hiển thị: bước tự động theo action (gọi công cụ, thêm / sửa ghi chú), còn lại như type.
  String get kind => type == 'auto' && const {'mcp', 'note_add', 'note_edit', 'delegate_set', 'user_status', 'chat_post'}.contains(node['action']) ? '${node['action']}' : type;
  String get name => '${node['name'] ?? ''}';

  /// Dựng lại danh sách nhánh theo cấu hình của bước (sau khi sửa nút / lựa chọn / hạn chờ...): nhánh còn khoá
  /// giữ nguyên các bước bên trong, nhánh mới thì trống, nhánh không còn thì bỏ.
  void syncPorts() {
    final keys = portKeys(node);
    ports = [
      for (final k in keys) ports.where((p) => p.key == k).firstOrNull ?? FPort(k, [], end: portEndsByDefault(type, k) || k == 'error', unwired: portEndsByDefault(type, k)),
    ];
  }

  // ------------------------------------------------------------------ cổng ra

  /// Loại bước có nhiều nhánh ra (mỗi nhánh ghi vào một trường `to` của node, không dùng cạnh).
  static const portTypes = {'wait_button', 'wait_choice', 'approval_request'};

  /// Loại bước có nhánh Lỗi (`on_error: {"to": "<bước>"}`): tự động, AI, chờ sự kiện, bắt đầu quy trình khác.
  static const errorTypes = {'auto', 'ai', 'wait_event', 'start_flow', 'process_wait', 'doc_render', 'mcp_pages'};

  /// Bước [node] rẽ sang nhánh Lỗi khi lỗi: sơ đồ có hai nhánh "Thành công" (cạnh đi ra) và "Lỗi" (`on_error.to`).
  static bool errorBranch(Map node) => errorTypes.contains(node['type']) && node['on_error'] is Map && (node['on_error'] as Map).containsKey('to');

  /// Bước đi tiếp bằng cạnh (nhánh "Thành công", ghi tạm `ok_to`) nhưng có thêm nhánh: nhánh Lỗi, hoặc nhánh Quá hạn
  /// của Chờ tiến trình (`timeout_to`).
  static bool okBranch(Map node) => errorBranch(node) || (node['type'] == 'process_wait' && _filled(node['timeout']));

  /// Bước có nhánh ra trên sơ đồ (bước nhiều cổng hoặc có nhánh Lỗi / Quá hạn).
  static bool hasPorts(Map node) => portTypes.contains(node['type']) || okBranch(node);

  /// Nhánh phụ (Luôn chạy, Leo thang): chạy song song / mỗi lần có sự kiện rồi tự kết thúc, không gặp lại nhánh chính.
  static bool sidePort(String key) => const {'always', 'escalate'}.contains(key);

  /// Nhánh chính mặc định kết thúc việc (không đi tiếp): Từ chối, Quá hạn của bước Duyệt. Hai nhánh này để trống
  /// (không nối bước nào) thì không ghi `*_to`: bộ chạy làm như bước Duyệt kiểu cũ (từ chối thì đi tới "khi bị từ
  /// chối" của quy trình hoặc kết thúc luồng "bị từ chối"; quá hạn thì chỉ nhắc người duyệt).
  static bool portEndsByDefault(String type, String key) =>
      (type == 'approval_request' && (key == 'reject' || key == 'timeout')) || (type == 'process_wait' && key == 'timeout');

  static bool _filled(Object? v) => v != null && '$v'.trim().isNotEmpty && v != false;

  /// Khoá các nhánh ra của [node] theo thứ tự vẽ: `always`, `b:<id nút>`, `o:<id lựa chọn>`, `approve`, `reject`,
  /// `escalate`, `timeout`. (Trả lại về bước nhập liệu không phải nhánh: quy trình tự quay về bước được chọn.)
  static List<String> portKeys(Map node) {
    // Nhánh Lỗi: "ok" đi theo cạnh đi ra (trong sơ đồ tạm ghi ở `ok_to`), "error" ghi vào `on_error.to`.
    if (node['type'] == 'process_wait' && okBranch(node)) return ['ok', if (_filled(node['timeout'])) 'timeout', if (errorBranch(node)) 'error'];
    if (errorBranch(node)) return const ['ok', 'error'];
    switch (node['type']) {
      case 'wait_button':
        return [
          'always',
          for (final b in (node['buttons'] as List? ?? const []))
            if (b is Map && b['url'] == null && b['id'] != null) 'b:${b['id']}',
          if (_filled(node['timeout'])) 'timeout',
        ];
      case 'wait_choice':
        return [
          'always',
          for (final o in (node['options'] as List? ?? const [])) if (o is Map && o['id'] != null) 'o:${o['id']}',
          if (_filled(node['timeout'])) 'timeout',
        ];
      case 'approval_request':
        return [
          'always',
          'approve',
          'reject',
          if ((node['escalate'] as List? ?? const []).isNotEmpty) 'escalate',
          if (_filled(node['due'])) 'timeout',
        ];
    }
    return const [];
  }

  /// Bước đích của nhánh [key] trong JSON của node (null nếu chưa nối).
  static String? portTarget(Map node, String key) {
    Object? v;
    if (key.startsWith('b:') || key.startsWith('o:')) {
      final list = node[key.startsWith('b:') ? 'buttons' : 'options'] as List? ?? const [];
      v = [for (final x in list) if (x is Map && '${x['id']}' == key.substring(2)) x].firstOrNull?['to'];
    } else if (key == 'error') {
      v = node['on_error'] is Map ? (node['on_error'] as Map)['to'] : null;
    } else {
      v = node['${key}_to'];
    }
    return v == null || '$v'.isEmpty ? null : '$v';
  }

  /// Bản sao của node với các trường `to` của nhánh xoá hết (để ghi lại theo sơ đồ).
  static Map<String, dynamic> withoutPortTargets(Map<String, dynamic> node) {
    final out = Map<String, dynamic>.of(node);
    for (final k in const ['always', 'timeout', 'approve', 'reject', 'escalate', 'ok']) {
      out.remove('${k}_to');
    }
    if (errorBranch(out)) out['on_error'] = <String, dynamic>{'to': ''};
    for (final l in const ['buttons', 'options']) {
      if (out[l] is List) {
        out[l] = [for (final x in out[l] as List) x is Map ? (Map<String, dynamic>.of(x.cast<String, dynamic>())..remove('to')) : x];
      }
    }
    return out;
  }

  static void setPortTarget(Map<String, dynamic> node, String key, String to) {
    if (key.startsWith('b:') || key.startsWith('o:')) {
      for (final x in node[key.startsWith('b:') ? 'buttons' : 'options'] as List? ?? const []) {
        if (x is Map && '${x['id']}' == key.substring(2)) x['to'] = to;
      }
    } else if (key == 'error') {
      node['on_error'] = <String, dynamic>{'to': to};
    } else {
      node['${key}_to'] = to;
    }
  }
}

/// Một nhánh ra của bước nhiều cổng. [end]: hết nhánh thì kết thúc (không gặp lại bước sau); nhánh phụ
/// (Luôn chạy, Leo thang) luôn tự kết thúc.
class FPort {
  final String key;
  List<FItem> steps;
  bool end;
  /// Nhánh Từ chối / Quá hạn của bước Duyệt chưa nối (trống thì không ghi `*_to`, xem [FStep.portEndsByDefault]).
  /// Có bước trong nhánh thì như nhánh thường.
  bool unwired;
  FPort(this.key, this.steps, {this.end = false, this.unwired = false});
  /// Trống và chưa nối: không ghi đích.
  bool get open => unwired && steps.isEmpty;
  bool get side => FStep.sidePort(key);
  bool get ends => side || end;
}

/// Nhánh của điều kiện: [cond] = biểu thức; null = nhánh "còn lại" (else).
class FBranch {
  String? cond;
  List<FItem> steps;
  FBranch(this.cond, this.steps);
}

/// Rẽ nhánh theo điều kiện: các nhánh có điều kiện theo thứ tự, nhánh cuối là "còn lại".
class FCondition extends FItem {
  String name;
  List<FBranch> branches;
  FCondition(super.id, this.name, this.branches);
}

/// Chạy song song nhiều nhánh, chờ đủ rồi đi tiếp.
class FParallel extends FItem {
  String name;
  String joinId;
  List<List<FItem>> branches;
  FParallel(super.id, this.name, this.joinId, this.branches);
}

/// Lặp bảng (`table_loop`, khung chứa các bước con): [body] chạy lần lượt cho từng dòng của bảng [items] (biểu thức,
/// vd "form.san_pham", "steps.nhom.output.groups"). [alias]: tên dòng (`<as>.<cột>`), [key]: biểu thức nhận diện
/// dòng ghi vào lỗi từng lượt, [stopOnError]: lượt lỗi thì dừng hẳn. [legacy]: khối lặp kiểu cũ (`foreach` /
/// `foreach_end`, id điểm kết thúc [endId]) không đổi được vì thân có bước khung không cho (chờ người...): giữ nguyên.
class FLoop extends FItem {
  String name;
  String items;
  String endId;
  List<FItem> body;
  String alias;
  String key;
  bool stopOnError;
  bool legacy;
  FLoop(super.id, this.name, this.items, this.endId, this.body, {this.alias = '', this.key = '', this.stopOnError = false, this.legacy = false});
}

class FlowDoc {
  Map<String, dynamic> meta; // id, name, icon, form, who_can_start, on_reject, on_return...
  List<FItem> steps;
  /// Nhánh "Khi luồng bị huỷ" (`on_cancel: {"to"}` của quy trình): chỉ bước tự động, chạy xong thì luồng kết thúc
  /// với trạng thái đã huỷ.
  List<FItem> cancelSteps = [];
  /// Hiện mục "Khi luồng bị huỷ" trên sơ đồ (có bước, hoặc người soạn vừa bật).
  bool cancelOn = false;
  /// Id các bước Duyệt kiểu cũ (`approval`) vừa được đổi sang dạng mới khi mở (lưu lại để áp dụng).
  List<String> upgraded = [];
  /// Loại bước mới đã dùng khi đổi (approval_request, send, wait_button), theo thứ tự gặp: cho ghi chú nâng cấp.
  List<String> upgradedKinds = [];
  FlowDoc(this.meta, this.steps);

  static final _rnd = Random();
  static String newId(String prefix) => '${prefix}_${_rnd.nextInt(1 << 30).toRadixString(36)}';

  /// Flow mới: một bước duyệt.
  factory FlowDoc.blank({String id = '', String name = ''}) => FlowDoc({
        'id': id.isEmpty ? newId('flow') : id,
        'name': name,
        'icon': '📋',
        'form': <Map<String, dynamic>>[],
      }, [
        FStep({'id': newId('duyet'), 'type': 'approval_request', 'name': 'Duyệt', 'title': '', 'approver': '\$requester', 'due': '24h', 'return_steps': ['start']}),
      ]);

  /// Đổi bước Duyệt kiểu cũ (`approval`) sang bước Duyệt dạng mới (`approval_request`), như
  /// `flows_engine::upgrade` của máy chủ: giữ id, số, tên, ủy quyền, người duyệt, chế độ, hạn, nhắc, trường sửa /
  /// nhập; `title` = tên bước; leo thang một cấp → một cấp "thêm người duyệt"; cho trả lại (mặc định) → trả về
  /// nốt Bắt đầu [start]; [approveTo] (đích cạnh đi ra) → nhánh Phê duyệt; nhánh Từ chối, Quá hạn để trống.
  static Map<String, dynamic> approvalToRequest(Map<String, dynamic> n, {String approveTo = '', String start = 'start'}) {
    final name = '${n['name'] ?? ''}'.trim();
    final esc = n['escalate'];
    bool has(String k) => n[k] != null && !(n[k] is List && (n[k] as List).isEmpty);
    return {
      'id': n['id'],
      if (n['no'] != null) 'no': n['no'],
      if (n['name'] != null) 'name': n['name'],
      if (n['delegation'] != null) 'delegation': n['delegation'],
      'type': 'approval_request',
      'title': name.isEmpty ? '${n['id']}' : name,
      'approver': n['approver'],
      if (n['mode'] != null) 'mode': n['mode'],
      for (final k in const ['due', 'remind', 'editable', 'fields'])
        if (has(k)) k: n[k],
      if (esc is Map) 'escalate': [{'after': esc['after'], 'to': esc['to'], 'mode': 'add'}],
      if (n['allow_return'] != false) 'return_steps': [start],
      if (approveTo.isNotEmpty) 'approve_to': approveTo,
    };
  }

  // ------------------------------------------------------------------ JSON -> sơ đồ

  factory FlowDoc.fromJson(Map<String, dynamic> raw) {
    // Bước gửi / chờ bấm nút kiểu cũ đổi sang bước gộp (Gửi, Chờ bấm nút), như máy chủ.
    final legacy = upgradeLegacySteps(raw);
    final def = legacy.def;
    final nodes = {for (final n in (def['nodes'] as List? ?? const [])) if (n is Map) '${n['id']}': n.cast<String, dynamic>()};
    final edges = [for (final e in (def['edges'] as List? ?? const [])) if (e is List && e.length == 2) ('${e[0]}', '${e[1]}')];
    // Bước Duyệt kiểu cũ đổi sang dạng mới; bước Duyệt dạng mới đi tiếp bằng cạnh (không nối nhánh Phê duyệt) thì
    // cạnh thành nhánh Phê duyệt. Sơ đồ chỉ còn một loại bước Duyệt, có đủ các nhánh.
    final upgraded = <String>[];
    final upgradedLoops = <String>[];
    // Bước có nhánh Lỗi: cạnh đi ra là nhánh "Thành công" (ghi tạm ở `ok_to`, lưu lại thành cạnh).
    for (final id in [...nodes.keys]) {
      final n = nodes[id]!;
      if (!FStep.okBranch(n)) continue;
      final out = [for (final (a, b) in edges) if (a == id) b];
      if (out.length != 1) continue;
      edges.remove((id, out.single));
      nodes[id] = {...n, 'ok_to': out.single};
    }
    for (final id in [...nodes.keys]) {
      final n = nodes[id]!;
      final legacy = n['type'] == 'approval';
      if (!legacy && !(n['type'] == 'approval_request' && '${n['approve_to'] ?? ''}'.isEmpty)) continue;
      final out = [for (final (a, b) in edges) if (a == id) b];
      final to = out.length == 1 ? out.single : '';
      if (to.isNotEmpty) edges.remove((id, to));
      if (legacy) {
        // Sơ đồ luôn ghi nốt Bắt đầu với id "start" (trả lại về đó).
        nodes[id] = approvalToRequest(n, approveTo: to);
        upgraded.add(id);
      } else if (to.isNotEmpty) {
        nodes[id] = {...n, 'approve_to': to};
      }
    }
    // Nhánh Lỗi / Quá hạn của bước (để tìm bước con đầu tiên của khung lặp).
    List<String> errorTargets(String id) {
      final n = nodes[id];
      if (n == null || !FStep.hasPorts(n)) return const [];
      return [for (final k in FStep.portKeys(n)) if (FStep.portTarget(n, k) != null) FStep.portTarget(n, k)!];
    }

    List<String> outs(String id) {
      final n = nodes[id];
      if (n != null && n['type'] == 'condition') {
        return [for (final r in (n['rules'] as List? ?? const [])) if (r is Map) '${r['to']}', '${n['else']}'];
      }
      // Bước nhiều cổng: chỉ các nhánh chính (nhánh phụ tự kết thúc, không tính khi tìm điểm gặp lại).
      if (n != null && FStep.hasPorts(n)) {
        return [
          for (final k in FStep.portKeys(n))
            if (!FStep.sidePort(k) && FStep.portTarget(n, k) != null) FStep.portTarget(n, k)!,
        ];
      }
      return [for (final (a, b) in edges) if (a == id) b];
    }

    // Thứ tự gặp các node khi đi từ [from] (theo chiều rộng).
    List<String> order(String from) {
      final seen = <String>{};
      final q = [from];
      final out = <String>[];
      while (q.isNotEmpty) {
        final x = q.removeAt(0);
        if (!seen.add(x)) continue;
        out.add(x);
        q.addAll(outs(x));
      }
      return out;
    }

    final endIds = {for (final n in nodes.values) if (n['type'] == 'end') '${n['id']}'};

    // Điểm gặp lại của các nhánh: node đầu tiên (theo thứ tự của nhánh đầu) mà mọi nhánh đều đi tới. Ưu tiên
    // bước thật hơn node kết thúc (một nhánh phụ có thể tới "end" sớm hơn điểm gặp lại thật).
    String? mergeOf(List<String> starts) {
      final sets = [for (final s in starts) order(s).toSet()];
      final common = [for (final x in order(starts.first)) if (sets.every((s) => s.contains(x))) x];
      return common.where((x) => !endIds.contains(x)).firstOrNull ?? common.firstOrNull;
    }

    late List<FItem> Function(String? id, String? stop, Set<String> guard) seq;

    // Bước nhiều cổng: nhánh chính nào cùng tới một bước thật thì gặp lại ở đó (đi tiếp sau bước); nhánh chính
    // chỉ đi tới kết thúc là nhánh "kết thúc việc"; nhánh phụ đọc tới hết. Trả về bước sau điểm gặp lại.
    String? portsFrom(FStep step, Map n, Set<String> guard) {
      final main = [for (final p in step.ports) if (!p.side) p];
      String? tgt(FPort p) => FStep.portTarget(n, p.key);
      var cont = [for (final p in main) if (tgt(p) != null && !endIds.contains(tgt(p))) p];
      // Nhánh Lỗi không bao giờ là đường chính: chỉ gặp lại nhánh Thành công, không thì là nhánh riêng.
      if (FStep.okBranch(n) && !cont.any((p) => p.key == 'ok')) cont = [];
      if (cont.length > 1) {
        final sets = {for (final p in cont) p.key: order(tgt(p)!).toSet().difference(endIds)};
        final shared = [for (final p in cont) if (cont.any((q) => q != p && sets[q.key]!.intersection(sets[p.key]!).isNotEmpty)) p];
        cont = shared.isEmpty ? [cont.first] : shared;
      }
      final merge = cont.isEmpty ? null : (cont.length == 1 ? tgt(cont.first) : mergeOf([for (final p in cont) tgt(p)!]));
      for (final p in main) {
        final t = tgt(p);
        p.unwired = false;
        if (t == null) {
          p.steps = [];
          // Từ chối / Quá hạn của bước Duyệt chưa nối: để trống (bộ chạy làm như bước Duyệt kiểu cũ).
          p.end = p.unwired = FStep.portEndsByDefault(step.type, p.key);
        } else if (cont.contains(p)) {
          p.steps = seq(t, merge, guard);
          p.end = false;
        } else {
          p.steps = seq(t, null, guard);
          p.end = true;
        }
      }
      for (final p in step.ports.where((p) => p.side)) {
        final t = tgt(p);
        p.steps = t == null ? [] : seq(t, merge, guard);
      }
      return merge;
    }

    seq = (String? id, String? stop, Set<String> guard) {
      final out = <FItem>[];
      while (id != null && id != stop && !endIds.contains(id) && guard.add(id)) {
        final n = nodes[id];
        if (n == null) break;
        switch (n['type']) {
          case 'start':
            final o = outs(id);
            id = o.isEmpty ? null : o.first;
          case 'condition':
            final starts = outs(id);
            final merge = mergeOf(starts);
            final rules = [for (final r in (n['rules'] as List? ?? const [])) if (r is Map) r];
            out.add(FCondition(id, '${n['name'] ?? ''}', [
              for (final r in rules) FBranch('${r['if']}', seq('${r['to']}', merge, guard)),
              FBranch(null, seq('${n['else']}', merge, guard)),
            ])..no = (n['no'] as num?)?.toInt());
            id = merge;
          case 'parallel':
            final starts = outs(id);
            final join = mergeOf(starts);
            out.add(FParallel(id, '${n['name'] ?? ''}', join ?? newId('gop'), [for (final s in starts) seq(s, join, guard)])..no = (n['no'] as num?)?.toInt());
            final after = join == null ? <String>[] : outs(join);
            if (join != null) guard.add(join);
            id = after.isEmpty ? null : after.first;
          case 'foreach':
            final end = '${n['end'] ?? ''}';
            final o = outs(id);
            final body = o.isEmpty ? <FItem>[] : seq(o.first, end, guard);
            // Khối lặp kiểu cũ đổi sang khung Lặp bảng (dừng khi lỗi, như cũ) nếu thân không có bước khung không cho.
            final keep = body.any(loopBlockedDeep);
            out.add(FLoop(id, '${n['name'] ?? ''}', '${n['items'] ?? ''}', end.isEmpty ? newId('het_lap') : end, body, stopOnError: !keep, legacy: keep)
              ..no = (n['no'] as num?)?.toInt());
            if (!keep) upgradedLoops.add(id);
            guard.add(end);
            final after = outs(end);
            id = after.isEmpty ? null : after.first;
          case 'table_loop':
            final body = {for (final b in (n['body'] as List? ?? const [])) '$b'};
            var entry = '${n['entry'] ?? ''}';
            if (entry.isEmpty) {
              entry = body.where((b) => !body.any((x) => outs(x).contains(b) || errorTargets(x).contains(b))).firstOrNull ?? '';
            }
            out.add(FLoop(id, '${n['name'] ?? ''}', '${n['table'] ?? ''}', '', entry.isEmpty ? [] : seq(entry, null, guard),
                alias: '${n['as'] ?? ''}', key: '${n['key'] ?? ''}', stopOnError: n['stop_on_error'] == true)
              ..no = (n['no'] as num?)?.toInt());
            final after = outs(id);
            id = after.isEmpty ? null : after.first;
          case 'foreach_end':
            final o = outs(id);
            id = o.isEmpty ? null : o.first;
          case 'join':
            final o = outs(id);
            id = o.isEmpty ? null : o.first;
          case _ when FStep.hasPorts(n):
            // Trường `to` của các nhánh chỉ có trong JSON; sơ đồ giữ nhánh ở [FStep.ports].
            final step = FStep(FStep.withoutPortTargets(n));
            out.add(step);
            id = portsFrom(step, n, guard);
          default:
            out.add(FStep(Map.of(n)));
            final o = outs(id);
            id = o.isEmpty ? null : o.first;
        }
      }
      return out;
    };

    final start = nodes.values.firstWhere((n) => n['type'] == 'start', orElse: () => const {})['id'];
    final meta = Map<String, dynamic>.of(def)..remove('nodes')..remove('edges')..remove('on_cancel');
    final kinds = [if (upgraded.isNotEmpty) 'approval_request', ...legacy.kinds];
    final guard = <String>{};
    final main = start == null ? <FItem>[] : seq('$start', null, guard);
    final oc = def['on_cancel'];
    final cancelTo = oc is Map ? '${oc['to'] ?? ''}' : '';
    final cancel = cancelTo.isEmpty ? <FItem>[] : seq(cancelTo, null, guard);
    return FlowDoc(meta, main)
      ..cancelSteps = cancel
      ..cancelOn = cancel.isNotEmpty
      ..upgraded = [...upgraded, ...legacy.ids, ...upgradedLoops]
      ..upgradedKinds = [...kinds, if (upgradedLoops.isNotEmpty) 'table_loop'];
  }

  /// Mục không dùng được trong khung Lặp bảng (như lint `table_loop` của máy chủ): chờ người, bắt đầu quy trình khác
  /// có chờ / xác nhận, song song, khối lặp kiểu cũ, giao việc tay khi lỗi.
  static bool loopBlocked(FItem it) => switch (it) {
        FParallel _ => true,
        FLoop l => l.legacy,
        FStep s => const {
              'approval', 'approval_request', 'form_task', 'claim', 'wait_button', 'wait_choice', 'card_wait', //
              'delegate_request', 'delegate_approve',
            }.contains(s.type) ||
            (s.type == 'start_flow' && (s.node['wait'] == true || s.node['confirm'] != null)) ||
            (s.type == 'buttons' && (s.node['buttons'] as List? ?? const []).any((b) => b is Map && '${b['url'] ?? ''}'.isEmpty)) ||
            (s.node['on_error'] is Map && (s.node['on_error'] as Map).containsKey('assign')),
        _ => false,
      };

  /// [it] hoặc một mục bên trong nó (nhánh, khung lồng) không dùng được trong khung Lặp bảng.
  static bool loopBlockedDeep(FItem it) {
    if (loopBlocked(it)) return true;
    final subs = switch (it) {
      FCondition c => [for (final b in c.branches) b.steps],
      FParallel p => p.branches,
      FLoop l => [l.body],
      FStep s => [for (final p in s.ports) p.steps],
    };
    return subs.any((l) => l.any(loopBlockedDeep));
  }

  /// Các mục trong khung Lặp bảng [l] mà khung không cho (hiện cảnh báo trên sơ đồ).
  static List<FItem> loopBlockedItems(FLoop l) {
    if (l.legacy) return const [];
    final out = <FItem>[];
    void walk(List<FItem> items) {
      for (final x in items) {
        if (loopBlocked(x)) out.add(x);
        switch (x) {
          case FCondition c:
            for (final b in c.branches) {
              walk(b.steps);
            }
          case FStep st:
            for (final p in st.ports) {
              walk(p.steps);
            }
          default:
        }
      }
    }

    walk(l.body);
    return out;
  }

  /// Mục không dùng được trong nhánh "Khi luồng bị huỷ" (chỉ bước tự động): duyệt, điền thông tin, tiếp nhận, mọi bước
  /// chờ, chờ tiến trình, khối lặp, bắt đầu quy trình khác có chờ / xác nhận (như lint `on_cancel` của máy chủ).
  static bool cancelBlocked(FItem it) => switch (it) {
        FLoop _ => true,
        FStep s => const {
              'approval', 'approval_request', 'form_task', 'claim', 'wait', 'wait_event', 'wait_button', 'wait_choice', 'card_wait', //
              'process_wait', 'delegate_request', 'delegate_approve',
            }.contains(s.type) ||
            (s.type == 'start_flow' && (s.node['wait'] == true || s.node['confirm'] != null)) ||
            (s.type == 'buttons' && (s.node['buttons'] as List? ?? const []).any((b) => b is Map && '${b['url'] ?? ''}'.isEmpty)),
        _ => false,
      };

  /// Các mục của nhánh "Khi luồng bị huỷ" không được dùng ở đó.
  List<FItem> get cancelBlockedItems {
    final out = <FItem>[];
    void walk(List<FItem> l) {
      for (final x in l) {
        if (cancelBlocked(x)) out.add(x);
        switch (x) {
          case FCondition c:
            for (final b in c.branches) {
              walk(b.steps);
            }
          case FParallel p:
            for (final b in p.branches) {
              walk(b);
            }
          case FLoop lp:
            walk(lp.body);
          case FStep st:
            for (final p in st.ports) {
              walk(p.steps);
            }
        }
      }
    }

    walk(cancelSteps);
    return out;
  }

  /// Mọi bước (kể cả trong nhánh, khối lặp), theo thứ tự trên sơ đồ.
  List<FItem> get allItems {
    final out = <FItem>[];
    void walk(List<FItem> l) {
      for (final x in l) {
        out.add(x);
        switch (x) {
          case FCondition c:
            for (final b in c.branches) {
              walk(b.steps);
            }
          case FParallel p:
            for (final b in p.branches) {
              walk(b);
            }
          case FLoop lp:
            walk(lp.body);
          case FStep s:
            for (final p in s.ports) {
              walk(p.steps);
            }
        }
      }
    }

    walk(steps);
    walk(cancelSteps);
    return out;
  }

  /// Đánh số bước nào chưa có số (nốt Bắt đầu trước, rồi các bước theo thứ tự). Số đã có giữ nguyên.
  void numberNodes() {
    final starts = [for (final s in (meta['starts'] as List? ?? const [])) if (s is Map) s];
    final items = allItems;
    var next = [
      for (final s in starts) (s['no'] as num?)?.toInt() ?? 0,
      for (final it in items) it.no ?? 0,
    ].fold<int>(0, (a, b) => b > a ? b : a);
    final used = <int>{};
    for (final s in starts) {
      final n = (s['no'] as num?)?.toInt();
      if (n == null || !used.add(n)) s['no'] = ++next;
    }
    for (final it in items) {
      if (it.no == null || !used.add(it.no!)) {
        it.no = ++next;
        used.add(it.no!);
      }
      if (it is FStep) it.node['no'] = it.no;
    }
  }

  /// Bước có số [no] (null nếu không có).
  FItem? byNo(int no) => allItems.where((x) => x.no == no).firstOrNull;

  /// Id các node đứng trước [id] trên mọi đường đi tới nó (kể cả "start"), theo JSON đã dựng: cạnh, nhánh của
  /// Rẽ nhánh và nhánh của bước nhiều cổng.
  Set<String> predecessorsOf(String id) {
    final def = toJson();
    final into = <String, Set<String>>{};
    void link(String a, Object? b) {
      if (b != null && '$b'.isNotEmpty) (into['$b'] ??= {}).add(a);
    }

    for (final e in (def['edges'] as List)) {
      link('${e[0]}', e[1]);
    }
    for (final n in (def['nodes'] as List).cast<Map<String, dynamic>>()) {
      final from = '${n['id']}';
      if (n['type'] == 'condition') {
        for (final r in (n['rules'] as List? ?? const [])) {
          if (r is Map) link(from, r['to']);
        }
        link(from, n['else']);
      }
      for (final k in FStep.portKeys(n)) {
        link(from, FStep.portTarget(n, k));
      }
      // Khung Lặp bảng đi vào bước con đầu tiên.
      if (n['type'] == 'table_loop') link(from, n['entry']);
    }
    final seen = <String>{};
    final q = [...?into[id]];
    while (q.isNotEmpty) {
      final x = q.removeLast();
      if (seen.add(x)) q.addAll(into[x] ?? const {});
    }
    return seen;
  }

  // ------------------------------------------------------------------ sơ đồ -> JSON

  Map<String, dynamic> toJson() {
    final nodes = <Map<String, dynamic>>[];
    final edges = <List<String>>[];

    late String Function(FItem it, String next) emitItem;

    // Nhánh kết thúc việc: Từ chối thì kết thúc với trạng thái "bị từ chối".
    var rejectedEnd = false;
    // Đang ghi bên trong khung Lặp bảng: nhánh "kết thúc việc" là kết thúc lượt (đích rỗng), không tới node end.
    var loopDepth = 0;
    String endNode(String key) {
      if (loopDepth > 0) return '';
      if (key != 'reject') return 'end';
      rejectedEnd = true;
      return 'end_rejected';
    }

    // Trả về id node vào đầu của chuỗi (hoặc [next] nếu chuỗi trống).
    String emit(List<FItem> items, String next) {
      var n = next;
      for (final it in items.reversed) {
        n = emitItem(it, n);
      }
      return n;
    }

    emitItem = (FItem it, String next) {
      switch (it) {
        case FStep s when s.ports.isNotEmpty:
          // Bước nhiều cổng: mỗi nhánh ghi vào trường `to` của nó, không có cạnh đi ra (như Rẽ nhánh). Nhánh chính
          // trống thì đi tiếp bước sau; nhánh phụ trống thì không có (bỏ trường).
          final node = FStep.withoutPortTargets(s.node)..['id'] = s.id;
          if (s.no != null) node['no'] = s.no;
          // Bước Duyệt chưa đặt tên yêu cầu: dùng tên bước.
          if (s.type == 'approval_request' && '${node['title'] ?? ''}'.trim().isEmpty) node['title'] = s.name.trim().isEmpty ? 'Duyệt' : s.name.trim();
          for (final p in s.ports) {
            if (p.side && p.steps.isEmpty) continue;
            if (p.open) continue;
            FStep.setPortTarget(node, p.key, emit(p.steps, p.ends ? endNode(p.key) : next));
          }
          // Nhánh Thành công của bước có nhánh Lỗi: là cạnh đi ra.
          final ok = node.remove('ok_to');
          if (ok != null && '$ok'.isNotEmpty) edges.add([s.id, '$ok']);
          nodes.add(node);
          return s.id;
        case FStep s:
          final node = Map<String, dynamic>.of(s.node)..['id'] = s.id;
          if (s.no != null) node['no'] = s.no;
          nodes.add(node);
          // Bước cuối trong khung Lặp bảng: không có cạnh đi ra (kết thúc lượt).
          if (next.isNotEmpty) edges.add([s.id, next]);
          return s.id;
        case FCondition c:
          final ruled = c.branches.where((b) => b.cond != null).toList();
          final other = c.branches.firstWhere((b) => b.cond == null, orElse: () => FBranch(null, []));
          nodes.add({
            'id': c.id,
            'no': ?c.no,
            'type': 'condition',
            if (c.name.isNotEmpty) 'name': c.name,
            'rules': [for (final b in ruled) {'if': b.cond, 'to': emit(b.steps, next)}],
            'else': emit(other.steps, next),
          });
          return c.id;
        case FLoop l when !l.legacy:
          final mark = nodes.length;
          loopDepth++;
          final entry = emit(l.body, '');
          loopDepth--;
          final inside = nodes.sublist(mark);
          final inner = {
            for (final n in inside)
              if (n['type'] == 'table_loop') ...[for (final b in (n['body'] as List? ?? const [])) '$b'],
          };
          nodes.add({
            'id': l.id,
            'no': ?l.no,
            'type': 'table_loop',
            if (l.name.isNotEmpty) 'name': l.name,
            'table': l.items,
            if (l.alias.trim().isNotEmpty) 'as': l.alias.trim(),
            if (l.key.trim().isNotEmpty) 'key': l.key.trim(),
            if (l.stopOnError) 'stop_on_error': true,
            'body': [for (final n in inside) if (!inner.contains('${n['id']}')) '${n['id']}'],
            if (entry.isNotEmpty) 'entry': entry,
          });
          if (next.isNotEmpty) edges.add([l.id, next]);
          return l.id;
        case FLoop l:
          nodes.add({'id': l.endId, 'type': 'foreach_end'});
          if (next.isNotEmpty) edges.add([l.endId, next]);
          nodes.add({'id': l.id, 'no': ?l.no, 'type': 'foreach', if (l.name.isNotEmpty) 'name': l.name, 'items': l.items, 'end': l.endId});
          edges.add([l.id, emit(l.body, l.endId)]);
          return l.id;
        case FParallel p:
          nodes.add({'id': p.joinId, 'type': 'join'});
          if (next.isNotEmpty) edges.add([p.joinId, next]);
          nodes.add({'id': p.id, 'no': ?p.no, 'type': 'parallel', if (p.name.isNotEmpty) 'name': p.name});
          for (final b in p.branches) {
            edges.add([p.id, emit(b, p.joinId)]);
          }
          return p.id;
      }
    };

    nodes.add({'id': 'end', 'type': 'end'});
    final first = emit(steps, 'end');
    // Nhánh khi luồng bị huỷ: chạy các bước rồi tới kết thúc (luồng vẫn là "đã huỷ").
    final cancelFirst = cancelSteps.isEmpty ? null : emit(cancelSteps, 'end');
    if (rejectedEnd) nodes.add({'id': 'end_rejected', 'type': 'end', 'status': 'rejected'});
    nodes.insert(0, {'id': 'start', 'type': 'start'});
    edges.insert(0, ['start', first]);
    return {...meta, 'on_cancel': ?(cancelFirst == null ? null : {'to': cancelFirst}), 'nodes': nodes, 'edges': edges};
  }

  // ------------------------------------------------------------------ sửa

  /// Tìm chuỗi chứa mục [id] (để xoá / chuyển chỗ).
  List<FItem>? listOf(String id, [List<FItem>? within]) {
    if (within == null) return listOf(id, steps) ?? listOf(id, cancelSteps);
    final l = within;
    if (l.any((x) => x.id == id)) return l;
    for (final x in l) {
      final subs = switch (x) {
        FCondition c => [for (final b in c.branches) b.steps],
        FParallel p => p.branches,
        FLoop l => [l.body],
        FStep s => [for (final p in s.ports) p.steps],
      };
      for (final s in subs) {
        final r = listOf(id, s);
        if (r != null) return r;
      }
    }
    return null;
  }

  FItem? find(String id) {
    final l = listOf(id);
    return l?.firstWhere((x) => x.id == id);
  }

  void remove(String id) => listOf(id)?.removeWhere((x) => x.id == id);

  /// Đặt cấu hình mới [node] cho bước [s] và dựng lại nhánh. Bỏ nhánh Lỗi (đổi sang cách khác) thì các bước của
  /// nhánh Thành công về lại ngay sau bước, không mất.
  void setNode(FStep s, Map<String, dynamic> node) {
    final ok = s.ports.where((p) => p.key == 'ok').firstOrNull;
    s.node = node;
    s.syncPorts();
    if (ok != null && ok.steps.isNotEmpty && !s.ports.any((p) => p.key == 'ok')) {
      final l = listOf(s.id);
      if (l != null) l.insertAll(l.indexOf(s) + 1, ok.steps);
    }
  }

  /// Mọi bước thường (kể cả trong nhánh / khối lặp), theo thứ tự trên sơ đồ.
  List<FStep> get allSteps {
    final out = <FStep>[];
    void walk(List<FItem> l) {
      for (final x in l) {
        switch (x) {
          case FStep s:
            out.add(s);
            for (final p in s.ports) {
              walk(p.steps);
            }
          case FCondition c:
            for (final b in c.branches) {
              walk(b.steps);
            }
          case FParallel p:
            for (final b in p.branches) {
              walk(b);
            }
          case FLoop lp:
            walk(lp.body);
        }
      }
    }

    walk(steps);
    walk(cancelSteps);
    return out;
  }

  /// Chuyển mục [id] tới vị trí [index] của chuỗi [target] (cùng chuỗi hay chuỗi khác).
  void move(String id, List<FItem> target, int index) {
    final from = listOf(id);
    if (from == null) return;
    final item = from.firstWhere((x) => x.id == id);
    // Không cho thả một khối vào trong chính nó.
    if (item is FCondition && item.branches.any((b) => identical(b.steps, target) || _contains(b.steps, target))) return;
    if (item is FParallel && item.branches.any((b) => identical(b, target) || _contains(b, target))) return;
    if (item is FLoop && (identical(item.body, target) || _contains(item.body, target))) return;
    if (item is FStep && item.ports.any((p) => identical(p.steps, target) || _contains(p.steps, target))) return;
    final old = from.indexOf(item);
    from.removeAt(old);
    var i = index;
    if (identical(from, target) && old < index) i--;
    target.insert(i.clamp(0, target.length), item);
  }

  bool _contains(List<FItem> l, List<FItem> target) {
    for (final x in l) {
      final subs = switch (x) {
        FCondition c => [for (final b in c.branches) b.steps],
        FParallel p => p.branches,
        FLoop l => [l.body],
        FStep s => [for (final p in s.ports) p.steps],
      };
      for (final s in subs) {
        if (identical(s, target) || _contains(s, target)) return true;
      }
    }
    return false;
  }

  /// Mục mới theo loại.
  static FItem make(String type) => switch (type) {
        'condition' => FCondition(newId('dieu_kien'), 'Điều kiện', [FBranch('form.so_tien > 20000000', []), FBranch(null, [])]),
        'parallel' => FParallel(newId('song_song'), 'Song song', newId('gop'), [[], []]),
        'foreach' || 'table_loop' => FLoop(newId('lap'), 'Lặp bảng', '', '', []),
        'start_flow' => FStep({'id': newId('noi'), 'type': 'start_flow', 'name': 'Bắt đầu quy trình khác', 'flow_id': '', 'mapping': <String, dynamic>{}, 'confirm': r'$requester'}),
        'form_task' => FStep({'id': newId('dien'), 'type': 'form_task', 'name': 'Điền thông tin', 'assignee': '\$requester', 'fields': <Map<String, dynamic>>[]}),
        'ai' => FStep({'id': newId('ai'), 'type': 'ai', 'name': 'Bước AI', 'runner': {'kind': 'bot', 'bot': ''}, 'prompt': '', 'output_schema': <String, String>{}, 'on_error': 'continue'}),
        'notify' => FStep({'id': newId('bao'), 'type': 'notify', 'name': 'Thông báo', 'to': ['\$requester'], 'text': ''}),
        // Bước Gửi (thay Thông báo, Gửi thẻ, Gửi tiến trình): mặc định gửi tin nhắn cho người tạo.
        'send' => FStep({'id': newId('gui'), 'type': 'send', 'name': 'Gửi', 'to': ['\$requester'], 'text': ''}),
        'set' => FStep({
            'id': newId('dat'),
            'type': 'set',
            'name': 'Đặt biến',
            'assign': [
              {'to': 'vars.bien_1', 'expr': ''},
            ],
          }),
        'wait' => FStep({'id': newId('cho'), 'type': 'wait', 'name': 'Chờ', 'for': '1d'}),
        'note_add' => FStep({
            'id': newId('ghi_chu'),
            'type': 'auto',
            'action': 'note_add',
            'name': 'Thêm ghi chú',
            'params': {'message': <String, dynamic>{}, 'text': '', 'color': 'yellow'},
          }),
        'note_edit' => FStep({'id': newId('sua_ghi_chu'), 'type': 'auto', 'action': 'note_edit', 'name': 'Sửa ghi chú', 'params': {'note_step': '', 'text': '', 'color': ''}}),
        'buttons' => FStep({
            'id': newId('nut'),
            'type': 'buttons',
            'name': 'Nút trên tin',
            'message': <String, dynamic>{},
            'buttons': [
              {'label': 'Đã nhận'},
            ],
          }),
        'delegate_set' => FStep({
            'id': newId('uy_quyen'),
            'type': 'auto',
            'action': 'delegate_set',
            'name': 'Đặt ủy quyền',
            'params': {
              'from': '',
              'until': '',
              'pending': true,
              'rules': [
                {'flows': <String>[], 'delegate': ''},
              ],
            },
          }),
        'user_status' => FStep({
            'id': newId('trang_thai'),
            'type': 'auto',
            'action': 'user_status',
            'name': 'Đổi trạng thái',
            'params': {'emoji': 'palm_tree', 'text': 'Nghỉ phép', 'until': '', 'dnd': false},
          }),
        'delegate_request' => FStep({'id': newId('yc_uy_quyen'), 'type': 'delegate_request', 'name': 'Yêu cầu ủy quyền'}),
        'delegate_approve' => FStep({'id': newId('duyet_uy_quyen'), 'type': 'delegate_approve', 'name': 'Duyệt ủy quyền'}),
        'wait_event' => FStep({'id': newId('cho_su_kien'), 'type': 'wait_event', 'name': 'Chờ sự kiện', 'server': '', 'tool': '', 'cond': '', 'seconds': 300, 'timeout': '3d'}),
        'calc' => FStep({'id': newId('tinh'), 'type': 'calc', 'name': 'Tính toán', 'vars': <Map<String, dynamic>>[]}),
        'progress' => FStep({'id': newId('tien_do'), 'type': 'progress', 'name': 'Báo tiến độ', 'percent': '', 'label': ''}),
        // Vị trí người bấm chọn khi mở bước (trường Vị trí đầu tiên); toạ độ công ty để 0 tới khi người soạn đặt.
        'geo_distance' => FStep({'id': newId('khoang_cach'), 'type': 'geo_distance', 'name': 'Tính khoảng cách GPS', 'from': '', 'lat': 0, 'lon': 0, 'radius': 200}),
        'chat_post' => FStep({
            'id': newId('gui_tin'),
            'type': 'auto',
            'action': 'chat_post',
            'name': 'Gửi tin kèm tệp',
            'params': {'to': [r'$requester'], 'text': ''},
          }),
        'delegate_apply' => FStep({'id': newId('ap_dung_uy_quyen'), 'type': 'delegate_apply', 'name': 'Áp dụng ủy quyền'}),
        'delegate_revoke' => FStep({'id': newId('thu_hoi_uy_quyen'), 'type': 'delegate_revoke', 'name': 'Thu hồi ủy quyền'}),
        'claim' => FStep({'id': newId('tiep_nhan'), 'type': 'claim', 'name': 'Tiếp nhận', 'assignee': r'$requester', 'due': '24h'}),
        'mcp' => FStep({
            'id': newId('cong_cu'),
            'type': 'auto',
            'action': 'mcp',
            'name': 'Gọi công cụ',
            'params': {'server': '', 'tool': '', 'args': <String, dynamic>{}},
            'on_error': 'fail',
          }),
        // Thẻ dữ liệu (flygo_card) và tiến trình.
        'card_send' => FStep({
            'id': newId('gui_the'),
            'type': 'card_send',
            'name': 'Gửi thẻ',
            'channels': <String>[],
            'to': <Object>[],
            'card': {'v': 1, 'icon': 'task', 'accent': 'blue', 'title': ''},
          }),
        'card_update' => FStep({'id': newId('sua_the'), 'type': 'card_update', 'name': 'Sửa thẻ', 'card': <String, dynamic>{}, 'patch': <String, dynamic>{}}),
        'card_wait' => FStep({'id': newId('cho_the'), 'type': 'card_wait', 'name': 'Chờ bấm nút trên thẻ', 'card': <String, dynamic>{}, 'timeout': '24h'}),
        'process_create' => FStep({
            'id': newId('tao_tt'),
            'type': 'process_create',
            'name': 'Tạo tiến trình',
            'key': '',
            'title': '',
            'icon': '📋',
            'steps': [
              {'key': 'b1', 'title': 'Tiếp nhận'},
              {'key': 'b2', 'title': 'Xử lý'},
              {'key': 'b3', 'title': 'Hoàn tất'},
            ],
            'stats': <Map<String, dynamic>>[],
            'labels': <String>[],
          }),
        'process_step' => FStep({'id': newId('buoc_tt'), 'type': 'process_step', 'name': 'Chuyển bước tiến trình', 'process': <String, dynamic>{}, 'step': ''}),
        'process_stat' => FStep({'id': newId('so_lieu_tt'), 'type': 'process_stat', 'name': 'Cập nhật thống kê', 'process': <String, dynamic>{}, 'stats': <Map<String, dynamic>>[]}),
        'process_attach' => FStep({'id': newId('dinh_kem_tt'), 'type': 'process_attach', 'name': 'Đính kèm vào tiến trình', 'process': <String, dynamic>{}, 'items': <Map<String, dynamic>>[]}),
        'process_fail' => FStep({'id': newId('loi_tt'), 'type': 'process_fail', 'name': 'Báo lỗi tiến trình', 'process': <String, dynamic>{}, 'reason': ''}),
        'process_finish' => FStep({'id': newId('xong_tt'), 'type': 'process_finish', 'name': 'Hoàn thành tiến trình', 'process': <String, dynamic>{}, 'result': 'done'}),
        'process_send' => FStep({
            'id': newId('gui_tt'),
            'type': 'process_send',
            'name': 'Gửi tiến trình',
            'process': <String, dynamic>{},
            'channels': <String>[],
            'to': <Object>[],
            'sync': true,
          }),
        'process_find' => FStep({'id': newId('tim_tt'), 'type': 'process_find', 'name': 'Tìm tiến trình', 'key': ''}),
        'process_label' => FStep({'id': newId('nhan_tt'), 'type': 'process_label', 'name': 'Gắn nhãn tiến trình', 'process': <String, dynamic>{}, 'add': <String>[], 'remove': <String>[]}),
        'process_props' => FStep({'id': newId('thuoc_tinh_tt'), 'type': 'process_props', 'name': 'Gán thuộc tính tiến trình', 'process': <String, dynamic>{}, 'set': <String, dynamic>{}}),
        'process_remind' => FStep({
            'id': newId('nhac_tt'),
            'type': 'process_remind',
            'name': 'Nhắc theo mốc',
            'process': <String, dynamic>{},
            'at': 'process.props.eta',
            'offset': '-3d',
            'to': <Object>[],
            'message': '',
          }),
        // Tạo tài liệu từ mẫu Word: mặc định ra Word, gắn vào tiến trình chính của luồng.
        'doc_render' => FStep({'id': newId('tai_lieu'), 'type': 'doc_render', 'name': 'Tạo tài liệu', 'template': '', 'output': 'docx', 'file_name': ''}),
        // Chờ tiến trình: mặc định chờ mọi tiến trình con của tiến trình tạo ở bước trước hoàn thành.
        'process_wait' => FStep({
            'id': newId('cho_tt'),
            'type': 'process_wait',
            'name': 'Chờ tiến trình',
            'of': {'children_of': <String, dynamic>{}},
            'until': 'all',
            'state': 'done',
          }),
        // Chờ người dùng: mỗi nút / lựa chọn một nhánh, cộng nhánh "Luôn chạy".
        'wait_button' => FStep({
            'id': newId('cho_nut'),
            'type': 'wait_button',
            'name': 'Chờ bấm nút',
            'prompt': '',
            'buttons': [
              {'id': newId('ok'), 'label': 'Đồng ý', 'style': 'primary'},
              {'id': newId('khong'), 'label': 'Không đồng ý'},
            ],
            'who': r'$requester',
            'stop_always_on_action': true,
          }),
        'wait_choice' => FStep({
            'id': newId('lua_chon'),
            'type': 'wait_choice',
            'name': 'Lựa chọn',
            'prompt': '',
            'options': [
              {'id': newId('a'), 'label': 'Lựa chọn 1'},
              {'id': newId('b'), 'label': 'Lựa chọn 2'},
            ],
            'min': 1,
            'who': r'$requester',
            'stop_always_on_action': true,
          }),
        'wait_close' => FStep({'id': newId('ket_thuc_cho'), 'type': 'wait_close', 'name': 'Kết thúc chờ', 'wait': '', 'reason': ''}),
        // Bước Duyệt (một loại duy nhất; "approval" kiểu cũ cũng tạo bước dạng mới). Cho trả lại về đơn ban đầu như
        // bước Duyệt cũ; Từ chối, Quá hạn để trống = kết thúc "bị từ chối", chỉ nhắc khi quá hạn.
        'approval_request' || 'approval' => FStep({
            'id': newId('duyet'),
            'type': 'approval_request',
            'name': 'Duyệt',
            'title': '',
            'approver': {'manager': r'$requester'},
            'mode': 'any',
            'due': '24h',
            'return_steps': ['start'],
            'stop_always_on_action': true,
          }),
        'table_filter' || 'table_add_field' || 'table_group' || 'table_join' => FStep(newTableNode(type, newId(type.replaceFirst('table_', 'bang_')))),
        'mcp_pages' => FStep(newTableNode(type, newId('doc_trang'))),
        'compose' => FStep({'id': newId('soan'), 'type': 'compose', 'name': 'Soạn nội dung', 'subject': '', 'body': '<p></p>'}),
        _ => FStep({'id': newId('buoc'), 'type': type, 'name': type}),
      };
}
