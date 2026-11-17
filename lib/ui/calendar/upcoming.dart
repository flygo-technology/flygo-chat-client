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
import 'event_style.dart';
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
    // Lịch hôm nay (bỏ sự kiện đã xong, Sếp 17/11) + các sự kiện những ngày tới.
    final today = [for (final e in todayFrom(d.events, now, d.tz)) if (e.endMs! > now.millisecondsSinceEpoch) e];
    final todayIds = {for (final e in today) e.instanceId};
    final later = [for (final e in list) if (!todayIds.contains(e.instanceId)) e];
    if (widget.compact) {
      // Điện thoại: banner sự kiện gần nhất (kiểu banner Giáng sinh); bấm để mở rộng thành lịch hôm nay + 7 ngày tới.
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        key: const ValueKey('upcoming-events'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _hero(context, list.first, now, d.tz, key: const ValueKey('upcoming-banner'), onTap: _toggle, expandable: true),
          if (_expanded) ...[const SizedBox(height: 8), _list(context, today, later, now, d.tz)],
        ]),
      );
    }
    if (today.isEmpty && later.isEmpty) return const SizedBox.shrink();
    return _card(context, list.isEmpty ? null : list.first, today, later, now, d.tz);
  }

  /// (nhãn đếm ngược gọn, đang diễn ra).
  (String, bool) _pill(CEvent e, DateTime now) {
    final live = e.startMs! <= now.millisecondsSinceEpoch;
    if (!live) return (shortCountdown(DateTime.fromMillisecondsSinceEpoch(e.startMs!).difference(now)), false);
    if (e.allDay) return (tr('Cả ngày'), true);
    return (shortCountdown(DateTime.fromMillisecondsSinceEpoch(e.endMs!).difference(now)), true);
  }

  Widget _hero(BuildContext context, CEvent e, DateTime now, String tz, {Key? key, VoidCallback? onTap, bool expandable = false}) {
    final st = styleOf(e);
    final (pill, live) = _pill(e, now);
    final sub = [if (live) tr('Đang diễn ra'), whenText(e, now, tz), if (e.location.trim().isNotEmpty) e.location.trim()].join(' · ');
    return EventHero(
      key: key,
      icon: st.icon,
      color: st.color,
      title: e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title,
      subtitle: sub,
      pill: pill,
      live: live,
      pillKey: const ValueKey('upcoming-hero-countdown'),
      onTap: onTap ?? () => _open(e),
      trailing: expandable
          ? Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: Colors.white.withValues(alpha: .85))
          : null,
    );
  }

  /// Một dòng: (giờ) + ô biểu tượng màu chuyển + tên / giờ · nơi + nhãn đếm ngược cùng tông màu.
  Widget _row(BuildContext context, CEvent e, DateTime now, String tz, {required bool agenda}) {
    final pal = Pal.of(context);
    final dark = calDark(context);
    final n = now.millisecondsSinceEpoch;
    final done = e.endMs! <= n;
    final st = styleOf(e);
    final g = kEventGradients[st.color] ?? kEventGradients['blue']!;
    String hhmm(int ms) {
      final x = wallOf(ms, tz);
      return '${_two(x.hour)}:${_two(x.minute)}';
    }

    final when = agenda ? (e.allDay ? tr('Cả ngày') : '${hhmm(e.startMs!)}–${hhmm(e.endMs!)}') : whenText(e, now, tz);
    final (pill, live) = _pill(e, now);
    final tint = live ? (dark ? const Color(0xFF6FDC8C) : const Color(0xFF137333)) : (dark ? Color.lerp(g.$1, Colors.white, .35)! : g.$1);
    return InkWell(
      key: ValueKey('upcoming-${e.instanceId}'),
      onTap: () => _open(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          if (agenda)
            SizedBox(
              width: 44,
              child: Text(e.allDay ? tr('Cả ngày') : hhmm(e.startMs!),
                  maxLines: 1, style: TextStyle(fontSize: 12, color: pal.sub, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          EventIconTile(icon: st.icon, color: st.color, dim: done),
          const SizedBox(width: 11),
          Expanded(
            child: Opacity(
              opacity: done ? .55 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.title.isEmpty ? tr('(Không có tiêu đề)') : e.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.text)),
                const SizedBox(height: 2),
                Text([when, if (e.location.trim().isNotEmpty) e.location.trim(), if (done) tr('đã xong')].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: pal.sub)),
                if (!done && e.pendingInvite && !e.notice)
                  Text(tr('Chưa trả lời'), style: TextStyle(fontSize: 11.5, color: pal.sub, fontStyle: FontStyle.italic)),
              ]),
            ),
          ),
          if (!done) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: tint.withValues(alpha: dark ? .2 : .13), borderRadius: BorderRadius.circular(999)),
              child: Text(pill,
                  key: ValueKey('upcoming-countdown-${e.instanceId}'),
                  maxLines: 1,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tint, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ]),
      ),
    );
  }

  /// Các mục: HÔM NAY (vạch bây giờ) rồi 7 NGÀY TỚI (tối đa [UpcomingEvents.max]).
  List<Widget> _sections(BuildContext context, List<CEvent> today, List<CEvent> later, DateTime now, String tz) {
    final pal = Pal.of(context);
    final dark = calDark(context);
    final shown = later.take(widget.max).toList();
    final n = now.millisecondsSinceEpoch;
    final w = wallOf(n, tz);
    final red = dark ? const Color(0xFFFF6B6E) : const Color(0xFFE5484D);
    Widget section(String text) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: pal.sub)),
        );
    final nowAt = today.indexWhere((e) => !e.allDay && e.startMs! > n);
    final nowLine = Padding(
      key: const ValueKey('upcoming-now'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text('${_two(w.hour)}:${_two(w.minute)}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: red)),
        const SizedBox(width: 6),
        Expanded(child: Container(height: 1.5, color: red)),
      ]),
    );
    final hasTimed = today.any((e) => !e.allDay);
    Widget div() => Divider(height: 1, thickness: .6, color: pal.divider);
    return [
      if (today.isNotEmpty) ...[
        section('${tr('Hôm nay')} · ${tr(_weekdays[w.weekday - 1])} ${w.day}/${w.month}'),
        for (var i = 0; i < today.length; i++) ...[
          if (i == nowAt) nowLine else if (i > 0) div(),
          _row(context, today[i], now, tz, agenda: true),
        ],
        if (hasTimed && nowAt < 0) nowLine,
      ],
      if (shown.isNotEmpty) ...[
        section(tr('{0} ngày tới', [kUpcomingWindow.inDays])),
        for (var i = 0; i < shown.length; i++) ...[if (i > 0) div(), _row(context, shown[i], now, tz, agenda: false)],
      ],
      if (later.length > shown.length)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('+{0} sự kiện', [later.length - shown.length]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
        ),
    ];
  }

  Widget _openLink(BuildContext context) => InkWell(
        key: const ValueKey('upcoming-open-calendar'),
        borderRadius: BorderRadius.circular(8),
        onTap: _openCalendar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(tr('Mở Lịch'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: calAccent(context))),
        ),
      );

  /// Điện thoại, khi mở rộng: thẻ danh sách dưới banner; chân thẻ: Mở Lịch + ˄ thu gọn.
  Widget _list(BuildContext context, List<CEvent> today, List<CEvent> later, DateTime now, String tz) {
    final pal = Pal.of(context);
    final canOpen = _data?.app != null || widget.onOpenCalendar != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: pal.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(right: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _sections(context, today, later, now, tz))),
        Row(children: [
          if (canOpen) _openLink(context),
          const Spacer(),
          IconButton(
            key: const ValueKey('upcoming-collapse'),
            tooltip: tr('Thu gọn'),
            visualDensity: VisualDensity.compact,
            onPressed: _toggle,
            icon: Icon(Icons.expand_less_rounded, color: pal.sub),
          ),
        ]),
      ]),
    );
  }

  /// Máy tính: thẻ "Sắp diễn ra": banner sự kiện gần nhất + lịch hôm nay + 7 ngày tới.
  Widget _card(BuildContext context, CEvent? next, List<CEvent> today, List<CEvent> later, DateTime now, String tz) {
    final pal = Pal.of(context);
    final canOpen = _data?.app != null || widget.onOpenCalendar != null;
    return Padding(
      key: const ValueKey('upcoming-events'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: pal.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.event_rounded, size: 18, color: calAccent(context)),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('Sắp diễn ra'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: pal.text))),
            if (canOpen) _openLink(context) else const SizedBox(height: 36),
          ]),
          if (next != null) ...[const SizedBox(height: 4), _hero(context, next, now, tz)],
          ..._sections(context, today, later, now, tz),
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
}
