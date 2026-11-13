// Bảng tin: soạn / sửa bài. Tiêu đề, nội dung Markdown (thanh định dạng + xem trước), chuyên mục, ảnh bìa, tệp,
// người nhận (toàn công ty / phòng ban / từng người), ghim (quản trị), ngày hết hạn, bắt buộc xác nhận + hạn.
// Kiểu mạng xã hội: nền màu cho chữ ngắn, nhiều ảnh, gắn thẻ người (nút hoặc gõ @).
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../config.dart' show isDesktop;
import '../../i18n/i18n.dart';
import '../app_route.dart';
import '../common.dart';
import '../markdown_view.dart';
import '../theme.dart';
import 'api.dart';
import 'backgrounds.dart';
import 'bang_tin_page.dart';
import 'feed_widgets.dart' show AvatarRing;

/// Mở trang soạn / sửa bài. Máy tính: hộp thoại giữa màn hình (Sếp); điện thoại: trang riêng. Trả về id bài đã lưu.
Future<String?> openBangTinEditor(
  BuildContext context, {
  required BangTinApi api,
  required BangTinMe me,
  Map<String, dynamic>? post,
  bool pickPhotos = false,
  bool pickBackground = false,
}) {
  final editor = BangTinEditor(api: api, me: me, post: post, pickPhotos: pickPhotos, pickBackground: pickBackground);
  if (!isDesktop) return Navigator.of(context).push<String>(AppPageRoute(builder: (_) => editor));
  return showDialog<String>(
    context: context,
    builder: (d) {
      final h = MediaQuery.sizeOf(d).height;
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(width: 600, height: (h * .9).clamp(420.0, 860.0), child: editor),
      );
    },
  );
}

class BangTinEditor extends StatefulWidget {
  const BangTinEditor({super.key, required this.api, required this.me, this.post, this.pickPhotos = false, this.pickBackground = false});
  final BangTinApi api;
  final BangTinMe me;

  /// Mở từ nút ảnh / nền màu ở ô soạn bài: mở luôn hộp chọn ảnh / chọn nền.
  final bool pickPhotos, pickBackground;

  /// Bài đang sửa (chi tiết từ GET /api/posts/:id); null = bài mới.
  final Map<String, dynamic>? post;

  @override
  State<BangTinEditor> createState() => _BangTinEditorState();
}

class _BangTinEditorState extends State<BangTinEditor> {
  late final _title = TextEditingController(text: '${widget.post?['title'] ?? ''}');
  late final _body = TextEditingController(text: '${widget.post?['body'] ?? ''}');
  String? _category;
  Map<String, dynamic>? _cover;
  List<Map<String, dynamic>> _files = [];
  bool _everyone = true;

  /// Phòng ban / người đã chọn: id → tên.
  Map<String, String> _depts = {}, _users = {};
  bool _pinned = false, _requireAck = false, _preview = false, _saving = false;
  String? _bg;

    /// Người được gắn thẻ: id → tên.
  Map<String, String> _tags = {};

  /// Bình chọn (Sếp): bật / tắt, câu hỏi, các lựa chọn, chọn nhiều, ẩn danh, hạn. Đã có người chọn thì khoá lựa chọn.
  bool _pollOn = false, _hadPoll = false, _pollLocked = false, _pollMulti = false, _pollAnon = false;
  int? _pollCloses;
  final _pollQ = TextEditingController();
  List<TextEditingController> _pollOpts = [TextEditingController(), TextEditingController()];
  String _lastBody = '';
  int? _expires, _deadline;
  final _uploading = <String>[];

