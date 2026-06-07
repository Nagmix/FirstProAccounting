import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v46: Add accounting integrity columns to transactions table.
///
/// Adds:
/// - `currency_code` TEXT: The currency in which the transaction was recorded
///   (e.g., 'YER', 'SAR', 'USD'). Enables multi-currency reporting without
///   joining to the accounts table.
/// - `exchange_rate` REAL: The exchange rate at the time of the transaction,
///   relative to the base currency (YER). Default 1.0. Enables historical
///   currency revaluation and accurate base-currency reporting.
/// - `reference_type` TEXT: The type of source document (e.g., 'invoice',
///   'expense', 'voucher', 'opening_balance', 'currency_exchange', etc.).
///   Replaces LIKE matching on description text for audit trails.
/// - `reference_id` TEXT: The ID of the source document. Together with
///   reference_type, provides a hard link for audit trail.
///
/// These columns address issues identified in the accounting audit:
/// - Missing historical exchange rates for currency revaluation
/// - No way to link transactions to source documents programmatically
/// - Audit trail relies on LIKE matching on description text
class MigrationV46 {
  static Future<void> migrate(Database db) async {
    // Add currency_code column
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN currency_code TEXT',
    );

    // Add exchange_rate column (default 1.0 = no conversion needed)
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0',
    );

    // Add reference_type column
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN reference_type TEXT',
    );

    // Add reference_id column
    await db.execute(
      'ALTER TABLE transactions ADD COLUMN reference_id TEXT',
    );

    // Backfill currency_code from accounts table for existing transactions
    await db.execute('''
      UPDATE transactions
      SET currency_code = (
        SELECT a.currency FROM accounts a WHERE a.id = transactions.account_id
      )
      WHERE currency_code IS NULL
    ''');

    // Create indexes for the new columns
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_currency ON transactions (currency_code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_reference ON transactions (reference_type, reference_id)',
    );
  }
}
