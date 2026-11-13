// Ký số cho các phần khác của app: ô "Ký số" trên trang Bạn / menu tab mới, và nút "Mở bằng trình duyệt ký số" của
// Quy trình (qua MagicSignHooks).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart' show kServerUrl;

import '../browser/browser_page.dart';
import '../browser/flygo_id.dart';
import '../browser/runtime.dart';
import '../ui/app_route.dart';
import '../ui/flows/magic_sign_hooks.dart';
import '../ui/theme.dart' show toast;
import 'kyso_admin.dart';
import 'kyso_windows.dart';

class KysoApi {
  KysoApi._();

  /// Hiện ô Ký số: máy chủ chat có Flygo ID và người này được dùng ít nhất một space Ký số (hoặc bản build thử
  /// KYSO_POC). Không có Flygo ID thì ẩn; nút ký của Quy trình vẫn mở được trang Ký số (đăng nhập Google như cũ).
  static final available = ValueNotifier<bool>(kKysoPoc && kysoSupported);

  static FlygoId? _id;
  static List<BrowserSpace> _spaces = const [];
  static String? _checkedToken;
  static DateTime _checkedAt = DateTime(2000);

  /// Đổi mỗi khi danh sách công ty Ký số (space Flygo ID) đổi: trang chủ / trang Bạn vẽ lại các ô.
  static final spacesChanged = ValueNotifier<int>(0);

  /// Lỗi lần hỏi Flygo ID gần nhất (null = ổn); Trang chủ hiện để biết vì sao chưa có ô Ký số, kèm nút thử lại.
  static final lastError = ValueNotifier<String?>(null);

  /// Công ty Ký số người này được dùng (Flygo ID). Mỗi công ty là một ô riêng ở Trang chủ / trang Bạn.
  static List<BrowserSpace> get spaces => _spaces;

  /// Tên ngắn của công ty trên ô: bỏ "Ký số" và "CÔNG TY TNHH / TRÁCH NHIỆM HỮU HẠN".
  static String shortName(BrowserSpace s) {
    var n = s.space.name.replaceFirst(RegExp(r'^\s*Ký số\s*', caseSensitive: false), '');
    n = n.replaceFirst(RegExp(r'^\s*CÔNG TY\s+(TRÁCH NHIỆM HỮU HẠN|TNHH|CỔ PHẦN|CP)\s*', caseSensitive: false), '');
    return n.trim().isEmpty ? s.space.name : n.trim();
  }

  /// Màu ô của một công ty: màu Flygo ID gán cho space nếu có, không thì một màu riêng theo mã công ty (mỗi công ty
  /// một màu, cố định giữa các lần mở).
  static Color colorOf(BrowserSpace s) {
    final c = s.space.color;
    if (c != null) return Color(c <= 0xFFFFFF ? 0xFF000000 | c : c);
    const palette = [
      Color(0xFF7B61FF), Color(0xFF2F80ED), Color(0xFF0D9488), Color(0xFFE08A1E),
      Color(0xFFE53935), Color(0xFFD81B60), Color(0xFF43A047), Color(0xFF00897B),
      Color(0xFF5E35B1), Color(0xFFF4511E),
    ];
    final i = _spaces.indexWhere((x) => x.space.id == s.space.id);
    final key = i >= 0 ? i : s.space.id.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[key % palette.length];
  }

  /// Mở thẳng trình duyệt ký số của một công ty bằng vé Flygo ID (không đăng nhập).
  static Future<void> openSpace(BuildContext context, BrowserSpace s) => openSpaceWindow(context, s);

  /// Mở công ty [s]: máy tính mở cửa sổ trình duyệt riêng (nhiều tab, một cửa sổ mỗi công ty, bấm lại thì đưa cửa sổ
  /// đó lên trước); điện thoại đẩy trang trình duyệt lên. Phiên đổi từ vé Flygo ID, không đăng nhập.
  static Future<void> openSpaceWindow(BuildContext context, BrowserSpace s, {NavigatorState? navigator}) =>
      openKysoSpace(context, s, navigator: navigator);

