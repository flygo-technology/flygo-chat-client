import 'dart:io';
import '../i18n/i18n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// Link (có hoặc không có http) và số điện thoại Việt Nam / quốc tế, cho phép
/// khoảng trắng, dấu chấm, gạch ngang giữa các số: "0912 345 678", "+84 912.345.678".
final linkRe = RegExp(
  r'(https?://[^\s<>()`]+|www\.[^\s<>()`]+)'
  r'|((?<![\w+])(?:\+84|\+\d{2}|0)(?:[ .\-]?\d){8,10}(?![\w]))',
  caseSensitive: false,
);

/// Địa chỉ email (mở bằng mailto:).
const _emailPat = r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}';
// Chữ thường: link / số điện thoại như [linkRe], thêm email (nhóm 3).
final _linkOrEmailRe = RegExp('${linkRe.pattern}|($_emailPat)', caseSensitive: false);
// Trong mã nội dòng (`...`): chỉ link http / www và email (không bắt số điện thoại trong mã).
final _codeLinkRe = RegExp('(https?://[^\\s<>()`]+|www\\.[^\\s<>()`]+)|($_emailPat)', caseSensitive: false);

class FoundLink {
  final String text;
  final bool isPhone;
  final bool isEmail;
  const FoundLink(this.text, this.isPhone, {this.isEmail = false});

  /// Số chỉ còn chữ số (giữ dấu +) để gọi.
  String get dial => text.replaceAll(RegExp(r'[^\d+]'), '');
  /// Chữ để sao chép: số điện thoại chỉ còn chữ số, email không kèm "mailto:", link đầy đủ.
  String get copyText => isPhone ? dial : (isEmail ? text : uri.toString());
  Uri get uri => isPhone
      ? Uri(scheme: 'tel', path: dial)
      : isEmail
      ? Uri(scheme: 'mailto', path: text)
      : text.startsWith('/') || text.startsWith('~/')
          // Đường dẫn tệp trên máy (bot AI thường gửi kiểu này).
          ? Uri.file(text.startsWith('~/') ? '${Platform.environment['HOME'] ?? ''}${text.substring(1)}' : text)
          : Uri.parse(text.toLowerCase().startsWith('www.') ? 'https://$text' : _trimPunct(text));

  Future<void> open() async {
    // Link nội bộ của app (vd. thẻ Boards của máy chủ đang dùng): mở ngay trong app nếu có nơi nhận.
    if (internalLinkHook?.call(uri) == true) return;
    await openInSystem(uri);
  }
}

/// Mở link bằng ứng dụng mặc định của hệ thống (trình duyệt cho http/https). Nếu url_launcher không mở được
/// (gặp trên một số máy Windows / Linux), gọi thẳng lệnh của hệ điều hành (Sếp, 2026-11-19: user không mở được link).
Future<bool> openInSystem(Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
  } catch (_) {}
  final s = uri.toString();
  try {
    if (Platform.isWindows) {
      // rundll32 không qua cmd nên ký tự & trong link không bị cắt.
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', s], mode: ProcessStartMode.detached);
      return true;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [s], mode: ProcessStartMode.detached);
      return true;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [s], mode: ProcessStartMode.detached);
      return true;
    }
  } catch (_) {}
  return false;
}

/// Màn hình chính đặt hook này: trả về true nếu đã tự mở link (không mở trình duyệt).
bool Function(Uri uri)? internalLinkHook;

String _trimPunct(String s) => s.replaceFirst(RegExp(r'[.,;:!?]+$'), '');

/// Link và số điện thoại trong một tin (không trùng, theo thứ tự xuất hiện).
List<FoundLink> findLinks(String text) {
  final seen = <String>{};
  final out = <FoundLink>[];
  for (final m in linkRe.allMatches(text)) {
    final phone = m.group(2) != null;
    final t = phone ? m.group(2)!.trim() : _trimPunct(m.group(1)!);
    final key = phone ? t.replaceAll(RegExp(r'\D'), '') : t;
    if (seen.add(key)) out.add(FoundLink(t, phone));
  }
  return out;
}

