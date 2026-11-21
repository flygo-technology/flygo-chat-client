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
import 'stage_frame.dart' show showStageThemeEditor;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 6),
          child: Row(children: [
            Text(tr('Hệ thống'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            // Giao diện sân khấu: màu nhấn, tối / sáng, nền chung của mọi trang (chủ trì; quản trị đặt mặc định công ty).
            if (call.canModerate)
              Flexible(
                child: TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: const Color(0xFF8AB4F8)),
                  onPressed: () => showStageThemeEditor(context, call, canCompany: _sysAdmin),
                  icon: const Icon(Icons.palette_outlined, size: 16),
                  label: Text(tr('Giao diện sân khấu'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
          ]),
        ),
        // Mọi thẻ hiện hết, xuống dòng (Sếp: không cuộn ngang).
        _wrap(pad, wide ? 150 : 104, sysPages.length, (i, cw) {
            final p = sysPages[i];
            return Padding(
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
                      width: cw,
                      height: wide ? 118 : 92,
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
              );
        }),
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
        // Mọi trang hiện hết, xuống dòng theo bề rộng (Sếp: không cuộn ngang).
        _wrap(
          pad,
          wide ? 176 : 112,
          r.pages.length + ((!mine && private > 0 && host) || mine ? 1 : 0),
          (i, cw) => i < r.pages.length
              ? KeyedSubtree(key: ValueKey(r.pages[i].id), child: _card(r.pages[i], mine: mine, wide: wide, width: cw))
              : mine
                  ? _addCard(wide, cw)
                  : _privateCard(private, wide, cw),
        ),
      ]),
    );
  }

  Widget _badge(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(5)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 10, fontFeatures: [FontFeature.tabularFigures()])),
      );

  /// Lưới xuống dòng: số cột theo bề rộng (thẻ ~[target] px), thẻ giãn đều cho kín hàng.
  Widget _wrap(double pad, double target, int n, Widget Function(int i, double w) item) => Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: LayoutBuilder(builder: (context, box) {
          final cols = ((box.maxWidth + 8) / (target + 8)).floor().clamp(2, 12);
          final cell = box.maxWidth / cols;
          return Wrap(runSpacing: 8, children: [for (var i = 0; i < n; i++) SizedBox(width: cell, child: item(i, cell - 8))]);
        }),
      );

  Widget _card(MeetPage p, {required bool mine, required bool wide, double? width}) {
    final s = pageTypeOf(p.type);
    final st = call.roomStage ?? const {};
    final live = st['page'] == p.id;
    final pr = call.roomPresent;
    final w = width ?? (wide ? 176.0 : 112.0);
    final sub = [s?.label ?? p.type, if (p.file?['pages'] != null && p.file!['pages'] != 0) tr('{0} trang', [p.file!['pages']])].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: _cardBg,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Builder(builder: (cardCtx) => InkWell(
          onTap: () => widget.onView(p.id),
          // Menu nổi ngay tại thẻ (nhấn giữ trên điện thoại, chuột phải / nhấn giữ trên máy tính).
          onLongPress: mine || call.canModerate ? () => _menu(p, cardCtx) : null,
          onSecondaryTap: mine || call.canModerate ? () => _menu(p, cardCtx) : null,
          child: Container(
            width: w,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: live ? const Color(0xFFF0464E) : Colors.transparent, width: live ? 2 : 1)),
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
                  // Đang chiếu: nhãn LIVE đỏ nhấp nháy để ai cũng biết trang này đang trên sân khấu.
                  if (live) const Positioned(top: 4, left: 0, right: 0, child: Center(child: LiveBadge())),
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
        )),
      ),
    );
  }

  Widget _privateCard(int n, bool wide, [double? width]) => Container(
        width: width ?? (wide ? 176 : 112),
        height: (width ?? (wide ? 176 : 112)) * 9 / 16 + (wide ? 40 : 22),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(color: _cardBg.withValues(alpha: .6), borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline_rounded, color: _sub),
          const SizedBox(height: 4),
          Text(tr('{0} trang chưa công khai', [n]), textAlign: TextAlign.center, style: const TextStyle(color: _sub, fontSize: 11.5)),
        ]),
      );

  Widget _addCard(bool wide, [double? width]) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: widget.onNew,
          child: Container(
            width: width ?? (wide ? 176 : 112),
            height: (width ?? (wide ? 176 : 112)) * 9 / 16 + (wide ? 40 : 22),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_rounded, color: _acc, size: 26),
              Text(tr('Thêm trang'), style: const TextStyle(color: _sub, fontSize: 11.5)),
            ]),
          ),
        ),
      );

  Future<void> _menu(MeetPage p, [BuildContext? at]) => showPageMenu(at ?? context, call, p, onEdit: () => widget.onEdit(p.id), reload: _load);
}

