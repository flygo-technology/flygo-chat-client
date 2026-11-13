import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor.dart';

void main() {
  final doc = FlowDoc.fromJson(jsonDecode(File('test/fixtures/flows/tai-chung-tu-ngan-hang.json').readAsStringSync()) as Map<String, dynamic>);
  Map tool(String name, Map<String, dynamic> props) => {'name': name, 'output_schema': {'type': 'object', 'properties': props}};
  final integ = {
    'mcp': [
      {
        'name': 'acb',
        'tools': [
          tool('acb-list-month-transactions', {'total': {'type': 'integer', 'title': 'Tổng số giao dịch'}, 'credit_count': {'type': 'integer'}}),
          tool('acb-get-month-advices-job', {
            'status': {'type': 'string', 'description': 'Trạng thái việc tải. Một trong queued, running...'},
            'result': {
              'type': 'object',
              'properties': {'download_url': {'type': 'string', 'title': 'Đường dẫn tải'}},
            },
          }),
        ],
      },
    ],
  };

  test('đường dẫn biến → tên khai báo (trường, biến tính toán, thuộc tính của tool)', () {
    expect(flowVarLabel('form.ngan_hang', doc), 'Ngân hàng');
    expect(flowVarLabel('steps.chuan_bi.output.server', doc), 'Chuẩn bị tham số › Máy chủ MCP');
    expect(flowVarLabel('steps.dem.output.total', doc, integ: integ), 'Đếm giao dịch trong tháng › Tổng số giao dịch');
    // Không có title / mô tả: tên trường của khuôn tool.
    expect(flowVarLabel('steps.dem.output.credit_count', doc, integ: integ), 'Đếm giao dịch trong tháng › credit_count');
    expect(flowVarLabel('steps.cho.output.result.result.download_url', doc, integ: integ), 'Chờ ngân hàng tải xong › Kết quả › result › Đường dẫn tải');
    expect(flowVarLabel('steps.cho.output.result.status', doc, integ: integ), 'Chờ ngân hàng tải xong › Kết quả › Trạng thái việc tải');
    expect(flowVarLabel('requester', doc), 'Người tạo tiến trình');
  });

  test('hiển thị: điều kiện và chuỗi có chèn biến không còn đường dẫn thô / ngoặc nhọn', () {
    final vars = labelledVars(doc, flowVars(doc), integ);
    final cond = condLabel('steps.dem.output.total >= 0', vars);
    expect(cond, startsWith('Đếm giao dịch trong tháng › Tổng số giao dịch'));
    expect(cond, isNot(contains('steps.')));
    final shown = humanTemplate('Đang lấy danh sách giao dịch {{form.ngan_hang}} tháng {{steps.chuan_bi.output.thang}}', vars, doc, integ: integ);
    expect(shown, 'Đang lấy danh sách giao dịch «Ngân hàng» tháng «Chuẩn bị tham số › Tháng (số)»');
    expect(humanTemplate('{{steps.chuan_bi.output.server}} › x', vars, doc), '«Chuẩn bị tham số › Máy chủ MCP» › x');
  });
}
