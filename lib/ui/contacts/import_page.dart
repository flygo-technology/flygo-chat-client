// Nhập danh bạ khách từ file: Excel (.xlsx), CSV, vCard (.vcf, danh bạ điện thoại / Gmail xuất ra).
// Bước: chọn file → ghép cột (app đoán sẵn) + áp chung cho cả file → xem trước từng dòng (mới / gộp / có thể trùng / lỗi) → nhập.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'api.dart';
import 'look.dart';

/// Trường đích khi ghép cột.
const _fields = <String, String>{
  'skip': 'Bỏ qua',
  'name': 'Tên công ty / họ tên',
  'full_name': 'Tên đầy đủ',
  'tax_id': 'MST',
  'phone': 'Điện thoại',
  'email': 'Email',
  'address': 'Địa chỉ',
  'contact_name': 'Người liên hệ – tên',
  'contact_phone': 'Người liên hệ – điện thoại',
  'contact_email': 'Người liên hệ – email',
  'contact_title': 'Người liên hệ – chức danh',
  'job_title': 'Chức danh',
  'owner': 'Người phụ trách',
  'tags': 'Nhãn',
  'website': 'Website',
  'country': 'Quốc gia',
  'external_id': 'Mã ở hệ khác',
  'notes': 'Ghi chú',
};

String _fold(String s) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().characters) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().trim();
}

/// Đoán trường theo tên cột.
String guessField(String header) {
  final h = _fold(header);
  bool has(List<String> w) => w.any(h.contains);
  if (has(['mst', 'ma so thue', 'tax'])) return 'tax_id';
  if (has(['nguoi lien he', 'nguoi lh', 'contact'])) {
    if (has(['dien thoai', 'sdt', 'dt', 'phone', 'mobile'])) return 'contact_phone';
    if (has(['email', 'mail'])) return 'contact_email';
    if (has(['chuc', 'title'])) return 'contact_title';
    return 'contact_name';
  }
  if (has(['ten day du', 'ten dkkd', 'ten dang ky', 'full name'])) return 'full_name';
  if (has(['ten', 'name', 'khach hang', 'cong ty', 'company', 'ho va ten'])) return 'name';
  if (has(['dien thoai', 'sdt', 'phone', 'mobile', 'di dong', 'tel']) || h == 'dt') return 'phone';
  if (has(['email', 'mail'])) return 'email';
  if (has(['dia chi', 'address', 'd/c', 'dc'])) return 'address';
  if (has(['chuc vu', 'chuc danh', 'title', 'position'])) return 'job_title';
  if (has(['sales', 'phu trach', 'nhan vien', 'owner', 'nvkd'])) return 'owner';
  if (has(['nhan', 'tag', 'nhom'])) return 'tags';
  if (has(['website', 'web'])) return 'website';
  if (has(['quoc gia', 'country'])) return 'country';
  if (has(['ma kh', 'ma khach', 'ma ncc', 'code', 'id'])) return 'external_id';
  if (has(['ghi chu', 'note', 'mo ta'])) return 'notes';
  return 'skip';
}

// ------------------------------------------------------------------ đọc file
/// CSV: tự nhận dấu phân cách (, ; tab), có ngoặc kép, bỏ BOM.
List<List<String>> parseCsv(String text) {
  text = text.replaceFirst('﻿', '');
  final first = text.split('\n').first;
  final sep = [';', '\t', ','].reduce((a, b) => first.split(a).length >= first.split(b).length ? a : b);
  final rows = <List<String>>[];
  var row = <String>[], cell = StringBuffer(), quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell = StringBuffer();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell = StringBuffer();
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  row.add(cell.toString());
  if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
  return rows;
}

