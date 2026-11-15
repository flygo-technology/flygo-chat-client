import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../calls/meet_rooms.dart';
import '../../config.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'meet_lobby.dart';

// App "Họp" (mục Chính của Trang chủ): bố cục quen thuộc của các app họp video — "Cuộc họp mới", ô nhập mã / link,
// danh sách đang diễn ra / sắp tới / gần đây. Phòng họp có mã do trạm push giữ (lib/calls/meet_rooms.dart); âm thanh,
// hình, trình chiếu vẫn là cuộc họp sẵn có của app (plugin Calls + phòng họp /meet).

/// Màu riêng của app Họp (ô ở Trang chủ, biểu tượng).
const kMeetColor = Color(0xFF0E9F8E);

class MeetHomePage extends StatefulWidget {
  /// Danh sách phòng (thử nghiệm / ảnh chụp): bỏ qua máy chủ.
  final List<MeetRoomInfo>? demoRooms;
  final MeetRoomsApi? api;
  const MeetHomePage({super.key, this.demoRooms, this.api});
  @override
  State<MeetHomePage> createState() => _MeetHomePageState();
}

class _MeetHomePageState extends State<MeetHomePage> {
  final _code = TextEditingController();
  List<MeetRoomInfo>? _rooms;
  String? _error;
  bool _unsupported = false; // máy chủ chưa có /meet/rooms
  bool _busy = false;
  Timer? _tick;

  MeetRoomsApi get _api => widget.api ?? MeetRoomsApi(context.read<AppState>().token);

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    _load();
    // Đồng hồ ở đầu trang và trạng thái "đang diễn ra" cập nhật mỗi phút.
    _tick = Timer.periodic(const Duration(seconds: 60), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (widget.demoRooms != null) {
      setState(() => _rooms = widget.demoRooms);
      return;
    }
    try {
      final r = await _api.mine();
      if (mounted) {
        setState(() {
          _rooms = r;
          _error = null;
          _unsupported = false;
        });
      }
    } on MeetRoomsException catch (e) {
      if (mounted) {
        setState(() {
          _rooms = const [];
          _error = e.unsupported ? null : e.message;
          _unsupported = e.unsupported;
        });
      }
    } catch (e) {
      if (mounted && !quiet) {
        setState(() {
          _rooms = _rooms ?? const [];
          _error = tr('Không tải được danh sách cuộc họp');
        });
      }
    }
  }

