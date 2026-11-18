import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/meet_rooms.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../calendar/tz.dart' show kDefaultTz, msOfWall, wallOf;
import '../common.dart';
import '../theme.dart';

// Lên lịch / sửa cuộc họp của app Họp: ngày, giờ bắt đầu, giờ kết thúc (24 giờ, giờ Việt Nam), quyền vào, người mời.
// Giờ luôn theo Asia/Ho_Chi_Minh (không theo múi giờ của máy), như máy chủ hiển thị trong tin báo và thẻ cuộc họp.

/// Múi giờ của cuộc họp.
const kMeetTz = kDefaultTz;

/// Giờ tường Việt Nam của một thời điểm (DateTime UTC "giả" chứa ngày giờ tường).
DateTime meetWall(DateTime t) => wallOf(t.millisecondsSinceEpoch, kMeetTz);

/// Thời điểm của giờ tường Việt Nam [w].
DateTime meetInstant(DateTime w) => DateTime.fromMillisecondsSinceEpoch(msOfWall(DateTime.utc(w.year, w.month, w.day, w.hour, w.minute), kMeetTz));

String _p2(int n) => n.toString().padLeft(2, '0');
String meetHm(TimeOfDay t) => '${_p2(t.hour)}:${_p2(t.minute)}';
String meetWeekday(DateTime d) => [tr('Thứ 2'), tr('Thứ 3'), tr('Thứ 4'), tr('Thứ 5'), tr('Thứ 6'), tr('Thứ 7'), tr('Chủ nhật')][d.weekday - 1];

/// "1 giờ 30 phút", "45 phút".
String meetDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return tr('{0} phút', [m]);
  return m == 0 ? tr('{0} giờ', [h]) : tr('{0} giờ {1} phút', [h, m]);
}

class MeetSchedule {
  final String title;
  final DateTime start, end;
  final List<String> invitees;
  final String access;
  const MeetSchedule(this.title, this.start, this.end, this.invitees, this.access);
}

/// Mở màn lên lịch (hoặc sửa [edit]). Trả về null nếu người dùng đóng.
Future<MeetSchedule?> showScheduleMeeting(BuildContext context, {MeetRoomInfo? edit, DateTime Function()? clock}) =>
    Navigator.of(context).push<MeetSchedule>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => MeetScheduleForm(edit: edit, clock: clock)),
    );

class MeetScheduleForm extends StatefulWidget {
  final MeetRoomInfo? edit;
  /// Đồng hồ (kiểm thử thay được).
  final DateTime Function()? clock;
  const MeetScheduleForm({super.key, this.edit, this.clock});
  @override
  State<MeetScheduleForm> createState() => _MeetScheduleFormState();
}

class _MeetScheduleFormState extends State<MeetScheduleForm> {
  late final _title = TextEditingController(text: widget.edit?.title ?? '');
  final _q = TextEditingController();
  late DateTime _day; // ngày (giờ tường VN, chỉ dùng năm-tháng-ngày)
  late TimeOfDay _from, _to;
  late bool _inviteOnly = (widget.edit?.access ?? 'invited') == 'invited';
  late final _invited = <String>{...?widget.edit?.invitees};

