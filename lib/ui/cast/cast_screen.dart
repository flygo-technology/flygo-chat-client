// "Đưa lên màn hình" dùng chung cho mọi app: quét / gõ mã trên màn hình (hello.<tên miền>), ghép, đẩy tài liệu lên,
// điện thoại thành điều khiển (trang trước / sau, laser khi giữ và kéo trên ảnh trang, màn đen, dừng).
// Màn hình đang có người chiếu thì vào hàng chờ; đến lượt thì tài liệu tự lên.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../call_screen.dart' show ScreenPicker;
import '../mini_app_view.dart' show ScanOncePage;
import '../theme.dart' show toast;
import 'cast_api.dart';

/// Tải tệp để chiếu (vd Drive: đổi Office sang PDF). [onProgress]: đã tải / tổng số byte.
typedef CastLoader = Future<File> Function(void Function(int got, int total)? onProgress);

/// Nội dung đưa lên màn hình: [type] pdf | image | video, [mime] loại tệp gửi lên trạm.
class CastContent {
  final String type, mime, name, app;
  final CastLoader load;

  /// PDF tự lật trang mỗi [auto] giây (0 = không).
  final int auto;
  const CastContent({required this.type, required this.mime, required this.name, required this.load, this.app = '', this.auto = 0});
  const CastContent.pdf({required this.name, required this.load, this.app = '', this.auto = 0}) : type = 'pdf', mime = 'application/pdf';

  /// Chiếu màn hình máy tính (chọn màn hình / cửa sổ sau khi ghép).
  CastContent.mirror({this.name = 'Màn hình máy tính'}) : type = 'mirror', mime = '', app = 'mirror', auto = 0, load = _noLoad;
  static Future<File> _noLoad(void Function(int, int)? _) => throw UnsupportedError('mirror');
}

bool get _desktop => !(Platform.isAndroid || Platform.isIOS);

/// Ô "Đưa lên màn hình" (Trang chủ): chọn tệp trên máy (PDF, ảnh, video) hoặc chia sẻ màn hình máy tính.
Future<void> castFromDevice(BuildContext context) async {
  final how = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sh) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(tr('Đưa lên màn hình'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            subtitle: Text(tr('Mở hello.flygo.vn trên TV / máy chiếu, rồi chọn nội dung.')),
          ),
          if (_desktop)
            ListTile(leading: const Icon(Icons.screen_share_rounded), title: Text(tr('Chia sẻ màn hình máy tính')), onTap: () => Navigator.pop(sh, 'screen')),
          ListTile(leading: const Icon(Icons.file_open_rounded), title: Text(tr('Chọn tệp (PDF, ảnh, video)')), onTap: () => Navigator.pop(sh, 'file')),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(tr('Tài liệu Office, slide: mở trong Drive rồi bấm ⋯ → Đưa lên màn hình')),
            enabled: false,
          ),
        ],
      ),
    ),
  );
  if (how == null || !context.mounted) return;
  if (how == 'screen') return castToScreen(context, CastContent.mirror(name: tr('Màn hình máy tính')));
  final r = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4', 'm4v', 'webm', 'mov'],
  );
  final f = r.firstOrNull;
  if (f?.path == null || !context.mounted) return;
  final k = castableByExt(f!.name);
  if (k == null) return;
  final file = File(f.path!);
  await castToScreen(context, CastContent(type: k.type, mime: k.mime, name: f.name, app: 'device', load: (_) async => file));
}

/// Loại tệp chiếu được theo đuôi tệp (ảnh / video trình duyệt TV mở được). Null: không chiếu được.
({String type, String mime})? castableByExt(String fileName) {
  final e = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return switch (e) {
    'pdf' => (type: 'pdf', mime: 'application/pdf'),
    'jpg' || 'jpeg' => (type: 'image', mime: 'image/jpeg'),
    'png' => (type: 'image', mime: 'image/png'),
    'webp' => (type: 'image', mime: 'image/webp'),
    'gif' => (type: 'image', mime: 'image/gif'),
    'mp4' || 'm4v' => (type: 'video', mime: 'video/mp4'),
    'webm' => (type: 'video', mime: 'video/webm'),
    'mov' => (type: 'video', mime: 'video/quicktime'),
    _ => null,
  };
}

