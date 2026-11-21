import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calls/call_service.dart';
import '../../calls/meet_room.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../meet/meet_home.dart' show meetToast;
import 'app_kit.dart';
import 'page_types.dart';
import 'pages_api.dart';
import 'types/media_apps.dart' show copyText;

// Trang hệ thống video (Chiếu màn hình, Video tự động / lưới) và Website của phòng thành app (mockup bảng 04, 05, 08).
// Hình thật (màn hình chia sẻ, video từng người, trang web) vẫn ở sân khấu của màn họp; app trong bảng trang là phần người
// xem tương tác + điều khiển của người chiếu / chủ trì, kèm hình sân khấu tóm tắt.

/// Cách xem riêng trên máy này cho Video tự động / lưới: '' = theo phòng, 'grid' = lưới, 'pin' = ghim người đang nói.
final sysVideoMine = ValueNotifier<String>('');

/// Chiếu màn hình: tăng để đưa màn hình chia sẻ về vừa khung (bỏ phóng to); bật để chạm chỉ laser (khi được cho phép).
final screenZoomReset = ValueNotifier<int>(0);
final screenLaserOn = ValueNotifier<bool>(false);

/// Bắt đầu / dừng chiếu màn hình của mình (màn họp gán; null = máy này không chiếu màn hình được).
final sysShareToggle = ValueNotifier<Future<void> Function()?>(null);

/// Phòng họp hiện tại (màn họp gán): app Website đọc / điều khiển trang web của phòng.
final currentMeetRoom = ValueNotifier<MeetRoom?>(null);

/// Website: máy này theo cuộn của người điều khiển (false = tự cuộn); người điều khiển gửi vị trí cuộn cho cả phòng.
final webFollow = ValueNotifier<bool>(true);
final webSync = ValueNotifier<bool>(true);

String _nameOf(BuildContext context, String uid) {
  try {
    return context.read<AppState>().users[uid]?.displayName ?? '';
  } catch (_) {
    return '';
  }
}

/// Người đang chia sẻ màn hình mới nhất (người khác trước, rồi mình): (user id, tên), null = chưa ai.
(String, String)? _sharer(BuildContext context, CallService call) {
  final ps = [for (final p in call.participants) if (p.screen) p]..sort((a, b) => b.screenAt.compareTo(a.screenAt));
  final other = ps.where((p) => p.userId != call.myId()).firstOrNull ?? ps.firstOrNull;
  if (other != null && other.userId != call.myId()) return (other.userId, _nameOf(context, other.userId));
  if (call.localScreen != null) return (call.myId(), tr('Bạn'));
  if (other != null) return (other.userId, _nameOf(context, other.userId));
  return null;
}

Map _cfg(PageCtx ctx, String k) => (ctx.view[k] as Map?) ?? const {};

// ------------------------------------------------------------------ Chiếu màn hình

/// Hình sân khấu tóm tắt: ai đang chiếu, đang che / cho chỉ laser.
class ScreenStagePreview extends StatelessWidget {
  final PageCtx ctx;
  const ScreenStagePreview(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final who = _sharer(context, ctx.call);
    final c = _cfg(ctx, 'screen_cfg');
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(color: const Color(0xFFF5B544).withValues(alpha: .16), borderRadius: BorderRadius.circular(30)),
          child: Icon(c['cover'] == true ? Icons.visibility_off_outlined : Icons.screen_share_outlined, color: const Color(0xFFF5B544), size: 60),
        ),
        const SizedBox(height: 24),
        Text(who == null ? tr('Chưa có ai chiếu màn hình') : tr('{0} đang chiếu màn hình', [who.$2.isEmpty ? tr('Một người') : who.$2]),
            textAlign: TextAlign.center, style: TextStyle(color: t.text, fontSize: 40, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(
          [if (c['cover'] == true) tr('Đang che: mọi người thấy "Chờ một chút"'), if (c['laser'] == true) tr('Mọi người chỉ laser được')].join(' · '),
          style: TextStyle(color: t.sub, fontSize: 24),
        ),
      ]),
    );
  }
}