  BangTinApi get api => widget.api;
  bool get _editing => widget.post != null;

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    _lastBody = _body.text;
    _body.addListener(_onBodyChanged);
    if (p == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.pickPhotos) _pickImages();
        if (widget.pickBackground) _chooseBg();
      });
      return;
    }
        _bg = p['bg'] as String?;
    if (p['poll'] is Map) {
      final pl = p['poll'] as Map;
      _pollOn = _hadPoll = true;
      _pollLocked = ((pl['voters'] as num?) ?? 0) > 0;
      _pollMulti = pl['multi'] == true;
      _pollAnon = pl['anonymous'] == true;
      _pollCloses = (pl['closes_at'] as num?)?.toInt();
      _pollQ.text = '${pl['question'] ?? ''}';
      _pollOpts = [for (final o in (pl['options'] as List? ?? const [])) TextEditingController(text: '${(o as Map)['text']}')];
    }
    _tags = {for (final t in (p['tags'] as List? ?? const [])) '${(t as Map)['id']}': '${t['name']}'};
    _category = p['category'] as String?;
    if (p['cover'] != null) _cover = {'id': p['cover'], 'name': '', 'mime': 'image/'};
    _files = [
      for (final f in (p['files'] as List? ?? const []))
        if (f is Map) Map<String, dynamic>.from(f),
    ];
    final a = p['audience'] as Map? ?? const {'everyone': true};
    _everyone = a['everyone'] == true;
    _depts = {for (final d in (a['depts'] as List? ?? const [])) '${(d as Map)['id']}': '${d['name']}'};
    _users = {for (final u in (a['users'] as List? ?? const [])) '${(u as Map)['id']}': '${u['name']}'};
    _pinned = p['pinned'] == true;
    _requireAck = p['require_ack'] == true;
    _expires = (p['expires_at'] as num?)?.toInt();
    _deadline = (p['ack_deadline'] as num?)?.toInt();
  }

  @override
  void dispose() {
    _title.dispose();
        _body.removeListener(_onBodyChanged);
    _body.dispose();
    _pollQ.dispose();
    for (final c in _pollOpts) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(toast(Text(s)));

  Future<void> _save() async {
        final pollOptions = [for (final c in _pollOpts) if (c.text.trim().isNotEmpty) c.text.trim()];
    if (_pollOn && pollOptions.length < 2) return _toast(tr('Bình chọn cần ít nhất 2 lựa chọn'));
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty && _files.isEmpty && _cover == null && !_pollOn) return _toast(tr('Viết gì đó hoặc thêm ảnh'));
    if (_useBg && _body.text.length > kBgMaxChars) return _toast(tr('Bài trên nền màu tối đa {0} ký tự', ['$kBgMaxChars']));
    if (!_everyone && _depts.isEmpty && _users.isEmpty) return _toast(tr('Chọn người nhận'));
    if (_uploading.isNotEmpty) return _toast(tr('Đang tải tệp lên, chờ một chút'));
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'body': _body.text,
      'category': _category,
      'cover': _cover?['id'],
      'files': [for (final f in _files) f['id']],
      'audience': _everyone ? {'everyone': true} : {'depts': _depts.keys.toList(), 'users': _users.keys.toList()},
      'expires_at': _expires,
      'bg': _useBg ? _bg : null,
            'tags': _tags.keys.toList(),
      if (_pollOn)
        'poll': {'question': _pollQ.text.trim(), 'options': pollOptions, 'multi': _pollMulti, 'anonymous': _pollAnon, 'closes_at': _pollCloses}
      else if (_hadPoll)
        'poll': null,
      'require_ack': _requireAck,
      'ack_deadline': _requireAck ? _deadline : null,
      'pinned': _pinned,
    };
    try {
      final r = _editing ? await api.patch('/api/posts/${widget.post!['id']}', body) : await api.post('/api/posts', body);
      if (mounted) Navigator.of(context).pop('${(r['post'] as Map)['id']}');
    } catch (e) {
      _toast('$e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Map<String, dynamic>?> _upload(PlatformFile p) async {
    if (p.path == null) return null;
    if (await File(p.path!).length() > 20 * 1024 * 1024) {
      _toast(tr('{0} lớn hơn 20 MB', [p.name]));
      return null;
    }
    setState(() => _uploading.add(p.name));
    try {
      return await api.upload(p.name, await File(p.path!).readAsBytes());
    } catch (e) {
      _toast(tr('Không tải được {0}: {1}', [p.name, '$e']));
      return null;
    } finally {
      if (mounted) setState(() => _uploading.remove(p.name));
    }
  }

  /// Nền chỉ dùng cho bài chữ ngắn, không có ảnh.
    bool get _useBg => _bg != null && _bg!.isNotEmpty && !_hasImages && !_pollOn;
  bool get _hasImages => _cover != null || _files.any((f) => '${f['mime']}'.startsWith('image/'));

  Future<void> _chooseBg() async {
    final v = await pickBackground(context, current: _bg);
    if (v != null && mounted) setState(() => _bg = v.isEmpty ? null : v);
  }

  Future<void> _pickImages() async {
    final picked = await _pick(() => FilePicker.pickFiles(type: FileType.image));
    for (final p in picked) {
      if (_files.length >= 20) {
        _toast(tr('Tối đa 20 tệp đính kèm'));
        break;
      }
      final f = await _upload(p);
      if (f != null && mounted) setState(() => _files = [..._files, f]);
    }
  }

  /// Gõ "@" (đầu dòng hoặc sau khoảng trắng) trong nội dung: mở danh sách người để gắn thẻ, chèn "@Tên".
  void _onBodyChanged() {
    final t = _body.text, old = _lastBody;
    _lastBody = t;
    final sel = _body.selection;
    if (t.length != old.length + 1 || !sel.isValid || sel.start < 1 || t[sel.start - 1] != '@') return;
    if (sel.start >= 2 && !RegExp(r'\s').hasMatch(t[sel.start - 2])) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final r = await _pickPeople(single: true);
      if (r == null || r.isEmpty || !mounted) return;
      final e = r.entries.first;
      final at = sel.start;
      final v = _body.text;
      if (at > v.length || v[at - 1] != '@') return;
      final ins = '${e.value} ';
      _body.value = TextEditingValue(
        text: v.replaceRange(at, at, ins),
        selection: TextSelection.collapsed(offset: at + ins.length),
      );
      _lastBody = _body.text;
      setState(() => _tags = {..._tags, e.key: e.value});
    });
  }

  Future<Map<String, String>?> _pickPeople({bool single = false}) => Navigator.of(context).push<Map<String, String>>(
    AppPageRoute(
      builder: (_) => _PeoplePicker(api: api, selected: single ? const {} : _tags, single: single),
    ),
  );

  Future<void> _pickTags() async {
    final r = await _pickPeople();
    if (r != null && mounted) setState(() => _tags = r);
  }

  /// Mở hộp chọn tệp; lỗi (vd thiếu quyền) thì báo, không im lặng (trước đây bấm không thấy gì).
  Future<List<PlatformFile>> _pick(Future<List<PlatformFile>> Function() open) async {
    try {
      return await open();
    } catch (e) {
      _toast(tr('Không mở được hộp chọn tệp: {0}', ['$e']));
      return const [];
    }
  }

  Future<void> _pickCover() async {
    final picked = await _pick(() => FilePicker.pickFiles(type: FileType.image));
    if (picked.isEmpty) return;
    final f = await _upload(picked.first);
    if (f != null && mounted) setState(() => _cover = f);
  }

  Future<void> _pickFiles() async {
    final picked = await _pick(() => FilePicker.pickFiles());
    for (final p in picked) {
      if (_files.length >= 20) {
        _toast(tr('Tối đa 20 tệp đính kèm'));
        break;
      }
      final f = await _upload(p);
      if (f != null && mounted) setState(() => _files = [..._files, f]);
    }
  }

  Future<int?> _pickDateTime(int? current) async {
    final now = DateTime.now();
    final init = current == null ? now.add(const Duration(days: 3)) : DateTime.fromMillisecondsSinceEpoch(current);
    final d = await showDatePicker(
      context: context,
      initialDate: init.isBefore(now) ? now : init,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: current == null ? const TimeOfDay(hour: 17, minute: 0) : TimeOfDay.fromDateTime(init));
    if (t == null) return null;
    final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (!at.isAfter(DateTime.now())) {
      _toast(tr('Chọn thời điểm trong tương lai'));
      return null;
    }
    return at.millisecondsSinceEpoch;
  }

  Future<void> _pickAudience() async {
    final r = await Navigator.of(context).push<(Map<String, String>, Map<String, String>)>(
      AppPageRoute(
        builder: (_) => _AudiencePicker(api: api, depts: _depts, users: _users),
      ),
    );
    if (r != null) setState(() => (_depts = r.$1, _users = r.$2));
  }

  /// Bọc chữ đang chọn trong ô nội dung bằng [left] / [right] (thanh định dạng).
  void _wrap(String left, [String? right]) {
    final v = _body.value;
    final s = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final sel = v.text.substring(s.start, s.end);
    final r = right ?? left;
    final text = v.text.replaceRange(s.start, s.end, '$left$sel$r');
    _body.value = TextEditingValue(
      text: text,
      selection: sel.isEmpty
          ? TextSelection.collapsed(offset: s.start + left.length)
          : TextSelection(baseOffset: s.start, extentOffset: s.end + left.length + r.length),
    );
  }

  /// Thêm [prefix] vào đầu dòng đang đứng (danh sách, tiêu đề).
  void _linePrefix(String prefix) {
    final v = _body.value;
    final at = v.selection.isValid ? v.selection.start : v.text.length;
    final lineStart = v.text.lastIndexOf('\n', at > 0 ? at - 1 : 0) + 1;
    final start = at == 0 ? 0 : lineStart;
    _body.value = TextEditingValue(
      text: v.text.replaceRange(start, start, prefix),
      selection: TextSelection.collapsed(offset: at + prefix.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final cats = widget.me.categories;
    final images = _files.where((f) => '${f['mime']}'.startsWith('image/')).toList();
    final others = _files.where((f) => !'${f['mime']}'.startsWith('image/')).toList();
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
    final audience = _everyone
        ? tr('Toàn công ty')
        : (_depts.length + _users.length == 0 ? tr('Chọn người nhận') : tr('{0} phòng ban, người', ['${_depts.length + _users.length}']));
    return Scaffold(
      backgroundColor: pal.surface,
      appBar: AppBar(
        backgroundColor: pal.surface,
        centerTitle: true,
        // Hộp thoại trên máy tính: nút đóng thay nút quay lại.
        leading: isDesktop ? IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.maybePop(context)) : null,
        title: Text(_editing ? tr('Sửa bài viết') : tr('Tạo bài viết'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _saving || _uploading.isNotEmpty ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_editing ? tr('Lưu') : tr('Đăng'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              // Người đăng + người nhận (như "Tạo bài viết" của Facebook).
              Row(
                children: [
                  AvatarRing(userId: widget.me.id, name: widget.me.name, size: 46, gold: widget.me.admin),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.me.name,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: pal.text),
                        ),
                        const SizedBox(height: 3),
                        PopupMenuButton<bool>(
                          tooltip: tr('Người nhận'),
                          onSelected: (v) async {
                            setState(() => _everyone = v);
                            if (!v) await _pickAudience();
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: true,
                              child: ListTile(leading: const Icon(Icons.public_rounded), title: Text(tr('Toàn công ty'))),
                            ),
                            PopupMenuItem(
                              value: false,
                              child: ListTile(leading: const Icon(Icons.groups_rounded), title: Text(tr('Chọn phòng ban, người'))),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_everyone ? Icons.public_rounded : Icons.groups_rounded, size: 15, color: pal.text),
                                const SizedBox(width: 4),
                                Text(
                                  audience,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text),
                                ),
                                Icon(Icons.arrow_drop_down_rounded, size: 18, color: pal.text),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!_everyone && _depts.length + _users.length > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final d in _depts.entries)
                        InputChip(
                          avatar: const Icon(Icons.groups_rounded, size: 16),
                          label: Text(d.value),
                          onDeleted: () => setState(() => _depts = {..._depts}..remove(d.key)),
                        ),
                      for (final u in _users.entries)
                        InputChip(
                          avatar: const Icon(Icons.person_rounded, size: 16),
                          label: Text(u.value),
                          onDeleted: () => setState(() => _users = {..._users}..remove(u.key)),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              // Nội dung: có nền thì gõ thẳng trên nền (chữ to giữa nền); không nền thì ô chữ thường.
              if (_useBg)
                SizedBox(
                  height: 280,
                  child: BgBox(
                    spec: bgById(_bg) ?? kBackgrounds.first,
                    radius: 14,
                    child: Center(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _body,
                        builder: (_, v, _) => TextField(
                          controller: _body,
                          autofocus: true,
                          maxLines: null,
                          maxLength: kBgMaxChars,
                          textAlign: TextAlign.center,
                          textCapitalization: TextCapitalization.sentences,
                          cursorColor: (bgById(_bg) ?? kBackgrounds.first).text,
                          style: TextStyle(
                            color: (bgById(_bg) ?? kBackgrounds.first).text,
                            fontSize: BgText.fontSize(v.text),
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 28),
                            hintText: tr('Bạn đang nghĩ gì?'),
                            hintStyle: TextStyle(color: (bgById(_bg) ?? kBackgrounds.first).text.withValues(alpha: .7)),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (_preview)
                Container(
                  constraints: const BoxConstraints(minHeight: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: pal.divider),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _body.text.trim().isEmpty
                      ? Text(tr('Chưa có nội dung'), style: TextStyle(color: pal.sub))
                      : MarkdownView(
                          text: _body.text,
                          style: TextStyle(fontSize: 15.5, color: pal.text, height: 1.45),
                        ),
                )
              else
                TextField(
                  controller: _body,
                  autofocus: !widget.pickPhotos && !_editing,
                  minLines: 5,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontSize: _body.text.length > 120 || images.isNotEmpty ? 16 : 20, color: pal.text, height: 1.4),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: tr('Bạn có gì muốn chia sẻ hôm nay?'),
                    hintStyle: TextStyle(color: pal.sub, fontSize: 20),
                  ),
                ),
              // Dải nền màu luôn hiện để chọn ngay (bài có ảnh hoặc bình chọn thì không dùng nền).
              if (!_hasImages && !_pollOn)
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      _bgTile(pal, null),
                      for (final b in kBackgrounds) _bgTile(pal, b),
                      Tooltip(
                        message: tr('Chọn nền'),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _chooseBg,
                          child: Container(
                            width: 38,
                            height: 38,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.grid_view_rounded, size: 20, color: pal.sub),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_useBg && !_preview)
                Row(
                  children: [
                    for (final (icon, tip, act) in [
                      (Icons.format_bold_rounded, tr('Đậm'), () => _wrap('**')),
                      (Icons.format_italic_rounded, tr('Nghiêng'), () => _wrap('_')),
                      (Icons.format_list_bulleted_rounded, tr('Danh sách'), () => _linePrefix('- ')),
                      (Icons.link_rounded, tr('Liên kết'), () => _wrap('[', '](https://)')),
                    ])
                      IconButton(
                        tooltip: tip,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(icon, size: 19, color: pal.sub),
                        onPressed: act,
                      ),
                    const Spacer(),
                    TextButton(onPressed: () => setState(() => _preview = true), child: Text(tr('Xem trước'))),
                  ],
                ),
              if (_preview && !_useBg)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => setState(() => _preview = false), child: Text(tr('Soạn'))),
                ),
              if (images.isNotEmpty || _uploading.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in images)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 104,
                              height: 104,
                              child: BangTinImage(api: api, fileId: '${f['id']}'),
                            ),
                          ),
                          Positioned(
                            right: 3,
                            top: 3,
                            child: InkWell(
                              onTap: () => setState(() => _files = [..._files]..removeWhere((x) => x['id'] == f['id'])),
                              child: const CircleAvatar(
                                radius: 11,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    for (final _ in _uploading)
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
                        child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                  ],
                ),
              ],
              if (_tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(tr('cùng với'), style: TextStyle(color: pal.sub)),
                      for (final t in _tags.entries) InputChip(label: Text('@${t.value}'), onDeleted: () => setState(() => _tags = {..._tags}..remove(t.key))),
                    ],
                  ),
                ),
              for (final f in others)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: f['size'] == null ? null : Text(fileSize((f['size'] as num).toInt())),
                  trailing: IconButton(
                    tooltip: tr('Bỏ'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _files = [..._files]..removeWhere((x) => x['id'] == f['id'])),
                  ),
                ),
              const SizedBox(height: 12),
                            if (_pollOn) ...[_pollEditor(pal), const SizedBox(height: 12)],
              // "Thêm vào bài viết": ảnh, gắn thẻ, tệp tách riêng (như Facebook).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: pal.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Thêm vào bài viết'),
                        style: TextStyle(fontWeight: FontWeight.w600, color: pal.text),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Thêm ảnh'),
                      onPressed: _pickImages,
                      icon: const Icon(Icons.photo_library_rounded, color: Color(0xFF45BD62)),
                    ),
                    IconButton(
                      tooltip: tr('Gắn thẻ người'),
                      onPressed: _pickTags,
                      icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF1877F2)),
                    ),
                    IconButton(
                      tooltip: tr('Thêm tệp'),
                      onPressed: _pickFiles,
                      icon: const Icon(Icons.attach_file_rounded, color: Color(0xFFF5A623)),
                    ),
                    IconButton(
                      tooltip: tr('Bình chọn'),
                      onPressed: () => setState(() => _pollOn = !_pollOn),
                      icon: Icon(Icons.poll_rounded, color: _pollOn ? pal.accent : const Color(0xFFE8833A)),
                    ),
                    IconButton(
                      tooltip: tr('Nền màu'),
                      onPressed: _hasImages ? null : _chooseBg,
                      icon: const Icon(Icons.palette_rounded, color: Color(0xFFB45BFF)),
                    ),
                  ],
                ),
              ),
              if (_bg != null && _hasImages)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr('Bài có ảnh nên không dùng nền màu'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
                ),
              // Tuỳ chọn ít dùng: tiêu đề, chuyên mục, ảnh bìa, hết hạn, bắt buộc xác nhận, ghim.
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  // Khoảng trên để nhãn nổi của ô Tiêu đề (đang gõ) không bị cắt (Sếp, ảnh Android).
                  childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
                  initiallyExpanded: _editing && (_title.text.isNotEmpty || _requireAck || _expires != null || _category != null),
                  title: Text(
                    tr('Tuỳ chọn khác'),
                    style: TextStyle(fontWeight: FontWeight.w600, color: pal.text),
                  ),
                  subtitle: Text(tr('Tiêu đề, chuyên mục, ảnh bìa, hết hạn, bắt buộc xác nhận'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
                  children: [
                    TextField(
                      controller: _title,
                      maxLength: 200,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: deco(tr('Tiêu đề (không bắt buộc)')),
                    ),
                    if (cats.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String?>(
                        initialValue: cats.any((c) => c['id'] == _category) ? _category : null,
                        decoration: deco(tr('Chuyên mục')),
                        items: [
                          DropdownMenuItem(value: null, child: Text(tr('Không có'))),
                          for (final c in cats) DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}')),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_cover != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 2.4,
                              child: BangTinImage(api: api, fileId: '${_cover!['id']}'),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: IconButton.filledTonal(
                              tooltip: tr('Bỏ ảnh bìa'),
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _cover = null),
                            ),
                          ),
                        ],
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(onPressed: _pickCover, icon: const Icon(Icons.image_outlined), label: Text(tr('Chọn ảnh bìa'))),
                      ),
                    // Bài đang ghim: chỉ quản trị bỏ ghim được (Sếp).
                    if (widget.me.admin || widget.post?['pinned'] != true)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _pinned,
                        onChanged: (v) => setState(() => _pinned = v),
                        title: Text(tr('Ghim lên đầu')),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _expires != null,
                      onChanged: (v) async {
                        if (!v) return setState(() => _expires = null);
                        final at = await _pickDateTime(_expires);
                        if (at != null) setState(() => _expires = at);
                      },
                      title: Text(tr('Hết hạn')),
                      subtitle: Text(_expires == null ? tr('Bài hết hạn sẽ chuyển vào Lưu trữ') : bangTinTime(_expires!)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _requireAck,
                      onChanged: (v) => setState(() => _requireAck = v),
                      title: Text(tr('Bắt buộc xác nhận đã đọc')),
                      subtitle: Text(tr('Người nhận phải bấm "Tôi đã đọc"; ai chưa xác nhận sẽ được nhắc')),
                    ),
                    if (_requireAck)
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 12),
                        leading: const Icon(Icons.event_outlined),
                        title: Text(_deadline == null ? tr('Không có hạn xác nhận') : tr('Hạn xác nhận: {0}', [bangTinTime(_deadline!)])),
                        trailing: _deadline == null
                            ? TextButton(
                                onPressed: () async {
                                  final at = await _pickDateTime(null);
                                  if (at != null) setState(() => _deadline = at);
                                },
                                child: Text(tr('Đặt hạn')),
                              )
                            : IconButton(tooltip: tr('Bỏ hạn'), icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _deadline = null)),
                        onTap: () async {
                          final at = await _pickDateTime(_deadline);
                          if (at != null) setState(() => _deadline = at);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pollEditor(Pal pal) {
    InputDecoration deco(String hint) => InputDecoration(hintText: hint, isDense: true, counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
      decoration: BoxDecoration(border: Border.all(color: pal.divider), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.poll_rounded, color: pal.accentText),
          const SizedBox(width: 6),
          Expanded(child: Text(tr('Bình chọn'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
          IconButton(tooltip: tr('Bỏ bình chọn'), icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _pollOn = false)),
        ]),
        if (_pollLocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, right: 8),
            child: Text(tr('Đã có người chọn: chỉ đổi được hạn bình chọn'), style: const TextStyle(color: Color(0xFFE8833A), fontSize: 12.5)),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(controller: _pollQ, enabled: !_pollLocked, maxLength: 300, decoration: deco(tr('Câu hỏi (không bắt buộc)'))),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _pollOpts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: TextField(controller: _pollOpts[i], enabled: !_pollLocked, maxLength: 100, decoration: deco(tr('Lựa chọn {0}', ['${i + 1}']))),
              ),
              IconButton(
                tooltip: tr('Bỏ'),
                icon: const Icon(Icons.remove_circle_outline_rounded),
                onPressed: _pollLocked || _pollOpts.length <= 2
                    ? null
                    : () => setState(() {
                          _pollOpts[i].dispose();
                          _pollOpts = [..._pollOpts]..removeAt(i);
                        }),
              ),
            ]),
          ),
        if (!_pollLocked && _pollOpts.length < 10)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _pollOpts = [..._pollOpts, TextEditingController()]),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Thêm lựa chọn')),
            ),
          ),
        SwitchListTile(
          contentPadding: const EdgeInsets.only(right: 8),
          dense: true,
          value: _pollMulti,
          onChanged: _pollLocked ? null : (v) => setState(() => _pollMulti = v),
          title: Text(tr('Cho chọn nhiều')),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.only(right: 8),
          dense: true,
          value: _pollAnon,
          onChanged: _pollLocked ? null : (v) => setState(() => _pollAnon = v),
          title: Text(tr('Ẩn danh')),
          subtitle: Text(tr('Không ai xem được ai đã chọn gì')),
        ),
        ListTile(
          contentPadding: const EdgeInsets.only(right: 8),
          dense: true,
          leading: const Icon(Icons.event_outlined),
          title: Text(_pollCloses == null ? tr('Không có hạn bình chọn') : tr('Kết thúc {0}', [bangTinTime(_pollCloses!)])),
          trailing: _pollCloses == null
              ? TextButton(
                  onPressed: () async {
                    final at = await _pickDateTime(null);
                    if (at != null) setState(() => _pollCloses = at);
                  },
                  child: Text(tr('Đặt hạn')),
                )
              : IconButton(tooltip: tr('Bỏ hạn'), icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _pollCloses = null)),
        ),
      ]),
    );
  }

  /// Ô nền trong dải chọn nhanh; [b] null = không nền ("Aa").
  Widget _bgTile(Pal pal, BgSpec? b) {
    final selected = b == null ? (_bg == null || _bg!.isEmpty) : _bg == b.id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _bg = b?.id),
        child: Container(
          width: 38,
          height: 38,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: selected ? pal.accent : Colors.transparent, width: 2),
          ),
          child: b == null
              ? Container(
                  decoration: BoxDecoration(
                    color: pal.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: pal.divider),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Aa',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: pal.sub),
                  ),
                )
              : BgBox(spec: b, radius: 8),
        ),
      ),
    );
  }
}

