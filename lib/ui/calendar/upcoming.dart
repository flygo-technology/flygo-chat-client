// Lịch: sự kiện sắp tới trong 7 ngày, đếm ngược trực tiếp ("còn 2 giờ 15 phút"). Máy tính: dưới thẻ người dùng ở Trang
// chủ (tối đa 3 sự kiện). Điện thoại: dải gọn ở đầu Trang chủ (sự kiện gần nhất + số sự kiện còn lại). Bấm → mở sự kiện
// trong Lịch. Ẩn khi người dùng không được dùng Lịch, không có sự kiện nào, hoặc tải lỗi. Tải lại mỗi 5 phút, khi app
// quay lại, khi danh sách app đổi và sau khi đóng Lịch. Danh sách đã tải giữ trong bộ nhớ (theo máy chủ + người dùng) và
// lưu ra đĩa: khối được dựng lại (cuộn ra khỏi màn hình rồi quay lại, mở lại app) hiện ngay, không ẩn rồi mới hiện;
// đang tải lại thì vẫn giữ danh sách cũ, chỉ thay khi có kết quả mới.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../config.dart' show serverKey;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'api.dart';
import 'calendar_page.dart' show openCalendar;
import 'look.dart';
import 'model.dart';
import 'tz.dart';

const kUpcomingWindow = Duration(days: 7);

/// Dữ liệu đã tải: app Lịch, các lần xảy ra trong khoảng hôm qua → 8 ngày tới, múi giờ của người dùng trong Lịch.
class UpcomingData {
  const UpcomingData({this.app, required this.events, this.tz = kDefaultTz});
  final MiniApp? app;
  final List<CEvent> events;
  final String tz;

  Map<String, dynamic> toJson() => {if (app != null) 'app': app!.toJson(), 'events': [for (final e in events) e.toJson()], 'tz': tz};
  static UpcomingData fromJson(Map j) => UpcomingData(
        app: j['app'] is Map ? MiniApp.fromJson(j['app'] as Map) : null,
        events: [for (final e in j['events'] as List? ?? const []) CEvent.fromJson(e as Map)],
        tz: '${j['tz'] ?? kDefaultTz}',
      );
}

// ------------------------------------------------------------ bộ nhớ đệm
// key → dữ liệu mới nhất (null = đã biết là không dùng được Lịch). Không có key = chưa biết gì.
final _mem = <String, UpcomingData?>{};
final _inflight = <String, Future<void>>{};

/// Kiểm thử: tắt lưu đĩa.
@visibleForTesting
bool upcomingDiskCache = true;

/// Kiểm thử: xoá bộ nhớ đệm trong bộ nhớ.
@visibleForTesting
void upcomingResetCache() {
  _UpcomingEventsState._expanded = false;
  _mem.clear();
  _inflight.clear();
}

Future<File?> _diskFile(String key) async {
  if (!upcomingDiskCache) return null;
  final dir = await getApplicationSupportDirectory();
  final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  return File('${dir.path}${Platform.pathSeparator}calendar_upcoming_$safe.json');
}

Future<void> _readDisk(String key) async {
  try {
    final f = await _diskFile(key);
    if (f == null || !f.existsSync() || _mem.containsKey(key)) return;
    final j = jsonDecode(await f.readAsString());
    if (j is Map && !_mem.containsKey(key)) _mem[key] = UpcomingData.fromJson(j);
  } catch (e) {
    debugPrint('[calendar] bộ nhớ đệm sự kiện sắp tới hỏng, bỏ qua: $e');
  }
}

Future<void> _writeDisk(String key, UpcomingData? d) async {
  try {
    final f = await _diskFile(key);
    if (f == null) return;
    if (d == null) {
      if (f.existsSync()) await f.delete();
      return;
    }
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(d.toJson()));
    await tmp.rename(f.path);
  } catch (e) {
    debugPrint('[calendar] không lưu được sự kiện sắp tới: $e');
  }
}

final _client = http.Client();

