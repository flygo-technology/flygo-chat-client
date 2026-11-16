// Danh bạ khách: các mảnh giao diện dùng chung (biểu tượng liên hệ, nhãn loại, dòng danh sách, khung thẻ).
import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../theme.dart';
import 'api.dart';

/// Màu nhãn theo quan hệ: màu thương hiệu tầm trung, nền là chính màu đó mờ đi nên đọc được cả nền sáng lẫn tối.
Color typeColor(String t) => switch (t) {
      'customer' => const Color(0xFF2F80ED),
      'lead' => const Color(0xFFD97706),
      'supplier' => const Color(0xFF16A34A),
      'partner' => const Color(0xFF8B5CF6),
      'shipping' => const Color(0xFF0D9488),
      'agency' => const Color(0xFF64748B),
      _ => const Color(0xFF64748B),
    };

class TypeChip extends StatelessWidget {
  const TypeChip(this.type, {super.key, this.label});
  final String type;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final c = typeColor(type);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: dark ? .22 : .13), borderRadius: BorderRadius.circular(6)),
      child: Text(label ?? typeLabel(type),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: dark ? Color.lerp(c, Colors.white, .45) : Color.lerp(c, Colors.black, .25))),
    );
  }
}

/// Biểu tượng liên hệ: công ty là ô vuông bo góc có hình toà nhà, người là vòng tròn có chữ cái đầu.
class ContactIcon extends StatelessWidget {
  const ContactIcon({super.key, required this.kind, required this.name, this.size = 44});
  final String kind, name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    if (kind == 'company') {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: pal.chipSelBg, borderRadius: BorderRadius.circular(size * .27)),
        child: Icon(Icons.apartment_rounded, size: size * .5, color: pal.chipSelFg),
      );
    }
    // Tên riêng ở cuối họ tên; bỏ phần mô tả sau dấu gạch ("Chị Bích – chủ nhà Ecopark").
    final words = name.split(RegExp(r'\s[–-]\s')).first.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initial = words.isEmpty ? '?' : words.last.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: pal.avatarBg, shape: BoxShape.circle),
      child: Text(initial, style: TextStyle(fontSize: size * .38, fontWeight: FontWeight.w600, color: pal.avatarFg)),
    );
  }
}

/// Dòng phụ dưới tên trong danh sách: MST · địa chỉ · số người (công ty) / chức danh – công ty · SĐT (người).
String contactSubtitle(Map c) {
  final parts = <String>[];
  if (c['kind'] == 'company') {
    if ('${c['tax_id'] ?? ''}'.isNotEmpty) parts.add('MST ${c['tax_id']}');
    final addr = '${c['address'] ?? ''}';
    if (addr.isNotEmpty) parts.add(addr.split(',').last.trim());
    if ('${c['country'] ?? ''}'.isNotEmpty) parts.add('${c['country']}');
    final n = (c['people_count'] as num?)?.toInt() ?? 0;
    if (n > 0) parts.add(tr('{0} người liên hệ', [n]));
    if (parts.isEmpty && '${c['phone'] ?? ''}'.isNotEmpty) parts.add('${c['phone']}');
  } else {
    final comps = (c['companies'] as List? ?? const []).where((x) => x['left'] != true).map((x) => '${x['name']}').toList();
    final job = '${c['job_title'] ?? ''}';
    if (job.isNotEmpty || comps.isNotEmpty) parts.add([job, comps.join(', ')].where((s) => s.isNotEmpty).join(' – '));
    if (comps.isEmpty && job.isEmpty) parts.add(tr('Khách lẻ'));
    if ('${c['phone'] ?? ''}'.isNotEmpty) parts.add('${c['phone']}');
  }
  return parts.join(' · ');
}

String ownerLine(Map c) {
  final o = c['owner'] as Map? ?? const {};
  final name = '${o['name'] ?? ''}';
  if (c['scope'] == 'company') return tr('Toàn công ty');
  if (c['scope'] == 'private') return name.isEmpty ? tr('Riêng tôi') : name;
  final dept = '${c['dept_name'] ?? ''}';
  return dept.isEmpty ? name : '$name · $dept';
}

class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.c, this.onTap, this.selected = false});
  final Map c;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final types = (c['types'] as List? ?? const []).map((e) => '$e').toList();
    final inactive = (c['owner'] as Map?)?['inactive'] == true;
    return Material(
      color: selected ? pal.chipSelBg.withValues(alpha: .6) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(children: [
            ContactIcon(kind: '${c['kind']}', name: '${c['name']}'),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 11, 16, 11),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: pal.divider, width: .6))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: pal.text)),
                      const SizedBox(height: 2),
                      Text(contactSubtitle(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: pal.sub)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (types.isNotEmpty) TypeChip(types.first),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: Text(ownerLine(c), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: inactive ? const Color(0xFFD97706) : pal.sub)),
                    ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Khung trắng bo góc chứa các dòng (như thẻ trong Cài đặt).
class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 4)});
  final List<Widget> children;
  final EdgeInsets padding;
  @override
  // Material (không phải Container có màu): ListTile bên trong vẽ được hiệu ứng bấm.
  Widget build(BuildContext context) => Material(
        color: Pal.of(context).surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Row(children: [
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Pal.of(context).text))),
          ?trailing,
        ]),
      );
}

String shortDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '${two(d.hour)}:${two(d.minute)}';
  return d.year == now.year ? '${two(d.day)}/${two(d.month)}' : '${two(d.day)}/${two(d.month)}/${d.year}';
}

IconData interactionIcon(String k) => switch (k) {
      'call' => Icons.call_rounded,
      'meeting' => Icons.event_rounded,
      'mail' => Icons.mail_outline_rounded,
      'chat' => Icons.chat_bubble_outline_rounded,
      'flow' => Icons.flag_outlined,
      'invoice' => Icons.receipt_long_rounded,
      'payment' => Icons.account_balance_rounded,
      _ => Icons.sticky_note_2_outlined,
    };
