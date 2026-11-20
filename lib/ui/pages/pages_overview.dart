import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calls/call_service.dart';
import '../../config.dart' show isDesktop;
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart' show Avatar;
import '../meet/meet_home.dart' show meetToast;
import 'page_thumb.dart';
import 'page_types.dart';
import 'system_pages.dart';
import 'pages_api.dart';
import 'pages_sheet.dart' show fmtLeft;

// Tab "▦ Tất cả" của bảng kéo lên Trang họp: mọi trang của mọi người trong cuộc họp, mỗi người một hàng cuộn ngang. Người
// khác chỉ hiện trang công khai; hàng của mình hiện đủ (theo thứ tự tạo, cũng là thứ tự tự chạy), cuối hàng có thẻ ＋.
// Thứ tự hàng: người đang trình chiếu → hàng đợi → mình → còn lại A→Z (chưa ai trình chiếu thì mình ở trên cùng).
// Chủ trì thấy số trang riêng của từng người (không thấy nội dung) và trao lượt. Chạm thẻ: xem trang (trong bảng);
// nhấn giữ / chuột phải thẻ của mình: sửa, công khai, lên sân khấu, xoá.

const _cardBg = Color(0xFF2A2E35);
const _line = Color(0xFF363B43);
const _sub = Color(0xFF9AA3AD);
const _acc = Color(0xFF2BB3A3);
const _gold = Color(0xFFFFD36B);
final _compact = TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32));

/// Một hàng: một người và các trang của họ.
class _Row {
  final String uid;
  String name;
  final List<MeetPage> pages = [];
  Map<String, dynamic>? count; // chủ trì: {pages, private, seconds}
  _Row(this.uid, this.name);
}

class PagesOverview extends StatefulWidget {
  final CallService call;
  /// Xem một trang (bảng chuyển sang chế độ xem trang).
  final void Function(String id) onView;
  /// Soạn trang của mình.
  final void Function(String id) onEdit;
  /// Thêm trang mới.
  final VoidCallback onNew;
  const PagesOverview({super.key, required this.call, required this.onView, required this.onEdit, required this.onNew});
  @override
  State<PagesOverview> createState() => _PagesOverviewState();
}

class _PagesOverviewState extends State<PagesOverview> {
  late final api = PagesApi(widget.call);
  List<MeetPage> _pages = const [];
  Map<String, Map<String, dynamic>> _counts = const {};
  String? _err;
  bool _loaded = false;
  StreamSubscription? _fx;
  Timer? _tick, _debounce;

  CallService get call => widget.call;