  /// Mở trang quản trị Ký số (quyền tổng, cấp trong Flygo ID): native xin vé quản trị, đổi lấy phiên quản trị ở máy
  /// chủ ký số rồi mở `/admin#token=<phiên>` trong WebView của app, không đăng nhập lại. Vé không bao giờ vào JS;
  /// phiên chỉ nằm sau dấu # (không gửi lên máy chủ, không vào nhật ký).
  static Future<void> openAdmin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    var id = _id;
    if (id == null) {
      final token = _checkedToken;
      if (token != null) await refresh(token, force: true);
      id = _id;
    }
    if (id == null) {
      messenger.showSnackBar(toast(const Text('Máy chủ chat này chưa có Flygo ID.')));
      return;
    }
    try {
      final admin = (await id.myAdmin()).where((a) => a['app'] == kKysoExtensionId && a['url'] is String).firstOrNull;
      if (admin == null) {
        messenger.showSnackBar(toast(const Text('Bạn chưa được cấp quyền quản trị Ký số.')));
        return;
      }
      final page = Uri.parse(admin['url'] as String);
      final ticket = await id.ticket(kKysoExtensionId);
      final session = await adminSession(page.origin, ticket);
      final url = page.replace(fragment: 'token=$session').toString();
      if (!context.mounted) return;
      if (!kysoSupported) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      }
      await nav.push(AppPageRoute(builder: (_) => KysoAdminPage(url: url, title: '${admin['name'] ?? 'Quản trị Ký số'}')));
    } catch (e) {
      messenger.showSnackBar(toast(Text('Không mở được trang quản trị Ký số: $e')));
    }
  }

  /// Flygo ID của máy chủ chat (sau [refresh]); null nếu không có.
  static FlygoId? get flygoId => _id;

  /// Hỏi lại Flygo ID (sau đăng nhập, khi mở trang Bạn). Lỗi mạng: giữ trạng thái cũ, lần sau hỏi lại.
  /// Nhật ký chẩn đoán (máy tính): `<app support>`/kyso-refresh.log, giữ khoảng 200 dòng cuối.
  static Future<void> _log(String line) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    try {
      final f = File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}kyso-refresh.log');
      final old = f.existsSync() ? f.readAsLinesSync() : const <String>[];
      final keep = old.length > 200 ? old.sublist(old.length - 200) : old;
      f.writeAsStringSync([...keep, '${DateTime.now().toIso8601String()} pid=$pid $line'].join('\n'));
    } catch (_) {}
  }

  static Future<void> refresh(String chatToken, {bool force = false}) async {
    unawaited(_log('refresh supported=$kysoSupported token=${chatToken.isNotEmpty} force=$force checked=${_checkedToken == chatToken} age=${DateTime.now().difference(_checkedAt).inSeconds}s server=$kServerUrl'));
    if (!kysoSupported || chatToken.isEmpty) return;
    // Hỏi lại tối đa mỗi phút một lần (mở trang chủ / trang Bạn), để quyền mới cấp hiện ra không cần khởi động lại.
    if (_checkedToken == chatToken && (!force || DateTime.now().difference(_checkedAt) < const Duration(minutes: 1))) return;
    _checkedToken = chatToken;
    _checkedAt = DateTime.now();
    try {
      final id = await FlygoId.current(chatToken);
      unawaited(_log('flygo id=${id?.base}'));
      final all = id == null ? const <BrowserSpace>[] : await id.spaces();
      final spaces = all.where(_isKyso).toList();
      unawaited(_log('spaces all=${all.length} kyso=${spaces.length}'));
      _id = id;
      final changed = spaces.map((s) => s.space.id).join('|') != _spaces.map((s) => s.space.id).join('|');
      _spaces = spaces;
      available.value = kKysoPoc || spaces.isNotEmpty;
      lastError.value = id == null ? 'máy chủ chưa có Flygo ID' : null;
      if (changed) spacesChanged.value++;
    } catch (e) {
      _checkedToken = null;
      lastError.value = '$e';
      debugPrint('[kyso] refresh: $e');
      unawaited(_log('ERROR $e'));
    }
  }

  static bool _isKyso(BrowserSpace s) => s.extensionEnv.containsKey(kKysoExtensionId) || s.space.provider == kKysoExtensionId;

  /// Gắn vào Quy trình: nút ký số mở trình duyệt ký số trong app (máy hỗ trợ). Máy không hỗ trợ: Quy trình mở link
  /// như thường.
  static void register() {
    if (!kysoSupported) return;
    MagicSignHooks.openSignBrowser = openSignBrowser;
    MagicSignHooks.signTokens = signTokens;
  }

  /// Token người này được dùng (cho ô chọn token của trình sửa quy trình): space Ký số của Flygo ID, hoặc catalog
  /// của phiên đăng nhập cũ. Rỗng nếu chưa có gì.
  static Future<List<({String id, String name, String company})>> signTokens() async {
    if (!kysoSupported) return const [];
    if (_spaces.isNotEmpty) {
      return [
        for (final s in _spaces)
          (id: s.space.env['TOKEN'] ?? s.space.id, name: s.space.name, company: s.space.name.replaceFirst(RegExp(r'^Ký số\s*'), '')),
      ];
    }
    await KysoHost.instance.ensureStarted();
    return [
      for (final t in KysoHost.instance.tokens)
        (id: kysoTokenId(t), name: kysoTileName(t), company: '${t['companyName'] ?? ''}'),
    ];
  }

  /// Mở trình duyệt ký số của [token] (mã token, hoặc tên ô / tên công ty) tại [url].
  /// Không có quyền với token đó thì báo và không mở gì.
  static Future<void> openSignBrowser(BuildContext context, {required String token, required String url, String? server}) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (!kysoSupported) {
      messenger.showSnackBar(toast(const Text('Máy này chưa chạy được trình duyệt ký số trong Flygo.')));
      return;
    }
    // Có Flygo ID: tìm space của token, phiên đổi từ vé (không đăng nhập lại).
    if (_id != null && _spaces.isNotEmpty) {
      final hit = matchSpace(_spaces, token);
      if (hit == null) {
        messenger.showSnackBar(toast(Text('Bạn chưa được cấp quyền ký số $token')));
        return;
      }
      if (!kysoCanOpen(url)) {
        messenger.showSnackBar(toast(Text('Địa chỉ không hợp lệ: $url')));
        return;
      }
      if (!context.mounted) return;
      await openFlygoSpace(context, _id!, hit, url: url, navigator: nav);
      return;
    }
    final host = KysoHost.instance;
    await host.ensureStarted();
    if (!host.loggedIn) {
      // Chưa đăng nhập máy chủ ký số trên máy này: mở trang Ký số để đăng nhập trước.
      messenger.showSnackBar(toast(const Text('Hãy đăng nhập Ký số trước rồi bấm lại nút ký.')));
      await nav.push(AppPageRoute(builder: (_) => const KysoHomePage()));
      return;
    }
    final hit = match(host.tokens, token);
    if (hit == null) {
      messenger.showSnackBar(toast(Text('Bạn chưa được cấp quyền ký số $token')));
      return;
    }
    if (!context.mounted) return;
    await openKysoBrowser(context, hit, url: url, navigator: nav);
  }

  /// Space Ký số theo mã token (env TOKEN), mã space, tên ô hoặc tên công ty (không phân biệt hoa thường).
  @visibleForTesting
  static BrowserSpace? matchSpace(List<BrowserSpace> spaces, String key) {
    final k = key.trim().toLowerCase();
    if (k.isEmpty) return null;
    for (final s in spaces) {
      final id = s.space.id.toLowerCase();
      if ((s.space.env['TOKEN'] ?? '').toLowerCase() == k || id == k || id.endsWith('/$k')) return s;
    }
    for (final s in spaces) {
      final name = s.space.name.toLowerCase();
      if (name == k || name.replaceFirst(RegExp(r'^ký số\s*'), '') == k) return s;
    }
    return null;
  }

  /// Tìm token: theo mã trước, rồi theo tên ô ("Ký số …"), rồi theo tên công ty (không phân biệt hoa thường).
  @visibleForTesting
  static Map<String, dynamic>? match(List<Map<String, dynamic>> tokens, String key) {
    final k = key.trim().toLowerCase();
    if (k.isEmpty) return null;
    for (final t in tokens) {
      if (kysoTokenId(t).toLowerCase() == k) return t;
    }
    for (final t in tokens) {
      if (kysoTileName(t).toLowerCase() == k) return t;
    }
    for (final t in tokens) {
      if ('${t['companyName'] ?? ''}'.trim().toLowerCase() == k) return t;
    }
    return null;
  }
}
