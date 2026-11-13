import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen, kFlowOrange, kFlowRed;
import 'flow_nav.dart';
import 'flows_page.dart' show openFlowInstance;

/// Báo cáo vận hành: mỗi quy trình bao nhiêu luồng, xong / đang chạy, thời gian xử lý trung bình; bước chờ lâu nhất;
/// ai đang giữ nhiều việc; việc chờ lâu nhất. Dùng để tìm điểm nghẽn.
class FlowsStatsPage extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final Map<String, dynamic>? debugData;
  const FlowsStatsPage({super.key, required this.app, required this.api, this.debugData});
  @override
  State<FlowsStatsPage> createState() => _FlowsStatsPageState();
}

class _FlowsStatsPageState extends State<FlowsStatsPage> {
  int _days = 30;
  Map<String, dynamic>? _d;
  String? _err;

  @override
  void initState() {
    super.initState();
    if (widget.debugData != null) {
      _d = widget.debugData;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final d = await widget.api.stats(_days);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  String _name(String id) {
    final u = widget.app.users[id];
    return u == null ? id : (u.displayName.isNotEmpty ? u.displayName : u.username);
  }

  /// "2 ngày 4 giờ", "35 phút".
  String _dur(num? ms) {
    if (ms == null) return '—';
    final m = (ms / 60000).round();
    if (m >= 1440) return tr('{0} ngày {1} giờ', [m ~/ 1440, (m % 1440) ~/ 60]);
    if (m >= 60) return tr('{0} giờ {1} phút', [m ~/ 60, m % 60]);
    return tr('{0} phút', [m < 1 ? 1 : m]);
  }

  Widget _section(Pal pal, String title, String sub, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: pal.text)),
          Text(sub, style: TextStyle(color: pal.sub, fontSize: 12.5)),
          const SizedBox(height: 8),
          if (children.isEmpty) Text(tr('Chưa có dữ liệu'), style: TextStyle(color: pal.sub)) else ...children,
        ]),
      );

  Widget _card(Pal pal, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.divider)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final d = _d;
    List<Map> list(String k) => [for (final x in (d?[k] as List? ?? const [])) if (x is Map) x];
    final now = DateTime.now().millisecondsSinceEpoch;
    final maxStep = list('steps').fold<double>(1, (m, s) => ((s['avg_ms'] as num?)?.toDouble() ?? 0) > m ? (s['avg_ms'] as num).toDouble() : m);
    return Scaffold(
      appBar: AppBar(
        leading: flowLeading(context),
        title: Text(tr('Báo cáo vận hành')),
        actions: [
          PopupMenuButton<int>(
            tooltip: tr('Khoảng thời gian'),
            initialValue: _days,
            onSelected: (v) {
              setState(() => _days = v);
              _load();
            },
            itemBuilder: (_) => [for (final x in [7, 30, 90, 365]) PopupMenuItem(value: x, child: Text(tr('{0} ngày gần đây', [x])))],
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Text(tr('{0} ngày', [_days])), const Icon(Icons.arrow_drop_down_rounded)])),
          ),
        ],
      ),
      body: _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!)))
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    _section(pal, tr('Theo quy trình'), tr('Số tiến trình tạo trong khoảng, đã xong, đang chạy và thời gian xử lý trung bình tới khi xong'), [
                      for (final f in list('flows'))
                        _card(
                          pal,
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${f['flow_name']}', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 14, runSpacing: 4, children: [
                              Text(tr('{0} tiến trình', [f['started']]), style: TextStyle(color: pal.text)),
                              Text(tr('{0} xong', [f['done']]), style: const TextStyle(color: kFlowGreen)),
                              Text(tr('{0} đang chạy', [f['running']]), style: const TextStyle(color: kFlowOrange)),
                              if ((f['stopped'] as num? ?? 0) > 0) Text(tr('{0} dừng / từ chối', [f['stopped']]), style: const TextStyle(color: kFlowRed)),
                              Text(tr('TB {0}', [_dur(f['avg_ms'] as num?)]), style: TextStyle(color: pal.sub)),
                            ]),
                          ]),
                        ),
                    ]),
                    _section(pal, tr('Bước chờ lâu nhất'), tr('Thời gian trung bình từ lúc giao tới lúc quyết / nộp'), [
                      for (final s in list('steps'))
                        _card(
                          pal,
                          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text('${s['step_name']}', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                            Text('${s['flow_name']} · ${tr('{0} lần', [s['count']])} · ${tr('lâu nhất {0}', [_dur(s['max_ms'] as num?)])}', style: TextStyle(color: pal.sub, fontSize: 12.5)),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(value: (((s['avg_ms'] as num?) ?? 0) / maxStep).clamp(0.02, 1.0), minHeight: 6, color: kFlowOrange, backgroundColor: pal.divider),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(_dur(s['avg_ms'] as num?), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                            ]),
                          ]),
                        ),
                    ]),
                    _section(pal, tr('Đang giữ nhiều tiến trình'), tr('Số tiến trình đang chờ mỗi người và tiến trình cũ nhất'), [
                      for (final b in list('busy'))
                        _card(
                          pal,
                          Row(children: [
                            Expanded(child: Text(_name('${b['user']}'), style: TextStyle(fontWeight: FontWeight.w600, color: pal.text))),
                            Text(tr('{0} tiến trình', [b['open']]), style: const TextStyle(fontWeight: FontWeight.w700, color: kFlowOrange)),
                            const SizedBox(width: 10),
                            Text(tr('cũ nhất {0}', [_dur(now - ((b['oldest'] as num?) ?? now))]), style: TextStyle(color: pal.sub, fontSize: 12.5)),
                          ]),
                        ),
                    ]),
                    _section(pal, tr('Tiến trình chờ lâu nhất'), tr('Chạm để mở tiến trình'), [
                      for (final s in list('stuck'))
                        InkWell(
                          onTap: () => openFlowInstance(context, widget.app, '${s['instance_id']}'),
                          child: _card(
                            pal,
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${s['title']}', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                              Text('${s['flow_name']} › ${s['step_name']} · ${_name('${s['user']}')}', style: TextStyle(color: pal.sub, fontSize: 12.5)),
                              Text(tr('Chờ {0}', [_dur(now - ((s['since'] as num?) ?? now))]), style: const TextStyle(color: kFlowRed, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                    ]),
                  ]),
                ),
    );
  }
}
