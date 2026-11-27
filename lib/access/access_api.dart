// Flygo ID (id.flygo.vn) và Flygo Access (access.flygo.vn) cho các màn quản trị native.
// Phiên Flygo ID: đăng nhập trong app (email / tên đăng nhập + mật khẩu), giữ trong Keychain / Keystore.
// Mọi lệnh gọi Access kèm Bearer <token phiên> lấy ở GET /api/auth/token (JWT 5 phút, aud flygo-access).
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const kFlygoIdUrl = 'https://id.flygo.vn';
const kAccessUrl = 'https://access.flygo.vn';
const kChatIssuer = 'https://chat.flygo.vn/flygo-id';
const kChatClientId = 'flygo-chat-app';

class AccessException implements Exception {
  AccessException(this.status, this.code, [this.message]);
  final int status;
  final String code;
  final String? message;

  /// 401: phiên chắc chắn sai, phải đăng nhập lại. 503 thì KHÔNG coi là đăng xuất.
  bool get needLogin => status == 401;
  bool get notAdmin => status == 403;
  @override
  String toString() => message ?? code;
}

/// Phiên Flygo ID của app. [client] thay được khi kiểm thử.
class FlygoSession {
  FlygoSession({http.Client? client, FlutterSecureStorage? storage, String? preset})
    : _http = client ?? http.Client(),
      _store = storage ?? const FlutterSecureStorage(),
      _session = preset;
  final http.Client _http;
  final FlutterSecureStorage _store;
  static const _key = 'flygo_id_session';

  /// Phiên GỐC của app (Sếp, 2026-11-27: mọi thứ do Flygo ID/Access quản lý). Phiên chat được đổi ra từ phiên này.
  static final FlygoSession instance = FlygoSession();

  /// Bearer của phiên (plugin bearer của Flygo ID) hoặc chuỗi cookie phiên.
  String? _session;
  String? _jwt;
  DateTime _jwtAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<bool> restore() async {
    _session ??= await _store.read(key: _key);
    return _session != null;
  }

  bool get signedIn => _session != null;

  Map<String, String> get _auth => _session == null
      ? {}
      : _session!.startsWith('cookie:')
      ? {'Cookie': _session!.substring(7)}
      : {'Authorization': 'Bearer $_session'};

  /// Đăng nhập bằng email hoặc tên đăng nhập. Trả `two_factor` khi cần mã xác minh hai bước.
  Future<String?> signIn(String login, String password) async {
    final email = login.contains('@');
    final r = await _http.post(
      Uri.parse('$kFlygoIdUrl/api/auth/sign-in/${email ? 'email' : 'username'}'),
      headers: {'Content-Type': 'application/json', 'Origin': kFlygoIdUrl},
      body: jsonEncode({email ? 'email' : 'username': login, 'password': password}),
    );
    final j = _json(r);
    if (r.statusCode != 200) throw AccessException(r.statusCode, '${j['code'] ?? 'sign_in_failed'}', j['message'] as String?);
    await _keep(r);
    if (j['twoFactorRedirect'] == true) return 'two_factor';
    return null;
  }

  /// Mã xác minh hai bước (ứng dụng xác thực).
  Future<void> verifyTotp(String code) async {
    final r = await _http.post(
      Uri.parse('$kFlygoIdUrl/api/auth/two-factor/verify-totp'),
      headers: {..._auth, 'Content-Type': 'application/json', 'Origin': kFlygoIdUrl},
      body: jsonEncode({'code': code}),
    );
    final j = _json(r);
    if (r.statusCode != 200) throw AccessException(r.statusCode, '${j['code'] ?? 'invalid_code'}', j['message'] as String?);
    await _keep(r);
  }

  Future<void> _keep(http.Response r) async {
    final bearer = r.headers['set-auth-token'];
    final cookie = r.headers['set-cookie'];
    final s = bearer != null && bearer.isNotEmpty
        ? bearer
        : cookie != null
        ? 'cookie:${RegExp(r'((?:__Secure-)?[\w.-]*session_token=[^;]+)').allMatches(cookie).map((m) => m.group(1)).join('; ')}'
        : null;
    if (s == null || s == 'cookie:') return;
    _session = s;
    _jwt = null;
    await _store.write(key: _key, value: s);
  }

