#include "remote_input.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <algorithm>
#include <vector>

namespace {

constexpr wchar_t kBarClass[] = L"FlygoRemoteControlBar";
constexpr int kStopButtonId = 1;
constexpr int kHotkeyId = 0x5243;  // "RC"

const flutter::EncodableValue* Field(const flutter::EncodableMap& m, const char* key) {
  auto it = m.find(flutter::EncodableValue(key));
  return it == m.end() ? nullptr : &it->second;
}

double Num(const flutter::EncodableMap& m, const char* key, double fallback = 0) {
  const auto* v = Field(m, key);
  if (!v) return fallback;
  if (const auto* d = std::get_if<double>(v)) return *d;
  if (const auto* i = std::get_if<int32_t>(v)) return *i;
  if (const auto* l = std::get_if<int64_t>(v)) return static_cast<double>(*l);
  return fallback;
}

bool Bool(const flutter::EncodableMap& m, const char* key) {
  const auto* v = Field(m, key);
  const bool* b = v ? std::get_if<bool>(v) : nullptr;
  return b && *b;
}

std::string Str(const flutter::EncodableMap& m, const char* key) {
  const auto* v = Field(m, key);
  const auto* s = v ? std::get_if<std::string>(v) : nullptr;
  return s ? *s : std::string();
}

std::wstring Wide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

std::string Narrow(const std::wstring& w) {
  if (w.empty()) return std::string();
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), s.data(), n, nullptr, nullptr);
  return s;
}

INPUT KeyInput(WORD scan, bool extended, bool down) {
  INPUT in = {};
  in.type = INPUT_KEYBOARD;
  in.ki.wScan = scan;
  in.ki.dwFlags = KEYEVENTF_SCANCODE | (extended ? KEYEVENTF_EXTENDEDKEY : 0) | (down ? 0 : KEYEVENTF_KEYUP);
  return in;
}

INPUT MouseInput(DWORD flags, LONG x = 0, LONG y = 0, DWORD data = 0) {
  INPUT in = {};
  in.type = INPUT_MOUSE;
  in.mi.dx = x;
  in.mi.dy = y;
  in.mi.mouseData = data;
  in.mi.dwFlags = flags;
  return in;
}

}  // namespace

RemoteInput::RemoteInput(flutter::BinaryMessenger* messenger, HWND main_window) : main_(main_window) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "flygo/remote_input", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { Handle(call, std::move(result)); });
}

RemoteInput::~RemoteInput() {
  HideBar();
  if (font_) DeleteObject(font_);
  if (red_) DeleteObject(red_);
  channel_ = nullptr;
}

