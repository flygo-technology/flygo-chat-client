import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowOrange, kFlowRed;
import 'flow_cond.dart';
import 'flow_editor.dart';

/// Nốt Bắt đầu: các cách tạo luồng của một quy trình (meta['starts']). Mỗi nốt `{id, type, ...}`; dữ liệu nguồn
/// (tin nhắn, webhook, dòng ERP, email...) điền vào biểu mẫu theo `mapping` (khoá trường ← đường dẫn).

const kGroupStart = Color(0xFF16A34A);

/// Các loại nốt Bắt đầu: (loại, biểu tượng, mô tả).
const startTypes = <(String, IconData, String)>[
  ('manual', Icons.touch_app_outlined, 'Người bấm "Tạo tiến trình mới" và điền biểu mẫu'),
  ('once', Icons.event_outlined, 'Chạy một lần vào ngày giờ chọn sẵn'),
  ('schedule', Icons.event_repeat_outlined, 'Lặp lại mỗi giờ / ngày / tuần / tháng / năm'),
  ('interval', Icons.timer_outlined, 'Cứ mỗi 30 giây, 5 phút, 1 giờ... chạy một lần'),
  ('webhook', Icons.webhook_rounded, 'Hệ thống ngoài gửi dữ liệu vào (URL riêng + secret)'),
  ('chat_message', Icons.forum_outlined, 'Có tin nhắn mới trong nhóm (lọc theo từ khoá)'),
  ('message_action', Icons.reply_rounded, 'Mục "Tạo tiến trình" trong menu tin nhắn, điền sẵn từ tin'),
  ('public_form', Icons.qr_code_2_rounded, 'Link / mã QR cho người ngoài công ty điền'),
  ('date_due', Icons.event_available_outlined, 'Trước hạn X ngày theo dữ liệu ứng dụng (hợp đồng, bảo hành...)'),
  ('watch', Icons.radar_outlined, 'Dữ liệu ứng dụng thoả điều kiện (tồn kho thấp, quá hạn...)'),
  ('flow', Icons.alt_route_rounded, 'Được bước "Bắt đầu quy trình khác" mở'),
  ('email', Icons.mail_outline_rounded, 'Có email mới gửi tới hộp thư'),
];

String startTypeLabel(String type) => switch (type) {
      'manual' => tr('Bấm thủ công'),
      'once' => tr('Ngày cụ thể'),
      'schedule' => tr('Ngày lặp lại'),
      'interval' => tr('Interval'),
      'webhook' => tr('Webhook'),
      'chat_message' => tr('Tin nhắn trong nhóm'),
      'message_action' => tr('Từ một tin nhắn'),
      'public_form' => tr('Form công khai'),
      'date_due' => tr('Mốc ngày theo dữ liệu'),
      'watch' => tr('Theo dõi điều kiện'),
      'flow' => tr('Được quy trình khác gọi'),
      'email' => tr('Email đến'),
      _ => tr('Bắt đầu'),
    };

IconData startIcon(String type) => startTypes.where((t) => t.$1 == type).firstOrNull?.$2 ?? Icons.play_arrow_rounded;

/// Loại chỉ được một nốt trong quy trình.
const singleStartTypes = {'manual', 'webhook', 'public_form', 'flow', 'email'};

/// Luồng tạo ra không có ai điền form: cần nguồn cho trường bắt buộc, đứng tên một người.
bool startAutomatic(String type) => !const {'manual', 'message_action', 'public_form', 'flow'}.contains(type);

const _weekdayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

String intervalLabel(int s) => s % 86400 == 0
    ? tr('{0} ngày', [s ~/ 86400])
    : s % 3600 == 0
        ? tr('{0} giờ', [s ~/ 3600])
        : s % 60 == 0
            ? tr('{0} phút', [s ~/ 60])
            : tr('{0} giây', [s]);

/// Dòng tóm tắt của nốt trên sơ đồ.
String startSummary(Map s, AppState app) {
  final at = '${s['at'] ?? '08:00'}';
  switch ('${s['type']}') {
    case 'manual':
      final who = s['who'] as List? ?? const [];
      return who.isEmpty ? tr('Mọi người') : who.map((w) => whoLabel(w, app)).join(', ');
    case 'once':
      return '${s['at'] ?? tr('Chưa chọn ngày giờ')}';
    case 'schedule':
      final day = s['last_day'] == true ? tr('ngày cuối tháng') : tr('ngày {0}', [s['day'] ?? 1]);
      return switch ('${s['every']}') {
        'hour' => tr('Mỗi giờ, phút {0}', [at.split(':').last]),
        'week' => tr('{0} lúc {1}', [
            [for (final d in (s['weekdays'] as List? ?? const [])) _weekdayNames[((d as num).toInt() - 1).clamp(0, 6)]].join(', ').ifEmptyOr(tr('Mọi ngày')),
            at,
          ]),
        'month' => tr('Hằng tháng {0} lúc {1}', [day, at]),
        'year' => tr('Hằng năm {0}/{1} lúc {2}', [s['day'] ?? 1, s['month'] ?? 1, at]),
        _ => tr('Hằng ngày lúc {0}', [at]),
      };
    case 'interval':
      return tr('Mỗi {0}', [intervalLabel((s['seconds'] as num?)?.toInt() ?? 60)]);
    case 'webhook':
      return tr('URL riêng + secret');
    case 'chat_message':
      final chs = [for (final c in (s['channels'] as List? ?? const [])) channelLabel(app, '$c')];
      final kw = [for (final k in (s['keywords'] as List? ?? const [])) '$k'];
      return [chs.isEmpty ? tr('Chưa chọn nhóm') : chs.join(', '), if (kw.isNotEmpty) kw.join(' / ')].join(' · ');
    case 'message_action':
      return '${s['label'] ?? ''}'.ifEmptyOr(tr('Tạo tiến trình từ tin này'));
    case 'public_form':
      return tr('Link / mã QR');
    case 'date_due':
      return tr('Trước {0} ngày · {1}', [s['days_before'] ?? 0, '${s['tool'] ?? ''}'.ifEmptyOr(tr('chưa chọn công cụ'))]);
    case 'watch':
      return [
        tr('Mỗi {0} · {1}', [intervalLabel((s['seconds'] as num?)?.toInt() ?? 300), '${s['tool'] ?? ''}'.ifEmptyOr(tr('chưa chọn công cụ'))]),
        if (s['mode'] == 'once') tr('mỗi khoá một lần'),
        if (s['baseline_on_enable'] == true) tr('lấy mốc khi bật'),
      ].join(' · ');
    case 'flow':
      final from = s['from'] as List? ?? const [];
      return from.isEmpty ? tr('Mọi quy trình được gọi') : tr('{0} quy trình được gọi', [from.length]);
    case 'email':
      return '${s['mailbox'] ?? ''}'.ifEmptyOr(tr('Chưa chọn hộp thư'));
  }
  return '';
}

