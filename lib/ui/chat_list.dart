import '../i18n/i18n.dart';
import 'package:flutter/gestures.dart' show kMiddleMouseButton, kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import 'chat_info_page.dart';
import 'common.dart';
import 'panes/pane_layout.dart';
import 'panes/pane_view.dart';
import 'theme.dart';
import 'threads_view.dart';
import 'desk_tabs.dart' show DeskTab, openTabHook;

enum ChatFilter { all, unread, favorites, groups, direct, threads }

/// Thứ tự tab lọc trong trang Chat: "Luồng riêng" (luồng công khai + bí mật chưa đóng) đứng thứ hai.
/// Số luồng (công khai + bí mật) chưa đóng.
int openThreadCount(AppState app) =>
    app.privateThreads.where((c) => !c.isClosed).length + app.workThreads.where((t) => !app.isThreadClosed(t.root.channelId, t.root.id)).length;

/// Nhãn một tab lọc của Chat; "Luồng riêng" kèm số luồng đang mở.
Widget chatFilterTabLabel(BuildContext context, ChatFilter f, bool selected, double fontSize) {
  final pal = Pal.of(context);
  final text = Text(chatFilterLabels[f]!,
      style: TextStyle(fontSize: fontSize, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? pal.accentText : pal.sub));
  if (f != ChatFilter.threads) return text;
  final n = openThreadCount(context.watch<AppState>());
  if (n == 0) return text;
  return Row(mainAxisSize: MainAxisSize.min, children: [
    text,
    const SizedBox(width: 5),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: pal.accent.withValues(alpha: .16), borderRadius: BorderRadius.circular(10)),
      child: Text('$n', style: TextStyle(fontSize: fontSize - 3.5, fontWeight: FontWeight.w700, color: pal.accentText)),
    ),
  ]);
}

const chatFilterTabs = [ChatFilter.all, ChatFilter.threads, ChatFilter.unread, ChatFilter.favorites, ChatFilter.groups, ChatFilter.direct];

Map<ChatFilter, String> get chatFilterLabels => {
  ChatFilter.all: tr('Tất cả'),
  ChatFilter.unread: tr('Chưa đọc'),
  ChatFilter.favorites: tr('Yêu thích'),
  ChatFilter.groups: tr('Nhóm'),
  ChatFilter.direct: tr('Tin nhắn riêng'),
  ChatFilter.threads: tr('Luồng riêng'),
};

/// Danh sách hội thoại: kênh và tin nhắn riêng chung một danh sách.
class ChatList extends StatelessWidget {
  final String query;
  final ChatFilter filter;
  final String? selectedId;
  final void Function(String channelId) onOpen;
  final VoidCallback? onSearchMessages;
  final Widget? header;
  final double bottomPadding;
  const ChatList({
    super.key,
    this.query = '',
    this.filter = ChatFilter.all,
    this.selectedId,
    required this.onOpen,
    this.onSearchMessages,
    this.header,
    this.bottomPadding = 0,
  });

