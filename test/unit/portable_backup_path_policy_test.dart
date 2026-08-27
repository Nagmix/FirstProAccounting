import 'package:flutter_test/flutter_test.dart';

import 'package:firstpro/core/services/portable_backup_path_policy.dart';

void main() {
  test('resolves attachment entries only inside the staged attachments root', () {
    final resolved = PortableBackupPathPolicy.resolveAttachmentPath(
      archiveEntryName: 'attachments/invoices/receipt.png',
      stagedAttachmentsPath: '/tmp/attachments.restore.tmp',
    );

    expect(resolved, '/tmp/attachments.restore.tmp/invoices/receipt.png');
  });

  test('rejects attachment entries that escape the staged attachments root', () {
    expect(
      () => PortableBackupPathPolicy.resolveAttachmentPath(
        archiveEntryName: 'attachments/../../outside.txt',
        stagedAttachmentsPath: '/tmp/attachments.restore.tmp',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('ignores non-attachment archive entries', () {
    expect(
      PortableBackupPathPolicy.resolveAttachmentPath(
        archiveEntryName: 'documents/receipt.png',
        stagedAttachmentsPath: '/tmp/attachments.restore.tmp',
      ),
      isNull,
    );
  });
}

