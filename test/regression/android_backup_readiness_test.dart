import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest protects SQLCipher data and opts into modern back', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
    expect(manifest, contains('android:dataExtractionRules='));
  });

  test('portable backup remains password protected and validated at the boundary', () {
    final source = File(
      'lib/core/services/portable_backup_service.dart',
    ).readAsStringSync();

    expect(source, contains("static const _minimumPasswordLength = 8"));
    expect(source, contains('_validatePassword(password)'));
    expect(source, contains('Hmac(sha256'));
    expect(source, contains('db_key.txt'));
  });
}
