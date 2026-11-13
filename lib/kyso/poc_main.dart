// Chạy riêng phần Ký số để thử trên từng nền tảng, không cần đăng nhập Flygo:
//   flutter run -t lib/kyso/poc_main.dart
// KYSO_TEST_URL: mở thẳng trình duyệt (không token) tại địa chỉ này, để kiểm tra extension trên một trang bất kỳ.
import 'package:flutter/material.dart';

import '../browser/browser_page.dart';

const _testUrl = String.fromEnvironment('KYSO_TEST_URL');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    title: 'Ký số (thử)',
    theme: ThemeData(colorSchemeSeed: const Color(0xFF7B61FF), useMaterial3: true),
    home: _testUrl.isEmpty ? const KysoHomePage() : const _TestBrowser(),
  ));
}

class _TestBrowser extends StatefulWidget {
  const _TestBrowser();

  @override
  State<_TestBrowser> createState() => _TestBrowserState();
}

class _TestBrowserState extends State<_TestBrowser> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => openKysoBrowser(context, {
        'tokenId': 'test',
        'companyName': 'THỬ',
        'pins': [
          {'title': 'Thử', 'url': _testUrl},
        ],
      }, url: _testUrl),
    );
  }

  @override
  Widget build(BuildContext context) => const KysoHomePage();
}
