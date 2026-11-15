// Lịch: ô chọn "Lặp lại" (các lựa chọn có sẵn theo ngày bắt đầu + "Tuỳ chỉnh…") và hộp tuỳ chỉnh: mỗi N ngày / tuần /
// tháng / năm, chọn thứ trong tuần, kết thúc không bao giờ / vào ngày / sau N lần.
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'look.dart';
import 'rrule_text.dart';

/// Ô chọn lặp lại. [value] = chuỗi RRULE hiện tại (null = không lặp).
class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({super.key, required this.value, required this.start, required this.onChanged});
  final String? value;
  final DateTime start;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = rrulePresets(start);
    final known = presets.any((p) => p.rule == value);
    return PopupMenuButton<String>(
      key: const ValueKey('recurrence'),
      tooltip: tr('Lặp lại'),
      onSelected: (v) async {
        if (v == '__custom') {
          final r = await editCustomRule(context, value, start);
          if (r != null) onChanged(r.isEmpty ? null : r);
        } else {
          onChanged(v.isEmpty ? null : v);
        }
      },
      itemBuilder: (_) => [
        for (final p in presets) PopupMenuItem(value: p.rule ?? '', height: 40, child: Text(tr(p.label))),
        if (!known && value != null) PopupMenuItem(value: value!, height: 40, child: Text(rruleText(value, start))),
        const PopupMenuDivider(),
        PopupMenuItem(value: '__custom', height: 40, child: Text(tr('Tuỳ chỉnh…'))),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Pal.of(context).surface, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sync_rounded, size: 17, color: Pal.of(context).sub),
          const SizedBox(width: 8),
          Flexible(child: Text(rruleText(value, start), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
          Icon(Icons.arrow_drop_down_rounded, size: 20, color: Pal.of(context).sub),
        ]),
      ),
    );
  }
}

/// Hộp "Lặp lại tuỳ chỉnh". Trả chuỗi RRULE mới ('' = không lặp), null = huỷ.
Future<String?> editCustomRule(BuildContext context, String? cur, DateTime start) =>
    showCalSheet<String>(context, width: 400, builder: (_) => _CustomRule(cur: cur, start: start));

class _CustomRule extends StatefulWidget {
  const _CustomRule({required this.cur, required this.start});
  final String? cur;
  final DateTime start;
  @override
  State<_CustomRule> createState() => _CustomRuleState();
}

class _CustomRuleState extends State<_CustomRule> {
  late final RRule? _r = RRule.parse(widget.cur);
  late String _freq = _r?.freq ?? 'WEEKLY';
  late final _interval = TextEditingController(text: '${_r?.interval ?? 1}');
  late Set<String> _days = {for (final d in _r?.byDay ?? <RDay>[]) if (d.ord == 0) d.code};
  late String _end = _r?.count != null ? 'count' : _r?.untilDate != null ? 'until' : 'never';
  late DateTime _until = _r?.untilDate ?? DateTime.utc(widget.start.year, widget.start.month + 3, widget.start.day);
  late final _count = TextEditingController(text: '${_r?.count ?? 10}');

  @override
  void initState() {
    super.initState();
    if (_days.isEmpty) _days = {weekdayCode(widget.start.weekday)};
  }

  @override
  void dispose() {
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  String _build() {
    final r = RRule(_freq, interval: int.tryParse(_interval.text)?.clamp(1, 999) ?? 1);
    // Giữ kiểu "hằng tháng vào thứ X thứ k" / ngày N nếu đang dùng.
    if (_freq == 'WEEKLY') r.byDay = [for (final c in kWeekdayCodes) if (_days.contains(c)) RDay(c)];
    if (_freq == 'MONTHLY' && _r?.freq == 'MONTHLY') {
      r.byDay = [..._r!.byDay];
      r.byMonthDay = [..._r.byMonthDay];
    }
    if (_freq == 'YEARLY' && _r?.lunar == true) r.lunar = true;
    if (_end == 'count') r.count = int.tryParse(_count.text)?.clamp(1, 999) ?? 10;
    if (_end == 'until') r.until = RRule.untilOf(_until);
    return r.build();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    const units = {'DAILY': 'ngày', 'WEEKLY': 'tuần', 'MONTHLY': 'tháng', 'YEARLY': 'năm'};
    Widget num(TextEditingController c, {Key? key}) => SizedBox(
          width: 64,
          child: TextField(
            key: key,
            controller: c,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(isDense: true, filled: true, fillColor: pal.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(tr('Lặp lại tuỳ chỉnh'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Row(children: [
          Text(tr('Lặp lại mỗi')),
          const SizedBox(width: 10),
          num(_interval, key: const ValueKey('rr-interval')),
          const SizedBox(width: 8),
          ChipMenu<String>(
            key: const ValueKey('rr-unit'),
            label: tr(units[_freq]!),
            items: [for (final e in units.entries) (e.key, tr(e.value))],
            onSelected: (v) => setState(() => _freq = v),
          ),
        ]),
        if (_freq == 'WEEKLY') ...[
          const SizedBox(height: 16),
          Text(tr('Lặp lại vào'), style: TextStyle(color: pal.sub, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (var i = 0; i < 7; i++)
              InkWell(
                key: ValueKey('rr-day-${kWeekdayCodes[i]}'),
                customBorder: const CircleBorder(),
                onTap: () => setState(() {
                  final c = kWeekdayCodes[i];
                  if (_days.contains(c) && _days.length > 1) {
                    _days.remove(c);
                  } else {
                    _days.add(c);
                  }
                }),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _days.contains(kWeekdayCodes[i]) ? calAccent(context) : pal.surface),
                  child: Text(kWeekdayShort[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _days.contains(kWeekdayCodes[i]) ? Colors.white : pal.text)),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 18),
        Text(tr('Kết thúc'), style: TextStyle(color: pal.sub, fontSize: 13)),
        RadioGroup<String>(
          groupValue: _end,
          onChanged: (v) => setState(() => _end = v ?? _end),
          child: Column(children: [
            Row(children: [const Radio<String>(value: 'never'), Text(tr('Không bao giờ'))]),
            Row(children: [
              const Radio<String>(value: 'until'),
              SizedBox(width: 80, child: Text(tr('Vào ngày'))),
              pill(context, dmy(_until), onTap: () async {
                final d = await showDatePicker(context: context, initialDate: DateTime(_until.year, _until.month, _until.day), firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d != null) {
                  setState(() {
                    _until = DateTime.utc(d.year, d.month, d.day);
                    _end = 'until';
                  });
                }
              }),
            ]),
            Row(children: [
              const Radio<String>(value: 'count'),
              SizedBox(width: 80, child: Text(tr('Sau'))),
              num(_count, key: const ValueKey('rr-count')),
              const SizedBox(width: 8),
              Text(tr('lần')),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        Text(rruleText(_build(), widget.start), style: TextStyle(fontSize: 12.5, color: pal.sub)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'))),
          const SizedBox(width: 8),
          FilledButton(key: const ValueKey('rr-done'), style: calPrimary(context), onPressed: () => Navigator.pop(context, _build()), child: Text(tr('Xong'))),
        ]),
      ]),
    );
  }
}