/// Người xem: ai đang chiếu, đưa về vừa khung, chỉ laser (khi người chiếu cho phép).
class ScreenPanel extends StatelessWidget {
  final PageCtx ctx;
  const ScreenPanel(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final who = _sharer(context, ctx.call);
    final c = _cfg(ctx, 'screen_cfg');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(who == null ? tr('Chưa có ai chiếu màn hình') : tr('Đang chiếu: {0}', [who.$2.isEmpty ? tr('Một người') : who.$2]),
            key: const ValueKey('screen-status'), style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(tr('Chụm hai ngón trên sân khấu để phóng to'), style: TextStyle(color: t.sub, fontSize: 12.5)),
        const SizedBox(height: 10),
        ValueListenableBuilder<bool>(
          valueListenable: screenLaserOn,
          builder: (context, on, _) => Row(children: [
            Expanded(child: AppButton(tr('Vừa khung'), key: const ValueKey('screen-fit'), icon: Icons.fit_screen_outlined, onPressed: () async => screenZoomReset.value++)),
            if (c['laser'] == true) ...[
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(on ? tr('Tắt laser') : tr('Chỉ laser'),
                    key: const ValueKey('screen-laser'), kind: on ? AppButtonKind.danger : AppButtonKind.tonal, icon: Icons.highlight_alt_rounded, onPressed: () async => screenLaserOn.value = !on),
              ),
            ],
          ]),
        ),
        if (c['laser'] == true)
          ValueListenableBuilder<bool>(
            valueListenable: screenLaserOn,
            builder: (context, on, _) => on
                ? Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Chạm giữ trên sân khấu để chỉ, mọi người cùng thấy'), style: TextStyle(color: t.sub, fontSize: 12.5)))
                : const SizedBox.shrink(),
          ),
      ]),
    );
  }
}

/// Người đang chiếu / chủ trì: dừng, đổi cửa sổ, tạm che, cho mọi người chỉ laser. (Điều khiển từ xa, chia sẻ âm thanh: bộ
/// chia sẻ màn hình hiện tại chưa hỗ trợ.)
class ScreenControls extends StatelessWidget {
  final PageCtx ctx;
  const ScreenControls(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final call = ctx.call;
    final mine = call.localScreen != null;
    final c = _cfg(ctx, 'screen_cfg');
    return ValueListenableBuilder<Future<void> Function()?>(
      valueListenable: sysShareToggle,
      builder: (context, toggle, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(mine ? tr('Bạn đang chiếu') : tr('Điều khiển')),
        if (mine)
          Row(children: [
            Expanded(
              child: AppButton(tr('Dừng chiếu'), key: const ValueKey('screen-stop'), kind: AppButtonKind.danger, icon: Icons.stop_screen_share_outlined, onPressed: () => call.stopScreenShare()),
            ),
            if (toggle != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(tr('Đổi cửa sổ'), key: const ValueKey('screen-switch'), onPressed: () async {
                  await call.stopScreenShare();
                  await toggle();
                }),
              ),
            ],
          ])
        else if (toggle != null)
          AppButton(tr('Chiếu màn hình của tôi'), key: const ValueKey('screen-start'), kind: AppButtonKind.primary, icon: Icons.screen_share_outlined, onPressed: toggle),
        const SizedBox(height: 4),
        AppToggleRow(tr('Tạm che màn hình'), key: const ValueKey('screen-cover'), sub: tr('Mọi người thấy "Chờ một chút"'), value: c['cover'] == true, onChanged: (v) => ctx.act('screen_cfg', {'cover': v})),
        AppToggleRow(tr('Mọi người chỉ laser'), key: const ValueKey('screen-allow-laser'), value: c['laser'] == true, onChanged: (v) => ctx.act('screen_cfg', {'laser': v})),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Video tự động / lưới

/// Hình sân khấu tóm tắt: ảnh đại diện từng người (viền xanh = đang nói, vàng = giơ tay), người lên lớn đầu tiên.
class VideoStagePreview extends StatelessWidget {
  final PageCtx ctx;
  final bool grid;
  const VideoStagePreview(this.ctx, {super.key, required this.grid});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final ps = [for (final p in ctx.call.participants) p];
    final spot = '${_cfg(ctx, 'video_cfg')['spot'] ?? ''}';
    ps.sort((a, b) => (b.userId == spot ? 1 : 0).compareTo(a.userId == spot ? 1 : 0));
    if (ps.isEmpty) return Center(child: Text(tr('Chưa có ai trong cuộc họp'), style: TextStyle(color: t.sub, fontSize: 28)));
    final shown = ps.take(grid ? 9 : 5).toList();
    Widget tile(CallParticipant p, double size) {
      final name = _nameOf(context, p.userId);
      return Container(
        decoration: BoxDecoration(
          color: t.light ? const Color(0xFFE9EDF2) : const Color(0xFF1B2230),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.speaking ? const Color(0xFF22B8A6) : p.raisedHand ? const Color(0xFFF5B544) : Colors.transparent, width: 4),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppAvatar(name.isEmpty ? '?' : name, size: size),
          const SizedBox(height: 8),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 20)),
        ]),
      );
    }

    if (grid) {
      return GridView.count(
        padding: const EdgeInsets.all(8),
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 16 / 9,
        physics: const NeverScrollableScrollPhysics(),
        children: [for (final p in shown) tile(p, 70)],
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: tile(shown.first, 150)),
      if (shown.length > 1) ...[
        const SizedBox(width: 12),
        SizedBox(width: 220, child: Column(children: [for (final p in shown.skip(1)) Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 10), child: tile(p, 44)))])),
      ],
    ]);
  }
}

