// Thư: soạn thư. Máy tính: khung nổi góc dưới bên phải (thu nhỏ / phóng to); điện thoại: trang toàn màn hình.
// Người nhận dạng thẻ, gợi ý từ danh bạ thư; định dạng (đậm / nghiêng / gạch chân / gạch ngang / màu chữ / link /
// danh sách / danh sách số / trích dẫn, dán giữ định dạng), tệp đính kèm, tự lưu bản nháp, Ctrl+Enter để gửi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart' show pickFilesOrReport;
import '../todo/look.dart' show kTextColors;
import '../todo/model.dart' show TRun;
import 'api.dart';
import 'html_view.dart';
import 'model.dart';
import 'rich.dart';
import 'widgets.dart';

/// Dữ liệu mở khung soạn (thư mới, trả lời, chuyển tiếp, mở bản nháp).
class ComposeArgs {
  const ComposeArgs({this.to = const [], this.cc = const [], this.subject = '', this.body = '', this.quote, this.threadId, this.draftId, this.attachments = const [], this.kind = 'new', this.runs, this.targets = const {}});
  final List<MailPerson> to, cc;
  final String subject;
  /// Nội dung có sẵn (chữ thuần, vd thư AI soạn).
  final String body;
  /// Nội dung có định dạng (mở lại bản nháp); có thì dùng thay [body].
  final List<TRun>? runs;
  /// HTML trích dẫn thư cũ, nối vào cuối khi gửi.
  final String? quote;
  final String? threadId, draftId;
  final List<MailAttachment> attachments;
  /// new | reply | all | fwd | draft
  final String kind;
  /// Người nhận cho từng kiểu trả lời ('reply' | 'all' -> (to, cc)), để đổi ngay trong khung soạn trước khi gửi.
  final Map<String, (List<MailPerson>, List<MailPerson>)> targets;

  ComposeArgs withBody(String b) => ComposeArgs(to: to, cc: cc, subject: subject, body: b, quote: quote, threadId: threadId, draftId: draftId, attachments: attachments, kind: kind, runs: runs, targets: targets);
}

class ComposeController extends ChangeNotifier {
  ComposeController(this.api, this.args)
      : to = [...args.to],
        cc = [...args.cc],
        attachments = [...args.attachments],
        draftId = args.draftId,
        showCc = args.cc.isNotEmpty,
        subject = TextEditingController(text: args.subject),
        body = MailRichController(args.runs ?? [TRun(args.body)]);

  final MailApi api;
  final ComposeArgs args;
  final List<MailPerson> to, cc, bcc = [];
  final List<MailAttachment> attachments;
  final TextEditingController subject;
  final MailRichController body;
  String? draftId;
  /// Kiểu trả lời đang chọn ('reply' | 'all'); đổi bằng [setMode].
  late String mode = args.kind;
  bool showCc, showBcc = false, minimized = false, maximized = false, sending = false, quoteShown = false;

  bool get canSwitchMode => args.targets.containsKey('reply') && args.targets.containsKey('all');

  /// Trả lời / Trả lời tất cả: thay danh sách người nhận theo kiểu đã chọn.
  void setMode(String m) {
    final t = args.targets[m];
    if (t == null || m == mode) return;
    mode = m;
    to
      ..clear()
      ..addAll(t.$1);
    cc
      ..clear()
      ..addAll(t.$2);
    if (cc.isNotEmpty) showCc = true;
    changed();
  }
  String savedNote = '';
  int uploading = 0;
  Timer? _t;
  bool _dirty = false, _closed = false;
  VoidCallback? onDraftsChanged;

  String get title => subject.text.trim().isNotEmpty
      ? subject.text.trim()
      : switch (args.kind) {
          'fwd' => 'Chuyển tiếp',
          'reply' || 'all' => 'Trả lời',
          _ => 'Thư mới',
        };

  bool get isEmpty => to.isEmpty && cc.isEmpty && bcc.isEmpty && subject.text.trim().isEmpty && body.body.trim().isEmpty && attachments.isEmpty;

