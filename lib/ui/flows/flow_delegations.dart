import 'package:flutter/material.dart';

import '../../api/flows_api.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../common.dart';
import '../theme.dart';
import 'flow_card.dart' show kFlowGreen, kFlowOrange, kFlowRed;
import 'flow_nav.dart';
import 'flows_org.dart' show pickUsers;
import 'flows_page.dart' show FlowDetailPage;

/// Tab "Ủy quyền" của trang Quy trình: ủy quyền của tôi và người đang ủy quyền cho tôi, thời gian còn lại, ngày
/// hết hạn. Ủy quyền chỉ tạo qua quy trình có cấp trên duyệt (bước "Đặt ủy quyền"): nút + mở quy trình đó.

String _userName(AppState app, String id) {
  final u = app.users[id];
  if (u == null) return id;
  return u.displayName.isNotEmpty ? u.displayName : u.username;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _when(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(t.hour)}:${_two(t.minute)} ${_two(t.day)}/${_two(t.month)}/${t.year}';
}

/// "3 ngày 4 giờ", "5 giờ 20 phút", "12 phút".
String durationLabel(int ms) {
  final m = (ms / 60000).ceil();
  final d = m ~/ 1440, h = (m % 1440) ~/ 60, mi = m % 60;
  if (d > 0) return h > 0 ? tr('{0} ngày {1} giờ', [d, h]) : tr('{0} ngày', [d]);
  if (h > 0) return mi > 0 ? tr('{0} giờ {1} phút', [h, mi]) : tr('{0} giờ', [h]);
  return tr('{0} phút', [mi < 1 ? 1 : mi]);
}

class DelegationsTab extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final double bottomPadding;
  /// Tăng khi cần tải lại (vd sau khi gửi đơn xin ủy quyền).
  final Listenable? reload;
  const DelegationsTab({super.key, required this.app, required this.api, this.bottomPadding = 0, this.reload});
  @override
  State<DelegationsTab> createState() => DelegationsTabState();
}

class DelegationsTabState extends State<DelegationsTab> {
  Map<String, dynamic>? _data;
  String? _err;

  /// Quy trình xin ủy quyền mà tôi bắt đầu được (nút + của tab).
  List<Map<String, dynamic>> get requestFlows => [for (final x in (_data?['request_flows'] as List? ?? const [])) if (x is Map) x.cast<String, dynamic>()];

  @override
  void initState() {
    super.initState();
    load();
    widget.reload?.addListener(load);
  }

  @override
  void dispose() {
    widget.reload?.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await widget.api.myDelegations();
      if (mounted) {
        setState(() {
          _data = d;
          _err = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  String _flows(Map d) {
    final names = (_data?['flows'] as Map?) ?? const {};
    final ids = [for (final f in (d['flows'] as List? ?? const [])) '$f'];
    return ids.isEmpty ? tr('Tất cả quy trình (còn lại)') : ids.map((f) => '${names[f] ?? f}').join(', ');
  }

  Future<void> _end(Map d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Kết thúc ủy quyền sớm?')),
        content: Text(tr('{0} sẽ không nhận tiến trình thay bạn nữa từ bây giờ. Tiến trình đã giao thay vẫn giữ nguyên.', [_userName(widget.app, '${d['delegate']}')])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Kết thúc'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final m = ScaffoldMessenger.of(context);
    try {
      await widget.api.endDelegation((d['id'] as num).toInt());
      m.showSnackBar(toast(Text(tr('Đã kết thúc ủy quyền'))));
      await load();
    } catch (e) {
      m.showSnackBar(toast(Text('$e')));
    }
  }

  Widget _card(Pal pal, Map d, {required bool mine}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final from = (d['from'] as num).toInt(), until = (d['until'] as num).toInt();
    final other = '${mine ? d['delegate'] : d['user']}';
    final (label, color) = now < from
        ? (tr('Bắt đầu sau {0}', [durationLabel(from - now)]), kFlowOrange)
        : now < until
            ? (tr('Còn {0}', [durationLabel(until - now)]), kFlowGreen)
            : (tr('Đã hết hạn'), pal.sub);
    final live = now < until;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      color: pal.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: pal.divider)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(userId: other, name: _userName(widget.app, other), size: 36, status: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(mine ? tr('Giao cho {0}', [_userName(widget.app, other)]) : tr('Nhận thay {0}', [_userName(widget.app, other)]),
                    style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
                Text(_flows(d), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: pal.sub)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
          const SizedBox(height: 10),
          if (live && now >= from)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: ((now - from) / (until - from)).clamp(0.0, 1.0), minHeight: 5, color: kFlowGreen, backgroundColor: pal.divider),
              ),
            ),
          Wrap(spacing: 14, runSpacing: 4, children: [
            Text(tr('Từ {0}', [_when(from)]), style: TextStyle(fontSize: 12.5, color: pal.sub)),
            Text(tr('Hết hạn {0}', [_when(until)]), style: TextStyle(fontSize: 12.5, color: pal.text, fontWeight: FontWeight.w600)),
          ]),
          if ('${d['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${d['note']}', style: TextStyle(fontSize: 12.5, color: pal.sub))),
          Row(children: [
            if (d['instance_id'] != null)
              TextButton.icon(
                onPressed: () => openFlowPage(context, 'instance-${d['instance_id']}', (_) => FlowDetailPage(app: widget.app, instanceId: '${d['instance_id']}')),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(tr('Xem đơn đã duyệt')),
              ),
            const Spacer(),
            if (mine && live)
              TextButton(onPressed: () => _end(d), child: Text(tr('Kết thúc sớm'), style: const TextStyle(color: kFlowRed))),
          ]),
        ]),
      ),
    );
  }

