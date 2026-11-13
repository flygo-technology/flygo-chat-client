import CallKit
import CryptoKit
import Flutter
import LocalAuthentication
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

/// Thông báo đẩy: lấy mã APNs (tin nhắn) và mã VoIP (cuộc gọi), báo cuộc gọi đến cho CallKit
/// ngay khi nhận VoIP push (iOS bắt buộc), chuyển thao tác bấm thông báo về Flutter qua kênh "flygo/push".
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  private var channel: FlutterMethodChannel?
  private var clipChannel: FlutterMethodChannel?
  private var deviceKeyChannel: FlutterMethodChannel?
  private var shareChannel: FlutterMethodChannel?
  private var apnsToken: String?
  private var tokenWaiters: [FlutterResult] = []
  private var launchPayload: [String: Any]?
  private var voipRegistry: PKPushRegistry?
  /// Các cuộc gọi CallKit hiện có (để biết cuộc gọi của kênh đã được trả lời trên máy này chưa).
  private let callObserver = CXCallObserver()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
      DispatchQueue.main.async { application.registerForRemoteNotifications() }
    }
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FlygoPush") else { return }
    let ch = FlutterMethodChannel(name: "flygo/push", binaryMessenger: registrar.messenger())
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "apnsToken":
        if let t = self.apnsToken { result(t) } else { self.tokenWaiters.append(result) }
      case "launchPayload":
        result(self.launchPayload)
        self.launchPayload = nil
      case "setRingtones":
        // Nhạc chuông theo nhóm: id kênh → tên tệp (Runner/<tên>.caf), đọc lại khi có cuộc gọi VoIP lúc app tắt.
        UserDefaults.standard.set(call.arguments as? [String: String] ?? [:], forKey: "flygo_ringtones")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
    // Bộ nhớ tạm có ảnh / chữ không: chỉ hỏi loại nội dung, không đọc nên iOS không hiện "đã dán từ…"
    // (Dart: lib/ui/clip.dart). Ảnh chỉ được đọc khi người dùng bấm "Dán ảnh" / "Dán".
    if let clipRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "FlygoClip") {
      let clip = FlutterMethodChannel(name: "flygo/clip", binaryMessenger: clipRegistrar.messenger())
      clip.setMethodCallHandler { call, result in
        guard call.method == "probe" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let pb = UIPasteboard.general
        result(["image": pb.hasImages, "text": pb.hasStrings || pb.hasURLs, "stamp": pb.changeCount])
      }
      clipChannel = clip
    }
    // Khoá thiết bị gắn Face ID / Touch ID cho "Thiết bị" / xác thực từ xa (Dart: lib/security/device_key.dart).
    if let keyRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "FlygoDeviceKey") {
      let ch = FlutterMethodChannel(name: "flygo/devicekey", binaryMessenger: keyRegistrar.messenger())
      ch.setMethodCallHandler { call, result in DeviceKey.handle(call, result) }
      deviceKeyChannel = ch
    }
    // Nhận chia sẻ từ app khác (Share Extension để lại tệp trong App Group; Dart: lib/ui/share_intake.dart).
    if let shareRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "FlygoShare") {
      let ch = FlutterMethodChannel(name: "flygo/share", binaryMessenger: shareRegistrar.messenger())
      ch.setMethodCallHandler { call, result in
        guard call.method == "take" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(AppDelegate.takeShare())
      }
      shareChannel = ch
    }
  }

  /// "Chia sẻ" → Flygo Chat: thứ Share Extension để lại trong App Group, chuyển sang thư mục tạm của app, lấy một lần.
  /// Cùng dạng với Android: {files: [đường dẫn], text}.
  static func takeShare() -> [String: Any]? {
    let fm = FileManager.default
    guard let box = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.vn.flygo.chat") else { return nil }
    let dir = box.appendingPathComponent("shared", isDirectory: true)
    let manifest = dir.appendingPathComponent("pending.json")
    guard let data = try? Data(contentsOf: manifest),
          let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    try? fm.removeItem(at: manifest)
    let tmp = fm.temporaryDirectory.appendingPathComponent("shared", isDirectory: true)
    try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    var files: [String] = []
    for name in (m["files"] as? [String]) ?? [] {
      let from = dir.appendingPathComponent(name), to = tmp.appendingPathComponent(name)
      try? fm.removeItem(at: to)
      if (try? fm.moveItem(at: from, to: to)) != nil { files.append(to.path) }
    }
    // Tệp cũ còn sót (lần chia sẻ chưa được lấy) cũng xoá.
    for left in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: left) }
    return ["files": files, "text": m["text"] as? String ?? ""]
  }

  // MARK: APNs (tin nhắn)

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data) {
    let t = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsToken = t
    tokenWaiters.forEach { $0(t) }
    tokenWaiters.removeAll()
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    tokenWaiters.forEach { $0(nil) }
    tokenWaiters.removeAll()
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    var data: [String: Any] = [:]
    for (k, v) in response.notification.request.content.userInfo {
      if let key = k as? String, key != "aps" { data[key] = v }
    }
    if let ch = channel {
      ch.invokeMethod("onTap", arguments: data)
    } else {
      launchPayload = data
    }
    completionHandler()
  }

  // MARK: PushKit (cuộc gọi)

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else { return completion() }
    let p = payload.dictionaryPayload
    let caller = (p["sender_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Flygo Chat"
    let channel = p["channel_id"] as? String ?? ""
    // Mỗi kênh một mã cuộc gọi cố định: tin "cuộc gọi đã kết thúc" tắt đúng màn hình đang đổ chuông.
    // Gọi nhóm của Flygo Chat (tin đổ chuông trong nhóm/kênh): máy chủ đẩy báo thêm video = "1" / "0".
    let video = (p["video"] as? String) == "1"
    let data = flutter_callkit_incoming.Data(id: Self.callUUID(channel), nameCaller: caller, handle: "Flygo Chat", type: video ? 1 : 0)
    if (p["sub_type"] as? String) == "calls_ended" {
      // iOS bắt buộc báo CallKit cho mọi VoIP push: báo lại cuộc gọi cùng mã (đang đổ chuông / đang gọi thì trùng mã,
      // bị bỏ qua) rồi kết thúc. Máy chủ đẩy gửi tin này cho MỌI máy của mình khi mình vào cuộc gọi, kể cả máy vừa
      // trả lời: cuộc gọi của kênh này đã được trả lời trên máy này thì giữ nguyên, không kết thúc.
      data.appName = "Flygo Chat"
      // Cuộc gọi đi / cuộc họp app tự báo CallKit (cùng mã kênh) cũng giữ nguyên, kể cả khi chưa kết nối.
      let answeredHere = callObserver.calls.contains {
        $0.uuid.uuidString.uppercased() == Self.callUUID(channel) && ($0.hasConnected || $0.isOutgoing) && !$0.hasEnded
      }
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
        if !answeredHere { SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(data) }
        completion()
      }
      return
    }
    data.appName = "Flygo Chat"
    data.duration = 45000
    data.extra = [
      "channel_id": p["channel_id"] as? String ?? "", "server_id": p["server_id"] as? String ?? "",
      "video": video ? "1" : "0",
    ]
    if let ch = p["channel_id"] as? String,
       let ring = (UserDefaults.standard.dictionary(forKey: "flygo_ringtones") as? [String: String])?[ch] {
      data.ringtonePath = "\(ring).caf"
    }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
      completion()
    }
  }

  /// Mã cuộc gọi (UUID) suy ra từ id kênh.
  static func callUUID(_ channel: String) -> String {
    if channel.isEmpty { return UUID().uuidString }
    let h = Insecure.MD5.hash(data: Foundation.Data(channel.utf8)).map { String(format: "%02x", $0) }.joined()
    let a = Array(h)
    func s(_ i: Int, _ j: Int) -> String { String(a[i..<j]) }
    return "\(s(0, 8))-\(s(8, 12))-4\(s(13, 16))-a\(s(17, 20))-\(s(20, 32))".uppercased()
  }
}


