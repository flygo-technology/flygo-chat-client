// Thư: trạng thái màn hình (mục đang xem, danh sách, chọn nhiều, đếm chưa đọc) và các thao tác có hoàn tác.
// Realtime: [startLive] nghe kênh `/mail/api/live`; thư mới / đổi trạng thái từ máy khác thì tải lại lặng lẽ.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'live.dart';
import 'model.dart';

/// Mục đang xem: một hộp (inbox…), một nhãn, hoặc kết quả tìm kiếm.
@immutable
class MailView {
  const MailView.box(this.box)
      : label = null,
        q = null;
  const MailView.label(String this.label)
      : box = 'inbox',
        q = null;
  const MailView.search(String this.q)
      : box = 'inbox',
        label = null;
  final String box;
  final String? label, q;

  bool get isSearch => q != null;
  bool get isLabel => label != null;
  bool get isBox => !isSearch && !isLabel;

  @override
  bool operator ==(Object other) => other is MailView && other.box == box && other.label == label && other.q == q;
  @override
  int get hashCode => Object.hash(box, label, q);
}

/// Thao tác trên cuộc hội thoại.
enum MailAction { archive, trash, spam, notSpam, restore, read, unread, star, unstar, important, unimportant, forever }

/// Bộ nhớ đệm hộp thư đến lần trước (một tệp mỗi máy chủ / người / hộp): mở Thư hiện ngay danh sách cũ rồi làm mới.
abstract class MailCache {
  Future<Map?> read();
  Future<void> write(Map j);
}

class MailStore extends ChangeNotifier {
  MailStore(this.api, {this.cache});
  final MailApi api;
  final MailCache? cache;

  /// Đang hiện danh sách từ bộ nhớ đệm và tải bản mới (vạch tải mảnh trên cùng, không khung chờ).
  bool syncing = false;

  MailMe? me;
  List<MailLabel> labels = [];
  MailCounts counts = const MailCounts();
  MailView view = const MailView.box('inbox');
  String category = 'primary';
  List<MailThreadSummary> items = [];
  int total = 0, page = 1;
  final int size = 50;
  bool loading = false;
  /// Đang đổi sang hộp thư khác (hiện khung chờ cả địa chỉ hộp).
  bool switching = false;
  Object? error;
  final selected = <String>{};
  bool _disposed = false;

  MailLive? _live;
  Timer? _reloadT, _meT;
  final _remote = StreamController<Set<String>>.broadcast();

  /// Cuộc hội thoại vừa đổi ở nơi khác (thư mới, đọc / gắn sao / nhãn từ máy khác): màn hình đang mở nó tự tải lại.
  Stream<Set<String>> get remoteThreads => _remote.stream;

  /// Kênh realtime đang nối được.
  bool get live => _live?.up ?? false;

  /// Địa chỉ hộp đang xem.
  String get mailboxId => (api.mailbox ?? me?.person.email ?? '').toLowerCase();

  bool get categories => (me?.has('categories') ?? true) && view == const MailView.box('inbox');
  bool get hasSelection => selected.isNotEmpty;
  /// Chỉ được xem hộp thư này: không soạn / không đổi trạng thái (máy chủ cũng chặn).
  bool get readOnly => me?.readOnly ?? false;
  MailLabel? labelById(String id) => labels.where((l) => l.id == id).firstOrNull;

  String get title => switch (view) {
        MailView(isSearch: true) => 'Kết quả tìm kiếm',
        MailView(label: final l?) => labelById(l)?.name ?? 'Nhãn',
        _ => boxName(view.box),
      };

