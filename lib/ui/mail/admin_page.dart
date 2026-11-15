// Quản trị Thư: mở từ mục Quản trị ở Trang chủ (Flygo ID cấp quyền admin app vn.flygo.mail) hoặc từ bộ chọn hộp thư.
// Máy tính: cột mục bên trái, nội dung bên phải (hộp thư: danh sách + chi tiết hai cột). Điện thoại: danh sách mục, bấm để mở trang.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_route.dart';
import 'admin_api.dart';
import 'model.dart';
import 'switcher.dart';
import 'widgets.dart';

class MailAdminStore extends ChangeNotifier {
  MailAdminStore(this.api);
  final MailAdminApi api;
  MaState? state;
  Object? error;
  List<MaAudit> log = [];
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait([api.load(), api.audit()]);
      state = r[0] as MaState;
      log = r[1] as List<MaAudit>;
      error = null;
    } catch (e) {
      error = e;
    }
    _notify();
  }

  /// Chạy một thao tác rồi tải lại; lỗi báo bằng thanh dưới màn hình.
  Future<bool> run(BuildContext context, Future<void> Function() f, [String? done]) async {
    final ms = ScaffoldMessenger.maybeOf(context);
    try {
      await f();
      await load();
      if (done != null) ms?.showSnackBar(SnackBar(content: Text(done)));
      return true;
    } catch (e) {
      ms?.showSnackBar(SnackBar(content: Text('$e')));
      return false;
    }
  }
}

const _sections = [
  ('mailboxes', 'Hộp thư', Icons.inbox_outlined, 'Hộp cá nhân, hộp dùng chung, nhóm; thành viên và quyền'),
  ('aliases', 'Bí danh', Icons.alternate_email, 'Địa chỉ phụ giao vào một hộp thư'),
  ('domains', 'Tên miền', Icons.language, 'Tên miền nhận / gửi thư và bản ghi DNS'),
  ('routing', 'Chuyển tiếp & catch-all', Icons.alt_route, 'Thư tới địa chỉ chưa có, quy tắc chuyển tiếp'),
  ('limits', 'Giới hạn gửi', Icons.speed, 'Số thư gửi mỗi giờ / ngày, dung lượng'),
  ('audit', 'Nhật ký', Icons.history, 'Ai đã đổi gì trong phần quản trị'),
];

String _kindName(String k) => const {'personal': 'Cá nhân', 'shared': 'Dùng chung', 'group': 'Nhóm'}[k] ?? k;
MailboxInfo _info(MaMailbox b) => MailboxInfo(b.id, name: b.name, kind: b.kind == 'personal' ? 'personal' : 'shared');
String _mb(num v) => v >= 1024 ? '${(v / 1024).toStringAsFixed(1)} GB' : '${v.round()} MB';
final _num = NumberFormat.decimalPattern('vi');

class MailAdminPage extends StatefulWidget {
  const MailAdminPage({super.key, required this.api, this.section, this.store});
  final MailAdminApi api;

  /// Mục mở sẵn (ảnh xem trước / liên kết); null = Hộp thư (máy tính) hoặc danh sách mục (điện thoại).
  final String? section;
  final MailAdminStore? store;

  @override
  State<MailAdminPage> createState() => MailAdminPageState();
}

