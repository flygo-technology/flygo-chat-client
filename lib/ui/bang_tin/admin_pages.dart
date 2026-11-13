// Bảng tin, quản trị: chuyên mục (thêm / sửa / xoá) và thống kê đã xem / đã xác nhận của các bài gần đây.
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../app_route.dart';
import '../common.dart';
import '../theme.dart';
import 'api.dart';
import 'bang_tin_page.dart';
import 'post_page.dart';

const _palette = ['#E8833A', '#E5484D', '#2E9E5B', '#3B82F6', '#8B5CF6', '#0EA5A4', '#D946EF', '#64748B'];

class BangTinCategoriesPage extends StatefulWidget {
  const BangTinCategoriesPage({super.key, required this.api});
  final BangTinApi api;

  @override
  State<BangTinCategoriesPage> createState() => _BangTinCategoriesPageState();
}

class _BangTinCategoriesPageState extends State<BangTinCategoriesPage> {
  List<Map<String, dynamic>> _cats = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.api.get('/api/categories');
      if (mounted) setState(() => (_cats = [for (final c in (j['categories'] as List? ?? const [])) if (c is Map) Map<String, dynamic>.from(c)], _loading = false));
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
      }
    }
  }

  /// Mã chuyên mục từ tên: bỏ dấu, chữ thường, nối bằng "-".
  static String _slug(String name) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final s = StringBuffer();
    for (final ch in name.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      s.write(i >= 0 ? to[i] : ch);
    }
    final slug = s.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'cm-${DateTime.now().millisecondsSinceEpoch % 100000}' : (slug.length > 40 ? slug.substring(0, 40) : slug);
  }

  Future<void> _edit([Map<String, dynamic>? c]) async {
    final name = TextEditingController(text: '${c?['name'] ?? ''}');
    var color = '${c?['color'] ?? _palette[_cats.length % _palette.length]}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(c == null ? tr('Thêm chuyên mục') : tr('Sửa chuyên mục')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, maxLength: 60, decoration: InputDecoration(labelText: tr('Tên chuyên mục'))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in _palette)
                GestureDetector(
                  onTap: () => set(() => color = p),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: hexColor(p),
                    child: color == p ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                  ),
                ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );
    final n = name.text.trim();
    name.dispose();
    if (ok != true || n.isEmpty) return;
    try {
      final id = c?['id'] as String? ?? _slug(n);
      await widget.api.put('/api/categories/$id', {'name': n, 'color': color, 'sort': c?['sort'] ?? _cats.length});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Xoá chuyên mục "{0}"?', ['${c['name']}'])),
        content: Text(tr('Các bài trong chuyên mục này vẫn còn, chỉ không thuộc chuyên mục nào.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Xoá'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete('/api/categories/${c['id']}');
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: Text(tr('Chuyên mục'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm chuyên mục'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cats.isEmpty
              ? Center(child: Text(tr('Chưa có chuyên mục nào'), style: TextStyle(color: pal.sub)))
              : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                  for (final c in _cats)
                    ListTile(
                      leading: CircleAvatar(radius: 8, backgroundColor: hexColor(c['color']) ?? pal.sub),
                      title: Text('${c['name']}'),
                      onTap: () => _edit(c),
                      trailing: IconButton(tooltip: tr('Xoá'), icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(c)),
                    ),
                ]),
    );
  }
}

class BangTinStatsPage extends StatefulWidget {
  const BangTinStatsPage({super.key, required this.api, required this.me});
  final BangTinApi api;
  final BangTinMe me;

  @override
  State<BangTinStatsPage> createState() => _BangTinStatsPageState();
}

class _BangTinStatsPageState extends State<BangTinStatsPage> {
  Map<String, dynamic>? _s;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.get('/api/stats');
      if (mounted) setState(() => (_s = s, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final s = _s;
    final posts = [for (final p in (s?['posts'] as List? ?? const [])) if (p is Map) Map<String, dynamic>.from(p)];
    Widget kpi(String label, String value) => Expanded(
          child: Card(
            elevation: 0,
            color: pal.surface,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: pal.text)),
                Text(label, style: TextStyle(color: pal.sub, fontSize: 12.5)),
              ]),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: Text(tr('Thống kê'))),
      body: s == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: TextStyle(color: pal.sub)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                Row(children: [kpi(tr('Tổng số bài'), '${s['total']}'), kpi(tr('30 ngày qua'), '${s['since_30d']}')]),
                const SizedBox(height: 8),
                for (final p in posts) _row(pal, p),
              ]),
            ),
    );
  }

  Widget _row(Pal pal, Map<String, dynamic> p) {
    final targets = (p['targets'] as num? ?? 0).toInt();
    double ratio(Object? v) => targets == 0 ? 0 : ((v as num? ?? 0) / targets).clamp(0, 1).toDouble();
    Widget bar(String label, Object? v, Color c) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(width: 92, child: Text(label, style: TextStyle(color: pal.sub, fontSize: 12.5))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: ratio(v), minHeight: 8, color: c, backgroundColor: pal.surface2),
              ),
            ),
            SizedBox(width: 64, child: Text('$v/$targets', textAlign: TextAlign.right, style: TextStyle(color: pal.text, fontSize: 12.5))),
          ]),
        );
    return Card(
      elevation: 0,
      color: pal.surface,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(AppPageRoute(builder: (_) => BangTinPostPage(api: widget.api, me: widget.me, postId: '${p['id']}'))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
            Text(
              '${(p['author'] as Map?)?['name']} · ${listTime((p['created_at'] as num).toInt())} · ${tr('{0} bình luận', ['${p['comments']}'])}',
              style: TextStyle(color: pal.sub, fontSize: 12.5),
            ),
            bar(tr('Đã xem'), p['read'], pal.accent),
            if (p['require_ack'] == true) bar(tr('Đã xác nhận'), p['acked'], const Color(0xFFE8833A)),
          ]),
        ),
      ),
    );
  }
}