  static String boxName(String b) => const {
        'inbox': 'Hộp thư đến',
        'starred': 'Có gắn sao',
        'snoozed': 'Đã tạm ẩn',
        'sent': 'Đã gửi',
        'scheduled': 'Đã lên lịch',
        'drafts': 'Thư nháp',
        'important': 'Quan trọng',
        'all': 'Tất cả thư',
        'spam': 'Thư rác',
        'trash': 'Thùng rác',
      }[b] ??
      b;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopLive();
    _remote.close();
    super.dispose();
  }

  /// Nghe kênh realtime trong lúc màn hình Thư mở ([connector] để test).
  void startLive({MailLiveConnector? connector}) {
    if (_live != null) return;
    _live = MailLive(target: api.liveTarget, onEvent: onLive, connector: connector)..start();
  }

  void stopLive() {
    _live?.stop();
    _live = null;
    _reloadT?.cancel();
    _meT?.cancel();
  }

  /// App vừa mở lại (từ nền): nối lại ngay và tải lại.
  void resumed() {
    _live?.kick();
    _reloadSoon();
    _meSoon();
  }

  void onLive(MailLiveEvent e) {
    if (_disposed) return;
    switch (e.type) {
      case 'mail':
        if (e.mailbox == mailboxId) {
          _reloadSoon();
          if (e.threads.isNotEmpty && !_remote.isClosed) _remote.add(e.threads.toSet());
        }
        // Số thư chưa đọc của các hộp khác (chấm đỏ trên ảnh đại diện, bộ chọn hộp thư).
        if (e.mailbox != mailboxId || e.isNew) _meSoon();
      case 'boxes':
        _meSoon(fast: true);
      case 'resync' || 'poll':
        _reloadSoon();
        _meSoon();
    }
  }

  void _reloadSoon() {
    _reloadT?.cancel();
    _reloadT = Timer(const Duration(milliseconds: 250), () {
      if (_disposed || me == null) return;
      load(quiet: true);
    });
  }

  void _meSoon({bool fast = false}) {
    _meT?.cancel();
    _meT = Timer(Duration(milliseconds: fast ? 150 : 900), refreshMe);
  }

  /// Tải lại danh sách hộp thư (sau khi quản trị tạo / xoá hộp, đổi quyền). Hộp đang xem bị thu quyền thì về hộp mặc định.
  Future<void> refreshMe() async {
    if (_disposed) return;
    try {
      final m = await api.me();
      if (_disposed) return;
      final lost = api.mailbox != null && m.boxes.isNotEmpty && !m.boxes.any((b) => b.id == api.mailbox!.toLowerCase());
      me = m;
      _notify();
      if (lost) {
        api.mailbox = null;
        view = const MailView.box('inbox');
        category = 'primary';
        page = 1;
        items = [];
        selected.clear();
        await start();
      }
    } catch (_) {}
  }

  /// Báo thư mới của hộp đang xem qua tin nhắn chat khi app Thư đóng.
  Future<void> setNotify(bool on) async {
    await api.setNotify(on);
    await refreshMe();
  }

  Future<void> start() async {
    if (me == null) await _restore();
    syncing = me != null && items.isNotEmpty;
    if (syncing) _notify();
    try {
      final r = await Future.wait([api.me(), api.labels(), api.counts()]);
      me = r[0] as MailMe;
      labels = r[1] as List<MailLabel>;
      counts = r[2] as MailCounts;
      error = null;
    } catch (e) {
      error = e;
      syncing = false;
      _notify();
      return;
    }
    // Đang hiện danh sách cũ: tải lặng lẽ, thay khi có bản mới.
    await load(quiet: items.isNotEmpty);
    if (syncing) {
      syncing = false;
      _notify();
    }
  }

  /// Mục mặc định (hộp thư đến, trang đầu): mục được lưu vào bộ nhớ đệm.
  bool get _cacheable => view == const MailView.box('inbox') && page == 1 && (!categories || category == 'primary');

  /// Hộp thư đang xem trong bộ nhớ đệm ("" = hộp mặc định của người dùng).
  String get _cacheBox => (api.mailbox ?? '').toLowerCase();

  Future<void> _restore() async {
    final c = cache;
    if (c == null || !_cacheable) return;
    try {
      final j = await c.read();
      if (j == null || j['box'] != _cacheBox || me != null || _disposed) return;
      me = MailMe.fromJson(j['me'] as Map);
      labels = [for (final l in j['labels'] as List? ?? const []) MailLabel.fromJson(l as Map)];
      counts = MailCounts.fromJson(j['counts'] as Map? ?? const {});
      items = [for (final t in j['items'] as List? ?? const []) MailThreadSummary.fromJson(t as Map)];
      total = (j['total'] as num?)?.toInt() ?? items.length;
    } catch (_) {
      // Bộ nhớ đệm hỏng: bỏ qua, tải như lần đầu.
      me = null;
      labels = [];
      counts = const MailCounts();
      items = [];
      total = 0;
    }
  }

  void _persist() {
    final c = cache, m = me;
    if (c == null || m == null || !_cacheable) return;
    c.write({
      'box': _cacheBox,
      'me': m.toCache(),
      'labels': [for (final l in labels) l.toCache()],
      'counts': counts.toCache(),
      'items': [for (final t in items.take(size)) t.toCache()],
      'total': total,
    }).catchError((_) {});
  }

  /// Đổi sang hộp thư khác (bộ chọn hộp thư): máy chủ đổi theo X-Mailbox, mọi trạng thái màn hình làm lại từ đầu.
  Future<void> switchMailbox(String id) async {
    if (id == (api.mailbox ?? me?.person.email)) return;
    api.mailbox = id;
    view = const MailView.box('inbox');
    category = 'primary';
    page = 1;
    items = [];
    total = 0;
    selected.clear();
    loading = true;
    switching = true;
    _notify();
    try {
      await start();
    } finally {
      switching = false;
      _notify();
    }
  }

  Future<void> open(MailView v) async {
    if (v != view) {
      view = v;
      page = 1;
      selected.clear();
      items = [];
    }
    await load();
  }

  Future<void> setCategory(String c) async {
    category = c;
    page = 1;
    selected.clear();
    items = []; // khung chờ ngay, không để danh sách của tab cũ
    total = 0;
    await load();
  }

  Future<void> load({bool quiet = false}) async {
    final v = view;
    if (!quiet) {
      loading = true;
      _notify();
    }
    try {
      final r = await api.list(box: v.box, label: v.label, q: v.q, category: categories ? category : null, page: page, size: size);
      if (v != view) return;
      items = r.items;
      total = r.total;
      if (r.counts != null) counts = r.counts!;
      selected.removeWhere((id) => !items.any((t) => t.id == id));
      error = null;
      _persist();
    } catch (e) {
      error = e;
    }
    loading = false;
    _notify();
  }

  Future<void> refreshCounts() async {
    try {
      counts = await api.counts();
      _notify();
    } catch (_) {}
  }

  Future<void> nextPage() async {
    if (page * size >= total) return;
    page++;
    await load();
  }

  Future<void> prevPage() async {
    if (page <= 1) return;
    page--;
    await load();
  }

  void toggleSelect(String id) {
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    _notify();
  }

  void selectWhere(bool Function(MailThreadSummary t) f) {
    selected
      ..clear()
      ..addAll(items.where(f).map((t) => t.id));
    _notify();
  }

  void clearSelection() {
    if (selected.isEmpty) return;
    selected.clear();
    _notify();
  }

  MailThreadSummary? byId(String id) => items.where((t) => t.id == id).firstOrNull;

  static MailChange changeFor(MailAction a) => switch (a) {
        MailAction.archive => const MailChange(box: 'all'),
        MailAction.trash => const MailChange(box: 'trash'),
        MailAction.spam => const MailChange(box: 'spam'),
        MailAction.notSpam || MailAction.restore => const MailChange(box: 'inbox'),
        MailAction.read => const MailChange(unread: false),
        MailAction.unread => const MailChange(unread: true),
        MailAction.star => const MailChange(starred: true),
        MailAction.unstar => const MailChange(starred: false),
        MailAction.important => const MailChange(important: true),
        MailAction.unimportant => const MailChange(important: false),
        MailAction.forever => const MailChange(),
      };

  static String? messageFor(MailAction a, int n) {
    final what = n > 1 ? '$n cuộc hội thoại' : 'cuộc hội thoại';
    return switch (a) {
      MailAction.archive => 'Đã lưu trữ $what',
      MailAction.trash => 'Đã chuyển $what vào Thùng rác',
      MailAction.spam => 'Đã báo cáo là thư rác',
      MailAction.notSpam || MailAction.restore => 'Đã chuyển $what vào Hộp thư đến',
      MailAction.read => 'Đã đánh dấu là đã đọc',
      MailAction.unread => 'Đã đánh dấu là chưa đọc',
      MailAction.important => 'Đã đánh dấu là quan trọng',
      MailAction.unimportant => 'Đã đánh dấu là không quan trọng',
      MailAction.forever => 'Đã xoá vĩnh viễn $what',
      _ => null,
    };
  }

  /// Hộp phù hợp cho phím "e": lưu trữ trong Hộp thư đến, ở nơi khác thì đưa về Hộp thư đến.
  MailAction archiveOrRestore(MailThreadSummary? t) => (t?.box ?? view.box) == 'inbox' ? MailAction.archive : MailAction.restore;

  /// Áp thay đổi (cập nhật ngay trên danh sách rồi gọi máy chủ). Trả lại hàm hoàn tác (null nếu không hoàn tác được).
  Future<Future<void> Function()?> apply(List<String> ids, MailChange change, {List<MailThreadSummary> extra = const []}) async {
    if (ids.isEmpty) return null;
    if (readOnly) throw MailException(403, 'Bạn chỉ có quyền xem hộp thư này');
    final targets = [...items.where((t) => ids.contains(t.id)), ...extra.where((t) => !items.contains(t))];
    final before = {for (final t in targets) t.id: t.snapshot()};
    for (final t in targets) {
      change.applyTo(t);
    }
    final leaves = change.leavesBox ||
        (view.isLabel && change.removeLabels.contains(view.label)) ||
        (view.box == 'starred' && view.isBox && change.starred == false) ||
        (view.box == 'important' && view.isBox && change.important == false);
    if (leaves) {
      items.removeWhere((t) => ids.contains(t.id));
      total = (total - ids.length).clamp(0, 1 << 30);
      selected.removeAll(ids);
    }
    _notify();
    try {
      final c = await api.modify(ids, change);
      if (c != null) counts = c;
    } catch (e) {
      error = e;
      await load(quiet: true);
      rethrow;
    }
    _notify();
    return () async {
      final all = labels.map((l) => l.id).toList();
      for (final e in before.entries) {
        final s = e.value;
        final had = (s['labels'] as List).cast<String>();
        await api.modify([e.key], MailChange(box: s['box'] as String, unread: s['unread'] as bool, starred: s['starred'] as bool, important: s['important'] as bool, addLabels: had, removeLabels: all.where((l) => !had.contains(l)).toList()));
      }
      await load(quiet: true);
      await refreshCounts();
    };
  }

  Future<Future<void> Function()?> act(MailAction a, List<String> ids, {List<MailThreadSummary> extra = const []}) async {
    if (readOnly) throw MailException(403, 'Bạn chỉ có quyền xem hộp thư này');
    if (a == MailAction.forever) {
      await api.remove(ids);
      items.removeWhere((t) => ids.contains(t.id));
      selected.removeAll(ids);
      total = (total - ids.length).clamp(0, 1 << 30);
      _notify();
      await refreshCounts();
      return null;
    }
    return apply(ids, changeFor(a), extra: extra);
  }

  /// Tạm ẩn tới [until] (null = bỏ tạm ẩn); trả hàm hoàn tác.
  Future<Future<void> Function()?> snooze(List<String> ids, DateTime? until) async {
    final undo = await apply(ids, until == null ? const MailChange(unsnooze: true) : MailChange(snooze: until));
    if (until == null) return undo;
    return () async {
      await api.modify(ids, const MailChange(unsnooze: true));
      await load(quiet: true);
      await refreshCounts();
    };
  }

  /// Huỷ hẹn giờ gửi: thư trở lại Thư nháp.
  Future<void> cancelScheduled(String draftId) async {
    await api.cancelScheduled(draftId);
    await load(quiet: true);
    await refreshCounts();
  }

  Future<MailLabel> createLabel(String name, int color) async {
    final l = await api.createLabel(name, color);
    labels = [...labels, l];
    _notify();
    return l;
  }

  /// Đọc thư: tải chi tiết và đánh dấu đã đọc.
  Future<MailThread> openThread(String id) async {
    final t = await api.thread(id);
    if (t.summary.unread && !readOnly) {
      t.summary.unread = false;
      byId(id)?.unread = false;
      api.modify([id], const MailChange(unread: false)).then((c) {
        if (c != null) counts = c;
        _notify();
      }).catchError((_) {});
      _notify();
    }
    return t;
  }
}
