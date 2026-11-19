import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../config.dart';
import '../../data/models.dart' show MmFile;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../drive/pickers.dart' show pickFromDrive;
import '../drive/session.dart' show DriveSession;
import 'meet_home.dart' show meetToast;

// Trình chiếu tài liệu trong cuộc họp, không cần chia sẻ màn hình. Người trình chiếu chọn tệp (Drive, tệp trong nhóm của
// cuộc họp, tệp trên máy); Word / Excel / PowerPoint được Drive đổi sang PDF; bản PDF gửi lên relay. Mọi máy (app: pdfrx,
// TV / web: PDF.js) hiện cùng bản PDF, theo trang của người trình chiếu (metadata phòng `present`); người xem vuốt để xem tự
// do rồi bấm "Về trang người trình chiếu". Bút laser đi qua tin dữ liệu {t: 'laser', x, y} (tỉ lệ 0..1 của trang).

const _exts = ['pdf', 'pptx', 'ppt', 'odp', 'docx', 'doc', 'odt', 'rtf', 'xlsx', 'xls', 'ods', 'csv'];

/// Bài đang trình chiếu (metadata phòng).
class MeetPresentation {
  final String id, name, url, by, byName;
  final int page, pages, at;
  MeetPresentation(Map m)
      : id = '${m['id'] ?? ''}',
        name = '${m['name'] ?? ''}',
        url = '${m['url'] ?? ''}',
        by = '${m['by'] ?? ''}',
        byName = '${m['by_name'] ?? ''}',
        page = (m['page'] as num?)?.toInt() ?? 1,
        pages = (m['pages'] as num?)?.toInt() ?? 0,
        at = (m['at'] as num?)?.toInt() ?? 0;
}

/// "Trình chiếu tài liệu": chọn nguồn, đổi sang PDF, gửi lên cuộc họp.
Future<void> startPresenting(BuildContext context, CallService call) async {
  final app = context.read<AppState>();
  final src = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF2D2E31),
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text(tr('Trình chiếu tài liệu'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(tr('PowerPoint, PDF, Word, Excel. Mọi người, kể cả TV, xem cùng trang với bạn mà không cần chia sẻ màn hình.'),
              style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 13)),
        ),
        ListTile(
            leading: const Icon(Icons.cloud_outlined, color: Colors.white),
            title: Text(tr('Từ Drive'), style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'drive')),
        ListTile(
            leading: const Icon(Icons.attach_file_rounded, color: Colors.white),
            title: Text(tr('Tệp trong nhóm của cuộc họp'), style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'chat')),
        ListTile(
            leading: const Icon(Icons.folder_open_rounded, color: Colors.white),
            title: Text(tr('Từ máy này'), style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'device')),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (src == null || !context.mounted) return;
  final tmp = Directory('${(await getTemporaryDirectory()).path}/meet-present');
  await tmp.create(recursive: true);
  File? local;
  String name = '';
  File? pdf;
  try {
    switch (src) {
      case 'drive':
        if (!context.mounted) return;
        final r = await pickFromDrive(context, remoteOnly: true, extensions: _exts, single: true);
        final it = r?.remote.firstOrNull;
        final s = r?.session;
        if (it == null || s == null) return;
        name = it.name;
        pdf = File('${tmp.path}/d_${DateTime.now().millisecondsSinceEpoch}.pdf');
        if (context.mounted) meetToast(context, tr('Đang chuẩn bị tài liệu…'));
        if (name.toLowerCase().endsWith('.pdf')) {
          await s.api.download(it.path, pdf);
        } else {
          await s.api.previewPdf(it.id, it.path, pdf);
        }
      case 'chat':
        final ch = call.channelId;
        if (ch == null || !context.mounted) return;
        final f = await _pickChatFile(context, app, ch);
        if (f == null) return;
        name = f.name;
        if (context.mounted) meetToast(context, tr('Đang chuẩn bị tài liệu…'));
        local = await app.api.downloadFile(f, tmp);
      case 'device':
        final r = (await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _exts)).firstOrNull;
        final path = r?.path;
        if (r == null || path == null) return;
        name = r.name;
        local = File(path);
        if (context.mounted) meetToast(context, tr('Đang chuẩn bị tài liệu…'));
    }
    if (pdf == null && local != null) {
      if (name.toLowerCase().endsWith('.pdf')) {
        pdf = local;
      } else {
        // Word / Excel / PowerPoint: Drive đổi sang PDF (OnlyOffice, có cache).
        final s = await DriveSession.current(app);
        if (s == null) throw Exception(tr('Cần Drive để đổi tài liệu sang dạng trình chiếu. Hãy chọn tệp PDF.'));
        pdf = await s.api.previewUpload(local, name, File('${tmp.path}/u_${DateTime.now().millisecondsSinceEpoch}.pdf'));
      }
    }
    if (pdf == null) return;
    var pages = 0;
    try {
      final doc = await PdfDocument.openFile(pdf.path);
      pages = doc.pages.length;
      await doc.dispose();
    } catch (_) {}
    final err = await call.presentUpload(pdf, name, pages);
    if (err != null && context.mounted) meetToast(context, tr('Không trình chiếu được: {0}', [err]));
  } catch (e) {
    if (context.mounted) meetToast(context, tr('Không trình chiếu được: {0}', [e]));
  }
}

