import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portable restore stages attachments before committing the database', () {
    final source = File(
      'lib/core/services/portable_backup_service.dart',
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
      'lib/core/services/portable_backup_service.dart',
    ).readAsStringSync();

    expect(source, contains('rollbackExists'),
        reason: 'Rollback must be attempted whenever the saved copy exists.');
    expect(source, contains('await _dbHelper.database'),
        reason: 'The replacement must be reopened before old files are deleted.');
  });
}
