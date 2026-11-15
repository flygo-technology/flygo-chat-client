// Thư (vn.flygo.mail): kiểu dữ liệu theo hợp đồng API của backend thư (docs/flygo-mail/API.md ở repo backend).

class MailPerson {
  const MailPerson(this.email, [this.name = '', this.me = false]);
  final String email, name;
  final bool me;

  factory MailPerson.fromJson(Map m) => MailPerson('${m['email'] ?? ''}', '${m['name'] ?? ''}', m['me'] == true);
  Map<String, dynamic> toJson() => {'email': email, 'name': name};

  /// Tên hiển thị đầy đủ (không có tên thì là địa chỉ).
  String get display => name.isNotEmpty ? name : email;

  /// Tên ngắn trong danh sách ("tôi", hoặc tên cuối kiểu Việt: "Nguyễn Văn Ba" → "Ba").
  String get short => me ? 'tôi' : (name.isNotEmpty ? name.trim().split(RegExp(r'\s+')).last : email.split('@').first);

  String get initial {
    final s = (name.isNotEmpty ? name.trim().split(RegExp(r'\s+')).last : email).trim();
    return s.isEmpty ? '?' : s.characters0.toUpperCase();
  }

  bool get valid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  @override
  bool operator ==(Object other) => other is MailPerson && other.email == email;
  @override
  int get hashCode => email.hashCode;
}

extension on String {
  /// Ký tự đầu (tính cả ký tự ghép UTF-16).
  String get characters0 => isEmpty ? '' : String.fromCharCode(runes.first);
}

class MailLabel {
  const MailLabel(this.id, this.name, this.color);
  final String id, name;
  final int color;

  factory MailLabel.fromJson(Map m) => MailLabel('${m['id']}', '${m['name'] ?? ''}', parseHexColor('${m['color'] ?? ''}'));
}

int parseHexColor(String s) {
  final h = s.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v ?? 0xFF5F6B7F;
}

String hexColor(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

class MailAttachment {
  const MailAttachment({required this.id, required this.name, this.size = 0, this.type = '', this.url = '', this.localPath});
  final String id, name, type, url;
  final int size;
  /// Tệp vừa chọn trên máy (chưa tải lên / bản demo).
  final String? localPath;

  factory MailAttachment.fromJson(Map m) => MailAttachment(
      id: '${m['id'] ?? ''}', name: '${m['name'] ?? ''}', size: (m['size'] as num?)?.toInt() ?? 0, type: '${m['type'] ?? ''}', url: '${m['url'] ?? ''}');
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'size': size, 'type': type, 'url': url};

  String get kind {
    final n = name.toLowerCase();
    if (type.contains('pdf') || n.endsWith('.pdf')) return 'pdf';
    if (type.startsWith('image/') || RegExp(r'\.(jpe?g|png|gif|webp|heic)$').hasMatch(n)) return 'img';
    if (type.contains('sheet') || type.contains('excel') || RegExp(r'\.(xlsx?|csv|ods)$').hasMatch(n)) return 'xls';
    if (type.contains('word') || RegExp(r'\.(docx?|odt|rtf)$').hasMatch(n)) return 'doc';
    return 'file';
  }
}

/// Hộp / mục xem: inbox, starred, snoozed, sent, drafts, important, all, spam, trash.
const kMailBoxes = ['inbox', 'starred', 'snoozed', 'sent', 'drafts', 'important', 'all', 'spam', 'trash'];

class MailThreadSummary {
  MailThreadSummary({
    required this.id,
    required this.subject,
    this.snippet = '',
    required this.date,
    this.count = 1,
    this.participants = const [],
    this.to = const [],
    this.unread = false,
    this.starred = false,
    this.important = false,
    this.labels = const [],
    this.box = 'inbox',
    this.draft = false,
    this.category = 'primary',
    this.attachments = const [],
  });

  final String id;
  String subject, snippet, box, category;
  DateTime date;
  int count;
  List<MailPerson> participants, to;
  bool unread, starred, important, draft;
  List<String> labels;
  List<MailAttachment> attachments;