class MailAdminPageState extends State<MailAdminPage> {
  late final MailAdminStore store = widget.store ?? MailAdminStore(widget.api);
  late String section = widget.section ?? 'mailboxes';
  String? selected;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  void dispose() {
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  void select(String? id) => setState(() => selected = id);
  void go(String s) => setState(() {
    section = s;
    selected = null;
  });

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 900;
          final s = store.state;
          if (s == null) {
            return Scaffold(
              backgroundColor: mc.bg,
              appBar: AppBar(title: const Text('Quản trị Thư'), backgroundColor: mc.bg),
              body: Center(
                child: store.error != null ? Text('${store.error}', style: TextStyle(color: mc.muted)) : const CircularProgressIndicator(),
              ),
            );
          }
          return wide ? _desktop(mc, s) : _phone(mc, s);
        },
      ),
    );
  }

  Widget _brand(MailColors mc) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: const Color(0xFF475569), borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 22),
      ),
      const SizedBox(width: 12),
      Text(
        'Quản trị Thư',
        style: TextStyle(fontSize: 20, color: mc.text, fontWeight: FontWeight.w500),
      ),
      if (store.api.demo) ...[const SizedBox(width: 8), const _DemoBadge()],
    ],
  );

  Widget _desktop(MailColors mc, MaState s) {
    final count = {'mailboxes': s.mailboxes.length, 'aliases': s.aliases.length, 'domains': s.domains.length, 'routing': s.rules.length};
    return Scaffold(
      backgroundColor: mc.bg,
      body: Column(
        children: [
          SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 12),
                if (Navigator.of(context).canPop()) IconButton(tooltip: 'Quay lại', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 8),
                _brand(mc),
                const Spacer(),
                IconButton(tooltip: 'Tải lại', icon: const Icon(Icons.refresh), onPressed: store.load),
                const SizedBox(width: 16),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 256,
                  child: ListView(
                    padding: const EdgeInsets.only(right: 8),
                    children: [for (final (id, name, icon, _) in _sections) _NavItem(icon: icon, label: name, count: count[id], selected: section == id, onTap: () => go(id))],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 16),
                    child: Material(
                      color: mc.surface,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: section == 'mailboxes'
                          ? Row(
                              children: [
                                Expanded(
                                  child: MailboxesSection(store: store, wide: true, selected: selected, onSelect: select),
                                ),
                                if (selected != null && s.box(selected!) != null) ...[
                                  VerticalDivider(width: 1, color: mc.line),
                                  SizedBox(
                                    width: 440,
                                    child: MailboxDetail(key: ValueKey(selected), store: store, id: selected!, onClose: () => select(null)),
                                  ),
                                ],
                              ],
                            )
                          : sectionBody(section, store, wide: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phone(MailColors mc, MaState s) {
    if (widget.section != null) return _PhoneSection(store: store, section: widget.section!);
    final sub = {
      'mailboxes': '${s.mailboxes.length} hộp · ${s.mailboxes.where((b) => b.kind == 'shared').length} dùng chung · ${s.mailboxes.where((b) => b.kind == 'group').length} nhóm',
      'aliases': '${s.aliases.length} bí danh',
      'domains': s.domains.map((d) => d.name).join(', '),
      'routing': '${s.rules.where((r) => r.enabled).length} quy tắc đang bật',
      'limits': '${s.limits.perHour}/giờ · ${s.limits.perDay}/ngày mỗi hộp',
      'audit': store.log.isEmpty ? '' : 'Gần nhất: ${_ago(store.log.first.at)}',
    };
    return Scaffold(
      backgroundColor: mc.bg,
      appBar: AppBar(
        backgroundColor: mc.bg,
        titleSpacing: 0,
        title: Row(
          children: [
            const Text('Quản trị Thư'),
            if (store.api.demo) ...[const SizedBox(width: 8), const _DemoBadge()],
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _SummaryCard(state: s),
          const SizedBox(height: 12),
          Material(
            color: mc.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _sections.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 64, color: mc.line),
                  ListTile(
                    leading: Icon(_sections[i].$3, color: mc.accent),
                    title: Text(
                      _sections[i].$2,
                      style: TextStyle(color: mc.text, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      sub[_sections[i].$1] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: mc.muted, fontSize: 12.5),
                    ),
                    trailing: Icon(Icons.chevron_right, color: mc.faint),
                    onTap: () => Navigator.of(context).push(
                      AppPageRoute(
                        builder: (_) => _PhoneSection(store: store, section: _sections[i].$1),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Một mục, toàn màn hình trên điện thoại.
class _PhoneSection extends StatelessWidget {
  const _PhoneSection({required this.store, required this.section});
  final MailAdminStore store;
  final String section;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final title = _sections.firstWhere((s) => s.$1 == section).$2;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        backgroundColor: mc.surface,
        appBar: AppBar(backgroundColor: mc.surface, title: Text(title)),
        body: store.state == null
            ? const Center(child: CircularProgressIndicator())
            : section == 'mailboxes'
            ? MailboxesSection(
                store: store,
                wide: false,
                onSelect: (id) {
                  if (id != null) {
                    Navigator.of(context).push(
                      AppPageRoute(
                        builder: (_) => _PhoneMailbox(store: store, id: id),
                      ),
                    );
                  }
                },
              )
            : sectionBody(section, store, wide: false),
      ),
    );
  }
}

class _PhoneMailbox extends StatelessWidget {
  const _PhoneMailbox({required this.store, required this.id});
  final MailAdminStore store;
  final String id;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return Scaffold(
      backgroundColor: mc.surface,
      appBar: AppBar(backgroundColor: mc.surface, title: const Text('Hộp thư')),
      body: ListenableBuilder(
        listenable: store,
        builder: (_, _) => MailboxDetail(store: store, id: id, onClose: () => Navigator.of(context).maybePop()),
      ),
    );
  }
}

Widget sectionBody(String section, MailAdminStore store, {required bool wide}) => switch (section) {
  'aliases' => AliasesSection(store: store, wide: wide),
  'domains' => DomainsSection(store: store, wide: wide),
  'routing' => RoutingSection(store: store, wide: wide),
  'limits' => LimitsSection(store: store, wide: wide),
  'audit' => AuditSection(store: store, wide: wide),
  _ => MailboxesSection(store: store, wide: wide),
};

// ---------------------------------------------------------------- phần dùng chung

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: const Color(0xFFFFE8A3), borderRadius: BorderRadius.circular(5)),
    child: const Text(
      'DEMO',
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00), letterSpacing: .5),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap, this.count});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? mc.accentSoft : Colors.transparent,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        child: InkWell(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 26),
                Icon(icon, size: 20, color: selected ? mc.accentText : mc.text),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 14, color: selected ? mc.accentText : mc.text, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
                if (count != null) Text('$count', style: TextStyle(fontSize: 12, color: selected ? mc.accentText : mc.muted)),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});
  final MaState state;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    Widget stat(String v, String l) => Expanded(
      child: Column(
        children: [
          Text(
            v,
            style: TextStyle(fontSize: 20, color: mc.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            l,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: mc.muted),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(color: mc.surface, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          stat('${state.mailboxes.where((b) => !b.disabled).length}', 'hộp đang dùng'),
          stat('${state.domains.where((d) => d.status == 'active').length}/${state.domains.length}', 'tên miền sẵn sàng'),
          stat(_num.format(state.usedToday), 'thư gửi hôm nay'),
        ],
      ),
    );
  }
}

/// Tiêu đề mục + nút chính (máy tính: hàng trên cùng; điện thoại: không có tiêu đề vì đã có AppBar).
class _Head extends StatelessWidget {
  const _Head({required this.title, required this.wide, this.sub, this.action, this.flush = false});
  final String title;
  final String? sub;
  final bool wide;
  final Widget? action;
  /// Mục đã có lề ngang (không thêm lề nữa).
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(flush ? 0 : (wide ? 24 : 16), wide ? 18 : 8, flush ? 0 : (wide ? 20 : 16), 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wide)
                  Text(
                    title,
                    style: TextStyle(fontSize: 20, color: mc.text, fontWeight: FontWeight.w500),
                  ),
                if (sub != null)
                  Padding(
                    padding: EdgeInsets.only(top: wide ? 2 : 0),
                    child: Text(sub!, style: TextStyle(fontSize: 13, color: mc.muted)),
                  ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

Widget _primary(String label, IconData icon, VoidCallback onTap) => FilledButton.icon(
  onPressed: onTap,
  icon: Icon(icon, size: 18),
  label: Text(label),
  style: FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
);

Widget _pill(BuildContext context, String t, {Color? color, IconData? icon}) {
  final mc = MailColors.of(context);
  final c = color ?? mc.muted;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color == null ? mc.chip : c.withValues(alpha: .13), borderRadius: BorderRadius.circular(6)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 3)],
        Flexible(
          child: Text(
            t,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: c, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

Color _ok(MailColors mc) => mc.dark ? const Color(0xFF34D399) : const Color(0xFF0F7B4A);
Color _warn(MailColors mc) => mc.dark ? const Color(0xFFFBBF24) : const Color(0xFFA16207);

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.icon, this.trailing, this.pad = true});
  final String title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;
  final bool pad;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border.all(color: mc.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: mc.muted), const SizedBox(width: 8)],
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 14, color: mc.text, fontWeight: FontWeight.w600),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Padding(padding: pad ? const EdgeInsets.fromLTRB(16, 4, 16, 14) : const EdgeInsets.only(bottom: 6), child: child),
        ],
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
  if (d.inHours < 24) return '${d.inHours} giờ trước';
  if (d.inDays < 7) return '${d.inDays} ngày trước';
  return DateFormat('dd/MM/yyyy').format(t);
}

Future<bool> _confirm(BuildContext context, String title, String body, {String ok = 'Đồng ý', bool danger = false, String? typeToConfirm}) async {
  final mc = MailColors.of(context);
  final ctl = TextEditingController();
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              if (typeToConfirm != null) ...[
                const SizedBox(height: 12),
                Text('Gõ "$typeToConfirm" để xác nhận:', style: TextStyle(fontSize: 13, color: mc.muted)),
                const SizedBox(height: 6),
                TextField(
                  controller: ctl,
                  autofocus: true,
                  onChanged: (_) => set(() {}),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: mc.danger) : null,
            onPressed: typeToConfirm == null || ctl.text.trim().toLowerCase() == typeToConfirm.toLowerCase() ? () => Navigator.pop(ctx, true) : null,
            child: Text(ok),
          ),
        ],
      ),
    ),
  );
  return r == true;
}

