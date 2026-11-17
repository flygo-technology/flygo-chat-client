// Hợp đồng: soạn / sửa hợp đồng — tệp PDF, số / tên / giá trị, "Ai ký?" (thẻ từng bên: nhãn, tên, MST/CCCD, email),
// lần lượt / cùng lúc, thời hạn (hiệu lực, hạn ký, nhắc gia hạn), ghi chú, tiến độ luồng ký và thanh dưới Lưu nháp / Gửi ký.
// Sau khi gửi ký máy chủ chỉ cho sửa ghi chú, công khai ghi chú và nhắc gia hạn: các phần khác khoá lại.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final String? id;
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

class ContractEditPage extends StatefulWidget {
  const ContractEditPage({super.key, required this.api, this.initial});
  final HopdongApi api;

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
  String _mode = 'seq';
  DateTime? _effFrom, _effTo, _deadline;
  int? _effMonths; // 6 / 12 / 24; 0 = tuỳ chọn
  int? _signDays; // 3 / 7 / 14
  bool _remind = true, _notePublic = false;
  bool _saving = false, _dirty = false, _uploading = false;
  DateTime? _savedAt;
  String _company = '';

  bool get _locked => _c != null && !_c!.isDraft;

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
    };
  }

  Future<Contract?> _save({bool quiet = false}) async {
    if (_saving) return null;
    setState(() => _saving = true);
    try {
      final n = _c == null ? await widget.api.create(_body()) : await widget.api.update(_c!.id, _body());
      if (!mounted) return n;
      setState(() {
        final keep = _parties.length == n.parties.length;
        _c = n;
        // Giữ ô đang gõ, chỉ gắn id máy chủ cấp cho bên mới.
        if (keep) {
          for (var i = 0; i < _parties.length; i++) {
            if (_parties[i].id == null) {
              final old = _parties[i];
              _parties[i] = _PartyDraft.of(n.parties[i]);
              old.dispose();
            }
          }
        }
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
  List<String> _missing() => [
        if (_c?.doc == null) 'tài liệu PDF',
        if (_parties.isEmpty) 'bên ký',
        for (var i = 0; i < _parties.length; i++) ...[
          if (_parties[i].name.text.trim().isEmpty) 'tên ${_label(i)}',
          if (!_parties[i].valid) '${_parties[i].kind == 'cccd' ? 'CCCD' : 'MST'} ${_label(i)}',
        ],
      ];

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
      'Link ký sẽ mở cho $who. Hạn ký: ${_deadline == null ? '7 ngày' : dmyHm(_deadline!.millisecondsSinceEpoch)}.\n\n'
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

  Future<void> _pickPdf({bool drive = false}) async {
    if (_locked) return;
    Uint8List? bytes;
    String name = 'hop-dong.pdf';
    try {
      if (drive) {
        final r = await pickFromDrive(context);
        final f = r?.files.firstOrNull;
        if (f == null) return;
        if (!f.$2.toLowerCase().endsWith('.pdf')) {
          if (mounted) hdToast(context, 'Chỉ nhận tệp PDF');
          return;
        }
        bytes = await File(f.$1).readAsBytes();
        name = f.$2;
      } else {
        final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
        final f = files.firstOrNull;
        if (f == null) return;
        bytes = await f.readAsBytes();
        name = f.name;
      }
    } catch (e) {
      if (mounted) hdToast(context, 'Không mở được tệp: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      // Chưa có hợp đồng trên máy chủ: lưu nháp trước để có chỗ gắn tệp.
      final c = _c ?? await _save(quiet: true);
      if (c == null) return;
      final n = await widget.api.uploadDoc(c.id, name, bytes);
      if (!mounted) return;
      setState(() {
        _c = n;
        if (_no.text.trim().isEmpty && n.no.isNotEmpty) _no.text = n.no;
        _savedAt = hdNow();
      });
      hdToast(context, 'Đã tải lên $name');
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _choosePdf(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final pos = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final v = await showMenu<String>(
      context: context,
      position: pos == null ? const RelativeRect.fromLTRB(100, 100, 100, 100) : RelativeRect.fromLTRB(pos.left, pos.bottom, pos.right, pos.bottom),
      items: const [
        PopupMenuItem(value: 'local', child: ListTile(leading: Icon(Icons.upload_file_rounded), title: Text('Chọn PDF trên máy'), dense: true)),
        PopupMenuItem(value: 'drive', child: ListTile(leading: Icon(Icons.add_to_drive_rounded), title: Text('Chọn từ Drive'), dense: true)),
      ],
    );
    if (v != null) await _pickPdf(drive: v == 'drive');
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
          _parties.removeAt(i).dispose();
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
  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final left = [_fileCard(l, wide), const SizedBox(height: 18), _partiesCard(l, wide), if (wide) ...[const SizedBox(height: 18), _flowCard(l)]];
      final right = [_termCard(l, wide), const SizedBox(height: 18), _noteCard(l, wide)];
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
              _header(l, wide),
              if (_locked) _lockedBanner(l, wide),
              Expanded(
                child: wide
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                          const SizedBox(width: 20),
                          SizedBox(width: 420, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
                        ]),
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

  Widget _header(HdLook l, bool wide) {
    final saved = _savedAt ?? (_c?.updatedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(_c!.updatedAt!));
    final hm = saved == null ? null : '${saved.hour.toString().padLeft(2, '0')}:${saved.minute.toString().padLeft(2, '0')}';
    final title = _title.text.trim().isEmpty ? (_c == null ? 'Hợp đồng mới' : 'Hợp đồng chưa đặt tên') : _title.text.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 14 : 4, 8, wide ? 24 : 8, 8),
      child: Row(children: [
        IconButton(onPressed: () => Navigator.maybePop(context), icon: Icon(wide ? Icons.arrow_back_rounded : Icons.close_rounded, color: l.sub)),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_c == null ? 'Soạn hợp đồng' : (_locked ? 'Hợp đồng' : 'Sửa hợp đồng'), style: TextStyle(color: l.sub, fontSize: 13.5)),
              if (_c != null) ...[
                Text(' · ', style: TextStyle(color: l.sub)),
                StatusChip(_c!, now: hdNow(), size: 11),
              ],
              if (hm != null) Flexible(child: Text(_dirty ? ' · chưa lưu' : ' · đã lưu $hm', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: 13.5))),
            ]),
            const SizedBox(height: 2),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: wide ? 21 : 19, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (_c?.doc != null)
          wide
              ? HdAction(Icons.visibility_outlined, 'Xem PDF', onTap: () => openPdf(context, widget.api, _c!))
              : IconButton(tooltip: 'Xem PDF', onPressed: () => openPdf(context, widget.api, _c!), icon: Icon(Icons.visibility_outlined, color: l.sub)),
        if (!_locked)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: l.sub),
            onSelected: (v) => v == 'delete' ? _deleteDraft() : null,
            itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(_c == null ? 'Bỏ hợp đồng này' : 'Xoá nháp'))],
          ),
      ]),
    );
  }

  Widget _lockedBanner(HdLook l, bool wide) => Container(
        margin: EdgeInsets.fromLTRB(wide ? 24 : 14, 0, wide ? 24 : 14, 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: l.warnSoft, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: l.warn),
          const SizedBox(width: 10),
          Expanded(child: Text('Hợp đồng đã gửi ký: tài liệu, các bên và thời hạn đã khoá. Chỉ sửa được ghi chú và nhắc gia hạn.', style: TextStyle(color: l.warn, fontSize: 13.5))),
        ]),
      );

  InputDecoration _fieldDeco(HdLook l, String label, {String? hint}) => InputDecoration(
        isDense: true,
        border: InputBorder.none,
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: l.faint),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(color: l.sub, fontSize: 15),
        contentPadding: const EdgeInsets.only(top: 4, bottom: 2),
      );

  Widget _field(HdLook l, String label, TextEditingController c, {String? hint, TextInputType? kb, List<TextInputFormatter>? fmt, String? suffix}) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: l.border.withValues(alpha: .6))),
        child: TextField(
          controller: c,
          enabled: !_locked,
          keyboardType: kb,
          inputFormatters: fmt,
          style: TextStyle(color: l.text, fontSize: 16.5, fontWeight: FontWeight.w500),
          decoration: _fieldDeco(l, label, hint: hint).copyWith(suffixText: suffix, suffixStyle: TextStyle(color: l.text, fontSize: 16.5)),
        ),
      );

  Widget _fileCard(HdLook l, bool wide) {
    final d = _c?.doc;
    final icon = Container(
      width: wide ? 64 : 56,
      height: wide ? 64 : 56,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: l.border)),
      child: _uploading
          ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2.4))
          : const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE5484D), size: 32),
    );
    final info = d == null
        ? (_c == null ? 'Chọn tệp PDF hợp đồng (bản chưa ký)' : 'Chưa có tài liệu — chọn tệp PDF (bản chưa ký)')
        : [if (d.pages != null) '${d.pages} trang', 'bản ${d.rev}', if (wide && _c!.updatedAt != null) 'cập nhật ${dm(_c!.updatedAt)}'].join(' · ');
    final value = parseMoney(_value.text);
    final fields = wide
        ? Row(children: [
            SizedBox(width: 240, child: _field(l, 'Số hợp đồng', _no, hint: 'HĐDV-2026/087')),
            const SizedBox(width: 14),
            Expanded(child: _field(l, 'Tên hợp đồng', _title, hint: 'Bảo trì hệ thống 12 tháng')),
            const SizedBox(width: 14),
            SizedBox(width: 240, child: _valueField(l)),
          ])
        : Column(children: [
            _field(l, 'Số hợp đồng', _no, hint: 'HĐDV-2026/087'),
            const SizedBox(height: 10),
            _field(l, 'Tên hợp đồng', _title, hint: 'Bảo trì hệ thống 12 tháng'),
            const SizedBox(height: 10),
            _valueField(l),
          ]);
    return HdCard(
      pad: EdgeInsets.all(wide ? 24 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          icon,
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                d?.name ?? (wide ? 'Chưa có tệp PDF' : [if (_no.text.trim().isNotEmpty) _no.text.trim(), 'Chưa có PDF'].join(' · ')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: l.text, fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(!wide && d != null && value != null ? '$info · ${money(value)}' : info,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: 14)),
            ]),
          ),
          if (!_locked)
            Builder(
              builder: (b) => wide
                  ? HdAction(d == null ? Icons.upload_file_rounded : Icons.swap_horiz_rounded, d == null ? 'Chọn PDF' : 'Đổi file', onTap: _uploading ? null : () => _choosePdf(b))
                  : IconButton(onPressed: _uploading ? null : () => _choosePdf(b), icon: Icon(d == null ? Icons.upload_file_rounded : Icons.swap_horiz_rounded, color: l.accentText)),
            ),
        ]),
        SizedBox(height: wide ? 20 : 14),
        fields,
      ]),
    );
  }

  Widget _valueField(HdLook l) => _field(l, 'Giá trị', _value, hint: '0', kb: TextInputType.number, suffix: '₫', fmt: [
        FilteringTextInputFormatter.digitsOnly,
        TextInputFormatter.withFunction((o, n) {
          final v = parseMoney(n.text);
          final t = v == null ? '' : groupDigits(v);
          return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
        }),
      ]);

  Widget _modeSwitch(HdLook l, bool wide) {
    Widget seg(String v, String t) {
      final sel = _mode == v;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: HdChip(t, selected: sel, dense: true, onTap: _locked ? () {} : () => setState(() {
              _mode = v;
              _dirty = true;
            })),
      );
    }

    final n = _parties.length;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      seg('seq', wide && n > 1 ? '1 → $n Lần lượt' : 'Lần lượt'),
      seg('par', 'Cùng lúc'),
    ]);
  }

  Widget _partiesCard(HdLook l, bool wide) {
    return HdCard(
      pad: EdgeInsets.all(wide ? 24 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HdCardTitle(Icons.groups_2_outlined, 'Ai ký?', trailing: _modeSwitch(l, wide)),
        const SizedBox(height: 16),
        for (var i = 0; i < _parties.length; i++) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.only(left: wide ? 50 : 26),
              child: Align(alignment: Alignment.centerLeft, child: Container(width: 2, height: wide ? 26 : 14, color: _mode == 'seq' ? l.border : Colors.transparent)),
            ),
          _partyCard(l, i, wide),
        ],
        if (!_locked && _parties.length < 10) ...[
          const SizedBox(height: 14),
          _addRow(l, wide),
        ],
      ]),
    );
  }

  Widget _partyCard(HdLook l, int i, bool wide) {
    final p = _parties[i];
    final ringColor = i == 0 ? l.warn : l.accent;
    final no = p.idNo.text.replaceAll(RegExp(r'\s+'), '');
    final ok = p.valid;
    final kind = p.kind == 'cccd' ? 'CCCD' : 'MST';
    final idColor = ok ? l.ok : (no.isEmpty ? l.sub : l.warn);
    final idPill = Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
      decoration: BoxDecoration(color: ok ? l.okSoft : l.card2, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? Icons.verified_rounded : Icons.badge_outlined, size: 18, color: idColor),
        const SizedBox(width: 6),
        if (wide) Text('$kind ', style: TextStyle(color: idColor, fontWeight: FontWeight.w700, fontSize: 15.5)),
        IntrinsicWidth(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96),
            child: TextField(
              controller: p.idNo,
              enabled: !_locked,
              onChanged: (_) => setState(() => _dirty = true),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')), LengthLimitingTextInputFormatter(14)],
              style: TextStyle(color: idColor, fontWeight: FontWeight.w700, fontSize: 15.5, fontFeatures: const [FontFeature.tabularFigures()]),
              decoration: InputDecoration.collapsed(hintText: p.kind == 'cccd' ? '12 số CCCD' : '10 số MST', hintStyle: TextStyle(color: l.faint, fontSize: 15)),
            ),
          ),
        ),
      ]),
    );
    final hint = ok
        ? (p.internal ? 'Ký bằng token công ty' : 'Chỉ chứng thư đúng $kind này mới ký được')
        : no.isEmpty
            ? 'Nhập $kind của bên ký'
            : (p.kind == 'cccd' ? 'CCCD phải đủ 12 số' : 'MST phải 10 số hoặc 10 số-3 số');
    final label = p.label.text.trim().isEmpty ? defaultLabel(i) : p.label.text.trim();
    final labelChip = InkWell(
      onTap: _locked ? null : () => _renameLabel(i),
      child: Pill('${label.toUpperCase()}${p.internal ? ' · MÌNH' : ''}', fg: p.internal ? l.accentText : l.warn, bg: p.internal ? l.accentSoft : l.warnSoft, size: 11.5),
    );
    final name = TextField(
      controller: p.name,
      enabled: !_locked,
      onChanged: (_) => _touch(),
      textCapitalization: TextCapitalization.characters,
      minLines: 1,
      maxLines: wide ? 1 : 2,
      style: TextStyle(color: l.text, fontSize: wide ? 17.5 : 16.5, fontWeight: FontWeight.w700),
      decoration: InputDecoration.collapsed(hintText: p.internal ? 'Tên công ty mình' : 'Tên công ty / người ký', hintStyle: TextStyle(color: l.faint, fontWeight: FontWeight.w500)),
    );
    final menu = _locked
        ? const SizedBox(width: 8)
        : PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: l.sub),
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
    final ring = Container(
      width: wide ? 44 : 34,
      height: wide ? 44 : 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ringColor, width: 2)),
      child: Text('${i + 1}', style: TextStyle(color: ringColor, fontWeight: FontWeight.w700, fontSize: wide ? 17 : 15)),
    );
    final email = SizedBox(
      width: 230,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Gửi link tới', style: TextStyle(color: l.sub, fontSize: 13.5)),
        TextField(
          controller: p.email,
          enabled: !_locked,
          onChanged: (_) => _touch(),
          textAlign: TextAlign.end,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: l.text, fontSize: 15.5),
          decoration: InputDecoration.collapsed(hintText: 'email (không bắt buộc)', hintStyle: TextStyle(color: l.faint, fontSize: 14)),
        ),
      ]),
    );
    return Container(
      key: p.key,
      padding: EdgeInsets.fromLTRB(wide ? 18 : 0, wide ? 18 : 4, wide ? 6 : 0, wide ? 18 : 4),
      decoration: wide ? BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(16), border: Border.all(color: l.border)) : null,
      child: Row(children: [
        ring,
        SizedBox(width: wide ? 18 : 12),
        PartyAvatar(p.name.text.isEmpty ? label : p.name.text, index: p.internal ? 1 : 0, size: wide ? 62 : 52),
        SizedBox(width: wide ? 18 : 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: wide ? IntrinsicWidth(child: name) : name),
              if (wide) ...[const SizedBox(width: 10), labelChip],
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              idPill,
              if (wide) Text(hint, style: TextStyle(color: ok ? l.sub : idColor, fontSize: 14.5)),
              if (!wide && !ok) Text(hint, style: TextStyle(color: idColor, fontSize: 13)),
            ]),
          ]),
        ),
        if (wide) email,
        menu,
      ]),
    );
  }

  Widget _addRow(HdLook l, bool wide) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: l.border, width: 1.4, strokeAlign: BorderSide.strokeAlignInside),
        ),
        child: Row(children: [
          Icon(Icons.add_circle_outline_rounded, color: l.accentText, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _add,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
              onSubmitted: _addParty,
              style: TextStyle(color: l.text, fontSize: 16),
              decoration: InputDecoration(border: InputBorder.none, hintText: 'Nhập MST để thêm bên ký', hintStyle: TextStyle(color: l.sub, fontSize: 16)),
            ),
          ),
          TextButton(onPressed: () => _addParty(_add.text), child: Text(wide ? 'hoặc thêm bên trống' : 'Thêm', style: TextStyle(color: l.sub))),
        ]),
      );

  Widget _label2(HdLook l, String t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(t, style: TextStyle(color: l.sub, fontSize: 15)));

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
      pad: EdgeInsets.all(wide ? 24 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const HdCardTitle(Icons.schedule_rounded, 'Thời hạn'),
        const SizedBox(height: 14),
        _label2(l, wide ? 'Hiệu lực hợp đồng' : 'Hiệu lực'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in [6, 12, 24]) HdChip(wide || m == 12 ? '$m tháng' : '$m th', selected: _effMonths == m, dense: true, onTap: () => eff(m)),
          HdChip(wide ? 'Tuỳ chọn' : 'Khác', selected: _effMonths == 0, dense: true, onTap: () => eff(0)),
        ]),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _locked ? null : _pickRange,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 0, vertical: 12),
            decoration: wide ? BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(12)) : null,
            child: Row(children: [
              if (wide) ...[Icon(Icons.calendar_month_outlined, color: l.sub, size: 20), const SizedBox(width: 12)],
              Expanded(child: Text(range, style: TextStyle(color: l.text, fontSize: 17, fontWeight: FontWeight.w500))),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _label2(l, wide ? 'Hạn để các bên ký xong' : 'Hạn ký'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in [3, 7, 14]) HdChip('$d ngày', selected: _signDays == d, dense: true, onTap: () => sign(d)),
        ]),
        if (_deadline != null) ...[
          const SizedBox(height: 10),
          Text('→ link hết hạn ${dmyHm(_deadline!.millisecondsSinceEpoch)}', style: TextStyle(color: l.sub, fontSize: 14.5)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Switch(value: _remind, onChanged: (v) => setState(() {
                _remind = v;
                _dirty = true;
              })),
          const SizedBox(width: 10),
          Expanded(child: Text('Nhắc gia hạn trước 30 ngày', style: TextStyle(color: l.text, fontSize: 15.5))),
        ]),
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
        pad: EdgeInsets.all(wide ? 24 : 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const HdCardTitle(Icons.sticky_note_2_outlined, 'Ghi chú'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: l.field, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: _note,
              minLines: wide ? 4 : 2,
              maxLines: 10,
              style: TextStyle(color: l.text, fontSize: 15.5, height: 1.4),
              decoration: InputDecoration.collapsed(hintText: 'Ghi chú nội bộ cho hợp đồng này…', hintStyle: TextStyle(color: l.faint)),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Switch(value: _notePublic, onChanged: (v) => setState(() {
                  _notePublic = v;
                  _dirty = true;
                })),
            const SizedBox(width: 10),
            Expanded(child: Text('Đối tác cũng thấy ghi chú này', style: TextStyle(color: l.text, fontSize: 15.5))),
          ]),
        ]),
      );

  /// Tiến độ luồng ký (ngang): Tạo & chốt → từng bên → Hoàn tất.
  Widget _flowCard(HdLook l) {
    final c = _c;
    final steps = <(HdStep, String, String, String)>[];
    final created = c?.doc != null;
    steps.add((created ? HdStep.done : HdStep.current, '', 'Tạo & chốt${c?.doc != null ? ' bản ${c!.doc!.rev}' : ''}',
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
      pad: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HdCardTitle(Icons.route_outlined, 'Tiến độ luồng ký',
            trailing: Text(c == null || c.isDraft ? 'Chưa gửi' : (kStatusLabels[c.status] ?? ''), style: TextStyle(color: l.sub, fontSize: 14.5))),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Container(height: 3, decoration: BoxDecoration(color: steps[i - 1].$1 == HdStep.done ? l.ok : l.border, borderRadius: BorderRadius.circular(2))),
                ),
              ),
            SizedBox(
              width: 150,
              child: Column(children: [
                StepDot(steps[i].$1, label: steps[i].$2, size: 42),
                const SizedBox(height: 10),
                Text(steps[i].$3, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(steps[i].$4, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: steps[i].$1 == HdStep.current ? l.accentText : l.sub, fontSize: 13.5)),
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
    final summary = [
      '${_parties.length} bên',
      _mode == 'par' ? 'cùng lúc' : 'lần lượt',
      if (_deadline != null) 'hạn ${dm(_deadline!.millisecondsSinceEpoch)}',
    ].join(' · ');
    final status = _locked
        ? Text('Đã gửi ký · chỉ sửa ghi chú', style: TextStyle(color: l.sub, fontSize: 15))
        : Row(mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
            if (wide) ...[Icon(ready ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: ready ? l.ok : l.warn, size: 22), const SizedBox(width: 10)],
            Flexible(
              child: Text(
                ready ? (wide ? 'Sẵn sàng gửi · $summary' : summary) : 'Còn thiếu: ${miss.take(3).join(', ')}${miss.length > 3 ? '…' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ready ? l.sub : l.warn, fontSize: 15),
              ),
            ),
          ]);
    final saveBtn = OutlinedButton(
      onPressed: _saving ? null : () => _save(),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        side: BorderSide(color: l.border),
        backgroundColor: l.card,
        shape: const StadiumBorder(),
      ),
      child: Text(_locked ? 'Lưu ghi chú' : 'Lưu nháp', style: TextStyle(color: l.text, fontSize: 16, fontWeight: FontWeight.w600)),
    );
    final sendBtn = FilledButton.icon(
      onPressed: _saving || _locked ? null : _send,
      icon: const Icon(Icons.send_rounded, size: 20),
      label: Text(_sendText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      style: FilledButton.styleFrom(
        backgroundColor: ready ? l.accent : l.accent.withValues(alpha: .55),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        shape: const StadiumBorder(),
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 14, 12, wide ? 24 : 14, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: l.nav, border: Border(top: BorderSide(color: l.border))),
      child: wide
          ? Row(children: [Expanded(child: status), saveBtn, if (!_locked) ...[const SizedBox(width: 12), sendBtn]])
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
