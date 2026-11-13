import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_chat/browser/bridge_policy.dart';
import 'package:flygo_chat/browser/model.dart';
import 'package:flygo_chat/browser/url_pattern.dart';

final kyso = ExtensionManifest.fromJson({
  'id': 'vn.flygo.kyso',
  'api_origins': {'main': {'url': 'env:SERVER'}},
  'host_origins': {'relay': {'url': 'wss://remote-sign-relay.flygo.vn'}},
  'extension': {
    'background': {'page': '/app/engine.html', 'compat': 'chrome'},
    'content_scripts': {
      'inject': {'js': '/ext/inject.js', 'match': ['https://*/*'], 'world': 'MAIN'},
    },
    'ports': {'magic-sign': {'to': 'background'}},
    'messages': {'web_status': {'to': 'background'}},
    'space_provider': true,
    'space_origins': {
      'thue': {'pattern': 'https://*.gdt.gov.vn/*'},
      'minvoice': {'pattern': 'https://*.minvoice.net/*'},
    },
  },
}, base: 'assets/magicsign/');

const env = {'SERVER': 'https://kyso.example.com'};

void main() {
  group('UrlPattern', () {
    test('miền con, scheme, đường dẫn', () {
      final p = UrlPattern.tryParse('https://*.gdt.gov.vn/*')!;
      expect(p.matches(Uri.parse('https://dichvucong.gdt.gov.vn/tthc/home')), isTrue);
      expect(p.matches(Uri.parse('https://gdt.gov.vn/')), isTrue);
      expect(p.matches(Uri.parse('http://dichvucong.gdt.gov.vn/')), isFalse);
      expect(p.matches(Uri.parse('https://gdt.gov.vn.evil.com/')), isFalse);
      expect(p.matches(Uri.parse('https://evilgdt.gov.vn/')), isFalse);
      final q = UrlPattern.tryParse('https://epayment.customs.gov.vn/epaymentportal/*')!;
      expect(q.matches(Uri.parse('https://epayment.customs.gov.vn/epaymentportal/home')), isTrue);
      expect(q.matches(Uri.parse('https://epayment.customs.gov.vn/other')), isFalse);
      expect(UrlPattern.tryParse('https://evil*.com/*'), isNull);
      expect(UrlPattern.tryParse('ftp://x/'), isNull);
    });

    test('within: mẫu trong khung', () {
      final outer = UrlPattern.tryParse('https://*.gdt.gov.vn/*')!;
      expect(UrlPattern.tryParse('https://dichvucong.gdt.gov.vn/tthc/*')!.within(outer), isTrue);
      expect(UrlPattern.tryParse('https://*.gdt.gov.vn/*')!.within(outer), isTrue);
      expect(UrlPattern.tryParse('https://*.gov.vn/*')!.within(outer), isFalse);
      expect(UrlPattern.tryParse('*://dichvucong.gdt.gov.vn/*')!.within(outer), isFalse);
      expect(UrlPattern.tryParse('https://*/*')!.within(outer), isFalse);
    });
  });

  test('space động bị cắt về space_origins của extension', () {
    final space = Space.fromJson({
      'id': 'vn.flygo.kyso/fpt:7e3f04',
      'name': 'Ký số CÔNG TY TNHH ABC CAPITAL',
      'whitelist': {
        'a': {'pattern': 'https://dichvucong.gdt.gov.vn/*'},
        'b': {'pattern': 'https://0100000000.minvoice.net/*'},
        'c': {'pattern': 'https://mail.google.com/*'},
      },
      'bookmarks': {
        'x': {'title': 'Thuế', 'url': 'https://dichvucong.gdt.gov.vn/tthc/home'},
        'y': {'title': 'Mail', 'url': 'https://mail.google.com/'},
      },
      'provider': 'vn.flygo.kyso',
    });
    final (clamped, dropped) = clampToProvider(space, kyso);
    expect(dropped, ['https://mail.google.com/*']);
    expect(clamped.allows('https://dichvucong.gdt.gov.vn/tthc/home'), isTrue);
    expect(clamped.allows('https://mail.google.com/'), isFalse);
    expect(clamped.bookmarks.map((b) => b.title), ['Thuế']);
  });

  group('checkFetch', () {
    test('api origin theo env: gắn vé; wss cùng host cũng là api', () {
      final d = checkFetch(surface: Surface.background, manifest: kyso, env: env, url: 'https://kyso.example.com/api/me', headers: {});
      expect(d.ticket, isTrue);
      expect(checkFetch(surface: Surface.background, manifest: kyso, env: env, url: 'wss://kyso.example.com/api/relay', headers: {}).ticket, isTrue);
    });

    test('host_origins: không vé, chỉ background', () {
      final d = checkFetch(surface: Surface.background, manifest: kyso, env: env, url: 'wss://remote-sign-relay.flygo.vn/v1', headers: {});
      expect(d.ticket, isFalse);
      expect(
        () => checkFetch(surface: Surface.web, manifest: kyso, env: env, url: 'wss://remote-sign-relay.flygo.vn/v1', headers: {}),
        throwsA(isA<BridgeError>().having((e) => e.code, 'code', 'NOT_ALLOWED_ORIGIN')),
      );
    });

    test('chặn: origin lạ, http, header cấm, content script, quá cỡ', () {
      Matcher code(String c) => throwsA(isA<BridgeError>().having((e) => e.code, 'code', c));
      expect(() => checkFetch(surface: Surface.background, manifest: kyso, env: env, url: 'https://evil.com/', headers: {}), code('NOT_ALLOWED_ORIGIN'));
      expect(() => checkFetch(surface: Surface.background, manifest: kyso, env: env, url: 'http://kyso.example.com/', headers: {}), code('NOT_ALLOWED_ORIGIN'));
      for (final h in ['Authorization', 'cookie', 'X-Flygo-Device', 'Sec-Fetch-Site', 'Proxy-Authorization', 'DPoP']) {
        expect(() => checkFetch(surface: Surface.background, manifest: kyso, env: env, url: 'https://kyso.example.com/', headers: {h: 'x'}), code('FORBIDDEN_HEADER'));
      }
      expect(() => checkFetch(surface: Surface.content, manifest: kyso, env: env, url: 'https://kyso.example.com/', headers: {}), code('UNSUPPORTED_CONTEXT'));
      expect(
        () => checkFetch(surface: Surface.background, manifest: kyso, env: env, url: 'https://kyso.example.com/', headers: {}, bodyBytes: kMaxRequestBytes + 1),
        code('TOO_LARGE'),
      );
      // env thiếu: api origin không xác định được.
      expect(() => checkFetch(surface: Surface.background, manifest: kyso, env: const {}, url: 'https://kyso.example.com/', headers: {}), code('NOT_ALLOWED_ORIGIN'));
    });
  });

  test('content script: chỉ loại tin và port đã khai', () {
    checkContentMessage(manifest: kyso, type: 'web_status');
    checkContentMessage(manifest: kyso, port: 'magic-sign');
    expect(() => checkContentMessage(manifest: kyso, type: 'login'), throwsA(isA<BridgeError>()));
    expect(() => checkContentMessage(manifest: kyso, port: 'other'), throwsA(isA<BridgeError>()));
  });

  test('lọc header phản hồi', () {
    expect(filterResponseHeaders({'Set-Cookie': 'a', 'content-type': 'x', 'X-Flygo-Debug': '1', 'WWW-Authenticate': 'Bearer'}), {'content-type': 'x'});
  });

  test('nonce: tin của trang trước bị bỏ', () {
    final n = NavigationNonce();
    expect(n.accepts('a'), isFalse);
    var i = 0;
    final first = n.next(() => 'n${i++}');
    expect(n.accepts(first), isTrue);
    n.next(() => 'n${i++}');
    expect(n.accepts(first), isFalse);
    expect(n.accepts(null), isFalse);
  });
}
