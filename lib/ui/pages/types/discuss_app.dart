import 'dart:async';

import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../bang_tin/api.dart';
import '../../bang_tin/bang_tin_page.dart' show BangTinMe;
import '../../bang_tin/discussion_page.dart' show bangTinSession, kStances, stanceOf;
import '../../bang_tin/reactions.dart' show kDiscussReactionKinds;
import '../../meet/meet_home.dart' show meetToast;
import '../app_kit.dart';
import '../page_types.dart';
import '../stage_frame.dart' show StageTheme;

// Thảo luận theo mockup "mỗi trang là một app" (21/11/2026): quan điểm là bài riêng tư của Bảng tin, cập nhật tức thì (SSE).
// - DiscussPanel (người xem): lập trường + tỉ lệ, sắp xếp, ý kiến (👍 / 👎 / cảm xúc, trả lời 2 cấp ngay tại chỗ), ô viết ý kiến
//   (lập trường, ẩn danh) ngay dưới; menu ⋯ của từng ý kiến (showAppMenu). Không mở hộp thoại / trang mới.
// - DiscussControls (chủ trang): bắt buộc lập trường, cho phép ẩn danh, khoá trả lời, khoá cả thảo luận, ghi Biên bản.

Future<void> _run(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    if (context.mounted) meetToast(context, '$e');
  }
}

String _ago(int ms) {
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return tr('vừa xong');
  if (d.inHours < 1) return tr('{0} phút', [d.inMinutes]);
  if (d.inDays < 1) return tr('{0} giờ', [d.inHours]);
  return tr('{0} ngày', [d.inDays]);
}

/// Phiên Bảng tin + dữ liệu cuộc thảo luận dùng chung cho phần người xem và phần chủ trang.
class _DiscussData extends ChangeNotifier {
  final String id;
  BangTinApi? api;
  BangTinMe? me;
  Map<String, dynamic>? disc;
  List<Map<String, dynamic>> posts = const [];
  String sort = 'new';
  String? error;
  StreamSubscription? _live;
  Timer? _deb;
  _DiscussData(this.id);

  static final _cache = <String, _DiscussData>{};
  static _DiscussData of(String id) => _cache.putIfAbsent(id, () => _DiscussData(id));

  /// Kiểm thử: dùng sẵn API Bảng tin giả (không cần mini app / Flygo ID).
  @visibleForTesting
  static void debugUse(String id, BangTinApi api, BangTinMe me) => _cache[id] = _DiscussData(id)
    ..api = api
    ..me = me;

