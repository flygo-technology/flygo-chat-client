import 'builtin.dart';
import 'poll.dart';
import 'qa.dart';

// Mọi loại trang của app. Loại trang mới: thêm tệp types/<loại>.dart có hàm register…() rồi gọi ở đây.
void registerAllPageTypes() {
  registerBuiltinPageTypes();
  registerPollPageType();
  registerQaPageType();
}
