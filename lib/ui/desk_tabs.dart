import 'dart:math' show Random;

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'theme.dart';

/// Tab của app máy tính (như trình duyệt): mỗi ứng dụng là một tab, một ứng dụng mở được nhiều tab.
///
/// [kind]:
/// - `launcher`: tab mới, hiện menu ứng dụng;
/// - `chat`: Chat (tab Chat chính giữ bố cục chia ô cũ; tab Chat thêm là danh sách + cuộc trò chuyện);
/// - `conv`: một cuộc trò chuyện ([arg] = id kênh), mở từ "Mở ở tab mới";
/// - `thread`: một luồng tin ([arg] = "kênh/tin gốc");
/// - `agents`: Trợ lý;
/// - `flows`: Quy trình;
/// - `app`: một ứng dụng của trang Bạn ([arg] = id trong youAppGroups, vd `contacts`);
/// - `flow`: một quy trình như một ứng dụng riêng ([arg] = "id\ttên\tbiểu tượng").
class DeskTab {
  final String id;
  String kind;
  String? arg;
  bool pinned;
  DeskTab(this.kind, {this.arg, this.pinned = false, String? id}) : id = id ?? _newId();

  static String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  Map<String, Object?> toJson() => {'id': id, 'kind': kind, if (arg != null) 'arg': arg, if (pinned) 'pinned': true};

  static DeskTab? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = j['kind'];
    if (kind is! String || !kinds.contains(kind)) return null;
    final id = j['id'];
    return DeskTab(kind, arg: j['arg'] as String?, pinned: j['pinned'] == true, id: id is String && id.isNotEmpty ? id : null);
  }

  static const kinds = {'launcher', 'chat', 'conv', 'thread', 'agents', 'flows', 'app', 'flow'};
}

/// Mở ở tab mới. null khi không có thanh tab (điện thoại, cửa sổ riêng): menu không hiện mục "Mở ở tab mới".
void Function(DeskTab tab)? openTabHook;

/// Trang đang nằm trong một tab máy tính: mini app / trang Quy trình mở ngay trong tab thay vì phủ cả cửa sổ.
class DeskTabScope extends InheritedWidget {
  /// Đặt tiêu đề tab theo nội dung đang mở trong tab (vd mini app, quy trình đang xem); null = về tên ứng dụng.
  final void Function(String? title)? onTitle;

  /// Biến tab này thành ứng dụng [appId] (`chat`, `agents`, `flows`, id trang Bạn).
  final void Function(String appId)? onLaunch;
  const DeskTabScope({super.key, this.onTitle, this.onLaunch, required super.child});
  static DeskTabScope? of(BuildContext context) => context.getInheritedWidgetOfExactType<DeskTabScope>();
  @override
  bool updateShouldNotify(DeskTabScope old) => false;
}

/// Nhãn một tab: biểu tượng (icon hoặc ảnh đại diện), tiêu đề, số chưa đọc.
class DeskTabLabel {
  final Widget icon;
  final String title;
  final int badge;
  const DeskTabLabel(this.icon, this.title, {this.badge = 0});
}

/// Thanh tab trên cùng. Kéo để đổi chỗ, nháy giữa / × để đóng, nháy phải để ghim / đóng tab khác.
class DeskTabBar extends StatelessWidget {
  final List<DeskTab> tabs;
  final int current;
  final DeskTabLabel Function(DeskTab t) label;
  final void Function(int i) onSelect;
  final void Function(int i) onClose;
  final void Function(int from, int to) onMove;
  final VoidCallback onNew;
  final void Function(int i) onTogglePin;
  final void Function(int i) onCloseOthers;

  /// Sát lề phải thanh tab (vd nút chuyển máy chủ).
  final Widget? trailing;
  const DeskTabBar({
    super.key,
    required this.tabs,
    required this.current,
    required this.label,
    required this.onSelect,
    required this.onClose,
    required this.onMove,
    required this.onNew,
    required this.onTogglePin,
    required this.onCloseOthers,
    this.trailing,
  });

