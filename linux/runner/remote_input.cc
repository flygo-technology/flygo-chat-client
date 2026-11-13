#include "remote_input.h"

#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// Sau header của GTK / Flutter: Xlib định nghĩa các macro None, Bool, Status...
#ifdef GDK_WINDOWING_X11
#include <X11/XKBlib.h>
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/Xrandr.h>
#include <X11/keysym.h>
#endif

// Kênh "flygo/remote_input" trên Linux X11:
//   - status: accessibility = máy chủ X có XTest; screen = đang chạy X11 (chụp màn hình do libwebrtc lo)
//   - screens: các màn hình XRandR (điểm ảnh trên cửa sổ gốc; id = atom tên màn hình như nguồn chụp WebRTC)
//   - inject: chuột / phím / chữ qua XTest
//   - showBar / hideBar: thanh đỏ luôn nổi trên cùng + phím tắt dừng Ctrl+Shift+F12 (XGrabKey trên cửa sổ gốc)
//   - fullscreen: cửa sổ app toàn màn hình (máy điều khiển)

struct _RemoteInput {
  FlMethodChannel* channel;
  GtkWindow* window;
  GtkWidget* bar;
  GtkWidget* label;
  GtkWidget* button;
  GtkCssProvider* css;
  guint raise_timer;
  gboolean fullscreen;
#ifdef GDK_WINDOWING_X11
  Display* dpy;
  gboolean xtest;
  // Phím tắt dừng đang giữ (0 = chưa đăng ký).
  KeyCode hot_key;
  const char* hot_label;
  gboolean filter_added;
  // Mã phím trống dùng tạm để gõ ký tự không có trên kiểu bàn phím hiện tại.
  std::vector<KeyCode>* scratch;
  std::vector<KeySym>* scratch_sym;
  std::vector<gint64>* scratch_at;
  size_t scratch_next;
#endif
};

namespace {

FlValue* Field(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return nullptr;
  return fl_value_lookup_string(map, key);
}

double ToNum(FlValue* v, double fallback = 0) {
  if (v == nullptr) return fallback;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return static_cast<double>(fl_value_get_int(v));
  return fallback;
}

double Num(FlValue* map, const char* key, double fallback = 0) { return ToNum(Field(map, key), fallback); }

gboolean Flag(FlValue* map, const char* key) {
  FlValue* v = Field(map, key);
  return v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(v);
}

std::string Str(FlValue* map, const char* key) {
  FlValue* v = Field(map, key);
  return v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_STRING ? fl_value_get_string(v) : std::string();
}

void FireStop(RemoteInput* self) {
  if (self->channel != nullptr) fl_method_channel_invoke_method(self->channel, "stop", nullptr, nullptr, nullptr, nullptr);
}

#ifdef GDK_WINDOWING_X11

constexpr unsigned int kHotMods = ControlMask | ShiftMask;
// Phím tắt vẫn chạy khi đang bật CapsLock / NumLock (Mod2).
constexpr unsigned int kLockVariants[] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};

void Tap(Display* dpy, KeyCode kc) {
  XTestFakeKeyEvent(dpy, kc, True, CurrentTime);
  XTestFakeKeyEvent(dpy, kc, False, CurrentTime);
}

void FindScratch(RemoteInput* self) {
  if (!self->scratch->empty()) return;
  int min = 0, max = 0, per = 0;
  XDisplayKeycodes(self->dpy, &min, &max);
  KeySym* map = XGetKeyboardMapping(self->dpy, static_cast<KeyCode>(min), max - min + 1, &per);
  if (map == nullptr) return;
  // Từ mã cao xuống: tránh các mã evdev của phím thật.
  for (int kc = max; kc >= min && self->scratch->size() < 64; kc--) {
    bool empty = true;
    for (int i = 0; i < per && empty; i++) empty = map[(kc - min) * per + i] == NoSymbol;
    if (empty) self->scratch->push_back(static_cast<KeyCode>(kc));
  }
  XFree(map);
  self->scratch_sym->assign(self->scratch->size(), NoSymbol);
  self->scratch_at->assign(self->scratch->size(), 0);
}

