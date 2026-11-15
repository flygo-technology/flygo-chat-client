// Lịch: hộp "Cài đặt và chia sẻ" của một lịch (cũng dùng để tạo lịch mới) — tên, mô tả, màu, lời nhắc mặc định; chia sẻ
// với người / kênh theo 4 mức quyền; "Cho mọi người xem lịch này" (principal "*"); liên kết ICS để sau.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'look.dart';
import 'model.dart';
import 'people.dart';
import 'store.dart';

/// [cal] = null: tạo lịch mới.
Future<void> openCalendarSettings(BuildContext context, CalStore store, CCalendar? cal) =>
    showCalSheet<void>(context, width: 560, builder: (_) => CalendarSettings(store: store, cal: cal));

class CalendarSettings extends StatefulWidget {
  const CalendarSettings({super.key, required this.store, this.cal});
  final CalStore store;
  final CCalendar? cal;
  @override
  State<CalendarSettings> createState() => _CalendarSettingsState();
}

class _CalendarSettingsState extends State<CalendarSettings> {
  late final CCalendar? cal = widget.cal;
  late final _name = TextEditingController(text: cal?.name ?? '');
  late final _desc = TextEditingController(text: cal?.description ?? '');
  late String _color = cal?.color ?? 'teal';
  late List<CReminder> _reminders = [...cal?.defaultReminders ?? const [CReminder(30)]];
  List<CAcl> _acl = [];
  String _aclOrig = '[]';
  bool _loading = false, _saving = false;
  String? _error;

  CalStore get store => widget.store;
  bool get _isNew => cal == null;
  bool get _manage => _isNew || cal!.canManage;

