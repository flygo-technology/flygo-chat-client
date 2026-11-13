// Mô hình của app Browser: extension (của mình, đóng gói sẵn trong app) và space (một "trình duyệt" có tên, màu,
// danh sách trang được phép, extension kèm env, kho tài khoản dùng chung). Đặc tả: /home/admin/handoff/
// miniapp-sso-design.md (§9 space tự khai báo) và flygo-fetch-spec.md v0.2. Danh sách trong JSON đều là object theo id.
import 'url_pattern.dart';

/// Thế giới JS của content script: MAIN chạy chung với trang (cần để vá fetch/XHR/WebSocket), ISOLATED tách riêng
/// (iOS / macOS có WKContentWorld; Android không có, coi như MAIN).
enum ScriptWorld { main, isolated }

class ContentScript {
  ContentScript({required this.id, required this.js, required this.match, this.world = ScriptWorld.main, this.allFrames = true});
  final String id;

  /// Đường dẫn tệp trong gói extension, vd "/ext/inject.js".
  final String js;
  final UrlPatternSet match;
  final ScriptWorld world;
  final bool allFrames;

  static ContentScript fromJson(String id, Map j) => ContentScript(
        id: id,
        js: '${j['js'] ?? ''}',
        match: UrlPatternSet([for (final m in (j['match'] as List? ?? const ['*://*/*'])) '$m']),
        world: j['world'] == 'ISOLATED' ? ScriptWorld.isolated : ScriptWorld.main,
        allFrames: j['all_frames'] != false,
      );
}

/// Một origin khai trong manifest. `url` có thể là "env:SERVER": lấy theo env của space (mỗi công ty một máy chủ).
class DeclaredOrigin {
  DeclaredOrigin(this.id, this.url);
  final String id;
  final String url;

  /// Origin thật trong một space (null nếu env thiếu hoặc địa chỉ sai).
  String? resolve(Map<String, String> env) {
    var u = url;
    if (u.startsWith('env:')) u = env[u.substring(4)] ?? '';
    final p = Uri.tryParse(u);
    if (p == null || p.host.isEmpty) return null;
    return p.hasPort ? '${p.scheme}://${p.host}:${p.port}' : '${p.scheme}://${p.host}';
  }
}

List<DeclaredOrigin> _origins(Object? j) => [
      if (j is Map)
        for (final e in j.entries)
          if (e.value is Map) DeclaredOrigin('${e.key}', '${(e.value as Map)['url'] ?? ''}'),
    ];

/// Manifest Flygo của một extension (tệp flygo-manifest.json trong gói), khác manifest.json của Chrome.
class ExtensionManifest {
  ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.base,
    this.backgroundPage,
    this.compat = '',
    this.contentScripts = const [],
    this.ports = const {},
    this.messages = const {},
    this.apiOrigins = const [],
    this.hostOrigins = const [],
    this.spaceProvider = false,
    this.spaceOrigins = const [],
    this.promptPage,
    this.promptScript,
  });

  final String id;
  final String name;
  final String version;

  /// Thư mục asset của gói, vd "assets/magicsign/".
  final String base;

  /// Trang chạy background (WebView ẩn), vd "/app/engine.html".
  final String? backgroundPage;

  /// "chrome": nạp lớp chrome.* (shim.js) để chạy nguyên extension MV3 cũ.
  final String compat;
  final List<ContentScript> contentScripts;

  /// Tên port content script được mở (runtime.connect) và loại tin được gửi (runtime.send).
  final Set<String> ports;
  final Set<String> messages;
  final List<DeclaredOrigin> apiOrigins;
  final List<DeclaredOrigin> hostOrigins;
  final bool spaceProvider;

  /// Khung tối đa cho whitelist của space do extension tự khai (duyệt lúc cài, không tự mở rộng).
  final List<UrlPattern> spaceOrigins;

  /// Hộp xác nhận (v1: trang của extension vẽ đè lên website).
  final String? promptPage;
  final String? promptScript;

  static ExtensionManifest fromJson(Map j, {required String base}) {
    final ext = j['extension'] as Map? ?? const {};
    final bg = ext['background'] as Map? ?? const {};
    final prompt = ext['prompt'] as Map? ?? const {};
    return ExtensionManifest(
      id: '${j['id']}',
      name: '${j['name'] ?? j['id']}',
      version: '${j['version'] ?? ''}',
      base: base,
      backgroundPage: bg['page'] as String?,
      compat: '${bg['compat'] ?? ''}',
      contentScripts: [
        if (ext['content_scripts'] is Map)
          for (final e in (ext['content_scripts'] as Map).entries)
            if (e.value is Map) ContentScript.fromJson('${e.key}', e.value as Map),
      ],
      ports: {if (ext['ports'] is Map) ...(ext['ports'] as Map).keys.map((k) => '$k')},
      messages: {if (ext['messages'] is Map) ...(ext['messages'] as Map).keys.map((k) => '$k')},
      apiOrigins: _origins(j['api_origins']),
      hostOrigins: _origins(j['host_origins']),
      spaceProvider: ext['space_provider'] == true,
      spaceOrigins: [
        if (ext['space_origins'] is Map)
          for (final v in (ext['space_origins'] as Map).values)
            if (v is Map) ?UrlPattern.tryParse('${v['pattern'] ?? ''}'),
      ],
      promptPage: prompt['page'] as String?,
      promptScript: prompt['script'] as String?,
    );
  }
}

