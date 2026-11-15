// Biểu mẫu: hộp "Gửi biểu mẫu" — nội bộ (người trong tổ chức, có thể giới hạn người / phòng / vai trò) hoặc công khai (link
// không cần đăng nhập), link + QR + nhúng, đổi link, giới hạn một lần, cho sửa, ngày đóng / số tối đa, người cùng sửa / xem.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';
import 'api.dart';
import 'model.dart';
import 'widgets.dart';

/// Mở hộp gửi; trả biểu mẫu mới (nếu đổi) để trình soạn cập nhật.
Future<Json?> showShareSheet(BuildContext context, FormsApi api, Json form) {
  final wide = MediaQuery.sizeOf(context).width > 760;
  final color = colorOf(form['theme'] as String?);
  final child = FormTheme(color: color, child: _ShareBody(api: api, form: form));
  if (wide) {
    return showDialog<Json>(context: context, builder: (c) => Dialog(insetPadding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640, maxHeight: 780), child: child)));
  }
  return showModalBottomSheet<Json>(context: context, isScrollControlled: true, useSafeArea: true, builder: (c) => FractionallySizedBox(heightFactor: .92, child: child));
}

class _ShareBody extends StatefulWidget {
  const _ShareBody({required this.api, required this.form});
  final FormsApi api;
  final Json form;
  @override
  State<_ShareBody> createState() => _ShareBodyState();
}

class _ShareBodyState extends State<_ShareBody> {
  late Json _form = widget.form;
  late Json _s = Map<String, dynamic>.from(_form['settings'] as Map);
  bool _busy = false;
  List<Json> _depts = [], _roles = [];

  String get _id => '${_form['id']}';

