// Lịch: trang Cài đặt (múi giờ, tuần bắt đầu, âm lịch, thời lượng / lời nhắc mặc định, giờ làm việc, cuối tuần, sự kiện
// đã từ chối) và hộp "Tìm giờ rảnh với…" (chọn người → khung giờ rảnh chung → tạo sự kiện mời họ).
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../app_route.dart';
import '../theme.dart';
import 'look.dart';
import 'model.dart';
import 'people.dart';
import 'store.dart';
import 'tz.dart';

Future<void> openCalSettings(BuildContext context, CalStore store) => Navigator.of(context).push(AppPageRoute(builder: (_) => CalSettingsPage(store: store)));

class CalSettingsPage extends StatelessWidget {
  const CalSettingsPage({super.key, required this.store});
  final CalStore store;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.settings;
        Widget row(String label, Widget trailing, {String? sub}) => ListTile(
              title: Text(tr(label)),
              subtitle: sub == null ? null : Text(sub, style: TextStyle(color: pal.sub, fontSize: 12.5)),
              trailing: trailing,
            );
        final halfHours = [for (var m = 0; m < 24 * 60; m += 30) '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}'];
        return Scaffold(
          backgroundColor: pal.bg,
          appBar: AppBar(backgroundColor: pal.bg, surfaceTintColor: Colors.transparent, title: Text(tr('Cài đặt Lịch'))),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(children: [
                row('Múi giờ', ChipMenu<String>(
                  key: const ValueKey('set-tz'),
                  label: tzLabel(s.tz),
                  items: [for (final z in kTimezones) (z.id, tzLabel(z.id))],
                  onSelected: (v) => store.putSettings({'tz': v}),
                )),
                row('Tuần bắt đầu vào', ChipMenu<int>(
                  label: s.weekStart == 1 ? tr('Thứ Hai') : tr('Chủ nhật'),
                  items: [(1, tr('Thứ Hai')), (0, tr('Chủ nhật'))],
                  onSelected: (v) => store.putSettings({'week_start': v}),
                )),
                row('Chế độ xem mặc định', ChipMenu<String>(
                  label: tr(const {'day': 'Ngày', 'week': 'Tuần', 'month': 'Tháng', 'agenda': 'Lịch biểu'}[s.defaultView] ?? 'Tuần'),
                  items: [('day', tr('Ngày')), ('week', tr('Tuần')), ('month', tr('Tháng')), ('agenda', tr('Lịch biểu'))],
                  onSelected: (v) => store.putSettings({'default_view': v}),
                )),
                SwitchListTile(
                  key: const ValueKey('set-lunar'),
                  title: Text(tr('Hiện ngày âm lịch')),
                  subtitle: Text(tr('Ngày âm dưới mỗi ngày trong tuần, mùng 1 và rằm trong tháng'), style: TextStyle(color: pal.sub, fontSize: 12.5)),
                  value: s.lunar,
                  onChanged: (v) => store.putSettings({'lunar': v}),
                ),
                row('Thời lượng mặc định', ChipMenu<int>(
                  label: tr('{0} phút', [s.defaultDuration]),
                  items: [for (final m in const [15, 30, 45, 60, 90, 120]) (m, tr('{0} phút', [m]))],
                  onSelected: (v) => store.putSettings({'default_duration': v}),
                )),
                ListTile(
                  title: Text(tr('Lời nhắc mặc định')),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final r in s.defaultReminders)
                        InputChip(
                          label: Text(reminderText(r.minutes), style: const TextStyle(fontSize: 12.5)),
                          onDeleted: () => store.putSettings({'default_reminders': [for (final x in s.defaultReminders) if (x.minutes != r.minutes) x.toJson()]}),
                        ),
                      ChipMenu<int>(
                        label: tr('Thêm'),
                        items: [for (final m in const [0, 10, 15, 30, 60, 120, 1440]) (m, reminderText(m))],
                        onSelected: (m) => store.putSettings({
                          'default_reminders': [for (final x in {...s.defaultReminders.map((r) => r.minutes), m}) {'minutes': x}],
                        }),
                      ),
                    ]),
                  ),
                ),
                row(
                  'Giờ làm việc',
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    ChipMenu<String>(label: s.workStart, items: [for (final t in halfHours) (t, t)], onSelected: (v) => store.putSettings({'work_start': v})),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
                    ChipMenu<String>(label: s.workEnd, items: [for (final t in halfHours) (t, t)], onSelected: (v) => store.putSettings({'work_end': v})),
                  ]),
                ),
                SwitchListTile(title: Text(tr('Hiện cuối tuần')), value: s.showWeekends, onChanged: (v) => store.putSettings({'show_weekends': v})),
                SwitchListTile(title: Text(tr('Hiện sự kiện đã từ chối')), value: s.showDeclined, onChanged: (v) => store.putSettings({'show_declined': v})),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Kết quả "Tìm giờ rảnh với…": những người đã chọn + khung giờ bấm vào.
