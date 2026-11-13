// Todo: các hộp chọn — lời nhắc (có lặp lại), nhãn, chia sẻ (có thể sửa / chỉ xem), sửa nhãn, màu và hình nền.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config.dart' show isDesktop;
import '../../i18n/i18n.dart';
import 'look.dart';
import 'model.dart';
import 'store.dart';

/// Mở như hộp thoại trên máy tính, như bảng trượt từ dưới lên trên điện thoại.
Future<T?> showTodoSheet<T>(BuildContext context, {required String title, required WidgetBuilder builder, double width = 420}) {
  Widget body(BuildContext c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 18, 12, 6), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        Flexible(child: builder(c)),
      ]);
  if (isDesktop) {
    return showDialog<T>(
      context: context,
      builder: (c) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(c).height * .85), child: body(c)),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom), child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .85), child: body(c))),
  );
}

// ------------------------------------------------------------ lời nhắc
String repeatName(String? r) {
  if (r == null) return tr('Không lặp lại');
  final m = RegExp(r'^every:(\d+)([dwm])$').firstMatch(r);
  if (m != null) return tr('Mỗi {0} {1}', [m[1], {'d': tr('ngày'), 'w': tr('tuần'), 'm': tr('tháng')}[m[2]]]);
  return tr(kRepeats[r] ?? r);
}

String reminderLabel(TReminder r) {
  final t = DateTime.fromMillisecondsSinceEpoch(r.at);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day), day = DateTime(t.year, t.month, t.day);
  final hm = DateFormat('HH:mm').format(t);
  final d = day == today
      ? tr('Hôm nay')
      : day == today.add(const Duration(days: 1))
          ? tr('Ngày mai')
          : day == today.subtract(const Duration(days: 1))
              ? tr('Hôm qua')
              : DateFormat(t.year == now.year ? 'dd/MM' : 'dd/MM/yyyy').format(t);
  return '$d, $hm';
}

