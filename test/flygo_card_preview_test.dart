// Ảnh xem trước thẻ chung flygo_card (chạy tay): FCARD_OUT=<thư mục> flutter test test/flygo_card_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/flygo_card.dart';
import 'package:flygo_chat/ui/theme.dart';

Future<void> _fonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/tools/flutter'}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File('$dir/$f');
      if (b.existsSync()) l.addFont(Future.value(ByteData.sublistView(b.readAsBytesSync())));
    }
    await l.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  // Theme Linux dùng 'Noto Sans': nạp Roboto dưới tên đó để chữ không thành ô vuông.
  await load('Noto Sans', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final _demos = <Map<String, dynamic>>[
  {
    'v': 1, 'icon': 'invoice', 'accent': 'blue', 'title': 'Hoá đơn điện tử mới', 'subtitle': 'Ký hiệu 1C26MYX · Số 2154',
    'status': {'label': 'Đã gửi CQT', 'tone': 'green'},
    'hero': {'value': '128.450.000 ₫', 'label': 'Tổng thanh toán (đã gồm VAT 8%)'},
    'fields': [
      {'label': 'Bên bán', 'value': 'CÔNG TY CP THANG MÁY ABC VINA'},
      {'label': 'Bên mua', 'value': 'CÔNG TY TNHH XÂY DỰNG HOÀNG LONG'},
      {'label': 'MST bên mua', 'value': '0109876543', 'kind': 'copy'},
      {'label': 'Ngày lập', 'value': '07/11/2026'},
      {'label': 'Mã tra cứu', 'value': 'B7K2-9QXD-41MN', 'kind': 'copy'},
    ],
    'actions': [{'label': 'Xem PDF', 'style': 'secondary'}, {'label': 'Tải XML', 'style': 'primary'}],
    'footer': 'Hoá đơn · tự động từ hệ thống kế toán',
  },
  {
    'v': 1, 'icon': 'debt', 'accent': 'orange', 'title': 'Nhắc công nợ quá hạn', 'subtitle': 'Công trình Vinhomes Ocean Park – Toà S2.05',
    'status': {'label': 'Quá hạn 12 ngày', 'tone': 'red'},
    'hero': {'value': '245.000.000 ₫', 'label': 'Còn phải thu', 'tone': 'red'},
    'fields': [
      {'label': 'Khách hàng', 'value': 'CÔNG TY CP ĐẦU TƯ AN PHÁT'},
      {'label': 'Hợp đồng', 'value': 'HĐ 0123/2026/DND', 'kind': 'copy'},
      {'label': 'Hạn thanh toán', 'value': '26/10/2026', 'tone': 'red'},
      {'label': 'Phụ trách', 'value': 'Nguyễn Văn Diệp'},
      {'label': 'Điện thoại', 'value': '0912 345 678', 'kind': 'phone'},
    ],
    'progress': {'value': .65, 'label': 'Đã thu 455 / 700 triệu (65%)'},
    'actions': [{'label': 'Đã gọi KH', 'style': 'secondary'}, {'label': 'Gửi nhắc nợ', 'style': 'primary'}],
  },
  {
    'v': 1, 'icon': 'incident', 'accent': 'red', 'title': 'Sự cố thang máy – kẹt người', 'subtitle': 'Mã thang TM-HN-0417 · Chung cư Golden Park',
    'status': {'label': 'Khẩn cấp', 'tone': 'red'},
    'fields': [
      {'label': 'Địa chỉ', 'value': 'Số 2 Phạm Văn Bạch, Cầu Giấy, Hà Nội'},
      {'label': 'Vị trí', 'value': 'Thang số 2 · dừng giữa tầng 7–8'},
      {'label': 'Báo lúc', 'value': '15:42 · 07/11/2026 (8 phút trước)'},
      {'label': 'Người báo', 'value': 'Bảo vệ toà nhà · 0988 112 233', 'kind': 'phone'},
      {'label': 'KTV gần nhất', 'value': 'Trần Quang Huy · cách 2,1 km'},
    ],
    'note': 'Có 2 người trong cabin, đã liên lạc qua intercom, đèn cứu hộ hoạt động.',
    'actions': [{'label': 'Chỉ đường', 'style': 'secondary'}, {'label': 'Nhận việc', 'style': 'primary'}],
    'footer': 'Phiếu sự cố #SC-26-1187',
  },
  {
    'v': 1, 'icon': 'sign', 'accent': 'purple', 'title': 'Hợp đồng chờ ký số', 'subtitle': 'HĐ bảo trì thang máy năm 2027 – Toà A1',
    'status': {'label': 'Chờ bạn ký', 'tone': 'orange'},
    'items': {
      'title': 'Người ký',
      'rows': [
        {'title': 'Phạm Thị Lan', 'sub': 'Kế toán trưởng · 09:12 hôm nay', 'value': 'Đã ký', 'tone': 'green'},
        {'title': 'Trần Văn Bình', 'sub': 'Giám đốc', 'value': 'Chờ ký', 'tone': 'orange'},
        {'title': 'Đại diện bên B', 'sub': 'CÔNG TY TNHH QUẢN LÝ TOÀ NHÀ A1', 'value': 'Chưa tới lượt', 'tone': 'gray'},
      ],
    },
    'progress': {'value': 1 / 3, 'label': '1/3 chữ ký · hạn chót 10/11/2026'},
    'actions': [{'label': 'Xem văn bản', 'style': 'secondary'}, {'label': 'Ký ngay', 'style': 'primary'}],
  },
  {
    'v': 1, 'icon': 'report', 'accent': 'green', 'title': 'Báo cáo kinh doanh ngày 07/11', 'subtitle': 'ABC Vina · tự gửi lúc 18:00',
    'stats': [
      {'label': 'Doanh thu', 'value': '1,26 tỷ', 'delta': '18%', 'trend': 'up', 'tone': 'green'},
      {'label': 'Thu tiền về', 'value': '502 tr', 'delta': '4%', 'trend': 'up', 'tone': 'green'},
      {'label': 'Đơn hàng mới', 'value': '7', 'delta': '2', 'trend': 'down', 'tone': 'red'},
      {'label': 'Sự cố mở', 'value': '3', 'delta': '0', 'tone': 'gray'},
    ],
    'items': {
      'title': 'Top nhân viên',
      'rows': [
        {'title': 'Nguyễn Văn Diệp', 'sub': '3 hợp đồng', 'value': '620 tr'},
        {'title': 'Lê Thị Mai', 'sub': '2 hợp đồng', 'value': '410 tr'},
      ],
    },
    'actions': [{'label': 'Mở báo cáo đầy đủ', 'style': 'primary'}],
  },
  {
    'v': 1, 'icon': 'order', 'accent': 'blue', 'title': 'Đơn đặt hàng linh kiện', 'subtitle': 'PO-26-0331 · Nhà cung cấp Fuji Elevator',
    'status': {'label': 'Chờ duyệt', 'tone': 'orange'},
    'items': {
      'title': 'Mặt hàng',
      'rows': [
        {'title': 'Bo mạch điều khiển MCB-3000', 'sub': 'SL 4 × 8.500.000', 'value': '34.000.000'},
        {'title': 'Cáp tải 10mm (cuộn 200m)', 'sub': 'SL 2 × 12.300.000', 'value': '24.600.000'},
        {'title': 'Nút gọi tầng inox', 'sub': 'SL 30 × 350.000', 'value': '10.500.000'},
      ],
    },
    'hero': {'value': '69.100.000 ₫', 'label': 'Tổng giá trị đơn'},
    'fields': [
      {'label': 'Giao dự kiến', 'value': '15/11/2026 · Kho Hà Đông'},
      {'label': 'Người đề xuất', 'value': 'Trần Quang Huy'},
    ],
    'actions': [{'label': 'Từ chối', 'style': 'secondary'}, {'label': 'Duyệt', 'style': 'primary'}],
  },
];

final _stepDemos = <Map<String, dynamic>>[
  {
    'v': 1, 'icon': 'task', 'accent': 'blue', 'title': 'Phiếu bảo trì #BT-26-0912', 'subtitle': 'Thang TM-HN-0417 · Chung cư Golden Park',
    'status': {'label': 'Đang xử lý', 'tone': 'blue'},
    'steps': {
      'title': 'Tiến độ công việc',
      'rows': [
        {'title': 'Tiếp nhận yêu cầu', 'state': 'done', 'sub': 'Lan CSKH · 08:05'},
        {'title': 'Phân công kỹ thuật viên', 'state': 'done', 'sub': 'Trần Quang Huy · 08:20'},
        {'title': 'Kiểm tra tại công trình', 'state': 'active', 'sub': 'Huy · bắt đầu 09:10', 'note': 'Phanh cabin mòn, cần thay má phanh. Đang chờ vật tư từ kho Hà Đông.'},
        {'title': 'Thay thế linh kiện', 'state': 'pending'},
        {'title': 'Nghiệm thu với khách hàng', 'state': 'pending'},
      ],
    },
    'progress': {'value': .5, 'label': 'Bước 3/5 · hạn hoàn thành 17:00 hôm nay'},
    'actions': [{'label': 'Báo vướng mắc', 'id': 'blocked'}, {'label': 'Xong bước này', 'style': 'primary', 'id': 'next'}],
  },
  {
    'v': 1, 'icon': 'order', 'accent': 'purple', 'title': 'Duyệt đề nghị thanh toán', 'subtitle': 'ĐNTT-26-1104 · 69.100.000 ₫ · Fuji Elevator',
    'status': {'label': 'Bị trả lại', 'tone': 'red'},
    'steps': {
      'rows': [
        {'title': 'Lập đề nghị', 'state': 'done', 'sub': 'Trần Quang Huy · 06/11 14:02'},
        {'title': 'Trưởng phòng kỹ thuật duyệt', 'state': 'done', 'sub': 'Nguyễn Văn Đăng · 06/11 16:30'},
        {'title': 'Kế toán kiểm tra chứng từ', 'state': 'failed', 'sub': 'Phạm Thị Lan · 07/11 09:12', 'note': 'Thiếu hoá đơn VAT của lô cáp tải. Bổ sung rồi gửi lại.'},
        {'title': 'Giám đốc duyệt', 'state': 'pending'},
        {'title': 'Chi tiền', 'state': 'skipped'},
      ],
    },
    'actions': [{'label': 'Xem chứng từ', 'url': 'https://example.com'}, {'label': 'Gửi lại', 'style': 'primary', 'id': 'resubmit'}],
  },
];

void main() {
  final out = Platform.environment['FCARD_OUT'];

  Future<void> shot(WidgetTester tester, String name, Brightness b, List<Map<String, dynamic>> cards) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(b),
      home: Builder(builder: (c) {
        return Scaffold(
          backgroundColor: Pal.of(c).chatBg,
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Pal.of(c).chatBg,
                padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final m in cards) ...[FlygoCard(data: FlygoCardData.tryParse(m)!, width: 340), const SizedBox(height: 16)],
                ]),
              ),
            ),
          ),
        );
      }),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('ảnh xem trước thẻ chung', (tester) async {
    if (out == null) return;
    await tester.runAsync(_fonts);
    for (final b in Brightness.values) {
      for (var i = 0; i < _demos.length; i += 2) {
        await shot(tester, 'fcard-${i ~/ 2 + 1}-${b.name}', b, _demos.sublist(i, i + 2));
      }
      await shot(tester, 'fcard-steps-${b.name}', b, _stepDemos);
    }
  });
}