  bool _started = false;
  Future<void> start(BuildContext context) async {
    if (_started) return;
    _started = true;
    try {
      if (api == null) {
        final s = await bangTinSession(context);
        api = s.$1;
        me = s.$2;
      }
      await load();
      _live = api!.events(discussion: id).listen((_) {
        _deb?.cancel();
        _deb = Timer(const Duration(milliseconds: 300), load);
      });
    } catch (e) {
      error = '$e';
      _started = false;
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (api == null) return;
    try {
      final j = await api!.get('/api/discussions/$id/posts?sort=${sort == 'stance' ? 'top' : sort}');
      disc = Map<String, dynamic>.from(j['discussion'] as Map);
      final list = [if (j['pinned'] is Map) Map<String, dynamic>.from(j['pinned'] as Map), for (final p in (j['posts'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
      if (sort == 'stance') list.sort((a, b) => const ['y', 'n', 'o', null].indexOf(a['stance']).compareTo(const ['y', 'n', 'o', null].indexOf(b['stance'])));
      posts = list;
      error = null;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _live?.cancel();
    _deb?.cancel();
    super.dispose();
  }
}

class DiscussPanel extends StatefulWidget {
  final PageCtx ctx;
  const DiscussPanel(this.ctx, {super.key});
  @override
  State<DiscussPanel> createState() => _DiscussPanelState();
}

class _DiscussPanelState extends State<DiscussPanel> {
  _DiscussData? _d;
  final _text = TextEditingController();
  String? _stance;
  bool _anon = false, _sending = false;

  String? get _id => widget.ctx.view['disc_id'] as String?;

  @override
  void initState() {
    super.initState();
    if (_id != null) {
      _d = _DiscussData.of(_id!)..addListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => _d?.start(context));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _d?.removeListener(_changed);
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final d = _d!, body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    if (d.disc?['stance'] == true && d.disc?['require_stance'] == true && _stance == null) {
      meetToast(context, tr('Hãy chọn lập trường'));
      return;
    }
    setState(() => _sending = true);
    await _run(context, () async {
      await d.api!.post('/api/posts', {'discussion': d.id, 'body': body, 'stance': ?_stance, 'anon': _anon});
      _text.clear();
      await d.load();
    });
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), t = s.theme;
    final d = _d;
    if (d == null) return AppEmpty(icon: Icons.cloud_off_outlined, title: tr('Chưa nối được Bảng tin'));
    if (d.disc == null) {
      return AppCard(child: d.error != null ? Text(d.error!, style: TextStyle(color: t.sub)) : const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())));
    }
    final disc = d.disc!;
    final sc = Map<String, dynamic>.from(disc['stance_counts'] as Map? ?? const {});
    final total = kStances.fold<int>(0, (a, x) => a + ((sc[x.$1] as num?)?.toInt() ?? 0));
    final closed = disc['closed'] == true;
    final list = s.compact ? d.posts.take(3).toList() : d.posts;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if ('${disc['question'] ?? ''}'.isNotEmpty) Text('${disc['question']}', style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
          if (disc['stance'] == true) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 8,
                child: total == 0
                    ? ColoredBox(color: t.surface2)
                    : Row(children: [for (final x in kStances) if (((sc[x.$1] as num?) ?? 0) > 0) Expanded(flex: (sc[x.$1] as num).toInt(), child: Container(color: x.$3))]),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 12, children: [
              for (final x in kStances)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: x.$3, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text('${x.$2} ${sc[x.$1] ?? 0}', style: TextStyle(color: t.sub, fontSize: 12.5)),
                ]),
            ]),
          ],
          const SizedBox(height: 10),
          AppSegmented<String>(
            items: [('new', tr('Mới nhất')), ('top', tr('Nhiều thích')), if (disc['stance'] == true) ('stance', tr('Theo lập trường'))],
            value: d.sort,
            onChanged: (x) {
              d.sort = x;
              d.load();
            },
          ),
        ]),
      ),
      const SizedBox(height: 10),
      if (list.isEmpty) AppEmpty(icon: Icons.forum_outlined, title: tr('Chưa có ý kiến nào'), sub: tr('Hãy là người đầu tiên nêu ý kiến.')),
      for (final p in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: _Opinion(key: ValueKey('op-${p['id']}'), post: p, data: d, pctx: widget.ctx)),
      if (!closed && widget.ctx.data.role != 'viewer')
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (disc['stance'] == true)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in kStances) AppChip(x.$2, key: ValueKey('st-${x.$1}'), color: x.$3, selected: _stance == x.$1, onTap: () => setState(() => _stance = _stance == x.$1 ? null : x.$1)),
                if (disc['allow_anon'] != false) AppChip(tr('Ẩn danh'), key: const ValueKey('st-anon'), icon: Icons.visibility_off_outlined, selected: _anon, onTap: () => setState(() => _anon = !_anon)),
              ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('discuss-text'),
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  style: TextStyle(color: t.text),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: t.surface2,
                    hintText: _anon ? tr('Viết ý kiến ẩn danh…') : tr('Viết ý kiến…'),
                    hintStyle: TextStyle(color: t.sub),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(key: const ValueKey('discuss-send'), tooltip: tr('Gửi'), onPressed: _sending ? null : _send, icon: Icon(Icons.send_rounded, color: t.accent)),
            ]),
          ]),
        ),
    ]);
  }
}