void ResetScratch(RemoteInput* self) {
  if (self->dpy == nullptr) return;
  bool changed = false;
  for (size_t i = 0; i < self->scratch->size(); i++) {
    if ((*self->scratch_sym)[i] == NoSymbol) continue;
    KeySym none = NoSymbol;
    XChangeKeyboardMapping(self->dpy, (*self->scratch)[i], 1, &none, 1);
    (*self->scratch_sym)[i] = NoSymbol;
    changed = true;
  }
  if (changed) XFlush(self->dpy);
}

// Gõ một ký tự Unicode: dùng phím có sẵn trên kiểu bàn phím hiện tại nếu có (thêm Shift nếu cần), không thì gán
// tạm ký tự cho một mã phím trống (như xdotool).
void TypeChar(RemoteInput* self, gunichar c) {
  Display* dpy = self->dpy;
  KeySym ks;
  if (c == '\n') {
    ks = XK_Return;
  } else if (c == '\t') {
    ks = XK_Tab;
  } else if ((c >= 0x20 && c <= 0x7E) || (c >= 0xA0 && c <= 0xFF)) {
    ks = c;
  } else {
    ks = 0x01000000 | c;
  }
  KeyCode kc = XKeysymToKeycode(dpy, ks);
  if (kc != 0) {
    XkbStateRec st = {};
    XkbGetState(dpy, XkbUseCoreKbd, &st);
    KeySym lower = 0, upper = 0;
    XConvertCase(ks, &lower, &upper);
    // CapsLock đảo hoa / thường của chữ cái: để phím trống lo.
    const bool caps_letter = (st.locked_mods & LockMask) && lower != upper;
    if (!caps_letter && XkbKeycodeToKeysym(dpy, kc, st.group, 0) == ks) {
      Tap(dpy, kc);
      return;
    }
    const KeyCode shift = XKeysymToKeycode(dpy, XK_Shift_L);
    if (!caps_letter && shift != 0 && XkbKeycodeToKeysym(dpy, kc, st.group, 1) == ks) {
      XTestFakeKeyEvent(dpy, shift, True, CurrentTime);
      Tap(dpy, kc);
      XTestFakeKeyEvent(dpy, shift, False, CurrentTime);
      return;
    }
  }
  FindScratch(self);
  const size_t n = self->scratch->size();
  if (n == 0) return;
  size_t slot = n;
  for (size_t i = 0; i < n; i++) {
    if ((*self->scratch_sym)[i] == ks) slot = i;
  }
  if (slot == n) {
    slot = self->scratch_next;
    self->scratch_next = (self->scratch_next + 1) % n;
    // Mã phím này vừa dùng cho ký tự khác: chờ chút để app nhận phím cũ trước khi đổi bảng phím.
    const gint64 since = g_get_monotonic_time() - (*self->scratch_at)[slot];
    if ((*self->scratch_sym)[slot] != NoSymbol && since < 150000) {
      XSync(dpy, False);
      g_usleep(150000 - since);
    }
    KeySym syms[2] = {ks, ks};
    XChangeKeyboardMapping(dpy, (*self->scratch)[slot], 2, syms, 1);
    XSync(dpy, False);
    (*self->scratch_sym)[slot] = ks;
  }
  (*self->scratch_at)[slot] = g_get_monotonic_time();
  Tap(dpy, (*self->scratch)[slot]);
}