  Widget _head(Pal pal, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: pal.sub)),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (_err != null) {
      return ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(tr('Không tải được ủy quyền: {0}', [_err]), textAlign: TextAlign.center))]);
    }
    if (_data == null) return const Center(child: CircularProgressIndicator());
    final mine = [for (final x in (_data!['mine'] as List? ?? const [])) if (x is Map) x];
    final toMe = [for (final x in (_data!['to_me'] as List? ?? const [])) if (x is Map) x];
    return ListView(padding: EdgeInsets.only(bottom: 96 + widget.bottomPadding), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Text(tr('Ủy quyền tạo qua đơn xin ủy quyền (cấp trên duyệt). Trong thời gian ủy quyền, tiến trình của bạn ở các quy trình đã chọn cũng giao cho người nhận thay; bạn vẫn tự duyệt được.'),
            style: TextStyle(color: pal.sub, fontSize: 12.5)),
      ),
      _head(pal, tr('Tôi ủy quyền')),
      if (mine.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(tr('Chưa có ủy quyền nào. Bấm + để gửi đơn xin ủy quyền.'), style: TextStyle(color: pal.sub)))
      else
        for (final d in mine) _card(pal, d, mine: true),
      _head(pal, tr('Tôi đang nhận thay')),
      if (toMe.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(tr('Không ai đang ủy quyền cho bạn.'), style: TextStyle(color: pal.sub)))
      else
        for (final d in toMe) _card(pal, d, mine: false),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------- tự điền ủy quyền

String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _dmy(String ymd) {
  final p = ymd.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : ymd;
}

/// Bước "Yêu cầu ủy quyền": người tạo luồng tự điền từ ngày, đến ngày và bảng các quy trình (nhiều) → một người.
/// Quản lý trực tiếp duyệt ở bước sau thì mới có hiệu lực.
class DelegationRequestPage extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final int taskId;
  /// Ngày điền sẵn (vd từ ngày / đến ngày của đơn nghỉ phép), "YYYY-MM-DD".
  final String? from, until;
  const DelegationRequestPage({super.key, required this.app, required this.api, required this.taskId, this.from, this.until});
  @override
  State<DelegationRequestPage> createState() => _DelegationRequestPageState();
}