/// Một ý kiến: đầu thẻ (tên, lập trường, giờ, ⋯), nội dung, 👍 / 👎 / cảm xúc, trả lời 2 cấp mở ngay tại chỗ.
class _Opinion extends StatefulWidget {
  final Map<String, dynamic> post;
  final _DiscussData data;
  final PageCtx pctx;
  const _Opinion({super.key, required this.post, required this.data, required this.pctx});
  @override
  State<_Opinion> createState() => _OpinionState();
}

class _OpinionState extends State<_Opinion> {
  bool _open = false;
  List<Map<String, dynamic>>? _comments;
  Map<String, dynamic>? _replyTo;
  final _reply = TextEditingController();

  Map<String, dynamic> get p => widget.post;
  BangTinApi get api => widget.data.api!;

  @override
  void didUpdateWidget(_Opinion old) {
    super.didUpdateWidget(old);
    if (_open && old.post['comments'] != p['comments']) _loadComments();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final j = await api.get('/api/posts/${p['id']}/comments');
      if (mounted) setState(() => _comments = [for (final c in (j['comments'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)].where((c) => c['deleted'] != true).toList());
    } catch (_) {}
  }

  Future<void> _react(String? emoji) => _run(context, () async {
        final cur = (p['my_reactions'] as List? ?? const []).map((e) => '$e').firstOrNull;
        if (emoji == null || emoji == cur) {
          if (cur != null) await api.delete('/api/posts/${p['id']}/reactions/${Uri.encodeComponent(cur)}');
        } else {
          await api.post('/api/posts/${p['id']}/reactions', {'emoji': emoji});
        }
        await widget.data.load();
      });

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final to = _replyTo, name = '${(to?['author'] as Map?)?['name'] ?? ''}';
    await _run(context, () async {
      await api.post('/api/posts/${p['id']}/comments', {
        'body': to != null && to['parent'] != null && name.isNotEmpty && !text.startsWith('@') ? '@$name $text' : text,
        if (to != null) 'parent': to['id'],
      });
      _reply.clear();
      setState(() => _replyTo = null);
      await _loadComments();
      await widget.data.load();
    });
  }

  Future<void> _menu(Offset? at) async {
    final d = widget.data;
    final manage = d.disc?['can_manage'] == true;
    final pinned = p['discussing'] == true;
    await showAppMenu(context, at: at, items: [
      for (final k in kDiscussReactionKinds.skip(2))
        PageMenuItem(label: '${k.emoji}  ${k.label}', icon: Icons.add_reaction_outlined, onTap: () => _react(k.emoji)),
      if (manage)
        PageMenuItem(
          label: pinned ? tr('Bỏ ghim khỏi TV') : tr('Ghim lên TV (Đang bàn)'),
          icon: Icons.push_pin_outlined,
          color: const Color(0xFF7FD8CC),
          onTap: () => _run(context, () async {
            await api.patch('/api/discussions/${d.id}', {'pinned_post': pinned ? null : p['id']});
            await d.load();
          }),
        ),
      if (manage)
        PageMenuItem(
          label: d.disc?['locked'] == true ? tr('Mở lại trả lời') : tr('Khoá trả lời'),
          icon: Icons.lock_outline_rounded,
          onTap: () => _run(context, () async {
            await api.patch('/api/discussions/${d.id}', {'locked': d.disc?['locked'] != true});
            await d.load();
          }),
        ),
      if (manage && widget.pctx.page.meeting != null)
        PageMenuItem(label: tr('Ghi vào Biên bản'), icon: Icons.note_add_outlined, onTap: () => _run(context, () => widget.pctx.act('to_minutes'))),
      if (manage)
        PageMenuItem(
          label: p['hidden'] == true ? tr('Hiện lại ý kiến') : tr('Ẩn ý kiến'),
          icon: Icons.visibility_off_outlined,
          onTap: () => _run(context, () async {
            await api.patch('/api/posts/${p['id']}', {'hidden': p['hidden'] != true});
            await d.load();
          }),
        ),
      if (p['can_delete'] == true)
        PageMenuItem(
          label: tr('Xoá ý kiến'),
          icon: Icons.delete_outline_rounded,
          danger: true,
          onTap: () => _run(context, () async {
            await api.delete('/api/posts/${p['id']}');
            await d.load();
          }),
        ),
    ]);
  }