  bool _match(ChatSummary c, Set<String> favorites) {
    final ch = c.channel;
    switch (filter) {
      case ChatFilter.all:
        break;
      case ChatFilter.unread:
        if (c.unread == 0 && c.mentions == 0) return false;
      case ChatFilter.favorites:
        if (!favorites.contains(ch.id)) return false;
      case ChatFilter.groups:
        if (ch.isDirect) return false;
      case ChatFilter.direct:
        if (!ch.isDirect && !ch.isGroupDm) return false;
      case ChatFilter.threads:
        return false;
    }
    final q = query.trim().toLowerCase();
    return q.isEmpty || c.title.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    if (filter == ChatFilter.threads) return ThreadsView(header: header, query: query, bottomPadding: bottomPadding, openOnly: true);
    final app = context.watch<AppState>();
    final pal = Pal.of(context);
    // Chat 1-1 với bot (trợ lý nằm ở tab Agents, bot thường thì ẩn) không hiện ở tab Chat.
    // Chat 1-1 với bot (trợ lý AI, System bot, bot tích hợp) hiện như chat thường (Sếp 26/10: bỏ ẩn).
    final chats = app.chats.where((c) => _match(c, app.favorites)).toList();
    final searchRow = query.trim().length >= 2 && onSearchMessages != null;
    final extra = (header != null ? 1 : 0);
    return RefreshIndicator(
      color: pal.accent,
      onRefresh: app.syncAll,
      child: ListView.builder(
        // Chừa chỗ cho nút + nổi để dòng chat cuối (ngày, số chưa đọc) không bị che.
        padding: EdgeInsets.only(bottom: bottomPadding + 80),
        itemCount: extra + (app.ready ? chats.length : 1) + (searchRow ? 1 : 0),
        itemBuilder: (context, i) {
          if (header != null && i == 0) return header!;
          i -= extra;
          if (!app.ready) {
            if (app.lastError != null) {
              return Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  Icon(Icons.cloud_off, size: 48, color: pal.sub),
                  const SizedBox(height: 12),
                  Text(tr('Chưa kết nối được máy chủ.'),
                      textAlign: TextAlign.center, style: TextStyle(color: pal.text, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  // Lý do cụ thể: mạng, máy chủ chậm, chưa có nhóm, lỗi đồng bộ…
                  SelectableText(app.lastError!, textAlign: TextAlign.center, style: TextStyle(color: pal.sub, fontSize: 14)),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: pal.accent, foregroundColor: Colors.white),
                    onPressed: app.syncAll,
                    child: Text(tr('Thử lại')),
                  ),
                ]),
              );
            }
            return Padding(
                padding: const EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: pal.accent)));
          }
          if (i == chats.length) {
            return ListTile(
              leading: Icon(Icons.search, color: pal.sub),
              title: Text(tr('Tìm "{0}" trong tin nhắn', [query]), style: TextStyle(color: pal.text)),
              onTap: onSearchMessages,
            );
          }
          return ChatTile(
            c: chats[i],
            selected: chats[i].channel.id == selectedId,
            onTap: () => onOpen(chats[i].channel.id),
          );
        },
      ),
    );
  }
}

/// Chỗ chạm gần nhất trong danh sách chat, để menu giữ-lâu hiện đúng chỗ.
Offset? _lastDown;
/// Ctrl+nháy vừa mở chat ở tab mới: bỏ qua cú nháy thường đi kèm.
bool _ctrlOpened = false;

