import 'dart:async';

import 'package:flutter/material.dart';

import '../../../calls/call_service.dart';
import '../../../i18n/i18n.dart';
import 'fx_api.dart';

// Hỏi đáp trong cuộc họp: ai cũng đặt câu hỏi (có thể ẩn danh), bấm 👍 để đẩy lên; chủ trì / phó phòng đánh dấu đã trả lời,
// ghim. Câu hỏi là tin trong chat của cuộc họp (relay đăng), nên họp xong vẫn còn trong nhóm.

class QaItem {
  final String id, text, byName;
  final bool anon, voted, mine, answered, pinned;
  final int votes, at;
  QaItem.fromJson(Map j)
      : id = j['id'] as String,
        text = (j['text'] as String?) ?? '',
        byName = (j['by_name'] as String?) ?? '',
        anon = j['anon'] == true,
        voted = j['voted'] == true,
        mine = j['mine'] == true,
        answered = j['answered'] == true,
        pinned = j['pinned'] == true,
        votes = (j['votes'] as num?)?.toInt() ?? 0,
        at = (j['at'] as num?)?.toInt() ?? 0;
}

Future<void> showQa(BuildContext context, CallService call) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF2D2E31),
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _QaSheet(call: call),
    );

class _QaSheet extends StatefulWidget {
  final CallService call;
  const _QaSheet({required this.call});
  @override
  State<_QaSheet> createState() => _QaSheetState();
}

class _QaSheetState extends State<_QaSheet> {
  final _text = TextEditingController();
  List<QaItem> _items = const [];
  bool _manage = false, _anon = false, _loading = true, _sending = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Câu hỏi / 👍 của người khác: tải lại mỗi 4 giây khi bảng đang mở.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  int get _since => (widget.call.startedAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch) - 60000;

  Future<void> _load() async {
    try {
      final j = await fxRequest(widget.call, 'GET', '/qa?since=$_since');
      if (!mounted) return;
      setState(() {
        _items = [for (final q in (j['questions'] as List? ?? const [])) QaItem.fromJson(q as Map)];
        _manage = j['can_manage'] == true;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _act(String method, String path, [Map<String, dynamic>? body]) async {
    try {
      await fxRequest(widget.call, method, path, body);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _ask() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await fxRequest(widget.call, 'POST', '/qa', {'text': t, 'anon': _anon});
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _row(QaItem q) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(color: const Color(0xFF3A3B3F), borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${q.pinned ? '📌 ' : ''}${q.text}', style: const TextStyle(color: Colors.white, fontSize: 15)),
              const SizedBox(height: 4),
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(q.anon ? tr('Ẩn danh') : q.byName, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                if (q.answered)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFF1F4A35), borderRadius: BorderRadius.circular(10)),
                    child: Text(tr('Đã trả lời'), style: const TextStyle(color: Color(0xFFA6F0C9), fontSize: 11)),
                  ),
              ]),
            ]),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
              onPressed: () => _act('POST', '/qa/${q.id}/vote'),
              style: TextButton.styleFrom(
                foregroundColor: q.voted ? const Color(0xFF8AB4F8) : Colors.white70,
                minimumSize: const Size(56, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: Icon(q.voted ? Icons.thumb_up : Icons.thumb_up_outlined, size: 16),
              label: Text('${q.votes}'),
            ),
            if (_manage || q.mine)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: Colors.white54, size: 20),
                color: const Color(0xFF3A3B3F),
                onSelected: (a) => a == 'del' ? _act('DELETE', '/qa/${q.id}') : _act('POST', '/qa/${q.id}/$a'),
                itemBuilder: (_) => [
                  if (_manage) ...[
                    PopupMenuItem(value: 'answer', child: Text(q.answered ? tr('Bỏ đánh dấu đã trả lời') : tr('Đánh dấu đã trả lời'), style: const TextStyle(color: Colors.white))),
                    PopupMenuItem(value: 'pin', child: Text(q.pinned ? tr('Bỏ ghim') : tr('Ghim'), style: const TextStyle(color: Colors.white))),
                  ],
                  PopupMenuItem(value: 'del', child: Text(tr('Xoá câu hỏi'), style: const TextStyle(color: Color(0xFFF28B82)))),
                ],
              ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Hỏi đáp · {0}', [_items.length]), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _items.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)))
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('Chưa có câu hỏi nào. Câu hỏi sẽ được lưu vào chat của cuộc họp.'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
              )
            else
              Flexible(child: ListView(shrinkWrap: true, children: [for (final q in _items) _row(q)])),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _ask(),
                  decoration: InputDecoration(
                    hintText: tr('Đặt câu hỏi…'),
                    hintStyle: const TextStyle(color: Colors.white38),
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFF3A3B3F),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: _sending ? null : _ask, icon: const Icon(Icons.send, size: 20)),
            ]),
            Row(children: [
              Checkbox(value: _anon, onChanged: (v) => setState(() => _anon = v == true)),
              GestureDetector(
                onTap: () => setState(() => _anon = !_anon),
                child: Text(tr('Hỏi ẩn danh'), style: const TextStyle(color: Colors.white70)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