/// Chiếu một tài liệu PDF lên màn hình.
Future<void> castPdfToScreen(BuildContext context, {required String name, required CastLoader load, String app = ''}) =>
    castToScreen(context, CastContent.pdf(name: name, load: load, app: app));

/// Đưa [c] lên màn hình: hỏi mã màn hình, ghép, mở trang điều khiển.
Future<void> castToScreen(BuildContext context, CastContent c) async {
  AppState? app0;
  try {
    app0 = context.read<AppState>();
  } catch (_) {} // cửa sổ con (Drive riêng) không có phiên chat
  final m = ScaffoldMessenger.maybeOf(context);
  if (app0 == null) {
    m?.showSnackBar(toast(Text(tr('Mở Flygo Chat để đưa lên màn hình'))));
    return;
  }
  final token = app0.token;
  final s = await pickAndPair(context, token);
  if (s == null || !context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(
    AppPageRoute(
      builder: (_) => CastRemotePage(session: s, content: c),
    ),
  );
}

/// "Thêm màn hình" trong cuộc họp: chọn màn hình hello (danh sách / quét mã) rồi đưa vào cuộc họp [code] / [channelId].
/// Màn hình khoá cho thành viên cuộc họp, không chiếu gì thì hiện giao diện phòng họp; cuộc họp kết thúc thì tự mở.
/// Trả về true nếu đã thêm.
Future<bool> addScreenToMeeting(BuildContext context, {String? code, String? channelId}) async {
  AppState? app0;
  try {
    app0 = context.read<AppState>();
  } catch (_) {}
  if (app0 == null || (code == null && channelId == null)) return false;
  final m = ScaffoldMessenger.maybeOf(context);
  final s = await pickAndPair(context, app0.token);
  if (s == null) return false;
  try {
    await s.joinMeeting(code: code, channelId: channelId);
    m?.showSnackBar(toast(Text(tr('Đã thêm «{0}» vào cuộc họp', [s.first.screen]))));
    return true;
  } catch (e) {
    await s.stop();
    m?.showSnackBar(toast(Text(tr('Không thêm được màn hình: {0}', ['$e']))));
    return false;
  }
}

/// Chọn màn hình (danh sách màn hình của công ty, hoặc quét / gõ mã) rồi ghép. Màn hình đang khoá: hỏi "Xin dùng".
Future<CastSession?> pickAndPair(BuildContext context, String token) async {
  final m = ScaffoldMessenger.maybeOf(context);
  final pick = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sh) => _ScreenListSheet(token: token),
  );
  if (pick == null || !context.mounted) return null;
  String? code, screenId;
  if (pick == '#code') {
    code = await askScreenCode(context, direct: true);
    if (code == null) return null;
  } else {
    screenId = pick;
  }
  try {
    return await CastSession.pair(kServerUrl, token, code: code, screenId: screenId);
  } on CastError catch (e) {
    if (!context.mounted) return null;
    if (e.locked && e.screenId != null) {
      final ask = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          icon: const Icon(Icons.lock_rounded, size: 36),
          title: Text(tr('Màn hình đang được dùng')),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Đóng'))),
            if ((e.body?['lock'] as Map?)?['meeting'] == null) FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Xin dùng'))),
          ],
        ),
      );
      if (ask == true) {
        try {
          final r = await CastSession.screenAction(kServerUrl, token, e.screenId!, 'request');
          m?.showSnackBar(toast(Text(r['notified'] == true ? tr('Đã báo người đang dùng màn hình') : tr('Người khoá không mở app lúc này, thử lại sau'))));
        } catch (x) {
          m?.showSnackBar(toast(Text('$x')));
        }
      }
      return null;
    }
    if (e.status == 428) {
      // Màn hình chưa xác nhận (mở ngoài văn phòng): quét mã một lần.
      m?.showSnackBar(toast(Text(e.message)));
      final c2 = await askScreenCode(context, direct: true);
      if (c2 == null || !context.mounted) return null;
      try {
        return await CastSession.pair(kServerUrl, token, code: c2);
      } catch (x) {
        m?.showSnackBar(toast(Text(tr('Không ghép được với màn hình: {0}', ['$x']))));
        return null;
      }
    }
    m?.showSnackBar(toast(Text(tr('Không ghép được với màn hình: {0}', ['$e']))));
    return null;
  } catch (e) {
    m?.showSnackBar(toast(Text(tr('Không ghép được với màn hình: {0}', ['$e']))));
    return null;
  }
}

