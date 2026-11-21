import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../state/app_state.dart';
import '../page_media.dart';
import '../pages_api.dart' show pageAssetUrl;
import '../stage_frame.dart' show StageBackgroundPicker, StageMetrics, StagePill, StageTheme, stageBackground, stageBgLight;

import '../../../i18n/i18n.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../../meet/meet_present.dart' show MeetPresentView, pickPresentPdf;
import '../page_thumb.dart' show PdfThumb;
import '../page_types.dart';

// Loại trang có sẵn: Chào mừng, Video, Tài liệu (Slide / PDF / Word / Excel), Chương trình họp, Biên bản.

const _sub = Color(0xFF9AA0A6);
const _field = Color(0xFF3C4043);

InputDecoration pageField(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _sub),
      filled: true,
      fillColor: _field,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      isDense: true,
    );

/// Ô chữ sửa một khoá trong content của trang (lưu khi rời ô / sau 800 ms).
class PageContentField extends StatefulWidget {
  final PageCtx ctx;
  final String k, label;
  final int maxLines;
  const PageContentField(this.ctx, this.k, this.label, {super.key, this.maxLines = 1});
  @override
  State<PageContentField> createState() => _PageContentFieldState();
}

class _PageContentFieldState extends State<PageContentField> {
  late final c = TextEditingController(text: '${widget.ctx.page.content[widget.k] ?? ''}');
  Timer? _t;
  void _save() {
    _t?.cancel();
    final v = c.text;
    if (v == '${widget.ctx.page.content[widget.k] ?? ''}') return;
    widget.ctx.api.patch(widget.ctx.page.id, {'content': {...widget.ctx.page.content, widget.k: v}}).then((_) => widget.ctx.reload()).catchError((Object e) {
      if (mounted) meetToast(context, '$e');
    });
  }

  @override
  void dispose() {
    if (_t?.isActive ?? false) _save();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Focus(
          onFocusChange: (f) => f ? null : _save(),
          child: TextField(
            controller: c,
            maxLines: widget.maxLines,
            minLines: 1,
            style: const TextStyle(color: Colors.white),
            decoration: pageField(widget.label),
            onChanged: (_) {
              _t?.cancel();
              _t = Timer(const Duration(milliseconds: 800), _save);
            },
          ),
        ),
      );
}

void registerBuiltinPageTypes() {
  registerPageType(PageTypeSpec(
    type: 'welcome',
    label: tr('Chào mừng'),
    desc: tr('Màn hình chờ đầu buổi, giữa các phần'),
    icon: Icons.waving_hand_outlined,
    color: const Color(0xFF0E9F8E),
    create: (context, call) async => PageDraft(title: tr('Chào mừng'), content: {'heading': call.meetingInfo?.title ?? tr('Chào mừng'), 'subtitle': ''}),
    view: (context, ctx) => _Welcome(ctx),
    editor: (context, ctx) => _WelcomeEditor(ctx),
    stageBleed: true,
  ));
  registerPageType(PageTypeSpec(
    type: 'video',
    label: tr('Video'),
    desc: tr('Phát đồng bộ cho mọi người'),
    icon: Icons.smart_display_outlined,
    color: const Color(0xFFD93025),
    view: (context, ctx) => _Video(ctx, key: ValueKey('v:${ctx.page.id}:${ctx.page.content['url']}')),
    stageThemed: true,
    // Ảnh xem trước: không mở video (nặng), chỉ khung đen + nút phát.
    thumb: (context, call, page, data) => Container(
      decoration: BoxDecoration(
        color: Colors.black,
        image: '${page.content['poster'] ?? ''}'.isEmpty ? null : DecorationImage(image: NetworkImage(pageAssetUrl('${page.content['poster']}')), fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 34),
    ),
    editor: (context, ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageContentField(ctx, 'url', tr('Đường dẫn video (mp4, m3u8)')),
      // Ảnh đại diện (thẻ trang, màn hình chờ trước khi phát).
      Row(children: [
        Expanded(child: PageContentField(ctx, 'poster', tr('Ảnh đại diện (tuỳ chọn)'), key: ValueKey('po:${ctx.page.content['poster']}'))),
        IconButton(
          tooltip: tr('Chọn ảnh đại diện'),
          icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
          onPressed: () async {
            final u = await pickPageMedia(context, ctx.call, image: true);
            if (u == null || !context.mounted) return;
            await ctx.api.patch(ctx.page.id, {'content': {...ctx.page.content, 'poster': u}});
            await ctx.reload();
          },
        ),
      ]),
    ]),
  ));
  registerPageType(PageTypeSpec(
    type: 'doc',
    label: tr('Tài liệu'),
    desc: tr('Slide, PDF, Word, Excel'),
    icon: Icons.slideshow_rounded,
    color: const Color(0xFFF29900),
    view: (context, ctx) => _Doc(ctx),
    editor: (context, ctx) => _DocEditor(ctx),
    stageThemed: true,
    // Thanh cuối: số trang lớn (trang đang chiếu / tổng), tên tệp.
    stageFooter: (context, ctx) {
      final t = StageMetrics.themeOf(context);
      final pr = ctx.call.roomPresent;
      final n = pr != null && pr['page_id'] == ctx.page.id ? (pr['page'] as num?)?.toInt() ?? 1 : 1;
      final total = (ctx.page.file?['pages'] as num?)?.toInt() ?? 0;
      return [
        StagePill(total > 0 ? tr('Trang {0} / {1}', [n, total]) : tr('Trang {0}', [n]), icon: Icons.description_outlined, theme: t),
        if ('${ctx.page.file?['name'] ?? ''}'.isNotEmpty) Text('${ctx.page.file?['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.sub, fontSize: 14)),
      ];
    },
    // Ảnh xem trước: trang PDF đang chiếu (nếu đang trên sân khấu), không thì trang 1.
    thumb: (context, call, page, data) {
      final pr = call.roomPresent;
      final n = pr != null && pr['page_id'] == page.id ? (pr['page'] as num?)?.toInt() ?? 1 : 1;
      return PdfThumb(file: page.file, page: n);
    },
  ));
  registerPageType(PageTypeSpec(
    type: 'agenda',
    label: tr('Chương trình họp'),
    desc: tr('Các mục, thời gian, người phụ trách'),
    icon: Icons.format_list_numbered_rounded,
    color: const Color(0xFF1A73E8),
    view: (context, ctx) => ctx.onStage ? _AgendaStage(ctx) : _Agenda(ctx),
    editor: (context, ctx) => _AgendaEditor(ctx),
    stageThemed: true,
    stageFooter: (context, ctx) => _agendaFooter(context, ctx),
  ));
  registerPageType(PageTypeSpec(
    type: 'minutes',
    label: tr('Biên bản'),
    desc: tr('Mọi người cùng ghi, việc cần làm'),
    icon: Icons.edit_note_rounded,
    color: const Color(0xFF9334E6),
    create: (context, call) async => PageDraft(title: tr('Biên bản: {0}', [call.meetingInfo?.title ?? tr('cuộc họp')])),
    view: (context, ctx) => ctx.onStage ? _MinutesStage(ctx) : _Minutes(ctx),
    stageThemed: true,
    stageFooter: (context, ctx) {
      final t = StageMetrics.themeOf(context);
      final v = ctx.view;
      final tasks = (v['tasks'] as List? ?? const []);
      return [
        if ('${v['edited_by'] ?? ''}'.isNotEmpty) StagePill(tr('{0} vừa ghi', [v['edited_by']]), icon: Icons.edit_outlined, theme: t, accent: true),
        if (v['closed'] == true) StagePill(tr('Đã chốt'), icon: Icons.lock_outline_rounded, theme: t),
        const Spacer(),
        StagePill(tr('{0} việc cần làm', [tasks.length]), icon: Icons.checklist_rounded, theme: t),
      ];
    },
  ));
}

