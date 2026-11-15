// Wiki: bộ nhớ đệm trên máy (cây, các trang đã mở, bản nháp đang sửa) để mở nhanh và đọc được khi mất mạng.
// Ghi (lưu trang, phân quyền…) cần mạng: máy chủ kiểm quyền và phiên bản. Bản nháp giữ trên máy tới khi lưu được.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'model.dart';

class WikiStore extends ChangeNotifier {
  WikiStore(this.api, {this.cacheKey});

  final WikiApi api;
  /// Tên tệp bộ nhớ đệm (máy chủ + người dùng); null = chỉ trong bộ nhớ (kiểm thử).
  final String? cacheKey;

  final Map<String, WFolder> folders = {};
  final Map<String, WPageRef> pages = {};
  final Map<String, Map<String, dynamic>> _pageCache = {};
  /// Bản nháp theo id trang: {title, body, base, note, folder?}.
  final Map<String, Map<String, dynamic>> drafts = {};
  String rootName = 'Công ty';
  String? rootRole, home;
  bool admin = false, loaded = false, offline = false;
  int staffCount = 0;
  String? error;

  static const root = 'root', staff = 'staff';
  static final _rnd = Random.secure();
  static String newId() {
    const a = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    return List.generate(12, (_) => a[_rnd.nextInt(a.length)]).join();
  }

  /// Id của mình: chủ thư mục nhân viên của mình.
  String? get meId => home == null ? null : folders[home]?.owner;

  bool canIn(String folder, String role) => folder == root ? roleRank(rootRole) >= roleRank(role) : (folders[folder]?.can(role) ?? false);

  int _cmp(double sa, double sb, String a, String b) => sa != sb ? sa.compareTo(sb) : viCompare(a, b);

  /// Thư mục con: thư mục của mình đứng đầu trong "Nhân viên".
  List<WFolder> children(String folder) {
    final list = folders.values.where((f) => f.parent == folder).toList()..sort((a, b) => _cmp(a.sort, b.sort, a.name, b.name));
    if (folder == staff && home != null) {
      final i = list.indexWhere((f) => f.id == home);
      if (i > 0) list.insert(0, list.removeAt(i));
    }
    return list;
  }

  List<WPageRef> pagesIn(String folder) => pages.values.where((p) => p.folder == folder).toList()..sort((a, b) => _cmp(a.sort, b.sort, a.title, b.title));

  /// Đường dẫn từ gốc (không gồm gốc) tới thư mục.
  List<WFolder> pathOf(String folder) {
    final out = <WFolder>[];
    String? p = folder;
    var hops = 0;
    while (p != null && p != root && hops++ < 200) {
      final f = folders[p];
      if (f == null) break;
      out.insert(0, f);
      p = f.parent;
    }
    return out;
  }

  String folderName(String id) => id == root ? rootName : folders[id]?.name ?? '';

