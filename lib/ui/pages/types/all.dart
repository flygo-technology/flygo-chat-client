import 'builtin.dart';
import 'poll.dart';
import 'discuss.dart';
import 'draw.dart';
import 'notes.dart';
import 'qa.dart';
import 'timer.dart';
import 'whiteboard.dart';
import 'show.dart';

// Mọi loại trang của app. Loại trang mới: thêm tệp types/<loại>.dart có hàm register…() rồi gọi ở đây.
void registerAllPageTypes() {
  registerBuiltinPageTypes();
  registerPollPageType();
  registerQaPageType();
  registerDiscussPageType();
  registerTimerPageType();
  registerDrawPageType();
  registerNotesPageType();
  registerShowPageType();
  registerWhiteboardPageType();
}
