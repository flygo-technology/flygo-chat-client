/// Đổi các bước gửi / chờ bấm nút kiểu cũ sang bước gộp khi mở quy trình, đúng như `flows_engine::upgrade` của máy
/// chủ (`upgrade_sends`, `upgrade_waits`; bước Duyệt cũ đổi ở [FlowDoc.fromJson]). Hàm thuần trên JSON quy trình.
///
/// - `notify` / `card_send` / `process_send` → `send` (cùng tên trường: to, channels, text / card, message / process, sync);
/// - `buttons` có ít nhất một nút "chạy tiếp" → `wait_button` với `where.message`: nút thứ i không url → `nut_<i>` rẽ
///   tới đích cạnh đi ra cũ, nút có url → `link_<i>` chỉ mở link; bỏ cạnh. Mọi `steps.<bước>.output.clicked` của bước
///   đó đổi thành `.output.label` (bước cũ trả chữ nút ở `clicked`);
/// - `card_wait` → `wait_button` với `where.card`: nút theo `ids` (nhãn lấy từ thẻ của bước gửi thẻ), không có `ids` thì
///   mọi nút có id của thẻ; không biết trước → một nút "*" (bất kỳ nút nào). Mọi nút và Quá hạn tới đích cạnh cũ.
library;

/// Kết quả: quy trình đã đổi, id các bước đã đổi (theo thứ tự), loại mới đã dùng (send / wait_button).
class LegacyUpgrade {
  final Map<String, dynamic> def;
  final List<String> ids;
  final List<String> kinds;
  const LegacyUpgrade(this.def, this.ids, this.kinds);
}

const legacySendTypes = {'notify', 'card_send', 'process_send'};

/// Mã nút "bất kỳ nút nào trên thẻ" của `wait_button` với `where.card`.
const anyButtonId = '*';

bool _isUrl(Object? b) => b is Map && '${b['url'] ?? ''}'.trim().isNotEmpty;

/// Bước `buttons` này có phải bước chờ (có nút chạy tiếp) không.
bool buttonsWait(Map n) => n['type'] == 'buttons' && (n['buttons'] as List? ?? const []).any((b) => b is Map && !_isUrl(b));

Map<String, dynamic> _base(Map n) => {
      'id': n['id'],
      if (n['no'] != null) 'no': n['no'],
      if (n['name'] != null) 'name': n['name'],
      if (n['delegation'] != null) 'delegation': n['delegation'],
    };

/// `notify` / `card_send` / `process_send` → `send` (null nếu không phải bước gửi kiểu cũ).
Map<String, dynamic>? sendFrom(Map<String, dynamic> n) {
  final t = n['type'];
  if (!legacySendTypes.contains(t)) return null;
  return {
    ..._base(n),
    'type': 'send',
    if (n['to'] != null) 'to': n['to'],
    if (n['channels'] != null) 'channels': n['channels'],
    if (t == 'notify') 'text': n['text'] ?? '',
    if (t == 'card_send') ...{'card': n['card'] ?? <String, dynamic>{}, if (n['message'] != null) 'message': n['message']},
    if (t == 'process_send') ...{'process': n['process'] ?? <String, dynamic>{}, if (n['sync'] != null) 'sync': n['sync']},
  };
}

/// `buttons` → `wait_button` (where.message); [target]: đích cạnh đi ra cũ. Null nếu không phải bước chờ.
Map<String, dynamic>? buttonsToWait(Map<String, dynamic> n, String target) {
  if (target.isEmpty || !buttonsWait(n)) return null;
  final bs = [for (final b in n['buttons'] as List) if (b is Map) b];
  return {
    ..._base(n),
    'type': 'wait_button',
    'where': {'message': n['message'] ?? <String, dynamic>{}},
    if (n['who'] != null) 'who': n['who'],
    'buttons': [
      for (final (i, b) in bs.indexed)
        _isUrl(b) ? {'id': 'link_${i + 1}', 'label': b['label'] ?? '', 'url': b['url']} : {'id': 'nut_${i + 1}', 'label': b['label'] ?? '', 'to': target},
    ],
  };
}

/// Các nút có id (mã, nhãn) của thẻ do bước gửi thẻ [card].step gửi.
List<(String, String)> _cardActions(Map<String, Map<String, dynamic>> nodes, Object? card) {
  final step = card is Map ? card['step'] : null;
  final n = step == null ? null : nodes['$step'];
  if (n == null || !(n['type'] == 'card_send' || (n['type'] == 'send' && n['card'] is Map))) return const [];
  return [
    for (final a in ((n['card'] as Map?)?['actions'] as List? ?? const []))
      if (a is Map && a['id'] is String) ('${a['id']}', '${a['label'] ?? a['id']}'),
  ];
}

