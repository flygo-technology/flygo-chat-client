// Biểu mẫu: tab Câu trả lời — bật / tắt nhận câu trả lời, tóm tắt từng câu (biểu đồ), từng câu trả lời, lọc theo ngày,
// xuất Excel / CSV (lưu hoặc chia sẻ tệp), xoá câu trả lời. Tự cập nhật khi có câu trả lời mới (realtime).
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart' show isDesktop;
import '../theme.dart';
import 'api.dart';
import 'model.dart';
import 'widgets.dart';

class ResponsesTab extends StatefulWidget {
  const ResponsesTab({super.key, required this.api, required this.form, required this.tick, required this.onForm});
  final FormsApi api;
  final Json form;
  final int tick;
  final ValueChanged<Json> onForm;
  @override
  State<ResponsesTab> createState() => _ResponsesTabState();
}

const _palette = [Color(0xFF0F8B8D), Color(0xFFE4A11B), Color(0xFF5B6CC4), Color(0xFFD9534F), Color(0xFF2E7D32), Color(0xFF8E9AAF), Color(0xFFC2185B), Color(0xFF6D4C41)];

class _ResponsesTabState extends State<ResponsesTab> {
  String _view = 'summary';
  Json? _summary;
  List<Json> _responses = [];
  int _total = 0, _index = 0;
  int? _since;
  Object? _error;
  bool _busy = false;