  @override
  void initState() {
    super.initState();
    widget.api.get('/api/org').then((j) {
      if (!mounted) return;
      setState(() {
        _depts = [for (final d in (j['departments'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];
        _roles = [for (final r in (j['roles'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
      });
    }).catchError((_) {});
  }

  Future<void> _run(Future<Json> Function() f) async {
    setState(() => _busy = true);
    try {
      final j = await f();
      setState(() {
        _form = Map<String, dynamic>.from(j['form'] as Map);
        _s = Map<String, dynamic>.from(_form['settings'] as Map);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settings(Json patch) => _run(() => widget.api.put('/api/forms/$_id/settings', patch));

  Future<void> _publish() => _run(() => widget.api.post('/api/forms/$_id/publish', {'access': _s['access']}));

  Future<void> _closeAt() async {
    final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)), initialDate: DateTime.now().add(const Duration(days: 7)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 23, minute: 59));
    if (t == null) return;
    await _settings({'close_at': DateTime(d.year, d.month, d.day, t.hour, t.minute).millisecondsSinceEpoch});
  }

  Future<void> _maxResponses() async {
    final c = TextEditingController(text: _s['max_responses'] == null ? '' : '${_s['max_responses']}');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Số câu trả lời tối đa'),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Để trống = không giới hạn')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Lưu'))],
      ),
    );
    if (v != null) await _settings({'max_responses': v.trim().isEmpty ? null : int.tryParse(v.trim())});
  }

  /// Chọn người / phòng / vai trò. Trả {kind, ref, name}.
  Future<Json?> _pickSubject() => showDialog<Json>(
        context: context,
        builder: (ctx) => _SubjectPicker(api: widget.api, depts: _depts, roles: _roles),
      );

  Future<void> _addMember() async {
    final s = await _pickSubject();
    if (s == null) return;
    if (!mounted) return;
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text('Quyền của ${s['name']}'), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'editor'), child: const Text('Có thể sửa (sửa biểu mẫu + xem câu trả lời)')),
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'viewer'), child: const Text('Chỉ xem câu trả lời')),
      ]),
    );
    if (role == null) return;
    final list = [for (final m in (_form['members'] as List? ?? const [])) {'kind': (m as Map)['kind'], 'ref': m['ref'], 'role': m['role']}, {'kind': s['kind'], 'ref': s['ref'], 'role': role}];
    await _run(() => widget.api.put('/api/forms/$_id/members', {'members': list}));
  }

  Future<void> _removeMember(Json m) async {
    final list = [for (final x in (_form['members'] as List? ?? const [])) if (!((x as Map)['kind'] == m['kind'] && x['ref'] == m['ref'])) {'kind': x['kind'], 'ref': x['ref'], 'role': x['role']}];
    await _run(() => widget.api.put('/api/forms/$_id/members', {'members': list}));
  }

  Future<void> _addAudience() async {
    final s = await _pickSubject();
    if (s == null) return;
    final a = Map<String, dynamic>.from(_s['audience'] as Map? ?? const {});
    final key = s['kind'] == 'user' ? 'users' : s['kind'] == 'dept' ? 'depts' : 'roles';
    a[key] = {...(a[key] as List? ?? const []), s['ref']}.toList();
    a['everyone'] = false;
    await _settings({'audience': a});
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final color = FormTheme.of(context);
    final public = _s['access'] == 'public';
    final link = '${_form['link']}';
    final draft = _form['status'] == 'draft', open = _form['accepting'] == true;
    final audience = Map<String, dynamic>.from(_s['audience'] as Map? ?? const {});
    final names = Map<String, dynamic>.from(_form['audience_names'] as Map? ?? const {});
    Widget seg(String label, IconData icon, bool on, String help, VoidCallback tap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _busy ? null : tap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: on ? tintOf(color, isDark(context)) : null, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? color : p.divider, width: on ? 1.6 : 1)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: on ? color : p.sub),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text(help, style: TextStyle(color: p.sub, fontSize: 12))])),
              ]),
            ),
          ),
        );
    return Material(
      color: cardColor(context),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
          child: Row(children: [
            const Expanded(child: Text('Gửi biểu mẫu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
            if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            IconButton(onPressed: () => Navigator.pop(context, _form), icon: const Icon(Icons.close)),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
            Row(children: [
              seg('Nội bộ', Icons.lock_outline, !public, 'Người trong tổ chức, điền trong Flygo Chat', () => _settings({'access': 'internal'})),
              const SizedBox(width: 10),
              seg('Công khai', Icons.public, public, 'Ai có link đều điền được, không cần đăng nhập', () => _settings({'access': 'public'})),
            ]),
            if (!public) ...[
              const SizedBox(height: 12),
              Text('Ai được điền', style: TextStyle(color: p.sub, fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (audience['everyone'] != false) const Pill('Mọi người trong tổ chức', icon: Icons.groups_outlined),
                for (final u in (audience['users'] as List? ?? const [])) Pill('${names['$u'] ?? u}', icon: Icons.close, onTap: () => _settings({'audience': {...audience, 'users': (audience['users'] as List).where((x) => x != u).toList()}})),
                for (final d in (audience['depts'] as List? ?? const [])) Pill('${_depts.where((x) => x['id'] == d).firstOrNull?['name'] ?? d}', icon: Icons.close, onTap: () => _settings({'audience': {...audience, 'depts': (audience['depts'] as List).where((x) => x != d).toList()}})),
                for (final r in (audience['roles'] as List? ?? const [])) Pill('${_roles.where((x) => x['id'] == r).firstOrNull?['name'] ?? r}', icon: Icons.close, onTap: () => _settings({'audience': {...audience, 'roles': (audience['roles'] as List).where((x) => x != r).toList()}})),
                Pill('Giới hạn người / phòng…', icon: Icons.person_add_alt, bg: p.chipSelBg, fg: p.chipSelFg, onTap: _addAudience),
                if (audience['everyone'] == false) Pill('Cho mọi người', icon: Icons.public, onTap: () => _settings({'audience': {'everyone': true}})),
              ]),
            ],
            const SizedBox(height: 16),
            if (draft || !open)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(44)),
                onPressed: _busy ? null : _publish,
                icon: const Icon(Icons.send),
                label: Text(draft ? 'Gửi đi (bắt đầu nhận câu trả lời)' : 'Mở lại nhận câu trả lời'),
              ),
            if (!draft) ...[
              const SizedBox(height: 12),
              Text(public ? 'Link công khai' : 'Link (mở trong Flygo Chat)', style: TextStyle(color: p.sub, fontSize: 12.5)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(8)), child: SelectableText(link, maxLines: 1, style: const TextStyle(fontSize: 13.5)))),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: link));
                    ScaffoldMessenger.of(context).showSnackBar(toast(const Text('Đã sao chép link')));
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Sao chép'),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pill('QR', icon: Icons.qr_code_2, onTap: () => showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('${_form['title']}'),
                        content: SizedBox(width: 280, height: 300, child: Column(children: [QrImageView(data: link, size: 260, backgroundColor: Colors.white), const SizedBox(height: 6), Text(public ? 'Quét để điền' : 'Quét bằng Flygo Chat', style: TextStyle(color: p.sub))])),
                      ),
                    )),
                Pill('Chia sẻ…', icon: Icons.ios_share, onTap: () => SharePlus.instance.share(ShareParams(text: '${_form['title']}\n$link'))),
                if (public)
                  Pill('Nhúng vào web', icon: Icons.code, onTap: () {
                    Clipboard.setData(ClipboardData(text: '<iframe src="$link?embed=1" width="640" height="900" frameborder="0">Đang tải…</iframe>'));
                    ScaffoldMessenger.of(context).showSnackBar(toast(const Text('Đã sao chép mã nhúng')));
                  }),
                Pill('Đổi link', icon: Icons.refresh, onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Đổi link?'),
                      content: const Text('Link cũ sẽ không dùng được nữa.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Đổi link'))],
                    ),
                  );
                  if (ok == true) await _run(() => widget.api.post('/api/forms/$_id/rotate-link'));
                }),
              ]),
            ],
            const SizedBox(height: 14),
            Divider(height: 1, color: p.divider),
            const SizedBox(height: 6),
            SwitchRow(
              label: public ? 'Mỗi thiết bị chỉ gửi 1 lần' : 'Mỗi người chỉ gửi 1 lần',
              help: public ? 'Theo thiết bị (chặn nhẹ) + giới hạn tốc độ theo IP' : 'Theo tài khoản Flygo Chat',
              value: _s['one_per_user'] == true,
              onChanged: _busy ? null : (v) => _settings({'one_per_user': v}),
            ),
            if (!public) SwitchRow(label: 'Cho sửa sau khi gửi', value: _s['allow_edit'] == true, onChanged: _busy ? null : (v) => _settings({'allow_edit': v})),
            if (public) SwitchRow(label: 'Cho khách tải tệp lên', help: 'Tối đa 10 MB / tệp; tắt thì câu tải tệp chỉ điền được trong app', value: _s['public_uploads'] == true, onChanged: _busy ? null : (v) => _settings({'public_uploads': v})),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tự đóng lúc'),
              subtitle: Text(_s['close_at'] == null ? 'Không đặt' : fmtTime(_s['close_at'] as int)),
              trailing: _s['close_at'] == null ? const Icon(Icons.event) : IconButton(onPressed: () => _settings({'close_at': null}), icon: const Icon(Icons.close)),
              onTap: _closeAt,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Đóng khi đủ số câu trả lời'),
              subtitle: Text(_s['max_responses'] == null ? 'Không giới hạn' : '${_s['max_responses']} câu trả lời'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _maxResponses,
            ),
            const SizedBox(height: 6),
            Divider(height: 1, color: p.divider),
            const SizedBox(height: 10),
            Text('Người cùng sửa biểu mẫu và xem câu trả lời', style: TextStyle(color: p.sub, fontSize: 12.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Pill('${(_form['owner'] as Map?)?['name'] ?? ''} (chủ)', icon: Icons.person),
              for (final m in (_form['members'] as List? ?? const []))
                InputChip(
                  avatar: Icon((m as Map)['kind'] == 'user' ? Icons.person_outline : m['kind'] == 'dept' ? Icons.groups_outlined : Icons.badge_outlined, size: 16),
                  label: Text('${m['name']} · ${m['role'] == 'editor' ? 'Có thể sửa' : 'Xem câu trả lời'}', style: const TextStyle(fontSize: 12.5)),
                  onDeleted: _form['role'] == 'viewer' ? null : () => _removeMember(Map<String, dynamic>.from(m)),
                ),
              if (_form['role'] != 'viewer') Pill('Thêm người…', icon: Icons.person_add_alt, bg: p.chipSelBg, fg: p.chipSelFg, onTap: _addMember),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _SubjectPicker extends StatefulWidget {
  const _SubjectPicker({required this.api, required this.depts, required this.roles});
  final FormsApi api;
  final List<Json> depts, roles;
  @override
  State<_SubjectPicker> createState() => _SubjectPickerState();
}

class _SubjectPickerState extends State<_SubjectPicker> {
  List<Json> _people = [];
  String _q = '';

  Future<void> _search(String q) async {
    _q = q;
    if (q.trim().length < 2) {
      setState(() => _people = []);
      return;
    }
    try {
      final j = await widget.api.get('/api/people', {'q': q});
      if (mounted && q == _q) setState(() => _people = [for (final x in (j['people'] as List)) Map<String, dynamic>.from(x as Map)]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final depts = widget.depts.where((d) => q.isEmpty || '${d['name']}'.toLowerCase().contains(q));
    final roles = widget.roles.where((r) => q.isEmpty || '${r['name']}'.toLowerCase().contains(q));
    return AlertDialog(
      title: TextField(autofocus: true, decoration: const InputDecoration(hintText: 'Tìm người, phòng ban, vai trò', prefixIcon: Icon(Icons.search)), onChanged: _search),
      content: SizedBox(
        width: 420,
        height: 380,
        child: ListView(children: [
          for (final u in _people) ListTile(leading: const Icon(Icons.person_outline), title: Text('${u['name']}'), subtitle: Text('@${u['username']}'), onTap: () => Navigator.pop(context, {'kind': 'user', 'ref': u['id'], 'name': u['name']})),
          for (final d in depts) ListTile(leading: const Icon(Icons.groups_outlined), title: Text('${d['name']}'), subtitle: const Text('Phòng ban (gồm phòng con)'), onTap: () => Navigator.pop(context, {'kind': 'dept', 'ref': d['id'], 'name': d['name']})),
          for (final r in roles) ListTile(leading: const Icon(Icons.badge_outlined), title: Text('${r['name']}'), subtitle: const Text('Vai trò'), onTap: () => Navigator.pop(context, {'kind': 'role', 'ref': r['id'], 'name': r['name']})),
          if (_people.isEmpty && _q.trim().length < 2) const Padding(padding: EdgeInsets.all(12), child: Text('Gõ ít nhất 2 chữ để tìm người')),
        ]),
      ),
    );
  }
}
