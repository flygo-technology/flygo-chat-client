import 'dart:async';
import 'dart:io' show Platform;

import '../i18n/i18n.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'chat_info_page.dart';
import 'chat_list.dart';
import 'flows/flow_nav.dart' show flowsChanged;
import 'flows/flows_page.dart' show FlowDelegationsPage, FlowsHome, openFlowsHome;
import 'flows/workflow_page.dart' show WorkflowPage;
import 'flows/process_list.dart' show openProcess;
import 'flows/flow_experimental.dart' show FlowExperimentalBadge, flowExperimentalMsg, showFlowExperimental;
import 'flows/flows_org.dart' show FlowsOrgPage;
import '../api/flows_api.dart' show FlowDefInfo, FlowsApi;
import 'chat_page.dart';
import 'ai_panel.dart';
import 'ai_consent.dart';
import 'edit_profile_page.dart';
import 'three_finger_swipe.dart';
import 'common.dart';
import '../data/servers.dart';
import '../push/push_service.dart';
import 'server_picker.dart';
import 'status_ui.dart';
import 'agent_page.dart';
import 'agents_view.dart';
import 'qr_login.dart';
import 'mini_app_view.dart';
import 'password_page.dart';
import 'call_history.dart';
import 'bot_page.dart';
import '../update/build_label.dart';
import 'update_banner.dart';
import 'app_badge.dart';
import 'desktop_tray.dart';
import 'flags.dart';
import 'moderation.dart';
import 'tasks_view.dart';
import 'tasks/quick_add.dart' show TaskDigestSwitch;
import 'tasks/task_chat.dart' show openSourceMessage;
import 'tasks/task_logic.dart' show permalinkPostId;
import '../api/boards_api.dart' show isBoardsUrl, parseBoardsPath;
import 'boards/board_page.dart' show openBoard;
import 'boards/boards_home.dart' show BoardsHomePage;
import 'boards/card_detail.dart' show openBoardCard;
import 'links.dart' show internalLinkHook;
import 'panes/pane_layout.dart';
import 'panes/pane_view.dart';
import 'popout_windows.dart';
import '../remote/rc_ui.dart' show RcDevicesPage;
import 'theme.dart';
import 'bang_tin/bang_tin_page.dart' show BangTinTab, bangTinApp, kBangTinTab;
import 'bang_tin/bang_tin_service.dart' show BangTinService;
import 'desk_tabs.dart';
import 'devices_page.dart';
import 'users_admin_page.dart';
import 'wallpaper.dart';
import '../browser/runtime.dart' show kKysoExtensionId;
import '../kyso/kyso_api.dart';
import '../browser/browser_page.dart' show KysoHomePage;
import 'package:flygo_chat/ui/app_route.dart';

/// Các nhóm ô ở tab Bạn (Apps): (tiêu đề đã dịch, mã các ô theo thứ tự). Trợ lý và Bot nằm trong nhóm "Cá nhân";
/// Hẹn giờ đã chuyển sang tab Agents nên không còn ở đây. Nhóm rỗng không hiện (kể cả tiêu đề).
@visibleForTesting
List<(String, List<String>)> youAppGroups({required bool desktop}) => [
      // Ký số (lib/browser, lib/kyso): dòng riêng, mỗi công ty Flygo ID cấp cho mình là một ô, bấm là mở trình duyệt
      // ký số của công ty đó bằng vé Flygo ID. Chưa có công ty nào (bản thử KYSO_POC): một ô Ký số chung như trước.
      (tr('Ký số'), [
        if (KysoApi.spaces.isNotEmpty)
          for (final s in KysoApi.spaces) 'kyso:${s.space.id}'
        else if (KysoApi.available.value)
          'kyso',
      ]),
      (tr('Công việc'), [
        'contacts', 'org', 'delegations', 'calls', 'computers',
      ]),
      (tr('Cá nhân'), [
        'settings',
        // Thiết bị đang đăng nhập, khoá bảo mật (Flygo ID).
        'devices',
        // Điện thoại: quét QR để đăng nhập máy tính cùng mạng LAN (ngay sau Cài đặt).
        if (!desktop) 'qr',
        'assistants',
        'bots',
        'language',
        'password',
        'blocked',
        'update',
        'privacy',
        'terms',
        'ai',
        // Hình nền Trang chủ (máy tính, lưu trên máy này).
        if (desktop) 'wallpaper',
      ]),
    ].where((g) => g.$2.isNotEmpty).toList();

/// Ứng dụng của trang Bạn mở được thành tab (máy tính). Các mục còn lại là hộp thoại / link (Ngôn ngữ, Cập nhật…).
/// Biểu tượng thương hiệu (assets/brands, Simple Icons, CC0): Zalo, WeChat.
Widget brandIcon(String id, double size, Color color) =>
    SvgPicture.asset('assets/brands/$id.svg', width: size, height: size, colorFilter: ColorFilter.mode(color, BlendMode.srcIn));

/// Mini app hiện ở mục "Chính" của Trang chủ thay vì mục Ứng dụng.
/// Bảng tin: ô riêng ngay sau "Dự án AI" ở mục Chính (Sếp, 2026-11-10); Todo ngay sau Bảng tin (Sếp, 2026-11-11).
const kLeadMiniApps = ['vn.flygo.bangtin', 'vn.flygo.todo'];
/// Teable, Multica, Nebula, Codex nằm ở mục Ứng dụng (Sếp, 2026-11-10).
const kMainMiniApps = {'vn.flygo.bangtin', 'vn.flygo.todo', 'vn.flygo.show'};

/// Thứ tự các app nhóm Công việc ở mục Chính (Sếp 10/11); app khác của nhóm (nếu có) đứng sau.
List<String> _workAppOrder(Iterable<String> ids) {
  const order = ['org', 'contacts', 'delegations', 'calls', 'computers'];
  final all = ids.toList();
  return [...order.where(all.contains), ...all.where((id) => !order.contains(id))];
}

const kDeskTabApps = {'zalo', 'wechat', 'wallpaper', 'devices', 'users', 'contacts', 'org', 'delegations', 'calls', 'computers', 'settings', 'assistants', 'bots', 'password', 'blocked'};

/// Màn hình chính. Màn hình rộng (máy tính) chia hai cột, vùng nội dung chia được tới 4 ô; màn hình hẹp
/// (điện thoại) có thanh tab nổi ở dưới như WhatsApp iOS.
class HomePage extends StatefulWidget {
  final Future<void> Function() onLogout;
  final void Function(String url) onSwitchServer;
  /// Cửa sổ riêng của một mục thanh tab (`--section=`): chỉ hiện mục đó, mở chat chồng lên như điện thoại.
  final String? solo;
  const HomePage({super.key, required this.onLogout, required this.onSwitchServer, this.solo});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ---------------------------------------------------------------- chia ô (máy tính)
  /// Các ô của vùng nội dung (1–4 ô). Một ô: giao diện như trước (chat giữa + cột phải luồng / AI / thông tin).
  PaneLayout _panes = PaneLayout();
  /// Người dùng đã đổi bố cục trước khi bố cục đã lưu đọc xong: không ghi đè.
  bool _panesTouched = false;
  bool _panesPruned = false;
  Timer? _paneSave;
  String _paneSig = '';
  final Map<String, GlobalKey> _paneKeys = {};
  /// Navigator của từng ô, đổi nội dung ô thì tạo khoá mới (xem [_sideNav]).
  final Map<String, (String, GlobalKey<NavigatorState>)> _paneNavs = {};
  final Map<String, FocusScopeNode> _paneScopes = {};

  /// Cuộc trò chuyện ở ô đang chọn (một ô: cuộc đang mở ở giữa như trước).
  String? get _selected {
    final c = _panes.focused.content;
    return c != null && c.isChat ? c.id : null;
  }

  bool get _multi => _wide && _panes.isMulti;
  String? _infoFor;
  /// Máy tính: chủ đề đang mở ở cột phải (id kênh, id tin gốc).
  (String, String)? _thread;
  /// Độ rộng cột (máy tính, kéo thanh chia để đổi): danh sách chat, cột phải (luồng), cột thông tin.
  /// Cột phải chưa kéo lần nào thì rộng bằng chat chính.
  double _leftW = 380, _infoW = 380;
  double? _rightW;
  /// Luồng riêng tư mở ở cột phải: (chat chính, luồng riêng).
  (String, String)? _side;
  /// Trang đang mở ở vùng giữa thay cho chat (máy tính), và khung ở cột phải của trang đó.
  (String, WidgetBuilder)? _page;
  (String, WidgetBuilder)? _pageSide;
  /// Navigator của cột phải. Đổi luồng ở cột phải thì tạo khoá mới: dùng lại cùng GlobalKey sẽ làm Flutter
  /// chuyển nguyên Navigator cũ (vẫn đang hiện luồng cũ) sang chỗ mới → bấm luồng bí mật tầng 2 không thấy trang mới.
  var _sideNav = GlobalKey<NavigatorState>();
  /// Nhóm đang tạm đóng cột trợ lý AI (bấm ✕); mở nhóm khác thì cột AI hiện lại.
  String? _aiHidden;
  final _leftNav = GlobalKey<NavigatorState>();
  String _query = '';
  /// Ô tìm ở góc trên bên phải trang Ứng dụng: lọc ô theo tên (không dấu).
  String _appQ = '';
  final _appQCtl = TextEditingController();
  /// Cột AI đang mở phiên AI của luồng nào: (nhóm, id tin gốc); null = AI của cả nhóm.
  (String, String)? _aiThread;
  ChatFilter _filter = ChatFilter.all;
  /// Tab lọc trong trang Chat ("Luồng riêng" đứng thứ hai) và key từng tab để cuộn tab đang chọn vào tầm nhìn.
  static const _filters = chatFilterTabs;
  final _filterKeys = {for (final f in ChatFilter.values) f: GlobalKey()};

  /// Mỗi tab lọc là một trang: vuốt ngang trang trượt theo ngón tay (như tab Các trợ lý), bấm tab thì trượt tới.
  late final _filterPages = PageController(initialPage: _filters.indexOf(_filter));