  // ---------------------------------------------------------------- thao tác
  Future<MeetRoomInfo?> _create({
    String? title,
    DateTime? start,
    DateTime? end,
    List<String> invitees = const [],
    String? access,
    String? channelId,
  }) async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      return await _api.create(
        title: title ?? tr('Cuộc họp của {0}', [app.me?.displayName ?? tr('bạn')]),
        start: start,
        end: end,
        invitees: invitees,
        access: access,
        channelId: channelId,
        teamId: app.teamId,
      );
    } catch (e) {
      if (mounted) meetToast(context, tr('Không tạo được cuộc họp: {0}', [e]));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newMeeting(String action) async {
    switch (action) {
      case 'later':
        final r = await _create();
        if (r != null && mounted) {
          await showMeetLinkDialog(context, r, title: tr('Đây là đường liên kết đến cuộc họp của bạn'));
          _load(quiet: true);
        }
      case 'now':
        final r = await _create();
        if (r != null && mounted) {
          await openMeetLobby(context, r.code, room: r, fresh: true);
          _load(quiet: true);
        }
      case 'schedule':
        final s = await showScheduleMeeting(context);
        if (s == null || !mounted) return;
        final r = await _create(title: s.title, start: s.start, end: s.end, invitees: s.invitees, access: s.access);
        if (r != null && mounted) {
          await showMeetLinkDialog(context, r, title: tr('Đã lên lịch cuộc họp'));
          _load(quiet: true);
        }
      case 'chat':
        final ch = await _pickChat();
        if (ch == null || !mounted) return;
        final r = _unsupported ? null : await _create(title: tr('Họp {0}', [context.read<AppState>().channelTitle(ch)]), channelId: ch.id);
        if (!mounted) return;
        if (r != null) {
          await openMeetLobby(context, r.code, room: r, fresh: true);
        } else if (_unsupported) {
          // Máy chủ chưa có phòng họp có mã: họp trong nhóm theo cách cũ (thẻ cuộc họp trong chat).
          await openMeetLobby(context, null, channelId: ch.id);
        }
        _load(quiet: true);
    }
  }

  Future<MmChannel?> _pickChat() {
    final app = context.read<AppState>();
    final chats = [
      for (final s in app.chats)
        if (!s.channel.isDirect && s.channel.deleteAt == 0) s.channel,
    ];
    return showModalBottomSheet<MmChannel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(tr('Họp trong nhóm chat nào?'), style: Theme.of(ctx).textTheme.titleMedium),
              ),
              Flexible(
                child: chats.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(tr('Chưa có nhóm chat nào.'), textAlign: TextAlign.center),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final c in chats)
                            ListTile(
                              leading: Avatar(name: app.channelTitle(c), channel: c, size: 40, status: false),
                              title: Text(app.channelTitle(c), maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => Navigator.pop(ctx, c),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _join([String? input]) async {
    final code = parseMeetCode(input ?? _code.text);
    if (code == null) {
      meetToast(context, tr('Mã hoặc đường liên kết không đúng. Mã có dạng abc-defg-hij.'));
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await openMeetLobby(context, code);
    _load(quiet: true);
  }

  Future<void> _askCode() async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Nhập mã hoặc đường liên kết')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Ví dụ: abc-defg-hij')),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Tham gia'))),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty && mounted) await _join(v);
  }

  // ---------------------------------------------------------------- giao diện
  static const _actions = [
    ('later', Icons.link_rounded, 'Tạo cuộc họp để dùng sau'),
    ('now', Icons.add_rounded, 'Bắt đầu cuộc họp tức thì'),
    ('schedule', Icons.calendar_month_rounded, 'Lên lịch cuộc họp'),
    ('chat', Icons.groups_rounded, 'Họp trong một nhóm chat…'),
  ];

  Iterable<(String, IconData, String)> get _availableActions => _unsupported ? _actions.where((a) => a.$1 == 'chat') : _actions;

  Widget _newButton(Pal pal, {bool expand = false}) {
    final phone = !isDesktop && MediaQuery.sizeOf(context).width < 700;
    final btn = FilledButton.icon(
      key: const ValueKey('meet-new'),
      style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 20)),
      onPressed: _busy ? null : (phone ? _newSheet : null),
      icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.video_call_rounded),
      label: Text(tr('Cuộc họp mới')),
    );
    if (phone) return expand ? SizedBox(width: double.infinity, child: btn) : btn;
    return MenuAnchor(
      menuChildren: [
        for (final a in _availableActions)
          MenuItemButton(
            leadingIcon: Icon(a.$2),
            onPressed: () => _newMeeting(a.$1),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(tr(a.$3))),
          ),
      ],
      builder: (ctx, ctl, _) => FilledButton.icon(
        key: const ValueKey('meet-new'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 20)),
        onPressed: _busy ? null : () => ctl.isOpen ? ctl.close() : ctl.open(),
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.video_call_rounded),
        label: Text(tr('Cuộc họp mới')),
      ),
    );
  }

  Future<void> _newSheet() async {
    final a = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in _availableActions) ListTile(leading: Icon(a.$2), title: Text(tr(a.$3)), onTap: () => Navigator.pop(ctx, a.$1)),
            ListTile(leading: const Icon(Icons.close_rounded), title: Text(tr('Đóng')), onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
    if (a != null && mounted) await _newMeeting(a);
  }

  Widget _codeField(Pal pal) => SizedBox(
    width: 285,
    child: TextField(
      key: const ValueKey('meet-code'),
      controller: _code,
      onSubmitted: (_) => _join(),
      textInputAction: TextInputAction.go,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.keyboard_alt_outlined),
        hintText: tr('Nhập mã hoặc đường liên kết'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final rooms = _rooms;
    final live = [
      for (final r in rooms ?? const <MeetRoomInfo>[])
        if (r.live) r,
    ];
    final upcoming = [
      for (final r in rooms ?? const <MeetRoomInfo>[])
        if (!r.live && !r.finished && r.start != null && r.start!.isAfter(now.subtract(const Duration(minutes: 30)))) r,
    ]..sort((a, b) => a.start!.compareTo(b.start!));
    final recent = [
      for (final r in rooms ?? const <MeetRoomInfo>[])
        if (!live.contains(r) && !upcoming.contains(r) && r.status != MeetRoomStatus.cancelled) r,
    ];

    final lists = _RoomLists(
      live: live,
      upcoming: upcoming,
      recent: recent.take(10).toList(),
      loading: rooms == null,
      error: _error,
      onOpen: (r) => openMeetLobby(context, r.code, room: r).then((_) => _load(quiet: true)),
      onCopy: (r) => showMeetLinkDialog(context, r),
    );
    final header = Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 8, 8, wide ? 24 : 16, 8),
      child: Row(
        children: [
          if (Navigator.of(context).canPop()) const BackButton(),
          if (!wide && !Navigator.of(context).canPop()) const SizedBox(width: 8),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: kMeetColor, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Text(
            wide ? tr('Flygo Họp') : tr('Họp'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: pal.text),
          ),
          const Spacer(),
          if (wide) Text('${hhmm(now)} · ${_weekday(now)}, ${now.day}/${now.month}', style: TextStyle(color: pal.sub, fontSize: 15)),
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: () => _load(),
            icon: Icon(Icons.refresh_rounded, color: pal.sub),
          ),
        ],
      ),
    );
    final notice = _unsupported
        ? Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              tr('Máy chủ này chưa bật phòng họp có mã. Bạn vẫn họp được trong một nhóm chat.'),
              style: TextStyle(color: pal.sub, fontSize: 13),
            ),
          )
        : const SizedBox.shrink();

    final body = wide
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Họp video an toàn,\nngay trong Flygo Chat'),
                            style: TextStyle(fontSize: 38, height: 1.2, fontWeight: FontWeight.w500, color: pal.text),
                          ),
                          const SizedBox(height: 14),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Text(
                              tr(
                                'Tạo cuộc họp, gửi mã hoặc đường liên kết cho đồng nghiệp. Có trình chiếu, chia sẻ màn hình, giơ tay và trợ lý AI ghi chép.',
                              ),
                              style: TextStyle(fontSize: 16.5, height: 1.45, color: pal.sub),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Wrap(
                            spacing: 14,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _newButton(pal),
                              _codeField(pal),
                              TextButton(onPressed: parseMeetCode(_code.text) == null ? null : () => _join(), child: Text(tr('Tham gia'))),
                            ],
                          ),
                          notice,
                        ],
                      ),
                    ),
                    const SizedBox(width: 56),
                    Expanded(flex: 5, child: SingleChildScrollView(child: lists)),
                  ],
                ),
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Row(
                children: [
                  Expanded(child: _newButton(pal, expand: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('meet-enter-code'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                      onPressed: _askCode,
                      icon: const Icon(Icons.keyboard_alt_outlined),
                      label: Text(tr('Nhập mã')),
                    ),
                  ),
                ],
              ),
              notice,
              const SizedBox(height: 8),
              lists,
            ],
          );
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            header,
            if (wide) Divider(height: 1, color: pal.divider),
            Expanded(
              child: RefreshIndicator(onRefresh: _load, child: body),
            ),
            // Giữ AppState lắng nghe (danh bạ tải xong thì tên người tạo hiện đúng).
            if (app.me == null) const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

