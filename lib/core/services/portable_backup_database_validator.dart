import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

import 'package:firstpro/core/services/portable_backup_compatibility.dart';

typedef PortableBackupDatabaseOpener =
    Future<sqflite.Database> Function(String path, String key);

class PortableBackupDatabaseValidator {
  const PortableBackupDatabaseValidator._();

  static Future<void> validate({
    required String path,
    required String key,
    required PortableBackupDatabaseOpener openDatabase,
  }) async {
    sqflite.Database? database;
    try {
      database = await openDatabase(path, key);
      final versionRows = await database.rawQuery('PRAGMA user_version');
      final schemaVersion = versionRows.isNotEmpty
          ? (versionRows.first.values.first as num?)?.toInt() ?? 0
          : 0;
      PortableBackupCompatibility.validateSchemaVersion(schemaVersion);

      final integrityRows = await database.rawQuery('PRAGMA integrity_check');
      final integrity = integrityRows.isNotEmpty
          ? integrityRows.first.values.first.toString().toLowerCase()
          : '';
      if (integrity != 'ok') {
        throw const FormatException('قاعدة النسخة المحمولة تالفة');
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('قاعدة النسخة المحمولة غير صالحة');
    } finally {
      if (database != null) await database.close();
    }
  }
}
