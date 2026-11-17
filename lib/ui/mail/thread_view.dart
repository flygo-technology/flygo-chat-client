// Thư: xem một cuộc hội thoại. Thư cũ thu gọn (bấm để mở), thư cuối mở sẵn; tệp đính kèm dạng thẻ (mở / chia sẻ);
// Trả lời / Trả lời tất cả / Chuyển tiếp; thêm vào Lịch, gửi vào chat.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../open_file.dart' show openLocalFile;
import 'attachments.dart';
import 'compose.dart';
import 'html_view.dart';
import 'image_trust.dart';
import 'skeleton.dart';
import 'model.dart';
import 'photos.dart';
import 'store.dart';
import 'widgets.dart';

/// Móc nối sang ứng dụng khác của Flygo (gắn ở mail_page.dart; test có thể thay).
class MailHooks {
  /// Tạo sự kiện Lịch từ thư (mở trình soạn sự kiện có sẵn dữ liệu, người dùng bấm Lưu).
  static Future<void> Function(BuildContext context, {required String title, required List<String> guestEmails, required String description})? createEvent;

  /// Gửi tóm tắt thư vào một cuộc trò chuyện.
  static Future<void> Function(BuildContext context, String text)? sendToChat;

  /// Lưu tệp vào Drive của người dùng (mail_page gắn khi có app Drive). Null = ẩn nút.
  static SaveToDrive? saveToDrive;

  /// Mở / chia sẻ tệp đã tải về máy.
  static Future<void> Function(BuildContext context, String path, MailAttachment a) openFile = (context, path, a) async {
    await openLocalFile(path, mime: a.type.isEmpty ? null : a.type, title: a.name);
  };
}

/// Đường dẫn trong app để mở lại thư (dùng trong Lịch / chat).
String mailLink(String threadId) => 'vn.flygo.mail:/t/$threadId';

class ThreadView extends StatefulWidget {
  const ThreadView({super.key, required this.store, required this.threadId, required this.onBack, required this.onCompose, this.onStep, this.wide = true, this.inlineReply});
  final MailStore store;
  final String threadId;
  final VoidCallback onBack;

  /// Mở khung soạn (điện thoại: trang mới; máy tính: trả lời ngay dưới thư nếu [inlineReply] null).
  final void Function(ComposeArgs args) onCompose;

  /// Sang thư mới hơn (-1) / cũ hơn (+1) trong danh sách.
  final void Function(int delta)? onStep;
  final bool wide;

  /// Máy tính: khung trả lời ngay dưới thư.
  final Widget Function(ComposeArgs args, VoidCallback done)? inlineReply;

  @override
  State<ThreadView> createState() => ThreadViewState();
}

class ThreadViewState extends State<ThreadView> {
  MailThread? _t;
  Object? _err;
  final _open = <String>{};
  ComposeArgs? _inline;
  final _scroll = ScrollController();
  // AI đọc thư: tóm tắt + soạn nháp trả lời (không bao giờ tự gửi).
  bool _aiOpen = false, _aiBusy = false, _aiReplyBusy = false;
  MailAiResult? _ai;
  Object? _aiErr;
  String _aiTone = 'polite';
  final _aiAsk = TextEditingController();

  MailStore get store => widget.store;
  MailThread? get thread => _t;

  StreamSubscription<Set<String>>? _remote;

  @override
  void initState() {
    super.initState();
    _load();
    MailImageTrust.load().then((_) { if (mounted) setState(() {}); });
    // Thư mới trong cuộc hội thoại / đổi trạng thái từ máy khác: tải lại tại chỗ.
    _remote = store.remoteThreads.listen((ids) {
      if (ids.contains(widget.threadId) && mounted) _load();
    });
  }