/// Ô chọn mức quyền.
class _LevelPicker extends StatelessWidget {
  const _LevelPicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Đổi quyền',
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final (v, d) in const [('read', 'Đọc thư, không gửi / không sửa'), ('send', 'Đọc, trả lời, gửi, sắp xếp thư'), ('admin', 'Thêm: cài đặt hộp và thành viên')])
        PopupMenuItem(
          value: v,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(accessName(v), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(d, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
    ],
    child: Row(mainAxisSize: MainAxisSize.min, children: [AccessChip(value), const Icon(Icons.arrow_drop_down, size: 18)]),
  );
}

// ---------------------------------------------------------------- Hộp thư

class MailboxesSection extends StatefulWidget {
  const MailboxesSection({super.key, required this.store, required this.wide, this.selected, this.onSelect});
  final MailAdminStore store;
  final bool wide;
  final String? selected;
  final ValueChanged<String?>? onSelect;

  @override
  State<MailboxesSection> createState() => _MailboxesSectionState();
}

class _MailboxesSectionState extends State<MailboxesSection> {
  String kind = '';
  final q = TextEditingController();

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final s = widget.store.state!;
    final l = q.text.trim().toLowerCase();
    final list = s.mailboxes.where((b) {
      if (kind == 'disabled' ? !b.disabled : kind.isNotEmpty && b.kind != kind) return false;
      return l.isEmpty || '${b.id} ${b.name} ${b.members.keys.join(' ')} ${s.aliasesOf(b.id).map((a) => a.address).join(' ')}'.toLowerCase().contains(l);
    }).toList();
    final wide = widget.wide;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(
          title: 'Hộp thư',
          wide: wide,
          sub: '${s.mailboxes.length} hộp · ${_mb(s.mailboxes.fold<double>(0, (a, b) => a + b.usedMb))} đã dùng',
          action: wide ? _primary('Tạo hộp thư', Icons.add, () => createMailboxDialog(context, widget.store)) : null,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
          child: TextField(
            controller: q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Tìm địa chỉ, tên, thành viên, bí danh',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: mc.surface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16, vertical: 8),
            children: [
              for (final (k, n) in const [('', 'Tất cả'), ('personal', 'Cá nhân'), ('shared', 'Dùng chung'), ('group', 'Nhóm'), ('disabled', 'Đã tắt')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(k.isEmpty ? n : '$n ${k == 'disabled' ? s.mailboxes.where((b) => b.disabled).length : s.mailboxes.where((b) => b.kind == k).length}'),
                    selected: kind == k,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => kind = k),
                  ),
                ),
            ],
          ),
        ),
        if (wide)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: mc.line)),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12, color: mc.muted, fontWeight: FontWeight.w600),
              child: const Row(
                children: [
                  SizedBox(width: 50),
                  Expanded(flex: 5, child: Text('Hộp thư')),
                  SizedBox(width: 104, child: Text('Loại')),
                  Expanded(flex: 3, child: Text('Thành viên')),
                  Expanded(flex: 2, child: Text('Bí danh')),
                  Expanded(flex: 3, child: Text('Dung lượng')),
                  SizedBox(width: 70, child: Text('Gửi hôm nay', textAlign: TextAlign.right)),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: list.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: mc.line, indent: wide ? 0 : 68),
            itemBuilder: (_, i) => _row(mc, s, list[i]),
          ),
        ),
        if (!wide)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(alignment: Alignment.centerRight, child: _primary('Tạo hộp thư', Icons.add, () => createMailboxDialog(context, widget.store))),
          ),
      ],
    );
  }

  Widget _row(MailColors mc, MaState s, MaMailbox b) {
    final aliases = s.aliasesOf(b.id);
    final quota = b.quotaMb ?? s.limits.quotaMb;
    final sel = widget.selected == b.id;
    final name = Row(
      children: [
        Flexible(
          child: Text(
            b.display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: b.disabled ? mc.faint : mc.text, fontWeight: FontWeight.w600),
          ),
        ),
        if (b.disabled) ...[const SizedBox(width: 6), _pill(context, 'Đã tắt', icon: Icons.block)],
      ],
    );
    final av = Opacity(opacity: b.disabled ? .45 : 1, child: MailboxAvatar(_info(b), size: 36));
    if (!widget.wide) {
      return ListTile(
        onTap: () => widget.onSelect?.call(b.id),
        leading: av,
        title: name,
        subtitle: Text(
          [b.id, if (b.kind != 'personal') '${_kindName(b.kind)} · ${b.members.length} thành viên', if (aliases.isNotEmpty) '${aliases.length} bí danh'].join(' · '),
          maxLines: 2,
          style: TextStyle(fontSize: 12.5, color: mc.muted),
        ),
      );
    }
    return Material(
      color: sel ? mc.sel : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelect?.call(sel ? null : b.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            children: [
              av,
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name,
                    Text(
                      b.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: mc.muted),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 104,
                child: Align(alignment: Alignment.centerLeft, child: _pill(context, _kindName(b.kind))),
              ),
              Expanded(
                flex: 3,
                child: b.members.isEmpty
                    ? Text('—', style: TextStyle(color: mc.faint))
                    : Row(
                        children: [
                          SizedBox(
                            width: 18.0 * b.members.length.clamp(0, 4) + 8,
                            height: 26,
                            child: Stack(
                              children: [
                                for (final (i, e) in b.members.keys.take(4).indexed)
                                  Positioned(
                                    left: i * 18.0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: sel ? mc.sel : mc.surface, width: 2),
                                      ),
                                      child: MailAvatar(MailPerson(e), size: 22),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text('${b.members.length}', style: TextStyle(fontSize: 12.5, color: mc.muted)),
                        ],
                      ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  aliases.isEmpty
                      ? '—'
                      : aliases.length == 1
                      ? aliases.first.address.split('@').first
                      : '${aliases.first.address.split('@').first} +${aliases.length - 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: aliases.isEmpty ? mc.faint : mc.muted),
                ),
              ),
              Expanded(
                flex: 3,
                child: b.kind == 'group'
                    ? Text('—', style: TextStyle(color: mc.faint))
                    : Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: (b.usedMb / quota).clamp(0, 1),
                                minHeight: 5,
                                backgroundColor: mc.line,
                                color: b.usedMb / quota > .85 ? mc.danger : mc.accent,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text('${_mb(b.usedMb)} / ${_mb(quota)}', style: TextStyle(fontSize: 11.5, color: mc.muted)),
                          ],
                        ),
                      ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  b.kind == 'group' ? '—' : '${b.sentToday}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: b.kind == 'group' ? mc.faint : mc.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> createMailboxDialog(BuildContext context, MailAdminStore store) async {
  final s = store.state!;
  final local = TextEditingController(), name = TextEditingController(), member = TextEditingController();
  var domain = s.domains.firstWhere((d) => d.primary, orElse: () => s.domains.first).name;
  var kind = 'personal';
  final members = <String, String>{};
  final mc = MailColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        void addMember() {
          final e = member.text.trim().toLowerCase();
          if (MailPerson(e).valid) set(() => members[e] = kind == 'group' ? 'read' : 'send');
          member.clear();
        }

        return AlertDialog(
          title: const Text('Tạo hộp thư'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'personal', label: Text('Cá nhân'), icon: Icon(Icons.person_outline)),
                      ButtonSegment(value: 'shared', label: Text('Dùng chung'), icon: Icon(Icons.groups_outlined)),
                      ButtonSegment(value: 'group', label: Text('Nhóm'), icon: Icon(Icons.forward_to_inbox_outlined)),
                    ],
                    selected: {kind},
                    onSelectionChanged: (v) => set(() => kind = v.first),
                  ),
                  const SizedBox(height: 8),
                  Text(switch (kind) {
                    'shared' => 'Một hộp thư nhiều người cùng dùng (vd hotro@). Mỗi thành viên có quyền Chỉ xem / Đọc và gửi / Quản lý.',
                    'group' => 'Thư gửi tới nhóm được chép vào hộp của từng thành viên (vd kinhdoanh@). Nhóm không có hộp riêng.',
                    _ => 'Hộp thư của một người; chủ hộp có toàn quyền và có thể uỷ quyền cho người khác.',
                  }, style: TextStyle(fontSize: 12.5, color: mc.muted)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: local,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: 'Địa chỉ', hintText: 'vd hotro', border: OutlineInputBorder(), isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: domain,
                        underline: const SizedBox.shrink(),
                        items: [for (final d in s.domains) DropdownMenuItem(value: d.name, child: Text('@${d.name}'))],
                        onChanged: (v) => set(() => domain = v!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Tên hiển thị', hintText: 'vd Hỗ trợ khách hàng', border: OutlineInputBorder(), isDense: true),
                  ),
                  if (kind != 'personal') ...[
                    const SizedBox(height: 16),
                    Text(
                      'Thành viên',
                      style: TextStyle(fontSize: 13, color: mc.text, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in members.keys) InputChip(label: Text(e), avatar: MailAvatar(MailPerson(e), size: 22), onDeleted: () => set(() => members.remove(e))),
                      ],
                    ),
                    TextField(
                      controller: member,
                      onSubmitted: (_) => addMember(),
                      decoration: InputDecoration(
                        hintText: 'Thêm email thành viên',
                        isDense: true,
                        suffixIcon: IconButton(icon: const Icon(Icons.person_add_alt), onPressed: addMember),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tạo')),
          ],
        );
      },
    ),
  );
  if (ok != true || local.text.trim().isEmpty || !context.mounted) return;
  final id = '${local.text.trim().toLowerCase()}@$domain';
  await store.run(context, () => store.api.createMailbox(id, name: name.text.trim(), kind: kind, members: members), 'Đã tạo $id');
}