typedef FreePick = ({List<Picked> people, CSlot slot, int duration});

Future<FreePick?> findFreeTime(BuildContext context, CalStore store) => showCalSheet<FreePick>(context, width: 520, builder: (_) => _FindFree(store: store));

class _FindFree extends StatefulWidget {
  const _FindFree({required this.store});
  final CalStore store;
  @override
  State<_FindFree> createState() => _FindFreeState();
}

class _FindFreeState extends State<_FindFree> {
  final List<Picked> _people = [];
  int _duration = 60, _days = 7;
  List<CSlot>? _slots;
  bool _busy = false;
  String? _error;

  CalStore get store => widget.store;

  Future<void> _find() async {
    if (_people.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final from = store.today;
      final r = await store.api.findTime([store.meId, for (final p in _people) p.id],
          from: fmtDate(from), to: fmtDate(addDays(from, _days)), duration: _duration, workStart: store.settings.workStart, workEnd: store.settings.workEnd, limit: 12);
      if (mounted) setState(() => _slots = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(tr('Tìm giờ rảnh với…'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        PeopleSearch(
          store: store,
          channels: false,
          hint: tr('Thêm người'),
          exclude: {for (final p in _people) p.principal},
          onPick: (p) => setState(() {
            _people.add(p);
            _slots = null;
          }),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final p in _people)
            InputChip(
              avatar: personAvatar(context, p.name, r: 11),
              label: Text(p.name),
              onDeleted: () => setState(() {
                _people.remove(p);
                _slots = null;
              }),
            ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ChipMenu<int>(
            label: tr('Dài {0} phút', [_duration]),
            items: [for (final m in const [15, 30, 45, 60, 90, 120]) (m, tr('{0} phút', [m]))],
            onSelected: (v) => setState(() => _duration = v),
          ),
          ChipMenu<int>(
            label: tr('Trong {0} ngày tới', [_days]),
            items: [for (final d in const [3, 7, 14, 30]) (d, tr('{0} ngày tới', [d]))],
            onSelected: (v) => setState(() => _days = v),
          ),
          FilledButton(key: const ValueKey('ff-find'), style: calPrimary(context), onPressed: _people.isEmpty || _busy ? null : _find, child: Text(tr('Tìm'))),
        ]),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: kNowRed))),
        if (_slots != null && !_busy) ...[
          const SizedBox(height: 14),
          if (_slots!.isEmpty) Text(tr('Không có khung giờ nào cả nhóm cùng rảnh'), style: TextStyle(color: pal.sub)),
          for (final s in _slots!)
            ListTile(
              key: ValueKey('slot-${s.startMs}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_available_outlined, color: calAccent(context)),
              title: Text(dayLong(wallOf(s.startMs, store.tz), now: store.today)),
              subtitle: Text('${hm(wallOf(s.startMs, store.tz))} – ${hm(wallOf(s.endMs, store.tz))}'),
              trailing: Text(tr('Tạo sự kiện'), style: TextStyle(color: calAccent(context), fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, (people: [..._people], slot: s, duration: _duration)),
            ),
        ],
      ]),
    );
  }
}