void Inject(RemoteInput* self, FlValue* events) {
  Display* dpy = self->dpy;
  if (dpy == nullptr || !self->xtest || events == nullptr || fl_value_get_type(events) != FL_VALUE_TYPE_LIST) return;
  for (size_t i = 0; i < fl_value_get_length(events); i++) {
    FlValue* e = fl_value_get_list_value(events, i);
    const std::string op = Str(e, "op");
    const bool has_pos = Field(e, "x") != nullptr && Field(e, "y") != nullptr;
    // Toạ độ điểm ảnh trên cửa sổ gốc (đã đổi sẵn bên Dart).
    const int x = static_cast<int>(Num(e, "x")), y = static_cast<int>(Num(e, "y"));
    if (op == "move") {
      XTestFakeMotionEvent(dpy, -1, x, y, CurrentTime);
    } else if (op == "button") {
      const int b = static_cast<int>(Num(e, "b"));
      const unsigned int xb = b == 1 ? 3 : b == 2 ? 2 : 1;
      if (has_pos) XTestFakeMotionEvent(dpy, -1, x, y, CurrentTime);
      XTestFakeButtonEvent(dpy, xb, Flag(e, "down"), CurrentTime);
    } else if (op == "wheel") {
      // Số nấc: dy > 0 = cuộn xuống (nút 5), dx > 0 = sang phải (nút 7).
      auto clicks = [&](int n, unsigned int neg, unsigned int pos) {
        const unsigned int btn = n < 0 ? neg : pos;
        for (int k = 0; k < std::min(std::abs(n), 60); k++) {
          XTestFakeButtonEvent(dpy, btn, True, CurrentTime);
          XTestFakeButtonEvent(dpy, btn, False, CurrentTime);
        }
      };
      clicks(static_cast<int>(Num(e, "dy")), 4, 5);
      clicks(static_cast<int>(Num(e, "dx")), 6, 7);
    } else if (op == "key") {
      const int code = static_cast<int>(Num(e, "code"));
      if (code < 8 || code > 255) continue;
      XTestFakeKeyEvent(dpy, static_cast<unsigned int>(code), Flag(e, "down"), CurrentTime);
    } else if (op == "text") {
      const std::string s = Str(e, "s");
      if (!g_utf8_validate(s.c_str(), -1, nullptr)) continue;
      for (const gchar* p = s.c_str(); *p; p = g_utf8_next_char(p)) TypeChar(self, g_utf8_get_char(p));
    }
  }
  XFlush(dpy);
}

FlValue* Screens(RemoteInput* self) {
  g_autoptr(FlValue) list = fl_value_new_list();
  Display* dpy = self->dpy;
  FlValue* r = fl_value_new_map();
  if (dpy == nullptr) {
    fl_value_set_string_take(r, "screens", fl_value_ref(list));
    return r;
  }
  const Window root = DefaultRootWindow(dpy);
  int ev = 0, err = 0, major = 0, minor = 0;
  if (XRRQueryExtension(dpy, &ev, &err) && XRRQueryVersion(dpy, &major, &minor) &&
      (major > 1 || (major == 1 && minor >= 5))) {
    int n = 0;
    XRRMonitorInfo* mons = XRRGetMonitors(dpy, root, True, &n);
    for (int i = 0; mons != nullptr && i < n; i++) {
      const XRRMonitorInfo& m = mons[i];
      FlValue* s = fl_value_new_map();
      fl_value_set_string_take(s, "id", fl_value_new_string(std::to_string(static_cast<unsigned long>(m.name)).c_str()));
      char* name = XGetAtomName(dpy, m.name);
      fl_value_set_string_take(s, "name", fl_value_new_string(name != nullptr ? name : ""));
      if (name != nullptr) XFree(name);
      fl_value_set_string_take(s, "x", fl_value_new_float(m.x));
      fl_value_set_string_take(s, "y", fl_value_new_float(m.y));
      fl_value_set_string_take(s, "w", fl_value_new_float(m.width));
      fl_value_set_string_take(s, "h", fl_value_new_float(m.height));
      fl_value_set_string_take(s, "primary", fl_value_new_bool(m.primary != 0));
      fl_value_append_take(list, s);
    }
    if (mons != nullptr) XRRFreeMonitors(mons);
  }
  const double rw = DisplayWidth(dpy, DefaultScreen(dpy)), rh = DisplayHeight(dpy, DefaultScreen(dpy));
  if (fl_value_get_length(list) == 0) {
    // Không có XRandR 1.5: cả cửa sổ gốc là một màn hình (nguồn chụp WebRTC khi đó cũng chỉ có một).
    FlValue* s = fl_value_new_map();
    fl_value_set_string_take(s, "id", fl_value_new_string("0"));
    fl_value_set_string_take(s, "name", fl_value_new_string("Screen"));
    fl_value_set_string_take(s, "x", fl_value_new_float(0));
    fl_value_set_string_take(s, "y", fl_value_new_float(0));
    fl_value_set_string_take(s, "w", fl_value_new_float(rw));
    fl_value_set_string_take(s, "h", fl_value_new_float(rh));
    fl_value_set_string_take(s, "primary", fl_value_new_bool(TRUE));
    fl_value_append_take(list, s);
  }
  fl_value_set_string_take(r, "screens", fl_value_ref(list));
  FlValue* virt = fl_value_new_list();
  fl_value_append_take(virt, fl_value_new_float(0));
  fl_value_append_take(virt, fl_value_new_float(0));
  fl_value_append_take(virt, fl_value_new_float(rw));
  fl_value_append_take(virt, fl_value_new_float(rh));
  fl_value_set_string_take(r, "virtual", virt);
  return r;
}

