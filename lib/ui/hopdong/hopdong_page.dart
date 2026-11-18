// Hợp đồng (vn.flygo.hopdong): trang chủ. Máy tính: thanh trái (Tổng quan, Tất cả, Đang ký, Tiến độ ký, Quá hạn ký,
// Sắp hết hạn, …) có số đếm, ô KPI, chip lọc, bảng hợp đồng và trang Tiến độ ký (danh sách + khung chi tiết).
// Điện thoại: chip lọc + thẻ hợp đồng; bấm vào thẻ mở Tiến độ ký (hợp đồng nháp mở trang soạn).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../state/app_state.dart';
import '../app_shell.dart';
import '../app_route.dart';
import '../theme.dart' show toast;
import 'api.dart';
import 'detail_page.dart';
import 'edit_page.dart';
import 'look.dart';
import 'model.dart';
import 'progress.dart';

Future<void> openHopdong(BuildContext context, MiniApp app, {String? path}) async {
  final state = context.read<AppState>();
  final host = AppHost.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final id = await FlygoId.current(state.token);
    if (id == null) throw StateError('Máy chủ này chưa có Flygo ID');
    final api = HopdongApi(base: app.baseUrl, id: id);
    final cid = path == null ? null : RegExp(r'^/c/([A-Za-z0-9_-]{6,40})').firstMatch(path)?.group(1);
    await host.open(key: app.id, title: app.name, deep: cid != null, builder: (_) => HopdongHome(api: api, title: app.name, openId: cid));
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

/// Mục ở thanh trái (máy tính) / chip (điện thoại): (khoá, icon, tên, trạng thái lọc gửi máy chủ).
const _navItems = <(String, IconData, String, String?)>[
  ('overview', Icons.space_dashboard_outlined, 'Tổng quan', null),
  ('all', Icons.description_outlined, 'Tất cả hợp đồng', null),
  ('sending', Icons.draw_outlined, 'Đang ký', 'sending'),
  ('progress', Icons.route_outlined, 'Tiến độ ký', 'sending'),
  ('overdue', Icons.alarm_outlined, 'Quá hạn ký', 'overdue'),
  ('expiring', Icons.event_busy_outlined, 'Sắp hết hạn', 'expiring'),
  ('signed', Icons.task_alt_rounded, 'Đã ký đủ', 'signed'),
  ('rejected', Icons.do_not_disturb_on_outlined, 'Bị từ chối', 'rejected'),
  ('draft', Icons.edit_note_rounded, 'Nháp', 'draft'),
];

/// Chip lọc trạng thái trên bảng (máy tính).
const _statusChips = <(String?, String)>[(null, 'Tất cả'), ('draft', 'Nháp'), ('sending', 'Đang ký'), ('signed', 'Đã ký đủ'), ('rejected', 'Bị từ chối'), ('cancelled', 'Đã huỷ')];

/// Chip lọc trên trang Tiến độ ký.
const _progressChips = <(String, String)>[('sending', 'Đang ký'), ('overdue', 'Quá hạn ký'), ('rejected', 'Bị từ chối'), ('week', 'Hoàn tất tuần này')];

/// Chip lọc trên điện thoại.
const _phoneChips = <(String?, String)>[
  (null, 'Tất cả'), ('sending', 'Chờ ký'), ('overdue', 'Quá hạn'), ('expiring', 'Sắp hết hạn'), ('draft', 'Nháp'), ('signed', 'Đã ký'), ('rejected', 'Bị từ chối'),
];

class HopdongHome extends StatefulWidget {
  const HopdongHome({super.key, required this.api, this.title = 'Hợp đồng', this.openId, this.initialView = 'overview'});
  final HopdongApi api;
  final String title;

  /// Mở thẳng một hợp đồng (link `/c/<id>`).
  final String? openId;

  /// Kiểm thử: mở sẵn trang (overview / progress / …).
  final String initialView;
  @override
  State<HopdongHome> createState() => _HopdongHomeState();
}

class _HopdongHomeState extends State<HopdongHome> {
  late String _view = widget.initialView; // overview | all | sending | progress | overdue | expiring | signed | rejected | draft
  String? _status; // chip trạng thái (bảng máy tính / điện thoại)
  String _progress = 'sending';
  final _search = TextEditingController();
  bool _phoneSearch = false;
  HdCounts _counts = const HdCounts();
  HdMe? _me;
  List<Contract>? _list;
  int _weekDone = 0;
  Object? _error;
  Contract? _sel; // hợp đồng đang xem ở trang Tiến độ ký
  int _loadSeq = 0;
  bool _wide = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.openId != null) _openById(widget.openId!);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Trạng thái gửi máy chủ theo trang đang mở.
  String? get _serverStatus {
    if (_view == 'progress') return _progress == 'week' ? 'signed' : _progress;
    if (_view == 'overview' || _view == 'all') return _status;
    return _navItems.firstWhere((x) => x.$1 == _view).$4;
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    try {
      final r = await Future.wait<Object>([
        widget.api.counts(),
        widget.api.contracts(status: _serverStatus, q: _search.text),
        if (_me == null) widget.api.me(),
        if (_view == 'progress') widget.api.contracts(status: 'signed'),
      ]);
      if (!mounted || seq != _loadSeq) return;
      final weekAgo = hdNow().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      bool inWeek(Contract c) => (c.doneAt ?? 0) >= weekAgo;
      setState(() {
        _counts = r[0] as HdCounts;
        var list = r[1] as List<Contract>;
        if (_view == 'progress' && _progress == 'week') list = list.where(inWeek).toList();
        _list = list;
        final hadMe = _me != null;
        _me ??= r[2] as HdMe;
        if (_view == 'progress') _weekDone = (r[hadMe ? 2 : 3] as List<Contract>).where(inWeek).length;
        _error = null;
      });
      if (_view == 'progress' && _wide) {
        final keep = _sel == null ? null : _list!.where((c) => c.id == _sel!.id).firstOrNull;
        final pick = keep ?? _list!.firstOrNull;
        if (pick != null) {
          _select(pick);
        } else {
          setState(() => _sel = null);
        }
      }
    } catch (e) {
      if (mounted && seq == _loadSeq) setState(() => _error = e);
    }
  }

  Future<void> _select(Contract c) async {
    setState(() => _sel = c);
    try {
      final full = await widget.api.contract(c.id);
      if (mounted && _sel?.id == c.id) setState(() => _sel = full);
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    }
  }

  void _go(String view) {
    setState(() {
      _view = view;
      _status = null;
      _list = null;
      if (view != 'progress') _sel = null;
    });
    _load();
  }

  Future<void> _open(Contract c) async {
    await openContract(context, widget.api, c, wide: _wide);
    _load();
  }

  Future<void> _openById(String id) async {
    try {
      final c = await widget.api.contract(id);
      if (mounted) await _open(c);
    } catch (e) {
      if (mounted) hdToast(context, '$e');
    }
  }

  Future<void> _create() async {
    await Navigator.of(context).push<Contract>(AppPageRoute(builder: (_) => ContractEditPage(api: widget.api)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = HdLook.of(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      if (wide != _wide) {
        _wide = wide;
        if (wide && _view == 'progress' && _sel == null && (_list?.isNotEmpty ?? false)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _select(_list!.first) : null);
        }
      }
      return Scaffold(backgroundColor: l.bg, body: wide ? _desktop(l) : _phone(l));
    });
  }

  // ================================================================ máy tính
  Widget _desktop(HdLook l) => SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sideNav(l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(decoration: BoxDecoration(border: Border(bottom: BorderSide(color: l.border))), child: _wrap(_topBar(l))),
              Expanded(child: _wrap(_error != null && _list == null ? _errorView(l) : (_view == 'progress' ? _progressView(l) : _listView(l)))),
            ]),
          ),
        ]),
      );

  /// Nội dung máy tính rộng tối đa 1200px, ở giữa.
  Widget _wrap(Widget child) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1200), child: child));

  Widget _sideNav(HdLook l) {
    final canPop = showsBack(context);
    Widget item((String, IconData, String, String?) it) {
      final sel = _view == it.$1;
      final n = switch (it.$1) { 'overview' => null, 'all' => _counts.all, 'progress' => _counts.sending, _ => _counts.of(it.$4) };
      final nc = it.$1 == 'overdue' && (n ?? 0) > 0 ? l.red : (it.$1 == 'expiring' && (n ?? 0) > 0 ? l.warn : l.sub);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: sel ? l.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _go(it.$1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(children: [
                Icon(it.$2, size: 18, color: sel ? l.accentText : l.sub),
                const SizedBox(width: 10),
                Expanded(child: Text(it.$3, style: TextStyle(color: sel ? l.accentText : l.text, fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400))),
                if (n != null && n > 0) Text('$n', style: TextStyle(color: sel ? l.accentText : nc, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 216,
      decoration: BoxDecoration(color: l.nav, border: Border(right: BorderSide(color: l.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
          child: Row(children: [
            if (canPop)
              IconButton(visualDensity: VisualDensity.compact, onPressed: () => Navigator.maybePop(context), icon: Icon(Icons.arrow_back_rounded, color: l.sub, size: 18)),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: l.accent, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.description_rounded, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title, style: TextStyle(color: l.text, fontSize: 15, fontWeight: FontWeight.w700))),
            if (_me?.admin == true) Pill('Quản trị', fg: l.accentText, bg: l.accentSoft, size: 10),
          ]),
        ),
        for (final it in _navItems.take(4)) item(it),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Text('THEO TRẠNG THÁI', style: TextStyle(color: l.faint, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
        ),
        for (final it in _navItems.skip(4)) item(it),
        const Spacer(),
        if (_me != null && _me!.company.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Row(children: [
              Icon(Icons.apartment_rounded, size: 16, color: l.sub),
              const SizedBox(width: 8),
              Expanded(child: Text(_me!.company, maxLines: 2, style: TextStyle(color: l.sub, fontSize: 12))),
            ]),
          ),
      ]),
    );
  }

  Widget _topBar(HdLook l) {
    final title = _navItems.firstWhere((x) => x.$1 == _view).$3;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
      child: Row(children: [
        Expanded(child: Text(title, style: TextStyle(color: l.text, fontSize: 17, fontWeight: FontWeight.w700))),
        HdSearch(controller: _search, width: 300, height: 34, onSubmit: (_) => _load(), hint: 'Tìm số HĐ, tên, đối tác, MST…'),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('Hợp đồng mới', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          style: FilledButton.styleFrom(
            backgroundColor: l.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }

  Widget _errorView(HdLook l) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: l.sub),
          const SizedBox(height: 10),
          Text('Không tải được: $_error', textAlign: TextAlign.center, style: TextStyle(color: l.sub)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _load, child: const Text('Thử lại')),
        ]),
      );

  Widget _kpis(HdLook l) {
    final list = _list ?? const <Contract>[];
    final signedValue = list.where((c) => c.status == 'signed' && c.currency == 'VND').fold<num>(0, (a, c) => a + (c.value ?? 0));
    final waitPartner = list.where((c) => c.status == 'sending' && c.current.any((p) => !p.internal)).length;
    final waitMe = list.where((c) => c.status == 'sending' && c.current.any((p) => p.internal)).length;
    Widget tile(String label, int n, String sub, {Color? nc, Color? sc}) => Expanded(
          child: HdCard(
            pad: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: l.sub, fontSize: 12)),
              const SizedBox(height: 2),
              Text('$n', style: TextStyle(color: nc ?? l.text, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 1),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sc ?? l.sub, fontSize: 12)),
            ]),
          ),
        );
    return Row(children: [
      tile('Đã ký đủ', _counts.signed, signedValue > 0 ? 'Giá trị ${moneyShort(signedValue)}' : 'chưa có hợp đồng ký xong', sc: signedValue > 0 ? l.ok : null),
      const SizedBox(width: 12),
      tile('Đang chờ ký', _counts.sending, '$waitMe chờ mình · $waitPartner chờ đối tác'),
      const SizedBox(width: 12),
      tile('Quá hạn ký', _counts.overdue, _counts.overdue > 0 ? 'cần gia hạn hoặc nhắc' : 'không có', nc: _counts.overdue > 0 ? l.red : null),
      const SizedBox(width: 12),
      tile('Hết hạn trong 30 ngày', _counts.expiring, _counts.expiring > 0 ? 'nhắc gia hạn tự động' : 'không có', nc: _counts.expiring > 0 ? l.warn : null),
    ]);
  }

  Widget _listView(HdLook l) {
    final list = _list;
    final showChips = _view == 'overview' || _view == 'all';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
        if (_view == 'overview') ...[_kpis(l), const SizedBox(height: 14)],
        Row(children: [
          if (showChips)
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in _statusChips)
                  HdChip(s.$1 == null ? 'Trạng thái: Tất cả' : s.$2, small: true, icon: s.$1 == null ? Icons.filter_list_rounded : null, selected: _status == s.$1, onTap: () {
                    setState(() => _status = s.$1);
                    _load();
                  }),
              ]),
            )
          else
            const Spacer(),
          Text('${list?.length ?? 0} hợp đồng', style: TextStyle(color: l.sub, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        if (list == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else if (list.isEmpty)
          _empty(l)
        else
          _table(l, list),
      ]),
    );
  }

  Widget _empty(HdLook l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(children: [
          Icon(Icons.description_outlined, size: 44, color: l.faint),
          const SizedBox(height: 10),
          Text(_search.text.isNotEmpty ? 'Không có hợp đồng khớp "${_search.text}"' : 'Chưa có hợp đồng nào ở đây', style: TextStyle(color: l.sub, fontSize: 15)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Hợp đồng mới')),
        ]),
      );

  static const _cols = [5, 3, 2, 2, 2, 2]; // + cột Phụ trách cố định

  Widget _table(HdLook l, List<Contract> list) {
    final now = hdNow();
    final head = TextStyle(color: l.sub, fontSize: 12, fontWeight: FontWeight.w600);
    Widget cell(int flex, Widget w) => Expanded(flex: flex, child: Padding(padding: const EdgeInsets.only(right: 12), child: w));
    final soon = now.add(const Duration(days: 30)).millisecondsSinceEpoch;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Row(children: [
          cell(_cols[0], Text('Hợp đồng', style: head)),
          cell(_cols[1], Text('Đối tác', style: head)),
          cell(_cols[2], Text('Giá trị', style: head)),
          cell(_cols[3], Text('Hiệu lực', style: head)),
          cell(_cols[4], Text('Trạng thái', style: head)),
          cell(_cols[5], Text('Tiến độ ký', style: head)),
          SizedBox(width: 70, child: Text('Phụ trách', style: head)),
        ]),
      ),
      Divider(height: 1, color: l.border),
      for (final c in list) ...[
        InkWell(
          onTap: () => _open(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              cell(
                _cols[0],
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(children: [
                      if (c.no.isNotEmpty) TextSpan(text: c.no, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (c.no.isNotEmpty && c.title.isNotEmpty) const TextSpan(text: ' · '),
                      TextSpan(text: c.title.isEmpty && c.no.isEmpty ? 'Chưa đặt tên' : c.title),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: l.text, fontSize: 13),
                  ),
                  const SizedBox(height: 1),
                  Text(_rowSub(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: 11.5)),
                ]),
              ),
              cell(
                _cols[1],
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.partner?.name ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: 13)),
                  const SizedBox(height: 1),
                  Text([if (c.partner != null && c.partner!.label.isNotEmpty) c.partner!.label, if (c.parties.length > 2) '+${c.parties.length - 2} bên'].join(' · '),
                      style: TextStyle(color: l.sub, fontSize: 11.5)),
                ]),
              ),
              cell(_cols[2], Text(money(c.value, c.currency), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: 13))),
              cell(
                _cols[3],
                c.effFrom == null && c.effTo == null
                    ? Text('—', style: TextStyle(color: l.sub))
                    : c.status == 'signed' && c.effTo != null && c.effTo! <= soon
                        ? Text('→ ${dmy(c.effTo)}', style: TextStyle(color: l.red, fontSize: 13))
                        : Text('${dmyShort(c.effFrom)} → ${dmyShort(c.effTo)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: 12.5)),
              ),
              cell(_cols[4], Align(alignment: Alignment.centerLeft, child: StatusChip(c, now: now, size: 11))),
              cell(_cols[5], _progressCell(l, c, now)),
              SizedBox(width: 70, child: Align(alignment: Alignment.centerLeft, child: OwnerDot(c.ownerName, size: 24))),
            ]),
          ),
        ),
        Divider(height: 1, color: l.border),
      ],
    ]);
  }

  String _rowSub(Contract c) {
    final d = c.doc;
    return [
      if (c.docs.length > 1)
        '${c.docs.length} tài liệu'
      else if (d != null)
        '${d.pages != null ? '${d.pages} trang · ' : ''}bản ${d.rev}'
      else
        'chưa có PDF',
      if (c.status == 'signed' && c.doneAt != null) 'ký xong ${dm(c.doneAt)}' else if (c.sentAt != null) 'gửi ${dm(c.sentAt)}' else if (c.updatedAt != null) 'sửa ${dm(c.updatedAt)}',
    ].join(' · ');
  }

  Widget _progressCell(HdLook l, Contract c, DateTime now) {
    final t = TextStyle(color: l.sub, fontSize: 12);
    switch (c.status) {
      case 'draft':
        return Text('Chưa gửi · ${c.parties.length} bên', style: t);
      case 'rejected':
        final p = c.parties.where((p) => p.status == 'rejected').firstOrNull;
        return Text('Từ chối: ${p?.name ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.copyWith(color: l.warn));
      case 'cancelled':
        return Text('Đã huỷ', style: t);
      case 'signed':
        if (c.effTo != null && c.effTo! > now.millisecondsSinceEpoch && c.effTo! - now.millisecondsSinceEpoch < 30 * 86400000) {
          final d = ((c.effTo! - now.millisecondsSinceEpoch) / 86400000).ceil();
          return Text('⚠ còn $d ngày', style: t.copyWith(color: l.red));
        }
    }
    return Row(children: [
      SizedBox(width: 70, child: SegProgress(c, now: now, height: 5, gap: 3)),
      const SizedBox(width: 8),
      Text('${c.signedCount}/${c.parties.length}', style: t),
    ]);
  }

  // ---------------------------------------------------------------- Tiến độ ký (máy tính)
  int _progressCount(String k) => switch (k) { 'sending' => _counts.sending, 'overdue' => _counts.overdue, 'rejected' => _counts.rejected, _ => _weekDone };

  Widget _progressView(HdLook l) {
    final list = _list;
    final now = hdNow();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in _progressChips)
            HdChip('${k.$2} · ${_progressCount(k.$1)}', small: true, selected: _progress == k.$1, onTap: () {
              setState(() {
                _progress = k.$1;
                _list = null;
              });
              _load();
            }),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 380,
              child: list == null
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Padding(padding: const EdgeInsets.only(top: 40), child: Text('Không có hợp đồng nào', textAlign: TextAlign.center, style: TextStyle(color: l.sub)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _progressCard(l, list[i], now),
                          ),
                        ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: HdCard(
                pad: EdgeInsets.zero,
                child: _sel == null
                    ? SizedBox(height: 200, child: Center(child: Text('Chọn một hợp đồng để xem tiến độ', style: TextStyle(color: l.sub))))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: ProgressPane(
                          key: ValueKey(_sel!.id),
                          api: widget.api,
                          contract: _sel!,
                          onChanged: (n) {
                            setState(() => _sel = n);
                            _load();
                          },
                        ),
                      ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _progressCard(HdLook l, Contract c, DateTime now) {
    final sel = _sel?.id == c.id;
    final cur = c.current.firstOrNull;
    final rej = c.parties.where((p) => p.status == 'rejected').firstOrNull;
    final over = c.overdue(now);
    final Widget badge = over
        ? Pill('Quá hạn', fg: l.red, bg: l.redSoft, size: 11)
        : c.status == 'rejected'
            ? Pill('Từ chối', fg: l.warn, bg: l.warnSoft, size: 11)
            : c.status == 'signed'
                ? Pill('Đã ký đủ', fg: l.ok, bg: l.okSoft, size: 11)
                : Pill('${c.signedCount}/${c.parties.length}', fg: l.accentText, bg: l.accentSoft, size: 11);
    String left;
    String right = '';
    Color rc = l.sub;
    if (c.status == 'rejected') {
      left = '"${rej?.rejectReason ?? 'Từ chối ký'}"';
      right = dm(c.updatedAt);
    } else if (c.status == 'signed') {
      left = 'Đủ ${c.parties.length} chữ ký';
      right = dm(c.doneAt);
    } else if (cur != null) {
      left = over ? 'Chờ: ${cur.name} · ${cur.idLabel}' : 'Đang chờ: ${cur.name}${cur.label.isNotEmpty ? ' (${cur.label})' : ''}';
      if (c.signDeadline != null) {
        final d = now.difference(DateTime.fromMillisecondsSinceEpoch(c.signDeadline!)).inDays;
        right = over ? 'quá ${d < 1 ? 1 : d} ngày' : 'hạn ${dm(c.signDeadline)}';
        if (over) rc = l.red;
      }
    } else {
      left = kStatusLabels[c.status] ?? '';
    }
    return HdCard(
      color: sel ? l.accentSoft.withValues(alpha: l.dark ? .55 : .7) : null,
      borderColor: sel ? l.accent : null,
      pad: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      onTap: () => _select(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(c.heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: 13.5, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          badge,
        ]),
        const SizedBox(height: 8),
        SegProgress(c, now: now, height: 4, gap: 4),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: 12))),
          if (right.isNotEmpty) Text(right, style: TextStyle(color: rc, fontSize: 12)),
        ]),
      ]),
    );
  }

  // ================================================================ điện thoại
  Widget _phone(HdLook l) {
    final list = _list;
    final now = hdNow();
    final canPop = showsBack(context);
    return Column(children: [
      AppBar(
        backgroundColor: l.bg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: canPop,
        title: _phoneSearch
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Tìm số HĐ, đối tác, MST…'),
              )
            : Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Tìm',
            onPressed: () {
              setState(() => _phoneSearch = !_phoneSearch);
              if (!_phoneSearch && _search.text.isNotEmpty) {
                _search.clear();
                _load();
              }
            },
            icon: Icon(_phoneSearch ? Icons.close_rounded : Icons.search_rounded),
          ),
          IconButton(tooltip: 'Hợp đồng mới', onPressed: _create, icon: const Icon(Icons.add_circle_outline_rounded)),
        ],
      ),
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
          children: [
            for (final s in _phoneChips)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: HdChip('${s.$2} · ${s.$1 == null ? _counts.all : _counts.of(s.$1)}', selected: _phoneStatus == s.$1, onTap: () {
                  setState(() {
                    _view = s.$1 ?? 'all';
                    _list = null;
                  });
                  _load();
                }),
              ),
          ],
        ),
      ),
      Expanded(
        child: _error != null && list == null
            ? _errorView(l)
            : list == null
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: list.isEmpty
                        ? ListView(children: [_empty(l)])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _phoneCard(l, list[i], now),
                          ),
                  ),
      ),
    ]);
  }

  /// Chip đang chọn trên điện thoại (theo trang đang mở).
  String? get _phoneStatus => switch (_view) { 'overview' || 'all' || 'progress' => _view == 'progress' ? 'sending' : null, _ => _view };

  Widget _phoneCard(HdLook l, Contract c, DateTime now) {
    final over = c.overdue(now);
    final days = c.effTo == null ? null : ((c.effTo! - now.millisecondsSinceEpoch) / 86400000).ceil();
    final expiring = c.status == 'signed' && days != null && days >= 0 && days <= 30;
    final cur = c.current.firstOrNull;
    final Widget badge = expiring
        ? Pill('Còn $days ngày', fg: l.red, bg: l.redSoft, size: 12.5)
        : cur != null && cur.internal && !over
            ? Pill('Lượt bên mình', fg: l.accentText, bg: l.accentSoft, size: 12.5)
            : StatusChip(c, now: now, size: 12.5);
    return HdCard(
      pad: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () => _open(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(c.no.isEmpty ? 'Chưa có số' : c.no, style: TextStyle(color: l.sub, fontSize: 14.5, fontWeight: FontWeight.w700))),
          badge,
        ]),
        const SizedBox(height: 4),
        Text(c.title.isEmpty ? 'Hợp đồng chưa đặt tên' : c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.text, fontSize: 16.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text([c.partner?.name ?? '', if (c.value != null) moneyShort(c.value, c.currency)].where((x) => x.isNotEmpty).join('  ·  '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: l.sub, fontSize: 13.5)),
          ),
          if (c.status == 'sending') ...[
            const SizedBox(width: 10),
            SizedBox(width: 90, child: SegProgress(c, now: now, height: 5, gap: 3)),
            const SizedBox(width: 8),
            Text('${c.signedCount}/${c.parties.length}', style: TextStyle(color: l.sub, fontSize: 13.5)),
          ] else if (expiring && c.remindDays > 0)
            Text('nhắc gia hạn', style: TextStyle(color: l.sub, fontSize: 13.5)),
        ]),
      ]),
    );
  }
}
