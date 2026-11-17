// Hợp đồng: dữ liệu (hợp đồng, bên ký, nhật ký) đọc từ JSON của máy chủ, cùng các hàm định dạng tiền / ngày
// và câu chữ tiếng Việt cho trạng thái, cách ký và từng dòng nhật ký.
typedef Json = Map<String, dynamic>;

/// Giờ hiện tại (kiểm thử thay bằng giờ cố định).
DateTime Function() hdNow = DateTime.now;

int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
String _s(Object? v) => v == null ? '' : '$v';

class HdMe {
  HdMe({required this.id, required this.name, this.admin = false, this.company = ''});
  factory HdMe.fromJson(Json j) {
    final u = Map<String, dynamic>.from((j['user'] as Map?) ?? const {});
    return HdMe(id: _s(u['id']), name: _s(u['name']), admin: j['admin'] == true, company: _s(j['company']));
  }
  final String id, name, company;
  final bool admin;
}

class HdCounts {
  const HdCounts({this.all = 0, this.draft = 0, this.sending = 0, this.signed = 0, this.rejected = 0, this.overdue = 0, this.expiring = 0});
  factory HdCounts.fromJson(Json j) => HdCounts(
        all: _int(j['all']) ?? 0, draft: _int(j['draft']) ?? 0, sending: _int(j['sending']) ?? 0, signed: _int(j['signed']) ?? 0,
        rejected: _int(j['rejected']) ?? 0, overdue: _int(j['overdue']) ?? 0, expiring: _int(j['expiring']) ?? 0,
      );
  final int all, draft, sending, signed, rejected, overdue, expiring;
  int of(String? status) => switch (status) {
        'draft' => draft, 'sending' => sending, 'signed' => signed, 'rejected' => rejected, 'overdue' => overdue, 'expiring' => expiring, _ => all,
      };
}

class HdParty {
  HdParty({
    required this.id, this.idx = 0, this.label = '', this.name = '', this.idKind = 'mst', this.idNo = '', this.email = '', this.internal = false,
    this.status = 'waiting', this.linkExpires, this.openedAt, this.openCount = 0, this.signedAt, this.signedVia, this.certCn, this.certIssuer,
    this.certSerial, this.rejectReason, this.link,
  });
  factory HdParty.fromJson(Json j) => HdParty(
        id: _s(j['id']), idx: _int(j['idx']) ?? 0, label: _s(j['label']), name: _s(j['name']), idKind: j['id_kind'] == 'cccd' ? 'cccd' : 'mst',
        idNo: _s(j['id_no']), email: _s(j['email']), internal: j['internal'] == true, status: _s(j['status']).isEmpty ? 'waiting' : _s(j['status']),
        linkExpires: _int(j['link_expires']), openedAt: _int(j['opened_at']), openCount: _int(j['open_count']) ?? 0, signedAt: _int(j['signed_at']),
        signedVia: j['signed_via'] as String?, certCn: j['cert_cn'] as String?, certIssuer: j['cert_issuer'] as String?,
        certSerial: j['cert_serial'] as String?, rejectReason: j['reject_reason'] as String?, link: j['link'] as String?,
      );
  final String id, label, name, idKind, idNo, email, status;
  final int idx, openCount;
  final bool internal;
  final int? linkExpires, openedAt, signedAt;
  final String? signedVia, certCn, certIssuer, certSerial, rejectReason, link;

  bool get signed => status == 'signed';
  bool get waitingTurn => status == 'ready' || status == 'opened';
  String get idLabel => '${idKind == 'cccd' ? 'CCCD' : 'MST'} $idNo';
  String get title => label.isEmpty ? name : '$label · $name';
  bool linkExpired(DateTime now) => linkExpires != null && linkExpires! < now.millisecondsSinceEpoch;
}

class HdEvent {
  HdEvent({required this.seq, required this.at, required this.actor, required this.action, this.detail = const {}, this.ip});
  factory HdEvent.fromJson(Json j) => HdEvent(
        seq: _int(j['seq']) ?? 0, at: _int(j['at']) ?? 0, actor: _s(j['actor']), action: _s(j['action']),
        detail: j['detail'] is Map ? Map<String, dynamic>.from(j['detail'] as Map) : const {}, ip: j['ip'] as String?,
      );
  final int seq, at;
  final String actor, action;
  final Json detail;
  final String? ip;
}

class HdDoc {
  HdDoc({required this.name, required this.rev, this.sha256, this.pages});
  final String name;
  final int rev;
  final String? sha256;
  final int? pages;
}