  Future<void> signOut() async {
    if (_session != null) {
      unawaited(_http.post(Uri.parse('$kFlygoIdUrl/api/auth/sign-out'), headers: {..._auth, 'Origin': kFlygoIdUrl}).catchError((_) => http.Response('', 0)));
    }
    _session = null;
    _jwt = null;
    await _store.delete(key: _key);
  }

  /// Token phiên cho Access, giữ lại 4 phút (sống 5 phút).
  Future<String> token() async {
    if (_jwt != null && DateTime.now().difference(_jwtAt) < const Duration(minutes: 4)) return _jwt!;
    if (_session == null) throw AccessException(401, 'login_required');
    final r = await _http.get(Uri.parse('$kFlygoIdUrl/api/auth/token'), headers: _auth);
    if (r.statusCode == 401) {
      await signOut();
      throw AccessException(401, 'login_required');
    }
    final j = _json(r);
    if (r.statusCode != 200 || j['token'] is! String) throw AccessException(r.statusCode, 'token_unavailable');
    _jwtAt = DateTime.now();
    return _jwt = j['token'] as String;
  }

  /// Đổi phiên Flygo ID lấy phiên chat của [server], không mở trình duyệt: authorize (client công khai
  /// flygo-chat-app, PKCE S256, nonce) -> code -> id_token -> POST session-exchange. Trả token dùng như MMAUTHTOKEN.
  /// 404 not_enabled: máy chủ chưa bật, người gọi quay về đường đăng nhập cũ.
  Future<String> chatToken(String server) async {
    if (_session == null) throw AccessException(401, 'login_required');
    String rnd(int n) => base64Url.encode(List.generate(n, (_) => Random.secure().nextInt(256))).replaceAll('=', '');
    final verifier = rnd(48), nonce = rnd(16), state = rnd(16);
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    const redirect = 'http://127.0.0.1/auth/callback';
    final auth = Uri.parse('$kFlygoIdUrl/api/auth/oauth2/authorize').replace(
      queryParameters: {
        'client_id': kChatClientId,
        'response_type': 'code',
        'redirect_uri': redirect,
        'scope': 'openid profile email',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'nonce': nonce,
        'state': state,
      },
    );
    final req = http.Request('GET', auth)
      ..followRedirects = false
      ..headers.addAll(_auth);
    final r = await http.Response.fromStream(await _http.send(req));
    String? next = r.headers['location'];
    if (next == null) {
      final j = _json(r);
      next = (j['url'] ?? j['redirect'] ?? j['redirectURI']) as String?;
    }
    final cb = next == null ? null : Uri.tryParse(next);
    final code = cb?.queryParameters['code'];
    if (code == null || cb?.queryParameters['state'] != state) {
      throw AccessException(r.statusCode == 401 ? 401 : 502, 'authorize_failed', cb?.queryParameters['error_description'] ?? cb?.queryParameters['error']);
    }
    final t = await _http.post(
      Uri.parse('$kChatIssuer/oidc/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'authorization_code', 'code': code, 'redirect_uri': redirect, 'client_id': kChatClientId, 'code_verifier': verifier},
    );
    final tj = _json(t);
    if (t.statusCode != 200 || tj['id_token'] is! String)
      throw AccessException(t.statusCode, '${tj['error'] ?? 'token_failed'}', tj['error_description'] as String?);
    final x = await _http.post(
      Uri.parse('$server/plugins/vn.flygo.sso/flygo/session-exchange'),
      headers: {'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest'},
      body: jsonEncode({'id_token': tj['id_token'], 'nonce': nonce, 'mobile': true}),
    );
    final xj = _json(x);
    if (x.statusCode != 200 || xj['token'] is! String) throw AccessException(x.statusCode, '${xj['error'] ?? 'exchange_failed'}', xj['message'] as String?);
    return xj['token'] as String;
  }

  /// Gọi thẳng Flygo ID (tài khoản cá nhân).
  Future<dynamic> id(String method, String path, [Object? body]) => _send(Uri.parse('$kFlygoIdUrl/api/auth$path'), method, body, _auth);

  Future<dynamic> _send(Uri u, String method, Object? body, Map<String, String> h) async {
    final req = http.Request(method, u)..headers.addAll({...h, 'Origin': u.origin});
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final r = await http.Response.fromStream(await _http.send(req));
    final j = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 300) {
      final m = j is Map ? j : const {};
      throw AccessException(r.statusCode, '${m['error'] ?? m['code'] ?? r.statusCode}', m['message'] as String?);
    }
    return j;
  }

