// "Hỏi AI" / "Nhờ AI lập báo cáo": chọn trợ lý AI của mình, viết câu hỏi, gửi vào chat riêng với trợ lý kèm ngữ cảnh báo cáo
// (mã bản để trợ lý gọi report_ask_context). Trợ lý chạy bằng quyền của người hỏi (vé Flygo ID theo biên nhận tin nhắn).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../chat_page.dart';
import '../home_page.dart' show ChatHost;
import '../theme.dart';
import 'blocks.dart';

Future<void> showAskAi(BuildContext context, {required String title, String hint = '', String initial = '', required String context_}) async {
  AppState? app;
  try {
    app = context.read<AppState>();
  } catch (_) {}
  final messenger = ScaffoldMessenger.of(context);
  if (app == null) return;
  final mine = await app.myBotIds();
  final bots = app.users.values.where((u) => u.isBot && u.deleteAt == 0 && mine.contains(u.id) && app!.isAssistant(u.id)).toList()
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  if (bots.isEmpty) {
    messenger.showSnackBar(toast(const Text('Bạn chưa có trợ lý AI nào. Thêm trợ lý ở mục Trợ lý AI rồi thử lại.')));
    return;
  }
  if (!context.mounted) return;
  final host = ChatHost.of(context);
  final nav = Navigator.of(context);
  final r = await showModalBottomSheet<(MmUser, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Pal.of(context).bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (c) => _AskSheet(title: title, hint: hint, initial: initial, bots: bots),
  );
  if (r == null) return;
  try {
    final id = await app.openDirect(r.$1.id);
    await app.send(id, '${r.$2}\n\n_($context_)_');
    if (host != null) {
      host.openChat(id);
    } else {
      nav.push(AppPageRoute(builder: (_) => ChatPage(channelId: id)));
    }
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

class _AskSheet extends StatefulWidget {
  const _AskSheet({required this.title, required this.hint, required this.initial, required this.bots});
  final String title, hint, initial;
  final List<MmUser> bots;
  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  late final _text = TextEditingController(text: widget.initial);
  late MmUser _bot = widget.bots.first;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(context, (_bot, t));
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: aiColor(context), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: widget.hint,
              filled: true,
              fillColor: p.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (widget.bots.length > 1)
                DropdownButton<MmUser>(
                  value: _bot,
                  underline: const SizedBox(),
                  items: [for (final b in widget.bots) DropdownMenuItem(value: b, child: Text(b.displayName))],
                  onChanged: (b) => setState(() => _bot = b ?? _bot),
                )
              else
                Text('Trợ lý: ${_bot.displayName}', style: TextStyle(color: p.sub)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _send,
                style: FilledButton.styleFrom(backgroundColor: kReportColor),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Gửi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
