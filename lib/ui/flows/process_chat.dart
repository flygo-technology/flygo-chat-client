import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/flows_api.dart';
import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../markdown_view.dart';
import '../reactions.dart' show showEmojiPicker;
import '../theme.dart';

/// Thảo luận của một tiến trình: một tin trong cột thảo luận (giống dòng tin của chat).
class ProcessChatMessage extends StatelessWidget {
  final AppState app;
  /// `{id, user, at, text, files: [{id, name, size, image}], reactions: {tên emoji: [người]}, pending}`.
  final Map<String, dynamic> msg;
  final String when;
  /// Bấm "Đưa vào tệp của tiến trình" trên một tệp đính kèm (mã tệp).
  final void Function(String fileId)? onAddToFiles;
  /// Bấm một cảm xúc (tên emoji): thêm / bỏ cảm xúc của mình.
  final void Function(String emoji)? onReact;
  /// Bấm giữ / nháy phải: chọn cảm xúc.
  final VoidCallback? onLongPress;
  /// Bước của tiến trình lúc gửi (nhãn xám nhỏ "· tại bước …").
  final String step;
  const ProcessChatMessage(
      {super.key, required this.app, required this.msg, required this.when, this.onAddToFiles, this.onReact, this.onLongPress, this.step = ''});

  String _name(String id) {
    if (id == app.me?.id) return tr('Bạn');
    final u = app.users[id];
    if (u == null) return id;
    return u.displayName.isNotEmpty ? u.displayName : u.username;
  }