/// Người xem: cách xem riêng (theo phòng / lưới / ghim người nói), giơ tay, thả cảm xúc.
class VideoViewerPanel extends StatelessWidget {
  final PageCtx ctx;
  const VideoViewerPanel(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final call = ctx.call;
    final lock = _cfg(ctx, 'video_cfg')['lock'] == true;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSectionLabel(tr('Màn hình của bạn')),
        ValueListenableBuilder<String>(
          valueListenable: sysVideoMine,
          builder: (context, v, _) => AppSegmented<String>(
            key: const ValueKey('video-mine'),
            items: [('', tr('Theo phòng')), ('grid', tr('Lưới')), ('pin', tr('Ghim người nói'))],
            value: lock ? '' : v,
            onChanged: lock ? null : (x) => sysVideoMine.value = x,
          ),
        ),
        if (lock) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('Chủ trì đang khoá bố cục'), style: TextStyle(color: t.sub, fontSize: 12.5))),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: call,
          builder: (context, _) => Row(children: [
            Expanded(
              child: AppButton(call.handRaised ? tr('Hạ tay') : tr('Giơ tay'),
                  key: const ValueKey('video-hand'), kind: call.handRaised ? AppButtonKind.warn : AppButtonKind.tonal, icon: Icons.front_hand_outlined, onPressed: () async => call.toggleHand()),
            ),
            const SizedBox(width: 8),
            Expanded(child: AppButton(tr('Thả tim'), key: const ValueKey('video-heart'), onPressed: () async => call.react('❤️'))),
            const SizedBox(width: 8),
            Expanded(child: AppButton(tr('Vỗ tay'), key: const ValueKey('video-clap'), onPressed: () async => call.react('👏'))),
          ]),
        ),
      ]),
    );
  }
}

