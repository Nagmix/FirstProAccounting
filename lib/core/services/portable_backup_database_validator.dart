import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

typedef PortableBackupDatabaseOpener =
    Future<sqflite.Database> Function(String path, String key);

class PortableBackupDatabaseValidator {
  const PortableBackupDatabaseValidator._();

  static Future<void> validate({
    required String path,
    required String key,
    required PortableBackupDatabaseOpener openDatabase,
  }) {
    throw UnimplementedError('Staged database validation is not implemented.');
  }
}