class _DelegationRequestPageState extends State<DelegationRequestPage> {
  late String _from = widget.from ?? _ymd(DateTime.now());
  late String _until = widget.until ?? _ymd(DateTime.now().add(const Duration(days: 1)));
  final _rows = <({List<String> flows, String? person})>[(flows: <String>[], person: null)];
  final _note = TextEditingController();
  List<Map<String, dynamic>> _flows = [];
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    widget.api.flowNames().then((v) {
      if (mounted) setState(() => _flows = v);
    }).catchError((_) {});
  }

  String _flowName(String id) => '${_flows.where((f) => f['id'] == id).firstOrNull?['name'] ?? id}';

  Future<void> _pickDate(bool from) async {
    final cur = DateTime.tryParse(from ? _from : _until) ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2100));
    if (d != null) setState(() => from ? _from = _ymd(d) : _until = _ymd(d));
  }

  Future<void> _pickFlows(int i) async {
    final taken = {for (var j = 0; j < _rows.length; j++) if (j != i) ..._rows[j].flows};
    final sel = {..._rows[i].flows};
    final r = await showDialog<Set<String>>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr('Các quy trình')),
          content: SizedBox(
            width: 420,
            height: 440,
            child: ListView(children: [
              CheckboxListTile(
                dense: true,
                value: sel.isEmpty,
                title: Text(tr('Các quy trình còn lại')),
                subtitle: Text(tr('Mọi quy trình không nằm ở dòng khác')),
                onChanged: (_) => set(sel.clear),
              ),
              const Divider(height: 1),
              for (final f in _flows)
                CheckboxListTile(
                  dense: true,
                  enabled: !taken.contains(f['id']),
                  value: sel.contains(f['id']),
                  title: Text('${f['icon'] ?? ''} ${f['name']}'.trim()),
                  subtitle: taken.contains(f['id']) ? Text(tr('Đã ở dòng khác')) : null,
                  onChanged: (v) => set(() => v == true ? sel.add('${f['id']}') : sel.remove('${f['id']}')),
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
    if (r != null) setState(() => _rows[i] = (flows: r.toList(), person: _rows[i].person));
  }

  Future<void> _pickPerson(int i) async {
    final v = await pickUsers(context, widget.app, selected: [?_rows[i].person], single: true, title: tr('Giao cho'));
    if (v != null && v.isNotEmpty) setState(() => _rows[i] = (flows: _rows[i].flows, person: v.first));
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.api.submit(widget.taskId, {
        'from': _from,
        'until': _until,
        'note': _note.text.trim(),
        'rules': [for (final r in _rows) {'flows': r.flows, 'delegate': r.person ?? ''}],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget cellHead(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yêu cầu ủy quyền'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Trong thời gian này, tiến trình của bạn ở các quy trình đã chọn được giao cho người nhận thay. Quản lý trực tiếp duyệt xong mới có hiệu lực.'),
            style: TextStyle(color: pal.sub, fontSize: 12.5)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(true), icon: const Icon(Icons.event_outlined, size: 18), label: Text(tr('Từ {0}', [_dmy(_from)])))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: () => _pickDate(false), icon: const Icon(Icons.event_outlined, size: 18), label: Text(tr('Đến {0}', [_dmy(_until)])))),
        ]),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(border: Border.all(color: pal.divider), borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              color: pal.surface2,
              padding: const EdgeInsets.fromLTRB(12, 8, 48, 8),
              child: Row(children: [Expanded(child: cellHead(tr('Các quy trình'))), const SizedBox(width: 8), Expanded(child: cellHead(tr('Giao cho')))]),
            ),
            for (var i = 0; i < _rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: pal.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
                child: Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _pickFlows(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Row(children: [
                          Expanded(child: Text(_rows[i].flows.isEmpty ? tr('Các quy trình còn lại') : _rows[i].flows.map(_flowName).join(', '), maxLines: 3, overflow: TextOverflow.ellipsis)),
                          Icon(Icons.arrow_drop_down_rounded, color: pal.sub),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _pickPerson(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Row(children: [
                          if (_rows[i].person != null) ...[Avatar(userId: _rows[i].person, name: _userName(widget.app, _rows[i].person!), size: 24, status: false), const SizedBox(width: 6)],
                          Expanded(
                            child: Text(_rows[i].person == null ? tr('Chọn người') : _userName(widget.app, _rows[i].person!),
                                overflow: TextOverflow.ellipsis, style: TextStyle(color: _rows[i].person == null ? pal.accentText : pal.text)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Xoá dòng'),
                    onPressed: _rows.length <= 1 ? null : () => setState(() => _rows.removeAt(i)),
                    icon: const Icon(Icons.delete_outline_rounded, color: kFlowRed, size: 20),
                  ),
                ]),
              ),
            ],
          ]),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => setState(() => _rows.add((flows: <String>[], person: null))), icon: const Icon(Icons.add_rounded), label: Text(tr('Thêm dòng'))),
        ),
        TextField(controller: _note, decoration: InputDecoration(labelText: tr('Ghi chú (tuỳ chọn)'), border: const OutlineInputBorder())),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: kFlowRed))),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(tr('Gửi quản lý duyệt'))),
      ]),
    );
  }
}

