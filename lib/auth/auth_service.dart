import '../i18n/i18n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../access/access_api.dart';
import '../config.dart';

bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Lưu token phiên đăng nhập. Điện thoại dùng kho bảo mật của hệ điều hành,
/// máy tính dùng file riêng trong thư mục dữ liệu của app.
class TokenStore {
  static String get _key => serverKey == 'main' ? 'mm_token' : 'mm_token_$serverKey';
  // iOS: đọc được cả khi máy đang khoá (sau lần mở khoá đầu tiên). Cuộc gọi / push đánh thức app lúc khoá màn hình;
  // kiểu mặc định (chỉ đọc khi đang mở khoá) làm app tưởng chưa đăng nhập và đẩy ra màn đăng nhập.
  static const _secure = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));
  static bool _migrated = false;

  /// iOS: chuyển phiên đã lưu theo kiểu cũ sang kiểu đọc được khi máy khoá (ghi lại một lần, lúc app đang mở).
  static Future<void> migrate() async {
    if (_migrated || kIsWeb || !Platform.isIOS) return;
    _migrated = true;
    try {
      final t = await _secure.read(key: _key);
      if (t != null && t.isNotEmpty) await _secure.write(key: _key, value: t);
    } catch (_) {
      _migrated = false;
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}${serverKey == 'main' ? 'session' : 'session_$serverKey'}');
  }

  /// Phiên đã lưu của một máy chủ bất kỳ (không phải máy chủ đang dùng).
  static Future<String?> readFor(String url) async {
    final k = serverKeyOf(url);
    if (isMobile) return _secure.read(key: k == 'main' ? 'mm_token' : 'mm_token_$k');
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}${k == 'main' ? 'session' : 'session_$k'}');
    if (!await f.exists()) return null;
    final t = (await f.readAsString()).trim();
    return t.isEmpty ? null : t;
  }

  /// Phiên đã lưu, null nếu chưa đăng nhập. Ném lỗi khi kho bảo mật tạm thời không đọc được
  /// (khác với chưa đăng nhập: đừng đưa người dùng ra màn đăng nhập).
  static Future<String?> read() async {
    if (!kIsWeb && Platform.isAndroid) await _importPreset();
    if (isMobile) return _secure.read(key: _key);
    final f = await _file();
    if (!await f.exists()) return null;
    final t = (await f.readAsString()).trim();
    return t.isEmpty ? null : t;
  }

  /// Quản trị viên có thể cấp sẵn phiên đăng nhập: đẩy file `preset_token`
  /// vào thư mục riêng của app qua ADB. App nhập vào kho bảo mật rồi xóa file.
  static Future<void> _importPreset() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/preset_token');
      if (!await f.exists()) return;
      final t = (await f.readAsString()).trim();
      await f.delete();
      if (t.isNotEmpty) await _secure.write(key: _key, value: t);
    } catch (_) {}
  }

  static Future<void> write(String token) async {
    if (isMobile) return _secure.write(key: _key, value: token);
    final f = await _file();
    await f.writeAsString(token, flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', f.path]);
    }
  }

  static Future<void> clear() async {
    if (isMobile) return _secure.delete(key: _key);
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

class LoginCancelled implements Exception {}

/// Flygo ID cần mã xác minh hai bước: hỏi mã rồi gọi [AuthService.finishTwoFactor].
class TwoFactorRequired implements Exception {
  const TwoFactorRequired();
}

/// Đăng nhập Google qua luồng mobile_login của máy chủ chat.
/// Server chuyển về redirect_to kèm MMAUTHTOKEN sau khi Google xác thực xong.
class AuthService {
  /// Đăng nhập bằng tài khoản + mật khẩu (máy chủ không dùng Google).
  static Future<String> loginWithPassword(String login, String password) async {
    // Máy chủ có Flygo ID: đăng nhập Flygo ID trong app rồi đổi lấy phiên chat (giữ luôn phiên Flygo ID cho màn
    // quản trị). Máy chủ chưa bật (404) hoặc tài khoản chưa có ở Flygo ID: quay về đăng nhập mật khẩu của chat.
    if (Uri.tryParse(kServerUrl)?.host == Uri.parse(kChatIssuer).host) {
      // Phiên Flygo ID là phiên gốc; chỉ máy chủ chưa bật đổi phiên (404 / not_enabled) mới dùng đăng nhập cũ.
      final id = FlygoSession.instance;
      try {
        if (await id.signIn(login, password) == 'two_factor') throw const TwoFactorRequired();
        return await id.chatToken(kServerUrl);
      } on AccessException catch (e) {
        if (e.status != 404 && e.code != 'not_enabled') {
          if (e.status == 401 || e.status == 400) throw Exception(e.message ?? tr('Sai tài khoản hoặc mật khẩu.'));
          if (e.status == 403) throw Exception(e.message ?? tr('Tài khoản bị chặn đăng nhập.'));
          throw Exception(e.message ?? e.code);
        }
      }
    }
    final res = await http.post(
      Uri.parse('$kServerUrl/api/v4/users/login'),
      headers: {'Content-Type': 'application/json', 'User-Agent': kUserAgent, 'X-Requested-With': 'XMLHttpRequest'},
      body: jsonEncode({'login_id': login, 'password': password}),
    );
    final token = res.headers['token'];
    if (res.statusCode >= 400 || token == null || token.isEmpty) {
      String msg = tr('Sai tài khoản hoặc mật khẩu.');
      try {
        msg = (jsonDecode(res.body) as Map)['message'] as String? ?? msg;
      } catch (_) {}
      throw Exception(msg);
    }
    return token;
  }

  /// Gửi mã hai bước cho phiên Flygo ID đang chờ, rồi đổi lấy phiên chat.
  static Future<String> finishTwoFactor(String code) async {
    try {
      await FlygoSession.instance.verifyTotp(code.trim());
      return await FlygoSession.instance.chatToken(kServerUrl);
    } on AccessException catch (e) {
      throw Exception(e.message ?? tr('Mã xác minh không đúng.'));
    }
  }

  /// Máy chủ dùng Flygo ID làm phiên gốc (chat.flygo.vn).
  static bool get flygoIdRoot => Uri.tryParse(kServerUrl)?.host == Uri.parse(kChatIssuer).host;

  /// Kiểm tra một địa chỉ có phải máy chủ chat không.
  static Future<bool> ping(String url) async {
    try {
      final res = await http
          .get(Uri.parse('$url/api/v4/system/ping'), headers: {'User-Agent': kUserAgent})
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Một nút "Đăng nhập Flygo ID" (Sếp, 2026-11-27): mở trang Flygo ID trong trình duyệt hệ thống, Flygo ID tự lo
  /// mật khẩu / Google / passkey / hai bước. /oauth2/token trả id_token + session_token (phiên gốc 30 ngày của app);
  /// id_token đổi tiếp lấy phiên chat qua session-exchange.
  static Future<String> loginWithFlygoId() async {
    String rnd(int n) => base64Url.encode(List.generate(n, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
    final verifier = rnd(48), nonce = rnd(16), state = rnd(16);
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    const redirect = '$kMobileScheme://auth/callback';
    final url = Uri.parse('$kFlygoIdUrl/api/auth/oauth2/authorize').replace(queryParameters: {
      'client_id': kChatClientId,
      'response_type': 'code',
      'scope': 'openid profile email offline_access',
      'redirect_uri': redirect,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'nonce': nonce,
    }).toString();
    final cb = isMobile
        ? Uri.parse(await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: kMobileScheme))
        : await _browser(url, (u) => u.queryParameters.containsKey('code') || u.queryParameters.containsKey('error'));
    final code = cb.queryParameters['code'];
    if (code == null || cb.queryParameters['state'] != state) {
      if (cb.queryParameters['error'] == 'access_denied') throw LoginCancelled();
      throw Exception(cb.queryParameters['error_description'] ?? tr('Không nhận được kết quả đăng nhập Flygo ID.'));
    }
    final r = await http.post(
      Uri.parse('$kFlygoIdUrl/api/auth/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'authorization_code', 'code': code, 'code_verifier': verifier, 'redirect_uri': redirect, 'client_id': kChatClientId},
    );
    Map j = {};
    try {
      j = jsonDecode(r.body) as Map;
    } catch (_) {}
    if (r.statusCode == 503) throw Exception(tr('Flygo ID đang bận. Bấm đăng nhập lại.'));
    if (r.statusCode != 200 || j['id_token'] is! String) throw Exception('${j['error_description'] ?? j['error'] ?? tr('Đăng nhập Flygo ID không thành công.')}');
    if (j['session_token'] is String) await FlygoSession.instance.adopt(j['session_token'] as String);
    return FlygoSession.instance.exchange(kServerUrl, j['id_token'] as String, nonce);
  }

  static Future<String> loginWithGoogle() async {
    return isMobile ? _mobile() : _desktop();
  }

  static String _loginUrl(String redirect) =>
      '$kServerUrl/oauth/google/mobile_login?redirect_to=${Uri.encodeComponent(redirect)}';

  static Future<String> _mobile() async {
    final result = await FlutterWebAuth2.authenticate(
      url: _loginUrl('$kMobileScheme://callback'),
      callbackUrlScheme: kMobileScheme,
    );
    final token = Uri.parse(result).queryParameters['MMAUTHTOKEN'];
    if (token == null || token.isEmpty) throw Exception(tr('Không nhận được phiên đăng nhập'));
    return token;
  }

  /// Máy tính: mở [url] trong trình duyệt, chờ liên kết `flygochat://...` quay về app (macOS: kênh flygo/link;
  /// Windows/Linux: bản app mới mở chuyển qua cổng tạm, xem [relayCallback]). Trả liên kết đó khi [done].
  static Future<Uri> _browser(String url, bool Function(Uri) done) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completer = Completer<Uri>();
    server.listen((req) async {
      final ok = done(req.uri);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_resultPage(ok));
      await req.response.close();
      if (ok && !completer.isCompleted) completer.complete(req.uri);
    });
    try {
      if (Platform.isMacOS) {
        _linkChannel.setMethodCallHandler((call) async {
          final u = Uri.tryParse('${call.arguments}');
          if (call.method == 'open' && u != null && done(u) && !completer.isCompleted) completer.complete(u);
        });
      } else {
        await _portFile().writeAsString('${server.port}', flush: true);
      }
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) throw Exception(tr('Không mở được trình duyệt'));
      return await completer.future.timeout(const Duration(minutes: 5), onTimeout: () => throw LoginCancelled());
    } finally {
      await server.close(force: true);
    }
  }

  /// Máy tính: mở trình duyệt, nhận kết quả qua một cổng tạm trên 127.0.0.1.
  static Future<String> _desktop() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completer = Completer<String>();
    server.listen((req) async {
      final token = req.uri.queryParameters['MMAUTHTOKEN'];
      final ok = token != null && token.isNotEmpty;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_resultPage(ok));
      await req.response.close();
      if (ok && !completer.isCompleted) completer.complete(token);
    });
    try {
      // Máy chủ chat chỉ giữ nguyên redirect dạng đúng `flygochat://callback` (không path, không
      // query), nên trên Linux/Windows hệ điều hành mở một bản app khác với liên kết đó; bản đó
      // đọc cổng từ [_portFile] rồi chuyển phiên vào cổng này và thoát (xem [relayCallback]).
      // macOS: liên kết mở thẳng vào app đang chạy (AppDelegate → kênh "flygo/link").
      if (Platform.isMacOS) {
        _linkChannel.setMethodCallHandler((call) async {
          final token = Uri.tryParse('${call.arguments}')?.queryParameters['MMAUTHTOKEN'];
          if (call.method == 'open' && token != null && token.isNotEmpty && !completer.isCompleted) {
            completer.complete(token);
          }
        });
      } else {
        await _portFile().writeAsString('${server.port}', flush: true);
      }
      final redirect = '$kMobileScheme://callback';
      final url = _loginUrl(redirect);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw Exception(tr('Không mở được trình duyệt'));
      }
      return await completer.future.timeout(const Duration(minutes: 5), onTimeout: () => throw LoginCancelled());
    } finally {
      await server.close(force: true);
    }
  }

  /// App được mở bằng liên kết `flygochat://callback/<cổng>?MMAUTHTOKEN=...` (máy tính):
  /// gửi phiên cho bản app đang chờ đăng nhập rồi trả về true để thoát luôn.
  static Future<bool> relayCallback(List<String> args) async {
    final link = args.where((a) => a.startsWith('$kMobileScheme://')).firstOrNull;
    if (link == null) return false;
    final uri = Uri.parse(link);
    var port = int.tryParse(uri.pathSegments.lastOrNull ?? '');
    try {
      port ??= int.tryParse((await _portFile().readAsString()).trim());
    } catch (_) {}
    if (port != null) {
      try {
        final target = Uri.http('127.0.0.1:$port', '/callback', uri.queryParameters);
        await http.get(target).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    return true;
  }

  static const _linkChannel = MethodChannel('flygo/link');

  /// File tạm ghi cổng của bản app đang chờ đăng nhập (máy tính).
  static File _portFile() {
    final dir = Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path;
    final user = Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? '';
    return File('$dir${Platform.pathSeparator}flygo-chat-login-$user.port');
  }

  static String _resultPage(bool ok) => '''<!doctype html><html lang="vi"><head><meta charset="utf-8">
<title>Flygo Chat</title><style>body{font-family:system-ui,sans-serif;background:#f0f2f5;display:flex;
align-items:center;justify-content:center;height:100vh;margin:0}div{background:#fff;padding:40px 48px;
border-radius:12px;text-align:center;box-shadow:0 1px 3px rgba(0,0,0,.1)}h1{color:#008069;font-size:22px}
p{color:#667781}</style></head><body><div><h1>${ok ? tr('Đăng nhập thành công') : tr('Đăng nhập chưa xong')}</h1>
<p>${ok ? tr('Bạn có thể đóng trang này và quay lại ứng dụng Flygo Chat.') : tr('Vui lòng quay lại ứng dụng và thử lại.')}</p>
</div></body></html>''';
}
