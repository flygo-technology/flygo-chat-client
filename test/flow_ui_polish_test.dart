import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/api/flows_api.dart';
import 'package:flygo_chat/ui/flows/flow_doc.dart';
import 'package:flygo_chat/ui/flows/flow_editor_vars.dart';
import 'package:flygo_chat/ui/flows/flow_icon_picker.dart';
import 'package:flygo_chat/ui/flows/process_list.dart';
import 'package:flygo_chat/ui/theme.dart';

/// Biểu tượng từ khoá thẻ, khoá "_" ẩn, nhãn nhiều dòng (theo Sếp, F1 hoá đơn).
void main() {
  Widget wrap(Widget child) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Builder(builder: (c) => child)));

  testWidgets('từ khoá "invoice" vẽ thành hình, không phải chữ; emoji vẫn là chữ', (t) async {
    final p = FlowProcess.fromJson({'id': 'P-1', 'name': 'VINA VAT · FSD', 'icon': 'invoice'});
    await t.pumpWidget(wrap(Builder(builder: (c) => processIconBox(Pal.of(c), p))));
    expect(find.text('invoice'), findsNothing);
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
    await t.pumpWidget(wrap(flowIconView('🧾')));
    expect(find.text('🧾'), findsOneWidget);
  });

  testWidgets('chọn biểu tượng cho tiến trình có nhóm biểu tượng thẻ', (t) async {
    String? picked;
    await t.pumpWidget(wrap(Builder(builder: (c) => TextButton(onPressed: () async => picked = await pickFlowIcon(c, keywords: true), child: const Text('mở')))));
    await t.tap(find.text('mở'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('icon-kw-invoice')));
    await t.pumpAndSettle();
    expect(picked, 'invoice');
  });

  test('khoá "_" không hiện: thuộc tính, thống kê; chọn thông tin xếp vào nhóm Ẩn', () {
    final p = FlowProcess.fromJson({
      'id': 'P-1',
      'props': {'so': '15', '_key_api': 'LQF:x', '_chung_tu': [1, 2]},
      'stats': [{'key': 'tien', 'label': 'Tiền', 'value': 1}, {'key': '_loi_lan', 'label': 'Lần lỗi', 'value': 2}],
    });
    expect(p.props.keys, ['so']);
    expect(p.stats.map((s) => s['key']), ['tien']);
    final s = FlowDoc.make('process_create') as FStep;
    s.node['props'] = {'so': '', '_key_api': ''};
    final vars = processVars([s]);
    final so = vars.firstWhere((v) => v.path == 'process.props.so');
    final hid = vars.firstWhere((v) => v.path == 'process.props._key_api');
    expect(so.label, contains('Thuộc tính'));
    expect(hid.label, contains('Ẩn'));
    expect(vars.indexOf(hid) > vars.indexOf(so), isTrue);
  });
}
