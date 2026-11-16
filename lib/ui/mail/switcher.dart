// Thư: bộ chọn hộp thư (bấm ảnh đại diện góc trên bên phải). Liệt kê mọi hộp thư người dùng mở được: hộp của mình,
// hộp dùng chung, hộp được uỷ quyền, và (quản trị Thư) các hộp khác; kèm mức quyền và số thư chưa đọc.
import 'package:flutter/material.dart';

import 'model.dart';
import 'store.dart';
import 'widgets.dart';

/// Ảnh đại diện hộp thư: hộp dùng chung là ô vuông bo góc có biểu tượng nhóm.
class MailboxAvatar extends StatelessWidget {
  const MailboxAvatar(this.box, {super.key, this.size = 36});
  final MailboxInfo box;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!box.shared) return MailAvatar(box.person, size: size);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: avatarColor(box.id), borderRadius: BorderRadius.circular(size * .28)),
      child: Icon(Icons.groups_rounded, color: Colors.white, size: size * .58),
    );
  }
}

/// Chip mức quyền (Chỉ xem / Đọc và gửi / Quản lý).
class AccessChip extends StatelessWidget {
  const AccessChip(this.access, {super.key, this.small = false});
  final String access;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final mc = MailColors.of(context);
    final (c, i) = switch (access) {
      'read' => (mc.dark ? const Color(0xFFFBBF24) : const Color(0xFFA16207), Icons.visibility_outlined),
      'send' => (mc.accent, Icons.send_outlined),
      _ => (mc.dark ? const Color(0xFF34D399) : const Color(0xFF0F766E), Icons.shield_outlined),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 7, vertical: small ? 1 : 2),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: small ? 11 : 13, color: c),
        const SizedBox(width: 3),
        Flexible(child: Text(accessName(access), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: small ? 10.5 : 11.5, color: c, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Mở bộ chọn: máy tính là thẻ nổi dưới ảnh đại diện, điện thoại là hộp thoại phủ gần hết chiều ngang (kiểu Gmail).
Future<void> showMailboxSwitcher(BuildContext context, MailStore store, {required bool wide, VoidCallback? onAdmin}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Đóng',
    barrierColor: Colors.black.withValues(alpha: wide ? .08 : .4),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, _) => SafeArea(
      child: Align(
        alignment: wide ? Alignment.topRight : Alignment.topCenter,
        child: Padding(
          padding: wide ? const EdgeInsets.only(top: 58, right: 12) : const EdgeInsets.fromLTRB(12, 52, 12, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 400 : 480),
            child: MailboxSwitcher(
              store: store,
              onClose: () => Navigator.of(ctx).pop(),
              onAdmin: onAdmin == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      onAdmin();
                    },
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(alignment: wide ? Alignment.topRight : Alignment.topCenter, scale: Tween(begin: .96, end: 1.0).animate(a), child: child),
    ),
  );
}

class MailboxSwitcher extends StatelessWidget {
  const MailboxSwitcher({super.key, required this.store, required this.onClose, this.onAdmin});
  final MailStore store;
  final VoidCallback onClose;
  final VoidCallback? onAdmin;

  static const _groups = [('owner', 'Hộp thư của tôi'), ('member', 'Được chia sẻ với tôi'), ('admin', 'Hộp khác (quyền quản trị)')];

  // Bộ chọn mở trong hộp thoại riêng: tự vẽ lại khi danh sách hộp thư đổi (realtime / vừa quản trị xong).
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final mc = MailColors.of(context);
    final me = store.me;
    if (me == null) return const SizedBox.shrink();
    final cur = me.boxes.where((b) => b.id == me.person.email).firstOrNull ?? MailboxInfo(me.person.email, name: me.person.name, access: me.access);
    final others = me.boxes.where((b) => b.id != cur.id).toList();
    return Material(
      color: mc.dark ? const Color(0xFF232836) : const Color(0xFFE9EEF6),
      borderRadius: BorderRadius.circular(28),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 90),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const SizedBox(width: 40),
                Expanded(child: Text(cur.id, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: mc.text, fontWeight: FontWeight.w500))),
                IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close, size: 20), onPressed: onClose),
              ]),
              const SizedBox(height: 6),
              Center(child: MailboxAvatar(cur, size: 76)),
              const SizedBox(height: 10),
              Text(cur.shared ? cur.display : 'Chào, ${cur.person.short}!', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, color: mc.text)),
              const SizedBox(height: 6),
              Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
                AccessChip(cur.access),
                if (cur.shared) _tag(mc, 'Hộp dùng chung'),
                if (cur.via == 'member' && !cur.shared) _tag(mc, 'Được uỷ quyền'),
              ]),
              if (me.user != null && me.user!.email != cur.id) ...[
                const SizedBox(height: 6),
                Text('Đang đăng nhập: ${me.user!.email}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: mc.muted)),
              ],
              if (onAdmin != null) ...[
                const SizedBox(height: 14),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: onAdmin,
                    icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                    label: const Text('Quản trị Thư'),
                    style: OutlinedButton.styleFrom(shape: const StadiumBorder(), side: BorderSide(color: mc.faint), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                  ),
                ),
              ],
              if (me.features['notify'] == true && !store.api.demo) ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(color: mc.surface, borderRadius: BorderRadius.circular(20)),
                  child: SwitchListTile(
                    key: const ValueKey('mail-notify'),
                    value: me.notify,
                    onChanged: (v) => store.setNotify(v).catchError((Object e) {
                      if (context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
                    }),
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Báo thư mới qua tin nhắn', style: TextStyle(fontSize: 14)),
                    subtitle: Text('Khi app Thư đang đóng, bot Thư nhắn riêng cho bạn', style: TextStyle(fontSize: 12, color: mc.muted)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (others.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: mc.surface, borderRadius: BorderRadius.circular(20)),
                  child: Text('Bạn chưa được chia sẻ hộp thư nào khác.', textAlign: TextAlign.center, style: TextStyle(color: mc.muted, fontSize: 13)),
                )
              else
                for (final (via, title) in _groups)
                  if (others.where((b) => b.via == via).toList() case final list when list.isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: Text(title, style: TextStyle(fontSize: 12.5, color: mc.muted, fontWeight: FontWeight.w600))),
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: mc.surface, borderRadius: BorderRadius.circular(20)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0) Divider(height: 1, indent: 64, color: mc.line),
                          _row(context, mc, list[i]),
                        ],
                      ]),
                    ),
                  ],
              const SizedBox(height: 4),
              Text('Quyền với từng hộp do quản trị Thư cấp.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: mc.faint)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(MailColors mc, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: mc.chip, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 11.5, color: mc.muted, fontWeight: FontWeight.w500)),
      );

  Widget _row(BuildContext context, MailColors mc, MailboxInfo b) => InkWell(
        onTap: () {
          onClose();
          store.switchMailbox(b.id);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(children: [
            MailboxAvatar(b, size: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(b.display, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: mc.text, fontWeight: b.unread > 0 ? FontWeight.w600 : FontWeight.w500))),
                  const SizedBox(width: 6),
                  AccessChip(b.access, small: true),
                ]),
                const SizedBox(height: 2),
                Text(b.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: mc.muted)),
              ]),
            ),
            if (b.unread > 0) ...[
              const SizedBox(width: 8),
              Text(b.unread > 99 ? '99+' : '${b.unread}', style: TextStyle(fontSize: 12.5, color: mc.text, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      );
}
