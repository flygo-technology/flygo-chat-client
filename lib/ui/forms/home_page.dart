// Biểu mẫu (vn.flygo.forms): trang chủ — tạo biểu mẫu mới (trống / từ mẫu), danh sách biểu mẫu của tôi và được chia sẻ.
// Mở link /f/<mã> (QR, link trong chat) thì vào thẳng trang điền; /e/<id> vào trình soạn.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart' show isDesktop;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_shell.dart';
import '../app_route.dart';
import '../theme.dart';
import 'api.dart';
import 'editor_page.dart';
import 'fill_page.dart';
import 'model.dart';
import 'widgets.dart';

Future<void> openForms(BuildContext context, MiniApp app, {String? path}) async {
  final state = context.read<AppState>();
  final host = AppHost.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id = await FlygoId.current(state.token);
    if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
    final api = FormsApi(base: app.baseUrl, id: id);
    final fill = path == null ? null : RegExp(r'/f/([A-Za-z0-9_-]{6,16})').firstMatch(path)?.group(1);
    final edit = path == null ? null : RegExp(r'^/e/([A-Za-z0-9_-]{6,40})').firstMatch(path)?.group(1);
    if (fill != null) {
      await host.open(key: app.id, title: app.name, deep: true, builder: (_) => FormFillPage(api: api, token: fill));
    } else if (edit != null) {
      await host.open(key: app.id, title: app.name, deep: true, builder: (_) => FormEditorPage(api: api, formId: edit));
    } else {
      await host.open(key: app.id, title: app.name, builder: (_) => FormsHome(api: api, title: app.name));
    }
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

class FormsHome extends StatefulWidget {
  const FormsHome({super.key, required this.api, this.title = 'Biểu mẫu'});
  final FormsApi api;
  final String title;
  @override
  State<FormsHome> createState() => _FormsHomeState();
}

const _tplIcons = <String, IconData>{
  'add': Icons.add, 'event_available': Icons.event_available_outlined, 'sentiment_satisfied_alt': Icons.sentiment_satisfied_alt_outlined,
  'beach_access': Icons.beach_access_outlined, 'forum': Icons.forum_outlined,
};

class _FormsHomeState extends State<FormsHome> {
  List<Json>? _forms;
  List<Json> _templates = const [];
  Object? _error;
  String _scope = 'all';
  String _q = '';
  bool _searching = false, _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([widget.api.get('/api/forms', {'scope': _scope, if (_q.isNotEmpty) 'q': _q}), if (_templates.isEmpty) widget.api.get('/api/me')]);
      setState(() {
        _forms = [for (final f in (r[0]['forms'] as List)) Map<String, dynamic>.from(f as Map)];
        if (r.length > 1) _templates = [for (final t in (r[1]['templates'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _create(String template) async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final j = await widget.api.post('/api/forms', {'template': template});
      if (!mounted) return;
      final id = '${(j['form'] as Map)['id']}';
      await Navigator.of(context).push(AppPageRoute(builder: (_) => FormEditorPage(api: widget.api, formId: id, initial: Map<String, dynamic>.from(j['form'] as Map))));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _open(Json f) async {
    await Navigator.of(context).push(AppPageRoute(builder: (_) => FormEditorPage(api: widget.api, formId: '${f['id']}')));
    _load();
  }

  Future<void> _menu(Json f, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case 'copy':
          await widget.api.post('/api/forms/${f['id']}/copy');
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Xoá biểu mẫu?'),
              content: Text('"${f['title']}" và toàn bộ câu trả lời sẽ bị xoá.'),
              actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xoá'))],
            ),
          );
          if (ok != true) return;
          await widget.api.delete('/api/forms/${f['id']}');
        case 'fill':
          if (!mounted) return;
          await Navigator.of(context).push(AppPageRoute(builder: (_) => FormFillPage(api: widget.api, token: '${f['token']}')));
      }
      _load();
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final wide = MediaQuery.sizeOf(context).width > 760;
    final canPop = showsBack(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        automaticallyImplyLeading: canPop,
        titleSpacing: canPop ? 0 : 16,
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Tìm biểu mẫu', border: InputBorder.none),
                onChanged: (v) {
                  _q = v;
                  _load();
                },
              )
            : Row(children: [FormsIcon(color: p.accent), const SizedBox(width: 10), Text(widget.title)]),
        actions: [
          IconButton(
            tooltip: 'Tìm',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching && _q.isNotEmpty) {
                _q = '';
                _load();
              }
            }),
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
          IconButton(tooltip: 'Tải lại', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 16, vertical: 16),
          children: [
            Text('Tạo biểu mẫu mới', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 10),
            SizedBox(
              height: wide ? 150 : 128,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final t in _templates.isEmpty ? [{'id': 'blank', 'name': 'Trống', 'icon': 'add', 'color': '#1E7BFF'}] : _templates)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _create('${t['id']}'),
                      child: SizedBox(
                        width: wide ? 160 : 118,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(color: tintOf(colorOf('${t['color']}'), isDark(context)), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.divider)),
                              child: Center(child: _creating ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_tplIcons['${t['icon']}'] ?? Icons.description_outlined, size: 38, color: colorOf('${t['color']}'))),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('${t['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.text)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 22),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
              Padding(padding: const EdgeInsets.only(right: 10), child: Text('Biểu mẫu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text))),
              for (final s in const [('all', 'Tất cả'), ('mine', 'Của tôi'), ('shared', 'Được chia sẻ')])
                Pill(s.$2, bg: _scope == s.$1 ? p.chipSelBg : null, fg: _scope == s.$1 ? p.chipSelFg : null, onTap: () {
                  setState(() => _scope = s.$1);
                  _load();
                }),
            ]),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(24), child: Text('$_error', textAlign: TextAlign.center, style: TextStyle(color: p.sub)))
            else if (_forms == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_forms!.isEmpty)
              Padding(padding: const EdgeInsets.all(40), child: Text(_q.isEmpty ? 'Chưa có biểu mẫu nào. Chọn một mẫu ở trên để bắt đầu.' : 'Không tìm thấy', textAlign: TextAlign.center, style: TextStyle(color: p.sub)))
            else
              LayoutBuilder(builder: (c, k) {
                final cols = (k.maxWidth / 290).floor().clamp(isDesktop || wide ? 2 : 2, 5);
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: wide ? 1.25 : .84,
                  children: [for (final f in _forms!) _tile(f)],
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _tile(Json f) {
    final p = Pal.of(context);
    final color = colorOf('${f['theme']}');
    final status = f['status'] == 'draft' ? 'Nháp' : (f['accepting'] == true ? 'Đang nhận' : 'Đã đóng');
    final access = f['status'] == 'draft' ? ('Nháp', Icons.edit_note) : f['access'] == 'public' ? ('Công khai', Icons.public) : ('Nội bộ', Icons.lock_outline);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(f),
      child: Container(
        decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.divider)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Container(
              color: tintOf(color, isDark(context)),
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 6, width: 60, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 10),
                for (final w in const [.9, .6, .75])
                  Container(margin: const EdgeInsets.only(bottom: 7), height: 6, width: 120 * w, decoration: BoxDecoration(color: p.sub.withValues(alpha: .25), borderRadius: BorderRadius.circular(3))),
                const Spacer(),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Pill(access.$1, icon: access.$2, bg: p.bg.withValues(alpha: .75)),
                  if (f['role'] != 'owner') Pill(f['role'] == 'editor' ? 'Cùng sửa' : 'Xem câu trả lời', bg: p.bg.withValues(alpha: .75)),
                  if (f['has_flows'] == true) Pill('Quy trình', icon: Icons.account_tree_outlined, bg: p.bg.withValues(alpha: .75)),
                ]),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${f['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.circle, size: 8, color: f['accepting'] == true ? const Color(0xFF2E9D57) : p.sub),
                    const SizedBox(width: 5),
                    Expanded(child: Text('$status · ${f['responses']} câu trả lời', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.sub))),
                  ]),
                ]),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: p.sub),
                onSelected: (a) => _menu(f, a),
                itemBuilder: (_) => [
                  if (f['status'] != 'draft') const PopupMenuItem(value: 'fill', child: Text('Mở trang điền')),
                  const PopupMenuItem(value: 'copy', child: Text('Tạo bản sao')),
                  if (f['role'] == 'owner') const PopupMenuItem(value: 'delete', child: Text('Xoá')),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
