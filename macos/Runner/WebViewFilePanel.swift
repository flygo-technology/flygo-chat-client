import Cocoa
import WebKit

/// Ô chọn tệp (`<input type=file>`, cả `webkitdirectory`) trong webview mini app. webview_flutter_wkwebview không cài
/// `webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)` của WKUIDelegate trên macOS, nên WebKit bỏ qua cú
/// bấm chọn tệp (iOS có sẵn bảng chọn của hệ thống, macOS thì không). Gắn thêm phương thức đó vào lớp UIDelegate của
/// plugin, trước khi có webview nào: WebKit chỉ xem delegate có những phương thức nào lúc được gán.
enum WebViewFilePanel {
  static let selector = NSSelectorFromString("webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:")

  static func install(className: String = "webview_flutter_wkwebview.UIDelegateImpl") {
    guard let cls = NSClassFromString(className) else {
      NSLog("WebViewFilePanel: class \(className) not found")
      return
    }
    // Bản plugin sau này tự có thì để nguyên.
    if class_getInstanceMethod(cls, selector) != nil { return }
    let impl: @convention(block) (AnyObject, WKWebView, WKOpenPanelParameters, WKFrameInfo, @escaping ([URL]?) -> Void) -> Void = {
      _, webView, params, _, done in
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = params.allowsMultipleSelection
      // `webkitdirectory`: chọn thư mục (trang nhận mọi tệp trong đó), không chọn tệp lẻ.
      panel.canChooseDirectories = params.allowsDirectories
      panel.canChooseFiles = !params.allowsDirectories
      panel.resolvesAliases = true
      if let window = webView.window {
        panel.beginSheetModal(for: window) { r in done(r == .OK ? panel.urls : nil) }
      } else {
        done(panel.runModal() == .OK ? panel.urls : nil)
      }
    }
    class_addMethod(cls, selector, imp_implementationWithBlock(impl), "v@:@@@@?")
  }
}
