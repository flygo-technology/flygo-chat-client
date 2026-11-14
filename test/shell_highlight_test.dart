import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/shell_highlight.dart';

void main() {
  String kinds(String cmd) => shellTokens(cmd).where((t) => t.$1 != ShTok.space).map((t) => '${t.$1.name}:${t.$2}').join(' ');

  test('lệnh, cờ, ống, đường dẫn, chuỗi, biến', () {
    expect(kinds('git -C /srv/app log --oneline | head -3'),
        'command:git flag:-C path:/srv/app text:log flag:--oneline op:| command:head flag:-3');
    expect(kinds('echo "hi \$USER" > out.txt 2>&1'), 'command:echo string:"hi  variable:\$USER string:" op:> path:out.txt op:2>&1');
    expect(kinds('sudo FOO=1 make && ls ~/x # xong'),
        'command:sudo variable:FOO= text:1 command:make op:&& command:ls path:~/x comment:# xong');
  });

  test('từ khoá và \$(…)', () {
    expect(kinds('for f in *.dart; do wc -l \$f; done'),
        'keyword:for text:f keyword:in path:*.dart op:; keyword:do command:wc flag:-l variable:\$f op:; keyword:done');
    expect(kinds('cd \$(git rev-parse --show-toplevel)'), 'command:cd variable:\$(git rev-parse --show-toplevel)');
  });

  test('ghép lại đúng chuỗi gốc', () {
    const s = "find . -name '*.g.dart' -print0 | xargs -0 rm -f; echo \"done: \${N:-0}\"";
    expect(shellTokens(s).map((t) => t.$2).join(), s);
  });
}
