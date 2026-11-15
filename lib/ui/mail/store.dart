// Thư: trạng thái màn hình (mục đang xem, danh sách, chọn nhiều, đếm chưa đọc) và các thao tác có hoàn tác.
import 'package:flutter/foundation.dart';

import 'api.dart';
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

class MailStore extends ChangeNotifier {
  MailStore(this.api);
  final MailApi api;

  MailMe? me;
  List<MailLabel> labels = [];
  MailCounts counts = const MailCounts();
  MailView view = const MailView.box('inbox');
  String category = 'primary';
  List<MailThreadSummary> items = [];
  int total = 0, page = 1;
  final int size = 50;
  bool loading = false;
  Object? error;
  final selected = <String>{};
  bool _disposed = false;

  bool get categories => (me?.has('categories') ?? true) && view == const MailView.box('inbox');
  bool get hasSelection => selected.isNotEmpty;
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
    super.dispose();
  }

  Future<void> start() async {
    try {
      final r = await Future.wait([api.me(), api.labels(), api.counts()]);
      me = r[0] as MailMe;
      labels = r[1] as List<MailLabel>;
      counts = r[2] as MailCounts;
      error = null;
    } catch (e) {
      error = e;
      _notify();
      return;
    }
    await load();
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

  Future<MailLabel> createLabel(String name, int color) async {
    final l = await api.createLabel(name, color);
    labels = [...labels, l];
    _notify();
    return l;
  }

  /// Đọc thư: tải chi tiết và đánh dấu đã đọc.
  Future<MailThread> openThread(String id) async {
    final t = await api.thread(id);
    if (t.summary.unread) {
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
