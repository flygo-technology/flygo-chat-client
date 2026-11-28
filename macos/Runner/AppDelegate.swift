import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Liên kết flygochat://... (đăng nhập Google, Ký số, mở app) mở vào chính app đang chạy: chuyển cho Flutter qua kênh
  /// "flygo/link". Flutter chưa nhận (app vừa mở bằng liên kết) thì giữ lại; Flutter hỏi "pending" khi sẵn sàng.
  private var pending: [String] = []
  private var channel: FlutterMethodChannel?

  private func linkChannel() -> FlutterMethodChannel? {
    if let c = channel { return c }
    guard let vc = mainFlutterWindow?.contentViewController as? FlutterViewController else { return nil }
    let c = FlutterMethodChannel(name: "flygo/link", binaryMessenger: vc.engine.binaryMessenger)
    c.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pending" else { return result(FlutterMethodNotImplemented) }
      result(self?.pending ?? [])
      self?.pending.removeAll()
    }
    channel = c
    return c
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    _ = linkChannel()
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      let s = url.absoluteString
      guard let c = linkChannel() else { pending.append(s); continue }
      c.invokeMethod("open", arguments: s) { [weak self] r in
        if (r as? NSObject) == FlutterMethodNotImplemented { self?.pending.append(s) }
      }
    }
  }
}
