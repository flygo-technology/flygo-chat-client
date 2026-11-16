// Tab "Khách" của Danh bạ: danh sách khách hàng / nhà cung cấp / đối tác, tìm, lọc, thêm, nhập file.
// Điện thoại: một cột, bấm vào liên hệ mở trang chi tiết. Máy tính (rộng): bộ lọc bên trái, danh sách, chi tiết bên phải.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../flows/flows_org.dart' show pickUsers;
import '../theme.dart';
import 'api.dart';
import 'contact_edit.dart';
import 'contact_page.dart';
import 'import_page.dart';
import 'look.dart';

class ContactsView extends StatefulWidget {
  const ContactsView({super.key, required this.api, this.openId, this.bottomPadding = 0});
  final ContactsApi api;
  /// Mở thẳng một liên hệ (bấm tin của bot, link).
  final String? openId;
  final double bottomPadding;
  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  ContactsApi get api => widget.api;
  Map<String, dynamic> _me = const {};
  Map<String, dynamic> _counts = const {};
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  String _filter = 'all';
  String _q = '';
  bool _loading = true;
  String? _error;
  String? _selected; // máy tính: liên hệ đang xem ở cột phải
  Timer? _debounce;
  int _reqNo = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _me = await api.me();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    await _reload();
    if (widget.openId != null && mounted) _open(widget.openId!);
  }

  Future<void> _reload() async {
    final no = ++_reqNo;
    setState(() => _loading = true);
    try {
      final f = _filter;
      final res = await api.list(
        q: _q,
        view: f.startsWith('type:') || f == 'dupes' ? 'all' : f,
        type: f.startsWith('type:') ? f.substring(5) : null,
      );
      final counts = await api.get('/api/counts');
      if (!mounted || no != _reqNo) return;
      setState(() {
        _rows = [for (final c in res['contacts'] as List) Map<String, dynamic>.from(c as Map)];
        _total = (res['total'] as num?)?.toInt() ?? _rows.length;
        _counts = counts;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && no == _reqNo) setState(() { _loading = false; _error = '$e'; });
    }
  }

  void _search(String v) {
    _q = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= 900;
  bool get _admin => _me['admin'] == true;
  bool get _manager => _me['manager'] == true;

  Future<void> _open(String id) async {
    if (_wide) {
      setState(() => _selected = id);
      return;
    }
    await Navigator.of(context).push(AppPageRoute(builder: (_) => ContactPage(api: api, id: id, me: _me)));
    if (mounted) _reload();
  }

  Future<void> _add(String kind) async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(AppPageRoute(builder: (_) => ContactEditPage(api: api, me: _me, kind: kind)));
    if (c == null || !mounted) return;
    await _reload();
    _open('${c['id']}');
  }

  Future<void> _addMenu() async {
    final pal = Pal.of(context);
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: pal.surface,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.apartment_rounded), title: Text(tr('Thêm công ty')), onTap: () => Navigator.pop(s, 'company')),
          ListTile(leading: const Icon(Icons.person_add_alt_rounded), title: Text(tr('Thêm người')), subtitle: Text(tr('Người liên hệ hoặc khách lẻ')), onTap: () => Navigator.pop(s, 'person')),
          ListTile(leading: const Icon(Icons.upload_file_rounded), title: Text(tr('Nhập từ file')), subtitle: Text(tr('Excel, CSV, vCard (danh bạ điện thoại xuất ra)')), onTap: () => Navigator.pop(s, 'import')),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick == 'import') {
      await Navigator.of(context).push(AppPageRoute(builder: (_) => ContactsImportPage(api: api, me: _me)));
      if (mounted) _reload();
    } else {
      await _add(pick);
    }
  }

  List<(String, String, int?)> get _chips => [
        ('all', tr('Tất cả'), null),
        ('mine', tr('Của tôi'), null),
        ('type:customer', tr('Khách hàng'), null),
        ('type:lead', tr('Tiềm năng'), null),
        ('type:supplier', tr('Nhà cung cấp'), null),
        ('type:partner', tr('Đối tác'), null),
        if (_admin && (_counts['duplicates'] as num? ?? 0) > 0) ('dupes', tr('Có thể trùng'), (_counts['duplicates'] as num).toInt()),
        if ((_admin || _manager) && (_counts['orphans'] as num? ?? 0) > 0) ('orphans', tr('Của người đã nghỉ'), (_counts['orphans'] as num).toInt()),
      ];

  void _setFilter(String f) {
    if (f == _filter) return;
    setState(() { _filter = f; _selected = null; });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (_error != null && _rows.isEmpty && _me.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: pal.sub))));
    }
    final list = _listColumn(pal);
    if (!_wide) return list;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 220, child: _sideNav(pal)),
      VerticalDivider(width: .6, thickness: .6, color: pal.divider),
      Expanded(flex: 5, child: list),
      VerticalDivider(width: .6, thickness: .6, color: pal.divider),
      Expanded(
        flex: 4,
        child: _selected == null
            ? Center(child: Text(tr('Chọn một liên hệ để xem'), style: TextStyle(color: pal.sub)))
            : ContactDetail(key: ValueKey(_selected), api: api, id: _selected!, me: _me, embedded: true, onChanged: _reload, onOpen: (id) => setState(() => _selected = id)),
      ),
    ]);
  }

  Widget _listColumn(Pal pal) {
    return Stack(children: [
      Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: _search,
                style: TextStyle(color: pal.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: pal.surface,
                  hintText: tr('Tên, SĐT, MST, email…'),
                  hintStyle: TextStyle(color: pal.sub),
                  prefixIcon: Icon(Icons.search, size: 20, color: pal.sub),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            if (_wide) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(AppPageRoute(builder: (_) => ContactsImportPage(api: api, me: _me)));
                  if (mounted) _reload();
                },
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(tr('Nhập file')),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _addMenu, icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Thêm khách'))),
            ],
          ]),
        ),
        if (!_wide)
          SizedBox(
            height: 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                for (final (id, label, n) in _chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 6),
                    child: ChoiceChip(
                      label: Text(n == null ? label : '$label · $n'),
                      selected: _filter == id,
                      showCheckmark: false,
                      onSelected: (_) => _setFilter(id),
                      selectedColor: pal.chipSelBg,
                      labelStyle: TextStyle(fontSize: 13.5, color: _filter == id ? pal.chipSelFg : pal.text, fontWeight: FontWeight.w500),
                      backgroundColor: pal.surface,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
              ]),
            ),
          ),
        if (_loading) LinearProgressIndicator(color: pal.accent, minHeight: 2) else const SizedBox(height: 2),
        Expanded(child: _body(pal)),
      ]),
      if (!_wide)
        Positioned(
          right: 20,
          bottom: 24 + widget.bottomPadding,
          child: FloatingActionButton(
            heroTag: 'contacts-add',
            tooltip: tr('Thêm khách'),
            onPressed: _addMenu,
            backgroundColor: pal.accent,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
    ]);
  }

  Widget _body(Pal pal) {
    if (_filter == 'dupes') return DuplicatesView(api: api, me: _me, onChanged: _reload, onOpen: _open);
    if (_filter == 'orphans' && _q.isEmpty) {
      return OrphansView(api: api, onChanged: _reload, rows: _rows, onOpen: _open, selected: _selected);
    }
    if (_rows.isEmpty && !_loading) {
      return ListView(padding: const EdgeInsets.all(32), children: [
        Icon(Icons.contacts_outlined, size: 56, color: pal.sub),
        const SizedBox(height: 12),
        Text(_q.isNotEmpty ? tr('Không tìm thấy liên hệ nào') : tr('Chưa có khách nào. Bấm + để thêm, hoặc nhập từ file Excel / vCard.'),
            textAlign: TextAlign.center, style: TextStyle(color: pal.sub, fontSize: 15)),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: EdgeInsets.only(bottom: 90 + widget.bottomPadding),
        itemCount: _rows.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Text(tr('{0} liên hệ', [_total]), style: TextStyle(color: pal.sub, fontSize: 13)),
            );
          }
          final c = _rows[i - 1];
          return ContactRow(c: c, selected: _selected == c['id'], onTap: () => _open('${c['id']}'));
        },
      ),
    );
  }

  Widget _sideNav(Pal pal) {
    final types = Map<String, dynamic>.from(_counts['types'] as Map? ?? const {});
    final depts = [for (final d in (_counts['depts'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];
    Widget item(String id, String label, Object? n, {bool warn = false}) {
      final sel = _filter == id;
      return Material(
        color: sel ? pal.chipSelBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _setFilter(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sel ? pal.chipSelFg : pal.text, fontWeight: sel ? FontWeight.w600 : FontWeight.w400))),
              if (n != null) Text('$n', style: TextStyle(fontSize: 12.5, color: warn ? const Color(0xFFD97706) : pal.sub, fontWeight: warn ? FontWeight.w700 : FontWeight.w400)),
            ]),
          ),
        ),
      );
    }

    Widget head(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
          child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: pal.sub, letterSpacing: .4)),
        );
    return ColoredBox(
      color: pal.surface.withValues(alpha: .5),
      child: ListView(padding: const EdgeInsets.all(10), children: [
        item('all', tr('Tất cả'), _counts['all']),
        item('mine', tr('Của tôi'), _counts['mine']),
        head(tr('Loại')),
        for (final t in const ['customer', 'lead', 'supplier', 'partner', 'shipping', 'agency', 'other'])
          if (types[t] != null || const ['customer', 'lead', 'supplier', 'partner'].contains(t)) item('type:$t', typeLabel(t), types[t] ?? 0),
        head(tr('Ai thấy')),
        item('private', tr('Riêng tôi'), _counts['private']),
        for (final d in depts) item('dept:${d['id']}', '${d['name']}', d['count']),
        item('company', tr('Toàn công ty'), _counts['company']),
        if (_admin || _manager) ...[
          head(tr('Quản lý')),
          if (_admin) item('dupes', tr('Có thể trùng'), _counts['duplicates'], warn: (_counts['duplicates'] as num? ?? 0) > 0),
          item('orphans', tr('Của người đã nghỉ'), _counts['orphans'], warn: (_counts['orphans'] as num? ?? 0) > 0),
        ],
      ]),
    );
  }
}