/// Khoá thiết bị: EC P-256 trong Secure Enclave, không xuất được, mỗi lần ký phải qua Face ID / Touch ID
/// (.biometryCurrentSet: thêm / đổi vân tay, khuôn mặt thì khoá mất hiệu lực).
enum DeviceKey {
  static let tag = "vn.flygo.chat.device.v1".data(using: .utf8)!

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "status": result(status())
    case "create":
      do { try create(); result(status()) } catch { result(FlutterError(code: "devicekey", message: error.localizedDescription, details: nil)) }
    case "delete":
      SecItemDelete(query() as CFDictionary)
      result(true)
    case "sign":
      let data = Foundation.Data(base64Encoded: args["data"] as? String ?? "") ?? Foundation.Data()
      sign(data, reason: args["title"] as? String ?? "Xác thực", result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  static func query() -> [String: Any] {
    [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: tag, kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom]
  }

  static func privateKey(context: LAContext? = nil) -> SecKey? {
    var q = query()
    q[kSecReturnRef as String] = true
    if let context = context { q[kSecUseAuthenticationContext as String] = context }
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let key = item else { return nil }
    return (key as! SecKey)
  }

  static func biometric() -> String {
    let ctx = LAContext()
    var err: NSError?
    if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) { return "ok" }
    if let e = err as? LAError, e.code == .biometryNotEnrolled { return "none_enrolled" }
    if let e = err as? LAError, e.code == .biometryNotAvailable { return "no_hardware" }
    return "unavailable"
  }