/// `card_wait` → `wait_button` (where.card); [target]: đích cạnh đi ra cũ.
Map<String, dynamic>? cardWaitToWait(Map<String, Map<String, dynamic>> nodes, Map<String, dynamic> n, String target) {
  if (n['type'] != 'card_wait' || target.isEmpty) return null;
  final actions = _cardActions(nodes, n['card']);
  final ids = [for (final x in (n['ids'] as List? ?? const [])) '$x'];
  var list = ids.isEmpty ? actions : [for (final i in ids) (i, actions.where((a) => a.$1 == i).firstOrNull?.$2 ?? i)];
  final ok = RegExp(r'^[A-Za-z0-9_-]+$');
  if (list.isEmpty || !list.every((x) => ok.hasMatch(x.$1))) list = const [(anyButtonId, 'Bất kỳ nút nào')];
  final timeout = '${n['timeout'] ?? ''}';
  return {
    ..._base(n),
    'type': 'wait_button',
    'where': {'card': n['card'] ?? <String, dynamic>{}},
    if (n['who'] != null) 'who': n['who'],
    if (n['seconds'] != null) 'seconds': n['seconds'],
    'buttons': [for (final (id, label) in list) {'id': id, 'label': label, 'to': target}],
    if (timeout.isNotEmpty) ...{'timeout': n['timeout'], 'timeout_to': target},
  };
}

/// Đổi [from] thành [to] trong mọi chuỗi (chỉ khi sau đó không còn chữ của tên biến).
Object? _rename(Object? v, String from, String to) {
  if (v is String) {
    if (!v.contains(from)) return v;
    return v.replaceAllMapped(RegExp('${RegExp.escape(from)}(?![\\p{L}\\p{N}_])', unicode: true), (_) => to);
  }
  if (v is List) return [for (final x in v) _rename(x, from, to)];
  if (v is Map) return {for (final e in v.entries) '${e.key}': _rename(e.value, from, to)};
  return v;
}

/// Mọi đổi gửi + chờ bấm nút (bước Duyệt cũ đổi riêng ở [FlowDoc.fromJson]).
LegacyUpgrade upgradeLegacySteps(Map<String, dynamic> def) {
  final rawNodes = [for (final n in (def['nodes'] as List? ?? const [])) if (n is Map) n.cast<String, dynamic>()];
  final edges = [for (final e in (def['edges'] as List? ?? const [])) if (e is List && e.length == 2) ['${e[0]}', '${e[1]}']];
  final ids = <String>[], kinds = <String>[];
  void mark(String id, String kind) {
    ids.add(id);
    if (!kinds.contains(kind)) kinds.add(kind);
  }

  // Gửi.
  final nodes = <Map<String, dynamic>>[];
  for (final n in rawNodes) {
    final s = sendFrom(n);
    if (s != null) mark('${n['id']}', 'send');
    nodes.add(s ?? n);
  }
  // Chờ bấm nút: chỉ bước có đúng một cạnh đi ra.
  final byId = {for (final n in nodes) '${n['id']}': n};
  final drop = <String>{};
  final renamed = <String>[];
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i];
    final id = '${n['id']}';
    final outs = [for (final e in edges) if (e[0] == id) e[1]];
    if (outs.length != 1) continue;
    final up = switch (n['type']) {
      'buttons' => buttonsToWait(n, outs.single),
      'card_wait' => cardWaitToWait(byId, n, outs.single),
      _ => null,
    };
    if (up == null) continue;
    if (n['type'] == 'buttons') renamed.add(id);
    nodes[i] = up;
    drop.add('$id>${outs.single}');
    mark(id, 'wait_button');
  }
  if (ids.isEmpty) return LegacyUpgrade(def, const [], const []);
  Object? out = {...def, 'nodes': nodes, 'edges': [for (final e in edges) if (!drop.contains('${e[0]}>${e[1]}')) e]};
  for (final id in renamed) {
    out = _rename(out, 'steps.$id.output.clicked', 'steps.$id.output.label');
  }
  return LegacyUpgrade((out as Map).cast<String, dynamic>(), ids, kinds);
}

/// Loại bước kiểu cũ còn trong quy trình mà trình sửa đổi khi mở (như `legacy_kinds` của máy chủ).
List<String> legacyKinds(Map<String, dynamic> def) {
  final out = <String>[];
  for (final n in (def['nodes'] as List? ?? const [])) {
    if (n is! Map) continue;
    final t = '${n['type']}';
    final k = switch (t) {
      'approval' || 'notify' || 'card_send' || 'process_send' || 'card_wait' => t,
      'buttons' when buttonsWait(n) => t,
      _ => null,
    };
    if (k != null && !out.contains(k)) out.add(k);
  }
  return out;
}