  void changed() {
    _dirty = true;
    savedNote = '';
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1500), save);
    notifyListeners();
  }

  void toggle(void Function() f) {
    f();
    notifyListeners();
  }

  String html() => composeHtml(body.runs) + (args.quote ?? '');

  /// Bản chữ thuần gửi kèm bản HTML.
  String text() {
    final q = args.quote;
    return composeText(body.runs) + (q == null ? '' : '\n\n${htmlToText(q).split('\n').map((l) => l.isEmpty ? '>' : '> $l').join('\n')}');
  }

  MailDraft draft() => MailDraft(id: draftId, to: to, cc: cc, bcc: bcc, subject: subject.text.trim(), html: html(), text: text(), attachments: attachments, threadId: args.threadId);

  Future<void> save() async {
    if (!_dirty || _closed || isEmpty) return;
    _dirty = false;
    try {
      draftId = await api.saveDraft(draft());
      savedNote = 'Đã lưu bản nháp';
      onDraftsChanged?.call();
    } catch (_) {
      savedNote = 'Chưa lưu được bản nháp';
    }
    if (!_closed) notifyListeners();
  }

  Future<void> addFiles(List<(String path, String name, int size)> files, void Function(String) report) async {
    for (final f in files) {
      if (f.$3 > 25 * 1024 * 1024) {
        report('"${f.$2}" vượt quá giới hạn 25 MB');
        continue;
      }
      uploading++;
      notifyListeners();
      try {
        attachments.add(await api.upload(File(f.$1), name: f.$2));
        changed();
      } catch (e) {
        report('Không tải lên được "${f.$2}": $e');
      }
      uploading--;
      notifyListeners();
    }
  }

  /// Kiểm tra trước khi gửi; trả câu báo lỗi (null = gửi được).
  String? validate() {
    if (to.isEmpty && cc.isEmpty && bcc.isEmpty) return 'Vui lòng chỉ định ít nhất một người nhận.';
    final bad = [...to, ...cc, ...bcc].where((p) => !p.valid).firstOrNull;
    if (bad != null) return 'Địa chỉ "${bad.email}" không hợp lệ. Vui lòng kiểm tra lại người nhận.';
    if (uploading > 0) return 'Đang tải tệp đính kèm lên, vui lòng đợi.';
    return null;
  }

  Future<void> send() async {
    sending = true;
    notifyListeners();
    _t?.cancel();
    try {
      await api.send(draft(), draftId: draftId);
      _closed = true;
    } finally {
      sending = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> close({bool keepDraft = true}) async {
    _t?.cancel();
    if (keepDraft && _dirty && !isEmpty) {
      _dirty = true;
      await save();
    }
    _closed = true;
  }

  Future<void> discard() async {
    _t?.cancel();
    _closed = true;
    if (draftId != null) {
      try {
        await api.deleteDraft(draftId!);
      } catch (_) {}
      onDraftsChanged?.call();
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    subject.dispose();
    body.dispose();
    super.dispose();
  }
}

/// Nội dung khung soạn (dùng cho cả khung nổi và trang toàn màn hình).
class ComposeBody extends StatefulWidget {
  const ComposeBody({super.key, required this.c, required this.onSent, required this.onClosed, this.phone = false, this.inline = false});
  final ComposeController c;
  final void Function(String? threadId) onSent;
  final void Function(String message) onClosed;
  final bool phone, inline;

  @override
  State<ComposeBody> createState() => _ComposeBodyState();
}

class _ComposeBodyState extends State<ComposeBody> {
  ComposeController get c => widget.c;
  bool _fmt = true;
  // "Sửa bằng AI": ô lệnh dưới thân thư; AI viết lại nội dung đang soạn (không tự gửi), có hoàn tác.
  bool _aiOpen = false, _aiBusy = false;
  final _aiCmd = TextEditingController();
  List<TRun>? _aiUndo;
  final _bodyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    c.addListener(_upd);
    c.body.onEdited = c.changed;
  }

  @override
  void dispose() {
    c.removeListener(_upd);
    _bodyFocus.dispose();
    _aiCmd.dispose();
    super.dispose();
  }

  Future<void> _aiRevise() async {
    if (_aiBusy) return;
    setState(() => _aiBusy = true);
    try {
      final r = await c.api.aiRevise(threadId: c.args.threadId, draft: c.body.body, instruction: _aiCmd.text.trim());
      if (!mounted) return;
      if (r.draft.trim().isEmpty) {
        _report('AI chưa sửa được, thử lại sau');
      } else {
        _aiUndo = c.body.runs;
        c.body.setBody([TRun(r.draft)]);
        _aiCmd.clear();
        c.changed();
      }
    } catch (e) {
      if (mounted) _report('AI lỗi: $e');
    }
    if (mounted) setState(() => _aiBusy = false);
  }

  void _aiUndoNow() {
    final u = _aiUndo;
    if (u == null) return;
    c.body.setBody(u);
    _aiUndo = null;
    c.changed();
  }

  Widget _aiBar(MailColors mc) => Container(
        key: const ValueKey('mail-ai-revise'),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(color: mc.accentSoft.withValues(alpha: .55), borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Icon(Icons.auto_awesome, size: 18, color: mc.accentText),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _aiCmd,
              enabled: !_aiBusy,
              autofocus: true,
              onSubmitted: (_) => _aiRevise(),
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Bảo AI sửa thư: ngắn gọn hơn, thêm lời xin lỗi, dịch sang tiếng Anh…'),
            ),
          ),
          if (_aiUndo != null && !_aiBusy) TextButton(onPressed: _aiUndoNow, child: const Text('Hoàn tác')),
          _aiBusy
              ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(tooltip: 'AI sửa', visualDensity: VisualDensity.compact, icon: Icon(Icons.send, size: 18, color: mc.accentText), onPressed: _aiRevise),
          IconButton(tooltip: 'Đóng', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _aiOpen = false)),
        ]),
      );

  Widget _modeMenu(MailColors mc) {
    const labels = {'reply': 'Trả lời', 'all': 'Trả lời tất cả'};
    return PopupMenuButton<String>(
      key: const ValueKey('mail-reply-mode'),
      tooltip: 'Chọn kiểu trả lời',
      initialValue: c.mode,
      onSelected: c.setMode,
      itemBuilder: (_) => [
        for (final e in labels.entries)
          PopupMenuItem(value: e.key, child: Row(children: [Icon(e.key == 'all' ? Icons.reply_all : Icons.reply, size: 18), const SizedBox(width: 10), Text(e.value)])),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: mc.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(c.mode == 'all' ? Icons.reply_all : Icons.reply, size: 18, color: mc.text),
          const SizedBox(width: 6),
          Text(labels[c.mode] ?? 'Trả lời', style: TextStyle(fontSize: 13, color: mc.text)),
          Icon(Icons.arrow_drop_down, size: 18, color: mc.muted),
        ]),
      ),
    );
  }

  void _upd() {
    if (mounted) setState(() {});
  }

  void _report(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  Future<void> _attach() async {
    final files = await pickFilesOrReport(context);
    await c.addFiles([for (final f in files) if (f.path != null) (f.path!, f.name, File(f.path!).lengthSync())], _report);
  }

  Future<bool> _confirm(String title, String text, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok))],
        ),
      ) ??
      false;

  Future<void> _send() async {
    final err = c.validate();
    if (err != null) {
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Lỗi'), content: Text(err), actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
      return;
    }
    if (c.subject.text.trim().isEmpty && c.args.threadId == null && !await _confirm('Gửi thư không có tiêu đề?', 'Gửi thư này mà không có dòng tiêu đề?', 'Gửi')) return;
    if (c.attachments.isEmpty && RegExp(r'đính kèm|gửi kèm|attach', caseSensitive: false).hasMatch('${c.subject.text} ${c.body.body}') &&
        !await _confirm('Quên tệp đính kèm?', 'Bạn nhắc đến tệp đính kèm nhưng chưa đính kèm tệp nào. Vẫn gửi?', 'Vẫn gửi')) {
      return;
    }
    try {
      await c.send();
      widget.onSent(c.args.threadId);
    } catch (e) {
      _report('Gửi thư thất bại: $e');
    }
  }

  Future<void> _close() async {
    final had = !c.isEmpty;
    await c.close();
    widget.onClosed(had && c.draftId != null ? 'Đã lưu thư vào Thư nháp' : '');
  }

  Future<void> _discard() async {
    await c.discard();
    widget.onClosed('Đã huỷ bản nháp');
  }

  Future<void> _link() async {
    final b = c.body;
    final sel = b.selection;
    final has = sel.isValid && !sel.isCollapsed;
    final url = TextEditingController(text: b.current.a ?? '');
    final label = TextEditingController();
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chèn liên kết'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!has) TextField(controller: label, decoration: const InputDecoration(labelText: 'Chữ hiển thị')),
            TextField(
              controller: url,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Địa chỉ (https://… hoặc email)'),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ]),
        ),
        actions: [
          if (b.current.a != null) TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bỏ liên kết')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (r == null) return;
    b.selection = sel;
    if (r == false) {
      b.setLink(null);
    } else {
      var u = url.text.trim();
      if (u.isEmpty) return;
      if (!RegExp(r'^(https?:|mailto:)', caseSensitive: false).hasMatch(u)) u = u.contains('@') && !u.contains('/') ? 'mailto:$u' : 'https://$u';
      if (has) {
        b.setLink(u);
      } else {
        final t = label.text.trim().isEmpty ? url.text.trim() : label.text.trim();
        b.insertRuns([TRun(t, b.current.copyWith(a: u))]);
      }
    }
    c.changed();
    _bodyFocus.requestFocus();
  }

  Widget _colorBtn() {
    final mc = MailColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cur = kTextColors[c.body.current.fg];
    return PopupMenuButton<String>(
      tooltip: 'Màu chữ',
      onSelected: (v) {
        c.body.setColor(v.isEmpty ? null : v);
        c.changed();
        _bodyFocus.requestFocus();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in ['', ...kTextColors.keys])
              InkWell(
                key: ValueKey('mail-color-$k'),
                onTap: () => Navigator.pop(context, k),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: k.isEmpty ? null : (dark ? kTextColors[k]!.$2 : kTextColors[k]!.$1),
                    shape: BoxShape.circle,
                    border: Border.all(color: mc.muted.withValues(alpha: .5)),
                  ),
                  child: k.isEmpty ? Icon(Icons.format_color_reset, size: 15, color: mc.muted) : null,
                ),
              ),
          ]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.format_color_text, size: 19, color: cur == null ? null : (dark ? cur.$2 : cur.$1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    c.body
      ..dark = Theme.of(context).brightness == Brightness.dark
      ..accent = mc.accent
      ..muted = mc.muted;
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) => SingleActivator(k, control: !mac, meta: mac, shift: shift);
    void fmt(VoidCallback f) {
      f();
      c.changed();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Column(children: [
        if (widget.phone)
          SizedBox(
            height: 56,
            child: Row(children: [
              IconButton(tooltip: 'Đóng', icon: const Icon(Icons.arrow_back), onPressed: _close),
              const Expanded(child: Text('Soạn thư', style: TextStyle(fontSize: 18))),
              IconButton(tooltip: 'Đính kèm tệp', icon: const Icon(Icons.attach_file), onPressed: _attach),
              IconButton(tooltip: 'Gửi', icon: Icon(Icons.send_outlined, color: mc.accent), onPressed: c.sending ? null : _send),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'discard' ? _discard() : setState(() => c.showCc = c.showBcc = true),
                itemBuilder: (_) => const [PopupMenuItem(value: 'cc', child: Text('Thêm Cc/Bcc')), PopupMenuItem(value: 'discard', child: Text('Huỷ bản nháp'))],
              ),
            ]),
          ),
        RecipientField(label: 'Đến', people: c.to, api: c.api, onChanged: c.changed, autofocus: c.to.isEmpty, trailing: [
          if (!c.showCc) _ccBtn('Cc', () => c.toggle(() => c.showCc = true)),
          if (!c.showBcc) _ccBtn('Bcc', () => c.toggle(() => c.showBcc = true)),
        ]),
        if (c.showCc) RecipientField(label: 'Cc', people: c.cc, api: c.api, onChanged: c.changed),
        if (c.showBcc) RecipientField(label: 'Bcc', people: c.bcc, api: c.api, onChanged: c.changed),
        if (!(widget.inline && c.args.threadId != null))
          _Field(
            child: TextField(
              controller: c.subject,
              onChanged: (_) => c.changed(),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Tiêu đề'),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CallbackShortcuts(
                bindings: {
                  key(LogicalKeyboardKey.keyB): () => fmt(() => c.body.toggle('b')),
                  key(LogicalKeyboardKey.keyI): () => fmt(() => c.body.toggle('i')),
                  key(LogicalKeyboardKey.keyU): () => fmt(() => c.body.toggle('u')),
                  key(LogicalKeyboardKey.keyX, shift: true): () => fmt(() => c.body.toggle('s')),
                  key(LogicalKeyboardKey.keyK): _link,
                  key(LogicalKeyboardKey.keyV): () => c.body.paste(),
                  key(LogicalKeyboardKey.digit7, shift: true): () => fmt(() => c.body.setLineKind('ol')),
                  key(LogicalKeyboardKey.digit8, shift: true): () => fmt(() => c.body.setLineKind('ul')),
                  key(LogicalKeyboardKey.digit9, shift: true): () => fmt(() => c.body.setLineKind('quote')),
                },
                child: TextField(
                key: const ValueKey('mail-body'),
                controller: c.body,
                focusNode: _bodyFocus,
                autofocus: c.to.isNotEmpty,
                maxLines: null,
                minLines: widget.inline ? 5 : 8,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: c.args.quote == null ? 'Nội dung thư' : null),
                style: TextStyle(fontSize: 14.5, height: 1.5, color: mc.text),
              )),
              if (c.args.quote != null)
                c.quoteShown
                    ? Padding(padding: const EdgeInsets.only(top: 8), child: MailHtml(c.args.quote!))
                    : Tooltip(
                        message: 'Hiện nội dung đã cắt bớt',
                        child: InkWell(
                          onTap: () => c.toggle(() => c.quoteShown = true),
                          child: Container(width: 30, height: 18, decoration: BoxDecoration(color: mc.chip, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.more_horiz, size: 16, color: mc.muted)),
                        ),
                      ),
            ]),
          ),
        ),
        if (c.attachments.isNotEmpty || c.uploading > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in c.attachments)
                Container(
                  height: 30,
                  padding: const EdgeInsets.only(left: 10, right: 2),
                  decoration: BoxDecoration(color: mc.surface2, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(a.name, overflow: TextOverflow.ellipsis, style: TextStyle(color: mc.accentText, fontWeight: FontWeight.w500, fontSize: 13))),
                    const SizedBox(width: 4),
                    Text('(${fmtSize(a.size)})', style: TextStyle(color: mc.muted, fontSize: 12)),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      tooltip: 'Xoá tệp',
                      onPressed: () => c.toggle(() {
                        c.attachments.remove(a);
                        c.changed();
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                ),
              if (c.uploading > 0) const SizedBox(width: 60, height: 30, child: Center(child: LinearProgressIndicator())),
            ]),
          ),
        if (_aiOpen) _aiBar(mc),
        if (_fmt)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: mc.surface2, borderRadius: BorderRadius.circular(20)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _fbtn(Icons.format_bold, 'Đậm (Ctrl+B)', c.body.current.b, () => c.body.toggle('b')),
                _fbtn(Icons.format_italic, 'Nghiêng (Ctrl+I)', c.body.current.i, () => c.body.toggle('i')),
                _fbtn(Icons.format_underlined, 'Gạch chân (Ctrl+U)', c.body.current.u, () => c.body.toggle('u')),
                _fbtn(Icons.strikethrough_s, 'Gạch ngang (Ctrl+Shift+X)', c.body.current.s, () => c.body.toggle('s')),
                _colorBtn(),
                _sep(),
                _fbtn(Icons.link, 'Chèn liên kết (Ctrl+K)', c.body.current.a != null, _link, mark: false),
                _sep(),
                _fbtn(Icons.format_list_numbered, 'Danh sách số (Ctrl+Shift+7)', c.body.currentKind == 'ol', () => c.body.setLineKind('ol')),
                _fbtn(Icons.format_list_bulleted, 'Danh sách dấu đầu dòng (Ctrl+Shift+8)', c.body.currentKind == 'ul', () => c.body.setLineKind('ul')),
                _fbtn(Icons.format_quote, 'Trích dẫn (Ctrl+Shift+9)', c.body.currentKind == 'quote', () => c.body.setLineKind('quote')),
                _sep(),
                _fbtn(Icons.format_clear, 'Xoá định dạng', false, c.body.clearFormat),
              ]),
            ),
          )),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 12, widget.phone ? 12 + MediaQuery.paddingOf(context).bottom : 12),
          child: Row(children: [
            if (!widget.phone) ...[
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: mc.button, padding: const EdgeInsets.symmetric(horizontal: 24)),
                onPressed: c.sending ? null : _send,
                child: c.sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Gửi'),
              ),
              const SizedBox(width: 8),
            ],
            if (c.canSwitchMode) ...[_modeMenu(mc), const SizedBox(width: 4)],
            IconButton(tooltip: 'Tuỳ chọn định dạng', isSelected: _fmt, icon: const Icon(Icons.text_format), onPressed: () => setState(() => _fmt = !_fmt)),
            if (!widget.phone) IconButton(tooltip: 'Đính kèm tệp', icon: const Icon(Icons.attach_file), onPressed: _attach),
            IconButton(
              key: const ValueKey('mail-ai-revise-btn'),
              tooltip: 'Sửa bằng AI',
              isSelected: _aiOpen,
              icon: Icon(Icons.auto_awesome, color: mc.accentText),
              onPressed: () => setState(() => _aiOpen = !_aiOpen),
            ),
            const Spacer(),
            Text(c.savedNote, style: TextStyle(fontSize: 12, color: mc.muted)),
            IconButton(tooltip: 'Huỷ bản nháp', icon: const Icon(Icons.delete_outline), onPressed: _discard),
          ]),
        ),
      ]),
    );
  }

  Widget _ccBtn(String t, VoidCallback f) => InkWell(onTap: f, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4), child: Text(t, style: TextStyle(color: MailColors.of(context).muted, fontSize: 13))));

  Widget _sep() => Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 4), color: MailColors.of(context).muted.withValues(alpha: .35));

  Widget _fbtn(IconData i, String tip, bool on, VoidCallback f, {bool mark = true}) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        iconSize: 19,
        isSelected: on,
        style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
        onPressed: () {
          f();
          if (mark) c.changed();
        },
        icon: Icon(i),
      );
}

