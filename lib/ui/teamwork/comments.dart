// TeamWork: bình luận của một việc — chữ có định dạng, @nhắc, trả lời một cấp, sửa / xoá, thả cảm xúc, tệp đính kèm;
// bình luận của agent có nhãn "Agent · thay <người>". Ô soạn ở dưới (AI hỗ trợ có thể điền sẵn bản cập nhật).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart' show emojiOf, pickFilesOrReport;
import '../open_file.dart' show openLocalFile;
import '../reaction_usage.dart';
import '../reactions.dart' show showEmojiPicker;
import '../todo/block_editor.dart';
import '../todo/model.dart';
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'rich_mentions.dart';
import 'store.dart';

/// Dãy cảm xúc (bấm để thả / gỡ) + nút thêm cảm xúc.
class ReactionRow extends StatelessWidget {
  const ReactionRow({super.key, required this.reactions, required this.me, required this.onToggle, this.keyPrefix = 'rx'});
  final List<TwReaction> reactions;
  final String me, keyPrefix;
  final void Function(String emoji) onToggle;

  Future<void> _add(BuildContext context) async {
    await ReactionUsage.load();
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final pos = box == null ? const RelativeRect.fromLTRB(100, 100, 100, 100) : RelativeRect.fromRect(box.localToGlobal(Offset.zero) & box.size, Offset.zero & MediaQuery.sizeOf(context));
    final r = await showMenu<String>(
      context: context,
      position: pos,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final e in ReactionUsage.quick.take(6))
              InkWell(key: ValueKey('$keyPrefix-quick-$e'), onTap: () => Navigator.pop(context, e), child: Padding(padding: const EdgeInsets.all(4), child: Text(emojiOf(e), style: const TextStyle(fontSize: 22)))),
            IconButton(onPressed: () => Navigator.pop(context, '…'), icon: const Icon(Icons.add_reaction_outlined)),
          ]),
        ),
      ],
    );
    if (r == null || !context.mounted) return;
    final e = r == '…' ? await showEmojiPicker(context) : r;
    if (e == null) return;
    ReactionUsage.used(e);
    onToggle(e);
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    return Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final r in reactions.where((r) => r.users.isNotEmpty))
        Tooltip(
          message: '${r.users.length} người',
          child: InkWell(
            key: ValueKey('$keyPrefix-${r.emoji}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => onToggle(r.emoji),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: r.users.contains(me) ? look.accentSoft : look.bg,
                border: Border.all(color: r.users.contains(me) ? look.accent : look.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(emojiOf(r.emoji), style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text('${r.users.length}', style: TextStyle(fontSize: 12, color: r.users.contains(me) ? look.accent : look.sub, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      Builder(
        builder: (c) => InkWell(
          key: ValueKey('$keyPrefix-add'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _add(c),
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.add_reaction_outlined, size: 15, color: look.sub),
          ),
        ),
      ),
    ]);
  }
}

/// Thả / gỡ cảm xúc trên danh sách cục bộ (áp ngay trước khi máy chủ trả).
List<TwReaction> toggleReaction(List<TwReaction> list, String emoji, String me) {
  final out = [for (final r in list) TwReaction(r.emoji, [...r.users])];
  final r = out.where((x) => x.emoji == emoji).firstOrNull;
  if (r == null) {
    out.add(TwReaction(emoji, [me]));
  } else if (r.users.contains(me)) {
    r.users.remove(me);
  } else {
    r.users.add(me);
  }
  return out.where((x) => x.users.isNotEmpty).toList();
}

class TwComments extends StatefulWidget {
  const TwComments({super.key, required this.store, required this.task, this.onMention, this.canComment = true, this.composer = true});
  final TwStore store;
  final TwTask task;
  final void Function(String kind, String id)? onMention;
  final bool canComment, composer;
  @override
  State<TwComments> createState() => TwCommentsState();
}

class TwCommentsState extends State<TwComments> {
  List<TwComment>? _list;
  List<TBlock> _draft = [];
  int _draftRev = 0;
  String? _replyTo, _editing;
  List<TBlock> _editBlocks = [];
  final List<TwAttachment> _pending = [];
  bool _sending = false;
  final _ed = BlockEditorController();
  int _rev = -1;

  TwStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    load();
    store.addListener(_maybeReload);
  }

  @override
  void dispose() {
    store.removeListener(_maybeReload);
    _ed.dispose();
    super.dispose();
  }

  void _maybeReload() {
    final r = store.taskRev[widget.task.id] ?? 0;
    if (r != _rev && _rev >= 0) load();
  }

  Future<void> load() async {
    _rev = store.taskRev[widget.task.id] ?? 0;
    try {
      final l = await store.api.comments(widget.task.id);
      if (mounted) setState(() => _list = l);
    } catch (_) {
      if (mounted) setState(() => _list ??= []);
    }
  }

  /// Điền sẵn ô soạn (AI soạn bản cập nhật).
  void setDraft(List<TBlock> blocks) => setState(() {
        _draft = blocks;
        _draftRev++;
      });

  Future<void> _send() async {
    final blocks = _draft.where((b) => b.text.trim().isNotEmpty || b.t == 'hr').toList();
    if (blocks.isEmpty && _pending.isEmpty) return;
    setState(() => _sending = true);
    try {
      final c = await store.api.addComment(widget.task.id, blocksToJson(blocks), parentId: _replyTo, attachmentIds: [for (final a in _pending) a.id]);
      setState(() {
        _list = [...?_list, c];
        _draft = [];
        _draftRev++;
        _replyTo = null;
        _pending.clear();
      });
      widget.task.commentCount++;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final f = (await pickFilesOrReport(context)).firstOrNull;
    if (f == null) return;
    try {
      final a = await store.api.upload(widget.task.id, f.name, await f.readAsBytes(), forComment: true);
      setState(() => _pending.add(a));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _react(TwComment c, String emoji) async {
    setState(() => c.reactions = toggleReaction(c.reactions, emoji, store.meId));
    try {
      await store.api.react('comment', c.id, emoji);
    } catch (_) {
      setState(() => c.reactions = toggleReaction(c.reactions, emoji, store.meId));
    }
  }

  Future<void> _saveEdit(TwComment c) async {
    try {
      final n = await store.api.editComment(c.id, blocksToJson(_editBlocks));
      setState(() {
        c.blocks = n.blocks;
        c.editedAt = n.editedAt ?? DateTime.now().millisecondsSinceEpoch;
        _editing = null;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete(TwComment c) async {
    if (!await confirm(context, 'Xoá bình luận?', 'Bình luận sẽ hiện "đã xoá".', ok: 'Xoá', danger: true)) return;
    try {
      await store.api.deleteComment(c.id);
      setState(() => c.deleted = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _comment(TwComment c, TwLook look, {bool reply = false}) {
    final mine = c.author == store.meId;
    final bot = c.agentBot;
    final agent = bot == null ? null : store.agent(bot);
    final name = c.agentName ?? agent?.name ?? c.authorName;
    final canAdmin = store.fullOf(widget.task.projectId)?.project.canAdmin ?? false;
    return Padding(
      key: ValueKey('comment-${c.id}'),
      padding: EdgeInsets.only(left: reply ? 40 : 0, top: 10, bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TwAvatar(name: name, id: bot ?? c.author, agent: bot != null, size: reply ? 26 : 30, border: false),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (bot != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: look.aiSoft, borderRadius: BorderRadius.circular(5)),
                  child: Text('Agent · thay ${c.authorName}', style: TextStyle(fontSize: 11, color: look.ai, fontWeight: FontWeight.w600)),
                ),
              ] else if (c.via == 'mcp') ...[
                const SizedBox(width: 6),
                Text('qua agent', style: TextStyle(fontSize: 11, color: look.ai)),
              ],
              const SizedBox(width: 6),
              Text(timeAgo(c.createdAt, store.now), style: TextStyle(fontSize: 12, color: look.sub)),
              if (c.editedAt != null && !c.deleted) Text(' · đã sửa', style: TextStyle(fontSize: 12, color: look.sub)),
              const Spacer(),
              if (!c.deleted && widget.canComment)
                PopupMenuButton<String>(
                  key: ValueKey('cmenu-${c.id}'),
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_horiz, size: 18, color: look.sub),
                  onSelected: (v) {
                    if (v == 'reply') setState(() => _replyTo = c.parentId ?? c.id);
                    if (v == 'edit') {
                      setState(() {
                        _editing = c.id;
                        _editBlocks = [for (final b in c.blocks) b.clone()];
                      });
                    }
                    if (v == 'delete') _delete(c);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'reply', child: Text('Trả lời')),
                    if (mine) const PopupMenuItem(value: 'edit', child: Text('Sửa')),
                    if (mine || canAdmin) const PopupMenuItem(value: 'delete', child: Text('Xoá')),
                  ],
                ),
            ]),
            const SizedBox(height: 2),
            if (c.deleted)
              Text('Bình luận đã xoá', style: TextStyle(color: look.sub, fontStyle: FontStyle.italic))
            else if (_editing == c.id) ...[
              TwRichEditor(blocks: _editBlocks, onChanged: (b) => _editBlocks = b, store: store, projectId: widget.task.projectId, compact: true, autofocus: true),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => setState(() => _editing = null), child: const Text('Huỷ')),
                FilledButton(key: ValueKey('csave-${c.id}'), onPressed: () => _saveEdit(c), child: const Text('Lưu')),
              ]),
            ] else
              TwRichView(c.blocks, onMention: widget.onMention),
            if (c.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 6, children: [for (final a in c.attachments) AttachmentChip(a: a, store: store)]),
              ),
            if (!c.deleted) Padding(padding: const EdgeInsets.only(top: 6), child: ReactionRow(reactions: c.reactions, me: store.meId, keyPrefix: 'crx-${c.id}', onToggle: (e) => _react(c, e))),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final list = _list;
    if (list == null) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final roots = list.where((c) => c.parentId == null).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final replying = list.where((c) => c.id == _replyTo).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in roots) ...[
        _comment(c, look),
        for (final r in list.where((x) => x.parentId == c.id).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt))) _comment(r, look, reply: true),
      ],
      if (roots.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text('Chưa có bình luận', style: TextStyle(color: look.sub))),
      if (widget.composer && widget.canComment) ...[
        const SizedBox(height: 10),
        if (replying != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(color: look.surface, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.reply, size: 16, color: look.sub),
              const SizedBox(width: 6),
              Expanded(child: Text('Trả lời ${replying.authorName}: ${blocksText(replying.blocks)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: look.sub))),
              InkWell(onTap: () => setState(() => _replyTo = null), child: Icon(Icons.close, size: 16, color: look.sub)),
            ]),
          ),
        TwRichEditor(
          key: ValueKey('composer-$_draftRev'),
          blocks: _draft,
          onChanged: (b) => _draft = b,
          store: store,
          projectId: widget.task.projectId,
          controller: _ed,
          compact: true,
        ),
        if (_pending.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, children: [for (final a in _pending) AttachmentChip(a: a, store: store, onRemove: () => setState(() => _pending.remove(a)))])),
        const SizedBox(height: 6),
        Row(children: [
          IconButton(tooltip: 'Đính kèm', onPressed: _attach, icon: const Icon(Icons.attach_file, size: 20)),
          const Spacer(),
          FilledButton.icon(key: const ValueKey('comment-send'), onPressed: _sending ? null : _send, icon: const Icon(Icons.send, size: 16), label: const Text('Bình luận')),
        ]),
      ],
    ]);
  }
}

/// Ô tệp đính kèm nhỏ (bình luận, ô soạn).
class AttachmentChip extends StatelessWidget {
  const AttachmentChip({super.key, required this.a, required this.store, this.onRemove});
  final TwAttachment a;
  final TwStore store;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => InputChip(
        avatar: Icon(a.isDrive ? Icons.add_to_drive : Icons.insert_drive_file_outlined, size: 16),
        label: Text(a.name, overflow: TextOverflow.ellipsis),
        onDeleted: onRemove,
        onPressed: () => openAttachment(context, store, a),
      );
}

/// Mở tệp: tệp Drive mở link, tệp tải lên thì tải về rồi mở bằng app hệ thống.
Future<void> openAttachment(BuildContext context, TwStore store, TwAttachment a) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (a.isDrive && a.driveUrl != null) {
      await launchUrl(Uri.parse(a.driveUrl!), mode: LaunchMode.externalApplication);
      return;
    }
    final path = await store.api.download(a);
    if (!await openLocalFile(path, mime: a.mime.isEmpty ? null : a.mime, title: a.name)) throw StateError('Không mở được tệp ${a.name}');
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