/// Chủ trì: bố cục cả phòng (tự động / lưới / một người), đưa một người lên lớn, ẩn người tắt camera, khoá bố cục.
class VideoRoomControls extends StatelessWidget {
  final PageCtx ctx;
  const VideoRoomControls(this.ctx, {super.key});
  @override
  Widget build(BuildContext context) {
    final call = ctx.call;
    final st = ctx.view;
    final c = _cfg(ctx, 'video_cfg');
    final spot = '${c['spot'] ?? ''}';
    final mode = st['page'] == 'sys:grid' ? 'grid' : (spot.isNotEmpty ? 'one' : 'auto');
    final people = <String, String>{for (final p in call.participants) if (p.userId.isNotEmpty && p.userId != call.myId()) p.userId: _nameOf(context, p.userId)};
    Future<void> layout(String m, [String who = '']) async {
      await ctx.act('show', {'page': m == 'grid' ? 'sys:grid' : 'sys:auto'});
      await ctx.act('video_cfg', {'spot': m == 'one' ? who : ''});
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Cả phòng xem')),
      AppSegmented<String>(
        key: const ValueKey('video-room'),
        items: [('auto', tr('Tự động')), ('grid', tr('Lưới')), ('one', tr('Một người'))],
        value: mode,
        onChanged: (m) {
          final speaking = call.participants.where((p) => p.speaking && p.userId != call.myId()).firstOrNull?.userId;
          layout(m, m == 'one' ? (spot.isNotEmpty ? spot : speaking ?? people.keys.firstOrNull ?? '') : '');
        },
      ),
      if (people.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(tr('Đưa lên lớn'), style: TextStyle(color: AppScope.of(context).theme.sub, fontSize: 12.5)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in people.entries)
            AppChip(e.value.isEmpty ? tr('Một người') : e.value, key: ValueKey('video-spot-${e.key}'), selected: e.key == spot, onTap: () => layout(e.key == spot ? 'auto' : 'one', e.key)),
        ]),
      ],
      const SizedBox(height: 4),
      AppToggleRow(tr('Ẩn người tắt camera'), key: const ValueKey('video-hide-off'), value: c['hide_off'] == true, onChanged: (v) => ctx.act('video_cfg', {'hide_off': v})),
      AppToggleRow(tr('Khoá bố cục'), key: const ValueKey('video-lock'), sub: tr('Người xem không đổi cách xem riêng được'), value: c['lock'] == true, onChanged: (v) => ctx.act('video_cfg', {'lock': v})),
    ]);
  }
}

// ------------------------------------------------------------------ Website của phòng

/// Ngữ cảnh của app Website: phòng (MeetRoom) giữ địa chỉ / vị trí cuộn / người điều khiển.
PageCtx webAppCtx(CallService call, MeetRoom room) => PageCtx(
      data: PageData.from({
        'page': {'id': 'app:web', 'type': 'app_web', 'title': tr('Website'), 'owner': '', 'visibility': 'meeting', 'content': {'url': room.webUrl ?? ''}},
        'view': {'url': room.webUrl ?? '', 'driver': room.webDriver ?? ''},
        'role': room.iDriveWeb || call.canModerate ? 'manager' : 'viewer',
        'rev': 0,
      }),
      api: PagesApi(call),
      call: call,
      presenting: false,
      onStage: false,
      act: (a, [b = const {}]) async {},
      reload: () async {},
    );

PageTypeSpec webAppSpec(MeetRoom room) => PageTypeSpec(
      type: 'app_web',
      label: tr('Website'),
      icon: Icons.public,
      color: const Color(0xFF4285F4),
      stageThemed: true,
      view: (context, ctx) => _WebPreview(room),
      panel: (context, ctx) => WebPanel(room),
      controls: (context, ctx) => WebControls(room),
    );

String _host(String url) => Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? url;

class _WebPreview extends StatelessWidget {
  final MeetRoom room;
  const _WebPreview(this.room);
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final url = room.webUrl ?? '';
    if (url.isEmpty) return Center(child: Text(tr('Chưa mở website nào'), style: TextStyle(color: t.sub, fontSize: 30)));
    return Row(children: [
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_host(url), style: TextStyle(color: t.text, fontSize: 48, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(url, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.sub, fontSize: 22)),
        ]),
      ),
      const SizedBox(width: 30),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: QrImageView(data: url, size: 220, padding: EdgeInsets.zero),
      ),
    ]);
  }
}