/// Danh sách màn hình của công ty: rảnh / đang dùng / đang khoá / trong cuộc họp / chưa xác nhận. Trả về id màn hình
/// hoặc '#code' (quét / nhập mã).
class _ScreenListSheet extends StatefulWidget {
  final String token;
  const _ScreenListSheet({required this.token});
  @override
  State<_ScreenListSheet> createState() => _ScreenListSheetState();
}

class _ScreenListSheetState extends State<_ScreenListSheet> {
  List<CastScreen>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await CastSession.screens(kServerUrl, widget.token);
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final l = _list;
    final online = l?.where((x) => x.online).toList() ?? const <CastScreen>[];
    String sub(CastScreen x) => switch (x.status) {
      _ when !x.online => tr('đang tắt'),
      _ when !x.approved => tr('⚠ chưa xác nhận: quét mã trên màn hình một lần'),
      'meeting' => tr('Cuộc họp «{0}» · chỉ thành viên', ['${(x.lock?['meeting'] as Map?)?['title'] ?? ''}']),
      'locked' => tr('Đang khoá bởi {0}', ['${x.lock?['by_name'] ?? ''}']),
      'casting' => x.queue > 0 ? tr('Đang chiếu: {0} · {1} người chờ', [x.nowBy, '${x.queue}']) : tr('Đang chiếu: {0}', [x.nowBy]),
      _ => x.lock?['mine'] == true ? tr('Bạn đang khoá') : tr('Đang rảnh'),
    };
    Color dot(CastScreen x) => !x.online
        ? Colors.grey
        : !x.approved
        ? Colors.amber
        : switch (x.status) {
            'meeting' => Colors.indigo,
            'locked' => Colors.red,
            'casting' => Colors.orange,
            _ => Colors.green,
          };
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(tr('Đưa lên màn hình'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                tr('Màn hình của công ty đang mở {0}', ['hello.${Uri.parse(kServerUrl).host.split('.').skip(1).join('.')}']),
                style: TextStyle(color: th.hintColor, fontSize: 13),
              ),
            ),
            if (l == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: th.colorScheme.error)),
              ),
            if (l != null && l.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(tr('Chưa có màn hình nào online. Mở hello trên TV / máy chiếu.'), style: TextStyle(color: th.hintColor)),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final x in [...online, ...?l?.where((x) => !x.online)])
                    ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.tv_rounded, size: 30),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: dot(x),
                                shape: BoxShape.circle,
                                border: Border.all(color: th.colorScheme.surface, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(sub(x)),
                      enabled: x.online,
                      trailing: x.online
                          ? Text(
                              !x.approved
                                  ? tr('Quét')
                                  : x.status == 'locked'
                                  ? tr('Xin dùng')
                                  : x.status == 'casting'
                                  ? tr('Xếp hàng')
                                  : x.status == 'meeting'
                                  ? tr('Chiếu')
                                  : tr('Chiếu'),
                              style: TextStyle(color: th.colorScheme.primary, fontWeight: FontWeight.w600),
                            )
                          : null,
                      onTap: () => Navigator.pop(context, x.approved ? x.id : '#code'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, '#code'),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(tr('Quét mã / nhập mã màn hình')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mã màn hình: điện thoại quét QR (hoặc gõ), máy tính gõ mã hiện dưới QR. Null nếu huỷ.
Future<String?> askScreenCode(BuildContext context, {bool direct = false}) async {
  final phone = Platform.isAndroid || Platform.isIOS;
  String? raw;
  if (phone && direct) {
    raw = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(builder: (_) => const ScanOncePage()));
    if (raw == null && context.mounted) raw = await _typeCode(context);
  } else if (phone) {
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sh) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Đưa lên màn hình'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(tr('Mở hello.flygo.vn trên TV / máy chiếu rồi quét mã QR trên đó.'), style: TextStyle(color: Theme.of(sh).hintColor)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(sh, 'scan'),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(tr('Quét mã trên màn hình')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: () => Navigator.pop(sh, 'type'), icon: const Icon(Icons.keyboard_rounded), label: Text(tr('Nhập mã'))),
            ],
          ),
        ),
      ),
    );
    if (how == null || !context.mounted) return null;
    if (how == 'scan') raw = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(builder: (_) => const ScanOncePage()));
  }
  if (raw == null && context.mounted) raw = await _typeCode(context);
  if (raw == null || !context.mounted) return null;
  final other = foreignScreenHost(raw, kServerUrl);
  final code = parseScreenCode(raw);
  if (other != null || code == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      toast(
        Text(
          other != null ? tr('Màn hình {0} thuộc máy chủ khác, hãy đăng nhập máy chủ đó', [other]) : tr('Đây không phải mã màn hình (8 ký tự, vd K7QM-2XPR)'),
        ),
      ),
    );
    return null;
  }
  return code;
}