class Contract {
  Contract({
    required this.id, this.no = '', this.title = '', this.value, this.currency = 'VND', this.effFrom, this.effTo, this.signDeadline, this.remindDays = 0,
    this.note = '', this.notePublic = false, this.mode = 'seq', this.status = 'draft', this.ownerId = '', this.ownerName = '', this.role, this.doc,
    this.sentAt, this.doneAt, this.updatedAt, this.parties = const [], this.events = const [],
  });
  factory Contract.fromJson(Json j) {
    final d = j['doc'] is Map ? Map<String, dynamic>.from(j['doc'] as Map) : null;
    final o = Map<String, dynamic>.from((j['owner'] as Map?) ?? const {});
    return Contract(
      id: _s(j['id']), no: _s(j['no']), title: _s(j['title']), value: j['value'] as num?, currency: _s(j['currency']).isEmpty ? 'VND' : _s(j['currency']),
      effFrom: _int(j['eff_from']), effTo: _int(j['eff_to']), signDeadline: _int(j['sign_deadline']), remindDays: _int(j['remind_days']) ?? 0,
      note: _s(j['note']), notePublic: j['note_public'] == true, mode: j['mode'] == 'par' ? 'par' : 'seq', status: _s(j['status']).isEmpty ? 'draft' : _s(j['status']),
      ownerId: _s(o['id']), ownerName: _s(o['name']), role: j['role'] as String?,
      doc: d == null ? null : HdDoc(name: _s(d['name']), rev: _int(d['rev']) ?? 1, sha256: d['sha256'] as String?, pages: _int(d['pages'])),
      sentAt: _int(j['sent_at']), doneAt: _int(j['done_at']), updatedAt: _int(j['updated_at']),
      parties: [for (final p in (j['parties'] as List? ?? const [])) HdParty.fromJson(Map<String, dynamic>.from(p as Map))]..sort((a, b) => a.idx.compareTo(b.idx)),
      events: [for (final e in (j['events'] as List? ?? const [])) HdEvent.fromJson(Map<String, dynamic>.from(e as Map))],
    );
  }

  final String id, no, title, currency, note, mode, status, ownerId, ownerName;
  final num? value;
  final int? effFrom, effTo, signDeadline, sentAt, doneAt, updatedAt;
  final int remindDays;
  final bool notePublic;
  final String? role;
  final HdDoc? doc;
  final List<HdParty> parties;
  final List<HdEvent> events;

  int get signedCount => parties.where((p) => p.signed).length;
  bool get isDraft => status == 'draft';
  bool get canEdit => role != 'viewer';
  String get heading => [if (no.isNotEmpty) no, if (title.isNotEmpty) title].join(' · ');

  /// Đang gửi ký mà đã quá hạn ký.
  bool overdue(DateTime now) => status == 'sending' && signDeadline != null && signDeadline! < now.millisecondsSinceEpoch;

  /// Các bên đang tới lượt ký.
  List<HdParty> get current => [for (final p in parties) if (p.waitingTurn) p];

  /// Bên khác mình (đối tác) để hiện ở danh sách.
  HdParty? get partner => parties.where((p) => !p.internal).firstOrNull ?? parties.firstOrNull;

  HdParty? party(String id) => parties.where((p) => p.id == id).firstOrNull;
}

// ---------------------------------------------------------------- định dạng
String _p2(int n) => n.toString().padLeft(2, '0');
DateTime _t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms).toLocal();

/// dd/MM/yyyy.
String dmy(int? ms) {
  if (ms == null) return '';
  final t = _t(ms);
  return '${_p2(t.day)}/${_p2(t.month)}/${t.year}';
}

/// dd/MM.
String dm(int? ms) {
  if (ms == null) return '';
  final t = _t(ms);
  return '${_p2(t.day)}/${_p2(t.month)}';
}

/// dd/MM HH:mm.
String dmHm(int? ms) {
  if (ms == null) return '';
  final t = _t(ms);
  return '${_p2(t.day)}/${_p2(t.month)} ${_p2(t.hour)}:${_p2(t.minute)}';
}

/// dd/MM/yyyy HH:mm.
String dmyHm(int? ms) {
  if (ms == null) return '';
  final t = _t(ms);
  return '${dmy(ms)} ${_p2(t.hour)}:${_p2(t.minute)}';
}

