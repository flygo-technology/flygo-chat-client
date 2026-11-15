// Báo cáo: chia sẻ và cài đặt một báo cáo (tên, báo tin khi có bản mới, nhạy cảm, lệnh định kỳ, người xem / người sửa, xoá).
// Trả 'changed' khi có sửa, 'deleted' khi đã xoá, null khi không đổi gì.
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'api.dart';
import 'blocks.dart';

Future<String?> showReportSettings(BuildContext context, ReportsSource api, Json report) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Pal.of(context).bg,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
  builder: (c) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .8,
    maxChildSize: .95,
    builder: (c, scroll) => _Settings(api: api, report: report, scroll: scroll),
  ),
);

class _Settings extends StatefulWidget {
  const _Settings({required this.api, required this.report, required this.scroll});
  final ReportsSource api;
  final Json report;
  final ScrollController scroll;
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  late Json _r = Map.of(widget.report);
  List<Json> _members = const [];
  bool _changed = false, _busy = false;
  late final _title = TextEditingController(text: '${_r['title']}');
  final _q = TextEditingController();
  List<Json> _found = const [];
  Timer? _debounce;

  String get _id => '${_r['id']}';
  String get _role => '${_r['role']}';
  bool get _owner => _role == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.api.get('/api/reports/$_id');
      if (mounted) {
        setState(() {
          _r = Map<String, dynamic>.from(j['report'] as Map);
          _members = [for (final m in (j['members'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)];
        });
      }
    } catch (_) {}
  }

  Future<void> _guard(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
      _changed = true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _put(Json b) => _guard(() async {
    final j = await widget.api.put('/api/reports/$_id', b);
    setState(() => _r = Map<String, dynamic>.from(j['report'] as Map));
  });

  Future<void> _saveMembers(List<Json> list) => _guard(() async {
    final j = await widget.api.put('/api/reports/$_id/members', {
      'members': [
        for (final m in list) {'kind': m['kind'], 'ref': m['ref'], 'role': m['role']},
      ],
    });
    setState(() => _members = [for (final m in (j['members'] as List)) Map<String, dynamic>.from(m as Map)]);
  });

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().isEmpty) return setState(() => _found = const []);
      try {
        final j = await widget.api.get('/api/people', {'q': q.trim()});
        if (mounted) setState(() => _found = [for (final x in (j['people'] as List)) Map<String, dynamic>.from(x as Map)]);
      } catch (_) {}
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xoá báo cáo?'),
        content: Text('"${_r['title']}" và mọi bản sẽ bị xoá.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete('/api/reports/$_id');
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final schedule = _r['schedule'] as Map?;
    final sec = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.sub, letterSpacing: .3);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) Navigator.pop(context, _changed ? 'changed' : null);
      },
      child: ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Chia sẻ & cài đặt',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            enabled: _role != 'viewer',
            decoration: const InputDecoration(labelText: 'Tên báo cáo', border: OutlineInputBorder()),
            onSubmitted: (v) => v.trim().isEmpty ? null : _put({'title': v.trim()}),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _r['notify'] == true,
            onChanged: _role == 'viewer' ? null : (v) => _put({'notify': v}),
            title: const Text('Báo qua chat khi có bản mới'),
            subtitle: const Text('Bot "Báo cáo" nhắn riêng cho người xem'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _r['sensitive'] == true,
            onChanged: _owner ? (v) => _put({'sensitive': v}) : null,
            title: const Text('Báo cáo tài chính (nhạy cảm)'),
            subtitle: const Text('Không chia sẻ cho mọi người; tin báo không hiện số'),
          ),
          if (schedule != null) ...[
            const SizedBox(height: 8),
            Text('LỆNH ĐỊNH KỲ', style: sec),
            const SizedBox(height: 6),
            ReportCard(
              color: aiBg(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: aiColor(context)),
                      const SizedBox(width: 6),
                      Text(
                        '${schedule['when'] ?? ''}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: p.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${schedule['prompt'] ?? ''}', style: TextStyle(color: p.text, height: 1.4)),
                  const SizedBox(height: 6),
                  Text('Đổi lịch hoặc lệnh: nhắn trợ lý AI đã đặt lịch này.', style: TextStyle(fontSize: 12, color: p.sub)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text('NGƯỜI XEM', style: sec),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text('${_r['owner_name']}'),
            trailing: Text('Chủ', style: TextStyle(color: p.sub)),
          ),
          for (final m in _members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                m['kind'] == 'all'
                    ? Icons.public
                    : m['kind'] == 'dept'
                    ? Icons.apartment_outlined
                    : m['kind'] == 'role'
                    ? Icons.badge_outlined
                    : Icons.person_outline,
              ),
              title: Text('${m['name']}'),
              trailing: _owner
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<String>(
                          value: '${m['role']}',
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(value: 'viewer', child: Text('Xem')),
                            DropdownMenuItem(value: 'editor', child: Text('Sửa')),
                          ],
                          onChanged: (v) => _saveMembers([
                            for (final x in _members) x == m ? {...x, 'role': v} : x,
                          ]),
                        ),
                        IconButton(
                          onPressed: () => _saveMembers([
                            for (final x in _members)
                              if (x != m) x,
                          ]),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    )
                  : Text(m['role'] == 'editor' ? 'Sửa' : 'Xem', style: TextStyle(color: p.sub)),
            ),
          if (_owner) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _q,
              onChanged: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_add_alt),
                hintText: 'Thêm người xem…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            for (final x in _found.where((x) => !_members.any((m) => m['kind'] == 'user' && m['ref'] == x['id'])))
              ListTile(
                dense: true,
                leading: const Icon(Icons.add_circle_outline),
                title: Text('${x['name']}'),
                subtitle: Text('@${x['username']}'),
                onTap: () {
                  _q.clear();
                  setState(() => _found = const []);
                  _saveMembers([
                    ..._members,
                    {'kind': 'user', 'ref': x['id'], 'role': 'viewer'},
                  ]);
                },
              ),
            if (_r['sensitive'] != true && !_members.any((m) => m['kind'] == 'all'))
              TextButton.icon(
                onPressed: () => _saveMembers([
                  ..._members,
                  {'kind': 'all', 'ref': '*', 'role': 'viewer'},
                ]),
                icon: const Icon(Icons.public),
                label: const Text('Cho mọi người trong công ty xem'),
              ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(foregroundColor: statusColors(context, 'crit').fg),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Xoá báo cáo'),
            ),
          ],
        ],
      ),
    );
  }
}
