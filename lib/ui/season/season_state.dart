import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart' show serverKey, kServerUrl, kUserAgent;
import '../../state/app_state.dart';
import '../bubble_styles.dart' show BubbleChoice, bubbleSeasonPick;
import 'season.dart';
import 'season_art.dart';

/// App Giao diện (Flygo ID): màn hình native "appearance" (mặc định của mình) + "appearance-admin" (Quản trị).
const kAppearanceApp = 'vn.flygo.appearance';

/// Các phần của giao diện mùa lễ (khớp `features` của máy chủ appearance).
const kSeasonFeatures = ['wallpaper', 'lights', 'hats', 'effect', 'banner'];

/// Trạng thái giao diện mùa lễ + hình nền chat:
/// - cài đặt của công ty: GET `<app>/api/seasons` (vé Flygo ID của [kAppearanceApp]); người không được dùng app thì không có gì;
/// - lựa chọn riêng của mình: preferences `flygo_season/me` (JSON) và `flygo_wallpaper/<id kênh | _default>`;
/// - "không đội mũ cho ảnh của mình": user props `flygo_no_hat` (người khác cần thấy).
class SeasonState extends ChangeNotifier {
  SeasonState._();
  static final instance = SeasonState._();

  static const kSeasonPref = 'flygo_season';
  static const kWallpaperPref = 'flygo_wallpaper';
  static const kDefaultKey = '_default';

  /// App Giao diện của người dùng (null = không được dùng → không có mùa lễ, không có hình nền).
  MiniApp? app;
  /// Phản hồi GET /api/seasons gần nhất ({cfg, version, windows, can_admin, ...}).
  Map<String, dynamic>? org;
  /// Lựa chọn riêng (flygo_season/me).
  Map<String, dynamic> mine = {};
  /// id kênh / _default → mã hình nền.
  Map<String, String> wallpapers = {};

  AppState? _app;
  Timer? _timer;
  /// Đồng hồ (kiểm thử đặt ngày giả).
  DateTime Function() clock = DateTime.now;

  /// Có dữ liệu mùa lễ của công ty (máy chủ có dịch vụ Giao diện). Nhân viên đọc bằng vé Gateway, không cần quyền dùng app.
  bool get available => org != null;
  bool get canAdmin => org?['can_admin'] == true;

  /// "Xem thử" của quản trị viên: hiện mùa này trên các máy của mình, bất kể ngày và công ty đã bật hay chưa.
  String? get preview => canAdmin && mine['preview'] is String ? mine['preview'] as String : null;

  // ---------------------------------------------------------------- tải
  Future<void> load(AppState state) async {
    _app = state;
    // Lớp "mùa lễ" trong thứ tự bong bóng: chat riêng → mặc định của mình → mùa lễ → thường (AppState.resolveBubble).
    state.seasonBubble = (_) => seasonBubble(state.me?.id ?? '');
    await _restoreCache();
    final raw = await state.loadPrefCategory(kSeasonPref);
    mine = _decode(raw['me']);
    wallpapers = Map.of(await state.loadPrefCategory(kWallpaperPref));
    notifyListeners();
    await refresh();
    _timer?.cancel();
    // Khung ngày tính ở máy (qua nửa đêm tự bật / tắt); tải lại cài đặt công ty vài giờ một lần.
    _timer = Timer.periodic(const Duration(hours: 3), (_) => refresh());
  }

  void clear() {
    _timer?.cancel();
    app = null;
    org = null;
    mine = {};
    wallpapers = {};
    notifyListeners();
  }

  /// Tải lại cài đặt của công ty.
  Future<void> refresh() async {
    final state = _app;
    if (state == null || state.token.isEmpty) return;
    try {
      final apps = await MiniApps.list(state.token).catchError((_) => const <MiniApp>[]);
      app = apps.where((a) => a.id == kAppearanceApp).firstOrNull;
      try {
        org = await api('GET', '/api/seasons');
        _saveCache();
      } on SeasonException catch (e) {
        // Máy chủ chưa có dịch vụ Giao diện / không cho đọc: không có mùa lễ.
        if (e.status == 404 || e.status == 401 || e.status == 403) org = null;
      }
      _changed();
    } catch (e) {
      debugPrint('season: $e');
    }
  }

