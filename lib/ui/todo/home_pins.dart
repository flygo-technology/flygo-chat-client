// Ghi chú ghim lên Trang chủ (Sếp, 2026-11-17). Lưu ở preferences Mattermost của người dùng (flygo_chat/home_notes):
// riêng từng người, đồng bộ mọi thiết bị, cập nhật ngay qua sự kiện preferences_changed; không cần sửa máy chủ Ghi chú.
// Mỗi ghim giữ bản tóm tắt (tiêu đề, vài dòng / tiến độ danh sách, màu) để Trang chủ hiện ngay, không phải tải Ghi chú;
// bản tóm tắt được làm mới mỗi khi app Ghi chú mở và đồng bộ trên bất kỳ thiết bị nào.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../state/app_state.dart';
import 'model.dart';

const kHomeNotesPref = 'home_notes';

/// Tối đa số ghim (Trang chủ hiện 6, phần còn lại ở "Xem tất cả").
const kHomeNotesMax = 30;

/// Tóm tắt một ghi chú đã ghim lên Trang chủ.
@immutable
class HomeNotePin {
  const HomeNotePin({required this.id, this.title = '', this.lines = const [], this.kind = 'note', this.done = 0, this.total = 0, this.color = 'default', this.at = 0});
  final String id, title, kind, color;
  /// Vài dòng đầu (ghi chú) hoặc các mục chưa xong (danh sách).
  final List<String> lines;
  /// Danh sách việc: số mục đã xong / tổng số mục.
  final int done, total;
  /// Lúc ghim (ms): mới ghim đứng trước.
  final int at;

  factory HomeNotePin.fromNote(TNote n, {int? at}) {
    final checks = n.blocks.where((b) => b.t == 'check').toList();
    final list = checks.isNotEmpty;
    final lines = [
      for (final b in list ? checks.where((b) => !b.done) : n.blocks)
        if (b.text.trim().isNotEmpty) b.text.trim(),
    ].take(4).map((s) => s.length > 120 ? '${s.substring(0, 120)}…' : s).toList();
    return HomeNotePin(
      id: n.id,
      title: n.title.trim(),
      lines: lines,
      kind: list ? 'list' : 'note',
      done: checks.where((b) => b.done).length,
      total: checks.length,
      color: n.color,
      at: at ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory HomeNotePin.fromJson(Map m) => HomeNotePin(
        id: '${m['id']}',
        title: '${m['title'] ?? ''}',
        lines: [for (final l in (m['lines'] as List? ?? const [])) '$l'],
        kind: '${m['kind'] ?? 'note'}',
        done: (m['done'] as num?)?.toInt() ?? 0,
        total: (m['total'] as num?)?.toInt() ?? 0,
        color: '${m['color'] ?? 'default'}',
        at: (m['at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title.isNotEmpty) 'title': title,
        if (lines.isNotEmpty) 'lines': lines,
        if (kind != 'note') 'kind': kind,
        if (total > 0) 'done': done,
        if (total > 0) 'total': total,
        if (color != 'default') 'color': color,
        'at': at,
      };

  /// Cùng nội dung hiển thị (bỏ qua lúc ghim).
  bool sameAs(HomeNotePin o) => jsonEncode({...toJson(), 'at': 0}) == jsonEncode({...o.toJson(), 'at': 0});
}

/// Các ghi chú ghim lên Trang chủ của người đang đăng nhập (máy chủ chat hiện tại).
class HomeNotePins extends ChangeNotifier {
  HomeNotePins._();
  static final instance = HomeNotePins._();

  List<HomeNotePin> pins = const [];
  AppState? _app;
  Timer? _save;

  bool has(String id) => pins.any((p) => p.id == id);

  @visibleForTesting
  void debugSet(List<HomeNotePin> v) {
    pins = v;
    notifyListeners();
  }

  void _set(List<HomeNotePin> v, {bool save = true}) {
    pins = [...v]..sort((a, b) => b.at.compareTo(a.at));
    if (pins.length > kHomeNotesMax) pins = pins.sublist(0, kHomeNotesMax);
    notifyListeners();
    if (save) _persistSoon();
  }

  void _parse(Object? raw) {
    try {
      final j = raw is String ? jsonDecode(raw) : raw;
      _set([for (final p in (j is List ? j : const [])) if (p is Map && p['id'] != null) HomeNotePin.fromJson(p)], save: false);
    } catch (_) {}
  }

  /// Đăng nhập / đổi máy chủ: đọc lại danh sách ghim.
  Future<void> load(AppState app) async {
    _app = app;
    pins = const [];
    notifyListeners();
    final me = app.me;
    if (me == null) return;
    try {
      final r = (await app.api.get('/users/${me.id}/preferences/flygo_chat/name/$kHomeNotesPref') as Map).cast<String, dynamic>();
      _parse(r['value']);
    } catch (_) {}
  }

  /// Sự kiện preferences_changed / preferences_deleted (ghim / bỏ ghim trên thiết bị khác).
  void onPref(Map p, {required bool deleted}) {
    if (p['category'] != 'flygo_chat' || p['name'] != kHomeNotesPref) return;
    if (deleted) {
      _set(const [], save: false);
    } else {
      _parse(p['value']);
    }
  }

  void _persistSoon() {
    final app = _app, me = app?.me;
    if (app == null || me == null) return;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), () {
      app.api.put('/users/${me.id}/preferences', [
        {'user_id': me.id, 'category': 'flygo_chat', 'name': kHomeNotesPref, 'value': jsonEncode([for (final p in pins) p.toJson()])}
      ]).catchError((_) => null);
    });
  }

  /// Ghim / bỏ ghim [n] lên Trang chủ. Trả về true nếu giờ đang ghim.
  /// [app]: chỉ cần khi chưa [load] (kiểm thử); bình thường dùng phiên đang đăng nhập.
  bool toggle(TNote n, {AppState? app}) {
    _app = app ?? _app;
    if (has(n.id)) {
      _set(pins.where((p) => p.id != n.id).toList());
      return false;
    }
    _set([HomeNotePin.fromNote(n), ...pins]);
    return true;
  }

  void unpin(String id, {AppState? app}) {
    _app = app ?? _app;
    if (has(id)) _set(pins.where((p) => p.id != id).toList());
  }

  /// App Ghi chú vừa đồng bộ ([loaded] = đã có danh sách đầy đủ từ máy chủ): làm mới bản tóm tắt của các ghim, bỏ ghim
  /// ghi chú đã vào thùng rác hoặc không còn (bị xoá, thôi được chia sẻ).
  void refreshFrom(Map<String, TNote> notes, {required bool loaded}) {
    if (pins.isEmpty) return;
    var changed = false;
    final next = <HomeNotePin>[];
    for (final p in pins) {
      final n = notes[p.id];
      if (n == null || n.trashed) {
        if (loaded) {
          changed = true;
          continue;
        }
        next.add(p);
        continue;
      }
      final fresh = HomeNotePin.fromNote(n, at: p.at);
      if (!fresh.sameAs(p)) changed = true;
      next.add(fresh);
    }
    if (changed) _set(next);
  }
}
