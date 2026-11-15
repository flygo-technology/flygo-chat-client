// Biểu mẫu: trang điền trong app (người nội bộ, đã đăng nhập) và xem trước của người soạn. Rẽ nhánh theo mục, kiểm từng
// mục trước khi sang mục sau, nháp tự lưu lên máy chủ, tải tệp, sửa câu trả lời đã gửi (nếu biểu mẫu cho phép).
import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'api.dart';
import 'model.dart';
import 'widgets.dart';

class FormFillPage extends StatefulWidget {
  /// Điền thật: [api] + [token]. Xem trước: [preview] = JSON biểu mẫu (không gửi).
  const FormFillPage({super.key, this.api, this.token, this.preview});
  final FormsApi? api;
  final String? token;
  final Json? preview;
  @override
  State<FormFillPage> createState() => _FormFillPageState();
}

class _FormFillPageState extends State<FormFillPage> {
  Json? _form, _mine, _me;
  Object? _error;
  final Json _answers = {};
  Map<String, String> _errors = {};
  final Map<String, String> _fileNames = {};
  final Map<String, TextEditingController> _ctl = {};
  int _sec = 0;
  final List<int> _history = [];
  bool _sending = false, _editing = false;
  String? _done;
  Timer? _draftTimer;
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};
  final _started = DateTime.now();

  bool get _preview => widget.preview != null;
  Json get _schema => Map<String, dynamic>.from(_form!['schema'] as Map);
  Json get _settings => Map<String, dynamic>.from(_form!['settings'] as Map? ?? const {});

  @override
  void initState() {
    super.initState();
    if (_preview) {
      _form = widget.preview;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    for (final c in _ctl.values) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.api!.get('/api/fill/${widget.token}');
      setState(() {
        _form = Map<String, dynamic>.from(j['form'] as Map);
        _mine = j['my_response'] == null ? null : Map<String, dynamic>.from(j['my_response'] as Map);
        _me = j['me'] == null ? null : Map<String, dynamic>.from(j['me'] as Map);
        final d = j['draft'] as Map?;
        if (d != null) {
          _answers.addAll(Map<String, dynamic>.from(d['answers'] as Map? ?? const {}));
        }
        if (_mine != null && _settings['one_per_user'] == true && d == null) {
          _done = _settings['allow_edit'] == true ? 'Bạn đã gửi câu trả lời. Có thể sửa lại câu trả lời của mình.' : 'Bạn đã gửi câu trả lời cho biểu mẫu này.';
        }
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  TextEditingController _c(String key) => _ctl.putIfAbsent(key, () => TextEditingController(text: _answers[key] == null ? '' : answerText(const {}, _answers[key])));

  void _set(Json it, Object? v) {
    final k = '${it['key']}';
    setState(() {
      if (v == null || v == '' || (v is List && v.isEmpty) || (v is Map && v.isEmpty)) {
        _answers.remove(k);
      } else {
        _answers[k] = v;
      }
      if (_errors.containsKey(k) && checkAnswer(it, normalize(it, _answers[k])) == null) _errors = {..._errors}..remove(k);
    });
    if (!_preview) {
      _draftTimer?.cancel();
      _draftTimer = Timer(const Duration(seconds: 2), () => widget.api!.put('/api/fill/${widget.token}/draft', {'answers': _answers, 'section': _sec}).catchError((_) => <String, dynamic>{}));
    }
  }

  Json _current() {
    final out = <String, dynamic>{};
    for (final it in questionsOf(_schema)) {
      final v = normalize(it, _answers[it['key']]);
      if (v != null) out['${it['key']}'] = v;
    }
    return out;
  }

  bool _checkSection() {
    final a = _current();
    final errs = <String, String>{..._errors};
    String? first;
    for (final it in itemsOf(sectionsOf(_schema)[_sec]).where(isQuestion)) {
      final e = checkAnswer(it, a[it['key']]);
      if (e != null) {
        errs['${it['key']}'] = e;
        first ??= '${it['key']}';
      } else {
        errs.remove(it['key']);
      }
    }
    setState(() => _errors = errs);
    if (first != null) {
      final ctx = _keys[first]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: .2);
    }
    return first == null;
  }

  int? _next() {
    final p = sectionPath(_schema, _current());
    final at = p.indexOf(_sec);
    return at >= 0 && at + 1 < p.length ? p[at + 1] : null;
  }

  void _go(int i) {
    setState(() {
      _history.add(_sec);
      _sec = i;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _submit() async {
    if (!_checkSection() || _sending) return;
    if (_preview) {
      setState(() => _done = '${_settings['confirmation'] ?? 'Đã ghi nhận câu trả lời.'} (xem trước, không gửi)');
      return;
    }
    setState(() => _sending = true);
    try {
      final j = await widget.api!.post('/api/fill/${widget.token}', {
        'answers': _current(),
        'duration_ms': DateTime.now().difference(_started).inMilliseconds,
        if (_editing && _mine != null) 'response_id': _mine!['id'],
      });
      _draftTimer?.cancel();
      setState(() {
        _sending = false;
        _mine = Map<String, dynamic>.from(j['response'] as Map);
        _done = '${j['confirmation'] ?? 'Đã ghi nhận câu trả lời.'}';
      });
    } on FormsException catch (e) {
      setState(() {
        _sending = false;
        if (e.errors.isNotEmpty) {
          _errors = e.errors;
          final p = sectionPath(_schema, _current());
          final bad = p.where((i) => itemsOf(sectionsOf(_schema)[i]).any((it) => _errors.containsKey(it['key']))).firstOrNull;
          if (bad != null) _sec = bad;
        }
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(e.message)));
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  void _editMine() {
    setState(() {
      _answers
        ..clear()
        ..addAll(Map<String, dynamic>.from(_mine!['answers'] as Map));
      for (final c in _ctl.values) {
        c.dispose();
      }
      _ctl.clear();
      _editing = true;
      _done = null;
      _sec = 0;
      _history.clear();
    });
  }

  void _again() {
    setState(() {
      _answers.clear();
      for (final c in _ctl.values) {
        c.dispose();
      }
      _ctl.clear();
      _errors = {};
      _done = null;
      _sec = 0;
      _history.clear();
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final color = colorOf(_form?['theme'] as String?);
    Widget body;
    if (_error != null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$_error', textAlign: TextAlign.center, style: TextStyle(color: p.sub))));
    } else if (_form == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_form!['accepting'] != true && !_preview && _done == null) {
      body = FormBackdrop(child: FCard(top: color, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_form!['title']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        Text('${_form!['closed_reason'] ?? 'Biểu mẫu đã ngừng nhận câu trả lời.'}', style: TextStyle(color: p.sub)),
      ])));
    } else if (_done != null) {
      body = _doneView(color);
    } else {
      body = _formView(color);
    }
    return FormTheme(
      color: color,
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            FormsIcon(color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(_preview ? 'Xem trước' : 'Biểu mẫu', overflow: TextOverflow.ellipsis)),
          ]),
        ),
        body: body,
      ),
    );
  }

  Widget _doneView(Color color) {
    final p = Pal.of(context);
    return FormBackdrop(
      child: FCard(
        top: color,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_form!['title']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check_circle, color: Color(0xFF2E9D57), size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(_done!, style: TextStyle(color: p.text, fontSize: 15))),
          ]),
          const SizedBox(height: 14),
          if (_settings['one_per_user'] != true || _preview) TextButton(onPressed: _again, child: const Text('Gửi câu trả lời khác')),
          if (_mine != null && _settings['allow_edit'] == true) TextButton(onPressed: _editMine, child: const Text('Sửa câu trả lời của tôi')),
          if (_mine != null && (_mine!['links'] as List? ?? const []).isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final l in (_mine!['links'] as List)) Pill('${(l as Map)['kind'] == 'flow' ? 'Đã tạo luồng' : 'Đã tạo việc'}: ${l['title'] ?? l['id']}', icon: l['kind'] == 'flow' ? Icons.account_tree_outlined : Icons.check_box_outlined),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _formView(Color color) {
    final p = Pal.of(context);
    final secs = sectionsOf(_schema);
    if (_sec >= secs.length) _sec = 0;
    final s = secs[_sec];
    final nxt = _next();
    final path = sectionPath(_schema, _current());
    final step = max(1, path.indexOf(_sec) + 1), steps = max(path.length, secs.length > 1 ? step + (nxt == null ? 0 : 1) : 1);
    final hasReq = questionsOf(_schema).any((q) => q['required'] == true);
    var items = itemsOf(s);
    if (_settings['shuffle'] == true) items = [...items]..shuffle(Random('${_form!['id']}${s['id']}'.hashCode));
    return FormBackdrop(
      controller: _scroll,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FCard(
          top: color,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_form!['title']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, height: 1.25)),
            if ('${_form!['description'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${_form!['description']}', style: TextStyle(fontSize: 13.5, color: p.sub)),
            ],
            if (hasReq) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: p.divider),
              const SizedBox(height: 10),
              const Text('* Bắt buộc', style: TextStyle(color: Color(0xFFD93025), fontSize: 12.5)),
            ],
          ]),
        ),
        if (!_preview && _settings['collect_identity'] == true && _me != null)
          FCard(
            pad: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              CircleAvatar(radius: 14, backgroundColor: p.avatarBg, child: Text('${_me!['name'] ?? '?'}'.characters.first, style: TextStyle(color: p.avatarFg, fontSize: 13))),
              const SizedBox(width: 10),
              Expanded(child: Text('Đang điền với tài khoản ${_me!['name']} · tên và email được ghi kèm câu trả lời', style: TextStyle(color: p.sub, fontSize: 12.5))),
            ]),
          ),
        if (_editing) const FCard(pad: EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Text('Đang sửa câu trả lời đã gửi')),
        if (_sec > 0 && ('${s['title'] ?? ''}'.isNotEmpty || '${s['description'] ?? ''}'.isNotEmpty))
          FCard(
            top: color,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['title'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
              if ('${s['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${s['description']}', style: TextStyle(color: p.sub))),
            ]),
          ),
        for (final it in items) isQuestion(it) ? _question(it) : _block(it),
        const SizedBox(height: 6),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
          if (_history.isNotEmpty)
            OutlinedButton(onPressed: () {
              setState(() => _sec = _history.removeLast());
              if (_scroll.hasClients) _scroll.jumpTo(0);
            }, child: const Text('Quay lại')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: _sending ? null : (nxt != null ? () => _checkSection() ? _go(nxt) : null : _submit),
            child: Text(nxt != null ? 'Tiếp' : (_sending ? 'Đang gửi…' : 'Gửi')),
          ),
          if (_settings['progress'] != false && steps > 1)
            SizedBox(
              width: 220,
              child: Row(children: [
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: step / steps, minHeight: 8, color: color, backgroundColor: p.surface2))),
                const SizedBox(width: 10),
                Text('Trang $step / $steps', style: TextStyle(color: p.sub, fontSize: 12.5)),
              ]),
            ),
          TextButton(onPressed: _again, child: Text('Xoá hết', style: TextStyle(color: color))),
        ]),
        const SizedBox(height: 18),
        Center(child: Text(_preview ? 'Xem trước: câu trả lời không được gửi' : 'Bản nháp được lưu tự động', style: TextStyle(color: p.sub, fontSize: 11.5))),
      ]),
    );
  }

  Widget _block(Json it) {
    final p = Pal.of(context);
    return FCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ('${it['title'] ?? ''}'.isNotEmpty) Text('${it['title']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        if ('${it['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${it['description']}', style: TextStyle(color: p.sub))),
        if (it['type'] == 'image' && it['image'] != null && widget.api != null) FormImage(api: widget.api!, fileId: '${it['image']}'),
      ]),
    );
  }

  Widget _question(Json it) {
    final p = Pal.of(context);
    final k = '${it['key']}';
    final err = _errors[k];
    return KeyedSubtree(
      key: _keys.putIfAbsent(k, GlobalKey.new),
      child: FCard(
        error: err != null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          reqTitle(context, '${it['title'] ?? ''}', it['required'] == true),
          if ('${it['description'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${it['description']}', style: TextStyle(color: p.sub, fontSize: 12.5))),
          const SizedBox(height: 8),
          QuestionInput(item: it, value: _answers[k], onChanged: (v) => _set(it, v), controller: _c(k), error: err != null, api: widget.api, fileNames: _fileNames),
          errorLine(err),
        ]),
      ),
    );
  }
}

