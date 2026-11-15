// Quản trị Thư (vn.flygo.mail): tên miền, hộp thư (cá nhân / dùng chung / nhóm), bí danh, thành viên + quyền,
// nhận mọi địa chỉ (catch-all) và quy tắc chuyển tiếp, giới hạn gửi / dung lượng, nhật ký quản trị.
// Máy chủ: <base_url>/mail/api/admin/* của Worker thư, chỉ cho người có quyền admin app vn.flygo.mail trong Flygo ID.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../browser/flygo_id.dart';
import '../../config.dart';
import 'api.dart';
import 'model.dart';

/// Tên miền nhận / gửi thư.
class MaDomain {
  MaDomain(this.name, {this.status = 'pending', this.dns = const {}, this.catchAll = 'reject', this.catchAllTarget = '', this.primary = false});
  final String name;
  /// active (nhận + gửi được) | pending (chờ bản ghi DNS) | error
  String status;
  /// Kiểm tra DNS: mx, spf, dkim, dmarc -> đúng chưa.
  Map<String, bool> dns;
  /// Thư tới địa chỉ chưa có: reject (trả lại) | mailbox (giao vào một hộp) | drop (bỏ im lặng)
  String catchAll;
  String catchAllTarget;
  bool primary;

  factory MaDomain.fromJson(Map m) => MaDomain('${m['name']}',
      status: '${m['status'] ?? 'pending'}',
      dns: {for (final e in (m['dns'] as Map? ?? const {}).entries) '${e.key}': e.value == true},
      catchAll: '${m['catch_all'] ?? 'reject'}',
      catchAllTarget: '${m['catch_all_target'] ?? ''}',
      primary: m['primary'] == true);
  Map<String, dynamic> toJson() => {'name': name, 'catch_all': catchAll, 'catch_all_target': catchAllTarget, 'primary': primary};
}

class MaMailbox {
  MaMailbox(this.id,
      {this.name = '',
      this.kind = 'personal',
      this.status = 'active',
      this.members = const {},
      this.forward = const [],
      this.keepCopy = true,
      this.limitHour,
      this.limitDay,
      this.quotaMb,
      this.usedMb = 0,
      this.sentToday = 0,
      this.unread = 0,
      this.created});
  final String id;
  String name;
  /// personal (hộp của một người) | shared (hộp dùng chung, thành viên đọc / gửi theo quyền) | group (nhóm: thư tới được chép vào hộp của từng thành viên)
  String kind;
  /// active | disabled (không nhận, không gửi; dữ liệu còn nguyên)
  String status;
  /// Thành viên -> quyền read | send | admin (nhóm: chỉ để biết ai nhận, quyền luôn là read).
  Map<String, String> members;
  /// Tự chuyển tiếp mọi thư đến tới các địa chỉ này.
  List<String> forward;
  bool keepCopy;
  /// Giới hạn riêng của hộp; null = theo mặc định.
  int? limitHour, limitDay, quotaMb;
  double usedMb;
  int sentToday, unread;
  DateTime? created;

  bool get disabled => status == 'disabled';
  String get display => name.isNotEmpty ? name : id;

