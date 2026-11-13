// Bảng tin: bình chọn trong bài (Sếp). Mỗi lựa chọn là một hàng có thanh phần trăm; bấm để chọn / đổi / rút phiếu
// (chọn nhiều thì bấm để bật tắt từng lựa chọn). Không ẩn danh thì xem được ai đã chọn gì.
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../common.dart';
import '../theme.dart';
import 'api.dart';
import 'bang_tin_page.dart' show bangTinTime;

class PollView extends StatefulWidget {
  const PollView({super.key, required this.api, required this.postId, required this.poll, required this.onChanged});
  final BangTinApi api;
  final String postId;
  final Map<String, dynamic> poll;

  /// Bình chọn mới sau khi bỏ phiếu (để thẻ / trang bài cập nhật theo).
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<PollView> createState() => _PollViewState();
}

class _PollViewState extends State<PollView> {
  bool _busy = false;

  Future<void> _vote(String optionId) async {
    final p = widget.poll;
    if (_busy || p['closed'] == true) return;
    final mine = {for (final x in (p['my_votes'] as List? ?? const [])) '$x'};
    final Set<String> next;
    if (p['multi'] == true) {
      next = {...mine};
      next.contains(optionId) ? next.remove(optionId) : next.add(optionId);
    } else {
      // Chọn một: bấm lại lựa chọn đang chọn thì rút phiếu.
      next = mine.contains(optionId) ? {} : {optionId};
    }
    setState(() => _busy = true);
    try {
      final r = await widget.api.post('/api/posts/${widget.postId}/vote', {'options': next.toList()});
      widget.onChanged(Map<String, dynamic>.from(r['poll'] as Map));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _voters() async {
    final pal = Pal.of(context);
    try {
      final j = await widget.api.get('/api/posts/${widget.postId}/poll/voters');
      if (!mounted) return;
      final opts = [for (final o in (j['options'] as List? ?? const [])) if (o is Map) o];
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: pal.surface,
        builder: (c) => FractionallySizedBox(
          heightFactor: .75,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(children: [
                Expanded(child: Text(tr('Ai đã chọn'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: pal.text))),
                IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(c)),
              ]),
            ),
            Expanded(
              child: ListView(children: [
                for (final o in opts) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text('${o['text']} (${(o['voters'] as List).length})', style: TextStyle(fontWeight: FontWeight.w600, color: pal.sub)),
                  ),
                  for (final v in (o['voters'] as List))
                    ListTile(
                      dense: true,
                      leading: Avatar(userId: '${(v as Map)['id']}', name: '${v['name']}', size: 30, status: false),
                      title: Text('${v['name']}'),
                    ),
                ],
              ]),
            ),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final p = widget.poll;
    final opts = [for (final o in (p['options'] as List? ?? const [])) if (o is Map) o];
    final mine = {for (final x in (p['my_votes'] as List? ?? const [])) '$x'};
    final total = opts.fold<int>(0, (s, o) => s + ((o['votes'] as num?)?.toInt() ?? 0));
    final voted = mine.isNotEmpty;
    final closed = p['closed'] == true;
    final multi = p['multi'] == true;
    final closes = (p['closes_at'] as num?)?.toInt();
    final question = '${p['question'] ?? ''}'.trim();
    final sub = TextStyle(color: pal.sub, fontSize: 12.5);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.poll_rounded, size: 18, color: pal.accentText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(question.isEmpty ? tr('Bình chọn') : question, style: TextStyle(fontWeight: FontWeight.w700, color: pal.text, fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 8),
        for (final o in opts)
          _OptionRow(
            text: '${o['text']}',
            votes: (o['votes'] as num?)?.toInt() ?? 0,
            total: total,
            selected: mine.contains('${o['id']}'),
            multi: multi,
            // Chưa chọn và còn hạn: chưa hiện kết quả để không lái ý kiến; chọn rồi / hết hạn thì hiện.
            showResult: voted || closed,
            onTap: closed || _busy ? null : () => _vote('${o['id']}'),
          ),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tr('{0} người bình chọn', ['${p['voters'] ?? 0}']), style: sub),
          if (multi) Text('· ${tr('Chọn nhiều')}', style: sub),
          if (p['anonymous'] == true) Text('· ${tr('Ẩn danh')}', style: sub),
          if (closed)
            Text('· ${tr('Đã kết thúc')}', style: sub.copyWith(color: const Color(0xFFE5484D)))
          else if (closes != null)
            Text('· ${tr('Kết thúc {0}', [bangTinTime(closes)])}', style: sub),
          if (p['anonymous'] != true && (p['voters'] as num? ?? 0) > 0)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: _voters,
              child: Text(tr('Xem ai đã chọn')),
            ),
        ]),
      ]),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.text, required this.votes, required this.total, required this.selected, required this.multi, required this.showResult, this.onTap});
  final String text;
  final int votes, total;
  final bool selected, multi, showResult;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final ratio = total == 0 ? 0.0 : votes / total;
    final icon = multi
        ? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
        : (selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: pal.surface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            if (showResult)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio,
                  child: ColoredBox(color: (selected ? pal.accent : pal.sub).withValues(alpha: selected ? .22 : .12)),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? pal.accent : pal.divider),
              ),
              child: Row(children: [
                Icon(icon, size: 20, color: selected ? pal.accent : pal.sub),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: TextStyle(color: pal.text, fontWeight: selected ? FontWeight.w600 : FontWeight.w500))),
                if (showResult) Text('${(ratio * 100).round()}% · $votes', style: TextStyle(color: pal.sub, fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