  factory MailThreadSummary.fromJson(Map m) => MailThreadSummary(
        id: '${m['id']}',
        subject: '${m['subject'] ?? ''}',
        snippet: '${m['snippet'] ?? ''}',
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0),
        count: (m['count'] as num?)?.toInt() ?? 1,
        participants: [for (final p in (m['participants'] as List? ?? const [])) MailPerson.fromJson(p as Map)],
        to: [for (final p in (m['to'] as List? ?? const [])) MailPerson.fromJson(p as Map)],
        unread: m['unread'] == true,
        starred: m['starred'] == true,
        important: m['important'] == true,
        labels: [for (final l in (m['labels'] as List? ?? const [])) '$l'],
        box: '${m['box'] ?? 'inbox'}',
        draft: m['draft'] == true,
        category: '${m['category'] ?? 'primary'}',
        attachments: [for (final a in (m['attachments'] as List? ?? const [])) MailAttachment.fromJson(a as Map)],
      );

  /// Ảnh chụp các trạng thái để hoàn tác.
  Map<String, dynamic> snapshot() => {'box': box, 'unread': unread, 'starred': starred, 'important': important, 'labels': [...labels]};
}

class MailMessage {
  const MailMessage({required this.id, required this.from, this.to = const [], this.cc = const [], required this.date, this.html = '', this.attachments = const []});
  final String id, html;
  final MailPerson from;
  final List<MailPerson> to, cc;
  final DateTime date;
  final List<MailAttachment> attachments;

  factory MailMessage.fromJson(Map m) => MailMessage(
        id: '${m['id']}',
        from: MailPerson.fromJson(m['from'] as Map? ?? const {}),
        to: [for (final p in (m['to'] as List? ?? const [])) MailPerson.fromJson(p as Map)],
        cc: [for (final p in (m['cc'] as List? ?? const [])) MailPerson.fromJson(p as Map)],
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num?)?.toInt() ?? 0),
        html: '${m['html'] ?? ''}',
        attachments: [for (final a in (m['attachments'] as List? ?? const [])) MailAttachment.fromJson(a as Map)],
      );
}

class MailThread {
  MailThread(this.summary, this.messages);
  final MailThreadSummary summary;
  final List<MailMessage> messages;

  factory MailThread.fromJson(Map m) =>
      MailThread(MailThreadSummary.fromJson(m), [for (final x in (m['messages'] as List? ?? const [])) MailMessage.fromJson(x as Map)]);
}

class MailCounts {
  const MailCounts({this.inbox = 0, this.drafts = 0, this.spam = 0, this.categories = const {}, this.labels = const {}});
  final int inbox, drafts, spam;
  final Map<String, int> categories, labels;

