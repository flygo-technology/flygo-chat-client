import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../calls/calls_client.dart';
import '../../calls/meet_rooms.dart';
import '../../config.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../call_screen.dart' show CallVideo;
import '../common.dart';
import '../desk_tabs.dart';
import '../theme.dart';
import 'meet_home.dart';

// Phòng chờ trước khi vào cuộc họp: xem trước camera, bật / tắt mic và camera, chọn micro / camera (máy tính), ai đang
// trong phòng, "Tham gia ngay" / "Trình bày". Phòng chỉ dành cho người được mời: người ngoài danh sách bấm "Xin tham gia"
// và chờ người tổ chức cho vào.

/// Mở phòng chờ của mã [code] (hoặc của nhóm chat [channelId] khi máy chủ chưa có phòng họp có mã).
/// [fresh]: phòng vừa tạo (mình là người tạo, không cần hỏi máy chủ).
///
/// Máy tính có thanh tab: phòng chờ mở thành một tab riêng (cả khung tab, không phải hộp nổi bị cắt). Điện thoại / cửa
/// sổ không có thanh tab: trang toàn màn hình.
Future<void> openMeetLobby(BuildContext context, String? code, {MeetRoomInfo? room, String? channelId, bool fresh = false}) {
  final calls = context.read<AppState>().calls;
  if (calls.busy) {
    meetToast(context, tr('Bạn đang trong một cuộc gọi khác.'));
    return Future.value();
  }
  final open = openTabHook;
  if (isDesktop && open != null && (code != null || channelId != null)) {
    final arg = code ?? 'ch:$channelId';
    MeetLobbyTab._pending[arg] = (room, fresh);
    open(DeskTab('meet', arg: arg));
    return Future.value();
  }
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => MeetLobbyPage(code: code, room: room, channelId: channelId, fresh: fresh),
    ),
  );
}

/// Phòng chờ trong một tab máy tính (`DeskTab('meet', arg: mã | ch:<kênh>)`).
abstract final class MeetLobbyTab {
  /// Thông tin phòng đã có sẵn khi mở tab (phòng vừa tạo, phòng chọn từ danh sách), theo [DeskTab.arg].
  /// Giữ lại (không xoá khi dựng) vì tab dựng lại nhiều lần; mở lại cùng mã thì ghi đè.
  static final _pending = <String, (MeetRoomInfo?, bool)>{};

  static Widget page(String arg, {bool demo = false}) {
    final (room, fresh) = _pending[arg] ?? (null, false);
    final ch = arg.startsWith('ch:') ? arg.substring(3) : null;
    return MeetLobbyPage(key: ValueKey('meet-$arg'), code: ch == null ? arg : null, channelId: ch, room: room, fresh: fresh, demo: demo);
  }
}

class MeetLobbyPage extends StatefulWidget {
  final String? code;
  final MeetRoomInfo? room;
  final String? channelId;
  final bool fresh;

  /// Không mở camera / không hỏi máy chủ (thử nghiệm, ảnh chụp).
  final bool demo;
  const MeetLobbyPage({super.key, this.code, this.room, this.channelId, this.fresh = false, this.demo = false});
  @override
  State<MeetLobbyPage> createState() => _MeetLobbyPageState();
}

enum _Stage { loading, ready, waiting, denied, missing }

