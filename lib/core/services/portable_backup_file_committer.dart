import 'dart:io';

class PortableBackupFileCommitter {
  PortableBackupFileCommitter({
    required this.databasePath,
    required this.stagedDatabasePath,
    required this.rollbackPath,
    required this.attachmentsPath,
    required this.stagedAttachmentsPath,
    required this.attachmentsRollbackPath,
  });

  final String databasePath;
  final String stagedDatabasePath;
  final String rollbackPath;
  final String attachmentsPath;
  final String stagedAttachmentsPath;
  final String attachmentsRollbackPath;

  List<String> get _liveSidecarPaths => ['$databasePath-wal', '$databasePath-shm'];

  List<String> get _rollbackSidecarPaths => [
        '$databasePath-wal.restore.backup',
        '$databasePath-shm.restore.backup',
      ];

  Future<void> commit({
    required Future<void> Function() afterDatabaseSwap,
    required Future<void> Function() onRollback,
    Future<void> Function(bool databaseWasRestored)? onRollbackComplete,
  }) async {
    var databaseRollbackPrepared = false;
    var attachmentsRollbackPrepared = false;

    try {
      final currentDatabase = File(databasePath);
      if (await currentDatabase.exists()) {
        await currentDatabase.copy(rollbackPath);
        databaseRollbackPrepared = true;
      }
      for (var i = 0; i < _liveSidecarPaths.length; i++) {
        final liveSidecar = File(_liveSidecarPaths[i]);
        if (await liveSidecar.exists()) {
          await liveSidecar.copy(_rollbackSidecarPaths[i]);
        }
      }

      if (await currentDatabase.exists()) await currentDatabase.delete();
      for (final sidecarPath in _liveSidecarPaths) {
        final sidecar = File(sidecarPath);
        if (await sidecar.exists()) await sidecar.delete();
      }
      await File(stagedDatabasePath).rename(databasePath);
      await afterDatabaseSwap();

      final liveAttachments = Directory(attachmentsPath);
      final stagedAttachments = Directory(stagedAttachmentsPath);
      final attachmentsRollback = Directory(attachmentsRollbackPath);
      if (await attachmentsRollback.exists()) {
        await attachmentsRollback.delete(recursive: true);
      }
      if (await liveAttachments.exists()) {
        await liveAttachments.rename(attachmentsRollbackPath);
        attachmentsRollbackPrepared = true;
      }
      if (await stagedAttachments.exists()) {
        await stagedAttachments.rename(attachmentsPath);
      }

      final rollback = File(rollbackPath);
      if (await rollback.exists()) await rollback.delete();
      for (final sidecarPath in _rollbackSidecarPaths) {
        final sidecar = File(sidecarPath);
        if (await sidecar.exists()) await sidecar.delete();
      }
      if (await attachmentsRollback.exists()) {
        await attachmentsRollback.delete(recursive: true);
      }
    } catch (_) {
      await onRollback();

      final staged = File(stagedDatabasePath);
      if (await staged.exists()) await staged.delete();

      final current = File(databasePath);
      final rollback = File(rollbackPath);
      final rollbackExists = databaseRollbackPrepared && await rollback.exists();
      if (rollbackExists) {
        if (await current.exists()) await current.delete();
        await rollback.rename(databasePath);
        for (var i = 0; i < _liveSidecarPaths.length; i++) {
          final rollbackSidecar = File(_rollbackSidecarPaths[i]);
          final liveSidecar = File(_liveSidecarPaths[i]);
          if (await rollbackSidecar.exists()) {
            if (await liveSidecar.exists()) await liveSidecar.delete();
            await rollbackSidecar.rename(liveSidecar.path);
          } else if (await liveSidecar.exists()) {
            await liveSidecar.delete();
          }
        }
      }

      final liveAttachments = Directory(attachmentsPath);
      final stagedAttachments = Directory(stagedAttachmentsPath);
      if (await stagedAttachments.exists()) {
        await stagedAttachments.delete(recursive: true);
      }
      final attachmentsRollback = Directory(attachmentsRollbackPath);
      final restoreAttachments = attachmentsRollbackPrepared &&
          await attachmentsRollback.exists();
      if (restoreAttachments) {
        if (await liveAttachments.exists()) {
          await liveAttachments.delete(recursive: true);
        }
        await attachmentsRollback.rename(attachmentsPath);
      }
      if (onRollbackComplete != null) {
        await onRollbackComplete(rollbackExists);
      }
      rethrow;
    }
  }
}