extension on String {
  String ifEmptyOr(String other) => trim().isEmpty ? other : this;
}

String channelLabel(AppState app, String id) {
  final c = app.channels[id];
  return c == null ? id : app.channelTitle(c);
}

/// Nốt mới, mã không trùng với các nốt đã có.
Map<String, dynamic> newStart(String type, List existing) {
  final ids = {for (final s in existing) if (s is Map) '${s['id']}'};
  var id = type;
  for (var i = 2; ids.contains(id); i++) {
    id = '${type}_$i';
  }
  return {
    'id': id,
    'type': type,
    ...switch (type) {
      'once' => {'at': _fmtDateTime(DateTime.now().add(const Duration(days: 1)).copyWith(hour: 8, minute: 0))},
      'schedule' => {'every': 'day', 'at': '08:00'},
      'interval' => {'seconds': 300},
      'chat_message' => {'channels': <String>[], 'mapping': <String, dynamic>{}},
      'date_due' => {'server': '', 'tool': '', 'date': '', 'days_before': 7, 'at': '08:00'},
      'watch' => {'server': '', 'tool': '', 'seconds': 300, 'cond': ''},
      'email' => {'mailbox': ''},
      _ => <String, dynamic>{},
    },
  };
}

/// Quy trình lưu trước khi có nốt Bắt đầu (`who_can_start` + `trigger`): đổi sang `starts` (máy chủ hiểu cả hai).
List<Map<String, dynamic>> legacyStarts(Map meta) {
  final out = <Map<String, dynamic>>[
    {'id': 'manual', 'type': 'manual', if ((meta['who_can_start'] as List? ?? const []).isNotEmpty) 'who': meta['who_can_start']},
  ];
  // Trước đây quy trình nào cũng gọi được: giữ như cũ.
  out.add({'id': 'flow', 'type': 'flow'});
  final t = meta['trigger'];
  if (t is Map) {
    final s = t['schedule'];
    if (s is Map) out.add({'id': 'schedule', 'type': 'schedule', ...s.cast<String, dynamic>(), if (t['run_as'] != null) 'run_as': t['run_as']});
    final w = t['webhook'];
    if (w is Map) {
      out.add({
        'id': 'webhook',
        'type': 'webhook',
        if ((w['mapping'] as Map? ?? const {}).isNotEmpty) 'mapping': w['mapping'],
        if (w['dedupe'] != null) 'dedupe': w['dedupe'],
        if (w['title'] != null) 'title': w['title'],
        if (t['run_as'] != null) 'run_as': t['run_as'],
      });
    }
  }
  return out;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _fmtDateTime(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

/// Thuộc tính của một dòng trong kết quả tool: mảng duy nhất trong kết quả (hoặc kết quả là mảng), không thì chính kết quả.
Map<String, dynamic> toolItemProps(Map? tool) {
  final os = (tool?['output_schema'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> propsOf(Map? s) => ((s?['properties'] as Map?) ?? const {}).cast<String, dynamic>();
  if (os['type'] == 'array') return propsOf(os['items'] as Map?);
  final props = propsOf(os);
  final arrays = [for (final e in props.entries) if ((e.value as Map?)?['type'] == 'array') e];
  if (arrays.length == 1) return propsOf(((arrays.first.value as Map)['items']) as Map?);
  return props;
}

String _condType(Object? schema) => switch ((schema as Map?)?['type']) { 'number' || 'integer' => 'number', 'boolean' => 'bool', _ => 'text' };

/// Dữ liệu nguồn của từng loại nốt (đường dẫn, nhãn, kiểu) cho ô "Lấy giá trị cho từng trường" và tiêu đề.
List<CondVar> startSources(Map s, Map integ) {
  final item = [
    for (final e in toolItemProps(_toolOf(integ, s)).entries) CondVar('item.${e.key}', '${(e.value as Map?)?['title'] ?? e.key}', _condType(e.value)),
  ];
  return switch ('${s['type']}') {
    'once' || 'schedule' || 'interval' => [CondVar('at', tr('Thời điểm chạy'), 'text')],
    'chat_message' || 'message_action' => [
        CondVar('text', tr('Nội dung tin'), 'text'),
        CondVar('user_display', tr('Tên người gửi'), 'text'),
        CondVar('user', tr('Người gửi (chọn người)'), 'user'),
        CondVar('user_name', tr('Tên đăng nhập người gửi'), 'text'),
        CondVar('channel_name', tr('Tên nhóm'), 'text'),
        CondVar('link', tr('Link tin nhắn'), 'text'),
        CondVar('at', tr('Thời gian gửi'), 'text'),
      ],
    'date_due' => [...item, CondVar('date', tr('Ngày tới hạn'), 'text'), CondVar('days_left', tr('Số ngày còn lại'), 'number')],
    'watch' => item,
    'email' => [
        CondVar('subject', tr('Tiêu đề thư'), 'text'),
        CondVar('text', tr('Nội dung thư'), 'text'),
        CondVar('from', tr('Địa chỉ người gửi'), 'text'),
        CondVar('from_name', tr('Tên người gửi'), 'text'),
        CondVar('to', tr('Gửi tới'), 'text'),
        CondVar('date', tr('Ngày gửi'), 'text'),
      ],
    _ => const [],
  };
}

Map? _toolOf(Map integ, Map s) {
  final srv = [for (final m in (integ['mcp'] as List? ?? const [])) if (m is Map && m['name'] == mcpKeyOf(s)) m].firstOrNull;
  return [for (final t in (srv?['tools'] as List? ?? const [])) if (t is Map && t['name'] == s['tool']) t].firstOrNull;
}

// ---------------------------------------------------------------------------------------------- bảng chọn loại

/// Chọn loại nốt Bắt đầu. [existing]: các nốt đã có (loại chỉ được một thì mờ).
class StartTypeSheet extends StatelessWidget {
  final List existing;
  const StartTypeSheet({super.key, this.existing = const []});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final have = {for (final s in existing) if (s is Map) '${s['type']}'};
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), shrinkWrap: true, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(tr('Thêm cách bắt đầu'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
        ),
        for (final (type, icon, desc) in startTypes)
          Builder(builder: (context) {
            final off = singleStartTypes.contains(type) && have.contains(type);
            return ListTile(
              enabled: !off,
              dense: true,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: kGroupStart.withValues(alpha: off ? 0.06 : 0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: off ? pal.sub : kGroupStart, size: 20),
              ),
              title: Text(startTypeLabel(type), style: TextStyle(fontWeight: FontWeight.w600, color: off ? pal.sub : pal.text)),
              subtitle: Text(off ? tr('Quy trình đã có bước này') : tr(desc)),
              onTap: off ? null : () => Navigator.pop(context, type),
            );
          }),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------- cài đặt nốt

/// Cài đặt một nốt Bắt đầu. Trả về nốt mới (Map), 'delete', hoặc null (huỷ) qua [onDone] / Navigator.pop.
class StartConfigSheet extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final Map<String, dynamic> start;
  final List<FlowField> form;
  final Map<String, List<String>> roles;
  final Map<String, dynamic> integ;
  final String flowId;
  /// Các quy trình (trang quản trị: có `calls` = quy trình mà nó mở).
  final List<Map<String, dynamic>> flows;
  final void Function(Object? result)? onDone;
  const StartConfigSheet({
    super.key,
    required this.app,
    required this.api,
    required this.start,
    required this.form,
    required this.roles,
    required this.integ,
    required this.flowId,
    this.flows = const [],
    this.onDone,
  });
  @override
  State<StartConfigSheet> createState() => _StartConfigSheetState();
}

class _StartConfigSheetState extends State<StartConfigSheet> {
  late final Map<String, dynamic> s = jsonDecode(jsonEncode(widget.start)) as Map<String, dynamic>;
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _hook;
  String? _infoErr;
  bool _showSecret = false;

  String get type => '${s['type']}';
  Map<String, dynamic> get mapping => (s['mapping'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _loadInfo();
    if (type == 'webhook') _loadHook();
  }

  Future<void> _loadInfo({String? rotate}) async {
    if (widget.flowId.isEmpty) return;
    try {
      final r = await widget.api.startInfo(widget.flowId, rotate: rotate);
      if (mounted) {
        setState(() {
          _info = r;
          _infoErr = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _infoErr = '$e');
    }
  }

  Future<void> _loadHook({bool rotate = false}) async {
    if (widget.flowId.isEmpty) return;
    try {
      final h = await widget.api.webhook(widget.flowId, rotate: rotate);
      if (mounted) setState(() => _hook = h);
    } catch (e) {
      if (mounted) setState(() => _infoErr = '$e');
    }
  }

  void _finish(Object? r) => widget.onDone != null ? widget.onDone!(r) : Navigator.pop(context, r);

  void _set(String k, Object? v) => setState(() => (v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty)) ? s.remove(k) : s[k] = v);

  Widget _gap() => const SizedBox(height: 14);

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: Theme.of(context).textTheme.labelLarge));

  Widget _note(String t, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(t, style: TextStyle(color: color ?? Pal.of(context).sub, fontSize: 12.5)),
      );

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã chép {0}', [what]))));
  }

  Widget _box(String label, String value, {bool secret = false, Widget? extra}) {
    final pal = Pal.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: pal.sub, fontWeight: FontWeight.w600)),
            SelectableText(secret && !_showSecret ? '•' * 24 : value, style: const TextStyle(fontSize: 13)),
          ]),
        ),
        if (secret) IconButton(onPressed: () => setState(() => _showSecret = !_showSecret), icon: Icon(_showSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18)),
        ?extra,
        IconButton(tooltip: tr('Chép'), onPressed: () => _copy(value, label), icon: const Icon(Icons.copy_rounded, size: 18)),
      ]),
    );
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Đồng ý'))),
          ],
        ),
      ) ==
      true;

  // ------------------------------------------------------------------ từng loại

  List<Widget> _manual() => [
        _label(tr('Ai được bắt đầu')),
        WhoListField(app: widget.app, roles: widget.roles, value: s['who'] as List? ?? const [], emptyLabel: tr('Mọi người'), onChanged: (v) => _set('who', v)),
      ];

  List<Widget> _once() {
    final cur = DateTime.tryParse('${s['at'] ?? ''}'.replaceFirst(' ', 'T')) ?? DateTime.now();
    return [
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_rounded, size: 18),
          label: Text('${_two(cur.day)}/${_two(cur.month)}/${cur.year}'),
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
            if (d != null) _set('at', _fmtDateTime(cur.copyWith(year: d.year, month: d.month, day: d.day)));
          },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.access_time_rounded, size: 18),
          label: Text('${_two(cur.hour)}:${_two(cur.minute)}'),
          onPressed: () async {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(cur));
            if (t != null) _set('at', _fmtDateTime(cur.copyWith(hour: t.hour, minute: t.minute)));
          },
        ),
      ]),
      _note(tr('Giờ Việt Nam. Chạy đúng một lần; đã qua quá một ngày lúc lưu thì không chạy.')),
    ];
  }

  Widget _timeButton(String key, {String def = '08:00', bool minuteOnly = false}) {
    final at = '${s[key] ?? def}';
    final p = at.split(':');
    return OutlinedButton.icon(
      icon: const Icon(Icons.access_time_rounded, size: 18),
      label: Text(minuteOnly ? tr('Phút {0}', [p.last]) : tr('Lúc {0}', [at])),
      onPressed: () async {
        final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p.first) ?? 8, minute: int.tryParse(p.last) ?? 0));
        if (t != null) _set(key, '${_two(t.hour)}:${_two(t.minute)}');
      },
    );
  }

  List<Widget> _schedule() {
    final every = '${s['every'] ?? 'day'}';
    final days = [for (final d in (s['weekdays'] as List? ?? const [])) (d as num).toInt()];
    final day = ((s['day'] as num?)?.toInt() ?? 1).clamp(1, 31);
    return [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, label) in [('hour', tr('Mỗi giờ')), ('day', tr('Hằng ngày')), ('week', tr('Hằng tuần')), ('month', tr('Hằng tháng')), ('year', tr('Hằng năm'))])
          ChoiceChip(label: Text(label), selected: every == k, onSelected: (_) => _set('every', k)),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _timeButton('at', minuteOnly: every == 'hour'),
        if (every == 'week')
          for (var d = 1; d <= 7; d++)
            FilterChip(label: Text(_weekdayNames[d - 1]), selected: days.contains(d), onSelected: (v) => _set('weekdays', v ? ([...days, d]..sort()) : ([...days]..remove(d)))),
        if (every == 'year')
          DropdownButton<int>(
            value: ((s['month'] as num?)?.toInt() ?? 1).clamp(1, 12),
            items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(tr('Tháng {0}', [m])))],
            onChanged: (v) => _set('month', v),
          ),
        if (every == 'month' || every == 'year')
          DropdownButton<int>(
            value: every == 'month' && s['last_day'] == true ? 0 : day,
            items: [
              if (every == 'month') DropdownMenuItem(value: 0, child: Text(tr('Ngày cuối tháng'))),
              for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text(tr('Ngày {0}', [d]))),
            ],
            onChanged: (v) => setState(() {
              if (v == 0) {
                s['last_day'] = true;
                s.remove('day');
              } else {
                s.remove('last_day');
                s['day'] = v;
              }
            }),
          ),
      ]),
      if ((every == 'month' || every == 'year') && day > 28 && s['last_day'] != true) _note(tr('Tháng ít ngày hơn thì chạy vào ngày cuối tháng.')),
      _note(tr('Giờ Việt Nam. Lần đầu sau khi lưu chỉ ghi mốc, chạy từ mốc kế tiếp.')),
    ];
  }

  /// Chọn chu kỳ: các mức hay dùng + tự nhập (giây / phút / giờ).
  List<Widget> _seconds(String key, int def, {required String label}) {
    final cur = (s[key] as num?)?.toInt() ?? def;
    const presets = [30, 60, 300, 900, 1800, 3600, 21600, 86400];
    return [
      _label(label),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in presets) ChoiceChip(label: Text(intervalLabel(p)), selected: cur == p, onSelected: (_) => _set(key, p)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          width: 110,
          child: TextFormField(
            key: ValueKey('$key-$cur'),
            initialValue: '${cur % 3600 == 0 ? cur ~/ 3600 : cur % 60 == 0 ? cur ~/ 60 : cur}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Tự nhập'), isDense: true, border: const OutlineInputBorder()),
            onFieldSubmitted: (v) {
              final n = int.tryParse(v.trim());
              final unit = cur % 3600 == 0 ? 3600 : cur % 60 == 0 ? 60 : 1;
              if (n != null && n > 0) _set(key, n * unit);
            },
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<int>(
          value: cur % 3600 == 0 ? 3600 : cur % 60 == 0 ? 60 : 1,
          items: [DropdownMenuItem(value: 1, child: Text(tr('giây'))), DropdownMenuItem(value: 60, child: Text(tr('phút'))), DropdownMenuItem(value: 3600, child: Text(tr('giờ')))],
          onChanged: (u) {
            final n = cur % 3600 == 0 ? cur ~/ 3600 : cur % 60 == 0 ? cur ~/ 60 : cur;
            if (u != null) _set(key, n * u);
          },
        ),
      ]),
      if (cur < 30) _note(tr('Tối thiểu 30 giây.'), color: kFlowRed),
    ];
  }

  List<Widget> _webhook() {
    final h = _hook;
    final url = h == null ? '' : '${widget.api.publicBase}${h['path']}';
    final paths = jsonPaths(h?['last_payload']);
    return [
      if (widget.flowId.isEmpty) _note(tr('Đặt mã quy trình (tab Cài đặt) để lấy URL.'), color: kFlowOrange),
      if (h == null && widget.flowId.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
      if (h != null) ...[
        _box(tr('URL nhận dữ liệu (POST JSON)'), url),
        _box(tr('Secret'), '${h['secret'] ?? ''}', secret: true),
        _note(tr('Hệ thống gửi kèm header X-Flygo-Secret: <secret>, hoặc X-Flygo-Signature: sha256=<HMAC-SHA256 của nội dung, khoá là secret>.')),
        Row(children: [
          TextButton.icon(onPressed: () => _loadHook(), icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(tr('Tải dữ liệu mới nhận'))),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              if (await _confirm(tr('Đổi URL và secret?'), tr('URL và secret cũ hết hiệu lực ngay. Hệ thống bên ngoài phải cập nhật cái mới.'))) _loadHook(rotate: true);
            },
            icon: const Icon(Icons.autorenew_rounded, size: 18, color: kFlowOrange),
            label: Text(tr('Đổi URL / secret'), style: const TextStyle(color: kFlowOrange)),
          ),
        ]),
        if (h['last_payload'] == null)
          _note(tr('Chưa nhận dữ liệu nào. Cho hệ thống bên ngoài gửi thử một lần để chọn khoá cho từng trường.'), color: kFlowOrange),
      ],
      _gap(),
      DropdownButtonFormField<String>(
        initialValue: paths.contains(s['dedupe']) ? '${s['dedupe']}' : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Mã giao dịch (gửi lại cùng mã thì không tạo trùng)'), border: const OutlineInputBorder()),
        items: [DropdownMenuItem(value: '', child: Text(tr('(không chống trùng)'))), for (final p in paths) DropdownMenuItem(value: p, child: Text(p))],
        onChanged: (v) => _set('dedupe', v),
      ),
    ];
  }

  Future<void> _pickChannels() async {
    final app = widget.app;
    final all = [
      for (final c in app.channels.values)
        if ((c.type == 'O' || c.type == 'P') && !c.isProcess && c.deleteAt == 0) c,
    ]..sort((a, b) => app.channelTitle(a).toLowerCase().compareTo(app.channelTitle(b).toLowerCase()));
    final sel = {for (final c in (s['channels'] as List? ?? const [])) '$c'};
    final r = await showDialog<Set<String>>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr('Chọn nhóm')),
          content: SizedBox(
            width: 420,
            height: 420,
            child: all.isEmpty
                ? Center(child: Text(tr('Bạn chưa ở nhóm nào')))
                : ListView(children: [
                    for (final c in all)
                      CheckboxListTile(
                        dense: true,
                        value: sel.contains(c.id),
                        title: Text(app.channelTitle(c)),
                        onChanged: (v) => set(() => v == true ? sel.add(c.id) : sel.remove(c.id)),
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(d, sel), child: Text(tr('Xong'))),
          ],
        ),
      ),
    );
    if (r != null) _set('channels', r.toList());
  }

  /// Danh sách chữ (từ khoá, người gửi, tiêu đề...): chip + ô thêm.
  Widget _words(String key, String label, String hint) {
    final list = [for (final k in (s[key] as List? ?? const [])) '$k'];
    final ctl = TextEditingController();
    void add() {
      final v = ctl.text.trim();
      if (v.isNotEmpty && !list.contains(v)) _set(key, [...list, v]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(label),
      if (list.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in list) InputChip(label: Text(k), onDeleted: () => _set(key, [...list]..remove(k))),
          ]),
        ),
      TextField(
        controller: ctl,
        decoration: InputDecoration(hintText: hint, isDense: true, border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: add, icon: const Icon(Icons.add_rounded))),
        onSubmitted: (_) => add(),
      ),
    ]);
  }

  List<Widget> _chat() {
    final chs = [for (final c in (s['channels'] as List? ?? const [])) '$c'];
    return [
      InputDecorator(
        decoration: InputDecoration(labelText: tr('Nhóm theo dõi'), border: const OutlineInputBorder(), contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8)),
        child: Row(children: [
          Expanded(child: Text(chs.isEmpty ? tr('Chưa chọn') : chs.map((c) => channelLabel(widget.app, c)).join(', '))),
          TextButton(onPressed: _pickChannels, child: Text(tr('Chọn'))),
        ]),
      ),
      _note(tr('Flow Bot phải được thêm vào các nhóm này mới đọc được tin. Lần đầu sau khi lưu chỉ tính tin mới.')),
      _gap(),
      _words('keywords', tr('Chỉ tin chứa một trong các từ'), tr('Vd #baohong (bỏ trống = mọi tin)')),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Chỉ tin gốc')),
        subtitle: Text(tr('Không tính trả lời trong luồng tin')),
        value: s['root_only'] == true,
        onChanged: (v) => _set('root_only', v ? true : null),
      ),
    ];
  }

  List<Widget> _messageAction() => [
        TextFormField(
          initialValue: '${s['label'] ?? ''}',
          decoration: InputDecoration(labelText: tr('Chữ trên menu tin nhắn'), hintText: tr('Vd Báo hỏng, Tạo đơn hàng'), border: const OutlineInputBorder()),
          onChanged: (v) => s['label'] = v.trim(),
        ),
        _gap(),
        _label(tr('Ai thấy mục này')),
        WhoListField(app: widget.app, roles: widget.roles, value: s['who'] as List? ?? const [], emptyLabel: tr('Mọi người'), onChanged: (v) => _set('who', v)),
        _note(tr('Nhấn giữ một tin nhắn → "Tạo tiến trình" → chọn mục này: biểu mẫu điền sẵn từ tin, người bấm sửa rồi gửi.')),
      ];

  List<Widget> _publicForm() {
    final pf = (_info?['public_form'] as Map?)?.cast<String, dynamic>();
    final bad = [
      for (final f in widget.form)
        if (f.required && f.calc == null && f.defaultValue == null && const {'table', 'files', 'user'}.contains(f.type)) f.label,
    ];
    return [
      TextFormField(
        initialValue: '${s['intro'] ?? ''}',
        minLines: 2,
        maxLines: 5,
        decoration: InputDecoration(labelText: tr('Lời giới thiệu trên trang'), hintText: tr('Vd Quý khách điền thông tin để yêu cầu bảo hành'), border: const OutlineInputBorder()),
        onChanged: (v) => s['intro'] = v.trim(),
      ),
      _gap(),
      if (widget.flowId.isEmpty) _note(tr('Đặt mã quy trình (tab Cài đặt) để lấy link.'), color: kFlowOrange),
      if (pf == null && widget.flowId.isNotEmpty && _infoErr == null) const LinearProgressIndicator(minHeight: 2),
      if (pf != null) ...[
        _box(tr('Link biểu mẫu'), '${pf['url']}'),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: Text(tr('Mở trang in mã QR')),
            onPressed: () => launchUrl(Uri.parse('${pf['qr']}'), mode: LaunchMode.externalApplication),
          ),
          TextButton.icon(
            onPressed: () async {
              if (await _confirm(tr('Đổi link?'), tr('Link và mã QR cũ hết hiệu lực ngay, phải in lại mã QR.'))) _loadInfo(rotate: 'public_form');
            },
            icon: const Icon(Icons.autorenew_rounded, size: 18, color: kFlowOrange),
            label: Text(tr('Đổi link'), style: const TextStyle(color: kFlowOrange)),
          ),
        ]),
        _note(tr('Trang chỉ hoạt động khi quy trình đã lưu và đang bật. Người ngoài điền các trường chữ, số, tiền, ngày, chọn, có/không; mỗi máy gửi tối đa 5 lần / 10 phút.')),
      ],
      if (bad.isNotEmpty) _note(tr('Trường bắt buộc không nhập được trên web: {0}. Bỏ bắt buộc hoặc đặt giá trị mặc định.', [bad.join(', ')]), color: kFlowRed),
    ];
  }

  /// Chọn ứng dụng MCP + công cụ + tham số (giá trị cố định).
  List<Widget> _tool() {
    final servers = [for (final m in (widget.integ['mcp'] as List? ?? const [])) if (m is Map) m];
    final srv = servers.where((m) => m['name'] == mcpKeyOf(s)).firstOrNull;
    final tools = [for (final t in (srv?['tools'] as List? ?? const [])) if (t is Map) t];
    final tool = tools.where((t) => t['name'] == s['tool']).firstOrNull;
    final props = ((tool?['input_schema'] as Map?)?['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final args = (s['args'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final itemProps = toolItemProps(tool);
    if (servers.isEmpty) {
      return [_note(tr('Máy chủ Flows chưa khai báo ứng dụng MCP nào (cấu hình "mcp"). Nhờ quản trị hệ thống thêm.'), color: kFlowOrange)];
    }
    return [
      DropdownButtonFormField<String>(
        initialValue: srv == null ? null : '${srv['name']}',
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Ứng dụng'), border: const OutlineInputBorder()),
        items: [for (final m in servers) DropdownMenuItem(value: '${m['name']}', child: Text('${m['label']}'))],
        onChanged: (v) => setState(() {
          setMcpKey(s, servers, v);
          s['tool'] = '';
          s.remove('args');
        }),
      ),
      _gap(),
      DropdownButtonFormField<String>(
        key: ValueKey('tool-${mcpKeyOf(s)}'),
        initialValue: tool == null ? null : '${tool['name']}',
        isExpanded: true,
        decoration: InputDecoration(labelText: tr('Công cụ (đọc dữ liệu)'), helperText: tool == null ? null : '${tool['description'] ?? ''}', helperMaxLines: 3, border: const OutlineInputBorder()),
        items: [
          for (final t in tools)
            DropdownMenuItem(value: '${t['name']}', enabled: t['allowed'] == true, child: Text(toolTitle(t), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() {
          s['tool'] = v;
          s.remove('args');
        }),
      ),
      for (final e in props.entries) ...[
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('arg-${s['tool']}-${e.key}'),
          initialValue: '${args[e.key] ?? ''}',
          decoration: InputDecoration(
            labelText: '${(e.value as Map?)?['title'] ?? e.key}',
            helperText: (e.value as Map?)?['description'] == null ? null : '${(e.value as Map)['description']}',
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) {
            final isNum = const {'number', 'integer'}.contains((e.value as Map?)?['type']);
            final next = {...args};
            v.trim().isEmpty ? next.remove(e.key) : next[e.key] = isNum && num.tryParse(v.trim()) != null ? num.parse(v.trim()) : v.trim();
            s['args'] = next;
          },
        ),
      ],
      const SizedBox(height: 10),
      if (itemProps.isEmpty)
        TextFormField(
          initialValue: '${s['items'] ?? ''}',
          decoration: InputDecoration(labelText: tr('Danh sách trong kết quả (tuỳ chọn)'), hintText: tr('Vd data.rows; bỏ trống = tự tìm'), isDense: true, border: const OutlineInputBorder()),
          onChanged: (v) => v.trim().isEmpty ? s.remove('items') : s['items'] = v.trim(),
        ),
      const SizedBox(height: 10),
      _column('key', tr('Cột nhận diện dòng'), itemProps, hint: tr('Vd ma_hd (mỗi dòng chỉ tạo tiến trình một lần)')),
    ];
  }

  /// Chọn một cột của dòng (theo khuôn kết quả của tool), không có khuôn thì gõ tên cột.
  Widget _column(String key, String label, Map<String, dynamic> props, {String? hint}) {
    if (props.isEmpty) {
      return TextFormField(
        key: ValueKey('$key-free'),
        initialValue: '${s[key] ?? ''}',
        decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
        onChanged: (v) => v.trim().isEmpty ? s.remove(key) : s[key] = v.trim(),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('$key-${s['tool']}'),
      initialValue: props.containsKey(s[key]) ? '${s[key]}' : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [for (final e in props.entries) DropdownMenuItem(value: e.key, child: Text('${(e.value as Map?)?['title'] ?? e.key}'))],
      onChanged: (v) => _set(key, v),
    );
  }

  List<Widget> _dateDue() {
    final props = toolItemProps(_toolOf(widget.integ, s));
    return [
      ..._tool(),
      _gap(),
      _column('date', tr('Cột ngày tới hạn'), props, hint: tr('Vd ngay_het_han (YYYY-MM-DD hoặc DD/MM/YYYY)')),
      _gap(),
      Row(children: [
        SizedBox(
          width: 140,
          child: TextFormField(
            initialValue: '${s['days_before'] ?? 0}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Báo trước (ngày)'), isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) => s['days_before'] = int.tryParse(v.trim()) ?? 0,
          ),
        ),
        const SizedBox(width: 12),
        _timeButton('at'),
      ]),
      _note(tr('Mỗi ngày vào giờ đã chọn, dòng nào còn ít hơn hoặc bằng số ngày báo trước thì tạo một tiến trình (mỗi dòng một lần cho mỗi ngày tới hạn).')),
    ];
  }

  List<Widget> _watch() {
    final props = toolItemProps(_toolOf(widget.integ, s));
    final vars = [for (final e in props.entries) CondVar('item.${e.key}', '${(e.value as Map?)?['title'] ?? e.key}', _condType(e.value))];
    final cond = '${s['cond'] ?? ''}';
    return [
      ..._tool(),
      _gap(),
      ..._seconds('seconds', 300, label: tr('Kiểm tra mỗi')),
      _gap(),
      _label(tr('Điều kiện tạo tiến trình')),
      OutlinedButton.icon(
        icon: const Icon(Icons.rule_rounded, size: 18),
        label: Text(cond.isEmpty ? tr('Đặt điều kiện') : condLabel(cond, vars), maxLines: 3),
        onPressed: vars.isEmpty
            ? null
            : () async {
                final r = await showDialog<String>(context: context, builder: (_) => CondDialog(app: widget.app, expr: cond, vars: vars));
                if (r != null && r != '\u0000delete') _set('cond', r);
              },
      ),
      if (vars.isEmpty) _note(tr('Chọn công cụ có khai báo khuôn kết quả để đặt điều kiện.'), color: kFlowOrange),
      _note(s['mode'] == 'once'
          ? tr('Dòng thoả điều kiện thì tạo tiến trình; mỗi khoá chỉ tạo một tiến trình, kể cả khi hết thoả rồi thoả lại.')
          : tr('Dòng thoả điều kiện thì tạo tiến trình; hết thoả rồi thoả lại thì tạo tiến trình mới.')),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Lấy mốc khi bật')),
        subtitle: Text(tr('Lần kiểm đầu sau khi tạo / bật lại quy trình chỉ ghi nhận các dòng đang thoả, không tạo tiến trình (tránh tạo hàng loạt tiến trình cho dữ liệu cũ).')),
        value: s['baseline_on_enable'] == true,
        onChanged: (v) => _set('baseline_on_enable', v ? true : null),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('Mỗi khoá chỉ một lần')),
        subtitle: Text(tr('Mỗi dòng (theo cột nhận diện) tạo nhiều nhất một tiến trình, nhớ mãi kể cả khi dòng biến mất rồi quay lại.')),
        value: s['mode'] == 'once',
        onChanged: (v) => _set('mode', v ? 'once' : null),
      ),
      if (s['mode'] == 'once' && '${s['key'] ?? ''}'.isEmpty) _note(tr('Cần chọn "Cột nhận diện dòng" để nhớ khoá.'), color: kFlowOrange),
    ];
  }

  List<Widget> _flow() {
    String name(Map f) => '${f['icon'] ?? ''} ${f['name']}'.trim();
    final callers = [for (final f in widget.flows) if ((f['calls'] as List? ?? const []).contains(widget.flowId)) f];
    final from = [for (final x in (s['from'] as List? ?? const [])) '$x'];
    final others = [for (final f in widget.flows) if (f['id'] != widget.flowId) f];
    return [
      Text(callers.isEmpty ? tr('Chưa quy trình nào mở quy trình này.') : tr('Đang được mở từ: {0}', [callers.map(name).join(', ')])),
      _gap(),
      _label(tr('Quy trình được gọi')),
      SegmentedButton<bool>(
        segments: [ButtonSegment(value: true, label: Text(tr('Mọi quy trình'))), ButtonSegment(value: false, label: Text(tr('Chỉ quy trình chọn')))],
        selected: {from.isEmpty && s['_pick'] != true},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() {
          if (v.first) {
            s.remove('from');
            s.remove('_pick');
          } else {
            s['_pick'] = true;
          }
        }),
      ),
      if (from.isNotEmpty || s['_pick'] == true) ...[
        const SizedBox(height: 8),
        for (final f in others)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: from.contains(f['id']),
            title: Text(name(f)),
            onChanged: (v) => _set('from', v == true ? [...from, '${f['id']}'] : ([...from]..remove('${f['id']}'))),
          ),
        for (final c in callers.where((c) => !from.contains(c['id'])))
          _note(tr('"{0}" đang gọi quy trình này nhưng chưa được chọn: lần chạy tới sẽ bị chặn.', [name(c)]), color: kFlowRed),
      ],
      _note(tr('Thêm bước "Bắt đầu quy trình khác" ở quy trình kia để nối sang đây; giá trị các trường lấy từ tiến trình đó. Không có bước này thì không quy trình nào gọi được.')),
    ];
  }

  List<Widget> _email() {
    final boxes = [for (final m in (widget.integ['mailboxes'] as List? ?? const [])) if (m is Map) m];
    return [
      if (boxes.isEmpty)
        _note(tr('Máy chủ Flows chưa khai báo hộp thư nào (cấu hình "mailboxes"). Nhờ quản trị hệ thống thêm.'), color: kFlowOrange)
      else
        DropdownButtonFormField<String>(
          initialValue: boxes.any((m) => m['name'] == s['mailbox']) ? '${s['mailbox']}' : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Hộp thư'), border: const OutlineInputBorder()),
          items: [for (final m in boxes) DropdownMenuItem(value: '${m['name']}', child: Text('${m['label']} (${m['address']})'))],
          onChanged: (v) => _set('mailbox', v),
        ),
      _gap(),
      _words('from', tr('Chỉ thư từ (chứa)'), tr('Vd @nhacungcap.vn (bỏ trống = mọi người gửi)')),
      _gap(),
      _words('subject', tr('Chỉ thư có tiêu đề chứa'), tr('Vd Đơn hàng (bỏ trống = mọi thư)')),
      _note(tr('Kiểm hộp thư mỗi phút; thư không bị đánh dấu đã đọc. Lần đầu sau khi lưu chỉ tính thư mới.')),
    ];
  }

  // ------------------------------------------------------------------ nguồn → trường

  Widget _mapping(List<CondVar> sources) {
    final m = mapping;
    final fields = [for (final f in widget.form) if (f.calc == null && f.type != 'table' && f.type != 'files') f];
    final webhookPaths = type == 'webhook' ? jsonPaths(_hook?['last_payload']) : const <String>[];
    final options = type == 'webhook' ? [for (final p in webhookPaths) CondVar(p, p, 'text')] : sources;
    void setField(String key, String? v) {
      final next = {...m};
      v == null || v.isEmpty ? next.remove(key) : next[key] = v;
      _set('mapping', next.isEmpty ? null : next);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(tr('Lấy giá trị cho từng trường')),
      if (fields.isEmpty) _note(tr('Biểu mẫu chưa có trường nào.')),
      for (final f in fields)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(flex: 4, child: Text(f.required && f.defaultValue == null ? '${f.label} *' : f.label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: options.isEmpty
                  ? TextFormField(
                      initialValue: '${m[f.key] ?? ''}',
                      decoration: InputDecoration(hintText: tr('khoá, vd amount'), isDense: true, border: const OutlineInputBorder()),
                      onChanged: (v) => setField(f.key, v.trim()),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: options.any((o) => o.path == m[f.key]) ? '${m[f.key]}' : '',
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: '', child: Text(tr('(không lấy)'))),
                        for (final o in options) DropdownMenuItem(value: o.path, child: Text(o.label, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setField(f.key, v),
                    ),
            ),
          ]),
        ),
    ]);
  }

  List<Widget> _common(List<CondVar> sources) {
    final auto = startAutomatic(type);
    final hasSource = sources.isNotEmpty || type == 'webhook';
    final titleVars = [
      for (final f in widget.form) if (f.type != 'table' && f.type != 'files') CondVar('form.${f.key}', f.label, f.type),
      for (final v in (type == 'webhook' ? [for (final p in jsonPaths(_hook?['last_payload'])) CondVar(p, p, 'text')] : sources)) CondVar('data.${v.path}', v.label, v.type),
    ];
    final missing = [
      for (final f in widget.form)
        if (auto && f.required && f.defaultValue == null && f.calc == null && f.showIf.isEmpty && !mapping.containsKey(f.key)) f.label,
    ];
    return [
      if (hasSource) ...[_gap(), _mapping(sources)],
      if (missing.isNotEmpty) _note(tr('Trường bắt buộc chưa có nguồn: {0}. Chọn nguồn hoặc đặt giá trị mặc định.', [missing.join(', ')]), color: kFlowRed),
      if (auto || type == 'public_form') ...[
        _gap(),
        TemplateField(label: tr('Tiêu đề tiến trình'), raw: '${s['title'] ?? ''}', vars: titleVars, lines: 1, onChanged: (v) => _set('title', v)),
        _gap(),
        WhoField(
          app: widget.app,
          roles: const {},
          label: tr('Tiến trình đứng tên'),
          value: s['run_as'] == null ? null : {'user': s['run_as']},
          onClear: () => _set('run_as', null),
          onChanged: (w) {
            final u = w is Map ? (w['user'] ?? (w['users'] as List?)?.firstOrNull) : null;
            if (u != null) _set('run_as', '$u');
          },
        ),
        _note(tr('Bỏ trống thì tiến trình đứng tên người lưu quy trình.')),
      ],
      // Theo thời gian: bỏ lượt khi lượt trước chưa xong, ẩn lượt chạy không làm gì.
      if (const {'once', 'schedule', 'interval'}.contains(type)) ...[
        _gap(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s['overlap'] == 'skip',
          title: Text(tr('Bỏ lượt khi lượt trước chưa xong')),
          subtitle: Text(tr('Tới giờ mà tiến trình trước của bước này còn chạy thì không tạo tiến trình mới')),
          onChanged: (v) => _set('overlap', v ? 'skip' : null),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: s['keep_noop_runs'] == false,
          title: Text(tr('Ẩn lượt chạy không làm gì')),
          subtitle: Text(tr('Lượt không nhắn tin, không đổi tiến trình, không ghi dữ liệu thì không hiện trong danh sách')),
          onChanged: (v) => _set('keep_noop_runs', v ? false : null),
        ),
      ],
    ];
  }

  Widget _status() {
    final st = ((_info?['starts'] as Map?)?[s['id']] as Map?)?.cast<String, dynamic>();
    if (st == null) return const SizedBox.shrink();
    final ok = (st['ok_at'] as num?)?.toInt();
    final err = st['error'] as String?;
    if (ok == null && err == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: (err != null ? kFlowRed : kGroupStart).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Text(
        err != null ? tr('Lỗi gần nhất: {0}', [err]) : tr('Kiểm tra gần nhất: {0}', [DateTime.fromMillisecondsSinceEpoch(ok!).toString().substring(0, 16)]),
        style: TextStyle(color: err != null ? kFlowRed : kGroupStart, fontSize: 12.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final sources = startSources(s, widget.integ);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        child: Row(children: [
          Icon(startIcon(type), color: kGroupStart),
          const SizedBox(width: 8),
          Expanded(child: Text(startTypeLabel(type), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text))),
          TextButton.icon(
            onPressed: () => _finish('delete'),
            icon: const Icon(Icons.delete_outline_rounded, color: kFlowRed),
            label: Text(tr('Xoá bước'), style: const TextStyle(color: kFlowRed)),
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
          _status(),
          TextFormField(
            initialValue: '${s['name'] ?? ''}',
            decoration: InputDecoration(labelText: tr('Tên bước (tuỳ chọn)'), hintText: startTypeLabel(type), border: const OutlineInputBorder()),
            onChanged: (v) => v.trim().isEmpty ? s.remove('name') : s['name'] = v.trim(),
          ),
          _gap(),
          ...switch (type) {
            'manual' => _manual(),
            'once' => _once(),
            'schedule' => _schedule(),
            'interval' => _seconds('seconds', 300, label: tr('Chạy mỗi')),
            'webhook' => _webhook(),
            'chat_message' => _chat(),
            'message_action' => _messageAction(),
            'public_form' => _publicForm(),
            'date_due' => _dateDue(),
            'watch' => _watch(),
            'flow' => _flow(),
            'email' => _email(),
            _ => const <Widget>[],
          },
          ..._common(sources),
          if (_infoErr != null) _note(_infoErr!, color: kFlowRed),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _finish(null), child: Text(tr('Hủy')))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton(onPressed: () => _finish(s..remove('_pick')), child: Text(tr('Xong')))),
          ]),
        ),
      ),
    ]);
  }
}