class MailboxDetail extends StatefulWidget {
  const MailboxDetail({super.key, required this.store, required this.id, this.onClose});
  final MailAdminStore store;
  final String id;
  final VoidCallback? onClose;

  @override
  State<MailboxDetail> createState() => _MailboxDetailState();
}

class _MailboxDetailState extends State<MailboxDetail> {
  final member = TextEditingController(), alias = TextEditingController(), fwd = TextEditingController();
  late final hour = TextEditingController(), day = TextEditingController(), quota = TextEditingController();
  String newLevel = 'send';

  MailAdminStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final b = store.state!.box(widget.id);
    hour.text = '${b?.limitHour ?? ''}';
    day.text = '${b?.limitDay ?? ''}';
    quota.text = b?.quotaMb == null ? '' : '${b!.quotaMb! ~/ 1024}';
  }

  @override
  void dispose() {
    for (final c in [member, alias, fwd, hour, day, quota]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _members(MaMailbox b, Map<String, String> m, String done) => store.run(context, () => store.api.setMembers(b.id, m), done);

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final s = store.state!;
    final b = s.box(widget.id);
    if (b == null) {
      return Center(
        child: Text('Hộp thư đã bị xoá', style: TextStyle(color: mc.muted)),
      );
    }
    final aliases = s.aliasesOf(b.id);
    final domain = b.id.split('@').last;
    final q = b.quotaMb ?? s.limits.quotaMb;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(opacity: b.disabled ? .45 : 1, child: MailboxAvatar(_info(b), size: 56)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.display,
                    style: TextStyle(fontSize: 19, color: mc.text, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(b.id, style: TextStyle(fontSize: 13, color: mc.muted)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _pill(context, _kindName(b.kind)),
                      b.disabled
                          ? _pill(context, 'Đã tắt', icon: Icons.block, color: mc.danger)
                          : _pill(context, 'Đang hoạt động', icon: Icons.check_circle_outline, color: _ok(mc)),
                      if (b.created != null) _pill(context, 'Tạo ${DateFormat('dd/MM/yyyy').format(b.created!)}'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(tooltip: 'Đổi tên', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _rename(b)),
            if (widget.onClose != null && MediaQuery.sizeOf(context).width >= 900) IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close, size: 20), onPressed: widget.onClose),
          ],
        ),
        const SizedBox(height: 18),
        _Card(
          title: switch (b.kind) {
            'group' => 'Thành viên nhận thư',
            'shared' => 'Thành viên và quyền',
            _ => 'Uỷ quyền',
          },
          icon: Icons.group_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (b.kind == 'personal')
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      MailAvatar(MailPerson(b.id, b.name), size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${b.display} (chủ hộp)', style: TextStyle(fontSize: 13.5, color: mc.text)),
                      ),
                      const AccessChip('admin'),
                      const SizedBox(width: 22),
                    ],
                  ),
                ),
              for (final e in b.members.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      MailAvatar(MailPerson(e.key), size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: mc.text),
                        ),
                      ),
                      if (b.kind != 'group') _LevelPicker(value: e.value, onChanged: (v) => _members(b, {...b.members, e.key: v}, '${e.key}: ${accessName(v)}')),
                      IconButton(
                        tooltip: 'Gỡ',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _members(b, {...b.members}..remove(e.key), 'Đã gỡ ${e.key}'),
                      ),
                    ],
                  ),
                ),
              if (b.members.isEmpty && b.kind != 'personal') Text('Chưa có thành viên.', style: TextStyle(fontSize: 13, color: mc.muted)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: member,
                      onSubmitted: (_) => _addMember(b),
                      decoration: const InputDecoration(hintText: 'Thêm email', isDense: true, prefixIcon: Icon(Icons.person_add_alt, size: 18)),
                    ),
                  ),
                  if (b.kind != 'group') _LevelPicker(value: newLevel, onChanged: (v) => setState(() => newLevel = v)),
                  TextButton(onPressed: () => _addMember(b), child: const Text('Thêm')),
                ],
              ),
            ],
          ),
        ),
        _Card(
          title: 'Bí danh',
          icon: Icons.alternate_email,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in aliases)
                    InputChip(
                      label: Text(a.address, style: TextStyle(decoration: a.enabled ? null : TextDecoration.lineThrough)),
                      tooltip: a.enabled ? null : 'Đang tắt',
                      onDeleted: () => store.run(context, () => store.api.deleteAlias(a.address), 'Đã xoá ${a.address}'),
                    ),
                  if (aliases.isEmpty) Text('Chưa có bí danh.', style: TextStyle(fontSize: 13, color: mc.muted)),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: alias,
                onSubmitted: (_) => _addAlias(b, domain),
                decoration: InputDecoration(
                  hintText: 'Thêm bí danh',
                  isDense: true,
                  suffixText: '@$domain',
                  suffixIcon: IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => _addAlias(b, domain)),
                ),
              ),
            ],
          ),
        ),
        if (b.kind != 'group')
          _Card(
            title: 'Tự chuyển tiếp',
            icon: Icons.forward_to_inbox_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in b.forward)
                  Row(
                    children: [
                      Icon(Icons.subdirectory_arrow_right, size: 18, color: mc.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f, style: TextStyle(fontSize: 13.5, color: mc.text)),
                      ),
                      IconButton(
                        tooltip: 'Bỏ',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => store.run(
                          context,
                          () => store.api.updateMailbox(b.id, {
                            'forward': [...b.forward]..remove(f),
                          }),
                        ),
                      ),
                    ],
                  ),
                TextField(
                  controller: fwd,
                  onSubmitted: (_) => _addForward(b),
                  decoration: InputDecoration(
                    hintText: 'Chuyển tiếp mọi thư đến tới…',
                    isDense: true,
                    suffixIcon: IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => _addForward(b)),
                  ),
                ),
                if (b.forward.isNotEmpty)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: b.keepCopy,
                    title: const Text('Giữ bản sao trong hộp này'),
                    onChanged: (v) => store.run(context, () => store.api.updateMailbox(b.id, {'keep_copy': v})),
                  ),
              ],
            ),
          ),
        if (b.kind != 'group')
          _Card(
            title: 'Giới hạn và dung lượng',
            icon: Icons.speed,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Đã dùng ${_mb(b.usedMb)} / ${_mb(q)}', style: TextStyle(fontSize: 13, color: mc.text)),
                    ),
                    Text('Gửi hôm nay: ${b.sentToday}/${b.limitDay ?? s.limits.perDay}', style: TextStyle(fontSize: 13, color: mc.muted)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: (b.usedMb / q).clamp(0, 1), minHeight: 6, backgroundColor: mc.line, color: b.usedMb / q > .85 ? mc.danger : mc.accent),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _numField(hour, 'Thư / giờ', '${s.limits.perHour}')),
                    const SizedBox(width: 8),
                    Expanded(child: _numField(day, 'Thư / ngày', '${s.limits.perDay}')),
                    const SizedBox(width: 8),
                    Expanded(child: _numField(quota, 'Dung lượng (GB)', '${s.limits.quotaMb ~/ 1024}')),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Để trống = theo mặc định của hệ thống.', style: TextStyle(fontSize: 11.5, color: mc.faint)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => store.run(
                      context,
                      () => store.api.updateMailbox(b.id, {
                        'limit_hour': int.tryParse(hour.text.trim()),
                        'limit_day': int.tryParse(day.text.trim()),
                        'quota_mb': int.tryParse(quota.text.trim()) == null ? null : int.parse(quota.text.trim()) * 1024,
                      }),
                      'Đã lưu giới hạn',
                    ),
                    child: const Text('Lưu giới hạn'),
                  ),
                ),
              ],
            ),
          ),
        _Card(
          title: 'Vùng nguy hiểm',
          icon: Icons.warning_amber_rounded,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: Icon(b.disabled ? Icons.play_circle_outline : Icons.block, size: 18),
                label: Text(b.disabled ? 'Bật lại hộp thư' : 'Tắt hộp thư'),
                onPressed: () async {
                  if (!b.disabled &&
                      !await _confirm(context, 'Tắt ${b.id}?', 'Hộp thư sẽ không nhận và không gửi được thư. Thư cũ còn nguyên, bật lại lúc nào cũng được.', ok: 'Tắt')) {
                    return;
                  }
                  if (context.mounted) await store.run(context, () => store.api.updateMailbox(b.id, {'status': b.disabled ? 'active' : 'disabled'}));
                },
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: mc.danger,
                  side: BorderSide(color: mc.danger.withValues(alpha: .5)),
                ),
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('Xoá hộp thư'),
                onPressed: () async {
                  if (!await _confirm(
                    context,
                    'Xoá vĩnh viễn ${b.id}?',
                    'Toàn bộ thư, tệp đính kèm, bí danh và quyền của hộp này bị xoá, không khôi phục được.',
                    ok: 'Xoá vĩnh viễn',
                    danger: true,
                    typeToConfirm: b.id,
                  )) {
                    return;
                  }
                  if (!context.mounted) return;
                  if (await store.run(context, () => store.api.deleteMailbox(b.id), 'Đã xoá ${b.id}')) widget.onClose?.call();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numField(TextEditingController c, String label, String hint) => TextField(
    controller: c,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder()),
  );

  void _addMember(MaMailbox b) {
    final e = member.text.trim().toLowerCase();
    if (!MailPerson(e).valid) return;
    member.clear();
    _members(b, {...b.members, e: b.kind == 'group' ? 'read' : newLevel}, 'Đã thêm $e');
  }

  void _addAlias(MaMailbox b, String domain) {
    final v = alias.text.trim().toLowerCase();
    if (v.isEmpty) return;
    alias.clear();
    final a = v.contains('@') ? v : '$v@$domain';
    store.run(context, () => store.api.saveAlias(MaAlias(a, b.id)), 'Đã thêm bí danh $a');
  }

  void _addForward(MaMailbox b) {
    final v = fwd.text.trim().toLowerCase();
    if (!MailPerson(v).valid) return;
    fwd.clear();
    store.run(
      context,
      () => store.api.updateMailbox(b.id, {
        'forward': [...b.forward, v],
      }),
      'Thư đến sẽ được chuyển tiếp tới $v',
    );
  }

  Future<void> _rename(MaMailbox b) async {
    final c = TextEditingController(text: b.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tên hiển thị'),
        content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Lưu')),
        ],
      ),
    );
    if (v != null && mounted) await store.run(context, () => store.api.updateMailbox(b.id, {'name': v.trim()}));
  }
}