  @override
  void initState() {
    super.initState();
    _load();
    call.addListener(_changed);
    _fx = call.fxEvents.stream.listen((m) {
      if (m['t'] != 'fx_page') return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), _load);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (call.roomStage?['ends_at'] ?? 0) != 0) setState(() {});
    });
  }

  @override
  void dispose() {
    call.removeListener(_changed);
    _fx?.cancel();
    _tick?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final (p, c) = await api.listAll();
      if (mounted) {
        setState(() {
          _pages = p;
          _counts = c;
          _err = null;
          _loaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _toast(Future<String?> f) async {
    final e = await f;
    if (e != null && mounted) meetToast(context, e);
  }

  List<_Row> _rows(AppState app) {
    final me = call.myId();
    final st = call.roomStage ?? const {};
    final pres = '${st['presenter'] ?? ''}';
    final queue = [for (final x in (st['queue'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final rows = <String, _Row>{};
    String nameOf(String uid, [String fb = '']) {
      final n = app.users[uid]?.displayName ?? '';
      return n.isNotEmpty ? n : fb;
    }

    _Row row(String uid, [String fb = '']) => rows.putIfAbsent(uid, () => _Row(uid, nameOf(uid, fb)));
    for (final p in _pages) {
      final r = row(p.owner, p.ownerName);
      if (p.owner == me || p.public || st['page'] == p.id) r.pages.add(p);
    }
    for (final e in _counts.entries) {
      row(e.key, '${e.value['name'] ?? ''}').count = e.value;
    }
    if (pres.isNotEmpty) row(pres, '${st['presenter_name'] ?? ''}');
    for (final q in queue) {
      row('${q['id']}', '${q['name'] ?? ''}');
    }
    row(me, app.me?.displayName ?? tr('Bạn'));
    final qIds = [for (final q in queue) '${q['id']}'];
    int rank(_Row r) {
      if (r.uid == pres) return 0;
      final qi = qIds.indexOf(r.uid);
      if (qi >= 0) return 1 + qi;
      if (r.uid == me) return pres.isEmpty ? -1 : 100;
      return 200;
    }

    final out = rows.values.toList()
      ..sort((a, b) {
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = isDesktop;
    final rows = _rows(app);
    final me = call.myId();
    final shown = rows.where((r) => r.pages.isNotEmpty || r.count != null || r.uid == me || r.uid == call.roomStage?['presenter']).toList();
    final shownIds = {for (final r in rows) r.uid};
    // Người trong cuộc họp chưa có trang nào hiện được.
    final empty = <String>{
      for (final r in rows)
        if (!shown.contains(r)) r.name,
      for (final p in call.participants)
          if (p.userId.isNotEmpty && !shownIds.contains(p.userId) && !p.userId.contains(':')) app.users[p.userId]?.displayName ?? '',
    }..removeWhere((x) => x.isEmpty);
    const pad = 12.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sysRow(wide, pad),
      if (!_loaded)
        Padding(padding: const EdgeInsets.all(24), child: Center(child: _err != null ? Text(_err!, style: const TextStyle(color: Colors.white70)) : const CircularProgressIndicator()))
      else ...[
        for (final r in shown) _row(r, wide, pad),
        if (empty.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(pad, 2, pad, 0),
            child: Text(
              call.canModerate ? tr('Chưa chuẩn bị trang: {0}', [empty.join(', ')]) : tr('Chưa có trang công khai: {0}', [empty.join(', ')]),
              style: const TextStyle(color: _sub, fontSize: 12),
            ),
          ),
      ],
    ]);
  }

  /// Hàng "Hệ thống": bố cục video của cả phòng và màn hình chờ lượt (người trình chiếu / chủ trì đưa lên sân khấu).
  Widget _sysRow(bool wide, double pad) {
    final st = call.roomStage ?? const {};
    final can = st['presenter'] == call.myId() || call.canModerate || ('${st['presenter'] ?? ''}'.isEmpty && st['locked'] != true);
    final w = wide ? 150.0 : 104.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 6),
          child: Text(tr('Hệ thống'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        SizedBox(
          height: wide ? 118 : 92,
          child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: pad), children: [
            for (final p in sysPages)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: can ? () => _toast(call.stageAct('show', {'page': p.id})) : () => meetToast(context, tr('Chỉ người trình chiếu / chủ trì chọn bố cục sân khấu')),
                    onLongPress: call.canModerate ? sysPageEditor(context, call, p.id, canCompany: _sysAdmin) : null,
                    onSecondaryTap: call.canModerate ? sysPageEditor(context, call, p.id, canCompany: _sysAdmin) : null,
                    child: Container(
                      width: w,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: st['page'] == p.id ? _acc : Colors.transparent)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(
                          child: Container(
                            color: p.color.withValues(alpha: .22),
                            child: Stack(children: [
                              Center(child: Icon(p.icon, color: p.color, size: wide ? 30 : 24)),
                              if (call.canModerate && sysPageEditor(context, call, p.id) != null)
                                Positioned(
                                  right: 2,
                                  top: 2,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: tr('Soạn trang này'),
                                    icon: const Icon(Icons.tune_rounded, size: 16, color: Colors.white70),
                                    onPressed: sysPageEditor(context, call, p.id, canCompany: _sysAdmin),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(7, 5, 7, 6),
                          child: Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: wide ? 12.5 : 11.5, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  bool get _sysAdmin => '${context.read<AppState>().me?.raw['roles'] ?? ''}'.contains('system_admin');

  Widget _pill(String text, Color fg, Color bg) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _row(_Row r, bool wide, double pad) {
    final st = call.roomStage ?? const {};
    final me = call.myId();
    final mine = r.uid == me;
    final pres = st['presenter'] == r.uid;
    final qi = [for (final x in (st['queue'] as List? ?? const [])) '${(x as Map)['id']}'].indexOf(r.uid);
    final ends = (st['ends_at'] as num?)?.toInt() ?? 0;
    final left = ends == 0 ? 0 : ends - DateTime.now().millisecondsSinceEpoch;
    final host = call.canModerate;
    final c = r.count;
    final private = mine ? r.pages.where((p) => !p.public).length : ((c?['private'] as num?)?.toInt() ?? 0);
    final total = mine ? r.pages.length : ((c?['pages'] as num?)?.toInt() ?? r.pages.length);
    final secs = mine || c == null ? r.pages.fold<int>(0, (a, p) => a + p.seconds) : (c['seconds'] as num?)?.toInt() ?? 0;
    final info = [
      if (total > 0) tr('{0} trang', [total]),
      if (private > 0) tr('{0} riêng', [private]),
      if (secs > 0) fmtLeft(secs * 1000),
    ].join(' · ');
    final h = wide ? 150.0 : 104.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 6),
          child: Row(children: [
            Avatar(userId: r.uid, name: r.name, size: 24, status: false),
            const SizedBox(width: 8),
            // Tên + nhãn lượt + số trang xuống dòng khi hẹp (panel máy tính, điện thoại nhỏ), không tràn.
            Expanded(
              child: Wrap(spacing: 0, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(mine ? tr('{0} (bạn)', [r.name]) : r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                if (pres) _pill(left > 0 ? tr('● đang chiếu · còn {0}', [fmtLeft(left)]) : tr('● đang chiếu'), const Color(0xFFFFB4AE), const Color(0xFF3A1F1F)),
                if (qi >= 0) _pill(tr('{0} chờ lượt', ['${qi + 1}']), _gold, const Color(0xFF3D3010)),
                if (info.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 8), child: Text(info, style: const TextStyle(color: _sub, fontSize: 11.5))),
              ]),
            ),
            if (host && pres) TextButton(style: _compact, onPressed: () => _toast(call.stageAct('release')), child: Text(tr('Kết thúc lượt'))),
            if (host && !pres && !mine && total > 0) TextButton(style: _compact, onPressed: () => _toast(call.stageAct('grant', {'user': r.uid, 'name': r.name})), child: Text(tr('Trao lượt'))),
          ]),
        ),
        SizedBox(
          height: h,
          // Dựng dần khi cuộn: chỉ thẻ đang hiện mới tải ảnh xem trước.
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemCount: r.pages.length + ((!mine && private > 0 && host) || mine ? 1 : 0),
            itemBuilder: (context, i) => i < r.pages.length
                ? KeyedSubtree(key: ValueKey(r.pages[i].id), child: _card(r.pages[i], mine: mine, wide: wide))
                : mine
                    ? _addCard(wide)
                    : _privateCard(private, wide),
          ),
        ),
      ]),
    );
  }

  Widget _badge(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(5)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 10, fontFeatures: [FontFeature.tabularFigures()])),
      );

  Widget _card(MeetPage p, {required bool mine, required bool wide}) {
    final s = pageTypeOf(p.type);
    final st = call.roomStage ?? const {};
    final live = st['page'] == p.id;
    final pr = call.roomPresent;
    final w = wide ? 176.0 : 112.0;
    final sub = [s?.label ?? p.type, if (p.file?['pages'] != null && p.file!['pages'] != 0) tr('{0} trang', [p.file!['pages']])].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onView(p.id),
          onLongPress: mine || call.canModerate ? () => _menu(p) : null,
          onSecondaryTap: mine || call.canModerate ? () => _menu(p) : null,
          child: Container(
            width: w,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: live ? _acc : Colors.transparent)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  PageThumb(call: call, page: p),
                  // Loại trang (góc trái), công khai / riêng của mình (góc phải), trang đang chiếu, thời lượng.
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(6)),
                      child: Icon(s?.icon ?? Icons.help_outline, color: s?.color ?? Colors.grey, size: 12),
                    ),
                  ),
                  if (mine)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(6)),
                        child: Icon(p.public ? Icons.public_rounded : Icons.lock_rounded, size: 12, color: Colors.white70),
                      ),
                    ),
                  if (live && pr != null && pr['page_id'] == p.id) Positioned(left: 4, bottom: 3, child: _badge('${pr['page']}/${pr['pages']}')),
                  if (p.seconds > 0) Positioned(right: 4, bottom: 3, child: _badge(fmtLeft(p.seconds * 1000))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 5, 7, 0),
                child: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: wide ? 12.5 : 11.5, fontWeight: FontWeight.w600)),
              ),
              if (wide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(7, 1, 7, 0),
                  child: Text(live ? tr('đang chiếu') : sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _sub, fontSize: 11)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _privateCard(int n, bool wide) => Container(
        width: wide ? 176 : 112,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(color: _cardBg.withValues(alpha: .6), borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline_rounded, color: _sub),
          const SizedBox(height: 4),
          Text(tr('{0} trang chưa công khai', [n]), textAlign: TextAlign.center, style: const TextStyle(color: _sub, fontSize: 11.5)),
        ]),
      );

  Widget _addCard(bool wide) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onNew,
          child: Container(
            width: wide ? 176 : 112,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_rounded, color: _acc, size: 26),
              Text(tr('Thêm trang'), style: const TextStyle(color: _sub, fontSize: 11.5)),
            ]),
          ),
        ),
      );

  Future<void> _menu(MeetPage p) => showPageMenu(context, call, p, onEdit: () => widget.onEdit(p.id), reload: _load);
}

