// TeamWork: "AI hỗ trợ" trên một việc — tóm tắt bình luận, chia thành việc con, soạn cập nhật tiến độ, gợi ý người làm +
// ngày, hỏi đáp tự do, và lối tắt giao cho agent. Máy chủ chỉ trả đề xuất (không ghi gì); người dùng bấm duyệt thì app
// mới ghi bằng API thường, dưới quyền của chính người đó.
import 'package:flutter/material.dart';

import '../todo/model.dart';
import 'look.dart';
import 'model.dart';
import 'pickers.dart';
import 'rich_mentions.dart';
import 'store.dart';

class TwAiPanel extends StatefulWidget {
  const TwAiPanel({super.key, required this.store, required this.detail, required this.onChanged, this.onDraft, this.onAssignAgent, this.onClose, this.sheet = false});
  final TwStore store;
  final TwTaskDetail detail;
  /// Đã ghi gì đó (thêm việc con, đổi người làm…): trang chi tiết tải lại.
  final VoidCallback onChanged;
  /// Đưa bản cập nhật AI soạn vào ô bình luận.
  final void Function(List<TBlock>)? onDraft;
  final VoidCallback? onAssignAgent, onClose;
  final bool sheet;
  @override
  State<TwAiPanel> createState() => _TwAiPanelState();
}

class _TwAiPanelState extends State<TwAiPanel> {
  String? _action, _busy, _err;
  TwAiResult? _res;
  final _q = TextEditingController();

  TwStore get store => widget.store;
  TwTask get task => widget.detail.task;