/// Chia chữ thành các đoạn: link / số điện thoại / email bấm được, phần còn lại qua [plain].
List<InlineSpan> linkSpans(String text, Pal pal, List<InlineSpan> Function(String) plain) {
  final spans = <InlineSpan>[];
  var i = 0;
  for (final m in _linkOrEmailRe.allMatches(text)) {
    final raw = m.group(0)!;
    final phone = m.group(2) != null;
    final email = m.group(3) != null;
    final t = phone ? raw : _trimPunct(raw);
    if (m.start > i) spans.addAll(plain(text.substring(i, m.start)));
    final link = FoundLink(phone ? t.trim() : t, phone, isEmail: email);
    spans.add(TextSpan(
      text: t,
      style: TextStyle(color: pal.tick, decoration: TextDecoration.underline, decorationColor: pal.tick),
      mouseCursor: SystemMouseCursors.click,
      recognizer: TapGestureRecognizer()..onTap = link.open,
    ));
    spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: InlineLinkButtons(link: link)));
    i = m.start + t.length;
  }
  if (i < text.length) spans.addAll(plain(text.substring(i)));
  return spans;
}

/// Mã nội dòng (`...`, trợ lý hay bọc link / email trong đó): giữ kiểu chữ mã [code], link http / www và email
/// bấm được (mở bằng ứng dụng của hệ thống), kèm nút sao chép như link thường. Khối code nhiều dòng không dùng hàm này.
List<InlineSpan> codeLinkSpans(String code, TextStyle style, Pal pal) {
  final spans = <InlineSpan>[];
  var i = 0;
  for (final m in _codeLinkRe.allMatches(code)) {
    final t = m.group(2) != null ? m.group(0)! : _trimPunct(m.group(0)!);
    if (m.start > i) spans.add(TextSpan(text: code.substring(i, m.start), style: style));
    final link = FoundLink(t, false, isEmail: m.group(2) != null);
    spans.add(TextSpan(
      text: t,
      style: style.copyWith(color: pal.tick, decoration: TextDecoration.underline, decorationColor: pal.tick),
      mouseCursor: SystemMouseCursors.click,
      recognizer: TapGestureRecognizer()..onTap = link.open,
    ));
    spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: InlineLinkButtons(link: link)));
    i = m.start + t.length;
  }
  if (spans.isEmpty) return [TextSpan(text: code, style: style)];
  if (i < code.length) spans.add(TextSpan(text: code.substring(i), style: style));
  return spans;
}

/// Hai nút nhỏ ngay sau link / số điện thoại: sao chép và mở link / gọi điện.
class InlineLinkButtons extends StatelessWidget {
  final FoundLink link;
  const InlineLinkButtons({super.key, required this.link});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    Widget btn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(3), child: Icon(icon, size: 15, color: pal.tick)),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 3),
      btn(Icons.copy_rounded, link.isPhone || link.isEmail ? tr('Sao chép') : tr('Sao chép link'), () {
        Clipboard.setData(ClipboardData(text: link.copyText));
        ScaffoldMessenger.of(context).showSnackBar(toast(Text(tr('Đã sao chép'))));
      }),
      // Link: bấm vào chữ là mở rồi, không cần nút mở riêng. Số điện thoại vẫn có nút gọi.
      if (link.isPhone) btn(Icons.call_outlined, tr('Gọi điện'), link.open),
    ]);
  }
}

final _mentionRe = RegExp(r'@[a-z0-9._-]+|(?<![\w&])#[\p{L}\p{N}_]+', caseSensitive: false, unicode: true);

/// @tên được tô màu; bấm vào thì gọi [onTap] với tên đăng nhập (không có @).
List<InlineSpan> mentionSpans(String text, Pal pal, void Function(String username)? onTap) {
  final spans = <InlineSpan>[];
  var i = 0;
  for (final m in _mentionRe.allMatches(text)) {
    if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
    if (m.group(0)!.startsWith('#')) {
      // Hashtag: chip nhỏ.
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: pal.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
          child: Text(m.group(0)!, style: TextStyle(fontSize: 13.5, color: pal.tick, fontWeight: FontWeight.w600)),
        ),
      ));
      i = m.end;
      continue;
    }
    final name = m.group(0)!.substring(1).replaceFirst(RegExp(r'[._-]+$'), '');
    spans.add(TextSpan(
      text: m.group(0),
      style: TextStyle(color: pal.tick, fontWeight: FontWeight.w500),
      mouseCursor: onTap == null ? null : SystemMouseCursors.click,
      recognizer: onTap == null ? null : (TapGestureRecognizer()..onTap = () => onTap(name)),
    ));
    i = m.end;
  }
  if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
  return spans;
}