/// Chọn lời nhắc. Trả về null nếu huỷ; (null) trong record nếu bỏ lời nhắc.
Future<({TReminder? value})?> pickReminder(BuildContext context, TReminder? cur) {
  final now = DateTime.now();
  DateTime at(int addDays, int h, [int m = 0]) => DateTime(now.year, now.month, now.day + addDays, h, m);
  final nextMon = at((8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7, 8);
  final quick = <(String, DateTime)>[
    if (now.hour < 19) (tr('Tối nay'), at(0, 20)),
    (tr('Sáng mai'), at(1, 8)),
    (tr('Chiều mai'), at(1, 14)),
    (tr('Thứ Hai tuần sau'), nextMon),
  ];
  return showTodoSheet<({TReminder? value})>(context, title: tr('Lời nhắc'), builder: (c) => _ReminderForm(cur: cur, quick: quick));
}

class _ReminderForm extends StatefulWidget {
  const _ReminderForm({required this.cur, required this.quick});
  final TReminder? cur;
  final List<(String, DateTime)> quick;
  @override
  State<_ReminderForm> createState() => _ReminderFormState();
}

class _ReminderFormState extends State<_ReminderForm> {
  late DateTime _at = widget.cur != null && widget.cur!.at > DateTime.now().millisecondsSinceEpoch
      ? DateTime.fromMillisecondsSinceEpoch(widget.cur!.at)
      : DateTime.now().add(const Duration(hours: 1)).copyWith(minute: 0, second: 0, millisecond: 0, microsecond: 0);
  late String? _repeat = widget.cur?.repeat;
  int _every = 2;
  String _unit = 'd';

  @override
  void initState() {
    super.initState();
    final m = RegExp(r'^every:(\d+)([dwm])$').firstMatch(_repeat ?? '');
    if (m != null) {
      _every = int.parse(m[1]!);
      _unit = m[2]!;
      _repeat = 'every';
    }
  }

  String? get _repeatCode => _repeat == 'every' ? 'every:$_every$_unit' : _repeat;

  void _done(DateTime t) => Navigator.pop(context, (value: TReminder(t.millisecondsSinceEpoch, repeat: _repeatCode)));

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurface.withValues(alpha: .6);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (name, t) in widget.quick)
          ListTile(
            dense: true,
            leading: const Icon(Icons.schedule_rounded),
            title: Text(name),
            trailing: Text(DateFormat('EEE dd/MM, HH:mm', appLanguage.value).format(t), style: TextStyle(color: sub)),
            onTap: () => _done(t),
          ),
        const Divider(),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(DateFormat('dd/MM/yyyy').format(_at)),
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
                if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.access_time_rounded, size: 18),
              label: Text(DateFormat('HH:mm').format(_at)),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
                if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
              },
            ),
          ),
        ]),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _repeat,
          decoration: InputDecoration(labelText: tr('Lặp lại'), border: const OutlineInputBorder(), isDense: true),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('Không lặp lại'))),
            for (final e in kRepeats.entries) DropdownMenuItem(value: e.key, child: Text(tr(e.value))),
            DropdownMenuItem(value: 'every', child: Text(tr('Tuỳ chỉnh…'))),
          ],
          onChanged: (v) => setState(() => _repeat = v),
        ),
        if (_repeat == 'every') ...[
          const SizedBox(height: 10),
          Row(children: [
            Text(tr('Mỗi')),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: DropdownButtonFormField<int>(
                initialValue: _every,
                isDense: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [for (var i = 1; i <= 30; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                onChanged: (v) => setState(() => _every = v ?? 2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _unit,
                isDense: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: [DropdownMenuItem(value: 'd', child: Text(tr('ngày'))), DropdownMenuItem(value: 'w', child: Text(tr('tuần'))), DropdownMenuItem(value: 'm', child: Text(tr('tháng')))],
                onChanged: (v) => setState(() => _unit = v ?? 'd'),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 8),
        Text(tr('Đến giờ, bot Todo sẽ nhắn riêng cho bạn trong chat.'), style: TextStyle(fontSize: 12.5, color: sub)),
        const SizedBox(height: 12),
        Row(children: [
          if (widget.cur != null) TextButton.icon(icon: const Icon(Icons.notifications_off_outlined), label: Text(tr('Bỏ lời nhắc')), onPressed: () => Navigator.pop(context, (value: null))),
          const Spacer(),
          FilledButton(onPressed: () => _done(_at), child: Text(tr('Lưu'))),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------ nhãn
/// Chọn nhãn cho ghi chú; gõ tên chưa có thì tạo nhãn mới. Trả về danh sách id nhãn.
Future<List<String>?> pickLabels(BuildContext context, TodoStore store, List<String> cur) =>
    showTodoSheet<List<String>>(context, title: tr('Gắn nhãn'), builder: (_) => _LabelPicker(store: store, cur: cur));

class _LabelPicker extends StatefulWidget {
  const _LabelPicker({required this.store, required this.cur});
  final TodoStore store;
  final List<String> cur;
  @override
  State<_LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<_LabelPicker> {
  late final Set<String> _on = {...widget.cur};
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim();
    final list = widget.store.labels.where((l) => l.name.toLowerCase().contains(q.toLowerCase())).toList();
    final exact = widget.store.labels.any((l) => l.name.toLowerCase() == q.toLowerCase());
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(controller: _q, autofocus: isDesktop, decoration: InputDecoration(hintText: tr('Nhập tên nhãn'), prefixIcon: const Icon(Icons.search_rounded), isDense: true), onChanged: (_) => setState(() {})),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          for (final l in list)
            CheckboxListTile(
              dense: true,
              value: _on.contains(l.id),
              title: Text(l.name),
              secondary: const Icon(Icons.label_outline_rounded),
              onChanged: (v) => setState(() => v == true ? _on.add(l.id) : _on.remove(l.id)),
            ),
          if (q.isNotEmpty && !exact)
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_rounded),
              title: Text(tr('Tạo nhãn "{0}"', [q])),
              onTap: () => setState(() {
                _on.add(widget.store.putLabel(q).id);
                _q.clear();
              }),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        child: Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => Navigator.pop(context, _on.toList()), child: Text(tr('Xong')))),
      ),
    ]);
  }
}

/// Sửa nhãn: thêm, đổi tên, xoá.
Future<void> editLabels(BuildContext context, TodoStore store) => showTodoSheet<void>(context, title: tr('Chỉnh sửa nhãn'), builder: (_) => _LabelEditor(store: store));

class _LabelEditor extends StatefulWidget {
  const _LabelEditor({required this.store});
  final TodoStore store;
  @override
  State<_LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends State<_LabelEditor> {
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  void _add() {
    final n = _new.text.trim();
    if (n.isEmpty || widget.store.labels.any((l) => l.name.toLowerCase() == n.toLowerCase())) return;
    widget.store.putLabel(n);
    _new.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), children: [
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: TextField(controller: _new, decoration: InputDecoration(hintText: tr('Tạo nhãn mới'), isDense: true, border: InputBorder.none), onSubmitted: (_) => _add()),
          trailing: IconButton(icon: const Icon(Icons.check_rounded), onPressed: _add),
        ),
        for (final l in widget.store.labels)
          ListTile(
            key: ValueKey(l.id),
            leading: IconButton(
              tooltip: tr('Xoá nhãn'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    content: Text(tr('Xoá nhãn "{0}"? Nhãn sẽ được gỡ khỏi mọi ghi chú, ghi chú không bị xoá.', [l.name])),
                    actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Huỷ'))), FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Xoá')))],
                  ),
                );
                if (ok == true) setState(() => widget.store.deleteLabel(l));
              },
            ),
            title: TextFormField(
              initialValue: l.name,
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
              onFieldSubmitted: (v) {
                if (v.trim().isNotEmpty && v.trim() != l.name) setState(() => widget.store.putLabel(v, id: l.id));
              },
            ),
            trailing: const Icon(Icons.edit_outlined, size: 18),
          ),
      ]);
}