/// Ô nhập của một câu hỏi theo loại (dùng ở trang điền).
class QuestionInput extends StatelessWidget {
  const QuestionInput({super.key, required this.item, required this.value, required this.onChanged, required this.controller, this.error = false, this.api, this.fileNames = const {}});
  final Json item;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final TextEditingController controller;
  final bool error;
  final FormsApi? api;
  final Map<String, String> fileNames;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final color = FormTheme.of(context);
    final it = item;
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: UnderlineInputBorder(borderSide: BorderSide(color: p.divider)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: error ? const Color(0xFFD93025) : p.divider)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: error ? const Color(0xFFD93025) : color, width: 2)),
        );
    switch (it['type']) {
      case 'short' || 'number':
        final kind = (it['validation'] as Map?)?['kind'];
        return TextField(
          controller: controller,
          decoration: deco(it['type'] == 'number' ? 'Số' : 'Câu trả lời của bạn'),
          keyboardType: it['type'] == 'number' || kind == 'range'
              ? const TextInputType.numberWithOptions(decimal: true, signed: true)
              : kind == 'email'
                  ? TextInputType.emailAddress
                  : kind == 'phone'
                      ? TextInputType.phone
                      : kind == 'url'
                          ? TextInputType.url
                          : TextInputType.text,
          onChanged: onChanged,
        );
      case 'paragraph':
        return TextField(controller: controller, decoration: deco('Câu trả lời của bạn'), minLines: 2, maxLines: 8, onChanged: onChanged);
      case 'choice' || 'checkbox':
        final multi = it['type'] == 'checkbox';
        final labels = optionLabels(it);
        final vals = multi ? [for (final x in (value as List? ?? const [])) '$x'] : (value == null ? <String>[] : ['$value']);
        final other = vals.where((x) => !labels.contains(x)).firstOrNull;
        Widget row(String label, bool on, VoidCallback tap, [Widget? trailing]) => InkWell(
              onTap: tap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(multi ? (on ? Icons.check_box : Icons.check_box_outline_blank) : (on ? Icons.radio_button_checked : Icons.radio_button_off), size: 22, color: on ? color : p.sub),
                  const SizedBox(width: 12),
                  if (trailing == null) Expanded(child: Text(label, style: TextStyle(color: p.text, fontSize: 14.5))) else ...[Text(label), const SizedBox(width: 8), Expanded(child: trailing)],
                ]),
              ),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final l in labels)
            row(l, vals.contains(l), () {
              if (multi) {
                onChanged(vals.contains(l) ? vals.where((x) => x != l).toList() : [...vals, l]);
              } else {
                onChanged(l);
              }
            }),
          if (it['other'] == true)
            row('Khác:', other != null, () {}, TextField(
              decoration: deco(''),
              controller: TextEditingController(text: other ?? '')..selection = TextSelection.collapsed(offset: (other ?? '').length),
              onChanged: (t) {
                if (multi) {
                  onChanged([...vals.where(labels.contains), if (t.isNotEmpty) t]);
                } else {
                  onChanged(t.isEmpty ? null : t);
                }
              },
            )),
          if (!multi && value != null && it['required'] != true)
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => onChanged(null), child: const Text('Xoá lựa chọn'))),
        ]);
      case 'dropdown':
        final labels = optionLabels(it);
        return Align(
          alignment: Alignment.centerLeft,
          child: DropdownButton<String>(
            value: labels.contains(value) ? value as String : null,
            hint: const Text('Chọn'),
            items: [for (final l in labels) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: onChanged,
          ),
        );
      case 'scale':
        final sc = it['scale'] as Map? ?? const {'min': 1, 'max': 5};
        final mn = sc['min'] as int? ?? 1, mx = sc['max'] as int? ?? 5;
        return Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = mn; i <= mx; i++)
                InkWell(
                  onTap: () => onChanged(i),
                  child: SizedBox(
                    width: max(44, (MediaQuery.sizeOf(context).width - 80).clamp(0, 640) / (mx - mn + 1)),
                    child: Column(children: [
                      Text('$i', style: TextStyle(fontSize: 13, color: p.text)),
                      const SizedBox(height: 6),
                      Icon(value == i ? Icons.radio_button_checked : Icons.radio_button_off, size: 22, color: value == i ? color : p.sub),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text('${sc['min_label'] ?? ''}', style: TextStyle(color: p.sub, fontSize: 11.5))),
            Flexible(child: Text('${sc['max_label'] ?? ''}', textAlign: TextAlign.right, style: TextStyle(color: p.sub, fontSize: 11.5))),
          ]),
        ]);
      case 'date' || 'time' || 'datetime':
        final t = it['type'];
        final label = value == null ? (t == 'time' ? 'Chọn giờ' : 'Chọn ngày') : (t == 'date' ? fmtDate('$value') : t == 'datetime' ? '${fmtDate('$value')} ${'$value'.substring(11)}' : '$value');
        Future<void> pick() async {
          String two(int x) => x.toString().padLeft(2, '0');
          DateTime? d;
          TimeOfDay? tm;
          if (t != 'time') {
            d = await showDatePicker(context: context, firstDate: DateTime(1900), lastDate: DateTime(2100), initialDate: DateTime.tryParse('$value') ?? DateTime.now());
            if (d == null) return;
          }
          if (t != 'date' && context.mounted) {
            tm = await showTimePicker(context: context, initialTime: TimeOfDay.now());
            if (tm == null) return;
          }
          final ds = d == null ? '' : '${d.year}-${two(d.month)}-${two(d.day)}';
          final ts = tm == null ? '' : '${two(tm.hour)}:${two(tm.minute)}';
          onChanged(t == 'date' ? ds : t == 'time' ? ts : '${ds}T$ts');
        }

        return Row(children: [
          OutlinedButton.icon(onPressed: pick, icon: Icon(t == 'time' ? Icons.schedule : Icons.calendar_today_outlined, size: 18), label: Text(label)),
          if (value != null) IconButton(onPressed: () => onChanged(null), icon: Icon(Icons.close, size: 18, color: p.sub)),
        ]);
      case 'grid_choice' || 'grid_checkbox':
        final multi = it['type'] == 'grid_checkbox';
        final cur = value is Map ? Map<String, dynamic>.from(value as Map) : <String, dynamic>{};
        final cols = lineLabels(it, 'cols');
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(children: [const SizedBox(), for (final c in cols) Padding(padding: const EdgeInsets.all(6), child: Text(c, textAlign: TextAlign.center, style: TextStyle(color: p.sub, fontSize: 12.5)))]),
              for (final r in lineLabels(it, 'rows'))
                TableRow(children: [
                  Padding(padding: const EdgeInsets.only(right: 10), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(r, style: const TextStyle(fontWeight: FontWeight.w500)))),
                  for (final c in cols)
                    IconButton(
                      onPressed: () {
                        final next = {...cur};
                        if (multi) {
                          final s = {...(next[r] as List? ?? const [])};
                          s.contains(c) ? s.remove(c) : s.add(c);
                          if (s.isEmpty) {
                            next.remove(r);
                          } else {
                            next[r] = s.toList();
                          }
                        } else {
                          next[r] = c;
                        }
                        onChanged(next);
                      },
                      icon: Icon(
                        multi
                            ? ((cur[r] as List? ?? const []).contains(c) ? Icons.check_box : Icons.check_box_outline_blank)
                            : (cur[r] == c ? Icons.radio_button_checked : Icons.radio_button_off),
                        color: (multi ? (cur[r] as List? ?? const []).contains(c) : cur[r] == c) ? color : p.sub,
                      ),
                    ),
                ]),
            ],
          ),
        );
      case 'file':
        final ids = [for (final x in (value as List? ?? const [])) '$x'];
        final fo = it['file'] as Map? ?? const {};
        final maxFiles = fo['max_files'] as int? ?? 1, maxMb = fo['max_mb'] as int? ?? 10;
        final types = [for (final t in (fo['types'] as List? ?? const [])) '$t'];
        Future<void> pick() async {
          if (api == null) return;
          final messenger = ScaffoldMessenger.of(context);
          final files = await FilePicker.pickFiles(type: types.isEmpty ? FileType.any : FileType.custom, allowedExtensions: types.isEmpty ? null : [for (final t in types) ...?kFileExts[t]]);
          var next = [...ids];
          for (final f in files.take(maxFiles - ids.length)) {
            final size = await f.length() ?? 0;
            if (size > maxMb * 1048576) {
              messenger.showSnackBar(toast(Text('Tệp "${f.name}" lớn hơn $maxMb MB')));
              continue;
            }
            try {
              final up = await api!.upload(f.name, await f.readAsBytes());
              fileNames['${up['id']}'] = '${up['name']}';
              next = [...next, '${up['id']}'];
              onChanged(next);
            } catch (e) {
              messenger.showSnackBar(toast(Text('$e')));
            }
          }
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final id in ids)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Icon(Icons.insert_drive_file_outlined, size: 18, color: p.sub),
                const SizedBox(width: 8),
                Expanded(child: Text(fileNames[id] ?? 'Tệp đã tải lên', overflow: TextOverflow.ellipsis)),
                IconButton(onPressed: () => onChanged(ids.where((x) => x != id).toList()), icon: const Icon(Icons.close, size: 18)),
              ]),
            ),
          Row(children: [
            if (ids.length < maxFiles) OutlinedButton.icon(onPressed: api == null ? null : pick, icon: const Icon(Icons.upload_file, size: 18), label: const Text('Thêm tệp')),
            const SizedBox(width: 10),
            Flexible(child: Text('Tối đa $maxFiles tệp · $maxMb MB / tệp${types.isEmpty ? '' : ' · ${types.map((t) => kFileTypes[t] ?? t).join(', ')}'}', style: TextStyle(color: p.sub, fontSize: 12))),
          ]),
        ]);
    }
    return const SizedBox.shrink();
  }
}

/// Ảnh trong biểu mẫu (tải bằng vé).
class FormImage extends StatelessWidget {
  const FormImage({super.key, required this.api, required this.fileId});
  final FormsApi api;
  final String fileId;
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: api.imageHeaders(),
        builder: (c, s) => s.data == null
            ? const SizedBox(height: 40)
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(api.uri('/api/files/$fileId').toString(), headers: s.data, fit: BoxFit.contain)),
              ),
      );
}