  List<WPageRef> get recent => [...pages.values]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  // ------------------------------------------------------------ nạp
  Future<File?> _file() async {
    if (cacheKey == null) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}wiki_$cacheKey.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        if (j['tree'] is Map) _applyTree(Map<String, dynamic>.from(j['tree'] as Map));
        for (final e in (j['pages'] as Map? ?? const {}).entries) {
          _pageCache['${e.key}'] = Map<String, dynamic>.from(e.value as Map);
        }
        for (final e in (j['drafts'] as Map? ?? const {}).entries) {
          drafts['${e.key}'] = Map<String, dynamic>.from(e.value as Map);
        }
        loaded = folders.isNotEmpty;
        notifyListeners();
      }
    } catch (_) {}
    await refresh();
  }

  Map<String, dynamic>? _tree;
  void _applyTree(Map<String, dynamic> t) {
    _tree = t;
    folders
      ..clear()
      ..addEntries([for (final f in (t['folders'] as List? ?? const [])) MapEntry('${f['id']}', WFolder(Map<String, dynamic>.from(f as Map)))]);
    pages
      ..clear()
      ..addEntries([for (final p in (t['pages'] as List? ?? const [])) MapEntry('${p['id']}', WPageRef(Map<String, dynamic>.from(p as Map)))]);
    final r = Map<String, dynamic>.from(t['root'] as Map? ?? const {});
    rootName = '${r['name'] ?? 'Công ty'}';
    rootRole = r['role'] as String?;
    home = t['home'] as String?;
    admin = t['admin'] == true;
    staffCount = (t['staff_count'] as num?)?.toInt() ?? 0;
  }

  Future<void> refresh() async {
    try {
      _applyTree(await api.get('/api/tree'));
      loaded = true;
      offline = false;
      error = null;
      _persist();
    } catch (e) {
      offline = WikiApi.isOffline(e);
      error = '$e';
    }
    notifyListeners();
  }

  Timer? _saveTimer;
  void _persist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final f = await _file();
        if (f == null) return;
        // Giữ 100 trang mở gần nhất.
        while (_pageCache.length > 100) {
          _pageCache.remove(_pageCache.keys.first);
        }
        await f.writeAsString(jsonEncode({'tree': _tree, 'pages': _pageCache, 'drafts': drafts}));
      } catch (_) {}
    });
  }

  // ------------------------------------------------------------ trang
  WPage? cached(String id) => _pageCache[id] == null ? null : WPage(_pageCache[id]!);

  Future<WPage> page(String id, {int? version}) async {
    try {
      final p = WPage(Map<String, dynamic>.from((await api.get('/api/pages/$id${version != null ? '?version=$version' : ''}'))['page'] as Map));
      if (version == null) {
        _pageCache.remove(id);
        _pageCache[id] = p.m;
        _persist();
      }
      return p;
    } catch (e) {
      final c = cached(id);
      if (version == null && c != null && WikiApi.isOffline(e)) {
        offline = true;
        notifyListeners();
        return c;
      }
      rethrow;
    }
  }

  void _gotPage(WPage p) {
    _pageCache.remove(p.id);
    _pageCache[p.id] = p.m;
    pages[p.id] = WPageRef({'id': p.id, 'folder': p.folder, 'title': p.title, 'version': p.version, 'updated_at': p.updatedAt, 'updated_by_name': p.updatedByName, 'sort': pages[p.id]?.sort ?? 0});
    _persist();
    notifyListeners();
  }

  /// Lưu trang. Máy chủ trả 409 (WikiException, body['current']) khi đã có bản mới hơn [base].
  Future<WPage> savePage(String id, {String? folder, String? title, String? body, int? base, String note = '', bool force = false}) async {
    final r = await api.put('/api/pages/$id', {
      'folder': ?folder,
      'title': ?title,
      'body': ?body,
      'base': ?base,
      if (note.isNotEmpty) 'note': note,
      if (force) 'force': true,
    });
    final p = WPage(Map<String, dynamic>.from(r['page'] as Map));
    drafts.remove(id);
    _gotPage(p);
    return p;
  }

  Future<String> createPage(String folder, String title) async {
    final id = newId();
    await savePage(id, folder: folder, title: title, body: '');
    return id;
  }

  Future<void> movePage(String id, String folder) async {
    _gotPage(WPage(Map<String, dynamic>.from((await api.post('/api/pages/$id/move', {'folder': folder}))['page'] as Map)));
  }

  Future<void> deletePage(String id) async {
    await api.delete('/api/pages/$id');
    pages.remove(id);
    _pageCache.remove(id);
    _persist();
    notifyListeners();
  }

  Future<List<WVersion>> history(String id) async =>
      [for (final v in (await api.get('/api/pages/$id/history'))['versions'] as List) WVersion(Map<String, dynamic>.from(v as Map))];

  Future<WPage> restoreVersion(String id, int version) async {
    final p = WPage(Map<String, dynamic>.from((await api.post('/api/pages/$id/restore', {'version': version}))['page'] as Map));
    _gotPage(p);
    return p;
  }

  void saveDraft(String id, Map<String, dynamic> d) {
    drafts[id] = d;
    _persist();
  }

  void dropDraft(String id) {
    if (drafts.remove(id) != null) _persist();
  }

  // ------------------------------------------------------------ thư mục, quyền
  Future<String> createFolder(String parent, String name) async {
    final id = newId();
    await api.put('/api/folders/$id', {'parent': parent, 'name': name});
    await refresh();
    return id;
  }

  Future<void> renameFolder(String id, String name) async {
    await api.put('/api/folders/$id', {'name': name});
    await refresh();
  }

  Future<void> moveFolder(String id, String parent) async {
    await api.post('/api/folders/$id/move', {'parent': parent});
    await refresh();
  }

  Future<void> deleteFolder(String id) async {
    await api.delete('/api/folders/$id');
    await refresh();
  }

  Future<Map<String, dynamic>> acl(String folder) => api.get('/api/folders/$folder/acl');

  Future<Map<String, dynamic>> setAcl(String folder, bool inherit, List<Map<String, dynamic>> entries) async {
    final r = await api.put('/api/folders/$folder/acl', {'inherit': inherit, 'entries': entries});
    await refresh();
    return r;
  }

  Future<List<Map<String, dynamic>>> subjects(String q) async =>
      [for (final s in (await api.get('/api/subjects?q=${Uri.encodeQueryComponent(q)}'))['subjects'] as List) Map<String, dynamic>.from(s as Map)];

  // ------------------------------------------------------------ tìm kiếm, thùng rác, quản trị, tệp
  Future<List<Map<String, dynamic>>> search(String q, {String? folder}) async => [
        for (final r in (await api.get('/api/search?q=${Uri.encodeQueryComponent(q)}${folder != null ? '&folder=$folder' : ''}'))['results'] as List)
          Map<String, dynamic>.from(r as Map)
      ];

  Future<List<Map<String, dynamic>>> trash() async => [for (final x in (await api.get('/api/trash'))['items'] as List) Map<String, dynamic>.from(x as Map)];

  Future<void> restoreTrash(String type, String id) async {
    await api.post('/api/trash/restore', {'type': type, 'id': id});
    await refresh();
  }

  Future<Map<String, dynamic>> syncStaff() async {
    final r = await api.post('/api/admin/sync-staff');
    await refresh();
    return r;
  }

  Future<WFile> upload(String name, Uint8List bytes) async => WFile(await api.upload(name, bytes));

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
