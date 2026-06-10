import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v49 — Currency integrity and base-amount tracking
///
/// 1. Adds `amount_base INTEGER DEFAULT 0` to transactions table
///    for storing the base-currency (YER) equivalent of each transaction.
///    This enables accurate cross-currency reporting without runtime
///    conversion lookups.
///
/// 2. Adds `exchange_rate REAL DEFAULT 1.0` to vouchers table
///    for proper FX tracking on voucher operations.
///
/// 3. Backfills NULL `currency_code` values in transactions to 'YER'
///    as the default currency, ensuring data consistency.
///
/// 4. Updates schema consistency: ensures `currency_code` has a default
///    of 'YER' for new records (the Dart code now always sets it).
class MigrationV49 {
  static Future<void> migrate(Database db) async {
    // 1. Add amount_base column to transactions
    final txColumns = await db.rawQuery('PRAGMA table_info(transactions)');
    final hasAmountBase = txColumns.any((col) => col['name'] == 'amount_base');

    if (!hasAmountBase) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN amount_base INTEGER NOT NULL DEFAULT 0',
      );
    }

    // 2. Add exchange_rate column to vouchers (if missing)
    final vColumns = await db.rawQuery('PRAGMA table_info(vouchers)');
    final hasVoucherExchangeRate =
        vColumns.any((col) => col['name'] == 'exchange_rate');

    if (!hasVoucherExchangeRate) {
      await db.execute(
        'ALTER TABLE vouchers ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0',
      );
    }

    // 3. Backfill NULL currency_code in transactions to 'YER'
    // This ensures all existing records have a valid currency code.
    await db.execute(
      "UPDATE transactions SET currency_code = 'YER' WHERE currency_code IS NULL",
    );

    // 4. Backfill amount_base for existing transactions
    // For records where amount_base is 0 but we have currency_code,
    // compute the base amount using the exchange_rate.
    // If currency_code = 'YER', amount_base = debit or credit.
    // If currency_code != 'YER', amount_base = round(debit/credit * exchange_rate).
    await db.execute('''
      UPDATE transactions
      SET amount_base = CASE
        WHEN currency_code = 'YER' OR currency_code IS NULL THEN
          CASE WHEN debit > 0 THEN debit ELSE credit END
        ELSE
          CAST(ROUND(
            CASE WHEN debit > 0 THEN debit ELSE credit END
            * exchange_rate
          ) AS INTEGER)
      END
      WHERE amount_base = 0
        AND (debit > 0 OR credit > 0)
    ''');

    // 5. Backfill exchange_rate for vouchers based on their currency
    await db.execute('''
      UPDATE vouchers
      SET exchange_rate = COALESCE(
        (SELECT c.exchange_rate FROM currencies c WHERE c.code = vouchers.currency),
        1.0
      )
      WHERE exchange_rate = 1.0
        AND currency != 'YER'
    ''');

    // 6. Create index on amount_base for fast base-currency queries
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_amount_base ON transactions (amount_base)',
      );
    } catch (_) {
      // Index may already exist, ignore
    }
  }
}