class _Field extends StatelessWidget {
  const _Field({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        constraints: const BoxConstraints(minHeight: 40),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: MailColors.of(context).line))),
        child: child,
      );
}

/// Ô người nhận: thẻ người + ô gõ, gợi ý từ danh bạ thư (Enter / Tab chọn; dấu phẩy chốt địa chỉ đang gõ).
class RecipientField extends StatefulWidget {
  const RecipientField({super.key, required this.label, required this.people, required this.api, required this.onChanged, this.autofocus = false, this.trailing = const []});
  final String label;
  final List<MailPerson> people;
  final MailApi api;
  final VoidCallback onChanged;
  final bool autofocus;
  final List<Widget> trailing;

  @override
  State<RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<RecipientField> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  OverlayEntry? _entry;
  List<MailPerson> _sug = [];
  int _sel = 0;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _commit();
        _hide();
      }
    });
  }

  @override
  void dispose() {
    _hide();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(MailPerson p) {
    if (!widget.people.contains(p)) widget.people.add(p);
    _ctl.clear();
    _hide();
    setState(() {});
    widget.onChanged();
  }

  void _commit() {
    final v = _ctl.text.trim().replaceAll(RegExp(r'[,;]$'), '');
    if (v.isNotEmpty) _add(MailPerson(v));
  }

  Future<void> _query(String v) async {
    if (RegExp(r'[,;]$').hasMatch(v)) return _commit();
    if (v.trim().isEmpty) return _hide();
    final id = ++_req;
    final r = await widget.api.contacts(v.trim());
    if (id != _req || !mounted) return;
    _sug = r.where((p) => !widget.people.contains(p)).toList();
    _sel = 0;
    _sug.isEmpty ? _hide() : _show();
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  void _show() {
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    _entry = OverlayEntry(builder: (ctx) {
      final mc = MailColors.of(context);
      return Positioned(
        width: 340,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(0, 36),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: mc.surface,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < _sug.length; i++)
                InkWell(
                  onTap: () => _add(_sug[i]),
                  child: Container(
                    color: i == _sel ? mc.surface2 : null,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      MailAvatar(_sug[i], size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_sug[i].display, style: TextStyle(color: mc.text)),
                          Text(_sug[i].email, style: TextStyle(color: mc.muted, fontSize: 12)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      );
    });
    Overlay.of(context).insert(_entry!);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (_entry != null && (e.logicalKey == LogicalKeyboardKey.arrowDown || e.logicalKey == LogicalKeyboardKey.arrowUp)) {
      _sel = (_sel + (e.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : _sug.length - 1)) % _sug.length;
      _entry!.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if ((e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.tab) && _ctl.text.trim().isNotEmpty) {
      _entry != null ? _add(_sug[_sel]) : _commit();
      return e.logicalKey == LogicalKeyboardKey.tab ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace && _ctl.text.isEmpty && widget.people.isNotEmpty) {
      setState(() => widget.people.removeLast());
      widget.onChanged();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return _Field(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(widget.label, style: TextStyle(color: mc.muted)),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final p in widget.people)
                Container(
                  height: 26,
                  padding: const EdgeInsets.only(left: 2, right: 2),
                  decoration: BoxDecoration(color: p.valid ? mc.chip : const Color(0x33E53935), borderRadius: BorderRadius.circular(13)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    MailAvatar(p, size: 22),
                    const SizedBox(width: 6),
                    ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: Text(p.display, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.valid ? mc.text : mc.danger))),
                    InkWell(
                      onTap: () {
                        setState(() => widget.people.remove(p));
                        widget.onChanged();
                      },
                      child: Padding(padding: const EdgeInsets.all(3), child: Icon(Icons.close, size: 14, color: mc.muted)),
                    ),
                  ]),
                ),
              CompositedTransformTarget(
                link: _link,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 120, maxWidth: 400),
                  child: IntrinsicWidth(
                    child: Focus(
                      onKeyEvent: _key,
                      child: TextField(
                        controller: _ctl,
                        focusNode: _focus,
                        autofocus: widget.autofocus,
                        onChanged: _query,
                        onSubmitted: (_) => _commit(),
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          ...widget.trailing,
        ]),
      ),
    );
  }
}

/// Khung soạn nổi góc dưới bên phải (máy tính).
class ComposeDock extends StatelessWidget {
  const ComposeDock({super.key, required this.c, required this.onSent, required this.onClosed});
  final ComposeController c;
  final void Function(String? threadId) onSent;
  final void Function(String message) onClosed;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final size = MediaQuery.sizeOf(context);
        final w = c.minimized ? 300.0 : c.maximized ? size.width * .8 : 560.0;
        final h = c.minimized ? 44.0 : c.maximized ? size.height * .9 : (size.height - 80).clamp(300.0, 560.0);
        return Material(
          elevation: 12,
          color: mc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: w,
            height: h,
            child: Column(children: [
              InkWell(
                onTap: () => c.toggle(() => c.minimized = !c.minimized),
                child: Container(
                  height: 44,
                  color: mc.surface2,
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(children: [
                    Expanded(child: Text(c.title, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w500, color: mc.text))),
                    _hb(Icons.minimize, 'Thu nhỏ', () => c.toggle(() => c.minimized = !c.minimized)),
                    _hb(c.maximized ? Icons.close_fullscreen : Icons.open_in_full, c.maximized ? 'Thoát toàn màn hình' : 'Toàn màn hình', () => c.toggle(() {
                          c.maximized = !c.maximized;
                          c.minimized = false;
                        })),
                    _hb(Icons.close, 'Lưu và đóng', () async {
                      final had = !c.isEmpty;
                      await c.close();
                      onClosed(had && c.draftId != null ? 'Đã lưu thư vào Thư nháp' : '');
                    }),
                  ]),
                ),
              ),
              if (!c.minimized) Expanded(child: ComposeBody(c: c, onSent: onSent, onClosed: onClosed)),
            ]),
          ),
        );
      },
    );
  }

  Widget _hb(IconData i, String tip, VoidCallback f) => IconButton(tooltip: tip, visualDensity: VisualDensity.compact, iconSize: 17, onPressed: f, icon: Icon(i));
}

