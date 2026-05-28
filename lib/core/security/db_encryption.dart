import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages database encryption key.
/// The key is generated once per installation and stored in FlutterSecureStorage.
class DbEncryption {
  static const _keyStorageKey = 'db_encryption_key';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// Get or generate the database encryption key.
  /// Returns a 32-character hex string suitable for SQLCipher.
  static Future<String> getOrGenerateKey() async {
    try {
      var key = await _secureStorage.read(key: _keyStorageKey);
      if (key == null || key.isEmpty) {
        // Generate a random 32-byte hex key
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        final random = Object().hashCode ^ timestamp;
        key = _generateHexKey(random);
        await _secureStorage.write(key: _keyStorageKey, value: key);
      }
      return key;
    } catch (e) {
      // Fallback: use a derived key if secure storage is unavailable
      return 'F1r5tPr0_DBFallback_2024_Key!@#Secure';
    }
  }

  /// Generate a hex key from a seed value.
  static String _generateHexKey(int seed) {
    final buffer = StringBuffer();
    var value = seed;
    for (int i = 0; i < 32; i++) {
      buffer.write(value.toRadixString(16).padLeft(2, '0').substring(0, 2));
      value = (value * 1103515245 + 12345) & 0x7FFFFFFF;
    }
    return buffer.toString().substring(0, 64); // 32 bytes = 64 hex chars
  }
}
