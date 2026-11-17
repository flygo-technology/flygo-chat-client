import Cocoa
import CryptoKit
import FlutterMacOS
import LocalAuthentication
import ScreenCaptureKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // Mở to sẵn (90% vùng màn hình, giữa màn hình) để thấy đủ 3 cột, khỏi phải kéo.
    if let screen = NSScreen.main ?? NSScreen.screens.first {
      let area = screen.visibleFrame
      let w = max(1000, area.width * 0.9), h = max(700, area.height * 0.9)
      let frame = NSRect(x: area.midX - w / 2, y: area.midY - h / 2, width: min(w, area.width), height: min(h, area.height))
      self.setFrame(frame, display: true)
    }
    self.minSize = NSSize(width: 420, height: 560)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Ô chọn tệp trong webview mini app (Drive: Tải tệp lên): macos/Runner/WebViewFilePanel.swift.
    WebViewFilePanel.install()

    // Khoá thiết bị / passkey (Dart: lib/security/device_key.dart), cùng kênh với iOS / Android.
    let deviceKey = FlutterMethodChannel(name: "flygo/devicekey", binaryMessenger: flutterViewController.engine.binaryMessenger)
    deviceKey.setMethodCallHandler { call, result in DeviceKeyCore.handle(call, result) }

    // Số tin chưa đọc trên biểu tượng ở Dock (Dart: lib/ui/app_badge.dart).
    let badge = FlutterMethodChannel(name: "flygo/badge", binaryMessenger: flutterViewController.engine.binaryMessenger)
    badge.setMethodCallHandler { call, result in
      guard call.method == "set", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      let n = args["count"] as? Int ?? 0
      NSApp.dockTile.badgeLabel = n <= 0 ? nil : (n > 99 ? "99+" : String(n))
      result(nil)
    }

    // Chụp màn hình để đính kèm vào tin nhắn (Dart: lib/ui/screen_grab.dart).
    let shot = FlutterMethodChannel(name: "flygo/screenshot", binaryMessenger: flutterViewController.engine.binaryMessenger)
    shot.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.handleShot(call, result)
    }

    // Vị trí / kích thước cửa sổ riêng tách từ màn chia ô (Dart: lib/ui/popout_windows.dart).
    let win = FlutterMethodChannel(name: "flygo/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    win.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.handleWindow(call, result)
    }

    // Điều khiển máy tính từ xa (Dart: lib/remote/rc_native.dart).
    RemoteInput.shared = RemoteInput(messenger: flutterViewController.engine.binaryMessenger, window: self)

    super.awakeFromNib()
  }

  // MARK: Cửa sổ riêng

  private func handleWindow(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let nums = (call.arguments as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
    switch call.method {
    case "getFrame":
      // Thu nhỏ / toàn màn hình: không lưu.
      if isMiniaturized || styleMask.contains(.fullScreen) {
        result(nil)
        return
      }
      result([frame.origin.x, frame.origin.y, frame.size.width, frame.size.height])
    case "setFrame":
      guard nums.count == 4, nums[2] >= 200, nums[3] >= 200 else {
        result(false)
        return
      }
      let r = NSRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
      // Màn hình cũ đã rút: không đặt cửa sổ ra ngoài vùng nhìn thấy.
      guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(r) }) else {
        result(false)
        return
      }
      setFrame(r, display: true)
      result(true)
    case "setTitle":
      // Tiêu đề cửa sổ riêng (vd tên công ty của cửa sổ Ký số).
      title = (call.arguments as? String) ?? title
      result(true)
    case "center":
      guard nums.count == 2, let screen = self.screen ?? NSScreen.main else {
        result(false)
        return
      }
      let area = screen.visibleFrame
      let w = min(nums[0], area.width), h = min(nums[1], area.height)
      setFrame(NSRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h), display: true)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Chụp màn hình

  /// Màn hình đang có con trỏ chuột lúc bấm chụp.
  private var shotScreen: NSScreen?
  /// Cửa sổ trước khi thành lớp phủ toàn màn hình (để trả lại như cũ).
  private var shotSaved: (frame: NSRect, style: NSWindow.StyleMask, level: NSWindow.Level, behavior: NSWindow.CollectionBehavior)?

  // Cửa sổ không viền (lớp phủ chọn vùng) vẫn nhận bàn phím (Esc, Enter, gõ chữ).
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  private func handleShot(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "permission":
      result(CGPreflightScreenCaptureAccess())
    case "requestPermission":
      result(CGRequestScreenCaptureAccess())
    case "hide":
      // Cửa sổ đang toàn màn hình (Space riêng): ẩn đi sẽ chỉ còn Space trống, không chụp được gì.
      if styleMask.contains(.fullScreen) {
        result(FlutterError(code: "fullscreen", message: "window is in full screen", details: nil))
        return
      }
      let mouse = NSEvent.mouseLocation
      shotScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? screen ?? NSScreen.main
      orderOut(nil)
      result(nil)
    case "capture":
      captureShot(result)
    case "overlay":
      guard let s = shotScreen else {
        result(nil)
        return
      }
      if shotSaved == nil { shotSaved = (frame, styleMask, level, collectionBehavior) }
      styleMask = [.borderless]
      level = .screenSaver  // trên cả thanh menu và Dock
      collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      setFrame(s.frame, display: true)
      makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      result(nil)
    case "restore":
      if let v = shotSaved {
        orderOut(nil)
        styleMask = v.style
        level = v.level
        collectionBehavior = v.behavior
        setFrame(v.frame, display: true)
        shotSaved = nil
      }
      makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Chụp màn hình [shotScreen] đủ độ phân giải (Retina), trả về điểm ảnh BGRA từ trên xuống.
  private func captureShot(_ result: @escaping FlutterResult) {
    guard let s = shotScreen ?? NSScreen.main,
          let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else {
      result(FlutterError(code: "failed", message: "no screen", details: nil))
      return
    }
    let id = CGDirectDisplayID(num.uint32Value)
    let pw = Int(s.frame.width * s.backingScaleFactor), ph = Int(s.frame.height * s.backingScaleFactor)
    let done: (CGImage?) -> Void = { img in
      DispatchQueue.main.async {
        guard let img = img, let px = Self.bgraPixels(img) else {
          result(FlutterError(code: "failed", message: "capture failed", details: nil))
          return
        }
        result(["bgra": FlutterStandardTypedData(bytes: px.data), "width": px.width, "height": px.height])
      }
    }
    if #available(macOS 14.0, *) {
      SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
        guard let d = content?.displays.first(where: { $0.displayID == id }) else {
          // ScreenCaptureKit từ chối (quyền / lỗi hệ thống): thử cách cũ trước khi báo lỗi.
          done(CGDisplayCreateImage(id))
          return
        }
        let cfg = SCStreamConfiguration()
        cfg.width = pw
        cfg.height = ph
        cfg.showsCursor = false
        SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: d, excludingWindows: []), configuration: cfg) { img, _ in
          done(img ?? CGDisplayCreateImage(id))
        }
      }
    } else {
      done(CGDisplayCreateImage(id))
    }
  }

  private static func bgraPixels(_ img: CGImage) -> (data: Data, width: Int, height: Int)? {
    let w = img.width, h = img.height
    guard w > 0, h > 0,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let p = ctx.data else { return nil }
    return (Data(bytes: p, count: w * h * 4), w, h)
  }
}

