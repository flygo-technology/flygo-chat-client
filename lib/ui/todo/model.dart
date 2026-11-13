// Todo: dữ liệu ghi chú như máy chủ trả (flygo-chat-server todo/README.md). Nội dung là danh sách khối (TBlock), mỗi khối gồm
// các đoạn chữ có định dạng (TRun).
import 'dart:math';

final _rnd = Random();
String todoId([int n = 12]) {
  const a = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(n, (_) => a[_rnd.nextInt(a.length)]).join();
}

/// Định dạng của một đoạn chữ. fg / hl: tên màu chữ / màu tô (red, orange… xem kTextColors).
class TFmt {
  const TFmt({this.b = false, this.i = false, this.u = false, this.s = false, this.c = false, this.a, this.fg, this.hl});
  final bool b, i, u, s, c;
  final String? a, fg, hl;
  static const plain = TFmt();

  TFmt copyWith({bool? b, bool? i, bool? u, bool? s, bool? c, Object? a = _keep, Object? fg = _keep, Object? hl = _keep}) => TFmt(
        b: b ?? this.b,
        i: i ?? this.i,
        u: u ?? this.u,
        s: s ?? this.s,
        c: c ?? this.c,
        a: a == _keep ? this.a : a as String?,
        fg: fg == _keep ? this.fg : fg as String?,
        hl: hl == _keep ? this.hl : hl as String?,
      );

  bool get isPlain => this == plain;

  @override
  bool operator ==(Object other) => other is TFmt && other.b == b && other.i == i && other.u == u && other.s == s && other.c == c && other.a == a && other.fg == fg && other.hl == hl;
  @override
  int get hashCode => Object.hash(b, i, u, s, c, a, fg, hl);
}

const _keep = Object();

class TRun {
  TRun(this.x, [this.f = TFmt.plain]);
  String x;
  TFmt f;

  factory TRun.fromJson(Map m) => TRun('${m['x'] ?? ''}', TFmt(
        b: m['b'] == true,
        i: m['i'] == true,
        u: m['u'] == true,
        s: m['s'] == true,
        c: m['c'] == true,
        a: m['a'] as String?,
        fg: m['fg'] as String?,
        hl: m['hl'] as String?,
      ));

  Map<String, dynamic> toJson() => {
        'x': x,
        if (f.b) 'b': true,
        if (f.i) 'i': true,
        if (f.u) 'u': true,
        if (f.s) 's': true,
        if (f.c) 'c': true,
        if (f.a != null) 'a': f.a,
        if (f.fg != null) 'fg': f.fg,
        if (f.hl != null) 'hl': f.hl,
      };
}

/// Kiểu khối: p, h1, h2, h3, ul, ol, check, quote, code, hr.
class TBlock {
  TBlock({String? id, this.t = 'p', List<TRun>? r, this.done = false, this.ind = 0}) : id = id ?? todoId(10), r = r ?? [];
  final String id;
  String t;
  List<TRun> r;
  bool done;
  int ind;

  String get text => r.map((x) => x.x).join();
  bool get isList => t == 'ul' || t == 'ol' || t == 'check';

  factory TBlock.fromJson(Map m) => TBlock(
        id: '${m['id']}',
        t: '${m['t'] ?? 'p'}',
        r: [for (final x in (m['r'] as List? ?? const [])) TRun.fromJson(x as Map)],
        done: m['done'] == true,
        ind: (m['ind'] as num?)?.toInt() ?? 0,
      );

  factory TBlock.text(String s, {String t = 'p', bool done = false}) => TBlock(t: t, r: s.isEmpty ? [] : [TRun(s)], done: done);

  Map<String, dynamic> toJson() => {
        'id': id,
        't': t,
        'r': [for (final x in r) if (x.x.isNotEmpty) x.toJson()],
        if (t == 'check' && done) 'done': true,
        if (ind > 0) 'ind': ind,
      };

  TBlock clone() => TBlock(id: id, t: t, r: [for (final x in r) TRun(x.x, x.f)], done: done, ind: ind);
}

class TFile {
  const TFile({required this.id, required this.name, required this.mime, required this.size});
  final String id, name, mime;
  final int size;
  bool get isImage => mime.startsWith('image/');
  factory TFile.fromJson(Map m) => TFile(id: '${m['id']}', name: '${m['name'] ?? ''}', mime: '${m['mime'] ?? ''}', size: (m['size'] as num?)?.toInt() ?? 0);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'mime': mime, 'size': size};
}

class TMember {
  const TMember(this.id, this.name, this.role);
  final String id, name, role; // role: owner | editor | viewer
  factory TMember.fromJson(Map m) => TMember('${m['id']}', '${m['name'] ?? m['id']}', '${m['role'] ?? 'editor'}');
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role};
}

class TReminder {
  const TReminder(this.at, {this.repeat, this.done = false});
  final int at;
  final String? repeat; // daily | weekdays | weekly | monthly | yearly | every:<n><d|w|m>
  final bool done;
  factory TReminder.fromJson(Map m) => TReminder((m['at'] as num).toInt(), repeat: m['repeat'] as String?, done: m['done'] == true);
  Map<String, dynamic> toJson() => {'at': at, 'repeat': repeat, if (done) 'done': true};
}