Future<MmFile?> _pickChatFile(BuildContext context, AppState app, String channelId) {
  final files = <MmFile>[
    for (final p in app.postsOf(channelId).reversed)
      for (final f in p.files)
        if (_exts.contains(f.name.split('.').last.toLowerCase())) f,
  ];
  return showModalBottomSheet<MmFile>(
    context: context,
    backgroundColor: const Color(0xFF2D2E31),
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: files.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('Nhóm của cuộc họp chưa có tài liệu nào (PDF, Word, Excel, PowerPoint).'),
                  style: const TextStyle(color: Colors.white70)),
            )
          : ListView(shrinkWrap: true, children: [
              for (final f in files.take(60))
                ListTile(
                  leading: const Icon(Icons.description_outlined, color: Colors.white),
                  title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  subtitle: Text('${(f.size / 1024 / 1024).toStringAsFixed(1)} MB', style: const TextStyle(color: Color(0xFF9AA0A6))),
                  onTap: () => Navigator.pop(ctx, f),
                ),
            ]),
    ),
  );
}

/// Bản PDF đang chiếu, tải một lần cho mỗi bài (mọi màn xem dùng chung).
final _pdfCache = <String, Future<File>>{};
Future<File> _pdfFile(MeetPresentation p, String token) => _pdfCache.putIfAbsent(p.id, () async {
      final dir = Directory('${(await getTemporaryDirectory()).path}/meet-present');
      await dir.create(recursive: true);
      final f = File('${dir.path}/${p.id}.pdf');
      if (await f.exists() && await f.length() > 0) return f;
      final r = await http.get(Uri.parse('$kPushUrl${p.url}'), headers: {'Authorization': 'Bearer $token', 'User-Agent': kUserAgent});
      if (r.statusCode != 200) {
        _pdfCache.remove(p.id);
        throw Exception(tr('Tài liệu không còn được trình chiếu'));
      }
      return f.writeAsBytes(r.bodyBytes);
    });

/// Màn xem bài trình chiếu (khung lớn của màn hình họp, hoặc toàn màn hình xoay ngang trên điện thoại).
class MeetPresentView extends StatefulWidget {
  final CallService call;
  final bool fullscreen;
  const MeetPresentView({super.key, required this.call, this.fullscreen = false});
  @override
  State<MeetPresentView> createState() => _MeetPresentViewState();
}

class _MeetPresentViewState extends State<MeetPresentView> {
  /// Người xem đang tự xem trang khác (không theo người trình chiếu).
  bool _free = false;
  int _myPage = 1;
  bool _laserMode = false;
  Offset? _laser; // tỉ lệ 0..1 trong trang
  Timer? _laserHide;
  StreamSubscription? _laserSub;

