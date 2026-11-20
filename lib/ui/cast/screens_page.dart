// App "Màn hình": mọi TV / máy chiếu đang mở hello.<tên miền> của công ty, xếp theo vị trí; trạng thái (rảnh, đang chiếu,
// khoá, cuộc họp, lịch tự chạy, tắt, chưa xác nhận); chi tiết một màn hình: xem trước, hàng chờ, chiếu lên, xin dùng,
// khoá, đổi tên / vị trí, lịch tự chạy (người quản lý / admin). Thứ tự ưu tiên: cuộc họp > chiếu tay > lịch.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../theme.dart' show toast;
import 'cast_api.dart';
import 'cast_screen.dart';

Color _dot(String status, bool online, bool approved) => !online
    ? Colors.grey
    : !approved
    ? Colors.amber
    : switch (status) {
        'meeting' => Colors.indigo,
        'locked' => Colors.red,
        'casting' => Colors.orange,
        'schedule' => Colors.teal,
        _ => Colors.green,
      };

String _statusText(String status, {required bool online, required bool approved, String nowBy = '', String nowName = '', Map? lock, String schedule = ''}) {
  if (!online) return tr('Đang tắt');
  if (!approved) return tr('⚠ Chưa xác nhận: quét mã trên màn hình một lần');
  return switch (status) {
    'meeting' => tr('Cuộc họp «{0}» · chỉ thành viên', ['${(lock?['meeting'] as Map?)?['title'] ?? ''}']),
    'locked' => tr('Đang khoá bởi {0}', ['${lock?['by_name'] ?? ''}']),
    'casting' => tr('Đang chiếu: {0}', [
      [nowBy, if (nowName.isNotEmpty) nowName].join(' · '),
    ]),
    'schedule' => tr('Lịch: {0}', [schedule.isEmpty ? nowName : schedule]),
    _ => lock?['mine'] == true ? tr('Bạn đang khoá') : tr('Đang rảnh'),
  };
}

class ScreensPage extends StatefulWidget {
  const ScreensPage({super.key});
  @override
  State<ScreensPage> createState() => _ScreensPageState();
}

class _ScreensPageState extends State<ScreensPage> {
  List<CastScreen>? _list;
  String? _error;
  Timer? _tick;
  final _q = TextEditingController();