// ------------------------------------------------------------------ Chào mừng
// content: heading, subtitle (mô tả), icon, bg (màu / chuyển màu có sẵn), bg_image, show_online, countdown, countdown_to (ms; 0 =
// giờ bắt đầu cuộc họp), music (đường dẫn), music_volume (0..100), music_devices (phát cả trên máy cá nhân; mặc định chỉ TV).
class _Welcome extends StatefulWidget {
  final PageCtx ctx;
  const _Welcome(this.ctx);
  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  Timer? _tick;
  AudioPlayer? _player;
  String _playing = '';

  Map<String, dynamic> get c => widget.ctx.page.content;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _music();
    });
    _music();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _player?.dispose();
    super.dispose();
  }

  /// Nhạc nền: chỉ khi trang đang trên sân khấu và cho phát trên máy cá nhân; nhỏ lại khi có người nói (tiếng họp không bị át).
  void _music() {
    final url = pageAssetUrl('${c['music'] ?? ''}');
    final want = widget.ctx.onStage && c['music_devices'] == true && url.startsWith('http');
    if (!want) {
      if (_playing.isNotEmpty) {
        _player?.stop();
        _playing = '';
      }
      return;
    }
    final p = _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.loop);
    if (_playing != url) {
      _playing = url;
      p.play(UrlSource(url)).catchError((_) {});
    }
    final vol = (((c['music_volume'] as num?)?.toDouble() ?? 40) / 100).clamp(0.0, 1.0);
    final talking = widget.ctx.call.participants.any((x) => x.speaking && x.unmuted) || (!widget.ctx.call.muted && widget.ctx.call.participants.isEmpty);
    p.setVolume(talking ? vol * .25 : vol).catchError((_) {});
  }

  String _left() {
    int to = (c['countdown_to'] as num?)?.toInt() ?? 0;
    if (to == 0) to = (widget.ctx.call.roomMeeting['start'] as num?)?.toInt() ?? 0;
    final ms = to - DateTime.now().millisecondsSinceEpoch;
    if (ms <= 0) return '';
    final s = (ms / 1000).ceil(), h = s ~/ 3600;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(s ~/ 60 % 60)}:${two(s % 60)}' : '${two(s ~/ 60)}:${two(s % 60)}';
  }

  static const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];

  @override
  Widget build(BuildContext context) {
    final metrics = StageMetrics.of(context);
    final t = metrics?.theme ?? StageTheme.of(widget.ctx.call.roomStage?['theme_cfg'] as Map?);
    final bg = '${c['bg'] ?? ''}', img = '${c['bg_image'] ?? ''}';
    final light = img.isEmpty && stageBgLight(bg.isEmpty ? 'linear-gradient(135deg,#0E5C55,#173431)' : bg, t);
    final fg = light ? const Color(0xFF141A23) : Colors.white;
    final sub = light ? const Color(0xFF4A5565) : const Color(0xFFC9D2DE);
    final eyebrow = light ? t.accent : Color.lerp(t.accent, Colors.white, .45)!;
    final call = widget.ctx.call;
    final left = c['countdown'] == true ? _left() : '';
    final people = c['show_online'] == true ? [for (final p in call.participants) if (!p.userId.contains(':')) p.userId] : const <String>[];
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    int start = (c['countdown_to'] as num?)?.toInt() ?? 0;
    if (start == 0) start = (call.roomMeeting['start'] as num?)?.toInt() ?? 0;
    final startAt = start > 0 ? DateTime.fromMillisecondsSinceEpoch(start) : null;

    // Khối giờ riêng (Sếp: tách giờ khỏi tiêu đề): giờ hiện tại + ngày, rồi đếm ngược tới giờ bắt đầu.
    Widget timeBlock(bool portrait) => Container(
          padding: EdgeInsets.symmetric(horizontal: portrait ? 18 : 28, vertical: portrait ? 14 : 24),
          decoration: BoxDecoration(
            color: (light ? Colors.white : Colors.black).withValues(alpha: light ? .7 : .28),
            borderRadius: BorderRadius.circular(portrait ? 18 : 24),
            border: Border.all(color: fg.withValues(alpha: .10)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: portrait ? CrossAxisAlignment.start : CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${two(now.hour)}:${two(now.minute)}', style: TextStyle(color: fg, fontSize: portrait ? 40 : 64, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${_weekdays[now.weekday - 1]}\n${two(now.day)}/${two(now.month)}/${now.year}', style: TextStyle(color: sub, fontSize: portrait ? 13 : 17, height: 1.3)),
              ),
            ]),
            if (left.isNotEmpty || startAt != null) ...[
              Container(width: portrait ? 160 : 260, height: 1, margin: EdgeInsets.symmetric(vertical: portrait ? 10 : 18), color: fg.withValues(alpha: .14)),
              Text(
                left.isNotEmpty ? tr('BẮT ĐẦU SAU') : tr('BẮT ĐẦU LÚC'),
                style: TextStyle(color: sub, fontSize: portrait ? 11 : 14, fontWeight: FontWeight.w700, letterSpacing: 1.6),
              ),
              const SizedBox(height: 4),
              Text(
                left.isNotEmpty ? left : '${two(startAt!.hour)}:${two(startAt.minute)}',
                style: TextStyle(color: left.isNotEmpty ? fg : sub, fontSize: portrait ? 44 : 84, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1),
              ),
            ],
          ]),
        );

    Widget peopleRow(bool portrait) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: (portrait ? 30.0 : 44.0) * (people.take(5).length + (people.length > 5 ? 1 : 0)) * .75 + (portrait ? 10 : 14),
            height: portrait ? 34 : 48,
            child: Stack(children: [
              for (final (i, id) in [...people.take(5), if (people.length > 5) '+${people.length - 5}'].indexed)
                Positioned(
                  left: i * (portrait ? 22.0 : 33.0),
                  child: Container(
                    width: portrait ? 34 : 48,
                    height: portrait ? 34 : 48,
                    decoration: BoxDecoration(
                      color: id.startsWith('+') ? const Color(0xFF2A3446) : t.series[i % t.series.length],
                      shape: BoxShape.circle,
                      border: Border.all(color: light ? Colors.white : const Color(0xFF13233F), width: 3),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      id.startsWith('+') ? id : _nameOf(context, id).trim().characters.first.toUpperCase(),
                      style: TextStyle(color: Colors.white, fontSize: portrait ? 12 : 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('{0} người đã vào', [people.length]), style: TextStyle(color: fg, fontSize: portrait ? 16 : 22, fontWeight: FontWeight.w700)),
              Text(
                people.take(4).map((id) => _nameOf(context, id).split(' ').last).join(', ') + (people.length > 4 ? tr(' và {0} người khác', [people.length - 4]) : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: sub, fontSize: portrait ? 12 : 15),
              ),
            ]),
          ),
        ]);

    final heading = '${c['heading'] ?? widget.ctx.page.title}';
    final subtitle = '${c['subtitle'] ?? ''}';
    final eyebrowText = '${call.roomMeeting['title'] ?? ''}'.trim();
    Widget texts(bool portrait) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ('${c['icon'] ?? ''}'.isNotEmpty) Text('${c['icon']}', style: TextStyle(fontSize: portrait ? 40 : 60)),
          if (eyebrowText.isNotEmpty && eyebrowText != heading)
            Text(eyebrowText.toUpperCase(), style: TextStyle(color: eyebrow, fontSize: portrait ? 13 : 18, fontWeight: FontWeight.w700, letterSpacing: 2)),
          SizedBox(height: portrait ? 8 : 14),
          Text(heading, style: TextStyle(color: fg, fontSize: portrait ? 36 : 68, fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -.5)),
          if (subtitle.isNotEmpty) ...[
            SizedBox(height: portrait ? 10 : 18),
            Text(subtitle, style: TextStyle(color: sub, fontSize: portrait ? 16 : 24, height: 1.45)),
          ],
        ]);

    Widget layout(Size size, bool portrait) {
      if (portrait) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 64, 20, 64),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            timeBlock(true),
            const Spacer(),
            texts(true),
            const Spacer(),
            if (people.isNotEmpty) peopleRow(true),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(96, 120, 96, 92),
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Vùng thấp (cửa sổ nhỏ): khối chữ + người đã vào co lại cho vừa, không tràn.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth, minWidth: box.maxWidth, minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      texts(false),
                      const Spacer(),
                      if (people.isNotEmpty) ...[const SizedBox(height: 24), peopleRow(false)],
                    ]),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
          Align(alignment: Alignment.topRight, child: timeBlock(false)),
        ]),
      );
    }

    final body = metrics != null
        ? layout(metrics.size, metrics.portrait)
        // Ngoài khung sân khấu (xem trên điện thoại, cửa sổ nhỏ, ảnh thu nhỏ): dựng theo đúng tỉ lệ ô (dọc: bố cục dọc, rộng
        // 440; ngang: rộng 1280) rồi co cho vừa, không cắt mất chữ / khối giờ.
        : LayoutBuilder(builder: (context, box) {
            if (!box.maxWidth.isFinite || !box.maxHeight.isFinite || box.maxWidth <= 0 || box.maxHeight <= 0) {
              return FittedBox(child: SizedBox(width: 1280, height: 720, child: layout(const Size(1280, 720), false)));
            }
            final portrait = box.maxWidth < box.maxHeight * 1.05;
            final lw = portrait ? 440.0 : 1280.0;
            final lh = (lw * box.maxHeight / box.maxWidth).clamp(portrait ? 560.0 : 560.0, 4000.0);
            return FittedBox(child: SizedBox(width: lw, height: lh, child: layout(Size(lw, lh), portrait)));
          });
    return Container(
      decoration: bg.isEmpty && img.isEmpty
          ? stageBackground('linear-gradient(135deg,#0E5C55,#173431)', '', t)
          : stageBackground(bg, img, t),
      child: DefaultTextStyle.merge(style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]), child: body),
    );
  }

  String _nameOf(BuildContext context, String uid) {
    final n = context.read<AppState>().users[uid]?.displayName ?? '';
    return n.isEmpty ? tr('Người tham gia') : n;
  }
}

