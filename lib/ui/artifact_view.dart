// Artifact của trợ lý (runner: tool artifact_publish): trang HTML / biểu đồ / mini app hiện ngay trong chat.
// Tin mang props.flygo_artifact = {id, title, version, file_id, kind}; các phiên bản là các tin cùng id.
// Trang chạy trong WebView riêng (ẩn danh, không cookie / token, CSP chặn gọi mạng, link mở trình duyệt ngoài);
// HTML do app tải bằng token của người dùng rồi nạp dạng chuỗi nên WebView không bao giờ thấy thông tin đăng nhập.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'app_route.dart';
import 'theme.dart';

Map<String, dynamic>? artifactOf(MmPost p) => (p.props['flygo_artifact'] as Map?)?.cast<String, dynamic>();

/// CSP chèn vào đầu trang: chỉ script / style inline + 2 CDN, ảnh data/https, không gọi mạng, không form.
const kArtifactCsp = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com; "
    "style-src 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://fonts.googleapis.com; "
    "font-src https://fonts.gstatic.com https://cdn.jsdelivr.net data:; img-src data: blob: https:; media-src data: blob: https:; "
    "connect-src 'none'; form-action 'none'; base-uri 'none'";

/// Chèn thẻ CSP vào ngay sau thẻ head (không có thẻ head thì đặt lên đầu).
@visibleForTesting
String withCsp(String html) {
  final meta = '<meta http-equiv="Content-Security-Policy" content="$kArtifactCsp">';
  final m = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
  return m == null ? '$meta$html' : html.replaceRange(m.end, m.end, meta);
}

bool get _webviewOk => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isIOS || Platform.isAndroid);

final _htmlCache = <String, String>{};

Future<String> _loadHtml(AppState app, String fileId) async =>
    _htmlCache[fileId] ??= utf8.decode(await app.api.fileBytes(fileId), allowMalformed: true);

IconData artifactIcon(String? kind) => switch (kind) {
      'chart' => Icons.insert_chart_outlined_rounded,
      'app' => Icons.widgets_outlined,
      'report' => Icons.article_outlined,
      _ => Icons.web_asset_rounded,
    };

/// Các phiên bản của artifact [id] trong kênh, cũ → mới.
List<MmPost> artifactVersions(AppState app, String channelId, String id) {
  final list = [for (final p in app.postsOf(channelId)) if (artifactOf(p)?['id'] == id) p];
  list.sort((a, b) => ((artifactOf(a)?['version'] as num?) ?? 1).compareTo((artifactOf(b)?['version'] as num?) ?? 1));
  return list;
}

class ArtifactCard extends StatefulWidget {
  final MmPost post;
  const ArtifactCard({super.key, required this.post});

  /// Chỉ cho kiểm thử / ảnh xem trước: thay khung WebView.
  @visibleForTesting
  static Widget Function(String html)? debugPreview;
  @visibleForTesting
  static String? debugHtml;

  @override
  State<ArtifactCard> createState() => _ArtifactCardState();
}

class _ArtifactCardState extends State<ArtifactCard> {
  /// Phiên bản đang xem (null = mới nhất).
  int? _picked;
  String? _html;
  String? _err;
  String? _loadedFile;

  MmPost _current(AppState app) {
    final id = artifactOf(widget.post)?['id'] as String?;
    if (id == null) return widget.post;
    final vs = artifactVersions(app, widget.post.channelId, id);
    if (vs.isEmpty) return widget.post;
    if (_picked != null) return vs.firstWhere((p) => artifactOf(p)?['version'] == _picked, orElse: () => vs.last);
    return vs.last;
  }

