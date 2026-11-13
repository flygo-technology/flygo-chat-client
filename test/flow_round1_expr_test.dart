import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/flows/flow_cond.dart';
import 'package:flygo_chat/ui/flows/flow_editor_expr.dart';

/// Ngôn ngữ biểu thức (như `flows_engine::expr`): phép tính, hàm, tên biến có "-", kiểm nhanh với lỗi tiếng Việt,
/// tính `show_if` trên app, chữ đọc được, số chứng từ.
void main() {
  Object? ev(String src, [Map<String, dynamic> ctx = const {}]) => evalExpr(parseExpr(src), ctx);

  setUp(() => exprNow = () => DateTime.utc(2026, 11, 8, 3, 30)); // 10:30 giờ VN, Chủ nhật.
  tearDown(() => exprNow = DateTime.now);

  test('phép tính, ưu tiên, dấu trừ đứng trước, chia cho 0, nối chuỗi', () {
    expect(ev('1 + 2 * 3'), 7);
    expect(ev('(1 + 2) * 3'), 9);
    expect(ev('-2 * 3'), -6);
    expect(ev('- form.a', {'form': {'a': 4}}), -4);
    expect(ev('7 % 3'), 1);
    expect(ev('5 / 0'), isNull);
    expect(ev('0.1 + 0.2'), 0.3);
    expect(ev('20_000_000 / 1000'), 20000);
    expect(ev('form.x + 1', {'form': <String, dynamic>{}}), 1, reason: 'ô trống tính là 0');
    expect(ev("form.ten + ' - ' + form.ma", {'form': {'ten': 'Cty A', 'ma': 'KH1'}}), 'Cty A - KH1');
    expect(ev('form.tien * 2', {'form': {'tien': '35.000.000'}}), 70000000, reason: 'chuỗi số tiền đọc được như số');
    expect(ev('form.a > 1 and form.b == "x" or not form.c', {'form': {'a': 2, 'b': 'x'}}), true);
  });

  test('tên biến có "-": phép trừ cần dấu cách', () {
    final ctx = {
      'steps': {
        'de-xuat': {'output': {'x': 10}},
      },
      'form': {'a': 5, 'b': 2},
    };
    expect(ev('steps.de-xuat.output.x - 3', ctx), 7);
    expect(ev('form.a - form.b', ctx), 3);
    expect(ev('form.a-1', ctx), isNull, reason: 'một tên biến lạ "form.a-1"');
    final c = checkExpr('form.a-form.b > 0', known: ['form.a', 'form.b']);
    expect(c.ok, isFalse);
    expect(c.error, contains('form.a - form.b'));
    expect(checkExpr('steps.de-xuat.output.x > 1', known: ['steps.de-xuat.output.x']).ok, isTrue);
  });

  test('hàm: ngày (giờ VN), bảng, chữ, số', () {
    expect(ev('today()'), '2026-11-08');
    expect(ev('now()'), '2026-11-08 10:30');
    expect(ev('days_between("2026-11-01", "2026-11-08")'), 7);
    expect(ev('days_between(form.tu, form.den) + 1', {'form': {'tu': '01/11/2026', 'den': '2026-11-03'}}), 3);
    expect(ev('add_days("2026-12-30", 3)'), '2027-01-02');
    expect(ev('add_workdays("2026-11-06", 1)'), '2026-11-09', reason: 'thứ Sáu + 1 ngày làm việc = thứ Hai');
    expect(ev('add_workdays("2026-11-09", -1)'), '2026-11-06');
    expect(ev('year("2026-11-08")'), 2026);
    expect(ev('month("2026-11-08")'), 11);
    final hang = {
      'form': {
        'hang': [
          {'so_luong': 2, 'thanh_tien': 100},
          {'so_luong': 20, 'thanh_tien': 300},
          {'so_luong': 0, 'thanh_tien': 0},
        ],
      },
    };
    expect(ev('sum(form.hang, "thanh_tien")', hang), 400);
    expect(ev('sum(form.hang, "thanh_tien", item.so_luong > 10)', hang), 300);
    expect(ev('count(form.hang)', hang), 3);
    expect(ev('count(form.hang, item.so_luong > 10)', hang), 1);
    expect(ev('len(form.hang)', hang), 3);
    expect(ev('len("abc")'), 3);
    expect(ev('contains(lower("Mua VẬT TƯ"), "vật")'), true);
    expect(ev('contains([1, 2], 2)'), true);
    expect(ev('empty("  ")'), true);
    expect(ev('upper("ab")'), 'AB');
    expect(ev('round(1234.567, 1)'), 1234.6);
    expect(ev('round(1234567, -3)'), 1235000);
    expect(ev('min(3, 1, 2)'), 1);
    expect(ev('max([4, 9, 2])'), 9);
    expect(ev('abs(-5)'), 5);
    expect(ev('if(form.a > 1, "lớn", "nhỏ")', {'form': {'a': 2}}), 'lớn');
  });

  test('lỗi tiếng Việt: hàm lạ, sai số tham số, thiếu ngoặc, dùng && / = / !', () {
    String? err(String s) => checkExpr(s).error;
    expect(err('foo(1)'), 'Không có hàm "foo"');
    expect(err('round()'), 'Hàm round cần 1–2 tham số (đang có 0)');
    expect(err('days_between(form.a)'), 'Hàm days_between cần 2 tham số (đang có 1)');
    expect(err('(form.a > 1'), 'Thiếu dấu ")"');
    expect(err('form.a > 1 && form.b'), 'Dùng "and" thay cho "&&"');
    expect(err('form.a = 1'), contains('=='));
    expect(err('!form.a'), 'Dùng "not" thay cho "!"');
    expect(err('form.a >'), contains('còn thiếu'));
    expect(err("form.a == 'x"), contains('nháy'));
    expect(err('form.a form.b'), contains('Thừa'));
    expect(err(''), 'Chưa có biểu thức');
    // Thông tin lạ: tên không thuộc nhóm nào là lỗi (thường do quên dấu nháy), thuộc nhóm thì chỉ cảnh báo.
    expect(checkExpr('form.loai == Mua', known: ['form.loai']).error, contains('Mua'));
    final w = checkExpr('form.khong_co > 1', known: ['form.so_tien']);
    expect(w.ok, isTrue);
    expect(w.warning, contains('form.khong_co'));
    expect(checkExpr('form.so_tien > 1 and vars.x', known: ['form.so_tien', 'vars.x']).warning, isNull);
    expect(checkExpr('form.vi_tri.lat > 1', known: ['form.vi_tri']).warning, isNull, reason: 'thành phần của thông tin đã biết');
  });

  test('biến dùng trong biểu thức, kiểu kết quả', () {
    expect(exprVars(parseExpr('count(form.hang, item.sl > 1) + vars.x')), ['form.hang', 'vars.x']);
    expect(exprType(parseExpr('round(form.a * 0.08)')), 'number');
    expect(exprType(parseExpr('add_days(form.d, 3)')), 'date');
    expect(exprType(parseExpr('form.a > 1')), 'bool');
    expect(exprType(parseExpr("'PC ' + vars.so")), 'text');
  });

  test('chữ đọc được: thông tin thành «tên», hàm và chữ giữ nguyên', () {
    String label(String p) => {'form.so_tien': 'Số tiền', 'vars.vat': 'Biến › vat'}[p] ?? p;
    expect(exprDisplay('form.so_tien * 1.08 > 50000000', label), '«Số tiền» * 1.08 > 50000000');
    expect(exprDisplay("round(vars.vat) + 'đ' and true", label), "round(«Biến › vat») + 'đ' and true");
    final vars = [const CondVar('form.so_tien', 'Số tiền', 'money')];
    expect(condLabel('form.so_tien * 2 > 10', vars), '«Số tiền» * 2 > 10');
    expect(condLabel('form.so_tien > 10', vars), 'Số tiền lớn hơn 10 đ', reason: 'dạng đơn giản vẫn đọc như cũ');
    expect(condLabel('foo(1)', vars), startsWith('Biểu thức lỗi'));
  });

  test('show_if trên app: biểu thức có phép tính / hàm được tính thật', () {
    final ctx = {
      'form': {'tu': '2026-11-01', 'den': '2026-11-05', 'loai': 'Mua vật tư'},
    };
    expect(condTrue('days_between(form.tu, form.den) + 1 > 3', ctx), isTrue);
    expect(condTrue('days_between(form.tu, form.den) > 10', ctx), isFalse);
    expect(condTrue('contains(lower(form.loai), "vật tư")', ctx), isTrue);
    expect(condTrue('form.loai == "Mua vật tư"', ctx), isTrue);
    expect(condTrue('foo(', ctx), isTrue, reason: 'sai cú pháp: vẫn hiện trường');
    // Rẽ nhánh dựng bằng giao diện đọc được tên biến có "-".
    final g = condFromExpr('steps.de-xuat.output.x > 1')!;
    expect(g.single.single.path, 'steps.de-xuat.output.x');
  });

  test('số chứng từ: xem trước theo dạng, chu kỳ đặt lại theo dạng', () {
    expect(numberPreview('PC-{yyyy}-{0000}'), 'PC-2026-0001');
    expect(numberPreview('PC-{yy}{mm}/{000}', n: 12), 'PC-2611/012');
    expect(numberPreview('HD{dd}-{n}', n: 7), 'HD08-7');
    expect(numberPreview('PC-{yyyy}-'), 'PC-2026-1', reason: 'không có chỗ số thì nối ở cuối');
    expect(numberPreview('PC-{{form.don_vi}}-{0000}'), 'PC-«form.don_vi»-0001');
    expect(numberResetOf('PC-{yyyy}-{0000}'), 'year');
    expect(numberResetOf('PC-{yyyy}{mm}-{0000}'), 'month');
    expect(numberResetOf('{dd}{0000}'), 'day');
    expect(numberResetOf('PC-{0000}'), 'never');
  });
}