  static func status() -> [String: Any?] {
    let key = privateKey()
    var pub: String?
    if let key = key, let p = SecKeyCopyPublicKey(key), let raw = SecKeyCopyExternalRepresentation(p, nil) as Foundation.Data? {
      pub = raw.base64EncodedString()
    }
    return [
      "supported": true,
      "biometric": biometric(),
      "enrolled": key != nil,
      "hw_backed": key != nil,
      "biometric_bound": key != nil,
      "public_key": pub,
    ]
  }

  static func create() throws {
    guard biometric() == "ok" else {
      throw NSError(domain: "devicekey", code: 1, userInfo: [NSLocalizedDescriptionKey: "Máy chưa cài Face ID / Touch ID"])
    }
    SecItemDelete(query() as CFDictionary)
    var cfErr: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], &cfErr) else {
      throw cfErr!.takeRetainedValue() as Error
    }
    let attrs: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: tag,
        kSecAttrAccessControl as String: access,
      ],
    ]
    guard SecKeyCreateRandomKey(attrs as CFDictionary, &cfErr) != nil else { throw cfErr!.takeRetainedValue() as Error }
  }

  static func sign(_ data: Foundation.Data, reason: String, _ result: @escaping FlutterResult) {
    let ctx = LAContext()
    ctx.localizedCancelTitle = "Hủy"
    ctx.evaluateAccessControl(
      SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], nil)!,
      operation: .useKeySign, localizedReason: reason
    ) { ok, err in
      DispatchQueue.main.async {
        guard ok else {
          let cancelled = (err as? LAError)?.code == .userCancel || (err as? LAError)?.code == .appCancel
          result(FlutterError(code: cancelled ? "cancelled" : "auth", message: err?.localizedDescription ?? "Chưa xác thực", details: nil))
          return
        }
        guard let key = privateKey(context: ctx) else {
          result(FlutterError(code: "no_key", message: "Thiết bị chưa có khoá xác thực (hoặc Face ID / vân tay đã đổi)", details: nil))
          return
        }
        var cfErr: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, &cfErr) as Foundation.Data? else {
          result(FlutterError(code: "sign", message: cfErr.map { ($0.takeRetainedValue() as Error).localizedDescription } ?? "Không ký được", details: nil))
          return
        }
        result(sig.base64EncodedString())
      }
    }
  }
}
