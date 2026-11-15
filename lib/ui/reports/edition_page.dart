// Báo cáo: xem một bản (điện thoại trước tiên). Tóm tắt AI, KPI thành cặp, biểu đồ, bảng, cảnh báo; chạm vào khối để xem nguồn.
// Vuốt / nút ‹ › để sang bản trước / sau; bình luận và "Hỏi AI" ở cuối. Máy tính: cột các bản bên trái.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart' show isDesktop;
import '../markdown_view.dart';
import '../shell_highlight.dart' show kMonoFont;
import '../theme.dart';
import 'api.dart';
import 'ask_ai.dart';
import 'blocks.dart';
import 'settings_sheet.dart';

class EditionPage extends StatefulWidget {
  const EditionPage({super.key, required this.api, required this.reportId, this.editionId, this.embedded = false, this.onChanged});
  final ReportsSource api;
  final String reportId;

  /// null: bản mới nhất.
  final String? editionId;

  /// Nằm trong khung chia đôi của máy tính (không có nút quay lại).
  final bool embedded;
  final VoidCallback? onChanged;
  @override
  State<EditionPage> createState() => _EditionPageState();
}

class _EditionPageState extends State<EditionPage> {
  Json? _e, _report;
  List<Json> _history = const [];
  List<Json> _comments = const [];
  Object? _error;
  String? _editionId;
  ReportsLive? _live;
  StreamSubscription<Json>? _liveSub;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _editionId = widget.editionId;
    _load();
    _connect();
  }

  @override
  void didUpdateWidget(EditionPage old) {
    super.didUpdateWidget(old);
    if (old.reportId != widget.reportId || old.editionId != widget.editionId) {
      _editionId = widget.editionId;
      _e = null;
      _load();
      _live?.subscribe(reports: [widget.reportId]);
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _live?.close();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      _live = await widget.api.live(reports: [widget.reportId]);
      _liveSub = _live?.events.listen((m) {
        if (!mounted || m['report'] != widget.reportId) return;
        if (m['type'] == 'comment' && m['edition'] == _e?['id']) _loadComments();
        if (m['type'] == 'edition') {
          // Bản mới tới khi đang xem bản mới nhất: chuyển sang bản mới. Bản đang xem bị sửa: tải lại.
          if ((_editionId == null && m['deleted'] != true) || m['edition'] == _e?['id']) _load();
          _loadHistory();
        }
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        _editionId == null ? widget.api.get('/api/reports/${widget.reportId}/latest') : widget.api.get('/api/editions/$_editionId'),
        widget.api.get('/api/reports/${widget.reportId}'),
      ]);
      if (!mounted) return;
      setState(() {
        _e = r[0]['edition'] == null ? null : Map<String, dynamic>.from(r[0]['edition'] as Map);
        _report = Map<String, dynamic>.from(r[1]['report'] as Map);
        _error = null;
      });
      _loadComments();
      if (_history.isEmpty) _loadHistory();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final j = await widget.api.get('/api/reports/${widget.reportId}/editions', {'limit': '60'});
      if (mounted) setState(() => _history = [for (final e in (j['editions'] as List)) Map<String, dynamic>.from(e as Map)]);
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    final id = _e?['id'];
    if (id == null) return;
    try {
      final j = await widget.api.get('/api/editions/$id/comments');
      if (mounted) setState(() => _comments = [for (final c in (j['comments'] as List)) Map<String, dynamic>.from(c as Map)]);
    } catch (_) {}
  }

  void _go(String? id) {
    if (id == null) return;
    setState(() {
      _editionId = id;
      _comments = const [];
    });
    _load();
  }

  Future<void> _sendComment() async {
    final t = _comment.text.trim();
    if (t.isEmpty || _sending || _e == null) return;
    setState(() => _sending = true);
    try {
      await widget.api.post('/api/editions/${_e!['id']}/comments', {'text': t});
      _comment.clear();
      await _loadComments();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await widget.api.bytes('/api/editions/${_e!['id']}/export');
      final name = '${'${_e!['title']}'.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]+'), ' ').trim()}.xlsx';
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

  Future<void> _menu(String a) async {
    switch (a) {
      case 'export':
        await _export();
      case 'settings':
        if (_report == null) return;
        final changed = await showReportSettings(context, widget.api, _report!);
        if (changed == 'deleted') {
          widget.onChanged?.call();
          if (mounted && !widget.embedded) Navigator.of(context).pop();
        } else if (changed != null) {
          _load();
        }
      case 'history':
        await _historySheet();
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Xoá bản này?'),
            content: Text('"${_e!['title']}" sẽ bị xoá. Các bản khác giữ nguyên.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xoá')),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await widget.api.delete('/api/editions/${_e!['id']}');
          _history = const [];
          _go(null);
          setState(() => _editionId = null);
          _load();
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
        }
    }
  }

  Future<void> _historySheet() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Pal.of(context).bg,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [_HistoryList(items: _history, current: _e?['id'] as String?, onPick: (id) => Navigator.pop(c, id))],
        ),
      ),
    );
    _go(id);
  }

  void _ask() {
    if (_e == null) return;
    showAskAi(
      context,
      title: 'Hỏi AI về báo cáo này',
      hint: 'Vd: Khoản chi lớn hôm qua là gì? So với tuần trước thế nào?',
      context_:
          'Báo cáo "${_e!['report_title']}", bản #${_e!['seq']} (${_e!['period']}). Dùng report_ask_context với edition_id=${_e!['id']} '
          'để lấy số liệu và nguồn, trả lời từ đó trước; cần tra thêm thì gọi công cụ nguồn và ghi rõ nguồn.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1100 && !widget.embedded;
    final e = _e;
    final role = '${e?['role'] ?? _report?['role'] ?? 'viewer'}';
    final body = _error != null && e == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.sub),
              ),
            ),
          )
        : _report == null
        ? const Center(child: CircularProgressIndicator())
        : e == null
        ? _empty(p)
        : _content(context, e);
    return Scaffold(
      backgroundColor: p.surface,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        titleSpacing: widget.embedded ? 16 : 0,
        title: Text(
          '${_report?['title'] ?? 'Báo cáo'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        actions: [
          IconButton(
            tooltip: 'Hỏi AI',
            onPressed: e == null ? null : _ask,
            icon: Icon(Icons.auto_awesome, color: aiColor(context)),
          ),
          IconButton(tooltip: 'Các bản', onPressed: _historySheet, icon: const Icon(Icons.history_rounded)),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              if (e != null)
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(leading: Icon(Icons.table_view_outlined), title: Text('Xuất Excel'), contentPadding: EdgeInsets.zero),
                ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(leading: Icon(Icons.tune_rounded), title: Text('Chia sẻ & cài đặt'), contentPadding: EdgeInsets.zero),
              ),
              if (e != null && role != 'viewer')
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Xoá bản này'), contentPadding: EdgeInsets.zero),
                ),
            ],
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                SizedBox(
                  width: 240,
                  child: Material(
                    color: p.bg,
                    child: ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                          child: Text(
                            'CÁC BẢN',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.sub, letterSpacing: .4),
                          ),
                        ),
                        _HistoryList(items: _history, current: e?['id'] as String?, onPick: _go),
                      ],
                    ),
                  ),
                ),
                VerticalDivider(width: 1, color: p.divider),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }

  Widget _empty(Pal p) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_chart_outlined_rounded, size: 56, color: p.sub),
          const SizedBox(height: 12),
          Text(
            'Báo cáo chưa có bản nào',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Nhờ AI lấy số liệu và đẩy bản đầu tiên vào đây.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.sub),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => showAskAi(
              context,
              title: 'Nhờ AI lập báo cáo',
              initial: 'Lập báo cáo "${_report?['title']}" ngay bây giờ.',
              context_: 'Đẩy bản mới vào báo cáo có report_id=${widget.reportId} bằng report_publish (xem report_templates để chọn khối).',
            ),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Nhờ AI lập báo cáo'),
          ),
        ],
      ),
    ),
  );

  Widget _content(BuildContext context, Json e) {
    final p = Pal.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final blocks = [for (final b in (e['blocks'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)];
    final prevKpi = Map<String, dynamic>.from(((e['prev'] as Map?)?['kpi'] as Map?) ?? const {});
    final checks = Map<String, dynamic>.from((e['checks'] as Map?) ?? const {});
    final bare = (checks['bare_numbers'] as List?)?.length ?? 0;
    final maxW = 980.0;
    final children = <Widget>[];
    children.add(_header(context, e, checks, bare));
    if ('${e['summary'] ?? ''}'.trim().isNotEmpty) {
      children.add(_gap(10));
      children.add(
        ReportCard(
          color: aiBg(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 15, color: aiColor(context)),
                  const SizedBox(width: 6),
                  Text(
                    e['act'] != null ? 'AI tóm tắt' : 'Tóm tắt',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: aiColor(context)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              MarkdownView(
                text: '${e['summary']}',
                style: TextStyle(fontSize: 15, height: 1.5, color: p.text),
              ),
            ],
          ),
        ),
      );
    }
    // Gom khối: KPI liền nhau thành lưới; tiêu đề mục khi đổi section.
    String? section;
    final kpiCols = w >= 760 ? 4 : 2;
    for (var i = 0; i < blocks.length;) {
      final b = blocks[i];
      final sec = b['section'] as String?;
      if (sec != null && sec != section) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 2),
            child: Text(
              sec.toUpperCase(),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.sub, letterSpacing: .4),
            ),
          ),
        );
      }
      section = sec ?? section;
      children.add(_gap(10));
      if (b['type'] == 'kpi') {
        final group = <Json>[];
        while (i < blocks.length && blocks[i]['type'] == 'kpi' && (blocks[i]['section'] as String? ?? section) == section) {
          group.add(blocks[i]);
          i++;
        }
        children.add(_grid(group.length < kpiCols && group.length >= 2 ? group.length : kpiCols, [for (final k in group) KpiTile(block: k, prev: prevKpi[k['id']] as num?, onTap: () => showSourceSheet(context, k))]));
      } else {
        children.add(BlockView(block: b, onSource: () => showSourceSheet(context, b)));
        i++;
      }
    }
    children.add(_gap(18));
    children.add(_sources(context, blocks));
    children.add(_gap(14));
    children.add(_commentsBox(context));
    children.add(_gap(28));
    return RefreshIndicator(
      onRefresh: _load,
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 600) _go((e['prev'] as Map?)?['id'] as String?);
          if (v < -600) _go(e['next'] as String?);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gap(double h) => SizedBox(height: h);

  Widget _grid(int cols, List<Widget> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += cols) {
      final row = items.sublist(i, (i + cols).clamp(0, items.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var k = 0; k < cols; k++) ...[if (k > 0) const SizedBox(width: 8), Expanded(child: k < row.length ? row[k] : const SizedBox())],
            ],
          ),
        ),
      );
      if (i + cols < items.length) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }

  Widget _header(BuildContext context, Json e, Json checks, int bare) {
    final p = Pal.of(context);
    final numeric = checks['numeric'] as int? ?? 0, withTool = checks['with_tool'] as int? ?? 0;
    final prev = e['prev'] as Map?;
    final next = e['next'] as String?;
    Widget chip(String t, Color fg, Color bg, IconData ic) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            t,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
    final good = statusColors(context, 'good'), warn = statusColors(context, 'warn');
    return ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e['period']?.toString().isNotEmpty == true ? e['period'] : e['title']}',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: p.text),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (e['as_of'] != null) 'Số liệu đến ${fmtAsOf('${e['as_of']}')}',
                        '${e['act'] != null ? 'AI phát hành' : 'Đăng'} ${fmtMs(e['created_at'] as int).split(' ').first}',
                        'bản #${e['seq']}',
                        if ((e['viewers'] as int? ?? 0) > 0) '${e['viewers']} người đã xem',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12.5, color: p.sub),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Bản trước',
                visualDensity: VisualDensity.compact,
                onPressed: prev == null ? null : () => _go(prev['id'] as String),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Bản sau',
                visualDensity: VisualDensity.compact,
                onPressed: next == null ? null : () => _go(next),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (e['act'] != null) chip('AI tổng hợp', aiColor(context), aiBg(context), Icons.auto_awesome),
              if (numeric > 0)
                chip(
                  '$withTool/$numeric khối có nguồn',
                  withTool == numeric ? good.fg : warn.fg,
                  withTool == numeric ? good.bg : warn.bg,
                  Icons.verified_outlined,
                ),
              if (bare > 0) chip('Có số chưa có nguồn trong chữ', warn.fg, warn.bg, Icons.warning_amber_rounded),
              if (e['sensitive'] == true) chip('Tài chính', p.sub, p.surface, Icons.lock_outline_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sources(BuildContext context, List<Json> blocks) {
    final p = Pal.of(context);
    final withSrc = [
      for (final b in blocks)
        if (b['source'] is Map) b,
    ];
    if (withSrc.isEmpty) return const SizedBox();
    final tools = <String, List<String>>{};
    for (final b in withSrc) {
      final s = b['source'] as Map;
      tools.putIfAbsent('${s['tool'] ?? s['note']}', () => []).add('${b['title'] ?? b['id']}');
    }
    return ReportCard(
      color: p.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nguồn số liệu',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.sub),
          ),
          const SizedBox(height: 6),
          for (final t in tools.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_outlined, size: 14, color: p.accentText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: t.key,
                            style: TextStyle(fontFamily: kMonoFont, fontSize: 12, color: p.text),
                          ),
                          TextSpan(
                            text: '  ·  ${t.value.join(', ')}',
                            style: TextStyle(fontSize: 12, color: p.sub),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _commentsBox(BuildContext context) {
    final p = Pal.of(context);
    return ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bình luận${_comments.isEmpty ? '' : ' · ${_comments.length}'}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
          ),
          for (final c in _comments)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${c['author_name']}',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text),
                      ),
                      if (c['by_ai'] == true)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.auto_awesome, size: 13, color: aiColor(context)),
                        ),
                      const SizedBox(width: 6),
                      Text(fmtMs(c['created_at'] as int), style: TextStyle(fontSize: 12, color: p.sub)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${c['text']}', style: TextStyle(fontSize: 14, color: p.text, height: 1.4)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _comment,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendComment(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Viết bình luận…',
                    filled: true,
                    fillColor: p.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _sendComment,
                icon: Icon(Icons.send_rounded, color: p.accentText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.items, required this.current, required this.onPick});
  final List<Json> items;
  final String? current;
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Chưa có bản nào', style: TextStyle(color: p.sub)),
      );
    }
    return Column(
      children: [
        for (final e in items)
          ListTile(
            dense: true,
            selected: e['id'] == current,
            selectedTileColor: kReportColor.withValues(alpha: .1),
            selectedColor: kReportColor,
            title: Text('${e['period']?.toString().isNotEmpty == true ? e['period'] : e['title']}', style: const TextStyle(fontSize: 14)),
            subtitle: Text('${fmtMs(e['created_at'] as int)}${e['act'] != null ? ' · AI' : ''}', style: TextStyle(fontSize: 12, color: p.sub)),
            trailing: Text('#${e['seq']}', style: TextStyle(fontSize: 12, color: p.sub)),
            onTap: () => onPick('${e['id']}'),
          ),
      ],
    );
  }
}
