import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';

/// Điều kiện dựng bằng giao diện: nhóm VÀ, giữa nhóm là HOẶC; đổi qua lại với biểu thức máy chủ.
void main() {
  const vars = [
    CondVar('form.so_tien', 'Số tiền', 'money'),
    CondVar('form.loai', 'Loại chi', 'select', ['Mua vật tư', 'Dịch vụ', 'Khác']),
    CondVar('steps.ai_kiem.output.khop', 'AI kiểm chứng từ › khop', 'bool'),
    CondVar('form.ngay', 'Ngày', 'date'),
  ];

  test('dựng biểu thức và đọc lại', () {
    final g = [
      [CondTerm('form.so_tien', '>', 20000000), CondTerm('form.loai', '==', 'Mua vật tư')],
      [CondTerm('steps.ai_kiem.output.khop', '==', false)],
    ];
    final e = condToExpr(g);
    expect(e, '(form.so_tien > 20000000 and form.loai == "Mua vật tư") or steps.ai_kiem.output.khop == false');
    final back = condFromExpr(e)!;
    expect(back.length, 2);
    expect(back[0].map((t) => '${t.path} ${t.op} ${t.value}'), ['form.so_tien > 20000000', 'form.loai == Mua vật tư']);
    expect(condToExpr(back), e);
    expect(condLabel(e, vars), '(Số tiền lớn hơn 20.000.000 đ và Loại chi là Mua vật tư) hoặc AI kiểm chứng từ › khop là Không');
  });

  test('là một trong, ngày, viết tắt của bot', () {
    final e = condToExpr([[CondTerm('form.loai', 'in', ['Dịch vụ', 'Khác']), CondTerm('form.ngay', '<', '2026-12-01')]]);
    expect(e, 'form.loai in ["Dịch vụ", "Khác"] and form.ngay < "2026-12-01"');
    expect(condLabel(e, vars), 'Loại chi là một trong Dịch vụ, Khác và Ngày trước ngày 01/12/2026');
    // Bot hay viết "&&", biến bool trần, not.
    final g = condFromExpr("form.so_tien >= 5000000 && steps.ai_kiem.output.khop || not steps.ai_kiem.output.khop")!;
    expect(g.map((x) => x.length), [2, 1]);
    expect(g[0][1].value, true);
    expect(g[1][0].value, false);
  });

  test('biểu thức ngoài khuôn: null (giao diện cho làm lại)', () {
    expect(condFromExpr('not (form.a > 1 or form.b < 2)'), isNull);
    expect(condFromExpr('form.a >> 1'), isNull);
    expect(condFromExpr('hash(form.a) != form.b'), isNull);
    expect(condFromExpr(''), isEmpty);
    // Không dựng được bằng giao diện: hiện chính biểu thức, thông tin thành «tên».
    expect(condLabel('hash(form.a) != form.b', vars), contains('«form.a»'));
  });

  test('so hai thông tin với nhau: dựng bằng giao diện, đọc thành câu, tính được', () {
    const e = 'steps.lp.output.hop_le == false and process.props.loi_hash != steps.lp.output.loi_hash';
    final g = condFromExpr(e)!;
    expect(g.single.length, 2);
    expect(g.single[1].value, const CondRef('steps.lp.output.loi_hash'));
    expect(condToExpr(g), e);
    const vs = [
      CondVar('steps.lp.output.hop_le', 'Lập payload hoá đơn › Hợp lệ', 'bool'),
      CondVar('steps.lp.output.loi_hash', 'Lập payload hoá đơn › loi_hash', 'text'),
      CondVar('process.props.loi_hash', 'Tiến trình › Thuộc tính › loi_hash', 'text'),
    ];
    expect(condLabel(e, vs), 'Lập payload hoá đơn › Hợp lệ là Không và Tiến trình › Thuộc tính › loi_hash khác Lập payload hoá đơn › loi_hash');
    expect(condFromExpr('form.a > form.b')!.single.single.value, const CondRef('form.b'));
  });

  test('nội dung: [Số tiền] <-> {{form.so_tien}}', () {
    const raw = 'Đối chiếu {{form.so_tien}} đ, khớp: {{ steps.ai_kiem.output.khop }}';
    final shown = templateToDisplay(raw, vars);
    expect(shown, 'Đối chiếu [Số tiền] đ, khớp: [AI kiểm chứng từ › khop]');
    expect(templateFromDisplay(shown, vars), 'Đối chiếu {{form.so_tien}} đ, khớp: {{steps.ai_kiem.output.khop}}');
  });
}