  void _ensure(AppState app, String fileId) {
    if (_loadedFile == fileId) return;
    _loadedFile = fileId;
    _html = ArtifactCard.debugHtml ?? _htmlCache[fileId];
    _err = null;
    if (_html != null) return;
    _loadHtml(app, fileId).then((h) {
      if (mounted && _loadedFile == fileId) setState(() => _html = h);
    }).catchError((_) {
      if (mounted && _loadedFile == fileId) setState(() => _err = tr('Không tải được artifact. Kiểm tra kết nối mạng.'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    final cur = _current(app);
    final art = artifactOf(cur) ?? const {};
    final id = art['id'] as String?;
    final versions = id == null ? <MmPost>[cur] : artifactVersions(app, cur.channelId, id);
    final fileId = art['file_id'] as String? ?? '';
    _ensure(app, fileId);
    final title = art['title'] as String? ?? tr('Artifact');
    final version = (art['version'] as num?)?.toInt() ?? 1;
    const accent = Color(0xFFD97757);
    Widget btn(String t, IconData i, VoidCallback? onTap, {bool primary = false}) => Padding(
          padding: const EdgeInsets.only(right: 6, top: 8),
          child: Material(
            color: primary ? accent.withValues(alpha: .14) : pal.text.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(i, size: 16, color: primary ? accent : pal.text),
                  const SizedBox(width: 5),
                  Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary ? accent : pal.text)),
                ]),
              ),
            ),
          ),
        );
    final html = _html;
    final preview = _err != null
        ? Center(child: Text(_err!, style: TextStyle(color: pal.sub)))
        : html == null
            ? Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent)))
            : ArtifactCard.debugPreview?.call(html) ??
                (_webviewOk
                    ? ArtifactWebView(key: ValueKey(fileId), html: html)
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(tr('Máy này chưa xem trực tiếp được, bấm "Mở trong trình duyệt".'),
                              textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
                        ),
                      ));
    return Container(
      constraints: const BoxConstraints(maxWidth: 760),
      decoration: BoxDecoration(
        color: Color.alphaBlend(pal.text.withValues(alpha: .035), pal.bg),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.text.withValues(alpha: .09)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
              child: Icon(artifactIcon(art['kind'] as String?), size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text)),
                Text(tr('Artifact · phiên bản {0}', [version]), style: TextStyle(fontSize: 12, color: pal.sub)),
              ]),
            ),
            if (versions.length > 1)
              PopupMenuButton<int>(
                tooltip: tr('Phiên bản'),
                onSelected: (v) => setState(() => _picked = v),
                itemBuilder: (_) => [
                  for (final p in versions.reversed)
                    PopupMenuItem(value: (artifactOf(p)?['version'] as num?)?.toInt() ?? 1, child: Text('v${artifactOf(p)?['version'] ?? 1}')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: pal.text.withValues(alpha: .07), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history_rounded, size: 14, color: pal.sub),
                    const SizedBox(width: 4),
                    Text('v$version', style: TextStyle(fontSize: 12.5, color: pal.sub)),
                  ]),
                ),
              ),
            IconButton(
              tooltip: tr('Toàn màn hình'),
              icon: Icon(Icons.open_in_full_rounded, size: 19, color: pal.sub),
              onPressed: html == null ? null : () => _fullscreen(context, title, html),
            ),
          ]),
        ),
        Container(
          height: 360,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.text.withValues(alpha: .08))),
          child: preview,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
          child: Wrap(children: [
            btn(tr('Toàn màn hình'), Icons.fullscreen_rounded, html == null ? null : () => _fullscreen(context, title, html), primary: true),
            btn(tr('Mở trong trình duyệt'), Icons.open_in_browser_rounded, html == null ? null : () => _openBrowser(title, html)),
            btn(tr('Sao chép HTML'), Icons.code_rounded, html == null ? null : () => _copy(context, html)),
            btn(tr('Chia sẻ link'), Icons.ios_share_rounded, () => _share(context, app, cur)),
          ]),
        ),
      ]),
    );
  }

  void _fullscreen(BuildContext context, String title, String html) {
    Navigator.of(context, rootNavigator: true).push(AppPageRoute(builder: (c) {
      final pal = Pal.of(c);
      return Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(title: Text(title), backgroundColor: pal.bg, foregroundColor: pal.text, elevation: 0),
        body: _webviewOk ? ArtifactWebView(html: html) : Center(child: Text(tr('Máy này chưa xem trực tiếp được, bấm "Mở trong trình duyệt".'))),
      );
    }));
  }

  Future<void> _openBrowser(String title, String html) async {
    final dir = await getTemporaryDirectory();
    final slug = title.replaceAll(RegExp(r'[^\w\-]+', unicode: true), '-');
    final f = File('${dir.path}${Platform.pathSeparator}flygo-artifact-$slug.html');
    await f.writeAsString(withCsp(html));
    await launchUrl(Uri.file(f.path));
  }

  Future<void> _copy(BuildContext context, String html) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: html));
    messenger.showSnackBar(toast(Text(tr('Đã sao chép'))));
  }

  /// Link xem công khai (chỉ xem) do trạm đẩy phục vụ; ai có link là xem được, thu hồi được.
  Future<void> _share(BuildContext context, AppState app, MmPost p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await http
          .post(Uri.parse('${pushUrlFor(kServerUrl)}/artifact/share'),
              headers: {'Authorization': 'Bearer ${app.token}', 'X-MM-Server': kServerUrl, 'Content-Type': 'application/json', 'User-Agent': kUserAgent},
              body: jsonEncode({'post_id': p.id}))
          .timeout(const Duration(seconds: 15));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode != 200 || j is! Map || j['url'] is! String) throw Exception(j is Map ? j['error'] : r.statusCode);
      await Clipboard.setData(ClipboardData(text: j['url'] as String));
      messenger.showSnackBar(toast(Text(tr('Đã sao chép link xem artifact (ai có link là xem được)'))));
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không tạo được link: {0}', ['$e'.replaceFirst('Exception: ', '')]))));
    }
  }
}

/// WebView riêng cho artifact: ẩn danh, không cache, link http(s) mở bằng trình duyệt ngoài.
class ArtifactWebView extends StatelessWidget {
  final String html;
  const ArtifactWebView({super.key, required this.html});

  @override
  Widget build(BuildContext context) => InAppWebView(
        initialData: InAppWebViewInitialData(data: withCsp(html), mimeType: 'text/html', encoding: 'utf-8'),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          incognito: true,
          cacheEnabled: false,
          clearCache: true,
          useShouldOverrideUrlLoading: true,
          supportMultipleWindows: false,
          javaScriptCanOpenWindowsAutomatically: false,
          allowFileAccess: false,
          allowContentAccess: false,
          isInspectable: kDebugMode,
        ),
        shouldOverrideUrlLoading: (c, nav) async {
          final u = nav.request.url;
          if (u == null || u.scheme == 'about' || u.scheme == 'data') return NavigationActionPolicy.ALLOW;
          if (u.scheme == 'http' || u.scheme == 'https' || u.scheme == 'mailto') {
            launchUrl(Uri.parse(u.toString()), mode: LaunchMode.externalApplication);
          }
          return NavigationActionPolicy.CANCEL;
        },
      );
}
