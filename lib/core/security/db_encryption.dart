import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Exception thrown when secure key storage fails and no fallback is allowed.
class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}

/// Manages database encryption key.
/// The key is generated once per installation and stored in FlutterSecureStorage.
///
/// If secure storage is unavailable (e.g. on rooted devices or after re-install),
/// a [SecurityException] is thrown instead of falling back to a hardcoded key.
/// This prevents silently decrypting the database with a publicly known key.
class DbEncryption {
  static const _keyStorageKey = 'db_encryption_key';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Get or generate the database encryption key.
  /// Returns a 64-character hex string (32 bytes) suitable for SQLCipher.
  ///
  /// Throws [SecurityException] if secure storage is unavailable — the caller
  /// should inform the user rather than proceeding with an insecure key.
  static Future<String> getOrGenerateKey() async {
    try {
      var key = await _secureStorage.read(key: _keyStorageKey);
      if (key == null || key.isEmpty) {
        // Generate a cryptographically random 32-byte hex key
        final bytes =
            List<int>.generate(32, (_) => Random.secure().nextInt(256));
        key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        await _secureStorage.write(key: _keyStorageKey, value: key);
      }
      return key;
    } catch (e) {
      // Do NOT fall back to a hardcoded key — that would expose all user data
      // to anyone who reads the source code. Instead, surface the failure.
      debugPrint('DbEncryption: secure storage unavailable: $e');
      throw const SecurityException(
        'فشل الوصول إلى مخزن المفاتيح الآمن. لا يمكن فتح قاعدة البيانات المشفرة.',
      );
    }
  }
}
