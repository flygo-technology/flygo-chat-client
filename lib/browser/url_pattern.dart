// Mẫu địa chỉ kiểu match pattern của Chrome: `<scheme>://<host>/<path>`.
//   scheme: http, https, wss, ws hoặc `*` (http + https)
//   host:   `*` (mọi host), `*.gdt.gov.vn` (miền đó và miền con), hoặc tên đúng
//   path:   có `*` (khớp mọi chuỗi); bỏ trống = `/*`
// Dùng cho danh sách trang được phép của trình duyệt (whitelist), space_origins, content_scripts.match.

class UrlPattern {
  UrlPattern._(this.source, this._schemes, this._host, this._subdomains, this._path);

  final String source;
  final Set<String>? _schemes; // null = http + https
  final String _host; // '' = mọi host
  final bool _subdomains;
  final RegExp _path;

  /// Trả về null nếu mẫu sai.
  static UrlPattern? tryParse(String raw) {
    final s = raw.trim();
    final m = RegExp(r'^(\*|https?|wss?)://([^/]+)(/.*)?$').firstMatch(s);
    if (m == null) return null;
    final scheme = m.group(1)!;
    var host = m.group(2)!.toLowerCase();
    final path = m.group(3) ?? '/*';
    if (host.contains(':') && !host.startsWith('[')) host = host.substring(0, host.indexOf(':'));
    var sub = false;
    if (host == '*') {
      host = '';
    } else if (host.startsWith('*.')) {
      host = host.substring(2);
      sub = true;
      if (host.isEmpty || host.contains('*')) return null;
    } else if (host.contains('*')) {
      return null;
    }
    final re = RegExp('^${path.split('*').map(RegExp.escape).join('.*')}\$');
    return UrlPattern._(s, scheme == '*' ? null : {scheme}, host, sub, re);
  }

  bool matches(Uri url) {
    final scheme = url.scheme.toLowerCase();
    if (_schemes == null ? !(scheme == 'http' || scheme == 'https') : !_schemes.contains(scheme)) return false;
    final host = url.host.toLowerCase();
    if (_host.isNotEmpty) {
      if (_subdomains) {
        if (host != _host && !host.endsWith('.$_host')) return false;
      } else if (host != _host) {
        return false;
      }
    }
    final path = url.path.isEmpty ? '/' : url.path;
    return _path.hasMatch(url.hasQuery ? '$path?${url.query}' : path) || _path.hasMatch(path);
  }

  /// Mẫu này có nằm gọn trong [outer] không (whitelist của space động phải nằm trong space_origins của extension).
  /// So theo scheme + host; đường dẫn của mẫu trong phải bắt đầu như đường dẫn của mẫu ngoài (đủ chặt cho whitelist).
  bool within(UrlPattern outer) {
    final mine = _schemes ?? {'http', 'https'};
    final theirs = outer._schemes ?? {'http', 'https'};
    if (!theirs.containsAll(mine)) return false;
    if (outer._host.isNotEmpty) {
      if (_host.isEmpty) return false;
      if (outer._subdomains) {
        if (_host != outer._host && !_host.endsWith('.${outer._host}')) return false;
      } else if (_subdomains || _host != outer._host) {
        return false;
      }
    }
    final outerPath = outer._path.pattern.substring(1, outer._path.pattern.length - 1);
    if (outerPath == '/.*') return true;
    final prefix = outerPath.split('.*').first;
    final innerPath = _path.pattern.substring(1, _path.pattern.length - 1);
    return innerPath.startsWith(prefix);
  }

  @override
  String toString() => source;
}

/// Một danh sách mẫu: khớp nếu khớp một mẫu bất kỳ. Danh sách rỗng không khớp gì.
class UrlPatternSet {
  UrlPatternSet(Iterable<String> patterns) : items = [for (final p in patterns) ?UrlPattern.tryParse(p)];
  final List<UrlPattern> items;

  bool matches(Uri url) => items.any((p) => p.matches(url));
  bool matchesString(String url) {
    final u = Uri.tryParse(url);
    return u != null && matches(u);
  }
}
