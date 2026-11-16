// Thư (vn.flygo.mail): màn hình chính kiểu webmail quen thuộc.
// Máy tính: thanh tìm kiếm trên cùng, cột trái (Soạn thư, các hộp, nhãn), danh sách hoặc cuộc hội thoại bên phải,
// khung soạn nổi góc dưới bên phải, phím tắt. Điện thoại: ô tìm kiếm dạng viên thuốc, menu trượt, danh sách có ảnh
// đại diện, nút Soạn thư nổi; mở thư / soạn thư thành trang riêng; nhấn giữ (hoặc chạm ảnh đại diện) để chọn nhiều.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/mini_apps.dart';
import '../../browser/flygo_id.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../desk_tabs.dart' show DeskTabScope;
import '../forward_page.dart';
import '../calendar/calendar_entry.dart' show openCalendarCreate;
import '../drive/drive_page.dart' show openDrive;
import '../drive/pickers.dart' show pickDriveFolder;
import '../drive/session.dart' show DriveSession;
import '../theme.dart' show toast;
import 'admin_page.dart';
import 'api.dart';
import 'digest.dart';
import 'when.dart';
import 'compose.dart';
import 'demo.dart';
import 'model.dart';
import 'store.dart';
import 'switcher.dart';
import 'thread_view.dart';
import 'widgets.dart';

const kMailScreen = 'mail';