/// Khoá thiết bị trên máy Mac (passkey của Flygo): P-256 trong Secure Enclave (CryptoKit), không xuất được; mỗi lần ký
/// phải qua Touch ID hoặc mật khẩu đăng nhập máy (.userPresence: Mac mini không có Touch ID vẫn dùng được). Khoá lưu dạng
/// dataRepresentation (khối đã mã hoá, chỉ Secure Enclave của chính máy này mở được) trong Application Support, nên không
/// cần keychain-access-groups / provisioning profile. Mac Intel không có chip T2: không hỗ trợ.
enum DeviceKeyCore {
  struct Failure: Error { let code: String; let message: String }

  static var file: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("FlygoChat", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("device-key.v1")
  }

  static func access() throws -> SecAccessControl {
    var cfErr: Unmanaged<CFError>?
    guard let a = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &cfErr) else {
      throw cfErr!.takeRetainedValue() as Error
    }
    return a
  }

  static func load(context: LAContext? = nil) -> SecureEnclave.P256.Signing.PrivateKey? {
    guard SecureEnclave.isAvailable, let blob = try? Foundation.Data(contentsOf: file) else { return nil }
    return try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
  }

  static func hasBiometrics() -> Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) }

  /// "ok" khi máy xác thực được chủ máy (Touch ID hoặc mật khẩu đăng nhập).
  static func presence() -> String {
    var err: NSError?
    if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) { return "ok" }
    if let e = err as? LAError, e.code == .passcodeNotSet { return "none_enrolled" }
    return "unavailable"
  }

  static func status() -> [String: Any?] {
    guard SecureEnclave.isAvailable else {
      return ["supported": false, "biometric": "no_hardware", "enrolled": false, "hw_backed": false, "biometric_bound": false, "public_key": nil]
    }
    let key = load()
    return [
      "supported": true,
      "biometric": presence(),
      "enrolled": key != nil,
      "hw_backed": key != nil,
      // Có Touch ID thì coi như gắn sinh trắc; Mac không có Touch ID dùng mật khẩu đăng nhập máy.
      "biometric_bound": key != nil && hasBiometrics(),
      "public_key": key?.publicKey.x963Representation.base64EncodedString(),
    ]
  }

  static func create() throws {
    guard SecureEnclave.isAvailable else {
      throw Failure(code: "unsupported", message: "Máy Mac này không có Secure Enclave (cần chip Apple hoặc chip T2)")
    }
    guard presence() == "ok" else { throw Failure(code: "devicekey", message: "Máy chưa đặt mật khẩu đăng nhập / Touch ID") }
    let key = try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: false, accessControl: access())
    try key.dataRepresentation.write(to: file, options: [.atomic])
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }

  static func delete() { try? FileManager.default.removeItem(at: file) }

  /// Ký sau khi chủ máy xác thực (Touch ID / mật khẩu); trả về chữ ký ECDSA P-256 / SHA-256 dạng DER, base64.
  static func sign(_ data: Foundation.Data, reason: String, _ done: @escaping (Result<String, Failure>) -> Void) {
    guard load() != nil else {
      done(.failure(Failure(code: "no_key", message: "Máy này chưa có passkey")))
      return
    }
    let ctx = LAContext()
    ctx.localizedCancelTitle = "Hủy"
    guard let ac = try? access() else {
      done(.failure(Failure(code: "devicekey", message: "Không tạo được quyền truy cập khoá")))
      return
    }
    ctx.evaluateAccessControl(ac, operation: .useKeySign, localizedReason: reason) { ok, err in
      guard ok else {
        let cancelled = (err as? LAError)?.code == .userCancel || (err as? LAError)?.code == .appCancel
        done(.failure(Failure(code: cancelled ? "cancelled" : "auth", message: err?.localizedDescription ?? "Chưa xác thực")))
        return
      }
      guard let key = load(context: ctx) else {
        done(.failure(Failure(code: "no_key", message: "Máy này chưa có passkey")))
        return
      }
      do {
        done(.success(try key.signature(for: data).derRepresentation.base64EncodedString()))
      } catch {
        done(.failure(Failure(code: "sign", message: error.localizedDescription)))
      }
    }
  }
}

extension DeviceKeyCore {
  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "status": result(status())
    case "create":
      do {
        try create()
        result(status())
      } catch let f as Failure {
        result(FlutterError(code: f.code, message: f.message, details: nil))
      } catch {
        result(FlutterError(code: "devicekey", message: error.localizedDescription, details: nil))
      }
    case "delete":
      delete()
      result(true)
    case "sign":
      let data = Foundation.Data(base64Encoded: args["data"] as? String ?? "") ?? Foundation.Data()
      sign(data, reason: args["title"] as? String ?? "Xác thực") { r in
        DispatchQueue.main.async {
          switch r {
          case .success(let sig): result(sig)
          case .failure(let f): result(FlutterError(code: f.code, message: f.message, details: nil))
          }
        }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
