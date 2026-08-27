import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

import 'package:firstpro/core/security/db_encryption.dart';
import 'package:firstpro/core/services/portable_backup_compatibility.dart';
import 'package:firstpro/core/services/portable_backup_file_committer.dart';
import 'package:firstpro/core/services/portable_backup_path_policy.dart';
import 'package:firstpro/data/datasources/database_helper.dart';

/// Portable, password-protected backup for a local installation.
///
/// The archive contains the SQLCipher database, its installation key, and
/// local attachments. The whole archive is encrypted before it is written;
/// the installation key is never written outside the encrypted payload.
class PortableBackupService {
  PortableBackupService(this._dbHelper);

  static const _magic = 'FPB1';
  static const _saltLength = 16;
  static const _ivLength = 16;
  static const _macLength = 32;
  static const _minimumPasswordLength = 8;

  final DatabaseHelper _dbHelper;

  Future<File> createBackup({required String password, required String outputPath}) async {
    _validatePassword(password);

    final dbPath = await _dbHelper.getDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw StateError('قاعدة البيانات غير موجودة');
    }

    // Close the connection before reading the encrypted file so the snapshot
    // cannot be taken in the middle of a write transaction.
    await _dbHelper.resetInstance();
    try {
      final databaseBytes = await dbFile.readAsBytes();
      final key = await DbEncryption.getOrGenerateKey();
      final archive = Archive();
      archive.addFile(ArchiveFile('database.db', databaseBytes.length, databaseBytes));
      archive.addFile(ArchiveFile('db_key.txt', utf8.encode(key).length, utf8.encode(key)));

      final documentsDir = await getApplicationDocumentsDirectory();
      final attachmentsDir = Directory(p.join(documentsDir.path, 'attachments'));
      if (await attachmentsDir.exists()) {
        await for (final entity in attachmentsDir.list(recursive: true)) {
          if (entity is File) {
            final relative = p.relative(entity.path, from: documentsDir.path);
            final bytes = await entity.readAsBytes();
            archive.addFile(ArchiveFile(relative, bytes.length, bytes));
          }
        }
      }

      final encodedZip = ZipEncoder().encode(archive);
      if (encodedZip == null) {
        throw StateError('تعذر ضغط قاعدة البيانات والمرفقات');
      }
      final zipBytes = Uint8List.fromList(encodedZip);
      final salt = _randomBytes(_saltLength);
      final iv = _randomBytes(_ivLength);
      final aesKey = _deriveKey(password, salt);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(aesKey), mode: encrypt.AESMode.cbc),
      );
      final encrypted = encrypter.encryptBytes(
        zipBytes,
        iv: encrypt.IV(Uint8List.fromList(iv)),
      );
      final payload = Uint8List.fromList(encrypted.bytes);
      final header = Uint8List.fromList([
        ...utf8.encode(_magic),
        ...salt,
        ...iv,
      ]);
      final mac = Hmac(sha256, aesKey).convert([...header, ...payload]).bytes;
      final result = Uint8List.fromList([...header, ...mac, ...payload]);
      return File(outputPath).writeAsBytes(result, flush: true);
    } finally {
      // Reopen for the rest of the application even if export fails.
      await _dbHelper.database;
    }
  }

  Future<void> restoreBackup({required String inputPath, required String password}) async {
    _validatePassword(password);
    final bytes = await File(inputPath).readAsBytes();
    final minimumLength = _magic.length + _saltLength + _ivLength + _macLength + 16;
    if (bytes.length < minimumLength || utf8.decode(bytes.sublist(0, 4)) != _magic) {
      throw const FormatException('ملف النسخة المحمولة غير صالح');
    }

    final saltStart = _magic.length;
    final ivStart = saltStart + _saltLength;
    final macStart = ivStart + _ivLength;
    final payloadStart = macStart + _macLength;
    final salt = bytes.sublist(saltStart, ivStart);
    final iv = bytes.sublist(ivStart, macStart);
    final expectedMac = bytes.sublist(macStart, payloadStart);
    final payload = bytes.sublist(payloadStart);
    final aesKey = _deriveKey(password, salt);
    final actualMac = Hmac(sha256, aesKey).convert([
      ...bytes.sublist(0, macStart),
      ...payload,
    ]).bytes;
    if (!_constantTimeEquals(expectedMac, actualMac)) {
      throw const FormatException('كلمة المرور خاطئة أو الملف تالف');
    }

    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(aesKey), mode: encrypt.AESMode.cbc),
    );
    final decrypted = encrypter.decryptBytes(
      encrypt.Encrypted(Uint8List.fromList(payload)),
      iv: encrypt.IV(Uint8List.fromList(iv)),
    );
    final archive = ZipDecoder().decodeBytes(decrypted);
    final databaseEntry = archive.findFile('database.db');
    final keyEntry = archive.findFile('db_key.txt');
    if (databaseEntry == null || keyEntry == null) {
      throw const FormatException('النسخة لا تحتوي قاعدة البيانات أو مفتاحها');
    }
    final databaseBytes = Uint8List.fromList(databaseEntry.content as List<int>);
    final dbKey = utf8.decode(keyEntry.content as List<int>).trim();
    if (dbKey.length != 64 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(dbKey)) {
      throw const FormatException('مفتاح قاعدة البيانات داخل النسخة غير صالح');
    }

    final dbPath = await _dbHelper.getDatabasePath();
    final currentKey = await DbEncryption.getOrGenerateKey();
    final rollbackPath = '$dbPath.restore.backup';
    final stagedDatabasePath = '$dbPath.restore.tmp';
    final documentsDir = await getApplicationDocumentsDirectory();
    final stagedAttachmentsPath =
        '${p.join(documentsDir.path, 'attachments')}.restore.tmp';
    final attachmentsRoot = p.join(documentsDir.path, 'attachments');
    final attachmentsRollbackPath = '$attachmentsRoot.restore.backup';
    var keyChanged = false;
    var commitStarted = false;

    try {
      await File(stagedDatabasePath).writeAsBytes(databaseBytes, flush: true);
      final validationDb = await sqflite.openDatabase(
        stagedDatabasePath,
        version: 1,
        readOnly: true,
        password: dbKey,
      );
      try {
        final versionRows = await validationDb.rawQuery('PRAGMA user_version');
        final schemaVersion = versionRows.isNotEmpty
            ? (versionRows.first.values.first as num?)?.toInt() ?? 0
            : 0;
        PortableBackupCompatibility.validateSchemaVersion(schemaVersion);

        final result = await validationDb.rawQuery('PRAGMA integrity_check');
        final integrity = result.isNotEmpty
            ? result.first.values.first.toString().toLowerCase()
            : '';
        if (integrity != 'ok') {
          throw const FormatException('قاعدة النسخة المحمولة تالفة');
        }
      } finally {
        await validationDb.close();
      }

      final stagedAttachmentsDir = Directory(stagedAttachmentsPath);
      if (await stagedAttachmentsDir.exists()) {
        await stagedAttachmentsDir.delete(recursive: true);
      }
      await stagedAttachmentsDir.create(recursive: true);
      for (final entry in archive) {
        if (!entry.isFile ||
            entry.name == 'database.db' ||
            entry.name == 'db_key.txt') continue;
        final targetPath = PortableBackupPathPolicy.resolveAttachmentPath(
          archiveEntryName: entry.name,
          stagedAttachmentsPath: stagedAttachmentsPath,
        );
        if (targetPath == null) continue;
        final target = File(targetPath);
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.content as List<int>, flush: true);
      }

      final committer = PortableBackupFileCommitter(
        databasePath: dbPath,
        stagedDatabasePath: stagedDatabasePath,
        rollbackPath: rollbackPath,
        attachmentsPath: attachmentsRoot,
        stagedAttachmentsPath: stagedAttachmentsPath,
        attachmentsRollbackPath: attachmentsRollbackPath,
      );
      commitStarted = true;
      await committer.commit(
        afterDatabaseSwap: () async {
          await DbEncryption.setKey(dbKey);
          keyChanged = true;
          await _dbHelper.database;
        },
        onRollback: () async {
          await _dbHelper.resetInstance();
        },
        onRollbackComplete: (databaseWasRestored) async {
          if (keyChanged) await DbEncryption.setKey(currentKey);
          if (databaseWasRestored) await _dbHelper.database;
        },
      );
    } catch (_) {
      if (!commitStarted) {
        final staged = File(stagedDatabasePath);
        if (await staged.exists()) await staged.delete();
        final stagedAttachmentsDir = Directory(stagedAttachmentsPath);
        if (await stagedAttachmentsDir.exists()) {
          await stagedAttachmentsDir.delete(recursive: true);
        }
      }
      rethrow;
    }
  }

  static void _validatePassword(String password) {
    if (password.length < _minimumPasswordLength) {
      throw ArgumentError('كلمة مرور النسخة يجب أن تكون 8 أحرف على الأقل');
    }
  }

  static Uint8List _deriveKey(String password, List<int> salt) {
    var digest = sha256.convert([...utf8.encode(password), ...salt]).bytes;
    for (var i = 0; i < 100000; i++) {
      digest = sha256.convert([...digest, ...salt]).bytes;
    }
    return Uint8List.fromList(digest);
  }

  static List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => Random.secure().nextInt(256));

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