/// Trình soạn trang Chào mừng (xem trước ở trên, trong bảng soạn trang).
class _WelcomeEditor extends StatelessWidget {
  final PageCtx ctx;
  const _WelcomeEditor(this.ctx);

  Future<void> _set(BuildContext context, Map<String, dynamic> v) async {
    try {
      await ctx.api.patch(ctx.page.id, {'content': {...ctx.page.content, ...v}});
      await ctx.reload();
    } catch (e) {
      if (context.mounted) meetToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ctx.page.content;
    Widget sw(String k, String label, {String? sub}) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: c[k] == true,
          title: Text(label, style: const TextStyle(color: Colors.white)),
          subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: _sub, fontSize: 12)),
          onChanged: (v) => _set(context, {k: v}),
        );
    final vol = ((c['music_volume'] as num?)?.toDouble() ?? 40).clamp(0.0, 100.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageContentField(ctx, 'heading', tr('Dòng chữ lớn trên màn hình')),
      PageContentField(ctx, 'subtitle', tr('Mô tả'), maxLines: 3),
      Row(children: [
        SizedBox(width: 150, child: PageContentField(ctx, 'icon', tr('Biểu tượng'))),
      ]),
      StageBackgroundPicker(
        call: ctx.call,
        theme: StageTheme.of(ctx.call.roomStage?['theme_cfg'] as Map?),
        value: '${c['bg'] ?? ''}',
        image: '${c['bg_image'] ?? ''}',
        onBg: (k) => _set(context, {'bg': k, 'bg_image': ''}),
        onImage: (u) => _set(context, {'bg_image': u}),
      ),
      const SizedBox(height: 6),
      sw('show_online', tr('Hiện danh sách người đã vào')),
      sw('countdown', tr('Đếm ngược'), sub: tr('Tới giờ bắt đầu cuộc họp')),
      const Divider(color: Colors.white12),
      Row(children: [
        Expanded(child: PageContentField(ctx, 'music', tr('Nhạc nền (tuỳ chọn)'), key: ValueKey('mu:${c['music']}'))),
        IconButton(
          tooltip: tr('Chọn nhạc'),
          icon: const Icon(Icons.library_music_outlined, color: Colors.white),
          onPressed: () async {
            final u = await pickPageMedia(context, ctx.call, image: false);
            if (u != null && context.mounted) await _set(context, {'music': u});
          },
        ),
      ]),
      Row(children: [
        const Icon(Icons.volume_down_rounded, color: _sub, size: 20),
        Expanded(
          child: Slider(
            value: vol,
            max: 100,
            divisions: 20,
            label: '${vol.round()}%',
            onChanged: (_) {},
            onChangeEnd: (v) => _set(context, {'music_volume': v.round()}),
          ),
        ),
        Text('${vol.round()}%', style: const TextStyle(color: _sub)),
      ]),
      sw('music_devices', tr('Phát nhạc cả trên máy của mọi người'), sub: tr('Mặc định chỉ phát trên TV / màn hình phòng; nhạc nhỏ lại khi có người nói')),
    ]);
  }
}

