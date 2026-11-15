// Drive: ghim để dùng khi không có mạng. Tệp lưu trong thư mục dữ liệu của app; ghim thư mục là ghim cả cây.
// Có mạng thì đồng bộ lại theo etag (tệp đổi trên máy chủ thì tải lại). Bản 1: chỉ đọc khi offline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';

class OfflineEntry {
  OfflineEntry({required this.item, this.local, this.root = true});
  DriveItem item;
  /// Tệp trên máy (null với thư mục / chưa tải xong).
  String? local;
  /// Người dùng tự ghim (false: tệp con của thư mục được ghim).
  bool root;
  Map<String, Object?> toJson() => {'item': item.toJson(), 'local': local, 'root': root};
  factory OfflineEntry.fromJson(Map j) => OfflineEntry(item: DriveItem.fromJson(j['item'] as Map), local: j['local'] as String?, root: j['root'] != false);
}

class DriveOffline extends ChangeNotifier {
  DriveOffline._(this.api, this.key);
  static final _all = <String, DriveOffline>{};
  static DriveOffline of(DriveApi api, String key) => _all.putIfAbsent(key, () => DriveOffline._(api, key).._load());

  DriveApi api;
  final String key;
  /// Theo đường dẫn trên Drive.
  final entries = <String, OfflineEntry>{};
  final busy = <String>{};
  bool syncing = false;
  DateTime? lastSync;

  Future<Directory> get _dir async => Directory('${(await getApplicationSupportDirectory()).path}/drive/offline_$key');
  Future<File> get _index async => File('${(await _dir).path}/index.json');

  Future<void> _load() async {
    try {
      final f = await _index;
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        for (final e in (j['entries'] as List? ?? const [])) {
          final o = OfflineEntry.fromJson(e as Map);
          entries[o.item.path] = o;
        }
        lastSync = j['synced'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['synced'] as num).toInt());
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final f = await _index;
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'entries': [for (final e in entries.values) e.toJson()], 'synced': lastSync?.millisecondsSinceEpoch}));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Đã ghim (chính nó hoặc nằm trong thư mục được ghim).
  bool pinned(String path) => entries.containsKey(path) || entries.values.any((e) => e.root && e.item.dir && path.startsWith('${e.item.path}/'));
  bool pinnedRoot(String path) => entries[path]?.root ?? false;
  List<OfflineEntry> get roots => entries.values.where((e) => e.root).toList()..sort((a, b) => a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase()));

  /// Tệp trên máy nếu đã có bản offline còn khớp.
  File? localFile(DriveItem it) {
    final l = entries[it.path]?.local;
    if (l == null) return null;
    final f = File(l);
    return f.existsSync() ? f : null;
  }

  int get bytes => entries.values.fold(0, (s, e) => s + (e.local == null ? 0 : e.item.size));

  Future<void> pin(DriveItem it) async {
    entries[it.path] = OfflineEntry(item: it);
    await _save();
    notifyListeners();
    await _fetch(it);
  }

  Future<void> unpin(DriveItem it) async {
    final drop = entries.keys.where((p) => p == it.path || p.startsWith('${it.path}/')).toList();
    for (final p in drop) {
      final l = entries.remove(p)?.local;
      if (l != null) await File(l).delete().catchError((_) => File(l));
    }
    await _save();
    notifyListeners();
  }

  Future<void> clearAll() async {
    entries.clear();
    try {
      final d = await _dir;
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  Future<String> _localPath(DriveItem it) async => '${(await _dir).path}/files/${it.id}_${it.name.replaceAll(RegExp(r'[/\\:]'), '_')}';

  /// Tải (lại) một mục; thư mục thì duyệt cả cây.
  Future<void> _fetch(DriveItem it, {bool root = true}) async {
    if (it.dir) {
      entries[it.path] = OfflineEntry(item: it, root: root || (entries[it.path]?.root ?? false));
      final kids = await api.list(it.path);
      final seen = {for (final k in kids) k.path};
      // Mục con đã bị xoá / chuyển đi trên máy chủ: bỏ khỏi bản offline.
      for (final p in entries.keys.where((p) => parentOf(p) == it.path && !seen.contains(p) && !(entries[p]?.root ?? false)).toList()) {
        final l = entries.remove(p)?.local;
        if (l != null) await File(l).delete().catchError((_) => File(l));
      }
      for (final k in kids) {
        await _fetch(k, root: false);
      }
      await _save();
      return;
    }
    final old = entries[it.path];
    final have = old?.local != null && File(old!.local!).existsSync() && old.item.etag == it.etag && it.etag.isNotEmpty;
    if (have) {
      old.item = it;
      return;
    }
    busy.add(it.path);
    notifyListeners();
    try {
      final dest = File(await _localPath(it));
      await api.download(it.path, dest);
      if (old?.local != null && old!.local != dest.path) await File(old.local!).delete().catchError((_) => File(old.local!));
      entries[it.path] = OfflineEntry(item: it, local: dest.path, root: root || (old?.root ?? false));
      await _save();
    } finally {
      busy.remove(it.path);
      notifyListeners();
    }
  }

  /// Đồng bộ mọi mục đã ghim (gọi khi mở Drive / app trở lại).
  Future<void> sync() async {
    if (syncing || entries.isEmpty) return;
    syncing = true;
    notifyListeners();
    try {
      for (final e in roots) {
        try {
          final fresh = await api.info(path: e.item.path);
          await _fetch(fresh);
        } on DriveException catch (x) {
          // Không còn trên máy chủ: bỏ ghim.
          if (x.status == 404) await unpin(e.item);
        }
      }
      lastSync = DateTime.now();
      await _save();
    } catch (_) {
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