Future<UpcomingData?> _load(String token) async {
  final apps = await MiniApps.list(token);
  final app = apps.where((a) => a.id == kCalApp).firstOrNull;
  if (app == null) return null;
  final id = await FlygoId.current(token);
  if (id == null) return null;
  final api = CalApi(base: app.baseUrl, id: id, client: _client);
  final now = DateTime.now();
  // Ngày theo giờ máy, nới một ngày mỗi đầu để múi giờ của Lịch khác giờ máy vẫn đủ.
  final (me, events) = await (
    api.me(),
    api.events(from: fmtDate(DateTime.utc(now.year, now.month, now.day - 1)), to: fmtDate(DateTime.utc(now.year, now.month, now.day + 8))),
  ).wait;
  final tz = '${(me['settings'] as Map?)?['tz'] ?? kDefaultTz}';
  return UpcomingData(app: app, events: events, tz: tz.isEmpty ? kDefaultTz : tz);
}

/// Nguồn dữ liệu (kiểm thử thay được). null = không dùng được Lịch.
@visibleForTesting
Future<UpcomingData?> Function(String token) upcomingLoader = _load;

/// Các sự kiện của mình (mình tổ chức hoặc được mời, chưa từ chối) chưa kết thúc và bắt đầu trong [within] tới.
/// Bỏ ngày lễ, lịch người khác chỉ đăng ký xem, sự kiện chỉ thấy bận, sự kiện đã huỷ.
List<CEvent> upcomingFrom(List<CEvent> events, DateTime now, {Duration within = kUpcomingWindow}) {
  final n = now.millisecondsSinceEpoch, until = now.add(within).millisecondsSinceEpoch;
  final seen = <String>{};
  final out = [
    for (final e in events)
      if (!e.cancelled && !e.busyOnly && e.myRsvp != null && !e.declined && e.startMs != null && e.endMs != null && e.endMs! > n && e.startMs! < until && seen.add(e.instanceId))
        e,
  ];
  // Đang diễn ra và sắp bắt đầu trước; cả ngày xếp sau sự kiện có giờ cùng lúc bắt đầu.
  out.sort((a, b) => a.startMs != b.startMs ? a.startMs!.compareTo(b.startMs!) : (a.allDay ? 1 : 0) - (b.allDay ? 1 : 0));
  return out;
}

/// Sự kiện của mình trong hôm nay (theo giờ [tz]), kể cả đã xong: bắt đầu hôm nay hoặc kéo dài qua hôm nay.
/// Cùng bộ lọc như [upcomingFrom] (bỏ ngày lễ, chỉ xem, bận, huỷ, đã từ chối), xếp theo giờ bắt đầu, cả ngày lên đầu.
List<CEvent> todayFrom(List<CEvent> events, DateTime now, String tz) {
  final today = dayOf(wallOf(now.millisecondsSinceEpoch, tz));
  final from = msOfWall(today, tz), to = msOfWall(addDays(today, 1), tz);
  final seen = <String>{};
  final out = [
    for (final e in events)
      if (!e.cancelled && !e.busyOnly && e.myRsvp != null && !e.declined && e.startMs != null && e.endMs != null && e.startMs! < to && e.endMs! > from && seen.add(e.instanceId))
        e,
  ];
  out.sort((a, b) => a.allDay != b.allDay ? (a.allDay ? -1 : 1) : a.startMs!.compareTo(b.startMs!));
  return out;
}

/// "còn 2 ngày 3 giờ", "còn 2 giờ 15 phút", "còn 15 phút", "còn 40 giây" (phút làm tròn lên).
String countdownText(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return tr('còn {0} giây', [s < 1 ? 1 : s]);
  final m = (s + 59) ~/ 60;
  if (m < 60) return tr('còn {0} phút', [m]);
  final h = m ~/ 60, mm = m % 60;
  if (h < 24) return mm == 0 ? tr('còn {0} giờ', [h]) : tr('còn {0} giờ {1} phút', [h, mm]);
  final days = h ~/ 24, hh = h % 24;
  return hh == 0 ? tr('còn {0} ngày', [days]) : tr('còn {0} ngày {1} giờ', [days, hh]);
}

