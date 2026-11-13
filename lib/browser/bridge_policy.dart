// Luật của cầu nối flygo.fetch / runtime (flygo-fetch-spec.md v0.2 §1, §4, §5, §10). Phần thuần Dart, không đụng
// WebView: native gọi trước khi gửi request, để kiểm bằng test.
import 'model.dart';

/// Nơi gọi, do native suy ra từ WebView (không bao giờ lấy theo lời JS).
enum Surface { web, background, content }

class BridgeError implements Exception {
  BridgeError(this.code, this.message);
  final String code;
  final String message;
  Map<String, String> toJson() => {'code': code, 'message': message};
  @override
  String toString() => '$code: $message';
}

/// Giới hạn v1 (§4 + §10): yêu cầu ≤ 10 MB, phản hồi ≤ 20 MB, 16 request song song mỗi WebView.
const kMaxRequestBytes = 10 * 1024 * 1024;
const kMaxResponseBytes = 20 * 1024 * 1024;
const kMaxConcurrent = 16;
const kMaxMessageBytes = 1024 * 1024;

const _forbiddenHeaders = {'authorization', 'cookie', 'host', 'origin', 'referer', 'dpop'};

/// Header không được trả về JS.
const kDroppedResponseHeaders = {'set-cookie', 'set-cookie2', 'authorization', 'www-authenticate'};

bool _forbidden(String name) {
  final h = name.toLowerCase();
  return _forbiddenHeaders.contains(h) || h.startsWith('proxy-') || h.startsWith('sec-') || h.startsWith('x-flygo-');
}

/// Kết quả kiểm: gửi tới đâu, có gắn vé Flygo không.
class FetchDecision {
  FetchDecision(this.uri, {required this.ticket});
  final Uri uri;

  /// true: origin thuộc api_origins, native gắn vé (Authorization). false: host_origins, không vé.
  final bool ticket;
}

/// Kiểm một lệnh fetch (flygo.fetch, hoặc fetch / XHR / WebSocket của background đi qua native).
/// [dev]: bản build thử cho phép http://localhost.
FetchDecision checkFetch({
  required Surface surface,
  required ExtensionManifest manifest,
  required Map<String, String> env,
  required String url,
  required Map<String, String> headers,
  int bodyBytes = 0,
  bool dev = false,
}) {
  if (surface == Surface.content) {
    throw BridgeError('UNSUPPORTED_CONTEXT', 'Content script trên trang ngoài không có flygo.fetch');
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) throw BridgeError('NOT_ALLOWED_ORIGIN', 'Địa chỉ không hợp lệ');
  final secure = uri.scheme == 'https' || uri.scheme == 'wss';
  final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
  if (!secure && !(dev && local)) throw BridgeError('NOT_ALLOWED_ORIGIN', 'Chỉ cho phép https');
  final origin = uri.hasPort ? '${uri.scheme}://${uri.host}:${uri.port}' : '${uri.scheme}://${uri.host}';
  // wss cùng host với một api origin https cũng là api (relay của máy chủ đó).
  String norm(String o) => o.replaceFirst(RegExp('^wss://'), 'https://').replaceFirst(RegExp('^ws://'), 'http://');
  bool inList(List<DeclaredOrigin> list) => list.any((d) {
        final r = d.resolve(env);
        return r != null && (r == origin || norm(r) == norm(origin));
      });
  final api = inList(manifest.apiOrigins);
  final host = !api && surface == Surface.background && inList(manifest.hostOrigins);
  if (!api && !host) throw BridgeError('NOT_ALLOWED_ORIGIN', '$origin không có trong api_origins / host_origins');
  for (final h in headers.keys) {
    if (_forbidden(h)) throw BridgeError('FORBIDDEN_HEADER', 'Không được đặt header $h');
  }
  if (bodyBytes > kMaxRequestBytes) throw BridgeError('TOO_LARGE', 'Nội dung gửi quá 10 MB');
  return FetchDecision(uri, ticket: api);
}

/// Kiểm một tin runtime.send / runtime.connect từ content script: chỉ loại tin và tên port đã khai.
void checkContentMessage({required ExtensionManifest manifest, String? type, String? port, int bytes = 0}) {
  if (bytes > kMaxMessageBytes) throw BridgeError('TOO_LARGE', 'Tin quá 1 MB');
  if (port != null) {
    if (!manifest.ports.contains(port)) throw BridgeError('NOT_DECLARED', 'Port "$port" chưa khai trong manifest');
    return;
  }
  if (type == null || !manifest.messages.contains(type)) {
    throw BridgeError('NOT_DECLARED', 'Loại tin "$type" chưa khai trong manifest');
  }
}

/// Lọc header phản hồi trước khi trả về JS.
Map<String, String> filterResponseHeaders(Map<String, String> headers) => {
      for (final e in headers.entries)
        if (!kDroppedResponseHeaders.contains(e.key.toLowerCase()) && !e.key.toLowerCase().startsWith('x-flygo-')) e.key: e.value,
    };

/// Mã chống nhầm trang theo từng lần tải (§10.1): mỗi WebView giữ mã hiện tại; tin mang mã cũ bị bỏ.
class NavigationNonce {
  String _current = '';
  String get current => _current;

  /// Gọi lúc trang mới bắt đầu (load-committed): mã mới, tin của trang trước hết hiệu lực.
  String next(String Function() random) => _current = random();

  bool accepts(Object? nonce) => _current.isNotEmpty && nonce is String && nonce == _current;
}
