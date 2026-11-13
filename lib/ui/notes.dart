import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../data/models.dart';
import '../i18n/i18n.dart';
import '../state/app_state.dart';
import 'common.dart';
import 'theme.dart';

/// Ghi chú gắn vào tin nhắn (props.flygo_notes): ai trong chat cũng thấy và thêm được; người viết ghi chú
/// (hoặc quản trị) sửa / xoá. Tin là của người khác nên trạm đẩy sửa props hộ (flygo-chat-server relay/notes.mjs), như bình chọn.

class MessageNote {
  final String id, by, color, text;
  final int at;
  final int? editedAt;
  const MessageNote({required this.id, required this.by, required this.color, required this.text, required this.at, this.editedAt});

  factory MessageNote.fromJson(Map j) => MessageNote(
        id: '${j['id']}',
        by: '${j['by'] ?? ''}',
        color: '${j['color'] ?? 'yellow'}',
        text: '${j['text'] ?? ''}',
        at: (j['at'] as num?)?.toInt() ?? 0,
        editedAt: (j['edited_at'] as num?)?.toInt(),
      );
}

List<MessageNote> notesOfPost(MmPost post) => [
      for (final n in (post.props['flygo_notes'] as List? ?? const []))
        if (n is Map && n['id'] is String) MessageNote.fromJson(n),
    ];

/// Màu ghi chú: (tên, nền sáng, nền tối, màu nhấn).
const kNoteColors = <String, (Color, Color, Color)>{
  'yellow': (Color(0xFFFFF4C2), Color(0xFF4A4220), Color(0xFFE0B400)),
  'green': (Color(0xFFDDF5E3), Color(0xFF1F3D2A), Color(0xFF2EAD6B)),
  'blue': (Color(0xFFDCEBFF), Color(0xFF1D3150), Color(0xFF3B82F6)),
  'pink': (Color(0xFFFFE0EC), Color(0xFF4A2234), Color(0xFFE5508A)),
  'purple': (Color(0xFFEDE3FF), Color(0xFF34284D), Color(0xFF8B5CF6)),
  'orange': (Color(0xFFFFE6D1), Color(0xFF4A2F1A), Color(0xFFF07B1E)),
};

(Color, Color) noteColors(BuildContext context, String name) {
  final c = kNoteColors[name] ?? kNoteColors['yellow']!;
  return (Theme.of(context).brightness == Brightness.dark ? c.$2 : c.$1, c.$3);
}

/// Gọi trạm đẩy cho ghi chú; trả về danh sách ghi chú mới. Lỗi thì ném Exception với lời báo của trạm.
Future<List<Map<String, dynamic>>> notesCall(AppState app, String action, Map<String, dynamic> body, {http.Client? client}) async {
  final c = client ?? notesDebugClient ?? http.Client();
  final r = await c
      .post(Uri.parse('${pushUrlFor(kServerUrl)}/notes/$action'),
          headers: {
            'Authorization': 'Bearer ${app.token}',
            'X-MM-Server': kServerUrl,
            'Content-Type': 'application/json',
            'User-Agent': kUserAgent,
          },
          body: jsonEncode(body))
      .timeout(const Duration(seconds: 15));
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  if (r.statusCode != 200 || j['ok'] != true) throw Exception(j['error'] ?? 'notes $action ${r.statusCode}');
  return [for (final n in (j['notes'] as List? ?? const [])) if (n is Map) n.cast<String, dynamic>()];
}

/// Chỉ cho kiểm thử: client giả cho notesCall.
@visibleForTesting
http.Client? notesDebugClient;

/// Hộp thoại ghi chú: chọn màu + nội dung. Trả về (nội dung, màu) hoặc null nếu huỷ.
/// Cách báo khi thêm / sửa ghi chú: 'none' im lặng (mặc định), 'author' báo người gửi tin, 'all' báo cả nhóm.
const kNoteNotify = ['none', 'author', 'all'];

