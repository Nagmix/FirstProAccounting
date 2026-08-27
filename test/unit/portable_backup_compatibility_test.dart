import 'package:flutter_test/flutter_test.dart';
import 'package:firstpro/core/services/portable_backup_compatibility.dart';

void main() {
  test('accepts current and older database schema versions', () {
    expect(() => PortableBackupCompatibility.validateSchemaVersion(1), returnsNormally);
    expect(() => PortableBackupCompatibility.validateSchemaVersion(59), returnsNormally);
  });

  test('rejects a backup created by a newer application', () {
    expect(
      () => PortableBackupCompatibility.validateSchemaVersion(60),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('أحدث من إصدار التطبيق'),
        ),
      ),
    );
  });

  test('rejects an invalid schema version', () {
    expect(
      () => PortableBackupCompatibility.validateSchemaVersion(0),
      throwsA(isA<FormatException>()),
    );
  });
}