/// Chọn phòng ban (cây, gồm cả phòng con) và từng người.
class _AudiencePicker extends StatefulWidget {
  const _AudiencePicker({required this.api, required this.depts, required this.users});
  final BangTinApi api;
  final Map<String, String> depts, users;

  @override
  State<_AudiencePicker> createState() => _AudiencePickerState();
}

class _AudiencePickerState extends State<_AudiencePicker> {
  late final Map<String, String> _depts = {...widget.depts}, _users = {...widget.users};
  List<(Map<String, dynamic>, int)> _tree = const [];
  List<Map<String, dynamic>> _people = const [];
  String? _error;
  bool _loading = true;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.api.get('/api/directory');
      final depts = [
        for (final d in (j['departments'] as List? ?? const []))
          if (d is Map) Map<String, dynamic>.from(d),
      ];
      // Sắp phòng ban thành cây (cha trước, con thụt vào).
      final kids = <String?, List<Map<String, dynamic>>>{};
      final ids = {for (final d in depts) d['id']};
      for (final d in depts) {
        kids.putIfAbsent(ids.contains(d['parent']) ? d['parent'] as String? : null, () => []).add(d);
      }
      final tree = <(Map<String, dynamic>, int)>[];
      void walk(String? parent, int depth) {
        final list = [...?kids[parent]]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
        for (final d in list) {
          tree.add((d, depth));
          if (depth < 20) walk('${d['id']}', depth + 1);
        }
      }