/// Người xem: thanh địa chỉ (khoá = https), theo cuộn của người điều khiển hoặc tự cuộn, chép link, mở ngoài.
class WebPanel extends StatelessWidget {
  final MeetRoom room;
  const WebPanel(this.room, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    return ListenableBuilder(
      listenable: room,
      builder: (context, _) {
        final url = room.webUrl ?? '';
        if (url.isEmpty) return AppCard(child: AppEmpty(icon: Icons.public, title: tr('Chưa mở website nào'), sub: tr('Người trình bày mở một trang web cho cả phòng ở phần điều khiển')));
        final secure = url.startsWith('https://');
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: t.light ? const Color(0xFFF1F3F6) : const Color(0xFF1F232B), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(secure ? Icons.lock_outline_rounded : Icons.lock_open_rounded, size: 15, color: secure ? const Color(0xFF38C793) : const Color(0xFFF5B544)),
                const SizedBox(width: 6),
                Expanded(child: Text(url, key: const ValueKey('web-url'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 13.5))),
              ]),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<bool>(
              valueListenable: webFollow,
              builder: (context, follow, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(room.iDriveWeb ? tr('Bạn đang điều khiển trang') : (follow ? tr('Đang theo cuộn của người điều khiển') : tr('Bạn đang tự cuộn')),
                    key: const ValueKey('web-status'), style: TextStyle(color: t.sub, fontSize: 12.5)),
                const SizedBox(height: 8),
                Row(children: [
                  if (!room.iDriveWeb) ...[
                    Expanded(
                      child: AppButton(follow ? tr('Tự cuộn') : tr('Theo cuộn'), key: const ValueKey('web-follow'), onPressed: () async => webFollow.value = !follow),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: AppButton(tr('Chép link'), key: const ValueKey('web-copy'), icon: Icons.link_rounded, onPressed: () => copyText(context, url, tr('Đã chép link')))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(tr('Mở ngoài'), key: const ValueKey('web-open'), icon: Icons.open_in_new_rounded, onPressed: () async {
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    }),
                  ),
                ]),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

/// Người điều khiển / chủ trì: gõ địa chỉ ngay trên thanh (kiểm tra trang có cho nhúng không: không thì TV hiện mã QR),
/// đồng bộ cuộn cho cả phòng, dừng website.
class WebControls extends StatefulWidget {
  final MeetRoom room;
  const WebControls(this.room, {super.key});
  @override
  State<WebControls> createState() => _WebControlsState();
}

class _WebControlsState extends State<WebControls> {
  late final _c = TextEditingController(text: widget.room.webUrl ?? 'https://');
  String? _embedNote;
  MeetRoom get room => widget.room;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    var u = _c.text.trim();
    if (u.isEmpty || u == 'https://') return;
    if (!u.startsWith('http')) u = 'https://$u';
    final ok = Uri.tryParse(u)?.hasAuthority ?? false;
    if (!ok) {
      if (mounted) meetToast(context, tr('Địa chỉ không hợp lệ'));
      return;
    }
    room.webUrl == null ? room.openWeb(u) : room.navWeb(u);
    final note = await webEmbedNote(u);
    if (mounted) setState(() => _embedNote = note);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(tr('Điều khiển')),
      Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('web-input'),
            controller: _c,
            keyboardType: TextInputType.url,
            style: TextStyle(color: t.text),
            decoration: InputDecoration(isDense: true, hintText: 'https://', hintStyle: TextStyle(color: t.sub), prefixIcon: Icon(Icons.public, color: t.sub, size: 18)),
            onSubmitted: (_) => _go(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 70, child: AppButton(tr('Đi'), key: const ValueKey('web-go'), kind: AppButtonKind.primary, onPressed: _go)),
      ]),
      if (_embedNote != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_embedNote!, style: const TextStyle(color: Color(0xFFF5B544), fontSize: 12.5))),
      ValueListenableBuilder<bool>(
        valueListenable: webSync,
        builder: (context, v, _) => AppToggleRow(tr('Đồng bộ cuộn cho cả phòng'), key: const ValueKey('web-sync'), value: v, onChanged: (x) => webSync.value = x),
      ),
      if (room.webUrl != null) ...[
        const SizedBox(height: 6),
        AppButton(tr('Dừng website'), key: const ValueKey('web-close'), kind: AppButtonKind.danger, confirm: true, onPressed: () async => room.closeWeb()),
      ],
    ]);
  }
}

/// Trang có chặn nhúng không (X-Frame-Options / CSP frame-ancestors): có thì TV / web hiện mã QR thay cho trang.
Future<String?> webEmbedNote(String url) async {
  try {
    final r = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 6));
    final xfo = (r.headers['x-frame-options'] ?? '').toLowerCase();
    final csp = (r.headers['content-security-policy'] ?? '').toLowerCase();
    if (xfo.contains('deny') || xfo.contains('sameorigin') || RegExp(r"frame-ancestors\s+('none'|'self')").hasMatch(csp)) {
      return tr('Trang này không cho nhúng: TV và trình duyệt sẽ hiện mã QR để mở trên điện thoại');
    }
  } catch (_) {}
  return null;
}
