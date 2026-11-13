// Bảng tin chạy nền (Sếp): tab Bảng tin hiện ngay khi đăng nhập (nhớ "máy chủ có Bảng tin" theo từng máy chủ), tự
// kiểm tra tin mới khi mở / quay lại app và mỗi 3 phút, tải sẵn trang đầu (kèm ảnh) và lưu xuống máy để bấm vào tab là
// hiện ngay, rồi mới làm mới. Số trên tab = bài mới kể từ lần xem bảng tin gần nhất + bài cần xác nhận chưa xác nhận.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart';
import 'api.dart';

class BangTinService extends ChangeNotifier with WidgetsBindingObserver {
  BangTinService._();
  static final instance = BangTinService._();

  static const _poll = Duration(minutes: 3);

  String? _server, _token;
  BangTinApi? api;
  String title = 'Bảng tin';
  bool hasApp = false;

  /// Bản đã tải gần nhất (cache): người dùng, bài ghim, bài, trang tiếp.
  Map<String, dynamic>? me;
  List<Map<String, dynamic>> pinned = const [], posts = const [];
  int? next;
  int lastSeen = 0;
  int badge = 0;
  Timer? _timer;
  bool _observing = false, _refreshing = false;

  /// Gọi khi vào màn hình chính (đã đăng nhập) và khi đổi máy chủ. Gọi lại nhiều lần không sao.
  Future<void> start(String token) async {
    final server = kServerUrl;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (_server != server || _token != token) {
      // Máy chủ khác: trạng thái riêng của máy chủ đó (cache trên máy), không lẫn với máy chủ cũ.
      _server = server;
      _token = token;
      api = null;
      me = null;
      pinned = posts = const [];
      next = null;
      badge = 0;
      hasApp = false;
      await _restore();
      notifyListeners();
    }
    await _connect();
    _timer?.cancel();
    _timer = Timer.periodic(_poll, (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  /// Tìm app Bảng tin của máy chủ (danh sách mini app đã lưu trước, rồi hỏi lại) và vé Flygo ID.
  Future<void> _connect() async {
    final token = _token, server = _server;
    if (token == null) return;
    try {
      await MiniApps.restore();
      var app = MiniApps.cached.where((a) => a.id == kBangTinApp).firstOrNull;
      if (app != null && !hasApp) {
        hasApp = true;
        notifyListeners();
      }
      final fresh = await MiniApps.list(token).timeout(const Duration(seconds: 25));
      if (server != _server) return;
      app = fresh.where((a) => a.id == kBangTinApp).firstOrNull;
      if (app == null) {
        // Máy chủ không có (hoặc không còn) Bảng tin: ẩn tab.
        if (hasApp) {
          hasApp = false;
          api = null;
          notifyListeners();
          await _save();
        }
        return;
      }
      title = app.name;
      final id = await FlygoId.current(token).timeout(const Duration(seconds: 25));
      if (id == null || server != _server) return;
      api = BangTinApi(base: app.baseUrl, id: id);
      hasApp = true;
      notifyListeners();
      await refresh();
    } catch (_) {
      // Mạng lỗi: giữ trạng thái đã lưu, lần sau (mở lại app / 3 phút) thử tiếp.
    }
  }

  /// Tải trang đầu, tính số tin mới, tải sẵn ảnh, lưu cache.
  Future<void> refresh() async {
    final a = api;
    if (a == null) {
      if (_token != null && !_refreshing) unawaited(_connect());
      return;
    }
    if (_refreshing) return;
    _refreshing = true;
    final server = _server;
    try {
      me ??= await a.get('/api/me');
      final j = await a.get('/api/posts?limit=20');
      if (server != _server) return;
      update(pinned: _maps(j['pinned']), posts: _maps(j['posts']), next: (j['next'] as num?)?.toInt());
      unawaited(_prefetchImages(a));
    } catch (_) {
    } finally {
      _refreshing = false;
    }
  }

  /// Màn hình Bảng tin tải được trang đầu mới: dùng làm cache luôn.
  void update({required List<Map<String, dynamic>> pinned, required List<Map<String, dynamic>> posts, int? next}) {
    this.pinned = pinned;
    this.posts = posts;
    this.next = next;
    _recount();
    notifyListeners();
    unawaited(_save());
  }

  /// Người dùng đang xem bảng tin: xoá số trên tab (bài cần xác nhận vẫn đếm tới khi xác nhận).
  void markSeen() {
    lastSeen = DateTime.now().millisecondsSinceEpoch;
    _recount();
    notifyListeners();
    unawaited(_save());
  }

  void _recount() {
    final myId = '${(me?['user'] as Map?)?['id'] ?? ''}';
    var n = 0;
    for (final p in [...pinned, ...posts]) {
      if ((p['author'] as Map?)?['id'] == myId) continue;
      final fresh = ((p['created_at'] as num?) ?? 0) > lastSeen;
      final mustRead = p['require_ack'] == true && p['acked'] != true;
      if (fresh || mustRead) n++;
    }
    badge = n;
  }

  /// Ảnh bìa / ảnh đầu của các bài trên cùng: tải sẵn vào bộ nhớ để mở tab là thấy ảnh ngay.
  Future<void> _prefetchImages(BangTinApi a) async {
    var count = 0;
    for (final p in [...pinned, ...posts]) {
      final ids = [for (final i in (p['images'] as List? ?? const [])) '$i'].take(4).toList();
      if (ids.isEmpty && p['cover'] != null) ids.add('${p['cover']}');
      for (final id in ids) {
        if (count++ >= 16) return;
        try {
          await a.bytes(id);
        } catch (_) {}
      }
    }
  }

  static List<Map<String, dynamic>> _maps(Object? v) => [for (final x in (v as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];

  Future<File?> _file() async {
    final s = _server;
    if (s == null) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}bang_tin_${sha1.convert(utf8.encode(s)).toString().substring(0, 12)}.json');
  }

  Future<void> _restore() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map;
      hasApp = j['has_app'] == true;
      title = '${j['title'] ?? title}';
      me = j['me'] is Map ? Map<String, dynamic>.from(j['me'] as Map) : null;
      pinned = _maps(j['pinned']);
      posts = _maps(j['posts']);
      next = (j['next'] as num?)?.toInt();
      lastSeen = (j['last_seen'] as num?)?.toInt() ?? 0;
      _recount();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      if (f == null) return;
      await f.writeAsString(jsonEncode({
        'has_app': hasApp,
        'title': title,
        'me': me,
        'pinned': pinned,
        'posts': posts,
        'next': next,
        'last_seen': lastSeen,
      }));
    } catch (_) {}
  }
}