  factory MaMailbox.fromJson(Map m) => MaMailbox('${m['id']}',
      name: '${m['name'] ?? ''}',
      kind: '${m['kind'] ?? 'personal'}',
      status: '${m['status'] ?? 'active'}',
      members: {for (final e in (m['members'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'},
      forward: [for (final f in (m['forward'] as List? ?? const [])) '$f'],
      keepCopy: m['keep_copy'] != false,
      limitHour: (m['limit_hour'] as num?)?.toInt(),
      limitDay: (m['limit_day'] as num?)?.toInt(),
      quotaMb: (m['quota_mb'] as num?)?.toInt(),
      usedMb: (m['used_mb'] as num?)?.toDouble() ?? 0,
      sentToday: (m['sent_today'] as num?)?.toInt() ?? 0,
      unread: (m['unread'] as num?)?.toInt() ?? 0,
      created: m['created'] is num ? DateTime.fromMillisecondsSinceEpoch((m['created'] as num).toInt()) : null);
}

/// Bí danh: thư tới [address] giao vào hộp [target].
class MaAlias {
  MaAlias(this.address, this.target, {this.enabled = true});
  final String address;
  String target;
  bool enabled;
  factory MaAlias.fromJson(Map m) => MaAlias('${m['address']}', '${m['target']}', enabled: m['enabled'] != false);
  Map<String, dynamic> toJson() => {'address': address, 'target': target, 'enabled': enabled};
}

/// Quy tắc định tuyến thư đến (chạy trước khi giao vào hộp).
class MaRule {
  MaRule({this.id = '', this.name = '', this.enabled = true, this.field = 'to', this.op = 'is', this.value = '', this.action = 'forward', this.target = ''});
  String id, name;
  bool enabled;
  /// to | from | subject
  String field;
  /// is | contains | ends
  String op;
  String value;
  /// forward (chuyển tiếp, vẫn giữ thư) | deliver (giao vào hộp khác) | drop (bỏ)
  String action;
  String target;

  factory MaRule.fromJson(Map m) => MaRule(
      id: '${m['id'] ?? ''}',
      name: '${m['name'] ?? ''}',
      enabled: m['enabled'] != false,
      field: '${m['field'] ?? 'to'}',
      op: '${m['op'] ?? 'is'}',
      value: '${m['value'] ?? ''}',
      action: '${m['action'] ?? 'forward'}',
      target: '${m['target'] ?? ''}');
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'enabled': enabled, 'field': field, 'op': op, 'value': value, 'action': action, 'target': target};
}

/// Giới hạn mặc định cho mọi hộp thư.
class MaLimits {
  MaLimits({this.perHour = 20, this.perDay = 100, this.maxRecipients = 50, this.maxAttachmentMb = 25, this.quotaMb = 2048, this.external = true});
  int perHour, perDay, maxRecipients, maxAttachmentMb, quotaMb;
  /// Cho gửi ra ngoài tên miền của mình.
  bool external;

  factory MaLimits.fromJson(Map m) => MaLimits(
      perHour: (m['per_hour'] as num?)?.toInt() ?? 20,
      perDay: (m['per_day'] as num?)?.toInt() ?? 100,
      maxRecipients: (m['max_recipients'] as num?)?.toInt() ?? 50,
      maxAttachmentMb: (m['max_attachment_mb'] as num?)?.toInt() ?? 25,
      quotaMb: (m['quota_mb'] as num?)?.toInt() ?? 2048,
      external: m['external'] != false);
  Map<String, dynamic> toJson() =>
      {'per_hour': perHour, 'per_day': perDay, 'max_recipients': maxRecipients, 'max_attachment_mb': maxAttachmentMb, 'quota_mb': quotaMb, 'external': external};
}

class MaAudit {
  const MaAudit(this.at, this.actor, this.action, this.target, [this.detail = '']);
  final DateTime at;
  final String actor, action, target, detail;
  factory MaAudit.fromJson(Map m) =>
      MaAudit(DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0), '${m['actor'] ?? ''}', '${m['action'] ?? ''}', '${m['target'] ?? ''}', '${m['detail'] ?? ''}');
}

/// Toàn bộ cấu hình quản trị (một lần tải).
class MaState {
  MaState({this.domains = const [], this.mailboxes = const [], this.aliases = const [], this.rules = const [], MaLimits? limits, this.usedToday = 0, this.monthSent})
      : limits = limits ?? MaLimits();
  List<MaDomain> domains;
  List<MaMailbox> mailboxes;
  List<MaAlias> aliases;
  List<MaRule> rules;
  MaLimits limits;
  /// Số thư cả hệ thống đã gửi hôm nay / tháng này (null: máy chủ chưa đếm theo tháng).
  int usedToday;
  int? monthSent;

  factory MaState.fromJson(Map m) => MaState(
        domains: [for (final d in (m['domains'] as List? ?? const [])) MaDomain.fromJson(d as Map)],
        mailboxes: [for (final d in (m['mailboxes'] as List? ?? const [])) MaMailbox.fromJson(d as Map)],
        aliases: [for (final d in (m['aliases'] as List? ?? const [])) MaAlias.fromJson(d as Map)],
        rules: [for (final d in (m['rules'] as List? ?? const [])) MaRule.fromJson(d as Map)],
        limits: m['limits'] is Map ? MaLimits.fromJson(m['limits'] as Map) : null,
        usedToday: (m['sent_today'] as num?)?.toInt() ?? 0,
        monthSent: (m['sent_month'] as num?)?.toInt(),
      );

  MaMailbox? box(String id) => mailboxes.where((b) => b.id == id).firstOrNull;
  List<MaAlias> aliasesOf(String id) => aliases.where((a) => a.target == id).toList();
}

abstract class MailAdminApi {
  bool get demo => false;
  Future<MaState> load();
  Future<void> addDomain(String name);
  Future<void> updateDomain(MaDomain d);
  Future<void> verifyDomain(String name);
  Future<void> deleteDomain(String name);
  Future<void> createMailbox(String id, {String name = '', String kind = 'personal', Map<String, String> members = const {}});
  /// Đổi các trường của hộp thư: name, status, forward, keep_copy, limit_hour, limit_day, quota_mb, kind.
  Future<void> updateMailbox(String id, Map<String, dynamic> patch);
  Future<void> setMembers(String id, Map<String, String> members);
  /// Xoá hộp thư cùng toàn bộ thư và tệp (không khôi phục được).
  Future<void> deleteMailbox(String id);
  Future<void> saveAlias(MaAlias a);
  Future<void> deleteAlias(String address);
  Future<void> saveRule(MaRule r);
  Future<void> deleteRule(String id);
  Future<void> saveLimits(MaLimits l);
  Future<List<MaAudit>> audit({String q = '', DateTime? before});
}

class HttpMailAdminApi extends MailAdminApi {
  HttpMailAdminApi({required this.base, required this.id, http.Client? client}) : _http = client ?? http.Client();
  final String base;
  final FlygoId id;
  final http.Client _http;

  Future<dynamic> _call(String method, String path, [Object? body, bool retried = false]) async {
    final req = http.Request(method, Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/mail/api/admin$path'))
      ..headers.addAll({
        'Authorization': 'Bearer ${await id.ticket(kMailApp, refresh: retried).timeout(const Duration(seconds: 25))}',
        'User-Agent': kUserAgent,
      });
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await _http.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 45));
    if (res.statusCode == 401 && !retried) return _call(method, path, body, true);
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    if (res.statusCode >= 400) {
      final e = j is Map ? '${j['error'] ?? ''}' : '';
      throw MailException(res.statusCode, e.isNotEmpty ? e : (res.statusCode == 403 ? 'Bạn không có quyền quản trị Thư' : 'Máy chủ thư trả lỗi ${res.statusCode}'));
    }
    return j;
  }

  String _e(String s) => Uri.encodeComponent(s);

  @override
  Future<MaState> load() async => MaState.fromJson(await _call('GET', '/state') as Map);
  @override
  Future<void> addDomain(String name) => _call('POST', '/domains', {'name': name});
  @override
  Future<void> updateDomain(MaDomain d) => _call('PUT', '/domains/${_e(d.name)}', d.toJson());
  @override
  Future<void> verifyDomain(String name) => _call('POST', '/domains/${_e(name)}/verify', const {});
  @override
  Future<void> deleteDomain(String name) => _call('DELETE', '/domains/${_e(name)}');
  @override
  Future<void> createMailbox(String id, {String name = '', String kind = 'personal', Map<String, String> members = const {}}) =>
      _call('POST', '/mailboxes', {'id': id, 'name': name, 'kind': kind, 'members': members});
  @override
  Future<void> updateMailbox(String id, Map<String, dynamic> patch) => _call('PATCH', '/mailboxes/${_e(id)}', patch);
  @override
  Future<void> setMembers(String id, Map<String, String> members) => _call('PUT', '/mailboxes/${_e(id)}/members', {'members': members});
  @override
  Future<void> deleteMailbox(String id) => _call('DELETE', '/mailboxes/${_e(id)}');
  @override
  Future<void> saveAlias(MaAlias a) => _call('PUT', '/aliases/${_e(a.address)}', a.toJson());
  @override
  Future<void> deleteAlias(String address) => _call('DELETE', '/aliases/${_e(address)}');
  @override
  Future<void> saveRule(MaRule r) => r.id.isEmpty ? _call('POST', '/rules', r.toJson()) : _call('PUT', '/rules/${_e(r.id)}', r.toJson());
  @override
  Future<void> deleteRule(String id) => _call('DELETE', '/rules/${_e(id)}');
  @override
  Future<void> saveLimits(MaLimits l) => _call('PUT', '/limits', l.toJson());
  @override
  Future<List<MaAudit>> audit({String q = '', DateTime? before}) async {
    final qs = [if (q.isNotEmpty) 'q=${_e(q)}', if (before != null) 'before=${before.millisecondsSinceEpoch}'].join('&');
    final j = await _call('GET', '/audit${qs.isEmpty ? '' : '?$qs'}') as Map;
    return [for (final a in (j['items'] as List? ?? const [])) MaAudit.fromJson(a as Map)];
  }
}

/// Dữ liệu mẫu (xem thử / chụp ảnh / test). Tên người là giả, tên miền example.
class DemoMailAdminApi extends MailAdminApi {
  DemoMailAdminApi({DateTime? now}) : _now = now ?? DateTime.now() {
    final d = const Duration(days: 1), h = const Duration(hours: 1);
    _s = MaState(
      domains: [
        MaDomain('example.com', status: 'active', dns: {'mx': true, 'spf': true, 'dkim': true, 'dmarc': true}, catchAll: 'mailbox', catchAllTarget: 'hotro@example.com', primary: true),
        MaDomain('example.vn', status: 'pending', dns: {'mx': true, 'spf': true, 'dkim': false, 'dmarc': false}),
      ],
      mailboxes: [
        MaMailbox('khoa@example.com', name: 'Trần Minh Khoa', usedMb: 812, sentToday: 14, unread: 4, created: _now.subtract(d * 40)),
        MaMailbox('trang.phan@example.com', name: 'Phan Thu Trang', members: {'khoa@example.com': 'send'}, usedMb: 1540, sentToday: 6, unread: 1, created: _now.subtract(d * 38)),
        MaMailbox('long@example.com', name: 'Lê Hoàng Long', usedMb: 233, sentToday: 3, created: _now.subtract(d * 30)),
        MaMailbox('mai.ketoan@example.com', name: 'Phạm Thị Mai', usedMb: 1960, quotaMb: 4096, sentToday: 21, limitDay: 300, created: _now.subtract(d * 30)),
        MaMailbox('hotro@example.com',
            name: 'Hỗ trợ khách hàng',
            kind: 'shared',
            members: {'khoa@example.com': 'send', 'long@example.com': 'send', 'thao@example.com': 'read', 'son@example.com': 'admin'},
            limitHour: 60,
            limitDay: 400,
            usedMb: 640,
            sentToday: 38,
            unread: 2,
            created: _now.subtract(d * 25)),
        MaMailbox('ketoan@example.com',
            name: 'Phòng Kế toán', kind: 'shared', members: {'mai.ketoan@example.com': 'admin', 'khoa@example.com': 'read'}, usedMb: 410, sentToday: 2, unread: 2, created: _now.subtract(d * 25)),
        MaMailbox('kinhdoanh@example.com',
            name: 'Nhóm Kinh doanh', kind: 'group', members: {'khoa@example.com': 'read', 'long@example.com': 'read', 'trang.phan@example.com': 'read'}, created: _now.subtract(d * 12)),
        MaMailbox('tuyendung@example.com',
            name: 'Tuyển dụng', kind: 'shared', members: {'trang.phan@example.com': 'send'}, forward: ['hr-backup@partner.example'], usedMb: 96, unread: 1, created: _now.subtract(d * 9)),
        MaMailbox('son@example.com', name: 'Đỗ Văn Sơn', status: 'disabled', usedMb: 120, created: _now.subtract(d * 30)),
      ],
      aliases: [
        MaAlias('info@example.com', 'hotro@example.com'),
        MaAlias('support@example.com', 'hotro@example.com'),
        MaAlias('billing@example.com', 'ketoan@example.com'),
        MaAlias('hoadon@example.com', 'ketoan@example.com'),
        MaAlias('ceo@example.com', 'khoa@example.com'),
        MaAlias('jobs@example.com', 'tuyendung@example.com', enabled: false),
      ],
      rules: [
        MaRule(id: 'r1', name: 'Hoá đơn điện tử về Kế toán', field: 'from', op: 'ends', value: '@einvoice.example', action: 'deliver', target: 'ketoan@example.com'),
        MaRule(id: 'r2', name: 'Chép thư khách VIP cho Sếp', field: 'from', op: 'ends', value: '@anduong.example', action: 'forward', target: 'khoa@example.com'),
        MaRule(id: 'r3', name: 'Chặn thư quảng cáo trúng thưởng', field: 'subject', op: 'contains', value: 'trúng thưởng', action: 'drop', enabled: false),
      ],
      limits: MaLimits(),
      usedToday: 84,
      monthSent: 1932,
    );
    _log = [
      MaAudit(_now.subtract(h * .3), 'khoa@example.com', 'members.set', 'hotro@example.com', 'thao@example.com: Chỉ xem'),
      MaAudit(_now.subtract(h * 2), 'khoa@example.com', 'alias.create', 'support@example.com', 'giao vào hotro@example.com'),
      MaAudit(_now.subtract(h * 5), 'mai.ketoan@example.com', 'members.set', 'ketoan@example.com', 'khoa@example.com: Chỉ xem'),
      MaAudit(_now.subtract(h * 26), 'khoa@example.com', 'mailbox.disable', 'son@example.com', 'Nghỉ việc'),
      MaAudit(_now.subtract(h * 30), 'khoa@example.com', 'rule.create', 'Hoá đơn điện tử về Kế toán', 'người gửi @einvoice.example: giao vào ketoan@example.com'),
      MaAudit(_now.subtract(d * 2), 'khoa@example.com', 'domain.add', 'example.vn', ''),
      MaAudit(_now.subtract(d * 3), 'khoa@example.com', 'limits.update', 'Mặc định', '20/giờ, 100/ngày'),
      MaAudit(_now.subtract(d * 9), 'khoa@example.com', 'mailbox.create', 'tuyendung@example.com', 'Hộp dùng chung'),
      MaAudit(_now.subtract(d * 12), 'khoa@example.com', 'mailbox.create', 'kinhdoanh@example.com', 'Nhóm'),
    ];
  }

