import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen;
import 'flow_editor.dart';
import 'flow_nav.dart';

/// Trang "Quản lý quy trình" (nút cài đặt, chỉ quản trị quy trình / quản trị hệ thống): mọi quy trình nhóm theo
/// danh mục, bật / tắt, mở trình soạn, tạo quy trình mới.
class FlowsAdminPage extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  const FlowsAdminPage({super.key, required this.app, required this.api});
  @override
  State<FlowsAdminPage> createState() => _FlowsAdminPageState();
}

class _FlowsAdminPageState extends State<FlowsAdminPage> {
  List<Map<String, dynamic>>? _defs;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.adminDefs();
      if (mounted) {
        setState(() {
          _defs = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: flowLeading(context), title: Text(tr('Quản lý quy trình')), actions: [
          IconButton(tooltip: tr('Tải lại'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ]),
        body: _err != null
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, textAlign: TextAlign.center)))
            : _defs == null
                ? const Center(child: CircularProgressIndicator())
                : FlowsAdminTab(app: widget.app, api: widget.api, defs: _defs!, reload: _load),
      );
}

class FlowsAdminTab extends StatelessWidget {
  final AppState app;
  final FlowsApi api;
  final List<Map<String, dynamic>> defs;
  final Future<void> Function() reload;
  const FlowsAdminTab({super.key, required this.app, required this.api, required this.defs, required this.reload});

  /// Tạo quy trình: trống hoặc từ mẫu có sẵn.
  Future<void> create(BuildContext context) => _create(context);

  Future<void> _create(BuildContext context) async {
    final pal = Pal.of(context);
    List<Map<String, dynamic>> tpl = const [];
    try {
      tpl = await api.templates();
    } catch (_) {}
    if (!context.mounted) return;
    final pick = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (s) => FractionallySizedBox(
        heightFactor: 0.8,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [
          Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(tr('Tạo quy trình'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text))),
          ListTile(
            leading: const Icon(Icons.note_add_outlined, size: 28),
            title: Text(tr('Quy trình trống')),
            subtitle: Text(tr('Tự soạn từ đầu')),
            onTap: () => Navigator.pop(s, 'blank'),
          ),
          if (tpl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(tr('TỪ MẪU CÓ SẴN'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: pal.sub)),
            ),
          for (final t in tpl)
            ListTile(
              leading: Text('${t['icon'] ?? '📋'}', style: const TextStyle(fontSize: 26)),
              title: Text('${t['name']}'),
              subtitle: Text([
                '${t['category'] ?? ''}',
                tr('{0} bước', [((t['nodes'] as List?)?.length ?? 2) - 2]),
                if (t['trigger'] != null) tr('tự chạy theo lịch'),
              ].where((x) => x.isNotEmpty).join(' · ')),
              onTap: () => Navigator.pop(s, t),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(tr('Mẹo: có thể nhắn trợ lý AI "soạn quy trình ... cho công ty" (trợ lý dùng công cụ Flows).'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
          ),
        ]),
      ),
    );
    if (pick == null || !context.mounted) return;
    await openFlowEditor(context, app, api, template: pick is Map<String, dynamic> ? pick : null);
    await reload();
  }

  Future<void> _open(BuildContext context, String? id) async {
    await openFlowEditor(context, app, api, flowId: id);
    await reload();
  }

  Future<void> _toggle(BuildContext context, Map<String, dynamic> d, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.setActive('${d['id']}', on);
      messenger.showSnackBar(toast(Text(on ? tr('Đã bật: mọi người tạo được tiến trình') : tr('Đã tắt: không tạo tiến trình mới, tiến trình đang chạy vẫn chạy tiếp'))));
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    // Nhóm theo danh mục (chưa phân loại để cuối), trong nhóm theo tên.
    String cat(Map d) => '${d['category'] ?? ''}';
    final defs = [...this.defs]..sort((a, b) {
        final ca = cat(a), cb = cat(b);
        if (ca != cb) return ca.isEmpty ? 1 : (cb.isEmpty ? -1 : ca.compareTo(cb));
        return '${a['name']}'.compareTo('${b['name']}');
      });
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        if (defs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr('Chưa có quy trình nào. Bấm "Tạo quy trình" hoặc nhờ trợ lý AI soạn giúp.'), textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
          ),
        for (final (i, d) in defs.indexed) ...[
          if (i == 0 || '${defs[i - 1]['category'] ?? ''}' != '${d['category'] ?? ''}')
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text('${d['category'] ?? ''}'.isEmpty ? tr('KHÁC') : '${d['category']}'.toUpperCase(),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: pal.sub)),
            ),
          Card(
            elevation: 0,
            color: pal.surface,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: pal.divider)),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              leading: Text('${d['icon'] ?? ''}'.isEmpty ? '📋' : '${d['icon']}', style: const TextStyle(fontSize: 28)),
              title: Text('${d['name'] ?? d['id']}', style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
              subtitle: Text(
                [
                  tr('Bản {0}', [d['version']]),
                  tr('{0} bước', [((d['steps'] as num?)?.toInt() ?? 2) - 2]),
                  if (d['active'] == true) tr('Đang bật') else tr('Đang tắt'),
                ].join(' · '),
                style: TextStyle(color: d['active'] == true ? kFlowGreen : pal.sub),
              ),
              trailing: Switch(value: d['active'] == true, onChanged: (v) => _toggle(context, d, v)),
              onTap: () => _open(context, '${d['id']}'),
            ),
          ),
        ],
      ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(heroTag: 'new-flow', onPressed: () => _create(context), icon: const Icon(Icons.add_rounded), label: Text(tr('Tạo quy trình'))),
      ),
    ]);
  }
}