/// Ủy quyền đề nghị (kết quả bước "Yêu cầu ủy quyền") cho người duyệt xem.
class DelegationSummary extends StatelessWidget {
  final AppState app;
  final Map data;
  final Map<String, String> flowNames;
  const DelegationSummary({super.key, required this.app, required this.data, this.flowNames = const {}});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final rules = [for (final r in (data['rules'] as List? ?? const [])) if (r is Map) r];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Ủy quyền đề nghị: từ {0} đến hết {1}', [_dmy('${data['from']}'), _dmy('${data['until']}')]), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 6),
        for (final r in rules)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${(r['flows'] as List? ?? const []).isEmpty ? tr('Các quy trình còn lại') : [for (final f in (r['flows'] as List)) flowNames['$f'] ?? '$f'].join(', ')} → ${_userName(app, '${r['delegate']}')}',
              style: TextStyle(color: pal.text),
            ),
          ),
        if ('${data['note'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${data['note']}', style: TextStyle(color: pal.sub))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------- trường Ủy quyền

/// Trường kiểu Ủy quyền trong form (vd đơn nghỉ phép). Mỗi thẻ là một dòng: người nhận thay ở đầu, các quy trình
/// bên dưới. Mặc định một thẻ chứa mọi quy trình liên quan tới người đang mở form (theo tên, vai trò, phòng ban,
/// quản lý); bấm giữ một quy trình rồi kéo sang thẻ khác (hoặc chạm để chọn nơi chuyển). Quy trình bỏ ra nằm ở
/// "Chưa giao". Giá trị: [{flows: [mã], delegate: người}].
class DelegationField extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final String label;
  final String? hint, error;
  final List? value;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  const DelegationField({super.key, required this.app, required this.api, required this.label, this.hint, this.error, this.value, required this.onChanged});
  @override
  State<DelegationField> createState() => _DelegationFieldState();
}

typedef _Row = ({List<String> flows, String? person});

class _DelegationFieldState extends State<DelegationField> {
  List<Map<String, dynamic>>? _all;
  final List<_Row> _rows = [];
  /// Quy trình liên quan nhưng chưa giao cho ai.
  final List<String> _pool = [];
  String? _err;

  @override
  void initState() {
    super.initState();
    for (final r in (widget.value ?? const [])) {
      if (r is Map) _rows.add((flows: [for (final f in (r['flows'] as List? ?? const [])) '$f'], person: (r['delegate'] as String?)?.ifEmptyNull));
    }
    widget.api.myDuties().then((all) {
      if (!mounted) return;
      setState(() {
        _all = all;
        if (_rows.isEmpty) {
          _rows.add((flows: [for (final f in all) if (f['relevant'] == true) '${f['id']}'], person: null));
        }
      });
      _emit();
    }).catchError((e) {
      if (mounted) setState(() => _err = '$e');
    });
  }

  String _name(String id) {
    final f = _all?.where((x) => x['id'] == id).firstOrNull;
    return f == null ? id : '${f['icon'] ?? ''} ${f['name']}'.trim();
  }

  void _emit() => widget.onChanged([
        for (final r in _rows)
          if (r.flows.isNotEmpty) {'flows': r.flows, 'delegate': r.person ?? ''},
      ]);

  /// Chuyển quy trình [f] tới dòng [to] (-1 = "Chưa giao").
  void _move(String f, int to) {
    setState(() {
      for (var i = 0; i < _rows.length; i++) {
        _rows[i].flows.remove(f);
      }
      _pool.remove(f);
      if (to < 0) {
        _pool.add(f);
      } else {
        _rows[to].flows.add(f);
      }
    });
    _emit();
  }