  final DateTime _now;
  late MaState _s;
  late List<MaAudit> _log;
  static const _me = 'khoa@example.com';

  @override
  bool get demo => true;

  void _audit(String action, String target, [String detail = '']) => _log.insert(0, MaAudit(DateTime.now(), _me, action, target, detail));

  @override
  Future<MaState> load() async => _s;

  @override
  Future<void> addDomain(String name) async {
    final n = name.trim().toLowerCase();
    if (_s.domains.any((d) => d.name == n)) throw MailException(409, 'Tên miền đã có');
    _s.domains = [..._s.domains, MaDomain(n, dns: {'mx': false, 'spf': false, 'dkim': false, 'dmarc': false})];
    _audit('domain.add', n);
  }

  @override
  Future<void> updateDomain(MaDomain d) async => _audit('domain.update', d.name, 'catch-all: ${d.catchAll}${d.catchAllTarget.isEmpty ? '' : ': ${d.catchAllTarget}'}');

  @override
  Future<void> verifyDomain(String name) async => _audit('domain.verify', name);

  @override
  Future<void> deleteDomain(String name) async {
    _s.domains = _s.domains.where((d) => d.name != name).toList();
    _audit('domain.delete', name);
  }

  @override
  Future<void> createMailbox(String id, {String name = '', String kind = 'personal', Map<String, String> members = const {}}) async {
    final a = id.trim().toLowerCase();
    if (_s.box(a) != null || _s.aliases.any((x) => x.address == a)) throw MailException(409, 'Địa chỉ đã được dùng');
    _s.mailboxes = [..._s.mailboxes, MaMailbox(a, name: name, kind: kind, members: {...members}, created: DateTime.now())];
    _audit('mailbox.create', a, const {'personal': 'Hộp cá nhân', 'shared': 'Hộp dùng chung', 'group': 'Nhóm'}[kind] ?? kind);
  }

