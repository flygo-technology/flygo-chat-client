// Thêm / sửa liên hệ khách. Gõ MST thì tra tên, địa chỉ; gõ số / email / MST thì báo ngay nếu đã có trong danh bạ
// (thấy được thì mở hoặc gắn vào công ty, không thấy thì chỉ biết ai phụ trách và xin chia sẻ). Chọn ai được xem.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../flows/flows_org.dart' show pickUsers;
import '../theme.dart';
import 'api.dart';
import 'look.dart';

class ContactEditPage extends StatefulWidget {
  const ContactEditPage({super.key, required this.api, required this.me, required this.kind, this.initial, this.company, this.prefill});
  final ContactsApi api;
  final Map<String, dynamic> me;
  final String kind;
  /// Liên hệ đang sửa; null = thêm mới.
  final Map<String, dynamic>? initial;
  /// Thêm người liên hệ cho công ty này.
  final Map<String, dynamic>? company;
  /// Điền sẵn khi thêm mới (vd tên gõ ở ô tìm của form Quy trình).
  final Map<String, dynamic>? prefill;
  @override
  State<ContactEditPage> createState() => _ContactEditPageState();
}

class _ContactEditPageState extends State<ContactEditPage> {
  late final bool _isNew = widget.initial == null;
  late final Map<String, dynamic> _src = {...?widget.prefill, ...?widget.initial};
  late final _name = TextEditingController(text: '${_src['name'] ?? ''}');
  late final _fullName = TextEditingController(text: '${_src['full_name'] ?? ''}');
  late final _tax = TextEditingController(text: '${_src['tax_id'] ?? ''}');
  late final _job = TextEditingController(text: '${_src['job_title'] ?? ''}');
  late final _zalo = TextEditingController(text: '${_src['zalo'] ?? ''}');
  late final _wechat = TextEditingController(text: '${_src['wechat'] ?? ''}');
  late final _website = TextEditingController(text: '${_src['website'] ?? ''}');
  late final _invoice = TextEditingController(text: '${_src['invoice_email'] ?? ''}');
  late final _country = TextEditingController(text: '${_src['country'] ?? ''}');
  late final _currency = TextEditingController(text: '${_src['currency'] ?? ''}');
  late final _tags = TextEditingController(text: (_src['tags'] as List? ?? const []).join(', '));
  late final _source = TextEditingController(text: '${_src['source'] ?? ''}');
  late final _notes = TextEditingController(text: '${_src['notes'] ?? ''}');
  late final List<TextEditingController> _phones = _ctls(_src['phones']);
  late final List<TextEditingController> _emails = _ctls(_src['emails']);
  late final List<TextEditingController> _addrs = _ctls(_src['addresses']);
  late final Set<String> _types = {for (final t in (_src['types'] as List? ?? (widget.kind == 'company' ? const ['customer'] : const []))) '$t'};
  late String _salutation = '${_src['salutation'] ?? ''}';
  late String _status = '${_src['status'] ?? 'active'}';
  late String _scope = '${_src['scope'] ?? (_myDepts.isEmpty ? 'private' : 'dept')}';
  late String? _dept = _src['dept'] as String? ?? (_myDepts.isEmpty ? null : '${_myDepts.first['id']}');
  late String _owner = '${(_src['owner'] as Map?)?['id'] ?? (widget.me['user'] as Map?)?['id'] ?? ''}';
  late String _ownerName = '${(_src['owner'] as Map?)?['name'] ?? (widget.me['user'] as Map?)?['name'] ?? ''}';
  bool _more = false;
  bool _busy = false;
  String? _taxNote;
  bool _taxOk = false;
  List<Map<String, dynamic>> _matches = [];
  Timer? _debounce;