/// Nhóm hàng nghìn bằng dấu chấm: 360000000 → "360.000.000".
String groupDigits(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

/// Tiền kiểu vi-VN: "360.000.000 ₫" (VND) hoặc "1.200 USD".
String money(num? v, [String currency = 'VND']) {
  if (v == null) return '—';
  final c = currency.toUpperCase();
  return '${groupDigits(v)} ${c == 'VND' ? '₫' : c}';
}

/// Đọc số tiền gõ tay ("360.000.000", "360 000 000 đ") → 360000000.
num? parseMoney(String s) {
  final d = s.replaceAll(RegExp(r'[^0-9]'), '');
  return d.isEmpty ? null : int.tryParse(d);
}

/// MST: 10 số hoặc 10 số-3 số (chi nhánh). CCCD: 12 số. Như máy chủ.
bool validId(String kind, String no) {
  final n = no.replaceAll(RegExp(r'\s+'), '');
  return kind == 'cccd' ? RegExp(r'^\d{12}$').hasMatch(n) : RegExp(r'^\d{10}(-\d{3})?$').hasMatch(n);
}

/// Đoán loại mã: 12 số là CCCD, còn lại là MST.
String guessKind(String no) => RegExp(r'^\d{12}$').hasMatch(no.replaceAll(RegExp(r'\s+'), '')) ? 'cccd' : 'mst';

/// Chữ viết tắt cho ô avatar: "CÔNG TY CP ĐÔNG NAM Á" → "ĐN".
String initials(String name) {
  const skip = {'CÔNG', 'TY', 'CP', 'TNHH', 'CỔ', 'PHẦN', 'MTV', 'CTY', 'CÔNG TY', 'VÀ', 'CỦA', 'THƯƠNG', 'MẠI'};
  final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  final core = w.where((x) => !skip.contains(x.toUpperCase())).toList();
  final use = core.isEmpty ? w : core;
  if (use.isEmpty) return '?';
  final s = use.length == 1 ? use.first.characters2 : '${use[0][0]}${use[1][0]}';
  return s.toUpperCase();
}

extension on String {
  String get characters2 => length <= 2 ? this : substring(0, 2);
}

/// Tên bên ký mặc định theo thứ tự: Bên A, Bên B, …
String defaultLabel(int i) => 'Bên ${String.fromCharCode(65 + (i % 26))}';

// ---------------------------------------------------------------- câu chữ
const kStatusLabels = {'draft': 'Nháp', 'sending': 'Đang ký', 'signed': 'Đã ký đủ', 'rejected': 'Bị từ chối', 'cancelled': 'Đã huỷ'};

/// Cách bên đã ký: plugin:misa → "qua plugin MISA", offline → "ký offline".
String viaText(String? via) {
  if (via == null || via.isEmpty) return '';
  if (via == 'offline') return 'ký offline';
  const names = {'misa': 'MISA', 'cthub': 'CT Hub', 'viettel': 'Viettel', 'efy': 'EFY', 'kysodanang': 'Ký số đa năng', 'unknown': 'plugin'};
  final k = via.startsWith('plugin:') ? via.substring(7) : via;
  return 'qua plugin ${names[k] ?? k}';
}

const _fieldNames = {
  'no': 'số HĐ', 'title': 'tên', 'value': 'giá trị', 'currency': 'tiền tệ', 'eff_from': 'hiệu lực', 'eff_to': 'hiệu lực', 'sign_deadline': 'hạn ký',
  'mode': 'thứ tự ký', 'note': 'ghi chú', 'note_public': 'ghi chú', 'remind_days': 'nhắc gia hạn', 'parties': 'các bên ký',
};

/// Một dòng nhật ký: (câu tiếng Việt, cảnh báo?).
(String, bool) eventText(HdEvent e, Contract c) {
  final d = e.detail;
  String who() {
    if (e.actor.startsWith('party:')) {
      final p = c.party(e.actor.substring(6));
      return p == null ? 'Đối tác' : (p.label.isNotEmpty ? p.label : p.name);
    }
    if (e.actor == 'system') return 'Hệ thống';
    if (d['by'] != null) return '${d['by']}';
    return e.actor == c.ownerId && c.ownerName.isNotEmpty ? c.ownerName : 'Người dùng';
  }

  String pname() {
    final p = d['party'] is String ? c.party(d['party'] as String) : null;
    final n = d['name'] ?? p?.name ?? '';
    final l = d['label'] ?? p?.label ?? '';
    return '$l'.isEmpty ? '$n' : '$l ($n)';
  }

  String plugin(Object? k) => viaText(k == null ? null : 'plugin:$k').replaceFirst('qua plugin ', '');
  switch (e.action) {
    case 'create':
      return ('${who()} tạo hợp đồng', false);
    case 'update':
      final f = {for (final x in (d['fields'] as List? ?? const [])) _fieldNames['$x'] ?? '$x'}.join(', ');
      return ('${who()} sửa ${f.isEmpty ? 'hợp đồng' : f}', false);
    case 'doc':
      return ('Tải lên tài liệu ${d['name'] ?? ''} · bản ${d['rev'] ?? ''}', false);
    case 'send':
      return ('${who()} gửi ký · ${d['mode'] == 'par' ? 'cùng lúc' : 'lần lượt'}', false);
    case 'turn':
      return ('Gửi link ký cho ${pname()}', false);
    case 'open':
      return ('${who()} mở link ký${(d['n'] ?? 1) is num && (d['n'] as num) > 1 ? ' (lần ${d['n']})' : ''}', false);
    case 'view':
      return ('${who()} xem tài liệu', false);
    case 'download':
      return ('${who()} tải PDF về', false);
    case 'plugins':
      final f = (d['found'] as List? ?? const []).map(plugin).join(', ');
      return ('${who()}: tìm thấy plugin ${f.isEmpty ? 'ký số' : f}', false);
    case 'no_plugin':
      return ('${who()}: không thấy plugin → chọn ký offline', false);
    case 'plugin_error':
      return ('${who()}: plugin ký số lỗi${d['error'] != null ? ' · ${d['error']}' : ''}', true);
    case 'sign_begin':
      return ('${who()} bắt đầu ký qua ${plugin(d['plugin'])}${d['cn'] != null ? ' · ${d['cn']}' : ''}', false);
    case 'wrong_cert':
      final ids = d['ids'] is Map ? (d['ids'] as Map) : const {};
      final got = ids['mst'] != null ? 'MST ${ids['mst']}' : ids['cccd'] != null ? 'CCCD ${ids['cccd']}' : '${d['cn'] ?? 'khác'}';
      return ('${who()} chọn chứng thư $got sai ${d['want'] ?? 'MST'} → bị từ chối', true);
    case 'sign_failed':
      return ('${who()} ký lỗi${d['error'] != null ? ' · ${d['error']}' : ''}', true);
    case 'signed':
      final via = d['via'] == 'offline' ? 'ký offline (tải bản đã ký lên) · chữ ký hợp lệ' : 'ký ${viaText('${d['via']}')}';
      return ('${who()} $via${d['issuer'] != null ? ' · ${d['issuer']}' : ''}', false);
    case 'upload_rejected':
      final r = d['reason'] == 'not_incremental' ? 'không phải bản PDF của hợp đồng' : '${d['reason'] ?? ''}';
      return ('${who()} tải lên bản ký bị từ chối · $r', true);
    case 'rejected':
      return ('${who()} từ chối ký: "${d['reason'] ?? ''}"', true);
    case 'completed':
      return ('Hoàn tất · đủ chữ ký các bên', false);
    case 'cancel':
      final r = '${d['reason'] ?? ''}';
      return ('${who()} huỷ hợp đồng${r.isEmpty ? '' : ': $r'}', true);
    case 'extend':
      return ('${who()} gia hạn link ký cho ${pname()} tới ${dmHm(d['until'] is num ? (d['until'] as num).toInt() : null)}', false);
    case 'revoke':
      return ('${who()} thu hồi link ký của ${pname()}', true);
    case 'remind':
      return ('${who()} gửi nhắc ký cho ${pname()}', false);
    case 'share':
      return ('${who()} chia sẻ cho ${(d['members'] as List? ?? const []).join(', ')}', false);
    case 'expiry_reminder':
      return ('Nhắc gia hạn: hợp đồng hết hiệu lực ${dmy(d['eff_to'] is num ? (d['eff_to'] as num).toInt() : null)}', true);
  }
  return ('${who()} · ${e.action}', false);
}

/// Tiền gọn: "1,24 tỷ ₫", "360 tr ₫".
String moneyShort(num? v, [String currency = 'VND']) {
  if (v == null) return '—';
  final c = currency.toUpperCase() == 'VND' ? '₫' : currency.toUpperCase();
  String f(double x) {
    var s = x.toStringAsFixed(x >= 100 ? 0 : (x >= 10 ? 1 : 2));
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s.replaceAll('.', ',');
  }

  if (v.abs() >= 1e9) return '${f(v / 1e9)} tỷ $c';
  if (v.abs() >= 1e6) return '${f(v / 1e6)} tr $c';
  return '${groupDigits(v)} $c';
}

/// dd/MM/yy (bảng danh sách).
String dmyShort(int? ms) {
  if (ms == null) return '';
  final t = _t(ms);
  return '${_p2(t.day)}/${_p2(t.month)}/${_p2(t.year % 100)}';
}