GdkFilterReturn HotkeyFilter(GdkXEvent* xevent, GdkEvent* event, gpointer data) {
  auto* self = static_cast<RemoteInput*>(data);
  auto* e = static_cast<XEvent*>(xevent);
  if (self->hot_key == 0 || (e->type != KeyPress && e->type != KeyRelease) || e->xkey.keycode != self->hot_key) {
    return GDK_FILTER_CONTINUE;
  }
  if ((e->xkey.state & kHotMods) != kHotMods) return GDK_FILTER_CONTINUE;
  if (e->type == KeyPress) {
    g_idle_add(
        [](gpointer d) -> gboolean {
          FireStop(static_cast<RemoteInput*>(d));
          return G_SOURCE_REMOVE;
        },
        self);
  }
  return GDK_FILTER_REMOVE;
}

void UngrabHotkey(RemoteInput* self) {
  if (self->dpy == nullptr || self->hot_key == 0) return;
  GdkDisplay* gd = gdk_display_get_default();
  gdk_x11_display_error_trap_push(gd);
  for (unsigned int v : kLockVariants) XUngrabKey(self->dpy, self->hot_key, kHotMods | v, DefaultRootWindow(self->dpy));
  gdk_x11_display_error_trap_pop_ignored(gd);
  self->hot_key = 0;
  self->hot_label = nullptr;
}

// Đăng ký Ctrl+Shift+F12 (bị app khác giữ thì Ctrl+Shift+F11); trả về tên phím tắt, rỗng nếu không được.
std::string GrabHotkey(RemoteInput* self) {
  if (self->dpy == nullptr) return std::string();
  if (self->hot_key != 0) UngrabHotkey(self);
  GdkDisplay* gd = gdk_display_get_default();
  if (!self->filter_added) {
    gdk_window_add_filter(nullptr, HotkeyFilter, self);
    self->filter_added = TRUE;
  }
  const struct {
    KeySym sym;
    const char* label;
  } keys[] = {{XK_F12, "Ctrl+Shift+F12"}, {XK_F11, "Ctrl+Shift+F11"}};
  for (const auto& k : keys) {
    const KeyCode kc = XKeysymToKeycode(self->dpy, k.sym);
    if (kc == 0) continue;
    gdk_x11_display_error_trap_push(gd);
    for (unsigned int v : kLockVariants) {
      XGrabKey(self->dpy, kc, kHotMods | v, DefaultRootWindow(self->dpy), False, GrabModeAsync, GrabModeAsync);
    }
    if (gdk_x11_display_error_trap_pop(gd) == 0) {
      self->hot_key = kc;
      self->hot_label = k.label;
      return k.label;
    }
    gdk_x11_display_error_trap_push(gd);
    for (unsigned int v : kLockVariants) XUngrabKey(self->dpy, kc, kHotMods | v, DefaultRootWindow(self->dpy));
    gdk_x11_display_error_trap_pop_ignored(gd);
  }
  return std::string();
}

#endif  // GDK_WINDOWING_X11

// ---------------------------------------------------------------- thanh đỏ

