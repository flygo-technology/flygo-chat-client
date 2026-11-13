import 'package:flutter/material.dart';
import '../../i18n/i18n.dart';
import '../theme.dart';

/// Quy trình "Thử nghiệm": hiện cho mọi người nhưng chưa cho bắt đầu (máy chủ cũng từ chối, 409).
String flowExperimentalMsg() => tr('Quy trình đang thử nghiệm, chưa chạy được.');

/// Bấm vào quy trình thử nghiệm: báo chưa chạy được.
void showFlowExperimental(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(toast(Text(flowExperimentalMsg()), icon: Icons.science_outlined));

/// Nhãn nhỏ "Thử nghiệm" (viên thuốc màu hổ phách) cạnh tên quy trình.
class FlowExperimentalBadge extends StatelessWidget {
  final bool small;
  const FlowExperimentalBadge({super.key, this.small = false});

  static const amber = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? const Color(0xFFFBBF24) : amber;
    return Tooltip(
      message: flowExperimentalMsg(),
      child: Container(
        key: const ValueKey('flow-experimental-badge'),
        padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
        decoration: BoxDecoration(
          // Nền đặc (không trong suốt) để nhãn vẫn đọc được khi Trang chủ có hình nền.
          color: dark ? const Color(0xFF3B2A0C) : const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: fg.withValues(alpha: .45)),
        ),
        child: Text(tr('Thử nghiệm'), maxLines: 1, style: TextStyle(fontSize: small ? 10.5 : 11.5, fontWeight: FontWeight.w700, color: fg, height: 1.3)),
      ),
    );
  }
}