/// Mở Thư (từ ô ứng dụng, hoặc từ tin báo thư mới với [threadId]).
Future<void> openMail(BuildContext context, MiniApp app, {String? threadId, String? mailbox}) async {
  final state = context.read<AppState>();
  final nav = Navigator.of(context);
  final tab = DeskTabScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final MailApi api;
    // Xem thử khi chưa có máy chủ thư: app đăng ký với base_url "demo:" hoặc tính năng "demo" dùng dữ liệu mẫu.
    if (isMailDemo(app)) {
      api = DemoMailApi();
    } else {
      final id = await FlygoId.current(state.token);
      if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
      api = HttpMailApi(base: app.baseUrl, id: id, mailbox: mailbox);
    }
    final store = MailStore(api);
    installMailHooks();
    await nav.push(
      AppPageRoute(
        builder: (_) => MailHome(store: store, title: app.name, openThreadId: threadId),
      ),
    );
    tab?.onTitle?.call(null);
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

/// Mở Quản trị Thư (ô "Thư" ở mục Quản trị của Trang chủ: Flygo ID /v1/me/admin trả native "mail-admin").
Future<void> openMailAdmin(BuildContext context) async {
  final state = context.read<AppState>();
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    var app = MiniApps.cached.where((a) => a.id == kMailApp).firstOrNull;
    app ??= (await MiniApps.list(state.token)).where((a) => a.id == kMailApp).firstOrNull;
    if (app == null) throw StateError(tr('Bạn chưa được cấp app Thư'));
    final MailApi api;
    if (isMailDemo(app)) {
      api = DemoMailApi();
    } else {
      final id = await FlygoId.current(state.token);
      if (id == null) throw StateError(tr('Máy chủ này chưa có Flygo ID'));
      api = HttpMailApi(base: app.baseUrl, id: id);
    }
    await nav.push(AppPageRoute(builder: (_) => MailAdminPage(api: api.adminApi())));
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

/// App Thư chạy bằng dữ liệu mẫu (base_url "demo:" hoặc features.demo = true).
bool isMailDemo(MiniApp app) => app.baseUrl.startsWith('demo:') || app.feature('demo');

/// Gắn móc nối mặc định: gửi vào chat bằng trang Chuyển tiếp của app, tạo sự kiện bằng app Lịch.
void installMailHooks() {
  // Lưu tệp đính kèm vào Drive của chính người dùng (drive-gw, vé của họ): chọn thư mục rồi tải lên nền.
  MailHooks.saveToDrive ??= (context, files) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = await DriveSession.current(context.read<AppState>());
    if (s == null) {
      messenger.showSnackBar(toast(const Text('Bạn chưa được cấp app Drive')));
      return;
    }
    if (!context.mounted) return;
    final title = files.length > 1 ? 'Lưu ${files.length} tệp vào Drive' : 'Lưu "${files.first.$2}" vào Drive';
    final dir = await pickDriveFolder(context, s, title: title, ok: 'Lưu vào đây');
    if (dir == null) return;
    await s.uploads.add(files, dir, origin: 'mail', copy: true);
    final app = s.app;
    messenger.showSnackBar(SnackBar(
      content: Text(files.length > 1 ? 'Đang lưu ${files.length} tệp vào Drive ($dir)' : 'Đang lưu "${files.first.$2}" vào Drive ($dir)'),
      action: app == null || !context.mounted ? null : SnackBarAction(label: 'Mở trong Drive', onPressed: () => openDrive(context, app, path: dir)),
    ));
  };
  MailHooks.sendToChat ??= (context, text) => Navigator.of(context).push(AppPageRoute(builder: (_) => ForwardPage.share(sharedText: text)));
  MailHooks.createEvent ??= (context, {required title, required guestEmails, required description}) =>
      openCalendarCreate(context, title: title, guestEmails: guestEmails, description: description);
}

class MailHome extends StatefulWidget {
  const MailHome({super.key, required this.store, this.title = 'Thư', this.openThreadId, this.ownsStore = true, this.initialView});
  final MailStore store;
  final String title;
  final String? openThreadId;
  final bool ownsStore;
  final MailView? initialView;
  @override
  State<MailHome> createState() => MailHomeState();
}

class MailHomeState extends State<MailHome> with WidgetsBindingObserver {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _q = TextEditingController();
  final _qFocus = FocusNode();
  final _keys = FocusNode(debugLabel: 'mail-keys');
  final _threadKey = GlobalKey<ThreadViewState>();
  bool _railOpen = true, _moreBoxes = false, _filters = false;
  String? _threadId;
  int _cursor = -1;
  final composers = <ComposeController>[];
  DateTime _gAt = DateTime(0);

  MailStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    if (widget.initialView != null) store.view = widget.initialView!;
    store.start();
    if (widget.ownsStore) store.startLive();
    WidgetsBinding.instance.addObserver(this);
    _threadId = widget.openThreadId;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) store.resumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_changed);
    if (widget.ownsStore) store.dispose();
    for (final c in composers) {
      c.dispose();
    }
    _q.dispose();
    _qFocus.dispose();
    _keys.dispose();
    super.dispose();
  }

  String? _tabTitle;

  void _changed() {
    if (!mounted) return;
    // Tiêu đề tab (bản desktop): địa chỉ hộp thư đang xem.
    final email = store.me?.current.id;
    if (email != null && email != _tabTitle) {
      _tabTitle = email;
      DeskTabScope.of(context)?.onTitle?.call(email);
    }
    setState(() {});
  }

  bool _wide(BuildContext c) => MediaQuery.sizeOf(c).width >= 760;

  void snack(String m, {Future<void> Function()? undo, String? action, VoidCallback? onAction}) {
    if (m.isEmpty) return;
    final ms = ScaffoldMessenger.of(context);
    ms.hideCurrentSnackBar();
    ms.showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        width: _wide(context) ? 420 : null,
        duration: Duration(seconds: undo != null || action != null ? 8 : 4),
        action: undo != null
            ? SnackBarAction(
                label: 'Hoàn tác',
                onPressed: () async {
                  await undo();
                  snack('Đã hoàn tác');
                },
              )
            : action != null
            ? SnackBarAction(label: action, onPressed: onAction ?? () {})
            : null,
      ),
    );
  }

  /* ---------------- navigation ---------------- */

  Future<void> go(MailView v) async {
    setState(() {
      _threadId = null;
      _cursor = -1;
      if (!v.isSearch) _q.clear();
    });
    if (!_wide(context)) _scaffold.currentState?.closeDrawer();
    await store.open(v);
  }

  /// Mở hội thoại theo id (từ "Tóm tắt bằng AI").
  void openThreadId(String id) {
    final t = store.items.where((x) => x.id == id).firstOrNull;
    if (t != null) return openThread(t);
    if (_wide(context)) {
      setState(() => _threadId = id);
      return;
    }
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: MailColors.of(context).surface,
          body: SafeArea(child: ThreadView(store: store, threadId: id, wide: false, onBack: () => Navigator.of(context).maybePop(), onCompose: compose)),
        ),
      ),
    );
  }

  void openThread(MailThreadSummary t) async {
    final sid = t.scheduledDraftId;
    if (sid != null && t.scheduledAt != null) {
      final edit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Thư đã hẹn giờ'),
          content: Text('Thư "${t.subject}" sẽ được gửi ${whenLabel(t.scheduledAt!)}. Huỷ hẹn giờ để sửa? Thư sẽ về Thư nháp.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Đóng')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Huỷ hẹn giờ và sửa')),
          ],
        ),
      );
      if (edit != true || !mounted) return;
      try {
        await store.cancelScheduled(sid);
        final th = await store.api.thread(t.id);
        compose(draftArgs(th));
      } catch (e) {
        snack('$e');
      }
      return;
    }
    if (t.draft) {
      try {
        final th = await store.api.thread(t.id);
        compose(draftArgs(th));
      } catch (e) {
        snack('$e');
      }
      return;
    }
    _cursor = store.items.indexOf(t);
    if (_wide(context)) {
      setState(() => _threadId = t.id);
    } else {
      await Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: MailColors.of(context).surface,
            body: SafeArea(
              child: ThreadView(store: store, threadId: t.id, wide: false, onBack: () => Navigator.of(context).maybePop(), onCompose: compose),
            ),
          ),
        ),
      );
      store.load(quiet: true);
    }
  }

  void step(int d) {
    final i = store.items.indexWhere((x) => x.id == _threadId);
    final n = i + d;
    if (n >= 0 && n < store.items.length) setState(() => _threadId = store.items[n].id);
  }

  /* ---------------- compose ---------------- */

  void compose([ComposeArgs args = const ComposeArgs()]) {
    final c = ComposeController(store.api, args)..onDraftsChanged = store.refreshCounts;
    if (_wide(context)) {
      setState(() {
        for (final o in composers) {
          o.minimized = true;
        }
        if (composers.length >= 3) {
          composers.removeAt(0).close();
        }
        composers.add(c);
      });
    } else {
      Navigator.of(context)
          .push(
            AppPageRoute(
              fullscreenDialog: true,
              builder: (ctx) => Scaffold(
                backgroundColor: MailColors.of(ctx).surface,
                body: SafeArea(
                  bottom: false,
                  child: ComposeBody(
                    c: c,
                    phone: true,
                    onSent: (tid) {
                      Navigator.of(ctx).pop();
                      _sent(tid);
                    },
                    onClosed: (m) {
                      Navigator.of(ctx).pop();
                      snack(m);
                      store.refreshCounts();
                    },
                  ),
                ),
              ),
            ),
          )
          .whenComplete(() => c.dispose());
    }
  }

  void _sent(String? threadId) {
    snack(
      'Đã gửi thư.',
      action: 'Xem thư',
      onAction: () {
        if (threadId != null && _wide(context)) {
          setState(() => _threadId = threadId);
        } else {
          go(const MailView.box('sent'));
        }
      },
    );
    store.load(quiet: true);
    store.refreshCounts();
    _threadKey.currentState?.reload();
  }

  void _removeComposer(ComposeController c) {
    setState(() => composers.remove(c));
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  /* ---------------- actions ---------------- */

  Future<void> act(MailAction a, List<String> ids) async {
    if (ids.isEmpty) return;
    if (a == MailAction.forever) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Xoá vĩnh viễn?'),
          content: Text('${ids.length > 1 ? '${ids.length} cuộc hội thoại' : 'Cuộc hội thoại này'} sẽ bị xoá vĩnh viễn và không thể khôi phục.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá vĩnh viễn')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      final undo = await store.act(a, ids);
      final m = MailStore.messageFor(a, ids.length);
      if (m != null) snack(m, undo: undo);
    } catch (e) {
      snack('$e');
    }
  }

  /// Tạm ẩn: chọn mốc giờ; thư quay lại Hộp thư đến (chưa đọc) đúng lúc đó. Đang ở mục Đã tạm ẩn: bỏ tạm ẩn.
  Future<void> _snooze([List<String>? only]) async {
    final ids = only ?? (store.selected.isNotEmpty ? store.selected.toList() : (_threadId == null ? <String>[] : [_threadId!]));
    if (ids.isEmpty) return;
    if (store.view.box == 'snoozed') {
      final undo = await store.snooze(ids, null);
      snack('Đã bỏ tạm ẩn', undo: undo);
      return;
    }
    final until = await pickWhen(context, title: 'Tạm ẩn đến');
    if (until == null || !mounted) return;
    try {
      final undo = await store.snooze(ids, until);
      if (_threadId != null && ids.contains(_threadId)) setState(() => _threadId = null);
      snack('Đã tạm ẩn đến ${whenLabel(until)}', undo: undo);
    } catch (e) {
      snack('$e');
    }
  }

  /* ---------------- keyboard ---------------- */

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus != _keys && focus.context?.findAncestorWidgetOfExactType<EditableText>() != null) return KeyEventResult.ignored;
    if (focus?.context?.widget is EditableText) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final ch = e.character ?? '';
    final inThread = _threadId != null;
    final cur = inThread ? store.byId(_threadId!) ?? _threadKey.currentState?.thread?.summary : (_cursor >= 0 && _cursor < store.items.length ? store.items[_cursor] : null);
    final ids = inThread
        ? [_threadId!]
        : store.selected.isNotEmpty
        ? store.selected.toList()
        : [if (cur != null) cur.id];
    if (DateTime.now().difference(_gAt).inMilliseconds < 1200) {
      _gAt = DateTime(0);
      final box = {'i': 'inbox', 's': 'starred', 't': 'sent', 'd': 'drafts', 'a': 'all'}[ch];
      if (box != null) {
        go(MailView.box(box));
        return KeyEventResult.handled;
      }
    }
    void run(void Function() f) => f();
    if (store.readOnly && const {'c', 's', 'e', '#', '!', 'I', 'U', 'r', 'a', 'f', 'x'}.contains(ch)) {
      snack('Bạn chỉ có quyền xem hộp thư này');
      return KeyEventResult.handled;
    }
    switch (ch) {
      case 'g':
        _gAt = DateTime.now();
        return KeyEventResult.handled;
      case 'c':
        run(compose);
      case '/':
        run(_qFocus.requestFocus);
      case '?':
        run(_help);
      case 'j' || 'k':
        final d = ch == 'j' ? 1 : -1;
        if (inThread) {
          step(d);
        } else {
          setState(() => _cursor = (_cursor + d).clamp(0, store.items.length - 1));
        }
      case 'o':
        if (!inThread && cur != null) openThread(cur);
      case 'u':
        if (inThread) setState(() => _threadId = null);
      case 'x':
        if (!inThread && cur != null) store.toggleSelect(cur.id);
      case 's':
        if (cur != null) act(cur.starred ? MailAction.unstar : MailAction.star, ids);
      case 'e':
        if (ids.isNotEmpty) {
          if (inThread) {
            _threadKey.currentState?.act(store.archiveOrRestore(cur));
          } else {
            act(store.archiveOrRestore(cur), ids);
          }
        }
      case '#':
        if (ids.isNotEmpty) inThread ? _threadKey.currentState?.act(MailAction.trash) : act(store.view.box == 'trash' ? MailAction.forever : MailAction.trash, ids);
      case '!':
        if (ids.isNotEmpty) inThread ? _threadKey.currentState?.act(MailAction.spam) : act(MailAction.spam, ids);
      case 'I' when shift:
        act(MailAction.read, ids);
      case 'U' when shift:
        inThread ? _threadKey.currentState?.act(MailAction.unread) : act(MailAction.unread, ids);
      case 'r' || 'a' || 'f':
        if (inThread) _threadKey.currentState?.reply({'r': 'reply', 'a': 'all', 'f': 'fwd'}[ch]!);
      default:
        if (k == LogicalKeyboardKey.enter && !inThread && cur != null) {
          openThread(cur);
        } else if (k == LogicalKeyboardKey.escape) {
          if (store.hasSelection) {
            store.clearSelection();
          } else if (inThread) {
            setState(() => _threadId = null);
          } else {
            return KeyEventResult.ignored;
          }
        } else {
          return KeyEventResult.ignored;
        }
    }
    return KeyEventResult.handled;
  }

  void _help() {
    const keys = [
      ('c', 'Soạn thư'),
      ('/', 'Tìm kiếm'),
      ('j / k', 'Thư cũ hơn / mới hơn'),
      ('o hoặc Enter', 'Mở thư'),
      ('u', 'Quay lại danh sách'),
      ('x', 'Chọn cuộc hội thoại'),
      ('s', 'Gắn / bỏ sao'),
      ('e', 'Lưu trữ'),
      ('#', 'Xoá'),
      ('!', 'Báo cáo thư rác'),
      ('r', 'Trả lời'),
      ('a', 'Trả lời tất cả'),
      ('f', 'Chuyển tiếp'),
      ('Shift + I', 'Đánh dấu đã đọc'),
      ('Shift + U', 'Đánh dấu chưa đọc'),
      ('g rồi i', 'Đến Hộp thư đến'),
      ('g rồi s', 'Đến Có gắn sao'),
      ('g rồi t', 'Đến Đã gửi'),
      ('g rồi d', 'Đến Thư nháp'),
      ('Ctrl + Enter', 'Gửi thư'),
      ('Esc', 'Đóng / bỏ chọn'),
      ('?', 'Bảng phím tắt này'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Phím tắt'),
        content: SizedBox(
          width: 640,
          child: Wrap(
            spacing: 32,
            children: [
              for (final (k, t) in keys)
                SizedBox(
                  width: 290,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
                        _Kbd(k),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );
  }

  /* ---------------- build ---------------- */

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final wide = _wide(context);
    final content = store.error != null && store.me == null
        ? _errorView(mc)
        : store.me == null
        ? _loadingView(mc)
        : wide
        ? _desktop(mc)
        : _phone(mc);
    return Focus(focusNode: _keys, autofocus: true, onKeyEvent: _onKey, child: content);
  }

  /// Đang tải thông tin hộp thư (lần mở đầu): không vẽ giao diện trống bấm không được.
  Widget _loadingView(MailColors mc) => Scaffold(
    key: const ValueKey('mail-loading'),
    backgroundColor: mc.bg,
    appBar: AppBar(title: Text(widget.title), backgroundColor: mc.bg),
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(height: 14),
        Text('Đang tải hộp thư…', style: TextStyle(color: mc.muted)),
      ]),
    ),
  );

  /// Máy chủ thư trả 404 cho /me: kết nối được, chỉ là người này chưa có hộp thư nào.
  bool get _noMailbox => store.error is MailException && (store.error as MailException).status == 404;

  /// Có quyền Quản trị Thư không (Flygo ID /v1/me/admin có native "mail-admin"): hiện nút mở trang quản trị.
  late final Future<bool> _canAdminMail = () async {
    try {
      final id = await FlygoId.current(Provider.of<AppState>(context, listen: false).token);
      return id != null && (await id.myAdmin()).any((a) => a['native'] == 'mail-admin');
    } catch (_) {
      return false;
    }
  }();

  Widget _errorView(MailColors mc) {
    final empty = _noMailbox;
    return Scaffold(
      backgroundColor: mc.bg,
      appBar: AppBar(title: Text(widget.title), backgroundColor: mc.bg),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(empty ? Icons.inbox_outlined : Icons.mail_outline, size: 56, color: mc.faint),
              const SizedBox(height: 12),
              if (empty) ...[
                Text('Bạn chưa có hộp thư nào', textAlign: TextAlign.center, style: TextStyle(color: mc.text, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('Nhờ quản trị tạo hộp thư cho bạn.', textAlign: TextAlign.center, style: TextStyle(color: mc.muted)),
              ] else
                Text(
                  'Không kết nối được máy chủ thư.\n${store.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mc.muted),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (empty)
                    FutureBuilder<bool>(
                      future: _canAdminMail,
                      builder: (context, snap) => snap.data == true
                          ? OutlinedButton.icon(
                              onPressed: () => openMailAdmin(context),
                              icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                              label: const Text('Quản trị Thư'),
                            )
                          : const SizedBox.shrink(),
                    ),
                  FilledButton(onPressed: store.start, child: const Text('Thử lại')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brand(MailColors mc) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF3B8CFF), Color(0xFF1450C8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.mail_rounded, color: Colors.white, size: 22),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text.rich(
          overflow: TextOverflow.ellipsis,
          TextSpan(
            children: [
              TextSpan(
                text: widget.title.replaceAll(RegExp(r'\s*Mail$'), ''),
                style: TextStyle(fontSize: 20, color: mc.text),
              ),
              if (widget.title.endsWith('Mail'))
                TextSpan(
                  text: ' Mail',
                  style: TextStyle(fontSize: 20, color: mc.accentText, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ),
      if (store.readOnly) ...[
        const SizedBox(width: 6),
        Tooltip(
          message: 'Bạn chỉ có quyền xem hộp thư này',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: mc.chip, borderRadius: BorderRadius.circular(6)),
            child: Text(
              'CHỈ XEM',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mc.muted),
            ),
          ),
        ),
      ],
      if (store.api.demo) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFFFE6B3), borderRadius: BorderRadius.circular(6)),
          child: const Text(
            'DEMO',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFA15C00)),
          ),
        ),
      ],
    ],
  );

  Widget _desktop(MailColors mc) {
    return Scaffold(
      backgroundColor: mc.bg,
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(
                height: 64,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    IconButton(tooltip: 'Menu chính', icon: const Icon(Icons.menu), onPressed: () => setState(() => _railOpen = !_railOpen)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 232,
                      child: Align(alignment: Alignment.centerLeft, child: _brand(mc)),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _searchBox(mc, wide: true)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(tooltip: 'Phím tắt', icon: const Icon(Icons.help_outline), onPressed: _help),
                    const SizedBox(width: 4),
                    if (store.me != null) _meButton(mc, wide: true, size: 34),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _railOpen ? 256 : 72,
                      child: _nav(mc, mini: !_railOpen),
                    ),
                    Expanded(
                      child: Container(
                        // Tách khỏi cột trái: khoảng cách + viền mảnh (Sếp, 2026-11-15: danh sách bị dính vào sidebar).
                        margin: const EdgeInsets.only(left: 8, right: 16, bottom: 16),
                        decoration: BoxDecoration(color: mc.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: mc.line)),
                        clipBehavior: Clip.antiAlias,
                        child: _threadId != null
                            ? ThreadView(
                                key: _threadKey,
                                store: store,
                                threadId: _threadId!,
                                onBack: () => setState(() => _threadId = null),
                                onCompose: compose,
                                onStep: step,
                                inlineReply: (args, done) => _InlineReply(
                                  store: store,
                                  args: args,
                                  onDone: (tid, msg) {
                                    done();
                                    if (tid != null || msg == 'sent') {
                                      _sent(tid);
                                    } else {
                                      snack(msg ?? '');
                                    }
                                  },
                                ),
                              )
                            : _list(mc, wide: true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_filters) _filterPanel(mc, wide: true),
          Positioned(
            right: 16,
            bottom: 0,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final c in composers) ...[
                  ComposeDock(
                    key: ObjectKey(c),
                    c: c,
                    onSent: (tid) {
                      _removeComposer(c);
                      _sent(tid);
                    },
                    onClosed: (m) {
                      _removeComposer(c);
                      snack(m);
                      store.refreshCounts();
                      if (store.view == const MailView.box('drafts')) store.load(quiet: true);
                    },
                  ),
                  const SizedBox(width: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phone(MailColors mc) {
    final sel = store.hasSelection;
    return Scaffold(
      key: _scaffold,
      backgroundColor: mc.bg,
      drawer: Drawer(
        backgroundColor: mc.surface,
        child: SafeArea(child: _nav(mc, drawer: true)),
      ),
      floatingActionButton: sel || store.readOnly
          ? null
          : FloatingActionButton.extended(
              backgroundColor: mc.accentSoft,
              foregroundColor: mc.accentText,
              onPressed: compose,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Soạn thư', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                if (sel)
                  Container(
                    height: 64,
                    color: mc.surface,
                    child: Row(
                      children: [
                        IconButton(tooltip: 'Bỏ chọn', icon: const Icon(Icons.arrow_back), onPressed: store.clearSelection),
                        Text('${store.selected.length}', style: TextStyle(fontSize: 18, color: mc.text)),
                        const Spacer(),
                        ..._selActions(mc, phone: true),
                      ],
                    ),
                  )
                else
                  Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: _searchBox(mc, wide: false)),
                Expanded(child: _list(mc, wide: false)),
              ],
            ),
            if (_filters) _filterPanel(mc, wide: false),
          ],
        ),
      ),
    );
  }

  Widget _searchBox(MailColors mc, {required bool wide}) {
    final searching = store.view.isSearch;
    return Container(
      height: 48,
      decoration: BoxDecoration(color: mc.surface2, borderRadius: BorderRadius.circular(24)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (wide || searching || _qFocus.hasFocus)
            IconButton(
              tooltip: searching && !wide ? 'Quay lại' : 'Tìm kiếm',
              icon: Icon(searching && !wide ? Icons.arrow_back : Icons.search),
              onPressed: () => searching && !wide ? go(const MailView.box('inbox')) : _search(),
            )
          else
            IconButton(tooltip: 'Menu', icon: const Icon(Icons.menu), onPressed: () => _scaffold.currentState?.openDrawer()),
          Expanded(
            child: TextField(
              controller: _q,
              focusNode: _qFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(hintText: 'Tìm trong thư', border: InputBorder.none, isDense: true),
            ),
          ),
          if (_q.text.isNotEmpty || searching) IconButton(tooltip: 'Xoá tìm kiếm', icon: const Icon(Icons.close), onPressed: () => go(const MailView.box('inbox'))),
          IconButton(tooltip: 'Tuỳ chọn tìm kiếm', icon: const Icon(Icons.tune), onPressed: () => setState(() => _filters = !_filters)),
          if (!wide && store.me != null) Padding(padding: const EdgeInsets.only(right: 6, left: 2), child: _meButton(mc, wide: false, size: 32)),
        ],
      ),
    );
  }

  /// Ảnh đại diện hộp đang xem, bấm để mở bộ chọn hộp thư; chấm đỏ khi hộp khác có thư chưa đọc.
  Widget _meButton(MailColors mc, {required bool wide, required double size}) {
    final me = store.me!;
    final cur = me.boxes.where((b) => b.id == me.person.email).firstOrNull ?? MailboxInfo(me.person.email, name: me.person.name, access: me.access);
    final otherUnread = me.boxes.any((b) => b.id != cur.id && b.unread > 0);
    return Semantics(
      button: true,
      label: 'Hộp thư: ${cur.id}',
      child: InkWell(
        key: const ValueKey('mail-switcher'),
        customBorder: const CircleBorder(),
        onTap: () => _switcher(wide: wide),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Stack(clipBehavior: Clip.none, children: [
            MailboxAvatar(cur, size: size),
            if (otherUnread)
              Positioned(
                right: -1,
                top: -1,
                child: Container(width: 11, height: 11, decoration: BoxDecoration(color: mc.danger, shape: BoxShape.circle, border: Border.all(color: mc.bg, width: 2))),
              ),
          ]),
        ),
      ),
    );
  }

  void _switcher({required bool wide}) {
    store.refreshMe();
    showMailboxSwitcher(context, store, wide: wide, onAdmin: store.me?.admin == true ? openAdmin : null);
  }

  /// Mở Quản trị Thư (từ bộ chọn hộp thư; cùng trang với ô Quản trị ở Trang chủ). Quay lại thì tải lại danh sách hộp thư
  /// (hộp vừa tạo / xoá, quyền vừa đổi); kênh realtime cũng báo khi đổi từ nơi khác.
  Future<void> openAdmin() async {
    await Navigator.of(context).push(AppPageRoute(builder: (_) => MailAdminPage(api: store.api.adminApi())));
    await store.refreshMe();
  }

  /// Dòng đầu danh sách thư: đang xem hộp nào (kèm quyền nếu không phải hộp của mình) + nút xem hộp thư khác.
  /// Điện thoại: địa chỉ một dòng riêng (không bị cắt), loại hộp + quyền ở dòng nhỏ bên dưới.
  Widget _mailboxBar(MailColors mc, {required bool wide}) {
    final me = store.me;
    if (me == null) return const SizedBox.shrink();
    final cur = me.current;
    final others = me.boxes.where((b) => b.id != cur.id).toList();
    final otherUnread = others.fold(0, (n, b) => n + b.unread);
    final notOwn = cur.shared || cur.via != 'owner' || cur.access == 'read';
    return Container(
      key: const ValueKey('mail-current-box'),
      padding: EdgeInsets.fromLTRB(16, wide ? 8 : 4, wide ? 10 : 8, wide ? 2 : 0),
      child: Row(
        children: [
          MailboxAvatar(cur, size: wide ? 22 : 30),
          const SizedBox(width: 8),
          if (wide) ...[
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  if (cur.shared || cur.via != 'owner') TextSpan(text: cur.shared ? 'Hộp chung ' : 'Hộp ', style: TextStyle(color: mc.muted)),
                  TextSpan(text: cur.id, style: TextStyle(color: mc.text, fontWeight: FontWeight.w600)),
                ]),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            if (notOwn) ...[const SizedBox(width: 8), AccessChip(cur.access, small: true)],
            const SizedBox(width: 4),
          ] else
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(cur.id, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: mc.text, fontWeight: FontWeight.w600)),
                if (notOwn)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      Flexible(child: Text(cur.shared ? 'Hộp chung' : 'Được chia sẻ', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: mc.muted))),
                      const SizedBox(width: 6),
                      Flexible(child: AccessChip(cur.access, small: true)),
                    ]),
                  ),
              ]),
            ),
          if (others.isNotEmpty || me.admin)
            TextButton.icon(
              key: const ValueKey('mail-other-boxes'),
              onPressed: () => _switcher(wide: wide),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
              icon: Badge(isLabelVisible: otherUnread > 0, smallSize: 8, backgroundColor: mc.danger, child: const Icon(Icons.swap_horiz, size: 18)),
              // Điện thoại: nhãn ngắn để địa chỉ hộp thư không bị ép mất chỗ (nút bị đẩy ra ngoài màn hình).
              label: Text(wide ? 'Xem hòm thư khác' : 'Đổi hộp'),
            ),
          if (me.has('ai') && !me.readOnly)
            wide
                ? TextButton.icon(
                    key: const ValueKey('mail-ai-digest'),
                    onPressed: () => showMailDigest(context, store, wide: wide, onOpen: openThreadId),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Tóm tắt bằng AI'),
                  )
                : IconButton(
                    key: const ValueKey('mail-ai-digest'),
                    tooltip: 'Tóm tắt bằng AI',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showMailDigest(context, store, wide: wide, onOpen: openThreadId),
                    icon: Icon(Icons.auto_awesome, size: 20, color: mc.accentText),
                  ),
        ],
      ),
    );
  }

  void _search() {
    final v = _q.text.trim();
    _qFocus.unfocus();
    setState(() => _filters = false);
    if (v.isNotEmpty) go(MailView.search(v));
  }

  Widget _filterPanel(MailColors mc, {required bool wide}) {
    final panel = _Filters(
      initial: MailQuery.parse(_q.text),
      labels: store.labels,
      onCancel: () => setState(() => _filters = false),
      onSearch: (q) {
        _q.text = q;
        _search();
      },
    );
    if (!wide) {
      return Positioned.fill(child: Material(color: mc.surface, child: panel));
    }
    return Positioned(
      left: (_railOpen ? 256 : 72) + 0.0 + 8,
      top: 58,
      width: 680,
      child: Material(elevation: 10, borderRadius: BorderRadius.circular(8), color: mc.surface, child: panel),
    );
  }

  /* ---------------- nav ---------------- */

  Widget _nav(MailColors mc, {bool mini = false, bool drawer = false}) {
    final c = store.counts;
    Widget item(String key, Widget icon, String text, int n, bool on, VoidCallback onTap) {
      if (mini) {
        return Tooltip(
          message: text,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 2),
            child: Material(
              color: on ? mc.sel : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onTap,
                child: SizedBox(
                  width: 48,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      icon,
                      if (n > 0)
                        Positioned(
                          right: 10,
                          top: 4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: mc.danger, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.only(right: drawer ? 12 : 8),
        child: Material(
          color: on ? mc.sel : Colors.transparent,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
          child: InkWell(
            key: ValueKey('nav-$key'),
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
            onTap: onTap,
            child: SizedBox(
              height: drawer ? 44 : 32,
              child: Row(
                children: [
                  const SizedBox(width: 26),
                  IconTheme(
                    data: IconThemeData(size: 20, color: on ? mc.accentText : mc.text),
                    child: icon,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: on ? mc.accentText : mc.text, fontWeight: on || n > 0 ? FontWeight.w700 : FontWeight.w400),
                    ),
                  ),
                  if (n > 0)
                    Text(
                      '$n',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? mc.accentText : mc.text),
                    ),
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final v = store.view;
    Widget box(String b) => item(
      b,
      Icon(boxIcon(b)),
      MailStore.boxName(b),
      b == 'inbox'
          ? c.inbox
          : b == 'drafts'
          ? c.drafts
          : b == 'spam'
          ? c.spam
          : 0,
      v.isBox && v.box == b,
      () => go(MailView.box(b)),
    );
    return ListView(
      padding: EdgeInsets.only(top: drawer ? 8 : 4, bottom: 16),
      children: [
        if (drawer) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 12, 12), child: _brand(mc)),
        if (!drawer && !store.readOnly)
          Padding(
            padding: EdgeInsets.only(left: mini ? 8 : 8, bottom: 14, top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: mc.accentSoft,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: compose,
                  child: SizedBox(
                    height: 56,
                    width: mini ? 56 : null,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: mini ? 0 : 18),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_outlined, color: mc.accentText),
                          if (!mini) ...[
                            const SizedBox(width: 12),
                            Text(
                              'Soạn thư',
                              style: TextStyle(color: mc.accentText, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        for (final b in ['inbox', 'starred', 'snoozed', 'sent', 'scheduled', 'drafts']) box(b),
        item('more', Icon(_moreBoxes ? Icons.expand_less : Icons.expand_more), _moreBoxes ? 'Ẩn bớt' : 'Thêm', 0, false, () => setState(() => _moreBoxes = !_moreBoxes)),
        if (_moreBoxes)
          for (final b in ['important', 'all', 'spam', 'trash']) box(b),
        if (!mini)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 14, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Nhãn',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: mc.text),
                  ),
                ),
                if (!store.readOnly)
                  IconButton(
                    tooltip: 'Tạo nhãn mới',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () async {
                      final l = await showNewLabelDialog(context, store);
                      if (l != null) snack('Đã tạo nhãn "${l.name}"');
                    },
                  ),
              ],
            ),
          ),
        for (final l in store.labels)
          item(
            'label-${l.id}',
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: Color(l.color), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            l.name,
            c.labels[l.id] ?? 0,
            v.label == l.id,
            () => go(MailView.label(l.id)),
          ),
      ],
    );
  }

  /* ---------------- list ---------------- */

  List<Widget> _selActions(MailColors mc, {bool phone = false}) {
    final ids = store.selected.toList();
    final b = store.view.box;
    final anyUnread = store.items.any((t) => store.selected.contains(t.id) && t.unread);
    IconButton ib(IconData i, String tip, VoidCallback f) => IconButton(tooltip: tip, icon: Icon(i), onPressed: f);
    return [
      if (b == 'trash' && store.view.isBox) ...[
        ib(Icons.move_to_inbox_outlined, 'Chuyển đến Hộp thư đến', () => act(MailAction.restore, ids)),
        TextButton(onPressed: () => act(MailAction.forever, ids), child: const Text('Xoá vĩnh viễn')),
      ] else if (b == 'spam' && store.view.isBox) ...[
        TextButton(onPressed: () => act(MailAction.notSpam, ids), child: const Text('Không phải thư rác')),
        TextButton(onPressed: () => act(MailAction.forever, ids), child: const Text('Xoá vĩnh viễn')),
      ] else ...[
        ib(Icons.archive_outlined, 'Lưu trữ (e)', () => act(MailAction.archive, ids)),
        if (!phone) ib(Icons.report_gmailerrorred_outlined, 'Báo cáo thư rác (!)', () => act(MailAction.spam, ids)),
        ib(Icons.delete_outline, 'Xoá (#)', () => act(MailAction.trash, ids)),
      ],
      if (!phone) Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 6), color: mc.line),
      ib(
        anyUnread ? Icons.drafts_outlined : Icons.mark_email_unread_outlined,
        anyUnread ? 'Đánh dấu là đã đọc' : 'Đánh dấu là chưa đọc',
        () => act(anyUnread ? MailAction.read : MailAction.unread, ids),
      ),
      if (!phone) ib(Icons.schedule, store.view.box == 'snoozed' ? 'Bỏ tạm ẩn' : 'Tạm ẩn', () => _snooze(ids)),
      Builder(
        builder: (bc) => IconButton(
          tooltip: 'Nhãn',
          icon: const Icon(Icons.label_outline),
          onPressed: () => showLabelMenu(bc, store, ids, onDone: (m, undo) => snack(m, undo: undo)),
        ),
      ),
      Builder(
        builder: (bc) => IconButton(
          tooltip: 'Thao tác khác',
          icon: const Icon(Icons.more_vert),
          onPressed: () {
            final ts = store.items.where((t) => ids.contains(t.id));
            final imp = ts.every((t) => t.important), star = ts.every((t) => t.starred);
            showAnchoredMenu(bc, [
              if (phone) MenuEntry('Báo cáo thư rác', Icons.report_gmailerrorred_outlined, () => act(MailAction.spam, ids)),
              MenuEntry(star ? 'Bỏ gắn dấu sao' : 'Thêm dấu sao', Icons.star_outline, () => act(star ? MailAction.unstar : MailAction.star, ids)),
              MenuEntry(imp ? 'Đánh dấu là không quan trọng' : 'Đánh dấu là quan trọng', Icons.label_important_outline, () => act(imp ? MailAction.unimportant : MailAction.important, ids)),
            ]);
          },
        ),
      ),
    ];
  }

  Widget _list(MailColors mc, {required bool wide}) {
    final n = store.selected.length, all = n > 0 && n == store.items.length;
    final from = store.total == 0 ? 0 : (store.page - 1) * store.size + 1;
    final to = (store.page * store.size).clamp(0, store.total);
    final v = store.view;
    final children = <Widget>[_mailboxBar(mc, wide: wide)];
    if (wide) {
      children.add(
        SizedBox(
          height: 48,
          child: Row(
            children: [
              const SizedBox(width: 10),
              if (!store.readOnly) ...[
                IconButton(
                  tooltip: 'Chọn',
                  icon: Icon(
                    all
                        ? Icons.check_box
                        : n > 0
                        ? Icons.indeterminate_check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                  ),
                  onPressed: () => n > 0 ? store.clearSelection() : store.selectWhere((_) => true),
                ),
                Builder(
                  builder: (bc) => InkWell(
                    onTap: () => showAnchoredMenu(bc, [
                      MenuEntry('Tất cả', null, () => store.selectWhere((_) => true)),
                      MenuEntry('Không chọn thư nào', null, store.clearSelection),
                      MenuEntry('Đã đọc', null, () => store.selectWhere((t) => !t.unread)),
                      MenuEntry('Chưa đọc', null, () => store.selectWhere((t) => t.unread)),
                      MenuEntry('Có gắn dấu sao', null, () => store.selectWhere((t) => t.starred)),
                      MenuEntry('Không có dấu sao', null, () => store.selectWhere((t) => !t.starred)),
                    ]),
                    child: Icon(Icons.arrow_drop_down, color: mc.muted),
                  ),
                ),
              ],
              if (n == 0) ...[
                IconButton(tooltip: 'Làm mới', icon: const Icon(Icons.refresh), onPressed: () => store.load()),
                if (!store.readOnly)
                  Builder(
                    builder: (bc) => IconButton(
                      tooltip: 'Thao tác khác',
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => showAnchoredMenu(bc, [
                        MenuEntry('Đánh dấu tất cả là đã đọc', Icons.drafts_outlined, () => act(MailAction.read, store.items.where((t) => t.unread).map((t) => t.id).toList())),
                      ]),
                    ),
                  ),
              ] else ...[
                ..._selActions(mc),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('Đã chọn $n', style: TextStyle(fontSize: 13, color: mc.muted)),
                ),
              ],
              const Spacer(),
              if (store.total > 0) Text('$from–$to trong tổng số ${store.total}', style: TextStyle(fontSize: 12, color: mc.muted)),
              IconButton(tooltip: 'Mới hơn', icon: const Icon(Icons.chevron_left), onPressed: store.page > 1 ? store.prevPage : null),
              IconButton(tooltip: 'Cũ hơn', icon: const Icon(Icons.chevron_right), onPressed: to < store.total ? store.nextPage : null),
              const SizedBox(width: 8),
            ],
          ),
        ),
      );
      if (store.categories) children.add(_tabs(mc));
    } else {
      final cats = store.categories ? const {'primary': 'Chính', 'promo': 'Quảng cáo', 'social': 'Mạng xã hội'} : null;
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Text(
                (cats?[store.category] ?? store.title).toUpperCase(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: .6, color: mc.muted),
              ),
              const Spacer(),
              if (cats != null)
                PopupMenuButton<String>(
                  tooltip: 'Loại thư',
                  icon: Icon(Icons.filter_list, size: 20, color: mc.muted),
                  onSelected: store.setCategory,
                  itemBuilder: (_) => [for (final e in cats.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
                ),
            ],
          ),
        ),
      );
    }
    if (v.isBox && v.box == 'trash') {
      children.add(
        _banner(
          mc,
          'Thư trong Thùng rác quá 30 ngày sẽ tự động bị xoá vĩnh viễn.',
          action: store.items.isEmpty ? null : TextButton(onPressed: () => act(MailAction.forever, store.items.map((t) => t.id).toList()), child: const Text('Dọn sạch Thùng rác ngay')),
        ),
      );
    }
    if (v.isBox && v.box == 'spam') children.add(_banner(mc, 'Thư trong mục Thư rác quá 30 ngày sẽ tự động bị xoá.'));
    Widget body;
    if (store.loading && store.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (store.items.isEmpty) {
      body = _empty(mc);
    } else {
      body = RefreshIndicator(
        onRefresh: () => store.load(quiet: true),
        child: ListView.builder(
          padding: EdgeInsets.only(bottom: wide ? 24 : 96),
          itemCount: store.items.length,
          itemBuilder: (_, i) => wide ? _row(mc, store.items[i], i) : _phoneRow(mc, store.items[i]),
        ),
      );
    }
    children.add(Expanded(child: body));
    return Column(children: children);
  }

  Widget _banner(MailColors mc, String text, {Widget? action}) => Container(
    color: mc.dark ? const Color(0xFF3A3220) : const Color(0xFFFFF4D6),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 18, color: mc.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: mc.text)),
        ),
        ?action,
      ],
    ),
  );

  Widget _tabs(MailColors mc) {
    const cats = [('primary', Icons.inbox_outlined, 'Chính'), ('promo', Icons.sell_outlined, 'Quảng cáo'), ('social', Icons.people_outline, 'Mạng xã hội')];
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: mc.line)),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          for (final (k, icon, name) in cats)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 250),
                child: InkWell(
                  onTap: () => store.setCategory(k),
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: store.category == k
                        ? BoxDecoration(
                            border: Border(bottom: BorderSide(color: mc.accent, width: 3)),
                          )
                        : null,
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: store.category == k ? mc.accentText : mc.muted),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w500, color: store.category == k ? mc.accentText : mc.muted),
                          ),
                        ),
                        if ((store.counts.categories[k] ?? 0) > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(color: k == 'promo' ? const Color(0xFF0F9D58) : const Color(0xFFE8710A), borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              '${store.counts.categories[k]} mới',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _empty(MailColors mc) {
    final v = store.view;
    final (icon, text) = v.isSearch
        ? (Icons.search, 'Không có thư nào khớp với tìm kiếm của bạn.')
        : v.box == 'inbox' && v.isBox
        ? (Icons.inbox_outlined, 'Không có thư mới. Bạn đã xử lý hết!')
        : v.box == 'starred' && v.isBox
        ? (Icons.star_outline, 'Chưa có thư nào được gắn sao. Gắn sao để dễ tìm lại thư quan trọng.')
        : v.box == 'trash' && v.isBox
        ? (Icons.delete_outline, 'Không có cuộc hội thoại nào trong Thùng rác.')
        : (Icons.mail_outline, 'Không có thư nào ở đây.');
    return ListView(
      children: [
        const SizedBox(height: 72),
        Icon(icon, size: 56, color: mc.faint),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: mc.muted),
        ),
      ],
    );
  }

  String _who(MailThreadSummary t) {
    final v = store.view;
    if (v.box == 'sent' && v.isBox || t.draft) return 'Đến: ${t.to.map((p) => p.short).join(', ')}';
    final ps = t.participants;
    if (ps.length > 1) return ps.skip(ps.length > 3 ? ps.length - 3 : 0).map((p) => p.short).join(', ');
    return ps.isEmpty ? '' : (ps.first.me ? 'tôi' : ps.first.display);
  }

  MailPerson _avatarOf(MailThreadSummary t) => t.participants.lastWhere((p) => !p.me, orElse: () => t.participants.isEmpty ? const MailPerson('?') : t.participants.first);

  List<Widget> _labelChips(MailThreadSummary t) => [
    if (store.view.isSearch && t.box != 'inbox' && kMailBoxes.contains(t.box)) LabelChip(MailStore.boxName(t.box), MailColors.of(context).muted),
    for (final id in t.labels)
      if (id != store.view.label)
        if (store.labelById(id) case final l?) LabelChip(l.name, Color(l.color)),
  ];

  Widget _row(MailColors mc, MailThreadSummary t, int i) => _MailRow(
    key: ValueKey(t.id),
    t: t,
    who: _who(t),
    labels: _labelChips(t),
    selected: store.selected.contains(t.id),
    cursor: i == _cursor,
    box: store.view.box,
    readOnly: store.readOnly,
    onTap: () => openThread(t),
    onSelect: () => store.toggleSelect(t.id),
    onStar: () => act(t.starred ? MailAction.unstar : MailAction.star, [t.id]),
    onAction: (a) => a == null ? _snooze([t.id]) : act(a, [t.id]),
  );

  Widget _phoneRow(MailColors mc, MailThreadSummary t) {
    final sel = store.selected.contains(t.id);
    final bold = t.unread ? FontWeight.w700 : FontWeight.w400;
    return Material(
      color: sel ? mc.sel : mc.bg,
      child: InkWell(
        onTap: () => store.hasSelection ? store.toggleSelect(t.id) : openThread(t),
        onLongPress: store.readOnly ? null : () => store.toggleSelect(t.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: store.readOnly ? null : () => store.toggleSelect(t.id),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: 14),
                  child: MailAvatar(_avatarOf(t), selected: sel),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (t.draft && store.view.box != 'drafts')
                                  TextSpan(
                                    text: 'Thư nháp',
                                    style: TextStyle(color: mc.danger),
                                  )
                                else
                                  TextSpan(text: _who(t)),
                                if (t.count > 1)
                                  TextSpan(
                                    text: '  ${t.count}',
                                    style: TextStyle(fontSize: 12, color: mc.muted, fontWeight: FontWeight.w400),
                                  ),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: bold, color: mc.text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          rowWhen(t) ?? fmtListDate(t.date),
                          style: TextStyle(fontSize: 12, fontWeight: bold, color: rowWhen(t) != null ? mc.accentText : t.unread ? mc.text : mc.muted),
                        ),
                      ],
                    ),
                    Text(
                      t.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: bold, color: mc.text),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.snippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: mc.muted),
                          ),
                        ),
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: store.readOnly ? null : () => act(t.starred ? MailAction.unstar : MailAction.star, [t.id]),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(t.starred ? Icons.star : Icons.star_border, size: 22, color: t.starred ? mc.star : mc.faint),
                          ),
                        ),
                      ],
                    ),
                    if (t.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Row(
                            children: [for (final a in t.attachments) Padding(padding: const EdgeInsets.only(right: 6), child: AttachmentChip(a, maxWidth: 170))],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Một dòng thư trên máy tính: ô chọn, sao, người gửi, nhãn + tiêu đề + đoạn trích, ngày; rê chuột hiện nút thao tác.
class _MailRow extends StatefulWidget {
  const _MailRow({
    super.key,
    required this.t,
    required this.who,
    required this.labels,
    required this.selected,
    required this.cursor,
    required this.box,
    this.readOnly = false,
    required this.onTap,
    required this.onSelect,
    required this.onStar,
    required this.onAction,
  });
  final MailThreadSummary t;
  final String who, box;
  final List<Widget> labels;
  final bool selected, cursor, readOnly;
  final VoidCallback onTap, onSelect, onStar;

  /// null = tạm ẩn.
  final void Function(MailAction? a) onAction;

  @override
  State<_MailRow> createState() => _MailRowState();
}

class _MailRowState extends State<_MailRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final t = widget.t;
    final bold = t.unread ? FontWeight.w700 : FontWeight.w400;
    final bg = widget.selected
        ? mc.sel
        : t.unread
        ? mc.surface
        : mc.rowRead;
    final trash = widget.box == 'trash', spam = widget.box == 'spam';
    final line = Row(
      children: [
        IconButton(
          tooltip: 'Chọn',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          color: widget.selected ? mc.text : mc.faint,
          onPressed: widget.readOnly ? null : widget.onSelect,
          icon: Icon(widget.selected ? Icons.check_box : Icons.check_box_outline_blank),
        ),
        IconButton(
          tooltip: t.starred ? 'Có gắn dấu sao' : 'Không có dấu sao',
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          onPressed: widget.readOnly ? null : widget.onStar,
          icon: Icon(t.starred ? Icons.star : Icons.star_border, color: t.starred ? mc.star : mc.faint),
        ),
        SizedBox(width: 22, child: t.important ? Icon(Icons.label_important, size: 16, color: mc.star) : null),
        SizedBox(
          width: 200,
          child: Padding(
            padding: const EdgeInsets.only(left: 6, right: 16),
            child: Text.rich(
              TextSpan(
                children: [
                  if (t.draft && widget.box != 'drafts')
                    TextSpan(
                      text: 'Thư nháp',
                      style: TextStyle(color: mc.danger),
                    )
                  else
                    TextSpan(text: widget.who),
                  if (t.count > 1)
                    TextSpan(
                      text: '  ${t.count}',
                      style: TextStyle(fontSize: 12, color: mc.muted, fontWeight: FontWeight.w400),
                    ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: bold, color: mc.text),
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              for (final l in widget.labels) Padding(padding: const EdgeInsets.only(right: 6), child: l),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: t.subject,
                        style: TextStyle(fontWeight: bold, color: mc.text),
                      ),
                      TextSpan(
                        text: '  -  ${t.snippet}',
                        style: TextStyle(color: mc.muted),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (t.attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.attach_file, size: 16, color: mc.faint),
                ),
            ],
          ),
        ),
        SizedBox(
          width: _hover && !widget.readOnly ? 160 : 84,
          child: _hover && !widget.readOnly
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (trash || spam)
                      _hb(Icons.move_to_inbox_outlined, trash ? 'Chuyển đến Hộp thư đến' : 'Không phải thư rác', () => widget.onAction(trash ? MailAction.restore : MailAction.notSpam))
                    else
                      _hb(Icons.archive_outlined, 'Lưu trữ', () => widget.onAction(MailAction.archive)),
                    _hb(Icons.delete_outline, trash ? 'Xoá vĩnh viễn' : 'Xoá', () => widget.onAction(trash ? MailAction.forever : MailAction.trash)),
                    _hb(
                      t.unread ? Icons.drafts_outlined : Icons.mark_email_unread_outlined,
                      t.unread ? 'Đánh dấu là đã đọc' : 'Đánh dấu là chưa đọc',
                      () => widget.onAction(t.unread ? MailAction.read : MailAction.unread),
                    ),
                    _hb(Icons.schedule, t.snoozedUntil != null ? 'Bỏ tạm ẩn' : 'Tạm ẩn', () => widget.onAction(null)),
                  ],
                )
              : Text(
                  rowWhen(t) ?? fmtListDate(t.date),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: bold, color: rowWhen(t) != null ? mc.accentText : t.unread ? mc.text : mc.muted),
                ),
        ),
        const SizedBox(width: 16),
      ],
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: bg,
        elevation: _hover ? 2 : 0,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: mc.line),
                left: BorderSide(color: widget.cursor ? mc.accent : Colors.transparent, width: 3),
              ),
            ),
            padding: const EdgeInsets.only(left: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 40, child: line),
                if (t.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 290, bottom: 8, right: 16),
                    child: ClipRect(
                      child: Row(
                        children: [for (final a in t.attachments) Padding(padding: const EdgeInsets.only(right: 8), child: AttachmentChip(a))],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hb(IconData i, String tip, VoidCallback f) => IconButton(tooltip: tip, visualDensity: VisualDensity.compact, iconSize: 18, onPressed: f, icon: Icon(i));
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.k);
  final String k;
  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in k.split(' '))
          if (const {'hoặc', 'rồi', '/', '+'}.contains(p))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(p, style: TextStyle(fontSize: 12, color: mc.muted)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: mc.surface2,
                border: Border.all(color: mc.line),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                p,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontFamilyFallback: ['Menlo', 'Consolas', 'DejaVu Sans Mono']),
              ),
            ),
      ],
    );
  }
}