/// Menu của một trang (nhấn giữ / chuột phải thẻ, hoặc ⋯ trên trang): menu nổi ngay tại thẻ (Sếp: không phải bảng kéo lên).
/// Chủ trang: Sửa, Xoá (hỏi lại), Trình chiếu, Nhân bản, Bật công khai, Bật riêng tư (mục đang ở trạng thái đó thì mờ);
/// chủ trì với trang người khác: chỉ Trình chiếu. Bấm (không giữ) là tương tác với trang.
Future<void> showPageMenu(BuildContext context, CallService call, MeetPage p, {required VoidCallback onEdit, required Future<void> Function() reload, Rect? anchor}) async {
  final api = PagesApi(call);
  final mine = p.owner == call.myId();
  final st = call.roomStage ?? const {};
  final myTurn = st['presenter'] == call.myId();
  final canShow = myTurn || call.canModerate || '${st['presenter'] ?? ''}'.isEmpty;
  if (!mine && !call.canModerate) return;
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final r = anchor ?? (box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size);
  final origin = overlay.globalToLocal(r.topLeft);
  PopupMenuItem<String> item(String v, IconData i, String label, {bool enabled = true, Color? color}) => PopupMenuItem<String>(
        value: v,
        enabled: enabled,
        height: 44,
        child: Row(children: [
          Icon(i, size: 20, color: enabled ? (color ?? Colors.white) : Colors.white24),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: enabled ? (color ?? Colors.white) : Colors.white38)),
        ]),
      );
  final a = await showMenu<String>(
    context: context,
    color: const Color(0xFF2B2E33),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    position: RelativeRect.fromRect(origin & r.size, Offset.zero & overlay.size),
    items: [
      if (mine) item('edit', Icons.edit_outlined, tr('Sửa')),
      if (mine) item('delete', Icons.delete_outline_rounded, tr('Xoá'), color: const Color(0xFFF28B82)),
      item('show', Icons.play_circle_outline_rounded, canShow ? tr('Trình chiếu') : tr('Xin lượt và chiếu'), color: const Color(0xFF7FD8CC)),
      if (mine) item('dup', Icons.copy_all_rounded, tr('Nhân bản')),
      if (mine) item('public', Icons.public_rounded, tr('Bật công khai'), enabled: !p.public),
      if (mine) item('private', Icons.lock_outline_rounded, tr('Bật riêng tư'), enabled: p.public),
    ],
  );
  if (a == null || !context.mounted) return;
  try {
    switch (a) {
      case 'edit':
        onEdit();
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF2B2E33),
            title: Text(tr('Xoá trang?'), style: const TextStyle(color: Colors.white)),
            content: Text(tr('"{0}" sẽ bị xoá, không khôi phục được.', [p.title]), style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD93025)), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xoá'))),
            ],
          ),
        );
        if (ok != true) return;
        await api.delete(p.id);
        await reload();
      case 'dup':
        await api.duplicate(p.id);
        await reload();
        if (context.mounted) meetToast(context, tr('Đã nhân bản "{0}"', [p.title]));
      case 'public':
        await api.patch(p.id, {'visibility': 'meeting'});
        await reload();
      case 'private':
        await api.patch(p.id, {'visibility': 'private'});
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
    }
  } catch (e) {
    if (context.mounted) meetToast(context, '$e');
  }
}

/// Nhãn "LIVE" đỏ nhấp nháy: trang đang trên sân khấu (thẻ trang, trang đang xem).
class LiveBadge extends StatefulWidget {
  final double size;
  const LiveBadge({super.key, this.size = 10});
  @override
  State<LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<LiveBadge> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Container(
        padding: EdgeInsets.symmetric(horizontal: widget.size * .7, vertical: widget.size * .2),
        decoration: BoxDecoration(
          color: const Color(0xFFE5343D),
          borderRadius: BorderRadius.circular(widget.size),
          boxShadow: [BoxShadow(color: const Color(0xFFE5343D).withValues(alpha: still ? .4 : .25 + .45 * _a.value), blurRadius: widget.size * (still ? .8 : .4 + 1.2 * _a.value))],
        ),
        child: child,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: widget.size * .55, height: widget.size * .55, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        SizedBox(width: widget.size * .4),
        Text('LIVE', style: TextStyle(color: Colors.white, fontSize: widget.size, fontWeight: FontWeight.w800, letterSpacing: .8)),
      ]),
    );
  }
}