void RemoteInput::Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (method == "status") {
    flutter::EncodableMap r;
    r[flutter::EncodableValue("accessibility")] = flutter::EncodableValue(true);
    r[flutter::EncodableValue("screen")] = flutter::EncodableValue(true);
    result->Success(flutter::EncodableValue(r));
  } else if (method == "request" || method == "openSettings") {
    result->Success();
  } else if (method == "screens") {
    // Cùng thứ tự / id với nguồn chụp màn hình của WebRTC: chỉ số thiết bị của EnumDisplayDevices (thiết bị đang bật).
    flutter::EncodableList list;
    for (DWORD i = 0;; ++i) {
      DISPLAY_DEVICEW dev = {};
      dev.cb = sizeof(dev);
      if (!EnumDisplayDevicesW(nullptr, i, &dev, 0)) break;
      if (!(dev.StateFlags & DISPLAY_DEVICE_ACTIVE)) continue;
      DEVMODEW mode = {};
      mode.dmSize = sizeof(mode);
      if (!EnumDisplaySettingsExW(dev.DeviceName, ENUM_CURRENT_SETTINGS, &mode, 0)) continue;
      flutter::EncodableMap s;
      s[flutter::EncodableValue("id")] = flutter::EncodableValue(std::to_string(i));
      s[flutter::EncodableValue("name")] = flutter::EncodableValue(Narrow(dev.DeviceString));
      s[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<double>(mode.dmPosition.x));
      s[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<double>(mode.dmPosition.y));
      s[flutter::EncodableValue("w")] = flutter::EncodableValue(static_cast<double>(mode.dmPelsWidth));
      s[flutter::EncodableValue("h")] = flutter::EncodableValue(static_cast<double>(mode.dmPelsHeight));
      s[flutter::EncodableValue("primary")] = flutter::EncodableValue((dev.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0);
      list.push_back(flutter::EncodableValue(s));
    }
    flutter::EncodableMap r;
    r[flutter::EncodableValue("screens")] = flutter::EncodableValue(list);
    r[flutter::EncodableValue("virtual")] = flutter::EncodableValue(flutter::EncodableList{
        flutter::EncodableValue(static_cast<double>(GetSystemMetrics(SM_XVIRTUALSCREEN))),
        flutter::EncodableValue(static_cast<double>(GetSystemMetrics(SM_YVIRTUALSCREEN))),
        flutter::EncodableValue(static_cast<double>(GetSystemMetrics(SM_CXVIRTUALSCREEN))),
        flutter::EncodableValue(static_cast<double>(GetSystemMetrics(SM_CYVIRTUALSCREEN)))});
    result->Success(flutter::EncodableValue(r));
  } else if (method == "inject") {
    const auto* ev = args ? Field(*args, "events") : nullptr;
    const auto* list = ev ? std::get_if<flutter::EncodableList>(ev) : nullptr;
    if (list) Inject(*list);
    result->Success();
  } else if (method == "showBar") {
    RECT rc = {};
    const RECT* screen = nullptr;
    if (args) {
      if (const auto* v = Field(*args, "screen")) {
        if (const auto* l = std::get_if<flutter::EncodableList>(v); l && l->size() == 4) {
          auto n = [&](size_t i) {
            const auto& e = (*l)[i];
            if (const auto* d = std::get_if<double>(&e)) return static_cast<LONG>(*d);
            if (const auto* x = std::get_if<int32_t>(&e)) return static_cast<LONG>(*x);
            return 0L;
          };
          rc = {n(0), n(1), n(0) + n(2), n(1) + n(3)};
          screen = &rc;
        }
      }
    }
    const std::wstring hotkey = ShowBar(args ? Wide(Str(*args, "text")) : L"", args ? Wide(Str(*args, "stop")) : L"Stop", screen);
    result->Success(flutter::EncodableValue(Narrow(hotkey)));
  } else if (method == "hideBar") {
    HideBar();
    result->Success();
  } else if (method == "fullscreen") {
    SetFullscreen(args && Bool(*args, "on"));
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void RemoteInput::Inject(const flutter::EncodableList& events) {
  std::vector<INPUT> inputs;
  for (const auto& e : events) {
    const auto* m = std::get_if<flutter::EncodableMap>(&e);
    if (!m) continue;
    const std::string op = Str(*m, "op");
    const bool has_pos = Field(*m, "x") != nullptr && Field(*m, "y") != nullptr;
    // Toạ độ đã đổi sẵn bên Dart sang 0..65535 trên màn hình ảo.
    const LONG x = static_cast<LONG>(std::clamp(Num(*m, "x"), 0.0, 65535.0));
    const LONG y = static_cast<LONG>(std::clamp(Num(*m, "y"), 0.0, 65535.0));
    if (op == "move") {
      inputs.push_back(MouseInput(MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK, x, y));
    } else if (op == "button") {
      const int b = static_cast<int>(Num(*m, "b"));
      const bool down = Bool(*m, "down");
      DWORD flag = b == 1 ? (down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP)
                 : b == 2 ? (down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP)
                          : (down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP);
      if (has_pos) flag |= MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
      inputs.push_back(MouseInput(flag, has_pos ? x : 0, has_pos ? y : 0));
    } else if (op == "wheel") {
      // dy: nấc WHEEL_DELTA (dương = cuộn lên); dx: dương = cuộn sang trái theo quy ước bên Dart → đảo cho HWHEEL.
      const LONG dy = static_cast<LONG>(Num(*m, "dy"));
      const LONG dx = static_cast<LONG>(Num(*m, "dx"));
      if (dy != 0) inputs.push_back(MouseInput(MOUSEEVENTF_WHEEL, 0, 0, static_cast<DWORD>(dy)));
      if (dx != 0) inputs.push_back(MouseInput(MOUSEEVENTF_HWHEEL, 0, 0, static_cast<DWORD>(-dx)));
    } else if (op == "key") {
      const int code = static_cast<int>(Num(*m, "code"));
      if (code <= 0 || code > 0xE0FF) continue;
      inputs.push_back(KeyInput(static_cast<WORD>(code & 0xFF), (code & 0xE000) == 0xE000, Bool(*m, "down")));
    } else if (op == "text") {
      const std::wstring s = Wide(Str(*m, "s"));
      for (wchar_t c : s) {
        if (c == L'\n') {
          inputs.push_back(KeyInput(0x1C, false, true));
          inputs.push_back(KeyInput(0x1C, false, false));
          continue;
        }
        if (c == L'\t') {
          inputs.push_back(KeyInput(0x0F, false, true));
          inputs.push_back(KeyInput(0x0F, false, false));
          continue;
        }
        INPUT in = {};
        in.type = INPUT_KEYBOARD;
        in.ki.wScan = c;
        in.ki.dwFlags = KEYEVENTF_UNICODE;
        inputs.push_back(in);
        in.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
        inputs.push_back(in);
      }
    }
  }
  if (!inputs.empty()) SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
}

// ---------------------------------------------------------------- thanh đỏ

std::wstring RemoteInput::ShowBar(const std::wstring& text, const std::wstring& stop, const RECT* screen) {
  text_ = text;
  stop_ = stop.empty() ? L"Stop" : stop;
  if (screen) {
    screen_ = *screen;
  } else {
    MONITORINFO mi = {};
    mi.cbSize = sizeof(mi);
    GetMonitorInfo(MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY), &mi);
    screen_ = mi.rcMonitor;
  }
  HINSTANCE inst = GetModuleHandle(nullptr);
  static bool registered = false;
  if (!registered) {
    WNDCLASSW wc = {};
    wc.lpfnWndProc = BarProc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursor(nullptr, IDC_SIZEALL);
    wc.lpszClassName = kBarClass;
    registered = RegisterClassW(&wc) != 0;
  }
  if (!red_) red_ = CreateSolidBrush(RGB(0xD9, 0x30, 0x25));
  if (!bar_) {
    bar_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kBarClass, L"Flygo Chat", WS_POPUP, 0, 0, 10, 10,
                           nullptr, nullptr, inst, this);
    if (!bar_) return std::wstring();
    SetWindowLongPtr(bar_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    button_ = CreateWindowW(L"BUTTON", stop_.c_str(), WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 0, 0, 10, 10, bar_,
                            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kStopButtonId)), inst, nullptr);
  } else if (button_) {
    SetWindowTextW(button_, stop_.c_str());
  }
  LayoutBar();
  ShowWindow(bar_, SW_SHOWNOACTIVATE);
  SetWindowPos(bar_, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  // F12 có thể bị Windows giữ cho trình gỡ lỗi: không được thì dùng F11.
  std::wstring label;
  if (!hotkey_) {
    if (RegisterHotKey(bar_, kHotkeyId, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_F12)) {
      hotkey_ = true;
      label = L"Ctrl+Shift+F12";
    } else if (RegisterHotKey(bar_, kHotkeyId, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, VK_F11)) {
      hotkey_ = true;
      label = L"Ctrl+Shift+F11";
    }
  }
  return label;
}