/// Bảng tìm kiếm nâng cao.
class _Filters extends StatefulWidget {
  const _Filters({required this.initial, required this.labels, required this.onSearch, required this.onCancel});
  final MailQuery initial;
  final List<MailLabel> labels;
  final void Function(String q) onSearch;
  final VoidCallback onCancel;
  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late final MailQuery q = widget.initial;
  late final _from = TextEditingController(text: q.from), _to = TextEditingController(text: q.to), _subj = TextEditingController(text: q.subject), _words = TextEditingController(text: q.words);

  @override
  void dispose() {
    for (final c in [_from, _to, _subj, _words]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final phone = MediaQuery.sizeOf(context).width < 760;
    Widget row(String label, Widget field) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13, color: mc.muted)),
                field,
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(label, style: TextStyle(fontSize: 13, color: mc.muted)),
                ),
                Expanded(child: field),
              ],
            ),
    );
    InputDecoration deco() => const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (phone)
            Row(
              children: [
                IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close), onPressed: widget.onCancel),
                const Text('Tìm kiếm nâng cao', style: TextStyle(fontSize: 18)),
              ],
            ),
          row('Từ', TextField(controller: _from, decoration: deco())),
          row('Đến', TextField(controller: _to, decoration: deco())),
          row('Tiêu đề', TextField(controller: _subj, decoration: deco())),
          row('Có các từ', TextField(controller: _words, decoration: deco())),
          row(
            'Trong vòng',
            DropdownButton<String>(
              isExpanded: true,
              value: q.within,
              onChanged: (v) => setState(() => q.within = v ?? ''),
              items: const [
                DropdownMenuItem(value: '', child: Text('Bất kỳ lúc nào')),
                DropdownMenuItem(value: '1d', child: Text('1 ngày')),
                DropdownMenuItem(value: '3d', child: Text('3 ngày')),
                DropdownMenuItem(value: '7d', child: Text('1 tuần')),
                DropdownMenuItem(value: '1m', child: Text('1 tháng')),
                DropdownMenuItem(value: '1y', child: Text('1 năm')),
              ],
            ),
          ),
          row(
            'Tìm kiếm trong',
            DropdownButton<String>(
              isExpanded: true,
              value: ['', 'inbox', 'sent', 'starred', for (final l in widget.labels) 'label:${l.name}'].contains(q.inBox) ? q.inBox : '',
              onChanged: (v) => setState(() => q.inBox = v ?? ''),
              items: [
                const DropdownMenuItem(value: '', child: Text('Tất cả thư')),
                const DropdownMenuItem(value: 'inbox', child: Text('Hộp thư đến')),
                const DropdownMenuItem(value: 'sent', child: Text('Đã gửi')),
                const DropdownMenuItem(value: 'starred', child: Text('Có gắn sao')),
                for (final l in widget.labels) DropdownMenuItem(value: 'label:${l.name}', child: Text(l.name)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: phone ? 0 : 150, top: 4),
            child: Wrap(
              spacing: 24,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(value: q.attachment, onChanged: (v) => setState(() => q.attachment = v ?? false)),
                    const Text('Có tệp đính kèm'),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(value: q.unread, onChanged: (v) => setState(() => q.unread = v ?? false)),
                    const Text('Chưa đọc'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  for (final c in [_from, _to, _subj, _words]) {
                    c.clear();
                  }
                  q
                    ..within = ''
                    ..inBox = ''
                    ..attachment = false
                    ..unread = false;
                }),
                child: const Text('Xoá bộ lọc'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  q
                    ..from = _from.text.trim()
                    ..to = _to.text.trim()
                    ..subject = _subj.text.trim()
                    ..words = _words.text.trim();
                  widget.onSearch(q.build());
                },
                child: const Text('Tìm kiếm'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Khung trả lời ngay dưới thư (máy tính).
class _InlineReply extends StatefulWidget {
  const _InlineReply({required this.store, required this.args, required this.onDone});
  final MailStore store;
  final ComposeArgs args;

  /// (threadId đã gửi | null, câu báo | 'sent').
  final void Function(String? threadId, String? message) onDone;
  @override
  State<_InlineReply> createState() => _InlineReplyState();
}

class _InlineReplyState extends State<_InlineReply> {
  late final c = ComposeController(widget.store.api, widget.args)..onDraftsChanged = widget.store.refreshCounts;

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    return Material(
      elevation: 3,
      color: mc.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 380,
        child: ComposeBody(c: c, inline: true, onSent: (tid) => widget.onDone(tid ?? '', 'sent'), onClosed: (m) => widget.onDone(null, m)),
      ),
    );
  }
}

/// Dòng thư: "Gửi lúc …" (đã hẹn giờ) hoặc "Đến …" (đang tạm ẩn) thay cho ngày.
String? rowWhen(MailThreadSummary t) =>
    t.scheduledAt != null ? 'Gửi ${whenLabel(t.scheduledAt!)}' : t.snoozedUntil != null ? 'Đến ${whenLabel(t.snoozedUntil!)}' : null;