String _two(int n) => n.toString().padLeft(2, '0');
const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

/// "Hôm nay 14:30–16:00", "Ngày mai · Cả ngày", "T4 18/11 09:00–10:00" theo giờ [tz].
String whenText(CEvent e, DateTime now, String tz) {
  final s = wallOf(e.startMs!, tz), en = wallOf(e.endMs!, tz), today = dayOf(wallOf(now.millisecondsSinceEpoch, tz));
  final diff = daysBetween(today, s);
  // Đã bắt đầu từ hôm trước (cả ngày nhiều ngày, sự kiện qua đêm): tính là hôm nay.
  final day = diff <= 0
      ? tr('Hôm nay')
      : diff == 1
          ? tr('Ngày mai')
          : '${tr(_weekdays[s.weekday - 1])} ${s.day}/${s.month}';
  if (e.allDay) return '$day · ${tr('Cả ngày')}';
  final end = dayOf(en) == dayOf(s) ? '${_two(en.hour)}:${_two(en.minute)}' : '${en.day}/${en.month} ${_two(en.hour)}:${_two(en.minute)}';
  return '$day ${_two(s.hour)}:${_two(s.minute)}–$end';
}

class UpcomingEvents extends StatefulWidget {
  const UpcomingEvents({super.key, this.compact = false, this.max = 3, this.clock, this.onOpen, this.onOpenCalendar});

  /// Điện thoại: một dòng gọn ở đầu trang.
  final bool compact;
  final int max;

  /// Kiểm thử: đồng hồ, và việc mở sự kiện thay cho mở Lịch thật.
  final DateTime Function()? clock;
  final void Function(CEvent e)? onOpen;
  final VoidCallback? onOpenCalendar;

  @override
  State<UpcomingEvents> createState() => _UpcomingEventsState();
}