  String get _token => context.read<AppState>().token;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await CastSession.screens(kServerUrl, _token, all: true);
      if (mounted) setState(() => (_list = l, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final q = _q.text.trim().toLowerCase();
    final list = (_list ?? const <CastScreen>[]).where((x) => q.isEmpty || '${x.name} ${x.location}'.toLowerCase().contains(q)).toList();
    // Nhóm theo vị trí; chưa xác nhận để riêng cuối.
    final groups = <String, List<CastScreen>>{};
    for (final x in list) {
      groups.putIfAbsent(!x.approved ? '~' : (x.location.isEmpty ? '' : x.location), () => []).add(x);
    }
    final keys = groups.keys.toList()
      ..sort(
        (a, b) => a == '~'
            ? 1
            : b == '~'
            ? -1
            : a.compareTo(b),
      );
    final online = list.where((x) => x.online).length, casting = list.where((x) => x.status == 'casting').length;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Màn hình')),
        actions: [IconButton(tooltip: tr('Làm mới'), onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => castFromDevice(context),
        icon: const Icon(Icons.cast_rounded),
        label: Text(tr('Đưa lên màn hình')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr('Tìm màn hình, vị trí…'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                tr('{0} online · {1} đang chiếu · TV mở hello.{2} là hiện ở đây', [
                  '$online',
                  '$casting',
                  Uri.parse(kServerUrl).host.split('.').skip(1).join('.'),
                ]),
                style: TextStyle(color: th.hintColor, fontSize: 13),
              ),
            ),
            if (_list == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: th.colorScheme.error)),
              ),
            if (_list != null && list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Chưa có màn hình nào. Mở hello trên TV / máy chiếu.'), textAlign: TextAlign.center),
              ),
            for (final k in keys) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  (k == '~'
                          ? tr('Chưa xác nhận')
                          : k.isEmpty
                          ? tr('Chưa đặt vị trí')
                          : k)
                      .toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .5, color: th.hintColor),
                ),
              ),
              for (final x in groups[k]!)
                ListTile(
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.tv_rounded, size: 32),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _dot(x.status, x.online, x.approved),
                            shape: BoxShape.circle,
                            border: Border.all(color: th.colorScheme.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _statusText(x.status, online: x.online, approved: x.approved, nowBy: x.nowBy, nowName: x.nowName, lock: x.lock, schedule: x.schedule),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await Navigator.of(context).push(
                      AppPageRoute(
                        builder: (_) => ScreenDetailPage(id: x.id, name: x.name),
                      ),
                    );
                    _load();
                  },
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final s = await pickAndPair(context, _token, preselect: '#code');
                  if (s != null) await s.stop(); // quét mã chỉ để xác nhận / thêm màn hình mới
                  _load();
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(tr('Thêm / xác nhận màn hình (quét mã)')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- chi tiết
class ScreenDetailPage extends StatefulWidget {
  final String id, name;
  const ScreenDetailPage({super.key, required this.id, required this.name});
  @override
  State<ScreenDetailPage> createState() => _ScreenDetailPageState();
}

const _days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

class _ScreenDetailPageState extends State<ScreenDetailPage> {
  Map? _d;
  String? _error;
  Timer? _tick;

  String get _token => context.read<AppState>().token;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await CastSession.screen(kServerUrl, _token, widget.id);
      if (mounted) setState(() => (_d = d, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _toast(String s) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(toast(Text(s)));

  Future<void> _act(String act, [Map body = const {}]) async {
    try {
      final r = await CastSession.screenAction(kServerUrl, _token, widget.id, act, body);
      if (act == 'request') _toast(r['notified'] == true ? tr('Đã báo người đang dùng màn hình') : tr('Người khoá không mở app lúc này, thử lại sau'));
      await _load();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _edit() async {
    final d = _d!;
    final name = TextEditingController(text: '${d['name'] ?? ''}'), loc = TextEditingController(text: '${d['location'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dl) => AlertDialog(
        title: Text(tr('Tên và vị trí')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: tr('Tên màn hình'), hintText: 'Phòng họp 3F-A'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: loc,
              decoration: InputDecoration(labelText: tr('Vị trí'), hintText: 'Văn phòng YLA · tầng 3'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dl, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(dl, true), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok == true) await _act('name', {'name': name.text.trim(), 'location': loc.text.trim()});
  }

  /// Thêm khung lịch: tắt màn hình, hoặc tự vào cuộc họp (mã phòng họp). Bộ trình chiếu: khi app Trình chiếu mới có.
  Future<void> _addSchedule() async {
    final r = await showDialog<Map>(context: context, builder: (_) => const _ScheduleDialog());
    if (r == null) return;
    final cur = [for (final x in (_d?['schedules'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)..remove('by_name')];
    await _act('schedules', {
      'schedules': [...cur, r],
    });
  }

  Future<void> _removeSchedule(String id) async {
    final cur = [
      for (final x in (_d?['schedules'] as List? ?? const []))
        if ('${(x as Map)['id']}' != id) Map<String, dynamic>.from(x)..remove('by_name'),
    ];
    await _act('schedules', {'schedules': cur});
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: Text('${d?['name'] ?? widget.name}'),
        actions: [if (d?['manager'] == true) IconButton(tooltip: tr('Sửa tên, vị trí'), onPressed: _edit, icon: const Icon(Icons.edit_rounded))],
      ),
      body: d == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : ListView(padding: const EdgeInsets.all(16), children: _body(th, d)),
    );
  }

  List<Widget> _body(ThemeData th, Map d) {
    final online = d['online'] == true, approved = d['approved'] == true;
    final status = '${d['status']}';
    final content = d['content'] as Map?;
    final lock = d['lock'] as Map?;
    final queue = [for (final x in (d['queue'] as List? ?? const [])) '$x'];
    final schedules = [for (final x in (d['schedules'] as List? ?? const [])) x as Map];
    final manager = d['manager'] == true;
    final today = d['today'] as Map? ?? const {};
    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: TextStyle(color: th.hintColor)),
          ),
          Expanded(child: Text(v, textAlign: TextAlign.right)),
        ],
      ),
    );
    return [
      _Preview(content: content, status: status, online: online),
      const SizedBox(height: 10),
      Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: _dot(status, online, approved), shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusText(
                    status,
                    online: online,
                    approved: approved,
                    nowBy: '${d['now_by'] ?? ''}',
                    nowName: '${content?['name'] ?? ''}',
                    lock: lock,
                    schedule: '${d['schedule'] ?? ''}',
                  ) +
                  ((content?['pages'] as num? ?? 0) > 0 ? ' · ${content!['page']}/${content['pages']}' : ''),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (online && approved && status != 'locked')
            FilledButton.icon(
              onPressed: () => castFromDevice(context, screenId: widget.id),
              icon: const Icon(Icons.cast_rounded),
              label: Text(status == 'casting' ? tr('Chiếu (xếp hàng)') : tr('Chiếu lên màn hình này')),
            ),
          // Dừng nội dung để lại (vd bộ slide Show) hoặc, với người quản lý, dừng người đang chiếu.
          if (status == 'casting' && (d['detached'] == true || manager))
            OutlinedButton.icon(onPressed: () => _act('stopcast'), icon: const Icon(Icons.stop_rounded), label: Text(tr('Dừng chiếu'))),
          if (status == 'locked')
            FilledButton.tonalIcon(onPressed: () => _act('request'), icon: const Icon(Icons.pan_tool_rounded), label: Text(tr('Xin dùng'))),
          if (lock != null && (lock['mine'] == true || manager) && lock['meeting'] == null)
            OutlinedButton.icon(onPressed: () => _act('unlock'), icon: const Icon(Icons.lock_open_rounded), label: Text(tr('Mở khoá'))),
          if (!approved && online)
            OutlinedButton.icon(
              onPressed: () async {
                final s = await pickAndPair(context, _token, preselect: '#code');
                if (s != null) await s.stop();
                _load();
              },
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: Text(tr('Quét mã để xác nhận')),
            ),
        ],
      ),
      if (queue.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(tr('Hàng chờ'), style: const TextStyle(fontWeight: FontWeight.w700)),
        for (var i = 0; i < queue.length; i++)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 13, child: Text('${i + 1}')),
            title: Text(queue[i]),
          ),
      ],
      const SizedBox(height: 16),
      kv(tr('Vị trí'), '${d['location'] ?? ''}'.isEmpty ? tr('(chưa đặt)') : '${d['location']}'),
      kv(
        tr('Mạng'),
        d['trusted'] == true
            ? tr('✓ IP văn phòng')
            : approved
            ? tr('✓ đã xác nhận')
            : tr('⚠ chưa xác nhận'),
      ),
      kv(tr('Thiết bị'), '${d['device'] ?? ''}'),
      kv(tr('Hôm nay'), tr('{0} lần chiếu · {1} người', ['${today['casts'] ?? 0}', '${today['people'] ?? 0}'])),
      const Divider(height: 28),
      Row(
        children: [
          Text(tr('Lịch tự chạy'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const Spacer(),
          if (manager) TextButton.icon(onPressed: _addSchedule, icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm'))),
        ],
      ),
      Text(tr('Khi không họp và không ai chiếu tay, màn hình tự chạy theo lịch (giờ Việt Nam).'), style: TextStyle(color: th.hintColor, fontSize: 12.5)),
      if (schedules.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(tr('Chưa có lịch'), style: TextStyle(color: th.hintColor)),
        ),
      for (final x in schedules)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(switch ('${(x['content'] as Map?)?['type']}') {
            'meeting' => Icons.video_call_rounded,
            'blank' => Icons.tv_off_rounded,
            _ => Icons.slideshow_rounded,
          }),
          title: Text('${x['from']}–${x['to']} · ${x['title']}'),
          subtitle: Text(
            [
              (x['days'] as List? ?? const []).length == 7
                  ? tr('Hằng ngày')
                  : [for (final n in (x['days'] as List? ?? const [])) _days[(n as num).toInt() - 1]].join(', '),
              if ('${x['by_name'] ?? ''}'.isNotEmpty) tr('đặt bởi {0}', ['${x['by_name']}']),
            ].join(' · '),
          ),
          trailing: manager
              ? IconButton(tooltip: tr('Xoá'), onPressed: () => _removeSchedule('${x['id']}'), icon: const Icon(Icons.delete_outline_rounded))
              : null,
        ),
    ];
  }
}

