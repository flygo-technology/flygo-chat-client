// Chi tiết một liên hệ khách: nút gọi / Zalo / mail / ghi chú, thông tin, người liên hệ (công ty) hoặc công ty (người),
// dòng thời gian. Trên máy tính hiện ở cột phải của tab Khách (embedded); trên điện thoại là trang riêng.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../flows/flows_org.dart' show pickUsers;
import '../theme.dart';
import 'api.dart';
import 'contact_edit.dart';
import 'look.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key, required this.api, required this.id, required this.me});
  final ContactsApi api;
  final String id;
  final Map<String, dynamic> me;
  @override
  Widget build(BuildContext context) => ContactDetail(api: api, id: id, me: me);
}

class ContactDetail extends StatefulWidget {
  const ContactDetail({super.key, required this.api, required this.id, required this.me, this.embedded = false, this.onChanged, this.onOpen});
  final ContactsApi api;
  final String id;
  final Map<String, dynamic> me;
  final bool embedded;
  final VoidCallback? onChanged;
  /// Mở một liên hệ khác (người của công ty…): máy tính đổi cột phải, điện thoại mở trang mới.
  final void Function(String id)? onOpen;
  @override
  State<ContactDetail> createState() => _ContactDetailState();
}

class _ContactDetailState extends State<ContactDetail> {
  Map<String, dynamic>? _c;
  String? _error;

  ContactsApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await api.contact(widget.id);
      if (mounted) setState(() { _c = c; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _changed(Map<String, dynamic> c) {
    setState(() => _c = c);
    widget.onChanged?.call();
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(toast(Text(s)));

  Future<void> _openOther(String id) async {
    if (widget.onOpen != null && widget.embedded) {
      widget.onOpen!(id);
      return;
    }
    await Navigator.of(context).push(AppPageRoute(builder: (_) => ContactPage(api: api, id: id, me: widget.me)));
    _load();
  }

  Future<void> _edit() async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(
        AppPageRoute(builder: (_) => ContactEditPage(api: api, me: widget.me, kind: '${_c!['kind']}', initial: _c)));
    if (c != null) _changed(c);
  }

  // ---------------------------------------------------------------- hành động nhanh
  List<String> get _phones => [for (final p in (_c?['phones'] as List? ?? const [])) '${p['v']}'];
  List<String> get _emails => [for (final e in (_c?['emails'] as List? ?? const [])) '${e['v']}'];

  Future<String?> _choose(List<String> items, String title) async {
    if (items.isEmpty) return null;
    if (items.length == 1) return items.first;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Pal.of(context).surface,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(14), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
          for (final i in items) ListTile(title: Text(i), onTap: () => Navigator.pop(s, i)),
        ]),
      ),
    );
  }

  Future<void> _call() async {
    final p = await _choose(_phones, tr('Gọi số nào?'));
    if (p == null) return _toast(tr('Liên hệ chưa có số điện thoại'));
    await launchUrl(Uri(scheme: 'tel', path: p.replaceAll(RegExp(r'[^\d+]'), '')));
    if (mounted) _logQuick('call', tr('Gọi {0}', [p]));
  }

  Future<void> _zalo() async {
    final z = '${_c?['zalo'] ?? ''}'.trim();
    final p = z.isNotEmpty ? z : await _choose(_phones, tr('Mở Zalo số nào?'));
    if (p == null) return _toast(tr('Liên hệ chưa có số điện thoại / Zalo'));
    final url = p.startsWith('http') ? Uri.parse(p) : Uri.parse('https://zalo.me/${p.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^84'), '0')}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _mail() async {
    final e = await _choose(_emails, tr('Gửi tới email nào?'));
    if (e == null) return _toast(tr('Liên hệ chưa có email'));
    await launchUrl(Uri(scheme: 'mailto', path: e));
  }

  /// Sau khi bấm Gọi: hỏi có ghi vào dòng thời gian không (không tự ghi, vì có thể không gọi được).
  void _logQuick(String kind, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('Ghi "{0}" vào dòng thời gian?', [text])),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: tr('Ghi'), onPressed: () => _addNote(kind: kind, text: text)),
    ));
  }

  Future<void> _addNote({String kind = 'note', String text = ''}) async {
    final pal = Pal.of(context);
    final ctl = TextEditingController(text: text);
    var k = kind;
    final res = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pal.surface,
      builder: (s) => StatefulBuilder(
        builder: (s, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(s).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Ghi vào dòng thời gian'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final x in const ['note', 'call', 'meeting', 'mail', 'chat', 'other'])
                ChoiceChip(
                  avatar: Icon(interactionIcon(x), size: 16),
                  label: Text(interactionLabel(x)),
                  selected: k == x,
                  showCheckmark: false,
                  onSelected: (_) => set(() => k = x),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: tr('Nội dung: khách hỏi gì, hẹn gì…'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: () => Navigator.pop(s, (k, ctl.text.trim())), child: Text(tr('Lưu'))),
            ),
          ]),
        ),
      ),
    );
    if (res == null || res.$2.isEmpty) return;
    try {
      await api.post('/api/contacts/${widget.id}/interactions', {'kind': res.$1, 'summary': res.$2});
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      _toast('$e');
    }
  }

  // ---------------------------------------------------------------- chia sẻ, người liên hệ, menu
  Future<void> _share() async {
    final c = _c!;
    final shares = [for (final s in (c['shares'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
    final depts = [for (final d in (widget.me['depts'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    final result = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pal.surface,
      builder: (s) => StatefulBuilder(builder: (s, set) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Chia sẻ thêm'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text)),
              const SizedBox(height: 4),
              Text(tr('Ngoài phạm vi "{0}", những người / phòng dưới đây cũng thấy liên hệ này.', [scopeLabel('${c['scope']}')]), style: TextStyle(color: pal.sub, fontSize: 13)),
              const SizedBox(height: 8),
              for (final sh in shares)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(sh['type'] == 'dept' ? Icons.groups_rounded : Icons.person_rounded),
                  title: Text('${sh['name'] ?? sh['id']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButton<String>(
                      value: '${sh['level']}',
                      underline: const SizedBox.shrink(),
                      items: [DropdownMenuItem(value: 'view', child: Text(tr('Chỉ xem'))), DropdownMenuItem(value: 'edit', child: Text(tr('Có thể sửa')))],
                      onChanged: (v) => set(() => sh['level'] = v),
                    ),
                    IconButton(tooltip: tr('Bỏ'), icon: const Icon(Icons.close_rounded), onPressed: () => set(() => shares.remove(sh))),
                  ]),
                ),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: Text(tr('Thêm người')),
                  onPressed: () async {
                    final ids = await pickUsers(s, app, title: tr('Chia sẻ cho'));
                    if (ids == null) return;
                    set(() {
                      for (final id in ids) {
                        if (!shares.any((x) => x['type'] == 'user' && x['id'] == id)) {
                          shares.add({'type': 'user', 'id': id, 'level': 'view', 'name': app.users[id]?.displayName ?? id});
                        }
                      }
                    });
                  },
                ),
                if (depts.isNotEmpty)
                  PopupMenuButton<Map<String, dynamic>>(
                    tooltip: tr('Thêm phòng ban'),
                    itemBuilder: (_) => [for (final d in depts) PopupMenuItem(value: d, child: Text('${d['name']}'))],
                    onSelected: (d) => set(() {
                      if (!shares.any((x) => x['type'] == 'dept' && x['id'] == d['id'])) shares.add({'type': 'dept', 'id': d['id'], 'level': 'view', 'name': d['name']});
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.group_add_rounded, color: pal.accentText),
                        const SizedBox(width: 6),
                        Text(tr('Thêm phòng ban'), style: TextStyle(color: pal.accentText, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => Navigator.pop(s, shares), child: Text(tr('Lưu'))),
            ]),
          ),
        );
      }),
    );
    if (result == null) return;
    try {
      final r = await api.put('/api/contacts/${widget.id}/shares', {'shares': [for (final x in result) {'type': x['type'], 'id': x['id'], 'level': x['level']}]});
      _changed(Map<String, dynamic>.from(r['contact'] as Map));
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _addPerson() async {
    final c = await Navigator.of(context).push<Map<String, dynamic>>(
        AppPageRoute(builder: (_) => ContactEditPage(api: api, me: widget.me, kind: 'person', company: _c)));
    if (c != null) {
      await _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _linkExisting() async {
    final isCompany = _c!['kind'] == 'company';
    final picked = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => ContactPicker(api: api, kind: isCompany ? 'person' : 'company'));
    if (picked == null || !mounted) return;
    final role = await _askText(tr('Chức danh ở công ty (không bắt buộc)'));
    try {
      await api.post('/api/contacts/${widget.id}/links', {'contact': picked['id'], 'role': role ?? ''});
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<String?> _askText(String title, {String initial = ''}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(d, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          TextButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: Text(tr('OK'))),
        ],
      ),
    );
  }

  Future<void> _vcard() async {
    try {
      final text = await api.text('/api/contacts/${widget.id}/vcard');
      final dir = await getTemporaryDirectory();
      final safe = '${_c!['name']}'.replaceAll(RegExp(r'[^\w\- ]', unicode: true), '').trim();
      final f = File('${dir.path}/${safe.isEmpty ? 'lien-he' : safe}.vcf');
      await f.writeAsString(text);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'text/vcard')], text: '${_c!['name']}'));
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Xoá liên hệ?')),
        content: Text(tr('Xoá "{0}" khỏi danh bạ khách. Dòng thời gian vẫn được giữ trong nhật ký.', [_c!['name']])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Xoá'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.delete('/api/contacts/${widget.id}');
      widget.onChanged?.call();
      if (mounted && !widget.embedded) Navigator.of(context).pop();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _mergeWith() async {
    final picked = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => ContactPicker(api: api, kind: '${_c!['kind']}', exclude: widget.id));
    if (picked == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Gộp liên hệ?')),
        content: Text(tr('Gộp "{0}" vào "{1}". Số điện thoại, email, nhãn, dòng thời gian và người liên hệ được hợp lại. Hoàn tác được trong 30 ngày.', [picked['name'], _c!['name']])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Gộp'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await api.post('/api/contacts/${widget.id}/merge', {'drop': [picked['id']]});
      _changed(Map<String, dynamic>.from(r['contact'] as Map));
      if (!mounted) return;
      final mid = '${r['merge_id']}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Đã gộp')),
        action: SnackBarAction(label: tr('Hoàn tác'), onPressed: () async {
          await api.post('/api/merges/$mid/undo');
          _load();
          widget.onChanged?.call();
        }),
      ));
    } catch (e) {
      _toast('$e');
    }
  }

  // ---------------------------------------------------------------- vẽ
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = _c;
    final canEdit = c?['can_edit'] == true;
    final admin = widget.me['admin'] == true;
    final actions = <Widget>[
      if (canEdit) TextButton(onPressed: _edit, child: Text(tr('Sửa'))),
      if (c != null)
        PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'share' => _share(),
            'vcard' => _vcard(),
            'merge' => _mergeWith(),
            'delete' => _delete(),
            _ => null,
          },
          itemBuilder: (_) => [
            if (canEdit) PopupMenuItem(value: 'share', child: Text(tr('Chia sẻ thêm…'))),
            PopupMenuItem(value: 'vcard', child: Text(tr('Gửi danh thiếp (vCard)'))),
            if (admin) PopupMenuItem(value: 'merge', child: Text(tr('Gộp liên hệ khác vào đây…'))),
            if (canEdit) PopupMenuItem(value: 'delete', child: Text(tr('Xoá'))),
          ],
        ),
    ];
    final body = _error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: pal.sub))))
        : c == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(onRefresh: _load, child: _content(pal, c));
    if (widget.embedded) {
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(8, 6, 4, 0), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions)),
        Expanded(child: body),
      ]);
    }
    return Scaffold(backgroundColor: pal.bg, appBar: AppBar(actions: actions), body: body);
  }

  Widget _content(Pal pal, Map<String, dynamic> c) {
    final types = [for (final t in (c['types'] as List? ?? const [])) '$t'];
    final isCompany = c['kind'] == 'company';
    final linked = [for (final x in (c[isCompany ? 'people' : 'companies'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final timeline = [for (final t in (c['timeline'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
    final facts = <(String, String)>[
      (tr('Phụ trách'), [
        '${(c['owner'] as Map?)?['name'] ?? ''}${(c['owner'] as Map?)?['inactive'] == true ? ' (${tr('đã nghỉ')})' : ''}',
        if ((c['helpers'] as List? ?? const []).isNotEmpty) '${tr('hỗ trợ')}: ${(c['helpers'] as List).map((h) => h['name']).join(', ')}',
      ].join(' · ')),
      (tr('Ai thấy'), [
        c['scope'] == 'dept' && '${c['dept_name'] ?? ''}'.isNotEmpty ? '${tr('Phòng')} ${c['dept_name']}' : scopeLabel('${c['scope']}'),
        for (final s in (c['shares'] as List? ?? const [])) '+${s['name']}',
      ].join(' · ')),
      if ('${c['full_name'] ?? ''}'.isNotEmpty && c['full_name'] != c['name']) (tr('Tên đầy đủ'), '${c['full_name']}'),
      if ('${c['job_title'] ?? ''}'.isNotEmpty) (tr('Chức danh'), '${c['job_title']}'),
      for (final p in (c['phones'] as List? ?? const [])) (p['label'] != null && '${p['label']}'.isNotEmpty ? '${p['label']}' : tr('Điện thoại'), '${p['pretty'] ?? p['v']}'),
      for (final e in (c['emails'] as List? ?? const [])) (e['label'] != null && '${e['label']}'.isNotEmpty ? '${e['label']}' : 'Email', '${e['v']}'),
      for (final a in (c['addresses'] as List? ?? const [])) (a['label'] != null && '${a['label']}'.isNotEmpty ? '${a['label']}' : tr('Địa chỉ'), '${a['v']}'),
      if ('${c['invoice_email'] ?? ''}'.isNotEmpty) (tr('Mail nhận HĐ'), '${c['invoice_email']}'),
      if ('${c['zalo'] ?? ''}'.isNotEmpty) ('Zalo', '${c['zalo']}'),
      if ('${c['wechat'] ?? ''}'.isNotEmpty) ('WeChat', '${c['wechat']}'),
      if ('${c['website'] ?? ''}'.isNotEmpty) ('Website', '${c['website']}'),
      if ('${c['country'] ?? ''}'.isNotEmpty) (tr('Quốc gia'), [c['country'], c['currency']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · ')),
      if ((c['tags'] as List? ?? const []).isNotEmpty) (tr('Nhãn'), (c['tags'] as List).join(' · ')),
      for (final e in Map<String, dynamic>.from(c['external_ids'] as Map? ?? const {}).entries) (tr('Mã {0}', [e.key]), '${e.value}'),
      if ('${c['source'] ?? ''}'.isNotEmpty) (tr('Nguồn'), '${c['source']}'),
    ];
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: Material(
            color: pal.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: 58,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 20, color: pal.accentText),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.accentText)),
                ]),
              ),
            ),
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
      Row(children: [
        ContactIcon(kind: '${c['kind']}', name: '${c['name']}', size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText('${c['name']}', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.text, height: 1.25)),
            const SizedBox(height: 5),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final t in types) TypeChip(t),
              if ('${c['tax_id'] ?? ''}'.isNotEmpty) SelectableText('MST ${c['tax_id']}', style: TextStyle(fontSize: 13, color: pal.sub)),
              if (c['status'] == 'inactive') TypeChip('agency', label: tr('Ngừng giao dịch')),
              if (c['status'] == 'blacklist') TypeChip('lead', label: tr('Danh sách đen')),
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        action(Icons.call_rounded, tr('Gọi'), _call),
        const SizedBox(width: 8),
        action(Icons.chat_rounded, 'Zalo', _zalo),
        const SizedBox(width: 8),
        action(Icons.mail_outline_rounded, 'Mail', _mail),
        const SizedBox(width: 8),
        action(Icons.edit_note_rounded, tr('Ghi chú'), _addNote),
      ]),
      const SizedBox(height: 12),
      CardBox(children: [
        for (final (k, v) in facts)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider, width: .6))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 110, child: Text(k, style: TextStyle(fontSize: 14, color: pal.sub))),
              Expanded(child: SelectableText(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: pal.text))),
            ]),
          ),
      ]),
      if ('${c['notes'] ?? ''}'.isNotEmpty) ...[
        SectionTitle(tr('Ghi chú')),
        CardBox(padding: const EdgeInsets.all(14), children: [SelectableText('${c['notes']}', style: TextStyle(color: pal.text, height: 1.4))]),
      ],
      SectionTitle(
        isCompany ? tr('Người liên hệ ({0})', [linked.length]) : tr('Công ty ({0})', [linked.length]),
        trailing: c['can_edit'] == true
            ? PopupMenuButton<String>(
                tooltip: tr('Thêm'),
                icon: Icon(Icons.add_circle_outline_rounded, color: pal.accentText),
                onSelected: (v) => v == 'new' ? _addPerson() : _linkExisting(),
                itemBuilder: (_) => [
                  if (isCompany) PopupMenuItem(value: 'new', child: Text(tr('Thêm người liên hệ mới'))),
                  PopupMenuItem(value: 'link', child: Text(isCompany ? tr('Gắn người có sẵn') : tr('Gắn vào công ty có sẵn'))),
                ],
              )
            : null,
      ),
      if (linked.isNotEmpty)
        CardBox(padding: EdgeInsets.zero, children: [
          for (final l in linked)
            ListTile(
              leading: ContactIcon(kind: '${l['kind']}', name: '${l['name']}', size: 36),
              title: Text('${l['name']}', style: TextStyle(color: pal.text, fontWeight: FontWeight.w600, decoration: l['left'] == true ? TextDecoration.lineThrough : null)),
              subtitle: Text([l['role'], l['phone']].where((x) => '${x ?? ''}'.isNotEmpty).join(' · '), style: TextStyle(color: pal.sub)),
              onTap: () => _openOther('${l['id']}'),
            ),
        ]),
      SectionTitle(tr('Dòng thời gian'), trailing: TextButton.icon(onPressed: _addNote, icon: const Icon(Icons.add_rounded, size: 18), label: Text(tr('Ghi chú / Đã gọi')))),
      if (timeline.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(tr('Chưa có tương tác nào'), style: TextStyle(color: pal.sub))),
      for (final t in timeline)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: pal.surface, shape: BoxShape.circle),
              child: Icon(interactionIcon('${t['kind']}'), size: 16, color: pal.accentText),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: '${t['link'] ?? ''}'.isEmpty ? null : () => launchUrl(Uri.parse('${t['link']}'), mode: LaunchMode.externalApplication),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText('${t['summary']}', style: TextStyle(fontSize: 14, color: pal.text)),
                  const SizedBox(height: 2),
                  Text(
                      [shortDate((t['at'] as num).toInt()), interactionLabel('${t['kind']}'), (t['actor'] as Map?)?['name'], if ('${t['via'] ?? ''}'.isNotEmpty) '${t['via']}']
                          .where((x) => '${x ?? ''}'.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(fontSize: 12.5, color: pal.sub)),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Hộp chọn một liên hệ có sẵn (gắn người vào công ty, gộp).
class ContactPicker extends StatefulWidget {
  const ContactPicker({super.key, required this.api, this.kind, this.exclude});
  final ContactsApi api;
  final String? kind;
  final String? exclude;
  @override
  State<ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<ContactPicker> {
  List<Map<String, dynamic>> _rows = [];
  int _no = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final no = ++_no;
    final r = await widget.api.list(q: q, kind: widget.kind, limit: 50);
    if (!mounted || no != _no) return;
    setState(() => _rows = [for (final c in r['contacts'] as List) if (c['id'] != widget.exclude) Map<String, dynamic>.from(c as Map)]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.kind == 'company' ? tr('Chọn công ty') : widget.kind == 'person' ? tr('Chọn người') : tr('Chọn liên hệ')),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Tìm tên, SĐT, MST'), isDense: true, border: const OutlineInputBorder()),
            onChanged: _search,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(children: [
              for (final c in _rows)
                ListTile(
                  leading: ContactIcon(kind: '${c['kind']}', name: '${c['name']}', size: 36),
                  title: Text('${c['name']}'),
                  subtitle: Text(contactSubtitle(c), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, c),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy')))],
    );
  }
}
