import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../open_file.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen, kFlowOrange, kFlowRed;
import 'flow_logic.dart';
import 'flows_page.dart' show openFlowInstance, FlowProgressBar;
import 'flow_nav.dart';
import 'flows_stats.dart';
import 'package:flygo_chat/ui/app_route.dart';

/// "Tất cả luồng" (quản trị quy trình, hoặc vai trò flow_viewer như kế toán / giám đốc): tìm, lọc theo quy trình,
/// trạng thái, thời gian; xuất Excel đúng bộ lọc đang chọn.

Color _statusColor(String s, Color accent) => switch (s) {
      'done' => kFlowGreen,
      'rejected' || 'cancelled' || 'failed' => kFlowRed,
      'returned' => kFlowOrange,
      _ => accent,
    };

/// Lưu tệp tải về rồi mở: máy tính lưu vào Tải xuống và mở thư mục; điện thoại mở bằng ứng dụng / chia sẻ.
Future<String?> saveAndOpen(String name, Uint8List bytes) async {
  final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  final dir = desktop ? (await getDownloadsDirectory() ?? await getTemporaryDirectory()) : await getTemporaryDirectory();
  final f = File('${dir.path}${Platform.pathSeparator}$name');
  await f.writeAsBytes(bytes);
  if (desktop) {
    await revealInFileManager(f.path);
  } else {
    await openLocalFile(f.path, title: name);
  }
  return f.path;
}

class FlowsAllPage extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  const FlowsAllPage({super.key, required this.app, required this.api});
  @override
  State<FlowsAllPage> createState() => _FlowsAllPageState();
}

class _FlowsAllPageState extends State<FlowsAllPage> {
  final List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _flows = [];
  int _total = 0;
  bool _loading = false, _exporting = false;
  String? _err;
  String _q = '';
  String? _flow;
  String? _status;
  String _period = 'all';
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Map<String, String> get _filter {
    final now = DateTime.now();
    DateTime? from, to;
    switch (_period) {
      case 'month':
        from = DateTime(now.year, now.month);
      case 'last':
        from = DateTime(now.year, now.month - 1);
        to = DateTime(now.year, now.month);
      case 'range':
        from = _range?.start;
        to = _range?.end.add(const Duration(days: 1));
    }
    return {
      if (_q.trim().isNotEmpty) 'q': _q.trim(),
      'flow_id': ?_flow,
      'status': ?_status,
      if (from != null) 'from': '${from.millisecondsSinceEpoch}',
      if (to != null) 'to': '${to.millisecondsSinceEpoch}',
    };
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final r = await widget.api.allInstances({..._filter, 'limit': '50', 'offset': '${reset ? 0 : _rows.length}'});
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll([for (final x in (r['instances'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()]);
        _total = (r['total'] as num?)?.toInt() ?? _rows.length;
        _flows = [for (final x in (r['flows'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final m = ScaffoldMessenger.of(context);
    try {
      final bytes = await widget.api.exportXlsx(_filter);
      final path = await saveAndOpen('luong-${_flow ?? 'tat-ca'}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}.xlsx', bytes);
      m.showSnackBar(toast(Text(tr('Đã xuất Excel: {0}', [path ?? '']))));
    } catch (e) {
      m.showSnackBar(toast(Text(tr('Không xuất được: {0}', ['$e']))));
    }
    if (mounted) setState(() => _exporting = false);
  }

  String _name(String id) {
    final u = widget.app.users[id];
    return u == null ? id : (u.displayName.isEmpty ? u.username : u.displayName);
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(label), selected: on, onSelected: (_) => onTap()),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final statuses = [(null, tr('Tất cả')), ('running', tr('Đang xử lý')), ('done', tr('Hoàn tất')), ('returned', tr('Bị trả lại')), ('rejected', tr('Bị từ chối')), ('cancelled', tr('Đã hủy'))];
    return Scaffold(
      appBar: AppBar(
        leading: flowLeading(context),
        title: Text(tr('Tất cả tiến trình')),
        actions: [
          IconButton(
            tooltip: tr('Báo cáo vận hành'),
            onPressed: () => Navigator.of(context).push(AppPageRoute(builder: (_) => FlowsStatsPage(app: widget.app, api: widget.api))),
            icon: const Icon(Icons.insights_rounded),
          ),
          TextButton.icon(
            onPressed: _exporting || _rows.isEmpty ? null : _export,
            icon: _exporting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.grid_on_rounded),
            label: Text(tr('Xuất Excel')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm theo tiêu đề'), isDense: true, border: const OutlineInputBorder()),
                onChanged: (v) => _q = v,
                onSubmitted: (_) => _load(reset: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                initialValue: _flow ?? '',
                isExpanded: true,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('Mọi quy trình'))),
                  for (final f in _flows) DropdownMenuItem(value: '${f['id']}', child: Text('${f['icon'] ?? ''} ${f['name']}'.trim(), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  _flow = (v == null || v.isEmpty) ? null : v;
                  _load(reset: true);
                },
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
            for (final (s, label) in statuses)
              _chip(label, _status == s, () {
                _status = s;
                _load(reset: true);
              }),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
            for (final (p, label) in [('all', tr('Mọi lúc')), ('month', tr('Tháng này')), ('last', tr('Tháng trước'))])
              _chip(label, _period == p, () {
                _period = p;
                _load(reset: true);
              }),
            _chip(_period == 'range' && _range != null ? '${_date(_range!.start.millisecondsSinceEpoch)} – ${_date(_range!.end.millisecondsSinceEpoch)}' : tr('Chọn khoảng…'), _period == 'range', () async {
              final r = await showDateRangePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)), initialDateRange: _range);
              if (r == null) return;
              _range = r;
              _period = 'range';
              _load(reset: true);
            }),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(children: [
            Text(tr('{0} tiến trình', [_total]), style: TextStyle(color: pal.sub, fontWeight: FontWeight.w600)),
            if (_loading) ...[const SizedBox(width: 8), const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))],
          ]),
        ),
        Expanded(
          child: _err != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ListView.separated(
                    itemCount: _rows.length + (_rows.length < _total ? 1 : 0),
                    separatorBuilder: (_, _) => Divider(height: 1, color: pal.divider),
                    itemBuilder: (_, i) {
                      if (i >= _rows.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Center(child: TextButton(onPressed: _loading ? null : _load, child: Text(tr('Xem thêm ({0})', [_total - _rows.length])))),
                        );
                      }
                      final r = _rows[i];
                      final status = '${r['status']}';
                      final c = _statusColor(status, pal.accentText);
                      final waiting = [for (final w in (r['waiting_for'] as List? ?? const [])) _name('$w')];
                      return ListTile(
                        leading: Text('${r['icon'] ?? ''}'.isEmpty ? '📋' : '${r['icon']}', style: const TextStyle(fontSize: 24)),
                        title: Text('${r['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            [
                              '${r['flow_name']}',
                              _name('${r['requester']}'),
                              _date((r['created_at'] as num?)?.toInt() ?? 0),
                              if (waiting.isNotEmpty) tr('chờ {0}', [waiting.join(', ')]),
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: pal.sub),
                          ),
                          FlowProgressBar(progress: r['progress'], compact: true),
                        ]),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                          child: Text(flowStatusLabel(status), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        onTap: () => openFlowInstance(context, widget.app, '${r['id']}'),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }
}