  @override
  Future<void> updateMailbox(String id, Map<String, dynamic> patch) async {
    final b = _s.box(id);
    if (b == null) throw MailException(404, 'Không có hộp thư này');
    if (patch['name'] is String) b.name = patch['name'] as String;
    if (patch['status'] is String) b.status = patch['status'] as String;
    if (patch['kind'] is String) b.kind = patch['kind'] as String;
    if (patch['forward'] is List) b.forward = [for (final f in patch['forward'] as List) '$f'];
    if (patch['keep_copy'] is bool) b.keepCopy = patch['keep_copy'] as bool;
    if (patch.containsKey('limit_hour')) b.limitHour = patch['limit_hour'] as int?;
    if (patch.containsKey('limit_day')) b.limitDay = patch['limit_day'] as int?;
    if (patch.containsKey('quota_mb')) b.quotaMb = patch['quota_mb'] as int?;
    _audit(patch['status'] == 'disabled' ? 'mailbox.disable' : patch['status'] == 'active' ? 'mailbox.enable' : 'mailbox.update', id, patch.keys.join(', '));
  }

  @override
  Future<void> setMembers(String id, Map<String, String> members) async {
    _s.box(id)?.members = {...members};
    _audit('members.set', id, members.entries.map((e) => '${e.key}: ${accessName(e.value)}').join(', '));
  }