/// Trả về (nội dung, màu, cách báo — xem [kNoteNotify]).
Future<(String, String, String)?> showNoteEditor(BuildContext context,
    {String text = '', String color = 'yellow', bool editing = false, String notify = 'none'}) {
  final ctl = TextEditingController(text: text);
  var picked = color;
  var ping = notify;
  return showDialog<(String, String, String)>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) {
        final (bg, accent) = noteColors(d, picked);
        return AlertDialog(
          title: Text(editing ? tr('Sửa ghi chú') : tr('Thêm ghi chú')),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Báo người gửi: tin nhỏ trong luồng của tin, tag người gửi tin. Báo cả nhóm: tin ở chat chính, trích tin gốc.
              RadioGroup<String>(
                groupValue: ping,
                onChanged: (x) => set(() => ping = x ?? 'none'),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final (v, icon, label) in [
                    ('none', Icons.notifications_off_outlined, tr('Thêm ghi chú im lặng')),
                    ('author', Icons.person_outline_rounded, tr('Báo người gửi tin')),
                    ('all', Icons.groups_outlined, tr('Báo cả nhóm')),
                  ])
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      value: v,
                      secondary: Icon(icon, size: 20),
                      title: Text(label),
                    ),
                ]),
              ),
              const Divider(height: 18),
              Wrap(spacing: 10, runSpacing: 8, children: [
                for (final name in kNoteColors.keys)
                  Semantics(
                    button: true,
                    selected: name == picked,
                    label: name,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => set(() => picked = name),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: noteColors(d, name).$1,
                          shape: BoxShape.circle,
                          border: Border.all(color: noteColors(d, name).$2, width: name == picked ? 3 : 1.2),
                        ),
                        child: name == picked ? Icon(Icons.check_rounded, size: 18, color: noteColors(d, name).$2) : null,
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: accent, width: 4))),
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                // Enter để lưu ngay (mọi máy); máy tính: Shift+Enter xuống dòng.
                child: Focus(
                  onKeyEvent: (_, e) {
                    if (e is! KeyDownEvent) return KeyEventResult.ignored;
                    if (e.logicalKey != LogicalKeyboardKey.enter && e.logicalKey != LogicalKeyboardKey.numpadEnter) return KeyEventResult.ignored;
                    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
                    if (ctl.text.trim().isNotEmpty) Navigator.pop(d, (ctl.text.trim(), picked, ping));
                    return KeyEventResult.handled;
                  },
                  child: TextField(
                  controller: ctl,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 1000,
                  // Điện thoại: phím Enter của bàn phím ảo là "Xong" -> lưu ghi chú.
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (ctl.text.trim().isNotEmpty) Navigator.pop(d, (ctl.text.trim(), picked, ping));
                  },
                  decoration: InputDecoration(border: InputBorder.none, hintText: tr('Nội dung ghi chú'), counterText: ''),
                  onChanged: (_) => set(() {}),
                ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text(tr('Hủy'))),
            FilledButton(onPressed: ctl.text.trim().isEmpty ? null : () => Navigator.pop(d, (ctl.text.trim(), picked, ping)), child: Text(tr('Lưu'))),
          ],
        );
      },
    ),
  );
}

Future<void> _run(ScaffoldMessengerState? messenger, AppState app, MmPost post, String action, Map<String, dynamic> body, String done,
    {String notify = 'none'}) async {
  try {
    final notes = await notesCall(app, action, {'post_id': post.id, ...body});
    app.mergeLocalProps(post, {'flygo_notes': notes});
    messenger?.showSnackBar(toast(Text(done)));
    if (notify != 'none') await _notifyNote(app, post, '${body['text'] ?? ''}', all: notify == 'all', edited: action == 'edit');
  } catch (e) {
    final why = e is TimeoutException || e is SocketException
        ? tr('trạm không phản hồi (mạng chậm hoặc mất kết nối), thử lại sau')
        : '$e'.replaceFirst('Exception: ', '');
    messenger?.showSnackBar(toast(Text(tr('Không lưu được ghi chú: {0}', [why]))));
    // Có thể trạm đã lưu xong mà câu trả lời bị mất / đến muộn: tải lại tin để hiện đúng ghi chú trên máy chủ.
    await _syncNotes(app, post);
  }
}

/// Đọc lại ghi chú của tin từ máy chủ chat (bỏ qua nếu lỗi).
Future<void> _syncNotes(AppState app, MmPost post) async {
  try {
    final fresh = MmPost(((await app.api.get('/posts/${post.id}')) as Map).cast());
    app.mergeLocalProps(post, {'flygo_notes': fresh.props['flygo_notes'] ?? const []});
  } catch (_) {}
}

/// Báo về ghi chú vừa thêm / sửa.
/// - Người gửi tin ([all] = false): tin nhỏ trong luồng của tin (không ra chat chính), tag người gửi tin. Tin của chính mình thì thôi.
/// - Cả nhóm ([all] = true): tin ở chat chính, trích tin gốc; mọi người nhận thông báo như tin thường.
Future<void> _notifyNote(AppState app, MmPost post, String text, {required bool all, bool edited = false}) async {
  final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final clip = one.length > 140 ? '${one.substring(0, 140)}…' : one;
  final props = {'flygo_note_ping': {'post_id': post.id}};
  if (all) {
    final author = post.userId == app.me?.id ? tr('mình') : (app.users[post.userId]?.displayName ?? '');
    await app.send(post.channelId, tr(edited ? '📝 Đã sửa ghi chú trên tin của {0}: {1}' : '📝 Ghi chú mới trên tin của {0}: {1}', [author, clip]),
        props: {...props, 'flygo_quote': post.id});
    return;
  }
  if (post.userId == app.me?.id) return;
  final author = app.users[post.userId];
  if (author == null) return;
  final root = post.rootId.isNotEmpty ? post.rootId : post.id;
  await app.send(post.channelId, tr(edited ? '📝 @{0} ghi chú trên tin của bạn đã được sửa: {1}' : '📝 @{0} có ghi chú mới trên tin của bạn: {1}', [author.username, clip]),
      rootId: root, replyKind: 'thread', props: props);
}