  void _setFilter(ChatFilter f, {bool fromPage = false}) {
    setState(() => _filter = f);
    if (!fromPage && _filterPages.hasClients) {
      _filterPages.animateToPage(_filters.indexOf(f), duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _filterKeys[f]!.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, alignment: .5, duration: const Duration(milliseconds: 200));
    });
  }

  int _tab = 0;
  final _searchCtl = TextEditingController();

  bool get _wide => widget.solo == null && MediaQuery.sizeOf(context).width >= 860;
  late final AppState _app;
  final _soloNav = GlobalKey<NavigatorState>();

  // ---------------------------------------------------------------- tab (máy tính)
  /// Các tab như trình duyệt. Tab Chat đầu tiên giữ bố cục cũ (danh sách, chia ô, cột phải); các tab khác tự giữ
  /// trạng thái riêng (IndexedStack). Điện thoại và cửa sổ riêng không có tab.
  List<DeskTab> _deskTabs = [DeskTab('chat')];
  int _deskCur = 0;
  final List<DeskTab> _closedTabs = [];
  bool _tabsTouched = false;
  Timer? _tabSave;
  /// Tiêu đề tab mới khi đang mở một mini app trong tab đó.
  final Map<String, String> _tabTitles = {};
  /// Cuộc trò chuyện đang hiện ở giữa của từng tab (trừ tab Chat chính).
  final Map<String, String?> _tabChat = {};
  final Map<String, GlobalKey<NavigatorState>> _tabNavs = {};
  final _mainLayoutKey = GlobalKey(debugLabel: 'main-chat-layout');
  /// Danh sách quy trình cho menu tab mới (tải một lần mỗi lần mở app).
  Future<List<FlowDefInfo>>? _flowDefs;
  DateTime _flowDefsAt = DateTime(2000);
  int _flowDefsRev = -1;

  /// Danh sách quy trình cho Trang chủ: tải lại khi quá 20 giây hoặc vừa có thay đổi quy trình (ẩn / hiện, lưu,
  /// đổi người được thấy…), để ẩn một quy trình là Trang chủ cập nhật ngay, không phải mở lại app.
  Future<List<FlowDefInfo>> _homeFlowDefs(AppState app) {
    final stale = DateTime.now().difference(_flowDefsAt) > const Duration(seconds: 20) || _flowDefsRev != flowsChanged.value;
    if (_flowDefs == null || stale) {
      _flowDefsAt = DateTime.now();
      _flowDefsRev = flowsChanged.value;
      final next = FlowsApi(app.token).defs();
      // Giữ danh sách cũ trên màn hình tới khi có danh sách mới (không nhấp nháy).
      next.then((_) {
        if (mounted) setState(() => _flowDefs = next);
      }).catchError((_) {});
      _flowDefs ??= next;
    }
    return _flowDefs!;
  }
  /// Quản trị Quy trình (GET /flows/me admin): chỉ người này thấy ô Quy trình và mục các quy trình ở Trang chủ.
  bool _flowsAdmin = false;
  bool _flowsAdminAsked = false;
    /// Mở app: thêm tab Trợ lý ngay sau tab Chat một lần (người có trợ lý AI); đóng rồi thì không tự mở lại.
  bool _agentsTabEnsured = false;
  bool _bangTinTabEnsured = false;

  /// Mở app: thêm tab Bảng tin một lần (máy chủ có Bảng tin), sau tab Dự án AI (không có thì sau tab Chat).
  void _ensureBangTinTab() {
    if (_bangTinTabEnsured || (bangTinApp() == null && !BangTinService.instance.hasApp)) return;
    _bangTinTabEnsured = true;
    if (_deskTabs.any((t) => t.kind == 'app' && t.arg == kBangTinTab)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cur = _deskTabs[_deskCur];
            final chat = _deskTabs.indexWhere((t) => t.kind == 'chat');
      final agents = _deskTabs.indexWhere((t) => t.kind == 'agents');
      setState(() {
        _deskTabs.insert((agents > chat ? agents : chat) + 1, DeskTab('app', arg: kBangTinTab));
        _deskCur = _deskTabs.indexOf(cur);
      });
      _tabsChanged();
    });
  }

    void _ensureAgentsTab(AppState app) {
    _ensureBangTinTab();
    if (_agentsTabEnsured || !app.hasUsableAgents) return;
    _agentsTabEnsured = true;
    if (_deskTabs.any((t) => t.kind == 'agents')) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cur = _deskTabs[_deskCur];
            // Thứ tự mặc định (Sếp): Chat, Dự án AI, Bảng tin.
      final chat = _deskTabs.indexWhere((t) => t.kind == 'chat');
      setState(() {
        _deskTabs.insert(chat + 1, DeskTab('agents'));
        _deskCur = _deskTabs.indexOf(cur);
      });
      _tabsChanged();
    });
  }

  /// Mục Quản trị ở Trang chủ: các app mình được cấp quyền quản trị trong Flygo ID (GET /v1/me/admin) có trang
  /// quản trị web. Quy trình quản trị ngay trong ô Quy trình nên không lặp lại ở đây.
  List<Map<String, dynamic>> _adminApps = const [];
  String? _adminAskedFor;

  /// Quản trị viên Flygo ID: thêm ô "Người dùng" ở mục Quản trị.
  bool _usersAdmin = false;

  void _askAdmin() {
    final id = KysoApi.flygoId;
    if (id == null || _adminAskedFor == kServerUrl) return;
    _adminAskedFor = kServerUrl;
    UsersAdminPage.allowed(id).then((ok) {
      if (mounted && ok != _usersAdmin) setState(() => _usersAdmin = ok);
    });
    id.myAdmin().then((apps) {
      if (mounted) setState(() => _adminApps = [for (final a in apps) if (a['url'] is String && a['native'] == null) a]);
    }).catchError((_) {
      _adminAskedFor = null;
    });
  }

  /// Tên ô trong mục Quản trị: bỏ chữ "Quản trị" ở đầu (đã có tiêu đề mục), vd "Quản trị Ký số" -> "Ký số".
  String _adminLabel(Map<String, dynamic> a) {
    final n = '${a['name'] ?? a['app']}'.trim();
    final s = n.replaceFirst(RegExp(r'^quản trị\s+', caseSensitive: false), '');
    return s.isEmpty ? n : '${s[0].toUpperCase()}${s.substring(1)}';
  }

  Future<void> _openAdmin(Map<String, dynamic> a) async {
    if (a['app'] == kKysoExtensionId) return KysoApi.openAdmin(context);
    final u = Uri.tryParse('${a['url']}');
    if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  void _askFlowsAdmin() {
    if (_flowsAdminAsked) return;
    _flowsAdminAsked = true;
    FlowsApi(_app.token).me().then((m) {
      if (mounted && m['admin'] == true) setState(() => _flowsAdmin = true);
    }).catchError((_) {
      _flowsAdminAsked = false;
    });
  }

  GlobalKey<NavigatorState> _tabNav(DeskTab t) => _tabNavs.putIfAbsent(t.id, () => GlobalKey<NavigatorState>(debugLabel: 'tab-${t.id}'));

  /// Tab Chat giữ bố cục cũ: tab Chat đầu tiên.
  DeskTab? get _mainChatTab {
    for (final t in _deskTabs) {
      if (t.kind == 'chat') return t;
    }
    return null;
  }

  void _tabsChanged() {
    _tabsTouched = true;
    _tabSave?.cancel();
    _tabSave = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _app.saveDeskTabs(_tabsJson()).catchError((_) {});
    });
  }

  Map<String, Object?> _tabsJson() => {'v': 2, 'tabs': [for (final t in _deskTabs) t.toJson()], 'current': _deskCur};

  /// Đã đọc xong các tab lưu lần trước (có hay không).
  bool _tabsRestored = false;

  void _restoreTabs(Object? j) {
    _tabsRestored = true;
    if (j is! Map) {
      if (mounted) setState(() {});
      return;
    }
    final tabs = [for (final x in (j['tabs'] as List? ?? const [])) ?DeskTab.fromJson(x)];
    if (tabs.isEmpty) return;
    // Bản 358 đầu tiên ghim sẵn tab Chat (tab chỉ còn biểu tượng): bỏ ghim một lần.
    if (j['v'] != 2) {
      for (final t in tabs) {
        if (t.kind == 'chat') t.pinned = false;
      }
    }
    // Mở app luôn có sẵn tab Chat và mở ở tab đó (người dùng vẫn đóng được tab).
    if (!tabs.any((t) => t.kind == 'chat')) tabs.insert(0, DeskTab('chat'));
    final chat = tabs.indexWhere((t) => t.kind == 'chat');
    setState(() {
      _deskTabs = tabs;
      _deskCur = chat;
    });
  }

  /// Mở tab mới ngay sau tab đang chọn và chuyển sang tab đó. Tab một cuộc trò chuyện đã mở thì chuyển tới.
  void _openTab(DeskTab t) {
    if (!mounted) return;
        // Chat / luồng / Bảng tin đã có tab thì chuyển sang tab đó, không mở thêm.
    if (t.kind == 'conv' || t.kind == 'thread' || (t.kind == 'app' && t.arg == kBangTinTab)) {
      final i = _deskTabs.indexWhere((x) => x.kind == t.kind && x.arg == t.arg);
      if (i >= 0) return _selectDeskTab(i);
    }
    setState(() {
      final at = (_deskCur + 1).clamp(0, _deskTabs.length);
      _deskTabs.insert(at, t);
      _deskCur = at;
    });
    _tabsChanged();
  }

  void _selectDeskTab(int i) {
    if (i < 0 || i >= _deskTabs.length || i == _deskCur) return;
    setState(() => _deskCur = i);
    _tabsChanged();
  }

  void _closeDeskTab(int i) {
    if (i < 0 || i >= _deskTabs.length || _deskTabs[i].pinned) return;
    final t = _deskTabs[i];
    setState(() {
      _deskTabs.removeAt(i);
      _closedTabs.add(t);
      if (_closedTabs.length > 20) _closedTabs.removeAt(0);
      // Đóng tab cuối: còn lại một tab mới (menu ứng dụng).
      if (_deskTabs.isEmpty) _deskTabs.add(DeskTab('launcher'));
      if (_deskCur > i || _deskCur >= _deskTabs.length) _deskCur = (_deskCur - 1).clamp(0, _deskTabs.length - 1);
    });
    _tabNavs.remove(t.id);
    _tabTitles.remove(t.id);
    _tabChat.remove(t.id);
    _tabsChanged();
  }

  void _reopenClosedTab() {
    if (_closedTabs.isEmpty) return;
    _openTab(_closedTabs.removeLast());
  }

  void _moveDeskTab(int from, int to) {
    if (from == to) return;
    final cur = _deskTabs[_deskCur];
    setState(() {
      final t = _deskTabs.removeAt(from);
      _deskTabs.insert(to.clamp(0, _deskTabs.length), t);
      _deskCur = _deskTabs.indexOf(cur);
    });
    _tabsChanged();
  }

  void _togglePinTab(int i) {
    final cur = _deskTabs[_deskCur];
    setState(() {
      final t = _deskTabs[i]..pinned = !_deskTabs[i].pinned;
      // Tab ghim xếp đầu thanh tab như trình duyệt.
      _deskTabs.removeAt(i);
      final pinnedCount = _deskTabs.where((x) => x.pinned).length;
      _deskTabs.insert(t.pinned ? pinnedCount : pinnedCount, t);
      _deskCur = _deskTabs.indexOf(cur);
    });
    _tabsChanged();
  }

  void _closeOtherTabs(int i) {
    final keep = _deskTabs[i];
    setState(() {
      final gone = _deskTabs.where((t) => t != keep && !t.pinned).toList();
      _closedTabs.addAll(gone);
      _deskTabs = _deskTabs.where((t) => t == keep || t.pinned).toList();
      _deskCur = _deskTabs.indexOf(keep);
    });
    _tabsChanged();
  }

  /// Chọn một ứng dụng trong menu tab mới: mở ứng dụng ở một tab mới ngay sau, tab menu vẫn giữ nguyên.
  void _launchInTab(DeskTab from, String id) {
    final DeskTab t;
    if (id == 'chat' || id == 'agents' || id == 'flows') {
      t = DeskTab(id);
    } else if (id.startsWith('flow:')) {
      t = DeskTab('flow', arg: id.substring(5));
    } else {
      t = DeskTab('app', arg: id);
    }
    if (id == 'calls') _app.markCallsSeen();
    final i = _deskTabs.indexOf(from);
    if (i >= 0 && i != _deskCur) setState(() => _deskCur = i);
    _openTab(t);
  }

  /// Chat mở từ nơi khác (thông báo, link, danh bạ trong tab khác): về tab Chat chính, chưa có thì mở thêm.
  void _showMainChatTab() {
    if (!_wide) return;
    final main = _mainChatTab;
    if (main == null) {
      setState(() {
        _deskTabs.insert(0, DeskTab('chat'));
        _deskCur = 0;
      });
      _tabsChanged();
      return;
    }
    _selectDeskTab(_deskTabs.indexOf(main));
  }

  void _kysoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Ô Ký số hiện / ẩn theo Flygo ID (hỏi một lần mỗi phiên chat).
    KysoApi.available.addListener(_kysoChanged);
    KysoApi.spacesChanged.addListener(_kysoChanged);
    // Bảng tin chạy nền (Sếp): tab hiện ngay, đếm tin mới, tải sẵn trang đầu.
    BangTinService.instance.addListener(_kysoChanged);
    unawaited(BangTinService.instance.start(context.read<AppState>().token));
    if (isDesktop) Wallpaper.load();
    // Ẩn / hiện / lưu quy trình ở mục Quy trình: Trang chủ tải lại danh sách quy trình ngay.
    flowsChanged.addListener(_kysoChanged);
    unawaited(KysoApi.refresh(context.read<AppState>().token));
    // Thiết bị: báo Flygo ID máy này đang dùng (mỗi 6 giờ).
    unawaited(DevicesPage.heartbeat(context.read<AppState>().token));
    if (widget.solo != null) {
      // Cửa sổ riêng của một mục: không nhận thông báo / link, không chấm số trên biểu tượng app (cửa sổ chính lo).
      _app = context.read<AppState>();
      _tab = PaneSections.tabOf(widget.solo!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppState>().loadWorkThreads();
      });
      return;
    }
    PushService.openChatHook = _open;
    // Link thẻ / bảng Boards trong tin nhắn: mở màn hình Boards gốc của app.
    internalLinkHook = _openInternalLink;
    PushService.openThreadHook = _hostOpenThread;
    _app = context.read<AppState>();
    AppBadge.attach(_app);
    context.read<AppState>().loadLayout().then((m) {
      if (!mounted) return;
      setState(() {
        _leftW = m['left'] ?? _leftW;
        _infoW = m['info'] ?? _infoW;
        _rightW = m['right'];
      });
    });
    // Bố cục chia ô đã lưu của máy chủ này.
    _app.loadPanes().then((j) {
      if (!mounted || j == null || _panesTouched) return;
      setState(() => _panes = PaneLayout.fromJson(j));
      _panesPruned = false;
      _syncPaneFocus();
    });
    // Các tab máy tính lần trước.
    _app.loadDeskTabs().then((j) {
      if (!mounted) return;
      _tabsTouched ? setState(() => _tabsRestored = true) : _restoreTabs(j);
    });
    // Phím tắt: tab (Ctrl/Cmd+T, W, Tab, 1..9, Shift+T), chuyển nhanh tới chat (Ctrl/Cmd+K).
    HardwareKeyboard.instance.addHandler(_onKey);
    // Cửa sổ riêng tách từ các ô: mở lại các cửa sổ còn mở lúc thoát app lần trước.
    if (isDesktop) PopoutWindows.startMain();
    // Số luồng công việc đang dang dở (chấm trên tab Luồng).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadWorkThreads();
    });
  }

  // ---------------------------------------------------------------- chia ô
  GlobalKey _paneKey(String id) => _paneKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'pane-$id'));

  FocusScopeNode _scopeOf(String id) => _paneScopes.putIfAbsent(id, () => FocusScopeNode(debugLabel: 'pane-$id'));

  GlobalKey<NavigatorState> _navFor(PaneLeaf l) {
    final k = l.content?.key ?? '';
    final cur = _paneNavs[l.id];
    if (cur != null && cur.$1 == k) return cur.$2;
    final n = GlobalKey<NavigatorState>();
    _paneNavs[l.id] = (k, n);
    return n;
  }

  /// Sau mỗi lần đổi bố cục: lưu (gộp các lần đổi liên tiếp) và báo AppState ô nào đang chọn.
  void _panesChanged() {
    _panesTouched = true;
    _paneSave?.cancel();
    _paneSave = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _app.savePanes(_panes.toJson()).catchError((_) {});
    });
    _syncPaneFocus();
  }

  /// AppState chỉ tự đánh dấu đã đọc ở ô đang chọn (màn chia ô), báo không hiện thông báo cho các ô đang hiện.
  void _syncPaneFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.solo != null) return;
      var multi = _multi;
      final max = multi ? _panes.maximizedId : null;
      final hidden = <String>{
        if (max != null)
          for (final l in _panes.leaves)
            if (l.id != max && l.content?.isChat == true) l.content!.id,
      };
      // Một ô (hoặc điện thoại): như trước, mọi chat đang mở đều là chat đang đọc.
      var focus = multi ? _selected : null;
      // Tab máy tính: chat của các tab không đang chọn coi như bị che (không tự đánh dấu đã đọc, vẫn có thông báo).
      if (_wide && _deskTabs.length > 1) {
        final cur = _deskTabs[_deskCur];
        if (cur == _mainChatTab) {
          final mainChats = {?_selected, ?_side?.$2, for (final l in _panes.leaves) if (l.content?.isChat == true) l.content!.id};
          for (final e in _tabChat.entries) {
            if (e.key != cur.id && e.value != null && !mainChats.contains(e.value)) hidden.add(e.value!);
          }
        } else {
          final mine = _tabChat[cur.id];
          hidden.addAll(_app.viewingIds.where((id) => id != mine));
          multi = true;
          focus = mine;
        }
      }
      final sig = '$multi|$focus|${hidden.join(',')}';
      if (sig == _paneSig) return;
      _paneSig = sig;
      _app.setPaneFocus(multi: multi, channelId: focus, hidden: hidden);
    });
  }

  void _focusPane(String id, {bool keyboard = false}) {
    if (id != _panes.focusedId) {
      setState(() => _panes.focus(id));
      _panesChanged();
    }
    if (keyboard) {
      final scope = _scopeOf(id);
      scope.requestFocus();
      if (scope.focusedChild == null) scope.nextFocus();
    }
  }

  void _closePane(String id) {
    setState(() => _panes.close(id));
    _paneNavs.remove(id);
    _paneKeys.remove(id);
    // Ô vẫn còn trong cây tới khung hình sau: huỷ FocusScopeNode sau khi ô đã gỡ.
    final scope = _paneScopes.remove(id);
    if (scope != null) WidgetsBinding.instance.addPostFrameCallback((_) => scope.dispose());
    _panesChanged();
  }

  /// Mở chat [channelId] từ ô [fromId] (ô danh sách thì mở ở ô chat khác / chia đôi). Trả về id ô hiện chat đó.
  String _openFromPane(String fromId, String channelId) {
    late PaneLeaf l;
    setState(() => l = _panes.openFrom(fromId, PaneContent.chat(channelId)));
    _panesChanged();
    return l.id;
  }

  /// Mở trang chồng lên trong ô [paneId] (sau khung hình: ô / navigator có thể vừa được tạo).
  void _pushInPane(String paneId, WidgetBuilder builder) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _paneNavs[paneId]?.$2.currentState?.push(AppPageRoute(builder: builder));
    });
  }

  void _onDrop(String targetId, PaneEdge edge, PaneDragData d) {
    setState(() => _panes.drop(targetId, edge, d.content, fromPane: d.fromPane));
    _panesChanged();
  }

  /// Tách nội dung ra cửa sổ riêng (máy tính). Kéo từ một ô thì đóng ô đó.
  Future<void> _popOut(PaneDragData d) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await PopoutWindows.open(d.content);
    if (!mounted) return;
    final msg = popoutNotice(r);
    if (msg != null) messenger.showSnackBar(toast(Text(msg)));
    final from = d.fromPane;
    if (from != null && (r == PopoutResult.opened || r == PopoutResult.alreadyOpen) && _panes.isMulti) _closePane(from);
  }

  (IconData, String) _sectionInfo(String s) => switch (s) {
        PaneSections.agents => (Icons.auto_awesome_outlined, tr('Các trợ lý')),
        PaneSections.tasks => (Icons.task_alt_rounded, tr('Việc')),
        PaneSections.threads => (Icons.account_tree_outlined, tr('Quy trình')),
        PaneSections.apps => (Icons.apps_rounded, tr('Bạn')),
        _ => (Icons.chat_bubble_outline, tr('Chat')),
      };

  PaneLabel _describe(PaneContent c) {
    final pal = Pal.of(context);
    if (c.isSection) {
      final (icon, label) = _sectionInfo(c.id);
      return PaneLabel(label, Icon(icon, size: 18, color: pal.accentText));
    }
    final app = _app;
    final ch = app.channels[c.id];
    if (ch == null) return PaneLabel(tr('Cuộc trò chuyện'), Icon(Icons.chat_bubble_outline, size: 18, color: pal.sub));
    final title = app.channelTitle(ch);
    final other = ch.isDirect && app.me != null ? ch.otherUserId(app.me!.id) : null;
    return PaneLabel(
        title, Avatar(userId: other, name: title, size: 22, status: false, icon: other == null ? chatIcon(ch) : null, channel: ch));
  }

  /// ChatHost của một ô: một ô thì như trước (luồng / thông tin / AI ở cột phải); từ hai ô thì mở chồng ngay trong ô
  /// (ô chat) hoặc mở ở ô chat khác (ô danh sách).
  Widget _paneHost(String id, Widget child) {
    bool chatPane() => _panes.leaf(id)?.content?.isChat == true;
    return ChatHost(
      openChat: (c) => _multi || !chatPane() ? _openFromPane(id, c) : _open(c),
      openInfo: (c) => _multi ? _pushInPane(id, (_) => ChatInfoPage(channelId: c)) : _hostOpenInfo(c),
      openThread: (cid, root) {
        if (!_multi) return _hostOpenThread(cid, root);
        final target = chatPane() && _panes.leaf(id)?.content?.id == cid ? id : _openFromPane(id, cid);
        _pushInPane(target, (_) => ThreadPage(channelId: cid, rootId: root));
      },
      openSide: (c) {
        if (!_multi) return _openSide(c);
        chatPane() ? _pushInPane(id, (_) => ChatPage(channelId: c)) : _openFromPane(id, c);
      },
      openAi: (g, {thread}) {
        if (!_multi) return _hostOpenAi(g, thread: thread);
        final target = chatPane() && _panes.leaf(id)?.content?.id == g ? id : _openFromPane(id, g);
        _pushInPane(target, (ctx) => AiPanel(groupId: g, thread: thread, onClose: () => Navigator.of(ctx).maybePop()));
      },
      child: child,
    );
  }

  Widget _paneBody(BuildContext context, PaneLeaf l) {
    final app = context.read<AppState>();
    final c = l.content;
    final Widget inner = c == null || (c.isChat && !app.channels.containsKey(c.id))
        ? const _Welcome()
        : _ColumnNavigator(
            key: ValueKey(c.key),
            navKey: _navFor(l),
            root: c.isChat ? ChatPage(channelId: c.id, embedded: true) : _paneSection(l.id, c.id),
          );
    return FocusScope(node: _scopeOf(l.id), child: _paneHost(l.id, inner));
  }

  /// Một mục thanh tab hiện trong ô: mở chat thì mở ở ô chat khác (không thay chính ô danh sách).
  Widget _paneSection(String paneId, String section) {
    NavigatorState? nav() => _paneNavs[paneId]?.$2.currentState;
    void open(String id) => _openFromPane(paneId, id);
    return Builder(builder: (context) {
      final app = context.watch<AppState>();
      return Scaffold(
        backgroundColor: Pal.of(context).bg,
        body: section == PaneSections.chats
            ? _PaneChatList(onOpen: open, onSearchMessages: (q) => nav()?.push(AppPageRoute(builder: (_) => SearchPage(terms: q, onOpen: open))))
            : _sectionBody(PaneSections.tabOf(section), app, 16, nav, open: open, header: const SizedBox(height: 4)),
      );
    });
  }

  /// Phím tắt máy tính: Ctrl/Cmd+T tab mới, Ctrl/Cmd+W đóng ô (khi chia ô) hoặc đóng tab, Ctrl+Tab / Ctrl+Shift+Tab
  /// chuyển tab, Ctrl/Cmd+1..8 tới tab, 9 tab cuối, Ctrl/Cmd+Shift+T mở lại tab vừa đóng, Ctrl/Cmd+K chuyển nhanh tới chat.
  /// Alt+1..4 chọn ô (màn chia ô của tab Chat).
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !mounted || !_wide) return false;
    final kb = HardwareKeyboard.instance;
    final mod = Platform.isMacOS ? kb.isMetaPressed : kb.isControlPressed;
    // Đang mở trang / hộp thoại chồng lên màn hình chính: để trang đó xử lý.
    if (!(ModalRoute.isCurrentOf(context) ?? false)) return false;
    final k = e.logicalKey;
    const digits = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final i = digits.indexOf(k);
    final onMainChat = _deskTabs[_deskCur] == _mainChatTab;
    // Alt+1..4: chọn ô trong tab Chat đang chia ô.
    if (kb.isAltPressed && !mod && i >= 0 && i < 4 && onMainChat) {
      final leaves = _panes.leaves;
      if (i >= leaves.length) return false;
      _focusPane(leaves[i].id, keyboard: true);
      return true;
    }
    // Ctrl+Tab luôn là Ctrl (cả macOS, như trình duyệt).
    if (k == LogicalKeyboardKey.tab && kb.isControlPressed && !kb.isAltPressed) {
      if (_deskTabs.length > 1) _selectDeskTab((_deskCur + (kb.isShiftPressed ? -1 : 1)) % _deskTabs.length);
      return true;
    }
    if (!mod || kb.isAltPressed) return false;
    if (kb.isShiftPressed) {
      if (k == LogicalKeyboardKey.keyT) {
        _reopenClosedTab();
        return true;
      }
      return false;
    }
    if (i >= 0) {
      _selectDeskTab(i == 8 ? _deskTabs.length - 1 : i);
      return true;
    }
    if (k == LogicalKeyboardKey.keyT) {
      _openTab(DeskTab('launcher'));
      return true;
    }
    if (k == LogicalKeyboardKey.keyW) {
      if (onMainChat && _panes.isMulti) {
        _closePane(_panes.focusedId);
      } else {
        _closeDeskTab(_deskCur);
      }
      return true;
    }
    if (k == LogicalKeyboardKey.keyK) {
      showQuickSwitcher(context).then((id) {
        if (id != null && mounted) _open(id);
      });
      return true;
    }
    return false;
  }

  /// Vùng nội dung (máy tính): các ô.
  Widget _paneArea(AppState app) {
    // Bố cục đọc từ máy: bỏ ô của cuộc trò chuyện không còn (đã rời / bị xoá) khi đã đồng bộ xong.
    if (!_panesPruned && app.ready) {
      _panesPruned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _panes.prune((c) => !c.isChat || app.channels.containsKey(c.id)));
        _syncPaneFocus();
      });
    }
    return PaneArea(
      layout: _panes,
      keyOf: _paneKey,
      body: _paneBody,
      describe: _describe,
      unread: (l) => l.content?.isChat == true && app.unreadOf(l.content!.id) > 0,
      onFocus: _focusPane,
      onDrop: _onDrop,
      onClose: _closePane,
      onMaximize: (id) {
        setState(() => _panes.toggleMaximize(id));
        _panesChanged();
      },
      onPopOut: isDesktop ? (id) => _popOut(PaneDragData(_panes.leaf(id)!.content!, fromPane: id)) : null,
      onRatio: (sid, r) => setState(() => _panes.setRatio(sid, r)),
      onRatioEnd: _panesChanged,
    );
  }

  /// Cột trái (máy tính) nằm trong bộ điều hướng riêng nên không tự dựng lại theo trang chính:
  /// mỗi lần đổi trạng thái thì báo cho nó dựng lại.
  final _leftTick = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _leftTick.value++;
  }

  /// Link Boards của máy chủ đang dùng: mở màn hình gốc của app (thẻ, bảng, hoặc danh sách bảng), không mở web.
  bool _openInternalLink(Uri u) {
    // Permalink tin nhắn của máy chủ đang dùng (vd. "Tin nhắn gốc" trong việc tạo từ chat): mở chat và cuộn tới tin.
    final pl = permalinkPostId(u, kServerUrl);
    if (pl != null && mounted) {
      openSourceMessage(context, context.read<AppState>(), pl);
      return true;
    }
    if (!isBoardsUrl(u) || !mounted) return false;
    final p = parseBoardsPath(u);
    if (p == null) {
      Navigator.of(context, rootNavigator: true).push(AppPageRoute(builder: (_) => const BoardsHomePage()));
    } else if (p.$3 != null) {
      openBoardCard(context, p.$1, p.$3!);
    } else {
      openBoard(context, p.$1, viewId: p.$2);
    }
    return true;
  }

  /// Tab Apps trên điện thoại dùng Trang chủ như máy tính: ô mở tab (máy tính) thì ở đây chuyển tab dưới hoặc mở trang.
  void _mobileLaunch(String id, AppState app) {
    final nav = Navigator.of(context);
    if (id == 'chat') return _selectTab(0);
    if (id == 'agents') return _selectTab(2);
    if (id == 'flows') {
      openFlowsHome(context, app);
      return;
    }
    if (id.startsWith('flow:')) {
      final parts = id.substring(5).split('\t');
      nav.push(AppPageRoute(
          builder: (_) => WorkflowPage(app: app, flowId: parts.first, name: parts.length > 1 ? parts[1] : '', icon: parts.length > 2 ? parts[2] : '')));
      return;
    }
    final title = switch (id) { 'zalo' => 'Zalo', 'wechat' => 'WeChat', _ => '' };
    nav.push(AppPageRoute(
        builder: (_) => Scaffold(appBar: title.isEmpty ? null : AppBar(title: Text(title)), body: _appPageBody(id, app))));
  }

  void _selectTab(int i) {
    if (i == _tab) return;
    final app = context.read<AppState>();
    if (i == 1) app.loadWorkThreads();
    setState(() => _tab = i);
  }

  /// Mở trang hồ sơ (ảnh đại diện góc trên bên trái).
  void _openProfile(NavigatorState? nav) => nav?.push(AppPageRoute(
      builder: (_) => _ProfilePage(onLogout: _confirmLogout, onSwitchServer: _switchServer)));

  // ---------------------------------------------------------------- vuốt 3 ngón lên: chọn máy chủ
  /// Điện thoại: vuốt 3 ngón từ dưới lên ở bất kỳ đâu trong app mở bảng chọn / thêm máy chủ (Sếp, 2026-11-13: thay cho
  /// nút đổi máy chủ ở đầu danh sách chat và trang Ứng dụng).
  Widget _threeFingerSwipe(Widget child) => ThreeFingerSwipe(
        onSwipe: () => showServerPicker(context).then((url) {
          if (url != null && mounted) _switchServer(url);
        }),
        child: child,
      );

  /// Gợi ý một lần (điện thoại): cách đổi / thêm máy chủ bằng 3 ngón.
  bool _swipeHintChecked = false;
  void _maybeSwipeHint(AppState app) {
    if (_swipeHintChecked || isDesktop || ServerList.items.isEmpty) return;
    _swipeHintChecked = true;
    app.uiPref<bool>('tip_three_finger').then((seen) {
      if (seen == true || !mounted) return;
      app.setUiPref('tip_three_finger', true);
      ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Mẹo: vuốt lên bằng 3 ngón để đổi hoặc thêm máy chủ'))));
    });
  }

  /// Nút ＋ (tạo tin nhắn / nhóm / …) nổi ngay trên thanh tab.
  Widget _newButton(NavigatorState? Function() nav) => Builder(
        builder: (b) => PlusFab(heroTag: 'new-chat', tooltip: tr('Tạo mới'), onPressed: () => _plusMenu(b, nav())),
      );

  /// Tiêu đề các tab không phải Chat: ảnh đại diện | tên tab.
  Widget _tabTitle(String title, NavigatorState? Function() nav) {
    final pal = Pal.of(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          const SizedBox(width: 40),
          Expanded(
            child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.text)),
          ),
          const SizedBox(width: 40),
        ]),
      ),
    );
  }

  /// Nội dung theo tab (dùng chung điện thoại và cột trái máy tính).
  Widget _tabBody(AppState app, double bottom, NavigatorState? Function() nav) => _sectionBody(_tab, app, bottom, nav);

  /// Nội dung một mục thanh tab: [open] = mở chat (mặc định ở ô đang chọn), [header] thay tiêu đề mục (ô đã có đầu ô).
  Widget _sectionBody(int tab, AppState app, double bottom, NavigatorState? Function() nav,
          {void Function(String id)? open, Widget? header}) =>
      switch (!app.hasUsableAgents && tab == 2 ? 0 : tab) {
        // Vị trí cũ của "Luồng" là app Quy trình; luồng tin nhắn nằm ở tab "Luồng riêng" trong Chat.
        1 => FlowsHome(app: app, embedded: true, bottomPadding: bottom),
        2 => AgentsView(
            onOpen: open ?? _open,
            selectedId: _wide && open == null ? _selected : null,
            bottomPadding: bottom,
            header: header ?? _tabTitle(tr('Các trợ lý'), nav)),
        3 => _apps(app, bottom, nav, open: open, onLaunch: isDesktop ? null : (id) => _mobileLaunch(id, app)),
        // Điện thoại: tab Bảng tin (Sếp 10/11) ngay sau Trợ lý.
                5 => BangTinTab(bottomPadding: bottom),
        // Module Việc đã bỏ (05/11): ô / cửa sổ cũ trỏ mục Việc hiện Chat.
        _ => Column(children: [
            _listHeader(),
            Expanded(
              child: PageView(
                controller: _filterPages,
                onPageChanged: (i) => _setFilter(_filters[i], fromPage: true),
                children: [
                  for (final f in _filters)
                    ChatList(
                      query: _query,
                      filter: f,
                      selectedId: _wide ? _selected : null,
                      onOpen: _open,
                      onSearchMessages: _searchMessages,
                      bottomPadding: bottom,
                    ),
                ],
              ),
            ),
          ]),
      };

  /// Mở một trang từ tab Apps (cột trái trên máy tính, trang mới trên điện thoại).
  void _push(NavigatorState? Function() nav, String title, Widget Function(BuildContext ctx) body) =>
      (nav() ?? Navigator.of(context)).push(AppPageRoute(
          builder: (ctx) => Scaffold(
                backgroundColor: Pal.of(ctx).bg,
                appBar: AppBar(title: Text(title)),
                body: body(ctx),
              )));

  /// Các ứng dụng của trang Bạn: id → (biểu tượng, màu, tên, số đếm, mở). Dùng cho trang Bạn và menu tab mới.
  Map<String, (IconData, Color, String, int, VoidCallback)> _appItems(AppState app, NavigatorState? Function() nav,
      {void Function(String id)? open}) {
    void openChat(BuildContext ctx, String id) {
      Navigator.of(ctx).pop();
      (open ?? _open)(id);
    }

    return {
      'contacts': (Icons.contacts_rounded, const Color(0xFF2F80ED), tr('Danh bạ'), 0,
          () => _push(nav, tr('Danh bạ'), (ctx) => PeopleView(header: const SizedBox.shrink(), onOpen: (id) => openChat(ctx, id)))),
      // Phòng ban (trưởng / phó / thành viên): ai cũng xem, quản trị sửa (lib/ui/flows/flows_org.dart).
      'org': (Icons.account_tree_rounded, const Color(0xFF0D9488), tr('Tổ chức'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => FlowsOrgPage(app: app, api: FlowsApi(app.token))))),
      // Ủy quyền (trước ở trang Quy trình): ủy quyền đang có, gửi đơn xin ủy quyền.
      'delegations': (Icons.assignment_ind_rounded, const Color(0xFFE08A1E), tr('Ủy quyền'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => FlowDelegationsPage(app: app)))),
      'calls': (Icons.call_rounded, const Color(0xFFE53935), tr('Lịch sử cuộc gọi'), app.missedCalls, () {
        app.markCallsSeen();
        _push(nav, tr('Lịch sử cuộc gọi'), (ctx) => CallHistoryView(header: const SizedBox.shrink(), onOpen: (id) => openChat(ctx, id)));
      }),
      // Máy tính đang đăng nhập bằng tài khoản này: bấm để điều khiển (lib/remote/rc_ui.dart).
      'computers': (Icons.computer_rounded, const Color(0xFF5B6CFF), tr('Máy tính'), 0,
          () => _push(nav, tr('Máy tính'), (ctx) => const RcDevicesPage())),
      'kyso': (Icons.draw_rounded, const Color(0xFF7B61FF), tr('Ký số'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => const KysoHomePage()))),
      for (final s in KysoApi.spaces)
        'kyso:${s.space.id}': (Icons.draw_rounded, KysoApi.colorOf(s), '${tr('Ký số')} ${KysoApi.shortName(s)}', 0,
            () => KysoApi.openSpace(context, s)),
      'settings': (Icons.settings_rounded, const Color(0xFF14A38B), tr('Cài đặt'), 0, () => _openProfile(nav())),
      'devices': (Icons.devices_rounded, const Color(0xFF2563EB), tr('Thiết bị'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => const DevicesPage()))),
      'wallpaper': (Icons.wallpaper_rounded, const Color(0xFF0EA5E9), tr('Hình nền'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => const WallpaperPage()))),
      // Zalo / WeChat (mục Chính của Trang chủ): đang phát triển, mở tab báo "Chức năng đang phát triển".
      'zalo': (Icons.chat_rounded, const Color(0xFF0068FF), 'Zalo', 0, () {}),
      'wechat': (Icons.forum_rounded, const Color(0xFF07C160), 'WeChat', 0, () {}),
      'qr': (Icons.qr_code_scanner_rounded, const Color(0xFF00A3A3), tr('Đăng nhập QR'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => const QrScanPage()))),
      'assistants': (Icons.auto_awesome_rounded, const Color(0xFFD97757), tr('Trợ lý'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => const AgentPage()))),
      'bots': (Icons.power_outlined, const Color(0xFF607D8B), tr('Bot'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => const BotsPage()))),
      'language': (Icons.translate_rounded, const Color(0xFF9B51E0), tr('Ngôn ngữ'), 0, () => _pickLanguage(context)),
      'password': (Icons.password_rounded, const Color(0xFFF2C94C), tr('Mật khẩu'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => const PasswordPage()))),
      'blocked': (Icons.block_rounded, const Color(0xFF8E8E93), tr('Chặn'), 0,
          () => (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => const BlockedUsersPage()))),
      'update': (Icons.system_update_rounded, const Color(0xFF27AE60), tr('Cập nhật'), 0, () => showUpdateDialog(context)),
      // App phục vụ theo từng tên miền: chính sách quyền riêng tư và điều khoản là của máy chủ đang dùng (link trong
      // cấu hình máy chủ). Yêu cầu xoá tài khoản (App Store bắt buộc) gửi cho quản trị viên của máy chủ đó.
      'privacy': (Icons.privacy_tip_outlined, const Color(0xFF5B6CFF), tr('Quyền riêng tư'), 0, () => openServerLegal(context)),
      'terms': (Icons.gavel_rounded, const Color(0xFF8D6E63), tr('Điều khoản'), 0, () => openServerLegal(context, terms: true)),
      // Đồng ý gửi dữ liệu cho AI: xem lại, rút lại.
      'ai': (Icons.auto_awesome_outlined, const Color(0xFFD97757), tr('AI'), 0, () => showAiConsentSettings(context)),
    };
  }

  /// Thẻ người dùng ([AppsUserCard]): điện thoại ở trên cùng, máy tính ở cột trái 1/3.
  Widget _userCard(AppState app, NavigatorState? Function() nav) => AppsUserCard(
        onProfile: () => showEditProfile(context),
        onSettings: () => _openProfile(nav()),
      );

  /// Tab Apps: lưới các ứng dụng theo nhóm [youAppGroups] (Danh bạ, Lịch sử cuộc gọi, Cài đặt, Trợ lý, Bot, Ngôn ngữ, Chặn…).
  Widget _apps(AppState app, double bottom, NavigatorState? Function() nav,
      {void Function(String id)? open, void Function(String id)? onLaunch}) {
    final pal = Pal.of(context);
    final me = app.me;
    final items = _appItems(app, nav, open: open);
    // Quyền Ký số vừa cấp hiện ngay khi mở trang chủ / trang Bạn (hỏi lại Flygo ID tối đa mỗi phút).
    unawaited(KysoApi.refresh(app.token, force: true));
    // Ô ứng dụng kiểu iOS: nền màu chuyển sắc (sáng → đậm), biểu tượng trắng, bóng mềm cùng màu.
    // [color] null = ô nền trắng có viền (mini app: biểu tượng riêng của app là ảnh / emoji).
    // Có hình nền (Trang chủ máy tính): chữ đặt trên nền mờ bo tròn để không chìm vào ảnh.
    final wall = onLaunch != null && Wallpaper.state.value.isSet;
    Widget onWall(Widget text) => !wall
        ? text
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: pal.surface.withValues(alpha: .82), borderRadius: BorderRadius.circular(8)),
            child: text,
          );

    Widget appTile(Widget icon, Color? color, String label, int badge, VoidCallback onTap) {
      if (_appQ.isNotEmpty && !_appFold(label).contains(_appFold(_appQ))) return const _HiddenTile();
      final box = color == null
          ? BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: pal.divider),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 10, offset: const Offset(0, 4))],
            )
          : BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(color, Colors.white, .28)!, color, Color.lerp(color, Colors.black, .12)!],
                stops: const [0, .55, 1],
              ),
              boxShadow: [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 12, offset: const Offset(0, 5))],
            );
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          // Lề ngang: tên dài xuống dòng không dính vào tên ô bên cạnh (Sếp, 2026-11-14).
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text(badge > 99 ? '99+' : '$badge'),
              backgroundColor: const Color(0xFFE53935),
              textColor: Colors.white,
              child: Container(width: 62, height: 62, decoration: box, child: Center(child: icon)),
            ),
            const SizedBox(height: 9),
            // Tên hiện đầy đủ, xuống dòng khi dài (vd tên công ty Ký số), không cắt bằng dấu "…".
            onWall(Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, color: pal.text))),
          ]),
        ),
      );
    }

    Widget tile((IconData, Color, String, int, VoidCallback) it) {
      final (icon, color, label, badge, onTap) = it;
      return appTile(Icon(icon, color: Colors.white, size: 30), color, label, badge, onTap);
    }

    // Mini app: biểu tượng của app (ảnh / emoji) trên ô trắng; mờ khi cần cập nhật Flygo.
    Widget miniTile(Widget icon, Color? color, String label, bool dim, VoidCallback onTap) {
      final t = appTile(icon, color, label, 0, onTap);
      return t is _HiddenTile ? t : Opacity(opacity: dim ? .45 : 1, child: t);
    }

    Widget grid(String title, List<Widget> all) {
      final tiles = [for (final t in all) if (t is! _HiddenTile) t];
      // Mục không có ô nào (vd Quản trị của người thường, hoặc đang tìm) thì ẩn luôn tiêu đề.
      if (tiles.isEmpty) return const SizedBox.shrink();
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: onWall(Text(title.toUpperCase(),
                    style: TextStyle(fontSize: 12.5, letterSpacing: .5, fontWeight: FontWeight.w700, color: wall ? pal.text : pal.sub))),
              ),
            ),
            LayoutBuilder(builder: (ctx, c) {
              // Điện thoại: 4 cột; màn rộng hơn thì thêm cột (tối đa 6).
              // Điện thoại: 4 cột; màn rộng (Trang chủ máy tính) thêm cột tới 12 để ít phải cuộn.
              final cols = (c.maxWidth / 108).floor().clamp(4, 12);
              final w = (c.maxWidth - 24) / cols;
              // Ô ứng dụng căn trái (Sếp, 2026-11-13).
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(children: [for (final t in tiles) SizedBox(width: w, child: t)]),
              );
            }),
          ],
        );
    }

    Widget section(String title, List<(IconData, Color, String, int, VoidCallback)> items) => grid(title, [for (final it in items) tile(it)]);

    // Menu tab mới (máy tính): chọn ứng dụng thì tab này thành ứng dụng đó; mục chỉ là hộp thoại thì mở như cũ.
    if (onLaunch != null) {
      _askFlowsAdmin();
      _askAdmin();
      (IconData, Color, String, int, VoidCallback) asTab(String id, (IconData, Color, String, int, VoidCallback) it) =>
          isDesktop && kDeskTabApps.contains(id) ? (it.$1, it.$2, it.$3, it.$4, () => onLaunch(id)) : it;
      loadCurrentBuild();
      final card = _userCard(app, nav);
      Widget appsList({required bool phone}) => ListView(padding: EdgeInsets.only(bottom: bottom + 16), children: [
        Padding(
          // Điện thoại: chừa vùng tai thỏ / thanh trạng thái (tab Apps không có thanh trên).
          // Điện thoại có tên công ty ở đầu: chỉ chừa vùng thanh trạng thái + 8 (không cộng thêm 24).
          padding: EdgeInsets.fromLTRB(20, (phone && ServerList.items.isNotEmpty ? 8 : 24) + (isDesktop ? 0 : MediaQuery.paddingOf(context).top), 20, 0),
          // Điện thoại: tên công ty một dòng, ô tìm ở dòng dưới (rộng hết trang) để tên không bị cắt.
          child: Flex(direction: phone ? Axis.vertical : Axis.horizontal, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Điện thoại: tên công ty (máy chủ) ở đầu trang, bấm để đổi / thêm máy chủ (Sếp, 2026-11-13).
            // Căn giữa, lề trên / dưới rộng (Sếp, 2026-11-13).
            if (phone && ServerList.items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Center(child: onWall(const AppsServerTitle())),
              )
            else
              Expanded(
                flex: phone ? 0 : 1,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: onWall(Text(tr('Mở ứng dụng'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text))),
                ),
              ),
            // Tìm ứng dụng theo tên (Sếp, 2026-11-10).
            SizedBox(
              width: phone ? double.infinity : (isDesktop ? 260 : 170),
              height: 38,
              // Esc: xoá ô tìm và thoát tìm kiếm (Sếp, 2026-11-10).
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    _appQCtl.clear();
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => _appQ = '');
                  },
                },
                child: TextField(
                key: const ValueKey('apps-search'),
                controller: _appQCtl,
                onChanged: (v) => setState(() => _appQ = v.trim()),
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 14, color: pal.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr('Tìm ứng dụng'),
                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: pal.sub),
                  filled: true,
                  fillColor: pal.surface.withValues(alpha: wall ? .9 : 1),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(19), borderSide: BorderSide(color: pal.divider)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(19), borderSide: BorderSide(color: pal.divider)),
                ),
              ),
              ),
            ),
          ]),
        ),
        // Mục Chính: Chat, Trợ lý, Quy trình và Trình chiếu (mini app của máy chủ, tải về sau).
        MiniAppsSection(
          key: ValueKey('main-$kServerUrl'),
          only: kMainMiniApps,
          showEmpty: true,
          tile: miniTile,
          lead: kLeadMiniApps,
          section: (_, shows) => const SizedBox.shrink(),
          split: (_, leads, shows) => grid(tr('Chính'), [
                        // Thứ tự (Sếp 10/11, đổi lại): Chat, Dự án AI, Bảng tin, rồi Tổ chức, Danh bạ, Ủy quyền, Lịch sử cuộc gọi, Máy tính.
            tile((Icons.chat_bubble_rounded, const Color(0xFF25A244), tr('Chat'), app.chats.where((c) => c.unread > 0).length, () => onLaunch('chat'))),
            if (app.hasUsableAgents) tile((Icons.auto_awesome_rounded, const Color(0xFFD97757), tr('Dự án AI'), app.agentUnread, () => onLaunch('agents'))),
            ...leads,
            // Tổ chức và Quy trình nằm ở mục Quản trị (Sếp, 2026-11-10).
            for (final id in _workAppOrder(youAppGroups(desktop: isDesktop).where((g) => g.$1 == tr('Công việc')).expand((g) => g.$2)).where((id) => id != 'org'))
              if (items[id] != null) tile(asTab(id, items[id]!)),
            appTile(brandIcon('zalo', 34, Colors.white), const Color(0xFF0068FF), 'Zalo', 0, () => onLaunch('zalo')),
            appTile(brandIcon('wechat', 34, Colors.white), const Color(0xFF07C160), 'WeChat', 0, () => onLaunch('wechat')),
            ...shows,
          ]),
        ),
        // Ứng dụng (mini app của máy chủ, trừ các ô đã ở mục Chính) ngay sau Chính (Sếp, 2026-11-10).
        MiniAppsSection(key: ValueKey('tab-$kServerUrl'), section: grid, tile: miniTile, except: kMainMiniApps),
        // Ký số sau Ứng dụng (mỗi công ty một ô).
        for (final (title, ids) in youAppGroups(desktop: isDesktop).where((g) => g.$1 == tr('Ký số')))
          section(title, [for (final id in ids) if (items[id] != null) asTab(id, items[id]!)]),
        // Chưa có ô Ký số vì hỏi Flygo ID lỗi: hiện lý do và nút thử lại (không im lặng như trước).
        ValueListenableBuilder<String?>(
          valueListenable: KysoApi.lastError,
          builder: (ctx, err, _) => err == null || KysoApi.spaces.isNotEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: pal.sub),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tr('Ký số: chưa tải được danh sách công ty ({0})', [err]), style: TextStyle(fontSize: 12.5, color: pal.sub))),
                    TextButton(onPressed: () => KysoApi.refresh(app.token, force: true), child: Text(tr('Thử lại'))),
                  ]),
                ),
        ),
        // Mỗi quy trình cũng là một ứng dụng.
        // Mọi người thấy các quy trình mình được thấy (máy chủ lọc theo visible_to), kể cả quy trình Thử nghiệm (mờ).
        FutureBuilder<List<FlowDefInfo>>(
          future: _homeFlowDefs(app),
          builder: (ctx, snap) {
            // Quy trình "Thử nghiệm": ô mờ có nhãn, bấm chỉ báo chưa chạy được.
            final defs = [for (final d in snap.data ?? const <FlowDefInfo>[]) if ((d.canStart || d.experimental) && !d.hidden) d];
            if (defs.isEmpty) return const SizedBox.shrink();
            return grid(tr('Quy trình'), [
              for (final d in defs)
                if (d.experimental)
                  Tooltip(
                    key: ValueKey('home-flow-experimental-${d.id}'),
                    message: flowExperimentalMsg(),
                    child: Stack(alignment: Alignment.topCenter, children: [
                      appTile(Text(d.icon.isEmpty ? '📋' : d.icon, style: const TextStyle(fontSize: 28)), null, d.name, 0, () => showFlowExperimental(ctx)),
                      const Positioned(top: 0, child: IgnorePointer(child: FlowExperimentalBadge(small: true))),
                    ]),
                  )
                else
                  appTile(Text(d.icon.isEmpty ? '📋' : d.icon, style: const TextStyle(fontSize: 28)), null, d.name, 0,
                      () => onLaunch('flow:${d.id}\t${d.name}\t${d.icon}')),
            ]);
          },
        ),
        // Quản trị ở cuối, ngay trước Cá nhân (Sếp, 2026-11-10).
        for (final (title, ids) in youAppGroups(desktop: isDesktop).where((g) => g.$1 != tr('Ký số') && g.$1 != tr('Công việc'))) ...[
          if (title == tr('Cá nhân')) ...[
          grid(tr('Quản trị'), [
              if (items['org'] != null) tile(asTab('org', items['org']!)),
              if (_flowsAdmin) tile((Icons.account_tree_rounded, const Color(0xFF5B6CFF), tr('Quy trình'), 0, () => onLaunch('flows'))),
              if (_usersAdmin && KysoApi.flygoId != null)
                appTile(const Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 32), const Color(0xFF0F766E), tr('Người dùng'), 0,
                    // Máy tính: mở thành tab mới (danh sách + chi tiết hai cột); điện thoại: mở trang.
                    () => isDesktop ? onLaunch('users') : (nav() ?? Navigator.of(context)).push(AppPageRoute(builder: (_) => UsersAdminPage(id: KysoApi.flygoId!)))),
              for (final a in _adminApps)
                appTile(const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 32),
                    a['app'] == kKysoExtensionId ? const Color(0xFF7C3AED) : const Color(0xFF475569), _adminLabel(a), 0, () => _openAdmin(a)),
            ]),
          ],
          // "Cập nhật" đã có trong thẻ người dùng (Kiểm tra cập nhật). Điện thoại: ô "Hồ sơ" (ảnh của mình) mở trang hồ sơ
          // (thẻ người dùng), vì trang Ứng dụng trên điện thoại không còn thẻ (Sếp, 2026-11-13).
          grid(title, [
            if (phone && title == tr('Cá nhân') && me != null)
              appTile(
                  ClipOval(child: Avatar(userId: me.id, name: me.displayName, size: 62, status: false)), null, tr('Hồ sơ'), 0,
                  () => (nav() ?? Navigator.of(context)).push(AppPageRoute(
                      builder: (_) => AppsProfilePage(onProfile: () => showEditProfile(context), onSettings: () => _openProfile(nav()))))),
            for (final id in ids)
              if (id != 'update' && items[id] != null) tile(asTab(id, items[id]!)),
          ]),
        ],
        // Điện thoại: Đăng xuất một dòng riêng, căn giữa, cuối trang (Sếp, 2026-11-13).
        if (phone && !isChildWindow)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(child: AppsLogoutButton(onLogout: _confirmLogout)),
          ),
      ]);
      // Máy tính / màn rộng: thẻ người dùng ở cột trái 1/3, ứng dụng bên phải 2/3.
      return LayoutBuilder(builder: (_, c) {
        if (c.maxWidth < 900) return appsList(phone: true);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cột trái: thẻ người dùng, máy chủ ghim ở dưới cùng.
          SizedBox(
            width: c.maxWidth / 3,
            child: Column(children: [
              Expanded(
                child: ListView(padding: EdgeInsets.only(top: 24 + (isDesktop ? 0 : MediaQuery.paddingOf(context).top), bottom: 16), children: [card]),
              ),
              // Dưới cùng cột trái: tên công ty bên trái, Đăng xuất bên phải (đối diện nhau).
              Padding(
                padding: EdgeInsets.fromLTRB(0, 0, 8, bottom + 8),
                child: Row(children: [
                  const Expanded(child: AppsServerRow(align: TextAlign.left)),
                  if (!isChildWindow) AppsLogoutButton(onLogout: _confirmLogout),
                ]),
              ),
            ]),
          ),
          Expanded(child: appsList(phone: false)),
        ]);
      });
    }

    return ListView(padding: EdgeInsets.only(bottom: bottom + 16), children: [
      const SafeArea(bottom: false, child: SizedBox(height: 8)),
      // Chọn / chuyển máy chủ.
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ServerSelectButton(onSelected: _switchServer)),
      const SizedBox(height: 16),
      // Ảnh đại diện + tên (như trang Bạn); bấm để mở cài đặt.
      if (me != null)
        Center(
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _openProfile(nav()),
            child: Avatar(userId: me.id, name: me.displayName, size: 96, status: false),
          ),
        ),
      const SizedBox(height: 12),
      if (me != null)
        Text(me.displayName, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: pal.text)),
      if (me != null)
        Text('@${me.username}', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: pal.sub)),
      const SizedBox(height: 16),
      // Hoạt động và trạng thái.
      const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: StatusSection(plain: true)),
      for (final (title, ids) in youAppGroups(desktop: isDesktop)) ...[
        section(title, [for (final id in ids) ?items[id]]),
        // Mini app của máy chủ (registry) ngay sau nhóm Công việc, ẩn khi không có.
        if (title == tr('Công việc')) MiniAppsSection(key: ValueKey(kServerUrl), section: grid, tile: miniTile, except: {...kLeadMiniApps}),
      ],
      // Xoá tài khoản / Đăng xuất: nút nhỏ căn giữa ở cuối trang, phải BẤM GIỮ để tránh bấm nhầm.
      // Cửa sổ riêng không đăng xuất (phiên dùng chung với cửa sổ chính).
      if (!isChildWindow) ...[
      const SizedBox(height: 20),
      Center(
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
          _holdButton(pal, Icons.person_remove_rounded, tr('Xoá tài khoản'), pal.sub,
              () => requestAccountDeletion(context, context.read<AppState>())),
          _holdButton(pal, Icons.logout_rounded, tr('Đăng xuất'), const Color(0xFFE53935), _confirmLogout),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(tr('Bấm giữ để thực hiện'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: pal.sub)),
      ),
      ],
    ]);
  }

  /// Nút nhỏ chỉ chạy khi bấm giữ; bấm thường thì nhắc "Bấm giữ để …".
  Widget _holdButton(Pal pal, IconData icon, String label, Color color, VoidCallback onHold) => Tooltip(
        message: tr('Bấm giữ để {0}', [label.toLowerCase()]),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Bấm giữ để {0}', [label.toLowerCase()])))),
          onLongPress: () {
            HapticFeedback.mediumImpact();
            onHold();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: .4)), borderRadius: BorderRadius.circular(18)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );

  Widget _tabBar(AppState app) => ValueListenableBuilder<int>(
      valueListenable: tasksOverdue,
      builder: (_, overdue, _) => _TabBar(
        index: _tab,
        unread: app.chats.where((c) => c.unread > 0).length,
        // Nút Quy trình: chưa có số đếm (tính năng đang phát triển). Số luồng mở hiện ở tab "Luồng riêng".
        threads: 0,
        missed: app.missedCalls,
        agents: app.agentUnread,
        // Chưa có trợ lý AI nào: ẩn tab Agents.
        hasAgents: app.hasUsableAgents,
        hasBangTin: !isDesktop && (BangTinService.instance.hasApp || bangTinApp() != null),
        bangTin: BangTinService.instance.badge,
        me: app.me,
        tasks: app.todos['in']?.length ?? 0,
        work: overdue,
        onTap: _selectTab,
      ));

  @override
  void dispose() {
    KysoApi.available.removeListener(_kysoChanged);
    KysoApi.spacesChanged.removeListener(_kysoChanged);
    BangTinService.instance.removeListener(_kysoChanged);
    flowsChanged.removeListener(_kysoChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    // Bố cục chưa kịp lưu (vừa đổi xong thì đóng cửa sổ / đổi ngôn ngữ): lưu ngay.
    if (_paneSave?.isActive == true) _app.savePanes(_panes.toJson()).catchError((_) {});
    _paneSave?.cancel();
    if (_tabSave?.isActive == true) _app.saveDeskTabs(_tabsJson()).catchError((_) {});
    _tabSave?.cancel();
    if (openTabHook == _openTab) openTabHook = null;
    for (final s in _paneScopes.values) {
      s.dispose();
    }
    if (internalLinkHook == _openInternalLink) internalLinkHook = null;
    if (PushService.openChatHook == _open) {
      PushService.openChatHook = null;
      PushService.openThreadHook = null;
    }
    if (widget.solo == null) AppBadge.detach(_app);
    _leftTick.dispose();
    _filterPages.dispose();
    super.dispose();
  }

  /// Chọn máy chủ khác: máy tính mở cửa sổ riêng, điện thoại chuyển ngay trong app.
  void _switchServer(String url) {
    if (url == ServerList.current) return;
    if (isDesktop) {
      // Thêm máy chủ mới: cửa sổ riêng mở thẳng màn đăng nhập.
      url == kAddServer ? AppState.openAddServerWindow() : AppState.openServerWindow(url);
    } else {
      widget.onSwitchServer(url);
    }
  }

  /// Mở luồng bí mật ở cột phải. Luồng nhiều tầng / mở từ nơi khác (tab Luồng, nhóm khác đang chọn):
  /// chọn nhóm gốc ngoài cùng ở cột giữa rồi mở luồng ở cột phải, để luôn hiện trang mới.
  void _openSide(String id) {
    final app = context.read<AppState>();
    // Nhiều ô: mở chồng trong ô đang chọn (nút quay lại trở về chat cha).
    if (_multi) {
      _pushInPane(_panes.focusedId, (_) => ChatPage(channelId: id));
      return;
    }
    // Luồng bí mật sâu hơn mở từ luồng bí mật đang ở cột phải: đẩy chồng lên trong cột (nút quay lại
    // trở về luồng bí mật cha), không thay luồng đang mở.
    final cur = _side?.$2;
    if (cur != null && cur != id && _sideNav.currentState != null) {
      var p = app.channels[id]?.subParent;
      for (var i = 0; i < 10 && p != null; i++) {
        if (p == cur) {
          _sideNav.currentState!.push(AppPageRoute(builder: (_) => ChatPage(channelId: id)));
          return;
        }
        p = app.channels[p]?.subParent;
      }
    }
    final top = app.topParentOf(id);
    setState(() {
      if (top != null && (_selected == null || (_selected != top && _selected != app.channels[id]?.subParent))) {
        _panes.open(PaneContent.chat(top));
      }
      if (_side?.$2 != id) _sideNav = GlobalKey<NavigatorState>();
      _side = _selected == null ? null : (_selected!, id);
      _thread = null;
      _infoFor = null;
    });
    _panesChanged();
    if (_selected == null) openChannelAnywhereFallback(id);
  }

  void openChannelAnywhereFallback(String id) =>
      Navigator.of(context).push(AppPageRoute(builder: (_) => ChatPage(channelId: id)));

  void _hostOpenPage(String key, WidgetBuilder builder) => setState(() {
        _page = (key, builder);
        _pageSide = null;
      });

  void _hostOpenSidePage(String key, WidgetBuilder? builder) => setState(() => _pageSide = builder == null ? null : (key, builder));

  void _open(String channelId) {
    // Thảo luận của tiến trình (kênh ẩn): mở trang tiến trình ở phần thảo luận, không mở như chat.
    final pid = context.read<AppState>().channels[channelId]?.processId;
    if (pid != null) {
      openProcess(context, context.read<AppState>(), pid, initialTab: 1);
      return;
    }
    if (_page != null) setState(() => _page = _pageSide = null);
    if (widget.solo != null) {
      _soloNav.currentState?.push(AppPageRoute(builder: (_) => ChatPage(channelId: channelId)));
    } else if (_wide) {
      _showMainChatTab();
      setState(() {
        if (_infoFor != null && _infoFor != channelId) _infoFor = channelId;
        final c = PaneContent.chat(channelId);
        // Ô đang chọn là một danh sách (vd. "Các trợ lý"): mở ở ô chat khác, giữ danh sách.
        _panes.isMulti && _panes.focused.content?.isSection == true ? _panes.openFrom(_panes.focusedId, c) : _panes.open(c);
      });
      _panesChanged();
    } else {
      Navigator.of(context).push(AppPageRoute(builder: (_) => ChatPage(channelId: channelId)));
    }
  }

  /// Nút "+": bảng dưới (bottom sheet) — tạo nhóm, kênh, cuộc họp, trợ lý AI, bot cá nhân.
  Future<void> _plusMenu(BuildContext btn, NavigatorState? nav) async {
    if (nav == null) return;
    final pal = Pal.of(context);
    Widget item(BuildContext ctx, String v, IconData icon, Color color, String title, String sub) => InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.pop(ctx, v),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.text)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 13, color: pal.sub)),
                ]),
              ),
              Icon(Icons.chevron_right, color: pal.sub),
            ]),
          ),
        );
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: pal.surface,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(tr('Tạo mới'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.text)),
            ),
            item(ctx, 'direct', Icons.person_add_alt_1_rounded, const Color(0xFF27AE60), tr('Nhắn tin riêng'),
                tr('Chọn người trong danh bạ để nhắn tin 1-1')),
            item(ctx, 'private', Icons.group_add_rounded, const Color(0xFF2F80ED), tr('Tạo nhóm'),
                tr('Nhóm riêng tư, chỉ người được mời mới vào được')),
            item(ctx, 'public', Icons.tag_rounded, const Color(0xFF14A38B), tr('Tạo kênh'),
                tr('Kênh công khai, ai trong công ty cũng tham gia được')),
            item(ctx, 'meeting', Icons.videocam_rounded, const Color(0xFFF2994A), tr('Tạo cuộc họp'),
                tr('Họp video ngay với nhiều người')),
            item(ctx, 'agent', Icons.auto_awesome_rounded, const Color(0xFF9B51E0), tr('Tạo trợ lý AI'),
                tr('Trợ lý Claude / Codex chạy trên máy của bạn')),
            item(ctx, 'bot', Icons.power_outlined, pal.sub, tr('Tạo bot tích hợp'),
                tr('Cho phần mềm khác gửi tin vào, không có AI')),
          ]),
        ),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'direct') {
      nav.push(AppPageRoute(
          builder: (ctx) => Scaffold(
                appBar: AppBar(title: Text(tr('Danh bạ'))),
                body: PeopleView(header: const SizedBox.shrink(), onOpen: (id) {
                  Navigator.of(ctx).pop();
                  _open(id);
                }),
              )));
      return;
    }
    if (v == 'agent') {
      nav.push(AppPageRoute(builder: (_) => const AgentPage()));
      return;
    }
    if (v == 'bot') {
      nav.push(AppPageRoute(builder: (_) => const BotEditPage()));
      return;
    }
    final kind = {'public': NewChatKind.publicGroup, 'private': NewChatKind.privateGroup, 'meeting': NewChatKind.meeting}[v]!;
    final id = await nav.push<String>(AppPageRoute(builder: (_) => NewChatPage(kind: kind)));
    if (id == null || !mounted) return;
    _open(id);
    if (kind == NewChatKind.meeting) context.read<AppState>().calls.startCall(id, meeting: true);
  }

  void _searchMessages() {
    Navigator.of(context).push(AppPageRoute(builder: (_) => SearchPage(terms: _query, onOpen: _open)));
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Đăng xuất?')),
        content: Text(tr('Tin nhắn lưu trên máy này sẽ bị xóa. Bạn có thể đăng nhập lại bằng Google bất cứ lúc nào.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(tr('Đăng xuất'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Đóng các trang đang mở chồng (trang cá nhân...) trước khi đăng xuất, tránh màn hình trắng.
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    _leftNav.currentState?.popUntil((r) => r.isFirst);
    await widget.onLogout();
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Expanded(
          // Điện thoại: chỉ hiện tên công ty; đổi / thêm máy chủ bằng vuốt 3 ngón lên (hoặc Cài đặt → Máy chủ).
          child: ServerTitle(onSelected: _switchServer, interactive: isDesktop),
        ),
      ]),
    );
  }

  /// Thanh trên của cột danh sách (máy tính): tên máy chủ (nút ＋ và ảnh đại diện ở dưới).
  Widget _topBarWide() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        Expanded(
          child: ServerTitle(onSelected: _switchServer),
        ),
      ]),
    );
  }

  Widget _listHeader() {
    final pal = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const UpdateBanner(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: TextField(
          controller: _searchCtl,
          onChanged: (v) => setState(() => _query = v),
          style: TextStyle(color: pal.text, fontSize: 16),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: pal.surface,
            hintText: tr('Tìm kiếm'),
            hintStyle: TextStyle(color: pal.sub),
            prefixIcon: Icon(Icons.search, color: pal.sub, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.cancel, size: 18, color: pal.sub),
                    onPressed: () => setState(() {
                          _query = '';
                          _searchCtl.clear();
                        })),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
      // Bộ lọc dạng tab (gạch chân), cuộn ngang khi chật.
      SizedBox(
        height: 42,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider, width: .6))),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final f in _filters)
                InkWell(
                  key: _filterKeys[f],
                  onTap: () => _setFilter(f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: _filter == f ? pal.accent : Colors.transparent, width: 2.5)),
                    ),
                    child: chatFilterTabLabel(context, f, _filter == f, 15),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 6),
    ]);
  }

  void _saveLayout() => context.read<AppState>().saveLayout({
        'left': _leftW,
        'info': _infoW,
        'right': ?_rightW,
      });

  /// Cột phải (một ô): thông tin của chat đang mở.
  void _hostOpenInfo(String id) {
    if (_multi) return _pushInPane(_panes.focusedId, (_) => ChatInfoPage(channelId: id));
    setState(() {
      _infoFor = _infoFor == id ? null : id;
      _thread = null;
      _side = null;
    });
  }

  /// Mở luồng (chủ đề) của chat: một ô thì ở cột phải, nhiều ô thì chồng trong ô của chat đó.
  void _hostOpenThread(String cid, String root) {
    _showMainChatTab();
    if (_multi) {
      final target = _panes.find(PaneContent.chat(cid))?.id ?? _openFromPane(_panes.focusedId, cid);
      _focusPane(target);
      _pushInPane(target, (_) => ThreadPage(channelId: cid, rootId: root));
      return;
    }
    setState(() {
      _thread = (cid, root);
      _infoFor = null;
      _side = null;
    });
  }

  /// Mở trợ lý AI của nhóm [g]: một ô thì ở cột AI bên phải, nhiều ô thì chồng trong ô của nhóm đó.
  void _hostOpenAi(String g, {String? thread}) {
    if (_multi) {
      final target = _panes.find(PaneContent.chat(g))?.id ?? _openFromPane(_panes.focusedId, g);
      _focusPane(target);
      _pushInPane(target, (ctx) => AiPanel(groupId: g, thread: thread, onClose: () => Navigator.of(ctx).maybePop()));
      return;
    }
    setState(() {
      _panes.open(PaneContent.chat(g));
      _aiThread = thread == null ? null : (g, thread);
      _aiHidden = null;
      _thread = null;
      _side = null;
      _infoFor = null;
    });
    _panesChanged();
  }

  /// Cửa sổ riêng của một mục thanh tab: mục đó chiếm cả cửa sổ, chat mở chồng lên (như điện thoại).
  Widget _soloBody(AppState app) {
    final pal = Pal.of(context);
    final section = widget.solo!;
    return AboveNavSnackBars(
      navTop: 24,
      child: Scaffold(
        backgroundColor: pal.bg,
        body: SafeArea(
          child: _ColumnNavigator(
            navKey: _soloNav,
            root: ListenableBuilder(
              listenable: _leftTick,
              builder: (context, _) {
                final app = context.watch<AppState>();
                return Scaffold(
                  backgroundColor: pal.bg,
                  body: Column(children: [
                    const OfflineBanner(),
                    Expanded(
                      child: section == PaneSections.chats
                          ? _PaneChatList(
                              onOpen: _open,
                              onSearchMessages: (q) => _soloNav.currentState
                                  ?.push(AppPageRoute(builder: (_) => SearchPage(terms: q, onOpen: _open))))
                          : _sectionBody(_tab, app, 16, () => _soloNav.currentState),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tab (máy tính): hiển thị
  /// Khung tab: thanh tab trên cùng, dưới là nội dung các tab (giữ trạng thái khi chuyển tab).
  Widget _deskShell(AppState app, Widget mainLayout) {
    final pal = Pal.of(context);
    // Chờ đọc xong các tab đã lưu (hoặc không có) rồi mới thêm tab Trợ lý, để không bị bản đã lưu ghi đè.
    if (_tabsRestored) _ensureAgentsTab(app);
    if (openTabHook != _openTab) openTabHook = _openTab;
    final main = _mainChatTab;
    return Material(
      color: pal.bg,
      child: SafeArea(
        child: Column(children: [
          DeskTabBar(
            tabs: _deskTabs,
            current: _deskCur,
            label: (t) => _deskLabel(t, app),
            onSelect: _selectDeskTab,
            onClose: _closeDeskTab,
            onMove: _moveDeskTab,
            onNew: () => _openTab(DeskTab('launcher')),
            onTogglePin: _togglePinTab,
            onCloseOthers: _closeOtherTabs,
            trailing: ServerChip(onSelected: _switchServer),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: IndexedStack(
                index: _deskCur,
                children: [
                  for (final t in _deskTabs)
                    KeyedSubtree(
                      key: ValueKey('tab-${t.id}'),
                      child: t == main ? KeyedSubtree(key: _mainLayoutKey, child: mainLayout) : _deskTabBody(t, app),
                    ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  DeskTabLabel _deskLabel(DeskTab t, AppState app) {
    final pal = Pal.of(context);
    Icon icon(IconData i, [Color? c]) => Icon(i, size: 17, color: c ?? pal.accentText);
    switch (t.kind) {
      case 'chat':
        // Tiêu đề tab là tên cuộc trò chuyện đang mở (tab Chat chính: chat ở ô đang chọn).
        final open = t == _mainChatTab ? _selected : _tabChat[t.id];
        final ch = open == null ? null : app.channels[open];
        return DeskTabLabel(icon(Icons.chat_bubble_rounded, const Color(0xFF25A244)), ch == null ? tr('Chat') : app.channelTitle(ch),
            badge: app.chats.where((c) => c.unread > 0).length);
      case 'agents':
        return DeskTabLabel(icon(Icons.auto_awesome_rounded, const Color(0xFFD97757)), tr('Dự án AI'), badge: app.agentUnread);
      case 'flows':
        // Đang xem một quy trình (trang Quy trình gọi DeskTabScope.onTitle): tên quy trình làm tiêu đề.
        return DeskTabLabel(icon(Icons.account_tree_rounded, const Color(0xFF5B6CFF)), _tabTitles[t.id] ?? tr('Quy trình'));
      case 'conv' || 'thread':
        final id = t.kind == 'thread' ? (t.arg ?? '').split('/').first : t.arg ?? '';
        final ch = app.channels[id];
        if (ch == null) return DeskTabLabel(icon(Icons.chat_bubble_outline, pal.sub), tr('Cuộc trò chuyện'));
        final title = app.channelTitle(ch);
        final other = ch.isDirect && app.me != null ? ch.otherUserId(app.me!.id) : null;
        return DeskTabLabel(
          t.kind == 'thread'
              ? icon(Icons.forum_outlined)
              : Avatar(userId: other, name: title, size: 20, status: false, icon: other == null ? chatIcon(ch) : null, channel: ch),
          t.kind == 'thread' ? tr('Luồng · {0}', [title]) : title,
          badge: t.kind == 'conv' ? app.unreadOf(id) : 0,
        );
      case 'flow':
        final parts = (t.arg ?? '').split('\t');
        final emoji = parts.length > 2 ? parts[2] : '';
        return DeskTabLabel(Text(emoji.isEmpty ? '📋' : emoji, style: const TextStyle(fontSize: 14)), parts.length > 1 ? parts[1] : tr('Quy trình'));
            case 'app' when t.arg == kBangTinTab:
        return DeskTabLabel(icon(Icons.newspaper_rounded, const Color(0xFFE8833A)), tr('Bảng tin'), badge: BangTinService.instance.badge);
      case 'app' when t.arg == 'zalo' || t.arg == 'wechat':
        return DeskTabLabel(brandIcon(t.arg!, 16, t.arg == 'zalo' ? const Color(0xFF0068FF) : const Color(0xFF07C160)), t.arg == 'zalo' ? 'Zalo' : 'WeChat');
      case 'app':
        final it = _appItems(app, () => null)[t.arg];
        if (it != null) return DeskTabLabel(icon(it.$1, it.$2), it.$3, badge: it.$4);
    }
    return DeskTabLabel(icon(Icons.home_rounded, pal.sub), _tabTitles[t.id] ?? tr('Trang chủ'));
  }

  /// Nội dung một tab (trừ tab Chat chính).
  Widget _deskTabBody(DeskTab t, AppState app) {
    void onChat(String? id) {
      if (_tabChat[t.id] != id && mounted) setState(() => _tabChat[t.id] = id);
    }
    final Widget body = switch (t.kind) {
      'chat' => _SplitTab(onChat: onChat, leftWidth: 360, left: (ctx, open, sel) => _LiteChatList(onOpen: open, selectedId: sel)),
      'agents' => _SplitTab(
          onChat: onChat,
          leftWidth: 380,
          left: (ctx, open, sel) => AgentsView(onOpen: open, selectedId: sel, bottomPadding: 16, header: const SizedBox(height: 8))),
      'flows' => _SplitTab(
          onChat: onChat,
          onPageClosed: () => setState(() => _tabTitles.remove(t.id)),
          fullLeftWhenIdle: true,
          leftWidth: 460, left: (ctx, open, sel) => FlowsHome(app: app, embedded: true, bottomPadding: 16)),
      // Chat / phiên trợ lý mở ở tab mới: kèm danh sách bên trái (chat hoặc trợ lý), không chỉ một cuộc trò chuyện.
      'conv' => (app.channels[t.arg]?.isAi ?? false) || (app.channels[t.arg]?.isAgentProject ?? false)
          ? _SplitTab(
              onChat: onChat,
              initialChat: t.arg,
              leftWidth: 380,
              left: (ctx, open, sel) => AgentsView(onOpen: open, selectedId: sel, bottomPadding: 16, header: const SizedBox(height: 8)))
          : _SplitTab(
              onChat: onChat,
              initialChat: t.arg,
              leftWidth: 360,
              left: (ctx, open, sel) => _LiteChatList(onOpen: open, selectedId: sel)),
      'thread' => _SplitTab(onChat: onChat, initialThread: t.arg),
      'app' => _ColumnNavigator(navKey: _tabNav(t), root: _appPage(t.arg ?? '', app)),
      'flow' => _ColumnNavigator(
          navKey: _tabNav(t),
          root: Builder(builder: (_) {
            final parts = (t.arg ?? '').split('\t');
            return WorkflowPage(app: app, flowId: parts.first, name: parts.length > 1 ? parts[1] : '', icon: parts.length > 2 ? parts[2] : '');
          }),
        ),
      _ => _ColumnNavigator(
          navKey: _tabNav(t),
          observers: [_TabRootObserver(() => setState(() => _tabTitles.remove(t.id)))],
          root: Scaffold(
            backgroundColor: Pal.of(context).bg,
            // Trang chủ có hình nền (cài ở ứng dụng Hình nền, lưu trên máy này).
            body: WallpaperBackground(child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: ValueListenableBuilder<WallpaperState>(
                  valueListenable: Wallpaper.state,
                  builder: (context, _, _) => _apps(app, 16, () => _tabNav(t).currentState, onLaunch: (id) => _launchInTab(t, id)),
                ),
              ),
            )),
          ),
        ),
    };
    return DeskTabScope(
      onTitle: (title) => setState(() => title == null ? _tabTitles.remove(t.id) : _tabTitles[t.id] = title),
      onLaunch: (id) => _launchInTab(t, id),
      child: body,
    );
  }

  /// Trang gốc của một ứng dụng trang Bạn mở thành tab. Mở chat từ đây thì về tab Chat chính.
  Widget _appPage(String id, AppState app) {
    final pal = Pal.of(context);
    final page = _appPageBody(id, app);
    // Ứng dụng mở thành tab: nội dung rộng tối đa 920px ở giữa (Tổ chức hai cột và Hình nền toàn màn hình thì để rộng).
        if (id == 'org' || id == 'wallpaper' || id == 'users' || id == kBangTinTab) return page;
    return ColoredBox(
      color: pal.bg,
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: page)),
    );
  }

  Widget _appPageBody(String id, AppState app) {
    final pal = Pal.of(context);
    Widget titled(String title, Widget body) =>
        Scaffold(backgroundColor: pal.bg, appBar: AppBar(title: Text(title), automaticallyImplyLeading: false), body: body);
    return switch (id) {
            kBangTinTab => const BangTinTab(),
      'contacts' => titled(tr('Danh bạ'), PeopleView(header: const SizedBox.shrink(), onOpen: _open)),
      'org' => FlowsOrgPage(app: app, api: FlowsApi(app.token)),
      'delegations' => FlowDelegationsPage(app: app),
      'calls' => titled(tr('Lịch sử cuộc gọi'), CallHistoryView(header: const SizedBox.shrink(), onOpen: _open)),
      'computers' => titled(tr('Máy tính'), const RcDevicesPage()),
      'settings' => Scaffold(backgroundColor: pal.bg, body: ProfileView(onLogout: _confirmLogout, onSwitchServer: _switchServer)),
      'assistants' => const AgentPage(),
      'bots' => const BotsPage(),
      'password' => const PasswordPage(),
      'blocked' => const BlockedUsersPage(),
      'wallpaper' => const WallpaperPage(),
      'devices' => const DevicesPage(),
      'users' => KysoApi.flygoId == null ? const _Welcome() : UsersAdminPage(id: KysoApi.flygoId!),
      'zalo' || 'wechat' => Scaffold(
          backgroundColor: pal.bg,
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              brandIcon(id, 64, id == 'zalo' ? const Color(0xFF0068FF) : const Color(0xFF07C160)),
              const SizedBox(height: 16),
              Text(id == 'zalo' ? 'Zalo' : 'WeChat', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
              const SizedBox(height: 8),
              Text(tr('Chức năng đang phát triển'), style: TextStyle(fontSize: 15, color: pal.sub)),
            ]),
          ),
        ),
      _ => const _Welcome(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    if (widget.solo != null) return _soloBody(app);
    _syncPaneFocus();

    if (_wide) {
      final multi = _panes.isMulti;
      // Nhiều ô: luồng / thông tin / AI mở ngay trong ô, không có cột phải.
      // Đang mở một trang (vd Quy trình) ở vùng giữa: cột phải chỉ dành cho khung của trang đó.
      final hasChat = !multi && _page == null && _selected != null && app.channels.containsKey(_selected);
      final showPageSide = _page != null && _pageSide != null;
      final showSide = hasChat && _side != null && _side!.$1 == _selected && app.channels.containsKey(_side!.$2);
      final showThread = hasChat && !showSide && _thread != null && _thread!.$1 == _selected;
      final showInfo = hasChat && _infoFor == _selected && !showThread && !showSide;
      // Cột phải mặc định: chat riêng với trợ lý AI của nhóm đang mở (khi không mở luồng / thông tin).
      final showAi = hasChat && !showThread && !showSide && !showInfo && _aiHidden != _selected &&
          app.showsAiFor(app.channels[_selected]!);
      // Phiên AI của một luồng (mở từ nút AI trong trang luồng); đổi sang chat khác thì về AI của cả nhóm.
      final aiThread = _aiThread != null && _aiThread!.$1 == _selected ? _aiThread!.$2 : null;
      final mainLayout = PaneHost(
        describe: _describe,
        canPopOut: isDesktop,
        popOut: _popOut,
        child: ChatHost(
        openChat: _open,
        openInfo: _hostOpenInfo,
        openThread: _hostOpenThread,
        openSide: _openSide,
        openAi: _hostOpenAi,
        openPage: _hostOpenPage,
        openSidePage: _hostOpenSidePage,
        child: AboveNavSnackBars(
          navTop: 16,
          child: Scaffold(
          backgroundColor: pal.bg,
          body: SafeArea(
            child: LayoutBuilder(builder: (context, box) {
            final total = box.maxWidth;
            _leftW = _leftW.clamp(260.0, (total * .45).clamp(260.0, 700.0));
            final rest = total - _leftW;
            final hasRight = showThread || showSide || showAi || showPageSide;
            final rightW = hasRight ? (_rightW ?? rest / 2).clamp(320.0, (rest - 360).clamp(320.0, 2000.0)) : 0.0;
            _infoW = _infoW.clamp(300.0, 600.0);
            return Row(children: [
              SizedBox(
                width: _leftW,
                child: _ColumnNavigator(
                  navKey: _leftNav,
                  // Thanh tab nổi ở đáy cột trái; tab đang chọn quyết định nội dung cột.
                  root: ListenableBuilder(
                    listenable: _leftTick,
                    builder: (context, _) {
                      final app = context.watch<AppState>();
                      return Scaffold(
                        backgroundColor: pal.bg,
                        body: Stack(children: [
                          Positioned.fill(
                            child: Column(children: [
                              _topBarWide(),
                              const OfflineBanner(),
                              // Máy tính có thanh tab trên cùng: cột trái luôn là danh sách chat, không còn thanh dưới.
                              Expanded(child: _sectionBody(0, app, 24, () => _leftNav.currentState)),
                            ]),
                          ),
                          Positioned(right: 16, bottom: 20, child: _newButton(() => _leftNav.currentState)),
                        ]),
                      );
                    },
                  ),
                ),
              ),
              _ResizeHandle(
                onDrag: (dx) => setState(() => _leftW += dx),
                onEnd: _saveLayout,
                onReset: () => setState(() => _leftW = 380),
              ),
              // Vùng nội dung: 1–4 ô (kéo chat / mục thanh tab vào để chia ô).
              Expanded(
                child: _page == null
                    ? _paneArea(app)
                    : PageCloser(
                        onClose: () => setState(() => _page = _pageSide = null),
                        child: _ColumnNavigator(key: ValueKey('page-${_page!.$1}'), root: Builder(builder: _page!.$2)),
                      ),
              ),
              if (hasRight)
                _ResizeHandle(
                  onDrag: (dx) => setState(() => _rightW = rightW - dx),
                  onEnd: _saveLayout,
                  // Bấm đúp: trở lại chia đôi với chat chính.
                  onReset: () => setState(() => _rightW = null),
                ),
              if (showPageSide) ...[
                SizedBox(
                  width: rightW,
                  child: _ColumnNavigator(key: ValueKey('pageside-${_pageSide!.$1}'), root: Builder(builder: _pageSide!.$2)),
                ),
              ],
              if (showThread) ...[
                SizedBox(
                  width: rightW,
                  child: _ColumnNavigator(
                    key: ValueKey('thread-${_thread!.$2}'),
                    root: ThreadPage(
                      channelId: _thread!.$1,
                      rootId: _thread!.$2,
                      onClose: () => setState(() => _thread = null),
                    ),
                  ),
                ),
              ],
              if (showSide) ...[
                // Luồng riêng tư ở cột phải. Trong cột: thông tin nhóm, luồng công việc riêng... mở chồng ngay trong cột.
                SizedBox(
                  width: rightW,
                  child: ChatHost(
                    openChat: _open,
                    openInfo: (id) => _sideNav.currentState?.push(AppPageRoute(builder: (_) => ChatInfoPage(channelId: id))),
                    openThread: (cid, root) =>
                        _sideNav.currentState?.push(AppPageRoute(builder: (_) => ThreadPage(channelId: cid, rootId: root))),
                    openSide: _openSide,
                    child: _ColumnNavigator(
                      key: ValueKey('side-${_side!.$2}'),
                      navKey: _sideNav,
                      root: ChatPage(channelId: _side!.$2, embedded: true, onClose: () => setState(() => _side = null)),
                    ),
                  ),
                ),
              ],
              if (showAi) ...[
                SizedBox(
                  width: rightW,
                  child: _ColumnNavigator(
                    key: ValueKey('ai-$_selected-${aiThread ?? ''}'),
                    root: AiPanel(groupId: _selected!, thread: aiThread, onClose: () => setState(() => _aiHidden = _selected)),
                  ),
                ),
              ],
              if (showInfo) ...[
                _ResizeHandle(
                  onDrag: (dx) => setState(() => _infoW -= dx),
                  onEnd: _saveLayout,
                  onReset: () => setState(() => _infoW = 380),
                ),
                SizedBox(
                  width: _infoW,
                  child: _ColumnNavigator(
                    key: ValueKey('info-$_selected'),
                    root: ChatInfoPage(channelId: _selected!, onClose: () => setState(() => _infoFor = null)),
                  ),
                ),
              ],
            ]);
            }),
          ),
        ),
        ),
      ),
      );
      return _deskShell(app, mainLayout);
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final Widget body = _tab == 0
        ? Column(children: [
            SafeArea(bottom: false, child: _topBar()),
            const OfflineBanner(),
            Expanded(child: _tabBody(app, 84 + kTabBarLift + bottomInset, () => Navigator.of(context))),
          ])
        : _tabBody(app, 84 + kTabBarLift + bottomInset, () => Navigator.of(context));

    // Gợi ý một lần: vuốt 3 ngón lên để đổi / thêm máy chủ.
    if (!_swipeHintChecked) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSwipeHint(app));
    // Thanh tab cao ~64: máy có thanh vuốt thì đáy thanh tab thấp hơn vùng an toàn 14, máy khác cách đáy 10.
    return AboveNavSnackBars(
      navTop: (bottomInset > 0 ? 50 : 74) + kTabBarLift,
      child: _threeFingerSwipe(Scaffold(
      backgroundColor: pal.bg,
      body: Stack(children: [
        Positioned.fill(child: body),
        if (_tab == 0)
          Positioned(right: 20, bottom: PlusFab.bottomOf(context), child: _newButton(() => Navigator.of(context))),
        Positioned(
          left: 20,
          right: 20,
          // Máy có thanh vuốt (iPhone): thanh tab đè nhẹ lên vùng an toàn cho thấp gọn như WhatsApp.
          bottom: (bottomInset > 0 ? bottomInset - 14 : 10) + kTabBarLift,
          child: _tabBar(app),
        ),
      ]),
      )),
    );
  }
}

/// Cho các trang trong cột chat biết đang ở giao diện máy tính nhiều cột:
/// mở chat khác, mở/đóng cột cài đặt.
class ChatHost extends InheritedWidget {
  final void Function(String channelId) openChat;
  final void Function(String channelId) openInfo;
  /// Mở chủ đề ở cột bên phải chat chính.
  final void Function(String channelId, String rootId) openThread;
  /// Mở một cuộc trò chuyện (luồng riêng tư) ở cột bên phải, giữ nguyên chat chính ở giữa.
  final void Function(String channelId)? openSide;
  /// Máy tính: hiện cột trợ lý AI của nhóm (đóng luồng / thông tin đang mở ở cột phải).
  /// Mở cột AI bên phải (máy tính); [thread]: phiên AI của luồng công việc riêng đó.
  final void Function(String groupId, {String? thread})? openAi;
  /// Máy tính: mở một trang (vd Quy trình) ở vùng giữa thay cho chat; trang con mở chồng trong vùng đó.
  final void Function(String key, WidgetBuilder builder)? openPage;
  /// Máy tính: mở một khung ở cột phải (vd cài đặt một bước của sơ đồ); null builder = đóng khung.
  final void Function(String key, WidgetBuilder? builder)? openSidePage;
  const ChatHost(
      {super.key,
      required this.openChat,
      required this.openInfo,
      required this.openThread,
      this.openSide,
      this.openAi,
      this.openPage,
      this.openSidePage,
      required super.child});
  static ChatHost? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ChatHost>();
  @override
  bool updateShouldNotify(ChatHost old) => false;
}

/// Mỗi cột có bộ điều hướng riêng: trang con mở trong cột, có nút quay lại.
/// Cột có điều hướng riêng. Trang gốc luôn là [root] của lần build mới nhất (route chỉ tạo một lần nên phải
/// chuyển qua ValueNotifier — trước đây trang gốc giữ màu cũ khi máy đổi sáng/tối lúc app đang mở).
class _ColumnNavigator extends StatefulWidget {
  final GlobalKey<NavigatorState>? navKey;
  final Widget root;
  final List<NavigatorObserver> observers;
  const _ColumnNavigator({super.key, this.navKey, required this.root, this.observers = const []});
  @override
  State<_ColumnNavigator> createState() => _ColumnNavigatorState();
}

class _ColumnNavigatorState extends State<_ColumnNavigator> {
  late final _root = ValueNotifier<Widget>(widget.root);

  @override
  void didUpdateWidget(_ColumnNavigator old) {
    super.didUpdateWidget(old);
    _root.value = widget.root;
  }

  @override
  void dispose() {
    _root.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
        child: Navigator(
          key: widget.navKey,
          observers: widget.observers,
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => ValueListenableBuilder<Widget>(valueListenable: _root, builder: (_, w, _) => w)),
        ),
      );
}

/// Quay về trang gốc của navigator (vd đóng mini app trong tab mới): báo để đặt lại tiêu đề tab.
class _TabRootObserver extends NavigatorObserver {
  final VoidCallback onRoot;
  _TabRootObserver(this.onRoot);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute?.isFirst == true) WidgetsBinding.instance.addPostFrameCallback((_) => onRoot());
  }
}

/// Một tab máy tính dạng hai / ba cột: cột trái [left] (danh sách chat, trợ lý, Quy trình…), giữa là cuộc trò chuyện
/// hoặc trang đang mở, phải là khung phụ của trang. Luồng / thông tin / AI mở chồng trong cột giữa.
/// Không có [left]: tab một cuộc trò chuyện ([initialChat]) hoặc một luồng ([initialThread] = "kênh/tin gốc").
class _SplitTab extends StatefulWidget {
  final Widget Function(BuildContext context, void Function(String id) open, String? selected)? left;
  final double leftWidth;
  final String? initialChat;
  final String? initialThread;
  /// Báo cuộc trò chuyện đang hiện ở giữa (để màn hình chính biết chat nào đang đọc).
  final void Function(String? id)? onChat;
  /// Trang ở giữa (vd một quy trình) vừa đóng.
  final VoidCallback? onPageClosed;
  /// Chưa mở gì ở giữa thì danh sách bên trái chiếm cả trang (tab Quy trình, Sếp 2026-11-14); mở trang thì về hai cột.
  final bool fullLeftWhenIdle;
  const _SplitTab({this.left, this.leftWidth = 360, this.initialChat, this.initialThread, this.onChat, this.onPageClosed, this.fullLeftWhenIdle = false});
  @override
  State<_SplitTab> createState() => _SplitTabState();
}

class _SplitTabState extends State<_SplitTab> {
  late String? _chat = widget.initialChat;
  (String, WidgetBuilder)? _page;
  (String, WidgetBuilder)? _side;
  var _centreNav = GlobalKey<NavigatorState>();
  final _leftKey = GlobalKey();
  late double _leftW = widget.leftWidth;

  @override
  void initState() {
    super.initState();
    final first = _chat ?? widget.initialThread?.split('/').first;
    if (first != null) WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChat?.call(first));
  }

  void _openChat(String id) {
    setState(() {
      if (_chat != id) _centreNav = GlobalKey<NavigatorState>();
      _chat = id;
      _page = _side = null;
    });
    widget.onChat?.call(id);
  }

  void _closeChat() {
    setState(() => _chat = null);
    widget.onChat?.call(null);
  }

  void _push(WidgetBuilder b) {
    final nav = _centreNav.currentState;
    if (nav != null && (_chat != null || widget.initialThread != null) && _page == null) {
      nav.push(AppPageRoute(builder: b));
    } else {
      setState(() {
        _page = ('push-${DateTime.now().microsecondsSinceEpoch}', b);
        _side = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final thread = widget.initialThread?.split('/');
    final Widget centre;
    if (_page != null) {
      centre = PageCloser(
        onClose: () {
          setState(() => _page = _side = null);
          widget.onPageClosed?.call();
        },
        child: _ColumnNavigator(key: ValueKey('page-${_page!.$1}'), root: Builder(builder: _page!.$2)),
      );
    } else if (thread != null && thread.length == 2 && app.channels.containsKey(thread[0])) {
      centre = _ColumnNavigator(navKey: _centreNav, root: ThreadPage(channelId: thread[0], rootId: thread[1]));
    } else if (_chat != null && app.channels.containsKey(_chat)) {
      centre = _ColumnNavigator(
        key: ValueKey('chat-$_chat'),
        navKey: _centreNav,
        root: ChatPage(channelId: _chat!, embedded: true, onClose: widget.left == null ? null : _closeChat),
      );
    } else {
      centre = const _Welcome();
    }
    final full = widget.fullLeftWhenIdle && widget.left != null && centre is _Welcome;
    // Một khoá chung: đổi giữa cả trang và cột trái vẫn giữ trạng thái danh sách (tab đang chọn, vị trí cuộn).
    final leftNav = widget.left == null
        ? null
        : _ColumnNavigator(
            key: _leftKey,
            root: Scaffold(backgroundColor: pal.bg, body: Builder(builder: (ctx) => widget.left!(ctx, _openChat, _page == null ? _chat : null))),
          );
    return ChatHost(
      openChat: _openChat,
      openInfo: (id) => _push((_) => ChatInfoPage(channelId: id)),
      openThread: (cid, root) => _push((_) => ThreadPage(channelId: cid, rootId: root)),
      openSide: (id) => _push((_) => ChatPage(channelId: id)),
      openAi: (g, {thread}) => _push((ctx) => AiPanel(groupId: g, thread: thread, onClose: () => Navigator.of(ctx).maybePop())),
      openPage: (key, b) => setState(() {
        _page = (key, b);
        _side = null;
      }),
      openSidePage: (key, b) => setState(() => _side = b == null ? null : (key, b)),
      child: LayoutBuilder(builder: (context, box) {
        _leftW = _leftW.clamp(260.0, (box.maxWidth * .5).clamp(260.0, 720.0));
        return Row(children: [
          if (full)
            Expanded(child: leftNav!)
          else if (widget.left != null) ...[
            SizedBox(width: _leftW, child: leftNav),
            _ResizeHandle(
              onDrag: (dx) => setState(() => _leftW += dx),
              onEnd: () {},
              onReset: () => setState(() => _leftW = widget.leftWidth),
            ),
          ],
          if (!full) Expanded(child: centre),
          if (_side != null) ...[
            VerticalDivider(width: 1, color: pal.divider),
            SizedBox(width: 420, child: _ColumnNavigator(key: ValueKey('side-${_side!.$1}'), root: Builder(builder: _side!.$2))),
          ],
        ]);
      }),
    );
  }
}

/// Danh sách chat của tab Chat thêm: ô tìm kiếm + danh sách (lọc theo tên).
class _LiteChatList extends StatefulWidget {
  final void Function(String id) onOpen;
  final String? selectedId;
  const _LiteChatList({required this.onOpen, this.selectedId});
  @override
  State<_LiteChatList> createState() => _LiteChatListState();
}

class _LiteChatListState extends State<_LiteChatList> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          style: TextStyle(color: pal.text, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: pal.surface,
            hintText: tr('Tìm kiếm'),
            hintStyle: TextStyle(color: pal.sub),
            prefixIcon: Icon(Icons.search, color: pal.sub, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: ChatList(
          query: _q,
          filter: ChatFilter.all,
          selectedId: widget.selectedId,
          onOpen: widget.onOpen,
          onSearchMessages: () => Navigator.of(context).push(AppPageRoute(builder: (_) => SearchPage(terms: _q, onOpen: widget.onOpen))),
          bottomPadding: 16,
        ),
      ),
    ]);
  }
}

class _ProfilePage extends StatelessWidget {
  final VoidCallback onLogout;
  final void Function(String url) onSwitchServer;
  const _ProfilePage({required this.onLogout, required this.onSwitchServer});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return EscToPop(
      child: Scaffold(
        backgroundColor: pal.bg,
        body: Stack(children: [
          ProfileView(onLogout: onLogout, onSwitchServer: onSwitchServer),
          Positioned(
            left: 16,
            top: MediaQuery.paddingOf(context).top + 10,
            child: GlassCircle(icon: Icons.arrow_back_ios_new, onTap: () => Navigator.pop(context)),
          ),
        ]),
      ),
    );
  }
}

/// Thanh tab nổi dạng viên thuốc, kính mờ: Chat · Agents (khi có trợ lý AI) · Việc · Luồng · Apps.
/// Chỉ số tab cố định theo nội dung (0 Chat, 1 Luồng, 2 Agents, 3 Apps, 4 Việc), không theo vị trí trên thanh.
/// Thanh tab điện thoại cho ảnh xem trước trong test.
@visibleForTesting
Widget debugMobileTabBar({int index = 0, bool hasAgents = true, bool hasBangTin = true}) =>
    _TabBar(index: index, unread: 3, threads: 0, missed: 0, agents: 1, hasAgents: hasAgents, hasBangTin: hasBangTin, tasks: 0, onTap: (_) {});

class _TabBar extends StatelessWidget {
  final int index;
  final int unread;
  final int threads;
  final int missed;
  final int agents;
  final bool hasAgents;
  /// Máy chủ có mini app Bảng tin: thêm tab Bảng tin (điện thoại).
  final bool hasBangTin;

  /// Số tin mới của Bảng tin (bài mới từ lần xem gần nhất + bài cần xác nhận).
  final int bangTin;
  /// Ô cuối là ảnh đại diện của mình (mở trang Apps).
  final MmUser? me;
  final int tasks;
  /// Số việc (Boards) của tôi đã quá hạn.
  final int work;
  final ValueChanged<int> onTap;
  const _TabBar({
    required this.index,
    required this.unread,
    required this.threads,
    required this.missed,
    required this.agents,
    this.hasAgents = true,
    this.hasBangTin = false,
    this.bangTin = 0,
    this.me,
    required this.tasks,
    this.work = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget item(int i, IconData icon, String label, int count, {Color? badge, Widget? avatar}) {
      final sel = i == index;
      return Expanded(
        // Máy tính: kéo một mục (Chat, Các trợ lý, Việc, Luồng, Bạn) vào vùng nội dung để mở thành một ô.
        child: PaneDragSource(
        content: PaneContent.section(PaneSections.ofTab(i)),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(i),
          child: Container(
            // 5 mục: lề ngang hẹp cho vừa điện thoại nhỏ.
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: sel ? pal.text.withValues(alpha: .10) : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              IconTheme(
                data: IconThemeData(color: pal.text.withValues(alpha: sel ? 1 : .8), size: 26),
                child: Badge(
                  isLabelVisible: count > 0,
                  backgroundColor: badge ?? pal.accent,
                  textColor: Colors.white,
                  label: Text(count > 99 ? '99+' : '$count'),
                  child: avatar == null
                      ? Icon(icon)
                      : Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: sel ? pal.accent : Colors.transparent, width: 1.5),
                          ),
                          child: avatar,
                        ),
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(fontSize: 11, fontWeight: sel ? FontWeight.w600 : FontWeight.w400, color: pal.text)),
                ),
              ),
            ]),
          ),
        ),
        ),
      );
    }

    return _LaunchGlow(
      radius: 36,
      child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: pal.text.withValues(alpha: .08)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Glass(
        radius: BorderRadius.circular(36),
        child: Row(children: [
          item(0, Icons.chat_bubble_outline, tr('Chat'), unread),
                    // Thứ tự (Sếp 10/11, đổi lại): Chat, Trợ lý, Bảng tin.
                    if (hasAgents) item(2, Icons.auto_awesome_outlined, tr('Trợ lý'), agents),
          if (hasBangTin) item(5, Icons.newspaper_rounded, tr('Bảng tin'), bangTin),
          // Điện thoại (Sếp 09/11): chỉ Chat, Trợ lý, Apps; Quy trình nằm trong Apps (Trang chủ như máy tính).
          item(3, Icons.apps_rounded, tr('Apps'), missed, badge: const Color(0xFFE53935)),
        ]),
      ),
      ),
    );
  }
}

/// Lúc mở app: một vệt viền gradient chạy đúng một vòng quanh thanh tab (khoảng 5 giây) rồi tắt.
class _LaunchGlow extends StatefulWidget {
  final double radius;
  final Widget child;
  const _LaunchGlow({required this.radius, required this.child});
  /// Chỉ chạy một lần mỗi lần mở app (đổi tab, xoay màn hình, mở lại trang không chạy lại).
  static bool _played = false;
  @override
  State<_LaunchGlow> createState() => _LaunchGlowState();
}

class _LaunchGlowState extends State<_LaunchGlow> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (_LaunchGlow._played) return;
    _LaunchGlow._played = true;
    final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5000));
    c.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) setState(() => _c = null);
    });
    _c = c;
    // Đợi khung hình đầu dựng xong để vệt sáng chạy mượt.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final accent = Pal.of(context).accent;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (_, child) => CustomPaint(
        foregroundPainter: _GlowRingPainter(t: Curves.easeInOut.transform(c.value), radius: widget.radius, accent: accent),
        child: child,
      ),
    );
  }
}

