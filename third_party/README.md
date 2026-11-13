# Vendored packages (copied from Magic Sign, apps/mobile/third_party)

- `flutter_inappwebview_android` 1.1.3 from pub.dev, patched for Android Gradle
  Plugin 9: `proguard-android.txt` → `proguard-android-optimize.txt` and
  `lintOptions` → `lint` in `android/build.gradle`. Drop it once upstream ships
  a fix.

Both `flutter_inappwebview_android` 1.1.3 and `flutter_inappwebview_ios` 1.1.2
also read an extra `msProfile` key in the initial settings (see
`ProfileSettings` in `lib/main.dart`): the WebView then keeps its cookies and
storage in that profile.

- Android: `WebViewCompat.setProfile` (WebView 123+, `MULTI_PROFILE`), in
  `FlutterWebView.java` right after the WebView is created.
- iOS 17+: `WKWebsiteDataStore(forIdentifier:)` with the profile UUID, in
  `FlutterWebViewController.swift`.