  Future<void> _pickPerson(int i) async {
    final v = await pickUsers(context, widget.app, selected: [?_rows[i].person], single: true, title: tr('Người nhận thay'));
    if (v == null || v.isEmpty) return;
    setState(() => _rows[i] = (flows: _rows[i].flows, person: v.first));
    _emit();
  }

  /// Chạm vào quy trình: chọn nơi chuyển (cách không cần kéo).
  Future<void> _moveMenu(String f) async {
    final to = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(tr('Chuyển "{0}" tới', [_name(f)]), style: Theme.of(c).textTheme.titleMedium)),
          for (var i = 0; i < _rows.length; i++)
            if (!_rows[i].flows.contains(f))
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(_rows[i].person == null ? tr('Dòng {0} (chưa chọn người)', [i + 1]) : _userName(widget.app, _rows[i].person!)),
                onTap: () => Navigator.pop(c, i),
              ),
          ListTile(leading: const Icon(Icons.add_rounded), title: Text(tr('Dòng mới')), onTap: () => Navigator.pop(c, _rows.length)),
          if (!_pool.contains(f)) ListTile(leading: const Icon(Icons.remove_circle_outline_rounded), title: Text(tr('Bỏ ra (không ủy quyền)')), onTap: () => Navigator.pop(c, -1)),
        ]),
      ),
    );
    if (to == null) return;
    if (to == _rows.length) setState(() => _rows.add((flows: <String>[], person: null)));
    _move(f, to);
  }

  Future<void> _addOthers() async {
    final used = {..._pool, for (final r in _rows) ...r.flows};
    final others = [for (final f in _all ?? const <Map<String, dynamic>>[]) if (!used.contains(f['id'])) f];
    final sel = <String>{};
    final r = await showDialog<Set<String>>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(tr('Thêm quy trình khác')),
          content: SizedBox(
            width: 420,
            height: 420,
            child: others.isEmpty
                ? Center(child: Text(tr('Đã có hết các quy trình')))
                : ListView(children: [
                    for (final f in others)
                      CheckboxListTile(
                        dense: true,
                        value: sel.contains(f['id']),
                        title: Text('${f['icon'] ?? ''} ${f['name']}'.trim()),
                        onChanged: (v) => set(() => v == true ? sel.add('${f['id']}') : sel.remove('${f['id']}')),
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(d, sel), child: Text(tr('Thêm'))),
          ],
        ),
      ),
    );
    if (r == null || r.isEmpty) return;
    setState(() => (_rows.isEmpty ? _pool : _rows.last.flows).addAll(r));
    _emit();
  }

  Widget _chip(Pal pal, String f, int row) {
    final chip = Chip(
      avatar: Icon(Icons.drag_indicator_rounded, size: 16, color: pal.sub),
      label: Text(_name(f), style: TextStyle(fontSize: 13, color: pal.text)),
      visualDensity: VisualDensity.compact,
    );
    return LongPressDraggable<(String, int)>(
      data: (f, row),
      feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.9, child: chip)),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: GestureDetector(onTap: () => _moveMenu(f), child: chip),
    );
  }

  /// Vùng thả: một dòng (thẻ) hoặc "Chưa giao" (to = -1).
  Widget _target(Pal pal, int to, Widget Function(bool hot) child) => DragTarget<(String, int)>(
        onWillAcceptWithDetails: (d) => d.data.$2 != to,
        onAcceptWithDetails: (d) => _move(d.data.$1, to),
        builder: (_, cand, _) => child(cand.isNotEmpty),
      );

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final relevant = [for (final f in _all ?? const <Map<String, dynamic>>[]) if (f['relevant'] == true) '${f['id']}'];
    return InputDecorator(
      decoration: InputDecoration(labelText: widget.label, helperText: widget.hint, helperMaxLines: 3, errorText: widget.error, border: const OutlineInputBorder()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_all == null && _err == null) const LinearProgressIndicator(minHeight: 2),
        if (_err != null) Text(_err!, style: const TextStyle(color: kFlowRed)),
        if (_all != null && relevant.isEmpty && _rows.every((r) => r.flows.isEmpty))
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(tr('Bạn không có quy trình nào cần ủy quyền.'), style: TextStyle(color: pal.sub))),
        for (var i = 0; i < _rows.length; i++)
          _target(
            pal,
            i,
            (hot) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 10),
              decoration: BoxDecoration(
                color: hot ? pal.accent.withValues(alpha: 0.08) : pal.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hot ? pal.accent : pal.divider, width: hot ? 2 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _pickPerson(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          _rows[i].person == null
                              ? CircleAvatar(radius: 14, backgroundColor: pal.accent.withValues(alpha: 0.14), child: Icon(Icons.person_add_alt_1_rounded, size: 16, color: pal.accentText))
                              : Avatar(userId: _rows[i].person, name: _userName(widget.app, _rows[i].person!), size: 28, status: false),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _rows[i].person == null ? tr('Chọn người nhận thay') : _userName(widget.app, _rows[i].person!),
                              style: TextStyle(fontWeight: FontWeight.w700, color: _rows[i].person == null ? pal.accentText : pal.text),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  if (_rows.length > 1)
                    IconButton(
                      tooltip: tr('Xoá dòng (quy trình về "Chưa giao")'),
                      icon: Icon(Icons.close_rounded, size: 18, color: pal.sub),
                      onPressed: () {
                        setState(() => _pool.addAll(_rows.removeAt(i).flows));
                        _emit();
                      },
                    ),
                ]),
                const SizedBox(height: 4),
                if (_rows[i].flows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(tr('Kéo quy trình vào đây'), style: TextStyle(color: pal.sub, fontStyle: FontStyle.italic)),
                  )
                else
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final f in _rows[i].flows) _chip(pal, f, i)]),
              ]),
            ),
          ),
        if (_pool.isNotEmpty)
          _target(
            pal,
            -1,
            (hot) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hot ? pal.accent : kFlowOrange.withValues(alpha: 0.5)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tr('Chưa giao ({0}): kéo vào một dòng', [_pool.length]), style: const TextStyle(color: kFlowOrange, fontWeight: FontWeight.w600, fontSize: 12.5)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final f in _pool) _chip(pal, f, -1)]),
              ]),
            ),
          ),
        Wrap(spacing: 4, children: [
          TextButton.icon(
            onPressed: () => setState(() => _rows.add((flows: <String>[], person: null))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr('Thêm người nhận thay')),
          ),
          if (_all != null)
            TextButton.icon(onPressed: _addOthers, icon: const Icon(Icons.playlist_add_rounded, size: 18), label: Text(tr('Thêm quy trình khác'))),
        ]),
        Text(tr('Bấm giữ một quy trình rồi kéo sang người khác, hoặc chạm vào quy trình để chọn nơi chuyển.'), style: TextStyle(color: pal.sub, fontSize: 12)),
      ]),
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}