  @override
  void initState() {
    super.initState();
    _laserSub = widget.call.laser.stream.listen((l) {
      if (!mounted) return;
      _laserHide?.cancel();
      setState(() => _laser = l.$3 ? Offset(l.$1, l.$2) : null);
      _laserHide = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _laser = null);
      });
    });
    if (widget.fullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _laserSub?.cancel();
    _laserHide?.cancel();
    if (widget.fullscreen) {
      SystemChrome.setPreferredOrientations(const []);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final call = widget.call;
    final raw = call.roomPresent;
    if (raw == null) {
      if (widget.fullscreen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const ColoredBox(color: Colors.black);
    }
    final p = MeetPresentation(raw);
    final presenter = p.by == app.me?.id;
    final control = presenter || call.canModerate;
    return ColoredBox(
      color: Colors.black,
      child: FutureBuilder<File>(
        future: _pdfFile(p, app.token),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}', style: const TextStyle(color: Colors.white70)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return PdfDocumentViewBuilder.file(
            snap.data!.path,
            builder: (context, doc) {
              if (doc == null) return const Center(child: CircularProgressIndicator());
              final n = doc.pages.length;
              final page = (_free && !presenter ? _myPage : p.page).clamp(1, n);
              final pg = doc.pages[page - 1];
              return LayoutBuilder(builder: (context, box) {
                // Khung trang vừa khít (giữ tỉ lệ), dùng cho cả bút laser.
                final s = (box.maxWidth / pg.width) < (box.maxHeight / pg.height) ? box.maxWidth / pg.width : box.maxHeight / pg.height;
                final w = pg.width * s, h = pg.height * s;
                final rect = Rect.fromLTWH((box.maxWidth - w) / 2, (box.maxHeight - h) / 2, w, h);
                void go(int to) {
                  to = to.clamp(1, n);
                  if (control && (!_free || presenter)) {
                    call.presentPage(to);
                  } else {
                    setState(() {
                      _free = true;
                      _myPage = to;
                    });
                  }
                }

                void point(Offset at) {
                  if (!presenter || !_laserMode || !rect.contains(at)) return;
                  final x = (at.dx - rect.left) / rect.width, y = (at.dy - rect.top) / rect.height;
                  setState(() => _laser = Offset(x, y));
                  call.sendLaser(x, y);
                }

                return Stack(children: [
                  Positioned.fromRect(rect: rect, child: PdfPageView(document: doc, pageNumber: page, backgroundColor: Colors.white)),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _laserMode
                          ? null
                          : (d) {
                              final v = d.primaryVelocity ?? 0;
                              if (v.abs() > 200) go(page + (v < 0 ? 1 : -1));
                            },
                      onPanStart: _laserMode ? (d) => point(d.localPosition) : null,
                      onPanUpdate: _laserMode ? (d) => point(d.localPosition) : null,
                      onTapDown: _laserMode ? (d) => point(d.localPosition) : null,
                    ),
                  ),
                  if (_laser != null)
                    Positioned(
                      left: rect.left + _laser!.dx * rect.width - 8,
                      top: rect.top + _laser!.dy * rect.height - 8,
                      child: IgnorePointer(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                              color: Color(0xFFFF2D2D), shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0xBBFF2D2D), blurRadius: 12, spreadRadius: 3)]),
                        ),
                      ),
                    ),
                  // Tên bài, người trình chiếu, trang.
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _chip('📄 ${p.name} · ${p.byName} · $page/$n'),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: Center(
                      child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                        if (control) ...[
                          _btn(Icons.chevron_left_rounded, tr('Trang trước'), page > 1 ? () => go(page - 1) : null),
                          _btn(Icons.chevron_right_rounded, tr('Trang sau'), page < n ? () => go(page + 1) : null),
                        ],
                        if (presenter)
                          _btn(Icons.highlight_alt_rounded, _laserMode ? tr('Tắt bút laser') : tr('Bút laser'), () => setState(() => _laserMode = !_laserMode),
                              on: _laserMode),
                        if (_free && !presenter)
                          ActionChip(
                            avatar: const Icon(Icons.undo_rounded, size: 18),
                            label: Text(tr('Về trang người trình chiếu')),
                            onPressed: () => setState(() => _free = false),
                          ),
                        if (!widget.fullscreen && (Platform.isAndroid || Platform.isIOS))
                          _btn(Icons.fullscreen_rounded, tr('Toàn màn hình'), () {
                            Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                                builder: (_) => Scaffold(backgroundColor: Colors.black, body: MeetPresentView(call: call, fullscreen: true))));
                          }),
                        if (widget.fullscreen) _btn(Icons.fullscreen_exit_rounded, tr('Thoát toàn màn hình'), () => Navigator.of(context).maybePop()),
                        if (control)
                          _btn(Icons.stop_screen_share_outlined, tr('Dừng trình chiếu'), () async {
                            final err = await call.presentStop();
                            if (err != null && context.mounted) meetToast(context, err);
                          }, danger: true),
                      ]),
                    ),
                  ),
                ]);
              });
            },
          );
        },
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
      );

  Widget _btn(IconData icon, String tip, VoidCallback? onTap, {bool on = false, bool danger = false}) => Tooltip(
        message: tip,
        child: Material(
          color: danger ? const Color(0xFFB3261E) : (on ? const Color(0xFF2BB3A3) : Colors.black.withValues(alpha: .6)),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: onTap == null ? Colors.white30 : Colors.white, size: 24)),
          ),
        ),
      );
}