void HideBar(RemoteInput* self) {
  if (self->raise_timer != 0) {
    g_source_remove(self->raise_timer);
    self->raise_timer = 0;
  }
#ifdef GDK_WINDOWING_X11
  UngrabHotkey(self);
  ResetScratch(self);
#endif
  if (self->bar != nullptr) {
    gtk_widget_destroy(self->bar);
    self->bar = nullptr;
    self->label = nullptr;
    self->button = nullptr;
  }
}

std::string ShowBar(RemoteInput* self, const std::string& text, const std::string& stop, const double* screen) {
  GdkDisplay* gd = gdk_display_get_default();
  if (self->css == nullptr) {
    self->css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(self->css,
                                    "#flygo-rc-bar { background-color: #D93025; padding: 6px 10px 6px 16px; }"
                                    "#flygo-rc-bar label { color: #FFFFFF; font-weight: 600; }"
                                    "#flygo-rc-bar button { background: #FFFFFF; color: #D93025; font-weight: 600;"
                                    " border: none; border-radius: 6px; padding: 2px 14px; box-shadow: none; }"
                                    "#flygo-rc-bar button label { color: #D93025; }",
                                    -1, nullptr);
  }
  if (self->bar == nullptr) {
    // Cửa sổ popup (override-redirect): không lấy tiêu điểm, không có trên thanh tác vụ, luôn nổi trên cùng.
    GtkWidget* bar = gtk_window_new(GTK_WINDOW_POPUP);
    gtk_widget_set_name(bar, "flygo-rc-bar");
    gtk_window_set_title(GTK_WINDOW(bar), "Flygo Chat");
    gtk_window_set_keep_above(GTK_WINDOW(bar), TRUE);
    gtk_window_set_accept_focus(GTK_WINDOW(bar), FALSE);
    gtk_window_set_skip_taskbar_hint(GTK_WINDOW(bar), TRUE);
    gtk_window_set_skip_pager_hint(GTK_WINDOW(bar), TRUE);
    gtk_style_context_add_provider_for_screen(gtk_widget_get_screen(bar), GTK_STYLE_PROVIDER(self->css),
                                              GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    GtkWidget* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 16);
    self->label = gtk_label_new("");
    gtk_label_set_ellipsize(GTK_LABEL(self->label), PANGO_ELLIPSIZE_END);
    self->button = gtk_button_new_with_label("");
    gtk_widget_set_can_focus(self->button, FALSE);
    g_signal_connect_swapped(self->button, "clicked", G_CALLBACK(+[](RemoteInput* s) { FireStop(s); }), self);
    gtk_box_pack_start(GTK_BOX(box), self->label, TRUE, TRUE, 0);
    gtk_box_pack_end(GTK_BOX(box), self->button, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(bar), box);
    self->bar = bar;
  }
  gtk_label_set_text(GTK_LABEL(self->label), text.c_str());
  gtk_button_set_label(GTK_BUTTON(self->button), stop.empty() ? "Stop" : stop.c_str());
  gtk_widget_show_all(self->bar);

  // Vùng màn hình (điểm ảnh X) → toạ độ GDK (chia hệ số phóng to GDK_SCALE).
  GdkRectangle area = {0, 0, 0, 0};
  if (screen != nullptr) {
    area = {static_cast<int>(screen[0]), static_cast<int>(screen[1]), static_cast<int>(screen[2]),
            static_cast<int>(screen[3])};
  }
  const int scale = std::max(1, gdk_window_get_scale_factor(gdk_get_default_root_window()));
  GdkRectangle geo = {area.x / scale, area.y / scale, area.width / scale, area.height / scale};
  if (geo.width <= 0 || geo.height <= 0) {
    GdkMonitor* mon = gdk_display_get_primary_monitor(gd);
    if (mon == nullptr) mon = gdk_display_get_monitor(gd, 0);
    if (mon != nullptr) gdk_monitor_get_geometry(mon, &geo);
  }
  GtkRequisition nat = {0, 0};
  gtk_widget_get_preferred_size(self->bar, nullptr, &nat);
  const int w = std::min(nat.width, std::max(200, geo.width));
  gtk_window_resize(GTK_WINDOW(self->bar), w, nat.height);
  gtk_window_move(GTK_WINDOW(self->bar), geo.x + (geo.width - w) / 2, geo.y);
  if (gtk_widget_get_window(self->bar) != nullptr) gdk_window_raise(gtk_widget_get_window(self->bar));
  if (self->raise_timer == 0) {
    // Cửa sổ khác bật lên trên (vd. toàn màn hình) thì kéo thanh đỏ lên lại.
    self->raise_timer = g_timeout_add(
        1500,
        [](gpointer d) -> gboolean {
          auto* s = static_cast<RemoteInput*>(d);
          if (s->bar != nullptr && gtk_widget_get_window(s->bar) != nullptr) gdk_window_raise(gtk_widget_get_window(s->bar));
          return G_SOURCE_CONTINUE;
        },
        self);
  }
#ifdef GDK_WINDOWING_X11
  return self->hot_label != nullptr ? std::string(self->hot_label) : GrabHotkey(self);
#else
  return std::string();
#endif
}

