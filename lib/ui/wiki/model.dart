// Wiki: dữ liệu trong app (thư mục, trang, phiên bản, quyền). Khớp JSON của backend (wiki/README.md).
import '../../i18n/i18n.dart';

const _viFrom = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _viTo = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Chữ thường bỏ dấu tiếng Việt (để sắp xếp và lọc: "Kế toán" đứng trước "Kinh doanh").
String viFold(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r), i = _viFrom.indexOf(c);
    b.write(i >= 0 ? _viTo[i] : c);
  }
  return b.toString();
}

/// So sánh tên theo kiểu tiếng Việt: bỏ dấu trước, cùng chữ thì so cả dấu.
int viCompare(String a, String b) {
  final c = viFold(a).compareTo(viFold(b));
  return c != 0 ? c : a.compareTo(b);
}

/// Mức quyền: view < edit < manage. null = không có quyền (thư mục chỉ hiện tên để cây liền mạch).
int roleRank(String? r) => const {'view': 1, 'edit': 2, 'manage': 3}[r] ?? 0;
String roleLabel(String? r) => switch (r) { 'manage' => tr('Quản lý'), 'edit' => tr('Sửa'), 'view' => tr('Xem'), _ => tr('Không có quyền') };

class WFolder {
  WFolder(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id']}';
  String? get parent => m['parent'] as String?;
  String get name => '${m['name'] ?? ''}';
  /// root | staff_root | staff_home | normal
  String get kind => '${m['kind'] ?? 'normal'}';
  String? get owner => m['owner'] as String?;
  String? get role => m['role'] as String?;
  bool get closed => m['closed'] == true;
  bool get left => m['left'] == true;
  double get sort => (m['sort'] as num?)?.toDouble() ?? 0;
  bool get fixed => kind != 'normal';
  bool can(String r) => roleRank(role) >= roleRank(r);
}

class WPageRef {
  WPageRef(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id']}';
  String get folder => '${m['folder']}';
  String get title => '${m['title'] ?? ''}';
  int get version => (m['version'] as num?)?.toInt() ?? 1;
  int get updatedAt => (m['updated_at'] as num?)?.toInt() ?? 0;
  String get updatedByName => '${m['updated_by_name'] ?? ''}';
  double get sort => (m['sort'] as num?)?.toDouble() ?? 0;
}

class WFile {
  WFile(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id']}';
  String get name => '${m['name'] ?? ''}';
  String get mime => '${m['mime'] ?? ''}';
  int get size => (m['size'] as num?)?.toInt() ?? 0;
  bool get isImage => mime.startsWith('image/');
}

/// Trang đầy đủ (GET /api/pages/:id).
class WPage {
  WPage(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id']}';
  String get folder => '${m['folder']}';
  String get title => '${m['title'] ?? ''}';
  String get body => '${m['body'] ?? ''}';
  int get version => (m['version'] as num?)?.toInt() ?? 1;
  int get latest => (m['latest'] as num?)?.toInt() ?? version;
  String get updatedByName => '${m['updated_by_name'] ?? ''}';
  String get updatedBy => '${m['updated_by'] ?? ''}';
  int get updatedAt => (m['updated_at'] as num?)?.toInt() ?? 0;
  bool get viaAgent => m['updated_via'] == 'mcp';
  String? get role => m['role'] as String?;
  bool can(String r) => roleRank(role) >= roleRank(r);
  List<({String id, String name})> get path => [for (final x in (m['path'] as List? ?? const [])) (id: '${x['id']}', name: '${x['name']}')];
  List<WFile> get files => [for (final x in (m['files'] as List? ?? const [])) WFile(Map<String, dynamic>.from(x as Map))];
  List<Map<String, dynamic>> get access => [for (final x in (m['access'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

  /// Tóm tắt quyền cho dòng thông tin: "Mọi người xem · Hành chính sửa".
  String get accessSummary {
    final list = [...access]..sort((a, b) => roleRank('${b['role']}') - roleRank('${a['role']}'));
    final parts = [for (final a in list.take(3)) '${a['name']} ${roleLabel('${a['role']}').toLowerCase()}'];
    if (list.length > 3) parts.add(tr('+{0}', ['${list.length - 3}']));
    return parts.join(' · ');
  }
}

/// Một phiên bản trong lịch sử.
class WVersion {
  WVersion(this.m);
  final Map<String, dynamic> m;
  int get version => (m['version'] as num).toInt();
  String get title => '${m['title'] ?? ''}';
  String get authorName => '${m['author_name'] ?? ''}';
  String get note => '${m['note'] ?? ''}';
  bool get viaAgent => m['via'] == 'mcp';
  int get at => (m['at'] as num?)?.toInt() ?? 0;
}

/// Thời gian tương đối ngắn: "vừa xong", "5 phút trước", "2 giờ trước", "hôm qua", "12/11".
String agoLabel(int ms, {DateTime? now}) {
  if (ms <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(ms), n = now ?? DateTime.now(), d = n.difference(t);
  if (d.inMinutes < 1) return tr('vừa xong');
  if (d.inHours < 1) return tr('{0} phút trước', ['${d.inMinutes}']);
  if (d.inDays < 1 && t.day == n.day) return tr('{0} giờ trước', ['${d.inHours}']);
  if (d.inDays < 2) return tr('hôm qua');
  String two(int x) => x.toString().padLeft(2, '0');
  return t.year == n.year ? '${two(t.day)}/${two(t.month)}' : '${two(t.day)}/${two(t.month)}/${t.year}';
}

/// Ngày giờ đầy đủ ngắn: "hôm nay 09:12", "12/11 16:40".
String whenLabel(int ms, {DateTime? now}) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms), n = now ?? DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  if (t.year == n.year && t.month == n.month && t.day == n.day) return tr('hôm nay {0}', [hm]);
  return '${two(t.day)}/${two(t.month)}${t.year == n.year ? '' : '/${t.year}'} $hm';
}

/// So sánh theo dòng (LCS) để xem khác biệt giữa hai bản: (loại, dòng) với loại ' ' giữ, '-' bỏ, '+' thêm.
List<(String, String)> lineDiff(String a, String b) {
  final x = a.split('\n'), y = b.split('\n');
  // Bỏ phần đầu / cuối giống nhau để bảng LCS nhỏ.
  var p = 0;
  while (p < x.length && p < y.length && x[p] == y[p]) {
    p++;
  }
  var s = 0;
  while (s < x.length - p && s < y.length - p && x[x.length - 1 - s] == y[y.length - 1 - s]) {
    s++;
  }
  final xs = x.sublist(p, x.length - s), ys = y.sublist(p, y.length - s);
  final out = <(String, String)>[for (final l in x.take(p)) (' ', l)];
  if (xs.length * ys.length > 4000000) {
    out.addAll([for (final l in xs) ('-', l), for (final l in ys) ('+', l)]);
  } else {
    final t = List.generate(xs.length + 1, (_) => List.filled(ys.length + 1, 0));
    for (var i = xs.length - 1; i >= 0; i--) {
      for (var j = ys.length - 1; j >= 0; j--) {
        t[i][j] = xs[i] == ys[j] ? t[i + 1][j + 1] + 1 : (t[i + 1][j] > t[i][j + 1] ? t[i + 1][j] : t[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < xs.length || j < ys.length) {
      if (i < xs.length && j < ys.length && xs[i] == ys[j]) {
        out.add((' ', xs[i]));
        i++;
        j++;
      } else if (j < ys.length && (i >= xs.length || t[i][j + 1] > t[i + 1][j])) {
        out.add(('+', ys[j++]));
      } else {
        out.add(('-', xs[i++]));
      }
    }
  }
  out.addAll([for (final l in x.sublist(x.length - s)) (' ', l)]);
  return out;
}
