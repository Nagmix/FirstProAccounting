import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v48 — Ensure employee_id column exists in vouchers table
///
/// This is a safety net for databases that were created fresh at version 47
/// where the onCreate method created the vouchers table WITHOUT the
/// employee_id column (since the schema CREATE TABLE was missing it).
/// Migration v47 only ran for upgrades from v46, so fresh installs at v47
/// never got the column. This migration ensures the column exists regardless.
class MigrationV48 {
  static Future<void> migrate(Database db) async {
    // Check if employee_id column already exists before trying to add it
    final columns = await db.rawQuery('PRAGMA table_info(vouchers)');
    final hasEmployeeId = columns.any((col) => col['name'] == 'employee_id');

    if (!hasEmployeeId) {
      await db.execute(
        'ALTER TABLE vouchers ADD COLUMN employee_id INTEGER REFERENCES employees (id)',
      );
    }

    // Also ensure the index exists
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_vouchers_employee_id ON vouchers (employee_id)',
      );
    } catch (_) {
      // Index may already exist, ignore
    }
  }
}
