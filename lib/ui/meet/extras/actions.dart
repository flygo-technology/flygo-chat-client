import 'package:flutter/material.dart';

import '../../../calls/call_service.dart';

// Tính năng thêm của Họp (module riêng, vd. giơ tay xếp hàng, hỏi đáp, bảng trắng): mỗi tính năng thêm một mục vào menu
// của màn hình họp ở đây; màn hình họp chỉ đọc danh sách này, không cần sửa call_screen.dart.

class MeetExtraAction {
  final String id;
  final IconData icon;
  final String label;
  final bool on;
  final Future<void> Function(BuildContext context, CallService call) run;
  const MeetExtraAction({required this.id, required this.icon, required this.label, required this.run, this.on = false});
}

/// Các mục thêm cho menu cuộc họp hiện tại (rỗng khi chưa có tính năng nào).
List<MeetExtraAction> meetExtraActions(BuildContext context, CallService call) => const [];
