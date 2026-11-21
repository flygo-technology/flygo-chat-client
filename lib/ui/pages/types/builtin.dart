import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../state/app_state.dart';
import '../page_media.dart';
import '../pages_api.dart' show pageAssetUrl;
import '../stage_frame.dart' show StageBackgroundPicker, StageTheme;
import '../system_pages.dart' show pageBackground;

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
    view: (context, ctx) => _Agenda(ctx),
    editor: (context, ctx) => _AgendaEditor(ctx),
  ));
  registerPageType(PageTypeSpec(
    type: 'minutes',
    label: tr('Biên bản'),
    desc: tr('Mọi người cùng ghi, việc cần làm'),
    icon: Icons.edit_note_rounded,
    color: const Color(0xFF9334E6),
    create: (context, call) async => PageDraft(title: tr('Biên bản: {0}', [call.meetingInfo?.title ?? tr('cuộc họp')])),
    view: (context, ctx) => _Minutes(ctx),
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

  @override
  Widget build(BuildContext context) {
    final bg = '${c['bg'] ?? ''}';
    final light = bg == '#F7F8FA';
    final fg = light ? const Color(0xFF1B2430) : Colors.white;
    final sub = light ? const Color(0xFF5C6670) : const Color(0xFFB7E4DD);
    final left = c['countdown'] == true ? _left() : '';
    final call = widget.ctx.call;
    final people = c['show_online'] == true ? [tr('Bạn'), for (final p in call.participants) if (!p.userId.contains(':')) p.userId] : const <String>[];
    return Container(
      decoration: pageBackground(bg, '${c['bg_image'] ?? ''}'),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if ('${c['icon'] ?? ''}'.isNotEmpty) Text('${c['icon']}', style: const TextStyle(fontSize: 64)),
            Text('${c['heading'] ?? widget.ctx.page.title}', textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 40, fontWeight: FontWeight.w700)),
            if ('${c['subtitle'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('${c['subtitle']}', textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 20)),
            ],
            if (left.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(tr('Bắt đầu sau'), style: TextStyle(color: sub, fontSize: 16)),
              Text(left, style: TextStyle(color: fg, fontSize: 56, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
            ],
            if (people.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(tr('{0} người đã vào', [people.length]), style: TextStyle(color: sub, fontSize: 15)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                  for (final id in people.take(24))
                    Chip(
                      backgroundColor: Colors.black26,
                      side: BorderSide.none,
                      label: Text(id == tr('Bạn') ? id : _nameOf(context, id), style: TextStyle(color: fg, fontSize: 13)),
                    ),
                ]),
              ),
            ],
          ]),
        ),
      ),
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
        SizedBox(width: 110, child: PageContentField(ctx, 'icon', tr('Biểu tượng'))),
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
    if (v == null) return Center(child: Text(tr('Chưa có đường dẫn video'), style: const TextStyle(color: Colors.white70)));
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
    return Container(
      color: const Color(0xFFF7F8FA),
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        Row(children: [
          Expanded(child: Text(widget.ctx.page.title, style: const TextStyle(color: Color(0xFF1B2430), fontSize: 20, fontWeight: FontWeight.w700))),
          if ('${v['edited_by'] ?? ''}'.isNotEmpty) Text(tr('✎ {0}', [v['edited_by']]), style: const TextStyle(color: Color(0xFF5C6670), fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _c,
          focusNode: _focus,
          readOnly: ro,
          maxLines: null,
          minLines: 6,
          style: const TextStyle(color: Color(0xFF1B2430), fontSize: 15, height: 1.5),
          decoration: InputDecoration(hintText: ro ? null : tr('Ghi vào biên bản…'), border: InputBorder.none),
          onChanged: (_) {
            _t?.cancel();
            _t = Timer(const Duration(milliseconds: 900), () => widget.ctx.act('text', {'text': _c.text}));
          },
        ),
        const Divider(),
        Text(tr('VIỆC CẦN LÀM'), style: const TextStyle(color: Color(0xFF0E5C55), fontWeight: FontWeight.w700, fontSize: 12.5)),
        for (final t in tasks)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: t['done'] == true,
            onChanged: ro ? null : (x) => widget.ctx.act('task', {'id': t['id'], 'done': x == true}),
            title: Text('${t['text']}', style: const TextStyle(color: Color(0xFF1B2430))),
            subtitle: Text([t['who'], t['due']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · '), style: const TextStyle(color: Color(0xFF5C6670))),
            secondary: ro ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => widget.ctx.act('del_task', {'id': t['id']})),
          ),
        if (!ro)
          TextField(
            controller: _task,
            style: const TextStyle(color: Color(0xFF1B2430)),
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