/// Hàng chờ "Có thể trùng" (Quản lý danh bạ): từng cặp, gộp vào bên nào hoặc đánh dấu không trùng.
class DuplicatesView extends StatefulWidget {
  const DuplicatesView({super.key, required this.api, required this.me, required this.onChanged, required this.onOpen});
  final ContactsApi api;
  final Map<String, dynamic> me;
  final VoidCallback onChanged;
  final void Function(String id) onOpen;
  @override
  State<DuplicatesView> createState() => _DuplicatesViewState();
}

class _DuplicatesViewState extends State<DuplicatesView> {
  List<Map<String, dynamic>>? _pairs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.get('/api/duplicates');
    if (mounted) setState(() => _pairs = [for (final p in r['pairs'] as List) Map<String, dynamic>.from(p as Map)]);
  }

  Future<void> _merge(Map keep, Map drop) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Gộp liên hệ?')),
        content: Text(tr('Gộp "{0}" vào "{1}". Số điện thoại, email, nhãn, dòng thời gian và người liên hệ được hợp lại. Hoàn tác được trong 30 ngày.', [drop['name'], keep['name']])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Gộp'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await widget.api.post('/api/contacts/${keep['id']}/merge', {'drop': [drop['id']]});
      final mid = '${r['merge_id']}';
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Đã gộp vào {0}', [keep['name']])),
        action: SnackBarAction(label: tr('Hoàn tác'), onPressed: () async {
          await widget.api.post('/api/merges/$mid/undo');
          widget.onChanged();
          _load();
        }),
      ));
      widget.onChanged();
      _load();
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final pairs = _pairs;
    if (pairs == null) return const Center(child: CircularProgressIndicator());
    if (pairs.isEmpty) return Center(child: Text(tr('Không còn cặp nào có thể trùng'), style: TextStyle(color: pal.sub)));
    final by = {'tax': tr('trùng MST'), 'phone': tr('trùng số điện thoại'), 'email': tr('trùng email'), 'name': tr('tên gần giống')};
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
      for (final p in pairs)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CardBox(padding: const EdgeInsets.all(12), children: [
            Text(by[p['by']] ?? '${p['by']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
            const SizedBox(height: 6),
            for (final side in [p['a'] as Map, p['b'] as Map])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ContactIcon(kind: '${side['kind']}', name: '${side['name']}', size: 38),
                title: Text('${side['name']}', style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
                subtitle: Text('${contactSubtitle(side)}\n${ownerLine(side)}', style: TextStyle(color: pal.sub, fontSize: 12.5)),
                isThreeLine: true,
                onTap: () => widget.onOpen('${side['id']}'),
              ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonal(onPressed: () => _merge(p['a'] as Map, p['b'] as Map), child: Text(tr('Giữ bản trên'))),
              FilledButton.tonal(onPressed: () => _merge(p['b'] as Map, p['a'] as Map), child: Text(tr('Giữ bản dưới'))),
              TextButton(
                onPressed: () async {
                  await widget.api.post('/api/not-dupes', {'a': (p['a'] as Map)['id'], 'b': (p['b'] as Map)['id']});
                  widget.onChanged();
                  _load();
                },
                child: Text(tr('Không trùng')),
              ),
            ]),
          ]),
        ),
    ]);
  }
}