  List<Map<String, dynamic>> get _myDepts => [for (final d in (widget.me['my_depts'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];
  List<Map<String, dynamic>> get _allDepts => [for (final d in (widget.me['depts'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];
  bool get _isCompany => widget.kind == 'company';

  static List<TextEditingController> _ctls(Object? list) {
    final out = [for (final x in (list as List? ?? const [])) TextEditingController(text: '${x is Map ? x['v'] : x}')];
    return out.isEmpty ? [TextEditingController()] : out;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _tax, ..._phones, ..._emails]) {
      c.addListener(_scheduleCheck);
    }
    if (_more == false && [_zalo, _wechat, _website, _invoice, _country, _currency, _source].any((c) => c.text.isNotEmpty)) _more = true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  List<String> _values(List<TextEditingController> l) => [for (final c in l) if (c.text.trim().isNotEmpty) c.text.trim()];

  void _scheduleCheck() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _check);
  }

  Future<void> _check() async {
    try {
      final r = await widget.api.post('/api/check', {
        'kind': widget.kind,
        'name': _name.text.trim(),
        'tax_id': _tax.text.trim(),
        'phones': _values(_phones),
        'emails': _values(_emails),
        if (!_isNew) 'exclude': widget.initial!['id'],
      });
      if (mounted) setState(() => _matches = [for (final m in r['matches'] as List) Map<String, dynamic>.from(m as Map)]);
    } catch (_) {}
  }

  Future<void> _lookupTax() async {
    final t = _tax.text.trim();
    if (t.isEmpty) return;
    setState(() { _busy = true; _taxNote = null; });
    try {
      final r = await widget.api.get('/api/tax/${Uri.encodeComponent(t.replaceAll(RegExp(r'[\s.]'), ''))}');
      final info = Map<String, dynamic>.from(r['info'] as Map);
      setState(() {
        if ('${info['name']}'.isNotEmpty) {
          _fullName.text = '${info['name']}';
          if (_name.text.trim().isEmpty) _name.text = '${info['short_name'] ?? ''}'.isNotEmpty ? '${info['short_name']}' : _titleCase('${info['name']}');
        }
        if ('${info['address'] ?? ''}'.isNotEmpty && !_values(_addrs).contains('${info['address']}')) {
          if (_addrs.last.text.trim().isEmpty) {
            _addrs.last.text = '${info['address']}';
          } else {
            _addrs.add(TextEditingController(text: '${info['address']}'));
          }
        }
        _taxOk = info['active'] == true;
        _taxNote = info['active'] == true ? tr('Đã tự điền tên và địa chỉ theo MST · đang hoạt động') : tr('Tình trạng: {0}', [info['status']]);
      });
      _check();
    } catch (e) {
      setState(() { _taxOk = false; _taxNote = '$e'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "CÔNG TY TNHH ABC" → "Công Ty TNHH ABC": tên in hoa toàn bộ của Cục Thuế đọc dễ hơn (giữ các chữ viết tắt).
  static String _titleCase(String s) {
    const keep = {'TNHH', 'CP', 'MTV', 'JSC', 'TM', 'DV', 'XD', 'XNK', 'SX', 'VN', 'HN', 'HCM'};
    return s.split(' ').map((w) {
      if (w.isEmpty || keep.contains(w)) return w;
      final lower = w.toLowerCase();
      return lower.characters.first.toUpperCase() + lower.characters.skip(1).toString();
    }).join(' ');
  }

  Map<String, dynamic> _body() => {
        'kind': widget.kind,
        'name': _name.text.trim(),
        'types': _types.toList(),
        'tags': _tags.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'phones': _values(_phones),
        'emails': _values(_emails),
        'addresses': _values(_addrs),
        'notes': _notes.text.trim(),
        'zalo': _zalo.text.trim(),
        'website': _website.text.trim(),
        'country': _country.text.trim(),
        'currency': _currency.text.trim(),
        'wechat': _wechat.text.trim(),
        'source': _source.text.trim(),
        if (_isCompany) ...{'tax_id': _tax.text.trim(), 'full_name': _fullName.text.trim(), 'invoice_email': _invoice.text.trim()},
        if (!_isCompany) ...{'job_title': _job.text.trim(), 'salutation': _salutation},
        if (!_isNew) 'status': _status,
        'scope': _scope,
        'dept': _scope == 'dept' ? _dept : (_dept ?? (_src['dept'] as String?)),
        if (_owner.isNotEmpty) 'owner': _owner,
        if (_isNew && widget.company != null) ...{'company': widget.company!['id'], 'role': _job.text.trim()},
        if (!_isNew) 'base_version': widget.initial!['version'],
      };

  Future<void> _save({bool force = false}) async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Cần nhập tên'))));
      return;
    }
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      final b = _body();
      final c = _isNew ? await widget.api.create({...b, if (force) 'force': true}) : await widget.api.update('${widget.initial!['id']}', b);
      nav.pop(c);
    } on ContactsException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.status == 409 && e.body['duplicates'] is List) {
        final dups = [for (final d in e.body['duplicates'] as List) Map<String, dynamic>.from(d as Map)];
        final hard = dups.any((d) => d['by'] == 'tax');
        final go = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(e.message),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [for (final m in dups) Text('• ${_matchText(m)}')]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Quay lại sửa'))),
              if (!hard) FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Vẫn tạo mới'))),
            ],
          ),
        );
        if (go == true) _save(force: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(toast(Text(e.message)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  String _matchText(Map m) {
    final by = switch (m['by']) { 'tax' => tr('MST'), 'phone' => tr('số điện thoại'), 'email' => 'email', _ => tr('tên gần giống') };
    return m['visible'] == true ? tr('{0}: trùng {1} · {2} phụ trách', [m['name'], by, m['owner_name']]) : tr('Trùng {0} với một liên hệ do {1} phụ trách (bạn chưa được xem)', [by, m['owner_name']]);
  }

  Future<void> _linkMatch(Map m) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.post('/api/contacts/${widget.company!['id']}/links', {'contact': m['id'], 'role': _job.text.trim()});
      nav.pop(await widget.api.contact('${m['id']}'));
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  Future<void> _requestShare(Map m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.post('/api/contacts/${m['id']}/share-request', {'note': _name.text.trim()});
      messenger.showSnackBar(toast(Text(tr('Đã nhắn {0} xin chia sẻ', [m['owner_name']]))));
    } catch (e) {
      messenger.showSnackBar(toast(Text('$e')));
    }
  }

  Future<void> _pickOwner() async {
    final app = context.read<AppState>();
    final ids = await pickUsers(context, app, single: true, selected: [_owner], title: tr('Người phụ trách'));
    if (ids == null || ids.isEmpty) return;
    setState(() {
      _owner = ids.first;
      _ownerName = app.users[ids.first]?.displayName ?? ids.first;
    });
  }

  // ---------------------------------------------------------------- vẽ
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final title = _isNew ? (_isCompany ? tr('Thêm công ty') : widget.company != null ? tr('Thêm người liên hệ') : tr('Thêm người')) : tr('Sửa liên hệ');
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        title: Text(title),
        actions: [TextButton(onPressed: _busy ? null : _save, child: Text(tr('Lưu'), style: const TextStyle(fontWeight: FontWeight.w700)))],
      ),
      body: Column(children: [
        if (_busy) LinearProgressIndicator(color: pal.accent, minHeight: 2),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
            if (widget.company != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  ContactIcon(kind: 'company', name: '${widget.company!['name']}', size: 28),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('Người liên hệ của {0}', [widget.company!['name']]), style: TextStyle(color: pal.sub))),
                ]),
              ),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final t in const ['customer', 'lead', 'supplier', 'partner', 'shipping', 'agency', 'other'])
                if (t != 'shipping' && t != 'agency' && t != 'other' || _types.contains(t) || _more)
                  FilterChip(
                    label: Text(typeLabel(t)),
                    selected: _types.contains(t),
                    showCheckmark: false,
                    selectedColor: pal.accent,
                    labelStyle: TextStyle(color: _types.contains(t) ? Colors.white : pal.text, fontWeight: FontWeight.w500),
                    backgroundColor: pal.surface,
                    side: BorderSide.none,
                    onSelected: (v) => setState(() => v ? _types.add(t) : _types.remove(t)),
                  ),
            ]),
            const SizedBox(height: 12),
            CardBox(children: [
              if (_isCompany) ...[
                _field(tr('MST'), _tax, keyboard: TextInputType.number, trailing: TextButton(onPressed: _busy ? null : _lookupTax, child: Text(tr('Tra MST')))),
                if (_taxNote != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(_taxNote!, style: TextStyle(fontSize: 12.5, color: _taxOk ? const Color(0xFF16A34A) : const Color(0xFFD97706), fontWeight: FontWeight.w500)),
                  ),
                _field(tr('Tên gọi'), _name, hint: tr('Tên ngắn hay dùng')),
                _field(tr('Tên đầy đủ'), _fullName, hint: tr('Theo đăng ký kinh doanh')),
              ] else ...[
                Row(children: [
                  SizedBox(width: 100, child: Text(tr('Xưng hô'), style: TextStyle(color: pal.sub, fontSize: 14))),
                  DropdownButton<String>(
                    value: const ['', 'anh', 'chị', 'ông', 'bà', 'Mr.', 'Ms.'].contains(_salutation) ? _salutation : '',
                    underline: const SizedBox.shrink(),
                    items: [for (final s in const ['', 'anh', 'chị', 'ông', 'bà', 'Mr.', 'Ms.']) DropdownMenuItem(value: s, child: Text(s.isEmpty ? '—' : s))],
                    onChanged: (v) => setState(() => _salutation = v ?? ''),
                  ),
                ]),
                _field(tr('Họ tên'), _name),
                _field(tr('Chức danh'), _job, hint: tr('PM công trình, Kế toán…')),
              ],
              for (var i = 0; i < _phones.length; i++)
                _field(i == 0 ? tr('Điện thoại') : '', _phones[i], keyboard: TextInputType.phone, trailing: _rowButton(_phones, i)),
              for (var i = 0; i < _emails.length; i++)
                _field(i == 0 ? 'Email' : '', _emails[i], keyboard: TextInputType.emailAddress, trailing: _rowButton(_emails, i)),
              for (var i = 0; i < _addrs.length; i++) _field(i == 0 ? tr('Địa chỉ') : '', _addrs[i], trailing: _rowButton(_addrs, i), last: i == _addrs.length - 1),
            ]),
            if (_matches.isNotEmpty) ...[const SizedBox(height: 12), _dupBanner(pal)],
            const SizedBox(height: 12),
            CardBox(padding: const EdgeInsets.all(14), children: [
              Text(tr('Ai được xem'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'private', label: Text(tr('Riêng tôi'))),
                  ButtonSegment(value: 'dept', label: Text(tr('Phòng ban')), enabled: _allDepts.isNotEmpty),
                  ButtonSegment(value: 'company', label: Text(tr('Toàn công ty'))),
                ],
                selected: {_scope},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _scope = s.first),
              ),
              if (_scope == 'dept') ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(tr('Phòng'), style: TextStyle(color: pal.sub))),
                  DropdownButton<String>(
                    value: _allDepts.any((d) => d['id'] == _dept) ? _dept : null,
                    hint: Text(tr('Chọn phòng')),
                    underline: const SizedBox.shrink(),
                    items: [for (final d in _myDepts.isNotEmpty ? [..._myDepts, ..._allDepts.where((x) => !_myDepts.any((m) => m['id'] == x['id']))] : _allDepts)
                      DropdownMenuItem(value: '${d['id']}', child: Text('${d['name']}'))],
                    onChanged: (v) => setState(() => _dept = v),
                  ),
                ]),
              ],
              const SizedBox(height: 4),
              InkWell(
                onTap: _pickOwner,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Expanded(child: Text(tr('Người phụ trách'), style: TextStyle(color: pal.sub))),
                    Text('$_ownerName ›', style: TextStyle(fontWeight: FontWeight.w500, color: pal.text)),
                  ]),
                ),
              ),
              Text(
                  _scope == 'private'
                      ? tr('Chỉ người phụ trách (và quản lý của họ) thấy.')
                      : _scope == 'dept'
                          ? tr('Mọi người trong phòng thấy; trưởng / phó phòng và quản lý cấp trên sửa được.')
                          : tr('Mọi người trong công ty thấy.'),
                  style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ]),
            const SizedBox(height: 12),
            CardBox(children: [
              _field(tr('Nhãn'), _tags, hint: tr('Cách nhau bằng dấu phẩy: VIP, Công trình HN')),
              if (_more) ...[
                _field('Zalo', _zalo, hint: tr('Số hoặc link Zalo nếu khác số điện thoại')),
                if (_isCompany) _field(tr('Mail nhận HĐ'), _invoice, keyboard: TextInputType.emailAddress),
                _field('Website', _website, keyboard: TextInputType.url),
                _field(tr('Quốc gia'), _country, hint: tr('Để trống nếu ở Việt Nam')),
                _field(tr('Tiền tệ'), _currency, hint: 'USD, CNY…'),
                _field('WeChat', _wechat),
                _field(tr('Nguồn'), _source, hint: tr('Giới thiệu, hội chợ, web…')),
              ],
              _field(tr('Ghi chú'), _notes, lines: 4, last: true),
            ]),
            if (!_more) TextButton(onPressed: () => setState(() => _more = true), child: Text(tr('Thêm Zalo, website, quốc gia, nguồn…'))),
            if (!_isNew) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text(tr('Trạng thái'), style: TextStyle(color: pal.sub))),
                DropdownButton<String>(
                  value: _status,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(value: 'active', child: Text(tr('Đang giao dịch'))),
                    DropdownMenuItem(value: 'inactive', child: Text(tr('Ngừng giao dịch'))),
                    DropdownMenuItem(value: 'blacklist', child: Text(tr('Danh sách đen'))),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'active'),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget? _rowButton(List<TextEditingController> list, int i) => i == list.length - 1
      ? IconButton(
          tooltip: tr('Thêm dòng'),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
          onPressed: () => setState(() {
            final c = TextEditingController();
            if (identical(list, _phones) || identical(list, _emails)) c.addListener(_scheduleCheck);
            list.add(c);
          }),
        )
      : IconButton(tooltip: tr('Bỏ'), icon: const Icon(Icons.remove_circle_outline_rounded, size: 20), onPressed: () => setState(() => list.removeAt(i)));

  Widget _field(String label, TextEditingController c, {String? hint, TextInputType? keyboard, Widget? trailing, int lines = 1, bool last = false}) {
    final pal = Pal.of(context);
    return Container(
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: pal.divider, width: .6))),
      child: Row(crossAxisAlignment: lines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
        SizedBox(width: 100, child: Padding(padding: EdgeInsets.only(top: lines > 1 ? 12 : 0), child: Text(label, style: TextStyle(color: pal.sub, fontSize: 14)))),
        Expanded(
          child: TextField(
            controller: c,
            keyboardType: lines > 1 ? TextInputType.multiline : keyboard,
            minLines: lines,
            // Tên, địa chỉ dài: xuống dòng thay vì bị cắt; số điện thoại, email, MST giữ một dòng.
            maxLines: lines > 1 ? 8 : (keyboard == null ? 3 : 1),
            textCapitalization: keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
            style: TextStyle(color: pal.text, fontSize: 15),
            decoration: InputDecoration(border: InputBorder.none, hintText: hint, hintStyle: TextStyle(color: pal.sub.withValues(alpha: .7)), isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        ?trailing,
      ]),
    );
  }

  Widget _dupBanner(Pal pal) {
    const ink = Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: ink.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded, color: ink, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final m in _matches) ...[
              Text(_matchText(m), style: TextStyle(color: pal.text, fontSize: 13.5, height: 1.4)),
              Wrap(spacing: 4, children: [
                if (m['visible'] == true && widget.company != null && m['kind'] == 'person')
                  TextButton(onPressed: () => _linkMatch(m), child: Text(tr('Gắn người này vào công ty'))),
                if (m['visible'] != true) TextButton(onPressed: () => _requestShare(m), child: Text(tr('Xin chia sẻ'))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