  static String _size(num? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final user = '${msg['user'] ?? ''}';
    final mine = user == app.me?.id;
    final text = '${msg['text'] ?? ''}'.trim();
    final files = [for (final f in (msg['files'] as List? ?? const [])) if (f is Map) f];
    final reactions = msg['reactions'] is Map ? (msg['reactions'] as Map) : const {};
    final me = app.me?.id;
    // Như bong bóng chat: tin của mình nền màu chủ đạo, chữ trên nền màu; tin người khác nền xám nhạt.
    final bp = mine ? pal.onFill(pal.outBubble) : pal;
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: mine ? pal.outBubble : Color.alphaBlend(pal.text.withValues(alpha: .06), pal.inBubble),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (text.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(extensions: [bp]),
            child: MarkdownView(text: text, style: TextStyle(fontSize: 14.5, height: 1.35, color: bp.text)),
          ),
        for (final (i, f) in files.indexed) ...[
          if (text.isNotEmpty || i > 0) const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: pal.surface.withValues(alpha: .7), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: pal.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
                child: Icon(f['image'] == true ? Icons.image_outlined : Icons.description_outlined, color: pal.accentText),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                  Text(_size(f['size'] as num?), style: TextStyle(fontSize: 12, color: pal.sub)),
                ]),
              ),
            ]),
          ),
        ],
      ]),
    );
    return Padding(
      key: ValueKey('chat-${msg['id']}'),
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: GestureDetector(
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: Opacity(
          opacity: msg['pending'] == true ? .6 : 1,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(userId: user, name: _name(user), size: 30, status: false),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: _name(user), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: pal.text)),
                  TextSpan(text: '  $when', style: TextStyle(fontSize: 11.5, color: pal.sub)),
                  if (step.isNotEmpty) TextSpan(text: '  · ${tr('tại bước {0}', [step])}', style: TextStyle(fontSize: 11, color: pal.sub.withValues(alpha: .75))),
                ])),
                const SizedBox(height: 3),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: bubble),
                if (reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 4, runSpacing: 4, children: [
                      for (final e in reactions.entries)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: onReact == null ? null : () => onReact!('${e.key}'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: (e.value as List?)?.contains(me) == true ? pal.accent.withValues(alpha: .16) : pal.surface2,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text('${emojiOf('${e.key}')} ${(e.value as List?)?.length ?? 0}', style: TextStyle(fontSize: 13, color: pal.text)),
                          ),
                        ),
                    ]),
                  ),
                for (final f in files)
                  TextButton.icon(
                    key: ValueKey('add-to-files-${f['id']}'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
                    onPressed: onAddToFiles == null ? null : () => onAddToFiles!('${f['id']}'),
                    icon: const Icon(Icons.drive_folder_upload_outlined, size: 17),
                    label: Text(files.length > 1 ? tr('Đưa "{0}" vào tệp của tiến trình', ['${f['name']}']) : tr('Đưa vào tệp của tiến trình'),
                        style: const TextStyle(fontSize: 12.5)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Khung soạn thảo luận (giống khung soạn của chat): đính kèm, ô nhập, @ nhắc tên, biểu tượng cảm xúc, gửi.
class ProcessChatComposer extends StatefulWidget {
  /// Gửi chữ (markdown, @tên).
  final Future<void> Function(String text)? onSend;
  /// Chọn và gửi tệp (kèm chữ đang gõ).
  final Future<void> Function(String text)? onAttach;
  /// Người để nhắc tên: (username, tên hiển thị).
  final List<(String, String)> people;
  const ProcessChatComposer({super.key, this.onSend, this.onAttach, this.people = const []});
  @override
  State<ProcessChatComposer> createState() => _ProcessChatComposerState();
}

class _ProcessChatComposerState extends State<ProcessChatComposer> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insert(String t) {
    final sel = _ctl.selection;
    final at = sel.isValid ? sel.start : _ctl.text.length;
    final end = sel.isValid ? sel.end : _ctl.text.length;
    _ctl.value = TextEditingValue(text: _ctl.text.replaceRange(at, end, t), selection: TextSelection.collapsed(offset: at + t.length));
    _focus.requestFocus();
    setState(() {});
  }

  Future<void> _mention() async {
    if (widget.people.isEmpty) return _insert('@');
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final (u, n) in widget.people) ListTile(leading: const Icon(Icons.alternate_email_rounded), title: Text(n), subtitle: Text('@$u'), onTap: () => Navigator.pop(c, u)),
        ]),
      ),
    );
    if (v != null) _insert('@$v ');
  }

  Future<void> _emoji() async {
    final name = await showEmojiPicker(context);
    if (name != null) _insert(emojiOf(name));
  }

  Future<void> _send() async {
    final t = _ctl.text.trim();
    if (t.isEmpty || widget.onSend == null || _busy) return;
    setState(() => _busy = true);
    _ctl.clear();
    try {
      await widget.onSend!(t);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget icon(IconData i, String tip, VoidCallback? on) =>
        IconButton(tooltip: tip, visualDensity: VisualDensity.compact, onPressed: on, icon: Icon(i, color: pal.sub));
    return Material(
      key: const ValueKey('process-composer'),
      color: pal.bg,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.divider))),
        child: SafeArea(
          top: false,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            icon(Icons.add_circle_outline_rounded, tr('Đính kèm'), widget.onAttach == null ? null : () {
              final t = _ctl.text.trim();
              _ctl.clear();
              widget.onAttach!(t);
            }),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 14, right: 4),
                decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(22)),
                child: Row(children: [
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _send},
                      child: TextField(
                        controller: _ctl,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 5,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: tr('Thảo luận trong tiến trình…'),
                          hintStyle: TextStyle(color: pal.sub, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  icon(Icons.alternate_email_rounded, tr('Nhắc tên'), _mention),
                  icon(Icons.emoji_emotions_outlined, tr('Biểu tượng cảm xúc'), _emoji),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: _ctl.text.trim().isEmpty ? pal.accent.withValues(alpha: .5) : pal.accent, shape: BoxShape.circle),
              child: IconButton(tooltip: tr('Gửi'), onPressed: _send, icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Số tin thảo luận chưa đọc trên dòng tiến trình (bong bóng xanh nhỏ).
class ProcessUnreadBadge extends StatelessWidget {
  final int count;
  const ProcessUnreadBadge({super.key, required this.count});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
      decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.chat_bubble_rounded, size: 11, color: Colors.white),
        const SizedBox(width: 3),
        Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Cột thảo luận của một tiến trình: tiêu đề "Thảo luận" (ảnh những người tham gia + số người, "Chỉ người liên quan
/// thấy"), các tin cũ trước mới sau (mở ra thấy tin mới nhất), khung soạn ghim ở dưới. Dữ liệu là kênh Mattermost
/// riêng tư của tiến trình (POST /flows/processes/{id}/discussion), đọc / gửi / cảm xúc / đánh dấu đã đọc bằng phiên
/// chat của app như trang chat.
class ProcessDiscussion extends StatefulWidget {
  final AppState app;
  final String processId;
  final String Function(int ms) when;
  /// Bước của tiến trình tại một thời điểm (nhãn "tại bước …").
  final String Function(int ms) stepOf;
  /// Đã đưa một tệp vào tệp của tiến trình (trang chi tiết tải lại).
  final VoidCallback? onFilesChanged;
  /// Số tin (cho nhãn tab "Thảo luận (n)").
  final void Function(int count)? onCount;
  /// Người gọi không liên quan (403): trang chi tiết bỏ cột thảo luận.
  final VoidCallback? onForbidden;
  /// Cột đang hiện (một cột: tab Thảo luận đang chọn): chỉ khi đó mở kênh như trang chat (tải tin, đánh dấu đã đọc).
  final bool active;
  const ProcessDiscussion(
      {super.key,
      required this.app,
      required this.processId,
      required this.when,
      required this.stepOf,
      this.onFilesChanged,
      this.onCount,
      this.onForbidden,
      this.active = true});
  @override
  State<ProcessDiscussion> createState() => _ProcessDiscussionState();
}

class _ProcessDiscussionState extends State<ProcessDiscussion> {
  late final api = FlowsApi(widget.app.token);
  String? _ch;
  List<Map<String, dynamic>> _members = const [];
  String? _err;
  bool _forbidden = false;
  bool _opened = false;
  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_changed);
    _open();
  }

  @override
  void dispose() {
    widget.app.removeListener(_changed);
    final ch = _ch;
    if (ch != null && _opened) widget.app.closeChannel(ch);
    super.dispose();
  }

  /// Mở như trang chat (tải tin, nhận tin mới qua websocket, đánh dấu đã đọc) khi cột đang hiện.
  void _activate() {
    final ch = _ch;
    if (ch == null || _opened || !widget.active || !widget.app.started) return;
    _opened = true;
    widget.app.openChannel(ch);
  }

  @override
  void didUpdateWidget(ProcessDiscussion old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _activate();
      final ch = _ch;
      if (ch != null && _opened) widget.app.markViewed(ch);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    try {
      final d = await api.processDiscussion(widget.processId);
      final ch = '${d['channel_id'] ?? ''}';
      if (ch.isEmpty) throw Exception(tr('Máy chủ chưa tạo được thảo luận'));
      await widget.app.ensureChannel(ch);
      if (!mounted) return;
      setState(() {
        _ch = ch;
        _members = [for (final m in (d['members'] as List? ?? const [])) if (m is Map) m.cast<String, dynamic>()];
        _err = null;
      });
      for (final m in _members) {
        final id = '${m['id']}';
        if (id != widget.app.me?.id && widget.app.users[id] == null && widget.app.started) widget.app.refreshUser(id).catchError((_) {});
      }
      _activate();
    } on FlowsException catch (e) {
      if (!mounted) return;
      setState(() => e.status == 403 ? _forbidden = true : _err = e.message);
      if (e.status == 403) widget.onForbidden?.call();
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Map<String, dynamic> _msgOf(MmPost p) => {
        'id': p.id,
        'user': p.userId,
        'at': p.createAt,
        'text': p.message,
        'pending': p.sendState != SendState.sent,
        'files': [for (final f in p.files) {'id': f.id, 'name': f.name, 'size': f.size, 'image': f.isImage}],
        'reactions': p.reactions,
      };

  Future<void> _addToFiles(MmPost p, String fileId) async {
    final m = ScaffoldMessenger.of(context);
    try {
      final r = await api.processFileFromPost(widget.processId, p.id, fileId);
      m.showSnackBar(toast(Text(r['added'] == false ? tr('Tệp đã có trong tệp của tiến trình') : tr('Đã đưa vào tệp của tiến trình'))));
      widget.onFilesChanged?.call();
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
    }
  }

  Future<void> _react(MmPost p) async {
    final name = await showEmojiPicker(context);
    if (name != null) await widget.app.toggleReaction(p, name);
  }

  Future<void> _attach(String text) async {
    final ch = _ch;
    if (ch == null) return;
    final files = await pickFilesOrReport(context);
    final items = <(String, String, String, double)>[
      for (final f in files)
        if (f.path != null) (f.path!, f.name, _mime(f.name), 1.0),
    ];
    if (items.isEmpty) return;
    await widget.app.sendMedia(ch, items, text: text);
  }

  static String _mime(String name) => switch (name.split('.').last.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      };

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final ch = _ch;
    // Tin gốc của kênh, cũ trước mới sau (postsOf: mới nhất trước); bỏ tin hệ thống (vào / rời kênh).
    final posts = ch == null ? const <MmPost>[] : [for (final p in widget.app.postsOf(ch).reversed) if (!p.isSystem && p.rootId.isEmpty) p];
    if (posts.length != _lastCount && widget.onCount != null) {
      _lastCount = posts.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCount?.call(posts.length));
    }
    final people = <String>[for (final m in _members) '${m['id']}'];
    String name(String id) {
      final u = widget.app.users[id];
      if (u != null) return u.displayName.isNotEmpty ? u.displayName : u.username;
      return '${_members.where((m) => m['id'] == id).firstOrNull?['name'] ?? id}';
    }

    final Widget body;
    if (_forbidden) {
      body = _note(pal, Icons.lock_outline_rounded, tr('Chỉ người liên quan tới tiến trình mới xem và nhắn trong thảo luận.'));
    } else if (_err != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Không mở được thảo luận: {0}', [_err]), textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _open, child: Text(tr('Thử lại'))),
          ]),
        ),
      );
    } else if (ch == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (posts.isEmpty) {
      body = _note(pal, Icons.forum_outlined, tr('Chưa có thảo luận. Nhắn để trao đổi với những người liên quan.'));
    } else {
      // Đảo chiều: mở ra là thấy tin mới nhất ở dưới cùng.
      body = ListView(
        key: const ValueKey('discussion-list'),
        reverse: true,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        children: [
          for (final p in posts.reversed)
            ProcessChatMessage(
              app: widget.app,
              msg: _msgOf(p),
              when: widget.when(p.createAt),
              step: widget.stepOf(p.createAt),
              onAddToFiles: (f) => _addToFiles(p, f),
              onReact: (e) => widget.app.toggleReaction(p, e),
              onLongPress: () => _react(p),
            ),
        ],
      );
    }
    return Material(
      key: const ValueKey('process-discussion'),
      color: pal.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Thảo luận'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.text)),
                Row(children: [
                  Icon(Icons.lock_outline_rounded, size: 12, color: pal.sub),
                  const SizedBox(width: 3),
                  Flexible(child: Text(tr('Chỉ người liên quan thấy'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub))),
                ]),
              ]),
            ),
            if (people.isNotEmpty) ...[
              Tooltip(
                message: people.map(name).join(', '),
                child: SizedBox(
                  width: 18.0 * (people.take(4).length - 1) + 26,
                  height: 26,
                  child: Stack(children: [
                    for (final (i, u) in people.take(4).indexed)
                      Positioned(
                        left: 18.0 * i,
                        child: Container(
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.bg, width: 2)),
                          child: Avatar(userId: u, name: name(u), size: 22, status: false),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              Text(tr('{0} người', [people.length]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ],
          ]),
        ),
        Expanded(child: body),
        if (!_forbidden)
          ProcessChatComposer(
            people: [
              for (final id in people)
                if (id != widget.app.me?.id && widget.app.users[id] != null) (widget.app.users[id]!.username, name(id)),
            ],
            onSend: ch == null ? null : (t) async => widget.app.send(ch, t),
            onAttach: ch == null ? null : _attach,
          ),
      ]),
    );
  }

  Widget _note(Pal pal, IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 34, color: pal.sub.withValues(alpha: .6)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
          ]),
        ),
      );
}