class _GlowRingPainter extends CustomPainter {
  final double t;
  final double radius;
  final Color accent;
  _GlowRingPainter({required this.t, required this.radius, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    // Hiện dần lúc đầu, mờ dần lúc cuối.
    final fade = (t < .15 ? t / .15 : t > .8 ? (1 - t) / .2 : 1.0).clamp(0.0, 1.0);
    final rect = (Offset.zero & size).deflate(1);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final colors = [
      accent.withValues(alpha: 0),
      accent.withValues(alpha: .9 * fade),
      const Color(0xFF8E7CFF).withValues(alpha: .9 * fade),
      const Color(0xFF34C3FF).withValues(alpha: .9 * fade),
      accent.withValues(alpha: 0),
    ];
    final shader = SweepGradient(
      colors: colors,
      stops: const [0, .08, .16, .24, .32],
      transform: GradientRotation(t * 2 * 3.141592653589793),
    ).createShader(rect);
    canvas.drawRRect(rrect, Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2);
    // Quầng sáng mờ phía sau vệt viền.
    canvas.drawRRect(rrect, Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  @override
  bool shouldRepaint(_GlowRingPainter old) => old.t != t || old.accent != accent;
}

/// Mục "Chat" mở trong một ô / cửa sổ riêng: ô tìm và bộ lọc riêng, không dùng chung với cột trái.
class _PaneChatList extends StatefulWidget {
  final void Function(String channelId) onOpen;
  final void Function(String query) onSearchMessages;
  const _PaneChatList({required this.onOpen, required this.onSearchMessages});
  @override
  State<_PaneChatList> createState() => _PaneChatListState();
}

class _PaneChatListState extends State<_PaneChatList> {
  String _q = '';
  ChatFilter _filter = ChatFilter.all;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          style: TextStyle(color: pal.text, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: pal.surface,
            hintText: tr('Tìm kiếm'),
            hintStyle: TextStyle(color: pal.sub),
            prefixIcon: Icon(Icons.search, color: pal.sub, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      ),
      SizedBox(
        height: 38,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          for (final f in chatFilterTabs)
              InkWell(
                onTap: () => setState(() => _filter = f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: _filter == f ? pal.accent : Colors.transparent, width: 2.5)),
                  ),
                  child: chatFilterTabLabel(context, f, _filter == f, 14),
                ),
              ),
        ]),
      ),
      const SizedBox(height: 4),
    ]);
    return ChatList(
      header: header,
      query: _q,
      filter: _filter,
      onOpen: widget.onOpen,
      onSearchMessages: () => widget.onSearchMessages(_q),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return DoodleBackground(
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: pal.accent, shape: BoxShape.circle),
            child: const Icon(Icons.forum, color: Colors.white, size: 52),
          ),
          const SizedBox(height: 24),
          Text('Flygo Chat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: pal.text)),
          const SizedBox(height: 10),
          Text(tr('Chọn một cuộc trò chuyện bên trái để bắt đầu nhắn tin.'), style: TextStyle(fontSize: 15, color: pal.sub)),
          const SizedBox(height: 28),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 14, color: pal.sub),
            const SizedBox(width: 6),
            Text(tr('Tin nhắn lưu trên máy chủ riêng của công ty'), style: TextStyle(fontSize: 13, color: pal.sub)),
          ]),
        ]),
      ),
    );
  }
}

