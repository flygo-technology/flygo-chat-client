// Lịch: ô tìm người / kênh trên Flygo Chat (GET /api/people) — dùng cho khách mời, chia sẻ lịch và "Tìm giờ rảnh với…".
import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'look.dart';
import 'model.dart';
import 'store.dart';

/// Kết quả chọn: principal (`mm:<id>` / `ch:<id>`) + tên hiển thị.
typedef Picked = ({String principal, String id, String name, bool channel, int members});

class PeopleSearch extends StatefulWidget {
  const PeopleSearch({super.key, required this.store, required this.onPick, this.channels = true, this.hint, this.exclude = const {}, this.autofocus = false});
  final CalStore store;
  final ValueChanged<Picked> onPick;
  final bool channels;
  final String? hint;
  /// principal đã có (không hiện lại).
  final Set<String> exclude;
  final bool autofocus;

  @override
  State<PeopleSearch> createState() => _PeopleSearchState();
}

class _PeopleSearchState extends State<PeopleSearch> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<CPerson> _people = [];
  List<CChannel> _channels = [];
  bool _busy = false;
  int _gen = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _people = [];
        _channels = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    final gen = ++_gen;
    setState(() => _busy = true);
    try {
      final (p, c) = await widget.store.api.people(q);
      if (!mounted || gen != _gen) return;
      setState(() {
        _people = p.where((x) => x.id != widget.store.meId).toList();
        _channels = widget.channels ? c : [];
      });
    } catch (_) {
      // Mất mạng: giữ kết quả cũ.
    } finally {
      if (mounted && gen == _gen) setState(() => _busy = false);
    }
  }

  void _pick(Picked p) {
    widget.onPick(p);
    _q.clear();
    setState(() {
      _people = [];
      _channels = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final people = _people.where((p) => !widget.exclude.contains('mm:${p.id}')).toList();
    final chans = _channels.where((c) => !widget.exclude.contains('ch:${c.id}')).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TextField(
        key: const ValueKey('people-q'),
        controller: _q,
        autofocus: widget.autofocus,
        onChanged: _changed,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: widget.hint ?? tr('Thêm khách (người trên Flygo Chat)'),
          isDense: true,
          filled: true,
          fillColor: pal.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
        ),
      ),
      if (people.isNotEmpty || chans.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 240),
          child: Material(
            color: calDark(context) ? pal.surface2 : pal.bg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: pal.divider)),
            clipBehavior: Clip.antiAlias,
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), children: [
            for (final p in people)
              ListTile(
                key: ValueKey('person-${p.id}'),
                dense: true,
                leading: personAvatar(context, p.name, r: 14),
                title: Text(p.name),
                subtitle: p.username.isEmpty ? null : Text('@${p.username}', style: TextStyle(color: pal.sub, fontSize: 12)),
                onTap: () => _pick((principal: 'mm:${p.id}', id: p.id, name: p.name, channel: false, members: 1)),
              ),
            for (final c in chans)
              ListTile(
                key: ValueKey('channel-${c.id}'),
                dense: true,
                leading: personAvatar(context, c.displayName, r: 14, channel: true),
                title: Text(c.displayName),
                subtitle: Text(tr('Kênh · {0} thành viên', [c.members]), style: TextStyle(color: pal.sub, fontSize: 12)),
                onTap: () => _pick((principal: 'ch:${c.id}', id: c.id, name: '${c.displayName} (${c.members})', channel: true, members: c.members)),
              ),
          ]),
          ),
        ),
    ]);
  }
}

/// Hộp chọn một người / kênh.
Future<Picked?> pickPrincipal(BuildContext context, CalStore store, {bool channels = true, Set<String> exclude = const {}, String? title}) => showCalSheet<Picked>(
      context,
      width: 440,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title ?? tr('Thêm người hoặc kênh'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Flexible(
            child: PeopleSearch(
              store: store,
              channels: channels,
              exclude: exclude,
              autofocus: true,
              hint: tr('Tìm theo tên'),
              onPick: (p) => Navigator.pop(c, p),
            ),
          ),
        ]),
      ),
    );