/// Menu bấm giữ tin → "Thêm ghi chú".
/// Bấm Lưu là lưu luôn, kể cả khi dòng tin đã được dựng lại trong lúc hộp thoại mở (không bỏ qua im lặng).
Future<void> addMessageNote(BuildContext context, AppState app, MmPost post) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final r = await showNoteEditor(context);
  if (r == null) return;
  await _run(messenger, app, post, 'add', {'text': r.$1, 'color': r.$2}, tr('Đã thêm ghi chú'), notify: r.$3);
}

/// Chỉ người viết được sửa / xoá ghi chú (quản trị cũng không sửa / xoá ghi chú của người khác).
bool _canManage(AppState app, MessageNote n) => n.by == app.me?.id;

/// Các ghi chú dưới một tin.
class MessageNotes extends StatelessWidget {
  final AppState app;
  final MmPost post;
  final double width;
  /// Chân bong bóng: ghi chú sát mép trái / phải / dưới của bong bóng (bong bóng cắt góc theo bo tròn của nó).
  final bool flush;
  const MessageNotes({super.key, required this.app, required this.post, required this.width, this.flush = false});

  Future<void> _menu(BuildContext context, MessageNote n) async {
    final manage = _canManage(app, n);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.copy_rounded), title: Text(tr('Sao chép')), onTap: () => Navigator.pop(s, 'copy')),
          if (manage) ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Sửa ghi chú')), onTap: () => Navigator.pop(s, 'edit')),
          if (manage)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: Text(tr('Xoá ghi chú'), style: const TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(s, 'delete'),
            ),
        ]),
      ),
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: n.text));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã sao chép'))));
      case 'edit':
        final r = await showNoteEditor(context, text: n.text, color: n.color, editing: true);
        if (r == null) return;
        await _run(messenger, app, post, 'edit', {'note_id': n.id, 'text': r.$1, 'color': r.$2}, tr('Đã sửa ghi chú'), notify: r.$3);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(tr('Xoá ghi chú này?')),
            content: Text(n.text, maxLines: 4, overflow: TextOverflow.ellipsis),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Hủy'))),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(d, true), child: Text(tr('Xoá'))),
            ],
          ),
        );
        if (ok == true) await _run(messenger, app, post, 'delete', {'note_id': n.id}, tr('Đã xoá ghi chú'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = notesOfPost(post);
    final pal = Pal.of(context);
    // Ghi chú trải hết bề rộng bong bóng (bong bóng có ghi chú dựng theo IntrinsicWidth): nền ánh nhẹ màu ghi chú,
    // vạch màu mảnh bên trái, chữ theo màu chữ của bong bóng; người viết + giờ nhỏ, mờ ở dòng trên, nội dung bên dưới.
    // Màu chữ lấy từ bảng màu của bong bóng (Pal đã đổi theo nền bong bóng, vd bong bóng của mình nền xanh đậm thì chữ
    // sáng); DefaultTextStyle trong bong bóng có thể vẫn là chữ đen nên ghi chú khó đọc trên nền tối (Sếp, 2026-11-11).
    final fg = pal.text;
    return Padding(
      padding: EdgeInsets.only(top: flush ? 0 : 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (final (i, n) in notes.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : (flush ? 1 : 4)),
            child: Builder(builder: (context) {
              final (_, accent) = noteColors(context, n.color);
              final who = n.by == app.me?.id ? tr('Bạn') : (app.users[n.by]?.displayName ?? '');
              final d = DateTime.fromMillisecondsSinceEpoch(n.editedAt ?? n.at);
              final meta = [who, '${dayLabel(d)} ${hhmm(d)}', if (n.editedAt != null) tr('đã sửa')].where((s) => s.isNotEmpty).join(' · ');
              return Material(
                color: accent.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .16 : .10),
                borderRadius: BorderRadius.circular(flush ? 0 : 8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onLongPress: () => _menu(context, n),
                  onSecondaryTap: () => _menu(context, n),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Container(width: 3, color: accent),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(flush ? 11 : 9, 7, 12, 7),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(Icons.sticky_note_2_outlined, size: 12, color: accent),
                              const SizedBox(width: 4),
                              // Người tạo ghi chú (trạm ghi theo token người gọi, không giả được).
                              Avatar(userId: n.by, name: who, size: 14, status: false),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(meta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: fg.withValues(alpha: .55), fontWeight: FontWeight.w500)),
                              ),
                            ]),
                            const SizedBox(height: 3),
                            Text(n.text, style: TextStyle(color: fg, fontSize: 13.5, height: 1.3)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }),
          ),
      ]),
    );
  }
}
