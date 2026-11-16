// Danh bạ có hai tab: Nội bộ (người dùng chat, như trước) và Khách (Danh bạ khách, app vn.flygo.contacts).
// Máy chủ chưa cài / mình chưa được cấp Danh bạ khách thì chỉ có Nội bộ, không hiện thanh chọn tab.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../home_page.dart' show PeopleView;
import '../theme.dart';
import 'api.dart';
import 'contacts_view.dart';

class DirectoryView extends StatefulWidget {
  const DirectoryView({super.key, required this.onOpen, this.guests = false, this.openContactId, this.bottomPadding = 0});
  final void Function(String channelId) onOpen;
  /// Mở sẵn tab Khách.
  final bool guests;
  final String? openContactId;
  final double bottomPadding;
  @override
  State<DirectoryView> createState() => _DirectoryViewState();
}

class _DirectoryViewState extends State<DirectoryView> {
  ContactsApi? _api;
  late bool _guests = widget.guests || widget.openContactId != null;
  /// Tab Khách chỉ tải khi mở lần đầu.
  late bool _guestsSeen = _guests;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    ContactsApi.forServer(context.read<AppState>().token).then((a) {
      if (mounted) setState(() { _api = a; _checked = true; });
    }).catchError((_) {
      if (mounted) setState(() => _checked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final app = context.watch<AppState>();
    final people = PeopleView(header: const SizedBox.shrink(), onOpen: widget.onOpen, bottomPadding: widget.bottomPadding);
    if (_api == null) {
      if (!_checked && _guests) return const Center(child: CircularProgressIndicator());
      return people;
    }
    Widget seg(String label, bool sel, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? pal.bg : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: sel ? [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 3, offset: const Offset(0, 1))] : null,
              ),
              child: Text(label, style: TextStyle(fontSize: 14, fontWeight: sel ? FontWeight.w600 : FontWeight.w500, color: sel ? pal.text : pal.sub)),
            ),
          ),
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: pal.surface2, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              seg('${tr('Nội bộ')} · ${app.people.length}', !_guests, () => setState(() => _guests = false)),
              const SizedBox(width: 3),
              seg(tr('Khách'), _guests, () => setState(() => _guests = _guestsSeen = true)),
            ]),
          ),
        ),
      ),
      Expanded(
        child: IndexedStack(index: _guests ? 1 : 0, children: [
          people,
          if (_guestsSeen) ContactsView(api: _api!, openId: widget.openContactId, bottomPadding: widget.bottomPadding) else const SizedBox.shrink(),
        ]),
      ),
    ]);
  }
}