String _weekday(DateTime d) => [tr('T2'), tr('T3'), tr('T4'), tr('T5'), tr('T6'), tr('T7'), tr('CN')][d.weekday - 1];

class _RoomLists extends StatelessWidget {
  final List<MeetRoomInfo> live, upcoming, recent;
  final bool loading;
  final String? error;
  final void Function(MeetRoomInfo) onOpen;
  final void Function(MeetRoomInfo) onCopy;
  const _RoomLists({
    required this.live,
    required this.upcoming,
    required this.recent,
    required this.loading,
    required this.error,
    required this.onOpen,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget head(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        t.toUpperCase(),
        style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub),
      ),
    );
    Widget card(List<Widget> rows) => Container(
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(height: 1, indent: 70, color: pal.divider), rows[i]],
        ],
      ),
    );
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final empty = live.isEmpty && upcoming.isEmpty && recent.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
          ),
        if (empty && error == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
            child: Column(
              children: [
                Icon(Icons.event_available_rounded, size: 48, color: pal.sub),
                const SizedBox(height: 10),
                Text(
                  tr('Chưa có cuộc họp nào'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('Bấm "Cuộc họp mới" để tạo, hoặc nhập mã người khác gửi cho bạn.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: pal.sub),
                ),
              ],
            ),
          ),
        if (live.isNotEmpty) ...[
          head(tr('Đang diễn ra')),
          card([for (final r in live) _RoomRow(room: r, onOpen: onOpen, onCopy: onCopy)]),
        ],
        if (upcoming.isNotEmpty) ...[
          head(tr('Sắp tới')),
          card([for (final r in upcoming) _RoomRow(room: r, onOpen: onOpen, onCopy: onCopy)]),
        ],
        if (recent.isNotEmpty) ...[
          head(tr('Gần đây')),
          card([for (final r in recent) _RoomRow(room: r, onOpen: onOpen, onCopy: onCopy)]),
        ],
      ],
    );
  }
}