  Future<void> _menu(BuildContext context, int i, Offset at) async {
    final pal = Pal.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    PopupMenuItem<String> item(String v, IconData icon, String text) => PopupMenuItem(
      value: v,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: pal.text),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: pal.text)),
        ],
      ),
    );
    final t = tabs[i];
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        item('new', Icons.add_rounded, tr('Mở Trang chủ')),
        item('pin', t.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, t.pinned ? tr('Bỏ ghim tab') : tr('Ghim tab')),
        if (!t.pinned) item('close', Icons.close_rounded, tr('Đóng tab')),
        if (tabs.length > 1) item('others', Icons.tab_unselected_rounded, tr('Đóng các tab khác')),
      ],
    );
    switch (v) {
      case 'new':
        onNew();
      case 'pin':
        onTogglePin(i);
      case 'close':
        onClose(i);
      case 'others':
        onCloseOthers(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barBg = dark ? Color.lerp(pal.bg, Colors.black, .35)! : Color.lerp(pal.bg, Colors.black, .05)!;
    return Container(
      height: 42,
      color: barBg,
      padding: const EdgeInsets.only(left: 8, top: 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                // Nút + nằm ngay sau tab cuối (như trình duyệt): danh sách tab co theo số tab.
                Flexible(
                  fit: FlexFit.loose,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      // Tab co lại khi nhiều (như trình duyệt): rộng 140–220, tab ghim chỉ còn biểu tượng.
                      final pinned = tabs.where((t) => t.pinned).length;
                      final free = tabs.length - pinned;
                      final w = free == 0 ? 220.0 : ((box.maxWidth - pinned * 48) / free - 2).clamp(110.0, 220.0);
                      return ReorderableListView.builder(
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        buildDefaultDragHandles: false,
                        itemCount: tabs.length,
                        onReorderItem: (a, b) => onMove(a, b),
                        proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                        itemBuilder: (context, i) {
                          final t = tabs[i];
                          final l = label(t);
                          final sel = i == current;
                          return ReorderableDragStartListener(
                            key: ValueKey(t.id),
                            index: i,
                            child: Listener(
                              onPointerDown: (e) {
                                // Nháy chuột giữa: đóng tab (tab ghim thì không).
                                if (e.buttons == 4 && !t.pinned) onClose(i);
                              },
                              child: GestureDetector(
                                onTap: () => onSelect(i),
                                onSecondaryTapDown: (d) => _menu(context, i, d.globalPosition),
                                child: Tooltip(
                                  message: l.title,
                                  waitDuration: const Duration(milliseconds: 700),
                                  child: Container(
                                    width: t.pinned ? 46 : w,
                                    margin: const EdgeInsets.only(right: 2),
                                    padding: EdgeInsets.only(left: t.pinned ? 0 : 10, right: t.pinned ? 0 : 4),
                                    decoration: BoxDecoration(
                                      color: sel ? pal.bg : Colors.transparent,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: t.pinned ? MainAxisAlignment.center : MainAxisAlignment.start,
                                      children: [
                                        Badge(
                                          isLabelVisible: l.badge > 0,
                                          smallSize: 8,
                                          label: Text(l.badge > 99 ? '99+' : '${l.badge}'),
                                          backgroundColor: const Color(0xFFE53935),
                                          textColor: Colors.white,
                                          child: SizedBox(width: 20, height: 20, child: Center(child: l.icon)),
                                        ),
                                        if (!t.pinned) ...[
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              l.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: sel ? pal.text : pal.sub,
                                                fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              iconSize: 15,
                                              tooltip: tr('Đóng tab'),
                                              onPressed: () => onClose(i),
                                              icon: Icon(Icons.close_rounded, color: pal.sub),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: '${tr('Mở Trang chủ')} (Ctrl+T)',
                    onPressed: onNew,
                    icon: Icon(Icons.add_rounded, size: 20, color: pal.sub),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8, bottom: 4), child: trailing),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}