/// Menu của một trang (nhấn giữ / chuột phải thẻ, hoặc ⋯ trên trang): chủ trang có Sửa, Chiếu, Công khai / riêng, Xoá;
/// chủ trì (trang người khác) có Chiếu. Bấm (không giữ) là tương tác với trang: người xem trả lời / hỏi / ghi, chủ trang soạn.
Future<void> showPageMenu(BuildContext context, CallService call, MeetPage p, {required VoidCallback onEdit, required Future<void> Function() reload}) async {
  final api = PagesApi(call);
  final mine = p.owner == call.myId();
  final st = call.roomStage ?? const {};
  final myTurn = st['presenter'] == call.myId();
  final canShow = myTurn || call.canModerate || '${st['presenter'] ?? ''}'.isEmpty;
  if (!mine && !call.canModerate) return;
  final s = pageTypeOf(p.type);
  final a = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF2B2E33),
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text([p.title, s?.label ?? p.type, if (!mine) p.ownerName, p.public ? tr('công khai') : tr('riêng')].join(' · '), maxLines: 2, style: const TextStyle(color: _sub, fontSize: 12.5)),
        ),
        if (mine) ListTile(leading: const Icon(Icons.edit_outlined, color: Colors.white), title: Text(tr('Sửa'), style: const TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'edit')),
        ListTile(
          leading: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF7FD8CC)),
          title: Text(canShow ? tr('Chiếu lên sân khấu') : tr('Xin lượt và chiếu'), style: const TextStyle(color: Color(0xFF7FD8CC), fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pop(ctx, 'show'),
        ),
        if (mine)
          SwitchListTile(
            secondary: const Icon(Icons.public_rounded, color: Colors.white),
            value: p.public,
            title: Text(tr('Công khai trong cuộc họp'), style: const TextStyle(color: Colors.white)),
            onChanged: (_) => Navigator.pop(ctx, 'vis'),
          ),
        if (mine)
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF28B82)),
            title: Text(tr('Xoá'), style: const TextStyle(color: Color(0xFFF28B82))),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
      ]),
    ),
  );
  if (a == null || !context.mounted) return;
  try {
    switch (a) {
      case 'edit':
        onEdit();
      case 'vis':
        await api.patch(p.id, {'visibility': p.public ? 'private' : 'meeting'});
        await reload();
      case 'show':
        if (!myTurn && !call.canModerate) {
          final e = await call.stageAct('request');
          if (e != null) return context.mounted ? meetToast(context, e) : null;
          if ((call.roomStage ?? const {})['presenter'] != call.myId()) {
            return context.mounted ? meetToast(context, tr('Đã xin lượt trình chiếu, chờ chủ trì trao lượt')) : null;
          }
        }
        final e = await call.stageAct('show', {'page': p.id});
        if (e != null && context.mounted) meetToast(context, e);
      case 'delete':
        await api.delete(p.id);
        await reload();
    }
  } catch (e) {
    if (context.mounted) meetToast(context, '$e');
  }
}