/// Khách của người đã nghỉ: theo từng người, chuyển hết cho người khác; bên dưới là danh sách liên hệ.
class OrphansView extends StatefulWidget {
  const OrphansView({super.key, required this.api, required this.onChanged, required this.rows, required this.onOpen, this.selected});
  final ContactsApi api;
  final VoidCallback onChanged;
  final List<Map<String, dynamic>> rows;
  final void Function(String id) onOpen;
  final String? selected;
  @override
  State<OrphansView> createState() => _OrphansViewState();
}

class _OrphansViewState extends State<OrphansView> {
  List<Map<String, dynamic>> _owners = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.get('/api/orphans');
    if (mounted) setState(() => _owners = [for (final o in r['owners'] as List) Map<String, dynamic>.from(o as Map)]);
  }

  Future<void> _move(Map o) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final to = await pickUsers(context, app, single: true, title: tr('Chuyển khách của {0} cho', [o['name']]));
    if (to == null || to.isEmpty) return;
    try {
      final r = await widget.api.post('/api/reassign', {'from': o['id'], 'to': to.first});
      messenger.showSnackBar(toast(Text(tr('Đã chuyển {0} liên hệ', [r['moved']]))));
      widget.onChanged();
      _load();
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
      for (final o in _owners)
        ListTile(
          leading: const Icon(Icons.person_off_outlined, color: Color(0xFFD97706)),
          title: Text(tr('{0} (đã nghỉ)', [o['name']]), style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
          subtitle: Text(tr('{0} liên hệ', [o['count']]), style: TextStyle(color: pal.sub)),
          trailing: FilledButton.tonal(onPressed: () => _move(o), child: Text(tr('Chuyển cho…'))),
        ),
      if (_owners.isNotEmpty) Divider(color: pal.divider),
      for (final c in widget.rows) ContactRow(c: c, selected: widget.selected == c['id'], onTap: () => widget.onOpen('${c['id']}')),
    ]);
  }
}
