import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:firstpro/core/license/license_constants.dart';

/// Generates a unique device fingerprint and manages installation ID.
class DeviceFingerprint {
  DeviceFingerprint._();
  static final DeviceFingerprint instance = DeviceFingerprint._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const _uuid = Uuid();

  /// Generate a SHA-256 device fingerprint based on hardware info.
  Future<String> generate() async {
    final deviceInfo = DeviceInfoPlugin();
    final buffer = StringBuffer();

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      buffer.write(android.brand);
      buffer.write(android.manufacturer);
      buffer.write(android.model);
      buffer.write(android.hardware);
      buffer.write(android.display);
      buffer.write(android.fingerprint);
      buffer.write(android.device);
      buffer.write(android.board);
      // androidId is a stable identifier on Android
      buffer.write(android.id);
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      buffer.write(ios.name);
      buffer.write(ios.systemName);
      buffer.write(ios.model);
      buffer.write(ios.identifierForVendor);
    }

    final fingerprint = sha256.convert(buffer.toString().codeUnits).toString();
    if (kDebugMode) {
      debugPrint('Device fingerprint: $fingerprint');
    }
    return fingerprint;
  }

  /// Get or create a unique installation ID.
  /// Stored in FlutterSecureStorage so it persists across app restarts.
  Future<String> getInstallationId() async {
    try {
      final existing = await _secureStorage.read(
        key: LicenseConstants.installationIdKey,
      );
      if (existing != null && existing.isNotEmpty) {
        return existing;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error reading installation_id: $e');
    }

    // Generate new installation ID
    final newId = _uuid.v4();
    try {
      await _secureStorage.write(
        key: LicenseConstants.installationIdKey,
        value: newId,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Error writing installation_id: $e');
    }
    return newId;
  }

  /// Get app version info.
  Future<Map<String, String>> getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    final info = <String, String>{};

    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      info['app_version'] = '2.0.0';
      info['os_version'] = 'Android ${android.version.release}';
      info['device_model'] = '${android.manufacturer} ${android.model}';
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      info['app_version'] = '2.0.0';
      info['os_version'] = '${ios.systemName} ${ios.systemVersion}';
      info['device_model'] = ios.utsname.machine;
    }

    return info;
  }
}