  /// Gọi máy chủ Giao diện bằng vé Flygo ID.
  Future<Map<String, dynamic>> api(String method, String path, [Object? body]) async {
    final state = _app;
    if (state == null || kServerUrl.isEmpty) throw StateError('Giao diện chưa sẵn sàng');
    // Người được dùng app: vé của app (có quyền admin nếu được cấp). Còn lại: vé Gateway, chỉ đọc.
    final a = app;
    final base = a?.baseUrl ?? '${kServerUrl.replaceAll(RegExp(r'/+$'), '')}/__apps/appearance';
    final audience = a != null ? kAppearanceApp : 'vn.flygo.gateway';
    final id = await FlygoId.current(state.token);
    if (id == null) throw StateError('Máy chủ này chưa có Flygo ID');
    Future<http.Response> send(bool refresh) async {
      final req = http.Request(method, Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path'))
        ..headers.addAll({
          'Authorization': 'Bearer ${await id.ticket(audience, refresh: refresh).timeout(const Duration(seconds: 25))}',
          'User-Agent': kUserAgent,
          if (body != null) 'Content-Type': 'application/json',
        });
      if (body != null) req.body = jsonEncode(body);
      return http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
    }

    var res = await send(false);
    if (res.statusCode == 401) res = await send(true);
    Map<String, dynamic> j = const {};
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {}
    if (res.statusCode >= 400) throw SeasonException(res.statusCode, '${j['error'] ?? 'Giao diện trả lỗi ${res.statusCode}'}');
    return j;
  }

  /// Quản trị viên lưu cài đặt của công ty (kèm version đã đọc; lệch thì máy chủ trả 409).
  Future<void> saveOrg(Map<String, dynamic> cfg) async {
    final r = await api('PUT', '/api/seasons', {...cfg, 'version': org?['version'] ?? 0});
    org = r;
    _saveCache();
    _changed();
  }

  /// Báo thay đổi cho giao diện + AppState (bong bóng mùa lễ dùng khi gửi tin, tên kiểu ở thông tin chat).
  void _changed() {
    notifyListeners();
    _app?.notifyListeners();
  }

  Future<File> _cacheFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/season-${serverKey.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}.json');

  Future<void> _restoreCache() async {
    try {
      final f = await _cacheFile();
      if (f.existsSync()) org = Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {}
  }

  void _saveCache() async {
    try {
      await (await _cacheFile()).writeAsString(jsonEncode(org));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- mùa đang diễn ra
  Map<String, dynamic> get cfg => (org?['cfg'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Ngày hôm nay theo giờ Việt Nam (khung ngày của máy chủ tính theo giờ VN).
  static String _today(DateTime now) => now.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10);

  /// Mùa đang diễn ra (công ty đã bật và hôm nay nằm trong khung), null = không có.
  String? activeSeason([DateTime? now]) {
    if (!available) return null;
    final p = preview;
    if (p != null) return p;
    final today = _today(now ?? clock());
    for (final w in (org?['windows'] as List? ?? const [])) {
      if (w is! Map || w['enabled'] != true) continue;
      final s = '${w['start']}', e = '${w['end']}';
      if (s.compareTo(today) <= 0 && today.compareTo(e) <= 0) return '${w['id']}';
    }
    return null;
  }

  /// Khung ngày của một mùa (năm nay / năm sau).
  ({String start, String end})? windowOf(String id) {
    for (final w in (org?['windows'] as List? ?? const [])) {
      if (w is Map && w['id'] == id) return (start: '${w['start']}', end: '${w['end']}');
    }
    return null;
  }

  /// Phần [feature] của mùa đang diễn ra có bật không: công ty bật sẵn + mình không tắt.
  bool on(String feature, [DateTime? now]) {
    final s = activeSeason(now);
    if (s == null || mine['off'] == true) return false;
    if (((cfg['seasons'] as Map?)?[s] as Map?)?['features']?[feature] == false) return false;
    return mine[feature] != false;
  }

  /// "Hiệu ứng động": tuyết rơi, đèn nhấp nháy (không tính hiệu ứng một lần khi có lời chúc).
  bool get motion => mine['motion'] != false;

  /// Mũ Noel cho ảnh đại diện của [user]: chỉ tháng 12, mình bật xem mũ, chủ ảnh không tắt.
  bool hatFor(Map<String, dynamic>? userRaw, double size) {
    if (size < 20 || userRaw == null || userRaw['is_bot'] == true) return false;
    if (activeSeason() != 'giangsinh' || (clock().month != 12 && preview == null) || !on('hats')) return false;
    return (userRaw['props'] as Map?)?['flygo_no_hat'] != 'true';
  }

  // ---------------------------------------------------------------- lựa chọn riêng
  Map<String, dynamic> _decode(String? v) {
    try {
      return v == null || v.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(v) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> setMine(String key, Object? value) async {
    final state = _app;
    if (state?.me == null) return;
    mine = {...mine, key: value};
    if (value == null) mine.remove(key);
    _changed();
    await state!.api.put('/users/${state.me!.id}/preferences', [
      {'user_id': state.me!.id, 'category': kSeasonPref, 'name': 'me', 'value': jsonEncode(mine)}
    ]);
  }

  /// Ảnh của mình có đội mũ không (user props, mọi người thấy).
  bool get myHat => (_app?.me?.raw['props'] as Map?)?['flygo_no_hat'] != 'true';

  Future<void> setMyHat(bool on) async {
    final state = _app;
    if (state?.me == null) return;
    final props = {...?(state!.me!.raw['props'] as Map?)?.cast<String, dynamic>(), 'flygo_no_hat': on ? 'false' : 'true'};
    final r = await state.api.put('/users/me/patch', {'props': props});
    if (r is Map) state.me!.raw['props'] = r['props'] ?? props;
    notifyListeners();
  }

  // ---------------------------------------------------------------- hình nền
  /// Lựa chọn riêng của chat (null = theo mặc định).
  String? wallpaperOf(String channelId) => wallpapers[channelId];
  String? get wallpaperDefault => wallpapers[kDefaultKey];

  /// Hình nền thật dùng cho [channelId]: riêng của chat → mặc định của mình → mùa lễ đang diễn ra (hình nền mùa do quản trị
  /// chọn) → mặc định của công ty. Trả về null = nền chat thường.
  WallpaperChoice? resolveWallpaper(String channelId, bool dark) {
    if (!available) return null;
    final key = wallpapers.containsKey(channelId) ? channelId : kDefaultKey;
    final id = wallpapers[channelId] ?? wallpapers[kDefaultKey] ?? 'season';
    if (id == 'season') return _seasonWallpaper(dark);
    return _choice(id, key);
  }

  WallpaperChoice? _seasonWallpaper(bool dark) {
    final s = activeSeason();
    if (s != null && on('wallpaper')) {
      final w = '${((cfg['seasons'] as Map?)?[s] as Map?)?['wallpaper'] ?? 'auto'}';
      // Hiện chỉ Giáng sinh có hình nền riêng.
      if (w == 'off') return null;
      // Mã cũ (auto / demnoel / tuyettrang) và mã mùa đều ra hình nền của mùa đó; mùa chưa có hình riêng thì thôi.
      final art = wallpaperById(w) ?? wallpaperById(s);
      return art == null ? null : WallpaperChoice(art);
    }
    final d = (cfg['defaults'] as Map?)?['wallpaper'] as String?;
    return d == null || d == 'season' ? null : _choice(d, kDefaultKey);
  }

  WallpaperChoice? _choice(String id, String key) {
    if (id == 'none') return null;
    if (id.startsWith('plain:')) {
      final c = int.tryParse(id.substring(6), radix: 16);
      return c == null ? null : WallpaperChoice.plain(Color(0xFF000000 | c));
    }
    if (id == 'photo') return WallpaperChoice.photo(key);
    final w = wallpaperById(id);
    return w == null ? null : WallpaperChoice(w);
  }

  /// Bong bóng mùa lễ của [userId] (lớp "mùa lễ" trong AppState.resolveBubble): null nếu không có mùa / mình tắt mùa lễ /
  /// quản trị tắt bong bóng mùa.
  BubbleChoice? seasonBubble(String userId) {
    final s = activeSeason();
    if (s == null || mine['off'] == true || userId.isEmpty) return null;
    final b = ((cfg['seasons'] as Map?)?[s] as Map?)?['bubble'] as Map?;
    final mode = b?['mode'] ?? 'random';
    if (mode == 'off') return null;
    return bubbleSeasonPick(s, userId, style: mode == 'one' ? b!['style'] as String? : null);
  }

  /// "Áp dụng cho mọi chat": bỏ hình nền riêng của mọi chat (giữ mặc định của mình).
  Future<void> clearChatWallpapers() async {
    final state = _app;
    if (state?.me == null) return;
    final keys = [for (final k in wallpapers.keys) if (k != kDefaultKey) k];
    if (keys.isEmpty) return;
    for (final k in keys) {
      wallpapers.remove(k);
    }
    notifyListeners();
    await state!.api.post('/users/${state.me!.id}/preferences/delete', [
      for (final k in keys) {'user_id': state.me!.id, 'category': kWallpaperPref, 'name': k, 'value': ''}
    ]);
  }

  /// Lưu hình nền của một chat (hoặc [kDefaultKey]); null = "Dùng mặc định" (xoá lựa chọn riêng).
  Future<void> setWallpaper(String key, String? id) async {
    final state = _app;
    if (state?.me == null) return;
    final pref = {'user_id': state!.me!.id, 'category': kWallpaperPref, 'name': key};
    if (id == null) {
      wallpapers.remove(key);
      notifyListeners();
      await state.api.post('/users/${state.me!.id}/preferences/delete', [
        {...pref, 'value': ''}
      ]);
    } else {
      wallpapers[key] = id;
      notifyListeners();
      await state.api.put('/users/${state.me!.id}/preferences', [
        {...pref, 'value': id}
      ]);
    }
  }

  /// Ảnh nền tự chọn (lưu trên máy này): `<support>/wallpaper-<server>-<key>.img`
  static Future<File> photoFile(String key) async => File(
      '${(await getApplicationSupportDirectory()).path}/wallpaper-${serverKey.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')}-${key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}.img');

  // ---------------------------------------------------------------- đồng bộ từ máy khác
  /// preferences_changed / preferences_deleted của mình (AppState chuyển sang).
  void onPref(Map p, {required bool deleted}) {
    final name = p['name'];
    if (name is! String) return;
    if (p['category'] == kWallpaperPref) {
      deleted ? wallpapers.remove(name) : wallpapers[name] = '${p['value']}';
      notifyListeners();
    } else if (p['category'] == kSeasonPref && name == 'me') {
      mine = deleted ? {} : _decode('${p['value']}');
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- hiệu ứng lời chúc
  /// Hiệu ứng cho tin [text] (null = không có): theo chế độ của công ty (trộn / theo từ khoá).
  BurstKind? effectFor(String text) {
    if (!on('effect')) return null;
    final eff = (cfg['effect'] as Map?) ?? const {};
    final kws = [for (final k in (eff['keywords'] as List? ?? const [])) if (k is Map && '${k['k']}'.trim().isNotEmpty) k];
    final low = _fold(text);
    Map? hit;
    for (final k in kws) {
      if (_wordMatch(low, _fold('${k['k']}'))) {
        hit = k;
        break;
      }
    }
    if (hit == null && !(kws.isEmpty && isXmasGreeting(text))) return null;
    if (eff['mode'] != 'keyword' || hit == null) return BurstKind.mix;
    return switch (hit['fx']) { 'snow' => BurstKind.snow, 'gifts' => BurstKind.gifts, _ => BurstKind.mix };
  }

  /// Bỏ dấu + chữ thường (để "giang sinh vui ve" khớp "Giáng sinh vui vẻ").
  static String _fold(String s) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to[i]);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _wordMatch(String text, String kw) {
    if (kw.isEmpty) return false;
    return RegExp('(^|[^a-z0-9])${RegExp.escape(kw)}(\$|[^a-z0-9])').hasMatch(text);
  }
}

class SeasonException implements Exception {
  SeasonException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Hình nền đã chọn: hình vẽ sẵn, màu trơn hoặc ảnh trên máy.
class WallpaperChoice {
  final Wallpaper? art;
  final Color? color;
  final String? photoKey;
  const WallpaperChoice(Wallpaper this.art)
      : color = null,
        photoKey = null;
  const WallpaperChoice.plain(Color this.color)
      : art = null,
        photoKey = null;
  const WallpaperChoice.photo(String this.photoKey)
      : art = null,
        color = null;

}

/// Banner mùa lễ ở Trang chủ (hiện ở Giáng sinh, tới hết 25/12); bấm × thì ẩn tới năm sau.
class SeasonBanner extends StatelessWidget {
  const SeasonBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final s = SeasonState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final now = s.clock();
        if (s.activeSeason(now) != 'giangsinh' || !s.on('banner', now) || (now.month == 12 && now.day > 25)) return const SizedBox.shrink();
        if (s.mine['banner_hidden'] == now.year) return const SizedBox.shrink();
        return XmasBanner(now: now, onClose: () => s.setMine('banner_hidden', now.year));
      },
    );
  }
}