  String get _id => '${widget.form['id']}';
  Json get _schema => Map<String, dynamic>.from(widget.form['schema'] as Map);
  bool get _canEdit => widget.form['role'] != 'viewer';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ResponsesTab old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) _load();
  }

  Future<void> _load() async {
    try {
      final q = {if (_since != null) 'since': '$_since'};
      final r = await Future.wait([widget.api.get('/api/forms/$_id/summary', q), widget.api.get('/api/forms/$_id/responses', {...q, 'limit': '500', 'order': 'asc'})]);
      if (!mounted) return;
      setState(() {
        _summary = r[0];
        _responses = [for (final x in (r[1]['responses'] as List)) Map<String, dynamic>.from(x as Map)];
        _total = r[1]['total'] as int? ?? _responses.length;
        if (_index >= _responses.length) _index = max(0, _responses.length - 1);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggleAccepting(bool on) async {
    setState(() => _busy = true);
    try {
      final j = await widget.api.post('/api/forms/$_id/${on ? 'publish' : 'close'}');
      widget.onForm(Map<String, dynamic>.from(j['form'] as Map));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(String format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await widget.api.bytes('/api/forms/$_id/export', {'format': format});
      final name = '${'${widget.form['title']}'.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]+'), ' ').trim()}.$format';
      if (isDesktop) {
        final saved = await FilePicker.saveFile(fileName: name, bytes: bytes);
        if (saved != null) messenger.showSnackBar(toast(Text('Đã lưu $name')));
      } else {
        final f = File('${(await getTemporaryDirectory()).path}/$name');
        await f.writeAsBytes(bytes);
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], title: name));
      }
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  Future<void> _delete(Json r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xoá câu trả lời này?'),
        content: const Text('Không khôi phục được.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xoá'))],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete('/api/responses/${r['id']}');
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = Map<String, dynamic>.from(widget.form['settings'] as Map? ?? const {});
    final wide = MediaQuery.sizeOf(context).width > 760;
    final closeAt = s['close_at'] as int?;
    final help = widget.form['status'] == 'draft'
        ? 'Biểu mẫu chưa gửi đi: bấm Gửi để mở nhận câu trả lời'
        : [
            if (closeAt != null) 'Tự đóng lúc ${fmtTime(closeAt)}',
            if (s['max_responses'] != null) '$_total / ${s['max_responses']} câu trả lời',
            if (widget.form['accepting'] != true && widget.form['closed_reason'] != null) '${widget.form['closed_reason']}',
          ].join(' · ');
    final header = FCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('$_total câu trả lời', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500))),
          if (wide) ...[
            OutlinedButton.icon(onPressed: _total == 0 ? null : () => _export('xlsx'), icon: const Icon(Icons.table_view_outlined, size: 18), label: const Text('Xuất Excel')),
            const SizedBox(width: 8),
          ],
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: p.sub),
            onSelected: (a) => a == 'reload' ? _load() : _export(a),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'xlsx', child: Text('Xuất Excel (.xlsx)')),
              const PopupMenuItem(value: 'csv', child: Text('Xuất CSV')),
              const PopupMenuItem(value: 'reload', child: Text('Tải lại')),
            ],
          ),
        ]),
        if (_canEdit)
          SwitchRow(
            label: 'Đang nhận câu trả lời',
            help: help.isEmpty ? null : help,
            value: widget.form['accepting'] == true,
            onChanged: _busy || widget.form['status'] == 'draft' ? null : _toggleAccepting,
          )
        else if (help.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(help, style: TextStyle(color: p.sub, fontSize: 12.5))),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in const [('summary', 'Tóm tắt'), ('question', 'Theo câu hỏi'), ('each', 'Từng câu trả lời')])
            Pill(v.$2, bg: _view == v.$1 ? p.chipSelBg : null, fg: _view == v.$1 ? p.chipSelFg : null, onTap: () => setState(() => _view = v.$1)),
          PopupMenuButton<int?>(
            tooltip: 'Lọc theo thời gian',
            onSelected: (d) {
              setState(() => _since = d == null ? null : DateTime.now().subtract(Duration(days: d)).millisecondsSinceEpoch);
              _load();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: null, child: Text('Mọi lúc')), PopupMenuItem(value: 1, child: Text('24 giờ qua')), PopupMenuItem(value: 7, child: Text('7 ngày qua')), PopupMenuItem(value: 30, child: Text('30 ngày qua'))],
            child: Pill(_since == null ? 'Mọi lúc' : 'Từ ${fmtTime(_since!).substring(6)}', icon: Icons.filter_list),
          ),
        ]),
      ]),
    );
    Widget body;
    if (_error != null) {
      body = FCard(child: Text('$_error', style: TextStyle(color: p.sub)));
    } else if (_summary == null) {
      body = const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    } else if (_total == 0) {
      body = FCard(child: Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('Chưa có câu trả lời', style: TextStyle(color: p.sub)))));
    } else {
      body = switch (_view) { 'each' => _each(), 'question' => _byQuestion(), _ => _summaryView(wide) };
    }
    return RefreshIndicator(onRefresh: _load, child: FormBackdrop(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, body])));
  }

  Widget _summaryView(bool wide) {
    final p = Pal.of(context);
    final qs = [for (final q in (_summary!['questions'] as List)) Map<String, dynamic>.from(q as Map)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final q in qs)
        FCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${q['title']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            Text(_sub(q), style: TextStyle(color: p.sub, fontSize: 12.5)),
            const SizedBox(height: 12),
            _chart(q, wide),
          ]),
        ),
    ]);
  }

  String _sub(Json q) {
    final n = q['answered'];
    final avg = q['avg'] as num?;
    if (q['type'] == 'scale' && avg != null) return '$n câu trả lời · trung bình ${avg.toStringAsFixed(1).replaceAll('.', ',')}';
    if (q['type'] == 'number' && avg != null) return '$n câu trả lời · trung bình ${avg.toStringAsFixed(2).replaceAll('.', ',')} · tổng ${q['sum']}';
    if (q['type'] == 'checkbox') return '$n câu trả lời · chọn nhiều';
    if (q['type'] == 'file') return '$n câu trả lời · ${q['files']} tệp';
    return '$n câu trả lời';
  }

  Widget _chart(Json q, bool wide) {
    final p = Pal.of(context);
    final color = FormTheme.of(context);
    final counts = [for (final c in (q['counts'] as List? ?? const [])) (('${(c as Map)['label']}'), c['n'] as int)];
    switch (q['type']) {
      case 'scale':
        return SizedBox(height: wide ? 170 : 140, child: CustomPaint(size: Size.infinite, painter: _Histogram(counts, color, p.sub, p.divider, DefaultTextStyle.of(context).style)));
      case 'choice' || 'dropdown':
        final items = [...counts, if ((q['other'] as int? ?? 0) > 0) ('Khác', q['other'] as int)];
        final total = items.fold(0, (a, b) => a + b.$2);
        return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 24, runSpacing: 12, children: [
          SizedBox(width: wide ? 140 : 110, height: wide ? 140 : 110, child: CustomPaint(painter: _Donut([for (final i in items) i.$2], cardColor(context)))),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: _palette[i % _palette.length], borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Flexible(child: Text(items[i].$1, style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 10),
                    Text('${items[i].$2} · ${total == 0 ? 0 : (100 * items[i].$2 / total).round()}%', style: TextStyle(color: p.sub, fontSize: 12.5)),
                  ]),
                ),
            ]),
          ),
        ]);
      case 'checkbox' || 'date':
        final items = [...counts, if ((q['other'] as int? ?? 0) > 0) ('Khác', q['other'] as int)];
        final total = max(1, q['answered'] as int? ?? 1);
        return Column(children: [for (final i in items) _bar(i.$1, i.$2, total, color, wide)]);
      case 'grid_choice' || 'grid_checkbox':
        final grid = [for (final g in (q['grid'] as List? ?? const [])) Map<String, dynamic>.from(g as Map)];
        if (grid.isEmpty) return const SizedBox.shrink();
        final cols = [for (final c in (grid.first['counts'] as List)) '${(c as Map)['label']}'];
        final mx = grid.expand((g) => (g['counts'] as List).map((c) => (c as Map)['n'] as int)).fold(1, max);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 40,
            columns: [const DataColumn(label: Text('')), for (final c in cols) DataColumn(label: Text(c), numeric: true)],
            rows: [
              for (final g in grid)
                DataRow(cells: [
                  DataCell(Text('${g['row']}', style: const TextStyle(fontWeight: FontWeight.w500))),
                  for (final c in (g['counts'] as List))
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: color.withValues(alpha: .1 + .6 * ((c as Map)['n'] as int) / mx), borderRadius: BorderRadius.circular(4)),
                      child: Text('${c['n']}'),
                    )),
                ]),
            ],
          ),
        );
      case 'number':
        return Text('Nhỏ nhất ${q['min']} · Lớn nhất ${q['max']}', style: TextStyle(color: p.sub));
      case 'file':
        return Text('Xem tệp ở "Từng câu trả lời" hoặc xuất Excel', style: TextStyle(color: p.sub));
      default:
        final samples = [for (final s in (q['samples'] as List? ?? const [])) '$s'];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final s in samples.take(8))
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6)),
              child: Text(s, style: const TextStyle(fontSize: 13.5)),
            ),
          if (samples.length > 8) TextButton(onPressed: () => setState(() => _view = 'question'), child: Text('Xem tất cả ${q['answered']}')),
        ]);
    }
  }

  Widget _bar(String label, int n, int total, Color color, bool wide) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: wide ? 170 : 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Container(
            height: 22,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(4)),
            child: FractionallySizedBox(widthFactor: (n / total).clamp(0.0, 1.0), child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)))),
          ),
        ),
        SizedBox(width: 74, child: Text('$n (${(100 * n / total).round()}%)', textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, color: p.sub))),
      ]),
    );
  }

  Widget _byQuestion() {
    final p = Pal.of(context);
    final qs = questionsOf(_schema);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final q in qs)
        FCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${q['title']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            subtitle: Text('${_responses.where((r) => (r['answers'] as Map)[q['key']] != null).length} câu trả lời', style: TextStyle(color: p.sub, fontSize: 12.5)),
            children: [
              for (final r in _responses.reversed)
                if ((r['answers'] as Map)[q['key']] != null)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(answerText(q, (r['answers'] as Map)[q['key']])),
                    subtitle: Text('${r['name'] ?? (r['public'] == true ? 'Khách' : 'Ẩn danh')} · ${fmtTime(r['created_at'] as int)}'),
                    onTap: () => setState(() {
                      _index = _responses.indexOf(r);
                      _view = 'each';
                    }),
                  ),
            ],
          ),
        ),
    ]);
  }

  Widget _each() {
    final p = Pal.of(context);
    final r = _responses[_index.clamp(0, _responses.length - 1)];
    final a = Map<String, dynamic>.from(r['answers'] as Map);
    final known = {for (final q in questionsOf(_schema)) q['key']};
    final color = FormTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FCard(
        pad: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: _index > 0 ? () => setState(() => _index--) : null, icon: const Icon(Icons.chevron_left)),
            Text('${_index + 1} / ${_responses.length}', style: const TextStyle(fontWeight: FontWeight.w600)),
            IconButton(onPressed: _index < _responses.length - 1 ? () => setState(() => _index++) : null, icon: const Icon(Icons.chevron_right)),
            const Spacer(),
            if (_canEdit) IconButton(tooltip: 'Xoá câu trả lời', onPressed: () => _delete(r), icon: Icon(Icons.delete_outline, color: p.sub)),
          ]),
          Row(children: [
            CircleAvatar(radius: 18, backgroundColor: p.surface2, child: Icon(r['public'] == true ? Icons.public : Icons.person_outline, size: 18, color: p.sub)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['public'] == true ? 'Khách (link công khai)' : '${r['name'] ?? 'Ẩn danh'}${r['email'] == null ? '' : ' · ${r['email']}'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${fmtTime(r['created_at'] as int)}${r['duration_ms'] == null ? '' : ' · ${_dur(r['duration_ms'] as int)}'}', style: TextStyle(color: p.sub, fontSize: 12.5)),
              ]),
            ),
          ]),
          if ((r['links'] as List? ?? const []).isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final l in (r['links'] as List))
                Pill('${(l as Map)['kind'] == 'flow' ? 'Luồng' : 'Công việc'}: ${l['title'] ?? l['id']}', icon: l['kind'] == 'flow' ? Icons.account_tree_outlined : Icons.check_box_outlined, bg: tintOf(color, isDark(context)), fg: color),
            ]),
          ],
        ]),
      ),
      for (final q in questionsOf(_schema))
        FCard(
          pad: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${q['title']}', style: TextStyle(color: p.sub, fontSize: 12.5)),
            const SizedBox(height: 4),
            if (q['type'] == 'file' && a[q['key']] is List)
              Wrap(spacing: 8, runSpacing: 8, children: [for (final id in (a[q['key']] as List)) _fileChip('$id')])
            else
              Text(a[q['key']] == null ? '—' : answerText(q, a[q['key']]), style: TextStyle(fontSize: 15, color: a[q['key']] == null ? p.sub : p.text)),
          ]),
        ),
      for (final k in a.keys.where((k) => !known.contains(k)))
        FCard(pad: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: Text('$k (câu đã xoá): ${a[k]}', style: TextStyle(color: p.sub))),
    ]);
  }

  String _dur(int ms) => ms < 60000 ? '${ms ~/ 1000} giây' : '${ms ~/ 60000} phút ${(ms % 60000) ~/ 1000} giây';

  Widget _fileChip(String id) => ActionChip(
        avatar: const Icon(Icons.attach_file, size: 16),
        label: const Text('Mở tệp'),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            final bytes = await widget.api.bytes('/api/files/$id', {'download': '1'});
            final dir = await getTemporaryDirectory();
            final f = File('${dir.path}/forms-$id');
            await f.writeAsBytes(bytes);
            await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
          } catch (e) {
            messenger.showSnackBar(toast(Text('$e')));
          }
        },
      );
}

