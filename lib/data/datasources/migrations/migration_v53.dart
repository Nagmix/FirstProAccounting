import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v53 — Add default_currency to settings table for legacy compatibility.
class MigrationV53 {
  static Future<void> migrate(Database db) async {
    await db.insert(
      'settings',
      {
        'key': 'default_currency',
        'value': 'YER',
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
