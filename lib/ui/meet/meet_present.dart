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
import '../pages/pages_api.dart' show PagesApi;
import 'meet_home.dart' show meetToast;
import 'meet_ink.dart';

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
  try {
    final r = await pickPresentPdf(context, call);
    if (r == null) return;
    final err = await call.presentUpload(r.$1, r.$2, r.$3);
    if (err != null && context.mounted) meetToast(context, tr('Không trình chiếu được: {0}', [err]));
  } catch (e) {
    if (context.mounted) meetToast(context, tr('Không trình chiếu được: {0}', [e]));
  }
}

/// Chọn tài liệu (Drive, tệp trong nhóm, tệp trên máy) và đổi sang PDF: (tệp PDF, tên, số trang), null = bỏ.
/// Dùng chung cho trình chiếu nhanh và trang "Tài liệu" của Họp (mới).
Future<(File, String, int)?> pickPresentPdf(BuildContext context, CallService call) async {
  final app = context.read<AppState>();
  final src = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF2D2E31),
    constraints: const BoxConstraints(maxWidth: 520),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(
              tr('Trình chiếu tài liệu'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              tr('PowerPoint, PDF, Word, Excel. Mọi người, kể cả TV, xem cùng trang với bạn mà không cần chia sẻ màn hình.'),
              style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 13),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined, color: Colors.white),
            title: Text(tr('Từ Drive'), style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'drive'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file_rounded, color: Colors.white),
            title: Text(tr('Tệp trong nhóm của cuộc họp'), style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'chat'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded, color: Colors.white),
            title: Text(tr('Từ máy này'), style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, 'device'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (src == null || !context.mounted) return null;
  final tmp = Directory('${(await getTemporaryDirectory()).path}/meet-present');
  await tmp.create(recursive: true);
  File? local;
  String name = '';
  File? pdf;
  switch (src) {
    case 'drive':
      if (!context.mounted) return null;
      final r = await pickFromDrive(context, remoteOnly: true, extensions: _exts, single: true);
      final it = r?.remote.firstOrNull;
      final s = r?.session;
      if (it == null || s == null) return null;
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
      if (ch == null || !context.mounted) return null;
      final f = await _pickChatFile(context, app, ch);
      if (f == null) return null;
      name = f.name;
      if (context.mounted) meetToast(context, tr('Đang chuẩn bị tài liệu…'));
      local = await app.api.downloadFile(f, tmp);
    case 'device':
      final r = (await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _exts)).firstOrNull;
      final path = r?.path;
      if (r == null || path == null) return null;
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
  if (pdf == null) return null;
  var pages = 0;
  try {
    final doc = await PdfDocument.openFile(pdf.path);
    pages = doc.pages.length;
    await doc.dispose();
  } catch (_) {}
  return (pdf, name, pages);
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
              child: Text(tr('Nhóm của cuộc họp chưa có tài liệu nào (PDF, Word, Excel, PowerPoint).'), style: const TextStyle(color: Colors.white70)),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                for (final f in files.take(60))
                  ListTile(
                    leading: const Icon(Icons.description_outlined, color: Colors.white),
                    title: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text('${(f.size / 1024 / 1024).toStringAsFixed(1)} MB', style: const TextStyle(color: Color(0xFF9AA0A6))),
                    onTap: () => Navigator.pop(ctx, f),
                  ),
              ],
            ),
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

  /// Ô nhỏ (dải người / lưới): chỉ hiện trang, không có nút.
  final bool compact;
  const MeetPresentView({super.key, required this.call, this.fullscreen = false, this.compact = false});
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
  // Nét vẽ chú thích (tài liệu là trang của Họp mới: present.page_id): {"<số trang>": [nét…]}.
  String? _pageId;
  Map _ink = const {};
  StreamSubscription? _fx;
  bool _inkMode = false;
  String _tool = 'pen';
  String _color = inkColors.first;
  Map<String, dynamic>? _cur;
  bool _saving = false;

  Future<void> _loadInk() async {
    final id = _pageId;
    if (id == null) return setState(() => _ink = const {});
    try {
      final d = await PagesApi(widget.call).get(id);
      if (mounted && _pageId == id) setState(() => _ink = (d.view['ink'] as Map?) ?? const {});
    } catch (_) {}
  }

  Future<void> _inkAct(String action, int page, [Map<String, dynamic>? stroke]) async {
    final id = _pageId;
    if (id == null) return;
    try {
      final (v, _) = await PagesApi(widget.call).act(id, action, {'page': page, 'stroke': ?stroke});
      if (mounted) setState(() => _ink = (v['ink'] as Map?) ?? const {});
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  /// Lưu bản PDF mới có nét chú thích vào nhóm chat của cuộc họp (bản gốc giữ nguyên).
  Future<void> _saveAnnotated(AppState app, PdfDocument doc, MeetPresentation p) async {
    final ch = widget.call.channelId;
    if (ch == null) return;
    setState(() => _saving = true);
    meetToast(context, tr('Đang tạo bản PDF có chú thích…'));
    try {
      final bytes = await annotatedPdf(doc, _ink);
      final base = p.name.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '');
      final name = '$base (chú thích).pdf';
      final ids = await app.api.uploadFile(ch, name, bytes);
      await app.api.createPost({'channel_id': ch, 'message': tr('📝 Bản có chú thích: {0}', [base]), 'file_ids': ids});
      if (mounted) meetToast(context, tr('Đã gửi "{0}" vào nhóm chat', [name]));
    } catch (e) {
      if (mounted) meetToast(context, tr('Không lưu được: {0}', [e]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fx = widget.call.fxEvents.stream.listen((m) {
      if (m['t'] == 'fx_page' && m['page'] == _pageId && _cur == null) _loadInk();
    });
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

  String? _docId;
  Future<PdfDocument>? _docF;
  PdfDocument? _doc;

  /// Mở tài liệu của bài [p] một lần (đổi bài thì đóng bài cũ).
  Future<PdfDocument> _open(MeetPresentation p, String token) {
    if (_docId == p.id && _docF != null) return _docF!;
    _doc?.dispose();
    _doc = null;
    _docId = p.id;
    return _docF = _pdfFile(p, token).then((f) async {
      final d = await PdfDocument.openFile(f.path);
      if (!mounted || _docId != p.id) {
        await d.dispose();
        throw StateError('stale');
      }
      return _doc = d;
    });
  }

  @override
  void dispose() {
    _doc?.dispose();
    _fx?.cancel();
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
    final pageId = raw['page_id'] as String?;
    if (pageId != _pageId) {
      _pageId = pageId;
      _inkMode = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _loadInk() : null);
    }
    return ColoredBox(
      color: Colors.black,
      // Tài liệu mở một lần cho mỗi bài và giữ nguyên qua các lần vẽ lại (màn hình họp vẽ lại mỗi giây, metadata, người
      // nói…): mở lại mỗi lần làm trang PDF nháy trên app.
      child: FutureBuilder<PdfDocument>(
        future: _open(p, app.token),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${snap.error}', style: const TextStyle(color: Colors.white70)));
          }
          final doc = snap.data;
          if (doc == null) return const Center(child: CircularProgressIndicator());
          final n = doc.pages.length;
          final page = (_free && !presenter ? _myPage : p.page).clamp(1, n);
          final pg = doc.pages[page - 1];
          return LayoutBuilder(
            builder: (context, box) {
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

              Offset norm(Offset at) => Offset(((at.dx - rect.left) / rect.width).clamp(0.0, 1.0), ((at.dy - rect.top) / rect.height).clamp(0.0, 1.0));
              List<double> pt(Offset at) {
                final o = norm(at);
                return [o.dx, o.dy];
              }

              void inkStart(Offset at) {
                if (_tool == 'text' || !rect.contains(at)) return;
                setState(() => _cur = {'t': _tool, 'c': _color, 'w': _tool == 'pen' ? .004 : .003, 'p': [pt(at)]});
              }

              void inkMove(Offset at) {
                final c = _cur;
                if (c == null) return;
                setState(() {
                  final ps = c['p'] as List;
                  if (_tool == 'pen') {
                    if (ps.length < 600) ps.add(pt(at));
                  } else {
                    c['p'] = [ps.first, pt(at)];
                  }
                });
              }

              void inkEnd() {
                final c = _cur;
                if (c == null) return;
                // Hiện ngay trên máy mình, gửi lên relay (mọi máy, TV nhận qua tin fx_page).
                setState(() {
                  _ink = {..._ink, '$page': [...((_ink['$page'] as List?) ?? const []), c]};
                  _cur = null;
                });
                _inkAct('ink', page, c);
              }

              Future<void> inkText(Offset at) async {
                if (!rect.contains(at)) return;
                final ctl = TextEditingController();
                final t = await showDialog<String>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text(tr('Thêm chữ')),
                    content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
                      FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Thêm'))),
                    ],
                  ),
                );
                if ((t ?? '').trim().isEmpty) return;
                final c = {'t': 'text', 'c': _color, 'w': .004, 's': t!.trim(), 'p': [pt(at)]};
                setState(() => _ink = {..._ink, '$page': [...((_ink['$page'] as List?) ?? const []), c]});
                await _inkAct('ink', page, c);
              }

              void point(Offset at) {
                if (!presenter || !_laserMode || !rect.contains(at)) return;
                final x = (at.dx - rect.left) / rect.width, y = (at.dy - rect.top) / rect.height;
                setState(() => _laser = Offset(x, y));
                call.sendLaser(x, y);
              }

              return Stack(
                children: [
                  Positioned.fromRect(
                    rect: rect,
                    child: RepaintBoundary(
                      child: PdfPageView(key: ValueKey('${p.id}:$page'), document: doc, pageNumber: page, backgroundColor: Colors.white),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: _laserMode
                          ? null
                          : (d) {
                              final v = d.primaryVelocity ?? 0;
                              if (v.abs() > 200) go(page + (v < 0 ? 1 : -1));
                            },
                      onPanStart: _inkMode ? (d) => inkStart(d.localPosition) : _laserMode ? (d) => point(d.localPosition) : null,
                      onPanUpdate: _inkMode ? (d) => inkMove(d.localPosition) : _laserMode ? (d) => point(d.localPosition) : null,
                      onPanEnd: _inkMode ? (_) => inkEnd() : null,
                      onTapUp: _inkMode && _tool == 'text' ? (d) => inkText(d.localPosition) : null,
                      onTapDown: _laserMode && !_inkMode ? (d) => point(d.localPosition) : null,
                    ),
                  ),
                  // Nét chú thích của trang (mọi người thấy).
                  Positioned.fromRect(
                    rect: rect,
                    child: IgnorePointer(child: CustomPaint(painter: InkPainter((_ink['$page'] as List?) ?? const [], _cur))),
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
                            color: Color(0xFFFF2D2D),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Color(0xBBFF2D2D), blurRadius: 12, spreadRadius: 3)],
                          ),
                        ),
                      ),
                    ),
                  if (widget.compact)
                    const SizedBox.shrink()
                  else
                    // Tên bài, người trình chiếu, trang.
                    Positioned(left: 10, top: 10, child: _chip('📄 ${p.name} · ${p.byName} · $page/$n')),
                  if (!widget.compact)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: Center(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            if (control) ...[
                              _btn(Icons.chevron_left_rounded, tr('Trang trước'), page > 1 ? () => go(page - 1) : null),
                              _btn(Icons.chevron_right_rounded, tr('Trang sau'), page < n ? () => go(page + 1) : null),
                            ],
                            if (control && pageId != null)
                              _btn(
                                Icons.draw_rounded,
                                _inkMode ? tr('Thôi vẽ') : tr('Vẽ chú thích'),
                                () => setState(() {
                                  _inkMode = !_inkMode;
                                  if (_inkMode) {
                                    _laserMode = false;
                                    _laser = null;
                                  }
                                }),
                                on: _inkMode,
                              ),
                            if (presenter)
                              _btn(
                                Icons.highlight_alt_rounded,
                                _laserMode ? tr('Tắt bút laser') : tr('Bút laser'),
                                () {
                                  // Tắt bút: xoá chấm trên máy mình và báo mọi máy (TV, người xem) tắt ngay.
                                  if (_laserMode) {
                                    call.sendLaser(_laser?.dx ?? 0, _laser?.dy ?? 0, on: false);
                                    _laserHide?.cancel();
                                  }
                                  setState(() {
                                    _laserMode = !_laserMode;
                                    if (!_laserMode) _laser = null;
                                  });
                                },
                                on: _laserMode,
                              ),
                            if (_free && !presenter)
                              ActionChip(
                                avatar: const Icon(Icons.undo_rounded, size: 18),
                                label: Text(tr('Về trang người trình chiếu')),
                                onPressed: () => setState(() => _free = false),
                              ),
                            if (!widget.fullscreen && (Platform.isAndroid || Platform.isIOS))
                              _btn(Icons.fullscreen_rounded, tr('Toàn màn hình'), () {
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      backgroundColor: Colors.black,
                                      body: MeetPresentView(call: call, fullscreen: true),
                                    ),
                                  ),
                                );
                              }),
                            if (widget.fullscreen) _btn(Icons.fullscreen_exit_rounded, tr('Thoát toàn màn hình'), () => Navigator.of(context).maybePop()),
                            if (control)
                              _btn(Icons.stop_screen_share_outlined, tr('Dừng trình chiếu'), () async {
                                final err = await call.presentStop();
                                if (err != null && context.mounted) meetToast(context, err);
                              }, danger: true),
                          ],
                        ),
                      ),
                    ),
                  // Công cụ vẽ: bút / hình / chữ, màu, hoàn tác, xoá trang, lưu bản PDF có chú thích vào nhóm chat.
                  if (_inkMode && !widget.compact)
                    Positioned(
                      top: 46,
                      left: 8,
                      right: 8,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Material(
                            color: Colors.black.withValues(alpha: .7),
                            borderRadius: BorderRadius.circular(24),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                for (final e in inkTools.entries)
                                  IconButton(
                                    tooltip: switch (e.key) {
                                      'pen' => tr('Bút'),
                                      'rect' => tr('Hình chữ nhật'),
                                      'circle' => tr('Hình tròn'),
                                      'arrow' => tr('Mũi tên'),
                                      _ => tr('Chữ'),
                                    },
                                    isSelected: _tool == e.key,
                                    style: IconButton.styleFrom(backgroundColor: _tool == e.key ? Colors.white24 : null),
                                    icon: Icon(e.value, color: Colors.white),
                                    onPressed: () => setState(() => _tool = e.key),
                                  ),
                                Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 4)),
                                for (final c in inkColors)
                                  InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => setState(() => _color = c),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      decoration: BoxDecoration(
                                        color: inkColor(c),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: _color == c ? Colors.white : Colors.white30, width: _color == c ? 3 : 1),
                                      ),
                                    ),
                                  ),
                                Container(width: 1, height: 24, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 4)),
                                IconButton(tooltip: tr('Hoàn tác'), icon: const Icon(Icons.undo_rounded, color: Colors.white), onPressed: () => _inkAct('ink_undo', page)),
                                IconButton(tooltip: tr('Xoá nét trên trang này'), icon: const Icon(Icons.layers_clear_rounded, color: Colors.white), onPressed: () => _inkAct('ink_clear', page)),
                                IconButton(
                                  tooltip: tr('Lưu thành PDF mới vào nhóm chat'),
                                  icon: _saving
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.save_alt_rounded, color: Colors.white),
                                  onPressed: _saving ? null : () => _saveAnnotated(app, doc, p),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
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
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: onTap == null ? Colors.white30 : Colors.white, size: 24),
        ),
      ),
    ),
  );
}
