#ifndef RUNNER_REMOTE_INPUT_H_
#define RUNNER_REMOTE_INPUT_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// Điều khiển máy tính từ xa (máy bị điều khiển), kênh "flygo/remote_input" (Dart: lib/remote/rc_native.dart):
//   - screens: các màn hình (điểm ảnh thật trên màn hình ảo; id = chỉ số EnumDisplayDevices như nguồn chụp của WebRTC)
//   - inject: chuột / bàn phím / chữ qua SendInput
//   - showBar / hideBar: thanh đỏ luôn nổi trên cùng + phím tắt dừng (Ctrl+Shift+F12, không được thì Ctrl+Shift+F11)
//   - fullscreen: cửa sổ app toàn màn hình (máy điều khiển)
// Giới hạn của Windows: không gửi được vào cửa sổ chạy quyền quản trị (UIPI), hộp thoại UAC, màn hình khoá
// (secure desktop) và Ctrl+Alt+Del.
class RemoteInput {
 public:
  RemoteInput(flutter::BinaryMessenger* messenger, HWND main_window);
  ~RemoteInput();

 private:
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Inject(const flutter::EncodableList& events);
  std::wstring ShowBar(const std::wstring& text, const std::wstring& stop, const RECT* screen);
  void HideBar();
  void LayoutBar();
  void FireStop();
  void SetFullscreen(bool on);
  static LRESULT CALLBACK BarProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND main_ = nullptr;
  HWND bar_ = nullptr;
  HWND button_ = nullptr;
  HFONT font_ = nullptr;
  HBRUSH red_ = nullptr;
  std::wstring text_;
  std::wstring stop_;
  RECT screen_ = {};
  bool hotkey_ = false;
  // Toàn màn hình: kiểu và vị trí cửa sổ trước đó.
  bool full_ = false;
  LONG_PTR full_style_ = 0;
  WINDOWPLACEMENT full_placement_ = {};
};

#endif  // RUNNER_REMOTE_INPUT_H_
