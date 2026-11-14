// Máy chủ ảnh giả cho ảnh xem trước: ảnh chân dung vẽ bằng canvas, không cần mạng.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ảnh "chân dung" giả: nền màu + hình tròn sáng, không vuông góc với khung để thấy rõ mép cắt.
Future<List<int>> _photo(int seed) async {
  final r = ui.PictureRecorder();
  final c = Canvas(r);
  const s = 256.0;
  c.drawRect(const Rect.fromLTWH(0, 0, s, s), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(s, s), [Color(0xFF000000 | (0x8E44AD + seed * 0x2F1B3D) & 0xFFFFFF), Color(0xFF000000 | (0xF39C12 + seed * 0x13579B) & 0xFFFFFF)]));
  c.drawCircle(const Offset(s / 2, s * .42), s * .2, Paint()..color = const Color(0xFFFFE0C2));
  c.drawOval(Rect.fromCenter(center: const Offset(s / 2, s * 1.0), width: s * .8, height: s * .7), Paint()..color = const Color(0xFF2C3E50));
  final img = await r.endRecording().toImage(256, 256);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// Mọi ảnh mạng trả về một trong vài ảnh giả (chọn theo đường dẫn), để ảnh xem trước giống app thật.
Future<void> useFakePhotos(WidgetTester t) async {
  final photos = (await t.runAsync(() async => [for (var i = 0; i < 6; i++) await _photo(i)]))!;
  HttpOverrides.global = _Http(photos);
}

class _Http extends HttpOverrides {
  final List<List<int>> photos;
  _Http(this.photos);
  @override
  HttpClient createHttpClient(SecurityContext? c) => _Client(photos);
}

class _Client implements HttpClient {
  final List<List<int>> photos;
  _Client(this.photos);
  List<int> _pick(Uri url) => photos[url.toString().hashCode.abs() % photos.length];
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Req(_pick(url));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _Req(_pick(url));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Req implements HttpClientRequest {
  final List<int> bytes;
  _Req(this.bytes);
  @override
  HttpHeaders get headers => _Headers();
  @override
  Future<HttpClientResponse> close() async => _Res(bytes);
  @override
  Future<void> addStream(Stream<List<int>> s) => s.drain<void>();
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Headers implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Res extends Stream<List<int>> implements HttpClientResponse {
  final List<int> bytes;
  _Res(this.bytes);
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpHeaders get headers => _Headers();
  @override
  String get reasonPhrase => 'OK';
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([bytes]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