class _RoomRow extends StatelessWidget {
  final MeetRoomInfo room;
  final void Function(MeetRoomInfo) onOpen;
  final void Function(MeetRoomInfo) onCopy;
  const _RoomRow({required this.room, required this.onOpen, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final s = room.start;
    final now = DateTime.now();
    final future = s != null && s.isAfter(now);
    final Widget lead = room.live
        ? const Icon(Icons.radio_button_checked_rounded, color: Color(0xFF1FA463))
        : future
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${s.day}',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.text),
              ),
              Text('${_weekday(s)} · ${hhmm(s)}', style: TextStyle(fontSize: 11.5, color: pal.sub)),
            ],
          )
        : Icon(room.finished ? Icons.history_rounded : Icons.videocam_outlined, color: pal.sub);
    final sub = [
      room.code,
      if (room.live) tr('{0} người', [room.participants]),
      if (!room.live && !future && s != null) '${hhmm(s)} ${ddmmyyyy(s)}',
      if (room.status == MeetRoomStatus.ended) tr('đã kết thúc'),
      if (!room.ownChannel) tr('trong nhóm chat'),
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onOpen(room),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 58, child: Center(child: lead)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: pal.sub),
                  ),
                ],
              ),
            ),
            if (room.live)
              FilledButton(onPressed: () => onOpen(room), child: Text(tr('Tham gia')))
            else if (!room.finished)
              IconButton(
                tooltip: tr('Sao chép đường liên kết'),
                onPressed: () => onCopy(room),
                icon: Icon(Icons.share_outlined, color: pal.sub),
              ),
          ],
        ),
      ),
    );
  }
}

/// Hộp "đường liên kết đến cuộc họp": sao chép, chia sẻ, mã QR.
Future<void> showMeetLinkDialog(BuildContext context, MeetRoomInfo r, {String? title}) => showDialog<void>(
  context: context,
  builder: (d) {
    final pal = Pal.of(d);
    return AlertDialog(
      title: Text(title ?? r.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Gửi đường liên kết hoặc mã này cho người bạn muốn mời. Người trong công ty dán vào ô "Nhập mã hoặc đường liên kết" của app Họp.'),
              style: TextStyle(color: pal.sub),
            ),
            const SizedBox(height: 14),
            MeetLinkBox(room: r),
            if (r.start != null && r.start!.isAfter(DateTime.now())) ...[
              const SizedBox(height: 10),
              Text(tr('Bắt đầu lúc {0}', ['${hhmm(r.start!)} ${ddmmyyyy(r.start!)}']), style: TextStyle(color: pal.sub)),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Đóng')))],
    );
  },
);

/// Ô đường liên kết + nút sao chép / chia sẻ / mã QR (hộp link mời, bảng "Thông tin cuộc họp").
class MeetLinkBox extends StatelessWidget {
  final MeetRoomInfo room;
  final bool dark;
  const MeetLinkBox({super.key, required this.room, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final fg = dark ? Colors.white : pal.text;
    final link = room.url.isEmpty ? meetLink(room.code) : room.url;
    final invite = tr('Mời bạn tham gia cuộc họp "{0}"\nMã: {1}\n{2}', [room.title, room.code, link]);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(color: dark ? const Color(0xFF2A2F37) : pal.surface, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(link.replaceFirst(RegExp(r'^https?://'), ''), maxLines: 1, style: TextStyle(color: fg, fontSize: 14)),
              ),
              IconButton(
                tooltip: tr('Sao chép'),
                icon: Icon(Icons.content_copy_rounded, color: fg, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  meetToast(context, tr('Đã sao chép đường liên kết'));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: invite));
                meetToast(context, tr('Đã sao chép lời mời'));
              },
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: Text(tr('Sao chép lời mời')),
            ),
            if (!isDesktop)
              TextButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(text: invite)),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: Text(tr('Chia sẻ')),
              ),
            TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text(room.code),
                  content: SizedBox(
                    width: 240,
                    height: 240,
                    child: QrImageView(data: link, backgroundColor: Colors.white),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Đóng')))],
                ),
              ),
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: Text(tr('Mã QR')),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- lên lịch