/// Excel .xlsx: trang tính đầu tiên (đọc thẳng XML trong file zip).
List<List<String>> parseXlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? read(String name) {
    final f = zip.findFile(name);
    return f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final shared = <String>[];
  final ss = read('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  // Trang đầu theo workbook.xml (r:id → đường dẫn trong workbook.xml.rels); không đọc được thì lấy sheet1.xml.
  var sheetPath = 'xl/worksheets/sheet1.xml';
  try {
    final wb = XmlDocument.parse(read('xl/workbook.xml')!);
    final rid = wb.findAllElements('sheet').first.attributes.firstWhere((a) => a.name.local == 'id').value;
    final rels = XmlDocument.parse(read('xl/_rels/workbook.xml.rels')!);
    final target = rels.findAllElements('Relationship').firstWhere((r) => r.getAttribute('Id') == rid).getAttribute('Target')!;
    sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/$target';
  } catch (_) {}
  final sheet = read(sheetPath) ?? read('xl/worksheets/sheet1.xml');
  if (sheet == null) throw FormatException(tr('Không đọc được trang tính trong file Excel'));
  int col(String ref) {
    var n = 0;
    for (final ch in ref.codeUnits) {
      if (ch < 65 || ch > 90) break;
      n = n * 26 + (ch - 64);
    }
    return n - 1;
  }

  final rows = <List<String>>[];
  for (final r in XmlDocument.parse(sheet).findAllElements('row')) {
    final cells = <int, String>{};
    for (final c in r.findElements('c')) {
      final ref = c.getAttribute('r') ?? '';
      final t = c.getAttribute('t');
      String v;
      if (t == 'inlineStr') {
        v = c.findAllElements('t').map((e) => e.innerText).join();
      } else {
        final raw = c.getElement('v')?.innerText ?? '';
        v = t == 's' ? (int.tryParse(raw) != null && int.parse(raw) < shared.length ? shared[int.parse(raw)] : '') : raw;
        // Số điện thoại / MST lưu dạng số: bỏ ".0" của Excel.
        if (t == null && RegExp(r'^\d+\.0$').hasMatch(v)) v = v.substring(0, v.length - 2);
      }
      cells[ref.isEmpty ? cells.length : col(ref)] = v;
    }
    if (cells.isEmpty) continue;
    final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    final row = List<String>.generate(width, (i) => cells[i] ?? '');
    if (row.any((s) => s.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}

/// vCard: mỗi thẻ thành một dòng đã ghép sẵn (có ORG thì là công ty + người liên hệ, không thì là người).
List<Map<String, dynamic>> parseVcf(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n[ \t]'), '').split('\n');
  final out = <Map<String, dynamic>>[];
  Map<String, List<String>>? cur;
  String unesc(String s) => s.replaceAll(r'\n', ' ').replaceAll(r'\,', ',').replaceAll(r'\;', ';').replaceAll(r'\\', r'\').trim();
  for (final line in lines) {
    final i = line.indexOf(':');
    if (i < 0) continue;
    final keyPart = line.substring(0, i);
    final key = keyPart.split(';').first.split('.').last.toUpperCase();
    final value = line.substring(i + 1);
    if (key == 'BEGIN') {
      cur = {};
    } else if (key == 'END' && cur != null) {
      String one(String k) => (cur![k] ?? const []).firstWhere((s) => s.isNotEmpty, orElse: () => '');
      var name = one('FN');
      if (name.isEmpty) name = one('N').split(';').where((s) => s.isNotEmpty).toList().reversed.join(' ');
      final org = one('ORG').split(';').first;
      final phones = cur['TEL'] ?? const [], emails = cur['EMAIL'] ?? const [];
      final adr = (cur['ADR'] ?? const []).map((a) => a.split(';').where((s) => s.trim().isNotEmpty).join(', ')).where((s) => s.isNotEmpty).toList();
      if (org.isNotEmpty && name.isNotEmpty && org != name) {
        out.add({'kind': 'company', 'name': org, 'contact_name': name, 'contact_phone': phones, 'contact_email': emails, 'contact_title': one('TITLE'), 'address': adr});
      } else if (name.isNotEmpty || org.isNotEmpty) {
        out.add({'kind': name.isEmpty ? 'company' : 'person', 'name': name.isEmpty ? org : name, 'phones': phones, 'emails': emails, 'job_title': one('TITLE'), 'address': adr,
          'notes': one('NOTE')});
      }
      cur = null;
    } else if (cur != null) {
      (cur[key] ??= []).add(unesc(value));
    }
  }
  return out;
}

// ------------------------------------------------------------------ trang nhập
class ContactsImportPage extends StatefulWidget {
  const ContactsImportPage({super.key, required this.api, required this.me});
  final ContactsApi api;
  final Map<String, dynamic> me;
  @override
  State<ContactsImportPage> createState() => _ContactsImportPageState();
}

class _ContactsImportPageState extends State<ContactsImportPage> {
  String? _fileName;
  List<String> _header = [];
  List<List<String>> _table = [];
  List<Map<String, dynamic>>? _vcf; // vCard: dòng đã ghép sẵn
  List<String> _map = [];
  String _kind = 'company';
  final Set<String> _types = {'customer'};
  String _scope = 'dept';
  String? _dept;
  final _tags = TextEditingController();
  Map<String, dynamic>? _preview;
  final Map<int, String> _actions = {}; // dòng → new | skip | merge:<id>
  bool _busy = false;
  Map<String, dynamic>? _done;

  List<Map<String, dynamic>> get _depts => [for (final d in (widget.me['my_depts'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];

  @override
  void initState() {
    super.initState();
    _dept = _depts.isEmpty ? null : '${_depts.first['id']}';
    if (_dept == null) _scope = 'private';
    final now = DateTime.now();
    _tags.text = tr('Nhập {0}/{1}', [now.day, now.month]);
  }

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    List<PlatformFile> res;
    try {
      res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'csv', 'vcf', 'txt']);
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không mở được hộp chọn tệp: {0}', ['$e']))));
      return;
    }
    final f = res.firstOrNull;
    if (f == null) return;
    try {
      final bytes = f.path == null ? null : await File(f.path!).readAsBytes();
      if (bytes == null) return;
      final ext = (f.extension ?? '').toLowerCase();
      setState(() { _preview = null; _done = null; _actions.clear(); _vcf = null; });
      if (ext == 'vcf') {
        final cards = parseVcf(utf8.decode(bytes, allowMalformed: true));
        if (cards.isEmpty) throw FormatException(tr('File không có danh thiếp nào'));
        setState(() { _fileName = f.name; _vcf = cards; _header = []; _table = []; });
        return;
      }
      final rows = ext == 'xlsx' ? parseXlsx(bytes) : parseCsv(utf8.decode(bytes, allowMalformed: true));
      if (rows.length < 2) throw FormatException(tr('File cần có dòng tiêu đề và ít nhất một dòng dữ liệu'));
      setState(() {
        _fileName = f.name;
        _header = rows.first.map((s) => s.trim()).toList();
        _table = rows.skip(1).toList();
        _map = [for (final h in _header) guessField(h)];
        // Tên cột "Họ tên" mà không có MST: nhiều khả năng là danh sách người.
        _kind = !_map.contains('tax_id') && _header.any((h) => _fold(h).contains('ho ten') || _fold(h).contains('ho va ten')) ? 'person' : 'company';
      });
    } catch (e) {
      messenger.showSnackBar(toast(Text(tr('Không đọc được file: {0}', [e]))));
    }
  }

  List<Map<String, dynamic>> _rows() {
    if (_vcf != null) return [for (var i = 0; i < _vcf!.length; i++) {..._vcf![i], if (_actions[i] != null) 'action': _actions[i]}];
    final out = <Map<String, dynamic>>[];
    for (var r = 0; r < _table.length; r++) {
      final row = _table[r];
      final m = <String, dynamic>{'kind': _kind};
      for (var i = 0; i < _map.length && i < row.length; i++) {
        final f = _map[i], v = row[i].trim();
        if (f == 'skip' || v.isEmpty) continue;
        if (f == 'phone' || f == 'email' || f == 'contact_phone' || f == 'contact_email') {
          // Một ô có thể chứa nhiều số / email cách nhau bằng , ; / hoặc xuống dòng.
          final parts = v.split(RegExp(r'[,;/\n]+')).map((s) => s.trim()).where((s) => s.isNotEmpty);
          (m[f == 'phone' ? 'phones' : f == 'email' ? 'emails' : f] ??= <String>[]).addAll(parts);
        } else if (m[f] != null && f == 'notes') {
          m[f] = '${m[f]}\n$v';
        } else {
          m[f] = v;
        }
      }
      if (_actions[r] != null) m['action'] = _actions[r];
      out.add(m);
    }
    return out;
  }

  Map<String, dynamic> get _defaults => {
        'types': _types.toList(),
        'scope': _scope,
        if (_scope == 'dept') 'dept': _dept,
        'tags': _tags.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'source': tr('Nhập file {0}', [_fileName ?? '']),
        'external_key': 'import',
      };

  Future<void> _run(bool dry) async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.post('/api/import', {'rows': _rows(), 'defaults': _defaults, 'dry_run': dry});
      setState(() => dry ? _preview = r : _done = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(title: Text(tr('Nhập khách từ file'))),
      body: Column(children: [
        if (_busy) LinearProgressIndicator(color: pal.accent, minHeight: 2),
        Expanded(child: _done != null ? _doneView(pal) : _fileName == null ? _start(pal) : _preview != null ? _previewView(pal) : _mapView(pal)),
      ]),
    );
  }

  Widget _start(Pal pal) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.upload_file_rounded, size: 56, color: pal.accentText),
            const SizedBox(height: 12),
            Text(tr('Chọn file Excel (.xlsx), CSV hoặc vCard (.vcf)'), textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: pal.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(tr('Dòng đầu của Excel / CSV là tiêu đề cột. Danh bạ điện thoại: vào app Danh bạ → Chia sẻ / Xuất ra file .vcf.'),
                textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.folder_open_rounded), label: Text(tr('Chọn file'))),
          ]),
        ),
      );

  Widget _mapView(Pal pal) {
    final count = _vcf?.length ?? _table.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: Text('$_fileName · ${tr('{0} dòng', [count])}', style: TextStyle(color: pal.sub))),
        TextButton(onPressed: _pick, child: Text(tr('Đổi file'))),
      ]),
      if (_vcf == null) ...[
        SectionTitle(tr('Ghép cột')),
        CardBox(children: [
          Row(children: [
            Expanded(child: Text(tr('Mỗi dòng là'), style: TextStyle(color: pal.sub))),
            SegmentedButton<String>(
              segments: [ButtonSegment(value: 'company', label: Text(tr('Công ty'))), ButtonSegment(value: 'person', label: Text(tr('Người')))],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          ]),
          for (var i = 0; i < _header.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.divider, width: .6))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_header[i].isEmpty ? tr('(cột {0})', [i + 1]) : _header[i], style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                    Text(_table.map((r) => i < r.length ? r[i] : '').firstWhere((s) => s.trim().isNotEmpty, orElse: () => '—'),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub)),
                  ]),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 16),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _map[i],
                  underline: const SizedBox.shrink(),
                  items: [for (final e in _fields.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value), style: TextStyle(color: e.key == 'skip' ? pal.sub : pal.text)))],
                  onChanged: (v) => setState(() => _map[i] = v ?? 'skip'),
                ),
              ]),
            ),
        ]),
      ] else
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('{0} danh thiếp: có tên công ty thì nhập thành công ty + người liên hệ, không thì là khách lẻ.', [count]), style: TextStyle(color: pal.sub))),
      SectionTitle(tr('Áp cho cả file')),
      CardBox(padding: const EdgeInsets.all(14), children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final t in const ['customer', 'lead', 'supplier', 'partner'])
            FilterChip(label: Text(typeLabel(t)), selected: _types.contains(t), showCheckmark: false, onSelected: (v) => setState(() => v ? _types.add(t) : _types.remove(t))),
        ]),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'private', label: Text(tr('Riêng tôi'))),
            ButtonSegment(value: 'dept', label: Text(tr('Phòng ban')), enabled: _depts.isNotEmpty),
            ButtonSegment(value: 'company', label: Text(tr('Toàn công ty'))),
          ],
          selected: {_scope},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _scope = s.first),
        ),
        if (_scope == 'dept' && _depts.length > 1)
          DropdownButton<String>(
            value: _dept,
            items: [for (final d in _depts) DropdownMenuItem(value: '${d['id']}', child: Text('${d['name']}'))],
            onChanged: (v) => setState(() => _dept = v),
          ),
        TextField(controller: _tags, decoration: InputDecoration(labelText: tr('Gắn nhãn'), isDense: true)),
      ]),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy || (_vcf == null && !_map.contains('name')) ? null : () => _run(true),
        child: Text(_vcf == null && !_map.contains('name') ? tr('Cần ghép một cột vào "Tên"') : tr('Tiếp: kiểm tra trùng')),
      ),
    ]);
  }

  Widget _statusChip(String s) => switch (s) {
        'new' => TypeChip('supplier', label: tr('Mới')),
        'merge' => TypeChip('customer', label: tr('Gộp vào bản có sẵn')),
        'maybe' => TypeChip('lead', label: tr('Có thể trùng')),
        'share' => TypeChip('partner', label: tr('Đã có, chưa được xem')),
        'skip' => TypeChip('other', label: tr('Bỏ qua')),
        _ => TypeChip('agency', label: tr('Lỗi')),
      };

  Widget _previewView(Pal pal) {
    final p = _preview!;
    final results = [for (final r in p['results'] as List) Map<String, dynamic>.from(r as Map)];
    final sum = Map<String, dynamic>.from(p['summary'] as Map);
    final willImport = results.where((r) => r['status'] == 'new' || r['status'] == 'merge').length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in const ['new', 'merge', 'maybe', 'share', 'error', 'skip'])
            if (sum[k] != null) Row(mainAxisSize: MainAxisSize.min, children: [_statusChip(k), Text(' ${sum[k]}', style: TextStyle(color: pal.text))]),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: results.length,
          itemBuilder: (_, i) {
            final r = results[i];
            final row = (r['row'] as num).toInt();
            final m = r['match'] as Map?;
            final msg = '${r['message'] ?? ''}'.isNotEmpty
                ? '${r['message']}'
                : m == null
                    ? ''
                    : m['visible'] == true
                        ? tr('giống "{0}" ({1} phụ trách)', [m['name'], m['owner_name']])
                        : tr('đã có, do {0} phụ trách', [m['owner_name']]);
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider, width: .6))),
              child: Row(children: [
                SizedBox(width: 44, child: Text('${row + 2}', style: TextStyle(color: pal.sub, fontSize: 12.5))),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['name']}'.isEmpty ? '—' : '${r['name']}', style: TextStyle(fontWeight: FontWeight.w600, color: pal.text)),
                    if (msg.isNotEmpty) Text(msg, style: TextStyle(fontSize: 12.5, color: pal.sub)),
                  ]),
                ),
                if (r['status'] == 'maybe' || _actions[row] != null)
                  DropdownButton<String>(
                    value: _actions[row] ?? '',
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: '', child: Text(tr('Chưa chọn'))),
                      DropdownMenuItem(value: 'new', child: Text(tr('Tạo mới'))),
                      if (m != null && m['visible'] == true) DropdownMenuItem(value: 'merge:${m['id']}', child: Text(tr('Gộp vào bản có sẵn'))),
                      DropdownMenuItem(value: 'skip', child: Text(tr('Bỏ qua'))),
                    ],
                    onChanged: (v) => setState(() => v == null || v.isEmpty ? _actions.remove(row) : _actions[row] = v),
                  )
                else
                  _statusChip('${r['status']}'),
              ]),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            TextButton(onPressed: () => setState(() => _preview = null), child: Text(tr('Quay lại'))),
            const Spacer(),
            if (_actions.isNotEmpty) TextButton(onPressed: _busy ? null : () => _run(true), child: Text(tr('Kiểm tra lại'))),
            FilledButton(
              onPressed: _busy || willImport == 0 && _actions.isEmpty ? null : () => _run(false),
              child: Text(tr('Nhập {0} dòng', [willImport + _actions.values.where((v) => v != 'skip').length])),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _doneView(Pal pal) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_rounded, size: 56, color: Color(0xFF16A34A)),
            const SizedBox(height: 12),
            Text(tr('Đã nhập: {0} mới, {1} gộp vào bản có sẵn', [_done!['created'], _done!['merged']]), textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: pal.text)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Xong'))),
          ]),
        ),
      );
}