void RemoteInput::LayoutBar() {
  if (!bar_) return;
  HMONITOR mon = MonitorFromRect(&screen_, MONITOR_DEFAULTTOPRIMARY);
  const double scale = FlutterDesktopGetDpiForMonitor(mon) / 96.0;
  auto px = [&](int v) { return static_cast<int>(v * scale); };
  if (font_) DeleteObject(font_);
  font_ = CreateFontW(-px(15), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  HDC dc = GetDC(bar_);
  HGDIOBJ old = SelectObject(dc, font_);
  SIZE ts = {}, bs = {};
  GetTextExtentPoint32W(dc, text_.c_str(), static_cast<int>(text_.size()), &ts);
  GetTextExtentPoint32W(dc, stop_.c_str(), static_cast<int>(stop_.size()), &bs);
  SelectObject(dc, old);
  ReleaseDC(bar_, dc);
  const int h = px(40), pad = px(16), bw = bs.cx + px(28), bh = px(28);
  const int w = std::min<int>(ts.cx + bw + pad * 3, screen_.right - screen_.left);
  const int x = screen_.left + ((screen_.right - screen_.left) - w) / 2;
  SetWindowPos(bar_, HWND_TOPMOST, x, screen_.top, w, h, SWP_NOACTIVATE);
  if (button_) {
    SendMessage(button_, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
    SetWindowPos(button_, nullptr, w - pad - bw, (h - bh) / 2, bw, bh, SWP_NOZORDER | SWP_NOACTIVATE);
  }
  // Bo góc dưới (Windows 11 bỏ qua nếu không hỗ trợ).
  HRGN rgn = CreateRoundRectRgn(0, -px(12), w + 1, h + 1, px(14), px(14));
  SetWindowRgn(bar_, rgn, TRUE);
  InvalidateRect(bar_, nullptr, TRUE);
}

void RemoteInput::HideBar() {
  if (!bar_) return;
  if (hotkey_) UnregisterHotKey(bar_, kHotkeyId);
  hotkey_ = false;
  DestroyWindow(bar_);
  bar_ = nullptr;
  button_ = nullptr;
}

void RemoteInput::FireStop() {
  if (channel_) channel_->InvokeMethod("stop", nullptr);
}

LRESULT CALLBACK RemoteInput::BarProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<RemoteInput*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  switch (msg) {
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      RECT r;
      GetClientRect(hwnd, &r);
      if (self && self->red_) FillRect(dc, &r, self->red_);
      if (self) {
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, RGB(255, 255, 255));
        HGDIOBJ old = SelectObject(dc, self->font_);
        RECT t = r;
        t.left += static_cast<LONG>((r.bottom - r.top) * 0.4);
        DrawTextW(dc, self->text_.c_str(), -1, &t, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
        SelectObject(dc, old);
      }
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_COMMAND:
      if (LOWORD(wparam) == kStopButtonId && self) self->FireStop();
      return 0;
    case WM_HOTKEY:
      if (static_cast<int>(wparam) == kHotkeyId && self) self->FireStop();
      return 0;
    case WM_NCHITTEST: {
      // Kéo thanh đi chỗ khác được (trừ nút Dừng).
      LRESULT hit = DefWindowProc(hwnd, msg, wparam, lparam);
      return hit == HTCLIENT ? HTCAPTION : hit;
    }
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_DPICHANGED:
      if (self) self->LayoutBar();
      return 0;
  }
  return DefWindowProc(hwnd, msg, wparam, lparam);
}

// ---------------------------------------------------------------- toàn màn hình (máy điều khiển)

void RemoteInput::SetFullscreen(bool on) {
  HWND hwnd = main_;
  if (!hwnd || on == full_) return;
  if (on) {
    full_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    full_placement_ = {};
    full_placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(hwnd, &full_placement_);
    MONITORINFO mi = {};
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &mi)) return;
    SetWindowLongPtr(hwnd, GWL_STYLE, (full_style_ & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW)) | WS_POPUP);
    SetWindowPos(hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right - mi.rcMonitor.left,
                 mi.rcMonitor.bottom - mi.rcMonitor.top, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    full_ = true;
  } else {
    SetWindowLongPtr(hwnd, GWL_STYLE, full_style_);
    SetWindowPlacement(hwnd, &full_placement_);
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
    full_ = false;
  }
}
