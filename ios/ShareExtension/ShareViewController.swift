import ImageIO
import UIKit
import UniformTypeIdentifiers

/// "Chia sẻ" → Flygo Chat: ảnh / video / tệp / chữ / link được chép vào thư mục `shared` của App Group kèm
/// `pending.json`, rồi mở Flygo Chat (flygochat-share://share). App chính lấy ra qua kênh "flygo/share"
/// (AppDelegate.takeShare, Dart: lib/ui/share_intake.dart) và mở màn "Gửi tới…".
class ShareViewController: UIViewController {
  static let group = "group.vn.flygo.chat"

  private let label = UILabel()
  private var started = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    label.text = "Đang chuyển sang Flygo Chat…"
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if started { return }
    started = true
    Task { await run() }
  }

  private func run() async {
    guard let box = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) else {
      return finish(open: false)
    }
    let dir = box.appendingPathComponent("shared", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var files: [String] = []
    var texts: [String] = []
    var n = 0
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    for item in (extensionContext?.inputItems as? [NSExtensionItem]) ?? [] {
      for p in item.attachments ?? [] {
        n += 1
        let base = "\(stamp)_\(n)"
        if p.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
          if let name = await copyFile(p, type: UTType.movie, to: dir, base: base) { files.append(name) }
        } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          if let name = await image(p, to: dir, base: base) { files.append(name) }
        } else if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || p.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
          // Tệp bất kỳ (PDF, Excel, Word…): giữ nguyên tên.
          if let name = await copyFile(p, type: UTType.data, to: dir, base: base) { files.append(name) }
        } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          if let u = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL { texts.append(u.absoluteString) }
        } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          if let t = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { texts.append(t) }
        }
      }
    }
    let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if files.isEmpty && text.isEmpty { return finish(open: false) }
    let manifest: [String: Any] = ["files": files, "text": text]
    if let data = try? JSONSerialization.data(withJSONObject: manifest) {
      try? data.write(to: dir.appendingPathComponent("pending.json"), options: .atomic)
    }
    finish(open: true)
  }

  /// Video / tệp như nguyên bản (bản tạm của hệ thống chỉ tồn tại trong lúc gọi lại), tên = tiền tố + tên gốc.
  private func copyFile(_ p: NSItemProvider, type: UTType, to dir: URL, base: String) async -> String? {
    await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
      p.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
        guard let url else { return c.resume(returning: nil) }
        let original = url.lastPathComponent.isEmpty ? "tep" : url.lastPathComponent
        let out = dir.appendingPathComponent("\(base)_\(original)")
        do {
          try? FileManager.default.removeItem(at: out)
          try FileManager.default.copyItem(at: url, to: out)
          c.resume(returning: out.lastPathComponent)
        } catch {
          c.resume(returning: nil)
        }
      }
    }
  }

  /// Ảnh thành JPEG (ảnh HEIC của máy ảnh cũng vậy, để mọi máy xem được), xoay đúng chiều bằng ImageIO mà không giải
  /// mã cả ảnh vào bộ nhớ (extension được cấp rất ít bộ nhớ). Ảnh JPEG sẵn thì chép nguyên.
  private func image(_ p: NSItemProvider, to dir: URL, base: String) async -> String? {
    let out = dir.appendingPathComponent("\(base).jpg")
    let item = try? await p.loadItem(forTypeIdentifier: UTType.image.identifier)
    var src: CGImageSource?
    if let url = item as? URL {
      src = CGImageSourceCreateWithURL(url as CFURL, nil)
    } else if let data = item as? Data {
      src = CGImageSourceCreateWithData(data as CFData, nil)
    } else if let img = item as? UIImage, let data = img.jpegData(compressionQuality: 0.9) {
      return (try? data.write(to: out)) != nil ? out.lastPathComponent : nil
    }
    guard let src, CGImageSourceGetCount(src) > 0 else { return nil }
    if let t = CGImageSourceGetType(src) as String?, t == UTType.jpeg.identifier, let url = item as? URL {
      try? FileManager.default.removeItem(at: out)
      return (try? FileManager.default.copyItem(at: url, to: out)) != nil ? out.lastPathComponent : nil
    }
    guard let dst = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImageFromSource(dst, src, 0, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    return CGImageDestinationFinalize(dst) ? out.lastPathComponent : nil
  }

  private func finish(open: Bool) {
    if open, let url = URL(string: "flygochat-share://share") { openApp(url) }
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }

  /// Extension không được gọi UIApplication.shared / open(_:): tìm UIApplication theo chuỗi responder rồi gọi
  /// openURL:options:completionHandler: qua runtime.
  private func openApp(_ url: URL) {
    typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
    let sel = NSSelectorFromString("openURL:options:completionHandler:")
    var r: UIResponder? = self
    while let x = r {
      if x is UIApplication, x.responds(to: sel) {
        let f = unsafeBitCast(x.method(for: sel), to: Open.self)
        f(x, sel, url as NSURL, NSDictionary(), nil)
        return
      }
      r = x.next
    }
  }
}