/// Mở bản nháp: lấy lại người nhận / nội dung từ thư nháp.
ComposeArgs draftArgs(MailThread t) {
  final m = t.messages.first;
  return ComposeArgs(
    to: m.to,
    cc: m.cc,
    subject: t.summary.subject == '(không có tiêu đề)' ? '' : t.summary.subject,
    body: htmlToText(m.html),
    runs: htmlToRuns(m.html),
    attachments: m.attachments,
    draftId: t.summary.id,
    kind: 'draft',
  );
}

/// Trích dẫn khi trả lời / chuyển tiếp.
String quoteHtml(String kind, MailMessage m, String subject) {
  String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
  final when = '${m.date.hour.toString().padLeft(2, '0')}:${m.date.minute.toString().padLeft(2, '0')} ${m.date.day}/${m.date.month}/${m.date.year}';
  final head = kind == 'fwd'
      ? '<p>---------- Thư đã chuyển tiếp ---------<br>Từ: <b>${esc(m.from.display)}</b> &lt;${esc(m.from.email)}&gt;<br>Ngày: $when<br>Tiêu đề: ${esc(subject)}<br>Đến: ${esc(m.to.map((p) => p.email).join(', '))}</p>'
      : '<p>Vào $when, ${esc(m.from.display)} &lt;${esc(m.from.email)}&gt; đã viết:</p>';
  return '<br><div class="gq">$head<blockquote type="cite">${m.html}</blockquote></div>';
}

/// Thư mới / trả lời / chuyển tiếp từ thư [m] của cuộc hội thoại [t].
ComposeArgs replyArgs(String kind, MailThread t, MailMessage m, String myEmail) {
  final fromMe = m.from.email == myEmail;
  final one = (fromMe ? m.to : [m.from], <MailPerson>[]);
  final all = (fromMe ? m.to : [m.from, ...m.to.where((p) => p.email != myEmail)], m.cc.where((p) => p.email != myEmail).toList());
  var to = <MailPerson>[], cc = <MailPerson>[];
  if (kind == 'reply') (to, cc) = one;
  if (kind == 'all') (to, cc) = all;
  final base = t.summary.subject.replaceFirst(RegExp(r'^((re|fwd?|tl|tr):\s*)+', caseSensitive: false), '');
  return ComposeArgs(
    to: to,
    cc: cc,
    subject: '${kind == 'fwd' ? 'Fwd' : 'Re'}: $base',
    quote: quoteHtml(kind, m, t.summary.subject),
    threadId: kind == 'fwd' ? null : t.summary.id,
    attachments: kind == 'fwd' ? m.attachments : const [],
    kind: kind,
    targets: kind == 'fwd' ? const {} : {'reply': one, 'all': all},
  );
}

