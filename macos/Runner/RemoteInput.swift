import ApplicationServices
import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

/// Điều khiển máy tính từ xa (máy bị điều khiển), kênh "flygo/remote_input" (Dart: lib/remote/rc_native.dart):
///   - status / request / openSettings: quyền Trợ năng (CGEventPost) và Ghi màn hình
///   - screens: các màn hình (điểm toàn cục, gốc trên trái màn hình chính; id = CGDirectDisplayID như nguồn chụp WebRTC)
///   - inject: chuột / bàn phím / chữ qua CGEventPost
///   - showBar / hideBar: thanh đỏ luôn nổi trên cùng + phím tắt dừng Cmd+Shift+F12 (Carbon, không cần quyền)
///   - fullscreen: cửa sổ app toàn màn hình (máy điều khiển)
final class RemoteInput: NSObject {
  static var shared: RemoteInput?

  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var bar: NSPanel?
  private var hotKey: EventHotKeyRef?
  private var hotKeyHandler: EventHandlerRef?
  private var flags: CGEventFlags = []
  private var lastPos = CGPoint.zero
  private let source = CGEventSource(stateID: .hidSystemState)

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    channel = FlutterMethodChannel(name: "flygo/remote_input", binaryMessenger: messenger)
    self.window = window
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "status":
      result(["accessibility": AXIsProcessTrusted(), "screen": CGPreflightScreenCaptureAccess()])
    case "request":
      if args["kind"] as? String == "screen" {
        _ = CGRequestScreenCaptureAccess()
      } else {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
      }
      result(nil)
    case "openSettings":
      let pane = args["kind"] as? String == "screen" ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
        NSWorkspace.shared.open(url)
      }
      result(nil)
    case "screens":
      result(["screens": screens()])
    case "inject":
      for e in args["events"] as? [[String: Any]] ?? [] {
        inject(e)
      }
      result(nil)
    case "showBar":
      let rect = (args["screen"] as? [NSNumber])?.map { CGFloat($0.doubleValue) }
      result(showBar(text: args["text"] as? String ?? "", stop: args["stop"] as? String ?? "Stop", screen: rect))
    case "hideBar":
      hideBar()
      result(nil)
    case "fullscreen":
      let on = args["on"] as? Bool ?? false
      if let w = window, w.styleMask.contains(.fullScreen) != on { w.toggleFullScreen(nil) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func screens() -> [[String: Any]] {
    NSScreen.screens.compactMap { s in
      guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
      let id = CGDirectDisplayID(num.uint32Value)
      let b = CGDisplayBounds(id)
      var name = ""
      if #available(macOS 10.15, *) { name = s.localizedName }
      return ["id": String(id), "name": name, "x": b.origin.x, "y": b.origin.y, "w": b.width, "h": b.height,
              "primary": CGDisplayIsMain(id) != 0]
    }
  }

  // MARK: Gửi thao tác

  private func num(_ e: [String: Any], _ k: String) -> Double? { (e[k] as? NSNumber)?.doubleValue }

  private func post(_ ev: CGEvent?) {
    guard let ev = ev else { return }
    ev.post(tap: .cghidEventTap)
  }

  private func inject(_ e: [String: Any]) {
    switch e["op"] as? String {
    case "move":
      guard let x = num(e, "x"), let y = num(e, "y") else { return }
      lastPos = CGPoint(x: x, y: y)
      let held = Int(num(e, "buttons") ?? 0)
      let (type, button): (CGEventType, CGMouseButton) =
        held & 1 != 0 ? (.leftMouseDragged, .left)
        : held & 2 != 0 ? (.rightMouseDragged, .right)
        : held & 4 != 0 ? (.otherMouseDragged, .center)
        : (.mouseMoved, .left)
      let ev = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: lastPos, mouseButton: button)
      ev?.flags = flags
      post(ev)
    case "button":
      if let x = num(e, "x"), let y = num(e, "y") { lastPos = CGPoint(x: x, y: y) }
      let b = Int(num(e, "b") ?? 0)
      let down = e["down"] as? Bool ?? false
      let type: CGEventType
      let button: CGMouseButton
      switch b {
      case 1:
        type = down ? .rightMouseDown : .rightMouseUp
        button = .right
      case 2:
        type = down ? .otherMouseDown : .otherMouseUp
        button = .center
      default:
        type = down ? .leftMouseDown : .leftMouseUp
        button = .left
      }
      let ev = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: lastPos, mouseButton: button)
      // Số lần bấm liên tiếp (nháy đúp) do phía Dart đếm.
      ev?.setIntegerValueField(.mouseEventClickState, value: Int64(max(1, Int(num(e, "clicks") ?? 1))))
      ev?.flags = flags
      post(ev)
    case "wheel":
      let dy = Int32(num(e, "dy") ?? 0), dx = Int32(num(e, "dx") ?? 0)
      let ev = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
      post(ev)
    case "key":
      guard let code = num(e, "code") else { return }
      let down = e["down"] as? Bool ?? false
      let hid = Int(num(e, "hid") ?? 0)
      // Phím bổ trợ: giữ trạng thái để gắn vào các sự kiện sau (Cmd+C...).
      let mask: CGEventFlags? = switch hid {
      case 0xE0, 0xE4: .maskControl
      case 0xE1, 0xE5: .maskShift
      case 0xE2, 0xE6: .maskAlternate
      case 0xE3, 0xE7: .maskCommand
      default: nil
      }
      if let m = mask {
        if down { flags.insert(m) } else { flags.remove(m) }
      }
      let ev = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
      if mask != nil { ev?.type = .flagsChanged }
      ev?.flags = flags
      post(ev)
    case "text":
      guard let s = e["s"] as? String, !s.isEmpty else { return }
      for line in s.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        if line.offset > 0 { tapKey(CGKeyCode(kVK_Return)) }
        typeUnicode(Array(String(line.element).utf16))
      }
    default:
      return
    }
  }

  private func tapKey(_ code: CGKeyCode) {
    for down in [true, false] {
      let ev = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
      ev?.flags = []
      post(ev)
    }
  }

  /// Gõ chữ Unicode (tiếng Việt có dấu, emoji): mỗi sự kiện tối đa 20 ký tự UTF-16.
  private func typeUnicode(_ units: [UniChar]) {
    var i = 0
    while i < units.count {
      var end = min(units.count, i + 20)
      // Không cắt giữa cặp UTF-16.
      if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
      var chunk = Array(units[i..<end])
      for down in [true, false] {
        let ev = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
        ev?.flags = []
        ev?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
        post(ev)
      }
      i = end
    }
  }

  // MARK: Thanh đỏ

  private func showBar(text: String, stop: String, screen rect: [CGFloat]?) -> String {
    hideBar()
    let label = NSTextField(labelWithString: text)
    label.textColor = .white
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.lineBreakMode = .byTruncatingTail
    let button = NSButton(title: stop, target: self, action: #selector(stopPressed))
    button.bezelStyle = .rounded
    button.controlSize = .regular
    let stack = NSStackView(views: [label, button])
    stack.orientation = .horizontal
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 10)
    let size = stack.fittingSize
    let w = min(max(size.width, 260), 900), h = max(size.height, 36)

    // Màn hình đang chia sẻ: đổi toạ độ toàn cục (gốc trên trái) sang toạ độ Cocoa (gốc dưới trái).
    var target = NSScreen.main ?? NSScreen.screens.first
    if let r = rect, r.count == 4, let mainH = NSScreen.screens.first?.frame.height {
      let cocoa = NSRect(x: r[0], y: mainH - r[1] - r[3], width: r[2], height: r[3])
      target = NSScreen.screens.first { $0.frame.intersects(cocoa) } ?? target
    }
    let area = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let frame = NSRect(x: area.midX - w / 2, y: area.maxY - h - 6, width: w, height: h)
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    let bg = NSView(frame: NSRect(origin: .zero, size: frame.size))
    bg.wantsLayer = true
    bg.layer?.backgroundColor = NSColor(red: 0.85, green: 0.19, blue: 0.15, alpha: 0.96).cgColor
    bg.layer?.cornerRadius = 10
    stack.frame = bg.bounds
    stack.autoresizingMask = [.width, .height]
    bg.addSubview(stack)
    panel.contentView = bg
    panel.orderFrontRegardless()
    bar = panel
    return registerHotKey() ? "Cmd+Shift+F12" : ""
  }

  private func hideBar() {
    bar?.orderOut(nil)
    bar = nil
    if let h = hotKey {
      UnregisterEventHotKey(h)
      hotKey = nil
    }
  }

  @objc private func stopPressed() {
    fireStop()
  }

  fileprivate func fireStop() {
    DispatchQueue.main.async { self.channel.invokeMethod("stop", arguments: nil) }
  }

  private func registerHotKey() -> Bool {
    if hotKeyHandler == nil {
      var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        RemoteInput.shared?.fireStop()
        return noErr
      }, 1, &spec, nil, &hotKeyHandler)
    }
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x4647_5243), id: 1)  // "FGRC"
    let status = RegisterEventHotKey(UInt32(kVK_F12), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &ref)
    hotKey = ref
    return status == noErr
  }
}
