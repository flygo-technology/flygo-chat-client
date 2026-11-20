// Bảng trắng trên macOS: không gọi setBackgroundColor (WKWebView/AppKit ném lỗi -> trang không tải, màn trắng) mà vẫn tải trang.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/ui/meet/extras/board.dart';
import 'package:webview_flutter/webview_flutter.dart';

class _FakeWeb implements WebViewController {
  final bool throwOnBackground;
  final calls = <String>[];
  _FakeWeb({this.throwOnBackground = false});
  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async => calls.add('js');
  @override
  Future<void> setBackgroundColor(Color color) {
    calls.add('bg');
    if (throwOnBackground) throw UnimplementedError('setBackgroundColor is not implemented on macOS');
    return Future.value();
  }

  @override
  Future<void> loadRequest(Uri uri, {LoadRequestMethod method = LoadRequestMethod.get, Map<String, String> headers = const {}, Uint8List? body}) async =>
      calls.add('load ${uri.path}');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final url = Uri.parse('https://push.flygo.vn/meet/extras/board-web/index.html?b=abc-defg-hij&t=x');
  test('macOS: không đặt màu nền, vẫn tải trang', () {
    final w = _FakeWeb(throwOnBackground: true);
    configureBoardWeb(w, url, isMacOS: true);
    expect(w.calls, ['js', 'load /meet/extras/board-web/index.html']);
  });
  test('nền tảng khác: đặt nền trắng; nếu nền tảng ném lỗi vẫn tải trang', () {
    final ok = _FakeWeb();
    configureBoardWeb(ok, url, isMacOS: false);
    expect(ok.calls, ['js', 'bg', 'load /meet/extras/board-web/index.html']);
    final bad = _FakeWeb(throwOnBackground: true);
    configureBoardWeb(bad, url, isMacOS: false);
    expect(bad.calls.last, 'load /meet/extras/board-web/index.html');
  });
}