  Widget _reactBtn(String emoji, int n, bool on, StageTheme t) => InkWell(
        key: ValueKey('react-${p['id']}-$emoji'),
        borderRadius: BorderRadius.circular(99),
        onTap: () => _react(on ? null : emoji),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: on ? t.accentSoft : t.surface2, borderRadius: BorderRadius.circular(99)),
          child: Text('$emoji $n', style: TextStyle(color: on ? t.accent : t.text, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      );

  Widget _commentTile(Map<String, dynamic> c, StageTheme t, {required bool deep}) => Padding(
        padding: EdgeInsets.only(left: deep ? 22 : 0, top: 6),
        child: Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: t.line, width: 2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '${(c['author'] as Map?)?['name'] ?? ''}  ', style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
              TextSpan(text: '${c['body'] ?? ''}', style: TextStyle(color: t.text)),
            ]), style: const TextStyle(fontSize: 13.5)),
            if (widget.data.disc?['locked'] != true && widget.data.disc?['closed'] != true)
              InkWell(
                onTap: () => setState(() => _replyTo = c),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(tr('Trả lời'), style: TextStyle(color: t.sub, fontSize: 12, fontWeight: FontWeight.w600))),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).theme;
    final st = stanceOf(p['stance']);
    final author = '${(p['author'] as Map?)?['name'] ?? ''}';
    final reactions = Map<String, dynamic>.from(p['reactions'] as Map? ?? const {});
    final my = (p['my_reactions'] as List? ?? const []).map((e) => '$e').firstOrNull;
    final comments = (p['comments'] as num?)?.toInt() ?? 0;
    final latest = [for (final r in (p['latest_replies'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    final locked = widget.data.disc?['locked'] == true || widget.data.disc?['closed'] == true;
    final others = reactions.entries.where((e) => e.key != '👍' && e.key != '👎' && ((e.value as num?) ?? 0) > 0).toList();
    return GestureDetector(
      onLongPressStart: (e) => _menu(e.globalPosition),
      onSecondaryTapDown: (e) => _menu(e.globalPosition),
      child: AppCard(
        outline: p['discussing'] == true ? const Color(0xFFF5B544) : null,
        child: Opacity(
          opacity: p['hidden'] == true ? .5 : 1,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (p['discussing'] == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(tr('ĐANG BÀN'), style: const TextStyle(color: Color(0xFFF5B544), fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
            Row(children: [
              AppAvatar(author, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: author, style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
                  TextSpan(text: ' · ${_ago((p['created_at'] as num).toInt())}', style: TextStyle(color: t.sub, fontSize: 12.5)),
                ]), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (st != null) AppChip(st.$2, color: st.$3),
              IconButton(key: ValueKey('op-menu-${p['id']}'), visualDensity: VisualDensity.compact, tooltip: tr('Thêm'), onPressed: () => _menu(null), icon: Icon(Icons.more_horiz_rounded, color: t.sub)),
            ]),
            const SizedBox(height: 6),
            Text('${p['body_preview'] ?? p['excerpt'] ?? ''}', style: TextStyle(color: t.text, fontSize: 15, height: 1.4)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _reactBtn('👍', (reactions['👍'] as num?)?.toInt() ?? 0, my == '👍', t),
              _reactBtn('👎', (reactions['👎'] as num?)?.toInt() ?? 0, my == '👎', t),
              for (final e in others) _reactBtn(e.key, (e.value as num).toInt(), my == e.key, t),
              TextButton(
                key: ValueKey('op-replies-${p['id']}'),
                onPressed: () {
                  setState(() => _open = !_open);
                  if (_open) _loadComments();
                },
                child: Text(comments == 0 ? tr('Trả lời') : tr('Trả lời · {0}', [comments])),
              ),
            ]),
            if (!_open)
              for (final r in latest) _commentTile(r, t, deep: r['parent'] != null)
            else ...[
              for (final c in (_comments ?? const <Map<String, dynamic>>[]).where((c) => c['parent'] == null)) ...[
                _commentTile(c, t, deep: false),
                for (final r in _comments!.where((x) => x['parent'] == c['id'])) _commentTile(r, t, deep: true),
              ],
              if (!locked)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('reply-${p['id']}'),
                        controller: _reply,
                        style: TextStyle(color: t.text, fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: t.surface2,
                          hintText: _replyTo == null ? tr('Trả lời {0}…', [author]) : tr('Trả lời {0}…', ['${(_replyTo!['author'] as Map?)?['name'] ?? ''}']),
                          hintStyle: TextStyle(color: t.sub),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _sendReply(),
                      ),
                    ),
                    IconButton(onPressed: _sendReply, icon: Icon(Icons.send_rounded, color: t.accent, size: 20)),
                  ]),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

class DiscussControls extends StatefulWidget {
  final PageCtx ctx;
  const DiscussControls(this.ctx, {super.key});
  @override
  State<DiscussControls> createState() => _DiscussControlsState();
}

class _DiscussControlsState extends State<DiscussControls> {
  _DiscussData? _d;

  @override
  void initState() {
    super.initState();
    final id = widget.ctx.view['disc_id'] as String?;
    if (id != null) {
      _d = _DiscussData.of(id)..addListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => _d?.start(context));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _d?.removeListener(_changed);
    super.dispose();
  }

  Future<void> _patch(Map<String, dynamic> b) => _run(context, () async {
        await _d!.api!.patch('/api/discussions/${_d!.id}', b);
        await _d!.load();
      });

  @override
  Widget build(BuildContext context) {
    final disc = _d?.disc;
    if (disc == null) return const SizedBox.shrink();
    final pinned = _d!.posts.where((p) => p['discussing'] == true).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionLabel(widget.ctx.live ? tr('Đang chiếu · ghim {0} ý kiến', [pinned]) : tr('Cài đặt ngay tại đây')),
      AppToggleRow(tr('Chọn lập trường'), value: disc['stance'] == true, onChanged: (x) => _patch({'stance': x})),
      AppToggleRow(tr('Bắt buộc chọn lập trường'), value: disc['require_stance'] == true, onChanged: disc['stance'] == true ? (x) => _patch({'require_stance': x}) : null),
      AppToggleRow(tr('Cho phép ẩn danh'), value: disc['allow_anon'] != false, onChanged: (x) => _patch({'allow_anon': x})),
      AppToggleRow(tr('Khoá trả lời'), value: disc['locked'] == true, onChanged: (x) => _patch({'locked': x})),
      AppToggleRow(tr('Khoá cả thảo luận'), value: disc['closed'] == true, onChanged: (x) => _patch({'closed': x})),
      if (widget.ctx.page.meeting != null) ...[
        const SizedBox(height: 8),
        AppButton(tr('Ghi tóm tắt vào Biên bản'), icon: Icons.note_add_outlined, onPressed: () async {
          await _run(context, () => widget.ctx.act('to_minutes'));
          if (context.mounted) meetToast(context, tr('Đã ghi vào Biên bản'));
        }),
      ],
    ]);
  }
}

/// Kiểm thử: trang Thảo luận [id] dùng sẵn API Bảng tin giả.
@visibleForTesting
void debugUseDiscussion(String id, BangTinApi api, BangTinMe me) => _DiscussData.debugUse(id, api, me);