Future<String?> _typeCode(BuildContext context) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(tr('Nhập mã màn hình')),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 22, letterSpacing: 3, fontFamily: 'monospace'),
          decoration: InputDecoration(hintText: 'K7QM-2XPR', helperText: tr('Mã hiện dưới QR trên màn hình')),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Kết nối'))),
      ],
    ),
  );
}

// ---------------------------------------------------------------- trang điều khiển
class CastRemotePage extends StatefulWidget {
  final CastSession session;
  final CastContent content;
  const CastRemotePage({super.key, required this.session, required this.content});
  @override
  State<CastRemotePage> createState() => _CastRemotePageState();
}

class _CastRemotePageState extends State<CastRemotePage> {
  late CastState st = widget.session.first;
  StreamSubscription<CastState>? _sub;
  PdfDocument? _doc;
  File? _pdf;
  bool _sent = false, _sending = false, _stopped = false;
  double? _progress;
  String? _error;
  int _page = 1;
  Offset? _laser; // vị trí laser trên ảnh trang (0..1)

  CastSession get s => widget.session;
  CastContent get c => widget.content;
  Timer? _clock; // video: cập nhật vị trí mỗi giây
  lk.Room? _mirror; // chiếu màn hình máy tính
  String _requestFrom = ''; // người vừa bấm "Xin dùng"
  bool _locking = false;
  int get _pages => _doc?.pages.length ?? 0;

  @override
  void initState() {
    super.initState();
    _sub = s.events().listen((v) {
      if (!mounted) return;
      if (v.role == 'request') {
        // Ai đó xin dùng màn hình: hiện dải báo (nút Nhường), không đổi trạng thái.
        HapticFeedback.mediumImpact();
        setState(() => _requestFrom = v.requestFrom);
        return;
      }
      final wasPresenting = st.presenting;
      setState(() => st = v);
      if (v.presenting && !wasPresenting) HapticFeedback.mediumImpact();
      _maybeSend();
    });
    _maybeSend();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    _mirror?.disconnect();
    if (!_stopped) s.stop();
    _doc?.dispose();
    super.dispose();
  }