// ------------------------------------------------------------------ Video đồng bộ
class _Video extends StatefulWidget {
  final PageCtx ctx;
  const _Video(this.ctx, {super.key});
  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  VideoPlayerController? _v;
  String? _err;
  /// Kiểm lại mỗi giây: theo vị trí chung, nhỏ tiếng khi có người nói.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _sync());
    final url = '${widget.ctx.page.content['url'] ?? ''}';
    if (url.isEmpty) return;
    _v = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        if (mounted) setState(_sync);
      }).catchError((Object e) {
        if (mounted) setState(() => _err = '$e');
      });
  }

  @override
  void didUpdateWidget(_Video old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Theo trạng thái chung {playing, pos, at}: lệch quá 1,5 giây thì tua lại.
  void _sync() {
    final v = _v;
    if (v == null || !v.value.isInitialized) return;
    final s = widget.ctx.view;
    final playing = s['playing'] == true;
    final pos = (s['pos'] as num?)?.toDouble() ?? 0;
    final at = (s['at'] as num?)?.toInt() ?? 0;
    final want = playing ? pos + (DateTime.now().millisecondsSinceEpoch - at) / 1000 : pos;
    final cur = v.value.position.inMilliseconds / 1000;
    if ((cur - want).abs() > 1.5) v.seekTo(Duration(milliseconds: (want * 1000).round()));
    if (playing && !v.value.isPlaying) v.play();
    if (!playing && v.value.isPlaying) v.pause();
    // Tiếng video nhỏ lại khi có người nói: tiếng họp luôn nghe rõ.
    final talking = widget.ctx.call.participants.any((x) => x.speaking && x.unmuted);
    v.setVolume(talking ? .25 : 1);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _v?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: const Color(0xFFF0646A).withValues(alpha: .16), borderRadius: BorderRadius.circular(22)),
            child: const Icon(Icons.smart_display_outlined, color: Color(0xFFF0646A), size: 40),
          ),
          const SizedBox(height: 16),
          Text(widget.ctx.page.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(tr('Chưa có đường dẫn video · chủ trang thêm trong phần Sửa'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 16)),
        ]),
      );
    }
    if (_err != null) return Center(child: Text(tr('Không phát được video: {0}', [_err]), style: const TextStyle(color: Colors.white70)));
    final playing = widget.ctx.view['playing'] == true;
    return Stack(children: [
      Positioned.fill(
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: v.value.isInitialized ? AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)) : const CircularProgressIndicator(),
        ),
      ),
      if (widget.ctx.control)
        Positioned(
          left: 12,
          bottom: 12,
          child: Row(children: [
            IconButton.filledTonal(
              onPressed: () => widget.ctx.act(playing ? 'pause' : 'play', {'pos': v.value.position.inMilliseconds / 1000}),
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
            IconButton.filledTonal(onPressed: () => widget.ctx.act('seek', {'pos': 0}), icon: const Icon(Icons.replay_rounded)),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ Tài liệu
class _Doc extends StatelessWidget {
  final PageCtx ctx;
  const _Doc(this.ctx);
  @override
  Widget build(BuildContext context) {
    final pr = ctx.call.roomPresent;
    // Đang chiếu trên sân khấu: dùng khung trình chiếu tài liệu có sẵn (đồng bộ trang, bút laser).
    if (ctx.onStage && pr != null && pr['page_id'] == ctx.page.id) return MeetPresentView(call: ctx.call, compact: false);
    final f = ctx.page.file;
    // Trên sân khấu, chưa bắt đầu trình chiếu: trang 1 lớn trong khung giấy (thay cho biểu tượng).
    if (ctx.onStage && f != null && StageMetrics.of(context) != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 16))]),
            clipBehavior: Clip.antiAlias,
            child: PdfThumb(file: f, page: 1),
          ),
        ),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.slideshow_rounded, color: Color(0xFFF29900), size: 48),
        const SizedBox(height: 10),
        Text(f == null ? tr('Chưa chọn tài liệu') : '${f['name']}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        if (f != null && (f['pages'] ?? 0) != 0) Text(tr('{0} trang', [f['pages']]), style: const TextStyle(color: _sub)),
      ]),
    );
  }
}

