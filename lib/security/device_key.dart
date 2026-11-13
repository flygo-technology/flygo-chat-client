// Khoá thiết bị cho "Thiết bị" / xác thực từ xa (Sếp, 2026-11-09: đây là tính năng xác thực, không phải bảo mật).
// Khoá EC P-256 tạo trong phần cứng an toàn của máy (Android Keystore / StrongBox, iOS Secure Enclave), không xuất được;
// mỗi lần ký phải qua vân tay / khuôn mặt, thêm sinh trắc mới thì khoá mất hiệu lực. Khoá bí mật không bao giờ rời máy;
// chỉ khoá công khai được đăng ký với Flygo ID. Native: android/.../DeviceKey.kt, ios/Runner/AppDelegate.swift (DeviceKey).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart';

import '../browser/flygo_id.dart';

/// Trạng thái khoá thiết bị trên máy này.
class DeviceKeyStatus {
  const DeviceKeyStatus({
    required this.supported,
    required this.biometric,
    required this.enrolled,
    required this.hwBacked,
    required this.biometricBound,
    this.publicKey,
  });

  /// Nền tảng có khoá thiết bị (điện thoại). Máy tính: chưa ("không hỗ trợ").
  final bool supported;

  /// Sinh trắc học: ok, none_enrolled (chưa cài vân tay / khuôn mặt), no_hardware, unavailable.
  final String biometric;

  /// Đã có khoá trên máy.
  final bool enrolled;

  /// Khoá nằm trong phần cứng an toàn (TEE / StrongBox / Secure Enclave).
  final bool hwBacked;

  /// Mỗi lần ký phải xác thực sinh trắc.
  final bool biometricBound;

  /// Khoá công khai: base64 của điểm X9.62 không nén (65 byte, 0x04‖X‖Y).
  final String? publicKey;

  /// Dùng được để xác thực (có sinh trắc).
  bool get available => supported && biometric == 'ok';

  /// Câu hiển thị ngắn cho trang "Thiết bị".
  String get label {
    if (!supported) return 'Không hỗ trợ';
    if (biometric == 'none_enrolled') return 'Không hỗ trợ (máy chưa cài vân tay / khuôn mặt)';
    if (biometric != 'ok') return 'Không hỗ trợ';
    if (!enrolled) return 'Chưa đăng ký';
    return hwBacked ? 'Khoá phần cứng · vân tay / khuôn mặt' : 'Khoá phần mềm · vân tay / khuôn mặt';
  }

  static DeviceKeyStatus fromMap(Map m) => DeviceKeyStatus(
        supported: m['supported'] == true,
        biometric: '${m['biometric'] ?? 'unavailable'}',
        enrolled: m['enrolled'] == true,
        hwBacked: m['hw_backed'] == true,
        biometricBound: m['biometric_bound'] == true,
        publicKey: m['public_key'] as String?,
      );

  static const unsupported =
      DeviceKeyStatus(supported: false, biometric: 'unavailable', enrolled: false, hwBacked: false, biometricBound: false);
}

/// Lỗi của khoá thiết bị. [code]: cancelled (người dùng huỷ), auth, no_key, invalidated (sinh trắc đã đổi: đăng ký lại),
/// devicekey.
class DeviceKeyException implements Exception {
  DeviceKeyException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class DeviceKey {
  DeviceKey._();

  static const _ch = MethodChannel('flygo/devicekey');

  static bool get platformSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<T> _call<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args) as T;
    } on PlatformException catch (e) {
      throw DeviceKeyException(e.code, e.message ?? e.code);
    }
  }

  static Future<DeviceKeyStatus> status() async {
    if (!platformSupported) return DeviceKeyStatus.unsupported;
    try {
      return DeviceKeyStatus.fromMap(await _call<Map>('status'));
    } catch (_) {
      return DeviceKeyStatus.unsupported;
    }
  }

  /// Tạo khoá mới trên máy (khoá cũ bị xoá). Đăng ký khoá công khai với Flygo ID là việc của nơi gọi
  /// (xem [DeviceKeyStatus.publicKey]).
  static Future<DeviceKeyStatus> create() async {
    if (!platformSupported) throw DeviceKeyException('unsupported', 'Không hỗ trợ trên máy này');
    return DeviceKeyStatus.fromMap(await _call<Map>('create'));
  }

  /// Xoá khoá trên máy.
  static Future<void> delete() async {
    if (!platformSupported) return;
    await _call<bool>('delete');
  }

  /// Đăng ký máy này cho xác thực từ xa: tạo khoá (thay khoá cũ), báo thiết bị và gửi khoá công khai lên Flygo ID.
  static Future<DeviceKeyStatus> enroll({required String chatToken, required String name}) async {
    final id = await FlygoId.current(chatToken);
    if (id == null) throw DeviceKeyException('no_flygo_id', 'Máy chủ chat này chưa có Flygo ID');
    final s = await create();
    final pub = s.publicKey;
    if (pub == null) throw DeviceKeyException('devicekey', 'Không đọc được khoá công khai');
    try {
      await id.registerDevice(name: name, platform: Platform.operatingSystem, os: Platform.operatingSystemVersion);
      await id.enrollDeviceKey(pub: pub, hwBacked: s.hwBacked, biometricBound: s.biometricBound);
    } catch (e) {
      // Không đăng ký được: không để lại khoá "mồ côi" trên máy.
      await delete();
      throw DeviceKeyException('enroll', 'Không đăng ký được với Flygo ID: $e');
    }
    return s;
  }

  /// Bỏ đăng ký: xoá khoá trên Flygo ID (nếu được) và trên máy.
  static Future<void> remove({required String chatToken}) async {
    try {
      await (await FlygoId.current(chatToken))?.removeDeviceKey();
    } finally {
      await delete();
    }
  }

  /// Chuỗi được ký khi đồng ý một yêu cầu xác thực (devices-verify.md):
  /// "flygo-verify-v1\n" + id + "\n" + hex(sha256(details_json)) + "\n" + code.
  static Uint8List verifyMessage(String requestId, String detailsJson, String code) => Uint8List.fromList(
        utf8.encode('flygo-verify-v1\n$requestId\n${sha256.convert(utf8.encode(detailsJson))}\n$code'),
      );

  /// Ký [message] sau khi người dùng xác thực sinh trắc (hộp hệ thống hiện [title] / [subtitle]).
  /// Trả về chữ ký ECDSA P-256 / SHA-256 dạng DER, base64.
  static Future<String> sign(Uint8List message, {required String title, String subtitle = ''}) async {
    if (!platformSupported) throw DeviceKeyException('unsupported', 'Không hỗ trợ trên máy này');
    return _call<String>('sign', {'data': base64Encode(message), 'title': title, 'subtitle': subtitle});
  }
}