void MethodCall(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  auto* self = static_cast<RemoteInput*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  bool x11 = false, xtest = false;
#ifdef GDK_WINDOWING_X11
  x11 = self->dpy != nullptr;
  xtest = x11 && self->xtest;
#endif
  if (strcmp(method, "status") == 0) {
    g_autoptr(FlValue) r = fl_value_new_map();
    fl_value_set_string_take(r, "accessibility", fl_value_new_bool(xtest));
    fl_value_set_string_take(r, "screen", fl_value_new_bool(x11));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(r));
  } else if (strcmp(method, "request") == 0 || strcmp(method, "openSettings") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "screens") == 0) {
#ifdef GDK_WINDOWING_X11
    g_autoptr(FlValue) r = Screens(self);
#else
    g_autoptr(FlValue) r = fl_value_new_map();
#endif
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(r));
  } else if (strcmp(method, "inject") == 0) {
#ifdef GDK_WINDOWING_X11
    Inject(self, Field(args, "events"));
#endif
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "showBar") == 0) {
    double rect[4] = {0, 0, 0, 0};
    const double* screen = nullptr;
    FlValue* s = Field(args, "screen");
    if (s != nullptr && fl_value_get_type(s) == FL_VALUE_TYPE_LIST && fl_value_get_length(s) == 4) {
      for (size_t i = 0; i < 4; i++) rect[i] = ToNum(fl_value_get_list_value(s, i));
      screen = rect;
    }
    const std::string hotkey = ShowBar(self, Str(args, "text"), Str(args, "stop"), screen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_string(hotkey.c_str())));
  } else if (strcmp(method, "hideBar") == 0) {
    HideBar(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "fullscreen") == 0) {
    const gboolean on = Flag(args, "on");
    if (self->window != nullptr && on != self->fullscreen) {
      on ? gtk_window_fullscreen(self->window) : gtk_window_unfullscreen(self->window);
      self->fullscreen = on;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

RemoteInput* remote_input_new(FlBinaryMessenger* messenger, GtkWindow* window) {
  auto* self = g_new0(RemoteInput, 1);
  self->window = window;
#ifdef GDK_WINDOWING_X11
  self->scratch = new std::vector<KeyCode>();
  self->scratch_sym = new std::vector<KeySym>();
  self->scratch_at = new std::vector<gint64>();
  GdkDisplay* gd = gdk_display_get_default();
  if (gd != nullptr && GDK_IS_X11_DISPLAY(gd)) {
    self->dpy = gdk_x11_display_get_xdisplay(gd);
    int ev = 0, err = 0, major = 0, minor = 0;
    self->xtest = XTestQueryExtension(self->dpy, &ev, &err, &major, &minor);
  }
#endif
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger, "flygo/remote_input", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, MethodCall, self, nullptr);
  return self;
}

void remote_input_free(RemoteInput* self) {
  if (self == nullptr) return;
  HideBar(self);
#ifdef GDK_WINDOWING_X11
  if (self->filter_added) gdk_window_remove_filter(nullptr, HotkeyFilter, self);
  delete self->scratch;
  delete self->scratch_sym;
  delete self->scratch_at;
#endif
  g_clear_object(&self->css);
  g_clear_object(&self->channel);
  g_free(self);
}
