import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_logic.dart';
import 'package:flygo_chat/ui/flows/flow_table.dart';
import 'package:flygo_chat/ui/theme.dart';

/// Trường kiểu bảng: tự tính + tổng giống máy chủ, kiểm theo dòng, thông tin dùng trong điều kiện, ô nhập.
void main() {
  final def = jsonDecode(File('test/fixtures/flows/don-hang.json').readAsStringSync()) as Map<String, dynamic>;
  final form = FlowField.listOf(def['form']);
  final sp = form.firstWhere((f) => f.key == 'san_pham');

  test('tự tính thành tiền, tổng, tóm tắt', () {
    final (rows, totals) = computeTable(sp, [
      {'ten': 'Cáp tải', 'so_luong': 3, 'don_gia': 1500000, 'thanh_tien': 1},
      {'ten': 'Biến tần', 'so_luong': '2', 'don_gia': '12.000.000'},
    ]);
    expect(rows[0]['thanh_tien'], 4500000, reason: 'tính lại, bỏ giá trị gửi lên');
    expect(rows[1]['thanh_tien'], 24000000);
    expect(totals, {'so_luong': 5, 'don_gia': 13500000, 'thanh_tien': 28500000});
    expect(showFieldValue(sp, rows), '2 dòng · tổng thành tiền 28.500.000 đ');
  });

  test('kiểm form theo dòng', () {
    expect(validateFlowForm([sp], {'san_pham': []})['san_pham'], 'Chưa nhập');
    expect(validateFlowForm([sp], {
      'san_pham': [
        {'ten': 'A', 'so_luong': 1, 'don_gia': 5},
        {'ten': 'B', 'don_gia': 5},
      ],
    })['san_pham'], 'Dòng 2: Số lượng: Chưa nhập');
    expect(validateFlowForm([sp], {'san_pham': [{'ten': 'A', 'so_luong': 1, 'don_gia': 5}]}), isEmpty);
  });

  test('điều kiện dùng số dòng và tổng cột', () {
    final vars = flowVars(FlowDoc.fromJson(def));
    expect(vars.map((v) => v.label), containsAll(['Sản phẩm › Số dòng', 'Sản phẩm › Tổng thành tiền', 'Khách hàng']));
    expect(vars.any((v) => v.path == 'form.san_pham'), isFalse, reason: 'không so sánh cả bảng');
    final cond = (def['nodes'] as List).firstWhere((n) => n['id'] == 'chk')['rules'][0]['if'] as String;
    expect(condLabel(cond, vars), 'Sản phẩm › Tổng thành tiền lớn hơn 50.000.000 đ hoặc Sản phẩm › Số dòng lớn hơn 10');
  });

  testWidgets('ô nhập bảng: thêm dòng, tự tính, tổng', (tester) async {
    // Bề ngang điện thoại: mỗi dòng một thẻ.
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<Map<String, dynamic>>? out;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: FlowTableInput(field: sp, value: null, onChanged: (r) => out = r))),
    ));
    expect(find.text('Dòng 1'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Tên sản phẩm *'), 'Cáp tải');
    await tester.enterText(find.widgetWithText(TextFormField, 'Đơn giá *'), '1500000');
    await tester.pump();
    expect(out!.single, {'ten': 'Cáp tải', 'so_luong': 1, 'don_gia': 1500000});
    expect(find.text('1.500.000 đ'), findsOneWidget, reason: 'thành tiền = 1 × 1.500.000');
    await tester.tap(find.text('Thêm dòng'));
    await tester.pump();
    expect(find.text('Dòng 2'), findsOneWidget);
    expect(out!.length, 2);
  });
}