class _DocEditor extends StatefulWidget {
  final PageCtx ctx;
  const _DocEditor(this.ctx);
  @override
  State<_DocEditor> createState() => _DocEditorState();
}

class _DocEditorState extends State<_DocEditor> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final f = widget.ctx.page.file;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.description_outlined, color: Colors.white),
      title: Text(f == null ? tr('Chưa chọn tài liệu') : '${f['name']}', style: const TextStyle(color: Colors.white)),
      subtitle: f == null ? null : Text(tr('{0} trang', [f['pages'] ?? '?']), style: const TextStyle(color: _sub)),
      trailing: _busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : FilledButton.tonal(
              onPressed: () async {
                setState(() => _busy = true);
                try {
                  final r = await pickPresentPdf(context, widget.ctx.call);
                  if (r != null) {
                    await widget.ctx.api.upload(widget.ctx.page.id, r.$1, r.$2, r.$3);
                    await widget.ctx.reload();
                  }
                } catch (e) {
                  if (context.mounted) meetToast(context, '$e');
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
              child: Text(f == null ? tr('Chọn tài liệu') : tr('Đổi')),
            ),
    );
  }
}

// ------------------------------------------------------------------ Chương trình họp
List<Map<String, dynamic>> _items(PageCtx ctx) => [for (final x in (ctx.page.content['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];

class _Agenda extends StatelessWidget {
  final PageCtx ctx;
  const _Agenda(this.ctx);
  @override
  Widget build(BuildContext context) {
    final items = _items(ctx);
    final cur = (ctx.view['current'] as num?)?.toInt() ?? 0;
    return Container(
      color: const Color(0xFF17191C),
      // Trên sân khấu: chừa chỗ cho dải điều khiển ở góc trên.
      padding: EdgeInsets.fromLTRB(20, ctx.onStage ? 52 : 20, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ctx.page.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (items.isEmpty) Text(tr('Chưa có mục nào'), style: const TextStyle(color: _sub)),
        Expanded(
          child: ListView(children: [
            for (final (i, it) in items.indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: i == cur ? const Color(0xFF173431) : const Color(0xFF26282C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: i == cur ? const Color(0xFF0E9F8E) : Colors.transparent),
                ),
                child: InkWell(
                  onTap: ctx.control ? () => ctx.act('goto', {'index': i}) : null,
                  child: Row(children: [
                    Text('${i + 1}.', style: TextStyle(color: i < cur ? _sub : Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${it['text'] ?? ''}', style: TextStyle(color: i < cur ? _sub : Colors.white, fontSize: 16, decoration: i < cur ? TextDecoration.lineThrough : null))),
                    if ('${it['who'] ?? ''}'.isNotEmpty) Text('${it['who']}  ', style: const TextStyle(color: _sub)),
                    if ((it['minutes'] ?? 0) != 0) Text('${it['minutes']}′', style: const TextStyle(color: _sub)),
                  ]),
                ),
              ),
          ]),
        ),
        if (ctx.control && items.isNotEmpty)
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton.filledTonal(onPressed: cur > 0 ? () => ctx.act('prev') : null, icon: const Icon(Icons.chevron_left_rounded)),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: cur < items.length - 1 ? () => ctx.act('next') : null, icon: const Icon(Icons.chevron_right_rounded)),
          ]),
      ]),
    );
  }
}

/// Chương trình trên sân khấu (mockup Họp): mục đang bàn lớn bên trái (thứ tự, tên, người phụ trách, đếm giờ của mục so với số
/// phút dự kiến), danh sách gọn bên phải (mục đã xong có dấu ✓).
class _AgendaStage extends StatefulWidget {
  final PageCtx ctx;
  const _AgendaStage(this.ctx);
  @override
  State<_AgendaStage> createState() => _AgendaStageState();
}

class _AgendaStageState extends State<_AgendaStage> {
  Timer? _tick;
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final m = StageMetrics.of(context);
    // Ngoài khung sân khấu (ảnh thu nhỏ của thẻ trang): dựng ở kích thước vùng nội dung của khung rồi co cho vừa.
    if (m == null) return FittedBox(child: SizedBox(width: 1168, height: 560, child: StageMetrics(theme: const StageTheme(), portrait: false, size: const Size(1168, 560), child: _AgendaStage(ctx))));
    final t = m.theme;
    final portrait = m.portrait;
    final items = _items(ctx);
    if (items.isEmpty) return Center(child: Text(tr('Chưa có mục nào'), style: TextStyle(color: t.sub, fontSize: 24)));
    final cur = ((ctx.view['current'] as num?)?.toInt() ?? 0).clamp(0, items.length - 1);
    final it = items[cur];
    final mins = (it['minutes'] as num?)?.toInt() ?? 0;
    final started = (ctx.view['started_at'] as num?)?.toInt() ?? 0;
    final el = started > 0 ? ((DateTime.now().millisecondsSinceEpoch - started) / 1000).floor().clamp(0, 359999) : 0;
    String two(int n) => n.toString().padLeft(2, '0');
    final over = mins > 0 && el > mins * 60;
    final main = Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('MỤC {0} / {1} · ĐANG BÀN', [cur + 1, items.length]), style: TextStyle(color: Color.lerp(t.accent, t.light ? Colors.black : Colors.white, .35), fontSize: portrait ? 13 : 16, fontWeight: FontWeight.w700, letterSpacing: 1.8)),
      SizedBox(height: portrait ? 10 : 18),
      Text('${it['text'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: portrait ? 34 : 60, fontWeight: FontWeight.w800, height: 1.08)),
      if ('${it['who'] ?? ''}'.isNotEmpty) ...[
        SizedBox(height: portrait ? 10 : 18),
        Row(children: [
          CircleAvatar(radius: 16, backgroundColor: t.accent, child: Text('${it['who']}'.trim().characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Text('${it['who']}', style: TextStyle(color: t.text, fontSize: portrait ? 16 : 20)),
        ]),
      ],
      if (started > 0 || mins > 0) ...[
        SizedBox(height: portrait ? 18 : 30),
        Row(children: [
          Text('${two(el ~/ 60)}:${two(el % 60)}', style: TextStyle(color: over ? const Color(0xFFF0646A) : t.text, fontSize: portrait ? 28 : 44, fontWeight: FontWeight.w800)),
          const SizedBox(width: 16),
          if (mins > 0) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (el / (mins * 60)).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: t.surface2,
                  valueColor: AlwaysStoppedAnimation(over ? const Color(0xFFF0646A) : t.accent),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(tr('trên {0}:00', [mins]), style: TextStyle(color: t.sub, fontSize: portrait ? 14 : 17)),
          ],
        ]),
      ],
    ]);
    if (portrait) return main;
    return Row(children: [
      Expanded(child: main),
      const SizedBox(width: 48),
      SizedBox(
        width: 400,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final (i, x) in items.take(8).indexed)
            Container(
              height: 56,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: i == cur ? t.accent.withValues(alpha: .16) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: i == cur ? Border.all(color: t.accent, width: 1.5) : null,
              ),
              child: Row(children: [
                SizedBox(
                  width: 28,
                  child: i < cur
                      ? const Icon(Icons.check_rounded, size: 20, color: Color(0xFF38C793))
                      : Text('${i + 1}', style: TextStyle(color: i == cur ? t.text : t.sub, fontWeight: FontWeight.w700, fontSize: 17)),
                ),
                Expanded(
                  child: Text('${x['text'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: i < cur ? t.sub : t.text, fontSize: 17, fontWeight: i == cur ? FontWeight.w700 : FontWeight.w400)),
                ),
                if ((x['minutes'] ?? 0) != 0) Text('${x['minutes']}′', style: TextStyle(color: t.sub, fontSize: 15)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// Thanh cuối của Chương trình: mục tiếp theo, nút mục trước / sau cho người trình chiếu.
List<Widget> _agendaFooter(BuildContext context, PageCtx ctx) {
  final t = StageMetrics.themeOf(context);
  final items = _items(ctx);
  if (items.isEmpty) return const [];
  final cur = ((ctx.view['current'] as num?)?.toInt() ?? 0).clamp(0, items.length - 1);
  final next = cur + 1 < items.length ? items[cur + 1] : null;
  return [
    if (MediaQuery.sizeOf(context).width >= 600)
      StagePill(next == null ? tr('Mục cuối') : tr('Tiếp: {0}', ['${next['text']}${'${next['who'] ?? ''}'.isEmpty ? '' : ' · ${next['who']}'}']), theme: t),
    if (ctx.control) ...[
      const Spacer(),
      IconButton.filledTonal(tooltip: tr('Mục trước'), onPressed: cur > 0 ? () => ctx.act('prev') : null, icon: const Icon(Icons.chevron_left_rounded)),
      IconButton.filledTonal(tooltip: tr('Mục sau'), onPressed: cur < items.length - 1 ? () => ctx.act('next') : null, icon: const Icon(Icons.chevron_right_rounded)),
    ],
  ];
}

class _AgendaEditor extends StatefulWidget {
  final PageCtx ctx;
  const _AgendaEditor(this.ctx);
  @override
  State<_AgendaEditor> createState() => _AgendaEditorState();
}

class _AgendaEditorState extends State<_AgendaEditor> {
  late List<Map<String, dynamic>> items = _items(widget.ctx);
  final _text = TextEditingController(), _who = TextEditingController(), _min = TextEditingController();

  Future<void> _save() async {
    try {
      await widget.ctx.api.patch(widget.ctx.page.id, {'content': {...widget.ctx.page.content, 'items': items}});
      await widget.ctx.reload();
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _who.dispose();
    _min.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: true,
          onReorderItem: (a, b) {
            setState(() => items.insert(b, items.removeAt(a)));
            _save();
          },
          children: [
            for (final (i, it) in items.indexed)
              ListTile(
                key: ValueKey('a$i${it['text']}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${i + 1}. ${it['text']}', style: const TextStyle(color: Colors.white)),
                subtitle: Text([if ('${it['who'] ?? ''}'.isNotEmpty) it['who'], if ((it['minutes'] ?? 0) != 0) '${it['minutes']}′'].join(' · '), style: const TextStyle(color: _sub)),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, color: _sub),
                  onPressed: () {
                    setState(() => items.removeAt(i));
                    _save();
                  },
                ),
              ),
          ],
        ),
        Row(children: [
          Expanded(flex: 5, child: TextField(controller: _text, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Mục mới')))),
          const SizedBox(width: 6),
          Expanded(flex: 3, child: TextField(controller: _who, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Người')))),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: TextField(controller: _min, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: pageField(tr('Phút')))),
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, color: Color(0xFF8AB4F8)),
            onPressed: () {
              final t = _text.text.trim();
              if (t.isEmpty) return;
              setState(() => items.add({'text': t, 'who': _who.text.trim(), 'minutes': int.tryParse(_min.text.trim()) ?? 0}));
              _text.clear();
              _who.clear();
              _min.clear();
              _save();
            },
          ),
        ]),
      ]);
}

// ------------------------------------------------------------------ Biên bản
/// Biên bản trên sân khấu (mockup Họp): trang giấy sáng chữ to (dòng bắt đầu bằng "1." / "#" là đề mục), việc cần làm bên phải.
class _MinutesStage extends StatelessWidget {
  final PageCtx ctx;
  const _MinutesStage(this.ctx);
  @override
  Widget build(BuildContext context) {
    final m = StageMetrics.of(context);
    if (m == null) return FittedBox(child: SizedBox(width: 1168, height: 560, child: StageMetrics(theme: const StageTheme(), portrait: false, size: const Size(1168, 560), child: _MinutesStage(ctx))));
    final t = m.theme;
    final portrait = m.portrait;
    final v = ctx.view;
    final text = '${v['text'] ?? ''}'.trim();
    final tasks = [for (final x in (v['tasks'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final heading = RegExp(r'^(#+\s*|\d+[.)]\s+)');
    final lines = text.isEmpty ? <String>[] : text.split('\n');
    final paper = Container(
      padding: EdgeInsets.all(portrait ? 18 : 32),
      decoration: BoxDecoration(color: const Color(0xFFF7F8FA), borderRadius: BorderRadius.circular(18)),
      child: lines.isEmpty
          ? Text(tr('Biên bản đang trống. Mọi người cùng ghi trên app.'), style: const TextStyle(color: Color(0xFF5C6670), fontSize: 20))
          : ListView(padding: EdgeInsets.zero, reverse: false, physics: const NeverScrollableScrollPhysics(), children: [
              for (final l in lines.length > 40 ? lines.sublist(lines.length - 40) : lines)
                if (l.trim().isEmpty)
                  const SizedBox(height: 10)
                else if (heading.hasMatch(l))
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(l.replaceFirst(RegExp(r'^#+\s*'), ''), style: TextStyle(color: const Color(0xFF1B2430), fontSize: portrait ? 17 : 21, fontWeight: FontWeight.w700)),
                  )
                else
                  Text(l, style: TextStyle(color: const Color(0xFF2C3644), fontSize: portrait ? 15 : 19, height: 1.5)),
            ]),
    );
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(tr('VIỆC CẦN LÀM'), style: TextStyle(color: t.sub, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
        const Spacer(),
        Text(tr('{0} / {1} xong', [tasks.where((x) => x['done'] == true).length, tasks.length]), style: TextStyle(color: t.sub, fontSize: 14)),
      ]),
      const SizedBox(height: 12),
      if (tasks.isEmpty) Text(tr('Chưa có việc nào'), style: TextStyle(color: t.sub, fontSize: 16)),
      for (final x in tasks.take(7))
        Opacity(
          opacity: x['done'] == true ? .6 : 1,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(x['done'] == true ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 22, color: x['done'] == true ? const Color(0xFF38C793) : t.sub),
              const SizedBox(width: 12),
              Expanded(
                child: Text('${x['text'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 16, decoration: x['done'] == true ? TextDecoration.lineThrough : null)),
              ),
              if ('${x['who'] ?? ''}${x['due'] ?? ''}'.isNotEmpty)
                Text([if ('${x['who'] ?? ''}'.isNotEmpty) x['who'], if ('${x['due'] ?? ''}'.isNotEmpty) x['due']].join(' · '), style: TextStyle(color: t.sub, fontSize: 13)),
            ]),
          ),
        ),
    ]);
    if (portrait) return Column(children: [Expanded(child: paper), const SizedBox(height: 12), SizedBox(height: 200, child: SingleChildScrollView(child: side))]);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: paper), const SizedBox(width: 28), SizedBox(width: 400, child: side)]);
  }
}

class _Minutes extends StatefulWidget {
  final PageCtx ctx;
  const _Minutes(this.ctx);
  @override
  State<_Minutes> createState() => _MinutesState();
}

class _MinutesState extends State<_Minutes> {
  late final _c = TextEditingController(text: '${widget.ctx.view['text'] ?? ''}');
  final _task = TextEditingController();
  final _focus = FocusNode();
  Timer? _t;

  @override
  void didUpdateWidget(_Minutes old) {
    super.didUpdateWidget(old);
    // Người khác vừa ghi: cập nhật khi mình không đang gõ.
    final v = '${widget.ctx.view['text'] ?? ''}';
    if (!_focus.hasFocus && v != _c.text) _c.text = v;
  }

  @override
  void dispose() {
    if (_t?.isActive ?? false) widget.ctx.act('text', {'text': _c.text});
    _t?.cancel();
    _c.dispose();
    _task.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.ctx.view;
    final closed = v['closed'] == true;
    final ro = closed || widget.ctx.data.role == 'viewer';
    final tasks = [for (final x in (v['tasks'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    // Material (không phải Container tô màu): ô đánh dấu việc cần làm hiện được hiệu ứng bấm. Nền tối như mọi app trong họp.
    return Material(
      color: const Color(0xFF23262C),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text(widget.ctx.page.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
          if ('${v['edited_by'] ?? ''}'.isNotEmpty) Text(tr('✎ {0}', [v['edited_by']]), style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _c,
          focusNode: _focus,
          readOnly: ro,
          maxLines: null,
          minLines: 6,
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
          decoration: InputDecoration(hintText: ro ? null : tr('Ghi vào biên bản…'), border: InputBorder.none),
          onChanged: (_) {
            _t?.cancel();
            _t = Timer(const Duration(milliseconds: 900), () => widget.ctx.act('text', {'text': _c.text}));
          },
        ),
        const Divider(),
        Text(tr('VIỆC CẦN LÀM'), style: const TextStyle(color: Color(0xFF7FD8CC), fontWeight: FontWeight.w700, fontSize: 12.5)),
        for (final t in tasks)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: t['done'] == true,
            onChanged: ro ? null : (x) => widget.ctx.act('task', {'id': t['id'], 'done': x == true}),
            title: Text('${t['text']}', style: const TextStyle(color: Colors.white)),
            subtitle: Text([t['who'], t['due']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · '), style: const TextStyle(color: Color(0xFF9AA0A6))),
            secondary: ro ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => widget.ctx.act('del_task', {'id': t['id']})),
          ),
        if (!ro)
          TextField(
            controller: _task,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: tr('＋ Việc mới (vd. Giao ray @quang 20/11)'), border: InputBorder.none),
            onSubmitted: (s) {
              final m = RegExp(r'^(.*?)(?:\s+(@\S+))?(?:\s+(\d{1,2}/\d{1,2}))?$').firstMatch(s.trim());
              if (m == null || (m.group(1) ?? '').isEmpty) return;
              widget.ctx.act('add_task', {'text': m.group(1), 'who': m.group(2) ?? '', 'due': m.group(3) ?? ''});
              _task.clear();
            },
          ),
        if (widget.ctx.data.manage)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () => widget.ctx.api.export(widget.ctx.page.id).then((_) {
                  if (context.mounted) meetToast(context, tr('Đã gửi biên bản vào nhóm cuộc họp'));
                }).catchError((Object e) {
                  if (context.mounted) meetToast(context, '$e');
                }),
                child: Text(tr('Gửi vào nhóm')),
              ),
              FilledButton.tonal(onPressed: () => widget.ctx.act(closed ? 'reopen' : 'close'), child: Text(closed ? tr('Mở lại') : tr('Chốt biên bản'))),
            ]),
          ),
      ]),
    );
  }
}
