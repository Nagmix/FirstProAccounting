import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v52 — Add vat_rate to currencies table for per-currency VAT configuration.
class MigrationV52 {
  static Future<void> migrate(Database db) async {
    // 1. Add vat_rate column to currencies table
    await db.execute(
      'ALTER TABLE currencies ADD COLUMN vat_rate REAL NOT NULL DEFAULT 0.0',
    );

    // 2. Set known VAT rates for default currencies (user can change later)
    // Yemen (YER): no VAT → 0.0
    // Saudi Arabia (SAR): 15% VAT
    // USA (USD): no federal VAT (varies by state, default 0.0)
    await db.update(
      'currencies',
      {'vat_rate': 15.0},
      where: "code = 'SAR'",
    );

    // 3. Record default_vat_rate in settings for legacy compatibility
    await db.insert(
      'settings',
      {
        'key': 'default_vat_rate',
        'value': '0.0',
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
