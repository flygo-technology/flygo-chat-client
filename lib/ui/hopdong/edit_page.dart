// Hợp đồng: soạn / sửa hợp đồng — tệp PDF, số / tên / giá trị, "Ai ký?" (thẻ từng bên: nhãn, tên, MST/CCCD, email),
// lần lượt / cùng lúc, thời hạn (hiệu lực, hạn ký, nhắc gia hạn), ghi chú, tiến độ luồng ký và thanh dưới Lưu nháp / Gửi ký.
// Sau khi gửi ký máy chủ chỉ cho sửa ghi chú, công khai ghi chú và nhắc gia hạn: các phần khác khoá lại.
// Thẻ "Tài liệu ký": nhiều PDF (tối đa 10) — thêm từ Drive / từ máy (máy tính kéo thả được), kéo để sắp xếp, nhãn, bên ký
// của từng tài liệu. Thêm / thay tệp đi qua đường /docs; thứ tự, nhãn, bên ký lưu cùng hợp đồng (PUT docs).
// Máy chủ cũ chỉ có một tài liệu: thẻ chỉ hiện một tệp, chọn tệp mới là thay tệp cũ.

import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart' show isDesktop;
import '../drive/session.dart' show localCopy;
import '../drive/pickers.dart' show pickFromDrive;
import 'api.dart';
import 'detail_page.dart' show openPdf;
import 'look.dart';
import 'model.dart';

class _PartyDraft {
  _PartyDraft({this.id, String label = '', String name = '', String idNo = '', String email = '', this.kind = 'mst', this.internal = false})
      : label = TextEditingController(text: label),
        name = TextEditingController(text: name),
        idNo = TextEditingController(text: idNo),
        email = TextEditingController(text: email);
  factory _PartyDraft.of(HdParty p) =>
      _PartyDraft(id: p.id, label: p.label, name: p.name, idNo: p.idNo, email: p.email, kind: p.idKind, internal: p.internal);
  String? id;
  final TextEditingController label, name, idNo, email;
  String kind;
  bool internal;
  final key = UniqueKey();

  bool get valid => validId(kind, idNo.text);
  Json toJson() => {
        'id': ?id, 'label': label.text.trim(), 'name': name.text.trim(), 'id_kind': kind, 'id_no': idNo.text.replaceAll(RegExp(r'\s+'), ''),
        'email': email.text.trim(), 'internal': internal,
      };
  void dispose() {
    label.dispose();
    name.dispose();
    idNo.dispose();
    email.dispose();
  }
}

/// Tài liệu đang soạn: tệp trên máy chủ + nhãn, bên ký (null = tất cả các bên, kể cả bên thêm sau) chưa lưu.
class _DocDraft {
  _DocDraft(this.src, {required this.label, this.signers});
  final HdDoc src;
  String label;
  Set<_PartyDraft>? signers;

  bool signs(_PartyDraft p) => signers == null || signers!.contains(p);
  String get title => label.trim().isEmpty ? src.title : label.trim();
}

/// Tệp PDF đã chọn trong Drive: đường dẫn + tên, cách xin vé Drive và cách tải về máy (dự phòng cho máy chủ cũ).
class HdDrivePick {
  HdDrivePick({required this.path, required this.name, required this.ticket, required this.download});
  final String path, name;
  final Future<String> Function() ticket;
  final Future<Uint8List> Function() download;
}

class ContractEditPage extends StatefulWidget {
  const ContractEditPage({super.key, required this.api, this.initial});
  final HopdongApi api;

  /// Kiểm thử: thay hộp chọn Drive.
  @visibleForTesting
  static Future<HdDrivePick?> Function(BuildContext context)? debugDrivePicker;

  /// null = hợp đồng mới (tạo khi lưu lần đầu hoặc khi chọn PDF).
  final Contract? initial;
  @override
  State<ContractEditPage> createState() => _ContractEditPageState();
}

class _ContractEditPageState extends State<ContractEditPage> {
  Contract? _c;
  final _no = TextEditingController(), _title = TextEditingController(), _value = TextEditingController(), _note = TextEditingController();
  final _add = TextEditingController();
  final List<_PartyDraft> _parties = [];
  final List<_DocDraft> _docs = [];
  String _mode = 'seq';
  DateTime? _effFrom, _effTo, _deadline;
  int? _effMonths; // 6 / 12 / 24; 0 = tuỳ chọn
  int? _signDays; // 3 / 7 / 14
  bool _remind = true, _notePublic = false;
  bool _saving = false, _dirty = false, _uploading = false, _dropping = false;
  String _uploadText = '';
  DateTime? _savedAt;
  String _company = '';

  bool get _locked => _c != null && !_c!.isDraft;

  /// Máy chủ nhận nhiều tài liệu (chưa tạo hợp đồng thì coi như có).
  bool get _multi => _c?.multi ?? true;