  static Map _json(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      return j is Map ? j : {};
    } catch (_) {
      return {};
    }
  }
}

/// Các đường của Flygo Access mà màn quản trị dùng.
class AccessApi {
  AccessApi(this.session);
  final FlygoSession session;

  Future<dynamic> _call(String method, String path, [Object? body]) async =>
      session._send(Uri.parse('$kAccessUrl$path'), method, body, {'Authorization': 'Bearer ${await session.token()}'});

  String _o(String org) => '/v1/orgs/${Uri.encodeComponent(org)}';

  Future<List<Map>> myOrgs() async => [for (final o in ((await _call('GET', '/v1/my-orgs'))['orgs'] as List? ?? const [])) o as Map];
  Future<List<Map>> myApps(String org) async => _list(await _call('GET', '${_o(org)}/my-apps'), 'apps');
  Future<Map> appToken(String org, String app) async => await _call('POST', '${_o(org)}/apps/$app/token') as Map;

  Future<Map> directory(String org) async => await _call('GET', '${_o(org)}/directory') as Map;
  Future<void> putMember(String org, String sub, Map body) => _call('PUT', '${_o(org)}/members/${Uri.encodeComponent(sub)}', body);
  Future<void> removeMember(String org, String sub) => _call('DELETE', '${_o(org)}/members/${Uri.encodeComponent(sub)}');
  Future<void> putDepartment(String org, String id, String name, String? parent) =>
      _call('PUT', '${_o(org)}/departments/${Uri.encodeComponent(id)}', {'name': name, 'parent_id': parent});
  Future<void> removeDepartment(String org, String id) => _call('DELETE', '${_o(org)}/departments/${Uri.encodeComponent(id)}');
  Future<void> putDeptMember(String org, String dept, String sub, String role) =>
      _call('PUT', '${_o(org)}/departments/${Uri.encodeComponent(dept)}/members/${Uri.encodeComponent(sub)}', {'role': role});
  Future<void> removeDeptMember(String org, String dept, String sub) =>
      _call('DELETE', '${_o(org)}/departments/${Uri.encodeComponent(dept)}/members/${Uri.encodeComponent(sub)}');

  Future<List<Map>> grants(String org, {String? sub, String? group}) async =>
      _list(await _call('GET', '${_o(org)}/grants?${Uri(queryParameters: {if (sub != null) 'sub': sub, if (group != null) 'group': group}).query}'), 'grants');
  Future<Map> policy(String org, String app) async => await _call('GET', '${_o(org)}/apps/$app/policy') as Map;

  Future<List<Map>> installed(String org) async => _list(await _call('GET', '${_o(org)}/apps'), 'apps');
  Future<Map> push(String org, String app) async => await _call('POST', '${_o(org)}/apps/$app/push') as Map;

  Future<List<Map>> catalog() async => _list(await _call('GET', '/v1/apps'), 'apps');
  Future<Map> app(String app) async => await _call('GET', '/v1/apps/$app') as Map;
  Future<Map> install(String org, String app, Map body) async => await _call('POST', '${_o(org)}/apps/$app/install', body) as Map;
  Future<Map> reviews(String app, String? org) async =>
      await _call('GET', '/v1/apps/$app/reviews${org == null ? '' : '?org=${Uri.encodeComponent(org)}'}') as Map;
  Future<void> putReview(String org, String app, int stars, String body) => _call('PUT', '${_o(org)}/apps/$app/review', {'stars': stars, 'body': body});
  Future<void> removeReview(String org, String app) => _call('DELETE', '${_o(org)}/apps/$app/review');

  Future<Map> keys(String org) async => await _call('GET', '${_o(org)}/keys') as Map;
  Future<List<Map>> audit(String org, {int limit = 100}) async => _list(await _call('GET', '${_o(org)}/audit?limit=$limit'), 'items');
  Future<Map> billing(String org) async => await _call('GET', '${_o(org)}/billing') as Map;

  static List<Map> _list(dynamic j, String k) => [for (final x in ((j is Map ? j[k] : null) as List? ?? const [])) x as Map];
}