// ------------------------------------------------------------ chia sẻ
/// Chia sẻ ghi chú: tìm người trên máy chủ chat, chọn "Có thể sửa" / "Chỉ xem". Chỉ chủ ghi chú đổi được.
Future<void> shareNote(BuildContext context, TodoStore store, TNote n) =>
    showTodoSheet<void>(context, title: tr('Cộng tác viên'), width: 480, builder: (_) => _ShareForm(store: store, note: n));

class _ShareForm extends StatefulWidget {
  const _ShareForm({required this.store, required this.note});
  final TodoStore store;
  final TNote note;
  @override
  State<_ShareForm> createState() => _ShareFormState();
}

class _ShareFormState extends State<_ShareForm> {
  late List<TMember> _others = widget.note.others;
  final _q = TextEditingController();
  List<TMember> _found = [];
  Timer? _deb;
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    _deb?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _deb?.cancel();
    if (q.trim().isEmpty) return setState(() => _found = []);
    _deb = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _busy = true);
      try {
        final j = await widget.store.api.get('/api/people?q=${Uri.encodeQueryComponent(q.trim())}');
        if (!mounted) return;
        setState(() => _found = [for (final p in j['people'] as List? ?? const []) TMember('${p['id']}', '${p['name']}${(p['username'] ?? '') != '' ? ' (@${p['username']})' : ''}', 'editor')]);
      } catch (_) {
        if (mounted) setState(() => _found = []);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  Widget _avatar(String name) => CircleAvatar(
        radius: 16,
        backgroundColor: Colors.primaries[name.hashCode.abs() % Colors.primaries.length].shade400,
        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final owner = widget.note.owner;
    final canManage = widget.note.isOwner;
    final sub = Theme.of(context).colorScheme.onSurface.withValues(alpha: .6);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          if (owner != null) ListTile(leading: _avatar(owner.name), title: Text(owner.name), subtitle: Text(tr('Chủ sở hữu'))),
          for (final m in _others)
            ListTile(
              leading: _avatar(m.name),
              title: Text(m.name),
              trailing: canManage
                  ? DropdownButton<String>(
                      value: m.role,
                      underline: const SizedBox(),
                      items: [
                        DropdownMenuItem(value: 'editor', child: Text(tr('Có thể sửa'))),
                        DropdownMenuItem(value: 'viewer', child: Text(tr('Chỉ xem'))),
                        DropdownMenuItem(value: 'remove', child: Text(tr('Bỏ chia sẻ'), style: const TextStyle(color: Colors.red))),
                      ],
                      onChanged: (v) => setState(() => _others = v == 'remove'
                          ? _others.where((x) => x.id != m.id).toList()
                          : [for (final x in _others) x.id == m.id ? TMember(x.id, x.name, v!) : x]),
                    )
                  : Text(m.role == 'viewer' ? tr('Chỉ xem') : tr('Có thể sửa'), style: TextStyle(color: sub)),
            ),
          if (canManage) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TextField(
                controller: _q,
                autofocus: isDesktop,
                decoration: InputDecoration(
                  hintText: tr('Tên hoặc username để chia sẻ'),
                  prefixIcon: const Icon(Icons.person_add_alt_1_rounded),
                  suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                  isDense: true,
                ),
                onChanged: _search,
              ),
            ),
            for (final p in _found.where((p) => !_others.any((o) => o.id == p.id) && p.id != owner?.id))
              ListTile(
                dense: true,
                leading: _avatar(p.name),
                title: Text(p.name),
                trailing: const Icon(Icons.add_rounded),
                onTap: () => setState(() {
                  _others = [..._others, TMember(p.id, p.name.replaceFirst(RegExp(r' \(@[^)]*\)$'), ''), 'editor')];
                  _q.clear();
                  _found = [];
                }),
              ),
          ] else
            Padding(padding: const EdgeInsets.all(12), child: Text(tr('Chỉ chủ ghi chú mới thêm hoặc bỏ người được chia sẻ.'), style: TextStyle(color: sub))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: Row(children: [
          if (!canManage)
            TextButton.icon(
              icon: const Icon(Icons.logout_rounded),
              label: Text(tr('Rời ghi chú')),
              onPressed: () {
                widget.store.remove(widget.note);
                Navigator.of(context)
                  ..pop()
                  ..maybePop();
              },
            ),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'))),
          if (canManage)
            FilledButton(
              onPressed: () {
                widget.store.setMembers(widget.note, _others);
                Navigator.pop(context);
              },
              child: Text(tr('Lưu')),
            ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------ màu, hình nền
Future<void> pickLook(BuildContext context, TNote n, void Function(String color, String? bg) onChange) {
  var color = n.color;
  String? bg = n.bg;
  return showTodoSheet<void>(context, title: tr('Màu và hình nền'), width: 520, builder: (c) => StatefulBuilder(
        builder: (c, set) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: LookPicker(
            color: color,
            bg: bg,
            onColor: (v) => set(() {
              color = v;
              onChange(color, bg);
            }),
            onBg: (v) => set(() {
              bg = v;
              onChange(color, bg);
            }),
          ),
        ),
      ));
}
