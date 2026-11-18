// Drive: phiên dùng chung cho các màn hình (API, hàng đợi tải lên, bản offline, thông tin tài khoản) và cách mở tệp.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../app_shell.dart';
import '../desk_tabs.dart' show appTabHook;
import '../mini_app_view.dart' show MiniAppPage;
import '../theme.dart' show toast;
import 'api.dart';
import 'look.dart';
import 'offline.dart';
import 'preview.dart';
import 'transfers.dart';
import 'uploads.dart';

class DriveSession {
  DriveSession({required this.api, required this.key, required this.app, required this.chatToken})
      : uploads = DriveUploads.of(api, key),
        offline = DriveOffline.of(api, key);

  /// Các lượt tải xuống (bảng tiến độ dưới màn hình).
  final downloads = DriveDownloads();

  final DriveApi api;
  final String key;
  /// App Drive trong Flygo ID (mở OnlyOffice qua SSO của app này). Có thể null khi mở từ chỗ khác (bảng chia sẻ).
  final MiniApp? app;
  final String chatToken;
  final DriveUploads uploads;
  final DriveOffline offline;
  DriveMe? me;
  /// Bộ nhớ tạm Ctrl+C / Ctrl+X của Drive (dán bằng Ctrl+V vào thư mục đang mở).
  List<DriveItem> clip = const [];
  bool clipCut = false;

  static final _cache = <String, DriveSession>{};

  /// Phiên Drive của người đang đăng nhập (null nếu máy chủ chưa có Flygo ID / người dùng không có app Drive).
  static Future<DriveSession?> current(AppState state, {MiniApp? app}) async {
    final id = await FlygoId.current(state.token);
    if (id == null) return null;
    app ??= await driveApp(state.token);
    if (app == null) return null;
    final key = '${serverKey}_${state.me?.id ?? 'me'}'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final hit = _cache[key];
    if (hit != null && hit.chatToken == state.token) return hit;
    final s = DriveSession(api: DriveApi(base: DriveApi.baseFor(kServerUrl), id: id), key: key, app: app, chatToken: state.token);
    s.uploads.api = s.api;
    s.offline.api = s.api;
    return _cache[key] = s;
  }

  /// App Drive (màn hình native "drive") trong danh sách app của người dùng.
  static Future<MiniApp?> driveApp(String token) async {
    try {
      final apps = await MiniApps.list(token);
      return apps.where((a) => a.id == kDriveApp || a.nativeScreen == kDriveScreen).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  Future<DriveMe> loadMe() async => me = await api.me();
}

/// Mở một tệp: thư mục do màn hình gọi tự xử lý; ảnh / PDF / Word / Excel / PowerPoint / video / chữ xem trong app
/// (Office xem bản PDF máy chủ chuyển sẵn; máy tính có nút "Chỉnh sửa" mở OnlyOffice ở tab riêng);
/// loại khác tải về rồi mở bằng app khác của máy.
Future<void> openDriveFile(BuildContext context, DriveSession s, DriveItem it, {List<DriveItem> siblings = const []}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (canPreview(it)) {
    // ← → / vuốt qua các tệp xem được cùng thư mục (ảnh, PDF, Office…).
    final list = siblings.where((x) => !x.dir && canPreview(x)).toList();
    await Navigator.of(context).push(AppPageRoute(builder: (_) => DrivePreviewPage(session: s, item: it, gallery: list)));
    return;
  }
  try {
    final f = await localCopy(s, it, onProgress: null);
    await openWithSystem(f);
  } catch (e) {
    messenger.showSnackBar(toast(Text(tr('Không mở được tệp: {0}', ['$e']))));
  }
}

/// Bản PDF để xem tài liệu Office (máy chủ chuyển bằng OnlyOffice, cache theo mã tệp + etag; máy cũng giữ một bản).
Future<File> previewPdf(DriveSession s, DriveItem it, {void Function(int, int)? onProgress}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/drive_preview');
  final f = File('${dir.path}/${it.id}_${it.etag.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}_${it.mtime}.pdf');
  if (await f.exists()) return f;
  return s.api.previewPdf(it.id, it.path, f, onProgress: onProgress);
}

/// Bản trên máy của tệp: bản ghim offline nếu còn khớp, không thì tải vào thư mục tạm.
Future<File> localCopy(DriveSession s, DriveItem it, {void Function(int, int)? onProgress}) async {
  final off = s.offline.localFile(it);
  if (off != null) return off;
  final dir = Directory('${(await getTemporaryDirectory()).path}/drive_open/${it.id}_${it.etag}');
  final f = File('${dir.path}/${it.name}');
  if (await f.exists()) return f;
  return s.api.download(it.path, f, onProgress: onProgress);
}

Future<void> openWithSystem(File f) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
  } else {
    await launchUrl(Uri.file(f.path));
  }
}

