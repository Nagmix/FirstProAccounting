import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:firstpro/core/services/portable_backup_file_committer.dart';

void main() {
  late Directory root;
  late String databasePath;
  late String stagedDatabasePath;
  late String rollbackPath;
  late String attachmentsPath;
  late String stagedAttachmentsPath;
  late String attachmentsRollbackPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('firstpro_restore_commit_');
    databasePath = '${root.path}/live.db';
    stagedDatabasePath = '${root.path}/staged.db';
    rollbackPath = '${root.path}/rollback.db';
    attachmentsPath = '${root.path}/attachments';
    stagedAttachmentsPath = '${root.path}/attachments.staged';
    attachmentsRollbackPath = '${root.path}/attachments.rollback';

    await File(databasePath).writeAsString('old database');
    await File(stagedDatabasePath).writeAsString('new database');
    await Directory(attachmentsPath).create();
    await File('$attachmentsPath/old.txt').writeAsString('old attachment');
    await Directory(stagedAttachmentsPath).create();
    await File('$stagedAttachmentsPath/new.txt').writeAsString('new attachment');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  PortableBackupFileCommitter createCommitter() {
    return PortableBackupFileCommitter(
      databasePath: databasePath,
      stagedDatabasePath: stagedDatabasePath,
      rollbackPath: rollbackPath,
      attachmentsPath: attachmentsPath,
      stagedAttachmentsPath: stagedAttachmentsPath,
      attachmentsRollbackPath: attachmentsRollbackPath,
    );
  }

  test('restores old database and attachments when post-swap step fails', () async {
    final committer = createCommitter();

    await expectLater(
      committer.commit(
        afterDatabaseSwap: () async {
          throw StateError('simulated restore failure');
        },
        onRollback: () async {},
      ),
      throwsA(isA<StateError>()),
    );

    expect(await File(databasePath).readAsString(), 'old database');
    expect(await File('$attachmentsPath/old.txt').readAsString(), 'old attachment');
    expect(await File(stagedDatabasePath).exists(), isFalse);
    expect(await Directory(stagedAttachmentsPath).exists(), isFalse);
    expect(await File(rollbackPath).exists(), isFalse);
    expect(await Directory(attachmentsRollbackPath).exists(), isFalse);
  });

  test('commits staged database and attachments together', () async {
    final committer = createCommitter();

    await committer.commit(
      afterDatabaseSwap: () async {},
      onRollback: () async {},
    );

    expect(await File(databasePath).readAsString(), 'new database');
    expect(await File('$attachmentsPath/new.txt').readAsString(), 'new attachment');
    expect(await File('$attachmentsPath/old.txt').exists(), isFalse);
    expect(await File(stagedDatabasePath).exists(), isFalse);
    expect(await Directory(stagedAttachmentsPath).exists(), isFalse);
  });
}