  DateTime _now() => (widget.clock ?? DateTime.now)();
  bool get _editing => widget.edit != null;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e?.start != null) {
      final s = meetWall(e!.start!);
      final en = meetWall(e.end ?? e.start!.add(const Duration(hours: 1)));
      _day = DateTime.utc(s.year, s.month, s.day);
      _from = TimeOfDay(hour: s.hour, minute: s.minute);
      _to = TimeOfDay(hour: en.hour, minute: en.minute);
    } else {
      // Mặc định: mốc 30 phút kế tiếp sau một giờ nữa, họp 1 giờ.
      final n = meetWall(_now().add(const Duration(hours: 1)));
      var s = DateTime.utc(n.year, n.month, n.day, n.hour, n.minute < 30 ? 30 : 0);
      if (n.minute >= 30) s = s.add(const Duration(hours: 1));
      _day = DateTime.utc(s.year, s.month, s.day);
      _from = TimeOfDay(hour: s.hour, minute: s.minute);
      final en = s.add(const Duration(hours: 1));
      _to = TimeOfDay(hour: en.hour, minute: en.minute);
    }
    _title.addListener(() => setState(() {}));
    _q.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _q.dispose();
    super.dispose();
  }

  int _mins(TimeOfDay t) => t.hour * 60 + t.minute;
  DateTime get _startWall => DateTime.utc(_day.year, _day.month, _day.day, _from.hour, _from.minute);
  // Giờ kết thúc nhỏ hơn giờ bắt đầu: sang ngày hôm sau (họp qua nửa đêm).
  DateTime get _endWall {
    final e = DateTime.utc(_day.year, _day.month, _day.day, _to.hour, _to.minute);
    return _mins(_to) <= _mins(_from) ? e.add(const Duration(days: 1)) : e;
  }

  int get _length => _endWall.difference(_startWall).inMinutes;

  String? get _problem {
    if (_title.text.trim().isEmpty) return tr('Nhập tên cuộc họp');
    if (meetInstant(_startWall).isBefore(_now()) && !_editing) return tr('Giờ bắt đầu đã qua');
    if (_length <= 0) return tr('Giờ kết thúc phải sau giờ bắt đầu');
    if (_length > 24 * 60) return tr('Cuộc họp dài tối đa 24 giờ');
    return null;
  }

  Future<void> _pickDay() async {
    final today = meetWall(_now());
    final first = DateTime(today.year, today.month, today.day);
    final cur = DateTime(_day.year, _day.month, _day.day);
    final d = await showDatePicker(
      context: context,
      locale: const Locale('vi'),
      initialDate: cur.isBefore(first) ? first : cur,
      firstDate: _editing && cur.isBefore(first) ? cur : first,
      lastDate: first.add(const Duration(days: 730)),
      helpText: tr('Chọn ngày họp'),
    );
    if (d != null) setState(() => _day = DateTime.utc(d.year, d.month, d.day));
  }

  /// Chọn giờ: danh sách mốc 15 phút (giờ kết thúc kèm thời lượng), cuối danh sách "Giờ khác…" mở đồng hồ 24 giờ.
  Future<TimeOfDay?> _pickTime(TimeOfDay current, {TimeOfDay? after}) async {
    final slots = <TimeOfDay>[
      for (var m = 0; m < 24 * 60; m += 15) TimeOfDay(hour: m ~/ 60, minute: m % 60),
    ];
    final start = after == null ? 0 : (_mins(after) ~/ 15 + 1);
    final list = after == null ? slots : [...slots.skip(start), ...slots.take(start)];
    final idx = list.indexWhere((t) => _mins(t) >= _mins(current)).clamp(0, list.length - 1);
    final pick = await showDialog<Object>(
      context: context,
      builder: (d) {
        final pal = Pal.of(d);
        return SimpleDialog(
          title: Text(after == null ? tr('Giờ bắt đầu') : tr('Giờ kết thúc')),
          contentPadding: const EdgeInsets.only(bottom: 8),
          children: [
            SizedBox(
              width: 320,
              height: 360,
              child: ListView.builder(
                controller: ScrollController(initialScrollOffset: (idx * 44.0 - 132).clamp(0, double.infinity)),
                itemExtent: 44,
                itemCount: list.length + 1,
                itemBuilder: (_, i) {
                  if (i == list.length) {
                    return ListTile(dense: true, leading: const Icon(Icons.schedule_rounded), title: Text(tr('Giờ khác…')), onTap: () => Navigator.pop(d, 'other'));
                  }
                  final t = list[i];
                  final sel = _mins(t) == _mins(current);
                  var dur = '';
                  if (after != null) {
                    var m = _mins(t) - _mins(after);
                    if (m <= 0) m += 24 * 60;
                    dur = ' (${meetDuration(m)})';
                  }
                  return ListTile(
                    dense: true,
                    selected: sel,
                    title: Text('${meetHm(t)}$dur', style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w400, color: sel ? null : pal.text)),
                    onTap: () => Navigator.pop(d, t),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
    if (pick is TimeOfDay) return pick;
    if (pick != 'other' || !mounted) return null;
    return showTimePicker(
      context: context,
      initialTime: current,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
  }

  Future<void> _pickFrom() async {
    final t = await _pickTime(_from);
    if (t == null) return;
    // Giữ nguyên thời lượng khi đổi giờ bắt đầu.
    final len = _length;
    final e = DateTime.utc(2000, 1, 1, t.hour, t.minute).add(Duration(minutes: len));
    setState(() {
      _from = t;
      _to = TimeOfDay(hour: e.hour, minute: e.minute);
    });
  }

  Future<void> _pickTo() async {
    final t = await _pickTime(_to, after: _from);
    if (t != null) setState(() => _to = t);
  }

  void _save() {
    Navigator.pop(
      context,
      MeetSchedule(_title.text.trim(), meetInstant(_startWall), meetInstant(_endWall), _invited.toList(), _inviteOnly ? 'invited' : 'company'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final q = _q.text.trim().toLowerCase();
    final people = [
      for (final u in app.people)
        if (q.isEmpty || u.displayName.toLowerCase().contains(q) || u.username.contains(q)) u,
    ];
    final problem = _problem;
    final nextDay = _endWall.day != _startWall.day;
    Widget field(String label, String value, IconData icon, VoidCallback onTap, {Key? key}) => Expanded(
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: label,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                suffixIcon: Icon(icon, size: 20),
              ),
              child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? tr('Sửa cuộc họp') : tr('Lên lịch cuộc họp')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(key: const ValueKey('meet-schedule-save'), onPressed: problem == null ? _save : null, child: Text(tr('Lưu'))),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _title,
                autofocus: !_editing,
                decoration: InputDecoration(labelText: tr('Tên cuộc họp'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(children: [
                field(tr('Ngày'), '${meetWeekday(_day)}, ${_p2(_day.day)}/${_p2(_day.month)}/${_day.year}', Icons.calendar_month_rounded, _pickDay,
                    key: const ValueKey('meet-day')),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                field(tr('Bắt đầu'), meetHm(_from), Icons.schedule_rounded, _pickFrom, key: const ValueKey('meet-from')),
                const SizedBox(width: 12),
                field(nextDay ? tr('Kết thúc (hôm sau)') : tr('Kết thúc'), meetHm(_to), Icons.schedule_rounded, _pickTo, key: const ValueKey('meet-to')),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.public_rounded, size: 16, color: pal.sub),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [tr('Giờ Việt Nam (GMT+7)'), if (_length > 0) meetDuration(_length)].join(' · '),
                    style: TextStyle(color: pal.sub, fontSize: 13),
                  ),
                ),
              ]),
              if (problem != null && _title.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(problem, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              if (_editing && widget.edit!.fromCalendar) ...[
                const SizedBox(height: 8),
                Text(tr('Cuộc họp này tạo từ Lịch: lưu sẽ đổi luôn sự kiện trong Lịch.'), style: TextStyle(color: pal.sub, fontSize: 13)),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _inviteOnly,
                onChanged: (v) => setState(() => _inviteOnly = v),
                title: Text(tr('Chỉ người được mời')),
                subtitle: Text(
                  _inviteOnly ? tr('Người khác có mã phải xin vào, người tổ chức cho vào.') : tr('Mọi người trong công ty có mã đều vào được.'),
                ),
              ),
              const Divider(height: 24),
              Text(
                tr('Mời ({0})', [_invited.length]),
                style: TextStyle(fontWeight: FontWeight.w700, color: pal.sub),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _q,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr('Tìm người'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              for (final u in people.take(80))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _invited.contains(u.id),
                  onChanged: (v) => setState(() => v == true ? _invited.add(u.id) : _invited.remove(u.id)),
                  secondary: Avatar(userId: u.id, name: u.displayName, size: 36, status: false),
                  title: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