  factory MailCounts.fromJson(Map m) => MailCounts(
        inbox: (m['inbox'] as num?)?.toInt() ?? 0,
        drafts: (m['drafts'] as num?)?.toInt() ?? 0,
        spam: (m['spam'] as num?)?.toInt() ?? 0,
        categories: {for (final e in (m['categories'] as Map? ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
        labels: {for (final e in (m['labels'] as Map? ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
      );
}

class MailMe {
  const MailMe(this.person, {this.mailboxes = const [], this.features = const {}, this.access = 'admin'});
  final MailPerson person;
  final List<String> mailboxes;
  final Map<String, bool> features;
  /// Quyền với hộp thư đang xem: read (chỉ xem, hộp được uỷ quyền) | send | admin.
  final String access;

  factory MailMe.fromJson(Map m) => MailMe(MailPerson('${m['email'] ?? ''}', '${m['name'] ?? ''}', true),
      mailboxes: [for (final x in (m['mailboxes'] as List? ?? const [])) '$x'],
      features: {for (final e in (m['features'] as Map? ?? const {}).entries) '${e.key}': e.value == true},
      access: '${m['access'] ?? 'admin'}');

  bool get readOnly => access == 'read';

  /// Tính năng backend có (mặc định có, trừ khi backend báo false).
  bool has(String f) => features[f] ?? true;
}

class MailPage {
  const MailPage(this.items, this.total, {this.page = 1, this.size = 50, this.counts});
  final List<MailThreadSummary> items;
  final int total, page, size;
  final MailCounts? counts;
}

class MailDraft {
  MailDraft({this.id, this.to = const [], this.cc = const [], this.bcc = const [], this.subject = '', this.html = '', this.attachments = const [], this.threadId});
  String? id, threadId;
  List<MailPerson> to, cc, bcc;
  String subject, html;
  List<MailAttachment> attachments;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'to': [for (final p in to) p.toJson()],
        'cc': [for (final p in cc) p.toJson()],
        'bcc': [for (final p in bcc) p.toJson()],
        'subject': subject,
        'html': html,
        'attachments': [for (final a in attachments) a.toJson()],
        if (threadId != null) 'threadId': threadId,
      };
}

/// Thay đổi trên các cuộc hội thoại (POST /threads/modify).
class MailChange {
  const MailChange({this.unread, this.starred, this.important, this.box, this.addLabels = const [], this.removeLabels = const []});
  final bool? unread, starred, important;
  final String? box;
  final List<String> addLabels, removeLabels;

  bool get leavesBox => box != null;

  Map<String, dynamic> toJson() => {
        if (unread != null) 'unread': unread,
        if (starred != null) 'starred': starred,
        if (important != null) 'important': important,
        if (box != null) 'box': box,
        if (addLabels.isNotEmpty) 'addLabels': addLabels,
        if (removeLabels.isNotEmpty) 'removeLabels': removeLabels,
      };

  void applyTo(MailThreadSummary t) {
    if (unread != null) t.unread = unread!;
    if (starred != null) t.starred = starred!;
    if (important != null) t.important = important!;
    if (box != null) t.box = box!;
    if (addLabels.isNotEmpty) t.labels = {...t.labels, ...addLabels}.toList();
    if (removeLabels.isNotEmpty) t.labels = t.labels.where((l) => !removeLabels.contains(l)).toList();
  }
}

/// Bộ lọc tìm kiếm ↔ chuỗi toán tử (from: to: subject: has:attachment is:unread label: in: newer_than:).
class MailQuery {
  MailQuery({this.from = '', this.to = '', this.subject = '', this.words = '', this.attachment = false, this.unread = false, this.within = '', this.inBox = ''});
  String from, to, subject, words, within, inBox;
  bool attachment, unread;

  static String _q(String s) => s.contains(' ') ? '"$s"' : s;

  String build() => [
        if (from.isNotEmpty) 'from:${_q(from)}',
        if (to.isNotEmpty) 'to:${_q(to)}',
        if (subject.isNotEmpty) 'subject:${_q(subject)}',
        if (words.isNotEmpty) words,
        if (within.isNotEmpty) 'newer_than:$within',
        if (inBox.isNotEmpty) inBox.startsWith('label:') ? 'label:${_q(inBox.substring(6))}' : 'in:$inBox',
        if (attachment) 'has:attachment',
        if (unread) 'is:unread',
      ].join(' ');

  factory MailQuery.parse(String q) {
    final r = MailQuery();
    final words = <String>[];
    for (final m in RegExp(r'(\w+:"[^"]*"|\w+:\S+|"[^"]*"|\S+)').allMatches(q)) {
      final tok = m.group(0)!;
      final i = tok.indexOf(':');
      final k = i > 0 ? tok.substring(0, i).toLowerCase() : '';
      final v = (i > 0 ? tok.substring(i + 1) : tok).replaceAll(RegExp(r'^"|"$'), '');
      switch (k) {
        case 'from':
          r.from = v;
        case 'to':
          r.to = v;
        case 'subject':
          r.subject = v;
        case 'has' when v == 'attachment':
          r.attachment = true;
        case 'is' when v == 'unread':
          r.unread = true;
        case 'newer_than':
          r.within = v;
        case 'in':
          r.inBox = v;
        case 'label':
          r.inBox = 'label:$v';
        default:
          words.add(tok);
      }
    }
    r.words = words.join(' ');
    return r;
  }
}