  @override
  void didUpdateWidget(ThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      _t = null;
      _inline = null;
      _open.clear();
      _aiOpen = false;
      _ai = null;
      _aiErr = null;
      _load();
    }
  }

  @override
  void dispose() {
    _remote?.cancel();
    _scroll.dispose();
    _aiAsk.dispose();
    super.dispose();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final t = await store.openThread(widget.threadId);
      if (!mounted) return;
      setState(() {
        _t = t;
        _err = null;
        _open.add(t.messages.last.id);
      });
    } catch (e) {
      if (mounted) setState(() => _err = e);
    }
  }

  void _snack(String m, {Future<void> Function()? undo}) {
    final ms = ScaffoldMessenger.maybeOf(context);
    ms?.hideCurrentSnackBar();
    ms?.showSnackBar(
      SnackBar(
        content: Text(m),
        duration: Duration(seconds: undo == null ? 4 : 8),
        action: undo == null ? null : SnackBarAction(label: 'Hoàn tác', onPressed: () => undo()),
      ),
    );
  }

  Future<void> act(MailAction a) async {
    final t = _t;
    if (t == null) return;
    if (a == MailAction.forever && !await _confirmForever()) return;
    try {
      final undo = await store.act(a, [t.summary.id], extra: [t.summary]);
      final msg = MailStore.messageFor(a, 1);
      if (msg != null) _snack(msg, undo: undo);
      if (MailStore.changeFor(a).leavesBox || a == MailAction.forever || a == MailAction.unread) {
        widget.onBack();
      } else {
        setState(() {});
      }
    } catch (e) {
      _snack('$e');
    }
  }

  Future<bool> _confirmForever() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Xoá vĩnh viễn?'),
          content: const Text('Cuộc hội thoại này sẽ bị xoá vĩnh viễn và không thể khôi phục.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá vĩnh viễn')),
          ],
        ),
      ) ??
      false;

  /// Bật khung AI và cho AI đọc cuộc hội thoại (lần đầu: tóm tắt + bản nháp).
  Future<void> openAi() async {
    setState(() => _aiOpen = true);
    if (_ai == null && !_aiBusy) await _runAi();
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  /// "AI soạn trả lời": AI viết bản nháp rồi mở ô trả lời với nội dung đó (không tự gửi).
  Future<void> aiReply() async {
    final t = _t;
    if (t == null || _aiReplyBusy) return;
    setState(() => _aiReplyBusy = true);
    try {
      final r = await store.api.ai(t.summary.id, task: 'draft', tone: _aiTone);
      if (!mounted) return;
      if (r.draft.trim().isEmpty) {
        _snack('AI chưa soạn được thư trả lời, thử lại sau');
      } else {
        reply('all', null, r.draft);
      }
    } catch (e) {
      if (mounted) _snack('AI lỗi: $e');
    }
    if (mounted) setState(() => _aiReplyBusy = false);
  }

  Future<void> _runAi() async {
    final t = _t;
    if (t == null) return;
    setState(() {
      _aiBusy = true;
      _aiErr = null;
    });
    try {
      final r = await store.api.ai(t.summary.id, task: store.readOnly ? 'summary' : 'draft', instruction: _aiAsk.text.trim(), tone: _aiTone);
      if (mounted) setState(() => _ai = r);
    } catch (e) {
      if (mounted) setState(() => _aiErr = e);
    }
    if (mounted) setState(() => _aiBusy = false);
  }

  void reply(String kind, [MailMessage? m, String body = '']) {
    final t = _t;
    if (t == null) return;
    var args = replyArgs(kind, t, m ?? t.messages.last, store.me?.person.email ?? '');
    if (body.isNotEmpty) {
      args = args.withBody(body);
    }
    if (widget.inlineReply != null && widget.wide) {
      setState(() => _inline = args);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });
    } else {
      widget.onCompose(args);
    }
  }

  Future<void> _labels(BuildContext anchor) async {
    final t = _t;
    if (t == null) return;
    await showLabelMenu(
      anchor,
      store,
      [t.summary.id],
      extra: [t.summary],
      onDone: (m, undo) {
        _snack(m, undo: undo);
        setState(() {});
      },
    );
  }

  late final _files = AttachmentFiles(store.api);
  final _imagesShown = <String>{};

  bool _imagesOn(MailMessage m) => _imagesShown.contains(m.id) || MailImageTrust.senders.contains(m.from.email.toLowerCase());

  /// Ảnh từ mạng đang ẩn: một dòng thay cho từng ô "Ảnh"; cho hiện thư này hoặc luôn hiện từ người gửi.
  Widget _imagesBar(MailMessage m, MailColors mc) => Container(
        key: ValueKey('mail-images-${m.id}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(color: mc.surface2, borderRadius: BorderRadius.circular(10)),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 2, children: [
          Icon(Icons.hide_image_outlined, size: 18, color: mc.muted),
          Padding(padding: const EdgeInsets.only(left: 4, right: 6), child: Text('Hình ảnh trong thư đang ẩn', style: TextStyle(fontSize: 13, color: mc.muted))),
          TextButton(key: const ValueKey('mail-images-show'), onPressed: () => setState(() => _imagesShown.add(m.id)), child: const Text('Hiển thị hình ảnh')),
          TextButton(
            onPressed: () async {
              await MailImageTrust.trust(m.from.email);
              if (mounted) setState(() {});
            },
            child: Text('Luôn hiện từ ${m.from.email}', overflow: TextOverflow.ellipsis),
          ),
        ]),
      );

  /// Ảnh dán trong thư: tải một lần, dùng chung cho thân thư và trình xem ảnh.
  final _inlineImgs = <String, Future<Uint8List?>>{};
  Future<Uint8List?> _inlineImage(String path) => _inlineImgs.putIfAbsent(path, () => store.api.inlineImage(path));

  MailPhotos _photos(MailMessage m) =>
      MailPhotos.of(m, mailBodyImages(m.html, loadImages: _imagesOn(m)), _files, inlineImage: _inlineImage, saveToDrive: MailHooks.saveToDrive);

  /// Bấm ảnh trong thân thư: trình xem ảnh của thư (mọi ảnh của thư xếp dọc) tại ảnh đó.
  void _viewImage(MailMessage m, String src) {
    final p = _photos(m);
    openMailPhotos(context, p, p.indexOfSrc(src));
  }

  /// Ảnh đính kèm: trình xem ảnh của thư; PDF / tệp khác: trình xem tệp (vuốt giữa các tệp không phải ảnh).
  void _view(MailMessage m, MailAttachment a) {
    if (isImageAttachment(a)) {
      final p = _photos(m);
      final i = p.indexOfAttachment(a);
      // Ảnh đính kèm cũng dán trong thư: mở tại ảnh trong thư.
      openMailPhotos(context, p, i >= 0 ? i : p.photos.indexWhere((x) => x.src?.split('?').first == a.url.split('?').first));
      return;
    }
    final items = m.attachments.where((x) => !isImageAttachment(x)).toList();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AttachmentViewer(items: items, index: items.indexOf(a), files: _files, onOpenExternal: _openAttachment, saveToDrive: MailHooks.saveToDrive),
    ));
  }

  Future<void> _download(MailAttachment a) async {
    try {
      final p = await downloadAttachment(context, _files, a);
      if (p != null) _snack('Đã lưu vào Tải về: ${p.split(Platform.pathSeparator).last}');
    } catch (e) {
      _snack('Không tải được "${a.name}": $e');
    }
  }

  Future<void> _saveToDrive(List<MailAttachment> list) async {
    final save = MailHooks.saveToDrive;
    if (save == null) return;
    try {
      _snack(list.length > 1 ? 'Đang chuẩn bị ${list.length} tệp…' : 'Đang chuẩn bị "${list.first.name}"…');
      final files = [for (final a in list) ((await _files.file(a)).path, a.name)];
      if (mounted) await save(context, files);
    } catch (e) {
      _snack('Không lưu được vào Drive: $e');
    }
  }

  Future<void> _openAttachment(MailAttachment a) async {
    final ms = ScaffoldMessenger.maybeOf(context);
    ms?.showSnackBar(SnackBar(content: Text('Đang mở "${a.name}"…'), duration: const Duration(seconds: 2)));
    try {
      final f = await store.api.download(a);
      if (mounted) await MailHooks.openFile(context, f.path, a);
    } catch (e) {
      _snack('Không mở được tệp: $e');
    }
  }

  Future<void> _toCalendar() async {
    final t = _t;
    if (t == null) return;
    final me = store.me?.person.email;
    final guests = {
      for (final m in t.messages) ...[m.from, ...m.to, ...m.cc],
    }.map((p) => p.email).where((e) => e != me).toList();
    final text = htmlToText(t.messages.last.html);
    final desc = '${text.length > 600 ? '${text.substring(0, 600)}…' : text}\n\nMở thư: ${mailLink(t.summary.id)}';
    final hook = MailHooks.createEvent;
    if (hook == null) {
      _snack('Lịch chưa có trên bản này');
      return;
    }
    await hook(context, title: t.summary.subject, guestEmails: guests, description: desc);
  }

  Future<void> _toChat() async {
    final t = _t;
    if (t == null) return;
    final m = t.messages.last;
    final text = '✉️ ${t.summary.subject}\nTừ: ${m.from.display} <${m.from.email}>\n\n${htmlToText(m.html)}';
    final hook = MailHooks.sendToChat;
    if (hook == null) {
      _snack('Chưa gửi vào chat được trên bản này');
      return;
    }
    await hook(context, text.length > 3000 ? '${text.substring(0, 3000)}…' : text);
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final t = _t;
    final idx = store.items.indexWhere((x) => x.id == widget.threadId);
    final s = t?.summary;
    final tr = s?.box == 'trash', sp = s?.box == 'spam';
    final bar = SizedBox(
      height: widget.wide ? 48 : 56,
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(tooltip: 'Quay lại (u)', icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
          if (store.readOnly) ...[
            IconButton(tooltip: 'Thêm vào Lịch', icon: const Icon(Icons.event_outlined), onPressed: _toCalendar),
            IconButton(tooltip: 'Gửi vào chat', icon: const Icon(Icons.forward_to_inbox_outlined), onPressed: _toChat),
          ] else ...[
            if (tr) ...[
              IconButton(tooltip: 'Chuyển đến Hộp thư đến', icon: const Icon(Icons.move_to_inbox_outlined), onPressed: () => act(MailAction.restore)),
              IconButton(tooltip: 'Xoá vĩnh viễn', icon: const Icon(Icons.delete_forever_outlined), onPressed: () => act(MailAction.forever)),
            ] else if (sp)
              TextButton(onPressed: () => act(MailAction.notSpam), child: const Text('Không phải thư rác'))
            else ...[
              if (s?.box == 'inbox')
                IconButton(tooltip: 'Lưu trữ (e)', icon: const Icon(Icons.archive_outlined), onPressed: () => act(MailAction.archive))
              else
                IconButton(tooltip: 'Chuyển đến Hộp thư đến', icon: const Icon(Icons.move_to_inbox_outlined), onPressed: () => act(MailAction.restore)),
              IconButton(tooltip: 'Báo cáo thư rác', icon: const Icon(Icons.report_gmailerrorred_outlined), onPressed: () => act(MailAction.spam)),
              IconButton(tooltip: 'Xoá (#)', icon: const Icon(Icons.delete_outline), onPressed: () => act(MailAction.trash)),
            ],
            _sep(mc),
            IconButton(tooltip: 'Đánh dấu là chưa đọc', icon: const Icon(Icons.mark_email_unread_outlined), onPressed: () => act(MailAction.unread)),
            if (widget.wide) ...[
              Builder(
                builder: (b) => IconButton(tooltip: 'Nhãn', icon: const Icon(Icons.label_outline), onPressed: () => _labels(b)),
              ),
              IconButton(tooltip: 'Thêm vào Lịch', icon: const Icon(Icons.event_outlined), onPressed: _toCalendar),
              IconButton(tooltip: 'Gửi vào chat', icon: const Icon(Icons.forward_to_inbox_outlined), onPressed: _toChat),
            ],
            Builder(
              builder: (b) => IconButton(tooltip: 'Thao tác khác', icon: const Icon(Icons.more_vert), onPressed: () => _more(b)),
            ),
          ],
          // AI ở cuối dãy nút công cụ
          _aiButton(mc),
          const Spacer(),
          if (idx >= 0 && widget.wide) Text('${(store.page - 1) * store.size + idx + 1} trong tổng số ${store.total}', style: TextStyle(fontSize: 12, color: mc.muted)),
          if (idx >= 0 && widget.onStep != null) ...[
            IconButton(tooltip: 'Mới hơn (k)', icon: const Icon(Icons.chevron_left), onPressed: idx > 0 ? () => widget.onStep!(-1) : null),
            IconButton(tooltip: 'Cũ hơn (j)', icon: const Icon(Icons.chevron_right), onPressed: idx < store.items.length - 1 ? () => widget.onStep!(1) : null),
          ],
          const SizedBox(width: 6),
        ],
      ),
    );
    Widget body;
    if (_err != null) {
      body = Center(
        child: Text('$_err', style: TextStyle(color: mc.muted)),
      );
    } else if (t == null) {
      body = ThreadSkeleton(wide: widget.wide);
    } else {
      final pad = widget.wide ? 72.0 : 16.0;
      body = ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 16, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  t.summary.subject,
                  style: TextStyle(fontSize: widget.wide ? 22 : 20, color: mc.text, height: 1.3),
                ),
                if (kMailBoxes.contains(t.summary.box) && t.summary.box != 'all')
                  LabelChip(MailStore.boxName(t.summary.box), mc.muted, onRemove: store.readOnly ? null : () => act(t.summary.box == 'inbox' ? MailAction.archive : MailAction.restore)),
                for (final id in t.summary.labels)
                  if (store.labelById(id) case final l?)
                    LabelChip(
                      l.name,
                      Color(l.color),
                      onRemove: store.readOnly
                          ? null
                          : () async {
                              final undo = await store.apply([t.summary.id], MailChange(removeLabels: [id]), extra: [t.summary]);
                              _snack('Đã gỡ nhãn "${l.name}"', undo: undo);
                              setState(() {});
                            },
                    ),
              ],
            ),
          ),
          if (_aiOpen) Padding(padding: EdgeInsets.fromLTRB(pad, 4, 16, 12), child: _aiPanel(mc)),
          for (var i = 0; i < t.messages.length; i++) _message(t, t.messages[i], i, mc),
          if (store.readOnly)
            const SizedBox.shrink()
          else if (_inline != null && widget.inlineReply != null)
            Padding(
              padding: EdgeInsets.fromLTRB(widget.wide ? 72 : 0, 8, widget.wide ? 24 : 0, 0),
              child: widget.inlineReply!(_inline!, () {
                setState(() => _inline = null);
                _load();
              }),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 16, 16, 0),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _replyBtn(Icons.reply, 'Trả lời', () => reply('all')),
                  _replyBtn(Icons.forward, 'Chuyển tiếp', () => reply('fwd')),
                  if (!store.readOnly)
                    OutlinedButton.icon(
                      key: const ValueKey('mail-ai-reply'),
                      onPressed: _aiReplyBusy ? null : aiReply,
                      icon: _aiReplyBusy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_aiReplyBusy ? 'AI đang soạn…' : 'AI soạn trả lời'),
                      style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                    ),
                ],
              ),
            ),
        ],
      );
    }
    return Column(
      children: [
        bar,
        Expanded(child: body),
      ],
    );
  }

  void _more(BuildContext b) {
    final t = _t;
    if (t == null) return;
    final s = t.summary;
    showAnchoredMenu(b, [
      if (!widget.wide) ...[
        MenuEntry('Nhãn', Icons.label_outline, () => _labels(b)),
        MenuEntry('Thêm vào Lịch', Icons.event_outlined, _toCalendar),
        MenuEntry('Gửi vào chat', Icons.forward_to_inbox_outlined, _toChat),
      ],
      MenuEntry(s.important ? 'Đánh dấu là không quan trọng' : 'Đánh dấu là quan trọng', Icons.label_important_outline, () => act(s.important ? MailAction.unimportant : MailAction.important)),
      MenuEntry(s.starred ? 'Bỏ gắn dấu sao' : 'Thêm dấu sao', Icons.star_outline, () => act(s.starred ? MailAction.unstar : MailAction.star)),
      MenuEntry('Trả lời', Icons.reply, () => reply('all')),
      MenuEntry('Chuyển tiếp', Icons.forward, () => reply('fwd')),
    ]);
  }

  Widget _aiButton(MailColors mc) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Tooltip(
          message: 'AI đọc thư và soạn nháp trả lời',
          child: Material(
            color: _aiOpen ? mc.accentSoft : Colors.transparent,
            shape: StadiumBorder(side: BorderSide(color: _aiOpen ? Colors.transparent : mc.line)),
            child: InkWell(
              key: const ValueKey('mail-ai'),
              customBorder: const StadiumBorder(),
              onTap: _aiOpen ? () => setState(() => _aiOpen = false) : openAi,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 18, color: mc.accentText),
                  const SizedBox(width: 6),
                  Text('AI', style: TextStyle(fontSize: 13.5, color: mc.accentText, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _aiPanel(MailColors mc) {
    final r = _ai;
    final grad = mc.dark ? const [Color(0xFF1F2A44), Color(0xFF2A2140)] : const [Color(0xFFEFF4FF), Color(0xFFF6EEFF)];
    Widget tone(String v, String l) => ChoiceChip(
          label: Text(l),
          selected: _aiTone == v,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: _aiBusy ? null : (_) => setState(() => _aiTone = v),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(gradient: LinearGradient(colors: grad), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.auto_awesome, size: 18, color: mc.accentText),
          const SizedBox(width: 8),
          Expanded(child: Text('AI đọc thư', style: TextStyle(fontSize: 14.5, color: mc.text, fontWeight: FontWeight.w600))),
          if (_aiBusy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          IconButton(tooltip: 'Đóng AI', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _aiOpen = false)),
        ]),
        if (_aiErr != null) Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: Text('$_aiErr', style: TextStyle(color: mc.danger, fontSize: 13))),
        if (r == null && _aiBusy) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Đang đọc cuộc hội thoại…', style: TextStyle(color: mc.muted, fontSize: 13))),
        if (r != null) ...[
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.only(right: 8), child: Text(r.summary, style: TextStyle(fontSize: 13.5, color: mc.text, height: 1.45))),
          if (r.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final a in r.actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, right: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.check_box_outline_blank, size: 15, color: mc.muted)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(a, style: TextStyle(fontSize: 13, color: mc.text))),
                ]),
              ),
          ],
          if (!store.readOnly && r.draft.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Bản nháp trả lời', style: TextStyle(fontSize: 12.5, color: mc.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: mc.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: mc.line)),
              child: SelectableText(r.draft, style: TextStyle(fontSize: 13.5, color: mc.text, height: 1.45)),
            ),
          ],
        ],
        if (!store.readOnly) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [tone('polite', 'Lịch sự'), tone('casual', 'Thân mật'), tone('short', 'Ngắn gọn')]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              controller: _aiAsk,
              enabled: !_aiBusy,
              onSubmitted: (_) => _runAi(),
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Muốn trả lời thế nào? (vd: đồng ý, hẹn gửi báo giá thứ Hai)',
                isDense: true,
                filled: true,
                fillColor: mc.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: mc.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: mc.line)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: r == null || r.draft.isEmpty || _aiBusy ? null : () => reply('all', null, r.draft),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('Dùng bản nháp'),
            ),
            OutlinedButton.icon(onPressed: _aiBusy ? null : _runAi, icon: const Icon(Icons.refresh, size: 18), label: Text(r == null ? 'Soạn' : 'Soạn lại')),
          ]),
          const SizedBox(height: 6),
          Text('AI chỉ soạn nháp, bạn xem và sửa trước khi gửi.', style: TextStyle(fontSize: 11.5, color: mc.faint)),
        ],
      ]),
    );
  }

  Widget _sep(MailColors mc) => Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 6), color: mc.line);

  Widget _replyBtn(IconData i, String t, VoidCallback f) => OutlinedButton.icon(
    onPressed: f,
    icon: Icon(i, size: 18),
    label: Text(t),
    style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
  );

  Widget _message(MailThread t, MailMessage m, int i, MailColors mc) {
    final open = _open.contains(m.id) || t.messages.length == 1;
    final mine = m.from.email == store.me?.person.email;
    final from = mine ? (store.me?.person ?? m.from) : m.from;
    final toTxt = 'đến ${[...m.to, ...m.cc].map((p) => p.email == store.me?.person.email ? 'tôi' : p.short).join(', ')}';
    return Container(
      decoration: BoxDecoration(
        border: i == 0 ? null : Border(top: BorderSide(color: mc.line)),
      ),
      padding: EdgeInsets.fromLTRB(widget.wide ? 16 : 12, 14, widget.wide ? 24 : 12, open ? 8 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MailAvatar(from, size: 40),
          SizedBox(width: widget.wide ? 16 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: t.messages.length > 1 ? () => setState(() => open ? _open.remove(m.id) : _open.add(m.id)) : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: from.display,
                                    style: TextStyle(fontWeight: FontWeight.w700, color: mc.text),
                                  ),
                                  if (widget.wide)
                                    TextSpan(
                                      text: '  <${m.from.email}>',
                                      style: TextStyle(fontSize: 12, color: mc.muted),
                                    ),
                                ],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (open)
                              Text(
                                toTxt,
                                style: TextStyle(fontSize: 12, color: mc.muted),
                                overflow: TextOverflow.ellipsis,
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  htmlToText(m.html).replaceAll('\n', ' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: mc.muted),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        fmtMessageDate(m.date, relative: widget.wide),
                        style: TextStyle(fontSize: 12, color: mc.muted),
                      ),
                      if (open && !store.readOnly) ...[
                        IconButton(tooltip: 'Trả lời', visualDensity: VisualDensity.compact, iconSize: 18, onPressed: () => reply('reply', m), icon: const Icon(Icons.reply)),
                        Builder(
                          builder: (b) => IconButton(
                            tooltip: 'Thêm',
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            onPressed: () => showAnchoredMenu(b, [
                              MenuEntry('Trả lời', Icons.reply, () => reply('reply', m)),
                              MenuEntry('Trả lời tất cả', Icons.reply_all, () => reply('all', m)),
                              MenuEntry('Chuyển tiếp', Icons.forward, () => reply('fwd', m)),
                            ]),
                            icon: const Icon(Icons.more_vert),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (open) ...[
                  const SizedBox(height: 10),
                  if (MailImageTrust.hasRemoteImages(m.html) && !_imagesOn(m)) _imagesBar(m, mc),
                  MailHtml(
                    m.html,
                    key: ValueKey('${m.id}-${_imagesOn(m)}'),
                    style: TextStyle(fontSize: 14.5, height: 1.55, color: mc.text),
                    inlineImage: _inlineImage,
                    loadImages: _imagesOn(m),
                    onImageTap: (src) => _viewImage(m, src),
                  ),
                  if (m.attachments.isNotEmpty) ...[
                    Divider(color: mc.line, height: 24),
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${m.attachments.length} tệp đính kèm',
                          style: TextStyle(fontWeight: FontWeight.w500, color: mc.text),
                        ),
                      ),
                      if (m.attachments.length > 1 && MailHooks.saveToDrive != null)
                        TextButton.icon(
                          key: const ValueKey('att-drive-all'),
                          onPressed: () => _saveToDrive(m.attachments),
                          icon: const Icon(Icons.add_to_drive_rounded, size: 18),
                          label: const Text('Lưu tất cả vào Drive'),
                        ),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final a in m.attachments)
                          _AttachmentCard(
                            a,
                            files: _files,
                            onOpen: () => _view(m, a),
                            onDownload: () => _download(a),
                            onDrive: MailHooks.saveToDrive == null ? null : () => _saveToDrive([a]),
                            phone: !widget.wide,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard(this.a, {required this.files, required this.onOpen, required this.onDownload, this.onDrive, this.phone = false});
  final MailAttachment a;
  final AttachmentFiles files;
  final VoidCallback onOpen, onDownload;
  final VoidCallback? onDrive;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final (icon, color) = attachmentIcon(a);
    final w = phone ? (MediaQuery.sizeOf(context).width - 100) / 2 : 180.0;
    Widget act(IconData i, String tip, VoidCallback? f, Key key) => SizedBox(
          width: 30,
          height: 30,
          child: IconButton(key: key, tooltip: tip, padding: EdgeInsets.zero, iconSize: 17, onPressed: f, icon: Icon(i, color: mc.muted)),
        );
    return Tooltip(
      message: a.name,
      child: Material(
        color: mc.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: mc.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: SizedBox(
            width: w,
            height: 132,
            child: Column(
              children: [
                Expanded(child: SizedBox(width: double.infinity, child: AttachmentThumb(a, files: files))),
                Container(
                  color: mc.surface,
                  padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: mc.text)),
                          Text(fmtSize(a.size), style: TextStyle(fontSize: 11, color: mc.muted)),
                        ]),
                      ),
                      act(Icons.download_rounded, 'Tải về', onDownload, ValueKey('att-dl-${a.id}')),
                      if (onDrive != null) act(Icons.add_to_drive_rounded, 'Lưu vào Drive', onDrive, ValueKey('att-dr-${a.id}')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Một mục của menu thả xuống.
class MenuEntry {
  const MenuEntry(this.title, this.icon, this.onTap, {this.color});
  final String title;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? color;
}

Future<void> showAnchoredMenu(BuildContext anchor, List<MenuEntry> entries) async {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
  final pos = RelativeRect.fromRect(
    Rect.fromPoints(box.localToGlobal(Offset(0, box.size.height), ancestor: overlay), box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay)),
    Offset.zero & overlay.size,
  );
  final i = await showMenu<int>(
    context: anchor,
    position: pos,
    items: [
      for (var k = 0; k < entries.length; k++)
        PopupMenuItem(
          value: k,
          height: 40,
          child: Row(
            children: [
              if (entries[k].color != null)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(color: entries[k].color, borderRadius: BorderRadius.circular(4)),
                )
              else if (entries[k].icon != null) ...[
                Icon(entries[k].icon, size: 18),
                const SizedBox(width: 12),
              ],
              Flexible(child: Text(entries[k].title)),
            ],
          ),
        ),
    ],
  );
  if (i != null) entries[i].onTap();
}

/// Menu gắn / gỡ nhãn cho các cuộc hội thoại [ids]; có ô tìm nhãn và "Tạo nhãn mới".
Future<void> showLabelMenu(
  BuildContext anchor,
  MailStore store,
  List<String> ids, {
  List<MailThreadSummary> extra = const [],
  required void Function(String message, Future<void> Function()? undo) onDone,
}) async {
  final threads = [...store.items.where((t) => ids.contains(t.id)), ...extra.where((t) => !store.items.contains(t))];
  final picked = await showDialog<Object>(
    context: anchor,
    builder: (ctx) {
      var q = '';
      return StatefulBuilder(
        builder: (ctx, set) => SimpleDialog(
          title: const Text('Gắn nhãn là:'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Tìm nhãn', isDense: true),
                onChanged: (v) => set(() => q = v.toLowerCase()),
              ),
            ),
            for (final l in store.labels.where((l) => l.name.toLowerCase().contains(q)))
              Builder(
                builder: (_) {
                  final n = threads.where((t) => t.labels.contains(l.id)).length;
                  final all = threads.isNotEmpty && n == threads.length;
                  return SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, l),
                    child: Row(
                      children: [
                        Icon(
                          all
                              ? Icons.check_box
                              : n > 0
                              ? Icons.indeterminate_check_box
                              : Icons.check_box_outline_blank,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(color: Color(l.color), borderRadius: BorderRadius.circular(4)),
                        ),
                        const SizedBox(width: 10),
                        Text(l.name),
                      ],
                    ),
                  );
                },
              ),
            const Divider(),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'new'),
              child: const Row(children: [Icon(Icons.add, size: 20), SizedBox(width: 12), Text('Tạo nhãn mới')]),
            ),
          ],
        ),
      );
    },
  );
  if (!anchor.mounted) return;
  if (picked == 'new') {
    final l = await showNewLabelDialog(anchor, store);
    if (l == null) return;
    final undo = await store.apply(ids, MailChange(addLabels: [l.id]), extra: extra);
    onDone('Đã gắn nhãn "${l.name}"', undo);
  } else if (picked is MailLabel) {
    final has = threads.isNotEmpty && threads.every((t) => t.labels.contains(picked.id));
    final undo = await store.apply(
      ids,
      has ? MailChange(removeLabels: [picked.id]) : MailChange(addLabels: [picked.id]),
      extra: extra,
    );
    onDone(has ? 'Đã gỡ nhãn "${picked.name}"' : 'Đã gắn nhãn "${picked.name}"', undo);
  }
}

Future<MailLabel?> showNewLabelDialog(BuildContext context, MailStore store) async {
  final ctl = TextEditingController();
  var color = kLabelSwatches.first;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Nhãn mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctl,
              autofocus: true,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Tên nhãn'),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final c in kLabelSwatches)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => set(() => color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: c == color ? Border.all(width: 3, color: Theme.of(ctx).colorScheme.onSurface) : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tạo')),
        ],
      ),
    ),
  );
  final name = ctl.text.trim();
  ctl.dispose();
  if (ok != true || name.isEmpty) return null;
  return store.createLabel(name, color);
}