  @override
  void initState() {
    super.initState();
    if (!_isNew && !cal!.isHoliday && roleRank(cal!.role) >= roleRank('reader')) _loadAcl();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadAcl() async {
    setState(() => _loading = true);
    try {
      final a = await store.api.acl(cal!.id);
      if (!mounted) return;
      setState(() {
        _acl = a;
        _aclOrig = jsonEncode([for (final x in a) x.toJson()]);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  CAcl? get _everyone => _acl.where((a) => a.isEveryone).firstOrNull;

  Future<void> _add() async {
    final p = await pickPrincipal(context, store, exclude: {for (final a in _acl) a.principal});
    if (p == null || !mounted) return;
    setState(() => _acl.add(CAcl(p.principal, p.name, 'reader')));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = tr('Lịch cần có tên'));
    setState(() {
      _saving = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    try {
      final id = cal?.id ?? calId(16);
      final body = {'name': name, 'description': _desc.text.trim(), 'color': _color, 'default_reminders': [for (final r in _reminders) r.toJson()]};
      final changed = _isNew ||
          name != cal!.name ||
          body['description'] != cal!.description ||
          _color != cal!.color ||
          jsonEncode(body['default_reminders']) != jsonEncode([for (final r in cal!.defaultReminders) r.toJson()]);
      if (changed) await store.saveCalendar(id, body);
      final acl = jsonEncode([for (final x in _acl) x.toJson()]);
      if (_manage && acl != _aclOrig) await store.api.putAcl(id, _acl);
      nav.pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(tr(t), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      );

  Widget _roleMenu(CAcl a, {bool everyone = false}) {
    if (a.role == 'owner') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Pal.of(context).surface, borderRadius: BorderRadius.circular(8)),
        child: Text(tr('Chủ sở hữu'), style: const TextStyle(fontSize: 13.5)),
      );
    }
    final roles = everyone ? const ['freebusy', 'reader'] : const ['freebusy', 'reader', 'writer', 'manager'];
    return ChipMenu<String>(
      key: ValueKey('role-${a.principal}'),
      enabled: _manage,
      label: everyone && a.role == 'freebusy' ? tr('Chỉ rảnh/bận') : tr(kRoleNames[a.role] ?? a.role),
      items: [for (final r in roles) (r, tr(kRoleNames[r]!)), if (!everyone) ('__remove', tr('Bỏ chia sẻ'))],
      onSelected: (v) => setState(() {
        if (v == '__remove') {
          _acl.remove(a);
        } else {
          a.role = v;
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = calDark(context);
    final holiday = cal?.isHoliday ?? false;
    final subtitle = _isNew
        ? tr('Lịch mới')
        : holiday
            ? tr('Lịch có sẵn, chỉ xem')
            : cal!.kind == 'shared' || _acl.length > 1
                ? tr('Lịch dùng chung · tạo bởi {0}', [cal!.ownerName.isEmpty ? store.meName : cal!.ownerName])
                : tr('Lịch cá nhân');
    final people = _acl.where((a) => !a.isEveryone).toList()..sort((a, b) => roleRank(b.role).compareTo(roleRank(a.role)));
    final ev = _everyone;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 5), child: ColorCheck(color: eventColor(_color, dark), on: true)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_isNew ? tr('Tạo lịch mới') : cal!.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(fontSize: 12.5, color: pal.sub)),
                ]),
              ),
              IconButton(tooltip: tr('Đóng'), icon: Icon(Icons.close_rounded, color: pal.sub), onPressed: () => Navigator.pop(context)),
            ]),
            if (holiday)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(cal!.description.isEmpty ? tr('Ngày lễ dương lịch và âm lịch của Việt Nam (Tết, Giỗ Tổ, 30/4, 2/9…).') : cal!.description,
                    style: TextStyle(color: pal.sub, height: 1.4)),
              )
            else ...[
              if (_manage) ...[
                _section('Cài đặt lịch'),
                TextField(key: const ValueKey('cal-name'), controller: _name, enabled: _manage, decoration: InputDecoration(labelText: tr('Tên'), isDense: true, border: const OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: _desc, enabled: _manage, maxLines: 2, decoration: InputDecoration(labelText: tr('Mô tả'), isDense: true, border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in kEventColors.keys)
                    Tooltip(
                      message: tr(kColorNames[c]!),
                      child: InkWell(
                        key: ValueKey('cal-color-$c'),
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _color = c),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: eventColor(c, dark), shape: BoxShape.circle),
                          child: _color == c ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(tr('Lời nhắc mặc định:'), style: TextStyle(fontSize: 13, color: pal.sub)),
                  for (final r in _reminders) InputChip(label: Text(reminderText(r.minutes), style: const TextStyle(fontSize: 12.5)), onDeleted: () => setState(() => _reminders.remove(r))),
                  ChipMenu<int>(
                    label: tr('Thêm'),
                    items: [for (final m in const [0, 10, 15, 30, 60, 120, 1440, 10080]) (m, reminderText(m))],
                    onSelected: (m) => setState(() => _reminders = {..._reminders.map((x) => x.minutes), m}.map(CReminder.new).toList()),
                  ),
                ]),
              ],
              if (!_isNew) ...[
                _section('Chia sẻ với người cụ thể'),
                if (_loading) const Padding(padding: EdgeInsets.all(12), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                for (final a in people)
                  Padding(
                    key: ValueKey('acl-${a.principal}'),
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      personAvatar(context, a.name, r: 16, channel: a.isChannel),
                      const SizedBox(width: 12),
                      Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5))),
                      _roleMenu(a),
                    ]),
                  ),
                if (_manage)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton.icon(
                        key: const ValueKey('acl-add'),
                        style: OutlinedButton.styleFrom(shape: const StadiumBorder(), foregroundColor: pal.text, side: BorderSide(color: pal.divider)),
                        onPressed: _add,
                        icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                        label: Text(tr('Thêm người hoặc kênh'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                _section('Mọi người trên máy chủ'),
                Row(children: [
                  Checkbox(
                    key: const ValueKey('acl-everyone'),
                    value: ev != null,
                    onChanged: !_manage
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _acl.add(CAcl('*', tr('Mọi người'), 'freebusy'));
                              } else {
                                _acl.removeWhere((a) => a.isEveryone);
                              }
                            }),
                  ),
                  Expanded(child: Text(tr('Cho mọi người xem lịch này'), style: const TextStyle(fontSize: 14.5))),
                  _roleMenu(ev ?? CAcl('*', '', 'freebusy'), everyone: true),
                ]),
                _section('Liên kết lịch (để sau)'),
                Opacity(
                  opacity: .6,
                  child: Row(children: [
                    Icon(Icons.link_rounded, size: 18, color: pal.sub),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('Địa chỉ ICS bí mật · xuất .ics · nhập .ics'), style: TextStyle(fontSize: 13, color: pal.sub))),
                  ]),
                ),
              ],
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: kNowRed))),
          ]),
        ),
      ),
      if (!holiday)
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'), style: TextStyle(fontWeight: FontWeight.w600, color: calAccent(context)))),
            const SizedBox(width: 10),
            FilledButton(key: const ValueKey('cal-save'), style: calPrimary(context), onPressed: _saving ? null : _save, child: Text(_isNew ? tr('Tạo lịch') : tr('Lưu'))),
          ]),
        ),
    ]);
  }
}
