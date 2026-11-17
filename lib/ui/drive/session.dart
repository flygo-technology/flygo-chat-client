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
import 'uploads.dart';

class DriveSession {
  DriveSession({required this.api, required this.key, required this.app, required this.chatToken})
      : uploads = DriveUploads.of(api, key),
        offline = DriveOffline.of(api, key);

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

/// Mở một tệp: thư mục do màn hình gọi tự xử lý; Office mở OnlyOffice (webview); ảnh / PDF / video / chữ xem trong app;
/// loại khác tải về rồi mở bằng app khác của máy.
Future<void> openDriveFile(BuildContext context, DriveSession s, DriveItem it, {List<DriveItem> siblings = const []}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (isOffice(it)) return openOffice(context, s, it);
  if (canPreview(it)) {
    final list = siblings.where((x) => !x.dir && kindOf(x) == DriveKind.image).toList();
    await Navigator.of(context).push(AppPageRoute(builder: (_) => DrivePreviewPage(session: s, item: it, gallery: kindOf(it) == DriveKind.image ? list : const [])));
    return;
  }
  try {
    final f = await localCopy(s, it, onProgress: null);
    await openWithSystem(f);
  } catch (e) {
    messenger.showSnackBar(toast(Text(tr('Không mở được tệp: {0}', ['$e']))));
  }
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
Future<void> openOffice(BuildContext context, DriveSession s, DriveItem it) async {
  final app = s.app;
  final messenger = ScaffoldMessenger.of(context);
  if (app == null) {
    messenger.showSnackBar(toast(Text(tr('Chưa mở được trình soạn Office'))));
    return;
  }
  final path = '/drive/edit.html?id=${it.id}&path=${Uri.encodeComponent(it.path)}';
  if (!MiniApps.inAppWebView) {
    try {
      await launchUrl(await MiniApps.launch(s.chatToken, app, path: path), mode: LaunchMode.externalApplication);
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
    return;
  }
  // Máy tính: mỗi tài liệu một tab riêng mang tên tệp (đã mở thì chuyển sang tab đó). Điện thoại: một trang như cũ.
  if (isDesktop && appTabHook != null) {
    await AppHost.of(context).open(key: officeTabKey(it.id, it.path), title: it.name, builder: (_) => MiniAppPage(app: app, url: MiniApps.launch(s.chatToken, app, path: path), title: it.name));
    return;
  }
  await Navigator.of(context).push(AppPageRoute(builder: (_) => MiniAppPage(app: app, url: MiniApps.launch(s.chatToken, app, path: path), title: it.name)));
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
  await AppHost.of(context).open(key: key, title: name, builder: (_) => MiniAppPage(app: app, url: MiniApps.launch(s.chatToken, app, path: path), title: name));
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
