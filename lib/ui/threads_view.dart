import '../i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'chat_page.dart' show openThread;
import 'common.dart';
import 'home_page.dart' show ChatHost;
import 'panes/pane_layout.dart';
import 'panes/pane_view.dart';
import 'sub_channel.dart';
import 'theme.dart';

typedef _Work = ({MmPost root, int replies, int lastAt});

/// Tab "Luồng riêng": các luồng công việc riêng và luồng riêng tư còn dang dở, có nút đóng luồng.
class ThreadsView extends StatefulWidget {
  final Widget? header;
  final String query;
  final double bottomPadding;
  /// Trong tab "Luồng riêng" của Chat: một danh sách luồng công khai rồi luồng bí mật, chỉ luồng chưa đóng (không có tab con).
  final bool openOnly;
  const ThreadsView({super.key, this.header, this.query = '', this.bottomPadding = 0, this.openOnly = false});
  @override
  State<ThreadsView> createState() => _ThreadsViewState();
}

class _ThreadsViewState extends State<ThreadsView> {
  /// Các dòng đang đóng / mở lại (id kênh luồng riêng tư hoặc id tin gốc): nút hiện vòng xoay.
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    context.read<AppState>().loadWorkThreads();
  }

  bool _match(String text) {
    final q = widget.query.trim().toLowerCase();
    return q.isEmpty || text.toLowerCase().contains(q);
  }

  void _openPrivate(MmChannel c) {
    final host = ChatHost.of(context);
    final parent = c.subParent;
    if (host != null && host.openSide != null && parent != null && context.read<AppState>().channels.containsKey(parent)) {
      host.openChat(parent);
      host.openSide!(c.id);
      return;
    }
    openChannelAnywhere(context, c.id);
  }

  void _openWork(MmPost root) {
    final host = ChatHost.of(context);
    if (host != null) host.openChat(root.channelId);
    openThread(context, root.channelId, root.id);
  }

  /// Đóng / mở lại luồng: không báo gì khi xong (luồng tự chuyển sang danh sách "Đã đóng" / "Đang mở"), chỉ báo khi lỗi.
  Future<void> _run(String id, Future<void> Function() job) async {
    if (_busy.contains(id)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(id));
    try {
      await job();
    } catch (_) {
      messenger.showSnackBar(toast(Text(tr('Không thực hiện được. Kiểm tra kết nối mạng.'))));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    List<MmChannel> privates(bool closed) => app.privateThreads
        .where((c) => c.isClosed == closed && _match('${c.displayName} ${app.channelTitle(app.channels[c.subParent] ?? c)}'))
        .toList();
    List<_Work> works(bool closed) => app.workThreads
        .where((t) => app.isThreadClosed(t.root.channelId, t.root.id) == closed && _match(plainPreview(t.root.message)))
        .toList();
    final open = (privates(false), works(false));
    final closed = (privates(true), works(true));

    if (widget.openOnly) {
      return Column(children: [
        ?widget.header,
        Expanded(child: _list(app, pal, false, open.$1, open.$2)),
      ]);
    }
    // 3 tab: luồng công khai (luồng công việc riêng), luồng bí mật còn mở; tab "Đã đóng" gồm cả hai loại.
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        ?widget.header,
        TabBar(
          labelColor: pal.accentText,
          unselectedLabelColor: pal.sub,
          indicatorColor: pal.accent,
          dividerColor: pal.divider,
          tabs: [
            CountTab(label: tr('Công khai'), count: open.$2.length),
            CountTab(label: tr('Bí mật'), count: open.$1.length),
            CountTab(label: tr('Đã đóng'), count: closed.$1.length + closed.$2.length),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _list(app, pal, false, null, open.$2),
            _list(app, pal, false, open.$1, null),
            _list(app, pal, true, closed.$1, closed.$2),
          ]),
        ),
      ]),
    );
  }

  /// [privates] / [works] null: tab không có loại luồng đó. Có cả hai loại thì gộp một danh sách (mới nhất lên đầu),
  /// mỗi luồng có nhãn "Công khai" (xanh) / "Bí mật" (đỏ) trước tên thay cho chia mục.
  Widget _list(AppState app, Pal pal, bool showClosed, List<MmChannel>? privates, List<_Work>? works) {
    final both = privates != null && works != null;
    Widget tag(String label, Color c) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white)),
        );
    Widget title(String text, Widget? label) => Row(children: [
          ?label,
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
          ),
        ]);
    // Nền đặc, chữ trắng (tương phản ≥ 5:1).
    final publicTag = both ? tag(tr('Công khai'), const Color(0xFF15803D)) : null;
    final secretTag = both ? tag(tr('Bí mật'), const Color(0xFFC62828)) : null;

    Widget action(String id, bool closed, VoidCallback onTap) => _busy.contains(id)
        ? SizedBox(
            width: 64,
            height: 36,
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent))),
          )
        // Luồng đã đóng thì không mở lại được nữa: chỉ hiện nhãn "Đã đóng".
        : closed
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_outline, size: 15, color: pal.sub),
                  const SizedBox(width: 4),
                  Text(tr('Đã đóng'), style: TextStyle(color: pal.sub, fontSize: 13)),
                ]),
              )
            // Luồng đang mở: đóng ở đầu khung chat của luồng (dưới tên), không đóng từ danh sách.
            : const SizedBox.shrink();

    Widget privateRow(MmChannel c) => PaneDragSource(
          content: PaneContent.chat(c.id),
          child: ListTile(
            leading: Avatar(name: c.displayName, size: 42, icon: Icons.lock_outline, channel: c),
            title: title(c.displayName, secretTag),
            subtitle: Text(
              [
                if (app.privateThreadCloser(c) case final by?) tr('{0} đã đóng', [by]),
                if (app.channels[c.subParent] != null) app.channelTitle(app.channels[c.subParent]!),
                if (c.lastPostAt > 0) listTime(c.lastPostAt),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: pal.sub, fontSize: 13),
            ),
            trailing: action(c.id, c.isClosed, () => _run(c.id, () => app.setPrivateThreadClosed(c, !c.isClosed))),
            onTap: () => _openPrivate(c),
          ),
        );
    Widget workRow(_Work t) => ListTile(
          leading: Avatar(userId: t.root.userId, name: app.users[t.root.userId]?.displayName ?? '', size: 42),
          title: title(app.threadName(t.root.channelId, t.root.id) ?? plainPreview(t.root.message).replaceAll('\n', ' '), publicTag),
          subtitle: Text(
            [
              if (showClosed)
                if (app.threadCloser(t.root.channelId, t.root.id) case final by?) tr('{0} đã đóng', [by]),
              if (app.channels[t.root.channelId] != null) app.channelTitle(app.channels[t.root.channelId]!),
              tr('{0} trả lời', [t.replies]),
              if (t.lastAt > 0) listTime(t.lastAt),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: pal.sub, fontSize: 13),
          ),
          trailing: action(t.root.id, showClosed, () {
            final closed = app.isThreadClosed(t.root.channelId, t.root.id);
            _run(t.root.id, () => app.setThreadClosed(t.root.channelId, t.root.id, !closed));
          }),
          onTap: () => _openWork(t.root),
        );

    final items = <(int, Widget)>[
      for (final c in privates ?? const <MmChannel>[]) (c.lastPostAt, privateRow(c)),
      for (final t in works ?? const <_Work>[]) (t.lastAt, workRow(t)),
    ];
    if (both) items.sort((a, b) => b.$1.compareTo(a.$1));
    final rows = <Widget>[
      for (final it in items) it.$2,
      if (items.isEmpty)
        works != null && app.workThreadsLoading
            ? Padding(padding: const EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: pal.accent)))
            : _empty(pal, showClosed),
    ];

    return RefreshIndicator(
      color: pal.accent,
      onRefresh: app.loadWorkThreads,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: widget.bottomPadding),
        children: rows,
      ),
    );
  }

  Widget _empty(Pal pal, bool showClosed) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
        child: Text(showClosed ? tr('Chưa có luồng nào đã đóng') : tr('Không có luồng nào đang dang dở'),
            style: TextStyle(color: pal.sub, fontSize: 14)),
      );
}

/// Máy tính: trang "Luồng công việc" mở thay cho danh sách chat (cột trái), có nút quay lại.
class WorkThreadsPage extends StatelessWidget {
  const WorkThreadsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(tr('Luồng công việc'), style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
      ),
      body: const ThreadsView(),
    );
  }
}