/// Tab Danh bạ (giữa thanh tab): bấm vào ai là mở tin nhắn riêng.
class PeopleView extends StatefulWidget {
  final void Function(String channelId) onOpen;
  final double bottomPadding;
  final bool pickMode;
  /// Tiêu đề thay cho chữ "Danh bạ" mặc định (vd. tiêu đề tab có ảnh đại diện).
  final Widget? header;
  const PeopleView({super.key, required this.onOpen, this.bottomPadding = 0, this.pickMode = false, this.header});
  @override
  State<PeopleView> createState() => _PeopleViewState();
}

class _PeopleViewState extends State<PeopleView> {
  String _q = '';
  bool _busy = false;

  Future<void> _start(MmUser u) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await context.read<AppState>().openDirect(u.id);
      widget.onOpen(id);
    } catch (_) {
      messenger.showSnackBar(toast(Text(tr('Không mở được cuộc trò chuyện. Kiểm tra kết nối mạng.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final q = _q.toLowerCase();
    final people = app.people
        .where((u) => q.isEmpty || u.displayName.toLowerCase().contains(q) || u.username.contains(q) || u.email.contains(q))
        .toList();
    return Column(children: [
      if (widget.header != null)
        widget.header!
      else if (!widget.pickMode)
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text(tr('Danh bạ'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.text)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          autofocus: widget.pickMode,
          onChanged: (v) => setState(() => _q = v),
          style: TextStyle(color: pal.text),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: pal.surface,
            hintText: tr('Tìm theo tên hoặc email'),
            hintStyle: TextStyle(color: pal.sub),
            prefixIcon: Icon(Icons.search, size: 20, color: pal.sub),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
          ),
        ),
      ),
      if (_busy) LinearProgressIndicator(color: pal.accent, minHeight: 2),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(tr('{0} người', [people.length]), style: TextStyle(color: pal.sub, fontSize: 13)),
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          itemCount: people.length,
          itemBuilder: (_, i) {
            final u = people[i];
            return InkWell(
              onTap: _busy ? null : () => _start(u),
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(children: [
                  Avatar(userId: u.id, name: u.displayName, size: 46),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider, width: .6))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(u.displayName, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: pal.text)),
                        Text(u.email, style: TextStyle(color: pal.sub, fontSize: 14)),
                      ]),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// Nút "+": tạo nhóm mới. Tick chọn thành viên → Tiếp → đặt tên nhóm → tạo và mở
/// luôn khung chat. Chọn 1 người và bỏ trống tên thì mở chat riêng với người đó.
enum NewChatKind { publicGroup, privateGroup, meeting }

/// Chọn thành viên rồi đặt tên để tạo nhóm công khai, riêng tư hoặc cuộc họp.
class NewChatPage extends StatefulWidget {
  final NewChatKind kind;
  const NewChatPage({super.key, this.kind = NewChatKind.privateGroup});
  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final List<String> _picked = [];
  String _q = '';
  bool _busy = false;
  /// Trợ lý AI của mình (để thêm vào nhóm cùng người); bot khác chỉ hiện khi mình có quyền gọi.
  Set<String>? _myBots;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().myBotIds().then((v) {
      if (mounted) setState(() => _myBots = v);
    });
  }

  Future<void> _next() async {
    final app = context.read<AppState>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final kind = widget.kind;
    final now = DateTime.now();
    final ctl = TextEditingController(
        text: kind == NewChatKind.meeting ? tr('Cuộc họp {0} {1}', [hhmm(now), '${two(now.day)}/${two(now.month)}']) : '');
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(kind == NewChatKind.meeting
            ? tr('Tên cuộc họp')
            : kind == NewChatKind.publicGroup
                ? tr('Tên kênh')
                : tr('Tên nhóm')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: tr('Ví dụ: Phòng kế toán')),
            onSubmitted: (v) => Navigator.pop(d, v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                kind == NewChatKind.publicGroup
                    ? tr('Kênh công khai: mọi người trong công ty tìm và tham gia được.')
                    : kind == NewChatKind.meeting
                        ? tr('Tạo nhóm riêng tư và bắt đầu cuộc họp ngay.')
                        : tr('Nhóm riêng tư: chỉ người được mời mới thấy và tham gia.'),
                style: TextStyle(fontSize: 13, color: Pal.of(d).sub)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
          TextButton(onPressed: () => Navigator.pop(d, ctl.text), child: Text(tr('Tạo'))),
        ],
      ),
    );
    if (name == null) return;
    final n = name.trim();
    if (n.isEmpty) {
      messenger.showSnackBar(toast(Text(kind == NewChatKind.publicGroup ? tr('Hãy đặt tên cho kênh.') : tr('Hãy đặt tên cho nhóm.'))));
      return;
    }
    setState(() => _busy = true);
    try {
      nav.pop(await app.createGroup(n, _picked, public: kind == NewChatKind.publicGroup));
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(toast(Text(tr('Không tạo được nhóm. Kiểm tra kết nối mạng.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final q = _q.toLowerCase();
    final mine = _myBots ?? const <String>{};
    final people = app.peopleAndBots
        .where((u) => !u.isBot || (engineOf(u) != null && app.canCallBot(u, mine)))
        .where((u) => q.isEmpty || u.displayName.toLowerCase().contains(q) || u.username.contains(q) || u.email.contains(q))
        .toList();
    return EscToPop(
      child: Scaffold(
        backgroundColor: pal.bg,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                GlassCircle(icon: Icons.close, onTap: () => Navigator.pop(context)),
                Expanded(
                  child: Column(children: [
                    Text(
                        switch (widget.kind) {
                          NewChatKind.publicGroup => tr('Kênh mới'),
                          NewChatKind.privateGroup => tr('Nhóm mới'),
                          NewChatKind.meeting => tr('Cuộc họp mới'),
                        },
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.text)),
                    Text(tr('Đã chọn {0}', [_picked.length]), style: TextStyle(fontSize: 13, color: pal.sub)),
                  ]),
                ),
                const SizedBox(width: 44),
              ]),
            ),
            if (_picked.isNotEmpty)
              SizedBox(
                height: 78,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final id in _picked)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _picked.remove(id)),
                        child: Column(children: [
                          Stack(children: [
                            Avatar(userId: id, name: app.users[id]?.displayName ?? '?', size: 48),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(radius: 9, backgroundColor: pal.surface2, child: Icon(Icons.close, size: 12, color: pal.text)),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 56,
                            child: Text(app.users[id]?.displayName.split(' ').last ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11.5, color: pal.sub)),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                style: TextStyle(color: pal.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: pal.surface,
                  hintText: tr('Tìm theo tên hoặc email'),
                  hintStyle: TextStyle(color: pal.sub),
                  prefixIcon: Icon(Icons.search, size: 20, color: pal.sub),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            if (_busy) LinearProgressIndicator(color: pal.accent, minHeight: 2),
            Expanded(
              child: ListView(children: [
                for (final u in people)
                  CheckboxListTile(
                    value: _picked.contains(u.id),
                    activeColor: pal.accent,
                    checkColor: Colors.white,
                    checkboxShape: const CircleBorder(),
                    onChanged: (v) => setState(() {
                      // Mỗi chat chỉ một trợ lý AI: chọn trợ lý này thì bỏ trợ lý đã chọn trước.
                      if (v == true && engineOf(u) != null) _picked.removeWhere((id) => engineOf(app.users[id]) != null);
                      v == true ? _picked.add(u.id) : _picked.remove(u.id);
                    }),
                    secondary: Avatar(userId: u.id, name: u.displayName, size: 44),
                    title: nameText(u.displayName,
                        bot: u.isBot, engine: engineOf(u), style: TextStyle(color: pal.text, fontWeight: FontWeight.w500)),
                    subtitle: Text(u.isBot ? '@${u.username}' : u.email, style: TextStyle(color: pal.sub)),
                  ),
              ]),
            ),
            if (_picked.isNotEmpty || widget.kind == NewChatKind.publicGroup)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: pal.accent, foregroundColor: Colors.white),
                      onPressed: _busy ? null : _next,
                      child: Text(tr('Tiếp ({0})', [_picked.length]), style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Tab Bạn: thông tin tài khoản.
/// Tên người dùng hợp lệ của máy chủ chat: 3–22 ký tự, bắt đầu bằng chữ, chỉ a-z 0-9 . - _
final _usernameRe = RegExp(r'^[a-z][a-z0-9._-]{2,21}$');

Future<void> _renameMe(BuildContext context, AppState app, MmUser me) async {
  final nameCtl = TextEditingController(text: me.displayName);
  final userCtl = TextEditingController(text: me.username);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final un = userCtl.text.trim().toLowerCase();
      final unError = un.isEmpty || _usernameRe.hasMatch(un) ? null : tr('3–22 ký tự, bắt đầu bằng chữ, chỉ gồm a-z, 0-9, dấu . - _');
      return AlertDialog(
        title: Text(tr('Đổi tên')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtl,
            autofocus: true,
            maxLength: 64,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Tên hiển thị')),
          ),
          TextField(
            controller: userCtl,
            maxLength: 22,
            autocorrect: false,
            onChanged: (_) => set(() {}),
            decoration: InputDecoration(labelText: tr('Tên người dùng'), prefixText: '@', errorText: unError),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: unError != null ? null : () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
        ],
      );
    }),
  );
  final name = nameCtl.text.trim(), username = userCtl.text.trim().toLowerCase();
  nameCtl.dispose();
  userCtl.dispose();
  if (ok != true) return;
  try {
    await app.renameMe(name: name == me.displayName ? null : name, username: username);
  } catch (e) {
    final taken = e.toString().contains('exists') || e.toString().contains('taken');
    messenger.showSnackBar(SnackBar(
        content: Text(taken
            ? tr('Tên người dùng này đã có người dùng.')
            : tr('Không đổi được tên. Máy chủ có thể không cho đổi tên người dùng với tài khoản đăng nhập bằng Google.'))));
  }
}

class ProfileView extends StatelessWidget {
  final VoidCallback onLogout;
  final void Function(String url) onSwitchServer;
  final double bottomPadding;
  const ProfileView({super.key, required this.onLogout, required this.onSwitchServer, this.bottomPadding = 0});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final me = app.me;
    if (me == null) return const SizedBox.shrink();
    return SafeArea(
      bottom: false,
      child: ListView(padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPadding + MediaQuery.paddingOf(context).bottom + 32), children: [
        Text(tr('Bạn'), textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: pal.text)),
        const SizedBox(height: 22),
        Center(
          child: EditableAvatar(
            size: 120,
            avatar: Avatar(userId: me.id, name: me.displayName, size: 120, status: false),
            onPicked: (n, b) => app.setUserImage(me.id, n, b),
          ),
        ),
        const SizedBox(height: 16),
        // Tên + nút sửa tên bên phải.
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 40),
          Flexible(
            child: Text(me.displayName,
                textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: pal.text)),
          ),
          IconButton(
            tooltip: tr('Đổi tên'),
            icon: Icon(Icons.edit_outlined, size: 22, color: pal.sub),
            onPressed: () => _renameMe(context, app, me),
          ),
        ]),
        const SizedBox(height: 4),
        Text('@${me.username}', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: pal.sub)),
        const SizedBox(height: 28),
        InfoGroup(children: [
          InfoRow(icon: Icons.mail_outline, title: tr('Email'), value: me.email),
          InfoRow(icon: Icons.dns_outlined, title: tr('Máy chủ'), value: Uri.parse(kServerUrl).host),
          InfoRow(
              icon: app.online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              title: tr('Kết nối'),
              value: app.online ? tr('Đang trực tuyến') : tr('Ngoại tuyến')),
        ]),
        const SizedBox(height: 16),
        InfoGroup(children: [
          InfoRow(
            icon: Icons.text_format,
            title: tr('Hiển thị định dạng'),
            trailing: Switch.adaptive(
              value: app.renderMarkdown,
              activeTrackColor: pal.accent,
              onChanged: app.setRenderMarkdown,
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(tr('Bật: chữ đậm, danh sách, bảng, khối mã hiển thị đẹp. Tắt: hiện chữ thô như khi gõ.'),
              style: TextStyle(fontSize: 13, color: pal.sub)),
        ),
        const SizedBox(height: 16),
        InfoGroup(children: [
          InfoRow(icon: Icons.wb_sunny_outlined, title: tr('Nhắc việc mỗi sáng'), trailing: const TaskDigestSwitch()),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(tr('8 giờ sáng nhận một tin tóm tắt việc hôm nay và việc quá hạn.'), style: TextStyle(fontSize: 13, color: pal.sub)),
        ),
        if (DesktopTray.supported) ...[
          const SizedBox(height: 16),
          InfoGroup(children: [
            ValueListenableBuilder<bool>(
              valueListenable: DesktopTray.closeToTray,
              builder: (_, v, _) => InfoRow(
                icon: Icons.move_to_inbox_outlined,
                title: tr('Chạy ẩn khi đóng cửa sổ'),
                trailing: Switch.adaptive(value: v, activeTrackColor: pal.accent, onChanged: DesktopTray.setCloseToTray),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: DesktopTray.autostart,
              builder: (_, v, _) => InfoRow(
                icon: Icons.power_settings_new,
                title: tr('Mở cùng Windows'),
                trailing: Switch.adaptive(value: v, activeTrackColor: pal.accent, onChanged: DesktopTray.setAutostart),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
                tr('Bấm X thì Flygo Chat thu xuống khay hệ thống (góc phải thanh taskbar) và vẫn nhận tin nhắn, cuộc gọi. Muốn thoát hẳn: chuột phải vào biểu tượng ở khay → Thoát.'),
                style: TextStyle(fontSize: 13, color: pal.sub)),
          ),
        ],
        // Đăng xuất ở cuối trang cài đặt (Sếp, 2026-11-13): bấm rồi xác nhận. Cửa sổ riêng dùng chung phiên: không có.
        if (!isChildWindow) ...[
          const SizedBox(height: 28),
          Center(
            child: TextButton.icon(
              key: const ValueKey('profile-logout'),
              onPressed: onLogout,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFE53935)),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: Text(tr('Đăng xuất'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Đầu trang người dùng của trang Mở ứng dụng (Sếp, 2026-11-13, kiểu trang cá nhân): dải ảnh bìa (màu chuyển của app),
/// ảnh đại diện to ở giữa đè lên mép dưới dải bìa (viền nền, nút máy ảnh đổi ảnh), tên, "@tên · email", chức danh; hai
/// nút Chỉnh sửa hồ sơ / Đặt trạng thái; hai dòng Hoạt động / Trạng thái; chân: số bản · Kiểm tra cập nhật, Đăng xuất.
/// Không có nền xám: nằm thẳng trên nền trang. Máy chủ: [AppsServerRow].
class AppsUserCard extends StatelessWidget {
  /// "Chỉnh sửa hồ sơ" (màn chỉnh sửa hồ sơ).
  final VoidCallback onProfile;

  /// Nút ⚙️ trên dải bìa: trang Cài đặt.
  final VoidCallback? onSettings;

  /// null: không có nút Đăng xuất (cửa sổ riêng dùng chung phiên với cửa sổ chính).
  final VoidCallback? onLogout;
  const AppsUserCard({super.key, required this.onProfile, this.onSettings, this.onLogout});

  static const _cover = 150.0, _avatar = 120.0, _ring = 4.0;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final me = app.me;
    if (me == null) return const SizedBox.shrink();
    final position = '${me.raw['position'] ?? ''}'.trim();
    final bio = '${(me.raw['props'] as Map?)?['bio'] ?? ''}'.trim();
    final custom = app.customStatusOf(me.id);
    final exp = app.customStatusExpiry(me.id);
    final now = DateTime.now();
    final until = exp == null
        ? null
        : exp.year == now.year && exp.month == now.month && exp.day == now.day
            ? hhmm(exp)
            : '${hhmm(exp)} ${two(exp.day)}/${two(exp.month)}';
    final muted = TextStyle(fontSize: 14, color: pal.sub);
    final line = ['@${me.username}', if (me.email.isNotEmpty) me.email].join(' · ');
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget quiet(String label, VoidCallback onTap, {Key? key, Color? color}) => TextButton(
          key: key,
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: color ?? pal.accentText,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
    final label = Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600);
    return Padding(
      key: const ValueKey('apps-user-card'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Dải bìa + ảnh đại diện đè lên mép dưới.
        SizedBox(
          height: _cover + _avatar / 2 + _ring,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            Container(
              key: const ValueKey('apps-cover'),
              height: _cover,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(pal.accent, dark ? Colors.black : Colors.white, dark ? .35 : .15)!,
                    Color.lerp(pal.accent, const Color(0xFF7C4DFF), .45)!,
                    Color.lerp(pal.accent, const Color(0xFF00BFA5), .35)!,
                  ],
                ),
              ),
            ),
            if (onSettings != null)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: .18),
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: const ValueKey('apps-settings'),
                    tooltip: tr('Cài đặt'),
                    onPressed: onSettings,
                    icon: const Icon(Icons.settings_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            Positioned(
              top: _cover - _avatar / 2 - _ring,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  padding: const EdgeInsets.all(_ring),
                  decoration: BoxDecoration(color: pal.bg, shape: BoxShape.circle),
                  child: EditableAvatar(
                    size: _avatar,
                    avatar: Avatar(userId: me.id, name: me.displayName, size: _avatar, status: false),
                    onPicked: (n, b) => app.setUserImage(me.id, n, b),
                  ),
                ),
                // Hoạt động (chấm màu) trên viền ảnh, góc dưới bên trái (góc phải là nút máy ảnh).
                Positioned(
                  left: 14,
                  bottom: 10,
                  child: Container(
                    key: const ValueKey('apps-presence-dot'),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: pal.bg, shape: BoxShape.circle),
                    child: statusDot(app.statusOf(me.id), pal, size: 16),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(me.displayName, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 4),
        Text(line, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        if (position.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(position, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: pal.text)),
        ],
        // Trạng thái hiện tại (vd "🍜 Đang ăn trưa · đến 13:30"); bấm để đổi. Không đặt thì ẩn.
        if (custom != null) ...[
          const SizedBox(height: 8),
          Center(
            child: InkWell(
              key: const ValueKey('apps-current-status'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => StatusSection.editCustomStatus(context, app),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text.rich(
                  TextSpan(children: [
                    if (custom.emoji.isNotEmpty) TextSpan(text: '${emojiOf(custom.emoji)} '),
                    TextSpan(text: custom.text, style: TextStyle(color: pal.text, fontWeight: FontWeight.w500)),
                    if (until != null) TextSpan(text: ' · ${tr('đến {0}', [until])}', style: TextStyle(color: pal.sub)),
                  ]),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5),
                ),
              ),
            ),
          ),
        ],
        // Giới thiệu ngắn (props.bio, sửa ở màn Chỉnh sửa hồ sơ).
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(bio, key: const ValueKey('apps-bio'), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: muted.copyWith(fontSize: 13.5, height: 1.35)),
        ],
        const SizedBox(height: 16),
        // Hai nút: Chỉnh sửa hồ sơ (trang cài đặt) và Đặt trạng thái.
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('apps-edit-profile'),
              onPressed: onProfile,
              style: FilledButton.styleFrom(
                backgroundColor: pal.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: label,
              ),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(tr('Chỉnh sửa hồ sơ'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.tonalIcon(
              key: const ValueKey('apps-set-status'),
              onPressed: () => StatusSection.editCustomStatus(context, app),
              style: FilledButton.styleFrom(
                backgroundColor: pal.surface2,
                foregroundColor: pal.text,
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: label,
              ),
              icon: const Icon(Icons.emoji_emotions_outlined, size: 18),
              label: Text(tr('Đặt trạng thái'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Hoạt động và trạng thái: mỗi cái một dòng, vạch mảnh, không nền.
        const StatusSection(rows: true),
        Divider(height: 1, thickness: .6, color: pal.divider),
        // Chân: số bản · Kiểm tra cập nhật, Đăng xuất (chữ nhỏ).
        Row(children: [
          ValueListenableBuilder<String>(
            valueListenable: currentBuild,
            builder: (_, b, _) => Text(b.isEmpty ? '' : tr('Phiên bản {0}', [b]), key: const ValueKey('apps-version'), style: muted.copyWith(fontSize: 12.5)),
          ),
          // Chiếm phần còn lại (Đăng xuất dạt phải); chỉ cắt chữ khi thật sự thiếu chỗ.
          Expanded(child: Align(alignment: Alignment.centerLeft, child: quiet(tr('Kiểm tra cập nhật'), () => showUpdateDialog(context)))),
          if (onLogout != null) quiet(tr('Đăng xuất'), onLogout!, key: const ValueKey('apps-logout'), color: pal.sub),
        ]),
      ]),
    );
  }
}

/// Đầu trang Ứng dụng trên điện thoại: tên công ty (máy chủ đang dùng), không bấm được. Đổi / thêm máy chủ: vuốt 3 ngón
/// từ dưới lên, hoặc Cài đặt → Máy chủ.
class AppsServerTitle extends StatelessWidget {
  const AppsServerTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Text(ServerList.currentEntry.name,
        key: const ValueKey('apps-server-title'),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text));
  }
}

/// Nút Đăng xuất chữ nhỏ (góc dưới bên phải trang Ứng dụng): bấm rồi xác nhận.
class AppsLogoutButton extends StatelessWidget {
  final VoidCallback onLogout;
  const AppsLogoutButton({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return TextButton.icon(
      key: const ValueKey('apps-logout'),
      onPressed: onLogout,
      style: TextButton.styleFrom(
        foregroundColor: pal.sub,
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
      icon: const Icon(Icons.logout_rounded, size: 17),
      label: Text(tr('Đăng xuất')),
    );
  }
}

/// Trang hồ sơ trên điện thoại (ô "Hồ sơ" của mục Cá nhân): thẻ người dùng như cột trái của máy tính.
class AppsProfilePage extends StatelessWidget {
  final VoidCallback onProfile;
  final VoidCallback? onSettings;
  const AppsProfilePage({super.key, required this.onProfile, this.onSettings});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      appBar: AppBar(backgroundColor: pal.bg, foregroundColor: pal.text, elevation: 0, title: Text(tr('Hồ sơ'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [AppsUserCard(onProfile: onProfile, onSettings: onSettings)]),
    );
  }
}

/// Tên máy chủ đang dùng, chữ nhỏ mờ căn giữa, không bấm được (Sếp, 2026-11-13). Trang Mở ứng dụng: điện thoại ở đáy
/// trang (sau mục Cá nhân), máy tính ở dưới cùng cột trái. Đổi / thêm máy chủ: tiêu đề danh sách chat và trang Cài đặt.
class AppsServerRow extends StatelessWidget {
  final TextAlign align;
  const AppsServerRow({super.key, this.align = TextAlign.center});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (ServerList.items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Text(ServerList.currentEntry.name,
          key: const ValueKey('apps-server'),
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: pal.sub)),
    );
  }
}

Future<void> _pickLanguage(BuildContext context) async {
  final lang = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) {
      final pal = Pal.of(ctx);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(tr('Ngôn ngữ'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: pal.text)),
          ),
          for (final e in appLanguages.entries)
            ListTile(
              leading: LangFlag(e.key),
              title: Text(e.value, style: TextStyle(color: pal.text, fontSize: 16)),
              trailing: e.key == appLanguage.value ? Icon(Icons.check_circle, color: pal.accent) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
  if (lang != null && lang != appLanguage.value) {
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    await setLanguage(lang);
  }
}

/// Khối bo tròn chứa các dòng, như trang cài đặt của WhatsApp iOS.
class InfoGroup extends StatelessWidget {
  final List<Widget> children;
  const InfoGroup({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) items.add(Divider(height: 1, thickness: .6, indent: 56, color: pal.divider));
    }
    return Container(
      decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final bool danger;
  final VoidCallback? onTap;
  final Widget? trailing;
  const InfoRow(
      {super.key, required this.icon, required this.title, this.value, this.danger = false, this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final color = danger ? Colors.redAccent : pal.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        // Giới hạn giá trị theo bề ngang của chính hàng (không theo cả màn hình): trên máy tính trang này chỉ
        // chiếm một cột, giá trị dài (email) từng chiếm hết chỗ làm tiêu đề bị ngắt mỗi dòng một chữ.
        child: LayoutBuilder(
          builder: (context, box) => Row(children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
                child: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, color: color))),
            // Không dùng Flexible: nó chia đôi chiều ngang với tiêu đề, làm số đếm lệch vào giữa.
            if (value != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * .55),
                child: Text(value!,
                    textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: pal.sub)),
              ),
            ?trailing,
            if (onTap != null && !danger) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: pal.sub),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Tìm tin nhắn trên máy chủ (toàn bộ hoặc trong một cuộc trò chuyện).
class SearchPage extends StatefulWidget {
  final String terms;
  final String? channelId;
  final void Function(String channelId) onOpen;
  const SearchPage({super.key, required this.terms, this.channelId, required this.onOpen});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  List<MmPost>? _res;
  String? _err;
  late final TextEditingController _ctl = TextEditingController(text: widget.terms);

  @override
  void initState() {
    super.initState();
    if (widget.terms.isNotEmpty) _run(widget.terms);
  }

  Timer? _debounce;
  int _seq = 0;

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _run(q));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _run(String q) {
    if (q.trim().isEmpty) {
      setState(() => _res = null);
      return;
    }
    final app = context.read<AppState>();
    final seq = ++_seq;
    setState(() {
      _res = null;
      _err = null;
    });
    // Tìm cả từ đang gõ dở: thêm * vào cuối từ cuối cùng.
    var terms = q.trim();
    if (RegExp(r'[\w\u00C0-\u1EF9]$').hasMatch(terms) && !terms.contains('"')) terms = '$terms*';
    final ch = widget.channelId == null ? null : app.channels[widget.channelId];
    if (ch != null && !ch.isDirect && !ch.isGroupDm) terms = '$terms in:${ch.name}';
    app.api.search(app.teamId!, terms).then((r) {
      if (!mounted || seq != _seq) return;
      // Thảo luận của tiến trình (kênh ẩn) không hiện trong kết quả tìm của chat.
      setState(() => _res = (ch == null ? r : r.where((p) => p.channelId == ch.id)).where((p) => app.channels[p.channelId]?.isProcess != true).toList());
    }).catchError((_) {
      if (mounted && seq == _seq) setState(() => _err = tr('Không tìm được. Cần có kết nối mạng.'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              GlassCircle(icon: Icons.arrow_back_ios_new, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ctl,
                  autofocus: widget.terms.isEmpty,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _run,
                  onChanged: _changed,
                  style: TextStyle(color: pal.text),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: pal.surface,
                    hintText: tr('Tìm tin nhắn'),
                    hintStyle: TextStyle(color: pal.sub),
                    prefixIcon: Icon(Icons.search, size: 20, color: pal.sub),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: _err != null
                ? Center(child: Text(_err!, style: TextStyle(color: pal.sub)))
                : _res == null
                    ? (_ctl.text.isEmpty
                        ? const SizedBox.shrink()
                        : Center(child: CircularProgressIndicator(color: pal.accent)))
                    : _res!.isEmpty
                        ? Center(child: Text(tr('Không có tin nhắn nào phù hợp'), style: TextStyle(color: pal.sub)))
                        : ListView.separated(
                            itemCount: _res!.length,
                            separatorBuilder: (_, _) => Divider(height: 1, indent: 72, color: pal.divider),
                            itemBuilder: (_, i) {
                              final p = _res![i];
                              final ch = app.channels[p.channelId];
                              return ListTile(
                                leading:
                                    Avatar(userId: p.userId, name: app.users[p.userId]?.displayName ?? '?', size: 42),
                                title: Text(
                                    '${app.users[p.userId]?.displayName ?? ''}${ch == null ? '' : ' · ${app.channelTitle(ch)}'}',
                                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: pal.text)),
                                subtitle: Text(p.message,
                                    maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.sub)),
                                trailing: Text(listTime(p.createAt), style: TextStyle(fontSize: 12, color: pal.sub)),
                                onTap: ch == null
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        widget.onOpen(p.channelId);
                                      },
                              );
                            },
                          ),
          ),
        ]),
      ),
    );
  }
}

/// Thanh chia cột kéo được (máy tính): kéo để đổi độ rộng, bấm đúp để trở về mặc định.
class _ResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;
  final VoidCallback onEnd;
  final VoidCallback onReset;
  const _ResizeHandle({required this.onDrag, required this.onEnd, required this.onReset});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        onDoubleTap: () {
          onReset();
          onEnd();
        },
        child: SizedBox(width: 7, child: Center(child: VerticalDivider(width: 1, color: pal.divider))),
      ),
    );
  }
}

/// Trang mở ở vùng giữa (máy tính) có nút đóng ở trang gốc để quay lại chat.
class PageCloser extends InheritedWidget {
  final VoidCallback onClose;
  const PageCloser({super.key, required this.onClose, required super.child});
  static PageCloser? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PageCloser>();
  @override
  bool updateShouldNotify(PageCloser old) => false;
}

/// Ô bị lọc bởi ô tìm ứng dụng: [grid] bỏ qua.
class _HiddenTile extends SizedBox {
  const _HiddenTile() : super.shrink();
}

String _appFold(String s) {
  const a = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const b = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = a.indexOf(ch);
    out.write(i < 0 ? ch : b[i]);
  }
  return out.toString();
}