/// Xem trước nội dung đang chiếu: PDF (trang hiện tại) / ảnh khi có quyền xem (người chiếu, quản lý, admin); còn lại là thẻ tên.
class _Preview extends StatelessWidget {
  final Map? content;
  final String status;
  final bool online;
  const _Preview({required this.content, required this.status, required this.online});

  @override
  Widget build(BuildContext context) {
    final c = content;
    final url = c?['url'] == null ? null : CastSession.absolute(kServerUrl, '${c!['url']}');
    Widget inner;
    if (url != null && c!['type'] == 'pdf') {
      inner = ColoredBox(
        color: Colors.white,
        child: PdfDocumentViewBuilder.uri(
          Uri.parse(url),
          builder: (context, doc) => doc == null
              ? const Center(child: CircularProgressIndicator())
              : PdfPageView(document: doc, pageNumber: ((c['page'] as num?)?.toInt() ?? 1).clamp(1, doc.pages.length)),
        ),
      );
    } else if (url != null && c!['type'] == 'image') {
      inner = Image.network(url, fit: BoxFit.contain);
    } else {
      final icon = !online
          ? Icons.tv_off_rounded
          : switch ('${c?['type'] ?? status}') {
              'pdf' => Icons.picture_as_pdf_rounded,
              'image' => Icons.image_rounded,
              'video' => Icons.movie_rounded,
              'mirror' => Icons.screen_share_rounded,
              'pages' => Icons.slideshow_rounded,
              'blank' => Icons.tv_off_rounded,
              'meeting' => Icons.video_call_rounded,
              _ => Icons.qr_code_2_rounded,
            };
      inner = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white70),
            const SizedBox(height: 8),
            Text(
              c != null
                  ? '${c['name']}'
                  : !online
                  ? tr('Màn hình đang tắt')
                  : status == 'meeting'
                  ? tr('Giao diện phòng họp')
                  : tr('Đang hiện mã QR'),
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF222222), width: 6),
        ),
        clipBehavior: Clip.antiAlias,
        child: inner,
      ),
    );
  }
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog();
  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  String _type = 'meeting';
  final _code = TextEditingController(), _title = TextEditingController();
  TimeOfDay _from = const TimeOfDay(hour: 9, minute: 0), _to = const TimeOfDay(hour: 10, minute: 0);
  final _sel = {1, 2, 3, 4, 5};

  String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Thêm lịch tự chạy')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'meeting', label: Text(tr('Tự vào họp')), icon: const Icon(Icons.video_call_rounded)),
                  ButtonSegment(value: 'blank', label: Text(tr('Tắt màn hình')), icon: const Icon(Icons.tv_off_rounded)),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Bộ trình chiếu / Bảng tin tự chạy: có khi app Trình chiếu mới phát hành.'),
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
              if (_type == 'meeting')
                TextField(
                  controller: _code,
                  decoration: InputDecoration(labelText: tr('Mã phòng họp'), hintText: 'abc-defg-hij'),
                ),
              TextField(
                controller: _title,
                decoration: InputDecoration(labelText: tr('Tên (tuỳ chọn)'), hintText: tr('Giao ban sáng')),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      final v = await showTimePicker(context: context, initialTime: _from);
                      if (v != null) setState(() => _from = v);
                    },
                    child: Text(tr('Từ {0}', [_hm(_from)])),
                  ),
                  TextButton(
                    onPressed: () async {
                      final v = await showTimePicker(context: context, initialTime: _to);
                      if (v != null) setState(() => _to = v);
                    },
                    child: Text(tr('đến {0}', [_hm(_to)])),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 1; i <= 7; i++)
                    FilterChip(label: Text(_days[i - 1]), selected: _sel.contains(i), onSelected: (v) => setState(() => v ? _sel.add(i) : _sel.remove(i))),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: () {
            final code = _code.text.trim().toLowerCase();
            if (_type == 'meeting' && !RegExp(r'^[a-z]{3}-?[a-z]{4}-?[a-z]{3}$').hasMatch(code)) return;
            Navigator.pop(context, {
              'days': _sel.toList()..sort(),
              'from': _hm(_from),
              'to': _hm(_to),
              'title': _title.text.trim(),
              'content': _type == 'meeting' ? {'type': 'meeting', 'code': code} : {'type': 'blank'},
            });
          },
          child: Text(tr('Thêm')),
        ),
      ],
    );
  }
}