  static const actions = [
    ('summarize', Icons.summarize_outlined, 'Tóm tắt bình luận'),
    ('breakdown', Icons.account_tree_outlined, 'Chia thành việc con'),
    ('update', Icons.edit_note_rounded, 'Soạn cập nhật tiến độ'),
    ('suggest', Icons.person_search_outlined, 'Gợi ý người làm & ngày'),
  ];

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run(String action, {String? question}) async {
    setState(() {
      _action = action;
      _busy = action;
      _err = null;
      _res = null;
    });
    try {
      final r = await store.api.ai(task.id, action, question: question);
      if (mounted) setState(() => _res = r);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _addSubtasks() async {
    final sel = _res!.subtasks.where((s) => s.selected).toList();
    if (sel.isEmpty) return;
    setState(() => _busy = 'apply');
    try {
      for (final s in sel) {
        await store.createTask(task.projectId, {
          'title': s.title,
          'parent_id': task.id,
          if (s.assignee != null) 'assignees': [s.assignee!.toJson()],
          if (s.start != null) 'start': dayStr(s.start!),
          if (s.due != null) 'due': dayStr(s.due!),
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã thêm ${sel.length} việc con')));
      setState(() => _res = null);
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _applySuggestion(TwAiSuggestion s) async {
    setState(() => _busy = 'apply');
    try {
      if (s.assignees.isNotEmpty) await store.setAssignees(task, {...task.assignees, ...s.assignees}.toList());
      if (s.start != null || s.due != null) {
        await store.updateTask(task, {if (s.start != null) 'start': dayStr(s.start!), if (s.due != null) 'due': dayStr(s.due!)});
      }
      setState(() => _res = null);
      widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _card(TwLook look, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: widget.sheet ? look.aiSoft : look.bg, borderRadius: BorderRadius.circular(10), border: widget.sheet ? null : Border.all(color: look.divider)),
        child: child,
      );

  Widget _result(TwLook look) {
    final r = _res!;
    final title = switch (_action) {
      'summarize' => 'Tóm tắt',
      'breakdown' => 'Đề xuất ${r.subtasks.length} việc con',
      'update' => 'Bản cập nhật tiến độ',
      'suggest' => 'Gợi ý',
      _ => 'Trả lời',
    };
    return _card(
      look,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (r.text != null) TwRichView(markdownToBlocks(r.text!), style: TextStyle(fontSize: 13.5, height: 1.5, color: look.text)),
        for (final s in r.subtasks)
          InkWell(
            key: ValueKey('ai-sub-${r.subtasks.indexOf(s)}'),
            onTap: () => setState(() => s.selected = !s.selected),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Icon(s.selected ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: s.selected ? look.ok : look.sub),
                const SizedBox(width: 8),
                Expanded(child: Text(s.title, style: const TextStyle(fontSize: 13))),
                if (s.assignee != null) TwAvatar.of(s.assignee!, size: 20, border: false),
                if (s.due != null) Padding(padding: const EdgeInsets.only(left: 6), child: Text(dShort(s.due!), style: TextStyle(fontSize: 11.5, color: look.sub))),
              ]),
            ),
          ),
        if (r.suggestion != null) ...[
          if (r.suggestion!.assignees.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Người làm:', style: TextStyle(fontSize: 13)),
                for (final a in r.suggestion!.assignees) Chip(visualDensity: VisualDensity.compact, avatar: TwAvatar.of(a, size: 20, border: false), label: Text(a.name)),
              ]),
            ),
          if (r.suggestion!.start != null || r.suggestion!.due != null)
            Text('Ngày: ${r.suggestion!.start == null ? '—' : dShort(r.suggestion!.start!)} → ${r.suggestion!.due == null ? '—' : dShort(r.suggestion!.due!)}', style: const TextStyle(fontSize: 13)),
          if (r.suggestion!.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.suggestion!.reason, style: TextStyle(fontSize: 12.5, color: look.sub))),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (r.subtasks.isNotEmpty)
            FilledButton(
              key: const ValueKey('ai-add-subtasks'),
              onPressed: _busy != null || !(store.fullOf(task.projectId)?.project.canEdit ?? false) ? null : _addSubtasks,
              child: Text(r.subtasks.where((s) => s.selected).length == r.subtasks.length ? 'Thêm cả ${r.subtasks.length}' : 'Thêm ${r.subtasks.where((s) => s.selected).length} việc con'),
            ),
          if (r.suggestion != null) FilledButton(key: const ValueKey('ai-apply'), onPressed: _busy != null ? null : () => _applySuggestion(r.suggestion!), child: const Text('Áp dụng')),
          if (_action == 'update' && r.text != null && widget.onDraft != null)
            FilledButton(
              key: const ValueKey('ai-to-comment'),
              onPressed: () {
                widget.onDraft!(markdownToBlocks(r.text!));
                if (widget.sheet) Navigator.maybePop(context);
              },
              child: const Text('Đưa vào bình luận'),
            ),
          OutlinedButton(onPressed: () => setState(() => _res = null), child: const Text('Bỏ')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = TwLook.of(context);
    final content = <Widget>[
      Row(children: [
        Icon(Icons.auto_awesome, color: look.ai, size: 20),
        const SizedBox(width: 8),
        const Text('AI hỗ trợ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const Spacer(),
        if (widget.onClose != null) IconButton(key: const ValueKey('ai-close'), visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 20), onPressed: widget.onClose),
      ]),
      const SizedBox(height: 10),
      if (widget.sheet)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (k, _, label) in actions)
            ChoiceChip(
              key: ValueKey('ai-$k'),
              label: Text(label.replaceAll(' bình luận', '').replaceAll(' tiến độ', '').replaceAll('thành ', '')),
              selected: _action == k,
              selectedColor: look.ai,
              labelStyle: TextStyle(color: _action == k ? Colors.white : look.ai, fontWeight: FontWeight.w600),
              backgroundColor: look.aiSoft,
              side: BorderSide.none,
              showCheckmark: false,
              onSelected: (_) => _run(k),
            ),
        ])
      else
        for (final (k, icon, label) in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Material(
              color: look.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9), side: BorderSide(color: look.divider)),
              child: InkWell(
                key: ValueKey('ai-$k'),
                borderRadius: BorderRadius.circular(9),
                onTap: _busy != null ? null : () => _run(k),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  child: Row(children: [
                    Icon(icon, size: 19, color: look.ai),
                    const SizedBox(width: 9),
                    Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (_busy == k) SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: look.ai)),
                  ]),
                ),
              ),
            ),
          ),
      if (!widget.sheet && widget.onAssignAgent != null)
        Material(
          color: look.bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9), side: BorderSide(color: look.divider)),
          child: InkWell(
            key: const ValueKey('ai-agent'),
            borderRadius: BorderRadius.circular(9),
            onTap: widget.onAssignAgent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              child: Row(children: [Icon(Icons.smart_toy_outlined, size: 19, color: look.ai), const SizedBox(width: 9), const Text('Giao cho agent làm', style: TextStyle(fontWeight: FontWeight.w600))]),
            ),
          ),
        ),
      const SizedBox(height: 10),
      if (_busy != null && _busy != 'apply' && widget.sheet) Center(child: Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: look.ai))),
      if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_err!, style: TextStyle(color: look.red))),
      if (_res != null) _result(look),
      if (widget.sheet && widget.onAssignAgent != null) ...[
        const SizedBox(height: 14),
        OutlinedButton.icon(key: const ValueKey('ai-agent'), onPressed: widget.onAssignAgent, icon: const Icon(Icons.smart_toy_outlined, size: 18), label: const Text('Giao cho agent')),
      ],
    ];
    final ask = Container(
      decoration: BoxDecoration(color: look.bg, border: Border.all(color: look.divider), borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.only(left: 12),
      child: Row(children: [
        Expanded(
          child: TextField(
            key: const ValueKey('ai-ask'),
            controller: _q,
            decoration: const InputDecoration(hintText: 'Hỏi AI về việc này…', border: InputBorder.none, isDense: true),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) _run('ask', question: v.trim());
            },
          ),
        ),
        IconButton(
          key: const ValueKey('ai-ask-send'),
          icon: Icon(Icons.send, color: look.ai, size: 20),
          onPressed: () {
            if (_q.text.trim().isNotEmpty) _run('ask', question: _q.text.trim());
          },
        ),
      ]),
    );
    final note = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('AI chỉ đọc và sửa những gì bạn được phép · đề xuất cần bấm duyệt', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: look.sub)),
    );
    if (widget.sheet) {
      return SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...content, const SizedBox(height: 10), ask, note]));
    }
    return Container(
      color: look.aiSoft,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content))),
        const SizedBox(height: 8),
        ask,
        note,
      ]),
    );
  }
}

/// Điện thoại: mở AI hỗ trợ dạng bảng trượt.
Future<void> showAiSheet(BuildContext context, TwStore store, TwTaskDetail d, {required VoidCallback onChanged, void Function(List<TBlock>)? onDraft, VoidCallback? onAssignAgent}) =>
    twSheet(context, builder: (c) => TwAiPanel(store: store, detail: d, onChanged: onChanged, onDraft: onDraft, onAssignAgent: onAssignAgent, sheet: true));