  /// Đến lượt chiếu: tải PDF (nếu chưa) rồi đẩy lên màn hình.
  Future<void> _maybeSend() async {
    if (!st.presenting || _sent || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (c.type == 'mirror') {
        await _startMirror();
        _sent = true;
        return;
      }
      _pdf ??= await c.load((got, total) {
        if (mounted) setState(() => _progress = total > 0 ? got / total : null);
      });
      if (c.type == 'pdf') _doc ??= await PdfDocument.openFile(_pdf!.path);
      if (mounted) setState(() => _progress = null);
      await s.showFile(_pdf!, type: c.type, mime: c.mime, name: c.name, pages: _pages, app: c.app, auto: c.auto);
      if (c.type == 'video') {
        _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
      _page = 1;
      _sent = true;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
        });
      }
    }
  }

  /// Chọn màn hình / cửa sổ rồi phát vào phòng LiveKit của màn hình (chọn lại thì đổi nguồn).
  Future<void> _startMirror() async {
    final id = await showDialog<String>(context: context, builder: (_) => const ScreenPicker());
    if (id == null) throw tr('Chưa chọn màn hình để chia sẻ');
    var room = _mirror;
    if (room == null) {
      final j = await s.mirror(c.name);
      // Máy LiveKit nhỏ: màn hình chiếu 15 khung / giây, tối đa ~1,5 Mbps, không simulcast.
      room = lk.Room(
        roomOptions: const lk.RoomOptions(
          defaultVideoPublishOptions: lk.VideoPublishOptions(
            simulcast: false,
            screenShareEncoding: lk.VideoEncoding(maxBitrate: 1500 * 1000, maxFramerate: 15),
          ),
        ),
      );
      await room.connect(j.url, j.token);
      _mirror = room;
    } else {
      await room.localParticipant?.setScreenShareEnabled(false);
    }
    await room.localParticipant?.setScreenShareEnabled(true, screenShareCaptureOptions: lk.ScreenShareCaptureOptions(sourceId: id, maxFrameRate: 15));
  }

  Future<void> _go(int p) async {
    if (!st.presenting || !_sent || _pages == 0) return;
    final n = p.clamp(1, _pages);
    if (n == _page) return;
    setState(() => _page = n);
    try {
      await s.page(n);
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$e')));
    }
  }

  Future<void> _stop() async {
    _stopped = true;
    await s.stop();
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmLeave() async {
    if (st.ended) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(st.presenting ? tr('Dừng chiếu?') : tr('Rời hàng chờ?')),
        content: Text(
          st.presenting ? tr('Màn hình sẽ về lại mã QR (hoặc chuyển cho người đang chờ).') : tr('Bạn sẽ không còn trong hàng chờ của màn hình này.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Ở lại'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(st.presenting ? tr('Dừng chiếu') : tr('Rời'))),
        ],
      ),
    );
    return r == true;
  }

  void _laserAt(Offset local, Size size, {bool on = true}) {
    final x = (local.dx / size.width).clamp(0.0, 1.0), y = (local.dy / size.height).clamp(0.0, 1.0);
    setState(() => _laser = on ? Offset(x, y) : null);
    s.laser(x, y, on: on);
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final cs = th.colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) async {
        if (did) return;
        if (await _confirmLeave() && mounted) _stop();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(_page + 1),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _go(_page + 1),
          const SingleActivator(LogicalKeyboardKey.space): () => _go(_page + 1),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_page - 1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _go(_page - 1),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  const Icon(Icons.tv_rounded, size: 22),
                  const SizedBox(width: 8),
                  Flexible(child: Text(st.screen.isEmpty ? tr('Màn hình') : st.screen, overflow: TextOverflow.ellipsis)),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: Text(
                      st.ended
                          ? tr('Đã ngắt')
                          : st.presenting
                          ? tr('● Đang chiếu')
                          : tr('Đang chờ'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: st.presenting ? Colors.green.shade600 : th.hintColor),
                    ),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: st.ended
                  ? _ended(th)
                  : st.presenting
                  ? _remote(th, cs)
                  : _queued(th, cs),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ended(ThemeData th) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tv_off_rounded, size: 56, color: th.hintColor),
          const SizedBox(height: 12),
          Text(st.why == 'timeout' ? tr('Mất kết nối quá lâu, màn hình đã chuyển cho người khác') : tr('Đã ngắt khỏi màn hình'), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              _stopped = true;
              Navigator.of(context).pop();
            },
            child: Text(tr('Đóng')),
          ),
        ],
      ),
    ),
  );

  Widget _queued(ThemeData th, ColorScheme cs) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Đang chiếu: {0}', [st.nowBy]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              tr('Bạn đứng thứ {0} trong hàng chờ', ['${st.position}']),
              style: TextStyle(fontSize: 16, color: cs.primary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text(tr('Khi {0} dừng hoặc nhường, “{1}” sẽ tự lên màn hình. Giữ trang này mở.', [st.nowBy, c.name]), style: TextStyle(color: th.hintColor)),
          ],
        ),
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: () async {
          if (await _confirmLeave()) _stop();
        },
        child: Text(tr('Rời hàng chờ')),
      ),
    ],
  );

  Widget _remote(ThemeData th, ColorScheme cs) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Không chiếu được: {0}', [_error!]), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _maybeSend, child: Text(tr('Thử lại'))),
            ],
          ),
        ),
      );
    }
    if (!_sent || (c.type == 'pdf' && _doc == null)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 220, child: LinearProgressIndicator(value: _progress)),
            const SizedBox(height: 12),
            Text(tr('Đang chuẩn bị “{0}”…', [c.name]), textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (c.type == 'video') return _videoRemote(th, cs);
    if (c.type == 'mirror') {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.screen_share_rounded, size: 72, color: cs.primary),
                  const SizedBox(height: 10),
                  Text(
                    tr('Đang chiếu màn hình máy tính lên {0}', [st.screen]),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _startMirror().catchError((Object e) {
                      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$e')));
                    }),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: Text(tr('Đổi màn hình / cửa sổ')),
                  ),
                ],
              ),
            ),
          ),
          ..._bottom(cs),
        ],
      );
    }
    final pg = c.type == 'pdf' ? _doc!.pages[(_page - 1).clamp(0, _pages - 1)] : null;
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Center(
              child: AspectRatio(
                aspectRatio: pg != null ? pg.width / pg.height : 16 / 9,
                child: LayoutBuilder(
                  builder: (_, box) => GestureDetector(
                    onPanStart: (d) => _laserAt(d.localPosition, box.biggest),
                    onPanUpdate: (d) => _laserAt(d.localPosition, box.biggest),
                    onPanEnd: (_) => _laserAt(Offset.zero, box.biggest, on: false),
                    onTapUp: pg == null ? null : (d) => _go(d.localPosition.dx > box.maxWidth / 2 ? _page + 1 : _page - 1),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: pg != null
                                  ? PdfPageView(document: _doc, pageNumber: _page)
                                  : ColoredBox(
                                      color: Colors.black,
                                      child: Image.file(_pdf!, fit: BoxFit.contain),
                                    ),
                            ),
                          ),
                        ),
                        if (st.blank)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black87,
                              alignment: Alignment.center,
                              child: Text(tr('Màn đen'), style: const TextStyle(color: Colors.white70)),
                            ),
                          ),
                        if (_laser != null)
                          Positioned(
                            left: _laser!.dx * box.maxWidth - 8,
                            top: _laser!.dy * box.maxHeight - 8,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: .6), blurRadius: 10, spreadRadius: 3)],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          pg != null
              ? tr('{0} · trang {1}/{2} · giữ và kéo trên trang để trỏ laser', [c.name, '$_page', '$_pages'])
              : tr('{0} · giữ và kéo trên ảnh để trỏ laser', [c.name]),
          style: TextStyle(fontSize: 12.5, color: th.hintColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (pg != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Expanded(child: _bigBtn(Icons.chevron_left_rounded, _page > 1 ? () => _go(_page - 1) : null)),
                const SizedBox(width: 12),
                Expanded(child: _bigBtn(Icons.chevron_right_rounded, _page < _pages ? () => _go(_page + 1) : null)),
              ],
            ),
          ),
        ..._bottom(cs),
      ],
    );
  }

  /// Phần dưới chung: người đang chờ (nút Nhường), màn đen, dừng chiếu.
  Future<void> _toggleLock(bool on) async {
    setState(() => _locking = true);
    try {
      await s.lock(on);
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _locking = false);
    }
  }

  Future<void> _rename() async {
    final ctl = TextEditingController(text: st.screen);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Tên màn hình')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('vd Phòng họp 3F-A')),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || st.screenId.isEmpty) return;
    try {
      await CastSession.screenAction(s.server, s.token, st.screenId, 'name', {'name': name.trim()});
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text('$e')));
    }
  }

  List<Widget> _bottom(ColorScheme cs) {
    final waiting = st.queueNames;
    final lock = st.lock;
    final mine = lock?['mine'] == true, meeting = lock?['meeting'] != null;
    return [
      if (_requestFrom.isNotEmpty && waiting.isEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: .4)),
          ),
          child: Row(
            children: [
              const Text('✋ '),
              Expanded(child: Text(tr('{0} xin dùng màn hình này', [_requestFrom]))),
              TextButton(
                onPressed: () async {
                  if (mine) await _toggleLock(false);
                  await _stop();
                },
                child: Text(tr('Nhường')),
              ),
              IconButton(onPressed: () => setState(() => _requestFrom = ''), icon: const Icon(Icons.close_rounded, size: 18)),
            ],
          ),
        ),
      if (!meeting)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: SwitchListTile(
            dense: true,
            secondary: const Icon(Icons.lock_rounded),
            title: Text(tr('Khoá màn hình từ xa')),
            subtitle: Text(mine ? tr('Chỉ bạn (và admin) chiếu được · tự mở sau 2 giờ không dùng') : tr('Người khác không chen vào được')),
            value: mine,
            onChanged: _locking ? null : _toggleLock,
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: TextButton.icon(onPressed: _rename, icon: const Icon(Icons.edit_rounded, size: 18), label: Text(tr('Đổi tên màn hình'))),
        ),
      ),
      if (waiting.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: .4)),
          ),
          child: Row(
            children: [
              const Text('✋ '),
              Expanded(child: Text(tr('{0} đang chờ chiếu', [waiting.length > 1 ? '${waiting.first} (+${waiting.length - 1})' : waiting.first]))),
              TextButton(onPressed: _stop, child: Text(tr('Nhường'))),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => s.blank(!st.blank).catchError((_) {}),
                icon: Icon(st.blank ? Icons.visibility_rounded : Icons.square_rounded),
                label: Text(st.blank ? tr('Hiện lại') : tr('Màn đen')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cs.errorContainer, foregroundColor: cs.onErrorContainer),
                onPressed: _stop,
                icon: const Icon(Icons.stop_rounded),
                label: Text(tr('Dừng chiếu')),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _videoRemote(ThemeData th, ColorScheme cs) {
    final playing = st.media?['playing'] == true;
    final pos = st.videoPos();
    String fmt(double x) => '${(x ~/ 60).toString().padLeft(2, '0')}:${(x.toInt() % 60).toString().padLeft(2, '0')}';
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.movie_rounded, size: 72, color: cs.primary),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    c.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fmt(pos),
                  style: TextStyle(fontSize: 28, fontFeatures: const [FontFeature.tabularFigures()], color: th.hintColor),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: _bigBtn(Icons.replay_10_rounded, () => s.media(t: (pos - 10).clamp(0, double.infinity)).catchError((_) {}))),
              const SizedBox(width: 12),
              Expanded(child: _bigBtn(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, () => s.media(playing: !playing).catchError((_) {}))),
              const SizedBox(width: 12),
              Expanded(child: _bigBtn(Icons.forward_10_rounded, () => s.media(t: pos + 10).catchError((_) {}))),
            ],
          ),
        ),
        ..._bottom(cs),
      ],
    );
  }

  Widget _bigBtn(IconData icon, VoidCallback? onTap) => SizedBox(
    height: 76,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      child: Icon(icon, size: 40),
    ),
  );
}
