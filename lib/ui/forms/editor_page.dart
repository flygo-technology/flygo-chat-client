// Biểu mẫu: trình soạn — tab Câu hỏi / Câu trả lời / Tự động hoá / Cài đặt. Lưu tự động (gửi `base` version: hai người
// cùng sửa thì máy chủ gộp theo câu hỏi), realtime khi người khác sửa hoặc có câu trả lời mới.
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_route.dart';
import '../theme.dart';
import 'api.dart';
import 'automation_tab.dart';
import 'fill_page.dart';
import 'model.dart';
import 'question_editor.dart';
import 'responses_tab.dart';
import 'settings_tab.dart';
import 'share_sheet.dart';
import 'widgets.dart';

class FormEditorPage extends StatefulWidget {
  const FormEditorPage({super.key, required this.api, required this.formId, this.initial, this.tab = 0});
  final FormsApi api;
  final String formId;
  final Json? initial;
  final int tab;
  @override
  State<FormEditorPage> createState() => _FormEditorPageState();
}

class _FormEditorPageState extends State<FormEditorPage> with SingleTickerProviderStateMixin {
  Json? _form;
  Object? _error;
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: widget.tab);
  String? _selected;
  Timer? _saveTimer;
  bool _saving = false, _dirty = false, _editedDuringSave = false;
  String? _saveError;
  FormsLive? _live;
  StreamSubscription<Json>? _liveSub;
  int _responsesTick = 0;
  final _title = TextEditingController(), _desc = TextEditingController();

  bool get _canEdit => _form?['role'] == 'owner' || _form?['role'] == 'editor';
  Json get _schema => Map<String, dynamic>.from(_form!['schema'] as Map);
  Color get _color => colorOf(_form?['theme'] as String?);

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _apply(widget.initial!);
    _load();
    _connect();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) _save();
    _liveSub?.cancel();
    _live?.close();
    _tabs.dispose();
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _apply(Json f) {
    _form = f;
    if (_title.text != f['title']) _title.text = '${f['title'] ?? ''}';
    if (_desc.text != f['description']) _desc.text = '${f['description'] ?? ''}';
  }

  Future<void> _load() async {
    try {
      final j = await widget.api.get('/api/forms/${widget.formId}');
      if (!mounted) return;
      setState(() => _apply(Map<String, dynamic>.from(j['form'] as Map)));
      if (_tabs.index == 0 && !_canEdit) _tabs.index = 1;
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _connect() async {
    try {
      _live = await widget.api.live([widget.formId]);
      _liveSub = _live!.events.listen((m) {
        if (!mounted) return;
        if (m['type'] == 'response') {
          setState(() {
            if (m['count'] is int) _form?['responses'] = m['count'];
            _responsesTick++;
          });
        } else if (m['type'] == 'form' && !_dirty && !_saving) {
          _load();
        } else if (m['type'] == 'deleted') {
          Navigator.of(context).maybePop();
        }
      });
    } catch (_) {
      // Không có realtime vẫn dùng được (tải lại khi mở tab).
    }
  }

  /// Ghi thay đổi cục bộ rồi hẹn lưu.
  void _edit(void Function(Json f) change) {
    setState(() {
      change(_form!);
      _dirty = true;
      if (_saving) _editedDuringSave = true;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _save);
  }

  void _editSchema(void Function(List<Json> sections) change) => _edit((f) {
        final secs = sectionsOf(_schema).map((s) => {...s, 'items': itemsOf(s)}).toList();
        change(secs);
        f['schema'] = {'sections': secs};
      });

  Future<void> _save() async {
    if (_form == null || !_dirty || !_canEdit) return;
    if (_saving) {
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 600), _save);
      return;
    }
    _saving = true;
    _editedDuringSave = false;
    _dirty = false;
    final sent = deepCopy(_form!);
    try {
      final j = await widget.api.put('/api/forms/${widget.formId}', {
        'title': sent['title'], 'description': sent['description'], 'theme': sent['theme'], 'schema': sent['schema'], 'base': sent['version'],
      });
      final f = Map<String, dynamic>.from(j['form'] as Map);
      if (!mounted) return;
      setState(() {
        _saveError = null;
        if (_editedDuringSave) {
          // Đang gõ tiếp: giữ bản cục bộ, chỉ lấy version và key máy chủ đã gán cho câu mới.
          final keys = {for (final q in questionsOf(Map<String, dynamic>.from(f['schema'] as Map))) q['id']: q['key']};
          _form!['version'] = f['version'];
          _editSchemaSilently((secs) {
            for (final s in secs) {
              for (final it in (s['items'] as List).cast<Json>()) {
                if (keys[it['id']] != null) it['key'] = keys[it['id']];
              }
            }
          });
        } else {
          _apply({..._form!, ...f});
        }
      });
    } on FormsException catch (e) {
      if (mounted) setState(() => _saveError = e.message);
      if (e.status != 422) _dirty = true;
    } catch (e) {
      if (mounted) setState(() => _saveError = 'Chưa lưu được (mất mạng?), sẽ thử lại');
      _dirty = true;
      _saveTimer = Timer(const Duration(seconds: 5), _save);
    } finally {
      _saving = false;
      if (_dirty && mounted) {
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 600), _save);
      }
    }
  }

  void _editSchemaSilently(void Function(List<Json> sections) change) {
    final secs = sectionsOf(_schema).map((s) => {...s, 'items': itemsOf(s)}).toList();
    change(secs);
    _form!['schema'] = {'sections': secs};
  }

  // ---------------------------------------------------------------- thao tác câu hỏi
  (int, int)? _find(String id) {
    final secs = sectionsOf(_schema);
    for (var s = 0; s < secs.length; s++) {
      final i = itemsOf(secs[s]).indexWhere((x) => x['id'] == id);
      if (i >= 0) return (s, i);
    }
    return null;
  }

  void _add(String type) {
    final it = newItem(type, title: type == 'text' ? 'Tiêu đề' : '');
    final at = _selected == null ? null : _find(_selected!);
    _editSchema((secs) {
      if (at == null) {
        (secs.last['items'] as List).add(it);
      } else {
        (secs[at.$1]['items'] as List).insert(at.$2 + 1, it);
      }
    });
    setState(() => _selected = '${it['id']}');
  }

  Future<void> _addImage() async {
    final f = (await FilePicker.pickFiles(type: FileType.image)).firstOrNull;
    if (f == null) return;
    try {
      final up = await widget.api.upload(f.name, await f.readAsBytes(), path: '/api/forms/${widget.formId}/images');
      final it = newItem('image')..['image'] = up['id'];
      _editSchema((secs) => (secs.last['items'] as List).add(it));
      setState(() => _selected = '${it['id']}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    }
  }

  void _addSection() {
    final at = _selected == null ? null : _find(_selected!);
    _editSchema((secs) {
      final s = {'id': newId(), 'title': 'Mục không có tiêu đề', 'items': <Json>[]};
      if (at == null) {
        secs.add(s);
      } else {
        // Tách mục tại câu đang chọn: các câu sau nó sang mục mới.
        final items = (secs[at.$1]['items'] as List).cast<Json>();
        s['items'] = items.sublist(at.$2 + 1);
        secs[at.$1]['items'] = items.sublist(0, at.$2 + 1);
        secs.insert(at.$1 + 1, s);
      }
    });
  }

  void _updateItem(Json it) => _editSchema((secs) {
        for (final s in secs) {
          final items = (s['items'] as List).cast<Json>();
          final i = items.indexWhere((x) => x['id'] == it['id']);
          if (i >= 0) items[i] = it;
        }
      });

  void _itemAction(String id, String action) {
    final at = _find(id);
    if (at == null) return;
    _editSchema((secs) {
      final items = (secs[at.$1]['items'] as List).cast<Json>();
      switch (action) {
        case 'copy':
          final c = deepCopy(items[at.$2])
            ..['id'] = newId()
            ..remove('key');
          if (c['options'] is List) c['options'] = [for (final o in c['options'] as List) {...(o as Map), 'id': newId()}];
          items.insert(at.$2 + 1, c);
        case 'delete':
          items.removeAt(at.$2);
        case 'up':
          if (at.$2 > 0) {
            items.insert(at.$2 - 1, items.removeAt(at.$2));
          } else if (at.$1 > 0) {
            (secs[at.$1 - 1]['items'] as List).add(items.removeAt(at.$2));
          }
        case 'down':
          if (at.$2 < items.length - 1) {
            items.insert(at.$2 + 1, items.removeAt(at.$2));
          } else if (at.$1 < secs.length - 1) {
            (secs[at.$1 + 1]['items'] as List).insert(0, items.removeAt(at.$2));
          }
      }
    });
    if (action == 'delete') setState(() => _selected = null);
  }

  void _sectionAction(int i, String action) => _editSchema((secs) {
        switch (action) {
          case 'up':
            if (i > 0) secs.insert(i - 1, secs.removeAt(i));
          case 'down':
            if (i < secs.length - 1) secs.insert(i + 1, secs.removeAt(i));
          case 'merge':
            // Xoá mục: câu hỏi gộp vào mục trước.
            if (i > 0) {
              (secs[i - 1]['items'] as List).addAll(secs[i]['items'] as List);
              secs.removeAt(i);
            }
          case 'copy':
            final c = deepCopy(secs[i])..['id'] = newId();
            c['items'] = [for (final it in (c['items'] as List).cast<Json>()) {...it, 'id': newId()}..remove('key')];
            secs.insert(i + 1, c);
        }
      });

  Future<void> _share() async {
    final f = await showShareSheet(context, widget.api, _form!);
    if (f != null && mounted) setState(() => _apply({..._form!, ...f}));
  }

  Future<void> _pickTheme() async {
    final c = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Màu chủ đề'),
        content: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final h in kThemeColors)
            InkWell(
              onTap: () => Navigator.pop(ctx, h),
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: colorOf(h), shape: BoxShape.circle, border: h == _form!['theme'] ? Border.all(color: Pal.of(ctx).text, width: 3) : null),
              ),
            ),
        ]),
      ),
    );
    if (c != null) _edit((f) => f['theme'] = c);
  }

  void _preview() => Navigator.of(context).push(AppPageRoute(builder: (_) => FormFillPage(api: widget.api, preview: deepCopy(_form!))));

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (_form == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: _error == null ? const CircularProgressIndicator() : Text('$_error', style: TextStyle(color: p.sub))));
    }
    final wide = MediaQuery.sizeOf(context).width > 760;
    final n = _form!['responses'] ?? 0;
    return FormTheme(
      color: _color,
      child: Scaffold(
        backgroundColor: p.bg,
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            FormsIcon(color: _color),
            const SizedBox(width: 10),
            Expanded(child: Text('${_form!['title']}', overflow: TextOverflow.ellipsis)),
            if (_saving || _dirty)
              Padding(padding: const EdgeInsets.only(left: 8), child: Text('Đang lưu…', style: TextStyle(fontSize: 12, color: p.sub)))
            else if (_saveError != null)
              Tooltip(message: _saveError!, child: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.cloud_off, size: 18, color: Color(0xFFD93025)))),
          ]),
          actions: [
            if (_canEdit && wide) IconButton(tooltip: 'Màu chủ đề', onPressed: _pickTheme, icon: const Icon(Icons.palette_outlined)),
            IconButton(tooltip: 'Xem trước', onPressed: _preview, icon: const Icon(Icons.visibility_outlined)),
            if (_canEdit)
              wide
                  ? Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _color), onPressed: _share, icon: const Icon(Icons.send, size: 18), label: const Text('Gửi')))
                  : IconButton(tooltip: 'Gửi', onPressed: _share, icon: const Icon(Icons.send_outlined)),
            PopupMenuButton<String>(
              onSelected: (a) async {
                if (a == 'theme') _pickTheme();
                final messenger = ScaffoldMessenger.of(context), nav = Navigator.of(context);
                if (a == 'copy') {
                  await widget.api.post('/api/forms/${widget.formId}/copy');
                  messenger.showSnackBar(toast(const Text('Đã tạo bản sao')));
                }
                if (a == 'fill') nav.push(AppPageRoute(builder: (_) => FormFillPage(api: widget.api, token: '${_form!['token']}')));
              },
              itemBuilder: (_) => [
                if (_canEdit && !wide) const PopupMenuItem(value: 'theme', child: Text('Màu chủ đề')),
                if (_form!['status'] != 'draft') const PopupMenuItem(value: 'fill', child: Text('Mở trang điền')),
                const PopupMenuItem(value: 'copy', child: Text('Tạo bản sao')),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: !wide,
            tabAlignment: wide ? TabAlignment.center : TabAlignment.start,
            labelColor: _color,
            indicatorColor: _color,
            unselectedLabelColor: p.sub,
            tabs: [const Tab(text: 'Câu hỏi'), Tab(text: 'Câu trả lời  $n'), const Tab(text: 'Tự động hoá'), const Tab(text: 'Cài đặt')],
          ),
        ),
        body: TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: [
          _questionsTab(wide),
          ResponsesTab(api: widget.api, form: _form!, tick: _responsesTick, onForm: (f) => setState(() => _apply({..._form!, ...f}))),
          AutomationTab(api: widget.api, form: _form!, canEdit: _canEdit, onForm: (f) => setState(() => _apply({..._form!, ...f}))),
          SettingsTab(api: widget.api, form: _form!, canEdit: _canEdit, onForm: (f) => setState(() => _apply({..._form!, ...f}))),
        ]),
      ),
    );
  }

  Widget _questionsTab(bool wide) {
    final p = Pal.of(context);
    final secs = sectionsOf(_schema);
    final toolbarItems = <(IconData, String, VoidCallback)>[
      (Icons.add_circle_outline, 'Thêm câu hỏi', () => _add('choice')),
      (Icons.title, 'Thêm tiêu đề và mô tả', () => _add('text')),
      (Icons.image_outlined, 'Thêm ảnh', _addImage),
      (Icons.view_agenda_outlined, 'Thêm mục', _addSection),
    ];
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var si = 0; si < secs.length; si++) ...[
        if (secs.length > 1) SectionBadge('Mục ${si + 1} / ${secs.length}'),
        if (si == 0)
          FCard(
            top: _color,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _title,
                enabled: _canEdit,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
                decoration: const InputDecoration(hintText: 'Tiêu đề biểu mẫu', border: InputBorder.none, isDense: true),
                maxLines: null,
                onChanged: (v) => _edit((f) => f['title'] = v),
              ),
              TextField(
                controller: _desc,
                enabled: _canEdit,
                style: TextStyle(fontSize: 13.5, color: p.sub),
                decoration: const InputDecoration(hintText: 'Mô tả biểu mẫu', border: InputBorder.none, isDense: true),
                maxLines: null,
                onChanged: (v) => _edit((f) => f['description'] = v),
              ),
            ]),
          )
        else
          _sectionHeader(secs, si),
        for (final it in itemsOf(secs[si]))
          QuestionEditor(
            key: ValueKey(it['id']),
            item: it,
            selected: _selected == it['id'] && _canEdit,
            sections: secs,
            api: widget.api,
            compact: !wide,
            onTap: _canEdit ? () => setState(() => _selected = '${it['id']}') : null,
            onChanged: _updateItem,
            onAction: (a) => _itemAction('${it['id']}', a),
          ),
        if (secs.length > 1 && si < secs.length - 1) _afterSection(secs, si),
      ],
      if (_canEdit && itemsOf(secs.last).isEmpty)
        Center(child: TextButton.icon(onPressed: () => _add('choice'), icon: const Icon(Icons.add), label: const Text('Thêm câu hỏi'))),
    ]);
    return Stack(children: [
      FormBackdrop(child: body),
      if (_canEdit && wide)
        Positioned(
          right: 24,
          top: 120,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(10), border: Border.all(color: p.divider), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [for (final t in toolbarItems) IconButton(tooltip: t.$2, onPressed: t.$3, icon: Icon(t.$1, color: p.sub))]),
          ),
        ),
      if (_canEdit && !wide)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(color: p.bg, border: Border(top: BorderSide(color: p.divider))),
            child: SafeArea(top: false, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final t in toolbarItems) IconButton(tooltip: t.$2, onPressed: t.$3, icon: Icon(t.$1, color: p.sub))])),
          ),
        ),
    ]);
  }

  Widget _sectionHeader(List<Json> secs, int si) {
    final p = Pal.of(context);
    final s = secs[si];
    return FCard(
      top: _color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('st-${s['id']}'),
              initialValue: '${s['title'] ?? ''}',
              enabled: _canEdit,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(hintText: 'Tiêu đề mục', border: InputBorder.none, isDense: true),
              onChanged: (v) => _editSchema((secs) => secs[si]['title'] = v),
            ),
          ),
          if (_canEdit)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: p.sub),
              onSelected: (a) => _sectionAction(si, a),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('Nhân bản mục')),
                PopupMenuItem(value: 'up', child: Text('Chuyển mục lên')),
                PopupMenuItem(value: 'down', child: Text('Chuyển mục xuống')),
                PopupMenuItem(value: 'merge', child: Text('Xoá mục (gộp câu hỏi vào mục trước)')),
              ],
            ),
        ]),
        TextFormField(
          key: ValueKey('sd-${s['id']}'),
          initialValue: '${s['description'] ?? ''}',
          enabled: _canEdit,
          style: TextStyle(fontSize: 13.5, color: p.sub),
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Mô tả (không bắt buộc)', border: InputBorder.none, isDense: true),
          onChanged: (v) => _editSchema((secs) => secs[si]['description'] = v),
        ),
      ]),
    );
  }

  Widget _afterSection(List<Json> secs, int si) {
    final p = Pal.of(context);
    final cur = '${secs[si]['next'] ?? 'next'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, left: 4),
      child: Row(children: [
        Text('Sau mục ${si + 1}', style: TextStyle(color: p.sub, fontSize: 13)),
        const SizedBox(width: 10),
        Flexible(child: DropdownButton<String>(
          value: cur == 'next' || cur == 'submit' || secs.any((s) => s['id'] == cur) ? cur : 'next',
          isDense: true,
          isExpanded: true,
          onChanged: !_canEdit ? null : (v) => _editSchema((secs) => v == 'next' ? secs[si].remove('next') : secs[si]['next'] = v),
          items: [
            const DropdownMenuItem(value: 'next', child: Text('Tiếp tục đến mục kế tiếp')),
            for (var i = 0; i < secs.length; i++)
              if (i != si) DropdownMenuItem(value: '${secs[i]['id']}', child: Text('Chuyển đến mục ${i + 1}${'${secs[i]['title'] ?? ''}'.isEmpty ? '' : ' (${secs[i]['title']})'}')),
            const DropdownMenuItem(value: 'submit', child: Text('Gửi biểu mẫu')),
          ],
        )),
      ]),
    );
  }
}
