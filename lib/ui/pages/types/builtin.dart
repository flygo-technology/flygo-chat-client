import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../i18n/i18n.dart';
import '../../meet/meet_home.dart' show meetToast;
import '../../meet/meet_present.dart' show MeetPresentView, pickPresentPdf;
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
    editor: (context, ctx) => Column(children: [
      PageContentField(ctx, 'heading', tr('Dòng chữ lớn')),
      PageContentField(ctx, 'subtitle', tr('Lời chào / ghi chú'), maxLines: 3),
    ]),
  ));
  registerPageType(PageTypeSpec(
    type: 'video',
    label: tr('Video'),
    desc: tr('Phát đồng bộ cho mọi người'),
    icon: Icons.smart_display_outlined,
    color: const Color(0xFFD93025),
    view: (context, ctx) => _Video(ctx, key: ValueKey('v:${ctx.page.id}:${ctx.page.content['url']}')),
    editor: (context, ctx) => PageContentField(ctx, 'url', tr('Đường dẫn video (mp4, m3u8)')),
  ));
  registerPageType(PageTypeSpec(
    type: 'doc',
    label: tr('Tài liệu'),
    desc: tr('Slide, PDF, Word, Excel'),
    icon: Icons.slideshow_rounded,
    color: const Color(0xFFF29900),
    view: (context, ctx) => _Doc(ctx),
    editor: (context, ctx) => _DocEditor(ctx),
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
class _Welcome extends StatelessWidget {
  final PageCtx ctx;
  const _Welcome(this.ctx);
  @override
  Widget build(BuildContext context) {
    final c = ctx.page.content;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0E5C55), Color(0xFF173431)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${c['heading'] ?? ctx.page.title}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700)),
            if ('${c['subtitle'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('${c['subtitle']}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB7E4DD), fontSize: 20)),
            ],
          ]),
        ),
      ),
    );
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

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
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
      padding: const EdgeInsets.all(20),
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