class ChatTile extends StatelessWidget {
  final ChatSummary c;
  final bool selected;
  final VoidCallback onTap;
  const ChatTile({super.key, required this.c, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final pal = Pal.of(context);
    final last = c.last;
    final mine = last != null && last.userId == app.me?.id;
    final unread = c.unread > 0;
    final typing = app.typingIn(c.channel.id);
    final ch = c.channel;
    final muted = app.notificationsOff(ch.id);
    String prefix = '';
    if (last != null && !mine && !ch.isDirect && !last.isSystem) {
      prefix = '~${app.users[last.userId]?.displayName ?? ''}: ';
    }
    IconData? leadIcon;
    if (last != null && last.message.isEmpty && last.files.isNotEmpty) {
      leadIcon = last.files.first.isImage ? Icons.photo_camera : Icons.insert_drive_file;
    }
    final preview = last != null && last.message.isEmpty && last.files.isNotEmpty
        ? (last.files.first.isImage ? tr('Ảnh') : last.files.first.name)
        : app.previewText(last);

    // Máy tính: kéo dòng chat vào vùng nội dung để mở thành một ô (thả ra ngoài cửa sổ: cửa sổ riêng).
    return PaneDragSource(
      content: PaneContent.chat(c.channel.id),
      // Nháy chuột giữa / Ctrl+nháy (máy tính có thanh tab): mở ở tab mới.
      child: Listener(
      onPointerDown: (e) {
        final hook = openTabHook;
        if (hook == null) return;
        final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
        if (e.buttons == kMiddleMouseButton || (ctrl && e.buttons == kPrimaryMouseButton)) {
          _ctrlOpened = true;
          hook(DeskTab('conv', arg: c.channel.id));
        }
      },
      child: Material(
      color: selected ? pal.surface : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_ctrlOpened) {
            _ctrlOpened = false;
            return;
          }
          onTap();
        },
        onTapDown: (d) => _lastDown = d.globalPosition,
        onLongPress: () => showChatActions(context, app, c.channel.id, at: _lastDown),
        onSecondaryTapDown: (d) => showChatActions(context, app, c.channel.id, at: d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Avatar(
                userId: c.avatarUserId,
                name: c.title,
                size: 56,
                icon: c.avatarUserId == null ? chatIcon(c.channel) : null,
                channel: c.channel,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(top: 12, bottom: 12, right: 16),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider, width: .6))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    // Có tin "Khẩn cấp" (đỏ, nháy nhanh) / "Quan trọng" (cam) chưa đọc: chấm nháy trước tên chat.
                    if (app.alertLevelOf(ch.id) case final lvl when lvl.isNotEmpty)
                      Padding(padding: const EdgeInsets.only(right: 6), child: _AlertDot(urgent: lvl == 'urgent')),
                    if (app.isFavorite(ch.id))
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.star_rounded, size: 18, color: const Color(0xFFF5B400)),
                      ),
                    // Nhóm công khai: nhãn "Công khai" trước tên.
                    if (c.channel.isPublic && !c.channel.isSub)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: pal.accent.withValues(alpha: .16), borderRadius: BorderRadius.circular(6)),
                        child: Text(tr('Công khai'),
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: pal.accentText)),
                      ),
                    // Đã tắt thông báo (Sếp): biểu tượng chuông tắt trước tên, tên mờ đi; ảnh chat giữ nguyên.
                    if (muted)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.notifications_off_rounded, size: 17, color: pal.sub),
                      ),
                    Expanded(
                      child: nameText(c.title,
                          bot: app.users[c.avatarUserId]?.isBot == true, engine: engineOf(app.users[c.avatarUserId]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: muted ? pal.sub : pal.text)),
                    ),
                    const SizedBox(width: 8),
                    Text(listTime(c.sortTime),
                        style: TextStyle(fontSize: 14, color: unread ? pal.accentText : pal.sub)),
                  ]),
                  const SizedBox(height: 3),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: typing.isNotEmpty
                          ? Text(tr('đang soạn tin...'), style: TextStyle(color: pal.accentText, fontSize: 15))
                          : Text.rich(
                              TextSpan(children: [
                                if (mine && !last.isSystem)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: statusIcon(last, app, pal, size: 17)),
                                  ),
                                if (leadIcon != null)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: Icon(leadIcon, size: 17, color: pal.sub)),
                                  ),
                                TextSpan(text: '$prefix$preview'),
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: pal.sub, fontSize: 15, height: 1.3),
                            ),
                    ),
                    if (c.mentions > 0 && !ch.isDirect)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, top: 2),
                        child: CircleAvatar(
                            radius: 11,
                            backgroundColor: pal.accent,
                            child: const Text('@', style: TextStyle(color: Colors.white, fontSize: 12))),
                      ),
                    if (unread)
                      Container(
                        margin: const EdgeInsets.only(left: 6, top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(11)),
                        child: Text(c.unread > 99 ? '99+' : '${c.unread}',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ),
    ),
    );
  }
}

/// Biểu tượng trạng thái tin của mình: đồng hồ, lỗi, hai dấu tích xám/xanh.
Widget statusIcon(MmPost p, AppState app, Pal pal, {double size = 15}) {
  switch (p.sendState) {
    case SendState.sending:
      return Icon(Icons.schedule, size: size - 2, color: pal.sub);
    case SendState.failed:
      return Icon(Icons.error_outline, size: size, color: Colors.redAccent);
    case SendState.sent:
      final seen = app.channels[p.channelId]?.isDirect == true && app.isSeen(p);
      return Icon(Icons.done_all, size: size, color: seen ? pal.tick : pal.sub);
  }
}

/// Chấm nháy trước tên chat khi có tin ưu tiên chưa đọc: đỏ nháy nhanh (Khẩn cấp), cam chậm hơn (Quan trọng).
class _AlertDot extends StatefulWidget {
  final bool urgent;
  const _AlertDot({required this.urgent});
  @override
  State<_AlertDot> createState() => _AlertDotState();
}

class _AlertDotState extends State<_AlertDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.urgent ? 550 : 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.urgent ? const Color(0xFFE5484D) : const Color(0xFFF59E0B);
    return Tooltip(
      message: widget.urgent ? tr('Có tin khẩn cấp chưa đọc') : tr('Có tin quan trọng chưa đọc'),
      child: FadeTransition(
        opacity: Tween(begin: .25, end: 1.0).animate(_c),
        child: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: .6), blurRadius: 6)]),
        ),
      ),
    );
  }
}
