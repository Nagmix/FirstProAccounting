import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v45: Create expense_sub_accounts table and add
/// expense_sub_account_id column to expenses table.
class MigrationV45 {
  static Future<void> migrate(Database db) async {
    // 1. Create expense_sub_accounts table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expense_sub_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        debt_ceiling INTEGER NOT NULL DEFAULT 0,
        phone TEXT,
        contact_method TEXT DEFAULT 'whatsapp',
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 2. Add expense_sub_account_id column to expenses table
    await db.execute(
      'ALTER TABLE expenses ADD COLUMN expense_sub_account_id INTEGER',
    );

    // 3. Create index on the new column in expenses
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_sub_account ON expenses (expense_sub_account_id)',
    );

    // 4. Create index on expense_sub_accounts name
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expense_sub_accounts_name ON expense_sub_accounts (name)',
    );
  }
}
