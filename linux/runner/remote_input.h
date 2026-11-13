#ifndef RUNNER_REMOTE_INPUT_H_
#define RUNNER_REMOTE_INPUT_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Điều khiển máy tính từ xa (máy bị điều khiển), kênh "flygo/remote_input" (Dart: lib/remote/rc_native.dart).
// Chỉ chạy trên X11 (XTest); Wayland thì phía Dart không bật tính năng này.
typedef struct _RemoteInput RemoteInput;

RemoteInput* remote_input_new(FlBinaryMessenger* messenger, GtkWindow* window);
void remote_input_free(RemoteInput* self);

#endif  // RUNNER_REMOTE_INPUT_H_