class MeetSchedule {
  final String title;
  final DateTime start, end;
  final List<String> invitees;
  final String access;
  const MeetSchedule(this.title, this.start, this.end, this.invitees, this.access);
}

Future<MeetSchedule?> showScheduleMeeting(BuildContext context) =>
    Navigator.of(context).push<MeetSchedule>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ScheduleMeeting()));

class _ScheduleMeeting extends StatefulWidget {
  const _ScheduleMeeting();
  @override
  State<_ScheduleMeeting> createState() => _ScheduleMeetingState();
}

class _ScheduleMeetingState extends State<_ScheduleMeeting> {
  final _title = TextEditingController();
  final _q = TextEditingController();
  late DateTime _start = () {
    final n = DateTime.now().add(const Duration(hours: 1));
    return DateTime(n.year, n.month, n.day, n.hour, n.minute < 30 ? 30 : 0).add(Duration(hours: n.minute < 30 ? 0 : 1));
  }();
  int _minutes = 60;
  bool _inviteOnly = true;
  final _invited = <String>{};

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _start, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (t == null) return;
    setState(() => _start = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final q = _q.text.trim().toLowerCase();
    final people = [
      for (final u in app.people)
        if (q.isEmpty || u.displayName.toLowerCase().contains(q) || u.username.contains(q)) u,
    ];
    final ok = _title.text.trim().isNotEmpty && _start.isAfter(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Lên lịch cuộc họp')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: ok
                  ? () => Navigator.pop(
                      context,
                      MeetSchedule(
                        _title.text.trim(),
                        _start,
                        _start.add(Duration(minutes: _minutes)),
                        _invited.toList(),
                        _inviteOnly ? 'invited' : 'company',
                      ),
                    )
                  : null,
              child: Text(tr('Lưu')),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(labelText: tr('Tên cuộc họp'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text('${_weekday(_start)}, ${ddmmyyyy(_start)} · ${hhmm(_start)}'),
                subtitle: Text(tr('Bấm để đổi ngày giờ')),
                onTap: _pick,
              ),
              Row(
                children: [
                  const Icon(Icons.timelapse_rounded),
                  const SizedBox(width: 16),
                  Text(tr('Thời lượng')),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _minutes,
                    items: [
                      for (final m in const [15, 30, 45, 60, 90, 120]) DropdownMenuItem(value: m, child: Text(tr('{0} phút', [m]))),
                    ],
                    onChanged: (v) => setState(() => _minutes = v ?? 60),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _inviteOnly,
                onChanged: (v) => setState(() => _inviteOnly = v),
                title: Text(tr('Chỉ người được mời')),
                subtitle: Text(
                  _inviteOnly ? tr('Người khác có mã phải xin vào, người tổ chức cho vào.') : tr('Mọi người trong công ty có mã đều vào được.'),
                ),
              ),
              const Divider(height: 24),
              Text(
                tr('Mời ({0})', [_invited.length]),
                style: TextStyle(fontWeight: FontWeight.w700, color: pal.sub),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _q,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr('Tìm người'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              for (final u in people.take(80))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _invited.contains(u.id),
                  onChanged: (v) => setState(() => v == true ? _invited.add(u.id) : _invited.remove(u.id)),
                  secondary: Avatar(userId: u.id, name: u.displayName, size: 36, status: false),
                  title: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thông báo ngắn ở đáy màn hình.
void meetToast(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