  static const _maxDocs = 10, _maxBytes = 30 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    if (c != null) {
      _load(c);
    } else {
      _effMonths = 12;
      _effFrom = _today();
      _effTo = _addMonths(_effFrom!, 12);
      _signDays = 7;
      _deadline = _deadlineIn(7);
      _parties.addAll([_PartyDraft(label: 'Bên A'), _PartyDraft(label: 'Bên B', internal: true)]);
    }
    for (final t in [_no, _title, _value, _note]) {
      t.addListener(_touch);
    }
    widget.api.me().then((m) {
      if (!mounted) return;
      _company = m.company;
      // Hợp đồng mới: bên mình điền sẵn tên công ty.
      if (widget.initial == null && _company.isNotEmpty) {
        for (final p in _parties.where((p) => p.internal && p.name.text.isEmpty)) {
          p.name.text = _company;
        }
        setState(() {});
      }
    }, onError: (_) {});
  }

  void _load(Contract c) {
    _c = c;
    _no.text = c.no;
    _title.text = c.title;
    _value.text = c.value == null ? '' : groupDigits(c.value!);
    _note.text = c.note;
    _mode = c.mode;
    _effFrom = c.effFrom == null ? null : DateTime.fromMillisecondsSinceEpoch(c.effFrom!);
    _effTo = c.effTo == null ? null : DateTime.fromMillisecondsSinceEpoch(c.effTo!);
    _effMonths = null;
    if (_effFrom != null && _effTo != null) {
      for (final m in [6, 12, 24]) {
        if (_sameDay(_addMonths(_effFrom!, m), _effTo!)) _effMonths = m;
      }
      _effMonths ??= 0;
    }
    _deadline = c.signDeadline == null ? null : DateTime.fromMillisecondsSinceEpoch(c.signDeadline!);
    _signDays = null;
    _remind = c.remindDays > 0;
    _notePublic = c.notePublic;
    for (final p in _parties) {
      p.dispose();
    }
    _parties
      ..clear()
      ..addAll(c.parties.map(_PartyDraft.of));
    _loadDocs(c);
  }

  /// Tài liệu theo bản máy chủ trả về; bên ký (id) gắn vào thẻ bên đang soạn.
  void _loadDocs(Contract c) {
    _docs
      ..clear()
      ..addAll(c.docs.map((d) => _DocDraft(d,
          label: d.label, signers: d.signers == null ? null : {for (final p in _parties) if (p.id != null && d.signers!.contains(p.id)) p})));
  }

  /// Giữ ô đang gõ, chỉ gắn id máy chủ cấp cho bên mới (cùng thứ tự).
  void _bindIds(Contract n) {
    if (_parties.length != n.parties.length) return;
    for (var i = 0; i < _parties.length; i++) {
      _parties[i].id ??= n.parties[i].id;
    }
  }

  @override
  void dispose() {
    for (final t in [_no, _title, _value, _note, _add]) {
      t.dispose();
    }
    for (final p in _parties) {
      p.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  // ------------------------------------------------------------ ngày
  static DateTime _today() {
    final n = hdNow();
    return DateTime(n.year, n.month, n.day);
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Cộng [m] tháng rồi lùi một ngày: 01/12/2026 + 12 tháng → 30/11/2027.
  static DateTime _addMonths(DateTime d, int m) => DateTime(d.year, d.month + m, d.day).subtract(const Duration(days: 1));

  static DateTime _deadlineIn(int days) {
    final t = _today().add(Duration(days: days));
    return DateTime(t.year, t.month, t.day, 17);
  }

  static String _d(DateTime? d) => d == null ? '' : dmy(d.millisecondsSinceEpoch);

  // ------------------------------------------------------------ lưu / gửi
  Json _body() {
    if (_locked) return {'note': _note.text, 'note_public': _notePublic, 'remind_days': _remind ? 30 : 0};
    return {
      'no': _no.text.trim(), 'title': _title.text.trim(), 'value': parseMoney(_value.text), 'currency': _c?.currency ?? 'VND',
      'eff_from': _effFrom?.millisecondsSinceEpoch, 'eff_to': _effTo?.millisecondsSinceEpoch, 'sign_deadline': _deadline?.millisecondsSinceEpoch,
      'remind_days': _remind ? 30 : 0, 'note': _note.text, 'note_public': _notePublic, 'mode': _mode,
      'parties': [for (var i = 0; i < _parties.length; i++) {..._parties[i].toJson(), if (_parties[i].label.text.trim().isEmpty) 'label': defaultLabel(i)}],
      if (_c != null && _multi) 'docs': _docsJson(),
    };
  }

  /// Thứ tự, nhãn, bên ký của các tài liệu. Máy chủ xoá tài liệu không có trong danh sách; bên đã bỏ thì không gửi.
  List<Json> _docsJson() => [
        for (final d in _docs)
          if (d.src.id.isNotEmpty)
            {
              'id': d.src.id, 'label': d.label.trim(),
              'signers': d.signers == null ? null : [for (final p in _parties) if (d.signers!.contains(p) && p.id != null) p.id],
            },
      ];

  Future<Contract?> _save({bool quiet = false}) async {
    if (_saving) return null;
    setState(() => _saving = true);
    try {
      final body = _body();
      final docs = body.remove('docs');
      // Bên mới chưa có id mà có tài liệu chọn riêng bên ký: lưu các bên trước để có id, rồi mới lưu tài liệu.
      final twoStep = docs != null && _parties.any((p) => p.id == null) && _docs.any((d) => d.signers != null);
      var n = _c == null ? await widget.api.create(body) : await widget.api.update(_c!.id, twoStep ? body : {...body, 'docs': ?docs});
      if (twoStep) {
        _bindIds(n);
        n = await widget.api.update(n.id, {'docs': _docsJson()});
      }
      if (!mounted) return n;
      setState(() {
        _c = n;
        _bindIds(n);
        _loadDocs(n);
        _dirty = false;
        _savedAt = hdNow();
      });
      if (!quiet) hdToast(context, _locked ? 'Đã lưu ghi chú' : 'Đã lưu nháp');
      return n;
    } catch (e) {
      if (mounted) hdToast(context, '$e');
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Những gì còn thiếu trước khi gửi ký.
  /// Nhiều tài liệu: tài liệu nào cũng có người ký, bên nào cũng ký ít nhất một tài liệu (máy chủ cũng kiểm tra).
  List<String> _missing() => [
        if (_docs.isEmpty) 'tài liệu PDF',
        if (_parties.isEmpty) 'bên ký',
        if (_multi)
          for (final d in _docs)
            if (!_parties.any(d.signs)) 'bên ký của ${d.title}',
        for (var i = 0; i < _parties.length; i++) ...[
          if (_parties[i].name.text.trim().isEmpty) 'tên ${_label(i)}',
          if (!_parties[i].valid) '${_parties[i].kind == 'cccd' ? 'CCCD' : 'MST'} ${_label(i)}',
          if (_multi && _docs.isNotEmpty && _docCount(_parties[i]) == 0) 'tài liệu cho ${_label(i)} ký',
        ],
      ];

  /// Số tài liệu bên [p] ký.
  int _docCount(_PartyDraft p) => _docs.where((d) => d.signs(p)).length;

  String _label(int i) => _parties[i].label.text.trim().isEmpty ? defaultLabel(i) : _parties[i].label.text.trim();

  String get _sendText => _mode == 'par' || _parties.length == 1
      ? (_parties.length == 1 ? 'Gửi ký cho ${_label(0)}' : 'Gửi ký cho ${_parties.length} bên')
      : 'Gửi ký cho ${_label(0)}';

  Future<void> _send() async {
    final miss = _missing();
    if (miss.isNotEmpty) return hdToast(context, 'Còn thiếu: ${miss.join(', ')}');
    final who = _mode == 'par' ? 'tất cả ${_parties.length} bên cùng lúc' : '${_label(0)} (${_parties[0].name.text.trim()}) trước, các bên sau lần lượt';
    final ok = await hdConfirm(
      context,
      '$_sendText?',
      'Link ký sẽ mở cho $who${_docs.length > 1 ? ' · ${_docs.length} tài liệu' : ''}. Hạn ký: ${_deadline == null ? '7 ngày' : dmyHm(_deadline!.millisecondsSinceEpoch)}.\n\n'
          'Sau khi gửi không sửa được tài liệu, các bên và thời hạn — chỉ sửa được ghi chú.',
      ok: 'Gửi ký',
    );
    if (!ok || !mounted) return;
    final saved = await _save(quiet: true);
    if (saved == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final n = await widget.api.send(saved.id);
      if (!mounted) return;
      hdToast(context, 'Đã gửi ký ${n.no.isEmpty ? '' : n.no}'.trim());
      Navigator.of(context).pop(n);
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Thêm PDF từ máy (chọn được nhiều tệp).
  Future<void> _pickLocal() async {
    if (_locked || _uploading) return;
    final files = <(String, Uint8List)>[];
    try {
      for (final f in await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'])) {
        files.add((f.name, await f.readAsBytes()));
      }
    } catch (e) {
      if (mounted) hdToast(context, 'Không mở được tệp: $e');
      return;
    }
    if (files.isNotEmpty && mounted) await _addFiles(files);
  }

  /// Máy tính: thả tệp vào thẻ tài liệu, chỉ nhận PDF.
  Future<void> _onDrop(List<(String, String)> dropped) async {
    setState(() => _dropping = false);
    if (_locked || _uploading) return;
    final pdfs = [for (final f in dropped) if (f.$2.toLowerCase().endsWith('.pdf')) f];
    if (pdfs.isEmpty) return hdToast(context, 'Chỉ nhận tệp PDF');
    final files = <(String, Uint8List)>[];
    try {
      for (final f in pdfs) {
        files.add((f.$2, await File(f.$1).readAsBytes()));
      }
    } catch (e) {
      if (mounted) hdToast(context, 'Không mở được tệp: $e');
      return;
    }
    if (mounted) await _addFiles(files);
  }

  /// Tải lần lượt các tệp lên: quá 30 MB thì bỏ qua, đủ 10 tài liệu thì thôi. Máy chủ cũ: tệp đầu thay tài liệu cũ.
  Future<void> _addFiles(List<(String, Uint8List)> files) async {
    final big = [for (final f in files) if (f.$2.length > _maxBytes) f.$1];
    if (big.isNotEmpty) hdToast(context, 'Bỏ qua tệp quá 30 MB: ${big.join(', ')}');
    var ok = [for (final f in files) if (f.$2.length <= _maxBytes) f];
    if (ok.isEmpty) return;
    if (_multi) {
      final room = _maxDocs - _docs.length;
      if (room <= 0) return hdToast(context, 'Tối đa $_maxDocs tài liệu');
      if (ok.length > room) hdToast(context, 'Chỉ thêm được $room tệp nữa (tối đa $_maxDocs tài liệu)');
      ok = ok.take(room).toList();
    }
    await _withUpload('Đang tải ${ok.first.$1} lên…', (id) async {
      if (!(_c?.multi ?? false)) return widget.api.uploadDoc(id, ok.first.$1, ok.first.$2);
      late Contract n;
      for (var i = 0; i < ok.length; i++) {
        if (i > 0 && mounted) setState(() => _uploadText = 'Đang tải ${ok[i].$1} lên (${i + 1}/${ok.length})…');
        n = await widget.api.addDoc(id, ok[i].$1, ok[i].$2);
        // Tệp nào lên xong hiện ngay trong danh sách.
        if (mounted) {
          setState(() {
            _c = n;
            _loadDocs(n);
          });
        }
      }
      return n;
    }, ok.length == 1 ? ok.first.$1 : '${ok.length} tệp');
  }

  /// Thêm PDF từ Drive: máy chủ Hợp đồng tự lấy tệp từ Drive (một lượt truyền trong máy chủ), không tải qua máy.
  /// Máy chủ chưa có đường lấy từ Drive (404 "không có" / 501) thì tải về máy rồi tải lên. Máy chủ cũ: thay tài liệu cũ.
  Future<void> _pickFromDrive() async {
    if (_locked || _uploading) return;
    if (_multi && _docs.length >= _maxDocs) return hdToast(context, 'Tối đa $_maxDocs tài liệu');
    final pick = await (ContractEditPage.debugDrivePicker ?? _drivePick)(context);
    if (pick == null || !mounted) return;
    await _withUpload('Đang lấy tệp từ Drive…', (id) async {
      final multi = _c?.multi ?? false;
      try {
        return multi
            ? await widget.api.addDocFromDrive(id, path: pick.path, name: pick.name, ticket: await pick.ticket())
            : await widget.api.docFromDrive(id, path: pick.path, name: pick.name, ticket: await pick.ticket());
      } on HopdongException catch (e) {
        final old = e.status == 501 || (e.status == 404 && !e.message.contains('Drive'));
        if (!old) rethrow;
        if (mounted) setState(() => _uploadText = 'Đang tải tệp từ Drive về máy…');
        final bytes = await pick.download();
        if (mounted) setState(() => _uploadText = 'Đang tải ${pick.name} lên…');
        return multi ? widget.api.addDoc(id, pick.name, bytes) : widget.api.uploadDoc(id, pick.name, bytes);
      }
    }, pick.name);
  }

  static Future<HdDrivePick?> _drivePick(BuildContext context) async {
    final r = await pickFromDrive(context, remoteOnly: true, extensions: const ['pdf'], single: true);
    final it = r?.remote.firstOrNull;
    final s = r?.session;
    if (it == null || s == null) return null;
    return HdDrivePick(
      path: it.path,
      name: it.name,
      // Vé Drive dạng chuỗi trần (không "Bearer") để máy chủ Hợp đồng gọi drive-gw thay người dùng.
      ticket: () async => (await s.api.auth())['Authorization']!.replaceFirst(RegExp(r'^Bearer\s+'), ''),
      download: () async => (await localCopy(s, it)).readAsBytes(),
    );
  }

  /// Thay tệp PDF của một tài liệu (bản mới, giữ nhãn và bên ký).
  Future<void> _replaceDoc(_DocDraft d) async {
    if (_locked || _uploading) return;
    (String, Uint8List) f;
    try {
      final r = (await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'])).firstOrNull;
      if (r == null) return;
      f = (r.name, await r.readAsBytes());
    } catch (e) {
      if (mounted) hdToast(context, 'Không mở được tệp: $e');
      return;
    }
    if (!mounted) return;
    if (f.$2.length > _maxBytes) return hdToast(context, 'Tệp quá 30 MB');
    final did = d.src.id;
    await _withUpload('Đang thay ${d.src.name}…', (id) => did.isEmpty ? widget.api.uploadDoc(id, f.$1, f.$2) : widget.api.replaceDoc(id, did, f.$1, f.$2), f.$1);
  }

  /// Gắn / thay tài liệu: lưu nháp trước nếu chưa có trên máy chủ hoặc còn thay đổi chưa lưu (thứ tự, nhãn, bên ký),
  /// hiện tiến trình trong thẻ tài liệu, khoá các nút trong lúc chạy.
  Future<void> _withUpload(String text, Future<Contract> Function(String id) run, String name) async {
    setState(() {
      _uploading = true;
      _uploadText = text;
    });
    try {
      final c = _c == null || _dirty ? await _save(quiet: true) : _c;
      if (c == null) return;
      final n = await run(c.id);
      if (!mounted) return;
      setState(() {
        _c = n;
        _loadDocs(n);
        if (_no.text.trim().isEmpty && n.no.isNotEmpty) _no.text = n.no;
        _savedAt = hdNow();
      });
      hdToast(context, 'Đã gắn tài liệu $name');
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Điện thoại: nút thêm tài liệu hỏi lấy từ máy hay từ Drive.
  Future<void> _choosePdf(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final pos = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final add = _multi ? 'Thêm' : 'Chọn';
    final v = await showMenu<String>(
      context: context,
      position: pos == null ? const RelativeRect.fromLTRB(100, 100, 100, 100) : RelativeRect.fromLTRB(pos.left, pos.bottom, pos.right, pos.bottom),
      items: [
        PopupMenuItem(value: 'local', child: ListTile(leading: const Icon(Icons.upload_file_rounded), title: Text('$add PDF trên máy'), dense: true)),
        PopupMenuItem(value: 'drive', child: ListTile(leading: const Icon(Icons.add_to_drive_rounded), title: Text('$add từ Drive'), dense: true)),
      ],
    );
    if (v == 'local') await _pickLocal();
    if (v == 'drive') await _pickFromDrive();
  }

  // ------------------------------------------------------------ tài liệu
  /// [to] đã tính sau khi bỏ tài liệu ở [from] ra (onReorderItem).
  void _reorderDoc(int from, int to) {
    if (to == from) return;
    setState(() {
      _docs.insert(to, _docs.removeAt(from));
      _dirty = true;
    });
  }

  void _docMenu(_DocDraft d, String a) {
    switch (a) {
      case 'label':
        _renameDoc(d);
      case 'replace':
        _replaceDoc(d);
      case 'view':
        if (_c != null) openPdf(context, widget.api, _c!, doc: d.src);
      case 'remove':
        _removeDoc(d);
    }
  }

  Future<void> _renameDoc(_DocDraft d) async {
    final ctl = TextEditingController(text: d.title);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nhãn tài liệu'),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'Hợp đồng chính, Phụ lục 01, Biên bản…')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Thôi')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Xong'))],
      ),
    );
    ctl.dispose();
    if (v != null && v.isNotEmpty && mounted) {
      setState(() {
        d.label = v;
        _dirty = true;
      });
    }
  }

  /// Bỏ một tài liệu: lưu ngay (máy chủ xoá tài liệu không còn trong danh sách); lỗi thì hiện lại như máy chủ.
  Future<void> _removeDoc(_DocDraft d) async {
    final ok = await hdConfirm(context, 'Xoá tài liệu?', '"${d.src.name}" sẽ bị bỏ khỏi hợp đồng.', ok: 'Xoá', danger: true);
    if (!ok || !mounted) return;
    setState(() {
      _docs.remove(d);
      _dirty = true;
    });
    final n = await _save(quiet: true);
    if (!mounted) return;
    if (n != null) {
      hdToast(context, 'Đã xoá ${d.src.name}');
    } else if (_c != null) {
      setState(() => _loadDocs(_c!));
    }
  }

  /// Chọn các bên ký một tài liệu (đánh dấu nhiều); chọn đủ các bên = tất cả (null).
  Future<void> _pickSigners(_DocDraft d) async {
    if (_locked || _parties.isEmpty) return;
    final picked = {for (final p in _parties) if (d.signs(p)) p};
    final r = await showDialog<Set<_PartyDraft>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Ai ký ${d.title}?'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < _parties.length; i++)
                CheckboxListTile(
                  value: picked.contains(_parties[i]),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(_label(i)),
                  subtitle: _parties[i].name.text.trim().isEmpty ? null : Text(_parties[i].name.text.trim(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onChanged: (v) => set(() {
                    if (v == true) {
                      picked.add(_parties[i]);
                    } else {
                      picked.remove(_parties[i]);
                    }
                  }),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => set(() => picked.addAll(_parties)), child: const Text('Tất cả các bên')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Thôi')),
            FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, picked), child: const Text('Xong')),
          ],
        ),
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      d.signers = r.length == _parties.length ? null : r;
      _dirty = true;
    });
  }

  /// Chữ trên chip bên ký: (chữ, chỉ một phần các bên?, chưa ai ký?).
  (String, bool, bool) _signersText(_DocDraft d) {
    final who = [for (var i = 0; i < _parties.length; i++) if (d.signs(_parties[i])) i];
    if (who.isEmpty) return ('Chưa chọn bên ký', true, true);
    if (who.length == _parties.length) {
      return (_parties.length == 1 ? '${_label(0)} ký' : _parties.length == 2 ? 'Cả 2 bên ký' : 'Tất cả các bên ký', false, false);
    }
    if (who.length == 1) return ('Chỉ ${_label(who.first)} ký', true, false);
    return ('${who.map(_label).join(', ')} ký', true, false);
  }

  Future<void> _deleteDraft() async {
    if (_c == null) return Navigator.of(context).pop();
    final ok = await hdConfirm(context, 'Xoá hợp đồng nháp?', '"${_c!.heading}" sẽ bị xoá hẳn, cùng tệp PDF đã tải lên.', ok: 'Xoá', danger: true);
    if (!ok) return;
    try {
      await widget.api.remove(_c!.id);
      if (mounted) Navigator.of(context).pop(_c);
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    }
  }

  // ------------------------------------------------------------ bên ký
  void _addParty([String idNo = '']) {
    if (_locked || _parties.length >= 10) return;
    final no = idNo.replaceAll(RegExp(r'\s+'), '');
    setState(() {
      _parties.add(_PartyDraft(label: defaultLabel(_parties.length), idNo: no, kind: guessKind(no)));
      _dirty = true;
    });
    _add.clear();
  }

  void _partyMenu(int i, String a) {
    final p = _parties[i];
    setState(() {
      switch (a) {
        case 'up':
          _parties.insert(i - 1, _parties.removeAt(i));
        case 'down':
          _parties.insert(i + 1, _parties.removeAt(i));
        case 'internal':
          p.internal = !p.internal;
          if (p.internal && p.name.text.trim().isEmpty) p.name.text = _company;
        case 'kind':
          p.kind = p.kind == 'cccd' ? 'mst' : 'cccd';
        case 'remove':
          // Bỏ bên này khỏi danh sách bên ký của các tài liệu.
          final gone = _parties.removeAt(i);
          for (final d in _docs) {
            d.signers?.remove(gone);
          }
          gone.dispose();
      }
      _dirty = true;
    });
  }

  Future<void> _renameLabel(int i) async {
    final ctl = TextEditingController(text: _parties[i].label.text);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nhãn bên ký'),
        content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(hintText: 'Bên A, Bên mua, Bên cho thuê…')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Thôi')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Xong'))],
      ),
    );
    ctl.dispose();
    if (v != null && mounted) {
      setState(() {
        _parties[i].label.text = v;
        _dirty = true;
      });
    }
  }

  // ------------------------------------------------------------ giao diện
  // Máy tính: gọn (chữ 13–14, ô nhập 34px, hàng bên ký ~60px, cột phải 312px, nội dung tối đa 1200px giữa màn hình).
  // Điện thoại: giữ cỡ to dễ bấm.
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final gap = SizedBox(height: wide ? 12 : 14);
      final left = [_infoCard(l, wide), gap, _docsCard(l, wide), gap, _partiesCard(l, wide), if (wide) ...[gap, _flowCard(l)]];
      final right = [_termCard(l, wide), if (wide && _multi && _docs.length > 1) ...[gap, _howCard(l)], gap, _noteCard(l, wide)];
      if (wide) return _desktop(l, left, right);
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (did, _) async {
          if (did) return;
          if (_dirty) await _save(quiet: true);
          if (context.mounted) Navigator.of(context).pop(_c);
        },
        child: Scaffold(
          backgroundColor: l.bg,
          body: SafeArea(
            bottom: false,
            child: Column(children: [
              _center(wide, _header(l, wide)),
              if (_locked) _center(wide, _lockedBanner(l, wide)),
              Expanded(
                child: wide
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: _center(
                          true,
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                            const SizedBox(width: 14),
                            SizedBox(width: 312, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
                          ]),
                        ),
                      )
                    : ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: [...left, const SizedBox(height: 14), ...right]),
              ),
              _bottomBar(l, wide),
            ]),
          ),
        ),
      );
    });
  }

  /// Máy tính (bản gọn Sếp duyệt): header có viền dưới; nội dung tối đa 1200px ở giữa; cột phải 310px với thẻ hành động
  /// (trạng thái + Lưu nháp / Gửi ký) luôn ở đầu, Thời hạn và Ghi chú cuộn bên dưới. Không có thanh dưới.
  Widget _desktop(HdLook l, List<Widget> left, List<Widget> right) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (did, _) async {
          if (did) return;
          if (_dirty) await _save(quiet: true);
          if (mounted) Navigator.of(context).pop(_c);
        },
        child: Scaffold(
          backgroundColor: l.bg,
          body: SafeArea(
            child: Column(children: [
              Container(
                decoration: BoxDecoration(color: l.nav, border: Border(bottom: BorderSide(color: l.border))),
                child: _center(true, _header(l, true)),
              ),
              if (_locked) Padding(padding: const EdgeInsets.only(top: 10), child: _center(true, _lockedBanner(l, true))),
              Expanded(
                child: _center(
                  true,
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 0, 20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 310,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14, right: 20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _actionCard(l),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );

  /// Thẻ hành động (máy tính): dòng trạng thái + Lưu nháp và nút chính ngoài cùng bên phải.
  Widget _actionCard(HdLook l) {
    final miss = _missing();
    final ready = miss.isEmpty;
    final busy = _saving || _uploading;
    final summary = [
      if (_docs.length > 1) '${_docs.length} tài liệu',
      '${_parties.length} bên',
      _mode == 'par' ? 'cùng lúc' : 'lần lượt',
      if (_deadline != null) 'hạn ${dm(_deadline!.millisecondsSinceEpoch)}',
    ].join(' · ');
    final (IconData icon, Color color, String text) = _locked
        ? (Icons.lock_outline_rounded, l.sub, 'Đã gửi ký · chỉ sửa ghi chú')
        : ready
            ? (Icons.check_circle_rounded, l.ok, 'Sẵn sàng gửi · $summary')
            : (Icons.error_outline_rounded, l.warn, 'Còn thiếu: ${miss.take(3).join(', ')}${miss.length > 3 ? '…' : ''}');
    return HdCard(
      pad: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: ready || _locked ? l.sub : l.warn, fontSize: 12.5, height: 1.35))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton(
            onPressed: busy ? null : () => _save(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: l.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(_locked ? 'Lưu ghi chú' : 'Lưu nháp', style: TextStyle(color: l.text, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          if (!_locked)
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _send,
                icon: const Icon(Icons.send_rounded, size: 15),
                label: Text(_sendText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: ready ? l.accent : l.accent.withValues(alpha: .55),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  /// Máy tính: nội dung rộng tối đa 1200px, ở giữa.
  Widget _center(bool wide, Widget child) =>
      wide ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: child)) : child;

  Widget _header(HdLook l, bool wide) {
    final saved = _savedAt ?? (_c?.updatedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(_c!.updatedAt!));
    final hm = saved == null ? null : '${saved.hour.toString().padLeft(2, '0')}:${saved.minute.toString().padLeft(2, '0')}';
    final title = _title.text.trim().isEmpty ? (_c == null ? 'Hợp đồng mới' : 'Hợp đồng chưa đặt tên') : _title.text.trim();
    final small = wide ? 12.0 : 13.5;
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 10 : 4, wide ? 6 : 8, wide ? 16 : 8, wide ? 6 : 8),
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          visualDensity: wide ? VisualDensity.compact : null,
          icon: Icon(wide ? Icons.arrow_back_rounded : Icons.close_rounded, color: l.sub, size: wide ? 20 : 24),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(_c == null ? 'Soạn hợp đồng' : (_locked ? 'Hợp đồng' : 'Sửa hợp đồng'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: small)),
              ),
              if (_c != null) ...[
                Text(' · ', style: TextStyle(color: l.sub, fontSize: small)),
                Flexible(child: StatusChip(_c!, now: hdNow(), size: wide ? 10.5 : 11)),
              ],
              if (hm != null)
                Flexible(child: Text(_dirty ? ' · chưa lưu' : ' · đã lưu $hm', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: small))),
            ]),
            const SizedBox(height: 1),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: wide ? 17 : 19, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (_c?.doc != null)
          wide
              ? HdAction(Icons.visibility_outlined, _c!.docs.length > 1 ? 'Xem tài liệu' : 'Xem PDF', small: true, onTap: () => openPdf(context, widget.api, _c!))
              : IconButton(tooltip: 'Xem tài liệu', onPressed: () => openPdf(context, widget.api, _c!), icon: Icon(Icons.visibility_outlined, color: l.sub)),
        if (!_locked)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: l.sub, size: wide ? 20 : 24),
            onSelected: (v) => v == 'delete' ? _deleteDraft() : null,
            itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(_c == null ? 'Bỏ hợp đồng này' : 'Xoá nháp'))],
          ),
      ]),
    );
  }

  Widget _lockedBanner(HdLook l, bool wide) => Container(
        margin: EdgeInsets.fromLTRB(wide ? 20 : 14, 0, wide ? 20 : 14, wide ? 0 : 10),
        padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 14, vertical: wide ? 8 : 10),
        decoration: BoxDecoration(color: l.warnSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, size: wide ? 16 : 18, color: l.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Hợp đồng đã gửi ký: tài liệu, các bên và thời hạn đã khoá. Chỉ sửa được ghi chú và nhắc gia hạn.',
                style: TextStyle(color: l.warn, fontSize: wide ? 12.5 : 13.5)),
          ),
        ]),
      );

  /// Ô nhập có nhãn. Máy tính: nhãn nhỏ phía trên + ô cao 34px; điện thoại: nhãn nổi trong ô.
  Widget _field(HdLook l, bool wide, String label, TextEditingController c, {String? hint, TextInputType? kb, List<TextInputFormatter>? fmt, String? suffix}) {
    if (wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: l.sub, fontSize: 12)),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: TextField(
            controller: c,
            enabled: !_locked,
            keyboardType: kb,
            inputFormatters: fmt,
            style: TextStyle(color: l.text, fontSize: 13, fontWeight: FontWeight.w400),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: l.field,
              hintText: hint,
              hintStyle: TextStyle(color: l.faint, fontSize: 13.5),
              suffixText: suffix,
              suffixStyle: TextStyle(color: l.sub, fontSize: 13.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: l.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: l.border)),
              disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: l.border.withValues(alpha: .5))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: l.accent)),
            ),
          ),
        ),
      ]);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: l.border.withValues(alpha: .6))),
      child: TextField(
        controller: c,
        enabled: !_locked,
        keyboardType: kb,
        inputFormatters: fmt,
        style: TextStyle(color: l.text, fontSize: 16.5, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: l.faint),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: TextStyle(color: l.sub, fontSize: 15),
          contentPadding: const EdgeInsets.only(top: 4, bottom: 2),
          suffixText: suffix,
          suffixStyle: TextStyle(color: l.text, fontSize: 16.5),
        ),
      ),
    );
  }

  /// Số / tên / giá trị hợp đồng.
  Widget _infoCard(HdLook l, bool wide) => HdCard(
        pad: EdgeInsets.all(wide ? 14 : 16),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 190, child: _field(l, true, 'Số hợp đồng', _no, hint: 'VD: HĐDV-2026/087')),
                const SizedBox(width: 10),
                Expanded(child: _field(l, true, 'Tên hợp đồng', _title, hint: 'VD: Bảo trì hệ thống 12 tháng')),
                const SizedBox(width: 10),
                SizedBox(width: 190, child: _valueField(l, true)),
              ])
            : Column(children: [
                _field(l, false, 'Số hợp đồng', _no, hint: 'VD: HĐDV-2026/087'),
                const SizedBox(height: 10),
                _field(l, false, 'Tên hợp đồng', _title, hint: 'VD: Bảo trì hệ thống 12 tháng'),
                const SizedBox(height: 10),
                _valueField(l, false),
              ]),
      );

  /// Thẻ "Tài liệu ký": tiêu đề "N file · M trang" + Từ Drive / Từ máy, danh sách tài liệu (kéo để sắp xếp), dòng tiến trình
  /// khi đang tải lên và dòng gợi ý thêm PDF. Máy tính: thả tệp vào thẻ là thêm.
  Widget _docsCard(HdLook l, bool wide) {
    final pages = _docs.fold<int>(0, (a, d) => a + (d.src.pages ?? 0));
    final count = _docs.isEmpty ? '' : '${_docs.length} file${pages > 0 ? ' · $pages trang' : ''}';
    final canAdd = !_locked && (_multi ? _docs.length < _maxDocs : true);
    final drag = _multi && !_locked && _docs.length > 1;
    final gap = wide ? 6.0 : 8.0;
    final head = Row(children: [
      Icon(Icons.folder_copy_outlined, size: wide ? 18 : 21, color: l.accentText),
      SizedBox(width: wide ? 8 : 10),
      Expanded(
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Tài liệu ký'),
            if (count.isNotEmpty) TextSpan(text: '  $count', style: TextStyle(color: l.sub, fontSize: wide ? 12 : 14, fontWeight: FontWeight.w500)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: l.text, fontSize: wide ? 14 : 17, fontWeight: FontWeight.w700),
        ),
      ),
      if (canAdd && wide) ...[
        HdAction(Icons.add_to_drive_outlined, 'Từ Drive', small: true, onTap: _uploading ? null : _pickFromDrive),
        const SizedBox(width: 6),
        HdAction(Icons.upload_file_rounded, 'Từ máy', small: true, onTap: _uploading ? null : _pickLocal),
      ],
      if (canAdd && !wide)
        Builder(
          builder: (b) => IconButton(
            tooltip: _multi ? 'Thêm tài liệu' : 'Chọn PDF',
            onPressed: _uploading ? null : () => _choosePdf(b),
            icon: Icon(_multi || _docs.isEmpty ? Icons.add_circle_outline_rounded : Icons.swap_horiz_rounded, color: l.accentText),
          ),
        ),
    ]);
    final rows = [for (var k = 0; k < _docs.length; k++) Padding(key: ValueKey('doc:${_docs[k].src.id}:$k'), padding: EdgeInsets.only(bottom: gap), child: _docRow(l, wide, k, drag))];
    final hintText = !_multi
        ? 'Chọn tệp PDF hợp đồng (bản chưa ký)'
        : '${isDesktop ? (_docs.isEmpty ? 'Kéo thả PDF vào đây' : 'Kéo thả thêm PDF vào đây') : 'Thêm PDF'} · tối đa $_maxDocs file, mỗi file ≤ 30 MB';
    final card = HdCard(
      pad: EdgeInsets.all(wide ? 14 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        SizedBox(height: wide ? 10 : 12),
        if (drag)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: _reorderDoc,
            children: rows,
          )
        else
          ...rows,
        if (_uploading)
          Container(
            height: wide ? 40 : 52,
            margin: EdgeInsets.only(bottom: gap),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: l.accentSoft.withValues(alpha: .5), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(child: Text(_uploadText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.accentText, fontSize: wide ? 12.5 : 14))),
            ]),
          )
        else if (canAdd && (_multi || _docs.isEmpty))
          Builder(
            builder: (b) => InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: wide ? _pickLocal : () => _choosePdf(b),
              child: Container(
                height: wide ? 34 : 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _dropping ? l.accentSoft : null,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _dropping ? l.accent : l.border, width: 1.2),
                ),
                child: Row(children: [
                  Icon(Icons.note_add_outlined, size: wide ? 17 : 20, color: l.accentText),
                  const SizedBox(width: 8),
                  Expanded(child: Text(hintText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: wide ? 12 : 13.5))),
                ]),
              ),
            ),
          ),
      ]),
    );
    if (!isDesktop || _locked) return card;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dropping = true),
      onDragExited: (_) => setState(() => _dropping = false),
      onDragDone: (d) => _onDrop([for (final f in d.files) (f.path, f.name)]),
      child: card,
    );
  }

  /// Một tài liệu: tay kéo, icon PDF, tên + nhãn, "4 trang · bản 3 · từ Drive /…", chip bên ký, menu.
  /// Điện thoại: chip bên ký xuống dưới dòng phụ.
  Widget _docRow(HdLook l, bool wide, int k, bool drag) {
    final d = _docs[k];
    final s = d.src;
    final label = d.title == s.name ? '' : d.title;
    final sub = [if (s.pages != null) '${s.pages} trang', if (s.rev > 1) 'bản ${s.rev}', s.fromText].where((x) => x.isNotEmpty).join(' · ');
    final (who, part, none) = _signersText(d);
    final fg = none ? l.red : (part ? l.warn : l.text);
    final chip = !_multi
        ? null
        : InkWell(
            onTap: _locked ? null : () => _pickSigners(d),
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: wide ? 26 : 30,
              padding: EdgeInsets.symmetric(horizontal: wide ? 9 : 11),
              decoration: BoxDecoration(
                color: none ? l.redSoft : (part ? null : l.card2),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: none ? l.red : (part ? l.warn : l.border)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(part ? Icons.person_outline_rounded : Icons.group_outlined, size: wide ? 15 : 17, color: none || part ? fg : l.sub),
                const SizedBox(width: 5),
                Flexible(child: Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: wide ? 12 : 13.5, fontWeight: FontWeight.w600))),
              ]),
            ),
          );
    final pill = _multi && label.isNotEmpty ? Pill(label.toUpperCase(), fg: k == 0 ? l.accentText : l.sub, bg: k == 0 ? l.accentSoft : l.card2, size: wide ? 10 : 11) : null;
    final box = wide ? 30.0 : 40.0;
    return Container(
      padding: EdgeInsets.fromLTRB(drag ? 2 : 10, wide ? 7 : 9, 0, wide ? 7 : 9),
      decoration: BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(10), border: Border.all(color: l.border)),
      child: Row(children: [
        if (drag)
          ReorderableDragStartListener(
            index: k,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child: Icon(Icons.drag_indicator_rounded, size: wide ? 18 : 22, color: l.faint)),
            ),
          ),
        Container(
          width: box,
          height: box,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(wide ? 7 : 10), border: Border.all(color: l.border)),
          child: Icon(Icons.picture_as_pdf_rounded, color: const Color(0xFFE5484D), size: wide ? 18 : 24),
        ),
        SizedBox(width: wide ? 10 : 12),
        Expanded(
          child: InkWell(
            onTap: _c == null ? null : () => openPdf(context, widget.api, _c!, doc: s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(s.name.isEmpty ? 'Chưa đặt tên' : s.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: wide ? 13 : 15, fontWeight: FontWeight.w600)),
                ),
                if (wide && pill != null) ...[const SizedBox(width: 6), pill],
              ]),
              SizedBox(height: wide ? 2 : 3),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: wide ? 11.5 : 13)),
              // Điện thoại: nhãn + chip bên ký xuống dòng riêng cho tên tệp đủ chỗ.
              if (!wide && (pill != null || chip != null)) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [?pill, ?chip]),
              ],
            ]),
          ),
        ),
        if (wide && chip != null) ...[const SizedBox(width: 8), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: chip)],
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: l.sub, size: wide ? 18 : 22),
          padding: EdgeInsets.zero,
          onSelected: (v) => _docMenu(d, v),
          itemBuilder: (_) => [
            if (_multi && !_locked) const PopupMenuItem(value: 'label', child: Text('Đổi nhãn')),
            if (!_locked) const PopupMenuItem(value: 'replace', child: Text('Thay file')),
            const PopupMenuItem(value: 'view', child: Text('Xem')),
            if (_multi && !_locked) const PopupMenuItem(value: 'remove', child: Text('Xoá')),
          ],
        ),
      ]),
    );
  }

  /// Máy tính, từ hai tài liệu: cách ký nhiều tài liệu.
  Widget _howCard(HdLook l) => HdCard(
        pad: const EdgeInsets.all(14),
        color: l.accentSoft.withValues(alpha: .6),
        borderColor: Colors.transparent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const HdCardTitle(Icons.info_outline_rounded, 'Cách ký nhiều tài liệu', size: 14),
          const SizedBox(height: 8),
          for (final t in const [
            'Mỗi bên mở 1 link, bấm ký 1 lần, hệ thống ký lần lượt từng file.',
            'Mỗi file có chữ ký số riêng, tải và kiểm tra riêng được.',
            'Hợp đồng hoàn tất khi mọi file đủ chữ ký.',
            'Sắp xếp kéo thả = thứ tự hiển thị cho đối tác.',
          ])
            Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $t', style: TextStyle(color: l.text, fontSize: 12.5, height: 1.45))),
        ]),
      );

  Widget _valueField(HdLook l, bool wide) => _field(l, wide, 'Giá trị', _value, hint: '0', kb: TextInputType.number, suffix: '₫', fmt: [
        FilteringTextInputFormatter.digitsOnly,
        TextInputFormatter.withFunction((o, n) {
          final v = parseMoney(n.text);
          final t = v == null ? '' : groupDigits(v);
          return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
        }),
      ]);

  Widget _modeSwitch(HdLook l, bool wide) {
    Widget seg(String v, String t) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: HdChip(t, selected: _mode == v, dense: true, small: wide, onTap: _locked ? () {} : () => setState(() {
                _mode = v;
                _dirty = true;
              })),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      seg('seq', 'Lần lượt'),
      seg('par', 'Cùng lúc'),
    ]);
  }

  Widget _partiesCard(HdLook l, bool wide) {
    return HdCard(
      pad: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HdCardTitle(Icons.groups_2_outlined, 'Ai ký?', size: wide ? 14 : 17, trailing: _modeSwitch(l, wide)),
        SizedBox(height: wide ? 12 : 16),
        for (var i = 0; i < _parties.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.only(left: wide ? 23 : 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(width: 2, height: wide ? 8 : 14, color: _mode == 'seq' ? l.border : Colors.transparent),
              ),
            ),
          wide ? _partyRowDesk(l, i) : _partyCard(l, i),
        ],
        if (!_locked && _parties.length < 10) ...[
          SizedBox(height: wide ? 10 : 14),
          _addRow(l, wide),
        ],
      ]),
    );
  }

  /// Mã số + gợi ý của một bên.
  (bool ok, String kind, Color color, String hint) _idState(HdLook l, _PartyDraft p) {
    final no = p.idNo.text.replaceAll(RegExp(r'\s+'), '');
    final ok = p.valid;
    final kind = p.kind == 'cccd' ? 'CCCD' : 'MST';
    final color = ok ? l.ok : (no.isEmpty ? l.sub : l.warn);
    final hint = ok
        ? (p.internal ? 'ký bằng token công ty' : 'chỉ token đúng $kind này ký được')
        : no.isEmpty
            ? 'Nhập $kind của bên ký'
            : (p.kind == 'cccd' ? 'CCCD phải đủ 12 số' : 'MST phải 10 số hoặc 10 số-3 số');
    return (ok, kind, color, hint);
  }

  Widget _idInput(HdLook l, _PartyDraft p, Color color, double size) => IntrinsicWidth(
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: size * 6.2),
          child: TextField(
            controller: p.idNo,
            enabled: !_locked,
            onChanged: (_) => setState(() => _dirty = true),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), LengthLimitingTextInputFormatter(14)],
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size, fontFeatures: const [FontFeature.tabularFigures()]),
            decoration: InputDecoration.collapsed(hintText: p.kind == 'cccd' ? '12 số CCCD' : '10 số MST', hintStyle: TextStyle(color: l.faint, fontSize: size)),
          ),
        ),
      );

  Widget _partyMenuButton(HdLook l, int i, {double size = 24}) {
    final p = _parties[i];
    if (_locked) return const SizedBox(width: 8);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: l.sub, size: size),
      padding: EdgeInsets.zero,
      onSelected: (v) => v == 'label' ? _renameLabel(i) : _partyMenu(i, v),
      itemBuilder: (_) => [
        if (i > 0) const PopupMenuItem(value: 'up', child: Text('Lên trên')),
        if (i < _parties.length - 1) const PopupMenuItem(value: 'down', child: Text('Xuống dưới')),
        const PopupMenuItem(value: 'label', child: Text('Đổi nhãn')),
        PopupMenuItem(value: 'internal', child: Text(p.internal ? 'Không phải bên mình' : 'Đây là bên mình')),
        PopupMenuItem(value: 'kind', child: Text(p.kind == 'cccd' ? 'Dùng MST (tổ chức)' : 'Dùng CCCD (cá nhân)')),
        const PopupMenuItem(value: 'remove', child: Text('Bỏ bên này')),
      ],
    );
  }

  Widget _labelChip(HdLook l, int i, double size) {
    final p = _parties[i];
    final label = p.label.text.trim().isEmpty ? defaultLabel(i) : p.label.text.trim();
    return InkWell(
      onTap: _locked ? null : () => _renameLabel(i),
      child: Pill('${label.toUpperCase()}${p.internal ? ' · MÌNH' : ''}', fg: p.internal ? l.accentText : l.warn, bg: p.internal ? l.accentSoft : l.warnSoft, size: size),
    );
  }

  /// Hàng bên ký trên máy tính (~60px): vòng số 24, avatar 38, tên + nhãn, MST + gợi ý một dòng, email bên phải.
  /// "ký N tài liệu" dưới mỗi bên (null khi chưa có tài liệu / máy chủ cũ).
  String? _docHint(_PartyDraft p) {
    if (!_multi || _docs.isEmpty) return null;
    final n = _docCount(p);
    return n == 0 ? 'chưa ký tài liệu nào' : 'ký $n tài liệu';
  }

  Widget _partyRowDesk(HdLook l, int i) {
    final p = _parties[i];
    final (ok, kind, color, idHint) = _idState(l, p);
    final dh = _docHint(p);
    final none = dh != null && _docCount(p) == 0;
    final hint = ok && dh != null ? '$dh${p.internal ? ' · token công ty' : ''}' : idHint;
    final ring = i == 0 ? l.warn : l.accent;
    final label = p.label.text.trim().isEmpty ? defaultLabel(i) : p.label.text.trim();
    return Container(
      key: p.key,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(10), border: Border.all(color: l.border)),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 1.5)),
          child: Text('${i + 1}', style: TextStyle(color: ring, fontWeight: FontWeight.w700, fontSize: 11.5)),
        ),
        const SizedBox(width: 12),
        PartyAvatar(p.name.text.isEmpty ? label : p.name.text, index: p.internal ? 1 : 0, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(
                child: IntrinsicWidth(
                  child: TextField(
                    controller: p.name,
                    enabled: !_locked,
                    onChanged: (_) => _touch(),
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: l.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                    decoration: InputDecoration.collapsed(
                        hintText: p.internal ? 'Tên công ty mình' : 'Tên công ty / người ký', hintStyle: TextStyle(color: l.faint, fontWeight: FontWeight.w500, fontSize: 13.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _labelChip(l, i, 10),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(color: ok ? l.okSoft : l.card2, borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(ok ? Icons.verified_rounded : Icons.badge_outlined, size: 13, color: color),
                  const SizedBox(width: 4),
                  Text('$kind ', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                  _idInput(l, p, color, 12),
                ]),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ok ? (none ? l.warn : l.sub) : color, fontSize: 12))),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 190,
          child: Tooltip(
            message: 'Gửi link ký tới email này',
            child: TextField(
              controller: p.email,
              enabled: !_locked,
              onChanged: (_) => _touch(),
              textAlign: TextAlign.end,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: l.sub, fontSize: 12.5),
              decoration: InputDecoration.collapsed(hintText: 'email (không bắt buộc)', hintStyle: TextStyle(color: l.faint, fontSize: 12.5)),
            ),
          ),
        ),
        _partyMenuButton(l, i, size: 18),
      ]),
    );
  }

  /// Thẻ bên ký trên điện thoại.
  Widget _partyCard(HdLook l, int i) {
    final p = _parties[i];
    final (ok, _, color, hint) = _idState(l, p);
    final ringColor = i == 0 ? l.warn : l.accent;
    final label = p.label.text.trim().isEmpty ? defaultLabel(i) : p.label.text.trim();
    return Container(
      key: p.key,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ringColor, width: 2)),
          child: Text('${i + 1}', style: TextStyle(color: ringColor, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        const SizedBox(width: 12),
        PartyAvatar(p.name.text.isEmpty ? label : p.name.text, index: p.internal ? 1 : 0, size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: p.name,
              enabled: !_locked,
              onChanged: (_) => _touch(),
              textCapitalization: TextCapitalization.characters,
              minLines: 1,
              maxLines: 2,
              style: TextStyle(color: l.text, fontSize: 16.5, fontWeight: FontWeight.w700),
              decoration: InputDecoration.collapsed(
                  hintText: p.internal ? 'Tên công ty mình' : 'Tên công ty / người ký', hintStyle: TextStyle(color: l.faint, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
                decoration: BoxDecoration(color: ok ? l.okSoft : l.card2, borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(ok ? Icons.verified_rounded : Icons.badge_outlined, size: 18, color: color),
                  const SizedBox(width: 6),
                  Flexible(child: _idInput(l, p, color, 15.5)),
                ]),
              ),
              if (!ok) Text(hint, style: TextStyle(color: color, fontSize: 13)),
              if (_docHint(p) != null) Text(_docHint(p)!, style: TextStyle(color: _docCount(p) == 0 ? l.warn : l.sub, fontSize: 13)),
            ]),
          ]),
        ),
        _partyMenuButton(l, i),
      ]),
    );
  }

  Widget _addRow(HdLook l, bool wide) => Container(
        height: wide ? 38 : null,
        padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 18, vertical: wide ? 0 : 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(wide ? 10 : 16), border: Border.all(color: l.border, width: 1.2)),
        child: Row(children: [
          Icon(Icons.add_circle_outline_rounded, color: l.accentText, size: wide ? 18 : 24),
          SizedBox(width: wide ? 10 : 12),
          Expanded(
            child: TextField(
              controller: _add,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
              onSubmitted: _addParty,
              style: TextStyle(color: l.text, fontSize: wide ? 13.5 : 16),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: wide,
                hintText: 'Nhập MST để thêm bên ký',
                hintStyle: TextStyle(color: l.sub, fontSize: wide ? 13.5 : 16),
              ),
            ),
          ),
          TextButton(
            onPressed: () => _addParty(_add.text),
            style: wide ? TextButton.styleFrom(visualDensity: VisualDensity.compact) : null,
            child: Text(wide ? 'Thêm' : 'Thêm', style: TextStyle(color: l.sub, fontSize: wide ? 12.5 : null)),
          ),
        ]),
      );

  Widget _sectionLabel(HdLook l, bool wide, String t) =>
      Padding(padding: EdgeInsets.only(bottom: wide ? 6 : 10), child: Text(t, style: TextStyle(color: l.sub, fontSize: wide ? 12.5 : 15)));

  Widget _termCard(HdLook l, bool wide) {
    void eff(int m) {
      if (_locked) return;
      if (m == 0) {
        _pickRange();
        return;
      }
      setState(() {
        _effMonths = m;
        _effFrom ??= _today();
        _effTo = _addMonths(_effFrom!, m);
        _dirty = true;
      });
    }

    void sign(int d) {
      if (_locked) return;
      setState(() {
        _signDays = d;
        _deadline = _deadlineIn(d);
        _dirty = true;
      });
    }

    final range = _effFrom == null && _effTo == null ? 'Chưa đặt thời hạn hiệu lực' : '${_d(_effFrom)} → ${_d(_effTo)}';
    return HdCard(
      pad: EdgeInsets.all(wide ? 14 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HdCardTitle(Icons.schedule_rounded, 'Thời hạn', size: wide ? 14 : 17),
        SizedBox(height: wide ? 10 : 14),
        _sectionLabel(l, wide, 'Hiệu lực'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final m in [6, 12, 24]) HdChip(m == 12 || _effMonths == m ? '$m tháng' : '$m th', selected: _effMonths == m, dense: true, small: wide, onTap: () => eff(m)),
          HdChip(wide ? 'Tuỳ chọn' : 'Khác', selected: _effMonths == 0, dense: true, small: wide, onTap: () => eff(0)),
        ]),
        SizedBox(height: wide ? 8 : 12),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _locked ? null : _pickRange,
          child: Container(
            height: wide ? 34 : null,
            padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 0, vertical: wide ? 0 : 12),
            decoration: wide ? BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(8), border: Border.all(color: l.border)) : null,
            child: Row(children: [
              if (wide) ...[Icon(Icons.calendar_month_outlined, color: l.sub, size: 16), const SizedBox(width: 8)],
              Expanded(child: Text(range, style: TextStyle(color: l.text, fontSize: wide ? 13.5 : 17, fontWeight: FontWeight.w500))),
            ]),
          ),
        ),
        SizedBox(height: wide ? 12 : 16),
        _sectionLabel(l, wide, 'Hạn ký'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in [3, 7, 14]) HdChip('$d ngày', selected: _signDays == d, dense: true, small: wide, onTap: () => sign(d)),
        ]),
        if (_deadline != null) ...[
          SizedBox(height: wide ? 6 : 10),
          Text('${wide ? '' : '→ '}link hết hạn ${dmyHm(_deadline!.millisecondsSinceEpoch)}', style: TextStyle(color: l.sub, fontSize: wide ? 12 : 14.5)),
        ],
        SizedBox(height: wide ? 8 : 14),
        HdSwitchRow(
          small: wide,
          value: _remind,
          text: 'Nhắc gia hạn trước 30 ngày',
          onChanged: (v) => setState(() {
            _remind = v;
            _dirty = true;
          }),
        ),
      ]),
    );
  }

  Future<void> _pickRange() async {
    final now = _today();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
      initialDateRange: _effFrom != null && _effTo != null ? DateTimeRange(start: _effFrom!, end: _effTo!) : null,
      helpText: 'Hiệu lực hợp đồng',
    );
    if (r == null || !mounted) return;
    setState(() {
      _effFrom = r.start;
      _effTo = r.end;
      _effMonths = 0;
      for (final m in [6, 12, 24]) {
        if (_sameDay(_addMonths(r.start, m), r.end)) _effMonths = m;
      }
      _dirty = true;
    });
  }

  Widget _noteCard(HdLook l, bool wide) => HdCard(
        pad: EdgeInsets.all(wide ? 14 : 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HdCardTitle(Icons.sticky_note_2_outlined, 'Ghi chú', size: wide ? 14 : 17),
          SizedBox(height: wide ? 10 : 12),
          Container(
            padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 16, vertical: wide ? 8 : 12),
            decoration: BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(wide ? 8 : 12), border: wide ? Border.all(color: l.border) : null),
            child: TextField(
              controller: _note,
              minLines: wide ? 3 : 2,
              maxLines: 10,
              style: TextStyle(color: l.text, fontSize: wide ? 13.5 : 15.5, height: 1.4),
              decoration: InputDecoration.collapsed(hintText: 'Ghi chú nội bộ cho hợp đồng này…', hintStyle: TextStyle(color: l.faint, fontSize: wide ? 13.5 : null)),
            ),
          ),
          SizedBox(height: wide ? 8 : 12),
          HdSwitchRow(
            small: wide,
            value: _notePublic,
            text: 'Đối tác cũng thấy ghi chú này',
            onChanged: (v) => setState(() {
              _notePublic = v;
              _dirty = true;
            }),
          ),
        ]),
      );

  /// Tiến độ luồng ký (ngang, mảnh): Tạo & chốt → từng bên → Hoàn tất.
  Widget _flowCard(HdLook l) {
    final c = _c;
    final steps = <(HdStep, String, String, String)>[];
    final created = c?.doc != null;
    steps.add((created ? HdStep.done : HdStep.current, '', 'Tạo & chốt${c?.doc != null ? ' v${c!.doc!.rev}' : ''}',
        created ? '${dm(c!.updatedAt)}${c.ownerName.isNotEmpty ? ' · ${c.ownerName}' : ''}' : 'cần tệp PDF'));
    for (var i = 0; i < _parties.length; i++) {
      final p = c != null && i < c.parties.length && c.parties[i].id == _parties[i].id ? c.parties[i] : null;
      final st = p == null
          ? HdStep.todo
          : p.signed
              ? HdStep.done
              : p.status == 'rejected'
                  ? HdStep.rejected
                  : p.waitingTurn
                      ? HdStep.current
                      : HdStep.todo;
      final first = _mode == 'par' || i == 0;
      final name = _parties[i].name.text.trim();
      final sub = p?.signed == true
          ? 'đã ký ${dm(p!.signedAt)}'
          : (c?.isDraft ?? true)
              ? (first ? '${_label(i)} · chờ gửi' : '${_label(i)} · sau ${_label(i - 1)}')
              : _label(i);
      steps.add((st == HdStep.todo && first && created && (c?.isDraft ?? true) ? HdStep.current : st, '${i + 1}', name.isEmpty ? _label(i) : _short(name), sub));
    }
    steps.add((c?.status == 'signed' ? HdStep.done : HdStep.todo, '✓', 'Hoàn tất', 'gửi PDF cho ${_parties.length} bên'));
    return HdCard(
      pad: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HdCardTitle(Icons.route_outlined, 'Tiến độ luồng ký',
            size: 14, trailing: Text(c == null || c.isDraft ? 'Chưa gửi' : (kStatusLabels[c.status] ?? ''), style: TextStyle(color: l.sub, fontSize: 12.5))),
        const SizedBox(height: 10),
        // Một dòng: chấm 20px + tên bước, nối bằng vạch; chú thích của bước nằm trong tooltip.
        Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: steps[i - 1].$1 == HdStep.done ? l.ok : l.border, borderRadius: BorderRadius.circular(1)),
                ),
              ),
            Tooltip(
              message: steps[i].$4,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                StepDot(steps[i].$1, label: steps[i].$2, size: 20),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(steps[i].$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: steps[i].$1 == HdStep.todo ? l.sub : l.text, fontSize: 13, fontWeight: steps[i].$1 == HdStep.current ? FontWeight.w600 : FontWeight.w500)),
                ),
              ]),
            ),
          ],
        ]),
      ]),
    );
  }

  /// Tên ngắn cho bước: bỏ "CÔNG TY CP/TNHH".
  static String _short(String name) {
    final s = name.replaceFirst(RegExp(r'^(CÔNG TY|CTY|Công ty|công ty)\s+(CỔ PHẦN|CP|TNHH|Cổ phần)?\s*', caseSensitive: false), '').trim();
    if (s.isEmpty) return name;
    return s.split(' ').map((w) => w.length <= 1 ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');
  }

  Widget _bottomBar(HdLook l, bool wide) {
    final miss = _missing();
    final ready = miss.isEmpty;
    final busy = _saving || _uploading;
    final summary = [
      if (_docs.length > 1) '${_docs.length} tài liệu',
      '${_parties.length} bên',
      _mode == 'par' ? 'cùng lúc' : 'lần lượt',
      if (_deadline != null) 'hạn ${dm(_deadline!.millisecondsSinceEpoch)}',
    ].join(' · ');
    final fs = wide ? 13.0 : 15.0;
    final status = _locked
        ? Text('Đã gửi ký · chỉ sửa ghi chú', style: TextStyle(color: l.sub, fontSize: fs))
        : Row(mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
            if (wide) ...[Icon(ready ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: ready ? l.ok : l.warn, size: 18), const SizedBox(width: 8)],
            Flexible(
              child: Text(
                ready ? (wide ? 'Sẵn sàng gửi · $summary' : summary) : 'Còn thiếu: ${miss.take(3).join(', ')}${miss.length > 3 ? '…' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ready ? l.sub : l.warn, fontSize: fs),
              ),
            ),
          ]);
    final pad = wide ? const EdgeInsets.symmetric(horizontal: 16, vertical: 0) : const EdgeInsets.symmetric(horizontal: 24, vertical: 18);
    final saveBtn = OutlinedButton(
      onPressed: busy ? null : () => _save(),
      style: OutlinedButton.styleFrom(
        padding: pad,
        minimumSize: wide ? const Size(0, 36) : null,
        side: BorderSide(color: l.border),
        backgroundColor: l.card,
        shape: const StadiumBorder(),
      ),
      child: Text(_locked ? 'Lưu ghi chú' : 'Lưu nháp', style: TextStyle(color: l.text, fontSize: wide ? 13.5 : 16, fontWeight: FontWeight.w600)),
    );
    final sendBtn = FilledButton.icon(
      onPressed: busy || _locked ? null : _send,
      icon: Icon(Icons.send_rounded, size: wide ? 16 : 20),
      label: Text(_sendText, style: TextStyle(fontSize: wide ? 13.5 : 16, fontWeight: FontWeight.w700)),
      style: FilledButton.styleFrom(
        backgroundColor: ready ? l.accent : l.accent.withValues(alpha: .55),
        foregroundColor: Colors.white,
        padding: wide ? const EdgeInsets.symmetric(horizontal: 18) : const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        minimumSize: wide ? const Size(0, 36) : null,
        shape: const StadiumBorder(),
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 20 : 14, wide ? 8 : 12, wide ? 20 : 14, (wide ? 8 : 12) + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: l.nav, border: Border(top: BorderSide(color: l.border))),
      child: wide
          ? _center(true, Row(children: [Expanded(child: status), saveBtn, if (!_locked) ...[const SizedBox(width: 10), sendBtn]]))
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              status,
              const SizedBox(height: 10),
              if (_locked)
                saveBtn
              else
                Row(children: [
                  saveBtn,
                  const SizedBox(width: 10),
                  Expanded(child: sendBtn),
                ]),
            ]),
    );
  }
}
