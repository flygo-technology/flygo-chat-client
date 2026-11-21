import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_shell.dart';
import '../flows/flows_org.dart' show pickUsers;
import '../meet/meet_home.dart' show meetToast;
import '../pages/page_types.dart';
import '../pages/pages_api.dart';

// App riêng dựng trên loại trang (máy chủ: relay/meet-pages.mjs, trang không thuộc cuộc họp): "Bình chọn & Trắc nghiệm"
// (manifest native.screen = "binh_chon", loại trang poll), "Hỏi đáp & Thảo luận" ("hoi_dap", qa) và "Bảng ghi chú" ("ghi_chu", notes; khác app Ghi chú kiểu Keep).
// Danh sách: Của tôi / Được mời / Toàn công ty. Mở một mục = đúng phần xem của loại trang (như trong cuộc họp).

const kBinhChonScreen = 'binh_chon';
const kHoiDapScreen = 'hoi_dap';
const kGhiChuScreen = 'ghi_chu';

const _bg = Color(0xFF16181C);
const _card = Color(0xFF23262C);
const _sub = Color(0xFF9AA0A6);

/// Mở app theo native.screen của mini app (Bình chọn / Hỏi đáp).
Future<void> openPageApp(BuildContext context, MiniApp app) async {
  final type = switch (app.nativeScreen) { kHoiDapScreen => 'qa', kGhiChuScreen => 'notes', _ => 'poll' };
  await AppHost.of(context).open(key: app.id, title: app.name, builder: (_) => PageAppScreen(type: type, title: app.name));
}

class PageAppScreen extends StatefulWidget {
  final String type;
  final String title;
  const PageAppScreen({super.key, required this.type, required this.title});
  @override
  State<PageAppScreen> createState() => _PageAppScreenState();
}

class _PageAppScreenState extends State<PageAppScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);
  static const _scopes = ['mine', 'invited', 'company'];
  final _lists = <String, List<MeetPage>>{};
  final _err = <String, String>{};
  bool _creating = false;

  AppState get app => context.read<AppState>();
  PagesApi get api => PagesApi(app.calls);
  PageTypeSpec? get spec => pageTypeOf(widget.type);

  @override
  void initState() {
    super.initState();
    for (final s in _scopes) {
      _load(s);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load(String scope) async {
    try {
      final l = await api.listApp(widget.type, scope);
      l.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (mounted) {
        setState(() {
          _lists[scope] = l;
          _err.remove(scope);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _err[scope] = '$e');
    }
  }

  Future<void> _create() async {
    final s = spec;
    if (s?.create == null || _creating) return;
    final draft = await s!.create!(context, app.calls);
    if (draft == null || !mounted) return;
    final share = await _pickShare();
    if (share == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final d = await api.create(
        type: widget.type, title: draft.title, content: draft.content, init: draft.init, seconds: draft.seconds,
        appPage: true, visibility: share.$1, audience: share.$2,
      );
      await _load('mine');
      if (mounted) await _open(d.page);
    } catch (e) {
      if (mounted) meetToast(context, '$e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  /// Ai được tham gia: toàn công ty, hoặc chỉ những người được mời.
  Future<(String, List<String>)?> _pickShare() => showModalBottomSheet<(String, List<String>)>(
        context: context,
        backgroundColor: const Color(0xFF2D2E31),
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr('Ai được tham gia?'), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.business_outlined, color: Colors.white70),
              title: Text(tr('Toàn công ty'), style: const TextStyle(color: Colors.white)),
              subtitle: Text(tr('Mọi người thấy trong mục "Toàn công ty"'), style: const TextStyle(color: _sub)),
              onTap: () => Navigator.pop(ctx, ('company', const <String>[])),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined, color: Colors.white70),
              title: Text(tr('Chỉ người được mời'), style: const TextStyle(color: Colors.white)),
              subtitle: Text(tr('Chọn người từ danh bạ'), style: const TextStyle(color: _sub)),
              onTap: () async {
                final ids = await pickUsers(ctx, app, title: tr('Mời người tham gia'));
                if (ids != null && ctx.mounted) Navigator.pop(ctx, ('private', ids));
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Colors.white70),
              title: Text(tr('Chỉ mình tôi (soạn trước)'), style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ('private', const <String>[])),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );

  Future<void> _open(MeetPage p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PageAppDetail(page: p)));
    if (mounted) {
      for (final s in _scopes) {
        _load(s);
      }
    }
  }

  Widget _list(String scope) {
    final l = _lists[scope];
    if (_err[scope] != null && l == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err[scope]!, textAlign: TextAlign.center, style: const TextStyle(color: _sub))));
    }
    if (l == null) return const Center(child: CircularProgressIndicator());
    if (l.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            scope == 'mine'
                ? switch (widget.type) { 'qa' => tr('Bạn chưa tạo chủ đề hỏi đáp nào.'), 'notes' => tr('Bạn chưa tạo bảng ghi chú nào.'), _ => tr('Bạn chưa tạo bình chọn / trắc nghiệm nào.') }
                : scope == 'invited'
                    ? tr('Chưa có ai mời bạn.')
                    : tr('Chưa có mục nào cho toàn công ty.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _sub),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(scope),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: l.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = l[i];
          return Material(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: CircleAvatar(backgroundColor: (spec?.color ?? Colors.teal).withValues(alpha: .25), child: Icon(spec?.icon ?? Icons.article_outlined, color: spec?.color)),
              title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text(
                [
                  if (scope != 'mine' && p.ownerName.isNotEmpty) p.ownerName,
                  p.visibility == 'company' ? tr('toàn công ty') : tr('người được mời'),
                  _ago(p.updatedAt),
                ].where((x) => x.isNotEmpty).join(' · '),
                style: const TextStyle(color: _sub, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: _sub),
              onTap: () => _open(p),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          title: Text(widget.title),
          bottom: TabBar(controller: _tabs, tabs: [Tab(text: tr('Của tôi')), Tab(text: tr('Được mời')), Tab(text: tr('Toàn công ty'))]),
        ),
        body: TabBarView(controller: _tabs, children: [for (final s in _scopes) _list(s)]),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _creating ? null : _create,
          icon: _creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
          label: Text(switch (widget.type) { 'qa' => tr('Chủ đề mới'), 'notes' => tr('Bảng mới'), _ => tr('Tạo mới') }),
        ),
      );
}

String _ago(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return tr('vừa xong');
  if (d.inHours < 1) return tr('{0} phút trước', [d.inMinutes]);
  if (d.inDays < 1) return tr('{0} giờ trước', [d.inHours]);
  return tr('{0} ngày trước', [d.inDays]);
}

/// Một mục của app: đúng phần xem của loại trang, theo dõi thay đổi qua SSE (PageHost).
class PageAppDetail extends StatelessWidget {
  final MeetPage page;
  const PageAppDetail({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final api = PagesApi(app.calls);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: Text(page.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (page.owner == app.me?.id)
            PopupMenuButton<String>(
              onSelected: (a) async {
                if (a == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text(tr('Xoá "{0}"?', [page.title])),
                      content: Text(tr('Mọi câu trả lời và kết quả sẽ mất.')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Huỷ'))),
                        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Xoá'))),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await api.delete(page.id);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) meetToast(context, '$e');
                  }
                }
              },
              itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(tr('Xoá')))],
            ),
        ],
      ),
      body: PageHost(
        call: app.calls,
        id: page.id,
        builder: (context, ctx, spec) => spec == null ? unknownPageView(ctx) : spec.view(context, ctx),
      ),
    );
  }
}