class _Histogram extends CustomPainter {
  _Histogram(this.items, this.color, this.text, this.line, this.base);
  final List<(String, int)> items;
  final Color color, text, line;
  final TextStyle base;
  @override
  void paint(Canvas canvas, Size s) {
    if (items.isEmpty) return;
    final mx = items.map((e) => e.$2).fold(1, max);
    final w = s.width / items.length, h = s.height - 40;
    for (var i = 0; i < items.length; i++) {
      final bh = h * items[i].$2 / mx;
      final r = Rect.fromLTWH(i * w + w * .18, 18 + h - bh, w * .64, bh);
      canvas.drawRRect(RRect.fromRectAndCorners(r, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), Paint()..color = color.withValues(alpha: .45 + .55 * (i + 1) / items.length));
      _txt(canvas, '${items[i].$2}', Offset(i * w + w / 2, 18 + h - bh - 16), text, 11.5);
      _txt(canvas, items[i].$1, Offset(i * w + w / 2, s.height - 18), text, 12);
    }
    canvas.drawLine(Offset(0, 18 + h), Offset(s.width, 18 + h), Paint()..color = line);
  }

  void _txt(Canvas c, String t, Offset center, Color color, double size) {
    final tp = TextPainter(text: TextSpan(text: t, style: base.copyWith(color: color, fontSize: size)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, center - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _Histogram o) => o.items != items || o.color != color;
}

class _Donut extends CustomPainter {
  _Donut(this.parts, this.hole);
  final List<int> parts;
  final Color hole;
  @override
  void paint(Canvas canvas, Size s) {
    final total = parts.fold(0, (a, b) => a + b);
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.shortestSide / 2);
    if (total == 0) {
      canvas.drawCircle(r.center, r.width / 2, Paint()..color = Colors.grey.withValues(alpha: .2));
    } else {
      var a = -pi / 2;
      for (var i = 0; i < parts.length; i++) {
        final sw = 2 * pi * parts[i] / total;
        canvas.drawArc(r, a, sw, true, Paint()..color = _palette[i % _palette.length]);
        a += sw;
      }
    }
    canvas.drawCircle(r.center, r.width * .3, Paint()..color = hole);
  }

  @override
  bool shouldRepaint(covariant _Donut o) => o.parts != parts;
}