// ---------------------------------------------------------------- Bí danh

class AliasesSection extends StatelessWidget {
  const AliasesSection({super.key, required this.store, required this.wide});
  final MailAdminStore store;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final s = store.state!;
    final list = [...s.aliases]..sort((a, b) => a.address.compareTo(b.address));
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _Head(
          title: 'Bí danh',
          wide: wide,
          sub: 'Thư gửi tới bí danh được giao vào hộp đích. Trả lời vẫn đi từ địa chỉ của hộp đích.',
          action: _primary('Thêm bí danh', Icons.add, () => aliasDialog(context, store)),
        ),
        for (final a in list)
          ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
            leading: Icon(Icons.alternate_email, color: a.enabled ? mc.accent : mc.faint),
            title: Text(
              a.address,
              style: TextStyle(color: a.enabled ? mc.text : mc.faint, fontWeight: FontWeight.w500),
            ),
            subtitle: Row(
              children: [
                Icon(Icons.arrow_forward, size: 14, color: mc.muted),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${s.box(a.target)?.display ?? a.target} · ${a.target}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: mc.muted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: a.enabled,
                  onChanged: (v) => store.run(context, () => store.api.saveAlias(MaAlias(a.address, a.target, enabled: v))),
                ),
                IconButton(
                  tooltip: 'Xoá',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () async {
                    if (await _confirm(context, 'Xoá ${a.address}?', 'Thư gửi tới địa chỉ này sẽ theo cài đặt catch-all của tên miền.', ok: 'Xoá', danger: true) &&
                        context.mounted) {
                      await store.run(context, () => store.api.deleteAlias(a.address), 'Đã xoá ${a.address}');
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Future<void> aliasDialog(BuildContext context, MailAdminStore store) async {
  final s = store.state!;
  final c = TextEditingController();
  var domain = s.domains.firstWhere((d) => d.primary, orElse: () => s.domains.first).name;
  String? target;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Thêm bí danh'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Bí danh', hintText: 'vd info', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: domain,
                    underline: const SizedBox.shrink(),
                    items: [for (final d in s.domains) DropdownMenuItem(value: d.name, child: Text('@${d.name}'))],
                    onChanged: (v) => set(() => domain = v!),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: target,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Giao vào hộp', border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final b in s.mailboxes.where((b) => !b.disabled))
                    DropdownMenuItem(
                      value: b.id,
                      child: Text('${b.display} · ${b.id}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => set(() => target = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: target == null ? null : () => Navigator.pop(ctx, true), child: const Text('Thêm')),
        ],
      ),
    ),
  );
  if (ok != true || c.text.trim().isEmpty || target == null || !context.mounted) return;
  final a = '${c.text.trim().toLowerCase()}@$domain';
  await store.run(context, () => store.api.saveAlias(MaAlias(a, target!)), 'Đã thêm $a');
}

// ---------------------------------------------------------------- Tên miền

class DomainsSection extends StatelessWidget {
  const DomainsSection({super.key, required this.store, required this.wide});
  final MailAdminStore store;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final s = store.state!;
    return ListView(
      padding: EdgeInsets.fromLTRB(0, 0, 0, 32),
      children: [
        _Head(
          title: 'Tên miền',
          wide: wide,
          sub: 'Tên miền nhận thư qua Cloudflare Email Routing và gửi qua Email Service.',
          action: _primary('Thêm tên miền', Icons.add, () => _add(context)),
        ),
        for (final d in s.domains)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
            child: _Card(
              title: d.name,
              icon: Icons.language,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (d.primary) ...[_pill(context, 'Chính'), const SizedBox(width: 6)],
                  d.status == 'active'
                      ? _pill(context, 'Sẵn sàng', icon: Icons.check_circle_outline, color: _ok(mc))
                      : _pill(context, 'Chờ DNS', icon: Icons.schedule, color: _warn(mc)),
                  PopupMenuButton<String>(
                    tooltip: 'Thao tác',
                    onSelected: (v) async {
                      if (v == 'verify') await store.run(context, () => store.api.verifyDomain(d.name), 'Đã kiểm tra lại DNS của ${d.name}');
                      if (v == 'primary') {
                        for (final x in s.domains) {
                          x.primary = x.name == d.name;
                        }
                        if (context.mounted) await store.run(context, () => store.api.updateDomain(d));
                      }
                      if (v == 'delete' &&
                          context.mounted &&
                          await _confirm(
                            context,
                            'Gỡ ${d.name}?',
                            'Ngừng nhận thư cho tên miền này. Hộp thư trên tên miền vẫn giữ dữ liệu.',
                            ok: 'Gỡ',
                            danger: true,
                            typeToConfirm: d.name,
                          ) &&
                          context.mounted) {
                        await store.run(context, () => store.api.deleteDomain(d.name), 'Đã gỡ ${d.name}');
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'verify', child: Text('Kiểm tra lại DNS')),
                      if (!d.primary) const PopupMenuItem(value: 'primary', child: Text('Đặt làm tên miền chính')),
                      const PopupMenuItem(value: 'delete', child: Text('Gỡ tên miền')),
                    ],
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      for (final (k, n) in const [('mx', 'MX (nhận thư)'), ('spf', 'SPF'), ('dkim', 'DKIM'), ('dmarc', 'DMARC')])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(d.dns[k] == true ? Icons.check_circle : Icons.error_outline, size: 16, color: d.dns[k] == true ? _ok(mc) : _warn(mc)),
                            const SizedBox(width: 4),
                            Text(n, style: TextStyle(fontSize: 13, color: mc.text)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${s.mailboxes.where((b) => b.id.endsWith('@${d.name}')).length} hộp thư · ${s.aliases.where((a) => a.address.endsWith('@${d.name}')).length} bí danh · thư tới địa chỉ chưa có: ${_catchAllName(d, s)}',
                    style: TextStyle(fontSize: 12.5, color: mc.muted),
                  ),
                  if (d.dns.values.any((v) => !v)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: mc.surface2, borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bản ghi DNS còn thiếu',
                            style: TextStyle(fontSize: 12.5, color: mc.text, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          if (d.dns['mx'] != true) _rec(mc, 'MX', d.name, 'route1.mx.cloudflare.net (ưu tiên 10)'),
                          if (d.dns['spf'] != true) _rec(mc, 'TXT', d.name, 'v=spf1 include:_spf.mx.cloudflare.net ~all'),
                          if (d.dns['dkim'] != true) _rec(mc, 'TXT', 'cf2024-1._domainkey.${d.name}', 'v=DKIM1; k=rsa; p=… (Cloudflare cấp)'),
                          if (d.dns['dmarc'] != true) _rec(mc, 'TXT', '_dmarc.${d.name}', 'v=DMARC1; p=quarantine; rua=mailto:dmarc@${d.name}'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _rec(MailColors mc, String type, String name, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            type,
            style: TextStyle(fontSize: 12, color: mc.muted, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(name, style: TextStyle(fontSize: 12, color: mc.muted)),
              SelectableText(value, style: TextStyle(fontSize: 12.5, color: mc.text, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _add(BuildContext context) async {
    final c = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm tên miền'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Tên miền', hintText: 'vd mail.congty.vn', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 10),
              const Text(
                'Nên dùng tên miền phụ (vd mail.congty.vn) để không ảnh hưởng hộp thư đang chạy ở nhà cung cấp khác. Sau khi thêm, làm theo hướng dẫn bản ghi DNS.',
                style: TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Thêm')),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty && context.mounted) await store.run(context, () => store.api.addDomain(v.trim()), 'Đã thêm ${v.trim()}');
  }
}

String _catchAllName(MaDomain d, MaState s) => switch (d.catchAll) {
  'mailbox' => 'giao vào ${s.box(d.catchAllTarget)?.display ?? d.catchAllTarget}',
  'drop' => 'bỏ im lặng',
  _ => 'trả lại người gửi',
};

// ---------------------------------------------------------------- Chuyển tiếp & catch-all

class RoutingSection extends StatelessWidget {
  const RoutingSection({super.key, required this.store, required this.wide});
  final MailAdminStore store;
  final bool wide;

  static const _fields = {'to': 'Người nhận', 'from': 'Người gửi', 'subject': 'Tiêu đề'};
  static const _ops = {'is': 'là', 'contains': 'chứa', 'ends': 'kết thúc bằng'};

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final s = store.state!;
    final h = EdgeInsets.symmetric(horizontal: wide ? 24 : 16);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _Head(title: 'Chuyển tiếp & catch-all', wide: wide, sub: 'Quy tắc chạy theo thứ tự trước khi thư vào hộp; thư tới địa chỉ chưa có theo cài đặt catch-all.'),
        Padding(
          padding: h,
          child: _Card(
            title: 'Thư tới địa chỉ chưa có (catch-all)',
            icon: Icons.all_inbox_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in s.domains)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        SizedBox(
                          width: wide ? 140 : double.infinity,
                          child: Text(
                            '*@${d.name}',
                            style: TextStyle(fontSize: 13.5, color: mc.text, fontWeight: FontWeight.w500),
                          ),
                        ),
                        DropdownButton<String>(
                          value: d.catchAll,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 'reject', child: Text('Trả lại người gửi')),
                            DropdownMenuItem(value: 'mailbox', child: Text('Giao vào hộp…')),
                            DropdownMenuItem(value: 'drop', child: Text('Bỏ im lặng')),
                          ],
                          onChanged: (v) {
                            d.catchAll = v!;
                            if (v == 'mailbox' && d.catchAllTarget.isEmpty) d.catchAllTarget = s.mailboxes.first.id;
                            store.run(context, () => store.api.updateDomain(d));
                          },
                        ),
                        if (d.catchAll == 'mailbox')
                          DropdownButton<String>(
                            value: s.box(d.catchAllTarget) != null ? d.catchAllTarget : null,
                            underline: const SizedBox.shrink(),
                            hint: const Text('Chọn hộp'),
                            items: [for (final b in s.mailboxes.where((b) => !b.disabled && b.kind != 'group')) DropdownMenuItem(value: b.id, child: Text(b.id))],
                            onChanged: (v) {
                              d.catchAllTarget = v!;
                              store.run(context, () => store.api.updateDomain(d));
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: h,
          child: _Card(
            title: 'Quy tắc chuyển tiếp',
            icon: Icons.alt_route,
            pad: false,
            trailing: TextButton.icon(onPressed: () => ruleDialog(context, store), icon: const Icon(Icons.add, size: 18), label: const Text('Thêm quy tắc')),
            child: Column(
              children: [
                if (s.rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Chưa có quy tắc.', style: TextStyle(color: mc.muted)),
                  ),
                for (final (i, r) in s.rules.indexed) ...[
                  if (i > 0) Divider(height: 1, color: mc.line),
                  ListTile(
                    onTap: () => ruleDialog(context, store, r),
                    leading: CircleAvatar(
                      radius: 15,
                      backgroundColor: mc.chip,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(fontSize: 12, color: mc.muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                    title: Text(
                      r.name.isEmpty ? 'Quy tắc ${i + 1}' : r.name,
                      style: TextStyle(color: r.enabled ? mc.text : mc.faint, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text.rich(
                      TextSpan(
                        style: TextStyle(fontSize: 12.5, color: mc.muted),
                        children: [
                          TextSpan(text: 'Nếu ${_fields[r.field]!.toLowerCase()} ${_ops[r.op]} '),
                          TextSpan(
                            text: r.value,
                            style: TextStyle(color: mc.text, fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: switch (r.action) {
                              'forward' => ', thì chép tới ',
                              'deliver' => ', thì giao vào ',
                              _ => ', thì bỏ thư',
                            },
                          ),
                          if (r.action != 'drop')
                            TextSpan(
                              text: r.target,
                              style: TextStyle(color: mc.text, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ),
                    trailing: Switch(value: r.enabled, onChanged: (v) => store.run(context, () => store.api.saveRule(r..enabled = v))),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> ruleDialog(BuildContext context, MailAdminStore store, [MaRule? edit]) async {
  final r = edit == null ? MaRule() : MaRule.fromJson(edit.toJson());
  final name = TextEditingController(text: r.name), value = TextEditingController(text: r.value), target = TextEditingController(text: r.target);
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(edit == null ? 'Thêm quy tắc' : 'Sửa quy tắc'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Tên quy tắc', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Nếu  '),
                  DropdownButton<String>(
                    value: r.field,
                    items: [for (final e in RoutingSection._fields.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => set(() => r.field = v!),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: r.op,
                    items: [for (final e in RoutingSection._ops.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => set(() => r.op = v!),
                  ),
                ],
              ),
              TextField(
                controller: value,
                decoration: const InputDecoration(hintText: 'vd @einvoice.example', isDense: true),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Thì  '),
                  DropdownButton<String>(
                    value: r.action,
                    items: const [
                      DropdownMenuItem(value: 'forward', child: Text('Chép tới (vẫn giữ thư)')),
                      DropdownMenuItem(value: 'deliver', child: Text('Giao vào hộp khác')),
                      DropdownMenuItem(value: 'drop', child: Text('Bỏ thư')),
                    ],
                    onChanged: (v) => set(() => r.action = v!),
                  ),
                ],
              ),
              if (r.action != 'drop')
                TextField(
                  controller: target,
                  decoration: const InputDecoration(hintText: 'Địa chỉ / hộp đích', isDense: true),
                ),
            ],
          ),
        ),
        actions: [
          if (edit != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: Text('Xoá', style: TextStyle(color: MailColors.of(ctx).danger)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Lưu')),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (res == 'delete') {
    await store.run(context, () => store.api.deleteRule(r.id), 'Đã xoá quy tắc');
  } else if (res == 'save' && value.text.trim().isNotEmpty) {
    r
      ..name = name.text.trim()
      ..value = value.text.trim()
      ..target = target.text.trim().toLowerCase();
    await store.run(context, () => store.api.saveRule(r), 'Đã lưu quy tắc');
  }
}

// ---------------------------------------------------------------- Giới hạn gửi

class LimitsSection extends StatefulWidget {
  const LimitsSection({super.key, required this.store, required this.wide});
  final MailAdminStore store;
  final bool wide;

  @override
  State<LimitsSection> createState() => _LimitsSectionState();
}

class _LimitsSectionState extends State<LimitsSection> {
  late final MaLimits l = MaLimits.fromJson(widget.store.state!.limits.toJson());
  late final c = {
    'h': TextEditingController(text: '${l.perHour}'),
    'd': TextEditingController(text: '${l.perDay}'),
    'r': TextEditingController(text: '${l.maxRecipients}'),
    'a': TextEditingController(text: '${l.maxAttachmentMb}'),
    'q': TextEditingController(text: '${l.quotaMb ~/ 1024}'),
  };

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final s = widget.store.state!;
    final wide = widget.wide;
    const free = 3000;
    Widget f(String k, String label, String suffix) => SizedBox(
      width: wide ? 200 : double.infinity,
      child: TextField(
        controller: c[k],
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true, border: const OutlineInputBorder()),
      ),
    );
    final custom = s.mailboxes.where((b) => b.limitHour != null || b.limitDay != null || b.quotaMb != null).toList();
    final month = s.monthSent;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 0, wide ? 24 : 16, 32),
      children: [
        _Head(title: 'Giới hạn gửi', wide: wide, flush: true, sub: 'Chặn hộp thư bị lộ mật khẩu gửi thư rác hàng loạt và giữ chi phí trong tầm kiểm soát.'),
        _Card(
          title: month == null ? 'Cả hệ thống' : 'Cả hệ thống tháng này',
          icon: Icons.insights_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      month == null ? 'Hôm nay đã gửi ${_num.format(s.usedToday)} thư' : '${_num.format(month)} / ${_num.format(free)} thư miễn phí',
                      style: TextStyle(fontSize: 14, color: mc.text, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (month != null) Text('Hôm nay: ${_num.format(s.usedToday)}', style: TextStyle(fontSize: 13, color: mc.muted)),
                ],
              ),
              if (month != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (month / free).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: mc.line,
                    color: month > free * .9 ? mc.danger : mc.accent,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text('Quá mức miễn phí: khoảng 0,35 USD / 1.000 thư (Cloudflare Email Service).', style: TextStyle(fontSize: 12, color: mc.faint)),
            ],
          ),
        ),
        _Card(
          title: 'Mặc định cho mỗi hộp thư',
          icon: Icons.tune,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  f('h', 'Thư gửi mỗi giờ', 'thư'),
                  f('d', 'Thư gửi mỗi ngày', 'thư'),
                  f('r', 'Người nhận mỗi thư', 'người'),
                  f('a', 'Tệp đính kèm tối đa', 'MB'),
                  f('q', 'Dung lượng hộp thư', 'GB'),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: l.external,
                title: const Text('Cho gửi ra ngoài tên miền của mình'),
                subtitle: const Text('Tắt: chỉ gửi được trong nội bộ (thử nghiệm).'),
                onChanged: (v) => setState(() => l.external = v),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    int n(String k, int d) => int.tryParse(c[k]!.text.trim()) ?? d;
                    l
                      ..perHour = n('h', l.perHour)
                      ..perDay = n('d', l.perDay)
                      ..maxRecipients = n('r', l.maxRecipients)
                      ..maxAttachmentMb = n('a', l.maxAttachmentMb)
                      ..quotaMb = n('q', l.quotaMb ~/ 1024) * 1024;
                    widget.store.run(context, () => widget.store.api.saveLimits(l), 'Đã lưu giới hạn mặc định');
                  },
                  child: const Text('Lưu'),
                ),
              ),
            ],
          ),
        ),
        _Card(
          title: 'Hộp có giới hạn riêng',
          icon: Icons.rule,
          pad: false,
          child: Column(
            children: [
              if (custom.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Không có. Đặt giới hạn riêng trong trang chi tiết hộp thư.', style: TextStyle(color: mc.muted)),
                ),
              for (final b in custom)
                ListTile(
                  leading: MailboxAvatar(_info(b), size: 32),
                  title: Text(b.display, style: TextStyle(color: mc.text, fontSize: 14)),
                  subtitle: Text(
                    [if (b.limitHour != null) '${b.limitHour}/giờ', if (b.limitDay != null) '${b.limitDay}/ngày', if (b.quotaMb != null) _mb(b.quotaMb!)].join(' · '),
                    style: TextStyle(color: mc.muted, fontSize: 12.5),
                  ),
                  trailing: Text('hôm nay ${b.sentToday}', style: TextStyle(color: mc.muted, fontSize: 12.5)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Nhật ký

const _actions = {
  'mailbox.create': ('Tạo hộp thư', Icons.add_box_outlined),
  'mailbox.update': ('Sửa hộp thư', Icons.edit_outlined),
  'mailbox.disable': ('Tắt hộp thư', Icons.block),
  'mailbox.enable': ('Bật lại hộp thư', Icons.play_circle_outline),
  'mailbox.delete': ('Xoá hộp thư', Icons.delete_forever_outlined),
  'members.set': ('Đổi thành viên / quyền', Icons.group_outlined),
  'alias.create': ('Thêm bí danh', Icons.alternate_email),
  'alias.update': ('Sửa bí danh', Icons.alternate_email),
  'alias.disable': ('Tắt bí danh', Icons.alternate_email),
  'alias.delete': ('Xoá bí danh', Icons.alternate_email),
  'domain.add': ('Thêm tên miền', Icons.language),
  'domain.update': ('Sửa tên miền', Icons.language),
  'domain.verify': ('Kiểm tra DNS', Icons.language),
  'domain.delete': ('Gỡ tên miền', Icons.language),
  'rule.create': ('Thêm quy tắc', Icons.alt_route),
  'rule.update': ('Sửa quy tắc', Icons.alt_route),
  'rule.delete': ('Xoá quy tắc', Icons.alt_route),
  'limits.update': ('Đổi giới hạn', Icons.speed),
};

class AuditSection extends StatefulWidget {
  const AuditSection({super.key, required this.store, required this.wide});
  final MailAdminStore store;
  final bool wide;

  @override
  State<AuditSection> createState() => _AuditSectionState();
}

class _AuditSectionState extends State<AuditSection> {
  final q = TextEditingController();

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final l = q.text.trim().toLowerCase();
    final log = widget.store.log.where((a) => l.isEmpty || '${a.actor} ${a.action} ${_actions[a.action]?.$1 ?? ''} ${a.target} ${a.detail}'.toLowerCase().contains(l)).toList();
    final wide = widget.wide;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(title: 'Nhật ký', wide: wide, sub: 'Mọi thay đổi trong phần quản trị, giữ 1 năm.'),
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 0, wide ? 24 : 16, 8),
          child: TextField(
            controller: q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Lọc theo người, hộp thư, thao tác',
              prefixIcon: const Icon(Icons.filter_list, size: 20),
              isDense: true,
              filled: true,
              fillColor: mc.surface2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: log.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: mc.line, indent: wide ? 24 : 16, endIndent: wide ? 24 : 16),
            itemBuilder: (_, i) {
              final a = log[i];
              final (name, icon) = _actions[a.action] ?? (a.action, Icons.history);
              return ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: mc.chip, shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: mc.muted),
                ),
                title: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 13.5, color: mc.text),
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: '  ${a.target}'),
                    ],
                  ),
                ),
                subtitle: Text([a.actor, if (a.detail.isNotEmpty) a.detail].join(' · '), maxLines: 2, style: TextStyle(fontSize: 12.5, color: mc.muted)),
                trailing: Text(wide ? DateFormat('HH:mm dd/MM/yyyy').format(a.at) : _ago(a.at), style: TextStyle(fontSize: 12, color: mc.faint)),
              );
            },
          ),
        ),
      ],
    );
  }
}