class _MeetLobbyPageState extends State<MeetLobbyPage> {
  MeetRoomInfo? _room;
  String? _error;
  _Stage _stage = _Stage.loading;
  bool _mic = false;
  bool _cam = !isDesktop ? false : true;
  MediaStream? _preview;
  List<MediaDeviceInfo> _mics = const [], _cams = const [];
  String? _micId = CallsClient.audioInputId, _camId = CallsClient.videoInputId;
  Timer? _poll;
  String? _tabTitle;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    if (widget.demo) {
      _stage = _Stage.ready;
      return;
    }
    _load();
    _devices();
    if (_cam) _openPreview();
    // Trạng thái phòng (ai đang trong đó, tới giờ chưa) làm mới mỗi 15 giây.
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _closePreview();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final code = widget.code;
    if (code == null) {
      if (mounted) setState(() => _stage = _Stage.ready);
      return;
    }
    try {
      final r = await MeetRoomsApi(context.read<AppState>().token).get(code);
      if (!mounted) return;
      setState(() {
        _room = r;
        if (_stage == _Stage.loading || _stage == _Stage.missing) _stage = _Stage.ready;
      });
    } on MeetRoomsException catch (e) {
      if (!mounted || quiet) return;
      if (widget.fresh && _room != null) {
        setState(() => _stage = _Stage.ready);
      } else {
        setState(() {
          _stage = _Stage.missing;
          _error = e.status == 404 ? tr('Không tìm thấy cuộc họp với mã này.') : e.message;
        });
      }
    } catch (e) {
      if (mounted && !quiet) {
        setState(() {
          _stage = _room == null ? _Stage.missing : _Stage.ready;
          _error = tr('Không kết nối được máy chủ.');
        });
      }
    }
  }

  // ---------------------------------------------------------------- camera / thiết bị
  Future<void> _devices() async {
    if (!isDesktop) return;
    try {
      final all = await navigator.mediaDevices.enumerateDevices();
      if (!mounted) return;
      setState(() {
        _mics = [
          for (final d in all)
            if (d.kind == 'audioinput' && d.deviceId.isNotEmpty) d,
        ];
        _cams = [
          for (final d in all)
            if (d.kind == 'videoinput' && d.deviceId.isNotEmpty) d,
        ];
      });
    } catch (e) {
      debugPrint('[meet] devices: $e');
    }
  }

  Future<void> _openPreview() async {
    await _closePreview();
    try {
      final s = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          if (_camId != null) 'deviceId': _camId else 'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      if (!mounted || !_cam) {
        s.getTracks().forEach((t) => t.stop());
        await s.dispose();
        return;
      }
      setState(() => _preview = s);
      // Lần đầu cấp quyền camera thì tên thiết bị mới đọc được.
      if (_cams.isEmpty) _devices();
    } catch (e) {
      debugPrint('[meet] preview: $e');
      if (mounted) setState(() => _cam = false);
    }
  }

  Future<void> _closePreview() async {
    final s = _preview;
    _preview = null;
    if (s == null) return;
    for (final t in s.getTracks()) {
      await t.stop();
    }
    await s.dispose();
  }

  void _toggleCam() {
    setState(() => _cam = !_cam);
    if (widget.demo) return;
    _cam ? _openPreview() : _closePreview().then((_) => mounted ? setState(() {}) : null);
  }

  // ---------------------------------------------------------------- vào họp
  Future<void> _enter({bool present = false}) async {
    final app = context.read<AppState>();
    final calls = app.calls;
    if (calls.busy) return meetToast(context, tr('Bạn đang trong một cuộc gọi khác.'));
    var channel = widget.channelId ?? _room?.channelId;
    final code = widget.code;
    if (code != null) {
      // Chưa ở kênh của phòng: máy chủ thêm vào (hoặc chờ người tổ chức cho vào).
      if (_room?.member != true && !widget.fresh) {
        setState(() => _stage = _Stage.waiting);
        try {
          final (res, ch) = await MeetRoomsApi(app.token).join(code);
          if (!mounted) return;
          if (res == MeetJoinResult.denied || res == MeetJoinResult.timeout) {
            setState(() {
              _stage = _Stage.denied;
              _error = res == MeetJoinResult.denied ? tr('Người tổ chức đã từ chối yêu cầu tham gia.') : tr('Chưa ai cho bạn vào. Thử lại sau.');
            });
            return;
          }
          channel = ch ?? channel;
        } on MeetRoomsException catch (e) {
          if (mounted) {
            setState(() {
              _stage = _Stage.denied;
              _error = e.message;
            });
          }
          return;
        }
      }
    }
    if (channel == null || channel.isEmpty) return;
    await app.ensureChannel(channel);
    await _closePreview();
    CallsClient.audioInputId = _micId;
    CallsClient.videoInputId = _camId;
    calls.joinPrefs = MeetJoinPrefs(mic: _mic, cam: _cam, present: present);
    if (!mounted) return;
    // Trong tab máy tính: đóng tab phòng chờ (cuộc họp mở ở cửa sổ riêng); trang toàn màn hình thì đóng trang.
    final tab = DeskTabScope.of(context)?.onClose;
    if (tab != null) {
      tab();
    } else {
      Navigator.of(context).pop();
    }
    await calls.startCall(channel, meeting: true);
  }

  // ---------------------------------------------------------------- giao diện
  // Bố cục theo chỗ thật có (tab, ô chia, cửa sổ hẹp), không theo cả cửa sổ: đủ rộng thì hai cột (xem trước | tham gia),
  // hẹp hơn thì cột tham gia xuống dưới phần xem trước, không bao giờ bị cắt.
  static const _sideW = 330.0, _gap = 48.0, _pad = 32.0, _minPreview = 440.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) => _build(context, box.maxWidth));

  Widget _build(BuildContext context, double width) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final previewW = (width - 2 * _pad - _gap - _sideW).clamp(0.0, 760.0);
    final wide = previewW >= _minPreview;
    // Một cột trên màn rộng (cửa sổ / ô chia hẹp): phần xem trước 16:9, nút rộng vừa phải.
    final roomy = width >= 600;
    final me = app.me?.displayName ?? '';
    final title =
        _room?.title ?? (widget.channelId != null && app.channels[widget.channelId] != null ? app.channelTitle(app.channels[widget.channelId]!) : '');
    // Trong tab máy tính: tên cuộc họp làm tiêu đề tab.
    if (title.isNotEmpty && title != _tabTitle) {
      _tabTitle = title;
      final onTitle = DeskTabScope.of(context)?.onTitle;
      if (onTitle != null) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? onTitle(title) : null);
    }

    final preview = AspectRatio(
      aspectRatio: roomy ? 16 / 9 : 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF262A31)),
            if (_preview != null)
              CallVideo(stream: _preview!, mirror: true)
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Avatar(userId: app.me?.id, name: me, size: wide ? 110 : 96, status: false),
                    const SizedBox(height: 12),
                    Text(_cam ? tr('Đang mở camera…') : tr('Camera đang tắt'), style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  ],
                ),
              ),
            Positioned(
              left: 16,
              top: 12,
              child: Text(
                me,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, shadows: [Shadow(blurRadius: 4)]),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LobbyToggle(
                    key: const ValueKey('lobby-mic'),
                    on: _mic,
                    icon: _mic ? Icons.mic_rounded : Icons.mic_off_rounded,
                    tooltip: _mic ? tr('Tắt micro') : tr('Bật micro'),
                    onTap: () => setState(() => _mic = !_mic),
                  ),
                  const SizedBox(width: 18),
                  _LobbyToggle(
                    key: const ValueKey('lobby-cam'),
                    on: _cam,
                    icon: _cam ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    tooltip: _cam ? tr('Tắt camera') : tr('Bật camera'),
                    onTap: _toggleCam,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    Widget devicePick(IconData icon, List<MediaDeviceInfo> list, String? value, void Function(String?) onPick, String fallback) => Expanded(
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: pal.divider),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: pal.sub),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  isDense: true,
                  value: list.any((d) => d.deviceId == value) ? value : null,
                  hint: Text(
                    fallback,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: pal.sub),
                  ),
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13, color: pal.text),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(fallback, overflow: TextOverflow.ellipsis)),
                    for (final d in list)
                      DropdownMenuItem<String?>(
                        value: d.deviceId,
                        child: Text(d.label.isEmpty ? d.deviceId : d.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: onPick,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final devices = isDesktop
        ? Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                devicePick(Icons.mic_none_rounded, _mics, _micId, (v) => setState(() => _micId = v), tr('Micro mặc định')),
                const SizedBox(width: 10),
                devicePick(Icons.videocam_outlined, _cams, _camId, (v) {
                  setState(() => _camId = v);
                  if (_cam) _openPreview();
                }, tr('Camera mặc định')),
              ],
            ),
          )
        : const SizedBox.shrink();

    final r = _room;
    final inside = r?.participants ?? 0;
    final locked = r?.locked == true;
    final knock =
        r != null &&
        r.member != true &&
        !widget.fresh &&
        (!r.ownChannel || (r.access == 'invited' && !r.invitees.contains(app.me?.id) && r.creator != app.me?.id));
    final String status;
    if (r == null) {
      status = '';
    } else if (r.finished) {
      status = r.status == MeetRoomStatus.cancelled ? tr('Cuộc họp đã bị huỷ.') : tr('Cuộc họp đã kết thúc.');
    } else if (locked) {
      status = tr('Cuộc họp bắt đầu lúc {0}.', ['${hhmm(r.start!)} ${ddmmyyyy(r.start!)}']);
    } else {
      status = inside > 0 ? tr('{0} người đang trong cuộc họp', [inside]) : tr('Chưa có ai trong cuộc họp');
    }
    final busy = _stage == _Stage.loading || _stage == _Stage.waiting;
    final canEnter = _stage != _Stage.missing && !busy && !(r?.finished ?? false) && !locked;

    final side = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _stage == _Stage.waiting ? tr('Đang xin tham gia…') : tr('Sẵn sàng tham gia?'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: wide ? 28 : 22, fontWeight: FontWeight.w500, color: pal.text),
        ),
        const SizedBox(height: 10),
        if (_stage == _Stage.waiting)
          Text(
            tr('Người tổ chức sẽ cho bạn vào trong giây lát.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.sub),
          )
        else if (_error != null && (_stage == _Stage.missing || _stage == _Stage.denied))
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          )
        else if (status.isNotEmpty)
          Text(
            status,
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.sub),
          ),
        const SizedBox(height: 22),
        if (busy)
          const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
        else ...[
          SizedBox(
            width: roomy ? 260 : double.infinity,
            height: 48,
            child: FilledButton(
              key: const ValueKey('lobby-join'),
              onPressed: canEnter ? () => _enter() : null,
              child: Text(knock ? tr('Xin tham gia') : tr('Tham gia ngay'), style: const TextStyle(fontSize: 16)),
            ),
          ),
          if (CallService.canShareScreen && !knock) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: roomy ? 260 : double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: canEnter ? () => _enter(present: true) : null,
                icon: const Icon(Icons.present_to_all_rounded),
                label: Text(tr('Trình bày')),
              ),
            ),
          ],
        ],
        if (r != null) ...[
          const SizedBox(height: 22),
          Text(
            '${r.title} · ${r.code}',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.sub, fontSize: 13),
          ),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (r != null && !r.finished)
            IconButton(tooltip: tr('Đường liên kết'), icon: const Icon(Icons.link_rounded), onPressed: () => showMeetLinkDialog(context, r)),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 24),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: previewW,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [preview, devices]),
                      ),
                      const SizedBox(width: _gap),
                      SizedBox(width: _sideW, child: side),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: roomy ? 400 : 480, maxWidth: 640),
                      child: preview,
                    ),
                  ),
                  Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: devices)),
                  const SizedBox(height: 20),
                  side,
                ],
              ),
      ),
    );
  }
}

class _LobbyToggle extends StatelessWidget {
  final bool on;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _LobbyToggle({super.key, required this.on, required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: on ? Colors.black.withValues(alpha: .18) : const Color(0xFFE5484D),
      shape: CircleBorder(side: BorderSide(color: on ? Colors.white70 : const Color(0xFFE5484D))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 56, height: 56, child: Icon(icon, color: Colors.white)),
      ),
    ),
  );
}