class _UpcomingEventsState extends State<UpcomingEvents> with WidgetsBindingObserver {
  // Điện thoại: đang mở rộng hay thu gọn. Tĩnh để giữ nguyên khi khối bị dựng lại (cuộn ra rồi vào).
  static bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);
  UpcomingData? _data;
  Timer? _tick, _refresh;
  late final String _key;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _key = '$serverKey|${context.read<AppState>().me?.id ?? ''}';
    // Dựng lại (cuộn ra rồi vào, đổi trang): hiện ngay danh sách đã có, không chờ tải.
    _data = _mem[_key];
    _sync();
    WidgetsBinding.instance.addObserver(this);
    MiniApps.changed.addListener(_reload);
    if (_mem.containsKey(_key)) {
      _reload();
    } else {
      // Mở app: hiện bản lưu trên đĩa trước, rồi mới tải mới.
      _readDisk(_key).whenComplete(() {
        if (!mounted) return;
        if (_mem.containsKey(_key) && _data == null) setState(() => _data = _mem[_key]);
        _sync();
        _reload();
      });
    }
    _refresh = Timer.periodic(const Duration(minutes: 5), (_) => _reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MiniApps.changed.removeListener(_reload);
    _tick?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final key = _key, token = context.read<AppState>().token;
    // Một lần tải cho mỗi key, dù có nhiều khối (hoặc khối vừa dựng lại) cùng gọi.
    await (_inflight[key] ??= () async {
      try {
        final d = await upcomingLoader(token);
        _mem[key] = d;
        unawaited(_writeDisk(key, d));
      } catch (e) {
        // Lỗi mạng / máy chủ: giữ danh sách cũ (nếu có), lần sau tải lại.
        debugPrint('[calendar] sự kiện sắp tới: $e');
      } finally {
        _inflight.remove(key);
      }
    }());
    if (!mounted) return;
    if (_mem.containsKey(key) && !identical(_mem[key], _data)) setState(() => _data = _mem[key]);
    _sync();
  }

  /// Đồng hồ đếm ngược chỉ chạy khi đang có sự kiện để hiện.
  void _sync() {
    final any = _data != null && upcomingFrom(_data!.events, _now).isNotEmpty;
    if (any && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (_data == null || upcomingFrom(_data!.events, _now).isEmpty) {
          _tick?.cancel();
          _tick = null;
        }
      });
    } else if (!any) {
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _open(CEvent e) async {
    if (widget.onOpen != null) return widget.onOpen!(e);
    final app = _data?.app;
    if (app == null) return;
    await openCalendar(context, app, eventId: e.id, rid: e.rid);
    // Có thể vừa sửa / xoá / trả lời trong Lịch.
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();
    final now = _now;
    final list = upcomingFrom(d.events, now);
    // Lịch hôm nay (kể cả đã xong) + các sự kiện những ngày tới.
    final today = todayFrom(d.events, now, d.tz);
    final todayIds = {for (final e in today) e.instanceId};
    final later = [for (final e in list) if (!todayIds.contains(e.instanceId)) e];
    // Điện thoại: dải một dòng (thu gọn); bấm để mở rộng thành lịch hôm nay + 7 ngày tới, bấm ˄ để thu lại.
    if (widget.compact) {
      if (list.isEmpty) return const SizedBox.shrink();
      if (!_expanded) return _banner(context, list, now, d.tz);
    }
    if (today.isEmpty && later.isEmpty) return const SizedBox.shrink();
    return _card(context, today, later, now, d.tz);
  }

  (String, bool) _status(CEvent e, DateTime now) {
    final live = e.startMs! <= now.millisecondsSinceEpoch;
    if (!live) return (countdownText(DateTime.fromMillisecondsSinceEpoch(e.startMs!).difference(now)), false);
    if (e.allDay) return (tr('Đang diễn ra'), true);
    return ('${tr('Đang diễn ra')} · ${countdownText(DateTime.fromMillisecondsSinceEpoch(e.endMs!).difference(now))}', true);
  }

  Widget _card(BuildContext context, List<CEvent> today, List<CEvent> later, DateTime now, String tz) {
    final pal = Pal.of(context);
    final dark = calDark(context);
    final shown = later.take(widget.max).toList();
    final n = now.millisecondsSinceEpoch;
    final w = wallOf(n, tz);
    String hhmm(int ms) {
      final x = wallOf(ms, tz);
      return '${_two(x.hour)}:${_two(x.minute)}';
    }

    Widget section(String text, {double top = 10}) => Padding(
          padding: EdgeInsets.fromLTRB(14, top, 14, 4),
          child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: pal.sub)),
        );
    Widget item(CEvent e, {required bool agenda}) {
      final done = e.endMs! <= n;
      final c = eventColor(e.color ?? e.calendarColor, dark);
      final when = agenda ? (e.allDay ? tr('Cả ngày') : '${hhmm(e.startMs!)}–${hhmm(e.endMs!)}') : whenText(e, now, tz);
      return InkWell(
        key: ValueKey('upcoming-${e.instanceId}'),
        onTap: () => _open(e),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (agenda)
              SizedBox(
                width: 46,
                child: Text(e.allDay ? tr('Cả ngày') : hhmm(e.startMs!),
                    maxLines: 1,
                    style: TextStyle(fontSize: 12.5, color: pal.sub, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            Container(
              width: 4,
              height: done ? 32 : 40,
              margin: const EdgeInsets.only(top: 2, right: 10),
              decoration: BoxDecoration(color: done ? c.withValues(alpha: .4) : c, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: done ? FontWeight.w500 : FontWeight.w600, color: done ? pal.sub : pal.text)),
                const SizedBox(height: 2),
                Text([when, if (e.location.trim().isNotEmpty) e.location.trim(), if (done) tr('đã xong')].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub)),
                if (!done) ...[const SizedBox(height: 4), _chip(context, e, now)],
              ]),
            ),
          ]),
        ),
      );
    }

    // Vạch "bây giờ" trong lịch hôm nay: trước sự kiện đầu tiên chưa bắt đầu (sau các sự kiện đã xong / đang diễn ra).
    final red = dark ? const Color(0xFFFF6B6E) : const Color(0xFFE5484D);
    final nowAt = today.indexWhere((e) => !e.allDay && e.startMs! > n);
    final nowLine = Padding(
      key: const ValueKey('upcoming-now'),
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: Row(children: [
        Text('${_two(w.hour)}:${_two(w.minute)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: red)),
        const SizedBox(width: 6),
        Expanded(child: Container(height: 1.5, color: red)),
      ]),
    );
    final hasTimed = today.any((e) => !e.allDay);
    return Padding(
      key: const ValueKey('upcoming-events'),
      padding: EdgeInsets.fromLTRB(16, widget.compact ? 10 : 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.divider)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 0),
            child: Row(children: [
              Icon(Icons.event_rounded, size: 18, color: calAccent(context)),
              const SizedBox(width: 8),
              Expanded(child: Text(tr('Sắp diễn ra'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text))),
              if (_data?.app != null || widget.onOpenCalendar != null)
                InkWell(
                  key: const ValueKey('upcoming-open-calendar'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: _openCalendar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text(tr('Mở Lịch'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: calAccent(context))),
                  ),
                ),
              if (widget.compact)
                IconButton(
                  key: const ValueKey('upcoming-collapse'),
                  tooltip: tr('Thu gọn'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _toggle,
                  icon: Icon(Icons.expand_less_rounded, color: pal.sub),
                ),
            ]),
          ),
          if (today.isNotEmpty) ...[
            section('${tr('Hôm nay')} · ${tr(_weekdays[w.weekday - 1])} ${w.day}/${w.month}', top: 2),
            for (var i = 0; i < today.length; i++) ...[
              if (i == nowAt) nowLine,
              item(today[i], agenda: true),
            ],
            if (hasTimed && nowAt < 0) nowLine,
          ],
          if (shown.isNotEmpty) ...[
            section(tr('{0} ngày tới', [kUpcomingWindow.inDays]), top: today.isEmpty ? 2 : 10),
            for (final e in shown) item(e, agenda: false),
          ],
          if (later.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Text(tr('+{0} sự kiện', [later.length - shown.length]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
            ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  Future<void> _openCalendar() async {
    if (widget.onOpenCalendar != null) return widget.onOpenCalendar!();
    final app = _data?.app;
    if (app == null) return;
    await openCalendar(context, app);
    unawaited(_reload());
  }

  Widget _chip(BuildContext context, CEvent e, DateTime now) {
    final (text, live) = _status(e, now);
    final dark = calDark(context);
    final fg = live ? (dark ? const Color(0xFF6FDC8C) : const Color(0xFF137333)) : calAccent(context);
    final bg = live ? (dark ? const Color(0xFF173A22) : const Color(0xFFE6F4EA)) : calAccentSoft(context);
    return Row(children: [
      Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Text(text,
              key: ValueKey('upcoming-countdown-${e.instanceId}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
      ),
      if (e.pendingInvite && !e.notice) ...[
        const SizedBox(width: 6),
        Text(tr('Chưa trả lời'), style: TextStyle(fontSize: 12, color: Pal.of(context).sub)),
      ],
    ]);
  }

  Widget _banner(BuildContext context, List<CEvent> list, DateTime now, String tz) {
    // Một ô nhỏ: tên sự kiện gần nhất, dòng dưới là thời gian còn lại (Sếp, 2026-11-17). Bấm: mở rộng lịch.
    final pal = Pal.of(context);
    final e = list.first;
    final (text, live) = _status(e, now);
    final dark = calDark(context);
    final accent = live ? (dark ? const Color(0xFF6FDC8C) : const Color(0xFF137333)) : calAccent(context);
    return Padding(
      key: const ValueKey('upcoming-events'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        color: live ? (dark ? const Color(0xFF173A22) : const Color(0xFFE6F4EA)) : calAccentSoft(context),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('upcoming-banner'),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.text)),
              const SizedBox(height: 1),
              Text(text,
                  key: ValueKey('upcoming-countdown-${e.instanceId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: accent, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
  }

}