  @override
  Future<void> deleteMailbox(String id) async {
    _s.mailboxes = _s.mailboxes.where((b) => b.id != id).toList();
    _s.aliases = _s.aliases.where((a) => a.target != id).toList();
    _audit('mailbox.delete', id);
  }

  @override
  Future<void> saveAlias(MaAlias a) async {
    final i = _s.aliases.indexWhere((x) => x.address == a.address);
    if (i < 0 && (_s.box(a.address) != null)) throw MailException(409, 'Địa chỉ đã là một hộp thư');
    _s.aliases = i < 0 ? [..._s.aliases, a] : (_s.aliases..[i] = a);
    _audit(i < 0 ? 'alias.create' : (a.enabled ? 'alias.update' : 'alias.disable'), a.address, 'giao vào ${a.target}');
  }

  @override
  Future<void> deleteAlias(String address) async {
    _s.aliases = _s.aliases.where((a) => a.address != address).toList();
    _audit('alias.delete', address);
  }

  @override
  Future<void> saveRule(MaRule r) async {
    if (r.id.isEmpty) {
      r.id = 'r${DateTime.now().microsecondsSinceEpoch}';
      _s.rules = [..._s.rules, r];
      _audit('rule.create', r.name);
    } else {
      final i = _s.rules.indexWhere((x) => x.id == r.id);
      if (i >= 0) _s.rules[i] = r;
      _audit('rule.update', r.name, r.enabled ? 'bật' : 'tắt');
    }
  }

  @override
  Future<void> deleteRule(String id) async {
    final r = _s.rules.where((x) => x.id == id).firstOrNull;
    _s.rules = _s.rules.where((x) => x.id != id).toList();
    _audit('rule.delete', r?.name ?? id);
  }

  @override
  Future<void> saveLimits(MaLimits l) async {
    _s.limits = l;
    _audit('limits.update', 'Mặc định', '${l.perHour}/giờ, ${l.perDay}/ngày');
  }

  @override
  Future<List<MaAudit>> audit({String q = '', DateTime? before}) async {
    final l = q.toLowerCase();
    return _log.where((a) => l.isEmpty || '${a.actor} ${a.action} ${a.target} ${a.detail}'.toLowerCase().contains(l)).toList();
  }
}