      walk(null, 0);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _people = [
          for (final p in (j['people'] as List? ?? const []))
            if (p is Map) Map<String, dynamic>.from(p),
        ];
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _loading = false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final q = _q.text.trim().toLowerCase();
    final tree = q.isEmpty ? _tree : _tree.where((t) => '${t.$1['name']}'.toLowerCase().contains(q)).toList();
    final people = q.isEmpty ? _people : _people.where((p) => '${p['name']}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        title: Text(tr('Chọn người nhận')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: () => Navigator.pop(context, (_depts, _users)), child: Text(tr('Xong ({0})', ['${_depts.length + _users.length}']))),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: TextStyle(color: pal.sub)),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: tr('Tìm phòng ban, người'),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (tree.isNotEmpty) _header(pal, tr('Phòng ban (gồm cả phòng con)')),
                      for (final (d, depth) in tree)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.only(left: 16 + (q.isEmpty ? depth * 20.0 : 0), right: 12),
                          value: _depts.containsKey(d['id']),
                          onChanged: (v) => setState(() => v == true ? _depts['${d['id']}'] = '${d['name']}' : _depts.remove(d['id'])),
                          secondary: const Icon(Icons.groups_rounded),
                          title: Text('${d['name']}'),
                          subtitle: Text(tr('{0} người', ['${d['members']}'])),
                        ),
                      if (people.isNotEmpty) _header(pal, tr('Người')),
                      for (final p in people)
                        CheckboxListTile(
                          value: _users.containsKey(p['id']),
                          onChanged: (v) => setState(() => v == true ? _users['${p['id']}'] = '${p['name']}' : _users.remove(p['id'])),
                          secondary: Avatar(userId: '${p['id']}', name: '${p['name']}', size: 32, status: false),
                          title: Text('${p['name']}'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header(Pal pal, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      t,
      style: TextStyle(color: pal.sub, fontWeight: FontWeight.w600, fontSize: 13),
    ),
  );
}

/// Chọn người (gắn thẻ). [single]: chọn một người là xong.
class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({required this.api, required this.selected, this.single = false});
  final BangTinApi api;
  final Map<String, String> selected;
  final bool single;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  late final Map<String, String> _sel = {...widget.selected};
  List<Map<String, dynamic>> _people = const [];
  String? _error;
  bool _loading = true;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.api.get('/api/directory');
      final people = [
        for (final p in (j['people'] as List? ?? const []))
          if (p is Map) Map<String, dynamic>.from(p),
      ];
      if (mounted) setState(() => (_people = people, _loading = false));
    } catch (e) {
      if (mounted) setState(() => (_error = '$e', _loading = false));
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final q = _q.text.trim().toLowerCase();
    final people = q.isEmpty ? _people : _people.where((p) => '${p['name']}'.toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        title: Text(tr('Gắn thẻ người')),
        actions: [
          if (!widget.single)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(onPressed: () => Navigator.pop(context, _sel), child: Text(tr('Xong ({0})', ['${_sel.length}']))),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: TextStyle(color: pal.sub)),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    controller: _q,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: tr('Tìm người'),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final p in people)
                        widget.single
                            ? ListTile(
                                leading: Avatar(userId: '${p['id']}', name: '${p['name']}', size: 34, status: false),
                                title: Text('${p['name']}'),
                                onTap: () => Navigator.pop(context, {'${p['id']}': '${p['name']}'}),
                              )
                            : CheckboxListTile(
                                value: _sel.containsKey(p['id']),
                                onChanged: (v) => setState(() => v == true ? _sel['${p['id']}'] = '${p['name']}' : _sel.remove(p['id'])),
                                secondary: Avatar(userId: '${p['id']}', name: '${p['name']}', size: 34, status: false),
                                title: Text('${p['name']}'),
                              ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