/// Một space = một "trình duyệt": cookie riêng, whitelist, extension kèm env.
class Space {
  Space({
    required this.id,
    required this.name,
    this.color,
    required this.whitelist,
    this.env = const {},
    this.extensions = const [],
    this.bookmarks = const [],
    this.provider,
  });

  /// Space động: `vn.flygo.kyso/<token_id>`; space admin khai: id do Flygo ID cấp.
  final String id;
  final String name;
  final int? color;
  final UrlPatternSet whitelist;
  final Map<String, String> env;

  /// Extension chạy trong space này.
  final List<String> extensions;

  /// Trang đánh dấu sẵn: (tiêu đề, địa chỉ).
  final List<({String title, String url})> bookmarks;

  /// Extension đã khai space này (space động); null = space do admin khai.
  final String? provider;

  bool allows(String url) => whitelist.matchesString(url);

  static Space fromJson(Map j) => Space(
        id: '${j['id']}',
        name: '${j['name'] ?? j['id']}',
        color: j['color'] is int ? j['color'] as int : int.tryParse('${j['color'] ?? ''}'.replaceFirst('#', ''), radix: 16),
        whitelist: UrlPatternSet([
          if (j['whitelist'] is Map)
            for (final v in (j['whitelist'] as Map).values)
              if (v is Map) '${v['pattern'] ?? ''}',
        ]),
        env: {if (j['env'] is Map) for (final e in (j['env'] as Map).entries) '${e.key}': '${e.value}'},
        extensions: [if (j['extensions'] is Map) ...(j['extensions'] as Map).keys.map((k) => '$k')],
        bookmarks: [
          if (j['bookmarks'] is Map)
            for (final v in (j['bookmarks'] as Map).values)
              if (v is Map) (title: '${v['title'] ?? v['url']}', url: '${v['url'] ?? ''}'),
        ],
        provider: j['provider'] as String?,
      );
}

/// Space động phải nằm gọn trong space_origins của extension đã khai nó: bỏ các mẫu vượt khung.
/// Trả về (space đã cắt, các mẫu bị bỏ).
(Space, List<String>) clampToProvider(Space space, ExtensionManifest provider) {
  final kept = <UrlPattern>[];
  final dropped = <String>[];
  for (final p in space.whitelist.items) {
    if (provider.spaceOrigins.any(p.within)) {
      kept.add(p);
    } else {
      dropped.add(p.source);
    }
  }
  return (
    Space(
      id: space.id,
      name: space.name,
      color: space.color,
      whitelist: UrlPatternSet(kept.map((p) => p.source)),
      env: space.env,
      extensions: space.extensions,
      bookmarks: space.bookmarks.where((b) => kept.any((p) => Uri.tryParse(b.url) != null && p.matches(Uri.parse(b.url)))).toList(),
      provider: space.provider,
    ),
    dropped,
  );
}
