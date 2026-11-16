// Tin của bot Danh bạ khách (props.flygo_app = vn.flygo.contacts, props.flygo_contact): nút mở thẳng liên hệ.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../i18n/i18n.dart';
import '../../state/app_state.dart';
import '../app_route.dart';
import '../theme.dart';
import 'api.dart';
import 'contact_page.dart';

/// Id liên hệ mà tin [p] trỏ tới; null nếu không phải tin của Danh bạ khách.
String? contactOf(MmPost p) {
  if (p.props['flygo_app'] != kContactsApp) return null;
  final id = '${p.props['flygo_contact'] ?? ''}';
  return RegExp(r'^[A-Za-z0-9_-]{6,40}$').hasMatch(id) ? id : null;
}

/// Mở trang một liên hệ khách (từ tin nhắn, link).
Future<void> openContact(BuildContext context, String id) async {
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  try {
    final api = await ContactsApi.forServer(context.read<AppState>().token);
    if (api == null) throw StateError(tr('Bạn chưa được dùng Danh bạ khách trên máy chủ này'));
    final me = await api.me();
    await nav.push(AppPageRoute(builder: (_) => ContactPage(api: api, id: id, me: me)));
  } catch (e) {
    messenger.showSnackBar(toast(Text('$e')));
  }
}

class ContactOpenButton extends StatelessWidget {
  const ContactOpenButton({super.key, required this.contactId});
  final String contactId;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Pal.of(context).accentText),
          onPressed: () => openContact(context, contactId),
          icon: const Icon(Icons.contacts_outlined, size: 18),
          label: Text(tr('Mở liên hệ')),
        ),
      );
}