/// OnlyOffice trong webview (đăng nhập bằng SSO của app Drive), thanh trên là của app.
Future<void> openOffice(BuildContext context, DriveSession s, DriveItem it) => openOfficeAt(context, s, id: it.id, path: it.path);

/// Mở tài liệu Office [id] (đường dẫn [path] trong Drive của người dùng) bằng trang soạn nhanh `/drive/edit.html`:
/// máy tính mỗi tài liệu một tab riêng mang tên tệp (đã mở thì chuyển sang tab đó), điện thoại một trang.
Future<void> openOfficeAt(BuildContext context, DriveSession s, {required int id, required String path}) async {
  final app = s.app;
  final messenger = ScaffoldMessenger.of(context);
  if (app == null) {
    messenger.showSnackBar(toast(Text(tr('Chưa mở được trình soạn Office'))));
    return;
  }
  final name = path.split('/').last;
  final page = '/drive/edit.html?id=$id&path=${Uri.encodeComponent(path)}';
  if (!MiniApps.inAppWebView) {
    try {
      await launchUrl(await MiniApps.launch(s.chatToken, app, path: page), mode: LaunchMode.externalApplication);
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
    return;
  }
  Widget editor(BuildContext _) => MiniAppPage(app: app, url: MiniApps.launch(s.chatToken, app, path: page), title: name, editor: true);
  if (isDesktop && appTabHook != null) {
    await AppHost.of(context).open(key: officeTabKey(id, path), title: name, builder: editor);
    return;
  }
  await Navigator.of(context).push(AppPageRoute(builder: editor));
}

/// Link tới một tài liệu Office trong Drive / Office (trang soạn nhanh hoặc trang soạn của Nextcloud): (mã tệp, đường dẫn).
(int, String)? officeLinkOf(Uri u) {
  final p = u.path;
  if (p.endsWith('/drive/edit.html')) {
    final id = int.tryParse(u.queryParameters['id'] ?? '');
    return id == null ? null : (id, u.queryParameters['path'] ?? '');
  }
  final m = RegExp(r'^(?:/index\.php)?/apps/onlyoffice/(\d+)$').firstMatch(p);
  if (m == null) return null;
  return (int.parse(m.group(1)!), u.queryParameters['filePath'] ?? '');
}

/// Mở link tài liệu Office (từ trang Office / Drive web, link trong chat…) bằng phiên Drive của người đang đăng nhập.
Future<bool> openOfficeLink(BuildContext context, int id, String path) async {
  final state = context.read<AppState>();
  final s = await DriveSession.current(state);
  if (s == null || !context.mounted) return false;
  // Link cũ không có đường dẫn: hỏi drive-gw tên tệp theo mã.
  if (path.isEmpty) {
    try {
      path = (await s.api.info(id: id)).path;
    } catch (_) {}
    if (!context.mounted) return false;
  }
  await openOfficeAt(context, s, id: id, path: path.isEmpty ? '/$id' : path);
  return true;
}

/// Khoá tab máy tính của một tài liệu Office: `drive-office:<fileId>:<đường dẫn>` (mở lại được sau khởi động).
const kOfficeTabPrefix = 'drive-office:';
String officeTabKey(int id, String path) => '$kOfficeTabPrefix$id:${Uri.encodeComponent(path)}';

/// Tab tài liệu Office mở lại sau khởi động ([key] từ [officeTabKey]).
Future<void> restoreOfficeTab(BuildContext context, String key) async {
  final rest = key.substring(kOfficeTabPrefix.length);
  final i = rest.indexOf(':');
  if (i <= 0) return;
  final state = context.read<AppState>();
  final s = await DriveSession.current(state);
  final app = s?.app;
  if (s == null || app == null || !context.mounted) return;
  final id = rest.substring(0, i), filePath = Uri.decodeComponent(rest.substring(i + 1));
  final name = filePath.split('/').last;
  final path = '/drive/edit.html?id=$id&path=${Uri.encodeComponent(filePath)}';
  await AppHost.of(context).open(key: key, title: name, builder: (_) => MiniAppPage(app: app, url: MiniApps.launch(s.chatToken, app, path: path), title: name, editor: true));
}

/// Tên tệp và biểu tượng của tab tài liệu Office [key].
(String, IconData, Color) officeTabInfo(String key) {
  final rest = key.substring(kOfficeTabPrefix.length);
  final i = rest.indexOf(':');
  final name = i < 0 ? '' : Uri.decodeComponent(rest.substring(i + 1)).split('/').last;
  final (ic, c) = switch (kindOf(DriveItem(path: '/$name', name: name, dir: false))) {
    DriveKind.sheet => (Icons.table_chart_rounded, const Color(0xFF1E7B45)),
    DriveKind.slide => (Icons.slideshow_rounded, const Color(0xFFC4501F)),
    _ => (Icons.description_rounded, const Color(0xFF2B579A)),
  };
  return (name, ic, c);
}
