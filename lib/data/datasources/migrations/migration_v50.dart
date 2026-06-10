import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v50 — Fix balance_type='auto' in accounts table
///
/// Some accounts may have been created with `balance_type = 'auto'` which
/// is not a valid value.  This migration resolves all 'auto' values to
/// their correct balance_type based on `account_type`:
///
/// - LIABILITY, EQUITY, REVENUE → 'credit'
/// - ASSET, COST, EXPENSE       → 'debit'
class MigrationV50 {
  static Future<void> migrate(Database db) async {
    // Credit-nature accounts: liability, equity, revenue
    await db.execute('''
      UPDATE accounts
      SET balance_type = 'credit'
      WHERE balance_type = 'auto'
        AND account_type IN ('LIABILITY', 'EQUITY', 'REVENUE')
    ''');

    // Debit-nature accounts: asset, cost, expense
    await db.execute('''
      UPDATE accounts
      SET balance_type = 'debit'
      WHERE balance_type = 'auto'
        AND account_type IN ('ASSET', 'COST', 'EXPENSE')
    ''');

    // Safety net: any remaining 'auto' that didn't match known types
    // default to 'debit' (the more conservative choice).
    await db.execute('''
      UPDATE accounts
      SET balance_type = 'debit'
      WHERE balance_type = 'auto'
    ''');
  }
}