/// Giá trị trường Ủy quyền để xem (trang luồng, thẻ duyệt): bảng người → quy trình.
class DelegationValueView extends StatefulWidget {
  final AppState app;
  final FlowsApi api;
  final List value;
  const DelegationValueView({super.key, required this.app, required this.api, required this.value});
  @override
  State<DelegationValueView> createState() => _DelegationValueViewState();
}

class _DelegationValueViewState extends State<DelegationValueView> {
  Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    widget.api.flowNames().then((v) {
      if (mounted) setState(() => _names = {for (final f in v) '${f['id']}': '${f['icon'] ?? ''} ${f['name']}'.trim()});
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final rows = [for (final r in widget.value) if (r is Map && (r['flows'] as List? ?? const []).isNotEmpty) r];
    if (rows.isEmpty) return Text(tr('Không ủy quyền'), style: TextStyle(color: pal.sub));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(userId: '${r['delegate']}', name: _userName(widget.app, '${r['delegate']}'), size: 24, status: false),
              const SizedBox(width: 8),
              Expanded(child: Text(_userName(widget.app, '${r['delegate']}'), style: TextStyle(fontWeight: FontWeight.w700, color: pal.text))),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in (r['flows'] as List)) Chip(label: Text(_names['$f'] ?? '$f', style: const TextStyle(fontSize: 12.5)), visualDensity: VisualDensity.compact),
            ]),
          ]),
        ),
    ]);
  }
}