class TLabel {
  const TLabel(this.id, this.name);
  final String id, name;
  factory TLabel.fromJson(Map m) => TLabel('${m['id']}', '${m['name']}');
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class TNote {
  TNote({
    required this.id,
    this.kind = 'note',
    this.title = '',
    List<TBlock>? blocks,
    this.color = 'default',
    this.bg,
    List<TFile>? files,
    this.version = 0,
    int? createdAt,
    int? updatedAt,
    this.editedBy,
    this.role = 'owner',
    this.pinned = false,
    this.archived = false,
    this.trashedAt,
    double? sort,
    List<String>? labels,
    this.reminder,
    List<TMember>? members,
  })  : blocks = blocks ?? [],
        files = files ?? [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch,
        sort = sort ?? DateTime.now().millisecondsSinceEpoch.toDouble(),
        labels = labels ?? [],
        members = members ?? [];

  final String id;
  String kind; // note | list
  String title;
  List<TBlock> blocks;
  String color;
  String? bg;
  List<TFile> files;
  int version; // 0 = chưa lên máy chủ
  int createdAt, updatedAt;
  String? editedBy;
  String role;
  bool pinned, archived;
  int? trashedAt;
  double sort;
  List<String> labels;
  TReminder? reminder;
  List<TMember> members;

  bool get canEdit => role != 'viewer';
  bool get isOwner => role == 'owner';
  bool get trashed => trashedAt != null;
  bool get isEmpty => title.trim().isEmpty && blocks.every((b) => b.text.trim().isEmpty && b.t != 'hr') && files.isEmpty;
  List<TMember> get others => members.where((m) => m.role != 'owner').toList();
  TMember? get owner => members.where((m) => m.role == 'owner').firstOrNull;
  String get plain => [title, ...blocks.map((b) => b.text)].join('\n');

  factory TNote.fromJson(Map m) => TNote(
        id: '${m['id']}',
        kind: '${m['kind'] ?? 'note'}',
        title: '${m['title'] ?? ''}',
        blocks: [for (final b in (m['blocks'] as List? ?? const [])) TBlock.fromJson(b as Map)],
        color: '${m['color'] ?? 'default'}',
        bg: m['bg'] as String?,
        files: [for (final f in (m['files'] as List? ?? const [])) if (f is Map) TFile.fromJson(f)],
        version: (m['version'] as num?)?.toInt() ?? 0,
        createdAt: (m['created_at'] as num?)?.toInt(),
        updatedAt: (m['updated_at'] as num?)?.toInt(),
        editedBy: m['edited_by'] as String?,
        role: '${m['role'] ?? 'owner'}',
        pinned: m['pinned'] == true,
        archived: m['archived'] == true,
        trashedAt: (m['trashed_at'] as num?)?.toInt(),
        sort: (m['sort'] as num?)?.toDouble(),
        labels: [for (final l in (m['labels'] as List? ?? const [])) '$l'],
        reminder: m['reminder'] is Map ? TReminder.fromJson(m['reminder'] as Map) : null,
        members: [for (final x in (m['members'] as List? ?? const [])) TMember.fromJson(x as Map)],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'blocks': [for (final b in blocks) b.toJson()],
        'color': color,
        'bg': bg,
        'files': [for (final f in files) f.toJson()],
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'edited_by': editedBy,
        'role': role,
        'pinned': pinned,
        'archived': archived,
        'trashed_at': trashedAt,
        'sort': sort,
        'labels': labels,
        'reminder': reminder?.toJson(),
        'members': [for (final x in members) x.toJson()],
      };

  TNote clone() => TNote.fromJson(toJson());

  /// Áp các trường của một lệnh PUT (app vừa sửa, chưa lên máy chủ) lên bản trong máy.
  void applyPut(Map<String, dynamic> b) {
    if (b.containsKey('kind')) kind = b['kind'] as String;
    if (b.containsKey('title')) title = b['title'] as String;
    if (b.containsKey('blocks')) blocks = [for (final x in b['blocks'] as List) TBlock.fromJson(x as Map)];
    if (b.containsKey('color')) color = b['color'] as String;
    if (b.containsKey('bg')) bg = b['bg'] as String?;
    if (b.containsKey('files')) files = [for (final f in b['files'] as List) if (f is Map) TFile.fromJson(f)];
    if (b.containsKey('pinned')) pinned = b['pinned'] == true;
    if (b.containsKey('archived')) archived = b['archived'] == true;
    if (b.containsKey('trashed')) trashedAt = b['trashed'] == true ? (trashedAt ?? DateTime.now().millisecondsSinceEpoch) : null;
    if (b.containsKey('sort')) sort = (b['sort'] as num).toDouble();
    if (b.containsKey('labels')) labels = [for (final l in b['labels'] as List) '$l'];
    if (b.containsKey('reminder')) reminder = b['reminder'] == null ? null : TReminder.fromJson(b['reminder'] as Map);
    // Ghim thì bỏ lưu trữ và ngược lại (như máy chủ).
    if (b['pinned'] == true && !b.containsKey('archived')) archived = false;
    if (b['archived'] == true && !b.containsKey('pinned')) pinned = false;
  }
}

/// Lặp lại lời nhắc: mã gửi máy chủ → tên hiển thị.
const kRepeats = {
  'daily': 'Hằng ngày',
  'weekdays': 'Ngày làm việc (T2–T6)',
  'weekly': 'Hằng tuần',
  'monthly': 'Hằng tháng',
  'yearly': 'Hằng năm',
};
