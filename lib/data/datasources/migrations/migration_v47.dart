import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v47 — Add employee_id column to vouchers table
///
/// This allows vouchers to be directly linked to employees (similar to
/// customer_id and supplier_id), enabling the employee detail screen
/// to find vouchers created for specific employees.
class MigrationV47 {
  static Future<void> migrate(Database db) async {
    await db.execute(
        'ALTER TABLE vouchers ADD COLUMN employee_id INTEGER REFERENCES employees (id)');
  }
}
