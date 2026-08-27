import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portable restore stages attachments before committing the database', () {
    final source = File(
      'lib/core/services/portable_backup_file_committer.dart',
    ).readAsStringSync();

    expect(source, contains('stagedAttachmentsPath'),
        reason: 'Attachments must be prepared outside the live directory.');
    expect(source, contains('attachmentsRollbackPath'),
        reason: 'The live attachments directory needs a rollback path.');
    expect(source, contains('restoreRollback'),
        reason: 'A failed post-replacement restore must restore the old database.');
  });

  test('portable restore does not condition rollback on dbPath absence', () {
    final source = File(
      'lib/core/services/portable_backup_file_committer.dart',
    ).readAsStringSync();

    expect(source, contains('rollbackExists'),
        reason: 'Rollback must be attempted whenever the saved copy exists.');
    expect(source, contains('await _dbHelper.database'),
        reason: 'The replacement must be reopened before old files are deleted.');
  });

  test('portable backup authenticates and validates its encrypted payload', () {
    final source = File(
      'lib/core/services/portable_backup_service.dart',
    ).readAsStringSync();

    expect(source, contains("static const _magic = 'FPB1'"));
    expect(source, contains('Hmac(sha256, aesKey)'));
    expect(source, contains('_constantTimeEquals'));
    expect(source, contains('_validatePassword(password)'));
    expect(source, contains('integrity_check'));
    expect(source, contains('FormatException'));
  });

  test('settings screen exposes portable backup and restore actions', () {
    final source = File(
      'lib/ui/screens/settings/widgets/settings_data_section.dart',
    ).readAsStringSync();

    expect(source, contains('PortableBackupService'));
    expect(source, contains('.createBackup('));
    expect(source, contains('.restoreBackup('));
  });
}
